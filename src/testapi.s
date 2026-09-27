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
