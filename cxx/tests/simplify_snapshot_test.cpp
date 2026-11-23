// The words of memory a text reads again and again (round 4): a read of the
// word at a constant address - the free memory pointer, a length kept in
// memory - is a snapshot of state the lines after it may change. The final
// naming (name_values) gives the reads of one word while it is unchanged
// one name, set before the first: display only - which name stands for a
// value, never a value. Each trace is run before and after in the trace
// machine.
#include <doctest/doctest.h>

#include <optional>
#include <string>
#include <vector>

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

// calldata of random words (small ones often)
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

bool same_runs(Value t, Value u, int n = 64) {
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

Value named(const std::string& text) {
    Value t = V(text);
    Value u = S::name_values(t);
    CHECK_MESSAGE(same_runs(t, u), dump_trace(t) << "\n->\n" << dump_trace(u));
    return u;
}

// the occurrences of op in v, each place counted
usize count_op(Value v, Op op) {
    if (!(v.is_expr() || v.is_list())) return 0;
    usize n = v.is_expr() && v.op() == op ? 1 : 0;
    for (Value a : v.args()) n += count_op(a, op);
    return n;
}

// the SETVARs of v set to a read of the word at addr, in the text's order
void word_names(Value v, i64 addr, std::vector<Value>& out) {
    if (!(v.is_expr() || v.is_list())) return;
    if (v.is(Op::SETVAR, 2) && v[1] == V("(mem (range " + std::to_string(addr) + " 32))")) out.push_back(v);
    for (Value a : v.args()) word_names(a, addr, out);
}

// the word at 64 written by a branch: what it holds after the join is known
// to no pass, only that it is at least 128 (the floor)
const std::string kMoved =
    "(setmem (range 64 32) (sized 32 128)) "
    "(if (calldataload 4) {(setmem (range 64 32) (sized 32 (add 160 (and 4064 (calldataload 36)))))} {}) ";

}  // namespace

TEST_CASE("snapshot: the reads of a word while it is unchanged are one name") {
    Fixture fx;
    // mem[mem[64]] = x; mem[mem[64] + 32] = y; stor7 = mem[64]: the writes are
    // at the word's value, past the word (its floor): `_1 = mem[64]`, then
    // mem[_1] = x, mem[_1 + 32] = y, stor7 = _1
    Value u = named("{" + kMoved +
                    "(setmem (range (mem (range 64 32)) 32) (sized 32 (calldataload 68))) "
                    "(setmem (range (add 32 (mem (range 64 32))) 32) (sized 32 (calldataload 100))) "
                    "(store 256 0 7 (mem (range 64 32))) "
                    "(stop)}");
    std::vector<Value> names;
    word_names(u, 64, names);
    REQUIRE_MESSAGE(names.size() == 1, dump_trace(u));
    // (the one read left is the name's)
    CHECK_MESSAGE(count_op(u, Op::MEM) == 1, dump_trace(u));
    const Value k = names[0][0];
    CHECK_MESSAGE(u[u.size() - 2] == mk(Op::STORE, Value::small(256), Value::small(0), Value::small(7), k), dump_trace(u));
}

TEST_CASE("snapshot: past a write of the word its reads are another name") {
    Fixture fx;
    // ... mem[64] = mem[64] + 64 (the word moves): the reads after it are
    // not the first name's - `_1 = mem[64]` ... `mem[64] = _1 + 64`, `_2 =
    // mem[64]`, mem[_2] = z, stor7 = _2
    Value u = named("{" + kMoved +
                    "(setmem (range (mem (range 64 32)) 32) (sized 32 (calldataload 68))) "
                    "(setmem (range (add 32 (mem (range 64 32))) 32) (sized 32 (calldataload 100))) "
                    "(setmem (range 64 32) (sized 32 (add 64 (mem (range 64 32))))) "
                    "(setmem (range (mem (range 64 32)) 32) (sized 32 (calldataload 132))) "
                    "(setmem (range (add 32 (mem (range 64 32))) 32) (sized 32 (calldataload 164))) "
                    "(store 256 0 7 (mem (range 64 32))) "
                    "(stop)}");
    std::vector<Value> names;
    word_names(u, 64, names);
    REQUIRE_MESSAGE(names.size() == 2, dump_trace(u));
    const Value a = names[0][0], b = names[1][0];
    CHECK(a != b);
    // the word's write reads the first name, the store after it the second
    bool moved = false;
    for (Value l : u.args())
        if (l.is(Op::SETMEM, 2) && l[0] == V("(range 64 32)") && l[1].is(Op::SIZED, 2) && l[1][1].is(Op::ADD, 2))
            moved = moved || (l[1][1][0] == Value::small(64) && l[1][1][1] == a);
    CHECK_MESSAGE(moved, dump_trace(u));
    CHECK_MESSAGE(u[u.size() - 2] == mk(Op::STORE, Value::small(256), Value::small(0), Value::small(7), b), dump_trace(u));
}

TEST_CASE("snapshot: past a write that may be the word's the name does not stand for its reads") {
    Fixture fx;
    // a write at 0, 32, 64 or 96 (a word of the calldata decides): it may
    // be the word's. The reads after it are not the name set before it -
    // and, nothing known of the word any more, a write at its value may be
    // the word's too: each read after is its own, written as it is
    Value u = named("{" + kMoved +
                    "(setmem (range (mem (range 64 32)) 32) (sized 32 (calldataload 68))) "
                    "(setmem (range (add 32 (mem (range 64 32))) 32) (sized 32 (calldataload 100))) "
                    "(setmem (range (and 96 (calldataload 132)) 32) (sized 32 (add 256 (and 96 (calldataload 164))))) "
                    "(setmem (range (mem (range 64 32)) 32) (sized 32 7)) "
                    "(store 256 0 7 (mem (range 64 32))) "
                    "(stop)}");
    std::vector<Value> names;
    word_names(u, 64, names);
    REQUIRE_MESSAGE(names.size() == 1, dump_trace(u));
    CHECK_MESSAGE(u[u.size() - 3] == V("(setmem (range (mem (range 64 32)) 32) (sized 32 7))"), dump_trace(u));
    CHECK_MESSAGE(u[u.size() - 2] == V("(store 256 0 7 (mem (range 64 32)))"), dump_trace(u));
}

TEST_CASE("snapshot: a word both branches of an if read first is named before the if") {
    Fixture fx;
    // if c: mem[mem[64]] = 1 else: mem[mem[64]] = 2; then mem[mem[64] + 32] =
    // 3, stor7 = mem[64]: one name, set before the if - the lines after the
    // branches (in each of them, in a trace that holds them so) are the same
    Value u = named("{" + kMoved +
                    "(if (calldataload 68) "
                    "{(setmem (range (mem (range 64 32)) 32) (sized 32 1))} "
                    "{(setmem (range (mem (range 64 32)) 32) (sized 32 2))}) "
                    "(setmem (range (add 32 (mem (range 64 32))) 32) (sized 32 3)) "
                    "(store 256 0 7 (mem (range 64 32))) "
                    "(stop)}");
    std::vector<Value> names;
    word_names(u, 64, names);
    REQUIRE_MESSAGE(names.size() == 1, dump_trace(u));
    CHECK_MESSAGE(count_op(u, Op::MEM) == 1, dump_trace(u));
    // (set at the trace's level, not in a branch)
    bool top = false;
    for (Value l : u.args()) top = top || l == names[0];
    CHECK_MESSAGE(top, dump_trace(u));
}

TEST_CASE("snapshot: the same line in two branches names the word the same") {
    Fixture fx;
    // each branch moves the word its own way, then goes on with the same
    // lines (the trace holds them in each branch): the word read before
    // the if by both is one name, set before it; read again in those lines
    // it is another - the same in both branches, the lines stay the same
    const std::string tail =
        "(setmem (range (mem (range 64 32)) 32) (sized 32 5)) "
        "(setmem (range (add 32 (mem (range 64 32))) 32) (sized 32 6)) "
        "(store 256 0 7 (mem (range 64 32))) "
        "(stop)";
    Value u = named("{" + kMoved +
                    "(if (calldataload 68) "
                    "{(setmem (range 64 32) (sized 32 (add 64 (mem (range 64 32))))) " + tail + "} "
                    "{(setmem (range 64 32) (sized 32 (add 96 (mem (range 64 32))))) " + tail + "})}");
    std::vector<Value> names;
    word_names(u, 64, names);
    REQUIRE_MESSAGE(names.size() == 3, dump_trace(u));
    CHECK_MESSAGE(names[0] != names[1], dump_trace(u));
    CHECK_MESSAGE(names[1] == names[2], dump_trace(u));
    // (the branches' lines after the word's write: the same)
    const Value branches = u[u.size() - 1];
    REQUIRE(branches.is(Op::IF, 3));
    REQUIRE(branches[1].size() == branches[2].size());
    for (u32 i = 1; i < branches[1].size(); ++i) CHECK_MESSAGE(branches[1][i] == branches[2][i], dump_trace(u));
}

TEST_CASE("snapshot: a word read once, or by the bytes of a return alone, gets no name") {
    Fixture fx;
    const std::string once = "{" + kMoved + "(store 256 0 7 (mem (range 64 32))) (stop)}";
    CHECK(S::name_values(V(once)) == V(once));
    const std::string bytes = "{" + kMoved + "(return (mem (range (mem (range 64 32)) (add 32 (mem (range 64 32))))))}";
    CHECK(S::name_values(V(bytes)) == V(bytes));
}

TEST_CASE("snapshot: the name takes the number of the trace's variable set to the same read") {
    Fixture fx;
    // mem[mem[64]] = x; p = mem[64]; mem[64] = p + 64; stor7 = p: the read
    // before p is the same snapshot - named p, set before the first read
    Value u = named("{" + kMoved +
                    "(setmem (range (mem (range 64 32)) 32) (sized 32 (calldataload 68))) "
                    "(setvar tmp45 (mem (range 64 32))) "
                    "(setmem (range 64 32) (sized 32 (add 64 tmp45))) "
                    "(store 256 0 7 tmp45) "
                    "(stop)}");
    std::vector<Value> names;
    word_names(u, 64, names);
    REQUIRE_MESSAGE(names.size() == 1, dump_trace(u));
    CHECK_MESSAGE(names[0][0] == V("tmp45"), dump_trace(u));
    CHECK_MESSAGE(count_op(u, Op::MEM) == 1, dump_trace(u));
}
