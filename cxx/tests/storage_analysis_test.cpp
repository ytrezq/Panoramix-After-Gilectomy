// The storage analysis (lot 9: storage::analyse) on hand-made traces: the
// layout it finds (variables, types, names), the forms the accesses become -
// and, every time, the rewritten traces run by the trace machine against the
// raw ones on storage worlds: the same ends, the same writes.
#include <doctest/doctest.h>

#include <optional>
#include <string>
#include <vector>

#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/contract.hpp"
#include "core/dump.hpp"
#include "core/evmint.hpp"
#include "exec/machine.hpp"
#include "storage/names.hpp"
#include "storage/storage.hpp"

using namespace pan;

namespace {

struct Fixture {
    Budget budget{Budget::Limits{}};
    std::unique_ptr<Context> ctx;
    std::optional<ContextScope> scope;
    Fixture() {
        init();
        budget.attach_thread();
        ctx = Context::create(budget);
        scope.emplace(*ctx);
    }
    ~Fixture() {
        scope.reset();
        ctx.reset();
        budget.detach_thread();
    }
};

using Kind = StorageType::Kind;

// a world of random storage words (small ones in odd worlds) and calldata
class HashWorld final : public exec::SimpleHost {
public:
    HashWorld(u64 seed, u32 selector) : seed_(seed) {
        calldata = {u8(selector >> 24), u8(selector >> 16), u8(selector >> 8), u8(selector)};
        for (int i = 0; i < 6; ++i) {
            u8 w[32];
            const Word256 v = seed & 1 ? Word256::of((seed * 7 + u64(i) * 13) & 0xff) : mix(u64(i) + 100);
            v.to_be(w);
            calldata.insert(calldata.end(), w, w + 32);
        }
        call_env.caller = Word256{{0xaaaabbbbccccddddull + seed, 0x1111, 0x22, 0}};
        call_env.callvalue = Word256::of(seed);
    }
    Word256 initial(const Word256& slot) override {
        u8 buf[32];
        slot.to_be(buf);
        Word256 h = exec::keccak256(std::span<const u8>(buf, 32));
        h.limb[0] ^= seed_;
        return seed_ & 1 ? Word256::of(h.limb[0] & 0xffff) : h;
    }

private:
    Word256 mix(u64 k) const {
        Word256 w;
        for (u64 i = 0; i < 4; ++i) w.limb[i] = hash_mix(k * 31 + i + seed_ * 1000003);
        return w;
    }
    u64 seed_;
};

// the effects as the stage checks compare them (validate/effects.hpp): the
// events but the storage writes in their order, and the storage at the end
bool same_effects(exec::SimpleHost& a, exec::SimpleHost& b) {
    auto events = [](const exec::SimpleHost& h) {
        std::vector<exec::SimpleHost::Effect> e;
        for (const auto& x : h.effects)
            if (!std::holds_alternative<exec::SimpleHost::Sstore>(x)) e.push_back(x);
        return e;
    };
    if (events(a) != events(b)) return false;
    for (const auto* h : {&a, &b})
        for (const auto& [slot, value] : h->storage) {
            (void)value;
            if (a.sload(slot) != b.sload(slot)) return false;
        }
    return true;
}

FunctionInfo fn(u32 selector, std::string_view trace) {
    FunctionInfo f;
    f.kind = FunctionInfo::Kind::Selector;
    f.selector = selector;
    f.entry.selector = selector;
    f.trace = V(trace);
    return f;
}

struct Analysed {
    std::vector<FunctionInfo> before, after;
    std::shared_ptr<const StorageLayout> layout;
};

Analysed analyse(std::vector<FunctionInfo> fns, Lang lang = Lang::Solidity) {
    Analysed a;
    a.before = fns;
    a.after = fns;
    ContractShared shared;
    shared.lang = lang;
    std::vector<FunctionInfo> internals;
    a.layout = storage::analyse(a.after, internals, shared);
    return a;
}

// every function, raw and rewritten, the same in 8 worlds
void same_runs(const Analysed& a) {
    REQUIRE(a.before.size() == a.after.size());
    for (usize i = 0; i < a.before.size(); ++i) {
        exec::Program p0, p1;
        p0.functions = a.before;
        p1.functions = a.after;
        p1.layout = a.layout.get();
        exec::Machine m0(p0), m1(p1);
        for (u64 seed = 0; seed < 8; ++seed) {
            HashWorld w0(seed, a.before[i].selector), w1(seed, a.before[i].selector);
            const exec::Outcome o0 = m0.run(w0, a.before[i]);
            const exec::Outcome o1 = m1.run(w1, a.after[i]);
            INFO("function ", i, " seed ", seed, ": ", dump(a.after[i].trace), " / ", o0.note, " / ", o1.note);
            CHECK(o1.status != exec::Status::Bug);
            CHECK(o0.status == o1.status);
            CHECK(o0.data == o1.data);
            CHECK(same_effects(w0, w1));
        }
    }
}

bool has(Value v, Value part) {
    if (v == part) return true;
    for (Value c : v.children())
        if (has(c, part)) return true;
    return false;
}

// no access left raw: no STORAGE, STORE, LENGTH, LOC
bool no_pre_p(Value v) {
    switch (v.op()) {
        case Op::STORAGE:
        case Op::STORE:
        case Op::LENGTH:
        case Op::LOC:
        case Op::SBYTES:
            return false;
        default:
            break;
    }
    for (Value c : v.children())
        if (!no_pre_p(c)) return false;
    return true;
}

}  // namespace

TEST_CASE("storage: getter names (Ragel)") {
    using storage::detail::getter_name;
    using storage::detail::good_name;
    auto bytes = [](std::string_view s) { return std::span<const u8>(reinterpret_cast<const u8*>(s.data()), s.size()); };
    CHECK(good_name(bytes("balanceOf")));
    CHECK(good_name(bytes("owner")));
    CHECK(good_name(bytes("get")));
    CHECK(good_name(bytes("x_1")));
    CHECK(good_name(bytes("storage")));  // (not the word stor)
    CHECK(good_name(bytes("integer")));
    CHECK(!good_name(bytes("")));
    CHECK(!good_name(bytes("stor")));
    CHECK(!good_name(bytes("stor5")));
    CHECK(!good_name(bytes("storA66D")));
    CHECK(!good_name(bytes("storA66D_3")));
    CHECK(!good_name(bytes("stor0_160")));
    CHECK(!good_name(bytes("uint256")));
    CHECK(!good_name(bytes("int")));
    CHECK(!good_name(bytes("bytes32")));
    CHECK(!good_name(bytes("_owner")));
    CHECK(!good_name(bytes("unknown1234")));
    CHECK(!good_name(bytes("address")));
    CHECK(!good_name(bytes("max")));
    CHECK(!good_name(bytes("1abc")));
    CHECK(!good_name(bytes("a-b")));
    CHECK(!good_name(bytes("caf\xc3\xa9")));  // (ASCII names only)
    auto gn = getter_name(bytes("getBalance"));
    CHECK(gn.good);
    CHECK(gn.strip);
    gn = getter_name(bytes("getStor5"));
    CHECK(!gn.good);
    CHECK(gn.strip);
    gn = getter_name(bytes("getaway"));
    CHECK(gn.good);
    CHECK(!gn.strip);
    gn = getter_name(bytes("getMax"));
    CHECK(!gn.good);
    gn = getter_name(bytes("getX"));
    CHECK(gn.good);
    CHECK(gn.strip);
}

TEST_CASE("storage: a token - values, mappings, mappings of mappings") {
    Fixture f;
    std::vector<FunctionInfo> fns{
        fn(0x313ce567, "{(return (sized 32 (storage 8 0 2)))}"),
        fn(0x70a08231, "{(return (sized 32 (storage 256 0 (sha3 (sized 32 (mask_shl 160 0 0 (calldataload 4))) (sized 32 3)))))}"),
        fn(0xdd62ed3e,
           "{(return (sized 32 (storage 256 0 (sha3 (sized 32 (mask_shl 160 0 0 (calldataload 36))) (sized 32 (sha3 (sized "
           "32 (mask_shl 160 0 0 (calldataload 4))) (sized 32 4)))))))}"),
        fn(0xa9059cbb,
           "{(if (lt (storage 256 0 (sha3 (sized 32 caller) (sized 32 3))) (calldataload 36)) {(revert None)} {"
           "(store 256 0 (sha3 (sized 32 caller) (sized 32 3)) (add (mul -1 (calldataload 36)) (storage 256 0 (sha3 (sized 32 "
           "caller) (sized 32 3)))))"
           "(store 256 0 (sha3 (sized 32 (mask_shl 160 0 0 (calldataload 4))) (sized 32 3)) (add (calldataload 36) (storage 256 0 "
           "(sha3 (sized 32 (mask_shl 160 0 0 (calldataload 4))) (sized 32 3)))))"
           "(return (sized 32 1))})}"),
        fn(0x095ea7b3,
           "{(store 256 0 (sha3 (sized 32 (mask_shl 160 0 0 (calldataload 4))) (sized 32 (sha3 (sized 32 caller) (sized 32 4)))) "
           "(calldataload 36)) (return (sized 32 1))}"),
    };
    const Analysed a = analyse(fns);
    const StorageLayout& l = *a.layout;
    CHECK(l.lang == Lang::Solidity);
    REQUIRE(l.vars.size() == 3);
    CHECK(l.vars[0].slot == Word256::of(2));
    CHECK(l.types[l.vars[0].type].kind == Kind::Value);
    CHECK(l.types[l.vars[0].type].width == 8);
    CHECK(l.vars[1].slot == Word256::of(3));
    CHECK(l.types[l.vars[1].type].kind == Kind::Mapping);
    CHECK(l.types[l.types[l.vars[1].type].elem].kind == Kind::Value);
    CHECK(l.vars[2].slot == Word256::of(4));
    CHECK(l.types[l.vars[2].type].kind == Kind::Mapping);
    CHECK(l.types[l.types[l.vars[2].type].elem].kind == Kind::Mapping);
    // the forms
    CHECK(a.after[0].trace == V("{(return (sized 32 (st 8 (sv stor0) 8)))}"));
    CHECK(has(a.after[3].trace, V("(st 256 (si (sv stor1) caller) 256)")));
    CHECK(has(a.after[4].trace, V("(set (st 256 (si (si (sv stor2) caller) (mask_shl 160 0 0 (calldataload 4))) 256) (calldataload 36))")));
    same_runs(a);
}

TEST_CASE("storage: packed fields, split stores regrouped") {
    Fixture f;
    std::vector<FunctionInfo> fns{
        // uint112 at 0, uint112 at 112, uint32 at 224 (UniswapV2's reserves)
        fn(0x0902f1ac,
           "{(return (data (sized 32 (storage 112 0 8)) (sized 32 (storage 112 112 8)) (sized 32 (storage 32 224 8))))}"),
        fn(0x11111111, "{(store 112 0 8 (calldataload 4)) (store 112 112 8 (calldataload 36)) (store 32 224 8 timestamp) (stop)}"),
        // an address at 0 and a flag at 160 of slot 1: a delete of the slot, split
        fn(0x22222222, "{(return (sized 32 (storage 160 0 1)))}"),
        fn(0x33333333, "{(return (sized 32 (storage 8 160 1)))}"),
        fn(0x44444444, "{(store 160 0 1 caller) (store 8 160 1 (iszero (calldataload 4))) (stop)}"),
        fn(0x55555555, "{(store 160 0 1 0) (store 96 160 1 0) (stop)}"),
        // two numbers in one variable (a split store of 0x0102 in a uint16): one store
        fn(0x66666666, "{(return (sized 32 (storage 16 0 2)))}"),
        fn(0x77777777, "{(store 16 0 2 (calldataload 4)) (stop)}"),
        fn(0x88888888, "{(store 8 0 2 2) (store 8 8 2 1) (stop)}"),
    };
    const Analysed a = analyse(fns);
    const StorageLayout& l = *a.layout;
    // slot 1: the address, the flag, the bits the delete clears above them;
    // slot 2: the uint16; slot 8: the reserves
    REQUIRE(l.vars.size() == 7);
    CHECK(l.vars[0].slot == Word256::of(1));
    CHECK(l.vars[0].off == 0);
    CHECK(l.types[l.vars[0].type].width == 160);
    CHECK(l.vars[1].slot == Word256::of(1));
    CHECK(l.vars[1].off == 160);
    CHECK(l.types[l.vars[1].type].width == 8);
    CHECK(l.vars[2].off == 168);
    CHECK(l.vars[3].slot == Word256::of(2));
    CHECK(l.types[l.vars[3].type].width == 16);
    CHECK(l.vars[4].off == 0);
    CHECK(l.vars[5].off == 112);
    CHECK(l.vars[6].off == 224);
    CHECK(a.after[0].trace ==
          V("{(return (data (sized 32 (st 112 (sv stor4) 112)) (sized 32 (st 112 (sv stor5) 112)) (sized 32 (st 32 (sv stor6) 32))))}"));
    // the split number regrouped
    CHECK(a.after[8].trace == V("{(set (st 16 (sv stor3) 16) 258) (stop)}"));
    same_runs(a);
}

TEST_CASE("storage: dynamic arrays, packed arrays, fixed arrays, structs in mappings") {
    Fixture f;
    // keccak(5) (the data of the array at 5) as the simplifier leaves it: a sha3 of the slot
    std::vector<FunctionInfo> fns{
        fn(0x01010101, "{(return (sized 32 (storage 256 0 5)))}"),
        fn(0x02020202, "{(if (lt (calldataload 4) (storage 256 0 5)) {(return (sized 32 (storage 256 0 (add (calldataload 4) (sha3 (sized 32 5))))))} {(revert None)})}"),
        fn(0x03030303, "{(store 256 0 (add (calldataload 4) (sha3 (sized 32 5))) (calldataload 36)) (stop)}"),
        // a mapping of structs of 3 words: members 0 and 2
        fn(0x04040404, "{(return (sized 32 (storage 256 0 (sha3 (sized 32 caller) (sized 32 7)))))}"),
        fn(0x05050505, "{(return (sized 32 (storage 256 0 (add 2 (sha3 (sized 32 caller) (sized 32 7))))))}"),
        fn(0x06060606, "{(store 256 0 (add 2 (sha3 (sized 32 caller) (sized 32 7))) 9) (stop)}"),
        // a fixed array of 4 words at 10, its index checked
        fn(0x07070707, "{(if (lt (calldataload 4) 4) {(return (sized 32 (storage 256 0 (add 10 (calldataload 4)))))} {(revert None)})}"),
    };
    const Analysed a = analyse(fns);
    const StorageLayout& l = *a.layout;
    bool array = false, mapping = false, fixed = false;
    for (const StorageVar& v : l.vars) {
        const StorageType& t = l.types[v.type];
        if (v.slot == Word256::of(5)) array = t.kind == Kind::Array;
        if (v.slot == Word256::of(7)) mapping = t.kind == Kind::Mapping && l.types[t.elem].kind == Kind::Struct;
        if (v.slot == Word256::of(10)) fixed = t.kind == Kind::Fixed && t.length == std::optional<u64>(4);
    }
    CHECK(array);
    CHECK(mapping);
    CHECK(fixed);
    CHECK(has(a.after[0].trace, V("(st 256 (sl (sv stor0)) 256)")));
    same_runs(a);
}

TEST_CASE("storage: vyper - the slot first in the hashes (voted)") {
    Fixture f;
    std::vector<FunctionInfo> fns{
        fn(0x70a08231, "{(return (sized 32 (storage 256 0 (sha3 (sized 32 3) (sized 32 (mask_shl 160 0 0 (calldataload 4)))))))}"),
        fn(0xa9059cbb, "{(store 256 0 (sha3 (sized 32 3) (sized 32 caller)) (calldataload 36)) (stop)}"),
    };
    const Analysed a = analyse(fns, Lang::Unknown);
    CHECK(a.layout->lang == Lang::Vyper);
    REQUIRE(a.layout->vars.size() == 1);
    CHECK(a.layout->types[a.layout->vars[0].type].kind == Kind::Mapping);
    CHECK(has(a.after[1].trace, V("(st 256 (si (sv stor0) caller) 256)")));
    same_runs(a);
}

TEST_CASE("storage: what no path reads stays raw - and runs the same") {
    Fixture f;
    std::vector<FunctionInfo> fns{
        // a slot read from the storage, a slot of the calldata, runtime offsets
        fn(0x01010101, "{(return (sized 32 (storage 256 0 (storage 256 0 9))))}"),
        fn(0x02020202, "{(store 8 (mask_shl 5 0 3 (calldataload 4)) 12 7) (stop)}"),
        fn(0x03030303, "{(return (sized 32 (storage 8 (mask_shl 5 0 3 (calldataload 4)) 12)))}"),
        fn(0x04040404, "{(return (sized 32 (storage 256 0 (length (loc 13)))))}"),
        fn(0x05050505, "{(store 16 -8 14 0xffff) (stop)}"),
    };
    const Analysed a = analyse(fns);
    for (const FunctionInfo& fi : a.after) {
        INFO(dump(fi.trace));
        CHECK(no_pre_p(fi.trace));
    }
    same_runs(a);
}

TEST_CASE("storage: rewrite_raw - every access as its slot") {
    Fixture f;
    std::vector<FunctionInfo> fns{
        fn(0x313ce567, "{(return (sized 32 (storage 8 0 2)))}"),
        fn(0xa9059cbb, "{(store 256 0 (sha3 (sized 32 caller) (sized 32 3)) (add 1 (storage 256 0 (sha3 (sized 32 caller) (sized 32 3))))) (stop)}"),
        fn(0x01010101, "{(return (sized 32 (storage 256 0 (length (loc 13)))))}"),
        fn(0x02020202, "{(store 8 (mask_shl 5 0 3 (calldataload 4)) 12 7) (stop)}"),
    };
    Analysed a;
    a.before = fns;
    a.after = fns;
    std::vector<FunctionInfo> internals;
    a.layout = storage::rewrite_raw(a.after, internals, Lang::Unknown);
    CHECK(a.layout->vars.empty());
    CHECK(a.layout->lang == Lang::Solidity);
    CHECK(a.after[0].trace == V("{(return (sized 32 (st 8 (sr 2) 256)))}"));
    for (const FunctionInfo& fi : a.after) {
        INFO(dump(fi.trace));
        CHECK(no_pre_p(fi.trace));
    }
    same_runs(a);
}
