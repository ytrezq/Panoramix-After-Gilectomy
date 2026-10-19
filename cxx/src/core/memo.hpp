// Memo tables: open-addressing hash maps keyed by 64-bit words (a Value, or
// a pair / triple of raw words), one per module and context - so per job, no
// locks -, their bytes charged to the context's budget; and ModuleState, the
// base of a module's per-context state (its memo tables), made on demand by
// ctx.state<T>(). A port of the old runtime's maps.hpp and ModuleState.
#pragma once

#include <cassert>
#include <concepts>
#include <cstddef>
#include <cstdlib>
#include <new>
#include <type_traits>
#include <utility>

#include "core/base.hpp"

namespace pan {

class Value;     // core/value.hpp: one 64-bit word; u64 raw(), Value::from_raw(u64)
class Importer;  // core/context.hpp: a value of another context into cx()

// ---- memory charging ------------------------------------------------------

// Where a memo's bytes are counted (the context's budget): charge(+n) before
// n bytes are taken - it may throw (MemoryLimit), nothing is taken then -,
// charge(-n) when they are given back (must not throw then).
struct MemCharge {
    virtual void charge(isize bytes) = 0;

protected:
    ~MemCharge() = default;
};

// The charger a memo takes at its first growth when none was bound: the
// current context's (ContextScope sets it, through a MemChargeScope);
// nullptr: the bytes are not counted.
inline thread_local MemCharge* tl_mem_charge = nullptr;

class MemChargeScope {  // nests
public:
    explicit MemChargeScope(MemCharge* c) noexcept : saved_(tl_mem_charge) { tl_mem_charge = c; }
    ~MemChargeScope() { tl_mem_charge = saved_; }
    MemChargeScope(const MemChargeScope&) = delete;
    MemChargeScope& operator=(const MemChargeScope&) = delete;

private:
    MemCharge* saved_;
};

// ---- keys -----------------------------------------------------------------

// a one-word key: anything with u64 raw() (Value); equal when the words are
template <class T>
concept RawWord = requires(const T& t) {
    { t.raw() } -> std::same_as<u64>;
};

// several values' raw words; the first one must not be 0 (NIL): it marks an
// empty slot
struct Key2 {
    u64 a, b;
    bool operator==(const Key2&) const = default;
};
struct Key3 {
    u64 a, b, c;
    bool operator==(const Key3&) const = default;
};
template <RawWord A, RawWord B>
constexpr Key2 key2(const A& a, const B& b) noexcept {
    return {a.raw(), b.raw()};
}
template <RawWord A, RawWord B, RawWord C>
constexpr Key3 key3(const A& a, const B& b, const C& c) noexcept {
    return {a.raw(), b.raw(), c.raw()};
}
// a key's word back as a value (a compaction re-keys through the Importer)
template <class V = Value>
constexpr V key_value(u64 w) noexcept {
    return V::from_raw(w);
}

// the first half of murmur3's fmix64; the index is the hash's low bits
constexpr u64 map_hash(u64 k) noexcept {
    k ^= k >> 33;
    k *= 0xff51afd7ed558ccdull;
    k ^= k >> 29;
    return k;
}
template <RawWord T>
constexpr u64 map_hash(const T& k) noexcept {
    return map_hash(k.raw());
}
constexpr u64 map_hash(const Key2& k) noexcept {
    u64 h = k.a * 0x9e3779b97f4a7c15ull;
    h = (h << 29 | h >> 35) ^ k.b;
    return map_hash(h);
}
constexpr u64 map_hash(const Key3& k) noexcept {
    u64 h = k.a * 0x9e3779b97f4a7c15ull;
    h = (h << 29 | h >> 35) ^ k.b;
    h *= 0xc4ceb9fe1a85ec53ull;
    h = (h << 31 | h >> 33) ^ k.c;
    return map_hash(h);
}

// a slot is empty when its key's first word is 0
constexpr bool key_empty(u64 k) noexcept { return k == 0; }
template <RawWord T>
constexpr bool key_empty(const T& k) noexcept {
    return k.raw() == 0;
}
constexpr bool key_empty(const Key2& k) noexcept { return k.a == 0; }
constexpr bool key_empty(const Key3& k) noexcept { return k.a == 0; }

template <class K>
constexpr bool key_eq(const K& x, const K& y) noexcept {
    if constexpr (RawWord<K>)
        return x.raw() == y.raw();
    else
        return x == y;
}

// ---- Memo -----------------------------------------------------------------

// Open addressing, linear probing, half full at most (64 slots first, grown
// by two, by four past 4096 slots); keys and values inline in zeroed
// (calloc) slots: K and V trivially copyable, all-zero bytes a valid V (0,
// NIL...). No erase: a memo is only filled, then cleared whole. The bytes
// are charged to the bound MemCharge, or else to the current one
// (tl_mem_charge) at the first growth, and given back to that same one: it
// must outlive the memo (the budget outlives the context and its states).
// The iteration order is the table's (addresses): nothing may rely on it.
template <class K, class V>
class Memo {
public:
    struct Slot {
        K key;
        [[no_unique_address]] V val;
    };

    Memo() = default;
    explicit Memo(MemCharge* c) noexcept : bound_(c) {}
    Memo(const Memo&) = delete;
    Memo& operator=(const Memo&) = delete;
    Memo(Memo&& o) noexcept { take(o); }
    Memo& operator=(Memo&& o) noexcept {
        if (this != &o) {
            free_slots();
            take(o);
        }
        return *this;
    }
    ~Memo() { free_slots(); }
    void swap(Memo& o) noexcept {
        std::swap(slots_, o.slots_);
        std::swap(cap_, o.cap_);
        std::swap(count_, o.count_);
        std::swap(charged_, o.charged_);
        std::swap(bound_, o.bound_);
    }

    // the charger of the next first growth (tests, importers); nullptr:
    // the current one then
    void bind(MemCharge* c) noexcept { bound_ = c; }

    usize size() const noexcept { return count_; }
    bool empty() const noexcept { return count_ == 0; }
    usize capacity() const noexcept { return cap_; }
    usize bytes() const noexcept { return cap_ * sizeof(Slot); }  // what is charged

    V* find(const K& k) noexcept {
        if (!cap_) return nullptr;
        usize mask = cap_ - 1;
        for (usize i = usize(map_hash(k)) & mask;; i = (i + 1) & mask) {
            Slot& s = slots_[i];
            if (key_empty(s.key)) return nullptr;
            if (key_eq(s.key, k)) return &s.val;
        }
    }
    const V* find(const K& k) const noexcept { return const_cast<Memo*>(this)->find(k); }
    bool contains(const K& k) const noexcept { return find(k) != nullptr; }

    // the value of k, inserted as V{} first if absent (*inserted says which);
    // the reference holds until the next insertion
    V& slot(const K& k, bool* inserted = nullptr) {
        assert(!key_empty(k));
        if ((count_ + 1) * 2 > cap_) grow();
        usize mask = cap_ - 1;
        for (usize i = usize(map_hash(k)) & mask;; i = (i + 1) & mask) {
            Slot& s = slots_[i];
            if (key_empty(s.key)) {
                s.key = k;
                s.val = V{};
                ++count_;
                if (inserted) *inserted = true;
                return s.val;
            }
            if (key_eq(s.key, k)) {
                if (inserted) *inserted = false;
                return s.val;
            }
        }
    }
    V& operator[](const K& k) { return slot(k); }
    void put(const K& k, const V& v) { slot(k) = v; }
    // inserts k (a set's add): true when it wasn't there
    bool add(const K& k) {
        bool ins;
        slot(k, &ins);
        return ins;
    }

    // emptied, its memory given back (python's clear_caches)
    void clear() noexcept {
        free_slots();
        count_ = 0;
    }
    // f(const K&, const V&) on every entry, in table order
    template <class F>
    void each(F&& f) const {
        for (usize i = 0; i < cap_; i++)
            if (!key_empty(slots_[i].key)) f(std::as_const(slots_[i].key), std::as_const(slots_[i].val));
    }
    // room for n entries without a growth
    void reserve(usize n) {
        while (n * 2 > cap_) grow();
    }

private:
    static_assert(std::is_trivially_copyable_v<K> && std::is_trivially_destructible_v<K>);
    static_assert(std::is_trivially_copyable_v<V> && std::is_trivially_destructible_v<V>);
    static_assert(alignof(Slot) <= alignof(std::max_align_t));

    void grow() {
        usize ncap = cap_ ? (cap_ >= 4096 ? cap_ * 4 : cap_ * 2) : 64;
        MemCharge* c = cap_ ? charged_ : (bound_ ? bound_ : tl_mem_charge);
        isize delta = isize((ncap - cap_) * sizeof(Slot));
        if (c) c->charge(delta);  // throws past the limit: the memo as it was
        auto* fresh = static_cast<Slot*>(std::calloc(ncap, sizeof(Slot)));
        if (!fresh) {
            if (c) c->charge(-delta);
            throw std::bad_alloc();
        }
        charged_ = c;
        usize mask = ncap - 1;
        for (usize i = 0; i < cap_; i++) {
            const Slot& s = slots_[i];
            if (key_empty(s.key)) continue;
            usize j = usize(map_hash(s.key)) & mask;
            while (!key_empty(fresh[j].key)) j = (j + 1) & mask;
            fresh[j] = s;
        }
        std::free(slots_);
        slots_ = fresh;
        cap_ = ncap;
    }
    void free_slots() noexcept {
        if (charged_ && cap_) charged_->charge(-isize(cap_ * sizeof(Slot)));
        std::free(slots_);
        slots_ = nullptr;
        cap_ = 0;
        charged_ = nullptr;
    }
    void take(Memo& o) noexcept {
        slots_ = o.slots_;
        cap_ = o.cap_;
        count_ = o.count_;
        charged_ = o.charged_;
        bound_ = o.bound_;
        o.slots_ = nullptr;
        o.cap_ = o.count_ = 0;
        o.charged_ = nullptr;
    }

    Slot* slots_ = nullptr;
    usize cap_ = 0;
    usize count_ = 0;
    MemCharge* charged_ = nullptr;  // holds the bytes of the slots (cap_ > 0)
    MemCharge* bound_ = nullptr;
};

// a set: a memo without values
template <class K>
class MemoSet {
public:
    MemoSet() = default;
    explicit MemoSet(MemCharge* c) noexcept : map_(c) {}
    void bind(MemCharge* c) noexcept { map_.bind(c); }
    bool add(const K& k) { return map_.add(k); }
    bool contains(const K& k) const noexcept { return map_.contains(k); }
    usize size() const noexcept { return map_.size(); }
    bool empty() const noexcept { return map_.empty(); }
    usize bytes() const noexcept { return map_.bytes(); }
    void clear() noexcept { map_.clear(); }
    void reserve(usize n) { map_.reserve(n); }
    void swap(MemoSet& o) noexcept { map_.swap(o.map_); }
    template <class F>
    void each(F&& f) const {
        map_.each([&](const K& k, const Unit&) { f(k); });
    }

private:
    struct Unit {};
    Memo<K, Unit> map_;
};

// ---- ModuleState ----------------------------------------------------------

// A module's state on a context (its memo tables, its scratch): made the
// first time the module asks (Context::state<T>(), default-constructed),
// freed with the context. A compaction (Context::compact) drops it, unless
// the module keeps what it needs: compact_prepare imports that into new
// storage (it may throw - the state as it was is then kept, compact_abort
// called), compact_commit switches to it once every state is prepared.
class ModuleState {
public:
    ModuleState() = default;
    ModuleState(const ModuleState&) = delete;
    ModuleState& operator=(const ModuleState&) = delete;
    virtual ~ModuleState() = default;

    // python's clear_caches (the asm's: set_variables, a change of the free
    // memory pointer): the state's memo tables forgotten - in place, the
    // state may be in use up the stack. The default: nothing to forget.
    virtual void clear_caches() {}

    // false: the state is dropped (the default: caches)
    virtual bool compact_prepare(Importer&) { return false; }
    virtual void compact_commit() noexcept {}
    virtual void compact_abort() noexcept {}
};

}  // namespace pan
