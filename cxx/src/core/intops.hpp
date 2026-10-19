// Integer arithmetic on Values (python's unbounded ints): two small ints
// take the fast path (__builtin_*_overflow), anything else goes through
// EvmInt. Every result is made on cx().
#pragma once

#include "core/value.hpp"

namespace pan {

Value int_add(Value a, Value b);
Value int_sub(Value a, Value b);
Value int_mul(Value a, Value b);
Value int_neg(Value a);
int int_sign(Value a);              // -1, 0, 1
int int_cmp(Value a, Value b);      // -1, 0, 1 (numeric)
bool int_tstbit(Value a, u64 bit);  // two's complement, python semantics
bool int_is(Value a, i64 x);        // a is the small int x

}  // namespace pan
