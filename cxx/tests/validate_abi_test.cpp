// validate/abi_encode.hpp: the types read from the signature database's
// codes, the ABI encoding (the specification's examples), the generated
// calls (deterministic, well-formed but for the malformed share, the values
// that exercise the branches), the encoder of a database as the call
// generator's hook; evm_runner.hpp's count of the instructions, evmrun's
// options of the typed calls.
#include "validate/abi_encode.hpp"
#include "validate/evm_runner.hpp"
#include "validate/scan.hpp"

#include "sigdb.hpp"

#include "validate_test_util.hpp"

#include <lzma.h>

#include <algorithm>
#include <atomic>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <functional>
#include <map>
#include <random>
#include <set>
#include <string>
#include <string_view>

using namespace validate;
namespace fs = std::filesystem;
using K = AbiType::Kind;

namespace
{
// --- helpers ---

BytesView text_bytes(std::string_view s)
{
    return {reinterpret_cast<const std::uint8_t*>(s.data()), s.size()};
}

std::uint32_t selector_of(std::string_view signature)
{
    return static_cast<std::uint32_t>(keccak256(text_bytes(signature)) >> 224);
}

Bytes bytes_of(std::string_view s)
{
    const auto b = text_bytes(s);
    return {b.begin(), b.end()};
}

/// s left-aligned in a word (a bytes<N>).
Word left(std::string_view s)
{
    std::uint8_t b[32]{};
    std::copy(s.begin(), s.end(), b);
    return load_word(b, 0);
}

AbiType type(std::string_view code_hex)
{
    const auto code = parse_hex(code_hex);
    REQUIRE(code);
    auto t = AbiType::from_code(*code);
    REQUIRE_MESSAGE(t, code_hex);
    return std::move(*t);
}

bool refused(std::string_view code_hex)
{
    return !AbiType::from_code(*parse_hex(code_hex));
}

/// The parameters of a function, from their codes.
AbiType params(std::initializer_list<std::string_view> codes)
{
    std::vector<AbiType> fields;
    for (const auto c : codes)
        fields.push_back(type(c));
    return AbiType::tuple(std::move(fields));
}

AbiValue list(std::vector<AbiValue> v)
{
    return AbiValue{std::move(v)};
}

Bytes call_data(std::uint32_t selector, const Bytes& args)
{
    Bytes out{static_cast<std::uint8_t>(selector >> 24), static_cast<std::uint8_t>(selector >> 16),
        static_cast<std::uint8_t>(selector >> 8), static_cast<std::uint8_t>(selector)};
    out.insert(out.end(), args.begin(), args.end());
    return out;
}

// --- a strict decoder: the reference of the round trips ---

/// The value of a type whose encoding starts at `at` (a tuple's: what its
/// offsets are relative to), every word of its type's range, every part in
/// the data; nullopt otherwise.
class Decoder
{
public:
    explicit Decoder(BytesView data) : data_{data} {}

    std::optional<AbiValue> value(const AbiType& t, std::size_t at)
    {
        switch (t.kind())
        {
        case K::bytes:
        case K::string:
        {
            const auto n = word(at);
            if (!n || *n > data_.size())
                return std::nullopt;
            const auto len = static_cast<std::size_t>(*n);
            const auto padded = (len + 31) / 32 * 32;
            if (at + 32 + padded > data_.size())
                return std::nullopt;
            for (auto i = at + 32 + len; i < at + 32 + padded; ++i)
                if (data_[i] != 0)
                    return std::nullopt;
            return Bytes(data_.begin() + static_cast<std::ptrdiff_t>(at + 32),
                data_.begin() + static_cast<std::ptrdiff_t>(at + 32 + len));
        }
        case K::array:
        {
            const auto n = word(at);
            if (!n || *n > 100'000 ||
                *n * std::max<std::uint64_t>(t.element().head_size(), 1) > data_.size())
                return std::nullopt;
            return sequence([&](std::size_t) -> const AbiType& { return t.element(); },
                static_cast<std::size_t>(*n), at + 32);
        }
        case K::static_array:
            return sequence([&](std::size_t) -> const AbiType& { return t.element(); },
                static_cast<std::size_t>(t.length()), at);
        case K::tuple:
            return sequence([&](std::size_t i) -> const AbiType& { return t.fields()[i]; },
                t.fields().size(), at);
        default:
        {
            const auto w = word(at);
            if (!w || !in_range(t, *w))
                return std::nullopt;
            return *w;
        }
        }
    }

    static bool in_range(const AbiType& t, const Word& w)
    {
        switch (t.kind())
        {
        case K::uint_n:
            return t.bits() == 256 || w >> t.bits() == 0;
        case K::int_n:
        {
            if (t.bits() == 256)
                return true;
            const auto high = w >> (t.bits() - 1);  // the sign and above: all 0 or all 1
            return high == 0 || high == (~Word{0} >> (t.bits() - 1));
        }
        case K::address:
            return w <= address_mask;
        case K::boolean:
            return w <= 1;
        case K::bytes_n:
            return t.size() == 32 || (w << (8 * t.size())) == 0;
        case K::function:
            return (w << 192) == 0;
        default:
            return true;
        }
    }

private:
    std::optional<Word> word(std::size_t at) const
    {
        if (at + 32 > data_.size())
            return std::nullopt;
        return load_word(data_, at);
    }

    template <class TypeAt>
    std::optional<AbiValue> sequence(TypeAt type_at, std::size_t n, std::size_t start)
    {
        std::vector<AbiValue> out;
        auto head = start;
        for (std::size_t i = 0; i < n; ++i)
        {
            const AbiType& t = type_at(i);
            std::optional<AbiValue> v;
            if (t.dynamic())
            {
                const auto offset = word(head);
                if (!offset || *offset >= data_.size())
                    return std::nullopt;
                v = value(t, start + static_cast<std::size_t>(*offset));
                head += 32;
            }
            else
            {
                v = value(t, head);
                head += static_cast<std::size_t>(t.head_size());
            }
            if (!v)
                return std::nullopt;
            out.push_back(std::move(*v));
        }
        return AbiValue{std::move(out)};
    }

    BytesView data_;
};

/// The arguments of calldata, decoded, if they are the canonical encoding
/// of values of the types (decoded, then encoded again: the same bytes).
std::optional<AbiValue> canonical(const AbiType& params, const Bytes& calldata)
{
    if (calldata.size() < 4)
        return std::nullopt;
    const BytesView args{calldata.data() + 4, calldata.size() - 4};
    auto v = Decoder{args}.value(params, 0);
    if (!v)
        return std::nullopt;
    const auto again = abi_encode(params, *v);
    if (!again || !std::ranges::equal(*again, args))
        return std::nullopt;
    return v;
}

const std::vector<AbiValue>& items(const AbiValue& v)
{
    return std::get<std::vector<AbiValue>>(v.value);
}

const Word& word_of(const AbiValue& v)
{
    return std::get<Word>(v.value);
}

// --- a signature database of a few entries ---

std::string xz(std::string_view text)
{
    std::string out(text.size() + text.size() / 2 + 4096, '\0');
    std::size_t pos = 0;
    const auto r = lzma_easy_buffer_encode(6, LZMA_CHECK_CRC64,
        nullptr, reinterpret_cast<const std::uint8_t*>(text.data()), text.size(),
        reinterpret_cast<std::uint8_t*>(out.data()), &pos, out.size());
    REQUIRE(r == LZMA_OK);
    out.resize(pos);
    return out;
}

std::string dump_line(std::string_view signature, std::string_view abi)
{
    char sel[16];
    std::snprintf(sel, sizeof sel, "0x%08x", selector_of(signature));
    return "{\"selector\": \"" + std::string{sel} + "\", \"abi\": " + std::string{abi} + "}\n";
}

struct MiniDb
{
    fs::path dir;
    std::unique_ptr<pan::sigdb::Database> db;

    MiniDb()
    {
        static std::atomic<int> n{0};
        dir = fs::temp_directory_path() /
              ("validate_abi_test." + std::to_string(std::random_device{}()) + "." + std::to_string(n++));
        fs::remove_all(dir);
        fs::create_directories(dir);
        std::string d;
        d += dump_line("transfer(address,uint256)",
            R"({"name": "transfer", "type": "function", "inputs": [{"name": "to", "type": "address"}, {"name": "value", "type": "uint256"}]})");
        d += dump_line("deposit((address,(uint8,bytes32)[])[2],string)",
            R"({"name": "deposit", "inputs": [{"name": "orders", "type": "tuple[2]", "components": [{"name": "owner", "type": "address"}, {"name": "items", "type": "tuple[]", "components": [{"name": "kind", "type": "uint8"}, {"name": "data", "type": "bytes32"}]}]}, {"name": "memo", "type": "string"}]})");
        d += dump_line("pull(IERC20,uint256)",
            R"({"name": "pull", "inputs": [{"name": "token", "type": "IERC20"}, {"name": "amount", "type": "uint256"}]})");
        d += dump_line("totalSupply()", R"({"name": "totalSupply", "inputs": []})");
        d += dump_line("big(bytes32[1263941234127518272])",
            R"({"name": "big", "inputs": [{"name": "b", "type": "bytes32[1263941234127518272]"}]})");
        d += dump_line("Transfer(address,address,uint256)",
            R"({"name": "Transfer", "type": "event", "inputs": [{"name": "from", "type": "address", "indexed": true}, {"name": "to", "type": "address", "indexed": true}, {"name": "value", "type": "uint256"}]})");
        const auto dump = dir / "abi_dump.xz";
        {
            std::ofstream f{dump, std::ios::binary};
            const auto z = xz(d);
            f.write(z.data(), static_cast<std::streamsize>(z.size()));
        }
        pan::sigdb::build(dump, dir / "sigdb1.bin");
        db = pan::sigdb::Database::open(dir / "sigdb1.bin");
    }

    ~MiniDb()
    {
        db.reset();
        std::error_code ec;
        fs::remove_all(dir, ec);
    }
};
}  // namespace

TEST_CASE("validate: the ABI types of the database's codes")
{
    // elementary: one byte
    CHECK(type("00").kind() == K::uint_n);
    CHECK(type("00").bits() == 8);
    CHECK(type("1f").bits() == 256);
    CHECK(type("20").kind() == K::int_n);
    CHECK(type("20").bits() == 8);
    CHECK(type("3f").bits() == 256);
    CHECK(type("40").kind() == K::bytes_n);
    CHECK(type("40").size() == 1);
    CHECK(type("5f").size() == 32);
    CHECK(type("60").kind() == K::address);
    CHECK(type("61").kind() == K::boolean);
    CHECK(type("62").kind() == K::string);
    CHECK(type("63").kind() == K::bytes);
    CHECK(type("64").kind() == K::function);
    // fixed<M>x<N>: an int<M>; ufixed: a uint<M>
    CHECK(type("650f12").kind() == K::int_n);
    CHECK(type("650f12").bits() == 128);
    CHECK(type("660000").kind() == K::uint_n);
    CHECK(type("660000").bits() == 8);
    // arrays, the outer dimension first
    CHECK(type("671f").kind() == K::array);
    CHECK(type("671f").element().bits() == 256);
    CHECK(type("6768021f").element().kind() == K::static_array);
    CHECK(type("6768021f").element().length() == 2);
    CHECK(type("6803671f").length() == 3);
    // tuples: the fields' names (string references) skipped
    const auto t = type("690205" "1f" "8001" "6760");
    REQUIRE(t.kind() == K::tuple);
    REQUIRE(t.fields().size() == 2);
    CHECK(t.fields()[0].bits() == 256);
    CHECK(t.fields()[1].element().kind() == K::address);
    CHECK(type("6900").fields().empty());
    // a library's reference to storage: a slot; memory, calldata: the type
    CHECK(type("6a6703").kind() == K::word);
    CHECK(type("6b00").kind() == K::uint_n);
    CHECK(type("6c63").kind() == K::bytes);
    // a named type (a contract, an enum, a struct): a word
    CHECK(type("6d01").kind() == K::word);
    CHECK(type("68026d8101").element().kind() == K::word);

    // static or dynamic, the sizes of the heads
    CHECK_FALSE(type("1f").dynamic());
    CHECK(type("1f").head_size() == 32);
    CHECK(type("63").dynamic());
    CHECK(type("63").head_size() == 32);
    CHECK(type("671f").dynamic());
    CHECK(type("68031f").head_size() == 96);
    CHECK_FALSE(type("68031f").dynamic());
    CHECK(type("680362").dynamic());   // string[3]
    CHECK(type("680362").min_size() == 3 * 64);
    CHECK(type("6902001f0060").head_size() == 64);
    CHECK(type("6902001f0063").dynamic());
    CHECK(type("6900").head_size() == 0);
    CHECK(type("6800671f").dynamic());  // uint256[][0]: dynamic, empty
    CHECK(type("6800671f").min_size() == 0);
    CHECK(type("6a68ffffffff0f1f").kind() == K::word);  // (a slot: whatever its type's size)

    // not codes, cut short, too large to encode
    CHECK(refused(""));
    CHECK(refused("67"));
    CHECK(refused("6802"));
    CHECK(refused("650f"));
    CHECK(refused("652012"));  // fixed264x18
    CHECK(refused("6e"));
    CHECK(refused("ff"));
    CHECK(refused("1f1f"));  // two types
    CHECK(refused("6902001f"));
    CHECK(refused("6d"));
    CHECK(refused("68c0f48ea9b1fb9ac5115f"));  // bytes32[1263941234127518272]
    CHECK(refused("68ffffffffffffffffff015f"));
    CHECK_FALSE(refused("6880101f"));  // uint256[2048]: 64 KiB
    CHECK(refused("6881101f"));        // uint256[2049]
    std::string deep(130, '6');
    for (std::size_t i = 1; i < deep.size(); i += 2)
        deep[i] = '7';
    CHECK_FALSE(refused(deep.substr(0, 2 * 60) + "1f"));  // uint256[]...[]: 60 deep
    CHECK(refused(deep + "1f"));                          // 65
}

TEST_CASE("validate: the ABI encoding: the specification's examples")
{
    const auto expect = [](std::string_view signature, const AbiType& types, const AbiValue& values,
                            std::string_view hex) {
        const auto args = abi_encode(types, values);
        REQUIRE(args);
        CHECK_MESSAGE(call_data(selector_of(signature), *args) == *parse_hex(hex), signature);
        // the reference decoder reads it back
        CHECK(canonical(types, call_data(0, *args)));
    };
    CHECK(selector_of("baz(uint32,bool)") == 0xcdcd77c0);
    CHECK(selector_of("bar(bytes3[2])") == 0xfce353f6);
    CHECK(selector_of("sam(bytes,bool,uint256[])") == 0xa5643bf2);
    CHECK(selector_of("f(uint256,uint32[],bytes10,bytes)") == 0x8be65246);
    CHECK(selector_of("g(uint256[][],string[])") == 0x2289b18c);
    CHECK(selector_of("transfer(address,uint256)") == 0xa9059cbb);

    expect("baz(uint32,bool)", params({"03", "61"}), list({Word{69}, Word{1}}),
        "0xcdcd77c0"
        "0000000000000000000000000000000000000000000000000000000000000045"
        "0000000000000000000000000000000000000000000000000000000000000001");
    expect("bar(bytes3[2])", params({"680242"}), list({list({left("abc"), left("def")})}),
        "0xfce353f6"
        "6162630000000000000000000000000000000000000000000000000000000000"
        "6465660000000000000000000000000000000000000000000000000000000000");
    expect("sam(bytes,bool,uint256[])", params({"63", "61", "671f"}),
        list({bytes_of("dave"), Word{1}, list({Word{1}, Word{2}, Word{3}})}),
        "0xa5643bf2"
        "0000000000000000000000000000000000000000000000000000000000000060"
        "0000000000000000000000000000000000000000000000000000000000000001"
        "00000000000000000000000000000000000000000000000000000000000000a0"
        "0000000000000000000000000000000000000000000000000000000000000004"
        "6461766500000000000000000000000000000000000000000000000000000000"
        "0000000000000000000000000000000000000000000000000000000000000003"
        "0000000000000000000000000000000000000000000000000000000000000001"
        "0000000000000000000000000000000000000000000000000000000000000002"
        "0000000000000000000000000000000000000000000000000000000000000003");
    expect("f(uint256,uint32[],bytes10,bytes)", params({"1f", "6703", "49", "63"}),
        list({Word{0x123}, list({Word{0x456}, Word{0x789}}), left("1234567890"), bytes_of("Hello, world!")}),
        "0x8be65246"
        "0000000000000000000000000000000000000000000000000000000000000123"
        "0000000000000000000000000000000000000000000000000000000000000080"
        "3132333435363738393000000000000000000000000000000000000000000000"
        "00000000000000000000000000000000000000000000000000000000000000e0"
        "0000000000000000000000000000000000000000000000000000000000000002"
        "0000000000000000000000000000000000000000000000000000000000000456"
        "0000000000000000000000000000000000000000000000000000000000000789"
        "000000000000000000000000000000000000000000000000000000000000000d"
        "48656c6c6f2c20776f726c642100000000000000000000000000000000000000");
    expect("g(uint256[][],string[])", params({"67671f", "6762"}),
        list({list({list({Word{1}, Word{2}}), list({Word{3}})}),
            list({bytes_of("one"), bytes_of("two"), bytes_of("three")})}),
        "0x2289b18c"
        "0000000000000000000000000000000000000000000000000000000000000040"
        "0000000000000000000000000000000000000000000000000000000000000140"
        "0000000000000000000000000000000000000000000000000000000000000002"
        "0000000000000000000000000000000000000000000000000000000000000040"
        "00000000000000000000000000000000000000000000000000000000000000a0"
        "0000000000000000000000000000000000000000000000000000000000000002"
        "0000000000000000000000000000000000000000000000000000000000000001"
        "0000000000000000000000000000000000000000000000000000000000000002"
        "0000000000000000000000000000000000000000000000000000000000000001"
        "0000000000000000000000000000000000000000000000000000000000000003"
        "0000000000000000000000000000000000000000000000000000000000000003"
        "0000000000000000000000000000000000000000000000000000000000000060"
        "00000000000000000000000000000000000000000000000000000000000000a0"
        "00000000000000000000000000000000000000000000000000000000000000e0"
        "0000000000000000000000000000000000000000000000000000000000000003"
        "6f6e650000000000000000000000000000000000000000000000000000000000"
        "0000000000000000000000000000000000000000000000000000000000000003"
        "74776f0000000000000000000000000000000000000000000000000000000000"
        "0000000000000000000000000000000000000000000000000000000000000005"
        "7468726565000000000000000000000000000000000000000000000000000000");
    expect("transfer(address,uint256)", params({"60", "1f"}),
        list({*parse_number("0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed"), Word{1'000'000'000'000'000'000ULL}}),
        "0xa9059cbb"
        "0000000000000000000000005aaeb6053f3e94c9b9a09f33669435e7ef1beaed"
        "0000000000000000000000000000000000000000000000000de0b6b3a7640000");

    // a dynamic tuple, int<N> sign-extended (the words as given), bytes of 32
    expect("h((int8,bytes),bytes32[])", params({"690200200063", "675f"}),
        list({list({~Word{0}, Bytes(32, 0xab)}), list({})}),
        "0x1f7fffd2"
        "0000000000000000000000000000000000000000000000000000000000000040"
        "00000000000000000000000000000000000000000000000000000000000000c0"
        "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
        "0000000000000000000000000000000000000000000000000000000000000040"
        "0000000000000000000000000000000000000000000000000000000000000020"
        "abababababababababababababababababababababababababababababababab"
        "0000000000000000000000000000000000000000000000000000000000000000");
    // a static tuple inline; a function: an address, then a selector
    expect("k((uint8,address),function)", params({"690200000060", "64"}),
        list({list({Word{7}, Word{0xbeef}}),
            *parse_number("0x1122334455667788990011223344556677889900aabbccdd0000000000000000")}),
        "0xd3a9f7c5"
        "0000000000000000000000000000000000000000000000000000000000000007"
        "000000000000000000000000000000000000000000000000000000000000beef"
        "1122334455667788990011223344556677889900aabbccdd0000000000000000");
    expect("totalSupply()", params({}), list({}), "0x18160ddd");

    // values not of the types' shapes
    CHECK_FALSE(abi_encode(params({"1f"}), list({bytes_of("x")})));
    CHECK_FALSE(abi_encode(params({"1f"}), list({})));
    CHECK_FALSE(abi_encode(params({"680242"}), list({list({left("abc")})})));
    CHECK_FALSE(abi_encode(params({"63"}), list({Word{1}})));
    CHECK_FALSE(abi_encode(params({"671f"}), list({Word{1}})));
}

TEST_CASE("validate: the typed calls: deterministic, well-formed but the malformed ones")
{
    const SeededWorld world{{.seed = 11}};
    // f(uint8,int16,address,bool,bytes4,uint256[],string,bytes,(uint32,bytes)[2],
    //   int256[][],function,IERC20,uint64,bytes32)
    const auto p = params({"00", "21", "60", "61", "43", "671f", "62", "63", "6802690200030063",
        "67673f", "64", "6d01", "07", "5f"});
    const auto a = abi_call(0x12345678, p, 2, world);
    CHECK(abi_call(0x12345678, p, 2, world).calldata == a.calldata);
    CHECK(abi_call(0x12345678, p, 3, world).calldata != a.calldata);
    CHECK(abi_call(0x12345679, p, 2, world).calldata != a.calldata);
    CHECK(abi_call(0x12345678, p, 2, SeededWorld{{.seed = 12}}).calldata != a.calldata);
    CHECK((load_word(a.calldata, 0) >> 224) == 0x12345678);

    unsigned calls = 0, malformed = 0;
    std::map<Malformation, unsigned> kinds;
    std::set<Word> u8, i16, addresses, bools, u64;
    std::set<std::size_t> array_lengths, string_lengths, bytes_lengths;
    bool letters = true;
    for (std::uint32_t s = 0; s < 400; ++s)
        for (unsigned v = 0; v < 4; ++v)
        {
            const auto c = abi_call(0xab000000 + s, p, v, world);
            ++calls;
            const auto decoded = canonical(p, c.calldata);
            // well-formed exactly when not malformed
            CHECK_MESSAGE((c.malformation == Malformation::none) == decoded.has_value(),
                hex(c.calldata), " ", static_cast<int>(c.malformation));
            if (c.malformation != Malformation::none)
            {
                ++malformed;
                ++kinds[c.malformation];
                continue;
            }
            if (!decoded)
                continue;
            const auto& args = items(*decoded);
            REQUIRE(args.size() == 14);
            u8.insert(word_of(args[0]));
            i16.insert(word_of(args[1]));
            addresses.insert(word_of(args[2]));
            bools.insert(word_of(args[3]));
            array_lengths.insert(items(args[5]).size());
            const auto& str = std::get<Bytes>(args[6].value);
            string_lengths.insert(str.size());
            for (const auto ch : str)
                letters = letters && ((ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9'));
            bytes_lengths.insert(std::get<Bytes>(args[7].value).size());
            u64.insert(word_of(args[12]));
            if (v == 0)
            {
                // the plainest: no zero address, short arrays
                CHECK(word_of(args[2]) != 0);
                CHECK(items(args[5]).size() >= 1);
                CHECK(items(args[5]).size() <= 3);
            }
        }
    // the share of the malformed calls, every kind of them
    CHECK(malformed * 100 >= calls * 7);
    CHECK(malformed * 100 <= calls * 13);
    CHECK(kinds[Malformation::out_of_range] > 0);
    CHECK(kinds[Malformation::short_data] > 0);
    CHECK(kinds[Malformation::bad_offset] > 0);
    CHECK(kinds[Malformation::bad_length] > 0);

    // the values of the branches
    const auto has = [](const std::set<Word>& s, const Word& w) { return s.contains(w); };
    CHECK(has(u8, 0));
    CHECK(has(u8, 1));
    CHECK(has(u8, 255));
    CHECK(has(u8, 254));
    CHECK(has(u8, 128));
    CHECK(has(i16, 0));
    CHECK(has(i16, ~Word{0}));               // -1
    CHECK(has(i16, 0x7fff));                 // max
    CHECK(has(i16, ~Word{0} << 15));         // min, sign-extended
    CHECK(has(addresses, 0));
    CHECK(has(addresses, world.contract_address()));
    for (const auto& actor : world.actors())
        CHECK(has(addresses, actor));
    CHECK(bools == std::set<Word>{0, 1});
    CHECK(has(u64, (Word{1} << 64) - 1));
    CHECK(has(u64, world.block().timestamp));
    for (const std::size_t n : {0, 1, 2, 3})
        CHECK(array_lengths.contains(n));
    for (const std::size_t n : {0, 1, 31, 32, 33, 64})
    {
        CHECK(bytes_lengths.contains(n));
        CHECK(string_lengths.contains(n));
    }
    CHECK(*bytes_lengths.rbegin() > 128);
    CHECK(letters);
}

TEST_CASE("validate: the typed calls: the malformed shares")
{
    const SeededWorld world{{.seed = 3}};
    const auto transfer = params({"60", "1f"});
    const auto count = [&](const AbiType& p, unsigned percent) {
        unsigned n = 0;
        for (std::uint32_t s = 0; s < 500; ++s)
            n += abi_call(s, p, s % 4, world, {.malformed_percent = percent}).malformation != Malformation::none;
        return n;
    };
    CHECK(count(transfer, 0) == 0);
    CHECK(count(transfer, 100) == 500);
    const auto ten = count(transfer, 10);
    CHECK(ten >= 30);
    CHECK(ten <= 70);
    // no parameters: nothing to malform, the selector only
    CHECK(count(params({}), 100) == 0);
    CHECK(abi_call(0xaabbccdd, params({}), 1, world, {.malformed_percent = 100}).calldata ==
          Bytes{0xaa, 0xbb, 0xcc, 0xdd});

    // what each kind does, on transfer(address,uint256) (no offsets, no
    // lengths: out of range or short) and on bytes, uint256[] (all four)
    const auto dyn = params({"63", "671f"});
    for (std::uint32_t s = 0; s < 300; ++s)
    {
        const auto c = abi_call(s, transfer, 1, world, {.malformed_percent = 100});
        CHECK(c.malformation != Malformation::bad_offset);
        CHECK(c.malformation != Malformation::bad_length);
        if (c.malformation == Malformation::out_of_range)
        {
            REQUIRE(c.calldata.size() == 68);
            CHECK(load_word(c.calldata, 4) > address_mask);  // the address: the only narrow one
        }
        if (c.malformation == Malformation::short_data)
        {
            CHECK(c.calldata.size() < 68);
            CHECK(c.calldata.size() >= 4);
        }
        const auto d = abi_call(s, dyn, 1, world, {.malformed_percent = 100});
        const auto good = abi_call(s, dyn, 1, world, {.malformed_percent = 0});
        CHECK_FALSE(canonical(dyn, d.calldata));
        REQUIRE(canonical(dyn, good.calldata));
        if (d.malformation == Malformation::bad_offset || d.malformation == Malformation::bad_length)
        {
            // one word changed: an offset (word 0, 1) or a length
            REQUIRE(d.calldata.size() == good.calldata.size());
            unsigned changed = 0;
            for (std::size_t at = 4; at < d.calldata.size(); at += 32)
                changed += load_word(d.calldata, at) != load_word(good.calldata, at);
            CHECK(changed == 1);
            if (d.malformation == Malformation::bad_offset)
                CHECK((load_word(d.calldata, 4) != load_word(good.calldata, 4) ||
                       load_word(d.calldata, 36) != load_word(good.calldata, 36)));
        }
    }
}

TEST_CASE("validate: the instructions and the gas of a call")
{
    const SeededWorld world{{.seed = 1}};
    const auto code = *parse_hex("0x600160020100");  // PUSH1 1 PUSH1 2 ADD STOP
    EvmRunner runner{code};
    State state{world, world.contract_address(), code};
    CHECK(runner.run(state, CallContext{}).end.status == Status::stop);
    CHECK(runner.cost().instructions == 0);  // not counted
    CHECK(runner.cost().gas == 9);
    runner.options().count_instructions = true;
    CHECK(runner.run(state, CallContext{}).end.status == Status::stop);
    CHECK(runner.cost().instructions == 4);
    CHECK(runner.cost().gas == 9);
    // the code's end: the padding's STOP isn't one of its instructions
    EvmRunner short_code{*parse_hex("0x6001600201"), {.count_instructions = true}};
    State state2{world, world.contract_address(), short_code.code()};
    CHECK(short_code.run(state2, CallContext{}).end.status == Status::stop);
    CHECK(short_code.cost().instructions == 3);
    runner.options().count_instructions = false;
    CHECK(runner.run(state, CallContext{}).end.status == Status::stop);
    CHECK(runner.cost().instructions == 0);
}

TEST_CASE("validate: evmrun's options of the typed calls")
{
    CHECK(evmrun_option("--sigdb") == EvmrunOption::sigdb);
    CHECK(evmrun_option("--untyped") == EvmrunOption::untyped);
    CHECK(evmrun_option("--malformed") == EvmrunOption::malformed);
    CHECK(evmrun_option("--count") == EvmrunOption::count);
    CHECK(evmrun_option("--corpus") == EvmrunOption::corpus);
    CHECK(evmrun_option("--compare") == EvmrunOption::compare);
    CHECK(evmrun_option("--counts") == EvmrunOption::none);
    CHECK(evmrun_option("--typed") == EvmrunOption::none);
}

TEST_CASE("validate: the typed calls of a signature database")
{
    MiniDb m;
    REQUIRE(m.db);
    const AbiEncoder encoder{*m.db};
    const SeededWorld world{{.seed = 5}};
    const auto transfer = selector_of("transfer(address,uint256)");
    const auto deposit = selector_of("deposit((address,(uint8,bytes32)[])[2],string)");
    CHECK(encoder.knows(transfer));
    CHECK(encoder.knows(deposit));
    CHECK(encoder.knows(selector_of("pull(IERC20,uint256)")));
    CHECK(encoder.knows(selector_of("totalSupply()")));
    CHECK_FALSE(encoder.knows(selector_of("big(bytes32[1263941234127518272])")));  // too large
    CHECK_FALSE(encoder.knows(selector_of("Transfer(address,address,uint256)")));  // an event
    CHECK_FALSE(encoder.knows(0x11223344));
    CHECK_FALSE(encoder(0x11223344, 1, world));

    // the parameters as the database has them
    const auto p = encoder.params(deposit);
    REQUIRE(p);
    REQUIRE(p->fields().size() == 2);
    const auto& orders = p->fields()[0];
    CHECK(orders.kind() == K::static_array);
    CHECK(orders.length() == 2);
    CHECK(orders.element().fields()[1].kind() == K::array);
    CHECK(orders.element().fields()[1].element().fields()[1].kind() == K::bytes_n);
    CHECK(p->fields()[1].kind() == K::string);
    for (unsigned v = 0; v < 8; ++v)
    {
        const auto c = abi_call(deposit, *p, v, world, encoder.config());
        CHECK(*encoder(deposit, v, world) == c.calldata);
        CHECK((c.malformation == Malformation::none) == canonical(*p, c.calldata).has_value());
    }
    CHECK(*encoder(selector_of("totalSupply()"), 2, world) == Bytes{0x18, 0x16, 0x0d, 0xdd});

    // as the call generator's hook: the known selector typed, the other one
    // the generator's words
    const auto code = *parse_hex("0x60003560e01c" "8063a9059cbb1461001057" "8063112233441461002057" "00");
    const CallGenerator untyped{world, code};
    CallGenerator typed{world, code};
    typed.set_encoder(encoder);
    REQUIRE(typed.selectors() == std::vector<std::uint32_t>{transfer, 0x11223344});
    const auto a = untyped.calls(), b = typed.calls();
    REQUIRE(a.size() == b.size());
    const auto tp = params({"60", "1f"});
    for (std::size_t i = 0; i < a.size(); ++i)
    {
        CHECK(a[i].context.caller == b[i].context.caller);
        if (b[i].selector == transfer)
        {
            CHECK(b[i].context.calldata == abi_call(transfer, tp, b[i].variant, world).calldata);
            CHECK((load_word(b[i].context.calldata, 0) >> 224) == transfer);
        }
        else
            CHECK(a[i].context.calldata == b[i].context.calldata);
    }
}
