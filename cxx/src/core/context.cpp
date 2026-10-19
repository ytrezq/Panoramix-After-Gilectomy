// Contexts, arenas, the hash-consing, the import of values.
#include "core/context.hpp"

#include <gmpxx.h>

#include <algorithm>
#include <atomic>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <new>
#include <string>

#include "core/platform.hpp"
#include "core/sync.hpp"

namespace pan {

// --- the chunk pool ---

struct Arena::Chunk {
    Chunk* next;
    usize size;  // the whole mapping
    usize used;  // the payload used, once it isn't the current one
    usize pad_;
    char* data() { return reinterpret_cast<char*>(this + 1); }
};

namespace {

SpinLock pool_lock;
void* pool_head = nullptr;  // a Chunk*, linked through its first word
usize pool_count = 0;

void* pool_pop() {
    pool_lock.lock();
    void* c = pool_head;
    if (c) {
        pool_head = *static_cast<void**>(c);
        pool_count--;
    }
    pool_lock.unlock();
    return c;
}

bool pool_push(void* c) {
    pool_lock.lock();
    bool kept = pool_count < CHUNK_POOL_MAX;
    if (kept) {
        *static_cast<void**>(c) = pool_head;
        pool_head = c;
        pool_count++;
    }
    pool_lock.unlock();
    return kept;
}

constexpr usize ARENA_MAX_BLOCK = usize(1) << 46;  // a bigger request is a size that wrapped

[[noreturn]] PAN_COLD void no_system_memory() { throw MemoryLimit("out of memory: the system gave no more (mmap failed)"); }

}  // namespace

void chunk_pool_trim(usize keep) {
    for (;;) {
        pool_lock.lock();
        bool more = pool_count > keep;
        pool_lock.unlock();
        if (!more) return;
        void* c = pool_pop();
        if (!c) return;
        platform::unmap(c, ARENA_CHUNK);
    }
}

// --- the arena ---

void* Arena::alloc(usize n) {
    void* p = alloc_raw(n);
    std::memset(p, 0, (n + 15) & ~usize(15));
    return p;
}

bool Arena::owns(const void* p) const noexcept {
    auto a = reinterpret_cast<uintptr_t>(p);
    for (Chunk* c = chunks_; c; c = c->next) {
        auto b = reinterpret_cast<uintptr_t>(c);
        if (a >= b && a < b + c->size) return true;
    }
    return false;
}

void Arena::new_chunk(usize payload) {
    if (payload > ARENA_MAX_BLOCK) no_system_memory();
    usize size = (payload + sizeof(Chunk) + 15) & ~usize(15);
    if (size < ARENA_CHUNK) size = ARENA_CHUNK;
    size = (size + platform::HUGE_PAGE - 1) & ~(platform::HUGE_PAGE - 1);
    if (owner_) owner_->charge(isize(size));  // MemoryLimit past the budget
    void* m = nullptr;
    if (size == ARENA_CHUNK) m = pool_pop();
    if (!m) m = platform::map_huge(size);
    if (!m) m = platform::map_pages(size);
    if (!m) {
        if (owner_) owner_->charge(-isize(size));
        no_system_memory();
    }
    auto* c = static_cast<Chunk*>(m);
    if (chunks_) chunks_->used = usize(cur_ - chunks_->data());
    c->next = chunks_;
    c->size = size;
    c->used = 0;
    chunks_ = c;
    cur_ = c->data();
    end_ = reinterpret_cast<char*>(c) + size;
    total_ += size;
}

void* Arena::grow(usize n) {
    new_chunk(n);
    char* p = cur_;
    cur_ = p + n;
    return p;
}

void Arena::release() noexcept {
    for (Chunk* c = chunks_; c;) {
        Chunk* next = c->next;
        usize size = c->size;
        if (size == ARENA_CHUNK) {
            // reused as it is: alloc() zeroes, alloc_raw's callers write all
            if (!pool_push(c)) platform::unmap(c, size);
        } else {
            platform::unmap(c, size);
        }
        if (owner_) owner_->charge(-isize(size));
        c = next;
    }
    chunks_ = nullptr;
    cur_ = end_ = nullptr;
    total_ = 0;
}

void Arena::swap(Arena& o) noexcept {
    std::swap(owner_, o.owner_);
    std::swap(cur_, o.cur_);
    std::swap(end_, o.end_);
    std::swap(chunks_, o.chunks_);
    std::swap(total_, o.total_);
}

// --- the hash-cons table ---

namespace {

u64* table_alloc(usize slots) {
    usize bytes = slots * 8;
    if (bytes < platform::HUGE_PAGE) return static_cast<u64*>(std::calloc(slots, 8));
    bytes = (bytes + platform::HUGE_PAGE - 1) & ~(platform::HUGE_PAGE - 1);
    void* m = platform::map_huge(bytes);
    if (!m) m = platform::map_pages(bytes);
    return static_cast<u64*>(m);
}

void table_free(u64* t, usize slots) noexcept {
    if (!t) return;
    usize bytes = slots * 8;
    if (bytes < platform::HUGE_PAGE)
        std::free(t);
    else
        platform::unmap(t, (bytes + platform::HUGE_PAGE - 1) & ~(platform::HUGE_PAGE - 1));
}

}  // namespace

HashCons::~HashCons() {
    table_free(table_, cap_);
    if (owner_ && cap_) owner_->charge(-isize(cap_ * 8));
}

void HashCons::init(usize cap) {
    if (owner_) owner_->charge(isize(cap * 8));
    table_ = table_alloc(cap);
    if (!table_) {
        if (owner_) owner_->charge(-isize(cap * 8));
        throw MemoryLimit("out of memory: the system gave no more (malloc failed)");
    }
    cap_ = cap;
    count_ = 0;
}

void HashCons::swap(HashCons& o) noexcept {
    std::swap(owner_, o.owner_);
    std::swap(parent_, o.parent_);
    std::swap(table_, o.table_);
    std::swap(cap_, o.cap_);
    std::swap(count_, o.count_);
}

void HashCons::grow() {
    usize ncap = cap_ * 2;
    if (cap_ >= (usize(1) << 16)) ncap *= 2;  // four times past 2^16 slots
    if (owner_) owner_->charge(isize((ncap - cap_) * 8));
    u64* fresh = table_alloc(ncap);
    if (!fresh) {
        if (owner_) owner_->charge(-isize((ncap - cap_) * 8));
        throw MemoryLimit("out of memory: the system gave no more (malloc failed)");
    }
    usize mask = ncap - 1;
    for (usize i = 0; i < cap_; i++) {
        u64 s = table_[i];
        if (!s) continue;
        auto* n = reinterpret_cast<const NodeHeader*>(s & PTR_MASK);
        usize j = n->hash & mask;
        while (fresh[j]) j = (j + 1) & mask;
        fresh[j] = s;
    }
    table_free(table_, cap_);
    table_ = fresh;
    cap_ = ncap;
}

void HashCons::reserve_one() {
    if (PAN_UNLIKELY(!table_)) init();
    if (PAN_UNLIKELY((count_ + 1) * 2 > cap_)) grow();
}

const NodeHeader* HashCons::find_seq(u64 h, NodeKind kind, u16 op, std::span<const Value> items,
                                     usize* slot) const {
    if (!table_) return nullptr;
    usize mask = cap_ - 1;
    u64 tag = tag_of(h);
    usize n = items.size();
    for (usize i = h & mask;; i = (i + 1) & mask) {
        u64 s = table_[i];
        if (!s) {
            if (slot) *slot = i;
            return nullptr;
        }
        if ((s ^ tag) >> 48) continue;  // another tag: another hash
        auto* node = reinterpret_cast<const NodeHeader*>(s & PTR_MASK);
        if (node->hash != h || node->kind != u16(kind) || node->op != op || node->size != n) continue;
        if (n == 0 || std::memcmp(node_args(node), items.data(), n * 8) == 0) return node;
    }
}

const NodeHeader* HashCons::find_big(u64 h, mpz_srcptr z, usize* slot) const {
    if (!table_) return nullptr;
    usize mask = cap_ - 1;
    u64 tag = tag_of(h);
    usize limbs = usize(z->_mp_size < 0 ? -z->_mp_size : z->_mp_size);
    u16 neg = z->_mp_size < 0;
    for (usize i = h & mask;; i = (i + 1) & mask) {
        u64 s = table_[i];
        if (!s) {
            if (slot) *slot = i;
            return nullptr;
        }
        if ((s ^ tag) >> 48) continue;
        auto* node = reinterpret_cast<const NodeHeader*>(s & PTR_MASK);
        if (node->hash != h || node->kind != u16(NodeKind::BigInt) || node->op != neg || node->size != limbs)
            continue;
        if (std::memcmp(node_limbs(node), z->_mp_d, limbs * sizeof(mp_limb_t)) == 0) return node;
    }
}

const NodeHeader* HashCons::find_bytes(u64 h, std::span<const u8> data, usize* slot) const {
    if (!table_) return nullptr;
    usize mask = cap_ - 1;
    u64 tag = tag_of(h);
    for (usize i = h & mask;; i = (i + 1) & mask) {
        u64 s = table_[i];
        if (!s) {
            if (slot) *slot = i;
            return nullptr;
        }
        if ((s ^ tag) >> 48) continue;
        auto* node = reinterpret_cast<const NodeHeader*>(s & PTR_MASK);
        if (node->hash != h || node->kind != u16(NodeKind::Bytes) || node->size != data.size()) continue;
        if (data.empty() || std::memcmp(node_data(node), data.data(), data.size()) == 0) return node;
    }
}

Value HashCons::seq(Arena& a, NodeKind kind, u16 op, std::span<const Value> items, u8 add_flags) {
    u64 h = hash_seq(kind, op, items, add_flags);
    if (parent_)
        if (const NodeHeader* g = parent_->find_seq(h, kind, op, items, nullptr)) return Value::of(g);
    reserve_one();
    usize i;
    if (const NodeHeader* n = find_seq(h, kind, op, items, &i)) return Value::of(n);
    if (items.size() > 0xffffffffu) throw SizeLimit("a node has too many operands");
    usize n = items.size();
    auto* node = static_cast<NodeHeader*>(a.alloc_raw(node_bytes(n * 8)));
    node->kind = u16(kind);
    node->op = op;
    node->size = u32(n);
    node->hash = h;
    if (n) std::memcpy(const_cast<Value*>(node_args(node)), items.data(), n * 8);
    table_[i] = tag_of(h) | reinterpret_cast<u64>(node);
    count_++;
    if (tl_ctx) tl_ctx->node_count++;
    return Value::of(node);
}

Value HashCons::bigint(Arena& a, mpz_srcptr z) {
    u64 h = hash_big(z);
    if (parent_)
        if (const NodeHeader* g = parent_->find_big(h, z, nullptr)) return Value::of(g);
    reserve_one();
    usize i;
    if (const NodeHeader* n = find_big(h, z, &i)) return Value::of(n);
    usize limbs = usize(z->_mp_size < 0 ? -z->_mp_size : z->_mp_size);
    auto* node = static_cast<NodeHeader*>(a.alloc_raw(node_bytes(limbs * sizeof(mp_limb_t))));
    node->kind = u16(NodeKind::BigInt);
    node->op = z->_mp_size < 0;
    node->size = u32(limbs);
    node->hash = h;
    std::memcpy(const_cast<mp_limb_t*>(node_limbs(node)), z->_mp_d, limbs * sizeof(mp_limb_t));
    table_[i] = tag_of(h) | reinterpret_cast<u64>(node);
    count_++;
    if (tl_ctx) tl_ctx->node_count++;
    return Value::of(node);
}

Value HashCons::bytes(Arena& a, std::span<const u8> data) {
    u64 h = hash_bytes(data);
    if (parent_)
        if (const NodeHeader* g = parent_->find_bytes(h, data, nullptr)) return Value::of(g);
    reserve_one();
    usize i;
    if (const NodeHeader* n = find_bytes(h, data, &i)) return Value::of(n);
    if (data.size() > 0xffffffffu) throw SizeLimit("a byte string is too long");
    auto* node = static_cast<NodeHeader*>(a.alloc(node_bytes(data.size())));  // zero padded
    node->kind = u16(NodeKind::Bytes);
    node->op = 0;
    node->size = u32(data.size());
    node->hash = h;
    if (!data.empty()) std::memcpy(const_cast<u8*>(node_data(node)), data.data(), data.size());
    table_[i] = tag_of(h) | reinterpret_cast<u64>(node);
    count_++;
    if (tl_ctx) tl_ctx->node_count++;
    return Value::of(node);
}

// --- contexts ---

int register_state_type() {
    static std::atomic<int> next{0};
    int id = next.fetch_add(1);
    if (id >= MAX_STATES) std::abort();  // a programming error: more module states than MAX_STATES
    return id;
}

namespace {
Context* g_global = nullptr;
std::once_flag g_init_once;
}  // namespace

Context::Context(Budget& b, const ContractShared* s) : arena(this), hc(this), budget(b), shared(s) {}

std::unique_ptr<Context> Context::create(Budget& budget, const ContractShared* shared) {
    std::unique_ptr<Context> c(new Context(budget, shared));
    c->hc.init();
    if (g_global) c->hc.set_parent(&g_global->hc);
    return c;
}

Context::~Context() {
    // the states first: their memo tables give their bytes back
    for (auto& s : states_) s.reset();
}

bool Context::is_global() const noexcept { return this == g_global; }

void Context::charge(isize bytes) {
    budget.charge(bytes);
    charged_ += usize(bytes);
}

void Context::clear_caches() {
    for (auto& s : states_)
        if (s) s->clear_caches();
}

void Context::compact(std::span<Value> roots) {
    Arena old_arena(this);
    HashCons old_hc(this);
    old_arena.swap(arena);
    old_hc.swap(hc);
    u64 old_nodes = node_count;
    std::vector<int> kept;
    PcMap new_pcs;
    std::vector<Value> new_roots(roots.begin(), roots.end());
    try {
        hc.set_parent(g_global && this != g_global ? &g_global->hc : nullptr);
        hc.init();
        node_count = 0;
        Importer imp;
        for (Value& r : new_roots) r = imp(r);
        for (int i = 0; i < MAX_STATES; i++)
            if (states_[i] && states_[i]->compact_prepare(imp)) kept.push_back(i);
        for (auto& [line, pc] : pcs.pcs_)
            if (auto nl = imp.lookup(Value::from_raw(line))) new_pcs.pcs_.try_emplace(nl->raw(), pc);
    } catch (...) {
        // the old arena put back: what was made in the new one goes
        for (int i : kept) states_[i]->compact_abort();
        arena.release();
        arena.swap(old_arena);
        hc.swap(old_hc);
        node_count = old_nodes;
        throw;
    }
    std::copy(new_roots.begin(), new_roots.end(), roots.begin());
    for (int i = 0; i < MAX_STATES; i++) {
        if (!states_[i]) continue;
        bool keep = false;
        for (int k : kept) keep |= k == i;
        if (keep)
            states_[i]->compact_commit();
        else
            states_[i].reset();
    }
    pcs.pcs_.swap(new_pcs.pcs_);
    old_arena.release();
}

Context& global_context() noexcept { return *g_global; }

void init() {
    std::call_once(g_init_once, [] {
        static Budget global_budget(Budget::Limits{});
        g_global = new Context(global_budget, nullptr);
        g_global->hc.init(1 << 14);
        ContextScope scope(*g_global);
        // the frequent constants: one pointer everywhere
        mpz_class v;
        for (unsigned bits : {62u, 63u, 64u, 128u, 160u, 192u, 224u, 255u, 256u}) {
            mpz_ui_pow_ui(v.get_mpz_t(), 2, bits);
            mk_int_mpz(v.get_mpz_t());
            mpz_class m = v - 1;
            mk_int_mpz(m.get_mpz_t());
            mpz_class n = -v;
            mk_int_mpz(n.get_mpz_t());
        }
        // frozen from here on: the other contexts look it up first
    });
}

// --- making values ---

[[noreturn]] PAN_COLD static void bad_arity(Op op, usize n) {
    throw InternalError(std::string("mk: ") + op_name(op) + " with " + std::to_string(n) + " operands");
}

Value mk(Op op, std::span<const Value> args) {
    const OpInfo& i = info(op);
    usize n = args.size();
    if (PAN_UNLIKELY(!i.defined)) bad_arity(op, n);
    if (i.leaf) {
        if (n != 0) bad_arity(op, n);
        return Value::leaf(op);
    }
    if (PAN_UNLIKELY(n < i.arity_min || (i.arity_max != 255 && n > i.arity_max))) bad_arity(op, n);
    Context& c = cx();
    return c.hc.seq(c.arena, NodeKind::Expr, u16(op), args, i.content);
}

Value mk_list(std::span<const Value> items, ListKind kind) {
    Context& c = cx();
    return c.hc.seq(c.arena, NodeKind::List, u16(kind), items, 0);
}

Value mk_like(Value orig, std::span<const Value> args) {
    if (args.size() == orig.size() && (args.empty() || std::memcmp(args.data(), orig.data(), args.size() * 8) == 0))
        return orig;
    if (orig.is_list()) return mk_list(args, ListKind(orig.node()->op));
    return mk(orig.op(), args);
}

Value mk_int(i64 x) {
    if (x >= SMALL_MIN && x <= SMALL_MAX) return Value::small(x);
    mpz_t z;
    mpz_init_set_si(z, x);
    Value v = mk_int_mpz(z);
    mpz_clear(z);
    return v;
}

Value mk_uint(u64 x) {
    if (x <= u64(SMALL_MAX)) return Value::small(i64(x));
    mpz_t z;
    mpz_init_set_ui(z, x);
    Value v = mk_int_mpz(z);
    mpz_clear(z);
    return v;
}

Value mk_int_mpz(mpz_srcptr z) {
    if (mpz_fits_slong_p(z)) {
        long x = mpz_get_si(z);
        if (x >= SMALL_MIN && x <= SMALL_MAX) return Value::small(x);
    }
    Context& c = cx();
    return c.hc.bigint(c.arena, z);
}

Value mk_int_be(std::span<const u8> p) {
    usize n = p.size();
    if (n <= 8) {
        u64 x = 0;
        for (usize i = 0; i < n; i++) x = x << 8 | p[i];
        return mk_uint(x);
    }
    mpz_t z;
    mpz_init(z);
    mpz_import(z, n, 1, 1, 0, 0, p.data());
    Value v = mk_int_mpz(z);
    mpz_clear(z);
    return v;
}

Value mk_bytes(std::span<const u8> data) {
    Context& c = cx();
    return c.hc.bytes(c.arena, data);
}

std::optional<i64> Value::as_i64() const noexcept {
    if (is_small()) return small_val();
    if (!is_big()) return std::nullopt;
    mpz_t t;
    mpz_srcptr z = big_view(*this, t);
    if (!mpz_fits_slong_p(z)) return std::nullopt;
    return i64(mpz_get_si(z));
}

// --- the import of values ---

const Importer::Slot* Importer::find(u64 key) const {
    if (memo_.empty()) return nullptr;
    usize mask = memo_.size() - 1;
    for (usize i = map_hash(key) & mask;; i = (i + 1) & mask) {
        if (!memo_[i].key) return nullptr;
        if (memo_[i].key == key) return &memo_[i];
    }
}

void Importer::put(u64 key, Value v) {
    if ((count_ + 1) * 2 > memo_.size()) {
        std::vector<Slot> old(std::move(memo_));
        memo_.assign(old.empty() ? 256 : old.size() * 2, Slot{0, 0});
        usize mask = memo_.size() - 1;
        for (auto& s : old) {
            if (!s.key) continue;
            usize i = map_hash(s.key) & mask;
            while (memo_[i].key) i = (i + 1) & mask;
            memo_[i] = s;
        }
    }
    usize mask = memo_.size() - 1;
    usize i = map_hash(key) & mask;
    while (memo_[i].key && memo_[i].key != key) i = (i + 1) & mask;
    if (!memo_[i].key) count_++;
    memo_[i] = {key, v.raw()};
}

std::optional<Value> Importer::lookup(Value old) const {
    if (!old.is_node()) return old;
    if (const Slot* s = find(old.raw())) return Value::from_raw(s->val);
    return std::nullopt;
}

Value Importer::operator()(Value v) {
    if (!v.is_node()) return v;
    if (g_global && g_global->arena.owns(v.node())) return v;  // the global layer is shared
    if (const Slot* s = find(v.raw())) return Value::from_raw(s->val);
    check_stack();
    const NodeHeader* n = v.node();
    Value r;
    switch (NodeKind(n->kind)) {
        case NodeKind::BigInt: {
            mpz_t t;
            r = mk_int_mpz(big_view(v, t));
            break;
        }
        case NodeKind::Bytes:
            r = mk_bytes(v.bytes());
            break;
        case NodeKind::Expr:
        case NodeKind::List: {
            u32 count = n->size;
            std::vector<Value> items(count);
            for (u32 i = 0; i < count; i++) items[i] = (*this)(node_args(n)[i]);
            Context& c = cx();
            r = c.hc.seq(c.arena, NodeKind(n->kind), n->op, items,
                         n->kind == u16(NodeKind::Expr) ? info(Op(n->op)).content : u8(0));
            break;
        }
        default:
            r = v;
    }
    put(v.raw(), r);
    return r;
}

Value import_value(Value v) {
    Importer imp;
    return imp(v);
}

}  // namespace pan
