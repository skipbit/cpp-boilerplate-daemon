#include "task.hpp"

#include <string>
#include <string_view>

namespace mydaemon::task {

auto run(const State& before, std::string_view label) -> Result
{
    const State state{.runs = before.runs + 1};

    std::string line;
    if (! label.empty()) {
        line += label;
        line += ' ';
    }
    line += "run ";
    line += std::to_string(state.runs);

    return {.state = state, .line = line};
}

}  // namespace mydaemon::task
