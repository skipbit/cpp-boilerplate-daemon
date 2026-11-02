# Versioning

## The short version

Semantic versioning, `MAJOR.MINOR.PATCH`, about **the interface other things
depend on** - not about how much work went into the release.

Which interface that is depends on what you are shipping. A library's is its
public API and its ABI. A program's is its command line, its exit codes and the
shape of what it prints, because a script that calls it depends on those
exactly the way code depends on a header.

- **MAJOR** - something that used the previous version stops working: code that
  no longer compiles or links, or a command line that is no longer accepted or
  now means something else.
- **MINOR** - something was added and everything that worked still works.
- **PATCH** - a fix that changes no declaration, no layout and no interface.

A release is a git tag, `vMAJOR.MINOR.PATCH`. Everything else - the GitHub
release, the notes, the archive - is produced from that tag by
`.github/workflows/release.yml`.

## Where the number lives

In `project(VERSION ...)` in `CMakeLists.txt`, and nowhere else. The generated
`version.hpp`, the package version file and the `pkg-config` file all read it
from there.

The tag is the source of truth for *what a release is*; the number in the
source is what the built artefacts say about themselves. Those two can drift,
and a release where they disagree is one nobody can trace back. So they are
compared, twice:

```sh
./scripts/release.sh v1.2.3     # refuses to create a tag that disagrees
```

and again in CI, by the same script, because a tag can also be made by hand.

The alternative - deriving the version from `git describe` at configure time -
was not taken. A template is consumed as a source archive and through **Use this
template**, and neither of those has tags. The version would become
`0.0.0-unknown` in exactly the situation this project exists to serve.

## What breaks a C++ library

This section and the next one are the library case. If what you are versioning
is a program, its equivalent is two sections down, and none of the header rules
below apply to it.

A C++ library has two contracts, and they break differently. Source
compatibility is what a recompile needs; binary compatibility is what an
existing `.so` needs. **The second is easier to break by accident**, because
nothing in the language warns you.

Breaks both:

- removing or renaming anything public
- changing a function's parameter or return types
- adding a parameter, even with a default value

Breaks the ABI while the source still compiles - the dangerous set:

- adding, removing or reordering non-static data members of a public type
- changing a member's type, or anything else that changes size or alignment
- adding the first virtual function to a class, or adding one to a class that
  already has them, or reordering them
- changing a base class
- changing an inline function or a template, which is compiled into everything
  that used it
- changing the value of an existing enumerator
- changing the standard the public headers require, or the standard library
  they are built against

The way out of most of that is to keep the state out of the public type: the
handle-body idiom, where the public class holds one pointer to an incomplete
type. Then adding a member is not an ABI change, because the member is not in
the public header. It costs an allocation and an indirection, which is a
trade you should make deliberately rather than discover.

## What the build does with the number

`SOVERSION` is set to `MAJOR`, so the installed shared library is
`libmylib.so.MAJOR` and a consumer that linked against MAJOR 1 will not
silently load MAJOR 2.

Static is the default, and none of that reaches a static build: the export
header, the hidden visibility and `SOVERSION` are all inert until the library
is a `.so`. So there is one CI job that builds with `BUILD_SHARED_LIBS=ON` and
reads the SONAME back out of what it installed, rather than out of the build
log. In a project that installs no library it still runs, and says how many it
found.

The package version file is generated with:

- `SameMinorVersion` while MAJOR is `0`
- `SameMajorVersion` from `1.0.0` on

because semantic versioning puts breaking changes in the MINOR slot while MAJOR
is zero. With `SameMajorVersion`, `find_package(mylib 0.1)` would accept an
installed `0.9`, which under that rule is a different library. The switch is
three lines in `CMakeLists.txt` and it changes on its own when you reach 1.0.0.

A program has neither. It installs one binary, nothing links against it and
nothing calls `find_package` on it, so its version is carried only by the tag
and by whatever `--version` prints.

## What breaks a program

Shorter than the library list, and easier to break without noticing, because
none of it is declared anywhere a compiler can check:

- renaming or removing an option, or changing what it takes
- changing what happens when an option is absent
- changing the format of what is printed, if anything reads it
- changing an exit code, including which failures are given the same one
- reading from a different place, or writing to one

The output format is the one that gets missed. A column added to a table is a
MINOR change to a person and a MAJOR one to the `awk` in somebody's pipeline.
Deciding which of those your output is for, and writing it down, is what makes
that question answerable at all.

A service has three more, and they break somebody's machine rather than
somebody's pipeline: the keys in its configuration file, the name of its unit -
which is what `systemctl enable` was typed with, and what every `systemctl`
command after it is typed with too - and which signals it answers. `systemctl
reload` is a promise about `SIGHUP` in the same way a flag is a promise about a
word.

## When to raise it

- **Start at `0.1.0`** and stay in `0.x` while the API is still being decided.
  While MAJOR is `0` anything may change in a MINOR release, and that is the
  point of `0.x`.
- **Go to `1.0.0` when somebody else depends on it.** Not when it feels
  finished. `1.0.0` is not a claim about quality, it is a promise about
  breakage, and the promise only means something once there is somebody to
  make it to.
- **Raise MAJOR without apology when you have to.** A library that never
  reaches 2.0.0 either stopped changing or started lying.

## Releasing

```sh
# 1. the version in CMakeLists.txt is the one you are about to release
./scripts/release.sh v0.2.0

# 2. it is local until you push it; that push is the release
git push origin v0.2.0
```

The tag runs `release.yml`, which checks the tag against the source, runs the
same gate `main` has to pass, builds in the pinned image, and publishes a
GitHub release with generated notes and an installed-tree archive.
