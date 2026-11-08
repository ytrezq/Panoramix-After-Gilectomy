// The dispatcher read as the machine runs it (vm/discover.cpp; DESIGN.md,
// "Nothing assumed of the compiler"): the trace machine (and the printed
// text's interpreter) dispatches by the first 4 bytes of calldata of 4 bytes
// or more, else to the default function - so a test the discovery takes for a
// selector's must be one for every call, and the default function where every
// other call goes. Hand-assembled dispatchers that aren't solc's, decompiled
// by the pipeline and run by evmone and by the trace machine on every stage's
// traces, on the calls that tell them apart.
#include "validate/stage_check.hpp"

#include "core/context.hpp"
#include "core/dump.hpp"
#include "driver/pipeline.hpp"
#include "validate_test_util.hpp"

#include <memory>
#include <optional>
#include <string_view>
#include <vector>

using namespace validate;

namespace
{
struct Call
{
    Bytes calldata;
    Word value = 0;
    bool inconclusive = false;  ///< the machine may give up (UNDEFINED): never different
};

Bytes bytes(std::string_view s)
{
    return *parse_hex(s);
}

Bytes with_selector(std::uint32_t sel, std::size_t extra = 32)
{
    Bytes b{static_cast<std::uint8_t>(sel >> 24), static_cast<std::uint8_t>(sel >> 16),
        static_cast<std::uint8_t>(sel >> 8), static_cast<std::uint8_t>(sel)};
    b.resize(4 + extra, 0x11);
    return b;
}

/// The log quiet for a test (the driver's INFO lines), as it was after
struct QuietLog
{
    int saved = pan::log_level();
    QuietLog() { pan::set_log_level(pan::log_critical); }
    ~QuietLog() { pan::set_log_level(saved); }
};

/// The code decompiled by the pipeline (driver::run_until, every stage
/// kept): its functions (the last stage's selectors, then the default one)
/// and every stage's calls the same as evmone's, on the empty and a random
/// world.
std::vector<std::uint32_t> check_dispatch(std::string_view code_hex, std::initializer_list<Call> calls)
{
    const QuietLog quiet;
    pan::init();
    pan::Budget budget{pan::Budget::Limits{}};
    budget.attach_thread();
    std::vector<std::uint32_t> selectors;
    {
        Decompiled contract{bytes(code_hex)};
        auto ctx = pan::Context::create(budget, &contract.shared);
        pan::ContextScope scope{*ctx};
        pan::driver::PipelineOptions o;
        o.threads = 1;
        o.keep = pan::driver::KEEP_ALL;
        const auto r = pan::driver::run_until(contract.code, pan::driver::Stage::Folded, o);
        for (unsigned s = 0; s < stage_count; ++s)
            if (r.kept[s])
            {
                contract.functions[s] = r.functions[s];
                contract.internals[s] = r.internals[s];
                contract.made[s] = true;
            }
        contract.storage = r.storage;
        contract.safemath = r.safemath;
        for (const auto& f : r.final_functions())
            if (f.kind == pan::FunctionInfo::Kind::Selector)
                selectors.push_back(f.selector);
        for (unsigned s = 0; s < stage_count; ++s)
        {
            REQUIRE(contract.made[s]);
            pan::exec::Program p;
            p.functions = contract.functions[s];
            p.internals = contract.internals[s];
            p.shared = &contract.shared;
            p.layout = contract.storage.get();
            p.safemath = contract.safemath.get();
            for (const bool random : {false, true})
                for (const Call& c : calls)
                {
                    const SeededWorld world{{.seed = 3, .random = random}};
                    const CallContext context{world.actors()[0], world.actors()[0], c.value, 1, c.calldata};
                    State evm_state{world, world.contract_address(), contract.code};
                    EvmRunner runner{contract.code};
                    const Effects expected = runner.run(evm_state, context);
                    State state{world, world.contract_address(), contract.code};
                    Session session{state, context};
                    pan::exec::Machine m{p};
                    pan::exec::Outcome out;
                    const Effects actual = run_machine(m, session, std::nullopt, &out);
                    const auto v = compare(expected, actual, {.transient = true, .precompiles = true});
                    INFO("stage ", stage_name(static_cast<Stage>(s)), (random ? ", random" : ", empty"),
                        " world, calldata ", hex(c.calldata), " value ", hex(c.value));
                    INFO("evm:\n", to_string(expected), "machine (", pan::exec::status_name(out.status), " ", out.note,
                        "):\n", to_string(actual));
                    CHECK(!expected.end.inconclusive());
                    if (c.inconclusive && v.verdict == Verdict::inconclusive)
                        continue;
                    CHECK(v.verdict == Verdict::same);
                }
        }
    }
    budget.detach_thread();
    return selectors;
}
}  // namespace

TEST_CASE("vm dispatch: a dispatcher on the first byte has no selectors")
{
    // cmd = byte(0, calldataload(0)); cmd == 1 -> return 1; else return 2 (the
    // test reads the calldata, but not its first 4 bytes as a number: the
    // calls of 0x00000001 return 2, those of 0x01... return 1)
    const auto sels = check_dispatch("600035" "60001a" "80" "600114" "601857" "50" "6002600052" "60206000f3"
                                     "5b" "6001600052" "60206000f3",
        {{with_selector(0x00000001)}, {with_selector(0x01000000)}, {with_selector(0x01ffffff)}, {bytes("01")}, {{}}});
    CHECK(sels.empty());
}

TEST_CASE("vm dispatch: a selector test and'ed with another condition than the calldata's size is none")
{
    // sel == 0xaabbccdd and callvalue == 0 -> return 1; else return 2: with a
    // value, the calls of 0xaabbccdd return 2
    const auto sels = check_dispatch("600035" "60e01c" "63aabbccdd14" "341516" "601c57" "6002600052" "60206000f3"
                                     "5b" "6001600052" "60206000f3",
        {{with_selector(0xaabbccdd)}, {with_selector(0xaabbccdd), 5}, {with_selector(0x12345678)}, {{}}});
    CHECK(sels.empty());
}

TEST_CASE("vm dispatch: Vyper's calldatasize > 3 and'ed with the test: the selector's")
{
    // sel == 0xaabbcc00 and calldatasize > 3 -> return 1; else revert
    const auto sels = check_dispatch("600035" "60e01c" "63aabbcc0014" "600336" "11" "16" "601857" "600080fd"
                                     "5b" "6001600052" "60206000f3",
        {{with_selector(0xaabbcc00)}, {with_selector(0xaabbcc00, 0)}, {bytes("aabbcc")}, {with_selector(0x12345678)},
            {{}}});
    CHECK(sels == std::vector<std::uint32_t>{0xaabbcc00});
}

TEST_CASE("vm dispatch: calldata of fewer than 4 bytes reads as its bytes then zeroes")
{
    // no size check: sel == 0xaabbcc00 -> return 1; else revert. The 3 bytes
    // aabbcc are that selector's call: not a function the machine can give
    // them to - the default function's code (all of the dispatcher)
    const auto none = check_dispatch("600035" "60e01c" "63aabbcc0014" "601357" "600080fd" "5b" "6001600052"
                                     "60206000f3",
        {{bytes("aabbcc")}, {bytes("aabb")}, {with_selector(0xaabbcc00)}, {with_selector(0xaabbcc01)}, {{}}});
    CHECK(none.empty());
    // ... unless a check of calldatasize < 4 comes first (solc's): then the
    // short calls never get to the test, the function is the selector's - and
    // the default function's knowledge that no selector matched holds for the
    // short calls the machine gives it too
    const auto one = check_dispatch("600436" "10" "601657" "600035" "60e01c" "63aabbcc0014" "601b57"
                                    "5b600080fd" "5b" "6001600052" "60206000f3",
        {{bytes("aabbcc")}, {bytes("aabbcc00")}, {with_selector(0xaabbcc00)}, {with_selector(0x12345678)}, {{}}});
    CHECK(one == std::vector<std::uint32_t>{0xaabbcc00});
    // the same, a selector whose last byte isn't 0: no short call is it
    const auto two = check_dispatch("600035" "60e01c" "63aabbccdd14" "601357" "600080fd" "5b" "6001600052"
                                    "60206000f3",
        {{bytes("aabbcc")}, {with_selector(0xaabbccdd)}, {with_selector(0xaabbcc00)}, {{}}});
    CHECK(two == std::vector<std::uint32_t>{0xaabbccdd});
}

TEST_CASE("vm dispatch: a selector the dispatcher sends to two places by something else is none")
{
    // callvalue != 0 -> (sel == 0xaabbccdd -> return 2); else (sel ==
    // 0xaabbccdd -> return 1); else revert
    const auto sels = check_dispatch("34" "602257" "600035" "60e01c" "63aabbccdd14" "601757" "600080fd" "5b"
                                     "6001600052" "60206000f3" "5b" "600035" "60e01c" "63aabbccdd14" "603657"
                                     "600080fd" "5b" "6002600052" "60206000f3",
        {{with_selector(0xaabbccdd)}, {with_selector(0xaabbccdd), 7}, {with_selector(0x12345678)}, {{}}});
    CHECK(sels.empty());
}

TEST_CASE("vm dispatch: the default function reached with the selector on the stack, or not")
{
    // calldatasize < 4 -> 26 with no word; sel == 0xaabbccdd -> 36 (return
    // 1); else -> 26 with the selector on the stack. At 26: return callvalue,
    // the word below unread - one default function
    const auto sels = check_dispatch("6004" "36" "10" "601a" "57" "600035" "60e01c" "80" "63aabbccdd" "14" "6024" "57"
                                     "601a" "56" "5b" "34" "600052" "60206000f3" "5b" "6001600052" "60206000f3",
        {{with_selector(0xaabbccdd)}, {with_selector(0x12345678), 3}, {bytes("aabbcc"), 5}, {{}}});
    CHECK(sels == std::vector<std::uint32_t>{0xaabbccdd});
    // at 26: return the word below (dup1): the short calls' code fails with
    // no word there, the others' returns the selector - where the word is
    // read the machine gives up, never takes one path's for the other's
    check_dispatch("6004" "36" "10" "601a" "57" "600035" "60e01c" "80" "63aabbccdd" "14" "6024" "57" "601a" "56" "5b"
                   "80" "600052" "60206000f3" "5b" "6001600052" "60206000f3",
        {{with_selector(0xaabbccdd)}, {with_selector(0x12345678), 0, true}, {bytes("aabbcc"), 0, true},
            {{}, 0, true}});
}
