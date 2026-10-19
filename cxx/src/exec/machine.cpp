// The trace machine (machine.hpp): a trace run on concrete words.
//
// The words are Word256 (4 limbs, no node made); the byte strings evb makes
// are buffers kept by the machine from run to run (a pool, by nesting
// depth); the variables of a frame and the values of the expressions already
// evaluated are open-addressing tables emptied at once by a generation
// (the memo of an expression holds until the next change of the state: a
// variable, the memory, the storage, a call's record, a frame).
//
// The control flow of the lines is a signal returned by run_line (no
// exception on the hot path); the ends found deep in an expression (a bug of
// the trace, a limit, an exceptional halt in a byte string) are thrown
// (Stop) and caught by call() / run().
#include "exec/machine.hpp"

#include <gmp.h>

#include <algorithm>
#include <cstring>
#include <utility>

#include "algebra/eval.hpp"
#include "core/context.hpp"
#include "core/dump.hpp"
#include "core/errors.hpp"
#include "core/memo.hpp"
#include "core/node.hpp"
#include "core/smallvec.hpp"

namespace pan::exec {

namespace {

using Bytes = std::vector<u8>;

// what a line does to the control flow
enum class Sig : u8 { None, Halt, Continue, Break, Goto, Leave };

// the end of a run found deep in an expression or a line (rare: thrown)
struct Stop {
    Status status;
    std::string note;
    u32 reason = 0;
};

[[noreturn]] PAN_COLD void stop(Status s, std::string note, u32 reason = 0) { throw Stop{s, std::move(note), reason}; }
[[noreturn]] PAN_COLD void bug(std::string note) { stop(Status::Bug, std::move(note)); }
[[noreturn]] PAN_COLD void exhausted(std::string note) { stop(Status::Exhausted, std::move(note)); }
[[noreturn]] PAN_COLD void unsupported(std::string note) { stop(Status::Unsupported, std::move(note)); }

// a value for a note (diagnostics only)
PAN_COLD std::string show(Value v) {
    std::string s = dump(v);
    if (s.size() > 240) {
        s.resize(240);
        s += "...";
    }
    return s;
}

inline Word256 w_small(i64 n) noexcept {
    const u64 hi = n < 0 ? ~u64(0) : 0;
    return Word256{{u64(n), hi, hi, hi}};
}
inline Word256 w_bool(bool b) noexcept { return Word256::of(b ? 1 : 0); }
inline bool fits_u64(const Word256& w) noexcept { return (w.limb[1] | w.limb[2] | w.limb[3]) == 0; }

// a field of a mask, a storage access, a store: a small signed number
// (python's small(): signed, clamped where the masks clamp it)
constexpr i64 kFieldMax = 4096;

// a bytes expression (as opposed to a word): its evb is its value
inline bool is_bytes_value(Value v) noexcept {
    return v.is_bytes() || (v.is_expr() && info(v.op()).sort == Sort::Bytes);
}

// the bits of a big int's magnitude (0 for anything else)
u64 big_bits(Value v) noexcept {
    if (!v.is_big()) return 0;
    mpz_t tmp;
    return mpz_sizeinbase(big_view(v, tmp), 2);
}

// a table keyed by nonzero words, emptied at once (a new generation)
template <class V>
class GenTable {
public:
    V* find(u64 key) noexcept {
        if (slots_.empty()) return nullptr;
        const usize mask = slots_.size() - 1;
        for (usize i = usize(map_hash(key)) & mask;; i = (i + 1) & mask) {
            Slot& s = slots_[i];
            if (s.gen != gen_) return nullptr;
            if (s.key == key) return &s.val;
        }
    }
    void put(u64 key, const V& val) {
        if ((count_ + 1) * 2 > slots_.size()) grow();
        const usize mask = slots_.size() - 1;
        for (usize i = usize(map_hash(key)) & mask;; i = (i + 1) & mask) {
            Slot& s = slots_[i];
            if (s.gen != gen_) {
                s.key = key;
                s.gen = gen_;
                s.val = val;
                ++count_;
                return;
            }
            if (s.key == key) {
                s.val = val;
                return;
            }
        }
    }
    void clear() noexcept {
        count_ = 0;
        if (PAN_UNLIKELY(++gen_ == 0)) {
            for (Slot& s : slots_) s.gen = 0;
            gen_ = 1;
        }
    }
    usize size() const noexcept { return count_; }

private:
    struct Slot {
        u64 key = 0;
        u32 gen = 0;
        V val{};
    };
    void grow() {
        std::vector<Slot> old = std::move(slots_);
        slots_.assign(old.empty() ? 64 : old.size() * 2, Slot{});
        const usize mask = slots_.size() - 1;
        for (const Slot& s : old) {
            if (s.gen != gen_) continue;
            usize i = usize(map_hash(s.key)) & mask;
            while (slots_[i].gen == gen_) i = (i + 1) & mask;
            slots_[i] = s;
        }
    }

    std::vector<Slot> slots_;
    u32 gen_ = 1;
    usize count_ = 0;
};

// what a numbered call left: CALL_SUCCESS, CREATE_ADDRESS, RETURNDATASIZE,
// RETURNDATA_BYTES of its id read it
struct Record {
    bool written = false;
    bool success = false;
    Word256 created{};
    Bytes output;
};

// a function's run: its variables and call records (an internal function's:
// fresh ones, and its arguments)
struct Frame {
    const FunctionInfo* fn = nullptr;
    bool internal = false;
    std::vector<Word256> args;
    GenTable<Word256> vars;
    std::vector<Record> records;
};

bool is_var_name(Value v) noexcept {
    if (!v.is_name()) return false;
    switch (v.name_kind()) {
        case NameKind::TMP:
        case NameKind::LOOP:
        case NameKind::MSIZE_VAR:
        case NameKind::PRECOMPILE:
        case NameKind::SAFEMATH_PARAM:
            return true;
        default:
            return false;
    }
}

}  // namespace

struct Machine::Impl {
    Program program;
    MachineLimits lim;

    // the program's tables
    std::vector<std::pair<u32, usize>> by_selector;  // (selector, index), sorted, the first of each
    std::optional<usize> fallback;
    std::vector<std::pair<u32, const FunctionInfo*>> internals;  // (entry pc, function), sorted

    // a run's state
    Host* host = nullptr;
    const CallEnv* env = nullptr;
    Bytes mem;
    u64 steps = 0;
    usize work = 0;
    std::vector<std::unique_ptr<Frame>> frames;
    usize depth = 0;
    GenTable<Word256> memo;
    std::vector<std::unique_ptr<Bytes>> pool;
    usize pool_used = 0;
    Value cur_line;
    // the signals' payloads
    Value sig_loop;                   // Continue, Break, Goto: the loop's id
    Value sig_setvars;                // Continue, Goto: their setvars
    std::vector<Word256> sig_values;  // Leave: the values (the callee's)
    Outcome out;                      // Halt: how

    Impl(const Program& p, const MachineLimits& l) : program(p), lim(l) {
        for (usize i = 0; i < program.functions.size(); ++i) {
            const FunctionInfo& f = program.functions[i];
            if (f.kind == FunctionInfo::Kind::Selector)
                by_selector.emplace_back(f.selector, i);
            else if (f.kind == FunctionInfo::Kind::Fallback && !fallback)
                fallback = i;
        }
        // the first function of a selector wins (stable sort keeps the order)
        std::stable_sort(by_selector.begin(), by_selector.end(),
                         [](const auto& a, const auto& b) { return a.first < b.first; });
        by_selector.erase(std::unique(by_selector.begin(), by_selector.end(),
                                      [](const auto& a, const auto& b) { return a.first == b.first; }),
                          by_selector.end());
        for (const FunctionInfo& f : program.internals) internals.emplace_back(f.entry_pc, &f);
        std::stable_sort(internals.begin(), internals.end(),
                         [](const auto& a, const auto& b) { return a.first < b.first; });
    }

    // ---- limits ---------------------------------------------------------------

    void step() {
        if (PAN_UNLIKELY(++steps > lim.steps)) exhausted("more than " + std::to_string(lim.steps) + " steps");
        if (PAN_UNLIKELY((steps & 1023) == 0)) poll();
    }
    void charge(usize n) {
        work += n;
        if (PAN_UNLIKELY(work > lim.work_max))
            exhausted("more than " + std::to_string(lim.work_max) + " bytes of byte strings");
    }
    // the length of a byte string
    u64 length(const Word256& w) {
        if (PAN_UNLIKELY(!fits_u64(w) || w.limb[0] > lim.bytes_max))
            exhausted("a byte string of more than " + std::to_string(lim.bytes_max) + " bytes");
        return w.limb[0];
    }
    // the state changed: the values evaluated so far are forgotten
    void touch() noexcept { memo.clear(); }

    // ---- frames and records -----------------------------------------------------

    Frame& frame() noexcept { return *frames[depth - 1]; }
    void push_frame(const FunctionInfo* fn, bool internal) {
        if (PAN_UNLIKELY(depth >= lim.depth_max))
            exhausted("internal calls nested deeper than " + std::to_string(lim.depth_max));
        if (depth == frames.size()) frames.push_back(std::make_unique<Frame>());
        Frame& f = *frames[depth++];
        f.fn = fn;
        f.internal = internal;
        f.args.clear();
        f.vars.clear();
        f.records.clear();
        touch();
    }
    void pop_frame() noexcept {
        --depth;
        touch();
    }

    u32 call_id(Value v) {
        if (!v.is_small() || v.small_val() < 1 || v.small_val() > (1 << 24)) bug("not a call id: " + show(v));
        return u32(v.small_val());
    }
    Record& record_to_write(u32 id) {
        auto& rs = frame().records;
        if (rs.size() <= id) rs.resize(id + 1);
        return rs[id];
    }
    const Record& record(u32 id) {
        const auto& rs = frame().records;
        if (id >= rs.size() || !rs[id].written) bug("the result of call " + std::to_string(id) + " read before the call");
        return rs[id];
    }

    // ---- byte buffers -----------------------------------------------------------

    Bytes& acquire() {
        if (pool_used == pool.size()) pool.push_back(std::make_unique<Bytes>());
        Bytes& b = *pool[pool_used++];
        b.clear();
        return b;
    }
    struct Lease {
        Impl& m;
        Bytes& b;
        explicit Lease(Impl& im) : m(im), b(im.acquire()) {}
        ~Lease() { --m.pool_used; }
        Lease(const Lease&) = delete;
        Lease& operator=(const Lease&) = delete;
    };

    void append(Bytes& out, const u8* p, usize n) {
        if (!n) return;
        if (PAN_UNLIKELY(out.size() + n > lim.bytes_max))
            exhausted("a byte string of more than " + std::to_string(lim.bytes_max) + " bytes");
        charge(n);
        out.insert(out.end(), p, p + n);
    }
    void append_zeros(Bytes& out, usize n) {
        if (!n) return;
        if (PAN_UNLIKELY(out.size() + n > lim.bytes_max))
            exhausted("a byte string of more than " + std::to_string(lim.bytes_max) + " bytes");
        charge(n);
        out.resize(out.size() + n, 0);
    }
    // src as n bytes: zeroes before it, or its last n bytes
    void append_resized(Bytes& out, std::span<const u8> src, u64 n) {
        if (src.size() >= n) {
            append(out, src.data() + (src.size() - n), n);
        } else {
            append_zeros(out, n - src.size());
            append(out, src.data(), src.size());
        }
    }
    // src[p : p + n], zeroes past its end
    void append_padded(Bytes& out, std::span<const u8> src, const Word256& p, u64 n) {
        if (!n) return;
        const usize start = out.size();
        append_zeros(out, n);
        if (fits_u64(p) && p.limb[0] < src.size()) {
            const u64 avail = std::min<u64>(n, src.size() - p.limb[0]);
            std::memcpy(out.data() + start, src.data() + p.limb[0], avail);
        }
    }

    // ---- memory ---------------------------------------------------------------------

    // the memory made as large as [p, p + n) needs (n > 0), word rounded
    u8* mem_at(const Word256& p, u64 n) {
        if (PAN_UNLIKELY(!fits_u64(p) || p.limb[0] > lim.memory_max || n > lim.memory_max - p.limb[0]))
            exhausted("memory past " + std::to_string(lim.memory_max) + " bytes");
        const u64 end = (p.limb[0] + n + 31) & ~u64(31);
        if (end > mem.size()) mem.resize(end, 0);
        return mem.data() + p.limb[0];
    }
    void mem_read(const Word256& p, u64 n, Bytes& out) {
        if (!n) return;
        const u8* src = mem_at(p, n);
        append(out, src, n);
    }

    // ---- calldata, storage ----------------------------------------------------------

    Word256 cd_word(const Word256& p) {
        const auto cd = env->calldata;
        if (!fits_u64(p) || p.limb[0] >= cd.size()) return Word256{};
        u8 b[32] = {};
        std::memcpy(b, cd.data() + p.limb[0], std::min<u64>(32, cd.size() - p.limb[0]));
        return Word256::from_be(std::span<const u8>(b, 32));
    }

    // solidity's length of a bytes/string at a slot: (s & (256 * iszero(s & 1) - 1)) / 2
    Word256 bytes_length(const Word256& slot) {
        const Word256 s = host->sload(slot);
        if (s.limb[0] & 1) return pan::shr(Word256::of(1), s);
        return Word256::of((s.limb[0] & 0xff) >> 1);
    }

    // solidity's bytes/string at a slot: short (even: its length (s & 0xff) / 2,
    // its bytes the high ones of s), long (odd: length (s - 1) / 2, its words
    // from keccak(slot) on)
    void solidity_bytes(const Word256& slot, Bytes& out) {
        const Word256 s = host->sload(slot);
        u8 w[32];
        if (!(s.limb[0] & 1)) {
            s.to_be(w);
            append(out, w, (s.limb[0] & 0xff) >> 1);
            return;
        }
        const u64 len = length(pan::shr(Word256::of(1), s));
        u8 key[32];
        slot.to_be(key);
        const Word256 base = keccak256(std::span<const u8>(key, 32));
        for (u64 i = 0; i * 32 < len; ++i) {
            const Word256 word = host->sload(pan::add(base, Word256::of(i)));
            word.to_be(w);
            append(out, w, std::min<u64>(32, len - i * 32));
            if ((i & 255) == 255) poll();
        }
    }

    // STORAGE(size, off, slot) (pre-P): the `size` bits at bit off of the
    // slot (or of the decoded length of LENGTH(key)); off < 0: moved left
    Word256 storage_read(Value size_v, Value off_v, Value slot_v) {
        const i64 size = field(size_v), off = field(off_v);
        const Word256 s = slot_v.is(Op::LENGTH, 1) ? bytes_length(ev(slot_v[0])) : host->sload(ev(slot_v));
        if (off < 0) return alg::mask_shl_word(size, 0, -off, s);
        return alg::mask_shl_word(size, off, -off, s);
    }

    // ---- words ------------------------------------------------------------------------

    i64 field(Value v) {
        if (v.is_small()) return std::clamp<i64>(v.small_val(), -kFieldMax, kFieldMax);
        return alg::clamp_field(ev(v));
    }

    Word256 ev(Value v) {
        if (v.is_small()) return w_small(v.small_val());
        if (v.is_node()) {
            switch (NodeKind(v.node()->kind)) {
                case NodeKind::Expr: return ev_expr(v);
                case NodeKind::BigInt: return Word256::from_value(v);
                case NodeKind::Bytes: {
                    if (v.size() > 32) bug("a byte string of more than 32 bytes as a word: " + show(v));
                    return Word256::from_be(v.bytes());
                }
                case NodeKind::List: break;
            }
            bug("a list as a word: " + show(v));
        }
        if (v.is_leaf()) return ev_leaf(v);
        if (v.is_name()) return ev_name(v);
        if (v.is_true()) return Word256::of(1);
        if (v.is_false()) return Word256{};
        bug("not a word: " + show(v));
    }

    Word256 ev_expr(Value v) {
        // MSIZE moves with every access of the memory: never remembered
        const bool remember = !v.has_flags(F_MSIZE);
        if (remember)
            if (const Word256* w = memo.find(v.raw())) return *w;
        check_stack();
        const Word256 r = compute(v);
        if (remember) memo.put(v.raw(), r);
        return r;
    }

    Word256 compute(Value v) {
        const Op op = v.op();
        const std::span<const Value> a = v.args();
        switch (op) {
            case Op::LAND: {
                if (a.size() != 2) break;
                const Word256 x = ev(a[0]);
                return x.is_zero() ? x : ev(a[1]);
            }
            case Op::LOR: {
                if (a.size() != 2) break;
                const Word256 x = ev(a[0]);
                return x.is_zero() ? ev(a[1]) : x;
            }
            case Op::FAND:
                for (Value x : a)
                    if (ev(x).is_zero()) return Word256{};
                return Word256::of(1);
            case Op::FOR:
                for (Value x : a)
                    if (!ev(x).is_zero()) return Word256::of(1);
                return Word256{};
            case Op::MASK_SHL:
                if (a.size() == 4 && is_bytes_value(a[3])) return mask_bytes(field(a[0]), field(a[1]), field(a[2]), a[3]);
                break;
            case Op::MASK: {  // print form: the bits [off, off + size) of x, moved to 0
                const i64 off = field(a[1]);
                if (is_bytes_value(a[2])) return mask_bytes(field(a[0]), off, -off, a[2]);
                return alg::mask_shl_word(field(a[0]), off, -off, ev(a[2]));
            }
            case Op::SHA3: {
                Lease l(*this);
                for (Value x : a) evb(x, l.b);
                return keccak256(l.b);
            }
            case Op::BALANCE: return host->balance(ev(a[0]));
            case Op::EXTCODESIZE: return host->code_size(ev(a[0]));
            case Op::EXTCODEHASH: return host->code_hash(ev(a[0]));
            case Op::BLOCKHASH: return host->block_hash(ev(a[0]));
            case Op::BLOBHASH: return host->blob_hash(ev(a[0]));
            case Op::TLOAD: return host->tload(ev(a[0]));
            case Op::CALLDATALOAD: return cd_word(ev(a[0]));
            case Op::STORAGE: return storage_read(a[0], a[1], a[2]);
            case Op::LENGTH: return bytes_length(ev(a[0]));
            case Op::LOC: return ev(a[0]);
            case Op::SIZED:
            case Op::DATA:
            case Op::ARR:
            case Op::MEM:
            case Op::CALLDATA_BYTES:
            case Op::CODE_BYTES:
            case Op::EXTCODE_BYTES:
            case Op::RETURNDATA_BYTES:
            case Op::SBYTES:
            case Op::SALL:
                return bytes_word(v);
            case Op::ST:
            case Op::SV:
            case Op::SI:
            case Op::SL:
            case Op::SBL:
            case Op::SF:
            case Op::SR:
                unsupported("the storage forms need lot 9's layout: " + show(v));
            case Op::SAFEMATH:
                unsupported("SAFEMATH needs lot 8's table: " + show(v));
            default:
                break;
        }
        if (alg::is_pure(op)) {
            SmallVec<Word256, 4> w;
            for (Value x : a) w.push_back(ev(x));
            if (const auto r = alg::eval_op(op, w.span())) return *r;
        }
        bug("not a word: " + show(v));
    }

    // MASK_SHL(size, off, shl, x) of a byte string x: its big-endian number,
    // wider than a word when it has more than 32 bytes - its bits past 256
    // exist (lot 2's may_be_wide, python's unbounded ints)
    Word256 mask_bytes(i64 size, i64 off, i64 shl, Value x) {
        Lease l(*this);
        evb(x, l.b);
        if (l.b.size() <= 32) return alg::mask_shl_word(size, off, shl, Word256::from_be(l.b));
        return mask_shl_wide(size, off, shl, l.b);
    }

    // the bits [off, off + size) of the big-endian number of `be` (any
    // length), moved left by shl, mod 2^256
    static Word256 mask_shl_wide(i64 size, i64 off, i64 shl, std::span<const u8> be) noexcept {
        if (off < 0) {
            size += off;
            off = 0;
        }
        if (size <= 0) return Word256{};
        const i64 nbits = i64(be.size()) * 8;
        const i64 lo = std::max(off, -shl);  // the bits that land in [0, 256)
        const i64 hi = std::min({off + size, nbits, 256 - shl});
        if (lo >= hi) return Word256{};
        // the bits [lo, lo + 320) of the number, then [lo, hi) at bit 0
        const u64 k = u64(lo) / 8;
        const unsigned r = unsigned(lo % 8);
        u64 limbs[5] = {};
        for (u64 j = 0; j < 40 && k + j < be.size(); ++j)
            limbs[j / 8] |= u64(be[be.size() - 1 - (k + j)]) << (8 * (j % 8));
        Word256 w;
        for (int i = 0; i < 4; ++i) w.limb[i] = r ? (limbs[i] >> r) | (limbs[i + 1] << (64 - r)) : limbs[i];
        w = pan::band(w, alg::mask_word(hi - lo, 0));
        return pan::shl(Word256::of(u64(lo + shl)), w);
    }

    // a bytes expression as a word: its big-endian number (32 bytes at most)
    Word256 bytes_word(Value v) {
        if (v.is(Op::SIZED, 2) && !is_bytes_value(v[1]) && big_bits(v[1]) <= 256) {
            const u64 n = length(ev(v[0]));
            const Word256 w = ev(v[1]);
            return n >= 32 ? w : pan::band(w, alg::mask_word(i64(8 * n), 0));
        }
        Lease l(*this);
        evb(v, l.b);
        if (l.b.size() > 32)
            bug("a byte string of " + std::to_string(l.b.size()) + " bytes as a word: " + show(v));
        return Word256::from_be(l.b);
    }

    Word256 ev_leaf(Value v) {
        const CallEnv& e = *env;
        switch (v.op()) {
            case Op::ADDRESS: return e.address;
            case Op::ORIGIN: return e.origin;
            case Op::CALLER: return e.caller;
            case Op::CALLVALUE: return e.callvalue;
            case Op::CALLDATASIZE: return Word256::of(e.calldata.size());
            case Op::CODESIZE: return Word256::of(e.code.size());
            case Op::GASPRICE: return e.gasprice;
            case Op::COINBASE: return e.coinbase;
            case Op::TIMESTAMP: return e.timestamp;
            case Op::NUMBER: return e.number;
            case Op::DIFFICULTY: return e.prevrandao;
            case Op::GASLIMIT: return e.gaslimit;
            case Op::CHAINID: return e.chainid;
            case Op::BASEFEE: return e.basefee;
            case Op::BLOBBASEFEE: return e.blobbasefee;
            case Op::SELFBALANCE: return host->balance(e.address);
            case Op::MSIZE: return Word256::of(mem.size());
            case Op::GAS: return e.gas;
            case Op::RETURNDATASIZE:
                if (v.leaf_n() == 0) return Word256{};
                return Word256::of(record(v.leaf_n()).output.size());
            case Op::CALL_SUCCESS: return w_bool(record(v.leaf_n()).success);
            case Op::CREATE_ADDRESS: return record(v.leaf_n()).created;
            default: break;
        }
        bug("a leaf that is not a word: " + show(v));
    }

    Word256 ev_name(Value v) {
        if (v.is_name(NameKind::PARAM)) return param(v.name_id());
        if (is_var_name(v)) {
            if (const Word256* w = frame().vars.find(v.raw())) return *w;
            bug("the variable " + show(v) + " read before it is set");
        }
        bug("a name that is not a word: " + show(v));
    }

    Word256 param(u32 k) {
        Frame& f = frame();
        if (f.internal) {
            if (k >= f.args.size())
                bug("param " + std::to_string(k) + " of an internal function of " + std::to_string(f.args.size()) +
                    " arguments");
            return f.args[k];
        }
        if (!f.fn || k >= f.fn->params.size()) bug("param " + std::to_string(k) + " has no ParamInfo");
        return cd_word(Word256::of(f.fn->params[k].calldata_offset));
    }

    void set_var(Value name, const Word256& w) {
        if (!is_var_name(name)) bug("not a variable: " + show(name));
        frame().vars.put(name.raw(), w);
    }

    // ---- bytes ------------------------------------------------------------------------

    // the bytes a word expression without SIZED is written with (ir.md 4.2)
    u64 implicit_width(Value e) {
        switch (e.op()) {
            case Op::MASK_SHL: return width_bits(field(e[0]) + field(e[1]) + field(e[2]), e);
            case Op::STORAGE:
            case Op::ST: return width_bits(field(e[0]), e);
            default: return 32;
        }
    }
    u64 width_bits(i64 bits, Value e) {
        if (bits < 0 || bits > 256 || bits % 8) unsupported("a byte string element of " + std::to_string(bits) + " bits: " + show(e));
        return u64(bits / 8);
    }

    // a big int (more than 256 bits): its bytes, big-endian, as few as hold it
    void big_bytes(Value v, Bytes& out) {
        mpz_t tmp;
        mpz_srcptr z = big_view(v, tmp);
        const usize n = (mpz_sizeinbase(z, 2) + 7) / 8;
        if (n > lim.bytes_max) exhausted("a constant of " + std::to_string(n) + " bytes");
        const usize start = out.size();
        append_zeros(out, n);
        usize written = 0;
        mpz_export(out.data() + start, &written, 1, 1, 1, 0, z);
        if (written < n) {  // (mpz_export writes no leading zero bytes)
            std::memmove(out.data() + start + (n - written), out.data() + start, written);
            std::memset(out.data() + start, 0, n - written);
        }
    }

    void note_unsized(Value e) noexcept {
        if (out.unsized++ == 0) {
            out.unsized_element = e;
            out.unsized_line = cur_line;
        }
    }

    // the bytes of e as an element of a byte string (python runtrace.evb)
    void evb(Value e, Bytes& out) {
        check_stack();
        if (e.is_none()) return;
        if (e.is_bytes()) {
            append(out, e.bytes().data(), e.size());
            return;
        }
        if (e.is_big() && big_bits(e) > 256) {
            note_unsized(e);
            big_bytes(e, out);
            return;
        }
        if (e.is_expr()) {
            const std::span<const Value> a = e.args();
            switch (e.op()) {
                case Op::SIZED: {
                    const u64 n = length(ev(a[0]));
                    const Value x = a[1];
                    if (is_bytes_value(x) || big_bits(x) > 256) {
                        Lease l(*this);
                        evb(x, l.b);
                        append_resized(out, l.b, n);
                    } else {
                        u8 w[32];
                        ev(x).to_be(w);
                        append_resized(out, std::span<const u8>(w, 32), n);
                    }
                    return;
                }
                case Op::DATA:
                    data(a, out);
                    return;
                case Op::ARR:
                    data(std::span<const Value>(&e, 1), out);
                    return;
                case Op::MEM: {
                    const Value r = a[0];
                    if (!r.is(Op::RANGE, 2)) bug("MEM of something else than a RANGE: " + show(e));
                    const Word256 p = ev(r[0]);
                    mem_read(p, length(ev(r[1])), out);
                    return;
                }
                case Op::CALLDATA_BYTES: {
                    const Word256 p = ev(a[0]);
                    append_padded(out, env->calldata, p, length(ev(a[1])));
                    return;
                }
                case Op::CODE_BYTES: {
                    const Word256 p = ev(a[0]);
                    append_padded(out, env->code, p, length(ev(a[1])));
                    return;
                }
                case Op::EXTCODE_BYTES: {
                    const Value r = a[1];
                    if (!r.is(Op::RANGE, 2)) bug("EXTCODE_BYTES of something else than a RANGE: " + show(e));
                    const Word256 account = ev(a[0]);
                    const Word256 p = ev(r[0]);
                    const u64 n = length(ev(r[1]));
                    const Bytes code = host->code_of(account);
                    append_padded(out, code, p, n);
                    return;
                }
                case Op::RETURNDATA_BYTES: {  // zero padded: the VM makes the EVM's halt explicit
                    const u32 id = call_id(a[0]);
                    const Word256 p = ev(a[1]);
                    const u64 n = length(ev(a[2]));
                    append_padded(out, record(id).output, p, n);
                    return;
                }
                case Op::SBYTES:
                    solidity_bytes(ev(a[0]), out);
                    return;
                case Op::SALL:
                    unsupported("the storage forms need lot 9's layout: " + show(e));
                case Op::RANGE:
                    bug("a RANGE as bytes: " + show(e));
                default:
                    break;
            }
        } else if (e.is_list() || e.nil()) {
            bug("not bytes: " + show(e));
        }
        // a word without its width: a stage's bug (counted), run as wide as
        // it is written (ir.md 4.2, the fallback)
        note_unsized(e);
        const u64 n = implicit_width(e);
        u8 w[32];
        ev(e).to_be(w);
        append(out, w + (32 - n), n);
    }

    // DATA(e1...en): the concatenation; an ARR element ABI-encoded - its offset
    // (from the start of this data) in its place, its length and content
    // (padded to 32 bytes) after all the heads
    void data(std::span<const Value> els, Bytes& out) {
        bool arr = false;
        for (Value x : els) arr = arr || x.is(Op::ARR);
        if (!arr) {
            for (Value x : els) evb(x, out);
            return;
        }
        const usize start = out.size();
        Lease tails(*this);
        struct Head {
            usize at, tail;  // where the offset goes, where its tail starts
        };
        SmallVec<Head, 4> heads;
        for (Value x : els) {
            if (!x.is(Op::ARR)) {
                evb(x, out);
                continue;
            }
            if (x.size() < 1) bug("ARR without a length: " + show(x));
            heads.push_back({out.size() - start, tails.b.size()});
            append_zeros(out, 32);
            u8 w[32];
            ev(x[0]).to_be(w);
            append(tails.b, w, 32);
            const usize content = tails.b.size();
            for (u32 i = 1; i < x.size(); ++i) evb(x[i], tails.b);
            append_zeros(tails.b, (32 - (tails.b.size() - content) % 32) % 32);
        }
        const usize head_size = out.size() - start;
        for (const Head& h : heads) Word256::of(head_size + h.tail).to_be(out.data() + start + h.at);
        append(out, tails.b.data(), tails.b.size());
    }

    // ---- lines ------------------------------------------------------------------------

    Sig halt(Status s) {
        out.status = s;
        return Sig::Halt;
    }

    // setvars all at once: every value first, then the variables
    void assign(Value setvars) {
        if (setvars.nil()) return;
        if (!setvars.is_list()) bug("setvars that are not a list: " + show(setvars));
        SmallVec<Word256, 8> vals;
        for (Value sv : setvars) {
            if (!sv.is(Op::SETVAR, 2)) bug("not a SETVAR among setvars: " + show(sv));
            vals.push_back(ev(sv[1]));
        }
        for (u32 i = 0; i < setvars.size(); ++i) set_var(setvars[i][0], vals[i]);
        touch();
    }

    Sig run_trace(Value trace) {
        if (trace.nil()) return Sig::None;
        if (!trace.is_list()) bug("not a trace: " + show(trace));
        check_stack();
        const Value* lines = trace.data();
        const u32 n = trace.size();
        struct Label {
            u64 id;
            u32 at;
        };
        SmallVec<Label, 2> labels;  // the LABELs of this trace run
        for (u32 i = 0; i < n; ++i) {
            const Value line = lines[i];
            if (line.is(Op::LABEL, 2)) {
                step();
                cur_line = line;
                assign(line[1]);
                bool known = false;
                for (Label& l : labels)
                    if (l.id == line[0].raw()) {
                        l.at = i;
                        known = true;
                    }
                if (!known) labels.push_back({line[0].raw(), i});
                continue;
            }
            const Sig s = run_line(line);
            if (s == Sig::None) continue;
            if (s == Sig::Goto) {
                bool found = false;
                for (const Label& l : labels)
                    if (l.id == sig_loop.raw()) {
                        assign(sig_setvars);
                        i = l.at;  // on after the LABEL
                        found = true;
                        break;
                    }
                if (found) continue;
            }
            return s;
        }
        return Sig::None;
    }

    Sig run_line(Value line) {
        step();
        cur_line = line;
        const std::span<const Value> a = line.children();
        switch (line.op()) {
            case Op::STOP:
                out.data.clear();
                return halt(Status::Stop);
            case Op::RETURN:
                out.data.clear();
                evb(a[0], out.data);
                return halt(Status::Return);
            case Op::REVERT:
                out.data.clear();
                evb(a[0], out.data);
                return halt(Status::Revert);
            case Op::INVALID:
                out.data.clear();
                out.reason = a.size() && a[0].is_small() ? u32(a[0].small_val()) : 0;
                return halt(Status::Invalid);
            case Op::SELFDESTRUCT:
                host->selfdestruct(ev(a[0]));
                out.data.clear();
                return halt(Status::Stop);
            case Op::UNDEFINED:
                stop(Status::Undefined, "the decompiler gave up there: " + show(line));
            case Op::ASM:
                return Sig::None;
            case Op::SETVAR:
                set_var(a[0], ev(a[1]));
                touch();
                return Sig::None;
            case Op::SETMEM:
                setmem(a[0], a[1]);
                touch();
                return Sig::None;
            case Op::STORE:
                store(a[0], a[1], a[2], a[3]);
                touch();
                return Sig::None;
            case Op::SET:
                unsupported("the storage forms need lot 9's layout: " + show(line));
            case Op::TSTORE: {
                const Word256 k = ev(a[0]);
                const Word256 v = ev(a[1]);
                host->tstore(k, v);
                touch();
                return Sig::None;
            }
            case Op::LOG0:
            case Op::LOG1:
            case Op::LOG2:
            case Op::LOG3:
            case Op::LOG4:
                log(line);
                return Sig::None;
            case Op::CALL:
            case Op::CALLCODE:
            case Op::DELEGATECALL:
            case Op::STATICCALL:
                call_line(line);
                return Sig::None;
            case Op::CREATE:
            case Op::CREATE2:
                create_line(line);
                return Sig::None;
            case Op::PRECOMPILED:
                precompiled_line(line);
                return Sig::None;
            case Op::IF:
            case Op::MERGED_IF:
                return run_trace(ev(a[0]).is_zero() ? a[2] : a[1]);
            case Op::WHILE:
                return while_line(a);
            case Op::CONTINUE:
            case Op::GOTO:
                sig_loop = a[0];
                sig_setvars = a[1];
                return line.op() == Op::GOTO ? Sig::Goto : Sig::Continue;
            case Op::BREAK:
                sig_loop = a[0];
                return Sig::Break;
            case Op::LABEL:  // (a LABEL out of a trace's lines: run_trace takes them)
                assign(a[1]);
                return Sig::None;
            case Op::INTERNAL:
                return internal_line(a);
            case Op::LEAVE:
                return leave_line(a[0]);
            case Op::REQUIRE:  // (cond, revert data: absent or None for none)
                if (!ev(a[0]).is_zero()) return Sig::None;
                out.data.clear();
                if (a.size() > 1) evb(a[1], out.data);
                return halt(Status::Revert);
            case Op::ASSERT:
                if (!ev(a[0]).is_zero()) return Sig::None;
                out.data.clear();
                out.reason = u32(InvalidReason::ASSERT_FAIL);
                return halt(Status::Invalid);
            case Op::LOOP_PATH:
                unsupported("LOOP_PATH (a folder's form): " + show(line));
            default:
                break;
        }
        bug("not a line: " + show(line));
    }

    // SETMEM(RANGE(p, n), v): a word's low n bytes; bytes of n bytes
    void setmem(Value range, Value v) {
        if (!range.is(Op::RANGE, 2)) bug("SETMEM of something else than a RANGE: " + show(cur_line));
        const Word256 p = ev(range[0]);
        const u64 n = length(ev(range[1]));
        if (is_bytes_value(v) || big_bits(v) > 256) {
            Lease l(*this);
            evb(v, l.b);
            if (big_bits(v) > 256 && l.b.size() != n) {  // a number: its low n bytes
                Lease m(*this);
                append_resized(m.b, l.b, n);
                std::swap(l.b, m.b);
            }
            if (l.b.size() != n)
                bug("SETMEM of " + std::to_string(n) + " bytes with " + std::to_string(l.b.size()) + " bytes: " +
                    show(cur_line));
            if (n) std::memcpy(mem_at(p, n), l.b.data(), n);
            return;
        }
        const Word256 w = ev(v);
        if (!n) return;
        charge(n);
        u8 buf[32];
        w.to_be(buf);
        u8* dst = mem_at(p, n);
        if (n <= 32) {
            std::memcpy(dst, buf + (32 - n), n);
        } else {
            std::memset(dst, 0, n - 32);
            std::memcpy(dst + (n - 32), buf, 32);
        }
    }

    // STORE(size, off, slot, v): the bits [off, off + size) of the slot set to
    // the low `size` bits of v, the others kept
    void store(Value size_v, Value off_v, Value slot_v, Value v) {
        const i64 size = field(size_v), off = field(off_v);
        if (slot_v.is(Op::LENGTH)) bug("a STORE to a bytes length: " + show(cur_line));
        const Word256 slot = ev(slot_v);
        const Word256 val = ev(v);
        if (size >= 256 && off == 0) {
            host->sstore(slot, val);
            return;
        }
        const Word256 m = alg::mask_word(size, off);
        const Word256 placed = off >= 0 ? pan::shl(Word256::of(u64(off)), val) : pan::shr(Word256::of(u64(-off)), val);
        const Word256 old = host->sload(slot);
        host->sstore(slot, pan::bor(pan::band(old, pan::bnot(m)), pan::band(placed, m)));
    }

    void log(Value line) {
        const u32 k = u32(line.op()) - u32(Op::LOG0);
        if (line.size() != k + 1) bug("a LOG with another count of topics: " + show(line));
        SmallVec<Word256, 4> topics;
        for (u32 i = 1; i <= k; ++i) topics.push_back(ev(line[i]));
        Lease l(*this);
        evb(line[0], l.b);
        host->log(topics.span(), l.b);
    }

    void call_line(Value line) {
        const Op op = line.op();
        const u32 id = call_id(line[0]);
        const Word256 target = ev(line[2]);
        Word256 value{};
        Value sel, params;
        CallKind kind;
        if (op == Op::CALL || op == Op::CALLCODE) {
            value = ev(line[3]);
            sel = line[4];
            params = line[5];
            kind = op == Op::CALL ? CallKind::Call : CallKind::CallCode;
        } else {
            sel = line[3];
            params = line[4];
            kind = op == Op::DELEGATECALL ? CallKind::DelegateCall : CallKind::StaticCall;
        }
        Lease l(*this);
        evb(sel, l.b);
        evb(params, l.b);
        CallResult r = host->call(kind, target, value, l.b);
        Record& rec = record_to_write(id);
        rec.written = true;
        rec.success = r.success;
        rec.created = Word256{};
        rec.output = std::move(r.output);
        touch();
    }

    void create_line(Value line) {
        const u32 id = call_id(line[0]);
        const Word256 value = ev(line[1]);
        Lease l(*this);
        evb(line[2], l.b);
        const Word256 salt = line.op() == Op::CREATE2 ? ev(line[3]) : Word256{};
        CreateResult r =
            host->create(line.op() == Op::CREATE2 ? CreateKind::Create2 : CreateKind::Create, value, l.b, salt);
        Record& rec = record_to_write(id);
        rec.written = true;
        rec.success = r.success;
        rec.created = r.success ? r.address : Word256{};
        rec.output = std::move(r.output);
        touch();
    }

    // PRECOMPILED(id, name, address, input): a staticcall of the precompile;
    // its name := the output's first word (zeroes past its end)
    void precompiled_line(Value line) {
        const u32 id = call_id(line[0]);
        const Value name = line[1];
        const Word256 address = ev(line[2]);
        Lease l(*this);
        evb(line[3], l.b);
        CallResult r = host->call(CallKind::StaticCall, address, Word256{}, l.b);
        u8 first[32] = {};
        std::memcpy(first, r.output.data(), std::min<usize>(32, r.output.size()));
        Record& rec = record_to_write(id);
        rec.written = true;
        rec.success = r.success;
        rec.created = Word256{};
        rec.output = std::move(r.output);
        set_var(name, Word256::from_be(std::span<const u8>(first, 32)));
        touch();
    }

    Sig while_line(std::span<const Value> a) {
        const Value cond = a[0], body = a[1], id = a[2];
        assign(a[3]);
        for (;;) {
            step();
            if (ev(cond).is_zero()) return Sig::None;
            const Sig s = run_trace(body);
            switch (s) {
                case Sig::None:  // the body ended without a continue: out of the loop
                    return Sig::None;
                case Sig::Continue:
                    if (sig_loop != id) return s;
                    assign(sig_setvars);
                    continue;
                case Sig::Break:
                    if (sig_loop != id) return s;
                    return Sig::None;
                default:
                    return s;
            }
        }
    }

    const FunctionInfo* find_internal(u32 entry) const noexcept {
        auto it = std::lower_bound(internals.begin(), internals.end(), entry,
                                   [](const auto& p, u32 e) { return p.first < e; });
        if (it == internals.end() || it->first != entry) return nullptr;
        return it->second;
    }

    // INTERNAL(entry, [args], [names])
    Sig internal_line(std::span<const Value> a) {
        if (!a[0].is_small() || !a[1].is_list() || !a[2].is_list()) bug("a malformed INTERNAL: " + show(cur_line));
        const u32 entry = u32(a[0].small_val());
        const FunctionInfo* fn = find_internal(entry);
        if (!fn) unsupported("the internal function at pc " + std::to_string(entry) + " is not given");
        if (fn->problem || fn->trace.nil())
            unsupported("the internal function at pc " + std::to_string(entry) + " failed to decompile");
        SmallVec<Word256, 8> args;
        for (Value x : a[1]) args.push_back(ev(x));
        push_frame(fn, true);
        frame().args.assign(args.begin(), args.end());
        const Sig s = run_trace(fn->trace);
        pop_frame();
        switch (s) {
            case Sig::Leave: {
                const Value names = a[2];
                if (names.size() != sig_values.size())
                    bug("a LEAVE of " + std::to_string(sig_values.size()) + " values for " +
                        std::to_string(names.size()) + " results: " + show(cur_line));
                for (u32 i = 0; i < names.size(); ++i) set_var(names[i], sig_values[i]);
                touch();
                return Sig::None;
            }
            case Sig::Halt:
                return s;
            case Sig::None:  // the end of its trace: the end of the call
                out.data.clear();
                return halt(Status::Stop);
            default:
                bug("a loop's signal out of the internal function at pc " + std::to_string(entry));
        }
    }

    Sig leave_line(Value values) {
        if (depth == 0 || !frame().internal) bug("a LEAVE out of an internal function: " + show(cur_line));
        if (!values.is_list()) bug("a malformed LEAVE: " + show(cur_line));
        sig_values.clear();
        for (Value x : values) sig_values.push_back(ev(x));
        return Sig::Leave;
    }

    // ---- runs ---------------------------------------------------------------------------

    void begin(Host& h) {
        host = &h;
        env = &h.env();
        mem.clear();
        steps = 0;
        work = 0;
        depth = 0;
        pool_used = 0;
        touch();
        out = Outcome{};
        cur_line = Value{};
        sig_loop = sig_setvars = Value{};
        sig_values.clear();
    }

    void body(const FunctionInfo& fn, Value trace, bool with_entry) {
        if (fn.problem) unsupported("the function failed to decompile");
        if (trace.nil()) unsupported("the function has no trace");
        push_frame(&fn, fn.kind == FunctionInfo::Kind::Internal);
        if (with_entry) {
            const Sig s = run_trace(fn.entry.entry_lines);
            if (s == Sig::Halt) return;
            if (s != Sig::None) bug("a loop's or a function's signal out of the entry lines");
            if (fn.entry.nonpayable && !env->callvalue.is_zero()) {
                // the check lot 8 took out of the body: its halting line
                const Value fails = fn.entry.value_fails;
                if (fails.nil()) {
                    out.data.clear();
                    out.status = Status::Revert;
                    return;
                }
                if (run_line(fails) != Sig::Halt) bug("value_fails is not a halting line: " + show(fails));
                return;
            }
        }
        switch (run_trace(trace)) {
            case Sig::None:
                out.data.clear();
                out.status = Status::Stop;
                return;
            case Sig::Halt:
                return;
            case Sig::Leave:
                bug("a LEAVE out of an internal function's call");
            default:
                bug("a CONTINUE, BREAK or GOTO out of its loop: " + show(sig_loop));
        }
    }

    template <class F>
    Outcome guarded(F&& f) {
        try {
            f();
        } catch (const Stop& s) {
            out.status = s.status;
            out.note = s.note;
            out.reason = s.reason;
            out.data.clear();
        } catch (const Unsupported& e) {  // (a host's, an algebra's)
            out.status = Status::Unsupported;
            out.note = e.what();
            out.data.clear();
        } catch (const LimitExceeded& e) {  // MemoryLimit, DepthLimit, SizeLimit
            out.status = Status::Exhausted;
            out.note = e.what();
            out.data.clear();
        } catch (const Error& e) {  // InternalError...
            out.status = Status::Bug;
            out.note = e.what();
            out.data.clear();
        } catch (const std::bad_alloc&) {
            out.status = Status::Exhausted;
            out.note = "out of memory";
            out.data.clear();
        }
        out.steps = steps;
        out.line = cur_line;
        depth = 0;
        pool_used = 0;
        return std::move(out);
    }

    Outcome call(Host& h, std::optional<u32> hint) {
        (void)hint;  // the selector of the calldata decides; the hint names the same
        begin(h);
        return guarded([&] {
            std::optional<usize> index;
            const auto cd = env->calldata;
            if (cd.size() >= 4) {
                const u32 sel = (u32(cd[0]) << 24) | (u32(cd[1]) << 16) | (u32(cd[2]) << 8) | u32(cd[3]);
                auto it = std::lower_bound(by_selector.begin(), by_selector.end(), sel,
                                           [](const auto& p, u32 s) { return p.first < s; });
                if (it != by_selector.end() && it->first == sel) index = it->second;
            }
            if (!index) index = fallback;
            if (!index) unsupported("no function for this call (no fallback)");
            out.function = *index;
            const FunctionInfo& fn = program.functions[*index];
            body(fn, fn.trace, true);
        });
    }

    Outcome run(Host& h, const FunctionInfo& fn, Value trace, bool with_entry) {
        begin(h);
        return guarded([&] { body(fn, trace, with_entry); });
    }
};

// ---- Machine ----------------------------------------------------------------------

Machine::Machine(const Program& program, MachineLimits limits) : impl_(std::make_unique<Impl>(program, limits)) {}
Machine::~Machine() = default;

Outcome Machine::call(Host& host, std::optional<u32> selector_hint) { return impl_->call(host, selector_hint); }

Outcome Machine::run(Host& host, const FunctionInfo& fn, Value trace, bool with_entry) {
    return impl_->run(host, fn, trace, with_entry);
}

const Program& Machine::program() const noexcept { return impl_->program; }
const MachineLimits& Machine::limits() const noexcept { return impl_->lim; }
void Machine::set_limits(const MachineLimits& l) noexcept { impl_->lim = l; }

const char* status_name(Status s) noexcept {
    switch (s) {
        case Status::Stop: return "stop";
        case Status::Return: return "return";
        case Status::Revert: return "revert";
        case Status::Invalid: return "invalid";
        case Status::Exhausted: return "exhausted";
        case Status::Undefined: return "undefined";
        case Status::Unsupported: return "unsupported";
        case Status::Bug: return "bug";
    }
    return "?";
}

// ---- SimpleHost ----------------------------------------------------------------------

const CallEnv& SimpleHost::env() {
    call_env.calldata = calldata;
    call_env.code = code;
    return call_env;
}

Word256 SimpleHost::sload(const Word256& slot) {
    if (auto it = storage.find(slot); it != storage.end()) return it->second;
    return initial(slot);
}

void SimpleHost::sstore(const Word256& slot, const Word256& value) {
    storage[slot] = value;
    effects.emplace_back(Sstore{slot, value});
}

Word256 SimpleHost::tload(const Word256& key) {
    if (auto it = transient.find(key); it != transient.end()) return it->second;
    return Word256{};
}

void SimpleHost::tstore(const Word256& key, const Word256& value) {
    transient[key] = value;
    effects.emplace_back(Tstore{key, value});
}

Word256 SimpleHost::balance(const Word256& account) {
    if (auto it = balances.find(account); it != balances.end()) return it->second;
    return Word256{};
}

Word256 SimpleHost::code_size(const Word256& account) {
    return account == call_env.address ? Word256::of(code.size()) : Word256{};
}

Word256 SimpleHost::code_hash(const Word256& account) {
    return account == call_env.address ? keccak256(code) : Word256{};
}

std::vector<u8> SimpleHost::code_of(const Word256& account) {
    return account == call_env.address ? code : std::vector<u8>{};
}

Word256 SimpleHost::block_hash(const Word256&) { return Word256{}; }
Word256 SimpleHost::blob_hash(const Word256&) { return Word256{}; }

void SimpleHost::log(std::span<const Word256> topics, std::span<const u8> data) {
    effects.emplace_back(Log{{topics.begin(), topics.end()}, {data.begin(), data.end()}});
}

CallResult SimpleHost::call(CallKind kind, const Word256& target, const Word256& value, std::span<const u8> input) {
    const bool with_value = kind == CallKind::Call || kind == CallKind::CallCode;
    effects.emplace_back(Call{kind, target, with_value ? value : Word256{}, {input.begin(), input.end()}});
    return call_answer;
}

CreateResult SimpleHost::create(CreateKind kind, const Word256& value, std::span<const u8> init_code,
                                const Word256& salt) {
    effects.emplace_back(Create{kind, value, salt, {init_code.begin(), init_code.end()}});
    return CreateResult{};
}

void SimpleHost::selfdestruct(const Word256& beneficiary) { effects.emplace_back(SelfDestruct{beneficiary}); }

}  // namespace pan::exec
