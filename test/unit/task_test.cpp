#include "task.hpp"

#include <gtest/gtest.h>

// The work takes its state as an argument and hands it back, so a hundred runs
// of it cost nothing and wait for nothing.

TEST(Task, CountsItsRunsFromOne)
{
    const auto first = mydaemon::task::run({}, "watch");
    EXPECT_EQ(first.state.runs, 1U);
    EXPECT_EQ(first.line, "watch run 1");
}

TEST(Task, CarriesTheCountForward)
{
    mydaemon::task::State state;
    for (int run = 0; run < 100; ++run) {
        state = mydaemon::task::run(state, "watch").state;
    }
    EXPECT_EQ(state.runs, 100U);
}

TEST(Task, LeavesNoStraySpaceWhenThereIsNoLabel)
{
    EXPECT_EQ(mydaemon::task::run({}, "").line, "run 1");
}
