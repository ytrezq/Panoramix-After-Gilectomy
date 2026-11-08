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
#include "mem/memory.hpp"
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
    // a floor reading a variable set again: what it leaves of it (64 + tmp1
    // >= 64, tmp1 a word of an address), or nothing
    alg::Facts h = S::floor_transfer(alg::Facts{}, V("(setmem (range 64 32) (add 64 tmp1))"));
    CHECK(!h.floor_of(64).nil());
    CHECK(S::floor_transfer(h, V("(setvar tmp1 3)")).floor_of(64) == Value::small(64));
    h = S::floor_transfer(alg::Facts{}, V("(setmem (range 64 32) (sized 32 tmp1))"));
    CHECK(S::floor_transfer(h, V("(setvar tmp1 3)")).floor_of(64).nil());
    // a store, a call: the word stays (no memory written)
    CHECK(S::floor_transfer(f, V("(store 256 0 3 7)")).floor_of(64) == Value::small(128));
}

TEST_CASE("floor: a floor that says nothing isn't kept") {
    Fixture fx;
    // 0: any word is at least that (and floored() would read the word as a
    // fresh atom, the conditions about it lost)
    CHECK(S::floor_transfer(alg::Facts{}, V("(setmem (range 64 32) (sized 32 0))")).floor_of(64).nil());
    CHECK(alg::Facts{}.with_floor(V("tmp1"), Value::small(0)).floor_of(V("tmp1")).nil());
    // 2^64: past every address of the memory model (a word of data)
    CHECK(S::floor_transfer(alg::Facts{}, V("(setmem (range 160 32) (sized 32 18446744073709551616))"))
              .floor_of(160)
              .nil());
    // what says something is kept
    CHECK(S::floor_transfer(alg::Facts{}, V("(setmem (range 64 32) (sized 32 128))")).floor_of(64) ==
          Value::small(128));
    CHECK(alg::Facts{}.with_floor(V("tmp1"), Value::small(32)).floor_of(V("tmp1")) == Value::small(32));
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

// ---- the floors of variables, and the walks that read them (the decisions the
// old range mem[64] >= 0x60 made: cleanup_vars, the memory pass both ways,
// cleanup_conds) ------------------------------------------------------------------

namespace {

usize count_op(Value v, Op op) {
    if (!(v.is_expr() || v.is_list())) return 0;
    usize n = v.is_expr() && v.op() == op ? 1 : 0;
    for (Value a : v.args()) n += count_op(a, op);
    return n;
}

bool reads_name(Value v, Value name) {
    if (v == name) return true;
    if (!(v.is_expr() || v.is_list())) return false;
    for (Value a : v.args())
        if (reads_name(a, name)) return true;
    return false;
}

}  // namespace

TEST_CASE("floor: a variable set to a floored word has the word's floor") {
    Fixture fx;
    const Value x = V("tmp1"), y = V("tmp2");
    alg::Facts f = S::floor_transfer(alg::Facts{}, V("(setmem (range 64 32) (sized 32 128))"));
    // the pointer taken before the word moves on: at least the floor
    alg::Facts g = S::floor_transfer(f, V("(setvar tmp1 (mem (range 64 32)))"));
    CHECK(g.floor_of(x) == Value::small(128));
    // what it adds, added; through another variable's floor
    CHECK(S::floor_transfer(f, V("(setvar tmp1 (add 32 (mem (range 64 32))))")).floor_of(x) == Value::small(160));
    CHECK(S::floor_transfer(g, V("(setvar tmp2 (add 64 tmp1))")).floor_of(y) == Value::small(192));
    // not a sum of the word: nothing
    CHECK(S::floor_transfer(f, V("(setvar tmp1 (mul 2 (mem (range 64 32))))")).floor_of(x).nil());
    // the value the word's floor is (as the forward pass resolves the read)
    CHECK(S::floor_transfer(f, V("(setvar tmp1 128)")).floor_of(x) == Value::small(128));
    // set again: gone (and the floors reading it keep what's left of them)
    alg::Facts h = S::floor_transfer(g, V("(setmem (range 64 32) (add 64 tmp1))"));
    REQUIRE(h.floor_of(64) == V("(add 64 tmp1)"));
    h = S::floor_transfer(h, V("(setvar tmp1 (and 127 (calldataload 4)))"));
    CHECK(h.floor_of(x).nil());
    CHECK(h.floor_of(64) == Value::small(64));
    // the word moved on: the variable keeps its floor, the word gets its own
    alg::Facts k = S::floor_transfer(g, V("(setmem (range 64 32) (add 96 (mem (range 64 32))))"));
    CHECK(k.floor_of(x) == Value::small(128));
    CHECK(k.floor_of(64) == Value::small(224));
    // a position made of it is decided with it: tmp1 + 32 >= 160 > 96
    CHECK(alg::lt(V("96"), V("(add 32 tmp1)"), alg::Top::Memory, &k) == Tri::True);
    CHECK(alg::lt(V("96"), V("(add 32 tmp1)"), alg::Top::Memory, nullptr) == Tri::None);
}

TEST_CASE("floor: a write that moves a word another floor places: decided without that floor") {
    Fixture fx;
    // the words at 64 and 96 floored at 128 and 200; an IF that sets the
    // word at 96 to 64 and then writes where it points - over the word at
    // 64: neither floor holds after it (the second write isn't decided with
    // the floor of 96 it changed)
    alg::Facts f = S::floor_transfer(alg::Facts{}, V("(setmem (range 64 32) (sized 32 128))"));
    f = S::floor_transfer(f, V("(setmem (range 96 32) (sized 32 200))"));
    const alg::Facts g = S::floor_transfer(
        f, V("(if (calldataload 4) {(setmem (range 96 32) (sized 32 64)) (setmem (range (mem (range 96 32)) 32) 7)} "
             "{})"));
    CHECK(g.floor_of(96).nil());
    CHECK(g.floor_of(64).nil());
    CHECK(S::floors_through(f, V("(if (calldataload 4) {(setmem (range 96 32) (sized 32 64)) (setmem (range (mem "
                                 "(range 96 32)) 32) 7)} {})"))
              .floor_of(64)
              .nil());
}

TEST_CASE("floor: cleanup_vars keeps the pointer past a write the floors place above the word") {
    Fixture fx;
    // solidity's `return x`: p = mload(0x40); mstore(p, x); return(mload(0x40),
    // p + 32 - mload(0x40)) - after a join that leaves the word unknown but
    // at least 128: the write at p misses the word, p is still mem[64]
    Value u = check_pass(
        "{(setmem (range 64 32) (sized 32 128)) "
        "(if (calldataload 4) {(setmem (range 64 32) (add 128 (and 65504 (calldataload 36))))} {}) "
        "(setvar tmp3 (mem (range 64 32))) (setmem (range tmp3 32) (sized 32 (calldataload 68))) "
        "(setvar tmp4 (mem (range 64 32))) (return (mem (range tmp4 (add 32 tmp3 (mul -1 tmp4)))))}",
        S::cleanup_vars);
    CHECK(!reads_name(last(u), V("tmp3")));
    // (p + 32 - mload(0x40): 32 once simplify_exps folds it)
    CHECK(last(S::simplify_exps(u)) == V("(return (mem (range (mem (range 64 32)) 32)))"));
    // the word lowered in a branch to where the write lands on it: kept
    u = check_pass(
        "{(setmem (range 64 32) (sized 32 128)) "
        "(if (calldataload 4) {(setmem (range 64 32) (sized 32 64))} {}) "
        "(setvar tmp3 (mem (range 64 32))) (setmem (range tmp3 32) (sized 32 (calldataload 68))) "
        "(setvar tmp4 (mem (range 64 32))) (return (mem (range tmp4 (add 32 tmp3 (mul -1 tmp4)))))}",
        S::cleanup_vars);
    CHECK(reads_name(last(u), V("tmp3")));
}

TEST_CASE("floor: the forward memory pass places a write at a pointer taken from the word") {
    Fixture fx;
    // p = mload(0x40); mstore(0x40, p + 64); mstore(p, a); mstore(p + 32, b):
    // the writes at p are at least the word's floor when p was taken, above
    // the word: the word's value stays known
    Value u = check_pass(
        "{(setmem (range 64 32) (add 1504 (and 65504 (calldataload 4)))) (setvar tmp12 (mem (range 64 32))) "
        "(setmem (range 64 32) (add 64 tmp12)) (setmem (range tmp12 32) (sized 32 (calldataload 36))) "
        "(setmem (range (add 32 tmp12) 32) (sized 32 (calldataload 68))) (return (mem (range 64 32)))}",
        S::cleanup_mems);
    CHECK(!has_op(last(u), Op::MEM));
    // the pointer set again below the word: the read stays
    u = check_pass(
        "{(setmem (range 64 32) (add 1504 (and 65504 (calldataload 4)))) (setvar tmp12 (mem (range 64 32))) "
        "(setvar tmp12 (and 127 (calldataload 100))) (setmem (range 64 32) (add 64 (and 65504 (calldataload 4)))) "
        "(setmem (range tmp12 32) (sized 32 (calldataload 36))) (return (mem (range 64 32)))}",
        S::cleanup_mems);
    CHECK(has_op(last(u), Op::MEM));
}

TEST_CASE("floor: the backward memory pass drops what the floors place apart from every read") {
    Fixture fx;
    // after a join the word is unknown but at least 128: the write at it and
    // the write of the scratch word at 0 are read by nothing (the return reads
    // the word, and 32 bytes past where it points)
    Value u = check_pass(
        "{(setmem (range 64 32) (sized 32 128)) "
        "(if (calldataload 4) {(setmem (range 64 32) (add 160 (and 65504 (calldataload 36))))} {}) "
        "(setmem (range 0 32) (sized 32 (calldataload 68))) (setmem (range (mem (range 64 32)) 32) (sized 32 5)) "
        "(return (mem (range (mem (range 64 32)) 64)))}",
        S::cleanup_mems);
    CHECK(count_op(u, Op::SETMEM) == 2);
    // the word lowered to 0 in a branch: the scratch write may be what's read
    u = check_pass(
        "{(setmem (range 64 32) (sized 32 128)) "
        "(if (calldataload 4) {(setmem (range 64 32) (sized 32 0))} {}) "
        "(setmem (range 0 32) (sized 32 (calldataload 68))) (setmem (range (mem (range 64 32)) 32) (sized 32 5)) "
        "(return (mem (range (mem (range 64 32)) 64)))}",
        S::cleanup_mems);
    CHECK(count_op(u, Op::SETMEM) == 4);
}

TEST_CASE("floor: cleanup_conds keeps a condition across a write the floors place apart") {
    Fixture fx;
    // the pointer p >= 128 (taken from the word): a write at 0 doesn't change
    // mem[p], the inner check is the outer one
    Value u = check_pass(
        "{(setmem (range 64 32) (sized 32 128)) (setvar tmp1 (mem (range 64 32))) "
        "(setmem (range tmp1 32) (sized 32 (and 15 (calldataload 4)))) "
        "(if (lt (mem (range tmp1 32)) 10) {(setmem (range 0 32) (sized 32 1)) "
        "(if (lt (mem (range tmp1 32)) 10) {(return (sized 32 1))} {(return (sized 32 2))})} "
        "{(return (sized 32 3))})}",
        S::cleanup_conds);
    CHECK(count_op(u, Op::IF) == 1);
    // the pointer from a word that may be anything: both checks stay
    u = check_pass(
        "{(setvar tmp1 (mem (range 64 32))) (setmem (range tmp1 32) (sized 32 (and 15 (calldataload 4)))) "
        "(if (lt (mem (range tmp1 32)) 10) {(setmem (range 0 32) (sized 32 1)) "
        "(if (lt (mem (range tmp1 32)) 10) {(return (sized 32 1))} {(return (sized 32 2))})} "
        "{(return (sized 32 3))})}",
        S::cleanup_conds);
    CHECK(count_op(u, Op::IF) == 2);
}

TEST_CASE("floor: a loop's iterations that revert don't change what's known at its head") {
    Fixture fx;
    // a check in a loop whose failing branch copies data of any length to
    // memory before reverting with it: that iteration reverts, so the words
    // known before the loop are known at its head and after it
    Value u = check_pass(
        "{(setmem (range 64 32) (sized 32 224)) (setmem (range 128 32) (sized 32 42)) "
        "(while (lt loop1 (and 7 (calldataload 4))) "
        "{(if (lt (calldataload (add 36 (mul 32 loop1))) 1000) "
        "{(setmem (range 0 32) (sized 32 loop1)) (continue loopid1 [(setvar loop1 (add 1 loop1))])} "
        "{(setmem (range 0 (and 255 (calldataload 100))) (calldata_bytes 0 (and 255 (calldataload 100)))) "
        "(revert (mem (range 0 (and 255 (calldataload 100)))))})} "
        "loopid1 [(setvar loop1 0)]) "
        "(return (mem (range 128 32)))}",
        S::cleanup_mems);
    CHECK(!has_op(last(u), Op::MEM));
    // the message written where the word points (an Error(string) at
    // mload(0x40)) - above the word at 128 anyway
    u = check_pass(
        "{(setmem (range 64 32) (sized 32 224)) (setmem (range 128 32) (sized 32 42)) "
        "(while (lt loop1 (and 7 (calldataload 4))) "
        "{(if (lt (calldataload (add 36 (mul 32 loop1))) 1000) "
        "{(setmem (range 0 32) (sized 32 loop1)) (continue loopid1 [(setvar loop1 (add 1 loop1))])} "
        "{(setvar tmp44 (mem (range 64 32))) (setmem (range tmp44 32) (sized 32 0x08c379a0)) "
        "(setmem (range (add 4 tmp44) 32) (sized 32 32)) (revert (mem (range tmp44 36)))})} "
        "loopid1 [(setvar loop1 0)]) "
        "(return (mem (range 128 32)))}",
        S::cleanup_mems);
    CHECK(!has_op(last(u), Op::MEM));
    // the same write on the path that goes on: the word at 128 may be what it hits
    u = check_pass(
        "{(setmem (range 64 32) (sized 32 224)) (setmem (range 128 32) (sized 32 42)) "
        "(while (lt loop1 (and 7 (calldataload 4))) "
        "{(setvar tmp44 (and 255 (calldataload (add 36 (mul 32 loop1))))) (setmem (range tmp44 32) (sized 32 1)) "
        "(continue loopid1 [(setvar loop1 (add 1 loop1))])} "
        "loopid1 [(setvar loop1 0)]) "
        "(return (mem (range 128 32)))}",
        S::cleanup_mems);
    CHECK(has_op(last(u), Op::MEM));
}

TEST_CASE("floor: a loop writing where the word points leaves the words it misses known") {
    Fixture fx;
    // the loop writes at mem[64] + 32 i: what that range reads (the word)
    // isn't changed by the loop - the floors place every write above it -,
    // so the range doesn't go anywhere, and the word at 128 stays
    Value u = check_pass(
        "{(setmem (range 64 32) (sized 32 256)) (setmem (range 128 32) (sized 32 42)) "
        "(while (lt loop1 (and 7 (calldataload 4))) "
        "{(setmem (range (add (mem (range 64 32)) (mul 32 loop1)) 32) (sized 32 loop1)) "
        "(continue loopid1 [(setvar loop1 (add 1 loop1))])} "
        "loopid1 [(setvar loop1 0)]) "
        "(return (mem (range 128 32)))}",
        S::cleanup_mems);
    CHECK(!has_op(last(u), Op::MEM));
    // the word low enough for the writes to reach the word at 128: the read stays
    u = check_pass(
        "{(setmem (range 64 32) (sized 32 96)) (setmem (range 128 32) (sized 32 42)) "
        "(while (lt loop1 (and 7 (calldataload 4))) "
        "{(setmem (range (add (mem (range 64 32)) (mul 32 loop1)) 32) (sized 32 loop1)) "
        "(continue loopid1 [(setvar loop1 (add 1 loop1))])} "
        "loopid1 [(setvar loop1 0)]) "
        "(return (mem (range 128 32)))}",
        S::cleanup_mems);
    CHECK(has_op(last(u), Op::MEM));
}

TEST_CASE("floor: a loop variable that never goes down is at least its start") {
    Fixture fx;
    // loop2 starts at 160 and steps up by 32 to 1024 (not a constant step:
    // no hull of its writes): every write at loop2 is above the word at 64
    Value u = check_pass(
        "{(setmem (range 64 32) (sized 32 128)) "
        "(while (lt loop1 (and 7 (calldataload 4))) "
        "{(setmem (range loop2 32) (sized 32 loop1)) "
        "(continue loopid1 [(setvar loop1 (add 1 loop1)) "
        "(setvar loop2 (add 32 loop2 (and 992 (calldataload (add 36 (mul 32 loop1))))))])} "
        "loopid1 [(setvar loop1 0) (setvar loop2 160)]) "
        "(return (mem (range 64 32)))}",
        S::cleanup_mems);
    CHECK(!has_op(last(u), Op::MEM));
    // a step that may go down (a word of calldata, 2^256 - 32 wraps it to
    // loop2 - 32): the read stays
    u = check_pass(
        "{(setmem (range 64 32) (sized 32 128)) "
        "(while (lt loop1 (and 7 (calldataload 4))) "
        "{(setmem (range loop2 32) (sized 32 loop1)) "
        "(continue loopid1 [(setvar loop1 (add 1 loop1)) "
        "(setvar loop2 (add loop2 (calldataload (add 36 (mul 32 loop1)))))])} "
        "loopid1 [(setvar loop1 0) (setvar loop2 160)]) "
        "(return (mem (range 64 32)))}",
        S::cleanup_mems);
    CHECK(has_op(last(u), Op::MEM));
}

TEST_CASE("floor: a loop that allocates (the word only grows) keeps the word's floor") {
    Fixture fx;
    // abi.decode of an array of bytes: mstore(0x40, add(mload(0x40), s)) in
    // each iteration - the word never goes down, its floor holds after the
    // loop: the pointer taken then is above the scratch word at 0
    Value u = check_pass(
        "{(setmem (range 64 32) (sized 32 128)) "
        "(while (lt loop1 (and 7 (calldataload 4))) "
        "{(setmem (range 64 32) (add 64 (mem (range 64 32)))) (continue loopid1 [(setvar loop1 (add 1 loop1))])} "
        "loopid1 [(setvar loop1 0)]) "
        "(setvar tmp28 (mem (range 64 32))) (setmem (range tmp28 32) (sized 32 (calldataload 36))) "
        "(setmem (range 0 32) (sized 32 7)) (return (mem (range tmp28 32)))}",
        S::cleanup_mems);
    CHECK(!has_op(last(u), Op::MEM));
    // the allocation by a length of calldata the iteration checked first
    // (abi.decode's `require len <= 2^64 - 1`): it never goes down either
    u = check_pass(
        "{(setmem (range 64 32) (sized 32 128)) "
        "(while (lt loop1 (and 7 (calldataload 4))) "
        "{(if (gt (calldataload (add 36 (mul 32 loop1))) 65535) {(revert None)} {}) "
        "(setmem (range 64 32) (add 32 (mem (range 64 32)) (calldataload (add 36 (mul 32 loop1))))) "
        "(continue loopid1 [(setvar loop1 (add 1 loop1))])} "
        "loopid1 [(setvar loop1 0)]) "
        "(setvar tmp28 (mem (range 64 32))) (setmem (range tmp28 32) (sized 32 (calldataload 36))) "
        "(setmem (range 0 32) (sized 32 7)) (return (mem (range tmp28 32)))}",
        S::cleanup_mems);
    CHECK(!has_op(last(u), Op::MEM));
    // a loop that may lower the word (to a word of calldata): the read stays
    u = check_pass(
        "{(setmem (range 64 32) (sized 32 128)) "
        "(while (lt loop1 (and 7 (calldataload 4))) "
        "{(setmem (range 64 32) (and 255 (calldataload (add 68 (mul 32 loop1))))) "
        "(continue loopid1 [(setvar loop1 (add 1 loop1))])} "
        "loopid1 [(setvar loop1 0)]) "
        "(setvar tmp28 (mem (range 64 32))) (setmem (range tmp28 32) (sized 32 (calldataload 36))) "
        "(setmem (range 0 32) (sized 32 7)) (return (mem (range tmp28 32)))}",
        S::cleanup_mems);
    CHECK(has_op(last(u), Op::MEM));
}

TEST_CASE("floor: a write over what a floor reads leaves the rest of it") {
    Fixture fx;
    // mem[64] = 160 + mem[128] (an allocation by a length kept in memory);
    // the length overwritten: the word is still at least 160, a write where
    // it points misses it
    alg::Facts f = S::floor_transfer(alg::Facts{}, V("(setmem (range 64 32) (sized 32 128))"));
    f = S::floor_transfer(f, V("(setmem (range 128 32) (sized 32 (and 65535 (calldataload 4))))"));
    f = S::floor_transfer(f, V("(setmem (range 64 32) (add 160 (mem (range 128 32))))"));
    REQUIRE(f.floor_of(64) == V("(add 160 (mem (range 128 32)))"));
    CHECK(S::floor_transfer(f, V("(setmem (range 128 32) (sized 32 0))")).floor_of(64) == Value::small(160));
    Value u = check_pass(
        "{(setmem (range 64 32) (sized 32 128)) (setmem (range 128 32) (sized 32 (and 65535 (calldataload 4)))) "
        "(setmem (range 64 32) (add 160 (mem (range 128 32)))) (setmem (range 128 32) (sized 32 0)) "
        "(setmem (range (mem (range 64 32)) 32) (sized 32 5)) (return (mem (range (mem (range 64 32)) 32)))}",
        S::cleanup_mems);
    CHECK(!has_op(last(u), Op::MEM));
}


TEST_CASE("floor: a loop's body is walked with its path's conditions") {
    Fixture fx;
    // a pointer stepping up (loop2, from 160) and a length of calldata the
    // iteration checks before writing past it (the padding after a copy):
    // the write misses the word at 64 because of the check - and the offset
    // of that calldata word reads the loop's variable, which the floors
    // read as its floor plus d only where it is a position, not inside the
    // offset the check is about
    Value u = check_pass(
        "{(setmem (range 64 32) (sized 32 128)) "
        "(while (lt loop1 (and 7 (calldataload 4))) "
        "{(if (gt (calldataload loop2) 65535) {(revert None)} {}) "
        "(setmem (range (add 160 (calldataload loop2)) 32) (sized 32 0)) "
        "(continue loopid1 [(setvar loop1 (add 1 loop1)) (setvar loop2 (add 32 loop2))])} "
        "loopid1 [(setvar loop1 0) (setvar loop2 36)]) "
        "(setvar tmp28 (mem (range 64 32))) (setmem (range tmp28 32) (sized 32 (calldataload 36))) "
        "(setmem (range 0 32) (sized 32 7)) (return (mem (range tmp28 32)))}",
        S::cleanup_mems);
    CHECK(!has_op(last(u), Op::MEM));
    // without the check: the write may land anywhere, on the word too
    u = check_pass(
        "{(setmem (range 64 32) (sized 32 128)) "
        "(while (lt loop1 (and 7 (calldataload 4))) "
        "{(setmem (range (add 160 (calldataload loop2)) 32) (sized 32 0)) "
        "(continue loopid1 [(setvar loop1 (add 1 loop1)) (setvar loop2 (add 32 loop2))])} "
        "loopid1 [(setvar loop1 0) (setvar loop2 36)]) "
        "(setvar tmp28 (mem (range 64 32))) (setmem (range tmp28 32) (sized 32 (calldataload 36))) "
        "(setmem (range 0 32) (sized 32 7)) (return (mem (range tmp28 32)))}",
        S::cleanup_mems);
    CHECK(has_op(last(u), Op::MEM));
}

TEST_CASE("floor: what a loop writes through pointers its body takes from the word") {
    Fixture fx;
    // p = mload(0x40); mstore(0x40, p + 64); mstore(p, i) in each iteration:
    // p, set in the body, is at least the word's floor wherever it is used -
    // the loop's writes miss the word at 128, known at its head and after it
    Value u = check_pass(
        "{(setmem (range 64 32) (sized 32 256)) (setmem (range 128 32) (sized 32 42)) "
        "(while (lt loop1 (and 7 (calldataload 4))) "
        "{(setvar tmp22 (mem (range 64 32))) (setmem (range 64 32) (add 64 (mem (range 64 32)))) "
        "(setmem (range tmp22 32) (sized 32 loop1)) (continue loopid1 [(setvar loop1 (add 1 loop1))])} "
        "loopid1 [(setvar loop1 0)]) "
        "(return (mem (range 128 32)))}",
        S::cleanup_mems);
    CHECK(!has_op(last(u), Op::MEM));
    // the word starting below the word at 128: the read stays
    u = check_pass(
        "{(setmem (range 64 32) (sized 32 96)) (setmem (range 128 32) (sized 32 42)) "
        "(while (lt loop1 (and 7 (calldataload 4))) "
        "{(setvar tmp22 (mem (range 64 32))) (setmem (range 64 32) (add 64 (mem (range 64 32)))) "
        "(setmem (range tmp22 32) (sized 32 loop1)) (continue loopid1 [(setvar loop1 (add 1 loop1))])} "
        "loopid1 [(setvar loop1 0)]) "
        "(return (mem (range 128 32)))}",
        S::cleanup_mems);
    CHECK(has_op(last(u), Op::MEM));
}
