# Whether the standard library in front of this compiler has a feature.
#
# "C++23" is not one thing, and not one thing per compiler either: it is a
# compiler and a standard library, and the two disagree. Measured with
# -std=gnu++23 on stock toolchains, Ubuntu 24.04 and 26.04:
#
#                              24.04                      26.04
#                     GCC 13   Clang    Clang    GCC 15   Clang    Clang
#                             +stdc++    +c++            +stdc++    +c++
#   std::expected      yes       NO      yes      yes      yes      yes
#   std::print          NO       NO      yes      yes      yes      yes
#   std::mdspan         NO       NO      yes       NO       NO      yes
#   std::stacktrace    yes      yes       NO      yes      yes       NO
#   std::views::zip    yes      yes       NO      yes      yes       NO
#
# The two libraries are missing different things, and 26.04 does not fix that -
# so no choice of supported set makes the problem go away. It moves.
#
# One command:
#
#   cppbp_require_std_feature(__cpp_lib_expected 202202)
#   cppbp_require_std_feature(__cpp_lib_expected)          # any version of it
#
# Put it next to the code that needs the feature. Configuration then stops on
# the environments that do not have it, naming the environment and the way out,
# instead of a compile error a hundred lines into a build or in somebody else's
# clone of your repository.
#
# The argument is the feature test macro from the standard, not a name this
# project made up. The standard already keeps that list, cppreference already
# publishes it, and a list kept here could only ever be a worse copy that
# answers "why is your feature not in it" with "nobody added it yet".
#
# The code this template ships calls none of this. It stays inside what every
# environment above provides, so the presets it advertises work on a stock
# machine. This is for the code that replaces it - and because nothing calls it,
# cmake/test does: ctest puts the function to whatever toolchain is building, in
# each of the three ways it can refuse and the one way it can agree.
# docs/standard-library.md has the table and the reasoning.

include_guard(GLOBAL)

# include_guard() alone does not hold here: the monorepo reaches this file
# through a per-template symlink, so each template includes it under a different
# path and the guard sees two different files. A global property is keyed by
# nothing but itself.
get_property(cppbp_std_features_done GLOBAL PROPERTY CPPBP_STD_FEATURES_DONE)
if(cppbp_std_features_done)
    return()
endif()
set_property(GLOBAL PROPERTY CPPBP_STD_FEATURES_DONE TRUE)

include(CheckCXXSourceCompiles)

# Which library. For the diagnostics only - every decision below is a compile.
block(SCOPE_FOR VARIABLES)
    set(CMAKE_CXX_STANDARD 23)
    set(CMAKE_CXX_STANDARD_REQUIRED ON)

    check_cxx_source_compiles("
        #include <version>
        #ifndef __GLIBCXX__
        #error not libstdc++
        #endif
        int main() {}
    " CPPBP_STANDARD_LIBRARY_IS_LIBSTDCXX)

    check_cxx_source_compiles("
        #include <version>
        #ifndef _LIBCPP_VERSION
        #error not libc++
        #endif
        int main() {}
    " CPPBP_STANDARD_LIBRARY_IS_LIBCXX)
endblock()

# Cached rather than set here: the guard above means the second template to
# include this file gets none of it, so anything a later scope reads has to
# outlive this one.
if(CPPBP_STANDARD_LIBRARY_IS_LIBSTDCXX)
    set(CPPBP_STANDARD_LIBRARY "libstdc++" CACHE INTERNAL "The C++ standard library in use")
elseif(CPPBP_STANDARD_LIBRARY_IS_LIBCXX)
    set(CPPBP_STANDARD_LIBRARY "libc++" CACHE INTERNAL "The C++ standard library in use")
else()
    set(CPPBP_STANDARD_LIBRARY "unrecognised" CACHE INTERNAL "The C++ standard library in use")
endif()

message(STATUS
    "Standard library: ${CPPBP_STANDARD_LIBRARY}"
    " (${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION})")

# Refuses to configure unless <version> reports the feature.
#
# The macro is read rather than the type used, because the two agree: where a
# feature is absent the macro is undefined, including the case where the header
# exists and its contents are switched off. Measured on all six environments
# above - <expected> is present and empty under clang 18 with libstdc++, and
# __cpp_lib_expected is undefined there too.
function(cppbp_require_std_feature macro)
    if(NOT macro MATCHES "^__cpp")
        message(FATAL_ERROR
            "cppbp_require_std_feature(${macro}): expected a feature test macro,"
            " for example __cpp_lib_expected. The names are the standard's;"
            " cppreference lists them next to each feature.")
    endif()

    set(minimum "${ARGV1}")
    if(minimum STREQUAL "")
        set(condition "!defined(${macro})")
        set(wanted "defined")
    else()
        set(condition "!defined(${macro}) || ${macro} < ${minimum}")
        set(wanted "${minimum} or newer")
    endif()

    # The standard has to be set here, and to what the templates ask of their
    # targets: this project sets it per target with target_compile_features, and
    # check_cxx_source_compiles knows nothing about targets, so left alone it
    # compiles with the compiler's default and reads a <version> from the wrong
    # standard.
    set(CMAKE_CXX_STANDARD 23)
    set(CMAKE_CXX_STANDARD_REQUIRED ON)

    string(MAKE_C_IDENTIFIER "CPPBP_HAVE_${macro}_${minimum}" cached)
    check_cxx_source_compiles("
        #include <version>
        #if ${condition}
        #error feature not available
        #endif
        int main() {}
    " ${cached})

    if(${cached})
        message(STATUS "  ${macro}: ${wanted} - yes")
        return()
    endif()

    # Two ways to fail, and they are worth telling apart: a library that has
    # never had the feature, and one whose version of it is older than asked for.
    string(MAKE_C_IDENTIFIER "CPPBP_DEFINES_${macro}" defined_at_all)
    check_cxx_source_compiles("
        #include <version>
        #if !defined(${macro})
        #error not defined
        #endif
        int main() {}
    " ${defined_at_all})

    if(${defined_at_all})
        set(found "it is defined, but older than ${minimum}")
    else()
        set(found "it is not defined at all")
    endif()

    # Printed rather than passed to FATAL_ERROR, which rewraps what it is given
    # and would turn the commands below into prose. The point of naming a preset
    # is that it can be copied.
    message(NOTICE "
This toolchain does not provide ${macro} (${wanted}).

  compiler:         ${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION}
  standard library: ${CPPBP_STANDARD_LIBRARY}
  <version> says:   ${found}

The two standard libraries are missing different things, so the answer depends
on which feature this is. Both of these are worth trying:

  cmake --preset clang-libc++     clang against libc++
  cmake --preset debug            the default compiler

or drop the requirement: remove
  cppbp_require_std_feature(${macro} ${minimum})
from CMakeLists.txt, and do not use the feature.

docs/standard-library.md has the measurements.
")
    message(FATAL_ERROR "${macro} is missing from this toolchain; see above.")
endfunction()
