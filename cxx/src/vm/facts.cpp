// What the VM knows on a path: python vm.py's known, write_memory,
// read_memory, known_zeroes, forget, is_known, decided, upper_bound, bound,
// write_range; arithmetic.eval_bool; memloc.max_value_bits.
#include "vm/facts.hpp"

#include <algorithm>
#include <new>

#include "algebra/construct.hpp"
#include "algebra/eval.hpp"
#include "algebra/masks.hpp"
#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/intops.hpp"

namespace pan::vm {

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

// python memloc.max_value_bits, a budget of nodes visited (past it: 256,
// which is always true)
struct BitsWalk {
    const PathFacts* facts;
    u32 budget = 4096;

    u32 bits(Value v) {
        check_stack();
        if (budget == 0) return 256;
        --budget;
        if (facts && v.is_name()) {
            if (u32 b = facts->var_bits(v)) return b;
        }
        if (v.is_int()) {
            if (int_sign(v) < 0) return 256;
            EvmInt x(v);
            u64 n = x.bit_length();
            return n <= 256 ? u32(n) : 256;
        }
        if (v.is_bool()) return v.is_true() ? 1 : 0;
        if (v.is_leaf()) {
            switch (v.op()) {
                case Op::CALLDATASIZE:
                case Op::RETURNDATASIZE:
                case Op::CODESIZE:
                case Op::MSIZE:
                case Op::GAS:
                    return 64;
                default:
                    return alg::max_bits(v);
            }
        }
        if (!v.is_expr()) return 256;
        switch (v.op()) {
            case Op::ADD: {
                u32 top = 0;
                for (Value t : v.args()) top = std::max(top, bits(t));
                u32 n = v.size() - 1, extra = 0;
                while (n) {
                    ++extra;
                    n >>= 1;
                }
                return std::min<u32>(256, top + extra);
            }
            case Op::MUL: {
                u32 s = 0;
                for (Value t : v.args()) s = std::min<u32>(256, s + bits(t));
                return s;
            }
            case Op::DIV:
                return bits(v[0]);
            case Op::MOD:
                return std::min(bits(v[0]), bits(v[1]));
            case Op::AND:
            case Op::MIN: {
                u32 m = 256;
                for (Value t : v.args()) m = std::min(m, bits(t));
                return m;
            }
            case Op::OR:
            case Op::XOR: {
                u32 m = 0;
                for (Value t : v.args()) m = std::max(m, bits(t));
                return m;
            }
            case Op::MASK_SHL:
                if (v[0].is_small() && v[1].is_small() && v[2].is_small()) {
                    i64 size = v[0].small_val(), off = v[1].small_val(), shl = v[2].small_val();
                    i64 top = std::min<i64>(off + size, bits(v[3]));
                    if (top <= off) return 0;
                    i64 r = std::min<i64>(top + shl, 256);
                    return r < 0 ? 0 : u32(r);
                }
                return 256;
            case Op::STORAGE:
                if (v[0].is_small() && v[1].is_small() && v[1].small_val() >= 0 && v[0].small_val() >= 0 &&
                    v[0].small_val() <= 256)
                    return u32(v[0].small_val());
                return alg::max_bits(v);
            default:
                return alg::max_bits(v);
        }
    }
};

}  // namespace

Value mask_value(Value v, i64 size, i64 off, i64 shl) {
    if (size == 256 && off == 0 && shl == 0) return v;
    return alg::mask(size, off, shl, v);
}

u32 max_value_bits(Value v, const PathFacts* facts) {
    BitsWalk w{facts};
    return w.bits(v);
}

// ---- eval_bool ----------------------------------------------------------------

namespace {

// a <= b for every value of what they're made of, as words (python
// algebra.proven_le with is_word: here only what is certain without ranges)
bool proven_le_words(Value a, Value b) {
    if (a == b) return true;
    if (a.is_int() && b.is_int()) {
        if (int_sign(a) < 0 || int_sign(b) < 0) return false;
        return int_cmp(a, b) <= 0;
    }
    return false;
}

std::optional<bool> eval_bool_rec(Value exp, Value iz_exp, Value kt, Value iz_kt) {
    check_stack();
    if (exp == kt) return true;
    if (iz_exp == kt) return false;
    if (exp == iz_kt) return false;
    if (exp.is_bool()) return exp.is_true();
    if (exp.is_int()) return !Word256::from_value(exp).is_zero();
    if (!exp.is_expr()) return std::nullopt;
    switch (exp.op()) {
        case Op::BOOL:
            return eval_bool_rec(exp[0], alg::iszero(exp[0]), kt, iz_kt);
        case Op::ISZERO: {
            auto e = eval_bool_rec(exp[0], alg::iszero(exp[0]), kt, iz_kt);
            if (e) return !*e;
            break;
        }
        case Op::OR: {
            bool res = false;
            for (Value e : exp.args()) {
                auto r = eval_bool_rec(e, alg::iszero(e), kt, iz_kt);
                if (!r) return std::nullopt;
                res = res || *r;
            }
            return res;
        }
        case Op::AND:
            // (bitwise too: only an operand known to be 0 decides it)
            for (Value e : exp.args()) {
                auto r = eval_bool_rec(e, alg::iszero(e), kt, iz_kt);
                if (r && !*r) return false;
            }
            break;
        default:
            break;
    }
    if ((exp.is(Op::LE, 2) || exp.is(Op::LT, 2)) && kt.is(exp.op(), 2) && exp[0] == kt[0]) {
        // x < b where x < a is known: when a <= b, as words
        if (proven_le_words(kt[1], exp[1])) return true;
    }
    if (auto w = alg::eval_const(exp)) return !w->is_zero();
    return std::nullopt;
}

}  // namespace

std::optional<bool> eval_bool(Value exp, Value fact) {
    Value kt = fact.is(Op::BOOL, 1) ? fact[0] : fact;
    return eval_bool_rec(exp, alg::iszero(exp), kt, alg::iszero(kt));
}

// ---- the list -------------------------------------------------------------------

const PathFacts::Cell* PathFacts::cons(const Fact& f, const Cell* next) {
    void* p = cx().arena.alloc_raw(sizeof(Cell));
    return new (p) Cell{next, f};
}

PathFacts PathFacts::with(const Fact& f) const {
    PathFacts r;
    Fact g = f;
    if (g.kind == FactKind::Cond && g.c.nil()) {
        // its negation, computed once (eval_bool compares with it)
        Value kt = g.a.is(Op::BOOL, 1) ? g.a[0] : g.a;
        g.c = alg::iszero(kt);
    }
    r.head_ = cons(g, head_);
    r.n_ = n_ + 1;
    return r;
}

bool PathFacts::contains(const Fact& f) const noexcept {
    for (const Cell* c = head_; c; c = c->next) {
        const Fact& g = c->f;
        if (g.kind != f.kind || g.a != f.a || g.b != f.b) continue;
        // (a condition's c is its cached negation)
        if (g.kind == FactKind::Cond || g.c == f.c) return true;
    }
    return false;
}

bool PathFacts::has(FactKind k) const noexcept {
    for (const Cell* c = head_; c; c = c->next)
        if (c->f.kind == k) return true;
    return false;
}

void PathFacts::to_vector(SmallVec<Fact, 32>& out) const {
    out.clear();
    for (const Cell* c = head_; c; c = c->next) out.push_back(c->f);
    std::reverse(out.begin(), out.end());
}

PathFacts PathFacts::from(std::span<const Fact> oldest_first) {
    PathFacts r;
    for (const Fact& f : oldest_first) {
        r.head_ = cons(f, r.head_);
        ++r.n_;
    }
    return r;
}

bool PathFacts::operator==(const PathFacts& o) const noexcept {
    if (n_ != o.n_) return false;
    const Cell* a = head_;
    const Cell* b = o.head_;
    for (; a && b; a = a->next, b = b->next) {
        if (a == b) return true;  // a shared tail
        if (!(a->f == b->f)) return false;
    }
    return a == b;
}

std::optional<bool> PathFacts::is_known(Value exp) const {
    if (exp.is_int()) return !Word256::from_value(exp).is_zero();
    if (exp.is_bool()) return exp.is_true();
    Value iz_exp;
    for (const Cell* c = head_; c; c = c->next) {
        const Fact& f = c->f;
        if (f.kind != FactKind::Cond) continue;
        poll();
        if (iz_exp.nil()) iz_exp = alg::iszero(exp);
        Value kt = f.a.is(Op::BOOL, 1) ? f.a[0] : f.a;
        if (auto r = eval_bool_rec(exp, iz_exp, kt, f.c)) return r;
    }
    return std::nullopt;
}

Value PathFacts::decided(Value exp) const {
    if (exp.is_int()) return exp;
    auto r = is_known(exp);
    if (r && !*r) return Value::small(0);
    if (r && *r && alg::is_bool(exp)) return Value::small(1);
    return exp;
}

PathFacts PathFacts::forget(Forget what) const {
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
    SmallVec<Fact, 32> v, out;
    to_vector(v);
    for (Fact f : v) {
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
        out.push_back(f);
    }
    return from(out.span());
}

PathFacts PathFacts::without_memory() const {
    bool any = false;
    for (const Cell* c = head_; c && !any; c = c->next)
        any = c->f.kind == FactKind::Mem || c->f.kind == FactKind::Fresh;
    if (!any) return *this;
    SmallVec<Fact, 32> v, out;
    to_vector(v);
    for (const Fact& f : v)
        if (f.kind != FactKind::Mem && f.kind != FactKind::Fresh) out.push_back(f);
    return from(out.span());
}

// ---- memory -------------------------------------------------------------------------

PathFacts PathFacts::write_memory(Value start, Value size, Value value) const {
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
    SmallVec<Fact, 32> v, out;
    to_vector(v);
    for (const Fact& f : v) {
        if (f.kind != FactKind::Mem) {
            out.push_back(f);
            continue;
        }
        u64 fs = u64(f.a.small_val()), fe = fs + u64(f.b.small_val());
        if (fe <= st || end <= fs) {
            out.push_back(f);
            continue;
        }
        // what the write leaves of a value written before, on each side
        if (fs < st) {
            u64 k = st - fs;
            i64 off = i64(8 * (fe - st));
            Value nv = f.c.nil() || f.c == Value::small(0) ? f.c : mask_value(f.c, i64(8 * k), off, -off);
            out.push_back(Fact{FactKind::Mem, f.a, Value::small(i64(k)), nv});
        }
        if (end < fe) {
            u64 k = fe - end;
            Value nv = f.c.nil() || f.c == Value::small(0) ? f.c : mask_value(f.c, i64(8 * k));
            out.push_back(Fact{FactKind::Mem, Value::small(i64(end)), Value::small(i64(k)), nv});
        }
    }
    out.push_back(nf);
    return from(out.span());
}

Value PathFacts::read_memory(Value addr) const {
    auto a = small_place(addr);
    if (!a) return Value();
    bool any = false;
    for (const Cell* c = head_; c && !any; c = c->next)
        any = c->f.kind == FactKind::Mem || c->f.kind == FactKind::Fresh;
    if (!any) return Value();
    const u64 end = *a + 32;
    SmallVec<Fact, 32> v;
    to_vector(v);
    Value res = Value::small(0);
    u64 covered = 0;
    for (const Fact& f : v) {
        if (f.kind != FactKind::Mem) continue;
        u64 fs = u64(f.a.small_val()), fe = fs + u64(f.b.small_val());
        u64 lo = std::max(fs, *a), hi = std::min(fe, end);
        if (lo >= hi) continue;
        if (f.c.nil()) return Value();
        // the bytes lo..hi of the value of fs..fe, to their place in the word
        i64 off = i64(8 * (fe - hi));
        res = alg::bor(res, mask_value(f.c, i64(8 * (hi - lo)), off, i64(8 * (end - hi)) - off));
        covered += hi - lo;
    }
    if (covered < 32 && !fresh()) return Value();
    return res;
}

bool PathFacts::known_zeroes(Value start, Value size) const {
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

std::optional<EvmInt> PathFacts::upper_bound(Value v) const {
    std::optional<EvmInt> res;
    auto take = [&](const EvmInt& n) {
        if (!res || n < *res) res = n;
    };
    for (const Cell* c = head_; c; c = c->next) {
        const Fact& f = c->f;
        if (f.kind != FactKind::Cond) continue;
        Value fact = f.a;
        bool neg = false;
        if (fact.is(Op::ISZERO, 1)) {
            neg = true;
            fact = fact[0];
        }
        if (!fact.is_expr() || fact.size() != 2) continue;
        Op op = fact.op();
        if (fact[0] == v && fact[1].is_int()) {
            EvmInt n(fact[1]);
            if (!neg && op == Op::LT) take(n - EvmInt(1));
            if (!neg && op == Op::LE) take(n);
            if (neg && op == Op::GT) take(n);
            if (neg && op == Op::GE) take(n - EvmInt(1));
        } else if (fact[1] == v && fact[0].is_int()) {
            EvmInt n(fact[0]);
            if (!neg && op == Op::GT) take(n - EvmInt(1));
            if (!neg && op == Op::GE) take(n);
            if (neg && op == Op::LT) take(n);
            if (neg && op == Op::LE) take(n - EvmInt(1));
        }
    }
    return res;
}

std::optional<EvmInt> PathFacts::bound(Value v) const {
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
    std::optional<EvmInt> top = upper_bound(v);
    if (!top) {
        u32 b = max_value_bits(v, this);
        if (b <= 128) top = EvmInt::pow2(b) - EvmInt(1);
    }
    if (top && ok(*top)) return top;
    return std::nullopt;
}

std::optional<PathFacts::Span> PathFacts::write_range(Value start, Value size) const {
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
    Value offset = rest.size() == 1 ? rest[0] : alg::add(rest.span());
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

u32 PathFacts::var_bits(Value var) const noexcept {
    for (const Cell* c = head_; c; c = c->next)
        if (c->f.kind == FactKind::VarBits && c->f.a == var) return u32(c->f.b.small_val());
    return 0;
}

}  // namespace pan::vm
