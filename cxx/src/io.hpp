// The system as the front-ends need it - files, the standard streams, the
// process, the signals - behind one header: io_posix.cpp is the POSIX one,
// a MinGW port writes io_win32.cpp (net.hpp: the sockets, the same way).
#pragma once

#include <chrono>
#include <cstddef>
#include <memory>
#include <optional>
#include <string>
#include <string_view>

namespace pan::io {

// The most bytecode read whole from a file or standard input, as a node's
// answer: past it, a refusal rather than a contract cut short.
inline constexpr std::size_t max_input = std::size_t{256} << 20;

enum class Stream { out, err };

// The whole text, whatever the system takes at a time (again after a
// signal, waited for when the stream is non-blocking and full); false on an
// error - a closed pipe is one (EPIPE) once ignore_broken_pipe() was called.
bool write_all(Stream stream, std::string_view text) noexcept;

// A regular file of max bytes at most, read whole: nullopt if it can't be
// opened, isn't a regular file (a fifo, a device: opened without waiting
// for a writer, refused), or is longer. For paths anybody may give.
std::optional<std::string> read_regular_file(const std::string& path, std::size_t max);

// Standard input to its end - waited for when it is non-blocking (a
// program's pipe that ran dry isn't the end) -, nullopt past max bytes
// (refused, not cut).
std::optional<std::string> read_standard_input(std::size_t max);

// Whether the file can be read (access R_OK), whether it exists (F_OK).
bool readable(const std::string& path) noexcept;
bool exists(const std::string& path) noexcept;

bool is_terminal(Stream stream) noexcept;
std::string host_name();
long process_id() noexcept;

// The local time of a moment, broken down (for the log lines).
struct LocalTime {
    int year = 1970, month = 1, day = 1, hour = 0, minute = 0, second = 0;
};
LocalTime local_time(std::chrono::system_clock::time_point when) noexcept;

// A write to a pipe closed early is an error (EPIPE), not the end of the
// process (the command line's choice; the library's sockets never raise it).
void ignore_broken_pipe() noexcept;

// While one lives, the signals the program handles (python's SIGINT
// handler, any it set) wait on this thread: a call into the library runs to
// its end, its system calls never cut short by them. release() (or the
// destructor) lets them in: delivered at once, their handlers run. The
// signals left to their default action, and the synchronous ones (a
// fault), are never held.
class HeldSignals {
public:
    HeldSignals();
    ~HeldSignals();
    HeldSignals(const HeldSignals&) = delete;
    HeldSignals& operator=(const HeldSignals&) = delete;
    void release() noexcept;

private:
    struct State;
    std::unique_ptr<State> state_;
};

}  // namespace pan::io
