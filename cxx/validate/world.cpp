// The world of the validation by execution: the helpers, SeededWorld, State.
#include "world.hpp"

#include <evmone_precompiles/keccak.h>

#include <algorithm>
#include <cstring>

namespace validate
{
#ifdef EVMONE_FIXED_GAS
static_assert(EVMONE_FIXED_GAS == fixed_gas, "EVMONE_FIXED_GAS (validate/Makefile.inc) != fixed_gas");
#endif

Word keccak256(BytesView data) noexcept
{
    const auto h = ethash_keccak256(data.data(), data.size());
    return intx::be::unsafe::load<Word>(h.bytes);
}

std::array<std::uint8_t, 32> to_bytes(const Word& w) noexcept
{
    std::array<std::uint8_t, 32> b;
    intx::be::unsafe::store(b.data(), w);
    return b;
}

Word load_word(BytesView data, const Word& offset) noexcept
{
    if (offset >= data.size())
        return 0;
    const auto start = static_cast<std::size_t>(offset);
    std::uint8_t b[32]{};
    std::memcpy(b, data.data() + start, std::min<std::size_t>(32, data.size() - start));
    return intx::be::unsafe::load<Word>(b);
}

void append_word(Bytes& out, const Word& w)
{
    const auto b = to_bytes(w);
    out.insert(out.end(), b.begin(), b.end());
}


Word create_address(const Word& sender, std::uint64_t nonce) noexcept
{
    // rlp([sender, nonce]): the list's payload is at most 21 + 9 bytes
    std::uint8_t nonce_bytes[8];
    unsigned n = 0;
    for (auto v = nonce; v != 0; v >>= 8)
        ++n;
    for (unsigned i = 0; i < n; ++i)
        nonce_bytes[i] = static_cast<std::uint8_t>(nonce >> (8 * (n - 1 - i)));
    std::uint8_t rlp[32];
    const unsigned nonce_len = (nonce != 0 && nonce < 0x80) ? 1 : 1 + n;
    rlp[0] = static_cast<std::uint8_t>(0xc0 + 21 + nonce_len);
    rlp[1] = 0x94;
    const auto s = to_bytes(sender);
    std::memcpy(rlp + 2, s.data() + 12, 20);
    if (nonce == 0)
        rlp[22] = 0x80;
    else if (nonce < 0x80)
        rlp[22] = static_cast<std::uint8_t>(nonce);
    else
    {
        rlp[22] = static_cast<std::uint8_t>(0x80 + n);
        std::memcpy(rlp + 23, nonce_bytes, n);
    }
    return to_address(keccak256({rlp, 22 + std::size_t{nonce_len}}));
}

Word create2_address(const Word& sender, const Word& salt, BytesView init_code) noexcept
{
    std::uint8_t buf[85];
    buf[0] = 0xff;
    const auto s = to_bytes(sender);
    std::memcpy(buf + 1, s.data() + 12, 20);
    intx::be::unsafe::store(buf + 21, salt);
    intx::be::unsafe::store(buf + 53, keccak256(init_code));
    return to_address(keccak256(buf));
}

bool is_precompile(const Word& address) noexcept
{
    return (address >= 0x01 && address <= 0x11) || address == 0x100;
}

// SeededWorld: the kinds of its keys (below 0x80, the others are the users').
namespace
{
enum Kind : std::uint8_t
{
    k_storage = 1,
    k_balance,
    k_nonce,
    k_code,
    k_code_bytes,
    k_block_hash,
    k_block,
    k_call,
    k_call_output,
    k_create,
    k_actor,
    k_contract,
    k_mix_address,
};

/// The key of words, then of bytes: sized once (GCC's LTO warns of the
/// reallocations of the growing vectors, wrongly).
Bytes key_of(std::initializer_list<Word> words, BytesView tail = {}, int tag = -1)
{
    const std::size_t head = tag >= 0 ? 1 : 0;
    Bytes key(head + 32 * words.size() + tail.size());
    if (tag >= 0)
        key[0] = static_cast<std::uint8_t>(tag);
    auto* p = key.data() + head;
    for (const auto& w : words)
    {
        intx::be::unsafe::store(p, w);
        p += 32;
    }
    if (!tail.empty())
        std::memcpy(p, tail.data(), tail.size());
    return key;
}

/// An ABI-encoded Error(string) of a short text.
Bytes error_string(const Word& random)
{
    static constexpr std::uint8_t text[] = "mock revert";
    const std::size_t n = sizeof(text) - 1;
    Bytes out{0x08, 0xc3, 0x79, 0xa0};
    append_word(out, 0x20);
    append_word(out, n + 1);
    std::uint8_t data[32]{};
    std::memcpy(data, text, n);
    data[n] = static_cast<std::uint8_t>('a' + static_cast<unsigned>(random % 26));
    out.insert(out.end(), data, data + 32);
    return out;
}
}  // namespace

SeededWorld::SeededWorld(const WorldConfig& config) : config_{config}
{
    contract_ = to_address(hash(k_contract, {}));
    for (unsigned i = 0; i < config_.actors; ++i)
        actors_.push_back(to_address(hash(k_actor, key_of({i}))));
}

Word SeededWorld::hash(std::uint8_t kind, BytesView key) const
{
    Bytes buf(9 + key.size());
    for (int i = 0; i < 8; ++i)
        buf[static_cast<std::size_t>(i)] = static_cast<std::uint8_t>(config_.seed >> (8 * (7 - i)));
    buf[8] = kind;
    if (!key.empty())
        std::memcpy(buf.data() + 9, key.data(), key.size());
    return keccak256(buf);
}

Word SeededWorld::word(std::uint8_t kind, BytesView key) const
{
    return mixed(hash(kind, key));
}

Word SeededWorld::mixed(const Word& random) const
{
    const auto& m = config_.mix;
    const unsigned total = m.zero + m.one + m.small + m.address + m.large + m.max;
    if (total == 0)
        return random;
    // the kind from the low 32 bits, the value from the others (the large
    // words are the whole hash: their low bits are as random as the rest)
    auto pick = static_cast<unsigned>(static_cast<std::uint32_t>(random) % total);
    const Word rest = random >> 32;
    if (pick < m.zero)
        return 0;
    pick -= m.zero;
    if (pick < m.one)
        return 1;
    pick -= m.one;
    if (pick < m.small)
        return 2 + rest % 62;
    pick -= m.small;
    if (pick < m.address)
    {
        // 40% an actor, 10% the contract, 50% any address
        const auto which = static_cast<unsigned>(rest % 10);
        if (which < 4 && !actors_.empty())
            return actors_[static_cast<std::size_t>((rest >> 8) % actors_.size())];
        if (which < 5)
            return contract_;
        return to_address(rest >> 16);
    }
    pick -= m.address;
    if (pick < m.large)
        return random;
    return ~Word{0};
}

Word SeededWorld::storage(const Word& account, const Word& slot) const
{
    if (!config_.random)
        return 0;
    return word(k_storage, key_of({account, slot}));
}

Word SeededWorld::balance(const Word& account) const
{
    if (!config_.random)
        return 0;
    const auto r = hash(k_balance, key_of({account}));
    const auto pick = static_cast<unsigned>(r % 100);
    const Word rest = r >> 8;
    if (pick < 25)
        return 0;
    if (pick < 40)
        return 1 + rest % 1'000'000;
    if (pick < 90)
        return rest % intx::from_string<Word>("1000000000000000000000");  // < 1000 ether
    return rest % (Word{1} << 128);
}

std::uint64_t SeededWorld::nonce(const Word& account) const
{
    if (!config_.random)
        return account == contract_ ? 1 : 0;
    if (!code(account).empty())
        return 1;
    return static_cast<std::uint64_t>(hash(k_nonce, key_of({account})) % 4);
}

Bytes SeededWorld::code(const Word& account) const
{
    if (!config_.random || is_precompile(account) || account == contract_)
        return {};
    if (std::ranges::find(actors_, account) != actors_.end())
        return {};  // the actors are EOAs
    const auto r = hash(k_code, key_of({account}));
    if (r % 100 >= config_.contracts_percent)
        return {};
    const auto size = static_cast<std::size_t>(1 + (r >> 8) % 128);
    Bytes code;
    code.reserve(size + 31);
    for (unsigned i = 0; code.size() < size; ++i)
        append_word(code, hash(k_code_bytes, key_of({account, i})));
    code.resize(size);
    if (code[0] == 0xef)
        code[0] = 0xfe;  // no EIP-7702 delegation, no EOF
    return code;
}

Word SeededWorld::block_hash(const Word& number) const
{
    return hash(k_block_hash, key_of({number}));
}

BlockContext SeededWorld::block() const
{
    const auto r = hash(k_block, {});
    BlockContext b;
    b.number = 21'000'000 + r % 1'000'000;
    b.timestamp = 1'730'000'000 + (r >> 32) % 50'000'000;
    b.coinbase = to_address(hash(k_block, key_of({1})));
    b.prevrandao = hash(k_block, key_of({2}));
    b.gas_limit = 30'000'000;
    b.chain_id = 1;
    b.base_fee = 1'000'000'000 + (r >> 64) % 50'000'000'000ULL;
    b.blob_base_fee = 1;
    return b;
}

CallResult SeededWorld::call(CallKind kind, const Word& target, const Word& value,
    BytesView input) const
{
    const auto r = hash(k_call, key_of({target, value}, input, static_cast<int>(kind)));
    const auto output_word = [&](unsigned i) {
        return word(k_call_output, key_of({r, i}));
    };

    CallResult result;
    result.success = r % 100 < config_.call_success_percent;
    const auto shape = static_cast<unsigned>((r >> 8) % 100);
    const Word rest = r >> 16;
    if (result.success)
    {
        unsigned words = 0;
        if (shape < 15)
            words = 0;
        else if (shape < 65)
            words = 1;
        else if (shape < 80)
            words = 2;
        else if (shape < 90)
            words = 3 + static_cast<unsigned>(rest % 6);
        else
        {
            // bytes/string: offset, length, the data
            const auto length = static_cast<unsigned>(rest % 65);
            append_word(result.output, 0x20);
            append_word(result.output, length);
            for (unsigned i = 0; i < (length + 31) / 32; ++i)
                append_word(result.output, hash(k_call_output, key_of({r, i})));
            const auto end = result.output.end();
            std::fill(end - static_cast<std::ptrdiff_t>((32 - length % 32) % 32), end, 0);
            return result;
        }
        for (unsigned i = 0; i < words; ++i)
            append_word(result.output, output_word(i));
    }
    else if (shape < 50)
        ;  // no data
    else if (shape < 80)
        result.output = error_string(rest);
    else
    {
        // a custom error: a selector and a word
        const auto sel = to_bytes(rest);
        result.output.assign(sel.begin(), sel.begin() + 4);
        append_word(result.output, output_word(0));
    }
    return result;
}

CallResult SeededWorld::create(CreateKind kind, const Word& address, const Word& value,
    BytesView init_code) const
{
    const auto r = hash(k_create, key_of({address, value}, init_code, static_cast<int>(kind)));
    CallResult result;
    result.success = r % 100 < config_.create_success_percent;
    if (!result.success && (r >> 8) % 2 != 0)
        result.output = error_string(r >> 16);
    return result;
}

State::State(const World& world, const Word& address, Bytes code)
  : block{world.block()}, world_{&world}, address_{to_address(address)}, code_{std::move(code)}
{}

Word State::storage(const Word& slot) const
{
    if (const auto it = storage_.find(slot); it != storage_.end())
        return it->second;
    return world_->storage(address_, slot);
}

Word State::balance(const Word& account) const
{
    if (const auto it = balances_.find(account); it != balances_.end())
        return it->second;
    return world_->balance(account);
}

std::uint64_t State::nonce(const Word& account) const
{
    if (const auto it = nonces_.find(account); it != nonces_.end())
        return it->second;
    const auto n = world_->nonce(account);
    return account == address_ ? std::max<std::uint64_t>(n, 1) : n;
}

Bytes State::code_of(const Word& account) const
{
    if (account == address_)
        return code_;
    if (created_.contains(account))
        return Bytes{created_code};
    return world_->code(account);
}
}  // namespace validate
