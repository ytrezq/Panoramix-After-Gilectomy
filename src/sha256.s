# SHA-256 (FIPS 180-4), for the version of the signature dump the
# database was built from - python's dump_version(): the first 4 bytes of
# the sha256 of abi_dump.xz, big-endian, mod 2^31 - 1, plus 1.

.include "defs.inc"

        .section .rodata
        .p2align 6
sha256_k:
        .long 0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5
        .long 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174
        .long 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da
        .long 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967
        .long 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85
        .long 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070
        .long 0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3
        .long 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
sha256_h0:
        .long 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
        .text

# SHA_ROUND a..h, i: round i of a group of 8 (rsi: the constants of the
# group, rdi: their words); h becomes the new a, d the new e (the next
# round names them so)
.macro SHA_ROUND a, b, c, d, e, f, g, h, i
        mov eax, \e
        ror eax, 6
        mov ebx, \e
        ror ebx, 11
        xor eax, ebx
        ror ebx, 14
        xor eax, ebx                    # S1(e)
        mov ebx, \f
        xor ebx, \g
        and ebx, \e
        xor ebx, \g                     # Ch(e, f, g)
        add eax, ebx
        add eax, [rsi + \i*4]
        add eax, [rdi + \i*4]
        add \h, eax                     # T1
        add \d, \h
        mov eax, \a
        ror eax, 2
        mov ebx, \a
        ror ebx, 13
        xor eax, ebx
        ror ebx, 9
        xor eax, ebx                    # S0(a)
        mov ebx, \a
        or ebx, \b
        and ebx, \c
        mov ecx, \a
        and ecx, \b
        or ebx, ecx                     # Maj(a, b, c)
        add eax, ebx
        add \h, eax                     # T1 + T2
.endm

# sha256_block(state, block): the 8 words of state updated with a block
# of 64 bytes
FUNC sha256_block
        push rbp
        mov rbp, rsp
        push rbx
        push r12
        push r13
        push r14
        push r15
        sub rsp, 264                    # the 64 words (and rsp 16-aligned)
        push rdi
        # the schedule
        xor ecx, ecx
1:      mov eax, [rsi + rcx*4]
        bswap eax
        mov [rsp + 8 + rcx*4], eax
        inc ecx
        cmp ecx, 16
        jb 1b
2:      mov eax, [rsp + 8 + rcx*4 - 8]  # W[t-2]
        mov ebx, eax
        ror eax, 17
        mov edx, ebx
        ror edx, 19
        xor eax, edx
        shr ebx, 10
        xor eax, ebx                    # s1
        add eax, [rsp + 8 + rcx*4 - 28] # W[t-7]
        mov ebx, [rsp + 8 + rcx*4 - 60] # W[t-15]
        mov edx, ebx
        ror edx, 7
        mov r8d, ebx
        ror r8d, 18
        xor edx, r8d
        shr ebx, 3
        xor edx, ebx                    # s0
        add eax, edx
        add eax, [rsp + 8 + rcx*4 - 64] # W[t-16]
        mov [rsp + 8 + rcx*4], eax
        inc ecx
        cmp ecx, 64
        jb 2b
        # the rounds, 8 at a time
        mov r8d, [rdi]
        mov r9d, [rdi + 4]
        mov r10d, [rdi + 8]
        mov r11d, [rdi + 12]
        mov r12d, [rdi + 16]
        mov r13d, [rdi + 20]
        mov r14d, [rdi + 24]
        mov r15d, [rdi + 28]
        lea rsi, [rip + sha256_k]
        lea rdi, [rsp + 8]
        lea rdx, [rsi + 256]
3:      SHA_ROUND r8d, r9d, r10d, r11d, r12d, r13d, r14d, r15d, 0
        SHA_ROUND r15d, r8d, r9d, r10d, r11d, r12d, r13d, r14d, 1
        SHA_ROUND r14d, r15d, r8d, r9d, r10d, r11d, r12d, r13d, 2
        SHA_ROUND r13d, r14d, r15d, r8d, r9d, r10d, r11d, r12d, 3
        SHA_ROUND r12d, r13d, r14d, r15d, r8d, r9d, r10d, r11d, 4
        SHA_ROUND r11d, r12d, r13d, r14d, r15d, r8d, r9d, r10d, 5
        SHA_ROUND r10d, r11d, r12d, r13d, r14d, r15d, r8d, r9d, 6
        SHA_ROUND r9d, r10d, r11d, r12d, r13d, r14d, r15d, r8d, 7
        add rsi, 32
        add rdi, 32
        cmp rsi, rdx
        jb 3b
        pop rdi
        add [rdi], r8d
        add [rdi + 4], r9d
        add [rdi + 8], r10d
        add [rdi + 12], r11d
        add [rdi + 16], r12d
        add [rdi + 20], r13d
        add [rdi + 24], r14d
        add [rdi + 28], r15d
        add rsp, 264
        pop r15
        pop r14
        pop r13
        pop r12
        pop rbx
        pop rbp
        ret
ENDF sha256_block

# sha256(buf, len, out): the 32 bytes of the digest at out
FUNC sha256
        ENTER
        sub rsp, 176
        .set SHA_STATE, 0               # 8 words
        .set SHA_TAIL, 32               # the last block or two (128 bytes)
        .set SHA_OUT, 160
        .set SHA_LEN, 168
        mov rbx, rdi                    # the next block
        mov r12, rsi                    # the bytes left
        mov [rsp + SHA_OUT], rdx
        mov [rsp + SHA_LEN], rsi
        movdqu xmm0, [rip + sha256_h0]
        movdqu xmm1, [rip + sha256_h0 + 16]
        movdqu [rsp + SHA_STATE], xmm0
        movdqu [rsp + SHA_STATE + 16], xmm1
1:      cmp r12, 64
        jb 2f
        lea rdi, [rsp + SHA_STATE]
        mov rsi, rbx
        call sha256_block
        add rbx, 64
        sub r12, 64
        jmp 1b
2:      # the rest, 0x80, zeros and the length in bits (big-endian)
        lea rdi, [rsp + SHA_TAIL]
        xor esi, esi
        mov edx, 128
        call memset@PLT
        lea rdi, [rsp + SHA_TAIL]
        mov rsi, rbx
        mov rdx, r12
        call memcpy@PLT
        mov byte ptr [rsp + SHA_TAIL + r12], 0x80
        mov r13d, 64                    # the tail's size
        cmp r12, 56
        jb 3f
        mov r13d, 128
3:      mov rax, [rsp + SHA_LEN]
        shl rax, 3
        bswap rax
        mov [rsp + SHA_TAIL + r13 - 8], rax
        lea rdi, [rsp + SHA_STATE]
        lea rsi, [rsp + SHA_TAIL]
        call sha256_block
        cmp r13, 128
        jne 4f
        lea rdi, [rsp + SHA_STATE]
        lea rsi, [rsp + SHA_TAIL + 64]
        call sha256_block
4:      mov rdx, [rsp + SHA_OUT]
        xor ecx, ecx
5:      mov eax, [rsp + SHA_STATE + rcx*4]
        bswap eax
        mov [rdx + rcx*4], eax
        inc ecx
        cmp ecx, 8
        jb 5b
        add rsp, 176
        LEAVE
ENDF sha256

# dump_version_buf(data, len) -> rax: python's dump_version() of a file's
# contents (1 to 2^31 - 1)
FUNC dump_version_buf
        ENTER
        sub rsp, 32
        mov rdx, rsp
        call sha256
        mov eax, [rsp]
        bswap eax                       # the first 4 bytes, big-endian
        xor edx, edx
        mov ecx, 0x7fffffff
        div ecx
        lea eax, [rdx + 1]
        add rsp, 32
        LEAVE
ENDF dump_version_buf

# dump_version(path) -> rax: the same of a file, or 0 if it can't be read
FUNC dump_version
        ENTER
        sub rsp, 16
        mov rsi, rsp
        call read_file                  # (malloc'ed)
        test rax, rax
        jz 9f
        mov rbx, rax
        mov rdi, rax
        mov rsi, [rsp]
        call dump_version_buf
        mov r12, rax
        mov rdi, rbx
        call free@PLT
        mov rax, r12
        add rsp, 16
        LEAVE
9:      xor eax, eax
        add rsp, 16
        LEAVE
ENDF dump_version

        .section .note.GNU-stack,"",@progbits
