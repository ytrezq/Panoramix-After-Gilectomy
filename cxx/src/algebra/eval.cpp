// Concrete evaluation (eval.hpp).
#include "algebra/eval.hpp"

#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/errors.hpp"
#include "core/smallvec.hpp"

namespace pan::alg {

// ---------------------------------------------------------------- ints

Value word_int(Value v) {
    if (v.is_small() && v.small_val() >= 0) return v;
    return EvmInt(v).word().value();
}

Value signed_int(Value v) {
    if (v.is_small()) return v;  // |small| < 2^62
    return EvmInt(v).to_signed().value();
}

i64 clamp_field(const Word256& x) noexcept {
    constexpr u64 LIM = 4096;
    if (x.limb[3] >> 63) {
        Word256 n = pan::sub(Word256{}, x);  // |x|
        if (n.limb[1] | n.limb[2] | n.limb[3] || n.limb[0] > LIM) return -i64(LIM);
        return -i64(n.limb[0]);
    }
    if (x.limb[1] | x.limb[2] | x.limb[3] || x.limb[0] > LIM) return i64(LIM);
    return i64(x.limb[0]);
}

// ---------------------------------------------------------------- words

namespace {

inline Word256 w_of(u64 v) noexcept { return Word256::of(v); }
inline Word256 w_bool(bool b) noexcept { return Word256::of(b ? 1 : 0); }
inline Word256 w_ones() noexcept { return Word256{{~u64(0), ~u64(0), ~u64(0), ~u64(0)}}; }

// bits [lo, hi) set, 0 <= lo <= hi <= 256
Word256 bit_range(u32 lo, u32 hi) noexcept {
    Word256 r{};
    for (u32 i = 0; i < 4; ++i) {
        u32 a = i * 64, b = a + 64;
        u32 l = lo > a ? lo : a, h = hi < b ? hi : b;
        if (l >= h) continue;
        u32 n = h - l;
        u64 m = n == 64 ? ~u64(0) : ((u64(1) << n) - 1);
        r.limb[i] = m << (l - a);
    }
    return r;
}

}  // namespace

Word256 mask_word(i64 size, i64 off) noexcept {
    if (off < 0) {
        size += off;
        off = 0;
    }
    if (size <= 0 || off >= 256) return Word256{};
    i64 hi = off + size > 256 ? 256 : off + size;
    return bit_range(u32(off), u32(hi));
}

Word256 mask_shl_word(i64 size, i64 off, i64 shl, const Word256& x) noexcept {
    Word256 v = pan::band(x, mask_word(size, off));
    if (shl >= 256 || shl <= -256) return Word256{};
    if (shl >= 0) return pan::shl(w_of(u64(shl)), v);
    return pan::shr(w_of(u64(-shl)), v);
}

Word256 mask_shl_word(const Word256& size, const Word256& off, const Word256& shl, const Word256& x) noexcept {
    return mask_shl_word(clamp_field(size), clamp_field(off), clamp_field(shl), x);
}

bool is_pure(Op op) noexcept {
    switch (op) {
        case Op::ADD: case Op::MUL: case Op::SUB: case Op::DIV: case Op::SDIV: case Op::MOD:
        case Op::SMOD: case Op::ADDMOD: case Op::MULMOD: case Op::EXP: case Op::SIGNEXTEND:
        case Op::LT: case Op::GT: case Op::SLT: case Op::SGT: case Op::EQ: case Op::ISZERO:
        case Op::AND: case Op::OR: case Op::XOR: case Op::NOT: case Op::BYTE: case Op::SHL:
        case Op::SHR: case Op::SAR: case Op::CLZ: case Op::MASK_SHL: case Op::BOOL: case Op::LE:
        case Op::GE: case Op::SLE: case Op::SGE: case Op::MAX: case Op::MIN: case Op::LAND:
        case Op::LOR:
            return true;
        default:
            return false;
    }
}

std::optional<Word256> eval_op(Op op, std::span<const Word256> a) noexcept {
    if (!is_pure(op)) return std::nullopt;
    const OpInfo& in = info(op);
    if (a.size() < in.arity_min || (in.arity_max != 255 && a.size() > in.arity_max)) return std::nullopt;
    switch (op) {
        case Op::ADD: {
            Word256 r = a[0];
            for (usize i = 1; i < a.size(); ++i) r = pan::add(r, a[i]);
            return r;
        }
        case Op::MUL: {
            Word256 r = a[0];
            for (usize i = 1; i < a.size(); ++i) r = pan::mul(r, a[i]);
            return r;
        }
        case Op::AND: {
            Word256 r = a[0];
            for (usize i = 1; i < a.size(); ++i) r = pan::band(r, a[i]);
            return r;
        }
        case Op::OR: {
            Word256 r = a[0];
            for (usize i = 1; i < a.size(); ++i) r = pan::bor(r, a[i]);
            return r;
        }
        case Op::MAX: {
            Word256 r = a[0];
            for (usize i = 1; i < a.size(); ++i)
                if (a[i] > r) r = a[i];
            return r;
        }
        case Op::MIN: {
            Word256 r = a[0];
            for (usize i = 1; i < a.size(); ++i)
                if (a[i] < r) r = a[i];
            return r;
        }
        case Op::SUB: return pan::sub(a[0], a[1]);
        case Op::DIV: return pan::div(a[0], a[1]);
        case Op::SDIV: return pan::sdiv(a[0], a[1]);
        case Op::MOD: return pan::mod(a[0], a[1]);
        case Op::SMOD: return pan::smod(a[0], a[1]);
        case Op::ADDMOD: return pan::addmod(a[0], a[1], a[2]);
        case Op::MULMOD: return pan::mulmod(a[0], a[1], a[2]);
        case Op::EXP: return pan::exp(a[0], a[1]);
        case Op::SIGNEXTEND: return pan::signextend(a[0], a[1]);
        case Op::LT: return pan::lt(a[0], a[1]);
        case Op::GT: return pan::gt(a[0], a[1]);
        case Op::SLT: return pan::slt(a[0], a[1]);
        case Op::SGT: return pan::sgt(a[0], a[1]);
        case Op::EQ: return pan::eq(a[0], a[1]);
        case Op::ISZERO: return pan::iszero(a[0]);
        case Op::XOR: return pan::bxor(a[0], a[1]);
        case Op::NOT: return pan::bnot(a[0]);
        case Op::BYTE: return pan::byte(a[0], a[1]);
        case Op::SHL: return pan::shl(a[0], a[1]);
        case Op::SHR: return pan::shr(a[0], a[1]);
        case Op::SAR: return pan::sar(a[0], a[1]);
        case Op::CLZ: return pan::clz(a[0]);
        case Op::MASK_SHL: return mask_shl_word(a[0], a[1], a[2], a[3]);
        case Op::BOOL: return w_bool(!a[0].is_zero());
        case Op::LE: return w_bool(a[0] <= a[1]);
        case Op::GE: return w_bool(a[0] >= a[1]);
        case Op::SLE: return w_bool(pan::sgt(a[0], a[1]).is_zero());
        case Op::SGE: return w_bool(pan::slt(a[0], a[1]).is_zero());
        case Op::LAND: return a[0].is_zero() ? a[0] : a[1];
        case Op::LOR: return a[0].is_zero() ? a[1] : a[0];
        default: return std::nullopt;
    }
}

// ---------------------------------------------------------------- eval_const

namespace {

struct ConstSlot {
    Word256 w;
    u32 state;  // 1 constant, 2 not
};

struct EvalState final : ModuleState {
    Memo<Value, ConstSlot> memo;
    // (pure: nothing to forget at clear_caches)
};

std::optional<Word256> const_rec(Value v, EvalState& st) {
    if (v.is_int()) return Word256::from_value(v);
    if (v.is_bool()) return Word256::of(v.is_true() ? 1 : 0);
    if (!v.is_expr() || !is_pure(v.op())) return std::nullopt;
    if (const ConstSlot* s = st.memo.find(v)) {
        if (s->state == 1) return s->w;
        return std::nullopt;
    }
    check_stack();
    // a pure op of constants (no flags: no leaf, no name) - else not constant
    std::optional<Word256> res;
    if (v.flags() == 0) {
        SmallVec<Word256, 4> args;
        bool ok = true;
        for (Value a : v.args()) {
            auto w = const_rec(a, st);
            if (!w) {
                ok = false;
                break;
            }
            args.push_back(*w);
        }
        if (ok) res = eval_op(v.op(), args.span());
    }
    ConstSlot& s = st.memo[v];
    if (res) {
        s.w = *res;
        s.state = 1;
    } else {
        s.state = 2;
    }
    return res;
}

}  // namespace

std::optional<Word256> eval_const(Value v) {
    if (v.is_int()) return Word256::from_value(v);
    if (v.is_bool()) return Word256::of(v.is_true() ? 1 : 0);
    if (!v.is_expr()) return std::nullopt;
    return const_rec(v, cx().state<EvalState>());
}

// ---------------------------------------------------------------- Evaluator

std::optional<Word256> Evaluator::run(Value v) {
    if (v.is_int()) return Word256::from_value(v);
    if (v.is_bool()) return Word256::of(v.is_true() ? 1 : 0);
    if (v.nil()) return std::nullopt;
    if (const Slot* s = memo_.find(v)) {
        if (s->state == 1) return s->w;
        return std::nullopt;
    }
    check_stack();
    std::optional<Word256> res;
    Op op = v.op();
    if (v.is_expr() && is_pure(op)) {
        if (op == Op::LAND || op == Op::LOR) {
            // python's and / or: the second operand only when it decides
            if (v.size() == 2) {
                auto c = run(v[0]);
                if (c) {
                    bool second = op == Op::LAND ? !c->is_zero() : c->is_zero();
                    res = second ? run(v[1]) : c;
                }
            }
        } else {
            SmallVec<Word256, 4> args;
            bool ok = true;
            for (Value a : v.args()) {
                auto w = run(a);
                if (!w) {
                    ok = false;
                    break;
                }
                args.push_back(*w);
            }
            if (ok) res = eval_op(op, args.span());
        }
    } else {
        res = env_.value(v, *this);
    }
    Slot& s = memo_[v];
    if (res) {
        s.w = *res;
        s.state = 1;
    } else {
        s.state = 2;
    }
    return res;
}

std::optional<Word256> Evaluator::try_eval(Value v) { return run(v); }

Word256 Evaluator::operator()(Value v) {
    auto r = run(v);
    if (!r) throw Unsupported("eval: a value the environment doesn't know");
    return *r;
}

Word256 eval(Value v, Env& env) {
    Evaluator ev(env);
    return ev(v);
}

// ---------------------------------------------------------------- envs

namespace {

inline u64 splitmix(u64& s) noexcept {
    u64 z = (s += 0x9e3779b97f4a7c15ull);
    z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9ull;
    z = (z ^ (z >> 27)) * 0x94d049bb133111ebull;
    return z ^ (z >> 31);
}

Word256 pow2_word(u32 k) noexcept {
    Word256 r{};
    if (k < 256) r.limb[k / 64] = u64(1) << (k % 64);
    return r;
}

}  // namespace

Word256 RandomEnv::word_for(u64 seed, u64 k) noexcept {
    u64 s = seed * 0xd1b54a32d192ed03ull ^ k;
    u64 r = splitmix(s);
    Word256 w{};
    switch (r & 7) {
        case 0:
        case 1: {  // an edge value
            static constexpr u64 small[] = {0, 1, 2, 3, 7, 8, 31, 32, 64, 255, 256, 4096};
            u64 sel = (r >> 3) % 24;
            if (sel < 12) return Word256::of(small[sel]);
            u32 bit = u32((r >> 8) % 257);
            switch (sel) {
                case 12: return pow2_word(255);                           // 2^255
                case 13: return pan::bnot(Word256{});                     // 2^256 - 1
                case 14: return pan::sub(pow2_word(255), Word256::of(1));  // 2^255 - 1
                case 15: return pan::sub(Word256{}, Word256::of(2));      // -2
                case 16: return pan::add(pow2_word(255), Word256::of(1));
                case 17: return pan::sub(pow2_word(160), Word256::of(1));  // address mask
                case 18: return pow2_word(bit);                            // 2^k (0 for 256)
                case 19: return pan::sub(pow2_word(bit), Word256::of(1));  // 2^k - 1
                case 20: return pan::sub(Word256{}, Word256::of((r >> 20) % 300));  // small negative
                case 21: return pan::bnot(pan::sub(pow2_word(bit), Word256::of(1)));  // ~(2^k - 1)
                default: return Word256::of((r >> 20) % 1000);
            }
        }
        case 2:
        case 3: {  // a random bit length
            u32 len = u32((r >> 3) % 257);
            for (int i = 0; i < 4; ++i) w.limb[i] = splitmix(s);
            if (len < 256) w = pan::band(w, pan::sub(pow2_word(len), Word256::of(1)));
            return w;
        }
        default:  // a random word
            for (int i = 0; i < 4; ++i) w.limb[i] = splitmix(s);
            return w;
    }
}

std::optional<Word256> RandomEnv::value(Value v, Evaluator&) { return word_for(seed_, v.hash()); }

std::optional<Word256> MapEnv::value(Value v, Evaluator& ev) {
    if (const Word256* w = map_.find(v)) return *w;
    if (fallback_) return fallback_->value(v, ev);
    return std::nullopt;
}

}  // namespace pan::alg
