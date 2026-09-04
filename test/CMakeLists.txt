include(TestDependencies)
include(GoogleTest)

# One executable for every test file in the program's library. The library is
# what makes this possible: linking main.cpp here would mean two entry points,
# so a service whose loop lives in main() gets tested by starting it, or not at
# all.
add_executable(mydaemon_test
    options_test.cpp
    service_test.cpp
    task_test.cpp
    unique_fd_test.cpp)
target_link_libraries(mydaemon_test PRIVATE mydaemon_lib GTest::gtest_main)
cppbp_set_warnings(mydaemon_test PRIVATE)
cppbp_set_sanitizers(mydaemon_test PRIVATE)
cppbp_enable_clang_tidy(mydaemon_test)

gtest_discover_tests(mydaemon_test)

# The tests above drive the loop with lambdas. This one starts the real process
# and sends it the signals a service manager sends, which is the only way to
# check the part that is not a function: that the signals are blocked before
# they can kill it, that a stop is taken between two runs, and that the exit
# status a service manager reads is zero.
add_test(NAME mydaemon.answers-signals
    COMMAND "${CMAKE_CURRENT_LIST_DIR}/run-daemon.sh"
            "$<TARGET_FILE:mydaemon>"
            "${CMAKE_CURRENT_BINARY_DIR}/run")

# Longer than it needs, because a sanitizer build is slower than this one.
set_tests_properties(mydaemon.answers-signals PROPERTIES TIMEOUT 120)

# The shared check on cppbp_require_std_feature, which the CMake modules bring
# with them. It is registered by whoever is the top of the build: in this
# repository that is the file that adds every template, so this condition is
# false and nothing here runs twice; in the published copy of this template
# there is no such file, cmake/test is a real directory rather than a symlink,
# and this is what puts the tests in ctest.
if(PROJECT_IS_TOP_LEVEL)
    add_subdirectory("${CMAKE_CURRENT_LIST_DIR}/../cmake/test" cmake-test)
endif()
