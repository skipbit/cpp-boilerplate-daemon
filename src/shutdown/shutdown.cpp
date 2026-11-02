#include "shutdown.hpp"

#include <algorithm>
#include <cerrno>
#include <chrono>
#include <csignal>
#include <limits>
#include <system_error>

#include <poll.h>
#include <sys/signalfd.h>
#include <sys/types.h>
#include <unistd.h>

#include "service.hpp"
#include "unique_fd.hpp"

namespace mydaemon::shutdown {

namespace {

auto watched() -> sigset_t
{
    sigset_t set{};
    sigemptyset(&set);
    sigaddset(&set, SIGTERM);
    sigaddset(&set, SIGINT);
    sigaddset(&set, SIGHUP);
    return set;
}

// Rounded up, for the reason options.cpp rounds the interval up: what is left
// of a wait must not become nothing until it has actually run out, or the
// smallest interval the options can produce - one millisecond - is polled for
// zero and the loop spins. Written out rather than with std::chrono::ceil,
// which clang-tidy 18 reports as a symbol no included header provides.
//
// poll counts milliseconds in an int and reads a negative one as "for ever",
// so both ends are clamped.
auto milliseconds_until(std::chrono::steady_clock::time_point deadline) -> int
{
    const auto left = deadline - std::chrono::steady_clock::now();
    auto whole = std::chrono::duration_cast<std::chrono::milliseconds>(left);
    if (whole < left) {
        whole += std::chrono::milliseconds{1};
    }
    const auto capped = std::clamp<std::chrono::milliseconds::rep>(whole.count(), 0, std::numeric_limits<int>::max());
    return static_cast<int>(capped);
}

}  // namespace

Watcher::Watcher()
{
    const sigset_t wanted = watched();

    // Blocked before the descriptor exists, so nothing is delivered the old way
    // in between. pthread_sigmask rather than sigprocmask: what the latter does
    // in a process with more than one thread is unspecified, and doing it here,
    // before any thread exists, is what makes every later thread inherit it.
    if (const int failure = pthread_sigmask(SIG_BLOCK, &wanted, nullptr); failure != 0) {
        throw std::system_error(failure, std::generic_category(), "blocking the signals this process answers");
    }

    descriptor_ = UniqueFd{signalfd(-1, &wanted, SFD_CLOEXEC)};
    if (! descriptor_.valid()) {
        throw std::system_error(errno, std::generic_category(), "opening a descriptor to read signals from");
    }
}

auto Watcher::wait(std::chrono::milliseconds limit) -> service::Wakeup
{
    // Capped before it becomes a point in time, because steady_clock counts
    // nanoseconds: an interval of more than about 292 years overflows the
    // addition rather than producing a distant deadline, and poll cannot be
    // asked for more than INT_MAX milliseconds anyway.
    const auto capped = std::chrono::milliseconds{
        std::min<std::chrono::milliseconds::rep>(limit.count(), std::numeric_limits<int>::max())};

    // A deadline rather than the interval itself. A signal this does not watch
    // for ends the poll below with EINTR, and asking again for the interval
    // would start the wait over every time one arrived - so a process being
    // profiled, or stopped and continued, would never reach its next run.
    const auto deadline = std::chrono::steady_clock::now() + capped;

    for (;;) {
        pollfd watching{.fd = descriptor_.get(), .events = POLLIN, .revents = 0};
        const int ready = ::poll(&watching, 1, milliseconds_until(deadline));
        if (ready > 0) {
            break;
        }
        if (ready == 0) {
            return service::Wakeup::Timeout;
        }
        if (errno != EINTR) {
            throw std::system_error(errno, std::generic_category(), "waiting for a signal");
        }
    }

    signalfd_siginfo received{};
    if (::read(descriptor_.get(), &received, sizeof received) != static_cast<ssize_t>(sizeof received)) {
        throw std::system_error(errno, std::generic_category(), "reading a signal");
    }

    return received.ssi_signo == SIGHUP ? service::Wakeup::Reload : service::Wakeup::Stop;
}

}  // namespace mydaemon::shutdown
