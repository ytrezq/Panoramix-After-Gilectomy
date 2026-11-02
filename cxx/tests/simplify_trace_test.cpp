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
#include "algebra/ranges.hpp"
#include "exec/machine.hpp"
#include "loops/loops.hpp"
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
        // (a limit - memory past the machine's - is inconclusive, as in stagecheck)
        if (a.status == exec::Status::Exhausted || b.status == exec::Status::Exhausted) continue;
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

// x appears in v (any depth)
bool contains(Value v, Value x) {
    if (v == x) return true;
    if (!(v.is_expr() || v.is_list())) return false;
    for (Value a : v.args())
        if (contains(a, x)) return true;
    return false;
}

// an op appears in v (any depth)
bool has_op(Value v, Op op) {
    if (!(v.is_expr() || v.is_list())) return false;
    if (v.is_expr() && v.op() == op) return true;
    for (Value a : v.args())
        if (has_op(a, op)) return true;
    return false;
}

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

TEST_CASE("simplify: conditions known on the path") {
    Fixture f;
    // a check passed holds until what it reads changes: the same check again is decided
    Value u = check_trace(
        "{(if (iszero (storage 8 64 7)) {(revert None)} {}) (store 8 0 7 1) (if (iszero (storage 8 64 7)) {(revert "
        "None)} {}) (stop)}",
        S::cleanup_conds);
    CHECK(u.size() == 3);
    // ... and isn't once it changes
    u = check_trace(
        "{(if (iszero (storage 8 64 7)) {(revert None)} {}) (store 8 64 7 (calldataload 4)) (if (iszero (storage 8 64 "
        "7)) {(revert None)} {}) (stop)}",
        S::cleanup_conds);
    CHECK(u.size() == 4);
    // nested: the inner test decided by the outer one
    u = check_trace(
        "{(if (lt (calldataload 4) 10) {(if (lt (calldataload 4) 20) {(return (sized 32 1))} {(return (sized 32 2))})} "
        "{(stop)})}",
        S::cleanup_conds);
    CHECK(u[0][1][0].is(Op::RETURN));
    // a variable set again
    check_trace(
        "{(setvar tmp1 (calldataload 4)) (if (iszero tmp1) {(revert None)} {}) (setvar tmp1 (calldataload 36)) (if "
        "(iszero tmp1) {(revert None)} {}) (stop)}",
        S::cleanup_conds);
}

TEST_CASE("simplify: memory where msize is read") {
    Fixture f;
    // a read of what was written: its bytes (it touches no more memory); a
    // read of memory nothing wrote: kept (it moves msize - not zeroes); the
    // writes all kept
    Value u = check_trace(
        "{(setmem (range 0 32) caller) (setmem (range 32 32) 0) (setvar tmp1 (sha3 (mem (range 0 64)))) (setvar tmp2 (mem "
        "(range 256 32))) (setvar tmp3 msize) (return (data (sized 32 tmp1) (sized 32 tmp2) (sized 32 tmp3)))}",
        whole);
    CHECK(!contains(u, V("(mem (range 0 64))")));
    CHECK(contains(u, V("(mem (range 256 32))")));
    CHECK(contains(u, V("(setmem (range 0 32) caller)")));
    // a revert's message written before it, then msize read on the other path
    u = check_trace(
        "{(if (calldataload 4) {(setmem (range 128 32) 0x8c379a000000000000000000000000000000000000000000000000000000000) "
        "(setmem (range 132 32) 32) (setmem (range 164 32) 18) (setmem (range 196 32) "
        "0x5661742f6e6f742d617574686f72697a65640000000000000000000000000000) (revert (mem (range 128 100)))} "
        "{(setvar tmp1 msize) (setmem (range tmp1 32) 5) (return (data (sized 32 tmp1) (sized 32 msize)))})}",
        whole);
    CHECK(!contains(u, V("(mem (range 128 100))")));
    // a piece made of msize isn't kept past what moves it
    check_trace(
        "{(setmem (range 64 32) msize) (setmem (range 512 32) 1) (return (mem (range 64 32)))}", whole);
    check_trace(
        "{(setmem (range msize 32) 7) (setmem (range 512 32) 1) (return (mem (range msize 32)))}", whole);
    // a whole-bytes mask of a read narrowed only where it ends the same
    check_trace(
        "{(setvar tmp1 (mask_shl 160 96 -96 (mem (range 200 32)))) (return (data (sized 32 tmp1) (sized 32 msize)))}",
        whole);
}

TEST_CASE("simplify: memory a loop's iterations write") {
    Fixture f;
    // each iteration reads what the one before wrote (the step not
    // constant: no induction, the loop's writes made of its variable);
    // fresh memory: the read isn't zeroes
    S::SimplifyOptions o;
    o.fresh_memory = true;
    Value t = V(
        "{(setmem (range 64 32) 128) (while (lt loop1 (mask_shl 8 0 0 (calldataload 4))) {(setmem (range (add 160 loop1) "
        "32) (add 1 (mem (range (add 128 loop1) 32)))) (continue loopid1 [(setvar loop1 (add 32 loop1 (mul 32 (mask_shl 1 "
        "0 0 (calldataload 36)))))])} loopid1 [(setvar loop1 0)]) (return (mem (range 128 160)))}");
    Value u = S::simplify_trace(t, o);
    CHECK_MESSAGE(same_runs(t, u), dump_trace(t) << "\n->\n" << dump_trace(u));
    // the step constant, the bound unknown
    t = V("{(setmem (range 64 32) 128) (while (lt loop1 (mask_shl 8 0 0 (calldataload 4))) {(setmem (range (add 160 loop1) "
          "32) (add 1 (mem (range (add 128 loop1) 32)))) (continue loopid1 [(setvar loop1 (add 32 loop1))])} loopid1 "
          "[(setvar loop1 0)]) (return (mem (range 128 160)))}");
    u = S::simplify_trace(t, o);
    CHECK_MESSAGE(same_runs(t, u), dump_trace(t) << "\n->\n" << dump_trace(u));
}

TEST_CASE("simplify: memory at offsets the checks bound") {
    Fixture f;
    // X = ceil32(len) of a word of calldata: X + k may wrap, unless len <=
    // 2^32 is checked before any memory position reads it (a small word) -
    // then a write at 64 doesn't meet X + 160
    const std::string x = "(mask_shl 251 5 0 (add 31 (calldataload 4)))";
    const std::string check = "(if (gt (calldataload 4) 4294967296) {(revert None)} {}) ";
    const std::string body = "(setmem (range (add 160 " + x + ") 32) 64) (setmem (range 64 32) (add 256 " + x +
                             ")) (return (sized 32 (mem (range (add 160 " + x + ") 32))))}";
    Value u = check_trace(("{" + check + body).c_str(), whole);
    CHECK(!has_op(u, Op::MEM));
    // the rest of the trace in the branch where it holds (the VM's form)
    u = check_trace(("{(if (le (calldataload 4) 4294967296) {" + body.substr(0, body.size() - 1) +
                     "} {(revert None)})}")
                        .c_str(),
                    whole);
    CHECK(!has_op(u, Op::MEM));
    // a function that always reverts (its result reverted): both branches
    // revert, the rest of the trace in the larger one
    const std::string rbody = "(setmem (range (add 160 " + x + ") 32) 64) (setmem (range 64 32) (add 256 " + x +
                              ")) (revert (sized 32 (mem (range (add 160 " + x + ") 32))))";
    u = check_trace(("{(if (gt (calldataload 4) 4294967296) {(revert None)} {" + rbody + "})}").c_str(), whole);
    CHECK(!has_op(u, Op::MEM));
    u = check_trace(("{(if (le (calldataload 4) 4294967296) {" + rbody + "} {(revert None)})}").c_str(), whole);
    CHECK(!has_op(u, Op::MEM));
    // ... a position reading it in the smaller one: not small
    u = check_trace(("{(if (le (calldataload 4) 4294967296) {" + rbody + "} {(setmem (range (add 192 " + x +
                     ") 32) 7) (revert None)})}")
                        .c_str(),
                    whole);
    CHECK(has_op(u, Op::MEM));
    // not without the check, nor with a position reading it before the check
    u = check_trace(("{" + body).c_str(), whole);
    CHECK(has_op(u, Op::MEM));
    u = check_trace(("{(setmem (range (add 192 " + x + ") 32) 7) " + check + body).c_str(), whole);
    CHECK(has_op(u, Op::MEM));
    // Error(string)'s layout at X + 160: partly overlapping writes
    u = check_trace(("{" + check + "(setmem (range (add 160 " + x +
                     ") 32) 0x8c379a000000000000000000000000000000000000000000000000000000000) (setmem (range (add 164 " + x +
                     ") 32) 32) (setmem (range (add 196 " + x + ") 32) 18) (setmem (range (add 228 " + x +
                     ") 32) 0x5661742f6e6f742d617574686f72697a65640000000000000000000000000000) (revert (mem (range (add 160 " +
                     x + ") 100)))}")
                        .c_str(),
                    whole);
    CHECK(!has_op(u, Op::MEM));
    // a variable set twice isn't the same word everywhere: not small
    const std::string y = "(mask_shl 251 5 0 (add 31 tmp1))";
    u = check_trace(("{(setvar tmp1 (calldataload 4)) (if (gt tmp1 4294967296) {(revert None)} {}) (setvar tmp1 "
                     "(calldataload 36)) (setmem (range (add 160 " +
                     y + ") 32) 64) (setmem (range 64 32) (add 256 " + y + ")) (return (sized 32 (mem (range (add 160 " + y +
                     ") 32))))}")
                        .c_str(),
                    whole);
    CHECK(has_op(u, Op::MEM));
    // ... once: its value is
    u = check_trace(("{(setvar tmp1 (calldataload 4)) (if (gt tmp1 4294967296) {(revert None)} {}) (setmem (range (add "
                     "160 " +
                     y + ") 32) 64) (setmem (range 64 32) (add 256 " + y + ")) (return (sized 32 (mem (range (add 160 " + y +
                     ") 32))))}")
                        .c_str(),
                    whole);
    CHECK(!has_op(u, Op::MEM));
}

TEST_CASE("simplify: review 2026-11-02 F1 (10-simplify1) - a write before a BREAK, read after the loop") {
    Fixture f;
    // the backward pass took a BREAK for the end of every path (C_ENDS) and
    // dropped the write before it; a BREAK leaves the loop for what follows
    // the WHILE. (BREAK is a print-only line today - never in a simplified
    // trace - but the trace machine runs it, and the pass must be right on it.)
    Value t = V("{(while (lt loop1 4) {(setmem (range 0 32) 7) (break loopid1)} loopid1 [(setvar loop1 0)]) "
                "(return (mem (range 0 32)))}");
    Value u = S::cleanup_mems(t);
    CHECK(has_op(u, Op::SETMEM));
    CHECK_MESSAGE(same_runs(t, u), dump_trace(t) << "\n->\n" << dump_trace(u));
    // the write in the branch that breaks, the other path writing again
    t = V("{(while (lt loop1 4) {(if (calldataload 4) {(setmem (range 0 32) 7) (break loopid1)} {}) (setmem (range 0 32) "
          "9) (continue loopid1 [(setvar loop1 (add 1 loop1))])} loopid1 [(setvar loop1 0)]) (return (mem (range 0 32)))}");
    u = S::cleanup_mems(t);
    CHECK(has_op(u, Op::SETMEM));
    CHECK_MESSAGE(same_runs(t, u), dump_trace(t) << "\n->\n" << dump_trace(u));
    // a BREAK of a loop that isn't there: anything may be read after it
    t = V("{(setmem (range 0 32) 7) (break loopid9) (return (mem (range 0 32)))}");
    u = S::cleanup_mems(t);
    CHECK(has_op(u, Op::SETMEM));
}

TEST_CASE("simplify: review 2026-11-02 F2 (10-simplify1) - a read of memory moves msize") {
    Fixture f;
    // an MLOAD past msize grows the memory as a write does (the EVM, the
    // trace machine's mem_at): a SETVAR whose value reads memory writes
    // S_MSIZE, like every other line touching memory (effects.hpp) - the
    // summary said S_VARS only, so a fact or a value reading msize was kept
    // across it
    const Value line = V("(setvar tmp1 (mem (range 1000 32)))");
    CHECK((S::summary(line).writes & S::S_MSIZE) != 0);
    CHECK(S::affects(line, V("msize")));
    CHECK(S::affects(line, V("(add 32 _msize)")) == false);  // (a variable of its own: not msize itself)
    // the setvars of a CONTINUE / WHILE / GOTO / LABEL too (their SETVARs' summaries)
    CHECK((S::summary(V("(continue loopid1 [(setvar loop1 (mem (range 1000 32)))])")).writes & S::S_MSIZE) != 0);
    CHECK((S::summary(V("(label loopid1 [(setvar loop1 (mem (range 1000 32)))])")).writes & S::S_MSIZE) != 0);
    // a value reading no memory moves it not (a read of msize itself either)
    CHECK(!S::affects(V("(setvar tmp1 msize)"), V("msize")));
    CHECK(!S::affects(V("(setvar tmp1 (calldataload 4))"), V("msize")));
    CHECK(!S::affects(V("(setvar tmp1 (add 1 tmp2))"), V("msize")));
    // cleanup_conds: a check of msize passed, a read of memory past it, the
    // same check again - not decided by the first (msize moved: the machine
    // returns 2, the decided trace returned 1)
    const char* text =
        "{(if (lt msize 1000) {(setvar tmp1 (mem (range 1000 32))) (if (lt msize 1000) {(return (sized 32 1))} "
        "{(return (sized 32 2))})} {(stop)})}";
    Value u = check_trace(text, S::cleanup_conds);
    CHECK(has_op(u[0][1], Op::IF));
    u = check_trace(text, whole);
    CHECK(has_op(u, Op::IF));
    // ... and a check that stays decided: the read of memory before both
    u = check_trace(
        "{(setvar tmp1 (mem (range 1000 32))) (if (lt msize 2000) {(if (lt msize 2000) {(return (sized 32 1))} "
        "{(return (sized 32 2))})} {(stop)})}",
        S::cleanup_conds);
    CHECK(!has_op(u[1][1], Op::IF));
    // cleanup_mems keeps its precision on a SETVAR reading memory (a live
    // range made of its variable is read before it as its value, not as
    // anything): the write of 1024 is read by no one (tmp1 < 256)
    u = check_trace(
        "{(setmem (range 1024 32) 5) (setvar tmp1 (mask_shl 8 0 0 (mem (range 64 32)))) (return (mem (range tmp1 32)))}",
        S::cleanup_mems);
    CHECK(!has_op(u, Op::SETMEM));
}

TEST_CASE("simplify: review 2026-11-02 F3 (10-simplify1) - the live set at a WHILE body's end") {
    Fixture f;
    // a body whose end isn't a CONTINUE leaves the loop (loops.hpp, ir.md
    // 4.4: the trace machine's while_line), so the backward walk of the body
    // starts from what follows the WHILE: a write at the body's end, read
    // after the loop only, is live there (the loop itself reads no memory)
    Value t = V("{(while (lt loop1 4) {(if (lt loop1 3) {(continue loopid1 [(setvar loop1 (add 1 loop1))])} {}) "
                "(setmem (range 0 32) loop1)} loopid1 [(setvar loop1 0)]) (return (mem (range 0 32)))}");
    Value u = S::cleanup_mems(t);
    CHECK(has_op(u, Op::SETMEM));
    CHECK_MESSAGE(same_runs(t, u), dump_trace(t) << "\n->\n" << dump_trace(u));
    // a write before a CONTINUE, read by the next iteration only (its first
    // line; nothing after the loop reads memory): live through the loop's
    // head. (The read isn't resolved by the forward pass: at the head, what
    // the loop writes is forgotten.)
    t = V("{(while (lt loop1 4) {(setvar tmp1 (mem (range 32 32))) (setmem (range 32 32) (add 2 tmp1)) (continue loopid1 "
          "[(setvar loop1 (add 1 loop1))])} loopid1 [(setvar loop1 0)]) (return (sized 32 tmp1))}");
    u = S::cleanup_mems(t);
    CHECK(has_op(u, Op::SETMEM));
    CHECK_MESSAGE(same_runs(t, u), dump_trace(t) << "\n->\n" << dump_trace(u));
    // (a write read by the CONTINUE's setvars alone is read as its value by
    // the forward pass: dead then, dropped - the same runs)
    t = V("{(while (lt loop1 4) {(setmem (range 32 32) (add 1 loop1)) (continue loopid1 [(setvar loop1 (mem (range 32 "
          "32)))])} loopid1 [(setvar loop1 0)]) (return (sized 32 loop1))}");
    u = S::cleanup_mems(t);
    CHECK(!has_op(u, Op::SETMEM));
    CHECK_MESSAGE(same_runs(t, u), dump_trace(t) << "\n->\n" << dump_trace(u));
    // ... and read by the condition of the next iteration
    t = V("{(while (lt (mem (range 32 32)) 4) {(setmem (range 32 32) (add 1 (mem (range 32 32)))) (continue loopid1 "
          "[])} loopid1 []) (return (sized 32 (mem (range 32 32))))}");
    u = S::cleanup_mems(t);
    CHECK(has_op(u, Op::SETMEM));
    CHECK_MESSAGE(same_runs(t, u), dump_trace(t) << "\n->\n" << dump_trace(u));
    // both at once: the write at the end read after the loop, the one before
    // the CONTINUE read by the next round; the whole simplifier
    t = V("{(while (lt loop1 4) {(setmem (range 32 32) (add 1 loop1)) (if (lt loop1 3) {(continue loopid1 [(setvar loop1 "
          "(mem (range 32 32)))])} {}) (setmem (range 0 32) loop1)} loopid1 [(setvar loop1 0)]) (return (mem (range 0 "
          "64)))}");
    u = S::simplify_trace(t);
    CHECK_MESSAGE(same_runs(t, u), dump_trace(t) << "\n->\n" << dump_trace(u));
}

TEST_CASE("simplify: review 2026-11-02 F1 (11-simplify2) - a LABEL precedes every GOTO to it") {
    Fixture f;
    // The VM makes a GOTO only in a node below its LABEL's (vm_rounds.cpp:
    // replace_loops loops to an ancestor at the same jumpdest, set_label
    // makes the label node the head's only child), so in its trace the
    // LABEL comes before every GOTO to it, in the same trace or an enclosing
    // one; make_whiles refuses a GOTO out of its LABEL's lines; the trace
    // machine (ir.md 4.4) resumes a GOTO after a LABEL already run, and
    // reports a bug otherwise. So cleanup_vars / cleanup_conds may take a
    // LABEL for a loop's head: what the lines after it change is forgotten,
    // what the lines before it know holds (every path to the label ran them).
    // a value set before the label and in the loop: not inlined past it
    Value u = check_trace(
        "{(setvar tmp1 7) (label loopid1 [(setvar loop1 0)]) (if (lt loop1 3) {(setvar tmp1 (add loop1 tmp1)) (goto "
        "loopid1 [(setvar loop1 (add 1 loop1))])} {}) (return (sized 32 tmp1))}",
        S::cleanup_vars);
    CHECK(contains(u, V("(return (sized 32 tmp1))")));
    // a fact known before the label, changed in the loop: not decided after it
    u = check_trace(
        "{(setvar tmp1 0) (label loopid1 [(setvar loop1 0)]) (if (iszero tmp1) {(setvar tmp1 1) (goto loopid1 [(setvar "
        "loop1 (add 1 loop1))])} {}) (return (sized 32 loop1))}",
        S::cleanup_conds);
    CHECK(has_op(u, Op::IF));
    // a GOTO before its LABEL isn't a trace: make_whiles refuses it, the
    // machine reports the stage's bug
    Value fwd = V("{(if 1 {(goto loopid1 [(setvar loop1 1)])} {}) (setvar tmp1 7) (label loopid1 [(setvar loop1 0)]) "
                  "(return (sized 32 tmp1))}");
    std::vector<LoopInfo> loops;
    CHECK_THROWS_AS((void)loops::make_whiles(fwd, loops), Unsupported);
    FunctionInfo fn;
    fn.kind = FunctionInfo::Kind::Selector;
    exec::Program p;
    exec::Machine m(p);
    World w{1};
    CHECK(m.run(w, fn, fwd).status == exec::Status::Bug);
}

TEST_CASE("simplify: review 2026-11-02 F2 (11-simplify2) - truth(cond) is an equivalence") {
    Fixture f;
    // alg::truth's contract (algebra/construct.hpp): zero exactly when cond
    // is - an equivalence, as the local rules of conds.cpp are (an odd
    // factor, c + x == 0 <=> x == -c, a - b, xor): the if's condition may be
    // truth(cond) and its else branch may assume iszero(truth(cond)).
    // Conditions whose truth isn't them as a value: the inner ifs (the
    // condition as it was) are decided by the branch they're in, and the
    // machine agrees on both values of the bit
    const std::string b = "(mask_shl 1 0 0 (calldataload 4))";
    const std::string conds[] = {
        "(mul 3 " + b + ")",            // 3 * b is 0 exactly when b is (odd: a bijection)
        "(mul 2 " + b + ")",            // 2 * b too, b below 2^255
        "(bool " + b + ")",             // the same truth, 0 / 1 as a value
        "(iszero (iszero " + b + "))",  // the same
        "(add -1 " + b + ")",           // b - 1: 0 exactly when b == 1
        "(xor 1 " + b + ")",            // b ^ 1: the same
    };
    for (const std::string& c : conds) {
        const std::string text = "{(if " + c + " {(if " + c + " {(return (sized 32 1))} {(return (sized 32 2))})} {(if " +
                                 c + " {(return (sized 32 3))} {(return (sized 32 4))})})}";
        Value u = check_trace(text.c_str(), S::cleanup_conds);
        REQUIRE(u.size() == 1);
        REQUIRE(u[0].is(Op::IF, 3));
        CHECK_MESSAGE(u[0][0] != V(c), dump(u[0][0]));  // (truth changed it)
        CHECK_MESSAGE(!has_op(u[0][1], Op::IF), dump_trace(u));
        CHECK_MESSAGE(!has_op(u[0][2], Op::IF), dump_trace(u));
    }
}

TEST_CASE("simplify: review 2026-11-02 F2 (04-algebra1) - iszero of a mask of a wide value keeps its shift") {
    Fixture f;
    // iszero(MASK_SHL(8, 256, -256, D)) - D two words: the byte at bit 256 of
    // the data, moved down to bit 0 - was rewritten to iszero(MASK_SHL(8, 256,
    // 0, D)): the field left past bit 256 is out of the word, so that is
    // iszero(0) = 1 whatever the byte (the IR's MASK_SHL is a word mod 2^256
    // whatever its operand: exec/machine.hpp). The rule holds when the field
    // stays within the word.
    Value t = V("{(if (iszero (mask_shl 8 256 -256 (data (sized 32 (calldataload 4)) (sized 32 (calldataload 36))))) "
                "{(return (sized 32 1))} {(return (sized 32 2))})}");
    Value u = S::simplify_trace(t);
    CHECK_MESSAGE(same_runs(t, u), dump_trace(t) << "\n->\n" << dump_trace(u));
    CHECK(u[0].is(Op::IF));
    // the same mask of a word: the shift is dropped (the rule), the runs agree
    t = V("{(if (iszero (mask_shl 8 8 -8 (calldataload 4))) {(return (sized 32 1))} {(return (sized 32 2))})}");
    u = S::simplify_trace(t);
    CHECK_MESSAGE(same_runs(t, u), dump_trace(t) << "\n->\n" << dump_trace(u));
}
