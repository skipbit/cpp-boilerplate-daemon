# mydaemon

![C++23](https://img.shields.io/badge/C%2B%2B-23-blue.svg)
![CMake 3.28+](https://img.shields.io/badge/CMake-3.28%2B-blue.svg)
![License 0BSD](https://img.shields.io/badge/license-0BSD-blue.svg)

A C++ service that builds, tests, installs and stops cleanly from the first
commit. Rename it and start writing.

Generated from [cpp-boilerplate](https://github.com/skipbit/cpp-boilerplate),
where the template itself is developed and where issues about it belong.

There is no build badge here on purpose. **Use this template** copies this file
into your repository unchanged, and a workflow badge names the repository it
belongs to - so it would sit at the top of your README reporting somebody
else's build, green whatever yours does. The three above describe the code, and
stay true after the copy. Add your own once you have a repository:

```
[![main check](https://github.com/YOU/YOURS/actions/workflows/main-check.yml/badge.svg)](https://github.com/YOU/YOURS/actions/workflows/main-check.yml)
```

## Start

```sh
cmake --preset debug
cmake --build --preset debug
ctest --preset debug
```

CMake, a compiler and Ninja are enough; CLI11 and the test framework are fetched
during configuration.

Presets: `debug` (warnings as errors), `release`, `asan`, `tsan`, `tidy`,
`clang-libc++` (clang against libc++, which needs `libc++-dev` and
`libc++abi-dev`).

What it does out of the box, so that there is something to run:

```sh
./build/debug/mydaemon --interval 1 --label hello
# hello run 1
# hello run 2
# ^C
# stopping
```

It runs in the foreground and writes to standard error. Both are deliberate;
the next section says why.

## It does not daemonise, and that is the point

The traditional way to write a service - fork, `setsid`, fork again, close the
descriptors, write a pid file - solves a problem that no longer exists. It was
how a process detached from the terminal that started it back when the thing
starting it was a shell script with no way to keep track of it.

systemd is that way to keep track of it. It puts the service in its own cgroup,
knows its main process, restarts it, collects its output and reports its state.
A process that forks away from all of that is a process systemd has to guess
about, and every one of those steps takes something away:

| the old step | what it costs under a service manager |
| --- | --- |
| fork twice, `setsid` | the manager loses the process it was told to supervise |
| write a pid file | two answers to "which process is this", one of them stale |
| open a log file | timestamps, rotation and retention written again, worse |
| `chdir("/")`, `umask(0)` | `WorkingDirectory=` and `UMask=` already say it, in one place |

So this template stays in the foreground, writes lines to standard error, and
lets `systemd/mydaemon.service.in` say the rest. If you need it to run under
something that is not systemd, the shape is the same: every supervisor written
in the last fifteen years - runit, s6, supervisord, a container runtime - wants
a foreground process too.

## Make it yours

Everything is called `mydaemon`. Rename it:

```sh
./scripts/rename.sh yourservice
./scripts/install-hooks.sh
```

The first covers the namespace, both targets, the generated version header, the
name the program prints in its own messages, the homepage in `project()`, and
the systemd unit - its file name as well as what is inside it. The homepage
comes from the `origin` remote, or from `--url`; with neither, the line is
deleted rather than left pointing at the template.

`--author "Your Name"` rewrites the copyright line in `LICENSE`, and the year
with it. It is never taken from your git configuration: a name written there by
mistake is harder to notice than the template author's still being there, and
0BSD asks for no attribution either way.

The second points git at `.githooks/`, which runs clang-format, clang-tidy,
actionlint, hadolint and shellcheck on the files in a commit; anything not installed is
skipped rather than treated as a failure. The dev container runs it for you.

Then replace what it does. `task.cpp` counts its own runs, which is an example
of the shape rather than a feature.

## How it is laid out

```
src/               everything, because nothing here is installed as a header
test/              one test file per source file, plus one that signals the program
systemd/           the unit, with the name and the path filled in by CMake
cmake/             the generated version header's template
docs/              why the configuration is what it is
.devcontainer/     the pinned toolchain, used by CI and the dev container
.githooks/         the checks that run before a commit
```

There is no `include/`. A service publishes a command and a unit file, not an
API: no other project compiles against these headers, so none of them is
installed and changing one breaks nobody.

**`main()` decides nothing.** It reads the command line, connects the loop to
the signals and to the log, and turns what comes back into an exit status.
Everything it calls lives in `mydaemon_lib`, a static library that is built but
never installed - because a function in a library can be tested, and a loop in
`main()` can only be checked by starting a process and sending it signals.

**One thing per file, and the last column is the design.**

| unit | does | knows about |
| --- | --- | --- |
| `options` | turns `argv` and a configuration file into `Options` | CLI11, and nothing else does |
| `shutdown` | turns signals into an answer the loop can read | the OS, and nothing else does |
| `unique_fd` | closes a file descriptor exactly once | `close()` |
| `service` | works, waits, works again, until asked to stop | `options` and `task` |
| `task` | one run of the work | nothing |

`service` does not know that `shutdown` exists. `service.hpp` declares what the
loop needs - a wait, a way to report a line, a way to re-read the configuration
- and `shutdown` is written to fit that. The layer that knows about the OS
depends on the one that does not, so no signal type reaches the loop and its
tests drive it with lambdas: none of them starts a process, and none of them
waits for an interval.

`task` is the layer with nothing underneath it at all, which makes it the one
worth keeping pure as it grows. It is handed the state of the previous run and
returns the next one, so a test can run a hundred of them in no time.

To add a feature: `src/thing.hpp`, `src/thing.cpp`, `test/thing_test.cpp`, and
add the source to `add_library(mydaemon_lib ...)` and the test to
`add_executable(mydaemon_test ...)`.

## Signals

| signal | what happens |
| --- | --- |
| `SIGTERM`, `SIGINT` | finishes the run it is in, writes `stopping`, exits 0 |
| `SIGHUP` | reads the configuration file again; keeps the old one if it cannot |

**There is no signal handler.** The signals are blocked with `pthread_sigmask`,
turned into a file descriptor with `signalfd`, and waited for with `poll` -
`shutdown::Watcher` is all of it. Three things follow, and together they are the
reason for it:

- Nothing runs asynchronously, so there is no async-signal-safe code to get
  wrong. The usual advice - "a handler may only assign to a
  `volatile sig_atomic_t`" - is a rule about a thing that does not exist here,
  and neither does the global it would have to be written to. Turn that around
  and it is the argument: a handler *needs* a mutable global, `clang-tidy`
  objects to mutable globals, and the objection is right.
- One wait covers both the next interval and the next signal, so a stop is acted
  on when it arrives rather than at the end of the interval it interrupted.
- A signal that arrives while the work is running stays pending until that wait.
  So "it finishes what it is doing first" is a property of the loop's shape
  rather than a promise the work has to keep.

That descriptor is also where this grows. A service that later needs a socket, a
timer or an `inotify` watch adds a second entry to the same `poll` - which is
what a daemon's event loop is, and why it is worth starting from one.

`test/run-daemon.sh` is what says that is true rather than intended: it starts
the built program, signals it, and checks the exit status and every line that
came out - and then kills a second copy with `SIGKILL` to show the two are told
apart. A check that cannot tell a clean stop from a killed process is not
checking the clean stop.

## Under systemd

```sh
cmake --install build/debug --prefix /usr/local
systemctl daemon-reload
systemctl enable --now mydaemon
journalctl -u mydaemon -f
systemctl reload mydaemon   # the SIGHUP above
```

The unit is generated, not shipped: CMake fills in the description, the homepage
and the absolute path of the installed program. That path is fixed when you
configure, so installing to a different prefix means configuring again rather
than editing the installed copy.

It is installed to `lib/systemd/system` under the prefix - not to
`CMAKE_INSTALL_LIBDIR`, which under `/usr` is a multiarch directory that systemd
does not read. `systemd-analyze --system unit-paths` is the list it does read.
`-DMYDAEMON_SYSTEMD_UNIT_DIR=...` moves it for a distribution that wants it
somewhere else.

Read the unit before running it anywhere real. It denies itself everything this
example does not need (`ProtectSystem=strict`, `ProtectHome=true`,
`PrivateTmp=true`, `NoNewPrivileges=true`), and the first thing your service
does that it actually needs is the first line of that list to reconsider.

## Configuration

Options come from the command line, from a file, or from both - the command
line wins:

```sh
mydaemon --config /etc/mydaemon.conf
```

```ini
interval = 30
label = "collector"
```

The file is read again on every `SIGHUP`, by calling the same parser with the
same arguments, so there is one definition of what an option means rather than
two. A key it does not recognise is an error rather than something ignored: a
file being re-read is exactly the case where nobody is watching, and a typo that
silently does nothing is worse than one that says so and leaves the running
configuration alone.

## What is wired in

- **Warnings** per compiler, applied per target so fetched dependencies are not
  affected. `-Werror` is on in the `debug` preset; turn it off with
  `-DCPPBP_WARNINGS_AS_ERRORS=OFF`.
- **Sanitizers** for address, undefined behaviour, threads and memory.
  Combinations that cannot work together fail configuration rather than quietly
  checking less than you expect.
- **clang-tidy** in the compile step, so a violation fails the build the same
  way a compile error does.
- **CLI11**, fetched rather than vendored, for the command line and the
  configuration file both.
- **GoogleTest**, the same.
- **A test that signals the program.** `mydaemon.answers-signals` starts the
  built executable and does to it what a service manager does. The unit tests
  say the pieces work; this one says they were wired together.
- **An installed service**: `cmake --install` puts one binary in `bin/` and one
  unit in `lib/systemd/system/`.
- **Workflows**: `pr-check` and `main-check` run the matrix, the pinned build
  and the static analysis; `nightly-sanitizer` runs the address and thread
  builds overnight; `release` turns a `vX.Y.Z` tag into a GitHub release;
  `dependency-freshness` opens one issue, weekly, when a pin this started with
  falls behind - the ones Dependabot cannot see, because it does not read
  `FetchContent` tags or apt versions inside a `RUN` layer.
- **A pinned environment** in `.devcontainer/`, the same one CI builds against,
  so a green build means the code changed rather than the machine.

The rows are not a fixed list. `pr-check` and `main-check` ask this project what
it can be built with and build the rows it answers with, so a configuration the
project refuses in `CMakeLists.txt` gets no check at all - rather than a check
that builds nothing and reports success. Worth knowing before you name a row in
GitHub's required status checks: that name disappears the day the project
refuses the configuration, and a required check nothing reports waits forever.
The job named "what this project can be built with" lists every row in its
summary, and which of them were built.

A job named "what BUILD_SHARED_LIBS=ON builds and installs" runs on every pull
request, and here it installs no shared library at all: `mydaemon_lib` says
`STATIC`, so the flag does not reach it, and the prefix gets the binary and
the unit. It prints the number of libraries it read, zero included, rather
than letting a green tick stand for a count nobody has seen. What it checks
here is that the flag changes nothing: configure, build, test and install
still pass with it on, and the installed program asks the loader for nothing
it cannot find. If that is not a claim worth keeping, deleting the job is a
reasonable answer - nothing else in the workflow depends on it.

There is no SBOM here, unlike the library template. `install(SBOM)` refuses to
describe a target that links one it cannot attribute, and a dependency fetched
with `FetchContent` is never installed or exported, so CLI11 cannot be
attributed. The feature is experimental and this is worth trying again later;
exporting a dependency nobody consumes to satisfy it is not.

## Documents

- [docs/coding-style.md](docs/coding-style.md) - what `.clang-format` and
  `.clang-tidy` are set to, and why every disabled check is disabled. The list
  is enforced: `scripts/check-tidy-rationale.sh` fails the build if a check is
  switched off without a reason written down.
- [docs/standard-library.md](docs/standard-library.md) - which environments are
  supported, what their standard libraries actually provide, and how to depend
  on something outside what all of them have.
- [docs/toolchain.md](docs/toolchain.md) - what the pinned image fixes and what
  it deliberately does not, why apt packages are installed without a version,
  and the one hadolint rule that is switched off because of it.
- [docs/versioning.md](docs/versioning.md) - semantic versioning, what a break
  means, and how a release happens.

## Releasing

```sh
./scripts/release.sh v0.2.0   # refuses a tag that disagrees with project(VERSION)
git push origin v0.2.0        # this push is the release
```

## Standard

C++23, set per target with `target_compile_features`. Change one line in
`CMakeLists.txt` to move it.

A standard is not one thing, and not one thing per compiler either: it is a
compiler and a standard library, and the two disagree. On Ubuntu 24.04, GCC 13
has `std::expected` and no `<print>`; clang 18 has neither against the
libstdc++ it picks up by default, and both against libc++ - the same compiler,
a different answer. Configuration prints what the toolchain in front of you
actually has, and the code here stays inside what every environment in the
matrix provides, so `cmake --preset tidy` works on a stock machine.

To use something outside that set, ask for it in `CMakeLists.txt`, by the
feature test macro the standard gives it:

```cmake
cppbp_require_std_feature(__cpp_lib_expected 202202)
```

Configuration then stops on the environments that do not have it, naming the
environment and the way out, instead of failing later in a compile log or in
somebody else's clone. Any feature test macro works; there is no list here to
be on. [docs/standard-library.md](docs/standard-library.md) has what the
environments in the matrix actually provide, measured.

What is not standard C++ here is `shutdown.cpp` and the one line of
`unique_fd.cpp`: `pthread_sigmask` is POSIX, and `signalfd` is Linux. That is
where a port to something else would start, and it is why they are their own
files.

`std::stop_token` would be the standard way to carry a stop request, and it is
not used, because libc++ 18 - the third column of that table, and what
`--preset clang-libc++` gets on Ubuntu 24.04 - does not have it. `Wakeup` is the
enum that replaces it, and it is three lines to delete when that stops being a
floor you care about.

## Contributing

To this repository: please don't. It is assembled from
[cpp-boilerplate](https://github.com/skipbit/cpp-boilerplate) and republished,
so anything committed here is overwritten. Issues and pull requests belong
there.

To your own copy, once you have used the template: it is yours, and none of
this applies.

## License

0BSD. Use it, change it, ship it; no attribution required. Replace this file and
`LICENSE` with your own once it is your project.
