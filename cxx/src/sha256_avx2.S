// SHA-256 blocks, with AVX2 (and BMI1, BMI2: andn, rorx).
//
// A translation into GNU as (Intel syntax) of sha256-simd's sha256blockAvx2_amd64.s
// (https://github.com/libonomy/sha256-simd, commit df94ecd9f4af;
// vendored in cxx/third_party/sha256-simd, see its NOTICE). The original's
// header:
//
//   SHA256 implementation for AVX2
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
// the arguments in registers (System V), the callee-saved registers saved;
// `{load}` keeps the encoding of the one register move GNU as would encode
// otherwise.
//
// void pan_sha256_blocks_avx2(uint32_t state[8], const uint8_t* data, size_t len)
// (System V ABI): the state updated with the 64-byte blocks of data; len is a
// multiple of 64, at least 64.

#include "sha256_asm.h"

        .intel_syntax noprefix

        SHA256_RODATA
        .p2align 6
avx2_K256:
        .quad 0x71374491428a2f98
        .quad 0xe9b5dba5b5c0fbcf
        .quad 0x71374491428a2f98
        .quad 0xe9b5dba5b5c0fbcf
        .quad 0x59f111f13956c25b
        .quad 0xab1c5ed5923f82a4
        .quad 0x59f111f13956c25b
        .quad 0xab1c5ed5923f82a4
        .quad 0x12835b01d807aa98
        .quad 0x550c7dc3243185be
        .quad 0x12835b01d807aa98
        .quad 0x550c7dc3243185be
        .quad 0x80deb1fe72be5d74
        .quad 0xc19bf1749bdc06a7
        .quad 0x80deb1fe72be5d74
        .quad 0xc19bf1749bdc06a7
        .quad 0xefbe4786e49b69c1
        .quad 0x240ca1cc0fc19dc6
        .quad 0xefbe4786e49b69c1
        .quad 0x240ca1cc0fc19dc6
        .quad 0x4a7484aa2de92c6f
        .quad 0x76f988da5cb0a9dc
        .quad 0x4a7484aa2de92c6f
        .quad 0x76f988da5cb0a9dc
        .quad 0xa831c66d983e5152
        .quad 0xbf597fc7b00327c8
        .quad 0xa831c66d983e5152
        .quad 0xbf597fc7b00327c8
        .quad 0xd5a79147c6e00bf3
        .quad 0x1429296706ca6351
        .quad 0xd5a79147c6e00bf3
        .quad 0x1429296706ca6351
        .quad 0x2e1b213827b70a85
        .quad 0x53380d134d2c6dfc
        .quad 0x2e1b213827b70a85
        .quad 0x53380d134d2c6dfc
        .quad 0x766a0abb650a7354
        .quad 0x92722c8581c2c92e
        .quad 0x766a0abb650a7354
        .quad 0x92722c8581c2c92e
        .quad 0xa81a664ba2bfe8a1
        .quad 0xc76c51a3c24b8b70
        .quad 0xa81a664ba2bfe8a1
        .quad 0xc76c51a3c24b8b70
        .quad 0xd6990624d192e819
        .quad 0x106aa070f40e3585
        .quad 0xd6990624d192e819
        .quad 0x106aa070f40e3585
        .quad 0x1e376c0819a4c116
        .quad 0x34b0bcb52748774c
        .quad 0x1e376c0819a4c116
        .quad 0x34b0bcb52748774c
        .quad 0x4ed8aa4a391c0cb3
        .quad 0x682e6ff35b9cca4f
        .quad 0x4ed8aa4a391c0cb3
        .quad 0x682e6ff35b9cca4f
        .quad 0x78a5636f748f82ee
        .quad 0x8cc7020884c87814
        .quad 0x78a5636f748f82ee
        .quad 0x8cc7020884c87814
        .quad 0xa4506ceb90befffa
        .quad 0xc67178f2bef9a3f7
        .quad 0xa4506ceb90befffa
        .quad 0xc67178f2bef9a3f7
        .quad 0x0405060700010203
        .quad 0x0c0d0e0f08090a0b
        .quad 0x0405060700010203
        .quad 0x0c0d0e0f08090a0b
        .quad 0x0b0a090803020100
        .quad 0xffffffffffffffff
        .quad 0x0b0a090803020100
        .quad 0xffffffffffffffff
        .quad 0xffffffffffffffff
        .quad 0x0b0a090803020100
        .quad 0xffffffffffffffff
        .quad 0x0b0a090803020100

        .text
        // func blockAvx2(h []uint32, message []uint8)
SHA256_FUNCTION(pan_sha256_blocks_avx2)
        push        rbx
        push        rbp
        push        r12
        push        r13
        push        r14
        push        r15
        // DI: &h, SI: &message, DX: len(message) (Go: from its arguments' frame)
        add         rdx, rsi                     // end pointer of input
        mov         r11, rsp                     // copy stack pointer
        sub         rsp, 0x220                   // sp -= 0x220
        and         rsp, 0xfffffffffffffc00      // align stack frame
        add         rsp, 0x1c0
        mov         [rsp + 0x40], rdi            // save ctx
        mov         [rsp + 0x48], rsi            // save input
        mov         [rsp + 0x50], rdx            // save end pointer
        mov         [rsp + 0x58], r11            // save copy of stack pointer

        vzeroupper
        add         rsi, 0x40                    // input++
        mov         eax, [rdi]
        mov         r12, rsi                     // borrow $T1
        mov         ebx, [rdi + 4]
        cmp         rsi, rdx                     // $_end
        mov         ecx, [rdi + 8]
        cmove       r12, rsp
        mov         edx, [rdi + 12]
        mov         r8d, [rdi + 16]
        mov         r9d, [rdi + 20]
        mov         r10d, [rdi + 24]
        mov         r11d, [rdi + 28]

        lea         rbp, [rip + avx2_K256]
        vmovdqa     ymm8, [rbp + 0x220]
        vmovdqa     ymm9, [rbp + 0x240]
        vmovdqa     ymm10, [rbp + 0x200]

.Lavx2_loop0:
        {load} vmovdqa ymm7, ymm10

        // Load first 16 dwords from two blocks
        movdqu      xmm0, [rsi - 64]             // vmovdqu xmm0,XMMWORD PTR [rsi-0x40]
        movdqu      xmm1, [rsi - 48]             // vmovdqu xmm1,XMMWORD PTR [rsi-0x30]
        movdqu      xmm2, [rsi - 32]             // vmovdqu xmm2,XMMWORD PTR [rsi-0x20]
        movdqu      xmm3, [rsi - 16]             // vmovdqu xmm3,XMMWORD PTR [rsi-0x10]

        // Byte swap data and transpose data into high/low
        vinserti128 ymm0, ymm0, [r12], 0x1
        vinserti128 ymm1, ymm1, [r12 + 0x10], 0x1
        vpshufb     ymm0, ymm0, ymm7
        vinserti128 ymm2, ymm2, [r12 + 0x20], 0x1
        vpshufb     ymm1, ymm1, ymm7
        vinserti128 ymm3, ymm3, [r12 + 0x30], 0x1

        lea         rbp, [rip + avx2_K256]
        vpshufb     ymm2, ymm2, ymm7
        vpaddd      ymm4, ymm0, [rbp]
        vpshufb     ymm3, ymm3, ymm7
        vpaddd      ymm5, ymm1, [rbp + 0x20]
        vpaddd      ymm6, ymm2, [rbp + 0x40]
        vpaddd      ymm7, ymm3, [rbp + 0x60]

        vmovdqa     [rsp], ymm4
        xor         r14, r14
        vmovdqa     [rsp+0x20], ymm5

        add         rsp, -0x40
        mov         rdi, rbx
        vmovdqa     [rsp], ymm6
        xor         rdi, rcx                     // magic
        vmovdqa     [rsp+0x20], ymm7
        mov         r12, r9
        add         rbp, 0x80

.Lavx2_loop1:
        // Schedule 48 input dwords, by doing 3 rounds of 12 each
        // Note: SIMD instructions are interleaved with the SHA calculations
        add         rsp, -0x40
        vpalignr    ymm4, ymm1, ymm0, 0x4

        // ROUND(AX, BX, CX, DX, R8, R9, R10, R11, R12, R13, R14, R15, DI, SP, 0x80)
        add         r11d, [rsp+0x80]
        and         r12d, r8d
        rorx        r13d, r8d, 0x19
        vpalignr    ymm7, ymm3, ymm2, 0x4
        rorx        r15d, r8d, 0xb
        lea         eax, [rax+r14*1]
        lea         r11d, [r11+r12*1]
        vpsrld      ymm6, ymm4, 0x7
        andn        r12d, r8d, r10d
        xor         r13d, r15d
        rorx        r14d, r8d, 0x6
        vpaddd      ymm0, ymm0, ymm7
        lea         r11d, [r11+r12*1]
        xor         r13d, r14d
        mov         r15d, eax
        vpsrld      ymm7, ymm4, 0x3
        rorx        r12d, eax, 0x16
        lea         r11d, [r11+r13*1]
        xor         r15d, ebx
        vpslld      ymm5, ymm4, 0xe
        rorx        r14d, eax, 0xd
        rorx        r13d, eax, 0x2
        lea         edx, [rdx+r11*1]
        vpxor       ymm4, ymm7, ymm6
        and         edi, r15d
        xor         r14d, r12d
        xor         edi, ebx
        vpshufd     ymm7, ymm3, 0xfa
        xor         r14d, r13d
        lea         r11d, [r11+rdi*1]
        mov         r12d, r8d
        vpsrld      ymm6, ymm6, 0xb

        // ROUND(R11, AX, BX, CX, DX, R8, R9, R10, R12, R13, R14, DI, R15, SP, 0x84)
        add         r10d, [rsp+0x84]
        and         r12d, edx
        rorx        r13d, edx, 0x19
        vpxor       ymm4, ymm4, ymm5
        rorx        edi, edx, 0xb
        lea         r11d, [r11+r14*1]
        lea         r10d, [r10+r12*1]
        vpslld      ymm5, ymm5, 0xb
        andn        r12d, edx, r9d
        xor         r13d, edi
        rorx        r14d, edx, 0x6
        vpxor       ymm4, ymm4, ymm6
        lea         r10d, [r10+r12*1]
        xor         r13d, r14d
        mov         edi, r11d
        vpsrld      ymm6, ymm7, 0xa
        rorx        r12d, r11d, 0x16
        lea         r10d, [r10+r13*1]
        xor         edi, eax
        vpxor       ymm4, ymm4, ymm5
        rorx        r14d, r11d, 0xd
        rorx        r13d, r11d, 0x2
        lea         ecx, [rcx+r10*1]
        vpsrlq      ymm7, ymm7, 0x11
        and         r15d, edi
        xor         r14d, r12d
        xor         r15d, eax
        vpaddd      ymm0, ymm0, ymm4
        xor         r14d, r13d
        lea         r10d, [r10+r15*1]
        mov         r12d, edx
        vpxor       ymm6, ymm6, ymm7

        // ROUND(R10, R11, AX, BX, CX, DX, R8, R9, R12, R13, R14, R15, DI, SP, 0x88)
        add         r9d, [rsp+0x88]
        and         r12d, ecx
        rorx        r13d, ecx, 0x19
        vpsrlq      ymm7, ymm7, 0x2
        rorx        r15d, ecx, 0xb
        lea         r10d, [r10+r14*1]
        lea         r9d, [r9+r12*1]
        vpxor       ymm6, ymm6, ymm7
        andn        r12d, ecx, r8d
        xor         r13d, r15d
        rorx        r14d, ecx, 0x6
        vpshufb     ymm6, ymm6, ymm8
        lea         r9d, [r9+r12*1]
        xor         r13d, r14d
        mov         r15d, r10d
        vpaddd      ymm0, ymm0, ymm6
        rorx        r12d, r10d, 0x16
        lea         r9d, [r9+r13*1]
        xor         r15d, r11d
        vpshufd     ymm7, ymm0, 0x50
        rorx        r14d, r10d, 0xd
        rorx        r13d, r10d, 0x2
        lea         ebx, [rbx+r9*1]
        vpsrld      ymm6, ymm7, 0xa
        and         edi, r15d
        xor         r14d, r12d
        xor         edi, r11d
        vpsrlq      ymm7, ymm7, 0x11
        xor         r14d, r13d
        lea         r9d, [r9+rdi*1]
        mov         r12d, ecx
        vpxor       ymm6, ymm6, ymm7

        // ROUND(R9, R10, R11, AX, BX, CX, DX, R8, R12, R13, R14, DI, R15, SP, 0x8c)
        add         r8d, [rsp+0x8c]
        and         r12d, ebx
        rorx        r13d, ebx, 0x19
        vpsrlq      ymm7, ymm7, 0x2
        rorx        edi, ebx, 0xb
        lea         r9d, [r9+r14*1]
        lea         r8d, [r8+r12*1]
        vpxor       ymm6, ymm6, ymm7
        andn        r12d, ebx, edx
        xor         r13d, edi
        rorx        r14d, ebx, 0x6
        vpshufb     ymm6, ymm6, ymm9
        lea         r8d, [r8+r12*1]
        xor         r13d, r14d
        mov         edi, r9d
        vpaddd      ymm0, ymm0, ymm6
        rorx        r12d, r9d, 0x16
        lea         r8d, [r8+r13*1]
        xor         edi, r10d
        vpaddd      ymm6, ymm0, [rbp+0x0]
        rorx        r14d, r9d, 0xd
        rorx        r13d, r9d, 0x2
        lea         eax, [rax+r8*1]
        and         r15d, edi
        xor         r14d, r12d
        xor         r15d, r10d
        xor         r14d, r13d
        lea         r8d, [r8+r15*1]
        mov         r12d, ebx

        vmovdqa     [rsp], ymm6
        vpalignr    ymm4, ymm2, ymm1, 0x4

        // ROUND(R8, R9, R10, R11, AX, BX, CX, DX, R12, R13, R14, R15, DI, SP, 0xa0)
        add         edx, [rsp+0xa0]
        and         r12d, eax
        rorx        r13d, eax, 0x19
        vpalignr    ymm7, ymm0, ymm3, 0x4
        rorx        r15d, eax, 0xb
        lea         r8d, [r8+r14*1]
        lea         edx, [rdx+r12*1]
        vpsrld      ymm6, ymm4, 0x7
        andn        r12d, eax, ecx
        xor         r13d, r15d
        rorx        r14d, eax, 0x6
        vpaddd      ymm1, ymm1, ymm7
        lea         edx, [rdx+r12*1]
        xor         r13d, r14d
        mov         r15d, r8d
        vpsrld      ymm7, ymm4, 0x3
        rorx        r12d, r8d, 0x16
        lea         edx, [rdx+r13*1]
        xor         r15d, r9d
        vpslld      ymm5, ymm4, 0xe
        rorx        r14d, r8d, 0xd
        rorx        r13d, r8d, 0x2
        lea         r11d, [r11+rdx*1]
        vpxor       ymm4, ymm7, ymm6
        and         edi, r15d
        xor         r14d, r12d
        xor         edi, r9d
        vpshufd     ymm7, ymm0, 0xfa
        xor         r14d, r13d
        lea         edx, [rdx+rdi*1]
        mov         r12d, eax
        vpsrld      ymm6, ymm6, 0xb

        // ROUND(DX, R8, R9, R10, R11, AX, BX, CX, R12, R13, R14, DI, R15, SP, 0xa4)
        add         ecx, [rsp+0xa4]
        and         r12d, r11d
        rorx        r13d, r11d, 0x19
        vpxor       ymm4, ymm4, ymm5
        rorx        edi, r11d, 0xb
        lea         edx, [rdx+r14*1]
        lea         ecx, [rcx+r12*1]
        vpslld      ymm5, ymm5, 0xb
        andn        r12d, r11d, ebx
        xor         r13d, edi
        rorx        r14d, r11d, 0x6
        vpxor       ymm4, ymm4, ymm6
        lea         ecx, [rcx+r12*1]
        xor         r13d, r14d
        mov         edi, edx
        vpsrld      ymm6, ymm7, 0xa
        rorx        r12d, edx, 0x16
        lea         ecx, [rcx+r13*1]
        xor         edi, r8d
        vpxor       ymm4, ymm4, ymm5
        rorx        r14d, edx, 0xd
        rorx        r13d, edx, 0x2
        lea         r10d, [r10+rcx*1]
        vpsrlq      ymm7, ymm7, 0x11
        and         r15d, edi
        xor         r14d, r12d
        xor         r15d, r8d
        vpaddd      ymm1, ymm1, ymm4
        xor         r14d, r13d
        lea         ecx, [rcx+r15*1]
        mov         r12d, r11d
        vpxor       ymm6, ymm6, ymm7

        // ROUND(CX, DX, R8, R9, R10, R11, AX, BX, R12, R13, R14, R15, DI, SP, 0xa8)
        add         ebx, [rsp+0xa8]
        and         r12d, r10d
        rorx        r13d, r10d, 0x19
        vpsrlq      ymm7, ymm7, 0x2
        rorx        r15d, r10d, 0xb
        lea         ecx, [rcx+r14*1]
        lea         ebx, [rbx+r12*1]
        vpxor       ymm6, ymm6, ymm7
        andn        r12d, r10d, eax
        xor         r13d, r15d
        rorx        r14d, r10d, 0x6
        vpshufb     ymm6, ymm6, ymm8
        lea         ebx, [rbx+r12*1]
        xor         r13d, r14d
        mov         r15d, ecx
        vpaddd      ymm1, ymm1, ymm6
        rorx        r12d, ecx, 0x16
        lea         ebx, [rbx+r13*1]
        xor         r15d, edx
        vpshufd     ymm7, ymm1, 0x50
        rorx        r14d, ecx, 0xd
        rorx        r13d, ecx, 0x2
        lea         r9d, [r9+rbx*1]
        vpsrld      ymm6, ymm7, 0xa
        and         edi, r15d
        xor         r14d, r12d
        xor         edi, edx
        vpsrlq      ymm7, ymm7, 0x11
        xor         r14d, r13d
        lea         ebx, [rbx+rdi*1]
        mov         r12d, r10d
        vpxor       ymm6, ymm6, ymm7

        // ROUND(BX, CX, DX, R8, R9, R10, R11, AX, R12, R13, R14, DI, R15, SP, 0xac)
        add         eax, [rsp+0xac]
        and         r12d, r9d
        rorx        r13d, r9d, 0x19
        vpsrlq      ymm7, ymm7, 0x2
        rorx        edi, r9d, 0xb
        lea         ebx, [rbx+r14*1]
        lea         eax, [rax+r12*1]
        vpxor       ymm6, ymm6, ymm7
        andn        r12d, r9d, r11d
        xor         r13d, edi
        rorx        r14d, r9d, 0x6
        vpshufb     ymm6, ymm6, ymm9
        lea         eax, [rax+r12*1]
        xor         r13d, r14d
        mov         edi, ebx
        vpaddd      ymm1, ymm1, ymm6
        rorx        r12d, ebx, 0x16
        lea         eax, [rax+r13*1]
        xor         edi, ecx
        vpaddd      ymm6, ymm1, [rbp+0x20]
        rorx        r14d, ebx, 0xd
        rorx        r13d, ebx, 0x2
        lea         r8d, [r8+rax*1]
        and         r15d, edi
        xor         r14d, r12d
        xor         r15d, ecx
        xor         r14d, r13d
        lea         eax, [rax+r15*1]
        mov         r12d, r9d

        vmovdqa     [rsp+0x20], ymm6

        lea         rsp, [rsp-0x40]
        vpalignr    ymm4, ymm3, ymm2, 0x4

        // ROUND(AX, BX, CX, DX, R8, R9, R10, R11, R12, R13, R14, R15, DI, SP, 0x80)
        add         r11d, [rsp+0x80]
        and         r12d, r8d
        rorx        r13d, r8d, 0x19
        vpalignr    ymm7, ymm1, ymm0, 0x4
        rorx        r15d, r8d, 0xb
        lea         eax, [rax+r14*1]
        lea         r11d, [r11+r12*1]
        vpsrld      ymm6, ymm4, 0x7
        andn        r12d, r8d, r10d
        xor         r13d, r15d
        rorx        r14d, r8d, 0x6
        vpaddd      ymm2, ymm2, ymm7
        lea         r11d, [r11+r12*1]
        xor         r13d, r14d
        mov         r15d, eax
        vpsrld      ymm7, ymm4, 0x3
        rorx        r12d, eax, 0x16
        lea         r11d, [r11+r13*1]
        xor         r15d, ebx
        vpslld      ymm5, ymm4, 0xe
        rorx        r14d, eax, 0xd
        rorx        r13d, eax, 0x2
        lea         edx, [rdx+r11*1]
        vpxor       ymm4, ymm7, ymm6
        and         edi, r15d
        xor         r14d, r12d
        xor         edi, ebx
        vpshufd     ymm7, ymm1, 0xfa
        xor         r14d, r13d
        lea         r11d, [r11+rdi*1]
        mov         r12d, r8d
        vpsrld      ymm6, ymm6, 0xb

        // ROUND(R11, AX, BX, CX, DX, R8, R9, R10, R12, R13, R14, DI, R15, SP, 0x84)
        add         r10d, [rsp+0x84]
        and         r12d, edx
        rorx        r13d, edx, 0x19
        vpxor       ymm4, ymm4, ymm5
        rorx        edi, edx, 0xb
        lea         r11d, [r11+r14*1]
        lea         r10d, [r10+r12*1]
        vpslld      ymm5, ymm5, 0xb
        andn        r12d, edx, r9d
        xor         r13d, edi
        rorx        r14d, edx, 0x6
        vpxor       ymm4, ymm4, ymm6
        lea         r10d, [r10+r12*1]
        xor         r13d, r14d
        mov         edi, r11d
        vpsrld      ymm6, ymm7, 0xa
        rorx        r12d, r11d, 0x16
        lea         r10d, [r10+r13*1]
        xor         edi, eax
        vpxor       ymm4, ymm4, ymm5
        rorx        r14d, r11d, 0xd
        rorx        r13d, r11d, 0x2
        lea         ecx, [rcx+r10*1]
        vpsrlq      ymm7, ymm7, 0x11
        and         r15d, edi
        xor         r14d, r12d
        xor         r15d, eax
        vpaddd      ymm2, ymm2, ymm4
        xor         r14d, r13d
        lea         r10d, [r10+r15*1]
        mov         r12d, edx
        vpxor       ymm6, ymm6, ymm7

        // ROUND(R10, R11, AX, BX, CX, DX, R8, R9, R12, R13, R14, R15, DI, SP, 0x88)
        add         r9d, [rsp+0x88]
        and         r12d, ecx
        rorx        r13d, ecx, 0x19
        vpsrlq      ymm7, ymm7, 0x2
        rorx        r15d, ecx, 0xb
        lea         r10d, [r10+r14*1]
        lea         r9d, [r9+r12*1]
        vpxor       ymm6, ymm6, ymm7
        andn        r12d, ecx, r8d
        xor         r13d, r15d
        rorx        r14d, ecx, 0x6
        vpshufb     ymm6, ymm6, ymm8
        lea         r9d, [r9+r12*1]
        xor         r13d, r14d
        mov         r15d, r10d
        vpaddd      ymm2, ymm2, ymm6
        rorx        r12d, r10d, 0x16
        lea         r9d, [r9+r13*1]
        xor         r15d, r11d
        vpshufd     ymm7, ymm2, 0x50
        rorx        r14d, r10d, 0xd
        rorx        r13d, r10d, 0x2
        lea         ebx, [rbx+r9*1]
        vpsrld      ymm6, ymm7, 0xa
        and         edi, r15d
        xor         r14d, r12d
        xor         edi, r11d
        vpsrlq      ymm7, ymm7, 0x11
        xor         r14d, r13d
        lea         r9d, [r9+rdi*1]
        mov         r12d, ecx
        vpxor       ymm6, ymm6, ymm7

        // ROUND(R9, R10, R11, AX, BX, CX, DX, R8, R12, R13, R14, DI, R15, SP, 0x8c)
        add         r8d, [rsp+0x8c]
        and         r12d, ebx
        rorx        r13d, ebx, 0x19
        vpsrlq      ymm7, ymm7, 0x2
        rorx        edi, ebx, 0xb
        lea         r9d, [r9+r14*1]
        lea         r8d, [r8+r12*1]
        vpxor       ymm6, ymm6, ymm7
        andn        r12d, ebx, edx
        xor         r13d, edi
        rorx        r14d, ebx, 0x6
        vpshufb     ymm6, ymm6, ymm9
        lea         r8d, [r8+r12*1]
        xor         r13d, r14d
        mov         edi, r9d
        vpaddd      ymm2, ymm2, ymm6
        rorx        r12d, r9d, 0x16
        lea         r8d, [r8+r13*1]
        xor         edi, r10d
        vpaddd      ymm6, ymm2, [rbp+0x40]
        rorx        r14d, r9d, 0xd
        rorx        r13d, r9d, 0x2
        lea         eax, [rax+r8*1]
        and         r15d, edi
        xor         r14d, r12d
        xor         r15d, r10d
        xor         r14d, r13d
        lea         r8d, [r8+r15*1]
        mov         r12d, ebx

        vmovdqa     [rsp], ymm6
        vpalignr    ymm4, ymm0, ymm3, 0x4

        // ROUND(R8, R9, R10, R11, AX, BX, CX, DX, R12, R13, R14, R15, DI, SP, 0xa0)
        add         edx, [rsp+0xa0]
        and         r12d, eax
        rorx        r13d, eax, 0x19
        vpalignr    ymm7, ymm2, ymm1, 0x4
        rorx        r15d, eax, 0xb
        lea         r8d, [r8+r14*1]
        lea         edx, [rdx+r12*1]
        vpsrld      ymm6, ymm4, 0x7
        andn        r12d, eax, ecx
        xor         r13d, r15d
        rorx        r14d, eax, 0x6
        vpaddd      ymm3, ymm3, ymm7
        lea         edx, [rdx+r12*1]
        xor         r13d, r14d
        mov         r15d, r8d
        vpsrld      ymm7, ymm4, 0x3
        rorx        r12d, r8d, 0x16
        lea         edx, [rdx+r13*1]
        xor         r15d, r9d
        vpslld      ymm5, ymm4, 0xe
        rorx        r14d, r8d, 0xd
        rorx        r13d, r8d, 0x2
        lea         r11d, [r11+rdx*1]
        vpxor       ymm4, ymm7, ymm6
        and         edi, r15d
        xor         r14d, r12d
        xor         edi, r9d
        vpshufd     ymm7, ymm2, 0xfa
        xor         r14d, r13d
        lea         edx, [rdx+rdi*1]
        mov         r12d, eax
        vpsrld      ymm6, ymm6, 0xb

        // ROUND(DX, R8, R9, R10, R11, AX, BX, CX, R12, R13, R14, DI, R15, SP, 0xa4)
        add         ecx, [rsp+0xa4]
        and         r12d, r11d
        rorx        r13d, r11d, 0x19
        vpxor       ymm4, ymm4, ymm5
        rorx        edi, r11d, 0xb
        lea         edx, [rdx+r14*1]
        lea         ecx, [rcx+r12*1]
        vpslld      ymm5, ymm5, 0xb
        andn        r12d, r11d, ebx
        xor         r13d, edi
        rorx        r14d, r11d, 0x6
        vpxor       ymm4, ymm4, ymm6
        lea         ecx, [rcx+r12*1]
        xor         r13d, r14d
        mov         edi, edx
        vpsrld      ymm6, ymm7, 0xa
        rorx        r12d, edx, 0x16
        lea         ecx, [rcx+r13*1]
        xor         edi, r8d
        vpxor       ymm4, ymm4, ymm5
        rorx        r14d, edx, 0xd
        rorx        r13d, edx, 0x2
        lea         r10d, [r10+rcx*1]
        vpsrlq      ymm7, ymm7, 0x11
        and         r15d, edi
        xor         r14d, r12d
        xor         r15d, r8d
        vpaddd      ymm3, ymm3, ymm4
        xor         r14d, r13d
        lea         ecx, [rcx+r15*1]
        mov         r12d, r11d
        vpxor       ymm6, ymm6, ymm7

        // ROUND(CX, DX, R8, R9, R10, R11, AX, BX, R12, R13, R14, R15, DI, SP, 0xa8)
        add         ebx, [rsp+0xa8]
        and         r12d, r10d
        rorx        r13d, r10d, 0x19
        vpsrlq      ymm7, ymm7, 0x2
        rorx        r15d, r10d, 0xb
        lea         ecx, [rcx+r14*1]
        lea         ebx, [rbx+r12*1]
        vpxor       ymm6, ymm6, ymm7
        andn        r12d, r10d, eax
        xor         r13d, r15d
        rorx        r14d, r10d, 0x6
        vpshufb     ymm6, ymm6, ymm8
        lea         ebx, [rbx+r12*1]
        xor         r13d, r14d
        mov         r15d, ecx
        vpaddd      ymm3, ymm3, ymm6
        rorx        r12d, ecx, 0x16
        lea         ebx, [rbx+r13*1]
        xor         r15d, edx
        vpshufd     ymm7, ymm3, 0x50
        rorx        r14d, ecx, 0xd
        rorx        r13d, ecx, 0x2
        lea         r9d, [r9+rbx*1]
        vpsrld      ymm6, ymm7, 0xa
        and         edi, r15d
        xor         r14d, r12d
        xor         edi, edx
        vpsrlq      ymm7, ymm7, 0x11
        xor         r14d, r13d
        lea         ebx, [rbx+rdi*1]
        mov         r12d, r10d
        vpxor       ymm6, ymm6, ymm7

        // ROUND(BX, CX, DX, R8, R9, R10, R11, AX, R12, R13, R14, DI, R15, SP, 0xac)
        add         eax, [rsp+0xac]
        and         r12d, r9d
        rorx        r13d, r9d, 0x19
        vpsrlq      ymm7, ymm7, 0x2
        rorx        edi, r9d, 0xb
        lea         ebx, [rbx+r14*1]
        lea         eax, [rax+r12*1]
        vpxor       ymm6, ymm6, ymm7
        andn        r12d, r9d, r11d
        xor         r13d, edi
        rorx        r14d, r9d, 0x6
        vpshufb     ymm6, ymm6, ymm9
        lea         eax, [rax+r12*1]
        xor         r13d, r14d
        mov         edi, ebx
        vpaddd      ymm3, ymm3, ymm6
        rorx        r12d, ebx, 0x16
        lea         eax, [rax+r13*1]
        xor         edi, ecx
        vpaddd      ymm6, ymm3, [rbp+0x60]
        rorx        r14d, ebx, 0xd
        rorx        r13d, ebx, 0x2
        lea         r8d, [r8+rax*1]
        and         r15d, edi
        xor         r14d, r12d
        xor         r15d, ecx
        xor         r14d, r13d
        lea         eax, [rax+r15*1]
        mov         r12d, r9d

        vmovdqa     [rsp+0x20], ymm6
        add         rbp, 0x80

        cmp         byte ptr [rbp + 0x3], 0x0
        jne         .Lavx2_loop1

        // ROUND(AX, BX, CX, DX, R8, R9, R10, R11, R12, R13, R14, R15, DI, SP, 0x40)
        add         r11d, [rsp+0x40]
        and         r12d, r8d
        rorx        r13d, r8d, 0x19
        rorx        r15d, r8d, 0xb
        lea         eax, [rax+r14*1]
        lea         r11d, [r11+r12*1]
        andn        r12d, r8d, r10d
        xor         r13d, r15d
        rorx        r14d, r8d, 0x6
        lea         r11d, [r11+r12*1]
        xor         r13d, r14d
        mov         r15d, eax
        rorx        r12d, eax, 0x16
        lea         r11d, [r11+r13*1]
        xor         r15d, ebx
        rorx        r14d, eax, 0xd
        rorx        r13d, eax, 0x2
        lea         edx, [rdx+r11*1]
        and         edi, r15d
        xor         r14d, r12d
        xor         edi, ebx
        xor         r14d, r13d
        lea         r11d, [r11+rdi*1]
        mov         r12d, r8d

        // ROUND(R11, AX, BX, CX, DX, R8, R9, R10, R12, R13, R14, DI, R15, SP, 0x44)
        add         r10d, [rsp+0x44]
        and         r12d, edx
        rorx        r13d, edx, 0x19
        rorx        edi, edx, 0xb
        lea         r11d, [r11+r14*1]
        lea         r10d, [r10+r12*1]
        andn        r12d, edx, r9d
        xor         r13d, edi
        rorx        r14d, edx, 0x6
        lea         r10d, [r10+r12*1]
        xor         r13d, r14d
        mov         edi, r11d
        rorx        r12d, r11d, 0x16
        lea         r10d, [r10+r13*1]
        xor         edi, eax
        rorx        r14d, r11d, 0xd
        rorx        r13d, r11d, 0x2
        lea         ecx, [rcx+r10*1]
        and         r15d, edi
        xor         r14d, r12d
        xor         r15d, eax
        xor         r14d, r13d
        lea         r10d, [r10+r15*1]
        mov         r12d, edx

        // ROUND(R10, R11, AX, BX, CX, DX, R8, R9, R12, R13, R14, R15, DI, SP, 0x48)
        add         r9d, [rsp+0x48]
        and         r12d, ecx
        rorx        r13d, ecx, 0x19
        rorx        r15d, ecx, 0xb
        lea         r10d, [r10+r14*1]
        lea         r9d, [r9+r12*1]
        andn        r12d, ecx, r8d
        xor         r13d, r15d
        rorx        r14d, ecx, 0x6
        lea         r9d, [r9+r12*1]
        xor         r13d, r14d
        mov         r15d, r10d
        rorx        r12d, r10d, 0x16
        lea         r9d, [r9+r13*1]
        xor         r15d, r11d
        rorx        r14d, r10d, 0xd
        rorx        r13d, r10d, 0x2
        lea         ebx, [rbx+r9*1]
        and         edi, r15d
        xor         r14d, r12d
        xor         edi, r11d
        xor         r14d, r13d
        lea         r9d, [r9+rdi*1]
        mov         r12d, ecx

        // ROUND(R9, R10, R11, AX, BX, CX, DX, R8, R12, R13, R14, DI, R15, SP, 0x4c)
        add         r8d, [rsp+0x4c]
        and         r12d, ebx
        rorx        r13d, ebx, 0x19
        rorx        edi, ebx, 0xb
        lea         r9d, [r9+r14*1]
        lea         r8d, [r8+r12*1]
        andn        r12d, ebx, edx
        xor         r13d, edi
        rorx        r14d, ebx, 0x6
        lea         r8d, [r8+r12*1]
        xor         r13d, r14d
        mov         edi, r9d
        rorx        r12d, r9d, 0x16
        lea         r8d, [r8+r13*1]
        xor         edi, r10d
        rorx        r14d, r9d, 0xd
        rorx        r13d, r9d, 0x2
        lea         eax, [rax+r8*1]
        and         r15d, edi
        xor         r14d, r12d
        xor         r15d, r10d
        xor         r14d, r13d
        lea         r8d, [r8+r15*1]
        mov         r12d, ebx

        // ROUND(R8, R9, R10, R11, AX, BX, CX, DX, R12, R13, R14, R15, DI, SP, 0x60)
        add         edx, [rsp+0x60]
        and         r12d, eax
        rorx        r13d, eax, 0x19
        rorx        r15d, eax, 0xb
        lea         r8d, [r8+r14*1]
        lea         edx, [rdx+r12*1]
        andn        r12d, eax, ecx
        xor         r13d, r15d
        rorx        r14d, eax, 0x6
        lea         edx, [rdx+r12*1]
        xor         r13d, r14d
        mov         r15d, r8d
        rorx        r12d, r8d, 0x16
        lea         edx, [rdx+r13*1]
        xor         r15d, r9d
        rorx        r14d, r8d, 0xd
        rorx        r13d, r8d, 0x2
        lea         r11d, [r11+rdx*1]
        and         edi, r15d
        xor         r14d, r12d
        xor         edi, r9d
        xor         r14d, r13d
        lea         edx, [rdx+rdi*1]
        mov         r12d, eax

        // ROUND(DX, R8, R9, R10, R11, AX, BX, CX, R12, R13, R14, DI, R15, SP, 0x64)
        add         ecx, [rsp+0x64]
        and         r12d, r11d
        rorx        r13d, r11d, 0x19
        rorx        edi, r11d, 0xb
        lea         edx, [rdx+r14*1]
        lea         ecx, [rcx+r12*1]
        andn        r12d, r11d, ebx
        xor         r13d, edi
        rorx        r14d, r11d, 0x6
        lea         ecx, [rcx+r12*1]
        xor         r13d, r14d
        mov         edi, edx
        rorx        r12d, edx, 0x16
        lea         ecx, [rcx+r13*1]
        xor         edi, r8d
        rorx        r14d, edx, 0xd
        rorx        r13d, edx, 0x2
        lea         r10d, [r10+rcx*1]
        and         r15d, edi
        xor         r14d, r12d
        xor         r15d, r8d
        xor         r14d, r13d
        lea         ecx, [rcx+r15*1]
        mov         r12d, r11d

        // ROUND(CX, DX, R8, R9, R10, R11, AX, BX, R12, R13, R14, R15, DI, SP, 0x68)
        add         ebx, [rsp+0x68]
        and         r12d, r10d
        rorx        r13d, r10d, 0x19
        rorx        r15d, r10d, 0xb
        lea         ecx, [rcx+r14*1]
        lea         ebx, [rbx+r12*1]
        andn        r12d, r10d, eax
        xor         r13d, r15d
        rorx        r14d, r10d, 0x6
        lea         ebx, [rbx+r12*1]
        xor         r13d, r14d
        mov         r15d, ecx
        rorx        r12d, ecx, 0x16
        lea         ebx, [rbx+r13*1]
        xor         r15d, edx
        rorx        r14d, ecx, 0xd
        rorx        r13d, ecx, 0x2
        lea         r9d, [r9+rbx*1]
        and         edi, r15d
        xor         r14d, r12d
        xor         edi, edx
        xor         r14d, r13d
        lea         ebx, [rbx+rdi*1]
        mov         r12d, r10d

        // ROUND(BX, CX, DX, R8, R9, R10, R11, AX, R12, R13, R14, DI, R15, SP, 0x6c)
        add         eax, [rsp+0x6c]
        and         r12d, r9d
        rorx        r13d, r9d, 0x19
        rorx        edi, r9d, 0xb
        lea         ebx, [rbx+r14*1]
        lea         eax, [rax+r12*1]
        andn        r12d, r9d, r11d
        xor         r13d, edi
        rorx        r14d, r9d, 0x6
        lea         eax, [rax+r12*1]
        xor         r13d, r14d
        mov         edi, ebx
        rorx        r12d, ebx, 0x16
        lea         eax, [rax+r13*1]
        xor         edi, ecx
        rorx        r14d, ebx, 0xd
        rorx        r13d, ebx, 0x2
        lea         r8d, [r8+rax*1]
        and         r15d, edi
        xor         r14d, r12d
        xor         r15d, ecx
        xor         r14d, r13d
        lea         eax, [rax+r15*1]
        mov         r12d, r9d

        // ROUND(AX, BX, CX, DX, R8, R9, R10, R11, R12, R13, R14, R15, DI, SP, 0x00)
        add         r11d, [rsp]
        and         r12d, r8d
        rorx        r13d, r8d, 0x19
        rorx        r15d, r8d, 0xb
        lea         eax, [rax+r14*1]
        lea         r11d, [r11+r12*1]
        andn        r12d, r8d, r10d
        xor         r13d, r15d
        rorx        r14d, r8d, 0x6
        lea         r11d, [r11+r12*1]
        xor         r13d, r14d
        mov         r15d, eax
        rorx        r12d, eax, 0x16
        lea         r11d, [r11+r13*1]
        xor         r15d, ebx
        rorx        r14d, eax, 0xd
        rorx        r13d, eax, 0x2
        lea         edx, [rdx+r11*1]
        and         edi, r15d
        xor         r14d, r12d
        xor         edi, ebx
        xor         r14d, r13d
        lea         r11d, [r11+rdi*1]
        mov         r12d, r8d

        // ROUND(R11, AX, BX, CX, DX, R8, R9, R10, R12, R13, R14, DI, R15, SP, 0x04)
        add         r10d, [rsp+0x4]
        and         r12d, edx
        rorx        r13d, edx, 0x19
        rorx        edi, edx, 0xb
        lea         r11d, [r11+r14*1]
        lea         r10d, [r10+r12*1]
        andn        r12d, edx, r9d
        xor         r13d, edi
        rorx        r14d, edx, 0x6
        lea         r10d, [r10+r12*1]
        xor         r13d, r14d
        mov         edi, r11d
        rorx        r12d, r11d, 0x16
        lea         r10d, [r10+r13*1]
        xor         edi, eax
        rorx        r14d, r11d, 0xd
        rorx        r13d, r11d, 0x2
        lea         ecx, [rcx+r10*1]
        and         r15d, edi
        xor         r14d, r12d
        xor         r15d, eax
        xor         r14d, r13d
        lea         r10d, [r10+r15*1]
        mov         r12d, edx

        // ROUND(R10, R11, AX, BX, CX, DX, R8, R9, R12, R13, R14, R15, DI, SP, 0x08)
        add         r9d, [rsp+0x8]
        and         r12d, ecx
        rorx        r13d, ecx, 0x19
        rorx        r15d, ecx, 0xb
        lea         r10d, [r10+r14*1]
        lea         r9d, [r9+r12*1]
        andn        r12d, ecx, r8d
        xor         r13d, r15d
        rorx        r14d, ecx, 0x6
        lea         r9d, [r9+r12*1]
        xor         r13d, r14d
        mov         r15d, r10d
        rorx        r12d, r10d, 0x16
        lea         r9d, [r9+r13*1]
        xor         r15d, r11d
        rorx        r14d, r10d, 0xd
        rorx        r13d, r10d, 0x2
        lea         ebx, [rbx+r9*1]
        and         edi, r15d
        xor         r14d, r12d
        xor         edi, r11d
        xor         r14d, r13d
        lea         r9d, [r9+rdi*1]
        mov         r12d, ecx

        // ROUND(R9, R10, R11, AX, BX, CX, DX, R8, R12, R13, R14, DI, R15, SP, 0x0c)
        add         r8d, [rsp+0xc]
        and         r12d, ebx
        rorx        r13d, ebx, 0x19
        rorx        edi, ebx, 0xb
        lea         r9d, [r9+r14*1]
        lea         r8d, [r8+r12*1]
        andn        r12d, ebx, edx
        xor         r13d, edi
        rorx        r14d, ebx, 0x6
        lea         r8d, [r8+r12*1]
        xor         r13d, r14d
        mov         edi, r9d
        rorx        r12d, r9d, 0x16
        lea         r8d, [r8+r13*1]
        xor         edi, r10d
        rorx        r14d, r9d, 0xd
        rorx        r13d, r9d, 0x2
        lea         eax, [rax+r8*1]
        and         r15d, edi
        xor         r14d, r12d
        xor         r15d, r10d
        xor         r14d, r13d
        lea         r8d, [r8+r15*1]
        mov         r12d, ebx

        // ROUND(R8, R9, R10, R11, AX, BX, CX, DX, R12, R13, R14, R15, DI, SP, 0x20)
        add         edx, [rsp+0x20]
        and         r12d, eax
        rorx        r13d, eax, 0x19
        rorx        r15d, eax, 0xb
        lea         r8d, [r8+r14*1]
        lea         edx, [rdx+r12*1]
        andn        r12d, eax, ecx
        xor         r13d, r15d
        rorx        r14d, eax, 0x6
        lea         edx, [rdx+r12*1]
        xor         r13d, r14d
        mov         r15d, r8d
        rorx        r12d, r8d, 0x16
        lea         edx, [rdx+r13*1]
        xor         r15d, r9d
        rorx        r14d, r8d, 0xd
        rorx        r13d, r8d, 0x2
        lea         r11d, [r11+rdx*1]
        and         edi, r15d
        xor         r14d, r12d
        xor         edi, r9d
        xor         r14d, r13d
        lea         edx, [rdx+rdi*1]
        mov         r12d, eax

        // ROUND(DX, R8, R9, R10, R11, AX, BX, CX, R12, R13, R14, DI, R15, SP, 0x24)
        add         ecx, [rsp+0x24]
        and         r12d, r11d
        rorx        r13d, r11d, 0x19
        rorx        edi, r11d, 0xb
        lea         edx, [rdx+r14*1]
        lea         ecx, [rcx+r12*1]
        andn        r12d, r11d, ebx
        xor         r13d, edi
        rorx        r14d, r11d, 0x6
        lea         ecx, [rcx+r12*1]
        xor         r13d, r14d
        mov         edi, edx
        rorx        r12d, edx, 0x16
        lea         ecx, [rcx+r13*1]
        xor         edi, r8d
        rorx        r14d, edx, 0xd
        rorx        r13d, edx, 0x2
        lea         r10d, [r10+rcx*1]
        and         r15d, edi
        xor         r14d, r12d
        xor         r15d, r8d
        xor         r14d, r13d
        lea         ecx, [rcx+r15*1]
        mov         r12d, r11d

        // ROUND(CX, DX, R8, R9, R10, R11, AX, BX, R12, R13, R14, R15, DI, SP, 0x28)
        add         ebx, [rsp+0x28]
        and         r12d, r10d
        rorx        r13d, r10d, 0x19
        rorx        r15d, r10d, 0xb
        lea         ecx, [rcx+r14*1]
        lea         ebx, [rbx+r12*1]
        andn        r12d, r10d, eax
        xor         r13d, r15d
        rorx        r14d, r10d, 0x6
        lea         ebx, [rbx+r12*1]
        xor         r13d, r14d
        mov         r15d, ecx
        rorx        r12d, ecx, 0x16
        lea         ebx, [rbx+r13*1]
        xor         r15d, edx
        rorx        r14d, ecx, 0xd
        rorx        r13d, ecx, 0x2
        lea         r9d, [r9+rbx*1]
        and         edi, r15d
        xor         r14d, r12d
        xor         edi, edx
        xor         r14d, r13d
        lea         ebx, [rbx+rdi*1]
        mov         r12d, r10d

        // ROUND(BX, CX, DX, R8, R9, R10, R11, AX, R12, R13, R14, DI, R15, SP, 0x2c)
        add         eax, [rsp+0x2c]
        and         r12d, r9d
        rorx        r13d, r9d, 0x19
        rorx        edi, r9d, 0xb
        lea         ebx, [rbx+r14*1]
        lea         eax, [rax+r12*1]
        andn        r12d, r9d, r11d
        xor         r13d, edi
        rorx        r14d, r9d, 0x6
        lea         eax, [rax+r12*1]
        xor         r13d, r14d
        mov         edi, ebx
        rorx        r12d, ebx, 0x16
        lea         eax, [rax+r13*1]
        xor         edi, ecx
        rorx        r14d, ebx, 0xd
        rorx        r13d, ebx, 0x2
        lea         r8d, [r8+rax*1]
        and         r15d, edi
        xor         r14d, r12d
        xor         r15d, ecx
        xor         r14d, r13d
        lea         eax, [rax+r15*1]
        mov         r12d, r9d

        mov         rdi, [rsp + 0x200]           // $_ctx
        add         rax, r14

        lea         rbp, [rsp + 0x1c0]

        add         eax, [rdi]
        add         ebx, [rdi + 4]
        add         ecx, [rdi + 8]
        add         edx, [rdi + 12]
        add         r8d, [rdi + 16]
        add         r9d, [rdi + 20]
        add         r10d, [rdi + 24]
        add         r11d, [rdi + 28]

        mov         [rdi], eax
        mov         [rdi + 4], ebx
        mov         [rdi + 8], ecx
        mov         [rdi + 12], edx
        mov         [rdi + 16], r8d
        mov         [rdi + 20], r9d
        mov         [rdi + 24], r10d
        mov         [rdi + 28], r11d

        cmp         rsi, [rbp + 0x50]            // $_end
        je          .Lavx2_done

        xor         r14, r14
        mov         rdi, rbx
        xor         rdi, rcx                     // magic
        mov         r12, r9

.Lavx2_loop2:
        // ROUND(AX, BX, CX, DX, R8, R9, R10, R11, R12, R13, R14, R15, DI, BP, 0x10)
        add         r11d, [rbp+0x10]
        and         r12d, r8d
        rorx        r13d, r8d, 0x19
        rorx        r15d, r8d, 0xb
        lea         eax, [rax+r14*1]
        lea         r11d, [r11+r12*1]
        andn        r12d, r8d, r10d
        xor         r13d, r15d
        rorx        r14d, r8d, 0x6
        lea         r11d, [r11+r12*1]
        xor         r13d, r14d
        mov         r15d, eax
        rorx        r12d, eax, 0x16
        lea         r11d, [r11+r13*1]
        xor         r15d, ebx
        rorx        r14d, eax, 0xd
        rorx        r13d, eax, 0x2
        lea         edx, [rdx+r11*1]
        and         edi, r15d
        xor         r14d, r12d
        xor         edi, ebx
        xor         r14d, r13d
        lea         r11d, [r11+rdi*1]
        mov         r12d, r8d

        // ROUND(R11, AX, BX, CX, DX, R8, R9, R10, R12, R13, R14, DI, R15, BP, 0x14)
        add         r10d, [rbp+0x14]
        and         r12d, edx
        rorx        r13d, edx, 0x19
        rorx        edi, edx, 0xb
        lea         r11d, [r11+r14*1]
        lea         r10d, [r10+r12*1]
        andn        r12d, edx, r9d
        xor         r13d, edi
        rorx        r14d, edx, 0x6
        lea         r10d, [r10+r12*1]
        xor         r13d, r14d
        mov         edi, r11d
        rorx        r12d, r11d, 0x16
        lea         r10d, [r10+r13*1]
        xor         edi, eax
        rorx        r14d, r11d, 0xd
        rorx        r13d, r11d, 0x2
        lea         ecx, [rcx+r10*1]
        and         r15d, edi
        xor         r14d, r12d
        xor         r15d, eax
        xor         r14d, r13d
        lea         r10d, [r10+r15*1]
        mov         r12d, edx

        // ROUND(R10, R11, AX, BX, CX, DX, R8, R9, R12, R13, R14, R15, DI, BP, 0x18)
        add         r9d, [rbp+0x18]
        and         r12d, ecx
        rorx        r13d, ecx, 0x19
        rorx        r15d, ecx, 0xb
        lea         r10d, [r10+r14*1]
        lea         r9d, [r9+r12*1]
        andn        r12d, ecx, r8d
        xor         r13d, r15d
        rorx        r14d, ecx, 0x6
        lea         r9d, [r9+r12*1]
        xor         r13d, r14d
        mov         r15d, r10d
        rorx        r12d, r10d, 0x16
        lea         r9d, [r9+r13*1]
        xor         r15d, r11d
        rorx        r14d, r10d, 0xd
        rorx        r13d, r10d, 0x2
        lea         ebx, [rbx+r9*1]
        and         edi, r15d
        xor         r14d, r12d
        xor         edi, r11d
        xor         r14d, r13d
        lea         r9d, [r9+rdi*1]
        mov         r12d, ecx

        // ROUND(R9, R10, R11, AX, BX, CX, DX, R8, R12, R13, R14, DI, R15, BP, 0x1c)
        add         r8d, [rbp+0x1c]
        and         r12d, ebx
        rorx        r13d, ebx, 0x19
        rorx        edi, ebx, 0xb
        lea         r9d, [r9+r14*1]
        lea         r8d, [r8+r12*1]
        andn        r12d, ebx, edx
        xor         r13d, edi
        rorx        r14d, ebx, 0x6
        lea         r8d, [r8+r12*1]
        xor         r13d, r14d
        mov         edi, r9d
        rorx        r12d, r9d, 0x16
        lea         r8d, [r8+r13*1]
        xor         edi, r10d
        rorx        r14d, r9d, 0xd
        rorx        r13d, r9d, 0x2
        lea         eax, [rax+r8*1]
        and         r15d, edi
        xor         r14d, r12d
        xor         r15d, r10d
        xor         r14d, r13d
        lea         r8d, [r8+r15*1]
        mov         r12d, ebx

        // ROUND(R8, R9, R10, R11, AX, BX, CX, DX, R12, R13, R14, R15, DI, BP, 0x30)
        add         edx, [rbp+0x30]
        and         r12d, eax
        rorx        r13d, eax, 0x19
        rorx        r15d, eax, 0xb
        lea         r8d, [r8+r14*1]
        lea         edx, [rdx+r12*1]
        andn        r12d, eax, ecx
        xor         r13d, r15d
        rorx        r14d, eax, 0x6
        lea         edx, [rdx+r12*1]
        xor         r13d, r14d
        mov         r15d, r8d
        rorx        r12d, r8d, 0x16
        lea         edx, [rdx+r13*1]
        xor         r15d, r9d
        rorx        r14d, r8d, 0xd
        rorx        r13d, r8d, 0x2
        lea         r11d, [r11+rdx*1]
        and         edi, r15d
        xor         r14d, r12d
        xor         edi, r9d
        xor         r14d, r13d
        lea         edx, [rdx+rdi*1]
        mov         r12d, eax

        // ROUND(DX, R8, R9, R10, R11, AX, BX, CX, R12, R13, R14, DI, R15, BP, 0x34)
        add         ecx, [rbp+0x34]
        and         r12d, r11d
        rorx        r13d, r11d, 0x19
        rorx        edi, r11d, 0xb
        lea         edx, [rdx+r14*1]
        lea         ecx, [rcx+r12*1]
        andn        r12d, r11d, ebx
        xor         r13d, edi
        rorx        r14d, r11d, 0x6
        lea         ecx, [rcx+r12*1]
        xor         r13d, r14d
        mov         edi, edx
        rorx        r12d, edx, 0x16
        lea         ecx, [rcx+r13*1]
        xor         edi, r8d
        rorx        r14d, edx, 0xd
        rorx        r13d, edx, 0x2
        lea         r10d, [r10+rcx*1]
        and         r15d, edi
        xor         r14d, r12d
        xor         r15d, r8d
        xor         r14d, r13d
        lea         ecx, [rcx+r15*1]
        mov         r12d, r11d

        // ROUND(CX, DX, R8, R9, R10, R11, AX, BX, R12, R13, R14, R15, DI, BP, 0x38)
        add         ebx, [rbp+0x38]
        and         r12d, r10d
        rorx        r13d, r10d, 0x19
        rorx        r15d, r10d, 0xb
        lea         ecx, [rcx+r14*1]
        lea         ebx, [rbx+r12*1]
        andn        r12d, r10d, eax
        xor         r13d, r15d
        rorx        r14d, r10d, 0x6
        lea         ebx, [rbx+r12*1]
        xor         r13d, r14d
        mov         r15d, ecx
        rorx        r12d, ecx, 0x16
        lea         ebx, [rbx+r13*1]
        xor         r15d, edx
        rorx        r14d, ecx, 0xd
        rorx        r13d, ecx, 0x2
        lea         r9d, [r9+rbx*1]
        and         edi, r15d
        xor         r14d, r12d
        xor         edi, edx
        xor         r14d, r13d
        lea         ebx, [rbx+rdi*1]
        mov         r12d, r10d

        // ROUND(BX, CX, DX, R8, R9, R10, R11, AX, R12, R13, R14, DI, R15, BP, 0x3c)
        add         eax, [rbp+0x3c]
        and         r12d, r9d
        rorx        r13d, r9d, 0x19
        rorx        edi, r9d, 0xb
        lea         ebx, [rbx+r14*1]
        lea         eax, [rax+r12*1]
        andn        r12d, r9d, r11d
        xor         r13d, edi
        rorx        r14d, r9d, 0x6
        lea         eax, [rax+r12*1]
        xor         r13d, r14d
        mov         edi, ebx
        rorx        r12d, ebx, 0x16
        lea         eax, [rax+r13*1]
        xor         edi, ecx
        rorx        r14d, ebx, 0xd
        rorx        r13d, ebx, 0x2
        lea         r8d, [r8+rax*1]
        and         r15d, edi
        xor         r14d, r12d
        xor         r15d, ecx
        xor         r14d, r13d
        lea         eax, [rax+r15*1]
        mov         r12d, r9d

        add         rbp, -0x40
        cmp         rbp, rsp
        jae         .Lavx2_loop2

        mov         rdi, [rsp + 0x200]           // $_ctx
        add         rax, r14

        add         rsp, 0x1c0

        add         eax, [rdi]
        add         ebx, [rdi + 4]
        add         ecx, [rdi + 8]
        add         edx, [rdi + 12]
        add         r8d, [rdi + 16]
        add         r9d, [rdi + 20]

        add         rsi, 0x80                    // input += 2
        add         r10d, [rdi + 24]
        mov         r12, rsi
        add         r11d, [rdi + 28]
        cmp         rsi, [rsp + 0x50]            // input == _end

        mov         [rdi], eax
        cmove       r12, rsp
        mov         [rdi], eax
        mov         [rdi + 4], ebx
        mov         [rdi + 8], ecx
        mov         [rdi + 12], edx
        mov         [rdi + 16], r8d
        mov         [rdi + 20], r9d
        mov         [rdi + 24], r10d
        mov         [rdi + 28], r11d

        jbe         .Lavx2_loop0
        lea         rbp, [rsp]

.Lavx2_done:
        mov         rsp, rbp
        mov         rsp, [rsp + 0x58]
        vzeroupper

        pop         r15
        pop         r14
        pop         r13
        pop         r12
        pop         rbp
        pop         rbx
        ret
SHA256_END(pan_sha256_blocks_avx2)
