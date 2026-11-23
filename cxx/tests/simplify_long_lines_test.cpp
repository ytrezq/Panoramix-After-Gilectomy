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

TEST_CASE("names: a base of two positions a line of rounded lengths repeats is named (the review's ensdom122 NameWrapper)") {
    Fixture fx;
    // A buffer past a dynamic one, `p + ceil32(n)` (two terms: long_sum's
    // names need three), read at four offsets in one line: four rounded
    // lengths written out (`mem[p + ceil32(n) + 64] + mem[p + ceil32(n) +
    // 96]...`). The base is named before the line, which reads `mem[_k +
    // 64]`...
    const std::string b = "(add (calldataload 36) (mask_shl 251 5 0 (add 31 (calldataload 4))))";
    std::string sum = "(add";
    for (int k : {64, 96, 128, 160}) sum += " (mem (range (add " + std::to_string(k) + " " + b + ") 32))";
    sum += ")";
    const std::string text = "{(store 256 0 9 " + sum + ") (stop)}";
    Value u = check_whole(text);
    // (the name: a variable set to a sum of two terms, one rounded)
    std::vector<Value> svs, stores;
    lines_of(u, Op::SETVAR, svs);
    lines_of(u, Op::STORE, stores);
    REQUIRE(stores.size() == 1);
    Value name;
    for (Value sv : svs)
        if (sv[1].is(Op::ADD, 2) && (sv[1][0].is(Op::MASK_SHL) || sv[1][1].is(Op::MASK_SHL))) name = sv[0];
    REQUIRE_MESSAGE(!name.nil(), dump_trace(u));
    CHECK(count_of(stores[0][3], name) == 4);
    CHECK(count_of(stores[0][3], V("(calldataload 4)")) == 0);
}

TEST_CASE("names: a base the checks right before the line read isn't named there (lot 8's SafeMath)") {
    Fixture fx;
    // The same line after a check that reads the base: a name made for the
    // line alone would read differently there and in the check, and lot 8's
    // SafeMath (which finds a check's operands in the line after it) would
    // lose the site (c00026: two Panic(17) checks printed raw)
    const std::string b = "(add (calldataload 36) (mask_shl 251 5 0 (add 31 (calldataload 4))))";
    std::string sum = "(add";
    for (int k : {64, 96, 128, 160}) sum += " (mem (range (add " + std::to_string(k) + " " + b + ") 32))";
    sum += ")";
    const std::string text = "{(if (gt (mem (range (add 64 " + b + ") 32)) (calldataload 68)) {(revert None)} {}) "
                             "(store 256 0 9 " + sum + ") (stop)}";
    Value u = check_whole(text);
    std::vector<Value> svs;
    lines_of(u, Op::SETVAR, svs);
    for (Value sv : svs)
        CHECK_MESSAGE(!(sv[1].is(Op::ADD, 2) && (sv[1][0].is(Op::MASK_SHL) || sv[1][1].is(Op::MASK_SHL))), dump_trace(u));
}

namespace {

// a hash of data no storage layout reads as a slot (a word that is no slot
// first, twelve words: an operation's id, a typed-data digest)
std::string data_hash(int salt, int words = 12) {
    std::string k = "(sha3 (sized 32 caller)";
    for (int i = 0; i + 1 < words; ++i) k += " (sized 32 (calldataload " + std::to_string(4 + 32 * i + salt) + "))";
    return k + ")";
}

// the trace after name_values, run in the trace machine before and after
Value named(const std::string& text) {
    Value t = V(text.c_str());
    Value u = S::name_values(t);
    CHECK_MESSAGE(same_runs(t, u), dump_trace(t) << "\n->\n" << dump_trace(u));
    return u;
}

// the STORE lines of u, in order
std::vector<Value> stores_of(Value u) {
    std::vector<Value> stores;
    lines_of(u, Op::STORE, stores);
    return stores;
}

}  // namespace

TEST_CASE("long lines: a storage key a variable of the trace's own holds reads as that variable (0x032 batchExecuteTransactions)") {
    Fixture fx;
    // `_275 = sha3(...)` (the code's own variable, read past the store) and
    // long lines keyed by the same hash, written out in the slot
    // (`transactionsExecuted[sha3(Bytes(2, 0x1901), ..)] = 1`): the variable
    // is the key's name, no line made - the slot still `sha3(key, 2)`, the
    // same mapping for the storage's forms
    const std::string k = data_hash(0);
    const std::string slot = "(sha3 (sized 32 " + k + ") (sized 32 2))";
    SUBCASE("the key of the place a line writes and of the read in its value") {
        Value u = named("{(setvar tmp7 " + k + ") (store 32 48 " + slot + " (mask_shl 32 0 0 (add 1 (storage 32 48 " + slot +
                        ")))) (return (sized 32 tmp7))}");
        std::vector<Value> svs;
        lines_of(u, Op::SETVAR, svs);
        CHECK_MESSAGE(svs.size() == 1, dump_trace(u));
        const auto stores = stores_of(u);
        REQUIRE(stores.size() == 1);
        CHECK_MESSAGE(stores[0][2] == V("(sha3 (sized 32 tmp7) (sized 32 2))"), dump_trace(u));
        CHECK(count_of(stores[0][3], V("tmp7")) == 1);
    }
    SUBCASE("where the variable holds the hash: not before it is set, not after it is set again") {
        Value u = named("{(store 256 0 " + slot + " 1) (setvar tmp7 " + k + ") (store 256 0 " + slot +
                        " 2) (setvar tmp7 (calldataload 4)) (store 256 0 " + slot + " 3) (return (sized 32 tmp7))}");
        const auto stores = stores_of(u);
        REQUIRE(stores.size() == 3);
        CHECK_MESSAGE(stores[0][2] == V(slot.c_str()), dump_trace(u));
        CHECK_MESSAGE(stores[1][2] == V("(sha3 (sized 32 tmp7) (sized 32 2))"), dump_trace(u));
        CHECK_MESSAGE(stores[2][2] == V(slot.c_str()), dump_trace(u));
    }
    SUBCASE("a line that isn't long keeps its key") {
        // `stor2[sha3(caller, cd[4])] = 1`: 31 characters
        const std::string k2 = "(sha3 (sized 32 caller) (sized 32 (calldataload 4)))";
        const std::string slot2 = "(sha3 (sized 32 " + k2 + ") (sized 32 2))";
        Value u = named("{(setvar tmp7 " + k2 + ") (store 256 0 " + slot2 + " 1) (return (sized 32 tmp7))}");
        const auto stores = stores_of(u);
        REQUIRE(stores.size() == 1);
        CHECK_MESSAGE(stores[0][2] == V(slot2.c_str()), dump_trace(u));
    }
}

TEST_CASE("long lines: a variable stands for a key, not for a mapping's slot (the review's c00168)") {
    Fixture fx;
    const std::string k = data_hash(1);
    SUBCASE("an inner mapping's slot keeps its hash: its own key reads as the variable that holds it") {
        // m[k][cd[4]]: `sha3(cd[4], sha3(k, 11))` - the inner hash is the
        // slot of m[k], which the storage's forms parse (a variable there is
        // a slot of its own for them: `stor[sha3(cd[4], _7)]`, c00168's
        // `stor[_155 + 2]`); k is that mapping's key
        const std::string inner = "(sha3 (sized 32 " + k + ") (sized 32 11))";
        const std::string slot = "(sha3 (sized 32 (calldataload 4)) (sized 32 " + inner + "))";
        const std::string line = "(store 256 0 " + slot + " (add 1 (storage 256 0 " + slot + ")))";
        Value u = named("{(setvar tmp7 " + inner + ") " + line + " (return (sized 32 tmp7))}");
        auto stores = stores_of(u);
        REQUIRE(stores.size() == 1);
        // (the inner slot: a hash still, of a key - which gets a name of
        // its own, no variable holding it - and the mapping's place)
        REQUIRE_MESSAGE(stores[0][2].is(Op::SHA3, 2), dump_trace(u));
        REQUIRE(stores[0][2][1].is(Op::SIZED, 2));
        REQUIRE_MESSAGE(stores[0][2][1][1].is(Op::SHA3, 2), dump_trace(u));
        CHECK(stores[0][2][1][1][1] == V("(sized 32 11)"));
        CHECK_MESSAGE(count_of(stores[0], V("tmp7")) == 0, dump_trace(u));

        u = named("{(setvar tmp7 " + inner + ") (setvar tmp8 " + k + ") " + line + " (return (sized 32 (add tmp7 tmp8)))}");
        stores = stores_of(u);
        REQUIRE(stores.size() == 1);
        const std::string kept = "(sha3 (sized 32 (calldataload 4)) (sized 32 (sha3 (sized 32 tmp8) (sized 32 11))))";
        CHECK_MESSAGE(stores[0][2] == V(kept.c_str()), dump_trace(u));
        CHECK_MESSAGE(count_of(stores[0], V("tmp7")) == 0, dump_trace(u));
        CHECK_MESSAGE(count_of(stores[0][3], V("tmp8")) == 1, dump_trace(u));
    }
    SUBCASE("a hash that may be a slot under either layout is left") {
        // `sha3(sha3(cd[4], 5), 11)`: the first part a mapping's slot where
        // the slot comes last - or the key where it comes first: left
        const std::string inner = "(sha3 (sized 32 (calldataload 4)) (sized 32 5))";
        std::string big = "(add";
        for (int i = 0; i < 30; ++i) big += " (calldataload " + std::to_string(36 + 32 * i) + ")";
        big += ")";
        const std::string slot = "(sha3 (sized 32 " + inner + ") (sized 32 11))";
        Value u = named("{(setvar tmp7 " + inner + ") (store 256 0 " + slot + " (add " + big + " (storage 256 0 " + slot +
                        "))) (return (sized 32 tmp7))}");
        const auto stores = stores_of(u);
        REQUIRE(stores.size() == 1);
        CHECK_MESSAGE(count_of(stores[0], V("tmp7")) == 0, dump_trace(u));
    }
}

TEST_CASE("long lines: a key the checks before the line read keeps its hash where the line uses what they check (lot 8's SafeMath)") {
    Fixture fx;
    // (a key of five words: the check, 110 characters, isn't long)
    const std::string k = data_hash(0, 5);
    const std::string slot = "(sha3 (sized 32 " + k + ") (sized 32 2))";
    const std::string read = "(storage 256 0 " + slot + ")";
    std::string big = "(add 1 " + read;
    for (int i = 0; i < 20; ++i) big += " (calldataload " + std::to_string(400 + 32 * i) + ")";
    big += ")";
    const std::string store = "(store 256 0 " + slot + " " + big + ")";
    SUBCASE("a check of the slot's value: the line after it reads the variable") {
        // `require stor2[k]`, then `stor2[k] = stor2[k] + 1 + ..`: the line
        // uses no arithmetic the check checks
        Value u = named("{(setvar tmp7 " + k + ") (if (iszero " + read + ") {(revert None)} {}) " + store +
                        " (return (sized 32 tmp7))}");
        const auto stores = stores_of(u);
        REQUIRE(stores.size() == 1);
        CHECK_MESSAGE(stores[0][2] == V("(sha3 (sized 32 tmp7) (sized 32 2))"), dump_trace(u));
    }
    SUBCASE("a check of the sum the line stores: the key stays in both") {
        // `if stor2[k] + 1 < cd[4000]: revert`, then `stor2[k] = stor2[k] +
        // 1`: the line uses the sum the check checks - the check's operand
        // is read in the line as the check has it (lot 8's SafeMath pairs
        // them by it)
        Value u = named("{(setvar tmp7 " + k + ") (if (lt (add 1 " + read + ") (calldataload 4000)) {(revert None)} {}) "
                        "(store 256 0 " + slot + " (add 1 " + read + ")) (return (sized 32 tmp7))}");
        const auto stores = stores_of(u);
        REQUIRE(stores.size() == 1);
        CHECK_MESSAGE(stores[0][2] == V(slot.c_str()), dump_trace(u));
        std::vector<Value> ifs;
        lines_of(u, Op::IF, ifs);
        REQUIRE(ifs.size() == 1);
        CHECK_MESSAGE(count_of(ifs[0][0], stores[0][3]) == 1, dump_trace(u));
    }
}

// ---- a key no variable holds: a name of its own ----

TEST_CASE("long lines: a storage key that is a hash is named, the slot's own hash and place as they were (0x032, AccessManager)") {
    Fixture fx;
    SUBCASE("the key read by the store and by its value") {
        // `uint32(stor2[sha3(caller, ...)].field_48) = uint32(stor2[sha3(<the
        // same>)].field_48) + 1`: the key, a hash of twelve words, written
        // twice in one line of 345 characters. The key gets a name - the
        // slot stays `sha3(key, 2)`, a mapping's for the storage's forms:
        // `stor2[_k].field_48`
        const std::string k = data_hash(0);
        const std::string slot = "(sha3 (sized 32 " + k + ") (sized 32 2))";
        const std::string text = "{(store 32 48 " + slot + " (add 1 (storage 32 48 " + slot + "))) (stop)}";
        Value u = check_whole(text);
        const Value key = V(k.c_str());
        const Value name = name_of(u, key);
        REQUIRE_MESSAGE(!name.nil(), dump_trace(u));
        std::vector<Value> stores, reads;
        lines_of(u, Op::STORE, stores);
        lines_of(u, Op::STORAGE, reads);
        REQUIRE(stores.size() == 1);
        REQUIRE(reads.size() == 1);
        for (Value sl : {stores[0][2], reads[0][2]}) {
            CHECK(count_of(sl, key) == 0);
            CHECK(count_of(sl, name) == 1);
            // (the slot: still the hash of the key and the mapping's place)
            REQUIRE(sl.is(Op::SHA3, 2));
            CHECK(sl[1] == V("(sized 32 2)"));
        }
    }
    SUBCASE("the key read once: named in a line that is long, written out in one that isn't") {
        // (`if stor2[k] < cd[400] + ... (16 words)`: 296 characters, 194
        // with the key named)
        const std::string k = data_hash(0);
        std::string big = "(add";
        for (int i = 0; i < 16; ++i) big += " (calldataload " + std::to_string(400 + 32 * i) + ")";
        big += ")";
        for (const std::string& other : {big, std::string("(calldataload 400)")}) {
            const std::string text = "{(if (lt (storage 256 0 (sha3 (sized 32 " + k + ") (sized 32 2))) " + other +
                                     ") {(revert None)} {}) (store 256 0 9 1) (stop)}";
            Value u = check_whole(text);
            CHECK_MESSAGE(name_of(u, V(k.c_str())).nil() == (other != big), dump_trace(u));
        }
    }
    SUBCASE("an inner mapping's slot is no key: its own key is") {
        // m[k][cd[4]]: `sha3(cd[4], sha3(k, 11))` - the inner hash is the
        // slot of m[k], which the storage's forms read (named, it would be
        // a slot of its own for them: `stor[sha3(cd[4], _5)]`, the review's
        // c00168); its key k, a hash of data, is named
        const std::string k = data_hash(1);
        const std::string inner = "(sha3 (sized 32 " + k + ") (sized 32 11))";
        const std::string slot = "(sha3 (sized 32 (calldataload 4)) (sized 32 " + inner + "))";
        const std::string text = "{(store 256 0 " + slot + " (add 1 (storage 256 0 " + slot + "))) (stop)}";
        Value u = check_whole(text);
        const Value name = name_of(u, V(k.c_str()));
        REQUIRE_MESSAGE(!name.nil(), dump_trace(u));
        std::vector<Value> svs, stores;
        lines_of(u, Op::SETVAR, svs);
        lines_of(u, Op::STORE, stores);
        for (Value sv : svs) CHECK_MESSAGE(sv[1] == V(k.c_str()), dump_trace(u));  // (no name but the key's)
        REQUIRE(stores.size() == 1);
        const Value sl = stores[0][2];
        REQUIRE(sl.is(Op::SHA3, 2));
        REQUIRE(sl[1].is(Op::SIZED, 2));
        REQUIRE(sl[1][1].is(Op::SHA3, 2));  // (the inner slot: a hash still)
        CHECK(sl[1][1][0] == mk(Op::SIZED, Value::small(32), name));
        CHECK(sl[1][1][1] == V("(sized 32 11)"));
    }
    SUBCASE("a hash that may be a slot under either layout is left") {
        // `sha3(sha3(cd[4], 5), 11)`: the first part a mapping's slot where
        // the slot comes last - or the key where it comes first: left
        const std::string inner = "(sha3 (sized 32 (calldataload 4)) (sized 32 5))";
        std::string big = "(add";
        for (int i = 0; i < 30; ++i) big += " (calldataload " + std::to_string(36 + 32 * i) + ")";
        big += ")";
        const std::string slot = "(sha3 (sized 32 " + inner + ") (sized 32 11))";
        const std::string text = "{(store 256 0 " + slot + " (add " + big + " (storage 256 0 " + slot + "))) (stop)}";
        Value u = check_whole(text);
        CHECK_MESSAGE(name_of(u, V(inner.c_str())).nil(), dump_trace(u));
    }
}

TEST_CASE("long lines: a key read once is named only where the line is then no longer long (the review's c00004, c00193)") {
    Fixture fx;
    const std::string k = data_hash(0);
    const std::string read = "(storage 256 0 (sha3 (sized 32 " + k + ") (sized 32 2)))";
    SUBCASE("a line that stays long with the key's name: the key written out") {
        // `if stor2[k] < cd[400] + ... (45 words)`: 560 characters, 455 with
        // the key named - one more line, and the line as long to the reader
        std::string big = "(add";
        for (int i = 0; i < 45; ++i) big += " (calldataload " + std::to_string(400 + 32 * i) + ")";
        big += ")";
        const std::string text = "{(if (lt " + read + " " + big + ") {(revert None)} {}) (store 256 0 9 1) (stop)}";
        Value t = V(text.c_str());
        Value u = S::name_values(t);
        CHECK_MESSAGE(same_runs(t, u), dump_trace(t) << "\n->\n" << dump_trace(u));
        CHECK_MESSAGE(name_of(u, V(k.c_str())).nil(), dump_trace(u));
    }
    SUBCASE("a line that isn't long as its numbers print: the key written out") {
        // `if stor2[k] < (-1 >> cd[400]) + (-1 >> cd[432]) + (-1 >> cd[464])`:
        // 2^256 - 1 prints `-1`, not 32 bytes of ff - a line of 180
        // characters (c00193's `~(-1 >> 8 * (cd[..] % 32)) & mem[..]`)
        const std::string ones = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
        std::string sum = "(add";
        for (int i = 0; i < 3; ++i) sum += " (shr (calldataload " + std::to_string(400 + 32 * i) + ") " + ones + ")";
        sum += ")";
        const std::string text = "{(if (lt " + read + " " + sum + ") {(revert None)} {}) (store 256 0 9 1) (stop)}";
        Value t = V(text.c_str());
        Value u = S::name_values(t);
        CHECK_MESSAGE(same_runs(t, u), dump_trace(t) << "\n->\n" << dump_trace(u));
        CHECK_MESSAGE(name_of(u, V(k.c_str())).nil(), dump_trace(u));
    }
    SUBCASE("a key the line prints as a key and as a word of its own: named, both written as its name") {
        // `log t: k, stor2[k] + cd[400] + ...`: the key once in the place and
        // once a topic (c00058's `log ..: indexed _5, indexed
        // uint32(stor[_5].field_48)`) - a line that stays long without the
        // sum's words, the name read twice
        std::string big = "(add " + read;
        for (int i = 0; i < 25; ++i) big += " (calldataload " + std::to_string(400 + 32 * i) + ")";
        big += ")";
        const std::string text = "{(log3 None 7 " + k + " " + big + ") (stop)}";
        Value t = V(text.c_str());
        Value u = S::name_values(t);
        CHECK_MESSAGE(same_runs(t, u), dump_trace(t) << "\n->\n" << dump_trace(u));
        const Value name = name_of(u, V(k.c_str()));
        REQUIRE_MESSAGE(!name.nil(), dump_trace(u));
        CHECK_MESSAGE(count_of(u, V(k.c_str())) == 1, dump_trace(u));
        CHECK_MESSAGE(count_of(u, name) == 3, dump_trace(u));
    }
}

TEST_CASE("long lines: a key the checks before the line read is named, unless the line uses what they check (lot 8's SafeMath)") {
    Fixture fx;
    const std::string k = data_hash(0);
    const std::string slot = "(sha3 (sized 32 " + k + ") (sized 32 2))";
    const std::string read = "(storage 256 0 " + slot + ")";
    const std::string store = "(store 256 0 " + slot + " (add 1 " + read + "))";
    SUBCASE("a check of the slot's value: the line after it names the key") {
        // `require stor2[k]`, then `stor2[k] = stor2[k] + 1`: the line uses
        // no arithmetic the check checks
        Value u = check_whole("{(if (iszero " + read + ") {(revert None)} {}) " + store + " (stop)}");
        CHECK_MESSAGE(!name_of(u, V(k.c_str())).nil(), dump_trace(u));
    }
    SUBCASE("a check of the sum the line stores: the key stays in both") {
        // `if stor2[k] + 1 < cd[400]: revert` (a line that isn't long), then
        // `stor2[k] = stor2[k] + 1`: the line uses the sum the check
        // checks - the check's operand is read in the line as the check has
        // it (lot 8's SafeMath pairs them by it)
        Value u = check_whole("{(if (lt (add 1 " + read + ") (calldataload 400)) {(revert None)} {}) " + store + " (stop)}");
        CHECK_MESSAGE(name_of(u, V(k.c_str())).nil(), dump_trace(u));
    }
    SUBCASE("a long check: its key named before it, the line after reads the name too") {
        Value u = check_whole("{(if (lt (add 1 " + read + ") " + read + ") {(revert None)} {}) " + store + " (stop)}");
        const Value name = name_of(u, V(k.c_str()));
        REQUIRE_MESSAGE(!name.nil(), dump_trace(u));
        CHECK_MESSAGE(count_of(u, V(k.c_str())) == 1, dump_trace(u));  // (the key: written once, its name's value)
    }
}

TEST_CASE("long lines: no name is made for a key a name already hides (c00066 withinExecutionLimit)") {
    Fixture fx;
    // A storage read named by a long check (`_16 = stor0[sha3(...)]`), then
    // a short-circuit if (`_7 = c and stor0[...] >= _16 + x`: an if whose
    // branches set _7) whose value reads it again, written `_16` there: a
    // name made for its key, which that line doesn't print, is dropped (a
    // `_17 = sha3(...)` nothing read)
    // (a key of five words: the read, not the key, is what the check names)
    const std::string k = data_hash(0, 5);
    const std::string read = "(storage 256 0 (sha3 (sized 32 " + k + ") (sized 32 2)))";
    std::string big = "(add";
    for (int i = 0; i < 20; ++i) big += " (calldataload " + std::to_string(400 + 32 * i) + ")";
    big += ")";
    const std::string text = "{(if (lt (add " + read + " (calldataload 68)) " + read + ") {(revert None)} {}) "
                             "(if (calldataload 100) {(setvar tmp9 (lt (add " + read + " " + big +
                             ") (calldataload 132)))} {(setvar tmp9 0)}) (return (sized 32 tmp9))}";
    Value t = V(text.c_str());
    Value u = S::name_values(t);
    CHECK_MESSAGE(same_runs(t, u), dump_trace(t) << "\n->\n" << dump_trace(u));
    std::vector<Value> svs;
    lines_of(u, Op::SETVAR, svs);
    CHECK(!svs.empty());
    for (Value sv : svs) CHECK_MESSAGE(count_of(u, sv[0]) >= 2, dump_trace(u));  // (set, and read)
    // (the read is what the check named)
    CHECK_MESSAGE(!name_of(u, V(read.c_str())).nil(), dump_trace(u));
}
