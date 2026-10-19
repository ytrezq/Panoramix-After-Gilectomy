// keccak-256 (the EVM's SHA3, not FIPS-202's SHA3-256: the padding byte is
// 0x01): Keccak-f[1600], rate 136 bytes. machine.hpp: keccak256.
#include <cstring>

#include "exec/machine.hpp"

namespace pan::exec {

namespace {

constexpr u64 kRoundConstants[24] = {
    0x0000000000000001ull, 0x0000000000008082ull, 0x800000000000808aull, 0x8000000080008000ull,
    0x000000000000808bull, 0x0000000080000001ull, 0x8000000080008081ull, 0x8000000000008009ull,
    0x000000000000008aull, 0x0000000000000088ull, 0x0000000080008009ull, 0x000000008000000aull,
    0x000000008000808bull, 0x800000000000008bull, 0x8000000000008089ull, 0x8000000000008003ull,
    0x8000000000008002ull, 0x8000000000000080ull, 0x000000000000800aull, 0x800000008000000aull,
    0x8000000080008081ull, 0x8000000000008080ull, 0x0000000080000001ull, 0x8000000080008008ull,
};

// rho offsets and pi positions, in the order of the lane walk
constexpr int kRho[24] = {1, 3, 6, 10, 15, 21, 28, 36, 45, 55, 2, 14, 27, 41, 56, 8, 25, 43, 62, 18, 39, 61, 20, 44};
constexpr int kPi[24] = {10, 7, 11, 17, 18, 3, 5, 16, 8, 21, 24, 4, 15, 23, 19, 13, 12, 2, 20, 14, 22, 9, 6, 1};

inline u64 rotl(u64 x, int n) noexcept { return (x << n) | (x >> (64 - n)); }

void keccak_f(u64 a[25]) noexcept {
    for (int round = 0; round < 24; ++round) {
        u64 c[5];
        for (int x = 0; x < 5; ++x) c[x] = a[x] ^ a[x + 5] ^ a[x + 10] ^ a[x + 15] ^ a[x + 20];
        for (int x = 0; x < 5; ++x) {
            const u64 d = c[(x + 4) % 5] ^ rotl(c[(x + 1) % 5], 1);
            for (int y = 0; y < 25; y += 5) a[y + x] ^= d;
        }
        u64 t = a[1];
        for (int i = 0; i < 24; ++i) {
            const int j = kPi[i];
            const u64 next = a[j];
            a[j] = rotl(t, kRho[i]);
            t = next;
        }
        for (int y = 0; y < 25; y += 5) {
            u64 row[5];
            for (int x = 0; x < 5; ++x) row[x] = a[y + x];
            for (int x = 0; x < 5; ++x) a[y + x] = row[x] ^ (~row[(x + 1) % 5] & row[(x + 2) % 5]);
        }
        a[0] ^= kRoundConstants[round];
    }
}

inline u64 load_le64(const u8* p) noexcept {
    u64 v = 0;
    for (int i = 7; i >= 0; --i) v = (v << 8) | p[i];
    return v;
}

}  // namespace

Word256 keccak256(std::span<const u8> data) noexcept {
    constexpr usize rate = 136;
    u64 a[25] = {};
    const u8* p = data.data();
    usize n = data.size();
    while (n >= rate) {
        for (usize i = 0; i < rate / 8; ++i) a[i] ^= load_le64(p + 8 * i);
        keccak_f(a);
        p += rate;
        n -= rate;
    }
    u8 last[rate] = {};
    if (n) std::memcpy(last, p, n);
    last[n] ^= 0x01;
    last[rate - 1] ^= 0x80;
    for (usize i = 0; i < rate / 8; ++i) a[i] ^= load_le64(last + 8 * i);
    keccak_f(a);
    u8 out[32];
    for (int i = 0; i < 4; ++i)
        for (int b = 0; b < 8; ++b) out[8 * i + b] = u8(a[i] >> (8 * b));
    return Word256::from_be(std::span<const u8>(out, 32));
}

}  // namespace pan::exec
