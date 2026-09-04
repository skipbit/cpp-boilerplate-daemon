#include "unique_fd.hpp"

#include <unistd.h>

namespace mydaemon {

void UniqueFd::close_now() noexcept
{
    if (descriptor_ != closed) {
        // The result is dropped deliberately. close() can report an error left
        // over from a write, and there is nothing a destructor can do with it:
        // on Linux the descriptor is gone either way, so closing again would
        // shut whatever was opened next.
        static_cast<void>(::close(descriptor_));
        descriptor_ = closed;
    }
}

}  // namespace mydaemon
