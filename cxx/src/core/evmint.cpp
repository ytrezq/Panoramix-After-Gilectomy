// Ethereum integers: EvmInt (python int on gmpxx) and Word256 (EVM word).
#include "core/evmint.hpp"

#include <cstring>
#include <type_traits>

#include "core/errors.hpp"

namespace pan {

static_assert(sizeof(long) == 8, "mpz_*_si needs a 64-bit long");
static_assert(std::is_same_v<mp_limb_t, u64>, "Word256 limbs are GMP limbs");

// ---------------------------------------------------------------- EvmInt

EvmInt::EvmInt(const mpz_class& z) : s_(0), big_(true), z_(z) { norm(); }
EvmInt::EvmInt(mpz_class&& z) : s_(0), big_(true), z_(std::move(z)) { norm(); }

EvmInt::EvmInt(const EvmInt& o) : s_(o.s_), big_(o.big_) {
    if (big_) z_ = o.z_;
}

EvmInt& EvmInt::operator=(const EvmInt& o) {
    s_ = o.s_;
    big_ = o.big_;
    if (big_) z_ = o.z_;
    return *this;
}

EvmInt EvmInt::from_u64(u64 v) {
    if (v <= u64(INT64_MAX)) return EvmInt(i64(v));
    mpz_class z;
    mpz_set_ui(z.get_mpz_t(), v);
    return EvmInt(std::move(z));
}

void EvmInt::norm() noexcept {
    if (big_ && mpz_fits_slong_p(z_.get_mpz_t())) {
        s_ = mpz_get_si(z_.get_mpz_t());
        big_ = false;
    }
}

mpz_srcptr EvmInt::ref(mpz_class& tmp) const {
    if (big_) return z_.get_mpz_t();
    mpz_set_si(tmp.get_mpz_t(), s_);
    return tmp.get_mpz_t();
}

mpz_class EvmInt::to_mpz() const {
    if (big_) return z_;
    mpz_class z;
    mpz_set_si(z.get_mpz_t(), s_);
    return z;
}

static void check_bits(u64 k) {
    if (k > kEvmIntMaxBits) throw SizeLimit("integer too large (shift or exponent past 2^20 bits)");
}

EvmInt EvmInt::pow2(u64 k) {
    if (k < 63) return EvmInt(i64(1) << k);
    check_bits(k);
    mpz_class z;
    mpz_setbit(z.get_mpz_t(), k);
    return EvmInt(std::move(z));
}

EvmInt EvmInt::from_be(std::span<const u8> b) {
    usize i = 0;
    while (i < b.size() && b[i] == 0) ++i;
    b = b.subspan(i);
    if (b.size() <= 8) {
        u64 v = 0;
        for (u8 c : b) v = (v << 8) | c;
        return from_u64(v);
    }
    mpz_class z;
    mpz_import(z.get_mpz_t(), b.size(), 1, 1, 1, 0, b.data());
    return EvmInt(std::move(z));
}

int EvmInt::sign() const noexcept {
    if (big_) return mpz_sgn(z_.get_mpz_t());
    return (s_ > 0) - (s_ < 0);
}

std::optional<u64> EvmInt::to_u64() const noexcept {
    if (!big_) {
        if (s_ < 0) return std::nullopt;
        return u64(s_);
    }
    if (mpz_sgn(z_.get_mpz_t()) > 0 && mpz_sizeinbase(z_.get_mpz_t(), 2) <= 64)
        return u64(mpz_getlimbn(z_.get_mpz_t(), 0));
    return std::nullopt;
}

u64 EvmInt::bit_length() const noexcept {
    if (big_) return mpz_sizeinbase(z_.get_mpz_t(), 2);
    if (s_ == 0) return 0;
    u64 m = s_ < 0 ? u64(0) - u64(s_) : u64(s_);
    return 64 - u64(__builtin_clzll(m));
}

bool EvmInt::test_bit(u64 n) const noexcept {
    if (big_) return mpz_tstbit(z_.get_mpz_t(), n);
    if (n >= 63) return s_ < 0;
    return (s_ >> n) & 1;
}

#define PAN_EVMINT_SLOW2(fn)                                                  \
    EvmInt out_;                                                              \
    out_.big_ = true;                                                         \
    mpz_class ta_, tb_;                                                       \
    fn(out_.z_.get_mpz_t(), a.ref(ta_), b.ref(tb_));                          \
    out_.norm();                                                              \
    return out_

EvmInt operator+(const EvmInt& a, const EvmInt& b) {
    i64 r;
    if (!a.big_ && !b.big_ && !__builtin_add_overflow(a.s_, b.s_, &r)) return EvmInt(r);
    PAN_EVMINT_SLOW2(mpz_add);
}

EvmInt operator-(const EvmInt& a, const EvmInt& b) {
    i64 r;
    if (!a.big_ && !b.big_ && !__builtin_sub_overflow(a.s_, b.s_, &r)) return EvmInt(r);
    PAN_EVMINT_SLOW2(mpz_sub);
}

EvmInt operator*(const EvmInt& a, const EvmInt& b) {
    i64 r;
    if (!a.big_ && !b.big_ && !__builtin_mul_overflow(a.s_, b.s_, &r)) return EvmInt(r);
    PAN_EVMINT_SLOW2(mpz_mul);
}

EvmInt operator-(const EvmInt& a) {
    if (!a.big_ && a.s_ != INT64_MIN) return EvmInt(-a.s_);
    EvmInt r;
    r.big_ = true;
    mpz_class ta;
    mpz_neg(r.z_.get_mpz_t(), a.ref(ta));
    r.norm();
    return r;
}

EvmInt floordiv(const EvmInt& a, const EvmInt& b) {
    if (b.is_zero()) throw Unsupported("integer division by zero");
    if (!a.big_ && !b.big_ && !(a.s_ == INT64_MIN && b.s_ == -1)) {
        i64 q = a.s_ / b.s_;
        if (a.s_ % b.s_ != 0 && ((a.s_ < 0) != (b.s_ < 0))) --q;
        return EvmInt(q);
    }
    PAN_EVMINT_SLOW2(mpz_fdiv_q);
}

EvmInt pymod(const EvmInt& a, const EvmInt& b) {
    if (b.is_zero()) throw Unsupported("integer modulo by zero");
    if (!a.big_ && !b.big_) {
        if (b.s_ == -1) return EvmInt(0);
        i64 r = a.s_ % b.s_;
        if (r != 0 && ((r < 0) != (b.s_ < 0))) r += b.s_;
        return EvmInt(r);
    }
    PAN_EVMINT_SLOW2(mpz_fdiv_r);
}

EvmInt operator&(const EvmInt& a, const EvmInt& b) {
    if (!a.big_ && !b.big_) return EvmInt(a.s_ & b.s_);
    PAN_EVMINT_SLOW2(mpz_and);
}

EvmInt operator|(const EvmInt& a, const EvmInt& b) {
    if (!a.big_ && !b.big_) return EvmInt(a.s_ | b.s_);
    PAN_EVMINT_SLOW2(mpz_ior);
}

EvmInt operator^(const EvmInt& a, const EvmInt& b) {
    if (!a.big_ && !b.big_) return EvmInt(a.s_ ^ b.s_);
    PAN_EVMINT_SLOW2(mpz_xor);
}

#undef PAN_EVMINT_SLOW2

EvmInt operator~(const EvmInt& a) {
    if (!a.big_) return EvmInt(~a.s_);
    EvmInt r;
    r.big_ = true;
    mpz_com(r.z_.get_mpz_t(), a.z_.get_mpz_t());
    r.norm();
    return r;
}

EvmInt operator<<(const EvmInt& a, u64 k) {
    if (a.is_zero()) return a;
    if (!a.big_ && k < 64 && k <= u64(__builtin_clrsbll(a.s_)))
        return EvmInt(i64(u64(a.s_) << k));
    check_bits(k);
    EvmInt r;
    r.big_ = true;
    mpz_class ta;
    mpz_mul_2exp(r.z_.get_mpz_t(), a.ref(ta), k);
    r.norm();
    return r;
}

EvmInt operator>>(const EvmInt& a, u64 k) {
    if (!a.big_) return EvmInt(k >= 63 ? (a.s_ < 0 ? -1 : 0) : a.s_ >> k);
    if (k >= a.bit_length()) return EvmInt(a.sign() < 0 ? -1 : 0);
    EvmInt r;
    r.big_ = true;
    mpz_fdiv_q_2exp(r.z_.get_mpz_t(), a.z_.get_mpz_t(), k);
    r.norm();
    return r;
}

EvmInt EvmInt::pow(u64 k) const {
    if (k == 0) return EvmInt(1);
    if (!big_ && (s_ == 0 || s_ == 1)) return *this;
    if (!big_ && s_ == -1) return EvmInt((k & 1) ? -1 : 1);
    check_bits(k);
    // |x| >= 2: the result has at most bit_length * k bits; cap that at 2^21
    if (bit_length() > 2 * kEvmIntMaxBits / k) check_bits(kEvmIntMaxBits + 1);
    if (!big_) {
        i64 r = 1, b = s_;
        u64 e = k;
        bool ok = true;
        while (ok) {
            if ((e & 1) && __builtin_mul_overflow(r, b, &r)) ok = false;
            e >>= 1;
            if (!e || !ok) break;
            if (__builtin_mul_overflow(b, b, &b)) ok = false;
        }
        if (ok) return EvmInt(r);
    }
    EvmInt r;
    r.big_ = true;
    mpz_class ta;
    mpz_pow_ui(r.z_.get_mpz_t(), ref(ta), k);
    r.norm();
    return r;
}

bool operator==(const EvmInt& a, const EvmInt& b) noexcept {
    if (a.big_ != b.big_) return false;  // big never fits an i64
    if (!a.big_) return a.s_ == b.s_;
    return mpz_cmp(a.z_.get_mpz_t(), b.z_.get_mpz_t()) == 0;
}

std::strong_ordering operator<=>(const EvmInt& a, const EvmInt& b) noexcept {
    int c;
    if (!a.big_ && !b.big_) return a.s_ <=> b.s_;
    if (a.big_ && b.big_)
        c = mpz_cmp(a.z_.get_mpz_t(), b.z_.get_mpz_t());
    else if (a.big_)
        c = mpz_cmp_si(a.z_.get_mpz_t(), b.s_);
    else
        c = -mpz_cmp_si(b.z_.get_mpz_t(), a.s_);
    return c <=> 0;
}

EvmInt EvmInt::word() const {
    if (!big_ && s_ >= 0) return *this;
    return mod_2exp(256);
}

EvmInt EvmInt::to_signed() const {
    if (!big_) return *this;  // |x| < 2^63: already its own signed word
    EvmInt w = mod_2exp(256);
    if (w.test_bit(255)) return w - two_256();
    return w;
}

EvmInt EvmInt::mod_2exp(u64 k) const {
    if (!big_) {
        if (k < 63) return EvmInt(s_ & ((i64(1) << k) - 1));
        if (s_ >= 0) return *this;
    } else if (sign() > 0 && bit_length() <= k) {
        return *this;
    }
    check_bits(k);
    EvmInt r;
    r.big_ = true;
    mpz_class ta;
    mpz_fdiv_r_2exp(r.z_.get_mpz_t(), ref(ta), k);
    r.norm();
    return r;
}

EvmInt EvmInt::mask(u64 size, u64 off) {
    if (size == 0) return EvmInt(0);
    if (size + off < 63) return EvmInt(((i64(1) << size) - 1) << off);
    check_bits(size);
    check_bits(off);
    check_bits(size + off);
    mpz_class z;
    mpz_setbit(z.get_mpz_t(), size);
    mpz_sub_ui(z.get_mpz_t(), z.get_mpz_t(), 1);
    mpz_mul_2exp(z.get_mpz_t(), z.get_mpz_t(), off);
    return EvmInt(std::move(z));
}

void EvmInt::to_be32(u8 out[32]) const noexcept {
    u64 l[4];
    if (!big_) {
        u64 ext = s_ < 0 ? ~u64(0) : 0;
        l[0] = u64(s_);
        l[1] = l[2] = l[3] = ext;
    } else {
        mpz_class t;
        mpz_fdiv_r_2exp(t.get_mpz_t(), z_.get_mpz_t(), 256);
        for (int i = 0; i < 4; ++i) l[i] = mpz_getlimbn(t.get_mpz_t(), i);
    }
    for (int j = 0; j < 32; ++j) out[31 - j] = u8(l[j / 8] >> (8 * (j % 8)));
}

const EvmInt& two_256() {
    static const EvmInt v = EvmInt::pow2(256);
    return v;
}

const EvmInt& word_max() {
    static const EvmInt v = EvmInt::pow2(256) - EvmInt(1);
    return v;
}

// ---------------------------------------------------------------- Word256

Word256 Word256::from_be(std::span<const u8> b) noexcept {
    if (b.size() > 32) b = b.subspan(b.size() - 32);
    Word256 r{};
    usize n = b.size();
    for (usize j = 0; j < n; ++j) r.limb[j / 8] |= u64(b[n - 1 - j]) << (8 * (j % 8));
    return r;
}

void Word256::to_be(u8 out[32]) const noexcept {
    for (int j = 0; j < 32; ++j) out[31 - j] = u8(limb[j / 8] >> (8 * (j % 8)));
}

Word256 Word256::from_int(const EvmInt& x) noexcept {
    u8 b[32];
    x.to_be32(b);
    return from_be(b);
}

EvmInt Word256::to_int() const {
    u8 b[32];
    to_be(b);
    return EvmInt::from_be(b);
}

static inline Word256 w_bool(bool b) noexcept { return Word256::of(b ? 1 : 0); }
static inline bool w_neg(const Word256& a) noexcept { return a.limb[3] >> 63; }
static inline int w_top(const mp_limb_t* p, int n) noexcept {
    while (n > 0 && p[n - 1] == 0) --n;
    return n;
}

// n (nn limbs) mod m (m != 0)
static Word256 w_rem(const mp_limb_t* n, int nn, const Word256& m) noexcept {
    Word256 r{};
    int dn = w_top(m.limb, 4);
    nn = w_top(n, nn);
    if (nn < dn) {
        for (int i = 0; i < nn; ++i) r.limb[i] = n[i];
        return r;
    }
    mp_limb_t q[9];
    mpn_tdiv_qr(q, r.limb, 0, n, nn, m.limb, dn);
    return r;
}

static Word256 w_quot(const Word256& a, const Word256& b) noexcept {
    Word256 q{};
    int dn = w_top(b.limb, 4), nn = w_top(a.limb, 4);
    if (nn < dn) return q;
    mp_limb_t r[4];
    mpn_tdiv_qr(q.limb, r, 0, a.limb, nn, b.limb, dn);
    return q;
}

static inline Word256 w_negate(const Word256& a) noexcept { return sub(Word256{}, a); }
static inline Word256 w_abs(const Word256& a) noexcept { return w_neg(a) ? w_negate(a) : a; }

Word256 add(const Word256& a, const Word256& b) noexcept {
    Word256 r;
    mpn_add_n(r.limb, a.limb, b.limb, 4);
    return r;
}

Word256 sub(const Word256& a, const Word256& b) noexcept {
    Word256 r;
    mpn_sub_n(r.limb, a.limb, b.limb, 4);
    return r;
}

Word256 mul(const Word256& a, const Word256& b) noexcept {
    Word256 r{};
    for (int i = 0; i < 4; ++i) {
        unsigned __int128 c = 0;
        for (int j = 0; i + j < 4; ++j) {
            c += (unsigned __int128)a.limb[i] * b.limb[j] + r.limb[i + j];
            r.limb[i + j] = u64(c);
            c >>= 64;
        }
    }
    return r;
}

Word256 div(const Word256& a, const Word256& b) noexcept {
    if (b.is_zero()) return Word256{};
    return w_quot(a, b);
}

Word256 mod(const Word256& a, const Word256& b) noexcept {
    if (b.is_zero()) return Word256{};
    return w_rem(a.limb, 4, b);
}

Word256 sdiv(const Word256& a, const Word256& b) noexcept {
    if (b.is_zero()) return Word256{};
    Word256 q = w_quot(w_abs(a), w_abs(b));
    return w_neg(a) != w_neg(b) ? w_negate(q) : q;
}

Word256 smod(const Word256& a, const Word256& b) noexcept {
    if (b.is_zero()) return Word256{};
    Word256 aa = w_abs(a);
    Word256 r = w_rem(aa.limb, 4, w_abs(b));
    return w_neg(a) ? w_negate(r) : r;
}

Word256 addmod(const Word256& a, const Word256& b, const Word256& n) noexcept {
    if (n.is_zero()) return Word256{};
    mp_limb_t s[5];
    s[4] = mpn_add_n(s, a.limb, b.limb, 4);
    return w_rem(s, 5, n);
}

Word256 mulmod(const Word256& a, const Word256& b, const Word256& n) noexcept {
    if (n.is_zero()) return Word256{};
    mp_limb_t p[8];
    mpn_mul_n(p, a.limb, b.limb, 4);
    return w_rem(p, 8, n);
}

Word256 exp(const Word256& base, const Word256& e) noexcept {
    Word256 r = Word256::of(1);
    int top = w_top(e.limb, 4);
    if (top == 0) return r;
    for (int bit = top * 64 - 1; bit >= 0; --bit) {
        r = mul(r, r);
        if ((e.limb[bit / 64] >> (bit % 64)) & 1) r = mul(r, base);
    }
    return r;
}

Word256 signextend(const Word256& b, const Word256& x) noexcept {
    auto k = b.as_u64();
    if (!k || *k >= 31) return x;
    u64 bit = *k * 8 + 7;
    u64 idx = bit / 64, off = bit % 64;
    bool neg = (x.limb[idx] >> off) & 1;
    u64 hi = off == 63 ? 0 : ~u64(0) << (off + 1);  // the bits above the sign bit
    Word256 r = x;
    if (neg)
        r.limb[idx] |= hi;
    else
        r.limb[idx] &= ~hi;
    for (u64 i = idx + 1; i < 4; ++i) r.limb[i] = neg ? ~u64(0) : 0;
    return r;
}

Word256 lt(const Word256& a, const Word256& b) noexcept { return w_bool(a < b); }
Word256 gt(const Word256& a, const Word256& b) noexcept { return w_bool(a > b); }

Word256 slt(const Word256& a, const Word256& b) noexcept {
    Word256 x = a, y = b;
    x.limb[3] ^= u64(1) << 63;
    y.limb[3] ^= u64(1) << 63;
    return w_bool(x < y);
}

Word256 sgt(const Word256& a, const Word256& b) noexcept { return slt(b, a); }
Word256 eq(const Word256& a, const Word256& b) noexcept { return w_bool(a == b); }
Word256 iszero(const Word256& a) noexcept { return w_bool(a.is_zero()); }

Word256 band(const Word256& a, const Word256& b) noexcept {
    Word256 r;
    for (int i = 0; i < 4; ++i) r.limb[i] = a.limb[i] & b.limb[i];
    return r;
}

Word256 bor(const Word256& a, const Word256& b) noexcept {
    Word256 r;
    for (int i = 0; i < 4; ++i) r.limb[i] = a.limb[i] | b.limb[i];
    return r;
}

Word256 bxor(const Word256& a, const Word256& b) noexcept {
    Word256 r;
    for (int i = 0; i < 4; ++i) r.limb[i] = a.limb[i] ^ b.limb[i];
    return r;
}

Word256 bnot(const Word256& a) noexcept {
    Word256 r;
    for (int i = 0; i < 4; ++i) r.limb[i] = ~a.limb[i];
    return r;
}

Word256 byte(const Word256& i, const Word256& x) noexcept {
    auto k = i.as_u64();
    if (!k || *k >= 32) return Word256{};
    u64 pos = 31 - *k;  // from the least significant byte
    return Word256::of((x.limb[pos / 8] >> (8 * (pos % 8))) & 0xff);
}

Word256 shl(const Word256& shift, const Word256& x) noexcept {
    auto k = shift.as_u64();
    if (!k || *k >= 256) return Word256{};
    int ls = int(*k / 64), bs = int(*k % 64);
    Word256 r{};
    for (int i = 3; i >= ls; --i) {
        int src = i - ls;
        u64 v = x.limb[src] << bs;
        if (bs && src > 0) v |= x.limb[src - 1] >> (64 - bs);
        r.limb[i] = v;
    }
    return r;
}

Word256 shr(const Word256& shift, const Word256& x) noexcept {
    auto k = shift.as_u64();
    if (!k || *k >= 256) return Word256{};
    int ls = int(*k / 64), bs = int(*k % 64);
    Word256 r{};
    for (int i = 0; i + ls < 4; ++i) {
        int src = i + ls;
        u64 v = x.limb[src] >> bs;
        if (bs && src < 3) v |= x.limb[src + 1] << (64 - bs);
        r.limb[i] = v;
    }
    return r;
}

Word256 sar(const Word256& shift, const Word256& x) noexcept {
    if (!w_neg(x)) return shr(shift, x);
    auto k = shift.as_u64();
    Word256 ones = bnot(Word256{});
    if (!k || *k >= 256) return ones;
    return bor(shr(shift, x), bnot(shr(shift, ones)));
}

Word256 clz(const Word256& x) noexcept {
    for (int i = 3; i >= 0; --i)
        if (x.limb[i]) return Word256::of(u64(3 - i) * 64 + u64(__builtin_clzll(x.limb[i])));
    return Word256::of(256);
}

}  // namespace pan
