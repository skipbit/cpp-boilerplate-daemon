# This file builds on its own and as part of the monorepo. Nothing here assumes
# a parent project, which is why the distributed copy needs no edits.
cmake_minimum_required(VERSION 3.28)

project(mydaemon
    VERSION 0.1.0
    DESCRIPTION "A C++ service that runs until it is asked to stop — replace this line with what yours does"
    HOMEPAGE_URL "https://github.com/skipbit/cpp-boilerplate"
    LANGUAGES CXX)

# clangd, clang-tidy and everything else that reads the code without building it
# need the compile database, and its absence is the usual reason a fresh clone
# has no working "go to definition". The presets ask for it; this covers a build
# configured without them, which is what most people type first. An explicit
# -DCMAKE_EXPORT_COMPILE_COMMANDS still wins - and it is tested for emptiness,
# not for DEFINED, because CMake creates the cache entry itself and leaves it
# empty, so DEFINED is true even when nobody has asked for anything.
if(PROJECT_IS_TOP_LEVEL AND CMAKE_EXPORT_COMPILE_COMMANDS STREQUAL "")
    set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
endif()

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_LIST_DIR}/cmake/modules")

include(GNUInstallDirs)
include(CompilerWarnings)
include(StandardLibraryFeatures)
include(Sanitizers)
include(ClangTidy)
include(CommandLineDependencies)

find_package(Threads REQUIRED)

option(MYDAEMON_BUILD_TESTING "Build the test suite" ${PROJECT_IS_TOP_LEVEL})
option(MYDAEMON_INSTALL "Generate the install rules" ${PROJECT_IS_TOP_LEVEL})

# Not derived from CMAKE_INSTALL_LIBDIR. Under /usr, the prefix a distribution
# package uses, GNUInstallDirs makes that lib/x86_64-linux-gnu here, and systemd
# reads no multiarch directory: it reads lib/systemd/system under /usr and
# /usr/local. `systemd-analyze --system unit-paths` is the list.
set(MYDAEMON_SYSTEMD_UNIT_DIR "lib/systemd/system"
    CACHE STRING "Where the systemd unit is installed, relative to the install prefix")

set(MYDAEMON_GENERATED_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated")
configure_file(cmake/version.hpp.in "${MYDAEMON_GENERATED_DIR}/mydaemon/version.hpp" @ONLY)

# Two targets, and the split is the point. Everything the program does is in a
# library the tests can link; the executable is main.cpp and nothing else. A
# service written the other way round can only be checked by starting it and
# sending it signals, which is why so few of them are checked at all.
#
# The library is static and is never installed: it is an arrangement for testing
# this program, not an API for anyone else.
add_library(mydaemon_lib STATIC
    src/options.cpp
    src/service.cpp
    src/shutdown.cpp
    src/task.cpp
    src/unique_fd.cpp)

target_include_directories(mydaemon_lib PUBLIC
    "${CMAKE_CURRENT_LIST_DIR}/src"
    "${MYDAEMON_GENERATED_DIR}")

# Raise this to cxx_std_26 and the CI matrix will tell you what breaks.
target_compile_features(mydaemon_lib PUBLIC cxx_std_23)

# Threads for pthread_sigmask, which is the one signal call whose behaviour is
# defined once a process has more than one thread. CLI11 is named in one .cpp
# file and in no header, so swapping the parser is a change to that file and to
# cmake/modules/CommandLineDependencies.cmake.
target_link_libraries(mydaemon_lib PRIVATE CLI11::CLI11 Threads::Threads)

cppbp_set_warnings(mydaemon_lib PRIVATE)
cppbp_set_sanitizers(mydaemon_lib PUBLIC)
cppbp_enable_clang_tidy(mydaemon_lib)

add_executable(mydaemon src/main.cpp)
target_link_libraries(mydaemon PRIVATE mydaemon_lib)
cppbp_set_warnings(mydaemon PRIVATE)
cppbp_set_sanitizers(mydaemon PRIVATE)
cppbp_enable_clang_tidy(mydaemon)

# The unit names the program and the absolute path it was installed to, so it is
# generated rather than shipped. That path is fixed at configure time: installing
# to a different prefix means configuring again, not editing the copy.
configure_file(systemd/mydaemon.service.in
    "${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}.service" @ONLY)

if(MYDAEMON_BUILD_TESTING)
    enable_testing()
    add_subdirectory(test)
endif()

if(NOT MYDAEMON_INSTALL)
    return()
endif()

# A service installs two things: the program, and the unit that starts it. There
# is no export set and no config file, because nothing finds a service with
# find_package().
#
# There is no SBOM either, which is a limitation rather than a decision. CMake's
# install(SBOM) refuses to describe a target that links one it cannot attribute,
# and a dependency brought in by FetchContent is never installed or exported, so
# it can never be attributed. The feature is experimental; this is a thing to try
# again rather than to work around by exporting a dependency nobody consumes.
install(TARGETS mydaemon
    RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}" COMPONENT mydaemon_runtime)

install(FILES "${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}.service"
    DESTINATION "${MYDAEMON_SYSTEMD_UNIT_DIR}" COMPONENT mydaemon_runtime)
