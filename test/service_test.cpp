#include "service.hpp"

#include <chrono>
#include <cstddef>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include <gtest/gtest.h>

#include "options.hpp"

// The loop is driven here by lambdas rather than by a clock and a signal, which
// is the whole reason Environment exists. None of these tests waits for an
// interval, and none of them starts a process.

namespace {

using mydaemon::service::Wakeup;

// No test here reaches a real wait, so the interval only has to be a value.
constexpr auto any_interval = std::chrono::hours{1};

struct Script {
    std::vector<Wakeup> wakeups;
    std::optional<mydaemon::options::Options> on_reload;
    std::vector<std::string> reported;
    std::size_t waits = 0;

    auto environment() -> mydaemon::service::Environment
    {
        return {
            .wait =
                [this](std::chrono::milliseconds) {
                    return wakeups.at(waits++);
                },
            .report =
                [this](std::string_view line) {
                    reported.emplace_back(line);
                },
            .reload =
                [this] {
                    return on_reload;
                },
        };
    }
};

auto every(std::chrono::milliseconds interval, std::string label) -> mydaemon::options::Options
{
    return {.interval = interval, .label = std::move(label)};
}

}  // namespace

TEST(Run, WorksOnceBeforeItWaitsAtAll)
{
    // A service that does nothing for its first interval looks broken for its
    // first interval.
    Script script;
    script.wakeups = {Wakeup::Stop};
    mydaemon::service::run(every(any_interval, "watch"), script.environment());

    EXPECT_EQ(script.waits, 1U);
    EXPECT_EQ(script.reported, (std::vector<std::string>{"watch run 1", "stopping"}));
}

TEST(Run, FinishesTheRunItIsInAndThenStops)
{
    // One line per run, the stop taken between two of them, and nothing after
    // it. A stop noticed inside the work would show up here as a run with no
    // line, or a line after "stopping".
    Script script;
    script.wakeups = {Wakeup::Timeout, Wakeup::Timeout, Wakeup::Stop};
    mydaemon::service::run(every(any_interval, "watch"), script.environment());

    EXPECT_EQ(script.reported, (std::vector<std::string>{"watch run 1", "watch run 2", "watch run 3", "stopping"}));
}

TEST(Run, UsesTheConfigurationItWasHandedOnReload)
{
    Script script;
    script.wakeups = {Wakeup::Reload, Wakeup::Stop};
    script.on_reload = every(any_interval, "reloaded");
    mydaemon::service::run(every(any_interval, "original"), script.environment());

    ASSERT_EQ(script.reported.size(), 4U);
    EXPECT_EQ(script.reported.at(0), "original run 1");
    EXPECT_EQ(script.reported.at(2), "reloaded run 2");
}

TEST(Run, KeepsRunningWhenTheConfigurationCannotBeRead)
{
    // The old configuration is known to work, because it is the one running.
    // Stopping a healthy service over a typo in a file is a worse answer.
    Script script;
    script.wakeups = {Wakeup::Reload, Wakeup::Stop};
    mydaemon::service::run(every(any_interval, "original"), script.environment());

    ASSERT_EQ(script.reported.size(), 4U);
    EXPECT_EQ(script.reported.at(2), "original run 2");
}
