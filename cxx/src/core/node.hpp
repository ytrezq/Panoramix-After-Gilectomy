// Nodes: the 16-byte header (core/value.hpp: NodeHeader) and its payload.
//
//   EXPR    op = the Op;        payload Value args[size]
//   LIST    op = the ListKind;  payload Value items[size]
//   BIGINT  op = 1 if negative; payload mp_limb_t limbs[size] (the magnitude,
//           normalized; only for |x| >= 2^62: smaller ints are small Values)
//   BYTES   op = 0;             payload u8 data[size] (zero padded to 16)
//
// The hash is content-based, never an address: the same structure has the
// same hash in every context and every run (imports, the structural order,
// determinism). Its top byte holds the content flags.
#pragma once

#include <gmp.h>

#include <cstring>
#include <span>

#include "core/value.hpp"

namespace pan {

inline const Value* node_args(const NodeHeader* n) noexcept { return reinterpret_cast<const Value*>(n + 1); }
inline const mp_limb_t* node_limbs(const NodeHeader* n) noexcept { return reinterpret_cast<const mp_limb_t*>(n + 1); }
inline const u8* node_data(const NodeHeader* n) noexcept { return reinterpret_cast<const u8*>(n + 1); }

// the bytes of a node with this payload, rounded to 16
inline constexpr usize node_bytes(usize payload) noexcept { return (sizeof(NodeHeader) + payload + 15) & ~usize(15); }

// the hash of an EXPR or LIST node (flags: the operands' | add)
inline u64 hash_seq(NodeKind kind, u16 op, std::span<const Value> items, u8 add_flags) noexcept {
    u64 h = 0x9e3779b97f4a7c15ull * (u64(kind) << 16 | op) ^ items.size();
    u8 flags = add_flags;
    for (Value v : items) {
        h ^= v.hash();
        h *= 0xc4ceb9fe1a85ec53ull;
        h = h << 31 | h >> 33;
        flags |= v.flags();
    }
    return (hash_mix(h) & HASH_BITS) | (u64(flags) << HASH_FLAGS_SHIFT);
}

// the hash of a big int: its sign and limbs
inline u64 hash_big(mpz_srcptr z) noexcept {
    i64 size = z->_mp_size;
    u64 h = hash_mix(u64(size) ^ 0x5851f42d4c957f2dull);
    for (i64 i = size < 0 ? -size : size; i > 0; i--) h = hash_mix(z->_mp_d[i - 1] ^ h);
    return h & HASH_BITS;
}

// the hash of bytes, eight at a time
inline u64 hash_bytes(std::span<const u8> d) noexcept {
    const u8* s = d.data();
    usize n = d.size();
    u64 h = 0xcbf29ce484222325ull ^ n;
    const u64 k = 0x9e3779b97f4a7c15ull;
    usize i = 0;
    for (; i + 8 <= n; i += 8) {
        u64 w;
        std::memcpy(&w, s + i, 8);
        h ^= w;
        h *= k;
        h = h << 29 | h >> 35;
    }
    if (i < n) {
        u64 w = 0;
        for (usize j = n; j > i; j--) w = (w << 8) | s[j - 1];
        h ^= w;
        h *= k;
        h = h << 29 | h >> 35;
    }
    return hash_mix(h) & HASH_BITS;
}

// a read-only mpz over a BIGINT node (no allocation)
inline mpz_srcptr big_view(Value v, mpz_ptr tmp) noexcept {
    const NodeHeader* n = v.node();
    return mpz_roinit_n(tmp, node_limbs(n), n->op ? -mp_size_t(n->size) : mp_size_t(n->size));
}

}  // namespace pan
