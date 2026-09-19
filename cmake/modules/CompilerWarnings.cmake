# Warnings are the cheapest static analysis available. This module turns them on
# per target, so that dependencies fetched into the build tree are not affected.
#
# GCC and Clang are what the choice below is between, and anything else is given
# the GCC set. This is built and tested on Linux only, so a flag for a third
# compiler would be one nothing here has ever run.
#
# Usage:
#   include(CompilerWarnings)
#   cppbp_set_warnings(mylib PRIVATE)

option(CPPBP_WARNINGS_AS_ERRORS "Turn compiler warnings into errors" OFF)

function(cppbp_set_warnings target visibility)
    set(clang_warnings
        -Wall
        -Wextra              # reasonable and standard
        -Wshadow             # a variable declaration shadows a parent one
        -Wnon-virtual-dtor   # a class with virtual functions has a non-virtual destructor
        -Wold-style-cast     # C-style casts
        -Wcast-align         # potential performance problem casts
        -Wunused
        -Woverloaded-virtual # overloaded (not overridden) virtual function
        -Wpedantic           # non-standard C++ is used
        -Wconversion         # type conversions that may lose data
        -Wsign-conversion
        -Wnull-dereference
        -Wdouble-promotion   # float implicitly promoted to double
        -Wformat=2
        -Wimplicit-fallthrough
    )

    set(gcc_warnings
        ${clang_warnings}
        -Wmisleading-indentation
        -Wduplicated-cond
        -Wduplicated-branches
        -Wlogical-op
        -Wuseless-cast
    )

    if(CMAKE_CXX_COMPILER_ID MATCHES ".*Clang")
        set(warnings ${clang_warnings})
    else()
        set(warnings ${gcc_warnings})
    endif()

    if(CPPBP_WARNINGS_AS_ERRORS)
        list(APPEND warnings -Werror)
    endif()

    target_compile_options(${target} ${visibility} ${warnings})
endfunction()
