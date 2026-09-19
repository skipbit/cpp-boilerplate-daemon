#pragma once

#include <chrono>
#include <cstdint>
#include <functional>
#include <optional>
#include <string_view>

#include "options.hpp"

// The loop: work, wait, work again, until asked to stop. It is the only part of
// the program that decides when the work happens, and it does so without
// knowing what a signal is or what a clock is.

namespace mydaemon::service {

/// Why a wait ended.
enum class Wakeup : std::uint8_t {
    Timeout,
    Stop,
    Reload
};

/// Everything the loop needs from outside itself.
///
/// Declared here rather than where it is implemented, so that the layer which
/// knows about signals depends on this one and not the other way round. That is
/// what keeps every OS type out of this header, and what lets a test drive the
/// loop with lambdas and no process at all.
struct Environment {
    /// Waits up to the given time, or until something is asked of the process.
    std::function<Wakeup(std::chrono::milliseconds)> wait;

    /// Writes one line where the service manager collects it.
    std::function<void(std::string_view)> report;

    /// Reads the configuration again. Empty when it could not be read.
    std::function<std::optional<options::Options>()> reload;
};

void run(options::Options options, const Environment& environment);

}  // namespace mydaemon::service
