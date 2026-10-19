// The getters (python storage.py: getter_access, bytes_tail, splits): what
// a getter returns - its storage access names the variable - and the
// getters of a bytes/string, whose copy of the bytes to the memory is
// replaced by `return name[all]` when running both (the trace machine, on
// storage worlds) says it is the same.
#include "storage/getters.hpp"

#include <algorithm>
#include <functional>
#include <set>

#include "algebra/masks.hpp"
#include "core/context.hpp"
#include "core/errors.hpp"
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

// a deterministic stream of numbers (splitmix64)
struct Rng {
    u64 s = 0;
    u64 next() noexcept {
        u64 z = (s += 0x9e3779b97f4a7c15ull);
        z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9ull;
        z = (z ^ (z >> 27)) * 0x94d049bb133111ebull;
        return z ^ (z >> 31);
    }
    std::vector<u8> content(usize n) {
        std::vector<u8> b(n);
        for (u8& c : b) c = u8(1 + next() % 255);
        return b;
    }
};

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
    if (!(v.is_expr() || v.is_list()) || !seen.add(v)) return;
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

// a storage world of the getter's check: the words set, any other slot unknown
class GetterHost final : public exec::SimpleHost {
public:
    Word256 sload(const Word256& slot) override {
        if (auto it = storage.find(slot); it != storage.end()) return it->second;
        throw Unsupported("storage: another slot");
    }
};

// a storage world: the calldata, the bytes (python's content, when clean:
// as solidity keeps them), the slot's word and the words from keccak(slot) on
struct World {
    std::vector<u8> calldata, content;
    bool clean = true;
    Word256 word{};
    std::vector<Word256> data;
};

// the words of bytes as solidity keeps them (python's), garbage past them
// when dirty
void encode(World& w, Rng& rnd, bool dirty) {
    const usize len = w.content.size();
    if (len < 32) {
        u8 b[32] = {};
        std::copy(w.content.begin(), w.content.end(), b);
        if (dirty)
            for (usize i = len; i < 31; ++i) b[i] = u8(1 + rnd.next() % 255);
        b[31] = u8(2 * len);
        w.word = Word256::from_be(std::span<const u8>(b, 32));
        w.data.clear();
        return;
    }
    w.word = pan::add(pan::shl(Word256::of(1), Word256::of(len)), Word256::of(1));
    std::vector<u8> padded = w.content;
    while (padded.size() % 32) padded.push_back(dirty ? u8(1 + rnd.next() % 255) : 0);
    w.data.clear();
    for (usize i = 0; i < padded.size() / 32 + 1; ++i) {
        u8 b[32] = {};
        if (32 * i < padded.size()) std::copy(padded.begin() + 32 * i, padded.begin() + 32 * i + 32, b);
        w.data.push_back(Word256::from_be(std::span<const u8>(b, 32)));
    }
}

struct Result {
    bool ok = false;  // halted (else the run says nothing)
    exec::Status status = exec::Status::Stop;
    std::vector<u8> data;
    bool reached = false;  // it ended at the tail's line
    bool operator==(const Result& o) const { return ok == o.ok && status == o.status && data == o.data; }
};

}  // namespace

BytesTail::BytesTail(const FunctionInfo& fn, std::span<const FunctionInfo> internals, const ContractShared* shared)
    : fn_(fn) {
    program_.functions = std::span<const FunctionInfo>(&fn_, 1);
    program_.internals = internals;
    program_.shared = shared;
    program_.layout = &layout_;
    machine_ = std::make_unique<exec::Machine>(program_, exec::MachineLimits::storage_check());
}

BytesTail::~BytesTail() = default;

Value BytesTail::find(Value trace, Value key) {
    // the worlds: bytes as solidity keeps them, short and long, of every
    // length the code may treat apart, params clean and dirty and of the
    // numbers the code compares with
    Rng rnd;
    std::vector<i64> lengths{0, 1, 2, 30, 31, 32, 33, 63, 64, 65, 96, 97, 300};
    {
        Memo<Value, u8> seen;
        std::vector<Word256> ints;
        ints_of(trace, seen, ints, false);
        std::set<i64> around;
        for (const Word256& w : ints) {
            const i64 c = i64(w.limb[0]);
            for (i64 x : {c - 1, c, c + 1, c / 2, c / 2 + 1}) around.insert(x);
        }
        usize added = 0;
        const std::vector<i64> base = lengths;
        for (i64 x : around) {
            if (added >= 48) break;
            if (std::find(base.begin(), base.end(), x) != base.end()) continue;
            lengths.push_back(x);
            ++added;
        }
    }
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
    for (usize n = 0; n < lengths.size(); ++n) {
        World w;
        w.content = rnd.content(usize(std::max<i64>(lengths[n], 0)));
        w.calldata.assign(selb, selb + 4);
        for (usize k = 0; k < 8; ++k) put_word(w.calldata, values[(n + 3 * k) % NV]);
        encode(w, rnd, false);
        worlds.push_back(std::move(w));
    }
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
            World w;
            w.content = rnd.content(usize(std::max<i64>(lengths[n % lengths.size()], 0)));
            w.calldata.assign(selb, selb + 4);
            for (int k = 0; k < 8; ++k) put_word(w.calldata, v);
            encode(w, rnd, false);
            worlds.push_back(std::move(w));
            ++n;
        }
    }
    for (usize n : {usize(0), usize(31)}) {  // calldata too short for a param
        World w;
        w.calldata.assign(selb, selb + 4);
        w.calldata.insert(w.calldata.end(), n, u8(1));
        w.content = {u8('a'), u8('b')};
        encode(w, rnd, false);
        worlds.push_back(std::move(w));
    }
    // and what no solc keeps, as a random world holds: garbage past the bytes,
    // a short encoding of a length past 31 (its data words read by a legacy
    // copy), a long one of a length below 32
    {
        const usize base = worlds.size();
        for (usize n = 0; n < 13 && n < base; ++n) {
            World w = worlds[n];
            if (w.content.empty()) continue;
            w.clean = false;
            encode(w, rnd, true);
            worlds.push_back(std::move(w));
        }
        for (u64 len : {u64(32), u64(33), u64(50), u64(64), u64(127)}) {
            World w;
            w.clean = false;
            w.calldata = worlds[len % base].calldata;
            u8 b[32];
            for (u8& c : b) c = u8(rnd.next());
            b[31] = u8(2 * len);
            w.word = Word256::from_be(std::span<const u8>(b, 32));
            for (u64 i = 0; i < (len + 31) / 32 + 1; ++i)
                w.data.push_back(Word256{{rnd.next(), rnd.next(), rnd.next(), rnd.next()}});
            worlds.push_back(std::move(w));
        }
        for (u64 len : {u64(0), u64(1), u64(5), u64(31)}) {
            World w;
            w.clean = false;
            w.calldata = worlds[len % base].calldata;
            w.word = Word256::of(2 * len + 1);
            for (u64 i = 0; i < 2; ++i) w.data.push_back(Word256{{rnd.next(), rnd.next(), rnd.next(), rnd.next()}});
            worlds.push_back(std::move(w));
        }
    }

    const Value tail_line =
        mk(Op::RETURN, mk(Op::DATA, mk(Op::ARR, mk(Op::STORAGE, small(256), small(0), mk(Op::LENGTH, key)),
                                       mk(Op::SALL, mk(Op::SR, key)))));
    const Value key_trace = mk_trace({mk(Op::RETURN, mk(Op::SIZED, small(32), key))});

    auto run = [&](Value t, const World& w) -> Result {
        poll();
        GetterHost host;
        host.calldata = w.calldata;
        // the slot of the bytes, with this calldata
        const exec::Outcome ko = machine_->run(host, fn_, key_trace);
        if (ko.status != exec::Status::Return || ko.data.size() != 32) return Result{};
        const Word256 slot = Word256::from_be(ko.data);
        host.storage[slot] = w.word;
        if (!w.data.empty()) {
            const Word256 base = keccak_word(slot);
            for (usize i = 0; i < w.data.size(); ++i) host.storage[pan::add(base, Word256::of(i))] = w.data[i];
        }
        const exec::Outcome o = machine_->run(host, fn_, t);
        if (!o.halted()) return Result{};
        Result r;
        r.ok = true;
        r.status = o.status;
        r.data = o.data;
        r.reached = o.status == exec::Status::Return && o.line == tail_line;
        return r;
    };

    std::vector<Result> orig;
    bool returns = false;
    for (const World& w : worlds) {
        Result r = run(trace, w);
        if (!r.ok) return Value();
        returns |= r.status == exec::Status::Return;
        orig.push_back(std::move(r));
    }
    if (!returns) return Value();

    auto returns_bytes = [](const Result& r, const std::vector<u8>& content) {
        if (r.status != exec::Status::Return) return false;
        std::vector<u8> d;
        put_word(d, Word256::of(32));
        put_word(d, Word256::of(content.size()));
        d.insert(d.end(), content.begin(), content.end());
        d.resize(64 + (content.size() + 31) / 32 * 32, 0);
        return r.data == d;
    };

    Value found;
    usize count = 0;
    splits(trace.args(), tail_line, [&](Value cand) {
        if (count++ >= MAX_CANDIDATES) return false;
        bool reached = false;
        for (usize k = 0; k < worlds.size(); ++k) {
            const Result got = run(cand, worlds[k]);
            if (!got.ok || !(got == orig[k])) return true;
            // the bytes returned by what's kept of the code, not by the tail
            // (a branch kept returns something else: `return ''`)
            if (worlds[k].clean && !worlds[k].content.empty() && returns_bytes(orig[k], worlds[k].content) &&
                !got.reached)
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
