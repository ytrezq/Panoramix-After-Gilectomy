# Function signatures and parameter names, as the printer needs them
# (utils/signatures.py, Loader.find_sig, and masks.py's type names).
#
# An abi entry is a tuple (name, inputs) where inputs is a list of
# (type, name) tuples, or NIL when the signature is unknown (python: no
# "inputs" key). sig_db_lookup finds the entry of a selector in the
# signature database; the current function's entry is on the context.

.include "defs.inc"

        .section .rodata
.Ls_bool:       .asciz "bool"
.Ls_uint8:      .asciz "uint8"
.Ls_uint16:     .asciz "uint16"
.Ls_uint32:     .asciz "uint32"
.Ls_uint64:     .asciz "uint64"
.Ls_uint128:    .asciz "uint128"
.Ls_address:    .asciz "address"
.Ls_uint256:    .asciz "uint256"
.Ls_big:        .asciz "big"
.Ls_dot_length: .asciz ".length"
.Ls_qqq:        .asciz "???"
.Ls_unknown:    .asciz "unknown"
.Ls_lparen:     .asciz "("
.Ls_rparen:     .asciz ")"
.Ls_comma_sp:   .asciz ", "
.Ls_space:      .asciz " "
.Ls_lbracket:   .asciz "["
.Ls_rbracket:   .asciz "]"

        # mask sizes and their type names, in python's lookup order
        .section .data.rel.ro
        .align 8
mask_types:
        .quad 1,   .Ls_bool
        .quad 8,   .Ls_uint8
        .quad 16,  .Ls_uint16
        .quad 32,  .Ls_uint32
        .quad 64,  .Ls_uint64
        .quad 128, .Ls_uint128
        .quad 160, .Ls_address
        .quad 256, .Ls_uint256
        .quad 0, 0

        # type names and their mask sizes (type_to_mask)
type_masks:
        .quad .Ls_bool, 1
        .quad .Ls_uint8, 8
        .quad .Ls_uint16, 16
        .quad .Ls_uint32, 32
        .quad .Ls_uint64, 64
        .quad .Lt_int8, 8
        .quad .Lt_bytes1, 1
        .quad .Lt_int16, 16
        .quad .Lt_bytes2, 16
        .quad .Lt_int32, 32
        .quad .Lt_bytes4, 32
        .quad .Lt_int64, 64
        .quad .Lt_bytes8, 64
        .quad .Lt_int128, 128
        .quad .Ls_uint128, 128
        .quad .Lt_bytes16, 128
        .quad .Ls_address, 160
        .quad .Ls_uint256, 256
        .quad .Lt_bytes32, 256
        .quad .Lt_int256, 256
        .quad .Lt_int, 256
        .quad .Lt_uint, 256
        .quad 0, 0
        .section .rodata
.Lt_int8:    .asciz "int8"
.Lt_bytes1:  .asciz "bytes1"
.Lt_int16:   .asciz "int16"
.Lt_bytes2:  .asciz "bytes2"
.Lt_int32:   .asciz "int32"
.Lt_bytes4:  .asciz "bytes4"
.Lt_int64:   .asciz "int64"
.Lt_bytes8:  .asciz "bytes8"
.Lt_int128:  .asciz "int128"
.Lt_bytes16: .asciz "bytes16"
.Lt_bytes32: .asciz "bytes32"
.Lt_int256:  .asciz "int256"
.Lt_int:     .asciz "int"
.Lt_uint:    .asciz "uint"

        .text

.macro B reg, n
        mov \reg, [rsp + 8*(\n)]
.endm

# mask_to_type(num, force) -> value: the type name of a mask size (a
# string), num itself when it isn't an int, 0 (None) when unknown - unless
# force, which gives "big<num>" above 256 and the smallest type that fits
# otherwise
FUNC mask_to_type
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call is_int
        test eax, eax
        jz .Lmt_asis
        lea r13, [rip + mask_types]
1:      mov rax, [r13]
        test rax, rax
        jz 2f
        TAG rax
        cmp rax, rbx
        je .Lmt_found
        add r13, 16
        jmp 1b
2:      test r12, r12
        jz .Lmt_none
        mov rdi, rbx
        mov rsi, 256
        TAG rsi
        call int_cmp
        cmp eax, 1
        jne 3f
        # "big" + str(num)
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_big]
        call sb_append_c
        mov rdi, r13
        mov rsi, rbx
        mov edx, 10
        call sb_append_int
        mov rdi, r13
        call sb_finish
        LEAVE
3:      lea r13, [rip + mask_types]
4:      mov rax, [r13]
        test rax, rax
        jz .Lmt_assert
        TAG rax
        mov rdi, rax
        mov rsi, rbx
        call int_cmp
        cmp eax, 1
        je .Lmt_found
        add r13, 16
        jmp 4b
.Lmt_found:
        mov rdi, [r13 + 8]
        call str_intern_c
        LEAVE
.Lmt_asis:
        mov rax, rbx
        LEAVE
.Lmt_none:
        xor eax, eax
        LEAVE
.Lmt_assert:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_mt_assert]
        call err_throw
ENDF mask_to_type

        .section .rodata
.Ls_mt_assert: .asciz "mask_to_type: no type fits"
        .text

# type_to_mask(type_str) -> value: the mask size of a type name, or 0
FUNC type_to_mask
        ENTER
        mov rbx, rdi
        lea r12, [rip + type_masks]
1:      mov rsi, [r12]
        test rsi, rsi
        jz 2f
        mov rdi, rbx
        call str_eq_c
        test eax, eax
        jnz 3f
        add r12, 16
        jmp 1b
2:      xor eax, eax
        LEAVE
3:      mov rax, [r12 + 8]
        TAG rax
        LEAVE
ENDF type_to_mask

# hex_digits(sb, v): the hex digits of an integer, without 0x nor sign
FUNC hex_digits
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call sb_new
        mov r13, rax
        mov rdi, rax
        mov rsi, r12
        mov edx, 16
        call sb_append_int
        mov rsi, [r13 + SB_BUF]
        cmp byte ptr [rsi], '-'
        jne 1f
        inc rsi
1:      add rsi, 2                      # past "0x"
        mov rdi, rbx
        call sb_append_c
        mov rdi, r13
        call sb_free
        LEAVE
ENDF hex_digits

# padded_hex(v, n) -> str: helpers.padded_hex - "0x" and the hex digits
# padded with zeros to n of them, or n question marks when there are more
FUNC padded_hex
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        call sb_new
        mov r13, rax
        mov rdi, rax
        mov rsi, rbx
        call hex_digits
        mov r14, [r13 + SB_LEN]         # the digits
        cmp r14, r12
        ja 2f
        call sb_new
        mov [rsp], rax
        mov rdi, rax
        lea rsi, [rip + .Ls_0x]
        call sb_append_c
        mov rcx, r12
        sub rcx, r14
1:      test rcx, rcx
        jz 3f
        push rcx
        push rcx
        mov rdi, [rsp + 16]
        mov esi, '0'
        call sb_append_char
        pop rcx
        pop rcx
        dec rcx
        jmp 1b
3:      mov rdi, [rsp]
        mov rsi, [r13 + SB_BUF]
        mov rdx, r14
        call sb_append
        mov rdi, r13
        call sb_free
        mov rdi, [rsp]
        call sb_finish
        add rsp, 16
        LEAVE
2:      mov rdi, r13
        call sb_reset
4:      test r12, r12
        jz 5f
        mov rdi, r13
        mov esi, '?'
        call sb_append_char
        dec r12
        jmp 4b
5:      mov rdi, r13
        call sb_finish
        add rsp, 16
        LEAVE
ENDF padded_hex

        .section .rodata
.Ls_0x: .asciz "0x"
        .text

# --- the signature database ---

# sig_db_lookup(selector) -> rax: the abi entry (name, inputs) of a
# selector (an integer below 2^32), or 0. The database comes later: without
# one, every selector is unknown.
FUNC sig_db_lookup
        mov rax, [rip + sig_db_hook]
        test rax, rax
        jz 1f
        jmp rax
1:      ENTER
        mov rbx, rdi
        call sigdb_load                 # (once: the state is kept)
        test eax, eax
        jz 2f
        mov rdi, rbx
        call [rip + sig_db_hook]
        LEAVE
2:      xor eax, eax
        LEAVE
ENDF sig_db_lookup

        .section .bss
        .align 8
        .globl sig_db_hook
        .hidden sig_db_hook
sig_db_hook: .quad 0                    # a function(selector) -> entry, once there is a database
        .text

# sig_of_hex(sigstr) -> rax: python's int(sigstr, 16) for the prefixes of
# a hex number that find_sig gets, or -1 when it isn't one that a selector
# could be (a sign, question marks, more than 8 digits)
FUNC sig_of_hex
        mov ecx, [rdi + N_DATA]
        lea rsi, [rdi + N_DATA + 4]
        cmp ecx, 2
        jbe 4f
        cmp word ptr [rsi], 0x7830      # "0x"
        jne 4f
        add rsi, 2
        sub ecx, 2
        cmp ecx, 8
        ja 4f
        xor eax, eax
1:      test ecx, ecx
        jz 3f
        movzx edx, byte ptr [rsi]
        sub edx, '0'
        cmp edx, 9
        jbe 2f
        sub edx, 'a' - '0'
        cmp edx, 5
        ja 4f
        add edx, 10
2:      shl rax, 4
        or rax, rdx
        inc rsi
        dec ecx
        jmp 1b
3:      ret
4:      mov rax, -1
        ret
ENDF sig_of_hex

# find_sig(sigstr, flags) -> str or 0: Loader.find_sig - the signature of
# a selector given as the first 10 characters of a hex number, formatted as
# "name(type name, type name)", the types gray when PF_COLOR
FUNC find_sig
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        cmp dword ptr [rbx + N_DATA], 8
        jb .Lfs_none
        call sig_of_hex
        cmp rax, -1
        je .Lfs_none
        mov rdi, rax
        call sig_db_lookup
        test rax, rax
        jz .Lfs_none
        mov r13, rax
        cmp qword ptr [r13 + N_DATA + 8], 0
        je .Lfs_assert                  # assert "inputs" in a
        call sb_new
        mov r14, rax
        mov rdi, rax
        mov rsi, [r13 + N_DATA]
        call sb_append_str
        mov rdi, r14
        mov esi, '('
        call sb_append_char
        mov r13, [r13 + N_DATA + 8]     # the inputs
        mov qword ptr [rsp], 0
1:      mov rcx, [rsp]
        cmp ecx, [r13 + N_AUX]
        jae 2f
        test ecx, ecx
        jz 3f
        mov rdi, r14
        lea rsi, [rip + .Ls_comma_sp]
        call sb_append_c
3:      mov rcx, [rsp]
        mov rbx, [r13 + N_DATA + rcx*8]
        mov rdi, r14
        mov rsi, [rbx + N_DATA]
        lea rdx, [rip + C_GRAY]
        mov rcx, r12
        call sb_append_col
        mov rdi, r14
        mov esi, ' '
        call sb_append_char
        mov rsi, [rbx + N_DATA + 8]
        cmp dword ptr [rsi + N_DATA], 0
        je 4f
        mov rdi, r14
        call sb_append_str
        inc qword ptr [rsp]
        jmp 1b
4:      # an unnamed input: _param<i+1>, as signatures.fix_input_names
        mov rdi, r14
        lea rsi, [rip + .Ls_param]
        call sb_append_c
        mov rdi, r14
        mov rsi, [rsp]
        lea rsi, [rsi*2 + 3]
        mov edx, 10
        call sb_append_int
        inc qword ptr [rsp]
        jmp 1b
2:      mov rdi, r14
        mov esi, ')'
        call sb_append_char
        mov rdi, r14
        call sb_finish
        add rsp, 16
        LEAVE
.Lfs_none:
        xor eax, eax
        add rsp, 16
        LEAVE
.Lfs_assert:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_fs_assert]
        call err_throw
ENDF find_sig

        .section .rodata
.Ls_fs_assert: .asciz "find_sig: a signature without inputs"
.Ls_param:     .asciz "_param"
        .text

# try_fname(v, flags) -> str or 0: prettify's try_fname - the signature of
# an integer that looks like a selector (as its top 8 hex digits, as a
# 32-byte word, or as it is)
FUNC try_fname
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        call sb_new
        mov r13, rax
        mov rdi, rax
        mov rsi, rbx
        mov edx, 16
        call sb_append_int
        mov r14, [r13 + SB_LEN]         # len(hex(v))
        mov rdi, r13
        call sb_finish
        mov rdi, rax
        xor esi, esi
        mov edx, 10
        call str_slice
        mov rdi, rax
        mov rsi, r12
        call find_sig
        test rax, rax
        jnz 1f
        cmp r14, 63
        jb 2f
        mov rdi, rbx
        mov esi, 64
        call padded_hex
        mov rdi, rax
        xor esi, esi
        mov edx, 10
        call str_slice
        mov rdi, rax
        mov rsi, r12
        call find_sig
        test rax, rax
        jnz 1f
2:      cmp r14, 8
        jb 3f
        mov rdi, rbx
        mov esi, 8
        call padded_hex
        mov rdi, rax
        xor esi, esi
        mov edx, 10
        call str_slice
        mov rdi, rax
        mov rsi, r12
        call find_sig
1:      add rsp, 16
        LEAVE
3:      xor eax, eax
        add rsp, 16
        LEAVE
ENDF try_fname

# --- the parameters of the function being printed ---

# get_param_name(cd, flags) -> value: signatures.get_param_name - the name
# of a calldata parameter (a green string), or the ('cd', loc) itself when
# there is no name for it
FUNC get_param_name
        STACK_CHECK
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 16
        .set GP_INPUTS, MATCH_BINDINGS_SIZE
        mov rbx, rdi
        mov r12, rsi
        mov rax, [r15 + CTX_FUNC]
        test rax, rax
        jz .Lgp_cd
        mov rax, [rax + FN_INPUTS]
        test rax, rax
        jz .Lgp_cd
        mov [rsp + GP_INPUTS], rax
        mov r13, [rbx + N_DATA + 8]     # loc
        mov rdi, r13
        call is_int
        test eax, eax
        jnz .Lgp_int
        mov rdi, rbx
        call cleanup_mul_1
        mov rbx, rax
        PAT rsi, "('add', 4, ('param', ':point_loc'))"
        mov rdi, r13
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 1f
        B rdi, 0
        jmp .Lgp_length
1:      PAT rsi, "('add', 4, ('cd', ':point_loc'))"
        mov rdi, r13
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 2f
        B rsi, 0
        LOADS rdi, CD
        call mk2
        mov rdi, rax
        xor esi, esi                    # (the inner name isn't colored)
        call get_param_name
        mov rdi, rax
        call value_str                  # str(...)
        mov rdi, rax
.Lgp_length:
        # colorize(name + ".length", GREEN)
        mov r13, rdi
        call sb_new
        mov r14, rax
        mov rdi, rax
        mov rsi, r13
        call sb_append_str
        mov rdi, r14
        lea rsi, [rip + .Ls_dot_length]
        call sb_append_c
        mov rdi, r14
        call sb_finish
        mov rdi, rax
        lea rsi, [rip + C_GREEN]
        mov rdx, r12
        call colorize
        add rsp, MATCH_BINDINGS_SIZE + 16
        LEAVE
2:      PAT rsi, "('add', ':int:offset', ('cd', ':point_loc'))"
        mov rdi, r13
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz .Lgp_cd
        B rsi, 1
        LOADS rdi, CD
        call mk2
        mov rdi, rax
        xor esi, esi
        call get_param_name
        mov rdi, rax
        call value_str
        mov r13, rax
        # name + "[" + (offset - 36) // 32 + "]"
        call sb_new
        mov r14, rax
        mov rdi, rax
        mov rsi, r13
        call sb_append_str
        mov rdi, r14
        mov esi, '['
        call sb_append_char
        B rdi, 0
        mov rsi, 36
        TAG rsi
        call int_sub
        mov rdi, rax
        mov rsi, 32
        TAG rsi
        call int_floordiv
        mov rdi, r14
        mov rsi, rax
        mov edx, 10
        call sb_append_int
        mov rdi, r14
        mov esi, ']'
        call sb_append_char
        mov rdi, r14
        call sb_finish
        mov rdi, rax
        lea rsi, [rip + C_GREEN]
        mov rdx, r12
        call colorize
        add rsp, MATCH_BINDINGS_SIZE + 16
        LEAVE
.Lgp_int:
        # (loc - 4) % 32 must be 0, and the parameter must exist
        mov rdi, r13
        mov rsi, 4
        TAG rsi
        call int_sub
        mov r14, rax
        mov rdi, rax
        mov rsi, 32
        TAG rsi
        call int_mod
        cmp rax, 1                      # tagged 0
        jne .Lgp_cd
        mov rdi, r14
        mov rsi, 32
        TAG rsi
        call int_floordiv
        mov rdi, rax
        call int_to_i64
        mov rcx, [rsp + GP_INPUTS]
        mov edx, [rcx + N_AUX]
        cmp rax, rdx
        jge .Lgp_cd
        test rax, rax
        jns 4f
        add rax, rdx                    # (python indexes from the end)
        js .Lgp_index
4:      mov rax, [rcx + N_DATA + rax*8]
        mov rdi, [rax + N_DATA + 8]     # the name
        lea rsi, [rip + C_GREEN]
        mov rdx, r12
        call colorize
        add rsp, MATCH_BINDINGS_SIZE + 16
        LEAVE
.Lgp_cd:
        mov rax, rbx
        add rsp, MATCH_BINDINGS_SIZE + 16
        LEAVE
.Lgp_index:
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_gp_index]
        call err_throw
ENDF get_param_name

        .section .rodata
.Ls_gp_index: .asciz "get_param_name: no such parameter"
        .text

# value_str(v) -> str: python's str() of a value - the string itself, the
# repr of anything else
FUNC value_str
        ENTER
        mov rbx, rdi
        call is_str
        test eax, eax
        jnz 1f
        call sb_new
        mov r12, rax
        mov rdi, rax
        mov rsi, rbx
        call value_print
        mov rdi, r12
        call sb_finish
        LEAVE
1:      mov rax, rbx
        LEAVE
ENDF value_str

# --- colors (helpers.py) ---

        .section .rodata
        .globl C_HEADER, C_BLUE, C_OKGREEN, C_WARNING, C_FAIL, C_ENDC, C_BOLD, C_UNDERLINE, C_GREEN, C_GRAY, C_ASM, C_GREEN_BACK, C_BLUE_BACK
        .hidden C_HEADER, C_BLUE, C_OKGREEN, C_WARNING, C_FAIL, C_ENDC, C_BOLD, C_UNDERLINE, C_GREEN, C_GRAY, C_ASM, C_GREEN_BACK, C_BLUE_BACK
C_HEADER:     .asciz "\033[95m"
C_BLUE:       .asciz "\033[94m"
C_OKGREEN:    .asciz "\033[92m"
C_WARNING:    .asciz "\033[93m"
C_FAIL:       .asciz "\033[91m"
C_ENDC:       .asciz "\033[0m"
C_BOLD:       .asciz "\033[1m"
C_UNDERLINE:  .asciz "\033[4m"
C_GREEN:      .asciz "\033[32m"
C_GRAY:       .asciz "\033[38;5;8m"
C_ASM:        .asciz "\033[38;5;33m"
C_GREEN_BACK: .asciz "\033[42;1m\033[38;5;0m"
C_BLUE_BACK:  .asciz "\033[43;1m\033[38;5;0m"
        # the codes clean_color removes (C.every)
        .section .data.rel.ro
        .align 8
every_color:
        .quad C_HEADER, C_BLUE, C_OKGREEN, C_WARNING, C_FAIL, C_BOLD, C_UNDERLINE, C_GREEN, C_GRAY, C_ENDC, 0
        .text

# colorize(str, color_cstr, flags) -> str: helpers.color - the text
# between the color and ENDC when PF_COLOR (an empty text stays empty),
# else the text itself
FUNC colorize
        ENTER
        mov rbx, rdi
        mov r12, rsi
        test rdx, PF_COLOR
        jz 1f
        cmp dword ptr [rbx + N_DATA], 0
        je 1f
        call sb_new
        mov r13, rax
        mov rdi, rax
        mov rsi, r12
        call sb_append_c
        mov rdi, r13
        mov rsi, rbx
        call sb_append_str
        mov rdi, r13
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        mov rdi, r13
        call sb_finish
        LEAVE
1:      mov rax, rbx
        LEAVE
ENDF colorize

# colorize_c(cstr, color_cstr, flags) -> str
FUNC colorize_c
        ENTER
        mov rbx, rsi
        mov r12, rdx
        call str_new_c
        mov rdi, rax
        mov rsi, rbx
        mov rdx, r12
        call colorize
        LEAVE
ENDF colorize_c

# sb_append_col(sb, str, color_cstr, flags): colorize, appended
FUNC sb_append_col
        ENTER
        mov rbx, rdi
        mov rdi, rsi
        mov rsi, rdx
        mov rdx, rcx
        call colorize
        mov rdi, rbx
        mov rsi, rax
        call sb_append_str
        LEAVE
ENDF sb_append_col

# sb_append_col_c(sb, cstr, color_cstr, flags)
FUNC sb_append_col_c
        ENTER
        mov rbx, rdi
        mov rdi, rsi
        mov rsi, rdx
        mov rdx, rcx
        call colorize_c
        mov rdi, rbx
        mov rsi, rax
        call sb_append_str
        LEAVE
ENDF sb_append_col_c

# clean_color(str) -> str: the text without the color codes
FUNC clean_color
        ENTER
        sub rsp, 16
        mov rbx, rdi
        call sb_new
        mov r12, rax
        lea r13, [rbx + N_DATA + 4]
        mov r14d, [rbx + N_DATA]
        add r14, r13                    # the end
1:      cmp r13, r14
        jae 5f
        cmp byte ptr [r13], 0x1b
        jne 3f
        # one of the codes?
        lea rcx, [rip + every_color]
2:      mov rsi, [rcx]
        test rsi, rsi
        jz 3f
        mov [rsp], rcx
        mov [rsp + 8], rsi
        mov rdi, rsi
        call strlen@PLT
        mov rdx, rax
        mov rdi, r13
        mov rsi, [rsp + 8]
        push rdx
        push rdx
        call strncmp@PLT
        pop rdx
        pop rdx
        mov rcx, [rsp]
        test eax, eax
        jnz 4f
        add r13, rdx                    # skip the code
        jmp 1b
4:      add rcx, 8
        jmp 2b
3:      mov rdi, r12
        movzx esi, byte ptr [r13]
        call sb_append_char
        inc r13
        jmp 1b
5:      mov rdi, r12
        call sb_finish
        add rsp, 16
        LEAVE
ENDF clean_color

        .section .note.GNU-stack,"",@progbits
