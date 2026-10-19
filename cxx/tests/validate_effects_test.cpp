// validate/effects.hpp: the comparison of the effects, their readable forms.
#include "validate/calls.hpp"
#include "validate/effects.hpp"

#include "validate_test_util.hpp"

using namespace validate;

namespace
{
Bytes bytes(std::string_view s)
{
    return *parse_hex(s);
}

Effects effects(std::vector<Event> events, End end, std::map<Word, Word> diff = {})
{
    return {std::move(events), std::move(end), std::move(diff)};
}
}  // namespace

TEST_CASE("validate: compare, the same effects")
{
    const auto a = effects({StorageWrite{1, 2}, Log{{7}, bytes("0x01")}}, End::returned(bytes("0x2a")), {{1, 2}});
    CHECK(compare(a, a).verdict == Verdict::same);
    // stop is a return of no data
    CHECK(compare(effects({}, End::stop()), effects({}, End::returned({}))).verdict == Verdict::same);
    // the order of the storage writes is not compared by default, the diff is
    const auto b = effects({StorageWrite{3, 4}, StorageWrite{1, 2}}, End::stop(), {{1, 2}, {3, 4}});
    const auto c = effects({StorageWrite{1, 2}, StorageWrite{3, 4}}, End::stop(), {{1, 2}, {3, 4}});
    CHECK(compare(b, c).verdict == Verdict::same);
    CHECK(compare(b, c, {.write_order = true}).verdict == Verdict::different);
    // a failed call's events are not compared by default
    const auto d = effects({Log{{}, {}}}, End::reverted(bytes("0x01")));
    const auto e = effects({}, End::reverted(bytes("0x01")));
    CHECK(compare(d, e).verdict == Verdict::same);
    CHECK(compare(d, e, {.failed_events = true}).verdict == Verdict::different);
    // the invalid ends are the same whatever their reasons, by default
    const auto f = effects({}, End::invalid(Fault::bad_jump));
    const auto g = effects({}, End::invalid(Fault::invalid_instruction));
    CHECK(compare(f, g).verdict == Verdict::same);
    CHECK(compare(f, g, {.faults = true}).verdict == Verdict::different);
    // the results of the calls and the precompile calls are not compared
    const ExternalCall call{CallKind::call, 5, 0, bytes("0x01"), false, {true, {}}};
    auto call2 = call;
    call2.result = {false, bytes("0x02")};
    const ExternalCall pre{CallKind::staticcall, 2, 0, bytes("0x01"), true, {true, {}}};
    CHECK(compare(effects({call}, End::stop()), effects({pre, call2}, End::stop())).verdict == Verdict::same);
    CHECK(compare(effects({call}, End::stop()), effects({pre, call2}, End::stop()), {.precompiles = true})
              .verdict == Verdict::different);
}

TEST_CASE("validate: compare, the first difference")
{
    const auto a = effects({Log{{1}, {}}}, End::returned(bytes("0x2a")), {{1, 2}});

    auto r = compare(a, effects({Log{{1}, {}}}, End::reverted(bytes("0x2a")), {{1, 2}}));
    CHECK(r.verdict == Verdict::different);
    CHECK(r.message == "end: expected return 0x2a, got revert 0x2a");

    r = compare(a, effects({Log{{1}, {}}}, End::returned(bytes("0x2b")), {{1, 2}}));
    CHECK(r.verdict == Verdict::different);
    CHECK(r.message == "end: expected return 0x2a, got return 0x2b (first difference at byte 0)");

    r = compare(a, effects({Log{{2}, {}}}, End::returned(bytes("0x2a")), {{1, 2}}));
    CHECK(r.message == "event 0: expected log1 [0x1] 0x, got log1 [0x2] 0x");

    r = compare(a, effects({Log{{1}, {}}, SelfDestruct{9}}, End::returned(bytes("0x2a")), {{1, 2}}));
    CHECK(r.message == "event 1: expected nothing, got selfdestruct 0x9");

    r = compare(a, effects({Log{{1}, {}}}, End::returned(bytes("0x2a")), {{1, 3}}));
    CHECK(r.message == "storage [0x1]: expected 0x2, got 0x3");

    r = compare(a, effects({Log{{1}, {}}}, End::returned(bytes("0x2a")), {}));
    CHECK(r.message == "storage [0x1]: expected 0x2, got unchanged");

    r = compare(a, effects({Log{{1}, {}}}, End::returned(bytes("0x2a")), {{0, 5}, {1, 2}}));
    CHECK(r.message == "storage [0x0]: expected unchanged, got 0x5");

    r = compare(a, effects({}, End::exhausted("steps")));
    CHECK(r.verdict == Verdict::inconclusive);
    CHECK(r.message == "decompiled: exhausted: steps");
    r = compare(effects({}, End::exhausted()), effects({}, End::unsupported("msize")));
    CHECK(r.verdict == Verdict::inconclusive);
}

TEST_CASE("validate: the readable effects")
{
    Bytes error = bytes("0x08c379a0");
    append_word(error, 0x20);
    append_word(error, 5);
    auto text = bytes("0x68656c6c6f");  // hello
    text.resize(32);
    error.insert(error.end(), text.begin(), text.end());
    CHECK(to_string(End::reverted(error)) == "revert Error(\"hello\")");
    Bytes panic = bytes("0x4e487b71");
    append_word(panic, 0x11);
    CHECK(to_string(End::reverted(panic)) == "revert Panic(0x11)");
    CHECK(to_string(End::invalid(Fault::bad_jump)) == "invalid (bad jump destination)");
    CHECK(to_string(End::stop()) == "stop");
    CHECK(hex(Word{0}) == "0x0");
    CHECK(hex(Word{255}) == "0xff");
    CHECK(hex(bytes("0x00ff")) == "0x00ff");

    const ExternalCall call{CallKind::delegatecall, 0xabc, 0, bytes("0x01"), false, {false, error}};
    CHECK(to_string(Event{call}) == "delegatecall 0xabc 0x01 -> fail Error(\"hello\")");
    const Creation create{CreateKind::create2, 1, bytes("0x00"), Word{7}, 0x123, {true, {}}};
    CHECK(to_string(Event{create}) == "create2 salt 0x7 value 0x1 0x00 -> 0x123 ok");
    const auto e = effects({StorageWrite{1, 2}}, End::stop(), {{1, 2}});
    CHECK(to_string(e) == "sstore [0x1] = 0x2\nstop\n  storage [0x1] = 0x2\n");
}
