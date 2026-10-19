// net.hpp on POSIX: non-blocking sockets, every wait a poll() bounded by
// net::timeout and the deadline.
#include "net.hpp"

#include <algorithm>
#include <cerrno>
#include <cstddef>
#include <cstring>

#include <fcntl.h>
#include <netdb.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

namespace pan::net {

namespace {

// The time a wait may take: `timeout`, no more than what is left before the
// deadline (ms, rounded up); 0 when it has passed.
int wait_ms(Clock::time_point deadline) noexcept
{
    const auto left = deadline - Clock::now();
    if (left <= Clock::duration::zero())
        return 0;
    const auto ms = std::chrono::ceil<std::chrono::milliseconds>(std::min<Clock::duration>(left, timeout));
    return static_cast<int>(ms.count());
}

// poll() for one event, again after a signal for what is left: > 0 ready, 0
// the time is up, < 0 an error
int wait_for(int fd, short events, Clock::time_point deadline) noexcept
{
    const auto until = std::min(deadline, Clock::now() + timeout);
    for (;;) {
        pollfd p{fd, events, 0};
        const int r = ::poll(&p, 1, wait_ms(until));
        if (r >= 0 || errno != EINTR)
            return r;
    }
}

int new_socket(int family, int type, int protocol) noexcept
{
    return ::socket(family, type | SOCK_NONBLOCK | SOCK_CLOEXEC, protocol);
}

// A connection in progress (a non-blocking socket's) finished: waited for
// (POLLOUT) its time at most, its outcome read (SO_ERROR)
bool finish_connect(int fd, Clock::time_point deadline) noexcept
{
    if (wait_for(fd, POLLOUT, deadline) <= 0)
        return false;
    int error = 0;
    socklen_t size = sizeof error;
    return ::getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &size) == 0 && error == 0;
}

bool connect_wait(int fd, const sockaddr* address, socklen_t length, Clock::time_point deadline) noexcept
{
    if (::connect(fd, address, length) == 0)
        return true;
    return (errno == EINPROGRESS || errno == EINTR) && finish_connect(fd, deadline);
}

}  // namespace

Connection::Connection(Connection&& other) noexcept : handle_(other.handle_)
{
    other.handle_ = -1;
}

Connection& Connection::operator=(Connection&& other) noexcept
{
    if (this != &other) {
        if (handle_ >= 0)
            ::close(static_cast<int>(handle_));
        handle_ = other.handle_;
        other.handle_ = -1;
    }
    return *this;
}

Connection::~Connection()
{
    if (handle_ >= 0)
        ::close(static_cast<int>(handle_));
}

bool Connection::send_all(std::string_view data, Clock::time_point deadline) noexcept
{
    const int fd = static_cast<int>(handle_);
    while (!data.empty()) {
        const ssize_t n = ::send(fd, data.data(), data.size(), MSG_NOSIGNAL);
        if (n > 0) {
            data.remove_prefix(static_cast<std::size_t>(n));
            continue;
        }
        if (n < 0 && errno == EINTR)
            continue;
        if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) && wait_for(fd, POLLOUT, deadline) > 0)
            continue;
        return false;
    }
    return true;
}

Connection::End Connection::receive(std::string& into, std::size_t max, Clock::time_point deadline,
                                    const std::function<bool(std::string_view)>& enough)
{
    const int fd = static_cast<int>(handle_);
    constexpr std::size_t piece = 65536;
    for (;;) {
        if (into.size() >= max)
            return End::limit;
        if (Clock::now() >= deadline)
            return End::late;
        const std::size_t room = std::min(piece, max - into.size());
        const std::size_t old = into.size();
        ssize_t n = 0;
        into.resize_and_overwrite(old + room, [&](char* buffer, std::size_t) {
            n = ::recv(fd, buffer + old, room, 0);
            return old + (n > 0 ? static_cast<std::size_t>(n) : 0);
        });
        if (n > 0) {
            if (enough && enough(std::string_view(into).substr(old)))
                return End::enough;
            continue;
        }
        if (n == 0)
            return End::closed;
        if (errno == EINTR)
            continue;
        if (errno != EAGAIN && errno != EWOULDBLOCK)
            return End::failed;
        const int r = wait_for(fd, POLLIN, deadline);
        if (r < 0)
            return End::failed;
        if (r == 0)
            return Clock::now() >= deadline ? End::late : End::idle;
    }
}

std::optional<Connection> connect_tcp(const std::string& host, const std::string& port,
                                      Clock::time_point deadline)
{
    addrinfo hints{};
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    addrinfo* found = nullptr;
    if (::getaddrinfo(host.c_str(), port.c_str(), &hints, &found) != 0)
        return std::nullopt;
    std::optional<Connection> connection;
    for (const addrinfo* a = found; a && !connection; a = a->ai_next) {
        const int fd = new_socket(a->ai_family, a->ai_socktype, a->ai_protocol);
        if (fd < 0)
            continue;
        if (connect_wait(fd, a->ai_addr, a->ai_addrlen, deadline))
            connection.emplace(Connection(fd));
        else
            ::close(fd);
    }
    ::freeaddrinfo(found);
    return connection;
}

std::optional<Connection> connect_unix(const std::string& path, Clock::time_point deadline)
{
    sockaddr_un address{};
    if (path.empty() || path.size() >= sizeof address.sun_path)
        return std::nullopt;
    address.sun_family = AF_UNIX;
    std::memcpy(address.sun_path, path.data(), path.size());
    const auto length = static_cast<socklen_t>(offsetof(sockaddr_un, sun_path) + path.size() + 1);
    const int fd = new_socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0)
        return std::nullopt;
    Connection connection(fd);
    const auto until = std::min(deadline, Clock::now() + timeout);
    for (;;) {
        if (::connect(fd, reinterpret_cast<const sockaddr*>(&address), length) == 0)
            return connection;
        if (errno == EINPROGRESS) {
            if (!finish_connect(fd, deadline))
                return std::nullopt;
            return connection;
        }
        // (a unix socket whose listener's backlog is full: EAGAIN, the
        // connection not begun - tried again a little later, its time)
        if ((errno != EAGAIN && errno != EINTR) || Clock::now() >= until)
            return std::nullopt;
        ::poll(nullptr, 0, 10);
    }
}

}  // namespace pan::net
