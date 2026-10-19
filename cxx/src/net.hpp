// The sockets the fetch talks to a node with (fetch.hpp), behind one
// header: net_posix.cpp is the POSIX one, a MinGW port writes net_win32.cpp.
#pragma once

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <optional>
#include <string>
#include <string_view>

namespace pan::net {

using Clock = std::chrono::steady_clock;

// web3's: for a connection, a write, a wait for the answer's next bytes
inline constexpr std::chrono::seconds timeout{10};

// A connected stream socket; closed with the object. Its writes never raise
// a SIGPIPE, its waits go on after a signal.
class Connection {
public:
    Connection(Connection&& other) noexcept;
    Connection& operator=(Connection&& other) noexcept;
    ~Connection();

    // The whole of it sent, each wait `timeout` at most and none past the
    // deadline; false when it couldn't be.
    bool send_all(std::string_view data, Clock::time_point deadline) noexcept;

    enum class End {
        closed,  // the peer closed the connection
        enough,  // `enough` said the answer is whole
        limit,   // max bytes came
        late,    // the deadline passed before the answer ended
        idle,    // nothing came for `timeout`
        failed,  // an error of the connection
    };
    // What comes, appended to `into` (max bytes in it at most), until one of
    // End's - `enough` is given each piece as it comes.
    End receive(std::string& into, std::size_t max, Clock::time_point deadline,
                const std::function<bool(std::string_view)>& enough = nullptr);

private:
    friend std::optional<Connection> connect_tcp(const std::string&, const std::string&,
                                                 Clock::time_point);
    friend std::optional<Connection> connect_unix(const std::string&, Clock::time_point);
    explicit Connection(std::intptr_t handle) noexcept : handle_(handle) {}

    std::intptr_t handle_ = -1;
};

// The first of the host's addresses (getaddrinfo's) that takes the
// connection, each given `timeout`, none past the deadline; nullopt if none.
std::optional<Connection> connect_tcp(const std::string& host, const std::string& port,
                                      Clock::time_point deadline);

// The unix socket at the path (a node's IPC socket); nullopt if it can't be
// reached - a path too long for a socket's address, or empty, can't.
std::optional<Connection> connect_unix(const std::string& path, Clock::time_point deadline);

}  // namespace pan::net
