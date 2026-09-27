# Masks (port of panoramix/core/masks.py): to_mask / to_neg_mask.
#
# Both return the pair (size, offset) as tagged values in rax, rdx, or
# rax = NIL for python's None.

.include "defs.inc"

        .text

# int_bit(v, i) -> eax: bit i of the integer value v, two's complement
# (python's `num & 2**i > 0`)
FUNC int_bit
        test dil, 1
        jz 1f
        mov rax, rdi
        sar rax, 1
        cmp rsi, 63
        jae 2f
        mov ecx, esi
        shr rax, cl
        and eax, 1
        ret
2:      shr rax, 63                     # the sign bit
        ret
1:      jmp int_tstbit
ENDF int_bit

# mask_of_int(num) -> (size, offset) or NIL: a single run of ones
FUNC mask_of_int
        ENTER
        mov rbx, rdi
        xor r12d, r12d                  # i
1:      cmp r12, 256
        jae 2f
        mov rdi, rbx
        mov rsi, r12
        call int_bit
        test eax, eax
        jnz 2f
        inc r12
        jmp 1b
2:      mov r13, r12                    # mask_pos
3:      cmp r12, 256
        jae 4f
        mov rdi, rbx
        mov rsi, r12
        call int_bit
        test eax, eax
        jz 4f
        inc r12
        jmp 3b
4:      mov r14, r12                    # mask_pos_plus_len
5:      cmp r12, 256
        jae 6f
        mov rdi, rbx
        mov rsi, r12
        call int_bit
        test eax, eax
        jnz 7f
        inc r12
        jmp 5b
6:      mov rax, r14
        sub rax, r13
        TAG rax
        mov rdx, r13
        TAG rdx
        LEAVE
7:      xor eax, eax
        LEAVE
ENDF mask_of_int

# neg_mask_of_int(num) -> (size, offset) or NIL: ones, a run of zeros, ones
FUNC neg_mask_of_int
        ENTER
        mov rbx, rdi
        xor r12d, r12d
1:      cmp r12, 256
        jae 2f
        mov rdi, rbx
        mov rsi, r12
        call int_bit
        test eax, eax
        jz 2f
        inc r12
        jmp 1b
2:      mov r13, r12
3:      cmp r12, 256
        jae 4f
        mov rdi, rbx
        mov rsi, r12
        call int_bit
        test eax, eax
        jnz 4f
        inc r12
        jmp 3b
4:      mov r14, r12
5:      cmp r12, 256
        jae 6f
        mov rdi, rbx
        mov rsi, r12
        call int_bit
        test eax, eax
        jz 7f
        inc r12
        jmp 5b
6:      mov rax, r14
        sub rax, r13
        TAG rax
        mov rdx, r13
        TAG rdx
        LEAVE
7:      xor eax, eax
        LEAVE
ENDF neg_mask_of_int

# to_mask(num) -> (rax, rdx) or NIL (memoized: the pair is stored as a tuple)
FUNC to_mask
        ENTER
        mov rbx, rdi
        call is_int
        test eax, eax
        jnz 1f
        # symbolic: memoized on the expression
        mov edi, MEMO_TO_MASK
        mov rsi, rbx
        call memo_get
        test rax, rax
        jz 2f
        cmp rax, MEMO_NONE
        je 3f
        mov rdx, [rax + N_DATA + 8]
        mov rax, [rax + N_DATA]
        LEAVE
3:      xor eax, eax
        LEAVE
2:      mov rdi, rbx
        call to_mask_impl
        test rax, rax
        jz 4f
        mov rdi, rax
        mov rsi, rdx
        call mk2
        mov r12, rax
        mov edi, MEMO_TO_MASK
        mov rsi, rbx
        mov rdx, rax
        call memo_put
        mov rdx, [r12 + N_DATA + 8]
        mov rax, [r12 + N_DATA]
        LEAVE
4:      mov edi, MEMO_TO_MASK
        mov rsi, rbx
        mov edx, MEMO_NONE
        call memo_put
        xor eax, eax
        LEAVE
1:      mov rdi, rbx
        call mask_of_int
        LEAVE
ENDF to_mask

FUNC to_mask_impl
        ENTER
        mov rdi, rdi
        call cleanup_mul_1
        mov rbx, rax
        mov rdi, rbx
        call opcode_of
        cmp eax, OP_NOT
        jne 1f
        cmp dword ptr [rbx + N_AUX], 2
        jne 1f
        mov rdi, [rbx + N_DATA + 8]
        call to_neg_mask
        LEAVE
1:      cmp eax, OP_SUB
        jne 2f
        cmp dword ptr [rbx + N_AUX], 3
        jne 2f
        cmp qword ptr [rbx + N_DATA + 16], 3   # num[2] == 1
        jne 2f
        mov r12, [rbx + N_DATA + 8]
        mov rdi, r12
        mov esi, OP_EXP
        mov edx, 3
        call is_op_n
        test eax, eax
        jz 2f
        # mul = to_exp2(base); mask_len = mul_op(mul, exponent); (mask_len, 256 - mask_len)
        mov rdi, [r12 + N_DATA + 8]
        call to_exp2
        cmp rax, -1
        je .Ltm_none
        mov rdi, rax
        TAG rdi
        mov rsi, [r12 + N_DATA + 16]
        call alg_mul2
        mov r13, rax
        mov edi, (256 << 1) | 1
        mov rsi, rax
        call alg_sub_op
        mov rdx, rax
        mov rax, r13
        LEAVE
2:      cmp eax, OP_ADD
        jne 3f
        cmp dword ptr [rbx + N_AUX], 3
        jne 3f
        mov rax, -1
        TAG rax
        cmp [rbx + N_DATA + 8], rax
        jne 3f
        # to_mask(('sub', num[2], 1))
        LOADS rdi, SUB
        mov rsi, [rbx + N_DATA + 16]
        mov edx, 3
        call mk3
        mov rdi, rax
        call to_mask
        LEAVE
3:      mov rdi, rbx
        call is_int
        test eax, eax
        jz .Ltm_none
        mov rdi, rbx
        call mask_of_int
        LEAVE
.Ltm_none:
        xor eax, eax
        LEAVE
ENDF to_mask_impl

# to_neg_mask(num) -> (rax, rdx) or NIL
FUNC to_neg_mask
        ENTER
        mov rbx, rdi
        call opcode_of
        cmp eax, OP_NOT
        jne 1f
        cmp dword ptr [rbx + N_AUX], 2
        jne 1f
        mov rdi, [rbx + N_DATA + 8]
        call to_mask
        LEAVE
1:      mov rdi, rbx
        call is_int
        test eax, eax
        jz 2f
        mov rdi, rbx
        call neg_mask_of_int
        LEAVE
2:      xor eax, eax
        LEAVE
ENDF to_neg_mask


# find_mask(num) -> rax, rdx: (size, offset), the byte-aligned mask that
# encompasses the number
FUNC find_mask
        ENTER
        mov rbx, rdi
        xor r12d, r12d                  # i
1:      cmp r12, 256
        jae 2f
        mov rdi, rbx
        mov rsi, r12
        call int_bit
        test eax, eax
        jnz 2f
        inc r12
        jmp 1b
2:      mov r13, r12
        and r13, -8                     # mask_pos = i - i % 8
        mov r14d, 256                   # mask_pos_plus_len
3:      cmp r12, 256
        jae 4f
        mov rdi, rbx
        mov rsi, r12
        call int_bit
        test eax, eax
        jz 5f
        mov r14, r12
        and r14, -8
        add r14, 8
5:      inc r12
        jmp 3b
4:      mov rax, r14
        sub rax, r13
        TAG rax
        mov rdx, r13
        TAG rdx
        LEAVE
ENDF find_mask

        .section .note.GNU-stack,"",@progbits
