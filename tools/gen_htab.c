// gen_htab: the tables of the hashes a compiler writes as numbers
// (storage.s's hash_table, python's storage.hash_table): keccak(n) of the
// DATA_SLOTS first slots, keccak(key . n) of the MAP_KEYS first keys of
// the MAP_SLOTS first slots - solidity's w32(key) + w32(n), vyper's
// w32(n) + w32(key) -, each table sorted by the hash (big-endian, as
// memcmp orders them). Made at build time with keccak.s itself: every
// process made them at its first storage constant, 10240 hashes (8% of
// the instructions of the corpora, a fixed cost of every contract).
//
//     cc -O2 -o build/gen_htab tools/gen_htab.c build/keccak.o
//     build/gen_htab build/storage_htab.bin
//
// The output: solidity's table, then vyper's, of 40-byte entries (the
// hash, then the slot and the key as u32, the key -1 for keccak(n)),
// what storage.s includes (.incbin).
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void keccak256(const void *buf, size_t len, void *out);
// (keccak.o's keccak_value makes a value: never called here)
void mk_int_bytes_be(void) { abort(); }

enum { DATA_SLOTS = 4096, MAP_KEYS = 16, MAP_SLOTS = 64,
       COUNT = DATA_SLOTS + MAP_KEYS * MAP_SLOTS };

struct entry {
    uint8_t hash[32];
    uint32_t n, k;
};

static int cmp(const void *a, const void *b) { return memcmp(a, b, 32); }

int main(int argc, char **argv) {
    static struct entry t[COUNT];
    FILE *f;
    // a known digest first: keccak of 32 zero bytes (slot 0's data)
    static const uint8_t zero32[32];
    static const uint8_t k0[32] = {0x29, 0x0d, 0xec, 0xd9, 0x54, 0x8b, 0x62, 0xa8, 0xd6, 0x03, 0x45,
                                   0xa9, 0x88, 0x38, 0x6f, 0xc8, 0x4b, 0xa6, 0xbc, 0x95, 0x48, 0x40,
                                   0x08, 0xf6, 0x36, 0x2f, 0x93, 0x16, 0x0e, 0xf3, 0xe5, 0x63};
    uint8_t d[32];
    if (sizeof(struct entry) != 40 || argc != 2) {
        fprintf(stderr, "usage: gen_htab OUT\n");
        return 2;
    }
    keccak256(zero32, 32, d);
    if (memcmp(d, k0, 32) != 0) {
        fprintf(stderr, "gen_htab: keccak256 gives a wrong digest\n");
        return 1;
    }
    if (!(f = fopen(argv[1], "wb"))) {
        perror(argv[1]);
        return 1;
    }
    for (int lang = 0; lang < 2; lang++) {
        int e = 0;
        for (uint32_t n = 0; n < DATA_SLOTS; n++, e++) {
            uint8_t w[32] = {0};
            w[31] = n & 0xff;
            w[30] = n >> 8;
            keccak256(w, 32, t[e].hash);
            t[e].n = n;
            t[e].k = 0xffffffff;
        }
        for (uint32_t i = 0; i < MAP_SLOTS * MAP_KEYS; i++, e++) {
            uint8_t w[64] = {0};
            uint32_t n = i / MAP_KEYS, k = i % MAP_KEYS;
            if (lang) {
                w[31] = n;
                w[63] = k;
            } else {
                w[31] = k;
                w[63] = n;
            }
            keccak256(w, 64, t[e].hash);
            t[e].n = n;
            t[e].k = k;
        }
        qsort(t, COUNT, sizeof t[0], cmp);
        if (fwrite(t, sizeof t[0], COUNT, f) != COUNT) {
            perror(argv[1]);
            return 1;
        }
    }
    return fclose(f) != 0;
}
