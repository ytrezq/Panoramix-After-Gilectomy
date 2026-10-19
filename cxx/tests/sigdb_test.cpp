// The signature database (sigdb.hpp): Keccak, the types' codes, a dump
// built and read back (python's rules: the last line of a selector, only
// signatures that hash to it), events, the JSON as python reads it, the
// file's checks, the rebuild when the dump changes. The real dump is
// opt-in: PANORAMIX_TEST_ABI_DUMP=path/to/abi_dump.xz.
#include <doctest/doctest.h>

#include <lzma.h>

#include <atomic>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <random>
#include <string>
#include <string_view>
#include <vector>

#include "sha256.hpp"
#include "sigdb.hpp"
#include "sigdb_impl.hpp"

using namespace std::literals;
namespace sigdb = pan::sigdb;
namespace fs = std::filesystem;

namespace {

std::string hex(std::span<const std::uint8_t> b)
{
    static constexpr char digits[] = "0123456789abcdef";
    std::string s;
    for (std::uint8_t x : b) {
        s += digits[x >> 4];
        s += digits[x & 15];
    }
    return s;
}

// "0x" and the first 4 bytes of the signature's keccak
std::string sel(std::string_view signature)
{
    auto h = sigdb::keccak256(signature);
    return "0x" + hex(std::span(h).first(4));
}
std::uint32_t sel32(std::string_view signature)
{
    auto h = sigdb::keccak256(signature);
    return std::uint32_t{h[0]} << 24 | std::uint32_t{h[1]} << 16 | std::uint32_t{h[2]} << 8 | h[3];
}

std::string xz(std::string_view text)
{
    std::string out(text.size() + text.size() / 2 + 4096, '\0');
    std::size_t pos = 0;
    lzma_ret r = lzma_easy_buffer_encode(
        6, LZMA_CHECK_CRC64, nullptr, reinterpret_cast<const std::uint8_t*>(text.data()),
        text.size(), reinterpret_cast<std::uint8_t*>(out.data()), &pos, out.size());
    REQUIRE(r == LZMA_OK);
    out.resize(pos);
    return out;
}

void write_file(const fs::path& path, std::string_view data)
{
    std::ofstream f(path, std::ios::binary | std::ios::trunc);
    f.write(data.data(), static_cast<std::streamsize>(data.size()));
    REQUIRE(f.good());
}

std::string read_file(const fs::path& path)
{
    std::ifstream f(path, std::ios::binary);
    return std::string(std::istreambuf_iterator<char>(f), {});
}

struct TempDir {
    fs::path path;
    TempDir()
    {
        static std::atomic<int> n{0};
        static const unsigned tag = std::random_device{}();
        path = fs::temp_directory_path() /
               ("sigdb_test." + std::to_string(tag) + "." + std::to_string(n++));
        fs::remove_all(path);
        fs::create_directories(path);
    }
    ~TempDir()
    {
        std::error_code ec;
        fs::remove_all(path, ec);
    }
};

// the messages of the module
std::vector<std::string>& messages()
{
    static std::vector<std::string> m;
    return m;
}
void capture(int level, std::string_view, std::string_view message)
{
    messages().push_back(std::to_string(level) + " " + std::string(message));
}
struct Capture {
    Capture()
    {
        messages().clear();
        sigdb::set_log_sink(capture);
    }
    ~Capture() { sigdb::set_log_sink(nullptr); }
    std::size_t count(std::string_view what) const
    {
        std::size_t n = 0;
        for (const std::string& m : messages())
            n += m.find(what) != std::string::npos;
        return n;
    }
};

// a type's code (hex), or "refused"
std::string code_of(std::string_view text)
{
    sigdb::StringPool pool;
    std::string code;
    if (!sigdb::parse_type(text, nullptr, pool, code))
        return "refused";
    // its text again: the same
    std::string back;
    const auto* p = reinterpret_cast<const std::uint8_t*>(code.data());
    sigdb::append_type_text(p, reinterpret_cast<const std::uint8_t*>(pool.bytes().data()), back);
    CHECK(back == text);
    CHECK(p == reinterpret_cast<const std::uint8_t*>(code.data() + code.size()));
    return hex({reinterpret_cast<const std::uint8_t*>(code.data()), code.size()});
}

// --- a dump of python's format ---

std::string line(std::string_view selector, std::string_view abi)
{
    return "{\"selector\": \"" + std::string(selector) + "\", \"abi\": " + std::string(abi) + "}\n";
}

std::string mini_dump()
{
    std::string d;
    // well-known ones, their selectors as everybody knows them
    d += line("0xa9059cbb",
              R"({"name": "transfer", "type": "function", "inputs": [{"name": "to", "type": "address", "internalType": "address"}, {"name": "value", "type": "uint256"}], "outputs": [{"name": "", "type": "bool"}], "stateMutability": "nonpayable"})");
    d += line("0x70a08231", R"({"name": "balanceOf", "inputs": [{"name": "", "type": "address"}]})");
    d += line("0x23b872dd",
              R"({"name": "transferFrom", "type": "function", "inputs": [{"name": "from", "type": "address"}, {"name": "to", "type": "address"}, {"name": "value", "type": "uint256"}]})");
    d += line("0xddf252ad",
              R"({"name": "Transfer", "type": "event", "anonymous": false, "inputs": [{"name": "from", "type": "address", "indexed": true}, {"name": "to", "type": "address", "indexed": true}, {"name": "value", "type": "uint256", "indexed": false}]})");
    // python's truth for "indexed"
    d += line("0x8c5be1e5",
              R"({"name": "Approval", "type": "event", "inputs": [{"name": "owner", "type": "address", "indexed": 1}, {"name": "spender", "type": "address", "indexed": "yes"}, {"name": "value", "type": "uint256", "indexed": []}]})");
    d += line("0x4e487b71", R"({"name": "Panic", "type": "error", "inputs": [{"name": "code", "type": "uint256"}]})");
    // a real collision (Poly Network): the last line of the selector wins
    d += line("0x41973cd9", R"({"name": "putCurEpochConPubKeyBytes", "inputs": [{"name": "", "type": "bytes"}]})");
    d += line("0x41973cd9",
              R"({"name": "f1121318093", "inputs": [{"name": "a", "type": "bytes"}, {"name": "b", "type": "bytes"}, {"name": "c", "type": "uint64"}]})");
    // the last one doesn't hash to its selector: python knows none
    d += line(sel("mint(address,uint256)"), R"({"name": "mint", "inputs": [{"name": "to", "type": "address"}, {"name": "amount", "type": "uint256"}]})");
    d += line(sel("mint(address,uint256)"), R"({"name": "unknown40c10f19", "inputs": [{"name": "_param1", "type": "uint64"}]})");
    // the first one doesn't, the last one does
    d += line(sel("burn(uint256)"), R"({"name": "unknown42966c68", "inputs": []})");
    d += line(sel("burn(uint256)"), R"({"name": "burn", "inputs": [{"name": "amount", "type": "uint256"}]})");
    // a key python never asks for: "0x" and 8 lowercase digits only
    d += line("0xA9059CBB", R"({"name": "transfer", "inputs": [{"name": "x", "type": "address"}, {"name": "y", "type": "uint256"}]})");
    // a library of an old compiler: hashed without its space
    d += line("0x0592ca9d", R"({"name": "getMin", "inputs": [{"name": "self", "type": "uint32[] storage"}]})");
    // tuples by their components, nested, with names
    d += line(sel("deposit((address,(uint8,bytes32)[])[2],string)"),
              R"({"name": "deposit", "inputs": [{"name": "orders", "type": "tuple[2]", "components": [{"name": "owner", "type": "address"}, {"name": "items", "type": "tuple[]", "components": [{"name": "kind", "type": "uint8"}, {"internalType": "bytes32", "type": "bytes32", "name": "data"}]}]}, {"name": "memo", "type": "string"}]})");
    // a tuple written out: no names
    d += line(sel("batch((uint256,address)[])"), R"({"name": "batch", "inputs": [{"name": "calls", "type": "(uint256,address)[]"}]})");
    // an empty tuple; "tupleX": python's text, a named type
    d += line(sel("e(())"), R"({"name": "e", "inputs": [{"name": "t", "type": "tuple", "components": []}]})");
    d += line(sel("odd((uint256)X)"), R"({"name": "odd", "inputs": [{"name": "t", "type": "tupleX", "components": [{"name": "v", "type": "uint256"}]}]})");
    // texts that aren't types: named types of that text
    d += line(sel("f(uint)"), R"({"name": "f", "inputs": [{"name": "v", "type": "uint"}]})");
    d += line(sel("pull(IERC20,uint256)"), R"({"name": "pull", "inputs": [{"name": "token", "type": "IERC20"}, {"name": "amount", "type": "uint256"}]})");
    d += line(sel("setRate(fixed128x18)"), R"({"name": "setRate", "inputs": [{"name": "r", "type": "fixed128x18"}]})");
    d += line(sel("call(function)"), R"({"name": "call", "inputs": [{"name": "f", "type": "function"}]})");
    d += line(sel("big(bytes32[1263941234127518272])"), R"({"name": "big", "inputs": [{"name": "b", "type": "bytes32[1263941234127518272]"}]})");
    // escapes: \u, a surrogate pair; a lone surrogate isn't text
    d += line("0x5371ede7", R"({"name": "naïve", "inputs": [{"name": "v", "type": "bytes32"}]})");
    d += line("0x34f68609", R"({"name": "smile😀", "inputs": []})");
    d += line(sel("lone()"), R"({"name": "lone\ud800", "inputs": []})");
    // keys twice: the last; values python reads and this skips
    d += line("0x095ea7b3",
              R"({"name": "wrong", "inputs": [], "outputs": [{"name": "x", "type": "uint256", "weird": [NaN, -Infinity, Infinity, 1e10, -0.5E-3, {"a": [true, null, false]}, "\"\\\/\b\f\n\r\tA"]}], "name": "approve", "inputs": [{"name": "spender", "type": "address"}, {"name": "amount", "type": "uint256"}]})");
    // what python can't read: an input that isn't an object, a type that
    // isn't a string, no inputs
    d += line(sel("notObject(uint256)"), R"({"name": "notObject", "inputs": ["uint256"]})");
    d += line(sel("notString(uint256)"), R"({"name": "notString", "inputs": [{"name": "x", "type": 5}]})");
    d += line(sel("noInputs()"), R"({"name": "noInputs"})");
    // blank lines, other keys; the last line without its newline
    d += "\n   \r\n";
    d += R"({"abi": {"name": "totalSupply", "inputs": [], "type": "function"}, "extra": [1, 2, {"x": "y"}], "selector": "0x18160ddd"})";
    return d;
}

struct Mini {
    TempDir dir;
    fs::path dump = dir.path / "abi_dump.xz";
    fs::path db = dir.path / "cache" / "sigdb1.bin";
    sigdb::BuildStats stats;
    std::unique_ptr<sigdb::Database> open;
    Mini()
    {
        write_file(dump, xz(mini_dump()));
        stats = sigdb::build(dump, db);
        open = sigdb::Database::open(db);
    }
};

std::vector<std::string> param_names(const sigdb::Entry& e)
{
    std::vector<std::string> v;
    for (sigdb::Field f : e.params())
        v.emplace_back(f.name());
    return v;
}

}  // namespace

TEST_CASE("sigdb: keccak-256")
{
    auto k = [](std::string_view s) { return hex(sigdb::keccak256(s)); };
    CHECK(k("") == "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470");
    CHECK(k("transfer(address,uint256)") ==
          "a9059cbb2ab09eb219583f4a59a5d0623ade346d962bcd4e46b11da047c9049b");
    CHECK(k("Transfer(address,address,uint256)") ==
          "ddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef");
    // around the rate (136 bytes), several blocks
    CHECK(k(std::string(135, 'a')) == "34367dc248bbd832f4e3e69dfaac2f92638bd0bbd18f2912ba4ef454919cf446");
    CHECK(k(std::string(136, 'a')) == "a6c4d403279fe3e0af03729caada8374b5ca54d8065329a3ebcaeb4b60aa386e");
    CHECK(k(std::string(137, 'a')) == "d869f639c7046b4929fc92a4d988a8b22c55fbadb802c0c66ebcd484f1915f39");
    CHECK(k(std::string(200, 'a')) == "96ea54061def936c4be90b518992fdc6f12f535068a256229aca54267b4d084d");
}

TEST_CASE("sigdb: the codes of the types")
{
    // elementary: a byte
    CHECK(code_of("uint8") == "00");
    CHECK(code_of("uint256") == "1f");
    CHECK(code_of("int8") == "20");
    CHECK(code_of("int256") == "3f");
    CHECK(code_of("bytes1") == "40");
    CHECK(code_of("bytes32") == "5f");
    CHECK(code_of("address") == "60");
    CHECK(code_of("bool") == "61");
    CHECK(code_of("string") == "62");
    CHECK(code_of("bytes") == "63");
    CHECK(code_of("function") == "64");
    CHECK(code_of("fixed128x18") == "650f12");
    CHECK(code_of("ufixed8x0") == "660000");
    // arrays: the outer dimension (the last one written) first
    CHECK(code_of("uint256[]") == "671f");
    CHECK(code_of("uint256[2][]") == "6768021f");
    CHECK(code_of("uint256[][3]") == "6803671f");
    CHECK(code_of("bytes32[1263941234127518272]") == "68c0f48ea9b1fb9ac5115f");
    CHECK(code_of("bool[0]") == "680061");
    // tuples written out: unnamed fields (the name 0), nested
    CHECK(code_of("(uint256,address)[]") == "676902001f0060");
    CHECK(code_of("((uint8,address),uint256)") == "690200690200000060001f");
    CHECK(code_of("()") == "6900");
    CHECK(code_of("()[2]") == "68026900");
    // a library's references, named types (their text a string reference)
    CHECK(code_of("uint32[] storage") == "6a6703");
    CHECK(code_of("uint8 memory") == "6b00");
    CHECK(code_of("bytes calldata") == "6c63");
    CHECK(code_of("IERC20") == "6d01");
    CHECK(code_of("Lib.Data storage") == "6a6d01");
    CHECK(code_of("IERC20[2]") == "68026d01");
    CHECK(code_of("tuple") == "6d01");  // (without components: the text)
    CHECK(code_of("uint") == "6d01");
    CHECK(code_of("tuples") == "6d01");
    // what isn't a type exactly: refused (kept as text by the builder)
    for (std::string_view t : {"uint7"sv, "uint264"sv, "uint08"sv, "int0"sv, "bytes0"sv, "bytes33"sv,
                               "fixed0x1"sv, "fixed128x81"sv, " uint256"sv, "uint256 "sv,
                               "uint256[01]"sv, "uint256["sv, "uint256[]]"sv, "address payable"sv,
                               "(uint256"sv, "(uint256,)"sv, "uint256 storage memory"sv, ""sv,
                               "uint256[18446744073709551616]"sv, "a..b"sv})
        CHECK_MESSAGE(code_of(t) == "refused", t);
    CHECK(code_of("bytes32[18446744073709551615]") == "68ffffffffffffffffff015f");
    // nesting: the tuples written in tuples, 32 at most
    std::string deep = std::string(32, '(') + "uint8" + std::string(32, ')');
    CHECK(code_of(deep) != "refused");
    CHECK(code_of("(" + deep + ")") == "refused");
}

TEST_CASE("sigdb: a dump built and read back")
{
    Mini m;
    const sigdb::Database& db = *m.open;
    CHECK(m.stats.lines == 33);
    CHECK(db.size() == m.stats.entries);
    CHECK(db.file_size() == m.stats.file_size);
    CHECK(db.dump_sha256() == pan::sha256::hash(read_file(m.dump)));
    CHECK(db.dump_size() == fs::file_size(m.dump));
    CHECK(db.dump_path() == fs::canonical(m.dump));

    SUBCASE("well-known functions")
    {
        auto t = db.function(0xa9059cbb);
        REQUIRE(t);
        CHECK(t->selector() == 0xa9059cbb);
        CHECK(t->kind() == sigdb::Kind::function);
        CHECK(t->name() == "transfer");
        CHECK(t->signature() == "transfer(address,uint256)");
        CHECK(param_names(*t) == std::vector<std::string>{"to", "value"});
        CHECK(t->params()[0].type().kind() == sigdb::TypeKind::address);
        CHECK(t->params()[1].type().kind() == sigdb::TypeKind::uintN);
        CHECK(t->params()[1].type().bits() == 256);
        CHECK_FALSE(t->hashed_without_spaces());
        auto b = db.function(0x70a08231);
        REQUIRE(b);
        CHECK(b->kind() == sigdb::Kind::unspecified);
        CHECK(param_names(*b) == std::vector<std::string>{""});  // (python's _param1)
        CHECK(db.function(0x23b872dd)->signature() == "transferFrom(address,address,uint256)");
        CHECK(db.function(0x18160ddd)->signature() == "totalSupply()");
        CHECK(db.function(0x4e487b71)->kind() == sigdb::Kind::error);
        CHECK_FALSE(db.function(0x12345678));
        CHECK_FALSE(db.function(0));
        CHECK_FALSE(db.function(0xffffffff));
    }
    SUBCASE("the last line of a selector, if it hashes to it")
    {
        auto c = db.function(0x41973cd9);
        REQUIRE(c);
        CHECK(c->signature() == "f1121318093(bytes,bytes,uint64)");
        CHECK_FALSE(db.function(sel32("mint(address,uint256)")));
        auto burn = db.function(sel32("burn(uint256)"));
        REQUIRE(burn);
        CHECK(burn->signature() == "burn(uint256)");
        // "0xA9059CBB" isn't transfer's key
        CHECK(param_names(*db.function(0xa9059cbb)) == std::vector<std::string>{"to", "value"});
        // what python can't read isn't known
        CHECK_FALSE(db.function(sel32("notObject(uint256)")));
        CHECK_FALSE(db.function(sel32("notString(uint256)")));
        CHECK_FALSE(db.function(sel32("noInputs()")));
        CHECK_FALSE(db.function(sel32("lone()")));
        // keys given twice: the last
        CHECK(db.function(0x095ea7b3)->signature() == "approve(address,uint256)");
    }
    SUBCASE("without spaces")
    {
        auto g = db.function(0x0592ca9d);
        REQUIRE(g);
        CHECK(g->hashed_without_spaces());
        CHECK(g->signature() == "getMin(uint32[] storage)");
        sigdb::Type t = g->params()[0].type();
        CHECK(t.kind() == sigdb::TypeKind::storage);
        CHECK(t.element().kind() == sigdb::TypeKind::array);
        CHECK(t.element().element().bits() == 32);
        CHECK_FALSE(t.dynamic());
    }
    SUBCASE("tuples")
    {
        auto d = db.function(sel32("deposit((address,(uint8,bytes32)[])[2],string)"));
        REQUIRE(d);
        CHECK(d->signature() == "deposit((address,(uint8,bytes32)[])[2],string)");
        sigdb::Type orders = d->params()[0].type();
        CHECK(d->params()[0].name() == "orders");
        CHECK(orders.kind() == sigdb::TypeKind::static_array);
        CHECK(orders.length() == 2);
        CHECK(orders.text() == "(address,(uint8,bytes32)[])[2]");
        CHECK(orders.dynamic());
        sigdb::Type order = orders.element();
        REQUIRE(order.kind() == sigdb::TypeKind::tuple);
        REQUIRE(order.fields().size() == 2);
        CHECK(order.fields()[0].name() == "owner");
        CHECK(order.fields()[0].type().kind() == sigdb::TypeKind::address);
        CHECK(order.fields()[1].name() == "items");
        sigdb::Type item = order.fields()[1].type().element();
        REQUIRE(item.kind() == sigdb::TypeKind::tuple);
        std::vector<std::string> names;
        for (sigdb::Field f : item.fields())
            names.emplace_back(f.name());
        CHECK(names == std::vector<std::string>{"kind", "data"});
        CHECK(item.fields()[1].type().size() == 32);
        CHECK_FALSE(item.dynamic());
        CHECK(d->params()[1].type().kind() == sigdb::TypeKind::string);

        auto b = db.function(sel32("batch((uint256,address)[])"));
        REQUIRE(b);
        sigdb::Type calls = b->params()[0].type();
        CHECK(hex(calls.code()) == "676902001f0060");
        CHECK(calls.element().fields()[0].name().empty());

        auto e = db.function(sel32("e(())"));
        REQUIRE(e);
        CHECK(e->params()[0].type().kind() == sigdb::TypeKind::tuple);
        CHECK(e->params()[0].type().fields().empty());

        auto odd = db.function(sel32("odd((uint256)X)"));
        REQUIRE(odd);
        CHECK(odd->params()[0].type().kind() == sigdb::TypeKind::named);
        CHECK(odd->params()[0].type().name() == "(uint256)X");
    }
    SUBCASE("types known by their text")
    {
        auto f = db.function(sel32("f(uint)"));
        REQUIRE(f);
        CHECK(f->params()[0].type().kind() == sigdb::TypeKind::named);
        CHECK(f->params()[0].type().name() == "uint");
        auto p = db.function(sel32("pull(IERC20,uint256)"));
        REQUIRE(p);
        CHECK(p->params()[0].type().name() == "IERC20");
        auto r = db.function(sel32("setRate(fixed128x18)"));
        REQUIRE(r);
        CHECK(r->params()[0].type().kind() == sigdb::TypeKind::fixed);
        CHECK(r->params()[0].type().bits() == 128);
        CHECK(r->params()[0].type().decimals() == 18);
        CHECK(db.function(sel32("call(function)"))->params()[0].type().kind() ==
              sigdb::TypeKind::function);
        auto big = db.function(sel32("big(bytes32[1263941234127518272])"));
        REQUIRE(big);
        CHECK(big->params()[0].type().length() == 1263941234127518272u);
    }
    SUBCASE("names: raw bytes, escapes decoded")
    {
        auto n = db.function(0x5371ede7);
        REQUIRE(n);
        CHECK(n->name() == "na\xc3\xafve");
        CHECK(n->params()[0].name() == "v");
        auto s = db.function(0x34f68609);
        REQUIRE(s);
        CHECK(s->name() == "smile\xf0\x9f\x98\x80");
    }
    SUBCASE("the entries in order")
    {
        std::uint32_t prev = 0;
        for (std::size_t i = 0; i < db.size(); i++) {
            auto e = db.at(i);
            REQUIRE(e);
            CHECK((i == 0 || e->selector() > prev));
            prev = e->selector();
            CHECK(db.function(e->selector())->name() == e->name());
        }
        CHECK_FALSE(db.at(db.size()));
    }
}

TEST_CASE("sigdb: events")
{
    Mini m;
    const sigdb::Database& db = *m.open;
    auto topic = sigdb::keccak256("Transfer(address,address,uint256)");
    auto t = db.event(topic);
    REQUIRE(t);
    CHECK(t->kind() == sigdb::Kind::event);
    CHECK(hex(t->topic()) == hex(topic));
    CHECK(t->indexed(0));
    CHECK(t->indexed(1));
    CHECK_FALSE(t->indexed(2));
    CHECK_FALSE(t->indexed(3));
    CHECK(param_names(*t) == std::vector<std::string>{"from", "to", "value"});
    // python's fetch_sig by its 4 bytes: the event too
    CHECK(db.function(0xddf252ad)->name() == "Transfer");
    // the same 4 bytes, another topic: not that event
    auto other = topic;
    other[31] ^= 1;
    CHECK_FALSE(db.event(other));
    // python's truth for "indexed": 1, "yes" are; [] isn't
    auto a = db.event(sigdb::keccak256("Approval(address,address,uint256)"));
    REQUIRE(a);
    CHECK(a->indexed(0));
    CHECK(a->indexed(1));
    CHECK_FALSE(a->indexed(2));
    // a function isn't an event
    auto tr = sigdb::keccak256("transfer(address,uint256)");
    CHECK_FALSE(db.event(tr));
    CHECK(hex(db.function(0xa9059cbb)->topic()) == std::string(64, '0'));
}

TEST_CASE("sigdb: dumps it refuses")
{
    TempDir dir;
    auto fails = [&](std::string_view text, sigdb::Error::Code code, std::string_view why) {
        fs::path dump = dir.path / "d.xz";
        write_file(dump, xz(text));
        try {
            sigdb::build(dump, dir.path / "db.bin");
            FAIL("built: ", text);
        } catch (const sigdb::Error& e) {
            CHECK(e.code() == code);
            CHECK_MESSAGE(std::string(e.what()).find(why) != std::string::npos, e.what());
        }
        CHECK_FALSE(fs::exists(dir.path / "db.bin"));
    };
    std::string ok = line("0xa9059cbb", R"({"name": "transfer", "inputs": []})");
    fails(ok + "{\"selector\": \"0x12345678\", \"abi\": {]}\n", sigdb::Error::Code::failed,
          "line 2: not the JSON expected");
    fails(ok + ok + "{\"abi\": {}}\n", sigdb::Error::Code::failed, "line 3: no \"selector\"");
    fails("{\"selector\": \"0x12345678\"}\n", sigdb::Error::Code::failed, "line 1: no \"abi\"");
    fails("[1, 2]\n", sigdb::Error::Code::failed, "line 1");
    fails("{\"selector\": \"0x12345678\", \"abi\": {}} x\n", sigdb::Error::Code::failed, "line 1");
    fails("{\"selector\": \"0x\x01\"}\n", sigdb::Error::Code::failed, "line 1");  // (a control character)
    fails("{\"selector\": \"\xff\"}\n", sigdb::Error::Code::failed, "line 1");     // (not UTF-8)
    fails("{\"selector\": \"0x12345678\", \"abi\": " + std::string(2000, '[') + std::string(2000, ']') + "}\n",
          sigdb::Error::Code::bad_dump, "nested too deep");
    // not xz
    write_file(dir.path / "plain", ok);
    CHECK_THROWS_AS(sigdb::build(dir.path / "plain", dir.path / "db.bin"), sigdb::Error);
    CHECK_THROWS_AS(sigdb::build(dir.path / "none.xz", dir.path / "db.bin"), sigdb::Error);
    // the front-ends' codes
    Capture c;
    CHECK(pan::build_signature_db((dir.path / "none.xz").string(), (dir.path / "db.bin").string()) == 1);
    CHECK(c.count("40 can't read") == 1);
    write_file(dir.path / "deep.xz", xz("{\"selector\": \"0x12345678\", \"abi\": {\"x\": " +
                                        std::string(2000, '[') + std::string(2000, ']') + "}}\n"));
    CHECK(pan::build_signature_db((dir.path / "deep.xz").string(), (dir.path / "db.bin").string()) == -1);
    write_file(dir.path / "ok.xz", xz(ok));
    CHECK(pan::build_signature_db((dir.path / "ok.xz").string(), (dir.path / "db.bin").string()) == 0);
    CHECK(c.count("20 Loading") == 3);
    CHECK(c.count("is ready: 1 signatures") == 1);
}

TEST_CASE("sigdb: the file is checked")
{
    Mini m;
    std::string bytes = read_file(m.db);
    TempDir dir;
    fs::path f = dir.path / "copy.bin";
    auto refused = [&](const std::string& data) {
        write_file(f, data);
        CHECK_THROWS_AS(sigdb::Database::open(f), sigdb::Error);
    };
    refused(bytes.substr(0, bytes.size() - 1));  // cut short
    refused(bytes + "x");
    refused("");
    refused("PANSIGDB");
    std::string other = bytes;
    other[0] = 'X';
    refused(other);  // another format
    other = bytes;
    other[8] = 2;
    refused(other);  // another version
    // a record damaged: that entry unknown, the others as they were
    std::string damaged = bytes;
    std::size_t at = damaged.find("\x08transfer\x02");
    REQUIRE(at != std::string::npos);
    damaged[at - 1] = static_cast<char>(0xf0);
    write_file(f, damaged);
    auto db = sigdb::Database::open(f);
    CHECK_FALSE(db->function(0xa9059cbb));
    CHECK(db->function(0x23b872dd));
    // a type's code that isn't one
    damaged = bytes;
    at = damaged.find("\x0ctransferFrom\x03");
    REQUIRE(at != std::string::npos);
    REQUIRE(damaged[at + 15] == 0x60);  // (from: its name's reference, then address)
    damaged[at + 15] = 0x7e;
    write_file(f, damaged);
    db = sigdb::Database::open(f);
    CHECK_FALSE(db->function(0x23b872dd));
    CHECK(db->function(0xa9059cbb));
    CHECK_THROWS_AS(sigdb::Database::open(dir.path / "missing.bin"), sigdb::Error);
}

TEST_CASE("sigdb: built again when its dump changes")
{
    Capture c;
    TempDir dir;
    fs::path dump = dir.path / "abi_dump.xz", db = dir.path / "cache" / "sigdb1.bin";
    // none, no dump: nothing
    CHECK_FALSE(sigdb::load(db, std::nullopt));
    CHECK(c.count("30 no signature database") == 1);
    // none, a dump: built
    write_file(dump, xz(line("0xa9059cbb", R"({"name": "transfer", "inputs": [{"name": "to", "type": "address"}, {"name": "value", "type": "uint256"}]})")));
    auto d = sigdb::load(db, dump);
    REQUIRE(d);
    CHECK(d->function(0xa9059cbb));
    CHECK(c.count("20 Loading") == 1);
    // the same dump: kept
    d = sigdb::load(db, dump);
    REQUIRE(d);
    CHECK(c.count("20 Loading") == 1);
    d = sigdb::load(db, std::nullopt);  // (the dump it names)
    REQUIRE(d);
    CHECK(c.count("20 Loading") == 1);
    // the same bytes, touched: kept (its SHA-256)
    fs::last_write_time(dump, fs::last_write_time(dump) + std::chrono::seconds(5));
    d = sigdb::load(db, std::nullopt);
    REQUIRE(d);
    CHECK(c.count("20 Loading") == 1);
    // another dump: built again, from the dump it names
    write_file(dump, xz(line("0x70a08231", R"({"name": "balanceOf", "inputs": [{"name": "owner", "type": "address"}]})")));
    d = sigdb::load(db, std::nullopt);
    REQUIRE(d);
    CHECK(c.count("20 Loading") == 2);
    CHECK_FALSE(d->function(0xa9059cbb));
    CHECK(d->function(0x70a08231));
    // not a database: built again from the dump given, else nothing
    write_file(db, "not a database");
    CHECK_FALSE(sigdb::load(db, std::nullopt));
    CHECK(c.count("isn't a signature database") == 1);
    d = sigdb::load(db, dump);
    REQUIRE(d);
    CHECK(d->function(0x70a08231));
    // a dump that can't be built from: the database there was
    write_file(dump, "broken");
    d = sigdb::load(db, dump);
    REQUIRE(d);
    CHECK(d->function(0x70a08231));
    CHECK(c.count("40 ") >= 1);
}

#ifndef _WIN32
TEST_CASE("sigdb: the default path")
{
    const char* old = std::getenv("PANORAMIX_SIGDB");
    std::string saved = old ? old : "";
    ::setenv("PANORAMIX_SIGDB", "/some/where.bin", 1);
    CHECK(sigdb::default_path() == "/some/where.bin");
    ::unsetenv("PANORAMIX_SIGDB");
    fs::path p = sigdb::default_path();
    if (!p.empty())
        CHECK(p.filename() == "sigdb1.bin");
    if (old)
        ::setenv("PANORAMIX_SIGDB", saved.c_str(), 1);
}
#endif

TEST_CASE("sigdb: the real dump (PANORAMIX_TEST_ABI_DUMP)")
{
    const char* dump = std::getenv("PANORAMIX_TEST_ABI_DUMP");
    if (!dump || !*dump) {
        MESSAGE("PANORAMIX_TEST_ABI_DUMP not set: the real dump isn't tested");
        return;
    }
    TempDir dir;
    sigdb::BuildStats s = sigdb::build(dump, dir.path / "sigdb1.bin");
    auto db = sigdb::Database::open(dir.path / "sigdb1.bin");
    MESSAGE(s.lines, " lines, ", s.entries, " signatures, ", s.events, " events, ", s.file_size, " bytes");
    CHECK(db->size() == s.entries);
    struct Known {
        std::uint32_t selector;
        std::string_view signature;
    };
    for (Known k : {Known{0xa9059cbb, "transfer(address,uint256)"},
                    Known{0x23b872dd, "transferFrom(address,address,uint256)"},
                    Known{0x095ea7b3, "approve(address,uint256)"},
                    Known{0x70a08231, "balanceOf(address)"}, Known{0x18160ddd, "totalSupply()"},
                    Known{0xdd62ed3e, "allowance(address,address)"}}) {
        auto e = db->function(k.selector);
        REQUIRE(e);
        CHECK(e->signature() == k.signature);
    }
    for (std::string_view ev : {"Transfer(address,address,uint256)"sv,
                                "Approval(address,address,uint256)"sv}) {
        auto e = db->event(sigdb::keccak256(ev));
        REQUIRE(e);
        CHECK(e->signature() == ev);
    }
    // every entry hashes to its selector
    for (std::size_t i = 0; i < db->size(); i++) {
        auto e = db->at(i);
        REQUIRE(e);
        std::string text = e->signature();
        if (e->hashed_without_spaces())
            std::erase(text, ' ');
        auto h = sigdb::keccak256(text);
        REQUIRE((std::uint32_t{h[0]} << 24 | std::uint32_t{h[1]} << 16 | std::uint32_t{h[2]} << 8 | h[3]) ==
                e->selector());
    }
}
