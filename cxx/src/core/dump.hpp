// Debug and test text of Values: S-expressions (the only text in the core).
//
//   (add 1 (mask_shl 160 0 0 caller))      expression: (op_name operand...)
//   caller   (call_success 3)              leaf; a leaf whose n != 0 is (name n)
//   tmp3 loop5 loopid1 _msize param0 stor2 sm0 prec_1_0 func_a9059cbb
//   fallback internal_1234                 names (name_K_I for an unknown kind)
//   True False None NIL                    immediates; NIL = no value
//   -5 4611686018427387904 -> 0x4000000000000000   small ints decimal, big ints 0x...
//   b"ab\"\x00"                            bytes (\\ \" \n \t \r \0 \xHH)
//   [a b]  {line line}                     list of values, trace
//
// The variable _msize is written with an underscore: msize is the EVM leaf.
// parse_sexpr (sexpr.rl, a Ragel machine) is the exact inverse of dump and also
// reads dump_trace's output (whitespace is free). Errors: InvalidInput with the
// byte offset.
#pragma once

#include <string>
#include <string_view>

#include "core/value.hpp"

namespace pan {

std::string dump(Value v);
// One line per trace line; the trace operands of a line (IF/WHILE bodies) are
// written as indented {...} blocks under it. A non-trace value is one line.
std::string dump_trace(Value v);

Value parse_sexpr(std::string_view text);  // on cx()

// Test helper: auto v = V("(add 1 (calldataload 4))");
inline Value V(std::string_view s) { return parse_sexpr(s); }

}  // namespace pan
