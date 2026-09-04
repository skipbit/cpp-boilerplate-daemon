# The standard library, and which parts of it are here

## What is supported

Support is not "C++23". It is a set of environments, and an environment is an
operating system, a compiler and a standard library - three things, not two.
The set is the CI matrix. When this document and the matrix disagree, the
matrix is right.

The operating system is Linux on every row of that matrix. Windows and macOS are
not built and not supported; a row for either would be a decision about what
this is for, not a column left blank.

Measured with `-std=gnu++23`, on the stock toolchains of each release. `24 gcc`
is GCC 13.3.0, `24 clang` is Clang 18.1.3, `26 gcc` is GCC 15.2.0, `26 clang` is
Clang 21.1.8; `stdc++` and `c++` are the standard library each was given.

| feature test macro | 24 gcc | 24 clang stdc++ | 24 clang c++ | 26 gcc | 26 clang stdc++ | 26 clang c++ |
| --- | --- | --- | --- | --- | --- | --- |
| `__cpp_lib_expected` | yes | **no** | yes | yes | yes | yes |
| `__cpp_lib_print` | **no** | **no** | yes | yes | yes | yes |
| `__cpp_lib_mdspan` | **no** | **no** | yes | **no** | **no** | yes |
| `__cpp_lib_ranges_to_container` | **no** | **no** | yes | yes | yes | yes |
| `__cpp_lib_stacktrace` | yes | yes | **no** | yes | yes | **no** |
| `__cpp_lib_move_only_function` | yes | yes | **no** | yes | yes | **no** |
| `__cpp_lib_ranges_zip` | yes | yes | **no** | yes | yes | **no** |
| `__cpp_lib_ranges_chunk` | yes | yes | **no** | yes | yes | **no** |
| `__cpp_lib_spanstream` | yes | yes | **no** | yes | yes | **no** |
| `__cpp_lib_generator` | **no** | **no** | **no** | yes | yes | **no** |
| `__cpp_lib_flat_map` | **no** | **no** | **no** | yes | yes | yes |
| `__cpp_lib_jthread` | yes | yes | **no** | yes | yes | yes |

Three things worth reading off it.

**Not one of these twelve is available everywhere.** C++23 as a whole is much
less portable than a version number suggests, and this is a sample rather than
the whole standard.

**The two libraries are missing opposite things.** libc++ has `print`, `mdspan`
and `ranges::to` and lacks `stacktrace`, `move_only_function`, `views::zip`,
`views::chunk` and `spanstream`. libstdc++ is the other way round. So narrowing
what is supported - to GCC with libstdc++ and clang with libc++, say - does not
widen what can be used. It buys `std::expected` and loses `std::stacktrace`.
The problem moves rather than shrinking.

**A newer release does not fix it.** Everything true of libc++ 18 above is still
true of libc++ 21, and libstdc++ 15 still has no `mdspan`.

Three rows deserve a note. `__cpp_lib_expected` is the only one where the same
library gives two answers: it is libstdc++ 13 in both 24.04 columns, and the
compiler is what differs. `__cpp_lib_flat_map` and `__cpp_lib_generator` are
plain absences - nobody has implemented them there yet.

`__cpp_lib_jthread` is the one that catches people writing services.
`std::stop_token` is the standard way to say "stop when you are asked", it is
C++20 rather than C++23, and libc++ 18 does not have it: `<stop_token>` compiles
to `no type named 'stop_source' in namespace 'std'` on the third column. So a
long-running program that wants a stop request portable across all six writes
its own - a small enum is enough - and can drop it for the standard one once
24.04 is no longer a floor it cares about.

Row `24 clang stdc++` is not an exotic environment. It is what you get by
installing clang on Ubuntu 24.04 and building, and it is what
`cmake --preset tidy` uses.

## The floor is the intersection

The code shipped here uses only what every row provides. Not because the rest
is bad, but because of what this code is: an example to be deleted and replaced.
Using the newest thing available in a file whose purpose is to be thrown away
buys very little, and costs three things - a template whose own advertised
preset fails on a stock machine, a red CI in the repository of whoever pressed
**Use this template**, and a failure that arrives as a page of compiler output
rather than as a sentence.

Your code is not the example. The floor is where the template starts, not where
your project has to stay.

## Stepping outside it

Say so in `CMakeLists.txt`, next to the code that needs it:

```cmake
cppbp_require_std_feature(__cpp_lib_expected 202202)
cppbp_require_std_feature(__cpp_lib_stacktrace)   # any version of it
```

Configuration then stops, on exactly the environments that cannot provide it,
naming the compiler, the standard library, whether the feature is missing
entirely or merely older than asked for, and the presets that do have it. It
does not stop anywhere else. What it costs is one line; what it buys is that the
environments you have decided not to support say so at the beginning of a build
instead of the middle, in the same words to everyone who clones the repository.

The argument is the feature test macro from the standard - the name cppreference
prints beside the feature - and not a name invented here. There is no list of
supported features to be on: the standard keeps that list, and a copy of it kept
in this repository could only be a worse one, out of date the moment a library
implements something.

The check reads the macro out of `<version>` rather than using the type. Those
agree, including in the awkward case: under clang 18 with libstdc++,
`<expected>` exists and is empty, and `__cpp_lib_expected` is undefined too. A
check that asked only whether the header could be included would answer yes
there and be wrong.

Configuration reports which library it found, whether or not anything asked:

```
-- Standard library: libstdc++ (Clang 18.1.3)
```

## Why `24 clang stdc++` is missing `std::expected`

Not because Clang 18 is missing a language feature. libstdc++ declares the
contents of `<expected>` only when the compiler reports
`__cpp_concepts >= 202002L`, and Clang 18 reports `201907L` - so the header is
present and empty. The same compiler, given libc++, has `std::expected`.

It is a library's declaration condition, not a compiler's capability, and the
distinction matters when you are deciding what to do about it: there is nothing
to wait for in the compiler, and the way out is a different library.

It also expires. Clang 21 reports `202002L`, so the 26.04 columns are unaffected
and this particular hole closes when 24.04 stops being the oldest supported
release. Most of the table does not expire that way: the libc++ column is a set
of features nobody has written yet, and 26.04 shows them still missing.

## The way out, and why it is not the default

`cmake --preset clang-libc++` builds with clang against libc++, which is the
answer when what is missing is one of libc++'s strengths - `expected` on 24.04,
`print`, `mdspan`. It is not an answer for `stacktrace` or `views::zip`, which
libc++ does not have; there the default library is already the right one.

It is not what clang does by default here, deliberately:

- It needs `libc++-dev` and `libc++abi-dev` installed. A template whose first
  instruction is an installation is not a starting point.
- Objects built against libc++ do not link against objects built against
  libstdc++. An installed library and the project consuming it have to agree, or
  the consumer gets a link error naming symbols nobody wrote.
- Which standard library a project runs on is a decision with consequences past
  compiling. A template should not make it quietly on your behalf.

So it is a named preset rather than a default: a thing to reach for once, on
purpose, and not something you discover you have been using.
