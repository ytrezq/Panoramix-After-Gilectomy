// The ast's own passes (lot 10; python's VM snapshots, its folder's merge of
// identical branches): on cx(), each the same effects as its input (ir.md 4:
// the trace machine runs the ast, M3).
//
//  - The entry's lines a function's text needs (python's trace starts with
//    the dispatcher's): its checks, and its SETMEMs the body may read.
//  - Call results kept: the text's ext_call.success, return_data.size,
//    ext_call.return_data[...], create.new_address are the last call's,
//    the IR's are numbered. A result of call k read where another call may
//    have been made since (on some path) gets a variable, set right after
//    each call k line, read there instead (python's VM snapshots them: `_1 =
//    ext_call.return_data[0]`) - the variable of a result that only depends
//    on call k (its offsets and lengths of numbers or of call k's size).
//  - An if whose branches are the same lines but for the ids of the calls
//    they make (python has no ids: they're equal there) is its lines.
//  - The paths the VM didn't finish end in one line (python's has no pc:
//    its folder merges them).
#include <algorithm>
#include <optional>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include "algebra/eval.hpp"
#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/contract.hpp"
#include "output/fold.hpp"

namespace pan::output::detail {

namespace {

// ---- what the IR's numbering says -------------------------------------------------------

constexpr u32 kInternalCalls = 0xffffffffu;  // an internal function's calls (unknown)

// the id of a call line (CALL...CREATE2, PRECOMPILED)
std::optional<u32> call_line_id(Value l) noexcept
{
    if (!l.is_expr() || l.size() < 1 || !l[0].is_small() || l[0].small_val() < 0)
        return std::nullopt;
    switch (l.op()) {
        case Op::CALL:
        case Op::CALLCODE:
        case Op::DELEGATECALL:
        case Op::STATICCALL:
        case Op::CREATE:
        case Op::CREATE2:
        case Op::PRECOMPILED:
            return u32(std::min<i64>(l[0].small_val(), i64(kInternalCalls - 1)));
        default:
            return std::nullopt;
    }
}

// the call a result read is of: CALL_SUCCESS, CREATE_ADDRESS, RETURNDATASIZE
// k (leaves), RETURNDATA_BYTES(k, off, len)
std::optional<u32> result_id(Value v) noexcept
{
    if (v.is_leaf()) {
        switch (v.op()) {
            case Op::CALL_SUCCESS:
            case Op::CREATE_ADDRESS:
            case Op::RETURNDATASIZE:
                return v.leaf_n();
            default:
                return std::nullopt;
        }
    }
    if (v.is(Op::RETURNDATA_BYTES, 3) && v[0].is_small() && v[0].small_val() >= 0)
        return u32(std::min<i64>(v[0].small_val(), i64(kInternalCalls - 1)));
    return std::nullopt;
}

// v is fixed once call k is made: numbers, call k's leaves, pure ops of them
bool fixed_by_call(Value v, u32 k)
{
    check_stack();
    if (v.is_int())
        return true;
    if (v.is_leaf())
        return result_id(v) == k;
    if (v.is_expr() && alg::is_pure(v.op())) {
        for (const Value a : v.args())
            if (!fixed_by_call(a, k))
                return false;
        return true;
    }
    return false;
}

// a result read a variable can hold from right after its call on
bool snapshot_safe(Value t, u32 k)
{
    return t.is_leaf() || (fixed_by_call(t[1], k) && fixed_by_call(t[2], k));
}

// ---- the calls the text may take for others ----------------------------------------------

// the calls that may be the last one made (sorted)
using Last = std::vector<u32>;

void join(Last& a, const Last& b)
{
    Last r;
    std::set_union(a.begin(), a.end(), b.begin(), b.end(), std::back_inserter(r));
    a = std::move(r);
}

// the ids of the call lines of a trace, any depth (a loop's body: its calls
// may come before any line of it, in its next round)
void calls_in(Value v, Last& out, std::unordered_set<u64>& seen)
{
    check_stack();
    if (!(v.is_expr() || v.is_list()) || !seen.insert(v.raw()).second)
        return;
    if (v.is_expr()) {
        if (const auto id = call_line_id(v))
            out.push_back(*id);
        if (v.is(Op::INTERNAL))
            out.push_back(kInternalCalls);
    }
    for (const Value a : v.args())
        if (a.is_list() || (a.is_expr() && (a.op() == Op::IF || a.op() == Op::WHILE || call_line_id(a) ||
                                            a.is(Op::INTERNAL))))
            calls_in(a, out, seen);
}

class Snapshots {
public:
    // pass 1: the reads that need a variable; pass 2: the trace with them
    Value run(Value trace)
    {
        Last none;
        rewrite_ = false;
        walk(trace, none);
        if (needs_.empty() || steps_ > kMaxSteps)
            return trace;
        // the variables' names: the first _N the trace doesn't have (python's
        // VM numbers its snapshots with the others: `_1` the first)
        {
            std::unordered_set<u64> seen;
            tmps(trace, seen);
        }
        u32 next = 1;
        for (const Value t : needs_) {
            while (used_.contains(next))
                ++next;
            used_.insert(next);
            var_of_.emplace(t.raw(), Value::name(NameKind::TMP, next));
        }
        rewrite_ = true;
        memo_.clear();
        steps_ = 0;
        Last start;
        const Value r = walk(trace, start);
        return steps_ > kMaxSteps ? trace : r;
    }

private:
    static constexpr u64 kMaxSteps = u64(1) << 21;  // (a walk past it: the trace as it is)

    void tmps(Value v, std::unordered_set<u64>& seen)
    {
        check_stack();
        if (v.is_name(NameKind::TMP)) {
            used_.insert(v.name_id());
            return;
        }
        if (!(v.is_expr() || v.is_list()) || !(v.flags() & F_VAR) || !seen.insert(v.raw()).second)
            return;
        for (const Value a : v.args())
            tmps(a, seen);
    }

    static bool surely(const Last& last, u32 k) noexcept { return last.size() == 1 && last[0] == k; }

    // a line's (or an expression's) reads: pass 1 notes those the text may
    // take for another call's, pass 2 reads their variables there
    Value use(Value e, const Last& last, std::unordered_map<u64, Value>& memo)
    {
        check_stack();
        if (const auto k = result_id(e); k && *k != 0 && *k != kInternalCalls && !surely(last, *k) &&
                                          snapshot_safe(e, *k)) {
            if (!rewrite_) {
                if (noted_.insert(e.raw()).second)
                    needs_.push_back(e);
                return e;
            }
            if (const auto it = var_of_.find(e.raw()); it != var_of_.end())
                return it->second;
            return e;
        }
        if (!(e.is_expr() || e.is_list()) || !(e.flags() & F_STATE))
            return e;
        if (const auto it = memo.find(e.raw()); it != memo.end())
            return it->second;
        std::vector<Value> args;
        args.reserve(e.size());
        bool changed = false;
        for (const Value a : e.args()) {
            const Value b = use(a, last, memo);
            changed = changed || b != a;
            args.push_back(b);
        }
        const Value r = changed && rewrite_ ? mk_like(e, args) : e;
        memo.emplace(e.raw(), r);
        return r;
    }

    Value line_use(Value l, const Last& last)
    {
        std::unordered_map<u64, Value> memo;
        const Value r = use(l, last, memo);
        if (r != l)
            cx().pcs.inherit(r, l);
        return r;
    }

    // the lines of a trace from the calls that may be the last one; last:
    // after them
    Value walk(Value lines, Last& last)
    {
        check_stack();
        if (!lines.is_list())
            return lines;
        auto& seen = memo_[lines.raw()];
        for (const Memo& m : seen)
            if (m.before == last) {
                last = m.after;
                return m.result;
            }
        if (++steps_ > kMaxSteps)
            return lines;
        poll();
        const Last before = last;
        std::vector<Value> out;
        out.reserve(lines.size());
        for (const Value l : lines.args()) {
            if (l.is(Op::IF, 3) || l.is(Op::MERGED_IF, 3)) {
                const Value c = line_use(l[0], last);
                Last a = last, b = last;
                const Value t = walk(l[1], a);
                const Value f = walk(l[2], b);
                join(a, b);
                last = std::move(a);
                out.push_back(rebuild(l, {c, t, f}));
                continue;
            }
            if (l.is(Op::WHILE, 4)) {
                // (its first values: before it; in it, any round's last call)
                const Value setvars = line_use(l[3], last);
                Last in = last;
                {
                    Last body_calls;
                    std::unordered_set<u64> seen;
                    calls_in(l[1], body_calls, seen);
                    std::sort(body_calls.begin(), body_calls.end());
                    body_calls.erase(std::unique(body_calls.begin(), body_calls.end()), body_calls.end());
                    join(in, body_calls);
                }
                const Value c = line_use(l[0], in);
                Last body_last = in;
                const Value body = walk(l[1], body_last);
                last = std::move(in);
                out.push_back(rebuild(l, {c, body, l[2], setvars}));
                continue;
            }
            out.push_back(line_use(l, last));
            if (const auto id = call_line_id(l)) {
                last = {*id};
                if (rewrite_)
                    for (const Value t : needs_)
                        if (result_id(t) == *id)
                            out.push_back(mk(Op::SETVAR, var_of_.at(t.raw()), t));
            } else if (l.is(Op::INTERNAL)) {
                last = {kInternalCalls};
            }
        }
        const Value r = rewrite_ ? mk_like(lines, out) : lines;
        memo_[lines.raw()].push_back(Memo{before, last, r});
        return r;
    }

    Value rebuild(Value l, std::initializer_list<Value> args)
    {
        if (!rewrite_)
            return l;
        const Value r = mk_like(l, std::span<const Value>(args.begin(), args.size()));
        cx().pcs.inherit(r, l);
        return r;
    }

    struct Memo {
        Last before, after;
        Value result;
    };
    bool rewrite_ = false;
    u64 steps_ = 0;
    std::unordered_set<u32> used_;  // the trace's _N
    std::vector<Value> needs_;              // the reads given a variable, in the order found
    std::unordered_set<u64> noted_;
    std::unordered_map<u64, Value> var_of_;  // a read -> its variable
    std::unordered_map<u64, std::vector<Memo>> memo_;  // lines -> (last before, after, what they became)
};

// ---- branches the same but for their calls' ids -------------------------------------------

// a ~ b but for the ids of the calls they make (a's k is b's m, one to one;
// an id they don't make: the same on both sides)
class SameButIds {
public:
    bool operator()(Value a, Value b)
    {
        pairs_.clear();
        made_.clear();
        gas_.clear();
        if (!same(a, b))
            return false;
        // (a pair of different ids: both made inside, never one made before)
        for (const auto& [x, y] : pairs_)
            if (x != y && std::find(made_.begin(), made_.end(), std::pair{x, y}) == made_.end())
                return false;
        return true;
    }

private:
    static bool map_in(std::vector<std::pair<u32, u32>>& pairs, u32 x, u32 y)
    {
        for (const auto& [p, q] : pairs) {
            if (p == x || q == y)
                return p == x && q == y;
        }
        pairs.emplace_back(x, y);
        return true;
    }
    bool map(u32 x, u32 y) { return map_in(pairs_, x, y); }
    bool map_gas(u32 x, u32 y) { return map_in(gas_, x, y); }

    // the ids v reads or makes, each the same on both sides
    bool fixed(Value v)
    {
        check_stack();
        if (const auto k = result_id(v); k && v.is_leaf())
            return map(*k, *k);
        if (v.is_leaf() && v.op() == Op::GAS)
            return map_gas(v.leaf_n(), v.leaf_n());
        if (!(v.is_expr() || v.is_list()))
            return true;
        if (const auto k = call_line_id(v))
            if (!map(*k, *k))
                return false;
        if (const auto k = result_id(v))
            if (!map(*k, *k))
                return false;
        for (const Value x : v.args())
            if (!fixed(x))
                return false;
        return true;
    }

    bool same(Value a, Value b)
    {
        check_stack();
        if (a == b)
            return !(a.is_expr() || a.is_list() || a.is_leaf()) || fixed(a);
        if (a.is_leaf() && b.is_leaf()) {
            if (a.op() != b.op())
                return false;
            if (const auto k = result_id(a))
                return map(*k, *result_id(b));
            if (a.op() == Op::GAS)  // (the VM numbers its reads: one to one)
                return map_gas(a.leaf_n(), b.leaf_n());
            return a.leaf_n() == b.leaf_n();
        }
        if (a.is_expr() != b.is_expr() || a.is_list() != b.is_list() || !(a.is_expr() || a.is_list()))
            return false;
        if (a.is_expr() && a.op() != b.op())
            return false;
        if (a.is_list() && a.is_trace() != b.is_trace())
            return false;
        if (a.size() != b.size())
            return false;
        u32 from = 0;
        if (a.is_expr()) {
            const auto ka = call_line_id(a);
            const auto ra = result_id(a);
            if (ka || ra) {
                const auto kb = ka ? call_line_id(b) : result_id(b);
                const u32 x = ka ? *ka : *ra;
                if (!kb || !map(x, *kb))
                    return false;
                if (ka)
                    made_.emplace_back(x, *kb);
                from = 1;
            }
        }
        for (u32 i = from; i < a.size(); ++i)
            if (!same(a[i], b[i]))
                return false;
        return true;
    }

    std::vector<std::pair<u32, u32>> pairs_;
    std::vector<std::pair<u32, u32>> made_;
    std::vector<std::pair<u32, u32>> gas_;
};

class MergeBranches {
public:
    Value run(Value lines)
    {
        check_stack();
        if (!lines.is_list())
            return lines;
        if (const auto it = memo_.find(lines.raw()); it != memo_.end())
            return it->second;
        poll();
        std::vector<Value> out;
        out.reserve(lines.size());
        bool changed = false;
        for (const Value l : lines.args()) {
            if (l.is(Op::IF, 3) || l.is(Op::MERGED_IF, 3)) {
                const Value t = run(l[1]), f = run(l[2]);
                if (t.is_list() && f.is_list() && SameButIds{}(t, f)) {
                    // (its condition read nothing but values: the lines alone)
                    out.insert(out.end(), t.begin(), t.end());
                    changed = true;
                    continue;
                }
                const Value args[] = {l[0], t, f};
                const Value r = mk_like(l, args);
                if (r != l) {
                    cx().pcs.inherit(r, l);
                    changed = true;
                }
                out.push_back(r);
                continue;
            }
            if (l.is(Op::WHILE, 4)) {
                const Value body = run(l[1]);
                const Value args[] = {l[0], body, l[2], l[3]};
                const Value r = mk_like(l, args);
                if (r != l) {
                    cx().pcs.inherit(r, l);
                    changed = true;
                }
                out.push_back(r);
                continue;
            }
            out.push_back(l);
        }
        const Value r = changed ? mk_like(lines, out) : lines;
        memo_.emplace(lines.raw(), r);
        return r;
    }

private:
    std::unordered_map<u64, Value> memo_;
};

// does the trace read memory that may be [a, a + n)
bool may_read(Value v, const EvmInt& a, const EvmInt& n, std::unordered_set<u64>& seen)
{
    check_stack();
    if (!(v.is_expr() || v.is_list()) || !(v.flags() & F_MEM) || !seen.insert(v.raw()).second)
        return false;
    if (v.is(Op::MEM, 1)) {
        const Value r = v[0];
        if (!r.is(Op::RANGE, 2) || !r[0].is_int() || !r[1].is_int())
            return true;  // (where it reads isn't known: may be there)
        const EvmInt s(r[0]), m(r[1]);
        if (!(m.sign() <= 0 || s + m <= a || a + n <= s))
            return true;
    }
    for (const Value x : v.args())
        if (may_read(x, a, n, seen))
            return true;
    return false;
}

// may a path from these lines read [a, a + n) before a SETMEM writes all of
// it (python's cleanup of the memory never read)
bool read_before_written(Value lines, const EvmInt& a, const EvmInt& n, std::unordered_map<u64, bool>& memo)
{
    check_stack();
    if (!lines.is_list())
        return false;
    if (const auto it = memo.find(lines.raw()); it != memo.end())
        return it->second;
    poll();
    bool r = false;
    for (const Value l : lines.args()) {
        std::unordered_set<u64> seen;
        if (l.is(Op::IF, 3) || l.is(Op::MERGED_IF, 3)) {
            // (its branches' writes don't count for what follows it)
            if (may_read(l[0], a, n, seen) || read_before_written(l[1], a, n, memo) ||
                read_before_written(l[2], a, n, memo)) {
                r = true;
                break;
            }
            continue;
        }
        if (may_read(l, a, n, seen)) {  // (a loop: any of its reads)
            r = true;
            break;
        }
        if (l.is(Op::SETMEM, 2) && l[0].is(Op::RANGE, 2) && l[0][0].is_int() && l[0][1].is_int()) {
            const EvmInt s(l[0][0]), m(l[0][1]);
            if (s <= a && a + n <= s + m)
                break;  // (written over: dead from here)
        }
    }
    memo.emplace(lines.raw(), r);
    return r;
}

// ---- the paths the VM didn't finish ------------------------------------------------------

bool unfinished(Value l) noexcept
{
    return l.is(Op::UNDEFINED, 2) && l[0].is_small() && l[0].small_val() == i64(UndefinedReason::UNFINISHED);
}

// the smallest pc of the trace's UNDEFINED(UNFINISHED, pc) lines
void first_unfinished(Value v, std::optional<i64>& pc, std::unordered_set<u64>& seen)
{
    check_stack();
    if (!(v.is_expr() || v.is_list()) || !seen.insert(v.raw()).second)
        return;
    if (unfinished(v)) {
        const Value p = v[1];
        if (p.is_small() && (!pc || p.small_val() < *pc))
            pc = p.small_val();
        return;
    }
    if (v.is_expr() && !v.is(Op::IF) && !v.is(Op::WHILE) && !v.is(Op::MERGED_IF))
        return;  // (a line: lists of lines are only in these)
    for (const Value a : v.args())
        first_unfinished(a, pc, seen);
}

// every UNDEFINED(UNFINISHED, pc) as the one of the smallest pc
Value as_one(Value v, Value one, std::unordered_map<u64, Value>& memo)
{
    check_stack();
    if (unfinished(v))
        return one;
    if (!(v.is_list() || v.is(Op::IF) || v.is(Op::WHILE) || v.is(Op::MERGED_IF)))
        return v;
    if (const auto it = memo.find(v.raw()); it != memo.end())
        return it->second;
    std::vector<Value> args;
    args.reserve(v.size());
    bool changed = false;
    for (const Value a : v.args()) {
        const Value b = as_one(a, one, memo);
        changed = changed || b != a;
        args.push_back(b);
    }
    Value r = v;
    if (changed) {
        r = mk_like(v, args);
        if (v.is_expr())
            cx().pcs.inherit(r, v);
    }
    memo.emplace(v.raw(), r);
    return r;
}

}  // namespace

Value one_unfinished(Value trace)
{
    // python's undefined line has no pc: the paths its VM didn't finish end
    // the same, and its folder makes them one
    std::optional<i64> pc;
    {
        std::unordered_set<u64> seen;
        first_unfinished(trace, pc, seen);
    }
    if (!pc)
        return trace;
    const Value one = mk(Op::UNDEFINED, Value::small(i64(UndefinedReason::UNFINISHED)), Value::small(*pc));
    std::unordered_map<u64, Value> memo;
    return as_one(trace, one, memo);
}

Value with_entry(Value entry_lines, Value trace)
{
    if (!entry_lines.is_trace() || !trace.is_trace())
        return trace;
    // the dispatcher's checks; its SETMEMs (mem[64] = 128) the body may read
    // - python's trace begins with them, its cleanup drops those never read
    std::vector<Value> lines;
    for (const Value l : entry_lines.args()) {
        if (l.is(Op::IF, 3)) {
            lines.push_back(l);
            continue;
        }
        if (l.is(Op::SETMEM, 2) && l[0].is(Op::RANGE, 2) && l[0][0].is_int() && l[0][1].is_int()) {
            std::unordered_map<u64, bool> memo;
            if (read_before_written(trace, EvmInt(l[0][0]), EvmInt(l[0][1]), memo))
                lines.push_back(l);
        }
    }
    if (lines.empty())
        return trace;
    lines.insert(lines.end(), trace.begin(), trace.end());
    return mk_trace(std::span<const Value>(lines.data(), lines.size()));
}

Value snapshot_call_results(Value trace)
{
    if (!trace.is_trace())
        return trace;
    return Snapshots{}.run(trace);
}

Value merge_same_branches(Value ast)
{
    if (!ast.is_list())
        return ast;
    return MergeBranches{}.run(ast);
}

}  // namespace pan::output::detail
