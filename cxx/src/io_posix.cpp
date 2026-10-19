// io.hpp on POSIX.
#include "io.hpp"

#include <algorithm>
#include <cerrno>
#include <csignal>
#include <ctime>

#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <sys/stat.h>
#include <unistd.h>

namespace pan::io {

namespace {

int descriptor(Stream stream) noexcept
{
    return stream == Stream::out ? STDOUT_FILENO : STDERR_FILENO;
}

// a descriptor that closes itself
class Descriptor {
public:
    explicit Descriptor(int fd) noexcept : fd_(fd) {}
    ~Descriptor()
    {
        if (fd_ >= 0)
            ::close(fd_);
    }
    Descriptor(const Descriptor&) = delete;
    Descriptor& operator=(const Descriptor&) = delete;
    int get() const noexcept { return fd_; }

private:
    int fd_;
};

// The descriptor read to its end into `into`, max + 1 bytes at most (the
// caller refuses more than max): again after a signal; a descriptor with
// nothing to read yet (O_NONBLOCK) waited for; another error is the end,
// as the asm's read_fd.
void read_to_end(int fd, std::string& into, std::size_t max)
{
    for (;;) {
        if (into.size() > max)
            return;
        if (into.capacity() - into.size() < 4096)
            into.reserve(std::min(std::max(into.capacity() * 2, std::size_t{65536}), max + 1));
        const std::size_t room = std::min(into.capacity(), max + 1) - into.size();
        const std::size_t old = into.size();
        ssize_t n = 0;
        into.resize_and_overwrite(old + room, [&](char* buffer, std::size_t) {
            n = ::read(fd, buffer + old, room);
            return old + (n > 0 ? static_cast<std::size_t>(n) : 0);
        });
        if (n > 0)
            continue;
        if (n == 0)
            return;
        if (errno == EINTR)
            continue;
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            pollfd wait{fd, POLLIN, 0};
            ::poll(&wait, 1, -1);
            continue;
        }
        return;
    }
}

}  // namespace

bool write_all(Stream stream, std::string_view text) noexcept
{
    const int fd = descriptor(stream);
    while (!text.empty()) {
        const ssize_t n = ::write(fd, text.data(), text.size());
        if (n > 0) {
            text.remove_prefix(static_cast<std::size_t>(n));
            continue;
        }
        if (n < 0 && errno == EINTR)
            continue;
        if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
            pollfd wait{fd, POLLOUT, 0};
            ::poll(&wait, 1, -1);
            continue;
        }
        return false;
    }
    return true;
}

std::optional<std::string> read_regular_file(const std::string& path, std::size_t max)
{
    // O_NONBLOCK: opening a fifo waits for a writer, before fstat could
    // refuse it (a regular file reads the same)
    Descriptor fd(::open(path.c_str(), O_RDONLY | O_NONBLOCK | O_CLOEXEC));
    if (fd.get() < 0)
        return std::nullopt;
    struct stat st;
    if (::fstat(fd.get(), &st) != 0 || !S_ISREG(st.st_mode) || st.st_size < 0
        || static_cast<std::size_t>(st.st_size) > max)
        return std::nullopt;
    std::string contents;
    contents.reserve(static_cast<std::size_t>(st.st_size) + 1);
    // (a byte more than the limit read: a file grown since the fstat is
    // refused, not cut short)
    read_to_end(fd.get(), contents, max);
    if (contents.size() > max)
        return std::nullopt;
    return contents;
}

std::optional<std::string> read_standard_input(std::size_t max)
{
    std::string contents;
    read_to_end(STDIN_FILENO, contents, max);
    if (contents.size() > max)
        return std::nullopt;
    return contents;
}

bool readable(const std::string& path) noexcept
{
    return ::access(path.c_str(), R_OK) == 0;
}

bool exists(const std::string& path) noexcept
{
    return ::access(path.c_str(), F_OK) == 0;
}

bool is_terminal(Stream stream) noexcept
{
    return ::isatty(descriptor(stream)) == 1;
}

std::string host_name()
{
    char name[256] = {};
    if (::gethostname(name, sizeof name - 1) != 0)
        return "localhost";
    return name;
}

long process_id() noexcept
{
    return static_cast<long>(::getpid());
}

LocalTime local_time(std::chrono::system_clock::time_point when) noexcept
{
    const std::time_t t = std::chrono::system_clock::to_time_t(when);
    std::tm tm{};
    if (!::localtime_r(&t, &tm))
        return {};
    return {tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday, tm.tm_hour, tm.tm_min, tm.tm_sec};
}

void ignore_broken_pipe() noexcept
{
    std::signal(SIGPIPE, SIG_IGN);
}

struct HeldSignals::State {
    sigset_t previous;
    bool held = false;
};

HeldSignals::HeldSignals() : state_(std::make_unique<State>())
{
    sigset_t set;
    sigemptyset(&set);
    for (int s = 1; s < NSIG; ++s) {
        switch (s) {
        case SIGKILL: case SIGSTOP: case SIGSEGV: case SIGBUS: case SIGFPE:
        case SIGILL: case SIGTRAP: case SIGSYS: case SIGABRT:
            continue;
        default:
            break;
        }
        struct sigaction sa;
        if (::sigaction(s, nullptr, &sa) != 0)  // (glibc's own: refused, skipped)
            continue;
        if ((sa.sa_flags & SA_SIGINFO) || (sa.sa_handler != SIG_DFL && sa.sa_handler != SIG_IGN))
            sigaddset(&set, s);
    }
    state_->held = ::pthread_sigmask(SIG_BLOCK, &set, &state_->previous) == 0;
}

HeldSignals::~HeldSignals()
{
    release();
}

void HeldSignals::release() noexcept
{
    if (state_ && state_->held) {
        state_->held = false;
        ::pthread_sigmask(SIG_SETMASK, &state_->previous, nullptr);
    }
}

}  // namespace pan::io
