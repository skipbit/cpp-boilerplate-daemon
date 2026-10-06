# Where a test goes when it needs more than one module and no process.
#
# This template ships none, and the reason is a fact about this program rather
# than an omission. Every pair of modules here is either part of one module's
# interface - shutdown::Watcher::wait returns a service::Wakeup, so a test of
# the watcher is a test of one module - or hidden inside an implementation:
# service calls task and says so in no header, so no test can reach it. The one
# place all three are assembled is main(), which is not in a library. e2e/ is
# what checks that wiring.
#
# Your service will have somewhere they meet that is not main() - a module that
# owns the loop and the signals together, a pipeline assembled from parts - and
# that is what belongs here:
#
#   add_executable(mydaemon_integration_test loop_test.cpp)
#   target_link_libraries(mydaemon_integration_test
#       PRIVATE mydaemon_shutdown mydaemon_task Threads::Threads GTest::gtest_main)
#   cppbp_set_warnings(mydaemon_integration_test PRIVATE)
#   cppbp_set_sanitizers(mydaemon_integration_test PRIVATE)
#   cppbp_enable_clang_tidy(mydaemon_integration_test)
#   gtest_discover_tests(mydaemon_integration_test TEST_PREFIX "integration.")
#
# The directory is here rather than added when it is first needed, because a
# level that has to be invented under pressure is a level that gets skipped: the
# test ends up in unit/ linking three modules, or in e2e/ starting a process to
# check something that is not about processes.
