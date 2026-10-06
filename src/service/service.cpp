#include "service.hpp"

#include "options.hpp"
#include "task.hpp"

namespace mydaemon::service {

void run(options::Options options, const Environment& environment)
{
    task::State state;

    for (;;) {
        const auto done = task::run(state, options.label);
        state = done.state;
        environment.report(done.line);

        // The one place a stop is noticed. A request that arrived while the
        // work above was running waits until here, so "it finishes what it is
        // doing" is a property of this shape rather than a promise the work
        // has to keep.
        switch (environment.wait(options.interval)) {
            case Wakeup::Stop:
                environment.report("stopping");
                return;
            case Wakeup::Reload:
                if (const auto fresh = environment.reload()) {
                    options = *fresh;
                    environment.report("configuration re-read");
                } else {
                    environment.report("configuration unreadable; keeping the one already loaded");
                }
                break;
            case Wakeup::Timeout:
                break;
        }
    }
}

}  // namespace mydaemon::service
