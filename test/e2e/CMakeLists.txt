# The tests in unit/ drive the loop with lambdas. This one starts the real process
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

# add_test expands the path and checks nothing. In a build directory where only
# a test was built, this would start a program that is not there and fail inside
# it; REQUIRED_FILES makes ctest say NOT RUN instead.
set_tests_properties(mydaemon.answers-signals PROPERTIES
    REQUIRED_FILES "$<TARGET_FILE:mydaemon>")
