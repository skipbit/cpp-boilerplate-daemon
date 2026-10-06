#include <chrono>
#include <exception>
#include <iostream>
#include <optional>
#include <string_view>

#include "options.hpp"
#include "service.hpp"
#include "shutdown.hpp"

// main() decides nothing. It reads the command line, connects the loop to the
// signals and to the log, and turns what comes back into an exit status.
//
// It does not fork, detach or write a pid file. systemd starts this process,
// supervises it and stops it, and a process that forks away from its manager
// only makes itself harder to supervise. See systemd/ and the README.
//
// `char* const*` rather than `char**`: nothing here writes through that array,
// and misc-const-correctness says so. The standard requires an implementation to
// accept `int main(int, char**)` and leaves any other parameter type to it, and
// every compiler this project builds with accepts this one.

int main(int argc, char* const* argv)
{
    try {
        const auto parsed = mydaemon::options::parse(argc, argv);
        if (! parsed.run) {
            return parsed.status;
        }

        // First, so that no signal is delivered the old way before this takes
        // them over.
        mydaemon::shutdown::Watcher signals;

        const auto wait = [&signals](std::chrono::milliseconds limit) {
            return signals.wait(limit);
        };

        // std::cerr rather than std::clog: it flushes on every write, so a line
        // is in the journal when it was written rather than when the buffer
        // happened to fill.
        const auto report = [](std::string_view line) {
            std::cerr << line << '\n';
        };

        // The same parser on the same arguments, so an option means one thing
        // whether it was read at startup or on a SIGHUP.
        const auto reload = [argc, argv]() -> std::optional<mydaemon::options::Options> {
            const auto reread = mydaemon::options::parse(argc, argv);
            if (! reread.run) {
                return std::nullopt;
            }
            return reread.options;
        };

        mydaemon::service::run(parsed.options, {.wait = wait, .report = report, .reload = reload});
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "mydaemon: " << error.what() << '\n';
        return 1;
    }
}
