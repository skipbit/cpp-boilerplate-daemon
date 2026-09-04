# Sanitizers catch what the type system and the warnings cannot: use-after-free,
# undefined behaviour, data races. They are off by default because they slow the
# build and the binary down; nightly-sanitizer.yml turns them on.
#
# Usage:
#   include(Sanitizers)
#   cppbp_set_sanitizers(mylib PRIVATE)
#
# A sanitized library is not a drop-in replacement for an unsanitized one:
# anything that links it has to be built the same way, or the sanitizer runtime
# calls compiled into it resolve to nothing. cppbp_sanitizer_flags() exists so
# that a test which builds a separate consumer can ask what those flags were.

# Declared here rather than in each project's CMakeLists.txt, because this module
# is what reads them. An option nobody declares still works from the command
# line, but it is absent from `cmake -LAH` and from ccmake, so the only way to
# find out it exists is to read the source.
option(CPPBP_SANITIZE_ADDRESS   "Build with AddressSanitizer" OFF)
option(CPPBP_SANITIZE_UNDEFINED "Build with UndefinedBehaviorSanitizer" OFF)
option(CPPBP_SANITIZE_THREAD    "Build with ThreadSanitizer" OFF)
option(CPPBP_SANITIZE_MEMORY    "Build with MemorySanitizer" OFF)

# Writes the flags implied by the CPPBP_SANITIZE_* options into out_var, or an
# empty string when none are on. Both compiling and linking need them.
function(cppbp_sanitizer_flags out_var)
    if(MSVC)
        if(CPPBP_SANITIZE_ADDRESS)
            set(${out_var} /fsanitize=address PARENT_SCOPE)
        else()
            set(${out_var} "" PARENT_SCOPE)
        endif()
        return()
    endif()

    set(enabled "")
    if(CPPBP_SANITIZE_ADDRESS)
        list(APPEND enabled address)
    endif()
    if(CPPBP_SANITIZE_UNDEFINED)
        list(APPEND enabled undefined)
    endif()
    if(CPPBP_SANITIZE_THREAD)
        list(APPEND enabled thread)
    endif()
    if(CPPBP_SANITIZE_MEMORY)
        list(APPEND enabled memory)
    endif()

    if(NOT enabled)
        set(${out_var} "" PARENT_SCOPE)
        return()
    endif()

    # address and thread cannot be combined; fail loudly instead of producing a
    # binary that silently checks less than the author thinks it does.
    if("address" IN_LIST enabled AND "thread" IN_LIST enabled)
        message(FATAL_ERROR "AddressSanitizer and ThreadSanitizer cannot be enabled together")
    endif()
    if("memory" IN_LIST enabled AND ("address" IN_LIST enabled OR "thread" IN_LIST enabled))
        message(FATAL_ERROR "MemorySanitizer cannot be combined with AddressSanitizer or ThreadSanitizer")
    endif()

    list(JOIN enabled "," joined)
    set(${out_var} -fsanitize=${joined} -fno-omit-frame-pointer PARENT_SCOPE)
endfunction()

function(cppbp_set_sanitizers target visibility)
    cppbp_sanitizer_flags(flags)
    if(NOT flags)
        return()
    endif()

    target_compile_options(${target} ${visibility} ${flags})
    if(NOT MSVC)
        target_link_options(${target} ${visibility} ${flags})
    endif()
endfunction()
