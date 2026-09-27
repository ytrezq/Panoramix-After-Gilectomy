# The symbolic stack (port of panoramix/stack.py): a vector of values with
# Stack.simplify applied to everything pushed, and Stack.cleanup.

.include "defs.inc"

        .text

# stack_simplify(exp) -> value (memoized)
FUNC stack_simplify
        ENTER
        mov rbx, rdi
        test dil, 1
        jnz .Lss_asis
        test rdi, rdi
        jz .Lss_asis
        cmp dword ptr [rbx + N_KIND], K_INT
        jne 1f
        # ints are wrapped to 256 bits
        mov rdi, rbx
        mov esi, 256
        call int_mod_2exp
        LEAVE
1:      cmp dword ptr [rbx + N_KIND], K_TUPLE
        jne .Lss_asis
        mov edi, MEMO_STACK_SIMPLIFY
        mov rsi, rbx
        call memo_get
        test rax, rax
        jz 2f
        LEAVE
2:      mov rdi, rbx
        call stack_simplify_impl
        mov r12, rax
        mov edi, MEMO_STACK_SIMPLIFY
        mov rsi, rbx
        mov rdx, rax
        call memo_put
        mov rax, r12
        LEAVE
.Lss_asis:
        test dil, 1
        jz 3f
        # small ints: & UINT_256_MAX is a no-op for non-negative ones;
        # negative small ints wrap
        mov rax, rdi
        sar rax, 1
        test rax, rax
        jns 4f
        mov esi, 256
        call int_mod_2exp
        LEAVE
4:      mov rax, rbx
        LEAVE
3:      mov rax, rbx
        LEAVE
ENDF stack_simplify

FUNC stack_simplify_impl
        ENTER
        mov rbx, rdi
        call opcode_of
        mov r12d, eax
        mov edi, eax
        call is_arith_op
        test eax, eax
        jz 1f
        mov rdi, rbx
        call arith_eval
        mov rbx, rax
        mov rdi, rbx
        call is_tuple
        test eax, eax
        jz .Lssi_done
1:      cmp dword ptr [rbx + N_AUX], 3
        jne .Lssi_asis
        mov r13, [rbx + N_DATA + 8]     # left
        mov r14, [rbx + N_DATA + 16]    # right
        cmp r12d, OP_AND
        je .Lssi_and
        cmp r12d, OP_DIV
        je .Lssi_div
        cmp r12d, OP_MUL
        je .Lssi_mul
        jmp .Lssi_asis
.Lssi_and:
        mov rdi, r13
        call to_mask
        test rax, rax
        jz 2f
        mov rdi, r14
        mov rsi, rax
        mov ecx, 1
        mov r8d, 1
        call alg_mask_op
        LEAVE
2:      mov rdi, r14
        call to_mask
        test rax, rax
        jz 3f
        mov rdi, r13
        mov rsi, rax
        mov ecx, 1
        mov r8d, 1
        call alg_mask_op
        LEAVE
3:      mov rdi, r13
        call to_neg_mask
        test rax, rax
        jz 4f
        mov rdi, r14
        mov rsi, rax
        call alg_neg_mask_op
        LEAVE
4:      mov rdi, r14
        call to_neg_mask
        test rax, rax
        jz .Lssi_asis
        mov rdi, r13
        mov rsi, rax
        call alg_neg_mask_op
        LEAVE
.Lssi_div:
        mov rdi, r14
        call to_exp2
        cmp rax, -1
        je .Lssi_asis
        test rax, rax
        jz .Lssi_asis
        # mask_op(left, size=256 - shift, offset=shift, shr=shift)
        mov rdi, r13
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
.Lssi_mul:
        mov rdi, r13
        call to_exp2
        cmp rax, -1
        je 5f
        test rax, rax
        jz 5f
        # mask_op(right, size=256 - shift, shl=shift)
        mov rdi, r14
        mov esi, 256
        sub rsi, rax
        TAG rsi
        mov edx, 1
        mov rcx, rax
        TAG rcx
        mov r8d, 1
        call alg_mask_op
        LEAVE
5:      mov rdi, r14
        call to_exp2
        cmp rax, -1
        je .Lssi_asis
        test rax, rax
        jz .Lssi_asis
        mov rdi, r13
        mov esi, 256
        sub rsi, rax
        TAG rsi
        mov edx, 1
        mov rcx, rax
        TAG rcx
        mov r8d, 1
        call alg_mask_op
        LEAVE
.Lssi_asis:
.Lssi_done:
        mov rax, rbx
        LEAVE
ENDF stack_simplify_impl

# stack_cleanup(vec): Stack.cleanup, in place
FUNC stack_cleanup
        ENTER
        mov rbx, rdi
        xor r12d, r12d
1:      cmp r12, [rbx + VEC_LEN]
        jae .Lsc_done
        mov rax, [rbx + VEC_DATA]
        mov r13, [rax + r12*8]
        mov rdi, r13
        call is_tuple
        test eax, eax
        jz .Lsc_next
        mov rdi, r13
        call opcode_of
        cmp eax, OP_LT
        je .Lsc_lt
        cmp eax, OP_ISZERO
        je .Lsc_iszero
        jmp .Lsc_next
.Lsc_lt:
        cmp dword ptr [r13 + N_AUX], 3
        jne .Lsc_next
        mov rdi, [r13 + N_DATA + 8]
        call is_int
        test eax, eax
        jz .Lsc_next
        mov rdi, [r13 + N_DATA + 16]
        call is_int
        test eax, eax
        jz .Lsc_next
        mov rdi, [r13 + N_DATA + 8]
        mov rsi, [r13 + N_DATA + 16]
        call int_cmp
        mov edi, 1
        cmp eax, -1
        jne 2f
        mov edi, 3
2:      call mk_bool_of
        jmp .Lsc_store
.Lsc_iszero:
        cmp dword ptr [r13 + N_AUX], 2
        jne .Lsc_next
        mov r14, [r13 + N_DATA + 8]
        mov rdi, r14
        call is_int
        test eax, eax
        jz 3f
        mov esi, 1
        cmp r14, 1
        jne 4f
        mov esi, 3
4:      mov rdi, rsi
        call mk_bool_of
        jmp .Lsc_store
3:      mov rdi, r14
        call opcode_of
        cmp eax, OP_BOOL
        jne 5f
        cmp dword ptr [r14 + N_AUX], 2
        jne 5f
        mov rdi, [r14 + N_DATA + 8]
        test dil, 1
        jz .Lsc_next
        # ('bool', 1 - x)
        mov esi, 3
        sub rsi, rdi
        inc rsi                         # tagged 1 - x
        mov rdi, rsi
        call mk_bool_of
        jmp .Lsc_store
5:      cmp eax, OP_ISZERO
        jne .Lsc_next
        cmp dword ptr [r14 + N_AUX], 2
        jne .Lsc_next
        mov rdi, [r14 + N_DATA + 8]
        call opcode_of
        cmp eax, OP_ISZERO
        je 6f
        cmp eax, OP_EQ
        je 6f
        cmp eax, OP_LT
        je 6f
        cmp eax, OP_GT
        je 6f
        cmp eax, OP_SLT
        je 6f
        cmp eax, OP_SGT
        je 6f
        mov rdi, [r14 + N_DATA + 8]
        call mk_bool_of
        jmp .Lsc_store
6:      mov rax, [r14 + N_DATA + 8]
.Lsc_store:
        mov rcx, [rbx + VEC_DATA]
        mov [rcx + r12*8], rax
.Lsc_next:
        inc r12
        jmp 1b
.Lsc_done:
        LEAVE
ENDF stack_cleanup

# fold_stacks(first, second, depth, &vars) -> rax: the folded stack (a
# tuple), vars = tuple of ('var', counter, first[idx], idx). The stacks are
# tuples of the same length; elements that differ become loop variables.
FUNC fold_stacks
        ENTER
        sub rsp, 32
        mov rbx, rdi                    # first (tuple)
        mov r12, rsi                    # second (tuple)
        mov r13, rdx                    # depth
        mov [rsp], rcx                  # &vars
        mov r14d, [rbx + N_AUX]         # len
        lea rdi, [r14*8]
        call arena_alloc
        mov [rsp + 8], rax              # folded elements: a copy of first's
        mov rdi, rax
        lea rsi, [rbx + N_DATA]
        lea rdx, [r14*8]
        call memcpy@PLT
        call vec_new
        mov [rsp + 16], rax             # the vars, as a vec
        mov rcx, r14
1:      test rcx, rcx
        jz 5f
        dec rcx
        mov [rsp + 24], rcx             # idx
        mov rdi, [rbx + N_DATA + rcx*8]
        mov rsi, [r12 + N_DATA + rcx*8]
        call values_equal
        mov rcx, [rsp + 24]
        test eax, eax
        jnz 1b
        # temp_var_counter = len - idx + depth * 1000
        mov rax, r14
        sub rax, rcx
        imul rdx, r13, 1000
        add rax, rdx
        TAG rax
        mov rsi, rax
        LOADS rdi, VAR
        mov rdx, [rbx + N_DATA + rcx*8]
        TAG rcx
        call mk4                        # ('var', counter, first[idx], idx)
        mov rdi, [rsp + 16]
        mov rsi, rax
        call vec_push
        mov rcx, [rsp + 24]
        mov rax, r14
        sub rax, rcx
        imul rdx, r13, 1000
        add rax, rdx
        TAG rax
        mov rsi, rax
        LOADS rdi, VAR
        call mk2                        # ('var', counter)
        mov rcx, [rsp + 24]
        mov rdx, [rsp + 8]
        mov [rdx + rcx*8], rax
        jmp 1b
5:      mov rdi, [rsp + 16]
        call vec_to_tuple
        mov rcx, [rsp]
        mov [rcx], rax
        mov rdi, r14
        mov rsi, [rsp + 8]
        call mk_tuple
        add rsp, 32
        LEAVE
ENDF fold_stacks

        .section .note.GNU-stack,"",@progbits
