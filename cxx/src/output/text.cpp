// The printer's text: python's colors (helpers.C), python's numbers
// (str, hex, padded_hex, prettify.pretty_num) - integers only.
#include <string>

#include "output/print.hpp"

namespace pan::output::detail {

std::string_view col_code(Col c) noexcept
{
    switch (c) {
        case Col::header: return "\033[95m";
        case Col::blue: return "\033[94m";
        case Col::okgreen: return "\033[92m";
        case Col::warning: return "\033[93m";
        case Col::fail: return "\033[91m";
        case Col::bold: return "\033[1m";
        case Col::underline: return "\033[4m";
        case Col::green: return "\033[32m";
        case Col::gray: return "\033[38;5;8m";
        case Col::asm_code: return "\033[38;5;33m";
        case Col::green_back: return "\033[42;1m\033[38;5;0m";
        case Col::blue_back: return "\033[43;1m\033[38;5;0m";
    }
    return "";
}

u64 code_points(std::string_view s) noexcept
{
    u64 n = 0;
    for (const char ch : s)
        n += (static_cast<unsigned char>(ch) & 0xc0) != 0x80;
    return n;
}

u64 Out::visible_chars() const noexcept
{
    const u64 all = code_points(s);
    return emit_ ? all - pycodes_ : all;
}

// ---- numbers -------------------------------------------------------------------------

std::string int_dec(const EvmInt& x)
{
    if (x.fits_i64())
        return std::to_string(x.to_i64());
    return x.big()->get_str(10);
}

std::string int_hex(const EvmInt& x)
{
    std::string digits;
    bool neg = x.sign() < 0;
    if (x.fits_i64()) {
        const i64 v = x.to_i64();
        u64 m = neg ? u64(0) - u64(v) : u64(v);
        if (m == 0)
            digits = "0";
        while (m) {
            digits.insert(digits.begin(), "0123456789abcdef"[m & 15]);
            m >>= 4;
        }
    } else {
        mpz_class z = *x.big();
        if (neg)
            z = -z;
        digits = z.get_str(16);
    }
    return (neg ? "-0x" : "0x") + digits;
}

std::string padded_hex(const EvmInt& x, u32 n)
{
    EvmInt v = x;
    if (v.sign() < 0)
        v = v.mod_2exp(u64(4) * n);  // (the word's given_len lowest digits)
    std::string h = int_hex(v).substr(2);
    if (h.size() > n)
        return std::string(n, '?');
    return "0x" + std::string(n - h.size(), '0') + h;
}

namespace {

const EvmInt& pow10(unsigned k)
{
    static const EvmInt table[19] = {
        EvmInt(i64(1)),
        EvmInt(i64(10)),
        EvmInt(i64(100)),
        EvmInt(i64(1000)),
        EvmInt(i64(10000)),
        EvmInt(i64(100000)),
        EvmInt(i64(1000000)),
        EvmInt(i64(10000000)),
        EvmInt(i64(100000000)),
        EvmInt(i64(1000000000)),
        EvmInt(i64(10000000000)),
        EvmInt(i64(100000000000)),
        EvmInt(i64(1000000000000)),
        EvmInt(i64(10000000000000)),
        EvmInt(i64(100000000000000)),
        EvmInt(i64(1000000000000000)),
        EvmInt(i64(10000000000000000)),
        EvmInt(i64(100000000000000000)),
        EvmInt(i64(1000000000000000000)),
    };
    return table[k];
}

// "10**k" or "q * 10**k" when x is a multiple of 10**k
bool tens(const EvmInt& x, unsigned k, std::string& out)
{
    if (!pymod(x, pow10(k)).is_zero())
        return false;
    const EvmInt q = floordiv(x, pow10(k));
    out = q == 1 ? "10**" + std::to_string(k) : int_dec(q) + " * 10**" + std::to_string(k);
    return true;
}

}  // namespace

std::string pretty_num(const EvmInt& x)
{
    static const EvmInt big_hex = EvmInt::pow2(150);  // 8**50
    static const EvmInt small_dec = EvmInt::pow2(90);  // 8**30
    if (x > big_hex)
        return int_hex(x);  // binary data, probably
    if (!x.is_zero()) {
        std::string t;
        for (unsigned k = 18; k >= 9; --k)
            if (tens(x, k, t))
                return t;
        if (tens(x, 6, t))
            return t;
    }
    const EvmInt w = x.word();
    if (w < small_dec)
        return int_dec(w);  // (the word it is: -2**256 + 128 is 128)
    if (x.sign() > 0)
        return int_hex(x);
    return int_dec(x);
}

int num_precedence(std::string_view text) noexcept
{
    if (text.find(" * ") != std::string_view::npos)
        return P_MUL;
    if (!text.empty() && text[0] == '-')
        return P_UNARY;
    if (text.find("**") != std::string_view::npos)
        return P_POW;
    return P_ATOM;
}

}  // namespace pan::output::detail
