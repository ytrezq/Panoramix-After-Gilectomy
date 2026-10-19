// validate/scan.rl, calls.hpp: hex and numbers, the selectors of the
// dispatchers, the generated calls.
#include "validate/calls.hpp"

#include "validate_test_util.hpp"

using namespace validate;

TEST_CASE("validate: parse_hex")
{
    CHECK(parse_hex("0x6001") == Bytes{0x60, 0x01});
    CHECK(parse_hex(" 6001\n") == Bytes{0x60, 0x01});
    CHECK(parse_hex("0X0aFf") == Bytes{0x0a, 0xff});
    CHECK(parse_hex("") == Bytes{});
    CHECK(parse_hex("0x") == Bytes{});
    CHECK_FALSE(parse_hex("600"));
    CHECK_FALSE(parse_hex("zz"));
    CHECK_FALSE(parse_hex("60 01"));
    CHECK_FALSE(parse_hex("0x0x60"));
}

TEST_CASE("validate: parse_number")
{
    CHECK(parse_number("0") == Word{0});
    CHECK(parse_number("123") == Word{123});
    CHECK(parse_number("0x1f") == Word{31});
    CHECK(parse_number("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff") == ~Word{0});
    CHECK(parse_number(
              "115792089237316195423570985008687907853269984665640564039457584007913129639935") ==
          ~Word{0});
    CHECK_FALSE(parse_number(
        "115792089237316195423570985008687907853269984665640564039457584007913129639936"));
    CHECK_FALSE(parse_number("0x10000000000000000000000000000000000000000000000000000000000000000"));
    CHECK_FALSE(parse_number(""));
    CHECK_FALSE(parse_number("0x"));
    CHECK_FALSE(parse_number("12a"));
    CHECK_FALSE(parse_number("-1"));
}

TEST_CASE("validate: evmrun's options")
{
    CHECK(evmrun_option("--seed") == EvmrunOption::seed);
    CHECK(evmrun_option("--each") == EvmrunOption::each);
    CHECK(evmrun_option("--empty") == EvmrunOption::empty);
    CHECK(evmrun_option("-h") == EvmrunOption::help);
    CHECK(evmrun_option("--see") == EvmrunOption::none);
    CHECK(evmrun_option("--seeds") == EvmrunOption::none);
    CHECK(evmrun_option("file.hex") == EvmrunOption::none);
}

TEST_CASE("validate: the selectors of the dispatchers")
{
    const auto sel = [](std::string_view hex) { return find_selectors(*parse_hex(hex)); };
    using V = std::vector<std::uint32_t>;
    // solc >= 0.5: DUP1 PUSH4 s EQ PUSH2 dest JUMPI, twice
    CHECK(sel("0x60003560e01c" "8063aabbccdd14610010578063112233441461002057" "00") ==
          V{0xaabbccdd, 0x11223344});
    // solc 0.4: PUSH4 s DUP2 EQ PUSH2 dest JUMPI
    CHECK(sel("0x63aabbccdd8114610010" "57") == V{0xaabbccdd});
    // vyper: PUSH4 s DUP2 XOR PUSH2 dest JUMPI; PUSH4 s DUP2 EQ ISZERO PUSH2 dest JUMPI
    CHECK(sel("0x63aabbccdd811861001057" "6301020304811415610020" "57") == V{0xaabbccdd, 0x01020304});
    // vyper < 0.2: PUSH4 s PUSH1 0 MLOAD EQ ISZERO PUSH2 dest JUMPI
    CHECK(sel("0x63aabbccdd600051141561001057") == V{0xaabbccdd});
    // once each, in code order
    CHECK(sel("0x8063000000021461001057" "8063000000011461002057" "8063000000021461003057") == V{2, 1});
    // not a jump: not a selector
    CHECK(sel("0x8063aabbccdd1400").empty());
    // in a PUSH32's immediate: not instructions
    CHECK(sel("0x7f" "8063aabbccdd14610010570000000000000000000000000000000000000000000000" "00").empty());
    // a truncated code
    CHECK(sel("0x8063aabb").empty());
    CHECK(sel("0x").empty());
}

TEST_CASE("validate: the generated calls")
{
    const SeededWorld world{{.seed = 9}};
    const auto code = *parse_hex("0x60003560e01c" "8063aabbccdd14610010578063112233441461002057" "00");
    const CallGenerator gen{world, code};
    REQUIRE(gen.selectors() == std::vector<std::uint32_t>{0xaabbccdd, 0x11223344});
    const auto calls = gen.calls();
    REQUIRE(calls.size() == 2 * 4 + 3);
    CHECK(calls[0].selector == 0xaabbccdd);
    CHECK(calls[0].variant == 0);
    CHECK(calls[0].context.calldata == Bytes{0xaa, 0xbb, 0xcc, 0xdd});
    CHECK(calls[1].context.calldata.size() > 4);
    CHECK(calls[4].selector == 0x11223344);
    for (const auto& c : calls)
    {
        CHECK(c.context.origin == c.context.caller);
        bool actor = false;
        for (const auto& a : world.actors())
            actor |= a == c.context.caller;
        CHECK(actor);
    }
    // the fallback's: no calldata, 1-3 bytes, a selector of none of the functions
    CHECK(calls[8].context.calldata.empty());
    CHECK(calls[9].context.calldata.size() >= 1);
    CHECK(calls[9].context.calldata.size() <= 3);
    REQUIRE(calls[10].context.calldata.size() >= 4);
    const auto other = static_cast<std::uint32_t>(load_word(calls[10].context.calldata, 0) >> 224);
    CHECK(other != 0xaabbccdd);
    CHECK(other != 0x11223344);

    // the same world, the same calls
    const CallGenerator again{world, code};
    const auto calls2 = again.calls();
    for (std::size_t i = 0; i < calls.size(); ++i)
    {
        CHECK(calls[i].context.calldata == calls2[i].context.calldata);
        CHECK(calls[i].context.caller == calls2[i].context.caller);
        CHECK(calls[i].context.value == calls2[i].context.value);
    }

    // the hook of the typed arguments
    CallGenerator typed{world, code};
    typed.set_encoder([](std::uint32_t selector, unsigned variant, const SeededWorld&) -> std::optional<Bytes> {
        if (selector != 0x11223344)
            return std::nullopt;
        Bytes b{0x11, 0x22, 0x33, 0x44};
        append_word(b, variant);
        return b;
    });
    CHECK(typed.call(0x11223344, 3).context.calldata.size() == 36);
    CHECK(load_word(typed.call(0x11223344, 3).context.calldata, 4) == 3);
    CHECK(typed.call(0xaabbccdd, 3).context.calldata == calls[3].context.calldata);

    // many shapes of arguments
    std::size_t shortest = 1000, longest = 0;
    bool unaligned = false;
    for (unsigned v = 1; v < 60; ++v)
    {
        const auto args = gen.arguments(0xaabbccdd, v);
        shortest = std::min(shortest, args.size());
        longest = std::max(longest, args.size());
        unaligned |= args.size() % 32 != 0;
    }
    CHECK(shortest <= 32);
    CHECK(longest >= 16 * 32);
    CHECK(unaligned);
}

TEST_CASE("validate: the selectors found by probing the dispatcher")
{
    // if (sload(0) == caller) dispatch 0x22222222;
    // a binary search on the pivot 0x80000000: 0xaaaaaaaa above, 0x11111111
    // below, then the optimizer's left-aligned x + (0x64d3180d << 225) == 0
    // (upgradeTo(address): 0x3659cfe6)
    const auto code = *parse_hex(
        "0x60005433146100465760003560e01c80638000000011610026578063aaaaaaaa1461005857005b8063"
        "1111111114610058576000356364d3180d60e11b810161004457005b005b60003560e01c632222222214"
        "61005857005b600160005260206000f3");
    const SeededWorld empty{{.seed = 4, .random = false}};
    const auto found = probe_selectors(code, empty);
    const auto has = [&](std::uint32_t s) { return std::ranges::find(found.selectors, s) != found.selectors.end(); };
    CHECK(has(0x80000000));
    CHECK(has(0xaaaaaaaa));
    CHECK(has(0x11111111));
    CHECK(has(0x3659cfe6));
    CHECK(has(0x22222222));  // as the owner: address 0 in the empty world
    CHECK(std::ranges::find(found.callers, Word{0}) != found.callers.end());
    // the static patterns don't see the pivot, nor the shifted constant
    const auto s = find_selectors(code);
    CHECK(std::ranges::find(s, 0xaaaaaaaau) != s.end());
    CHECK(std::ranges::find(s, 0x80000000u) == s.end());
    CHECK(std::ranges::find(s, 0x3659cfe6u) == s.end());

    // the generator has both, and calls from the owner sometimes
    const CallGenerator gen{empty, code};
    CHECK(gen.selectors().size() == 5);
    REQUIRE(gen.privileged().size() == 1);
    unsigned from_owner = 0;
    for (const auto& c : gen.calls())
        from_owner += c.context.caller == 0;
    CHECK(from_owner > 0);
    // deterministic
    CHECK(probe_selectors(code, empty).selectors == found.selectors);
}
