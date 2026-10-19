// Lot 8: the function traits (src/analysis/traits.hpp) on hand-made traces -
// payable (the callvalue check out of the body or the entry), params
// (inferred, the abi's), cleanup_masks, Name(PARAM, k), read_only, const,
// getter - and every rewrite run by the trace machine against the original
// on concrete calls (same outcome, same effects).
#include <doctest/doctest.h>

#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "analysis/traits.hpp"
#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/contract.hpp"
#include "core/dump.hpp"
#include "core/evmint.hpp"
#include "exec/machine.hpp"
#include "sigdb.hpp"

using namespace pan;

namespace {

struct Fixture {
    Budget budget{Budget::Limits{}};
    std::unique_ptr<Context> ctx;
    std::optional<ContextScope> scope;
    Fixture()
    {
        init();
        budget.attach_thread();
        ctx = Context::create(budget);
        scope.emplace(*ctx);
    }
    ~Fixture()
    {
        scope.reset();
        ctx.reset();
        budget.detach_thread();
    }
};

constexpr u32 SEL = 0x12345678;

FunctionInfo fn_of(std::string_view body, std::string_view entry = "{}", FunctionInfo::Kind kind = FunctionInfo::Kind::Selector)
{
    FunctionInfo f;
    f.kind = kind;
    if (kind == FunctionInfo::Kind::Selector) {
        f.selector = SEL;
        f.entry.selector = SEL;
    }
    f.entry.checks = mk_list({});
    f.entry.entry_lines = V(entry);
    f.trace = V(body);
    return f;
}

FunctionInfo analysed(FunctionInfo f)
{
    ContractShared shared;
    traits::analyse_function(f, shared);
    return f;
}

std::vector<u8> word_bytes(const Word256& w)
{
    std::vector<u8> b(32);
    w.to_be(b.data());
    return b;
}

// a few calls: the selector then words (edge and odd values), with and
// without value, some short
struct Call {
    std::vector<u8> calldata;
    u64 value = 0;
};
std::vector<Call> calls()
{
    std::vector<Call> out;
    const std::vector<Word256> words = {
        Word256::of(0),
        Word256::of(1),
        Word256::of(77),
        Word256{{~u64(0), ~u64(0), ~u64(0), ~u64(0)}},
        Word256{{0x1111, 0x2222, 0x3333, 0x4444}},          // past an address
        Word256{{0x1111222233334444ull, 0x5555, 0x66667777, 0}},  // an address
        Word256{{0, 0, 0, 0x1234000000000000ull}},           // a bytes2
    };
    for (const u64 value : {u64(0), u64(5)}) {
        for (usize i = 0; i < words.size(); ++i) {
            Call c;
            c.value = value;
            c.calldata = {u8(SEL >> 24), u8(SEL >> 16), u8(SEL >> 8), u8(SEL)};
            for (usize k = 0; k < 4; ++k) {
                const auto b = word_bytes(words[(i + k) % words.size()]);
                c.calldata.insert(c.calldata.end(), b.begin(), b.end());
            }
            out.push_back(c);
        }
        Call shortc;
        shortc.value = value;
        shortc.calldata = {u8(SEL >> 24), u8(SEL >> 16), u8(SEL >> 8), u8(SEL), 1, 2};
        out.push_back(shortc);
    }
    return out;
}

exec::Outcome run(const FunctionInfo& f, const Call& c, std::vector<exec::SimpleHost::Effect>& effects)
{
    exec::Program p;
    p.functions = std::span<const FunctionInfo>(&f, 1);
    exec::Machine m(p);
    exec::SimpleHost h;
    h.calldata = c.calldata;
    h.call_env.callvalue = Word256::of(c.value);
    h.call_env.caller = Word256::of(0xca11e7);
    h.call_env.address = Word256::of(0xadd7e55);
    for (u64 s = 0; s < 8; ++s)
        h.storage[Word256::of(s)] = Word256{{s * 0x9e3779b97f4a7c15ull, s, 0, s == 3 ? 1u : 0u}};
    exec::Outcome o = m.call(h);
    effects = h.effects;
    return o;
}

// the analysed function does what the original did, on every call
void same_runs(const FunctionInfo& orig, const FunctionInfo& done)
{
    for (const Call& c : calls()) {
        std::vector<exec::SimpleHost::Effect> e1, e2;
        const exec::Outcome a = run(orig, c, e1);
        const exec::Outcome b = run(done, c, e2);
        INFO("value " << c.value << " calldata " << c.calldata.size() << " bytes: " << exec::status_name(a.status)
                      << " vs " << exec::status_name(b.status) << " " << b.note);
        CHECK(a.status == b.status);
        CHECK(a.data == b.data);
        CHECK(e1 == e2);
        CHECK(a.halted());
    }
}

}  // namespace

TEST_CASE("traits: payable - the callvalue check out of the body")
{
    Fixture fx;
    SUBCASE("revert")
    {
        const FunctionInfo f = fn_of("{(if callvalue {(revert None)} {(return (sized 32 1))})}");
        const FunctionInfo g = analysed(f);
        CHECK(g.entry.nonpayable);
        CHECK_FALSE(g.payable);
        CHECK(g.entry.value_fails == V("(revert None)"));
        CHECK(g.trace == V("{(return (sized 32 1))}"));
        same_runs(f, g);
    }
    SUBCASE("invalid, old compilers")
    {
        const FunctionInfo f = fn_of("{(if callvalue {(invalid 1 77)} {(stop)})}");
        const FunctionInfo g = analysed(f);
        CHECK(g.entry.nonpayable);
        CHECK(g.entry.value_fails == V("(invalid 1 77)"));
        CHECK(g.trace == V("{(stop)}"));
        same_runs(f, g);
    }
    SUBCASE("no value: the branches swapped")
    {
        const FunctionInfo f = fn_of("{(if (iszero callvalue) {(stop)} {(revert None)})}");
        const FunctionInfo g = analysed(f);
        CHECK(g.entry.nonpayable);
        CHECK(g.trace == V("{(stop)}"));
        same_runs(f, g);
    }
    SUBCASE("vyper: the size check stays")
    {
        const FunctionInfo f = fn_of("{(if (or callvalue (lt calldatasize 36)) {(revert None)} {(return (sized 32 2))})}");
        const FunctionInfo g = analysed(f);
        CHECK(g.entry.nonpayable);
        CHECK(g.trace == V("{(if (lt calldatasize 36) {(revert None)} {(return (sized 32 2))})}"));
        same_runs(f, g);
    }
    SUBCASE("after setmems, and an IF's continuation")
    {
        const FunctionInfo f = fn_of("{(setmem (range 64 32) (sized 32 128)) (if callvalue {(revert None)} {}) (return (mem (range 64 32)))}");
        const FunctionInfo g = analysed(f);
        CHECK(g.entry.nonpayable);
        CHECK(g.trace == V("{(setmem (range 64 32) (sized 32 128)) (return (mem (range 64 32)))}"));
        same_runs(f, g);
    }
    SUBCASE("payable")
    {
        const FunctionInfo f = fn_of("{(setmem (range 64 32) (sized 32 callvalue)) (return (mem (range 64 32)))}");
        const FunctionInfo g = analysed(f);
        CHECK_FALSE(g.entry.nonpayable);
        CHECK(g.payable);
        CHECK(g.entry.value_fails.nil());
        CHECK(g.trace == f.trace);
        same_runs(f, g);
    }
    SUBCASE("a check that fails otherwise is no value check")
    {
        const FunctionInfo f = fn_of("{(if callvalue {(setmem (range 0 32) (sized 32 1)) (revert (mem (range 0 32)))} {(stop)})}");
        const FunctionInfo g = analysed(f);
        CHECK_FALSE(g.entry.nonpayable);
        CHECK(g.trace == f.trace);
    }
}

TEST_CASE("traits: payable - the dispatcher's check (solc, no payable function)")
{
    Fixture fx;
    const char* entry =
        "{(setmem (range 64 32) (sized 32 128)) (if (iszero callvalue) {} {(revert None)}) (if (lt calldatasize 4) {(revert None)} {})}";
    SUBCASE("removed, not payable")
    {
        const FunctionInfo f = fn_of("{(return (sized 32 5))}", entry);
        const FunctionInfo g = analysed(f);
        CHECK(g.entry.nonpayable);
        CHECK(g.entry.value_fails == V("(revert None)"));
        CHECK(g.entry.entry_lines ==
              V("{(setmem (range 64 32) (sized 32 128)) (if (lt calldatasize 4) {(revert None)} {})}"));
        CHECK(g.trace == f.trace);
        same_runs(f, g);
    }
    SUBCASE("a body that fails at once the same way: payable, as python's merged branches")
    {
        const FunctionInfo f = fn_of("{(revert None)}", entry, FunctionInfo::Kind::Fallback);
        const FunctionInfo g = analysed(f);
        CHECK_FALSE(g.entry.nonpayable);
        CHECK(g.payable);
        same_runs(f, g);
    }
    SUBCASE("kept when a later check fails another way")
    {
        const char* e2 = "{(if (iszero callvalue) {} {(revert None)}) (if (lt calldatasize 4) {(invalid 1 9)} {})}";
        const FunctionInfo f = fn_of("{(return (sized 32 5))}", e2);
        const FunctionInfo g = analysed(f);
        CHECK_FALSE(g.entry.nonpayable);
        CHECK(g.entry.entry_lines == f.entry.entry_lines);
        same_runs(f, g);
    }
}

TEST_CASE("traits: params inferred from the calldata's uses")
{
    Fixture fx;
    SUBCASE("masks, a bool, a pointer")
    {
        const FunctionInfo f = fn_of(
            "{(if callvalue {(revert None)} {(if (calldataload 68) {(store 256 0 (mask_shl 160 0 0 (calldataload 4)) "
            "(mask_shl 8 0 0 (calldataload 36)))} {(store 256 0 1 (calldataload (add 4 (calldataload 100))))}) (stop)})}");
        const FunctionInfo g = analysed(f);
        REQUIRE(g.params.size() == 4);
        CHECK(g.params[0].calldata_offset == 4);
        CHECK(g.params[0].kind == AbiKind::Address);
        CHECK(g.params[1].calldata_offset == 36);
        CHECK(g.params[1].kind == AbiKind::Uint);
        CHECK(g.params[1].bits == 8);
        CHECK(g.params[2].calldata_offset == 68);
        CHECK(g.params[2].kind == AbiKind::Bool);
        CHECK(g.params[3].calldata_offset == 100);
        CHECK(g.params[3].kind == AbiKind::Array);
        CHECK(g.params[3].dynamic);
        CHECK_FALSE(g.name_known);
        // the reads of the params are their names now
        CHECK(g.trace ==
              V("{(if param2 {(store 256 0 (mask_shl 160 0 0 param0) (mask_shl 8 0 0 param1))} {(store 256 0 1 "
                "(calldataload (add 4 param3)))}) (stop)}"));
        same_runs(f, g);
    }
    SUBCASE("a word read at no place of a param: none at all")
    {
        const FunctionInfo f = fn_of("{(return (sized 32 (add (calldataload 4) (calldataload 7))))}");
        const FunctionInfo g = analysed(f);
        CHECK(g.params.empty());
        CHECK(g.trace == f.trace);
        same_runs(f, g);
    }
    SUBCASE("masked somewhere, used whole elsewhere: a word")
    {
        const FunctionInfo f =
            fn_of("{(store 256 0 0 (mask_shl 160 0 0 (calldataload 4))) (store 256 0 1 (calldataload 4)) (stop)}");
        const FunctionInfo g = analysed(f);
        REQUIRE(g.params.size() == 1);
        CHECK(g.params[0].kind == AbiKind::Word);
        same_runs(f, g);
    }
    SUBCASE("the fallback's too; the selector word isn't one")
    {
        const FunctionInfo f = fn_of("{(store 256 0 (calldataload 0) (calldataload 36)) (stop)}", "{}", FunctionInfo::Kind::Fallback);
        const FunctionInfo g = analysed(f);
        REQUIRE(g.params.size() == 1);
        CHECK(g.params[0].calldata_offset == 36);
        CHECK(g.trace == V("{(store 256 0 (calldataload 0) param0) (stop)}"));
        same_runs(f, g);
    }
}

TEST_CASE("traits: cleanup_masks - a checked param is its clean form")
{
    Fixture fx;
    SUBCASE("solc >= 0.8's validation")
    {
        const FunctionInfo f = fn_of(
            "{(if (iszero (eq (calldataload 4) (mask_shl 160 0 0 (calldataload 4)))) {(revert None)} "
            "{(log2 None 7 (mask_shl 160 0 0 (calldataload 4))) (return (sized 32 (mask_shl 160 0 0 (calldataload 4))))})}");
        const FunctionInfo g = analysed(f);
        REQUIRE(g.params.size() == 1);
        CHECK(g.params[0].kind == AbiKind::Address);
        CHECK(g.trace ==
              V("{(if (iszero (eq param0 (mask_shl 160 0 0 param0))) {(revert None)} {(log2 None 7 param0) (return "
                "(sized 32 param0))})}"));
        same_runs(f, g);
    }
    SUBCASE("the mask forms of the checks; the lines after the IF too")
    {
        const FunctionInfo f = fn_of(
            "{(if (mask_shl 96 160 0 (calldataload 4)) {(revert None)} {}) (if (mask_shl 240 0 0 (calldataload 36)) "
            "{(revert None)} {}) (return (data (sized 32 (mask_shl 160 0 0 (calldataload 4))) (sized 32 (mask_shl 16 240 0 "
            "(calldataload 36)))))}");
        const FunctionInfo g = analysed(f);
        REQUIRE(g.params.size() == 2);
        CHECK(g.params[0].kind == AbiKind::Address);
        CHECK(g.params[1].kind == AbiKind::BytesN);
        CHECK(g.params[1].bits == 16);
        CHECK(g.trace == V("{(if (mask_shl 96 160 0 param0) {(revert None)} {}) (if (mask_shl 240 0 0 param1) {(revert "
                           "None)} {}) (return (data (sized 32 param0) (sized 32 param1)))}"));
        same_runs(f, g);
    }
    SUBCASE("not before the check, nor without one")
    {
        const FunctionInfo f = fn_of(
            "{(store 256 0 0 (mask_shl 160 0 0 (calldataload 4))) (if (iszero (eq (calldataload 4) (mask_shl 160 0 0 "
            "(calldataload 4)))) {(revert None)} {(stop)})}");
        const FunctionInfo g = analysed(f);
        CHECK(g.trace ==
              V("{(store 256 0 0 (mask_shl 160 0 0 param0)) (if (iszero (eq param0 (mask_shl 160 0 0 param0))) {(revert "
                "None)} {(stop)})}"));
        same_runs(f, g);
    }
}

TEST_CASE("traits: read_only, const, getter")
{
    Fixture fx;
    SUBCASE("a getter of a field")
    {
        const FunctionInfo g = analysed(fn_of("{(if callvalue {(revert None)} {(return (sized 32 (storage 160 0 5)))})}"));
        CHECK(g.read_only);
        CHECK(g.getter);
        CHECK_FALSE(g.is_const);
        const auto get = traits::getter_of(g);
        REQUIRE(get);
        CHECK(get->kind == traits::Getter::Kind::Read);
        CHECK(get->read == V("(storage 160 0 5)"));
    }
    SUBCASE("a getter of a mapping, a bool of it, moved left")
    {
        CHECK(analysed(fn_of("{(return (sized 32 (storage 256 0 (sha3 (sized 32 (calldataload 4)) (sized 32 3)))))}")).getter);
        CHECK(analysed(fn_of("{(return (sized 32 (bool (storage 8 0 7))))}")).getter);
        CHECK(analysed(fn_of("{(return (sized 32 (mul 0x100000000000000000000000000000000000000000000000000000000 "
                             "(storage 256 0 9))))}"))
                  .getter);
    }
    SUBCASE("a struct of consecutive words")
    {
        const FunctionInfo g = analysed(fn_of(
            "{(return (data (sized 32 (storage 256 0 (sha3 (sized 32 (calldataload 4)) (sized 32 2)))) (sized 32 (storage 256 0 "
            "(add 1 (sha3 (sized 32 (calldataload 4)) (sized 32 2)))))))}"));
        CHECK(g.getter);
        const auto get = traits::getter_of(g);
        REQUIRE(get);
        CHECK(get->kind == traits::Getter::Kind::Struct);
    }
    SUBCASE("kitties-style")
    {
        const FunctionInfo g = analysed(fn_of(
            "{(return (data (sized 32 (storage 64 0 (sha3 (sized 32 (calldataload 4)) (sized 32 6)))) (sized 32 (storage 32 64 "
            "(sha3 (sized 32 (calldataload 4)) (sized 32 6))))))}"));
        CHECK(g.getter);
        const auto get = traits::getter_of(g);
        REQUIRE(get);
        CHECK(get->kind == traits::Getter::Kind::Kitties);
        CHECK(get->slot == 6);
    }
    SUBCASE("a const")
    {
        const FunctionInfo g = analysed(fn_of("{(if callvalue {(revert None)} {(return (sized 32 18))})}"));
        CHECK(g.is_const);
        CHECK_FALSE(g.getter);
        CHECK(traits::const_of(g) == V("(sized 32 18)"));
        // payable: not a const (sent ether, a const reverts with no data)
        CHECK_FALSE(analysed(fn_of("{(return (sized 32 18))}")).is_const);
        // what it returns varies
        CHECK_FALSE(analysed(fn_of("{(if callvalue {(revert None)} {(return (sized 32 caller))})}")).is_const);
        CHECK(analysed(fn_of("{(if callvalue {(revert None)} {(return (sized 32 address))})}")).is_const);
    }
    SUBCASE("not read only")
    {
        for (const char* t : {"{(store 256 0 1 2) (stop)}", "{(log1 None 5) (stop)}", "{(call 1 gas caller 0 None None) (stop)}",
                              "{(selfdestruct caller)}", "{(tstore 1 2) (stop)}"}) {
            const FunctionInfo g = analysed(fn_of(t));
            CHECK_FALSE(g.read_only);
            CHECK_FALSE(g.getter);
        }
        CHECK(analysed(fn_of("{(setmem (range 0 32) (sized 32 1)) (staticcall 1 gas caller None None) (stop)}")).read_only);
    }
    SUBCASE("two returns: neither")
    {
        const FunctionInfo g =
            analysed(fn_of("{(if (calldataload 4) {(return (sized 32 (storage 256 0 1)))} {(return (sized 32 (storage 256 0 2)))})}"));
        CHECK_FALSE(g.getter);
        CHECK_FALSE(g.is_const);
        std::vector<Value> rets;
        traits::returns_of(g.trace, rets);
        CHECK(rets.size() == 2);
    }
}

TEST_CASE("traits: internal functions are left alone")
{
    Fixture fx;
    FunctionInfo f = fn_of("{(if callvalue {(revert None)} {(leave [])})}", "{}", FunctionInfo::Kind::Internal);
    f.params.resize(1);
    const FunctionInfo g = analysed(f);
    CHECK(g.trace == f.trace);
    CHECK_FALSE(g.entry.nonpayable);
    CHECK(g.params.size() == 1);
}

TEST_CASE("traits: the abi's params (a database when there is one)")
{
    Fixture fx;
    std::unique_ptr<sigdb::Database> db;
    try {
        db = sigdb::Database::open(sigdb::default_path());
    } catch (const sigdb::Error&) {
        return;  // (no database here)
    }
    // transfer(address,uint256)
    const auto e = db->function(0xa9059cbb);
    if (!e || e->trust() != sigdb::Trust::verified)
        return;
    const auto ps = traits::abi_params(*e);
    REQUIRE(ps.size() == 2);
    CHECK(ps[0].calldata_offset == 4);
    CHECK(ps[0].kind == AbiKind::Address);
    CHECK(ps[0].abi_index == 0u);
    CHECK(ps[1].calldata_offset == 36);
    CHECK(ps[1].kind == AbiKind::Uint);
    CHECK(ps[1].bits == 256);
    ContractShared shared;
    shared.db = db.get();
    FunctionInfo f = fn_of("{(store 256 0 (mask_shl 160 0 0 (calldataload 4)) (calldataload 36)) (stop)}");
    f.selector = 0xa9059cbb;
    f.entry.selector = 0xa9059cbb;
    traits::analyse_function(f, shared);
    CHECK(f.name_known);
    CHECK(f.params.size() == 2);
    CHECK(f.trace == V("{(store 256 0 (mask_shl 160 0 0 param0) param1) (stop)}"));
}
