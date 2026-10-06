# CLI11 is fetched rather than vendored, so that `git clone && cmake` works on a
# machine with nothing installed. Swap this file to change argument parsers:
# nothing else in the tree names CLI11 except the target that links it, and no
# header outside the file that does the parsing includes it.

include(FetchContent)

set(CPPBP_CLI11_TAG "v2.7.2" CACHE STRING "CLI11 git tag to build against")

FetchContent_Declare(
    cli11
    GIT_REPOSITORY https://github.com/CLIUtils/CLI11.git
    GIT_TAG ${CPPBP_CLI11_TAG}
    GIT_SHALLOW TRUE
    SYSTEM               # suppress warnings from third-party headers
    EXCLUDE_FROM_ALL     # do not install CLI11 alongside this project
)

FetchContent_MakeAvailable(cli11)
