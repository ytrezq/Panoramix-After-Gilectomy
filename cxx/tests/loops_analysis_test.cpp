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
    // a negated comparison (a pass's form): while not (i >= n)
    check(
        "{(setvar tmp1 (mask_shl 6 0 0 (calldataload 4)))"
        " (while (iszero (ge loop1 tmp1)) {(continue loopid1 {(setvar loop1 (add 1 loop1)) (setvar loop2 (add 5 "
        "loop2))})} loopid1 {(setvar loop1 0) (setvar loop2 3)})"
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
    // a start value read from memory the loop writes: that variable's
    // value after the loop isn't its start's plus the moves (evaluated after)
    ind = check(
        "{(setvar tmp1 (mask_shl 3 0 0 (calldataload 4)))"
        " (setmem (range 0 32) (sized 32 64))"
        " (while (lt loop1 tmp1) {(setmem (range 0 32) (sized 32 loop1)) (continue loopid1 {(setvar loop1 (add 1 "
        "loop1)) (setvar loop2 (add 32 loop2))})} loopid1 {(setvar loop1 0) (setvar loop2 (mem (range 0 32)))})"
        " (return (sized 32 loop1))}",
        false);
    REQUIRE(ind);
    REQUIRE(!ind->endvars.nil());
    CHECK(ind->endvars.size() == 1);
    // degenerate conditions: no induction, no crash
    for (const char* c : {"(iszero loop1)", "(iszero 5)", "(iszero tmp9)", "7", "tmp9", "(bool loop1)", "(iszero (add 1 loop1))",
                          "(lt 3 4)", "(eq loop1 3)", "(slt loop1 3)"}) {
        std::string text = std::string("(while ") + c +
                           " {(continue loopid1 {(setvar loop1 (add 1 loop1))})} loopid1 {(setvar loop1 0)})";
        Value w = V(text);
        auto i2 = L::induction(w);
        (void)i2;
        (void)L::summary(w);
    }
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

namespace {

// the trace of lines with the WHILE w and a return of data
Value make(std::initializer_list<Value> lines) { return mk_trace(lines); }

}  // namespace

TEST_CASE("loops: summary ranges at the loop's bounds, checked by execution") {
    Fixture f;
    // BAYC's copy of a string (name()): the counter 160, 192, ... step 32
    const Value prefix1 = V("(setmem (range 64 32) (sized 32 128))");
    const Value prefix2 = V("(setmem (range 160 128) (calldata_bytes 4 128))");
    const Value bound = V("(setvar tmp1 (mul 32 (mask_shl 2 0 0 (calldataload 4))))");
    const Value w = V(
        "(while (lt loop1 (add 160 tmp1)) {(setmem (range (add 32 loop1) 32) (mem (range loop1 32))) (continue loopid1 "
        "{(setvar loop1 (add 32 loop1))})} loopid1 {(setvar loop1 160)})");
    const Value all = make({prefix1, prefix2, bound, w, V("(stop)")});
    Vars vars(all);
    const L::LoopSummary& s = L::summary(w);
    REQUIRE(s.ind.has_value());
    REQUIRE(!s.ind->trips.nil());
    REQUIRE(!s.mem_writes.nil());
    REQUIRE(s.mem_writes.size() == 1);
    const Value hw = s.mem_writes[0];
    CHECK(hw[0] == V("192"));
    MESSAGE("writes " << dump(s.mem_writes) << " reads " << dump(s.mem_reads));
    // the free memory pointer out of it
    CHECK(L::may_write(w, V("(range 64 32)")) == Tri::False);
    CHECK(L::may_write(w, V("(range 192 32)")) != Tri::False);
    // every word around: what the summary says it doesn't write is as it was
    const Value sent = V("(sized 32 0x5e5e5e)");
    int decided = 0;
    for (int q = 0; q <= 640; q += 16) {
        const Value r = mk(Op::RANGE, Value::small(q), Value::small(32));
        if (L::may_write(w, r) != Tri::False) continue;
        ++decided;
        Value ta = make({prefix1, prefix2, bound, mk(Op::SETMEM, r, sent), w, mk(Op::RETURN, mk(Op::MEM, r))});
        Value tb = make({prefix1, prefix2, bound, mk(Op::SETMEM, r, sent), w, mk(Op::RETURN, sent)});
        CHECK_MESSAGE(same_runs(ta, tb), "q " << q);
    }
    CHECK(decided > 10);
    // what it says it doesn't read changes nothing it does
    const Value out = V("(return (mem (range 192 128)))");
    decided = 0;
    for (int q = 0; q <= 640; q += 16) {
        if (q + 32 > 192 && q < 320) continue;  // (the returned bytes)
        const Value r = mk(Op::RANGE, Value::small(q), Value::small(32));
        if (L::may_read(w, r) != Tri::False) continue;
        ++decided;
        Value ta = make({prefix1, prefix2, bound, w, out});
        Value tb = make({prefix1, prefix2, bound, mk(Op::SETMEM, r, sent), w, out});
        CHECK_MESSAGE(same_runs(ta, tb), "q " << q);
    }
    CHECK(decided > 5);
}

TEST_CASE("loops: summary ranges downwards, and kept per iteration when unproven") {
    Fixture f;
    const Value bound = V("(setvar tmp1 (mask_shl 3 0 0 (calldataload 4)))");
    // downwards: writes at 512 - 32 j
    const Value w = V(
        "(while (gt loop1 0) {(setmem (range (add 480 (mul 32 loop1)) 32) loop1) (continue loopid1 {(setvar loop1 (add -1 "
        "loop1))})} loopid1 {(setvar loop1 tmp1)})");
    const Value all = make({bound, w, V("(stop)")});
    Vars vars(all);
    const L::LoopSummary& s = L::summary(w);
    REQUIRE(!s.mem_writes.nil());
    MESSAGE("writes " << dump(s.mem_writes));
    const Value sent = V("(sized 32 0x77)");
    int decided = 0;
    for (int q = 256; q <= 1024; q += 16) {
        const Value r = mk(Op::RANGE, Value::small(q), Value::small(32));
        if (L::may_write(w, r) != Tri::False) continue;
        ++decided;
        Value ta = make({bound, mk(Op::SETMEM, r, sent), w, mk(Op::RETURN, mk(Op::MEM, r))});
        Value tb = make({bound, mk(Op::SETMEM, r, sent), w, mk(Op::RETURN, sent)});
        CHECK_MESSAGE(same_runs(ta, tb), "q " << q);
    }
    CHECK(decided > 10);
    CHECK(L::may_write(w, V("(range 256 32)")) == Tri::False);
    CHECK(L::may_write(w, V("(range 512 32)")) != Tri::False);
    // a step that isn't additive: the range per iteration, the counter free
    const Value w2 = V(
        "(while (lt loop1 64) {(setmem (range (add 480 loop1) 32) loop1) (continue loopid1 {(setvar loop1 (mul 2 "
        "loop1))})} loopid1 {(setvar loop1 1)})");
    const L::LoopSummary& s2 = L::summary(w2);
    REQUIRE(!s2.mem_writes.nil());
    CHECK(s2.mem_writes[0] == V("(range (add 480 loop1) 32)"));
}

TEST_CASE("loops: summary ranges of an address read from memory the loop doesn't write") {
    Fixture f;
    // words written above the free memory pointer, read in every iteration:
    // one range made of its value at the start (no iteration writes it)
    const Value fill = V("(setmem (range 128 896) (calldata_bytes 4 896))");
    const Value fmp = V("(setmem (range 64 32) (add 128 (mask_shl 3 5 0 (calldataload 4))))");
    const Value w = V(
        "(while (lt loop0 (mask_shl 3 5 0 (calldataload 36))) {(setmem (range (add 96 loop0 (mem (range 64 32))) 32) "
        "(sized 32 7)) (continue loopid1 {(setvar loop0 (add 32 loop0))})} loopid1 {(setvar loop0 0)})");
    const Value all = make({fill, fmp, w, V("(stop)")});
    Vars vars(all);
    const L::LoopSummary& s = L::summary(w);
    REQUIRE(!s.mem_writes.nil());
    REQUIRE(s.mem_writes.size() == 1);
    MESSAGE("writes " << dump(s.mem_writes));
    CHECK(s.mem_writes[0][0] == V("(add 96 (mem (range 64 32)))"));
    CHECK(L::may_write(w, V("(range 64 32)")) == Tri::False);
    // every word it says no iteration writes is as it was (the free memory
    // pointer left at least 0x60: the ranges' assumption for solidity's
    // code - no sentinel over part of it)
    const Value sent = V("(sized 32 0x100)");
    int decided = 0;
    for (int q = 0; q <= 1024; q += 16) {
        if (q + 32 > 64 && q < 96 && q != 64) continue;
        const Value r = mk(Op::RANGE, Value::small(q), Value::small(32));
        if (L::may_write(w, r) != Tri::False) continue;
        ++decided;
        Value ta = make({fill, fmp, mk(Op::SETMEM, r, sent), w, mk(Op::RETURN, mk(Op::MEM, r))});
        Value tb = make({fill, fmp, mk(Op::SETMEM, r, sent), w, mk(Op::RETURN, sent)});
        CHECK_MESSAGE(same_runs(ta, tb), "q " << q);
    }
    CHECK(decided > 5);
    // a write that may reach the word its address reads: per iteration
    const Value w2 = V(
        "(while (lt loop0 (mask_shl 3 5 0 (calldataload 36))) {(setmem (range (add loop0 (mask_shl 6 0 0 (mem (range 64 "
        "32)))) 32) (sized 32 7)) (continue loopid1 {(setvar loop0 (add 32 loop0))})} loopid1 {(setvar loop0 0)})");
    const L::LoopSummary& s2 = L::summary(w2);
    REQUIRE(!s2.mem_writes.nil());
    CHECK(L::may_write(w2, V("(range 64 32)")) != Tri::False);
}
