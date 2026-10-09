# Memory locations (port of core/memloc.py): splitting the values written
# to memory and to storage into their pieces, and the overlaps of memory
# ranges. The widths of what's in memory are in widths.s.
#
# Ranges are ('range', position, length) in bytes; the rows of a split are
# (size, offset, value) in bits. The comparisons are the memory model's
# (mem_lt_op, mem_safe_le_op...: algebra's with top=MEMORY_TOP), of
# addresses that don't wrap around 2^256 (mem_words4, python's words).

.include "defs.inc"

        .section .rodata
.Ls_assert_bits:    .asciz "apply_mask_to_range: sizes not in whole bytes"
.Ls_assert_fits:    .asciz "apply_mask_to_range: the mask doesn't fit the range"
.Ls_assert_range:   .asciz "not a range"
.Ls_assert_split:   .asciz "split_or: unexpected second row"
.Ls_assert_inleft:  .asciz "splits_mem: the split ends before the memory"
.Ls_index:          .asciz "tuple index out of range"
.Ls_unpack:         .asciz "unexpected number of values to unpack"
.Ls_not_iterable:   .asciz "cannot unpack non-iterable object"
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

# unpack_range(v): python's `op, pos, len = v; assert op == "range"` - a
# TypeError for what isn't a sequence, a ValueError for a sequence (or a
# string) of another length than 3, an AssertionError for another head
# (split_or catches the AssertionErrors of apply_mask_to_range only)
FUNC unpack_range
        test dil, 1
        jnz .Lur_type
        test rdi, rdi
        jz .Lur_type
        mov eax, [rdi + N_KIND]
        cmp eax, K_TUPLE
        je 1f
        cmp eax, K_LIST
        je 1f
        cmp eax, K_STR
        jne .Lur_type
        test dword ptr [rdi + N_AUX], STR_FLOAT
        jnz .Lur_type
        cmp dword ptr [rdi + N_DATA], 3         # (a string of 3 is 3 strings)
        jne throw_unpack
        jmp .Lur_assert
1:      cmp dword ptr [rdi + N_AUX], 3
        jne throw_unpack
        LOADS rax, RANGE
        cmp rax, [rdi + N_DATA]
        jne .Lur_assert
        ret
.Lur_assert:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_range]
        jmp err_throw
.Lur_type:
        mov edi, E_TYPE
        lea rsi, [rip + .Ls_not_iterable]
        jmp err_throw
ENDF unpack_range

# throw_index(), throw_unpack(): python's IndexError, ValueError
FUNC throw_index
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_index]
        jmp err_throw
ENDF throw_index

FUNC throw_unpack
        mov edi, E_VALUE
        lea rsi, [rip + .Ls_unpack]
        jmp err_throw
ENDF throw_unpack

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

# mem_words4(a, b, c, d) -> eax: python's words(a, b, c, d) - each of them
# a memory address that doesn't wrap around 2^256 (see memory_range), in
# this order, the first that does deciding
FUNC mem_words4
        ENTER
        mov rbx, rsi
        mov r12, rdx
        mov r13, rcx
        call mem_words
        test eax, eax
        jz 9f
        mov rdi, rbx
        call mem_words
        test eax, eax
        jz 9f
        mov rdi, r12
        call mem_words
        test eax, eax
        jz 9f
        mov rdi, r13
        call mem_words
9:      LEAVE
ENDF mem_words4

# apply_mask_to_range(memloc, size, offset) -> ('range', pos, len): the
# part of the range a mask of `size` bits at `offset` covers (asserts
# when they aren't whole bytes, or when the mask doesn't fit)
FUNC apply_mask_to_range
        ENTER
        sub rsp, 32
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        call unpack_range
        mov rdi, r12
        call to_bytes
        mov [rsp], rax                  # size_bytes
        mov [rsp + 24], rdx             # size_bits
        mov rdi, r13
        call to_bytes
        mov [rsp + 8], rax              # offset_bytes
        cmp rdx, 1                      # offset_bits == size_bits == 0
        jne .Lamr_bits
        cmp qword ptr [rsp + 24], 1
        jne .Lamr_bits
        mov rdi, [rsp]
        mov rsi, [rsp + 8]
        call alg_add2
        mov [rsp + 16], rax             # size + offset, in bytes
        mov rdi, rax
        mov rsi, [rbx + N_DATA + 16]    # range_len
        call mem_safe_le_op
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
# may raise CannotCompare); 1 when a < b, 0 otherwise
FUNC row_lt
        ENTER
        mov rdi, [rdi + N_DATA + 8]
        mov rsi, [rsi + N_DATA + 8]
        call mem_lt_op
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
# made of ORed parts (masks, bytes of memory, fields of storage, truth
# values...), sorted by offset, with zeroes in the gaps - the value as one
# piece, [(256, 0, value)], when it can't be split so
FUNC split_or
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 128
        .set SO_ORIG, MATCH_BINDINGS_SIZE
        .set SO_ROWS, MATCH_BINDINGS_SIZE + 8
        .set SO_SIZE, MATCH_BINDINGS_SIZE + 16
        .set SO_OFFSET, MATCH_BINDINGS_SIZE + 24
        .set SO_SHL, MATCH_BINDINGS_SIZE + 32
        .set SO_STOR_OFFSET, MATCH_BINDINGS_SIZE + 40
        .set SO_VALUE, MATCH_BINDINGS_SIZE + 48    # the value of the mask
        .set SO_IDX, MATCH_BINDINGS_SIZE + 56      # (the gaps' loop)
        .set SO_ERR, MATCH_BINDINGS_SIZE + 64      # (64 bytes)
        mov [rsp + SO_ORIG], rdi
        mov rbx, rdi
        call opcode_of
        cmp eax, OP_OR
        je 1f
        cmp eax, OP_MASK_SHL
        jne .Lso_whole
        # a single mask: ('or', value)
        mov rsi, rbx
        LOADS rdi, OR
        call mk2
        mov rbx, rax
1:      call vec_new
        mov [rsp + SO_ROWS], rax
        mov r12d, 1                     # the term
.Lso_term:
        cmp r12d, [rbx + N_AUX]
        jae .Lso_terms_done
        mov r13, [rbx + N_DATA + r12*8] # row
        inc r12d
        # (does weird things if size == 1, in loops.activateSafeMode)
        PAT rsi, "('bool', ':arg')"
        mov rdi, r13
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 3f
        mov rsi, [rsp]
        LOADS rdi, BOOL
        call mk2
        mov r8, rax
        LOADS rdi, MASK_SHL
        mov esi, (8 << 1) | 1
        mov edx, 1
        mov ecx, 1
        call mk5
        mov r13, rax
3:      LOADS rax, CALLER
        cmp r13, rax
        jne 5f
        mov r8, r13
        LOADS rdi, MASK_SHL
        mov esi, (160 << 1) | 1
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
6:      # 0, or the bits of a value above its top (Mask(56, 200,
        # uint200(x))): nothing
        mov rdi, r13
        mov esi, 1
        call py_equal
        test eax, eax
        jnz .Lso_term
        mov rdi, r13
        call opcode_of
        cmp eax, OP_MASK_SHL
        jne .Lso_not_mask
        # (python reads row[2] and row[4], then unpacks five of them: a
        # shorter mask is an IndexError, or a ValueError)
        cmp dword ptr [r13 + N_AUX], 5
        jb .Lso_index
        mov rdi, [r13 + N_DATA + 16]
        call is_int
        test eax, eax
        jz 7f
        mov rdi, [r13 + N_DATA + 32]
        call value_bits
        mov rdi, rax
        mov rsi, [r13 + N_DATA + 16]
        call int_cmp
        cmp eax, 0
        jle .Lso_term
7:      # a mask of numbers: the number it is
        mov edi, [r13 + N_AUX]
        dec edi
        lea rsi, [r13 + N_DATA + 8]
        call all_ints
        test eax, eax
        jz 8f
        mov rdi, [r13 + N_DATA + 32]
        mov rsi, [r13 + N_DATA + 8]
        mov rdx, [r13 + N_DATA + 16]
        mov rcx, [r13 + N_DATA + 24]
        call alg_apply_mask
        mov r13, rax
        jmp .Lso_number
8:      cmp dword ptr [r13 + N_AUX], 5
        jne .Lso_unpack
        jmp .Lso_mask
.Lso_not_mask:
        mov rdi, r13
        call is_int
        test eax, eax
        jnz .Lso_number
        PAT rsi, "('mem', ':mem_idx')"
        mov rdi, r13
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 10f
        mov rdi, [rsp]
        call opcode_of
        cmp eax, OP_RANGE
        je 9f
        mov rdi, [rsp]
        mov esi, (32 << 1) | 1
        call mk_range
        mov [rsp], rax
9:      mov rax, [rsp]
        cmp dword ptr [rax + N_AUX], 3
        jb .Lso_index
        mov rdi, [rax + N_DATA + 16]    # mem_len
        call alg_bits
        mov rdi, rax
        mov esi, 1
        mov rdx, r13
        call mk_row
        jmp .Lso_push
10:     PAT rsi, "('storage', ':size', ':off', ':idx')"
        mov rdi, r13
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 12f
        mov rdi, [rsp + 8]
        call is_int
        test eax, eax
        jz 11f
        mov rdi, [rsp + 8]
        call int_sign
        test eax, eax
        jns 11f
        # a field moved left (see algebra.apply_mask_to_storage)
        mov rdi, [rsp + 8]
        call int_neg
        mov [rsp + 8], rax
        mov rcx, [rsp + 16]
        mov rsi, [rsp]
        LOADS rdi, STORAGE
        mov edx, 1
        call mk4
        mov rdx, rax
        mov rdi, [rsp]
        mov rsi, [rsp + 8]
        call mk_row
        jmp .Lso_push
11:     mov rdi, [rsp]
        mov esi, 1
        mov rdx, r13
        call mk_row
        jmp .Lso_push
12:     # a truth value (x < y, iszero(x)...): its bits from the bit 0
        mov rdi, r13
        call value_bits
        mov r14, rax
        mov rdi, rax
        mov esi, (256 << 1) | 1
        call int_cmp
        test eax, eax
        jns .Lso_whole
        mov rdi, r14
        mov esi, 1
        mov rdx, r13
        call mk_row
        jmp .Lso_push
.Lso_number:
        # a number: the bytes it spans, as a mask of it
        mov rdi, r13
        call find_mask
        mov rsi, rax
        mov r8, r13
        mov ecx, 1
        LOADS rdi, MASK_SHL
        call mk5
        mov r13, rax
.Lso_mask:
        # _, size, offset, shl, value = row
        mov rax, [r13 + N_DATA + 8]
        mov [rsp + SO_SIZE], rax
        mov rax, [r13 + N_DATA + 16]
        mov [rsp + SO_OFFSET], rax
        mov rax, [r13 + N_DATA + 24]
        mov [rsp + SO_SHL], rax
        mov rax, [r13 + N_DATA + 32]
        mov [rsp + SO_VALUE], rax
        # a part that goes past the top of the word: x << 128 is all of x
        # moved, as the code shifted it (see shl_op), not 256 bits of the
        # word - the word is written whole, as it's computed
        mov rdi, [rsp + SO_SIZE]
        call is_int
        test eax, eax
        jz 25f
        mov rdi, [rsp + SO_OFFSET]
        call is_int
        test eax, eax
        jz 25f
        mov rdi, [rsp + SO_SHL]
        call is_int
        test eax, eax
        jz 25f
        mov rdi, [rsp + SO_SIZE]
        mov rsi, [rsp + SO_OFFSET]
        call int_add
        mov rdi, rax
        mov rsi, [rsp + SO_SHL]
        call int_add
        mov rdi, rax
        mov esi, (256 << 1) | 1
        call int_cmp
        test eax, eax
        jg .Lso_whole
25:     # stor_offset = offset + shl; shl = shl - stor_offset
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
        jz 21f
        mov rdi, [rsp + SO_SIZE]
        call is_int
        test eax, eax
        jz 21f
        mov rdi, [rsp + SO_OFFSET]
        call is_int
        test eax, eax
        jz 21f
        mov rdi, [rsp + SO_SHL]
        call is_int
        test eax, eax
        jz 21f
        mov rdi, [rsp + SO_VALUE]
        mov rsi, [rsp + SO_SIZE]
        mov rdx, [rsp + SO_OFFSET]
        mov rcx, [rsp + SO_SHL]
        call alg_apply_mask
        mov [rsp + SO_VALUE], rax
        jmp 24f
21:     PAT rsi, "('mem', ':idx')"
        mov rdi, [rsp + SO_VALUE]
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 23f
        mov rdi, [rsp + SO_OFFSET]
        mov rsi, [rsp + SO_SHL]
        call alg_add2
        cmp rax, 1
        jne 23f
        # a memory slice, when the mask fits it (else the mask stays: an
        # AssertionError only, python lets the others through)
        lea rdi, [rsp + SO_ERR]
        call err_catch
        test eax, eax
        jz 22f
        cmp eax, E_ASSERT
        je 23f
        mov edi, eax
        mov rsi, [r15 + CTX_ERR_MSG]
        call err_throw
22:     mov rdi, [rsp]
        mov rsi, [rsp + SO_SIZE]
        mov rdx, [rsp + SO_OFFSET]
        call apply_mask_to_range
        mov rsi, rax
        LOADS rdi, MEM
        call mk2
        mov [rsp + SO_VALUE], rax
        call err_end
        jmp 24f
23:     mov rdi, [rsp + SO_VALUE]
        mov rsi, [rsp + SO_SIZE]
        mov rdx, [rsp + SO_OFFSET]
        mov rcx, [rsp + SO_SHL]
        mov r8d, 1
        call alg_mask_op
        mov [rsp + SO_VALUE], rax
24:     mov rdi, [rsp + SO_SIZE]
        mov rsi, [rsp + SO_STOR_OFFSET]
        mov rdx, [rsp + SO_VALUE]
        call mk_row
.Lso_push:
        mov rdi, [rsp + SO_ROWS]
        mov rsi, rax
        call vec_push
        jmp .Lso_term
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
        # sort by offsets (an exception, CannotCompare above all: the whole
        # value as one piece)
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
        mov qword ptr [rsp + SO_IDX], 0
15:     mov rcx, [rsp + SO_IDX]
        mov rax, [rsp + SO_ROWS]
        cmp rcx, [rax + VEC_LEN]
        jae 18f
        mov rax, [rax + VEC_DATA]
        mov r13, [rax + rcx*8]          # r
        mov rdi, [r13 + N_DATA + 8]
        call is_int
        test eax, eax
        jz .Lso_whole
        mov rdi, [r13 + N_DATA]
        call is_int
        test eax, eax
        jz .Lso_whole
        mov rdi, [r13 + N_DATA + 8]
        mov rsi, r12
        call int_cmp
        cmp eax, 0
        jl .Lso_whole                   # the parts overlap: their bits are or-ed
        je 16f
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
16:     mov r14, [r13 + N_DATA]         # size
        # a mask wider than the value in it, up to the next part: e.g. a
        # bool shifted left, Mask(32, 0, bool) << 224, next to what's
        # above its byte
        mov rcx, [rsp + SO_IDX]
        inc rcx
        mov rax, [rsp + SO_ROWS]
        cmp rcx, [rax + VEC_LEN]
        jae 17f
        mov rax, [rax + VEC_DATA]
        mov rax, [rax + rcx*8]
        mov rdi, [rax + N_DATA + 8]
        mov [rsp + SO_VALUE], rdi
        call is_int
        test eax, eax
        jz 17f
        mov rdi, [rsp + SO_VALUE]
        mov rsi, [r13 + N_DATA + 8]
        call int_sub
        mov [rsp + SO_VALUE], rax       # room
        mov rdi, rax
        mov rsi, r14
        call int_cmp
        test eax, eax
        jns 17f
        mov rdi, [r13 + N_DATA + 16]
        call value_bits
        mov rdi, rax
        mov rsi, [rsp + SO_VALUE]
        call int_cmp
        cmp eax, 0
        jg 17f
        mov r14, [rsp + SO_VALUE]
17:     mov rdi, r14
        mov rsi, [r13 + N_DATA + 8]
        mov rdx, [r13 + N_DATA + 16]
        call mk_row
        mov rdi, rbx
        mov rsi, rax
        call vec_push
        mov rdi, [r13 + N_DATA + 8]
        mov rsi, r14
        call int_add
        mov r12, rax                    # pos = offset + size
        inc qword ptr [rsp + SO_IDX]
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
.Lso_unsortable:
        mov edi, eax                    # (python's timeout isn't an Exception)
        call err_rethrow_timeout
.Lso_whole:
        mov rdi, [rsp + SO_ORIG]
        call full_row
.Lso_done:
        add rsp, MATCH_BINDINGS_SIZE + 128
        LEAVE
.Lso_assert:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_split]
        call err_throw
.Lso_index:
        call throw_index
.Lso_unpack:
        call throw_unpack
ENDF split_or

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

# int_is_ones(v) -> eax: the int v is 2^k - 1 for its bit length k (all
# of its bits set; 0 too, not a negative one)
FUNC int_is_ones
        test dil, 1
        jz 1f
        mov rax, rdi
        sar rax, 1
        js 9f
        lea rcx, [rax + 1]
        test rax, rcx
        jnz 9f
        mov eax, 1
        ret
9:      xor eax, eax
        ret
1:      ENTER
        mov rbx, rdi
        call int_sign
        test eax, eax
        js 8f
        lea rdi, [rbx + N_DATA]
        call __gmpz_popcount@PLT
        mov r12, rax
        lea rdi, [rbx + N_DATA]
        mov esi, 2
        call __gmpz_sizeinbase@PLT
        cmp rax, r12
        sete al
        movzx eax, al
        LEAVE
8:      xor eax, eax
        LEAVE
ENDF int_is_ones

# is_mem_tuple(exp) -> eax / is_storage4(exp) -> eax: the predicates of
# find_f_list (walk_collect): a ('mem', ...), a ('storage', size, off, idx)
FUNC is_mem_tuple
        push rbx
        call opcode_of
        cmp eax, OP_MEM
        sete al
        movzx eax, al
        pop rbx
        ret
ENDF is_mem_tuple

FUNC is_storage4
        push rbx
        mov rbx, rdi
        call opcode_of
        cmp eax, OP_STORAGE
        jne 1f
        cmp dword ptr [rbx + N_AUX], 4
        jne 1f
        mov eax, 1
        pop rbx
        ret
1:      xor eax, eax
        pop rbx
        ret
ENDF is_storage4

# in_order(writes, reads_written) -> rax: the parts a write of a whole
# word was split in (a vec) - all written at once, with values of what
# was there before - as a list, one after the other, in an order where
# none reads what one before it wrote: as they are, unless one reads what
# one before it writes (then that one goes first). NIL (python's None)
# when there's no such order: two that read what the other writes, a swap.
# reads_written(a, b) -> eax: whether the value a writes may read what b
# writes; asked of every pair, in python's order.
FUNC in_order
        ENTER
        sub rsp, 48
        .set IO_FN, 0
        .set IO_RW, 8                   # n * n bytes: i reads what j writes
        .set IO_WAIT, 16                # n qwords: how many are to go before
        .set IO_DONE, 24                # n bytes
        .set IO_RES, 32
        .set IO_J, 40
        mov rbx, rdi
        mov [rsp + IO_FN], rsi
        mov r12, [rbx + VEC_LEN]        # n
        mov rdi, r12
        imul rdi, r12
        add rdi, 16
        call arena_alloc
        mov [rsp + IO_RW], rax
        lea rdi, [r12*8 + 16]
        call arena_alloc
        mov [rsp + IO_WAIT], rax
        lea rdi, [r12 + 16]
        call arena_alloc
        mov [rsp + IO_DONE], rax
        # after[i]: the j's that i reads what they write
        xor r13d, r13d                  # i
1:      cmp r13, r12
        jae 4f
        mov qword ptr [rsp + IO_J], 0
2:      mov r14, [rsp + IO_J]
        cmp r14, r12
        jae 3f
        inc qword ptr [rsp + IO_J]
        cmp r14, r13
        je 2b
        mov rax, [rbx + VEC_DATA]
        mov rdi, [rax + r13*8]
        mov rsi, [rax + r14*8]
        call [rsp + IO_FN]
        test eax, eax
        jz 2b
        mov rax, r13
        imul rax, r12
        add rax, [rsp + IO_RW]
        mov byte ptr [rax + r14], 1
        mov rax, [rsp + IO_WAIT]
        inc qword ptr [rax + r14*8]
        jmp 2b
3:      inc r13
        jmp 1b
4:      call vec_new
        mov [rsp + IO_RES], rax
5:      mov rax, [rsp + IO_RES]
        cmp [rax + VEC_LEN], r12
        jae 9f
        # the first ready
        xor r13d, r13d
6:      cmp r13, r12
        jae .Lio_none
        mov rax, [rsp + IO_DONE]
        cmp byte ptr [rax + r13], 0
        jne 7f
        mov rax, [rsp + IO_WAIT]
        cmp qword ptr [rax + r13*8], 0
        je 8f
7:      inc r13
        jmp 6b
8:      mov rax, [rsp + IO_DONE]
        mov byte ptr [rax + r13], 1
        mov rax, [rbx + VEC_DATA]
        mov rsi, [rax + r13*8]
        mov rdi, [rsp + IO_RES]
        call vec_push
        mov rax, r13
        imul rax, r12
        add rax, [rsp + IO_RW]
        mov rcx, [rsp + IO_WAIT]
        xor edx, edx
10:     cmp rdx, r12
        jae 5b
        cmp byte ptr [rax + rdx], 0
        je 11f
        dec qword ptr [rcx + rdx*8]
11:     inc rdx
        jmp 10b
9:      mov rdi, [rsp + IO_RES]
        call vec_to_list
        add rsp, 48
        LEAVE
.Lio_none:
        xor eax, eax
        add rsp, 48
        LEAVE
ENDF in_order

# setmem_reads_written(a, b) -> eax: whether the value of the setmem a may
# read memory the setmem b writes
FUNC setmem_reads_written
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov rdi, [rbx + N_DATA + 16]
        LOADS rsi, MSIZE
        call contains
        test eax, eax
        jnz 8f
        call vec_new
        mov r13, rax
        mov rdi, [rbx + N_DATA + 16]
        lea rsi, [rip + is_mem_tuple]
        mov rdx, r13
        call walk_collect
        xor r14d, r14d
1:      cmp r14, [r13 + VEC_LEN]
        jae 9f
        mov rax, [r13 + VEC_DATA]
        mov rax, [rax + r14*8]          # m
        inc r14
        cmp dword ptr [rax + N_AUX], 2
        jb .Lsrw_index
        mov rdi, [rax + N_DATA + 8]
        mov [rsp], rdi
        call opcode_of
        cmp eax, OP_RANGE
        jne 8f
        mov rdi, [rsp]
        mov rsi, [r12 + N_DATA + 8]
        call range_overlaps
        cmp eax, TRI_FALSE
        jne 8f
        jmp 1b
8:      mov eax, 1
        add rsp, 16
        LEAVE
9:      xor eax, eax
        add rsp, 16
        LEAVE
.Lsrw_index:
        call throw_index
ENDF setmem_reads_written

# store_reads_written(a, b) -> eax: whether the value of the store a may
# read bits the store b writes: of its slot, or of one that may be it
FUNC store_reads_written
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi                    # ('store', size, off, idx, _)
        call vec_new
        mov r13, rax
        mov rdi, [rbx + N_DATA + 32]
        lea rsi, [rip + is_storage4]
        mov rdx, r13
        call walk_collect
        xor r14d, r14d
1:      cmp r14, [r13 + VEC_LEN]
        jae 9f
        mov rax, [r13 + VEC_DATA]
        mov rax, [rax + r14*8]          # ('storage', r_size, r_off, r_idx)
        inc r14
        mov [rsp], rax
        mov rdi, [rax + N_DATA + 24]
        mov rsi, [r12 + N_DATA + 24]
        call alg_sub_op
        mov [rsp + 8], rax              # diff
        mov rdi, rax
        call is_int
        test eax, eax
        jz 2f
        mov rdi, [rsp + 8]              # another slot
        mov esi, 256
        call int_mod_2exp
        cmp rax, 1
        jne 1b
2:      mov rax, [rsp]
        mov rdi, [rax + N_DATA + 8]
        call is_int
        test eax, eax
        jz 8f
        mov rax, [rsp]
        mov rdi, [rax + N_DATA + 16]
        call is_int
        test eax, eax
        jz 8f
        mov rdi, [r12 + N_DATA + 8]
        call is_int
        test eax, eax
        jz 8f
        mov rdi, [r12 + N_DATA + 16]
        call is_int
        test eax, eax
        jz 8f
        # r_off < off + size and off < r_off + r_size - of a field moved
        # left (r_off < 0, see algebra.apply_mask_to_storage), the bits
        # from 0
        mov rax, [rsp]
        mov rdi, [rax + N_DATA + 16]
        mov esi, 1
        call int_max
        mov [rsp + 8], rax              # r_off
        mov rdi, [r12 + N_DATA + 16]
        mov rsi, [r12 + N_DATA + 8]
        call int_add
        mov rsi, rax
        mov rdi, [rsp + 8]
        call int_cmp
        test eax, eax
        jns 1b
        mov rax, [rsp]
        mov rdi, [rsp + 8]
        mov rsi, [rax + N_DATA + 8]
        call int_add
        mov rsi, rax
        mov rdi, [r12 + N_DATA + 16]
        call int_cmp
        test eax, eax
        jns 1b
8:      mov eax, 1
        add rsp, 16
        LEAVE
9:      xor eax, eax
        add rsp, 16
        LEAVE
ENDF store_reads_written

# split_setmem(line, arg, out): a setmem of ORed parts, as one setmem per
# part (written all at once: see in_order), when they are whole bytes
FUNC split_setmem
        ENTER
        sub rsp, ERR_SIZEOF + 32
        .set SS_OUT, ERR_SIZEOF
        .set SS_ROWS, ERR_SIZEOF + 8
        .set SS_RES, ERR_SIZEOF + 16
        .set SS_I, ERR_SIZEOF + 24
        mov rbx, rdi
        mov [rsp + SS_OUT], rdx
        call opcode_of
        cmp eax, OP_SETMEM
        jne .Lss_asis
        cmp dword ptr [rbx + N_AUX], 3
        jne .Lss_unpack
        mov rdi, [rbx + N_DATA + 16]
        call opcode_of
        cmp eax, OP_OR
        jne .Lss_asis
        mov rdi, [rbx + N_DATA + 16]
        call split_or
        mov [rsp + SS_ROWS], rax
        call vec_new
        mov [rsp + SS_RES], rax
        mov qword ptr [rsp + SS_I], 0
1:      mov rcx, [rsp + SS_I]
        mov rax, [rsp + SS_ROWS]
        cmp ecx, [rax + N_AUX]
        jae 3f
        mov r12, [rax + N_DATA + rcx*8] # (size, offset, split_val)
        inc qword ptr [rsp + SS_I]
        # parts of bytes: memory is written byte by byte
        mov rdi, [r12 + N_DATA]
        call divisible_bytes
        test eax, eax
        jz .Lss_asis
        mov rdi, [r12 + N_DATA + 8]
        call divisible_bytes
        test eax, eax
        jz .Lss_asis
        lea rdi, [rsp]
        call err_catch
        test eax, eax
        jnz .Lss_problem
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, [r12 + N_DATA]
        mov rdx, [r12 + N_DATA + 8]
        call apply_mask_to_range
        mov r13, rax
        call err_end
        mov rdx, [r12 + N_DATA + 16]
        mov rsi, r13
        LOADS rdi, SETMEM
        call mk3
        mov rdi, [rsp + SS_RES]
        mov rsi, rax
        call vec_push
        jmp 1b
3:      mov rdi, [rsp + SS_RES]
        lea rsi, [rip + setmem_reads_written]
        call in_order
        test rax, rax
        jz .Lss_asis
        mov rdi, [rsp + SS_OUT]
        mov rsi, rax
        call vec_extend_seq
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
        mov rdi, [rsp + SS_OUT]
        mov rsi, rbx
        call vec_push
        add rsp, ERR_SIZEOF + 32
        LEAVE
.Lss_unpack:
        call throw_unpack
ENDF split_setmem

# times_byte(exp) -> rax: x, rdx: k when exp is x * 256^k - a mul of one
# ('exp', 256, k) and one other factor (and 1s) -, rax NIL otherwise
FUNC times_byte
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 16
        mov rbx, rdi
        call opcode_of
        cmp eax, OP_MUL
        jne .Ltb_none
        # the powers: exactly one
        xor r12d, r12d                  # the power
        xor r13d, r13d                  # how many
        mov r14d, 1
1:      cmp r14d, [rbx + N_AUX]
        jae 2f
        mov rdi, [rbx + N_DATA + r14*8]
        inc r14d
        PAT rsi, "('exp', 256, 'Any')"
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 1b
        inc r13d
        mov r12, [rbx + N_DATA + r14*8 - 8]
        jmp 1b
2:      cmp r13d, 1
        jne .Ltb_none
        # the others: neither the power nor 1
        xor r13d, r13d
        mov r14d, 1
3:      cmp r14d, [rbx + N_AUX]
        jae 4f
        mov rdi, [rbx + N_DATA + r14*8]
        inc r14d
        cmp rdi, r12
        je 3b
        mov [rsp + MATCH_BINDINGS_SIZE + 8], rdi
        mov esi, 3
        call py_equal
        test eax, eax
        jnz 3b
        inc r13d
        cmp r13d, 1
        jne 3b
        mov rax, [rsp + MATCH_BINDINGS_SIZE + 8]
        mov [rsp + MATCH_BINDINGS_SIZE], rax
        jmp 3b
4:      cmp r13d, 1
        jne .Ltb_none
        mov rax, [rsp + MATCH_BINDINGS_SIZE]
        mov rdx, [r12 + N_DATA + 16]
        add rsp, MATCH_BINDINGS_SIZE + 16
        LEAVE
.Ltb_none:
        xor eax, eax
        xor edx, edx
        add rsp, MATCH_BINDINGS_SIZE + 16
        LEAVE
ENDF times_byte

# byte_field_store(line) -> rax: the store of a field at a byte computed
# at runtime - an element of a packed array - as the compiler writes it,
# the whole slot:
#     stor[idx] = v * 256^k or not(mask * 256^k) and stor[idx]
# is the field of the bits of mask at the byte k set to v:
# ('store', size, 8 * k, idx, v). NIL if the line isn't that.
FUNC byte_field_store
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 96
        .set BF_IDX, MATCH_BINDINGS_SIZE
        .set BF_A, MATCH_BINDINGS_SIZE + 8
        .set BF_B, MATCH_BINDINGS_SIZE + 16
        .set BF_PUT, MATCH_BINDINGS_SIZE + 24
        .set BF_KEEP, MATCH_BINDINGS_SIZE + 32
        .set BF_X, MATCH_BINDINGS_SIZE + 40
        .set BF_Y, MATCH_BINDINGS_SIZE + 48
        .set BF_STOR, MATCH_BINDINGS_SIZE + 56
        .set BF_MX, MATCH_BINDINGS_SIZE + 64   # mask = (mx, mk)
        .set BF_MK, MATCH_BINDINGS_SIZE + 72
        .set BF_VX, MATCH_BINDINGS_SIZE + 80   # val = (vx, vk)
        .set BF_VK, MATCH_BINDINGS_SIZE + 88
        PATXD "('store', 256, 0, ':idx', ('or', ':a', ':b'))"
        test eax, eax
        jz .Lbf_none
        mov rax, [rsp]
        mov [rsp + BF_IDX], rax
        mov rax, [rsp + 8]
        mov [rsp + BF_A], rax
        mov rax, [rsp + 16]
        mov [rsp + BF_B], rax
        mov rcx, [rsp + BF_IDX]
        LOADS rdi, STORAGE
        mov esi, (256 << 1) | 1
        mov edx, 1
        call mk4
        mov [rsp + BF_STOR], rax
        xor r12d, r12d                  # (put, keep): (a, b), then (b, a)
.Lbf_outer:
        cmp r12d, 2
        jae .Lbf_none
        mov rax, [rsp + BF_A]
        mov rcx, [rsp + BF_B]
        test r12d, r12d
        jz 1f
        xchg rax, rcx
1:      mov [rsp + BF_PUT], rax
        mov [rsp + BF_KEEP], rcx
        inc r12d
        PAT rsi, "('and', ':x', ':y')"
        mov rdi, [rsp + BF_KEEP]
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz .Lbf_outer
        mov rax, [rsp]
        mov [rsp + BF_X], rax
        mov rax, [rsp + 8]
        mov [rsp + BF_Y], rax
        xor r13d, r13d                  # (cleared, stor): (x, y), then (y, x)
.Lbf_inner:
        cmp r13d, 2
        jae .Lbf_outer
        mov rbx, [rsp + BF_X]           # cleared
        mov rax, [rsp + BF_Y]           # stor
        test r13d, r13d
        jz 2f
        xchg rbx, rax
2:      inc r13d
        cmp rax, [rsp + BF_STOR]
        jne .Lbf_inner
        mov rdi, rbx
        call opcode_of
        cmp eax, OP_NOT
        jne .Lbf_inner
        cmp dword ptr [rbx + N_AUX], 2
        jb .Lbf_index
        mov rdi, [rbx + N_DATA + 8]
        call times_byte
        mov [rsp + BF_MX], rax
        mov [rsp + BF_MK], rdx
        mov rdi, [rsp + BF_PUT]
        call times_byte
        mov [rsp + BF_VX], rax
        mov [rsp + BF_VK], rdx
        cmp qword ptr [rsp + BF_MX], 0
        je .Lbf_inner
        cmp qword ptr [rsp + BF_VX], 0
        je .Lbf_inner
        mov rdi, [rsp + BF_MK]
        mov rsi, [rsp + BF_VK]
        call py_equal
        test eax, eax
        jz .Lbf_inner
        mov rdi, [rsp + BF_MX]
        call is_int
        test eax, eax
        jz .Lbf_inner
        mov rdi, [rsp + BF_MX]
        call int_bit_length
        mov r14, rax
        TAG r14                         # size
        mov rdi, [rsp + BF_MX]          # mask == 2^size - 1
        call int_is_ones
        test eax, eax
        jz .Lbf_inner
        mov rdi, [rsp + BF_VX]
        call value_bits
        mov rdi, rax
        mov rsi, r14
        call int_cmp
        cmp eax, 0
        jg .Lbf_inner
        mov rdi, [rsp + BF_VK]
        xor esi, esi
        xor edx, edx
        call value_range
        mov rbx, rdx                    # hi
        mov rdi, rax
        call int_sign
        test eax, eax
        js .Lbf_inner
        # (256^k is 0 for a k of 32 or more: then nothing changes, not a
        # field past the slot)
        mov edi, (8 << 1) | 1
        mov rsi, rbx
        call int_mul
        mov rdi, rax
        mov rsi, r14
        call int_add
        mov rdi, rax
        mov esi, (256 << 1) | 1
        call int_cmp
        cmp eax, 0
        jg .Lbf_inner
        mov edi, (8 << 1) | 1
        mov rsi, [rsp + BF_VK]
        call alg_mul2
        mov rdx, rax
        mov rsi, r14
        mov rcx, [rsp + BF_IDX]
        mov r8, [rsp + BF_VX]
        LOADS rdi, STORE
        call mk5
        add rsp, MATCH_BINDINGS_SIZE + 96
        LEAVE
.Lbf_none:
        xor eax, eax
        add rsp, MATCH_BINDINGS_SIZE + 96
        LEAVE
.Lbf_index:
        call throw_index
ENDF byte_field_store

# merge_zeros(stores) -> vec: a value that fits in its part with the 0
# bits after it, up to a whole byte: one store of both - a bool of the
# bits 224-231 rather than the bit 224 and 0 in the 7 bits above it
FUNC merge_zeros
        ENTER
        sub rsp, 32
        mov rbx, rdi                    # the stores (a vec)
        call vec_new
        mov r12, rax                    # res
        xor r13d, r13d
1:      cmp r13, [rbx + VEC_LEN]
        jae 9f
        mov rax, [rbx + VEC_DATA]
        mov r14, [rax + r13*8]          # store
        inc r13
        mov rax, [r12 + VEC_LEN]
        test rax, rax
        jz 8f
        mov rcx, [r12 + VEC_DATA]
        mov rax, [rcx + rax*8 - 8]
        mov [rsp], rax                  # res[-1]: ('store', int size, int off, idx, val)?
        mov rdi, rax
        mov esi, OP_STORE
        mov edx, 5
        call is_op_n
        test eax, eax
        jz 8f
        mov rax, [rsp]
        mov rdi, [rax + N_DATA + 8]
        call is_int
        test eax, eax
        jz 8f
        mov rax, [rsp]
        mov rdi, [rax + N_DATA + 16]
        call is_int
        test eax, eax
        jz 8f
        mov rdi, [r14 + N_DATA + 32]    # store[4] == 0
        mov esi, 1
        call py_equal
        test eax, eax
        jz 8f
        mov rax, [rsp]                  # store[2] == off + size
        mov rdi, [rax + N_DATA + 16]
        mov rsi, [rax + N_DATA + 8]
        call int_add
        mov rdi, [r14 + N_DATA + 16]
        mov rsi, rax
        call py_equal
        test eax, eax
        jz 8f
        mov rax, [rsp]                  # size % 8
        mov rdi, [rax + N_DATA + 8]
        mov esi, (8 << 1) | 1
        call int_mod
        cmp rax, 1
        je 8f
        mov [rsp + 8], rax
        mov rax, [rsp]                  # value_bits(val) <= size
        mov rdi, [rax + N_DATA + 32]
        call value_bits
        mov rdi, rax
        mov rax, [rsp]
        mov rsi, [rax + N_DATA + 8]
        call int_cmp
        cmp eax, 0
        jg 8f
        # grow = min(store[1], 8 - size % 8)
        mov edi, (8 << 1) | 1
        mov rsi, [rsp + 8]
        call int_sub
        mov rsi, rax
        mov rdi, [r14 + N_DATA + 8]
        call int_min
        mov [rsp + 8], rax
        # res[-1] = ('store', size + grow, off, idx, val)
        mov rax, [rsp]
        mov rdi, [rax + N_DATA + 8]
        mov rsi, [rsp + 8]
        call int_add
        mov rsi, rax
        mov rax, [rsp]
        mov rdx, [rax + N_DATA + 16]
        mov rcx, [rax + N_DATA + 24]
        mov r8, [rax + N_DATA + 32]
        LOADS rdi, STORE
        call mk5
        mov rcx, [r12 + VEC_DATA]
        mov rdx, [r12 + VEC_LEN]
        mov [rcx + rdx*8 - 8], rax
        # grow < store[1]: the rest of the zeroes
        mov rdi, [rsp + 8]
        mov rsi, [r14 + N_DATA + 8]
        call int_cmp
        test eax, eax
        jns 1b
        mov rdi, [r14 + N_DATA + 8]
        mov rsi, [rsp + 8]
        call int_sub
        mov [rsp + 16], rax
        mov rdi, [r14 + N_DATA + 16]
        mov rsi, [rsp + 8]
        call int_add
        mov rdx, rax
        mov rsi, [rsp + 16]
        mov rax, [rsp]
        mov rcx, [rax + N_DATA + 24]
        mov r8d, 1
        LOADS rdi, STORE
        call mk5
        mov rdi, r12
        mov rsi, rax
        call vec_push
        jmp 1b
8:      mov rdi, r12
        mov rsi, r14
        call vec_push
        jmp 1b
9:      mov rax, r12
        add rsp, 32
        LEAVE
ENDF merge_zeros

# split_store(line, arg, out): a store of a whole slot made of parts, as
# one store per part (written all at once: see in_order)
FUNC split_store
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 64
        .set ST_OUT, MATCH_BINDINGS_SIZE
        .set ST_IDX, MATCH_BINDINGS_SIZE + 8
        .set ST_ROWS, MATCH_BINDINGS_SIZE + 16
        .set ST_RES, MATCH_BINDINGS_SIZE + 24
        .set ST_POS, MATCH_BINDINGS_SIZE + 32
        .set ST_SAME, MATCH_BINDINGS_SIZE + 40
        .set ST_VALUES, MATCH_BINDINGS_SIZE + 48
        .set ST_LINE, MATCH_BINDINGS_SIZE + 56
        mov rbx, rdi
        mov [rsp + ST_LINE], rdi
        mov [rsp + ST_OUT], rdx
        call byte_field_store
        test rax, rax
        jz 1f
        mov rdi, [rsp + ST_OUT]
        mov rsi, rax
        call vec_push
        jmp .Lst_done
1:      mov rdi, rbx
        PATXD "('store', 256, 0, ':int:idx', ('mask_shl', ':int:size', ':int:off', 0, ('storage', 256, 0, ':idx')))"
        test eax, eax
        jz 2f
        mov rdi, [rsp + 8]              # size < 256
        mov esi, (256 << 1) | 1
        call int_cmp
        test eax, eax
        jns 2f
        # a store of the storage itself, masked: the bits outside the mask
        # set to 0. idx [rsp], size [rsp + 8], off [rsp + 16]
        mov rdi, [rsp + 16]
        call int_sign
        test eax, eax
        jle 11f
        mov rsi, [rsp + 16]
        mov rcx, [rsp]
        LOADS rdi, STORE
        mov edx, 1
        mov r8d, 1
        call mk5
        mov rdi, [rsp + ST_OUT]
        mov rsi, rax
        call vec_push
11:     mov rdi, [rsp + 8]
        mov rsi, [rsp + 16]
        call int_add
        mov r12, rax                    # size + off
        mov rdi, rax
        mov esi, (256 << 1) | 1
        call int_cmp
        test eax, eax
        jns .Lst_done
        mov edi, (256 << 1) | 1
        mov rsi, r12
        call int_sub
        mov rsi, rax
        mov rdx, r12
        mov rcx, [rsp]
        LOADS rdi, STORE
        mov r8d, 1
        call mk5
        mov rdi, [rsp + ST_OUT]
        mov rsi, rax
        call vec_push
        jmp .Lst_done
2:      mov rdi, rbx
        PATXD "('store', 256, 0, ':idx', ':val')"
        test eax, eax
        jz .Lst_asis
        mov rax, [rsp]
        mov [rsp + ST_IDX], rax
        mov rdi, [rsp + 8]
        call split_or
        mov r12, rax
        # where the parts are isn't known: nor what the rest of the word
        # is set to
        xor r13d, r13d
3:      cmp r13d, [r12 + N_AUX]
        jae 4f
        mov rax, [r12 + N_DATA + r13*8]
        inc r13d
        mov rdi, [rax + N_DATA]
        call is_int
        test eax, eax
        jz .Lst_asis
        mov rax, [r12 + N_DATA + r13*8 - 8]
        mov rdi, [rax + N_DATA + 8]
        call is_int
        test eax, eax
        jz .Lst_asis
        jmp 3b
4:      # the parts of a size, sorted by offset (stable: an insertion sort)
        call vec_new
        mov [rsp + ST_ROWS], rax
        xor r13d, r13d
5:      cmp r13d, [r12 + N_AUX]
        jae 7f
        mov r14, [r12 + N_DATA + r13*8]
        inc r13d
        mov rdi, [r14 + N_DATA]
        call int_sign
        test eax, eax
        jle 5b
        mov rdi, [rsp + ST_ROWS]
        mov rsi, r14
        call vec_push
        mov rax, [rsp + ST_ROWS]        # sift it down
        mov rbx, [rax + VEC_DATA]
        mov r14, [rax + VEC_LEN]
        dec r14
6:      test r14, r14
        jz 5b
        mov rax, [rbx + r14*8 - 8]
        mov rdi, [rax + N_DATA + 8]
        mov rax, [rbx + r14*8]
        mov rsi, [rax + N_DATA + 8]
        call int_cmp
        cmp eax, 0
        jle 5b
        mov rax, [rbx + r14*8 - 8]
        mov rcx, [rbx + r14*8]
        mov [rbx + r14*8 - 8], rcx
        mov [rbx + r14*8], rax
        dec r14
        jmp 6b
7:      mov rbx, [rsp + ST_ROWS]
        # parts over each other (or out of the word): that's an or of
        # them, not stores of one then the other
        mov r12d, 1                     # pos
        xor r13d, r13d
8:      cmp r13, [rbx + VEC_LEN]
        jae 9f
        mov rax, [rbx + VEC_DATA]
        mov r14, [rax + r13*8]
        inc r13
        mov rdi, [r14 + N_DATA + 8]
        mov rsi, r12
        call int_cmp
        test eax, eax
        js .Lst_unusual
        mov rdi, [r14 + N_DATA + 8]
        mov rsi, [r14 + N_DATA]
        call int_add
        mov r12, rax
        mov rdi, rax
        mov esi, (256 << 1) | 1
        call int_cmp
        cmp eax, 0
        jg .Lst_unusual
        jmp 8b
9:      # the parts that write the same to the same storage, the values
        mov qword ptr [rsp + ST_SAME], 0
        mov qword ptr [rsp + ST_VALUES], 0
        xor r13d, r13d
10:     cmp r13, [rbx + VEC_LEN]
        jae 12f
        mov rax, [rbx + VEC_DATA]
        mov r14, [rax + r13*8]
        inc r13
        mov rsi, [r14 + N_DATA]
        mov rdx, [r14 + N_DATA + 8]
        mov rcx, [rsp + ST_IDX]
        LOADS rdi, STORAGE
        call mk4
        cmp rax, [r14 + N_DATA + 16]
        jne 11f
        inc qword ptr [rsp + ST_SAME]
        jmp 10b
11:     mov rdi, [r14 + N_DATA + 16]
        mov esi, 1
        call py_equal
        test eax, eax
        jnz 10b
        inc qword ptr [rsp + ST_VALUES]
        jmp 10b
12:     # one value: the word it makes, rather than it at its bits and
        # zeroes around them (but a store that keeps some bits of the slot
        # is one of the others)
        cmp qword ptr [rsp + ST_SAME], 0
        jne 13f
        cmp qword ptr [rsp + ST_VALUES], 2
        jb .Lst_asis_line
13:     # the word is written whole: the bits of no part are set to 0
        call vec_new
        mov [rsp + ST_RES], rax
        mov qword ptr [rsp + ST_POS], 1
        xor r13d, r13d
14:     cmp r13, [rbx + VEC_LEN]
        jae 17f
        mov rax, [rbx + VEC_DATA]
        mov r14, [rax + r13*8]          # (s_size, s_off, s_val)
        inc r13
        mov rdi, [r14 + N_DATA + 8]
        mov rsi, [rsp + ST_POS]
        call int_cmp
        cmp eax, 0
        jle 15f
        mov rdi, [r14 + N_DATA + 8]
        mov rsi, [rsp + ST_POS]
        call int_sub
        mov rsi, rax
        mov rdx, [rsp + ST_POS]
        mov rcx, [rsp + ST_IDX]
        mov r8d, 1
        LOADS rdi, STORE
        call mk5
        mov rdi, [rsp + ST_RES]
        mov rsi, rax
        call vec_push
15:     # (writing the same to the same storage: nothing)
        mov rsi, [r14 + N_DATA]
        mov rdx, [r14 + N_DATA + 8]
        mov rcx, [rsp + ST_IDX]
        LOADS rdi, STORAGE
        call mk4
        cmp rax, [r14 + N_DATA + 16]
        je 16f
        mov rsi, [r14 + N_DATA]
        mov rdx, [r14 + N_DATA + 8]
        mov rcx, [rsp + ST_IDX]
        mov r8, [r14 + N_DATA + 16]
        LOADS rdi, STORE
        call mk5
        mov rdi, [rsp + ST_RES]
        mov rsi, rax
        call vec_push
16:     mov rdi, [r14 + N_DATA + 8]
        mov rsi, [r14 + N_DATA]
        call int_add
        mov [rsp + ST_POS], rax
        jmp 14b
17:     mov rdi, [rsp + ST_POS]
        mov esi, (256 << 1) | 1
        call int_cmp
        test eax, eax
        jns 18f
        mov edi, (256 << 1) | 1
        mov rsi, [rsp + ST_POS]
        call int_sub
        mov rsi, rax
        mov rdx, [rsp + ST_POS]
        mov rcx, [rsp + ST_IDX]
        mov r8d, 1
        LOADS rdi, STORE
        call mk5
        mov rdi, [rsp + ST_RES]
        mov rsi, rax
        call vec_push
18:     mov rdi, [rsp + ST_RES]
        call merge_zeros
        mov rdi, rax
        lea rsi, [rip + store_reads_written]
        call in_order
        test rax, rax
        jz .Lst_asis_line
        mov rdi, [rsp + ST_OUT]
        mov rsi, rax
        call vec_extend_seq
        jmp .Lst_done
.Lst_unusual:
        mov edi, LOG_WARNING
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_unusual_store]
        call log_fmt
.Lst_asis_line:
.Lst_asis:
        mov rdi, [rsp + ST_OUT]
        mov rsi, [rsp + ST_LINE]
        call vec_push
.Lst_done:
        add rsp, MATCH_BINDINGS_SIZE + 64
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
        call unpack_range
        mov rdi, r12
        call unpack_range
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, [rbx + N_DATA + 16]
        call alg_add2
        mov [rsp + MO_M_RIGHT], rax
        mov rdi, [r12 + N_DATA + 8]
        mov rsi, [r12 + N_DATA + 16]
        call alg_add2
        mov [rsp + MO_S_RIGHT], rax
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, [rsp + MO_M_RIGHT]
        mov rdx, [r12 + N_DATA + 8]
        mov rcx, [rsp + MO_S_RIGHT]
        call mem_words4
        test eax, eax
        jz .Lmo_whole
        # no overlap when the split is after or before the memory
        mov rdi, [rsp + MO_M_RIGHT]
        mov rsi, [r12 + N_DATA + 8]
        call mem_safe_le_op
        cmp eax, TRI_TRUE
        je .Lmo_whole
        mov rdi, [rsp + MO_S_RIGHT]
        mov rsi, [rbx + N_DATA + 8]
        call mem_safe_le_op
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
        call mem_safe_ge_zero
        mov r13d, eax
        mov rdi, [rsp + MO_RIGHT_LEN]
        call mem_safe_ge_zero
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

# slice_exp(exp, left, right, width) -> value or NIL: python's slice_exp -
# the bytes left to right of exp, `width` bits wide (the width of the
# memory it's in; NIL: sizeof)
FUNC slice_exp
        STACK_CHECK
        ENTER
        sub rsp, 64
        .set SL_SIZE, 0
        .set SL_WIDTH, 8
        .set SL_RES, 16                 # the data's pieces
        .set SL_POS, 24
        .set SL_I, 32
        .set SL_PSIZE, 40
        .set SL_SIZES, 48
        mov rbx, rdi
        mov r12, rsi                    # left
        mov r13, rdx                    # right
        mov [rsp + SL_WIDTH], rcx
        mov rdi, rdx
        mov rsi, r12
        call alg_sub_op
        mov [rsp + SL_SIZE], rax        # size = right - left
        # bytes, as the number they make (see with_width)
        mov rdi, rbx
        call opcode_of
        cmp eax, OP_BYTES
        jne 1f
        cmp dword ptr [rbx + N_AUX], 3
        jb 1f
        mov rdi, [rbx + N_DATA + 16]
        call sized
        test eax, eax
        jz 1f
        cmp qword ptr [rsp + SL_WIDTH], 0
        jne 11f
        mov rdi, [rbx + N_DATA + 8]
        call alg_bits
        mov [rsp + SL_WIDTH], rax
11:     mov rbx, [rbx + N_DATA + 16]
1:      # bytes in memory of another width: the number they make there
        mov rdi, rbx
        call sized
        test eax, eax
        jz 2f
        mov rdi, rbx
        call opcode_of
        cmp eax, OP_BYTES
        je 2f
        mov rdi, [rsp + SL_WIDTH]
        call is_int
        test eax, eax
        jz 2f
        mov rdi, rbx
        call width_of
        mov r14, rax                    # w
        test rax, rax
        jz 12f                          # (None != width)
        mov rdi, rax
        mov rsi, [rsp + SL_WIDTH]
        call py_equal
        test eax, eax
        jnz 2f
12:     mov rdi, r14
        call is_int
        test eax, eax
        jz .Lsl_none
        mov rdi, [rsp + SL_WIDTH]
        mov esi, 3
        call int_mod_2exp
        cmp rax, 1
        jne .Lsl_none
        mov rdi, [rsp + SL_WIDTH]
        mov esi, (8 << 1) | 1
        call int_floordiv
        mov rdi, rbx
        mov rsi, rax
        call resize_bytes
        test rax, rax
        jz .Lsl_none
        mov rbx, rax
2:      # ('mem', ('range', rleft, rlen))
        mov rdi, rbx
        mov esi, OP_MEM
        mov edx, 2
        call is_op_n
        test eax, eax
        jz 3f
        mov rdi, [rbx + N_DATA + 8]
        mov esi, OP_RANGE
        mov edx, 3
        call is_op_n
        test eax, eax
        jz 3f
        mov r14, [rbx + N_DATA + 8]
        mov rdi, r12
        mov rsi, [rsp + SL_SIZE]
        call alg_add2
        mov rdi, rax
        mov rsi, [r14 + N_DATA + 16]
        call mem_safe_le_op
        cmp eax, TRI_TRUE
        jne .Lsl_none
        mov rdi, [r14 + N_DATA + 8]
        mov rsi, r12
        call alg_add2
        mov rdi, rax
        mov rsi, [rsp + SL_SIZE]
        call mk_mem_range
        jmp .Lsl_done
3:      # (op, rleft, rlen), op an array
        mov rdi, rbx
        call is_tuple
        test eax, eax
        jz 4f
        cmp dword ptr [rbx + N_AUX], 3
        jne 4f
        mov rdi, [rbx + N_DATA]
        call str_id
        mov edi, eax
        call is_array_op
        test eax, eax
        jz 4f
        mov rdi, r12
        mov rsi, [rsp + SL_SIZE]
        call alg_add2
        mov rdi, rax
        mov rsi, [rbx + N_DATA + 16]
        call mem_safe_le_op
        cmp eax, TRI_TRUE
        jne .Lsl_none
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, r12
        call alg_add2
        mov rsi, rax
        mov rdi, [rbx + N_DATA]
        mov rdx, [rsp + SL_SIZE]
        call mk3
        jmp .Lsl_done
4:      # ('extcodecopy', addr, ('range', rleft, rlen))
        mov rdi, rbx
        mov esi, OP_EXTCODECOPY
        mov edx, 3
        call is_op_n
        test eax, eax
        jz 5f
        mov rdi, [rbx + N_DATA + 16]
        mov esi, OP_RANGE
        mov edx, 3
        call is_op_n
        test eax, eax
        jz 5f
        mov r14, [rbx + N_DATA + 16]
        mov rdi, r12
        mov rsi, [rsp + SL_SIZE]
        call alg_add2
        mov rdi, rax
        mov rsi, [r14 + N_DATA + 16]
        call mem_safe_le_op
        cmp eax, TRI_TRUE
        jne .Lsl_none
        mov rdi, [r14 + N_DATA + 8]
        mov rsi, r12
        call alg_add2
        mov rdi, rax
        mov rsi, [rsp + SL_SIZE]
        call mk_range
        LOADS rdi, EXTCODECOPY
        mov rsi, [rbx + N_DATA + 8]
        mov rdx, rax
        call mk3
        jmp .Lsl_done
5:      # a data, numbers left < right: the parts of it between them (a mask
        # of it would be a mask of a value of more than a word)
        mov rdi, rbx
        call opcode_of
        cmp eax, OP_DATA
        jne .Lsl_bytes
        mov rdi, r12
        call is_int
        test eax, eax
        jz .Lsl_bytes
        mov rdi, r13
        call is_int
        test eax, eax
        jz .Lsl_bytes
        mov rdi, r12
        mov rsi, r13
        call int_cmp
        test eax, eax
        jns .Lsl_bytes
        # the sizes of its parts (sizeof may assert), all whole bytes
        call vec_new
        mov [rsp + SL_SIZES], rax
        mov qword ptr [rsp + SL_I], 1
51:     mov rax, [rsp + SL_I]
        cmp eax, [rbx + N_AUX]
        jae 52f
        mov rdi, [rbx + N_DATA + rax*8]
        inc qword ptr [rsp + SL_I]
        call sizeof
        mov rdi, [rsp + SL_SIZES]
        mov rsi, rax
        call vec_push
        jmp 51b
52:     mov qword ptr [rsp + SL_I], 0
        mov qword ptr [rsp + SL_POS], 1         # (their sum, a value)
53:     mov rax, [rsp + SL_SIZES]
        mov rcx, [rsp + SL_I]
        cmp rcx, [rax + VEC_LEN]
        jae 54f
        mov rax, [rax + VEC_DATA]
        mov r14, [rax + rcx*8]
        inc qword ptr [rsp + SL_I]
        mov rdi, r14
        call is_int
        test eax, eax
        jz .Lsl_bytes
        mov rdi, r14
        mov esi, 3
        call int_mod_2exp
        cmp rax, 1
        jne .Lsl_bytes
        mov rdi, [rsp + SL_POS]
        mov rsi, r14
        call int_add
        mov [rsp + SL_POS], rax
        jmp 53b
54:     cmp qword ptr [rsp + SL_WIDTH], 0      # width is None or the sum
        je 55f
        mov rdi, [rsp + SL_WIDTH]
        mov rsi, [rsp + SL_POS]
        call py_equal
        test eax, eax
        jz .Lsl_bytes
55:     call vec_new
        mov [rsp + SL_RES], rax
        mov qword ptr [rsp + SL_POS], 1         # pos, in bytes
        mov qword ptr [rsp + SL_I], 0
56:     mov rax, [rsp + SL_SIZES]
        mov rcx, [rsp + SL_I]
        cmp rcx, [rax + VEC_LEN]
        jae 59f
        mov rax, [rax + VEC_DATA]
        mov rdi, [rax + rcx*8]
        mov esi, (8 << 1) | 1
        call int_floordiv
        mov [rsp + SL_PSIZE], rax       # part_size, in bytes
        # lo, hi = max(left, pos), min(right, pos + part_size)
        mov rdi, [rsp + SL_POS]
        mov rsi, rax
        call int_add
        mov r14, rax                    # pos + part_size
        mov rdi, r12
        mov rsi, [rsp + SL_POS]
        call int_max
        push rax                        # lo
        push rax
        mov rdi, r13
        mov rsi, r14
        call int_min
        mov rdx, rax                    # hi
        pop rax
        pop rax
        mov [rsp + SL_PSIZE], rdx       # (hi; part_size is r14 - pos)
        mov rdi, rax
        mov rsi, rdx
        push rax
        push rax
        call int_cmp
        pop rcx                         # lo
        pop rcx
        test eax, eax
        jns 58f                         # lo >= hi: none of it
        mov rax, [rsp + SL_I]
        mov rdx, [rbx + N_DATA + 8 + rax*8]     # the part
        cmp rcx, [rsp + SL_POS]
        jne 57f
        cmp r14, [rsp + SL_PSIZE]
        jne 57f
        mov rax, rdx                    # all of it: the part
        jmp 571f
57:     # slice_exp(part, lo - pos, hi - pos)
        push rdx
        push rcx
        mov rdi, rcx
        mov rsi, [rsp + 16 + SL_POS]
        call int_sub
        mov [rsp], rax                  # lo - pos
        mov rdi, [rsp + 16 + SL_PSIZE]
        mov rsi, [rsp + 16 + SL_POS]
        call int_sub
        mov rdx, rax
        pop rsi
        pop rdi
        xor ecx, ecx
        call slice_exp
        test rax, rax
        jz .Lsl_none
571:    mov rdi, [rsp + SL_RES]
        mov rsi, rax
        call vec_push
58:     mov [rsp + SL_POS], r14         # pos += part_size
        inc qword ptr [rsp + SL_I]
        jmp 56b
59:     # right <= pos: the pieces (one: itself)
        mov rdi, r13
        mov rsi, [rsp + SL_POS]
        call int_cmp
        cmp eax, 0
        jg .Lsl_bytes
        mov rax, [rsp + SL_RES]
        cmp qword ptr [rax + VEC_LEN], 1
        jne 591f
        mov rax, [rax + VEC_DATA]
        mov rax, [rax]
        jmp .Lsl_done
591:    mov rdi, rax
        LOADS rsi, DATA
        call vec_prepend
        mov rdi, [rsp + SL_RES]
        call vec_to_tuple
        jmp .Lsl_done
.Lsl_bytes:
        # bytes: the number they make, of the width of the bytes
        mov rdi, rbx
        call opcode_of
        cmp eax, OP_BYTES
        jne 6f
        cmp dword ptr [rbx + N_AUX], 3
        jb 6f
        cmp qword ptr [rsp + SL_WIDTH], 0
        jne 61f
        mov rdi, [rbx + N_DATA + 8]
        call alg_bits
        mov [rsp + SL_WIDTH], rax
61:     mov rbx, [rbx + N_DATA + 16]
6:      # bytes of more than a word (or of a width not known) cut where it's
        # not known: not a number, to take bits of
        mov rdi, rbx
        call sized
        test eax, eax
        jz 7f
        mov rdi, rbx
        call opcode_of
        cmp eax, OP_BYTES
        je 7f
        mov rdi, rbx
        call width_of
        mov r14, rax
        test rax, rax
        jz .Lsl_none
        mov rdi, rax
        call is_int
        test eax, eax
        jz .Lsl_none
        mov rdi, r14
        mov esi, (256 << 1) | 1
        call int_cmp
        cmp eax, 0
        jg .Lsl_none
7:      cmp qword ptr [rsp + SL_WIDTH], 0
        jne 8f
        mov rdi, rbx
        call sizeof
        mov [rsp + SL_WIDTH], rax
8:      # a mask: 8 * size bits, at width - 8 * right
        mov rdi, r13
        call alg_bits
        mov rdi, [rsp + SL_WIDTH]
        mov rsi, rax
        call alg_sub_op
        mov r14, rax                    # off
        mov rdi, [rsp + SL_SIZE]
        call alg_bits
        mov rsi, rax
        mov rdi, rbx
        mov rdx, r14
        mov ecx, 1
        mov r8, r14
        call alg_mask_op
        mov rdi, rax
        mov rsi, [rsp + SL_SIZE]
        call with_width
        jmp .Lsl_done
.Lsl_none:
        xor eax, eax
.Lsl_done:
        add rsp, 64
        LEAVE
ENDF slice_exp


# splits_mem(memloc, split, memval, split_val) -> list of (range, value):
# the memory values we can be confident of after the split part of the
# memory is overwritten (split_val = NIL when not known)
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
        .set SM_RIGHT_LEN, 128
        mov [rsp + SM_MEMVAL], rdx
        mov [rsp + SM_SPLIT_VAL], rcx
        mov rbx, rdi
        mov r12, rsi
        call unpack_range
        mov rdi, r12
        call unpack_range
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
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, [rsp + SM_M_RIGHT]
        mov rdx, [r12 + N_DATA + 8]
        mov rcx, [rsp + SM_S_RIGHT]
        call mem_words4
        test eax, eax
        jz .Lsm_unsure
        # a split of unknown sign is of undefined length
        mov rdi, [rsp + SM_S_LEN]
        call mem_safe_ge_zero
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
        call mem_safe_le_op
        cmp eax, TRI_TRUE
        je .Lsm_untouched
        mov rdi, [rsp + SM_S_RIGHT]
        mov rsi, [rbx + N_DATA + 8]
        call mem_safe_le_op
        cmp eax, TRI_TRUE
        je .Lsm_untouched
        mov rdi, [r12 + N_DATA + 8]
        mov rsi, [rbx + N_DATA + 8]
        call mem_max_op
        mov [rsp + SM_LEFT], rax        # (NIL for python's None)
        mov rdi, [rsp + SM_S_RIGHT]
        mov rsi, [rsp + SM_M_RIGHT]
        call mem_min_op
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
        call mem_safe_le_op
        cmp eax, TRI_TRUE
        jne .Lsm_unsure
        cmp qword ptr [rsp + SM_LEFT], 0
        je .Lsm_unsure
        # (a split ending before the memory can't begin inside it)
        mov rdi, [rsp + SM_RIGHT]
        call none_if_nil
        mov rdi, rax
        mov rsi, [rbx + N_DATA + 8]
        call mem_safe_le_op
        cmp eax, TRI_TRUE
        jne 2f
        cmp qword ptr [rsp + SM_IN_LEFT], 1
        jne .Lsm_assert
2:      # the untouched values on each side, of the memory's width
        mov rdi, [rbx + N_DATA + 16]
        call alg_bits
        mov rcx, rax
        mov rdi, [rsp + SM_MEMVAL]
        mov esi, 1
        mov rdx, [rsp + SM_IN_LEFT]
        call slice_exp
        mov [rsp + SM_VAL_LEFT], rax
        mov qword ptr [rsp + SM_VAL_RIGHT], 0
        cmp qword ptr [rsp + SM_RIGHT], 0
        je 3f
        mov rdi, [rsp + SM_M_RIGHT]
        mov rsi, [rbx + N_DATA + 8]
        call alg_sub_op
        mov r13, rax
        mov rdi, [rbx + N_DATA + 16]
        call alg_bits
        mov rcx, rax
        mov rdi, [rsp + SM_MEMVAL]
        mov rsi, [rsp + SM_IN_RIGHT]
        mov rdx, r13
        call slice_exp
        mov [rsp + SM_VAL_RIGHT], rax
3:      call vec_new
        mov [rsp + SM_RES], rax
        mov r13, [rsp + SM_IN_LEFT]     # left_len (left - m_left: in_left)
        mov rdi, [rsp + SM_RIGHT]
        call none_if_nil
        mov rsi, rax
        mov rdi, [rsp + SM_M_RIGHT]
        call alg_sub_op
        mov [rsp + SM_RIGHT_LEN], rax
        mov rdi, r13
        call mem_safe_ge_zero
        cmp eax, TRI_TRUE
        jne 4f
        cmp r13, 1
        je 4f
        cmp qword ptr [rsp + SM_VAL_LEFT], 0
        je 4f
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, r13
        call mk_range
        mov rdi, rax
        mov rsi, [rsp + SM_VAL_LEFT]
        call mk2
        mov rdi, [rsp + SM_RES]
        mov rsi, rax
        call vec_push
4:      cmp qword ptr [rsp + SM_SPLIT_VAL], 0
        je 7f
        # the part of the split value inside the memory location
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, [r12 + N_DATA + 8]
        call mem_max_op
        mov rdi, rax
        call none_if_nil
        mov [rsp + SM_CLEFT], rax
        mov rdi, [rsp + SM_M_RIGHT]
        mov rsi, [rsp + SM_S_RIGHT]
        call mem_min_op
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
        jz 5f
        # mem[a len b] = calldata[x len b]; log mem[c len d] ->
        # calldata[x + c - a, center_len]
        mov rax, [rsp + SM_SPLIT_VAL]
        cmp dword ptr [rax + N_AUX], 3
        jne .Lsm_unpack
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
        jmp 6f
5:      # its bytes there, of the split_val the split's s_len bytes are
        mov rdi, [rsp + SM_CLEFT]
        mov rsi, [r12 + N_DATA + 8]
        call alg_sub_op
        mov r13, rax
        mov rdi, [rsp + SM_CRIGHT]
        mov rsi, [r12 + N_DATA + 8]
        call alg_sub_op
        mov r14, rax
        mov rdi, [rsp + SM_S_LEN]
        call alg_bits
        mov rcx, rax
        mov rdi, [rsp + SM_SPLIT_VAL]
        mov rsi, r13
        mov rdx, r14
        call slice_exp
        mov [rsp + SM_CVAL], rax
6:      mov rdi, [rsp + SM_CLEN]
        call mem_safe_ge_zero
        cmp eax, TRI_TRUE
        jne 7f
        cmp qword ptr [rsp + SM_CLEN], 1
        je 7f
        cmp qword ptr [rsp + SM_CVAL], 0
        je 7f
        mov rdi, [rsp + SM_CLEFT]
        mov rsi, [rsp + SM_CLEN]
        call mk_range
        mov rdi, rax
        mov rsi, [rsp + SM_CVAL]
        call mk2
        mov rdi, [rsp + SM_RES]
        mov rsi, rax
        call vec_push
7:      mov r14, [rsp + SM_RIGHT_LEN]
        mov rdi, r14
        call mem_safe_ge_zero
        cmp eax, TRI_TRUE
        jne 8f
        cmp r14, 1
        je 8f
        cmp qword ptr [rsp + SM_VAL_RIGHT], 0
        je 8f
        # (the split ends in the memory, not before it: then all of it is
        # left, not a part from the split's end on)
        mov rdi, [rsp + SM_RIGHT]
        call none_if_nil
        mov rsi, rax
        mov rdi, [rbx + N_DATA + 8]
        call mem_safe_le_op
        cmp eax, TRI_TRUE
        jne 8f
        mov rdi, [rsp + SM_RIGHT]
        mov rsi, r14
        call mk_range
        mov rdi, rax
        mov rsi, [rsp + SM_VAL_RIGHT]
        call mk2
        mov rdi, [rsp + SM_RES]
        mov rsi, rax
        call vec_push
8:      mov rdi, [rsp + SM_RES]
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
        lea rsi, [rip + .Ls_assert_inleft]
        call err_throw
.Lsm_unpack:
        call throw_unpack
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

# fill_mem(exp, split, split_val) -> value: the memory read `exp` with the
# part the split overwrote filled in - the data of the memory before the
# split, the split's part, and the memory after it; exp as it is when
# where they are isn't known
FUNC fill_mem
        ENTER
        sub rsp, 112
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
        .set FM_RES, 80
        .set FM_MEMLOC_MAX, 88
        .set FM_TMP, 96
        mov [rsp + FM_EXP], rdi
        mov [rsp + FM_SPLIT], rsi
        mov [rsp + FM_SPLIT_VAL], rdx
        mov rbx, rdi
        mov r12, rsi
        mov rdi, rbx
        call opcode_of
        cmp eax, OP_MEM
        jne .Lfm_assert
        cmp dword ptr [rbx + N_AUX], 2
        jne .Lfm_assert
        mov r13, [rbx + N_DATA + 8]     # memloc
        mov [rsp + FM_MEMLOC], r13
        cmp r13, r12                    # exp == ('mem', split): the value,
        jne 1f                          # as wide as the split
        mov rdi, r12
        call is_seq
        test eax, eax
        jz .Lfm_index
        cmp dword ptr [r12 + N_AUX], 3
        jb .Lfm_index
        mov rdi, [rsp + FM_SPLIT_VAL]
        mov rsi, [r12 + N_DATA + 16]
        call with_width
        jmp .Lfm_done
1:      mov rdi, r13
        call unpack_range
        mov rdi, r12
        call unpack_range
        mov rdi, [r13 + N_DATA + 8]
        mov rsi, [r13 + N_DATA + 16]
        call alg_add2
        mov [rsp + FM_M_RIGHT], rax
        mov rdi, [r12 + N_DATA + 8]
        mov rsi, [r12 + N_DATA + 16]
        call alg_add2
        mov [rsp + FM_S_RIGHT], rax
        # all of it was written: that part of the value (maybe none of it,
        # for a length that may be 0 - the padding of an array to whole
        # words). A read of a negative length, its end before its start,
        # isn't in anything.
        mov rdi, [r13 + N_DATA + 16]
        call mem_safe_ge_zero
        cmp eax, TRI_FALSE
        je 2f
        mov rdi, r12
        mov rsi, r13
        call range_contains
        cmp eax, TRI_TRUE
        jne 2f
        mov rdi, [r13 + N_DATA + 8]
        mov rsi, [r12 + N_DATA + 8]
        call alg_sub_op
        mov r14, rax
        mov rdi, [rsp + FM_M_RIGHT]
        mov rsi, [r12 + N_DATA + 8]
        call alg_sub_op
        mov [rsp + FM_TMP], rax
        mov rdi, [r12 + N_DATA + 16]
        call alg_bits
        mov rcx, rax
        mov rdi, [rsp + FM_SPLIT_VAL]
        mov rsi, r14
        mov rdx, [rsp + FM_TMP]
        call slice_exp
        test rax, rax
        jnz .Lfm_done
2:      # the split may be all after the memory read, or all before it (or
        # it's not known): not replacing. Else the read is the memory before
        # the split, the split's part, and the memory after it - each of a
        # size >= 0, maybe 0 (a read of a length that may be 0)
        mov rdi, [r13 + N_DATA + 8]
        mov rsi, [rsp + FM_M_RIGHT]
        mov rdx, [r12 + N_DATA + 8]
        mov rcx, [rsp + FM_S_RIGHT]
        call mem_words4
        test eax, eax
        jz .Lfm_asis
        mov rdi, [r12 + N_DATA + 16]
        call mem_safe_ge_zero
        cmp eax, TRI_TRUE
        jne .Lfm_asis
        mov rdi, [r13 + N_DATA + 16]
        call mem_safe_ge_zero
        cmp eax, TRI_TRUE
        jne .Lfm_asis
        mov rdi, [r12 + N_DATA + 8]
        mov rsi, [rsp + FM_M_RIGHT]
        call mem_safe_le_op
        cmp eax, TRI_TRUE
        jne .Lfm_asis
        mov rdi, [r13 + N_DATA + 8]
        mov rsi, [rsp + FM_S_RIGHT]
        call mem_safe_le_op
        cmp eax, TRI_TRUE
        jne .Lfm_asis
        mov rdi, [r12 + N_DATA + 8]
        mov rsi, [r13 + N_DATA + 8]
        call mem_max_op
        mov [rsp + FM_LEFT], rax
        mov rdi, [rsp + FM_S_RIGHT]
        mov rsi, [rsp + FM_M_RIGHT]
        call mem_min_op
        mov [rsp + FM_RIGHT], rax
        # if we can't figure out which one is smaller/larger, we're not
        # replacing
        cmp qword ptr [rsp + FM_LEFT], 0
        je .Lfm_asis
        test rax, rax
        jz .Lfm_asis
        # the read has none of it
        mov rdi, rax
        mov rsi, [rsp + FM_LEFT]
        call mem_safe_le_op
        cmp eax, TRI_TRUE
        je .Lfm_asis
        # 'max' tends to mess up with all the algebra: a variable stands
        # for it for the time being (never, of a range)
        mov rdi, r13
        call replace_max_with_MAX
        mov [rsp + FM_MEMLOC_MAX], rdx
        mov rdi, r12
        call replace_max_with_MAX
        cmp rdx, [rsp + FM_MEMLOC_MAX]
        je 3f
        mov edi, LOG_WARNING
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_different_maxes]
        call log_fmt
        jmp .Lfm_asis
3:      # (before_split, split_val, after_split)
        mov rdi, [rsp + FM_LEFT]
        mov rsi, [r13 + N_DATA + 8]
        call alg_sub_op
        mov rdi, rbx
        mov esi, 1
        mov rdx, rax
        xor ecx, ecx                    # (width: sizeof)
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
        xor ecx, ecx                    # (width: sizeof)
        call slice_exp
        mov [rsp + FM_RES_RIGHT], rax
        test rax, rax
        jz .Lfm_asis
        call vec_new
        mov [rsp + FM_RES], rax
        mov rdi, [rsp + FM_RES_LEFT]
        call sizeof
        mov r14, rax
        mov rdi, rax
        call mem_safe_ge_zero
        cmp eax, TRI_TRUE
        jne .Lfm_asis
        cmp r14, 1
        je 4f
        mov rdi, [rsp + FM_RES]
        mov rsi, [rsp + FM_RES_LEFT]
        call vec_push
4:      # the inserted value, cut to the overlap
        mov rdi, [rsp + FM_LEFT]
        mov rsi, [r12 + N_DATA + 8]
        call alg_sub_op
        mov r14, rax
        mov rdi, [rsp + FM_RIGHT]
        mov rsi, [r12 + N_DATA + 8]
        call alg_sub_op
        mov [rsp + FM_TMP], rax
        mov rdi, [r12 + N_DATA + 16]
        call alg_bits
        mov rcx, rax
        mov rdi, [rsp + FM_SPLIT_VAL]
        mov rsi, r14
        mov rdx, [rsp + FM_TMP]
        call slice_exp
        test rax, rax
        jz .Lfm_asis
        mov r14, rax
        mov rdi, rax
        call sizeof
        mov rdi, rax
        call mem_safe_ge_zero
        cmp eax, TRI_TRUE
        jne .Lfm_asis                   # (that the part of the split that's read is there)
        mov rdi, [rsp + FM_RES]
        mov rsi, r14
        call vec_push
        mov rdi, [rsp + FM_RES_RIGHT]
        call sizeof
        mov r14, rax
        mov rdi, rax
        call mem_safe_ge_zero
        cmp eax, TRI_TRUE
        jne .Lfm_asis
        cmp r14, 1
        je 5f
        mov rdi, [rsp + FM_RES]
        mov rsi, [rsp + FM_RES_RIGHT]
        call vec_push
5:      mov rdi, [rsp + FM_RES]
        LOADS rsi, DATA
        call vec_prepend
        mov rdi, [rsp + FM_RES]
        call vec_to_tuple
        jmp .Lfm_done
.Lfm_asis:
        mov rax, [rsp + FM_EXP]
.Lfm_done:
        add rsp, 112
        LEAVE
.Lfm_assert:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_range]
        call err_throw
.Lfm_index:
        call throw_index
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
        call unpack_range
        mov rdi, r12
        call unpack_range
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
        mov rdi, [rsp]
        mov rsi, [rsp + 16]
        mov rdx, [rsp + 8]
        mov rcx, [rsp + 24]
        call mem_words4
        test eax, eax
        jz .Lro_none
        mov rdi, [rsp + 8]
        mov rsi, [rsp]
        call mem_lt_op
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
        call mem_le_op
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
        call unpack_range
        mov rdi, r12
        call unpack_range
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, [rbx + N_DATA + 16]
        call alg_add2
        mov [rsp], rax                  # outer_end
        mov rdi, [r12 + N_DATA + 8]
        mov rsi, [r12 + N_DATA + 16]
        call alg_add2
        mov [rsp + 8], rax              # inner_end
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, [rsp]
        mov rdx, [r12 + N_DATA + 8]
        mov rcx, [rsp + 8]
        call mem_words4
        test eax, eax
        jz .Lrc_none
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, [r12 + N_DATA + 8]
        call mem_le_op
        cmp eax, TRI_CANNOT
        je .Lrc_none
        cmp eax, TRI_TRUE
        jne .Lrc_false
        mov rdi, [rsp + 8]
        mov rsi, [rsp]
        call mem_le_op
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
