#pragma once

#include <cstdint>
#include <string>
#include <string_view>

// The work itself. It knows nothing about signals, sleeping or the process it
// runs in, which is what makes it the easiest thing here to test.

namespace mydaemon::task {

/// What one run carries to the next. The loop holds it and hands it back, so a
/// test can run a thousand runs without waiting for a thousand intervals.
struct State {
    std::uint64_t runs = 0;
};

struct Result {
    State state;
    std::string line;
};

/// One run of the work, and the line it wants written. Replace it with yours.
[[nodiscard]] auto run(const State& before, std::string_view label) -> Result;

}  // namespace mydaemon::task
