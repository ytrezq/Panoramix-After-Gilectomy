// Lot 8: SafeMath (src/analysis/safemath.hpp) on hand-made asts - the checks
// of OpenZeppelin's SafeMath, ds-math, solidity >= 0.8, their table, the
// lines they don't move past - and every rewrite run by the trace machine
// (SAFEMATH from the table) against the original on concrete calls.
#include <doctest/doctest.h>

#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "algebra/construct.hpp"
#include "analysis/safemath.hpp"
#include "core/budget.hpp"
#include "core/context.hpp"
#include "core/contract.hpp"
#include "core/dump.hpp"
#include "core/evmint.hpp"
#include "exec/machine.hpp"

using namespace pan;
using Table = SafeMathTable;

namespace {

struct Fixture {
    Budget budget{Budget::Limits{}};
    std::unique_ptr<Context> ctx;
    std::optional<ContextScope> scope;
    Fixture()
    {
        init();
        budget.attach_thread();
        ctx = Context::create(budget);
        scope.emplace(*ctx);
    }
    ~Fixture()
    {
        scope.reset();
        ctx.reset();
        budget.detach_thread();
    }
};

constexpr u32 SEL = 0x12345678;

FunctionInfo fn_of(Value body, u32 selector = SEL)
{
    FunctionInfo f;
    f.kind = FunctionInfo::Kind::Selector;
    f.selector = selector;
    f.entry.selector = selector;
    f.entry.checks = mk_list({});
    f.entry.entry_lines = mk_trace({});
    f.trace = body;
    return f;
}

// Error(string) of a message, as the compilers write it: the selector, the
// offset, the length, the text in words
Value error_data(std::string_view msg)
{
    std::vector<Value> parts{mk(Op::SIZED, Value::small(4), Value::small(0x08c379a0)),
                             mk(Op::SIZED, Value::small(32), Value::small(32)),
                             mk(Op::SIZED, Value::small(32), Value::small(i64(msg.size())))};
    for (usize k = 0; k < msg.size(); k += 32) {
        u8 w[32] = {};
        for (usize j = 0; j < 32 && k + j < msg.size(); ++j)
            w[j] = u8(msg[k + j]);
        parts.push_back(mk(Op::SIZED, Value::small(32), Word256::from_be(std::span<const u8>(w, 32)).to_value()));
    }
    return mk(Op::DATA, std::span<const Value>(parts.data(), parts.size()));
}

Value revert_line(Value data) { return mk(Op::REVERT, data); }
Value panic_line(i64 code)
{
    return mk(Op::REVERT, mk(Op::DATA, mk(Op::SIZED, Value::small(4), Value::small(0x4e487b71)),
                             mk(Op::SIZED, Value::small(32), Value::small(code))));
}
Value tr(std::initializer_list<Value> lines) { return mk_trace(lines); }
Value check(Value cond, Value fail) { return mk(Op::IF, cond, tr({fail}), tr({})); }

std::vector<u8> word_bytes(const Word256& w)
{
    std::vector<u8> b(32);
    w.to_be(b.data());
    return b;
}

struct Call {
    std::vector<u8> calldata;
    Word256 slot1, slot5;
};

std::vector<Call> calls(u32 selector)
{
    const std::vector<Word256> words = {
        Word256::of(0),
        Word256::of(1),
        Word256::of(2),
        Word256::of(1000),
        Word256{{~u64(0), ~u64(0), ~u64(0), ~u64(0)}},
        Word256{{0, 0, 0, u64(1) << 63}},
        Word256{{0, 0, u64(1) << 63, 0}},
        Word256{{12345, 0, 0, 0}},
    };
    std::vector<Call> out;
    for (usize i = 0; i < words.size(); ++i)
        for (usize j = 0; j < words.size(); ++j) {
            Call c;
            c.calldata = {u8(selector >> 24), u8(selector >> 16), u8(selector >> 8), u8(selector)};
            for (const usize k : {i, j, (i + j) % words.size()}) {
                const auto b = word_bytes(words[k]);
                c.calldata.insert(c.calldata.end(), b.begin(), b.end());
            }
            c.slot1 = words[(i * 3 + j) % words.size()];
            c.slot5 = words[(j * 5 + i + 1) % words.size()];
            out.push_back(c);
        }
    return out;
}

exec::Outcome run(std::span<const FunctionInfo> fns, const SafeMathTable* table, const Call& c,
                  std::vector<exec::SimpleHost::Effect>& effects)
{
    exec::Program p;
    p.functions = fns;
    p.safemath = table;
    exec::Machine m(p);
    exec::SimpleHost h;
    h.calldata = c.calldata;
    h.call_env.caller = Word256::of(0xca11e7);
    h.storage[Word256::of(1)] = c.slot1;
    h.storage[Word256::of(5)] = c.slot5;
    exec::Outcome o = m.call(h);
    effects = h.effects;
    return o;
}

// the rewritten functions do what the originals did, on every call
void same_runs(const std::vector<FunctionInfo>& orig, const std::vector<FunctionInfo>& done, const SafeMathTable* table)
{
    for (const FunctionInfo& f : orig)
        for (const Call& c : calls(f.selector)) {
            std::vector<exec::SimpleHost::Effect> e1, e2;
            const exec::Outcome a = run(orig, nullptr, c, e1);
            const exec::Outcome b = run(done, table, c, e2);
            INFO(exec::status_name(a.status) << " vs " << exec::status_name(b.status) << " " << b.note);
            CHECK(a.status == b.status);
            CHECK(a.data == b.data);
            CHECK(e1 == e2);
            CHECK(a.halted());
        }
}

struct Rewritten {
    std::vector<FunctionInfo> before, after;
    std::shared_ptr<const SafeMathTable> table;
};

Rewritten rewrite(std::vector<FunctionInfo> fns)
{
    Rewritten r;
    r.before = fns;
    r.after = std::move(fns);
    ContractShared shared;
    r.table = safemath::rewrite(r.after, {}, shared);
    return r;
}

Value cd(i64 off) { return mk(Op::CALLDATALOAD, Value::small(off)); }
Value st(i64 slot) { return mk(Op::STORAGE, Value::small(256), Value::small(0), Value::small(slot)); }
Value store(i64 slot, Value v) { return mk(Op::STORE, Value::small(256), Value::small(0), Value::small(slot), v); }
Value stop() { return V("(stop)"); }

bool mentions(Value v, Op op)
{
    if (v.is(op))
        return true;
    for (const Value c : v.children())
        if (c.is_node() && mentions(c, op))
            return true;
    return false;
}

}  // namespace

TEST_CASE("safemath: OpenZeppelin's sub and add, with messages")
{
    Fixture fx;
    const Value a = st(5), b = cd(4);
    const Value diff = alg::sub(a, b);
    const Value sum = alg::add(cd(36), st(1));
    const Value body = tr({check(alg::cmp(Op::GT, b, a), revert_line(error_data("SafeMath: subtraction overflow"))),
                           store(5, diff),
                           check(alg::cmp(Op::LT, sum, st(1)), revert_line(error_data("SafeMath: addition overflow"))),
                           store(1, sum), stop()});
    Rewritten r = rewrite({fn_of(body)});
    REQUIRE(r.table);
    REQUIRE(r.table->fns.size() == 2);
    CHECK(r.table->fns[0].op == Table::Arith::Add);
    CHECK(r.table->fns[1].op == Table::Arith::Sub);
    CHECK(r.table->fns[1].checks.size() == 1);
    CHECK(r.table->fns[1].checks[0].kind == Table::Fail::Error);
    CHECK_FALSE(r.table->fns[1].checks[0].message);
    CHECK(r.table->fns[1].result == alg::sub(Value::name(NameKind::SAFEMATH_PARAM, 0), Value::name(NameKind::SAFEMATH_PARAM, 1)));
    CHECK_FALSE(mentions(r.after[0].trace, Op::IF));
    CHECK(mentions(r.after[0].trace, Op::SAFEMATH));
    same_runs(r.before, r.after, r.table.get());
}

TEST_CASE("safemath: the folded forms - REQUIRE, ASSERT, an IF whose other branch goes on")
{
    Fixture fx;
    const Value sum = alg::add(cd(4), st(1));
    SUBCASE("require")
    {
        const Value body = tr({mk(Op::REQUIRE, alg::cmp(Op::GE, sum, st(1))), store(1, sum), stop()});
        Rewritten r = rewrite({fn_of(body)});
        REQUIRE(r.table);
        CHECK(r.table->fns[0].checks[0].kind == Table::Fail::Revert);
        CHECK_FALSE(mentions(r.after[0].trace, Op::REQUIRE));
        same_runs(r.before, r.after, r.table.get());
    }
    SUBCASE("assert (solidity < 0.5's invalid)")
    {
        const Value body = tr({mk(Op::ASSERT, alg::cmp(Op::GE, sum, cd(4))), store(1, sum), stop()});
        Rewritten r = rewrite({fn_of(body)});
        REQUIRE(r.table);
        CHECK(r.table->fns[0].checks[0].kind == Table::Fail::Invalid);
        same_runs(r.before, r.after, r.table.get());
    }
    SUBCASE("unfolded: the use in the branch that goes on")
    {
        const Value body = tr({mk(Op::IF, alg::cmp(Op::LT, sum, st(1)), tr({revert_line(None)}), tr({store(1, sum), stop()}))});
        Rewritten r = rewrite({fn_of(body)});
        REQUIRE(r.table);
        CHECK_FALSE(mentions(r.after[0].trace, Op::IF));
        same_runs(r.before, r.after, r.table.get());
    }
}

TEST_CASE("safemath: the same check in two places, other messages: a message parameter")
{
    Fixture fx;
    auto fn = [&](u32 sel, i64 slot, std::string_view msg) {
        const Value diff = alg::sub(st(slot), cd(4));
        return fn_of(tr({check(alg::cmp(Op::GT, cd(4), st(slot)), revert_line(error_data(msg))), store(slot, diff), stop()}), sel);
    };
    Rewritten r = rewrite({fn(0x11111111, 1, "ERC20: burn amount exceeds balance"), fn(0x22222222, 5, "SafeMath: subtraction overflow")});
    REQUIRE(r.table);
    REQUIRE(r.table->fns.size() == 1);
    CHECK(r.table->fns[0].messages == 1);
    CHECK(r.table->fns[0].checks[0].message == 0u);
    CHECK(r.table->fns[0].checks[0].fail.nil());
    same_runs(r.before, r.after, r.table.get());
}

TEST_CASE("safemath: mul, div, solidity >= 0.8's panics, inc")
{
    Fixture fx;
    const Value a = cd(4), b = cd(36);
    SUBCASE("OpenZeppelin's mul: a == 0 or a * b / a == b")
    {
        const Value prod = alg::mul(a, b);
        const Value cond = alg::band(a, alg::iszero(alg::cmp(Op::EQ, alg::div(prod, a), b)));
        const Value body = tr({check(cond, revert_line(error_data("SafeMath: multiplication overflow"))), store(1, prod), stop()});
        Rewritten r = rewrite({fn_of(body)});
        REQUIRE(r.table);
        CHECK(r.table->fns[0].op == Table::Arith::Mul);
        same_runs(r.before, r.after, r.table.get());
    }
    SUBCASE("solidity >= 0.8's mul: b == a * b / a unless a is 0 - a a product of two")
    {
        const Value a2 = alg::mul(cd(4), cd(68));
        const Value prod = alg::mul(a2, b);
        const Value cond = alg::band(alg::iszero(alg::cmp(Op::EQ, b, alg::div(prod, a2))), alg::to_bool(a2));
        const Value body = tr({check(cond, panic_line(0x11)), store(1, prod), stop()});
        Rewritten r = rewrite({fn_of(body)});
        REQUIRE(r.table);
        CHECK(r.table->fns[0].op == Table::Arith::Mul);
        same_runs(r.before, r.after, r.table.get());
    }
    SUBCASE("a product the algebra distributed: (x - y) * 997")
    {
        const Value a2 = alg::sub(st(1), a);
        const Value prod = alg::mul(a2, Value::small(997));
        CHECK(prod.is(Op::ADD));
        const Value cond = alg::band(alg::to_bool(a2), alg::iszero(alg::cmp(Op::EQ, alg::div(prod, a2), Value::small(997))));
        const Value body = tr({check(cond, panic_line(0x11)), store(5, prod), stop()});
        Rewritten r = rewrite({fn_of(body)});
        REQUIRE(r.table);
        CHECK(r.table->fns[0].op == Table::Arith::Mul);
        same_runs(r.before, r.after, r.table.get());
    }
    SUBCASE("x - (y - 1) checked against x (the algebra's sum)")
    {
        const Value res = alg::add({Value::small(1), alg::neg(b), a});
        const Value body = tr({check(alg::cmp(Op::GT, res, a), panic_line(0x11)), store(1, res), stop()});
        Rewritten r = rewrite({fn_of(body)});
        REQUIRE(r.table);
        CHECK(r.table->fns[0].op == Table::Arith::Sub);
        same_runs(r.before, r.after, r.table.get());
    }
    SUBCASE("an addition of a difference: x + (y - z), the sum checked against x")
    {
        const Value sum = alg::add({st(1), b, alg::neg(cd(68))});
        const Value body = tr({mk(Op::ASSERT, alg::cmp(Op::GE, sum, st(1))), store(1, sum), stop()});
        Rewritten r = rewrite({fn_of(body)});
        REQUIRE(r.table);
        CHECK(r.table->fns[0].op == Table::Arith::Add);
        same_runs(r.before, r.after, r.table.get());
    }
    SUBCASE("div by zero, Panic(0x12)")
    {
        const Value q = alg::div(a, b);
        const Value body = tr({check(alg::iszero(b), panic_line(0x12)), store(1, q), stop()});
        Rewritten r = rewrite({fn_of(body)});
        REQUIRE(r.table);
        CHECK(r.table->fns[0].op == Table::Arith::Div);
        CHECK(r.table->fns[0].checks[0].kind == Table::Fail::Panic);
        CHECK(r.table->fns[0].checks[0].panic == 0x12);
        same_runs(r.before, r.after, r.table.get());
    }
    SUBCASE("a + 1, Panic(0x11)")
    {
        const Value inc = alg::add(Value::small(1), st(1));
        const Value body = tr({check(alg::cmp(Op::EQ, st(1), alg::bnot(Value::small(0))), panic_line(0x11)), store(1, inc), stop()});
        Rewritten r = rewrite({fn_of(body)});
        REQUIRE(r.table);
        CHECK(r.table->fns[0].op == Table::Arith::Inc);
        CHECK(r.table->fns[0].params == 1);
        same_runs(r.before, r.after, r.table.get());
    }
}

TEST_CASE("safemath: what stays as it is")
{
    Fixture fx;
    const Value sum = alg::add(cd(4), st(1));
    const Value ck = check(alg::cmp(Op::LT, sum, st(1)), revert_line(None));
    SUBCASE("a line that may fail between the check and the use")
    {
        const Value call = mk(Op::CALL, {Value::small(1), Value::leaf(Op::GAS, 1), Value::leaf(Op::CALLER), Value::small(0), None, None});
        const Value body = tr({ck, call, store(1, sum), stop()});
        Rewritten r = rewrite({fn_of(body)});
        CHECK_FALSE(r.table);
        CHECK(r.after[0].trace == body);
    }
    SUBCASE("a line between that changes what the check reads")
    {
        const Value body = tr({ck, store(1, Value::small(7)), store(2, sum), stop()});
        Rewritten r = rewrite({fn_of(body)});
        CHECK_FALSE(r.table);
        CHECK(r.after[0].trace == body);
    }
    SUBCASE("the result never used")
    {
        const Value body = tr({ck, store(2, cd(36)), stop()});
        Rewritten r = rewrite({fn_of(body)});
        CHECK_FALSE(r.table);
        CHECK(r.after[0].trace == body);
    }
    SUBCASE("two checks, the first's result used after the second: the order kept")
    {
        const Value sum2 = alg::add(cd(36), st(5));
        const Value ck2 = check(alg::cmp(Op::LT, sum2, st(5)), revert_line(error_data("second")));
        const Value body = tr({ck, ck2, mk(Op::LOG2, None, sum, sum2), stop()});
        Rewritten r = rewrite({fn_of(body)});
        same_runs(r.before, r.after, r.table.get());
    }
}
