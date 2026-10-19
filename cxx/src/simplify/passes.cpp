// The other passes of python's _simplify_trace: precompiled_results,
// split_lines (lot 4's splits), replace_bytes_or_string_length,
// cleanup_mul_1, max_to_add, fix_storages, readability, postprocess_exps.
#include "simplify/effects.hpp"
#include "simplify/internal.hpp"
#include "simplify/simplify.hpp"

#include "algebra/compare.hpp"
#include "algebra/construct.hpp"
#include "algebra/eval.hpp"
#include "algebra/linear.hpp"
#include "algebra/ranges.hpp"
#include "core/context.hpp"
#include "core/intops.hpp"
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
// (x & (256 * iszero(x & 1) - 1)) >> 1 - as the algebra's normal form makes
// it: the bits [1, 256) of AND(x, 255 + 2^256 - 256 * ... )...; matched by
// evaluating: the shape below built for the slot and compared
Value length_idiom(Value key, i64 size, i64 off) {
    Value x = mk(Op::STORAGE, small(256), small(0), key);
    Value low = alg::band(x, small(1));
    Value m = alg::add(alg::mul(small(256), alg::iszero(low)), small(-1));
    Value v = alg::band(x, m);
    return alg::mask(size, off, -1, v);
}

}  // namespace

Value replace_bytes_or_string_length(Value trace) {
    return rewrite_exprs(trace, [](Value e, Pos) -> Value {
        auto m = alg::as_mask(e);
        if (!m || !m->concrete() || m->ishl() != -1 || m->ioff() < 1 || m->isize() + m->ioff() > 256) return e;
        if (!m->x.is(Op::AND)) return e;
        // the slot: the STORAGE(256, 0, key) operand of the AND
        for (Value t : m->x.args()) {
            if (!t.is(Op::STORAGE, 3) || !is_int(t[0], 256) || !is_int(t[1], 0)) continue;
            Value key = t[2];
            if (length_idiom(key, m->isize(), m->ioff()) != e) continue;
            Value k = key.is_int() ? mk(Op::LOC, key) : key;
            Value len = mk(Op::STORAGE, small(256), small(0), mk(Op::LENGTH, k));
            if (m->isize() == 255 && m->ioff() == 1) return len;
            return alg::mask(m->isize(), m->ioff() - 1, 0, len);
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

Value readability_trace(Value trace) {
    if (!trace.is_list()) return trace;
    check_stack();
    SmallVec<Value, 32> out;
    bool changed = false;
    for (Value l : trace.args()) {
        poll();
        Value r = l;
        if (l.is(Op::IF, 3)) {
            Value t = readability_trace(l[1]), e = readability_trace(l[2]);
            // the revert first: `if not cond: revert`
            if (e.size() == 1 && e[0].is(Op::REVERT) && !(t.size() == 1 && t[0].is(Op::REVERT)))
                r = mk(Op::IF, alg::iszero(l[0]), e, t);
            else if (t != l[1] || e != l[2])
                r = mk(Op::IF, l[0], t, e);
        } else if (l.is(Op::WHILE, 4)) {
            Value body = readability_trace(l[1]);
            if (body != l[1]) r = mk(Op::WHILE, l[0], body, l[2], l[3]);
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

Value readability(Value trace) { return readability_trace(trace); }

namespace {

// an ABI-encoded array in a DATA - its offset among the head words, then at
// that offset its length and its content in whole words - as ARR(len,
// content...) in the offset's place (python rewriter.postprocess_exp): the
// same bytes (the machine encodes an ARR so: its offset in the head, its
// length and content, padded to whole words, after the heads)
Value abi_array(Value d) {
    if (!d.is(Op::DATA) || d.size() < 3) return d;
    const u32 n = d.size();
    auto word_const = [](Value e) -> std::optional<i64> {
        if (e.is(Op::SIZED, 2) && is_int(e[0], 32) && e[1].is_small() && e[1].small_val() >= 0) return e[1].small_val();
        return std::nullopt;
    };
    // the offset: the one constant multiple of 32 among the words before what it points at
    i64 at = -1, loc = -1;
    for (u32 i = 0; i < n; ++i) {
        auto c = word_const(d[i]);
        if (!c || *c % 32 != 0 || *c == 0) continue;
        if (at >= 0) return d;  // several: ambiguous
        at = i;
        loc = *c / 32;
    }
    if (at < 0 || loc <= at || loc + 1 >= i64(n)) return d;
    for (i64 i = 0; i <= loc; ++i) {
        auto w = mem::width_u64(d[u32(i)]);
        if (!w || *w != 32) return d;
    }
    Value lenw = d[u32(loc)];
    if (!lenw.is(Op::SIZED, 2)) return d;
    Value len = lenw[1];
    // the content: whole words
    SmallVec<Value, 8> content;
    u64 total = 0;
    for (u32 i = u32(loc) + 1; i < n; ++i) {
        auto w = mem::width_u64(d[i]);
        if (!w) return d;
        total += *w;
        content.push_back(d[i]);
    }
    if (total % 32 != 0) return d;
    // without the zeroes past its length, when they're only that
    if (len.is_small()) {
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
    SmallVec<Value, 8> out;
    for (i64 i = 0; i < loc; ++i) out.push_back(i == at ? mk(Op::ARR, arr.span()) : d[u32(i)]);
    return mk(Op::DATA, out.span());
}

}  // namespace

Value postprocess_exps(Value trace) {
    return rewrite_exprs(trace, [](Value e, Pos pos) -> Value { return pos == Pos::Bytes ? abi_array(e) : e; });
}

}  // namespace pan::simplify
