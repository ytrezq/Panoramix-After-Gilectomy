// Contexts: the memory a decompilation works in.
//
// Each function is decompiled on a context of its own: an Arena (4 MiB
// chunks, bump allocated, from a process-wide pool, given back at once when
// the context goes) holds every node it makes, and a HashCons table makes
// each distinct node one pointer (hash-consing: structural equality is word
// equality). The thread's context is cx(): a thread_local pointer set for a
// scope by ContextScope. Values never cross contexts by pointer: a value
// made on another context is imported (import_value) first.
//
// The global context holds the constants made by init(); it is frozen
// afterwards and every context looks it up first, so a constant is the same
// pointer everywhere (lock-free: the frozen table is never written again).
//
// Memory: the arena's chunks, the table and every module's memo tables are
// charged to the context's Budget (MemoryLimit past its limit).
#pragma once

#include <gmp.h>

#include <initializer_list>
#include <memory>
#include <optional>
#include <span>
#include <unordered_map>
#include <vector>

#include "core/base.hpp"
#include "core/budget.hpp"
#include "core/errors.hpp"
#include "core/memo.hpp"
#include "core/node.hpp"
#include "core/value.hpp"

namespace pan {

inline constexpr usize ARENA_CHUNK = usize(4) << 20;
inline constexpr usize CHUNK_POOL_MAX = 256;  // chunks kept for reuse (1 GiB)
inline constexpr usize CHUNK_POOL_KEEP = 16;  // kept between two decompilations

struct ContractShared;  // core/contract.hpp

// A bump allocator over chunks, freed as a whole.
class Arena {
public:
    explicit Arena(MemCharge* owner = nullptr) : owner_(owner) {}
    Arena(const Arena&) = delete;
    Arena& operator=(const Arena&) = delete;
    ~Arena() { release(); }

    // memory the caller writes all of, 16-byte aligned
    void* alloc_raw(usize n) {
        n = (n + 15) & ~usize(15);
        char* p = cur_;
        if (PAN_UNLIKELY(n > usize(end_ - p))) return grow(n);
        cur_ = p + n;
        return p;
    }
    // zeroed memory
    void* alloc(usize n);

    usize total() const noexcept { return total_; }  // the chunks' bytes
    bool owns(const void* p) const noexcept;
    void release() noexcept;
    void swap(Arena& o) noexcept;
    void set_owner(MemCharge* o) noexcept { owner_ = o; }

private:
    struct Chunk;
    void* grow(usize n);
    void new_chunk(usize payload);

    MemCharge* owner_ = nullptr;
    char* cur_ = nullptr;
    char* end_ = nullptr;
    Chunk* chunks_ = nullptr;
    usize total_ = 0;
};

// The hash-cons table: one node per distinct EXPR, LIST, BIGINT, BYTES of a
// context. Open addressing; a slot holds the node's pointer (48 bits) and
// 16 bits of its hash, compared before the node is read.
class HashCons {
public:
    explicit HashCons(MemCharge* owner = nullptr) : owner_(owner) {}
    HashCons(const HashCons&) = delete;
    HashCons& operator=(const HashCons&) = delete;
    ~HashCons();

    void init(usize cap = 4096);
    Value seq(Arena& a, NodeKind kind, u16 op, std::span<const Value> items, u8 add_flags);
    Value bigint(Arena& a, mpz_srcptr z);  // |z| >= 2^62 (mk_int decides)
    Value bytes(Arena& a, std::span<const u8> data);
    usize count() const noexcept { return count_; }
    usize table_bytes() const noexcept { return cap_ * 8; }
    void swap(HashCons& o) noexcept;
    void set_owner(MemCharge* o) noexcept { owner_ = o; }
    // the frozen table looked up first (the global context's)
    void set_parent(const HashCons* p) noexcept { parent_ = p; }

private:
    static constexpr u64 PTR_MASK = 0x0000ffffffffffffull;
    static u64 tag_of(u64 hash) noexcept { return (hash << 8) >> 48 << 48; }
    const NodeHeader* find_seq(u64 h, NodeKind kind, u16 op, std::span<const Value> items, usize* slot) const;
    const NodeHeader* find_big(u64 h, mpz_srcptr z, usize* slot) const;
    const NodeHeader* find_bytes(u64 h, std::span<const u8> data, usize* slot) const;
    void reserve_one();
    void grow();

    MemCharge* owner_ = nullptr;
    const HashCons* parent_ = nullptr;
    u64* table_ = nullptr;
    usize cap_ = 0;
    usize count_ = 0;
};

// Where a line came from (the pc of its instruction): kept beside the lines,
// so that two equal lines stay one node. Best effort: a line rebuilt by a
// pass inherits its origin's pc (inherit).
class PcMap {
public:
    void note(Value line, u32 pc) { pcs_.try_emplace(line.raw(), pc); }
    std::optional<u32> pc_of(Value line) const {
        auto it = pcs_.find(line.raw());
        if (it == pcs_.end()) return std::nullopt;
        return it->second;
    }
    void inherit(Value new_line, Value old_line) {
        if (new_line == old_line) return;
        if (auto pc = pc_of(old_line)) note(new_line, *pc);
    }
    usize size() const noexcept { return pcs_.size(); }
    void clear() noexcept { pcs_.clear(); }

private:
    friend class Context;
    std::unordered_map<u64, u32> pcs_;
};

int register_state_type();
template <class T>
struct StateId {
    static inline const int id = register_state_type();
};
inline constexpr int MAX_STATES = 64;

class Context final : public MemCharge {
public:
    // a fresh context charged to budget (MemoryLimit when it can't)
    static std::unique_ptr<Context> create(Budget& budget, const ContractShared* shared = nullptr);
    ~Context();
    Context(const Context&) = delete;
    Context& operator=(const Context&) = delete;

    Arena arena;
    HashCons hc;
    Budget& budget;
    PcMap pcs;
    const ContractShared* shared;  // the contract's read-only data (may be null)
    u64 node_count = 0;

    // per-module state, made on demand, freed with the context
    template <class T>
    T& state() {
        int id = StateId<T>::id;
        ModuleState* s = states_[id].get();
        if (PAN_UNLIKELY(!s)) {
            s = new T();
            states_[id].reset(s);
        }
        return *static_cast<T*>(s);
    }
    template <class T>
    T* state_if() noexcept {
        return static_cast<T*>(states_[StateId<T>::id].get());
    }
    template <class T>
    void drop_state() noexcept {
        states_[StateId<T>::id].reset();
    }

    // every state's clear_caches (python's clear_caches)
    void clear_caches();
    // a fresh arena holding the roots (imported), with the states that keep
    // something (imported too) and the pcs of the lines still alive; the
    // rest freed. On an error (MemoryLimit...) the context is as it was.
    void compact(std::span<Value> roots);
    // what counts against the budget: arena + table + memo tables
    usize usage() const noexcept { return charged_; }
    bool is_global() const noexcept;

    // MemCharge: the memo tables' bytes, to the budget
    void charge(isize bytes) override;

private:
    Context(Budget& b, const ContractShared* s);
    friend class Importer;
    friend void init();
    usize charged_ = 0;
    std::unique_ptr<ModuleState> states_[MAX_STATES];
};

// the thread's context
inline thread_local Context* tl_ctx PAN_TLS = nullptr;
inline Context& cx() noexcept { return *tl_ctx; }

// makes c the thread's context for a scope (nests); the memo tables made
// meanwhile are charged to it
class ContextScope {
public:
    explicit ContextScope(Context& c) noexcept : prev_(tl_ctx), charge_(&c) { tl_ctx = &c; }
    ~ContextScope() { tl_ctx = prev_; }
    ContextScope(const ContextScope&) = delete;
    ContextScope& operator=(const ContextScope&) = delete;

private:
    Context* prev_;
    MemChargeScope charge_;
};

// the process-wide context: the constants made by init(), frozen after
Context& global_context() noexcept;
// once per process (thread-safe): the global context and its constants
void init();
// the chunks kept for reuse beyond keep given back to the system
void chunk_pool_trim(usize keep = CHUNK_POOL_KEEP);

// --- making values on the thread's context (the only way nodes are made) ---

// an EXPR node (hash-consed); its operands' count checked against the op
// table (InternalError). A leaf op without operands: its Leaf immediate.
Value mk(Op op, std::span<const Value> args);
inline Value mk(Op op, std::initializer_list<Value> args) { return mk(op, std::span<const Value>(args.begin(), args.size())); }
template <class... A>
    requires(std::same_as<A, Value> && ...)
inline Value mk(Op op, A... args) {
    const Value a[] = {args..., Value()};
    return mk(op, std::span<const Value>(a, sizeof...(A)));
}
Value mk_list(std::span<const Value> items, ListKind kind = ListKind::Values);
inline Value mk_list(std::initializer_list<Value> items, ListKind kind = ListKind::Values) {
    return mk_list(std::span<const Value>(items.begin(), items.size()), kind);
}
inline Value mk_trace(std::span<const Value> lines) { return mk_list(lines, ListKind::Trace); }
inline Value mk_trace(std::initializer_list<Value> lines) { return mk_list(lines, ListKind::Trace); }
// a node of orig's kind and op with these operands: orig itself when they
// are its own (a walk that changed nothing returns the same value)
Value mk_like(Value orig, std::span<const Value> args);

// ints: small when they fit 63 bits, a BIGINT node else
Value mk_int(i64 x);
Value mk_uint(u64 x);
Value mk_int_mpz(mpz_srcptr z);  // (not an overload of mk_int: mk_int(0) would be ambiguous)
Value mk_int_be(std::span<const u8> big_endian);  // a PUSHn immediate
// a contract's string (raw bytes; text only when printed)
Value mk_bytes(std::span<const u8> data);

// A value of another context rebuilt on the thread's context (nodes
// hash-consed again; immediates and small ints as they are). One Importer
// keeps its memo across calls: shared subtrees are imported once.
class Importer {
public:
    Value operator()(Value v);
    // what a value of the source context became, if it was imported
    std::optional<Value> lookup(Value old) const;

private:
    struct Slot {
        u64 key, val;
    };
    std::vector<Slot> memo_;
    usize count_ = 0;
    const Slot* find(u64 key) const;
    void put(u64 key, Value v);
};
Value import_value(Value v);

}  // namespace pan
