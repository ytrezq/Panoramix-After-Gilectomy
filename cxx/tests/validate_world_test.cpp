// validate/world.hpp, session.hpp: the helpers, the seeded world, the state
// and the sessions (the EVM's rules both sides share).
#include "validate/calls.hpp"
#include "validate/session.hpp"
#include "validate/world.hpp"

#include <doctest/doctest.h>

#include <map>

using namespace validate;

namespace
{
Word word(std::string_view s)
{
    return *parse_number(s);
}

Bytes bytes(std::string_view s)
{
    return *parse_hex(s);
}
}  // namespace

TEST_CASE("validate: keccak256, load_word, to_bytes")
{
    CHECK(keccak256({}) == word("0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"));
    const auto data = bytes("0x0102");
    CHECK(load_word(data, 0) == word("0x0102000000000000000000000000000000000000000000000000000000000000"));
    CHECK(load_word(data, 1) == word("0x0200000000000000000000000000000000000000000000000000000000000000"));
    CHECK(load_word(data, 2) == 0);
    CHECK(load_word(data, ~Word{0}) == 0);
    CHECK(to_bytes(1)[31] == 1);
    Bytes out;
    append_word(out, 0x20);
    CHECK(out.size() == 32);
    CHECK(out[31] == 0x20);
}

TEST_CASE("validate: create addresses")
{
    // the addresses of 0x6ac7ea33f8831ea9dcc53393aaa88b25a785dbf0's first creations
    const auto sender = word("0x6ac7ea33f8831ea9dcc53393aaa88b25a785dbf0");
    CHECK(create_address(sender, 0) == word("0xcd234a471b72ba2f1ccf0a70fcaba648a5eecd8d"));
    CHECK(create_address(sender, 1) == word("0x343c43a37d37dff08ae8c4a11544c718abb4fcf8"));
    CHECK(create_address(sender, 2) == word("0xf778b86fa74e846c4f0a1fbd1335fe81c00a0c91"));
    CHECK(create_address(sender, 3) == word("0xfffd933a0bc612844eaf0c6fe3e5b8e9b6c1d19c"));
    // the RLP of the longer nonces (computed with pycryptodome's keccak)
    CHECK(create_address(sender, 127) == word("0x06d9a77f5e4b311bae8d559db9cdb4df94104aa0"));
    CHECK(create_address(sender, 128) == word("0x08e190dcb7b73f5fcdabb43e102215c83659a76d"));
    CHECK(create_address(sender, 255) == word("0x3ef7c1a519e4b4431e317d7839340e3139b03c65"));
    CHECK(create_address(sender, 256) == word("0x3837c1ae70354f670550c746580199ac6a73cb0a"));
    CHECK(create_address(sender, 0x10000) == word("0xf666a819b370d38f44f2573464da3fba8479b917"));
    CHECK(create_address(sender, 1ULL << 32) == word("0xf4bf328880432064068338f915c49f817dc4ce18"));
    CHECK(create_address(sender, 1ULL << 63) == word("0x2784510e2ee056fdb751085bad9a38b57799fd99"));
    // EIP-1014's examples
    CHECK(create2_address(0, 0, bytes("0x00")) == word("0x4d1a2e2bb4f88f0250f26ffff098b0b30b26bf38"));
    CHECK(create2_address(word("0xdeadbeef00000000000000000000000000000000"), 0, bytes("0x00")) ==
          word("0xb928f69bb1d91cd65274e3c79d8986362984fda3"));
    CHECK(create2_address(word("0x00000000000000000000000000000000deadbeef"),
              word("0xcafebabe"), bytes("0xdeadbeef")) ==
          word("0x60f3f640a8508fc6a86d45df051962668e1e8ac7"));
    CHECK(is_precompile(1));
    CHECK(is_precompile(0x11));
    CHECK(is_precompile(0x100));
    CHECK_FALSE(is_precompile(0));
    CHECK_FALSE(is_precompile(0x12));
}

TEST_CASE("validate: the seeded world is a function of its seed and keys")
{
    const SeededWorld a{{.seed = 7}};
    const SeededWorld b{{.seed = 7}};
    const SeededWorld c{{.seed = 8}};
    CHECK(a.contract_address() == b.contract_address());
    CHECK(a.contract_address() != c.contract_address());
    REQUIRE(a.actors().size() == 4);
    CHECK(a.actors()[0] == b.actors()[0]);

    // the same answers whatever the order of the questions
    std::map<Word, Word> forward;
    for (unsigned i = 0; i < 200; ++i)
        forward[i] = a.storage(a.contract_address(), i);
    for (unsigned i = 200; i-- > 0;)
        CHECK(b.storage(b.contract_address(), i) == forward[i]);
    bool differs = false;
    for (unsigned i = 0; i < 200; ++i)
        differs |= c.storage(c.contract_address(), i) != forward[i];
    CHECK(differs);

    const auto input = bytes("0x70a08231");
    CHECK(a.call(CallKind::call, 5, 0, input) == b.call(CallKind::call, 5, 0, input));
    CHECK(a.block().number == b.block().number);
    CHECK(a.block().number < Word{1} << 63);
    CHECK(a.block_hash(100) == b.block_hash(100));
    CHECK(a.code(12345) == b.code(12345));
}

TEST_CASE("validate: the random world's mix of words")
{
    const SeededWorld w{{.seed = 1}};
    unsigned zero = 0, one = 0, small = 0, address = 0, actor = 0, max = 0, large = 0;
    const unsigned n = 4000;
    for (unsigned i = 0; i < n; ++i)
    {
        const auto v = w.storage(w.contract_address(), i);
        if (v == 0)
            ++zero;
        else if (v == 1)
            ++one;
        else if (v < 64)
            ++small;
        else if (v == ~Word{0})
            ++max;
        else if (v <= address_mask)
        {
            ++address;
            for (const auto& a : w.actors())
                actor += a == v;
        }
        else
            ++large;
    }
    // the default weights: 30 10 20 25 10 5 (out of 100)
    CHECK(zero > n * 25 / 100);
    CHECK(zero < n * 35 / 100);
    CHECK(one > n * 7 / 100);
    CHECK(small > n * 16 / 100);
    CHECK(address > n * 20 / 100);
    CHECK(actor > address / 4);
    CHECK(large > n * 7 / 100);
    CHECK(max > n * 3 / 100);
}

TEST_CASE("validate: the empty world")
{
    const SeededWorld w{{.seed = 3, .random = false}};
    for (unsigned i = 0; i < 50; ++i)
    {
        CHECK(w.storage(w.contract_address(), i) == 0);
        CHECK(w.code(1000 + i).empty());
        CHECK(w.balance(1000 + i) == 0);
    }
}

TEST_CASE("validate: the random world's codes and calls")
{
    const SeededWorld w{{.seed = 5}};
    unsigned contracts = 0;
    for (unsigned i = 0; i < 400; ++i)
    {
        const auto code = w.code(0x1000 + i);
        if (!code.empty())
        {
            ++contracts;
            CHECK(code[0] != 0xef);
        }
    }
    CHECK(contracts > 250);
    CHECK(contracts < 350);
    for (const auto& a : w.actors())
        CHECK(w.code(a).empty());

    unsigned ok = 0;
    for (unsigned i = 0; i < 400; ++i)
    {
        Bytes input = bytes("0xa9059cbb");
        append_word(input, i);
        const auto r = w.call(CallKind::call, 0x1234, 0, input);
        ok += r.success;
        if (r.success)
            CHECK(r.output.size() % 32 == 0);
    }
    CHECK(ok > 300);
    CHECK(ok < 380);
}

TEST_CASE("validate: a session commits its changes when its call succeeds")
{
    const SeededWorld w{{.seed = 11}};
    State state{w, w.contract_address(), bytes("0x00")};
    const auto original = state.storage(5);
    {
        Session s{state, {.caller = w.actors()[0]}};
        s.sstore(5, original + 1);
        CHECK(s.sload(5) == original + 1);
        CHECK(state.storage(5) == original);
        const auto e = s.finish(End::stop());
        REQUIRE(e.events.size() == 1);
        CHECK(std::get<StorageWrite>(e.events[0]) == StorageWrite{5, original + 1});
        REQUIRE(e.storage_diff.size() == 1);
        CHECK(e.storage_diff.at(5) == original + 1);
    }
    CHECK(state.storage(5) == original + 1);
    {
        Session s{state, {}};
        s.sstore(5, 99);
        s.sstore(6, state.storage(6));  // the same value: no diff
        const auto e = s.finish(End::reverted({}));
        CHECK(e.events.size() == 2);
        CHECK(e.storage_diff.empty());
    }
    CHECK(state.storage(5) == original + 1);
    {
        Session s{state, {}};
        s.sstore(6, state.storage(6));
        const auto e = s.finish(End::returned(bytes("0x01")));
        CHECK(e.storage_diff.empty());
    }
}

TEST_CASE("validate: the EVM's rules of the external calls")
{
    const SeededWorld w{{.seed = 12, .random = false}};
    const auto self = w.contract_address();
    State state{w, self, bytes("0x00")};
    Session s{state, {.caller = w.actors()[0], .value = 1000}};

    // the call's value is the contract's
    CHECK(s.balance(self) == 1000);
    // a value above the balance: a light failure, no event
    CHECK_FALSE(s.call(CallKind::call, 0x5555, 1001, {}).success);
    CHECK(s.events().empty());
    // an account without code: success, no data, the value moves
    const auto r = s.call(CallKind::call, 0x5555, 400, bytes("0x1234"));
    CHECK(r.success);
    CHECK(r.output.empty());
    CHECK(s.balance(self) == 600);
    CHECK(s.balance(0x5555) == 400);
    REQUIRE(s.events().size() == 1);
    const auto& call = std::get<ExternalCall>(s.events()[0]);
    CHECK(call.target == 0x5555);
    CHECK(call.value == 400);
    CHECK(call.input == bytes("0x1234"));
    // staticcall and delegatecall have no value
    s.call(CallKind::delegatecall, 0x5555, 77, {});
    CHECK(std::get<ExternalCall>(s.events().back()).value == 0);
    // the precompiles are computed
    const auto id = s.call(CallKind::staticcall, 4, 0, bytes("0xdeadbeef"));
    CHECK(id.success);
    CHECK(id.output == bytes("0xdeadbeef"));
    CHECK(std::get<ExternalCall>(s.events().back()).precompile);

    // creations: CREATE's address from the nonce, which increments
    const auto n = s.nonce(self);
    const auto c1 = s.create(CreateKind::create, 0, bytes("0x6000"));
    CHECK(s.nonce(self) == n + 1);
    if (c1.success)
    {
        CHECK(c1.address == create_address(self, n));
        CHECK(s.code_size(c1.address) == 1);
    }
    const auto c2 = s.create(CreateKind::create2, 0, bytes("0x6000"), 42);
    if (c2.success)
        CHECK(c2.address == create2_address(self, 42, bytes("0x6000")));
    CHECK(std::get<Creation>(s.events().back()).salt == Word{42});

    // the block hashes of the 256 blocks before
    const auto& number = s.block().number;
    CHECK(s.block_hash(number) == 0);
    CHECK(s.block_hash(number - 1) == w.block_hash(number - 1));
    CHECK(s.block_hash(number - 256) == w.block_hash(number - 256));
    CHECK(s.block_hash(number - 257) == 0);

    // selfdestruct: the balance goes
    s.selfdestruct(0x7777);
    CHECK(s.balance(self) == 0);
    CHECK(s.balance(0x7777) == 600);
    const auto e = s.finish(End::stop());
    CHECK(std::get<SelfDestruct>(e.events.back()).beneficiary == 0x7777);
    CHECK(state.balance(0x7777) == 600);
}

TEST_CASE("validate: the precompiles")
{
    CHECK(run_precompile(2, {}).output ==
          bytes("0xe3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"));
    CHECK(run_precompile(3, {}).output ==
          bytes("0x0000000000000000000000009c1185a5c5e9fc54612808977ee8f548b2258d31"));
    // ecrecover: a signature of the hash 0x456e9aea...: the signer
    const auto sig = bytes(
        "0x456e9aea5e197a1f1af7a3e85a3212fa4049a3ba34c2289b4c860fc0b0c64ef3"
        "000000000000000000000000000000000000000000000000000000000000001c"
        "9242685bf161793cc25603c231bc2f568eb630ea16aa137d2664ac8038825608"
        "4f8ae3bd7535248d0bd448298cc2e2071e56992d0774dc340c368ae950852ada");
    CHECK(run_precompile(1, sig).output ==
          bytes("0x0000000000000000000000007156526fbd7a3c72969b54f64e42c10fbb768c8a"));
    // a v other than 27, 28: no data
    auto bad = sig;
    bad[63] = 0x1d;
    CHECK(run_precompile(1, bad).success);
    CHECK(run_precompile(1, bad).output.empty());
    // modexp: 3^5 mod 7 = 5
    Bytes m;
    append_word(m, 1);
    append_word(m, 1);
    append_word(m, 1);
    m.push_back(3);
    m.push_back(5);
    m.push_back(7);
    CHECK(run_precompile(5, m).output == bytes("0x05"));
    // the BLS12-381 and the point evaluation aren't built: they fail
    CHECK_FALSE(run_precompile(0x0a, {}).success);
    CHECK_FALSE(run_precompile(0x12, {}).success);
}
