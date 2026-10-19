// The trace machine against evmone (lot 11, validate/stage_check.hpp): small
// bytecodes run by evmone and their traces, written by hand, run by the
// machine through a SessionHost on the same worlds - the effects the same;
// then check_contract end to end on a hand-made pipeline.
#include "validate/stage_check.hpp"

#include "core/context.hpp"
#include "core/dump.hpp"
#include "validate_test_util.hpp"

#include <optional>
#include <string_view>
#include <vector>

using namespace validate;

namespace
{
Bytes bytes(std::string_view s)
{
    return *parse_hex(s);
}

Bytes cat(std::initializer_list<Bytes> parts)
{
    Bytes out;
    for (const auto& p : parts)
        out.insert(out.end(), p.begin(), p.end());
    return out;
}

Bytes word(const Word& w)
{
    const auto b = to_bytes(w);
    return {b.begin(), b.end()};
}

/// a context of its own for the Values of a test
struct Context
{
    pan::Budget budget{pan::Budget::Limits{}};
    std::unique_ptr<pan::Context> ctx;
    std::optional<pan::ContextScope> scope;
    Context()
    {
        pan::init();
        budget.attach_thread();
        ctx = pan::Context::create(budget);
        scope.emplace(*ctx);
    }
    ~Context()
    {
        scope.reset();
        ctx.reset();
        budget.detach_thread();
    }
};

pan::FunctionInfo function(std::optional<std::uint32_t> selector, std::string_view trace)
{
    pan::FunctionInfo f;
    f.kind = selector ? pan::FunctionInfo::Kind::Selector : pan::FunctionInfo::Kind::Fallback;
    f.selector = selector.value_or(0);
    f.entry.selector = selector;
    f.trace = pan::V(trace);
    return f;
}

/// A bytecode and its decompiled functions, run on both sides.
struct Pair
{
    Context cx;
    Bytes code;
    std::vector<pan::FunctionInfo> functions;
    std::vector<pan::FunctionInfo> internals;

    /// the call on both sides from the same state of a world: (evmone's, the machine's)
    std::pair<Effects, Effects> run(bool random, Bytes calldata, Word value = 0, std::uint64_t seed = 3)
    {
        const SeededWorld world{{.seed = seed, .random = random}};
        const CallContext context{world.actors()[0], world.actors()[0], value, 1, std::move(calldata)};
        State evm_state{world, world.contract_address(), code};
        EvmRunner runner{code};
        auto expected = runner.run(evm_state, context);
        State state{world, world.contract_address(), code};
        Session session{state, context};
        pan::exec::Program p;
        p.functions = functions;
        p.internals = internals;
        pan::exec::Machine m{p};
        pan::exec::Outcome o;
        auto actual = run_machine(m, session, std::nullopt, &o);
        INFO("machine: ", pan::exec::status_name(o.status), " ", o.note);
        return {std::move(expected), std::move(actual)};
    }

    /// the same on both worlds, for each calldata
    void check(std::initializer_list<Bytes> calldatas, Word value = 0)
    {
        for (const bool random : {false, true})
            for (const auto& cd : calldatas)
            {
                const auto [expected, actual] = run(random, cd, value);
                const auto c = compare(expected, actual, {.transient = true, .precompiles = true});
                INFO((random ? "random" : "empty"), " world, calldata ", hex(cd));
                INFO("evm:\n", to_string(expected), "machine:\n", to_string(actual));
                CHECK(c.verdict == Verdict::same);
                CHECK(!expected.end.inconclusive());
            }
    }
};

Bytes calldata(std::uint32_t selector, std::initializer_list<Word> words = {})
{
    Bytes b{static_cast<std::uint8_t>(selector >> 24), static_cast<std::uint8_t>(selector >> 16),
        static_cast<std::uint8_t>(selector >> 8), static_cast<std::uint8_t>(selector)};
    for (const auto& w : words)
        b = cat({b, word(w)});
    return b;
}
}  // namespace

TEST_CASE("stagecheck: the machine and evmone, a return of memory")
{
    Pair p;
    // PUSH1 0x2a PUSH1 0 MSTORE PUSH1 0x20 PUSH1 0 RETURN
    p.code = bytes("602a60005260206000f3");
    p.functions.push_back(function(std::nullopt, "{(setmem (range 0 32) 42) (return (mem (range 0 32)))}"));
    p.check({{}, calldata(0x12345678)});
}

TEST_CASE("stagecheck: the machine and evmone, storage and a log")
{
    Pair p;
    // sstore(0, calldataload(4)); mstore(0, caller); log1(0, 32, 0xdead); stop
    p.code = bytes("6004356000553360005261dead60206000a100");
    p.functions.push_back(function(std::nullopt,
        "{(store 256 0 0 (calldataload 4)) (setmem (range 0 32) caller) (log1 (mem (range 0 32)) 0xdead) (stop)}"));
    p.check({calldata(1, {7}), calldata(1, {0}), {}});
}

TEST_CASE("stagecheck: the machine and evmone, an external call and its return data")
{
    Pair p;
    // call(0xffff, calldataload(4), 0, 0, 0, 0, 0); pop; returndatacopy(0, 0,
    // returndatasize); return(0, returndatasize)
    p.code = bytes("6000600060006000600060043561fffff1503d600060003e3d6000f3");
    p.functions.push_back(function(std::nullopt,
        "{(call 1 gas (calldataload 4) 0 None None)"
        " (setmem (range 0 (returndatasize 1)) (returndata_bytes 1 0 (returndatasize 1)))"
        " (return (mem (range 0 (returndatasize 1))))}"));
    p.check({calldata(1, {0x1234567890}), calldata(1, {0xdeadbeef}), calldata(1, {2})});
    // the success flag and the return data's size
    Pair q;
    // success = call(...); mstore(32, success); mstore(0, returndatasize); return(0, 64)
    q.code = bytes("6000600060006000600060043561fffff16020523d60005260406000f3");
    q.functions.push_back(function(std::nullopt,
        "{(call 1 gas (calldataload 4) 0 None None) (setmem (range 32 32) (call_success 1))"
        " (setmem (range 0 32) (returndatasize 1)) (return (mem (range 0 64)))}"));
    q.check({calldata(1, {0x1234567890}), calldata(1, {77})});
}

TEST_CASE("stagecheck: the machine and evmone, Error(string)")
{
    Pair p;
    // mstore(0, 0x08c379a0 << 224); mstore(4, 32); mstore(36, 1); mstore(68,
    // "x" << 248); revert(0, 100)
    p.code = bytes("6308c379a060e01b600052602060045260016024526078" "60f81b6044526064" "6000fd");
    p.functions.push_back(function(std::nullopt,
        "{(revert (data (sized 4 0x08c379a0) 32 1 (sized 32 "
        "0x7800000000000000000000000000000000000000000000000000000000000000)))}"));
    p.check({{}});
}

TEST_CASE("stagecheck: the machine and evmone, a mapping's slot")
{
    Pair p;
    // mstore(0, caller); mstore(32, 1); k = sha3(0, 64); sstore(k, sload(k) + 7); stop
    p.code = bytes("33600052600160205260406000208054600701905500");
    p.functions.push_back(
        function(std::nullopt, "{(store 256 0 (sha3 caller 1) (add 7 (storage 256 0 (sha3 caller 1)))) (stop)}"));
    p.check({{}});
}

TEST_CASE("stagecheck: the machine and evmone, a loop as while and as label/goto")
{
    // n = calldataload(4) & 0xff; sum = 0; for (i = 0; i < n; i++) sum += i; return sum
    const auto code = bytes("60043560ff16600060005b828110" "15601c57" "80910190" "600101600a56" "5b50600052"
                            "60206000f3");
    const char* whiles =
        "{(setvar tmp1 (mask_shl 8 0 0 (calldataload 4)))"
        " (while (lt loop2 tmp1) {(continue loopid1 {(setvar loop1 (add loop1 loop2)) (setvar loop2 (add loop2 1))})}"
        "  loopid1 {(setvar loop1 0) (setvar loop2 0)})"
        " (setmem (range 0 32) loop1) (return (mem (range 0 32)))}";
    const char* raw =
        "{(setvar tmp1 (mask_shl 8 0 0 (calldataload 4)))"
        " (label loopid1 {(setvar loop1 0) (setvar loop2 0)})"
        " (if (lt loop2 tmp1) {(goto loopid1 {(setvar loop1 (add loop1 loop2)) (setvar loop2 (add loop2 1))})}"
        "  {(setmem (range 0 32) loop1) (return (mem (range 0 32)))})}";
    for (const char* trace : {whiles, raw})
    {
        Pair p;
        p.code = code;
        p.functions.push_back(function(std::nullopt, trace));
        p.check({calldata(1, {0}), calldata(1, {1}), calldata(1, {10}), calldata(1, {0x1ff})});
    }
}

TEST_CASE("stagecheck: the machine and evmone, a dispatcher, nonpayable")
{
    Pair p;
    // sel = calldataload(0) >> 224; 0xaabbccdd -> f1 (nonpayable: return 1);
    // 0x11223344 -> f2 (return 2); else revert(0, 0)
    p.code = bytes("60003560e01c8063aabbccdd14601e57806311223344146033576000" "80fd5b3415602857600080fd5b6001600052"
                   "60206000f35b600260005260206000f3");
    p.functions.push_back(function(0xaabbccdd, "{(setmem (range 0 32) 1) (return (mem (range 0 32)))}"));
    p.functions.back().entry.nonpayable = true;
    p.functions.push_back(function(0x11223344, "{(setmem (range 0 32) 2) (return (mem (range 0 32)))}"));
    p.functions.push_back(function(std::nullopt, "{(revert None)}"));
    p.check({calldata(0xaabbccdd), calldata(0x11223344, {5}), calldata(0x99999999), {}, bytes("aabbcc")});
    p.check({calldata(0xaabbccdd), calldata(0x11223344)}, 1'000);
}

TEST_CASE("stagecheck: the machine and evmone, the context")
{
    Pair p;
    // mstore(0, timestamp + number + chainid + selfbalance + gas + callvalue + caller); return(0, 32)
    p.code = bytes("424301460147015a013401330160005260206000f3");
    p.functions.push_back(function(std::nullopt,
        "{(setmem (range 0 32) (add timestamp number chainid selfbalance gas callvalue caller))"
        " (return (mem (range 0 32)))}"));
    p.check({{}}, 0);
    p.check({{}}, 5);
    Pair q;
    // mstore(0, extcodesize(a) + balance(a) + extcodehash(a)) with a = calldataload(4); return(0, 32)
    q.code = bytes("6004353b600435310160043531" "3f" "0160005260206000f3");
    // (extcodehash of the balance: what the bytecode computes)
    q.functions.push_back(function(std::nullopt,
        "{(setmem (range 0 32) (add (extcodesize (calldataload 4)) (balance (calldataload 4))"
        " (extcodehash (balance (calldataload 4))))) (return (mem (range 0 32)))}"));
    q.check({calldata(1, {0x1234567890}), calldata(1, {3})});
}

TEST_CASE("stagecheck: the machine and evmone, transient storage, calldata copies, creations")
{
    Pair p;
    // tstore(1, 5); mstore(0, tload(1)); return(0, 32)
    p.code = bytes("600560015d60015c60005260206000f3");
    p.functions.push_back(function(std::nullopt, "{(tstore 1 5) (setmem (range 0 32) (tload 1)) (return (mem (range 0 32)))}"));
    p.check({{}});
    Pair q;
    // calldatacopy(0, 0, calldatasize); return(0, calldatasize)
    q.code = bytes("366000600037366000f3");
    q.functions.push_back(function(std::nullopt,
        "{(setmem (range 0 calldatasize) (calldata_bytes 0 calldatasize)) (return (mem (range 0 calldatasize)))}"));
    q.check({{}, bytes("01"), calldata(0xabcdef01, {1, 2, 3})});
    Pair r;
    // mstore(0, create(0, 0, 0)); return(0, 32)
    r.code = bytes("600060006000f060005260206000f3");
    r.functions.push_back(function(std::nullopt,
        "{(create 1 0 None) (setmem (range 0 32) (create_address 1)) (return (mem (range 0 32)))}"));
    r.check({{}});
}

TEST_CASE("stagecheck: a different trace is found different")
{
    Pair p;
    p.code = bytes("602a60005260206000f3");
    p.functions.push_back(function(std::nullopt, "{(setmem (range 0 32) 43) (return (mem (range 0 32)))}"));
    const auto [expected, actual] = p.run(false, {});
    CHECK(compare(expected, actual).verdict == Verdict::different);
    // a bug of the trace: an error end, inconclusive for compare()
    Pair q;
    q.code = bytes("602a60005260206000f3");
    q.functions.push_back(function(std::nullopt, "{(return tmp1)}"));
    const auto [e2, a2] = q.run(false, {});
    CHECK(a2.end.status == Status::error);
}

TEST_CASE("stagecheck: check_contract on a hand-made pipeline")
{
    // the dispatcher of the test above; its raw stage made by hand, one
    // function right, one wrong
    const auto code = bytes("60003560e01c8063aabbccdd14601e57806311223344146033576000"
                            "80fd5b3415602857600080fd5b600160005260206000f35b600260005260206000f3");
    const Pipeline pipeline = [](Decompiled& c, Stage, pan::Budget&) {
        auto& fns = c.functions[0];
        fns.push_back(function(0xaabbccdd, "{(if callvalue {(revert None)} {}) (setmem (range 0 32) 1)"
                                           " (return (mem (range 0 32)))}"));
        fns.push_back(function(0x11223344, "{(setmem (range 0 32) 3) (return (mem (range 0 32)))}"));
        fns.push_back(function(std::nullopt, "{(revert None)}"));
        c.made[0] = true;
    };
    CheckConfig config;
    config.calls.probe = false;
    const auto report = check_contract(code, config, pipeline);
    INFO(summary(report));
    REQUIRE(report.ran);
    CHECK(report.functions == 3);
    const auto& raw = report.stages[0];
    CHECK(raw.ran);
    CHECK(!report.stages[1].ran);
    CHECK(raw.same > 0);
    CHECK(raw.different > 0);  // 0x11223344's calls
    CHECK(raw.by_category[static_cast<unsigned>(Category::end_data)] == raw.different);
    CHECK(raw.bugs == 0);
    REQUIRE(report.first_divergent);
    CHECK(*report.first_divergent == Stage::raw);
    REQUIRE(!raw.examples.empty());
    CHECK(raw.examples[0].call.find("0x11223344") != std::string::npos);

    // a pipeline that fails: the report says why
    const Pipeline failing = [](Decompiled&, Stage, pan::Budget&) { throw pan::Unsupported("no"); };
    const auto failed = check_contract(code, config, failing);
    CHECK(!failed.ran);
    CHECK(failed.failure.find("no") != std::string::npos);
}

TEST_CASE("stagecheck: the options and the stages' names")
{
    CHECK(stagecheck_option("--stage") == StagecheckOption::stage);
    CHECK(stagecheck_option("-j") == StagecheckOption::jobs);
    CHECK(stagecheck_option("--jobs") == StagecheckOption::jobs);
    CHECK(stagecheck_option("--stag") == StagecheckOption::none);
    CHECK(stagecheck_option("--stagex") == StagecheckOption::none);
    CHECK(stagecheck_option("file.hex") == StagecheckOption::none);
    CHECK(parse_stage("raw") == Stage::raw);
    CHECK(parse_stage("folded") == Stage::folded);
    CHECK(!parse_stage("fold"));
    CHECK(!parse_stage(""));
}
