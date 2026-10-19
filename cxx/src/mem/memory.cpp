// The memory model (lot 4): see memory.hpp. First version: the widths and
// the operand tables; the rest answers what is always right (nothing known,
// nothing split) until it lands.
#include "mem/memory.hpp"

#include "algebra/construct.hpp"
#include "core/context.hpp"
#include "core/errors.hpp"

namespace pan::mem {

namespace {

Value small(i64 x) { return Value::small(x); }

}  // namespace

// ---- bytes expressions and their widths ------------------------------------------

bool is_bytes(Value v) noexcept {
    if (v.is_none() || v.is_bytes()) return true;
    if (!v.is_expr()) return false;
    return info(v.op()).sort == Sort::Bytes;
}

std::optional<Value> width_of(Value b) {
    check_stack();
    if (b.is_none()) return small(0);
    if (b.is_bytes()) return small(i64(b.size()));
    if (!b.is_expr()) return std::nullopt;
    switch (b.op()) {
        case Op::SIZED:
            if (b.size() == 2) return b[0];
            return std::nullopt;
        case Op::MEM:
            if (b.size() == 1 && b[0].is(Op::RANGE, 2)) return b[0][1];
            return std::nullopt;
        case Op::CALLDATA_BYTES:
        case Op::CODE_BYTES:
            if (b.size() == 2) return b[1];
            return std::nullopt;
        case Op::RETURNDATA_BYTES:
            if (b.size() == 3) return b[2];
            return std::nullopt;
        case Op::EXTCODE_BYTES:
            if (b.size() == 2 && b[1].is(Op::RANGE, 2)) return b[1][1];
            return std::nullopt;
        case Op::DATA: {
            SmallVec<Value, 8> ws;
            for (Value e : b.args()) {
                auto w = width_of(e);
                if (!w) return std::nullopt;
                ws.push_back(*w);
            }
            if (ws.empty()) return small(0);
            return alg::add(ws.span());
        }
        default:
            return std::nullopt;
    }
}

std::optional<u64> width_u64(Value b) {
    auto w = width_of(b);
    if (!w || !w->is_small() || w->small_val() < 0) return std::nullopt;
    return u64(w->small_val());
}

Value sized(Value n, Value v) {
    if (is_bytes(v)) {
        if (auto w = width_of(v); w && *w == n) return v;
    }
    return mk(Op::SIZED, n, v);
}

Value keep_width(Value old_elem, Value new_elem) {
    if (new_elem == old_elem || is_bytes(new_elem)) return new_elem;
    auto w = width_of(old_elem);
    if (!w) return old_elem;
    return sized(*w, new_elem);
}

std::optional<u32> implicit_width(Value word) noexcept {
    (void)word;
    return std::nullopt;
}

Value concat(std::span<const Value> parts) {
    if (parts.size() == 1) return parts[0];
    return mk(Op::DATA, parts);
}

std::optional<Value> as_word(Value b) {
    (void)b;
    return std::nullopt;
}

std::optional<Value> slice(Value b, Value lo, Value hi, const alg::Facts* facts) {
    (void)facts;
    if (lo == small(0)) {
        if (auto w = width_of(b); w && *w == hi) return b;
    }
    return std::nullopt;
}

std::span<const u8> byte_operands(Value v) noexcept {
    static constexpr u8 k0[] = {0}, k1[] = {1}, k2[] = {2}, k3[] = {3}, k34[] = {3, 4}, k45[] = {4, 5};
    static constexpr u8 kAll[] = {0,  1,  2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13, 14, 15,
                                  16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31};
    if (!v.is_expr()) return {};
    const u32 n = v.size();
    auto upto = [&](std::span<const u8> s) {
        usize k = 0;
        while (k < s.size() && s[k] < n) ++k;
        return s.first(k);
    };
    switch (v.op()) {
        case Op::SHA3:
        case Op::DATA:
            if (n <= 32) return std::span<const u8>(kAll, n);
            return {};
        case Op::ARR:
            if (n >= 1 && n <= 32) return std::span<const u8>(kAll + 1, n - 1);
            return {};
        case Op::RETURN:
        case Op::REVERT:
        case Op::LOG0:
        case Op::LOG1:
        case Op::LOG2:
        case Op::LOG3:
        case Op::LOG4:
            return upto(k0);
        case Op::CALL:
        case Op::CALLCODE:
            return upto(k45);
        case Op::DELEGATECALL:
        case Op::STATICCALL:
            return upto(k34);
        case Op::CREATE:
        case Op::CREATE2:
            return upto(k2);
        case Op::PRECOMPILED:
            return upto(k3);
        case Op::REQUIRE:
            return upto(k1);
        default:
            return {};
    }
}

// ---- ranges ------------------------------------------------------------------------

Value make_range(Value start, Value len) { return mk(Op::RANGE, start, len); }

Value range_end(Value r) { return alg::add(r[0], r[1]); }

Tri overlaps(Value r1, Value r2, const alg::Facts* facts) {
    (void)r1, (void)r2, (void)facts;
    return Tri::None;
}

Tri contains(Value outer, Value inner, const alg::Facts* facts) {
    (void)outer, (void)inner, (void)facts;
    return Tri::None;
}

Tri overwrites(Value write, Value read, const alg::Facts* facts) {
    (void)write, (void)read, (void)facts;
    return Tri::None;
}

SmallVec<Value, 2> survivors(Value read, Value write, const alg::Facts* facts) {
    (void)write, (void)facts;
    return SmallVec<Value, 2>{read};
}

// ---- reads from the writes before them -------------------------------------------

MemWrite as_write(Value line) {
    if (line.is(Op::SETMEM, 2) && line[0].is(Op::RANGE, 2)) return MemWrite{line[0], line[1]};
    return MemWrite{};
}

MemState::MemState(bool fresh, const alg::Facts* facts)
    : facts_(facts),
      fresh_(fresh),
      pieces_(cx().budget.resource()),
      written_(cx().budget.resource()) {}

void MemState::write(Value range, Value value) {
    (void)range, (void)value;
    pieces_.clear();
    written_.clear();
    fresh_ = false;
}

void MemState::clear() noexcept {
    pieces_.clear();
    written_.clear();
    fresh_ = false;
}

void MemState::forget_flags(u8 content_flags) {
    (void)content_flags;
    pieces_.clear();
}

void MemState::forget_name(Value name) {
    (void)name;
    pieces_.clear();
}

std::optional<Value> MemState::read(Value range) const {
    (void)range;
    return std::nullopt;
}

std::optional<Value> MemState::read_word(Value range) const {
    (void)range;
    return std::nullopt;
}

void MemState::meet(const MemState& other) {
    (void)other;
    pieces_.clear();
    written_.clear();
    fresh_ = false;
}

std::optional<Value> fill(Value read_range, std::span<const MemWrite> writes, const alg::Facts* facts) {
    MemState st(false, facts);
    for (const MemWrite& w : writes) st.write(w);
    return st.read(read_range);
}

// ---- splits of a write of fields ---------------------------------------------------

std::optional<SmallVec<Field, 8>> split_word(Value word) {
    (void)word;
    return std::nullopt;
}

SmallVec<Value, 4> split_setmem(Value line) { return SmallVec<Value, 4>{line}; }

SmallVec<Value, 4> split_store(Value line) { return SmallVec<Value, 4>{line}; }

std::optional<Value> byte_field_store(Value line) {
    (void)line;
    return std::nullopt;
}

}  // namespace pan::mem
