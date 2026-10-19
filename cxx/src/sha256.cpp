// SHA-256: sha256-simd's choice of its block functions, its padding (sha256.go)
// and its portable block function (sha256block_noasm.go: blockGeneric), in
// C++. See sha256.hpp and cxx/third_party/sha256-simd/NOTICE.
#include "sha256.hpp"

#include <algorithm>
#include <bit>
#include <cstring>

#if defined(__x86_64__)
#include <cpuid.h>
#endif

namespace pan::sha256 {

#if defined(__x86_64__)
// sha256_*.S: the state updated with len bytes of blocks (len a multiple of
// 64, at least 64). The System V convention on every system (sha256_asm.h).
extern "C" {
[[gnu::sysv_abi]] void pan_sha256_blocks_shani(std::uint32_t* state, const std::uint8_t* data,
                                               std::size_t len) noexcept;
[[gnu::sysv_abi]] void pan_sha256_blocks_avx2(std::uint32_t* state, const std::uint8_t* data,
                                              std::size_t len) noexcept;
[[gnu::sysv_abi]] void pan_sha256_blocks_avx(std::uint32_t* state, const std::uint8_t* data,
                                             std::size_t len) noexcept;
[[gnu::sysv_abi]] void pan_sha256_blocks_ssse3(std::uint32_t* state, const std::uint8_t* data,
                                               std::size_t len) noexcept;
}
#endif

namespace {

constexpr std::array<std::uint32_t, 64> k = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
    0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
    0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
    0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
    0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
    0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
    0xc67178f2,
};

constexpr std::array<std::uint32_t, 8> initial = {0x6a09e667, 0xbb67ae85, 0x3c6ef372,
                                                  0xa54ff53a, 0x510e527f, 0x9b05688c,
                                                  0x1f83d9ab, 0x5be0cd19};

// blockGeneric (sha256block_noasm.go)
void blocks_generic(std::uint32_t* state, const std::uint8_t* p, std::size_t len) noexcept
{
    std::uint32_t w[64];
    std::uint32_t h0 = state[0], h1 = state[1], h2 = state[2], h3 = state[3];
    std::uint32_t h4 = state[4], h5 = state[5], h6 = state[6], h7 = state[7];
    for (; len >= block_size; p += block_size, len -= block_size) {
        for (int i = 0; i < 16; i++)
            w[i] = std::uint32_t{p[4 * i]} << 24 | std::uint32_t{p[4 * i + 1]} << 16 |
                   std::uint32_t{p[4 * i + 2]} << 8 | std::uint32_t{p[4 * i + 3]};
        for (int i = 16; i < 64; i++) {
            std::uint32_t v1 = w[i - 2];
            std::uint32_t t1 = std::rotr(v1, 17) ^ std::rotr(v1, 19) ^ (v1 >> 10);
            std::uint32_t v2 = w[i - 15];
            std::uint32_t t2 = std::rotr(v2, 7) ^ std::rotr(v2, 18) ^ (v2 >> 3);
            w[i] = t1 + w[i - 7] + t2 + w[i - 16];
        }
        std::uint32_t a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7;
        for (int i = 0; i < 64; i++) {
            std::uint32_t t1 = h + (std::rotr(e, 6) ^ std::rotr(e, 11) ^ std::rotr(e, 25)) +
                               ((e & f) ^ (~e & g)) + k[i] + w[i];
            std::uint32_t t2 = (std::rotr(a, 2) ^ std::rotr(a, 13) ^ std::rotr(a, 22)) +
                               ((a & b) ^ (a & c) ^ (b & c));
            h = g;
            g = f;
            f = e;
            e = d + t1;
            d = c;
            c = b;
            b = a;
            a = t1 + t2;
        }
        h0 += a;
        h1 += b;
        h2 += c;
        h3 += d;
        h4 += e;
        h5 += f;
        h6 += g;
        h7 += h;
    }
    state[0] = h0, state[1] = h1, state[2] = h2, state[3] = h3;
    state[4] = h4, state[5] = h5, state[6] = h6, state[7] = h7;
}

// What the processor and the system support (cpuid.go: its init).
struct Features {
    bool ssse3 = false, sse41 = false, avx = false, avx2 = false, sha = false;
    bool bmi1 = false, bmi2 = false;
};

Features detect() noexcept
{
    Features f;
#if defined(__x86_64__)
    unsigned a, b, c, d;
    unsigned max_leaf = __get_cpuid_max(0, nullptr);
    bool xsave = false, osxsave = false, cpu_avx = false, cpu_avx2 = false;
    if (max_leaf >= 1) {
        __cpuid(1, a, b, c, d);
        f.ssse3 = (c >> 9) & 1;
        f.sse41 = (c >> 19) & 1;
        xsave = (c >> 26) & 1;
        osxsave = (c >> 27) & 1;
        cpu_avx = (c >> 28) & 1;
    }
    if (max_leaf >= 7) {
        __cpuid_count(7, 0, a, b, c, d);
        f.bmi1 = (b >> 3) & 1;
        cpu_avx2 = (b >> 5) & 1;
        f.bmi2 = (b >> 8) & 1;
        f.sha = (b >> 29) & 1;
    }
    // AVX only where the system saves the registers' upper halves
    if (xsave && osxsave) {
        unsigned lo, hi;
        asm volatile("xgetbv" : "=a"(lo), "=d"(hi) : "c"(0));
        if (!((lo >> 1) & 1))  // (no SSE state: very unlikely)
            f.ssse3 = f.sse41 = false;
        if ((lo >> 2) & 1) {
            f.avx = cpu_avx;
            f.avx2 = cpu_avx2;
        }
    }
#endif
    return f;
}

const Features& features() noexcept
{
    static const Features f = detect();
    return f;
}

void blocks(Impl impl, std::uint32_t* state, const std::uint8_t* data, std::size_t len) noexcept
{
    switch (impl) {
#if defined(__x86_64__)
    case Impl::shani:
        return pan_sha256_blocks_shani(state, data, len);
    case Impl::avx2:
        return pan_sha256_blocks_avx2(state, data, len);
    case Impl::avx:
        return pan_sha256_blocks_avx(state, data, len);
    case Impl::ssse3:
        return pan_sha256_blocks_ssse3(state, data, len);
#endif
    default:
        return blocks_generic(state, data, len);
    }
}

}  // namespace

std::string_view name(Impl impl) noexcept
{
    switch (impl) {
    case Impl::shani:
        return "sha-ni";
    case Impl::avx2:
        return "avx2";
    case Impl::avx:
        return "avx";
    case Impl::ssse3:
        return "ssse3";
    case Impl::generic:
        break;
    }
    return "generic";
}

bool supported(Impl impl) noexcept
{
    const Features& f = features();
    switch (impl) {
    case Impl::shani:
        return f.sha && f.ssse3 && f.sse41;
    case Impl::avx2:
        // (sha256-simd checks AVX2 alone; its code uses andn and rorx too)
        return f.avx2 && f.bmi1 && f.bmi2;
    case Impl::avx:
        return f.avx;
    case Impl::ssse3:
        return f.ssse3;
    case Impl::generic:
        break;
    }
    return true;
}

Impl best() noexcept
{
    static const Impl chosen = [] {
        for (Impl impl : all_impls)
            if (supported(impl))
                return impl;
        return Impl::generic;
    }();
    return chosen;
}

Hasher::Hasher(Impl impl) noexcept : impl_(impl)
{
    reset();
}

void Hasher::reset() noexcept
{
    state_ = initial;
    buffered_ = 0;
    length_ = 0;
}

Hasher& Hasher::update(std::span<const std::uint8_t> data) noexcept
{
    const std::uint8_t* p = data.data();
    std::size_t n = data.size();
    length_ += n;
    if (buffered_ > 0) {
        std::size_t take = std::min(n, block_size - buffered_);
        std::memcpy(buffer_.data() + buffered_, p, take);
        buffered_ += take;
        p += take;
        n -= take;
        if (buffered_ < block_size)
            return *this;
        blocks(impl_, state_.data(), buffer_.data(), block_size);
        buffered_ = 0;
    }
    if (std::size_t whole = n & ~(block_size - 1)) {
        blocks(impl_, state_.data(), p, whole);
        p += whole;
        n -= whole;
    }
    if (n > 0) {
        std::memcpy(buffer_.data(), p, n);
        buffered_ = n;
    }
    return *this;
}

Hasher& Hasher::update(std::string_view data) noexcept
{
    return update(std::span(reinterpret_cast<const std::uint8_t*>(data.data()), data.size()));
}

// checkSum (sha256.go): 0x80, zeros, then the length in bits (big-endian)
Digest Hasher::finish() noexcept
{
    std::array<std::uint8_t, block_size> last{};
    std::memcpy(last.data(), buffer_.data(), buffered_);
    last[buffered_] = 0x80;
    if (buffered_ >= block_size - 8) {
        blocks(impl_, state_.data(), last.data(), block_size);
        last.fill(0);
    }
    std::uint64_t bits = length_ << 3;
    for (int i = 0; i < 8; i++)
        last[block_size - 1 - i] = static_cast<std::uint8_t>(bits >> (8 * i));
    blocks(impl_, state_.data(), last.data(), block_size);

    Digest digest;
    for (std::size_t i = 0; i < 8; i++)
        for (std::size_t j = 0; j < 4; j++)
            digest[4 * i + j] = static_cast<std::uint8_t>(state_[i] >> (24 - 8 * j));
    reset();
    return digest;
}

Digest hash(std::span<const std::uint8_t> data, Impl impl) noexcept
{
    return Hasher(impl).update(data).finish();
}

Digest hash(std::string_view data, Impl impl) noexcept
{
    return Hasher(impl).update(data).finish();
}

}  // namespace pan::sha256
