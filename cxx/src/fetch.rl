// The code at an address, from a node (fetch.hpp): the providers tried as
// web3's AutoProvider tries them, what the node says read by a ragel machine
// a function - the address, the provider's URI, the HTTP answer and its
// chunks, the JSON-RPC answer -, the code's hex made bytes (hex.hpp).
#include "fetch.hpp"

#include <algorithm>
#include <cstdlib>
#include <format>
#include <initializer_list>
#include <utility>

#include "decompile.hpp"
#include "hex.hpp"
#include "io.hpp"
#include "net.hpp"

// (ragel -G2 makes the cases of its switches fall through)
#pragma GCC diagnostic ignored "-Wimplicit-fallthrough"

namespace pan::fetch {

namespace {

using Clock = net::Clock;

constexpr std::string_view logger = "panoramix.loader";
// the most of a text from outside that goes in a message
constexpr std::size_t excerpt = 200;

const unsigned char* bytes(std::string_view text)
{
    return reinterpret_cast<const unsigned char*>(text.data());
}

std::string_view view(const unsigned char* begin, const unsigned char* end)
{
    return {reinterpret_cast<const char*>(begin), static_cast<std::size_t>(end - begin)};
}

// "0x" and 40 hex digits, made lowercase
%%{
    machine address;
    alphtype unsigned char;

    action keep { out.push_back(static_cast<char>(fc)); }
    action lower { out.push_back(static_cast<char>(fc - 'A' + 'a')); }

    main := '0' [xX] ([0-9a-f] @keep | [A-F] @lower){40};
}%%

%% write data;

// a provider's scheme, any case: the rest after it, or (an unknown one)
// where its name ends
%%{
    machine scheme;
    alphtype unsigned char;

    action http { kind = Scheme::http; rest = p + 1; fbreak; }
    action file { kind = Scheme::file; rest = p + 1; fbreak; }
    action no_tls { kind = Scheme::no_tls; fbreak; }
    action colon { colon = p; }

    main := 'http://'i @http
          | 'file://'i @file
          | ('https://'i | 'ws://'i | 'wss://'i) @no_tls
          | [^:]* ':' @colon any*;
}%%

%% write data;

// what follows http://: [userinfo@]host[:port], the path and the query to
// the fragment. The userinfo is up to the last '@' (each one starts the
// host again), the port after the last ':' of the host - or after the ']'
// of an IPv6 address.
%%{
    machine http_url;
    alphtype unsigned char;

    action at { host = p + 1; colon = v6_begin = v6_end = nullptr; }
    action colon { colon = p; }
    action v6_begin { v6_begin = p + 1; }
    action v6_end { v6_end = p; }
    action slash { path = p; }
    action query { path = p; query_first = true; }
    action fragment { fragment = p; }

    userinfo = [^/?#@]* '@' @at;
    ipv6 = '[' @v6_begin [^\]/?#@]* ']' @v6_end (':' @colon [^/?#@]*)?;
    reg = ([^/?#@:\[] | ':' @colon) ([^/?#@:] | ':' @colon)*;

    main := userinfo* (ipv6 | reg)?
            ('/' @slash [^#]* | '?' @query [^#]*)?
            ('#' @fragment any*)?;
}%%

%% write data;

// file://PATH or file://host/PATH: the path from its first '/'
%%{
    machine file_path;
    alphtype unsigned char;

    action slash { path = p; fbreak; }

    main := [^/]* '/' @slash;
}%%

%% write data;

// An HTTP answer's head: the status line (its status, its reason), the
// fields (a chunked transfer-encoding noted), the empty line.
%%{
    machine http_answer;
    alphtype unsigned char;

    action status {
        status_seen = true;
        if (status < 1000000)
            status = status * 10 + (fc - '0');
    }
    action reason { reason = p + 1; }
    action line_end { line_end = p; }
    action chunked { chunked = true; }
    action head_end { body = p + 1; fbreak; }

    eol = '\r'? '\n';
    status_line = [^ \r\n]* ' '+ (digit @status)+ (' ' @reason [^\r\n]*)? eol >line_end;
    te_value = ([^\r\n] | 'chunked'i @chunked)*;
    field = [^\r\n]+ eol
          | 'transfer-encoding'i ':' te_value eol;

    main := status_line field* eol @head_end;
}%%

%% write data;

// A chunked body: the size in hex (its extensions dropped), the bytes -
// stepped over at once (fexec), what a cut answer has of them taken -, and
// again until a size 0.
%%{
    machine chunked;
    alphtype unsigned char;

    action start { size = 0; }
    action digit { size = size > (SIZE_MAX >> 4) ? SIZE_MAX : size << 4 | std::size_t(fc - '0'); }
    action lower { size = size > (SIZE_MAX >> 4) ? SIZE_MAX : size << 4 | std::size_t(fc - 'a' + 10); }
    action upper { size = size > (SIZE_MAX >> 4) ? SIZE_MAX : size << 4 | std::size_t(fc - 'A' + 10); }
    action data {
        if (size == 0)
            fbreak;
        const std::size_t n = std::min(size, static_cast<std::size_t>(pe - (p + 1)));
        out.append(reinterpret_cast<const char*>(p + 1), n);
        fexec p + 1 + n;
    }

    eol = '\r'? '\n';
    chunk_size = ([0-9] @digit | [a-f] @lower | [A-F] @upper)+ >start;

    main := (chunk_size (';' [^\r\n]*)? eol @data eol)*;
}%%

%% write data;

// A JSON-RPC answer: its members' keys and values (a nested one stepped
// over by the counting machine `nested`, called), the first "result" and
// the first "error" kept.
%%{
    machine rpc_answer;
    alphtype unsigned char;

    action key_other { key = Key::other; }
    action key_result { key = result_key ? Key::other : Key::result; result_key = true; }
    action key_error { key = error_key ? Key::other : Key::error; error_key = true; }
    action begin { begin = p; }
    action string_end { take(begin, p + 1, true); }
    action scalar_end { take(begin, p, false); }
    action null { if (key == Key::error) error_null = true; }
    action nested { begin = p; depth = 1; fcall nested; }
    action open { ++depth; }
    action close {
        if (--depth == 0) {
            take(begin, p + 1, false);
            fret;
        }
    }
    action done { fbreak; }

    ws = [ \t\r\n];
    string = '"' ([^"\\] | '\\' any)* '"';

    nested := (string | [{\[] @open | [}\]] @close | [^"{}\[\]])*;

    key = string >key_other
        | '"result"' @key_result
        | '"error"' @key_error;
    scalar = [^,}\]"{\[ \t\r\n]+;
    value = string >begin @string_end
          | scalar >begin %scalar_end
          | 'null' %null
          | [{\[] @nested;
    member = key ws* ':' ws* value;

    main := ws* '{' ws* (member ws* (',' ws* member ws*)*)? '}' @done;
}%%

%% write data;

// Whether a whole JSON value went by: the brackets counted, the strings
// stepped over; read across the pieces of an answer (cs_ kept).
%%{
    machine json_value_end;
    alphtype unsigned char;
    variable cs cs_;

    action open { ++depth_; }
    action close {
        if (--depth_ == 0) {
            whole_ = true;
            fbreak;
        }
    }
    action string_end {
        if (depth_ == 0) {
            whole_ = true;
            fbreak;
        }
    }

    string = '"' ([^"\\] | '\\' any)* '"' @string_end;

    main := [ \t\r\n]*
            (string | [{\[] @open (string | [{\[] @open | [}\]] @close | [^"{}\[\]])*);
}%%

%% write data;

Provider parse_http_url(std::string_view rest)
{
    const unsigned char* const start = bytes(rest);
    const unsigned char* p = start;
    const unsigned char* const pe = start + rest.size();
    const unsigned char* host = start;
    const unsigned char* colon = nullptr;
    const unsigned char* v6_begin = nullptr;
    const unsigned char* v6_end = nullptr;
    const unsigned char* path = nullptr;
    const unsigned char* fragment = nullptr;
    bool query_first = false;
    int cs;
    %% machine http_url;
    %% write init;
    %% write exec;
    if (cs < http_url_first_final)
        return BadUrl{};
    const unsigned char* const authority_end = path ? path : fragment ? fragment : pe;
    std::string_view name, port;
    if (v6_begin) {
        name = view(v6_begin, v6_end);
        port = colon ? view(colon + 1, authority_end) : std::string_view();
    } else {
        name = view(host, colon ? colon : authority_end);
        port = colon ? view(colon + 1, authority_end) : std::string_view();
    }
    // (the asm's bounds: a host of 1 to 239 bytes, a port of 15 at most)
    if (name.empty() || name.size() > 239 || port.size() > 15)
        return BadUrl{};
    Http http;
    http.host = name;
    http.port = port.empty() ? "80" : std::string(port);
    http.authority = view(host, authority_end);
    if (path) {
        if (query_first)
            http.target = "/";
        http.target += view(path, fragment ? fragment : pe);
    } else {
        http.target = "/";
    }
    return http;
}

std::string parse_file_path(std::string_view rest)
{
    const unsigned char* p = bytes(rest);
    const unsigned char* const pe = p + rest.size();
    const unsigned char* path = nullptr;
    int cs;
    %% machine file_path;
    %% write init;
    %% write exec;
    (void)cs;
    return path ? std::string(view(path, pe)) : std::string();
}

std::optional<std::string_view> environment(const char* name)
{
    const char* value = std::getenv(name);
    if (!value)
        return std::nullopt;
    return std::string_view(value);
}

// The first of the default IPC sockets that exists (web3's
// get_default_ipc_path: geth's, parity's, trinity's)
std::optional<std::string> default_ipc()
{
    const auto home = environment("HOME");
    if (!home)
        return std::nullopt;
    for (const std::string_view place : {"/.ethereum/geth.ipc",
                                         "/.local/share/io.parity.ethereum/jsonrpc.ipc",
                                         "/.local/share/trinity/mainnet/ipcs-eth1/jsonrpc.ipc"}) {
        std::string path = std::string(*home) + std::string(place);
        if (io::exists(path))
            return path;
    }
    return std::nullopt;
}

// The answer of the node at the IPC socket: nullopt if it can't be
// reached. The answer is read until it is a whole JSON value.
std::optional<std::string> ask_ipc(const std::string& path, const std::string& request,
                                   Clock::time_point until)
{
    auto connection = net::connect_unix(path, until);
    if (!connection)
        return std::nullopt;
    if (!connection->send_all(request, until))
        throw Error("the request couldn't be sent to " + hex::escape(path));
    std::string answer;
    JsonValueEnd end;
    const auto how = connection->receive(answer, max_answer, until,
                                         [&](std::string_view piece) { return end.feed(piece); });
    if (how == net::Connection::End::late)
        throw Error("the node took more than 60 s to answer: " + hex::escape(path));
    return answer;
}

// The answer (its body) of the node at the http:// URI: nullopt if it can't
// be reached. HTTP/1.0: the node closes the connection after its answer.
std::optional<std::string> ask_http(const Http& http, std::string_view uri, const std::string& request,
                                    Clock::time_point until)
{
    auto connection = net::connect_tcp(http.host, http.port, until);
    if (!connection)
        return std::nullopt;
    const std::string message = std::format(
        "POST {} HTTP/1.0\r\nHost: {}\r\nContent-Type: application/json\r\n"
        "User-Agent: panoramix-cxx\r\nContent-Length: {}\r\n\r\n{}",
        http.target, http.authority, request.size(), request);
    if (!connection->send_all(message, until))
        throw Error("the request couldn't be sent to " + hex::escape(uri));
    std::string answer;
    if (connection->receive(answer, max_answer, until) == net::Connection::End::late)
        throw Error("the node took more than 60 s to answer: " + hex::escape(uri));
    HttpAnswer read = parse_http_answer(answer);
    switch (read.kind) {
    case HttpAnswer::Kind::ok:
        return std::move(read.body);
    case HttpAnswer::Kind::status:  // requests' raise_for_status
        throw Error(std::format("{} {} Error: {} for url: {}", read.status,
                                read.status < 500 ? "Client" : "Server",
                                hex::escape(read.reason, excerpt), hex::escape(uri)));
    case HttpAnswer::Kind::bad:
        break;
    }
    throw Error("the node's HTTP answer: " + hex::escape(read.excerpt, excerpt));
}

// The answer of the provider at the URI: nullopt if it can't be reached
// (the next one is tried), Error if it refuses otherwise.
std::optional<std::string> ask(std::string_view uri, const std::string& request, Clock::time_point until)
{
    const Provider provider = parse_provider(uri);
    if (const auto* http = std::get_if<Http>(&provider))
        return ask_http(*http, uri, request, until);
    if (const auto* ipc = std::get_if<Ipc>(&provider))
        return ask_ipc(ipc->path, request, until);
    if (std::holds_alternative<NoTls>(provider))
        throw Error("pancxx has no TLS nor websockets: give the http:// address of a node or its IPC "
                    "socket (file://PATH), not " + hex::escape(uri));
    if (const auto* unknown = std::get_if<UnknownScheme>(&provider))
        throw Error("Web3 does not know how to connect to scheme '" + hex::escape(unknown->scheme)
                    + "' in '" + hex::escape(uri) + "'");
    return std::nullopt;  // (BadUrl: as one that can't be reached)
}

}  // namespace

std::optional<std::string> parse_address(std::string_view text)
{
    std::string out = "0x";
    out.reserve(42);
    const unsigned char* p = bytes(text);
    const unsigned char* const pe = p + text.size();
    int cs;
    %% machine address;
    %% write init;
    %% write exec;
    if (cs < address_first_final)
        return std::nullopt;
    return out;
}

Provider parse_provider(std::string_view uri)
{
    enum class Scheme { other, http, file, no_tls } kind = Scheme::other;
    const unsigned char* const start = bytes(uri);
    const unsigned char* p = start;
    const unsigned char* const pe = start + uri.size();
    const unsigned char* rest = pe;
    const unsigned char* colon = nullptr;
    int cs;
    %% machine scheme;
    %% write init;
    %% write exec;
    (void)cs;
    switch (kind) {
    case Scheme::http:
        return parse_http_url(view(rest, pe));
    case Scheme::file:
        return Ipc{parse_file_path(view(rest, pe))};
    case Scheme::no_tls:
        return NoTls{};
    case Scheme::other:
        break;
    }
    return UnknownScheme{std::string(view(start, colon ? colon : start))};
}

HttpAnswer parse_http_answer(std::string_view answer)
{
    const unsigned char* const start = bytes(answer);
    const unsigned char* p = start;
    const unsigned char* const pe = start + answer.size();
    int status = 0;
    bool status_seen = false, chunked = false;
    const unsigned char* reason = nullptr;
    const unsigned char* line_end = nullptr;
    const unsigned char* body = nullptr;
    int cs;
    %% machine http_answer;
    %% write init;
    %% write exec;
    (void)cs;
    HttpAnswer read;
    read.status = status;
    read.excerpt = answer.substr(0, excerpt);
    if (!status_seen)
        return read;
    const unsigned char* const line = line_end ? line_end : pe;
    if (status >= 400 && status < 600) {
        read.kind = HttpAnswer::Kind::status;
        if (reason)
            read.reason = view(reason, line);
        return read;
    }
    if (status < 200 || status >= 300) {
        read.excerpt = view(start, line).substr(0, excerpt);
        return read;
    }
    if (!body)
        return read;
    read.kind = HttpAnswer::Kind::ok;
    read.body = chunked ? dechunk(view(body, pe)) : std::string(view(body, pe));
    return read;
}

std::string dechunk(std::string_view body)
{
    std::string out;
    std::size_t size = 0;
    const unsigned char* p = bytes(body);
    const unsigned char* const pe = p + body.size();
    int cs;
    %% machine chunked;
    %% write init;
    %% write exec;
    (void)cs;
    return out;
}

JsonValueEnd::JsonValueEnd()
{
    %% machine json_value_end;
    %% write init;
}

bool JsonValueEnd::feed(std::string_view piece)
{
    if (whole_)
        return true;
    const unsigned char* p = bytes(piece);
    const unsigned char* const pe = p + piece.size();
    %% machine json_value_end;
    %% write exec;
    return whole_;
}

std::variant<RpcCode, RpcFailure> parse_rpc_answer(std::string_view answer)
{
    enum class Key { other, result, error } key = Key::other;
    bool result_key = false, error_key = false, error_null = false, result_string = false;
    std::optional<std::string_view> result, error;
    const unsigned char* begin = nullptr;
    std::size_t depth = 0;
    const auto take = [&](const unsigned char* from, const unsigned char* to, bool is_string) {
        if (key == Key::result && !result) {
            result = view(from, to);
            result_string = is_string;
        } else if (key == Key::error && !error) {
            error = view(from, to);
        }
    };
    const unsigned char* p = bytes(answer);
    const unsigned char* const pe = p + answer.size();
    int cs, top = 0;
    int stack[1];
    %% machine rpc_answer;
    %% write init;
    %% write exec;
    (void)cs;
    if (error && !error_null)
        return RpcFailure{"the node answered an error: " + hex::escape(*error, excerpt)};
    if (!result)
        return RpcFailure{"the node's answer isn't JSON-RPC: " + hex::escape(answer, excerpt)};
    if (!result_string)
        return RpcFailure{"the node gave no code: " + hex::escape(*result, excerpt)};
    return RpcCode{result->substr(1, result->size() - 2)};
}

std::vector<std::uint8_t> code_at(std::string_view address)
{
    const auto lower = parse_address(address);
    if (!lower)
        throw Error("not an address (0x and 40 hex digits): " + hex::escape(address, excerpt));
    log(log_info, logger, "Fetching code for " + *lower + "...");
    const std::string request = R"({"jsonrpc": "2.0", "method": "eth_getCode", "params": [")" + *lower
                                + R"(", "latest"], "id": 1})";
    const auto until = Clock::now() + deadline;
    std::optional<std::string> answer;
    if (const auto uri = environment("WEB3_PROVIDER_URI"); uri && !uri->empty())
        answer = ask(*uri, request, until);
    if (!answer)
        if (const auto ipc = default_ipc())
            answer = ask_ipc(*ipc, request, until);
    if (!answer) {
        const auto uri = environment("WEB3_HTTP_PROVIDER_URI");
        answer = ask(uri && !uri->empty() ? *uri : "http://localhost:8545", request, until);
    }
    // (web3's websocket provider comes next: not here) none
    if (!answer)
        throw Error("Could not discover provider while making request: method:eth_getCode\nparams:('" + *lower
                    + "', 'latest')");
    const auto rpc = parse_rpc_answer(*answer);
    if (const auto* failure = std::get_if<RpcFailure>(&rpc))
        throw Error(failure->message);
    const std::string_view code_hex = std::get<RpcCode>(rpc).hex;
    if (log_enabled(log_debug))
        log(log_debug, logger, "Code: " + hex::escape(code_hex, std::size_t{256} << 10));
    auto code = hex::decode(code_hex);
    if (!code)
        throw NotHex("the node's answer isn't the code in hex");
    return std::move(*code);
}

}  // namespace pan::fetch
