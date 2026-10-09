# SafeMath: python's safemath.py - the arithmetic a contract checks before
# it uses its result (OpenZeppelin's SafeMath, ds-math, solidity's checks
# since 0.8, the compiler's check of a division, Vyper's), the checks gone
# where the result is used after them, the result a call of the contract's
# `def SafeMath:` functions, numbered for each other check, a message their
# parameter where it differs.
#
# The representation, as python's: a failure is ('invalid',), ('revert',),
# ('panic', code) or ('error', message) - the message an interned string
# of its bytes; a function's key is (op,) + ((check, kind), ...), the
# checks as the function's (of its parameters a and b), kind the failure
# without its message; what's found is (key, messages) for each call made,
# the call ('safemath', index, a[, b]) until the functions are named.

.include "defs.inc"

        .section .rodata
.Ls_two:        .asciz "  "
.Ls_def:        .asciz "def "
.Ls_open_a:     .asciz "(a"
.Ls_comma_b:    .asciz ", b"
.Ls_comma:      .asciz ", "
.Ls_close:      .asciz "):"
.Ls_solc8:      .asciz "# solidity >= 0.8"
.Ls_if:         .asciz "      if "
.Ls_colon:      .asciz ":"
.Ls_revert_w:   .asciz "          revert with "
.Ls_errorMessage: .asciz "errorMessage"
.Ls_safemath_dot: .asciz "SafeMath."
        .text

# the parameters of the functions: ('var', 'a'), ('var', 'b')
FUNC sm_param_a
        ENTER
        LOADS rdi, VAR
        LOADS rsi, A
        call mk2
        LEAVE
ENDF sm_param_a

FUNC sm_param_b
        ENTER
        LOADS rdi, VAR
        LOADS rsi, B
        call mk2
        LEAVE
ENDF sm_param_b

# sm_result(op id) -> rax: python's RESULTS[op], the result of a function
# of its parameters
FUNC sm_result
        ENTER
        mov ebx, edi
        call sm_param_a
        mov r12, rax
        call sm_param_b
        mov r13, rax
        cmp ebx, OP_ADD
        jne 1f
        LOADS rdi, ADD
        mov rsi, r12
        mov rdx, r13
        call mk3
        LEAVE
1:      cmp ebx, OP_SUB
        jne 2f
        LOADS rdi, MUL
        mov rsi, -1
        mov rdx, r13
        call mk3
        LOADS rdi, ADD
        mov rsi, r12
        mov rdx, rax
        call mk3
        LEAVE
2:      cmp ebx, OP_MUL
        jne 3f
        LOADS rdi, MUL
        mov rsi, r12
        mov rdx, r13
        call mk3
        LEAVE
3:      cmp ebx, OP_DIV
        jne 4f
        LOADS rdi, DIV
        mov rsi, r12
        mov rdx, r13
        call mk3
        LEAVE
4:      cmp ebx, OP_MOD
        jne 5f
        LOADS rdi, MOD
        mov rsi, r12
        mov rdx, r13
        call mk3
        LEAVE
5:      cmp ebx, OP_INC
        jne 6f
        LOADS rdi, ADD
        mov esi, 3                      # (1)
        mov rdx, r12
        call mk3
        LEAVE
6:      LOADS rdi, ADD                  # dec
        mov rsi, -1                     # (-1)
        mov rdx, r12
        call mk3
        LEAVE
ENDF sm_result

# the operations, in the block's order (python's RESULTS)
        .section .rodata
        .align 4
sm_ops: .long OP_ADD, OP_SUB, OP_MUL, OP_DIV, OP_MOD, OP_INC, OP_DEC, 0
        .text

# sm_fail(kind_op, arg) -> rax: (kind,) or (kind, arg) when arg isn't 0
FUNC sm_fail
        ENTER
        mov ebx, edi
        mov r12, rsi
        lea rax, [rip + opcode_nodes]
        mov rdi, [rax + rbx*8]
        test r12, r12
        jz 1f
        mov rsi, r12
        call mk2
        LEAVE
1:      call mk1
        LEAVE
ENDF sm_fail

# sm_failure(body) -> rax: python's failure - how the branch of a check
# fails, if that's all it does, or 0
FUNC sm_failure
        ENTER
        sub rsp, 16
        mov rbx, rdi
        call is_list
        test eax, eax
        jz .Lsf_none
        cmp dword ptr [rbx + N_AUX], 1
        jne .Lsf_none
        mov r12, [rbx + N_DATA]         # the line
        mov rdi, r12
        OP_N_CHECK OP_INVALID, 1, 1f
        mov edi, OP_INVALID
        xor esi, esi
        call sm_fail
        jmp .Lsf_ret
1:      mov rdi, r12
        OP_N_CHECK OP_REVERT, 2, .Lsf_none
        mov rdi, [r12 + N_DATA + 8]
        call is_none
        test eax, eax
        jz 2f
        mov edi, OP_REVERT
        xor esi, esi
        call sm_fail
        jmp .Lsf_ret
2:      mov r13, [r12 + N_DATA + 8]     # the data
        mov rdi, r13
        call opcode_of
        cmp eax, OP_DATA
        jne .Lsf_none
        # ('data', ('bytes', 4, PANIC), code)
        cmp dword ptr [r13 + N_AUX], 3
        jne 3f
        mov rdi, [r13 + N_DATA + 8]
        mov esi, 0x4E487B71
        call sm_is_selector
        test eax, eax
        jz 3f
        mov rdi, [r13 + N_DATA + 16]
        call is_int
        test eax, eax
        jz 3f
        mov edi, OP_PANIC
        mov rsi, [r13 + N_DATA + 16]
        call sm_fail
        jmp .Lsf_ret
3:      # ('data', ('bytes', 4, ERROR), 32, length, parts...)
        cmp dword ptr [r13 + N_AUX], 4
        jb .Lsf_none
        mov rdi, [r13 + N_DATA + 8]
        mov esi, 0x08C379A0
        call sm_is_selector
        test eax, eax
        jz .Lsf_none
        cmp qword ptr [r13 + N_DATA + 16], 65   # (32)
        jne .Lsf_none
        mov r14, [r13 + N_DATA + 24]    # the length
        test r14b, 1                    # (a small int: a length past 2^62
        jz .Lsf_none                    # is no message)
        sar r14, 1
        test r14, r14
        jle .Lsf_none
        call sb_new
        mov [rsp], rax
        mov ebx, 4                      # the part
4:      mov rax, [rsp]
        cmp [rax + SB_LEN], r14
        jae 5f
        cmp ebx, [r13 + N_AUX]
        jae 5f
        mov rdi, [rsp]
        mov rsi, [r13 + N_DATA + rbx*8]
        call data_bytes_into
        test eax, eax
        jz 8f
        inc ebx
        jmp 4b
5:      mov rax, [rsp]
        cmp [rax + SB_LEN], r14
        jb 8f
        mov rdi, [rax + SB_BUF]
        mov rsi, r14
        xor edx, edx
        call pretty_text
        test rax, rax
        jz 8f
        mov rax, [rsp]
        mov rdi, [rax + SB_BUF]
        mov rsi, r14
        call str_intern
        mov r12, rax
        mov rdi, [rsp]
        call sb_free
        mov edi, OP_ERROR
        mov rsi, r12
        call sm_fail
        jmp .Lsf_ret
8:      mov rdi, [rsp]
        call sb_free
.Lsf_none:
        xor eax, eax
.Lsf_ret:
        add rsp, 16
        LEAVE
ENDF sm_failure

# sm_is_selector(exp, sel) -> eax: exp is ('bytes', 4, sel)
FUNC sm_is_selector
        ENTER
        mov rbx, rdi
        mov r12d, esi
        OP_N_CHECK OP_BYTES, 3, 1f
        cmp qword ptr [rbx + N_DATA + 8], 9     # (4)
        jne 1f
        mov rax, r12
        shl rax, 1
        or rax, 1
        cmp [rbx + N_DATA + 16], rax
        jne 1f
        mov eax, 1
        LEAVE
1:      xor eax, eax
        LEAVE
ENDF sm_is_selector

# sm_is_check(line) -> eax: a one-sided if whose branch fails, all it does
FUNC sm_is_check
        ENTER
        mov rbx, rdi
        OP_N_CHECK OP_IF, 3, 1f
        mov rdi, [rbx + N_DATA + 16]
        call sm_failure
        test rax, rax
        setnz al
        movzx eax, al
        LEAVE
1:      xor eax, eax
        LEAVE
ENDF sm_is_check

# sm_check_fail(check) -> rax: the failure of a check (its branch's)
FUNC sm_check_fail
        mov rdi, [rdi + N_DATA + 16]
        jmp sm_failure
ENDF sm_check_fail

# sm_kind_id(fail) -> eax: the opcode id of a failure's kind
FUNC sm_kind_id
        mov rdi, [rdi + N_DATA]
        mov eax, [rdi + N_AUX]
        and eax, STR_ID_MASK
        ret
ENDF sm_kind_id

# sm_negated(term) -> rax: what a term of a sum subtracts, if it's
# subtracted, or 0
FUNC sm_negated
        ENTER
        mov rbx, rdi
        call is_int
        test eax, eax
        jz 2f
        mov rdi, rbx
        call int_sign
        cmp eax, -1
        jne 9f
        mov rdi, rbx
        call int_neg
        LEAVE
2:      mov rdi, rbx
        call opcode_of
        cmp eax, OP_MUL
        jne 9f
        mov ecx, [rbx + N_AUX]
        cmp ecx, 3
        jb 9f
        mov rdi, [rbx + N_DATA + 8]
        mov r12, rdi
        call is_int
        test eax, eax
        jz 9f
        cmp r12, -1                     # (-1, tagged)
        jne 4f
        cmp dword ptr [rbx + N_AUX], 3
        jne 3f
        mov rax, [rbx + N_DATA + 16]
        LEAVE
3:      # ('mul',) + term[2:]
        mov edi, [rbx + N_AUX]
        sub edi, 2
        lea rsi, [rbx + N_DATA + 16]
        LOADS rdx, MUL
        call sm_tuple_with_head
        LEAVE
4:      mov rdi, r12
        call int_sign
        cmp eax, -1
        jne 9f
        # ('mul', -term[1]) + term[2:]
        mov rdi, r12
        call int_neg
        mov r13, rax
        mov edi, [rbx + N_AUX]
        dec edi
        call vec_new_cap
        mov r14, rax
        mov rdi, rax
        LOADS rsi, MUL
        call vec_push
        mov rdi, r14
        mov rsi, r13
        call vec_push
        mov edx, [rbx + N_AUX]
        sub edx, 2
        lea rsi, [rbx + N_DATA + 16]
        mov rdi, r14
        call vec_extend
        mov rdi, r14
        call vec_to_tuple
        LEAVE
9:      xor eax, eax
        LEAVE
ENDF sm_negated

# sm_tuple_with_head(count, elems, head) -> (head,) + elems
FUNC sm_tuple_with_head
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        lea rdi, [rbx + 1]
        call vec_new_cap
        mov r14, rax
        mov rdi, rax
        mov rsi, r13
        call vec_push
        mov rdi, r14
        mov rsi, r12
        mov rdx, rbx
        call vec_extend
        mov rdi, r14
        call vec_to_tuple
        LEAVE
ENDF sm_tuple_with_head

# sm_sum(vec) -> rax: python's _sum - 0, the term, or ('add',) + terms
FUNC sm_sum
        mov rax, [rdi + VEC_LEN]
        test rax, rax
        jnz 1f
        mov eax, 1                      # (0)
        ret
1:      cmp rax, 1
        jne 2f
        mov rax, [rdi + VEC_DATA]
        mov rax, [rax]
        ret
2:      mov rsi, [rdi + VEC_DATA]
        mov rdi, rax
        LOADS rdx, ADD
        jmp sm_tuple_with_head
ENDF sm_sum

# sm_product(vec) -> rax: python's _product - the term, or ('mul',) + terms
FUNC sm_product
        mov rax, [rdi + VEC_LEN]
        cmp rax, 1
        jne 2f
        mov rax, [rdi + VEC_DATA]
        mov rax, [rax]
        ret
2:      mov rsi, [rdi + VEC_DATA]
        mov rdi, rax
        LOADS rdx, MUL
        jmp sm_tuple_with_head
ENDF sm_product

# sm_others(seq, i) -> vec: the elements 1.. of seq but the i-th (1-based)
FUNC sm_others
        ENTER
        mov rbx, rdi
        mov r12d, esi
        mov edi, [rbx + N_AUX]
        call vec_new_cap
        mov r13, rax
        mov r14d, 1
1:      cmp r14d, [rbx + N_AUX]
        jae 2f
        cmp r14d, r12d
        je 11f
        mov rdi, r13
        mov rsi, [rbx + N_DATA + r14*8]
        call vec_push
11:     inc r14d
        jmp 1b
2:      mov rax, r13
        LEAVE
ENDF sm_others

# sm_in3(cond, op, x, y) -> eax: cond is (op, x, y) - op an opcode id
FUNC sm_in3
        ENTER
        mov rbx, rdi
        lea rax, [rip + opcode_nodes]
        mov rdi, [rax + rsi*8]
        mov rsi, rdx
        mov rdx, rcx
        call mk3
        cmp rax, rbx
        sete al
        movzx eax, al
        LEAVE
ENDF sm_in3

# sm_in2(cond, op, x) -> eax: cond is (op, x)
FUNC sm_in2
        ENTER
        mov rbx, rdi
        lea rax, [rip + opcode_nodes]
        mov rdi, [rax + rsi*8]
        mov rsi, rdx
        call mk2
        cmp rax, rbx
        sete al
        movzx eax, al
        LEAVE
ENDF sm_in2

# sm_max() -> rax: 2^256 - 1
FUNC sm_max
        mov rdi, -1
        mov esi, 256
        jmp int_mod_2exp
ENDF sm_max

# sm_match(cond, fail, res, out) -> eax: python's match_check - the
# operation a check (of cond, failing as fail) is of, if res is its result:
# out[0] the op's id, out[1] a, out[2] b (0 for inc and dec)
FUNC sm_match
        STACK_CHECK
        ENTER
        sub rsp, 80
        .set SM_FAIL, 0
        .set SM_OUT, 8
        .set SM_I, 16
        .set SM_A, 24
        .set SM_B, 32
        .set SM_T, 40                   # scratch
        .set SM_T2, 48
        .set SM_T3, 56
        .set SM_POS, 64
        .set SM_NEG, 72
        mov rbx, rdi                    # cond
        mov [rsp + SM_FAIL], rsi
        mov r12, rdx                    # res
        mov [rsp + SM_OUT], rcx
        mov rdi, r12
        call opcode_of
        cmp eax, OP_ADD
        je .Lsm_add
        cmp eax, OP_MUL
        je .Lsm_mul
        cmp eax, OP_DIV
        je .Lsm_div
        cmp eax, OP_MOD
        je .Lsm_div
        jmp .Lsm_none

.Lsm_add:
        cmp dword ptr [r12 + N_AUX], 2
        jbe .Lsm_none
        # the terms subtracted, and the others
        mov edi, [r12 + N_AUX]
        call vec_new_cap
        mov [rsp + SM_POS], rax
        mov edi, [r12 + N_AUX]
        call vec_new_cap
        mov [rsp + SM_NEG], rax
        mov r13d, 1
1:      cmp r13d, [r12 + N_AUX]
        jae 2f
        mov rdi, [r12 + N_DATA + r13*8]
        call sm_negated
        test rax, rax
        jz 11f
        mov rdi, [rsp + SM_NEG]
        mov rsi, rax
        call vec_push
        jmp 12f
11:     mov rdi, [rsp + SM_POS]
        mov rsi, [r12 + N_DATA + r13*8]
        call vec_push
12:     inc r13d
        jmp 1b
2:      mov rax, [rsp + SM_NEG]
        cmp qword ptr [rax + VEC_LEN], 0
        je .Lsm_addition
        # a - b
        mov rdi, [rsp + SM_POS]
        call sm_sum
        mov [rsp + SM_A], rax
        mov rdi, [rsp + SM_NEG]
        call sm_sum
        mov [rsp + SM_B], rax
        mov rdi, rbx
        mov esi, OP_GT
        mov rdx, [rsp + SM_B]
        mov rcx, [rsp + SM_A]
        call sm_in3
        test eax, eax
        jnz .Lsm_sub
        mov rdi, rbx
        mov esi, OP_LT
        mov rdx, [rsp + SM_A]
        mov rcx, [rsp + SM_B]
        call sm_in3
        test eax, eax
        jnz .Lsm_sub
        mov rdi, rbx
        mov esi, OP_GT
        mov rdx, r12
        mov rcx, [rsp + SM_A]
        call sm_in3
        test eax, eax
        jnz .Lsm_sub
        mov rdi, rbx
        mov esi, OP_LT
        mov rdx, [rsp + SM_A]
        mov rcx, r12
        call sm_in3
        test eax, eax
        jnz .Lsm_sub
        # solidity's a - 1 since 0.8: a isn't 0
        cmp qword ptr [rsp + SM_B], 3   # (1)
        jne .Lsm_none
        mov rdi, [rsp + SM_FAIL]
        mov esi, 0x11
        call sm_is_panic
        test eax, eax
        jz .Lsm_none
        mov rdi, rbx
        mov esi, OP_ISZERO
        mov rdx, [rsp + SM_A]
        call sm_in2
        test eax, eax
        jnz .Lsm_dec
        mov rdi, rbx
        mov esi, OP_EQ
        mov rdx, [rsp + SM_A]
        mov ecx, 1                      # (0)
        call sm_in3
        test eax, eax
        jnz .Lsm_dec
        mov rdi, rbx
        mov esi, OP_EQ
        mov edx, 1
        mov rcx, [rsp + SM_A]
        call sm_in3
        test eax, eax
        jnz .Lsm_dec
        jmp .Lsm_none
.Lsm_sub:
        mov eax, OP_SUB
        jmp .Lsm_found
.Lsm_dec:
        mov qword ptr [rsp + SM_B], 0
        mov eax, OP_DEC
        jmp .Lsm_found

.Lsm_addition:
        mov qword ptr [rsp + SM_I], 1
.Lsm_add_term:
        mov rcx, [rsp + SM_I]
        cmp ecx, [r12 + N_AUX]
        jae .Lsm_none
        mov rax, [r12 + N_DATA + rcx*8]
        mov [rsp + SM_A], rax
        mov rdi, r12
        mov esi, ecx
        call sm_others
        mov rdi, rax
        call sm_sum
        mov [rsp + SM_B], rax
        # the sum compared with a
        mov rdi, rbx
        mov esi, OP_LT
        mov rdx, r12
        mov rcx, [rsp + SM_A]
        call sm_in3
        test eax, eax
        jnz .Lsm_add_found
        mov rdi, rbx
        mov esi, OP_LE
        mov rdx, r12
        mov rcx, [rsp + SM_A]
        call sm_in3
        test eax, eax
        jnz .Lsm_add_found
        mov rdi, rbx
        mov esi, OP_GT
        mov rdx, [rsp + SM_A]
        mov rcx, r12
        call sm_in3
        test eax, eax
        jnz .Lsm_add_found
        mov rdi, rbx
        mov esi, OP_GE
        mov rdx, [rsp + SM_A]
        mov rcx, r12
        call sm_in3
        test eax, eax
        jnz .Lsm_add_found
        # a compared with ~b, as the simplifier may have it: ('not', b),
        # -1 - b, and that mod 2^256 when it's a number
        LOADS rdi, NOT
        mov rsi, [rsp + SM_B]
        call mk2
        mov [rsp + SM_T], rax
        mov rdi, -1
        mov rsi, [rsp + SM_B]
        call alg_mul2
        mov rsi, rax
        mov rdi, -1
        call alg_add2
        mov [rsp + SM_T2], rax
        mov qword ptr [rsp + SM_T3], 0
        mov rdi, rax
        call is_int
        test eax, eax
        jz 3f
        mov rdi, [rsp + SM_T2]
        mov esi, 256
        call int_mod_2exp
        mov [rsp + SM_T3], rax
3:      lea r13, [rsp + SM_T]
        xor r14d, r14d
4:      cmp r14d, 3
        jae 6f
        mov rcx, [r13 + r14*8]
        test rcx, rcx
        jz 5f
        mov rdi, rbx
        mov esi, OP_GT
        mov rdx, [rsp + SM_A]
        call sm_in3
        test eax, eax
        jnz .Lsm_add_found
        mov rdi, rbx
        mov esi, OP_LT
        mov rdx, [r13 + r14*8]
        mov rcx, [rsp + SM_A]
        call sm_in3
        test eax, eax
        jnz .Lsm_add_found
5:      inc r14d
        jmp 4b
6:      # solidity's a + 1 since 0.8: a isn't the largest word
        cmp qword ptr [rsp + SM_B], 3   # (1)
        jne 7f
        mov rdi, [rsp + SM_FAIL]
        mov esi, 0x11
        call sm_is_panic
        test eax, eax
        jz 7f
        call sm_max
        mov [rsp + SM_T], rax
        mov qword ptr [rsp + SM_T2], -1
        lea r13, [rsp + SM_T]
        xor r14d, r14d
61:     cmp r14d, 2
        jae 7f
        mov rdi, rbx
        mov esi, OP_EQ
        mov rdx, [rsp + SM_A]
        mov rcx, [r13 + r14*8]
        call sm_in3
        test eax, eax
        jnz .Lsm_inc
        mov rdi, rbx
        mov esi, OP_EQ
        mov rdx, [r13 + r14*8]
        mov rcx, [rsp + SM_A]
        call sm_in3
        test eax, eax
        jnz .Lsm_inc
        inc r14d
        jmp 61b
7:      inc qword ptr [rsp + SM_I]
        jmp .Lsm_add_term
.Lsm_add_found:
        mov eax, OP_ADD
        jmp .Lsm_found
.Lsm_inc:
        mov qword ptr [rsp + SM_B], 0
        mov eax, OP_INC
        jmp .Lsm_found

.Lsm_mul:
        cmp dword ptr [r12 + N_AUX], 2
        jbe .Lsm_none
        mov qword ptr [rsp + SM_I], 1
.Lsm_mul_term:
        mov rcx, [rsp + SM_I]
        cmp ecx, [r12 + N_AUX]
        jae .Lsm_none
        mov rax, [r12 + N_DATA + rcx*8]
        mov [rsp + SM_A], rax
        mov rdi, r12
        mov esi, ecx
        call sm_others
        mov rdi, rax
        call sm_product
        mov [rsp + SM_B], rax
        # ('iszero', ('eq', ('div', res, a), b)), and with b first
        LOADS rdi, DIV
        mov rsi, r12
        mov rdx, [rsp + SM_A]
        call mk3
        mov [rsp + SM_T3], rax          # res / a
        LOADS rdi, EQ
        mov rsi, rax
        mov rdx, [rsp + SM_B]
        call mk3
        mov rsi, rax
        LOADS rdi, ISZERO
        call mk2
        mov [rsp + SM_T], rax
        LOADS rdi, EQ
        mov rsi, [rsp + SM_B]
        mov rdx, [rsp + SM_T3]
        call mk3
        mov rsi, rax
        LOADS rdi, ISZERO
        call mk2
        mov [rsp + SM_T2], rax
        lea r13, [rsp + SM_T]
        xor r14d, r14d
1:      cmp r14d, 2
        jae 3f
        cmp rbx, [r13 + r14*8]
        je .Lsm_mul_found
        mov rdi, rbx
        mov esi, OP_AND
        mov rdx, [rsp + SM_A]
        mov rcx, [r13 + r14*8]
        call sm_in3
        test eax, eax
        jnz .Lsm_mul_found
        mov rdi, rbx
        mov esi, OP_AND
        mov rdx, [r13 + r14*8]
        mov rcx, [rsp + SM_A]
        call sm_in3
        test eax, eax
        jnz .Lsm_mul_found
        inc r14d
        jmp 1b
3:      # b compared with the most a can be multiplied by: -1 / a, then
        # 2^256 - 1 / a
        mov qword ptr [rsp + SM_T3], -1
.Lsm_mul_most:
        LOADS rdi, DIV
        mov rsi, [rsp + SM_T3]
        mov rdx, [rsp + SM_A]
        call mk3
        mov [rsp + SM_T2], rax          # most
        LOADS rdi, GT
        mov rsi, [rsp + SM_B]
        mov rdx, rax
        call mk3
        mov [rsp + SM_T], rax           # ('gt', b, most)
        call .Lsm_mul_and
        test eax, eax
        jnz .Lsm_mul_found
        LOADS rdi, LT
        mov rsi, [rsp + SM_T2]
        mov rdx, [rsp + SM_B]
        call mk3
        mov [rsp + SM_T], rax           # ('lt', most, b)
        call .Lsm_mul_and
        test eax, eax
        jnz .Lsm_mul_found
        cmp qword ptr [rsp + SM_T3], -1
        jne 4f
        call sm_max
        mov [rsp + SM_T3], rax
        jmp .Lsm_mul_most
4:      inc qword ptr [rsp + SM_I]
        jmp .Lsm_mul_term
.Lsm_mul_found:
        mov eax, OP_MUL
        jmp .Lsm_found
# local: eax = cond is ('and', a, gt) or ('and', gt, a), gt at [rsp + 8 + SM_T]
.Lsm_mul_and:
        sub rsp, 8
        mov rdi, rbx
        mov esi, OP_AND
        mov rdx, [rsp + 16 + SM_A]
        mov rcx, [rsp + 16 + SM_T]
        call sm_in3
        test eax, eax
        jnz 1f
        mov rdi, rbx
        mov esi, OP_AND
        mov rdx, [rsp + 16 + SM_T]
        mov rcx, [rsp + 16 + SM_A]
        call sm_in3
1:      add rsp, 8
        ret

.Lsm_div:
        cmp dword ptr [r12 + N_AUX], 3
        jne .Lsm_none
        mov rax, [r12 + N_DATA + 8]
        mov [rsp + SM_A], rax
        mov rax, [r12 + N_DATA + 16]
        mov [rsp + SM_B], rax
        mov rdi, rbx
        call sm_zero_test
        test rax, rax
        jz .Lsm_none
        cmp rax, [rsp + SM_B]
        jne .Lsm_none
        mov rdi, r12
        call opcode_of
        jmp .Lsm_found

.Lsm_found:
        mov rcx, [rsp + SM_OUT]
        mov [rcx], rax
        mov rax, [rsp + SM_A]
        mov [rcx + 8], rax
        mov rax, [rsp + SM_B]
        mov [rcx + 16], rax
        mov eax, 1
        add rsp, 80
        LEAVE
.Lsm_none:
        xor eax, eax
        add rsp, 80
        LEAVE
ENDF sm_match

# sm_is_panic(fail, code) -> eax: fail is ('panic', code)
FUNC sm_is_panic
        ENTER
        mov rbx, rdi
        mov r12d, esi
        test rbx, rbx
        jz 1f
        mov rdi, rbx
        OP_N_CHECK OP_PANIC, 2, 1f
        mov rax, r12
        shl rax, 1
        or rax, 1
        cmp [rbx + N_DATA + 8], rax
        jne 1f
        mov eax, 1
        LEAVE
1:      xor eax, eax
        LEAVE
ENDF sm_is_panic

# sm_zero_test(cond) -> rax: what cond tests to be 0, or 0
FUNC sm_zero_test
        ENTER
        mov rbx, rdi
        call opcode_of
        cmp eax, OP_ISZERO
        jne 1f
        cmp dword ptr [rbx + N_AUX], 2
        jne 9f
        mov rax, [rbx + N_DATA + 8]
        LEAVE
1:      cmp eax, OP_EQ
        je 2f
        cmp eax, OP_LE
        jne 9f
2:      cmp dword ptr [rbx + N_AUX], 3
        jne 9f
        cmp qword ptr [rbx + N_DATA + 16], 1    # (0)
        jne 3f
        mov rax, [rbx + N_DATA + 8]
        LEAVE
3:      cmp eax, OP_EQ
        jne 9f
        cmp qword ptr [rbx + N_DATA + 8], 1
        jne 9f
        mov rax, [rbx + N_DATA + 16]
        LEAVE
9:      xor eax, eax
        LEAVE
ENDF sm_zero_test

# sm_divides(d, exp) -> eax: exp divides by d somewhere
FUNC sm_divides
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov rdi, rsi
        call opcode_of
        cmp eax, OP_DIV
        je 1f
        cmp eax, OP_MOD
        jne 2f
1:      cmp dword ptr [r12 + N_AUX], 3
        jne 2f
        cmp [r12 + N_DATA + 16], rbx
        je 8f
2:      test r12b, 1
        jnz 9f
        test r12, r12
        jz 9f
        mov eax, [r12 + N_KIND]
        cmp eax, K_TUPLE
        je 3f
        cmp eax, K_LIST
        jne 9f
3:      xor r13d, r13d
4:      cmp r13d, [r12 + N_AUX]
        jae 9f
        mov rdi, rbx
        mov rsi, [r12 + N_DATA + r13*8]
        call sm_divides
        test eax, eax
        jnz 8f
        inc r13d
        jmp 4b
8:      mov eax, 1
        LEAVE
9:      xor eax, eax
        LEAVE
ENDF sm_divides

# sm_candidates(exp, vec): the results of arithmetic in exp pushed, the
# outer ones first - but a * b / a, which only a check of a * b computes
FUNC sm_candidates
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        test bl, 1
        jnz 9f
        test rbx, rbx
        jz 9f
        mov eax, [rbx + N_KIND]
        cmp eax, K_TUPLE
        je 1f
        cmp eax, K_LIST
        jne 9f
1:      mov rdi, rbx
        call opcode_of
        cmp eax, OP_ADD
        je 3f
        cmp eax, OP_MUL
        je 3f
        cmp eax, OP_MOD
        je 3f
        cmp eax, OP_DIV
        jne 4f
        # a * b / a?
        cmp dword ptr [rbx + N_AUX], 3
        jne 3f
        mov rdi, [rbx + N_DATA + 8]
        call opcode_of
        cmp eax, OP_MUL
        jne 3f
        mov rax, [rbx + N_DATA + 8]
        mov rcx, [rbx + N_DATA + 16]
        mov edx, 1
2:      cmp edx, [rax + N_AUX]
        jae 3f
        cmp [rax + N_DATA + rdx*8], rcx
        je 4f
        inc edx
        jmp 2b
3:      mov rdi, r12
        mov rsi, rbx
        call vec_push
4:      xor r13d, r13d
5:      cmp r13d, [rbx + N_AUX]
        jae 9f
        mov rdi, [rbx + N_DATA + r13*8]
        mov rsi, r12
        call sm_candidates
        inc r13d
        jmp 5b
9:      LEAVE
ENDF sm_candidates

# sm_replace(exp, old, new) -> rax: exp with old as new, wherever it is
FUNC sm_replace
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        cmp rbx, r12
        jne 1f
        mov rax, r13
        LEAVE
1:      test bl, 1
        jnz 8f
        test rbx, rbx
        jz 8f
        mov eax, [rbx + N_KIND]
        cmp eax, K_TUPLE
        je 2f
        cmp eax, K_LIST
        jne 8f
2:      mov edi, [rbx + N_AUX]
        call vec_new_cap
        mov r14, rax
        xor ecx, ecx
        push rcx
        push rcx
3:      mov rcx, [rsp]
        cmp ecx, [rbx + N_AUX]
        jae 4f
        mov rdi, [rbx + N_DATA + rcx*8]
        mov rsi, r12
        mov rdx, r13
        call sm_replace
        mov rdi, r14
        mov rsi, rax
        call vec_push
        inc qword ptr [rsp]
        jmp 3b
4:      add rsp, 16
        mov rdi, r14
        cmp dword ptr [rbx + N_KIND], K_LIST
        je 5f
        call vec_to_tuple
        LEAVE
5:      call vec_to_list
        LEAVE
8:      mov rax, rbx
        LEAVE
ENDF sm_replace

# sm_abstract(cond, res, op, a, b) -> rax: python's abstract - the
# condition of a check of op(a, b), of the function's parameters
FUNC sm_abstract
        STACK_CHECK
        ENTER
        sub rsp, 48
        .set SA_RES, 0
        .set SA_OP, 8
        .set SA_A, 16
        .set SA_B, 24
        .set SA_I, 32
        .set SA_VEC, 40
        mov rbx, rdi
        mov [rsp + SA_RES], rsi
        mov [rsp + SA_OP], rdx
        mov [rsp + SA_A], rcx
        mov [rsp + SA_B], r8
        cmp rbx, rsi
        jne 1f
        mov edi, edx
        call sm_result
        jmp 9f
1:      cmp rbx, rcx
        jne 2f
        call sm_param_a
        jmp 9f
2:      test r8, r8
        jz 3f
        cmp rbx, r8
        jne 3f
        call sm_param_b
        jmp 9f
3:      test bl, 1
        jnz 8f
        test rbx, rbx
        jz 8f
        cmp dword ptr [rbx + N_KIND], K_TUPLE
        jne 8f
        mov edi, [rbx + N_AUX]
        call vec_new_cap
        mov [rsp + SA_VEC], rax
        mov qword ptr [rsp + SA_I], 0
4:      mov rcx, [rsp + SA_I]
        cmp ecx, [rbx + N_AUX]
        jae 5f
        mov rdi, [rbx + N_DATA + rcx*8]
        mov rsi, [rsp + SA_RES]
        mov rdx, [rsp + SA_OP]
        mov rcx, [rsp + SA_A]
        mov r8, [rsp + SA_B]
        call sm_abstract
        mov rdi, [rsp + SA_VEC]
        mov rsi, rax
        call vec_push
        inc qword ptr [rsp + SA_I]
        jmp 4b
5:      mov rdi, [rsp + SA_VEC]
        call vec_to_tuple
        jmp 9f
8:      mov rax, rbx
9:      add rsp, 48
        LEAVE
ENDF sm_abstract

# sm_transparent(line) -> eax: a string, or a setvar, setmem, set, store,
# log - what runs between the checks and the use of their result, as long
# as it changes nothing they read
FUNC sm_transparent
        ENTER
        mov rbx, rdi
        call is_str
        test eax, eax
        jnz 1f
        mov rdi, rbx
        call opcode_of
        cmp eax, OP_SETVAR
        je 1f
        cmp eax, OP_SETMEM
        je 1f
        cmp eax, OP_SET
        je 1f
        cmp eax, OP_STORE
        je 1f
        cmp eax, OP_LOG
        je 1f
        xor eax, eax
        LEAVE
1:      mov eax, 1
        LEAVE
ENDF sm_transparent

# sm_uses(out, lines, j, res, call): python's _uses of lines[j:] (a vec)
# appended to out - the call in place of the result, until a line changes
# what it reads (in that one, where it's read before: a write's value, an
# if's condition; not in a loop that changes it)
FUNC sm_uses
        STACK_CHECK
        ENTER
        sub rsp, 32
        .set SU_RES, 0
        .set SU_CALL, 8
        .set SU_CHANGES, 16
        mov rbx, rdi                    # out
        mov r12, rsi                    # lines
        mov r13, rdx                    # k
        mov [rsp + SU_RES], rcx
        mov [rsp + SU_CALL], r8
1:      cmp r13, [r12 + VEC_LEN]
        jae 9f
        mov rax, [r12 + VEC_DATA]
        mov r14, [rax + r13*8]          # the line
        mov rdi, r14
        mov rsi, [rsp + SU_RES]
        call changes_read
        mov [rsp + SU_CHANGES], eax
        test eax, eax
        jz 4f
        mov rdi, r14
        call opcode_of
        cmp eax, OP_WHILE
        je 7f                           # the rest as it is, from it
        cmp eax, OP_IF
        jne 4f
        # its condition only
        mov rdi, [r14 + N_DATA + 8]
        mov rsi, [rsp + SU_RES]
        mov rdx, [rsp + SU_CALL]
        call sm_replace
        mov edi, [r14 + N_AUX]
        lea rsi, [r14 + N_DATA]
        mov rdx, rax
        call sm_tuple_set1
        mov rdi, rbx
        mov rsi, rax
        call vec_push
        inc r13
        jmp 7f
4:      mov rdi, r14
        mov rsi, [rsp + SU_RES]
        mov rdx, [rsp + SU_CALL]
        call sm_replace
        mov rdi, rbx
        mov rsi, rax
        call vec_push
        inc r13
        cmp dword ptr [rsp + SU_CHANGES], 0
        jne 7f
        jmp 1b
7:      # the rest, as it is
        mov rax, [r12 + VEC_LEN]
        sub rax, r13
        jbe 9f
        mov rdx, rax
        mov rsi, [r12 + VEC_DATA]
        lea rsi, [rsi + r13*8]
        mov rdi, rbx
        call vec_extend
9:      add rsp, 32
        LEAVE
ENDF sm_uses

# sm_tuple_set1(count, elems, x) -> the tuple of the elems, x the second
FUNC sm_tuple_set1
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        call vec_new_cap
        mov r14, rax
        mov rdi, rax
        mov rsi, r12
        mov rdx, rbx
        call vec_extend
        mov rax, [r14 + VEC_DATA]
        mov [rax + 8], r13
        mov rdi, r14
        call vec_to_tuple
        LEAVE
ENDF sm_tuple_set1

# sm_of(lines, i, e, res, out) -> eax: python's _of of the checks lines[i:e]
# (a vec) - the operation they're all of, if res is its result (out as
# sm_match's)
FUNC sm_of
        STACK_CHECK
        ENTER
        sub rsp, 80
        .set SO_LINES, 0
        .set SO_I, 8
        .set SO_E, 16
        .set SO_RES, 24
        .set SO_OUT, 32
        .set SO_K, 40
        .set SO_M, 48                   # (3 words: another match)
        .set SO_D, 72
        mov [rsp + SO_LINES], rdi
        mov [rsp + SO_I], rsi
        mov [rsp + SO_E], rdx
        mov [rsp + SO_RES], rcx
        mov [rsp + SO_OUT], r8
        # the last one
        mov rax, [rdi + VEC_DATA]
        mov rbx, [rax + rdx*8 - 8]
        mov rdi, rbx
        call sm_check_fail
        mov rsi, rax
        mov rdi, [rbx + N_DATA + 8]
        mov rdx, [rsp + SO_RES]
        mov rcx, [rsp + SO_OUT]
        call sm_match
        test eax, eax
        jz .Lso_none
        mov rax, [rsp + SO_I]
        mov [rsp + SO_K], rax
.Lso_check:
        mov rcx, [rsp + SO_K]
        mov rax, [rsp + SO_E]
        dec rax
        cmp rcx, rax
        jae .Lso_yes
        mov rax, [rsp + SO_LINES]
        mov rax, [rax + VEC_DATA]
        mov rbx, [rax + rcx*8]          # the check
        mov rdi, rbx
        call sm_check_fail
        mov r12, rax                    # its failure
        # of it too, followed by the compiler's only
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, r12
        mov rdx, [rsp + SO_RES]
        lea rcx, [rsp + SO_M]
        call sm_match
        test eax, eax
        jz 3f
        mov rcx, [rsp + SO_OUT]
        mov rax, [rsp + SO_M]
        cmp rax, [rcx]
        jne 3f
        mov rax, [rsp + SO_M + 8]
        cmp rax, [rcx + 8]
        jne 3f
        mov rax, [rsp + SO_M + 16]
        cmp rax, [rcx + 16]
        jne 3f
        mov r13, [rsp + SO_K]
        inc r13
1:      cmp r13, [rsp + SO_E]
        jae .Lso_next                   # all of the later ones are
        mov rax, [rsp + SO_LINES]
        mov rax, [rax + VEC_DATA]
        mov rdi, [rax + r13*8]
        call sm_check_fail
        mov rdi, rax
        call sm_kind_id
        cmp eax, OP_INVALID
        je 2f
        cmp eax, OP_PANIC
        jne 3f
2:      inc r13
        jmp 1b
3:      # the compiler's check of a division a later one makes by a parameter
        mov rdi, [rbx + N_DATA + 8]
        call sm_zero_test
        test rax, rax
        jz .Lso_none
        mov r14, rax                    # d
        mov rdi, r12
        call sm_kind_id
        cmp eax, OP_INVALID
        je 4f
        mov rdi, r12
        mov esi, 0x12
        call sm_is_panic
        test eax, eax
        jz .Lso_none
4:      mov rdi, r14
        call .Lso_abstract
        mov [rsp + SO_D], rax
        call sm_param_a
        cmp rax, [rsp + SO_D]
        je 5f
        call sm_param_b
        cmp rax, [rsp + SO_D]
        jne .Lso_none
5:      mov r13, [rsp + SO_K]
        inc r13
6:      cmp r13, [rsp + SO_E]
        jae .Lso_none
        mov rax, [rsp + SO_LINES]
        mov rax, [rax + VEC_DATA]
        mov rax, [rax + r13*8]
        mov rdi, [rax + N_DATA + 8]
        call .Lso_abstract
        mov rsi, rax
        mov rdi, [rsp + SO_D]
        call sm_divides
        test eax, eax
        jnz .Lso_next
        inc r13
        jmp 6b
.Lso_next:
        inc qword ptr [rsp + SO_K]
        jmp .Lso_check
.Lso_yes:
        mov eax, 1
        add rsp, 80
        LEAVE
.Lso_none:
        xor eax, eax
        add rsp, 80
        LEAVE
# local: rax = sm_abstract(rdi, res, op, a, b) of the match in out
.Lso_abstract:
        sub rsp, 8
        mov rsi, [rsp + 16 + SO_RES]
        mov rax, [rsp + 16 + SO_OUT]
        mov rdx, [rax]
        mov rcx, [rax + 8]
        mov r8, [rax + 16]
        call sm_abstract
        add rsp, 8
        ret
ENDF sm_of

# sm_state: found (a vec of (key, messages)), in the conversions' order
.set SMS_FOUND, 0
.set SMS_SIZEOF, 8

# sm_convert(lines, i, state) -> rax: python's _convert - a vec of the
# lines after the checks from i on (those one after the other of the vec
# lines), their result a call where it's used, or 0
FUNC sm_convert
        STACK_CHECK
        ENTER
        sub rsp, 96
        .set SC_LINES, 0
        .set SC_I, 8
        .set SC_STATE, 16
        .set SC_END, 24
        .set SC_E, 32
        .set SC_J, 40
        .set SC_CANDS, 48
        .set SC_C, 56
        .set SC_M, 64                   # (3 words)
        .set SC_NOW, 88
        mov [rsp + SC_LINES], rdi
        mov [rsp + SC_I], rsi
        mov [rsp + SC_STATE], rdx
        mov rbx, rdi
        mov r12, rsi
1:      cmp r12, [rbx + VEC_LEN]
        jae 2f
        mov rax, [rbx + VEC_DATA]
        mov rdi, [rax + r12*8]
        call sm_is_check
        test eax, eax
        jz 2f
        inc r12
        jmp 1b
2:      mov [rsp + SC_END], r12
        mov [rsp + SC_E], r12
.Lsc_e:
        mov rax, [rsp + SC_E]
        cmp rax, [rsp + SC_I]
        jbe .Lsc_none
        mov [rsp + SC_J], rax
.Lsc_j:
        mov rcx, [rsp + SC_J]
        mov rbx, [rsp + SC_LINES]
        cmp rcx, [rbx + VEC_LEN]
        jae .Lsc_next_e
        mov rax, [rbx + VEC_DATA]
        mov r13, [rax + rcx*8]          # the line
        # what runs at once: an if's condition, not a loop's
        mov rdi, r13
        call opcode_of
        mov qword ptr [rsp + SC_NOW], 0
        cmp eax, OP_WHILE
        je 4f
        mov [rsp + SC_NOW], r13
        cmp eax, OP_IF
        jne 4f
        mov qword ptr [rsp + SC_NOW], 0
        cmp dword ptr [r13 + N_AUX], 1
        jbe 4f
        mov rax, [r13 + N_DATA + 8]
        mov [rsp + SC_NOW], rax
4:      cmp qword ptr [rsp + SC_NOW], 0
        je 6f
        call vec_new
        mov [rsp + SC_CANDS], rax
        mov rdi, [rsp + SC_NOW]
        mov rsi, rax
        call sm_candidates
        mov qword ptr [rsp + SC_C], 0
5:      mov rax, [rsp + SC_CANDS]
        mov rcx, [rsp + SC_C]
        cmp rcx, [rax + VEC_LEN]
        jae 6f
        mov rax, [rax + VEC_DATA]
        mov r14, [rax + rcx*8]          # res
        mov rdi, [rsp + SC_LINES]
        mov rsi, [rsp + SC_I]
        mov rdx, [rsp + SC_E]
        mov rcx, r14
        lea r8, [rsp + SC_M]
        call sm_of
        test eax, eax
        jnz .Lsc_found
        inc qword ptr [rsp + SC_C]
        jmp 5b
6:      # past it, if it can't fail and changes nothing they read
        mov rax, [rsp + SC_E]
        cmp rax, [rsp + SC_END]
        jb .Lsc_next_e
        mov rdi, r13
        call sm_transparent
        test eax, eax
        jz .Lsc_next_e
        mov r12, [rsp + SC_I]
7:      cmp r12, [rsp + SC_E]
        jae 8f
        mov rax, [rsp + SC_LINES]
        mov rax, [rax + VEC_DATA]
        mov rax, [rax + r12*8]
        mov rsi, [rax + N_DATA + 8]
        mov rdi, r13
        call changes_read
        test eax, eax
        jnz .Lsc_next_e
        inc r12
        jmp 7b
8:      inc qword ptr [rsp + SC_J]
        jmp .Lsc_j
.Lsc_next_e:
        dec qword ptr [rsp + SC_E]
        jmp .Lsc_e
.Lsc_found:
        # lines[e:j] + the uses, the call in place of the result
        mov rdi, [rsp + SC_LINES]
        mov rsi, [rsp + SC_I]
        mov rdx, [rsp + SC_E]
        mov rcx, r14
        lea r8, [rsp + SC_M]
        mov r9, [rsp + SC_STATE]
        call sm_record
        mov r12, rax                    # the call
        call vec_new
        mov rbx, rax
        mov rax, [rsp + SC_LINES]
        mov rsi, [rax + VEC_DATA]
        mov rcx, [rsp + SC_E]
        lea rsi, [rsi + rcx*8]
        mov rdx, [rsp + SC_J]
        sub rdx, rcx
        mov rdi, rbx
        call vec_extend
        mov rdi, rbx
        mov rsi, [rsp + SC_LINES]
        mov rdx, [rsp + SC_J]
        mov rcx, r14
        mov r8, r12
        call sm_uses
        mov rax, rbx
        add rsp, 96
        LEAVE
.Lsc_none:
        xor eax, eax
        add rsp, 96
        LEAVE
ENDF sm_convert

# sm_record(lines, i, e, res, m, state) -> rax: python's _call but the
# uses - the key and the messages of the checks lines[i:e] found, the
# temporary call ('safemath', index, a[, b])
FUNC sm_record
        ENTER
        sub rsp, 64
        .set SR_LINES, 0
        .set SR_I, 8
        .set SR_E, 16
        .set SR_RES, 24
        .set SR_M, 32
        .set SR_STATE, 40
        .set SR_KEY, 48
        .set SR_MSGS, 56
        mov [rsp + SR_LINES], rdi
        mov [rsp + SR_I], rsi
        mov [rsp + SR_E], rdx
        mov [rsp + SR_RES], rcx
        mov [rsp + SR_M], r8
        mov [rsp + SR_STATE], r9
        call vec_new
        mov [rsp + SR_KEY], rax
        call vec_new
        mov [rsp + SR_MSGS], rax
        mov rax, [rsp + SR_M]
        lea rcx, [rip + opcode_nodes]
        mov edx, [rax]
        mov rsi, [rcx + rdx*8]
        mov rdi, [rsp + SR_KEY]
        call vec_push                   # (op,)
        mov r12, [rsp + SR_I]
1:      cmp r12, [rsp + SR_E]
        jae 3f
        mov rax, [rsp + SR_LINES]
        mov rax, [rax + VEC_DATA]
        mov rbx, [rax + r12*8]
        mov rdi, rbx
        call sm_check_fail
        mov r13, rax                    # its failure
        mov rax, [rsp + SR_M]
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, [rsp + SR_RES]
        mov edx, [rax]
        mov rcx, [rax + 8]
        mov r8, [rax + 16]
        call sm_abstract
        mov r14, rax
        mov rdi, r13
        call sm_kind_id
        mov rsi, r13
        cmp eax, OP_ERROR
        jne 2f
        mov rdi, [rsp + SR_MSGS]
        mov rsi, [r13 + N_DATA + 8]
        call vec_push
        mov edi, OP_ERROR
        xor esi, esi
        call sm_fail
        mov rsi, rax                    # ('error',)
2:      mov rdi, r14
        call mk2                        # (check, kind)
        mov rdi, [rsp + SR_KEY]
        mov rsi, rax
        call vec_push
        inc r12
        jmp 1b
3:      mov rdi, [rsp + SR_KEY]
        call vec_to_tuple
        mov rbx, rax
        mov rdi, [rsp + SR_MSGS]
        call vec_to_tuple
        mov rsi, rax
        mov rdi, rbx
        call mk2                        # (key, messages)
        mov rcx, [rsp + SR_STATE]
        mov rdi, [rcx + SMS_FOUND]
        mov rbx, [rdi + VEC_LEN]        # its index
        mov rsi, rax
        call vec_push
        # ('safemath', index, a[, b])
        call vec_new
        mov r12, rax
        mov rdi, rax
        LOADS rsi, SAFEMATH
        call vec_push
        lea rsi, [rbx*2 + 1]
        mov rdi, r12
        call vec_push
        mov rax, [rsp + SR_M]
        mov rdi, r12
        mov rsi, [rax + 8]
        call vec_push
        mov rax, [rsp + SR_M]
        mov rsi, [rax + 16]
        test rsi, rsi
        jz 4f
        mov rdi, r12
        call vec_push
4:      mov rdi, r12
        call vec_to_tuple
        add rsp, 64
        LEAVE
ENDF sm_record

# sm_block(lines, state) -> list: python's block - the lines (a list),
# their checked arithmetic calls
FUNC sm_block
        STACK_CHECK
        ENTER
        sub rsp, 32
        .set SB2_STATE, 0
        .set SB2_OUT, 8
        .set SB2_LINES, 16
        mov [rsp + SB2_STATE], rsi
        mov rbx, rdi
        mov edi, [rbx + N_AUX]
        call vec_new_cap
        mov [rsp + SB2_LINES], rax
        mov rdi, rax
        mov rsi, rbx
        call vec_extend_seq
        call vec_new
        mov [rsp + SB2_OUT], rax
        xor r12d, r12d                  # i
1:      mov rbx, [rsp + SB2_LINES]
        cmp r12, [rbx + VEC_LEN]
        jae 9f
        mov rax, [rbx + VEC_DATA]
        mov rdi, [rax + r12*8]
        call sm_is_check
        test eax, eax
        jz 3f
        mov rdi, [rsp + SB2_LINES]
        mov rsi, r12
        mov rdx, [rsp + SB2_STATE]
        call sm_convert
        test rax, rax
        jz 3f
        # lines[:i] + the rest
        mov r13, rax
        mov rbx, [rsp + SB2_LINES]
        mov [rbx + VEC_LEN], r12
        mov rdi, rbx
        mov rsi, [r13 + VEC_DATA]
        mov rdx, [r13 + VEC_LEN]
        call vec_extend
        jmp 1b
3:      mov rbx, [rsp + SB2_LINES]
        mov rax, [rbx + VEC_DATA]
        mov rdi, [rax + r12*8]
        mov rsi, [rsp + SB2_STATE]
        call sm_inside
        mov rdi, [rsp + SB2_OUT]
        mov rsi, rax
        call vec_push
        inc r12
        jmp 1b
9:      mov rdi, [rsp + SB2_OUT]
        call vec_to_list
        add rsp, 32
        LEAVE
ENDF sm_block

# sm_inside(line, state) -> rax: python's inside - the line, the checked
# arithmetic of its branches calls
FUNC sm_inside
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call opcode_of
        cmp eax, OP_IF
        je 1f
        cmp eax, OP_WHILE
        je 5f
        jmp 8f
1:      cmp dword ptr [rbx + N_AUX], 2
        jb 8f
        mov edi, [rbx + N_AUX]
        call vec_new_cap
        mov r13, rax
        mov rdi, rax
        lea rsi, [rbx + N_DATA]
        mov edx, 2
        call vec_extend
        mov r14d, 2
2:      cmp r14d, [rbx + N_AUX]
        jae 4f
        mov rdi, [rbx + N_DATA + r14*8]
        call is_list
        mov rsi, [rbx + N_DATA + r14*8]
        test eax, eax
        jz 3f
        mov rdi, rsi
        mov rsi, r12
        call sm_block
        mov rsi, rax
3:      mov rdi, r13
        call vec_push
        inc r14d
        jmp 2b
4:      mov rdi, r13
        call vec_to_tuple
        LEAVE
5:      cmp dword ptr [rbx + N_AUX], 3
        jb 8f
        mov rdi, [rbx + N_DATA + 16]
        call is_list
        test eax, eax
        jz 8f
        mov rdi, [rbx + N_DATA + 16]
        mov rsi, r12
        call sm_block
        mov r13, rax
        mov edi, [rbx + N_AUX]
        lea rsi, [rbx + N_DATA]
        call sm_tuple_copy
        mov rcx, [rax + VEC_DATA]
        mov [rcx + 16], r13
        mov rdi, rax
        call vec_to_tuple
        LEAVE
8:      mov rax, rbx
        LEAVE
ENDF sm_inside

# sm_tuple_copy(count, elems) -> vec of them
FUNC sm_tuple_copy
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call vec_new_cap
        mov r13, rax
        mov rdi, rax
        mov rsi, r12
        mov rdx, rbx
        call vec_extend
        mov rax, r13
        LEAVE
ENDF sm_tuple_copy

# safemath_rewrite(asts) -> rax: (asts, defs) - python's rewrite: the asts
# (a list of them, 0 for a function that has none), their checked
# arithmetic calls of the contract's SafeMath functions; defs the
# functions, (name, key, varying, first) in the order of the block
FUNC safemath_rewrite
        ENTER
        sub rsp, 80
        .set SW_ASTS, 0
        .set SW_STATE, 8                # (SMS_SIZEOF)
        .set SW_NEW, 16
        .set SW_KEYS, 24
        .set SW_MSGS, 32                # for each key, the vec of its messages
        .set SW_DEFS, 40
        .set SW_NAMES, 48               # for each key, its name
        .set SW_VARYING, 56             # for each key, its varying
        .set SW_I, 64
        mov [rsp + SW_ASTS], rdi
        call vec_new
        mov [rsp + SW_STATE], rax
        call vec_new
        mov [rsp + SW_NEW], rax
        mov rbx, [rsp + SW_ASTS]
        xor r12d, r12d
1:      cmp r12d, [rbx + N_AUX]
        jae 3f
        mov r13, [rbx + N_DATA + r12*8]
        mov rdi, r13
        call is_none
        test eax, eax
        jnz 2f
        mov rdi, r13
        lea rsi, [rsp + SW_STATE]
        call sm_block
        mov r13, rax
2:      mov rdi, [rsp + SW_NEW]
        mov rsi, r13
        call vec_push
        inc r12d
        jmp 1b
3:      # the keys, in the order they're found, each with its messages
        call vec_new
        mov [rsp + SW_KEYS], rax
        call vec_new
        mov [rsp + SW_MSGS], rax
        mov rax, [rsp + SW_STATE]
        xor r12d, r12d
4:      mov rax, [rsp + SW_STATE]
        cmp r12, [rax + VEC_LEN]
        jae 7f
        mov rax, [rax + VEC_DATA]
        mov r13, [rax + r12*8]          # (key, messages)
        mov rdi, [rsp + SW_KEYS]
        mov rsi, [r13 + N_DATA]
        call sm_vec_index
        test rax, rax
        jns 5f
        mov rdi, [rsp + SW_KEYS]
        mov rsi, [r13 + N_DATA]
        call vec_push
        call vec_new
        mov rsi, rax
        mov rdi, [rsp + SW_MSGS]
        call vec_push
        mov rax, [rsp + SW_KEYS]
        mov rax, [rax + VEC_LEN]
        dec rax
5:      mov rcx, [rsp + SW_MSGS]
        mov rcx, [rcx + VEC_DATA]
        mov rdi, [rcx + rax*8]
        mov rsi, [r13 + N_DATA + 8]
        call vec_push
        inc r12
        jmp 4b
7:      # the names, op by op, and the varying messages
        call vec_new
        mov [rsp + SW_DEFS], rax
        mov rax, [rsp + SW_KEYS]
        mov rdi, [rax + VEC_LEN]
        call vec_new_cap
        mov [rsp + SW_NAMES], rax
        mov rdi, rax
        mov rax, [rsp + SW_KEYS]
        mov rsi, [rax + VEC_LEN]
        call vec_resize
        mov rax, [rsp + SW_KEYS]
        mov rdi, [rax + VEC_LEN]
        call vec_new_cap
        mov [rsp + SW_VARYING], rax
        mov rdi, rax
        mov rax, [rsp + SW_KEYS]
        mov rsi, [rax + VEC_LEN]
        call vec_resize
        lea rax, [rip + sm_ops]
        mov [rsp + SW_I], rax
.Lsw_op:
        mov rax, [rsp + SW_I]
        mov ebx, [rax]                  # the op
        test ebx, ebx
        jz .Lsw_calls
        xor r13d, r13d                  # its count
        xor r12d, r12d                  # the key
.Lsw_key:
        mov rax, [rsp + SW_KEYS]
        cmp r12, [rax + VEC_LEN]
        jae .Lsw_next_op
        mov rax, [rax + VEC_DATA]
        mov r14, [rax + r12*8]
        mov rax, [r14 + N_DATA]         # key[0], the op's string
        mov eax, [rax + N_AUX]
        and eax, STR_ID_MASK
        cmp eax, ebx
        jne .Lsw_skip
        inc r13d
        # the name: op, op2, op3...
        lea rax, [rip + opcode_nodes]
        mov rdi, [rax + rbx*8]
        mov esi, r13d
        call sm_name
        mov rcx, [rsp + SW_NAMES]
        mov rcx, [rcx + VEC_DATA]
        mov [rcx + r12*8], rax
        # varying: the positions where a message differs from the first's
        mov rcx, [rsp + SW_MSGS]
        mov rcx, [rcx + VEC_DATA]
        mov rdi, [rcx + r12*8]
        call sm_varying
        mov rcx, [rsp + SW_VARYING]
        mov rcx, [rcx + VEC_DATA]
        mov [rcx + r12*8], rax
        # (name, key, varying, first)
        mov rcx, [rsp + SW_MSGS]
        mov rcx, [rcx + VEC_DATA]
        mov rcx, [rcx + r12*8]
        mov rcx, [rcx + VEC_DATA]
        mov rcx, [rcx]                  # the first messages
        mov rdx, [rsp + SW_VARYING]
        mov rdx, [rdx + VEC_DATA]
        mov rdx, [rdx + r12*8]
        mov rsi, [rsp + SW_NAMES]
        mov rsi, [rsi + VEC_DATA]
        mov rdi, [rsi + r12*8]
        mov rsi, r14
        call mk4
        mov rdi, [rsp + SW_DEFS]
        mov rsi, rax
        call vec_push
.Lsw_skip:
        inc r12
        jmp .Lsw_key
.Lsw_next_op:
        add qword ptr [rsp + SW_I], 4
        jmp .Lsw_op
.Lsw_calls:
        # the calls named
        mov rbx, [rsp + SW_NEW]
        xor r12d, r12d
8:      cmp r12, [rbx + VEC_LEN]
        jae 9f
        mov rax, [rbx + VEC_DATA]
        mov rdi, [rax + r12*8]
        test rdi, rdi
        jz 81f
        lea rsi, [rsp]
        call sm_name_calls
        mov rcx, [rbx + VEC_DATA]
        mov [rcx + r12*8], rax
81:     inc r12
        jmp 8b
9:      mov rdi, rbx
        call vec_to_list
        mov rbx, rax
        mov rdi, [rsp + SW_DEFS]
        call vec_to_list
        mov rsi, rax
        mov rdi, rbx
        call mk2
        add rsp, 80
        LEAVE
ENDF safemath_rewrite

# sm_vec_index(vec, x) -> rax: the index of x (by pointer), -1 if none
FUNC sm_vec_index
        mov rcx, [rdi + VEC_DATA]
        mov rdx, [rdi + VEC_LEN]
        xor eax, eax
1:      cmp rax, rdx
        jae 2f
        cmp [rcx + rax*8], rsi
        je 3f
        inc rax
        jmp 1b
2:      mov rax, -1
3:      ret
ENDF sm_vec_index

# sm_name(op_str, n) -> rax: op, or op followed by n past the first
FUNC sm_name
        ENTER
        mov rbx, rdi
        mov r12d, esi
        cmp r12d, 1
        jne 1f
        mov rax, rbx
        LEAVE
1:      call sb_new
        mov r13, rax
        mov rdi, rax
        mov rsi, rbx
        call sb_append_str
        mov rdi, r13
        mov esi, r12d
        call sb_append_u64
        mov rdi, [r13 + SB_BUF]
        mov rsi, [r13 + SB_LEN]
        call str_intern
        mov r14, rax
        mov rdi, r13
        call sb_free
        mov rax, r14
        LEAVE
ENDF sm_name

# sm_varying(vec of messages tuples) -> tuple: the positions (tagged)
# where a tuple's message differs from the first's
FUNC sm_varying
        ENTER
        mov rbx, rdi
        call vec_new
        mov r12, rax
        mov rax, [rbx + VEC_DATA]
        mov r13, [rax]                  # the first
        xor r14d, r14d
1:      cmp r14d, [r13 + N_AUX]
        jae 9f
        mov rcx, [rbx + VEC_LEN]
        mov rdx, [rbx + VEC_DATA]
2:      test rcx, rcx
        jz 4f
        dec rcx
        mov rax, [rdx + rcx*8]
        mov rax, [rax + N_DATA + r14*8]
        cmp rax, [r13 + N_DATA + r14*8]
        je 2b
        lea rsi, [r14*2 + 1]
        mov rdi, r12
        call vec_push
4:      inc r14d
        jmp 1b
9:      mov rdi, r12
        call vec_to_tuple
        LEAVE
ENDF sm_varying

# sm_name_calls(exp, frame) -> rax: python's rewrite's call - the
# temporary calls named, with their varying messages (frame: the
# rewrite's stack frame)
FUNC sm_name_calls
        STACK_CHECK
        ENTER
        sub rsp, 32
        .set SN_FRAME, 0
        .set SN_VEC, 8
        .set SN_I, 16
        .set SN_ENTRY, 24
        mov rbx, rdi
        mov [rsp + SN_FRAME], rsi
        test bl, 1
        jnz 8f
        test rbx, rbx
        jz 8f
        mov eax, [rbx + N_KIND]
        cmp eax, K_TUPLE
        je 1f
        cmp eax, K_LIST
        jne 8f
1:      mov edi, [rbx + N_AUX]
        call vec_new_cap
        mov [rsp + SN_VEC], rax
        mov rdi, rbx
        call opcode_of
        cmp eax, OP_SAFEMATH
        jne 5f
        cmp dword ptr [rbx + N_AUX], 2
        jb 5f
        mov rax, [rbx + N_DATA + 8]
        test al, 1
        jz 5f                           # (named already: a string)
        # ('safemath', name) + its operands + its varying messages
        sar rax, 1
        mov rcx, [rsp + SN_FRAME]
        mov rcx, [rcx + SW_STATE]
        mov rcx, [rcx + VEC_DATA]
        mov r12, [rcx + rax*8]          # (key, messages)
        mov [rsp + SN_ENTRY], r12
        mov rdi, [rsp + SN_FRAME]
        mov rdi, [rdi + SW_KEYS]
        mov rsi, [r12 + N_DATA]
        call sm_vec_index
        mov r13, rax                    # the key's index
        mov rdi, [rsp + SN_VEC]
        LOADS rsi, SAFEMATH
        call vec_push
        mov rcx, [rsp + SN_FRAME]
        mov rcx, [rcx + SW_NAMES]
        mov rcx, [rcx + VEC_DATA]
        mov rsi, [rcx + r13*8]
        mov rdi, [rsp + SN_VEC]
        call vec_push
        mov qword ptr [rsp + SN_I], 2
2:      mov rcx, [rsp + SN_I]
        cmp ecx, [rbx + N_AUX]
        jae 3f
        mov rdi, [rbx + N_DATA + rcx*8]
        mov rsi, [rsp + SN_FRAME]
        call sm_name_calls
        mov rdi, [rsp + SN_VEC]
        mov rsi, rax
        call vec_push
        inc qword ptr [rsp + SN_I]
        jmp 2b
3:      mov rcx, [rsp + SN_FRAME]
        mov rcx, [rcx + SW_VARYING]
        mov rcx, [rcx + VEC_DATA]
        mov r14, [rcx + r13*8]          # varying
        xor r13d, r13d
4:      cmp r13d, [r14 + N_AUX]
        jae 7f
        mov rax, [r14 + N_DATA + r13*8]
        sar rax, 1
        mov rcx, [rsp + SN_ENTRY]
        mov rcx, [rcx + N_DATA + 8]     # its messages
        mov rax, [rcx + N_DATA + rax*8]
        lea rdi, [rax + N_DATA + 4]
        mov esi, [rax + N_DATA]
        xor edx, edx
        call pretty_text
        lea rdi, [rax + N_DATA + 4]     # (interned: the calls are hash-consed)
        mov esi, [rax + N_DATA]
        call str_intern
        mov rdi, [rsp + SN_VEC]
        mov rsi, rax
        call vec_push
        inc r13d
        jmp 4b
5:      xor r13d, r13d
6:      cmp r13d, [rbx + N_AUX]
        jae 7f
        mov rdi, [rbx + N_DATA + r13*8]
        mov rsi, [rsp + SN_FRAME]
        call sm_name_calls
        mov rdi, [rsp + SN_VEC]
        mov rsi, rax
        call vec_push
        inc r13d
        jmp 6b
7:      mov rdi, [rsp + SN_VEC]
        cmp dword ptr [rbx + N_KIND], K_LIST
        je 71f
        call vec_to_tuple
        jmp 9f
71:     call vec_to_list
        jmp 9f
8:      mov rax, rbx
9:      add rsp, 32
        LEAVE
ENDF sm_name_calls

# --- the printing ---

# sm_operands(name) -> eax: how many operands a function of the block
# takes - 1 for inc and dec (the name without its number), 2 for the others
FUNC sm_operands
        mov eax, [rdi + N_DATA]         # the length
        lea rcx, [rdi + N_DATA + 4]
1:      test eax, eax
        jz 3f
        movzx edx, byte ptr [rcx + rax - 1]
        sub edx, '0'
        cmp edx, 9
        ja 2f
        dec eax
        jmp 1b
2:      cmp eax, 3
        jne 3f
        movzx edx, word ptr [rcx]
        cmp byte ptr [rcx + 2], 'c'
        jne 3f
        cmp edx, 'i' | ('n' << 8)
        je 4f
        cmp edx, 'd' | ('e' << 8)
        je 4f
3:      mov eax, 2
        ret
4:      mov eax, 1
        ret
ENDF sm_operands

# sm_pretty_call(sb, exp, flags): python's prettify of ('safemath', name,
# operands..., messages...) appended - SafeMath.name(...): the operands
# prettified (flags: PF_COLOR or not), then the messages as they are,
# string literals
FUNC sm_pretty_call
        STACK_CHECK
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov [rsp], rdx
        lea rsi, [rip + .Ls_safemath_dot]
        call sb_append_c
        mov rdi, rbx
        mov rsi, [r12 + N_DATA + 8]
        call sb_append_str
        mov rdi, rbx
        mov esi, '('
        call sb_append_char
        mov rdi, [r12 + N_DATA + 8]
        call sm_operands
        lea r14d, [rax + 2]             # the first message
        mov r13d, 2
1:      cmp r13d, [r12 + N_AUX]
        jae 3f
        cmp r13d, 2
        je 2f
        mov rdi, rbx
        lea rsi, [rip + .Ls_comma]
        call sb_append_c
2:      mov rdi, rbx
        mov rsi, [r12 + N_DATA + r13*8]
        cmp r13d, r14d
        jae 21f
        mov rdx, [rsp]
        call sb_append_pret
        jmp 22f
21:     call sb_append_str
22:     inc r13d
        jmp 1b
3:      mov rdi, rbx
        mov esi, ')'
        call sb_append_char
        add rsp, 16
        LEAVE
ENDF sm_pretty_call

# sm_append_param(sb, n): the name of the n-th message parameter appended
# (errorMessage, errorMessage2...)
FUNC sm_append_param
        ENTER
        mov rbx, rdi
        mov r12d, esi
        lea rsi, [rip + .Ls_errorMessage]
        call sb_append_c
        test r12d, r12d
        jz 1f
        mov rdi, rbx
        lea esi, [r12 + 1]
        call sb_append_u64
1:      LEAVE
ENDF sm_append_param

# sm_fail_line(kind, message) -> rax: python's fail_line - the line a
# check fails with: its revert (the panic; a message - a string - as the
# words of an ABI-encoded string), its invalid
FUNC sm_fail_line
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        call sm_kind_id
        mov r14d, eax
        cmp eax, OP_INVALID
        jne 1f
        LOADS rdi, INVALID
        call mk1
        jmp 9f
1:      cmp eax, OP_REVERT
        jne 2f
        LOADS rdi, REVERT
        lea rsi, [rip + sp_none]
        call mk2
        jmp 9f
2:      # ('data', ('bytes', 4, selector), ...)
        call vec_new
        mov r13, rax
        mov rdi, rax
        LOADS rsi, DATA
        call vec_push
        mov edx, 0x4E487B71 * 2 + 1     # (PANIC)
        cmp r14d, OP_PANIC
        je 3f
        mov edx, 0x08C379A0 * 2 + 1     # (ERROR)
3:      LOADS rdi, BYTES
        mov esi, 9                      # (4)
        call mk3
        mov rdi, r13
        mov rsi, rax
        call vec_push
        cmp r14d, OP_PANIC
        jne 4f
        mov rdi, r13                    # its code
        mov rsi, [rbx + N_DATA + 8]
        call vec_push
        jmp 8f
4:      # 32, the length, the words of the bytes (zeros after them)
        mov rdi, r13
        mov esi, 65                     # (32)
        call vec_push
        mov eax, [r12 + N_DATA]
        lea rsi, [rax*2 + 1]
        mov rdi, r13
        call vec_push
        call sb_new
        mov [rsp], rax
        mov rdi, rax
        lea rsi, [r12 + N_DATA + 4]
        mov edx, [r12 + N_DATA]
        call sb_append
5:      mov rdi, [rsp]
        test qword ptr [rdi + SB_LEN], 31
        jz 6f
        xor esi, esi
        call sb_append_char
        jmp 5b
6:      xor r14d, r14d                  # the offset
7:      mov rax, [rsp]
        cmp r14, [rax + SB_LEN]
        jae 71f
        mov rdi, [rax + SB_BUF]
        add rdi, r14
        mov esi, 32
        call mk_int_bytes_be
        mov rdi, r13
        mov rsi, rax
        call vec_push
        add r14, 32
        jmp 7b
71:     mov rdi, [rsp]
        call sb_free
8:      mov rdi, r13
        call vec_to_tuple
        mov rsi, rax
        LOADS rdi, REVERT
        call mk2
9:      add rsp, 16
        LEAVE
ENDF sm_fail_line

# safemath_pretty(defs) -> list of str: python's pretty_defs - the lines
# of the block's functions: the head (the parameters a and b - a alone
# for inc and dec - and errorMessage, errorMessage2... where the messages
# differ; a comment where there are the compiler's checks, a panic), each
# check as an if that fails as it does (with its parameter, where its
# message differs), the result
FUNC safemath_pretty
        ENTER
        sub rsp, 48
        .set SPD_DEFS, 0
        .set SPD_OUT, 8
        .set SPD_I, 16
        .set SPD_J, 24                  # the check
        .set SPD_K, 32                  # its position among those with messages
        .set SPD_T, 40
        mov [rsp + SPD_DEFS], rdi
        call vec_new
        mov [rsp + SPD_OUT], rax
        mov qword ptr [rsp + SPD_I], 0
.Lspd_def:
        mov rax, [rsp + SPD_DEFS]
        mov rcx, [rsp + SPD_I]
        cmp ecx, [rax + N_AUX]
        jae .Lspd_done
        mov rbx, [rax + N_DATA + rcx*8] # (name, key, varying, first)
        mov r12, [rbx + N_DATA + 8]     # the key: (op,) + checks
        # "  def name(a, b, errorMessage...):", and the comment
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_two]
        call sb_append_c
        mov rdi, r13
        lea rsi, [rip + C_GREEN]
        call sb_append_c
        mov rdi, r13
        lea rsi, [rip + .Ls_def]
        call sb_append_c
        mov rdi, r13
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        mov rdi, r13
        mov rsi, [rbx + N_DATA]
        call sb_append_str
        mov rdi, r13
        lea rsi, [rip + .Ls_open_a]
        call sb_append_c
        mov rdi, [r12 + N_DATA]
        call sm_operands
        cmp eax, 1
        je 1f
        mov rdi, r13
        lea rsi, [rip + .Ls_comma_b]
        call sb_append_c
1:      xor r14d, r14d
2:      mov rax, [rbx + N_DATA + 16]    # varying
        cmp r14d, [rax + N_AUX]
        jae 3f
        mov rdi, r13
        lea rsi, [rip + .Ls_comma]
        call sb_append_c
        mov rdi, r13
        mov esi, r14d
        call sm_append_param
        inc r14d
        jmp 2b
3:      mov rdi, r13
        lea rsi, [rip + .Ls_close]
        call sb_append_c
        mov r14d, 1
4:      cmp r14d, [r12 + N_AUX]
        jae 6f
        mov rax, [r12 + N_DATA + r14*8]
        mov rdi, [rax + N_DATA + 8]     # its kind
        call sm_kind_id
        cmp eax, OP_PANIC
        je 5f
        inc r14d
        jmp 4b
5:      mov rdi, r13
        lea rsi, [rip + .Ls_two]
        call sb_append_c
        mov rdi, r13
        lea rsi, [rip + C_GRAY]
        call sb_append_c
        mov rdi, r13
        lea rsi, [rip + .Ls_solc8]
        call sb_append_c
        mov rdi, r13
        lea rsi, [rip + C_ENDC]
        call sb_append_c
6:      mov rdi, r13
        call sb_finish
        mov rdi, [rsp + SPD_OUT]
        mov rsi, rax
        call vec_push
        # the checks
        mov qword ptr [rsp + SPD_K], 0
        mov qword ptr [rsp + SPD_J], 1
.Lspd_check:
        mov rcx, [rsp + SPD_J]
        cmp ecx, [r12 + N_AUX]
        jae .Lspd_result
        mov r13, [r12 + N_DATA + rcx*8] # (cond, kind)
        mov rdi, [r13 + N_DATA + 8]
        call sm_kind_id
        xor esi, esi                    # (no message)
        cmp eax, OP_ERROR
        jne .Lspd_if
        # a message: the parameter's where it differs, else the first one's
        mov rax, [rbx + N_DATA + 16]    # varying
        mov rcx, [rsp + SPD_K]
        lea rcx, [rcx*2 + 1]
        xor r14d, r14d
7:      cmp r14d, [rax + N_AUX]
        jae 8f
        cmp [rax + N_DATA + r14*8], rcx
        je .Lspd_given
        inc r14d
        jmp 7b
8:      mov rax, [rbx + N_DATA + 24]    # first
        mov rcx, [rsp + SPD_K]
        mov rsi, [rax + N_DATA + rcx*8]
        inc qword ptr [rsp + SPD_K]
.Lspd_if:
        # pprint_logic([('if', cond, [fail_line(kind, message)])], 6)
        mov rdi, [r13 + N_DATA + 8]
        call sm_fail_line
        mov [rsp + SPD_T], rax
        mov edi, 1
        lea rsi, [rsp + SPD_T]
        call mk_list
        mov rdx, rax
        LOADS rdi, IF
        mov rsi, [r13 + N_DATA]
        call mk3
        call .Lspd_lines
        inc qword ptr [rsp + SPD_J]
        jmp .Lspd_check
.Lspd_given:
        inc qword ptr [rsp + SPD_K]
        # "      if " + prettify(cond, color, rem_bool) + ":"
        call sb_new
        mov [rsp + SPD_T], rax
        mov rdi, rax
        lea rsi, [rip + .Ls_if]
        call sb_append_c
        mov rdi, [rsp + SPD_T]
        mov rsi, [r13 + N_DATA]
        mov edx, PF_COLOR | PF_REM_BOOL
        call sb_append_pret
        mov rdi, [rsp + SPD_T]
        lea rsi, [rip + .Ls_colon]
        call sb_append_c
        mov rdi, [rsp + SPD_T]
        call sb_finish
        mov rdi, [rsp + SPD_OUT]
        mov rsi, rax
        call vec_push
        # "          revert with errorMessage..."
        call sb_new
        mov [rsp + SPD_T], rax
        mov rdi, rax
        lea rsi, [rip + .Ls_revert_w]
        call sb_append_c
        mov rdi, [rsp + SPD_T]
        mov esi, r14d
        call sm_append_param
        mov rdi, [rsp + SPD_T]
        call sb_finish
        mov rdi, [rsp + SPD_OUT]
        mov rsi, rax
        call vec_push
        inc qword ptr [rsp + SPD_J]
        jmp .Lspd_check
.Lspd_result:
        # pprint_logic([('return', RESULTS[op])], 6)
        mov rax, [r12 + N_DATA]
        mov edi, [rax + N_AUX]
        and edi, STR_ID_MASK
        call sm_result
        mov rsi, rax
        LOADS rdi, RETURN
        call mk2
        call .Lspd_lines
        inc qword ptr [rsp + SPD_I]
        jmp .Lspd_def
.Lspd_done:
        mov rdi, [rsp + SPD_OUT]
        call vec_to_list
        add rsp, 48
        LEAVE
# local: the lines of pprint_logic([rax], 6) appended
.Lspd_lines:
        sub rsp, 8
        mov [rsp + 16 + SPD_T], rax
        mov edi, 1
        lea rsi, [rsp + 16 + SPD_T]
        call mk_list
        mov rdi, rax
        mov esi, 6
        call pprint_logic
        mov rdi, [rsp + 16 + SPD_OUT]
        mov rsi, rax
        call vec_extend_seq
        add rsp, 8
        ret
ENDF safemath_pretty

        .section .note.GNU-stack,"",@progbits
