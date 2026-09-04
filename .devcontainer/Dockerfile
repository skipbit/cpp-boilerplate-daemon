# The pinned toolchain shared by every template. CI builds against this image
# and the dev container uses the same one, so "works on my machine" and "works
# in CI" are the same claim.
#
# Everything is pinned by version. Ubuntu's own archive is too old for what this
# project wants to verify (24.04 ships CMake 3.28 and GCC 13), so CMake comes
# from Kitware's repository and Clang from LLVM's.
#
# Only the toolchain lives here. Dependencies fall into three kinds, and they
# belong in three different places:
#
#   toolchain            compilers, CMake, ninja, clang-tidy  -> this file
#   system libraries     Qt, TreeFrog, OpenGL                 -> a Dockerfile
#                                                               FROM this one
#   source dependencies  CLI11, GoogleTest                    -> FetchContent,
#                                                               no image at all
#
# This file is shared, so adding a system library here invalidates the cache for
# everything that uses it and mixes unrelated changes together. Something that
# needs Qt builds FROM this image and adds Qt on top, so the two update
# independently.

FROM ubuntu:24.04

# Bump these deliberately, in a commit of their own, so that a toolchain change
# is visible in the history instead of arriving with an unrelated build.
#
# UBUNTU_CODENAME and CMAKE_VERSION both name the Ubuntu release, so changing the
# base image means changing both. That is the pin doing its job rather than a
# footgun: a silently mismatched archive would install packages built for another
# release.
ARG UBUNTU_CODENAME=noble
ARG CMAKE_VERSION=4.4.2-0kitware1ubuntu24.04.1
ARG CLANG_VERSION=21
ARG GCC_VERSION=14
# No Debian package, so these are release binaries rather than apt pins.
ARG ACTIONLINT_VERSION=1.7.12
ARG HADOLINT_VERSION=2.15.1

ENV DEBIAN_FRONTEND=noninteractive

# RUN is /bin/sh -c unless this says otherwise, and /bin/sh has no pipefail: a
# pipeline is judged by its last command alone. Two of the lines below fetch a
# signing key and pipe it into gpg, and gpg is perfectly happy to dearmor an
# empty stream - so a failed download would have produced an empty keyring and a
# successful build. Named here once rather than guarded at each pipe, for the
# same reason the workflows set it on the shell rather than per step.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates gnupg wget \
 && wget -qO- https://apt.kitware.com/keys/kitware-archive-latest.asc \
      | gpg --dearmor -o /usr/share/keyrings/kitware-archive-keyring.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] https://apt.kitware.com/ubuntu/ ${UBUNTU_CODENAME} main" \
      > /etc/apt/sources.list.d/kitware.list \
 && wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key \
      | gpg --dearmor -o /usr/share/keyrings/llvm-archive-keyring.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/llvm-archive-keyring.gpg] http://apt.llvm.org/${UBUNTU_CODENAME}/ llvm-toolchain-${UBUNTU_CODENAME}-${CLANG_VERSION} main" \
      > /etc/apt/sources.list.d/llvm.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      "cmake=${CMAKE_VERSION}" \
      ninja-build \
      "g++-${GCC_VERSION}" \
      "clang-${CLANG_VERSION}" \
      "clang-tidy-${CLANG_VERSION}" \
      "clang-format-${CLANG_VERSION}" \
      "libc++-${CLANG_VERSION}-dev" \
      "libc++abi-${CLANG_VERSION}-dev" \
      shellcheck \
      git \
 && rm -rf /var/lib/apt/lists/*

# Each is one static binary and is in nobody's archive, so they come from their
# own releases. Here rather than installed by the jobs that run them, for the
# reason clang-tidy is here: a linter that changes version between one machine
# and the next turns a review into an argument about whose copy is right.
RUN wget -qO- "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz" \
      | tar -xz -C /usr/local/bin actionlint \
 && actionlint --version \
 && wget -qO /usr/local/bin/hadolint \
      "https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/hadolint-linux-x86_64" \
 && chmod +x /usr/local/bin/hadolint \
 && hadolint --version

# Unversioned names, so that CMakeLists and CI do not carry version numbers
# around. Changing the ARG above changes what these point at.
RUN update-alternatives --install /usr/bin/clang clang "/usr/bin/clang-${CLANG_VERSION}" 100 \
 && update-alternatives --install /usr/bin/clang++ clang++ "/usr/bin/clang++-${CLANG_VERSION}" 100 \
 && update-alternatives --install /usr/bin/clang-tidy clang-tidy "/usr/bin/clang-tidy-${CLANG_VERSION}" 100 \
 && update-alternatives --install /usr/bin/clang-format clang-format "/usr/bin/clang-format-${CLANG_VERSION}" 100 \
 && update-alternatives --install /usr/bin/gcc gcc "/usr/bin/gcc-${GCC_VERSION}" 100 \
 && update-alternatives --install /usr/bin/g++ g++ "/usr/bin/g++-${GCC_VERSION}" 100
