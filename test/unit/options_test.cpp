#include "options.hpp"

#include <chrono>
#include <fstream>
#include <ios>
#include <string>
#include <vector>

#include <gtest/gtest.h>

namespace {

auto parse(const std::vector<std::string>& arguments) -> mydaemon::options::Outcome
{
    std::vector<const char*> argv;
    argv.reserve(arguments.size());
    for (const auto& argument : arguments) {
        argv.push_back(argument.c_str());
    }
    return mydaemon::options::parse(static_cast<int>(argv.size()), argv.data());
}

auto write_config(const std::string& name, const std::string& contents) -> std::string
{
    const std::string path = testing::TempDir() + name;
    std::ofstream file(path, std::ios::trunc);
    file << contents;
    return path;
}

}  // namespace

TEST(Parse, HasAnIntervalWithoutBeingGivenOne)
{
    const auto parsed = parse({"mydaemon"});
    ASSERT_TRUE(parsed.run);
    EXPECT_GT(parsed.options.interval, std::chrono::milliseconds{0});
    EXPECT_TRUE(parsed.options.label.empty());
}

TEST(Parse, ReadsTheIntervalInSeconds)
{
    const auto parsed = parse({"mydaemon", "--interval", "0.25"});
    ASSERT_TRUE(parsed.run);
    EXPECT_EQ(parsed.options.interval, std::chrono::milliseconds{250});
}

TEST(Parse, RoundsAnIntervalTooSmallToExpressUpRatherThanAway)
{
    const auto parsed = parse({"mydaemon", "--interval", "0.0001"});
    ASSERT_TRUE(parsed.run);
    EXPECT_EQ(parsed.options.interval, std::chrono::milliseconds{1});
}

TEST(Parse, RefusesAnIntervalOfZero)
{
    const auto parsed = parse({"mydaemon", "--interval", "0"});
    EXPECT_FALSE(parsed.run);
    EXPECT_NE(parsed.status, 0);
}

TEST(Parse, ReportsAnExitCodeForAnUnknownOption)
{
    // The usage message this prints belongs to the run: the parser has already
    // said what was wrong, which is why what comes back here is a status.
    const auto parsed = parse({"mydaemon", "--nonsense"});
    EXPECT_FALSE(parsed.run);
    EXPECT_NE(parsed.status, 0);
}

TEST(Parse, ReadsTheSameOptionsFromAFile)
{
    const auto path = write_config("mydaemon-good.conf", "interval = 0.5\nlabel = \"from the file\"\n");
    const auto parsed = parse({"mydaemon", "--config", path});
    ASSERT_TRUE(parsed.run);
    EXPECT_EQ(parsed.options.interval, std::chrono::milliseconds{500});
    EXPECT_EQ(parsed.options.label, "from the file");
}

TEST(Parse, LetsTheCommandLineWinOverTheFile)
{
    const auto path = write_config("mydaemon-both.conf", "interval = 0.5\n");
    const auto parsed = parse({"mydaemon", "--config", path, "--interval", "0.75"});
    ASSERT_TRUE(parsed.run);
    EXPECT_EQ(parsed.options.interval, std::chrono::milliseconds{750});
}

TEST(Parse, RefusesAFileItCannotUnderstand)
{
    // What the loop does about this is its own decision, and service_test.cpp
    // has it: a configuration that stopped making sense is not a reason to stop
    // a service that is already running with a good one.
    const auto path = write_config("mydaemon-bad.conf", "nonsense = 1\n");
    const auto parsed = parse({"mydaemon", "--config", path});
    EXPECT_FALSE(parsed.run);
    EXPECT_NE(parsed.status, 0);
}
