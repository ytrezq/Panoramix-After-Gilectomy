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
    // beginning, aren't in the or)
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
            const Value body = fold(line[1]);
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

Value fold_trace(Value trace)
{
    Folder f;
    return f.fold(trace);
}

}  // namespace pan::output::detail
