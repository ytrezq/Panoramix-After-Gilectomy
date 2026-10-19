// The storage forms on concrete values (lot 9: storage::locate, and the
// trace machine's ST / SET / SALL): each form against the raw access it
// stands for (STORAGE / STORE / SBYTES / LENGTH), run by the machine on
// storage worlds - the same return data, the same writes.
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

using Bytes = std::vector<u8>;
using Kind = StorageType::Kind;

// a world whose every slot holds a word of the slot's hash (seeded): the
// same for the same slot, different words for different slots
class HashWorld final : public exec::SimpleHost {
public:
    explicit HashWorld(u64 seed) : seed_(seed) {
        calldata = {0x11, 0x22, 0x33, 0x44};
        for (int i = 0; i < 4; ++i) {
            u8 w[32];
            Word256::of(0x1234567 * u64(i + 1) + seed).to_be(w);
            calldata.insert(calldata.end(), w, w + 32);
        }
        call_env.caller = Word256{{0xaaaabbbbccccddddull + seed, 0x1111, 0x22, 0}};
    }
    Word256 initial(const Word256& slot) override {
        u8 buf[40];
        slot.to_be(buf);
        for (int i = 0; i < 8; ++i) buf[32 + i] = u8(seed_ >> (8 * i));
        const Word256 h = exec::keccak256(std::span<const u8>(buf, 40));
        // small words in odd worlds (lengths, flags)
        return seed_ & 1 ? Word256::of(h.limb[0] & 0xffff) : h;
    }

private:
    u64 seed_;
};

StorageType value(u16 w) {
    StorageType t;
    t.kind = Kind::Value;
    t.width = w;
    return t;
}
StorageType container(Kind k, u32 elem, u64 stride = 1) {
    StorageType t;
    t.kind = k;
    t.elem = elem;
    t.stride = stride;
    return t;
}
StorageType bytes_type() {
    StorageType t;
    t.kind = Kind::Bytes;
    return t;
}
StorageVar var(u64 slot, u16 off, u32 type) {
    StorageVar v;
    v.slot = Word256::of(slot);
    v.off = off;
    v.type = type;
    return v;
}

// types: 0 uint256, 1 mapping of uint256, 2 mapping of mapping, 3 array of
// uint256, 4 uint8, 5 array of uint8 (packed), 6 fixed of 2-slot elements,
// 7 bytes, 8 address, 9 fixed of uint32 (packed)
StorageLayout layout(Lang lang) {
    StorageLayout l;
    l.lang = lang;
    l.types = {value(256),
               container(Kind::Mapping, 0),
               container(Kind::Mapping, 1),
               container(Kind::Array, 0),
               value(8),
               container(Kind::Array, 4),
               container(Kind::Fixed, 0, 2),
               bytes_type(),
               value(160),
               container(Kind::Fixed, 10)};
    l.types.push_back(value(32));  // 10
    l.vars = {var(0, 0, 8), var(0, 160, 4), var(3, 0, 1), var(4, 0, 2), var(5, 0, 3),
              var(6, 0, 5), var(7, 0, 6), var(8, 0, 7), var(9, 0, 9)};
    StorageVar big;
    big.slot = Word256{{0x2076cc3735a920a3ull, 0x8dca3e2076cc3735ull, 0xa3210667c828492dull, 0x360894a13ba1a321ull}};
    big.type = 0;
    l.vars.push_back(big);  // stor9
    return l;
}

struct Run {
    exec::Outcome out;
    std::vector<exec::SimpleHost::Effect> effects;
};

Run run(const StorageLayout* l, std::string_view trace, u64 seed) {
    std::vector<FunctionInfo> fns(1);
    fns[0].kind = FunctionInfo::Kind::Selector;
    fns[0].selector = 0x11223344;
    fns[0].trace = V(trace);
    exec::Program p;
    p.functions = fns;
    p.layout = l;
    exec::Machine m(p);
    HashWorld w(seed);
    Run r;
    r.out = m.run(w, fns[0]);
    r.effects = w.effects;
    return r;
}

// the form and the raw access read the same, in several worlds
void same_read(const StorageLayout& l, std::string_view form, std::string_view raw) {
    for (u64 seed = 0; seed < 4; ++seed) {
        const std::string tf = "{(return (sized 32 " + std::string(form) + "))}";
        const std::string tr = "{(return (sized 32 " + std::string(raw) + "))}";
        const Run a = run(&l, tf, seed), b = run(&l, tr, seed);
        INFO(form, " vs ", raw, " seed ", seed, ": ", a.out.note, " / ", b.out.note);
        REQUIRE(a.out.status == exec::Status::Return);
        REQUIRE(b.out.status == exec::Status::Return);
        CHECK(a.out.data == b.out.data);
    }
}

// the SET and the STORE write the same
void same_write(const StorageLayout& l, std::string_view set, std::string_view store) {
    for (u64 seed = 0; seed < 4; ++seed) {
        const std::string tf = "{" + std::string(set) + " (stop)}";
        const std::string tr = "{" + std::string(store) + " (stop)}";
        const Run a = run(&l, tf, seed), b = run(&l, tr, seed);
        INFO(set, " vs ", store, " seed ", seed, ": ", a.out.note, " / ", b.out.note);
        REQUIRE(a.out.status == exec::Status::Stop);
        REQUIRE(b.out.status == exec::Status::Stop);
        CHECK(a.effects == b.effects);
        CHECK(!a.effects.empty());
    }
}

}  // namespace

TEST_CASE("storage: forms - variables, fields, raw slots") {
    Fixture f;
    const StorageLayout l = layout(Lang::Solidity);
    same_read(l, "(st 160 (sv stor0) 160)", "(storage 160 0 0)");
    same_read(l, "(st 8 (sv stor1) 8)", "(storage 8 160 0)");
    same_read(l, "(st 4 (sv stor1) 8)", "(storage 4 160 0)");  // a cast
    same_read(l, "(st 256 (sv stor9) 256)",
              "(storage 256 0 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc)");
    same_read(l, "(st 256 (sr (add 7 (calldataload 4))) 256)", "(storage 256 0 (add 7 (calldataload 4)))");
    same_read(l, "(st 8 (sf (sr 12) 24) 232)", "(storage 8 24 12)");
    same_read(l, "(st 16 (sf (sv stor3) 520) 248)", "(storage 16 8 6)");  // 520 = 2 * 256 + 8
    same_read(l, "(st 16 (sf (sr 9) -8) 8)", "(storage 16 248 8)");     // floor(-8 / 256) = -1
    same_read(l, "(mask_shl 4 2 -2 (st 8 (sv stor1) 8))", "(storage 4 162 0)");
}

TEST_CASE("storage: forms - mappings (solidity, vyper), arrays, fixed, bytes") {
    Fixture f;
    const StorageLayout l = layout(Lang::Solidity);
    same_read(l, "(st 256 (si (sv stor2) caller) 256)", "(storage 256 0 (sha3 (sized 32 caller) (sized 32 3)))");
    same_read(l, "(st 256 (si (si (sv stor3) caller) (calldataload 4)) 256)",
              "(storage 256 0 (sha3 (sized 32 (calldataload 4)) (sized 32 (sha3 (sized 32 caller) (sized 32 4)))))");
    // a bytes key: its bytes, then the slot
    same_read(l, "(st 256 (si (sv stor2) (data (calldata_bytes 4 7))) 256)",
              "(storage 256 0 (sha3 (calldata_bytes 4 7) (sized 32 3)))");
    // a dynamic array: its length, an element
    same_read(l, "(st 256 (sl (sv stor4)) 256)", "(storage 256 0 5)");
    same_read(l, "(st 256 (si (sv stor4) (calldataload 4)) 256)",
              "(storage 256 0 (add (calldataload 4) (sha3 (sized 32 5))))");
    // packed uint8s: 32 a slot
    same_read(l, "(st 8 (si (sv stor5) (calldataload 4)) 8)",
              "(storage 8 (mask_shl 5 0 3 (calldataload 4)) (add (mask_shl 251 5 -5 (calldataload 4)) (sha3 (sized 32 6))))");
    same_read(l, "(st 8 (si (sv stor5) 37) 8)", "(storage 8 40 (add 1 (sha3 (sized 32 6))))");
    // a fixed array of two-slot elements: element i at 7 + 2 i, its second word
    same_read(l, "(st 256 (sf (si (sv stor6) (calldataload 4)) 256) 256)",
              "(storage 256 0 (add 8 (mul 2 (calldataload 4))))");
    // a fixed array of packed uint32s (8 a slot) at 9
    same_read(l, "(st 32 (si (sv stor8) 11) 32)", "(storage 32 96 10)");
    // a bytes: its word, its length decoded, a word of its data
    same_read(l, "(st 256 (sv stor7) 256)", "(storage 256 0 8)");
    same_read(l, "(st 256 (sbl (sv stor7)) 256)", "(storage 256 0 (length 8))");
    same_read(l, "(st 256 (si (sv stor7) 2) 256)", "(storage 256 0 (add 2 (sha3 (sized 32 8))))");

    const StorageLayout v = layout(Lang::Vyper);
    same_read(v, "(st 256 (si (sv stor2) caller) 256)", "(storage 256 0 (sha3 (sized 32 3) (sized 32 caller)))");
}

TEST_CASE("storage: forms - writes") {
    Fixture f;
    const StorageLayout l = layout(Lang::Solidity);
    same_write(l, "(set (st 160 (sv stor0) 160) caller)", "(store 160 0 0 caller)");
    same_write(l, "(set (st 8 (sv stor1) 8) 0x1ff)", "(store 8 160 0 0x1ff)");
    same_write(l, "(set (st 256 (si (sv stor2) caller) 256) (calldataload 4))",
               "(store 256 0 (sha3 (sized 32 caller) (sized 32 3)) (calldataload 4))");
    same_write(l, "(set (st 8 (si (sv stor5) (calldataload 4)) 8) 7)",
               "(store 8 (mask_shl 5 0 3 (calldataload 4)) (add (mask_shl 251 5 -5 (calldataload 4)) (sha3 (sized 32 6))) 7)");
    same_write(l, "(set (st 256 (sr 77) 256) 5)", "(store 256 0 77 5)");
    same_write(l, "(set (st 8 (sf (sr 77) 248) 8) 0x1234)", "(store 8 248 77 0x1234)");
    same_write(l, "(set (st 16 (sf (sr 77) 248) 8) 0x1234)", "(store 16 248 77 0x1234)");  // past the word: cut
}

TEST_CASE("storage: forms - SALL is the bytes of the storage bytes") {
    Fixture f;
    const StorageLayout l = layout(Lang::Solidity);
    // (the worlds' words at slot 8: short ones and long ones)
    for (u64 seed = 0; seed < 8; ++seed) {
        const Run a = run(&l, "{(return (data (arr (st 256 (sbl (sv stor7)) 256) (sall (sv stor7)))))}", seed);
        const Run b = run(&l, "{(return (data (arr (storage 256 0 (length 8)) (sbytes 8))))}", seed);
        INFO(a.out.note, " / ", b.out.note);
        if (b.out.status == exec::Status::Exhausted) {
            CHECK(a.out.status == exec::Status::Exhausted);  // (a long one of a hash's length)
            continue;
        }
        REQUIRE(b.out.status == exec::Status::Return);
        CHECK(a.out.status == exec::Status::Return);
        CHECK(a.out.data == b.out.data);
    }
}

TEST_CASE("storage: forms - what the layout doesn't have is a bug") {
    Fixture f;
    const StorageLayout l = layout(Lang::Solidity);
    CHECK(run(&l, "{(return (sized 32 (st 256 (sv stor99) 256)))}", 0).out.status == exec::Status::Bug);
    CHECK(run(&l, "{(return (sized 32 (st 256 (si (sv stor0) 1) 256)))}", 0).out.status == exec::Status::Bug);
    CHECK(run(&l, "{(return (sized 32 (st 256 (si (sr 3) 1) 256)))}", 0).out.status == exec::Status::Bug);
    CHECK(run(&l, "{(set (st 256 (sbl (sv stor7)) 256) 1)}", 0).out.status == exec::Status::Bug);
    CHECK(run(&l, "{(return (sized 32 (sv stor0)))}", 0).out.status == exec::Status::Bug);
    CHECK(run(&l, "{(set (sv stor0) 1)}", 0).out.status == exec::Status::Bug);
    // no layout: unsupported (inconclusive)
    CHECK(run(nullptr, "{(return (sized 32 (st 256 (sv stor0) 256)))}", 0).out.status == exec::Status::Unsupported);
}
