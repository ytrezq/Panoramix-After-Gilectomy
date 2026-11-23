// The folder (python folder.py, asm folder.s): a trace's paths folded back
// into the display form - shared beginnings and endings once,
// if-without-else where a branch ends, the ifs whose branches begin alike
// with those lines above them (when they don't change what the condition
// reads: lot 7's effect summaries).
//
//   as_paths     the trace unfolded into its branchless paths: an IF that
//                is a trace's last line splits the path (its condition, or
//                its negation, an item of each); an IF followed by more lines
//                (its branches join again) folded on its own, kept as one
//                opaque MERGED_IF item
//   fold_paths   the paths of a level share a beginning and an end: taken
//                off all of them at once, the rest grouped by their first
//                item (a condition or its negation) into an or of two
//                alternatives, recursively - on stretches (start, trim) of the
//                paths, not copies (python's n^3 for n nested ifs is n^2)
//   flatten, cleanup_ors, make_ifs, merge_ifs, fold_aux: python's
//
// The items of a path are Values (hash-consed on the fold's context: equal
// items are equal words): a line; a condition LIST[0|1, cond] (1: its
// negation); an or LIST[2, LIST(alternative), LIST(alternative)] or,
// one-sided, LIST[3, LIST(alternative)].
//
// What it makes is equivalent to the trace (the same effects for every
// input, ir.md 4): a fold that can't (python's asserts) throws FoldFail
// and the trace is left as it is.
#include <algorithm>
#include <optional>
#include <vector>

#include "algebra/construct.hpp"
#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/errors.hpp"
#include "output/fold.hpp"
#include "simplify/effects.hpp"

namespace pan::output::detail {

namespace {

// python's asserts and its failures in fold_or: the fold isn't made
struct FoldFail {};

constexpr i64 TAG_COND = 0, TAG_NEG = 1, TAG_OR2 = 2, TAG_OR1 = 3;

// a path on the fold's budget (its memory counted: FOLD_LIMIT)
using Path = std::pmr::vector<Value>;
std::pmr::memory_resource* res() { return cx().budget.resource(); }
template <class It>
Path path_of(It b, It e)
{
    return Path(b, e, res());
}

bool is_small(Value v, i64 x) noexcept { return v.is_small() && v.small_val() == x; }

// ---- items ----
bool is_cond(Value it) noexcept
{
    return it.is_list() && !it.is_trace() && it.size() == 2 && (is_small(it[0], TAG_COND) || is_small(it[0], TAG_NEG));
}
bool is_or(Value it) noexcept
{
    return it.is_list() && !it.is_trace() && it.size() >= 2 && (is_small(it[0], TAG_OR2) || is_small(it[0], TAG_OR1));
}
bool is_or2(Value it) noexcept { return it.is_list() && !it.is_trace() && it.size() == 3 && is_small(it[0], TAG_OR2); }
bool is_or1(Value it) noexcept { return it.is_list() && !it.is_trace() && it.size() == 2 && is_small(it[0], TAG_OR1); }

// a condition as an item: its base (no BOOL, no ISZERO of it) and polarity
Value cond_item(Value c, bool neg)
{
    for (;;) {
        if (c.is(Op::BOOL, 1)) {
            c = c[0];
            continue;
        }
        if (c.is(Op::ISZERO, 1)) {
            c = c[0];
            neg = !neg;
            continue;
        }
        break;
    }
    return mk_list({Value::small(neg ? TAG_NEG : TAG_COND), c});
}
// the condition an item tests (python's line[1][0] as an if's condition)
Value cond_value(Value it)
{
    if (!is_cond(it))
        throw FoldFail{};
    return is_small(it[0], TAG_NEG) ? alg::iszero(it[1]) : it[1];
}
bool complementary(Value a, Value b) noexcept { return is_cond(a) && is_cond(b) && a[1] == b[1] && a[0] != b[0]; }

Value mk_or2(std::span<const Value> a, std::span<const Value> b)
{
    return mk_list({Value::small(TAG_OR2), mk_list(a), mk_list(b)});
}
Value mk_or1(std::span<const Value> a) { return mk_list({Value::small(TAG_OR1), mk_list(a)}); }
std::span<const Value> alt(Value orv, u32 k) { return orv[1 + k].args(); }

// python's TERMINATING (ends_exec's)
bool terminating(Value l) noexcept
{
    switch (l.op()) {
        case Op::RETURN:
        case Op::STOP:
        case Op::SELFDESTRUCT:
        case Op::INVALID:
        case Op::REVERT:
        case Op::CONTINUE:
        case Op::UNDEFINED:
        case Op::LEAVE:
            return true;
        default:
            return false;
    }
}

bool one_sided(Value l) noexcept { return l.is(Op::IF, 3) && (!l[2].is_list() || l[2].size() == 0); }

Value if_line(Value cond, std::span<const Value> t, std::span<const Value> f)
{
    return mk(Op::IF, cond, mk_trace(t), mk_trace(f));
}

// a line that ends the run and prints as one line wherever it's copied: a
// stop, an invalid, a revert of a Panic or of a custom error without params,
// a return of data no memory holds
// (not an aborted path, nor a revert or return of memory, nor an Error the
// printer may show word by word)
bool prints_whole(Value l) noexcept
{
    if (!l.is_expr())
        return false;
    switch (l.op()) {
        case Op::STOP:
        case Op::INVALID:
            return true;
        case Op::RETURN:
            return !(simplify::summary(l).reads & simplify::S_MEM);
        case Op::REVERT: {
            if (l.size() != 1 || (simplify::summary(l).reads & simplify::S_MEM))
                return false;
            const Value d = l[0];
            // (a custom error without params; a Panic)
            if (d.is(Op::SIZED, 2) && is_small(d[0], 4) && d[1].is_int())
                return true;
            if (d.is(Op::DATA, 2) && d[0].is(Op::SIZED, 2) && is_small(d[0][0], 4) && is_small(d[0][1], 0x4e487b71))
                return true;
            // (a custom error of up to three params, each a variable or a
            // number: TimelockController's `revert with 0x5ead8eb5, _12, 4`,
            // its id named once the guards' copies of its hash are one)
            // (not an Error(string): the printer may show it word by word)
            if (!d.is(Op::DATA) || d.size() < 2 || d.size() > 4 || !d[0].is(Op::SIZED, 2) || !is_small(d[0][0], 4) ||
                !d[0][1].is_int() || is_small(d[0][1], 0x08c379a0))
                return false;
            for (u32 k = 1; k < d.size(); ++k) {
                const Value p = d[k].is(Op::SIZED, 2) && is_small(d[k][0], 32) ? d[k][1] : d[k];
                if (!(p.is_int() || p.is_name()))
                    return false;
            }
            return true;
        }
        default:
            return false;
    }
}

// a return of the word 0 (python's ("return", 0))
bool return_zero(Value l) noexcept
{
    if (!l.is(Op::RETURN, 1))
        return false;
    Value d = l[0];
    if (d.is(Op::DATA, 1))
        d = d[0];
    return d.is(Op::SIZED, 2) && is_small(d[0], 32) && is_small(d[1], 0);
}

// does v read the gas left or the memory's size (python changes_read: any
// line changes them)
bool reads_gas_or_msize(Value v, std::vector<u64>& seen)
{
    if (v.is_leaf())
        return v.op() == Op::GAS || v.op() == Op::MSIZE;
    if (v.is_name(NameKind::MSIZE_VAR))
        return true;
    if (!v.is_expr() && !v.is_list())
        return false;
    if (!(v.flags() & (F_STATE | F_MSIZE)))
        return false;
    if (std::find(seen.begin(), seen.end(), v.raw()) != seen.end())
        return false;
    seen.push_back(v.raw());
    check_stack();
    for (const Value a : v.args())
        if (reads_gas_or_msize(a, seen))
            return true;
    return false;
}
bool reads_gas_or_msize(Value v)
{
    std::vector<u64> seen;
    return reads_gas_or_msize(v, seen);
}

}  // namespace

// ---- the folder ---------------------------------------------------------------------------

class Folder {
public:
    Value fold(Value trace);

private:
    void as_paths(Value trace, Path& path, std::pmr::vector<Path>& out);
    Path fold_stretches(std::vector<const Path*> paths, usize start, usize trim);
    std::pair<Value, Path> fold_or_stretches(std::vector<const Path*> sides, usize start, usize trim);
    std::optional<std::pair<usize, usize>> split_stretches(const std::vector<const Path*>& a_sides,
                                                           const std::vector<const Path*>& b_sides, const Path& shortest,
                                                           const Path& longest, usize start, usize trim);
    Path flatten(std::span<const Value> path);
    Path try_merge(Path one, Path two);
    bool ends_exec(std::span<const Value> path);
    Path cleanup_ors(std::span<const Value> path);
    std::vector<Value> make_ifs(std::span<const Value> path);
    std::vector<Value> merge_ifs(std::span<const Value> path);
    std::pair<std::vector<Value>, std::pair<std::vector<Value>, std::vector<Value>>> try_merge_ifs(
        Value cond, std::span<const Value> t, std::span<const Value> f);
    std::vector<Value> fold_aux(std::span<const Value> trace);
    void join_if(Value cond, std::vector<Value> t, std::vector<Value> f, std::vector<Value>& out);
    bool changes_read(Value line, Value cond);
    std::vector<Value> guard_tails(std::vector<Value> lines);

    // the id of the loop whose body is being folded (nil: no loop's)
    Value loop_;
};

// python's fold: the trace itself when it can't
Value Folder::fold(Value trace)
{
    check_stack();
    if (!trace.is_trace())
        return trace;
    try {
        std::pmr::vector<Path> paths(res());
        {
            Path path(res());
            as_paths(trace, path, paths);
        }
        // meta_fold_paths
        std::vector<const Path*> for_merge;
        for (const Path& p : paths)
            if (!p.empty())
                for_merge.push_back(&p);
        Path output = fold_stretches(for_merge, 0, 0);
        paths.clear();
        output = flatten(output);
        output = cleanup_ors(output);
        std::vector<Value> lines = make_ifs(output);
        lines = merge_ifs(lines);
        lines = fold_aux(lines);
        lines = guard_tails(std::move(lines));
        return mk_trace(std::span<const Value>(lines.data(), lines.size()));
    } catch (const FoldFail&) {
        return trace;  // (python: "folder failed in a function", the trace unfolded)
    }
}

// the trace's branchless paths, path the items before it (restored on return);
// an IF followed by more lines folded on its own
void Folder::as_paths(Value trace, Path& path, std::pmr::vector<Path>& out)
{
    check_stack();
    const usize base = path.size();
    const u32 n = trace.size();
    for (u32 i = 0; i < n; ++i) {
        poll();
        const Value line = trace[i];
        if (line.is(Op::IF, 3)) {
            if (i + 1 < n) {
                // the branches merge again and the trace goes on after the if:
                // each branch folded on its own, the if a single item
                path.push_back(mk(Op::MERGED_IF, line[0], fold(line[1]), fold(line[2])));
                continue;
            }
            const usize at = path.size();
            path.push_back(cond_item(line[0], false));
            as_paths(line[1], path, out);
            path.resize(at);
            path.push_back(cond_item(line[0], true));
            as_paths(line[2], path, out);
            path.resize(base);
            return;
        }
        path.push_back(line);
    }
    out.push_back(path);
    path.resize(base);
}

// python's _fold_stretches: fold_path_lists of [path[start : len(path) - trim] for path in paths]
Path Folder::fold_stretches(std::vector<const Path*> paths, usize start, usize trim)
{
    check_stack();
    poll();
    if (paths.empty())
        return Path(res());
    if (paths.size() == 1) {
        const Path& p = *paths[0];
        return path_of(p.begin() + i64(start), p.end() - i64(trim));
    }
    std::stable_sort(paths.begin(), paths.end(), [](const Path* a, const Path* b) { return a->size() > b->size(); });
    // the lines all the paths begin with, as the first (the longest) does,
    // and those they all end with - all of it at most
    const Path& first = *paths[0];
    const usize f_end = first.size() - trim;
    usize begin = 0;
    while (begin < f_end - start &&
           std::all_of(paths.begin(), paths.end(), [&](const Path* p) {
               return p->size() - trim - start > begin && (*p)[start + begin] == first[start + begin];
           }))
        ++begin;
    usize end = 0;
    while (end < f_end - start && std::all_of(paths.begin(), paths.end(), [&](const Path* p) {
               return p->size() - trim - start > end && (*p)[p->size() - trim - 1 - end] == first[f_end - 1 - end];
           }))
        ++end;
    Path output = path_of(first.begin() + i64(start), first.begin() + i64(start + begin));
    const Path ending = path_of(first.begin() + i64(f_end - end), first.begin() + i64(f_end));
    // the paths without them (those too short for both, without the
    // beginning, aren't in the or - none is, from as_paths: a condition item
    // is shared by no path taking the other side at every if of its
    // condition, so the beginning and the ending hold lines only, and two
    // paths or more of a level each hold a condition item between them;
    // review 2026-11-02, 15-output1 F1)
    start += begin;
    if (end > 0) {
        std::vector<const Path*> kept;
        for (const Path* p : paths)
            if (p->size() - trim - start >= end)
                kept.push_back(p);
        paths = std::move(kept);
        trim += end;
    }
    std::stable_sort(paths.begin(), paths.end(), [](const Path* a, const Path* b) { return a->size() < b->size(); });
    auto [ors, rest] = fold_or_stretches(paths, start, trim);
    if (!ors.nil())
        output.push_back(ors);
    output.insert(output.end(), rest.begin(), rest.end());
    output.insert(output.end(), ending.begin(), ending.end());
    return output;
}

// python's _fold_or_stretches: the or of the sides' stretches (sorted by
// length), and what's left folded
std::pair<Value, Path> Folder::fold_or_stretches(std::vector<const Path*> sides, usize start, usize trim)
{
    if (sides.empty())
        return {Value(), Path(res())};
    if (sides.size() == 1) {
        // (python's fold_or fails on one side: here, the side itself)
        const Path& p = *sides[0];
        return {Value(), path_of(p.begin() + i64(start), p.end() - i64(trim))};
    }
    if (sides[0]->size() - trim == start)
        throw FoldFail{};  // (an empty side: python's fold_or fails)
    const Path& longest = *sides.back();
    const Value l0 = longest[start];
    usize i = 0;
    while ((*sides[i])[start] == l0) {
        ++i;
        if (i == sides.size())
            throw FoldFail{};  // (they all begin alike: fold_or fails)
    }
    const Path& shortest = *sides[i];
    const Value s0 = shortest[start];
    for (const Path* s : sides)
        if ((*s)[start] != l0 && (*s)[start] != s0)
            throw FoldFail{};  // (another first line: fold_or fails)
    // the sides beginning with the shortest's first line, and the others, with the longest's
    std::vector<const Path*> a_sides, b_sides;
    for (const Path* s : sides)
        ((*s)[start] == s0 ? a_sides : b_sides).push_back(s);
    if (2 * a_sides.size() == sides.size()) {
        if (const auto best = split_stretches(a_sides, b_sides, shortest, longest, start, trim)) {
            const auto [idx1, idx2] = *best;
            // python's or_op(shortest[start:start+idx1], longest[start:start+idx2]): sorted by length
            std::span<const Value> sa(shortest.data() + start, idx1), lb(longest.data() + start, idx2);
            const Value ors = sa.size() <= lb.size() ? mk_or2(sa, lb) : mk_or2(lb, sa);
            return {ors, fold_stretches(a_sides, start + idx1, trim)};
        }
    }
    // cut the first line, merge the remaining paths if possible
    Path s1 = fold_stretches(a_sides, start + 1, trim);
    Path s2 = fold_stretches(b_sides, start + 1, trim);
    s1.insert(s1.begin(), s0);
    s2.insert(s2.begin(), l0);
    return {mk_or2(s1, s2), Path(res())};
}

// python's _split_stretches: the first pair (idx1 lines of the shortest,
// idx2 of the longest) that splits the or in two - the sides beginning
// with those lines all of them, as many of each, with the same rest after
// them
std::optional<std::pair<usize, usize>> Folder::split_stretches(const std::vector<const Path*>& a_sides,
                                                                const std::vector<const Path*>& b_sides,
                                                                const Path& shortest, const Path& longest, usize start,
                                                                usize trim)
{
    const i64 s_len = i64(shortest.size() - trim - start);
    const i64 l_len = i64(longest.size() - trim - start);
    const i64 d = i64(b_sides[0]->size()) - i64(a_sides[0]->size());
    for (usize k = 0; k < a_sides.size(); ++k)
        if (i64(b_sides[k]->size()) - i64(a_sides[k]->size()) != d)
            return std::nullopt;
    i64 hi_a = 0;
    while (hi_a < s_len && std::all_of(a_sides.begin(), a_sides.end(), [&](const Path* a) {
               return i64(a->size() - trim - start) > hi_a && (*a)[start + usize(hi_a)] == shortest[start + usize(hi_a)];
           }))
        ++hi_a;
    i64 hi_b = 0;
    while (hi_b < l_len && std::all_of(b_sides.begin(), b_sides.end(), [&](const Path* b) {
               return i64(b->size() - trim - start) > hi_b && (*b)[start + usize(hi_b)] == longest[start + usize(hi_b)];
           }))
        ++hi_b;
    i64 lo = std::max<i64>(1, 1 - d);
    const i64 hi = std::min({hi_a, s_len - 1, l_len - 1 - d, hi_b - d});
    for (usize k = 0; k < a_sides.size(); ++k) {
        poll();
        if (lo > hi)
            return std::nullopt;
        const Path& a = *a_sides[k];
        const Path& b = *b_sides[k];
        const i64 a_end = i64(a.size() - trim), b_end = i64(b.size() - trim);
        // (the lines past lo end alike, or lo is past it)
        const i64 n = std::min(a_end - i64(start) - lo, b_end - i64(start));
        i64 i = 0;
        while (i < n && a[usize(a_end - 1 - i)] == b[usize(b_end - 1 - i)])
            ++i;
        if (i < a_end - i64(start) - lo)
            lo = a_end - i64(start) - i;
    }
    if (lo > hi)
        return std::nullopt;
    return std::pair<usize, usize>{usize(lo), usize(lo + d)};
}

// python's ends_exec: every subpath ends the execution (the last line)
bool Folder::ends_exec(std::span<const Value> path)
{
    check_stack();
    if (path.empty())
        return false;
    const Value line = path.back();
    if (terminating(line))
        return true;
    if (is_or2(line))
        return ends_exec(alt(line, 0)) && ends_exec(alt(line, 1));
    return false;
}

// python's flatten: if-else into if where a branch ends the execution
Path Folder::flatten(std::span<const Value> path)
{
    check_stack();
    Path res(detail::res());
    for (const Value line : path) {
        poll();
        if (!is_or(line)) {
            res.push_back(line);
            continue;
        }
        if (!is_or2(line))
            throw FoldFail{};  // (only if-else at this stage)
        const auto a = alt(line, 0), b = alt(line, 1);
        if (a.size() == 1 && b.size() == 1)
            continue;  // (both paths, folded, the same: the if is nothing)
        if (ends_exec(a)) {
            Path m = try_merge(flatten(a), flatten(b));
            res.insert(res.end(), m.begin(), m.end());
        } else {
            const Path fa = flatten(a), fb = flatten(b);
            res.push_back(mk_or2(fa, fb));
        }
    }
    return res;
}

// python's try_merge: the lines both end with after the or
Path Folder::try_merge(Path one, Path two)
{
    const Path& shorter = one.size() > two.size() ? two : one;
    usize idx = 1;
    while (idx <= one.size() && idx <= two.size() && one[one.size() - idx] == two[two.size() - idx] &&
           idx < shorter.size())
        ++idx;
    --idx;
    // (the line after a one-sided or is the guard of what follows it, that
    // cleanup_ors skips: it stays with its or)
    auto guard_before = [&](const Path& x) {
        return x.size() >= idx + 1 && is_or1(x[x.size() - idx - 1]);
    };
    while (idx > 0 && (guard_before(one) || guard_before(two)))
        --idx;
    // (not python's: an ending that is only the line that ends the run, or
    // two lines that leave a side nothing but its condition, isn't taken off
    // when that line prints whole in each branch (prints_whole: a stop, a
    // Panic...): the branch that ends stays a guard and the other one's
    // lines follow it, not nested under the negated condition with the
    // ending after them - a revert or a stop the guards share with the main
    // path became, guard by guard, one line at the end of the function, the
    // main path several levels deep: c00152's Panic(17), c00124's custom
    // error, c00284's `if not stor4910:`. A longer ending stays shared
    // (python's `if c: x = 1 else: x = 2` before the lines both end with),
    // and an aborted path, a revert of memory the branches wrote: each copy
    // would print raw.)
    if (idx > 0 && idx <= 2 && idx <= one.size() && prints_whole(one.back()) &&
        (idx == 1 || one.size() - idx <= 1 || two.size() - idx <= 1))
        idx = 0;
    Path res(detail::res());
    if (idx > 0) {
        res.push_back(mk_or2(std::span<const Value>(one.data(), one.size() - idx),
                             std::span<const Value>(two.data(), two.size() - idx)));
        res.insert(res.end(), one.end() - i64(idx), one.end());
    } else {
        res.push_back(mk_or1(one));
        res.insert(res.end(), two.begin(), two.end());
    }
    return res;
}

// python's cleanup_ors: the guards (the negated condition after a one-sided
// or, an else's) dropped
Path Folder::cleanup_ors(std::span<const Value> path)
{
    check_stack();
    Path ret(res());
    for (usize idx = 0; idx < path.size(); ++idx) {
        poll();
        const Value line = path[idx];
        if (!is_or(line)) {
            ret.push_back(line);
            continue;
        }
        if (is_or1(line)) {
            // clean up the inside, skip the next line in the main path (its guard)
            const auto a = alt(line, 0);
            if (a.empty() || idx + 1 >= path.size() || !complementary(a[0], path[idx + 1]))
                throw FoldFail{};
            ret.push_back(mk_or1(cleanup_ors(a)));
            ++idx;
            continue;
        }
        const auto a = alt(line, 0), b = alt(line, 1);
        if (a.empty() || b.empty() || !complementary(a[0], b[0]))
            throw FoldFail{};
        if (a.size() == 1) {
            ret.push_back(mk_or1(cleanup_ors(b)));
        } else {
            const Path ca = cleanup_ors(a), cb = cleanup_ors(b.subspan(1));
            ret.push_back(mk_or2(ca, cb));
        }
    }
    return ret;
}

// python's make_ifs: the ors as ifs (their conditions the first items)
std::vector<Value> Folder::make_ifs(std::span<const Value> path)
{
    check_stack();
    std::vector<Value> ret;
    for (const Value line : path) {
        poll();
        if (!is_or(line)) {
            if (is_cond(line))
                throw FoldFail{};  // (a condition left out of an if)
            ret.push_back(line);
            continue;
        }
        const auto a = alt(line, 0);
        if (a.empty())
            throw FoldFail{};
        const Value cond = cond_value(a[0]);
        const std::vector<Value> t = make_ifs(a.subspan(1));
        if (is_or1(line)) {
            ret.push_back(if_line(cond, t, {}));
        } else {
            const std::vector<Value> f = make_ifs(alt(line, 1));
            ret.push_back(if_line(cond, t, f));
        }
    }
    return ret;
}

// python's changes_read: whether the line may change what cond reads
bool Folder::changes_read(Value line, Value cond)
{
    // (the gas left, the size of the memory: any line may change them)
    if (reads_gas_or_msize(cond))
        return true;
    const simplify::EffectSummary& l = simplify::summary(line);
    const simplify::EffectSummary& c = simplify::summary(cond);
    // A call's results: the IR's are numbered (call 2 changes nothing
    // call_success 1 reads), the text's ext_call.success, return_data...
    // are the last call's - and snapshot_call_results gave them variables
    // on the unfolded trace. A line making a call (an internal function may)
    // doesn't go above a condition reading one: python's changes_read, its
    // STATE_SYMBOLS (review 2026-11-02, 15-output1 F3).
    if ((l.writes & simplify::S_CALLRES) && (c.reads & simplify::S_CALLRES))
        return true;
    // (and a line reading msize doesn't go above a condition whose read of
    // memory may grow it)
    if ((l.reads & simplify::S_MSIZE) && (c.reads & simplify::S_MEM))
        return true;
    return simplify::affects(line, cond);
}

// python's try_merge_ifs: the lines both branches begin with go before the
// if - before its condition is evaluated: up to one that may change what it reads
std::pair<std::vector<Value>, std::pair<std::vector<Value>, std::vector<Value>>> Folder::try_merge_ifs(
    Value cond, std::span<const Value> t, std::span<const Value> f)
{
    usize idx = 0;
    while (idx < std::min(t.size(), f.size()) && t[idx] == f[idx] && !changes_read(t[idx], cond))
        ++idx;
    return {std::vector<Value>(t.begin(), t.begin() + i64(idx)),
            {std::vector<Value>(t.begin() + i64(idx), t.end()), std::vector<Value>(f.begin() + i64(idx), f.end())}};
}

// python's merge_ifs: if-else sections with the same beginnings, the if moved down
std::vector<Value> Folder::merge_ifs(std::span<const Value> path)
{
    check_stack();
    std::vector<Value> ret;
    for (usize idx = 0; idx < path.size(); ++idx) {
        poll();
        const Value line = path[idx];
        if (!line.is(Op::IF, 3)) {
            ret.push_back(line);
            continue;
        }
        const Value cond = line[0];
        if (one_sided(line)) {
            const std::vector<Value> t = merge_ifs(line[1].args());
            const std::vector<Value> f = merge_ifs(path.subspan(idx + 1));
            if (t.empty() || !terminating(t.back())) {
                // what follows the if runs after its body too: it's not an
                // else, nothing of the two is the same code
                ret.push_back(if_line(cond, t, {}));
                ret.insert(ret.end(), f.begin(), f.end());
                break;
            }
            auto [lines, merged] = try_merge_ifs(cond, t, f);
            ret.insert(ret.end(), lines.begin(), lines.end());
            ret.push_back(if_line(cond, merged.first, {}));
            ret.insert(ret.end(), merged.second.begin(), merged.second.end());
            break;
        }
        const std::vector<Value> t = merge_ifs(line[1].args());
        const std::vector<Value> f = merge_ifs(line[2].args());
        auto [lines, merged] = try_merge_ifs(cond, t, f);
        ret.insert(ret.end(), lines.begin(), lines.end());
        ret.push_back(if_line(cond, merged.first, merged.second));
    }
    return ret;
}

// python's join_if (its branches through fold_aux already)
void Folder::join_if(Value cond, std::vector<Value> t, std::vector<Value> f, std::vector<Value>& out)
{
    if (t.empty() && f.empty())
        return;
    if (t.empty()) {
        cond = alg::iszero(cond);
        t = std::move(f);
        f.clear();
    }
    if (f.empty()) {
        out.push_back(if_line(cond, t, {}));
        return;
    }
    if (terminating(t.back()) && !f[0].is(Op::INVALID) && !f[0].is(Op::REVERT)) {
        out.push_back(if_line(cond, t, {}));
        out.insert(out.end(), f.begin(), f.end());
        return;
    }
    out.push_back(if_line(cond, t, f));
}

// python's fold_aux: the last-minute rules (the merged ifs back to ifs, the
// bodies of the loops folded)
std::vector<Value> Folder::fold_aux(std::span<const Value> trace)
{
    check_stack();
    std::vector<Value> out;
    for (usize idx = 0; idx < trace.size(); ++idx) {
        poll();
        const Value line = trace[idx];
        if (line.is(Op::WHILE, 4)) {
            const Value outer = loop_;
            loop_ = line[2];
            const Value body = fold(line[1]);
            loop_ = outer;
            out.push_back(body == line[1] ? line : mk(Op::WHILE, line[0], body, line[2], line[3]));
            continue;
        }
        if (line.is(Op::MERGED_IF, 3)) {
            // the branches are folded already
            auto [lines, merged] = try_merge_ifs(line[0], line[1].args(), line[2].args());
            out.insert(out.end(), lines.begin(), lines.end());
            join_if(line[0], std::move(merged.first), std::move(merged.second), out);
            continue;
        }
        if (line.is(Op::IF, 3)) {
            const Value cond = line[0];
            if (one_sided(line)) {
                std::vector<Value> t(line[1].begin(), line[1].end());
                const std::span<const Value> rest = trace.subspan(idx + 1);
                if (!rest.empty() &&
                    ((rest.size() == 1 && (return_zero(rest[0]) || (rest[0].is(Op::REVERT, 1) && rest[0][0].is_none()))) ||
                     rest[0].is(Op::INVALID))) {
                    if (t.empty() || !terminating(t.back()))
                        t.push_back(rest[0]);
                    t = fold_aux(t);
                    out.push_back(if_line(cond, t, rest));
                    return out;
                }
                t = fold_aux(t);
                if (!t.empty())  // (an if of nothing: nothing)
                    out.push_back(if_line(cond, t, {}));
                continue;
            }
            std::vector<Value> t = fold_aux(line[1].args()), f = fold_aux(line[2].args());
            join_if(cond, std::move(t), std::move(f), out);
            continue;
        }
        out.push_back(line);
    }
    return out;
}

namespace {

// An iteration's end taken as a guard (guard_tails): a tail of kTailLines
// printed lines at most, its `continue` one of them, where the lines it
// un-nests are kGuardRatio times the tail's or more - the characters the
// copy adds are no more than those the lines un-nested lose (four each),
// and no function prints longer or deeper for it.
constexpr usize kTailLines = 5;
constexpr usize kGuardRatio = 8;

// about the lines a line prints (an if and its branches, a loop and its
// body, a continue and the variables it sets, a call and its gas and args)
usize printed_lines(std::span<const Value> lines);
usize printed_lines(Value l)
{
    check_stack();
    if (!l.is_expr())
        return 1;
    switch (l.op()) {
        case Op::IF:
            if (l.size() == 3)
                return 1 + printed_lines(l[1].args()) + (l[2].is_list() && l[2].size() ? 1 + printed_lines(l[2].args()) : 0);
            return 1;
        case Op::WHILE:
            if (l.size() == 4)
                return 1 + printed_lines(l[1].args()) + (l[3].is_list() ? l[3].size() : 0);
            return 1;
        case Op::CONTINUE:
            return 1 + (l.size() == 2 && l[1].is_list() ? l[1].size() : 0);
        case Op::CALL:
        case Op::CALLCODE:
        case Op::DELEGATECALL:
        case Op::STATICCALL:
            return 3;
        default:
            return 1;
    }
}
usize printed_lines(std::span<const Value> lines)
{
    usize n = 0;
    for (const Value l : lines)
        n += printed_lines(l);
    return n;
}

// whether the run may go on past the block's last line (not: it ends the
// run or the iteration, or it is an if-else neither branch of which goes on)
bool goes_on(std::span<const Value> lines)
{
    check_stack();
    if (lines.empty())
        return true;
    const Value l = lines.back();
    if (terminating(l))
        return false;
    if (l.is(Op::IF, 3) && l[1].is_list() && l[2].is_list() && l[1].size() && l[2].size())
        return goes_on(l[1].args()) || goes_on(l[2].args());
    return true;
}

// a line that prints as one line and opens no block: an assignment
bool assignment(Value l) noexcept
{
    return l.is(Op::SETVAR, 2) || l.is(Op::SETMEM, 2) || l.is(Op::STORE, 4) || l.is(Op::SET, 2);
}

}  // namespace

// (not python's) The guards of an iteration's end. Where a block of a
// loop's body ends
//
//     if c:
//         B            (long: the rest of the iteration)
//     T                (a few assignments, the loop's `continue`)
//
// - the paths that skip B and the one through it end alike, and the
// folder took that ending off both (fold_stretches, try_merge: python's) -
// it is made
//
//     if not c:
//         T
//     B
//     T
//
// : the skip is a guard, and B, the iteration's main path, is one level
// up - guard after guard where B ends the same way (an `if c2: B2` before
// T). The same lines run in the same order on each path: with c, B then T;
// without, T - whose last line ends the iteration, so nothing follows the
// guard's copy. (aave311 SupplyLogic's reserves loop: two skips before 150
// lines, each `if not ...: <the counter's increment>; continue` in the text
// before the memory pass made the three endings alike.)
//
// Only the loop's own continue (the copy prints no label, as the original),
// a tail of assignments (kTailLines: each copy prints as the original, one
// line), a B that goes on to T and is long enough (kGuardRatio).
std::vector<Value> Folder::guard_tails(std::vector<Value> lines)
{
    check_stack();
    for (;;) {
        poll();
        const usize n = lines.size();
        if (loop_.nil() || n < 2 || !lines[n - 1].is(Op::CONTINUE, 2) || lines[n - 1][0] != loop_)
            break;
        // the tail: the assignments before the continue, then the if
        usize at = n - 1;
        usize tail = printed_lines(lines[n - 1]);
        while (at > 0 && assignment(lines[at - 1]) && tail <= kTailLines) {
            --at;
            ++tail;
        }
        if (at == 0 || tail > kTailLines)
            break;
        const Value s = lines[at - 1];
        if (!one_sided(s) || !s[1].is_list() || s[1].size() == 0)
            break;
        const auto body = s[1].args();
        if (!goes_on(body) || printed_lines(body) < kGuardRatio * tail)
            break;
        std::vector<Value> out(lines.begin(), lines.begin() + i64(at - 1));
        out.push_back(if_line(alg::iszero(s[0]), std::span<const Value>(lines.data() + at, n - at), {}));
        out.insert(out.end(), body.begin(), body.end());
        out.insert(out.end(), lines.begin() + i64(at), lines.end());
        lines = std::move(out);
    }
    // the blocks in it (a loop's body: folded on its own, done)
    for (Value& l : lines) {
        if (!l.is(Op::IF, 3) || !l[1].is_list() || !l[2].is_list())
            continue;
        std::vector<Value> t = guard_tails(std::vector<Value>(l[1].begin(), l[1].end()));
        std::vector<Value> f = guard_tails(std::vector<Value>(l[2].begin(), l[2].end()));
        const Value nl = if_line(l[0], t, f);
        if (nl != l)
            l = nl;
    }
    return lines;
}

Value fold_trace(Value trace)
{
    Folder f;
    return f.fold(trace);
}

}  // namespace pan::output::detail
