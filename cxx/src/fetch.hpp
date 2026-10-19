// The code deployed at an address, from an Ethereum node: python's
// decompile_address (Loader.load_addr: web3's automatic provider, then
// eth_getCode at "latest"), as the asm's fetch.s does it. The provider is
// the one web3's AutoProvider finds: $WEB3_PROVIDER_URI (http://URL, or
// file://PATH - the node's IPC socket), else the first of the default IPC
// sockets that exists (geth's, parity's, trinity's under $HOME), else
// $WEB3_HTTP_PROVIDER_URI or http://localhost:8545; each tried when the one
// before can't be reached. JSON-RPC over the socket, or over HTTP/1.0. No
// TLS nor websockets: https://, ws:// and wss:// are refused with a message.
// What comes from the node is read by ragel machines (fetch.rl), the code's
// hex made bytes by hex.hpp's: the caller gets bytes.
#pragma once

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>
#include <variant>
#include <vector>

namespace pan::fetch {

// Why the code couldn't be had: what() is the message (text from outside
// in it escaped and cut to an excerpt).
class Error : public std::runtime_error {
public:
    using std::runtime_error::runtime_error;
};

// The node's answer is a code, but not in hex ("the node's answer isn't the
// code in hex"; the command line says "not a valid hex file: ADDRESS").
class NotHex : public Error {
public:
    using Error::Error;
};

// the whole of a fetch, every provider tried: each wait has net::timeout
// (10 s), the answer has to be in by then
inline constexpr std::chrono::seconds deadline{60};
// the biggest answer taken from a node
inline constexpr std::size_t max_answer = std::size_t{256} << 20;

// The code at the address ("0x" and 40 hex digits, any case): its bytes,
// none for an address without code. Logs "Fetching code for ADDRESS..."
// (panoramix.loader, INFO), the code at DEBUG. Throws Error.
std::vector<std::uint8_t> code_at(std::string_view address);

// --- the readings, apart for the tests ---

// "0x" and 40 hex digits, lowercase (python's address.lower()), or nullopt.
std::optional<std::string> parse_address(std::string_view text);

// A provider's URI, by its scheme (any case).
struct Http {               // http://[userinfo@]host[:port][/path][?query][#fragment]
    std::string host;       // a name or an address ([...] taken off an IPv6 one)
    std::string port;       // "80" when none
    std::string authority;  // host[:port] as written: the Host header
    std::string target;     // the path and the query ("/" when none)
};
struct Ipc {                // file://PATH (file://host/PATH: /PATH)
    std::string path;
};
struct NoTls {};            // https://, ws://, wss://
struct BadUrl {};           // http:// that can't be one: as a provider that can't be reached
struct UnknownScheme {      // python's NotImplementedError
    std::string scheme;     // up to the first ':' ("" when none)
};
using Provider = std::variant<Http, Ipc, NoTls, BadUrl, UnknownScheme>;
Provider parse_provider(std::string_view uri);

// An HTTP answer, read whole (HTTP/1.0: the node closes after it).
struct HttpAnswer {
    enum class Kind {
        ok,      // a 2xx status and the end of the head: the body
        status,  // a 4xx or 5xx status: requests' raise_for_status
        bad,     // anything else: no status line, another status, no end of the head
    };
    Kind kind = Kind::bad;
    int status = 0;
    std::string_view reason;       // status: the status line's reason
    std::string_view excerpt;      // bad: the status line, or the answer's beginning
    std::string body;              // ok: the body, a chunked one put together
};
HttpAnswer parse_http_answer(std::string_view answer);

// A chunked body put together (what a chunk cut short has, taken; the
// trailers dropped).
std::string dechunk(std::string_view body);

// Whether a whole JSON value has come yet (an IPC socket's answer has no
// other end): fed the answer's pieces as they come, the value read once.
class JsonValueEnd {
public:
    JsonValueEnd();
    // true once the value (an object, an array, a string) has ended
    bool feed(std::string_view piece);

private:
    int cs_;
    std::size_t depth_ = 0;
    bool whole_ = false;
};

// A JSON-RPC answer's code: the "result" string's inside (its hex, 0x and
// all), or the message (an "error" member that isn't null: the node's; no
// "result", or not a string).
struct RpcCode {
    std::string_view hex;
};
struct RpcFailure {
    std::string message;
};
std::variant<RpcCode, RpcFailure> parse_rpc_answer(std::string_view answer);

}  // namespace pan::fetch
