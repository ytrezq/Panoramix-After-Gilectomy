// What the VM knows on a path (python vm.py's `known`, asm vmmem.s): the
// conditions that hold there (one per JUMPI taken), what the path wrote in
// memory at known places, whether the memory is still of zeroes elsewhere
// (memory_fresh), whether no call was made yet (returndatasize_zero), and
// the bit lengths of a few variables (var_bits: a snapshot of a small read).
//
// Lot 5's own, behind this small interface, until lot 3's Facts lands (the
// switch must stay cheap: nothing outside src/vm/ sees it).
//
// A persistent list (cells in the context's arena, the newest first): a
// child node adds a fact in O(1) and shares the rest with its parent; a
// rewrite (forget, a memory write over known facts) rebuilds the list.
// Python's tuples kept their facts oldest first: "the last fact" is the head.
#pragma once

#include <optional>
#include <span>

#include "core/base.hpp"
#include "core/evmint.hpp"
#include "core/smallvec.hpp"
#include "core/value.hpp"

namespace pan::vm {

enum class FactKind : u8 {
    Cond,     // a: a condition known to hold (an expression, != 0)
    Mem,      // a: start, b: size (small ints), c: the value of those bytes (NIL: not known)
    Fresh,    // memory_fresh: the memory is of zeroes where no Mem fact says otherwise
    RdZero,   // returndatasize_zero: no call was made yet in this run
    VarBits,  // a: a variable, b: the bit length of its value (small int)
};

struct Fact {
    FactKind kind = FactKind::Cond;
    Value a, b, c;
    bool operator==(const Fact&) const = default;
};

// the reads a state change may change (python forget's names)
enum class Forget : u8 {
    Storage,   // an SSTORE: the facts mentioning storage reads
    Tload,     // a TSTORE: those mentioning TLOAD
    Volatile,  // a call, a create, a loop's head: those mentioning any volatile read (F_VOLATILE)
};

// Python's mask_value: alg::mask, the whole word left as it is.
Value mask_value(Value v, i64 size, i64 off = 0, i64 shl = 0);

// The bit length a value can have at most (python memloc.max_value_bits):
// calldatasize, returndatasize, codesize, msize and gas below 2^64 (gas keeps
// them there), the variables of `var_bits` their bits.
class PathFacts;
u32 max_value_bits(Value v, const PathFacts* facts = nullptr);

class PathFacts {
public:
    PathFacts() = default;

    bool empty() const noexcept { return head_ == nullptr; }
    u32 size() const noexcept { return n_; }

    // --- adding ---
    PathFacts with(const Fact& f) const;
    PathFacts with_cond(Value cond) const { return with(Fact{FactKind::Cond, cond, {}, {}}); }
    PathFacts with_fresh() const { return with(Fact{FactKind::Fresh, {}, {}, {}}); }
    PathFacts with_rdzero() const { return with(Fact{FactKind::RdZero, {}, {}, {}}); }
    PathFacts with_var_bits(Value var, u32 bits) const {
        return with(Fact{FactKind::VarBits, var, Value::small(i64(bits)), {}});
    }

    // --- reading ---
    bool contains(const Fact& f) const noexcept;
    bool has(FactKind k) const noexcept;
    bool fresh() const noexcept { return has(FactKind::Fresh); }
    bool rdzero() const noexcept { return has(FactKind::RdZero); }
    // f(const Fact&) newest first (python's reversed(known)); f returns false to stop
    template <class F>
    void each_newest_first(F&& f) const {
        for (const Cell* c = head_; c; c = c->next)
            if (!f(c->f)) return;
    }
    // the facts, oldest first (python's order)
    void to_vector(SmallVec<Fact, 32>& out) const;
    static PathFacts from(std::span<const Fact> oldest_first);

    // python is_known: true / false when a known condition decides exp
    std::optional<bool> is_known(Value exp) const;
    // python decided: 0 where the facts say exp is false, 1 where true and
    // exp is a truth value, else exp
    Value decided(Value exp) const;

    // --- state changes ---
    // python forget: the conditions mentioning what changed dropped, the
    // memory facts whose value mentions it made unknown
    PathFacts forget(Forget what) const;
    // the facts but the memory's (Mem and Fresh)
    PathFacts without_memory() const;

    // --- memory (python write_memory, read_memory, known_zeroes) ---
    // what's known once value is written at [start, start + size); start,
    // size: expressions (a write that may go anywhere drops the memory facts)
    PathFacts write_memory(Value start, Value size, Value value) const;
    // the word at addr when what's there is known, NIL otherwise
    Value read_memory(Value addr) const;
    // the memory [start, start + size) is known to be zeroes (at most
    // MAX_ZEROES_SIZE bytes)
    bool known_zeroes(Value start, Value size) const;

    // --- bounds (python upper_bound, bound, write_range) ---
    // the highest value v can have by the known conditions
    std::optional<EvmInt> upper_bound(Value v) const;
    // the highest value v can have, below 2^128: by the conditions, a MIN's
    // operands, the bits of what it's made of
    std::optional<EvmInt> bound(Value v) const;
    // the bytes a write at start of size may touch: [lo, hi)
    struct Span {
        EvmInt lo, hi;
    };
    std::optional<Span> write_range(Value start, Value size) const;
    // var_bits of a variable (0 when none)
    u32 var_bits(Value var) const noexcept;

    // --- rewrites ---
    // every Mem fact's value rewritten by f (NIL kept), the rest as it is
    template <class F>
    PathFacts map_mem_values(F&& f) const {
        SmallVec<Fact, 32> v;
        to_vector(v);
        bool changed = false;
        for (Fact& x : v)
            if (x.kind == FactKind::Mem && !x.c.nil()) {
                Value n = f(x.c);
                if (n != x.c) {
                    x.c = n;
                    changed = true;
                }
            }
        return changed ? from(std::span<const Fact>(v.data(), v.size())) : *this;
    }

    bool operator==(const PathFacts& o) const noexcept;

private:
    struct Cell {
        const Cell* next;
        Fact f;
    };
    static const Cell* cons(const Fact& f, const Cell* next);
    const Cell* head_ = nullptr;
    u32 n_ = 0;
};

// python arithmetic.eval_bool(exp, fact, symbolic=False): true / false when
// the condition fact (known to hold) decides exp
std::optional<bool> eval_bool(Value exp, Value fact);

}  // namespace pan::vm
