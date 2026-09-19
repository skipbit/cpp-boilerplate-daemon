# Coding style

Two files decide what the compiler and the linter say about your code:
`.clang-format` for layout and `.clang-tidy` for everything else. This document
is the part neither of them can hold: why they are set the way they are.

Change them. They are your project's, not a rule handed down. What this
document asks is only that a change comes with a reason, in the same way the
ones below do.

## Layout: `.clang-format`

WebKit style, four-space indent, 100 columns, braces on their own line for
functions and types. There is nothing to defend in those numbers: they are a
choice, and their whole value is that nobody has to make it again.

The one thing worth knowing is that formatting is *only* clang-format's job.
No clang-tidy check may also be a formatter. Two tools with opinions about the
same character produce a file that changes every time either one runs.

## Analysis: `.clang-tidy`

The list starts from `-*` and turns on whole groups: `bugprone`, `cert`,
`clang-analyzer`, `cppcoreguidelines`, `hicpp`, `misc`, `modernize`,
`performance`, `portability`, `readability`. A check added by a newer
clang-tidy therefore arrives switched on, and the build is where you find out
about it. `WarningsAsErrors: '*'` makes every finding stop the build, because a
warning nobody has to fix is a warning everybody learns to ignore.

Then a short list of exclusions. Each one is below. **An exclusion that is not
listed here fails the build** - `scripts/check-tidy-rationale.sh` compares the
two, and CI runs it - because an exclusion nobody can explain becomes a box
nobody dares to open.

### The same check under two names

clang-tidy has alias checks: `hicpp-use-auto` and `modernize-use-auto` are one
check with two names, and a finding is reported under every name it has. With
both groups enabled, switching off one name of a pair changes nothing at all -
the finding still arrives under the other. So the exclusions below always name
every alias of the check they turn off, and any exclusion that named only one
half has been removed.

You can see this for yourself: a diagnostic prints as
`[cppcoreguidelines-avoid-c-arrays,hicpp-avoid-c-arrays,modernize-avoid-c-arrays]`.
Those are three names, one check.

### `NOLINT` is the last resort, and there are none

A `// NOLINT(check-name)` switches a check off on one line. Nothing enforces a
reason for one the way `check-tidy-rationale.sh` enforces a reason for the list
below - which is why it is the last thing to reach for rather than the first.
Three steps, in order.

**A finding you want to suppress is first a question about the design.** A
signal handler, for instance, can only tell the rest of a program anything
through a mutable global, and `cppcoreguidelines-avoid-non-const-global-variables`
says so; blocking the signals and receiving them synchronously needs neither a
handler nor a global, and the finding is then absent rather than suppressed.

**When the code is right and the check is wrong, say so in `.clang-tidy`,
once.** That is the list below, and `check-tidy-rationale.sh` makes writing the
reason a rule rather than a habit. A configuration entry can be read, argued
with and deleted; a `NOLINT` on line 41 of one file can only be found with grep.

**An inline `NOLINT` is for a finding that is wrong in one place and right
everywhere else.** There are none in this repository. If you add the first one,
name the checks rather than writing a bare `NOLINT`, and put the reason on the
line above it.

Some findings are neither, and the answer is then to narrow what the check asks
rather than to switch it off. `misc-include-cleaner` names the header that
declares a symbol, and three times here that is a header nobody writes.

- For the POSIX signal names, glibc's answer is a `bits/` header nobody may
  include, or `<signal.h>` where `<csignal>` is the spelling that belongs in
  C++ and works.
- For `poll`, `pollfd` and `POLLIN`, glibc's `<poll.h>` is a single line
  including `<sys/poll.h>`, so the declarations sit in the System V
  compatibility header and the check asks for that one. `<poll.h>` is the
  spelling POSIX defines, and the one the daemon template uses.
- `<QLabel>` is a forwarding header that some versions of the check see through
  to `qlabel.h`.

`misc-include-cleaner.IgnoreHeaders:
'bits/.*;.*signal\.h;.*sys/poll\.h;.*/Qt[A-Z][A-Za-z]*/.*'` says so, and the
check keeps its opinion about every other header. It goes inside
`CheckOptions:`; appended after it, YAML puts it somewhere clang-tidy does not
read and it silently does nothing.

### What is switched off, and why

**`bugprone-easily-swappable-parameters`** - fires on any two adjacent
parameters of the same type, which is most functions. The suggested remedy is
to give each parameter a distinct type, which is an API design decision and not
something a linter can be right about.

**`cert-oop54-cpp`** - the stricter half of a pair. `bugprone-unhandled-self-assignment`,
which stays on, asks for a self-assignment guard where the members make it
matter. This alias asks for one everywhere, including a copy assignment whose
members are `int`, where self-assignment is already correct.

**`cppcoreguidelines-avoid-magic-numbers`, `readability-magic-numbers`** - a
test file is nothing but literals, and there is no way for a check to tell an
expected value from a magic number.

**`cppcoreguidelines-macro-usage`** - the macros a library actually has are the
export macros a build system generates and the ones a test framework provides.
Those are exactly what this flags, and neither is yours to remove.

**`cppcoreguidelines-non-private-member-variables-in-classes`,
`misc-non-private-member-variables-in-classes`** - an aggregate with public data
members is a C++ type, not a mistake. This check turns every one of them into a
class with getters.

**`cppcoreguidelines-owning-memory`**, **`cppcoreguidelines-pro-bounds-constant-array-index`**,
**`cppcoreguidelines-pro-bounds-pointer-arithmetic`**,
**`cppcoreguidelines-pro-bounds-array-to-pointer-decay`**, **`hicpp-no-array-decay`** -
each of these can only be satisfied with the Guidelines Support Library:
`gsl::owner`, `gsl::at`, `gsl::span`. This template has no dependencies beyond
a test framework, and a check whose fix is "add a dependency" is a check that
argues with that. Add the library and turn them on if you want them.

**`cppcoreguidelines-pro-type-reinterpret-cast`**,
**`cppcoreguidelines-pro-type-union-access`** - both name the only way to do
something the language otherwise cannot: reinterpreting storage, and reading a
C API's union. Banning the spelling does not remove the need.

**`hicpp-multiway-paths-covered`** - `bugprone-switch-missing-default-case` is
on and covers the same switch. Two complaints about one `switch` teach nothing
the first one did not.

**`misc-use-anonymous-namespace`** - it contradicts `misc-use-internal-linkage`,
which is on: that one asks a file-local function to be given internal linkage,
and this one objects to the `static` you would write to do it. One of the two
has to go, and `static` on a free function is the shorter spelling.

**`modernize-use-trailing-return-type`** - the code here uses trailing return
types (`auto squeeze(std::string_view) -> std::string`), so the check agrees
with the style everywhere except one place: it also rewrites `int main()`.
`auto main() -> int` is legal and nobody writes it. If you would rather have
the convention enforced than merely followed, delete this line and change
`main`; it is a one-line decision either way.

**`portability-avoid-pragma-once`** - the headers here use `#pragma once`.
Every compiler this project supports implements it, and include guards are a
name you have to invent and keep unique.

**`readability-function-cognitive-complexity`** - `readability-function-size`
is on, and its thresholds are written down in `.clang-tidy` where you can argue
with them. Cognitive complexity is a second limit with an invisible formula.

**`readability-identifier-length`** - it demands three characters, and it fired
on `c` for the character in a loop over characters. A name that says what the
thing is beats a name that reaches a length.

## What the structure enforces

Some rules are not in either file, because the layout carries them:

- **Public headers declare, `src/` implements.** Anything under `src/` is never
  installed, so changing it is never a breaking change for a consumer.
  `HeaderFilterRegex` covers `include/` and `src/` both: clang-tidy reports a
  finding in a header only when the header itself matches that expression, so a
  public header outside it is a public header nothing checks.
- **One feature is one header, one implementation, one test.** There is no
  umbrella header, because a header that includes everything becomes a header
  that everything depends on.
- **No `utils`, `common`, `misc` or `helpers`.** A container with no meaning
  accumulates whatever has no home, and nothing ever leaves it.
- **Warnings and analysis are set per target**, so that code fetched into the
  build tree is not judged by rules its authors never agreed to - and, more to
  the point, so that its findings do not bury yours.

## Running the checks

```sh
cmake --preset tidy          # clang is pinned: clang-tidy reads the build's flags
cmake --build --preset tidy  # a finding fails the build, like a compile error
```

`./scripts/install-hooks.sh` runs clang-format, clang-tidy, actionlint,
hadolint and shellcheck on the files in a commit, before the commit exists. Anything not
installed is skipped and said so.
