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
    // poll counts milliseconds in an int, and reads a negative one as "for
    // ever" - which is what an interval longer than 24 days would become.
    const auto capped = std::min<std::chrono::milliseconds::rep>(limit.count(), std::numeric_limits<int>::max());

    for (;;) {
        pollfd watching{.fd = descriptor_.get(), .events = POLLIN, .revents = 0};
        const int ready = ::poll(&watching, 1, static_cast<int>(capped));
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
