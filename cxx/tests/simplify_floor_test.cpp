// The free-memory floors (docs/alloc-floor.md part 1, simplify/floor.hpp):
// the transfer rules on the facts, then the forward memory pass using them,
// each pass checked by running the trace before and after in the trace
// machine on random worlds; and part 3: nothing assumed of mem[64].
#include <doctest/doctest.h>

#include <optional>
#include <string>

#include "algebra/compare.hpp"
#include "algebra/facts.hpp"
#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/dump.hpp"
#include "exec/machine.hpp"
#include "simplify/floor.hpp"
#include "simplify/simplify.hpp"

using namespace pan;
namespace S = pan::simplify;

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

u64 mix(u64 x) {
    x ^= x >> 33;
    x *= 0xff51afd7ed558ccdull;
    x ^= x >> 33;
    x *= 0xc4ceb9fe1a85ec53ull;
    x ^= x >> 33;
    return x;
}

// calldata of random words (small ones often), storage from the slot
struct World final : exec::SimpleHost {
    explicit World(u64 seed) {
        calldata.resize(4 + 32 * 6);
        for (usize i = 0; i < calldata.size(); ++i) {
            const u64 r = mix(seed * 1315423911u + i);
            calldata[i] = (i >= 4 && (i - 4) % 32 < 28 && (seed & 1)) ? 0 : u8(r);
        }
        call_env.caller = Word256::of(0x1234);
        call_env.address = Word256::of(0x5678);
    }
};

bool same_runs(Value t, Value u, int n = 32) {
    FunctionInfo fn;
    fn.kind = FunctionInfo::Kind::Selector;
    exec::Program p;
    exec::Machine m(p);
    for (int s = 0; s < n; ++s) {
        World w1{u64(s)}, w2{u64(s)};
        exec::Outcome a = m.run(w1, fn, t);
        exec::Outcome b = m.run(w2, fn, u);
        if (a.status == exec::Status::Bug || b.status == exec::Status::Bug) return false;
        if (a.status == exec::Status::Exhausted || b.status == exec::Status::Exhausted) continue;
        if (a.status != b.status || a.data != b.data || w1.effects != w2.effects) return false;
    }
    return true;
}

Value check_pass(const char* text, Value (*pass)(Value)) {
    Value t = V(text);
    Value u = pass(t);
    CHECK_MESSAGE(same_runs(t, u), dump_trace(t) << "\n->\n" << dump_trace(u));
    return u;
}

bool has_op(Value v, Op op) {
    if (!(v.is_expr() || v.is_list())) return false;
    if (v.is_expr() && v.op() == op) return true;
    for (Value a : v.args())
        if (has_op(a, op)) return true;
    return false;
}

Value last(Value trace) { return trace[trace.size() - 1]; }

Value whole(Value t) { return S::simplify_trace(t); }

}  // namespace

TEST_CASE("floor: the transfer rules") {
    Fixture fx;
    alg::Facts f;
    // a write of the word gives it its floor: the value written
    f = S::floor_transfer(f, V("(setmem (range 64 32) (sized 32 128))"));
    CHECK(f.floor_of(64) == Value::small(128));
    // a write above it (at mem[64], which is >= 128): the floor stays
    alg::Facts g = S::floor_transfer(f, V("(setmem (range (mem (range 64 32)) 32) 7)"));
    CHECK(g.floor_of(64) == Value::small(128));
    // a write at a place the floor can't place: gone
    g = S::floor_transfer(f, V("(setmem (range (calldataload 4) 32) 7)"));
    CHECK(g.floor_of(64).nil());
    // over the word itself (a part of it): gone
    g = S::floor_transfer(f, V("(setmem (range 80 1) 7)"));
    CHECK(g.floor_of(64).nil());
    // an allocation from the word: the old floor plus the size
    g = S::floor_transfer(f, V("(setmem (range 64 32) (add 96 (mem (range 64 32))))"));
    CHECK(g.floor_of(64) == Value::small(224));
    // a value of the word that isn't an addition to it: nothing known
    g = S::floor_transfer(f, V("(setmem (range 64 32) (and 4095 (mem (range 64 32))))"));
    CHECK(g.floor_of(64).nil());
    // a floor reading a variable set again: gone
    alg::Facts h = S::floor_transfer(alg::Facts{}, V("(setmem (range 64 32) (add 64 tmp1))"));
    CHECK(!h.floor_of(64).nil());
    CHECK(S::floor_transfer(h, V("(setvar tmp1 3)")).floor_of(64).nil());
    // a store, a call: the word stays (no memory written)
    CHECK(S::floor_transfer(f, V("(store 256 0 3 7)")).floor_of(64) == Value::small(128));
}

TEST_CASE("floor: joins and loops") {
    Fixture fx;
    const alg::Facts before = S::floor_transfer(alg::Facts{}, V("(setmem (range 64 32) (add 100 tmp1))"));
    const alg::Facts t = S::floor_transfer(before, V("(setmem (range 64 32) (add 292 tmp1))"));
    const alg::Facts e = S::floor_transfer(before, V("(setmem (range 64 32) (add 320 tmp1))"));
    // the least of the branches' floors, proven at most both
    CHECK(S::floor_join(alg::Facts{}, before, t, e).floor_of(64) == V("(add 292 tmp1)"));
    CHECK(S::floor_join(alg::Facts{}, before, e, t).floor_of(64) == V("(add 292 tmp1)"));
    // a branch without a floor: none after
    CHECK(S::floor_join(alg::Facts{}, before, t, alg::Facts{}).floor_of(64).nil());
    // floors that can't be ordered: the one before, when it is below both
    const alg::Facts e2 = S::floor_transfer(before, V("(setmem (range 64 32) (add 300 tmp2))"));
    CHECK(S::floor_join(alg::Facts{}, before, t, e2).floor_of(64).nil());
    // (before's floor tmp1 + 100 is below t's, not provably below e2's)
    // a loop that writes where the floor places away from the word: kept;
    // one that may write anywhere: gone
    const alg::Facts f128 = S::floor_transfer(alg::Facts{}, V("(setmem (range 64 32) (sized 32 128))"));
    Value keeps = V(
        "(while (lt loop1 4) {(setmem (range (add (mem (range 64 32)) (mul 32 loop1)) 32) loop1) (continue loopid1 "
        "[(setvar loop1 (add 1 loop1))])} loopid1 [(setvar loop1 0)])");
    CHECK(S::floor_loop(f128, keeps).floor_of(64) == Value::small(128));
    Value anywhere = V(
        "(while (lt loop1 4) {(setmem (range (calldataload (mul 32 loop1)) 32) loop1) (continue loopid1 [(setvar "
        "loop1 (add 1 loop1))])} loopid1 [(setvar loop1 0)])");
    CHECK(S::floor_loop(f128, anywhere).floor_of(64).nil());
}

TEST_CASE("floor: a walk through branches doesn't use the facts their lines may make wrong") {
    Fixture fx;
    // tmp1 > 300 before the IF, the word >= 250; the then branch sets tmp1
    // to 0 and the word to tmp1 + 5 = 5, the else branch the word to 260:
    // after the IF, no floor (above 5) holds on both paths - the condition
    // isn't true in the then branch any more
    alg::Facts f = alg::Facts{}.with_cond(V("(lt 300 tmp1)"));
    f = S::floor_transfer(f, V("(setmem (range 64 32) (sized 32 250))"));
    REQUIRE(f.floor_of(64) == Value::small(250));
    const alg::Facts after = S::floor_walk(
        f, V("(if (calldataload 4) {(setvar tmp1 0) (setmem (range 64 32) (add 5 tmp1))} {(setmem (range 64 32) "
             "(sized 32 260))})"));
    CHECK(after.floor_of(64).nil());
    // the facts other than floors come back as they were given (the caller
    // forgets what the IF changes)
    CHECK(after.without_floors() == f.without_floors());
}

TEST_CASE("floor: the comparisons of positions read the word as its floor plus d") {
    Fixture fx;
    const alg::Facts f = alg::Facts{}.with_floor(64, V("(add 292 (and 65535 (calldataload 4)))"));
    // mem[64] >= x + 292 > x + 260
    CHECK(alg::lt(V("(add 260 (and 65535 (calldataload 4)))"), V("(mem (range 64 32))"), alg::Top::Memory, &f) ==
          Tri::True);
    // nothing about words that aren't positions (Top::Word)
    CHECK(alg::lt(V("(add 260 (and 65535 (calldataload 4)))"), V("(mem (range 64 32))"), alg::Top::Word, &f) ==
          Tri::None);
    // nor without the floor
    CHECK(alg::lt(V("(add 260 (and 65535 (calldataload 4)))"), V("(mem (range 64 32))"), alg::Top::Memory, nullptr) ==
          Tri::None);
}

TEST_CASE("floor: forwarding past a write at the free word, through a join") {
    Fixture fx;
    // (OpenZeppelin's TokenTimelock shape: the word set to different values in
    // two branches, then a write where it points; the piece below survives)
    Value u = check_pass(
        "{(setvar tmp1 (and 65535 (calldataload 4))) (setmem (range (add 228 tmp1) 32) 7) "
        "(if (calldataload 36) {(setmem (range 64 32) (add 292 tmp1))} {(setmem (range 64 32) (add 320 tmp1))}) "
        "(setmem (range (mem (range 64 32)) 32) 9) (return (mem (range (add 228 tmp1) 32)))}",
        S::cleanup_mems);
    CHECK(!has_op(last(u), Op::MEM));
    // the word lowered in a branch below the piece: the read stays a read
    u = check_pass(
        "{(setvar tmp1 (and 65535 (calldataload 4))) (setmem (range (add 228 tmp1) 32) 7) "
        "(if (calldataload 36) {(setmem (range 64 32) (add 292 tmp1))} {(setmem (range 64 32) (add 100 tmp1))}) "
        "(setmem (range (mem (range 64 32)) 32) 9) (return (mem (range (add 228 tmp1) 32)))}",
        S::cleanup_mems);
    CHECK(has_op(last(u), Op::MEM));
    // a write at an unknown place between: nothing known of the word after
    u = check_pass(
        "{(setvar tmp1 (and 65535 (calldataload 4))) (setmem (range (add 228 tmp1) 32) 7) "
        "(setmem (range 64 32) (add 292 tmp1)) (setmem (range (calldataload 68) 32) 1) "
        "(setmem (range (mem (range 64 32)) 32) 9) (return (mem (range (add 228 tmp1) 32)))}",
        S::cleanup_mems);
    CHECK(has_op(last(u), Op::MEM));
}

TEST_CASE("floor: nothing assumed of mem[64] (part 3)") {
    Fixture fx;
    // the word set below 0x60: compared as the machine runs it
    Value u = check_pass(
        "{(setmem (range 64 32) (and 255 (calldataload 4))) (if (lt (mem (range 64 32)) 96) {(return (sized 32 1))} "
        "{(return (sized 32 2))})}",
        whole);
    CHECK(has_op(u, Op::IF));
    // never written: the word is what the memory holds (zeroes at a call's start)
    check_pass("{(if (lt (mem (range 64 32)) 96) {(return (sized 32 1))} {(return (sized 32 2))})}", whole);
}
