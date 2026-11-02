#include "shutdown.hpp"

#include <chrono>
#include <csignal>
#include <thread>
#include <utility>

#include <pthread.h>

#include <gtest/gtest.h>

#include "service.hpp"

// The wait is given an interval and has to end within it - and not before it.
// Both halves are easy to lose. Too long comes from EINTR: any signal the
// process catches ends the poll early, and a running system has no shortage of
// them - a profiler's timer, a debugger, a terminal resuming a stopped process
// - so a wait that asked again for its whole interval would keep postponing the
// next run. Too short comes from rounding: options.cpp rounds an interval up so
// that one too small to express in milliseconds becomes the smallest one there
// is, and a wait that rounds the other way turns that into no wait at all.

namespace {

/// Counted in the handler, so that the test which needs the interruptions to
/// land inside the wait can say whether they did. A function-local static
/// rather than a global, and sig_atomic_t because a handler writes it.
auto interruptions_delivered() -> volatile std::sig_atomic_t&
{
    static volatile std::sig_atomic_t count = 0;
    return count;
}

extern "C" void caught(int /*signal_number*/)
{
    interruptions_delivered() = interruptions_delivered() + 1;
}

/// Catches SIGUSR1 for the length of a test, so that a poll interrupted by one
/// comes back with EINTR. Without SA_RESTART deliberately: with it - which is
/// what a handler installed through signal() gets - the kernel restarts the
/// poll and there is nothing here to measure.
class Interruptions {
public:
    Interruptions()
    {
        struct sigaction handler{};
        handler.sa_handler = caught;
        sigemptyset(&handler.sa_mask);
        EXPECT_EQ(::sigaction(SIGUSR1, &handler, &previous_), 0);
    }

    ~Interruptions()
    {
        EXPECT_EQ(::sigaction(SIGUSR1, &previous_, nullptr), 0);
    }

    Interruptions(const Interruptions&) = delete;
    Interruptions(Interruptions&&) = delete;
    auto operator=(const Interruptions&) -> Interruptions& = delete;
    auto operator=(Interruptions&&) -> Interruptions& = delete;

private:
    struct sigaction previous_{};
};

/// A Watcher blocks the signals a service manager sends and never unblocks
/// them. In the program that is the point; here the thread it did it in
/// outlives the test, and one of those signals is the SIGTERM ctest stops a
/// test with when it runs out of time. Saved before the first Watcher exists,
/// so that what is put back is what was there.
class BlockedSignals {
public:
    BlockedSignals()
    {
        EXPECT_EQ(::pthread_sigmask(SIG_SETMASK, nullptr, &previous_), 0);
    }

    ~BlockedSignals()
    {
        EXPECT_EQ(::pthread_sigmask(SIG_SETMASK, &previous_, nullptr), 0);
    }

    BlockedSignals(const BlockedSignals&) = delete;
    BlockedSignals(BlockedSignals&&) = delete;
    auto operator=(const BlockedSignals&) -> BlockedSignals& = delete;
    auto operator=(BlockedSignals&&) -> BlockedSignals& = delete;

private:
    sigset_t previous_{};
};

/// A thread that is joined however the test leaves - including through the
/// exception Watcher::wait throws, which would otherwise reach ~std::thread
/// while it is still joinable and end the process in std::terminate.
///
/// Not std::jthread, which says this in one word: libc++ 18 is one of the six
/// configurations this is built in, and does not have it.
class JoinedThread {
public:
    explicit JoinedThread(std::thread running)
        : running_{std::move(running)}
    {
    }

    ~JoinedThread()
    {
        if (running_.joinable()) {
            running_.join();
        }
    }

    JoinedThread(const JoinedThread&) = delete;
    JoinedThread(JoinedThread&&) = delete;
    auto operator=(const JoinedThread&) -> JoinedThread& = delete;
    auto operator=(JoinedThread&&) -> JoinedThread& = delete;

private:
    std::thread running_;
};

/// Takes whatever the wait under test did not, so that a signal left pending is
/// not delivered when the mask is restored. SIGTERM ends a process: without
/// this, a failure of the assertion above the call would be reported as a
/// crash, with no assertion text.
void discard_anything_still_pending(mydaemon::shutdown::Watcher& watcher)
{
    static_cast<void>(watcher.wait(std::chrono::milliseconds{0}));
}

}  // namespace

TEST(Watcher, WaitsTheWholeLimitWhenNothingArrives)
{
    const BlockedSignals restored;
    mydaemon::shutdown::Watcher watcher;

    constexpr auto limit = std::chrono::milliseconds{20};

    const auto started = std::chrono::steady_clock::now();
    const auto woke = watcher.wait(limit);
    const auto elapsed = std::chrono::steady_clock::now() - started;

    EXPECT_EQ(woke, mydaemon::service::Wakeup::Timeout);
    EXPECT_GE(elapsed, limit);
}

TEST(Watcher, WaitsTheSmallestIntervalTheOptionsCanProduce)
{
    const BlockedSignals restored;
    mydaemon::shutdown::Watcher watcher;

    // What options.cpp rounds a sub-millisecond interval up to. Polled for zero
    // it is not a wait, and the loop it belongs to is a spin.
    constexpr auto limit = std::chrono::milliseconds{1};

    const auto started = std::chrono::steady_clock::now();
    const auto woke = watcher.wait(limit);
    const auto elapsed = std::chrono::steady_clock::now() - started;

    EXPECT_EQ(woke, mydaemon::service::Wakeup::Timeout);
    EXPECT_GE(elapsed, limit);
}

TEST(Watcher, AnswersAStopThatArrivedBeforeTheWait)
{
    const BlockedSignals restored;
    mydaemon::shutdown::Watcher watcher;

    ASSERT_EQ(::raise(SIGTERM), 0);

    // Short, because a passing wait returns at once: the signal is already
    // pending. The limit is only how long a broken one is given to say so.
    EXPECT_EQ(watcher.wait(std::chrono::milliseconds{500}), mydaemon::service::Wakeup::Stop);
    discard_anything_still_pending(watcher);
}

TEST(Watcher, TellsAReloadFromAStop)
{
    const BlockedSignals restored;
    mydaemon::shutdown::Watcher watcher;

    ASSERT_EQ(::raise(SIGHUP), 0);

    EXPECT_EQ(watcher.wait(std::chrono::milliseconds{500}), mydaemon::service::Wakeup::Reload);
    discard_anything_still_pending(watcher);
}

TEST(Watcher, EndsWithinItsLimitWhileOtherSignalsInterruptIt)
{
    const BlockedSignals restored;
    const Interruptions interrupted;
    mydaemon::shutdown::Watcher watcher;

    constexpr auto limit = std::chrono::milliseconds{600};
    constexpr auto between = std::chrono::milliseconds{80};
    constexpr int interruptions = 5;

    interruptions_delivered() = 0;

    const pthread_t waiting = ::pthread_self();
    const auto started = std::chrono::steady_clock::now();

    // Sent against a fixed schedule rather than by sleeping between sends, so
    // that the last one lands at 400ms on a loaded machine too. Late ones would
    // arrive after the wait had already ended, and this test would pass having
    // interrupted nothing.
    const JoinedThread interrupter{std::thread{[waiting, started, between] {
        for (int sent = 1; sent <= interruptions; ++sent) {
            std::this_thread::sleep_until(started + (between * sent));
            ::pthread_kill(waiting, SIGUSR1);
        }
    }}};

    const auto woke = watcher.wait(limit);
    const auto elapsed = std::chrono::steady_clock::now() - started;

    EXPECT_EQ(woke, mydaemon::service::Wakeup::Timeout);

    const int delivered = interruptions_delivered();
    EXPECT_EQ(delivered, interruptions);

    // The last interruption lands at 400ms, so a wait that started its limit
    // over there cannot end before 1000ms however fast the machine is. Anything
    // under 900 counted the time it had already spent - and leaves a sanitizer
    // build 300ms of room over the 600 a correct wait takes.
    EXPECT_GE(elapsed, limit);
    EXPECT_LT(elapsed, std::chrono::milliseconds{900});
}
