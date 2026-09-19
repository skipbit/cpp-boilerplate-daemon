# Runs cppbp_require_std_feature, which nothing else does.
#
# It is the one function this repository offers the code that starts from a
# template, README.md points at it, and the templates deliberately never call it
# - they stay inside what every environment in the matrix provides, so that the
# presets they advertise work on a stock machine. That leaves the function
# checked by hand once and by nothing since: a rename inside it, a message that
# stops naming the preset it offers, an argument check that stops rejecting
# anything, all of them green.
#
# The five tests below cover the three ways it can refuse and the one way it can
# agree, and they name no compiler, no distribution and no standard library.
# That is not tidiness. A test that named an environment would run in one row of
# the matrix, would stop running the day that row was replaced, and would say
# nothing at all when it did - which is the failure this file exists to end, one
# level up.
#
# What lets them avoid naming one: of the twelve features measured in
# docs/standard-library.md, mdspan is provided by libc++ and not libstdc++, and
# stacktrace by libstdc++ and not libc++. Asking for both is therefore one
# success and one refusal on every environment there is, and the assertion is
# "exactly one", which is a sentence about the toolchain rather than a list of
# toolchains.
#
# Registered here rather than under any one template, because the module is
# shared by all four and belongs to none of them. Whoever is the top of the
# build registers it: the monorepo from its own CMakeLists.txt, a published
# template from its test/CMakeLists.txt, and never both.

# Only for CPPBP_STANDARD_LIBRARY, which the module caches. Including it a
# second time is free - it holds a global property and returns - and this is
# what makes the answer available even to a build where the module has not been
# reached yet.
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_LIST_DIR}/../modules")
include(StandardLibraryFeatures)

if(NOT CPPBP_STANDARD_LIBRARY)
    message(FATAL_ERROR
        "StandardLibraryFeatures did not report a standard library, so the"
        " tests below have nothing to compare the nested configures with.")
endif()

# What every case is handed. CMAKE_CXX_FLAGS is where a preset puts
# -stdlib=libc++, and CPPBP_STANDARD_LIBRARY is what this build measured with
# those flags in place - the nested configure re-measures and refuses to
# continue if the two disagree. Dropping either turns the whole file green on a
# toolchain it never ran.
set(cppbp_feature_gate_arguments
    -D "SOURCE_DIR=${CMAKE_CURRENT_LIST_DIR}/feature-gate"
    -D "GENERATOR=${CMAKE_GENERATOR}"
    -D "CXX_COMPILER=${CMAKE_CXX_COMPILER}"
    -D "CXX_FLAGS=${CMAKE_CXX_FLAGS}"
    -D "STANDARD_LIBRARY=${CPPBP_STANDARD_LIBRARY}")

function(cppbp_add_std_feature_gate_test case)
    add_test(NAME "std-feature-gate.${case}"
        COMMAND "${CMAKE_COMMAND}"
                ${cppbp_feature_gate_arguments}
                -D "CASE=${case}"
                -D "WORK_DIR=${CMAKE_CURRENT_BINARY_DIR}/${case}"
                -P "${CMAKE_CURRENT_LIST_DIR}/run-feature-gate.cmake")
endfunction()

# A feature every environment has, so this one is about the function agreeing
# rather than about the toolchain.
cppbp_add_std_feature_gate_test(accepts-what-is-there)

# The first way to refuse: the macro is not defined anywhere.
cppbp_add_std_feature_gate_test(stops-on-what-is-not)

# The second, which the diagnostic tells apart from the first: defined, and
# older than what was asked for.
cppbp_add_std_feature_gate_test(stops-on-a-version-nobody-has)

# The third, which happens before anything is compiled: the argument was not a
# feature test macro at all.
cppbp_add_std_feature_gate_test(refuses-a-name-that-is-not-one)

# And the one that puts the repository's own claim about C++23 to a machine:
# whichever standard library is here, it has exactly one of two features.
cppbp_add_std_feature_gate_test(tells-the-two-libraries-apart)
