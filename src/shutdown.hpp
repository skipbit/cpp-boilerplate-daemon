#pragma once

#include <chrono>

#include "service.hpp"
#include "unique_fd.hpp"

// Where the operating system is allowed in, and the only place. This header
// names none of its types, so nothing that includes it inherits them.

namespace mydaemon::shutdown {

/// Turns the signals a service manager sends into the answer the loop waits for.
///
/// There is no signal handler. The signals are blocked and read from a file
/// descriptor instead, so nothing runs asynchronously, there is no global for a
/// handler to write to, and one wait covers both the next interval and the next
/// signal. A signal that arrives while the work is running stays pending until
/// that wait, which is what lets the run it interrupted finish first.
class Watcher {
public:
    Watcher();

    /// Waits up to `limit` for SIGTERM, SIGINT or SIGHUP.
    [[nodiscard]] auto wait(std::chrono::milliseconds limit) -> service::Wakeup;

private:
    UniqueFd descriptor_;
};

}  // namespace mydaemon::shutdown
