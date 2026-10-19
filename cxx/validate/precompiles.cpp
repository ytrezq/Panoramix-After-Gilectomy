// The precompiles, computed with evmone's implementations (the inputs and
// outputs as evmone's test/state/precompiles.cpp makes them, gas aside: they
// never run out of it, but for the inputs the revision rejects whatever the
// gas - modexp's lengths above 1024, blake2f's sizes, absurd round counts).
#include "session.hpp"

#include <evmone_precompiles/blake2b.hpp>
#include <evmone_precompiles/bn254.hpp>
#include <evmone_precompiles/modexp.hpp>
#include <evmone_precompiles/ripemd160.hpp>
#include <evmone_precompiles/secp256k1.hpp>
#include <evmone_precompiles/secp256r1.hpp>
#include <evmone_precompiles/sha256.hpp>

#include <algorithm>
#include <cstring>
#include <utility>

namespace validate
{
namespace
{
namespace crypto = evmone::crypto;

CallResult failure()
{
    return {false, {}};
}

CallResult ecrecover(BytesView input)
{
    std::uint8_t buf[128]{};
    std::copy_n(input.data(), std::min<std::size_t>(input.size(), 128), buf);
    const auto v = intx::be::unsafe::load<Word>(buf + 32);
    if (v != 27 && v != 28)
        return {true, {}};
    const std::span<const std::uint8_t, 32> hash{buf, 32};
    const std::span<const std::uint8_t, 32> r{buf + 64, 32};
    const std::span<const std::uint8_t, 32> s{buf + 96, 32};
    const auto a = crypto::secp256k1::ecrecover(hash, r, s, v == 28);
    if (!a)
        return {true, {}};
    Bytes out(12, 0);
    out.insert(out.end(), a->bytes, a->bytes + 20);
    return {true, out};
}

CallResult sha256(BytesView input)
{
    Bytes out(32);
    crypto::sha256(reinterpret_cast<std::byte*>(out.data()),
        reinterpret_cast<const std::byte*>(input.data()), input.size());
    return {true, out};
}

CallResult ripemd160(BytesView input)
{
    Bytes out(32, 0);
    crypto::ripemd160(reinterpret_cast<std::byte*>(out.data() + 12),
        reinterpret_cast<const std::byte*>(input.data()), input.size());
    return {true, out};
}

CallResult modexp(BytesView input)
{
    std::uint8_t header[96]{};
    std::copy_n(input.data(), std::min<std::size_t>(input.size(), 96), header);
    const auto base_len256 = intx::be::unsafe::load<Word>(header);
    const auto exp_len256 = intx::be::unsafe::load<Word>(header + 32);
    const auto mod_len256 = intx::be::unsafe::load<Word>(header + 64);
    // EIP-7823 (Osaka): the lengths are at most 1024 bytes
    if (base_len256 > 1024 || exp_len256 > 1024 || mod_len256 > 1024)
        return failure();
    const auto base_len = static_cast<std::size_t>(base_len256);
    const auto exp_len = static_cast<std::size_t>(exp_len256);
    const auto mod_len = static_cast<std::size_t>(mod_len256);

    // the arguments, zero-padded past the end of the input
    Bytes payload(base_len + exp_len + mod_len, 0);
    if (input.size() > 96)
        std::copy_n(input.data() + 96, std::min(input.size() - 96, payload.size()), payload.data());
    const BytesView all{payload};
    const auto base = all.subspan(0, base_len);
    const auto exp = all.subspan(base_len, exp_len);
    const auto mod = all.subspan(base_len + exp_len, mod_len);

    Bytes out(mod_len, 0);
    if (mod_len == 0 || std::ranges::all_of(mod, [](std::uint8_t b) { return b == 0; }))
        return {true, out};
    crypto::modexp(base, exp, mod, out.data());
    return {true, out};
}

CallResult ecadd(BytesView input)
{
    std::uint8_t buf[128]{};
    std::copy_n(input.data(), std::min<std::size_t>(input.size(), 128), buf);
    namespace bn = crypto::bn254;
    const auto p = bn::AffinePoint::from_bytes(std::span<const std::uint8_t, 64>{buf, 64});
    const auto q = bn::AffinePoint::from_bytes(std::span<const std::uint8_t, 64>{buf + 64, 64});
    if (!p || !q || !bn::validate(*p) || !bn::validate(*q))
        return failure();
    const auto res = crypto::ecc::add_affine(*p, *q);
    Bytes out(64);
    res.to_bytes(std::span<std::uint8_t, 64>{out.data(), 64});
    return {true, out};
}

CallResult ecmul(BytesView input)
{
    std::uint8_t buf[96]{};
    std::copy_n(input.data(), std::min<std::size_t>(input.size(), 96), buf);
    namespace bn = crypto::bn254;
    const auto p = bn::AffinePoint::from_bytes(std::span<const std::uint8_t, 64>{buf, 64});
    if (!p || !bn::validate(*p))
        return failure();
    const auto res = bn::mul(*p, intx::be::unsafe::load<Word>(buf + 64));
    Bytes out(64);
    res.to_bytes(std::span<std::uint8_t, 64>{out.data(), 64});
    return {true, out};
}

CallResult ecpairing(BytesView input)
{
    constexpr std::size_t pair_size = 192;
    if (input.size() % pair_size != 0 || input.size() > 1000 * pair_size)
        return failure();
    namespace bn = crypto::bn254;
    std::vector<std::pair<bn::AffinePoint, bn::ExtPoint>> pairs;
    for (auto p = input.data(); p != input.data() + input.size(); p += pair_size)
    {
        const auto a = bn::AffinePoint::from_bytes(std::span<const std::uint8_t, 64>{p, 64});
        if (!a)
            return failure();
        // the imaginary coefficient first, in the EVM's encoding
        const auto xr = bn::Fq::from_bytes(std::span<const std::uint8_t, 32>{p + 96, 32});
        const auto xi = bn::Fq::from_bytes(std::span<const std::uint8_t, 32>{p + 64, 32});
        const auto yr = bn::Fq::from_bytes(std::span<const std::uint8_t, 32>{p + 160, 32});
        const auto yi = bn::Fq::from_bytes(std::span<const std::uint8_t, 32>{p + 128, 32});
        if (!xr || !xi || !yr || !yi)
            return failure();
        pairs.emplace_back(*a, bn::ExtPoint{bn::Fq2({*xr, *xi}), bn::Fq2({*yr, *yi})});
    }
    const auto res = bn::pairing_check(pairs);
    if (!res)
        return failure();
    Bytes out(32, 0);
    out[31] = *res ? 1 : 0;
    return {true, out};
}

CallResult blake2f(BytesView input)
{
    if (input.size() != 213)
        return failure();
    const auto* p = input.data();
    const auto rounds = intx::be::unsafe::load<std::uint32_t>(p);
    if (rounds > (1u << 24))
        return failure();  // would take seconds: out of any real gas
    p += 4;
    std::uint64_t h[8];
    std::uint64_t m[16];
    std::uint64_t t[2];
    std::memcpy(h, p, sizeof(h));
    p += sizeof(h);
    std::memcpy(m, p, sizeof(m));
    p += sizeof(m);
    std::memcpy(t, p, sizeof(t));
    p += sizeof(t);
    if (*p != 0 && *p != 1)
        return failure();
    crypto::blake2b_compress(rounds, h, m, t, *p != 0);
    Bytes out(64);
    std::memcpy(out.data(), h, sizeof(h));
    return {true, out};
}

CallResult p256verify(BytesView input)
{
    if (input.size() != 160)
        return {true, {}};
    ethash::hash256 h{};
    std::copy_n(input.data(), 32, h.bytes);
    const auto r = intx::be::unsafe::load<Word>(input.data() + 32);
    const auto s = intx::be::unsafe::load<Word>(input.data() + 64);
    const auto qx = intx::be::unsafe::load<Word>(input.data() + 96);
    const auto qy = intx::be::unsafe::load<Word>(input.data() + 128);
    if (!crypto::secp256r1::verify(h, r, s, qx, qy))
        return {true, {}};
    Bytes out(32, 0);
    out[31] = 1;
    return {true, out};
}
}  // namespace

CallResult run_precompile(const Word& address, BytesView input)
{
    if (!is_precompile(address))
        return failure();
    if (address == 0x100)
        return p256verify(input);
    switch (static_cast<unsigned>(address))
    {
    case 0x01:
        return ecrecover(input);
    case 0x02:
        return sha256(input);
    case 0x03:
        return ripemd160(input);
    case 0x04:
        return {true, Bytes(input.begin(), input.end())};
    case 0x05:
        return modexp(input);
    case 0x06:
        return ecadd(input);
    case 0x07:
        return ecmul(input);
    case 0x08:
        return ecpairing(input);
    case 0x09:
        return blake2f(input);
    default:
        return failure();  // 0x0a point evaluation, 0x0b-0x11 BLS12-381: not built (blst)
    }
}
}  // namespace validate
