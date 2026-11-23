// The review's round 3b (lines): a line that would print long has the parts
// it repeats named by variables set before it (name_values' last pass,
// vars.cpp name_long) - the values round 2 kept in variables (c00127
// flashLoan's `_3059 = mem[...]`, the return data the memory pass now reads
// through) are written in full again since the memory pass resolves them,
// and the interest-rate lines grew past 240 characters (100 -> 180 long
// lines). Each case checked by running the trace before and after in the
// trace machine.
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

Value check_whole(const std::string& text) {
    Value t = V(text.c_str());
    Value u = S::simplify_trace(t);
    CHECK_MESSAGE(same_runs(t, u), dump_trace(t) << "\n->\n" << dump_trace(u));
    return u;
}

// the lines of op in v, its nested lists searched
void lines_of(Value v, Op op, std::vector<Value>& out) {
    if (!(v.is_expr() || v.is_list())) return;
    if (v.is_expr() && v.op() == op) out.push_back(v);
    for (Value a : v.args()) lines_of(a, op, out);
}

// the times part is in v, each place counted
usize count_of(Value v, Value part) {
    if (v == part) return 1;
    if (!(v.is_expr() || v.is_list())) return 0;
    usize n = 0;
    for (Value a : v.args()) n += count_of(a, part);
    return n;
}

// the variable a SETVAR of v sets to part (nil: none)
Value name_of(Value v, Value part) {
    std::vector<Value> svs;
    lines_of(v, Op::SETVAR, svs);
    for (Value sv : svs)
        if (sv[1] == part) return sv[0];
    return Value();
}

// a storage read of 5 bytes at a mapping's field, keyed by an address from
// calldata (c00127's uint40(reserveData[address(cd[...])].field_896))
const char* const kStored = "(storage 40 0 (add 7 (sha3 (mask_shl 160 0 0 (calldataload 36)) 53)))";
// a rate per second (c00127's ext_call.return_data[64] / (365 * 24 * 3600))
const char* const kRate = "(div (calldataload 4) 31536000)";

// the interest polynomial of c00127 (calculateCompoundedInterest's terms):
// rate * rate * t, -2 * rate * t * t, rate * t * t * t, in rays
std::string interest(const std::string& rate, const std::string& t) {
    return "(div (add (mul " + rate + " " + rate + " " + t + ") (mul -2 " + rate + " " + t + " " + t + ") (mul " + rate +
           " " + t + " " + t + " " + t + ") 500000000000000000000000000) 1000000000000000000000000000)";
}

}  // namespace

TEST_CASE("long lines: the parts a long line repeats are named before it (the review's c00127 flashLoan)") {
    Fixture fx;
    // A store whose value reads the same storage field six times and the
    // same rate four times: written out, the line is about 450 characters.
    // The field, the part that saves the most, is named first, then the rate
    // - each set once before the line, the line reading the names.
    const std::string text = "{(store 256 0 9 " + interest(kRate, kStored) + ") (stop)}";
    Value u = check_whole(text);
    std::vector<Value> stores;
    lines_of(u, Op::STORE, stores);
    REQUIRE(stores.size() == 1);
    const Value field = V(kStored), rate = V(kRate);
    const Value nf = name_of(u, field), nr = name_of(u, rate);
    REQUIRE(!nf.nil());
    REQUIRE(!nr.nil());
    CHECK(count_of(stores[0][3], field) == 0);
    CHECK(count_of(stores[0][3], rate) == 0);
    CHECK(count_of(stores[0][3], nf) >= 2);
    CHECK(count_of(stores[0][3], nr) >= 2);
    // (the names set before the store, in the same block)
    REQUIRE(u.is_list());
    usize at_store = 0, at_nf = u.size(), at_nr = u.size();
    for (usize i = 0; i < u.size(); ++i) {
        if (u[i] == stores[0]) at_store = i;
        if (u[i].is(Op::SETVAR, 2) && u[i][0] == nf) at_nf = i;
        if (u[i].is(Op::SETVAR, 2) && u[i][0] == nr) at_nr = i;
    }
    CHECK(at_nf < at_store);
    CHECK(at_nr < at_store);
}

TEST_CASE("long lines: a short line keeps its parts written out, and a value named again keeps its name") {
    Fixture fx;
    SUBCASE("a short line: nothing named") {
        // `require cd[4] / (365 * 24 * 3600) == cd[4] / (365 * 24 * 3600)`-like
        // short lines repeat parts too: written out, they read as the code
        const std::string text = "{(store 256 0 9 (mul " + std::string(kRate) + " " + kRate + ")) (stop)}";
        Value u = check_whole(text);
        CHECK(name_of(u, V(kRate)).nil());
    }
    SUBCASE("the branches of an if: the same names") {
        // both branches store the polynomial: the same values get the same
        // names, so the branches end with the same lines (the folder merges
        // them; names made apart would keep them apart)
        const std::string v = interest(kRate, kStored);
        const std::string text =
            "{(if (calldataload 100) {(store 256 0 9 " + v + ") (store 256 0 11 1)} {(store 256 0 9 " + v + ") (store 256 0 12 1)}) (stop)}";
        Value u = check_whole(text);
        std::vector<Value> svs;
        lines_of(u, Op::SETVAR, svs);
        const Value field = V(kStored);
        std::vector<Value> names;
        for (Value sv : svs)
            if (sv[1] == field) names.push_back(sv[0]);
        REQUIRE(names.size() >= 1);
        for (Value n : names) CHECK(n == names[0]);
    }
}

TEST_CASE("long lines: a part the checks before the line read isn't named (lot 8's SafeMath reads them with it)") {
    Fixture fx;
    // A division checked for its divisor before the line that divides (a
    // SafeMath.div site: the check, then the line using the quotient), the
    // divisor read in the line outside the quotient too. Named in the line
    // alone, the divisor would read differently there and in the check, and
    // SafeMath (which finds the check's operands in the line) would lose the
    // site (c00027 getActualSupply: its SafeMath.div gone, the check and the
    // division written out). The divisor stays written out; the quotient,
    // which no check reads, is named.
    const std::string divisor = kStored;
    const std::string quotient = "(div (calldataload 68) " + divisor + ")";
    std::string text;
    SUBCASE("the check before the line") {
        text = "{(if (iszero " + divisor + ") {(revert None)} {}) (store 256 0 9 " + interest(quotient, divisor) +
               ") (stop)}";
    }
    SUBCASE("the check around the line (the line in the branch that goes on)") {
        text = "{(if (iszero " + divisor + ") {(revert None)} {(store 256 0 9 " + interest(quotient, divisor) +
               ") (stop)})}";
    }
    Value u = check_whole(text);
    CHECK(name_of(u, V(divisor.c_str())).nil());
    std::vector<Value> stores;
    lines_of(u, Op::STORE, stores);
    REQUIRE(stores.size() == 1);
    // (the line was long and repeats the quotient: it is named)
    CHECK(!name_of(u, V(quotient.c_str())).nil());
}

TEST_CASE("long lines: an if whose branches only set one variable gets its names before it (c00027 getActualSupply)") {
    Fixture fx;
    // `_9 = not q or (x * q - q * y) / q == x - y` (SafeMath.mul's check of
    // a quotient q): the VM's if whose branches set _9 to 1 and to the
    // comparison, one line once cleanup_conds makes it the `or`. Its names
    // are set before the if - named in the branch, the branch would be two
    // lines and stay an if (c00027: an if, an else and a deeper function)
    const std::string q = "(div (calldataload 68) " + std::string(kStored) + ")";
    const std::string y = "(storage 40 0 (add 8 (sha3 (mask_shl 160 0 0 (calldataload 36)) 53)))";
    const std::string x = kRate;
    const std::string text = "{(if (iszero " + q + ") {(setvar tmp9 1)} {(setvar tmp9 (eq (div (add (mul " + x + " " +
                             q + ") (mul -1 " + q + " " + y + ")) " + q + ") (add " + x + " (mul -1 " + y +
                             "))))}) (if (iszero tmp9) {(revert None)} {}) (store 256 0 9 " + q + ") (stop)}";
    Value u = check_whole(text);
    const Value nq = name_of(u, V(q.c_str()));
    REQUIRE(!nq.nil());
    // (the name set in the function's block, not in a branch: the if is one
    // line, the or)
    REQUIRE(u.is_list());
    bool top = false;
    for (Value l : u.args()) top |= l.is(Op::SETVAR, 2) && l[0] == nq;
    CHECK(top);
    std::vector<Value> ifs;
    lines_of(u, Op::IF, ifs);
    for (Value l : ifs) CHECK_MESSAGE(!(l[1].size() == 1 && l[1][0].is(Op::SETVAR, 2) && l[2].size() > 1), dump_trace(u));
}


TEST_CASE("long lines: a check a check before it decides keeps its condition unnamed (the review's c00005)") {
    Fixture fx;
    // A divisor checked for zero, a long line that names it, the same check
    // again (the code that goes on in the checks' branches, as the VM leaves
    // it): the last cleanup_conds drops the second check, decided by the
    // first one's fact, only if it still reads the divisor - named, it read
    // `if not _82` and stayed, its revert printed twice more (c00005: raw
    // reverts 58 -> 60). name_values alone, on the trace as it gets it.
    const std::string d = kStored;
    const std::string text = "{(if " + d + " {(if (calldataload 200) {(store 256 0 20 1)} {(store 256 0 21 1)}) "
                             "(store 256 0 9 " + interest(kRate, d) + ") "
                             "(if " + d + " {(stop)} {(revert None)})} {(revert None)})}";
    Value t = V(text.c_str());
    Value u = S::name_values(t);
    CHECK_MESSAGE(same_runs(t, u), dump_trace(t) << "\n->\n" << dump_trace(u));
    // (the field is named: the store reads its name)
    const Value field = V(d.c_str());
    REQUIRE(!name_of(u, field).nil());
    // the second check reads the field, not its name
    std::vector<Value> ifs;
    lines_of(u, Op::IF, ifs);
    usize on_field = 0;
    for (Value l : ifs)
        if (l[0] == field) ++on_field;
    CHECK_MESSAGE(on_field == 2, dump_trace(u));
}
