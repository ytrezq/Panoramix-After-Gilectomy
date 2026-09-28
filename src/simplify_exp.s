# Expression simplification (port of simplify.py's simplify_exp and its
# helpers): the rewrites applied to every expression of the trace.

.include "defs.inc"

        .section .rodata
.Ls_assert_mask:    .asciz "cleanup_mask_data: not a mask"
.Ls_msize_var:      .asciz "_msize"

        .text

# B reg, n: reg := binding n (of the last pat_match into [rsp])
.macro B reg, n
        mov \reg, [rsp + 8*(\n)]
.endm

# simplify_exp(exp) -> value (memoized; python's None for a zero-length
# memory read is sp_none)
FUNC simplify_exp
        STACK_CHECK
        ENTER
        mov rbx, rdi
        test dil, 1
        jnz .Lse_int
        test rdi, rdi
        jz .Lse_asis
        mov eax, [rbx + N_KIND]
        cmp eax, K_INT
        je .Lse_int
        cmp eax, K_SPECIAL
        je .Lse_special
        cmp eax, K_TUPLE
        jne .Lse_asis                   # lists, strings: as they are
        mov edi, MEMO_SIMPLIFY_EXP
        mov rsi, rbx
        call memo_get
        test rax, rax
        jnz 1f
        mov rdi, rbx
        call simplify_exp_impl
        mov r12, rax
        mov edi, MEMO_SIMPLIFY_EXP
        mov rsi, rbx
        mov rdx, r12
        call memo_put
        mov rax, r12
1:      LEAVE
.Lse_special:
        # True and False become 1 and 0: python's simplify_exp is @cached, and
        # True == 1 with the same hash, so simplify_exp(True) returns what
        # simplify_exp(1) gave, cached long before (every trace has a 1)
        mov eax, (1 << 1) | 1
        cmp dword ptr [rbx + N_AUX], SP_TRUE
        je 1b
        mov eax, 1
        cmp dword ptr [rbx + N_AUX], SP_FALSE
        je 1b
        mov rax, rbx                    # None
        LEAVE
.Lse_int:
        # larger than 30 bytes: probably an address, not a negative number
        mov rdi, rbx
        call to_real_int
        mov r12, rax
        mov rdi, rax
        mov esi, -1
        call int_cmp_pow8_22            # to_real_int(exp) > -(8**22)?
        test eax, eax
        jz .Lse_asis
        mov rax, r12
        LEAVE
.Lse_asis:
        mov rax, rbx
        LEAVE
ENDF simplify_exp

# int_cmp_pow8_22(v) -> eax: v > -(8^22)
FUNC int_cmp_pow8_22
        ENTER
        mov rbx, rdi
        mov edi, 3                      # 1
        mov esi, 66
        call int_shl_bits               # 2^66 = 8^22
        mov rdi, rax
        call int_neg
        mov rdi, rbx
        mov rsi, rax
        call int_cmp
        cmp eax, 1
        sete al
        movzx eax, al
        LEAVE
ENDF int_cmp_pow8_22

# int_shl_bits(v, k) -> value: v * 2^k (exact)
FUNC int_shl_bits
        ENTER
        mov rbx, rdi
        mov r12, rsi
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, rbx
        call value_set_mpz
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, rdi
        mov rdx, r12
        call __gmpz_mul_2exp@PLT
        call arith_result
        LEAVE
ENDF int_shl_bits

# simplify_exp_impl(exp) -> value, for a tuple
FUNC simplify_exp_impl
        STACK_CHECK
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 64
        .set SE_TMP, MATCH_BINDINGS_SIZE
        .set SE_TMP2, MATCH_BINDINGS_SIZE + 8
        .set SE_VEC, MATCH_BINDINGS_SIZE + 16
        .set SE_I, MATCH_BINDINGS_SIZE + 24
        .set SE_ACC, MATCH_BINDINGS_SIZE + 32
        mov rbx, rdi
        # mathematically incorrect, but this appears as an artifact of
        # other ops often
        PAT rsi, "('mask_shl', 246, 5, 0, ':exp')"
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 1f
        B r8, 0
        LOADS rdi, MASK_SHL
        mov esi, (251 << 1) | 1
        mov edx, (5 << 1) | 1
        mov ecx, 1
        call mk5
        mov rbx, rax
1:      mov rdi, rbx
        call opcode_of
        cmp eax, OP_AND
        jne 2f
        mov rdi, rbx
        call simplify_and_terms
        mov rbx, rax
2:      # ('data', 0, 0, ...) is 0
        mov rdi, rbx
        call opcode_of
        cmp eax, OP_DATA
        jne 3f
        mov ecx, 1
21:     cmp ecx, [rbx + N_AUX]
        jae 22f
        cmp qword ptr [rbx + N_DATA + rcx*8], 1
        jne 3f
        inc ecx
        jmp 21b
22:     mov eax, 1
        jmp .Lse_done
3:      # calldata params are left-padded usually, it seems
        PAT rsi, "('mask_shl', ':int:size', ':int:off', ':int:moff', ('cd', ':int:num'))"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 4f
        B rax, 1
        cmp rax, 1
        jle 4f
        B rcx, 2
        sar rcx, 1
        sar rax, 1
        add rax, rcx
        jnz 4f                          # moff == -off
        B rax, 0
        sar rax, 1
        cmp rax, 8
        je 31f
        cmp rax, 16
        je 31f
        cmp rax, 32
        je 31f
        cmp rax, 64
        je 31f
        cmp rax, 128
        jne 4f
31:     B rsi, 3
        LOADS rdi, CD
        call mk2
        mov r8, rax
        B rsi, 0
        LOADS rdi, MASK_SHL
        mov edx, 1
        mov ecx, 1
        call mk5
        jmp .Lse_done
4:      PAT rsi, "('iszero', ('iszero', ':e'))"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 5f
        B rdi, 0
        call mk_bool_of
        mov rbx, rax
5:      PAT rsi, "('bool', ('bool', ':e'))"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 6f
        B rdi, 0
        call mk_bool_of
        mov rbx, rax
6:      PAT rsi, "('eq', ':sth', 0)"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jnz 61f
        PAT rsi, "('eq', 0, ':sth')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 7f
61:     B rdi, 0
        call mk_iszero_of
        mov rbx, rax
7:      PAT rsi, "('mask_shl', ':int:size', 5, 0, ('add', ':int:num', '...'))"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 8f
        B rax, 0
        cmp rax, (240 << 1) | 1
        jle 8f
        B rax, 1
        cmp rax, (32 << 1) | 1
        jle 8f
        sar rax, 1
        mov rcx, rax
        and rcx, 31
        cmp rcx, 31
        jne 8f
        # ('add', num // 32, ('mask_shl', 256, 5, 0, ('add', 31) + add_terms))
        mov rax, [rbx + N_DATA + 32]    # the add
        mov [rsp + SE_TMP], rax
        call vec_new
        mov [rsp + SE_VEC], rax
        mov rdi, rax
        LOADS rsi, ADD
        call vec_push
        mov rdi, [rsp + SE_VEC]
        mov esi, (31 << 1) | 1
        call vec_push
        mov rax, [rsp + SE_TMP]
        mov edx, [rax + N_AUX]
        sub edx, 2
        lea rsi, [rax + N_DATA + 16]
        mov rdi, [rsp + SE_VEC]
        call vec_extend
        mov rdi, [rsp + SE_VEC]
        call vec_to_tuple
        mov r8, rax
        LOADS rdi, MASK_SHL
        mov esi, (256 << 1) | 1
        mov edx, (5 << 1) | 1
        mov ecx, 1
        call mk5
        mov rdx, rax
        B rsi, 1
        sar rsi, 1
        sar rsi, 5
        TAG rsi
        LOADS rdi, ADD
        call mk3
        mov rbx, rax
8:      PAT rsi, "('iszero', ('mask_shl', ':size', ':off', ':shl', ':val'))"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 9f
        B r8, 3
        B rdx, 1
        B rsi, 0
        LOADS rdi, MASK_SHL
        mov ecx, 1
        call mk5
        mov rdi, rax
        call mk_iszero_of
        mov rbx, rax
9:      PAT rsi, "('max', ':single')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 10f
        B rbx, 0
10:     PAT rsi, "('mem', ('range', 'Any', 0))"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 11f
        # sic. this happens usually in params to logs etc, we probably want None here
        lea rax, [rip + sp_none]
        jmp .Lse_done
11:     PAT rsi, "('mod', ':exp2', ':int:num')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 12f
        B rdi, 1
        call to_exp2
        cmp rax, 1
        jle 12f
        TAG rax
        B rdi, 0
        mov rsi, rax
        mov edx, 1
        mov ecx, 1
        mov r8d, 1
        call alg_mask_op
        jmp .Lse_done
12:     PAT rsi, "('mod', 0, 'Any')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 13f
        mov ebx, 1
13:     # same thing is added in both sides of a comparison?
        PAT rsi, "(':op', ('add', '...'), ('add', '...'))"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 14f
        B rdi, 0
        call str_id
        IN_OPSET cmp4, rax              # lt, le, gt, ge
        je 14f
        mov rdi, rbx
        call cancel_common_terms
        mov rbx, rax
14:     PAT rsi, "('add', ':e')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 15f
        B rdi, 0
        call simplify_exp
        jmp .Lse_done
15:     PAT rsi, "('mul', 1, ':e')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 16f
        B rdi, 0
        call simplify_exp
        jmp .Lse_done
16:     PAT rsi, "('div', ':e', 1)"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 17f
        B rdi, 0
        call simplify_exp
        jmp .Lse_done
17:     PAT rsi, "('mask_shl', 256, 0, 0, ':val')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 18f
        B rdi, 0
        call simplify_exp
        jmp .Lse_done
18:     PAT rsi, "('mask_shl', ':int:size', ':int:offset', ':int:shl', ':e')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 19f
        B rdi, 3
        call simplify_exp
        mov rdi, rax
        B rsi, 0
        B rdx, 1
        B rcx, 2
        mov r8d, 1
        call alg_mask_op
        mov rbx, rax
19:     PAT rsi, "('mask_shl', ':size', 0, 0, ('div', ':expr', ('exp', 256, ':shr')))"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 20f
        B rdi, 2
        call alg_bits
        mov [rsp + SE_TMP], rax
        B rdi, 1
        call simplify_exp
        mov rdi, rax
        B rsi, 0
        mov edx, 1
        mov ecx, 1
        mov r8, [rsp + SE_TMP]
        call alg_mask_op
        mov rbx, rax
20:     PAT rsi, "('mask_shl', 'Any', 'Any', ':shl', ('storage', ':size', 'Any', 'Any'))"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 23f
        B rdi, 0
        call alg_minus_op
        B rdi, 1
        mov rsi, rax
        call alg_safe_le_op
        cmp eax, TRI_TRUE
        jne 23f
        mov eax, 1
        jmp .Lse_done
23:     PAT rsi, "('or', ':sth', 0)"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 24f
        B rax, 0
        jmp .Lse_done
24:     mov rdi, rbx
        call opcode_of
        cmp eax, OP_ADD
        jne 25f
        mov rdi, rbx
        call simplify_add_terms
        mov rbx, rax
25:     mov rdi, rbx
        call opcode_of
        cmp eax, OP_MASK_SHL
        jne 26f
        mov rdi, rbx
        call cleanup_mask_data
        mov rbx, rax
26:     PAT rsi, "('mask_shl', ':size', 0, 0, ('mem', ('range', ':mem_loc', ':mem_size')))"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 27f
        B rdi, 0
        call divisible_bytes
        test eax, eax
        jz 27f
        B rdi, 0
        call to_bytes
        mov rdi, rax
        B rsi, 2
        call alg_safe_le_op
        cmp eax, TRI_TRUE
        jne 27f
        B rdi, 1
        B rsi, 2
        call mk_range
        mov rdi, rax
        B rsi, 0
        mov edx, 1
        call apply_mask_to_range
        mov rsi, rax
        LOADS rdi, MEM
        call mk2
        jmp .Lse_done
27:     PAT rsi, "('mask_shl', ':size', ':off', ':shl', ('mem', ('range', ':mem_loc', ':mem_size')))"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz .Lse_not_mem_mask
        B rdi, 1
        call alg_minus_op
        B rcx, 2
        cmp rax, rcx
        jne .Lse_after_data             # (an elif: no 'data' handling then)
        B rdi, 0
        call divisible_bytes
        test eax, eax
        jz .Lse_after_data
        B rdi, 0
        call to_bytes
        mov rdi, rax
        B rsi, 4
        call alg_safe_le_op
        cmp eax, TRI_TRUE
        jne .Lse_after_data
        B rdi, 1
        call divisible_bytes
        test eax, eax
        jz .Lse_after_data
        B rdi, 3
        B rsi, 4
        call mk_range
        mov rdi, rax
        B rsi, 0
        B rdx, 1
        call apply_mask_to_range
        mov rsi, rax
        LOADS rdi, MEM
        call mk2
        jmp .Lse_done
.Lse_not_mem_mask:
        mov rdi, rbx
        call opcode_of
        cmp eax, OP_DATA
        jne .Lse_after_data
        mov rdi, rbx
        call simplify_data
        jmp .Lse_done
.Lse_after_data:
        PAT rsi, "('mul', -1, ('mask_shl', ':size', ':offset', ':shl', ('mul', -1, ':val')))"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 28f
        B rdi, 0
        call simplify_exp
        mov [rsp + 0], rax
        B rdi, 1
        call simplify_exp
        mov [rsp + 8], rax
        B rdi, 2
        call simplify_exp
        mov [rsp + 16], rax
        B rdi, 3
        call simplify_exp
        mov r8, rax
        B rcx, 2
        B rdx, 1
        B rsi, 0
        LOADS rdi, MASK_SHL
        call mk5
        jmp .Lse_done
28:     mov rdi, rbx
        call is_int
        test eax, eax
        jz 29f
        # (rewritten to an int above: as simplify_exp does)
        mov rdi, rbx
        call simplify_exp
        jmp .Lse_done
29:     PAT rsi, "('and', ':num', ':num2')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 30f
        B rdi, 0
        call arith_eval
        mov rdi, rax
        call is_int
        test eax, eax
        jnz 291f
        B rdi, 1
        call arith_eval
        mov rdi, rax
        call is_int
        test eax, eax
        jz 30f
291:    mov rdi, rbx
        call simplify_mask
        jmp .Lse_done
30:     mov rdi, rbx
        call is_tuple
        test eax, eax
        jz .Lsei_asis
        PAT rsi, "('mask_shl', ':int:size', ':int:offset', ':int:shl', ':int:val')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 32f
        B rdi, 3
        B rsi, 0
        B rdx, 1
        B rcx, 2
        call alg_apply_mask
        jmp .Lse_done
32:     PAT rsi, "('mask_shl', ':size', 5, ':shl', ('add', 31, ('mask_shl', 251, 0, 5, ':val')))"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 33f
        B r8, 2
        B rcx, 1
        B rsi, 0
        LOADS rdi, MASK_SHL
        mov edx, (5 << 1) | 1
        call mk5
        mov rdi, rax
        call simplify_exp
        jmp .Lse_done
33:     mov rdi, rbx
        call opcode_of
        cmp eax, OP_MUL
        jne 34f
        # mul_op over the simplified terms
        mov qword ptr [rsp + SE_ACC], 3         # res = 1
        mov qword ptr [rsp + SE_I], 1
331:    mov rcx, [rsp + SE_I]
        cmp ecx, [rbx + N_AUX]
        jae 332f
        mov rdi, [rbx + N_DATA + rcx*8]
        call simplify_exp
        mov rdi, [rsp + SE_ACC]
        mov rsi, rax
        call alg_mul2
        mov [rsp + SE_ACC], rax
        inc qword ptr [rsp + SE_I]
        jmp 331b
332:    PAT rsi, "('mul', 1, ':res')"
        mov rdi, [rsp + SE_ACC]
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 333f
        B rax, 0
        jmp .Lse_done
333:    mov rax, [rsp + SE_ACC]
        jmp .Lse_done
34:     cmp eax, OP_MAX
        jne 35f
        # _max_op over the simplified terms
        mov qword ptr [rsp + SE_ACC], 1         # res = 0
        mov qword ptr [rsp + SE_I], 1
341:    mov rcx, [rsp + SE_I]
        cmp ecx, [rbx + N_AUX]
        jae 342f
        mov rdi, [rbx + N_DATA + rcx*8]
        call simplify_exp
        mov rdi, [rsp + SE_ACC]
        mov rsi, rax
        call alg_max_op2
        mov [rsp + SE_ACC], rax
        inc qword ptr [rsp + SE_I]
        jmp 341b
342:    mov rax, [rsp + SE_ACC]
        jmp .Lse_done
35:     # every element simplified
        mov rdi, rbx
        lea rsi, [rip + simplify_exp_cb]
        call map_seq
        jmp .Lse_done
.Lsei_asis:
        mov rax, rbx
.Lse_done:
        add rsp, MATCH_BINDINGS_SIZE + 64
        LEAVE
ENDF simplify_exp_impl

        OPSET_MEMBER cmp4, OP_LT
        OPSET_MEMBER cmp4, OP_LE
        OPSET_MEMBER cmp4, OP_GT
        OPSET_MEMBER cmp4, OP_GE
        OPSET_END cmp4, OP_COUNT

# simplify_exp_cb(x, arg) -> simplify_exp(x)
FUNC simplify_exp_cb
        STACK_CHECK
        jmp simplify_exp
ENDF simplify_exp_cb

# map_seq(seq, f) -> a sequence of the same kind with f(e, 0) applied to
# every element
FUNC map_seq
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov edi, [rbx + N_AUX]
        shl rdi, 3
        call arena_alloc
        mov [rsp], rax
        xor r13d, r13d
1:      cmp r13d, [rbx + N_AUX]
        jae 2f
        mov rdi, [rbx + N_DATA + r13*8]
        xor esi, esi
        call r12
        mov rcx, [rsp]
        mov [rcx + r13*8], rax
        inc r13d
        jmp 1b
2:      mov rdi, rbx
        mov rsi, [rsp]
        call mk_seq_like
        add rsp, 16
        LEAVE
ENDF map_seq

# simplify_and_terms(('and', ...)) -> ('and', [real], *symbols): the
# concrete terms ANDed together, the nested ands flattened
FUNC simplify_and_terms
        ENTER
        sub rsp, 16
        mov rbx, rdi
        call vec_new
        mov r12, rax                    # symbols
        mov edi, 3                      # 1
        mov esi, 256
        call int_shl_bits
        mov rdi, rax
        mov esi, 3
        call int_sub
        mov r13, rax                    # real = 2^256 - 1
        mov [rsp], r13
        mov r14d, 1
1:      cmp r14d, [rbx + N_AUX]
        jae 4f
        mov rdi, [rbx + N_DATA + r14*8]
        call is_int
        test eax, eax
        jz 2f
        mov rdi, [rbx + N_DATA + r14*8]
        call int_sign
        cmp eax, -1
        je 3f
        mov rdi, r13
        mov rsi, [rbx + N_DATA + r14*8]
        call int_and
        mov r13, rax
        jmp 5f
2:      mov rdi, [rbx + N_DATA + r14*8]
        call opcode_of
        cmp eax, OP_AND
        jne 3f
        mov rax, [rbx + N_DATA + r14*8]
        mov edx, [rax + N_AUX]
        dec edx
        lea rsi, [rax + N_DATA + 8]
        mov rdi, r12
        call vec_extend
        jmp 5f
3:      mov rdi, r12
        mov rsi, [rbx + N_DATA + r14*8]
        call vec_push
5:      inc r14d
        jmp 1b
4:      # ('and',) + (real,) if real changed + symbols
        mov rdi, r13
        mov rsi, [rsp]
        call values_equal
        test eax, eax
        jnz 6f
        mov rdi, r12
        mov rsi, r13
        call vec_prepend
6:      mov rdi, r12
        LOADS rsi, AND
        call vec_prepend
        mov rdi, r12
        call vec_to_tuple
        add rsp, 16
        LEAVE
ENDF simplify_and_terms

# int_and(a, b) -> value: the bitwise and of two non-negative ints
FUNC int_and
        ENTER
        mov rbx, rdi
        mov r12, rsi
        test dil, 1
        jz 1f
        test sil, 1
        jz 1f
        mov rax, rdi
        and rax, rsi                    # (the tag bits are both set)
        LEAVE
1:      lea rdi, [r15 + CTX_MPZ_A]
        mov rsi, rbx
        call value_set_mpz
        lea rdi, [r15 + CTX_MPZ_B]
        mov rsi, r12
        call value_set_mpz
        lea rdi, [r15 + CTX_MPZ_R]
        lea rsi, [r15 + CTX_MPZ_A]
        lea rdx, [r15 + CTX_MPZ_B]
        call __gmpz_and@PLT
        call arith_result
        LEAVE
ENDF int_and

# cancel_common_terms((op, ('add', ...), ('add', ...))) -> (op, add_op(*t1), add_op(*t2))
# with the terms both sides have removed
FUNC cancel_common_terms
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, [rbx + N_DATA + 8]     # ('add', ...)
        mov r13, [rbx + N_DATA + 16]
        mov rdi, r12
        mov rsi, r13
        call terms_not_in
        mov rdi, rax
        mov rsi, [rax + VEC_DATA]
        mov rdi, [rax + VEC_LEN]
        call alg_add_n
        mov [rsp], rax
        mov rdi, r13
        mov rsi, r12
        call terms_not_in
        mov rsi, [rax + VEC_DATA]
        mov rdi, [rax + VEC_LEN]
        call alg_add_n
        mov rdx, rax
        mov rsi, [rsp]
        mov rdi, [rbx + N_DATA]
        call mk3
        add rsp, 16
        LEAVE
ENDF cancel_common_terms

# terms_not_in(a, b) -> vec: the terms of the add a that aren't in b
FUNC terms_not_in
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call vec_new
        mov r13, rax
        mov r14d, 1
1:      cmp r14d, [rbx + N_AUX]
        jae 3f
        mov rdi, r12
        mov rsi, [rbx + N_DATA + r14*8]
        call seq_index_from1
        cmp rax, -1
        jne 2f
        mov rdi, r13
        mov rsi, [rbx + N_DATA + r14*8]
        call vec_push
2:      inc r14d
        jmp 1b
3:      mov rax, r13
        LEAVE
ENDF terms_not_in

# seq_index_from1(seq, x) -> rax: the index of x among seq[1:], or -1
# (by value: big ints compare equal)
FUNC seq_index_from1
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13d, 1
1:      cmp r13d, [rbx + N_AUX]
        jae 2f
        mov rdi, [rbx + N_DATA + r13*8]
        mov rsi, r12
        call values_equal
        test eax, eax
        jnz 3f
        inc r13d
        jmp 1b
2:      mov rax, -1
        LEAVE
3:      mov rax, r13
        LEAVE
ENDF seq_index_from1

# simplify_add_terms(('add', ...)) -> add_op over the simplified terms,
# the nested adds flattened
FUNC simplify_add_terms
        STACK_CHECK
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12d, 1                     # res = 0
        mov r13d, 1
1:      cmp r13d, [rbx + N_AUX]
        jae 5f
        mov rdi, [rbx + N_DATA + r13*8]
        call simplify_exp
        mov r14, rax
        mov rdi, rax
        call opcode_of
        cmp eax, OP_ADD
        jne 3f
        mov qword ptr [rsp], 1
2:      mov rcx, [rsp]
        cmp ecx, [r14 + N_AUX]
        jae 4f
        mov rdi, r12
        mov rsi, [r14 + N_DATA + rcx*8]
        call alg_add2
        mov r12, rax
        inc qword ptr [rsp]
        jmp 2b
3:      mov rdi, r12
        mov rsi, r14
        call alg_add2
        mov r12, rax
4:      inc r13d
        jmp 1b
5:      mov rax, r12
        add rsp, 16
        LEAVE
ENDF simplify_add_terms

# simplify_data(('data', ...)) -> value: the inner expressions
# simplified, the nested datas flattened, and the masks next to each
# other that make one merged
FUNC simplify_data
        STACK_CHECK
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 48
        .set SD_RES, MATCH_BINDINGS_SIZE
        .set SD_RES2, MATCH_BINDINGS_SIZE + 8
        .set SD_I, MATCH_BINDINGS_SIZE + 16
        .set SD_EL, MATCH_BINDINGS_SIZE + 24
        mov rbx, rdi
        call vec_new
        mov r12, rax
        mov r13d, 1
1:      cmp r13d, [rbx + N_AUX]
        jae 3f
        mov rdi, [rbx + N_DATA + r13*8]
        call simplify_exp
        mov r14, rax
        mov rdi, rax
        call opcode_of
        cmp eax, OP_DATA
        jne 2f
        mov edx, [r14 + N_AUX]
        dec edx
        lea rsi, [r14 + N_DATA + 8]
        mov rdi, r12
        call vec_extend
        jmp 4f
2:      mov rdi, r12
        mov rsi, r14
        call vec_push
4:      inc r13d
        jmp 1b
3:      # every swipe merges up to two elements next to each other; repeat
        # until there are no new merges
        mov rdi, r12
        call vec_to_list
        mov [rsp + SD_RES2], rax
        mov qword ptr [rsp + SD_RES], 0
.Lsd_swipe:
        mov rax, [rsp + SD_RES2]
        cmp rax, [rsp + SD_RES]
        je .Lsd_merged
        mov [rsp + SD_RES], rax
        mov rbx, rax                    # res
        call vec_new
        mov r12, rax                    # res2
        xor r13d, r13d                  # idx
5:      cmp r13d, [rbx + N_AUX]
        jae 8f
        mov r14, [rbx + N_DATA + r13*8] # el
        mov eax, [rbx + N_AUX]
        dec eax
        cmp r13d, eax
        jne 6f
        mov rdi, r12
        mov rsi, r14
        call vec_push
        jmp 8f
6:      mov rax, [rbx + N_DATA + r13*8 + 8]
        mov [rsp + SD_EL], rax          # next_el
        inc r13d
        PAT rsi, "('mask_shl', ':size', ':offset', ':shl', ':val')"
        mov rdi, r14
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 7f
        # next_el == ('mask_shl', offset, 0, 0, val) and offset + shl == 0
        B r8, 3
        B rsi, 1
        LOADS rdi, MASK_SHL
        mov edx, 1
        mov ecx, 1
        call mk5
        cmp rax, [rsp + SD_EL]
        jne 7f
        B rdi, 1
        B rsi, 2
        call alg_add2
        cmp rax, 1
        jne 7f
        B rdi, 0
        B rsi, 1
        call alg_add2
        mov rsi, rax
        B r8, 3
        LOADS rdi, MASK_SHL
        mov edx, 1
        mov ecx, 1
        call mk5
        mov rdi, r12
        mov rsi, rax
        call vec_push
        inc r13d
        jmp 5b
7:      mov rdi, r12
        mov rsi, r14
        call vec_push
        jmp 5b
8:      mov rdi, r12
        call vec_to_list
        mov [rsp + SD_RES2], rax
        jmp .Lsd_swipe
.Lsd_merged:
        mov rax, [rsp + SD_RES2]
        cmp dword ptr [rax + N_AUX], 1
        jne 9f
        mov rax, [rax + N_DATA]
        jmp .Lsd_done
9:      call vec_new
        mov r12, rax
        mov rdi, rax
        LOADS rsi, DATA
        call vec_push
        mov rdi, r12
        mov rsi, [rsp + SD_RES2]
        call vec_extend_seq
        mov rdi, r12
        call vec_to_tuple
.Lsd_done:
        add rsp, MATCH_BINDINGS_SIZE + 48
        LEAVE
ENDF simplify_data

# simplify_mask(exp) -> value
FUNC simplify_mask
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 16
        mov rbx, rdi
        call opcode_of
        mov edi, eax
        call is_arith_op
        test eax, eax
        jz 1f
        mov rdi, rbx
        call arith_eval
        mov rbx, rax
1:      PAT rsi, "('and', ':left', ':right')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 2f
        B rdi, 0
        call to_mask
        test rax, rax
        jz 11f
        B rdi, 1
        jmp 14f
11:     B rdi, 1
        call to_mask
        test rax, rax
        jz 12f
        B rdi, 0
14:     mov rsi, rax
        mov ecx, 1
        mov r8d, 1
        call alg_mask_op
        jmp .Lsm_done
12:     B rdi, 0
        call to_neg_mask
        test rax, rax
        jz 13f
        B rdi, 1
        jmp 15f
13:     B rdi, 1
        call to_neg_mask
        test rax, rax
        jz .Lsm_asis
        B rdi, 0
15:     mov rsi, rax
        call alg_neg_mask_op
        jmp .Lsm_done
2:      PAT rsi, "('div', ':left', ':int:right')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 3f
        B rdi, 1
        call to_exp2
        cmp rax, 0
        jle .Lsm_asis
        # mask_op(left, size=256 - shift, offset=shift, shr=shift)
        mov r8, rax
        TAG r8
        mov esi, 256
        sub rsi, rax
        TAG rsi
        mov rdx, r8
        mov ecx, 1
        B rdi, 0
        call alg_mask_op
        jmp .Lsm_done
3:      PAT rsi, "('mul', ':int:left', ':right')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 4f
        B rdi, 0
        call to_exp2
        cmp rax, 0
        jle 4f
        B rdi, 1
        jmp 5f
4:      PAT rsi, "('mul', ':left', ':int:right')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz .Lsm_asis
        B rdi, 1
        call to_exp2
        cmp rax, 0
        jle .Lsm_asis
        B rdi, 0
5:      # mask_op(x, size=256 - shift, shl=shift)
        mov rcx, rax
        TAG rcx
        mov esi, 256
        sub rsi, rax
        TAG rsi
        mov edx, 1
        mov r8d, 1
        call alg_mask_op
        jmp .Lsm_done
.Lsm_asis:
        mov rax, rbx
.Lsm_done:
        add rsp, MATCH_BINDINGS_SIZE + 16
        LEAVE
ENDF simplify_mask

# cleanup_mask_data(exp) -> value: for a mask over some data, removes the
# pieces of data that for sure won't fit into the mask
FUNC cleanup_mask_data
        STACK_CHECK
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 32
        .set CM_PREV, MATCH_BINDINGS_SIZE
        .set CM_SUM, MATCH_BINDINGS_SIZE + 8
        .set CM_I, MATCH_BINDINGS_SIZE + 16
        mov rbx, rdi
        call opcode_of
        cmp eax, OP_MASK_SHL
        jne .Lcm_assert
        mov qword ptr [rsp + CM_PREV], 0
1:      cmp rbx, [rsp + CM_PREV]
        je 2f
        mov [rsp + CM_PREV], rbx
        mov rdi, rbx
        call cleanup_mask_right
        mov rbx, rax
        jmp 1b
2:      mov qword ptr [rsp + CM_PREV], 0
3:      cmp rbx, [rsp + CM_PREV]
        je 4f
        mov [rsp + CM_PREV], rbx
        mov rdi, rbx
        call cleanup_mask_left
        mov rbx, rax
        jmp 3b
4:      PAT rsi, "('mask_shl', ':size', 0, 0, ('data', '...'))"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz .Lcm_done
        # if the size of the data is the size of the mask, the mask goes
        mov r12, [rbx + N_DATA + 32]    # the data
        mov qword ptr [rsp + CM_SUM], 1
        mov qword ptr [rsp + CM_I], 1
5:      mov rcx, [rsp + CM_I]
        cmp ecx, [r12 + N_AUX]
        jae 6f
        mov rdi, [r12 + N_DATA + rcx*8]
        call sizeof_s
        test rax, rax
        jz .Lcm_done
        mov rdi, [rsp + CM_SUM]
        mov rsi, rax
        call alg_add2
        mov [rsp + CM_SUM], rax
        inc qword ptr [rsp + CM_I]
        jmp 5b
6:      mov rdi, [rsp + CM_SUM]
        B rsi, 0
        call alg_sub_op
        cmp rax, 1
        jne .Lcm_done
        mov rbx, r12                    # ('data',) + terms: the data itself
.Lcm_done:
        mov rax, rbx
        add rsp, MATCH_BINDINGS_SIZE + 32
        LEAVE
.Lcm_assert:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_mask]
        call err_throw
ENDF cleanup_mask_data

# assert_mask5(exp): python's `m = match(exp, ("mask_shl", ":size",
# ":offset", ":shl", ":val")); assert m` - an AssertionError otherwise
FUNC assert_mask5
        ENTER
        mov esi, OP_MASK_SHL
        mov edx, 5
        call is_op_n
        test eax, eax
        jz 1f
        LEAVE
1:      mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_mask5]
        call err_throw
ENDF assert_mask5

        .section .rodata
.Ls_assert_mask5:   .asciz "cleanup_mask_data: the mask became something else"
        .text

# cleanup_mask_right(('mask_shl', size, offset, shl, val)): removes the
# last element of a data cut off by the offset
FUNC cleanup_mask_right
        ENTER
        sub rsp, 32
        mov rbx, rdi
        call assert_mask5               # (mask_op may have returned something else)
        mov r12, [rbx + N_DATA + 32]    # val
        mov rdi, r12
        call opcode_of
        cmp eax, OP_DATA
        jne .Lcr_asis
        mov rdi, r12
        call seq_last
        mov rdi, rax
        call sizeof_s
        test rax, rax
        jz .Lcr_asis
        mov r13, rax                    # sizeof(last)
        mov rdi, rax
        mov rsi, [rbx + N_DATA + 16]
        call alg_safe_le_op
        cmp eax, TRI_TRUE
        jne .Lcr_asis
        mov rdi, [rbx + N_DATA + 16]
        mov rsi, r13
        call alg_sub_op
        mov [rsp], rax                  # offset - sizeof(last)
        mov rdi, [rbx + N_DATA + 24]
        mov rsi, r13
        call alg_add2
        mov [rsp + 8], rax              # shl + sizeof(last)
        cmp dword ptr [r12 + N_AUX], 3
        jne 1f
        mov rdi, [r12 + N_DATA + 8]
        jmp 2f
1:      mov edi, [r12 + N_AUX]
        dec edi
        lea rsi, [r12 + N_DATA]
        call mk_tuple
        mov rdi, rax
2:      mov rsi, [rbx + N_DATA + 8]
        mov rdx, [rsp]
        mov rcx, [rsp + 8]
        mov r8d, 1
        call alg_mask_op
        add rsp, 32
        LEAVE
.Lcr_asis:
        mov rax, rbx
        add rsp, 32
        LEAVE
ENDF cleanup_mask_right

# cleanup_mask_left(('mask_shl', size, offset, shl, val)): removes the
# first elements of a data cut off by size + offset
FUNC cleanup_mask_left
        STACK_CHECK
        ENTER
        sub rsp, 32
        mov rbx, rdi
        call assert_mask5
        mov r12, [rbx + N_DATA + 32]    # val
        mov rdi, r12
        call opcode_of
        cmp eax, OP_DATA
        jne .Lcl_asis
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, [rbx + N_DATA + 16]
        call alg_add2
        mov [rsp], rax                  # total_size
        mov qword ptr [rsp + 8], 1      # sum_sizes = 0
        mov r13d, [r12 + N_AUX]         # the elements from the last one
1:      dec r13d
        jz .Lcl_asis
        mov rdi, [r12 + N_DATA + r13*8]
        call sizeof_s
        test rax, rax
        jz .Lcl_asis
        mov rdi, [rsp + 8]
        mov rsi, rax
        call alg_add2
        mov rdi, rax
        call simplify_exp
        mov [rsp + 8], rax
        mov rdi, [rsp]
        mov rsi, rax
        call alg_safe_le_op
        cmp eax, TRI_TRUE
        jne 1b
        # exp[:4] + (('data',) + the elements from r13 on,)
        call vec_new
        mov r14, rax
        mov rdi, rax
        LOADS rsi, DATA
        call vec_push
        mov edx, [r12 + N_AUX]
        sub edx, r13d
        lea rsi, [r12 + N_DATA + r13*8]
        mov rdi, r14
        call vec_extend
        mov rdi, r14
        call vec_to_tuple
        mov r8, rax
        mov rdi, [rbx + N_DATA]
        mov rsi, [rbx + N_DATA + 8]
        mov rdx, [rbx + N_DATA + 16]
        mov rcx, [rbx + N_DATA + 24]
        call mk5
        add rsp, 32
        LEAVE
.Lcl_asis:
        mov rax, rbx
        add rsp, 32
        LEAVE
ENDF cleanup_mask_left

# sizeof_s(exp) -> value or 0 (None): simplify.py's sizeof, in bits
FUNC sizeof_s
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE
        mov rbx, rdi
        PAT rsi, "('storage', ':size', '...')"
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 1f
        B rax, 0
        jmp .Lszs_done
1:      PAT rsi, "('mask_shl', ':size', '...')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 2f
        B rax, 0
        jmp .Lszs_done
2:      PAT rsi, "(':op', 'Any', ':size_bytes')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 3f
        B rdi, 0
        call str_id
        mov edi, eax
        call is_array_op
        test eax, eax
        jz 3f
        B rdi, 1
        call alg_bits
        jmp .Lszs_done
3:      PAT rsi, "('mem', ('range', 'Any', ':size_bytes'))"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 4f
        B rdi, 0
        call alg_bits
        jmp .Lszs_done
4:      PAT rsi, "('mem', ':idx')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jnz .Lszs_assert
        xor eax, eax
.Lszs_done:
        add rsp, MATCH_BINDINGS_SIZE
        LEAVE
.Lszs_assert:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_mask]
        call err_throw
ENDF sizeof_s

# canonise_max(exp) -> value: the terms of a max in a canonical order
# (sorted by their repr, the ints first)
FUNC canonise_max
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 16
        mov rbx, rdi
        call opcode_of
        cmp eax, OP_MAX
        jne .Lcx_asis
        call vec_new
        mov r12, rax
        mov r13d, 1
1:      cmp r13d, [rbx + N_AUX]
        jae 3f
        mov r14, [rbx + N_DATA + r13*8]
        PAT rsi, "('mul', 1, ':num')"
        mov rdi, r14
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 2f
        B r14, 0
2:      mov rdi, r12
        mov rsi, r14
        call vec_push
        inc r13d
        jmp 1b
3:      mov rdi, r12
        call sort_by_repr
        mov rdi, r12
        LOADS rsi, MAX
        call vec_prepend
        mov rdi, r12
        call vec_to_tuple
        add rsp, MATCH_BINDINGS_SIZE + 16
        LEAVE
.Lcx_asis:
        mov rax, rbx
        add rsp, MATCH_BINDINGS_SIZE + 16
        LEAVE
ENDF canonise_max

# sort_by_repr(vec): stable sort of values by their python str(), the
# ints keyed with a space in front (so first)
FUNC sort_by_repr
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, [rbx + VEC_LEN]
        # the keys, malloc'ed C strings
        lea rdi, [r12*8 + 8]
        call malloc@PLT
        mov r13, rax
        xor r14d, r14d
1:      cmp r14, r12
        jae 2f
        mov rax, [rbx + VEC_DATA]
        mov rdi, [rax + r14*8]
        call repr_key
        mov [r13 + r14*8], rax
        inc r14
        jmp 1b
2:      # insertion sort (stable), on the keys and the values together
        mov r14d, 1
3:      cmp r14, r12
        jae 6f
        mov rcx, r14
4:      test rcx, rcx
        jz 5f
        mov [rsp], rcx
        mov rdi, [r13 + rcx*8 - 8]
        mov rsi, [r13 + rcx*8]
        call strcmp@PLT
        mov rcx, [rsp]
        test eax, eax
        jle 5f
        mov rax, [r13 + rcx*8 - 8]
        xchg rax, [r13 + rcx*8]
        mov [r13 + rcx*8 - 8], rax
        mov rdx, [rbx + VEC_DATA]
        mov rax, [rdx + rcx*8 - 8]
        xchg rax, [rdx + rcx*8]
        mov [rdx + rcx*8 - 8], rax
        dec rcx
        jmp 4b
5:      inc r14
        jmp 3b
6:      xor r14d, r14d
7:      cmp r14, r12
        jae 8f
        mov rdi, [r13 + r14*8]
        call free@PLT
        inc r14
        jmp 7b
8:      mov rdi, r13
        call free@PLT
        add rsp, 16
        LEAVE
ENDF sort_by_repr

# repr_key(v) -> rax: a malloc'ed C string, the repr of the value, with
# a space in front for ints
FUNC repr_key
        ENTER
        mov r12, rdi
        call sb_new
        mov rbx, rax
        mov rdi, r12
        call is_int
        test eax, eax
        jz 1f
        mov rdi, rbx
        mov esi, ' '
        call sb_append_char
1:      mov rdi, r12                    # python's str(): a string without its quotes
        call is_str
        test eax, eax
        jz 2f
        mov rdi, rbx
        mov rsi, r12
        call sb_append_str
        jmp 3f
2:      mov rdi, rbx
        mov rsi, r12
        call value_print
3:      mov rdi, rbx
        xor esi, esi
        call sb_append_char             # NUL
        mov r12, [rbx + SB_BUF]
        mov rdi, rbx
        call free@PLT                   # (the builder, not its buffer)
        mov rax, r12
        LEAVE
ENDF repr_key

        .section .note.GNU-stack,"",@progbits
