# Keccak-256, the EVM's sha3 (python's eth_hash.auto.keccak): the
# original Keccak's padding (0x01 ... 0x80), not FIPS 202's SHA3-256 and
# its 0x06. Rate 136 bytes, capacity 512 bits.
#
#   keccak256(buf, len, out)        the 32 bytes of the digest at out
#   keccak_value(buf, len) -> value int.from_bytes(keccak(b), "big")

.include "defs.inc"

.set KECCAK_RATE, 136

        .section .rodata
        .p2align 6
keccak_rc:
        .quad 0x0000000000000001, 0x0000000000008082, 0x800000000000808a, 0x8000000080008000
        .quad 0x000000000000808b, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009
        .quad 0x000000000000008a, 0x0000000000000088, 0x0000000080008009, 0x000000008000000a
        .quad 0x000000008000808b, 0x800000000000008b, 0x8000000000008089, 0x8000000000008003
        .quad 0x8000000000008002, 0x8000000000000080, 0x000000000000800a, 0x800000008000000a
        .quad 0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008
        .text

# KC_COLUMN reg, x: the parity of the column x (theta's C[x])
.macro KC_COLUMN reg, x
        mov \reg, [rdi + 8*\x]
        xor \reg, [rdi + 8*(\x+5)]
        xor \reg, [rdi + 8*(\x+10)]
        xor \reg, [rdi + 8*(\x+15)]
        xor \reg, [rdi + 8*(\x+20)]
.endm

# KC_THETA x, cm1, cp1: D[x] = C[x-1] ^ rol(C[x+1], 1), into the column x
.macro KC_THETA x, cm1, cp1
        mov rax, \cp1
        rol rax, 1
        xor rax, \cm1
        xor [rdi + 8*\x], rax
        xor [rdi + 8*(\x+5)], rax
        xor [rdi + 8*(\x+10)], rax
        xor [rdi + 8*(\x+15)], rax
        xor [rdi + 8*(\x+20)], rax
.endm

# KC_RHOPI j, r: one step of rho and pi done together along their cycle
# (rax: the lane carried from the step before)
.macro KC_RHOPI j, r
        mov rdx, [rdi + 8*\j]
        rol rax, \r
        mov [rdi + 8*\j], rax
        mov rax, rdx
.endm

# KC_CHI1 y, x, b0, b1, b2: A[x, y] = b0 ^ (~b1 & b2)
.macro KC_CHI1 y, x, b0, b1, b2
        mov rax, \b1
        not rax
        and rax, \b2
        xor rax, \b0
        mov [rdi + 8*(5*\y+\x)], rax
.endm

# KC_CHI y: chi on the row y (its five lanes read first)
.macro KC_CHI y
        mov r8, [rdi + 8*(5*\y)]
        mov r9, [rdi + 8*(5*\y+1)]
        mov r10, [rdi + 8*(5*\y+2)]
        mov r11, [rdi + 8*(5*\y+3)]
        mov rdx, [rdi + 8*(5*\y+4)]
        KC_CHI1 \y, 0, r8, r9, r10
        KC_CHI1 \y, 1, r9, r10, r11
        KC_CHI1 \y, 2, r10, r11, rdx
        KC_CHI1 \y, 3, r11, rdx, r8
        KC_CHI1 \y, 4, rdx, r8, r9
.endm

# keccak_f(state): Keccak-f[1600] on the 25 lanes at state (a leaf: only
# scratch registers)
FUNC keccak_f
        lea rcx, [rip + keccak_rc]
        xor esi, esi
1:      KC_COLUMN r8, 0
        KC_COLUMN r9, 1
        KC_COLUMN r10, 2
        KC_COLUMN r11, 3
        KC_COLUMN rdx, 4
        KC_THETA 0, rdx, r9
        KC_THETA 1, r8, r10
        KC_THETA 2, r9, r11
        KC_THETA 3, r10, rdx
        KC_THETA 4, r11, r8
        mov rax, [rdi + 8]
        KC_RHOPI 10, 1
        KC_RHOPI 7, 3
        KC_RHOPI 11, 6
        KC_RHOPI 17, 10
        KC_RHOPI 18, 15
        KC_RHOPI 3, 21
        KC_RHOPI 5, 28
        KC_RHOPI 16, 36
        KC_RHOPI 8, 45
        KC_RHOPI 21, 55
        KC_RHOPI 24, 2
        KC_RHOPI 4, 14
        KC_RHOPI 15, 27
        KC_RHOPI 23, 41
        KC_RHOPI 19, 56
        KC_RHOPI 13, 8
        KC_RHOPI 12, 25
        KC_RHOPI 2, 43
        KC_RHOPI 20, 62
        KC_RHOPI 14, 18
        KC_RHOPI 22, 39
        KC_RHOPI 9, 61
        KC_RHOPI 6, 20
        KC_RHOPI 1, 44
        KC_CHI 0
        KC_CHI 1
        KC_CHI 2
        KC_CHI 3
        KC_CHI 4
        mov rax, [rcx + rsi*8]          # iota
        xor [rdi], rax
        inc esi
        cmp esi, 24
        jb 1b
        ret
ENDF keccak_f

# keccak_absorb(state, block): a block of KECCAK_RATE bytes into the state
FUNC keccak_absorb
        xor ecx, ecx
1:      mov rax, [rsi + rcx*8]
        xor [rdi + rcx*8], rax
        inc ecx
        cmp ecx, KECCAK_RATE / 8
        jb 1b
        jmp keccak_f
ENDF keccak_absorb

# keccak256(buf, len, out): the 32 bytes of the digest at out
FUNC keccak256
        ENTER
        sub rsp, 352
        .set KS_STATE, 0                # 25 lanes
        .set KS_LAST, 208               # the last block (KECCAK_RATE bytes)
        mov rbx, rdi                    # the next block
        mov r12, rsi                    # the bytes left
        mov r13, rdx
        lea rdi, [rsp + KS_STATE]
        xor esi, esi
        mov edx, 200
        call memset@PLT
1:      cmp r12, KECCAK_RATE
        jb 2f
        lea rdi, [rsp + KS_STATE]
        mov rsi, rbx
        call keccak_absorb
        add rbx, KECCAK_RATE
        sub r12, KECCAK_RATE
        jmp 1b
2:      # the rest, then 0x01, zeros and 0x80 (one byte 0x81 when the rest
        # is a byte short of a block)
        lea rdi, [rsp + KS_LAST]
        xor esi, esi
        mov edx, KECCAK_RATE
        call memset@PLT
        lea rdi, [rsp + KS_LAST]
        mov rsi, rbx
        mov rdx, r12
        call memcpy@PLT
        xor byte ptr [rsp + KS_LAST + r12], 0x01
        xor byte ptr [rsp + KS_LAST + KECCAK_RATE - 1], 0x80
        lea rdi, [rsp + KS_STATE]
        lea rsi, [rsp + KS_LAST]
        call keccak_absorb
        movdqu xmm0, [rsp + KS_STATE]   # the digest: the state's first
        movdqu xmm1, [rsp + KS_STATE + 16]  # 32 bytes (little-endian lanes)
        movdqu [r13], xmm0
        movdqu [r13 + 16], xmm1
        add rsp, 352
        LEAVE
ENDF keccak256

# keccak_value(buf, len) -> value: the digest as a big-endian integer
# (runtrace's keccak: int.from_bytes(k(b), "big"))
FUNC keccak_value
        ENTER
        sub rsp, 32
        mov rdx, rsp
        call keccak256
        mov rdi, rsp
        mov esi, 32
        call mk_int_bytes_be
        add rsp, 32
        LEAVE
ENDF keccak_value

        .section .note.GNU-stack,"",@progbits
