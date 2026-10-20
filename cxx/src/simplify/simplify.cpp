// The simplifier's driver (python simplify_trace / _simplify_trace, asm
// simplify.s): the trace's variables installed in the algebra, the rounds of
// passes in python's order until nothing changes (or the step timeout), then
// the final passes.
#include "simplify/simplify.hpp"

#include <algorithm>
#include <utility>
#include <vector>

#include "algebra/compare.hpp"
#include "algebra/construct.hpp"
#include "algebra/ranges.hpp"
#include "core/evmint.hpp"
#include "core/memo.hpp"
#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/errors.hpp"
#include "core/order.hpp"
#include "core/platform.hpp"
#include "loops/loops.hpp"
#include "simplify/effects.hpp"
#include "simplify/internal.hpp"

namespace pan::simplify {

namespace {

thread_local SimplifyStats tl_stats;

// times a pass into the thread's stats
template <class F>
Value timed(u32 bit_index, F&& f) {
    const i64 t0 = platform::monotonic_ns();
    Value r = f();
    tl_stats.ns[bit_index] += u64(platform::monotonic_ns() - t0);
    ++tl_stats.runs[bit_index];
    return r;
}

// python variable_values: every (name, value) a SETVAR sets anywhere
// (WHILE / CONTINUE / LABEL / GOTO setvars too), each pair once, in a
// deterministic order
std::vector<std::pair<Value, Value>> variable_values(Value trace) {
    std::vector<std::pair<Value, Value>> out;
    SmallVec<Value, 64> todo{trace};
    MemoSet<Value> seen;
    MemoSet<Key2> pairs;
    MemoSet<Value> volatile_names;  // (set otherwise than by a SETVAR)
    while (!todo.empty()) {
        poll();
        Value v = todo.back();
        todo.pop_back();
        if (!(v.is_list() || v.is_expr())) continue;
        if (v.is_expr() && !has(v.op(), LINE)) continue;
        if (!seen.add(v)) continue;
        // (variables set otherwise: by a precompile's call, an internal call)
        if (v.is(Op::PRECOMPILED, 4) && v[1].is_name()) volatile_names.add(v[1]);
        if (v.is(Op::INTERNAL, 3))
            if (Value results = v[2]; results.is_list())
                for (Value n : results.args()) volatile_names.add(n);
        if (v.is(Op::SETVAR, 2)) {
            if (pairs.add(Key2{v[0].raw(), v[1].raw()})) out.emplace_back(v[0], v[1]);
            continue;
        }
        for (Value x : v.children()) todo.push_back(x);
    }
    // (a variable also set by a precompile's or an internal call: values
    // not known, left out: any word)
    std::erase_if(out, [&](const auto& p) { return volatile_names.contains(p.first); });
    std::sort(out.begin(), out.end(), [](const auto& a, const auto& b) {
        int c = compare(a.first, b.first);
        return c != 0 ? c < 0 : compare(a.second, b.second) < 0;
    });
    return out;
}

// python small_words, made sound: the words the contract is given (what may
// make a memory position wrap: alg::unchecked), the same wherever they are
// (python immutable: made of the calldata, the call's context, variables
// set once to such), that a check bounds below 2^64 - an if one branch of
// which ends: `if len > 2^64 - 1: revert` - with
// no memory position of the trace reading them before it (where the check
// may not have passed yet: what the lines before it touch, the branch that
// ends included, the variables' values too). Every position they're in is
// then evaluated where they are below 2^64: the memory model takes them for
// words that small (ceil32(len) + k doesn't wrap). A variable set once:
// its value too (cleanup_vars puts it in its place). Not past a LABEL (a
// raw trace's loop).
class SmallWords {
public:
    explicit SmallWords(const std::vector<std::pair<Value, Value>>& values) : values_(values) {}
    std::vector<Value> run(Value trace) {
        (void)spine(trace);
        return std::move(small_);
    }

private:
    // the lines every execution that goes on runs, in order; false where
    // nothing after runs
    bool spine(Value trace) {
        if (!trace.is_list()) return true;
        check_stack();
        for (Value l : trace.args()) {
            poll();
            if (l.is(Op::IF, 3) || l.is(Op::MERGED_IF, 3)) {
                note(l[0]);
                // the branch that's gone: one that ends while the other goes
                // on - or, both ending (the rest of the trace in one of them),
                // the one that reverts: the check fails there; both
                // reverting (a function that always reverts: its result
                // reverted) or neither, the smaller one. Either is sound: the
                // gone one is noted before the bound, what's bounded holds
                // in the one followed
                const bool t_ends = ends(l[1]), e_ends = ends(l[2]);
                int gone = -1;  // 1: the true branch, 2: the false one
                if (t_ends != e_ends) {
                    gone = t_ends ? 1 : 2;
                } else if (t_ends) {
                    const bool t_rev = reverts(l[1]), e_rev = reverts(l[2]);
                    if (t_rev != e_rev) gone = t_rev ? 1 : 2;
                    else gone = exp_size(l[1], 256) <= exp_size(l[2], 256) ? 1 : 2;
                }
                if (gone < 0) {
                    note(l);
                    continue;
                }
                note(l[u32(gone)]);
                bound(gone == 1 ? alg::iszero(l[0]) : l[0]);
                if (!spine(l[gone == 1 ? 2u : 1u])) return false;
                if (t_ends && e_ends) return false;
                continue;
            }
            if (l.is(Op::LABEL)) return false;
            note(l);
            if (ends(l)) return false;
        }
        return true;
    }
    // every path of t reverts (or runs an invalid opcode)
    static bool reverts(Value t) {
        if (!t.is_list() || t.size() == 0) return false;
        Value last = t[t.size() - 1];
        if (last.is(Op::REVERT) || last.is(Op::INVALID)) return true;
        if (last.is(Op::IF, 3) || last.is(Op::MERGED_IF, 3)) return reverts(last[1]) && reverts(last[2]);
        return false;
    }
    // what holds from here on: the words it bounds below 2^64
    void bound(Value holds) {
        static const EvmInt top = EvmInt::pow2(64);
        for (const alg::CondBound& b : alg::cond_bounds(holds)) {
            if (!(b.range().hi < top)) continue;
            add(b.x);
            if (b.x.is_name()) {
                // (a variable set once: its value)
                Value v;
                u32 n = 0;
                for (const auto& [name, value] : values_)
                    if (name == b.x) {
                        v = value;
                        ++n;
                    }
                if (n == 1) add(v);
            }
        }
    }
    void add(Value x) {
        if (x.is_int() || x.is(Op::ADD) || x.is(Op::MUL)) return;  // (a sum may be small only modulo 2^256)
        if (!alg::unchecked(x) || !immutable(x, 0) || seen_.contains(x)) return;
        for (Value y : small_)
            if (y == x) return;
        small_.push_back(x);
    }
    // x is the same word wherever it is: it reads the calldata, the call's
    // context and variables set once to such words only
    bool immutable(Value x, u32 depth) {
        if (depth > 16) return false;
        if (x.is_name()) {
            if (x.is_name(NameKind::PARAM)) return true;
            Value v;
            u32 n = 0;
            for (const auto& [name, value] : values_)
                if (name == x) {
                    v = value;
                    ++n;
                }
            return n == 1 && immutable(v, depth + 1);
        }
        const EffectSummary& s = summary(x);
        if (s.writes || s.control || (s.reads & ~(S_CALLDATA | S_CTX | S_VARS)) || (s.reads_any & S_VARS)) return false;
        if (!s.var_reads.nil())
            for (Value n : s.var_reads.args())
                if (!immutable(n, depth + 1)) return false;
        return true;
    }
    // the subterms of v's memory positions (its RANGEs, any depth; the
    // values of the variables in them) as seen
    void note(Value v) {
        if (!(v.is_expr() || v.is_list())) return;
        if (!noted_.add(v)) return;
        check_stack();
        if (v.is(Op::RANGE, 2)) {
            subterms(v);
            return;
        }
        for (Value a : v.args()) note(a);
    }
    void subterms(Value v) {
        if (!seen_.add(v)) return;
        check_stack();
        if (v.is_name()) {
            for (const auto& [name, value] : values_)
                if (name == v) subterms(value);
            return;
        }
        if (v.is_expr() || v.is_list())
            for (Value a : v.args()) subterms(a);
    }

    const std::vector<std::pair<Value, Value>>& values_;
    MemoSet<Value> noted_, seen_;
    std::vector<Value> small_;
};

class Driver {
public:
    Driver(const SimplifyOptions& o, ExplainHook* e) : opts_(o), explain_(e) {
        i64 t = o.timeout_ns;
        if (t == 0) t = scaled_timeout(limits::WHILES_TIMEOUT_NS);
        deadline_ = t < 0 || t >= limits::NO_TIMEOUT_NS ? 0 : platform::monotonic_ns() + t;
    }

    Value run(Value trace) {
        const u32 p = opts_.passes;
        auto on = [&](u32 bit) { return (p & bit) != 0; };
        const loops::RewriteOptions lo{opts_.dubious};
        for (u32 round = 0; round < opts_.max_rounds && !timed_out(); ++round) {
            const Value old = trace;
            if (on(P_EXPS)) trace = step(pass(0, 0, trace, simplify_exps), ExplainStage::SimplifyExpressions);
            if (on(P_VARS)) trace = step(pass(1, 1, trace, cleanup_vars), ExplainStage::CleanupVariables);
            if (on(P_MEMS)) trace = step(pass(2, 2, trace, cleanup_mems), ExplainStage::CleanupMems);
            if (on(P_PRECOMPILED)) trace = step(pass(3, 3, trace, precompiled_results), ExplainStage::PrecompiledResults);
            if (on(P_MIN_IFS)) trace = step(pass(4, 4, trace, min_ifs), ExplainStage::Minimums);
            if (on(P_SPLIT)) trace = step(pass(5, 5, trace, split_lines), ExplainStage::SplitSetmemsStorages);
            if (on(P_VARS)) trace = step(pass(1, 1, trace, cleanup_vars), ExplainStage::CleanupVars);
            if (on(P_EXPS)) trace = step(pass(0, 0, trace, simplify_exps), ExplainStage::SimplifyExpressions);
            trace = step(cleanup_mul_1(trace), ExplainStage::SimplifyExpressions);
            if (on(P_LENGTH))
                trace = step(pass(6, 6, trace, replace_bytes_or_string_length), ExplainStage::ReplaceStorageWithLength);
            if (on(P_CONDS)) trace = step(pass(7, 7, trace, cleanup_conds), ExplainStage::CleanupUnusedIfs);
            if (on(P_LOOPS)) {
                trace = step(pass(8, 9, trace, [&](Value t) { return loops::loops_to_setmems(t, lo); }),
                             ExplainStage::ConvertLoopsToSetmems);
                trace = step(pass(9, 9, trace, loops::propagate_storage_in_loops), ExplainStage::MoveLoopIndexes);
            }
            if (trace == old) break;
            trace = maybe_compact(trace);
        }
        if (!opts_.final_passes || !on(P_FINAL)) return trace;
        // the final passes (python: they would break the rounds); on the
        // rounds' last trace they are what that round made (pass())
        const i64 f0 = platform::monotonic_ns();
        if (!timed_out()) {
            if (on(P_MEMS))
                for (int k = 0; k < 3; ++k) trace = pass(2, 2, trace, cleanup_mems);
            if (on(P_EXPS)) trace = pass(0, 0, trace, simplify_exps);
            if (on(P_VARS)) trace = pass(1, 1, trace, cleanup_vars);
        }
        struct Final {
            i64 f0;
            ~Final() { tl_stats.ns[8] += u64(platform::monotonic_ns() - f0); }
        } final_time{f0};
        trace = max_to_add(trace);
        trace = postprocess_exps(trace);
        trace = step(trace, ExplainStage::Heuristics);
        if (on(P_PRECOMPILED)) trace = precompiled_results(trace);
        if (on(P_CONDS)) trace = step(cleanup_conds(trace), ExplainStage::FinalCleanup);
        trace = fix_storages(trace);
        if (on(P_CONDS)) trace = step(cleanup_conds(trace), ExplainStage::CleaningStorages);
        trace = readability(trace);
        trace = step(cleanup_mul_1(trace), ExplainStage::NicerNames);
        if (on(P_CONDS)) trace = cleanup_conds(trace);
        return trace;
    }

private:
    Value step(Value trace, ExplainStage s) {
        if (explain_) explain_->stage(s, trace);
        return trace;
    }
    // A pass run on the trace (timed into stats index `stat`), or what it
    // made the last time when its input is that trace again: during a run a
    // pass is a function of its input (the algebra's variables and the
    // run's flags are fixed, its caches only remember), so a round that
    // changes nothing and the final passes after it don't redo the work.
    // (slot: the pass; the Values forgotten when the context compacts.)
    template <class F>
    Value pass(u32 slot, u32 stat, Value trace, F&& f) {
        Last& l = last_[slot];
        if (!l.in.nil() && l.in == trace) return l.out;
        Value r = timed(stat, [&] { return f(trace); });
        l.in = trace;
        l.out = r;
        return r;
    }
    bool timed_out() const { return deadline_ != 0 && platform::monotonic_ns() > deadline_; }
    // (every Value the run holds is among the roots or in a state that
    // imports it: the trace, the caller's roots, the run's flags' entry lines)
    Value maybe_compact(Value trace) {
        if (!opts_.compact) return trace;
        Context& c = cx();
        const usize threshold =
            opts_.compact_threshold ? opts_.compact_threshold : compact_threshold(c.budget.limits().memory);
        if (c.usage() <= threshold) return trace;
        std::vector<Value> roots;
        roots.reserve(opts_.compact_roots.size() + 1);
        roots.push_back(trace);
        for (Value v : opts_.compact_roots) roots.push_back(v);
        c.compact(roots);
        for (usize i = 0; i < opts_.compact_roots.size(); ++i) opts_.compact_roots[i] = roots[i + 1];
        for (Last& l : last_) l = Last{};  // (freed)
        return roots[0];
    }

    struct Last {
        Value in, out;
    };
    SimplifyOptions opts_;
    ExplainHook* explain_;
    i64 deadline_ = 0;
    Last last_[10];
};

}  // namespace

Value simplify_trace(Value trace, const SimplifyOptions& opts, ExplainHook* explain) {
    if (!trace.is_list()) return trace;
    const auto values = variable_values(trace);
    alg::set_variables(values, {});
    // (the small words: with the variables installed - unchecked reads them)
    if (const std::vector<Value> small = SmallWords(values).run(trace); !small.empty())
        alg::set_variables(values, small);
    struct Clear {
        ~Clear() { alg::clear_variables(); }
    } clear;
    RunFlags& f = run_flags();
    f.msize = trace.has_flags(F_MSIZE) || (opts.entry_lines.is_list() && opts.entry_lines.has_flags(F_MSIZE));
    f.dubious = opts.dubious;
    f.entry_lines = opts.entry_lines;
    f.fresh = opts.fresh_memory;
    struct Reset {
        ~Reset() { run_flags() = RunFlags{}; }
    } reset;
    SimplifyOptions o = opts;
    o.entry_lines = Value();  // (run_flags() holds them, through compactions)
    Driver d(o, explain);
    return d.run(trace);
}

SimplifyStats& simplify_stats() noexcept { return tl_stats; }

void simplify_function(FunctionInfo& fn, const SimplifyOptions& opts, ExplainHook* explain) {
    SimplifyOptions o = opts;
    o.entry_lines = fn.entry.entry_lines;
    o.fresh_memory = fn.kind != FunctionInfo::Kind::Internal;
    fn.trace = simplify_trace(fn.trace, o, explain);
}

void simplify_stage(const std::vector<FunctionInfo>& in, std::vector<FunctionInfo>& out, const SimplifyOptions& opts) {
    out = in;
    for (FunctionInfo& f : out) {
        if (f.problem || f.trace.nil()) continue;
        try {
            simplify_function(f, opts);
        } catch (const Error&) {
            f.trace = Value();
            f.problem = 0;
        }
    }
}

}  // namespace pan::simplify
