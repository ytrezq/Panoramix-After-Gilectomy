# Arithmetic (port of panoramix/core/arithmetic.py): concrete 256-bit EVM
# operations on integer values, `eval`, `is_zero`, `simplify_bool`,
# `eval_bool`.
#
# Tri-state / four-state results (eax): TRI_TRUE 1, TRI_FALSE 0,
# TRI_NONE -1, TRI_CANNOT -2 (python's CannotCompare exception).

.include "defs.inc"

        .section .bss
        .align 16
        .globl mpz_two256, mpz_two255, mpz_max256, mpz_max255
        .hidden mpz_two256, mpz_two255, mpz_max256, mpz_max255
mpz_two256: .space 16
mpz_two255: .space 16
mpz_max256: .space 16
mpz_max255: .space 16

        .text

# arith_init(): the constants (allocated on the bound context)
FUNC arith_init
        ENTER
        lea rdi, [rip + mpz_two256]
        call __gmpz_init@PLT
        lea rdi, [rip + mpz_two256]
        mov esi, 2
        mov edx, 256
        call __gmpz_ui_pow_ui@PLT
        lea rdi, [rip + mpz_two255]
        call __gmpz_init@PLT
        lea rdi, [rip + mpz_two255]
        mov esi, 2
        mov edx, 255
        call __gmpz_ui_pow_ui@PLT
        lea rdi, [rip + mpz_max256]
        call __gmpz_init@PLT
        lea rdi, [rip + mpz_max256]
        lea rsi, [rip + mpz_two256]
        mov edx, 1
        call __gmpz_sub_ui@PLT
        lea rdi, [rip + mpz_max255]
        call __gmpz_init@PLT
        lea rdi, [rip + mpz_max255]
        lea rsi, [rip + mpz_two255]
        mov edx, 1
        call __gmpz_sub_ui@PLT
        LEAVE
ENDF arith_init

# ---------------------------------------------------------------------
# helpers on integer values

# arith_load(a, b): MPZ_A := a, MPZ_B := b
FUNC arith_load
        ENTER
        mov rbx, rsi
        mov rsi, rdi
        lea rdi, [r15 + CTX_MPZ_A]
        call value_set_mpz
        lea rdi, [r15 + CTX_MPZ_B]
        mov rsi, rbx
        call value_set_mpz
        LEAVE
ENDF arith_load

# arith_result() -> rax: the value of MPZ_R
FUNC arith_result
        lea rdi, [r15 + CTX_MPZ_R]
        jmp mk_int_mpz
ENDF arith_result

# arith_wrap_r(): MPZ_R := MPZ_R mod 2^256 (python's `& UINT_256_MAX`)
FUNC arith_wrap_r
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, rdi
        mov edx, 256
        jmp __gmpz_fdiv_r_2exp@PLT
ENDF arith_wrap_r

# int_cmp(a, b) -> eax: -1, 0, 1
FUNC int_cmp
        test dil, 1
        jz 1f
        test sil, 1
        jz 1f
        xor eax, eax
        cmp rdi, rsi
        setg al
        mov ecx, -1
        cmovl eax, ecx
        ret
1:      ENTER
        call arith_load
        lea rdi, [r15 + CTX_MPZ_A]
        lea rsi, [r15 + CTX_MPZ_B]
        call __gmpz_cmp@PLT
        mov ecx, eax
        xor eax, eax
        test ecx, ecx
        setg al
        mov ecx, -1
        cmovs eax, ecx
        LEAVE
ENDF int_cmp

# int_sign(v) -> eax: -1, 0, 1
FUNC int_sign
        test dil, 1
        jz 1f
        sar rdi, 1
        xor eax, eax
        test rdi, rdi
        setg al
        mov ecx, -1
        cmovs eax, ecx
        ret
1:      mov ecx, [rdi + N_DATA + MPZ_SIZE]
        xor eax, eax
        test ecx, ecx
        setg al
        mov ecx, -1
        cmovs eax, ecx
        ret
ENDF int_sign

# int_tstbit(v, bit) -> eax: two's complement bit test (python semantics)
FUNC int_tstbit
        ENTER
        mov rbx, rsi
        call value_mpz
        mov rdi, rax
        mov rsi, rbx
        call __gmpz_tstbit@PLT
        LEAVE
ENDF int_tstbit

# int_to_i64(v) -> rax: small ints as is; big ones clamped to +-2^63
FUNC int_to_i64
        test dil, 1
        jz 1f
        mov rax, rdi
        sar rax, 1
        ret
1:      cmp dword ptr [rdi + N_DATA + MPZ_SIZE], 0
        jl 2f
        mov rax, 0x7fffffffffffffff
        ret
2:      mov rax, 0x8000000000000000
        ret
ENDF int_to_i64

# unsigned_to_signed_mpz(mpz): in place, value -= 2^256 if > 2^255-1
FUNC unsigned_to_signed_mpz
        ENTER
        mov rbx, rdi
        lea rsi, [rip + mpz_max255]
        call __gmpz_cmp@PLT
        test eax, eax
        jle 1f
        mov rdi, rbx
        mov rsi, rbx
        lea rdx, [rip + mpz_two256]
        call __gmpz_sub@PLT
1:      LEAVE
ENDF unsigned_to_signed_mpz

# unsigned_to_signed(v) -> value
FUNC unsigned_to_signed
        ENTER
        mov rsi, rdi
        lea rdi, [r15 + CTX_MPZ_R]
        call value_set_mpz
        lea rdi, [r15 + CTX_MPZ_R]
        call unsigned_to_signed_mpz
        call arith_result
        LEAVE
ENDF unsigned_to_signed

# to_real_int(v) -> value: -((-v) mod 2^256) when bit 255 is set (ints only);
# that's python's `-sub(0, exp)`, and it leaves negative numbers alone
FUNC to_real_int
        ENTER
        mov rbx, rdi
        call is_int
        test eax, eax
        jz 1f
        mov rdi, rbx
        mov esi, 255
        call int_tstbit
        test eax, eax
        jz 1f
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, rbx
        call value_set_mpz
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, rdi
        call __gmpz_neg@PLT
        call arith_wrap_r
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, rdi
        call __gmpz_neg@PLT
        call arith_result
        LEAVE
1:      mov rax, rbx
        LEAVE
ENDF to_real_int

# py_equal(a, b) -> eax: values_equal, plus python's False == 0, True == 1
FUNC py_equal
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call values_equal
        test eax, eax
        jnz 1f
        mov rdi, rbx
        mov rsi, r12
        call py_bool_int_equal
        test eax, eax
        jnz 1f
        mov rdi, r12
        mov rsi, rbx
        call py_bool_int_equal
1:      LEAVE
ENDF py_equal

# py_bool_int_equal(a, b) -> eax: a is False and b == 0, or a is True and b == 1
FUNC py_bool_int_equal
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov esi, SP_FALSE
        call is_special
        test eax, eax
        jz 1f
        xor eax, eax
        cmp r12, 1
        sete al
        LEAVE
1:      mov rdi, rbx
        mov esi, SP_TRUE
        call is_special
        test eax, eax
        jz 2f
        xor eax, eax
        cmp r12, 3
        sete al
        LEAVE
2:      xor eax, eax
        LEAVE
ENDF py_bool_int_equal

# ---------------------------------------------------------------------
# the concrete operations: ev_xxx(a, b) -> value. All go through GMP
# (fast paths for small operands can come later).

FUNC ev_add
        ENTER
        call arith_load
        lea rdi, [r15 + CTX_MPZ_R]
        lea rsi, [r15 + CTX_MPZ_A]
        lea rdx, [r15 + CTX_MPZ_B]
        call __gmpz_add@PLT
        call arith_wrap_r
        call arith_result
        LEAVE
ENDF ev_add

FUNC ev_sub
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call values_equal
        test eax, eax
        jz 1f
        mov eax, 1
        LEAVE
1:      mov rdi, rbx
        mov rsi, r12
        call arith_load
        lea rdi, [r15 + CTX_MPZ_R]
        lea rsi, [r15 + CTX_MPZ_A]
        lea rdx, [r15 + CTX_MPZ_B]
        call __gmpz_sub@PLT
        call arith_wrap_r
        call arith_result
        LEAVE
ENDF ev_sub

FUNC ev_mul
        cmp rdi, 1
        je .Lzero
        cmp rsi, 1
        je .Lzero
        ENTER
        call arith_load
        lea rdi, [r15 + CTX_MPZ_R]
        lea rsi, [r15 + CTX_MPZ_A]
        lea rdx, [r15 + CTX_MPZ_B]
        call __gmpz_mul@PLT
        call arith_wrap_r
        call arith_result
        LEAVE
.Lzero: mov eax, 1
        ret
ENDF ev_mul

FUNC ev_div
        cmp rdi, 1
        je .Lzero
        cmp rsi, 1
        je .Lzero
        ENTER
        call arith_load
        lea rdi, [r15 + CTX_MPZ_R]
        lea rsi, [r15 + CTX_MPZ_A]
        lea rdx, [r15 + CTX_MPZ_B]
        call __gmpz_fdiv_q@PLT
        call arith_wrap_r
        call arith_result
        LEAVE
ENDF ev_div

# sdiv: sign * (|a'| // |b'|), not wrapped (as in python)
FUNC ev_sdiv
        ENTER
        call arith_load
        lea rdi, [r15 + CTX_MPZ_A]
        call unsigned_to_signed_mpz
        lea rdi, [r15 + CTX_MPZ_B]
        call unsigned_to_signed_mpz
        cmp dword ptr [r15 + CTX_MPZ_B + MPZ_SIZE], 0
        je .Lzero_leave
        mov ebx, [r15 + CTX_MPZ_A + MPZ_SIZE]
        xor ebx, [r15 + CTX_MPZ_B + MPZ_SIZE]     # sign bit set iff signs differ
        lea rdi, [r15 + CTX_MPZ_A]
        mov rsi, rdi
        call __gmpz_abs@PLT
        lea rdi, [r15 + CTX_MPZ_B]
        mov rsi, rdi
        call __gmpz_abs@PLT
        lea rdi, [r15 + CTX_MPZ_R]
        lea rsi, [r15 + CTX_MPZ_A]
        lea rdx, [r15 + CTX_MPZ_B]
        call __gmpz_fdiv_q@PLT
        test ebx, ebx
        jns 1f
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, rdi
        call __gmpz_neg@PLT
1:      call arith_result
        LEAVE
.Lzero_leave:
        mov eax, 1
        LEAVE
ENDF ev_sdiv

FUNC ev_mod
        cmp rsi, 1
        je .Lzero
        ENTER
        call arith_load
        lea rdi, [r15 + CTX_MPZ_R]
        lea rsi, [r15 + CTX_MPZ_A]
        lea rdx, [r15 + CTX_MPZ_B]
        call __gmpz_fdiv_r@PLT
        call arith_result
        LEAVE
ENDF ev_mod

FUNC ev_smod
        ENTER
        call arith_load
        lea rdi, [r15 + CTX_MPZ_A]
        call unsigned_to_signed_mpz
        lea rdi, [r15 + CTX_MPZ_B]
        call unsigned_to_signed_mpz
        cmp dword ptr [r15 + CTX_MPZ_B + MPZ_SIZE], 0
        je .Lzero_leave2
        mov ebx, [r15 + CTX_MPZ_A + MPZ_SIZE]      # sign of the value
        lea rdi, [r15 + CTX_MPZ_A]
        mov rsi, rdi
        call __gmpz_abs@PLT
        lea rdi, [r15 + CTX_MPZ_B]
        mov rsi, rdi
        call __gmpz_abs@PLT
        lea rdi, [r15 + CTX_MPZ_R]
        lea rsi, [r15 + CTX_MPZ_A]
        lea rdx, [r15 + CTX_MPZ_B]
        call __gmpz_fdiv_r@PLT
        test ebx, ebx
        jns 1f
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, rdi
        call __gmpz_neg@PLT
1:      call arith_wrap_r
        call arith_result
        LEAVE
.Lzero_leave2:
        mov eax, 1
        LEAVE
ENDF ev_smod

# ev_addmod(a, b, m) / ev_mulmod(a, b, m)
FUNC ev_addmod
        cmp rdx, 1
        je .Lzero
        ENTER
        mov rbx, rdx
        call arith_load
        lea rdi, [r15 + CTX_MPZ_R]
        lea rsi, [r15 + CTX_MPZ_A]
        lea rdx, [r15 + CTX_MPZ_B]
        call __gmpz_add@PLT
        lea rdi, [r15 + CTX_MPZ_A]
        mov rsi, rbx
        call value_set_mpz
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, rdi
        lea rdx, [r15 + CTX_MPZ_A]
        call __gmpz_fdiv_r@PLT
        call arith_result
        LEAVE
ENDF ev_addmod

FUNC ev_mulmod
        cmp rdx, 1
        je .Lzero
        ENTER
        mov rbx, rdx
        call arith_load
        lea rdi, [r15 + CTX_MPZ_R]
        lea rsi, [r15 + CTX_MPZ_A]
        lea rdx, [r15 + CTX_MPZ_B]
        call __gmpz_mul@PLT
        lea rdi, [r15 + CTX_MPZ_A]
        mov rsi, rbx
        call value_set_mpz
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, rdi
        lea rdx, [r15 + CTX_MPZ_A]
        call __gmpz_fdiv_r@PLT
        call arith_result
        LEAVE
ENDF ev_mulmod

# ev_exp(base, exponent): pow(base, exponent, 2^256)
FUNC ev_exp
        cmp rsi, 1
        jne 1f
        mov eax, 3                      # exponent 0 -> 1
        ret
1:      cmp rdi, 1
        je .Lzero
        ENTER
        call arith_load
        cmp dword ptr [r15 + CTX_MPZ_B + MPZ_SIZE], 0
        jl .Lzero_leave3
        lea rdi, [r15 + CTX_MPZ_R]
        lea rsi, [r15 + CTX_MPZ_A]
        lea rdx, [r15 + CTX_MPZ_B]
        lea rcx, [rip + mpz_two256]
        call __gmpz_powm@PLT
        call arith_result
        LEAVE
.Lzero_leave3:
        mov eax, 1
        LEAVE
ENDF ev_exp

# ev_signextend(bits, value)
FUNC ev_signextend
        ENTER
        mov rbx, rdi
        mov r12, rsi
        test bl, 1
        jz .Lse_asis                    # huge `bits`: value unchanged
        mov rax, rbx
        sar rax, 1
        cmp rax, 31
        ja .Lse_asis
        lea r13, [rax*8 + 7]            # testbit
        mov rdi, r12
        mov rsi, r13
        call int_tstbit
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, r12
        push rax
        push rax
        call value_set_mpz
        pop rax
        pop rax
        test eax, eax
        jz 1f
        # value | (2^256 - 2^testbit): set the bits testbit..255
2:      cmp r13, 256
        jae 3f
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, r13
        call __gmpz_setbit@PLT
        inc r13
        jmp 2b
1:      # value & (2^testbit - 1)
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, rdi
        mov rdx, r13
        call __gmpz_fdiv_r_2exp@PLT
3:      call arith_result
        LEAVE
.Lse_asis:
        mov rax, r12
        LEAVE
ENDF ev_signextend

# shift amount check: shift_ok(v) -> rax = shift (0..255) or -1
FUNC shift_amount
        test dil, 1
        jz 1f
        mov rax, rdi
        sar rax, 1
        cmp rax, 255
        ja 1f
        ret
1:      mov rax, -1
        ret
ENDF shift_amount

FUNC ev_shl
        ENTER
        mov rbx, rsi
        call shift_amount
        cmp rax, -1
        je .Lzero_leave4
        mov r12, rax
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, rbx
        call value_set_mpz
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, rdi
        mov rdx, r12
        call __gmpz_mul_2exp@PLT
        call arith_wrap_r
        call arith_result
        LEAVE
.Lzero_leave4:
        mov eax, 1
        LEAVE
ENDF ev_shl

FUNC ev_shr
        ENTER
        mov rbx, rsi
        call shift_amount
        cmp rax, -1
        je .Lzero_leave4
        mov r12, rax
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, rbx
        call value_set_mpz
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, rdi
        mov rdx, r12
        call __gmpz_fdiv_q_2exp@PLT
        call arith_wrap_r
        call arith_result
        LEAVE
ENDF ev_shr

FUNC ev_sar
        ENTER
        mov rbx, rsi
        mov r13, rdi
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, rbx
        call value_set_mpz
        lea rdi, [r15 + CTX_MPZ_R]
        call unsigned_to_signed_mpz
        mov rdi, r13
        call shift_amount
        cmp rax, -1
        jne 1f
        # shift >= 256: 0 if value >= 0 else -1 (2^256 - 1)
        cmp dword ptr [r15 + CTX_MPZ_R + MPZ_SIZE], 0
        jl 2f
        mov eax, 1
        LEAVE
2:      lea rdi, [rip + mpz_max256]
        call mk_int_mpz
        LEAVE
1:      lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, rdi
        mov rdx, rax
        call __gmpz_fdiv_q_2exp@PLT
        call arith_wrap_r
        call arith_result
        LEAVE
ENDF ev_sar

FUNC ev_and
        ENTER
        call arith_load
        lea rdi, [r15 + CTX_MPZ_R]
        lea rsi, [r15 + CTX_MPZ_A]
        lea rdx, [r15 + CTX_MPZ_B]
        call __gmpz_and@PLT
        call arith_result
        LEAVE
ENDF ev_and

FUNC ev_or
        ENTER
        call arith_load
        lea rdi, [r15 + CTX_MPZ_R]
        lea rsi, [r15 + CTX_MPZ_A]
        lea rdx, [r15 + CTX_MPZ_B]
        call __gmpz_ior@PLT
        call arith_result
        LEAVE
ENDF ev_or

FUNC ev_xor
        ENTER
        call arith_load
        lea rdi, [r15 + CTX_MPZ_R]
        lea rsi, [r15 + CTX_MPZ_A]
        lea rdx, [r15 + CTX_MPZ_B]
        call __gmpz_xor@PLT
        call arith_result
        LEAVE
ENDF ev_xor

# ev_not(a): 2^256 - 1 - a
FUNC ev_not
        ENTER
        mov rsi, rdi
        lea rdi, [r15 + CTX_MPZ_A]
        call value_set_mpz
        lea rdi, [r15 + CTX_MPZ_R]
        lea rsi, [rip + mpz_max256]
        lea rdx, [r15 + CTX_MPZ_A]
        call __gmpz_sub@PLT
        call arith_result
        LEAVE
ENDF ev_not

# ev_byte(position, value): (value // 256^(31-pos)) % 256 (negative
# positions shift further right, like in python)
FUNC ev_byte
        ENTER
        mov rbx, rsi
        test dil, 1
        jz .Lzero_leave5                # a huge position
        mov rax, rdi
        sar rax, 1
        cmp rax, 31
        jg .Lzero_leave5
        mov r12d, 31
        sub r12, rax                    # 31 - pos (>= 0)
        shl r12, 3                      # bits to shift right
        cmp r12, 512
        jbe 1f
        mov r12d, 512                   # enough for any 256-bit value
1:      lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, rbx
        call value_set_mpz
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, rdi
        mov rdx, r12
        call __gmpz_fdiv_q_2exp@PLT
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, rdi
        mov edx, 8
        call __gmpz_fdiv_r_2exp@PLT
        call arith_result
        LEAVE
.Lzero_leave5:
        mov eax, 1
        LEAVE
ENDF ev_byte

# comparisons -> tagged 0 or 1
FUNC ev_lt
        ENTER
        call int_cmp
        mov ecx, 1
        cmp eax, -1
        mov eax, 3
        cmove eax, ecx
        xor eax, 2                      # 3 -> 1 (0), 1 -> 3 (1)
        LEAVE
ENDF ev_lt

FUNC ev_gt
        ENTER
        call int_cmp
        mov ecx, 3
        mov edx, 1
        cmp eax, 1
        cmove eax, ecx
        cmovne eax, edx
        LEAVE
ENDF ev_gt

FUNC ev_le
        ENTER
        call int_cmp
        mov ecx, 3
        mov edx, 1
        cmp eax, 1
        cmove eax, edx
        cmovne eax, ecx
        LEAVE
ENDF ev_le

FUNC ev_ge
        ENTER
        call int_cmp
        mov ecx, 3
        mov edx, 1
        cmp eax, -1
        cmove eax, edx
        cmovne eax, ecx
        LEAVE
ENDF ev_ge

FUNC ev_eq
        ENTER
        call int_cmp
        mov ecx, 3
        mov edx, 1
        test eax, eax
        cmove eax, ecx
        cmovne eax, edx
        LEAVE
ENDF ev_eq

# signed comparisons: through unsigned_to_signed on both sides
FUNC ev_scmp
        # -> eax: -1/0/1 comparing the signed views
        ENTER
        call arith_load
        lea rdi, [r15 + CTX_MPZ_A]
        call unsigned_to_signed_mpz
        lea rdi, [r15 + CTX_MPZ_B]
        call unsigned_to_signed_mpz
        lea rdi, [r15 + CTX_MPZ_A]
        lea rsi, [r15 + CTX_MPZ_B]
        call __gmpz_cmp@PLT
        mov ecx, eax
        xor eax, eax
        test ecx, ecx
        setg al
        mov ecx, -1
        cmovs eax, ecx
        LEAVE
ENDF ev_scmp

FUNC ev_slt
        ENTER
        call ev_scmp
        mov ecx, 3
        mov edx, 1
        cmp eax, -1
        cmove eax, ecx
        cmovne eax, edx
        LEAVE
ENDF ev_slt

FUNC ev_sgt
        ENTER
        call ev_scmp
        mov ecx, 3
        mov edx, 1
        cmp eax, 1
        cmove eax, ecx
        cmovne eax, edx
        LEAVE
ENDF ev_sgt

FUNC ev_sle
        ENTER
        call ev_scmp
        mov ecx, 3
        mov edx, 1
        cmp eax, 1
        cmove eax, edx
        cmovne eax, ecx
        LEAVE
ENDF ev_sle

FUNC ev_sge
        ENTER
        call ev_scmp
        mov ecx, 3
        mov edx, 1
        cmp eax, -1
        cmove eax, edx
        cmovne eax, ecx
        LEAVE
ENDF ev_sge

# ---------------------------------------------------------------------
# eval

        .section .rodata
        .align 4
arith_op_ids:
        .long OP_ADD, OP_ADDMOD, OP_SUB, OP_MOD, OP_SMOD, OP_MUL, OP_MULMOD
        .long OP_DIV, OP_SDIV, OP_EXP, OP_SIGNEXTEND, OP_SHL, OP_SHR, OP_SAR
        .long OP_AND, OP_OR, OP_XOR, OP_NOT, OP_BYTE, OP_EQ, OP_LT, OP_LE
        .long OP_GT, OP_SGT, OP_SLT, OP_GE, OP_SGE, OP_SLE, 0

        .section .bss
arith_op_flags: .space OP_COUNT + 1
        .text

# arith_ops_init(): the OPCODES membership table
FUNC arith_ops_init
        lea rcx, [rip + arith_op_ids]
        lea rdx, [rip + arith_op_flags]
1:      mov eax, [rcx]
        test eax, eax
        jz 2f
        mov byte ptr [rdx + rax], 1
        add rcx, 4
        jmp 1b
2:      ret
ENDF arith_ops_init

# is_arith_op(id) -> eax
FUNC is_arith_op
        lea rax, [rip + arith_op_flags]
        movzx eax, byte ptr [rax + rdi]
        ret
ENDF is_arith_op

# binary op dispatch: ev_binary(id, a, b) -> value, NIL if not binary
        .section .data
        .align 8
ev_binary_table:
        .fill OP_COUNT + 1, 8, 0
        .text

FUNC ev_binary_init
        lea rax, [rip + ev_binary_table]
        lea rcx, [rip + ev_add]
        mov [rax + 8*OP_ADD], rcx
        lea rcx, [rip + ev_sub]
        mov [rax + 8*OP_SUB], rcx
        lea rcx, [rip + ev_mul]
        mov [rax + 8*OP_MUL], rcx
        lea rcx, [rip + ev_div]
        mov [rax + 8*OP_DIV], rcx
        lea rcx, [rip + ev_sdiv]
        mov [rax + 8*OP_SDIV], rcx
        lea rcx, [rip + ev_mod]
        mov [rax + 8*OP_MOD], rcx
        lea rcx, [rip + ev_smod]
        mov [rax + 8*OP_SMOD], rcx
        lea rcx, [rip + ev_exp]
        mov [rax + 8*OP_EXP], rcx
        lea rcx, [rip + ev_signextend]
        mov [rax + 8*OP_SIGNEXTEND], rcx
        lea rcx, [rip + ev_shl]
        mov [rax + 8*OP_SHL], rcx
        lea rcx, [rip + ev_shr]
        mov [rax + 8*OP_SHR], rcx
        lea rcx, [rip + ev_sar]
        mov [rax + 8*OP_SAR], rcx
        lea rcx, [rip + ev_or]
        mov [rax + 8*OP_OR], rcx
        lea rcx, [rip + ev_xor]
        mov [rax + 8*OP_XOR], rcx
        lea rcx, [rip + ev_byte]
        mov [rax + 8*OP_BYTE], rcx
        lea rcx, [rip + ev_eq]
        mov [rax + 8*OP_EQ], rcx
        lea rcx, [rip + ev_lt]
        mov [rax + 8*OP_LT], rcx
        lea rcx, [rip + ev_le]
        mov [rax + 8*OP_LE], rcx
        lea rcx, [rip + ev_gt]
        mov [rax + 8*OP_GT], rcx
        lea rcx, [rip + ev_ge]
        mov [rax + 8*OP_GE], rcx
        lea rcx, [rip + ev_slt]
        mov [rax + 8*OP_SLT], rcx
        lea rcx, [rip + ev_sgt]
        mov [rax + 8*OP_SGT], rcx
        lea rcx, [rip + ev_sle]
        mov [rax + 8*OP_SLE], rcx
        lea rcx, [rip + ev_sge]
        mov [rax + 8*OP_SGE], rcx
        ret
ENDF ev_binary_init

# arith_apply(id, count, elems) -> value, or NIL when the arity doesn't fit
# (elems[0] is the opcode string, the arguments follow, all integers)
FUNC arith_apply
        ENTER
        mov ebx, edi
        mov r12, rsi
        mov r13, rdx
        mov eax, ebx
        JT_SWITCH arith_apply, OP_COUNT, .Lap_binary
        JT_CASE arith_apply, OP_AND, .Lap_and
        JT_CASE arith_apply, OP_OR, .Lap_or
        JT_CASE arith_apply, OP_NOT, .Lap_not
        JT_CASE arith_apply, OP_ADDMOD, .Lap_3
        JT_CASE arith_apply, OP_MULMOD, .Lap_3
        JT_END arith_apply, OP_COUNT, .Lap_binary
.Lap_binary:                            # the others: binary, from ev_binary_table
        cmp r12, 3
        jne .Lap_nil
        lea rax, [rip + ev_binary_table]
        mov rax, [rax + rbx*8]
        test rax, rax
        jz .Lap_nil
        mov rdi, [r13 + 8]
        mov rsi, [r13 + 16]
        call rax
        LEAVE
.Lap_and:
        cmp r12, 2
        jb .Lap_nil
        mov rax, [r13 + 8]
        mov r14d, 2
1:      cmp r14, r12
        jae 2f
        mov rdi, rax
        mov rsi, [r13 + r14*8]
        call ev_and
        inc r14
        jmp 1b
2:      LEAVE
.Lap_or:
        cmp r12, 2
        jne 3f
        mov rax, [r13 + 8]
        LEAVE
3:      cmp r12, 3
        jne .Lap_nil
        mov rdi, [r13 + 8]
        mov rsi, [r13 + 16]
        call ev_or
        LEAVE
.Lap_not:
        cmp r12, 2
        jne .Lap_nil
        mov rdi, [r13 + 8]
        call ev_not
        LEAVE
.Lap_3:
        cmp r12, 4
        jne .Lap_nil
        mov rdi, [r13 + 8]
        mov rsi, [r13 + 16]
        mov rdx, [r13 + 24]
        cmp ebx, OP_ADDMOD
        jne 4f
        call ev_addmod
        LEAVE
4:      call ev_mulmod
        LEAVE
.Lap_nil:
        xor eax, eax
        LEAVE
ENDF arith_apply

# is_tuple(v) -> eax
FUNC is_tuple
        test dil, 1
        jnz 1f
        test rdi, rdi
        jz 1f
        xor eax, eax
        cmp dword ptr [rdi + N_KIND], K_TUPLE
        sete al
        ret
1:      xor eax, eax
        ret
ENDF is_tuple

# tuple_count(v) -> eax (v must be a tuple/list)
FUNC tuple_count
        mov eax, [rdi + N_AUX]
        ret
ENDF tuple_count

# arith_eval(exp) -> value
FUNC arith_eval
        ENTER
        mov rbx, rdi
        call is_tuple
        test eax, eax
        jz .Lev_asis
        mov r12d, [rbx + N_AUX]         # count
        test r12, r12
        jz .Lev_asis
        # a copy of the elements on the stack
        lea rax, [r12*8 + 15]
        and rax, -16
        sub rsp, rax
        mov r13, rsp
        mov rdi, r13
        lea rsi, [rbx + N_DATA]
        lea rdx, [r12*8]
        call memcpy@PLT
        # evaluate the arguments that are arithmetic
        mov r14d, 1
1:      cmp r14, r12
        jae 2f
        mov rdi, [r13 + r14*8]
        call opcode_of
        mov edi, eax
        call is_arith_op
        test eax, eax
        jz 3f
        mov rdi, [r13 + r14*8]
        call arith_eval
        mov [r13 + r14*8], rax
3:      inc r14
        jmp 1b
2:      # all ints?
        mov r14d, 1
4:      cmp r14, r12
        jae 5f
        mov rdi, [r13 + r14*8]
        call is_int
        test eax, eax
        jz .Lev_symbolic
        inc r14
        jmp 4b
5:      mov rdi, rbx
        call opcode_of
        mov edi, eax
        call is_arith_op
        test eax, eax
        jz .Lev_rebuild
        mov rdi, rbx
        call opcode_of
        mov edi, eax
        mov rsi, r12
        mov rdx, r13
        call arith_apply
        test rax, rax
        jz .Lev_rebuild
        LEAVE_DYN
.Lev_rebuild:
        mov rdi, r12
        mov rsi, r13
        call mk_tuple
        LEAVE_DYN
.Lev_symbolic:
        mov rdi, r12
        mov rsi, r13
        call mk_tuple
        mov rdi, rax
        call eval_symbolic
        LEAVE_DYN
.Lev_asis:
        mov rax, rbx
        LEAVE
ENDF arith_eval

# is_volatile(exp) -> eax: mentions storage, balances, calls... (a string
# node flagged STR_VOLATILE anywhere in the tree)
FUNC is_volatile
        test dil, 1
        jnz .Liv_no
        test rdi, rdi
        jz .Liv_no
        mov eax, [rdi + N_KIND]
        cmp eax, K_STR
        jne 1f
        mov eax, [rdi + N_AUX]
        shr eax, 31
        ret
1:      cmp eax, K_TUPLE
        je 2f
        cmp eax, K_LIST
        jne .Liv_no
2:      ENTER
        mov rbx, rdi
        xor r12d, r12d
3:      cmp r12d, [rbx + N_AUX]
        jae 4f
        mov rdi, [rbx + N_DATA + r12*8]
        call is_volatile
        test eax, eax
        jnz 5f
        inc r12
        jmp 3b
4:      xor eax, eax
        LEAVE
5:      mov eax, 1
        LEAVE
.Liv_no:
        xor eax, eax
        ret
ENDF is_volatile

# eval_symbolic(exp) -> value: identities that hold whatever the operands
FUNC eval_symbolic
        ENTER
        mov rbx, rdi
        cmp dword ptr [rbx + N_AUX], 3
        jne .Les_asis
        mov rdi, rbx
        call opcode_of
        mov r12d, eax
        mov r13, [rbx + N_DATA + 8]     # left
        mov r14, [rbx + N_DATA + 16]    # right
        # div/sdiv/mod/smod with left == 0 -> 0
        cmp r13, 1
        jne 1f
        lea rcx, [rip + .Lset_div_mod]
        cmp byte ptr [rcx + r12], 0
        jne .Les_zero
1:      cmp r12d, OP_MUL
        jne 2f
        cmp r13, 1
        je .Les_zero
        cmp r14, 1
        je .Les_zero
2:      # left == right, not volatile: the strict comparisons are false,
        # the others true
        mov rdi, r13
        mov rsi, r14
        call values_equal
        test eax, eax
        jz .Les_zero_cmp
        mov rdi, r13
        call is_volatile
        test eax, eax
        jnz .Les_zero_cmp
        mov eax, r12d
        JT_SWITCH es_same, OP_COUNT, .Les_zero_cmp
        JT_CASE es_same, OP_LT, .Les_zero
        JT_CASE es_same, OP_GT, .Les_zero
        JT_CASE es_same, OP_SLT, .Les_zero
        JT_CASE es_same, OP_SGT, .Les_zero
        JT_CASE es_same, OP_LE, .Les_one
        JT_CASE es_same, OP_GE, .Les_one
        JT_CASE es_same, OP_SLE, .Les_one
        JT_CASE es_same, OP_SGE, .Les_one
        JT_CASE es_same, OP_EQ, .Les_one
        JT_END es_same, OP_COUNT, .Les_zero_cmp
.Les_zero_cmp:
        # unsigned comparisons with zero: gt(0, x) and lt(x, 0) are false,
        # le(0, x) and ge(x, 0) true
        mov eax, r12d
        JT_SWITCH es_zero, OP_COUNT, .Les_asis
        JT_CASE es_zero, OP_GT, .Les_gt
        JT_CASE es_zero, OP_LT, .Les_lt
        JT_CASE es_zero, OP_LE, .Les_le
        JT_CASE es_zero, OP_GE, .Les_ge
        JT_END es_zero, OP_COUNT, .Les_asis
.Les_gt:
        cmp r13, 1
        je .Les_zero
        jmp .Les_asis
.Les_lt:
        cmp r14, 1
        je .Les_zero
        jmp .Les_asis
.Les_le:
        cmp r13, 1
        je .Les_one
        jmp .Les_asis
.Les_ge:
        cmp r14, 1
        je .Les_one
.Les_asis:
        mov rax, rbx
        LEAVE
.Les_zero:
        mov eax, 1
        LEAVE
.Les_one:
        mov eax, 3
        LEAVE
ENDF eval_symbolic

        OPSET_MEMBER div_mod, OP_DIV
        OPSET_MEMBER div_mod, OP_SDIV
        OPSET_MEMBER div_mod, OP_MOD
        OPSET_MEMBER div_mod, OP_SMOD
        OPSET_END div_mod, OP_COUNT

# ---------------------------------------------------------------------
# booleans

# arith_and_n(count, elems) -> value: arithmetic.and_op (flattens `and`s,
# folds ints)
FUNC arith_and_n
        ENTER
        mov r12, rdi
        mov r13, rsi
        cmp r12, 1
        jne 1f
        mov rax, [r13]
        LEAVE
1:      cmp r12, 2
        jne 2f
        mov rdi, [r13]
        mov rsi, [r13 + 8]
        call arith_and2
        LEAVE
2:      # and_op(left, and_op(rest...))
        lea rdi, [r12 - 1]
        lea rsi, [r13 + 8]
        call arith_and_n
        mov rdi, [r13]
        mov rsi, rax
        call arith_and2
        LEAVE
ENDF arith_and_n

# arith_and2(left, right) -> value
FUNC arith_and2
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call is_int
        test eax, eax
        jz 1f
        mov rdi, r12
        call is_int
        test eax, eax
        jz 1f
        mov rdi, rbx
        mov rsi, r12
        call ev_and
        LEAVE
1:      call vec_new
        mov r13, rax
        mov rdi, r13
        LOADS rsi, AND
        call vec_push
        mov rdi, rbx
        call opcode_of
        cmp eax, OP_AND
        jne 2f
        mov rdi, r13
        mov rsi, rbx
        add rsi, N_DATA + 8
        mov edx, [rbx + N_AUX]
        dec edx
        call vec_extend
        jmp 3f
2:      mov rdi, r13
        mov rsi, rbx
        call vec_push
3:      mov rdi, r12
        call opcode_of
        cmp eax, OP_AND
        jne 4f
        mov rdi, r13
        mov rsi, r12
        add rsi, N_DATA + 8
        mov edx, [r12 + N_AUX]
        dec edx
        call vec_extend
        jmp 5f
4:      mov rdi, r13
        mov rsi, r12
        call vec_push
5:      mov rdi, r13
        call vec_to_tuple
        LEAVE
ENDF arith_and2

# mk_bool_of(x) -> ("bool", x) ; mk_iszero_of(x) -> ("iszero", x)
FUNC mk_iszero_of
        mov rsi, rdi
        LOADS rdi, ISZERO
        jmp mk2
ENDF mk_iszero_of

FUNC mk_bool_of
        mov rsi, rdi
        LOADS rdi, BOOL
        jmp mk2
ENDF mk_bool_of

# is_zero(exp) -> value (sp_true/sp_false for ints, like python's bools)
FUNC is_zero
        ENTER
        mov rbx, rdi
        call is_int
        test eax, eax
        jz 1f
        lea rax, [rip + sp_false]
        cmp rbx, 1
        jne 2f
        lea rax, [rip + sp_true]
2:      LEAVE
1:      mov rdi, rbx
        call is_tuple
        test eax, eax
        jnz 3f
        mov rdi, rbx
        call mk_iszero_of
        LEAVE
3:      mov rdi, rbx
        call opcode_of
        mov r12d, eax
        JT_SWITCH iz, OP_COUNT, .Liz_cmp
        JT_CASE iz, OP_ISZERO, .Liz_iszero
        JT_CASE iz, OP_BOOL, .Liz_bool
        JT_CASE iz, OP_OR, .Liz_or
        JT_CASE iz, OP_AND, .Liz_and
        JT_END iz, OP_COUNT, .Liz_cmp
.Liz_cmp:
        # the comparisons: swap the opcode
        lea rcx, [rip + iszero_swap_table]
        mov ecx, [rcx + r12*4]
        test ecx, ecx
        jz .Liz_default
        cmp dword ptr [rbx + N_AUX], 3
        jne .Liz_default
        lea rdi, [rip + opcode_nodes]
        mov rdi, [rdi + rcx*8]
        mov rsi, [rbx + N_DATA + 8]
        mov rdx, [rbx + N_DATA + 16]
        call mk3
        LEAVE
.Liz_iszero:
        cmp dword ptr [rbx + N_AUX], 2
        jne .Liz_default
        mov r13, [rbx + N_DATA + 8]
        mov rdi, r13
        call opcode_of
        cmp eax, OP_EQ
        jne 4f
        mov rax, r13
        LEAVE
4:      cmp eax, OP_ISZERO
        jne 5f
        mov rdi, [r13 + N_DATA + 8]
        call is_zero
        LEAVE
5:      mov rdi, r13
        call mk_bool_of
        LEAVE
.Liz_bool:
        cmp dword ptr [rbx + N_AUX], 2
        jne .Liz_default
        mov rdi, [rbx + N_DATA + 8]
        call is_zero
        LEAVE
.Liz_or:
.Liz_and:
        # is_zero of every term, then and_op / or_op of them
        mov r13d, [rbx + N_AUX]
        dec r13d                        # number of terms
        jz .Liz_default
        lea rax, [r13*8 + 15]
        and rax, -16
        sub rsp, rax
        mov r14, rsp
        xor ecx, ecx
6:      cmp rcx, r13
        jae 7f
        push rcx
        push rcx
        mov rdi, [rbx + N_DATA + 8 + rcx*8]
        call is_zero
        pop rcx
        pop rcx
        mov [r14 + rcx*8], rax
        inc rcx
        jmp 6b
7:      mov rdi, r13
        mov rsi, r14
        cmp r12d, OP_OR
        jne 8f
        call arith_and_n
        LEAVE_DYN
8:      call alg_or_n
        LEAVE_DYN
.Liz_default:
        mov rdi, rbx
        call mk_iszero_of
        LEAVE
ENDF is_zero

        .section .data
        .align 4
iszero_swap_table:
        .fill OP_COUNT + 1, 4, 0
        .text

FUNC iszero_swap_init
        lea rax, [rip + iszero_swap_table]
        mov dword ptr [rax + 4*OP_LE], OP_GT
        mov dword ptr [rax + 4*OP_LT], OP_GE
        mov dword ptr [rax + 4*OP_GE], OP_LT
        mov dword ptr [rax + 4*OP_GT], OP_LE
        mov dword ptr [rax + 4*OP_SLE], OP_SGT
        mov dword ptr [rax + 4*OP_SLT], OP_SGE
        mov dword ptr [rax + 4*OP_SGE], OP_SLT
        mov dword ptr [rax + 4*OP_SGT], OP_SLE
        ret
ENDF iszero_swap_init

# simplify_bool(exp) -> value
FUNC simplify_bool
        ENTER
        mov rbx, rdi
        call opcode_of
        cmp eax, OP_ISZERO
        jne 1f
        cmp dword ptr [rbx + N_AUX], 2
        jne 3f
        mov rdi, [rbx + N_DATA + 8]
        call simplify_bool
        mov r12, rax
        mov rdi, rax
        call opcode_of
        cmp eax, OP_ISZERO
        jne 2f
        mov rax, [r12 + N_DATA + 8]
        LEAVE
2:      mov rdi, r12
        call is_zero
        LEAVE
1:      cmp eax, OP_BOOL
        jne 3f
        cmp dword ptr [rbx + N_AUX], 2
        jne 3f
        mov rax, [rbx + N_DATA + 8]
        LEAVE
3:      mov rax, rbx
        LEAVE
ENDF simplify_bool

# comp_bool(left, right) -> eax: TRI_TRUE or TRI_NONE
FUNC comp_bool
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call values_equal
        test eax, eax
        jnz .Lcb_true
        mov rdi, r12
        call mk_bool_of
        mov rdi, rbx
        mov rsi, rax
        call values_equal
        test eax, eax
        jnz .Lcb_true
        mov rdi, rbx
        call mk_bool_of
        mov rdi, rax
        mov rsi, r12
        call values_equal
        test eax, eax
        jnz .Lcb_true
        mov eax, TRI_NONE
        LEAVE
.Lcb_true:
        mov eax, TRI_TRUE
        LEAVE
ENDF comp_bool

# is_special(v, which) -> eax
FUNC is_special
        test dil, 1
        jnz 1f
        test rdi, rdi
        jz 1f
        cmp dword ptr [rdi + N_KIND], K_SPECIAL
        jne 1f
        xor eax, eax
        cmp [rdi + N_AUX], esi
        sete al
        ret
1:      xor eax, eax
        ret
ENDF is_special

# eval_bool(exp, known_true, symbolic) -> eax: TRI_TRUE / TRI_FALSE / TRI_NONE
FUNC eval_bool
        ENTER
        sub rsp, 16
        mov rbx, rdi                    # exp
        mov r12, rsi                    # known_true
        mov r13, rdx                    # symbolic flag
        # a known-true ('bool', x) is a known-true x
        mov rdi, r12
        call opcode_of
        cmp eax, OP_BOOL
        jne 1f
        cmp dword ptr [r12 + N_AUX], 2
        jne 1f
        mov r12, [r12 + N_DATA + 8]
1:      mov rdi, rbx
        mov rsi, r12
        call values_equal
        test eax, eax
        jnz .Leb_true
        mov rdi, rbx
        call is_zero
        mov rdi, rax
        mov rsi, r12
        call values_equal
        test eax, eax
        jnz .Leb_false
        mov rdi, r12
        call is_zero
        mov rdi, rbx
        mov rsi, rax
        call values_equal
        test eax, eax
        jnz .Leb_false
        mov rdi, rbx
        mov esi, SP_TRUE
        call is_special
        test eax, eax
        jnz .Leb_true
        mov rdi, rbx
        mov esi, SP_FALSE
        call is_special
        test eax, eax
        jnz .Leb_false
        mov rdi, rbx
        call is_int
        test eax, eax
        jz 2f
        mov rdi, rbx
        call int_sign
        cmp eax, 1
        je .Leb_true
        jmp .Leb_false
2:      mov rdi, rbx
        call opcode_of
        mov r14d, eax
        cmp eax, OP_BOOL
        jne 3f
        cmp dword ptr [rbx + N_AUX], 2
        jne 3f
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, r12
        mov rdx, r13
        call eval_bool
        add rsp, 16
        LEAVE
3:      cmp eax, OP_ISZERO
        jne 4f
        cmp dword ptr [rbx + N_AUX], 2
        jne 4f
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, r12
        mov rdx, r13
        call eval_bool
        cmp eax, TRI_NONE
        je 4f
        xor eax, 1
        add rsp, 16
        LEAVE
4:      cmp r14d, OP_OR
        jne 6f
        # every term must be known; the result is their or
        xor r14d, r14d                  # accumulated result
        mov ecx, 1
5:      cmp ecx, [rbx + N_AUX]
        jae 7f
        mov [rsp], rcx
        mov rdi, [rbx + N_DATA + rcx*8]
        mov rsi, r12
        mov rdx, r13
        call eval_bool
        cmp eax, TRI_NONE
        je .Leb_none
        or r14d, eax
        mov rcx, [rsp]
        inc ecx
        jmp 5b
7:      mov eax, r14d
        add rsp, 16
        LEAVE
6:      cmp r14d, OP_AND
        jne 9f
        # a false term makes it false; otherwise unknown here
        mov ecx, 1
8:      cmp ecx, [rbx + N_AUX]
        jae 9f
        mov [rsp], rcx
        mov rdi, [rbx + N_DATA + rcx*8]
        mov rsi, r12
        mov rdx, r13
        call eval_bool
        cmp eax, TRI_FALSE
        je .Leb_false
        mov rcx, [rsp]
        inc ecx
        jmp 8b
9:      # ('le'/'lt', x, a) with ('le'/'lt', x, b) known: a >= b makes it true
        mov rdi, rbx
        call opcode_of
        mov r14d, eax
        cmp eax, OP_LE
        je 10f
        cmp eax, OP_LT
        jne 12f
10:     mov rdi, r12
        call opcode_of
        cmp eax, r14d
        jne 12f
        cmp dword ptr [rbx + N_AUX], 3
        jne 12f
        cmp dword ptr [r12 + N_AUX], 3
        jne 12f
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, [r12 + N_DATA + 8]
        call values_equal
        test eax, eax
        jz 12f
        mov rdi, [rbx + N_DATA]         # the opcode string
        mov rsi, [r12 + N_DATA + 16]
        mov rdx, [rbx + N_DATA + 16]
        call mk3
        mov rdi, rax
        lea rsi, [rip + sp_true]
        mov edx, 1
        call eval_bool
        cmp eax, TRI_TRUE
        je .Leb_true
12:     test r13, r13
        jnz .Leb_symbolic
        # concrete only: eval and look at the number
        mov rdi, rbx
        call arith_eval
        mov rdi, rax
        call is_int
        test eax, eax
        jz .Leb_none
        # r != 0
        cmp rdi, 1
        je .Leb_false
        jmp .Leb_true
.Leb_symbolic:
        mov rdi, rbx
        mov rsi, r12
        call eval_bool_symbolic
        add rsp, 16
        LEAVE
.Leb_true:
        mov eax, TRI_TRUE
        add rsp, 16
        LEAVE
.Leb_false:
        mov eax, TRI_FALSE
        add rsp, 16
        LEAVE
.Leb_none:
        mov eax, TRI_NONE
        add rsp, 16
        LEAVE
ENDF eval_bool

# eval_bool_symbolic(exp, known_true) -> tri-state, the algebra part
FUNC eval_bool_symbolic
        ENTER
        mov rbx, rdi
        mov rdi, rbx
        call opcode_of
        mov r14d, eax
        cmp dword ptr [rbx + N_AUX], 3
        jne .Lebs_none
        lea rcx, [rip + .Lset_ebs_cmp]  # le, lt, gt, ge, eq
        cmp byte ptr [rcx + r14], 0
        je .Lebs_none
        mov rdi, [rbx + N_DATA + 8]
        call arith_eval
        mov r12, rax                    # left
        mov rdi, [rbx + N_DATA + 16]
        call arith_eval
        mov r13, rax                    # right
        mov rdi, r12
        call is_int
        mov ebx, eax
        mov rdi, r13
        call is_int
        and ebx, eax                    # both ints?
        mov eax, r14d
        JT_SWITCH ebs, OP_COUNT, .Lebs_eq
        JT_CASE ebs, OP_LE, .Lebs_le
        JT_CASE ebs, OP_LT, .Lebs_lt
        JT_CASE ebs, OP_GT, .Lebs_gt
        JT_CASE ebs, OP_GE, .Lebs_ge
        JT_END ebs, OP_COUNT, .Lebs_eq
.Lebs_eq:
        mov rdi, r12
        mov rsi, r13
        call values_equal
        test eax, eax
        jnz .Lebs_true
        mov rdi, r12
        mov rsi, r13
        call alg_sub_op
        cmp rax, 1
        je .Lebs_true
        jmp .Lebs_none
.Lebs_le:
        mov rdi, r12
        mov rsi, r13
        call values_equal
        test eax, eax
        jnz .Lebs_true
        test ebx, ebx
        jz 2f
        mov rdi, r12
        mov rsi, r13
        call int_cmp
        cmp eax, 1
        je .Lebs_false
        jmp .Lebs_true
2:      mov rdi, r12
        mov rsi, r13
        call alg_le_op
        jmp .Lebs_tri
.Lebs_lt:
        mov rdi, r12
        mov rsi, r13
        call values_equal
        test eax, eax
        jnz .Lebs_false
        test ebx, ebx
        jz 3f
        mov rdi, r12
        mov rsi, r13
        call int_cmp
        cmp eax, -1
        je .Lebs_true
        jmp .Lebs_false
3:      mov rdi, r12
        mov rsi, r13
        call alg_lt_op
        jmp .Lebs_tri
.Lebs_gt:
        test ebx, ebx
        jz 4f
        mov rdi, r12
        mov rsi, r13
        call int_cmp
        cmp eax, 1
        je .Lebs_true
        jmp .Lebs_false
4:      mov rdi, r12
        mov rsi, r13
        call values_equal
        test eax, eax
        jnz .Lebs_false
        # (python's symbolic `gt` branch is dead code: it calls lt_op with
        # three arguments, which raises and gets swallowed)
        jmp .Lebs_none
.Lebs_ge:
        test ebx, ebx
        jz 5f
        mov rdi, r12
        mov rsi, r13
        call int_cmp
        cmp eax, -1
        je .Lebs_false
        jmp .Lebs_true
5:      mov rdi, r12
        mov rsi, r13
        call values_equal
        test eax, eax
        jnz .Lebs_true
        mov rdi, r12
        mov rsi, r13
        call alg_lt_op
        cmp eax, TRI_TRUE
        je .Lebs_false
        cmp eax, TRI_FALSE
        je .Lebs_true
        jmp .Lebs_none
.Lebs_tri:
        # CannotCompare and None both become None
        cmp eax, TRI_CANNOT
        jne 6f
        mov eax, TRI_NONE
6:      LEAVE
.Lebs_true:
        mov eax, TRI_TRUE
        LEAVE
.Lebs_false:
        mov eax, TRI_FALSE
        LEAVE
.Lebs_none:
        mov eax, TRI_NONE
        LEAVE
ENDF eval_bool_symbolic

        OPSET_MEMBER ebs_cmp, OP_LE
        OPSET_MEMBER ebs_cmp, OP_LT
        OPSET_MEMBER ebs_cmp, OP_GT
        OPSET_MEMBER ebs_cmp, OP_GE
        OPSET_MEMBER ebs_cmp, OP_EQ
        OPSET_END ebs_cmp, OP_COUNT

# arith_module_init(): tables (called from rt_init)
FUNC arith_module_init
        ENTER
        call arith_ops_init
        call ev_binary_init
        call iszero_swap_init
        LEAVE
ENDF arith_module_init

        .section .note.GNU-stack,"",@progbits
