// Path facts: what is known on a path of the VM (python vm.py's `known`:
// is_known, decided, forget, write_memory, read_memory, known_zeroes,
// upper_bound, known_bounds, bound, write_range; memloc.max_value_bits;
// asm vm.s, vmmem.s) - the conditions that hold there (one per JUMPI taken,
// with its polarity), what the path wrote in memory at known places,
// whether the memory is still of zeroes elsewhere (memory_fresh), whether no
// call was made yet (returndatasize_zero), the bit lengths of a few
// variables (var_bits: a snapshot of a small read).
//
// Persistent and cheap to copy: a list of cells in the context's arena, the
// newest first; a child path adds a fact in O(1) and shares the rest with
// its parent; a rewrite (forget, a memory write over known facts) rebuilds
// the list. Each condition is read once when added: its negation and the
// bound it puts on what it compares with a constant (x < 10: x in [0, 9])
// are kept beside it, for is_known and the ranges (ranges.hpp: a Facts*
// narrows the range of every expression a fact bounds).
//
// (The API of lot 5's first src/vm/facts.hpp, which this replaces, kept.)
#pragma once

#include <optional>
#include <span>

#include "algebra/ranges.hpp"
#include "core/base.hpp"
#include "core/evmint.hpp"
#include "core/smallvec.hpp"  // Tri
#include "core/value.hpp"

namespace pan::alg {

enum class FactKind : u8 {
    Cond,     // a: a condition known to hold (an expression, != 0); c: its negation (a cache)
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
    Storage,   // an SSTORE: the facts mentioning storage reads (F_STORAGE)
    Tload,     // a TSTORE: those mentioning TLOAD
    Volatile,  // a call, a create, a loop's head: those mentioning any volatile read (F_VOLATILE)
};

// what a memory fact keeps of a SETMEM's value: the word of a SIZED(n, v)
// (its low n bytes are what was written), anything else as it is
inline Value fact_value(Value v) { return v.is(Op::SIZED, 2) ? v[1] : v; }

// python vm.mask_value: alg::mask, the whole word left as it is
Value mask_value(Value v, i64 size, i64 off = 0, i64 shl = 0);

class Facts;
// the bit length v's value has at most (python memloc.max_value_bits, by
// the ranges: the BOUNDED leaves below 2^64, the facts' bounds and var_bits)
u32 max_value_bits(Value v, const Facts* facts = nullptr);

class Facts {
public:
    Facts() = default;

    bool empty() const noexcept { return head_ == nullptr; }
    u32 size() const noexcept { return n_; }

    // --- adding ---
    Facts with(const Fact& f) const;
    // cond holds (holds = true) or not (its negation: alg::iszero(cond))
    Facts with(Value cond, bool holds) const;
    Facts with_cond(Value cond) const { return with(Fact{FactKind::Cond, cond, {}, {}}); }
    Facts with_fresh() const { return with(Fact{FactKind::Fresh, {}, {}, {}}); }
    Facts with_rdzero() const { return with(Fact{FactKind::RdZero, {}, {}, {}}); }
    Facts with_var_bits(Value var, u32 bits) const {
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
    static Facts from(std::span<const Fact> oldest_first);

    // whether cond holds where the facts do: eval_bool(cond, this)
    // (compare.hpp) - the conditions, and the ranges they bound
    Tri is_known(Value cond) const;
    // the conditions alone, one at a time (python is_known: eval_bool(exp,
    // fact, symbolic=False) per fact, the newest first): cond or its
    // negation known, through BOOL / ISZERO / OR / AND, x < a known deciding
    // x < b (eval_bool's first step)
    Tri match(Value cond) const;
    // python decided: 0 where the facts say exp is false, 1 where true and
    // exp is a truth value (is_bool), else exp
    Value decided(Value exp) const;
    // what the conditions say of x's word (x compared with constants,
    // var_bits): the intersection of their bounds; nullopt when none
    std::optional<Range> bounds(Value x) const;
    // f(Value x, Value lo, Value hi) for every bound a condition puts on an
    // expression (compare.hpp cond_bounds; lo, hi: int Values), newest first
    template <class F>
    void each_bound(F&& f) const {
        if (!nbounds_) return;
        for (const Cell* c = head_; c; c = c->next)
            for (u32 i = 0; i < c->nb; ++i) f(c->b[i].x, c->b[i].lo, c->b[i].hi);
    }
    bool any_bound() const noexcept { return nbounds_ != 0; }

    // --- state changes ---
    // python forget: the conditions mentioning what changed dropped, the
    // memory facts whose value mentions it made unknown
    Facts forget(Forget what) const;
    // the same, for the facts mentioning any of these content flags
    // (F_STORAGE, F_STATE...: core/ops_gen.hpp)
    Facts forget_flags(u8 content_flags) const;
    // the facts but the memory's (Mem and Fresh)
    Facts without_memory() const;

    // --- memory (python write_memory, read_memory, known_zeroes) ---
    // what's known once value is written at [start, start + size); start,
    // size: expressions (a write that may go anywhere drops the memory facts)
    Facts write_memory(Value start, Value size, Value value) const;
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
    Facts map_mem_values(F&& f) const {
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

    bool operator==(const Facts& o) const noexcept;

private:
    struct Cell {
        const Cell* next;
        Fact f;
        // a condition's bounds (cond_bounds), in the arena
        const CondBound* b;
        u32 nb;
    };
    // a cell for f; its bounds computed, or taken from a cell of the same
    // fact (a rebuild)
    static const Cell* cons(const Fact& f, const Cell* next, const Cell* same = nullptr);
    // the list rebuilt from cells (oldest first), their bounds kept
    static Facts from_cells(std::span<const Cell* const> oldest_first);
    const Cell* head_ = nullptr;
    u32 n_ = 0;
    u32 nbounds_ = 0;  // the bounds of all the cells
};

}  // namespace pan::alg
