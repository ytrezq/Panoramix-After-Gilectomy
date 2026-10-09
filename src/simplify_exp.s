# Expression simplification (port of simplify.py's simplify_exp and its
# helpers): the rewrites applied to every expression of the trace.

.include "defs.inc"

        .section .rodata
.Ls_assert_mask:    .asciz "cleanup_mask_data: not a mask"

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

# int_cmp_pow8_22(v) -> eax: v > -(8^22) = -(2^66), read off the number
# (it is asked of every number simplify_exp meets)
FUNC int_cmp_pow8_22
        mov eax, 1
        test dil, 1
        jnz 1f                          # a small int: above -2^62
        movsxd rcx, dword ptr [rdi + N_DATA + MPZ_SIZE]
        test rcx, rcx
        jns 1f                          # not negative
        cmp rcx, -1
        je 1f                           # |v| < 2^64
        cmp rcx, -2
        jne 2f                          # |v| >= 2^128
        mov rcx, [rdi + N_DATA + MPZ_D]
        cmp qword ptr [rcx + 8], 4      # the high limb: |v| < 2^66?
        jb 1f
2:      xor eax, eax
1:      ret
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

# PATM "pattern": eax := pat_match(rbx, pattern, rsp), for the patterns
# whose head is a wildcard (PATX turns down a tuple of another head)
.macro PATM text
        PAT rsi, "\text"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
.endm

# simplify_exp_impl(exp) -> value, for a tuple: python's simplify_exp, its
# rules in its order
FUNC simplify_exp_impl
        STACK_CHECK
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 64
        .set SE_TMP, MATCH_BINDINGS_SIZE
        .set SE_TMP2, MATCH_BINDINGS_SIZE + 8
        .set SE_VEC, MATCH_BINDINGS_SIZE + 16
        .set SE_I, MATCH_BINDINGS_SIZE + 24
        .set SE_ACC, MATCH_BINDINGS_SIZE + 32
        # the operands that are numbers not wrapped in bytes, and the ones
        # that are bytes not of another width than they say
        call unwrap_bytes
        mov rbx, rax
        mov rdi, rax
        OPCODE_OF_RDI
        cmp eax, OP_BYTES
        jne .Lse_shr
        mov rdi, rbx
        call simplify_bytes
        jmp .Lse_done
.Lse_shr:
        # a shift by an amount the vm didn't know, known now (the word of
        # what it was made of)
        PATX "('shr', ':int:off', ':val')"
        test eax, eax
        jz .Lse_shl
        B rdi, 0
        mov esi, 256
        call int_mod_2exp
        mov rsi, rax
        B rdi, 1
        call alg_shr_op
        mov rbx, rax
.Lse_shl:
        # (see shl_op: a mask when it's known to be one)
        PATX "('shl', ':off', ':val')"
        test eax, eax
        jz .Lse_signextend
        B rdi, 0
        call is_int
        B rsi, 0
        test eax, eax
        jz 1f
        mov rdi, rsi
        mov esi, 256
        call int_mod_2exp
        mov rsi, rax
1:      B rdi, 1
        call alg_shl_op
        mov rbx, rax
.Lse_signextend:
        PATX "('signextend', ':b', ':val')"
        test eax, eax
        jz .Lse_mask0
        B rdi, 0
        B rsi, 1
        call alg_signextend_op
        mov rbx, rax
.Lse_mask0:
        # a mask of 0, whatever its size and offset
        PATX "('mask_shl', 'Any', 'Any', 'Any', 0)"
        test eax, eax
        jnz .Lse_ret0
        mov rdi, rbx
        OPCODE_OF_RDI
        cmp eax, OP_AND
        jne .Lse_iszero2
        mov rdi, rbx
        call simplify_and_terms
        mov rbx, rax
.Lse_iszero2:
        PATX "('iszero', ('iszero', ':e'))"
        test eax, eax
        jz 1f
        B rdi, 0
        call mk_bool_of
        mov rbx, rax
1:      PATX "('bool', ('bool', ':e'))"
        test eax, eax
        jz 2f
        B rdi, 0
        call mk_bool_of
        mov rbx, rax
2:      PATX "('eq', ':sth', 0)"
        test eax, eax
        jnz 3f
        PATX "('eq', 0, ':sth')"
        test eax, eax
        jz 4f
3:      B rdi, 0
        call mk_iszero_of
        mov rbx, rax
4:      # a truth value is 1 when it's true
        PATX "('eq', ':sth', 1)"
        test eax, eax
        jnz 5f
        PATX "('eq', 1, ':sth')"
        test eax, eax
        jz .Lse_cmp_c
5:      B rdi, 0
        call is_bool
        test eax, eax
        jz .Lse_cmp_c
        B rbx, 0
.Lse_cmp_c:
        # a comparison that what's compared can't make true, or false
        PATM "(':op', ':a', ':int:c')"
        test eax, eax
        jz .Lse_c_cmp
        B rdi, 0
        call str_id
        IN_OPSET cmp4, rax
        je .Lse_c_cmp
        mov [rsp + SE_TMP2], rax        # the op
        B rdi, 1
        call max_value
        mov [rsp + SE_TMP], rax         # top
        B rdi, 2
        mov esi, 256
        call int_mod_2exp
        mov rsi, rax
        mov rdi, [rsp + SE_TMP]
        call int_cmp                    # top against c
        mov rcx, [rsp + SE_TMP2]
        cmp ecx, OP_GT
        jne 1f
        test eax, eax                   # gt: top <= c
        jle .Lse_ret0
        jmp .Lse_c_cmp
1:      cmp ecx, OP_GE
        jne 2f
        test eax, eax                   # ge: top < c
        js .Lse_ret0
        jmp .Lse_c_cmp
2:      cmp ecx, OP_LT
        jne 3f
        test eax, eax                   # lt: top < c
        js .Lse_ret1
        jmp .Lse_c_cmp
3:      test eax, eax                   # le: top <= c
        jle .Lse_ret1
.Lse_c_cmp:
        PATM "(':op', ':int:c', ':a')"
        test eax, eax
        jz .Lse_neg
        B rdi, 0
        call str_id
        IN_OPSET cmp4, rax
        je .Lse_neg
        mov [rsp + SE_TMP2], rax
        B rdi, 2
        call max_value
        mov [rsp + SE_TMP], rax
        B rdi, 1
        mov esi, 256
        call int_mod_2exp
        mov rsi, rax
        mov rdi, [rsp + SE_TMP]
        call int_cmp                    # top against c
        mov rcx, [rsp + SE_TMP2]
        cmp ecx, OP_LT
        jne 1f
        test eax, eax                   # c < x, top <= c
        jle .Lse_ret0
        jmp .Lse_neg
1:      cmp ecx, OP_LE
        jne 2f
        test eax, eax                   # c <= x, top < c
        js .Lse_ret0
        jmp .Lse_neg
2:      cmp ecx, OP_GT
        jne 3f
        test eax, eax                   # c > x, top < c
        js .Lse_ret1
        jmp .Lse_neg
3:      test eax, eax                   # c >= x, top <= c
        jle .Lse_ret1
.Lse_neg:
        # -x is 0 when x is
        PATM "(':op', ('mul', -1, ':x'))"
        test eax, eax
        jz 2f
        B rdi, 0
        call str_id
        cmp eax, OP_ISZERO
        je 1f
        cmp eax, OP_BOOL
        jne 2f
1:      B rdi, 0
        B rsi, 1
        call mk2
        mov rbx, rax
2:      # a xor b is 0 when they're equal
        PATX "('iszero', ('xor', ':a', ':b'))"
        test eax, eax
        jz 3f
        LOADS rdi, EQ
        B rsi, 0
        B rdx, 1
        call mk3
        mov rbx, rax
3:      # a word of the calldata
        PATX "('call.data', ':int:pos', 32)"
        test eax, eax
        jz 4f
        LOADS rdi, CD
        B rsi, 0
        call mk2
        jmp .Lse_done
4:      # past the end of the calldata: zeroes (Vyper copies them to clear
        # the memory)
        PATX "('call.data', 'calldatasize', ':int:size')"
        test eax, eax
        jz 5f
        LOADS rdi, BYTES
        B rsi, 0
        mov edx, 1
        call mk3
        jmp .Lse_done
5:      PATX "('iszero', ('add', ':int:c', ':x'))"
        test eax, eax
        jz 6f
        B rdi, 1
        B rsi, 0
        call equals
        mov rbx, rax
        jmp .Lse_ceil
6:      PATX "('iszero', ':diff')"
        test eax, eax
        jz .Lse_ceil
        B rdi, 0
        call difference_eq
        test rax, rax
        jz .Lse_ceil
        mov rbx, rax
.Lse_ceil:
        # floor32(num + x) = (num - 31) + floor32(31 + x), num - 31 being a
        # multiple of 32 - with a mask up to the top of the word
        PATX "('mask_shl', ':int:size', 5, 0, ('add', ':int:num', '...'))"
        test eax, eax
        jz .Lse_iszero_mask
        B rdi, 0
        mov esi, (251 << 1) | 1
        call int_cmp
        test eax, eax
        js .Lse_iszero_mask             # size + 5 >= 256
        B rdi, 1
        mov esi, 5
        call int_mod_2exp
        cmp rax, (31 << 1) | 1
        jne .Lse_iszero_mask            # num % 32 == 31
        B rdi, 1
        mov esi, (32 << 1) | 1
        call int_cmp
        cmp eax, 0
        jle .Lse_iszero_mask            # num > 32
        # ('add', num - 31, ('mask_shl', size, 5, 0, ('add', 31) + add_terms))
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
        B rsi, 0
        mov edx, (5 << 1) | 1
        mov ecx, 1
        call mk5
        mov [rsp + SE_TMP], rax
        B rdi, 1
        mov esi, (31 << 1) | 1
        call int_sub
        mov rsi, rax
        mov rdx, [rsp + SE_TMP]
        LOADS rdi, ADD
        call mk3
        mov rbx, rax
.Lse_iszero_mask:
        # a shift that loses none of the bits of the mask doesn't change
        # whether they're all 0
        PATX "('iszero', ('mask_shl', ':size', ':off', ':shl', ':val'))"
        test eax, eax
        jz .Lse_max1
        B rdi, 0                        # all_concrete(size, off, shl)
        call is_int
        test eax, eax
        jz .Lse_max1
        B rdi, 1
        call is_int
        test eax, eax
        jz .Lse_max1
        B rdi, 2
        call is_int
        test eax, eax
        jz .Lse_max1
        B rdi, 1                        # -off <= shl
        call int_neg
        mov rdi, rax
        B rsi, 2
        call int_cmp
        cmp eax, 0
        jg .Lse_max1
        mov edi, (256 << 1) | 1         # shl <= 256 - size - off
        B rsi, 0
        call int_sub
        mov rdi, rax
        B rsi, 1
        call int_sub
        mov rsi, rax
        B rdi, 2
        call int_cmp
        cmp eax, 0
        jg .Lse_max1
        B r8, 3
        B rdx, 1
        B rsi, 0
        LOADS rdi, MASK_SHL
        mov ecx, 1
        call mk5
        mov rdi, rax
        call mk_iszero_of
        mov rbx, rax
.Lse_max1:
        PATX "('max', ':single')"
        test eax, eax
        jz 1f
        B rbx, 0
1:      # no data: the params of a log, of a call... (in a data, no part
        # of it - and not a number)
        PATX "('mem', ('range', 'Any', 0))"
        test eax, eax
        jz 2f
        lea rax, [rip + sp_none]
        jmp .Lse_done
2:      PATX "('mod', ':exp2', ':int:num')"
        test eax, eax
        jz 3f
        B rdi, 1
        call to_exp2
        cmp rax, 1
        jle 3f
        TAG rax
        B rdi, 0
        mov rsi, rax
        mov edx, 1
        mov ecx, 1
        mov r8d, 1
        call alg_mask_op
        jmp .Lse_done
3:      PATX "('mod', 0, 'Any')"
        test eax, eax
        jz .Lse_cmp_adds
        mov ebx, 1
.Lse_cmp_adds:
        # sums that don't wrap around 2**256 compare as integers do: what
        # both have can go. Otherwise it can't: x + 1 < x is an overflow.
        PATM "(':op', ('add', '...'), ('add', '...'))"
        test eax, eax
        jz .Lse_add1
        B rdi, 0
        call str_id
        IN_OPSET cmp4, rax
        je .Lse_add1
        mov rdi, [rbx + N_DATA + 8]
        call terms_below_250_bits
        test eax, eax
        jz .Lse_add1
        mov rdi, [rbx + N_DATA + 16]
        call terms_below_250_bits
        test eax, eax
        jz .Lse_add1
        mov rax, [rbx + N_DATA + 8]
        cmp dword ptr [rax + N_AUX], 33
        ja .Lse_add1
        mov rax, [rbx + N_DATA + 16]
        cmp dword ptr [rax + N_AUX], 33
        ja .Lse_add1
        mov rdi, rbx
        call cancel_common_terms
        mov rbx, rax
.Lse_add1:
        PATX "('add', ':e')"
        test eax, eax
        jz 1f
        B rdi, 0
        call simplify_exp
        jmp .Lse_done
1:      PATX "('mul', 1, ':e')"
        test eax, eax
        jz 2f
        B rdi, 0
        call simplify_exp
        jmp .Lse_done
2:      PATX "('div', ':e', 1)"
        test eax, eax
        jz 3f
        B rdi, 0
        call simplify_exp
        jmp .Lse_done
3:      PATX "('mask_shl', 256, 0, 0, ':val')"
        test eax, eax
        jz 4f
        B rdi, 0
        call may_be_wide
        test eax, eax
        jnz 4f
        B rdi, 0
        call simplify_exp
        jmp .Lse_done
4:      PATX "('mask_shl', ':int:size', ':int:offset', ':int:shl', ':e')"
        test eax, eax
        jz 5f
        B rdi, 3
        call simplify_exp
        mov rdi, rax
        B rsi, 0
        B rdx, 1
        B rcx, 2
        mov r8d, 1
        call alg_mask_op
        mov rbx, rax
5:      # (256 ** shr is 0 for a shr of 32 or more, and so is the division
        # by it: the mask's offset is 8 * shr if that's the integer it's
        # made of)
        PATX "('mask_shl', ':size', 0, 0, ('div', ':expr', ('exp', 256, ':shr')))"
        test eax, eax
        jz 6f
        LOADS rdi, MUL
        mov esi, (8 << 1) | 1
        B rdx, 2
        call mk3
        mov rdi, rax
        xor esi, esi
        call is_word
        test eax, eax
        jz 6f
        B rdi, 2
        call alg_bits
        mov [rsp + SE_TMP], rax         # the shift
        B rdi, 1
        call simplify_exp
        mov rdi, rax
        B rsi, 0
        mov rdx, [rsp + SE_TMP]
        mov ecx, 1
        mov r8, [rsp + SE_TMP]
        call alg_mask_op
        mov rbx, rax
6:      # all the bits of a field (at 0: not one moved left, see
        # algebra.apply_mask_to_storage) moved down past 0
        PATX "('mask_shl', 'Any', 'Any', ':shl', ('storage', ':size', ':off', 'Any'))"
        test eax, eax
        jz 7f
        B rdi, 2
        call is_int
        test eax, eax
        jz 61f
        B rdi, 2
        call int_sign
        test eax, eax
        js 7f
61:     B rdi, 0
        call alg_minus_op
        B rdi, 1
        mov rsi, rax
        call alg_safe_le_op
        cmp eax, TRI_TRUE
        je .Lse_ret0
7:      PATX "('or', ':sth', 0)"
        test eax, eax
        jz 8f
        B rax, 0
        jmp .Lse_done
8:      mov rdi, rbx
        OPCODE_OF_RDI
        cmp eax, OP_ADD
        jne 9f
        mov rdi, rbx
        call simplify_add_terms
        mov rbx, rax
9:      mov rdi, rbx
        OPCODE_OF_RDI
        cmp eax, OP_MASK_SHL
        jne .Lse_mem_mask
        mov rdi, rbx
        call cleanup_mask_data
        mov rbx, rax
.Lse_mem_mask:
        PATX "('mask_shl', ':size', 0, 0, ('mem', ('range', ':mem_loc', ':mem_size')))"
        test eax, eax
        jz .Lse_mem_mask2
        B rdi, 0
        call divisible_bytes
        test eax, eax
        jz .Lse_mem_mask2
        B rdi, 0
        call to_bytes
        mov rdi, rax
        B rsi, 2
        call mem_safe_le_op
        cmp eax, TRI_TRUE
        jne .Lse_mem_mask2
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
.Lse_mem_mask2:
        PATX "('mask_shl', ':size', ':off', ':shl', ('mem', ('range', ':mem_loc', ':mem_size')))"
        test eax, eax
        jz .Lse_data
        B rdi, 1
        call alg_minus_op
        mov rdi, rax
        B rsi, 2
        call py_equal
        test eax, eax
        jz .Lse_after_data              # (an elif: no 'data' handling then)
        B rdi, 0
        call divisible_bytes
        test eax, eax
        jz .Lse_after_data
        B rdi, 1
        call divisible_bytes
        test eax, eax
        jz .Lse_after_data
        # (the bytes masked are in the range: of mem[p len 1], bits 248 to
        # 256 aren't)
        B rdi, 0
        call to_bytes
        mov [rsp + SE_TMP], rax
        B rdi, 1
        call to_bytes
        mov rsi, rax
        mov rdi, [rsp + SE_TMP]
        call alg_add2
        mov rdi, rax
        B rsi, 4
        call mem_safe_le_op
        cmp eax, TRI_TRUE
        jne .Lse_after_data
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
.Lse_data:
        mov rdi, rbx
        OPCODE_OF_RDI
        cmp eax, OP_DATA
        jne .Lse_after_data
        mov rdi, rbx
        call simplify_data
        jmp .Lse_done
.Lse_after_data:
        mov rdi, rbx
        call is_int
        test eax, eax
        jz 1f
        # (rewritten to an int above: as simplify_exp does)
        mov rdi, rbx
        call simplify_exp
        jmp .Lse_done
1:      PATX "('and', ':num', ':num2')"
        test eax, eax
        jz 3f
        # python evaluates both before looking at either (the second's
        # exceptions come even when the first is a number)
        B rdi, 0
        call arith_eval
        mov [rsp + SE_TMP], rax
        B rdi, 1
        call arith_eval
        mov rdi, rax
        call is_int
        test eax, eax
        jnz 2f
        mov rdi, [rsp + SE_TMP]
        call is_int
        test eax, eax
        jz 3f
2:      mov rdi, rbx
        call simplify_mask
        jmp .Lse_done
3:      mov rdi, rbx
        call is_list
        test eax, eax
        jz 4f
        # list(simplify_exp(tuple(exp)))
        mov edi, [rbx + N_AUX]
        lea rsi, [rbx + N_DATA]
        call mk_tuple
        mov rdi, rax
        call simplify_exp
        mov rdi, rax
        call list_of
        jmp .Lse_done
4:      mov rdi, rbx
        call is_tuple
        test eax, eax
        jz .Lsei_asis
        PATX "('mask_shl', ':int:size', ':int:offset', ':int:shl', ':int:val')"
        test eax, eax
        jz .Lse_add_low
        B rdi, 3
        B rsi, 0
        B rdx, 1
        B rcx, 2
        call alg_apply_mask
        jmp .Lse_done
.Lse_add_low:
        # the other terms are multiples of 2**off: adding less than that
        # doesn't change their bits from off up (ceil32 of a multiple of 32
        # is the number)
        PATX "('mask_shl', ':size', ':int:off', ':shl', ('add', ':int:num', '...'))"
        test eax, eax
        jz .Lse_full_mask
        B rdi, 3                        # 0 < num
        call int_sign
        cmp eax, 0
        jle .Lse_full_mask
        B rdi, 1                        # num < 2**off (never, of an off < 0)
        call int_sign
        test eax, eax
        js .Lse_full_mask
        B rdi, 3
        call int_bit_length
        mov rdi, rax
        TAG rdi
        B rsi, 1
        call int_cmp
        cmp eax, 0
        jg .Lse_full_mask
        mov rax, [rbx + N_DATA + 32]    # the add
        mov [rsp + SE_TMP], rax
        mov qword ptr [rsp + SE_I], 2
1:      mov rax, [rsp + SE_TMP]
        mov rcx, [rsp + SE_I]
        cmp ecx, [rax + N_AUX]
        jae 2f
        mov rdi, [rax + N_DATA + rcx*8]
        call s_low_zero_bits
        mov rdi, rax
        B rsi, 1
        call int_cmp
        test eax, eax
        js .Lse_full_mask
        inc qword ptr [rsp + SE_I]
        jmp 1b
2:      mov rax, [rsp + SE_TMP]
        mov edi, [rax + N_AUX]
        sub edi, 2
        lea rsi, [rax + N_DATA + 16]
        call alg_add_n
        mov r8, rax
        B rsi, 0
        B rdx, 1
        B rcx, 2
        LOADS rdi, MASK_SHL
        call mk5
        mov rdi, rax
        call simplify_exp
        jmp .Lse_done
.Lse_full_mask:
        # the mask keeps all the bits of the word that may be set
        PATX "('mask_shl', ':int:size', ':int:off', 0, ':val')"
        test eax, eax
        jz .Lse_mul
        B rdi, 0
        B rsi, 1
        call int_add
        mov rdi, rax
        mov esi, (256 << 1) | 1
        call int_cmp
        test eax, eax
        js .Lse_mul                     # size + off >= 256
        B rdi, 2
        OPCODE_OF_RDI
        cmp eax, OP_ADD
        je 1f
        cmp eax, OP_MUL
        jne .Lse_mul
1:      B rdi, 2
        call s_low_zero_bits
        mov rdi, rax
        B rsi, 1
        call int_cmp
        test eax, eax
        js .Lse_mul
        B rdi, 2
        call simplify_exp
        jmp .Lse_done
.Lse_mul:
        mov rdi, rbx
        OPCODE_OF_RDI
        cmp eax, OP_MUL
        jne .Lse_max
        # mul_op over the simplified terms
        mov qword ptr [rsp + SE_ACC], 3         # res = 1
        mov qword ptr [rsp + SE_I], 1
1:      mov rcx, [rsp + SE_I]
        cmp ecx, [rbx + N_AUX]
        jae 2f
        mov rdi, [rbx + N_DATA + rcx*8]
        call simplify_exp
        mov rdi, [rsp + SE_ACC]
        mov rsi, rax
        call alg_mul2
        mov [rsp + SE_ACC], rax
        inc qword ptr [rsp + SE_I]
        jmp 1b
2:      PAT rsi, "('mul', 1, ':res')"
        mov rdi, [rsp + SE_ACC]
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 3f
        B rax, 0
        jmp .Lse_done
3:      mov rax, [rsp + SE_ACC]
        jmp .Lse_done
.Lse_max:
        cmp eax, OP_MAX
        jne .Lse_map
        # _max_op over the simplified terms
        mov qword ptr [rsp + SE_ACC], 1         # res = 0
        mov qword ptr [rsp + SE_I], 1
1:      mov rcx, [rsp + SE_I]
        cmp ecx, [rbx + N_AUX]
        jae 2f
        mov rdi, [rbx + N_DATA + rcx*8]
        call simplify_exp
        mov rdi, [rsp + SE_ACC]
        mov rsi, rax
        call alg_max_op2
        mov [rsp + SE_ACC], rax
        inc qword ptr [rsp + SE_I]
        jmp 1b
2:      mov rax, [rsp + SE_ACC]
        jmp .Lse_done
.Lse_map:
        # every element simplified - what's bytes in it as wide as it was
        # (see memloc.keep_widths)
        mov rdi, rbx
        lea rsi, [rip + simplify_exp_cb]
        call map_seq
        cmp rax, rbx
        je .Lse_done
        mov rdi, rbx
        mov rsi, rax
        call keep_widths
        jmp .Lse_done
.Lse_ret0:
        mov eax, 1
        jmp .Lse_done
.Lse_ret1:
        mov eax, 3
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

# list_of(v) -> rax: python's list(v) of a tuple or a list (a TypeError
# otherwise: simplify_exp of a list made a tuple of it, see there)
FUNC list_of
        ENTER
        mov rbx, rdi
        IS_SEQ_RDI
        test eax, eax
        jz 1f
        mov edi, [rbx + N_AUX]
        lea rsi, [rbx + N_DATA]
        call mk_list
        LEAVE
1:      mov edi, E_TYPE
        lea rsi, [rip + .Ls_not_iterable]
        call err_throw
ENDF list_of

        .section .rodata
.Ls_not_iterable:   .asciz "object is not iterable"
.Ls_se_index:       .asciz "tuple index out of range"
.Ls_se_unpack:      .asciz "not enough values to unpack (expected 3)"
        .text

# terms_below_250_bits(add) -> eax: max_value_bits(t) <= 250 for every term
# of the add (sums of these don't wrap around 2**256)
FUNC terms_below_250_bits
        ENTER
        mov rbx, rdi
        mov r12d, 1
1:      cmp r12d, [rbx + N_AUX]
        jae 2f
        mov rdi, [rbx + N_DATA + r12*8]
        inc r12d
        xor esi, esi
        call max_value_bits
        mov rdi, rax
        mov esi, (250 << 1) | 1
        call int_cmp
        cmp eax, 0
        jle 1b
        xor eax, eax
        LEAVE
2:      mov eax, 1
        LEAVE
ENDF terms_below_250_bits

# equals(x, c) -> rax: python's equals - c + x == 0, as a comparison
FUNC equals
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE
        mov rbx, rdi
        mov r12, rsi
        PATX "('mul', -1, ':y')"
        test eax, eax
        jz 1f
        LOADS rdi, EQ
        B rsi, 0
        mov rdx, r12
        call mk3
        jmp 9f
1:      mov rdi, r12                    # to_real_int(-c % 2**256)
        call int_neg
        mov rdi, rax
        mov esi, 256
        call int_mod_2exp
        mov rdi, rax
        call to_real_int
        mov rdx, rax
        mov rsi, rbx
        LOADS rdi, EQ
        call mk3
9:      add rsp, MATCH_BINDINGS_SIZE
        LEAVE
ENDF equals

# difference_eq(exp) -> rax: python's difference_eq - a == b if exp is a -
# b (a sum with one term subtracted, and no constant), NIL (None) otherwise:
# the difference is 0 when they are equal
FUNC difference_eq
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 16
        .set DQ_NEG, MATCH_BINDINGS_SIZE
        mov rbx, rdi
        OPCODE_OF_RDI
        cmp eax, OP_ADD
        jne 8f
        cmp dword ptr [rbx + N_AUX], 3
        jb 8f
        xor r12d, r12d                  # the terms subtracted
        mov r13d, 1
1:      cmp r13d, [rbx + N_AUX]
        jae 2f
        mov rdi, [rbx + N_DATA + r13*8]
        PATXD "('mul', -1, 'Any')"
        test eax, eax
        jz 11f
        inc r12d
        mov [rsp + DQ_NEG], r13
11:     inc r13d
        jmp 1b
2:      cmp r12d, 1
        jne 8f
        mov r13d, 1                     # no number among them
3:      cmp r13d, [rbx + N_AUX]
        jae 4f
        mov rdi, [rbx + N_DATA + r13*8]
        inc r13d
        call is_int
        test eax, eax
        jnz 8f
        jmp 3b
4:      call vec_new                    # the others
        mov r12, rax
        mov r13d, 1
5:      cmp r13d, [rbx + N_AUX]
        jae 6f
        cmp r13, [rsp + DQ_NEG]
        je 51f
        mov rdi, r12
        mov rsi, [rbx + N_DATA + r13*8]
        call vec_push
51:     inc r13d
        jmp 5b
6:      mov rdi, [r12 + VEC_LEN]
        mov rsi, [r12 + VEC_DATA]
        call alg_add_n
        mov rsi, rax
        mov rax, [rsp + DQ_NEG]
        mov rax, [rbx + N_DATA + rax*8]
        mov rdx, [rax + N_DATA + 16]
        LOADS rdi, EQ
        call mk3
        jmp 9f
8:      xor eax, eax
9:      add rsp, MATCH_BINDINGS_SIZE + 16
        LEAVE
ENDF difference_eq


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
        call arena_alloc_raw   # (every element written)
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

# simplify_and_terms(('and', ...)) -> value: the numbers ANDed together
# (python's bools as the numbers they are: False and x is 0), the nested
# ands flattened - 0 when the numbers make 0, the one term when there's
# one, 2**256 - 1 when there's none
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
        call vr_number                  # an int, or a bool as one
        test rax, rax
        jz 2f
        mov [rsp + 8], rax
        mov rdi, rax
        call int_sign
        cmp eax, -1
        je 3f
        mov rdi, r13
        mov rsi, [rsp + 8]
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
4:      cmp r13, 1
        je 9f                           # real == 0: 0
        # (real,) if real changed, then the symbols
        mov rdi, r13
        mov rsi, [rsp]
        call values_equal
        test eax, eax
        jnz 6f
        mov rdi, r12
        mov rsi, r13
        call vec_prepend
6:      mov rax, [r12 + VEC_LEN]
        cmp rax, 1
        ja 7f
        jb 8f
        mov rax, [r12 + VEC_DATA]       # one: it
        mov rax, [rax]
        jmp 10f
8:      mov rax, [rsp]                  # none: 2**256 - 1
        jmp 10f
7:      mov rdi, r12
        LOADS rsi, AND
        call vec_prepend
        mov rdi, r12
        call vec_to_tuple
        jmp 10f
9:      mov eax, 1
10:     add rsp, 16
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

# cancel_common_terms((op, ('add', ...), ('add', ...))) -> (op, add_op(*t1),
# add_op(*t2)): the terms both sides have taken away from both, as
# python's collections.Counter does it
FUNC cancel_common_terms
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, [rbx + N_DATA + 8]     # ('add', ...)
        mov r13, [rbx + N_DATA + 16]
        mov rdi, r12
        mov rsi, r13
        call counter_minus
        mov rsi, [rax + VEC_DATA]
        mov rdi, [rax + VEC_LEN]
        call alg_add_n
        mov [rsp], rax
        mov rdi, r13
        mov rsi, r12
        call counter_minus
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

# counter_minus(a, b) -> vec: python's (e1 - (e1 & e2)).elements() for the
# Counters e1 of a[1:] and e2 of b[1:] - each term of a, in the order it
# first comes, as many times as a has it more than b does
FUNC counter_minus
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        call vec_new
        mov [rsp], rax
        mov r13d, 1
1:      cmp r13d, [rbx + N_AUX]
        jae 9f
        mov r14, [rbx + N_DATA + r13*8]
        mov rdi, rbx                    # counted already (a key of e1)?
        mov rsi, r14
        mov edx, r13d
        call count_in
        test rax, rax
        jnz 8f
        mov rdi, rbx
        mov rsi, r14
        mov edx, [rbx + N_AUX]
        call count_in
        mov [rsp + 8], rax
        mov rdi, r12
        mov rsi, r14
        mov edx, [r12 + N_AUX]
        call count_in
        mov rcx, [rsp + 8]
        sub rcx, rax
        jle 8f
        mov [rsp + 8], rcx
7:      mov rdi, [rsp]
        mov rsi, r14
        call vec_push
        dec qword ptr [rsp + 8]
        jnz 7b
8:      inc r13d
        jmp 1b
9:      mov rax, [rsp]
        add rsp, 16
        LEAVE
ENDF counter_minus

# count_in(seq, x, end) -> rax: how many of seq[1:end] are x (python's ==:
# a key of a dict)
FUNC count_in
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13d, edx
        xor r14d, r14d
        mov ecx, 1
        push rcx
        push rcx
1:      mov rcx, [rsp]
        cmp ecx, r13d
        jae 2f
        mov rdi, [rbx + N_DATA + rcx*8]
        inc qword ptr [rsp]
        mov rsi, r12
        call py_equal
        add r14d, eax
        jmp 1b
2:      add rsp, 16
        mov eax, r14d
        LEAVE
ENDF count_in

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

# simplify_data(('data', ...)) -> value: the inner expressions simplified
# (each as wide as it was, a range of no bytes gone), the nested datas
# flattened, the masks next to each other that make one merged, and the
# elements as data_elements makes them
FUNC simplify_data
        STACK_CHECK
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 48
        .set SD_RES, MATCH_BINDINGS_SIZE
        .set SD_RES2, MATCH_BINDINGS_SIZE + 8
        .set SD_I, MATCH_BINDINGS_SIZE + 16
        .set SD_EL, MATCH_BINDINGS_SIZE + 24
        .set SD_E, MATCH_BINDINGS_SIZE + 32
        mov rbx, rdi
        call vec_new
        mov r12, rax
        mov r13d, 1
1:      cmp r13d, [rbx + N_AUX]
        jae 3f
        mov rax, [rbx + N_DATA + r13*8]
        mov [rsp + SD_E], rax
        mov rdi, rax
        call simplify_exp
        mov r14, rax
        mov rdi, rax                    # a range of length 0 (simplify_exp's
        call is_none                    # None): no bytes
        test eax, eax
        jz 11f
        mov rdi, [rsp + SD_E]
        OPCODE_OF_RDI
        cmp eax, OP_MEM
        je 4f
11:     mov rdi, [rsp + SD_E]
        mov rsi, r14
        call keep_width
        mov r14, rax
        mov rdi, rax
        OPCODE_OF_RDI
        cmp eax, OP_BYTES
        jne 12f
        mov rdi, r14
        call as_bytes
        mov r14, rax
12:     mov rdi, r14
        OPCODE_OF_RDI
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
        mov rdi, [rsp + SD_RES2]
        call data_elements
        mov r12, rax
        cmp qword ptr [r12 + VEC_LEN], 1
        jne 9f
        mov rax, [r12 + VEC_DATA]
        mov rax, [rax]
        jmp .Lsd_done
9:      mov rdi, r12
        LOADS rsi, DATA
        call vec_prepend
        mov rdi, r12
        call vec_to_tuple
.Lsd_done:
        add rsp, MATCH_BINDINGS_SIZE + 48
        LEAVE
ENDF simplify_data

# data_elements(list) -> vec: python's data_elements - the elements of a
# data without "bytes" when they're as wide as their value, zeroes
# followed by a value merged into it, and zeroes into one - and without
# the ones of no bytes (a range of length 0). Two parts of the same bytes,
# one where the other ends, are one.
FUNC data_elements
        STACK_CHECK
        ENTER
        sub rsp, 48
        .set DE_W, 0
        .set DE_Z, 8
        .set DE_INNER, 16
        .set DE_ZW, 24
        mov rbx, rdi
        call vec_new
        mov r12, rax                    # res
        xor r13d, r13d
1:      cmp r13d, [rbx + N_AUX]
        jae 3f
        mov r14, [rbx + N_DATA + r13*8]
        inc r13d
        mov rdi, r14
        call width_of
        test rax, rax
        jz 2f                           # (None isn't 0)
        mov rdi, rax
        mov esi, 1
        call py_equal
        test eax, eax
        jnz 1b                          # no bytes: gone
2:      mov rdi, r14
        mov esi, 1
        call implicit_value
        mov rdi, r12
        mov rsi, rax
        call vec_push
        jmp 1b
3:      call vec_new
        mov r13, rax                    # merged
        xor r14d, r14d
4:      cmp r14, [r12 + VEC_LEN]
        jae .Lde_last
        mov rax, [r12 + VEC_DATA]
        mov rbx, [rax + r14*8]          # e
        inc r14
        mov rcx, [r13 + VEC_LEN]
        test rcx, rcx
        jz 19f
        mov rax, [r13 + VEC_DATA]
        mov rdi, [rax + rcx*8 - 8]
        mov rsi, rbx
        call join_slices
        test rax, rax
        jz 5f
        mov rcx, [r13 + VEC_LEN]
        mov rdx, [r13 + VEC_DATA]
        mov [rdx + rcx*8 - 8], rax
        jmp 4b
5:      mov rcx, [r13 + VEC_LEN]
        mov rax, [r13 + VEC_DATA]
        mov rdi, [rax + rcx*8 - 8]
        call data_zeroes
        test rax, rax
        jz 19f
        mov [rsp + DE_Z], rax           # z: zeroes before e
        mov rdi, rbx
        call sizeof
        mov [rsp + DE_W], rax           # w
        mov rdi, rbx
        call data_zeroes
        test rax, rax
        jz 6f
        mov rdi, [rsp + DE_Z]           # zeroes and zeroes: one
        mov rsi, rax
        call int_add
        mov rdi, rax
        mov esi, (8 << 1) | 1
        call int_floordiv
        mov rsi, rax
        LOADS rdi, BYTES
        mov edx, 1
        call mk3
        mov rcx, [r13 + VEC_LEN]
        mov rdx, [r13 + VEC_DATA]
        mov [rdx + rcx*8 - 8], rax
        jmp 4b
6:      mov [rsp + DE_INNER], rbx
        mov rdi, rbx
        OPCODE_OF_RDI
        cmp eax, OP_BYTES
        jne 7f
        cmp dword ptr [rbx + N_AUX], 3
        jb .Lde_index
        mov rax, [rbx + N_DATA + 16]
        mov [rsp + DE_INNER], rax
7:      # the zeroes, then the low bytes of a number: its low bytes then only
        # if there's nothing above them - and a number of no more than a
        # word (bytes - a range, a data - go after the zeroes)
        mov rdi, [rsp + DE_W]
        call is_int
        test eax, eax
        jz 19f
        mov rdi, [rsp + DE_W]
        mov esi, 3
        call int_mod_2exp
        cmp rax, 1
        jne 19f                         # w % 8 == 0
        mov rcx, [r13 + VEC_LEN]
        mov rax, [r13 + VEC_DATA]
        mov rdi, [rax + rcx*8 - 8]
        OPCODE_OF_RDI
        cmp eax, OP_BYTES
        jne 19f
        mov rdi, [rsp + DE_Z]
        mov rsi, [rsp + DE_W]
        call int_add
        mov [rsp + DE_ZW], rax
        mov rdi, rax
        mov esi, (256 << 1) | 1
        call int_cmp
        cmp eax, 0
        jg 19f                          # z + w <= 256
        mov rdi, [rsp + DE_INNER]
        call sized
        test eax, eax
        jnz 19f
        mov rdi, [rsp + DE_INNER]
        call value_bits
        mov rdi, rax
        mov rsi, [rsp + DE_W]
        call int_cmp
        cmp eax, 0
        jg 19f                          # value_bits(inner) <= w
        mov rdi, [rsp + DE_ZW]
        mov esi, (8 << 1) | 1
        call int_floordiv
        mov rsi, rax
        mov rdx, [rsp + DE_INNER]
        LOADS rdi, BYTES
        call mk3
        mov rcx, [r13 + VEC_LEN]
        mov rdx, [r13 + VEC_DATA]
        mov [rdx + rcx*8 - 8], rax
        jmp 4b
19:     mov rdi, r13
        mov rsi, rbx
        call vec_push
        jmp 4b
.Lde_last:
        # the values that need no bytes to say how wide they are, as they are
        xor r14d, r14d
1:      cmp r14, [r13 + VEC_LEN]
        jae 2f
        mov rax, [r13 + VEC_DATA]
        mov rdi, [rax + r14*8]
        xor esi, esi
        call implicit_value
        mov rcx, [r13 + VEC_DATA]
        mov [rcx + r14*8], rax
        inc r14
        jmp 1b
2:      mov rax, r13
        add rsp, 48
        LEAVE
.Lde_index:
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_se_index]
        call err_throw
ENDF data_elements

# implicit_value(e, nonzero) -> rax: e[2] when e is ('bytes', n, v) of a v
# that needs no bytes to say how wide it is (implicit(v, bits(n))) - and
# isn't 0, with nonzero - else e
FUNC implicit_value
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12d, esi
        OPCODE_OF_RDI
        cmp eax, OP_BYTES
        jne 9f
        cmp dword ptr [rbx + N_AUX], 3
        jb 8f
        test r12d, r12d
        jz 1f
        mov rdi, [rbx + N_DATA + 16]
        mov esi, 1
        call py_equal
        test eax, eax
        jnz 9f
1:      mov rdi, [rbx + N_DATA + 8]
        call alg_bits
        mov rsi, rax
        mov rdi, [rbx + N_DATA + 16]
        call implicit
        test eax, eax
        jz 9f
        mov rax, [rbx + N_DATA + 16]
        LEAVE
9:      mov rax, rbx
        LEAVE
8:      mov edi, E_INDEX
        lea rsi, [rip + .Ls_se_index]
        call err_throw
ENDF implicit_value

# data_zeroes(e) -> rax: the width of e if it's zeroes (a 0, a ('bytes',
# int n, 0)), NIL otherwise
FUNC data_zeroes
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE
        mov rbx, rdi
        mov esi, 1
        call py_equal
        test eax, eax
        jz 1f
        mov eax, (256 << 1) | 1
        jmp 9f
1:      PATX "('bytes', ':size', 0)"
        test eax, eax
        jz 8f
        B rdi, 0
        call is_int
        test eax, eax
        jz 8f
        B rdi, 0
        call alg_bits
        jmp 9f
8:      xor eax, eax
9:      add rsp, MATCH_BINDINGS_SIZE
        LEAVE
ENDF data_zeroes

# join_slices(a, b) -> rax: python's join_slices - the bytes a then b are,
# where they're the same bytes and b starts where a ends:
# `ext_call.return_data[0 len n], ext_call.return_data[n len 32 - n]` is
# `ext_call.return_data[0 len 32]`. NIL (None) otherwise.
FUNC join_slices
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 16
        .set JS_S1, MATCH_BINDINGS_SIZE
        .set JS_N1, MATCH_BINDINGS_SIZE + 8
        mov rbx, rdi
        mov r12, rsi
        PATX "('mem', ('range', ':s1', ':n1'))"
        test eax, eax
        jz 5f
        B rax, 0
        mov [rsp + JS_S1], rax
        B rax, 1
        mov [rsp + JS_N1], rax
        mov rdi, r12
        PATXD "('mem', ('range', ':s2', ':n2'))"
        test eax, eax
        jz 5f
        mov rdi, [rsp + JS_S1]
        mov rsi, [rsp + JS_N1]
        call alg_add2
        mov rsi, rax
        B rdi, 0
        call alg_sub_op
        mov rdi, rax
        mov esi, 1
        call py_equal
        test eax, eax
        jz 8f
        mov rdi, [rsp + JS_N1]
        B rsi, 1
        call alg_add2
        mov rsi, [rsp + JS_S1]
        mov rdi, rsi
        mov rsi, rax
        call mk_range
        mov rsi, rax
        LOADS rdi, MEM
        call mk2
        jmp 9f
5:      # two parts of the same array
        mov rdi, rbx
        call opcode_of
        mov r13d, eax
        mov rdi, r12
        call opcode_of
        cmp eax, r13d
        jne 8f
        mov edi, r13d
        call is_array_op
        test eax, eax
        jz 8f
        cmp dword ptr [rbx + N_AUX], 3
        jne 8f
        cmp dword ptr [r12 + N_AUX], 3
        jne 8f
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, [rbx + N_DATA + 16]
        call alg_add2
        mov rsi, rax
        mov rdi, [r12 + N_DATA + 8]
        call alg_sub_op
        mov rdi, rax
        mov esi, 1
        call py_equal
        test eax, eax
        jz 8f
        mov rdi, [rbx + N_DATA + 16]
        mov rsi, [r12 + N_DATA + 16]
        call alg_add2
        mov rdx, rax
        mov rdi, [rbx + N_DATA]
        mov rsi, [rbx + N_DATA + 8]
        call mk3
        jmp 9f
8:      xor eax, eax
9:      add rsp, MATCH_BINDINGS_SIZE + 16
        LEAVE
ENDF join_slices

# unwrap_bytes(exp) -> rax: python's unwrap_bytes - exp (a tuple), with the
# operands that are numbers not wrapped in "bytes", and the ones that are
# bytes not Bytes(n, v) of v bytes of another width than n
FUNC unwrap_bytes
        ENTER
        sub rsp, 16
        mov rbx, rdi
        OPCODE_OF_RDI
        cmp eax, OP_BYTES
        je .Lub_asis
        mov r13d, eax                   # op
        mov r12d, 1
1:      cmp r12d, [rbx + N_AUX]
        jae .Lub_asis
        mov rdi, [rbx + N_DATA + r12*8]
        inc r12d
        OPCODE_OF_RDI
        cmp eax, OP_BYTES
        jne 1b
        mov edi, [rbx + N_AUX]
        shl rdi, 3
        call arena_alloc_raw            # (every element written)
        mov [rsp], rax
        mov rcx, [rbx + N_DATA]
        mov [rax], rcx
        mov r12d, 1
2:      cmp r12d, [rbx + N_AUX]
        jae 8f
        mov r14, [rbx + N_DATA + r12*8] # e
        mov rdi, r14
        OPCODE_OF_RDI
        cmp eax, OP_BYTES
        jne 7f
        mov rdi, rbx
        mov esi, r12d
        call is_byte_element
        test eax, eax
        jz 3f
        mov rdi, r14
        call as_bytes
        mov r14, rax
        jmp 7f
3:      cmp dword ptr [r14 + N_AUX], 3
        jb .Lub_index
        cmp r13d, OP_SETMEM
        jne 4f
        cmp r12d, 2
        jne 4f
        # bytes of another width than the memory written: the number they
        # make (see memloc.keep_setmem_width)
        mov rdi, [r14 + N_DATA + 16]
        call sized
        test eax, eax
        jnz 7f
4:      mov r14, [r14 + N_DATA + 16]
7:      mov rax, [rsp]
        mov [rax + r12*8], r14
        inc r12d
        jmp 2b
8:      mov edi, [rbx + N_AUX]
        mov rsi, [rsp]
        call mk_tuple
        add rsp, 16
        LEAVE
.Lub_asis:
        mov rax, rbx
        add rsp, 16
        LEAVE
.Lub_index:
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_se_index]
        call err_throw
ENDF unwrap_bytes

# as_bytes(e) -> rax: python's as_bytes - e, a ('bytes', n, v) where it's
# bytes: v, when it's bytes of another width than n, as zeroes and v or
# its last n bytes
FUNC as_bytes
        ENTER
        mov rbx, rdi
        cmp dword ptr [rbx + N_AUX], 3
        jb 8f
        mov rdi, [rbx + N_DATA + 16]
        call sized
        test eax, eax
        jz 9f
        mov rdi, [rbx + N_DATA + 16]
        mov rsi, [rbx + N_DATA + 8]
        call resize_bytes
        test rax, rax
        jz 9f
        LEAVE
9:      mov rax, rbx
        LEAVE
8:      mov edi, E_INDEX
        lea rsi, [rip + .Ls_se_index]
        call err_throw
ENDF as_bytes

# simplify_bytes(('bytes', size, val)) -> value: python's simplify_bytes -
# val simplified, the bytes of bytes no wider than these only once, and val
# alone when it says how wide it is
FUNC simplify_bytes
        STACK_CHECK
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE
        mov rbx, rdi
        cmp dword ptr [rbx + N_AUX], 3
        jne .Lsb_unpack
        mov r12, [rbx + N_DATA + 8]     # size
        mov rdi, [rbx + N_DATA + 16]
        call simplify_exp
        mov r13, rax                    # val
        mov rdi, rax
        PATXD "('bytes', ':inner_size', ':inner')"
        test eax, eax
        jz 1f
        B rdi, 0
        mov rsi, r12
        call mem_safe_le_op
        cmp eax, TRI_TRUE
        jne 1f
        B r13, 1
1:      mov rdi, r13
        mov esi, 1
        call py_equal
        test eax, eax
        jnz 2f
        mov rdi, r12
        call alg_bits
        mov rsi, rax
        mov rdi, r13
        call implicit
        test eax, eax
        jz 2f
        mov rax, r13
        jmp 9f
2:      LOADS rdi, BYTES
        mov rsi, r12
        mov rdx, r13
        call mk3
9:      add rsp, MATCH_BINDINGS_SIZE
        LEAVE
.Lsb_unpack:
        mov edi, E_VALUE
        lea rsi, [rip + .Ls_se_unpack]
        call err_throw
ENDF simplify_bytes


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
        xor esi, esi                    # (no bounds)
        call to_mask
        test rax, rax
        jz 11f
        B rdi, 1
        jmp 14f
11:     B rdi, 1
        xor esi, esi                    # (no bounds)
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
        xor esi, esi                    # (no bounds)
        call to_neg_mask
        test rax, rax
        jz 13f
        B rdi, 1
        jmp 15f
13:     B rdi, 1
        xor esi, esi                    # (no bounds)
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
        call sizeof
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
        call sizeof
        test rax, rax
        jz .Lcr_asis
        mov r13, rax                    # sizeof(last)
        mov rdi, rax
        mov rsi, [rbx + N_DATA + 16]
        call mem_safe_le_op
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
        call sizeof
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
        call mem_safe_le_op
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


# canonise_max(exp) -> value: the terms of a max in a canonical order
# (sorted by their repr, the ints first)
FUNC canonise_max
        OPCODE_INLINE rdi, eax, rcx     # (a callback on every node: not a
        cmp eax, OP_MAX                 # max, as it is, without a frame)
        je 1f
        mov rax, rdi
        ret
1:      ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 16
        mov rbx, rdi
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
        call xmalloc
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
