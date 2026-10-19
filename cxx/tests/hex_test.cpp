// hex.hpp: hex text into bytes, bytes from outside escaped.
#include <doctest/doctest.h>

#include <cstdint>
#include <random>
#include <string>
#include <vector>

#include "hex.hpp"

using pan::hex::decode;
using pan::hex::escape;
using Bytes = std::vector<std::uint8_t>;

namespace {

Bytes ok(std::string_view text)
{
    const auto r = decode(text);
    REQUIRE_MESSAGE(r.has_value(), "not decoded: ", std::string(text));
    return *r;
}

pan::hex::DecodeError bad(std::string_view text)
{
    const auto r = decode(text);
    REQUIRE_MESSAGE(!r.has_value(), "decoded: ", std::string(text));
    return r.error();
}

std::string hex_of(const Bytes& bytes, bool upper)
{
    static constexpr char lower_digits[] = "0123456789abcdef", upper_digits[] = "0123456789ABCDEF";
    const char* digits = upper ? upper_digits : lower_digits;
    std::string s;
    for (const auto b : bytes) {
        s += digits[b >> 4];
        s += digits[b & 15];
    }
    return s;
}

}  // namespace

TEST_CASE("hex: bytes, a prefix, nothing")
{
    CHECK(ok("") == Bytes{});
    CHECK(ok("0x") == Bytes{});
    CHECK(ok("0X") == Bytes{});
    CHECK(ok("6080") == Bytes{0x60, 0x80});
    CHECK(ok("0x6080") == Bytes{0x60, 0x80});
    CHECK(ok("0XaBcD") == Bytes{0xab, 0xcd});
    CHECK(ok("00") == Bytes{0x00});
    CHECK(ok("0x00") == Bytes{0x00});
    CHECK(ok("0000") == Bytes{0x00, 0x00});
}

TEST_CASE("hex: blanks anywhere, before the prefix too")
{
    CHECK(ok(" \t\r\n0x60 80\n") == Bytes{0x60, 0x80});
    CHECK(ok("0x 60") == Bytes{0x60});
    CHECK(ok("6 0") == Bytes{0x60});      // (the asm's: a byte's digits apart)
    CHECK(ok("6\r\n\t0") == Bytes{0x60});
    CHECK(ok("\n") == Bytes{});
}

TEST_CASE("hex: what isn't")
{
    CHECK(bad("608").odd);
    CHECK(bad("0").odd);
    CHECK(bad("0x6").odd);
    CHECK(bad("6 ").odd);
    auto e = bad("60zz");
    CHECK_FALSE(e.odd);
    CHECK(e.offset == 2);
    CHECK(bad("0x0x60").offset == 3);   // (a prefix, at the beginning only)
    CHECK(bad("60 0x").offset == 4);
    CHECK(bad(" 0 x60").offset == 3);   // (the prefix's two letters together)
    CHECK(bad("\v6000").offset == 0);   // (blanks: space, tab, CR, LF)
    CHECK(bad("60\f").offset == 2);
    CHECK(bad(std::string_view("60\0" "00", 5)).offset == 2);
    CHECK(bad("\xc3\xa9").offset == 0);
    CHECK(bad("-").offset == 0);
}

TEST_CASE("hex: every byte, either case, round trip")
{
    Bytes all(256);
    for (int i = 0; i < 256; ++i)
        all[i] = static_cast<std::uint8_t>(i);
    CHECK(ok(hex_of(all, false)) == all);
    CHECK(ok(hex_of(all, true)) == all);
    CHECK(ok("0x" + hex_of(all, true)) == all);
    std::mt19937 random(7);
    Bytes big(1 << 20);
    for (auto& b : big)
        b = static_cast<std::uint8_t>(random());
    CHECK(ok(hex_of(big, false)) == big);
}

TEST_CASE("escape: printable ASCII kept, the rest as \\xNN")
{
    CHECK(escape("abc ~") == "abc ~");
    CHECK(escape("a\\b") == "a\\x5cb");
    CHECK(escape("\x1b]0;pwned\x07") == "\\x1b]0;pwned\\x07");
    CHECK(escape("line\r\nforged") == "line\\x0d\\x0aforged");
    CHECK(escape(std::string_view("\0\x7f\x80\xff", 4)) == "\\x00\\x7f\\x80\\xff");
    CHECK(escape("") == "");
}

TEST_CASE("escape: an excerpt")
{
    CHECK(escape("abcdef", 3) == "abc");
    CHECK(escape("\n\n\n\n", 2) == "\\x0a\\x0a");
    CHECK(escape("abc", 0) == "");
    CHECK(escape(std::string(100000, 'z'), 200).size() == 200);
}
