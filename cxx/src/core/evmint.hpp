// Ethereum integers.
//  - EvmInt: python's unbounded int (gmpxx mpz_class behind), allocation-free
//    while the value fits an i64 (inline i64 + flag; the mpz only past i64).
//  - Word256: a concrete EVM word (4 little-endian u64 limbs) with the yellow
//    paper's semantics (x / 0 = 0, signed ops in two's complement).
// No floating point anywhere (-Ofast).
#pragma once

#include <compare>
#include <optional>
#include <span>

#include <gmpxx.h>

#include "core/base.hpp"

namespace pan {

class Value;  // core/value.hpp (main)

// the largest shift / exponent / mask width a contract number may reach GMP
// with; past it: SizeLimit (core/errors.hpp)
inline constexpr u64 kEvmIntMaxBits = u64{1} << 20;

class EvmInt {
public:
    EvmInt() noexcept : s_(0), big_(false) {}
    EvmInt(i64 v) noexcept : s_(v), big_(false) {}  // NOLINT: implicit on purpose
    EvmInt(int v) noexcept : s_(v), big_(false) {}
    EvmInt(u32 v) noexcept : s_(v), big_(false) {}
    EvmInt(u64) = delete;  // values past 2^63 would wrap: EvmInt::from_u64
    EvmInt(const mpz_class& z);
    EvmInt(mpz_class&& z);
    static EvmInt from_u64(u64 v);
    EvmInt(const EvmInt& o);
    EvmInt(EvmInt&& o) noexcept = default;
    EvmInt& operator=(const EvmInt& o);
    EvmInt& operator=(EvmInt&& o) noexcept = default;

    static EvmInt pow2(u64 k);                        // SizeLimit past kEvmIntMaxBits
    static EvmInt from_be(std::span<const u8> bytes);  // unsigned big-endian
    explicit EvmInt(Value v);  // a small or big int Value (core/value_int.cpp)
    Value value() const;       // on cx(): small when it fits 63 bits (core/value_int.cpp)

    int sign() const noexcept;
    bool is_zero() const noexcept { return !big_ && s_ == 0; }
    bool fits_i64() const noexcept { return !big_; }
    i64 to_i64() const noexcept { return s_; }  // only when fits_i64()
    std::optional<u64> to_u64() const noexcept;  // when 0 <= x < 2^64
    u64 bit_length() const noexcept;              // python's int.bit_length() (of |x|)
    bool test_bit(u64 n) const noexcept;          // (x >> n) & 1, two's complement
    mpz_class to_mpz() const;
    // the mpz of a big value (nullptr when small): for printing
    const mpz_class* big() const noexcept { return big_ ? &z_ : nullptr; }

    // python operators
    friend EvmInt operator+(const EvmInt& a, const EvmInt& b);
    friend EvmInt operator-(const EvmInt& a, const EvmInt& b);
    friend EvmInt operator*(const EvmInt& a, const EvmInt& b);
    friend EvmInt operator-(const EvmInt& a);
    friend EvmInt floordiv(const EvmInt& a, const EvmInt& b);  // a // b (Unsupported on 0)
    friend EvmInt pymod(const EvmInt& a, const EvmInt& b);     // a % b (sign of b)
    friend EvmInt operator<<(const EvmInt& a, u64 k);          // SizeLimit past 2^20
    friend EvmInt operator>>(const EvmInt& a, u64 k);          // arithmetic (floor)
    friend EvmInt operator&(const EvmInt& a, const EvmInt& b);
    friend EvmInt operator|(const EvmInt& a, const EvmInt& b);
    friend EvmInt operator^(const EvmInt& a, const EvmInt& b);
    friend EvmInt operator~(const EvmInt& a);
    EvmInt pow(u64 k) const;  // x ** k; SizeLimit when k or the result is past 2^20 bits
    friend bool operator==(const EvmInt& a, const EvmInt& b) noexcept;
    friend std::strong_ordering operator<=>(const EvmInt& a, const EvmInt& b) noexcept;
    friend bool operator==(const EvmInt& a, i64 b) noexcept { return !a.big_ && a.s_ == b; }

    EvmInt& operator+=(const EvmInt& b) { return *this = *this + b; }
    EvmInt& operator-=(const EvmInt& b) { return *this = *this - b; }

    // EVM words
    EvmInt word() const;       // mod 2^256, in [0, 2^256)
    EvmInt to_signed() const;  // word() with bit 255 as the sign
    EvmInt mod_2exp(u64 k) const;                // x mod 2^k (floor: >= 0)
    static EvmInt mask(u64 size, u64 off = 0);   // ((1 << size) - 1) << off
    void to_be32(u8 out[32]) const noexcept;     // word() big-endian

private:
    void norm() noexcept;  // big -> small when it fits
    mpz_srcptr ref(mpz_class& tmp) const;
    i64 s_;
    bool big_;
    mpz_class z_;  // meaningful only when big_ (mpz_init doesn't allocate)
};

const EvmInt& two_256();   // 2^256
const EvmInt& word_max();  // 2^256 - 1

// a concrete EVM word
struct Word256 {
    u64 limb[4];  // little-endian limbs

    static constexpr Word256 of(u64 v) noexcept { return Word256{{v, 0, 0, 0}}; }
    static Word256 from_be(std::span<const u8> bytes) noexcept;  // right-aligned; mod 2^256
    void to_be(u8 out[32]) const noexcept;
    static Word256 from_int(const EvmInt& x) noexcept;  // mod 2^256 (negative wraps)
    EvmInt to_int() const;                              // unsigned
    static Word256 from_value(Value v);  // an int Value mod 2^256 (core/value_int.cpp)
    Value to_value() const;              // on cx() (core/value_int.cpp)

    bool is_zero() const noexcept { return (limb[0] | limb[1] | limb[2] | limb[3]) == 0; }
    std::optional<u64> as_u64() const noexcept {
        if (limb[1] | limb[2] | limb[3]) return std::nullopt;
        return limb[0];
    }
    bool operator==(const Word256&) const noexcept = default;
    std::strong_ordering operator<=>(const Word256& o) const noexcept {
        for (int i = 3; i >= 0; --i)
            if (limb[i] != o.limb[i]) return limb[i] <=> o.limb[i];
        return std::strong_ordering::equal;
    }
};

// EVM semantics; argument order is the stack order (a = top)
Word256 add(const Word256& a, const Word256& b) noexcept;
Word256 sub(const Word256& a, const Word256& b) noexcept;
Word256 mul(const Word256& a, const Word256& b) noexcept;
Word256 div(const Word256& a, const Word256& b) noexcept;
Word256 sdiv(const Word256& a, const Word256& b) noexcept;
Word256 mod(const Word256& a, const Word256& b) noexcept;
Word256 smod(const Word256& a, const Word256& b) noexcept;
Word256 addmod(const Word256& a, const Word256& b, const Word256& n) noexcept;
Word256 mulmod(const Word256& a, const Word256& b, const Word256& n) noexcept;
Word256 exp(const Word256& base, const Word256& e) noexcept;
Word256 signextend(const Word256& b, const Word256& x) noexcept;
Word256 lt(const Word256& a, const Word256& b) noexcept;
Word256 gt(const Word256& a, const Word256& b) noexcept;
Word256 slt(const Word256& a, const Word256& b) noexcept;
Word256 sgt(const Word256& a, const Word256& b) noexcept;
Word256 eq(const Word256& a, const Word256& b) noexcept;
Word256 iszero(const Word256& a) noexcept;
Word256 band(const Word256& a, const Word256& b) noexcept;
Word256 bor(const Word256& a, const Word256& b) noexcept;
Word256 bxor(const Word256& a, const Word256& b) noexcept;
Word256 bnot(const Word256& a) noexcept;
Word256 byte(const Word256& i, const Word256& x) noexcept;
Word256 shl(const Word256& shift, const Word256& x) noexcept;
Word256 shr(const Word256& shift, const Word256& x) noexcept;
Word256 sar(const Word256& shift, const Word256& x) noexcept;
Word256 clz(const Word256& x) noexcept;  // EIP-7939: 256 for 0

}  // namespace pan
