// The types of what is at a slot (python storage.py: typeof, array_type,
// elem_width, is_bytes_slot) and the variables of a slot that holds values
// (layout, merge_ranges, uncovered).
#include <algorithm>

#include "core/context.hpp"
#include "core/errors.hpp"
#include "storage/internal.hpp"

namespace pan::storage::detail {

// ---- the type table -----------------------------------------------------------------------

u32 Types::intern(const StorageType& t) {
    for (u32 i = 0; i < t_.size(); ++i)
        if (t_[i] == t) return i;
    t_.push_back(t);
    return u32(t_.size() - 1);
}

u32 Types::value(u16 width) {
    StorageType t;
    t.kind = StorageType::Kind::Value;
    t.width = width;
    return intern(t);
}

u32 Types::structure(std::optional<u64> slots) {
    StorageType t;
    t.kind = StorageType::Kind::Struct;
    t.slots = slots;
    return intern(t);
}

u32 Types::bytes() {
    StorageType t;
    t.kind = StorageType::Kind::Bytes;
    return intern(t);
}

u32 Types::mapping(u32 elem) {
    StorageType t;
    t.kind = StorageType::Kind::Mapping;
    t.elem = elem;
    return intern(t);
}

u32 Types::array(StorageType::Kind kind, u32 elem, u64 stride) {
    StorageType t;
    t.kind = kind;
    t.elem = elem;
    t.stride = stride;
    return intern(t);
}

u16 Types::elem_width(u32 i) const noexcept {
    const StorageType& t = t_[i];
    if (t.kind == StorageType::Kind::Value && t.width < 256 && 256 % t.width == 0 && t.width >= 8) return t.width;
    return 256;
}

// ---- typeof ----------------------------------------------------------------------------------

namespace {

// python's kinds of first steps, in the order of their names (the ties of
// python's max(kinds, key=(count, name)))
enum K : u8 { KData = 0, KFixed = 1, KMap = 2, KMember = 3 };

K kind_of(const Step& s) {
    switch (s.kind) {
        case Step::Kind::Off: return s.e.is_int() ? KMember : KFixed;
        case Step::Kind::Blen:
        case Step::Kind::Data: return KData;
        case Step::Kind::Map: return KMap;
    }
    return KData;
}

// (offset from the start of the elements, the steps after it)
std::pair<Value, std::span<const Step>> element_offset(std::span<const Step> st) {
    if (!st.empty() && st[0].kind == Step::Kind::Off) return {st[0].e, st.subspan(1)};
    return {small(0), st};
}

struct SizeOff {
    Value size, off;
    bool operator==(const SizeOff&) const = default;
};

u32 array_type(Types& T, std::span<const RootAccess> elems, u64& stride_out) {
    check_stack();
    // packed values: all the elements' accesses at bits of their slot
    std::optional<i64> width;
    bool one_width = true;
    for (const RootAccess& a : elems) {
        const auto [e, rest] = element_offset(a.steps);
        const auto size = small_of(a.size);
        if (rest.empty() && size && *size >= 8 && *size < 256 && !packed(e, a.off, a.size).nil()) {
            if (width && *width != *size) one_width = false;
            width = *size;
        }
    }
    if (width && one_width) {
        bool all = true;
        for (const RootAccess& a : elems) {
            const auto [e, rest] = element_offset(a.steps);
            if (!rest.empty() || packed(e, a.off, a.size).nil()) {
                all = false;
                break;
            }
        }
        if (all) {
            stride_out = 1;
            return T.value(u16(*width));
        }
    }
    // the stride: the gcd of the elements' strides
    mpz_class g = 0;
    for (const RootAccess& a : elems) {
        const Lin l = linear(element_offset(a.steps).first);
        if (!l.stride.is_zero()) {
            const mpz_class s = l.stride.to_mpz();
            mpz_gcd(g.get_mpz_t(), g.get_mpz_t(), s.get_mpz_t());
        }
    }
    if (g == 0) g = 1;
    if (g > mpz_class(1u << 30) * mpz_class(1u << 30)) throw Unsupported("storage: an array's stride past 2^60");
    const u64 stride = g.get_ui();
    const EvmInt st_int = EvmInt::from_u64(stride);
    std::vector<RootAccess> inner;
    inner.reserve(elems.size());
    for (const RootAccess& a : elems) {
        const auto [e, rest] = element_offset(a.steps);
        const Lin l = linear(e);
        const EvmInt member = pymod(l.c, st_int);
        RootAccess r;
        if (!member.is_zero()) r.steps.push_back(Step{Step::Kind::Off, member.value(), false});
        r.steps.insert(r.steps.end(), rest.begin(), rest.end());
        r.size = a.size;
        r.off = a.off;
        r.written = a.written;
        inner.push_back(std::move(r));
    }
    u32 t = type_of(T, inner);
    if ((stride > 1 && T[t].kind != StorageType::Kind::Struct) || T[t].kind == StorageType::Kind::Struct)
        t = T.structure(stride);
    stride_out = stride;
    return t;
}

}  // namespace

u32 type_of(Types& T, std::span<const RootAccess> accs) {
    check_stack();
    u64 cnt[4] = {};
    bool kinds = false;
    for (const RootAccess& a : accs) {
        if (a.steps.empty()) continue;
        ++cnt[kind_of(a.steps[0])];
        kinds = true;
    }
    std::vector<SizeOff> direct;
    for (const RootAccess& a : accs)
        if (a.steps.empty()) {
            const SizeOff so{a.size, a.off};
            if (std::find(direct.begin(), direct.end(), so) == direct.end()) direct.push_back(so);
        }
    if (!kinds) {
        bool zero_offs = true, int_sizes = true;
        i64 most = -1;
        for (const SizeOff& d : direct) {
            if (!is_small(d.off, 0)) zero_offs = false;
            if (!d.size.is_small()) int_sizes = false;
            else most = std::max(most, d.size.small_val());
        }
        if (direct.empty()) throw Unsupported("storage: a type of no access");
        if (zero_offs && int_sizes) {
            if (most < 1 || most > 256) throw Unsupported("storage: a value of no width");
            return T.value(u16(most));
        }
        std::optional<i64> width;
        bool one = true;
        for (const SizeOff& d : direct)
            if (!d.off.is_int()) {
                const auto s = small_of(d.size);
                if (!s || (width && *width != *s)) one = false;
                else width = *s;
            }
        if (width && one && *width > 0 && *width <= 256 && T.elem_width(T.value(u16(*width))) < 256)
            return T.array(StorageType::Kind::Fixed, T.value(u16(*width)), 1);
        return T.structure(1);
    }
    // the most of them (ties: python's greatest name)
    K kind = KData;
    for (int k = 0; k < 4; ++k)
        if (cnt[k] >= cnt[kind]) kind = K(k);
    if (cnt[KFixed] && cnt[KMember] && !cnt[KData] && !cnt[KMap]) kind = KFixed;

    switch (kind) {
        case KMap: {
            std::vector<RootAccess> inner;
            for (const RootAccess& a : accs)
                if (!a.steps.empty() && a.steps[0].kind == Step::Kind::Map) {
                    RootAccess r;
                    r.steps.assign(a.steps.begin() + 1, a.steps.end());
                    r.size = a.size;
                    r.off = a.off;
                    r.written = a.written;
                    inner.push_back(std::move(r));
                }
            return T.mapping(type_of(T, inner));
        }
        case KMember: {
            std::optional<EvmInt> lo, hi;
            for (const RootAccess& a : accs)
                if (!a.steps.empty() && a.steps[0].kind == Step::Kind::Off && a.steps[0].e.is_int()) {
                    const EvmInt m(a.steps[0].e);
                    if (!lo || m < *lo) lo = m;
                    if (!hi || *hi < m) hi = m;
                }
            if (lo->sign() >= 0) {
                const EvmInt n = *hi + EvmInt(1);
                if (const auto u = n.to_u64()) return T.structure(*u);
            }
            return T.structure(std::nullopt);
        }
        case KData: {
            bool blen = false;
            for (const RootAccess& a : accs)
                if (!a.steps.empty() && a.steps[0].kind == Step::Kind::Blen) blen = true;
            auto has = [&](i64 s, i64 o) {
                for (const SizeOff& d : direct)
                    if (is_small(d.size, s) && is_small(d.off, o)) return true;
                return false;
            };
            if (blen || (has(1, 0) && (has(255, 1) || has(7, 1) || has(248, 8)))) return T.bytes();
            std::vector<RootAccess> elems;
            for (const RootAccess& a : accs)
                if (!a.steps.empty() && a.steps[0].kind == Step::Kind::Data) {
                    RootAccess r;
                    r.steps.assign(a.steps.begin() + 1, a.steps.end());
                    r.size = a.size;
                    r.off = a.off;
                    r.written = a.written;
                    elems.push_back(std::move(r));
                }
            u64 stride = 1;
            const u32 et = array_type(T, elems, stride);
            return T.array(StorageType::Kind::Array, et, stride);
        }
        case KFixed:
            break;
    }
    std::vector<RootAccess> elems;
    for (const RootAccess& a : accs)
        if (!a.steps.empty() && a.steps[0].kind == Step::Kind::Off) elems.push_back(a);
    u64 stride = 1;
    const u32 et = array_type(T, elems, stride);
    return T.array(StorageType::Kind::Fixed, et, stride);
}

// ---- the variables of a slot of values ----------------------------------------------------------

std::vector<Range> merge_ranges(std::span<const std::pair<i64, i64>> fields) {
    std::vector<std::pair<i64, i64>> iv;  // (off, end)
    iv.reserve(fields.size());
    for (const auto& [size, off] : fields) iv.emplace_back(off, off + size);
    std::sort(iv.begin(), iv.end());
    std::vector<Range> res;
    for (const auto& [off, end] : iv) {
        if (!res.empty() && off < res.back().end)
            res.back().end = std::max(res.back().end, end);
        else
            res.push_back(Range{off, end});
    }
    return res;
}

namespace {

// the (size, off) of the bits of the parts no range has
std::vector<std::pair<i64, i64>> uncovered(std::span<const std::pair<i64, i64>> parts, std::span<const Range> ranges) {
    std::vector<Range> sorted(ranges.begin(), ranges.end());
    std::sort(sorted.begin(), sorted.end(), [](const Range& a, const Range& b) {
        return a.off != b.off ? a.off < b.off : a.end < b.end;
    });
    std::vector<std::pair<i64, i64>> res;
    for (const auto& [size, off] : parts) {
        i64 pos = off;
        const i64 end = off + size;
        for (const Range& r : sorted) {
            if (r.end <= pos || r.off >= end) continue;
            if (r.off > pos) res.emplace_back(r.off - pos, pos);
            pos = std::max(pos, r.end);
        }
        if (pos < end) res.emplace_back(end - pos, pos);
    }
    return res;
}

}  // namespace

std::vector<Range> fields_layout(std::span<const RootAccess> accs) {
    std::vector<std::pair<i64, i64>> written, numbers, all;
    for (const RootAccess& a : accs) {
        const auto size = small_of(a.size), off = small_of(a.off);
        if (!size || !off) throw Unsupported("storage: a field of no known bits");
        all.emplace_back(*size, *off);
        if (a.written == Written::Yes) written.emplace_back(*size, *off);
        if (a.written == Written::Const) numbers.emplace_back(*size, *off);
    }
    const std::vector<Range> fields = merge_ranges(written);
    const std::vector<std::pair<i64, i64>> unc = uncovered(numbers, fields);
    const std::vector<Range> nums = merge_ranges(unc);
    std::vector<std::pair<i64, i64>> parts;
    for (const Range& r : fields) parts.emplace_back(r.end - r.off, r.off);
    for (const Range& r : nums) parts.emplace_back(r.end - r.off, r.off);
    if (parts.empty()) return merge_ranges(all);
    return merge_ranges(parts);
}

}  // namespace pan::storage::detail
