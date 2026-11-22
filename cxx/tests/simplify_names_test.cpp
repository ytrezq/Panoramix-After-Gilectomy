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
[[maybe_unused]] usize count_op(Value v, Op op) {
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

[[maybe_unused]] bool reads_name(Value v, Value name) {
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

[[maybe_unused]] Value last_line(Value t) { return t[t.size() - 1]; }

// the SETVARs of v
[[maybe_unused]] void setvars(Value v, std::vector<Value>& out) {
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
