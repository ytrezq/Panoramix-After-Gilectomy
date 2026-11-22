// The gas left is no value: every GAS instruction reads it anew (the
// review's c00460, c00384, c00465, c00523, c00549, c00069, c00171, c00059,
// c00159). The VM gives each read a variable set where the code reads it
// (a call's own gas, `GAS CALL`, apart), every line consumes gas for the
// effect summaries, lot 10 prints a read in the one line that uses it right
// after it. Checked by execution on a gas left that goes down at every read
// and every call (validate's Session::gas(), the same for evmone, the trace
// machine and the text's interpreter): each case below differs from evmone
// where a read is moved past a call, taken out of a loop or taken for loop
// invariant - what the decompiler did before.
#include "validate/stage_check.hpp"
#include "validate/text_interp.hpp"
#include "validate/text_parser.hpp"

#include "core/context.hpp"
#include "core/dump.hpp"
#include "decompile.hpp"
#include "driver/pipeline.hpp"
#include "exec/machine.hpp"
#include "output/output.hpp"
#include "simplify/effects.hpp"
#include "validate_test_util.hpp"

#include <string>
#include <vector>

using namespace validate;

namespace
{
struct QuietLog
{
    int saved = pan::log_level();
    QuietLog() { pan::set_log_level(pan::log_critical); }
    ~QuietLog() { pan::set_log_level(saved); }
};

Bytes word(const Word& w)
{
    const auto b = to_bytes(w);
    return {b.begin(), b.end()};
}

Word gas_word(std::int64_t x)
{
    return Word{static_cast<std::uint64_t>(x)};
}

/// calldata of no selector: words from offset 4 on
Bytes args(std::initializer_list<Word> words)
{
    Bytes b{0, 0, 0, 0};
    for (const auto& w : words)
    {
        const auto x = word(w);
        b.insert(b.end(), x.begin(), x.end());
    }
    return b;
}

/// A bytecode decompiled by the pipeline (every stage kept) and its text;
/// each call run by evmone, by the machine on every stage and by the text's
/// interpreter, on the empty and a random world: the effects the same.
struct Decompile
{
    pan::Budget budget{pan::Budget::Limits{}};
    Bytes code;
    std::unique_ptr<Decompiled> contract;
    std::unique_ptr<pan::Context> ctx;
    std::optional<pan::ContextScope> scope;
    std::string text, folded;

    explicit Decompile(Bytes c) : code(std::move(c))
    {
        pan::init();
        budget.attach_thread();
        contract = std::make_unique<Decompiled>(code);
        ctx = pan::Context::create(budget, &contract->shared);
        scope.emplace(*ctx);
        pan::driver::PipelineOptions o;
        o.threads = 1;
        o.keep = pan::driver::KEEP_ALL;
        o.function_memory = budget.limits().memory;
        const auto r = pan::driver::run_until(code, pan::driver::Stage::Folded, o);
        for (unsigned s = 0; s < stage_count; ++s)
            if (r.kept[s])
            {
                contract->functions[s] = r.functions[s];
                contract->internals[s] = r.internals[s];
                contract->made[s] = true;
            }
        contract->storage = r.storage;
        contract->safemath = r.safemath;
        pan::output::PrintOptions po;
        po.color = false;
        text = pan::output::print_contract(r, po);
        for (const auto& f : contract->functions[stage_count - 1])
            folded += pan::dump_trace(f.trace) + "\n";
    }
    ~Decompile()
    {
        scope.reset();
        ctx.reset();
        contract.reset();
        budget.detach_thread();
    }

    void check(std::initializer_list<Bytes> calldatas)
    {
        INFO("text:\n", text, "folded:\n", folded);
        for (unsigned s = 0; s < stage_count; ++s)
            REQUIRE(contract->made[s]);
        const text::Program program = text::parse(text);
        for (const auto& e : program.errors)
            MESSAGE(e);
        CHECK(program.errors.empty());
        text::Interpreter interp{program};
        for (const bool random : {false, true})
            for (const auto& cd : calldatas)
            {
                const SeededWorld world{{.seed = 7, .random = random}};
                const CallContext call{world.actors()[0], world.actors()[0], 0, 1, cd};
                EvmRunner runner{code};
                State evm_state{world, world.contract_address(), code};
                const Effects expected = runner.run(evm_state, call);
                INFO((random ? "random" : "empty"), " world, calldata ", hex(cd), "\nevm:\n", to_string(expected));
                REQUIRE(!expected.end.inconclusive());
                for (unsigned s = 0; s < stage_count; ++s)
                {
                    pan::exec::Program p;
                    p.functions = contract->functions[s];
                    p.internals = contract->internals[s];
                    p.shared = &contract->shared;
                    p.layout = contract->storage.get();
                    p.safemath = contract->safemath.get();
                    State state{world, world.contract_address(), code};
                    Session session{state, call};
                    pan::exec::Machine m{p};
                    pan::exec::Outcome out;
                    const Effects actual = run_machine(m, session, std::nullopt, &out);
                    INFO("stage ", stage_name(static_cast<Stage>(s)), ", machine (", pan::exec::status_name(out.status),
                        " ", out.note, "):\n", to_string(actual));
                    CHECK(compare(expected, actual).verdict == Verdict::same);
                }
                State text_state{world, world.contract_address(), code};
                const Effects mine = interp.run(text_state, call);
                INFO("text's run:\n", to_string(mine));
                CHECK(compare(expected, mine).verdict == Verdict::same);
            }
    }
};

/// the word of a return of 32 bytes
Word returned(const Effects& e)
{
    REQUIRE(e.end.status == Status::return_);
    REQUIRE(e.end.data.size() >= 32);
    return load_word(e.end.data, 0);
}

/// the effects of a call of code by evmone
Effects evm(const Bytes& code, const Bytes& calldata)
{
    const SeededWorld world{{.seed = 7, .random = false}};
    const CallContext call{world.actors()[0], world.actors()[0], 0, 1, calldata};
    EvmRunner runner{code};
    State state{world, world.contract_address(), code};
    return runner.run(state, call);
}

/// a world in memory whose gas left goes down by `step` at every read
struct DrainingHost final : pan::exec::SimpleHost
{
    std::uint64_t left = 1'000'000, step = 7;
    pan::Word256 gas() override
    {
        const auto g = left;
        left -= step;
        return pan::Word256::of(g);
    }
};

/// a context of its own for a test's Values
struct Ctx
{
    pan::Budget budget{pan::Budget::Limits{}};
    std::unique_ptr<pan::Context> ctx;
    std::optional<pan::ContextScope> scope;
    Ctx()
    {
        pan::init();
        budget.attach_thread();
        ctx = pan::Context::create(budget);
        scope.emplace(*ctx);
    }
    ~Ctx()
    {
        scope.reset();
        ctx.reset();
        budget.detach_thread();
    }
};

/// a trace run as a fallback by the machine on a draining host: the end, the data
std::pair<pan::exec::Status, std::vector<std::uint8_t>> run_trace(pan::Value trace)
{
    pan::FunctionInfo f;
    f.kind = pan::FunctionInfo::Kind::Fallback;
    f.trace = trace;
    std::vector<pan::FunctionInfo> fns{f};
    pan::exec::Program p;
    p.functions = fns;
    pan::exec::MachineLimits lim;
    lim.steps = 100'000;
    pan::exec::Machine m{p, lim};
    DrainingHost host;
    const auto o = m.call(host);
    return {o.status, o.data};
}
}  // namespace

TEST_CASE("gas reads: Session::gas goes down at every read and every call, the same for evmone")
{
    // mstore(0, gas); mstore(32, gas); call(gas, 0x1234, 0, 0, 0, 0, 0);
    // mstore(64, gas); return(0, 96) - three reads, the call's own gas not one
    const Bytes code = *parse_hex("5a600052" "5a602052" "6000600060006000600061123" "45a" "f150" "5a604052"
                                  "60606000f3");
    const Effects e = evm(code, {});
    REQUIRE(e.end.status == Status::return_);
    REQUIRE(e.end.data.size() == 96);
    CHECK(load_word(e.end.data, 0) == gas_word(fixed_gas));
    CHECK(load_word(e.end.data, 32) == gas_word(fixed_gas - gas_read_cost));
    CHECK(load_word(e.end.data, 64) == gas_word(fixed_gas - 2 * gas_read_cost - gas_event_cost));
}

TEST_CASE("gas reads: a read before a call, used after it, is read before it (c00523, c00549, c00171)")
{
    // g = gas; call(gas, calldataload(4), 0, 0, 0, 0, 0); pop; mstore(0, g); return(0, 32)
    const QuietLog quiet;
    Decompile d{*parse_hex("5a" "6000600060006000" "6000" "600435" "5a" "f1" "50" "600052" "60206000f3")};
    // what the bytecode returns: the gas left before the call
    CHECK(returned(evm(d.code, args({0x1234}))) == gas_word(fixed_gas));
    d.check({args({0x1234}), args({0}), args({3})});
    // the text reads it before the call: `_1 = gas_remaining`, then the call
    // with its own gas, then `return _1`
    INFO(d.text);
    const auto read = d.text.find(" = gas_remaining");
    const auto call = d.text.find("call ");
    REQUIRE(read != std::string::npos);
    REQUIRE(call != std::string::npos);
    CHECK(read < call);
    CHECK(d.text.find("gas gas_remaining") != std::string::npos);
    CHECK(d.text.find("return gas_remaining") == std::string::npos);
}

TEST_CASE("gas reads: the reads of a loop stay in the loop (c00384, c00465, c00059, c00159)")
{
    // n = calldataload(4) & 3; for (i = 0; i < n; i++) { before = gas;
    // call(gas, calldataload(36), 0, 0, 0, 0, 0); mstore(32 i, before - gas) }
    // return(0, 32 n) - multicall's gasUsed: the same for every call
    const QuietLog quiet;
    Decompile d{*parse_hex("600435" "600316" "6000" "5b" "81" "81" "10" "15" "602f" "57" "5a" "6000" "6000" "6000"
                           "6000" "6000" "6024" "35" "5a" "f1" "50" "5a" "90" "03" "81" "6005" "1b" "52" "6001"
                           "01" "6008" "56" "5b" "50" "6005" "1b" "6000" "f3")};
    const Effects e = evm(d.code, args({3, 0x1234}));
    REQUIRE(e.end.status == Status::return_);
    REQUIRE(e.end.data.size() == 96);
    for (unsigned i = 0; i < 3; ++i)
        CHECK(load_word(e.end.data, 32 * i) == gas_word(gas_read_cost + gas_event_cost));
    d.check({args({0, 0x1234}), args({1, 0x1234}), args({3, 0x1234}), args({2, 0})});
    INFO(d.text);
    // the read before the call is in the loop, not before it
    const auto loop = d.text.find("while ");
    const auto read = d.text.find(" = gas_remaining");
    REQUIRE(loop != std::string::npos);
    REQUIRE(read != std::string::npos);
    CHECK(loop < read);
}

TEST_CASE("gas reads: a loop that waits for the gas to run low stays a loop (c00460)")
{
    // Burn.gas as solc 0.8 makes it, with its helpers: amount =
    // calldataload(4) & 0xffff; initial = gas; i = 0; while (sub(initial,
    // gas) < amount) i = inc(i); mstore(0, i); return(0, 32) - sub: x - y,
    // revert where y > x; inc: x + 1, revert where x = 2^256 - 1. (The tree
    // before read the subtraction's check once, before the loop, and the
    // condition's read in it: a read more than the code's.)
    const QuietLog quiet;
    Decompile d{*parse_hex("60043561ffff166000805a9050" "5b825a601790836033565b10156029576023826043565b9150600d56"
                           "5b5060005260206000f3" "5b81811015603f57600080fd5b039056" "5b8019604d57600080fd5b6001019056")};
    // initial - gas is gas_read_cost at the first test, then more by as much at each
    CHECK(returned(evm(d.code, args({0}))) == gas_word(0));
    CHECK(returned(evm(d.code, args({15}))) == gas_word(1));
    CHECK(returned(evm(d.code, args({500}))) == gas_word(49));
    d.check({args({0}), args({15}), args({500}), args({0xffff})});
    INFO(d.text);
    CHECK(d.text.find("while") != std::string::npos);
}

TEST_CASE("gas reads: the trace machine asks the host at every read")
{
    Ctx cx;
    // two reads differ; a read in a loop is read at every iteration - the
    // same read taken out of the loop gives another end
    const auto two = run_trace(pan::V("{(setvar tmp1 gas) (setvar tmp2 gas) (setmem (range 0 32) (sub tmp1 tmp2))"
                                      " (return (mem (range 0 32)))}"));
    REQUIRE(two.first == pan::exec::Status::Return);
    CHECK(pan::Word256::from_be(two.second) == pan::Word256::of(7));
    const char* in_loop =
        "{(setvar tmp1 gas) (while (lt (sub tmp1 tmp2) 30) {(setvar tmp2 gas) (continue loopid1 {(setvar loop1 (add loop1"
        " 1))})} loopid1 {(setvar loop1 0) (setvar tmp2 gas)}) (setmem (range 0 32) loop1) (return (mem (range 0 32)))}";
    const char* hoisted =
        "{(setvar tmp1 gas) (setvar tmp3 gas) (while (lt (sub tmp1 tmp2) 30) {(setvar tmp2 tmp3) (continue loopid1"
        " {(setvar loop1 (add loop1 1))})} loopid1 {(setvar loop1 0) (setvar tmp2 tmp3)}) (setmem (range 0 32) loop1)"
        " (return (mem (range 0 32)))}";
    const auto a = run_trace(pan::V(in_loop));
    REQUIRE(a.first == pan::exec::Status::Return);
    CHECK(pan::Word256::from_be(a.second) == pan::Word256::of(4));
    const auto b = run_trace(pan::V(hoisted));
    CHECK(b != a);  // (it never ends: exhausted)
    // an expression reading gas isn't remembered from one line to the next
    const auto again = run_trace(pan::V("{(if (lt (add gas 0) 999999) {(revert None)} {})"
                                        " (if (lt (add gas 0) 999999) {(stop)} {(revert None)})}"));
    CHECK(again.first == pan::exec::Status::Stop);
}

TEST_CASE("gas reads: every line consumes gas - a read is moved past none")
{
    Ctx cx;
    const pan::Value read = pan::V("(setvar tmp1 gas)");
    const pan::Value set = pan::V("(setvar tmp2 (add tmp3 1))");
    const pan::Value mem = pan::V("(setmem (range 0 32) 5)");
    CHECK(pan::simplify::affects(set, pan::V("(add gas 1)")));
    CHECK(pan::simplify::affects(mem, pan::V("gas")));
    CHECK(!pan::simplify::independent(read, set));
    CHECK(!pan::simplify::independent(mem, read));
    // two lines that only consume it: either order
    CHECK(pan::simplify::independent(set, pan::V("(setvar tmp4 (add tmp5 2))")));
}

TEST_CASE("gas reads: a read printed in the next line when it alone uses it, once")
{
    Ctx cx;
    struct Case
    {
        const char* trace;
        bool inlined;
    };
    const Case cases[] = {
        {"{(setvar tmp1 gas) (if (lt tmp1 999990) {(revert None)} {}) (stop)}", true},
        {"{(setvar tmp1 gas) (setmem (range 0 32) (add tmp1 1)) (return (mem (range 0 32)))}", true},
        // a line between them: the variable stays
        {"{(setvar tmp1 gas) (setmem (range 32 32) gas) (setmem (range 0 32) tmp1) (return (mem (range 0 64)))}",
            false},
        // read twice in the line, or by another line
        {"{(setvar tmp1 gas) (setmem (range 0 32) (sub tmp1 (div tmp1 64))) (return (mem (range 0 32)))}", false},
        {"{(setvar tmp1 gas) (setmem (range 0 32) tmp1) (setmem (range 32 32) tmp1) (return (mem (range 0 64)))}",
            false},
        // on the right of an `and`, in a loop's condition, in a branch
        {"{(setvar tmp1 gas) (if (land calldatasize (lt tmp1 999990)) {(revert None)} {}) (stop)}", false},
        {"{(setvar tmp1 gas) (while (lt tmp1 0) {(continue loopid1 {})} loopid1 {}) (stop)}", false},
        {"{(setvar tmp1 gas) (if calldatasize {(setmem (range 0 32) tmp1) (return (mem (range 0 32)))} {}) (stop)}",
            false},
    };
    for (const Case& c : cases)
    {
        INFO(c.trace);
        const pan::Value t = pan::V(c.trace);
        const pan::Value r = pan::output::inline_gas_reads(t);
        INFO(pan::dump_trace(r));
        CHECK((r != t) == c.inlined);
        // the same run, the gas left going down at every read
        CHECK(run_trace(r) == run_trace(t));
    }
}
