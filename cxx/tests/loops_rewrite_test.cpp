// Lot 6: the loop rewrites (loop_to_setmem, propagate_storage_in_loops,
// rename_var) on hand-made WHILE loops, each checked by execution in lot
// 11's trace machine on random worlds; python's dubious copy (source and
// destination overlapping) shown to differ.
#include <doctest/doctest.h>

#include <algorithm>
#include <optional>
#include <utility>
#include <string>
#include <variant>
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
        calldata.resize(4 + 32 * 8);
        for (usize i = 0; i < calldata.size(); ++i) {
            u64 r = mix(seed * 1315423911u + i);
            calldata[i] = (i >= 4 && i < 4 + 32 * 2 && (i - 4) % 32 < 31) ? 0 : u8(r);
        }
    }
    Word256 initial(const Word256& slot) override {
        u8 b[32];
        slot.to_be(b);
        u64 h = seed;
        for (u8 x : b) h = mix(h ^ x);
        Word256 w{};
        w.limb[0] = h;
        return w;
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

// the effects but the storage writes in their order, and the storage at the
// end (as the stage checks compare them: validate/effects.hpp)
bool same_end_storage(World& a, World& b) {
    auto events = [](const World& h) {
        std::vector<exec::SimpleHost::Effect> e;
        for (const auto& x : h.effects)
            if (!std::holds_alternative<exec::SimpleHost::Sstore>(x)) e.push_back(x);
        return e;
    };
    if (events(a) != events(b)) return false;
    for (World* h : {&a, &b})
        for (const auto& [slot, value] : h->storage) {
            (void)value;
            if (a.sload(slot) != b.sload(slot)) return false;
        }
    return true;
}

// t and u run the same in n worlds: their ends, their effects - the storage
// writes in their order, or (any_order) the storage they leave
bool same_runs(Value t, Value u, int n = 48, bool any_order = false) {
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
        const bool effects = any_order ? same_end_storage(w1, w2) : w1.effects == w2.effects;
        if (a.status != b.status || a.data != b.data || !effects) {
            MESSAGE("world " << s << ": " << show(a) << " vs " << show(b) << (effects ? "" : ", other effects"));
            return false;
        }
    }
    return true;
}

Value pass_setmems(Value t) { return L::loops_to_setmems(t); }
Value pass_dubious(Value t) {
    L::RewriteOptions o;
    o.dubious = true;
    return L::loops_to_setmems(t, o);
}
Value pass_storage(Value t) { return L::propagate_storage_in_loops(t); }

// the pass on the trace, checked by execution; whether it changed it
bool check(const char* text, Value (*pass)(Value)) {
    Value t = V(text);
    Vars vars(t);
    Value u = pass(t);
    CHECK_MESSAGE(same_runs(t, u), dump_trace(t) << "\n->\n" << dump_trace(u));
    return u != t;
}

bool has_while(Value v) {
    if (!(v.is_expr() || v.is_list())) return false;
    if (v.is(Op::WHILE)) return true;
    for (Value a : v.children())
        if (has_while(a)) return true;
    return false;
}

bool has_op(Value v, Op op) {
    if (!(v.is_expr() || v.is_list())) return false;
    if (v.is(op)) return true;
    for (Value a : v.children())
        if (has_op(a, op)) return true;
    return false;
}

// the pass made the loop one SETMEM of the storage's words (no WHILE left),
// the same by execution
bool storage_copy(const char* text) {
    Value t = V(text);
    Vars vars(t);
    Value u = pass_setmems(t);
    CHECK_MESSAGE(same_runs(t, u), dump_trace(t) << "\n->\n" << dump_trace(u));
    INFO(dump_trace(u));
    return !has_while(u) && has_op(u, Op::STORAGE_RANGE);
}

}  // namespace

TEST_CASE("loops: loop_to_setmem, zeroes and copies") {
    Fixture f;
    // zeroes, a counter of words
    CHECK(check("{(setvar tmp1 (mask_shl 4 0 0 (calldataload 4)))"
                " (setmem (range 0 512) (calldata_bytes 100 512))"
                " (while (lt loop1 tmp1) {(setmem (range (add 64 (mul 32 loop1)) 32) 0) (continue loopid1 {(setvar loop1 "
                "(add 1 loop1))})} loopid1 {(setvar loop1 0)})"
                " (return (data (mem (range 0 576)) (sized 32 loop1)))}",
                pass_setmems));
    // the address itself the counter, step 32
    CHECK(check("{(setvar tmp1 (mul 32 (mask_shl 4 0 0 (calldataload 4))))"
                " (setmem (range 0 640) (calldata_bytes 100 640))"
                " (while (lt loop1 tmp1) {(setmem (range (add 128 loop1) 32) 0) (continue loopid1 {(setvar loop1 (add 32 "
                "loop1))})} loopid1 {(setvar loop1 0)})"
                " (return (data (mem (range 0 640)) (sized 32 loop1)))}",
                pass_setmems));
    // a copy forward, its source ahead of its destination: rewritten
    CHECK(check("{(setvar tmp1 (mask_shl 4 0 0 (calldataload 4)))"
                " (setmem (range 0 1024) (calldata_bytes 4 1024))"
                " (while (lt loop1 tmp1) {(setmem (range (add 64 (mul 32 loop1)) 32) (mem (range (add 96 (mul 32 loop1)) "
                "32))) (continue loopid1 {(setvar loop1 (add 1 loop1))})} loopid1 {(setvar loop1 0)})"
                " (return (mem (range 0 1024)))}",
                pass_setmems));
    // a copy forward, its source behind (overlapping): kept...
    const char* behind =
        "{(setvar tmp1 (mask_shl 4 0 0 (calldataload 4)))"
        " (setmem (range 0 1024) (calldata_bytes 4 1024))"
        " (while (lt loop1 tmp1) {(setmem (range (add 96 (mul 32 loop1)) 32) (mem (range (add 64 (mul 32 loop1)) "
        "32))) (continue loopid1 {(setvar loop1 (add 1 loop1))})} loopid1 {(setvar loop1 0)})"
        " (return (mem (range 0 1024)))}";
    CHECK(!check(behind, pass_setmems));
    // ... python's rewrite (dubious) changes what it does
    {
        Value t = V(behind);
        Vars vars(t);
        Value u = pass_dubious(t);
        CHECK(u != t);
        CHECK(!same_runs(t, u));
    }
    // apart: rewritten
    CHECK(check("{(setvar tmp1 (mask_shl 3 0 0 (calldataload 4)))"
                " (setmem (range 0 1024) (calldata_bytes 4 1024))"
                " (while (lt loop1 tmp1) {(setmem (range (add 512 (mul 32 loop1)) 32) (mem (range (add 64 (mul 32 loop1)) "
                "32))) (continue loopid1 {(setvar loop1 (add 1 loop1))})} loopid1 {(setvar loop1 0)})"
                " (return (mem (range 0 1024)))}",
                pass_setmems));
    // calldata words
    CHECK(check("{(setvar tmp1 (mask_shl 3 0 0 (calldataload 4)))"
                " (while (lt loop1 tmp1) {(setmem (range (add 64 (mul 32 loop1)) 32) (calldataload (add 36 (mul 32 "
                "loop1)))) (continue loopid1 {(setvar loop1 (add 1 loop1))})} loopid1 {(setvar loop1 0)})"
                " (return (data (mem (range 0 320)) (sized 32 loop1)))}",
                pass_setmems));
    // downwards
    CHECK(check("{(setvar tmp1 (mask_shl 3 0 0 (calldataload 4)))"
                " (setmem (range 0 512) (calldata_bytes 100 512))"
                " (while (gt loop1 0) {(setmem (range (add 32 (mul 32 loop1)) 32) 0) (continue loopid1 {(setvar loop1 (add "
                "-1 loop1))})} loopid1 {(setvar loop1 tmp1)})"
                " (return (data (mem (range 0 512)) (sized 32 loop1)))}",
                pass_setmems));
    // not rewritten: a value that isn't one of them, a width not 32, no trips
    CHECK(!check("{(while (lt loop1 4) {(setmem (range (mul 32 loop1) 32) loop1) (continue loopid1 {(setvar loop1 (add 1 "
                 "loop1))})} loopid1 {(setvar loop1 0)}) (return (mem (range 0 128)))}",
                 pass_setmems));
    CHECK(!check("{(while (lt loop1 4) {(setmem (range (mul 32 loop1) 1) 0) (continue loopid1 {(setvar loop1 (add 1 "
                 "loop1))})} loopid1 {(setvar loop1 0)}) (return (mem (range 0 128)))}",
                 pass_setmems));
    CHECK(!check("{(while (lt loop1 (calldataload 4)) {(setmem (range (mul 32 loop1) 32) 0) (continue loopid1 {(setvar "
                 "loop1 (add 1 (mul 2 loop1)))})} loopid1 {(setvar loop1 0)}) (return (mem (range 0 128)))}",
                 pass_setmems));
    // nested: the inner loop made a SETMEM
    Value t = V("{(setvar tmp1 (mask_shl 2 0 0 (calldataload 4)))"
                " (while (lt loop2 3) {(while (lt loop1 tmp1) {(setmem (range (add (mul 128 loop2) (mul 32 loop1)) 32) 0) "
                "(continue loopid1 {(setvar loop1 (add 1 loop1))})} loopid1 {(setvar loop1 0)}) (continue loopid2 "
                "{(setvar loop2 (add 1 loop2))})} loopid2 {(setvar loop2 0)})"
                " (return (mem (range 0 384)))}");
    Value u;
    {
        Vars vars(t);
        u = pass_setmems(t);
    }
    CHECK(same_runs(t, u));
    CHECK(u != t);
}

TEST_CASE("loops: loop_to_setmem, the storage's words (python's loop_to_setmem_from_storage)") {
    Fixture f;
    // the slots from 5 on, a counter of words: mem[64 len 32 tmp1] =
    // stor[5 len tmp1]
    CHECK(storage_copy("{(setvar tmp1 (mask_shl 3 0 0 (calldataload 4)))"
                       " (setmem (range 0 512) (calldata_bytes 100 512))"
                       " (while (lt loop1 tmp1) {(setmem (range (add 64 (mul 32 loop1)) 32) (storage 256 0 (add 5 "
                       "loop1))) (continue loopid1 {(setvar loop1 (add 1 loop1))})} loopid1 {(setvar loop1 0)})"
                       " (return (data (mem (range 0 512)) (sized 32 loop1)))}"));
    // Vyper's: while i + 1 != n (xor), a slot of a struct in an array
    CHECK(storage_copy("{(setvar tmp1 (add 1 (mask_shl 3 0 0 (calldataload 4))))"
                       " (setvar tmp2 (mul 100 (mask_shl 2 0 0 (calldataload 36))))"
                       " (setmem (range 0 640) (calldata_bytes 100 640))"
                       " (while (xor (add 1 loop1) tmp1) {(setmem (range (add 320 (mul 32 loop1)) 32) (storage 256 0 "
                       "(add (add 5 tmp2) loop1))) (continue loopid1 {(setvar loop1 (add 1 loop1))})} loopid1 "
                       "{(setvar loop1 0)})"
                       " (return (data (mem (range 0 640)) (sized 32 loop1)))}"));
    // downwards: the address and the slot both
    CHECK(storage_copy("{(setvar tmp1 (mask_shl 3 0 0 (calldataload 4)))"
                       " (setmem (range 0 512) (calldata_bytes 100 512))"
                       " (while (gt loop1 0) {(setmem (range (add 32 (mul 32 loop1)) 32) (storage 256 0 (add 7 "
                       "loop1))) (continue loopid1 {(setvar loop1 (add -1 loop1))})} loopid1 {(setvar loop1 tmp1)})"
                       " (return (data (mem (range 0 512)) (sized 32 loop1)))}"));
    // the slot read from memory the loop doesn't write
    CHECK(storage_copy("{(setvar tmp1 (mask_shl 3 0 0 (calldataload 4)))"
                       " (setmem (range 0 32) (calldataload 36))"
                       " (while (lt loop1 tmp1) {(setmem (range (add 64 (mul 32 loop1)) 32) (storage 256 0 (add (mem "
                       "(range 0 32)) loop1))) (continue loopid1 {(setvar loop1 (add 1 loop1))})} loopid1 {(setvar "
                       "loop1 0)})"
                       " (return (mem (range 0 320)))}"));
    // not rewritten: the slot read from memory the loop writes, a slot
    // moving by 2 a word, against the address, a field of the word
    CHECK(!check("{(setvar tmp1 (mask_shl 3 0 0 (calldataload 4)))"
                 " (setmem (range 0 512) (calldata_bytes 100 512))"
                 " (while (lt loop1 tmp1) {(setmem (range (add 64 (mul 32 loop1)) 32) (storage 256 0 (add (mem (range "
                 "96 32)) loop1))) (continue loopid1 {(setvar loop1 (add 1 loop1))})} loopid1 {(setvar loop1 0)})"
                 " (return (mem (range 0 512)))}",
                 pass_setmems));
    CHECK(!check("{(setvar tmp1 (mask_shl 3 0 0 (calldataload 4)))"
                 " (while (lt loop1 tmp1) {(setmem (range (add 64 (mul 32 loop1)) 32) (storage 256 0 (add 5 (mul 2 "
                 "loop1)))) (continue loopid1 {(setvar loop1 (add 1 loop1))})} loopid1 {(setvar loop1 0)})"
                 " (return (mem (range 0 320)))}",
                 pass_setmems));
    CHECK(!check("{(setvar tmp1 (mask_shl 3 0 0 (calldataload 4)))"
                 " (while (lt loop1 tmp1) {(setmem (range (add 64 (mul 32 loop1)) 32) (storage 256 0 (add 9 (mul -1 "
                 "loop1)))) (continue loopid1 {(setvar loop1 (add 1 loop1))})} loopid1 {(setvar loop1 0)})"
                 " (return (mem (range 0 320)))}",
                 pass_setmems));
    CHECK(!check("{(setvar tmp1 (mask_shl 3 0 0 (calldataload 4)))"
                 " (while (lt loop1 tmp1) {(setmem (range (add 64 (mul 32 loop1)) 32) (storage 160 0 (add 5 "
                 "loop1))) (continue loopid1 {(setvar loop1 (add 1 loop1))})} loopid1 {(setvar loop1 0)})"
                 " (return (mem (range 0 320)))}",
                 pass_setmems));
}

TEST_CASE("loops: the copy loops of the storage, one STORE_RANGE (to_store)") {
    Fixture f;
    // (a loop downwards writes its slots from the last: the storage it
    // leaves the same, as the stage checks compare it)
    auto stored = [](const char* text) {
        Value t = V(text);
        Vars vars(t);
        Value u = pass_setmems(t);
        CHECK_MESSAGE(same_runs(t, u, 48, true), dump_trace(t) << "\n->\n" << dump_trace(u));
        INFO(dump_trace(u));
        return !has_while(u) && has_op(u, Op::STORE_RANGE);
    };
    // memory to the slots from 5 on, a counter of words (the storage read
    // back after it: the slots it wrote, the ones around)
    CHECK(stored("{(setvar tmp1 (mask_shl 3 0 0 (calldataload 4)))"
                 " (setmem (range 0 512) (calldata_bytes 100 512))"
                 " (while (lt loop1 tmp1) {(store 256 0 (add 5 loop1) (mem (range (add 64 (mul 32 loop1)) 32))) "
                 "(continue loopid1 {(setvar loop1 (add 1 loop1))})} loopid1 {(setvar loop1 0)})"
                 " (return (data (storage_range 4 10) (sized 32 loop1)))}"));
    // Vyper's: while i + 1 != n (xor), a string's words after its length
    CHECK(stored("{(setvar tmp1 (add 1 (mask_shl 3 0 0 (calldataload 4))))"
                 " (setvar tmp2 (mul 8 (mask_shl 2 0 0 (calldataload 36))))"
                 " (setmem (range 0 640) (calldata_bytes 100 640))"
                 " (while (xor (add 1 loop1) tmp1) {(store 256 0 (add (add 6 tmp2) loop1) (mem (range (add 96 (mul "
                 "32 loop1)) 32))) (continue loopid1 {(setvar loop1 (add 1 loop1))})} loopid1 {(setvar loop1 0)})"
                 " (return (data (storage_range 5 40) (sized 32 loop1)))}"));
    // downwards
    CHECK(stored("{(setvar tmp1 (mask_shl 3 0 0 (calldataload 4)))"
                 " (setmem (range 0 512) (calldata_bytes 100 512))"
                 " (while (gt loop1 0) {(store 256 0 (add 7 loop1) (mem (range (add 32 (mul 32 loop1)) 32))) "
                 "(continue loopid1 {(setvar loop1 (add -1 loop1))})} loopid1 {(setvar loop1 tmp1)})"
                 " (return (data (storage_range 6 10) (sized 32 loop1)))}"));
    // the calldata, solc's two counters (the slot's, the address's bounded)
    CHECK(stored("{(setvar tmp1 (add 36 (mul 32 (mask_shl 3 0 0 (calldataload 4)))))"
                 " (while (lt loop2 tmp1) {(store 256 0 (add 9 loop1) (calldataload loop2)) (continue loopid1 "
                 "{(setvar loop1 (add 1 loop1)) (setvar loop2 (add 32 loop2))})} loopid1 {(setvar loop1 0) (setvar "
                 "loop2 36)})"
                 " (return (data (storage_range 8 10) (sized 32 loop1) (sized 32 loop2)))}"));
    // zeroes (an old string's tail cleared)
    CHECK(stored("{(setvar tmp1 (mask_shl 3 0 0 (calldataload 4)))"
                 " (while (lt loop1 tmp1) {(store 256 0 (add 1000 loop1) 0) (continue loopid1 {(setvar loop1 (add 1 "
                 "loop1))})} loopid1 {(setvar loop1 0)})"
                 " (return (data (storage_range 999 10) (sized 32 loop1)))}"));
    // the storage: its source ahead of its destination
    CHECK(stored("{(setvar tmp1 (mask_shl 3 0 0 (calldataload 4)))"
                 " (while (lt loop1 tmp1) {(store 256 0 (add 5 loop1) (storage 256 0 (add 8 loop1))) (continue "
                 "loopid1 {(setvar loop1 (add 1 loop1))})} loopid1 {(setvar loop1 0)})"
                 " (return (data (storage_range 4 14) (sized 32 loop1)))}"));
    // ... an element of 8 slots moved within an array of them, 3 words at
    // most (Vyper's struct moved to another index - or the same)
    CHECK(stored("{(setvar tmp1 (mask_shl 2 0 0 (calldataload 4)))"
                 " (while (lt loop1 tmp1) {(store 256 0 (add 6 (mul 8 (mask_shl 2 0 0 (calldataload 36))) loop1) "
                 "(storage 256 0 (add 6 (mul 8 (mask_shl 2 0 0 (calldataload 68))) loop1))) (continue loopid1 "
                 "{(setvar loop1 (add 1 loop1))})} loopid1 {(setvar loop1 0)})"
                 " (return (data (storage_range 5 32) (sized 32 loop1)))}"));
    // kept: the source behind its destination (each iteration may read what
    // an earlier one wrote), a slot read from the storage, a field
    CHECK(!check("{(setvar tmp1 (mask_shl 3 0 0 (calldataload 4)))"
                 " (while (lt loop1 tmp1) {(store 256 0 (add 8 loop1) (storage 256 0 (add 5 loop1))) (continue "
                 "loopid1 {(setvar loop1 (add 1 loop1))})} loopid1 {(setvar loop1 0)})"
                 " (return (data (storage_range 4 14) (sized 32 loop1)))}",
                 pass_setmems));
    CHECK(!check("{(setvar tmp1 (mask_shl 3 0 0 (calldataload 4)))"
                 " (setmem (range 0 512) (calldata_bytes 100 512))"
                 " (while (lt loop1 tmp1) {(store 256 0 (add (storage 256 0 3) loop1) (mem (range (add 64 (mul 32 "
                 "loop1)) 32))) (continue loopid1 {(setvar loop1 (add 1 loop1))})} loopid1 {(setvar loop1 0)})"
                 " (return (data (storage_range 0 8) (sized 32 loop1)))}",
                 pass_setmems));
    CHECK(!check("{(setvar tmp1 (mask_shl 3 0 0 (calldataload 4)))"
                 " (setmem (range 0 512) (calldata_bytes 100 512))"
                 " (while (lt loop1 tmp1) {(store 160 0 (add 5 loop1) (mem (range (add 64 (mul 32 loop1)) 32))) "
                 "(continue loopid1 {(setvar loop1 (add 1 loop1))})} loopid1 {(setvar loop1 0)})"
                 " (return (data (storage_range 4 10) (sized 32 loop1)))}",
                 pass_setmems));
}

TEST_CASE("loops: loop_to_setmem, what the path knows and the variables' last values") {
    Fixture f;
    // solc <= 0.5's word loop: a length counted down while >= 32, read from
    // memory the copy overwrites (the variables' last values set first)
    const char* down =
        "{(setmem (range 0 1024) (calldata_bytes 4 1024))"
        " (setmem (range 512 32) (calldataload 36))"
        " (while (ge loop0 32) {(setmem (range loop2 32) (mem (range loop1 32))) (continue loopid1 {(setvar loop1 (add "
        "32 loop1)) (setvar loop2 (add 32 loop2)) (setvar loop0 (add -32 loop0))})} loopid1 {(setvar loop1 64) (setvar "
        "loop2 480) (setvar loop0 (mask_shl 8 0 0 (mem (range 512 32))))})"
        " (return (data (mem (range 0 1024)) (sized 32 loop0) (sized 32 loop1) (sized 32 loop2)))}";
    CHECK(check(down, pass_setmems));
    {
        Value t = V(down);
        Vars vars(t);
        CHECK(!has_while(pass_setmems(t)));
    }
    // a copy to ceil32(len) + 32 past its source, len checked below 2^32
    // first: apart (the trip count's wrap proven by the check). (The length
    // read where it's used: the ranges don't carry a fact on a variable to
    // its value.)
    const std::string y = "(mask_shl 251 5 0 (add 31 (calldataload 4)))";
    const std::string apart = "{(if (gt (calldataload 4) 4294967296) {(revert None)} {})"
                              " (setmem (range 0 1024) (calldata_bytes 4 1024))"
                              " (while (lt loop1 (calldataload 4)) {(setmem (range (add 160 " +
                              y +
                              " loop1) 32) (mem (range (add 128 loop1) 32))) (continue loopid1 {(setvar loop1 (add 32 "
                              "loop1))})} loopid1 {(setvar loop1 0)})"
                              " (return (data (mem (range 0 1024)) (sized 32 loop1)))}";
    CHECK(check(apart.c_str(), pass_setmems));
    {
        Value t = V(apart.c_str());
        Vars vars(t);
        CHECK(!has_while(pass_setmems(t)));
    }
    // ... not without the check (calldata: its length may be any word)
    const std::string unchecked = "{(setmem (range 0 1024) (calldata_bytes 4 1024))"
                                  " (while (lt loop1 (calldataload 4)) {(setmem (range (add 160 " +
                                  y +
                                  " loop1) 32) (mem (range (add 128 loop1) 32))) (continue loopid1 {(setvar loop1 (add "
                                  "32 loop1))})} loopid1 {(setvar loop1 0)})"
                                  " (return (data (mem (range 0 1024)) (sized 32 loop1)))}";
    CHECK(!check(unchecked.c_str(), pass_setmems));
}

TEST_CASE("loops: loop_to_setmem, addresses read from memory the loop doesn't write") {
    Fixture f;
    // zeroes at the free memory pointer (read in every iteration: the loop
    // never writes it, its range over all iterations above it)
    const char* zeroes =
        "{(setmem (range 128 896) (calldata_bytes 4 896))"
        " (setmem (range 64 32) (add 128 (mask_shl 3 5 0 (calldataload 4))))"
        " (while (lt loop0 (mask_shl 3 5 0 (calldataload 36))) {(setmem (range (add 96 loop0 (mem (range 64 32))) 32) 0) "
        "(continue loopid1 {(setvar loop0 (add 32 loop0))})} loopid1 {(setvar loop0 0)})"
        " (return (data (mem (range 0 1024)) (sized 32 loop0)))}";
    CHECK(check(zeroes, pass_setmems));
    {
        Value t = V(zeroes);
        Vars vars(t);
        CHECK(!has_while(pass_setmems(t)));
    }
    // a copy there from ahead of it
    const char* ahead =
        "{(setmem (range 128 896) (calldata_bytes 4 896))"
        " (setmem (range 64 32) (add 128 (mask_shl 3 5 0 (calldataload 4))))"
        " (while (lt loop0 (mask_shl 3 5 0 (calldataload 36))) {(setmem (range (add 96 loop0 (mem (range 64 32))) 32) "
        "(mem (range (add 160 loop0 (mem (range 64 32))) 32))) (continue loopid1 {(setvar loop0 (add 32 loop0))})} loopid1 "
        "{(setvar loop0 0)})"
        " (return (data (mem (range 0 1024)) (sized 32 loop0)))}";
    CHECK(check(ahead, pass_setmems));
    {
        Value t = V(ahead);
        Vars vars(t);
        CHECK(!has_while(pass_setmems(t)));
    }
    // ... from behind, overlapping: kept
    CHECK(!check("{(setmem (range 128 896) (calldata_bytes 4 896))"
                 " (setmem (range 64 32) (add 128 (mask_shl 3 5 0 (calldataload 4))))"
                 " (while (lt loop0 (mask_shl 3 5 0 (calldataload 36))) {(setmem (range (add 160 loop0 (mem (range 64 32))) "
                 "32) (mem (range (add 96 loop0 (mem (range 64 32))) 32))) (continue loopid1 {(setvar loop0 (add 32 loop0))})} "
                 "loopid1 {(setvar loop0 0)})"
                 " (return (data (mem (range 0 1024)) (sized 32 loop0)))}",
                 pass_setmems));
    // a bound read from memory the loop doesn't write
    const char* bound =
        "{(setmem (range 0 1024) (calldata_bytes 4 1024))"
        " (while (lt loop0 (mask_shl 8 0 0 (mem (range 128 32)))) {(setmem (range (add 512 loop0) 32) 0) (continue loopid1 "
        "{(setvar loop0 (add 32 loop0))})} loopid1 {(setvar loop0 0)})"
        " (return (data (mem (range 0 1024)) (sized 32 loop0)))}";
    CHECK(check(bound, pass_setmems));
    {
        Value t = V(bound);
        Vars vars(t);
        CHECK(!has_while(pass_setmems(t)));
    }
    // ... one it may write: kept
    CHECK(!check("{(setmem (range 0 1024) (calldata_bytes 4 1024))"
                 " (while (lt loop0 (mask_shl 8 0 0 (mem (range 128 32)))) {(setmem (range (add 96 loop0) 32) 0) (continue "
                 "loopid1 {(setvar loop0 (add 32 loop0))})} loopid1 {(setvar loop0 0)})"
                 " (return (data (mem (range 0 1024)) (sized 32 loop0)))}",
                 pass_setmems));
    // a write that may reach the word the address reads: kept
    CHECK(!check("{(setmem (range 0 1024) (calldata_bytes 4 1024))"
                 " (while (lt loop0 (mask_shl 3 5 0 (calldataload 36))) {(setmem (range (add loop0 (mask_shl 6 0 0 (mem (range "
                 "64 32)))) 32) 0) (continue loopid1 {(setvar loop0 (add 32 loop0))})} loopid1 {(setvar loop0 0)})"
                 " (return (data (mem (range 0 1024)) (sized 32 loop0)))}",
                 pass_setmems));
}

TEST_CASE("loops: loop_to_setmem, a SIZED word, a SETVAR of the value read nowhere") {
    Fixture f;
    // (sized 32 0): zeroes
    const char* sized =
        "{(setmem (range 0 1024) (calldata_bytes 4 1024))"
        " (while (lt loop1 (mask_shl 3 0 0 (calldataload 4))) {(setmem (range (add 64 (mul 32 loop1)) 32) (sized 32 0)) "
        "(continue loopid1 {(setvar loop1 (add 1 loop1))})} loopid1 {(setvar loop1 0)})"
        " (return (data (mem (range 0 1024)) (sized 32 loop1)))}";
    CHECK(check(sized, pass_setmems));
    {
        Value t = V(sized);
        Vars vars(t);
        CHECK(!has_while(pass_setmems(t)));
    }
    // a copy whose word is also set to a variable the function never reads
    // (lot 7 keeps such a SETVAR where msize is read): dropped
    const char* dead =
        "{(setmem (range 0 1024) (calldata_bytes 4 1024))"
        " (while (lt loop1 (mask_shl 3 0 0 (calldataload 4))) {(setvar tmp9 (mem (range (add 96 (mul 32 loop1)) 32))) "
        "(setmem (range (add 64 (mul 32 loop1)) 32) (mem (range (add 96 (mul 32 loop1)) 32))) (continue loopid1 {(setvar "
        "loop1 (add 1 loop1))})} loopid1 {(setvar loop1 0)})"
        " (return (data (mem (range 0 1024)) (sized 32 loop1) (sized 32 msize)))}";
    CHECK(check(dead, pass_setmems));
    {
        Value t = V(dead);
        Vars vars(t);
        CHECK(!has_while(pass_setmems(t)));
    }
    // ... read after the loop: kept
    CHECK(!check("{(setmem (range 0 1024) (calldata_bytes 4 1024)) (setvar tmp9 5)"
                 " (while (lt loop1 (mask_shl 3 0 0 (calldataload 4))) {(setvar tmp9 (mem (range (add 96 (mul 32 loop1)) "
                 "32))) (setmem (range (add 64 (mul 32 loop1)) 32) (mem (range (add 96 (mul 32 loop1)) 32))) (continue "
                 "loopid1 {(setvar loop1 (add 1 loop1))})} loopid1 {(setvar loop1 0)})"
                 " (return (data (mem (range 0 1024)) (sized 32 loop1) (sized 32 tmp9)))}",
                 pass_setmems));
}

TEST_CASE("loops: a loop that runs once or never") {
    Fixture f;
    // once: its body, then its CONTINUE's values (set in an order that sets
    // them all at once: loop1 reads loop0's value before the iteration)
    const char* once =
        "{(setmem (range 0 1024) (calldata_bytes 4 1024))"
        " (while (lt loop0 20) {(setmem (range (add 670 loop0) 32) (add loop1 (mem (range (add 582 loop0) 32)))) "
        "(continue loopid1 {(setvar loop0 (add 32 loop0)) (setvar loop1 (add 7 loop0))})} loopid1 {(setvar loop0 0) "
        "(setvar loop1 (calldataload 36))})"
        " (return (data (mem (range 0 1024)) (sized 32 loop0) (sized 32 loop1)))}";
    CHECK(check(once, pass_setmems));
    {
        Value t = V(once);
        Vars vars(t);
        CHECK(!has_while(pass_setmems(t)));
    }
    // never: its start values
    const char* never =
        "{(while (lt loop0 20) {(setmem (range loop0 32) 1) (continue loopid1 {(setvar loop0 (add 32 loop0))})} "
        "loopid1 {(setvar loop0 50)})"
        " (return (data (mem (range 0 128)) (sized 32 loop0)))}";
    CHECK(check(never, pass_setmems));
    {
        Value t = V(never);
        Vars vars(t);
        CHECK(!has_while(pass_setmems(t)));
    }
    // twice: kept
    CHECK(!check("{(while (lt loop0 40) {(setmem (range loop0 32) (add 1 loop0)) (continue loopid1 {(setvar loop0 (add "
                 "32 loop0))})} loopid1 {(setvar loop0 0)})"
                 " (return (data (mem (range 0 128)) (sized 32 loop0)))}",
                 pass_setmems));
    // a start value reading a variable of the loop: kept
    CHECK(!check("{(setvar loop0 9) (setvar loop1 5) (while (lt loop0 20) {(setmem (range loop0 32) loop1) (continue loopid1 {(setvar "
                 "loop0 (add 32 loop0))})} loopid1 {(setvar loop0 0) (setvar loop1 (add 1 loop0))})"
                 " (return (data (mem (range 0 128)) (sized 32 loop0) (sized 32 loop1)))}",
                 pass_setmems));
    // the CONTINUE's values a cycle (a swap): kept
    CHECK(!check("{(while (lt loop0 20) {(setmem (range 0 32) loop1) (continue loopid1 {(setvar loop0 (add 32 loop0)) "
                 "(setvar loop1 loop2) (setvar loop2 loop1)})} loopid1 {(setvar loop0 0) (setvar loop1 3) (setvar loop2 "
                 "4)})"
                 " (return (data (mem (range 0 32)) (sized 32 loop1) (sized 32 loop2)))}",
                 pass_setmems));
}

TEST_CASE("loops: propagate_storage_in_loops") {
    Fixture f;
    // a storage array read from its start: the variable moved, read as itself + sha3
    const char* arr =
        "{(setvar tmp1 (mask_shl 3 0 0 (calldataload 4)))"
        " (while (lt loop2 tmp1) {(setmem (range (add 64 (mul 32 loop2)) 32) (storage 256 0 loop1)) (continue loopid1 "
        "{(setvar loop1 (add 1 loop1)) (setvar loop2 (add 1 loop2))})} loopid1 {(setvar loop1 (sha3 (sized 32 5))) "
        "(setvar loop2 0)})"
        " (return (data (mem (range 64 256)) (sized 32 loop1)))}";
    CHECK(check(arr, pass_storage));
    {
        Value t = V(arr);
        Vars vars(t);
        Value u = pass_storage(t);
        Value w = u[1];
        REQUIRE(w.is(Op::WHILE, 4));
        CHECK(w[3][0] == V("(setvar loop1 0)"));
    }
    // a step that isn't additive: still exact
    CHECK(check("{(setvar tmp1 (mask_shl 3 0 0 (calldataload 4)))"
                " (while (lt loop2 tmp1) {(setmem (range (add 64 (mul 32 loop2)) 32) (storage 256 0 loop1)) (continue "
                "loopid1 {(setvar loop1 (mul 3 loop1)) (setvar loop2 (add 1 loop2))})} loopid1 {(setvar loop1 (add 2 "
                "(sha3 (sized 32 5)))) (setvar loop2 0)})"
                " (return (data (mem (range 64 256)) (sized 32 loop1)))}",
                pass_storage));
    // another variable's step reading it
    CHECK(check("{(setvar tmp1 (mask_shl 3 0 0 (calldataload 4)))"
                " (while (lt loop2 tmp1) {(store 256 0 loop1 loop2) (continue loopid1 {(setvar loop1 (add 1 loop1)) "
                "(setvar loop2 (add 1 loop2)) (setvar loop3 loop1)})} loopid1 {(setvar loop1 (sha3 (sized 32 7))) (setvar "
                "loop2 0) (setvar loop3 0)})"
                " (return (data (sized 32 loop1) (sized 32 loop3)))}",
                pass_storage));
    // a sha3 the loop changes: kept
    CHECK(!check("{(setmem (range 0 32) 5)"
                 " (while (lt loop2 3) {(setmem (range 0 32) loop2) (continue loopid1 {(setvar loop1 (add 1 loop1)) "
                 "(setvar loop2 (add 1 loop2))})} loopid1 {(setvar loop1 (sha3 (mem (range 0 32)))) (setvar loop2 0)})"
                 " (return (sized 32 loop1))}",
                 pass_storage));
}

TEST_CASE("loops: rename_var") {
    Fixture f;
    Value t = V("{(setvar loop5 1) (while (lt loop5 3) {(continue loopid1 {(setvar loop5 (add 1 loop5))})} loopid1 "
                "{(setvar loop5 0)}) (return (sized 32 loop5))}");
    Value u = L::rename_var(t, V("loop5"), V("loop0"));
    CHECK(u == V("{(setvar loop0 1) (while (lt loop0 3) {(continue loopid1 {(setvar loop0 (add 1 loop0))})} loopid1 "
                 "{(setvar loop0 0)}) (return (sized 32 loop0))}"));
    CHECK(same_runs(t, u));
    CHECK(L::rename_var(t, V("loop9"), V("loop0")) == t);
}
