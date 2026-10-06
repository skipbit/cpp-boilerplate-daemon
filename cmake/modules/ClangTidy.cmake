# clang-tidy runs as part of the compile step, so a violation fails the build the
# same way a compile error does. It is opt-in: a contributor without clang-tidy
# installed can still build, while the tidy preset and CI always turn it on.

option(CPPBP_ENABLE_CLANG_TIDY "Run clang-tidy as part of the compile step" OFF)

# Defined either way, so that a CMakeLists.txt can call it unconditionally.
if(NOT CPPBP_ENABLE_CLANG_TIDY)
    function(cppbp_enable_clang_tidy target)
    endfunction()
    return()
endif()

# clang-tidy reads the compiler flags out of the build it is attached to, and it
# understands clang's. Attached to a GCC build it is handed -Wduplicated-cond,
# -Wlogical-op and -Wuseless-cast, which clang has never had, and every single
# file fails with clang-diagnostic-unknown-warning-option before a check has run.
#
# That failure says nothing about the code, so it is refused here with an
# explanation rather than produced four times per file. The tidy preset pins
# clang for this reason; this message is for anyone who turns the option on by
# hand.
if(NOT CMAKE_CXX_COMPILER_ID MATCHES ".*Clang")
    message(FATAL_ERROR
        "CPPBP_ENABLE_CLANG_TIDY needs a Clang build (this one is "
        "${CMAKE_CXX_COMPILER_ID}). clang-tidy reads this build's flags, and the "
        "GCC-only warnings would fail every file as unknown warning options. "
        "Use --preset tidy, or configure with -DCMAKE_CXX_COMPILER=clang++.")
endif()

find_program(CPPBP_CLANG_TIDY_EXE NAMES clang-tidy)

if(NOT CPPBP_CLANG_TIDY_EXE)
    message(FATAL_ERROR "CPPBP_ENABLE_CLANG_TIDY is ON but clang-tidy was not found")
endif()

message(STATUS "clang-tidy: ${CPPBP_CLANG_TIDY_EXE}")

# Per target, like the warnings, and for the same reason: CMAKE_CXX_CLANG_TIDY
# applies to everything in the build tree, and FetchContent puts other people's
# code in the build tree. Analysing GoogleTest produces a hundred and fifty
# findings nobody in this project is going to fix, and they drown the ones that
# matter.
#
# Usage:
#   include(ClangTidy)
#   cppbp_enable_clang_tidy(mylib)
#
# --warnings-as-errors is intentional: a warning nobody has to fix is a warning
# everybody learns to ignore.
function(cppbp_enable_clang_tidy target)
    set_target_properties(${target} PROPERTIES
        CXX_CLANG_TIDY "${CPPBP_CLANG_TIDY_EXE};--warnings-as-errors=*")
endfunction()
