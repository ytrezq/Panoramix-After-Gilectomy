// Labels and gotos made whiles and continues (python whiles.make /
// to_while, asm whiles.s).
//
// The raw trace (vm.hpp): LABEL(id, setvars) at a loop's head - the lines
// after it in its trace are the loop: the trace machine runs them, and a
// GOTO(id, setvars) in them (any depth) assigns the setvars and goes back
// to the line after the LABEL. Their end (falling off the trace) is the end
// of the trace that holds the LABEL.
//
// The general form: WHILE(BOOL(1), those lines with each GOTO(id) a
// CONTINUE(id), id, setvars) - the same runs: the setvars at the start, the
// lines, a CONTINUE back to the start, falling off the body is leaving the
// loop for what follows the WHILE: nothing, as it was the end of the trace.
// Always equivalent; python's to_while finds a nicer one when it is:
//
//   LABEL(id, S0); P; IF(c, B, O); R      (R: the IF's continuation, the
//                                           paths that fall off B and O)
//
// with B the branch that jumps back, O the other one, P the lines before
// the exit test (checks on the way: an IF one of whose branches only ends -
// a revert - kept, its other branch spliced after it):
//
//   P[v := S0]; WHILE(c, B', id, S0); R'    B': each GOTO(id, Sk) in B
//                                           preceded by P[v := Sk]
//
// equivalent when (rotation) P sets no loop variable, holds no loop control
// (no jump, no loop), and no line
// of P[v := S] changes what a value of S reads (S: S0, each Sk) - the
// values are the same evaluated after it, where the setvars are now (a call
// in P copied with its id: each run of a copy is that call's latest); and
// when O, which ran before R when the condition failed, is nothing once its
// merge variables are renamed (python exit_values: each one R reads a loop
// variable R neither reads nor sets, the breaks of B setting it instead -
// none of their setvars reading another such), or when no path of B falls
// off it (O then runs after the loop: R' = O; R). Without a continuation
// (the IF the last line of the loop): R' = O, when no path of B falls off
// it or O is nothing.
#include "loops/loops.hpp"

#include <algorithm>
#include <memory_resource>
#include <vector>

#include "algebra/construct.hpp"
#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/errors.hpp"
#include "loops/internal.hpp"
#include "simplify/effects.hpp"

namespace pan::loops {

using namespace detail;

namespace {

Value small(i64 x) { return Value::small(x); }

// the nodes of the lines a rotation may copy, all copies together
constexpr u32 kMaxRotation = 1u << 14;

using Lines = std::pmr::vector<Value>;

class Whiles {
public:
    explicit Whiles(const WhilesOptions& o) : opts_(o), open_(cx().budget.resource()) {}

    // python make: the trace with its labels made whiles, its gotos continues
    Value make(Value trace);

    std::vector<Value> gone;  // the loops whose LABEL nothing loops back to (made plain SETVARs)

private:
    // what a LABEL becomes: before; WHILE(cond, body, id, setvars); remaining
    struct Made {
        explicit Made(std::pmr::memory_resource* r) : before(r), remaining(r) {}
        Lines before;
        Value body;
        Lines remaining;
        Value cond;
        bool loop = true;  // false: nothing loops back (the setvars, then the lines)
        bool renamed = false, exit_after = false, check_exit = false;  // (stats)
    };

    struct Label {
        Value id;
        Value setvars;
        SmallVec<Value, 8> names, starts;
    };

    void to_while(std::span<const Value> rest, const Label& lb, Made& m);
    void as_while_true(Made& m, const Lines& body, std::span<const Value> remaining);
    bool check_exit(const Lines& body, std::span<const usize> checks, const Label& lb, Made& m);
    bool exit_values(Value out, Value body, std::span<const Value> after, const Label& lb, Value& body2,
                     Lines& after2);
    bool break_setvars(Value trace, bool tail, std::span<const Value> from, std::span<const Value> to,
                       std::span<const Value> group);
    bool rotates(const Lines& path, Value body, const Label& lb);
    Value add_path(Value trace, const Lines& path, const Label& lb);
    void substituted(const Lines& path, const Label& lb, Value setvars, Lines& out);
    bool independent(const Lines& lines, Value setvars);
    void gotos(Value v, Value id, SmallVec<Value, 8>& out);

    const WhilesOptions& opts_;
    std::pmr::vector<Value> open_;  // the loops around: their ids
};

Value Whiles::make(Value trace) {
    if (!trace.is_list() || !trace.has_flags(F_LOOPCTL)) return trace;
    check_stack();
    std::pmr::memory_resource* res = cx().budget.resource();
    Lines out(res);
    bool changed = false;
    const u32 n = trace.size();
    for (u32 i = 0; i < n; ++i) {
        poll();
        Value l = trace[i];
        if (!l.is_expr() || !l.has_flags(F_LOOPCTL)) {
            out.push_back(l);
            continue;
        }
        switch (l.op()) {
            case Op::IF:
            case Op::MERGED_IF: {
                Value t = make(l[1]);
                Value e = make(l[2]);
                Value r = mk_like(l, std::span<const Value>({l[0], t, e}));
                cx().pcs.inherit(r, l);
                if (r != l) changed = true;
                out.push_back(r);
                break;
            }
            case Op::WHILE: {
                open_.push_back(l[2]);
                Value b = make(l[1]);
                open_.pop_back();
                Value r = b == l[1] ? l : mk(Op::WHILE, l[0], b, l[2], l[3]);
                cx().pcs.inherit(r, l);
                if (r != l) changed = true;
                out.push_back(r);
                break;
            }
            case Op::LABEL: {
                if (!l[0].is_name(NameKind::LOOP_ID) || !l[1].is_list())
                    throw Unsupported("loops: a malformed LABEL");
                Label lb{l[0], l[1], {}, {}};
                const Value setvars = l[1];
                for (Value x : setvars.args()) {
                    if (!x.is(Op::SETVAR, 2)) throw Unsupported("loops: a LABEL's setvars that are not SETVARs");
                    lb.names.push_back(x[0]);
                    lb.starts.push_back(x[1]);
                }
                Made m(res);
                to_while(std::span<const Value>(trace.data() + i + 1, n - i - 1), lb, m);
                {
                    WhilesStats& ws = whiles_stats();
                    if (!m.loop)
                        ++ws.no_loop;
                    else {
                        ++ws.labels;
                        if (m.cond.is(Op::BOOL, 1) && m.cond[0] == small(1)) {
                            ++ws.while_true;
                        } else {
                            ++ws.exit_test;
                            if (!m.before.empty()) ++ws.rotated;
                            if (m.renamed) ++ws.renamed;
                            if (m.exit_after) ++ws.exit_after;
                            if (m.check_exit) ++ws.check_exit;
                        }
                    }
                }
                // what runs before the loop (no jump of its own: make for the
                // outer loops' gotos all the same)
                if (!m.before.empty()) {
                    Value b = make(trace_of(std::span<const Value>(m.before.data(), m.before.size())));
                    for (Value x : b.args()) out.push_back(x);
                }
                if (m.loop) {
                    open_.push_back(l[0]);
                    Value body = make(m.body);
                    open_.pop_back();
                    Value w = mk(Op::WHILE, m.cond, body, l[0], l[1]);
                    cx().pcs.inherit(w, l);
                    out.push_back(w);
                } else {
                    // nothing loops back: the first iteration's setvars (one
                    // after the other: none reads what another sets), the lines
                    for (Value x : setvars.args()) out.push_back(x);
                    gone.push_back(l[0]);
                    Value b = make(m.body);
                    for (Value x : b.args()) out.push_back(x);
                }
                if (!m.remaining.empty()) {
                    Value r = make(trace_of(std::span<const Value>(m.remaining.data(), m.remaining.size())));
                    for (Value x : r.args()) out.push_back(x);
                }
                return trace_of(std::span<const Value>(out.data(), out.size()));
            }
            case Op::GOTO:
            case Op::CONTINUE: {
                if (!l[0].is_name(NameKind::LOOP_ID) || !l[1].is_list())
                    throw Unsupported("loops: a malformed GOTO");
                if (std::find(open_.begin(), open_.end(), l[0]) == open_.end())
                    throw Unsupported("loops: a GOTO out of its loop");
                Value r = l.is(Op::GOTO) ? mk(Op::CONTINUE, l[0], l[1]) : l;
                cx().pcs.inherit(r, l);
                if (r != l) changed = true;
                out.push_back(r);
                break;
            }
            default: out.push_back(l); break;
        }
    }
    return changed ? trace_of(std::span<const Value>(out.data(), out.size())) : trace;
}

void Whiles::as_while_true(Made& m, const Lines& body, std::span<const Value> remaining) {
    m.before.clear();
    m.body = trace_of(std::span<const Value>(body.data(), body.size()));
    m.remaining.assign(remaining.begin(), remaining.end());
    m.cond = mk(Op::BOOL, small(1));
    m.loop = true;
}

// A loop whose only way out (but halts and outer loops) is a check - IF(c,
// X, []) on its path, X ending the run (a return of what the loop made):
//
//   LABEL(id, S0); P; IF(c, X, []); B          (no path of B falls off it)
//   P[v := S0]; WHILE(iszero(c), B', id, S0); X
//
// (B': B with P[v := Sk] before each GOTO, the rotation's conditions on P).
// X runs where the loop is left, in the state the check saw. The check
// chosen, among those whose X isn't a lone REVERT / INVALID (those stay
// checks, python's): the first whose condition reads a variable of the loop
// (a counter's test at the head), else the last one (a test at the end, the
// loop's state in memory: Vyper's, python's exit test there).
bool Whiles::check_exit(const Lines& body, std::span<const usize> checks, const Label& lb, Made& m) {
    if (!opts_.exit_test || checks.empty()) return false;
    std::pmr::memory_resource* res = cx().budget.resource();
    const std::span<const Value> names(lb.names.data(), lb.names.size());
    auto lone_fail = [](Value x) { return x.size() == 1 && (x[0].is(Op::REVERT) || x[0].is(Op::INVALID)); };
    auto attempt = [&](usize k) {
        const Value chk = body[k];
        const Value c = chk[0], x = chk[1];
        const Value rest = trace_of(std::span<const Value>(body.data() + k + 1, body.size() - k - 1));
        // (no break: X only when the check holds)
        if (falls_through(rest)) return false;
        Lines p(body.begin(), body.begin() + isize(k), res);
        if (!rotates(p, rest, lb)) return false;
        Lines before(res);
        substituted(p, lb, lb.setvars, before);
        m.before.swap(before);
        m.body = add_path(rest, p, lb);
        m.remaining.assign(x.args().begin(), x.args().end());
        m.cond = alg::iszero(c);
        m.loop = true;
        m.check_exit = true;
        return true;
    };
    for (usize k : checks) {
        const Value chk = body[k];
        if (lone_fail(chk[1]) || !reads_any(chk[0], names)) continue;
        if (attempt(k)) return true;
    }
    for (usize i = checks.size(); i-- > 0;) {
        const usize k = checks[i];
        if (lone_fail(body[k][1])) continue;
        return attempt(k);
    }
    return false;
}

// python to_while: the lines after the label (rest) as before, the loop's
// condition and body, what follows the loop
void Whiles::to_while(std::span<const Value> rest, const Label& lb, Made& m) {
    std::pmr::memory_resource* res = cx().budget.resource();
    const Value id = lb.id;
    Lines path(res);
    std::pmr::vector<usize> checks(res);  // the checks spliced into the path: their places in it
    Lines lines(rest.begin(), rest.end(), res);  // the lines left, from `at`
    usize at = 0;
    // the lines left that jump back to the label
    usize jumps = 0;
    for (Value x : lines) jumps += has_jump_to(x, id);
    // a branch spliced in front of the lines left (after the current line)
    auto splice = [&](Value branch) {
        Lines next(res);
        next.reserve(branch.size() + lines.size() - at);
        for (Value x : branch.args()) {
            next.push_back(x);
            jumps += has_jump_to(x, id);
        }
        next.insert(next.end(), lines.begin() + isize(at), lines.end());
        lines.swap(next);
        at = 0;
    };
    auto left = [&]() { return std::span<const Value>(lines.data() + at, lines.size() - at); };

    while (at < lines.size()) {
        poll();
        const Value line = lines[at++];
        if (has_jump_to(line, id)) --jumps;
        if (!line.is_expr()) {
            path.push_back(line);
            continue;
        }
        switch (line.op()) {
            case Op::IF:
            case Op::MERGED_IF: {
                const Value c = line[0], t = line[1], e = line[2];
                // a branch that only ends (a revert): a check on the way
                // to the exit test, kept as it is
                if (is_check_branch(t)) {
                    Value r = mk(line.op(), c, t, mk_trace(std::span<const Value>()));
                    cx().pcs.inherit(r, line);
                    checks.push_back(path.size());
                    path.push_back(r);
                    splice(e);
                    continue;
                }
                if (is_check_branch(e)) {
                    Value r = mk(line.op(), alg::iszero(c), e, mk_trace(std::span<const Value>()));
                    cx().pcs.inherit(r, line);
                    checks.push_back(path.size());
                    path.push_back(r);
                    splice(t);
                    continue;
                }
                const bool jt = has_jump_to(t, id), je = has_jump_to(e, id);
                const bool more = at < lines.size();
                if (more && (jt || je) && jumps == 0) {
                    // The branches go on after the IF, and the loop doesn't:
                    // what follows the IF is where the loop is left for (by
                    // its exit test, a break...). The IF is the loop's last
                    // line.
                    if (opts_.exit_test && jt != je) {
                        const Value body = jt ? t : e, out = jt ? e : t;
                        const Value cond = jt ? c : alg::iszero(c);
                        Value body2;
                        Lines after2(res);
                        if (exit_values(out, body, left(), lb, body2, after2) && rotates(path, body2, lb)) {
                            Lines before(res);
                            substituted(path, lb, lb.setvars, before);
                            m.before.swap(before);
                            m.body = add_path(body2, path, lb);
                            m.remaining.swap(after2);
                            m.cond = cond;
                            m.renamed = body2 != body;
                            return;
                        }
                        if (!falls_through(body) && rotates(path, body, lb)) {
                            // no break: the exit branch runs after the loop
                            Lines before(res);
                            substituted(path, lb, lb.setvars, before);
                            m.before.swap(before);
                            m.body = add_path(body, path, lb);
                            m.remaining.assign(out.args().begin(), out.args().end());
                            m.remaining.insert(m.remaining.end(), left().begin(), left().end());
                            m.cond = cond;
                            m.exit_after = out.size() != 0;
                            return;
                        }
                    }
                    path.push_back(line);
                    as_while_true(m, path, left());
                    return;
                }
                if (more || (!jt && !je)) {
                    // a line of the body (its gotos continues), not the exit
                    // test, the last thing on the loop's path
                    path.push_back(line);
                    continue;
                }
                // the IF is the last line of the loop
                if (opts_.exit_test && jt != je) {
                    const Value body = jt ? t : e, out = jt ? e : t;
                    // a path of the body that falls off it goes on after the
                    // IF (the loop's end), not with the exit branch: unless
                    // that's nothing
                    if ((out.size() == 0 || !falls_through(body)) && rotates(path, body, lb)) {
                        Lines before(res);
                        substituted(path, lb, lb.setvars, before);
                        m.before.swap(before);
                        m.body = add_path(body, path, lb);
                        m.remaining.assign(out.args().begin(), out.args().end());
                        m.cond = jt ? c : alg::iszero(c);
                        m.exit_after = out.size() != 0;
                        return;
                    }
                }
                path.push_back(line);
                if (check_exit(path, checks, lb, m)) return;
                as_while_true(m, path, {});
                return;
            }
            case Op::GOTO:
            case Op::CONTINUE:
                if (line[0] == id) {
                    // the path loops back whatever happens: the loop as it is
                    // (what follows the goto never runs: left where it is)
                    path.push_back(line);
                    path.insert(path.end(), left().begin(), left().end());
                    if (check_exit(path, checks, lb, m)) return;
                    as_while_true(m, path, {});
                    return;
                }
                path.push_back(line);
                continue;
            case Op::LABEL:
                // a loop in this one before its exit test (Vyper tests it at
                // the end): the rest is that loop and what follows it, where
                // this one goes on or ends
                path.push_back(line);
                path.insert(path.end(), left().begin(), left().end());
                as_while_true(m, path, {});
                return;
            default: path.push_back(line); continue;
        }
    }
    // nothing jumps back to the label: the lines run once
    bool plain = true;
    for (Value s : lb.starts)
        if (reads_any(s, std::span<const Value>(lb.names.data(), lb.names.size()))) plain = false;
    if (plain) {
        m.before.clear();
        m.body = trace_of(std::span<const Value>(path.data(), path.size()));
        m.remaining.clear();
        m.loop = false;
        return;
    }
    as_while_true(m, path, {});
}

// python exit_values: `out`, the exit branch, made nothing - the variables
// it sets that `after` reads renamed the loop variables it sets them to, in
// the body and after
bool Whiles::exit_values(Value out, Value body, std::span<const Value> after, const Label& lb, Value& body2,
                         Lines& after2) {
    const Value after_t = trace_of(after);
    Renamer ren;
    SmallVec<Value, 8> from, to, group;
    for (Value l : out.args()) {
        if (!l.is(Op::SETVAR, 2)) return false;
        const Value name = l[0], value = l[1];
        group.push_back(name);
        if (!reads_name(after_t, name)) continue;  // (nobody reads what it sets)
        if (!value.is_name(NameKind::LOOP)) return false;
        if (std::find(lb.names.begin(), lb.names.end(), value) == lb.names.end()) return false;
        if (std::find(to.begin(), to.end(), value) != to.end()) return false;
        if (std::find(from.begin(), from.end(), name) != from.end()) return false;
        if (reads_name(after_t, value) || sets_name(after_t, value)) return false;
        ren.add(name, value);
        from.push_back(name);
        to.push_back(value);
    }
    if (ren.empty()) {
        body2 = body;
        after2.assign(after.begin(), after.end());
        return true;
    }
    // the body sets the renamed variables only at the end of its breaks
    // (the merge's setvars: nothing but such setvars after them until the
    // body's end), and none of those setvars reads another one's new name
    // (they run one after the other: a swap would read it set)
    if (!break_setvars(body, true, std::span<const Value>(from.data(), from.size()),
                       std::span<const Value>(to.data(), to.size()),
                       std::span<const Value>(group.data(), group.size())))
        return false;
    body2 = ren(body);
    const Value a2 = ren(after_t);
    after2.assign(a2.args().begin(), a2.args().end());
    return true;
}

// In trace (a part of the body: `tail` says whether falling off its end
// goes on to the body's end through nothing but setvars of the merge's
// variables - `group`, those the exit branch sets), every line setting a
// name of `from` is a SETVAR followed by nothing but such setvars to the
// body's end, its value reading no other name of `to` (the group's others
// that `after` doesn't read: dead, whatever they read).
bool Whiles::break_setvars(Value trace, bool tail, std::span<const Value> from, std::span<const Value> to,
                           std::span<const Value> group) {
    if (!trace.is_list()) return true;
    check_stack();
    const u32 n = trace.size();
    auto is_from_setvar = [&](Value l) {
        return l.is(Op::SETVAR, 2) && std::find(group.begin(), group.end(), l[0]) != group.end();
    };
    // ok[i]: the lines from i on are such setvars
    SmallVec<u8, 32> ok;
    ok.resize(usize(n) + 1);
    ok[usize(n)] = 1;
    for (u32 i = n; i-- > 0;) ok[i] = ok[i + 1] && is_from_setvar(trace[i]);
    for (u32 i = 0; i < n; ++i) {
        poll();
        const Value l = trace[i];
        const bool t = tail && ok[i + 1];
        if (l.is(Op::SETVAR, 2)) {
            auto it = std::find(from.begin(), from.end(), l[0]);
            if (it == from.end()) continue;
            if (!t) return false;
            const usize k = usize(it - from.begin());
            for (usize j = 0; j < to.size(); ++j)
                if (j != k && reads_name(l[1], to[j])) return false;
            continue;
        }
        if (l.is(Op::IF, 3) || l.is(Op::MERGED_IF, 3)) {
            if (!break_setvars(l[1], t, from, to, group) || !break_setvars(l[2], t, from, to, group)) return false;
            continue;
        }
        for (Value name : from)
            if (sets_name(l, name)) return false;
    }
    return true;
}

// the GOTO / CONTINUE lines of the loop in v (any depth)
void Whiles::gotos(Value v, Value id, SmallVec<Value, 8>& out) {
    if (!has_jump_to(v, id)) return;
    check_stack();
    if (v.is_list()) {
        for (Value l : v.args()) gotos(l, id, out);
        return;
    }
    if ((v.is(Op::GOTO) || v.is(Op::CONTINUE)) && v[0] == id) {
        if (std::find(out.begin(), out.end(), v) == out.end()) out.push_back(v);
        return;
    }
    for (Value a : v.args())
        if (a.is_list()) gotos(a, id, out);
}

// the path with the loop's variables replaced by the values of setvars (all at once)
void Whiles::substituted(const Lines& path, const Label& lb, Value setvars, Lines& out) {
    out.clear();
    if (path.empty()) return;
    Subst s;
    for (const Value& name : lb.names) {
        Value v = setvar_of(setvars, name);
        // (a variable a GOTO leaves as it is keeps its value)
        if (!v.nil()) s.add(name, v);
    }
    for (Value l : path) out.push_back(s(l));
}

// no line changes what a value of setvars reads (they are the same
// evaluated after the lines)
bool Whiles::independent(const Lines& lines, Value setvars) {
    SmallVec<Value, 8> vals;
    setvar_values(setvars, vals);
    for (Value l : lines)
        for (Value v : vals)
            if (simplify::affects(l, v)) return false;
    return true;
}

// python rotates: the lines before the exit test can run before the loop
// with its start values, and before each CONTINUE with the next ones
bool Whiles::rotates(const Lines& path, Value body, const Label& lb) {
    if (path.empty()) return true;
    if (!opts_.rotate) return false;
    std::pmr::memory_resource* res = cx().budget.resource();
    const Value pt = trace_of(std::span<const Value>(path.data(), path.size()));
    if (pt.has_flags(F_LOOPCTL)) return false;  // a jump, a loop: not copied
    // (a call in it: copied with its id, as python did - each run of a copy
    // is the call's latest, as each run of it was)
    for (Value name : lb.names)
        if (sets_name(pt, name)) return false;
    SmallVec<Value, 8> gs;
    gotos(body, lb.id, gs);
    if (u64(node_count(pt, kMaxRotation)) * (gs.size() + 1) > kMaxRotation) return false;
    Lines sub(res);
    substituted(path, lb, lb.setvars, sub);
    if (!independent(sub, lb.setvars)) return false;
    for (Value g : gs) {
        substituted(path, lb, g[1], sub);
        if (!independent(sub, g[1])) return false;
    }
    return true;
}

// python add_path: each GOTO of the loop in trace preceded by the path, the
// loop's variables replaced by the GOTO's values
Value Whiles::add_path(Value trace, const Lines& path, const Label& lb) {
    if (path.empty() || !trace.is_list() || !has_jump_to(trace, lb.id)) return trace;
    check_stack();
    std::pmr::memory_resource* res = cx().budget.resource();
    Lines out(res), sub(res);
    for (Value l : trace.args()) {
        poll();
        if (!l.is_expr() || !has_jump_to(l, lb.id)) {
            out.push_back(l);
            continue;
        }
        switch (l.op()) {
            case Op::GOTO:
            case Op::CONTINUE:
                substituted(path, lb, l[1], sub);
                out.insert(out.end(), sub.begin(), sub.end());
                out.push_back(l);
                break;
            case Op::IF:
            case Op::MERGED_IF: {
                Value r = mk_like(l, std::span<const Value>({l[0], add_path(l[1], path, lb), add_path(l[2], path, lb)}));
                cx().pcs.inherit(r, l);
                out.push_back(r);
                break;
            }
            case Op::WHILE: {
                Value r = mk(Op::WHILE, l[0], add_path(l[1], path, lb), l[2], l[3]);
                cx().pcs.inherit(r, l);
                out.push_back(r);
                break;
            }
            default: out.push_back(l); break;
        }
    }
    return trace_of(std::span<const Value>(out.data(), out.size()));
}

}  // namespace

WhilesStats& whiles_stats() noexcept {
    static thread_local WhilesStats s;
    return s;
}

Value make_whiles(Value trace, std::vector<LoopInfo>& loops, const WhilesOptions& opts) {
    if (!trace.is_list() || !trace.has_flags(F_LOOPCTL)) return trace;
    Whiles w(opts);
    Value r = w.make(trace);
    if (!w.gone.empty())
        std::erase_if(loops, [&](const LoopInfo& li) {
            return std::find(w.gone.begin(), w.gone.end(), Value::name(NameKind::LOOP_ID, li.id)) != w.gone.end();
        });
    return r;
}

void whiles_function(FunctionInfo& fn, const WhilesOptions& opts) {
    fn.trace = make_whiles(fn.trace, fn.loops, opts);
}

void whiles_stage(const std::vector<FunctionInfo>& in, std::vector<FunctionInfo>& out, const WhilesOptions& opts) {
    out = in;
    for (FunctionInfo& f : out) {
        if (f.problem || f.trace.nil()) continue;
        try {
            whiles_function(f, opts);
        } catch (const Error&) {
            f.trace = Value();
            f.problem = 0;
        }
    }
}

}  // namespace pan::loops
