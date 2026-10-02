# The width of what's in memory, and what's known of the bits of a value
# (port of core/memloc.py's sizeof, sized, width_of, implicit, keep_width,
# keep_widths, keep_setmem_width, resize_bytes, with_width, and of
# value_bits, max_value_bits, max_value, low_zero_bits, words).
#
# A value written to memory is as wide as the memory it's written to - the
# 32 bytes of an mstore, the 1 byte of an mstore8... - and as a part of a
# ('data', ...), what's read back is as wide as sizeof says: the top bit of
# a mask, 256 bits for a word. They differ for a narrow value written to a
# word (an address: sizeof is 160 bits), a number that isn't a word (the 4
# bytes of a selector), zeroes...
#
# ('bytes', size, exp) is exp, as `size` bytes: the lowest ones of its
# value. The memory model gives it to what it reads back when the width
# of the value isn't the width of the memory it's in. As a number, it's
# the value of exp.

.include "defs.inc"

        .text

# mem_words(exp) -> eax: python's memloc.words of one expression - exp, a
# memory address, doesn't wrap around 2^256: the integer it's compared as
# is the word it is (see memory_range)
FUNC mem_words
        STACK_CHECK
        ENTER
        mov rbx, rdi
        call is_int
        test eax, eax
        jz 1f
        mov rax, rbx
        mov rdx, rbx
        jmp 2f
1:      mov rdi, rbx
        call memory_range
2:      mov rdi, rax
        mov rsi, rdx
        call vr_is_word
        LEAVE
ENDF mem_words

# mask_ints(exp, out) -> eax: exp is ('mask_shl', int size, int off, int
# shl, x) - the matcher's ":int:", a bool too: out[0..2] := their values,
# out[3] := x
FUNC mask_ints
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov esi, OP_MASK_SHL
        mov edx, 5
        call is_op_n
        test eax, eax
        jz 9f
        xor r13d, r13d
1:      cmp r13d, 3
        jae 2f
        mov rdi, [rbx + N_DATA + 8 + r13*8]
        call vr_number
        test rax, rax
        jz 9f
        mov [r12 + r13*8], rax
        inc r13d
        jmp 1b
2:      mov rax, [rbx + N_DATA + 32]
        mov [r12 + 24], rax
        mov eax, 1
        LEAVE
9:      xor eax, eax
        LEAVE
ENDF mask_ints

# storage_ints(exp, out) -> eax: exp is ('storage', int size, int off >= 0,
# loc): out[0..1] := size, off
FUNC storage_ints
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov esi, OP_STORAGE
        mov edx, 4
        call is_op_n
        test eax, eax
        jz 9f
        mov rdi, [rbx + N_DATA + 8]
        call vr_number
        test rax, rax
        jz 9f
        mov [r12], rax
        mov rdi, [rbx + N_DATA + 16]
        call vr_number
        test rax, rax
        jz 9f
        mov [r12 + 8], rax
        mov rdi, rax
        call int_sign
        test eax, eax
        js 9f
        mov eax, 1
        LEAVE
9:      xor eax, eax
        LEAVE
ENDF storage_ints

# mask_top_bits(off, size, shl, xbits) -> rax: what value_bits and
# max_value_bits say of a mask whose x has xbits: top = min(off + size,
# xbits), 0 when it's at or below off, else max(0, min(top + shl, 256))
FUNC mask_top_bits
        ENTER
        mov rbx, rdi                    # off
        mov r12, rdx                    # shl
        mov r13, rcx                    # xbits
        call int_add                    # off + size
        mov rdi, rax
        mov rsi, r13
        call int_min
        mov r13, rax                    # top
        mov rdi, rax
        mov rsi, rbx
        call int_cmp
        cmp eax, 0
        jg 1f
        mov eax, 1                      # 0
        LEAVE
1:      mov rdi, r13
        mov rsi, r12
        call int_add
        mov rdi, rax
        mov esi, (256 << 1) | 1
        call int_min
        mov rdi, rax
        mov esi, 1
        call int_max
        LEAVE
ENDF mask_top_bits

# value_bits(exp) -> rax: python's value_bits - how many of the lowest bits
# of exp may not be 0, as far as it's known
FUNC value_bits
        STACK_CHECK
        ENTER
        sub rsp, 32
        mov rbx, rdi
        call is_int
        test eax, eax
        jz 1f
        mov rdi, rbx
        call int_sign
        test eax, eax
        js 9f                           # (below 0: as a word, any bit)
        mov rdi, rbx
        call int_bit_length
        TAG rax
        jmp .Lvb_ret
1:      mov rdi, rbx
        call opcode_of
        mov edi, eax
        call is_bool_op                 # a truth value
        test eax, eax
        jz 2f
        mov eax, 3
        jmp .Lvb_ret
2:      mov rdi, rbx
        mov rsi, rsp
        call mask_ints
        test eax, eax
        jz 3f
        mov rdi, [rsp + 24]
        call value_bits
        mov rcx, rax
        mov rdi, [rsp + 8]              # off
        mov rsi, [rsp]                  # size
        mov rdx, [rsp + 16]             # shl
        call mask_top_bits
        jmp .Lvb_ret
3:      mov rdi, rbx
        mov rsi, rsp
        call storage_ints
        test eax, eax
        jz 9f
        mov rax, [rsp]                  # its size
        jmp .Lvb_ret
9:      mov eax, (256 << 1) | 1
.Lvb_ret:
        add rsp, 32
        LEAVE
ENDF value_bits

# max_value_bits(exp, bounds) -> rax: python's max_value_bits - an upper
# bound of the bit length of exp. Numbers well below 2^256 add up like
# integers do. bounds: 0, or an emap {exp: bits} of what's known of some
# of what exp is made of (a variable that holds a size, say).
FUNC max_value_bits
        STACK_CHECK
        ENTER
        sub rsp, 48
        mov rbx, rdi
        mov r12, rsi
        test r12, r12
        jz 1f
        test bl, 1
        jnz 1f
        test rbx, rbx
        jz 1f
        mov eax, [rbx + N_KIND]
        cmp eax, K_TUPLE
        je 11f
        cmp eax, K_STR
        jne 1f
11:     mov rdi, r12
        mov rsi, rbx
        call emap_get
        test rax, rax
        jnz .Lmvb_ret
1:      mov rdi, rbx
        call is_int
        test eax, eax
        jz 2f
        mov rdi, rbx                    # 0 <= exp < 2^256: its bits, else 256
        call int_sign
        test eax, eax
        js 9f
        mov rdi, rbx
        call int_bit_length
        cmp rax, 256
        ja 9f
        TAG rax
        jmp .Lmvb_ret
2:      mov rdi, rbx
        call is_str
        test eax, eax
        jz 3f
        mov eax, [rbx + N_AUX]          # BOUNDED_SYMBOLS: 64 bits
        and eax, STR_ID_MASK
        mov edi, eax
        call is_bounded_symbol
        test eax, eax
        jz 9f
        mov eax, (64 << 1) | 1
        jmp .Lmvb_ret
3:      mov rdi, rbx
        call opcode_of
        mov r13d, eax
        mov ecx, [rbx + N_AUX]
        cmp r13d, OP_ADD
        je .Lmvb_add
        cmp r13d, OP_MUL
        je .Lmvb_mul
        cmp r13d, OP_DIV
        je .Lmvb_div
        cmp r13d, OP_MOD
        je .Lmvb_mod
        cmp r13d, OP_AND
        je .Lmvb_min
        cmp r13d, OP_MIN
        je .Lmvb_min
        cmp r13d, OP_OR
        je .Lmvb_max
        cmp r13d, OP_XOR
        je .Lmvb_max
.Lmvb_mask:
        mov rdi, rbx
        mov rsi, rsp
        call mask_ints
        test eax, eax
        jz 8f
        mov rdi, [rsp + 24]
        mov rsi, r12
        call max_value_bits
        mov rcx, rax
        mov rdi, [rsp + 8]
        mov rsi, [rsp]
        mov rdx, [rsp + 16]
        call mask_top_bits
        jmp .Lmvb_ret
8:      mov rdi, rbx
        call value_bits
        jmp .Lmvb_ret
9:      mov eax, (256 << 1) | 1
.Lmvb_ret:
        add rsp, 48
        LEAVE

.Lmvb_add:
        # the most bits of its terms, and one more for each doubling of
        # their number: min(256, top + (n - 1).bit_length())
        cmp ecx, 1
        jbe .Lmvb_mask
        mov qword ptr [rsp + 32], 0
        mov r14d, 1
1:      cmp r14d, [rbx + N_AUX]
        jae 2f
        mov rdi, [rbx + N_DATA + r14*8]
        inc r14d
        mov rsi, r12
        call max_value_bits
        cmp qword ptr [rsp + 32], 0
        je 3f
        mov rdi, [rsp + 32]
        mov rsi, rax
        call int_max
3:      mov [rsp + 32], rax
        jmp 1b
2:      mov eax, [rbx + N_AUX]
        sub eax, 2                      # n - 1
        xor ecx, ecx
        bsr ecx, eax
        jz 4f
        inc ecx
        jmp 5f
4:      xor ecx, ecx
5:      lea rsi, [rcx + rcx + 1]
        mov rdi, [rsp + 32]
        call int_add
        mov rdi, rax
        mov esi, (256 << 1) | 1
        call int_min
        jmp .Lmvb_ret

.Lmvb_mul:
        # min(256, the sum of their bits)
        cmp ecx, 1
        jbe .Lmvb_mask
        mov qword ptr [rsp + 32], 1
        mov r14d, 1
1:      cmp r14d, [rbx + N_AUX]
        jae 2f
        mov rdi, [rbx + N_DATA + r14*8]
        inc r14d
        mov rsi, r12
        call max_value_bits
        mov rdi, [rsp + 32]
        mov rsi, rax
        call int_add
        mov [rsp + 32], rax
        jmp 1b
2:      mov rdi, [rsp + 32]
        mov esi, (256 << 1) | 1
        call int_min
        jmp .Lmvb_ret

.Lmvb_div:
        cmp ecx, 3
        jne .Lmvb_mask
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, r12
        call max_value_bits
        jmp .Lmvb_ret

.Lmvb_mod:
        cmp ecx, 3
        jne .Lmvb_mask
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, r12
        call max_value_bits
        mov [rsp + 32], rax
        mov rdi, [rbx + N_DATA + 16]
        mov rsi, r12
        call max_value_bits
        mov rdi, [rsp + 32]
        mov rsi, rax
        call int_min
        jmp .Lmvb_ret

.Lmvb_min:
        mov r14d, 0                     # (an and, a min: the fewest)
        jmp 6f
.Lmvb_max:
        mov r14d, 1                     # (an or, a xor: the most)
6:      cmp ecx, 1
        jbe .Lmvb_mask
        mov [rsp + 40], r14
        mov qword ptr [rsp + 32], 0
        mov r14d, 1
1:      cmp r14d, [rbx + N_AUX]
        jae 2f
        mov rdi, [rbx + N_DATA + r14*8]
        inc r14d
        mov rsi, r12
        call max_value_bits
        cmp qword ptr [rsp + 32], 0
        je 3f
        mov rdi, [rsp + 32]
        mov rsi, rax
        cmp qword ptr [rsp + 40], 0
        jne 4f
        call int_min
        jmp 3f
4:      call int_max
3:      mov [rsp + 32], rax
        jmp 1b
2:      mov rax, [rsp + 32]
        jmp .Lmvb_ret
ENDF max_value_bits

# max_value(exp) -> rax: python's max_value - an upper bound of the value
# of exp, as an unsigned word
FUNC max_value
        STACK_CHECK
        ENTER
        sub rsp, 48
        mov rbx, rdi
        call vr_number                  # an int, a bool: itself, as a word
        test rax, rax
        jz 1f
        mov rdi, rax
        mov esi, 256
        call int_mod_2exp
        jmp .Lmv_ret
1:      mov rdi, rbx
        call opcode_of
        mov r12d, eax
        mov edi, eax
        call is_bool_op
        test eax, eax
        jz 2f
        mov eax, 3                      # a truth value: 1
        jmp .Lmv_ret
2:      cmp r12d, OP_MOD
        je .Lmv_mod
        cmp r12d, OP_DIV
        je .Lmv_div
        cmp r12d, OP_AND
        je .Lmv_and
.Lmv_mask:
        mov rdi, rbx
        mov rsi, rsp
        call mask_ints
        test eax, eax
        jz .Lmv_storage
        mov rdi, [rsp]                  # size <= 0: 0
        call int_sign
        cmp eax, 0
        jg 3f
        mov eax, 1
        jmp .Lmv_ret
3:      mov rdi, [rsp + 8]              # off < 0: any word
        call int_sign
        test eax, eax
        js .Lmv_top
        # x & mask is at most x, and at most the mask
        mov rdi, [rsp]
        call clamp_bits
        mov rdi, rax
        call pow2
        mov rdi, rax
        mov esi, 3
        call int_sub
        mov r13, rax                    # 2^size - 1
        mov rdi, [rsp + 8]
        call clamp_bits
        mov rdi, r13
        mov rsi, rax
        call int_shl_bits
        mov r13, rax                    # the mask
        mov rdi, [rsp + 24]
        call max_value
        mov rdi, rax
        mov rsi, r13
        call int_min
        mov r13, rax                    # its bits
        mov rdi, [rsp + 16]
        call int_sign
        test eax, eax
        js 4f
        mov rdi, [rsp + 16]
        call clamp_bits
        mov rdi, r13
        mov rsi, rax
        call int_shl_bits
        jmp 5f
4:      mov rdi, [rsp + 16]
        call int_neg
        mov rdi, r13
        mov rsi, rax
        call vr_shr
5:      mov rdi, rax
        mov rsi, [rip + vr_word_top_v]
        call int_min
        jmp .Lmv_ret
.Lmv_storage:
        mov rdi, rbx
        mov rsi, rsp
        call storage_ints
        test eax, eax
        jz .Lmv_top
        mov rdi, [rsp]                  # size < 256: 2^size - 1
        mov esi, (256 << 1) | 1
        call int_cmp
        test eax, eax
        jns .Lmv_top
        mov rdi, [rsp]
        call clamp_bits
        mov rdi, rax
        call pow2
        mov rdi, rax
        mov esi, 3
        call int_sub
        jmp .Lmv_ret
.Lmv_top:
        mov rax, [rip + vr_word_top_v]
.Lmv_ret:
        add rsp, 48
        LEAVE

.Lmv_mod:
        # ('mod', _, int c), 0 < c < 2^256: c - 1
        cmp dword ptr [rbx + N_AUX], 3
        jne .Lmv_mask
        mov rdi, [rbx + N_DATA + 16]
        call vr_number
        test rax, rax
        jz .Lmv_mask
        mov r13, rax
        mov rdi, rax
        call mv_word_above_zero
        test eax, eax
        jz .Lmv_mask
        mov rdi, r13
        mov esi, 3
        call int_sub
        jmp .Lmv_ret
.Lmv_div:
        # ('div', x, int c), 0 < c < 2^256: max_value(x) // c
        cmp dword ptr [rbx + N_AUX], 3
        jne .Lmv_mask
        mov rdi, [rbx + N_DATA + 16]
        call vr_number
        test rax, rax
        jz .Lmv_mask
        mov r13, rax
        mov rdi, rax
        call mv_word_above_zero
        test eax, eax
        jz .Lmv_mask
        mov rdi, [rbx + N_DATA + 8]
        call max_value
        mov rdi, rax
        mov rsi, r13
        call int_floordiv
        jmp .Lmv_ret
.Lmv_and:
        # the lowest of its operands'
        cmp dword ptr [rbx + N_AUX], 1
        jbe .Lmv_mask
        mov qword ptr [rsp + 32], 0
        mov r13d, 1
1:      cmp r13d, [rbx + N_AUX]
        jae 2f
        mov rdi, [rbx + N_DATA + r13*8]
        inc r13d
        call max_value
        cmp qword ptr [rsp + 32], 0
        je 3f
        mov rdi, [rsp + 32]
        mov rsi, rax
        call int_min
3:      mov [rsp + 32], rax
        jmp 1b
2:      mov rax, [rsp + 32]
        jmp .Lmv_ret
ENDF max_value

# mv_word_above_zero(c) -> eax: 0 < c < 2^256
FUNC mv_word_above_zero
        ENTER
        mov rbx, rdi
        call int_sign
        cmp eax, 1
        jne 9f
        mov rdi, rbx
        call int_lt_pow2_256
        LEAVE
9:      xor eax, eax
        LEAVE
ENDF mv_word_above_zero

# low_zero_bits(exp) -> rax: python's low_zero_bits - how many of the
# lowest bits of exp are sure to be 0
FUNC low_zero_bits
        STACK_CHECK
        ENTER
        sub rsp, 16
        mov rbx, rdi
        call is_int
        test eax, eax
        jz 1f
        mov rdi, rbx                    # as a word: 256 for 0, else its
        mov esi, 256                    # trailing zeros
        call int_mod_2exp
        cmp rax, 1
        je 8f
        mov rdi, rax
        call value_mpz
        mov rdi, rax
        xor esi, esi
        call __gmpz_scan1@PLT
        TAG rax
        jmp .Llz_ret
1:      mov rdi, rbx
        call opcode_of
        cmp eax, OP_MASK_SHL
        je .Llz_mask
        cmp eax, OP_MUL
        je .Llz_mul
        cmp eax, OP_ADD
        je .Llz_add
        mov eax, 1
        jmp .Llz_ret
.Llz_mask:
        # ('mask_shl', _, int off, int shl, _): max(0, min(256, off + shl))
        cmp dword ptr [rbx + N_AUX], 5
        jne 7f
        mov rdi, [rbx + N_DATA + 16]
        call vr_number
        test rax, rax
        jz 7f
        mov [rsp], rax
        mov rdi, [rbx + N_DATA + 24]
        call vr_number
        test rax, rax
        jz 7f
        mov rdi, [rsp]
        mov rsi, rax
        call int_add
        mov rdi, rax
        mov esi, (256 << 1) | 1
        call int_min
        mov rdi, rax
        mov esi, 1
        call int_max
        jmp .Llz_ret
7:      mov eax, 1
        jmp .Llz_ret
.Llz_mul:
        # min(256, the sum of its factors')
        mov qword ptr [rsp], 1
        mov r12d, 1
2:      cmp r12d, [rbx + N_AUX]
        jae 3f
        mov rdi, [rbx + N_DATA + r12*8]
        inc r12d
        call low_zero_bits
        mov rdi, [rsp]
        mov rsi, rax
        call int_add
        mov [rsp], rax
        jmp 2b
3:      mov rdi, [rsp]
        mov esi, (256 << 1) | 1
        call int_min
        jmp .Llz_ret
.Llz_add:
        # the fewest of its terms' (python's min() of none: a ValueError)
        cmp dword ptr [rbx + N_AUX], 1
        jbe .Llz_empty
        mov qword ptr [rsp], 0
        mov r12d, 1
4:      cmp r12d, [rbx + N_AUX]
        jae 5f
        mov rdi, [rbx + N_DATA + r12*8]
        inc r12d
        call low_zero_bits
        cmp qword ptr [rsp], 0
        je 6f
        mov rdi, [rsp]
        mov rsi, rax
        call int_min
6:      mov [rsp], rax
        jmp 4b
5:      mov rax, [rsp]
        jmp .Llz_ret
8:      mov eax, (256 << 1) | 1
.Llz_ret:
        add rsp, 16
        LEAVE
.Llz_empty:
        mov edi, E_VALUE
        lea rsi, [rip + .Ls_min_empty_lz]
        call err_throw
ENDF low_zero_bits

        .section .rodata
.Ls_min_empty_lz: .asciz "min() arg is an empty sequence"
        .text

# is_byte_element(exp, i) -> eax: python's `i in byte_elements(exp)` - the
# element i of exp is bytes: of a data, a sha3, an array, and the data (or
# the one value) of a return, a revert, a log, the params of a call... As
# many bytes as they're written (see sizeof), not as they're worth. Not a
# setmem's value - it's as wide as the range it's written to.
FUNC is_byte_element
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call opcode_of
        xor ecx, ecx
        cmp r12, 1
        jb 9f
        mov edx, [rbx + N_AUX]
        cmp r12, rdx
        jae 9f                          # (i < len(exp))
        cmp eax, OP_SHA3
        je 8f
        cmp eax, OP_DATA
        je 8f
        cmp eax, OP_ARR
        je 7f
        # the other operations: their operands that are bytes (and not None)
        mov ecx, 1 << 1
        cmp eax, OP_RETURN
        je 6f
        cmp eax, OP_REVERT
        je 6f
        cmp eax, OP_LOG
        je 6f
        mov ecx, (1 << 4) | (1 << 5)    # the selector and the params
        cmp eax, OP_CALL
        je 6f
        cmp eax, OP_STATICCALL
        je 6f
        cmp eax, OP_CALLCODE
        je 6f
        mov ecx, (1 << 3) | (1 << 4)
        cmp eax, OP_DELEGATECALL
        je 6f
        mov ecx, 1 << 2                 # the code
        cmp eax, OP_CREATE
        je 6f
        cmp eax, OP_CREATE2
        je 6f
        mov ecx, 1 << 3
        cmp eax, OP_PRECOMPILED
        je 6f
        jmp 9f
6:      cmp r12, 6
        jae 9f
        bt ecx, r12d
        jnc 9f
        mov rdi, [rbx + N_DATA + r12*8]
        call is_none
        test eax, eax
        jnz 9f
        jmp 8f
7:      cmp r12, 2                      # an arr: from 2
        jb 9f
8:      mov eax, 1
        LEAVE
9:      xor eax, eax
        LEAVE
ENDF is_byte_element

# sized(exp) -> eax: python's sized - exp, as an element of bytes, says how
# many bytes it is (a data, a Bytes(n, v), an ABI array, a range of memory
# or of calldata, of an account's code...) rather than by how it's written
FUNC sized
        ENTER
        call opcode_of
        mov ebx, eax
        mov edi, eax
        call is_array_op
        test eax, eax
        jnz 8f
        cmp ebx, OP_BYTES
        je 8f
        cmp ebx, OP_DATA
        je 8f
        cmp ebx, OP_ARR
        je 8f
        cmp ebx, OP_MEM
        je 8f
        cmp ebx, OP_SALL
        je 8f
        cmp ebx, OP_EXTCODECOPY
        je 8f
        xor eax, eax
        LEAVE
8:      mov eax, 1
        LEAVE
ENDF sized

# sizeof(exp) -> rax: python's sizeof - the size of an expression in bits
# (an AssertionError for a ('mem', x) that isn't of a range, an ('arr',
# ...))
FUNC sizeof
        STACK_CHECK
        ENTER
        call sizeof_nil
        test rax, rax
        jz 1f
        LEAVE
1:      mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_sizeof_w]
        call err_throw
ENDF sizeof

        .section .rodata
.Ls_assert_sizeof_w: .asciz "sizeof: unexpected expression"
        .text

# sizeof_nil(exp) -> rax: sizeof, NIL where it asserts
FUNC sizeof_nil
        STACK_CHECK
        ENTER
        sub rsp, 16
        mov rbx, rdi
        call is_tuple
        test eax, eax
        jz 7f                           # (a leaf: a number, a string...)
        mov rdi, rbx
        call opcode_of
        mov r12d, eax
        mov ecx, [rbx + N_AUX]
        cmp r12d, OP_BYTES
        jne 1f
        cmp ecx, 3                      # ('bytes', size, _): its bits
        jne 1f
        mov rdi, [rbx + N_DATA + 8]
        call alg_bits
        jmp .Lsz_ret
1:      cmp r12d, OP_DATA
        jne 2f
        # the sum of its parts' (0 for none)
        cmp ecx, 1
        jbe .Lsz_zero
        call vec_new
        mov [rsp], rax
        mov r13d, 1
11:     cmp r13d, [rbx + N_AUX]
        jae 12f
        mov rdi, [rbx + N_DATA + r13*8]
        inc r13d
        call sizeof_nil
        test rax, rax
        jz .Lsz_ret                     # (an assert: NIL)
        mov rdi, [rsp]
        mov rsi, rax
        call vec_push
        jmp 11b
12:     mov rax, [rsp]
        mov rdi, [rax + VEC_LEN]
        mov rsi, [rax + VEC_DATA]
        call alg_add_n
        jmp .Lsz_ret
2:      cmp r12d, OP_STORAGE
        jne 3f
        cmp ecx, 2                      # ('storage', size, ...)
        jb 3f
        mov rax, [rbx + N_DATA + 8]
        jmp .Lsz_ret
3:      cmp r12d, OP_MASK_SHL
        jne 4f
        cmp ecx, 5                      # size + off + shl
        jne 4f
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, [rbx + N_DATA + 16]
        mov rdx, [rbx + N_DATA + 24]
        call alg_add3
        jmp .Lsz_ret
4:      # (op, _, size_bytes), op an array: its bits - op any element
        cmp ecx, 3
        jne 5f
        mov rdi, [rbx + N_DATA]
        call str_id
        mov edi, eax
        call is_array_op
        test eax, eax
        jz 5f
        mov rdi, [rbx + N_DATA + 16]
        call alg_bits
        jmp .Lsz_ret
5:      cmp r12d, OP_MEM
        jne 6f
        cmp dword ptr [rbx + N_AUX], 2
        jne 6f
        mov rdi, [rbx + N_DATA + 8]     # ('mem', ('range', _, size_bytes))
        mov esi, OP_RANGE
        mov edx, 3
        call is_op_n
        test eax, eax
        jz .Lsz_nil                     # (assert not match(exp, ('mem', idx)))
        mov rax, [rbx + N_DATA + 8]
        mov rdi, [rax + N_DATA + 16]
        call alg_bits
        jmp .Lsz_ret
6:      cmp r12d, OP_EXTCODECOPY
        jne 61f
        cmp dword ptr [rbx + N_AUX], 3
        jne 61f
        mov rdi, [rbx + N_DATA + 16]    # ('extcodecopy', _, ('range', _, size))
        mov esi, OP_RANGE
        mov edx, 3
        call is_op_n
        test eax, eax
        jz 61f
        mov rax, [rbx + N_DATA + 16]
        mov rdi, [rax + N_DATA + 16]
        call alg_bits
        jmp .Lsz_ret
61:     cmp r12d, OP_ARR                # (assert not match(exp, ('arr', l, _)))
        jne 7f
        cmp dword ptr [rbx + N_AUX], 3
        je .Lsz_nil
7:      mov rdi, rbx
        call is_int
        test eax, eax
        jz 8f
        # above 2^256 (python's exp > 2**256): the bytes needed to hold it
        mov rdi, rbx
        call int_gt_pow2_256
        test eax, eax
        jz 8f
        mov rdi, rbx
        call int_bit_length
        add rax, 7
        shr rax, 3
        TAG rax
        mov rdi, rax
        call alg_bits
        jmp .Lsz_ret
8:      mov eax, (256 << 1) | 1
        jmp .Lsz_ret
.Lsz_zero:
        mov eax, 1
        jmp .Lsz_ret
.Lsz_nil:
        xor eax, eax
.Lsz_ret:
        add rsp, 16
        LEAVE
ENDF sizeof_nil

# width_of(exp) -> rax: python's width_of - the bits exp is as an element
# of bytes (see sizeof), NIL when it isn't known: an ABI-encoded array in
# it, whose offset goes before the rest
FUNC width_of
        STACK_CHECK
        ENTER
        mov rbx, rdi
        call opcode_of
        cmp eax, OP_ARR
        je 9f
        cmp eax, OP_DATA
        jne 2f
        mov r12d, 1
1:      cmp r12d, [rbx + N_AUX]
        jae 2f
        mov rdi, [rbx + N_DATA + r12*8]
        inc r12d
        call width_of
        test rax, rax
        jnz 1b
        jmp 9f
2:      mov rdi, rbx
        call sizeof_nil
        LEAVE
9:      xor eax, eax
        LEAVE
ENDF width_of

# implicit(exp, width) -> eax: python's implicit - exp, as `width` bits of
# bytes, needs no ('bytes', ...) to say how wide it is: it's a word, or it
# says how many bytes it is (a range...)
FUNC implicit
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call sized
        test eax, eax
        jz 2f
        mov rdi, rbx
        call width_of
        test rax, rax
        jz 8f                           # (not known: as it is)
        mov rdi, rax
        mov rsi, r12
        call alg_sub_op
        mov rdi, rax
        mov esi, 1
        call py_equal
        LEAVE
2:      mov rdi, r12                    # a word, 256 bits
        mov esi, (256 << 1) | 1
        call py_equal
        test eax, eax
        jz 9f
        mov rdi, rbx
        call width_of
        test rax, rax
        jz 9f
        mov rdi, rax
        mov esi, (256 << 1) | 1
        call py_equal
        LEAVE
8:      mov eax, 1
        LEAVE
9:      xor eax, eax
        LEAVE
ENDF implicit

# keep_width(old, new) -> rax: python's keep_width - new, worth what old
# is, where old is an element of bytes: as wide as old is. What says how
# many bytes it is is as it's rewritten; a number that isn't a word says it.
FUNC keep_width
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov rdi, rsi
        mov rsi, rbx
        call py_equal
        test eax, eax
        jnz 8f
        mov rdi, r12
        call sized
        test eax, eax
        jnz 8f
        mov rdi, rbx
        call width_of
        test rax, rax
        jz 8f
        mov r13, rax                    # old's width
        mov rdi, rax
        mov esi, (256 << 1) | 1
        call py_equal
        test eax, eax
        jz 1f
        mov rdi, r12                    # both words
        call width_of
        test rax, rax
        jz 1f
        mov rdi, rax
        mov esi, (256 << 1) | 1
        call py_equal
        test eax, eax
        jnz 8f
1:      # a whole number of bytes: the value, as that many bytes
        mov rdi, r13
        call is_int
        test eax, eax
        jz 9f
        mov rdi, r13
        call int_sign
        cmp eax, 1
        jne 9f
        mov rdi, r13
        mov esi, 3
        call int_mod_2exp
        cmp rax, 1
        jne 9f
        mov rdi, r13
        mov esi, (8 << 1) | 1
        call int_floordiv
        LOADS rdi, BYTES
        mov rsi, rax
        mov rdx, r12
        call mk3
        LEAVE
8:      mov rax, r12
        LEAVE
9:      mov rax, rbx
        LEAVE
ENDF keep_width

# keep_widths(old, new) -> rax: python's keep_widths - new, the operation
# old is with its operands rewritten, with the ones that are bytes as wide
# as they were - and the value of a write to memory as wide as the range
# it's written to
FUNC keep_widths
        STACK_CHECK
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov rdi, rbx
        call is_tuple
        test eax, eax
        jz 8f
        mov rdi, r12
        call is_tuple
        test eax, eax
        jz 8f
        cmp rbx, r12                    # (new == old: hash-consed)
        je 8f
        mov eax, [rbx + N_AUX]
        cmp eax, [r12 + N_AUX]
        jne 8f
        test eax, eax
        jz 8f
        mov rdi, r12                    # (an operation with no bytes: as it is)
        call opcode_of
        IN_OPSET kw_ops, rax
        je 8f
        mov rdi, [rbx + N_DATA]         # opcode(old) == opcode(new): their heads
        mov rsi, [r12 + N_DATA]
        call py_equal
        test eax, eax
        jz 8f
        # res = list(new): the elements, rewritten where they're bytes
        mov edi, [r12 + N_AUX]
        shl rdi, 3
        call arena_alloc_raw
        mov r13, rax
        mov ecx, [r12 + N_AUX]
        xor edx, edx
1:      cmp edx, ecx
        jae 2f
        mov rax, [r12 + N_DATA + rdx*8]
        mov [r13 + rdx*8], rax
        inc edx
        jmp 1b
2:      mov qword ptr [rsp], 1
3:      mov rax, [rsp]
        cmp eax, [r12 + N_AUX]
        jae 4f
        mov rdi, r12
        mov rsi, rax
        call is_byte_element
        test eax, eax
        jz 31f
        mov rcx, [rsp]
        mov rdi, [r13 + rcx*8]
        mov rsi, [rbx + N_DATA + rcx*8]
        call py_equal                   # (res[i] != old[i])
        test eax, eax
        jnz 31f
        mov rcx, [rsp]
        mov rdi, [rbx + N_DATA + rcx*8]
        mov rsi, [r13 + rcx*8]
        call keep_width
        mov rcx, [rsp]
        mov [r13 + rcx*8], rax
31:     inc qword ptr [rsp]
        jmp 3b
4:      # a setmem of a range: its value as wide as the range
        mov rdi, r12
        call opcode_of
        cmp eax, OP_SETMEM
        jne 5f
        cmp dword ptr [r12 + N_AUX], 3
        jne 5f
        mov rdi, [r12 + N_DATA + 8]
        call opcode_of
        cmp eax, OP_RANGE
        jne 5f
        mov rax, [r12 + N_DATA + 8]
        cmp dword ptr [rax + N_AUX], 3
        jb 5f
        mov rdi, [rax + N_DATA + 16]    # the range's length
        mov rsi, [rbx + N_DATA + 16]
        mov rdx, [r13 + 16]
        call keep_setmem_width
        mov [r13 + 16], rax
5:      mov edi, [r12 + N_AUX]
        mov rsi, r13
        call mk_tuple
        add rsp, 16
        LEAVE
8:      mov rax, r12
        add rsp, 16
        LEAVE
ENDF keep_widths

# keep_setmem_width(length, old, new) -> rax: python's keep_setmem_width -
# new, worth what old is, written to `length` bytes of memory: a number
# takes that many bytes; what says how many bytes it is must be as many -
# or, bytes of another width, the number they make: fewer of them as that
# many bytes (see with_width), more their last bytes
FUNC keep_setmem_width
        STACK_CHECK
        ENTER
        mov rbx, rdi                    # length
        mov r12, rsi                    # old
        mov r13, rdx                    # new
        mov rdi, rdx
        mov rsi, r12
        call py_equal
        test eax, eax
        jnz 8f
        mov rdi, r13
        call sized
        test eax, eax
        jz 8f
        mov rdi, r13
        call width_of
        mov r14, rax                    # width
        mov rdi, rax
        call is_int
        test eax, eax
        jz 8f
        mov rdi, rbx
        call is_int
        test eax, eax
        jz 8f
        mov rdi, rbx
        mov esi, (8 << 1) | 1
        call int_mul
        mov rdi, r14
        mov rsi, rax
        call int_cmp
        test eax, eax
        jz 8f                           # as many: as it's rewritten
        js 1f
        # more: their last bytes, when they can be cut there
        mov rdi, r13
        mov rsi, rbx
        call resize_bytes
        test rax, rax
        jnz 9f
1:      # fewer (or not cut): as that many bytes - up to a word, not a data
        mov rdi, rbx
        call int_sign
        cmp eax, 1
        jne 7f
        mov rdi, rbx
        mov esi, (32 << 1) | 1
        call int_cmp
        cmp eax, 0
        jg 7f
        mov rdi, r14
        call int_sign
        cmp eax, 1
        jne 7f
        mov rdi, r14
        mov esi, (256 << 1) | 1
        call int_cmp
        cmp eax, 0
        jg 7f
        mov rdi, r13
        call opcode_of
        cmp eax, OP_DATA
        je 7f
        LOADS rdi, BYTES
        mov rsi, rbx
        mov rdx, r13
        call mk3
        LEAVE
7:      mov rax, r12
        LEAVE
8:      mov rax, r13
9:      LEAVE
ENDF keep_setmem_width

# resize_bytes(exp, size) -> rax: python's resize_bytes - exp, bytes of a
# known width, as the number they make written to `size` bytes, without a
# ('bytes', ...) of bytes of another width: zeroes before them, or their
# last `size` bytes. NIL when they can't be cut there.
FUNC resize_bytes
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call width_of
        mov r13, rax
        mov rdi, rax
        call is_int
        test eax, eax
        jz 9f
        mov rdi, r12
        call is_int
        test eax, eax
        jz 9f
        mov rdi, r13                    # (a whole number of bytes)
        mov esi, 3
        call int_mod_2exp
        cmp rax, 1
        jne 9f
        mov rdi, r13
        mov esi, (8 << 1) | 1
        call int_floordiv
        mov r13, rax                    # the width, in bytes
        mov rdi, rax
        mov rsi, r12
        call int_cmp
        test eax, eax
        jz 7f                           # as many: as it is
        jns 4f
        # fewer: zeroes before them
        mov rdi, r12
        mov rsi, r13
        call int_sub
        LOADS rdi, BYTES
        mov rsi, rax
        mov edx, 1
        call mk3
        mov r14, rax                    # ('bytes', size - width, 0)
        call vec_new
        mov r13, rax
        mov rdi, r13
        LOADS rsi, DATA
        call vec_push
        mov rdi, r13
        mov rsi, r14
        call vec_push
        mov rdi, rbx
        call opcode_of
        cmp eax, OP_DATA
        jne 2f
        mov rdi, r13                    # a data's parts
        lea rsi, [rbx + N_DATA + 8]
        mov edx, [rbx + N_AUX]
        dec edx
        call vec_extend
        jmp 3f
2:      mov rdi, r13
        mov rsi, rbx
        call vec_push
3:      mov rdi, r13
        call vec_to_tuple
        LEAVE
4:      # more: their last `size` bytes
        mov rdi, r13
        mov rsi, r12
        call int_sub
        mov rdi, rbx
        mov rsi, rax
        mov rdx, r13
        xor ecx, ecx
        call slice_exp
        test rax, rax
        jz 9f
        mov r14, rax
        mov rdi, rax
        call opcode_of
        cmp eax, OP_BYTES
        jne 5f
        cmp dword ptr [r14 + N_AUX], 3
        jb 5f
        mov rdi, [r14 + N_DATA + 16]
        call sized
        test eax, eax
        jnz 9f
5:      mov rax, r14
        LEAVE
7:      mov rax, rbx
        LEAVE
9:      xor eax, eax
        LEAVE
ENDF resize_bytes

# with_width(exp, size) -> rax: python's with_width - exp as the `size`
# bytes of memory it's in: the number it is, as that many bytes - of bytes
# of another width, the number they make
FUNC with_width
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call opcode_of
        cmp eax, OP_BYTES
        jne 1f
        cmp dword ptr [rbx + N_AUX], 3
        jb 1f
        mov rbx, [rbx + N_DATA + 16]
1:      mov rdi, rbx                    # a mask of numbers: a number, a word
        call opcode_of
        cmp eax, OP_MASK_SHL
        jne 2f
        mov edi, [rbx + N_AUX]
        cmp edi, 5
        jb 2f
        dec edi
        lea rsi, [rbx + N_DATA + 8]
        call all_ints
        test eax, eax
        jz 2f
        mov rdi, [rbx + N_DATA + 32]
        mov rsi, [rbx + N_DATA + 8]
        mov rdx, [rbx + N_DATA + 16]
        mov rcx, [rbx + N_DATA + 24]
        call alg_apply_mask
        mov rbx, rax
2:      mov rdi, r12
        call alg_bits
        mov rdi, rbx
        mov rsi, rax
        call implicit
        test eax, eax
        jnz 8f
        LOADS rdi, BYTES
        mov rsi, r12
        mov rdx, rbx
        call mk3
        LEAVE
8:      mov rax, rbx
        LEAVE
ENDF with_width

        # the operations with operands that are bytes (byte_elements), and
        # setmem: keep_widths' only
        .irp op, SHA3, DATA, ARR, RETURN, REVERT, LOG, CALL, STATICCALL, CALLCODE, DELEGATECALL, CREATE, CREATE2, PRECOMPILED, SETMEM
        OPSET_MEMBER kw_ops, OP_\op
        .endr
        OPSET_END kw_ops, OP_COUNT

        .section .note.GNU-stack,"",@progbits
