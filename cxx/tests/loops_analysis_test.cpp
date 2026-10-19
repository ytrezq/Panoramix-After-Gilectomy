// Lot 6: the loop analyses (induction, summary, may_write / may_read) on
// hand-made WHILE loops. Each proven induction is checked by execution: the
// trace with the loop, and the trace with the loop replaced by its endvars
// (the values after the loop), run the same in lot 11's trace machine on
// random worlds.
#include <doctest/doctest.h>

#include <algorithm>
#include <optional>
#include <utility>
#include <string>
#include <vector>

#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/dump.hpp"
#include "core/errors.hpp"
#include "core/evmint.hpp"
#include "core/order.hpp"
#include "algebra/ranges.hpp"
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

struct World final : exec::SimpleHost {
    u64 seed;
    explicit World(u64 s) : seed(s) {
        calldata.resize(4 + 32 * 6);
        for (usize i = 0; i < calldata.size(); ++i) {
            u64 r = mix(seed * 1315423911u + i);
            calldata[i] = (i >= 4 && (i - 4) % 32 < 30) ? 0 : u8(r);
        }
    }
    Word256 initial(const Word256& slot) override {
        u8 b[32];
        slot.to_be(b);
        u64 h = seed;
        for (u8 x : b) h = mix(h ^ x);
        return Word256::of(h % 64);
    }
};

// the trace's variables installed in the algebra (python set_variables, as
// lot 7's simplify_trace does): every SETVAR's (name, value), setvars too
struct Vars {
    explicit Vars(Value trace) {
        std::vector<std::pair<Value, Value>> pairs;
        std::vector<Value> todo{trace};
        while (!todo.empty()) {
            Value v = todo.back();
            todo.pop_back();
            if (!(v.is_list() || v.is_expr())) continue;
            if (v.is(Op::SETVAR, 2)) {
                std::pair<Value, Value> p{v[0], v[1]};
                if (std::find(pairs.begin(), pairs.end(), p) == pairs.end()) pairs.push_back(p);
                continue;
            }
            if (v.is_expr() && !has(v.op(), LINE)) continue;
            for (Value x : v.children()) todo.push_back(x);
        }
        std::sort(pairs.begin(), pairs.end(), [](const auto& a, const auto& b) {
            int c = compare(a.first, b.first);
            return c != 0 ? c < 0 : compare(a.second, b.second) < 0;
        });
        alg::set_variables(pairs, {});
    }
    ~Vars() { alg::clear_variables(); }
    Vars(const Vars&) = delete;
    Vars& operator=(const Vars&) = delete;
};

std::string show(const exec::Outcome& o) {
    std::string s = exec::status_name(o.status);
    s += " data " + std::to_string(o.data.size());
    if (!o.note.empty()) s += " (" + o.note + ")";
    return s;
}

bool same_runs(Value t, Value u, int n = 48) {
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
            MESSAGE("world " << s << ": " << show(a) << " vs " << show(b));
            return false;
        }
    }
    return true;
}

// the trace's WHILE line (top level)
Value top_while(Value t) {
    for (Value l : t.args())
        if (l.is(Op::WHILE, 4)) return l;
    return Value();
}

// the trace with its WHILE replaced by the endvars (plain SETVARs)
Value with_endvars(Value t, Value endvars) {
    std::vector<Value> lines;
    for (Value l : t.args()) {
        if (l.is(Op::WHILE, 4)) {
            for (Value s : endvars.args()) lines.push_back(s);
            continue;
        }
        lines.push_back(l);
    }
    return mk_trace(std::span<const Value>(lines.data(), lines.size()));
}

// the induction of the trace's loop; its endvars checked by execution
std::optional<L::Induction> check(const char* text, bool expect_endvars = true) {
    Value t = V(text);
    Vars vars(t);
    Value w = top_while(t);
    REQUIRE(!w.nil());
    auto ind = L::induction(w);
    if (ind && !ind->endvars.nil()) {
        Value u = with_endvars(t, ind->endvars);
        CHECK_MESSAGE(same_runs(t, u), dump_trace(t) << "\n->\n" << dump_trace(u));
    }
    if (expect_endvars) CHECK_MESSAGE((ind && !ind->endvars.nil()), dump_trace(t));
    return ind;
}

}  // namespace

TEST_CASE("loops: induction of counted loops, endvars checked by execution") {
    Fixture f;
    // for (i = 0; i < n; i++): n trips, i = n after
    auto ind = check(
        "{(setvar tmp1 (mask_shl 6 0 0 (calldataload 4)))"
        " (while (lt loop1 tmp1) {(setmem (range (mul 32 loop1) 32) loop1) (continue loopid1 {(setvar loop1 (add 1 "
        "loop1))})} loopid1 {(setvar loop1 0)})"
        " (return (sized 32 loop1))}");
    REQUIRE(ind);
    CHECK(ind->var == V("loop1"));
    CHECK(ind->step == V("1"));
    CHECK(ind->cmp == L::Cmp::Lt);
    CHECK(ind->bound == V("tmp1"));
    CHECK(!ind->trips.nil());
    // a start past the bound (0 trips) and a pointer moving with it
    check(
        "{(setvar tmp1 (mask_shl 6 0 0 (calldataload 4)))"
        " (setvar tmp2 (mask_shl 6 0 0 (calldataload 36)))"
        " (while (lt loop1 tmp1) {(continue loopid1 {(setvar loop1 (add 1 loop1)) (setvar loop2 (add 32 loop2))})} "
        "loopid1 {(setvar loop1 tmp2) (setvar loop2 (add 128 tmp2))})"
        " (return (data (sized 32 loop1) (sized 32 loop2)))}");
    // a step of 32 (ceil), the bound on the left
    check(
        "{(setvar tmp1 (mask_shl 10 0 0 (calldataload 4)))"
        " (while (gt tmp1 loop1) {(continue loopid1 {(setvar loop1 (add 32 loop1)) (setvar loop2 (add 1 loop2))})} "
        "loopid1 {(setvar loop1 0) (setvar loop2 0)})"
        " (return (data (sized 32 loop1) (sized 32 loop2)))}");
    // <=
    check(
        "{(setvar tmp1 (mask_shl 6 0 0 (calldataload 4)))"
        " (while (le loop1 tmp1) {(continue loopid1 {(setvar loop1 (add 3 loop1)) (setvar loop2 (add 7 loop2))})} "
        "loopid1 {(setvar loop1 1) (setvar loop2 0)})"
        " (return (data (sized 32 loop1) (sized 32 loop2)))}");
    // down to the bound: > and >=
    check(
        "{(setvar tmp1 (mask_shl 6 0 0 (calldataload 4)))"
        " (while (gt loop1 0) {(continue loopid1 {(setvar loop1 (add -1 loop1)) (setvar loop2 (add 2 loop2))})} "
        "loopid1 {(setvar loop1 tmp1) (setvar loop2 5)})"
        " (return (data (sized 32 loop1) (sized 32 loop2)))}");
    check(
        "{(setvar tmp1 (mask_shl 6 0 0 (calldataload 4)))"
        " (while (ge loop1 3) {(continue loopid1 {(setvar loop1 (add -2 loop1))})} loopid1 {(setvar loop1 tmp1)})"
        " (return (sized 32 loop1))}");
    // != (exact mod 2^256 with a step of 1)
    check(
        "{(setvar tmp1 (mask_shl 6 0 0 (calldataload 4)))"
        " (while (iszero (eq loop1 tmp1)) {(continue loopid1 {(setvar loop1 (add 1 loop1)) (setvar loop2 (add 64 "
        "loop2))})} loopid1 {(setvar loop1 0) (setvar loop2 0)})"
        " (return (data (sized 32 loop1) (sized 32 loop2)))}");
    // the counter as the condition (while i: i -= 1)
    check(
        "{(while loop1 {(continue loopid1 {(setvar loop1 (add -1 loop1)) (setvar loop2 (add 1 loop2))})} loopid1 "
        "{(setvar loop1 (mask_shl 5 0 0 (calldataload 4))) (setvar loop2 0)})"
        " (return (data (sized 32 loop1) (sized 32 loop2)))}");
    // the counter plus an offset in the condition (do-while rotated)
    check(
        "{(setvar tmp1 (mask_shl 6 0 0 (calldataload 4)))"
        " (while (lt (add 1 loop1) tmp1) {(continue loopid1 {(setvar loop1 (add 1 loop1))})} loopid1 {(setvar loop1 "
        "0)})"
        " (return (sized 32 loop1))}");
    // several continues, the same step
    check(
        "{(setvar tmp1 (mask_shl 6 0 0 (calldataload 4)))"
        " (while (lt loop1 tmp1) {(if (mask_shl 1 0 0 loop1) {(continue loopid1 {(setvar loop1 (add 1 loop1))})} "
        "{(continue loopid1 {(setvar loop1 (add 1 loop1))})})} loopid1 {(setvar loop1 0)})"
        " (return (sized 32 loop1))}");
    // a variable moved by an invariant amount (not a constant)
    check(
        "{(setvar tmp1 (mask_shl 6 0 0 (calldataload 4)))"
        " (setvar tmp2 (mask_shl 8 0 0 (calldataload 36)))"
        " (while (lt loop1 tmp1) {(continue loopid1 {(setvar loop1 (add 1 loop1)) (setvar loop2 (add tmp2 "
        "loop2))})} loopid1 {(setvar loop1 0) (setvar loop2 9)})"
        " (return (data (sized 32 loop1) (sized 32 loop2)))}");
}

TEST_CASE("loops: no induction, no endvars") {
    Fixture f;
    // a step that isn't additive
    auto ind = check(
        "{(while (lt loop1 100) {(continue loopid1 {(setvar loop1 (mul 2 loop1))})} loopid1 {(setvar loop1 1)}) "
        "(return (sized 32 loop1))}",
        false);
    CHECK(!ind);
    // steps that differ between continues
    ind = check(
        "{(while (lt loop1 100) {(if (mask_shl 1 0 0 loop1) {(continue loopid1 {(setvar loop1 (add 1 loop1))})} "
        "{(continue loopid1 {(setvar loop1 (add 3 loop1))})})} loopid1 {(setvar loop1 0)}) (return (sized 32 "
        "loop1))}",
        false);
    CHECK(!ind);
    // the bound changed in the loop
    ind = check(
        "{(setvar tmp1 10) (while (lt loop1 tmp1) {(setvar tmp1 (add -1 tmp1)) (continue loopid1 {(setvar loop1 (add 1 "
        "loop1))})} loopid1 {(setvar loop1 0)}) (return (sized 32 loop1))}",
        false);
    CHECK(!ind);
    // the bound in memory the loop writes
    ind = check(
        "{(setmem (range 0 32) 9) (while (lt loop1 (mem (range 0 32))) {(setmem (range 0 32) 3) (continue loopid1 "
        "{(setvar loop1 (add 1 loop1))})} loopid1 {(setvar loop1 0)}) (return (sized 32 loop1))}",
        false);
    CHECK(!ind);
    // the counter set in the body
    ind = check(
        "{(while (lt loop1 9) {(setvar loop1 (add 2 loop1)) (continue loopid1 {(setvar loop1 (add 1 loop1))})} "
        "loopid1 {(setvar loop1 0)}) (return (sized 32 loop1))}",
        false);
    CHECK(!ind);
    // moving away from the bound (wraps): no trips
    ind = check(
        "{(while (lt loop1 100) {(continue loopid1 {(setvar loop1 (add -1 loop1))})} loopid1 {(setvar loop1 0)}) "
        "(return (sized 32 loop1))}",
        false);
    CHECK((!ind || ind->trips.nil()));
    // a step past the top: may wrap
    ind = check(
        "{(while (lt loop1 (calldataload 4)) {(continue loopid1 {(setvar loop1 (add 32 loop1))})} loopid1 {(setvar "
        "loop1 0)}) (return (sized 32 loop1))}",
        false);
    REQUIRE(ind);
    CHECK(ind->trips.nil());
    // a break: trips, no endvars
    ind = check(
        "{(setvar tmp1 (mask_shl 6 0 0 (calldataload 4)))"
        " (while (lt loop1 tmp1) {(if (eq loop1 7) {} {(continue loopid1 {(setvar loop1 (add 1 loop1))})})} loopid1 "
        "{(setvar loop1 0)})"
        " (return (sized 32 loop1))}",
        false);
    REQUIRE(ind);
    CHECK(!ind->trips.nil());
    CHECK(ind->endvars.nil());
}

TEST_CASE("loops: summary") {
    Fixture f;
    Value w = V(
        "(while (lt loop1 tmp1) {(setvar tmp3 (mem (range (mul 32 loop1) 32))) (setmem (range (add 512 (mul 32 loop1)) "
        "32) tmp3) (if (eq tmp3 1) {(stop)} {}) (continue loopid1 {(setvar loop1 (add 1 loop1)) (setvar loop2 (add 1 "
        "loop2))})} loopid1 {(setvar loop1 0) (setvar loop2 0)})");
    const L::LoopSummary& s = L::summary(w);
    CHECK(s.id == V("loopid1"));
    CHECK(s.vars == V("[loop1 loop2]"));
    REQUIRE(!s.written.nil());
    CHECK(s.written.size() == 3);
    CHECK(!s.breaks);
    CHECK(s.continues == 1);
    CHECK(!s.continues_outer);
    CHECK(!s.mem_writes_any);
    REQUIRE(!s.mem_writes.nil());
    CHECK(s.ind.has_value());
    // memoized
    CHECK(&L::summary(w) == &s);
    // what it may write: not the scratch space below 512 (its writes are past 512 for every loop1 with no wrap)
    CHECK(L::may_write(w, V("(range 512 32)")) != Tri::False);
    CHECK(L::may_read(w, V("(range 0 32)")) != Tri::False);
    // a range that reads what the loop changes: undecided
    CHECK(L::may_write(w, V("(range tmp3 32)")) == Tri::None);
    // breaks and outer continues
    Value w2 = V(
        "(while (lt loop1 9) {(if (eq loop1 3) {} {(if (eq loop1 4) {(continue loopid7 {})} {(continue loopid1 "
        "{(setvar loop1 (add 1 loop1))})})})} loopid1 {(setvar loop1 0)})");
    const L::LoopSummary& s2 = L::summary(w2);
    CHECK(s2.breaks);
    CHECK(s2.continues_outer);
    CHECK(s2.continues == 1);
    // a SETMEM with no RANGE-less write: none
    Value w3 = V("(while (lt loop1 9) {(continue loopid1 {(setvar loop1 (add 1 loop1))})} loopid1 {(setvar loop1 0)})");
    CHECK(L::may_write(w3, V("(range 0 32)")) == Tri::False);
    CHECK(L::summary(w3).mem_writes.nil());
}
