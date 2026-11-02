#pragma once

#include <chrono>
#include <string>

// What the process was asked to do, kept out of main() so that it can be tested
// by calling a function rather than by starting a program.
//
// CLI11 does not appear in this header: it is an implementation detail of one
// .cpp file, and replacing the parser is a change to that file alone.

namespace mydaemon::options {

struct Options {
    std::chrono::milliseconds interval{std::chrono::seconds{5}};
    std::string label;
};

/// What reading the command line produced.
///
/// `run` is false when the parser has already answered and the process should
/// end: `--help` and `--version` are requests it satisfies itself, and a usage
/// error has already been printed. `status` is what to exit with then.
struct Outcome {
    Options options;
    bool run = true;
    int status = 0;
};

/// Reads the command line, and the configuration file it names.
///
/// Called again on every SIGHUP, with the same arguments, which is why it holds
/// no state and reads the file each time.
[[nodiscard]] auto parse(int argc, const char* const* argv) -> Outcome;

}  // namespace mydaemon::options
