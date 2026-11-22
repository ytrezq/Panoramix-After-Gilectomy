// cleanup_vars (python simplify.cleanup_vars / replace_var, asm
// simplify_vars.s), as two walks of the structured trace instead of a
// rewrite of the rest of the trace per variable:
//
//  1. forward, with an environment: what each variable is known to hold at
//     this point (its value, an expression to evaluate here instead) - a
//     SETVAR's value (not past MAX_EXP_SIZE, not reading the variable
//     itself), dropped where a line may change what the value reads or sets
//     the variable again (effects.hpp); the expressions read with the
//     variables known replaced (python replace_var). An IF: each branch from
//     the environment before it, after it what the branches that go on
//     agree on; a WHILE: inside it and after it, what the loop changes
//     nowhere; a LABEL (raw traces): from it on, what the lines after it
//     (run again by a GOTO) change nowhere.
//  2. backward, the variables live (read later on some path): a SETVAR of a
//     variable no one reads after it dropped (python: kept only while the
//     rest of the trace mentions it). Loops: at a CONTINUE / GOTO, every
//     variable the loop reads anywhere is live. The reads are counted
//     exactly: where a summary's list of variables was capped, its parts'.
//
// Sound by construction: a value replaces a variable only where the SETVAR
// is the one that set it on every path, and nothing between changed what the
// value reads.
#include "simplify/effects.hpp"
#include "simplify/floor.hpp"
#include "simplify/internal.hpp"
#include "simplify/simplify.hpp"

#include <algorithm>
#include <functional>
#include <memory_resource>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include "algebra/construct.hpp"
#include "algebra/facts.hpp"
#include "algebra/linear.hpp"
#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/memo.hpp"
#include "loops/loops.hpp"

namespace pan::simplify {

namespace {

bool is_var(Value v) {
    if (!v.is_name()) return false;
    switch (v.name_kind()) {
        case NameKind::TMP:
        case NameKind::LOOP:
        case NameKind::MSIZE_VAR:
        case NameKind::PRECOMPILE:
        case NameKind::SAFEMATH_PARAM: return true;
        default: return false;
    }
}

// ---- the environment ------------------------------------------------------------------

struct Entry {
    Value name, value;
    u32 reads;           // summary(value).reads: a quick test before affects()
    bool named = false;  // the variable keeps its name (named_value): its value isn't put in its place
};

class Env {
public:
    explicit Env(std::pmr::memory_resource* r) : e_(r) {}
    Env(const Env& o) : e_(o.e_, o.e_.get_allocator()), any_named_(o.any_named_) {}
    Env& operator=(const Env& o) {
        e_.assign(o.e_.begin(), o.e_.end());
        any_named_ = o.any_named_;
        return *this;
    }

    // the value that stands for the variable (none for a named one)
    const Value* find(Value name) const {
        auto it = lower(name);
        return it != e_.end() && it->name == name && !it->named ? &it->value : nullptr;
    }
    void set(Value name, Value value, bool named = false) {
        auto it = lower(name);
        const u32 reads = summary(value).reads;
        if (it != e_.end() && it->name == name)
            *it = Entry{name, value, reads, named};
        else
            e_.insert(it, Entry{name, value, reads, named});
        any_named_ = any_named_ || named;
    }
    // the named variables known here (their values)
    template <class F>
    void each_named(F&& f) const {
        if (!any_named_) return;
        for (const Entry& x : e_)
            if (x.named) f(x.name, x.value);
    }
    void erase(Value name) {
        auto it = lower(name);
        if (it != e_.end() && it->name == name) e_.erase(it);
    }
    // the entries a line (its summary) may make wrong: the variables it sets,
    // the values whose reads it may change (the memory decided with the
    // floors that hold where the line's writes are: simplify/floor.hpp)
    void kill(const EffectSummary& s, const alg::Facts* floors = nullptr) {
        if (!s.writes || e_.empty()) return;
        std::erase_if(e_, [&](const Entry& x) {
            if (s.writes & S_VARS) {
                if (s.writes_any & S_VARS) return true;
                if (!s.var_writes.nil())
                    for (Value w : s.var_writes.args())
                        if (w == x.name) return true;
            }
            if (!(s.writes & x.reads)) return false;
            return changes(s, summary(x.value), floors);
        });
    }
    // what both say
    void meet(const Env& o) {
        std::erase_if(e_, [&](const Entry& x) {
            auto it = o.lower(x.name);
            return it == o.e_.end() || it->name != x.name || it->value != x.value || it->named != x.named;
        });
    }
    bool empty() const { return e_.empty(); }
    void clear() { e_.clear(); }

private:
    std::pmr::vector<Entry>::iterator lower(Value name) {
        return std::lower_bound(e_.begin(), e_.end(), name,
                                [](const Entry& a, Value n) { return a.name.raw() < n.raw(); });
    }
    std::pmr::vector<Entry>::const_iterator lower(Value name) const {
        return std::lower_bound(e_.begin(), e_.end(), name,
                                [](const Entry& a, Value n) { return a.name.raw() < n.raw(); });
    }
    std::pmr::vector<Entry> e_;
    bool any_named_ = false;  // (a named entry was set: each_named has something to see)
};

// ---- the values that keep their variable's name ---------------------------------------------

// a term rounded to whole words (ceil32, floor32: a mask clearing the low 5 bits)
bool rounded_term(Value t) { return t.is(Op::MASK_SHL, 4) && t[1] == Value::small(5); }

// a term of a sum of positions: a name, a leaf (return_data.size...), a read
// of memory, calldata or storage (a length), a mask of one (ceil32...) - not
// a product of words (arithmetic)
bool position_term(Value t) {
    return t.is_name() || t.is_leaf() || t.is(Op::MEM) || t.is(Op::CALLDATALOAD) || t.is(Op::STORAGE) ||
           t.is(Op::MASK_SHL);
}

// A sum of positions long enough that a variable set to it reads better as
// its name than as the sum written out wherever it is read: three terms or
// more, two of them rounded to words, or five - the base of a buffer the
// code allocated past others (ceil32(len_1) + ceil32(len_2) + 32 * n + 192).
bool long_sum(Value v) {
    if (!v.is(Op::ADD)) return false;
    const alg::Linear l = alg::linear(v);
    u32 rounded = 0;
    for (const alg::LinTerm& t : l.terms) {
        if (!position_term(t.term)) return false;
        rounded += rounded_term(t.term);
    }
    return l.terms.size() >= 3 && (rounded >= 2 || l.terms.size() >= 5);
}

// v reads memory at a place that isn't a constant (an allocated buffer's)
bool reads_buffer(Value v) {
    if (!(v.is_expr() || v.is_list()) || !v.has_flags(F_MEM)) return false;
    if (v.is(Op::MEM, 1) && !(v[0].is(Op::RANGE, 2) && v[0][0].is_small())) return true;
    for (Value a : v.args())
        if (reads_buffer(a)) return true;
    return false;
}

// The part of a sum of n terms that a variable names (naming): a long sum,
// or, where the sum had terms left out (a loop's counter: read where it is),
// two terms or more, one of them rounded - what the lines that read it
// repeat around those terms
bool base_sum(Value b, usize n) {
    if (long_sum(b)) return true;
    if (!b.is(Op::ADD)) return false;
    const alg::Linear l = alg::linear(b);
    if (l.terms.size() < 2 || l.terms.size() >= n) return false;
    u32 rounded = 0;
    for (const alg::LinTerm& t : l.terms) {
        if (!position_term(t.term)) return false;
        rounded += rounded_term(t.term);
    }
    return rounded >= 1;
}

// v hashes memory the trace doesn't know: the hash keeps its variable's
// name, not written out wherever it is read. buffer: only a buffer's
// (sha3(mem[p len n]), p not a constant) - the rounds' (the scratch words a
// mapping's slot is hashed from are the memory pass's to read as the key and
// the slot: named while they aren't, a slot's variable would stay where
// they are later); else any (the final naming: what is left unread)
bool raw_hash(Value v, bool buffer = false) {
    if (!(v.is_expr() || v.is_list()) || !v.has_flags(F_MEM)) return false;
    if (v.is(Op::SHA3))
        for (Value a : v.args())
            if (buffer ? reads_buffer(a) : a.has_flags(F_MEM)) return true;
    for (Value a : v.args())
        if (raw_hash(a, buffer)) return true;
    return false;
}

// a read of the word at a constant address (the free memory pointer...)
bool word_read(Value v) {
    return v.is(Op::MEM, 1) && v[0].is(Op::RANGE, 2) && v[0][0].is_small() && v[0][1] == Value::small(32);
}

// a variable set to v keeps its name: v isn't put where it is read (naming:
// a read of the word at a constant address too - where the variable holds
// it, `_45` for `mem[64]`: the buffer's base named as the code took it)
bool named_value(Value v) { return long_sum(v) || raw_hash(v) || word_read(v); }

// ---- forward: substitution ----------------------------------------------------------------

// the reads of each variable of the trace (its SETVARs' own names not ones)
void count_all_reads(Value v, std::unordered_map<u64, u32>& n) {
    if (v.is_name()) {
        ++n[v.raw()];
        return;
    }
    if (!(v.is_expr() || v.is_list()) || !v.has_flags(F_VAR)) return;
    if (v.is(Op::SETVAR, 2)) {
        count_all_reads(v[1], n);
        return;
    }
    for (Value a : v.args()) count_all_reads(a, n);
}

class Forward {
public:
    explicit Forward(std::pmr::memory_resource* r) : res_(r) {}

    // naming mode (name_values): the long sums of positions and the hashes of
    // memory a line reads get a variable set right before it, read there and
    // wherever it still holds that value after (`fresh`: the next unused name)
    bool naming = false;
    std::function<Value()> fresh;
    SmallVec<Value, 16> made;  // (the variables naming made)
    // the variables read twice or more in the trace (named_hash)
    std::unordered_map<u64, u32> reads;

    // the trace with the variables known replaced; env: at its end (the
    // paths that reach it); fl: the floors there (floor.hpp: the walk
    // carries them as the memory pass does)
    Value walk(Value trace, Env& env, alg::Facts& fl) {
        if (!trace.is_list()) return trace;
        check_stack();
        const u32 n = trace.size();
        SmallVec<Value, 32> out;
        bool changed = false;
        for (u32 i = 0; i < n; ++i) {
            poll();
            Value l = trace[i];
            SmallVec<Value, 4> before;
            Value r = line(l, env, fl, trace, i, before);
            if (r != l || !before.empty()) changed = true;
            for (Value b : before) out.push_back(b);
            out.push_back(r);
        }
        return changed ? mk_trace(out.span()) : trace;
    }

private:
    Value subst(Value e, const Env& env) {
        if (env.empty() || !e.has_flags(F_VAR)) return e;
        memo_.clear();
        return subst_rec(e, env);
    }
    Value subst_rec(Value e, const Env& env) {
        if (e.is_name()) {
            if (const Value* v = env.find(e)) return *v;
            return e;
        }
        if (!(e.is_expr() || e.is_list()) || !e.has_flags(F_VAR)) return e;
        if (const Value* r = memo_.find(e)) return *r;
        check_stack();
        SmallVec<Value, 8> args;
        bool changed = false;
        for (Value a : e.args()) {
            Value n = subst_rec(a, env);
            if (n != a) changed = true;
            args.push_back(n);
        }
        Value r = changed ? mk_like_checked(e, args.span()) : e;
        memo_.put(e, r);
        return r;
    }
    Value subst_line(Value l, const Env& env) {
        if (env.empty()) return l;
        return map_line_exprs(l, [&](Value e, Pos) { return put(e, env); });
    }

    // e with the variables known replaced by their values, and the values of
    // the named ones written as their names (named_value: where they hold
    // them - the same entries, killed as the others)
    Value put(Value e, const Env& env) {
        Value r = subst(e, env);
        bool any = false;
        env.each_named([&](Value, Value) { any = true; });
        if (!any || !(r.is_expr() || r.is_list())) return r;
        names_.clear();
        return named_rec(r, env);
    }
    Value named_rec(Value e, const Env& env) {
        if (!(e.is_expr() || e.is_list())) return e;
        if (const Value* r = names_.find(e)) return *r;
        check_stack();
        Value x = as_named(e, env);
        if (x.is_expr() || x.is_list()) {
            SmallVec<Value, 8> args;
            bool changed = false;
            for (Value a : x.args()) {
                Value n = named_rec(a, env);
                if (n != a) changed = true;
                args.push_back(n);
            }
            if (changed) x = mk_like_checked(x, args.span());
        }
        names_.put(e, x);
        return x;
    }
    // e as a named variable: its value itself, or a sum with all of that
    // value's terms, each with its coefficient - the variable plus the rest
    // (the value with the most terms); e itself when none
    static Value as_named(Value e, const Env& env) {
        Value name, value;
        usize most = 0;
        bool exact = false;
        std::optional<alg::Linear> le;
        env.each_named([&](Value n, Value v) {
            if (exact) return;
            if (v == e) {
                name = n;
                exact = true;
                return;
            }
            if (!e.is(Op::ADD) || !v.is(Op::ADD)) return;
            if (!le) le = alg::linear(e);
            const alg::Linear lv = alg::linear(v);
            if (lv.terms.size() <= most || lv.terms.size() > le->terms.size()) return;
            for (const alg::LinTerm& t : lv.terms)
                if (EvmInt(le->coeff_of(t.term)) != EvmInt(t.coeff)) return;
            name = n;
            value = v;
            most = lv.terms.size();
        });
        if (name.nil()) return e;
        if (exact) return name;
        return alg::add(name, alg::sub(e, value));
    }

    // naming: what e (an expression a line reads) has that a variable should
    // name - the part of a long sum of positions that the loops' counters
    // don't make (long_sum), a hash of memory the trace doesn't know
    // (raw_hash); not a storage slot's (the storage's forms read its sums)
    static void candidates(Value e, SmallVec<Value, 4>& out) {
        if (!(e.is_expr() || e.is_list()) || e.is(Op::STORAGE)) return;
        check_stack();
        if (e.is(Op::SHA3) && raw_hash(e)) {
            if (std::find(out.begin(), out.end(), e) == out.end()) out.push_back(e);
            return;
        }
        if (e.is(Op::ADD)) {
            const alg::Linear l = alg::linear(e);
            SmallVec<Value, 8> base;
            for (const alg::LinTerm& t : l.terms)
                if (!reads_loop_var(t.term)) base.push_back(alg::mul(t.coeff, t.term));
            if (base.size() >= 2) {
                const Value b = alg::add(base.span());
                if (base_sum(b, l.terms.size()) && std::find(out.begin(), out.end(), b) == out.end()) out.push_back(b);
            }
        }
        for (Value a : e.args()) candidates(a, out);
    }
    static bool reads_loop_var(Value v) {
        if (v.is_name(NameKind::LOOP)) return true;
        if (!(v.is_expr() || v.is_list()) || !v.has_flags(F_VAR)) return false;
        for (Value a : v.args())
            if (reads_loop_var(a)) return true;
        return false;
    }
    // naming: e's candidates named by variables set before the line (the
    // same value there: what the line reads is read before its effects)
    void name_in(Value e, Env& env, SmallVec<Value, 4>& before) {
        SmallVec<Value, 4> cs;
        candidates(e, cs);
        for (Value c : cs) {
            if (!movable(Value(), c)) continue;
            const Value k = fresh();
            made.push_back(k);
            const Value sv = mk(Op::SETVAR, k, c);
            before.push_back(sv);
            env.set(k, c, true);
        }
    }
    Value name_line(Value l, Env& env, SmallVec<Value, 4>& before) {
        if (!naming || !l.is_expr()) return l;
        const usize n0 = before.size();
        if (l.is(Op::STORE, 4)) {
            name_in(l[3], env, before);
        } else if (l.is(Op::SETVAR, 2)) {
            // (a variable set to such a value is its name already)
            if (!named_value(l[1])) name_in(l[1], env, before);
        } else {
            (void)map_line_exprs(l, [&](Value e, Pos) {
                name_in(e, env, before);
                return e;
            });
        }
        if (before.size() == n0) return l;
        Value r = subst_line(l, env);
        if (r != l) cx().pcs.inherit(r, l);
        for (usize j = n0; j < before.size(); ++j) cx().pcs.inherit(before[j], l);
        return r;
    }

    // a line, env going forward through it
    Value line(Value l, Env& env, alg::Facts& fl, Value trace, u32 i, SmallVec<Value, 4>& before) {
        if (!l.is_expr()) return l;
        switch (l.op()) {
            case Op::IF:
            case Op::MERGED_IF: {
                Value cond = put(l[0], env);
                if (naming && cond != l[0]) cond = simplify_word(cond);
                if (naming) {
                    const usize n0 = before.size();
                    name_in(cond, env, before);
                    if (before.size() != n0) cond = simplify_word(put(cond, env));
                }
                Env et(env), ee(env);
                alg::Facts ft = fl, fe = fl;
                Value t = walk(l[1], et, ft);
                Value e = l.size() > 2 ? walk(l[2], ee, fe) : Value();
                const bool t_ends = ends(t), e_ends = e.nil() ? false : ends(e);
                if (t_ends && !e_ends) {
                    env = ee;
                    fl = fe;
                } else if (e_ends && !t_ends) {
                    env = et;
                    fl = ft;
                } else if (!t_ends && !e_ends) {
                    et.meet(ee);
                    env = et;
                    fl = floor_join(fl, fl, ft, fe);
                }
                // (both end: nothing after it runs)
                SmallVec<Value, 3> a{cond, t};
                if (l.size() > 2) a.push_back(e);
                Value r = mk_like(l, a.span());
                cx().pcs.inherit(r, l);
                return r;
            }
            case Op::WHILE: {
                // the setvars: at the entry, from env
                Value sv = subst_setvars(l[3], env);
                if (naming && sv.is_list()) {
                    const usize n0 = before.size();
                    for (Value x : sv.args())
                        if (x.is(Op::SETVAR, 2)) name_in(x[1], env, before);
                    if (before.size() != n0) sv = subst_setvars(sv, env);
                }
                // (at its head, for every iteration, and after it: what the
                // paths that go on change - an iteration that reverts never
                // gets back -, decided with the floors none of them changes;
                // the paths that end walked in the body, line by line)
                const EffectSummary& s = loops::summary(l).cont_effects;
                const alg::Facts in = floor_loop_inside(fl, l);
                fl = floor_loop(fl, l);
                env.kill(s, &in);
                Env inside(env);
                alg::Facts fin = fl;
                Value cond = put(l[0], inside);
                if (naming && cond != l[0]) cond = simplify_word(cond);
                Value body = walk(l[1], inside, fin);
                Value r = mk(Op::WHILE, cond, body, l[2], sv);
                cx().pcs.inherit(r, l);
                // after it, the loop's variables' last values when lot 6
                // proves them (made of what the loop doesn't change)
                if (auto ind = loops::induction(l); ind && ind->endvars.is_list())
                    for (Value e : ind->endvars.args())
                        if (e.is(Op::SETVAR, 2) && is_var(e[0]) && !changes(s, summary(e[1]), &in) && movable(e[0], e[1]))
                            env.set(e[0], e[1]);
                return r;
            }
            case Op::LABEL: {
                Value sv = subst_setvars(l[1], env);
                fl = fl.without_floors();
                env.kill(summary(l));
                // what the lines after it (run again from it) change
                EffectSummary rest;
                for (u32 j = i + 1; j < trace.size(); ++j) rest = combine(rest, summary(trace[j]), true);
                rest.control &= ~C_ENDS;
                env.kill(rest);
                Value r = sv == l[1] ? l : mk(Op::LABEL, l[0], sv);
                cx().pcs.inherit(r, l);
                return r;
            }
            case Op::LOOP_PATH: {
                fl = fl.without_floors();
                Env inside(env);
                inside.kill(summary(l));
                alg::Facts fin;
                Value t = walk(l[0], inside, fin);
                env.kill(summary(l));
                return t == l[0] ? l : mk(Op::LOOP_PATH, t, l[1]);
            }
            default: break;
        }
        Value r = subst_line(l, env);
        if (naming && r != l) {
            // (a name in a sum's place: the normal form again)
            const Value q = simplify_line(r);
            if (!q.nil()) r = q;
        }
        if (r != l) cx().pcs.inherit(r, l);
        r = name_line(r, env, before);
        {
            // (what it writes, decided with the floors before it - its own
            // writes evaluated there; floors_through for a compound line)
            const alg::Facts through = floors_through(fl, r);
            env.kill(summary(r), &through);
        }
        fl = floor_transfer(fl, r);
        if (r.is(Op::SETVAR, 2) && is_var(r[0]) && movable(r[0], r[1]))
            env.set(r[0], r[1], named_hash(r[0], r[1]) || (naming && named_value(r[1])));
        return r;
    }

    // a variable set to a hash of memory the trace doesn't know, read twice
    // or more: its name, not the hash written out wherever it is read
    bool named_hash(Value name, Value v) const {
        if (!raw_hash(v, true)) return false;
        auto it = reads.find(name.raw());
        return it != reads.end() && it->second >= 2;
    }

    // v's value may stand for it where it's read: not reading v itself, not
    // past MAX_EXP_SIZE, nothing that may fail, no memory moved where msize
    // is read, no read of the gas left (the read is where the code reads it,
    // its variable read wherever its value is used: lot 10 puts it in the
    // one line that uses it right after it)
    static bool movable(Value name, Value v) {
        const EffectSummary& vs = summary(v);
        if (vs.reads & S_GAS) return false;
        if (vs.reads & S_VARS) {
            if (vs.reads_any & S_VARS) return false;
            if (!vs.var_reads.nil())
                for (Value x : vs.var_reads.args())
                    if (x == name) return false;
        }
        if (run_flags().msize && (vs.reads & (S_MEM | S_MSIZE))) return false;
        if (vs.control & C_FAILS) return false;
        return exp_size(v, limits::MAX_EXP_SIZE) <= limits::MAX_EXP_SIZE;
    }

    Value subst_setvars(Value sv, const Env& env) {
        if (!sv.is_list() || env.empty()) return sv;
        SmallVec<Value, 8> items;
        bool changed = false;
        for (Value x : sv.args()) {
            Value y = x;
            if (x.is(Op::SETVAR, 2)) {
                Value e = put(x[1], env);
                if (naming && e != x[1]) e = simplify_word(e);
                if (e != x[1]) y = mk(Op::SETVAR, x[0], e);
            }
            if (y != x) changed = true;
            items.push_back(y);
        }
        return changed ? mk_like(sv, items.span()) : sv;
    }

    std::pmr::memory_resource* res_;
    Memo<Value, Value> memo_, names_;
};

// ---- backward: liveness -----------------------------------------------------------------

// a set of variables: a bit per variable met (dense ids), or all of them
class Live {
public:
    bool all = false;
    std::vector<u64> bits;

    bool has(u32 i) const { return all || (i / 64 < bits.size() && (bits[i / 64] >> (i % 64) & 1)); }
    void add(u32 i) {
        if (i / 64 >= bits.size()) bits.resize(i / 64 + 1, 0);
        bits[i / 64] |= u64(1) << (i % 64);
    }
    void remove(u32 i) {
        if (all) return;  // (all: can't say which others)
        if (i / 64 < bits.size()) bits[i / 64] &= ~(u64(1) << (i % 64));
    }
    void unite(const Live& o) {
        all = all || o.all;
        if (o.bits.size() > bits.size()) bits.resize(o.bits.size(), 0);
        for (usize k = 0; k < o.bits.size(); ++k) bits[k] |= o.bits[k];
    }
};

class Backward {
public:
    // the trace with the dead SETVARs dropped; live: what's live after it
    // in, what's live before it out
    Value walk(Value trace, Live& live) {
        if (!trace.is_list()) return trace;
        check_stack();
        const u32 n = trace.size();
        // the LABELs of this trace: what the lines after each read, live at its GOTOs
        usize labels_mark = loops_.size();
        for (u32 i = 0; i < n; ++i) {
            Value l = trace[i];
            if (l.is(Op::LABEL, 2)) {
                Live head = live;
                for (u32 j = i + 1; j < n; ++j) add_reads_all(trace[j], head);
                loops_.push_back({l[0], std::move(head)});
            }
        }
        SmallVec<Value, 32> out;
        for (u32 i = 0; i < n; ++i) out.push_back(Value());
        u32 kept = n;
        bool changed = false;
        for (u32 i = n; i-- > 0;) {
            poll();
            Value l = trace[i];
            Value r = line(l, live);
            if (r != l) changed = true;
            if (r.nil()) {
                --kept;
                out[i] = Value();
            } else {
                out[i] = r;
            }
        }
        loops_.resize(labels_mark);
        if (!changed) return trace;
        SmallVec<Value, 32> lines;
        for (u32 i = 0; i < n; ++i)
            if (!out[i].nil()) lines.push_back(out[i]);
        (void)kept;
        return mk_trace(lines.span());
    }

private:
    struct Loop {
        Value id;
        Live head;  // live at the loop's head (a CONTINUE / GOTO goes there)
    };

    u32 index(Value name) {
        bool ins = false;
        u32& slot = ids_.slot(name, &ins);
        if (ins) slot = next_++;
        return slot;
    }
    void add_reads(const EffectSummary& s, Live& live) {
        if (!(s.reads & S_VARS)) return;
        if (s.reads_any & S_VARS) {
            live.all = true;
            return;
        }
        if (!s.var_reads.nil())
            for (Value v : s.var_reads.args()) live.add(index(v));
    }
    // every variable v reads anywhere in it (lines, nested traces) - the
    // summary's list, or where that list was capped (past kMaxPlaces a
    // summary reads variables "anywhere": a loop of 53 variables, a big
    // branch) its parts', down to those whose list is whole: exact, as only
    // the cap makes a summary read variables anywhere (a SETVAR's target, a
    // precompile's or an internal call's results are no reads)
    void add_reads_all(Value v, Live& live) {
        const EffectSummary& s = summary(v);
        if (!(s.reads & S_VARS)) return;
        if (!(s.reads_any & S_VARS)) {
            add_reads(s, live);
            return;
        }
        MemoSet<Value> seen;
        add_reads_parts(v, live, seen);
    }
    void add_reads_parts(Value v, Live& live, MemoSet<Value>& seen) {
        const EffectSummary& s = summary(v);
        if (!(s.reads & S_VARS)) return;
        if (!(s.reads_any & S_VARS) || !(v.is_expr() || v.is_list())) {
            add_reads(s, live);
            return;
        }
        if (!seen.add(v)) return;
        check_stack();
        for (u32 i = 0; i < v.size(); ++i) {
            if (v.is_expr() && is_target(v, i)) continue;
            add_reads_parts(v[i], live, seen);
        }
    }
    static bool is_target(Value line, u32 i) {
        switch (line.op()) {
            case Op::SETVAR: return i == 0;
            case Op::PRECOMPILED: return i == 1;
            case Op::INTERNAL: return i == 2;
            default: return false;
        }
    }
    void kill_writes(const EffectSummary& s, Live& live) {
        if (!(s.writes & S_VARS) || (s.writes_any & S_VARS)) return;
        if (!s.var_writes.nil())
            for (Value v : s.var_writes.args()) live.remove(index(v));
    }
    const Live* loop_head(Value id) const {
        for (usize k = loops_.size(); k-- > 0;)
            if (loops_[k].id == id) return &loops_[k].head;
        return nullptr;
    }
    // the reads of the values of a LIST of SETVARs, the variables it sets killed
    void setvars(Value sv, Live& live) {
        if (!sv.is_list()) return;
        for (Value x : sv.args())
            if (x.is(Op::SETVAR, 2)) live.remove(index(x[0]));
        for (Value x : sv.args())
            if (x.is(Op::SETVAR, 2)) add_reads_all(x[1], live);
    }

    Value line(Value l, Live& live) {
        if (!l.is_expr()) return l;
        switch (l.op()) {
            case Op::SETVAR: {
                if (is_var(l[0]) && !live.has(index(l[0]))) {
                    const EffectSummary& vs = summary(l[1]);
                    // (where msize is read, a read of memory moves it; a
                    // read of msize itself changes nothing; a read of the
                    // gas left stays where the code reads it, read or not:
                    // every GAS instruction is a read of its own)
                    const bool droppable = !(vs.control & C_FAILS) && !(run_flags().msize && (vs.reads & S_MEM)) &&
                                           !(vs.reads & S_GAS);
                    if (droppable) return Value();
                }
                live.remove(index(l[0]));
                add_reads_all(l[1], live);
                return l;
            }
            case Op::IF:
            case Op::MERGED_IF: {
                Live lt = live, le = live;
                Value t = walk(l[1], lt);
                Value e = l.size() > 2 ? walk(l[2], le) : Value();
                live = lt;
                if (l.size() > 2) live.unite(le);
                add_reads_all(l[0], live);
                SmallVec<Value, 3> a{l[0], t};
                if (l.size() > 2) a.push_back(e);
                Value r = mk_like(l, a.span());
                cx().pcs.inherit(r, l);
                return r;
            }
            case Op::WHILE: {
                // at its head: what the loop reads anywhere, and what follows it
                Live head = live;
                add_reads_all(l, head);
                loops_.push_back({l[2], head});
                Live in_body = live;  // a body that ends without a continue leaves the loop
                Value body = walk(l[1], in_body);
                loops_.pop_back();
                live = head;
                live.unite(in_body);
                setvars(l[3], live);
                Value r = body == l[1] ? l : mk(Op::WHILE, l[0], body, l[2], l[3]);
                cx().pcs.inherit(r, l);
                return r;
            }
            case Op::CONTINUE:
            case Op::GOTO: {
                const Live* head = loop_head(l[0]);
                if (head) {
                    live = *head;
                } else {
                    live = Live{};
                    live.all = true;
                }
                setvars(l[1], live);
                return l;
            }
            case Op::LABEL: {
                if (const Live* head = loop_head(l[0])) live.unite(*head);
                setvars(l[1], live);
                return l;
            }
            case Op::LOOP_PATH: {
                Live head = live;
                add_reads_all(l, head);
                live = head;
                return l;
            }
            default: break;
        }
        const EffectSummary& s = summary(l);
        if (s.control & C_ENDS) live = Live{};
        kill_writes(s, live);
        add_reads_all(l, live);
        return l;
    }

    Memo<Value, u32> ids_;
    u32 next_ = 0;
    std::vector<Loop> loops_;
};

}  // namespace

Value cleanup_vars(Value trace) {
    if (!trace.is_list()) return trace;
    const FloorScope scope(trace);
    Env env(cx().budget.resource());
    Forward fw(cx().budget.resource());
    // (the floors from the lines before the trace: the dispatcher's)
    alg::Facts fl = run_flags().entry_lines.is_list() ? floor_walk(alg::Facts{}, run_flags().entry_lines) : alg::Facts{};
    count_all_reads(trace, fw.reads);
    Value t = fw.walk(trace, env, fl);
    Backward bw;
    Live live;
    return bw.walk(t, live);
}

namespace {

// the ids of the _N names v has
void tmp_ids(Value v, std::unordered_set<u32>& used, MemoSet<Value>& seen) {
    if (v.is_name(NameKind::TMP)) {
        used.insert(v.name_id());
        return;
    }
    if (!(v.is_expr() || v.is_list()) || !v.has_flags(F_VAR) || !seen.add(v)) return;
    for (Value a : v.args()) tmp_ids(a, used, seen);
}


// v with the names of `back` read as their values (in turn), their SETVARs dropped
Value put_back(Value v, const std::unordered_map<u64, Value>& back, Memo<Value, Value>& memo) {
    if (v.is_name(NameKind::TMP)) {
        if (auto it = back.find(v.raw()); it != back.end()) return put_back(it->second, back, memo);
        return v;
    }
    if (!(v.is_expr() || v.is_list()) || !v.has_flags(F_VAR)) return v;
    if (const Value* r = memo.find(v)) return *r;
    check_stack();
    SmallVec<Value, 16> args;
    bool changed = false;
    for (Value a : v.args()) {
        if (v.is_list() && a.is(Op::SETVAR, 2) && back.contains(a[0].raw())) {
            changed = true;
            continue;
        }
        Value n = put_back(a, back, memo);
        changed |= n != a;
        args.push_back(n);
    }
    Value r = !changed ? v : v.is_list() ? mk_list(args.span(), ListKind(v.node()->op)) : mk_like_checked(v, args.span());
    memo.put(v, r);
    return r;
}

}  // namespace

Value name_values(Value trace) {
    if (!trace.is_list()) return trace;
    const FloorScope scope(trace);
    // (the names made: none the trace or the entry lines have, nor one the
    // algebra has values of - the trace's as the run got it)
    std::unordered_set<u32> used(run_flags().installed_tmps.begin(), run_flags().installed_tmps.end());
    {
        MemoSet<Value> seen;
        tmp_ids(trace, used, seen);
        if (run_flags().entry_lines.is_list()) tmp_ids(run_flags().entry_lines, used, seen);
    }
    Env env(cx().budget.resource());
    Forward fw(cx().budget.resource());
    fw.naming = true;
    u32 next = 1;
    fw.fresh = [&] {
        while (used.contains(next)) ++next;
        used.insert(next);
        return Value::name(NameKind::TMP, next);
    };
    alg::Facts fl = run_flags().entry_lines.is_list() ? floor_walk(alg::Facts{}, run_flags().entry_lines) : alg::Facts{};
    count_all_reads(trace, fw.reads);
    Value t = fw.walk(trace, env, fl);
    if (fw.made.empty()) return t;
    // (a name read once or never: its value put back)
    std::unordered_map<u64, u32> reads;
    count_all_reads(t, reads);
    std::unordered_map<u64, Value> back;
    std::unordered_map<u64, Value> values;
    {
        // (the values of the names made: their SETVARs)
        SmallVec<Value, 64> st{t};
        MemoSet<Value> seen;
        while (!st.empty()) {
            Value x = st.back();
            st.pop_back();
            if (!(x.is_expr() || x.is_list()) || !seen.add(x)) continue;
            if (x.is(Op::SETVAR, 2)) values[x[0].raw()] = x[1];
            for (Value a : x.args()) st.push_back(a);
        }
    }
    for (Value k : fw.made)
        if (reads[k.raw()] < 2) back[k.raw()] = values[k.raw()];
    if (back.empty()) return t;
    Memo<Value, Value> memo;
    return put_back(t, back, memo);
}

}  // namespace pan::simplify
