# BLAKE2b (python's hashlib.blake2b, unkeyed, any digest size up to 64)
# and python's random.Random's Mersenne Twister: what storage.py's check
# and its bytes getters rest on (storage.World.sym, storage.evb, the
# contents of storage.bytes_tail's worlds).
#
#   blake2b(out, outlen, data, len)   the outlen bytes of the digest at out
#   mt_seed(state, seed)              random.Random(seed) for a seed below 2^32
#   mt_next(state) -> eax             its next 32 bits (genrand_uint32)
#   mt_randrange(state, n) -> rax     _randbelow(n): getrandbits(k) until
#                                     below n, k = n.bit_length() (n <= 2^32)

.include "defs.inc"

.set MT_N, 624
.set MT_M, 397
.set MT_INDEX, 0                # the state: the index of the next word,
.set MT_WORDS, 8                # then the 624 words (u32)
.set MT_SIZEOF, 8 + 4 * MT_N

        .section .rodata
        .p2align 6
blake2b_iv:
        .quad 0x6a09e667f3bcc908, 0xbb67ae8584caa73b, 0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1
        .quad 0x510e527fade682d1, 0x9b05688c2b3e6c1f, 0x1f83d9abfb41bd6b, 0x5be0cd19137e2179
blake2b_sigma:
        .byte  0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15
        .byte 14, 10,  4,  8,  9, 15, 13,  6,  1, 12,  0,  2, 11,  7,  5,  3
        .byte 11,  8, 12,  0,  5,  2, 15, 13, 10, 14,  3,  6,  7,  1,  9,  4
        .byte  7,  9,  3,  1, 13, 12, 11, 14,  2,  6,  5, 10,  4,  0, 15,  8
        .byte  9,  0,  5,  7,  2,  4, 10, 15, 14,  1, 11, 12,  6,  8,  3, 13
        .byte  2, 12,  6, 10,  0, 11,  8,  3,  4, 13,  7,  5, 15, 14,  1,  9
        .byte 12,  5,  1, 15, 14, 13,  4, 10,  0,  7,  6,  3,  9,  2,  8, 11
        .byte 13, 11,  7, 14, 12,  1,  3,  9,  5,  0, 15,  4,  8,  6,  2, 10
        .byte  6, 15, 14,  9, 11,  3,  0,  8, 12,  2, 13,  7,  1,  4, 10,  5
        .byte 10,  2,  8,  4,  7,  6,  1,  5, 15, 11,  9, 14,  3, 12, 13,  0
        .byte  0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15
        .byte 14, 10,  4,  8,  9, 15, 13,  6,  1, 12,  0,  2, 11,  7,  5,  3
        .text

# B2_G a, b, c, d, i: the mixing function G on the words a, b, c, d of v
# (rdi), with the message words m[sigma[i]] and m[sigma[i + 1]] (rsi: m,
# rdx: the round's row of sigma)
.macro B2_G a, b, c, d, i
        movzx ecx, byte ptr [rdx + \i]
        mov r8, [rdi + 8*\a]
        add r8, [rdi + 8*\b]
        add r8, [rsi + rcx*8]
        mov r9, [rdi + 8*\d]
        xor r9, r8
        ror r9, 32
        mov r10, [rdi + 8*\c]
        add r10, r9
        mov r11, [rdi + 8*\b]
        xor r11, r10
        ror r11, 24
        movzx ecx, byte ptr [rdx + \i + 1]
        add r8, r11
        add r8, [rsi + rcx*8]
        xor r9, r8
        ror r9, 16
        add r10, r9
        xor r11, r10
        ror r11, 63
        mov [rdi + 8*\a], r8
        mov [rdi + 8*\b], r11
        mov [rdi + 8*\c], r10
        mov [rdi + 8*\d], r9
.endm

# blake2b_compress(h, block, t, last): one block of 128 bytes into the
# chained state h (8 words); t the bytes so far (this block's included),
# last: 1 for the final block
FUNC blake2b_compress
        ENTER
        sub rsp, 256
        .set BC_V, 0                    # the 16 working words
        .set BC_M, 128                  # the message's 16 words
        mov rbx, rdi
        mov r12, rcx
        mov r13, rdx
        lea rdi, [rsp + BC_M]
        mov edx, 128
        call memcpy@PLT
        xor ecx, ecx
1:      mov rax, [rbx + rcx*8]
        mov [rsp + BC_V + rcx*8], rax
        lea r8, [rip + blake2b_iv]
        mov rax, [r8 + rcx*8]
        mov [rsp + BC_V + 64 + rcx*8], rax
        inc ecx
        cmp ecx, 8
        jb 1b
        xor [rsp + BC_V + 96], r13      # v[12] ^= t (its low word: the
        test r12, r12                   # high one is 0 below 2^64 bytes)
        jz 2f
        not qword ptr [rsp + BC_V + 112]
2:      lea rdi, [rsp + BC_V]
        lea rsi, [rsp + BC_M]
        lea rdx, [rip + blake2b_sigma]
        mov r14d, 12
3:      B2_G 0, 4, 8, 12, 0
        B2_G 1, 5, 9, 13, 2
        B2_G 2, 6, 10, 14, 4
        B2_G 3, 7, 11, 15, 6
        B2_G 0, 5, 10, 15, 8
        B2_G 1, 6, 11, 12, 10
        B2_G 2, 7, 8, 13, 12
        B2_G 3, 4, 9, 14, 14
        add rdx, 16
        dec r14d
        jnz 3b
        xor ecx, ecx
4:      mov rax, [rsp + BC_V + rcx*8]
        xor rax, [rsp + BC_V + 64 + rcx*8]
        xor [rbx + rcx*8], rax
        inc ecx
        cmp ecx, 8
        jb 4b
        add rsp, 256
        LEAVE
ENDF blake2b_compress

# blake2b(out, outlen, data, len): the digest of len bytes, outlen bytes
# of it (1 to 64: hashlib.blake2b(data, digest_size=outlen).digest())
FUNC blake2b
        ENTER
        sub rsp, 224
        .set B2_H, 0                    # the state: 8 words
        .set B2_BLOCK, 64               # the last block (128 bytes)
        .set B2_OUT, 192
        .set B2_OUTLEN, 200
        .set B2_T, 208
        mov [rsp + B2_OUT], rdi
        mov [rsp + B2_OUTLEN], rsi
        mov rbx, rdx                    # the next block
        mov r12, rcx                    # the bytes left
        xor ecx, ecx
1:      lea r8, [rip + blake2b_iv]
        mov rax, [r8 + rcx*8]
        mov [rsp + B2_H + rcx*8], rax
        inc ecx
        cmp ecx, 8
        jb 1b
        mov rax, 0x01010000             # fanout 1, depth 1, no key
        or rax, rsi                     # the digest's length
        xor [rsp + B2_H], rax
        mov qword ptr [rsp + B2_T], 0
2:      cmp r12, 128                    # every block but the last
        jbe 3f
        add qword ptr [rsp + B2_T], 128
        lea rdi, [rsp + B2_H]
        mov rsi, rbx
        mov rdx, [rsp + B2_T]
        xor ecx, ecx
        call blake2b_compress
        add rbx, 128
        sub r12, 128
        jmp 2b
3:      lea rdi, [rsp + B2_BLOCK]       # the last one (all zeros for no
        xor esi, esi                    # data), padded with zeros
        mov edx, 128
        call memset@PLT
        lea rdi, [rsp + B2_BLOCK]
        mov rsi, rbx
        mov rdx, r12
        call memcpy@PLT
        add [rsp + B2_T], r12
        lea rdi, [rsp + B2_H]
        lea rsi, [rsp + B2_BLOCK]
        mov rdx, [rsp + B2_T]
        mov ecx, 1
        call blake2b_compress
        mov rdi, [rsp + B2_OUT]         # the digest: h's bytes, little-endian
        lea rsi, [rsp + B2_H]           # words
        mov rdx, [rsp + B2_OUTLEN]
        call memcpy@PLT
        add rsp, 224
        LEAVE
ENDF blake2b

# --- python's random.Random (CPython's _randommodule.c) ---

# mt_init_genrand(state, s): init_genrand
FUNC mt_init_genrand
        mov [rdi + MT_WORDS], esi
        mov ecx, 1
1:      mov eax, [rdi + MT_WORDS + rcx*4 - 4]
        mov edx, eax
        shr edx, 30
        xor eax, edx
        imul eax, eax, 1812433253
        add eax, ecx
        mov [rdi + MT_WORDS + rcx*4], eax
        inc ecx
        cmp ecx, MT_N
        jb 1b
        mov qword ptr [rdi + MT_INDEX], MT_N
        ret
ENDF mt_init_genrand

# mt_seed(state, seed): random.Random(seed) for 0 <= seed < 2^32 -
# init_by_array of the one word [seed]
FUNC mt_seed
        ENTER
        mov rbx, rdi
        mov r12d, esi                   # key[0]
        mov esi, 19650218
        call mt_init_genrand
        mov ecx, 1                      # i
        mov r8d, MT_N                   # k = max(N, key_length)
1:      mov eax, [rbx + MT_WORDS + rcx*4 - 4]
        mov edx, eax
        shr edx, 30
        xor eax, edx
        imul eax, eax, 1664525
        xor eax, [rbx + MT_WORDS + rcx*4]
        add eax, r12d                   # + key[j] + j (j always 0)
        mov [rbx + MT_WORDS + rcx*4], eax
        inc ecx
        cmp ecx, MT_N
        jb 2f
        mov eax, [rbx + MT_WORDS + 4*(MT_N - 1)]
        mov [rbx + MT_WORDS], eax
        mov ecx, 1
2:      dec r8d
        jnz 1b
        mov r8d, MT_N - 1
3:      mov eax, [rbx + MT_WORDS + rcx*4 - 4]
        mov edx, eax
        shr edx, 30
        xor eax, edx
        imul eax, eax, 1566083941
        xor eax, [rbx + MT_WORDS + rcx*4]
        sub eax, ecx
        mov [rbx + MT_WORDS + rcx*4], eax
        inc ecx
        cmp ecx, MT_N
        jb 4f
        mov eax, [rbx + MT_WORDS + 4*(MT_N - 1)]
        mov [rbx + MT_WORDS], eax
        mov ecx, 1
4:      dec r8d
        jnz 3b
        mov dword ptr [rbx + MT_WORDS], 0x80000000
        LEAVE
ENDF mt_seed

# mt_twist(state): the next 624 words
FUNC mt_twist
        xor ecx, ecx
1:      mov eax, [rdi + MT_WORDS + rcx*4]
        and eax, 0x80000000
        lea edx, [ecx + 1]
        cmp edx, MT_N
        jb 2f
        xor edx, edx
2:      mov r8d, [rdi + MT_WORDS + rdx*4]
        and r8d, 0x7fffffff
        or eax, r8d                     # y
        lea edx, [ecx + MT_M]
        cmp edx, MT_N
        jb 3f
        sub edx, MT_N
3:      mov r8d, [rdi + MT_WORDS + rdx*4]
        mov r9d, eax
        shr r9d, 1
        xor r8d, r9d
        test eax, 1
        jz 4f
        xor r8d, 0x9908b0df
4:      mov [rdi + MT_WORDS + rcx*4], r8d
        inc ecx
        cmp ecx, MT_N
        jb 1b
        mov qword ptr [rdi + MT_INDEX], 0
        ret
ENDF mt_twist

# mt_next(state) -> eax: genrand_uint32
FUNC mt_next
        cmp qword ptr [rdi + MT_INDEX], MT_N
        jb 1f
        push rdi
        call mt_twist
        pop rdi
1:      mov rcx, [rdi + MT_INDEX]
        mov eax, [rdi + MT_WORDS + rcx*4]
        inc qword ptr [rdi + MT_INDEX]
        mov edx, eax                    # the tempering
        shr edx, 11
        xor eax, edx
        mov edx, eax
        shl edx, 7
        and edx, 0x9d2c5680
        xor eax, edx
        mov edx, eax
        shl edx, 15
        and edx, 0xefc60000
        xor eax, edx
        mov edx, eax
        shr edx, 18
        xor eax, edx
        ret
ENDF mt_next

# mt_randrange(state, n) -> rax: python's _randbelow(n) for 0 < n <= 2^32:
# getrandbits(k) - the top k bits of a word - until it's below n
FUNC mt_randrange
        ENTER
        mov rbx, rdi
        mov r12, rsi
        lea rax, [r12 - 1]              # k = n.bit_length()
        bsr r13, r12
        inc r13d
        mov ecx, 32
        sub ecx, r13d
        mov r14d, ecx
1:      mov rdi, rbx
        call mt_next
        mov ecx, r14d
        shr eax, cl
        cmp rax, r12
        jae 1b
        LEAVE
ENDF mt_randrange

        .section .note.GNU-stack,"",@progbits
