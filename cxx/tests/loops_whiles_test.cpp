// Lot 6: make_whiles on hand-made raw traces (LABEL / GOTO, as lot 5's VM
// makes them), each checked by running the trace before and after in lot
// 11's trace machine on random worlds - the same outcome, the same effects -
// and by the shape of the result (exit tests, rotations, while True).
#include <doctest/doctest.h>

#include <optional>
#include <string>
#include <vector>

#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/dump.hpp"
#include "core/errors.hpp"
#include "core/evmint.hpp"
#include "exec/machine.hpp"
#include "loops/loops.hpp"

using namespace pan;
namespace L = pan::loops;

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

// a random world: storage words from the slot, calldata of words (small ones
// often), call answers
struct World final : exec::SimpleHost {
    u64 seed;
    explicit World(u64 s) : seed(s) {
        calldata.resize(4 + 32 * 6);
        for (usize i = 0; i < calldata.size(); ++i) {
            u64 r = mix(seed * 1315423911u + i);
            calldata[i] = (i >= 4 && (i - 4) % 32 < 30 && (seed & 1)) ? 0 : u8(r);
        }
        call_env.caller = Word256::of(0x1234);
        call_env.address = Word256::of(0x5678);
        call_answer = exec::CallResult{(seed % 2) == 0, std::vector<u8>(seed % 5 == 0 ? 0 : 64, u8(seed))};
    }
    Word256 initial(const Word256& slot) override {
        u8 b[32];
        slot.to_be(b);
        u64 h = seed;
        for (u8 x : b) h = mix(h ^ x);
        return Word256::of(h % 16);
    }
};

std::string show(const exec::Outcome& o) {
    std::string s = exec::status_name(o.status);
    s += " data " + std::to_string(o.data.size());
    if (!o.note.empty()) s += " (" + o.note + ")";
    return s;
}

// t and u run the same on n worlds (neither a bug)
bool same_runs(Value t, Value u, int n = 32) {
    FunctionInfo fn;
    fn.kind = FunctionInfo::Kind::Selector;
    exec::Program p;
    exec::Machine m(p);
    for (int s = 0; s < n; ++s) {
        World w1{u64(s)}, w2{u64(s)};
        exec::Outcome a = m.run(w1, fn, t);
        exec::Outcome b = m.run(w2, fn, u);
        if (a.status == exec::Status::Bug || b.status == exec::Status::Bug) {
            MESSAGE("bug: " << show(a) << " / " << show(b));
            return false;
        }
        if (a.status != b.status || a.data != b.data || w1.effects != w2.effects) {
            MESSAGE("world " << s << ": " << show(a) << " vs " << show(b) << " effects " << w1.effects.size()
                             << " vs " << w2.effects.size());
            return false;
        }
    }
    return true;
}

bool has_label_or_goto(Value v) {
    if (!(v.is_expr() || v.is_list())) return false;
    if (v.is(Op::LABEL) || v.is(Op::GOTO)) return true;
    for (Value a : v.children())
        if (has_label_or_goto(a)) return true;
    return false;
}

// make_whiles of the trace, checked by execution; the loops of the trace
// given (ids 1..nloops)
Value whiles(const char* text, const L::WhilesOptions& opts = {}, u32 nloops = 3) {
    Value t = V(text);
    std::vector<LoopInfo> loops;
    for (u32 k = 1; k <= nloops; ++k) loops.push_back({k, 0});
    Value u = L::make_whiles(t, loops, opts);
    CHECK_MESSAGE(same_runs(t, u), dump_trace(t) << "\n->\n" << dump_trace(u));
    CHECK_MESSAGE(!has_label_or_goto(u), dump_trace(u));
    // idempotent
    std::vector<LoopInfo> again;
    CHECK(L::make_whiles(u, again, opts) == u);
    return u;
}

// the first WHILE line of a trace (any depth), NIL when none
Value first_while(Value v) {
    if (!(v.is_expr() || v.is_list())) return Value();
    if (v.is(Op::WHILE, 4)) return v;
    for (Value a : v.children()) {
        Value w = first_while(a);
        if (!w.nil()) return w;
    }
    return Value();
}

bool is_true_cond(Value c) { return c.is(Op::BOOL, 1) && c[0] == Value::small(1); }

}  // namespace

TEST_CASE("loops: a counted loop, its exit test at the head") {
    Fixture f;
    Value u = whiles(
        "{(setvar tmp1 (mask_shl 3 0 0 (calldataload 4)))"
        " (label loopid1 {(setvar loop1 0)})"
        " (if (lt loop1 tmp1) {(setmem (range (add 128 (mul 32 loop1)) 32) loop1) (goto loopid1 {(setvar loop1 (add 1 "
        "loop1))})} {})"
        " (return (mem (range 128 256)))}");
    REQUIRE(u.size() == 3);
    Value w = u[1];
    REQUIRE(w.is(Op::WHILE, 4));
    CHECK(w[0] == V("(lt loop1 tmp1)"));
    CHECK(w[2] == V("loopid1"));
    CHECK(w[1].size() == 2);
    CHECK(w[1][1].is(Op::CONTINUE, 2));
    CHECK(u[2].is(Op::RETURN));
}

TEST_CASE("loops: the exit test in the else branch, a negated condition") {
    Fixture f;
    Value u = whiles(
        "{(label loopid1 {(setvar loop1 (mask_shl 3 0 0 (calldataload 4)))})"
        " (if (iszero loop1) {} {(setmem (range (mul 32 loop1) 32) loop1) (goto loopid1 {(setvar loop1 (add -1 "
        "loop1))})})"
        " (return (mem (range 0 256)))}");
    Value w = first_while(u);
    REQUIRE(!w.nil());
    CHECK(!is_true_cond(w[0]));
}

TEST_CASE("loops: rotation of the lines before the exit test") {
    Fixture f;
    // a read of memory before the test: run before the loop and before each continue
    Value u = whiles(
        "{(setmem (range 64 32) (mask_shl 3 0 0 (calldataload 4)))"
        " (label loopid1 {(setvar loop1 0)})"
        " (setvar tmp2 (mem (range 64 32)))"
        " (if (lt loop1 tmp2) {(setmem (range (add 128 (mul 32 loop1)) 32) (add tmp2 loop1)) (goto loopid1 {(setvar "
        "loop1 (add 1 loop1))})} {})"
        " (return (mem (range 128 256)))}");
    Value w = first_while(u);
    REQUIRE(!w.nil());
    CHECK(!is_true_cond(w[0]));
    CHECK(w[0] == V("(lt loop1 tmp2)"));
    // the setvar before the loop and before the continue
    CHECK(u.size() == 4);
    CHECK(u[1].is(Op::SETVAR, 2));
    REQUIRE(w[1].size() == 3);
    CHECK(w[1][1].is(Op::SETVAR, 2));
    // a check on the way (a revert branch) rotated too
    u = whiles(
        "{(label loopid1 {(setvar loop1 0)})"
        " (if (gt loop1 (calldataload 36)) {(revert None)} {})"
        " (if (lt loop1 5) {(setmem (range (mul 32 loop1) 32) loop1) (goto loopid1 {(setvar loop1 (add 1 loop1))})} {})"
        " (return (mem (range 0 160)))}");
    w = first_while(u);
    REQUIRE(!w.nil());
    CHECK(!is_true_cond(w[0]));
    // the loop variable in the lines rotated: replaced by its start, its next value
    u = whiles(
        "{(label loopid1 {(setvar loop1 3)})"
        " (setmem (range (mul 32 loop1) 32) (calldataload 4))"
        " (if (lt loop1 7) {(goto loopid1 {(setvar loop1 (add 1 loop1))})} {})"
        " (return (mem (range 0 256)))}");
    w = first_while(u);
    REQUIRE(!w.nil());
    CHECK(!is_true_cond(w[0]));
    CHECK(u[0] == V("(setmem (range 96 32) (calldataload 4))"));
}

TEST_CASE("loops: no rotation when it isn't equivalent") {
    Fixture f;
    // the next value reads what the lines before the test write
    Value u = whiles(
        "{(label loopid1 {(setvar loop1 0)})"
        " (setmem (range 64 32) loop1)"
        " (if (lt loop1 5) {(goto loopid1 {(setvar loop1 (add 1 (mem (range 64 32))))})} {})"
        " (return (mem (range 64 32)))}");
    Value w = first_while(u);
    REQUIRE(!w.nil());
    CHECK(is_true_cond(w[0]));
    // the start value reads what the lines before the test set
    u = whiles(
        "{(setvar tmp1 2)"
        " (label loopid1 {(setvar loop1 tmp1)})"
        " (setvar tmp1 (add 1 loop1))"
        " (if (lt loop1 5) {(goto loopid1 {(setvar loop1 tmp1)})} {})"
        " (return (sized 32 tmp1))}");
    w = first_while(u);
    REQUIRE(!w.nil());
    CHECK(is_true_cond(w[0]));
    // a call before the test: copied with its id (python's), its results read after it
    u = whiles(
        "{(label loopid1 {(setvar loop1 0)})"
        " (call 1 (gas 1) (calldataload 4) 0 None None)"
        " (if (lt loop1 (add 2 (call_success 1))) {(goto loopid1 {(setvar loop1 (add 1 loop1))})} {})"
        " (return (sized 32 loop1))}");
    w = first_while(u);
    REQUIRE(!w.nil());
    CHECK(!is_true_cond(w[0]));
    // the next value reads the call's result the copy would run again: not rotated
    u = whiles(
        "{(label loopid1 {(setvar loop1 0)})"
        " (call 1 (gas 1) (calldataload 4) 0 None None)"
        " (if (lt loop1 5) {(goto loopid1 {(setvar loop1 (add 1 (call_success 1) loop1))})} {})"
        " (return (sized 32 loop1))}");
    w = first_while(u);
    REQUIRE(!w.nil());
    CHECK(is_true_cond(w[0]));
    // rotation off
    L::WhilesOptions o;
    o.rotate = false;
    u = whiles(
        "{(label loopid1 {(setvar loop1 0)})"
        " (setvar tmp2 (calldataload 4))"
        " (if (lt loop1 3) {(goto loopid1 {(setvar loop1 (add 1 loop1))})} {})"
        " (return (sized 32 (add tmp2 loop1)))}",
        o);
    w = first_while(u);
    REQUIRE(!w.nil());
    CHECK(is_true_cond(w[0]));
}

TEST_CASE("loops: while True, its exits inside") {
    Fixture f;
    // a return inside, no exit test but that check: `while not check`
    Value u = whiles(
        "{(label loopid1 {(setvar loop1 0)})"
        " (if (eq loop1 (mask_shl 3 0 0 (calldataload 4))) {(return (sized 32 loop1))} {})"
        " (goto loopid1 {(setvar loop1 (add 1 loop1))})}");
    Value w = first_while(u);
    REQUIRE(!w.nil());
    CHECK(!is_true_cond(w[0]));
    // two returns: the first is the exit, the second a check in the body
    u = whiles(
        "{(label loopid1 {(setvar loop1 0)})"
        " (if (eq loop1 (mask_shl 3 0 0 (calldataload 4))) {(return (sized 32 loop1))} {})"
        " (if (eq loop1 (mask_shl 3 0 0 (calldataload 36))) {(return (sized 32 (add 100 loop1)))} {})"
        " (goto loopid1 {(setvar loop1 (add 1 loop1))})}");
    w = first_while(u);
    REQUIRE(!w.nil());
    CHECK(!is_true_cond(w[0]));
    // the plain form: while True
    L::WhilesOptions plain;
    plain.exit_test = false;
    u = whiles(
        "{(label loopid1 {(setvar loop1 0)})"
        " (if (eq loop1 (mask_shl 3 0 0 (calldataload 4))) {(return (sized 32 loop1))} {})"
        " (goto loopid1 {(setvar loop1 (add 1 loop1))})}",
        plain);
    w = first_while(u);
    REQUIRE(!w.nil());
    CHECK(is_true_cond(w[0]));
    // both branches loop back
    u = whiles(
        "{(label loopid1 {(setvar loop1 0)})"
        " (if (lt loop1 4) {(setmem (range 0 32) loop1) (goto loopid1 {(setvar loop1 (add 1 loop1))})} {(if (lt loop1 "
        "9) {(goto loopid1 {(setvar loop1 (add 2 loop1))})} {(return (mem (range 0 32)))})})}");
    w = first_while(u);
    REQUIRE(!w.nil());
    CHECK(is_true_cond(w[0]));
}

TEST_CASE("loops: the exit test the last line, a break falling off the body") {
    Fixture f;
    // the label in a branch: falling off the loop goes on after the outer IF
    Value u = whiles(
        "{(if (calldataload 4)"
        "   {(label loopid1 {(setvar loop1 0)})"
        "    (if (lt loop1 6) {(if (eq loop1 (mask_shl 3 0 0 (calldataload 36))) {} {(goto loopid1 {(setvar loop1 (add "
        "1 loop1))})})} {(setmem (range 0 32) 7)})}"
        "   {})"
        " (return (mem (range 0 32)))}");
    Value w = first_while(u);
    REQUIRE(!w.nil());
    // the exit branch isn't nothing, the body falls off: while True
    CHECK(is_true_cond(w[0]));
    // the exit branch nothing: a while
    u = whiles(
        "{(if (calldataload 4)"
        "   {(label loopid1 {(setvar loop1 0)})"
        "    (if (lt loop1 6) {(if (eq loop1 (mask_shl 3 0 0 (calldataload 36))) {(setmem (range 0 32) loop1)} {(goto "
        "loopid1 {(setvar loop1 (add 1 loop1))})})} {})}"
        "   {})"
        " (return (mem (range 0 32)))}");
    w = first_while(u);
    REQUIRE(!w.nil());
    CHECK(!is_true_cond(w[0]));
    // the body never falls off: the exit branch after the loop
    u = whiles(
        "{(if (calldataload 4)"
        "   {(label loopid1 {(setvar loop1 0)})"
        "    (if (lt loop1 6) {(if (eq loop1 9) {(revert None)} {(goto loopid1 {(setvar loop1 (add 1 loop1))})})} "
        "{(setmem (range 0 32) loop1)})}"
        "   {})"
        " (return (mem (range 0 32)))}");
    w = first_while(u);
    REQUIRE(!w.nil());
    CHECK(!is_true_cond(w[0]));
}

TEST_CASE("loops: the exit's merge variables renamed (python exit_values)") {
    Fixture f;
    Value u = whiles(
        "{(setvar tmp9 (mask_shl 4 0 0 (calldataload 4)))"
        " (label loopid1 {(setvar loop1 0)})"
        " (if (lt loop1 10)"
        "   {(if (eq loop1 tmp9) {(setvar tmp5 (add 100 loop1))} {(goto loopid1 {(setvar loop1 (add 1 loop1))})})}"
        "   {(setvar tmp5 loop1)})"
        " (return (sized 32 tmp5))}");
    Value w = first_while(u);
    REQUIRE(!w.nil());
    CHECK(!is_true_cond(w[0]));
    CHECK(u[u.size() - 1] == V("(return (sized 32 loop1))"));
    // a swap at the break: not renamed (the setvars run one after the other)
    u = whiles(
        "{(label loopid1 {(setvar loop1 0) (setvar loop2 5)})"
        " (if (lt loop1 10)"
        "   {(if (eq loop1 (mask_shl 3 0 0 (calldataload 4))) {(setvar tmp5 loop2) (setvar tmp6 loop1)} {(goto loopid1 "
        "{(setvar loop1 (add 1 loop1)) (setvar loop2 (add 2 loop2))})})}"
        "   {(setvar tmp5 loop1) (setvar tmp6 loop2)})"
        " (return (data (sized 32 tmp5) (sized 32 tmp6)))}");
    w = first_while(u);
    REQUIRE(!w.nil());
    // the exit branch reads a value not a loop variable: kept, while True
    u = whiles(
        "{(label loopid1 {(setvar loop1 0)})"
        " (if (lt loop1 10)"
        "   {(if (eq loop1 (mask_shl 3 0 0 (calldataload 4))) {(setvar tmp5 7)} {(goto loopid1 {(setvar loop1 (add 1 "
        "loop1))})})}"
        "   {(setvar tmp5 (add 1 loop1))})"
        " (return (sized 32 tmp5))}");
    w = first_while(u);
    REQUIRE(!w.nil());
    CHECK(is_true_cond(w[0]));
}

TEST_CASE("loops: nested loops") {
    Fixture f;
    Value u = whiles(
        "{(label loopid1 {(setvar loop1 0)})"
        " (if (lt loop1 3)"
        "   {(label loopid2 {(setvar loop2 0)})"
        "    (if (lt loop2 4)"
        "      {(setmem (range (mul 32 (add loop2 (mul 4 loop1))) 32) (add loop1 loop2)) (goto loopid2 {(setvar loop2 "
        "(add 1 loop2))})}"
        "      {(goto loopid1 {(setvar loop1 (add 1 loop1))})})}"
        "   {})"
        " (return (mem (range 0 384)))}");
    Value w = first_while(u);
    REQUIRE(!w.nil());
    CHECK(!is_true_cond(w[0]));
    Value inner = first_while(w[1]);
    REQUIRE(!inner.nil());
    CHECK(!is_true_cond(inner[0]));
    CHECK(inner[2] == V("loopid2"));
    // a continue of the outer loop from the inner one (a break of two loops)
    u = whiles(
        "{(label loopid1 {(setvar loop1 0)})"
        " (if (lt loop1 3)"
        "   {(label loopid2 {(setvar loop2 0)})"
        "    (if (eq loop2 loop1) {(goto loopid1 {(setvar loop1 (add 1 loop1))})} {})"
        "    (if (lt loop2 4)"
        "      {(setmem (range (mul 32 (add loop2 (mul 4 loop1))) 32) (add 1 loop2)) (goto loopid2 {(setvar loop2 (add 1 "
        "loop2))})}"
        "      {(goto loopid1 {(setvar loop1 (add 1 loop1))})})}"
        "   {})"
        " (return (mem (range 0 384)))}");
    // a loop whose exit test comes after another loop (vyper's tests at the end)
    u = whiles(
        "{(label loopid1 {(setvar loop1 0)})"
        " (label loopid2 {(setvar loop2 0)})"
        " (if (lt loop2 2) {(setmem (range (mul 32 loop2) 32) loop1) (goto loopid2 {(setvar loop2 (add 1 loop2))})} {})"
        " (if (lt loop1 3) {(goto loopid1 {(setvar loop1 (add 1 loop1))})} {})"
        " (return (mem (range 0 64)))}");
}

TEST_CASE("loops: steps that aren't additive, variables of several kinds") {
    Fixture f;
    whiles(
        "{(label loopid1 {(setvar loop1 1) (setvar loop2 0)})"
        " (if (lt loop1 (mask_shl 10 0 0 (calldataload 4))) {(goto loopid1 {(setvar loop1 (mul 2 loop1)) (setvar loop2 "
        "(add loop2 loop1))})} {})"
        " (return (data (sized 32 loop1) (sized 32 loop2)))}");
    // simultaneous setvars: a swap
    whiles(
        "{(label loopid1 {(setvar loop1 1) (setvar loop2 2) (setvar loop3 0)})"
        " (if (lt loop3 5) {(goto loopid1 {(setvar loop1 loop2) (setvar loop2 loop1) (setvar loop3 (add 1 loop3))})} {})"
        " (return (data (sized 32 loop1) (sized 32 loop2)))}");
    // storage in the loop
    whiles(
        "{(label loopid1 {(setvar loop1 0)})"
        " (setvar tmp1 (storage 256 0 loop1))"
        " (if (lt loop1 4) {(store 256 0 (add 1 loop1) (add 1 tmp1)) (goto loopid1 {(setvar loop1 (add 1 loop1))})} "
        "{})"
        " (return (sized 32 (storage 256 0 4)))}");
}

TEST_CASE("loops: a label nothing loops back to, a goto out of its loop") {
    Fixture f;
    Value t = V("{(label loopid1 {(setvar loop1 5)}) (return (sized 32 loop1))}");
    std::vector<LoopInfo> loops{{1, 10}, {2, 20}};
    Value u = L::make_whiles(t, loops);
    CHECK(u == V("{(setvar loop1 5) (return (sized 32 loop1))}"));
    REQUIRE(loops.size() == 1);
    CHECK(loops[0].id == 2);
    CHECK(same_runs(t, u));
    // a goto out of its loop: Unsupported
    std::vector<LoopInfo> none;
    CHECK_THROWS_AS(L::make_whiles(V("{(goto loopid1 {})}"), none), Unsupported);
    CHECK_THROWS_AS(
        L::make_whiles(V("{(if 1 {(label loopid1 {})} {}) (goto loopid1 {})}"), none), Unsupported);
    // nothing to do
    t = V("{(setvar tmp1 1) (return (sized 32 tmp1))}");
    CHECK(L::make_whiles(t, none) == t);
    // the whiles stage: a function whose make_whiles fails gets no trace
    std::vector<FunctionInfo> in(2), out;
    in[0].trace = V("{(goto loopid1 {})}");
    in[1].trace = V("{(label loopid1 {(setvar loop1 0)}) (if (lt loop1 2) {(goto loopid1 {(setvar loop1 (add 1 loop1))})} {}) (stop)}");
    L::whiles_stage(in, out);
    REQUIRE(out.size() == 2);
    CHECK(out[0].trace.nil());
    CHECK(out[0].problem.has_value());
    CHECK(!out[1].trace.nil());
    CHECK(!out[1].problem.has_value());
}

TEST_CASE("loops: the plain form, every loop while True") {
    Fixture f;
    L::WhilesOptions o;
    o.exit_test = false;
    Value u = whiles(
        "{(setvar tmp1 (mask_shl 3 0 0 (calldataload 4)))"
        " (label loopid1 {(setvar loop1 0)})"
        " (if (lt loop1 tmp1) {(setmem (range (add 128 (mul 32 loop1)) 32) loop1) (goto loopid1 {(setvar loop1 (add 1 "
        "loop1))})} {})"
        " (return (mem (range 128 256)))}",
        o);
    Value w = first_while(u);
    REQUIRE(!w.nil());
    CHECK(is_true_cond(w[0]));
}

TEST_CASE("loops: a check as the exit test (its branch ends the run)") {
    Fixture f;
    // the exit's code inlined at the test: a return of what the loop made
    Value u = whiles(
        "{(setvar tmp1 (mask_shl 3 0 0 (calldataload 4)))"
        " (label loopid1 {(setvar loop1 0)})"
        " (if (ge loop1 tmp1) {(setvar tmp2 (mem (range 0 32))) (return (mem (range 0 (add 64 tmp2))))} {})"
        " (setmem (range (add 64 (mul 32 loop1)) 32) (add 7 loop1))"
        " (goto loopid1 {(setvar loop1 (add 1 loop1))})}");
    Value w = first_while(u);
    REQUIRE(!w.nil());
    CHECK(!is_true_cond(w[0]));
    CHECK(w[0] == V("(lt loop1 tmp1)"));
    CHECK(u[u.size() - 1].is(Op::RETURN));
    // with lines before the check (rotated), and a revert check in the body
    u = whiles(
        "{(setmem (range 0 32) (mask_shl 3 0 0 (calldataload 4)))"
        " (label loopid1 {(setvar loop1 0)})"
        " (setvar tmp3 (mem (range 0 32)))"
        " (if (ge loop1 tmp3) {(setvar tmp2 (mem (range 32 32))) (return (data (sized 32 tmp2) (sized 32 loop1)))} {})"
        " (if (eq loop1 (mask_shl 3 0 0 (calldataload 36))) {(revert None)} {})"
        " (setmem (range 32 32) (add loop1 (mem (range 32 32))))"
        " (goto loopid1 {(setvar loop1 (add 1 loop1))})}");
    w = first_while(u);
    REQUIRE(!w.nil());
    CHECK(!is_true_cond(w[0]));
    // a lone revert: a check, not the exit
    u = whiles(
        "{(label loopid1 {(setvar loop1 0)})"
        " (if (ge loop1 (mask_shl 3 0 0 (calldataload 4))) {(revert None)} {})"
        " (if (eq loop1 3) {(return (sized 32 loop1))} {})"
        " (goto loopid1 {(setvar loop1 (add 1 loop1))})}");
    w = first_while(u);
    REQUIRE(!w.nil());
    // (the second check is the exit: it reads the loop's variable and returns)
    CHECK(!is_true_cond(w[0]));
    CHECK(w[0] == V("(iszero (eq loop1 3))"));
    // a check that doesn't read the loop's variables: not the exit
    u = whiles(
        "{(setvar tmp1 (mask_shl 1 0 0 (calldataload 4)))"
        " (label loopid1 {(setvar loop1 0)})"
        " (if tmp1 {(setmem (range 0 32) 5) (return (mem (range 0 32)))} {})"
        " (if (eq loop1 4) {(stop)} {})"
        " (goto loopid1 {(setvar loop1 (add 1 loop1))})}");
    w = first_while(u);
    REQUIRE(!w.nil());
    CHECK(w[0] == V("(iszero (eq loop1 4))"));
    // a body that may fall off (a break): while True
    u = whiles(
        "{(if (calldataload 4)"
        "   {(label loopid1 {(setvar loop1 0)})"
        "    (if (ge loop1 5) {(return (sized 32 loop1))} {})"
        "    (if (mask_shl 1 0 0 loop1) {(if (eq loop1 (mask_shl 2 0 0 (calldataload 36))) {(goto loopid1 {(setvar loop1 "
        "(add 1 loop1))})} {})} {(goto loopid1 {(setvar loop1 (add 1 loop1))})})}"
        "   {})"
        " (return (sized 32 99))}");
    w = first_while(u);
    REQUIRE(!w.nil());
    CHECK(is_true_cond(w[0]));
}

TEST_CASE("loops: Vyper's loops, their counter in memory, tested at the end") {
    Fixture f;
    // (the shape of Curve3pool's donate_admin_fees: no loop variable, the
    // test before the back edge, a STOP when it fails)
    Value u = whiles(
        "{(setmem (range 320 32) (sized 32 0))"
        " (label loopid1 {})"
        " (setvar tmp3 (mem (range 320 32)))"
        " (if (lt tmp3 3)"
        "   {(store 256 0 (add 100 tmp3) (calldataload (add 4 (mul 32 tmp3))))"
        "    (setvar tmp8 (mem (range 320 32)))"
        "    (setmem (range 320 32) (sized 32 (add 1 tmp8)))"
        "    (if (iszero (eq 3 (add 1 tmp8))) {(goto loopid1 {})} {(stop)})}"
        "   {(revert None)})}");
    Value w = first_while(u);
    REQUIRE(!w.nil());
    CHECK(!is_true_cond(w[0]));
    CHECK(u[u.size() - 1].is(Op::STOP));
}
