# Memory locations (port of core/memloc.py): splitting the values written
# to memory into their pieces, and the overlaps of memory ranges.
#
# Ranges are ('range', position, length) in bytes; the rows of a split are
# (size, offset, value) in bits.

.include "defs.inc"

        .section .rodata
.Ls_assert_bits:    .asciz "apply_mask_to_range: sizes not in whole bytes"
.Ls_assert_fits:    .asciz "apply_mask_to_range: the mask doesn't fit the range"
.Ls_assert_range:   .asciz "not a range"
.Ls_assert_split:   .asciz "split_or: unexpected second row"
.Ls_assert_sizeof:  .asciz "sizeof: unexpected expression"
.Ls_assert_center:  .asciz "fill_mem: negative center size"
.Ls_undefined:      .asciz "undefined"
.Ls_block_timestamp: .asciz "block.timestamp"
.Ls_MAX:            .asciz "MAX"
.Ls_logname:        .asciz "panoramix.memloc"
.Ls_unusual_store:  .asciz "unusual store"
.Ls_different_maxes: .asciz "different maxes"
.Ls_problem_split:  .asciz "problem with split_setmem"

        .text

# assert_range(v): the value is a ('range', pos, len)
FUNC assert_range
        ENTER
        mov rbx, rdi
        call opcode_of
        cmp eax, OP_RANGE
        jne 1f
        cmp dword ptr [rbx + N_AUX], 3
        jne 1f
        LEAVE
1:      mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_range]
        call err_throw
ENDF assert_range

# mk_row(size, offset, value) -> (size, offset, value)
FUNC mk_row
        jmp mk3
ENDF mk_row

# full_row(value) -> [(256, 0, value)]
FUNC full_row
        ENTER
        mov rdx, rdi
        mov edi, (256 << 1) | 1
        mov esi, 1
        call mk3
        mov rdi, rax
        call mk_list1
        LEAVE
ENDF full_row

# apply_mask_to_range(memloc, size, offset) -> ('range', pos, len): the
# part of the range a mask of `size` bits at `offset` covers (asserts
# when they aren't whole bytes, or when the mask doesn't fit)
FUNC apply_mask_to_range
        ENTER
        sub rsp, 32
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        call assert_range
        mov rdi, r12
        call to_bytes
        mov [rsp], rax                  # size_bytes
        cmp rdx, 1
        jne .Lamr_bits
        mov rdi, r13
        call to_bytes
        mov [rsp + 8], rax              # offset_bytes
        cmp rdx, 1
        jne .Lamr_bits
        mov rdi, [rsp]
        mov rsi, [rsp + 8]
        call alg_add2
        mov [rsp + 16], rax             # size + offset, in bytes
        mov rdi, rax
        mov rsi, [rbx + N_DATA + 16]    # range_len
        call alg_safe_le_op
        cmp eax, TRI_TRUE
        jne .Lamr_fits
        # range_pos + (range_len - (size + offset)), size
        mov rdi, [rbx + N_DATA + 16]
        mov rsi, [rsp + 16]
        call alg_sub_op
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, rax
        call alg_add2
        mov rdi, rax
        mov rsi, [rsp]
        call mk_range
        add rsp, 32
        LEAVE
.Lamr_bits:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_bits]
        call err_throw
.Lamr_fits:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_fits]
        call err_throw
ENDF apply_mask_to_range

# row_lt(a, b) -> eax: the ordering of the rows by offset (lt_op, which
# may raise CannotCompare); 1 when a < b, 0 otherwise (also for None)
FUNC row_lt
        ENTER
        mov rdi, [rdi + N_DATA + 8]
        mov rsi, [rsi + N_DATA + 8]
        call alg_lt_op
        mov edi, eax
        call must_compare
        cmp eax, TRI_TRUE
        sete al
        movzx eax, al
        LEAVE
ENDF row_lt

# sort_rows(vec): python's list.sort with `<` being row_lt - for fewer
# than 64 elements, a run count then a binary insertion sort, with the
# comparisons in the same order (they may raise)
FUNC sort_rows
        ENTER
        sub rsp, 16
        mov rbx, [rdi + VEC_DATA]
        mov r12, [rdi + VEC_LEN]
        cmp r12, 2
        jb .Lsr_done
        # count_run: an initial ascending run, or a strictly descending
        # one (reversed)
        mov rdi, [rbx + 8]
        mov rsi, [rbx]
        call row_lt
        mov r13d, 2                     # the run length
        test eax, eax
        jz 2f
        # descending
1:      cmp r13, r12
        jae 3f
        mov rdi, [rbx + r13*8]
        mov rsi, [rbx + r13*8 - 8]
        call row_lt
        test eax, eax
        jz 3f
        inc r13
        jmp 1b
3:      # reverse the run
        lea rdi, [rbx]
        lea rsi, [rbx + r13*8 - 8]
4:      cmp rdi, rsi
        jae 6f
        mov rax, [rdi]
        mov rcx, [rsi]
        mov [rdi], rcx
        mov [rsi], rax
        add rdi, 8
        sub rsi, 8
        jmp 4b
2:      # ascending
        cmp r13, r12
        jae 6f
        mov rdi, [rbx + r13*8]
        mov rsi, [rbx + r13*8 - 8]
        call row_lt
        test eax, eax
        jnz 6f
        inc r13
        jmp 2b
6:      # binarysort from r13 on
        cmp r13, r12
        jae .Lsr_done
        mov r14, [rbx + r13*8]          # pivot
        xor ecx, ecx                    # l
        mov rdx, r13                    # r
7:      cmp rcx, rdx
        jae 8f
        mov rax, rdx
        sub rax, rcx
        shr rax, 1
        add rax, rcx                    # p
        mov [rsp], rcx
        mov [rsp + 8], rdx
        push rax
        push rax
        mov rdi, r14
        mov rsi, [rbx + rax*8]
        call row_lt
        pop rdx
        pop rdx
        mov rcx, [rsp]
        test eax, eax
        jz 9f
        # pivot < a[p]: r = p
        jmp 7b
9:      lea rcx, [rdx + 1]              # l = p + 1
        mov rdx, [rsp + 8]
        jmp 7b
8:      # insert the pivot at l: shift a[l..start) up
        mov rax, r13
10:     cmp rax, rcx
        jbe 11f
        mov rdx, [rbx + rax*8 - 8]
        mov [rbx + rax*8], rdx
        dec rax
        jmp 10b
11:     mov [rbx + rcx*8], r14
        inc r13
        jmp 6b
.Lsr_done:
        add rsp, 16
        LEAVE
ENDF sort_rows

# split_or(value) -> list of (size, offset, value): the pieces of a value
# made of ORed masked parts, sorted by offset, with zeroes in the gaps
FUNC split_or
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 128
        .set SO_ORIG, MATCH_BINDINGS_SIZE
        .set SO_VALUE, MATCH_BINDINGS_SIZE + 8     # `value`: rebound along the way, as in python
        .set SO_ROWS, MATCH_BINDINGS_SIZE + 16
        .set SO_ROW, MATCH_BINDINGS_SIZE + 24
        .set SO_SIZE, MATCH_BINDINGS_SIZE + 32
        .set SO_OFFSET, MATCH_BINDINGS_SIZE + 40
        .set SO_SHL, MATCH_BINDINGS_SIZE + 48
        .set SO_STOR_OFFSET, MATCH_BINDINGS_SIZE + 56
        .set SO_ERR, MATCH_BINDINGS_SIZE + 64      # (64 bytes)
        mov [rsp + SO_ORIG], rdi
        mov [rsp + SO_VALUE], rdi
        mov rbx, rdi
        call opcode_of
        cmp eax, OP_OR
        je 1f
        cmp eax, OP_MASK_SHL
        je 2f
        mov rdi, [rsp + SO_ORIG]
        call full_row
        jmp .Lso_done
2:      # a single mask: ('or', value)
        mov rsi, rbx
        LOADS rdi, OR
        call mk2
        mov rbx, rax
        mov [rsp + SO_VALUE], rax
1:      call vec_new
        mov [rsp + SO_ROWS], rax
        mov r12d, 1                     # the term
.Lso_term:
        cmp r12d, [rbx + N_AUX]
        jae .Lso_terms_done
        mov r13, [rbx + N_DATA + r12*8] # row
        inc r12d
        PAT rsi, "('bool', ':arg')"
        mov rdi, r13
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 3f
        mov r8, r13
        LOADS rdi, MASK_SHL
        mov esi, (8 << 1) | 1
        mov edx, 1
        mov ecx, 1
        call mk5                        # (does weird things if size == 1, in loops.activateSafeMode)
        mov r13, rax
3:      LOADS rax, CALLER
        cmp r13, rax
        jne 4f
        mov r8, r13
        LOADS rdi, MASK_SHL
        mov esi, (160 << 1) | 1
        mov edx, 1
        mov ecx, 1
        call mk5
        mov r13, rax
4:      lea rdi, [rip + .Ls_block_timestamp]
        call str_intern_c
        cmp r13, rax
        jne 5f
        LOADS r8, CALLER                # (sic)
        LOADS rdi, MASK_SHL
        mov esi, (64 << 1) | 1
        mov edx, 1
        mov ecx, 1
        call mk5
        mov r13, rax
5:      PAT rsi, "('mul', 1, ':val')"
        mov rdi, r13
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 6f
        mov r13, [rsp]
6:      # (the python version's all_concrete(row) on a mask can't be true)
        mov rdi, r13
        call is_int
        test eax, eax
        jz 7f
        mov rdi, r13
        call find_mask
        mov rsi, rax
        mov r8, r13
        mov ecx, 1
        LOADS rdi, MASK_SHL
        call mk5
        mov r13, rax
7:      PAT rsi, "('mem', ':mem_idx')"
        mov rdi, r13
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 8f
        mov rdi, [rsp]
        call opcode_of
        cmp eax, OP_RANGE
        je 9f
        mov rdi, [rsp]
        mov esi, (32 << 1) | 1
        call mk_range
        mov [rsp], rax
9:      mov rax, [rsp]
        mov rdi, [rax + N_DATA + 16]    # mem_len
        call alg_bits
        mov rdi, rax
        mov esi, 1
        mov rdx, r13
        call mk_row
        jmp .Lso_push
8:      PAT rsi, "('storage', ':size', ':off', ':idx')"
        mov rdi, r13
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 10f
        mov rdi, [rsp]
        mov esi, 1
        mov rdx, r13
        call mk_row
        jmp .Lso_push
10:     mov rdi, r13
        call opcode_of
        cmp eax, OP_MASK_SHL
        jne .Lso_not_mask
        cmp dword ptr [r13 + N_AUX], 5
        jne .Lso_not_mask
        # _, size, offset, shl, value = row
        mov rax, [r13 + N_DATA + 8]
        mov [rsp + SO_SIZE], rax
        mov rax, [r13 + N_DATA + 16]
        mov [rsp + SO_OFFSET], rax
        mov rax, [r13 + N_DATA + 24]
        mov [rsp + SO_SHL], rax
        mov rax, [r13 + N_DATA + 32]
        mov [rsp + SO_VALUE], rax
        # stor_offset = offset + shl; shl = shl - stor_offset
        mov rdi, [rsp + SO_OFFSET]
        mov rsi, [rsp + SO_SHL]
        call alg_add2
        mov [rsp + SO_STOR_OFFSET], rax
        mov rdi, [rsp + SO_SHL]
        mov rsi, rax
        call alg_sub_op
        mov [rsp + SO_SHL], rax
        mov rdi, [rsp + SO_VALUE]
        call is_int
        test eax, eax
        jz 11f
        mov rdi, [rsp + SO_SIZE]
        call is_int
        test eax, eax
        jz 11f
        mov rdi, [rsp + SO_OFFSET]
        call is_int
        test eax, eax
        jz 11f
        mov rdi, [rsp + SO_SHL]
        call is_int
        test eax, eax
        jz 11f
        mov rdi, [rsp + SO_VALUE]
        mov rsi, [rsp + SO_SIZE]
        mov rdx, [rsp + SO_OFFSET]
        mov rcx, [rsp + SO_SHL]
        call alg_apply_mask
        mov [rsp + SO_VALUE], rax
        jmp 13f
11:     PAT rsi, "('mem', ':idx')"
        mov rdi, [rsp + SO_VALUE]
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 12f
        mov rdi, [rsp + SO_OFFSET]
        mov rsi, [rsp + SO_SHL]
        call alg_add2
        cmp rax, 1
        jne 12f
        # a memory slice, when the mask fits it (else the mask stays: an
        # AssertionError only, python lets the others through)
        lea rdi, [rsp + SO_ERR]
        call err_catch
        test eax, eax
        jz 11f
        cmp eax, E_ASSERT
        je 12f
        mov edi, eax
        mov rsi, [r15 + CTX_ERR_MSG]
        call err_throw
11:
        mov rdi, [rsp]
        mov rsi, [rsp + SO_SIZE]
        mov rdx, [rsp + SO_OFFSET]
        call apply_mask_to_range
        mov rsi, rax
        LOADS rdi, MEM
        call mk2
        mov [rsp + SO_VALUE], rax
        call err_end
        jmp 13f
12:     mov rdi, [rsp + SO_VALUE]
        mov rsi, [rsp + SO_SIZE]
        mov rdx, [rsp + SO_OFFSET]
        mov rcx, [rsp + SO_SHL]
        mov r8d, 1
        call alg_mask_op
        mov [rsp + SO_VALUE], rax
13:     mov rdi, [rsp + SO_SIZE]
        mov rsi, [rsp + SO_STOR_OFFSET]
        mov rdx, [rsp + SO_VALUE]
        call mk_row
.Lso_push:
        mov rdi, [rsp + SO_ROWS]
        mov rsi, rax
        call vec_push
        jmp .Lso_term
.Lso_not_mask:
        mov rdi, [rsp + SO_VALUE]
        call full_row
        jmp .Lso_done
.Lso_terms_done:
        mov r13, [rsp + SO_ROWS]
        cmp qword ptr [r13 + VEC_LEN], 2
        jne .Lso_sort
        # a special case where the rows are symbolic and complementary
        # (see the python version)
        mov rax, [r13 + VEC_DATA]
        mov rbx, [rax]                  # first
        mov r12, [rax + 8]              # second
        cmp qword ptr [rbx + N_DATA + 8], 1
        je 14f
        cmp qword ptr [r12 + N_DATA + 8], 1
        jne 14f
        xchg rbx, r12
14:     cmp qword ptr [rbx + N_DATA + 8], 1     # f_off == 0
        jne .Lso_sort
        # f_size[4]: only a sequence of 5+ elements has one (python: a
        # TypeError or IndexError otherwise, passed over)
        mov rdi, [rbx + N_DATA]
        call is_seq
        test eax, eax
        jz .Lso_sort
        mov rax, [rbx + N_DATA]
        cmp dword ptr [rax + N_AUX], 5
        jb .Lso_sort
        mov r14, [rax + N_DATA + 32]    # f_size[4]
        # s_off == ('add', 256, ('mul', -1, ('mask_shl', 253, 0, 3, ('add', 32, ('mul', -1, ('mask_shl', 5, 0, 0, f_size[4]))))))
        mov r8, r14
        LOADS rdi, MASK_SHL
        mov esi, (5 << 1) | 1
        mov edx, 1
        mov ecx, 1
        call mk5
        mov rdx, rax
        LOADS rdi, MUL
        mov rsi, -1
        TAG rsi
        call mk3
        mov rdx, rax
        LOADS rdi, ADD
        mov esi, (32 << 1) | 1
        call mk3
        mov r8, rax
        LOADS rdi, MASK_SHL
        mov esi, (253 << 1) | 1
        mov edx, 1
        mov ecx, (3 << 1) | 1
        call mk5
        mov rdx, rax
        LOADS rdi, MUL
        mov rsi, -1
        TAG rsi
        call mk3
        mov rdx, rax
        LOADS rdi, ADD
        mov esi, (256 << 1) | 1
        call mk3
        cmp rax, [r12 + N_DATA + 8]
        jne .Lso_sort
        PAT rsi, "('mask_shl', 'Any', 'Any', 'Any', ('add', 32, ('mul', -1, '...')))"
        mov rdi, [r12 + N_DATA]
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz .Lso_assert
        mov rdi, r13
        call vec_to_list
        jmp .Lso_done
.Lso_sort:
        # sort by offsets (CannotCompare: the whole value stays as is)
        lea rdi, [rsp + SO_ERR]
        call err_catch
        test eax, eax
        jnz .Lso_unsortable
        mov rdi, [rsp + SO_ROWS]
        call sort_rows
        call err_end
        # insert zeroes into the empty spaces (python's ints: big ones too)
        call vec_new
        mov rbx, rax                    # result
        mov r12d, 1                     # pos
        xor r14d, r14d
15:     mov r13, [rsp + SO_ROWS]
        cmp r14, [r13 + VEC_LEN]
        jae 18f
        mov rax, [r13 + VEC_DATA]
        mov r13, [rax + r14*8]          # r
        mov rdi, [r13 + N_DATA + 8]
        call is_int
        test eax, eax
        jz .Lso_symbolic
        mov rdi, [r13 + N_DATA]
        call is_int
        test eax, eax
        jz .Lso_symbolic
        mov rdi, [r13 + N_DATA + 8]
        mov rsi, r12
        call int_cmp
        cmp eax, 0
        jle 16f
        # (r[1] - pos, pos, 0)
        mov rdi, [r13 + N_DATA + 8]
        mov rsi, r12
        call int_sub
        mov rdi, rax
        mov rsi, r12
        mov edx, 1
        call mk_row
        mov rdi, rbx
        mov rsi, rax
        call vec_push
16:     mov rdi, rbx
        mov rsi, r13
        call vec_push
        mov rdi, [r13 + N_DATA + 8]
        mov rsi, [r13 + N_DATA]
        call int_add
        mov r12, rax                    # pos = r[1] + r[0]
        inc r14
        jmp 15b
18:     mov rdi, r12
        mov esi, (256 << 1) | 1
        call int_cmp
        cmp eax, 0
        jge 19f
        mov edi, (256 << 1) | 1
        mov rsi, r12
        call int_sub
        mov rdi, rax
        mov rsi, r12
        mov edx, 1
        call mk_row
        mov rdi, rbx
        mov rsi, rax
        call vec_push
19:     mov rdi, rbx
        call vec_to_list
        jmp .Lso_done
.Lso_symbolic:
        mov rdi, [rsp + SO_VALUE]
        call full_row
        jmp .Lso_done
.Lso_unsortable:
        mov edi, eax                    # (python's timeout isn't an Exception)
        call err_rethrow_timeout
        mov rdi, [rsp + SO_ORIG]
        call full_row
.Lso_done:
        add rsp, MATCH_BINDINGS_SIZE + 128
        LEAVE
.Lso_assert:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_split]
        call err_throw
ENDF split_or

# sizeof(exp) -> value: the size of an expression in bits
FUNC sizeof
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE
        mov rbx, rdi
        PAT rsi, "('storage', ':size', '...')"
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 1f
        mov rax, [rsp]
        jmp .Lsz_done
1:      PAT rsi, "('mask_shl', ':size', ':off', ':shl', 'Any')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 2f
        mov rdi, [rsp]
        mov rsi, [rsp + 8]
        mov rdx, [rsp + 16]
        call alg_add3
        jmp .Lsz_done
2:      PAT rsi, "(':op', 'Any', ':size_bytes')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 3f
        mov rdi, [rsp]
        call str_id
        mov edi, eax
        call is_array_op
        test eax, eax
        jz 3f
        mov rdi, [rsp + 8]
        call alg_bits
        jmp .Lsz_done
3:      PAT rsi, "('mem', ('range', 'Any', ':size_bytes'))"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 4f
        mov rdi, [rsp]
        call alg_bits
        jmp .Lsz_done
4:      PAT rsi, "('mem', ':idx')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jnz .Lsz_assert
        PAT rsi, "('arr', ':l', 'Any')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jnz .Lsz_assert
        mov rdi, rbx
        call is_int
        test eax, eax
        jz 5f
        # above 2^256 (python's exp > 2**256: neither 2^256 itself nor a
        # negative number): the bytes needed to hold the number
        mov rdi, rbx
        call int_gt_pow2_256
        test eax, eax
        jz 5f
        mov rdi, rbx
        call int_bit_length
        add rax, 7
        shr rax, 3
        TAG rax
        mov rdi, rax
        call alg_bits
        jmp .Lsz_done
5:      mov eax, (256 << 1) | 1
.Lsz_done:
        add rsp, MATCH_BINDINGS_SIZE
        LEAVE
.Lsz_assert:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_sizeof]
        call err_throw
ENDF sizeof

# int_gt_pow2_256(v) -> eax: the int v > 2^256, read off the number
FUNC int_gt_pow2_256
        xor eax, eax
        test dil, 1
        jnz 1f                          # a small int: below 2^62
        movsxd rcx, dword ptr [rdi + N_DATA + MPZ_SIZE]
        cmp rcx, 5
        jl 1f                           # negative, or below 2^256
        jg 2f                           # 2^320 and above
        mov rdx, [rdi + N_DATA + MPZ_D]
        cmp qword ptr [rdx + 32], 1
        ja 2f                           # the high limb: 2^257 and above
        mov rcx, [rdx]                  # 2^256 + the low limbs: above
        or rcx, [rdx + 8]               # unless they are all zero
        or rcx, [rdx + 16]
        or rcx, [rdx + 24]
        jz 1f
2:      mov eax, 1
1:      ret
ENDF int_gt_pow2_256

# int_lt_pow2_256(v) -> eax: the int v < 2^256 (the negative ones too)
FUNC int_lt_pow2_256
        mov eax, 1
        test dil, 1
        jnz 1f                          # a small int
        cmp dword ptr [rdi + N_DATA + MPZ_SIZE], 4
        jle 1f                          # negative, or 4 limbs at most
        xor eax, eax
1:      ret
ENDF int_lt_pow2_256

# int_bit_length(v) -> rax: python's int.bit_length() (of |v|)
FUNC int_bit_length
        test dil, 1
        jz 1f
        mov rax, rdi
        sar rax, 1
        mov rcx, rax
        neg rcx
        cmovs rcx, rax                  # |v|
        bsr rax, rcx
        jz 2f
        inc rax
        ret
2:      xor eax, eax
        ret
1:      ENTER
        add rdi, N_DATA
        mov esi, 2
        call __gmpz_sizeinbase@PLT
        LEAVE
ENDF int_bit_length

# split_setmem(line, arg, out): a setmem of ORed parts becomes one
# setmem per part
FUNC split_setmem
        ENTER
        sub rsp, ERR_SIZEOF + 32
        mov rbx, rdi
        mov r12, rdx
        call opcode_of
        cmp eax, OP_SETMEM
        jne .Lss_asis
        cmp dword ptr [rbx + N_AUX], 3
        jne .Lss_asis
        mov rdi, [rbx + N_DATA + 16]
        call opcode_of
        cmp eax, OP_OR
        jne .Lss_asis
        mov rdi, [rbx + N_DATA + 16]
        call split_or
        mov r13, rax                    # the rows
        call vec_new
        mov [rsp + ERR_SIZEOF], rax     # the lines
        lea rdi, [rsp]
        call err_catch
        test eax, eax
        jnz .Lss_problem
        xor r14d, r14d
1:      cmp r14d, [r13 + N_AUX]
        jae 2f
        mov rax, [r13 + N_DATA + r14*8] # (size, offset, val)
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, [rax + N_DATA]
        mov rdx, [rax + N_DATA + 8]
        call apply_mask_to_range
        mov rsi, rax
        mov rax, [r13 + N_DATA + r14*8]
        mov rdx, [rax + N_DATA + 16]
        LOADS rdi, SETMEM
        call mk3
        mov rdi, [rsp + ERR_SIZEOF]
        mov rsi, rax
        call vec_push
        inc r14d
        jmp 1b
2:      call err_end
        mov rax, [rsp + ERR_SIZEOF]
        mov rdi, r12
        mov rsi, [rax + VEC_DATA]
        mov rdx, [rax + VEC_LEN]
        call vec_extend
        add rsp, ERR_SIZEOF + 32
        LEAVE
.Lss_problem:
        mov edi, eax                    # (python's timeout isn't an Exception)
        call err_rethrow_timeout
        mov edi, LOG_ERROR
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_problem_split]
        call log_fmt
.Lss_asis:
        mov rdi, r12
        mov rsi, rbx
        call vec_push
        add rsp, ERR_SIZEOF + 32
        LEAVE
ENDF split_setmem

# split_store(line, arg, out): a store of ORed parts becomes one store
# per part
FUNC split_store
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 48
        .set ST_OUT, MATCH_BINDINGS_SIZE
        .set ST_ROWS, MATCH_BINDINGS_SIZE + 8
        .set ST_IDX, MATCH_BINDINGS_SIZE + 16
        .set ST_LINES, MATCH_BINDINGS_SIZE + 24
        .set ST_I, MATCH_BINDINGS_SIZE + 32
        mov rbx, rdi
        mov [rsp + ST_OUT], rdx
        PAT rsi, "('store', 256, 0, ':int:idx', ('mask_shl', ':int:size', ':int:off', 0, ('storage', 256, 0, ':idx')))"
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 2f
        cmp qword ptr [rsp + 8], (256 << 1) | 1
        jge 2f
        # a store of the storage itself, masked: the parts outside the
        # mask are zeroed. idx [rsp], size [rsp + 8], off [rsp + 16]
        cmp qword ptr [rsp + 16], 1
        jle 1f
        mov rsi, [rsp + 16]
        mov rcx, [rsp]
        LOADS rdi, STORE
        mov edx, 1
        mov r8d, 1
        call mk5
        mov rdi, [rsp + ST_OUT]
        mov rsi, rax
        call vec_push
1:      mov rax, [rsp + 8]
        add rax, [rsp + 16]
        dec rax                         # size + off, tagged
        cmp rax, (256 << 1) | 1
        jge .Lst_done
        # ('store', 256 - size - off, size + off, idx, 0)
        mov rdx, rax
        mov esi, (256 << 1) | 1
        sub rsi, rax
        inc rsi
        mov rcx, [rsp]
        LOADS rdi, STORE
        mov r8d, 1
        call mk5
        mov rdi, [rsp + ST_OUT]
        mov rsi, rax
        call vec_push
        jmp .Lst_done
2:      PAT rsi, "('store', 256, 0, ':idx', ':val')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz .Lst_asis
        mov rax, [rsp]
        mov [rsp + ST_IDX], rax
        mov rdi, [rsp + 8]
        call split_or
        mov [rsp + ST_ROWS], rax
        call vec_new
        mov [rsp + ST_LINES], rax
        mov qword ptr [rsp + ST_I], 0
3:      mov rcx, [rsp + ST_I]
        mov rax, [rsp + ST_ROWS]
        cmp ecx, [rax + N_AUX]
        jae 5f
        mov r12, [rax + N_DATA + rcx*8] # (s_size, s_off, s_val)
        inc qword ptr [rsp + ST_I]
        # 0 <= s_off and s_size + s_off <= 256
        mov edi, 1
        mov rsi, [r12 + N_DATA + 8]
        call alg_safe_le_op
        cmp eax, TRI_TRUE
        jne .Lst_unusual
        mov rdi, [r12 + N_DATA]
        mov rsi, [r12 + N_DATA + 8]
        call alg_add2
        mov rdi, rax
        mov esi, (256 << 1) | 1
        call alg_safe_le_op
        cmp eax, TRI_TRUE
        jne .Lst_unusual
        # ignore writing the same to the same storage
        mov rsi, [r12 + N_DATA]
        mov rdx, [r12 + N_DATA + 8]
        mov rcx, [rsp + ST_IDX]
        LOADS rdi, STORAGE
        call mk4
        cmp rax, [r12 + N_DATA + 16]
        je 3b
        mov r8, [r12 + N_DATA + 16]
        mov rcx, [rsp + ST_IDX]
        mov rdx, [r12 + N_DATA + 8]
        mov rsi, [r12 + N_DATA]
        LOADS rdi, STORE
        call mk5
        mov rdi, [rsp + ST_LINES]
        mov rsi, rax
        call vec_push
        jmp 3b
5:      mov rax, [rsp + ST_LINES]
        mov rdi, [rsp + ST_OUT]
        mov rsi, [rax + VEC_DATA]
        mov rdx, [rax + VEC_LEN]
        call vec_extend
        jmp .Lst_done
.Lst_unusual:
        mov edi, LOG_WARNING
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_unusual_store]
        call log_fmt
.Lst_asis:
        mov rdi, [rsp + ST_OUT]
        mov rsi, rbx
        call vec_push
.Lst_done:
        add rsp, MATCH_BINDINGS_SIZE + 48
        LEAVE
ENDF split_store

# memloc_overwrite(memloc, split) -> list of ranges: the parts of memloc
# that are for sure not overwritten by the split
FUNC memloc_overwrite
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov edi, MEMO_MEMLOC_OVERWRITE  # (remembered for the pair: mem_use
        mov rsi, rbx                    # asks it of the same setmems for
        mov rdx, r12                    # the same memory, round after round)
        call memo2_get
        test rax, rax
        jnz 1f
        mov rdi, rbx
        mov rsi, r12
        call memloc_overwrite_impl
        mov r13, rax
        mov edi, MEMO_MEMLOC_OVERWRITE
        mov rsi, rbx
        mov rdx, r12
        mov rcx, rax
        call memo2_put
        mov rax, r13
1:      LEAVE
ENDF memloc_overwrite

FUNC memloc_overwrite_impl
        ENTER
        sub rsp, 48
        .set MO_M_RIGHT, 0
        .set MO_S_RIGHT, 8
        .set MO_LEFT_LEN, 16
        .set MO_RIGHT_LEN, 24
        mov rbx, rdi
        mov r12, rsi
        call assert_range
        mov rdi, r12
        call assert_range
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, [rbx + N_DATA + 16]
        call alg_add2
        mov [rsp + MO_M_RIGHT], rax
        mov rdi, [r12 + N_DATA + 8]
        mov rsi, [r12 + N_DATA + 16]
        call alg_add2
        mov [rsp + MO_S_RIGHT], rax
        # no overlap when the split is after or before the memory
        mov rdi, [rsp + MO_M_RIGHT]
        mov rsi, [r12 + N_DATA + 8]
        call alg_safe_le_op
        cmp eax, TRI_TRUE
        je .Lmo_whole
        mov rdi, [rsp + MO_S_RIGHT]
        mov rsi, [rbx + N_DATA + 8]
        call alg_safe_le_op
        cmp eax, TRI_TRUE
        je .Lmo_whole
        mov rdi, [r12 + N_DATA + 8]
        mov rsi, [rbx + N_DATA + 8]
        call alg_sub_op
        mov [rsp + MO_LEFT_LEN], rax
        mov rdi, [rsp + MO_M_RIGHT]
        mov rsi, [rsp + MO_S_RIGHT]
        call alg_sub_op
        mov [rsp + MO_RIGHT_LEN], rax
        mov rdi, [rsp + MO_LEFT_LEN]
        call alg_safe_ge_zero
        mov r13d, eax
        mov rdi, [rsp + MO_RIGHT_LEN]
        call alg_safe_ge_zero
        mov r14d, eax
        # we can't compare some numbers: conservatively the whole range
        cmp r13d, TRI_NONE
        je .Lmo_whole
        cmp r14d, TRI_NONE
        je .Lmo_whole
        call vec_new
        mov r12, rax
        cmp r13d, TRI_TRUE
        jne 1f
        cmp qword ptr [rsp + MO_LEFT_LEN], 1
        je 1f
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, [rsp + MO_LEFT_LEN]
        call mk_range
        mov rdi, r12
        mov rsi, rax
        call vec_push
1:      cmp r14d, TRI_TRUE
        jne 2f
        cmp qword ptr [rsp + MO_RIGHT_LEN], 1
        je 2f
        mov rdi, [rsp + MO_S_RIGHT]
        mov rsi, [rsp + MO_RIGHT_LEN]
        call mk_range
        mov rdi, r12
        mov rsi, rax
        call vec_push
2:      mov rdi, r12
        call vec_to_list
        add rsp, 48
        LEAVE
.Lmo_whole:
        mov rdi, rbx
        call mk_list1
        add rsp, 48
        LEAVE
ENDF memloc_overwrite_impl

# slice_exp(exp, left, right) -> value or NIL: the bytes left..right of
# the expression
FUNC slice_exp
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 32
        .set SL_SIZE, MATCH_BINDINGS_SIZE
        .set SL_OFF, MATCH_BINDINGS_SIZE + 8
        mov rbx, rdi
        mov r12, rsi                    # left
        mov r13, rdx                    # right
        mov rdi, rdx
        mov rsi, r12
        call alg_sub_op
        mov [rsp + SL_SIZE], rax        # size = right - left
        PAT rsi, "('mem', ('range', ':rleft', ':rlen'))"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 1f
        # ('mem', ('range', rleft + left, size)) when left + size <= rlen
        mov rdi, r12
        mov rsi, [rsp + SL_SIZE]
        call alg_add2
        mov rdi, rax
        mov rsi, [rsp + 8]
        call alg_safe_le_op
        cmp eax, TRI_TRUE
        jne .Lsl_none
        mov rdi, [rsp]
        mov rsi, r12
        call alg_add2
        mov rdi, rax
        mov rsi, [rsp + SL_SIZE]
        call mk_mem_range
        jmp .Lsl_done
1:      PAT rsi, "(':op', ':rleft', ':rlen')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 2f
        mov rdi, [rsp]
        call str_id
        mov edi, eax
        call is_array_op
        test eax, eax
        jz 2f
        mov rdi, r12
        mov rsi, [rsp + SL_SIZE]
        call alg_add2
        mov rdi, rax
        mov rsi, [rsp + 16]
        call alg_safe_le_op
        cmp eax, TRI_TRUE
        jne .Lsl_none
        mov rdi, [rsp + 8]
        mov rsi, r12
        call alg_add2
        mov rsi, rax
        mov rdi, [rsp]
        mov rdx, [rsp + SL_SIZE]
        call mk3
        jmp .Lsl_done
2:      # a mask: size 8*size bits, at sizeof(exp) - 8*right
        mov rdi, rbx
        call sizeof
        mov r14, rax
        mov rdi, r13
        call alg_bits
        mov rdi, r14
        mov rsi, rax
        call alg_sub_op
        mov [rsp + SL_OFF], rax
        mov rdi, [rsp + SL_SIZE]
        call alg_bits
        mov rsi, rax
        mov rdi, rbx
        mov rdx, [rsp + SL_OFF]
        mov ecx, 1
        mov r8, [rsp + SL_OFF]
        call alg_mask_op
        jmp .Lsl_done
.Lsl_none:
        xor eax, eax
.Lsl_done:
        add rsp, MATCH_BINDINGS_SIZE + 32
        LEAVE
ENDF slice_exp

# splits_mem(memloc, split, memval, split_val) -> list of (range, value):
# the memory values we can be confident of after the split part of the
# memory is overwritten (split_val = NIL when unknown)
FUNC splits_mem
        ENTER
        sub rsp, 144
        .set SM_MEMVAL, 0
        .set SM_SPLIT_VAL, 8
        .set SM_M_RIGHT, 16
        .set SM_S_RIGHT, 24
        .set SM_S_LEN, 32
        .set SM_LEFT, 40
        .set SM_RIGHT, 48
        .set SM_IN_LEFT, 56
        .set SM_IN_RIGHT, 64
        .set SM_VAL_LEFT, 72
        .set SM_VAL_RIGHT, 80
        .set SM_RES, 88
        .set SM_CLEFT, 96
        .set SM_CRIGHT, 104
        .set SM_CLEN, 112
        .set SM_CVAL, 120
        .set SM_TMP, 128
        mov [rsp + SM_MEMVAL], rdx
        mov [rsp + SM_SPLIT_VAL], rcx
        mov rbx, rdi
        mov r12, rsi
        call assert_range
        mov rdi, r12
        call assert_range
        mov rax, [r12 + N_DATA + 16]
        mov [rsp + SM_S_LEN], rax
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, [rbx + N_DATA + 16]
        call alg_add2
        mov [rsp + SM_M_RIGHT], rax
        mov rdi, [r12 + N_DATA + 8]
        mov rsi, [rsp + SM_S_LEN]
        call alg_add2
        mov [rsp + SM_S_RIGHT], rax
        # a split of unknown sign is of undefined length
        mov rdi, [rsp + SM_S_LEN]
        call alg_safe_ge_zero
        cmp eax, TRI_TRUE
        je 1f
        LOADS rax, UNDEFINED
        mov [rsp + SM_S_LEN], rax
        mov rdi, [r12 + N_DATA + 8]
        mov rsi, rax
        call alg_add2
        mov [rsp + SM_S_RIGHT], rax
1:      # no overlap when the split is after or before the memory
        mov rdi, [rsp + SM_M_RIGHT]
        mov rsi, [r12 + N_DATA + 8]
        call alg_safe_le_op
        cmp eax, TRI_TRUE
        je .Lsm_untouched
        mov rdi, [rsp + SM_S_RIGHT]
        mov rsi, [rbx + N_DATA + 8]
        call alg_safe_le_op
        cmp eax, TRI_TRUE
        je .Lsm_untouched
        mov rdi, [r12 + N_DATA + 8]
        mov rsi, [rbx + N_DATA + 8]
        call alg_safe_max_op
        mov [rsp + SM_LEFT], rax        # (NIL for python's None)
        mov rdi, [rsp + SM_S_RIGHT]
        mov rsi, [rsp + SM_M_RIGHT]
        call alg_safe_min_op
        mov [rsp + SM_RIGHT], rax
        # left/right relative to the beginning of the memory location
        mov rdi, [rsp + SM_LEFT]
        call none_if_nil
        mov rdi, rax
        mov rsi, [rbx + N_DATA + 8]
        call alg_sub_op
        mov [rsp + SM_IN_LEFT], rax
        mov rdi, [rsp + SM_RIGHT]
        call none_if_nil
        mov rdi, rax
        mov rsi, [rbx + N_DATA + 8]
        call alg_sub_op
        mov [rsp + SM_IN_RIGHT], rax
        # we must be sure the split begins inside the memory
        mov rdi, [rsp + SM_IN_LEFT]
        mov rsi, [rbx + N_DATA + 16]
        call alg_safe_le_op
        cmp eax, TRI_TRUE
        jne .Lsm_unsure
        cmp qword ptr [rsp + SM_LEFT], 0
        je .Lsm_unsure
        # (a split ending before the memory can't begin inside it)
        mov rdi, [rsp + SM_RIGHT]
        call none_if_nil
        mov rdi, rax
        mov rsi, [rbx + N_DATA + 8]
        call alg_safe_le_op
        cmp eax, TRI_TRUE
        jne 8f
        cmp qword ptr [rsp + SM_IN_LEFT], 1
        jne .Lsm_assert
8:      # the untouched values on each side
        mov rdi, [rsp + SM_MEMVAL]
        mov esi, 1
        mov rdx, [rsp + SM_IN_LEFT]
        call slice_exp
        mov [rsp + SM_VAL_LEFT], rax
        mov qword ptr [rsp + SM_VAL_RIGHT], 0
        cmp qword ptr [rsp + SM_RIGHT], 0
        je 2f
        mov rdi, [rsp + SM_M_RIGHT]
        mov rsi, [rbx + N_DATA + 8]
        call alg_sub_op
        mov rdi, [rsp + SM_MEMVAL]
        mov rsi, [rsp + SM_IN_RIGHT]
        mov rdx, rax
        call slice_exp
        mov [rsp + SM_VAL_RIGHT], rax
2:      call vec_new
        mov [rsp + SM_RES], rax
        mov rdi, [rsp + SM_LEFT]
        mov rsi, [rbx + N_DATA + 8]
        call alg_sub_op
        mov r13, rax                    # left_len
        mov rdi, [rsp + SM_RIGHT]
        call none_if_nil
        mov rsi, rax
        mov rdi, [rsp + SM_M_RIGHT]
        call alg_sub_op
        mov r14, rax                    # right_len
        mov rdi, r13
        call alg_safe_ge_zero
        cmp eax, TRI_TRUE
        jne 3f
        cmp r13, 1
        je 3f
        cmp qword ptr [rsp + SM_VAL_LEFT], 0
        je 3f
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, r13
        call mk_range
        mov rdi, rax
        mov rsi, [rsp + SM_VAL_LEFT]
        call mk2
        mov rdi, [rsp + SM_RES]
        mov rsi, rax
        call vec_push
3:      cmp qword ptr [rsp + SM_SPLIT_VAL], 0
        je 6f
        # the part of the split value inside the memory location
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, [r12 + N_DATA + 8]
        call alg_safe_max_op
        mov rdi, rax
        call none_if_nil
        mov [rsp + SM_CLEFT], rax
        mov rdi, [rsp + SM_M_RIGHT]
        mov rsi, [rsp + SM_S_RIGHT]
        call alg_safe_min_op
        mov rdi, rax
        call none_if_nil
        mov [rsp + SM_CRIGHT], rax
        mov rdi, rax
        mov rsi, [rsp + SM_CLEFT]
        call alg_sub_op
        mov [rsp + SM_CLEN], rax
        mov rdi, [rsp + SM_SPLIT_VAL]
        call opcode_of
        mov edi, eax
        call is_array_op
        test eax, eax
        jz 4f
        # mem[a len b] = calldata[x len b]; log mem[c len d] ->
        # calldata[x + c - a, center_len]
        mov rdi, [rsp + SM_CLEFT]
        mov rsi, [r12 + N_DATA + 8]
        call alg_sub_op
        mov rsi, rax
        mov rdi, [rsp + SM_SPLIT_VAL]
        mov rdi, [rdi + N_DATA + 8]
        call alg_add2
        mov rsi, rax
        mov rax, [rsp + SM_SPLIT_VAL]
        mov rdi, [rax + N_DATA]
        mov rdx, [rsp + SM_CLEN]
        call mk3
        mov [rsp + SM_CVAL], rax
        jmp 5f
4:      # center_offset = s_right - center_right;
        # mask(split_val, 8*len, 8*offset, shr=8*offset)
        mov rdi, [rsp + SM_S_RIGHT]
        mov rsi, [rsp + SM_CRIGHT]
        call alg_sub_op
        mov rdi, rax
        mov esi, (8 << 1) | 1
        call alg_mul2
        mov [rsp + SM_TMP], rax
        mov rdi, [rsp + SM_CLEN]
        mov esi, (8 << 1) | 1
        call alg_mul2
        mov rsi, rax
        mov rdi, [rsp + SM_SPLIT_VAL]
        mov rdx, [rsp + SM_TMP]
        mov ecx, 1
        mov r8, [rsp + SM_TMP]
        call alg_mask_op
        mov [rsp + SM_CVAL], rax
5:      mov rdi, [rsp + SM_CLEN]
        call alg_safe_ge_zero
        cmp eax, TRI_TRUE
        jne 6f
        cmp qword ptr [rsp + SM_CLEN], 1
        je 6f
        mov rdi, [rsp + SM_CLEFT]
        mov rsi, [rsp + SM_CLEN]
        call mk_range
        mov rdi, rax
        mov rsi, [rsp + SM_CVAL]
        call mk2
        mov rdi, [rsp + SM_RES]
        mov rsi, rax
        call vec_push
6:      mov rdi, r14
        call alg_safe_ge_zero
        cmp eax, TRI_TRUE
        jne 7f
        cmp r14, 1
        je 7f
        cmp qword ptr [rsp + SM_VAL_RIGHT], 0
        je 7f
        mov rdi, [rsp + SM_RIGHT]
        mov rsi, r14
        call mk_range
        mov rdi, rax
        mov rsi, [rsp + SM_VAL_RIGHT]
        call mk2
        mov rdi, [rsp + SM_RES]
        mov rsi, rax
        call vec_push
7:      mov rdi, [rsp + SM_RES]
        call vec_to_list
        add rsp, 144
        LEAVE
.Lsm_untouched:
        mov rdi, rbx
        mov rsi, [rsp + SM_MEMVAL]
        call mk2
        mov rdi, rax
        call mk_list1
        add rsp, 144
        LEAVE
.Lsm_unsure:
        xor edi, edi
        xor esi, esi
        call mk_list
        add rsp, 144
        LEAVE
.Lsm_assert:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_split]
        call err_throw
ENDF splits_mem

# none_if_nil(v) -> rax: python's None for a NIL result
FUNC none_if_nil
        mov rax, rdi
        test rdi, rdi
        jnz 1f
        lea rax, [rip + sp_none]
1:      ret
ENDF none_if_nil

# replace_max_with_MAX(exp) -> rax, rdx: the expression with its (last)
# max replaced by the symbol MAX, and that max (NIL when none)
FUNC replace_max_with_MAX
        ENTER
        mov rbx, rdi
        call opcode_of
        cmp eax, OP_MAX
        je 1f
        mov rax, rbx
        xor edx, edx
        LEAVE
1:      mov rdi, rbx
        call alg_max_to_add
        mov rbx, rax
        mov r12, rax                    # res: the last max among the elements
        mov rdi, rbx
        call is_seq
        test eax, eax
        jz 3f
        xor r13d, r13d
2:      cmp r13d, [rbx + N_AUX]
        jae 3f
        mov rdi, [rbx + N_DATA + r13*8]
        call opcode_of
        cmp eax, OP_MAX
        jne 4f
        mov r12, [rbx + N_DATA + r13*8]
4:      inc r13d
        jmp 2b
3:      lea rdi, [rip + .Ls_MAX]
        call str_intern_c
        mov rdi, rbx
        mov rsi, r12
        mov rdx, rax
        call replace
        mov rdi, rax
        call alg_simplify
        mov rdx, r12
        LEAVE
ENDF replace_max_with_MAX

# fill_mem(exp, split, split_val) -> value: the memory read `exp` with
# the part the split overwrote filled in
FUNC fill_mem
        ENTER
        sub rsp, 128
        .set FM_EXP, 0
        .set FM_SPLIT, 8
        .set FM_SPLIT_VAL, 16
        .set FM_MEMLOC, 24
        .set FM_M_RIGHT, 32
        .set FM_S_RIGHT, 40
        .set FM_LEFT, 48
        .set FM_RIGHT, 56
        .set FM_RES_LEFT, 64
        .set FM_RES_RIGHT, 72
        .set FM_RES_CENTER, 80
        .set FM_RES, 88
        .set FM_MEMLOC_MAX, 96
        .set FM_TMP, 104
        mov [rsp + FM_EXP], rdi
        mov [rsp + FM_SPLIT], rsi
        mov [rsp + FM_SPLIT_VAL], rdx
        mov rbx, rdi
        mov r12, rsi
        # exp == ('mem', split)?
        LOADS rdi, MEM
        mov rsi, r12
        call mk2
        cmp rax, rbx
        jne 1f
        mov rax, [rsp + FM_SPLIT_VAL]
        jmp .Lfm_done
1:      mov rdi, rbx
        call opcode_of
        cmp eax, OP_MEM
        jne .Lfm_assert
        cmp dword ptr [rbx + N_AUX], 2
        jne .Lfm_assert
        mov r13, [rbx + N_DATA + 8]     # memloc
        mov [rsp + FM_MEMLOC], r13
        mov rdi, r13
        call assert_range
        mov rdi, r12
        call assert_range
        mov rdi, [r13 + N_DATA + 8]
        mov rsi, [r13 + N_DATA + 16]
        call alg_add2
        mov [rsp + FM_M_RIGHT], rax
        mov rdi, [r12 + N_DATA + 8]
        mov rsi, [r12 + N_DATA + 16]
        call alg_add2
        mov [rsp + FM_S_RIGHT], rax
        # the split must overlap the memory for sure
        mov rdi, [rsp + FM_M_RIGHT]
        mov rsi, [r12 + N_DATA + 8]
        call alg_safe_le_op
        cmp eax, TRI_FALSE
        jne .Lfm_asis
        mov rdi, [rsp + FM_S_RIGHT]
        mov rsi, [r13 + N_DATA + 8]
        call alg_safe_le_op
        cmp eax, TRI_FALSE
        jne .Lfm_asis
        mov rdi, [r12 + N_DATA + 8]
        mov rsi, [r13 + N_DATA + 8]
        call alg_safe_max_op
        mov [rsp + FM_LEFT], rax
        test rax, rax
        jz .Lfm_asis
        mov rdi, [rsp + FM_S_RIGHT]
        mov rsi, [rsp + FM_M_RIGHT]
        call alg_safe_min_op
        mov [rsp + FM_RIGHT], rax
        test rax, rax
        jz .Lfm_asis
        # 'max' tends to mess up with all the algebra: a variable stands
        # for it for the time being
        mov rdi, r13
        call replace_max_with_MAX
        mov r13, rax
        mov [rsp + FM_MEMLOC_MAX], rdx
        mov rdi, r12
        call replace_max_with_MAX
        mov r12, rax
        cmp rdx, [rsp + FM_MEMLOC_MAX]
        je 2f
        mov edi, LOG_WARNING
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_different_maxes]
        call log_fmt
        jmp .Lfm_asis
2:      # (before_split, split_val, after_split)
        mov rdi, [rsp + FM_LEFT]
        mov rsi, [r13 + N_DATA + 8]
        call alg_sub_op
        mov rdi, rbx
        mov esi, 1
        mov rdx, rax
        call slice_exp
        mov [rsp + FM_RES_LEFT], rax
        test rax, rax
        jz .Lfm_asis
        mov rdi, [rsp + FM_RIGHT]
        mov rsi, [r13 + N_DATA + 8]
        call alg_sub_op
        mov [rsp + FM_TMP], rax
        mov rdi, [rsp + FM_M_RIGHT]
        mov rsi, [r13 + N_DATA + 8]
        call alg_sub_op
        mov rdi, rbx
        mov rsi, [rsp + FM_TMP]
        mov rdx, rax
        call slice_exp
        mov [rsp + FM_RES_RIGHT], rax
        test rax, rax
        jz .Lfm_asis
        call vec_new
        mov [rsp + FM_RES], rax
        mov rdi, [rsp + FM_RES_LEFT]
        call sizeof
        mov rdi, rax
        call alg_safe_gt_zero
        cmp eax, TRI_TRUE
        jne 3f
        mov rdi, [rsp + FM_RES]
        mov rsi, [rsp + FM_RES_LEFT]
        call vec_push
        jmp 4f
3:      cmp eax, TRI_NONE
        je .Lfm_asis
4:      # the inserted value, cut to the overlap
        mov rdi, [rsp + FM_LEFT]
        mov rsi, [r12 + N_DATA + 8]
        call alg_sub_op
        mov [rsp + FM_TMP], rax
        mov rdi, [rsp + FM_RIGHT]
        mov rsi, [r12 + N_DATA + 8]
        call alg_sub_op
        mov rdi, [rsp + FM_SPLIT_VAL]
        mov rsi, [rsp + FM_TMP]
        mov rdx, rax
        call slice_exp
        mov [rsp + FM_RES_CENTER], rax
        test rax, rax
        jz .Lfm_asis
        mov rdi, rax
        call sizeof
        mov rdi, rax
        call alg_safe_ge_zero
        cmp eax, TRI_TRUE
        jne .Lfm_center_assert
        mov rdi, [rsp + FM_RES]
        mov rsi, [rsp + FM_RES_CENTER]
        call vec_push
        mov rdi, [rsp + FM_RES_RIGHT]
        call sizeof
        mov [rsp + FM_TMP], rax
        mov rdi, rax
        call alg_safe_ge_zero
        cmp eax, TRI_TRUE
        jne 5f
        cmp qword ptr [rsp + FM_TMP], 1
        je 6f
        mov rdi, [rsp + FM_RES]
        mov rsi, [rsp + FM_RES_RIGHT]
        call vec_push
        jmp 6f
5:      cmp eax, TRI_NONE
        je .Lfm_asis
6:      mov rdi, [rsp + FM_RES]
        LOADS rsi, DATA
        call vec_prepend
        mov rdi, [rsp + FM_RES]
        call vec_to_tuple
        jmp .Lfm_done
.Lfm_asis:
        mov rax, [rsp + FM_EXP]
.Lfm_done:
        add rsp, 128
        LEAVE
.Lfm_assert:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_range]
        call err_throw
.Lfm_center_assert:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_center]
        call err_throw
ENDF fill_mem

# range_overlaps(range1, range2) -> eax: TRI_TRUE / TRI_FALSE / TRI_NONE
# (memoized, as python's @cached)
FUNC range_overlaps
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov edi, MEMO_RANGE_OVERLAPS
        mov rsi, rbx
        mov rdx, r12
        call memo2_get
        test rax, rax
        jz 1f
        mov rdi, rax
        call memo_to_tri
        LEAVE
1:      mov rdi, rbx
        mov rsi, r12
        call range_overlaps_impl
        mov r14d, eax
        mov edi, eax
        call tri_to_memo
        mov edi, MEMO_RANGE_OVERLAPS
        mov rsi, rbx
        mov rdx, r12
        mov rcx, rax
        call memo2_put
        mov eax, r14d
        LEAVE
ENDF range_overlaps

FUNC range_overlaps_impl
        ENTER
        sub rsp, 32
        mov rbx, rdi
        mov r12, rsi
        call assert_range
        mov rdi, r12
        call assert_range
        mov rax, [rbx + N_DATA + 8]
        mov [rsp], rax                  # r1_begin
        mov rax, [r12 + N_DATA + 8]
        mov [rsp + 8], rax              # r2_begin
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, [rbx + N_DATA + 16]
        call alg_add2
        mov [rsp + 16], rax             # r1_end
        mov rdi, [r12 + N_DATA + 8]
        mov rsi, [r12 + N_DATA + 16]
        call alg_add2
        mov [rsp + 24], rax             # r2_end
        mov rdi, [rsp + 8]
        mov rsi, [rsp]
        call alg_lt_op
        cmp eax, TRI_CANNOT
        je .Lro_none
        cmp eax, TRI_TRUE
        jne 1f
        # r2 begins first: swap
        mov rax, [rsp]
        xchg rax, [rsp + 8]
        mov [rsp], rax
        mov rax, [rsp + 16]
        xchg rax, [rsp + 24]
        mov [rsp + 16], rax
1:      # r1 begins before r2 for sure now: they overlap unless r1 ends first
        mov rdi, [rsp + 16]
        mov rsi, [rsp + 8]
        call alg_le_op
        cmp eax, TRI_CANNOT
        je .Lro_none
        cmp eax, TRI_TRUE
        setne al
        movzx eax, al
        add rsp, 32
        LEAVE
.Lro_none:
        mov eax, TRI_NONE
        add rsp, 32
        LEAVE
ENDF range_overlaps_impl

# range_contains(outer, inner) -> eax: TRI_TRUE / TRI_FALSE / TRI_NONE:
# outer fully contains inner
FUNC range_contains
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        call assert_range
        mov rdi, r12
        call assert_range
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, [rbx + N_DATA + 16]
        call alg_add2
        mov [rsp], rax                  # outer_end
        mov rdi, [r12 + N_DATA + 8]
        mov rsi, [r12 + N_DATA + 16]
        call alg_add2
        mov [rsp + 8], rax              # inner_end
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, [r12 + N_DATA + 8]
        call alg_le_op
        cmp eax, TRI_CANNOT
        je .Lrc_none
        cmp eax, TRI_TRUE
        jne .Lrc_false
        mov rdi, [rsp + 8]
        mov rsi, [rsp]
        call alg_le_op
        cmp eax, TRI_CANNOT
        je .Lrc_none
        cmp eax, TRI_TRUE
        jne .Lrc_false
        mov eax, TRI_TRUE
        add rsp, 16
        LEAVE
.Lrc_false:
        mov eax, TRI_FALSE
        add rsp, 16
        LEAVE
.Lrc_none:
        mov eax, TRI_NONE
        add rsp, 16
        LEAVE
ENDF range_contains

        .section .note.GNU-stack,"",@progbits
