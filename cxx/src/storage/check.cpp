// The check of a printed access (python storage.py: World, ev, evb, read,
// read_loc, access_value, checks): the slot and the bits the form denotes -
// by storage::locate, the semantics the trace machine runs - must be those
// the access reads, in four worlds of random values for what the slot is
// computed from (keyed by the structural hash of each symbol: the same
// symbol the same value on both sides; odd worlds of 16-bit values, as
// indexes and lengths are).
#include "storage/check.hpp"

#include "algebra/eval.hpp"
#include "core/context.hpp"
#include "core/errors.hpp"
#include "exec/machine.hpp"
#include "storage/internal.hpp"

namespace pan::storage::detail {

World::World(u64 seed) : seed_(seed), ev_(*this) {}

World::~World() = default;

Word256 World::sym(Value v) const noexcept {
    const u64 h = v.hash();
    Word256 w;
    for (u64 i = 0; i < 4; ++i) w.limb[i] = hash_mix(h ^ hash_mix((seed_ + 1) * 0x9e3779b97f4a7c15ull + i));
    if (seed_ & 1) return Word256::of(w.limb[0] & 0xffff);
    return w;
}

void World::random_bytes(Value v, std::vector<u8>& out) const {
    // (python: 40 bytes of the symbol's, whatever its length)
    const Word256 a = sym(v);
    u8 b[32];
    a.to_be(b);
    out.insert(out.end(), b, b + 32);
    Word256 c;
    c.limb[0] = hash_mix(v.hash() + 0x51ed270b27f3a5c1ull * (seed_ + 7));
    c.to_be(b);
    out.insert(out.end(), b + 24, b + 32);
}

Word256 World::word(Value e) { return ev_(e); }

void World::bytes(Value e, std::vector<u8>& out) {
    check_stack();
    if (e.is(Op::SIZED, 2) && e[0].is_small() && e[0].small_val() > 0 && e[0].small_val() <= 32) {
        const usize n = usize(e[0].small_val());
        u8 b[32];
        ev_(e[1]).to_be(b);
        out.insert(out.end(), b + (32 - n), b + 32);
        return;
    }
    if (e.is(Op::DATA)) {
        for (Value x : e.args()) bytes(x, out);
        return;
    }
    if (is_bytes_expr(e)) {
        random_bytes(e, out);
        return;
    }
    u8 b[32];
    ev_(e).to_be(b);
    out.insert(out.end(), b, b + 32);
}

std::optional<Word256> World::value(Value v, alg::Evaluator& ev) {
    if (v.is(Op::SHA3)) {
        std::vector<u8> buf;
        for (Value x : v.args()) bytes(x, buf);
        return exec::keccak256(buf);
    }
    if (v.is(Op::SIZED, 2) && is_small(v[0], 32) && !is_bytes_expr(v[1])) return ev(v[1]);
    return sym(v);
}

Worlds::Worlds() {
    for (u64 s = 0; s < 4; ++s) w_.push_back(std::make_unique<World>(s));
}

Worlds::~Worlds() = default;

namespace {

struct Read {
    Word256 slot{};
    bool length = false;
    Word256 bit{}, size{};
};

// (slot, bit, size) a form reads; nullopt: not a form that reads as one
std::optional<Read> read_form(const StorageLayout& layout, Value f, World& w) {
    i64 d = 0;
    i64 size = 0;
    Value st = f;
    if (f.is(Op::MASK_SHL, 4)) {
        if (!f[0].is_small() || !f[1].is_small() || !f[2].is_small() || !f[3].is(Op::ST, 3)) return std::nullopt;
        size = f[0].small_val();
        d = f[1].small_val();
        if (f[2].small_val() != -d || d < 0 || size < 0) return std::nullopt;
        st = f[3];
        // (no bit past what the ST reads)
        if (!st[0].is_small() || size + d > st[0].small_val()) return std::nullopt;
    } else if (f.is(Op::ST, 3)) {
        if (!f[0].is_small()) return std::nullopt;
        size = f[0].small_val();
    } else {
        return std::nullopt;
    }
    if (size < 0 || size > 256) return std::nullopt;
    const Place p = locate(layout, st[1], w);
    return Read{p.slot, p.length, Word256::of(u64(p.bit) + u64(d)), Word256::of(u64(size))};
}

// (slot, bit, size) the access reads
Read read_access(const Access& a, World& w) {
    Read r;
    if (a.idx.is(Op::LENGTH, 1)) {
        const Value key = a.idx[0].is(Op::LOC, 1) ? a.idx[0][0] : a.idx[0];
        r.slot = w.word(key);
        r.length = true;
    } else {
        r.slot = w.word(a.idx);
    }
    r.bit = w.word(a.off);
    r.size = w.word(a.size);
    return r;
}

}  // namespace

bool Worlds::check(const StorageLayout& layout, Value f, const Access& a) {
    try {
        for (const auto& w : w_) {
            const std::optional<Read> got = read_form(layout, f, *w);
            if (!got) return false;
            const Read want = read_access(a, *w);
            if (got->slot != want.slot || got->length != want.length || got->bit != want.bit || got->size != want.size)
                return false;
        }
        return true;
    } catch (const Error&) {  // (locate's InternalError, the evaluator's Unsupported)
        return false;
    }
}

}  // namespace pan::storage::detail
