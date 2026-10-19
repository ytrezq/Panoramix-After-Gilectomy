// Value ranges: see ranges.hpp.
//
// The bounds are XInt: integers of magnitude below 2^320 on six limbs (two's
// complement), or past it (inf: +1 "at least 2^320", -1 "at most -2^320",
// the magnitude unknown) - no GMP on the hot path. A range's lo is finite or
// -inf, its hi finite or +inf: the arithmetic rounds outwards, what it can't
// count becomes a weaker bound, never a wrong one. A word's range is two
// finite XInts in [0, 2^256).
//
// A linear reading (Lin) of an expression is an integer E = c + sum(k_i *
// a_i) over atoms - a term's word, or the bits a mask clears - congruent to
// the expression's word mod 2^256 for every value (Mode::Word), or equal to
// python's integer of it (Mode::Int: the masks read only where that is
// exact). Its range, when it lies within one window [j * 2^256, (j + 1) *
// 2^256), gives the word's: E - j * 2^256.
#include "algebra/ranges.hpp"

#include <gmp.h>
#include <gmpxx.h>

#include <algorithm>
#include <memory_resource>
#include <vector>

#include "algebra/construct.hpp"
#include "algebra/eval.hpp"
#include "algebra/facts.hpp"
#include "algebra/masks.hpp"
#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/contract.hpp"
#include "core/errors.hpp"
#include "core/intops.hpp"
#include "core/memo.hpp"
#include "core/node.hpp"

namespace pan::alg {

namespace {

using u128 = unsigned __int128;
using i128 = __int128;

// ================================================================ XInt

constexpr u32 kLimbs = 6;     // 384 bits of two's complement
constexpr u32 kSatLimbs = 5;  // finite values: |x| < 2^320
constexpr u32 kSatBits = 320;

struct XInt {
    u64 l[kLimbs];
    i8 inf;  // 0 finite; +1 at least 2^320; -1 at most -2^320

    bool finite() const noexcept { return inf == 0; }
    bool neg() const noexcept { return inf ? inf < 0 : (l[5] >> 63) != 0; }
    bool zero() const noexcept { return !inf && !(l[0] | l[1] | l[2] | l[3] | l[4] | l[5]); }
    int sign() const noexcept { return inf ? inf : neg() ? -1 : zero() ? 0 : 1; }
};

constexpr XInt xi(i64 v) noexcept {
    XInt x{};
    x.l[0] = u64(v);
    const u64 fill = v < 0 ? ~u64(0) : 0;
    for (u32 i = 1; i < kLimbs; ++i) x.l[i] = fill;
    return x;
}
constexpr XInt xi_inf(int s) noexcept {
    XInt x{};
    x.inf = i8(s > 0 ? 1 : -1);
    return x;
}
XInt xi_word(const Word256& w) noexcept {
    XInt x{};
    for (u32 i = 0; i < 4; ++i) x.l[i] = w.limb[i];
    return x;
}
// 2^k (k >= 320: +inf)
constexpr XInt xi_pow2(u32 k) noexcept {
    if (k >= kSatBits) return xi_inf(1);
    XInt x{};
    x.l[k / 64] = u64(1) << (k % 64);
    return x;
}
// 2^k - 1 (k <= 320)
constexpr XInt xi_ones(u32 k) noexcept {
    XInt x{};
    for (u32 i = 0; i < k / 64; ++i) x.l[i] = ~u64(0);
    if (k % 64) x.l[k / 64] = (u64(1) << (k % 64)) - 1;
    return x;
}
constexpr XInt kZero = xi(0);
constexpr XInt kOne = xi(1);
constexpr XInt kWordMax = xi_ones(256);   // 2^256 - 1
constexpr XInt kSatMax = xi_ones(kSatBits);  // 2^320 - 1: the largest finite
constexpr XInt kTwo255 = xi_pow2(255);
constexpr XInt kTwo256 = xi_pow2(256);

void raw_add(XInt& r, const XInt& a, const XInt& b) noexcept {
    u64 c = 0;
    for (u32 i = 0; i < kLimbs; ++i) {
        u128 s = u128(a.l[i]) + b.l[i] + c;
        r.l[i] = u64(s);
        c = u64(s >> 64);
    }
    r.inf = 0;
}
void raw_neg(XInt& r, const XInt& a) noexcept {
    u64 c = 1;
    for (u32 i = 0; i < kLimbs; ++i) {
        u128 s = u128(~a.l[i]) + c;
        r.l[i] = u64(s);
        c = u64(s >> 64);
    }
    r.inf = 0;
}
// a finite result kept when |x| < 2^320, else the inf of its sign
void saturate(XInt& x) noexcept {
    if (x.inf) return;
    if (!(x.l[5] >> 63)) {
        if (x.l[5]) x = xi_inf(1);
    } else if (x.l[5] != ~u64(0) || !(x.l[0] | x.l[1] | x.l[2] | x.l[3] | x.l[4])) {
        x = xi_inf(-1);
    }
}

XInt xneg(const XInt& a) noexcept {
    if (a.inf) return xi_inf(-a.inf);
    XInt r;
    raw_neg(r, a);
    return r;
}

int xcmp(const XInt& a, const XInt& b) noexcept {
    if (a.inf || b.inf) {
        if (a.inf == b.inf) return 0;
        if (a.inf > 0 || b.inf < 0) return 1;
        return -1;
    }
    const i64 ha = i64(a.l[5]), hb = i64(b.l[5]);
    if (ha != hb) return ha < hb ? -1 : 1;
    for (int i = 4; i >= 0; --i)
        if (a.l[i] != b.l[i]) return a.l[i] < b.l[i] ? -1 : 1;
    return 0;
}
bool operator<(const XInt& a, const XInt& b) noexcept { return xcmp(a, b) < 0; }
bool operator<=(const XInt& a, const XInt& b) noexcept { return xcmp(a, b) <= 0; }
bool operator==(const XInt& a, const XInt& b) noexcept { return xcmp(a, b) == 0; }
const XInt& xmin(const XInt& a, const XInt& b) noexcept { return b < a ? b : a; }
const XInt& xmax(const XInt& a, const XInt& b) noexcept { return a < b ? b : a; }

// a + b, exact: false when past 2^320 (or an operand is infinite)
bool add_exact(XInt& r, const XInt& a, const XInt& b) noexcept {
    if (a.inf || b.inf) return false;
    raw_add(r, a, b);
    saturate(r);
    return r.inf == 0;
}

// a bound past the other side made the weaker finite one: a lower bound of
// +inf is 2^320 - 1, an upper bound of -inf is -(2^320 - 1)
XInt as_lo(const XInt& x) noexcept { return x.inf > 0 ? kSatMax : x; }
XInt as_hi(const XInt& x) noexcept { return x.inf < 0 ? xneg(kSatMax) : x; }

XInt add_lo(const XInt& a0, const XInt& b0) noexcept {
    const XInt a = as_lo(a0), b = as_lo(b0);
    if (a.inf || b.inf) return xi_inf(-1);
    XInt r;
    raw_add(r, a, b);
    saturate(r);
    return as_lo(r);
}
XInt add_hi(const XInt& a0, const XInt& b0) noexcept {
    const XInt a = as_hi(a0), b = as_hi(b0);
    if (a.inf || b.inf) return xi_inf(1);
    XInt r;
    raw_add(r, a, b);
    saturate(r);
    return as_hi(r);
}

// |a| on five limbs (a finite)
void magnitude(const XInt& a, u64 m[kSatLimbs]) noexcept {
    XInt t = a;
    if (a.neg()) raw_neg(t, a);
    for (u32 i = 0; i < kSatLimbs; ++i) m[i] = t.l[i];
}

// a * b: exact when below 2^320 in magnitude, else the inf of its sign
// (0 times anything is 0: an infinite end stands for a finite value)
XInt xmul(const XInt& a, const XInt& b) noexcept {
    const int sa = a.sign(), sb = b.sign();
    if (sa == 0 || sb == 0) return kZero;
    if (a.inf || b.inf) return xi_inf(sa * sb);
    u64 A[kSatLimbs], B[kSatLimbs];
    magnitude(a, A);
    magnitude(b, B);
    u64 P[2 * kSatLimbs] = {};
    for (u32 i = 0; i < kSatLimbs; ++i) {
        if (!A[i]) continue;
        u64 carry = 0;
        for (u32 j = 0; j < kSatLimbs; ++j) {
            u128 t = u128(A[i]) * B[j] + P[i + j] + carry;
            P[i + j] = u64(t);
            carry = u64(t >> 64);
        }
        P[i + kSatLimbs] = carry;
    }
    for (u32 k = kSatLimbs; k < 2 * kSatLimbs; ++k)
        if (P[k]) return xi_inf(sa * sb);
    XInt r{};
    for (u32 i = 0; i < kSatLimbs; ++i) r.l[i] = P[i];
    return sa * sb < 0 ? xneg(r) : r;
}
bool mul_exact(XInt& r, const XInt& a, const XInt& b) noexcept {
    if (a.inf || b.inf) return false;
    r = xmul(a, b);
    return r.inf == 0;
}

// the bit length of a finite x >= 0
u32 bitlen(const XInt& x) noexcept {
    for (int i = kLimbs - 1; i >= 0; --i)
        if (x.l[i]) return u32(i) * 64 + 64 - u32(__builtin_clzll(x.l[i]));
    return 0;
}

// a finite x in [0, 2^256) as a word, and back
Word256 to_w(const XInt& x) noexcept { return Word256{{x.l[0], x.l[1], x.l[2], x.l[3]}}; }

// floor(x / 2^256) (x finite: |x| < 2^320, so it fits)
i128 window(const XInt& x) noexcept { return i128((u128(x.l[5]) << 64) | x.l[4]); }
// x mod 2^256 (floor)
XInt low_word(const XInt& x) noexcept {
    XInt r{};
    for (u32 i = 0; i < 4; ++i) r.l[i] = x.l[i];
    return r;
}
// j * 2^256 (|j| < 2^64)
XInt times_two256(i128 j) noexcept {
    XInt r{};
    const u128 u = u128(j);
    r.l[4] = u64(u);
    r.l[5] = u64(u >> 64);
    return r;
}

// an int Value (any size), True / False
XInt xi_value(Value v) noexcept {
    if (v.is_small()) return xi(v.small_val());
    if (v.is_bool()) return xi(v.is_true() ? 1 : 0);
    if (!v.is_big()) return xi_inf(1);  // (not an int: never asked)
    const NodeHeader* n = v.node();
    const bool negative = n->op != 0;
    if (n->size > kSatLimbs) return xi_inf(negative ? -1 : 1);
    static_assert(sizeof(mp_limb_t) == 8);
    const mp_limb_t* limbs = node_limbs(n);
    XInt x{};
    for (u32 i = 0; i < n->size; ++i) x.l[i] = limbs[i];  // (at most 5 limbs: below 2^320)
    return negative ? xneg(x) : x;
}

// an int Value as lot 2's linear forms read it: its word in [-2^255, 2^255)
XInt xi_signed(Value v) noexcept {
    if (v.is_small()) return xi(v.small_val());
    if (v.is_bool()) return xi(v.is_true() ? 1 : 0);
    XInt x = xi_word(word_of(v));
    if (x.l[3] >> 63) {
        for (u32 i = 4; i < kLimbs; ++i) x.l[i] = ~u64(0);
    }
    return x;
}

// the public side: infinities reported as +-2^600
EvmInt to_evmint(const XInt& x) {
    if (x.inf) {
        EvmInt big = EvmInt::pow2(600);
        return x.inf > 0 ? big : -big;
    }
    const bool negative = x.neg();
    u64 m[kSatLimbs];
    magnitude(x, m);
    if (!(m[1] | m[2] | m[3] | m[4]) && m[0] < (u64(1) << 63)) {
        const i64 s = i64(m[0]);
        return negative ? EvmInt(-s) : EvmInt(s);
    }
    mpz_class z;
    mpz_import(z.get_mpz_t(), kSatLimbs, -1, sizeof(u64), 0, 0, m);
    if (negative) mpz_neg(z.get_mpz_t(), z.get_mpz_t());
    return EvmInt(std::move(z));
}

// x ** e with x >= 0 finite, rounded up (+inf past 2^320)
XInt xpow_hi(const XInt& x, const XInt& e) noexcept {
    if (e.zero()) return kOne;
    if (x.zero()) return kZero;
    if (x == kOne) return kOne;
    // x >= 2: past 320 bits for any e >= 320
    if (!(e < xi(kSatBits))) return xi_inf(1);
    u64 n = e.l[0];
    XInt r = kOne, b = x;
    while (n) {
        if (n & 1) r = xmul(r, b);
        n >>= 1;
        if (n) b = xmul(b, b);
        if (r.inf) return r;
    }
    return r;
}
// rounded down: exact when finite (the only caller compares it with a word)
XInt xpow_lo(const XInt& x, const XInt& e) noexcept {
    XInt r = xpow_hi(x, e);
    return as_lo(r);
}

// ================================================================ XRange

struct XRange {
    XInt lo, hi;
};

constexpr XRange xr_point(const XInt& x) noexcept { return XRange{x, x}; }
constexpr XRange xr_word() noexcept { return XRange{kZero, kWordMax}; }
constexpr XRange xr_all() noexcept { return XRange{xi_inf(-1), xi_inf(1)}; }
XRange xr_bits(u32 n) noexcept { return XRange{kZero, n >= 256 ? kWordMax : xi_ones(n)}; }
XRange xr_of(i64 lo, i64 hi) noexcept { return XRange{xi(lo), xi(hi)}; }

bool xr_is_word(const XRange& r) noexcept { return r.lo.finite() && r.hi.finite() && !r.lo.neg() && r.hi <= kWordMax; }

// the intersection; nullopt when empty
std::optional<XRange> xr_meet(const XRange& a, const XRange& b) noexcept {
    XRange r{xmax(a.lo, b.lo), xmin(a.hi, b.hi)};
    if (r.hi < r.lo) return std::nullopt;
    return r;
}
// the intersection, or a when they don't meet (contradictory facts: the path
// is infeasible, any answer holds there - a stays the honest one)
XRange xr_narrow(const XRange& a, const XRange& b) noexcept {
    auto m = xr_meet(a, b);
    return m ? *m : a;
}
XRange xr_hull(const XRange& a, const XRange& b) noexcept { return XRange{xmin(a.lo, b.lo), xmax(a.hi, b.hi)}; }
XRange xr_add(const XRange& a, const XRange& b) noexcept { return XRange{add_lo(a.lo, b.lo), add_hi(a.hi, b.hi)}; }
XRange xr_neg(const XRange& a) noexcept { return XRange{xneg(a.hi), xneg(a.lo)}; }
XRange xr_sub(const XRange& a, const XRange& b) noexcept { return xr_add(a, xr_neg(b)); }
XRange xr_shift(const XRange& a, const XInt& d) noexcept { return xr_add(a, xr_point(d)); }
// k times r, k finite
XRange xr_scale(const XRange& r, const XInt& k) noexcept {
    const int s = k.sign();
    if (s == 0) return xr_point(kZero);
    if (s > 0) return XRange{as_lo(xmul(k, r.lo)), as_hi(xmul(k, r.hi))};
    return XRange{as_lo(xmul(k, r.hi)), as_hi(xmul(k, r.lo))};
}
XRange xr_mul(const XRange& a, const XRange& b) noexcept {
    const XInt p[4] = {xmul(a.lo, b.lo), xmul(a.lo, b.hi), xmul(a.hi, b.lo), xmul(a.hi, b.hi)};
    XInt lo = p[0], hi = p[0];
    for (const XInt& x : p) {
        lo = xmin(lo, x);
        hi = xmax(hi, x);
    }
    return XRange{as_lo(lo), as_hi(hi)};
}
// the word an integer in r is: r moved into [0, 2^256) when it lies within
// one window, else any word
XRange xr_as_word(const XRange& r) noexcept {
    if (r.lo.inf || r.hi.inf) return xr_word();
    const i128 j = window(r.lo);
    if (window(r.hi) != j) return xr_word();
    return XRange{low_word(r.lo), low_word(r.hi)};
}
// the single window of r, when it has one
std::optional<i128> xr_window(const XRange& r) noexcept {
    if (r.lo.inf || r.hi.inf) return std::nullopt;
    const i128 j = window(r.lo);
    if (window(r.hi) != j) return std::nullopt;
    return j;
}
// a word range read as signed (two's complement)
XRange xr_signed(const XRange& w) noexcept {
    if (w.hi < kTwo255) return w;
    if (!(w.lo < kTwo255)) return XRange{add_lo(w.lo, xneg(kTwo256)), add_hi(w.hi, xneg(kTwo256))};
    return XRange{xneg(kTwo255), add_hi(kTwo255, xi(-1))};
}

SignRange sign_of(const XRange& r) noexcept { return SignRange{i8(r.lo.sign()), i8(r.hi.sign())}; }

Range to_range(const XRange& r) { return Range{to_evmint(r.lo), to_evmint(r.hi)}; }

// ================================================================ the context's state

// what the ranges assume of the trace (python set_variables, variants), and
// their memo tables (per top; without facts)
struct RangeState final : ModuleState {
    Memo<Key2, XRange> word_memo, int_memo;
    Memo<Value, u8> unchecked_memo;  // 1: no, 2: yes
    // the variables: name -> (start << 32 | count) in var_values
    Memo<Value, u64> var_index;
    std::pmr::vector<Value> var_values;
    MemoSet<Value> cyclic, small;
    // the variables set to one value that means the same wherever it's read
    // (set_variables): what a sum may be read through, the facts applied in
    MemoSet<Value> stable;
    Memo<Value, u8> stable_memo;  // a value: 1 its meaning may change, 2 it can't
    bool vars_flagged = true;  // every variable has F_VAR (walks below them prune by it)
    bool fmp = true;
    // the variables whose values are being looked at (python _VISITING)
    SmallVec<Value, 8> visiting;

    // a compaction's imports
    std::pmr::vector<std::pair<Value, u64>> new_index;
    std::pmr::vector<Value> new_values, new_cyclic, new_small, new_stable;

    RangeState()
        : var_values(cx().budget.resource()),
          new_index(cx().budget.resource()),
          new_values(cx().budget.resource()),
          new_cyclic(cx().budget.resource()),
          new_small(cx().budget.resource()),
          new_stable(cx().budget.resource()) {
        // the loader's decision about the contract (python
        // variants.FREE_MEMORY_POINTER); set_free_memory_pointer changes it
        if (cx().shared) fmp = cx().shared->free_memory_pointer;
    }

    void clear_caches() override {
        word_memo.clear();
        int_memo.clear();
        unchecked_memo.clear();
        stable_memo.clear();
    }

    // whether x means the same wherever it's read, as a variable's value: it
    // reads no state (F_VOLATILE) and every variable it mentions is stable
    // (a loop's variable, a name set_variables wasn't given: it may change)
    bool stable_value(Value x) {
        if (x.has_flags(F_VOLATILE)) return false;
        if (!x.has_flags(F_VAR)) return true;
        if (x.is_name()) return stable.contains(x);
        if (!x.is_expr() && !x.is_list()) return true;
        if (const u8* m = stable_memo.find(x)) return *m == 2;
        check_stack();
        bool ok = true;
        for (Value a : x.children())
            if (!stable_value(a)) {
                ok = false;
                break;
            }
        stable_memo.put(x, ok ? 2 : 1);
        return ok;
    }

    std::span<const Value> values_of(Value name) const noexcept {
        const u64* p = var_index.find(name);
        if (!p) return {};
        return std::span<const Value>(var_values.data() + (*p >> 32), usize(*p & 0xffffffffu));
    }
    bool is_var(Value name) const noexcept { return var_index.contains(name); }
    bool any_vars() const noexcept { return !var_index.empty(); }

    bool compact_prepare(Importer& imp) override {
        // (nothing to keep: the state is made again, its flag the contract's)
        const bool fmp_default = cx().shared ? cx().shared->free_memory_pointer : true;
        if (var_index.empty() && small.empty() && fmp == fmp_default) return false;
        new_index.clear();
        new_values.clear();
        new_cyclic.clear();
        new_small.clear();
        new_stable.clear();
        for (Value v : var_values) new_values.push_back(imp(v));
        var_index.each([&](const Value& k, const u64& p) { new_index.emplace_back(imp(k), p); });
        cyclic.each([&](const Value& k) { new_cyclic.push_back(imp(k)); });
        small.each([&](const Value& k) { new_small.push_back(imp(k)); });
        stable.each([&](const Value& k) { new_stable.push_back(imp(k)); });
        return true;
    }
    void compact_commit() noexcept override {
        clear_caches();
        var_index.clear();
        cyclic.clear();
        small.clear();
        stable.clear();
        var_values.swap(new_values);
        // (the tables were just emptied: the inserts below reuse nothing that
        // can fail but the allocation, which a compaction's commit can't
        // report - the memo of a few names is small)
        try {
            for (auto& [k, p] : new_index) var_index.put(k, p);
            for (Value k : new_cyclic) cyclic.add(k);
            for (Value k : new_small) small.add(k);
            for (Value k : new_stable) stable.add(k);
        } catch (...) {
            // what's left: fewer facts about the variables, which is sound
            var_index.clear();
            var_values.clear();
            cyclic.clear();
            small.clear();
            stable.clear();
        }
        new_index.clear();
        new_values.clear();
        new_cyclic.clear();
        new_small.clear();
        new_stable.clear();
    }
    void compact_abort() noexcept override {
        new_index.clear();
        new_values.clear();
        new_cyclic.clear();
        new_small.clear();
        new_stable.clear();
    }
};

inline RangeState& rst() { return cx().state<RangeState>(); }

// a variable being looked at, for a scope
class Visiting {
public:
    Visiting(RangeState& s, Value name) : s_(s) { s_.visiting.push_back(name); }
    ~Visiting() { s_.visiting.pop_back(); }
    Visiting(const Visiting&) = delete;
    Visiting& operator=(const Visiting&) = delete;

private:
    RangeState& s_;
};

bool visiting(const RangeState& s, Value name) noexcept {
    for (Value v : s.visiting)
        if (v == name) return true;
    return false;
}

// ================================================================ readings

enum class Rd : u8 { Masks, Exact, Plain };  // python's masks=True, "exact", False
enum class Md : u8 { Word, Int };             // congruent to the word / python's integer
constexpr Rd kReadings[3] = {Rd::Masks, Rd::Exact, Rd::Plain};

struct LinItem {
    u64 key;     // the atom's raw word; the bits a mask clears: its raw word | 8
    Value atom;  // the term, or the mask whose cleared bits these are
    i32 off;     // -1: the term's word; >= 0: the cleared bits, in [0, 2^off - 1]
    XInt k;      // the coefficient (exact)
};

struct Lin {
    XInt c = kZero;
    SmallVec<LinItem, 6> items;
    bool overflow = false;  // a coefficient past 2^320: the reading says nothing
    u32 masks = 0;          // masks read (the readings differ only then)

    void add_c(const XInt& x) noexcept {
        if (!add_exact(c, c, x)) overflow = true;
    }
    void add(u64 key, Value atom, i32 off, const XInt& k) {
        if (k.zero()) return;
        for (LinItem& it : items)
            if (it.key == key) {
                if (!add_exact(it.k, it.k, k)) overflow = true;
                return;
            }
        items.push_back(LinItem{key, atom, off, k});
    }
};

// python BOUNDED_SYMBOLS: what gas pays for, below 2^64 in any execution
bool bounded_leaf(Op op) noexcept {
    switch (op) {
        case Op::CALLDATASIZE:
        case Op::RETURNDATASIZE:
        case Op::CODESIZE:
        case Op::MSIZE:
        case Op::GAS:
            return true;
        default:
            return false;
    }
}

// a word the contract is given (python INPUTS)
bool is_input(Value v) noexcept {
    if (v.is_name(NameKind::PARAM)) return true;
    switch (v.op()) {
        case Op::CALLDATALOAD:
        case Op::CALLDATA_BYTES:
        case Op::RETURNDATA_BYTES:
            return v.is_expr();
        default:
            return false;
    }
}

// what a word is computed from (python algebra.COMPUTED)
bool is_computed(Op op) noexcept {
    switch (op) {
        case Op::ADD: case Op::MUL: case Op::DIV: case Op::SDIV: case Op::MOD: case Op::SMOD:
        case Op::EXP: case Op::ADDMOD: case Op::MULMOD: case Op::SIGNEXTEND: case Op::AND:
        case Op::OR: case Op::XOR: case Op::NOT: case Op::MASK_SHL: case Op::SHL: case Op::SHR:
        case Op::SAR: case Op::BYTE: case Op::CLZ: case Op::MIN: case Op::MAX: case Op::SIZED:
        case Op::DATA:
            return true;
        default:
            return false;
    }
}

// a sum (python's add, and mul by a number): its terms are read, not it
bool is_sum(Value v) noexcept { return v.is(Op::ADD) || (v.is(Op::MUL) && v.size() >= 2 && v[0].is_int()); }

// solidity's free memory pointer, mem[64]
bool is_fmp(Value v) noexcept {
    return v.is(Op::MEM, 1) && v[0].is(Op::RANGE, 2) && v[0][0] == Value::small(64) && v[0][1] == Value::small(32);
}

i64 clamp4096(i64 x) noexcept { return std::max<i64>(-4096, std::min<i64>(4096, x)); }

}  // namespace

// ================================================================ the walk

struct RangeQuery::Impl {
    RangeState& st;
    // the facts' bounds (none: the context's memo tables are used)
    struct FB {
        Value x;
        XRange r;
    };
    SmallVec<FB, 8> fb;
    Memo<Value, u32> fb_index;  // x -> its place in fb + 1 (when fb is long)
    Memo<Key2, XRange> word_local, int_local;
    u32 visits = 0;
    Impl* plain = nullptr;  // without the facts (past the budget)

    static constexpr u32 kFactsBudget = 4096;
    static constexpr u32 kAboutBudget = 2048;  // the nodes of `about` looked at
    static constexpr usize kLinearBounds = 16;  // past it, fb_index

    explicit Impl(const Facts* facts, std::span<const Value> about = {}) : st(rst()) {
        // (the conditions' bounds and the variables' bits)
        if (!facts || !facts->any_bound()) return;
        MemoSet<Value> nodes;
        const bool all = about.empty() || !collect(about, nodes);
        facts->each_bound([&](Value x, Value lo, Value hi) {
            if (all || nodes.contains(x)) add_bound(x, XRange{xi_value(lo), xi_value(hi)});
        });
    }
    ~Impl() { delete plain; }
    Impl(const Impl&) = delete;
    Impl& operator=(const Impl&) = delete;

    // the nodes of what the questions are about (and the values of their
    // variables): false past kAboutBudget
    bool collect(std::span<const Value> about, MemoSet<Value>& nodes) {
        SmallVec<Value, 32> work(about);
        u32 budget = kAboutBudget;
        while (!work.empty()) {
            Value v = work.back();
            work.pop_back();
            if (!v.is_expr() && !v.is_leaf() && !v.is_name()) continue;
            if (!nodes.add(v)) continue;
            if (budget-- == 0) return false;
            if (v.is_name()) {
                // (a value whose meaning may change is ranged without the facts)
                for (Value x : st.values_of(v))
                    if (st.stable_value(x)) work.push_back(x);
            } else {
                for (Value a : v.children()) work.push_back(a);
            }
        }
        return true;
    }

    void add_bound(Value x, const XRange& r) {
        if (fb.size() < kLinearBounds) {
            for (FB& b : fb)
                if (b.x == x) {
                    b.r = xr_narrow(b.r, r);
                    return;
                }
            fb.push_back(FB{x, r});
            if (fb.size() == kLinearBounds)
                for (usize i = 0; i < fb.size(); ++i) fb_index.put(fb[i].x, u32(i + 1));
            return;
        }
        u32& at = fb_index[x];
        if (at) {
            fb[at - 1].r = xr_narrow(fb[at - 1].r, r);
            return;
        }
        at = u32(fb.size() + 1);
        fb.push_back(FB{x, r});
    }
    const XRange* bound_of(Value v) const noexcept {
        if (fb.size() >= kLinearBounds) {
            const u32* at = fb_index.find(v);
            return at ? &fb[*at - 1].r : nullptr;
        }
        for (const FB& b : fb)
            if (b.x == v) return &b.r;
        return nullptr;
    }
    bool with_facts() const noexcept { return !fb.empty(); }
    Impl& no_facts() {
        if (!plain) plain = new Impl(nullptr);
        return *plain;
    }

    // ---- words ----

    XRange word(Value v, Top top) {
        if (v.is_int()) return xr_point(xi_word(word_of(v)));
        if (v.is_bool()) return xr_point(xi(v.is_true() ? 1 : 0));
        if (!v.is_expr() && !v.is_leaf() && !v.is_name()) return xr_word();
        Memo<Key2, XRange>& memo = with_facts() ? word_local : st.word_memo;
        const Key2 key{v.raw(), u64(top)};
        if (const XRange* r = memo.find(key)) return *r;
        if (with_facts() && ++visits > kFactsBudget) return no_facts().word(v, top);
        check_stack();
        XRange r = compute_word(v, top);
        memo.put(key, r);
        return r;
    }

    XRange compute_word(Value v, Top top) {
        XRange r = xr_word();
        if (v.is_leaf()) {
            const Op op = v.op();
            if (bounded_leaf(op)) {
                r = xr_bits(64);
            } else if (info(op).sort == Sort::Bool) {
                r = xr_bits(1);
            } else {
                switch (op) {
                    case Op::ADDRESS: case Op::CALLER: case Op::ORIGIN: case Op::COINBASE:
                    case Op::CREATE_ADDRESS:
                        r = xr_bits(160);  // an address: 20 bytes
                        break;
                    default:
                        break;
                }
            }
        } else if (v.is_name()) {
            if (v.is_name(NameKind::MSIZE_VAR)) {
                r = xr_bits(64);
            } else if (st.is_var(v)) {
                r = var_range(v, top);
            }
        } else {
            r = structural(v, top);
            if (is_sum(v) || (v.is(Op::MASK_SHL, 4) && v[0].is_small() && v[1].is_small() && v[2].is_small()))
                r = xr_narrow(r, readings_word(v, top));
            const u32 b = max_bits(v);
            if (b < 256) r = xr_narrow(r, xr_bits(b));
        }
        if (with_facts())
            if (const XRange* b = bound_of(v)) r = xr_narrow(r, *b);
        if (top == Top::Memory && !is_sum(v)) r = clamp_memory(v, r);
        return r;
    }

    // python _term_range_of: with MEMORY_TOP, a term of an address or a size
    // is below it - unless it's made of what may not be a word, or of what
    // the contract is given unchecked, but for the words known to be small
    XRange clamp_memory(Value t, const XRange& r) {
        static constexpr XInt kMemTop = xi_ones(64);
        if (!(r.lo <= kMemTop)) return r;
        if (!r.hi.inf && r.hi <= kMemTop) return r;
        if (!st.small.contains(t) && (of_wrapped(t) || unchecked_of(t))) return r;
        return XRange{r.lo, kMemTop};
    }

    // python _of_wrapped: t is a word made of what may not be one (a mask
    // of -x...): an operand whose integer isn't a word
    bool of_wrapped(Value t) {
        auto wrapped = [&](Value a) {
            if (a.is_int()) {
                const XInt x = xi_value(a);
                return x.neg() || kWordMax < x;
            }
            return !xr_is_word(intv(a, Top::Word));
        };
        if (t.is(Op::MASK_SHL, 4)) return wrapped(t[3]);
        switch (t.op()) {
            case Op::DIV: case Op::MOD: case Op::AND: case Op::OR: case Op::XOR: case Op::MIN: case Op::MAX:
                if (!t.is_expr()) return false;
                for (Value a : t.args())
                    if (wrapped(a)) return true;
                return false;
            default:
                return false;
        }
    }

    bool unchecked_of(Value t);

    // python's: the union of the ranges of the values it's set to. A value
    // that reads state is read where the variable is set: the facts (of
    // here) say nothing of it - its range without them
    XRange var_range(Value name, Top top) {
        if (st.cyclic.contains(name) || visiting(st, name)) return xr_word();
        std::span<const Value> vals = st.values_of(name);
        if (vals.empty()) return xr_word();
        Visiting guard(st, name);
        auto value_range = [&](Value x) {
            return with_facts() && !st.stable_value(x) ? no_facts().word(x, top) : word(x, top);
        };
        XRange r = value_range(vals[0]);
        for (usize i = 1; i < vals.size(); ++i) {
            poll();
            r = xr_hull(r, value_range(vals[i]));
        }
        return r;
    }

    XRange structural(Value v, Top top);
    XRange mask_range(Value v);

    // the linear readings of a sum or a mask, as words
    XRange readings_word(Value v, Top top) {
        XRange best = xr_word();
        for (Rd rd : kReadings) {
            if (v.is(Op::MASK_SHL) && !mask_readable(v, rd, Md::Word, top)) continue;
            Lin acc;
            expand(v, kOne, rd, Md::Word, top, acc);
            if (!acc.overflow) best = xr_narrow(best, xr_as_word(lin_range(acc, top)));
            if (acc.masks == 0) break;  // the other readings read no more
        }
        return best;
    }

    // ---- python's integers ----

    XRange intv(Value v, Top top) {
        if (v.is_int()) return xr_point(xi_signed(v));
        if (v.is_bool()) return xr_point(xi(v.is_true() ? 1 : 0));
        if (!is_sum(v) && !v.is(Op::MASK_SHL, 4)) return word(v, top);
        Memo<Key2, XRange>& memo = with_facts() ? int_local : st.int_memo;
        const Key2 key{v.raw(), u64(top)};
        if (const XRange* r = memo.find(key)) return *r;
        if (with_facts() && ++visits > kFactsBudget) return no_facts().intv(v, top);
        check_stack();
        XRange best = v.is(Op::MASK_SHL) ? word(v, top) : xr_all();
        for (Rd rd : kReadings) {
            if (v.is(Op::MASK_SHL) && !mask_readable(v, rd, Md::Int, top)) continue;
            Lin acc;
            expand(v, kOne, rd, Md::Int, top, acc);
            if (!acc.overflow) best = xr_narrow(best, lin_range(acc, top));
            if (acc.masks == 0) break;
        }
        memo.put(key, best);
        return best;
    }

    XRange int_linear(const Linear& l, Top top) {
        XRange best = xr_all();
        for (Rd rd : kReadings) {
            Lin acc;
            acc.add_c(xi_value(l.constant));
            for (const LinTerm& t : l.terms) expand(t.term, xi_value(t.coeff), rd, Md::Int, top, acc);
            if (!acc.overflow) best = xr_narrow(best, lin_range(acc, top));
            if (acc.masks == 0) break;
        }
        return best;
    }

    // ---- the readings ----

    // MASK_SHL(size, off, shl, y) read as 2^shl * (y - d) (rd: which masks;
    // Md::Word: y below 2^(off + size) as a word - a congruence; Md::Int:
    // python's, y's integer a word below 2^(off + size), the result below
    // 2^256 - the integer exactly)
    bool mask_readable(Value v, Rd rd, Md md, Top top) {
        if (rd == Rd::Plain) return false;
        auto m = as_mask(v);
        if (!m || !m->concrete()) return false;
        const i64 size = m->isize(), off = m->ioff(), shl = m->ishl();
        if (size <= 0 || off < 0 || shl < 0 || off > 16) return false;
        if (rd == Rd::Exact && off != 0) return false;
        if (off + size > 256 || shl > 256) return false;
        if (may_be_wide(m->x)) return false;
        if (md == Md::Word) {
            if (off + size >= 256) return true;
            return word(m->x, top).hi < xi_pow2(u32(off + size));
        }
        const XRange y = intv(m->x, top);
        if (y.lo.inf || y.hi.inf || y.lo.neg()) return false;
        if (!(y.hi < xi_pow2(u32(off + size)))) return false;
        const XInt top_bits = xmul(y.hi, xi_pow2(u32(shl)));
        return top_bits.finite() && top_bits <= kWordMax;
    }

    // acc += mult * (v's reading)
    void expand(Value v, const XInt& mult, Rd rd, Md md, Top top, Lin& acc) {
        check_stack();
        if (acc.overflow) return;
        if (v.is_int() || v.is_bool()) {
            // (python's integers: lot 2's, a word in [-2^255, 2^255); a word
            // reading takes any representative)
            XInt t;
            if (!mul_exact(t, mult, md == Md::Int ? xi_signed(v) : xi_value(v)))
                acc.overflow = true;
            else
                acc.add_c(t);
            return;
        }
        if (v.is_name() && st.is_var(v) && !st.cyclic.contains(v) && !visiting(st, v)) {
            // a variable set to one value is that value (python's
            // cleanup_vars replaces it) - when that value is stable: it is
            // read where the variable is set, the same expression here may
            // mean something else since (tmp8 = mem[64] before the free
            // memory pointer moves is no mem[64] after; tmp5 = loop7 + 1 is
            // no loop7 + 1 once loop7 moved); its integer only when that's a
            // word
            std::span<const Value> vals = st.values_of(v);
            if (vals.size() == 1 && st.stable.contains(v) && (md == Md::Word || xr_is_word(intv(vals[0], top)))) {
                Visiting guard(st, v);
                expand(vals[0], mult, rd, md, top, acc);
                return;
            }
        }
        if (v.is_expr()) {
            switch (v.op()) {
                case Op::ADD:
                    for (Value t : v.args()) {
                        expand(t, mult, rd, md, top, acc);
                        if (acc.overflow) return;
                    }
                    return;
                case Op::MUL:
                    if (v.size() >= 2 && v[0].is_int()) {
                        XInt k;
                        if (!mul_exact(k, mult, md == Md::Int ? xi_signed(v[0]) : xi_value(v[0]))) {
                            acc.overflow = true;
                            return;
                        }
                        if (v.size() == 2) {
                            expand(v[1], k, rd, md, top, acc);
                            return;
                        }
                        // k times a product of several factors: lot 2's base
                        Linear l = linear(v);
                        XInt c;
                        if (!mul_exact(c, mult, xi_value(l.constant))) {
                            acc.overflow = true;
                            return;
                        }
                        acc.add_c(c);
                        for (const LinTerm& t : l.terms) {
                            XInt kt;
                            if (!mul_exact(kt, mult, xi_value(t.coeff))) {
                                acc.overflow = true;
                                return;
                            }
                            if (t.term == v) {
                                acc.add(v.raw(), v, -1, kt);
                            } else {
                                expand(t.term, kt, rd, md, top, acc);
                            }
                        }
                        return;
                    }
                    break;
                case Op::MASK_SHL:
                    if (mask_readable(v, rd, md, top)) {
                        const i64 off = v[1].small_val(), shl = v[2].small_val();
                        XInt k;
                        if (!mul_exact(k, mult, xi_pow2(u32(shl)))) {
                            acc.overflow = true;
                            return;
                        }
                        ++acc.masks;
                        expand(v[3], k, rd, md, top, acc);
                        if (off > 0) acc.add(v.raw() | 8, v, i32(off), xneg(k));
                        return;
                    }
                    break;
                default:
                    break;
            }
        }
        acc.add(v.raw(), v, -1, mult);
    }

    XRange atom_range(const LinItem& it, Top top) {
        if (it.off >= 0) return XRange{kZero, xi_ones(u32(it.off))};
        return word(it.atom, top);
    }

    XRange lin_range(const Lin& acc, Top top) {
        if (acc.overflow) return xr_all();
        XRange r = xr_point(acc.c);
        for (const LinItem& it : acc.items) r = xr_add(r, xr_scale(atom_range(it, top), it.k));
        return r;
    }

    // ---- differences ----

    // word(b) - word(a), an integer
    XRange diff(Value a, Value b, Top top) {
        if (a == b) return xr_point(kZero);
        const XRange ra = word(a, top), rb = word(b, top);
        XRange best = xr_sub(rb, ra);
        for (Rd rd : kReadings) {
            Lin la, lb;
            expand(a, kOne, rd, Md::Word, top, la);
            expand(b, kOne, rd, Md::Word, top, lb);
            const u32 masks = la.masks + lb.masks;
            if (!la.overflow && !lb.overflow) {
                auto ja = xr_window(lin_range(la, top));
                auto jb = xr_window(lin_range(lb, top));
                if (ja && jb) {
                    Lin& ld = lb;
                    ld.add_c(xneg(la.c));
                    for (const LinItem& it : la.items) ld.add(it.key, it.atom, it.off, xneg(it.k));
                    if (!ld.overflow) {
                        const XRange d = xr_shift(lin_range(ld, top), xneg(times_two256(*jb - *ja)));
                        best = xr_narrow(best, d);
                    }
                }
            }
            if (masks == 0) break;
        }
        return best;
    }

    // I(b) - I(a), python's integers
    XRange int_diff(Value a, Value b, Top top) {
        if (a == b) return xr_point(kZero);
        XRange best = xr_sub(intv(b, top), intv(a, top));
        for (Rd rd : kReadings) {
            Lin ld;
            expand(b, kOne, rd, Md::Int, top, ld);
            expand(a, xi(-1), rd, Md::Int, top, ld);
            if (!ld.overflow) best = xr_narrow(best, lin_range(ld, top));
            if (ld.masks == 0) break;
        }
        return best;
    }

    // ---- the decisions ----

    Tri lt(Value a, Value b, Top top) {
        const SignRange s = sign_of(diff(a, b, top));
        if (s.pos()) return Tri::True;
        if (s.nonpos()) return Tri::False;
        return Tri::None;
    }
    Tri le(Value a, Value b, Top top) {
        const SignRange s = sign_of(diff(a, b, top));
        if (s.nonneg()) return Tri::True;
        if (s.neg()) return Tri::False;
        return Tri::None;
    }
    Tri eq(Value a, Value b, Top top) {
        if (a == b) return Tri::True;
        if (auto c = const_diff(a, b)) return tri(int_sign(*c) == 0);
        const SignRange s = sign_of(diff(a, b, top));
        if (s.zero()) return Tri::True;
        if (s.nonzero()) return Tri::False;
        return Tri::None;
    }
    // signed: both in the same half, the unsigned order; else the signed ranges
    Tri slt(Value a, Value b, Top top, bool strict) {
        const XRange wa = word(a, top), wb = word(b, top);
        const bool la = wa.hi < kTwo255, lb = wb.hi < kTwo255;
        const bool ha = !(wa.lo < kTwo255), hb = !(wb.lo < kTwo255);
        if ((la && lb) || (ha && hb)) return strict ? lt(a, b, top) : le(a, b, top);
        const XRange sa = xr_signed(wa), sb = xr_signed(wb);
        if (strict) {
            if (sa.hi < sb.lo) return Tri::True;
            if (sb.hi <= sa.lo) return Tri::False;
        } else {
            if (sa.hi <= sb.lo) return Tri::True;
            if (sb.hi < sa.lo) return Tri::False;
        }
        return Tri::None;
    }
    Tri nonzero(Value v, Top top) {
        const XRange r = word(v, top);
        if (r.lo.sign() > 0) return Tri::True;
        if (r.hi.zero()) return Tri::False;
        return Tri::None;
    }
};

// python unchecked(t, _VARIABLES, _SMALL), remembered (only what holds
// whatever the variables being looked at: a yes, or a no found with none)
bool RangeQuery::Impl::unchecked_of(Value t) {
    struct Walk {
        RangeState& st;
        SmallVec<Value, 8> seen;
        bool hit = false;  // a variable already seen was met: a no isn't final
        bool run(Value e) {
            check_stack();
            if (!e.is_expr() && !e.is_name()) return false;
            if (st.small.contains(e)) return false;
            if (const u8* m = st.unchecked_memo.find(e)) return *m == 2;
            if (is_input(e)) return true;
            bool r = false;
            if (e.is_name()) {
                if (!st.is_var(e)) return false;
                for (Value s : seen)
                    if (s == e) {
                        hit = true;
                        return false;
                    }
                seen.push_back(e);
                for (Value v : st.values_of(e))
                    if (run(v)) {
                        r = true;
                        break;
                    }
            } else if (is_computed(e.op())) {
                // (nothing below that reads calldata, a call's result or a variable)
                if (st.vars_flagged && !e.has_flags(F_CALLDATA | F_STATE | F_VAR)) return false;
                for (Value x : e.args())
                    if (run(x)) {
                        r = true;
                        break;
                    }
            }
            if (r || !hit) st.unchecked_memo.put(e, r ? 2 : 1);
            return r;
        }
    } w{st, {}, false};
    return w.run(t);
}

XRange RangeQuery::Impl::mask_range(Value v) {
    auto m = as_mask(v);
    if (!m || !m->concrete()) return xr_word();
    const i64 size = clamp4096(m->isize()), off = clamp4096(m->ioff()), shl = clamp4096(m->ishl());
    const bool wide = may_be_wide(m->x);
    XRange rx = wide ? xr_word() : word(m->x, Top::Word);
    i64 high_bit = clamp4096(off + size);
    if (!wide) high_bit = std::min<i64>(high_bit, i64(bitlen(rx.hi)));
    const i64 bottom = std::max<i64>(off, 0);
    if (high_bit <= bottom) return xr_point(kZero);
    // python: (2^high_bit - 2^bottom) moved by shl, at most a word
    XRange r = xr_word();
    if (high_bit <= i64(kSatBits)) {
        XInt high;
        raw_add(high, xi_pow2(u32(high_bit)), xneg(xi_pow2(u32(bottom))));
        if (shl >= 0) {
            high = shl < i64(kSatBits) ? xmul(high, xi_pow2(u32(shl))) : xi_inf(1);
        } else {
            // high >> -shl: the bits [bottom, high_bit) moved down
            const i64 nb = std::max<i64>(bottom + shl, 0), nh = high_bit + shl;
            high = nh <= nb ? kZero : (nh <= 0 ? kZero : [&] {
                XInt h;
                raw_add(h, xi_pow2(u32(nh)), xneg(xi_pow2(u32(nb))));
                return h;
            }());
        }
        r = XRange{kZero, high.inf || kWordMax < high ? kWordMax : high};
    }
    // all of x's bits within the field: the mask is monotone in x,
    // (x >> off) << (off + shl), when nothing goes past the word
    if (!wide && off >= 0 && size > 0 && off + size <= 256 && off + shl >= 0 && rx.hi < xi_pow2(u32(off + size))) {
        const Word256 lo = shr(Word256::of(u64(off)), to_w(rx.lo)), hi = shr(Word256::of(u64(off)), to_w(rx.hi));
        const XInt f = xi_pow2(u32(off + shl));
        const XInt flo = xmul(xi_word(lo), f), fhi = xmul(xi_word(hi), f);
        if (fhi.finite() && fhi <= kWordMax) r = xr_narrow(r, XRange{flo, fhi});
    }
    return r;
}

XRange RangeQuery::Impl::structural(Value v, Top top) {
    const Op op = v.op();
    if (info(op).sort == Sort::Bool) return xr_bits(1);
    auto args = v.args();
    switch (op) {
        case Op::ADD:
            return xr_word();  // (the readings)
        case Op::MUL: {
            if (v.size() >= 2 && v[0].is_int()) return xr_word();  // (the readings)
            // a product of words, mod 2^256: their product, when it's one word
            XRange r = word(args[0], Top::Word);
            for (usize i = 1; i < args.size(); ++i) r = xr_mul(r, word(args[i], Top::Word));
            return xr_as_word(r);
        }
        case Op::CLZ:
            return xr_of(0, 256);
        case Op::BYTE:
            return xr_bits(8);
        case Op::DIV:
        case Op::SDIV: {
            const XRange x = word(args[0], Top::Word), y = word(args[1], Top::Word);
            if (op == Op::SDIV && !(x.hi < kTwo255 && y.hi < kTwo255)) return xr_word();
            // x / 0 = 0; x / y <= x
            if (y.lo.sign() <= 0) return XRange{kZero, x.hi};
            return XRange{xi_word(div(to_w(x.lo), to_w(y.hi))), xi_word(div(to_w(x.hi), to_w(y.lo)))};
        }
        case Op::MOD:
        case Op::SMOD: {
            const XRange x = word(args[0], Top::Word), y = word(args[1], top);
            if (op == Op::SMOD && !(x.hi < kTwo255 && y.hi < kTwo255)) return xr_word();
            if (x.hi < y.lo) return x;  // x < y: x % y = x
            // below what it's divided by (0 by 0), at most x
            XInt hi = y.hi.sign() > 0 ? add_hi(y.hi, xi(-1)) : kZero;
            return XRange{kZero, xmin(hi, x.hi)};
        }
        case Op::ADDMOD:
        case Op::MULMOD: {
            const XRange n = word(args[2], Top::Word);
            return XRange{kZero, n.hi.sign() > 0 ? add_hi(n.hi, xi(-1)) : kZero};
        }
        case Op::EXP: {
            const XRange b = word(args[0], Top::Word), e = word(args[1], Top::Word);
            if (b.lo.sign() > 0) {
                const XInt hi = xpow_hi(b.hi, e.hi);
                if (hi.finite() && hi <= kWordMax) return XRange{xpow_lo(b.lo, e.lo), hi};
                return xr_word();
            }
            // 0 ** 0 = 1, 0 ** e = 0
            const XInt hi = xmax(kOne, xpow_hi(b.hi, e.hi));
            if (hi.finite() && hi <= kWordMax) return XRange{kZero, hi};
            return xr_word();
        }
        case Op::AND: {
            XInt hi = kWordMax;
            for (Value a : args) hi = xmin(hi, word(a, Top::Word).hi);
            return XRange{kZero, hi};
        }
        case Op::OR:
        case Op::XOR: {
            XInt lo = kZero, hi = kZero;
            for (Value a : args) {
                const XRange r = word(a, Top::Word);
                if (op == Op::OR) lo = xmax(lo, r.lo);
                hi = xmax(hi, r.hi);
            }
            return XRange{lo, xi_ones(std::min<u32>(256, bitlen(hi)))};
        }
        case Op::NOT: {
            const XRange x = word(args[0], Top::Word);
            XInt lo, hi;
            raw_add(lo, kWordMax, xneg(x.hi));
            raw_add(hi, kWordMax, xneg(x.lo));
            return XRange{lo, hi};
        }
        case Op::SHR:
        case Op::SAR: {
            const XRange s = word(args[0], Top::Word), x = word(args[1], Top::Word);
            if (op == Op::SAR && !(x.hi < kTwo255)) return xr_word();
            static constexpr XInt k256 = xi(256);
            if (!(s.lo < k256)) return xr_point(kZero);
            const XInt lo = !(s.hi < k256) ? kZero : xi_word(shr(to_w(s.hi), to_w(x.lo)));
            return XRange{lo, xi_word(shr(to_w(s.lo), to_w(x.hi)))};
        }
        case Op::SHL: {
            const XRange s = word(args[0], Top::Word), x = word(args[1], Top::Word);
            static constexpr XInt k256 = xi(256);
            if (!(s.hi < k256)) return xr_word();
            const XInt hi = xmul(x.hi, xi_pow2(u32(s.hi.l[0])));
            if (!hi.finite() || kWordMax < hi) return xr_word();
            return XRange{xmul(x.lo, xi_pow2(u32(s.lo.l[0]))), hi};
        }
        case Op::SIGNEXTEND: {
            const XRange b = word(args[0], Top::Word), x = word(args[1], Top::Word);
            static constexpr XInt k31 = xi(31);
            if (!(b.lo < k31)) return x;
            // the sign bit (8b + 7) clear for the smallest b: x itself
            if (x.hi < xi_pow2(u32(8 * b.lo.l[0] + 7))) return x;
            return xr_word();
        }
        case Op::MASK_SHL:
            return mask_range(v);
        case Op::MIN:
        case Op::MAX: {
            XRange r = word(args[0], Top::Word);
            for (usize i = 1; i < args.size(); ++i) {
                const XRange o = word(args[i], Top::Word);
                if (op == Op::MIN)
                    r = XRange{xmin(r.lo, o.lo), xmin(r.hi, o.hi)};
                else
                    r = XRange{xmax(r.lo, o.lo), xmax(r.hi, o.hi)};
            }
            return r;
        }
        case Op::STORAGE:
            if (args[0].is_small() && args[1].is_small() && args[1].small_val() >= 0)
                return xr_bits(u32(std::max<i64>(0, std::min<i64>(args[0].small_val(), 256))));
            return xr_word();
        case Op::MEM:
            if (st.fmp && is_fmp(v)) return XRange{xi(0x60), kWordMax};
            return xr_word();
        case Op::LAND: {
            // python's `and`: a when it's 0, else b
            const XRange a = word(args[0], Top::Word), b = word(args[1], Top::Word);
            if (a.lo.sign() > 0) return b;
            if (a.hi.zero()) return xr_point(kZero);
            return xr_hull(xr_point(kZero), b);
        }
        case Op::LOR: {
            // python's `or`: a when it isn't 0, else b
            const XRange a = word(args[0], Top::Word), b = word(args[1], Top::Word);
            if (a.lo.sign() > 0) return a;
            if (a.hi.zero()) return b;
            return xr_hull(a, b);
        }
        default:
            return xr_word();
    }
}

// ================================================================ the public side

RangeQuery::RangeQuery(const Facts* facts, std::span<const Value> about) : impl_(new Impl(facts, about)) {}
RangeQuery::~RangeQuery() { delete impl_; }

namespace {

// an expression too deep for the stack (DepthLimit, never a Timeout): what
// holds without looking - the ranges are a refinement, never needed
template <class F, class R>
R guarded(F&& f, R fallback) {
    try {
        return f();
    } catch (const DepthLimit&) {
        return fallback;
    }
}

const XRange kAnyDiff = XRange{xneg(kWordMax), kWordMax};
const XRange kAnySigned = XRange{xneg(kTwo255), add_hi(kTwo255, xi(-1))};

}  // namespace

Range RangeQuery::range(Value v, Top top) {
    return to_range(guarded([&] { return impl_->word(v, top); }, xr_word()));
}
Range RangeQuery::signed_range(Value v, Top top) {
    return to_range(guarded([&] { return xr_signed(impl_->word(v, top)); }, kAnySigned));
}
Range RangeQuery::word_diff(Value a, Value b, Top top) {
    return to_range(guarded([&] { return impl_->diff(a, b, top); }, kAnyDiff));
}
SignRange RangeQuery::diff_sign(Value a, Value b, Top top) {
    return sign_of(guarded([&] { return impl_->diff(a, b, top); }, kAnyDiff));
}
Range RangeQuery::int_range(Value v, Top top) {
    return to_range(guarded([&] { return impl_->intv(v, top); }, xr_all()));
}
Range RangeQuery::int_range(const Linear& l, Top top) {
    return to_range(guarded([&] { return impl_->int_linear(l, top); }, xr_all()));
}
SignRange RangeQuery::int_diff_sign(Value a, Value b, Top top) {
    return sign_of(guarded([&] { return impl_->int_diff(a, b, top); }, xr_all()));
}
u32 RangeQuery::range_bits(Value v, Top top) {
    const XRange r = guarded([&] { return impl_->word(v, top); }, xr_word());
    return std::min<u32>(256, bitlen(r.hi));
}
Tri RangeQuery::lt(Value a, Value b, Top top) {
    return guarded([&] { return impl_->lt(a, b, top); }, Tri::None);
}
Tri RangeQuery::le(Value a, Value b, Top top) {
    return guarded([&] { return impl_->le(a, b, top); }, Tri::None);
}
Tri RangeQuery::eq(Value a, Value b, Top top) {
    return guarded([&] { return impl_->eq(a, b, top); }, Tri::None);
}
Tri RangeQuery::slt(Value a, Value b, Top top) {
    return guarded([&] { return impl_->slt(a, b, top, true); }, Tri::None);
}
Tri RangeQuery::sle(Value a, Value b, Top top) {
    return guarded([&] { return impl_->slt(a, b, top, false); }, Tri::None);
}
Tri RangeQuery::nonzero(Value v, Top top) {
    return guarded([&] { return impl_->nonzero(v, top); }, Tri::None);
}

Range Range::word() { return Range{EvmInt(0), word_max()}; }

Range Range::bits(u32 n) {
    if (n >= 256) return word();
    return Range{EvmInt(0), EvmInt::pow2(n) - EvmInt(1)};
}

bool Range::is_word() const noexcept { return lo.sign() >= 0 && hi <= word_max(); }

std::optional<Range> Range::meet(const Range& o) const {
    const EvmInt& l = lo < o.lo ? o.lo : lo;
    const EvmInt& h = hi < o.hi ? hi : o.hi;
    if (h < l) return std::nullopt;
    return Range{l, h};
}

Range Range::hull(const Range& o) const { return Range{lo < o.lo ? lo : o.lo, hi < o.hi ? o.hi : hi}; }

Range Range::as_word() const {
    if (is_word()) return *this;
    EvmInt j = floordiv(lo, two_256());
    if (floordiv(hi, two_256()) != j) return word();
    EvmInt shift = j * two_256();
    return Range{lo - shift, hi - shift};
}

Range range(Value v, Top top, const Facts* facts) { return RangeQuery(facts, {&v, 1}).range(v, top); }
Range signed_range(Value v, Top top, const Facts* facts) { return RangeQuery(facts, {&v, 1}).signed_range(v, top); }
Range word_diff(Value a, Value b, Top top, const Facts* facts) {
    const Value ab[2] = {a, b};
    return RangeQuery(facts, ab).word_diff(a, b, top);
}
SignRange diff_sign(Value a, Value b, Top top, const Facts* facts) {
    const Value ab[2] = {a, b};
    return RangeQuery(facts, ab).diff_sign(a, b, top);
}
Range int_range(const Linear& l, Top top, const Facts* facts) {
    SmallVec<Value, 8> about;
    for (const LinTerm& t : l.terms) about.push_back(t.term);
    if (about.empty()) about.push_back(l.constant);
    return RangeQuery(facts, about.span()).int_range(l, top);
}
Range int_range(Value v, Top top, const Facts* facts) { return RangeQuery(facts, {&v, 1}).int_range(v, top); }
SignRange int_diff_sign(Value a, Value b, Top top, const Facts* facts) {
    const Value ab[2] = {a, b};
    return RangeQuery(facts, ab).int_diff_sign(a, b, top);
}
u32 range_bits(Value v, Top top, const Facts* facts) { return RangeQuery(facts, {&v, 1}).range_bits(v, top); }

bool is_word(Value v, Top top, const Facts* facts) { return int_range(v, top, facts).is_word(); }

std::optional<int> shift_sign(Value v) {
    if (v.is_int() && int_sign(v) == 0) return 0;
    const Range r = int_range(v);
    if (r.is_word()) return 1;
    if (r.lo >= -word_max() && r.hi.sign() <= 0) return -1;
    return std::nullopt;
}

// ---- the algebra context ----

namespace {

// the variables a value mentions (directly): names that are variables
void mentioned_vars(const RangeState& s, Value v, MemoSet<Value>& seen, SmallVec<Value, 8>& out) {
    check_stack();
    if (v.is_name()) {
        if (s.is_var(v) && seen.add(v)) out.push_back(v);
        return;
    }
    if (!v.is_expr() && !v.is_list()) return;
    if (s.vars_flagged && !v.has_flags(F_VAR)) return;
    if (!seen.add(v)) return;
    for (Value a : v.children()) mentioned_vars(s, a, seen, out);
}

}  // namespace

void set_variables(std::span<const std::pair<Value, Value>> name_values, std::span<const Value> small) {
    RangeState& s = rst();
    s.var_index.clear();
    s.var_values.clear();
    s.cyclic.clear();
    s.small.clear();
    s.stable.clear();
    s.stable_memo.clear();
    s.vars_flagged = true;
    // the values grouped by name (the order of the names: their words - a
    // name is an immediate; nothing depends on the order but the layout)
    std::pmr::vector<std::pair<Value, Value>> pairs(name_values.begin(), name_values.end(), cx().budget.resource());
    std::stable_sort(pairs.begin(), pairs.end(),
                     [](const auto& a, const auto& b) { return a.first.raw() < b.first.raw(); });
    for (usize i = 0; i < pairs.size();) {
        poll();
        usize j = i;
        while (j < pairs.size() && pairs[j].first == pairs[i].first) ++j;
        const u64 start = s.var_values.size();
        for (usize k = i; k < j; ++k) s.var_values.push_back(pairs[k].second);
        s.var_index.put(pairs[i].first, (start << 32) | u64(j - i));
        if (!pairs[i].first.has_flags(F_VAR)) s.vars_flagged = false;
        i = j;
    }
    for (Value v : small) s.small.add(v);
    // the cyclic ones: a value made of the variable itself, directly or
    // through other variables (a loop's counter): python's _CYCLIC
    if (!s.var_index.empty()) {
        std::pmr::vector<Value> names(cx().budget.resource());
        s.var_index.each([&](const Value& k, const u64&) { names.push_back(k); });
        std::sort(names.begin(), names.end(), [](Value a, Value b) { return a.raw() < b.raw(); });
        // each variable's direct successors
        std::pmr::vector<std::pmr::vector<Value>> succ(cx().budget.resource());
        Memo<Value, u32> pos;
        for (usize i = 0; i < names.size(); ++i) pos.put(names[i], u32(i));
        for (Value n : names) {
            poll();
            MemoSet<Value> seen;
            SmallVec<Value, 8> out;
            for (Value v : s.values_of(n)) mentioned_vars(s, v, seen, out);
            succ.emplace_back(out.begin(), out.end());
        }
        // n is cyclic when it reaches itself
        for (usize i = 0; i < names.size(); ++i) {
            poll();
            std::pmr::vector<u32> stack(cx().budget.resource());
            std::pmr::vector<bool> done(names.size(), false, cx().budget.resource());
            for (Value m : succ[i]) stack.push_back(*pos.find(m));
            while (!stack.empty()) {
                const u32 k = stack.back();
                stack.pop_back();
                if (k == i) {
                    s.cyclic.add(names[i]);
                    break;
                }
                if (done[k]) continue;
                done[k] = true;
                for (Value m : succ[k]) stack.push_back(*pos.find(m));
            }
        }
    }
    // the stable ones: one value, not cyclic, that reads no state and whose
    // variables are stable (a loop's variable, a name not given: never)
    if (!s.var_index.empty()) {
        Memo<Value, u8> state;  // 1 being looked at, 2 stable, 3 not
        auto stable_name = [&](auto&& self, Value n) -> bool {
            check_stack();
            u8& at = state[n];
            if (at) return at == 2;
            at = 1;
            std::span<const Value> vals = s.values_of(n);
            bool ok = vals.size() == 1 && !s.cyclic.contains(n) && !vals[0].has_flags(F_VOLATILE);
            if (ok && vals[0].has_flags(F_VAR)) {
                // every name with F_VAR in it: a stable variable
                SmallVec<Value, 16> work{vals[0]};
                MemoSet<Value> seen;
                while (ok && !work.empty()) {
                    Value x = work.back();
                    work.pop_back();
                    if (!x.has_flags(F_VAR) || !seen.add(x)) continue;
                    if (x.is_name()) {
                        ok = s.is_var(x) && x != n && self(self, x);
                    } else {
                        for (Value a : x.children()) work.push_back(a);
                    }
                }
            }
            state[n] = ok ? 2 : 3;  // (the reference may have moved: the table grew)
            return ok;
        };
        s.var_index.each([&](const Value& k, const u64&) {
            if (stable_name(stable_name, k)) s.stable.add(k);
        });
    }
    cx().clear_caches();
}

void clear_variables() { set_variables({}, {}); }

void set_free_memory_pointer(bool on) {
    RangeState& s = rst();
    if (s.fmp == on) return;
    s.fmp = on;
    cx().clear_caches();
}

bool free_memory_pointer() { return rst().fmp; }

bool unchecked(Value v) {
    RangeQuery::Impl impl(nullptr);
    return impl.unchecked_of(v);
}

}  // namespace pan::alg
