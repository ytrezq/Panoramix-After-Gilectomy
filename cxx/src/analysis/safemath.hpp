// SafeMath (lot 8; python safemath.py; asm safemath.s): the arithmetic a
// contract checks before it uses its result - OpenZeppelin's SafeMath,
// ds-math (solidity < 0.8: a library's internal functions, inlined), the
// compiler's own checks since solidity 0.8 (Panic(0x11) on an overflow,
// Panic(0x12) on a division by zero), Vyper's - made calls of the
// contract's `def SafeMath:` functions in the asts (Stage::Folded, after
// lot 10's fold): `c = a + b; require c >= a, '...'; use(c)` ->
// `use(SafeMath.add(a, b))`.
//
// A check is a line that fails where its condition holds and else goes on:
// IF(c, [F], []), IF(c, [], [F]) (fails where c is 0), REQUIRE(c[, data]),
// ASSERT(c), and an IF one branch of which is F (the other goes on), F
// being REVERT(None), REVERT(Error(string) of printable text), REVERT
// (Panic(code)) or INVALID. Checks of one operation (python match_check:
// `a + b < a`, `b > a` for a - b, `a == 0 or a * b / a == b`, `b == 0` for a
// / b, solidity's `a == max` for a + 1...) whose result is used after them,
// with nothing between that may fail or change what they read (lot 7's
// affects: only SETVAR SETMEM STORE SET LOG lines - and, not python's, the
// checks of other operations that fail exactly as they do) are removed,
// the result being a SAFEMATH call where it is used - in that line, and the
// lines after it until one changes what the result reads (python _uses).
// The checks only move past lines that can't fail and change nothing they
// read, and past checks failing the same way (the same revert data, the
// same panic, both INVALID: an order no call can tell): how a run fails is
// the original's.
#pragma once

#include <memory>
#include <optional>
#include <span>
#include <vector>

#include "core/base.hpp"
#include "core/contract.hpp"
#include "core/value.hpp"

namespace pan {

// The functions of the contract's SafeMath (python's defs). In an ast,
//     SAFEMATH(n, a[, b][, d_0, ..., d_{m-1}])
// calls fns[n] (n a small int; b when fns[n].params is 2; m =
// fns[n].messages: the data its checks with a message parameter revert
// with, in their order). It runs:
//   1. a, then b, evaluated where the SAFEMATH is (not the d's);
//   2. Name(SAFEMATH_PARAM, 0) := a, Name(SAFEMATH_PARAM, 1) := b;
//   3. each check in order: where its cond is nonzero, the run halts with
//      its `fail` line (REVERT(data), REVERT(None), INVALID(reason, pc)) -
//      or, a check with a message parameter (message = k), with
//      REVERT(d_k), d_k evaluated where the SAFEMATH is;
//   4. its value: `result` evaluated with a and b.
// The conds and results read the two params and constants only.
struct SafeMathTable {
    // python's RESULTS, in the block's order: their names add sub mul div mod inc dec
    enum class Arith : u8 { Add, Sub, Mul, Div, Mod, Inc, Dec };
    // how a check fails (python failure())
    enum class Fail : u8 {
        Revert,   // REVERT(None)
        Error,    // REVERT of Error(string): python's revert with 'message'
        Panic,    // REVERT of Panic(code) (solidity >= 0.8)
        Invalid,  // INVALID (an assert of solidity < 0.8)
    };
    struct Check {
        Value cond;  // the check fails where it is nonzero (a, b: Name(SAFEMATH_PARAM, 0 / 1))
        Fail kind = Fail::Revert;
        u32 panic = 0;                // Panic: its code (0x11 overflow, 0x12 division by zero)
        Value fail;                   // the halting line (NIL when message is set)
        std::optional<u32> message;   // the call's d_k it reverts with: a message parameter
                                      // (python's errorMessage, errorMessage2...: k = 0, 1...)
    };
    struct Fn {
        Arith op = Arith::Add;
        u32 number = 1;    // the number-th function of op: python's names add, add2, add3...
        u32 params = 2;    // a, b (inc, dec: a only)
        u32 messages = 0;  // the message parameters (the d operands of its calls)
        Value result;      // what it returns: ADD(a, b), ADD(a, MUL(-1, b)), MUL(a, b), DIV(a, b),
                           // MOD(a, b), ADD(1, a), ADD(-1, a)
        std::vector<Check> checks;
    };
    std::vector<Fn> fns;  // in the block's order: by op (Arith's order), then number
};

namespace safemath {

// The Folded stage's asts of a contract (the functions in their order, the
// internal ones by entry), rewritten in place: their checked arithmetic as
// SAFEMATH calls; the table of the functions called (null when none). A
// function that failed (problem, or no trace) is left alone. Everything is
// made aside first: an Error leaves every ast as it was (the caller logs
// python's "SafeMath failed: the arithmetic stays as it is."). On cx().
std::shared_ptr<const SafeMathTable> rewrite(std::span<FunctionInfo> functions, std::span<FunctionInfo> internals,
                                             const ContractShared& shared);

}  // namespace safemath
}  // namespace pan
