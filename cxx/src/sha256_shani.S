// SHA-256 blocks, with the SHA extensions (SHA-NI).
//
// A translation into GNU as (Intel syntax) of sha256-simd's sha256blockSha_amd64.s
// (https://github.com/libonomy/sha256-simd, commit df94ecd9f4af;
// vendored in cxx/third_party/sha256-simd, see its NOTICE). The original's
// header:
//
//
// Changes (see the NOTICE): the Go assembler's syntax written as GNU as's, the
// same instructions, byte for byte (the encoded ones as their mnemonics);
// the arguments in registers (System V) and rbx saved.
//
// void pan_sha256_blocks_shani(uint32_t state[8], const uint8_t* data, size_t len)
// (System V ABI): the state updated with the 64-byte blocks of data; len is a
// multiple of 64, at least 64.

#include "sha256_asm.h"

        .intel_syntax noprefix

        SHA256_RODATA
        .p2align 6
sha_K:
        .long 0x428a2f98
        .long 0x71374491
        .long 0xb5c0fbcf
        .long 0xe9b5dba5
        .long 0x3956c25b
        .long 0x59f111f1
        .long 0x923f82a4
        .long 0xab1c5ed5
        .long 0xd807aa98
        .long 0x12835b01
        .long 0x243185be
        .long 0x550c7dc3
        .long 0x72be5d74
        .long 0x80deb1fe
        .long 0x9bdc06a7
        .long 0xc19bf174
        .long 0xe49b69c1
        .long 0xefbe4786
        .long 0x0fc19dc6
        .long 0x240ca1cc
        .long 0x2de92c6f
        .long 0x4a7484aa
        .long 0x5cb0a9dc
        .long 0x76f988da
        .long 0x983e5152
        .long 0xa831c66d
        .long 0xb00327c8
        .long 0xbf597fc7
        .long 0xc6e00bf3
        .long 0xd5a79147
        .long 0x06ca6351
        .long 0x14292967
        .long 0x27b70a85
        .long 0x2e1b2138
        .long 0x4d2c6dfc
        .long 0x53380d13
        .long 0x650a7354
        .long 0x766a0abb
        .long 0x81c2c92e
        .long 0x92722c85
        .long 0xa2bfe8a1
        .long 0xa81a664b
        .long 0xc24b8b70
        .long 0xc76c51a3
        .long 0xd192e819
        .long 0xd6990624
        .long 0xf40e3585
        .long 0x106aa070
        .long 0x19a4c116
        .long 0x1e376c08
        .long 0x2748774c
        .long 0x34b0bcb5
        .long 0x391c0cb3
        .long 0x4ed8aa4a
        .long 0x5b9cca4f
        .long 0x682e6ff3
        .long 0x748f82ee
        .long 0x78a5636f
        .long 0x84c87814
        .long 0x8cc70208
        .long 0x90befffa
        .long 0xa4506ceb
        .long 0xbef9a3f7
        .long 0xc67178f2
        .p2align 6
sha_SHUF_MASK:
        .quad 0x0405060700010203
        .quad 0x0c0d0e0f08090a0b

        .text
        // Register Usage
        // BX  base address of constant table (constant)
        // DX  hash_state (constant)
        // SI  hash_data.data
        // DI  hash_data.data + hash_data.length - 64 (constant)
        // X0  scratch
        // X1  scratch
        // X2  working hash state // ABEF
        // X3  working hash state // CDGH
        // X4  first 16 bytes of block
        // X5  second 16 bytes of block
        // X6  third 16 bytes of block
        // X7  fourth 16 bytes of block
        // X12 saved hash state // ABEF
        // X13 saved hash state // CDGH
        // X15 data shuffle mask (constant)

SHA256_FUNCTION(pan_sha256_blocks_shani)
        push        rbx
        xchg        rdx, rdi                     // DX: state, SI: data, DI: len (Go: 8(SP), 16(SP), 24(SP))
        lea         rdi, [rsi + rdi*1 - 64]
        movdqu      xmm2, [rdx]
        movdqu      xmm1, [rdx + 16]
        movdqa      xmm3, xmm2
        punpckldq   xmm2, xmm1
        punpckhdq   xmm3, xmm1
        pshufd      xmm2, xmm2, 0x27
        pshufd      xmm3, xmm3, 0x27
        movdqa      xmm15, [rip + sha_SHUF_MASK]
        lea         rbx, [rip + sha_K]

        jmp         .Lsha_TEST

.Lsha_LOOP:
        movdqa      xmm12, xmm2
        movdqa      xmm13, xmm3

        // load block and shuffle
        movdqu      xmm4, [rsi]
        movdqu      xmm5, [rsi + 16]
        movdqu      xmm6, [rsi + 32]
        movdqu      xmm7, [rsi + 48]
        pshufb      xmm4, xmm15
        pshufb      xmm5, xmm15
        pshufb      xmm6, xmm15
        pshufb      xmm7, xmm15

.macro ROUND456
        paddd       xmm0, xmm5
        sha256rnds2 xmm3, xmm2
        movdqa      xmm1, xmm5
        palignr     xmm1, xmm4, 4
        paddd       xmm6, xmm1
        sha256msg2  xmm6, xmm5
        pshufd      xmm0, xmm0, 0x4e
        sha256rnds2 xmm2, xmm3
        sha256msg1  xmm4, xmm5
.endm
.macro ROUND567
        paddd       xmm0, xmm6
        sha256rnds2 xmm3, xmm2
        movdqa      xmm1, xmm6
        palignr     xmm1, xmm5, 4
        paddd       xmm7, xmm1
        sha256msg2  xmm7, xmm6
        pshufd      xmm0, xmm0, 0x4e
        sha256rnds2 xmm2, xmm3
        sha256msg1  xmm5, xmm6
.endm
.macro ROUND674
        paddd       xmm0, xmm7
        sha256rnds2 xmm3, xmm2
        movdqa      xmm1, xmm7
        palignr     xmm1, xmm6, 4
        paddd       xmm4, xmm1
        sha256msg2  xmm4, xmm7
        pshufd      xmm0, xmm0, 0x4e
        sha256rnds2 xmm2, xmm3
        sha256msg1  xmm6, xmm7
.endm
.macro ROUND745
        paddd       xmm0, xmm4
        sha256rnds2 xmm3, xmm2
        movdqa      xmm1, xmm4
        palignr     xmm1, xmm7, 4
        paddd       xmm5, xmm1
        sha256msg2  xmm5, xmm4
        pshufd      xmm0, xmm0, 0x4e
        sha256rnds2 xmm2, xmm3
        sha256msg1  xmm7, xmm4
.endm

        // rounds 0-3
        movdqa      xmm0, [rbx]
        paddd       xmm0, xmm4
        sha256rnds2 xmm3, xmm2
        pshufd      xmm0, xmm0, 0x4e
        sha256rnds2 xmm2, xmm3

        // rounds 4-7
        movdqa      xmm0, [rbx + 1*16]
        paddd       xmm0, xmm5
        sha256rnds2 xmm3, xmm2
        pshufd      xmm0, xmm0, 0x4e
        sha256rnds2 xmm2, xmm3
        sha256msg1  xmm4, xmm5

        // rounds 8-11
        movdqa      xmm0, [rbx + 2*16]
        paddd       xmm0, xmm6
        sha256rnds2 xmm3, xmm2
        pshufd      xmm0, xmm0, 0x4e
        sha256rnds2 xmm2, xmm3
        sha256msg1  xmm5, xmm6

        movdqa      xmm0, [rbx + 3*16]
        ROUND674                                 // rounds 12-15
        movdqa      xmm0, [rbx + 4*16]
        ROUND745                                 // rounds 16-19
        movdqa      xmm0, [rbx + 5*16]
        ROUND456                                 // rounds 20-23
        movdqa      xmm0, [rbx + 6*16]
        ROUND567                                 // rounds 24-27
        movdqa      xmm0, [rbx + 7*16]
        ROUND674                                 // rounds 28-31
        movdqa      xmm0, [rbx + 8*16]
        ROUND745                                 // rounds 32-35
        movdqa      xmm0, [rbx + 9*16]
        ROUND456                                 // rounds 36-39
        movdqa      xmm0, [rbx + 10*16]
        ROUND567                                 // rounds 40-43
        movdqa      xmm0, [rbx + 11*16]
        ROUND674                                 // rounds 44-47
        movdqa      xmm0, [rbx + 12*16]
        ROUND745                                 // rounds 48-51

        // rounds 52-55
        movdqa      xmm0, [rbx + 13*16]
        paddd       xmm0, xmm5
        sha256rnds2 xmm3, xmm2
        movdqa      xmm1, xmm5
        palignr     xmm1, xmm4, 4
        paddd       xmm6, xmm1
        sha256msg2  xmm6, xmm5
        pshufd      xmm0, xmm0, 0x4e
        sha256rnds2 xmm2, xmm3

        // rounds 56-59
        movdqa      xmm0, [rbx + 14*16]
        paddd       xmm0, xmm6
        sha256rnds2 xmm3, xmm2
        movdqa      xmm1, xmm6
        palignr     xmm1, xmm5, 4
        paddd       xmm7, xmm1
        sha256msg2  xmm7, xmm6
        pshufd      xmm0, xmm0, 0x4e
        sha256rnds2 xmm2, xmm3

        // rounds 60-63
        movdqa      xmm0, [rbx + 15*16]
        paddd       xmm0, xmm7
        sha256rnds2 xmm3, xmm2
        pshufd      xmm0, xmm0, 0x4e
        sha256rnds2 xmm2, xmm3

        paddd       xmm2, xmm12
        paddd       xmm3, xmm13

        add         rsi, 64
.Lsha_TEST:
        cmp         rsi, rdi
        jbe         .Lsha_LOOP

        pshufd      xmm0, xmm3, 0x4e
        pblendw     xmm0, xmm2, 0xf0
        pshufd      xmm1, xmm2, 0x4e
        pblendw     xmm1, xmm3, 0x0f
        pshufd      xmm0, xmm0, 0x1b
        pshufd      xmm1, xmm1, 0x1b

        movdqu      [rdx], xmm0
        movdqu      [rdx + 16], xmm1

        pop         rbx
        ret
SHA256_END(pan_sha256_blocks_shani)
