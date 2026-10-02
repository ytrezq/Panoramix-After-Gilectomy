# Algebra (port of panoramix/core/algebra.py): symbolic add/mul/masks and
# comparisons. As the original says, "crazy-fragile": the port follows it
# case by case, including its oddities, because the readability of the
# output depends on the exact shapes it produces.
#
# Results of comparisons are four-state (see TRI_*).

.include "defs.inc"

        .text

# ---------------------------------------------------------------------
# small helpers

# is_op_n(v, op, n) -> eax: v is a tuple with opcode op and n elements
# (a leaf: only rax is changed)
FUNC is_op_n
        test edx, edx
        jz 1f
        OP_N_CHECK esi, edx, 1f
        mov eax, 1
        ret
1:      xor eax, eax
        ret
ENDF is_op_n

# to_exp2(v) -> rax: k if v is 2^k (helpers.to_exp2: exactly, not by a
# float's log2), else -1. v an int (not a bool).
FUNC to_exp2
        ENTER
        mov rbx, rdi
        call is_int
        test eax, eax
        jz .Lte_no
        test bl, 1
        jz 1f
        mov rax, rbx                    # a small one
        sar rax, 1
        test rax, rax
        jle .Lte_no
        lea rcx, [rax - 1]
        test rax, rcx
        jnz .Lte_no
        bsf rax, rax
        LEAVE
1:      mov rdi, rbx                    # a big one
        call int_sign
        cmp eax, 1
        jne .Lte_no
        mov rdi, rbx
        call value_mpz
        mov rbx, rax
        mov rdi, rax
        call __gmpz_popcount@PLT
        cmp rax, 1
        jne .Lte_no
        mov rdi, rbx
        xor esi, esi
        call __gmpz_scan1@PLT
        LEAVE
.Lte_no:
        mov rax, -1
        LEAVE
ENDF to_exp2

# pow2(k) -> value: 2^k (0 for k < 0, and k is clamped to 4096: the
# expressions never need more than 256 bits, but a variant of an
# expression can put 2^230 in a shift)
FUNC pow2
        cmp rdi, 62
        jae 1f
        mov ecx, edi
        mov eax, 1
        shl rax, cl
        lea rax, [rax + rax + 1]
        ret
1:      test rdi, rdi
        jns 2f
        mov eax, 1                      # 0
        ret
2:      cmp rdi, 4096
        jle 3f
        mov edi, 4096
3:      ENTER
        mov rbx, rdi
        lea rdi, [r15 + CTX_MPZ_R]
        mov esi, 1
        call __gmpz_set_ui@PLT
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, rdi
        mov rdx, rbx
        call __gmpz_mul_2exp@PLT
        call arith_result
        LEAVE
ENDF pow2

# int_add(a, b) / int_sub(a, b) / int_mul(a, b): exact python integer
# arithmetic on integer values (no wrapping)
FUNC int_add
        test dil, 1
        jz 1f
        test sil, 1
        jz 1f
        mov rax, rdi
        sar rax, 1
        mov rcx, rsi
        sar rcx, 1
        add rax, rcx
        mov rcx, SMALL_MAX
        cmp rax, rcx
        jg 1f
        mov rcx, SMALL_MIN
        cmp rax, rcx
        jl 1f
        lea rax, [rax + rax + 1]
        ret
1:      ENTER
        call arith_load
        lea rdi, [r15 + CTX_MPZ_R]
        lea rsi, [r15 + CTX_MPZ_A]
        lea rdx, [r15 + CTX_MPZ_B]
        call __gmpz_add@PLT
        call arith_result
        LEAVE
ENDF int_add

FUNC int_sub
        test dil, 1
        jz 1f
        test sil, 1
        jz 1f
        mov rax, rdi
        sar rax, 1
        mov rcx, rsi
        sar rcx, 1
        sub rax, rcx
        mov rcx, SMALL_MAX
        cmp rax, rcx
        jg 1f
        mov rcx, SMALL_MIN
        cmp rax, rcx
        jl 1f
        lea rax, [rax + rax + 1]
        ret
1:      ENTER
        call arith_load
        lea rdi, [r15 + CTX_MPZ_R]
        lea rsi, [r15 + CTX_MPZ_A]
        lea rdx, [r15 + CTX_MPZ_B]
        call __gmpz_sub@PLT
        call arith_result
        LEAVE
ENDF int_sub

FUNC int_mul
        test dil, 1
        jz 1f
        test sil, 1
        jz 1f
        mov rax, rdi
        sar rax, 1
        mov rcx, rsi
        sar rcx, 1
        imul rax, rcx
        jo 1f
        mov rcx, SMALL_MAX
        cmp rax, rcx
        jg 1f
        mov rcx, SMALL_MIN
        cmp rax, rcx
        jl 1f
        lea rax, [rax + rax + 1]
        ret
1:      ENTER
        call arith_load
        lea rdi, [r15 + CTX_MPZ_R]
        lea rsi, [r15 + CTX_MPZ_A]
        lea rdx, [r15 + CTX_MPZ_B]
        call __gmpz_mul@PLT
        call arith_result
        LEAVE
ENDF int_mul

# int_neg(a) -> value
FUNC int_neg
        mov rsi, rdi
        mov edi, 1
        jmp int_sub
ENDF int_neg

# int_floordiv(a, b) -> value (python //; 0 for b == 0, where python would
# raise) ; int_mod(a, b) (python %)
FUNC int_floordiv
        cmp rsi, 1
        jne 1f
        mov eax, 1
        ret
1:      ENTER
        call arith_load
        lea rdi, [r15 + CTX_MPZ_R]
        lea rsi, [r15 + CTX_MPZ_A]
        lea rdx, [r15 + CTX_MPZ_B]
        call __gmpz_fdiv_q@PLT
        call arith_result
        LEAVE
ENDF int_floordiv

FUNC int_mod
        cmp rsi, 1
        jne 1f
        mov eax, 1
        ret
1:      ENTER
        call arith_load
        lea rdi, [r15 + CTX_MPZ_R]
        lea rsi, [r15 + CTX_MPZ_A]
        lea rdx, [r15 + CTX_MPZ_B]
        call __gmpz_fdiv_r@PLT
        call arith_result
        LEAVE
ENDF int_mod

# int_mod_2exp(a, k) -> value: a mod 2^k (non-negative)
FUNC int_mod_2exp
        ENTER
        mov rbx, rsi
        mov rsi, rdi
        lea rdi, [r15 + CTX_MPZ_R]
        call value_set_mpz
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, rdi
        mov rdx, rbx
        call __gmpz_fdiv_r_2exp@PLT
        call arith_result
        LEAVE
ENDF int_mod_2exp

# clamp_bits(v) -> rax: a small int value as a plain integer, clamped to
# [-4096, 4096] (masks never exceed 256 bits; python would try to build
# 2^huge and die)
FUNC clamp_bits
        test dil, 1
        jz 1f
        mov rax, rdi
        sar rax, 1
        cmp rax, 4096
        jg 2f
        cmp rax, -4096
        jl 3f
        ret
1:      cmp dword ptr [rdi + N_DATA + MPZ_SIZE], 0
        jl 3f
2:      mov eax, 4096
        ret
3:      mov rax, -4096
        ret
ENDF clamp_bits

# mask_to_int(size, offset) -> value: (2^size - 1) * 2^offset, with the
# negative-offset handling of algebra.mask_to_int (ints only)
FUNC mask_to_int
        ENTER
        call clamp_bits
        mov rbx, rax                    # size
        mov rdi, rsi
        call clamp_bits
        mov r12, rax                    # offset
        test r12, r12
        jns 1f
        # offset < 0: size += offset; if size < 1: 0; else 2^size - 1
        add rbx, r12
        cmp rbx, 1
        jge 2f
        mov eax, 1
        LEAVE
2:      mov rdi, rbx
        call pow2
        mov rdi, rax
        mov esi, 3
        call int_sub
        LEAVE
1:      test rbx, rbx
        jns 3f
        mov eax, 1                      # 2^negative - 1 -> 0 (python: -1 + fraction... never happens)
        LEAVE
3:      mov rdi, rbx
        call pow2
        mov rdi, rax
        mov esi, 3
        call int_sub
        mov rbx, rax
        mov rdi, r12
        call pow2
        mov rdi, rbx
        mov rsi, rax
        call int_mul
        LEAVE
ENDF mask_to_int

# alg_apply_mask(val, size, offset, shl) -> value (all ints)
FUNC alg_apply_mask
        ENTER
        mov rbx, rdi
        mov r12, rcx                    # shl
        mov rdi, rsi
        mov rsi, rdx
        call mask_to_int
        mov rdi, rbx
        mov rsi, rax
        call ev_and
        mov rbx, rax
        test r12b, 1
        jz .Lam_zero                    # a huge shift
        mov rax, r12
        sar rax, 1
        cmp rax, 256
        jge .Lam_zero
        cmp rax, -256
        jle .Lam_zero
        test rax, rax
        jz 1f
        js 2f
        # val << shl
        mov r12, rax
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, rbx
        call value_set_mpz
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, rdi
        mov rdx, r12
        call __gmpz_mul_2exp@PLT
        call arith_result
        LEAVE
2:      # val >> -shl
        neg rax
        mov r12, rax
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, rbx
        call value_set_mpz
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, rdi
        mov rdx, r12
        call __gmpz_fdiv_q_2exp@PLT
        call arith_result
        LEAVE
1:      mov rax, rbx
        LEAVE
.Lam_zero:
        mov eax, 1
        LEAVE
ENDF alg_apply_mask

# all_ints(count, elems) -> eax
FUNC all_ints
        push rdi                        # (a leaf: only rax is changed)
        push rsi
1:      test rdi, rdi
        jz 2f
        mov rax, [rsi]
        test al, 1
        jnz 3f
        test rax, rax
        jz 4f
        cmp dword ptr [rax + N_KIND], K_INT
        jne 4f
3:      add rsi, 8
        dec rdi
        jmp 1b
2:      mov eax, 1
        pop rsi
        pop rdi
        ret
4:      xor eax, eax
        pop rsi
        pop rdi
        ret
ENDF all_ints

# cleanup_mul_1(exp) -> value: ('mul', 1, x) -> x, recursively
FUNC cleanup_mul_1
        STACK_CHECK
        ENTER
        mov rbx, rdi
        test dil, 1
        jnz .Lcm_asis
        test rdi, rdi
        jz .Lcm_asis
        mov eax, [rbx + N_KIND]
        cmp eax, K_TUPLE
        je 1f
        cmp eax, K_LIST
        jne .Lcm_asis
1:      mov rdi, rbx
        mov esi, OP_MUL
        mov edx, 3
        call is_op_n
        test eax, eax
        jz 2f
        cmp qword ptr [rbx + N_DATA + 8], 3
        jne 2f
        mov rax, [rbx + N_DATA + 16]    # (not recursively, like helpers.cleanup_mul_1)
        LEAVE
2:      mov r12d, [rbx + N_AUX]
        test r12, r12
        jz .Lcm_asis
        lea rax, [r12*8 + 15]
        and rax, -16
        STACK_ALLOC rax
        mov r13, rsp
        xor r14d, r14d
3:      cmp r14, r12
        jae 4f
        mov rdi, [rbx + N_DATA + r14*8]
        call cleanup_mul_1
        mov [r13 + r14*8], rax
        inc r14
        jmp 3b
4:      mov rdi, rbx
        mov rsi, r13
        call mk_seq_like
        LEAVE_DYN
.Lcm_asis:
        mov rax, rbx
        LEAVE
ENDF cleanup_mul_1

# ---------------------------------------------------------------------
# or_op

# alg_or_n(count, elems) -> value: or_op(*args)
FUNC alg_or_n
        ENTER
        mov r12, rdi
        mov r13, rsi
        cmp r12, 1
        jne 1f
        mov rax, [r13]
        LEAVE
1:      call vec_new
        mov rbx, rax
        mov rdi, rbx
        LOADS rsi, OR
        call vec_push
        xor r14d, r14d
2:      cmp r14, r12
        jae 6f
        mov rdi, [r13 + r14*8]
        mov esi, 1
        call py_equal                   # 0 (and False) is dropped
        test eax, eax
        jnz 5f
        mov rdi, [r13 + r14*8]
        call opcode_of
        cmp eax, OP_OR
        jne 3f
        mov rdi, rbx
        mov rsi, [r13 + r14*8]
        mov edx, [rsi + N_AUX]
        dec edx
        add rsi, N_DATA + 8
        call vec_extend
        jmp 5f
3:      # skip duplicates
        mov rcx, 1
4:      cmp rcx, [rbx + VEC_LEN]
        jae 7f
        mov rax, [rbx + VEC_DATA]
        mov rdi, [rax + rcx*8]
        mov rsi, [r13 + r14*8]
        push rcx
        push rcx
        call py_equal
        pop rcx
        pop rcx
        test eax, eax
        jnz 5f
        inc rcx
        jmp 4b
7:      mov rdi, rbx
        mov rsi, [r13 + r14*8]
        call vec_push
5:      inc r14
        jmp 2b
6:      mov rax, [rbx + VEC_LEN]
        cmp rax, 1
        jne 8f
        mov eax, 1                      # nothing left: 0
        LEAVE
8:      cmp rax, 2
        jne 9f
        mov rax, [rbx + VEC_DATA]
        mov rax, [rax + 8]
        LEAVE
9:      mov rdi, rbx
        call vec_to_tuple
        LEAVE
ENDF alg_or_n

FUNC alg_or2
        ENTER
        sub rsp, 16
        mov [rsp], rdi
        mov [rsp + 8], rsi
        mov edi, 2
        mov rsi, rsp
        call alg_or_n
        add rsp, 16
        LEAVE
ENDF alg_or2

# ---------------------------------------------------------------------
# mul_op / add_op / sub_op

# alg_minus_op(exp) -> value
FUNC alg_minus_op
        STACK_CHECK
        mov rsi, rdi
        mov rdi, -1
        TAG rdi
        jmp alg_mul2
ENDF alg_minus_op

# alg_sub_op(left, right) -> value
FUNC alg_sub_op
        STACK_CHECK
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
        call int_sub
        LEAVE
1:      mov rdi, rbx
        mov esi, 1
        call py_equal
        test eax, eax
        jz 2f
        mov rdi, r12
        call alg_minus_op
        LEAVE
2:      mov rdi, r12
        mov esi, 1
        call py_equal
        test eax, eax
        jz 3f
        mov rax, rbx
        LEAVE
3:      mov rdi, r12
        call alg_minus_op
        mov rdi, rbx
        mov rsi, rax
        call alg_add2
        LEAVE
ENDF alg_sub_op

# alg_mul2(a, b) -> value: mul_op(a, b)
FUNC alg_mul2
        STACK_CHECK
        ENTER
        sub rsp, 16
        mov [rsp], rdi
        mov [rsp + 8], rsi
        # memoized (a pure function of the two; the minus_op of a sum
        # distributes over its terms, and comes back for the same ones)
        mov edi, MEMO_MUL2
        mov rsi, [rsp]
        mov rdx, [rsp + 8]
        call memo2_get
        test rax, rax
        jnz 1f
        mov edi, 2
        mov rsi, rsp
        call alg_mul_n
        mov rbx, rax
        mov edi, MEMO_MUL2
        mov rsi, [rsp]
        mov rdx, [rsp + 8]
        mov rcx, rax
        call memo2_put
        mov rax, rbx
1:      add rsp, 16
        LEAVE
ENDF alg_mul2

# alg_mul_n(count, args) -> value: mul_op(*args)
FUNC alg_mul_n
        STACK_CHECK
        ENTER
        sub rsp, 32
        mov rbx, rdi                    # count
        mov r12, rsi                    # args
        cmp rbx, 1
        jne 1f
        mov rax, [r12]
        add rsp, 32
        LEAVE
1:      cmp rbx, 2
        jne 2f
        mov rdi, [r12]                  # match(args, (int, int)): isinstance,
        call vr_number                  # a bool is a number too
        test rax, rax
        jz 2f
        mov [rsp], rax
        mov rdi, [r12 + 8]
        call vr_number
        test rax, rax
        jz 2f
        mov rdi, [rsp]
        mov rsi, rax
        call int_mul
        add rsp, 32
        LEAVE
2:      # a power of two among the args: mask_op(mul_op(rest), 256 - p, shl = p)
        xor r13d, r13d
3:      cmp r13, rbx
        jae 6f
        mov rdi, [r12 + r13*8]
        call to_exp2
        cmp rax, -1
        je 4f
        test rax, rax
        jz 4f                           # 2^0 = 1 is falsy in python
        mov r14, rax                    # p
        # rest = args without args[r13]
        lea rdi, [rbx*8 + 8]
        call arena_alloc
        xor ecx, ecx
        xor edx, edx
5:      cmp rcx, rbx
        jae 7f
        cmp rcx, r13
        je 8f
        mov rsi, [r12 + rcx*8]
        mov [rax + rdx*8], rsi
        inc rdx
8:      inc rcx
        jmp 5b
7:      mov rdi, rdx
        mov rsi, rax
        call alg_mul_n
        # mask_op(exp, size=256-p, offset=0, shl=p, shr=0)
        mov rdi, rax
        mov esi, 256
        sub rsi, r14
        TAG rsi
        mov edx, 1
        mov rcx, r14
        TAG rcx
        mov r8d, 1
        call alg_mask_op
        add rsp, 32
        LEAVE
4:      inc r13
        jmp 3b
6:      # flatten the muls
        call vec_new
        mov r13, rax
        xor r14d, r14d
9:      cmp r14, rbx
        jae 10f
        mov rdi, [r12 + r14*8]
        OPCODE_OF_RDI
        cmp eax, OP_MUL
        jne 11f
        mov rdi, r13
        mov rsi, [r12 + r14*8]
        mov edx, [rsi + N_AUX]
        dec edx
        add rsi, N_DATA + 8
        call vec_extend
        jmp 12f
11:     mov rdi, r13
        mov rsi, [r12 + r14*8]
        call vec_push
12:     inc r14
        jmp 9b
10:     # distribute over the first add
        mov rbx, [r13 + VEC_LEN]
        mov r12, [r13 + VEC_DATA]
        xor r14d, r14d
13:     cmp r14, rbx
        jae 16f
        mov rdi, [r12 + r14*8]
        OPCODE_OF_RDI
        cmp eax, OP_ADD
        je 14f
        inc r14
        jmp 13b
14:     # el = args[r14]; without = the others; add_op(*[mul_op(x, *without) for x in el[1:]])
        mov rdi, [r12 + r14*8]
        mov [rsp], rdi                  # el
        call vec_new
        mov [rsp + 8], rax              # results
        mov qword ptr [rsp + 16], 1     # index into el
15:     mov rax, [rsp]
        mov rcx, [rsp + 16]
        cmp ecx, [rax + N_AUX]
        jae 17f
        # build (x, without...)
        lea rdi, [rbx*8 + 8]
        call arena_alloc
        mov rcx, [rsp + 16]
        mov rdx, [rsp]
        mov rdx, [rdx + N_DATA + rcx*8]
        mov [rax], rdx
        mov rdi, rax
        xor ecx, ecx
        mov edx, 1
18:     cmp rcx, rbx
        jae 19f
        cmp rcx, r14
        je 20f
        mov rsi, [r12 + rcx*8]
        mov [rdi + rdx*8], rsi
        inc rdx
20:     inc rcx
        jmp 18b
19:     mov rsi, rdi
        mov rdi, rdx
        call alg_mul_n
        mov rdi, [rsp + 8]
        mov rsi, rax
        call vec_push
        inc qword ptr [rsp + 16]
        jmp 15b
17:     mov rax, [rsp + 8]
        mov rdi, [rax + VEC_LEN]
        mov rsi, [rax + VEC_DATA]
        call alg_add_n
        add rsp, 32
        LEAVE
16:     # multiply the numbers, keep the symbols
        mov qword ptr [rsp], 3          # real = 1
        call vec_new
        mov [rsp + 8], rax
        xor r14d, r14d
21:     cmp r14, rbx
        jae 24f
        mov rdi, [r12 + r14*8]
        mov esi, 1
        call py_equal                   # r == 0 -> 0
        test eax, eax
        jnz .Lmul_zero
        mov rdi, [r12 + r14*8]
        call is_int
        test eax, eax
        jz 22f
        mov rdi, [rsp]
        mov rsi, [r12 + r14*8]
        call int_mul
        mov [rsp], rax
        jmp 23f
22:     mov rdi, [rsp + 8]
        mov rsi, [r12 + r14*8]
        call vec_push
23:     inc r14
        jmp 21b
24:     mov rax, [rsp + 8]
        cmp qword ptr [rax + VEC_LEN], 0
        jne 25f
        mov rax, [rsp]
        add rsp, 32
        LEAVE
25:     # ("mul", real) + symbolic
        call vec_new
        mov r13, rax
        mov rdi, r13
        LOADS rsi, MUL
        call vec_push
        mov rdi, r13
        mov rsi, [rsp]
        call vec_push
        mov rax, [rsp + 8]
        mov rdi, r13
        mov rsi, [rax + VEC_DATA]
        mov rdx, [rax + VEC_LEN]
        call vec_extend
        mov rdi, r13
        call vec_to_tuple
        add rsp, 32
        LEAVE
.Lmul_zero:
        mov eax, 1
        add rsp, 32
        LEAVE
ENDF alg_mul_n

# flatten_adds_into(vec, count, args): the args pushed on vec, their
# ('add', ...) ones expanded, recursively - python's flatten_adds expands
# a level at a time until none is left: the same terms in the same order
FUNC flatten_adds_into
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi                    # count
        mov r13, rdx                    # args
        xor r14d, r14d
1:      cmp r14, r12
        jae 9f
        mov rdi, [r13 + r14*8]
        inc r14
        OPCODE_OF_RDI
        cmp eax, OP_ADD
        je 3f
        mov rsi, rdi
        mov rdi, rbx
        call vec_push
        jmp 1b
3:      mov esi, [rdi + N_AUX]
        cmp esi, 2
        jbe .Lfa_assert                 # python: assert len(r[1:]) > 1
        dec esi
        lea rdx, [rdi + N_DATA + 8]
        mov rdi, rbx
        call flatten_adds_into
        jmp 1b
9:      LEAVE
.Lfa_assert:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_fa_assert]
        call err_throw
ENDF flatten_adds_into

        .section .rodata
.Ls_fa_assert: .asciz "flatten_adds: an add of less than two terms"
        .text

# alg_add2(a, b) -> value: add_op(a, b)
FUNC alg_add2
        STACK_CHECK
        ENTER
        sub rsp, 16
        mov [rsp], rdi
        mov [rsp + 8], rsi
        mov edi, 2
        mov rsi, rsp
        call alg_add_n
        add rsp, 16
        LEAVE
ENDF alg_add2

# alg_add3(a, b, c)
FUNC alg_add3
        STACK_CHECK
        ENTER
        sub rsp, 32
        mov [rsp], rdi
        mov [rsp + 8], rsi
        mov [rsp + 16], rdx
        mov edi, 3
        mov rsi, rsp
        call alg_add_n
        add rsp, 32
        LEAVE
ENDF alg_add3

# alg_add_n(count, args) -> value: add_op(*args), memoized on the args
FUNC alg_add_n
        STACK_CHECK
        ENTER
        sub rsp, 48
        mov rbx, rdi
        mov r12, rsi
        mov qword ptr [r15 + CTX_ADD_WRAPPED], 0        # (python's: no sum reduced)
        cmp rbx, 1
        jne 1f
        mov rax, [r12]
        add rsp, 48
        LEAVE
1:      test rbx, rbx
        jnz 2f
        mov eax, 1
        add rsp, 48
        LEAVE
2:      # all ints: their sum
        mov qword ptr [rsp], 1
        xor r13d, r13d
3:      cmp r13, rbx
        jae 4f
        mov rdi, [r12 + r13*8]
        call is_int
        test eax, eax
        jz 5f
        mov rdi, [rsp]
        mov rsi, [r12 + r13*8]
        call int_add
        mov [rsp], rax
        inc r13
        jmp 3b
4:      mov rax, [rsp]
        add rsp, 48
        LEAVE
5:      cmp rbx, 2
        je 8f
        # more: not remembered (the tuple of the arguments made for the
        # key, 0 to 12% of them asked again)
        mov rdi, rbx
        mov rsi, r12
        call add_op_impl
        add rsp, 48
        LEAVE
8:      # two: the pair's memo, without a tuple made (most adds), with
        # whether add_op reduced its sum (CTX_ADD_WRAPPED: agz_by_family)
        mov edi, MEMO_ADD2
        mov rsi, [r12]
        mov rdx, [r12 + 8]
        call memo2_get
        test rax, rax
        jz 9f
        mov [r15 + CTX_ADD_WRAPPED], rdx        # (the entry's fourth word)
        add rsp, 48
        LEAVE
9:      mov rdi, rbx
        mov rsi, r12
        call add_op_impl
        mov [rsp + 16], rax
        mov edi, MEMO_ADD2
        mov rsi, [r12]
        mov rdx, [r12 + 8]
        mov rcx, [rsp + 16]
        mov r8, [r15 + CTX_ADD_WRAPPED]
        call memo2_put_w
        mov rax, [rsp + 16]
        add rsp, 48
        LEAVE
ENDF alg_add_n

# add_op_impl(count, args) -> value. python's add_op sums the numbers
# among the terms (flatten_adds'), and combines the others (try_add, in
# order) without looking at the numbers - the combination gives the
# symbolic part and a number of its own (try_add's ('add', num, term)):
# that is remembered for the sequence of the other terms (MEMO_ADD_FAMILY,
# add_op_family), whatever the numbers - add_op(64, x, y) and
# add_op(96, x, y) combine x and y once. The result: the numbers' sum
# plus the combination's, reduced mod 2^256 when positive, first.
FUNC add_op_impl
        STACK_CHECK
        ENTER
        sub rsp, 48
        .set AO_REAL, 0
        .set AO_S, 8                    # the combination's terms (a tuple)
        .set AO_KEY, 16
        mov rbx, rdi
        mov r12, rsi
        # res = flatten_adds(args)
        call vec_new
        mov r13, rax
        mov rdi, r13
        mov rsi, rbx
        mov rdx, r12
        call flatten_adds_into
        # the numbers summed, the other terms kept in order
        mov qword ptr [rsp + AO_REAL], 1
        xor r14d, r14d                  # read
        xor ebx, ebx                    # written
1:      cmp r14, [r13 + VEC_LEN]
        jae 3f
        mov rax, [r13 + VEC_DATA]
        mov rdi, [rax + r14*8]
        inc r14
        test dil, 1
        jnz 2f
        test rdi, rdi
        jz 14f
        cmp dword ptr [rdi + N_KIND], K_INT
        je 2f
14:     mov [rax + rbx*8], rdi
        inc rbx
        jmp 1b
2:      mov rsi, rdi
        mov rdi, [rsp + AO_REAL]
        call int_add
        mov [rsp + AO_REAL], rax
        jmp 1b
3:      mov [r13 + VEC_LEN], rbx
        # their combination, remembered for the sequence
        mov edi, K_TUPLE
        mov rsi, rbx
        mov rdx, [r13 + VEC_DATA]
        call mk_seq
        mov [rsp + AO_KEY], rax
        mov edi, MEMO_ADD_FAMILY
        mov rsi, rax
        call memo_get
        test rax, rax
        jnz 4f
        mov rdi, r13
        call add_op_family
        mov r12, rax
        mov edi, MEMO_ADD_FAMILY
        mov rsi, [rsp + AO_KEY]
        mov rdx, rax
        call memo_put
        mov rax, r12
4:      mov rcx, [rax + N_DATA + 8]
        mov [rsp + AO_S], rcx
        mov rdi, [rsp + AO_REAL]
        mov rsi, [rax + N_DATA]
        call int_add
        mov [rsp + AO_REAL], rax
        # the result
        mov qword ptr [r15 + CTX_ADD_WRAPPED], 0
        mov r12, [rsp + AO_S]
        mov r13d, [r12 + N_AUX]         # the terms
        cmp qword ptr [rsp + AO_REAL], 1
        je 6f                           # real == 0: the terms alone
        # real > 0: real % 2**256 (a small number stays as it is); whether
        # that changed it, for alg_add_n (CTX_ADD_WRAPPED: see
        # agz_by_family)
        mov rdi, [rsp + AO_REAL]
        test dil, 1
        jnz 5f
        call int_sign
        cmp eax, 1
        jne 5f
        mov rdi, [rsp + AO_REAL]
        mov esi, 256
        call int_mod_2exp
        mov rdi, rax
        xchg rax, [rsp + AO_REAL]
        mov rsi, rax
        call values_equal
        xor eax, 1
        mov [r15 + CTX_ADD_WRAPPED], rax
5:      test r13, r13
        jnz 7f
        mov rax, [rsp + AO_REAL]        # the number alone
        add rsp, 48
        LEAVE
7:      # ('add', real) + terms
        lea rax, [r13*8 + 16 + 15]
        and rax, -16
        STACK_ALLOC rax
        LOADS rax, ADD
        mov [rsp], rax
        mov rax, [rbp - 32 - 48 + AO_REAL]
        mov [rsp + 8], rax
        xor ecx, ecx
8:      cmp rcx, r13
        jae 9f
        mov rax, [r12 + N_DATA + rcx*8]
        mov [rsp + 16 + rcx*8], rax
        inc rcx
        jmp 8b
9:      mov edi, K_TUPLE
        lea rsi, [r13 + 2]
        mov rdx, rsp
        call mk_seq
        lea rsp, [rbp - 32]
        LEAVE
6:      test r13, r13
        jnz 10f
        mov eax, 1                      # nothing: 0
        add rsp, 48
        LEAVE
10:     cmp r13, 1
        jne 11f
        mov rax, [r12 + N_DATA]         # one term
        add rsp, 48
        LEAVE
11:     # ('add',) + terms
        lea rax, [r13*8 + 8 + 15]
        and rax, -16
        STACK_ALLOC rax
        LOADS rax, ADD
        mov [rsp], rax
        xor ecx, ecx
12:     cmp rcx, r13
        jae 13f
        mov rax, [r12 + N_DATA + rcx*8]
        mov [rsp + 8 + rcx*8], rax
        inc rcx
        jmp 12b
13:     mov edi, K_TUPLE
        lea rsi, [r13 + 1]
        mov rdx, rsp
        call mk_seq
        lea rsp, [rbp - 32]
        LEAVE
ENDF add_op_impl

# add_op_family(vec) -> rax: (num, terms): add_op's combination of the
# terms of vec (numbers none; the vector is used up) - every term that
# isn't a mul made mul_op(1, term), each one added to the first it
# combines with (try_add) or kept, the zero ones dropped and the mul 1
# ones unwrapped - and the sum of the numbers that came out of it
FUNC add_op_family
        STACK_CHECK
        ENTER
        sub rsp, 48
        mov r13, rdi
        # every term that isn't a mul becomes mul_op(1, term)
        xor r14d, r14d
1:      cmp r14, [r13 + VEC_LEN]
        jae 2f
        mov rax, [r13 + VEC_DATA]
        mov rdi, [rax + r14*8]
        call opcode_of
        cmp eax, OP_MUL
        je 3f
        mov rax, [r13 + VEC_DATA]
        mov rsi, [rax + r14*8]
        mov edi, 3                      # 1
        call alg_mul2
        mov rcx, [r13 + VEC_DATA]
        mov [rcx + r14*8], rax
3:      inc r14
        jmp 1b
2:      mov qword ptr [rsp], 1          # real = 0
        call vec_new
        mov [rsp + 8], rax              # symbolic
        xor r14d, r14d
4:      cmp r14, [r13 + VEC_LEN]
        jae 20f
        mov rax, [r13 + VEC_DATA]
        mov rbx, [rax + r14*8]          # r
        mov rdi, rbx
        call is_int
        test eax, eax
        jz 5f
        mov rdi, [rsp]
        mov rsi, rbx
        call int_add
        mov [rsp], rax
        jmp 19f
5:      # try to merge with a previous symbolic term
        mov qword ptr [rsp + 16], 0     # idx
6:      mov rax, [rsp + 8]
        mov rcx, [rsp + 16]
        cmp rcx, [rax + VEC_LEN]
        jae 18f
        mov rax, [rax + VEC_DATA]
        mov r12, [rax + rcx*8]          # rr
        mov rdi, rbx
        mov rsi, r12
        call alg_try_add
        test rax, rax
        jz 7f
        cmp rax, 1                      # a result of 0 is falsy
        jne 8f
7:      mov rdi, r12
        mov rsi, rbx
        call alg_try_add
        test rax, rax
        jz 17f
        cmp rax, 1
        je 17f
8:      mov [rsp + 24], rax             # tried
        mov rdi, rax
        call opcode_of
        cmp eax, OP_MUL
        jne 9f
        # symbolic[idx] = tried
        mov rax, [rsp + 8]
        mov rax, [rax + VEC_DATA]
        mov rcx, [rsp + 16]
        mov rdx, [rsp + 24]
        mov [rax + rcx*8], rdx
        jmp 19f
9:      mov rdi, [rsp + 24]
        mov esi, OP_MASK_SHL
        mov edx, 5
        call is_op_n
        test eax, eax
        jz 10f
        mov rax, [rsp + 24]
        mov rdi, [rax + N_DATA + 8]     # size
        call is_int
        test eax, eax
        jz 10f
        mov rax, [rsp + 24]
        cmp qword ptr [rax + N_DATA + 16], 1   # offset == 0
        jne 10f
        # assert osize == 256 - size
        mov edi, 513
        mov rsi, [rax + N_DATA + 8]
        call int_sub
        mov rdi, rax
        mov rax, [rsp + 24]
        mov rsi, [rax + N_DATA + 24]
        call py_equal
        test eax, eax
        jz .Lao_assert
        # symbolic[idx] = ("mul", 2**osize, val)
        mov rax, [rsp + 24]
        mov rdi, [rax + N_DATA + 24]    # osize
        call clamp_bits
        mov rdi, rax
        call pow2
        mov rcx, [rsp + 24]
        LOADS rdi, MUL
        mov rsi, rax
        mov rdx, [rcx + N_DATA + 32]
        call mk3
        mov rcx, [rsp + 8]
        mov rcx, [rcx + VEC_DATA]
        mov rdx, [rsp + 16]
        mov [rcx + rdx*8], rax
        jmp 19f
10:     # ("add", num, term): symbolic[idx] = term, real += num (else
        # python's assert fails: e.g. a number)
        mov rdi, [rsp + 24]
        mov esi, OP_ADD
        mov edx, 3
        call is_op_n
        test eax, eax
        jz .Lao_assert
        mov rax, [rsp + 24]
        mov rdi, [rax + N_DATA + 8]
        call is_int
        test eax, eax
        jz .Lao_assert
        mov rax, [rsp + 24]
        mov rdi, [rsp]
        mov rsi, [rax + N_DATA + 8]
        call int_add
        mov [rsp], rax
        mov rax, [rsp + 24]
        mov rdx, [rax + N_DATA + 16]
        mov rcx, [rsp + 8]
        mov rcx, [rcx + VEC_DATA]
        mov rax, [rsp + 16]
        mov [rcx + rax*8], rdx
        jmp 19f
17:     inc qword ptr [rsp + 16]
        jmp 6b
18:     mov rdi, [rsp + 8]
        mov rsi, rbx
        call vec_push
19:     inc r14
        jmp 4b
20:     # drop the terms with a zero coefficient, remove mul 1
        call vec_new
        mov r13, rax
        xor r14d, r14d
21:     mov rax, [rsp + 8]
        cmp r14, [rax + VEC_LEN]
        jae 24f
        mov rax, [rax + VEC_DATA]
        mov rbx, [rax + r14*8]
        # s[1]: a tuple or a list of two or more; a string of two
        # characters or more (s[1] a character: kept as it is); else
        # python's TypeError (a number, None) or IndexError
        test bl, 1
        jnz .Lao_type
        test rbx, rbx
        jz .Lao_type
        mov eax, [rbx + N_KIND]
        cmp eax, K_STR
        je 29f
        cmp eax, K_TUPLE
        je 30f
        cmp eax, K_LIST
        jne .Lao_type
30:     cmp dword ptr [rbx + N_AUX], 2
        jb .Lao_index
        cmp qword ptr [rbx + N_DATA + 8], 1     # s[1] == 0
        je 23f
        mov rdi, rbx
        mov esi, OP_MUL
        mov edx, 3
        call is_op_n
        test eax, eax
        jz 22f
        cmp qword ptr [rbx + N_DATA + 8], 3     # s[1] == 1
        jne 22f
        mov rbx, [rbx + N_DATA + 16]
        jmp 22f
29:     cmp dword ptr [rbx + N_DATA], 2         # a string
        jb .Lao_index
22:     mov rdi, r13
        mov rsi, rbx
        call vec_push
23:     inc r14
        jmp 21b
24:     mov edi, K_TUPLE
        mov rsi, [r13 + VEC_LEN]
        mov rdx, [r13 + VEC_DATA]
        call mk_seq
        mov rdi, [rsp]
        mov rsi, rax
        call mk2
        add rsp, 48
        LEAVE
.Lao_assert:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_ao_assert]
        call err_throw
.Lao_type:
        mov edi, E_TYPE
        lea rsi, [rip + .Ls_ao_type]
        call err_throw
.Lao_index:
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_ao_index]
        call err_throw
ENDF add_op_family

        .section .rodata
.Ls_ao_assert:  .asciz "add_op: try_add gave neither a mul, a mask nor an add of a number"
.Ls_ao_type:    .asciz "add_op: a term is not subscriptable"
.Ls_ao_index:   .asciz "add_op: a term of less than two elements"
        .text

# ---------------------------------------------------------------------
# try_add

        .section .rodata
        .align 8
try_add_ys: .quad 3, 4, 5, 6, 7, 8, 16, 32, 64, 128, 0
        .text

# is_try_add_y(v) -> eax: v is one of try_add_ys (a tagged small int)
FUNC is_try_add_y
        xor eax, eax
        test dil, 1
        jz 2f
        UNTAG rdi
        lea rcx, [rip + try_add_ys]
1:      mov rdx, [rcx]
        test rdx, rdx
        jz 2f
        add rcx, 8
        cmp rdx, rdi
        jne 1b
        mov eax, 1
2:      ret
ENDF is_try_add_y

# is_mul_int(v) -> eax: v ~ ('mul', int, any) (a leaf: only rax is changed)
FUNC is_mul_int
        OP_N_CHECK OP_MUL, 3, 2f
        mov rax, [rdi + N_DATA + 8]
        test al, 1
        jnz 1f
        test rax, rax
        jz 2f
        cmp dword ptr [rax + N_KIND], K_INT
        jne 2f
1:      mov eax, 1
        ret
2:      xor eax, eax
        ret
ENDF is_mul_int

# is_mask_shl_ints(v) -> eax: v ~ ('mask_shl', int, int, int, any)
FUNC is_mask_shl_ints
        OP_N_CHECK OP_MASK_SHL, 5, 2f   # (only rax is changed)
        push rsi
        push rdi
        lea rsi, [rdi + N_DATA + 8]
        mov edi, 3
        call all_ints
        pop rdi
        pop rsi
        ret
2:      xor eax, eax
        ret
ENDF is_mask_shl_ints

# mk_mask_shl(size, offset, shl, val) -> ('mask_shl', size, offset, shl, val)
FUNC mk_mask_shl
        mov r8, rcx
        mov rcx, rdx
        mov rdx, rsi
        mov rsi, rdi
        LOADS rdi, MASK_SHL
        jmp mk5
ENDF mk_mask_shl

# mk_mul(a, b) -> ('mul', a, b)
FUNC mk_mul
        mov rdx, rsi
        mov rsi, rdi
        LOADS rdi, MUL
        jmp mk3
ENDF mk_mul

# alg_try_add(self, other) -> value or NIL
FUNC alg_try_add
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        # (for speed) without a mask_shl in either term, the only rule
        # that can apply is mul(x, exp) + mul(y, exp) -> ('mul', x + y, exp)
        call is_mul_int
        test eax, eax
        jz 2f
        mov rdi, r12
        call is_mul_int
        test eax, eax
        jz 2f
        mov r13, [rbx + N_DATA + 16]    # self[2]
        mov r14, [r12 + N_DATA + 16]    # other[2]
        mov rdi, r13
        OP_N_CHECK OP_MASK_SHL, 5, 21f  # (a mask_shl of five: see try_add_1)
        jmp 2f
21:     mov rdi, r13
        call opcode_of
        cmp eax, OP_MASK_SHL
        je 2f
        mov rdi, r14
        call opcode_of
        cmp eax, OP_MASK_SHL
        je 2f
        mov rdi, r13
        mov rsi, r14
        call values_equal
        test eax, eax
        jz 3f
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, [r12 + N_DATA + 8]
        call int_add
        mov rdi, rax
        mov rsi, r13
        call mk_mul
        LEAVE
2:      # the other rules, memoized by pair (a pure function of the two
        # terms; python recomputes it, as its add_op's cache misses)
        mov edi, MEMO_TRY_ADD
        mov rsi, rbx
        mov rdx, r12
        call memo2_get
        test rax, rax
        jz 4f
        lea rcx, [rip + sp_none]
        cmp rax, rcx
        jne 1f
        xor eax, eax                    # None
        LEAVE
4:      mov rdi, rbx
        mov rsi, r12
        call try_add_1
        test rax, rax
        jnz 5f
        mov rdi, rbx
        mov rsi, r12
        call try_add_2
5:      mov r14, rax
        mov rcx, rax
        test rcx, rcx
        jnz 6f
        lea rcx, [rip + sp_none]
6:      mov edi, MEMO_TRY_ADD
        mov rsi, rbx
        mov rdx, r12
        call memo2_put
        mov rax, r14
1:      LEAVE
3:      xor eax, eax
        LEAVE
ENDF alg_try_add

# try_add_2(self, other): __try_add - _try_add of the terms unshifted
FUNC try_add_2
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov rdi, rbx
        call try_add_norm
        mov rbx, rax
        mov rdi, r12
        call try_add_norm
        mov r12, rax
        mov rdi, rbx
        mov rsi, r12
        call try_add_1
        LEAVE
ENDF try_add_2

# try_add_norm(v): python's _unshift - ('mul', num, ('mask_shl', size, off,
# shl > 0, val)) is num * 2**shl times the mask unshifted, and when no bit of
# it stays under 256 - shl, the mask takes all the bits from off: ('mul',
# num * 2^shl, ('mask_shl', size + shl or size, off, 0, val)). (A num that
# isn't a number: python's tuple times a number, which isn't a term
# _try_add adds: as it is.)
FUNC try_add_norm
        ENTER
        mov rbx, rdi
        mov esi, OP_MUL
        mov edx, 3
        call is_op_n                    # ('mul', num, mask) - num any
        test eax, eax
        jz .Ltn_asis
        mov r12, [rbx + N_DATA + 16]    # the mask_shl
        mov rdi, r12
        call is_mask_shl_ints
        test eax, eax
        jz .Ltn_asis
        mov rdi, [r12 + N_DATA + 24]    # shl
        call int_sign
        cmp eax, 1
        jne .Ltn_asis
        mov rdi, [rbx + N_DATA + 8]
        call vr_number                  # (a bool too)
        test rax, rax
        jz .Ltn_asis
        mov r13, rax
        mov rdi, [r12 + N_DATA + 24]
        call clamp_bits                 # (shl may be a big int)
        mov rdi, rax
        call pow2
        mov rdi, r13
        mov rsi, rax
        call int_mul
        mov r13, rax                    # num * 2^shl
        # off + size + shl >= 256: size + shl, else size
        mov rdi, [r12 + N_DATA + 16]
        mov rsi, [r12 + N_DATA + 8]
        call int_add
        mov rdi, rax
        mov rsi, [r12 + N_DATA + 24]
        call int_add
        mov rdi, rax
        mov esi, (256 << 1) | 1
        call int_cmp
        mov r14, [r12 + N_DATA + 8]
        test eax, eax
        js 1f
        mov rdi, r14
        mov rsi, [r12 + N_DATA + 24]
        call int_add
        mov r14, rax
1:      mov rdi, r14
        mov rsi, [r12 + N_DATA + 16]
        mov edx, 1
        mov rcx, [r12 + N_DATA + 32]
        call mk_mask_shl
        mov rdi, r13
        mov rsi, rax
        call mk_mul
        LEAVE
.Ltn_asis:
        mov rax, rbx
        LEAVE
ENDF try_add_norm

        .section .rodata
.Ls_tn_type: .asciz "TypeError: can only concatenate tuple (not \"int\") to tuple"
        .text

# try_add_1(self, other): _try_add
FUNC try_add_1
        STACK_CHECK
        ENTER
        sub rsp, 48
        mov rbx, rdi                    # self
        mov r12, rsi                    # other
        call is_mul_int
        test eax, eax
        jz .Lta_none
        mov rdi, r12
        call is_mul_int
        test eax, eax
        jz .Lta_none
        mov r13, [rbx + N_DATA + 16]    # self[2]
        mov r14, [r12 + N_DATA + 16]    # other[2]
        # case: self = mul(-1, val), other = mul(mul, mask_shl(256 - shl, 0, shl, val))
        mov rax, -1
        TAG rax
        cmp [rbx + N_DATA + 8], rax
        jne 2f
        mov rdi, r14
        call is_mask_shl_ints
        test eax, eax
        jz 2f
        cmp qword ptr [r14 + N_DATA + 16], 1       # offset 0
        jne 2f
        mov rdi, [r14 + N_DATA + 32]
        mov rsi, r13
        call values_equal
        test eax, eax
        jz 2f
        # other_size == 256 - shl
        mov rdi, [r14 + N_DATA + 8]
        mov rsi, [r14 + N_DATA + 24]
        call int_add
        cmp rax, (256 << 1) | 1
        jne 2f
        # mul * 2**shl * val - val
        mov rdi, [r14 + N_DATA + 24]
        call clamp_bits
        mov rdi, rax
        call pow2
        mov rdi, [r12 + N_DATA + 8]
        mov rsi, rax
        call int_mul
        mov rdi, rax
        mov esi, 3
        call int_sub
        mov rdi, rax
        mov rsi, r13
        call alg_mul2
        add rsp, 48
        LEAVE
2:      # case: mul(x, exp) + mul(y, exp) -> ('mul', x + y, exp)
        mov rdi, r13
        mov rsi, r14
        call values_equal
        test eax, eax
        jz 3f
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, [r12 + N_DATA + 8]
        call int_add
        mov rdi, rax
        mov rsi, r13
        call mk_mul
        add rsp, 48
        LEAVE
3:      # case: mul(x, mask_shl(256-y, y, shl, v)) + mul(x, mask_shl(y, 0, shl, v))
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, [r12 + N_DATA + 8]
        call values_equal
        test eax, eax
        jz 4f
        mov rdi, r13
        mov esi, OP_MASK_SHL
        mov edx, 5
        call is_op_n
        test eax, eax
        jz 4f
        mov rdi, r14
        mov esi, OP_MASK_SHL
        mov edx, 5
        call is_op_n
        test eax, eax
        jz 4f
        mov rdi, [r13 + N_DATA + 8]
        call is_int
        test eax, eax
        jz 4f
        mov rdi, [r13 + N_DATA + 16]
        call is_int
        test eax, eax
        jz 4f
        mov rdi, [r13 + N_DATA + 8]
        mov rsi, [r13 + N_DATA + 16]
        call int_add
        cmp rax, (256 << 1) | 1
        jne 4f
        mov rdi, [r13 + N_DATA + 16]
        mov rsi, [r14 + N_DATA + 8]
        call values_equal
        test eax, eax
        jz 4f
        cmp qword ptr [r14 + N_DATA + 16], 1
        jne 4f
        mov rdi, [r13 + N_DATA + 24]
        mov rsi, [r14 + N_DATA + 24]
        call values_equal
        test eax, eax
        jz 4f
        mov rdi, [r13 + N_DATA + 32]
        mov rsi, [r14 + N_DATA + 32]
        call values_equal
        test eax, eax
        jz 4f
        # mul_op(self[1], mask_op(self_mask[4], 256, 0, shl=self_mask[3]))
        mov rdi, [r13 + N_DATA + 32]
        mov esi, (256 << 1) | 1
        mov edx, 1
        mov rcx, [r13 + N_DATA + 24]
        mov r8d, 1
        call alg_mask_op
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, rax
        call alg_mul2
        add rsp, 48
        LEAVE
4:      # the two "mask_shl vs plain, opposite coefficients" cases
        mov rdi, r13
        call opcode_of
        cmp eax, OP_MASK_SHL
        jne 8f
        mov rdi, r14
        call opcode_of
        cmp eax, OP_MASK_SHL
        je 8f
        mov rdi, [r12 + N_DATA + 8]
        call int_neg
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, rax
        call values_equal
        test eax, eax
        jz 8f
        # python builds, for y in (3, 4, 5, 6, 7, 8, 16, 32, 64, 128),
        # mask_shl(256 - y, y, 0, ('add', 2**y - 1, ('mul', 1, x))) and
        # compares it with self[2]; here self[2] is taken apart instead: a
        # mask_shl(256 - y, y, 0, ...) with y one of those (is_try_add_y)
        cmp dword ptr [r13 + N_AUX], 5
        jne 6f
        mov rax, [r13 + N_DATA + 16]    # y
        mov rdi, rax
        call is_try_add_y
        test eax, eax
        jz 6f
        mov rax, [r13 + N_DATA + 16]
        mov [rsp + 8], rax              # y (tagged)
        cmp qword ptr [r13 + N_DATA + 24], 1   # shl 0
        jne 6f
        mov rcx, (256 << 1) | 1 + 1
        sub rcx, rax                    # 256 - y, tagged
        cmp [r13 + N_DATA + 8], rcx
        jne 6f
        # [4] ~ ('add', 2**y - 1, ('mul', 1, x))
        mov rdi, [r13 + N_DATA + 32]
        mov esi, OP_ADD
        mov edx, 3
        call is_op_n
        test eax, eax
        jz 6f
        mov rax, [r13 + N_DATA + 32]
        mov rdi, [rax + N_DATA + 16]
        mov esi, OP_MUL
        mov edx, 3
        call is_op_n
        test eax, eax
        jz 6f
        mov rax, [r13 + N_DATA + 32]
        mov rax, [rax + N_DATA + 16]    # the mul
        cmp qword ptr [rax + N_DATA + 8], 3    # 1
        jne 6f
        mov rdi, [rax + N_DATA + 16]
        mov rsi, r14
        call values_equal
        test eax, eax
        jz 6f
        mov rdi, [rsp + 8]
        UNTAG rdi
        call pow2
        mov rdi, rax
        mov esi, 3
        call int_sub                    # 2^y - 1
        mov rcx, [r13 + N_DATA + 32]
        mov rdi, [rcx + N_DATA + 8]
        mov rsi, rax
        call values_equal
        test eax, eax
        jz 6f
        # mul_op(self[1], sub_op(2**y, mask_op(x, size=y)))
        mov rdi, r14
        mov rsi, [rsp + 8]
        mov edx, 1
        mov ecx, 1
        mov r8d, 1
        call alg_mask_op
        mov [rsp + 16], rax
        mov rdi, [rsp + 8]
        UNTAG rdi
        call pow2
        mov rdi, rax
        mov rsi, [rsp + 16]
        call alg_sub_op
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, rax
        call alg_mul2
        add rsp, 48
        LEAVE
6:      # second loop: mask_shl(256 - y, y, 0, x)
        cmp dword ptr [r13 + N_AUX], 5
        jne 8f
        mov rax, [r13 + N_DATA + 16]    # y
        mov rdi, rax
        call is_try_add_y
        test eax, eax
        jz 8f
        mov rax, [r13 + N_DATA + 16]
        mov [rsp + 8], rax
        cmp qword ptr [r13 + N_DATA + 24], 1   # shl 0
        jne 8f
        mov rcx, (256 << 1) | 1 + 1
        sub rcx, rax                    # 256 - y, tagged
        cmp [r13 + N_DATA + 8], rcx
        jne 8f
        mov rdi, [r13 + N_DATA + 32]
        mov rsi, r14
        call values_equal
        test eax, eax
        jz 8f
10:     # mul_op(other[1], mask_op(x, size=y))
        mov rdi, r14
        mov rsi, [rsp + 8]
        mov edx, 1
        mov ecx, 1
        mov r8d, 1
        call alg_mask_op
        mov rdi, [r12 + N_DATA + 8]
        mov rsi, rax
        call alg_mul2
        add rsp, 48
        LEAVE
8:      # strip ('mask_shl', 256, 0, 0, exp)
        mov rdi, r13
        call strip_full_mask
        mov r13, rax
        mov rdi, r14
        call strip_full_mask
        mov r14, rax
        # num1, exp1 / num2, exp2
        mov rdi, r13
        mov rsi, r14
        call values_equal
        test eax, eax
        jz 11f
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, [r12 + N_DATA + 8]
        call int_add
        mov rdi, rax
        mov rsi, r13
        call alg_mul2
        add rsp, 48
        LEAVE
11:     # num1 == -num2 ?
        mov rdi, [r12 + N_DATA + 8]
        call int_neg
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, rax
        call values_equal
        test eax, eax
        jz .Lta_none
        # exp2 ~ mask_shl(int size, 0, 0, exp1) -> ('mul', num1, mask_shl(256 - size, size, 0, exp1))
        mov rdi, r14
        mov esi, OP_MASK_SHL
        mov edx, 5
        call is_op_n
        test eax, eax
        jz 12f
        mov rdi, [r14 + N_DATA + 8]
        call is_int
        test eax, eax
        jz 12f
        cmp qword ptr [r14 + N_DATA + 16], 1
        jne 12f
        cmp qword ptr [r14 + N_DATA + 24], 1
        jne 12f
        mov rdi, [r14 + N_DATA + 32]
        mov rsi, r13
        call values_equal
        test eax, eax
        jz 12f
        mov edi, (256 << 1) | 1
        mov rsi, [r14 + N_DATA + 8]
        call int_sub
        mov rdi, rax
        mov rsi, [r14 + N_DATA + 8]
        mov edx, 1
        mov rcx, r13
        call mk_mask_shl
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, rax
        call mk_mul
        add rsp, 48
        LEAVE
12:     # exp1 ~ mask_shl(size1, 0, 0, x), exp2 ~ mask_shl(size2, 0, 0, x), size2 < size1
        mov rdi, r13
        mov esi, OP_MASK_SHL
        mov edx, 5
        call is_op_n
        test eax, eax
        jz .Lta_none
        mov rdi, r14
        mov esi, OP_MASK_SHL
        mov edx, 5
        call is_op_n
        test eax, eax
        jz .Lta_none
        mov rdi, [r13 + N_DATA + 8]
        call is_int
        test eax, eax
        jz .Lta_none
        mov rdi, [r14 + N_DATA + 8]
        call is_int
        test eax, eax
        jz .Lta_none
        cmp qword ptr [r13 + N_DATA + 16], 1
        jne .Lta_none
        cmp qword ptr [r13 + N_DATA + 24], 1
        jne .Lta_none
        cmp qword ptr [r14 + N_DATA + 16], 1
        jne .Lta_none
        cmp qword ptr [r14 + N_DATA + 24], 1
        jne .Lta_none
        mov rdi, [r13 + N_DATA + 32]
        mov rsi, [r14 + N_DATA + 32]
        call values_equal
        test eax, eax
        jz .Lta_none
        mov rdi, [r14 + N_DATA + 8]
        mov rsi, [r13 + N_DATA + 8]
        call int_cmp
        cmp eax, -1
        jne .Lta_none
        # the bits [size2, size1) of x
        mov rdi, [r13 + N_DATA + 8]
        mov rsi, [r14 + N_DATA + 8]
        call int_sub
        mov rdi, rax
        mov rsi, [r14 + N_DATA + 8]
        mov edx, 1
        mov rcx, [r13 + N_DATA + 32]
        call mk_mask_shl
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, rax
        call mk_mul
        add rsp, 48
        LEAVE
.Lta_none:
        xor eax, eax
        add rsp, 48
        LEAVE
ENDF try_add_1

# strip_full_mask(v): ('mask_shl', 256, 0, 0, exp) -> exp
FUNC strip_full_mask
        ENTER
        mov rbx, rdi
        mov esi, OP_MASK_SHL
        mov edx, 5
        call is_op_n
        test eax, eax
        jz 1f
        cmp qword ptr [rbx + N_DATA + 8], (256 << 1) | 1
        jne 1f
        cmp qword ptr [rbx + N_DATA + 16], 1
        jne 1f
        cmp qword ptr [rbx + N_DATA + 24], 1
        jne 1f
        mov rax, [rbx + N_DATA + 32]
        LEAVE
1:      mov rax, rbx
        LEAVE
ENDF strip_full_mask

# ---------------------------------------------------------------------
# mask_op

# alg_mask_op(exp, size, offset, shl, shr) -> value, memoized
FUNC alg_mask_op
        STACK_CHECK
        ENTER
        sub rsp, 64
        mov [rsp], rdi                  # exp
        mov [rsp + 8], rsi              # size
        mov [rsp + 16], rdx             # offset
        mov [rsp + 24], rcx             # shl
        mov [rsp + 32], r8              # shr
        mov rdi, rsi
        mov esi, 1
        call py_equal
        test eax, eax
        jz 1f
        mov eax, 1
        add rsp, 64
        LEAVE
1:      # key = (size, offset, shl, shr, exp)
        mov rdi, [rsp + 8]
        mov rsi, [rsp + 16]
        mov rdx, [rsp + 24]
        mov rcx, [rsp + 32]
        mov r8, [rsp]
        call mk5
        mov [rsp + 40], rax
        mov edi, MEMO_MASK
        mov rsi, rax
        call memo_get
        test rax, rax
        jz 2f
        add rsp, 64
        LEAVE
2:      mov rdi, [rsp]
        mov rsi, [rsp + 8]
        mov rdx, [rsp + 16]
        mov rcx, [rsp + 24]
        mov r8, [rsp + 32]
        call mask_op_impl
        mov [rsp + 48], rax
        mov edi, MEMO_MASK
        mov rsi, [rsp + 40]
        mov rdx, rax
        call memo_put
        mov rax, [rsp + 48]
        add rsp, 64
        LEAVE
ENDF alg_mask_op

# mask_op_impl(exp, size, offset, shl, shr) -> value (python's _mask_op)
FUNC mask_op_impl
        STACK_CHECK
        ENTER
        sub rsp, 64
        mov rbx, rdi                    # exp
        mov r12, rsi                    # size
        mov r13, rdx                    # offset
        mov [rsp + 32], r8              # shr
        mov [rsp + 40], rcx             # shl
        mov esi, 1                      # exp == 0 (False too): 0
        call py_equal
        test eax, eax
        jnz 9f
        # ('div', num, 1) -> num
        mov rdi, rbx
        mov esi, OP_DIV
        mov edx, 3
        call is_op_n
        test eax, eax
        jz 1f
        cmp qword ptr [rbx + N_DATA + 16], 3
        jne 1f
        mov rbx, [rbx + N_DATA + 8]
1:      # shl = sub_op(shl, shr); shr = 0
        mov rdi, [rsp + 40]
        mov rsi, [rsp + 32]
        call alg_sub_op
        mov r14, rax                    # shl
        # a bool (0 or 1), with a mask of numbers: kept or dropped
        mov rdi, rbx
        call opcode_of
        mov edi, eax
        call is_bool_op
        test eax, eax
        jz 11f
        mov [rsp], r12
        mov [rsp + 8], r13
        mov [rsp + 16], r14
        mov edi, 3
        mov rsi, rsp
        call all_ints
        test eax, eax
        jz 11f
        mov rdi, r13
        call int_sign
        cmp eax, 1
        je 9f                           # offset > 0: 0
        mov rdi, r12
        call int_sign
        cmp eax, 0
        jle 9f                          # size <= 0: 0
        cmp r14, 1
        jne 11f
        mov rax, rbx                    # shl == 0: as it is
        add rsp, 64
        LEAVE
11:     # storage
        mov rdi, rbx
        mov esi, OP_STORAGE
        mov edx, 4
        call is_op_n
        test eax, eax
        jz .Lmo_not_storage
        # a field moved left (see apply_mask_to_storage): a mask of the
        # field, moved
        mov rdi, [rbx + N_DATA + 16]
        call vr_number                  # (":int:", a bool too)
        test rax, rax
        jz 12f
        mov rdi, rax
        call int_sign
        test eax, eax
        jns 12f
        LOADS rdi, STORAGE
        mov rsi, [rbx + N_DATA + 8]
        mov edx, 1
        mov rcx, [rbx + N_DATA + 24]
        call mk4
        mov [rsp], rax                  # the field
        mov rdi, [rbx + N_DATA + 16]
        call int_neg
        mov rdi, [rbx + N_DATA + 8]
        mov esi, 1
        mov rdx, rax
        mov rcx, [rsp]
        call mk_mask_shl
        mov rdi, rax
        mov rsi, r12
        mov rdx, r13
        mov rcx, r14
        mov r8d, 1
        call alg_mask_op
        add rsp, 64
        LEAVE
12:     # trimming the storage inside
        test r14b, 1
        jz 3f                           # symbolic shl
        mov rax, r14
        sar rax, 1
        cmp rax, 0
        jle 3f
        cmp rax, 8
        jl .Lmo_not_storage             # 0 < shl < 8: pass
        # shl >= 8 and size == 256
        cmp r12, (256 << 1) | 1
        jne 3f
        mov rdi, rbx
        mov esi, (256 << 1) | 1
        sub rsi, r14
        inc rsi                         # tagged 256 - shl
        mov rdx, r13
        mov rcx, r14
        call apply_mask_to_storage
        test rax, rax                   # (None: the next one; 0 is a result)
        jz 3f
        add rsp, 64
        LEAVE
3:      mov rdi, rbx
        mov rsi, r12
        mov rdx, r13
        mov rcx, r14
        call apply_mask_to_storage
        test rax, rax
        jz .Lmo_not_storage
        add rsp, 64
        LEAVE
.Lmo_not_storage:
        mov rdi, rbx
        call opcode_of
        cmp eax, OP_OR
        jne 5f
        # or_op(*[mask_op(e, size, offset, shl, 0) for e in exp[1:]])
        mov eax, [rbx + N_AUX]
        dec eax
        mov [rsp], rax                  # n
        lea rdi, [rax*8 + 8]
        call arena_alloc
        mov [rsp + 8], rax
        xor ecx, ecx
4:      cmp rcx, [rsp]
        jae 6f
        mov [rsp + 16], rcx
        mov rdi, [rbx + N_DATA + 8 + rcx*8]
        mov rsi, r12
        mov rdx, r13
        mov rcx, r14
        mov r8d, 1
        call alg_mask_op
        mov rcx, [rsp + 16]
        mov rdx, [rsp + 8]
        mov [rdx + rcx*8], rax
        inc rcx
        jmp 4b
6:      mov rdi, [rsp]
        mov rsi, [rsp + 8]
        call alg_or_n
        add rsp, 64
        LEAVE
5:      cmp eax, OP_SIGNEXTEND
        jne 51f
        # the bits signextend doesn't change: ('signextend', int b, val) with
        # offset + size <= 8 * (b + 1), numbers
        cmp dword ptr [rbx + N_AUX], 3
        jne 7f
        mov rdi, [rbx + N_DATA + 8]
        call vr_number
        test rax, rax
        jz 7f
        mov [rsp + 24], rax             # b
        mov [rsp], r12
        mov [rsp + 8], r13
        mov edi, 2
        mov rsi, rsp
        call all_ints
        test eax, eax
        jz 7f
        mov rdi, r13
        mov rsi, r12
        call int_add
        mov [rsp + 16], rax
        mov rdi, [rsp + 24]
        mov esi, 3
        call int_add
        mov rdi, rax
        mov esi, (8 << 1) | 1
        call int_mul
        mov rdi, [rsp + 16]
        mov rsi, rax
        call int_cmp
        cmp eax, 0
        jg 7f
        mov rdi, [rbx + N_DATA + 16]
        mov rsi, r12
        mov rdx, r13
        mov rcx, r14
        mov r8d, 1
        call alg_mask_op
        add rsp, 64
        LEAVE
51:     cmp eax, OP_MASK_SHL
        jne 7f
        cmp dword ptr [rbx + N_AUX], 5
        jne 7f
        # mask_mask_op(size, offset, shl, exp_size, exp_offset, exp_shl, exp)
        mov [rsp], r12
        mov [rsp + 8], r13
        mov [rsp + 16], r14
        mov rax, [rbx + N_DATA + 8]
        mov [rsp + 24], rax
        mov rax, [rbx + N_DATA + 16]
        mov [rsp + 32], rax
        mov rax, [rbx + N_DATA + 24]
        mov [rsp + 40], rax
        mov rax, [rbx + N_DATA + 32]
        mov [rsp + 48], rax
        mov rdi, rsp
        call mask_mask_op
        add rsp, 64
        LEAVE
7:      # size symbolic or > 0: ('mask_shl', size, offset, shl, exp), else 0
        mov rdi, r12
        call is_int
        test eax, eax
        jz 8f
        mov rdi, r12
        call int_sign
        cmp eax, 1
        jne 9f
8:      mov rdi, r12
        mov rsi, r13
        mov rdx, r14
        mov rcx, rbx
        call mk_mask_shl
        add rsp, 64
        LEAVE
9:      mov eax, 1
        add rsp, 64
        LEAVE
ENDF mask_op_impl

# apply_mask_to_storage(exp, size, offset, shl) -> value, or NIL (python's
# None: the mask has to stay)
FUNC apply_mask_to_storage
        STACK_CHECK
        ENTER
        sub rsp, 32
        mov rbx, rdi                    # ('storage', stor_size, stor_offset, stor_idx)
        mov r12, rsi                    # size
        mov r13, rdx                    # offset
        mov r14, rcx                    # shl
        # stor_offset = add_op(stor_offset, offset)
        mov rdi, [rbx + N_DATA + 16]
        mov rsi, r13
        call alg_add2
        mov [rsp], rax
        # stor_size = sub_op(stor_size, offset)
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, r13
        call alg_sub_op
        mov [rsp + 8], rax
        # shl = add_op(shl, offset)
        mov rdi, r14
        mov rsi, r13
        call alg_add2
        mov r14, rax
        # the narrower of the two - unless which one isn't known (uint8 of
        # a field of 256 - 8 * i bits): None
        mov rdi, r12
        mov rsi, [rsp + 8]
        call alg_safe_le_op
        cmp eax, TRI_TRUE
        jne 1f
        mov [rsp + 8], r12
        jmp 2f
1:      mov rdi, [rsp + 8]
        mov rsi, r12
        call alg_safe_le_op
        cmp eax, TRI_TRUE
        jne .Lams_none
2:      # if safe_le_op(stor_size, 0) is True: return 0
        mov rdi, [rsp + 8]
        mov esi, 1
        call alg_safe_le_op
        cmp eax, TRI_TRUE
        jne 3f
        mov eax, 1
        add rsp, 32
        LEAVE
3:      # res = ('storage', stor_size, stor_offset, stor_idx)
        LOADS rdi, STORAGE
        mov rsi, [rsp + 8]
        mov rdx, [rsp]
        mov rcx, [rbx + N_DATA + 24]
        call mk4
        mov [rsp + 16], rax
        mov rdi, r14
        mov esi, 1
        call py_equal
        test eax, eax
        jz 4f
        mov rax, [rsp + 16]             # shl == 0: res
        add rsp, 32
        LEAVE
4:      mov rdi, r14                    # (moved by a number of bits known only)
        call is_int
        test eax, eax
        jz .Lams_none
        mov rdi, r14
        call int_sign
        test eax, eax
        jns 6f
        # moved right: its bits from -shl on, at 0
        mov rdi, [rsp + 8]
        mov rsi, r14
        call alg_add2
        mov [rsp + 24], rax             # new_size
        mov rdi, rax
        call is_int
        test eax, eax
        jz .Lams_none
        mov rdi, [rsp + 24]
        call int_sign
        cmp eax, 0
        jg 5f
        mov eax, 1                      # new_size <= 0: 0
        add rsp, 32
        LEAVE
5:      mov rdi, r14
        call int_neg
        mov rdi, [rsp]
        mov rsi, rax
        call alg_add2
        LOADS rdi, STORAGE
        mov rsi, [rsp + 24]
        mov rdx, rax
        mov rcx, [rbx + N_DATA + 24]
        call mk4
        add rsp, 32
        LEAVE
6:      # a field moved left (see mask_op_impl): res ~ ('storage', size, 0,
        # stor_idx) -> ('storage', size, -shl, stor_idx)
        mov rdi, [rsp + 8]
        mov rsi, r12
        call py_equal
        test eax, eax
        jz .Lams_none
        mov rdi, [rsp]
        mov esi, 1
        call py_equal
        test eax, eax
        jz .Lams_none
        mov rdi, r14
        call int_neg
        LOADS rdi, STORAGE
        mov rsi, r12
        mov rdx, rax
        mov rcx, [rbx + N_DATA + 24]
        call mk4
        add rsp, 32
        LEAVE
.Lams_none:
        xor eax, eax
        add rsp, 32
        LEAVE
ENDF apply_mask_to_storage

# mask_mask_op(params): params -> size, offset, shl, exp_size, exp_offset,
# exp_shl, exp (7 words)
.set MM_SIZE, 0
.set MM_OFFSET, 8
.set MM_SHL, 16
.set MM_ESIZE, 24
.set MM_EOFFSET, 32
.set MM_ESHL, 40
.set MM_EXP, 48

FUNC mask_mask_op
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov edi, 6
        mov rsi, rbx
        call all_ints
        test eax, eax
        jz 1f
        mov rdi, rbx
        call strategy_concrete
        LEAVE
1:      # two masks that can be printed as they are: as far as it's proven
        mov rdi, [rbx + MM_SIZE]
        mov rsi, [rbx + MM_OFFSET]
        mov rdx, [rbx + MM_SHL]
        call readable_mask
        test eax, eax
        jz 10f
        mov rdi, [rbx + MM_ESIZE]
        mov rsi, [rbx + MM_EOFFSET]
        mov rdx, [rbx + MM_ESHL]
        call readable_mask
        test eax, eax
        jz 10f
        mov rdi, rbx
        call strategy_proven
        LEAVE
10:     # strategy_0: 0 if exp == 0
        mov rdi, [rbx + MM_EXP]
        mov esi, 1
        call py_equal
        test eax, eax
        jz 2f
        mov eax, 1
        LEAVE
2:      mov rdi, rbx
        call strategy_1
        test rax, rax
        jnz 9f
        mov rdi, rbx
        call strategy_2
        test rax, rax
        jnz 9f
        mov rdi, rbx
        call strategy_3
        test rax, rax
        jnz 9f
        # strategy_final
        mov rdi, [rbx + MM_ESIZE]
        mov rsi, [rbx + MM_EOFFSET]
        mov rdx, [rbx + MM_ESHL]
        mov rcx, [rbx + MM_EXP]
        call mk_mask_shl
        mov rdi, [rbx + MM_SIZE]
        mov rsi, [rbx + MM_OFFSET]
        mov rdx, [rbx + MM_SHL]
        mov rcx, rax
        call mk_mask_shl
9:      LEAVE
ENDF mask_mask_op

# strategy_proven(params) -> value: python's strategy_proven - a mask of a
# mask, as strategy_1 does it, but only as far as it's proven (value_range),
# and when what it makes can be printed as it is (readable_mask): else it
# stays a mask of a mask
FUNC strategy_proven
        STACK_CHECK
        ENTER
        sub rsp, 80
        .set SP_IR, 0                   # inner_right: where the inner mask's bits end up
        .set SP_IL, 8                   # inner_left
        .set SP_OL, 16                  # outer_left: the bits the outer one keeps
        .set SP_CANDS, 24               # three candidates
        .set SP_LEFT, 48
        .set SP_FINAL, 56
        .set SP_NSIZE, 64
        .set SP_NOFF, 72                # (after SP_NSIZE: all_ints of the two)
        mov rbx, rdi
        mov rdi, [rbx + MM_EOFFSET]
        mov rsi, [rbx + MM_ESHL]
        call alg_add2
        mov [rsp + SP_IR], rax
        mov rdi, [rbx + MM_EOFFSET]
        mov rsi, [rbx + MM_ESIZE]
        mov rdx, [rbx + MM_ESHL]
        call alg_add3
        mov [rsp + SP_IL], rax
        mov rdi, [rbx + MM_OFFSET]
        mov rsi, [rbx + MM_SIZE]
        call alg_add2
        mov [rsp + SP_OL], rax
        # no bit of the inner mask kept: 0
        mov rdi, [rsp + SP_IL]
        mov rsi, [rsp + SP_IR]
        call proven_le
        test eax, eax
        jnz .Lsp_zero
        mov rdi, [rsp + SP_IL]
        mov rsi, [rbx + MM_OFFSET]
        call proven_le
        test eax, eax
        jnz .Lsp_zero
        mov rdi, [rsp + SP_OL]
        mov rsi, [rsp + SP_IR]
        call proven_le
        test eax, eax
        jnz .Lsp_zero
        mov rdi, [rsp + SP_IL]
        mov esi, 1
        call proven_le
        test eax, eax
        jnz .Lsp_zero
        mov edi, (256 << 1) | 1
        mov rsi, [rsp + SP_IR]
        call proven_le
        test eax, eax
        jnz .Lsp_zero
        # (strategy_final's)
        mov rdi, [rbx + MM_ESIZE]
        mov rsi, [rbx + MM_EOFFSET]
        mov rdx, [rbx + MM_ESHL]
        mov rcx, [rbx + MM_EXP]
        call mk_mask_shl
        mov rdi, [rbx + MM_SIZE]
        mov rsi, [rbx + MM_OFFSET]
        mov rdx, [rbx + MM_SHL]
        mov rcx, rax
        call mk_mask_shl
        mov [rsp + SP_FINAL], rax
        # left: the one of outer_left, inner_left, 256 proven the lowest
        mov rax, [rsp + SP_OL]
        mov [rsp + SP_CANDS], rax
        mov rax, [rsp + SP_IL]
        mov [rsp + SP_CANDS + 8], rax
        mov qword ptr [rsp + SP_CANDS + 16], (256 << 1) | 1
        lea rdi, [rsp + SP_CANDS]
        xor esi, esi
        call proven_pick
        test rax, rax
        jz .Lsp_final
        mov [rsp + SP_LEFT], rax
        # right: the one of outer_right, inner_right, 0 proven the highest
        mov rax, [rbx + MM_OFFSET]
        mov [rsp + SP_CANDS], rax
        mov rax, [rsp + SP_IR]
        mov [rsp + SP_CANDS + 8], rax
        mov qword ptr [rsp + SP_CANDS + 16], 1
        lea rdi, [rsp + SP_CANDS]
        mov esi, 1
        call proven_pick
        test rax, rax
        jz .Lsp_final
        mov r12, rax                    # right
        mov rdi, [rsp + SP_LEFT]
        mov rsi, r12
        call alg_sub_op
        mov [rsp + SP_NSIZE], rax
        mov rdi, r12
        mov rsi, [rbx + MM_ESHL]
        call alg_sub_op
        mov [rsp + SP_NOFF], rax
        mov rdi, [rsp + SP_NSIZE]
        mov esi, 1
        call proven_le
        test eax, eax
        jnz .Lsp_zero
        mov rdi, [rsp + SP_NSIZE]
        xor esi, esi
        call is_word
        test eax, eax
        jz .Lsp_final
        # a size or an offset made of a shift (uint8(x << n), 2 * (1 << n)):
        # the two masks read better
        mov edi, 2
        lea rsi, [rsp + SP_NSIZE]
        call all_ints
        test eax, eax
        jnz 1f
        mov edi, 2
        lea rsi, [rbx + MM_SIZE]        # size, offset
        call all_ints
        test eax, eax
        jz 1f
        mov edi, 2
        lea rsi, [rbx + MM_ESIZE]       # exp_size, exp_offset
        call all_ints
        test eax, eax
        jnz .Lsp_final
1:      mov rdi, [rbx + MM_SHL]
        mov rsi, [rbx + MM_ESHL]
        call alg_add2
        mov rcx, rax
        mov rdi, [rbx + MM_EXP]
        mov rsi, [rsp + SP_NSIZE]
        mov rdx, [rsp + SP_NOFF]
        mov r8d, 1
        call alg_mask_op
        mov r12, rax
        mov rdi, rax
        call opcode_of
        cmp eax, OP_MASK_SHL
        jne 2f
        cmp dword ptr [r12 + N_AUX], 4
        jb 2f
        mov rdi, [r12 + N_DATA + 8]
        mov rsi, [r12 + N_DATA + 16]
        mov rdx, [r12 + N_DATA + 24]
        call readable_mask
        test eax, eax
        jz .Lsp_final
2:      mov rax, r12
        add rsp, 80
        LEAVE
.Lsp_final:
        mov rax, [rsp + SP_FINAL]
        add rsp, 80
        LEAVE
.Lsp_zero:
        mov eax, 1
        add rsp, 80
        LEAVE
ENDF strategy_proven

# proven_pick(cands, flip) -> rax: python's _proven_pick of three
# candidates - the first one proven to come first (proven_le(c, o), or
# proven_le(o, c) when flip) to each of the others it isn't equal to - or
# NIL
FUNC proven_pick
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12d, esi
        xor r13d, r13d                  # c
1:      cmp r13d, 3
        jae 8f
        xor r14d, r14d                  # o
2:      cmp r14d, 3
        jae 7f
        mov rdi, [rbx + r13*8]
        mov rsi, [rbx + r14*8]
        call py_equal
        test eax, eax
        jnz 3f
        mov rdi, [rbx + r13*8]
        mov rsi, [rbx + r14*8]
        test r12d, r12d
        jz 4f
        xchg rdi, rsi
4:      call proven_le
        test eax, eax
        jz 5f
3:      inc r14d
        jmp 2b
5:      inc r13d
        jmp 1b
7:      mov rax, [rbx + r13*8]
        LEAVE
8:      xor eax, eax
        LEAVE
ENDF proven_pick

# strategy_concrete(params) -> value (all ints). The six in [-2^59, 2^59),
# in registers (the results stay small ints); else strategy_concrete_big.
FUNC strategy_concrete
        STACK_CHECK
        ENTER
        sub rsp, 16
        mov rbx, rdi
        xor ecx, ecx
        mov rdx, 1 << 59
        mov rsi, 1 << 60
0:      mov rax, [rbx + rcx*8]
        test al, 1
        jz 1f                           # a big int
        sar rax, 1
        add rax, rdx
        cmp rax, rsi
        jae 1f                          # out of [-2^59, 2^59)
        inc ecx
        cmp ecx, 6
        jb 0b
        jmp 2f
1:      mov rdi, rbx
        call strategy_concrete_big
        add rsp, 16
        LEAVE
2:      mov rdi, [rbx + MM_OFFSET]
        sar rdi, 1
        mov rsi, [rbx + MM_SIZE]
        sar rsi, 1
        lea r12, [rdi + rsi]            # outer_left
        mov r13, rdi                    # outer_right
        mov rdi, [rbx + MM_EOFFSET]
        sar rdi, 1
        mov rsi, [rbx + MM_ESIZE]
        sar rsi, 1
        mov rdx, [rbx + MM_ESHL]
        sar rdx, 1
        lea r14, [rdi + rsi]
        add r14, rdx                    # inner_left
        lea rcx, [rdi + rdx]            # inner_right
        cmp r14, rcx
        jle .Lsc_zero
        cmp r14, r13
        jle .Lsc_zero
        # left = min(outer_left, inner_left); right = max(outer_right, inner_right)
        mov rax, r12
        cmp r14, rax
        cmovl rax, r14                  # left
        mov rsi, r13
        cmp rcx, rsi
        cmovg rsi, rcx                  # right
        mov rdi, rsi
        sub rdi, rdx                    # new_offset = right - exp_shl
        sub rax, rsi                    # new_size = left - right
        jle .Lsc_zero
        mov rcx, [rbx + MM_SHL]
        sar rcx, 1
        add rcx, rdx                    # new_shl = shl + exp_shl
        # mask_op(exp, new_size, new_offset, new_shl, 0)
        TAG rax
        TAG rdi
        TAG rcx
        mov rsi, rax
        mov rdx, rdi
        mov rdi, [rbx + MM_EXP]
        mov r8d, 1
        call alg_mask_op
        add rsp, 16
        LEAVE
.Lsc_zero:
        mov eax, 1
        add rsp, 16
        LEAVE
ENDF strategy_concrete

# strategy_concrete_big(params) -> value: strategy_concrete with python's
# integers (int_add, int_cmp: big ints, no overflow)
FUNC strategy_concrete_big
        STACK_CHECK
        ENTER
        sub rsp, 48
        .set SB_OUTER_LEFT, 0
        .set SB_INNER_LEFT, 8
        .set SB_INNER_RIGHT, 16
        .set SB_LEFT, 24
        .set SB_RIGHT, 32
        mov rbx, rdi
        mov rdi, [rbx + MM_OFFSET]
        mov rsi, [rbx + MM_SIZE]
        call int_add
        mov [rsp + SB_OUTER_LEFT], rax
        mov rdi, [rbx + MM_EOFFSET]
        mov rsi, [rbx + MM_ESIZE]
        call int_add
        mov rdi, rax
        mov rsi, [rbx + MM_ESHL]
        call int_add
        mov [rsp + SB_INNER_LEFT], rax
        mov rdi, [rbx + MM_EOFFSET]
        mov rsi, [rbx + MM_ESHL]
        call int_add
        mov [rsp + SB_INNER_RIGHT], rax
        # inner_left <= inner_right, inner_left <= outer_right: 0
        mov rdi, [rsp + SB_INNER_LEFT]
        mov rsi, [rsp + SB_INNER_RIGHT]
        call int_cmp
        cmp eax, 0
        jle .Lsb_zero
        mov rdi, [rsp + SB_INNER_LEFT]
        mov rsi, [rbx + MM_OFFSET]
        call int_cmp
        cmp eax, 0
        jle .Lsb_zero
        # left = min(outer_left, inner_left), right = max(outer_right, inner_right)
        mov rax, [rsp + SB_OUTER_LEFT]
        mov [rsp + SB_LEFT], rax
        mov rdi, [rsp + SB_INNER_LEFT]
        mov rsi, rax
        call int_cmp
        cmp eax, 0
        jge 1f
        mov rax, [rsp + SB_INNER_LEFT]
        mov [rsp + SB_LEFT], rax
1:      mov rax, [rbx + MM_OFFSET]
        mov [rsp + SB_RIGHT], rax
        mov rdi, [rsp + SB_INNER_RIGHT]
        mov rsi, rax
        call int_cmp
        cmp eax, 0
        jle 2f
        mov rax, [rsp + SB_INNER_RIGHT]
        mov [rsp + SB_RIGHT], rax
2:      # new_size = left - right > 0, or 0
        mov rdi, [rsp + SB_LEFT]
        mov rsi, [rsp + SB_RIGHT]
        call int_sub
        mov r12, rax
        mov rdi, rax
        call int_sign
        cmp eax, 0
        jle .Lsb_zero
        mov rdi, [rsp + SB_RIGHT]       # new_offset = right - exp_shl
        mov rsi, [rbx + MM_ESHL]
        call int_sub
        mov r13, rax
        mov rdi, [rbx + MM_SHL]         # new_shl = shl + exp_shl
        mov rsi, [rbx + MM_ESHL]
        call int_add
        mov rcx, rax
        mov rdi, [rbx + MM_EXP]
        mov rsi, r12
        mov rdx, r13
        mov r8d, 1                      # shr 0
        call alg_mask_op
        add rsp, 48
        LEAVE
.Lsb_zero:
        mov eax, 1
        add rsp, 48
        LEAVE
ENDF strategy_concrete_big

# strategy_1(params) -> value or NIL
FUNC strategy_1
        STACK_CHECK
        ENTER
        sub rsp, 64
        mov rbx, rdi
        # outer_left = add_op(offset, size); outer_right = offset
        mov rdi, [rbx + MM_OFFSET]
        mov rsi, [rbx + MM_SIZE]
        call alg_add2
        mov [rsp], rax                  # outer_left
        # inner_left = add_op(exp_offset, exp_size, exp_shl)
        mov rdi, [rbx + MM_EOFFSET]
        mov rsi, [rbx + MM_ESIZE]
        mov rdx, [rbx + MM_ESHL]
        call alg_add3
        mov [rsp + 8], rax              # inner_left
        mov rdi, [rbx + MM_EOFFSET]
        mov rsi, [rbx + MM_ESHL]
        call alg_add2
        mov [rsp + 16], rax             # inner_right
        mov rdi, [rsp]
        mov rsi, [rsp + 8]
        call alg_safe_min_op
        mov [rsp + 24], rax             # left (NIL if unknown)
        mov rdi, [rbx + MM_OFFSET]
        mov rsi, [rsp + 16]
        call alg_safe_max_op
        mov [rsp + 32], rax             # right
        mov rdi, [rsp + 8]
        mov rsi, [rsp + 16]
        call alg_safe_le_op
        cmp eax, TRI_TRUE
        je .Ls1_zero
        mov rdi, [rsp + 8]
        mov rsi, [rbx + MM_OFFSET]
        call alg_safe_le_op
        cmp eax, TRI_TRUE
        je .Ls1_zero
        cmp qword ptr [rsp + 24], 0
        je .Ls1_none
        cmp qword ptr [rsp + 32], 0
        je .Ls1_none
        # new_offset = sub_op(right, exp_shl); new_size = sub_op(left, right); new_shl = add_op(shl, exp_shl)
        mov rdi, [rsp + 32]
        mov rsi, [rbx + MM_ESHL]
        call alg_sub_op
        mov [rsp + 40], rax             # new_offset
        mov rdi, [rsp + 24]
        mov rsi, [rsp + 32]
        call alg_sub_op
        mov [rsp + 48], rax             # new_size
        mov rdi, [rbx + MM_SHL]
        mov rsi, [rbx + MM_ESHL]
        call alg_add2
        mov [rsp + 56], rax             # new_shl
        mov rdi, [rsp + 48]
        call alg_safe_ge_zero
        mov r12d, eax                   # gezero
        mov rdi, [rsp + 48]
        mov esi, 1
        call py_equal
        mov r13d, eax                   # new_size == 0
        cmp r12d, TRI_FALSE
        je 1f
        test r13d, r13d
        jnz 1f
        mov rdi, [rbx + MM_EXP]
        mov rsi, [rsp + 48]
        mov rdx, [rsp + 40]
        mov rcx, [rsp + 56]
        mov r8d, 1
        call alg_mask_op
        add rsp, 64
        LEAVE
1:      cmp r12d, TRI_FALSE
        je .Ls1_zero
        test r13d, r13d
        jnz .Ls1_zero
.Ls1_none:
        xor eax, eax
        add rsp, 64
        LEAVE
.Ls1_zero:
        mov eax, 1
        add rsp, 64
        LEAVE
ENDF strategy_1

# strategy_2: strategy_1(size, offset - exp_size, shl + exp_size, exp_size,
#                        exp_offset, exp_shl - exp_size, exp)
FUNC strategy_2
        STACK_CHECK
        ENTER
        sub rsp, 64
        mov rbx, rdi
        mov rax, [rbx + MM_SIZE]
        mov [rsp + MM_SIZE], rax
        mov rdi, [rbx + MM_OFFSET]
        mov rsi, [rbx + MM_ESIZE]
        call alg_sub_op
        mov [rsp + MM_OFFSET], rax
        mov rdi, [rbx + MM_SHL]
        mov rsi, [rbx + MM_ESIZE]
        call alg_add2
        mov [rsp + MM_SHL], rax
        mov rax, [rbx + MM_ESIZE]
        mov [rsp + MM_ESIZE], rax
        mov rax, [rbx + MM_EOFFSET]
        mov [rsp + MM_EOFFSET], rax
        mov rdi, [rbx + MM_ESHL]
        mov rsi, [rbx + MM_ESIZE]
        call alg_sub_op
        mov [rsp + MM_ESHL], rax
        mov rax, [rbx + MM_EXP]
        mov [rsp + MM_EXP], rax
        mov rdi, rsp
        call strategy_1
        add rsp, 64
        LEAVE
ENDF strategy_2

# strategy_3: strategy_1(size, offset - exp_shl, shl + exp_shl, exp_size,
#                        exp_offset, 0, exp)
FUNC strategy_3
        STACK_CHECK
        ENTER
        sub rsp, 64
        mov rbx, rdi
        mov rax, [rbx + MM_SIZE]
        mov [rsp + MM_SIZE], rax
        mov rdi, [rbx + MM_OFFSET]
        mov rsi, [rbx + MM_ESHL]
        call alg_sub_op
        mov [rsp + MM_OFFSET], rax
        mov rdi, [rbx + MM_SHL]
        mov rsi, [rbx + MM_ESHL]
        call alg_add2
        mov [rsp + MM_SHL], rax
        mov rax, [rbx + MM_ESIZE]
        mov [rsp + MM_ESIZE], rax
        mov rax, [rbx + MM_EOFFSET]
        mov [rsp + MM_EOFFSET], rax
        mov qword ptr [rsp + MM_ESHL], 1
        mov rax, [rbx + MM_EXP]
        mov [rsp + MM_EXP], rax
        mov rdi, rsp
        call strategy_1
        add rsp, 64
        LEAVE
ENDF strategy_3

# alg_neg_mask_op(exp, size, offset) -> value
FUNC alg_neg_mask_op
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        # exp1 = mask_op(exp, size=256 - (size + offset), offset=offset + size)
        mov rdi, r12
        mov rsi, r13
        call alg_add2
        mov r14, rax
        mov edi, (256 << 1) | 1
        mov rsi, rax
        call alg_sub_op
        mov rdi, rbx
        mov rsi, rax
        mov rdx, r14
        mov ecx, 1
        mov r8d, 1
        call alg_mask_op
        mov [rsp], rax
        # exp2 = mask_op(exp, size=offset, offset=0)
        mov rdi, rbx
        mov rsi, r13
        mov edx, 1
        mov ecx, 1
        mov r8d, 1
        call alg_mask_op
        mov rdi, [rsp]
        mov rsi, rax
        call alg_or2
        add rsp, 16
        LEAVE
ENDF alg_neg_mask_op

# alg_div_op(a, b) -> value
FUNC alg_div_op
        ENTER
        mov rbx, rdi
        mov r12, rsi
        cmp r12, 3
        jne 1f
        mov rax, rbx
        LEAVE
1:      mov rdi, rbx
        call is_int
        mov r13d, eax                   # a is int
        mov rdi, r12
        call is_int
        mov r14d, eax                   # b is int
        test r13d, r13d
        jnz 4f
        test r14d, r14d
        jz 4f
        # b < 0: a = -a, b = -b
        mov rdi, r12
        call int_sign
        cmp eax, -1
        jne 2f
        mov rdi, rbx
        call alg_minus_op
        mov rbx, rax
        mov rdi, r12
        call int_neg
        mov r12, rax
        mov rdi, rbx
        call is_int
        mov r13d, eax                   # -a may have folded to an int
2:      mov rdi, r12
        call to_exp2
        cmp rax, -1
        je 4f
        test rax, rax
        jz 4f
        # mask_op(a, size=256 - p, offset=p, shr=p)
        mov rdi, rbx
        mov esi, 256
        sub rsi, rax
        TAG rsi
        mov rdx, rax
        TAG rdx
        mov ecx, 1
        mov r8, rax
        TAG r8
        call alg_mask_op
        LEAVE
4:      test r13d, r13d
        jz 5f
        test r14d, r14d
        jz 5f
        mov rdi, rbx
        mov rsi, r12
        call int_floordiv
        LEAVE
5:      LOADS rdi, DIV
        mov rsi, rbx
        mov rdx, r12
        call mk3
        LEAVE
ENDF alg_div_op

# alg_bits(exp) -> rax: python's bits - the number of bits in exp bytes:
# a sum's terms' bits added up (a size, too small to overflow), a term
# subtracted minus the bits of what's subtracted (not 8 times the word of a
# negative number), else mul_op(exp, 8)
FUNC alg_bits
        STACK_CHECK
        ENTER
        mov rbx, rdi
        call opcode_of
        cmp eax, OP_ADD
        je .Lbits_add
        mov rdi, rbx
        mov esi, OP_MUL
        mov edx, 3
        call is_op_n
        test eax, eax
        jz 9f
        mov rdi, [rbx + N_DATA + 8]
        call is_int
        test eax, eax
        jz 9f
        mov rdi, [rbx + N_DATA + 8]
        call int_sign
        test eax, eax
        jns 9f
        mov rdi, [rbx + N_DATA + 16]
        cmp qword ptr [rbx + N_DATA + 8], -1    # k == -1 (a small int: -1)
        je 1f
        mov rdi, [rbx + N_DATA + 8]
        call int_neg
        mov rdi, rax
        mov rsi, [rbx + N_DATA + 16]
        call alg_mul2
        mov rdi, rax
1:      call alg_bits
        mov rdi, rax
        call alg_minus_op
        LEAVE
9:      mov rdi, rbx
        mov esi, (8 << 1) | 1
        call alg_mul2
        LEAVE
.Lbits_add:
        call vec_new
        mov r12, rax
        mov r13d, 1
2:      cmp r13d, [rbx + N_AUX]
        jae 3f
        mov rdi, [rbx + N_DATA + r13*8]
        inc r13d
        call alg_bits
        mov rdi, r12
        mov rsi, rax
        call vec_push
        jmp 2b
3:      mov rdi, [r12 + VEC_LEN]
        mov rsi, [r12 + VEC_DATA]
        call alg_add_n
        LEAVE
ENDF alg_bits

# ---------------------------------------------------------------------
# comparisons

# tri_to_memo(eax) -> rax memo sentinel ; memo_to_tri(rax) -> eax
FUNC tri_to_memo
        mov eax, MEMO_TRUE
        cmp edi, TRI_TRUE
        je 1f
        mov eax, MEMO_FALSE
        cmp edi, TRI_FALSE
        je 1f
        mov eax, MEMO_NONE
        cmp edi, TRI_NONE
        je 1f
        mov eax, MEMO_CANNOT
1:      ret
ENDF tri_to_memo

FUNC memo_to_tri
        mov eax, TRI_TRUE
        cmp rdi, MEMO_TRUE
        je 1f
        mov eax, TRI_FALSE
        cmp rdi, MEMO_FALSE
        je 1f
        mov eax, TRI_NONE
        cmp rdi, MEMO_NONE
        je 1f
        mov eax, TRI_CANNOT
1:      ret
ENDF memo_to_tri

# contains(exp, sub) -> eax: sub occurs in exp (structurally, any depth)
FUNC contains
        # the mention flags of sub (a string's, or a tuple's: the or of
        # its elements'): a tuple without all of them in its own can't
        # hold it
        xor edx, edx
        test sil, 1
        jnz contains_f
        test rsi, rsi
        jz contains_f
        mov eax, [rsi + N_KIND]
        cmp eax, K_STR
        je 1f
        cmp eax, K_TUPLE
        je 1f
        cmp eax, K_LIST
        jne contains_f
1:      mov rdx, [rsi + N_HASH]
        mov rax, HF_MASK
        and rdx, rax
        jmp contains_f
ENDF contains

# contains_f(exp, sub, flags): python's `exp == sub`, or a tuple or list
# holding it at any depth. (== is values_equal: the same pointer, as
# nodes are hash-consed, or two big ints of the same value.)
FUNC contains_f
        cmp rdi, rsi
        je .Lct_yes_ret
        test dil, 1
        jnz .Lct_no_ret
        test rdi, rdi
        jz .Lct_no_ret
        mov eax, [rdi + N_KIND]
        cmp eax, K_INT
        je values_equal                 # (a big int: == by value)
        sub eax, K_TUPLE
        cmp eax, K_LIST - K_TUPLE
        jbe contains_seq
.Lct_no_ret:
        xor eax, eax
        ret
.Lct_yes_ret:
        mov eax, 1
        ret
ENDF contains_f

# contains_seq(seq, sub, flags) -> eax: sub among the elements of the
# tuple or list, at any depth (the sequence itself isn't sub). Only the
# sequences are recursed into, and only those whose mention flags hold
# all of sub's; the leaves are compared here.
FUNC contains_seq
        mov rax, [rdi + N_HASH]
        and rax, rdx
        cmp rax, rdx
        jne .Lcs_no_ret
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r14, rdx
        xor r13d, r13d
.Lcs_next:
        cmp r13d, [rbx + N_AUX]
        jae .Lcs_no
        mov rdi, [rbx + N_DATA + r13*8]
        inc r13d
        cmp rdi, r12
        je .Lcs_yes
        test dil, 1
        jnz .Lcs_next
        test rdi, rdi
        jz .Lcs_next
        mov eax, [rdi + N_KIND]
        cmp eax, K_INT
        je .Lcs_int
        sub eax, K_TUPLE
        cmp eax, K_LIST - K_TUPLE
        ja .Lcs_next                    # a string: only the same pointer
        mov rax, [rdi + N_HASH]
        and rax, r14
        cmp rax, r14
        jne .Lcs_next
        mov rsi, r12
        mov rdx, r14
        call contains_seq
        test eax, eax
        jz .Lcs_next
.Lcs_yes:
        mov eax, 1
        LEAVE
.Lcs_int:
        mov rsi, r12
        call values_equal
        test eax, eax
        jz .Lcs_next
        mov eax, 1
        LEAVE
.Lcs_no:
        xor eax, eax
        LEAVE
.Lcs_no_ret:
        xor eax, eax
        ret
ENDF contains_seq

# is_array_op(id) -> eax: helpers.is_array
FUNC is_array_op
        xor eax, eax
        cmp edi, OP_COUNT
        ja 1f
        lea rax, [rip + .Lset_array_ops]
        movzx eax, byte ptr [rax + rdi]
1:      ret
ENDF is_array_op

        # helpers.ARRAY_OPCODES
        OPSET_MEMBER array_ops, OP_CALL_DATA
        OPSET_MEMBER array_ops, OP_EXT_CALL_RETURN_DATA
        OPSET_MEMBER array_ops, OP_DELEGATE_RETURN_DATA
        OPSET_MEMBER array_ops, OP_CALLCODE_RETURN_DATA
        OPSET_MEMBER array_ops, OP_STATICCALL_RETURN_DATA
        OPSET_MEMBER array_ops, OP_CODE_DATA
        OPSET_END array_ops, OP_COUNT

# alg_init(): the constants of the algebra, on the global context (r15 at
# rt_init): made once, before any thread asks for them
FUNC alg_init
        ret
ENDF alg_init

# is_mem64(v) -> eax: v == ('mem', ('range', 64, 32)) - read off the
# structure (the strings are the opcodes' own nodes, the numbers small:
# what values_equal would compare by pointer)
FUNC is_mem64
        xor eax, eax
        test dil, 1
        jnz 1f
        test rdi, rdi
        jz 1f
        cmp dword ptr [rdi + N_KIND], K_TUPLE
        jne 1f
        cmp dword ptr [rdi + N_AUX], 2
        jne 1f
        LOADS rcx, MEM
        cmp [rdi + N_DATA], rcx
        jne 1f
        mov rdi, [rdi + N_DATA + 8]
        test dil, 1
        jnz 1f
        test rdi, rdi
        jz 1f
        cmp dword ptr [rdi + N_KIND], K_TUPLE
        jne 1f
        cmp dword ptr [rdi + N_AUX], 3
        jne 1f
        LOADS rcx, RANGE
        cmp [rdi + N_DATA], rcx
        jne 1f
        cmp qword ptr [rdi + N_DATA + 8], (64 << 1) | 1
        jne 1f
        cmp qword ptr [rdi + N_DATA + 16], (32 << 1) | 1
        jne 1f
        mov eax, 1
1:      ret
ENDF is_mem64

# alg_calc_max(exp) -> value
FUNC alg_calc_max
        STACK_CHECK
        ENTER
        mov rbx, rdi
        call is_tuple
        test eax, eax
        jz .Lcmx_asis
        mov r12d, [rbx + N_AUX]
        test r12, r12
        jz .Lcmx_asis
        lea rax, [r12*8 + 8 + 15]       # the elements + one slot for the max
        and rax, -16
        STACK_ALLOC rax
        mov r13, rsp
        mov rax, [rbx + N_DATA]
        mov [r13], rax
        mov r14d, 1
1:      cmp r14, r12
        jae 2f
        mov rdi, [rbx + N_DATA + r14*8]
        call alg_calc_max
        mov [r13 + r14*8], rax
        inc r14
        jmp 1b
2:      mov rdi, rbx
        call opcode_of
        cmp eax, OP_MAX
        jne 4f
        # m = -(2^256), then the max of the terms as long as they are ints
        mov edi, 256
        call pow2
        mov rdi, rax
        call int_neg
        mov [r13 + r12*8], rax
        mov r14d, 1
3:      cmp r14, r12
        jae 5f
        mov rdi, [r13 + r14*8]
        call is_int
        test eax, eax
        jz 4f
        mov rdi, [r13 + r12*8]
        mov rsi, [r13 + r14*8]
        call int_cmp
        cmp eax, -1
        jne 6f
        mov rax, [r13 + r14*8]
        mov [r13 + r12*8], rax
6:      inc r14
        jmp 3b
5:      mov rax, [r13 + r12*8]
        LEAVE_DYN
4:      mov rdi, r12
        mov rsi, r13
        call mk_tuple
        LEAVE_DYN
.Lcmx_asis:
        mov rax, rbx
        LEAVE
ENDF alg_calc_max

# ---------------------------------------------------------------------
# simplify / max

# alg_simplify(exp) -> value (memoized)
FUNC alg_simplify
        STACK_CHECK
        ENTER
        mov rbx, rdi
        call is_tuple
        test eax, eax
        jz .Lsi0_asis
        mov edi, MEMO_SIMPLIFY
        mov rsi, rbx
        call memo_get
        test rax, rax
        jz 1f
        LEAVE
1:      mov rdi, rbx
        call simplify_impl
        mov r12, rax
        mov edi, MEMO_SIMPLIFY
        mov rsi, rbx
        mov rdx, rax
        call memo_put
        mov rax, r12
        LEAVE
.Lsi0_asis:
        mov rax, rbx
        LEAVE
ENDF alg_simplify

FUNC simplify_impl
        STACK_CHECK
        ENTER
        sub rsp, 48
        mov rbx, rdi
        mov rdi, rbx
        OPCODE_OF_RDI
        mov r12d, eax
        JT_SWITCH simplify, OP_COUNT, .Lsi_other
        JT_CASE simplify, OP_MAX, .Lsi_max
        JT_CASE simplify, OP_MASK_SHL, .Lsi_mask
        JT_CASE simplify, OP_ADD, .Lsi_add
        JT_CASE simplify, OP_MUL, .Lsi_mul
        JT_END simplify, OP_COUNT, .Lsi_other
.Lsi_other:
        mov rax, rbx
        add rsp, 48
        LEAVE
.Lsi_max:
        # els = [simplify(e)]; res = -(2^256); res = max_op(res, e) for each,
        # falling back to ('max',) + els on CannotCompare
        mov r13d, [rbx + N_AUX]
        lea rdi, [r13*8]
        call arena_alloc_raw   # (every element written)
        mov r14, rax
        mov rax, [rbx + N_DATA]
        mov [r14], rax
        mov qword ptr [rsp], 1
1:      mov rcx, [rsp]
        cmp rcx, r13
        jae 2f
        mov rdi, [rbx + N_DATA + rcx*8]
        call alg_simplify
        mov rcx, [rsp]
        mov [r14 + rcx*8], rax
        inc rcx
        mov [rsp], rcx
        jmp 1b
2:      mov edi, 256
        call pow2
        mov rdi, rax
        call int_neg
        mov [rsp + 8], rax              # res
        mov qword ptr [rsp], 1
3:      mov rcx, [rsp]
        cmp rcx, r13
        jae 4f
        mov rdi, [rsp + 8]
        mov rsi, [r14 + rcx*8]
        call alg_max_op
        test rax, rax
        jz 5f
        mov [rsp + 8], rax
        inc qword ptr [rsp]
        jmp 3b
4:      mov rax, [rsp + 8]
        add rsp, 48
        LEAVE
5:      mov rdi, r13
        mov rsi, r14
        call mk_tuple
        add rsp, 48
        LEAVE
.Lsi_mask:
        cmp dword ptr [rbx + N_AUX], 5
        jne .Lsi_asis
        mov rdi, [rbx + N_DATA + 8]
        call alg_simplify
        mov [rsp], rax                  # size
        mov rdi, [rbx + N_DATA + 16]
        call alg_simplify
        mov [rsp + 8], rax              # offset
        mov rdi, [rbx + N_DATA + 24]
        call alg_simplify
        mov [rsp + 16], rax             # shl
        mov rdi, [rbx + N_DATA + 32]
        call alg_simplify
        mov [rsp + 24], rax             # val
        mov edi, 4
        mov rsi, rsp
        call all_ints
        test eax, eax
        jz 6f
        mov rdi, [rsp + 24]
        mov rsi, [rsp]
        mov rdx, [rsp + 8]
        mov rcx, [rsp + 16]
        call alg_apply_mask
        add rsp, 48
        LEAVE
6:      cmp qword ptr [rsp], (256 << 1) | 1
        jne .Lsi_asis
        cmp qword ptr [rsp + 8], 1
        jne .Lsi_asis
        cmp qword ptr [rsp + 16], 1
        jne .Lsi_asis
        mov rdi, [rsp + 24]             # (a value from memory may be longer
        call may_be_wide                # than a word: the mask cuts it)
        test eax, eax
        jnz .Lsi_asis
        mov rax, [rsp + 24]
        add rsp, 48
        LEAVE
.Lsi_add:
        mov qword ptr [rsp], 1          # res = 0
        mov r13d, 1
7:      cmp r13d, [rbx + N_AUX]
        jae 8f
        mov rdi, [rbx + N_DATA + r13*8]
        call alg_simplify
        mov rdi, [rsp]
        mov rsi, rax
        call alg_add2
        mov [rsp], rax
        inc r13d
        jmp 7b
8:      mov rax, [rsp]
        add rsp, 48
        LEAVE
.Lsi_mul:
        mov qword ptr [rsp], 3          # res = 1
        mov r13d, 1
9:      cmp r13d, [rbx + N_AUX]
        jae 10f
        mov rdi, [rbx + N_DATA + r13*8]
        call alg_simplify
        mov rdi, [rsp]
        mov rsi, rax
        call alg_mul2
        mov [rsp], rax
        inc r13d
        jmp 9b
10:     mov rax, [rsp]
        add rsp, 48
        LEAVE
.Lsi_asis:
        mov rax, rbx
        add rsp, 48
        LEAVE
ENDF simplify_impl

# alg_simplify_max(exp) -> value: flattens nested max
FUNC alg_simplify_max
        ENTER
        mov rbx, rdi
        call opcode_of
        cmp eax, OP_MAX
        jne .Lsm_asis
        call vec_new
        mov r12, rax
        mov rdi, r12
        LOADS rsi, MAX
        call vec_push
        mov r13d, 1
1:      cmp r13d, [rbx + N_AUX]
        jae 2f
        mov r14, [rbx + N_DATA + r13*8]
        mov rdi, r14
        call opcode_of
        cmp eax, OP_MAX
        jne 3f
        mov rdi, r12
        mov edx, [r14 + N_AUX]
        dec edx
        lea rsi, [r14 + N_DATA + 8]
        call vec_extend
        jmp 4f
3:      mov rdi, r12
        mov rsi, r14
        call vec_push
4:      inc r13d
        jmp 1b
2:      mov rdi, r12
        call vec_to_tuple
        LEAVE
.Lsm_asis:
        mov rax, rbx
        LEAVE
ENDF alg_simplify_max

# alg_max_to_add(exp) -> value
FUNC alg_max_to_add
        STACK_CHECK
        ENTER
        sub rsp, 48
        mov rbx, rdi
        call opcode_of
        cmp eax, OP_MAX
        jne .Lmta_asis
        cmp dword ptr [rbx + N_AUX], 2  # (a max of nothing: its terms are
        jb .Lmta_asis                   # read below, and the count would
        mov r12d, [rbx + N_AUX]         # wrap for an empty tuple)
        dec r12d                        # number of terms
        lea r13, [rbx + N_DATA + 8]     # the terms
        # every term must be an add or an int
        xor r14d, r14d
1:      cmp r14, r12
        jae 2f
        mov rdi, [r13 + r14*8]
        call opcode_of
        cmp eax, OP_ADD
        je 3f
        mov rdi, [r13 + r14*8]
        call is_int
        test eax, eax
        jnz 3f
        mov rdi, rbx
        call alg_simplify_max
        add rsp, 48
        LEAVE
3:      inc r14
        jmp 1b
2:      # an int term e: m = min over terms of (x if int else x[1] if int else 0)
        xor r14d, r14d
4:      cmp r14, r12
        jae 10f
        mov rdi, [r13 + r14*8]
        call is_int
        test eax, eax
        jz 5f
        mov [rsp], r14                  # index of e
        # m
        mov qword ptr [rsp + 8], 0
        xor ecx, ecx
6:      cmp rcx, r12
        jae 9f
        mov [rsp + 16], rcx
        mov rdi, [r13 + rcx*8]
        call term_leading_int
        mov rcx, [rsp + 16]
        cmp qword ptr [rsp + 8], 0
        je 7f
        mov rdi, rax
        mov [rsp + 24], rax
        mov rsi, [rsp + 8]
        call int_cmp
        cmp eax, -1
        mov rax, [rsp + 24]
        jne 8f
7:      mov [rsp + 8], rax
8:      mov rcx, [rsp + 16]
        inc rcx
        jmp 6b
9:      # res = ('max', e - m, sub_op(e2, m) for the other terms) ; ('add', m, res)
        call vec_new
        mov [rsp + 16], rax
        mov rdi, rax
        LOADS rsi, MAX
        call vec_push
        mov rcx, [rsp]
        mov rdi, [r13 + rcx*8]
        mov rsi, [rsp + 8]
        call int_sub
        mov rdi, [rsp + 16]
        mov rsi, rax
        call vec_push
        xor ecx, ecx
11:     cmp rcx, r12
        jae 12f
        mov [rsp + 24], rcx
        mov rdi, [r13 + rcx*8]          # (python: `if e2 != e`, every term equal to e skipped)
        mov rax, [rsp]
        mov rsi, [r13 + rax*8]
        call py_equal
        mov rcx, [rsp + 24]
        test eax, eax
        jnz 13f
        mov rdi, [r13 + rcx*8]
        mov rsi, [rsp + 8]
        call alg_sub_op
        mov rdi, [rsp + 16]
        mov rsi, rax
        call vec_push
        mov rcx, [rsp + 24]
13:     inc rcx
        jmp 11b
12:     mov rdi, [rsp + 16]
        call vec_to_tuple
        LOADS rdi, ADD
        mov rsi, [rsp + 8]
        mov rdx, rax
        call mk3
        add rsp, 48
        LEAVE
5:      inc r14
        jmp 4b
10:     # all terms are adds: m = min of the e[1] (0 if one isn't an int)
        mov edi, 1
        call ten_pow_20
        mov [rsp], rax                  # m
        xor r14d, r14d
14:     cmp r14, r12
        jae 16f
        mov rax, [r13 + r14*8]
        mov rdi, [rax + N_DATA + 8]
        call is_int
        test eax, eax
        jnz 15f
        mov qword ptr [rsp], 1
        jmp 16f
15:     mov rax, [r13 + r14*8]
        mov rdi, [rax + N_DATA + 8]
        mov [rsp + 8], rdi
        mov rsi, [rsp]
        call int_cmp
        cmp eax, -1
        jne 17f
        mov rax, [rsp + 8]
        mov [rsp], rax
17:     inc r14
        jmp 14b
16:     # common = [f for f in first if all(f in e[1:] for e in exp[1:])]
        call vec_new
        mov [rsp + 8], rax              # common
        mov rax, [r13]                  # first
        mov qword ptr [rsp + 16], 0     # index into first (all its elements, head included)
18:     mov rax, [r13]
        mov rcx, [rsp + 16]
        cmp ecx, [rax + N_AUX]
        jae 22f
        mov rdi, [rax + N_DATA + rcx*8] # f
        mov [rsp + 24], rdi
        mov r14d, 1
19:     cmp r14, r12
        jae 21f
        mov rax, [r13 + r14*8]          # e
        mov rdi, [rsp + 24]
        mov rsi, rax
        call term_in_tail
        test eax, eax
        jz 20f
        inc r14
        jmp 19b
21:     mov rdi, [rsp + 8]
        mov rsi, [rsp + 24]
        call vec_push
20:     inc qword ptr [rsp + 16]
        jmp 18b
22:     # a = add_op(m, *common) if common else m
        mov rax, [rsp + 8]
        cmp qword ptr [rax + VEC_LEN], 0
        je 23f
        call vec_new
        mov [rsp + 16], rax
        mov rdi, rax
        mov rsi, [rsp]
        call vec_push
        mov rax, [rsp + 8]
        mov rdi, [rsp + 16]
        mov rsi, [rax + VEC_DATA]
        mov rdx, [rax + VEC_LEN]
        call vec_extend
        mov rax, [rsp + 16]
        mov rdi, [rax + VEC_LEN]
        mov rsi, [rax + VEC_DATA]
        call alg_add_n
        mov [rsp], rax                  # a
23:     # res = [sub_op(e, a) for e in exp]
        call vec_new
        mov [rsp + 8], rax
        mov rdi, rax
        LOADS rsi, MAX
        call vec_push
        xor r14d, r14d
24:     cmp r14, r12
        jae 25f
        mov rdi, [r13 + r14*8]
        mov rsi, [rsp]
        call alg_sub_op
        mov rdi, [rsp + 8]
        mov rsi, rax
        call vec_push
        inc r14
        jmp 24b
25:     mov rdi, [rsp + 8]
        call vec_to_tuple
        mov rdi, rax
        call alg_simplify_max
        mov [rsp + 8], rax
        # ('add',) + prefix + (max,) ; prefix = (a,) if int else a[1:]
        call vec_new
        mov [rsp + 16], rax
        mov rdi, rax
        LOADS rsi, ADD
        call vec_push
        mov rdi, [rsp]
        call is_int
        test eax, eax
        jz 26f
        mov rdi, [rsp + 16]
        mov rsi, [rsp]
        call vec_push
        jmp 27f
26:     mov rdi, [rsp]                  # a[1:]: a tuple's (a string: python's TypeError)
        call is_tuple
        test eax, eax
        jz .Lmta_type
        mov rax, [rsp]
        mov rdi, [rsp + 16]
        mov edx, [rax + N_AUX]
        dec edx
        lea rsi, [rax + N_DATA + 8]
        call vec_extend
27:     mov rdi, [rsp + 16]
        mov rsi, [rsp + 8]
        call vec_push
        mov rdi, [rsp + 16]
        call vec_to_tuple
        add rsp, 48
        LEAVE
.Lmta_asis:
        mov rax, rbx
        add rsp, 48
        LEAVE
.Lmta_type:
        mov edi, E_TYPE
        lea rsi, [rip + .Ls_mta_type]
        call err_throw
ENDF alg_max_to_add

        .section .rodata
.Ls_mta_type: .asciz "can only concatenate tuple (not \"str\") to tuple"
        .text

# term_leading_int(x) -> value: x if int, x[1] if a tuple of len > 1 with an
# int there, else 0
FUNC term_leading_int
        ENTER
        mov rbx, rdi
        call is_int
        test eax, eax
        jz 1f
        mov rax, rbx
        LEAVE
1:      mov rdi, rbx
        call is_tuple
        test eax, eax
        jz 2f
        cmp dword ptr [rbx + N_AUX], 2
        jb 2f
        mov rdi, [rbx + N_DATA + 8]
        call is_int
        test eax, eax
        jz 2f
        mov rax, [rbx + N_DATA + 8]
        LEAVE
2:      mov eax, 1
        LEAVE
ENDF term_leading_int

# term_in_tail(f, e) -> eax: f in e[1:]
FUNC term_in_tail
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13d, 1
1:      cmp r13d, [r12 + N_AUX]
        jae 2f
        mov rdi, rbx
        mov rsi, [r12 + N_DATA + r13*8]
        call py_equal
        test eax, eax
        jnz 3f
        inc r13d
        jmp 1b
2:      xor eax, eax
        LEAVE
3:      mov eax, 1
        LEAVE
ENDF term_in_tail

# ten_pow_20() -> value: 10**20
FUNC ten_pow_20
        ENTER
        lea rdi, [r15 + CTX_MPZ_R]
        mov esi, 10
        mov edx, 20
        call __gmpz_ui_pow_ui@PLT
        call arith_result
        LEAVE
ENDF ten_pow_20

# The comparisons (python's ge_zero, get_sign, lt_op, le_op, max_op,
# min_op and their safe_ forms) are decided by value_range (ranges.s) and
# nothing else: what an expression is as an integer, for any value of what
# it's made of. top: 0 for WORD_TOP, 1 for MEMORY_TOP (the memory
# addresses and sizes: memloc's, the mem_ forms below).

# alg_ge_zero(exp) -> eax: python's ge_zero (WORD_TOP)
FUNC alg_ge_zero
        xor esi, esi
        jmp alg_ge_zero_top
ENDF alg_ge_zero

# alg_ge_zero_top(exp, top) -> eax: python's ge_zero(exp, top) - TRI_TRUE if
# exp >= 0, TRI_FALSE if exp < 0, TRI_CANNOT if that depends
FUNC alg_ge_zero_top
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12d, esi
        call is_int                     # (python's int: a bool's range is its value)
        test eax, eax
        jz 1f
        mov rdi, rbx
        call int_sign
        cmp eax, -1
        setne al
        movzx eax, al
        LEAVE
1:      mov rdi, rbx
        xor esi, esi
        mov edx, r12d
        call value_range
        mov rbx, rdx
        mov rdi, rax
        call int_sign
        test eax, eax
        js 2f
        mov eax, TRI_TRUE               # lo >= 0
        LEAVE
2:      mov rdi, rbx
        call int_sign
        test eax, eax
        jns 3f
        mov eax, TRI_FALSE              # hi < 0
        LEAVE
3:      mov eax, TRI_CANNOT
        LEAVE
ENDF alg_ge_zero_top

# alg_safe_ge_zero(exp) / alg_safe_ge_zero_top(exp, top) -> eax: TRI_TRUE,
# TRI_FALSE or TRI_NONE
FUNC alg_safe_ge_zero
        xor esi, esi
        jmp alg_safe_ge_zero_top
ENDF alg_safe_ge_zero

FUNC alg_safe_ge_zero_top
        STACK_CHECK
        ENTER
        call alg_ge_zero_top
        cmp eax, TRI_CANNOT
        jne 1f
        mov eax, TRI_NONE
1:      LEAVE
ENDF alg_safe_ge_zero_top

# alg_safe_gt_zero(exp) / alg_safe_gt_zero_top(exp, top) -> eax:
# safe_ge_zero(exp - 1, top)
FUNC alg_safe_gt_zero
        xor esi, esi
        jmp alg_safe_gt_zero_top
ENDF alg_safe_gt_zero

FUNC alg_safe_gt_zero_top
        STACK_CHECK
        ENTER
        mov ebx, esi
        mov esi, 3
        call alg_sub_op
        mov rdi, rax
        mov esi, ebx
        call alg_safe_ge_zero_top
        LEAVE
ENDF alg_safe_gt_zero_top

# alg_get_sign(exp) / alg_get_sign_top(exp, top) -> eax: python's get_sign -
# 1 if exp > 0, -1 if exp < 0, 0 if it's 0, SIGN_NONE if that depends
FUNC alg_get_sign
        xor esi, esi
        jmp alg_get_sign_top
ENDF alg_get_sign

FUNC alg_get_sign_top
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12d, esi
        mov esi, 1
        call py_equal                   # exp == 0 (False too)
        test eax, eax
        jz 1f
        xor eax, eax
        LEAVE
1:      mov rdi, rbx
        xor esi, esi
        mov edx, r12d
        call value_range
        mov rbx, rax
        mov r12, rdx
        mov rdi, rax
        call int_sign
        cmp eax, 1
        jne 2f
        LEAVE                           # lo > 0: 1
2:      mov rdi, r12
        call int_sign
        test eax, eax
        jns 3f
        mov eax, -1                     # hi < 0
        LEAVE
3:      cmp rbx, 1                      # lo == hi == 0 (normalized: small)
        jne 4f
        cmp r12, 1
        jne 4f
        xor eax, eax
        LEAVE
4:      mov eax, SIGN_NONE
        LEAVE
ENDF alg_get_sign_top

# alg_lt_op(left, right) / alg_lt_op_top(left, right, top) -> eax: python's
# lt_op - TRI_TRUE if left < right, TRI_FALSE if not, TRI_CANNOT if that
# depends
FUNC alg_lt_op
        xor edx, edx
        jmp alg_lt_op_top
ENDF alg_lt_op

FUNC alg_lt_op_top
        STACK_CHECK
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov r13d, edx
        call is_int
        test eax, eax
        jz 1f
        mov rdi, r12
        call is_int
        test eax, eax
        jz 1f
        mov rdi, rbx
        mov rsi, r12
        call int_cmp
        cmp eax, -1
        sete al
        movzx eax, al
        jmp .Llt_ret
1:      mov rdi, rbx
        call add_max_terms
        mov rbx, rax
        mov rdi, r12
        call add_max_terms
        mov r12, rax
        mov rdi, rbx
        call opcode_of
        cmp eax, OP_MAX
        jne .Llt_right_max
        # below the largest: below all of them (each asked, as python's list)
        xor r14d, r14d                  # bit 0: one not True, bit 1: one False
        mov qword ptr [rsp], 1
2:      mov rax, [rsp]
        cmp eax, [rbx + N_AUX]
        jae 3f
        mov rdi, [rbx + N_DATA + rax*8]
        inc qword ptr [rsp]
        mov rsi, r12
        mov edx, r13d
        call alg_safe_lt_op_top
        cmp eax, TRI_TRUE
        je 2b
        or r14d, 1
        cmp eax, TRI_FALSE
        jne 2b
        or r14d, 2
        jmp 2b
3:      mov eax, TRI_TRUE
        test r14d, r14d
        jz .Llt_ret
        mov eax, TRI_FALSE
        test r14d, 2
        jnz .Llt_ret
        mov eax, TRI_CANNOT
        jmp .Llt_ret
.Llt_right_max:
        mov rdi, r12
        call opcode_of
        cmp eax, OP_MAX
        jne .Llt_range
        # below the largest: below one of them
        xor r14d, r14d                  # bit 0: one True, bit 1: one not False
        mov qword ptr [rsp], 1
4:      mov rax, [rsp]
        cmp eax, [r12 + N_AUX]
        jae 5f
        mov rsi, [r12 + N_DATA + rax*8]
        inc qword ptr [rsp]
        mov rdi, rbx
        mov edx, r13d
        call alg_safe_lt_op_top
        cmp eax, TRI_FALSE
        je 4b
        or r14d, 2
        cmp eax, TRI_TRUE
        jne 4b
        or r14d, 1
        jmp 4b
5:      mov eax, TRI_TRUE
        test r14d, 1
        jnz .Llt_ret
        mov eax, TRI_FALSE
        test r14d, 2
        jz .Llt_ret
        mov eax, TRI_CANNOT
        jmp .Llt_ret
.Llt_range:
        # right - left: above 0, or not
        mov rdi, r12
        mov rsi, rbx
        call alg_sub_op
        mov rdi, rax
        xor esi, esi
        mov edx, r13d
        call value_range
        mov rbx, rdx
        mov rdi, rax
        call int_sign
        mov ecx, eax
        mov eax, TRI_TRUE
        cmp ecx, 1
        je .Llt_ret                     # lo > 0
        mov rdi, rbx
        call int_sign
        mov ecx, eax
        mov eax, TRI_FALSE
        cmp ecx, 0
        jle .Llt_ret                    # hi <= 0
        mov eax, TRI_CANNOT
.Llt_ret:
        add rsp, 16
        LEAVE
ENDF alg_lt_op_top

# add_max_terms(v): ('add', int num, ('max', ...)) -> ('max', add_op(t, num)...)
# or v unchanged
FUNC add_max_terms
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov esi, OP_ADD
        mov edx, 3
        call is_op_n
        test eax, eax
        jz .Lamt_asis
        mov rdi, [rbx + N_DATA + 8]
        call is_int
        test eax, eax
        jz .Lamt_asis
        mov r12, [rbx + N_DATA + 16]
        mov rdi, r12
        call opcode_of
        cmp eax, OP_MAX
        jne .Lamt_asis
        call vec_new
        mov r13, rax
        mov rdi, r13
        LOADS rsi, MAX
        call vec_push
        mov r14d, 1
1:      cmp r14d, [r12 + N_AUX]
        jae 2f
        mov rdi, [r12 + N_DATA + r14*8]
        mov rsi, [rbx + N_DATA + 8]
        call alg_add2
        mov rdi, r13
        mov rsi, rax
        call vec_push
        inc r14d
        jmp 1b
2:      mov rdi, r13
        call vec_to_tuple
        LEAVE
.Lamt_asis:
        mov rax, rbx
        LEAVE
ENDF add_max_terms

# alg_safe_lt_op(left, right) / alg_safe_lt_op_top(left, right, top) -> eax:
# TRI_TRUE, TRI_FALSE or TRI_NONE
FUNC alg_safe_lt_op
        xor edx, edx
        jmp alg_safe_lt_op_top
ENDF alg_safe_lt_op

FUNC alg_safe_lt_op_top
        STACK_CHECK
        ENTER
        call alg_lt_op_top
        cmp eax, TRI_CANNOT
        jne 1f
        mov eax, TRI_NONE
1:      LEAVE
ENDF alg_safe_lt_op_top

# alg_le_op(left, right) / alg_le_op_top(left, right, top) -> eax: python's
# le_op - TRI_TRUE if left <= right, TRI_FALSE if not, TRI_CANNOT if that
# depends (remembered: a table of pairs for each top)
FUNC alg_le_op
        xor edx, edx
        jmp alg_le_op_top
ENDF alg_le_op

FUNC alg_le_op_top
        STACK_CHECK
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov [rsp], rdx                  # top
        mov r13d, MEMO_LE
        mov eax, MEMO_LE_M
        test edx, edx
        cmovnz r13d, eax
        mov edi, r13d
        mov rsi, rbx
        mov rdx, r12
        call memo2_get
        test rax, rax
        jz 1f
        mov rdi, rax
        call memo_to_tri
        add rsp, 16
        LEAVE
1:      mov rdi, rbx
        mov rsi, r12
        mov rdx, [rsp]
        call le_op_impl
        mov r14d, eax
        mov edi, eax
        call tri_to_memo
        mov edi, r13d
        mov rsi, rbx
        mov rdx, r12
        mov rcx, rax
        call memo2_put
        mov eax, r14d
        add rsp, 16
        LEAVE
ENDF alg_le_op_top

FUNC le_op_impl
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13d, edx
        mov rdi, rbx
        call alg_max_to_add
        mov rbx, rax
        mov rdi, r12
        call alg_max_to_add
        mov r12, rax
        mov rdi, rbx
        call is_int
        test eax, eax
        jz 1f
        mov rdi, r12
        call is_int
        test eax, eax
        jz 1f
        mov rdi, rbx
        mov rsi, r12
        call int_cmp
        cmp eax, 1
        setne al
        movzx eax, al
        LEAVE
1:      mov rdi, r12
        mov rsi, rbx
        call alg_sub_op
        mov rdi, rax
        mov esi, r13d
        call alg_ge_zero_top
        LEAVE
ENDF le_op_impl

# alg_safe_le_op(left, right) / alg_safe_le_op_top(left, right, top) -> eax:
# TRI_TRUE, TRI_FALSE or TRI_NONE
FUNC alg_safe_le_op
        STACK_CHECK
        xor edx, edx
        jmp alg_safe_le_op_top
ENDF alg_safe_le_op

FUNC alg_safe_le_op_top
        STACK_CHECK
        ENTER
        call alg_le_op_top
        cmp eax, TRI_CANNOT
        jne 1f
        mov eax, TRI_NONE
1:      LEAVE
ENDF alg_safe_le_op_top

# alg_max_op(left, right) / alg_max_op_top(left, right, top) -> rax: python's
# max_op, or NIL for its CannotCompare (the safe_ form's None)
FUNC alg_max_op
        xor edx, edx
        jmp alg_max_op_top
ENDF alg_max_op

FUNC alg_max_op_top
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13d, edx
        call alg_le_op_top
        cmp eax, TRI_CANNOT
        je 1f
        test eax, eax
        jz 2f
        mov rax, r12
        LEAVE
2:      mov rax, rbx
        LEAVE
1:      mov rdi, r12
        mov rsi, rbx
        mov edx, r13d
        call alg_le_op_top
        cmp eax, TRI_CANNOT
        je 3f
        test eax, eax
        jz 4f
        mov rax, rbx
        LEAVE
4:      mov rax, r12
        LEAVE
3:      xor eax, eax
        LEAVE
ENDF alg_max_op_top

FUNC alg_safe_max_op
        STACK_CHECK
        xor edx, edx
        jmp alg_max_op_top
ENDF alg_safe_max_op

# alg_min_op(left, right) / alg_min_op_top(left, right, top) -> rax: python's
# min_op, or NIL
FUNC alg_min_op
        xor edx, edx
        jmp alg_min_op_top
ENDF alg_min_op

FUNC alg_min_op_top
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13d, edx
        call alg_le_op_top
        cmp eax, TRI_CANNOT
        je 1f
        test eax, eax
        jz 2f
        mov rax, rbx
        LEAVE
2:      mov rax, r12
        LEAVE
1:      mov rdi, r12
        mov rsi, rbx
        mov edx, r13d
        call alg_le_op_top
        cmp eax, TRI_CANNOT
        je 3f
        test eax, eax
        jz 4f
        mov rax, r12
        LEAVE
4:      mov rax, rbx
        LEAVE
3:      xor eax, eax
        LEAVE
ENDF alg_min_op_top

FUNC alg_safe_min_op
        STACK_CHECK
        xor edx, edx
        jmp alg_min_op_top
ENDF alg_safe_min_op

# the comparisons of memory addresses and sizes (python's memloc: its
# partials of algebra's, top=MEMORY_TOP)
FUNC mem_ge_zero
        mov esi, 1
        jmp alg_ge_zero_top
ENDF mem_ge_zero

FUNC mem_safe_ge_zero
        mov esi, 1
        jmp alg_safe_ge_zero_top
ENDF mem_safe_ge_zero

FUNC mem_safe_gt_zero
        mov esi, 1
        jmp alg_safe_gt_zero_top
ENDF mem_safe_gt_zero

FUNC mem_get_sign
        mov esi, 1
        jmp alg_get_sign_top
ENDF mem_get_sign

FUNC mem_lt_op
        mov edx, 1
        jmp alg_lt_op_top
ENDF mem_lt_op

FUNC mem_safe_lt_op
        mov edx, 1
        jmp alg_safe_lt_op_top
ENDF mem_safe_lt_op

FUNC mem_le_op
        mov edx, 1
        jmp alg_le_op_top
ENDF mem_le_op

FUNC mem_safe_le_op
        mov edx, 1
        jmp alg_safe_le_op_top
ENDF mem_safe_le_op

FUNC mem_max_op
        mov edx, 1
        jmp alg_max_op_top
ENDF mem_max_op

FUNC mem_min_op
        mov edx, 1
        jmp alg_min_op_top
ENDF mem_min_op

# alg_max_op2(base, what) -> value: algebra._max_op (may yield ('max', ...))
FUNC alg_max_op2
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call opcode_of
        cmp eax, OP_MAX
        je 1f
        mov rdi, r12
        mov rsi, rbx
        call alg_safe_lt_op
        cmp eax, TRI_TRUE
        jne 2f
        mov rax, rbx
        LEAVE
2:      cmp eax, TRI_FALSE
        jne 3f
        mov rax, r12
        LEAVE
3:      LOADS rdi, MAX
        mov rsi, rbx
        mov rdx, r12
        call mk3
        LEAVE
1:      call vec_new
        mov r13, rax
        mov r14d, 1
4:      cmp r14d, [rbx + N_AUX]
        jae 7f
        mov rdi, r12
        mov rsi, [rbx + N_DATA + r14*8]
        call alg_safe_lt_op
        cmp eax, TRI_TRUE
        jne 5f
        mov rax, rbx
        LEAVE
5:      cmp eax, TRI_FALSE
        jne 6f
        mov rdi, r13
        mov rsi, r12
        call vec_push
        jmp 8f
6:      mov rdi, r13
        mov rsi, [rbx + N_DATA + r14*8]
        call vec_push
8:      inc r14d
        jmp 4b
7:      mov rdi, r13
        mov rsi, r12
        call vec_push
        # res = tuple(set(res)) - dedupe (keeping the first occurrences)
        mov rdi, r13
        call vec_dedupe
        mov rax, [r13 + VEC_LEN]
        cmp rax, 1
        jne 9f
        mov rax, [r13 + VEC_DATA]
        mov rax, [rax]
        LEAVE
9:      call vec_new
        mov r14, rax
        mov rdi, r14
        LOADS rsi, MAX
        call vec_push
        mov rdi, r14
        mov rsi, [r13 + VEC_DATA]
        mov rdx, [r13 + VEC_LEN]
        call vec_extend
        mov rdi, r14
        call vec_to_tuple
        LEAVE
ENDF alg_max_op2

# vec_dedupe(vec): removes later duplicates (py_equal), in place
FUNC vec_dedupe
        ENTER
        mov rbx, rdi
        xor r12d, r12d                  # write index
        xor r13d, r13d                  # read index
1:      cmp r13, [rbx + VEC_LEN]
        jae 5f
        mov rax, [rbx + VEC_DATA]
        mov r14, [rax + r13*8]
        xor ecx, ecx
2:      cmp rcx, r12
        jae 4f
        push rcx
        push rcx
        mov rax, [rbx + VEC_DATA]
        mov rdi, [rax + rcx*8]
        mov rsi, r14
        call py_equal
        pop rcx
        pop rcx
        test eax, eax
        jnz 3f
        inc rcx
        jmp 2b
4:      mov rax, [rbx + VEC_DATA]
        mov [rax + r12*8], r14
        inc r12
3:      inc r13
        jmp 1b
5:      mov [rbx + VEC_LEN], r12
        LEAVE
ENDF vec_dedupe

# --- the pieces used by the simplifier ---

        .section .rodata
.Ls_cannot_compare: .asciz "CannotCompare"
.Ls_type_error:     .asciz "TypeError: an int operation on an expression"
.Ls_not_implemented: .asciz "NotImplementedError"
        .text

# must_compare(eax) -> eax: raises CannotCompare where python would
FUNC must_compare
        cmp edi, TRI_CANNOT
        je 1f
        mov eax, edi
        ret
1:      mov edi, E_CANNOT_COMPARE
        lea rsi, [rip + .Ls_cannot_compare]
        jmp err_throw
ENDF must_compare

# must_int(v) -> v: python's TypeError when an expression meets an int
# operation
FUNC must_int
        test dil, 1
        jnz 1f
        test rdi, rdi
        jz 2f
        cmp dword ptr [rdi + N_KIND], K_INT
        jne 2f
1:      mov rax, rdi
        ret
2:      mov edi, E_TYPE
        lea rsi, [rip + .Ls_type_error]
        jmp err_throw
ENDF must_int

# to_bytes(exp) -> rax, rdx: python's to_bytes - exp bits, as (bytes, bits
# left over); the bits left over NIL (None) when it isn't known whether
# exp is a whole number of bytes
FUNC to_bytes
        STACK_CHECK
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 16
        mov rbx, rdi
        call is_int
        test eax, eax
        jz 1f
        # (exp + 7) // 8, exp % 8
        mov rdi, rbx
        mov esi, (7 << 1) | 1
        call int_add
        mov rdi, rax
        mov esi, (8 << 1) | 1
        call int_floordiv
        mov [rsp], rax
        mov rdi, rbx
        mov esi, (8 << 1) | 1
        call int_mod
        mov rdx, rax
        mov rax, [rsp]
        jmp .Ltb_done
1:      PAT rsi, "('mask_shl', 253, 0, 3, ':val')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 2f
        mov rax, [rsp]
        mov edx, 1
        jmp .Ltb_done
2:      PAT rsi, "('mask_shl', ':int:size', ':int:offset', ':int:shl', ':val')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 3f
        # the lowest 3 bits are 0: offset + shl >= 3
        mov rdi, [rsp + 8]
        call vr_number                  # (":int:": a bool too)
        mov [rsp + MATCH_BINDINGS_SIZE], rax
        mov rdi, [rsp + 16]
        call vr_number
        mov [rsp + MATCH_BINDINGS_SIZE + 8], rax
        mov rdi, [rsp + MATCH_BINDINGS_SIZE]
        mov rsi, rax
        call int_add
        mov rdi, rax
        mov esi, (3 << 1) | 1
        call int_cmp
        test eax, eax
        js 3f
        # ('mask_shl', size, offset, shl - 3, val), 0
        mov rdi, [rsp + MATCH_BINDINGS_SIZE + 8]
        mov esi, (3 << 1) | 1
        call int_sub
        mov rcx, rax
        mov r8, [rsp + 24]
        mov rdx, [rsp + 8]
        mov rsi, [rsp]
        LOADS rdi, MASK_SHL
        call mk5
        mov edx, 1
        jmp .Ltb_done
3:      mov rdi, rbx
        call opcode_of
        cmp eax, OP_MUL
        jne 4f
        # ('mul', int k, x), k a multiple of 8: ('mul', k // 8, x), 0
        cmp dword ptr [rbx + N_AUX], 3
        jne .Ltb_mask
        mov rdi, [rbx + N_DATA + 8]
        call is_int
        test eax, eax
        jz .Ltb_mask
        mov rdi, [rbx + N_DATA + 8]
        mov esi, (8 << 1) | 1
        call int_mod
        cmp rax, 1
        jne .Ltb_mask
        mov rdi, [rbx + N_DATA + 8]
        mov esi, (8 << 1) | 1
        call int_floordiv
        mov rsi, rax
        mov rdx, [rbx + N_DATA + 16]
        LOADS rdi, MUL
        call mk3
        mov edx, 1
        jmp .Ltb_done
4:      cmp eax, OP_ADD
        jne .Ltb_mask
        # the bytes of each term, when they all are whole
        call vec_new
        mov r12, rax
        mov r13d, 1
5:      cmp r13d, [rbx + N_AUX]
        jae 9f
        mov r14, [rbx + N_DATA + r13*8]
        inc r13d
        # ('mul', int k, ('mask_shl', 253, 0, 3, x)): ('mul', k, x)
        mov rdi, r14
        mov esi, OP_MUL
        mov edx, 3
        call is_op_n
        test eax, eax
        jz 6f
        mov rdi, [r14 + N_DATA + 8]
        call is_int
        test eax, eax
        jz 6f
        PAT rsi, "('mask_shl', 253, 0, 3, ':val')"
        mov rdi, [r14 + N_DATA + 16]
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 6f
        mov rsi, [r14 + N_DATA + 8]
        mov rdx, [rsp]
        LOADS rdi, MUL
        call mk3
        jmp 8f
6:      mov rdi, r14
        call to_bytes
        cmp rdx, 1
        jne .Ltb_mask                   # (bits left over, or not known)
8:      mov rdi, r12
        mov rsi, rax
        call vec_push
        jmp 5b
9:      # ('add', *res), 0
        mov rdi, r12
        LOADS rsi, ADD
        call vec_prepend
        mov rdi, r12
        call vec_to_tuple
        mov edx, 1
        jmp .Ltb_done
.Ltb_mask:
        # mask_op(exp, shr=3), None
        mov rdi, rbx
        mov esi, (256 << 1) | 1
        mov edx, 1
        mov ecx, 1
        mov r8d, (3 << 1) | 1
        call alg_mask_op
        xor edx, edx
.Ltb_done:
        add rsp, MATCH_BINDINGS_SIZE + 16
        LEAVE
ENDF to_bytes

# ---------------------------------------------------------------------
# shifts (python's shr_op, shl_op, signextend_op: the VM's and simplify's)

# alg_shr_op(exp, off) -> rax: python's shr_op - exp >> off, the bits [off,
# 256) of exp moved down by off: the mask a division by 2**off makes. By a
# symbolic amount: ('shr', off, exp).
FUNC alg_shr_op
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov rdi, rsi
        call vr_number                  # (isinstance(off, int): a bool too)
        test rax, rax
        jz 2f
        mov r13, rax
        mov rdi, rax
        mov esi, (256 << 1) | 1
        call int_cmp
        test eax, eax
        js 1f
        mov eax, 1                      # off >= 256: 0
        LEAVE
1:      mov edi, (256 << 1) | 1
        mov rsi, r13
        call int_sub
        mov rdi, rbx                    # mask_op(exp, size=256 - off,
        mov rsi, rax                    # offset=off, shr=off)
        mov rdx, r12
        mov ecx, 1
        mov r8, r12
        call alg_mask_op
        LEAVE
2:      LOADS rdi, SHR
        mov rsi, r12
        mov rdx, rbx
        call mk3
        LEAVE
ENDF alg_shr_op

# alg_shl_op(exp, off) -> rax: python's shl_op - exp << off, off a word: a
# mask of exp moved left by off, when that's what it is (off the integer
# it's made of, see value_range) and the mask can be printed as it is;
# else ('shl', off, exp)
FUNC alg_shl_op
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov rdi, rsi
        call is_int                     # (type(off) is int: not a bool)
        test eax, eax
        jz 2f
        mov rdi, r12
        mov esi, (256 << 1) | 1
        call int_cmp
        test eax, eax
        js 1f
        mov eax, 1                      # off >= 256: 0
        LEAVE
1:      mov rdi, rbx
        mov esi, (256 << 1) | 1
        mov edx, 1
        mov rcx, r12
        mov r8d, 1
        call alg_mask_op
        LEAVE
2:      mov rdi, r12
        xor esi, esi
        call is_word
        test eax, eax
        jz 3f
        mov rdi, rbx
        mov esi, (256 << 1) | 1
        mov edx, 1
        mov rcx, r12
        mov r8d, 1
        call alg_mask_op
        mov r13, rax
        mov rdi, rax
        call alg_readable
        test eax, eax
        jz 3f
        mov rax, r13
        LEAVE
3:      LOADS rdi, SHL
        mov rsi, r12
        mov rdx, rbx
        call mk3
        LEAVE
ENDF alg_shl_op

# alg_readable(exp) -> eax: python's _readable - a mask mask_op made can be
# printed as it is
FUNC alg_readable
        STACK_CHECK
        ENTER
        mov rbx, rdi
        call is_int
        test eax, eax
        jnz 8f
        mov rdi, rbx
        call opcode_of
        cmp eax, OP_MASK_SHL
        je 1f
        cmp eax, OP_OR
        je 2f
        cmp eax, OP_STORAGE
        je 4f
        jmp 9f
1:      cmp dword ptr [rbx + N_AUX], 5
        jne 9f
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, [rbx + N_DATA + 16]
        mov rdx, [rbx + N_DATA + 24]
        call readable_mask
        LEAVE
2:      mov r12d, 1                     # an or: all of its terms
3:      cmp r12d, [rbx + N_AUX]
        jae 8f
        mov rdi, [rbx + N_DATA + r12*8]
        inc r12d
        call alg_readable
        test eax, eax
        jnz 3b
        jmp 9f
4:      cmp dword ptr [rbx + N_AUX], 4  # a storage: its size and offset numbers
        jne 9f
        mov rdi, [rbx + N_DATA + 8]
        call is_int
        test eax, eax
        jz 9f
        mov rdi, [rbx + N_DATA + 16]
        call is_int
        LEAVE
8:      mov eax, 1
        LEAVE
9:      xor eax, eax
        LEAVE
ENDF alg_readable

# alg_signextend_op(b, val) -> rax: python's signextend_op - ('signextend',
# b, val), the lowest 8 * (b + 1) bits of val as a signed number
FUNC alg_signextend_op
        STACK_CHECK
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        call is_int                     # (type(b) is int)
        test eax, eax
        jz .Lse_asis
        # b %= 2**256 (the word it was made of); bits = 8 * (b + 1)
        mov rdi, rbx
        mov esi, 256
        call int_mod_2exp
        mov rbx, rax
        test bl, 1
        jz .Lse_val                     # (a big b: bits >= 256)
        mov r13, rbx
        sar r13, 1
        cmp r13, 31
        jae .Lse_val
        inc r13
        shl r13, 3                      # bits, < 256
        mov rdi, r12
        call is_int
        test eax, eax
        jz .Lse_exp
        # a number: its low bits, the ones above copies of the highest
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, r12
        call value_set_mpz
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, rdi
        mov rdx, r13
        call __gmpz_fdiv_r_2exp@PLT
        lea rdi, [r15 + CTX_MPZ_R]
        lea rsi, [r13 - 1]
        call __gmpz_tstbit@PLT
        mov [rsp], eax
        call arith_result
        cmp dword ptr [rsp], 0
        je .Lse_ret
        mov [rsp], rax                  # low | (2**256 - 2**bits)
        mov edi, 256
        call pow2
        mov [rsp + 8], rax
        mov rdi, r13
        call pow2
        mov rdi, [rsp + 8]
        mov rsi, rax
        call int_sub
        mov rdi, [rsp]
        mov rsi, rax
        call int_add
        jmp .Lse_ret
.Lse_exp:
        # ('signextend', int c, inner): of the fewer bits
        mov rdi, r12
        mov esi, OP_SIGNEXTEND
        mov edx, 3
        call is_op_n
        test eax, eax
        jz 2f
        mov rdi, [r12 + N_DATA + 8]
        call vr_number                  # (":int:c": a bool too)
        test rax, rax
        jz 2f
        mov rdi, rbx
        mov rsi, rax
        call int_cmp
        mov rdi, rbx                    # min(b, c): b when they're equal
        test eax, eax
        jle 21f
        mov rdi, [r12 + N_DATA + 8]
21:     mov rsi, [r12 + N_DATA + 16]
        call alg_signextend_op
        jmp .Lse_ret
2:      # a number made of some bits of another one: only its lowest bits
        # count, and if it has less than them the highest one is 0
        mov rdi, r12
        call is_mask_shl_ints
        test eax, eax
        jz 4f
        mov rdi, [r12 + N_DATA + 16]    # off >= 0
        call int_sign
        test eax, eax
        js 4f
        mov rdi, [r12 + N_DATA + 16]    # shl == -off
        call int_neg
        mov rdi, rax
        mov rsi, [r12 + N_DATA + 24]
        call values_equal
        test eax, eax
        jz 4f
        mov rdi, [r12 + N_DATA + 8]
        mov rsi, r13
        TAG rsi
        call int_cmp
        test eax, eax
        js .Lse_val                     # size < bits: val
        cmp qword ptr [r12 + N_DATA + 16], 1
        jne 3f
        mov rdi, rbx                    # off == 0: of the inner one
        mov rsi, [r12 + N_DATA + 32]
        call alg_signextend_op
        jmp .Lse_ret
3:      test eax, eax
        jz .Lse_mk                      # size == bits
        # ('signextend', b, ('mask_shl', bits, off, -off, inner))
        mov rdi, r13
        TAG rdi
        mov rsi, [r12 + N_DATA + 16]
        mov rdx, [r12 + N_DATA + 24]
        mov rcx, [r12 + N_DATA + 32]
        call mk_mask_shl
        mov r12, rax
        jmp .Lse_mk
4:      # ('storage', int size, int off >= 0, loc)
        mov rdi, r12
        mov esi, OP_STORAGE
        mov edx, 4
        call is_op_n
        test eax, eax
        jz .Lse_mk
        mov rdi, [r12 + N_DATA + 8]
        call vr_number
        test rax, rax
        jz .Lse_mk
        mov [rsp], rax
        mov rdi, [r12 + N_DATA + 16]
        call vr_number
        test rax, rax
        jz .Lse_mk
        mov rdi, rax
        call int_sign
        test eax, eax
        js .Lse_mk
        mov rdi, [rsp]
        mov rsi, r13
        TAG rsi
        call int_cmp
        test eax, eax
        js .Lse_val                     # size < bits: val
        jz .Lse_mk
        LOADS rdi, STORAGE              # ('signextend', b, ('storage', bits, off, loc))
        mov rsi, r13
        TAG rsi
        mov rdx, [r12 + N_DATA + 16]
        mov rcx, [r12 + N_DATA + 24]
        call mk4
        mov r12, rax
.Lse_mk:
        LOADS rdi, SIGNEXTEND
        mov rsi, rbx
        mov rdx, r12
        call mk3
        jmp .Lse_ret
.Lse_asis:
        LOADS rdi, SIGNEXTEND
        mov rsi, rbx
        mov rdx, r12
        call mk3
        jmp .Lse_ret
.Lse_val:
        mov rax, r12
.Lse_ret:
        add rsp, 16
        LEAVE
ENDF alg_signextend_op

# divisible_bytes(exp) -> eax: to_bytes gives whole bytes (and no error)
FUNC divisible_bytes
        ENTER
        sub rsp, ERR_SIZEOF + 16
        mov rbx, rdi
        mov rdi, rsp
        call err_catch
        test eax, eax
        jnz 1f
        mov rdi, rbx
        call to_bytes
        mov [rsp + ERR_SIZEOF], rdx
        call err_end
        xor eax, eax
        cmp qword ptr [rsp + ERR_SIZEOF], 1
        sete al
        add rsp, ERR_SIZEOF + 16
        LEAVE
1:      mov edi, eax                    # (python's timeout isn't an Exception)
        call err_rethrow_timeout
        xor eax, eax
        add rsp, ERR_SIZEOF + 16
        LEAVE
ENDF divisible_bytes

# vec_prepend(vec, v): insert v in front
FUNC vec_prepend
        ENTER
        mov rbx, rdi
        mov r12, rsi
        xor esi, esi
        call vec_push                   # room for one more
        mov rax, [rbx + VEC_DATA]
        mov rcx, [rbx + VEC_LEN]
        dec rcx
1:      test rcx, rcx
        jz 2f
        mov rdx, [rax + rcx*8 - 8]
        mov [rax + rcx*8], rdx
        dec rcx
        jmp 1b
2:      mov [rax], r12
        LEAVE
ENDF vec_prepend

        .section .note.GNU-stack,"",@progbits
