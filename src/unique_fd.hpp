#pragma once

#include <utility>

// A file descriptor is an owned resource behind a C interface: nothing about an
// int says it has to be closed, and nothing objects when it is closed twice.
// This is the smallest type that hands both of those to the compiler.

namespace mydaemon {

class UniqueFd {
public:
    UniqueFd() = default;

    explicit UniqueFd(int descriptor) noexcept
        : descriptor_(descriptor)
    {
    }

    UniqueFd(const UniqueFd&) = delete;
    auto operator=(const UniqueFd&) -> UniqueFd& = delete;

    UniqueFd(UniqueFd&& other) noexcept
        : descriptor_(std::exchange(other.descriptor_, closed))
    {
    }

    auto operator=(UniqueFd&& other) noexcept -> UniqueFd&
    {
        if (this != &other) {
            close_now();
            descriptor_ = std::exchange(other.descriptor_, closed);
        }
        return *this;
    }

    ~UniqueFd()
    {
        close_now();
    }

    [[nodiscard]] auto get() const noexcept -> int
    {
        return descriptor_;
    }

    [[nodiscard]] auto valid() const noexcept -> bool
    {
        return descriptor_ != closed;
    }

private:
    static constexpr int closed = -1;

    void close_now() noexcept;

    int descriptor_ = closed;
};

}  // namespace mydaemon
