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

# What this file decides: what the project is called, what it can be configured
# with, and what it installs. No target is defined here.
#
# src/CMakeLists.txt defines them, and that is where the program's own
# dependencies can be read in one place instead of inferred from a list of
# source files.
add_subdirectory(src)

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
# install(SBOM) refuses to describe a target that links one it cannot attribute.
# This program links the static libraries its modules are, which exist so the
# parts can be tested and are never installed, and CLI11 arrives through
# FetchContent, which installs and exports nothing. Measured with CMake 4.4.3:
# "references target mydaemon_options which has no install(EXPORT)/export(EXPORT)
# namespace and is not covered by any SBOM". The feature is experimental; this is
# a thing to try again rather than to work around by exporting what nobody
# consumes.
install(TARGETS mydaemon
    RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}" COMPONENT mydaemon_runtime)

install(FILES "${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}.service"
    DESTINATION "${MYDAEMON_SYSTEMD_UNIT_DIR}" COMPONENT mydaemon_runtime)
