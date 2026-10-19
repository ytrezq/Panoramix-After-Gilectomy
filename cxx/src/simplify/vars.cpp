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
//     variable the loop reads anywhere is live.
//
// Sound by construction: a value replaces a variable only where the SETVAR
// is the one that set it on every path, and nothing between changed what the
// value reads.
#include "simplify/effects.hpp"
#include "simplify/internal.hpp"
#include "simplify/simplify.hpp"

#include <algorithm>
#include <memory_resource>
#include <vector>

#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/memo.hpp"

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
    u32 reads;  // summary(value).reads: a quick test before affects()
};

class Env {
public:
    explicit Env(std::pmr::memory_resource* r) : e_(r) {}
    Env(const Env& o) : e_(o.e_, o.e_.get_allocator()) {}
    Env& operator=(const Env& o) {
        e_.assign(o.e_.begin(), o.e_.end());
        return *this;
    }

    const Value* find(Value name) const {
        auto it = lower(name);
        return it != e_.end() && it->name == name ? &it->value : nullptr;
    }
    void set(Value name, Value value) {
        auto it = lower(name);
        const u32 reads = summary(value).reads;
        if (it != e_.end() && it->name == name)
            *it = Entry{name, value, reads};
        else
            e_.insert(it, Entry{name, value, reads});
    }
    void erase(Value name) {
        auto it = lower(name);
        if (it != e_.end() && it->name == name) e_.erase(it);
    }
    // the entries a line (its summary) may make wrong: the variables it sets,
    // the values whose reads it may change
    void kill(const EffectSummary& s) {
        if (!s.writes || e_.empty()) return;
        std::erase_if(e_, [&](const Entry& x) {
            if (s.writes & S_VARS) {
                if (s.writes_any & S_VARS) return true;
                if (!s.var_writes.nil())
                    for (Value w : s.var_writes.args())
                        if (w == x.name) return true;
            }
            if (!(s.writes & x.reads)) return false;
            return changes(s, summary(x.value));
        });
    }
    // what both say
    void meet(const Env& o) {
        std::erase_if(e_, [&](const Entry& x) {
            const Value* v = o.find(x.name);
            return !v || *v != x.value;
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
};

// ---- forward: substitution ----------------------------------------------------------------

class Forward {
public:
    explicit Forward(std::pmr::memory_resource* r) : res_(r) {}

    // the trace with the variables known replaced; env: at its end (the
    // paths that reach it)
    Value walk(Value trace, Env& env) {
        if (!trace.is_list()) return trace;
        check_stack();
        const u32 n = trace.size();
        SmallVec<Value, 32> out;
        bool changed = false;
        for (u32 i = 0; i < n; ++i) {
            poll();
            Value l = trace[i];
            Value r = line(l, env, trace, i);
            if (r != l) changed = true;
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
        return map_line_exprs(l, [&](Value e, Pos) { return subst(e, env); });
    }

    // a line, env going forward through it
    Value line(Value l, Env& env, Value trace, u32 i) {
        if (!l.is_expr()) return l;
        switch (l.op()) {
            case Op::IF:
            case Op::MERGED_IF: {
                Value cond = subst(l[0], env);
                Env et(env), ee(env);
                Value t = walk(l[1], et);
                Value e = l.size() > 2 ? walk(l[2], ee) : Value();
                const bool t_ends = ends(t), e_ends = e.nil() ? false : ends(e);
                if (t_ends && !e_ends)
                    env = ee;
                else if (e_ends && !t_ends)
                    env = et;
                else if (!t_ends && !e_ends) {
                    et.meet(ee);
                    env = et;
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
                const EffectSummary& s = summary(l);
                env.kill(s);
                Env inside(env);
                Value cond = subst(l[0], inside);
                Value body = walk(l[1], inside);
                Value r = mk(Op::WHILE, cond, body, l[2], sv);
                cx().pcs.inherit(r, l);
                return r;
            }
            case Op::LABEL: {
                Value sv = subst_setvars(l[1], env);
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
                Env inside(env);
                inside.kill(summary(l));
                Value t = walk(l[0], inside);
                env.kill(summary(l));
                return t == l[0] ? l : mk(Op::LOOP_PATH, t, l[1]);
            }
            default: break;
        }
        Value r = subst_line(l, env);
        if (r != l) cx().pcs.inherit(r, l);
        env.kill(summary(r));
        if (r.is(Op::SETVAR, 2) && is_var(r[0])) {
            Value v = r[1];
            const EffectSummary& vs = summary(v);
            bool self = false;
            if (vs.reads & S_VARS) {
                if (vs.reads_any & S_VARS) self = true;
                else if (!vs.var_reads.nil())
                    for (Value x : vs.var_reads.args())
                        if (x == r[0]) self = true;
            }
            const bool movable = !(run_flags().msize && (vs.reads & (S_MEM | S_MSIZE))) && !(vs.control & C_FAILS);
            if (!self && movable && exp_size(v, limits::MAX_EXP_SIZE) <= limits::MAX_EXP_SIZE) env.set(r[0], v);
        }
        return r;
    }

    Value subst_setvars(Value sv, const Env& env) {
        if (!sv.is_list() || env.empty()) return sv;
        SmallVec<Value, 8> items;
        bool changed = false;
        for (Value x : sv.args()) {
            Value y = x;
            if (x.is(Op::SETVAR, 2)) {
                Value e = subst(x[1], env);
                if (e != x[1]) y = mk(Op::SETVAR, x[0], e);
            }
            if (y != x) changed = true;
            items.push_back(y);
        }
        return changed ? mk_like(sv, items.span()) : sv;
    }

    std::pmr::memory_resource* res_;
    Memo<Value, Value> memo_;
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
    // every variable v reads anywhere in it (lines, nested traces)
    void add_reads_all(Value v, Live& live) { add_reads(summary(v), live); }
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
            if (x.is(Op::SETVAR, 2)) add_reads(summary(x[1]), live);
    }

    Value line(Value l, Live& live) {
        if (!l.is_expr()) return l;
        switch (l.op()) {
            case Op::SETVAR: {
                if (is_var(l[0]) && !live.has(index(l[0]))) {
                    const EffectSummary& vs = summary(l[1]);
                    const bool droppable = !(vs.control & C_FAILS) && !(run_flags().msize && (vs.reads & (S_MEM | S_MSIZE)));
                    if (droppable) return Value();
                }
                live.remove(index(l[0]));
                add_reads(summary(l[1]), live);
                return l;
            }
            case Op::IF:
            case Op::MERGED_IF: {
                Live lt = live, le = live;
                Value t = walk(l[1], lt);
                Value e = l.size() > 2 ? walk(l[2], le) : Value();
                live = lt;
                if (l.size() > 2) live.unite(le);
                add_reads(summary(l[0]), live);
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
        add_reads(s, live);
        return l;
    }

    Memo<Value, u32> ids_;
    u32 next_ = 0;
    std::vector<Loop> loops_;
};

}  // namespace

Value cleanup_vars(Value trace) {
    if (!trace.is_list()) return trace;
    Env env(cx().budget.resource());
    Forward fw(cx().budget.resource());
    Value t = fw.walk(trace, env);
    Backward bw;
    Live live;
    return bw.walk(t, live);
}

}  // namespace pan::simplify
