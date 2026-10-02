# The bytes of the data as text (port of prettify.py's pretty_memory and
# the helpers of the PR around it): bytes of a known width (Bytes(n, v)),
# the bytes of text as string literals ('text'), the ABI-encoded strings,
# the selectors of a call's data, the widths of the elements of bytes
# (fix_widths), and the places of the storage (pretty_loc).

.include "defs.inc"

        .section .rodata
.Ls_bytes_:     .asciz "Bytes("
.Ls_comma_sp:   .asciz ", "
.Ls_rparen:     .asciz ")"
.Ls_0x:         .asciz "0x"
.Ls_zero:       .asciz "0"
.Ls_empty_call: .asciz "empty()"
.Ls_array_len:  .asciz "Array(len="
.Ls_data_eq:    .asciz ", data="
.Ls_unknown:    .asciz "unknown"
.Ls_q_end:      .asciz "(?)"
.Ls_dot_length: .asciz ".length"
.Ls_lbracket:   .asciz "["
.Ls_rbracket:   .asciz "]"
.Ls_dot_field_: .asciz ".field_"
.Ls_stor_:      .asciz "stor["
.Ls_param_:     .asciz " _param"
.Ls_pm_index:   .asciz "IndexError: tuple index out of range (pretty_memory)"
.Ls_neg_length: .asciz "ValueError: length argument must be non-negative"
.Ls_too_big:    .asciz "MemoryError: bytes of a size too big"
.Ls_loc_type:   .asciz "TypeError: a place of the storage that isn't a sequence"

        .text

.macro B reg, n
        mov \reg, [rsp + 8*(\n)]
.endm

.macro PF_COLOR_OF dst, src
        mov \dst, \src
        and \dst, PF_COLOR
.endm

# --- text ---

# is_text_byte(c) -> the character c is in TEXT_CHARS: the printable ones
# and the whitespace (\n \r \t)
.macro TEXT_BYTE_CHECK reg8, fail
        cmp \reg8, 0x7e
        ja \fail
        cmp \reg8, 0x20
        jae .Ltb_ok\@
        cmp \reg8, 9
        je .Ltb_ok\@
        cmp \reg8, 10
        je .Ltb_ok\@
        cmp \reg8, 13
        jne \fail
.Ltb_ok\@:
.endm

# pretty_text(buf, len, short) -> str or 0: python's pretty_text - the
# bytes as a string literal, if they're text: with letters or digits, or
# any printable ones if short (a separator of two at most)
FUNC pretty_text
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        test r12, r12
        jz 9f
        xor ecx, ecx
        xor r14d, r14d                  # any letter or digit
1:      cmp rcx, r12
        jae 3f
        movzx eax, byte ptr [rbx + rcx]
        TEXT_BYTE_CHECK al, 9f
        mov edx, eax
        sub edx, '0'
        cmp edx, 9
        jbe 2f
        mov edx, eax
        or edx, 0x20
        sub edx, 'a'
        cmp edx, 25
        ja 21f
2:      mov r14d, 1
21:     inc rcx
        jmp 1b
3:      test r14d, r14d
        jnz 4f
        test r13, r13
        jz 9f
        cmp r12, 2
        ja 9f
4:      call sb_new
        mov r13, rax
        mov rdi, rax
        mov esi, '\''
        call sb_append_char
        xor r14d, r14d
5:      cmp r14, r12
        jae 8f
        movzx esi, byte ptr [rbx + r14]
        inc r14
        cmp esi, '\\'
        je 51f
        cmp esi, '\''
        je 51f
        cmp esi, 10
        je 52f
        cmp esi, 13
        je 53f
        cmp esi, 9
        je 54f
        mov rdi, r13
        call sb_append_char
        jmp 5b
51:     push rsi
        push rsi
        mov rdi, r13
        mov esi, '\\'
        call sb_append_char
        pop rsi
        pop rsi
        mov rdi, r13
        call sb_append_char
        jmp 5b
52:     mov esi, 'n'
        jmp 55f
53:     mov esi, 'r'
        jmp 55f
54:     mov esi, 't'
55:     push rsi
        push rsi
        mov rdi, r13
        mov esi, '\\'
        call sb_append_char
        pop rsi
        pop rsi
        mov rdi, r13
        call sb_append_char
        jmp 5b
8:      mov rdi, r13
        mov esi, '\''
        call sb_append_char
        mov rdi, r13
        call sb_finish
        LEAVE
9:      xor eax, eax
        LEAVE
ENDF pretty_text

# sb_append_be(sb, val, size): the `size` bytes of the int val (0 <= val <
# 2^(8 size)), big-endian - val.to_bytes(size, "big")
FUNC sb_append_be
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov rdi, rsi
        call value_mpz
        mov r14, rax
        mov rdi, rax
        mov esi, 2
        call __gmpz_sizeinbase@PLT
        mov rcx, rax
        add rcx, 7
        shr rcx, 3                      # the bytes of val
        cmp r12, 1                      # (0: none)
        jne 1f
        xor ecx, ecx
1:      mov [rsp], rcx
        mov rax, r13
        sub rax, rcx                    # the zeroes before them
        mov [rsp + 8], rax
2:      cmp qword ptr [rsp + 8], 0
        jle 3f
        mov rdi, rbx
        xor esi, esi
        call sb_append_char
        dec qword ptr [rsp + 8]
        jmp 2b
3:      mov rsi, [rsp]
        test rsi, rsi
        jz 4f
        mov rdi, rbx
        call sb_reserve
        mov rdi, [rbx + SB_BUF]
        add rdi, [rbx + SB_LEN]
        xor esi, esi                    # (the count: not needed)
        mov edx, 1                      # order: most significant first
        mov ecx, 1                      # bytes
        mov r8d, 1                      # big endian
        xor r9d, r9d
        push r14
        push r14
        call __gmpz_export@PLT
        pop r14
        pop r14
        mov rax, [rsp]
        add [rbx + SB_LEN], rax
        mov rcx, [rbx + SB_BUF]
        add rcx, [rbx + SB_LEN]
        mov byte ptr [rcx], 0
4:      add rsp, 16
        LEAVE
ENDF sb_append_be

# data_bytes_into(sb, exp) -> eax: python's data_bytes - the bytes of exp
# as an element of a data, if they're known (Bytes(n, number), a word),
# appended (1); 0 for None
FUNC data_bytes_into
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov rdi, rsi
        OP_N_CHECK OP_BYTES, 3, 5f
        mov r13, [r12 + N_DATA + 8]     # size
        mov r14, [r12 + N_DATA + 16]    # val
        mov rdi, r13
        call is_int
        test eax, eax
        jz 9f
        mov rdi, r14
        call is_int
        test eax, eax
        jz 9f
        # 0 <= val < 2 ** (8 * size)
        mov rdi, r14
        call int_sign
        cmp eax, -1
        je 9f
        mov rdi, r13
        call int_sign
        cmp eax, -1
        jne 2f
        # a negative size: 2 ** (8 * size) is a float, only 0 below it -
        # whose to_bytes of that size is a ValueError (0.0, an underflow,
        # from 8 * size < -1074: nothing below it)
        cmp r14, 1
        jne 9f
        mov rdi, r13
        mov rsi, (-134 << 1) | 1
        call int_cmp
        cmp eax, -1
        je 9f
        mov edi, E_VALUE
        lea rsi, [rip + .Ls_neg_length]
        call err_throw
2:      mov rdi, r13
        call bytes_size
        mov r13, rax                    # (untagged)
        mov rdi, r14
        call int_bit_length
        lea rcx, [r13*8]
        cmp rax, rcx
        ja 9f
        mov rdi, rbx
        mov rsi, r14
        mov rdx, r13
        call sb_append_be
        mov eax, 1
        LEAVE
5:      # a word
        mov rdi, r12
        call is_int
        test eax, eax
        jz 9f
        mov rdi, r12
        call int_sign
        cmp eax, -1
        je 9f
        mov rdi, r12
        call int_lt_pow2_256
        test eax, eax
        jz 9f
        mov rdi, rbx
        mov rsi, r12
        mov edx, 32
        call sb_append_be
        mov eax, 1
        LEAVE
9:      xor eax, eax
        LEAVE
ENDF data_bytes_into

# bytes_size(size) -> rax: a size of bytes (a non-negative int) as a
# count, python's MemoryError past 2^24 (python would make them)
FUNC bytes_size
        test dil, 1
        jz 1f
        mov rax, rdi
        sar rax, 1
        cmp rax, 1 << 24
        ja 1f
        ret
1:      mov edi, E_MEMORY
        lea rsi, [rip + .Ls_too_big]
        jmp err_throw
ENDF bytes_size

# has_data_bytes(exp) -> eax: data_bytes(exp) is not None
FUNC has_data_bytes
        ENTER
        mov rbx, rdi
        call sb_new
        mov r12, rax
        mov rdi, rax
        mov rsi, rbx
        call data_bytes_into
        mov r13d, eax
        mov rdi, r12
        call sb_free
        mov eax, r13d
        LEAVE
ENDF has_data_bytes

# sb_any_nonzero(sb, from) -> eax: any(b[from:]) (from >= 0)
FUNC sb_any_nonzero
        mov rcx, [rdi + SB_LEN]
        mov rdx, [rdi + SB_BUF]
1:      cmp rsi, rcx
        jae 2f
        cmp byte ptr [rdx + rsi], 0
        jne 3f
        inc rsi
        jmp 1b
2:      xor eax, eax
        ret
3:      mov eax, 1
        ret
ENDF sb_any_nonzero

# arr_text(exp) -> str or 0: python's arr_text - an ("arr", len, ...) of
# text, as a string literal
FUNC arr_text
        ENTER
        sub rsp, 16
        mov rbx, rdi
        call opcode_of
        cmp eax, OP_ARR
        jne 9f
        cmp dword ptr [rbx + N_AUX], 2
        jb 9f
        # the bytes of the terms (all of them: python makes the list first)
        call sb_new
        mov r12, rax
        mov qword ptr [rsp], 0          # a term without bytes
        mov r13d, 2
1:      cmp r13d, [rbx + N_AUX]
        jae 2f
        mov rdi, r12
        mov rsi, [rbx + N_DATA + r13*8]
        call data_bytes_into
        test eax, eax
        jnz 11f
        mov qword ptr [rsp], 1
11:     inc r13d
        jmp 1b
2:      cmp qword ptr [rsp], 0
        jne 9f
        mov r13, [rbx + N_DATA + 8]     # l
        test r13b, 1
        jz 9f                           # (a big int: past the bytes, or
        sar r13, 1                      # before their start)
        mov r14, [r12 + SB_LEN]
        cmp r14, r13
        jl 9f                           # len(b) >= l
        # b[l:] all zero, b[:l] text (python's slices of a negative l)
        mov rsi, r13
        test rsi, rsi
        jns 3f
        add rsi, r14
        jns 3f
        xor esi, esi
3:      mov [rsp + 8], rsi              # where b[l:] starts, b[:l] ends
        mov rdi, r12
        call sb_any_nonzero
        test eax, eax
        jnz 9f
        mov rdi, [r12 + SB_BUF]
        mov rsi, [rsp + 8]
        xor edx, edx
        call pretty_text
        add rsp, 16
        LEAVE
9:      xor eax, eax
        add rsp, 16
        LEAVE
ENDF arr_text

# raw_text(el, printed) -> str: python's raw_text - printed, the element el
# that's all the data of a return or a revert: Bytes(n, 'text') if it's
# bytes of text - a string alone is ABI-encoded
FUNC raw_text
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov rdi, rsi
        call clean_color
        cmp dword ptr [rax + N_DATA], 0
        je 9f
        cmp byte ptr [rax + N_DATA + 4], '\''
        jne 9f
        call sb_new
        mov r13, rax
        mov rdi, rax
        mov rsi, rbx
        call data_bytes_into
        test eax, eax
        jz 9f
        mov r14, [r13 + SB_LEN]
        mov rdi, r13
        call sb_reset
        mov rdi, r13
        lea rsi, [rip + .Ls_bytes_]
        call sb_append_c
        mov rdi, r13
        mov rsi, r14
        call sb_append_u64
        mov rdi, r13
        lea rsi, [rip + .Ls_comma_sp]
        call sb_append_c
        mov rdi, r13
        mov rsi, r12
        call sb_append_str
        mov rdi, r13
        mov esi, ')'
        call sb_append_char
        mov rdi, r13
        call sb_finish
        LEAVE
9:      mov rax, r12
        LEAVE
ENDF raw_text

# --- bytes of a width ---

# pretty_bytes(size, val, flags, ctx) -> str: python's pretty_bytes -
# ("bytes", size, val): a word is shown as its value, text as a string,
# anything else as its value with its width - Bytes(size, val)
FUNC pretty_bytes
        STACK_CHECK
        ENTER
        sub rsp, 32
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov [rsp], rcx
        mov rsi, (32 << 1) | 1
        call py_equal
        test eax, eax
        jz 1f
        mov rdi, r12                    # prettify(val, parentheses=ctx)
        mov rsi, [rsp]
        shl rsi, PF_CTX_SHIFT
        test r13, PF_COLOR
        jz 11f
        or rsi, PF_COLOR
11:     call prettify
        add rsp, 32
        LEAVE
1:      # an int val of an int size, 0 <= val < 2 ** (8 * size)
        mov rdi, r12
        call is_int
        test eax, eax
        jz .Lpb_any
        mov rdi, rbx
        call is_int
        test eax, eax
        jz .Lpb_any
        mov rdi, r12
        call int_sign
        cmp eax, -1
        je .Lpb_any
        mov rdi, rbx
        call int_sign
        cmp eax, -1
        jne 2f
        # (a negative size: 0 alone is below its float, and can't be made
        # bytes of that size)
        cmp r12, 1
        jne .Lpb_any
        mov rdi, rbx
        mov rsi, (-134 << 1) | 1
        call int_cmp
        cmp eax, -1
        je .Lpb_any
        mov edi, E_VALUE
        lea rsi, [rip + .Ls_neg_length]
        call err_throw
2:      mov rdi, rbx
        call bytes_size
        mov r14, rax
        mov rdi, r12
        call int_bit_length
        lea rcx, [r14*8]
        cmp rax, rcx
        ja .Lpb_any
        # text, as a string literal (short: a separator)
        call sb_new
        mov [rsp + 8], rax
        mov rdi, rax
        mov rsi, r12
        mov rdx, r14
        call sb_append_be
        mov rax, [rsp + 8]
        mov rdi, [rax + SB_BUF]
        mov rsi, [rax + SB_LEN]
        mov edx, 1
        call pretty_text
        test rax, rax
        jnz .Lpb_ret
        # Bytes(size, 0x<2 size digits>), or Bytes(size, 0)
        mov rdi, [rsp + 8]
        call sb_reset
        mov rdi, [rsp + 8]
        lea rsi, [rip + .Ls_bytes_]
        lea rdx, [rip + C_GRAY]
        mov rcx, r13
        call sb_append_col_c
        mov rdi, [rsp + 8]
        mov rsi, r14
        call sb_append_u64
        mov rdi, [rsp + 8]
        lea rsi, [rip + .Ls_comma_sp]
        lea rdx, [rip + C_GRAY]
        mov rcx, r13
        call sb_append_col_c
        cmp r12, 1
        jne 3f
        mov rdi, [rsp + 8]
        lea rsi, [rip + .Ls_zero]
        call sb_append_c
        jmp 5f
3:      mov rdi, [rsp + 8]
        lea rsi, [rip + .Ls_0x]
        call sb_append_c
        mov rdi, r12
        call hex_digit_count
        lea rcx, [r14*2]
        sub rcx, rax                    # the zeroes before the digits
        mov [rsp + 16], rcx
4:      cmp qword ptr [rsp + 16], 0
        jle 41f
        mov rdi, [rsp + 8]
        mov esi, '0'
        call sb_append_char
        dec qword ptr [rsp + 16]
        jmp 4b
41:     mov rdi, [rsp + 8]
        mov rsi, r12
        call hex_digits
5:      mov rdi, [rsp + 8]
        lea rsi, [rip + .Ls_rparen]
        lea rdx, [rip + C_GRAY]
        mov rcx, r13
        call sb_append_col_c
        mov rdi, [rsp + 8]
        call sb_finish
        jmp .Lpb_ret
.Lpb_any:
        # Bytes(prettify(size), prettify(val))
        call sb_new
        mov r14, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_bytes_]
        lea rdx, [rip + C_GRAY]
        mov rcx, r13
        call sb_append_col_c
        mov rdi, r14
        mov rsi, rbx
        PF_COLOR_OF rdx, r13
        call sb_append_pret
        mov rdi, r14
        lea rsi, [rip + .Ls_comma_sp]
        lea rdx, [rip + C_GRAY]
        mov rcx, r13
        call sb_append_col_c
        mov rdi, r14
        mov rsi, r12
        PF_COLOR_OF rdx, r13
        call sb_append_pret
        mov rdi, r14
        lea rsi, [rip + .Ls_rparen]
        lea rdx, [rip + C_GRAY]
        mov rcx, r13
        call sb_append_col_c
        mov rdi, r14
        call sb_finish
.Lpb_ret:
        add rsp, 32
        LEAVE
ENDF pretty_bytes

# hex_digit_count(v) -> rax: the hex digits of a non-negative int (1 for 0)
FUNC hex_digit_count
        ENTER
        call value_mpz
        mov rdi, rax
        mov esi, 16
        call __gmpz_sizeinbase@PLT
        LEAVE
ENDF hex_digit_count

# pw_with_width(el) -> value: prettify.py's with_width - an element of
# bytes (of a data, a sha3, a return...) whose width isn't a word, with it:
# Bytes(n, el). It's in how the element is written (see memloc.sizeof),
# which rewrites for display don't keep - a mask of the lowest 8 bits
# becomes a division, uint8(x >> 8) x / 256.
FUNC pw_with_width
        STACK_CHECK
        ENTER
        mov rbx, rdi
        call opcode_of
        cmp eax, OP_BYTES
        jne 2f
        cmp dword ptr [rbx + N_AUX], 3
        jb .Lww_index
        mov rdi, [rbx + N_DATA + 16]
        call sized
        test eax, eax
        jz 2f
        # the number bytes of another width make, as n bytes: zeroes and
        # them, or their last n bytes (see memloc.resize_bytes)
        mov rdi, [rbx + N_DATA + 16]
        mov rsi, [rbx + N_DATA + 8]
        call resize_bytes
        test rax, rax
        jnz 9f
        mov rax, rbx
        LEAVE
2:      mov rdi, rbx
        call sized
        test eax, eax
        jnz 8f
        # an access of the storage (see storage.py): as wide as it reads
        mov rdi, rbx
        OP_N_CHECK OP_ST, 4, 3f
        mov r12, [rbx + N_DATA + 8]
        jmp 4f
3:      mov rdi, rbx
        call sizeof
        mov r12, rax
4:      cmp r12, (256 << 1) | 1
        je 8f
        mov rdi, r12
        call is_none
        test eax, eax
        jnz 8f
        mov rdi, r12
        call is_int
        test eax, eax
        jz 6f
        # (an int width: in bytes, unless not a positive multiple of 8)
        mov rdi, r12
        call int_sign
        cmp eax, 1
        jne 8f
        mov rdi, r12
        mov rsi, (8 << 1) | 1
        call int_mod
        cmp rax, 1
        jne 8f
        mov rdi, r12
        mov rsi, (8 << 1) | 1
        call int_floordiv
        mov rsi, rax
        jmp 7f
6:      LOADS rdi, DIV
        mov rsi, r12
        mov rdx, (8 << 1) | 1
        call mk3
        mov rsi, rax
7:      LOADS rdi, BYTES
        mov rdx, rbx
        call mk3
9:      LEAVE
8:      mov rax, rbx
        LEAVE
.Lww_index:
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_pm_index]
        call err_throw
ENDF pw_with_width

# pretty_element(el, flags) -> str: an element of a data - a word, or
# Bytes(n, value)
FUNC pretty_element
        STACK_CHECK
        ENTER
        mov rbx, rsi
        call pw_with_width
        mov rdi, rax
        PF_COLOR_OF rsi, rbx
        call prettify
        LEAVE
ENDF pretty_element

# setmem_value(val, n) -> value: python's setmem_value - the value of a
# write to n bytes of memory, as it's printed: a number (its low n bytes
# are written), or a list of data of n bytes - bytes of another width are
# the number they make (see memloc.keep_setmem_width)
FUNC setmem_value
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call opcode_of
        cmp eax, OP_BYTES
        jne 2f
        cmp dword ptr [rbx + N_AUX], 3
        jb .Lsv_index
        mov rdi, [rbx + N_DATA + 16]
        call sized
        test eax, eax
        jnz 1f
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, r12
        call py_equal
        test eax, eax
        jnz 1f
        mov rax, [rbx + N_DATA + 16]    # a number
        LEAVE
1:      mov rbx, [rbx + N_DATA + 16]
2:      mov rdi, rbx
        call sized
        test eax, eax
        jz 8f
        mov rdi, rbx
        call width_of
        test rax, rax
        jz 3f
        mov r13, rax
        mov rdi, r12
        mov rsi, (8 << 1) | 1
        call int_mul
        mov rdi, r13
        mov rsi, rax
        call py_equal
        test eax, eax
        jnz 8f
3:      mov rdi, rbx
        mov rsi, r12
        call resize_bytes
        test rax, rax
        jnz 9f
8:      mov rax, rbx
9:      LEAVE
.Lsv_index:
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_pm_index]
        call err_throw
ENDF setmem_value

# fix_widths(trace) -> trace: python's fix_widths - the elements of what
# is bytes, with their width when it isn't a word
FUNC fix_widths
        lea rsi, [rip + fix_widths_f]
        xor edx, edx
        jmp replace_f
ENDF fix_widths

# fix_widths_f(exp, arg): fix_widths' f
FUNC fix_widths_f
        STACK_CHECK
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 32
        .set FW_POS, MATCH_BINDINGS_SIZE        # a single position (the calls'), or 0: byte_elements
        .set FW_VEC, MATCH_BINDINGS_SIZE + 8
        mov rbx, rdi
        call is_tuple
        test eax, eax
        jz .Lfw_asis
        # a write to n bytes of memory: its value as it's printed
        PAT rsi, "('setmem', ('range', 'Any', ':int:n'), ':val')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 1f
        B rdi, 1
        B rsi, 0
        call setmem_value
        mov r12, rax
        mov rdi, rax
        B rsi, 1
        call values_equal
        test eax, eax
        jnz 1f
        mov rdi, [rbx + N_DATA]
        mov rsi, [rbx + N_DATA + 8]
        mov rdx, r12
        call mk3
        jmp .Lfw_ret
1:      mov qword ptr [rsp + FW_POS], 0
        mov rdi, rbx
        call opcode_of
        cmp eax, OP_CALL
        je 2f
        cmp eax, OP_STATICCALL
        je 2f
        cmp eax, OP_CALLCODE
        je 2f
        cmp eax, OP_DELEGATECALL
        jne 3f
2:      # but the selector: it's printed as the function it calls - the
        # last position, when it's the last element
        mov esi, [rbx + N_AUX]
        dec esi
        mov [rsp + FW_POS], rsi
        mov rdi, rbx
        call is_byte_element
        test eax, eax
        jz .Lfw_asis
3:      # any position?
        mov r13d, 1
4:      cmp r13d, [rbx + N_AUX]
        jae .Lfw_asis
        mov rdi, rbx
        mov esi, r13d
        call .Lfw_is_pos
        test eax, eax
        jnz 5f
        inc r13d
        jmp 4b
5:      call vec_new
        mov [rsp + FW_VEC], rax
        mov rdi, rbx
        call opcode_of
        mov r14d, eax                   # (the data's elements go in it)
        xor r13d, r13d
6:      cmp r13d, [rbx + N_AUX]
        jae 8f
        mov r12, [rbx + N_DATA + r13*8]
        mov rdi, rbx
        mov esi, r13d
        call .Lfw_is_pos
        test eax, eax
        jz 7f
        mov rdi, r12
        call pw_with_width
        mov r12, rax
        mov rdi, rax
        call opcode_of
        cmp eax, OP_DATA
        jne 7f
        cmp r14d, OP_DATA
        je 61f
        cmp r14d, OP_SHA3
        je 61f
        cmp r14d, OP_ARR
        jne 7f
61:     # (its elements, in the list it's in)
        mov rdi, [rsp + FW_VEC]
        lea rsi, [r12 + N_DATA + 8]
        mov edx, [r12 + N_AUX]
        dec edx
        call vec_extend
        inc r13d
        jmp 6b
7:      mov rdi, [rsp + FW_VEC]
        mov rsi, r12
        call vec_push
        inc r13d
        jmp 6b
8:      mov rdi, [rsp + FW_VEC]
        call vec_to_tuple
        jmp .Lfw_ret
.Lfw_asis:
        mov rax, rbx
.Lfw_ret:
        add rsp, MATCH_BINDINGS_SIZE + 32
        LEAVE
# a local: eax 1 when esi is one of the positions (fix_widths' frame 8
# bytes up)
.Lfw_is_pos:
        mov rax, [rsp + 8 + FW_POS]
        test rax, rax
        jz 1f
        cmp rax, rsi
        sete al
        movzx eax, al
        ret
1:      jmp is_byte_element
ENDF fix_widths_f

# --- the elements of the data ---

# pm_word(e) -> value: pretty_memory's word - the number of a word of the
# data (Bytes(32, number)), else e
FUNC pm_word
        ENTER
        mov rbx, rdi
        OP_N_CHECK OP_BYTES, 3, 1f
        cmp qword ptr [rbx + N_DATA + 8], (32 << 1) | 1
        jne 1f
        mov rdi, [rbx + N_DATA + 16]
        call is_int
        test eax, eax
        jz 1f
        mov rax, [rbx + N_DATA + 16]
        LEAVE
1:      mov rax, rbx
        LEAVE
ENDF pm_word

# pretty_memory(exp, flags) -> list of str, or a str: python's
# pretty_memory - the elements of a list of data, as they're printed.
# PF_ABI_TEXT (abi_text): it's the data of a return or a revert, where a
# string that's all the data (after a selector) is the ABI-encoded string
# - printed 'text' there, and bytes of text that are all the data
# Bytes(n, 'text'). Elsewhere a string is its bytes, and an ABI-encoded
# one an Array(len=n, data='text'). Python gives a bare string for "mem"
# and for a data of no elements ("empty()"), which its callers iterate:
# a str here (pm_join, pm_list).
FUNC pretty_memory
        STACK_CHECK
        ENTER
        sub rsp, 64
        .set PM_OUT, 0
        .set PM_IDX, 8
        .set PM_FIRST, 16               # first: the first element (after a selector)
        .set PM_SB, 24
        .set PM_END, 32
        .set PM_LEN, 40                 # the length of an ABI-encoded string
        .set PM_SIZE, 48
        mov rbx, rdi
        mov r12, rsi
        call is_none
        test eax, eax
        jz 1f
        xor edi, edi
        xor esi, esi
        call mk_list
        jmp .Lpm_ret
1:      LOADS rax, MEM
        cmp rbx, rax
        jne 2f
        mov rdi, rbx
        PF_COLOR_OF rsi, r12
        or rsi, PF_PARENS
        call prettify
        jmp .Lpm_ret
2:      mov rdi, rbx
        call opcode_of
        cmp eax, OP_DATA
        je 3f
        mov rdi, rbx
        PF_COLOR_OF rsi, r12
        call prettify
        test r12, PF_ABI_TEXT
        jz 21f
        mov rdi, rbx
        mov rsi, rax
        call raw_text
21:     mov rdi, rax
        call mk_list1
        jmp .Lpm_ret
3:      cmp dword ptr [rbx + N_AUX], 1
        jne 4f
        lea rdi, [rip + .Ls_empty_call]
        call str_new_c
        jmp .Lpm_ret
4:      call vec_new
        mov [rsp + PM_OUT], rax
        call sb_new
        mov [rsp + PM_SB], rax
        mov qword ptr [rsp + PM_IDX], 1         # (exp[1:] in python: our idx is 1-based)
.Lpm_loop:
        mov rcx, [rsp + PM_IDX]
        cmp ecx, [rbx + N_AUX]
        jae .Lpm_done
        mov r13, [rbx + N_DATA + rcx*8]         # el
        cmp rcx, 1
        jne 5f
        # a selector: of an error, of an event... - its 8 digits when it's
        # not known (a word that small is printed in decimal)
        PAT rsi, "('bytes', 4, ':int:selector')"
        mov rdi, r13
        lea rdx, [rsp + PM_LEN]         # (one binding)
        call pat_match
        test eax, eax
        jz 5f
        mov rdi, [rsp + PM_LEN]
        mov esi, 32
        call int_mod_2exp
        mov r14, rax
        mov rdi, rax
        sar rdi, 1
        mov rsi, r12
        call known_fname
        test rax, rax
        jnz 41f
        mov rdi, r14
        sar rdi, 1
        call selector_hex
41:     mov rdi, [rsp + PM_OUT]
        mov rsi, rax
        call vec_push
        inc qword ptr [rsp + PM_IDX]
        jmp .Lpm_loop
5:      # first = idx == 0 or (idx == 1 and exp[0] is 4 bytes)
        mov qword ptr [rsp + PM_FIRST], 1
        mov rcx, [rsp + PM_IDX]
        cmp rcx, 1
        je 6f
        mov qword ptr [rsp + PM_FIRST], 0
        cmp rcx, 2
        jne 6f
        PAT rsi, "('bytes', 4, 'Any')"
        mov rdi, [rbx + N_DATA + 8]
        call pat_match_nobind
        mov ecx, eax
        mov [rsp + PM_FIRST], rcx
6:      # all the data is an ABI-encoded string (after a selector)
        test r12, PF_ABI_TEXT
        jz 7f
        cmp qword ptr [rsp + PM_FIRST], 0
        je 7f
        mov rcx, [rsp + PM_IDX]
        inc ecx
        cmp ecx, [rbx + N_AUX]
        jne 7f
        mov rdi, r13
        call arr_text
        test rax, rax
        jz 7f
        mov rdi, [rsp + PM_OUT]
        mov rsi, rax
        call vec_push
        inc qword ptr [rsp + PM_IDX]
        jmp .Lpm_loop
7:      # an ABI-encoded string: its offset, its length, the words of its
        # bytes, padded with zeroes - when it's all the data is (after a
        # selector): return 'text', revert with Error(string), 'text' (an
        # Array of it elsewhere). A string elsewhere is its bytes.
        cmp qword ptr [rsp + PM_FIRST], 0
        je .Lpm_text
        mov rdi, r13
        call pm_word
        cmp rax, (32 << 1) | 1
        jne .Lpm_text
        mov rcx, [rsp + PM_IDX]
        inc ecx
        cmp ecx, [rbx + N_AUX]
        jae .Lpm_text
        mov rdi, [rbx + N_DATA + rcx*8]
        call pm_word
        mov r14, rax                    # length
        mov rdi, rax
        call is_int
        test eax, eax
        jz .Lpm_text
        # size = 32 * ((length + 31) // 32): nothing for a length below 1;
        # a length past 2^40 is past any data (its bytes are made all the
        # same, as python does)
        mov rdi, r14
        call int_sign
        cmp eax, 1
        jne .Lpm_text
        mov rax, -1
        mov [rsp + PM_LEN], rax
        mov [rsp + PM_SIZE], rax
        test r14b, 1
        jz 71f
        mov rax, r14
        sar rax, 1
        mov rcx, 1
        shl rcx, 40
        cmp rax, rcx
        jae 71f
        mov [rsp + PM_LEN], rax
        add rax, 31
        and rax, -32
        mov [rsp + PM_SIZE], rax
71:
        # its bytes, in as many parts as they come
        mov rdi, [rsp + PM_SB]
        call sb_reset
        mov rax, [rsp + PM_IDX]
        add rax, 2
        mov [rsp + PM_END], rax
8:      mov rcx, [rsp + PM_END]
        cmp ecx, [rbx + N_AUX]
        jae 9f
        mov rax, [rsp + PM_SB]
        mov rax, [rax + SB_LEN]
        cmp rax, [rsp + PM_SIZE]
        jae 9f
        mov rdi, [rsp + PM_SB]
        mov rsi, [rbx + N_DATA + rcx*8]
        call data_bytes_into
        test eax, eax
        jz 9f
        inc qword ptr [rsp + PM_END]
        jmp 8b
9:      mov rax, [rsp + PM_SB]
        mov rax, [rax + SB_LEN]
        cmp rax, [rsp + PM_SIZE]
        jne .Lpm_text
        mov rcx, [rsp + PM_END]
        cmp ecx, [rbx + N_AUX]
        jne .Lpm_text
        mov rdi, [rsp + PM_SB]
        mov rsi, [rsp + PM_LEN]
        call sb_any_nonzero
        test eax, eax
        jnz .Lpm_text
        mov rax, [rsp + PM_SB]
        mov rdi, [rax + SB_BUF]
        mov rsi, [rsp + PM_LEN]
        xor edx, edx
        call pretty_text
        test rax, rax
        jz .Lpm_text
        test r12, PF_ABI_TEXT
        jnz 10f
        # Array(len={length}, data={text})
        mov r14, rax
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_array_len]
        call sb_append_c
        mov rdi, r13
        mov rsi, [rsp + PM_LEN]
        call sb_append_u64
        mov rdi, r13
        lea rsi, [rip + .Ls_data_eq]
        call sb_append_c
        mov rdi, r13
        mov rsi, r14
        call sb_append_str
        mov rdi, r13
        mov esi, ')'
        call sb_append_char
        mov rdi, r13
        call sb_finish
10:     mov rdi, [rsp + PM_OUT]
        mov rsi, rax
        call vec_push
        mov rax, [rsp + PM_END]
        mov [rsp + PM_IDX], rax
        jmp .Lpm_loop
.Lpm_text:
        # bytes that are text, as parts of the data (hashed, say)
        mov rdi, [rsp + PM_SB]
        call sb_reset
        mov rax, [rsp + PM_IDX]
        mov [rsp + PM_END], rax
11:     mov rcx, [rsp + PM_END]
        cmp ecx, [rbx + N_AUX]
        jae 12f
        mov rdi, [rsp + PM_SB]
        mov rsi, [rbx + N_DATA + rcx*8]
        call data_bytes_into
        test eax, eax
        jz 12f
        inc qword ptr [rsp + PM_END]
        jmp 11b
12:     mov rax, [rsp + PM_SB]
        cmp qword ptr [rax + SB_LEN], 4
        jb .Lpm_element
        mov rdi, [rax + SB_BUF]
        mov rsi, [rax + SB_LEN]
        xor edx, edx
        call pretty_text
        test rax, rax
        jz .Lpm_element
        test r12, PF_ABI_TEXT
        jz 13f
        cmp qword ptr [rsp + PM_FIRST], 0
        je 13f
        mov rcx, [rsp + PM_END]
        cmp ecx, [rbx + N_AUX]
        jne 13f
        # all the data: its bytes, not the ABI-encoded string
        mov r14, rax
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_bytes_]
        call sb_append_c
        mov rax, [rsp + PM_SB]
        mov rdi, r13
        mov rsi, [rax + SB_LEN]
        call sb_append_u64
        mov rdi, r13
        lea rsi, [rip + .Ls_comma_sp]
        call sb_append_c
        mov rdi, r13
        mov rsi, r14
        call sb_append_str
        mov rdi, r13
        mov esi, ')'
        call sb_append_char
        mov rdi, r13
        call sb_finish
13:     mov rdi, [rsp + PM_OUT]
        mov rsi, rax
        call vec_push
        mov rax, [rsp + PM_END]
        mov [rsp + PM_IDX], rax
        jmp .Lpm_loop
.Lpm_element:
        mov rdi, r13
        mov rsi, r12
        call pretty_element
        test r12, PF_ABI_TEXT
        jz 14f
        cmp qword ptr [rsp + PM_FIRST], 0
        je 14f
        mov rcx, [rsp + PM_IDX]
        inc ecx
        cmp ecx, [rbx + N_AUX]
        jne 14f
        mov rdi, r13
        mov rsi, rax
        call raw_text
14:     mov rdi, [rsp + PM_OUT]
        mov rsi, rax
        call vec_push
        inc qword ptr [rsp + PM_IDX]
        jmp .Lpm_loop
.Lpm_done:
        mov rdi, [rsp + PM_SB]
        call sb_free
        mov rdi, [rsp + PM_OUT]
        call vec_to_list
.Lpm_ret:
        add rsp, 64
        LEAVE
ENDF pretty_memory

# selector_hex(sel) -> str: f"{sel:#010x}" (sel below 2^32)
FUNC selector_hex
        ENTER
        mov rbx, rdi
        call sb_new
        mov r12, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_0x]
        call sb_append_c
        mov r13d, 28
1:      mov rax, rbx
        mov ecx, r13d
        shr rax, cl
        and eax, 15
        lea rcx, [rip + .Lhex_chars]
        movzx esi, byte ptr [rcx + rax]
        mov rdi, r12
        call sb_append_char
        sub r13d, 4
        jns 1b
        mov rdi, r12
        call sb_finish
        LEAVE
ENDF selector_hex

        .section .rodata
.Lhex_chars: .ascii "0123456789abcdef"
        .text

# --- the calls ---

# known_fname(sel, flags) -> str or 0: python's known_fname - the function
# (or error...) of the selector sel, a number of 4 bytes, as it's printed,
# when the database knows it
FUNC known_fname
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov rdi, rbx
        call selector_hex               # "0x%08x" % sel
        mov rdi, rax
        mov rsi, r12
        call find_sig
        test rax, rax
        jz 9f
        mov r13, rax
        # a name of the database that's no name: nor are its params
        mov rdi, rax
        call clean_color
        mov rdi, rax
        call is_unknown_name
        test eax, eax
        jnz 9f
        # the names the database doesn't have are no names of the callee
        mov rdi, r13
        call drop_param_names
        LEAVE
9:      xor eax, eax
        LEAVE
ENDF known_fname

# is_unknown_name(str) -> eax: python's re.match(r"unknown_?([0-9a-f]{8})?\(", s)
FUNC is_unknown_name
        ENTER
        mov rbx, rdi
        lea rsi, [rip + .Ls_unknown]
        call str_startswith_c
        test eax, eax
        jz 9f
        lea r12, [rbx + N_DATA + 4 + 7]
        mov ecx, [rbx + N_DATA]
        lea r13, [rbx + N_DATA + 4 + rcx]       # the end
        cmp r12, r13
        jae 9f
        cmp byte ptr [r12], '_'
        jne 1f
        lea rdi, [r12 + 1]
        mov rsi, r13
        call .Liu_rest
        test eax, eax
        jnz 8f
1:      mov rdi, r12
        mov rsi, r13
        call .Liu_rest
        LEAVE
8:      mov eax, 1
        LEAVE
9:      xor eax, eax
        LEAVE
# a local: eax 1 when [rdi, rsi) starts with "(" or 8 lowercase hex digits
# and "("
.Liu_rest:
        cmp rdi, rsi
        jae 3f
        cmp byte ptr [rdi], '('
        je 2f
        lea rax, [rdi + 9]
        cmp rax, rsi
        ja 3f
        xor ecx, ecx
1:      movzx eax, byte ptr [rdi + rcx]
        sub eax, '0'
        cmp eax, 9
        jbe 11f
        sub eax, 'a' - '0'
        cmp eax, 5
        ja 3f
11:     inc ecx
        cmp ecx, 8
        jb 1b
        cmp byte ptr [rdi + 8], '('
        jne 3f
2:      mov eax, 1
        ret
3:      xor eax, eax
        ret
ENDF is_unknown_name

# drop_param_names(str) -> str: python's re.sub(r" _param\d+(?=[,)])", "",
# name)
FUNC drop_param_names
        ENTER
        mov rbx, rdi
        call sb_new
        mov r12, rax
        lea r13, [rbx + N_DATA + 4]
        mov ecx, [rbx + N_DATA]
        lea r14, [r13 + rcx]            # the end
1:      cmp r13, r14
        jae 8f
        # " _param" + digits, then "," or ")"?
        mov rdi, r13
        lea rsi, [rip + .Ls_param_]
        mov edx, 7
        mov rax, r14
        sub rax, r13
        cmp rax, 9
        jb 5f
        call strncmp@PLT
        test eax, eax
        jnz 5f
        lea rcx, [r13 + 7]
        mov rdx, rcx
2:      cmp rdx, r14
        jae 5f
        movzx eax, byte ptr [rdx]
        sub eax, '0'
        cmp eax, 9
        ja 3f
        inc rdx
        jmp 2b
3:      cmp rdx, rcx
        je 5f                           # (no digit)
        cmp byte ptr [rdx], ','
        je 4f
        cmp byte ptr [rdx], ')'
        jne 5f
4:      mov r13, rdx                    # (dropped)
        jmp 1b
5:      mov rdi, r12
        movzx esi, byte ptr [r13]
        call sb_append_char
        inc r13
        jmp 1b
8:      mov rdi, r12
        call sb_finish
        LEAVE
ENDF drop_param_names

# split_selector(fname, fparams) -> rax: fname, rdx: fparams - python's
# split_selector: the selector and the params of a call (see
# vm.VM.call_data): a call whose data is all in its params, when they start
# with 4 bytes that are a number, has them for selector and the rest for
# params
FUNC split_selector
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call is_none
        test eax, eax
        jz 9f
        mov rdi, r12
        call is_bytes4_int
        test eax, eax
        jz 1f
        mov rax, r12
        xor edx, edx                    # (None)
        LEAVE
1:      mov rdi, r12
        call opcode_of
        cmp eax, OP_DATA
        jne 9f
        cmp dword ptr [r12 + N_AUX], 2
        jb 9f
        mov rdi, [r12 + N_DATA + 8]
        call is_bytes4_int
        test eax, eax
        jz 9f
        # rest = fparams[2:]: ("data",) + rest if it's more than one, else
        # the one, else None
        mov ecx, [r12 + N_AUX]
        sub ecx, 2
        cmp ecx, 1
        ja 3f
        xor r13d, r13d
        test ecx, ecx
        jz 2f
        mov r13, [r12 + N_DATA + 16]
2:      mov rax, [r12 + N_DATA + 8]
        mov rdx, r13
        LEAVE
3:      mov rdi, r12
        mov esi, 2
        call data_of_rest
        mov rdx, rax
        mov rax, [r12 + N_DATA + 8]
        LEAVE
9:      mov rax, rbx
        mov rdx, r12
        LEAVE
ENDF split_selector

# is_bytes4_int(v) -> eax: v ~ ("bytes", 4, :int:)
FUNC is_bytes4_int
        ENTER
        mov rbx, rdi
        OP_N_CHECK OP_BYTES, 3, 9f
        cmp qword ptr [rbx + N_DATA + 8], (4 << 1) | 1
        jne 9f
        mov rdi, [rbx + N_DATA + 16]
        call is_int
        LEAVE
9:      xor eax, eax
        LEAVE
ENDF is_bytes4_int

# callee_name(fname, flags) -> str or 0: python's callee_name - what a
# call calls, printed after its address (`x.f(...)`): the function of its
# selector when that's known, `unknown1234abcd(?)` when it isn't (no
# params made up), the bytes of memory it is (`x.mem[a len 4]`) - 0 when
# it's none of these (a selector computed: printed as `funct ...`), or
# when the call has no data
FUNC callee_name
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call is_bytes4_int
        test eax, eax
        jz 1f
        mov rbx, [rbx + N_DATA + 16]
1:      mov rdi, rbx
        call is_int
        test eax, eax
        jz 3f
        # 0 <= fname < 2**32
        test bl, 1
        jz 3f
        mov rax, rbx
        sar rax, 1
        js 3f
        mov rcx, 1
        shl rcx, 32
        cmp rax, rcx
        jae 3f
        mov r13, rax
        mov rdi, rax
        mov rsi, r12
        call known_fname
        test rax, rax
        jnz 9f
        # f"unknown{fname:08x}(?)"
        mov rdi, r13
        call selector_hex
        mov r14, rax
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_unknown]
        call sb_append_c
        mov rdi, r13
        lea rsi, [r14 + N_DATA + 4 + 2]
        call sb_append_c
        mov rdi, r13
        lea rsi, [rip + .Ls_q_end]
        call sb_append_c
        mov rdi, r13
        call sb_finish
        LEAVE
3:      mov rdi, rbx
        call opcode_of
        cmp eax, OP_MEM
        jne 8f
        mov rdi, rbx
        PF_COLOR_OF rsi, r12
        or rsi, PF_PARENS
        call prettify
        LEAVE
8:      xor eax, eax
9:      LEAVE
ENDF callee_name

# --- the places of the storage ---

# pretty_loc(loc, flags) -> str: python's pretty_loc - a place of the
# storage (see storage.py): name[key].field_n, stor[slot]
FUNC pretty_loc
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov rdi, rbx
        call is_seq
        test eax, eax
        jnz 1f
        mov rdi, rbx
        call is_str
        test eax, eax
        jz .Lpl_type
        cmp dword ptr [rbx + N_DATA], 0
        je .Lpl_index
        jmp .Lpl_str                    # (its first character: no place)
1:      cmp dword ptr [rbx + N_AUX], 0
        je .Lpl_index
        mov rdi, [rbx + N_DATA]
        call str_id
        cmp eax, OP_SV
        je .Lpl_sv
        cmp eax, OP_SI
        je .Lpl_si
        cmp eax, OP_SL
        je .Lpl_sl
        cmp eax, OP_SBL
        je .Lpl_sl
        cmp eax, OP_SF
        je .Lpl_sf
        cmp eax, OP_SR
        je .Lpl_sr
.Lpl_str:
        mov rdi, rbx
        call value_str
        LEAVE
.Lpl_sv:
        cmp dword ptr [rbx + N_AUX], 2
        jb .Lpl_index
        mov rdi, [rbx + N_DATA + 8]
        call value_str
        mov rdi, rax
        lea rsi, [rip + C_GREEN]
        mov rdx, r12
        call colorize
        LEAVE
.Lpl_si:
        cmp dword ptr [rbx + N_AUX], 3
        jb .Lpl_index
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, r12
        call pretty_loc
        mov r13, rax
        call sb_new
        mov r14, rax
        mov rdi, rax
        mov rsi, r13
        call sb_append_str
        mov rdi, r14
        lea rsi, [rip + .Ls_lbracket]
        lea rdx, [rip + C_GREEN]
        mov rcx, r12
        call sb_append_col_c
        mov rdi, r14
        mov rsi, [rbx + N_DATA + 16]
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        mov rdi, r14
        lea rsi, [rip + .Ls_rbracket]
        lea rdx, [rip + C_GREEN]
        mov rcx, r12
        call sb_append_col_c
        mov rdi, r14
        call sb_finish
        LEAVE
.Lpl_sl:
        cmp dword ptr [rbx + N_AUX], 2
        jb .Lpl_index
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, r12
        call pretty_loc
        mov r13, rax
        call sb_new
        mov r14, rax
        mov rdi, rax
        mov rsi, r13
        call sb_append_str
        mov rdi, r14
        lea rsi, [rip + .Ls_dot_length]
        lea rdx, [rip + C_GREEN]
        mov rcx, r12
        call sb_append_col_c
        mov rdi, r14
        call sb_finish
        LEAVE
.Lpl_sf:
        cmp dword ptr [rbx + N_AUX], 3
        jb .Lpl_index
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, r12
        call pretty_loc
        mov r13, rax
        call sb_new
        mov r14, rax
        mov rdi, rax
        mov rsi, r13
        call sb_append_str
        mov rdi, r14
        lea rsi, [rip + .Ls_dot_field_]
        lea rdx, [rip + C_GREEN]
        mov rcx, r12
        call sb_append_col_c
        mov rdi, r14
        mov rsi, [rbx + N_DATA + 16]
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        mov rdi, r14
        call sb_finish
        LEAVE
.Lpl_sr:
        cmp dword ptr [rbx + N_AUX], 2
        jb .Lpl_index
        call sb_new
        mov r14, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_stor_]
        lea rdx, [rip + C_GREEN]
        mov rcx, r12
        call sb_append_col_c
        mov rdi, r14
        mov rsi, [rbx + N_DATA + 8]
        PF_COLOR_OF rdx, r12
        call sb_append_pret
        mov rdi, r14
        lea rsi, [rip + .Ls_rbracket]
        lea rdx, [rip + C_GREEN]
        mov rcx, r12
        call sb_append_col_c
        mov rdi, r14
        call sb_finish
        LEAVE
.Lpl_index:
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_pm_index]
        call err_throw
.Lpl_type:
        mov edi, E_TYPE
        lea rsi, [rip + .Ls_loc_type]
        call err_throw
ENDF pretty_loc

        .section .note.GNU-stack,"",@progbits
