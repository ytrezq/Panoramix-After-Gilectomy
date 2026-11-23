// The other passes of python's _simplify_trace: precompiled_results,
// split_lines (lot 4's splits), replace_bytes_or_string_length,
// cleanup_mul_1, max_to_add, fix_storages, readability, postprocess_exps.
#include "simplify/effects.hpp"
#include "simplify/internal.hpp"
#include "simplify/simplify.hpp"

#include <algorithm>
#include <vector>

#include "algebra/compare.hpp"
#include "algebra/construct.hpp"
#include "algebra/eval.hpp"
#include "algebra/facts.hpp"
#include "algebra/linear.hpp"
#include "algebra/ranges.hpp"
#include "core/context.hpp"
#include "core/intops.hpp"
#include "loops/loops.hpp"
#include "mem/memory.hpp"

namespace pan::simplify {

namespace {

Value small(i64 x) { return Value::small(x); }
bool is_int(Value v, i64 x) { return v.is_small() && v.small_val() == x; }

// ---- a generic rewrite of every expression of a trace (bottom-up, memoized) ---------------

// f(Value node, Pos pos) -> Value: called on each node after its operands
// were rewritten; returns the node (or its replacement)
template <class F>
class ExprRewrite {
public:
    explicit ExprRewrite(F f) : f_(f) {}

    Value trace(Value t) {
        if (!t.is_list()) return t;
        check_stack();
        SmallVec<Value, 32> out;
        bool changed = false;
        for (Value l : t.args()) {
            poll();
            Value r = line(l);
            if (r != l) changed = true;
            out.push_back(r);
        }
        return changed ? mk_trace(out.span()) : t;
    }
    Value line(Value l) {
        if (!l.is_expr()) return l;
        if (const Value* r = lines_.find(l)) return *r;
        const Op op = l.op();
        SmallVec<Value, 8> args;
        bool changed = false;
        for (u32 i = 0; i < l.size(); ++i) {
            Value a = l[i];
            Value n = a;
            switch (arg_kind(op, i)) {
                case Arg::Expr: n = exp(a, operand_pos(op, i, l.size())); break;
                case Arg::Trace: n = trace(a); break;
                case Arg::Setvars:
                case Arg::Values: {
                    if (!a.is_list()) break;
                    SmallVec<Value, 8> items;
                    bool ch = false;
                    for (Value x : a.args()) {
                        Value y = x.is(Op::SETVAR, 2) ? mk_if(x, exp(x[1], Pos::Word)) : exp(x, Pos::Word);
                        if (y != x) ch = true;
                        items.push_back(y);
                    }
                    if (ch) n = mk_like(a, items.span());
                    break;
                }
                case Arg::Raw: break;
            }
            if (n != a) changed = true;
            args.push_back(n);
        }
        Value r = changed ? mk_like_checked(l, args.span()) : l;
        if (r != l) cx().pcs.inherit(r, l);
        lines_.put(l, r);
        return r;
    }
    Value exp(Value e, Pos pos) {
        if (pos == Pos::Any) pos = mem::is_bytes(e) ? Pos::Bytes : Pos::Word;
        if (!e.is_expr()) return f_(e, pos);
        Memo<Value, Value>& m = pos == Pos::Bytes ? bytes_ : words_;
        if (const Value* r = m.find(e)) return *r;
        check_stack();
        SmallVec<Value, 8> args;
        bool changed = false;
        for (u32 i = 0; i < e.size(); ++i) {
            Value a = e[i];
            Value n = a.is_list() ? a : exp(a, operand_pos(e.op(), i, e.size()));
            if (n != a) changed = true;
            args.push_back(n);
        }
        Value r = changed ? mk_like_checked(e, args.span()) : e;
        r = f_(r, pos);
        m.put(e, r);
        return r;
    }

private:
    static Value mk_if(Value sv, Value e) { return e == sv[1] ? sv : mk(Op::SETVAR, sv[0], e); }
    F f_;
    Memo<Value, Value> lines_, words_, bytes_;
};

template <class F>
Value rewrite_exprs(Value trace, F f) {
    ExprRewrite<F> rw(f);
    return rw.trace(trace);
}

// ---- lines into lines ---------------------------------------------------------------------

// f(Value line, SmallVec<Value, 4>& out) -> bool: true when it put the
// line's replacement in out; traces inside rewritten first
template <class F>
Value rewrite_lines(Value trace, F& f) {
    if (!trace.is_list()) return trace;
    check_stack();
    SmallVec<Value, 32> out;
    bool changed = false;
    for (Value l : trace.args()) {
        poll();
        Value r = l;
        if (l.is_expr()) {
            const Op op = l.op();
            SmallVec<Value, 4> args;
            bool ch = false;
            for (u32 i = 0; i < l.size(); ++i) {
                Value a = l[i];
                Value n = arg_kind(op, i) == Arg::Trace ? rewrite_lines(a, f) : a;
                if (n != a) ch = true;
                args.push_back(n);
            }
            if (ch) r = mk_like(l, args.span());
        }
        SmallVec<Value, 4> repl;
        if (f(r, repl)) {
            changed = true;
            for (Value x : repl) {
                cx().pcs.inherit(x, l);
                out.push_back(x);
            }
            continue;
        }
        if (r != l) {
            changed = true;
            cx().pcs.inherit(r, l);
        }
        out.push_back(r);
    }
    return changed ? mk_trace(out.span()) : trace;
}

}  // namespace

// ---- precompiled_results ---------------------------------------------------------------------

Value precompiled_results(Value trace) {
    // the precompiles' calls: id -> their result variable (not the identity's,
    // whose output is its input; not modexp's, of any length)
    struct Result {
        Value id, name;
    };
    SmallVec<Result, 8> results;
    SmallVec<Value, 64> todo{trace};
    while (!todo.empty()) {
        Value t = todo.back();
        todo.pop_back();
        if (!t.is_list()) continue;
        for (Value l : t.args()) {
            if (l.is(Op::PRECOMPILED, 4) && l[1].is_name() && l[2].is_small()) {
                const i64 addr = l[2].small_val();
                if (addr != 4 && addr != 5 && addr >= 1 && addr <= 10) results.push_back({l[0], l[1]});
            }
            if (l.is_expr())
                for (u32 i = 0; i < l.size(); ++i)
                    if (arg_kind(l.op(), i) == Arg::Trace) todo.push_back(l[i]);
        }
    }
    if (results.empty()) return trace;
    return rewrite_exprs(trace, [&](Value e, Pos pos) -> Value {
        if (e.is(Op::RETURNDATA_BYTES, 3) && is_int(e[1], 0) && is_int(e[2], 32))
            for (const Result& x : results)
                if (e[0] == x.id) return pos == Pos::Bytes ? mk(Op::SIZED, small(32), x.name) : x.name;
        return e;
    });
}

// ---- splits -------------------------------------------------------------------------------------

Value split_lines(Value trace) {
    auto f = [](Value l, SmallVec<Value, 4>& out) -> bool {
        if (l.is(Op::SETMEM, 2)) {
            auto s = mem::split_setmem(l);
            if (s.size() == 1 && s[0] == l) return false;
            for (Value x : s) out.push_back(x);
            return true;
        }
        if (l.is(Op::STORE, 4)) {
            auto s = mem::split_store(l);
            if (s.size() == 1 && s[0] == l) return false;
            for (Value x : s) out.push_back(x);
            return true;
        }
        return false;
    };
    return rewrite_lines(trace, f);
}

// ---- the length of a bytes / string -----------------------------------------------------------

namespace {

// solidity's length of the bytes at slot key, from its word x = stor[key]:
// (x & (256 * iszero(x & 1) - 1)) >> 1 - the mask's normal form (the AND's
// operands in the order they come)
Value length_mask(Value key) {
    Value x = mk(Op::STORAGE, small(256), small(0), key);
    return alg::add(alg::mul(small(256), alg::iszero(alg::band(x, small(1)))), small(-1));
}

}  // namespace

Value replace_bytes_or_string_length(Value trace) {
    return rewrite_exprs(trace, [](Value e, Pos) -> Value {
        auto m = alg::as_mask(e);
        if (!m || !m->concrete() || m->ioff() < 1 || m->isize() + m->ioff() > 256) return e;
        if (!m->x.is(Op::AND, 2)) return e;
        // the slot: the STORAGE(256, 0, key) operand of the AND, the other its mask
        for (u32 i = 0; i < 2; ++i) {
            Value t = m->x[i];
            if (!t.is(Op::STORAGE, 3) || !is_int(t[0], 256) || !is_int(t[1], 0)) continue;
            Value key = t[2];
            if (m->x[1 - i] != length_mask(key)) continue;
            // (x & mask) is twice the length, plus the low bit of x: its bits
            // from 1 on are the length's from 0
            Value k = key.is_int() ? mk(Op::LOC, key) : key;
            Value len = mk(Op::STORAGE, small(256), small(0), mk(Op::LENGTH, k));
            if (m->isize() == 255 && m->ioff() == 1 && m->ishl() == -1) return len;
            return alg::mask(m->isize(), m->ioff() - 1, m->ishl() + 1, len);
        }
        return e;
    });
}

// ---- cleanup_mul_1, fix_storages, max_to_add -------------------------------------------------

Value cleanup_mul_1(Value trace) {
    // python's leftovers of its own normal forms (mul 1, mask 256 of a
    // number...) the algebra never makes: what's left is simplify_exp's
    return trace;
}

Value fix_storages(Value trace) {
    return rewrite_exprs(trace, [](Value e, Pos) -> Value {
        // a field moved left: the field, shifted
        if (e.is(Op::STORAGE, 3) && e[1].is_small() && e[1].small_val() < 0)
            return mk(Op::MASK_SHL, e[0], small(0), small(-e[1].small_val()), mk(Op::STORAGE, e[0], small(0), e[2]));
        return e;
    });
}

namespace {

// max(c1 + x, c2 + y) as m + max(c1 - m + x, c2 - m + y), m the least
// constant - when no sum wraps (python algebra.max_to_add, made sound)
Value max_add(Value e) {
    if (!e.is(Op::MAX) || e.size() < 2) return e;
    Value m;
    bool first = true;
    for (Value a : e.args()) {
        Value c;
        if (a.is_int())
            c = a;
        else if (a.is(Op::ADD) && a[0].is_int())
            c = a[0];
        else
            return e;
        if (int_sign(c) <= 0) return e;
        if (first || int_cmp(c, m) < 0) m = c;
        first = false;
    }
    if (first || int_sign(m) <= 0) return e;
    SmallVec<Value, 8> rest;
    for (Value a : e.args()) {
        if (!alg::is_word(a)) return e;
        Value d = alg::sub(a, m);
        if (!alg::is_word(d)) return e;
        rest.push_back(d);
    }
    return alg::add(m, alg::max(rest.span()));
}

}  // namespace

Value max_to_add(Value trace) {
    return rewrite_exprs(trace, [](Value e, Pos) -> Value { return max_add(e); });
}

// ---- readability --------------------------------------------------------------------------------

namespace {

// the loop variables' ids a value mentions (read or set)
using Ids = std::vector<u32>;
void loop_ids(Value v, Ids& out, MemoSet<Value>& seen) {
    if (v.is_name(NameKind::LOOP)) {
        out.push_back(v.name_id());
        return;
    }
    if (!(v.is_expr() || v.is_list()) || !v.has_flags(F_VAR)) return;
    if (!seen.add(v)) return;
    check_stack();
    for (Value x : v.children()) loop_ids(x, out, seen);
}
Ids ids_of(std::span<const Value> lines) {
    Ids out;
    MemoSet<Value> seen;
    for (Value l : lines) loop_ids(l, out, seen);
    std::sort(out.begin(), out.end());
    out.erase(std::unique(out.begin(), out.end()), out.end());
    return out;
}
bool has_id(const Ids& ids, u32 x) { return std::binary_search(ids.begin(), ids.end(), x); }
void add_ids(Ids& a, const Ids& b) {
    a.insert(a.end(), b.begin(), b.end());
    std::sort(a.begin(), a.end());
    a.erase(std::unique(a.begin(), a.end()), a.end());
}
bool has_loop(Value t) {
    SmallVec<Value, 16> todo{t};
    while (!todo.empty()) {
        Value x = todo.back();
        todo.pop_back();
        if (!x.is_list()) continue;
        for (Value l : x.args()) {
            if (l.is(Op::WHILE)) return true;
            if (l.is(Op::IF, 3)) {
                todo.push_back(l[1]);
                todo.push_back(l[2]);
            }
        }
    }
    return false;
}

// python readability: the revert branch of an if first; each loop's
// variables renamed, its counter 0 (printed idx), the others 1, 2... (s, t,
// ...) - python replace_while_var - avoiding the ids taken around them;
// `after`: the ids read past this trace (what follows the ifs and loops it
// is in): a variable read there keeps its name
Value readability_trace(Value trace, const Ids& outer, const Ids& after) {
    if (!trace.is_list()) return trace;
    check_stack();
    SmallVec<Value, 32> out;
    bool changed = false;
    const u32 n = trace.size();
    for (u32 i = 0; i < n; ++i) {
        poll();
        Value l = trace[i];
        if (l.is(Op::IF, 3)) {
            Ids around = outer, aft = after;
            const Ids rest_ids = ids_of(trace.args().subspan(i + 1));
            if (has_loop(l[1]) || has_loop(l[2])) add_ids(around, rest_ids);
            add_ids(aft, rest_ids);
            Value t = readability_trace(l[1], around, aft), e = readability_trace(l[2], around, aft);
            Value r = l;
            // the revert first: `if not cond: revert`
            if (e.size() == 1 && e[0].is(Op::REVERT) && !(t.size() == 1 && t[0].is(Op::REVERT)))
                r = mk(Op::IF, alg::iszero(l[0]), e, t);
            else if (t != l[1] || e != l[2])
                r = mk(Op::IF, l[0], t, e);
            if (r != l) {
                changed = true;
                cx().pcs.inherit(r, l);
            }
            out.push_back(r);
            continue;
        }
        if (l.is(Op::WHILE, 4)) {
            // the loop's variables renamed in it and what follows it here
            Value rest = mk_trace(trace.args().subspan(i));
            Ids taken = ids_of(trace.args().subspan(i));
            add_ids(taken, outer);
            const Ids before_ids = ids_of(trace.args().subspan(0, i));
            auto rename = [&](Value var, u32 from_id) {
                // (a variable read where the renaming doesn't reach keeps its name)
                if (!var.is_name(NameKind::LOOP) || has_id(after, var.name_id()) || has_id(before_ids, var.name_id()))
                    return from_id;
                u32 id = from_id;
                while (has_id(taken, id) && id != var.name_id()) ++id;
                add_ids(taken, Ids{id});
                Value to = Value::name(NameKind::LOOP, id);
                if (to != var) rest = loops::rename_var(rest, var, to);
                return id;
            };
            Value counter;
            if (auto ind = loops::induction(l)) {
                counter = ind->var;
                rename(counter, 0);
            }
            u32 next = 1;
            if (Value svs = l[3]; svs.is_list())
                for (Value sv : svs.args())
                    if (sv.is(Op::SETVAR, 2) && sv[0] != counter) next = rename(sv[0], next) + 1;
            Value w = rest[0];
            const auto tail = rest.args().subspan(1);
            Ids inner = outer;
            add_ids(inner, ids_of(std::span<const Value>(&w, 1)));
            const Ids tail_ids = ids_of(tail);
            add_ids(inner, tail_ids);
            Ids aft = after;
            add_ids(aft, tail_ids);
            add_ids(aft, ids_of(std::span<const Value>({w[0], w[3]})));
            Value body = readability_trace(w[1], inner, aft);
            Value nw = body == w[1] ? w : mk(Op::WHILE, w[0], body, w[2], w[3]);
            if (nw != l) {
                changed = true;
                cx().pcs.inherit(nw, l);
            }
            out.push_back(nw);
            Value more = readability_trace(mk_trace(tail), outer, after);
            for (Value x : more.args()) out.push_back(x);
            if (rest != mk_trace(trace.args().subspan(i)) || more != mk_trace(tail)) changed = true;
            return changed ? mk_trace(out.span()) : trace;
        }
        out.push_back(l);
    }
    return changed ? mk_trace(out.span()) : trace;
}

}  // namespace

Value readability(Value trace) { return readability_trace(trace, Ids{}, Ids{}); }

namespace {

// ---- ABI-encoded data: its arrays (python rewriter.postprocess_exp) ---------------------

// The most elements of a data read as an ABI encoding, and of head words
// that point at its tails (the readings are quadratic in them)
constexpr u32 ABI_MAX_ELEMENTS = 1024, ABI_MAX_OFFSETS = 64;

// a word element's value: SIZED(32, v)'s v (NIL for any other element)
Value word_of(Value e) { return e.is(Op::SIZED, 2) && is_int(e[0], 32) ? e[1] : Value(); }

// v's normal form (NIL past the algebra's caps: equal to nothing)
Value normal(Value v) {
    try {
        return alg::normalize(v);
    } catch (const SizeLimit&) {
        return Value();
    } catch (const DepthLimit&) {
        return Value();
    }
}

// v (a normal form) with its MAX / MIN the facts decide made the operand
// they are (any depth)
Value minmax_where(Value v, const alg::Facts& facts) {
    if (!v.is_expr()) return v;
    check_stack();
    SmallVec<Value, 8> args;
    bool changed = false;
    for (Value a : v.args()) {
        Value n = a.is_expr() ? minmax_where(a, facts) : a;
        if (n != a) changed = true;
        args.push_back(n);
    }
    Value r = changed ? mk_like(v, args.span()) : v;
    if (r.is(Op::MAX) || r.is(Op::MIN)) r = alg::reduce_minmax(r, alg::Top::Word, &facts);
    return r;
}

// v (a normal form) where the facts hold: its MAX / MIN they decide made
// the operand they are (aave311's 32 * max(2, len) once len > 1), then the
// value they bound it to when that is one value (a length 1 once 0 < len <=
// 1 is known); NIL past the algebra's caps
Value where_facts(Value v, const alg::Facts& facts) {
    if (v.is_int()) return v;
    Value r = minmax_where(v, facts);
    if (r != v) r = normal(r);
    if (r.nil() || r.is_int()) return r;
    const alg::Range b = alg::range(r, alg::Top::Word, &facts);
    return b.is_point() ? b.lo.value() : r;
}

// The tail of an ABI encoding at the elements [m, end) of a data - the
// length word d[m], then the content - when it is one: the content whole
// words for every value, as long as the length says - a bytes of len bytes
// (ceil32(len) bytes), len elements of k words (32 k len), or (constants
// only) len offsets and the tails they point at (64 len and more) -: where
// both are constants, those numbers; where both are expressions, provably
// (the same normal forms - the content's width the length itself when its
// form says it is a multiple of 32); never where one is a constant and the
// other not (they don't agree for every value). No content only for a
// length 0.
// With the facts that hold where the data is (abi_facts): agreeing where
// they hold - a length or a width they bound to one value is that value, a
// MAX / MIN they decide is the operand it is (alg::reduce_minmax), and the
// low 5 bits of the length they say are 0 or not: x % 32 == 0 => ceil32(x)
// == x (the width then whole words), x % 32 != 0 => ceil32(x) ==
// floor32(x) + 32 - both mod 2^256 (past 2^256 - 32, x + 31 wraps and
// ceil32(x) is 0, as floor32(x) + 32 = 2^256 is).
// 0: no tail; 2: an exact one (ceil32(len) bytes, len words, or provably
// so); 1: one of constants of k > 1 words an element, or of offsets
int abi_tail(std::span<const Value> d, u32 m, u32 end, const alg::Facts* facts) {
    const Value len = word_of(d[m]);
    if (len.nil()) return 0;
    SmallVec<Value, 8> widths;
    for (u32 i = m + 1; i < end; ++i) widths.push_back(*mem::width_of(d[i]));
    if (widths.empty()) return is_int(len, 0) || (facts && alg::eval_bool(alg::iszero(len), facts) == Tri::True) ? 2 : 0;
    Value w = normal(alg::add(widths.span()));
    Value l = normal(len);
    if (w.nil() || l.nil()) return 0;
    if (facts) {
        w = where_facts(w, *facts);
        l = where_facts(l, *facts);
        if (w.nil() || l.nil()) return 0;
    }
    // whole words: by the width's form, or where the facts say its low 5 bits are 0
    if (alg::low_zero_bits(w) < 5 &&
        !(facts && alg::eval_bool(alg::iszero(normal(alg::mask(5, 0, 0, w))), facts) == Tri::True))
        return 0;
    if (w.is_int() != l.is_int()) return 0;
    if (!w.is_int()) {
        // a content as wide as its length says: a multiple of 32 by its
        // form (low_zero_bits, of the masks, multiples and constants it is
        // made of), its ceil32 itself (ensdom122's resolve: a bytes of
        // ceil32(L) + 64 bytes, the ABI encoding of another bytes) - or by
        // the facts (the content's width is whole words, checked above)
        if (w == l) return 2;
        if (w == normal(alg::mask(251, 5, 0, alg::add(small(31), l)))) return 2;
        // the length not a multiple of 32 where the facts hold: ceil32(l) is floor32(l) + 32
        if (facts && alg::eval_bool(normal(alg::mask(5, 0, 0, l)), facts) == Tri::True &&
            w == normal(alg::add(small(32), alg::mask(251, 5, 0, l))))
            return 2;
        for (i64 k = 1; k <= 16; ++k)
            if (w == normal(alg::mul(small(32 * k), l))) return 2;
        return 0;
    }
    const EvmInt wi(w), li(l);
    if (li.sign() < 0 || li.bit_length() > 64 || wi.bit_length() > 64) return 0;
    const EvmInt per = EvmInt(i64(32)) * li;
    if (wi == floordiv(li + EvmInt(i64(31)), EvmInt(i64(32))) * EvmInt(i64(32)) || wi == per) return 2;
    if (li.is_zero()) return 0;
    return (!(wi < per) && pymod(wi, per).is_zero()) || !(wi < EvmInt(i64(2)) * per) ? 1 : 0;
}

// One reading of a data's elements d as an ABI encoding whose head is its
// first h elements (words): the head words that are offsets, each with the
// element its tail starts at
struct AbiReading {
    struct Offset {
        u32 head, tail;
    };
    SmallVec<Offset, 4> offsets;
};

// The readings with a head of h words: a head word is an offset when its
// value is, for every value, the place (from the data's start: places, in
// normal forms) of an element at h or after, a word (the length); the
// offsets, in the head's order, point at tails one after the other, the
// first at h, the last up to the data's end, each one a tail (abi_tail). Of
// the readings, those with the most offsets (a head word equal to the place
// of a tail is its offset, unless no reading has it so); nullopt when there
// is none, or several of them (ambiguous: two head words the offset of one
// tail).
std::optional<AbiReading> abi_reading(std::span<const Value> d, std::span<const Value> places, u32 h, int least,
                                      const alg::Facts* facts) {
    const u32 n = u32(d.size());
    // the candidates: (head word, the element at its value)
    SmallVec<AbiReading::Offset, 8> cand;
    for (u32 i = 0; i < h; ++i) {
        const Value v = word_of(d[i]);
        if (v.nil()) continue;
        const Value nv = normal(v);
        if (nv.nil()) continue;
        std::optional<u32> at;
        for (u32 m = h; m < n; ++m) {
            if (places[m] != nv || word_of(d[m]).nil()) continue;
            if (at) return std::nullopt;  // (the place of two elements: one of no width)
            at = m;
        }
        if (at) cand.push_back({i, *at});
        if (cand.size() > ABI_MAX_OFFSETS) return std::nullopt;
    }
    // the chains of candidates from the end: most[j] the most offsets of a
    // reading of the tails from cand[j]'s on, count[j] how many readings
    // have them (1, or 2 for more)
    const usize k = cand.size();
    std::vector<u32> most(k, 0), count(k, 0), next(k, u32(-1));
    for (usize j = k; j-- > 0;) {
        if (abi_tail(d, cand[j].tail, n, facts) >= least) {
            most[j] = 1;
            count[j] = 1;
        }
        for (usize q = j + 1; q < k; ++q) {
            if (count[q] == 0 || cand[q].tail <= cand[j].tail) continue;
            if (abi_tail(d, cand[j].tail, cand[q].tail, facts) < least) continue;
            if (most[q] + 1 > most[j]) {
                most[j] = most[q] + 1;
                count[j] = count[q];
                next[j] = u32(q);
            } else if (most[q] + 1 == most[j]) {
                count[j] = std::min<u32>(2, count[j] + count[q]);
            }
        }
    }
    // the first tail at h
    std::optional<usize> first;
    u32 best = 0, ways = 0;
    for (usize j = 0; j < k; ++j) {
        if (cand[j].tail != h || count[j] == 0) continue;
        if (most[j] > best) {
            best = most[j];
            ways = count[j];
            first = j;
        } else if (most[j] == best) {
            ways = std::min<u32>(2, ways + count[j]);
        }
    }
    if (!first || ways != 1) return std::nullopt;
    AbiReading r;
    for (usize j = *first;; j = next[j]) {
        r.offsets.push_back(cand[j]);
        if (next[j] == u32(-1)) break;
    }
    return r;
}

// The arrays of an ABI-encoded data - its head words, some of them the
// offsets (from the data's start) of tails after the head, each tail a
// length word and its content in whole words - each as ARR(len, content...)
// in its offset's place (python rewriter.postprocess_exp, for any number of
// them): the same bytes, which the machine encodes so - each ARR's offset in
// its place, its length and content padded to whole words after the head,
// in the ARRs' order. Only on a proven layout: the offsets equal to their
// tails' places for every value (normal forms), the tails one after the
// other from the end of the head to the end of the data; one reading of the
// data only (abi_reading, of every head size a head word's constant value
// gives), else the data as it is.

// the places of a data's elements (normal forms): places[0] 0, places[n]
// the data's end; false when a width isn't known (or past the caps)
bool abi_places(std::span<const Value> els, SmallVec<Value, 16>& places) {
    places.clear();
    places.push_back(small(0));
    for (u32 i = 0; i < els.size(); ++i) {
        const auto w = mem::width_of(els[i]);
        if (!w) return false;
        places.push_back(normal(alg::add(places[i], *w)));
        if (places.back().nil()) return false;
    }
    return true;
}

// the head sizes: h words, the value 32 h of one of them (its first tail's place)
SmallVec<u32, 4> abi_heads(std::span<const Value> els) {
    const u32 n = u32(els.size());
    SmallVec<u32, 4> heads;
    for (u32 i = 0; i < n; ++i) {
        const Value v = word_of(els[i]);
        if (!v.is_small() || v.small_val() <= 0 || v.small_val() % 32 != 0) continue;
        const i64 h = v.small_val() / 32;
        if (h <= i64(i) || h >= i64(n)) continue;
        bool words = true;
        for (i64 k = 0; k < h && words; ++k) words = mem::width_u64(els[u32(k)]) == std::optional<u64>(32);
        if (words && std::find(heads.begin(), heads.end(), u32(h)) == heads.end()) heads.push_back(u32(h));
    }
    return heads;
}

// The one reading of the elements, its head size: of exact tails only, else
// with the weak ones (c00600's 128 bytes, not a head of 4 words and an
// array of one element of 3 words); nullopt when there is none, or two of a
// kind (not proven)
struct AbiRead {
    AbiReading reading;
    u32 head = 0;
};
std::optional<AbiRead> abi_read(std::span<const Value> els, std::span<const Value> places, std::span<const u32> heads,
                                const alg::Facts* facts) {
    std::optional<AbiRead> found;
    for (int least = 2; least >= 1 && !found; --least)
        for (u32 h : heads) {
            poll();
            auto r = abi_reading(els, places, h, least, facts);
            if (!r) continue;
            if (found) return std::nullopt;  // (two readings: not proven)
            found = AbiRead{std::move(*r), h};
        }
    return found;
}

// The elements with a run of zero bytes, Bytes(n, 0), cut where the value
// of a head word - an offset - falls inside it (repo_Contract471's
// eip712Domain: a string's padding and the length 0 of the next tail, one
// run of zeroes): its first k bytes, then the rest - the length word, 32 of
// them, apart when the rest is longer. The cut proven inside the run: k and
// n - k, as words, add up below 2^256 (their ranges, with the facts where
// given), so they are n as integers - 0 <= k <= n for every value, the same
// bytes. Any number of cuts, a few rounds at most; false when none.
bool cut_zero_runs(SmallVec<Value, 16>& els, SmallVec<Value, 16>& places, std::span<const u32> heads,
                   const alg::Facts* facts) {
    u32 hmax = 0;
    for (u32 h : heads) hmax = std::max(hmax, h);
    const EvmInt top = EvmInt::pow2(256), word(i64(32));
    bool any = false;
    for (int round = 0; round < 4; ++round) {
        // the offsets no element starts at
        SmallVec<Value, 8> at;
        for (u32 i = 0; i < hmax && i < els.size(); ++i) {
            const Value v = word_of(els[i]);
            if (v.nil()) continue;
            const Value nv = normal(v);
            if (nv.nil() || std::find(places.begin(), places.end(), nv) != places.end()) continue;
            if (std::find(at.begin(), at.end(), nv) == at.end()) at.push_back(nv);
        }
        if (at.empty()) break;
        SmallVec<Value, 16> out;
        bool cut = false;
        for (u32 m = 0; m < els.size(); ++m) {
            poll();
            const Value e = els[m];
            bool done = false;
            if (m >= hmax && e.is(Op::SIZED, 2) && is_int(e[1], 0))
                for (Value nv : at) {
                    const Value k = normal(alg::sub(nv, places[m])), r = normal(alg::sub(places[m + 1], nv));
                    if (k.nil() || r.nil() || is_int(k, 0) || is_int(r, 0)) continue;
                    const alg::Range rk = alg::range(k, alg::Top::Word, facts), rr = alg::range(r, alg::Top::Word, facts);
                    if (!(rk.hi + rr.hi < top)) continue;
                    out.push_back(mk(Op::SIZED, k, small(0)));
                    if (word < rr.lo) {
                        out.push_back(mk(Op::SIZED, small(32), small(0)));
                        out.push_back(mk(Op::SIZED, normal(alg::sub(r, small(32))), small(0)));
                    } else {
                        out.push_back(mk(Op::SIZED, r, small(0)));
                    }
                    done = true;
                    break;
                }
            if (done)
                cut = true;
            else
                out.push_back(e);
        }
        if (!cut || out.size() > ABI_MAX_ELEMENTS) break;
        SmallVec<Value, 16> p;
        if (!abi_places(out.span(), p)) break;
        els = std::move(out);
        places = std::move(p);
        any = true;
    }
    return any;
}

// facts: those that hold where the data is (abi_facts), or none
Value abi_array(Value d, const alg::Facts* facts) {
    if (!d.is(Op::DATA) || d.size() < 2 || d.size() > ABI_MAX_ELEMENTS) return d;
    SmallVec<Value, 16> els(d.args());
    SmallVec<Value, 16> places;
    if (!abi_places(els.span(), places)) return d;
    const SmallVec<u32, 4> heads = abi_heads(els.span());
    if (heads.empty()) return d;
    std::optional<AbiRead> found = abi_read(els.span(), places.span(), heads.span(), facts);
    // else with the runs of zeroes an offset falls in cut there
    if (!found && cut_zero_runs(els, places, heads.span(), facts))
        found = abi_read(els.span(), places.span(), heads.span(), facts);
    if (!found) return d;
    const AbiReading* reading = &found->reading;
    const u32 head = found->head, n = u32(els.size());
    SmallVec<Value, 8> out;
    for (u32 i = 0; i < head; ++i) out.push_back(els[i]);
    const auto& offs = reading->offsets;
    for (usize j = 0; j < offs.size(); ++j) {
        const u32 m = offs[j].tail, end = j + 1 < offs.size() ? offs[j + 1].tail : n;
        const Value len = word_of(els[m]);
        SmallVec<Value, 8> content;
        u64 total = 0;
        bool known = true;
        for (u32 i = m + 1; i < end; ++i) {
            if (auto k = mem::width_u64(els[i]))
                total += *k;
            else
                known = false;
            content.push_back(els[i]);
        }
        // without the zeroes past its length, when they're only that
        if (known && len.is_small()) {
            u64 kept = total;
            usize k = content.size();
            while (k > 0 && content[k - 1].is(Op::SIZED, 2) && is_int(content[k - 1][1], 0)) {
                kept -= *mem::width_u64(content[k - 1]);
                --k;
            }
            if (i64(kept) == len.small_val() && (kept + 31) / 32 * 32 == total)
                while (content.size() > k) content.pop_back();
        }
        SmallVec<Value, 8> arr;
        arr.push_back(len);
        for (Value c : content) arr.push_back(c);
        out[offs[j].head] = mk(Op::ARR, arr.span());
    }
    return mk(Op::DATA, out.span());
}

// The ABI readings that need the conditions known where a line runs (a
// length that agrees with its content only on its path: gnosis130's and
// safe141's copy of return data, rounded where len % 32 != 0; aave311's
// array of one element where 0 < len <= 1): the trace walked with lot 3's
// facts as cleanup_conds keeps them (conds.cpp's Conds) - each condition
// of an enclosing if or while, the negation of an if's condition for the
// lines after it in its trace when one of its branches always ends, each
// dropped at the first line that may change what it reads (effects.hpp:
// the variables it reads set again, memory, storage, return data,
// balances written, a call) - a loop's head forgets what the loop changes,
// so a fact from outside doesn't enter it when the loop sets what it reads,
// and the facts its body learns don't leave it. Each data a line reads -
// its operands' - that no reading without facts made arrays (abi_array's
// own pass, before) is read again with the facts there.
class AbiFacts {
public:
    Value trace(Value t) {
        if (!t.is_list()) return t;
        check_stack();
        SmallVec<Value, 32> out;
        bool changed = false;
        const u32 n = t.size();
        for (u32 i = 0; i < n; ++i) {
            poll();
            const Value line = t[i];
            Value r = line;
            if (line.is(Op::LABEL, 2)) {
                // a loop's head: the lines after it run again - what they change, forgotten
                EffectSummary rest = summary(line);
                for (u32 j = i + 1; j < n; ++j) rest = combine(rest, summary(t[j]), true);
                forget(rest);
            } else if (line.is(Op::WHILE, 4)) {
                // at its head, every iteration's and after it: what the loop changes, forgotten
                forget(summary(line));
                const Saved saved = save();
                assume(line[0]);
                const Value body = trace(line[1]);
                restore(saved);
                if (body != line[1]) r = mk(Op::WHILE, line[0], body, line[2], line[3]);
            } else if (line.is(Op::IF, 3)) {
                const Value cond = line[0];
                const Saved saved = save();
                assume(cond);
                const Value tt = trace(line[1]);
                restore(saved);
                assume(alg::iszero(cond));
                const Value ee = trace(line[2]);
                restore(saved);
                forget(summary(line));
                // what follows runs after the branch that goes on, if one ends
                const bool t_ends = ends(line[1]), e_ends = ends(line[2]);
                if (t_ends != e_ends) {
                    const Value holds = t_ends ? alg::iszero(cond) : cond;
                    if (!changes(summary(t_ends ? line[2] : line[1]), summary(holds))) assume(holds);
                }
                if (tt != line[1] || ee != line[2]) r = mk(Op::IF, cond, tt, ee);
            } else {
                if (!known_.empty()) r = with_facts(line);
                // (a line of traces other than these: forgotten whole, not walked)
                forget(summary(line));
            }
            if (r != line) {
                changed = true;
                cx().pcs.inherit(r, line);
            }
            out.push_back(r);
        }
        return changed ? mk_trace(out.span()) : t;
    }

private:
    // the line's data operands read with the facts
    Value with_facts(Value line) {
        if (!line.is_expr()) return line;
        const Op op = line.op();
        SmallVec<Value, 8> args;
        bool changed = false;
        for (u32 i = 0; i < line.size(); ++i) {
            Value a = line[i];
            if (arg_kind(op, i) == Arg::Trace) return line;
            if (arg_kind(op, i) == Arg::Expr && a.is(Op::DATA)) {
                const Pos pos = operand_pos(op, i, line.size());
                if (pos == Pos::Bytes || (pos == Pos::Any && mem::is_bytes(a))) a = abi_array(a, &facts_);
            }
            if (a != line[i]) changed = true;
            args.push_back(a);
        }
        return changed ? mk_like_checked(line, args.span()) : line;
    }
    // (at most this many: past them, the newer ones aren't kept - fewer facts are as sound)
    static constexpr usize kMaxKnown = 32;
    struct Saved {
        SmallVec<Value, 16> known;
        alg::Facts facts;
    };
    Saved save() const { return Saved{known_, facts_}; }
    void restore(const Saved& s) {
        known_ = s.known;
        facts_ = s.facts;
    }
    void assume(Value cond) {
        if (cond.is_int() || known_.size() >= kMaxKnown) return;
        known_.push_back(cond);
        facts_ = facts_.with_cond(cond);
    }
    void forget(const EffectSummary& s) {
        if (!s.writes || known_.empty()) return;
        SmallVec<Value, 16> kept;
        for (Value c : known_)
            if (!changes(s, summary(c))) kept.push_back(c);
        if (kept.size() == known_.size()) return;
        known_ = kept;
        facts_ = alg::Facts();
        for (Value c : known_) facts_ = facts_.with_cond(c);
    }

    SmallVec<Value, 16> known_;
    alg::Facts facts_;
};

}  // namespace

Value postprocess_exps(Value trace) {
    trace = rewrite_exprs(trace, [](Value e, Pos pos) -> Value { return pos == Pos::Bytes ? abi_array(e, nullptr) : e; });
    return AbiFacts{}.trace(trace);
}

}  // namespace pan::simplify
