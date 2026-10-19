// SHA-256 blocks, with AVX.
//
// A translation into GNU as (Intel syntax) of sha256-simd's sha256blockAvx_amd64.s
// (https://github.com/libonomy/sha256-simd, commit df94ecd9f4af;
// vendored in cxx/third_party/sha256-simd, see its NOTICE). The original's
// header:
//
//   SHA256 implementation for AVX
//
//
//   Minio Cloud Storage, (C) 2016 Minio, Inc.
//
//   Licensed under the Apache License, Version 2.0 (the "License");
//   you may not use this file except in compliance with the License.
//   You may obtain a copy of the License at
//
//   http://www.apache.org/licenses/LICENSE-2.0
//
//   Unless required by applicable law or agreed to in writing, software
//   distributed under the License is distributed on an "AS IS" BASIS,
//   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//   See the License for the specific language governing permissions and
//   limitations under the License.
//
//
//
//   This code is based on an Intel White-Paper:
//   "Fast SHA-256 Implementations on Intel Architecture Processors"
//
//   together with the reference implementation from the following authors:
//   James Guilford <james.guilford@intel.com>
//   Kirk Yap <kirk.s.yap@intel.com>
//   Tim Chen <tim.c.chen@linux.intel.com>
//
//   For Golang it has been converted to Plan 9 assembly with the help of
//   github.com/minio/asm2plan9s to assemble Intel instructions to their Plan9
//   equivalents
//
// Changes (see the NOTICE): the Go assembler's syntax written as GNU as's, the
// same instructions, byte for byte (the encoded ones as their mnemonics);
// the arguments in registers (System V), copied where the code reads them in
// Go's frame (a frame of 80 bytes on the stack), the callee-saved registers
// saved.
//
// void pan_sha256_blocks_avx(uint32_t state[8], const uint8_t* data, size_t len)
// (System V ABI): the state updated with the 64-byte blocks of data; len is a
// multiple of 64, at least 64.

#include "sha256_asm.h"

        .intel_syntax noprefix

        SHA256_RODATA
        .p2align 6
avx_constants:
        .quad 0x71374491428a2f98
        .quad 0xe9b5dba5b5c0fbcf
        .quad 0x59f111f13956c25b
        .quad 0xab1c5ed5923f82a4
        .quad 0x12835b01d807aa98
        .quad 0x550c7dc3243185be
        .quad 0x80deb1fe72be5d74
        .quad 0xc19bf1749bdc06a7
        .quad 0xefbe4786e49b69c1
        .quad 0x240ca1cc0fc19dc6
        .quad 0x4a7484aa2de92c6f
        .quad 0x76f988da5cb0a9dc
        .quad 0xa831c66d983e5152
        .quad 0xbf597fc7b00327c8
        .quad 0xd5a79147c6e00bf3
        .quad 0x1429296706ca6351
        .quad 0x2e1b213827b70a85
        .quad 0x53380d134d2c6dfc
        .quad 0x766a0abb650a7354
        .quad 0x92722c8581c2c92e
        .quad 0xa81a664ba2bfe8a1
        .quad 0xc76c51a3c24b8b70
        .quad 0xd6990624d192e819
        .quad 0x106aa070f40e3585
        .quad 0x1e376c0819a4c116
        .quad 0x34b0bcb52748774c
        .quad 0x4ed8aa4a391c0cb3
        .quad 0x682e6ff35b9cca4f
        .quad 0x78a5636f748f82ee
        .quad 0x8cc7020884c87814
        .quad 0xa4506ceb90befffa
        .quad 0xc67178f2bef9a3f7
        .p2align 6
avx_bflipMask:
        .quad 0x0405060700010203
        .quad 0x0c0d0e0f08090a0b
        .p2align 6
avx_shuf00BA:
        .quad 0x0b0a090803020100
        .quad 0xFFFFFFFFFFFFFFFF
        .p2align 6
avx_shufDC00:
        .quad 0xFFFFFFFFFFFFFFFF
        .quad 0x0b0a090803020100

        .text
.macro ROTATE_XS
        movdqu      xmm15, xmm4
        movdqu      xmm4, xmm5
        movdqu      xmm5, xmm6
        movdqu      xmm6, xmm7
        movdqu      xmm7, xmm15
.endm

        // compute s0 four at a time and s1 two at a time
        // compute W[-16] + W[-7] 4 at a time
.macro FOUR_ROUNDS_AND_SCHED a, b, c, d, e, f, g, h
        mov         r13d, \e                     // y0 = e
        rol         r13d, 18                     // y0 = e >> (25-11)
        mov         r14d, \a                     // y1 = a
        vpalignr    xmm0, xmm7, xmm6, 0x4        // XTMP0 = W[-7]
        rol         r14d, 23                     // y1 = a >> (22-13)
        xor         r13d, \e                     // y0 = e ^ (e >> (25-11))
        mov         r15d, \f                     // y2 = f
        rol         r13d, 27                     // y0 = (e >> (11-6)) ^ (e >> (25-6))
        xor         r14d, \a                     // y1 = a ^ (a >> (22-13)
        xor         r15d, \g                     // y2 = f^g
        vpaddd      xmm0, xmm0, xmm4             // XTMP0 = W[-7] + W[-16]
        xor         r13d, \e                     // y0 = e ^ (e >> (11-6)) ^ (e >> (25-6) )
        and         r15d, \e                     // y2 = (f^g)&e
        rol         r14d, 21                     // y1 = (a >> (13-2)) ^ (a >> (22-2))
        // compute s0
        vpalignr    xmm1, xmm5, xmm4, 0x4        // XTMP1 = W[-15]
        xor         r14d, \a                     // y1 = a ^ (a >> (13-2)) ^ (a >> (22-2))
        rol         r13d, 26                     // y0 = S1 = (e>>6) & (e>>11) ^ (e>>25)
        xor         r15d, \g                     // y2 = CH = ((f^g)&e)^g
        rol         r14d, 30                     // y1 = S0 = (a>>2) ^ (a>>13) ^ (a>>22)
        add         r15d, r13d                   // y2 = S1 + CH
        add         r15d, [rsp + 48]             // y2 = k + w + S1 + CH
        mov         r13d, \a                     // y0 = a
        add         \h, r15d                     // h = h + S1 + CH + k + w
        // ROTATE_ARGS
        mov         r15d, \a                     // y2 = a
        vpsrld      xmm2, xmm1, 0x7
        or          r13d, \c                     // y0 = a|c
        add         \d, \h                       // d = d + h + S1 + CH + k + w
        and         r15d, \c                     // y2 = a&c
        vpslld      xmm3, xmm1, 0x19
        and         r13d, \b                     // y0 = (a|c)&b
        add         \h, r14d                     // h = h + S1 + CH + k + w + S0
        vpor        xmm3, xmm3, xmm2             // XTMP1 = W[-15] MY_ROR 7
        or          r13d, r15d                   // y0 = MAJ = (a|c)&b)|(a&c)
        add         \h, r13d                     // h = h + S1 + CH + k + w + S0 + MAJ
        // ROTATE_ARGS
        mov         r13d, \d                     // y0 = e
        mov         r14d, \h                     // y1 = a
        rol         r13d, 18                     // y0 = e >> (25-11)
        xor         r13d, \d                     // y0 = e ^ (e >> (25-11))
        mov         r15d, \e                     // y2 = f
        rol         r14d, 23                     // y1 = a >> (22-13)
        vpsrld      xmm2, xmm1, 0x12
        xor         r14d, \h                     // y1 = a ^ (a >> (22-13)
        rol         r13d, 27                     // y0 = (e >> (11-6)) ^ (e >> (25-6))
        xor         r15d, \f                     // y2 = f^g
        vpsrld      xmm8, xmm1, 0x3              // XTMP4 = W[-15] >> 3
        rol         r14d, 21                     // y1 = (a >> (13-2)) ^ (a >> (22-2))
        xor         r13d, \d                     // y0 = e ^ (e >> (11-6)) ^ (e >> (25-6))
        and         r15d, \d                     // y2 = (f^g)&e
        rol         r13d, 26                     // y0 = S1 = (e>>6) & (e>>11) ^ (e>>25)
        vpslld      xmm1, xmm1, 0xe
        xor         r14d, \h                     // y1 = a ^ (a >> (13-2)) ^ (a >> (22-2))
        xor         r15d, \f                     // y2 = CH = ((f^g)&e)^g
        vpxor       xmm3, xmm3, xmm1
        add         r15d, r13d                   // y2 = S1 + CH
        add         r15d, [rsp + 52]             // y2 = k + w + S1 + CH
        rol         r14d, 30                     // y1 = S0 = (a>>2) ^ (a>>13) ^ (a>>22)
        vpxor       xmm3, xmm3, xmm2             // XTMP1 = W[-15] MY_ROR 7 ^ W[-15] MY_ROR
        mov         r13d, \h                     // y0 = a
        add         \g, r15d                     // h = h + S1 + CH + k + w
        mov         r15d, \h                     // y2 = a
        vpxor       xmm1, xmm3, xmm8             // XTMP1 = s0
        or          r13d, \b                     // y0 = a|c
        add         \c, \g                       // d = d + h + S1 + CH + k + w
        and         r15d, \b                     // y2 = a&c
        // compute low s1
        vpshufd     xmm2, xmm7, 0xfa             // XTMP2 = W[-2] {BBAA}
        and         r13d, \a                     // y0 = (a|c)&b
        add         \g, r14d                     // h = h + S1 + CH + k + w + S0
        vpaddd      xmm0, xmm0, xmm1             // XTMP0 = W[-16] + W[-7] + s0
        or          r13d, r15d                   // y0 = MAJ = (a|c)&b)|(a&c)
        add         \g, r13d                     // h = h + S1 + CH + k + w + S0 + MAJ
        // ROTATE_ARGS
        mov         r13d, \c                     // y0 = e
        mov         r14d, \g                     // y1 = a
        rol         r13d, 18                     // y0 = e >> (25-11)
        xor         r13d, \c                     // y0 = e ^ (e >> (25-11))
        rol         r14d, 23                     // y1 = a >> (22-13)
        mov         r15d, \d                     // y2 = f
        xor         r14d, \g                     // y1 = a ^ (a >> (22-13)
        rol         r13d, 27                     // y0 = (e >> (11-6)) ^ (e >> (25-6))
        vpsrld      xmm8, xmm2, 0xa              // XTMP4 = W[-2] >> 10 {BBAA}
        xor         r15d, \e                     // y2 = f^g
        vpsrlq      xmm3, xmm2, 0x13             // XTMP3 = W[-2] MY_ROR 19 {xBxA}
        xor         r13d, \c                     // y0 = e ^ (e >> (11-6)) ^ (e >> (25-6))
        and         r15d, \c                     // y2 = (f^g)&e
        vpsrlq      xmm2, xmm2, 0x11             // XTMP2 = W[-2] MY_ROR 17 {xBxA}
        rol         r14d, 21                     // y1 = (a >> (13-2)) ^ (a >> (22-2))
        xor         r14d, \g                     // y1 = a ^ (a >> (13-2)) ^ (a >> (22-2))
        xor         r15d, \e                     // y2 = CH = ((f^g)&e)^g
        rol         r13d, 26                     // y0 = S1 = (e>>6) & (e>>11) ^ (e>>25)
        vpxor       xmm2, xmm2, xmm3
        add         r15d, r13d                   // y2 = S1 + CH
        rol         r14d, 30                     // y1 = S0 = (a>>2) ^ (a>>13) ^ (a>>22)
        add         r15d, [rsp + 56]             // y2 = k + w + S1 + CH
        vpxor       xmm8, xmm8, xmm2             // XTMP4 = s1 {xBxA}
        mov         r13d, \g                     // y0 = a
        add         \f, r15d                     // h = h + S1 + CH + k + w
        mov         r15d, \g                     // y2 = a
        vpshufb     xmm8, xmm8, xmm10            // XTMP4 = s1 {00BA}
        or          r13d, \a                     // y0 = a|c
        add         \b, \f                       // d = d + h + S1 + CH + k + w
        and         r15d, \a                     // y2 = a&c
        vpaddd      xmm0, xmm0, xmm8             // XTMP0 = {..., ..., W[1], W[0]}
        and         r13d, \h                     // y0 = (a|c)&b
        add         \f, r14d                     // h = h + S1 + CH + k + w + S0
        // compute high s1
        vpshufd     xmm2, xmm0, 0x50             // XTMP2 = W[-2] {DDCC}
        or          r13d, r15d                   // y0 = MAJ = (a|c)&b)|(a&c)
        add         \f, r13d                     // h = h + S1 + CH + k + w + S0 + MAJ
        // ROTATE_ARGS
        mov         r13d, \b                     // y0 = e
        rol         r13d, 18                     // y0 = e >> (25-11)
        mov         r14d, \f                     // y1 = a
        rol         r14d, 23                     // y1 = a >> (22-13)
        xor         r13d, \b                     // y0 = e ^ (e >> (25-11))
        mov         r15d, \c                     // y2 = f
        rol         r13d, 27                     // y0 = (e >> (11-6)) ^ (e >> (25-6))
        vpsrld      xmm11, xmm2, 0xa             // XTMP5 = W[-2] >> 10 {DDCC}
        xor         r14d, \f                     // y1 = a ^ (a >> (22-13)
        xor         r15d, \d                     // y2 = f^g
        vpsrlq      xmm3, xmm2, 0x13             // XTMP3 = W[-2] MY_ROR 19 {xDxC}
        xor         r13d, \b                     // y0 = e ^ (e >> (11-6)) ^ (e >> (25-6))
        and         r15d, \b                     // y2 = (f^g)&e
        rol         r14d, 21                     // y1 = (a >> (13-2)) ^ (a >> (22-2))
        vpsrlq      xmm2, xmm2, 0x11             // XTMP2 = W[-2] MY_ROR 17 {xDxC}
        xor         r14d, \f                     // y1 = a ^ (a >> (13-2)) ^ (a >> (22-2))
        rol         r13d, 26                     // y0 = S1 = (e>>6) & (e>>11) ^ (e>>25)
        xor         r15d, \d                     // y2 = CH = ((f^g)&e)^g
        vpxor       xmm2, xmm2, xmm3
        rol         r14d, 30                     // y1 = S0 = (a>>2) ^ (a>>13) ^ (a>>22)
        add         r15d, r13d                   // y2 = S1 + CH
        add         r15d, [rsp + 60]             // y2 = k + w + S1 + CH
        vpxor       xmm11, xmm11, xmm2           // XTMP5 = s1 {xDxC}
        mov         r13d, \f                     // y0 = a
        add         \e, r15d                     // h = h + S1 + CH + k + w
        mov         r15d, \f                     // y2 = a
        vpshufb     xmm11, xmm11, xmm12          // XTMP5 = s1 {DC00}
        or          r13d, \h                     // y0 = a|c
        add         \a, \e                       // d = d + h + S1 + CH + k + w
        and         r15d, \h                     // y2 = a&c
        vpaddd      xmm4, xmm11, xmm0            // X0 = {W[3], W[2], W[1], W[0]}
        and         r13d, \g                     // y0 = (a|c)&b
        add         \e, r14d                     // h = h + S1 + CH + k + w + S0
        or          r13d, r15d                   // y0 = MAJ = (a|c)&b)|(a&c)
        add         \e, r13d                     // h = h + S1 + CH + k + w + S0 + MAJ
        // ROTATE_ARGS
        ROTATE_XS
.endm

.macro DO_ROUND a, b, c, d, e, f, g, h, offset
        mov         r13d, \e                     // y0 = e
        rol         r13d, 18                     // y0 = e >> (25-11)
        mov         r14d, \a                     // y1 = a
        xor         r13d, \e                     // y0 = e ^ (e >> (25-11))
        rol         r14d, 23                     // y1 = a >> (22-13)
        mov         r15d, \f                     // y2 = f
        xor         r14d, \a                     // y1 = a ^ (a >> (22-13)
        rol         r13d, 27                     // y0 = (e >> (11-6)) ^ (e >> (25-6))
        xor         r15d, \g                     // y2 = f^g
        xor         r13d, \e                     // y0 = e ^ (e >> (11-6)) ^ (e >> (25-6))
        rol         r14d, 21                     // y1 = (a >> (13-2)) ^ (a >> (22-2))
        and         r15d, \e                     // y2 = (f^g)&e
        xor         r14d, \a                     // y1 = a ^ (a >> (13-2)) ^ (a >> (22-2))
        rol         r13d, 26                     // y0 = S1 = (e>>6) & (e>>11) ^ (e>>25)
        xor         r15d, \g                     // y2 = CH = ((f^g)&e)^g
        add         r15d, r13d                   // y2 = S1 + CH
        rol         r14d, 30                     // y1 = S0 = (a>>2) ^ (a>>13) ^ (a>>22)
        add         r15d, [rsp + \offset]        // y2 = k + w + S1 + CH
        mov         r13d, \a                     // y0 = a
        add         \h, r15d                     // h = h + S1 + CH + k + w
        mov         r15d, \a                     // y2 = a
        or          r13d, \c                     // y0 = a|c
        add         \d, \h                       // d = d + h + S1 + CH + k + w
        and         r15d, \c                     // y2 = a&c
        and         r13d, \b                     // y0 = (a|c)&b
        add         \h, r14d                     // h = h + S1 + CH + k + w + S0
        or          r13d, r15d                   // y0 = MAJ = (a|c)&b)|(a&c)
        add         \h, r13d                     // h = h + S1 + CH + k + w + S0 + MAJ
.endm

SHA256_FUNCTION(pan_sha256_blocks_avx)
        push        rbx
        push        rbp
        push        r13
        push        r14
        push        r15
        sub         rsp, 80                      // Go's arguments: h+0, message+24, lenmessage+32,
        mov         [rsp], rdi                   // and its 4 reserved ones (48..79) the code uses
        mov         [rsp + 24], rsi              // for _xfer (16 bytes), _inp_end and _inp
        mov         [rsp + 32], rdx

        mov         rsi, [rsp + 0]               // SI: &h
        mov         r8, [rsp + 24]               // &message
        mov         r9, [rsp + 32]               // length of message
        cmp         r9, 0
        je          .Lavx_done_hash
        add         r9, r8
        mov         [rsp + 64], r9               // store end of message

        // Register definition
        // a -->  eax
        // b -->  ebx
        // c -->  ecx
        // d -->  r8d
        // e -->  edx
        // f -->  r9d
        // g --> r10d
        // h --> r11d

        // y0 --> r13d
        // y1 --> r14d
        // y2 --> r15d

        mov         eax, [rsi + (0*4)]           // a = H0
        mov         ebx, [rsi + (1*4)]           // b = H1
        mov         ecx, [rsi + (2*4)]           // c = H2
        mov         r8d, [rsi + (3*4)]           // d = H3
        mov         edx, [rsi + (4*4)]           // e = H4
        mov         r9d, [rsi + (5*4)]           // f = H5
        mov         r10d, [rsi + (6*4)]          // g = H6
        mov         r11d, [rsi + (7*4)]          // h = H7

        movdqu      xmm13, [rip + avx_bflipMask]
        movdqu      xmm10, [rip + avx_shuf00BA]  // shuffle xBxA -> 00BA
        movdqu      xmm12, [rip + avx_shufDC00]  // shuffle xDxC -> DC00

        mov         rsi, [rsp + 24]              // SI: &message

.Lavx_loop0:
        lea         rbp, [rip + avx_constants]

        // byte swap first 16 dwords
        movdqu      xmm4, [rsi + 0*16]
        vpshufb     xmm4, xmm4, xmm13
        movdqu      xmm5, [rsi + 1*16]
        vpshufb     xmm5, xmm5, xmm13
        movdqu      xmm6, [rsi + 2*16]
        vpshufb     xmm6, xmm6, xmm13
        movdqu      xmm7, [rsi + 3*16]
        vpshufb     xmm7, xmm7, xmm13

        mov         [rsp + 72], rsi
        mov         rdi, 0x3

        // schedule 48 input dwords, by doing 3 rounds of 16 each
.Lavx_loop1:
        vpaddd      xmm9, xmm4, [rbp + 0]
        movdqu      [rsp + 48], xmm9
        FOUR_ROUNDS_AND_SCHED eax, ebx, ecx, r8d, edx, r9d, r10d, r11d

        vpaddd      xmm9, xmm4, [rbp + 16]
        movdqu      [rsp + 48], xmm9
        FOUR_ROUNDS_AND_SCHED edx, r9d, r10d, r11d, eax, ebx, ecx, r8d

        vpaddd      xmm9, xmm4, [rbp + 32]
        movdqu      [rsp + 48], xmm9
        FOUR_ROUNDS_AND_SCHED eax, ebx, ecx, r8d, edx, r9d, r10d, r11d

        vpaddd      xmm9, xmm4, [rbp + 48]
        movdqu      [rsp + 48], xmm9
        add         rbp, 64
        FOUR_ROUNDS_AND_SCHED edx, r9d, r10d, r11d, eax, ebx, ecx, r8d

        sub         rdi, 1
        jne         .Lavx_loop1

        mov         rdi, 0x2
.Lavx_loop2:
        vpaddd      xmm9, xmm4, [rbp + 0]
        movdqu      [rsp + 48], xmm9
        DO_ROUND eax, ebx, ecx, r8d, edx, r9d, r10d, r11d, 48
        DO_ROUND r11d, eax, ebx, ecx, r8d, edx, r9d, r10d, 52
        DO_ROUND r10d, r11d, eax, ebx, ecx, r8d, edx, r9d, 56
        DO_ROUND r9d, r10d, r11d, eax, ebx, ecx, r8d, edx, 60

        vpaddd      xmm9, xmm5, [rbp + 16]
        movdqu      [rsp + 48], xmm9
        add         rbp, 32
        DO_ROUND edx, r9d, r10d, r11d, eax, ebx, ecx, r8d, 48
        DO_ROUND r8d, edx, r9d, r10d, r11d, eax, ebx, ecx, 52
        DO_ROUND ecx, r8d, edx, r9d, r10d, r11d, eax, ebx, 56
        DO_ROUND ebx, ecx, r8d, edx, r9d, r10d, r11d, eax, 60

        movdqu      xmm4, xmm6
        movdqu      xmm5, xmm7

        sub         rdi, 1
        jne         .Lavx_loop2

        mov         rsi, [rsp + 0]               // SI: &h
        add         eax, [rsi + (0*4)]           // H0 = a + H0
        mov         [rsi + (0*4)], eax
        add         ebx, [rsi + (1*4)]           // H1 = b + H1
        mov         [rsi + (1*4)], ebx
        add         ecx, [rsi + (2*4)]           // H2 = c + H2
        mov         [rsi + (2*4)], ecx
        add         r8d, [rsi + (3*4)]           // H3 = d + H3
        mov         [rsi + (3*4)], r8d
        add         edx, [rsi + (4*4)]           // H4 = e + H4
        mov         [rsi + (4*4)], edx
        add         r9d, [rsi + (5*4)]           // H5 = f + H5
        mov         [rsi + (5*4)], r9d
        add         r10d, [rsi + (6*4)]          // H6 = g + H6
        mov         [rsi + (6*4)], r10d
        add         r11d, [rsi + (7*4)]          // H7 = h + H7
        mov         [rsi + (7*4)], r11d

        mov         rsi, [rsp + 72]
        add         rsi, 64
        cmp         [rsp + 64], rsi
        jne         .Lavx_loop0

.Lavx_done_hash:
        add         rsp, 80
        pop         r15
        pop         r14
        pop         r13
        pop         rbp
        pop         rbx
        ret
SHA256_END(pan_sha256_blocks_avx)

        // Constants table
