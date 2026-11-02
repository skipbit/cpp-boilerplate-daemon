# The toolchain image

`.devcontainer/Dockerfile` is the environment CI builds in and the one the dev
container gives you. One file, two users, so "works on my machine" and "works in
CI" are the same claim.

This document is the part the file itself cannot hold: what is pinned, what is
deliberately not, and why the linter that reads it has one rule switched off.

## What is pinned, and how

Four different kinds of pin, because the things being pinned are not alike.

| what | how it is pinned | where |
| --- | --- | --- |
| CMake | an exact version, down to the packaging suffix | `ARG CMAKE_VERSION` |
| Clang, GCC | the major version, which the package name carries | `ARG CLANG_VERSION`, `ARG GCC_VERSION` |
| actionlint, hadolint | an exact release, downloaded as a binary | `ARG ACTIONLINT_VERSION`, `ARG HADOLINT_VERSION` |
| the two archives' signing keys | the key itself, beside the Dockerfile | `.devcontainer/*-keyring.asc` |
| everything else from apt | not pinned | - |

The first three are pinned because a version change in them is a change to what
this project checks. A new Clang has new warnings, a new clang-tidy has new
checks, and a new actionlint or hadolint has new rules - so a linter that
changes version between one machine and the next turns a review into an argument
about whose copy is right. Those bumps happen in a commit of their own.

The last row is the one that needs explaining.

## Why the rest of apt is not pinned

Every package Ubuntu ships - `git`, `ninja-build`, `ca-certificates`, the Qt
modules - is installed by name and takes whatever version the archive currently
offers.

That is not an oversight, and it is not laziness. **Ubuntu removes a package
version from the archive as soon as a second update supersedes it.** A pin
written today names a version that will not exist in a few weeks.

Measured against `ubuntu:24.04`, on the release this project targets:

```
$ apt-cache madison git
       git | 1:2.43.0-1ubuntu7.3 | noble-updates/main
       git | 1:2.43.0-1ubuntu7.3 | noble-security/main
       git | 1:2.43.0-1ubuntu7   | noble/main

$ apt-get install -y "git=1:2.43.0-1ubuntu7.1"
E: Version '1:2.43.0-1ubuntu7.1' for 'git' was not found
```

Two versions are left: the one that shipped with the release, and the newest
update. `7.1` and `7.2` existed and are gone. Pinning `7.3` today buys a build
that fails outright - not with a stale package, but with `Version not found` -
the week after next.

The other way out is worse. Pinning to the release pocket does keep working,
because that version never moves:

```
$ apt-get install -y "ca-certificates=20240203"     # succeeds
```

But `20240203` is the version that shipped in April 2024, and the current one is
`20260601~24.04.1`. Pinning there does not freeze the environment; it freezes it
*behind every security update since*, and does so silently, in a file nobody
rereads.

So the choice is between a build that breaks on a schedule nobody controls and
an image that quietly rots. Neither is worth having, and the thing they are
meant to buy - a reproducible image - is already bought by pinning the base
image, the compilers and the tools whose output this project actually reads.

## The keys the archives are read with

CMake comes from Kitware's repository and Clang from LLVM's, and apt reads
neither of them without the key it signs with. Both keys sit beside the
Dockerfile and are copied in:

```dockerfile
COPY kitware-archive-keyring.asc llvm-archive-keyring.asc /etc/apt/keyrings/
```

Which keys those are is written down here, because an armored key is not
something a reviewer can check by reading:

| archive | fingerprint | published at |
| --- | --- | --- |
| Kitware | `4DBEBE3EEC96E7B8C6EC5BE99E92FDC6C5B9BA75` | `apt.kitware.com/keys/kitware-archive-latest.asc` |
| LLVM | `6084F3CF814B57C1CF12EFD515CF4D18AF4F7421` | `apt.llvm.org/llvm-snapshot.gpg.key` |

A change to either file is reviewed against that table. A keyblock that is
neither of these is a key apt would trust and nobody chose.

A key is a constant, and fetching a constant puts somebody else's web server
between a build and whether it works - a failure with nothing in it for anyone
to act on. apt reads an armored key when the file name ends in `.asc`, so
nothing dearmors them and the image installs no `gnupg`.

What that trades away is noticing a rotation. When an archive starts signing
with a key that is not the one here, apt refuses the archive:

```
E: The repository 'https://apt.kitware.com/ubuntu noble InRelease' is not signed.
```

A refused archive is a failed build rather than a package installed unverified,
so the day it happens is loud. `dependency-freshness.yml` is what speaks before
then: it compares both copies against what the archives publish - every
fingerprint and expiry in them - so a replaced key, a new signing subkey and an
extended expiry each arrive as a line in the weekly issue. It reports a key that
is simply running out as well, 90 days ahead, because a key nobody replaces
still stops working on the day it expires.

## The linter, and the one rule it is not allowed to make

`hadolint` checks every Dockerfile in the repository on each pull request, and
`scripts/lint-paths.sh` is what decides which those are. It is what catches a
bug that need not have a symptom: a `RUN` that pipes a download into a consumer,
in an image whose shell has no `pipefail`, is judged by the last command in the
pipeline alone - so whether a failed download fails the build is left to what
the consumer makes of an empty stream. That is `DL4006`, the rule about setting
`pipefail` before a `RUN` that contains a pipe, and the reason
`SHELL ["/bin/bash", "-o", "pipefail", "-c"]` is set before the first `RUN` that
contains one.

One rule is switched off in `.hadolint.yaml`:

- **`DL3008`** - the rule that every `apt-get install` name a version. It is
  switched off for the reason above: following it means choosing between a build
  that stops working and an image that stops being updated. This is the whole
  rationale; there is nothing written in the Dockerfiles themselves, so this
  section is the only place it lives.

Nothing else is ignored. `DL4006` above, `DL3015` (install without
`--no-install-recommends`), `DL3009` (leaving apt's package lists in the image)
and the `SC` rules that hadolint applies to shell inside a `RUN` all still fail
the build.

## Changing it

The pins are yours, like everything else here. Bump them in a commit of their
own so a toolchain change is visible in the history rather than arriving
underneath an unrelated build, and run the checks the same way CI does:

```sh
hadolint .devcontainer/Dockerfile
```

`./scripts/install-hooks.sh` runs the same check on a Dockerfile you are about
to commit. `dependency-freshness.yml` watches the pinned versions and the two
signing keys weekly and opens an issue when one of them falls behind, because
neither Dependabot nor apt can see a version written into an `ARG` or a key that
travels with the image.
