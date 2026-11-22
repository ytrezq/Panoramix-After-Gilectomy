// The readable forms the manual review's second round found lost
// (corpus/review/r2, round 3): a selector stored over its call's first
// argument no longer splits that argument (cleanup_mems' narrowed write),
// the long sums of positions and the hashes of memory named by a variable
// (name_values, cleanup_vars), a pointer read held by its variable. Each
// pass checked by running the trace before and after in the trace machine.
#include <doctest/doctest.h>

#include <optional>
#include <string>

#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/dump.hpp"
#include "exec/machine.hpp"
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
        calldata.resize(4 + 32 * 8);
        for (usize i = 0; i < calldata.size(); ++i) {
            const u64 r = mix(seed * 1315423911u + i);
            calldata[i] = (i >= 4 && (i - 4) % 32 < 30 && (seed & 1)) ? 0 : u8(r);
        }
        call_env.caller = Word256::of(0x1234);
        call_env.address = Word256::of(0x5678);
    }
};

bool same_runs(Value t, Value u, int n = 48) {
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

Value whole(Value t) { return S::simplify_trace(t); }

Value check_pass(const char* text, Value (*pass)(Value)) {
    Value t = V(text);
    Value u = pass(t);
    CHECK_MESSAGE(same_runs(t, u), dump_trace(t) << "\n->\n" << dump_trace(u));
    return u;
}

// the first line of op in a trace, its nested lists searched (NIL: none)
Value find_line(Value v, Op op) {
    if (!(v.is_expr() || v.is_list())) return Value();
    if (v.is_expr() && v.op() == op) return v;
    for (Value a : v.args())
        if (Value r = find_line(a, op); !r.nil()) return r;
    return Value();
}

// the occurrences of op in v, each place counted
usize count_op(Value v, Op op) {
    if (!(v.is_expr() || v.is_list())) return 0;
    usize n = v.is_expr() && v.op() == op ? 1 : 0;
    for (Value a : v.args()) n += count_op(a, op);
    return n;
}

// a SIZED of n bytes in v
bool has_width(Value v, i64 n) {
    if (!(v.is_expr() || v.is_list())) return false;
    if (v.is(Op::SIZED, 2) && v[0].is_small() && v[0].small_val() == n) return true;
    for (Value a : v.args())
        if (has_width(a, n)) return true;
    return false;
}

// a SETMEM of n bytes (its range's constant length) in v
bool has_store_of(Value v, i64 n) {
    if (!(v.is_expr() || v.is_list())) return false;
    if (v.is(Op::SETMEM, 2) && v[0].is(Op::RANGE, 2) && v[0][1].is_small() && v[0][1].small_val() == n) return true;
    for (Value a : v.args())
        if (has_store_of(a, n)) return true;
    return false;
}

bool reads_name(Value v, Value name) {
    if (v == name) return true;
    if (!(v.is_expr() || v.is_list())) return false;
    for (Value a : v.args())
        if (reads_name(a, name)) return true;
    return false;
}

// a read of memory in v
bool has_op_mem(Value v) {
    if (!(v.is_expr() || v.is_list())) return false;
    if (v.is(Op::MEM)) return true;
    for (Value a : v.args())
        if (has_op_mem(a)) return true;
    return false;
}

Value last_line(Value t) { return t[t.size() - 1]; }

// the SETVARs of v
void setvars(Value v, std::vector<Value>& out) {
    if (!(v.is_expr() || v.is_list())) return;
    if (v.is(Op::SETVAR, 2)) out.push_back(v);
    for (Value a : v.args()) setvars(a, out);
}

}  // namespace

TEST_CASE("names: a selector stored over the first argument's top bytes leaves the argument whole") {
    Fixture fx;
    // solc's abi.encodeWithSelector (the review's c00184, c00048, c00173):
    // the arguments at p + 36..., then the selector or-ed into the word at p
    // + 32, whose low 28 bytes are the first argument's top bytes - a
    // read-modify-write. Once the memory pass resolves that read the split
    // wrote those 28 bytes again as a line of their own, and the call read
    // the argument as Bytes(28, x >> 32), Bytes(4, uint32(x)). The write is
    // the selector's 4 bytes: the argument stays one word, no 28-byte store
    const char* text =
        "{(setmem (range 64 32) (sized 32 128)) "
        "(if (calldataload 100) {(setmem (range 64 32) (add 160 (and 4064 (calldataload 132))))} {}) "
        "(setvar tmp38 (mem (range 64 32))) "
        "(setmem (range (add 36 tmp38) 32) (sized 32 (mask_shl 160 0 0 (calldataload 4)))) "
        "(setmem (range (add 68 tmp38) 32) (sized 32 (calldataload 36))) "
        "(setvar tmp39 (mem (range 64 32))) "
        "(setmem (range tmp39 32) (sized 32 (add 68 tmp38 (mul -1 tmp39)))) "
        "(setmem (range 64 32) (add 100 tmp38)) "
        "(setvar tmp40 (mem (range (add 32 tmp39) 32))) "
        "(setmem (range (add 32 tmp39) 32) "
        "(sized 32 (or (mask_shl 224 0 0 tmp40) 0xa9059cbb00000000000000000000000000000000000000000000000000000000))) "
        "(call 1 gas 0xdead 0 (mem (range (add 32 tmp39) 4)) (mem (range (add 36 tmp39) 64))) (stop)}";
    Value u = check_pass(text, whole);
    const Value call = find_line(u, Op::CALL);
    REQUIRE(!call.nil());
    CHECK(!has_op_mem(call));
    CHECK(!has_width(call, 28));
    CHECK(!has_store_of(u, 28));
}

TEST_CASE("names: a long sum of positions read in several lines is a variable") {
    Fixture fx;
    // a buffer allocated past two others of lengths read from calldata and a
    // third of n words (the review's c00028, c00150, c00142): its base, a
    // sum of five terms, was written out in every line that read it. Named
    // where it is first read, its uses are short; the sum is written once
    // (tmp1, set and read once, is put in its place and gone: the name made
    // isn't it - the algebra still has tmp1's value, 0, and the conditions
    // decided after the naming would read the new variable as 0)
    const char* text =
        "{(setvar tmp1 0) (store 256 0 1 tmp1) "
        "(setvar tmp5 (add 192 (mask_shl 251 5 0 (add 31 (and 4095 (calldataload 4)))) "
        "(mask_shl 251 5 0 (add 31 (and 4095 (calldataload 36)))) (mul 32 (and 255 (calldataload 68))))) "
        "(if (lt (calldataload 100) tmp5) {(revert None)} {}) "
        "(if (lt (calldataload 132) (add 32 tmp5)) {(revert None)} {}) "
        "(store 256 0 7 (add 64 tmp5)) "
        "(return (sized 32 (add 96 tmp5)))}";
    Value u = check_pass(text, whole);
    // the sum once: in the variable's value (its masks: the rounded lengths,
    // the lengths' own) - its uses the variable
    std::vector<Value> svs;
    setvars(u, svs);
    REQUIRE(svs.size() == 1);
    CHECK(svs[0][0] != V("tmp1"));
    CHECK(count_op(svs[0], Op::MASK_SHL) >= 2);
    CHECK(count_op(u, Op::MASK_SHL) == count_op(svs[0], Op::MASK_SHL));
    CHECK(reads_name(last_line(u), svs[0][0]));
    // the conditions kept: the first one stays a condition of the variable
    CHECK(count_op(u, Op::REVERT) == 2);
    // read once: the sum stays where it is read, no variable
    const char* once =
        "{(setvar tmp1 (add 192 (mask_shl 251 5 0 (add 31 (and 4095 (calldataload 4)))) "
        "(mask_shl 251 5 0 (add 31 (and 4095 (calldataload 36)))) (mul 32 (and 255 (calldataload 68))))) "
        "(return (sized 32 (add 96 tmp1)))}";
    u = check_pass(once, whole);
    svs.clear();
    setvars(u, svs);
    CHECK(svs.empty());
}

TEST_CASE("names: a product of words is no sum of positions") {
    Fixture fx;
    // aave's balanceOf: an interest computation of five terms, products of
    // the timestamp and a stored time - arithmetic, written out as it is
    const char* text =
        "{(setvar tmp1 (add (mul timestamp timestamp) (mul -2 timestamp (storage 256 0 3)) "
        "(mul (storage 256 0 3) (storage 256 0 3)) (storage 256 0 3) (mul -1 timestamp))) "
        "(if (lt (calldataload 4) tmp1) {(revert None)} {}) "
        "(return (sized 32 (add 1 tmp1)))}";
    Value u = check_pass(text, whole);
    std::vector<Value> svs;
    setvars(u, svs);
    CHECK(svs.empty());
}

TEST_CASE("names: a hash of a buffer read in several lines keeps its variable") {
    Fixture fx;
    // Governor's proposal id (the review's c00033, c00144, c00157, c00208):
    // id = keccak256(abi.encode(...)) of a buffer at p, used as a mapping's
    // key in several lines - written out, sha3(mem[p + 32 len ...]) in each
    const char* text =
        "{(setmem (range 64 32) (sized 32 128)) "
        "(if (calldataload 4) {(setmem (range 64 32) (add 160 (and 4064 (calldataload 36))))} {}) "
        "(setvar tmp29 (mem (range 64 32))) "
        "(setmem (range (add 32 tmp29) 32) (sized 32 (calldataload 68))) "
        "(setmem (range (add 64 tmp29) 32) (sized 32 (calldataload 100))) "
        "(setmem (range 64 32) (add 96 tmp29)) "
        "(setvar tmp31 (sha3 (mem (range (add 32 tmp29) (and 63 (calldataload 132)))))) "
        "(setmem (range 0 32) (sized 32 tmp31)) (setmem (range 32 32) (sized 32 3)) "
        "(if (storage 8 0 (sha3 (mem (range 0 64)))) {(revert None)} {}) "
        "(store 256 0 9 tmp31) "
        "(return (sized 32 tmp31))}";
    Value u = check_pass(text, whole);
    CHECK(count_op(u, Op::SHA3) <= 2);  // (the id's and the slot's)
    CHECK(reads_name(last_line(u), V("tmp31")));
}

TEST_CASE("names: the word's reads where a variable holds it are the variable") {
    Fixture fx;
    // p = mload(0x40) kept for after the word moves on (the storage string
    // copies of the review's c00133, the npm corpus' uniswap tests): where p
    // holds the word, its reads are p - one name for the buffer's base
    const char* text =
        "{(setmem (range 64 32) (sized 32 128)) "
        "(if (calldataload 4) {(setmem (range 64 32) (add 160 (and 4064 (calldataload 36))))} {}) "
        "(setvar tmp45 (mem (range 64 32))) "
        "(setmem (range (add 32 (mem (range 64 32))) 32) (sized 32 (calldataload 68))) "
        "(setmem (range 64 32) (add 64 (mem (range 64 32)))) "
        "(log1 (mem (range tmp45 (and 63 (calldataload 100)))) 7) "
        "(if (calldataload 132) {(setmem (range 64 32) (add 32 (mem (range 64 32))))} {}) "
        "(store 256 0 7 tmp45) "
        "(store 256 0 8 (mem (range 64 32))) "
        "(stop)}";
    Value u = check_pass(text, whole);
    // mem[p + 32] = x, mem[64] = p + 64: no read of the word left but p's
    bool found = false;
    for (Value l : u.args())
        if (l.is(Op::SETMEM, 2) && l[0].is(Op::RANGE, 2) && !l[0][0].is_small() && reads_name(l[0], V("tmp45")))
            found = true;
    CHECK_MESSAGE(found, dump_trace(u));
    // (the reads left: the variable's own, the log's, the store's after the
    // join - none of the word where p holds it)
    CHECK(count_op(u, Op::MEM) == 3);
}
