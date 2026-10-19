// Effect summaries (lot 7; python simplify.affects / changes_reads /
// overwrites_mem / trace_uses_mem / trace_ends_execution, arithmetic
// changed_by / may_alias, whiles.PURE_LINES; asm cleanup.s line_summary,
// affects): what a line, a trace or an expression reads and writes of the
// state, and how its paths end - the one place where "may this line change
// what that expression reads" is answered (lots 6, 7, 8, 10).
//
// A summary is a function of the node alone (no algebra context), memoized
// per node: an IF / WHILE / trace's is the union of its parts'. Its state
// classes (S_*) are bits; for the classes with places (memory ranges,
// storage regions, transient keys, variables, call ids) the places are LISTs
// - or "anywhere" (the class's bit in *_any) when they aren't known or past
// kMaxPlaces. Everything is conservative: a place that may be touched is.
//
// What reads and writes what (ir.md section 4):
//  - expressions read: MEM(RANGE) memory (S_MEM, the range); MSIZE S_MSIZE;
//    STORAGE(size, off, slot) / LENGTH(key) storage (the region; SBYTES,
//    SALL, ST and the P forms anywhere); TLOAD(k) S_TRANSIENT (k); BALANCE,
//    EXTCODESIZE, EXTCODEHASH, SELFBALANCE, EXTCODE_BYTES S_ACCOUNT;
//    Leaf(CALL_SUCCESS | CREATE_ADDRESS | RETURNDATASIZE, id),
//    RETURNDATA_BYTES(id, ...) S_CALLRES (the id; RETURNDATASIZE 0 is a
//    constant); GAS S_GAS (numbered reads, never written: python inlined
//    them anywhere); names S_VARS (the Name; a PARAM is calldata);
//    CALLDATALOAD, CALLDATA_BYTES, CALLDATASIZE, PARAM S_CALLDATA; the
//    context leaves S_CTX. A SAFEMATH may fail (C_FAILS).
//  - lines write: SETVAR its name; SETMEM its range (and S_MSIZE: every line
//    that reads or writes memory may grow it); STORE(size, off, slot, _)
//    STORAGE(size, off, slot) (SET of the P forms: anywhere); TSTORE its
//    key; LOG S_LOG; CALL CALLCODE DELEGATECALL CREATE CREATE2 storage,
//    transient, accounts anywhere and their own id (their output is the
//    SETMEM lines after them, not theirs); STATICCALL and PRECOMPILED only
//    their id (and PRECOMPILED its result variable); SELFDESTRUCT accounts;
//    INTERNAL everything anywhere (memory, storage, calls...) and its result
//    names, and may end the call; WHILE / CONTINUE / GOTO / LABEL their
//    setvars' names; IF / WHILE / MERGED_IF / LOOP_PATH their parts'.
//  - LEAVE reads all memory (the caller goes on with it); RETURN / REVERT /
//    LOG / SHA3 / calls read the memory of their bytes.
//  - control: C_HALTS (STOP RETURN SELFDESTRUCT), C_FAILS (REVERT INVALID
//    REQUIRE ASSERT, a SAFEMATH), C_UNDEFINED, C_LEAVES (LEAVE), C_JUMPS
//    (CONTINUE GOTO BREAK: to a loop's head or exit; LABEL: the lines after
//    it run again), C_CALLS_OUT (an INTERNAL: may end the call any way);
//    C_ENDS when every path through it ends there (nothing after it in its
//    trace runs: python trace_ends_execution, plus goto / continue / leave /
//    undefined).
//
// Validity: a summary's reference and its LISTs live until the context's
// next compaction (Context::compact drops the memo; recomputed on demand).
#pragma once

#include "core/base.hpp"
#include "core/smallvec.hpp"  // Tri
#include "core/value.hpp"

namespace pan::simplify {

// ---- the state classes (EffectSummary::reads / writes) ----------------------
inline constexpr u32 S_MEM = 1u << 0;        // memory's bytes (places: RANGEs)
inline constexpr u32 S_MSIZE = 1u << 1;      // memory's size: any line touching memory grows it
inline constexpr u32 S_STORAGE = 1u << 2;    // storage (places: STORAGE(size, off, slot) regions)
inline constexpr u32 S_TRANSIENT = 1u << 3;  // transient storage (places: keys)
inline constexpr u32 S_ACCOUNT = 1u << 4;    // balances, accounts' code
inline constexpr u32 S_CALLRES = 1u << 5;    // numbered call results (places: call ids, small ints)
inline constexpr u32 S_GAS = 1u << 6;        // gas left (read only: numbered reads)
inline constexpr u32 S_VARS = 1u << 7;       // variables (places: Names)
inline constexpr u32 S_LOG = 1u << 8;        // logs (written only)
inline constexpr u32 S_CALLDATA = 1u << 9;   // calldata, params (read only)
inline constexpr u32 S_CTX = 1u << 10;       // the call's context, block values (read only)
inline constexpr u32 S_ALL = (1u << 11) - 1;
// the classes whose places are kept
inline constexpr u32 S_PLACED = S_MEM | S_STORAGE | S_TRANSIENT | S_CALLRES | S_VARS;

// ---- how paths end (EffectSummary::control) -----------------------------------
inline constexpr u32 C_HALTS = 1u << 0;      // some path halts: STOP RETURN SELFDESTRUCT
inline constexpr u32 C_FAILS = 1u << 1;      // some path fails: REVERT INVALID REQUIRE ASSERT SAFEMATH
inline constexpr u32 C_UNDEFINED = 1u << 2;  // some path reaches UNDEFINED
inline constexpr u32 C_LEAVES = 1u << 3;     // some path returns from an internal function: LEAVE
inline constexpr u32 C_JUMPS = 1u << 4;      // CONTINUE GOTO BREAK LABEL: some path jumps, or is a loop's head
inline constexpr u32 C_CALLS_OUT = 1u << 5;  // an INTERNAL: may halt, fail, leave... in the callee
inline constexpr u32 C_ENDS = 1u << 6;       // every path ends in it: what follows it in its trace never runs
// some path may not go on to the next line
inline constexpr u32 C_MAY_END = C_HALTS | C_FAILS | C_UNDEFINED | C_LEAVES | C_JUMPS | C_CALLS_OUT;

// at most this many places per set; past them, the class's *_any bit
inline constexpr u32 kMaxPlaces = 32;

struct EffectSummary {
    u32 reads = 0;       // S_* read
    u32 writes = 0;      // S_* written
    u32 reads_any = 0;   // S_* read at places not listed (anywhere)
    u32 writes_any = 0;  // S_* written anywhere
    u32 control = 0;     // C_*
    // the places, LIST values (NIL: none; deterministic order: compare())
    Value mem_reads, mem_writes;    // RANGE(start, len)
    Value stor_reads, stor_writes;  // STORAGE(size, off, slot)
    Value tr_reads, tr_writes;      // transient keys
    Value var_reads, var_writes;    // Names (TMP LOOP MSIZE_VAR PRECOMPILE SAFEMATH_PARAM)
    Value call_reads, call_writes;  // call ids (small ints)

    bool may_end() const noexcept { return control & C_MAY_END; }
    bool always_ends() const noexcept { return control & C_ENDS; }
    // no write of any kind, no control effect: a pure expression or a no-op line
    bool pure() const noexcept { return writes == 0 && control == 0; }
};

// The summary of a line, a trace (a TRACE / LIST of lines), or an expression
// (its reads; control C_FAILS for a SAFEMATH). Memoized per node; ints,
// immediates: reads of a leaf / a name. NIL: the empty summary.
const EffectSummary& summary(Value v);

// The union of two summaries (places merged, capped: *_any past kMaxPlaces;
// the LISTs made on cx()); control the union of both, but C_ENDS: for `a
// then b` (seq = true) when either ends, for two branches `a or b` (seq =
// false) when both do.
EffectSummary combine(const EffectSummary& a, const EffectSummary& b, bool seq);

// May running `line` (a line, a trace, an IF...) change the value `expr`
// has, evaluated after it vs before it (python affects + changes_reads)?
// True when it may: memory it writes overlapping a read of expr's (lot 4's
// mem::overlaps, Tri::None counts), msize when expr reads it and line
// touches memory, storage regions that may alias (python may_alias, plus
// fields: disjoint bits of one slot don't), transient keys, the variables
// expr reads that line sets, the call ids. Control effects don't count
// (a halting line changes no value: ask summary(line).control).
bool affects(Value line, Value expr);
bool affects(const EffectSummary& line, Value expr);
// may the writes of w change what r reads (the same test, summaries)
bool changes(const EffectSummary& w, const EffectSummary& r);

// Can a and b (lines) run in either order with the same effects: neither
// writes what the other reads or writes, and neither may end a path
// (control): the folder's hoisting (lot 10), the loops' motion (lot 6).
bool independent(Value a, Value b);

// Every path through v (a line or a trace) ends in it: nothing after it in
// its trace runs (python trace_ends_execution, with goto / continue / leave
// / undefined).
inline bool ends(Value v) { return summary(v).control & C_ENDS; }

// The storage places a and b (STORAGE(size, off, slot) regions, or slots)
// share a bit: False when they surely don't (python may_alias: different
// constant slots, a small slot and a hash's; plus disjoint fields of one
// slot, and slots whose difference is a nonzero constant), else True/None.
Tri storage_may_alias(Value a, Value b);

}  // namespace pan::simplify
