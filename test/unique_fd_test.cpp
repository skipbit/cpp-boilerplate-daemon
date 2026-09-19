#include "unique_fd.hpp"

#include <utility>

#include <unistd.h>

#include <gtest/gtest.h>

// A leaked descriptor is invisible until a long-running process runs out of
// them, which is the worst moment to find out. So these tests ask the question
// a leak would answer wrongly: is it closed?

namespace {

auto borrowed_descriptor() -> int
{
    return ::dup(STDERR_FILENO);
}

auto is_open(int descriptor) -> bool
{
    // A closed descriptor cannot be duplicated, and neither can one that was
    // never opened - which is what borrowing one returns when it fails.
    if (descriptor < 0) {
        return false;
    }
    const mydaemon::UniqueFd copy{::dup(descriptor)};
    return copy.valid();
}

}  // namespace

TEST(UniqueFd, HoldsNothingUntilItIsGivenSomething)
{
    const mydaemon::UniqueFd empty;
    EXPECT_FALSE(empty.valid());
}

TEST(UniqueFd, ClosesWhatItHoldsWhenItGoesAway)
{
    const int descriptor = borrowed_descriptor();
    ASSERT_TRUE(is_open(descriptor));
    {
        const mydaemon::UniqueFd owner{descriptor};
        EXPECT_TRUE(owner.valid());
    }
    EXPECT_FALSE(is_open(descriptor));
}

TEST(UniqueFd, MovingHandsOverTheOnlyClose)
{
    const int descriptor = borrowed_descriptor();
    mydaemon::UniqueFd first{descriptor};
    {
        const mydaemon::UniqueFd second{std::move(first)};
        EXPECT_EQ(second.get(), descriptor);
    }
    EXPECT_FALSE(is_open(descriptor));

    // The number is free now, so the next descriptor opened takes it back. If
    // the move had left `first` holding it, emptying `first` below would close
    // a descriptor that belongs to somebody else - which is the failure this
    // type exists to make impossible, and the one that asking a moved-from
    // object how it feels does not actually rule out.
    const mydaemon::UniqueFd reused{borrowed_descriptor()};
    ASSERT_EQ(reused.get(), descriptor);
    first = mydaemon::UniqueFd{};
    EXPECT_TRUE(is_open(descriptor));
}

TEST(UniqueFd, AssigningOverOneClosesWhatItHeld)
{
    const int replaced = borrowed_descriptor();
    const int kept = borrowed_descriptor();

    mydaemon::UniqueFd owner{replaced};
    owner = mydaemon::UniqueFd{kept};

    EXPECT_FALSE(is_open(replaced));
    EXPECT_TRUE(is_open(kept));
}
