# The project that puts one question to cppbp_require_std_feature.
#
# It is configured from run-feature-gate.cmake, once per case, and it is a
# separate project rather than a call in the build above because the answer
# under test is a configure that stops: a FATAL_ERROR in the build that is
# running the tests would take the tests down with it.
#
# Nothing here is built. The function's whole job happens at configure time, so
# a case is finished the moment cmake returns.
cmake_minimum_required(VERSION 3.28)

project(feature-gate LANGUAGES CXX)

# Reached the same way a template reaches it, and by the same relative path in
# the monorepo and in a published template: cmake/test sits next to
# cmake/modules in both, because it arrives in the second one as a copy of the
# first.
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_LIST_DIR}/../../modules")
include(StandardLibraryFeatures)

# The check that keeps the rest of this from being a test of nothing.
#
# The interesting cases below turn on which standard library is in front of the
# compiler, and this configure is a separate cmake process that inherits none of
# the flags of the one that started it. Handed the compiler but not
# -stdlib=libc++, it would measure libstdc++ while the build that launched it
# was on libc++ - and the cases would still pass, because the two libraries are
# each missing something and every case is either "something is missing" or
# "something is present". The libc++ half of the matrix would then be checking
# libstdc++ under another name, and would go on passing.
#
# So the library the parent measured is passed in, and this compares it with
# what it measures for itself. A break in the flags between the two is a
# mismatch here rather than a green light on a toolchain nobody ran.
if(NOT CPPBP_STANDARD_LIBRARY STREQUAL "${GATE_EXPECTED_STANDARD_LIBRARY}")
    message(FATAL_ERROR
        "the standard library did not survive the trip into this configure:"
        " the build that launched it measured"
        " '${GATE_EXPECTED_STANDARD_LIBRARY}' and this one measures"
        " '${CPPBP_STANDARD_LIBRARY}'. The compiler and flags are handed over in"
        " run-feature-gate.cmake; until they agree, what is being tested is not"
        " the toolchain that asked for the test.")
endif()

# Printed for the driver, which refuses to judge a case that did not get this
# far. The check above can only speak by stopping, and three of the five cases
# expect a stop - so silence is what a missing check and a working one have in
# common, and this line is the difference.
message(STATUS "feature-gate: standard library agrees (${CPPBP_STANDARD_LIBRARY})")

# The call under test. One argument or two, because the function takes the
# minimum version optionally and the two paths word their failure differently.
if("${GATE_MINIMUM}" STREQUAL "")
    cppbp_require_std_feature("${GATE_MACRO}")
else()
    cppbp_require_std_feature("${GATE_MACRO}" "${GATE_MINIMUM}")
endif()

message(STATUS "feature-gate: ${GATE_MACRO} was accepted")
