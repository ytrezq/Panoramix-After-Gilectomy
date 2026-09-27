# Algebra (port of panoramix/core/algebra.py) - in progress; stubs first.

.include "defs.inc"

        .text

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
        add rsi, N_DATA + 8
        mov rax, [r13 + r14*8]
        mov edx, [rax + N_AUX]
        dec edx
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

# temporary stubs
FUNC alg_sub_op
        xor eax, eax
        ret
ENDF alg_sub_op

FUNC alg_le_op
        mov eax, TRI_CANNOT
        ret
ENDF alg_le_op

FUNC alg_lt_op
        mov eax, TRI_CANNOT
        ret
ENDF alg_lt_op

        .section .note.GNU-stack,"",@progbits
