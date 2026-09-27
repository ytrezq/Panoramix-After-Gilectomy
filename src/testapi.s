# Test entry point: pan_test(name, text, len, &out, &outlen) parses the
# python literal `text`, applies the function called `name` to it and
# renders the result with value_print. The functions take one value
# (a tuple of arguments when there are several) and return a value.

.include "defs.inc"

        .section .data.rel.ro
        .align 8
test_table:
        .quad .Ln_roundtrip, tf_roundtrip
        .quad .Ln_hash, tf_hash
        .quad .Ln_opcode, tf_opcode
        .quad .Ln_eval, arith_eval
        .quad .Ln_is_zero, is_zero
        .quad .Ln_simplify_bool, simplify_bool
        .quad .Ln_eval_bool, tf_eval_bool
        .quad .Ln_to_real_int, to_real_int
        .quad .Ln_add_op, tf_add_op
        .quad .Ln_mul_op, tf_mul_op
        .quad .Ln_sub_op, tf_2args_sub
        .quad .Ln_or_op, tf_or_op
        .quad .Ln_mask_op, tf_mask_op
        .quad .Ln_div_op, tf_div_op
        .quad .Ln_neg_mask_op, tf_neg_mask_op
        .quad .Ln_simplify, alg_simplify
        .quad .Ln_calc_max, alg_calc_max
        .quad .Ln_max_to_add, alg_max_to_add
        .quad .Ln_lt_op, tf_lt_op
        .quad .Ln_le_op, tf_le_op
        .quad .Ln_ge_zero, tf_ge_zero
        .quad .Ln_max_op, tf_max_op
        .quad .Ln_min_op, tf_min_op
        .quad .Ln_get_sign, tf_get_sign
        .quad .Ln_to_exp2, tf_to_exp2
        .quad 0, 0

        .section .rodata
.Ln_roundtrip: .asciz "roundtrip"
.Ln_hash:      .asciz "hash"
.Ln_opcode:    .asciz "opcode"
.Ln_eval:      .asciz "eval"
.Ln_is_zero:   .asciz "is_zero"
.Ln_simplify_bool: .asciz "simplify_bool"
.Ln_eval_bool: .asciz "eval_bool"
.Ln_to_real_int: .asciz "to_real_int"
.Ln_add_op:    .asciz "add_op"
.Ln_mul_op:    .asciz "mul_op"
.Ln_sub_op:    .asciz "sub_op"
.Ln_or_op:     .asciz "or_op"
.Ln_mask_op:   .asciz "mask_op"
.Ln_div_op:    .asciz "div_op"
.Ln_neg_mask_op: .asciz "neg_mask_op"
.Ln_simplify:  .asciz "simplify"
.Ln_calc_max:  .asciz "calc_max"
.Ln_max_to_add: .asciz "max_to_add"
.Ln_lt_op:     .asciz "lt_op"
.Ln_le_op:     .asciz "le_op"
.Ln_ge_zero:   .asciz "ge_zero"
.Ln_max_op:    .asciz "max_op"
.Ln_min_op:    .asciz "min_op"
.Ln_get_sign:  .asciz "get_sign"
.Ln_to_exp2:   .asciz "to_exp2"
.Ls_unknown_fn: .asciz "<unknown test function>"
.Ls_parse_err:  .asciz "<parse error at %u>"

        .text

FUNC tf_roundtrip
        mov rax, rdi
        ret
ENDF tf_roundtrip

# hash(v) -> the value's hash, as an integer
FUNC tf_hash
        ENTER
        call value_hash
        mov rdi, rax
        call mk_int_u64
        LEAVE
ENDF tf_hash

# opcode(v) -> the opcode id of a tuple
FUNC tf_opcode
        ENTER
        call opcode_of
        mov edi, eax
        call mk_int_u64
        LEAVE
ENDF tf_opcode

# eval_bool((exp, known_true, symbolic)) -> True/False/None
FUNC tf_eval_bool
        ENTER
        mov rbx, rdi
        mov rdi, [rbx + N_DATA]
        mov rsi, [rbx + N_DATA + 8]
        mov rdx, [rbx + N_DATA + 16]
        sar rdx, 1
        call eval_bool
        lea rcx, [rip + sp_none]
        lea rdx, [rip + sp_true]
        cmp eax, TRI_TRUE
        cmove rcx, rdx
        lea rdx, [rip + sp_false]
        cmp eax, TRI_FALSE
        cmove rcx, rdx
        mov rax, rcx
        LEAVE
ENDF tf_eval_bool

# variadic ones take the tuple of arguments
FUNC tf_add_op
        mov esi, [rdi + N_AUX]
        add rdi, N_DATA
        xchg rdi, rsi
        jmp alg_add_n
ENDF tf_add_op

FUNC tf_mul_op
        mov esi, [rdi + N_AUX]
        add rdi, N_DATA
        xchg rdi, rsi
        jmp alg_mul_n
ENDF tf_mul_op

FUNC tf_or_op
        mov esi, [rdi + N_AUX]
        add rdi, N_DATA
        xchg rdi, rsi
        jmp alg_or_n
ENDF tf_or_op

FUNC tf_2args_sub
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        jmp alg_sub_op
ENDF tf_2args_sub

FUNC tf_div_op
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        jmp alg_div_op
ENDF tf_div_op

# mask_op((exp, size, offset, shl, shr))
FUNC tf_mask_op
        mov r8, [rdi + N_DATA + 32]
        mov rcx, [rdi + N_DATA + 24]
        mov rdx, [rdi + N_DATA + 16]
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        jmp alg_mask_op
ENDF tf_mask_op

FUNC tf_neg_mask_op
        mov rdx, [rdi + N_DATA + 16]
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        jmp alg_neg_mask_op
ENDF tf_neg_mask_op

# tri_value(eax) -> rax: True/False/None/'CannotCompare'
FUNC tri_value
        ENTER
        mov ebx, edi
        lea rax, [rip + sp_true]
        cmp ebx, TRI_TRUE
        je 1f
        lea rax, [rip + sp_false]
        cmp ebx, TRI_FALSE
        je 1f
        lea rax, [rip + sp_none]
        cmp ebx, TRI_NONE
        je 1f
        lea rdi, [rip + .Ls_cannot]
        call str_intern_c
1:      LEAVE
ENDF tri_value

        .section .rodata
.Ls_cannot: .asciz "CannotCompare"
        .text

FUNC tf_lt_op
        ENTER
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        call alg_lt_op
        mov edi, eax
        call tri_value
        LEAVE
ENDF tf_lt_op

FUNC tf_le_op
        ENTER
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        call alg_le_op
        mov edi, eax
        call tri_value
        LEAVE
ENDF tf_le_op

FUNC tf_ge_zero
        ENTER
        call alg_ge_zero
        mov edi, eax
        call tri_value
        LEAVE
ENDF tf_ge_zero

FUNC tf_get_sign
        ENTER
        call alg_get_sign
        cmp eax, TRI_CANNOT
        je 1f
        cmp eax, SIGN_NONE
        je 2f
        movsxd rdi, eax
        call mk_int_i64
        LEAVE
1:      mov edi, TRI_CANNOT
        call tri_value
        LEAVE
2:      lea rax, [rip + sp_none]
        LEAVE
ENDF tf_get_sign

# max_op / min_op -> value or 'CannotCompare'
FUNC tf_max_op
        ENTER
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        call alg_max_op
        test rax, rax
        jnz 1f
        mov edi, TRI_CANNOT
        call tri_value
1:      LEAVE
ENDF tf_max_op

FUNC tf_min_op
        ENTER
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        call alg_min_op
        test rax, rax
        jnz 1f
        mov edi, TRI_CANNOT
        call tri_value
1:      LEAVE
ENDF tf_min_op

FUNC tf_to_exp2
        ENTER
        call to_exp2
        cmp rax, -1
        je 1f
        mov rdi, rax
        call mk_int_i64
        LEAVE
1:      lea rax, [rip + sp_none]
        LEAVE
ENDF tf_to_exp2

# pan_test(name, text, len, &out, &outlen) -> int
FUNC pan_test
        push r15
        ENTER
        sub rsp, 56
        mov [rsp], rdi                  # name
        mov [rsp + 8], rsi              # text
        mov [rsp + 16], rdx             # len
        mov [rsp + 24], rcx             # &out
        mov [rsp + 32], r8              # &outlen
        call pan_init
        call ctx_current
        mov [rsp + 40], rax
        call ctx_new
        mov r15, rax
        mov rdi, r15
        call ctx_bind
        call sb_new
        mov rbx, rax                    # output builder
        # find the function
        lea r12, [rip + test_table]
1:      mov rdi, [r12]
        test rdi, rdi
        jz .Lt_unknown
        mov rsi, [rsp]
        call strcmp@PLT
        test eax, eax
        jz 2f
        add r12, 16
        jmp 1b
2:      mov r13, [r12 + 8]              # the function
        mov rdi, [rsp + 8]
        mov rsi, [rsp + 16]
        call parse_literal
        test rax, rax
        jz .Lt_parse_err
        mov rdi, rax
        call r13
        mov rdi, rbx
        mov rsi, rax
        call value_print
        jmp .Lt_out
.Lt_unknown:
        mov rdi, rbx
        lea rsi, [rip + .Ls_unknown_fn]
        call sb_append_c
        jmp .Lt_out
.Lt_parse_err:
        mov rdi, rbx
        lea rsi, [rip + .Ls_parse_err]
        lea rdx, [rip + parse_error_pos]
        call sb_format
.Lt_out:
        mov rax, [rsp + 24]
        mov rcx, [rbx + SB_BUF]
        mov [rax], rcx
        mov rax, [rsp + 32]
        mov rcx, [rbx + SB_LEN]
        mov [rax], rcx
        mov rdi, rbx
        call free@PLT
        mov rdi, r15
        call ctx_free
        mov rdi, [rsp + 40]
        call ctx_bind
        xor eax, eax
        add rsp, 56
        LEAVE_NORET
        pop r15
        ret
ENDF pan_test

        .section .note.GNU-stack,"",@progbits
