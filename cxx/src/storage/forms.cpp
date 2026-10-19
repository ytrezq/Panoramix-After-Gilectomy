// The printed accesses (python storage.py: form, field, element, raw).
#include "algebra/construct.hpp"
#include "core/context.hpp"
#include "core/errors.hpp"
#include "storage/internal.hpp"

namespace pan::storage::detail {

Value st_form(i64 size, Value loc, std::optional<i64> width) {
    return mk(Op::ST, small(size), loc, width ? small(*width) : None);
}

Value sv_form(u32 var) { return mk(Op::SV, Value::name(NameKind::STORVAR, var)); }

namespace {

// a member's or a field's number: small enough for its bits
constexpr i64 FIELD_MAX = i64(1) << 40;

// (offset from the start of the elements, the steps after it)
std::pair<Value, std::span<const Step>> element_offset(std::span<const Step> st) {
    if (!st.empty() && st[0].kind == Step::Kind::Off) return {st[0].e, st.subspan(1)};
    return {small(0), st};
}

i64 mod256(i64 n) { return ((n % 256) + 256) % 256; }

// python field(): the bits [off, off + size) of the slot bit / 256 from base -
// the whole word at the bit 0 as base itself, when whole
Value field(Value base, i64 bit, i64 size, Value off, bool whole) {
    if (!off.is_small()) return Value();
    const i64 o = off.small_val();
    if (o < -FIELD_MAX || o > FIELD_MAX) return Value();
    const i64 n = bit + o;
    if (n == 0 && size == 256 && whole) return st_form(256, base, 256);
    return st_form(size, mk(Op::SF, base, small(n)), 256 - mod256(n));
}

Value element(const FormCtx& c, Value base, u32 t, std::span<const Step> st, i64 size, Value off) {
    check_stack();
    const StorageType& T = c.types[t];
    const u32 et = T.elem;
    const auto [e, rest] = element_offset(st);
    const u16 width = c.types.elem_width(et);
    if (width < 256 && rest.empty()) {
        const Value i = packed(e, off, small(size));
        if (i.nil() || size != width) return Value();
        return st_form(size, mk(Op::SI, base, i), width);
    }
    const Lin l = linear(e);
    const EvmInt stride = EvmInt::from_u64(T.stride);
    if (!pymod(l.stride, stride).is_zero()) return Value();
    Value index;
    if (!l.stride.is_zero()) {
        index = l.stride == stride ? l.index : alg::mul(floordiv(l.stride, stride).value(), l.index);
        const EvmInt q = floordiv(l.c, stride);
        if (!q.is_zero()) index = alg::add(index, q.value());
    } else {
        index = floordiv(l.c, stride).value();
    }
    const EvmInt member = pymod(l.c, stride);
    Steps r;
    if (!member.is_zero()) {
        if (!member.fits_i64() || member.to_i64() > FIELD_MAX) return Value();
        r.push_back(Step{Step::Kind::Off, member.value(), false});
    }
    r.insert(r.end(), rest.begin(), rest.end());
    return form(c, mk(Op::SI, base, index), et, r, size, off);
}

}  // namespace

Value form(const FormCtx& c, Value base, u32 t, std::span<const Step> st, i64 size, Value off) {
    check_stack();
    const StorageType& T = c.types[t];
    using K = StorageType::Kind;
    if (st.empty()) {
        if (T.kind == K::Value) {
            const i64 width = T.width;
            if (is_small(off, 0) && size <= width) return st_form(size, base, width);
            if (off.is_small() && off.small_val() > 0 && off.small_val() + size <= width)
                return alg::mask(size, off.small_val(), -off.small_val(), st_form(width, base, width));
        }
        if (T.kind == K::Array && is_small(off, 0)) return st_form(size, mk(Op::SL, base), 256);
        if (T.kind == K::Bytes && is_small(off, 0)) return st_form(size, base, 256);
        if (T.kind == K::Fixed) return element(c, base, t, {}, size, off);
        // (the first word of a struct of more slots is its .field_0)
        return field(base, 0, size, off, !(T.kind == K::Struct && T.slots != std::optional<u64>(1)));
    }
    const Step& s = st[0];
    switch (s.kind) {
        case Step::Kind::Map:
            if (T.kind != K::Mapping) return Value();
            return form(c, mk(Op::SI, base, s.e), T.elem, st.subspan(1), size, off);
        case Step::Kind::Blen: {
            if (T.kind != K::Bytes || st.size() > 1) return Value();
            const Value loc = st_form(256, mk(Op::SBL, base), 256);
            if (is_small(off, 0) && size == 256) return loc;
            if (off.is_small() && off.small_val() < 0) return alg::mask(size, 0, -off.small_val(), loc);
            return alg::mask(small(size), off, alg::mul(small(-1), off), loc);
        }
        case Step::Kind::Data: {
            if (T.kind == K::Bytes) {
                const auto [e, rest] = element_offset(st.subspan(1));
                if (!rest.empty()) return Value();
                return field(mk(Op::SI, base, e), 0, size, off, true);
            }
            if (T.kind != K::Array) return Value();
            return element(c, base, t, st.subspan(1), size, off);
        }
        case Step::Kind::Off:
            if (T.kind == K::Fixed) return element(c, base, t, st, size, off);
            if (s.e.is_int()) {
                if (T.kind != K::Struct || st.size() > 1) return Value();
                if (!s.e.is_small() || s.e.small_val() < -FIELD_MAX || s.e.small_val() > FIELD_MAX) return Value();
                return field(base, 256 * s.e.small_val(), size, off, true);
            }
            return Value();
    }
    return Value();
}

// ---- raw ------------------------------------------------------------------------------

namespace {

// the bits [off, off + size) of a word-wide form, moved to the bit 0 - as
// STORAGE reads them (off < 0: the low size bits moved left)
Value bits_of(Value size, Value off, Value whole) {
    if (off.is_small() && off.small_val() < 0) return alg::mask(size, small(0), small(-off.small_val()), whole);
    return alg::mask(size, off, off.is_small() ? small(-off.small_val()) : alg::mul(small(-1), off), whole);
}

}  // namespace

Value raw_read(Value size, Value off, Value idx) {
    if (idx.is(Op::LENGTH, 1)) {
        // the length of a bytes, decoded (solidity's), of the slot
        const Value key = idx[0].is(Op::LOC, 1) ? idx[0][0] : idx[0];
        const Value length = st_form(256, mk(Op::SBL, mk(Op::SR, key)), 256);
        if (is_small(off, 0) && is_small(size, 256)) return length;
        return bits_of(size, off, length);
    }
    if (idx.is(Op::LOC, 1)) idx = idx[0];
    const Value base = mk(Op::SR, idx);
    if (!size.is_small()) return bits_of(size, off, st_form(256, base, 256));
    const i64 sz = size.small_val();
    if (is_small(off, 0)) return st_form(sz, base, 256);
    // (bits of the slot only: STORAGE reads none past its 256th)
    if (off.is_small() && off.small_val() > 0 && off.small_val() < 256)
        return st_form(sz, mk(Op::SF, base, off), 256 - off.small_val());
    if (off.is_small() && off.small_val() < 0) return alg::mask(sz, 0, -off.small_val(), st_form(sz, base, 256));
    return bits_of(size, off, st_form(256, base, 256));
}

Value raw_target(Value size, Value off, Value idx) {
    if (idx.is(Op::LENGTH)) throw Unsupported("storage: a write of the length of a bytes");
    if (idx.is(Op::LOC, 1)) idx = idx[0];
    if (!size.is_small()) return Value();
    const Value base = mk(Op::SR, idx);
    const i64 sz = size.small_val();
    if (is_small(off, 0)) return st_form(sz, base, 256);
    if (off.is_small() && off.small_val() > 0 && off.small_val() < 256)
        return st_form(sz, mk(Op::SF, base, off), 256 - off.small_val());
    return Value();
}

}  // namespace pan::storage::detail
