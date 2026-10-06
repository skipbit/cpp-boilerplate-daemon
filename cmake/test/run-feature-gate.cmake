# Driver for the std-feature-gate tests. Runs in CMake script mode.
#
# One case per invocation, named by CASE. Each one configures the small project
# in feature-gate/ with a different argument for cppbp_require_std_feature, and
# checks both halves of the answer: whether the configure stopped, and whether
# what it printed names the thing it was asked about.
#
# Not WILL_FAIL. That property inverts an exit status and reads nothing else, so
# a configure that died because the generator was missing, or because a module
# moved, would count as the refusal the case was waiting for - and three of the
# five cases here are about a refusal saying something useful, which an exit
# status cannot do. Pairing it with PASS_REGULAR_EXPRESSION does not recover
# that: with an expression set, "the process exit code is ignored", so the two
# together check less than either alone.
#
# What is matched is identifiers - the macro that was passed in, the version
# number that was passed in, the name of the preset the diagnostic offers - and
# never the sentences around them. The wording is meant to be rewritten; the
# names are the contract.

# CXX_FLAGS is not among these: an empty one is an ordinary answer, and the
# check that it arrived intact is not a presence test but the standard library
# comparison inside feature-gate/CMakeLists.txt.
foreach(required IN ITEMS
        CASE SOURCE_DIR WORK_DIR GENERATOR CXX_COMPILER STANDARD_LIBRARY)
    if(NOT DEFINED ${required})
        message(FATAL_ERROR "${required} was not passed to this script")
    endif()
endforeach()

# Configures feature-gate/ once, asking for one feature, and hands back the exit
# status and everything it said.
function(run_gate slot macro minimum result_variable text_variable)
    set(build "${WORK_DIR}/${slot}")

    # A fresh directory every time. check_cxx_source_compiles writes its answer
    # into the cache, so a second run in the same one would read the first run's
    # verdict instead of compiling anything - and the case that expects a
    # refusal would be handed the pass of the case before it.
    file(REMOVE_RECURSE "${build}")

    # The compiler and the flags of the build that registered this test, and
    # nothing else. -stdlib=libc++ lives in CMAKE_CXX_FLAGS, which is why it has
    # to be carried over; sanitizer flags do not, because this project attaches
    # them per target and there is no target here to attach them to. Adding them
    # would mean linking the runtime into a probe that only asks the
    # preprocessor a question.
    execute_process(
        COMMAND "${CMAKE_COMMAND}"
                -S "${SOURCE_DIR}" -B "${build}" -G "${GENERATOR}"
                "-DCMAKE_CXX_COMPILER=${CXX_COMPILER}"
                "-DCMAKE_CXX_FLAGS=${CXX_FLAGS}"
                "-DGATE_EXPECTED_STANDARD_LIBRARY=${STANDARD_LIBRARY}"
                "-DGATE_MACRO=${macro}"
                "-DGATE_MINIMUM=${minimum}"
        RESULT_VARIABLE result
        OUTPUT_VARIABLE out
        ERROR_VARIABLE err)

    # Both streams. The diagnostic under test is printed with message(NOTICE),
    # which goes to standard error, while the STATUS lines around it go to
    # standard output - so either one alone is half of what was said.
    set(text "${out}${err}")

    # Every case, including the ones that expect a refusal. This is the line
    # feature-gate/CMakeLists.txt prints once it has compared its own standard
    # library with the one measured here; without it, either the comparison
    # never ran or it is the reason this configure stopped, and in both cases
    # the verdict below would be about a toolchain nobody asked for.
    string(FIND "${text}" "feature-gate: standard library agrees" agreed)
    if(agreed LESS 0)
        message(FATAL_ERROR
            "${CASE}: the nested configure never reported which standard"
            " library it was using, so nothing below can be trusted."
            " Expected ${STANDARD_LIBRARY}.\n${text}")
    endif()

    set(${result_variable} "${result}" PARENT_SCOPE)
    set(${text_variable} "${text}" PARENT_SCOPE)
endfunction()

function(require_mentions text what)
    string(FIND "${text}" "${what}" found)
    if(found LESS 0)
        message(FATAL_ERROR
            "${CASE}: the configure never mentioned ${what}.\n${text}")
    endif()
endfunction()

function(require_never_mentions text what why)
    string(FIND "${text}" "${what}" found)
    if(NOT found LESS 0)
        message(FATAL_ERROR
            "${CASE}: the configure mentioned ${what}, and ${why}.\n${text}")
    endif()
endfunction()

function(require_stopped result text what)
    if(result EQUAL 0)
        message(FATAL_ERROR
            "${CASE}: configuring succeeded, and ${what}.\n${text}")
    endif()
endfunction()

# The two features this repository measured as being on opposite sides of the
# two standard libraries. Named once, because the case below asks for both and
# says which is which when the answer changes.
set(only_in_libcxx "__cpp_lib_mdspan")
set(only_in_libstdcxx "__cpp_lib_stacktrace")

if(CASE STREQUAL "accepts-what-is-there")
    # C++17, so every environment in the matrix has it and this case is about
    # the function and not about the toolchain.
    run_gate(present "__cpp_lib_optional" "" result text)
    if(NOT result EQUAL 0)
        message(FATAL_ERROR
            "${CASE}: __cpp_lib_optional is C++17 and this configure refused"
            " it.\n${text}")
    endif()
    require_mentions("${text}" "__cpp_lib_optional")

elseif(CASE STREQUAL "stops-on-what-is-not")
    # A name shaped like a feature test macro that no standard defines, so that
    # the refusal is the function's and not a compiler's opinion of the spelling.
    set(nobody_has "__cpp_lib_a_feature_no_standard_library_has")
    run_gate(absent "${nobody_has}" "" result text)
    require_stopped("${result}" "${text}" "${nobody_has} does not exist")
    require_mentions("${text}" "${nobody_has}")
    # The diagnostic offers a preset by name. Matched deliberately, unlike the
    # prose around it: if the preset is renamed in CMakePresets.json and not
    # here, the way out the function offers is a line that does nothing.
    require_mentions("${text}" "clang-libc++")

elseif(CASE STREQUAL "stops-on-a-version-nobody-has")
    # Present, but not this recent. The second of the two ways to fail, and the
    # one the diagnostic tells apart from the first.
    run_gate(too-old "__cpp_lib_optional" "999999" result text)
    require_stopped("${result}" "${text}" "999999 is not a version of anything")
    require_mentions("${text}" "__cpp_lib_optional")
    require_mentions("${text}" "999999")
    require_mentions("${text}" "clang-libc++")

elseif(CASE STREQUAL "refuses-a-name-that-is-not-one")
    # The argument check, which is a different refusal: it happens before
    # anything is compiled, and it names the call rather than the toolchain.
    run_gate(not-a-macro "optional" "" result text)
    require_stopped("${result}" "${text}" "optional is not a feature test macro")
    require_mentions("${text}" "cppbp_require_std_feature(optional)")
    # And stopped for that reason rather than for the toolchain's. Nothing has
    # been compiled at this point, so there is no standard library to have an
    # opinion and no preset to offer - naming one would mean the argument had
    # been taken for a feature and looked up after all.
    require_never_mentions("${text}" "clang-libc++"
        "a preset is what the other refusal offers")

elseif(CASE STREQUAL "tells-the-two-libraries-apart")
    # The case that names no environment and still runs everywhere. Each of the
    # two standard libraries provides exactly one of these and not the other,
    # so asking for both is one success and one refusal wherever this is built -
    # which is the claim the rest of the repository makes about C++23, put to a
    # machine on every commit instead of being written down.
    run_gate(mdspan "${only_in_libcxx}" "" mdspan_result mdspan_text)
    run_gate(stacktrace "${only_in_libstdcxx}" "" stacktrace_result stacktrace_text)

    set(answers "")
    string(APPEND answers "  ${only_in_libcxx}: ${mdspan_result}\n")
    string(APPEND answers "  ${only_in_libstdcxx}: ${stacktrace_result}\n")
    string(APPEND answers "(0 was accepted, anything else refused;")
    string(APPEND answers " the standard library here is ${STANDARD_LIBRARY})")

    if(mdspan_result EQUAL 0 AND stacktrace_result EQUAL 0)
        message(FATAL_ERROR
            "${CASE}: this toolchain has both features, and the pair was chosen"
            " because no toolchain had both. This is not a fault in"
            " cppbp_require_std_feature: a standard library has implemented"
            " something it did not have when docs/standard-library.md was"
            " measured. Update that table, and pick a pair that still splits"
            " the two libraries.\n${answers}")
    endif()

    if(NOT mdspan_result EQUAL 0 AND NOT stacktrace_result EQUAL 0)
        message(FATAL_ERROR
            "${CASE}: this toolchain has neither feature, and one of the two"
            " was expected on any standard library. Either the toolchain is"
            " one docs/standard-library.md has never measured, or the refusal"
            " has stopped being about the feature - read both configures"
            " below before changing the pair.\n${answers}"
            "\n--- ${only_in_libcxx} ---\n${mdspan_text}"
            "\n--- ${only_in_libstdcxx} ---\n${stacktrace_text}")
    endif()

    if(mdspan_result EQUAL 0)
        require_mentions("${stacktrace_text}" "${only_in_libstdcxx}")
        require_mentions("${stacktrace_text}" "clang-libc++")
    else()
        require_mentions("${mdspan_text}" "${only_in_libcxx}")
        require_mentions("${mdspan_text}" "clang-libc++")
    endif()

else()
    # The names are written twice - once in CMakeLists.txt where the tests are
    # registered, once above. A disagreement between the two lands here rather
    # than in a test that quietly checks nothing.
    message(FATAL_ERROR "no case named '${CASE}' in this script")
endif()
