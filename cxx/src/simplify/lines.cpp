// Lines: their operands' kinds, the walk of simplify_exps, the line-level
// rules of python's simplify_exp / cleanup_mems (no bytes of data: None,
// writes of nothing dropped).
#include "simplify/internal.hpp"
#include "simplify/simplify.hpp"

#include <algorithm>

#include "algebra/construct.hpp"
#include "core/context.hpp"
#include "mem/memory.hpp"

namespace pan::simplify {

namespace {

struct LineState final : ModuleState {
    Memo<Value, Value> line, trace;
    void clear_caches() override {
        line.clear();
        trace.clear();
    }
};

// the run's flags: kept through a compaction (their entry lines imported)
struct RunState final : ModuleState {
    RunFlags flags;
    Value next_entry;
    bool compact_prepare(Importer& imp) override {
        next_entry = flags.entry_lines.nil() ? Value() : imp(flags.entry_lines);
        return true;
    }
    void compact_commit() noexcept override { flags.entry_lines = next_entry; }
    void compact_abort() noexcept override { next_entry = Value(); }
};

LineState& lst() { return cx().state<LineState>(); }

bool is_int(Value v, i64 x) { return v.is_small() && v.small_val() == x; }

// bytes of none (python: a mem of length 0 is None in a data's place)
bool no_bytes(Value b) {
    if (b.is_none()) return true;
    if (b.is(Op::MEM, 1) && b[0].is(Op::RANGE, 2) && is_int(b[0][1], 0)) return true;
    if (b.is(Op::SIZED, 2) && is_int(b[0], 0)) return true;
    if (b.is(Op::DATA) && b.size() == 0) return true;
    if ((b.is(Op::CALLDATA_BYTES, 2) || b.is(Op::CODE_BYTES, 2)) && is_int(b[1], 0)) return true;
    if (b.is(Op::RETURNDATA_BYTES, 3) && is_int(b[2], 0)) return true;
    return false;
}

// A value's adjacent bytes in two parts - SIZED(a, x) SIZED(b, y), together
// the a + b low bytes of one field of a value in its place: x's low 8a bits
// moved up 8b OR y's low 8b bits is one mask, not moved (alg::bor merges
// two fields of one value) - as that field, SIZED(a + b, w): the same
// bytes. mem::concat merges such parts when their masks have the field's
// sizes; a mask narrowed since by the value's range, or a part of zeroes
// where the value's bits are zero, keeps them apart - a word written across
// where a call's selector goes, its 28 and 4 bytes apart: UniswapV3Pool's
// collectProtocol, `Bytes(28, uint96(_10 >> 32)), Bytes(4, uint32(_10))`
// (uint128(_10)); a bytes4 param's word, `Bytes(28, Mask(32, 224, p) >>
// 32), Bytes(4, 0)` (Mask(32, 224, p)). Words only (a part that is bytes,
// a read of memory, stays), a field in its place only (a value moved up
// stays apart: packed data). Two reads of one storage slot likewise
// (storage_fields).

// The parts SIZED(a, x) SIZED(b, y) of two reads of one storage slot, x's
// field right above y's and y's b bytes wide: the one read of both fields
// (a storage read masked is a narrower read, so alg::bor sees no masks of
// one value - OpenZeppelin's TokenTimelock, `Bytes(28, beneficiary >> 32),
// Bytes(4, uint32(beneficiary))`). The same storage at the same line: the
// bytes are the read's - x's low 8a bits (min(its size, 8a)) above y's 8b.
// NIL when they aren't that.
Value storage_fields(Value x, Value y, i64 a, i64 b) {
    if (!x.is(Op::STORAGE, 3) || !y.is(Op::STORAGE, 3) || x[2] != y[2]) return Value();
    if (!x[0].is_small() || !x[1].is_small() || !y[0].is_small() || !y[1].is_small()) return Value();
    const i64 xs = std::min<i64>(x[0].small_val(), 8 * a), xo = x[1].small_val();
    const i64 ys = y[0].small_val(), yo = y[1].small_val();
    if (ys != 8 * b || xo != yo + ys || xs <= 0 || yo < 0 || xo + xs > 256) return Value();
    return mk(Op::STORAGE, Value::small(xs + ys), Value::small(yo), x[2]);
}

// SIZED(a, x) SIZED(b, y) as the one field they are, SIZED(a + b, w) (see
// above); NIL when they aren't one
Value one_field(Value p, Value e) {
    if (!p.is(Op::SIZED, 2) || !e.is(Op::SIZED, 2) || !p[0].is_small() || !e[0].is_small() || mem::is_bytes(p[1]) ||
        mem::is_bytes(e[1]) || (p[1].is_int() && e[1].is_int()))
        return Value();
    const i64 a = p[0].small_val(), b = e[0].small_val();
    if (a <= 0 || b <= 0 || a + b > 32) return Value();
    Value w = alg::bor(alg::mask(8 * a, 0, 8 * b, p[1]), alg::mask(8 * b, 0, 0, e[1]));
    const alg::MaskShl f = alg::mask_view(w);
    if (w.is_int() || !f.concrete() || f.ishl() != 0 || f.x.is(Op::OR) || mem::is_bytes(f.x))
        w = storage_fields(p[1], e[1], a, b);
    return w.nil() ? Value() : mk(Op::SIZED, Value::small(a + b), w);
}

// A constant that ends with the zero bytes of a word, then the word's low
// bytes - SIZED(n, C), the last z bytes of C zero and the others not all,
// then a part of w = 32 - z bytes that is the low bytes of a word:
// SIZED(w, x) of a word x, or the last w bytes of a word of return data,
// calldata or code (as mem::concat reads zeroes before them: that word,
// masked) - as the constant without those zeroes, SIZED(n - z, C >> 8z),
// and the word, SIZED(32, its low w bytes): the same n + w bytes, the
// word's 32 being z zero bytes and its low w. A custom error with an
// address: the memory pass writes the address's masked word as 12 zero
// bytes and 20 bytes, and concat joins the zeroes to the selector's 4
// bytes before its own rule for zeroes and a word's low bytes sees them -
// `revert with Bytes(16, 0xd0103ae5000000000000000000000000), Bytes(20,
// x)`, the selector hidden, is `revert with 0xd0103ae5, address(x)`. A
// rule on the bytes, whatever their number (a 4-byte number after a
// constant of 32 bytes): nothing says which bytes a selector is. Not a
// constant of zeroes alone (concat's own rule), not a constant after it
// (concat joins constants), not bytes of memory (a mask of a memory word
// is the narrower read again). kept, word: the two parts; false when p
// and e aren't that.
bool constant_then_word(Value p, Value e, Value& kept, Value& word) {
    if (!p.is(Op::SIZED, 2) || !p[0].is_small() || !p[1].is_int()) return false;
    const auto width = mem::width_u64(e);
    if (!width || *width < 1 || *width > 31) return false;
    const i64 n = p[0].small_val(), w = i64(*width), z = 32 - w;
    if (n <= z || n > 32) return false;
    if (!is_int(alg::mask(8 * z, 0, 0, p[1]), 0)) return false;
    const Value rest = alg::mask(8 * (n - z), 8 * z, -8 * z, p[1]);
    if (!rest.is_int() || is_int(rest, 0)) return false;
    if (e.is(Op::SIZED, 2)) {
        if (mem::is_bytes(e[1]) || e[1].is_int()) return false;
        word = mk(Op::SIZED, Value::small(32), alg::mask(8 * w, 0, 0, e[1]));
    } else if (e.is(Op::RETURNDATA_BYTES) || e.is(Op::CALLDATA_BYTES) || e.is(Op::CODE_BYTES)) {
        const Value parts[] = {mk(Op::SIZED, Value::small(z), Value::small(0)), e};
        const Value m = mem::concat(parts);
        if (!m.is(Op::SIZED, 2) || !is_int(m[0], 32) || mem::is_bytes(m[1]) || m[1].is_int()) return false;
        word = m;
    } else {
        return false;
    }
    kept = mk(Op::SIZED, Value::small(n - z), rest);
    return true;
}

Value merged_parts(Value d) {
    if (!d.is(Op::DATA) || d.size() < 2) return d;
    SmallVec<Value, 8> out;
    bool changed = false;
    for (Value e : d.args()) {
        out.push_back(e);
        // (a part made joins the part before it in turn: a word's low bytes
        // in two parts, then the constant that ends with its zeroes)
        while (out.size() >= 2) {
            const Value p = out[out.size() - 2], q = out[out.size() - 1];
            if (const Value f = one_field(p, q); !f.nil()) {
                out.pop_back();
                out.back() = f;
                changed = true;
                continue;
            }
            Value kept, word;
            if (constant_then_word(p, q, kept, word)) {
                out[out.size() - 2] = kept;
                out.back() = word;
                changed = true;
            }
            break;
        }
    }
    if (!changed) return d;
    return out.size() == 1 ? out[0] : mk(Op::DATA, out.span());
}

// the line rules; NIL: drop the line
Value line_rules(Value l) {
    switch (l.op()) {
        case Op::SETMEM: {
            // a write of no bytes, a copy of memory onto itself: nothing changes
            if (l[0].is(Op::RANGE, 2) && is_int(l[0][1], 0)) return Value();
            if (!run_flags().msize && l[1].is(Op::MEM, 1) && l[1][0] == l[0]) return Value();
            // (the same: the bytes of a read of the range as its many bytes,
            // whole or masked to them - c00087's `mem[p + 296 len 28] =
            // uint224(mem[p + 296 len 28])`, a selector's write split)
            if (!run_flags().msize && l[0].is(Op::RANGE, 2) && l[0][1].is_small() && l[1].is(Op::SIZED, 2) &&
                l[1][0] == l[0][1]) {
                Value v = l[1][1];
                const i64 n = l[0][1].small_val();
                if (n > 0 && n < 32 && v.is(Op::MASK_SHL, 4) && is_int(v[0], 8 * n) && is_int(v[1], 0) &&
                    is_int(v[2], 0))
                    v = v[3];
                if (v.is(Op::MEM, 1) && v[0] == l[0]) return Value();
            }
            return l;
        }
        case Op::STORE_RANGE: {
            // no slot: nothing changes (nor msize: no byte read); one: a
            // STORE of its word (a read of memory stays one)
            if (l.size() != 3) return l;
            if (is_int(l[1], 0)) return Value();
            if (is_int(l[1], 1)) {
                const auto w = l[2].is_int() ? std::optional<Value>(l[2]) : mem::as_word(l[2]);
                if (w) return mk(Op::STORE, Value::small(256), Value::small(0), l[0], *w);
            }
            return l;
        }
        case Op::RETURN:
            if (no_bytes(l[0])) return mk(Op::STOP, std::span<const Value>{});
            if (Value d = merged_parts(l[0]); d != l[0]) return mk(Op::RETURN, d);
            return l;
        case Op::REVERT:
            if (!l[0].is_none() && no_bytes(l[0])) return mk(Op::REVERT, None);
            if (Value d = merged_parts(l[0]); d != l[0]) return mk(Op::REVERT, d);
            return l;
        case Op::LOG0:
        case Op::LOG1:
        case Op::LOG2:
        case Op::LOG3:
        case Op::LOG4:
            if (!l[0].is_none() && no_bytes(l[0])) {
                SmallVec<Value, 6> a(l.args());
                a[0] = None;
                return mk_like(l, a.span());
            }
            if (Value d = merged_parts(l[0]); d != l[0]) {
                SmallVec<Value, 6> a(l.args());
                a[0] = d;
                return mk_like(l, a.span());
            }
            return l;
        case Op::CALL:
        case Op::CALLCODE:
        case Op::DELEGATECALL:
        case Op::STATICCALL: {
            const u32 s = l.size() - 2, p = l.size() - 1;
            SmallVec<Value, 6> a(l.args());
            bool changed = false;
            if (!a[s].is_none() && no_bytes(a[s])) {
                a[s] = None;
                changed = true;
            }
            if (!a[p].is_none() && no_bytes(a[p])) {
                a[p] = None;
                changed = true;
            }
            // the selector: the input's first 4 bytes, apart (python's
            // fname / fdata; the input is sel ++ params all the same)
            if (a[s].is_none() && !a[p].is_none()) {
                Value d = a[p];
                if (auto w = mem::width_u64(d); w && *w == 4) {
                    a[s] = d;
                    a[p] = None;
                    changed = true;
                } else if (d.is(Op::DATA) && d.size() >= 2) {
                    bool arr = false;
                    for (Value e : d.args()) arr = arr || e.is(Op::ARR);
                    auto w0 = mem::width_u64(d[0]);
                    if (arr) {
                    } else if (w0 && *w0 == 4) {
                        a[s] = d[0];
                        a[p] = d.size() == 2 ? d[1] : mk(Op::DATA, d.args().subspan(1));
                        changed = true;
                    } else if (w0 && *w0 > 4) {
                        // (a first part wider than the selector: cut)
                        auto w = mem::width_of(d);
                        auto sel = mem::slice(d, Value::small(0), Value::small(4));
                        auto rest = w ? mem::slice(d, Value::small(4), *w) : std::nullopt;
                        if (sel && rest) {
                            a[s] = *sel;
                            a[p] = *rest;
                            changed = true;
                        }
                    }
                }
            }
            if (Value d = merged_parts(a[p]); d != a[p]) {
                a[p] = d;
                changed = true;
            }
            return changed ? mk_like(l, a.span()) : l;
        }
        default: return l;
    }
}

}  // namespace

RunFlags& run_flags() { return cx().state<RunState>().flags; }

Arg arg_kind(Op op, u32 i) {
    switch (op) {
        case Op::IF:
        case Op::MERGED_IF: return i == 0 ? Arg::Expr : Arg::Trace;
        case Op::WHILE: return i == 0 ? Arg::Expr : i == 1 ? Arg::Trace : i == 2 ? Arg::Raw : Arg::Setvars;
        case Op::CONTINUE:
        case Op::LABEL:
        case Op::GOTO: return i == 0 ? Arg::Raw : Arg::Setvars;
        case Op::LOOP_PATH: return i == 0 ? Arg::Trace : Arg::Raw;
        case Op::BREAK:
        case Op::UNDEFINED:
        case Op::INVALID:
        case Op::STOP: return Arg::Raw;
        case Op::SETVAR: return i == 0 ? Arg::Raw : Arg::Expr;
        case Op::INTERNAL: return i == 1 ? Arg::Values : Arg::Raw;
        case Op::LEAVE: return Arg::Values;
        case Op::ASM: return i == 3 ? Arg::Values : Arg::Raw;
        case Op::CALL:
        case Op::CALLCODE:
        case Op::DELEGATECALL:
        case Op::STATICCALL:
        case Op::CREATE:
        case Op::CREATE2: return i == 0 ? Arg::Raw : Arg::Expr;
        case Op::PRECOMPILED: return i == 3 ? Arg::Expr : Arg::Raw;
        default: return Arg::Expr;
    }
}

Value mk_like_checked(Value orig, std::span<const Value> args) {
    Value n = mk_like(orig, args);
    if (n == orig) return n;
    return mem::keep_widths(orig, n);
}

Value make_trace(std::span<const Value> lines) { return mk_trace(lines); }

namespace {

Value subst_rec(Value e, std::span<const Value> from, std::span<const Value> to, Memo<Value, Value>& memo) {
    if (e.is_name()) {
        for (usize i = 0; i < from.size(); ++i)
            if (from[i] == e) return to[i];
        return e;
    }
    if (!(e.is_expr() || e.is_list()) || !e.has_flags(F_VAR)) return e;
    if (const Value* r = memo.find(e)) return *r;
    check_stack();
    SmallVec<Value, 8> args;
    bool changed = false;
    for (Value a : e.args()) {
        Value n = subst_rec(a, from, to, memo);
        if (n != a) changed = true;
        args.push_back(n);
    }
    Value r = changed ? mk_like_checked(e, args.span()) : e;
    memo.put(e, r);
    return r;
}

}  // namespace

Value substitute(Value e, std::span<const Value> from, std::span<const Value> to) {
    if (from.empty() || !e.has_flags(F_VAR)) return e;
    Memo<Value, Value> memo;
    return subst_rec(e, from, to, memo);
}

void setvars_of(Value setvars, SmallVec<Value, 8>& names, SmallVec<Value, 8>& values) {
    if (!setvars.is_list()) return;
    for (Value sv : setvars.args())
        if (sv.is(Op::SETVAR, 2)) {
            names.push_back(sv[0]);
            values.push_back(sv[1]);
        }
}

bool assignments(Value line, SmallVec<Value, 8>& names, SmallVec<Value, 8>& values) {
    if (line.is(Op::SETVAR, 2)) {
        names.push_back(line[0]);
        values.push_back(line[1]);
        return true;
    }
    if (line.is(Op::CONTINUE, 2) || line.is(Op::GOTO, 2) || line.is(Op::LABEL, 2)) {
        setvars_of(line[1], names, values);
        return true;
    }
    return false;
}

u32 exp_size(Value e, u32 cap) {
    if (!e.is_expr() && !e.is_list()) return 1;
    u32 n = 1;
    SmallVec<Value, 32> todo;
    for (Value a : e.args()) todo.push_back(a);
    while (!todo.empty()) {
        if (n > cap) return n;
        Value v = todo.back();
        todo.pop_back();
        ++n;
        if (v.is_expr() || v.is_list())
            for (Value a : v.args()) todo.push_back(a);
    }
    return n;
}

Value simplify_line(Value line) {
    if (!line.is_expr()) return line;
    if (const Value* r = lst().line.find(line)) return *r;
    check_stack();
    const Op op = line.op();
    SmallVec<Value, 8> args;
    bool changed = false;
    for (u32 i = 0; i < line.size(); ++i) {
        Value a = line[i];
        Value n = a;
        switch (arg_kind(op, i)) {
            case Arg::Expr: n = simplify_at(a, operand_pos(op, i, line.size())); break;
            case Arg::Trace: n = simplify_exps(a); break;
            case Arg::Setvars:
            case Arg::Values: {
                if (!a.is_list()) break;
                SmallVec<Value, 8> items;
                bool ch = false;
                for (Value x : a.args()) {
                    Value y = x;
                    if (x.is(Op::SETVAR, 2)) {
                        Value e = simplify_word(x[1]);
                        if (e != x[1]) y = mk(Op::SETVAR, x[0], e);
                    } else {
                        y = simplify_word(x);
                    }
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
    Value r = changed ? mk_like_checked(line, args.span()) : line;
    r = line_rules(r);
    if (!r.nil() && r != line) cx().pcs.inherit(r, line);
    lst().line.put(line, r);
    return r;
}

Value simplify_exps(Value trace) {
    if (!trace.is_list()) return trace;
    if (const Value* r = lst().trace.find(trace)) return *r;
    SmallVec<Value, 32> out;
    bool changed = false;
    for (Value l : trace.args()) {
        poll();
        Value n = simplify_line(l);
        if (n != l) changed = true;
        if (!n.nil()) out.push_back(n);
    }
    Value r = changed ? mk_trace(out.span()) : trace;
    lst().trace.put(trace, r);
    return r;
}

}  // namespace pan::simplify
