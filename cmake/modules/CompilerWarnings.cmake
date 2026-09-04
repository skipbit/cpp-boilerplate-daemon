# Warnings are the cheapest static analysis available. This module turns them on
# per target, so that dependencies fetched into the build tree are not affected.
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

    set(msvc_warnings
        /W4
        /permissive-
        /w14242 /w14254 /w14263 /w14265 /w14287 /we4289 /w14296
        /w14311 /w14545 /w14546 /w14547 /w14549 /w14555 /w14619
        /w14640 /w14826 /w14905 /w14906 /w14928
    )

    if(MSVC)
        set(warnings ${msvc_warnings})
    elseif(CMAKE_CXX_COMPILER_ID MATCHES ".*Clang")
        set(warnings ${clang_warnings})
    else()
        set(warnings ${gcc_warnings})
    endif()

    if(CPPBP_WARNINGS_AS_ERRORS)
        if(MSVC)
            list(APPEND warnings /WX)
        else()
            list(APPEND warnings -Werror)
        endif()
    endif()

    target_compile_options(${target} ${visibility} ${warnings})
endfunction()
