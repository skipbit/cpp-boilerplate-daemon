# GoogleTest is fetched rather than vendored, so that `git clone && cmake` works
# on a machine with nothing installed. Swap this file to change test frameworks:
# nothing else in the tree names GoogleTest except the test targets themselves.

include(FetchContent)

set(CPPBP_GOOGLETEST_TAG "v1.18.0" CACHE STRING "GoogleTest git tag to build against")

FetchContent_Declare(
    googletest
    GIT_REPOSITORY https://github.com/google/googletest.git
    GIT_TAG ${CPPBP_GOOGLETEST_TAG}
    GIT_SHALLOW TRUE
    SYSTEM               # suppress warnings from third-party headers
    EXCLUDE_FROM_ALL     # do not install GoogleTest alongside this project
)

# Windows: link the same CRT as the rest of the build.
set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)

FetchContent_MakeAvailable(googletest)
