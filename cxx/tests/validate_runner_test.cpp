// validate/evm_runner.hpp: evmone against the world, its effects; and the
// same effects made by hand through a Session, the way the interpreters of
// the decompiled code make them.
#include "validate/calls.hpp"
#include "validate/evm_runner.hpp"

#include "validate_test_util.hpp"

using namespace validate;

namespace
{
Bytes bytes(std::string_view s)
{
    return *parse_hex(s);
}

struct Fixture
{
    SeededWorld world;
    explicit Fixture(bool random = true) : world{{.seed = 21, .random = random}} {}

    CallContext context(Bytes calldata = {}, Word value = 0) const
    {
        return {world.actors()[0], world.actors()[0], value, 1, std::move(calldata)};
    }

    Effects run(std::string_view code, Bytes calldata = {}, Word value = 0, std::int64_t gas = 1'000'000) const
    {
        const auto c = bytes(code);
        State state{world, world.contract_address(), c};
        EvmRunner runner{c, {gas}};
        return runner.run(state, context(std::move(calldata), value));
    }
};
}  // namespace

TEST_CASE("validate: evmone, storage and stop")
{
    const Fixture f{false};
    // PUSH1 0x2a PUSH1 0 SSTORE STOP
    const auto e = f.run("0x602a60005500");
    CHECK(e.end.status == Status::stop);
    REQUIRE(e.events.size() == 1);
    CHECK(std::get<StorageWrite>(e.events[0]) == StorageWrite{0, 0x2a});
    CHECK(e.storage_diff == std::map<Word, Word>{{0, 0x2a}});
}

TEST_CASE("validate: evmone, GAS gives fixed_gas")
{
    const Fixture f;
    // GAS PUSH1 0 MSTORE PUSH1 32 PUSH1 0 RETURN
    const auto e = f.run("0x5a60005260206000f3");
    REQUIRE(e.end.status == Status::return_);
    CHECK(load_word(e.end.data, 0) == fixed_gas);
}

TEST_CASE("validate: evmone, the ends")
{
    const Fixture f;
    // PUSH1 0xff PUSH1 0 MSTORE8 PUSH1 1 PUSH1 0 REVERT
    auto e = f.run("0x60ff60005360016000fd");
    CHECK(e.end.status == Status::revert);
    CHECK(e.end.data == bytes("0xff"));
    CHECK(f.run("0xfe").end.fault == Fault::invalid_instruction);
    CHECK(f.run("0x0c").end.fault == Fault::undefined_instruction);
    CHECK(f.run("0x600356").end.fault == Fault::bad_jump);
    CHECK(f.run("0x01").end.fault == Fault::stack_underflow);
    CHECK(f.run("0x01").end.status == Status::invalid);
    // RETURNDATACOPY past the return data
    CHECK(f.run("0x6001600060003e").end.fault == Fault::memory_access);
    // JUMPDEST PUSH1 0 JUMP: out of gas
    CHECK(f.run("0x5b600056", {}, 0, 100'000).end.status == Status::exhausted);
    // a memory offset of 2^32: out of gas too
    CHECK(f.run("0x640100000000510000").end.status == Status::exhausted);
    // the end of the code
    CHECK(f.run("0x6001").end.status == Status::stop);
}

TEST_CASE("validate: evmone, an external call answered by the world")
{
    const Fixture f;
    // mstore(0, 0xa9059cbb); success = call(gas, 0x1234, 0, 28, 4, 0, 0);
    // sstore(0, success); return(returndata)
    const auto program = "0x63a9059cbb600052600060006004601c60006112345af16000553d600060003e3d6000f3";
    const auto e = f.run(program);
    const auto input = bytes("0xa9059cbb");
    const auto expected = f.world.code(0x1234).empty() ? CallResult{true, {}} :
                                                         f.world.call(CallKind::call, 0x1234, 0, input);
    REQUIRE(e.events.size() == 2);
    const auto& call = std::get<ExternalCall>(e.events[0]);
    CHECK(call.kind == CallKind::call);
    CHECK(call.target == 0x1234);
    CHECK(call.input == input);
    CHECK(call.result == expected);
    CHECK(std::get<StorageWrite>(e.events[1]).value == Word{expected.success});
    CHECK((e.end.data == expected.output));

    // the same effects, by hand: what an interpreter of the decompiled code does
    State state{f.world, f.world.contract_address(), bytes(program)};
    Session s{state, f.context()};
    const auto r = s.call(CallKind::call, 0x1234, 0, input);
    s.sstore(0, r.success ? 1 : 0);
    const auto mine = s.finish(End::returned(r.output));
    const auto c = compare(e, mine);
    CHECK(c.verdict == Verdict::same);
    CHECK(c.message == "");
}

TEST_CASE("validate: evmone, the kinds of calls")
{
    const Fixture f;
    // STATICCALL(gas, 0x99, 0, 0, 0, 0), DELEGATECALL(gas, 0x98, 0, 0, 0, 0),
    // CALLCODE(gas, 0x97, 0, 0, 0, 0, 0), then a precompile: identity
    const auto e = f.run(
        "0x600060006000600060995afa50"
        "600060006000600060985af450"
        "6000600060006000600060975af250"
        "600060006000600060045afa50");
    REQUIRE(e.events.size() == 4);
    CHECK(std::get<ExternalCall>(e.events[0]).kind == CallKind::staticcall);
    CHECK(std::get<ExternalCall>(e.events[0]).target == 0x99);
    CHECK(std::get<ExternalCall>(e.events[1]).kind == CallKind::delegatecall);
    CHECK(std::get<ExternalCall>(e.events[1]).target == 0x98);
    CHECK(std::get<ExternalCall>(e.events[2]).kind == CallKind::callcode);
    CHECK(std::get<ExternalCall>(e.events[2]).target == 0x97);
    CHECK(std::get<ExternalCall>(e.events[3]).precompile);
}

TEST_CASE("validate: evmone, a call with more value than the balance never reaches the world")
{
    const Fixture f{false};  // the contract's balance: 0
    // CALL(gas, 0x1234, 1, 0, 0, 0, 0); SSTORE(0, success)
    const auto e = f.run("0x60006000600060006001611234" "5af160005500");
    REQUIRE(e.events.size() == 1);
    CHECK(std::get<StorageWrite>(e.events[0]).value == 0);
    // with a value of the call to pay it, it does
    const auto paid = f.run("0x60006000600060006001611234" "5af160005500", {}, 1);
    REQUIRE(paid.events.size() == 2);
    CHECK(std::get<ExternalCall>(paid.events[0]).value == 1);
}

TEST_CASE("validate: evmone, logs, transient storage, the context")
{
    const Fixture f;
    // MSTORE(0, 1); LOG2(0, 32, 1, 2); TSTORE(1, 5); MSTORE(0, TLOAD(1)); RETURN(0, 32)
    const auto e = f.run("0x60016000526002600160206000a2" "600560015d" "60015c60005260206000f3");
    REQUIRE(e.events.size() == 2);
    const auto& log = std::get<Log>(e.events[0]);
    CHECK(log.topics == std::vector<Word>{1, 2});
    const auto one = to_bytes(1);
    CHECK(log.data == Bytes(one.begin(), one.end()));
    CHECK(std::get<TransientWrite>(e.events[1]) == TransientWrite{1, 5});
    CHECK(load_word(e.end.data, 0) == 5);

    // SELFBALANCE, CALLER, CALLVALUE, NUMBER, CHAINID: MSTOREs, RETURN(0, 160)
    const auto c = f.run("0x4760005233602052346040524360605246608052" "60a06000f3", {}, 3);
    CHECK(load_word(c.end.data, 0) == f.world.balance(f.world.contract_address()) + 3);
    CHECK(load_word(c.end.data, 32) == f.world.actors()[0]);
    CHECK(load_word(c.end.data, 64) == 3);
    CHECK(load_word(c.end.data, 96) == f.world.block().number);
    CHECK(load_word(c.end.data, 128) == 1);

    // BLOCKHASH(NUMBER - 1)
    const auto b = f.run("0x600143034060005260206000f3");
    CHECK(load_word(b.end.data, 0) == f.world.block_hash(f.world.block().number - 1));
}

TEST_CASE("validate: evmone, creations and selfdestruct")
{
    const Fixture f;
    const auto self = f.world.contract_address();
    // CREATE(0, 0, 0); SSTORE(0, it); CREATE2(0, 0, 0, salt 7); SSTORE(1, it); SELFDESTRUCT(0x5555)
    const auto e = f.run("0x600060006000f0600055" "6007600060006000f5600155" "615555ff");
    REQUIRE(e.events.size() == 5);
    const auto& c1 = std::get<Creation>(e.events[0]);
    CHECK(c1.kind == CreateKind::create);
    CHECK(c1.address == create_address(self, 1));
    CHECK(std::get<StorageWrite>(e.events[1]).value == (c1.result.success ? c1.address : 0));
    const auto& c2 = std::get<Creation>(e.events[2]);
    CHECK(c2.kind == CreateKind::create2);
    CHECK(c2.address == create2_address(self, 7, {}));
    CHECK_FALSE(c2.salt.has_value());  // evmone doesn't tell it
    CHECK(std::get<SelfDestruct>(e.events[4]).beneficiary == 0x5555);
    CHECK(e.end.status == Status::stop);
}

TEST_CASE("validate: evmone, a sequence carries the storage over")
{
    const Fixture f{false};
    // no calldata: SSTORE(1, 7), STOP; calldata: RETURN(SLOAD(1))
    const auto code = bytes("0x36600a57600760015500" "5b60015460005260206000f3");
    State state{f.world, f.world.contract_address(), code};
    EvmRunner runner{code};
    const std::vector<CallContext> calls{f.context(), f.context(bytes("0x01"))};
    const auto e = runner.run(state, calls);
    REQUIRE(e.size() == 2);
    CHECK(e[0].storage_diff == std::map<Word, Word>{{1, 7}});
    CHECK(load_word(e[1].end.data, 0) == 7);
    CHECK(state.storage(1) == 7);

    // a reverted call leaves nothing: SSTORE(2, 9), REVERT(0, 0)
    const auto reverting = bytes("0x600960025560006000fd");
    State s2{f.world, f.world.contract_address(), reverting};
    EvmRunner r2{reverting};
    const auto e2 = r2.run(s2, f.context());
    CHECK(e2.end.status == Status::revert);
    CHECK(e2.events.size() == 1);
    CHECK(e2.storage_diff.empty());
    CHECK(s2.storage(2) == 0);
}

TEST_CASE("validate: evmone, the runs are deterministic")
{
    const Fixture f;
    // keccak of the calldata as a slot: SSTORE(keccak(calldata), CALLER), RETURN(SLOAD(that))
    const auto code = "0x366000600037366000205a5033815560005460005260206000f3";
    const auto a = f.run(code, bytes("0x0102"));
    const auto b = f.run(code, bytes("0x0102"));
    CHECK(compare(a, b).verdict == Verdict::same);
    CHECK(compare(a, b, {.write_order = true, .transient = true, .precompiles = true,
                            .failed_events = true, .faults = true})
              .verdict == Verdict::same);
}
