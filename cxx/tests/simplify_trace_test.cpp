// Lot 7: the trace passes (cleanup_vars, cleanup_mems, cleanup_conds,
// min_ifs, short_circuits, the driver) on hand-made traces, each checked by
// running the trace before and after in lot 11's trace machine on random
// worlds (calldata, storage, call answers) - the same outcome, the same
// effects.
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
#include "simplify/effects.hpp"
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

// a random world: storage words from the slot, calldata of words, call answers
struct World final : exec::SimpleHost {
    u64 seed;
    explicit World(u64 s) : seed(s) {
        calldata.resize(4 + 32 * 6);
        for (usize i = 0; i < calldata.size(); ++i) {
            u64 r = mix(seed * 1315423911u + i);
            // small words often: the high bytes zero
            calldata[i] = (i >= 4 && (i - 4) % 32 < 24 && (seed & 1)) ? 0 : u8(r);
        }
        call_env.caller = Word256::of(0x1234);
        call_env.address = Word256::of(0x5678);
        call_env.callvalue = Word256::of(seed % 3 == 0 ? 0 : 7);
        call_answer = exec::CallResult{(seed % 2) == 0, std::vector<u8>(seed % 5 == 0 ? 0 : 64, u8(seed))};
    }
    Word256 initial(const Word256& slot) override {
        u8 b[32];
        slot.to_be(b);
        u64 h = seed;
        for (u8 x : b) h = mix(h ^ x);
        if (seed % 4 == 1) return Word256::of(h % 100);
        Word256 w{};
        w.limb[0] = h;
        w.limb[1] = mix(h);
        return w;
    }
};

std::string show(const exec::Outcome& o) {
    std::string s = exec::status_name(o.status);
    s += " data " + std::to_string(o.data.size());
    if (!o.note.empty()) s += " (" + o.note + ")";
    return s;
}

// t and u run the same on `n` worlds
bool same_runs(Value t, Value u, int n = 24) {
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
            MESSAGE("world " << s << ": " << show(a) << " vs " << show(b) << " effects " << w1.effects.size() << " vs "
                              << w2.effects.size());
            return false;
        }
    }
    return true;
}

Value check_trace(const char* text, Value (*pass)(Value)) {
    Value t = V(text);
    Value u = pass(t);
    CHECK_MESSAGE(same_runs(t, u), dump_trace(t) << "\n->\n" << dump_trace(u));
    return u;
}

Value whole(Value t) { return S::simplify_trace(t); }

}  // namespace

TEST_CASE("simplify: cleanup_vars inlines and drops") {
    Fixture f;
    Value u = check_trace("{(setvar tmp1 (calldataload 4)) (setvar tmp2 (add 1 tmp1)) (return (sized 32 tmp2))}",
                          S::cleanup_vars);
    CHECK(u.size() == 1);
    CHECK(u[0].is(Op::RETURN));
    // a value read past a write of what it reads: kept
    u = check_trace("{(setvar tmp1 (mem (range 64 32))) (setmem (range 64 32) 5) (return (sized 32 tmp1))}",
                    S::cleanup_vars);
    CHECK(u.size() == 3);
    // storage
    u = check_trace("{(setvar tmp1 (storage 256 0 3)) (store 256 0 3 7) (return (sized 32 tmp1))}", S::cleanup_vars);
    CHECK(u.size() == 3);
    u = check_trace("{(setvar tmp1 (storage 256 0 3)) (store 256 0 4 7) (return (sized 32 tmp1))}", S::cleanup_vars);
    CHECK(u.size() == 2);
    // branches that agree
    u = check_trace(
        "{(if (calldataload 4) {(setvar tmp1 5)} {(setvar tmp1 5)}) (return (sized 32 tmp1))}", S::cleanup_vars);
    // branches that don't
    u = check_trace(
        "{(if (calldataload 4) {(setvar tmp1 5)} {(setvar tmp1 6)}) (return (sized 32 tmp1))}", S::cleanup_vars);
    CHECK(u.size() == 2);
    // a branch that ends: what the other one knows goes on
    u = check_trace(
        "{(setvar tmp1 (calldataload 4)) (if (calldataload 36) {(revert None)} {(setvar tmp2 tmp1)}) (return (sized 32 "
        "tmp2))}",
        S::cleanup_vars);
}

TEST_CASE("simplify: cleanup_vars and loops (raw LABEL / GOTO)") {
    Fixture f;
    // a counter: the label's setvar not inlined into the loop
    check_trace(
        "{(setvar tmp1 3) (label loopid1 [(setvar loop1 0)]) (if (lt loop1 tmp1) {(setmem (range (add 128 (mul 32 loop1)) "
        "32) loop1) (goto loopid1 [(setvar loop1 (add 1 loop1))])} {}) (return (mem (range 128 96)))}",
        S::cleanup_vars);
    // a variable set in the loop and read at its start, next round
    check_trace(
        "{(setvar tmp2 0) (label loopid1 [(setvar loop1 0)]) (setvar tmp3 (add tmp2 loop1)) (setvar tmp2 (add tmp3 1)) (if "
        "(lt loop1 4) {(goto loopid1 [(setvar loop1 (add 1 loop1))])} {}) (return (sized 32 tmp2))}",
        S::cleanup_vars);
}

TEST_CASE("simplify: cleanup_mems") {
    Fixture f;
    Value u = check_trace("{(setmem (range 64 32) (calldataload 4)) (return (mem (range 64 32)))}", S::cleanup_mems);
    CHECK(u.size() == 1);
    // a part of a word
    check_trace("{(setmem (range 64 32) (calldataload 4)) (return (mem (range 80 8)))}", S::cleanup_mems);
    // two writes, a read across them
    check_trace(
        "{(setmem (range 64 32) (calldataload 4)) (setmem (range 96 32) (calldataload 36)) (return (mem (range 80 "
        "32)))}",
        S::cleanup_mems);
    // a write that a branch overwrites
    check_trace(
        "{(setmem (range 64 32) 1) (if (calldataload 4) {(setmem (range 64 32) 2)} {}) (return (mem (range 64 32)))}",
        S::cleanup_mems);
    // a loop that writes it
    check_trace(
        "{(setmem (range 128 32) 9) (label loopid1 [(setvar loop1 0)]) (if (lt loop1 3) {(setmem (range (add 96 (mul 32 "
        "loop1)) 32) loop1) (goto loopid1 [(setvar loop1 (add 1 loop1))])} {}) (return (mem (range 128 32)))}",
        S::cleanup_mems);
    // the value read from storage, then the storage written
    check_trace(
        "{(setmem (range 64 32) (storage 256 0 1)) (store 256 0 1 5) (return (mem (range 64 32)))}", S::cleanup_mems);
    // a call's output
    check_trace(
        "{(setmem (range 0 32) 7) (call 1 (gas 1) (calldataload 4) 0 None None) (setmem (range 0 (min 32 (returndatasize "
        "1))) (returndata_bytes 1 0 (min 32 (returndatasize 1)))) (if (lt (returndatasize 1) 32) {(revert None)} {}) "
        "(return (mem (range 0 32)))}",
        S::cleanup_mems);
}

TEST_CASE("simplify: conditions") {
    Fixture f;
    check_trace("{(if 1 {(return (sized 32 1))} {(revert None)})}", S::cleanup_conds);
    check_trace("{(if (lt (mask_shl 8 0 0 (calldataload 4)) 256) {(return (sized 32 1))} {(revert None)})}",
                S::cleanup_conds);
    check_trace("{(if (calldataload 4) {} {(revert None)}) (stop)}", S::cleanup_conds);
    Value u = check_trace(
        "{(if (lt (calldataload 4) (calldataload 36)) {(setvar tmp1 (calldataload 4))} {(setvar tmp1 (calldataload "
        "36))}) (return (sized 32 tmp1))}",
        S::min_ifs);
    CHECK(u[0].is(Op::SETVAR));
    u = check_trace(
        "{(if (calldataload 4) {(setvar tmp1 (calldataload 36))} {(setvar tmp1 0)}) (return (sized 32 tmp1))}",
        S::short_circuits);
    CHECK(u[0].is(Op::SETVAR));
}

TEST_CASE("simplify: the driver") {
    Fixture f;
    check_trace(
        "{(setmem (range 64 32) 128) (setvar tmp1 (mem (range 64 32))) (setmem (range tmp1 32) (calldataload 4)) "
        "(setmem (range 64 32) (add 32 tmp1)) (setvar tmp2 (mem (range 64 32))) (return (mem (range tmp1 (add tmp2 (mul "
        "-1 tmp1)))))}",
        whole);
    check_trace(
        "{(setvar tmp1 (calldataload 4)) (if (iszero (eq tmp1 (mask_shl 160 0 0 tmp1))) {(revert None)} {}) (store 256 "
        "0 (sha3 (sized 32 tmp1) (sized 32 0)) (calldataload 36)) (log1 None 5) (stop)}",
        whole);
}

TEST_CASE("simplify: compaction mid-run") {
    Fixture f;
    // the outcomes of the trace before it is simplified (its Values are gone
    // after the first compaction: only plain data kept)
    const char* text =
        "{(setvar tmp1 (calldataload 4)) (setmem (range 128 32) tmp1) (setvar tmp2 (mem (range 128 32))) (setmem (range "
        "160 32) (add tmp2 (mem (range 64 32)))) (setvar tmp3 (mem (range 160 32))) (if (lt tmp3 5) {(revert None)} {}) "
        "(return (mem (range 128 64)))}";
    struct Run {
        exec::Status status;
        std::vector<u8> data;
        std::vector<exec::SimpleHost::Effect> effects;
    };
    std::vector<Run> before;
    {
        Value t = V(text);
        Value entry = V("{(setmem (range 64 32) 128)}");
        FunctionInfo fn;
        exec::Program p;
        exec::Machine m(p);
        for (int s = 0; s < 8; ++s) {
            World w{u64(s)};
            // (the entry lines first, as the dispatcher runs them)
            SmallVec<Value, 16> lines;
            lines.push_back(entry[0]);
            for (Value l : t.args()) lines.push_back(l);
            exec::Outcome o = m.run(w, fn, mk_trace(lines.span()));
            before.push_back({o.status, o.data, w.effects});
        }
    }
    Value t = V(text);
    Value keep = V("(add 1 (calldataload 4))");
    std::vector<Value> roots{keep};
    S::SimplifyOptions o;
    o.compact = true;
    o.compact_threshold = 1;  // after every round that changed something
    o.entry_lines = V("{(setmem (range 64 32) 128)}");
    o.compact_roots = roots;
    const void* old_node = t.node();
    Value r = S::simplify_trace(t, o);
    // (it compacted: the input's nodes are gone)
    CHECK(!cx().arena.owns(old_node));
    CHECK(!dump_trace(r).empty());
    CHECK(dump(roots[0]) == "(add 1 (calldataload 4))");
    FunctionInfo fn;
    exec::Program p;
    exec::Machine m(p);
    Value entry = V("{(setmem (range 64 32) 128)}");
    for (int s = 0; s < 8; ++s) {
        World w{u64(s)};
        SmallVec<Value, 16> lines;
        lines.push_back(entry[0]);
        for (Value l : r.args()) lines.push_back(l);
        exec::Outcome out = m.run(w, fn, mk_trace(lines.span()));
        CHECK(out.status == before[usize(s)].status);
        CHECK(out.data == before[usize(s)].data);
        CHECK(w.effects == before[usize(s)].effects);
    }
}

TEST_CASE("simplify: the length of a storage bytes") {
    Fixture f;
    Value u = check_trace(
        "{(return (sized 32 (mask_shl 255 1 -1 (and (add -1 (mul 256 (iszero (storage 1 0 6)))) (storage 256 0 6)))))}",
        S::replace_bytes_or_string_length);
    CHECK(u[0][0][1].is(Op::STORAGE));
    check_trace("{(return (sized 32 (mask_shl 255 1 0 (and (storage 256 0 6) (add -1 (mul 256 (iszero (storage 1 0 6))))))))}",
                S::replace_bytes_or_string_length);
    check_trace(
        "{(return (sized 32 (mask_shl 250 6 -1 (and (storage 256 0 (calldataload 4)) (add -1 (mul 256 (iszero (storage 1 0 "
        "(calldataload 4)))))))))}",
        S::replace_bytes_or_string_length);
}

TEST_CASE("simplify: calls' selectors, ABI arrays") {
    Fixture f;
    Value u = check_trace(
        "{(call 1 (gas 1) (calldataload 4) 0 None (data (sized 4 0xa9059cbb) (sized 32 caller) (sized 32 5))) (stop)}",
        S::simplify_exps);
    CHECK(u[0][4].is(Op::SIZED));
    // the selector in a wider first part (the address word's zeroes after it)
    u = check_trace(
        "{(call 1 (gas 1) (calldataload 4) 0 None (data (sized 16 0xa9059cbb000000000000000000000000) (sized 20 caller) "
        "(sized 32 5))) (stop)}",
        S::simplify_exps);
    CHECK(u[0][4].is(Op::SIZED));
    MESSAGE(dump(u[0]));
    u = check_trace("{(return (data (sized 32 32) (sized 32 5) (sized 5 0x1122334455) (sized 27 0)))}", S::postprocess_exps);
    CHECK(u[0][0].is(Op::DATA));
    CHECK(u[0][0][0].is(Op::ARR));
    // two heads before it, a symbolic length padded to whole words
    u = check_trace(
        "{(return (data (sized 32 caller) (sized 32 64) (sized 32 calldatasize) (calldata_bytes 0 calldatasize) (sized (add "
        "(mask_shl 251 5 0 (add 31 calldatasize)) (mul -1 calldatasize)) 0)))}",
        S::postprocess_exps);
    CHECK(u[0][0][1].is(Op::ARR));
    // not an encoding: as it is
    check_trace("{(return (data (sized 32 32) (sized 32 5) (sized 3 0x112233)))}", S::postprocess_exps);
}
