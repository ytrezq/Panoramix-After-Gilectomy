// The semantics of the storage forms on concrete values (storage.hpp:
// locate): the trace machine's and the analysis' check's one definition.
#include <cstring>

#include "core/context.hpp"
#include "core/dump.hpp"
#include "core/errors.hpp"
#include "exec/machine.hpp"
#include "storage/storage.hpp"

namespace pan {

u16 StorageLayout::packed_width(u32 type) const noexcept {
    if (type >= types.size()) return 256;
    const StorageType& t = types[type];
    if (t.kind != StorageType::Kind::Value) return 256;
    const u16 w = t.width;
    if (w >= 8 && w < 256 && 256 % w == 0) return w;
    return 256;
}

namespace storage {

namespace {

// a form the layout doesn't have: the stage that made it broke the IR
[[noreturn]] PAN_COLD void malformed(const char* why, Value loc) {
    std::string s = "storage: ";
    s += why;
    s += ": ";
    std::string d = dump(loc);
    if (d.size() > 200) {
        d.resize(200);
        d += "...";
    }
    s += d;
    throw InternalError(s);
}

bool is_bytes_expr(Value v) noexcept { return v.is_bytes() || (v.is_expr() && info(v.op()).sort == Sort::Bytes); }

// a small int Value as a word (two's complement)
Word256 small_word(i64 n) noexcept {
    const u64 hi = n < 0 ? ~u64(0) : 0;
    return Word256{{u64(n), hi, hi, hi}};
}

// keccak of a and b's 32 bytes each, a first
Word256 keccak_pair(const Word256& a, const Word256& b) noexcept {
    u8 buf[64];
    a.to_be(buf);
    b.to_be(buf + 32);
    return exec::keccak256(std::span<const u8>(buf, 64));
}

}  // namespace

Word256 bytes_length(const Word256& s) noexcept {
    if (s.limb[0] & 1) return pan::shr(Word256::of(1), s);
    return Word256::of((s.limb[0] & 0xff) >> 1);
}

Word256 keccak_word(const Word256& w) noexcept {
    u8 buf[32];
    w.to_be(buf);
    return exec::keccak256(std::span<const u8>(buf, 32));
}

Place locate(const StorageLayout& layout, Value loc, Eval& eval) {
    check_stack();
    switch (loc.op()) {
        case Op::SV: {
            if (!loc.is(Op::SV, 1) || !loc[0].is_name(NameKind::STORVAR) || loc[0].name_id() >= layout.vars.size())
                malformed("not a variable of the layout", loc);
            const StorageVar& v = layout.vars[loc[0].name_id()];
            return Place{v.slot, v.off, false, v.type};
        }
        case Op::SR:
            if (!loc.is(Op::SR, 1)) break;
            return Place{eval.word(loc[0]), 0, false, std::nullopt};
        case Op::SL:
        case Op::SBL: {
            if (loc.size() != 1) break;
            Place p = locate(layout, loc[0], eval);
            if (p.length) malformed("the length of a length", loc);
            p.type.reset();
            p.length = loc.op() == Op::SBL;
            return p;
        }
        case Op::SF: {
            if (!loc.is(Op::SF, 2)) break;
            Place p = locate(layout, loc[0], eval);
            if (p.length) malformed("a field of a length", loc);
            const Value n = loc[1];
            // bit(base) + n, a signed word: the slot moves by its floor / 256
            const Word256 t = pan::add(n.is_small() ? small_word(n.small_val()) : eval.word(n), Word256::of(p.bit));
            p.slot = pan::add(p.slot, pan::sar(Word256::of(8), t));
            p.bit = u32(t.limb[0] & 255);
            p.type.reset();
            return p;
        }
        case Op::SI: {
            if (!loc.is(Op::SI, 2)) break;
            const Place base = locate(layout, loc[0], eval);
            if (base.length || !base.type || *base.type >= layout.types.size())
                malformed("an element of a place of no type", loc);
            const StorageType& t = layout.types[*base.type];
            const Value key = loc[1];
            switch (t.kind) {
                case StorageType::Kind::Mapping: {
                    std::vector<u8> buf;
                    u8 w[32];
                    if (layout.lang == Lang::Vyper) {
                        base.slot.to_be(w);
                        buf.insert(buf.end(), w, w + 32);
                    }
                    if (is_bytes_expr(key)) {
                        eval.bytes(key, buf);
                    } else {
                        eval.word(key).to_be(w);
                        buf.insert(buf.end(), w, w + 32);
                    }
                    if (layout.lang != Lang::Vyper) {
                        base.slot.to_be(w);
                        buf.insert(buf.end(), w, w + 32);
                    }
                    return Place{exec::keccak256(buf), 0, false, t.elem};
                }
                case StorageType::Kind::Bytes:
                    return Place{pan::add(keccak_word(base.slot), eval.word(key)), 0, false, std::nullopt};
                case StorageType::Kind::Array:
                case StorageType::Kind::Fixed: {
                    const Word256 start = t.kind == StorageType::Kind::Array ? keccak_word(base.slot) : base.slot;
                    const Word256 i = eval.word(key);
                    const u16 w = layout.packed_width(t.elem);
                    if (w < 256) {
                        const Word256 per = Word256::of(256 / w);
                        const Word256 q = pan::div(i, per), r = pan::mod(i, per);
                        return Place{pan::add(start, q), u32(w * r.limb[0]), false, t.elem};
                    }
                    return Place{pan::add(start, pan::mul(i, Word256::of(t.stride))), 0, false, t.elem};
                }
                case StorageType::Kind::Value:
                case StorageType::Kind::Struct:
                    break;
            }
            malformed("an element of what has none", loc);
        }
        default:
            break;
    }
    malformed("not a location", loc);
}

}  // namespace storage
}  // namespace pan
