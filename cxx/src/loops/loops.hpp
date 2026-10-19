// Loops (lot 6; python whiles.py and the loop part of simplify.py -
// parse_counters, extract_setmems, while_touches_mem, while_uses_mem,
// loop_to_setmem, loop_to_setmem_from_storage, propagate_storage_in_loops,
// replace_while_var; asm whiles.s, loops.s).
//
// 1. make_whiles: the VM's raw trace (vm.hpp: LABEL(Name(LOOP_ID, k),
//    setvars) at a loop's head, the lines after it its body, GOTO(Name(LOOP_ID,
//    k), setvars) back to it) as WHILE(cond, body, Name(LOOP_ID, k), setvars)
//    lines whose body goes on to the next iteration with CONTINUE(Name(LOOP_ID,
//    k), setvars) (ir.md 4.4: the setvars simultaneous; a body that ends
//    without a CONTINUE leaves the loop). The exit test (python to_while): the
//    first IF after the label one of whose branches loops back while the other
//    leaves; the lines before it (checks, reads) rotated - run before the loop
//    with the start values and again before each CONTINUE with the next ones -
//    only when that is equivalent (they set no loop variable, no value of the
//    setvars reads what they change, no CONTINUE in them, no call id
//    duplicated); the exit branch's merge setvars renamed away (python
//    exit_values) only when that is equivalent. Otherwise the loop is
//    `while True` (BOOL(1)) with its exits inside: the general form, always
//    equivalent to the LABEL / GOTO it replaces. Nested labels: each its
//    loop. A GOTO with no LABEL of its loop around it, a LABEL / GOTO malformed:
//    Unsupported (python failed the function).
// 2. summary: what a WHILE line does, per node, memoized - its variables,
//    every name it may set, its effects (lot 7's effects.hpp), the memory it
//    may write and read, its paths (breaks, continues) and its induction.
// 3. induction: the loop's counter (python parse_counters, as a proof rather
//    than a shape): start, constant step, bound, comparison; the trip count
//    and the values after the loop only when proven (the counter starts on
//    the right side of the bound, never wraps, reaches it exactly; no break;
//    nothing the loop changes read by the bound).
// 4. rewrites, each sound by construction (and checked by execution, M2):
//    loop_to_setmem (only with the trip count proven, a copy only when its
//    source and destination can't overlap the wrong way - else behind
//    `dubious`), propagate_storage_in_loops (an exact change of variables:
//    v' = v - sha3(...) at its start, every read and write of it moved),
//    rename_var (python replace_while_var, for lot 7's readability).
//
// Values: on cx(). Errors: the Budget's (MemoryLimit, Timeout, DepthLimit);
// make_whiles also Unsupported (above); the rest never (a rewrite that can't
// leaves its input).
#pragma once

#include <optional>
#include <vector>

#include "core/base.hpp"
#include "core/contract.hpp"
#include "core/smallvec.hpp"  // Tri
#include "core/value.hpp"
#include "simplify/effects.hpp"

namespace pan::loops {

// ---- 1. label / goto -> while / continue ------------------------------------------

struct WhilesOptions {
    // look for the exit test (false: every loop `while True`, the plain form)
    bool exit_test = true;
    // rotate the lines before the exit test (python to_while's path), when
    // equivalent (false: such a loop is `while True`)
    bool rotate = true;
};

// The trace with its LABEL / GOTO made WHILE / CONTINUE (python whiles.make;
// not python make_whiles' simplify_trace: lot 7's). `loops`: the function's
// LoopInfo (FunctionInfo::loops) - the entries of the loops that are gone (a
// LABEL nothing loops back to: its setvars made plain SETVARs) removed. A
// trace with no LABEL / GOTO: itself.
Value make_whiles(Value trace, std::vector<LoopInfo>& loops, const WhilesOptions& opts = {});
// fn.trace through make_whiles (its loops updated)
void whiles_function(FunctionInfo& fn, const WhilesOptions& opts = {});
// The whiles stage of a contract's functions (stagecheck, lot 12): out = in
// with each trace through make_whiles; a function that failed before
// (problem) copied as it is; one whose make_whiles fails (an Error) gets no
// trace and problem = 0. Timeout (Abort) goes through.
void whiles_stage(const std::vector<FunctionInfo>& in, std::vector<FunctionInfo>& out,
                  const WhilesOptions& opts = {});

// what make_whiles made, on this thread (the tools, the tests)
struct WhilesStats {
    u64 labels = 0;      // LABELs made loops
    u64 exit_test = 0;   // `while cond`: an exit test found...
    u64 rotated = 0;     //   with lines rotated (run before the loop and each CONTINUE)
    u64 renamed = 0;     //   with the exit's merge variables renamed (python exit_values)
    u64 exit_after = 0;  //   with the exit branch run after the loop (no break)
    u64 while_true = 0;  // `while True`
    u64 no_loop = 0;     // nothing loops back: plain SETVARs
};
WhilesStats& whiles_stats() noexcept;

// ---- 3. induction variables -----------------------------------------------------------

// the loop goes on while `counter cmp bound` holds (unsigned words)
enum class Cmp : u8 { Lt, Le, Gt, Ge, Ne };

struct Induction {
    Value var;          // the counter: a variable of the loop (its WHILE's setvars)
    Value start;        // its value as the loop starts (its setvar's)
    Value step;         // what every CONTINUE of the loop adds to it: an int in [-2^255, 2^255), not 0
    Cmp cmp = Cmp::Lt;  // the loop goes on while `var cmp bound`
    Value bound;        // loop invariant: nothing the loop changes is read in it
    // The proven part (NIL when not proven):
    //  - trips: how many times the body runs when the loop is left by its
    //    condition: the counter starts on the right side of the bound (or
    //    on it) for every value, and steps to the bound without wrapping
    //    (for every value of what start and bound are made of);
    //  - last: the counter's value once the condition fails (start + step *
    //    trips);
    //  - endvars: LIST of SETVAR(v, e), every loop variable v that every
    //    CONTINUE moves by the same loop-invariant amount, e its value once
    //    the loop is left - made of the values before the loop (start values,
    //    the bound) - valid after the WHILE line only: set when no path of
    //    the body leaves the loop to what follows it but the condition (no
    //    break) and trips is proven.
    Value trips;
    Value last;
    Value endvars;
};
// the loop's counter (python parse_counters), memoized per node; nullopt
// when the condition isn't a comparison of a loop variable stepped by a
// constant with something the loop doesn't change
std::optional<Induction> induction(Value while_line);

// ---- 2. loop summaries -------------------------------------------------------------------

struct LoopSummary {
    Value id;       // Name(LOOP_ID, k)
    Value vars;     // LIST of the loop's variables (its WHILE's setvars' names), in setvars order
    // LIST of every name the loop may set (its setvars, its CONTINUEs', the
    // body's SETVARs, PRECOMPILED and INTERNAL results, nested loops'), in
    // compare() order; NIL: none
    Value written;
    // the whole loop's effects (its condition, body and setvars: lot 7's
    // simplify::summary of the WHILE line)
    simplify::EffectSummary effects;
    // The memory any iteration may write (read): RANGEs, NIL for none. Each
    // range holds the bytes an iteration writes there for SOME value of the
    // variables the loop sets (`written`: read as free atoms) - to be written
    // with value NIL into a mem::MemState at the loop's head after what the
    // loop changes was forgotten there (forget_name of `written`, the
    // effects' other writes) - or, when the induction bounds them, one range
    // over all the iterations made of the values before the loop. *_any: a
    // write (read) the ranges don't bound (a SETMEM of no RANGE, an
    // INTERNAL, a LEAVE...).
    Value mem_writes, mem_reads;
    bool mem_writes_any = false, mem_reads_any = false;
    // the paths of the body
    bool breaks = false;           // one ends without a CONTINUE of this loop: the loop is left for what follows it
    bool continues_outer = false;  // a CONTINUE of an enclosing loop in it
    u32 continues = 0;             // the CONTINUEs of this loop in it
    std::optional<Induction> ind;  // induction(while_line)
};
// The summary of a WHILE line (InternalError for anything else), memoized
// per node; the reference holds until the context's next compaction.
const LoopSummary& summary(Value while_line);

// May some iteration of the loop write (read) a byte of `range` (a RANGE)?
// (python while_touches_mem, while_uses_mem): True / None / False, False
// only when no iteration can, for every value of what they're made of.
Tri may_write(Value while_line, Value range);
Tri may_read(Value while_line, Value range);

// ---- 4. rewrites ---------------------------------------------------------------------------

struct RewriteOptions {
    // python's rewrites not proven sound here (a copy loop whose source and
    // destination may overlap made one SETMEM): off unless execution
    // confirms them (lot 7's SimplifyOptions::dubious)
    bool dubious = false;
};

// python loop_to_setmem: a loop whose body is SETMEM(RANGE(p, 32), v) then
// a CONTINUE, p moving by +-32 every iteration, v 0 or a MEM / CALLDATALOAD
// moving with it, as one SETMEM of the range it covers then the endvars -
// only with the induction's trips and endvars proven (and, for a copy, its
// source and destination not overlapping the wrong way, unless dubious).
// A TRACE of the lines replacing it, or while_line itself.
Value loop_to_setmem(Value while_line, const RewriteOptions& opts = {});
// every WHILE of the trace (any depth) through loop_to_setmem (python
// rewrite_trace(trace, loop_to_setmem)); the trace itself when nothing
// changes
Value loops_to_setmems(Value trace, const RewriteOptions& opts = {});
// python propagate_storage_in_loops: a loop variable that starts at
// sha3(...) + k (the start of a storage array) made to start at k and read
// as itself + sha3(...) everywhere it's read and written (an exact change
// of variables, whatever its steps; what follows the loop reads it moved
// back). The trace itself when nothing changes.
Value propagate_storage_in_loops(Value trace);
// python replace_while_var: trace with the variable `from` renamed `to`
// everywhere (its reads, its SETVARs, the setvars of WHILE / CONTINUE /
// LABEL / GOTO); the trace itself when it has none
Value rename_var(Value trace, Value from, Value to);

}  // namespace pan::loops
