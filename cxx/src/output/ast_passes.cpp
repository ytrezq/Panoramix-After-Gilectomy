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
//    on call k (its offsets and lengths of numbers or of call k's size). A
//    variable holds a word: a read of more than 32 bytes, a variable per
//    word, the read their concatenation (python snapshots the stack's words).
//  - Gas reads in the line that uses them (after SafeMath: inline_gas_reads):
//    the VM gives each read a variable where the code reads it; the text's
//    gas_remaining is the gas left where it's printed - a read the next line
//    uses once, and no other, is printed there (GasInline).
//  - An if whose branches are the same lines but for the ids of the calls
//    they make (python has no ids: they're equal there) is its lines.
//  - The paths the VM didn't finish end in one line (python's has no pc:
//    its folder merges them).
// And the text's view (printing only, no value made): the ifs whose
// branches print the same, the variables only their conditions read.
#include <algorithm>
#include <optional>
#include <set>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include "algebra/eval.hpp"
#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/contract.hpp"
#include "mem/memory.hpp"
#include "output/fold.hpp"
#include "output/print.hpp"

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

// The words of a read of more than 32 bytes of a call's return data,
// RETURNDATA_BYTES(k, off, n) with n a number: the reads of 32 bytes from
// off, off + 32... (the last one shorter), as the memory model slices them (a
// word the text reads elsewhere: that read). A variable holds a word - the
// trace machine's, the text's - as python's VM snapshots the stack's words:
// the asm's `_9 = ext_call.return_data[0]`, `_13 = ...[32]`, `_14 = ...[64]`
// where one variable of 96 bytes is none. nullopt for a read of a word at
// most, of a length that isn't a number or past kWideMax bytes (a variable
// per word: a hostile length mustn't make millions), or a word whose offset
// may wrap (mem::slice can't say).
constexpr i64 kWideMax = 1024;

std::optional<std::vector<Value>> wide_words(Value t)
{
    if (!t.is(Op::RETURNDATA_BYTES, 3) || !t[2].is_small())
        return std::nullopt;
    const i64 n = t[2].small_val();
    if (n <= 32 || n > kWideMax)
        return std::nullopt;
    std::vector<Value> r;
    for (i64 at = 0; at < n; at += 32) {
        const auto w = mem::slice(t, Value::small(at), Value::small(std::min(n, at + 32)));
        if (!w || !w->is(Op::RETURNDATA_BYTES, 3) || (*w)[0] != t[0])
            return std::nullopt;
        r.push_back(*w);
    }
    return r;
}

// v's operand i is a byte element (a DATA's and a SHA3's every one: past
// mem::byte_operands' 32 too)
bool byte_element(Value v, u32 i) noexcept
{
    if (v.is(Op::DATA) || v.is(Op::SHA3))
        return true;
    const std::span<const u8> bytes = mem::byte_operands(v);
    return std::find(bytes.begin(), bytes.end(), u8(i)) != bytes.end();
}

bool is_if(Value l) noexcept { return l.is(Op::IF, 3) || l.is(Op::MERGED_IF, 3); }

// the ids of the trace's _N
void tmps_in(Value v, std::unordered_set<u32>& used, std::unordered_set<u64>& seen)
{
    check_stack();
    if (v.is_name(NameKind::TMP)) {
        used.insert(v.name_id());
        return;
    }
    if (!(v.is_expr() || v.is_list()) || !(v.flags() & F_VAR) || !seen.insert(v.raw()).second)
        return;
    for (const Value a : v.args())
        tmps_in(a, used, seen);
}

// n fresh _N: the first ids the trace doesn't have (python's VM numbers its
// snapshots with the others: `_1` the first)
std::vector<Value> fresh_tmps(Value trace, usize n)
{
    std::unordered_set<u32> used;
    {
        std::unordered_set<u64> seen;
        tmps_in(trace, used, seen);
    }
    std::vector<Value> r;
    r.reserve(n);
    u32 next = 1;
    while (r.size() < n) {
        while (used.contains(next))
            ++next;
        used.insert(next);
        r.push_back(Value::name(NameKind::TMP, next));
    }
    return r;
}

// does v have a SAFEMATH (an expression that may fail)
bool may_fail(Value v, std::unordered_set<u64>& seen)
{
    check_stack();
    if (!(v.is_expr() || v.is_list()) || !seen.insert(v.raw()).second)
        return false;
    if (v.is_expr() && v.op() == Op::SAFEMATH)
        return true;
    for (const Value a : v.args())
        if (may_fail(a, seen))
            return true;
    return false;
}
bool may_fail(Value v)
{
    std::unordered_set<u64> seen;
    return may_fail(v, seen);
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
        const std::vector<Value> vars = fresh_tmps(trace, needs_.size());
        for (usize i = 0; i < needs_.size(); ++i)
            var_of_.emplace(needs_[i].raw(), vars[i]);
        rewrite_ = true;
        memo_.clear();
        steps_ = 0;
        Last start;
        const Value r = walk(trace, start);
        return steps_ > kMaxSteps ? trace : r;
    }

private:
    static constexpr u64 kMaxSteps = u64(1) << 21;  // (a walk past it: the trace as it is)

    static bool surely(const Last& last, u32 k) noexcept { return last.size() == 1 && last[0] == k; }

    // a line's (or an expression's) reads: pass 1 notes those the text may
    // take for another call's, pass 2 reads their variables there
    Value use(Value e, const Last& last, std::unordered_map<u64, Value>& memo)
    {
        check_stack();
        if (const auto k = result_id(e); k && *k != 0 && *k != kInternalCalls && !surely(last, *k) &&
                                          snapshot_safe(e, *k)) {
            // (more than a word: its words' variables, concatenated)
            if (const auto words = wide_words(e))
                return use_words(e, *words);
            if (!rewrite_) {
                note(e);
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
        // (a byte element - a SHA3's, a DATA's, a call's arguments... - that
        // was return data bytes: the variable as wide as they were, as every
        // byte element carries its width)
        const bool elements = e.is(Op::DATA) || e.is(Op::SHA3);
        for (u32 i = 0; i < e.size(); ++i) {
            const Value a = e[i];
            Value b = use(a, last, memo);
            if (a.is(Op::RETURNDATA_BYTES, 3) && noted_.contains(a.raw()) && byte_element(e, i)) {
                // (its length read here too: call k's, its size a variable
                // as well when another call may have been made)
                const Value n = use(a[2], last, memo);
                if (rewrite_ && b.is_name())
                    b = mem::sized(n, b);
            }
            changed = changed || b != a;
            // (the words of a wide read among a DATA's or a SHA3's elements:
            // elements there)
            if (elements && b != a && a.is(Op::RETURNDATA_BYTES) && b.is(Op::DATA)) {
                args.insert(args.end(), b.args().begin(), b.args().end());
                continue;
            }
            args.push_back(b);
        }
        const Value r = changed && rewrite_ ? mk_like(e, args) : e;
        memo.emplace(e.raw(), r);
        return r;
    }

    void note(Value t)
    {
        if (noted_.insert(t.raw()).second)
            needs_.push_back(t);
    }

    // a read of more than a word (t) where the text may take it for another
    // call's: pass 1 notes its words, pass 2 reads their variables, each as
    // wide as its word, one after the other (a DATA: the same bytes)
    Value use_words(Value t, const std::vector<Value>& words)
    {
        if (!rewrite_) {
            for (const Value w : words)
                note(w);
            return t;
        }
        std::vector<Value> parts;
        parts.reserve(words.size());
        for (const Value w : words) {
            const auto it = var_of_.find(w.raw());
            if (it == var_of_.end())
                return t;
            parts.push_back(mem::sized(w[2], it->second));
        }
        return mk(Op::DATA, parts);
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
    std::vector<Value> needs_;              // the reads given a variable, in the order found
    std::unordered_set<u64> noted_;
    std::unordered_map<u64, Value> var_of_;  // a read -> its variable
    std::unordered_map<u64, std::vector<Memo>> memo_;  // lines -> (last before, after, what they became)
};

// ---- the gas reads printed in the line that uses them ------------------------------------

// A GAS read is a variable set where the code reads it (vm.hpp), but a
// call's own gas (the read right before the call: the call line's operand).
// The text's gas_remaining is the gas left where it's printed: a read the
// next line uses once, and no other line, is printed in that line (`require
// gas_remaining >= 5000`, `x = SafeMath.sub(gas_remaining, _3)`) - its
// variable gone, the same read at the same place (no line between them).
// Not in a part of the line that may run more than once or not at all: a
// loop (its condition runs at every iteration, its setvars print as lines
// of their own), the branches of an if (their own lines), the right side of
// an `and` or an `or`, a call's gas (no interpreter of the text evaluates
// it: the read would be gone from the run). Anywhere else, the variable
// stays.
class GasInline {
public:
    Value run(Value trace)
    {
        scan(trace);
        if (steps_ > kMaxSteps)
            return trace;
        for (auto& [raw, v] : vars_)
            if (!v.far && !v.other_set && v.sets > 0 && v.sets == v.adjacent)
                inline_.insert(raw);
        if (inline_.empty())
            return trace;
        return rewrite(trace);
    }

private:
    static constexpr u64 kMaxSteps = u64(1) << 21;  // (a walk past it: the trace as it is)

    struct Var {
        u32 sets = 0;      // the SETVARs of a read of the gas left (positions in distinct lists)
        u32 adjacent = 0;  // those followed by a line using it once where it may stand
        bool far = false;  // a use anywhere else
        bool other_set = false;  // set to something else too (a merge's variable...)
    };

    static bool is_tmp(Value v) noexcept { return v.is_name(NameKind::TMP); }

    // SETVAR(_N, a read of the gas left)
    static bool gas_set(Value l) noexcept
    {
        return l.is(Op::SETVAR, 2) && is_tmp(l[0]) && l[1].is_leaf() && l[1].op() == Op::GAS;
    }

    // the _N an expression reads (any depth), counted: in `once` those of a
    // part every run of the line evaluates once, in `far` the others
    void reads(Value v, bool once, std::unordered_map<u64, u32>& count, std::unordered_set<u64>& far)
    {
        check_stack();
        if (++steps_ > kMaxSteps)
            return;
        if (v.is_name()) {
            if (is_tmp(v)) {
                if (once)
                    ++count[v.raw()];
                else
                    far.insert(v.raw());
            }
            return;
        }
        if (!(v.is_expr() || v.is_list()) || !(v.flags() & F_VAR))
            return;
        const bool short_circuit = v.is(Op::LAND, 2) || v.is(Op::LOR, 2);
        for (u32 i = 0; i < v.size(); ++i)
            reads(v[i], once && !(short_circuit && i > 0), count, far);
    }

    // what a line reads that the walk of its list sees: its own parts (an
    // if's condition, a line's operands; a loop's: none) - its nested lists
    // are walked as lists of their own
    void line_reads(Value l, std::unordered_map<u64, u32>& count, std::unordered_set<u64>& far)
    {
        if (!l.is_expr())
            return;
        switch (l.op()) {
            case Op::IF:
            case Op::MERGED_IF:
                reads(l[0], true, count, far);
                return;
            case Op::WHILE:
                reads(l[0], false, count, far);
                reads(l[3], false, count, far);
                return;
            case Op::CONTINUE:
            case Op::GOTO:
            case Op::LABEL:
                reads(l[1], false, count, far);
                return;
            case Op::LOOP_PATH:
                reads(l[1], false, count, far);
                return;
            case Op::SETVAR:
                reads(l[1], true, count, far);
                return;
            case Op::PRECOMPILED:
                // (its name is set, not read)
                reads(l[2], true, count, far);
                reads(l[3], true, count, far);
                return;
            case Op::INTERNAL:
                reads(l[1], true, count, far);
                return;
            case Op::CALL:
            case Op::CALLCODE:
            case Op::DELEGATECALL:
            case Op::STATICCALL:
                // (its gas: never evaluated by the text's interpreter)
                for (u32 i = 2; i < l.size(); ++i)
                    reads(l[i], true, count, far);
                reads(l[1], false, count, far);
                return;
            default:
                for (const Value a : l.args())
                    reads(a, true, count, far);
                return;
        }
    }

    // the setvars of a loop's head or a continue: their names set to anything
    void setvars_set(Value sv)
    {
        if (!sv.is_list())
            return;
        for (const Value x : sv.args())
            if (x.is(Op::SETVAR, 2) && is_tmp(x[0]))
                vars_[x[0].raw()].other_set = true;
    }

    void scan(Value lines)
    {
        check_stack();
        if (!lines.is_list() || !seen_.insert(lines.raw()).second || ++steps_ > kMaxSteps)
            return;
        poll();
        for (u32 i = 0; i < lines.size(); ++i) {
            const Value l = lines[i];
            if (!l.is_expr())
                continue;
            // what it sets
            if (gas_set(l))
                ++vars_[l[0].raw()].sets;
            else if (l.is(Op::SETVAR, 2) && is_tmp(l[0]))
                vars_[l[0].raw()].other_set = true;
            else if (l.is(Op::WHILE, 4))
                setvars_set(l[3]);
            else if (l.is(Op::CONTINUE, 2) || l.is(Op::GOTO, 2) || l.is(Op::LABEL, 2))
                setvars_set(l[1]);
            else if (l.is(Op::INTERNAL, 3) && l[2].is_list())
                for (const Value n : l[2].args())
                    if (is_tmp(n))
                        vars_[n.raw()].other_set = true;
            // what it reads
            std::unordered_map<u64, u32> count;
            std::unordered_set<u64> far;
            line_reads(l, count, far);
            for (const u64 r : far)
                vars_[r].far = true;
            for (const auto& [r, k] : count) {
                Var& v = vars_[r];
                if (k == 1 && !far.contains(r) && i > 0 && gas_set(lines[i - 1]) && lines[i - 1][0].raw() == r)
                    ++v.adjacent;
                else
                    v.far = true;
            }
            // its lines' lists
            for (const u32 k : nested(l))
                scan(l[k]);
        }
    }

    // the operands of a line that are lines of their own: an if's branches,
    // a loop's body
    static SmallVec<u32, 2> nested(Value l)
    {
        SmallVec<u32, 2> r;
        if (l.is(Op::IF, 3) || l.is(Op::MERGED_IF, 3)) {
            r.push_back(1);
            r.push_back(2);
        } else if (l.is(Op::WHILE, 4)) {
            r.push_back(1);
        } else if (l.is(Op::LOOP_PATH, 2)) {
            r.push_back(0);
        }
        return r;
    }

    // v with each variable inlined replaced by its read
    Value put(Value v, const std::unordered_map<u64, Value>& reads)
    {
        check_stack();
        if (v.is_name())
            if (const auto it = reads.find(v.raw()); it != reads.end())
                return it->second;
        if (!(v.is_expr() || v.is_list()) || !(v.flags() & F_VAR) || v.is_trace())
            return v;
        std::vector<Value> args;
        args.reserve(v.size());
        bool changed = false;
        for (const Value a : v.args()) {
            const Value b = put(a, reads);
            changed = changed || b != a;
            args.push_back(b);
        }
        return changed ? mk_like(v, args) : v;
    }

    Value rewrite(Value lines)
    {
        check_stack();
        if (!lines.is_list())
            return lines;
        if (const auto it = done_.find(lines.raw()); it != done_.end())
            return it->second;
        poll();
        std::vector<Value> out;
        out.reserve(lines.size());
        bool changed = false;
        std::unordered_map<u64, Value> pending;  // the read the next line takes
        for (const Value l : lines.args()) {
            Value r = l;
            if (l.is_expr()) {
                const SmallVec<u32, 2> lists = nested(l);
                std::vector<Value> args;
                args.reserve(l.size());
                bool inner = false;
                for (u32 k = 0; k < l.size(); ++k) {
                    const Value a = l[k];
                    const bool list = std::find(lists.begin(), lists.end(), k) != lists.end();
                    const Value b = list ? rewrite(a) : (pending.empty() ? a : put(a, pending));
                    inner = inner || b != a;
                    args.push_back(b);
                }
                if (inner) {
                    r = mk_like(l, args);
                    cx().pcs.inherit(r, l);
                }
            }
            pending.clear();
            if (gas_set(l) && inline_.contains(l[0].raw())) {
                pending.emplace(l[0].raw(), l[1]);
                changed = true;
                continue;
            }
            changed = changed || r != l;
            out.push_back(r);
        }
        const Value res = changed ? mk_like(lines, out) : lines;
        done_.emplace(lines.raw(), res);
        return res;
    }

    u64 steps_ = 0;
    std::unordered_set<u64> seen_;
    std::unordered_map<u64, Var> vars_;
    std::unordered_set<u64> inline_;
    std::unordered_map<u64, Value> done_;
};

// ---- what the text prints the same ------------------------------------------------------

// a ~ b as the text prints them: but for the calls' ids (the text names a
// result by its call's kind) and the gas reads' numbers
class SameText {
public:
    explicit SameText(Value ast)
    {
        std::unordered_set<u64> seen;
        calls(ast, seen);
    }

    bool operator()(Value a, Value b)
    {
        check_stack();
        if (a == b)
            return true;
        if (a.is_leaf() && b.is_leaf()) {
            if (a.op() != b.op())
                return false;
            switch (a.op()) {
                case Op::GAS:
                case Op::RETURNDATASIZE:
                    return true;
                case Op::CALL_SUCCESS:
                case Op::CREATE_ADDRESS:
                    return kind(a.leaf_n()) == kind(b.leaf_n());
                default:
                    return false;
            }
        }
        if (a.is_expr() != b.is_expr() || a.is_list() != b.is_list() || !(a.is_expr() || a.is_list()))
            return false;
        if (a.is_expr() ? a.op() != b.op() : a.is_trace() != b.is_trace())
            return false;
        if (a.size() != b.size())
            return false;
        const std::pair<u64, u64> key{a.raw(), b.raw()};
        if (const auto it = memo_.find(key); it != memo_.end())
            return it->second;
        poll();
        usize from = 0;
        if (a.is_expr() && (call_line_id(a) || result_id(a))) {
            if (!(call_line_id(b) || result_id(b)))
                return false;
            from = 1;
        }
        bool r = true;
        for (usize i = from; i < a.size() && r; ++i)
            r = (*this)(a[u32(i)], b[u32(i)]);
        memo_.emplace(key, r);
        return r;
    }

private:
    // a call's kind (and a precompile's address): its results' names
    void calls(Value v, std::unordered_set<u64>& seen)
    {
        check_stack();
        if (!(v.is_expr() || v.is_list()) || !seen.insert(v.raw()).second)
            return;
        if (v.is_expr()) {
            if (const auto id = call_line_id(v)) {
                u32 addr = 0;
                if (v.op() == Op::PRECOMPILED && v.size() > 2 && v[2].is_small())
                    addr = u32(v[2].small_val()) & 0xffffu;
                kinds_.emplace(*id, (u32(v.op()) << 16) | addr);
                return;
            }
            if (!is_if(v) && !v.is(Op::WHILE))
                return;
        }
        for (const Value a : v.args())
            calls(a, seen);
    }
    u32 kind(u32 id) const
    {
        const auto it = kinds_.find(id);
        return it != kinds_.end() ? it->second : 0;
    }

    struct PairHash {
        usize operator()(const std::pair<u64, u64>& p) const noexcept
        {
            return usize(hash_mix(p.first ^ hash_mix(p.second)));
        }
    };
    std::unordered_map<u32, u32> kinds_;  // call id -> kind
    std::unordered_map<std::pair<u64, u64>, bool, PairHash> memo_;
};

// the _N v reads (a SETVAR's name: set, not read)
void tmp_reads(Value v, std::unordered_set<u64>& read, std::unordered_set<u64>& seen)
{
    check_stack();
    if (v.is_name()) {
        if (v.is_name(NameKind::TMP))
            read.insert(v.raw());
        return;
    }
    if (!(v.is_expr() || v.is_list()) || !(v.flags() & F_VAR) || !seen.insert(v.raw()).second)
        return;
    if (v.is(Op::SETVAR, 2)) {
        tmp_reads(v[1], read, seen);
        return;
    }
    for (const Value a : v.args())
        tmp_reads(a, read, seen);
}

// the ifs whose branches print the same and whose condition can't fail; the
// _N their conditions read
void same_ifs(Value lines, SameText& same, TextView& view, std::unordered_set<u64>& cand,
              std::unordered_set<u64>& seen)
{
    check_stack();
    if (!lines.is_list() || !seen.insert(lines.raw()).second)
        return;
    for (const Value l : lines.args()) {
        if (is_if(l)) {
            same_ifs(l[1], same, view, cand, seen);
            same_ifs(l[2], same, view, cand, seen);
            if (l[1].is_list() && l[2].is_list() && same(l[1], l[2]) && !may_fail(l[0])) {
                view.one_branch.insert(l.raw());
                std::unordered_set<u64> s;
                tmp_reads(l[0], cand, s);
            }
        } else if (l.is(Op::WHILE, 4)) {
            same_ifs(l[1], same, view, cand, seen);
        }
    }
}

// the _N the text reads; keep: those a SETVAR the text can't drop sets (its
// value may fail or reads the gas left, or it's its list's only line)
void printed_reads(Value lines, const TextView& view, std::unordered_set<u64>& read, std::unordered_set<u64>& keep,
                   std::unordered_set<u64>& seen, std::unordered_set<u64>& seen_reads)
{
    check_stack();
    if (!lines.is_list() || !seen.insert(lines.raw()).second)
        return;
    for (const Value l : lines.args()) {
        if (is_if(l)) {
            if (view.one_branch.contains(l.raw())) {
                printed_reads(l[1], view, read, keep, seen, seen_reads);
                continue;
            }
            tmp_reads(l[0], read, seen_reads);
            printed_reads(l[1], view, read, keep, seen, seen_reads);
            printed_reads(l[2], view, read, keep, seen, seen_reads);
            continue;
        }
        if (l.is(Op::WHILE, 4)) {
            tmp_reads(l[0], read, seen_reads);
            tmp_reads(l[3], read, seen_reads);
            printed_reads(l[1], view, read, keep, seen, seen_reads);
            continue;
        }
        // (a read of the gas left too: the text reads it where the code does)
        if (l.is(Op::SETVAR, 2) && l[0].is_name(NameKind::TMP) &&
            (lines.size() == 1 || may_fail(l[1]) || (l[1].is_leaf() && l[1].op() == Op::GAS)))
            keep.insert(l[0].raw());
        tmp_reads(l, read, seen_reads);
    }
}

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


Value gas_inline(Value trace)
{
    if (!trace.is_list())
        return trace;
    return GasInline{}.run(trace);
}

TextView text_view(Value ast)
{
    TextView view;
    if (!ast.is_list())
        return view;
    SameText same(ast);
    std::unordered_set<u64> cand;
    {
        std::unordered_set<u64> seen;
        same_ifs(ast, same, view, cand, seen);
    }
    if (cand.empty())
        return view;
    std::unordered_set<u64> read, keep;
    {
        std::unordered_set<u64> seen, seen_reads;
        printed_reads(ast, view, read, keep, seen, seen_reads);
    }
    for (const u64 n : cand)
        if (!read.contains(n) && !keep.contains(n))
            view.unset.insert(n);
    return view;
}

Value merge_same_branches(Value ast)
{
    if (!ast.is_list())
        return ast;
    return MergeBranches{}.run(ast);
}

}  // namespace pan::output::detail
