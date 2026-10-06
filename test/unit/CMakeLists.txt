# One executable per module, and the link line is half the check.
#
# mydaemon_task_test links mydaemon_task and nothing else. The day task starts
# using a function of another module, this stops linking - which is an answer
# from the build rather than from whoever is reading the includes. That holds
# for what has external linkage; a struct used from a header costs no symbol,
# and scripts/check-module-includes.sh and the include path are what answer for
# those.
#
# A single test executable over the whole program cannot say that: every module
# is on its link line already, so a dependency nobody declared resolves and the
# test passes.
#
# Nor can it for a module that has dependencies of its own: a static library
# carries what it links privately to whoever links it, so mydaemon_shutdown_test has task on
# its link line whether or not shutdown named it. The answer the link line
# gives is a firm one for a leaf, and the include path and
# scripts/check-module-includes.sh are what answer above that.
#
# TEST_PREFIX puts the module in front of every test name, so that ctest output
# and a failing run say which module is wrong without opening the file.
#
# A test that needs something else - a fixture target, a thread library - names
# it in its own target_link_libraries after the call, the way a module with a
# second source file adds it with target_sources.
function(mydaemon_add_unit_test module)
    add_executable(mydaemon_${module}_test ${module}_test.cpp)
    target_link_libraries(mydaemon_${module}_test PRIVATE mydaemon_${module} GTest::gtest_main)
    cppbp_set_warnings(mydaemon_${module}_test PRIVATE)
    cppbp_set_sanitizers(mydaemon_${module}_test PRIVATE)
    cppbp_enable_clang_tidy(mydaemon_${module}_test)
    gtest_discover_tests(mydaemon_${module}_test TEST_PREFIX "${module}.")
endfunction()

mydaemon_add_unit_test(options)
mydaemon_add_unit_test(task)
mydaemon_add_unit_test(unique_fd)

# This one names options as well, and is still a unit test: the loop takes an
# options::Options, so it is part of calling the loop rather than a second thing
# under test. It links only mydaemon_service, which hands options over because
# service declared it PUBLIC.
mydaemon_add_unit_test(service)

# Threads because this test starts one and signals it by hand. mydaemon_shutdown
# links Threads privately and the test framework is meant to be swappable, so
# neither can be relied on to carry it here.
mydaemon_add_unit_test(shutdown)
target_link_libraries(mydaemon_shutdown_test PRIVATE Threads::Threads)
