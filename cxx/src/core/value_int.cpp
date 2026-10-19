// The glue between Values and the integer classes (EvmInt, Word256), and
// the Value-level fast paths of core/intops.hpp.
#include <gmpxx.h>

#include "core/context.hpp"
#include "core/evmint.hpp"
#include "core/intops.hpp"
#include "core/node.hpp"

namespace pan {

EvmInt::EvmInt(Value v) : EvmInt() {
    if (v.is_small()) {
        *this = EvmInt(v.small_val());
        return;
    }
    if (!v.is_big()) throw InternalError("EvmInt: not an int");
    mpz_t t;
    *this = EvmInt(mpz_class(big_view(v, t)));
}

Value EvmInt::value() const {
    if (const mpz_class* z = big()) return mk_int_mpz(z->get_mpz_t());
    return mk_int(to_i64());
}

Word256 Word256::from_value(Value v) {
    if (v.is_small()) {
        i64 x = v.small_val();
        u64 fill = x < 0 ? ~u64(0) : 0;
        return Word256{{u64(x), fill, fill, fill}};
    }
    return from_int(EvmInt(v));
}

Value Word256::to_value() const {
    if (!(limb[1] | limb[2] | limb[3]) && limb[0] <= u64(SMALL_MAX)) return Value::small(i64(limb[0]));
    return to_int().value();
}

// --- the fast paths ---

Value int_add(Value a, Value b) {
    i64 r;
    if (a.is_small() && b.is_small() && !__builtin_add_overflow(a.small_val(), b.small_val(), &r)) return mk_int(r);
    return (EvmInt(a) + EvmInt(b)).value();
}

Value int_sub(Value a, Value b) {
    i64 r;
    if (a.is_small() && b.is_small() && !__builtin_sub_overflow(a.small_val(), b.small_val(), &r)) return mk_int(r);
    return (EvmInt(a) - EvmInt(b)).value();
}

Value int_mul(Value a, Value b) {
    i64 r;
    if (a.is_small() && b.is_small() && !__builtin_mul_overflow(a.small_val(), b.small_val(), &r)) return mk_int(r);
    return (EvmInt(a) * EvmInt(b)).value();
}

Value int_neg(Value a) {
    if (a.is_small()) return mk_int(-a.small_val());  // |small| < 2^62: no overflow
    return (-EvmInt(a)).value();
}

int int_sign(Value a) {
    if (a.is_small()) return (a.small_val() > 0) - (a.small_val() < 0);
    mpz_t t;
    return mpz_sgn(big_view(a, t));
}

int int_cmp(Value a, Value b) {
    if (a == b) return 0;
    if (a.is_small() && b.is_small()) return a.small_val() < b.small_val() ? -1 : 1;
    if (a.is_small()) return -int_sign(b);  // b is big: |b| >= 2^62 > |a|
    if (b.is_small()) return int_sign(a);
    mpz_t ta, tb;
    int c = mpz_cmp(big_view(a, ta), big_view(b, tb));
    return (c > 0) - (c < 0);
}

bool int_tstbit(Value a, u64 bit) {
    if (a.is_small()) return bit >= 63 ? a.small_val() < 0 : (a.small_val() >> bit) & 1;
    return EvmInt(a).test_bit(bit);
}

bool int_is(Value a, i64 x) { return a.is_small() && a.small_val() == x; }

}  // namespace pan
