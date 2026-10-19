// Path facts: see facts.hpp. Python vm.py's known, write_memory,
// read_memory, known_zeroes, forget, is_known, decided, upper_bound, bound,
// write_range; arithmetic.eval_bool(exp, fact, symbolic=False) (match);
// memloc.max_value_bits. (The memory facts as lot 5 first wrote them.)
#include "algebra/facts.hpp"

#include <algorithm>
#include <new>

#include "algebra/compare.hpp"
#include "algebra/construct.hpp"
#include "algebra/eval.hpp"
#include "algebra/masks.hpp"
#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/intops.hpp"

namespace pan::alg {

namespace {

// a memory place or size as a number, when it is one we can count with
// (python's ints: past 2^48 the EVM can't reach it - the write is taken as
// one that may go anywhere, which is sound)
std::optional<u64> small_place(Value v) {
    if (!v.is_small()) return std::nullopt;
    i64 x = v.small_val();
    if (x < 0 || x >= (i64(1) << 48)) return std::nullopt;
    return u64(x);
}

// whether v reads transient storage (a walk only below values with F_STATE)
bool mentions_tload(Value v) {
    check_stack();
    if (!v.has_flags(F_STATE)) return false;
    if (v.is(Op::TLOAD)) return true;
    for (Value a : v.children())
        if (mentions_tload(a)) return true;
    return false;
}

bool mentions(Value v, Forget what) {
    switch (what) {
        case Forget::Storage: return v.has_flags(F_STORAGE);
        case Forget::Tload: return mentions_tload(v);
        case Forget::Volatile: return v.has_flags(F_VOLATILE);
    }
    return true;
}

// the condition a fact is: BOOL(x) is x
Value fact_cond(Value a) { return a.is(Op::BOOL, 1) ? a[0] : a; }

// a <= b for every value of what they're made of, as words (python
// algebra.proven_le with is_word: here only what is certain without ranges;
// eval_bool asks the ranges)
bool proven_le_words(Value a, Value b) {
    if (a == b) return true;
    if (a.is_int() && b.is_int()) return !(word_of(b) < word_of(a));
    return false;
}

// python arithmetic.eval_bool(exp, kt, symbolic=False), iz_exp = is_zero(exp),
// iz_kt = is_zero(kt)
Tri match_one(Value exp, Value iz_exp, Value kt, Value iz_kt) {
    check_stack();
    if (exp == kt) return Tri::True;
    if (iz_exp == kt) return Tri::False;
    if (exp == iz_kt) return Tri::False;
    if (exp.is_bool()) return tri(exp.is_true());
    if (exp.is_int()) return tri(!word_of(exp).is_zero());
    if (!exp.is_expr()) return Tri::None;
    switch (exp.op()) {
        case Op::BOOL:
            return match_one(exp[0], iszero(exp[0]), kt, iz_kt);
        case Op::ISZERO: {
            Tri e = match_one(exp[0], iszero(exp[0]), kt, iz_kt);
            if (e != Tri::None) return tri_not(e);
            break;
        }
        case Op::OR: {
            bool res = false;
            for (Value e : exp.args()) {
                Tri r = match_one(e, iszero(e), kt, iz_kt);
                if (r == Tri::None) return Tri::None;
                res = res || r == Tri::True;
            }
            return tri(res);
        }
        case Op::AND:
            // (bitwise too: only an operand known to be 0 decides it)
            for (Value e : exp.args()) {
                Tri r = match_one(e, iszero(e), kt, iz_kt);
                if (r == Tri::False) return Tri::False;
            }
            break;
        default:
            break;
    }
    if ((exp.is(Op::LE, 2) || exp.is(Op::LT, 2)) && kt.is(exp.op(), 2) && exp[0] == kt[0]) {
        // x < b where x < a is known: when a <= b, as words
        if (proven_le_words(kt[1], exp[1])) return Tri::True;
    }
    if (auto w = eval_const(exp)) return tri(!w->is_zero());
    return Tri::None;
}

}  // namespace

Value mask_value(Value v, i64 size, i64 off, i64 shl) {
    if (size == 256 && off == 0 && shl == 0) return v;
    return mask(size, off, shl, v);
}

u32 max_value_bits(Value v, const Facts* facts) { return range_bits(v, Top::Word, facts); }

// ---- the list -------------------------------------------------------------------

const Facts::Cell* Facts::cons(const Fact& f, const Cell* next, const Cell* same) {
    const CondBound* b = nullptr;
    u32 nb = 0;
    if (same && same->f.kind == f.kind && same->f.a == f.a && same->f.b == f.b) {
        b = same->b;
        nb = same->nb;
    } else if (f.kind == FactKind::Cond || f.kind == FactKind::VarBits) {
        // a condition's bounds; a variable's bits: [0, 2^bits - 1]
        CondBounds cb;
        if (f.kind == FactKind::Cond) {
            cb = cond_bounds(f.a);
        } else if (f.b.is_small() && f.b.small_val() >= 0 && f.b.small_val() < 256) {
            cb.push_back(CondBound{f.a, Value::small(0), (EvmInt::pow2(u64(f.b.small_val())) - EvmInt(1)).value()});
        }
        if (!cb.empty()) {
            void* p = cx().arena.alloc_raw(cb.size() * sizeof(CondBound));
            CondBound* arr = static_cast<CondBound*>(p);
            for (usize i = 0; i < cb.size(); ++i) new (arr + i) CondBound(cb[i]);
            b = arr;
            nb = u32(cb.size());
        }
    }
    void* p = cx().arena.alloc_raw(sizeof(Cell));
    return new (p) Cell{next, f, b, nb};
}

Facts Facts::with(const Fact& f) const {
    Facts r;
    Fact g = f;
    if (g.kind == FactKind::Cond && g.c.nil()) {
        // its negation, computed once (match compares with it)
        g.c = iszero(fact_cond(g.a));
    }
    r.head_ = cons(g, head_);
    r.n_ = n_ + 1;
    r.nbounds_ = nbounds_ + r.head_->nb;
    return r;
}

Facts Facts::with(Value cond, bool holds) const { return with_cond(holds ? cond : iszero(cond)); }

Facts Facts::from_cells(std::span<const Cell* const> oldest_first) {
    Facts r;
    for (const Cell* c : oldest_first) {
        r.head_ = cons(c->f, r.head_, c);
        ++r.n_;
        r.nbounds_ += r.head_->nb;
    }
    return r;
}

namespace {

// the cells of a list, oldest first
template <class Cell>
void cells_of(const Cell* head, SmallVec<const Cell*, 32>& out) {
    out.clear();
    for (const Cell* c = head; c; c = c->next) out.push_back(c);
    std::reverse(out.begin(), out.end());
}

}  // namespace

bool Facts::contains(const Fact& f) const noexcept {
    for (const Cell* c = head_; c; c = c->next) {
        const Fact& g = c->f;
        if (g.kind != f.kind || g.a != f.a || g.b != f.b) continue;
        // (a condition's c is its cached negation)
        if (g.kind == FactKind::Cond || g.c == f.c) return true;
    }
    return false;
}

bool Facts::has(FactKind k) const noexcept {
    for (const Cell* c = head_; c; c = c->next)
        if (c->f.kind == k) return true;
    return false;
}

void Facts::to_vector(SmallVec<Fact, 32>& out) const {
    out.clear();
    for (const Cell* c = head_; c; c = c->next) out.push_back(c->f);
    std::reverse(out.begin(), out.end());
}

Facts Facts::from(std::span<const Fact> oldest_first) {
    Facts r;
    for (const Fact& f : oldest_first) r = r.with(f);
    return r;
}

bool Facts::operator==(const Facts& o) const noexcept {
    if (n_ != o.n_) return false;
    const Cell* a = head_;
    const Cell* b = o.head_;
    for (; a && b; a = a->next, b = b->next) {
        if (a == b) return true;  // a shared tail
        if (!(a->f == b->f)) return false;
    }
    return a == b;
}

Tri Facts::match(Value exp) const {
    try {
        return match_all(exp);
    } catch (const DepthLimit&) {
        return Tri::None;  // (too deep for the stack: undecided)
    }
}

Tri Facts::match_all(Value exp) const {
    if (exp.is_int()) return tri(!word_of(exp).is_zero());
    if (exp.is_bool()) return tri(exp.is_true());
    if (!head_) return Tri::None;
    if (auto w = eval_const(exp)) return tri(!w->is_zero());
    // (per fact: a few compares, unless exp needs python's walk through
    // BOOL / ISZERO / OR / AND, or is x < b)
    const Value iz_exp = iszero(exp);
    const bool deep = exp.is(Op::BOOL, 1) || exp.is(Op::ISZERO, 1) || exp.is(Op::OR) || exp.is(Op::AND);
    const bool ltle = exp.is(Op::LE, 2) || exp.is(Op::LT, 2);
    for (const Cell* c = head_; c; c = c->next) {
        const Fact& f = c->f;
        if (f.kind != FactKind::Cond) continue;
        poll();
        const Value kt = fact_cond(f.a);
        if (exp == kt) return Tri::True;
        if (iz_exp == kt || exp == f.c) return Tri::False;
        if (deep) {
            Tri r = match_one(exp, iz_exp, kt, f.c);
            if (r != Tri::None) return r;
        } else if (ltle && kt.is(exp.op(), 2) && exp[0] == kt[0] && proven_le_words(kt[1], exp[1])) {
            // x < b where x < a is known: when a <= b, as words
            return Tri::True;
        }
        if (kt.is(Op::AND)) {
            // an AND that isn't 0: none of its operands is
            for (Value k0 : kt.args()) {
                const Value k = fact_cond(k0);
                if (exp == k) return Tri::True;
                if (iz_exp == k) return Tri::False;
                if (deep) {
                    Tri r = match_one(exp, iz_exp, k, iszero(k));
                    if (r != Tri::None) return r;
                } else if (ltle && k.is(exp.op(), 2) && exp[0] == k[0] && proven_le_words(k[1], exp[1])) {
                    return Tri::True;
                }
            }
        }
    }
    return Tri::None;
}

Tri Facts::is_known(Value cond) const { return eval_bool(cond, this); }

Value Facts::decided(Value exp) const {
    if (exp.is_int()) return exp;
    Tri r = is_known(exp);
    if (r == Tri::False) return Value::small(0);
    if (r == Tri::True && is_bool(exp)) return Value::small(1);
    return exp;
}

std::optional<Range> Facts::bounds(Value x) const {
    std::optional<Range> res;
    auto take = [&](const Range& r) {
        if (!res) {
            res = r;
        } else if (auto m = res->meet(r)) {
            res = *m;
        }
    };
    each_bound([&](Value bx, Value lo, Value hi) {
        if (bx == x) take(Range{EvmInt(lo), EvmInt(hi)});
    });
    if (u32 b = var_bits(x)) take(Range::bits(b));
    return res;
}

Facts Facts::forget(Forget what) const {
    // nothing to change: the same list
    bool any = false;
    for (const Cell* c = head_; c && !any; c = c->next) {
        const Fact& f = c->f;
        switch (f.kind) {
            case FactKind::Cond: any = mentions(f.a, what); break;
            case FactKind::Mem: any = !f.c.nil() && mentions(f.c, what); break;
            case FactKind::RdZero: any = what == Forget::Volatile; break;
            case FactKind::VarBits: any = mentions(f.a, what); break;
            case FactKind::Fresh: break;
        }
    }
    if (!any) return *this;
    SmallVec<const Cell*, 32> cs;
    cells_of(head_, cs);
    Facts r;
    for (const Cell* c : cs) {
        Fact f = c->f;
        switch (f.kind) {
            case FactKind::Cond:
            case FactKind::VarBits:
                if (mentions(f.a, what)) continue;
                break;
            case FactKind::Mem:
                if (!f.c.nil() && mentions(f.c, what)) f.c = Value();
                break;
            case FactKind::RdZero:
                if (what == Forget::Volatile) continue;
                break;
            case FactKind::Fresh:
                break;
        }
        r.head_ = cons(f, r.head_, c);
        ++r.n_;
        r.nbounds_ += r.head_->nb;
    }
    return r;
}

Facts Facts::forget_flags(u8 flags) const {
    bool any = false;
    for (const Cell* c = head_; c && !any; c = c->next) {
        const Fact& f = c->f;
        switch (f.kind) {
            case FactKind::Cond:
            case FactKind::VarBits: any = f.a.has_flags(flags); break;
            case FactKind::Mem: any = !f.c.nil() && f.c.has_flags(flags); break;
            case FactKind::RdZero: any = (flags & F_STATE) != 0; break;
            case FactKind::Fresh: break;
        }
    }
    if (!any) return *this;
    SmallVec<const Cell*, 32> cs;
    cells_of(head_, cs);
    Facts r;
    for (const Cell* c : cs) {
        Fact f = c->f;
        switch (f.kind) {
            case FactKind::Cond:
            case FactKind::VarBits:
                if (f.a.has_flags(flags)) continue;
                break;
            case FactKind::Mem:
                if (!f.c.nil() && f.c.has_flags(flags)) f.c = Value();
                break;
            case FactKind::RdZero:
                if (flags & F_STATE) continue;
                break;
            case FactKind::Fresh:
                break;
        }
        r.head_ = cons(f, r.head_, c);
        ++r.n_;
        r.nbounds_ += r.head_->nb;
    }
    return r;
}

Facts Facts::without_memory() const {
    bool any = false;
    for (const Cell* c = head_; c && !any; c = c->next)
        any = c->f.kind == FactKind::Mem || c->f.kind == FactKind::Fresh;
    if (!any) return *this;
    SmallVec<const Cell*, 32> cs, keep;
    cells_of(head_, cs);
    for (const Cell* c : cs)
        if (c->f.kind != FactKind::Mem && c->f.kind != FactKind::Fresh) keep.push_back(c);
    return from_cells(keep.span());
}

// ---- memory -------------------------------------------------------------------------

Facts Facts::write_memory(Value start, Value size, Value value) const {
    auto s = small_place(start);
    auto n = small_place(size);
    if (!s || !n) {
        if (auto r = write_range(start, size)) {
            // somewhere there
            if (r->hi.fits_i64() && r->lo.fits_i64())
                return write_memory(r->lo.value(), (r->hi - r->lo).value(), Value());
        }
        // anywhere
        return without_memory();
    }
    if (*n == 0) return *this;
    if (!value.nil()) {
        if (*n != 1 && *n != 32 && !(value.is_int() && *n < 32)) value = Value();
    }
    if (!value.nil() && value.has_flags(F_MEM)) {
        // a read of memory (mcopy's), made before the write: what the memory
        // has there then - the write may change it
        if (*n == 32 && value.is(Op::MEM, 1) && value[0].is(Op::RANGE, 2) && value[0][1] == Value::small(32)) {
            Value src = value[0][0];
            value = small_place(src) ? read_memory(src) : Value();
        } else {
            value = Value();
        }
    }
    const u64 st = *s, end = *s + *n;
    bool overlap = false;
    for (const Cell* c = head_; c && !overlap; c = c->next) {
        const Fact& f = c->f;
        if (f.kind != FactKind::Mem) continue;
        u64 fs = u64(f.a.small_val()), fe = fs + u64(f.b.small_val());
        overlap = !(fe <= st || end <= fs);
    }
    Fact nf{FactKind::Mem, Value::small(i64(st)), Value::small(i64(*n)), value};
    if (!overlap) return with(nf);
    SmallVec<const Cell*, 32> cs;
    cells_of(head_, cs);
    Facts r;
    auto push = [&](const Fact& f, const Cell* same) {
        r.head_ = cons(f, r.head_, same);
        ++r.n_;
        r.nbounds_ += r.head_->nb;
    };
    for (const Cell* c : cs) {
        const Fact& f = c->f;
        if (f.kind != FactKind::Mem) {
            push(f, c);
            continue;
        }
        u64 fs = u64(f.a.small_val()), fe = fs + u64(f.b.small_val());
        if (fe <= st || end <= fs) {
            push(f, c);
            continue;
        }
        // what the write leaves of a value written before, on each side
        if (fs < st) {
            u64 k = st - fs;
            i64 off = i64(8 * (fe - st));
            Value nv = f.c.nil() || f.c == Value::small(0) ? f.c : mask_value(f.c, i64(8 * k), off, -off);
            push(Fact{FactKind::Mem, f.a, Value::small(i64(k)), nv}, nullptr);
        }
        if (end < fe) {
            u64 k = fe - end;
            Value nv = f.c.nil() || f.c == Value::small(0) ? f.c : mask_value(f.c, i64(8 * k));
            push(Fact{FactKind::Mem, Value::small(i64(end)), Value::small(i64(k)), nv}, nullptr);
        }
    }
    push(nf, nullptr);
    return r;
}

Value Facts::read_memory(Value addr) const {
    auto a = small_place(addr);
    if (!a) return Value();
    bool any = false;
    for (const Cell* c = head_; c && !any; c = c->next)
        any = c->f.kind == FactKind::Mem || c->f.kind == FactKind::Fresh;
    if (!any) return Value();
    const u64 end = *a + 32;
    SmallVec<const Cell*, 32> cs;
    cells_of(head_, cs);
    Value res = Value::small(0);
    u64 covered = 0;
    for (const Cell* c : cs) {
        const Fact& f = c->f;
        if (f.kind != FactKind::Mem) continue;
        u64 fs = u64(f.a.small_val()), fe = fs + u64(f.b.small_val());
        u64 lo = std::max(fs, *a), hi = std::min(fe, end);
        if (lo >= hi) continue;
        if (f.c.nil()) return Value();
        // the bytes lo..hi of the value of fs..fe, to their place in the word
        i64 off = i64(8 * (fe - hi));
        res = bor(res, mask_value(f.c, i64(8 * (hi - lo)), off, i64(8 * (end - hi)) - off));
        covered += hi - lo;
    }
    if (covered < 32 && !fresh()) return Value();
    return res;
}

bool Facts::known_zeroes(Value start, Value size) const {
    auto s = small_place(start);
    auto n = small_place(size);
    if (!s || !n || *n == 0 || *n > limits::MAX_ZEROES_SIZE) return false;
    for (u64 off = 0; off < *n; off += 32) {
        poll();
        Value w = read_memory(Value::small(i64(*s + off)));
        if (w != Value::small(0)) return false;
    }
    return true;
}

// ---- bounds ---------------------------------------------------------------------------

std::optional<EvmInt> Facts::upper_bound(Value v) const {
    std::optional<EvmInt> res;
    each_bound([&](Value x, Value, Value hi) {
        if (x != v) return;
        EvmInt n(hi);
        if (!res || n < *res) res = n;
    });
    return res;
}

std::optional<EvmInt> Facts::bound(Value v) const {
    check_stack();
    static const EvmInt two128 = EvmInt::pow2(128);
    auto ok = [&](const EvmInt& t) { return t.sign() >= 0 && t < two128; };
    if (v.is(Op::MIN)) {
        // (the size of what a call wrote)
        std::optional<EvmInt> top;
        for (Value x : v.args()) {
            std::optional<EvmInt> t = x.is_int() ? std::optional<EvmInt>(EvmInt(x)) : bound(x);
            if (t && (!top || *t < *top)) top = *t;
        }
        if (top && ok(*top)) return top;
        return std::nullopt;
    }
    // the known conditions and what v is made of: its range (python's
    // upper_bound, else max_value_bits - the range has both)
    Range r = range(v, Top::Word, this);
    if (ok(r.hi)) return r.hi;
    return std::nullopt;
}

std::optional<Facts::Span> Facts::write_range(Value start, Value size) const {
    static const EvmInt two128 = EvmInt::pow2(128);
    static const EvmInt two64 = EvmInt::pow2(64);
    std::optional<EvmInt> size_top = size.is_int() ? std::optional<EvmInt>(EvmInt(size)) : bound(size);
    if (!size_top) return std::nullopt;
    if (start.is_int()) {
        EvmInt s(start);
        return Span{s, s + *size_top};
    }
    if (!start.is(Op::ADD)) return std::nullopt;
    SmallVec<Value, 8> bases, rest;
    for (Value t : start.args()) (t.is_int() ? bases : rest).push_back(t);
    if (bases.size() != 1 || rest.empty()) return std::nullopt;
    EvmInt base(bases[0]);
    if (base.sign() < 0 || !(base < two128)) return std::nullopt;
    Value offset = rest.size() == 1 ? rest[0] : add(rest.span());
    EvmInt k(1);
    Value i = offset;
    if (offset.is(Op::MUL, 2) && offset[0].is_int()) {
        k = EvmInt(offset[0]);
        i = offset[1];
    } else if (offset.is(Op::MASK_SHL, 4) && offset[0].is_small() && offset[1] == Value::small(0) &&
               offset[2].is_small() && offset[2].small_val() >= 0 && offset[2].small_val() < 256) {
        // (i & mask) << shl: at most i << shl
        k = EvmInt::pow2(u64(offset[2].small_val()));
        i = offset[3];
    }
    auto top = bound(i);
    if (top && k.sign() > 0 && k < two64) return Span{base, base + k * *top + *size_top};
    return std::nullopt;
}

u32 Facts::var_bits(Value var) const noexcept {
    for (const Cell* c = head_; c; c = c->next)
        if (c->f.kind == FactKind::VarBits && c->f.a == var) return u32(c->f.b.small_val());
    return 0;
}

}  // namespace pan::alg
