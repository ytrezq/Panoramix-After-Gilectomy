// fetch.hpp's readings: the address, the provider's URI, the HTTP answer,
// its chunks, the JSON-RPC answer.
#include <doctest/doctest.h>

#include <format>
#include <string>
#include <string_view>
#include <variant>

#include "fetch.hpp"

namespace fetch = pan::fetch;

namespace {

fetch::Http http_of(std::string_view uri)
{
    const auto p = fetch::parse_provider(uri);
    REQUIRE_MESSAGE(std::holds_alternative<fetch::Http>(p), std::string(uri));
    return std::get<fetch::Http>(p);
}

template <class T>
bool is(std::string_view uri)
{
    return std::holds_alternative<T>(fetch::parse_provider(uri));
}

std::string code_of(std::string_view answer)
{
    const auto r = fetch::parse_rpc_answer(answer);
    REQUIRE_MESSAGE(std::holds_alternative<fetch::RpcCode>(r), std::string(answer));
    return std::string(std::get<fetch::RpcCode>(r).hex);
}

std::string failure_of(std::string_view answer)
{
    const auto r = fetch::parse_rpc_answer(answer);
    REQUIRE_MESSAGE(std::holds_alternative<fetch::RpcFailure>(r), std::string(answer));
    return std::get<fetch::RpcFailure>(r).message;
}

// how many pieces of `text` (cut every `step` bytes) JsonValueEnd needed
// before it said the value is whole; 0 if it never did
std::size_t pieces_to_end(std::string_view text, std::size_t step)
{
    fetch::JsonValueEnd end;
    for (std::size_t i = 0, n = 1; i < text.size(); i += step, ++n)
        if (end.feed(text.substr(i, step)))
            return n;
    return 0;
}

}  // namespace

TEST_CASE("parse_address: 0x and 40 hex digits, lowercase")
{
    const std::string a = "0x00000000000000000000000000000000000000a1";
    CHECK(fetch::parse_address(a) == a);
    CHECK(fetch::parse_address("0XdAC17F958D2ee523a2206206994597C13D831ec7")
          == "0xdac17f958d2ee523a2206206994597c13d831ec7");
    CHECK_FALSE(fetch::parse_address("0x" + std::string(40, 'g')));
    CHECK_FALSE(fetch::parse_address("0x" + std::string(39, 'a')));
    CHECK_FALSE(fetch::parse_address("0x" + std::string(41, 'a')));
    CHECK_FALSE(fetch::parse_address("00" + std::string(40, 'a')));
    CHECK_FALSE(fetch::parse_address("0x12"));
    CHECK_FALSE(fetch::parse_address(""));
}

TEST_CASE("parse_provider: http://")
{
    auto h = http_of("http://127.0.0.1:8545");
    CHECK(h.host == "127.0.0.1");
    CHECK(h.port == "8545");
    CHECK(h.authority == "127.0.0.1:8545");
    CHECK(h.target == "/");
    h = http_of("HTTP://Node");
    CHECK(h.host == "Node");
    CHECK(h.port == "80");
    CHECK(h.authority == "Node");
    h = http_of("http://u:p@localhost:8545/");
    CHECK(h.host == "localhost");
    CHECK(h.authority == "localhost:8545");
    CHECK(h.target == "/");
    h = http_of("http://a@b:c@node:1/x");  // (the userinfo: to the last '@')
    CHECK(h.host == "node");
    CHECK(h.port == "1");
    CHECK(h.authority == "node:1");
    CHECK(h.target == "/x");
    CHECK(http_of("http://h/some/path?x=1#frag").target == "/some/path?x=1");
    CHECK(http_of("http://h?x=1").target == "/?x=1");
    CHECK(http_of("http://h#frag").target == "/");
    CHECK(http_of("http://h/a#b?c").target == "/a");
    h = http_of("http://a:b:80");  // (the port: after the last ':')
    CHECK(h.host == "a:b");
    CHECK(h.port == "80");
    CHECK(http_of("http://h:").port == "80");
}

TEST_CASE("parse_provider: http:// with an IPv6 address")
{
    auto h = http_of("http://[::1]:8545/rpc");
    CHECK(h.host == "::1");
    CHECK(h.port == "8545");
    CHECK(h.authority == "[::1]:8545");
    CHECK(h.target == "/rpc");
    h = http_of("http://[fe80::1]");
    CHECK(h.host == "fe80::1");
    CHECK(h.port == "80");
    h = http_of("http://[::1]@node:9");  // (an '@' after it: the userinfo's)
    CHECK(h.host == "node");
    CHECK(h.port == "9");
}

TEST_CASE("parse_provider: http:// that can't be one")
{
    CHECK(is<fetch::BadUrl>("http://"));
    CHECK(is<fetch::BadUrl>("http:///path"));
    CHECK(is<fetch::BadUrl>("http://:80"));
    CHECK(is<fetch::BadUrl>("http://u@"));
    CHECK(is<fetch::BadUrl>("http://[::1]x"));
    CHECK(is<fetch::BadUrl>("http://[::1"));
    CHECK(is<fetch::BadUrl>("http://h:1234567890123456"));
    CHECK(is<fetch::Http>("http://h:123456789012345"));
    CHECK(is<fetch::BadUrl>("http://" + std::string(240, 'h')));
    CHECK(is<fetch::Http>("http://" + std::string(239, 'h')));
}

TEST_CASE("parse_provider: file://, TLS, the other schemes")
{
    auto ipc = [](std::string_view uri) {
        const auto p = fetch::parse_provider(uri);
        REQUIRE(std::holds_alternative<fetch::Ipc>(p));
        return std::get<fetch::Ipc>(p).path;
    };
    CHECK(ipc("file:///home/u/.ethereum/geth.ipc") == "/home/u/.ethereum/geth.ipc");
    CHECK(ipc("FILE:///x") == "/x");
    CHECK(ipc("file://host/tmp/x.ipc") == "/tmp/x.ipc");
    CHECK(ipc("file://") == "");
    CHECK(ipc("file://host") == "");
    CHECK(is<fetch::NoTls>("https://example.com"));
    CHECK(is<fetch::NoTls>("HTTPS://example.com"));
    CHECK(is<fetch::NoTls>("ws://x"));
    CHECK(is<fetch::NoTls>("wss://x"));
    auto scheme = [](std::string_view uri) {
        const auto p = fetch::parse_provider(uri);
        REQUIRE(std::holds_alternative<fetch::UnknownScheme>(p));
        return std::get<fetch::UnknownScheme>(p).scheme;
    };
    CHECK(scheme("gopher://x") == "gopher");
    CHECK(scheme("http:/x") == "http");
    CHECK(scheme("httpx://x") == "httpx");
    CHECK(scheme("nothing") == "");
    CHECK(scheme("") == "");
    CHECK(scheme("a:b:c") == "a");
}

TEST_CASE("parse_http_answer: 2xx")
{
    auto a = fetch::parse_http_answer(
        "HTTP/1.0 200 OK\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{}");
    CHECK(a.kind == fetch::HttpAnswer::Kind::ok);
    CHECK(a.status == 200);
    CHECK(a.body == "{}");
    a = fetch::parse_http_answer("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2\r\n{}\r\n0\r\n\r\n");
    CHECK(a.kind == fetch::HttpAnswer::Kind::ok);
    CHECK(a.body == "{}");
    a = fetch::parse_http_answer("HTTP/1.1 204 No Content\r\ntransfer-encoding: gzip, Chunked\r\n\r\n3\r\nabc\r\n0\r\n");
    CHECK(a.body == "abc");
    // (chunked in another field's value is no transfer encoding)
    a = fetch::parse_http_answer("HTTP/1.0 200 OK\r\nX-Note: chunked\r\n\r\n3\r\nabc");
    CHECK(a.body == "3\r\nabc");
    a = fetch::parse_http_answer("HTTP/1.0 200 OK\nA: b\n\nbody");
    CHECK(a.kind == fetch::HttpAnswer::Kind::ok);
    CHECK(a.body == "body");
    a = fetch::parse_http_answer("HTTP/1.0 200 OK\r\n\r\n");
    CHECK(a.kind == fetch::HttpAnswer::Kind::ok);
    CHECK(a.body.empty());
}

TEST_CASE("parse_http_answer: errors")
{
    auto a = fetch::parse_http_answer("HTTP/1.0 404 Not Found\r\nServer: x\r\n\r\n");
    CHECK(a.kind == fetch::HttpAnswer::Kind::status);
    CHECK(a.status == 404);
    CHECK(a.reason == "Not Found");
    a = fetch::parse_http_answer("HTTP/1.0 503 Service Unavailable\r\n\r\n");
    CHECK(a.kind == fetch::HttpAnswer::Kind::status);
    CHECK(a.status == 503);
    CHECK(a.reason == "Service Unavailable");
    a = fetch::parse_http_answer("HTTP/1.0 404\r\n\r\n");
    CHECK(a.kind == fetch::HttpAnswer::Kind::status);
    CHECK(a.reason.empty());
    a = fetch::parse_http_answer("HTTP/1.0 404 Not Found");  // (no end of line: the reason to the end)
    CHECK(a.kind == fetch::HttpAnswer::Kind::status);
    CHECK(a.reason == "Not Found");
    a = fetch::parse_http_answer("HTTP/1.0 301 Moved\r\nLocation: x\r\n\r\n");
    CHECK(a.kind == fetch::HttpAnswer::Kind::bad);
    CHECK(a.excerpt == "HTTP/1.0 301 Moved");
    a = fetch::parse_http_answer("garbage");
    CHECK(a.kind == fetch::HttpAnswer::Kind::bad);
    CHECK(a.excerpt == "garbage");
    a = fetch::parse_http_answer("HTTP/1.0 200 OK\r\nA: b\r\n");  // (no end of the head)
    CHECK(a.kind == fetch::HttpAnswer::Kind::bad);
    CHECK(fetch::parse_http_answer("").kind == fetch::HttpAnswer::Kind::bad);
    CHECK(fetch::parse_http_answer(std::string(1000, 'x')).excerpt.size() == 200);
    a = fetch::parse_http_answer("HTTP/1.0 999999999999 Big\r\n\r\n");
    CHECK(a.kind == fetch::HttpAnswer::Kind::bad);
}

TEST_CASE("dechunk")
{
    CHECK(fetch::dechunk("5\r\nhello\r\n6\r\n world\r\n0\r\n\r\n") == "hello world");
    CHECK(fetch::dechunk("5;name=value\r\nhello\r\n0\r\n") == "hello");
    CHECK(fetch::dechunk("A\r\n0123456789\r\n0\r\n") == "0123456789");
    CHECK(fetch::dechunk("5\nhello\n0\n") == "hello");
    CHECK(fetch::dechunk("a\r\nhello") == "hello");  // (cut short: what there is)
    CHECK(fetch::dechunk("ffffffffffffffffffffffff\r\nabc") == "abc");
    CHECK(fetch::dechunk("zz") == "");
    CHECK(fetch::dechunk("") == "");
    CHECK(fetch::dechunk("3\r\nabcX") == "abc");  // (no end of line after the bytes: stopped there)
    // python's http.server, chunks of 1000 bytes
    std::string body, chunked;
    for (int i = 0; i < 5000; ++i)
        body += static_cast<char>('a' + i % 26);
    for (std::size_t i = 0; i < body.size(); i += 1000) {
        const auto part = std::string_view(body).substr(i, 1000);
        chunked += std::format("{:x}\r\n{}\r\n", part.size(), part);
    }
    chunked += "0\r\n\r\n";
    CHECK(fetch::dechunk(chunked) == body);
}

TEST_CASE("JsonValueEnd: a whole value, across pieces")
{
    CHECK(pieces_to_end(R"({"a": 1})", 100) == 1);
    CHECK(pieces_to_end(R"({"a": "}"})", 8) == 2);  // (the first '}' is in a string)
    const std::string nested = R"({"a": [1, {"b": "]"}, "\"}"], "c": {}})";
    CHECK(pieces_to_end(nested, 1) == nested.size());
    CHECK(pieces_to_end("  \n{}", 1) == 5);
    CHECK(pieces_to_end(R"("x")", 1) == 3);
    CHECK(pieces_to_end("[[]]", 1) == 4);
    CHECK(pieces_to_end(R"({"a": 1)", 1) == 0);
    CHECK(pieces_to_end("abc", 1) == 0);
    CHECK(pieces_to_end("}", 1) == 0);
    fetch::JsonValueEnd end;
    CHECK(end.feed("{}"));
    CHECK(end.feed("trailing"));
}

TEST_CASE("parse_rpc_answer: the code")
{
    CHECK(code_of(R"({"jsonrpc": "2.0", "id": 1, "result": "0x6000"})") == "0x6000");
    CHECK(code_of(R"({"result": "0x"})") == "0x");
    CHECK(code_of(R"({"result": ""})") == "");
    CHECK(code_of(R"({"error": null, "result": "0x60"})") == "0x60");
    CHECK(code_of(" \n{ \"result\" : \"0x60\" } trailing") == "0x60");
    CHECK(code_of(R"({"result": "0x60", "result": "0x61"})") == "0x60");
    CHECK(code_of(R"({"a": [{"result": "x"}], "result": "0x60"})") == "0x60");
    CHECK(code_of(R"({"a": "}\"]", "b": {"error": 1}, "result": "0x60"})") == "0x60");
    CHECK(code_of(R"({"a": true, "b": -1.5e3, "result": "0x60"})") == "0x60");
}

TEST_CASE("parse_rpc_answer: the failures")
{
    CHECK(failure_of(R"({"error": {"code": -32000, "message": "boom"}, "result": "0x60"})")
          == R"(the node answered an error: {"code": -32000, "message": "boom"})");
    CHECK(failure_of(R"({"result": "0x60", "error": "no"})") == R"(the node answered an error: "no")");
    CHECK(failure_of(R"({"error": nul, "result": "0x60"})") == "the node answered an error: nul");
    CHECK(failure_of(R"({"result": 5})") == "the node gave no code: 5");
    CHECK(failure_of(R"({"result": null})") == "the node gave no code: null");
    CHECK(failure_of(R"({"result": {"x": 1}})") == R"(the node gave no code: {"x": 1})");
    CHECK(failure_of(R"({"id": 1})") == R"(the node's answer isn't JSON-RPC: {"id": 1})");
    CHECK(failure_of(R"({"results": "0x60"})") == R"(the node's answer isn't JSON-RPC: {"results": "0x60"})");
    CHECK(failure_of("{}") == "the node's answer isn't JSON-RPC: {}");
    CHECK(failure_of("") == "the node's answer isn't JSON-RPC: ");
    CHECK(failure_of("garbage") == "the node's answer isn't JSON-RPC: garbage");
    CHECK(failure_of(R"({"result": "0x60)") == R"(the node's answer isn't JSON-RPC: {"result": "0x60)");
}

TEST_CASE("parse_rpc_answer: a node's text is escaped and cut")
{
    // (security.sh's node: escape sequences, raw, in its error's message)
    const std::string raw = "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-1,\"message\":"
                            "\"\x1b]0;pwned\x07\x1b[2J\x1b[31mGOTCHA\x1b[0m\r\nfake\"}}";
    const std::string m = failure_of(raw);
    CHECK(m.find('\x1b') == std::string::npos);
    CHECK(m.find('\n') == std::string::npos);
    CHECK(m.find("GOTCHA") != std::string::npos);
    const std::string big = "{\"error\": \"" + std::string(100000, '\x01') + "\"}";
    CHECK(failure_of(big).size() <= std::string_view("the node answered an error: ").size() + 4 * 200);
}

TEST_CASE("code_at: not an address")
{
    CHECK_THROWS_WITH_AS(fetch::code_at("0x12"), "not an address (0x and 40 hex digits): 0x12", fetch::Error);
    CHECK_THROWS_WITH_AS(fetch::code_at("0x" + std::string(40, 'g') + "\x1b"),
                         ("not an address (0x and 40 hex digits): 0x" + std::string(40, 'g') + "\\x1b").c_str(),
                         fetch::Error);
}
