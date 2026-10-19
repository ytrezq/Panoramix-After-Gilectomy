// The simplifier (lot 7; python simplify.py minus the loops, rewriter.py,
// postprocess.py; asm simplify.s, simplify_exp.s, simplify_vars.s,
// cleanup.s, conds.s, rewriter.s, postprocess.s, trace_util.s): a
// function's trace (the VM's, after lot 6's whiles) made readable without
// changing what it does - every pass keeps ir.md section 4's semantics, and
// the result runs in lot 11's trace machine with the same effects as the
// bytecode (M2).
//
//  - simplify_exp: the local rules of python simplify_exp (masks, shifts,
//    truth values, comparisons decided by ranges, byte elements, data
//    concatenation...) as a bottom-up rewrite of hash-consed nodes, a switch
//    on the op, memoized per node until the algebra's context changes
//    (alg::set_variables clears the caches).
//  - the dataflow cleanups: cleanup_vars (a variable's value inlined where it
//    is read, when single-use or cheap and nothing between changes what it
//    reads: effects.hpp; MAX_EXP_SIZE), cleanup_mems (memory reads resolved
//    against the writes that reach them, lot 4's MemState; writes no read
//    uses removed) - one forward walk each, not python's quadratic passes.
//  - the other passes of python's _simplify_trace, in its order.
//
// Raw traces (LABEL / GOTO, before lot 6) are accepted: a LABEL is a loop's
// head - what the lines after it (its body, run again) change is forgotten
// there - and its structure is left as it is.
//
// Values: on cx(); the trace's variables are installed in the algebra
// (alg::set_variables) by simplify_trace for its run and cleared after.
#pragma once

#include <span>
#include <vector>

#include "core/base.hpp"
#include "core/budget.hpp"
#include "core/contract.hpp"
#include "core/value.hpp"

namespace pan::simplify {

// --- --explain: the stages python's simplify_trace explains (lot 10 makes
// them text; it shows a stage when the trace changed) -------------------------
enum class ExplainStage : u8 {
    SimplifyExpressions,       // "simplify expressions"
    CleanupVariables,          // "cleanup variables"
    CleanupMems,               // "cleanup mems"
    PrecompiledResults,        // "results of precompiled contracts"
    Minimums,                  // "minimums"
    SplitSetmemsStorages,      // "split setmems & storages"
    CleanupVars,               // "cleanup vars"
    ReplaceStorageWithLength,  // "replace storage with length"
    CleanupUnusedIfs,          // "cleanup unused ifs"
    ConvertLoopsToSetmems,     // "convert loops to setmems" (lot 6's loop_to_setmem)
    MoveLoopIndexes,           // "move loop indexes outside of loops" (lot 6's)
    Heuristics,                // "using heuristics to clean up some things"
    FinalCleanup,              // "final setmem/condition cleanup"
    CleaningStorages,          // "cleaning up storages slightly"
    NicerNames,                // "adding nicer variable names"
};

// what --explain observes (lot 10's StageObserver implements or adapts it)
class ExplainHook {
public:
    virtual void stage(ExplainStage stage, Value trace) = 0;

protected:
    ~ExplainHook() = default;
};

struct SimplifyOptions {
    u32 max_rounds = limits::SIMPLIFY_ROUNDS;  // python's 40
    // the step timeout (python's timeout: rounds stop, the last cleanup_mems
    // skipped - the trace is less simplified, not wrong); 0:
    // scaled_timeout(limits::WHILES_TIMEOUT_NS) (60 s); < 0: none. The job's
    // own deadline (the watchdog: Timeout) is the Budget's.
    i64 timeout_ns = 0;
    // the passes after the rounds (max_to_add, ABI arrays, readability...)
    bool final_passes = true;
    // python's rewrites known to be unsound (rewriter.postprocess_trace's
    // `len % 32` branches assumed equal, replace_var into setmems past
    // clobbers): off unless execution confirms them
    bool dubious = false;
    // compact the context between rounds past its threshold (python's
    // PANORAMIX_COMPACT_MIB): only when the caller owns the context - every
    // Value it still holds besides the trace is in compact_roots (updated in
    // place); off: never compacted
    bool compact = false;
    std::span<Value> compact_roots{};
    // what runs before the trace (EntryCondition::entry_lines: the
    // dispatcher's SETMEMs and checks), and whether the memory is zeroes
    // before them (a call's start: not an internal function's) - what the
    // trace's memory reads may be filled from
    Value entry_lines{};
    bool fresh_memory = false;
    // the passes run (debugging: a pass left out to find which one breaks a
    // trace); all by default
    u32 passes = ~0u;
};

// SimplifyOptions::passes
inline constexpr u32 P_EXPS = 1u << 0;         // simplify_exps
inline constexpr u32 P_VARS = 1u << 1;         // cleanup_vars
inline constexpr u32 P_MEMS = 1u << 2;         // cleanup_mems
inline constexpr u32 P_PRECOMPILED = 1u << 3;  // precompiled_results
inline constexpr u32 P_MIN_IFS = 1u << 4;      // min_ifs
inline constexpr u32 P_SPLIT = 1u << 5;        // split_lines
inline constexpr u32 P_LENGTH = 1u << 6;       // replace_bytes_or_string_length
inline constexpr u32 P_CONDS = 1u << 7;        // cleanup_conds
inline constexpr u32 P_FINAL = 1u << 8;        // max_to_add, fix_storages, readability...

// ---- expressions ------------------------------------------------------------------

// e with the local rules applied to a fixpoint, any depth (python
// simplify_exp through replace_f): its value unchanged for every value of
// its leaves (and of the trace's variables: set_variables). Memoized per
// node until the context's caches are cleared.
Value simplify_exp(Value e);

// ---- the driver -------------------------------------------------------------------

// The trace simplified (python simplify_trace): variable_values and
// small_words installed in the algebra (alg::set_variables) for the run,
// then at most opts.max_rounds rounds of the passes until nothing changes
// (or the step timeout), then the final passes; the context compacted
// between rounds past its threshold (the trace, kept). Errors: the
// Budget's (MemoryLimit, Timeout, DepthLimit); Unsupported never (a pass
// that can't leaves its input).
Value simplify_trace(Value trace, const SimplifyOptions& opts = {}, ExplainHook* explain = nullptr);
// fn.trace simplified (simplify_trace, its entry lines and fresh memory
// from fn), on cx()
void simplify_function(FunctionInfo& fn, const SimplifyOptions& opts = {}, ExplainHook* explain = nullptr);
// The simplified stage of a contract's functions (stagecheck, lot 12): out
// = in with each trace simplified; a function that failed before (problem)
// is copied as it is; one whose simplification fails (an Error) gets no
// trace and problem = 0. Timeout (Abort) goes through.
void simplify_stage(const std::vector<FunctionInfo>& in, std::vector<FunctionInfo>& out,
                    const SimplifyOptions& opts = {});

// ---- the passes (each: a trace in, the trace out - itself when unchanged) ----------

// every expression of the trace through simplify_exp (python replace_f)
Value simplify_exps(Value trace);
// variables inlined where they are read and set lines nobody reads dropped
// (python cleanup_vars, with a def-use index)
Value cleanup_vars(Value trace);
// memory reads replaced by what the writes before them wrote, writes nobody
// reads dropped (python cleanup_mems / replace_mem, with lot 4's MemState);
// not in a trace that reads msize (what a run touches would change it)
Value cleanup_mems(Value trace);
// the first word a precompile returned read as its result variable
Value precompiled_results(Value trace);
// `if a > b: v = b else: v = a` -> `v = min(a, b)`
Value min_ifs(Value trace);
// lot 4's split_setmem / split_store on every line
Value split_lines(Value trace);
// solidity's `(s & (256 * iszero(s & 1) - 1)) / 2` of a slot -> LENGTH(slot)
Value replace_bytes_or_string_length(Value trace);
// ifs / whiles whose condition is decided removed, conditions known in a
// branch applied (python cleanup_conds, apply_constraint)
Value cleanup_conds(Value trace);
// python postprocess.cleanup_mul_1: mul 1 and mask leftovers
Value cleanup_mul_1(Value trace);
// `max(2 + x, 3 + y)` -> `2 + max(x, 1 + y)` (python algebra.max_to_add)
Value max_to_add(Value trace);
// ABI arrays in DATA -> ARR(len, ...) (python rewriter.postprocess_exp)
Value postprocess_exps(Value trace);
// a field of storage moved left as the field shifted (python fix_storages)
Value fix_storages(Value trace);
// _msize for msize maxes, loop variables renumbered, maxes in compare()
// order (python readability, canonise_max)
Value readability(Value trace);

// `if c: v = a else: v = b` as `v = c and a` / `c or b` (LAND / LOR) where
// the branches only set one variable to what c decides (python
// postprocess.short_circuits; run by lot 10's make_ast before the folder)
Value short_circuits(Value trace);

}  // namespace pan::simplify
