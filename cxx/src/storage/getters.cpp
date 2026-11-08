// The getters (python storage.py: getter_access, bytes_tail, splits): what
// a getter returns - its storage access names the variable - and the
// getters of a bytes/string, whose copy of the bytes to the memory is
// replaced by `return name[all]` when the trace machine runs both the same
// on a complete set of boundary worlds (checked, not proven).
#include "storage/getters.hpp"

#include <algorithm>
#include <functional>
#include <set>

#include "algebra/masks.hpp"
#include "core/context.hpp"
#include "core/errors.hpp"
#include "core/platform.hpp"
#include "exec/machine.hpp"

namespace pan::storage::detail {

// ---- what a getter returns -----------------------------------------------------------------

std::optional<GetterAccess> getter_access(const traits::Getter& g, Value narrowed) {
    if (g.kind == traits::Getter::Kind::Kitties) return GetterAccess{true, Word256::of(g.slot), {}};
    if (g.kind != traits::Getter::Kind::Read) return std::nullopt;
    Value ret = narrowed;
    if (ret.is(Op::BOOL, 1)) ret = ret[0];
    if (ret.is(Op::SIGNEXTEND, 2)) ret = ret[1];
    const alg::MaskShl m = alg::mask_view(ret);
    if (m.concrete() && m.ioff() == 0 && m.x.is(Op::STORAGE, 3) && m.x[0].is_small()) {
        // a cast of it, a left-aligned one (bytesN)
        const i64 s_size = m.x[0].small_val();
        if ((m.ishl() == 0 && m.isize() >= s_size) || (m.isize() == s_size && m.ishl() == 256 - m.isize())) ret = m.x;
    }
    if (ret.is(Op::STORAGE, 3)) return GetterAccess{false, {}, Access{ret[0], ret[1], ret[2]}};
    return std::nullopt;
}

// ---- the getters of a bytes ------------------------------------------------------------------

namespace {

constexpr usize MAX_CANDIDATES = 201;

// The largest lengths tried, L = 32 * M + r: M = 2^13 words, and the most the
// check machine's memory (lot 9's 1 MiB) holds with the bytes copied twice
// (solc's getters copy them to memory, then to the ABI encoding) and 4 KiB to
// spare: 16,320 (2^16 words would need 4 MiB)
constexpr u64 M_LARGE = u64(1) << 13, M_MAX = (exec::MachineLimits::storage_check().memory_max - 4096) / 64;

void put_word(std::vector<u8>& out, const Word256& w) {
    u8 b[32];
    w.to_be(b);
    out.insert(out.end(), b, b + 32);
}

// every int of v (any depth): small ones in (0, 4096) for the lengths, all
// of a condition's for its params
void ints_of(Value v, Memo<Value, u8>& seen, std::vector<Word256>& out, bool all) {
    check_stack();
    if (v.is_small()) {
        if (all || (v.small_val() > 0 && v.small_val() < 4096)) out.push_back(Word256::from_value(v));
        return;
    }
    if (v.is_big()) {
        if (all) out.push_back(Word256::from_value(v));
        return;
    }
    if (!(v.is_expr() || v.is_list()) || v.is(Op::ASM) || !seen.add(v)) return;
    for (Value c : v.children()) ints_of(c, seen, out, all);
}

// the conditions of the IFs and WHILEs of a trace (any depth)
void conds_of(Value t, std::vector<Value>& out) {
    check_stack();
    if (!t.is_trace()) return;
    for (Value l : t.args()) {
        if (l.is(Op::IF, 3) || l.is(Op::WHILE, 4)) out.push_back(l[0]);
        if (l.is_expr())
            for (Value a : l.args())
                if (a.is_trace()) conds_of(a, out);
    }
}

bool ends(std::span<const Value> lines) {
    if (lines.empty()) return false;
    switch (lines.back().op()) {
        case Op::REVERT:
        case Op::INVALID:
        case Op::RETURN:
        case Op::STOP: return true;
        default: return false;
    }
}

// python splits(): the trace with what's after a first part of it replaced
// by tail - the least first: after each line, and into the branch of an if
// that goes on when the other ends. yield(candidate) -> false: stop.
// (a candidate each: no hot path - at most MAX_CANDIDATES of them)
bool splits(std::span<const Value> lines, Value tail, const std::function<bool(Value)>& yield) {
    check_stack();
    std::vector<Value> pre;
    for (usize i = 0; i < lines.size(); ++i) {
        poll();
        {
            std::vector<Value> c(lines.begin(), lines.begin() + i);
            c.push_back(tail);
            if (!yield(mk_trace(std::span<const Value>(c.data(), c.size())))) return false;
        }
        const Value line = lines[i];
        if (line.is(Op::IF, 3) && line[1].is_trace() && line[2].is_trace()) {
            const Value cond = line[0], a = line[1], b = line[2];
            for (int side = 0; side < 2; ++side) {
                const Value fails = side == 0 ? a : b, goes = side == 0 ? b : a;
                if (!ends(fails.args())) continue;
                std::vector<Value> rest(goes.begin(), goes.end());
                rest.insert(rest.end(), lines.begin() + i + 1, lines.end());
                const bool go = splits(std::span<const Value>(rest.data(), rest.size()), tail, [&](Value sub) {
                    std::vector<Value> c(lines.begin(), lines.begin() + i);
                    c.push_back(side == 0 ? mk(Op::IF, cond, a, sub) : mk(Op::IF, cond, sub, b));
                    return yield(mk_trace(std::span<const Value>(c.data(), c.size())));
                });
                if (!go) return false;
            }
        }
    }
    return true;
}

// A world of the check: the calldata and the getter's bytes, by their
// parameters - the slot word's form, the length L, garbage where an encoding
// has bytes no reader should use, the slots next to the getter's - its
// storage made of fixed patterns (no randomness: the same verdict on every run)
struct World {
    std::vector<u8> calldata;
    bool odd = false;         // the slot word's low bit: L = s / 2 (else (s & 0xff) / 2)
    u64 len = 0;              // L
    bool garbage = false;     // bytes past L: the slot word's, the last data word's, the slot after the data
    bool neighbours = false;  // the slots next to the getter's non-zero
    u64 id = 0;               // the patterns' seed
    // as solidity keeps the bytes (the short form below 32, the long one from 32)
    bool clean() const noexcept { return !garbage && !neighbours && odd == (len >= 32); }
};

// the pattern word i of world id: no byte 0 (every byte's low bit set)
Word256 pattern(u64 id, u64 i) noexcept {
    const u64 h = hash_mix(id * 0x9e3779b97f4a7c15ull ^ (i + 1) * 0xc2b2ae3d27d4eb4full);
    Word256 w;
    for (int k = 0; k < 4; ++k) w.limb[k] = (h + u64(k)) * 0xd6e8feb86659fd93ull | 0x0101010101010101ull;
    return w;
}

// the high n bytes of w, the others 0
Word256 high_bytes(const Word256& w, u64 n) noexcept {
    if (n >= 32) return w;
    const Word256 s = Word256::of(8 * (32 - n));
    return pan::shl(s, pan::shr(s, w));
}

// a world's storage: the getter's slot, the words from keccak(slot) on - the
// long form's ceil(L / 32), garbage or 0 past L, then the slot after them;
// the long form's flag with a short length: two of garbage (what a reader
// going by the flag reads); the short form below 32: none - and the slots
// next to the getter's
struct Storage {
    Word256 slot{};
    std::vector<Word256> data;
    std::optional<Word256> up, down;
};

Storage storage_of(const World& w) {
    Storage st;
    if (w.odd) {
        st.slot = Word256::of(2 * w.len + 1);
    } else {  // the bytes (below 32), garbage or 0 past them, 2L
        const u64 n = w.len < 32 ? w.len : 0;
        st.slot = high_bytes(pattern(w.id, 0), n);
        if (w.garbage) {
            const Word256 g = pattern(w.id, 1);
            st.slot = pan::bor(st.slot, pan::bxor(g, high_bytes(g, n)));
        }
        st.slot.limb[0] = (st.slot.limb[0] & ~u64(0xff)) | 2 * w.len;
    }
    if (w.len < 32) {
        if (w.odd) st.data = {pattern(w.id, 2), pattern(w.id, 3)};
    } else {
        const u64 n = (w.len + 31) / 32;
        st.data.reserve(n + 1);
        for (u64 i = 0; i < n; ++i) st.data.push_back(pattern(w.id, 2 + i));
        if (!w.garbage) st.data.back() = high_bytes(st.data.back(), w.len - 32 * (n - 1));
        st.data.push_back(w.garbage ? pattern(w.id, 2 + n) : Word256{});
    }
    if (w.neighbours) {
        st.up = pattern(w.id, u64(1) << 40);
        st.down = pattern(w.id, (u64(1) << 40) + 1);
    }
    return st;
}

// a world's storage at the getter's slot (any other slot: Unsupported)
class GetterHost final : public exec::SimpleHost {
public:
    GetterHost() = default;
    // (base: keccak(slot), the data's first slot)
    GetterHost(const Storage& st, const Word256& slot, const Word256& base) : st_(&st), slot_(slot), base_(base) {}
    Word256 sload(const Word256& s) override {
        if (st_) {
            if (s == slot_) return st_->slot;
            if (const auto i = pan::sub(s, base_).as_u64(); i && *i < st_->data.size()) return st_->data[*i];
            if (st_->up && s == pan::add(slot_, Word256::of(1))) return *st_->up;
            if (st_->down && s == pan::sub(slot_, Word256::of(1))) return *st_->down;
        }
        throw Unsupported("storage: another slot");
    }
    // (slots base + i all among the data words and none the getter's slot -
    // the one sload answers first: those words)
    const Word256* sload_run(const Word256& base, u64 n) override {
        if (!st_ || n == 0) return nullptr;
        const auto d = pan::sub(base, base_).as_u64();
        if (!d || *d > st_->data.size() || n > st_->data.size() - *d) return nullptr;
        if (const auto e = pan::sub(slot_, base).as_u64(); e && *e < n) return nullptr;
        return st_->data.data() + *d;
    }

private:
    const Storage* st_ = nullptr;
    Word256 slot_{}, base_{};
};

struct Result {
    bool ok = false;  // halted (else the run says nothing)
    exec::Status status = exec::Status::Stop;
    std::vector<u8> data;
    bool reached = false;  // it ended at the tail's line
    bool operator==(const Result& o) const { return ok == o.ok && status == o.status && data == o.data; }
};

// r returns the ABI encoding of w's bytes as solidity keeps them (w clean)
bool returns_bytes(const Result& r, const World& w, const Storage& st) {
    if (r.status != exec::Status::Return) return false;
    std::vector<u8> want;
    put_word(want, Word256::of(32));
    put_word(want, Word256::of(w.len));
    if (w.len < 32) {
        if (w.len) put_word(want, high_bytes(st.slot, w.len));
    } else {
        for (usize i = 0; i + 1 < st.data.size(); ++i) put_word(want, st.data[i]);
    }
    return r.data == want;
}

}  // namespace

BytesTail::BytesTail(const FunctionInfo& fn, std::span<const FunctionInfo> internals, const ContractShared* shared,
                     i64 deadline_ns)
    : fn_(fn), deadline_(deadline_ns) {
    program_.functions = std::span<const FunctionInfo>(&fn_, 1);
    program_.internals = internals;
    program_.shared = shared;
    program_.layout = &layout_;
    machine_ = std::make_unique<exec::Machine>(program_, exec::MachineLimits::storage_check());
}

BytesTail::~BytesTail() = default;

Value BytesTail::find(Value trace, Value key) {
    // The worlds, in this order (the larger ones last: a wrong candidate fails
    // early). The short form (even slot word) of every L from 0 to 31, as
    // solidity keeps it and with garbage in the slot word's bytes past L; the
    // long form's flag (odd) with every L below 32, its data words garbage
    // (solc never writes it); the long form of every L from 32 to 95, clean
    // and with garbage past L in the last data word and in the slot after the
    // data; the short form's flag with every L from 32 to 127 (an even word
    // can't say more); the slots next to the getter's non-zero; the params of
    // the numbers the trace's conditions compare with, calldata too short for
    // a param; lengths around the trace's numbers past 159; the long form of
    // every residue r of L = 32 * M + r at M = 3, 4, M_LARGE and M_MAX, with
    // garbage.
    static const Word256 values[] = {Word256::of(0),
                                     Word256::of(1),
                                     Word256::of(2),
                                     Word256::of(255),
                                     Word256::of(0xffff),
                                     Word256{{~u64(0), ~u64(0), 0xffffffffull, 0}},
                                     Word256{{0, 0, 0x100000000ull, 0}},
                                     Word256{{0, 0, 0, u64(1) << 63}},
                                     Word256{{~u64(0), ~u64(0), ~u64(0), ~u64(0)}}};
    constexpr usize NV = sizeof(values) / sizeof(values[0]);
    const u32 sel = fn_.selector;
    const u8 selb[4] = {u8(sel >> 24), u8(sel >> 16), u8(sel >> 8), u8(sel)};
    std::vector<World> worlds;
    auto add = [&](bool odd, u64 len, bool garbage, bool neighbours = false) {
        World w;
        w.odd = odd;
        w.len = len;
        w.garbage = garbage;
        w.neighbours = neighbours;
        w.id = worlds.size();
        w.calldata.assign(selb, selb + 4);
        for (usize k = 0; k < 8; ++k) put_word(w.calldata, values[(worlds.size() + 3 * k) % NV]);
        worlds.push_back(std::move(w));
    };
    for (u64 l = 0; l < 32; ++l) {
        add(false, l, false);
        add(false, l, true);
    }
    for (u64 l = 0; l < 32; ++l) add(true, l, true);
    for (u64 l = 32; l < 96; ++l) {
        add(true, l, false);
        add(true, l, true);
    }
    for (u64 l = 32; l < 128; ++l) add(false, l, true);
    for (const u64 l : {5, 31, 32, 77}) add(l >= 32, l, true, true);
    {
        std::vector<Value> conds;
        conds_of(trace, conds);
        Memo<Value, u8> seen;
        std::vector<Word256> ints;
        for (Value c : conds) ints_of(c, seen, ints, true);
        std::set<Word256> near;
        for (const Word256& c : ints)
            for (const Word256& d : {pan::sub(c, Word256::of(1)), c, pan::add(c, Word256::of(1))}) near.insert(d);
        usize n = 0;
        for (const Word256& v : near) {
            if (n >= 64) break;
            if (std::find(std::begin(values), std::end(values), v) != std::end(values)) continue;
            add(n % 2 == 1, n % 2 ? 32 + n : n % 32, false);
            worlds.back().calldata.resize(4);
            for (int k = 0; k < 8; ++k) put_word(worlds.back().calldata, v);
            ++n;
        }
    }
    for (usize n : {usize(0), usize(31)}) {  // calldata too short for a param
        add(false, 2, false);
        worlds.back().calldata.resize(4);
        worlds.back().calldata.insert(worlds.back().calldata.end(), n, u8(1));
    }
    {
        Memo<Value, u8> seen;
        std::vector<Word256> ints;
        ints_of(trace, seen, ints, false);
        std::set<u64> around;
        for (const Word256& w : ints) {
            const u64 c = w.limb[0];
            for (u64 x : {c - 1, c, c + 1, c / 2, c / 2 + 1})
                if (x >= 160) around.insert(x);
        }
        usize added = 0;
        for (u64 x : around)
            if (added++ < 48) add(true, x, true);
    }
    for (const u64 m : {u64(3), u64(4), M_LARGE, M_MAX})
        for (u64 r = 0; r < 32; ++r) add(true, 32 * m + r, true);

    const Value tail_line =
        mk(Op::RETURN, mk(Op::DATA, mk(Op::ARR, mk(Op::STORAGE, small(256), small(0), mk(Op::LENGTH, key)),
                                       mk(Op::SALL, mk(Op::SR, key)))));
    const Value key_trace = mk_trace({mk(Op::RETURN, mk(Op::SIZED, small(32), key))});

    // the storage of the last world run (the original's run and a
    // candidate's on a world come one after the other)
    usize cached = worlds.size();
    Storage st;
    // keccak of the last slot (the same in most worlds)
    std::optional<std::pair<Word256, Word256>> slot_base;
    auto run = [&](Value t, usize k) -> Result {
        poll();
        if (steps_ > MAX_STEPS) return Result{};  // (too long a check: no rewrite)
        const World& w = worlds[k];
        GetterHost kh;
        kh.calldata = w.calldata;
        // the slot of the bytes, with this calldata
        const exec::Outcome ko = machine_->run(kh, fn_, key_trace);
        steps_ += ko.steps;
        if (ko.status != exec::Status::Return || ko.data.size() != 32) return Result{};
        if (cached != k) {
            st = storage_of(w);
            cached = k;
        }
        const Word256 slot = Word256::from_be(ko.data);
        if (!slot_base || slot_base->first != slot) slot_base.emplace(slot, keccak_word(slot));
        GetterHost host(st, slot, slot_base->second);
        host.calldata = w.calldata;
        exec::Outcome o = machine_->run(host, fn_, t);
        steps_ += o.steps;
        if (!o.halted()) return Result{};
        Result r;
        r.ok = true;
        r.status = o.status;
        r.data = std::move(o.data);
        r.reached = o.status == exec::Status::Return && o.line == tail_line;
        return r;
    };

    // the original's results, run as far as a candidate gets (a world the
    // original says nothing in: no rewrite)
    std::vector<Result> orig;
    bool broken = false;
    auto orig_at = [&](usize k) -> const Result* {
        while (orig.size() <= k && !broken) {
            Result r = run(trace, orig.size());
            if (r.ok)
                orig.push_back(std::move(r));
            else
                broken = true;
        }
        return k < orig.size() ? &orig[k] : nullptr;
    };

    Value found;
    usize count = 0;
    splits(trace.args(), tail_line, [&](Value cand) {
        if (count++ >= MAX_CANDIDATES || steps_ > MAX_STEPS) return false;
        if (deadline_ && platform::monotonic_ns() > deadline_)
            throw Timeout("the post-processing and the text took more than 3 minutes");
        bool reached = false;
        for (usize k = 0; k < worlds.size(); ++k) {
            const Result* o = orig_at(k);
            if (!o) return false;
            const Result got = run(cand, k);
            if (!got.ok || !(got == *o)) return true;
            // the bytes returned by what's kept of the code, not by the tail
            // (a branch kept returns something else: `return ''`)
            if (worlds[k].clean() && worlds[k].len > 0 && !got.reached && returns_bytes(*o, worlds[k], st))
                return true;
            reached |= got.reached;
        }
        if (!reached) return true;
        found = cand;
        return false;
    });
    return found;
}

}  // namespace pan::storage::detail
