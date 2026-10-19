// Values: the decompiler's data, one 64-bit word each.
//
//   ...1      a small signed int, 63 bits: v = i64(w) >> 1
//   ...0000   a node pointer (16-aligned), or 0 = NIL ("no value", never None)
//   ...010    an immediate: [2:0] = 010, [15:3] ImmKind (13 bits),
//             [31:16] sub-kind (16 bits), [63:32] payload (32 bits)
//
// The immediates: Bool (True / False), None, Leaf(op, n) (an operation
// without operands: an EVM byte that reads the context, CALLER 0x33, or a
// decompiler leaf >= 0x100; n numbers it when it is a call's result) and
// Name(kind, id) (a name the decompiler makes: its text exists only when
// printed).
//
// Nodes (core/node.hpp) are hash-consed per context (core/context.hpp): two
// equal values are the same word, so `==` is structural equality and a
// value keys a memo table. A node's hash is content-based (never an
// address); its top byte holds the content flags (F_MEM...), what the value
// contains anywhere in its tree, computed from the op table's properties.
#pragma once

#include <concepts>
#include <optional>
#include <span>

#include "core/base.hpp"
#include "core/ops.hpp"

namespace pan {

enum class NodeKind : u16 { Expr = 1, List = 2, BigInt = 3, Bytes = 4 };
// a LIST node's op: a list of values, or a trace (a list of lines)
enum class ListKind : u16 { Values = 0, Trace = 1 };

struct alignas(16) NodeHeader {
    u16 kind;  // NodeKind
    u16 op;    // Expr: the Op; List: the ListKind; BigInt: 1 when negative; Bytes: 0
    u32 size;  // Expr: operands; List: items; BigInt: limbs; Bytes: bytes
    u64 hash;  // content hash; the top byte: the content flags
};
static_assert(sizeof(NodeHeader) == 16);

enum class ImmKind : u16 { Bool = 1, None = 2, Leaf = 3, Name = 4 };

enum class Tag : u8 { Nil, SmallInt, BigInt, Expr, List, Bytes, Bool, None, Leaf, Name };

// the names the decompiler makes (ir.md section 2); the payload is the id
enum class NameKind : u16 {
    TMP = 1,             // the VM's _N
    LOOP = 2,            // a loop variable (opaque id; renumbered when printed)
    MSIZE_VAR = 3,       // _msize (id 0)
    PRECOMPILE = 4,      // a precompile's result: id = (address << 24) | k
    PARAM = 5,           // id = index in FunctionInfo::params
    STORVAR = 6,         // id = index in StorageLayout::vars
    FUNC = 7,            // id = the selector
    FALLBACK = 8,        // id 0
    INTERNAL = 9,        // id = the entry pc
    LOOP_ID = 10,        // id = the loop's id (WHILE/CONTINUE/LABEL/GOTO pairing)
    SAFEMATH_PARAM = 11  // id 0 (a), 1 (b)
};

inline constexpr i64 SMALL_MAX = (i64(1) << 62) - 1;
inline constexpr i64 SMALL_MIN = -(i64(1) << 62);
inline constexpr u64 HASH_FLAGS_SHIFT = 56;
inline constexpr u64 HASH_BITS = ~(u64(0xff) << HASH_FLAGS_SHIFT);

// Murmur3's 64-bit finalizer
constexpr u64 hash_mix(u64 x) {
    x ^= x >> 33;
    x *= 0xff51afd7ed558ccdull;
    x ^= x >> 33;
    x *= 0xc4ceb9fe1a85ec53ull;
    x ^= x >> 33;
    return x;
}

// the content flags of a name
constexpr u8 name_flags(NameKind k) {
    switch (k) {
        case NameKind::TMP:
        case NameKind::LOOP:
        case NameKind::PRECOMPILE:
        case NameKind::SAFEMATH_PARAM:
            return F_VAR;
        case NameKind::MSIZE_VAR:
            return F_VAR | F_MSIZE;
        case NameKind::PARAM:
            return F_CALLDATA;
        default:
            return 0;
    }
}

class Value {
    u64 w_ = 0;
    struct Raw {};
    constexpr Value(u64 w, Raw) : w_(w) {}

    static constexpr u64 IMM_TAG = 2;
    static constexpr u64 imm(ImmKind k, u16 sub, u32 payload) {
        return (u64(payload) << 32) | (u64(sub) << 16) | (u64(k) << 3) | IMM_TAG;
    }

public:
    constexpr Value() = default;
    // True / False (exactly a bool: Value(5) does not compile)
    template <std::same_as<bool> B>
    constexpr explicit Value(B b) : w_(imm(ImmKind::Bool, 0, b ? 1 : 0)) {}

    static constexpr Value none() { return Value(imm(ImmKind::None, 0, 0), Raw{}); }
    // a small int: the caller knows it fits 63 bits (mk_int for any)
    static constexpr Value small(i64 n) { return Value((u64(n) << 1) | 1, Raw{}); }
    // an operation without operands (info(op).leaf), n its number (0: none)
    static constexpr Value leaf(Op op, u32 n = 0) { return Value(imm(ImmKind::Leaf, u16(op), n), Raw{}); }
    static constexpr Value name(NameKind k, u32 id) { return Value(imm(ImmKind::Name, u16(k), id), Raw{}); }
    static Value of(const NodeHeader* n) noexcept { return Value(reinterpret_cast<u64>(n), Raw{}); }
    static constexpr Value from_raw(u64 w) noexcept { return Value(w, Raw{}); }
    constexpr u64 raw() const noexcept { return w_; }

    // --- classification (O(1)) ---
    constexpr bool nil() const noexcept { return w_ == 0; }
    constexpr bool is_small() const noexcept { return w_ & 1; }
    constexpr bool is_node() const noexcept { return w_ != 0 && (w_ & 15) == 0; }
    constexpr bool is_imm() const noexcept { return (w_ & 7) == IMM_TAG; }
    const NodeHeader* node() const noexcept { return reinterpret_cast<const NodeHeader*>(w_); }
    bool is_node(NodeKind k) const noexcept { return is_node() && node()->kind == u16(k); }
    bool is_big() const noexcept { return is_node(NodeKind::BigInt); }
    bool is_int() const noexcept { return is_small() || is_big(); }
    bool is_expr() const noexcept { return is_node(NodeKind::Expr); }
    bool is_list() const noexcept { return is_node(NodeKind::List); }
    bool is_trace() const noexcept { return is_list() && node()->op == u16(ListKind::Trace); }
    bool is_bytes() const noexcept { return is_node(NodeKind::Bytes); }

    constexpr ImmKind imm_kind() const noexcept { return ImmKind((w_ >> 3) & 0x1fff); }
    constexpr u16 imm_sub() const noexcept { return u16(w_ >> 16); }
    constexpr u32 imm_payload() const noexcept { return u32(w_ >> 32); }
    constexpr bool is_bool() const noexcept { return is_imm() && imm_kind() == ImmKind::Bool; }
    constexpr bool is_true() const noexcept { return w_ == imm(ImmKind::Bool, 0, 1); }
    constexpr bool is_false() const noexcept { return w_ == imm(ImmKind::Bool, 0, 0); }
    constexpr bool is_none() const noexcept { return w_ == imm(ImmKind::None, 0, 0); }
    constexpr bool is_leaf() const noexcept { return is_imm() && imm_kind() == ImmKind::Leaf; }
    constexpr bool is_name() const noexcept { return is_imm() && imm_kind() == ImmKind::Name; }
    constexpr bool is_name(NameKind k) const noexcept { return is_name() && imm_sub() == u16(k); }
    Tag tag() const noexcept;

    // --- operations: an EXPR node's op, a LEAF's op; Op::NONE otherwise ---
    Op op() const noexcept {
        if (is_node()) {
            const NodeHeader* n = node();
            return n->kind == u16(NodeKind::Expr) ? Op(n->op) : Op::NONE;
        }
        if (is_leaf()) return Op(imm_sub());
        return Op::NONE;
    }
    bool is(Op o) const noexcept { return op() == o; }
    // an EXPR with this op and this many operands
    bool is(Op o, u32 arity) const noexcept {
        return is_expr() && node()->op == u16(o) && node()->size == arity;
    }

    // --- nodes (is_node()): EXPR operands, LIST items, BYTES bytes, BIGINT limbs ---
    u32 size() const noexcept { return node()->size; }
    const Value* data() const noexcept { return reinterpret_cast<const Value*>(node() + 1); }
    // the i-th operand / item (EXPR, LIST; i < size())
    Value operator[](u32 i) const noexcept { return data()[i]; }
    std::span<const Value> args() const noexcept { return {data(), size()}; }
    const Value* begin() const noexcept { return data(); }
    const Value* end() const noexcept { return data() + size(); }
    std::span<const u8> bytes() const noexcept {
        return {reinterpret_cast<const u8*>(node() + 1), size()};
    }
    // EXPR or LIST: its operands; anything else: none
    std::span<const Value> children() const noexcept {
        return is_expr() || is_list() ? args() : std::span<const Value>{};
    }

    // --- immediates ---
    u32 leaf_n() const noexcept { return imm_payload(); }
    NameKind name_kind() const noexcept { return NameKind(imm_sub()); }
    u32 name_id() const noexcept { return imm_payload(); }

    // --- ints ---
    constexpr i64 small_val() const noexcept { return i64(w_) >> 1; }
    // a small int, or a big one that fits i64
    std::optional<i64> as_i64() const noexcept;

    // --- content flags, hash ---
    u8 flags() const noexcept {
        if (is_node()) return u8(node()->hash >> HASH_FLAGS_SHIFT);
        if (is_imm()) {
            if (imm_kind() == ImmKind::Leaf) return info(Op(imm_sub())).content;
            if (imm_kind() == ImmKind::Name) return name_flags(NameKind(imm_sub()));
        }
        return 0;
    }
    bool has_flags(u8 f) const noexcept { return flags() & f; }
    // content-based, deterministic: the same in every context and every run
    u64 hash() const noexcept {
        if (is_node()) return node()->hash;
        return hash_mix(w_ ^ 0x9e3779b97f4a7c15ull);
    }

    // structural equality (hash-consing: within a context and the global one)
    constexpr bool operator==(const Value&) const = default;
};
static_assert(sizeof(Value) == 8);

inline constexpr Value True = Value(true);
inline constexpr Value False = Value(false);
inline constexpr Value None = Value::none();
inline constexpr Value NIL = Value();

inline Tag Value::tag() const noexcept {
    if (w_ == 0) return Tag::Nil;
    if (w_ & 1) return Tag::SmallInt;
    if (is_imm()) {
        switch (imm_kind()) {
            case ImmKind::Bool: return Tag::Bool;
            case ImmKind::None: return Tag::None;
            case ImmKind::Leaf: return Tag::Leaf;
            case ImmKind::Name: return Tag::Name;
        }
        return Tag::Nil;
    }
    switch (NodeKind(node()->kind)) {
        case NodeKind::Expr: return Tag::Expr;
        case NodeKind::List: return Tag::List;
        case NodeKind::BigInt: return Tag::BigInt;
        case NodeKind::Bytes: return Tag::Bytes;
    }
    return Tag::Nil;
}

}  // namespace pan
