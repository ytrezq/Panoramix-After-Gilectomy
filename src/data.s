# python's decompilation.json (decompiler.py: contract.json(), after the
# postprocessing): the problems, the storage definitions and the
# functions - each with its names, its length, its getter or constant,
# payable, its printed text (with the colors), its trace and its
# parameters - serialized for the caller, in one of two forms:
#
#   DATA_BINARY (0), for the python module, which makes python's objects
#   back from it (the tuples stay tuples, the parameters' keys numbers):
#       'N' None, 'T' True, 'F' False
#       'i' int64 (little-endian)         a number that fits
#       'I' u32 n, n ASCII: [-]0x + hex   any other (python's int() takes
#                                         hex of any length, decimal of 4300
#                                         digits at most)
#       's' u32 n, n bytes of UTF-8       a string
#       'f' u32 n, n ASCII                a float, as python's repr
#       '(' u32 n, n values               a tuple
#       '[' u32 n, n values               a list
#       '{' u32 n, n keys and values      a dict
#   DATA_JSON (1): the text json.dumps makes of it (", " and ": ", the
#   non-ASCII characters escaped, the tuples as arrays, the numbers of
#   the keys as strings)

.include "defs.inc"

        .set DATA_BINARY, 0
        .set DATA_JSON, 1

        .section .rodata
.Ls_null:       .asciz "null"
.Ls_true:       .asciz "true"
.Ls_false:      .asciz "false"
.Ls_sep:        .asciz ", "
.Ls_colon:      .asciz ": "
.Ls_hex:        .ascii "0123456789abcdef"
.Ls_problems:   .asciz "problems"
.Ls_stor_defs:  .asciz "stor_defs"
.Ls_functions:  .asciz "functions"
.Ls_k_hash:     .asciz "hash"
.Ls_k_name:     .asciz "name"
.Ls_k_color_name: .asciz "color_name"
.Ls_k_abi_name: .asciz "abi_name"
.Ls_k_length:   .asciz "length"
.Ls_k_getter:   .asciz "getter"
.Ls_k_const:    .asciz "const"
.Ls_k_payable:  .asciz "payable"
.Ls_k_print:    .asciz "print"
.Ls_k_trace:    .asciz "trace"
.Ls_k_params:   .asciz "params"
        .text

# data_u32(sb, x): four bytes, little-endian
FUNC data_u32
        sub rsp, 24
        mov [rsp], esi
        mov rsi, rsp
        mov edx, 4
        call sb_append
        add rsp, 24
        ret
ENDF data_u32

# data_open(sb, c, count, mode): a dict ('{'), a tuple ('(') or a list
# ('[') of `count` elements begins
FUNC data_open
        ENTER
        mov rbx, rdi
        mov r12d, esi
        mov r13d, edx
        test ecx, ecx
        jnz 1f
        call sb_append_char
        mov rdi, rbx
        mov esi, r13d
        call data_u32
        LEAVE
1:      mov esi, '['
        cmp r12d, '{'
        jne 2f
        mov esi, '{'
2:      call sb_append_char
        LEAVE
ENDF data_open

# data_close(sb, c, mode): ... and ends
FUNC data_close
        test edx, edx
        jnz 1f
        ret
1:      cmp esi, '{'
        mov esi, ']'
        mov eax, '}'
        cmove esi, eax
        jmp sb_append_char
ENDF data_close

# data_sep(sb, index, mode): the separator before the element `index`
FUNC data_sep
        test edx, edx
        jz 1f
        test esi, esi
        jz 1f
        lea rsi, [rip + .Ls_sep]
        jmp sb_append_c
1:      ret
ENDF data_sep

# data_key(sb, cstr, mode): a key of a dict, the ':' included
FUNC data_key
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13d, edx
        test edx, edx
        jnz 1f
        mov esi, 's'
        call sb_append_char
        mov rdi, r12
        call strlen@PLT
        mov r14, rax
        mov rdi, rbx
        mov esi, eax
        call data_u32
        mov rdi, rbx
        mov rsi, r12
        mov rdx, r14
        call sb_append
        LEAVE
1:      mov esi, '"'
        call sb_append_char
        mov rdi, rbx
        mov rsi, r12
        call sb_append_c
        mov rdi, rbx
        mov esi, '"'
        call sb_append_char
        mov rdi, rbx
        lea rsi, [rip + .Ls_colon]
        call sb_append_c
        LEAVE
ENDF data_key

# data_special(sb, sp, mode): None, True or False (SP_*)
FUNC data_special
        test edx, edx
        jnz 1f
        mov eax, 'N'
        cmp esi, SP_TRUE
        mov ecx, 'T'
        cmove eax, ecx
        cmp esi, SP_FALSE
        mov ecx, 'F'
        cmove eax, ecx
        mov esi, eax
        jmp sb_append_char
1:      lea rax, [rip + .Ls_null]
        cmp esi, SP_TRUE
        lea rcx, [rip + .Ls_true]
        cmove rax, rcx
        cmp esi, SP_FALSE
        lea rcx, [rip + .Ls_false]
        cmove rax, rcx
        mov rsi, rax
        jmp sb_append_c
ENDF data_special

# data_small(sb, n, mode): a number of 64 bits (untagged)
FUNC data_small
        test edx, edx
        jnz 1f
        push rbx
        sub rsp, 16
        mov rbx, rdi
        mov [rsp], rsi
        mov esi, 'i'
        call sb_append_char
        mov rdi, rbx
        mov rsi, rsp
        mov edx, 8
        call sb_append
        add rsp, 16
        pop rbx
        ret
1:      jmp sb_append_i64
ENDF data_small

# data_value(sb, v, mode): any value of a trace
FUNC data_value
        STACK_CHECK
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov r13d, edx
        test sil, 1
        jnz .Ldv_small
        test rsi, rsi
        jz .Ldv_none
        mov eax, [r12 + N_KIND]
        cmp eax, K_INT
        je .Ldv_big
        cmp eax, K_STR
        je .Ldv_str
        cmp eax, K_TUPLE
        je .Ldv_seq
        cmp eax, K_LIST
        je .Ldv_seq
        cmp eax, K_SPECIAL
        jne .Ldv_none                   # (nothing else in a trace)
        mov esi, [r12 + N_AUX]
        jmp .Ldv_special
.Ldv_none:
        mov esi, SP_NONE
.Ldv_special:
        mov rdi, rbx
        mov edx, r13d
        call data_special
        jmp .Ldv_done
.Ldv_small:
        sar rsi, 1
        call data_small
        jmp .Ldv_done
.Ldv_big:
        test r13d, r13d
        jnz 1f
        mov esi, 'I'
        call data_len_begin
        mov [rsp], rax
        mov rdi, rbx
        mov rsi, r12
        mov edx, 16                     # (python reads hex of any length)
        call sb_append_int
        mov rdi, rbx
        mov rsi, [rsp]
        call data_len_end
        jmp .Ldv_done
1:      mov rsi, r12
        mov edx, 10
        call sb_append_int
        jmp .Ldv_done
.Ldv_str:
        test dword ptr [r12 + N_AUX], STR_FLOAT
        jnz .Ldv_float
        test r13d, r13d
        jnz 1f
        mov esi, 's'
        call sb_append_char
        mov rdi, rbx
        mov esi, [r12 + N_DATA]
        call data_u32
        mov rdi, rbx
        lea rsi, [r12 + N_DATA + 4]
        mov edx, [r12 + N_DATA]
        call sb_append
        jmp .Ldv_done
1:      lea rsi, [r12 + N_DATA + 4]
        mov edx, [r12 + N_DATA]
        call json_string
        jmp .Ldv_done
.Ldv_float:                             # python's repr, bare in json too
        test r13d, r13d
        jnz 1f
        mov esi, 'f'
        call sb_append_char
        mov rdi, rbx
        mov esi, [r12 + N_DATA]
        call data_u32
1:      mov rdi, rbx
        lea rsi, [r12 + N_DATA + 4]
        mov edx, [r12 + N_DATA]
        call sb_append
        jmp .Ldv_done
.Ldv_seq:
        mov esi, '('
        mov eax, '['
        cmp dword ptr [r12 + N_KIND], K_LIST
        cmove esi, eax
        mov [rsp + 8], rsi
        mov edx, [r12 + N_AUX]
        mov ecx, r13d
        call data_open
        xor r14d, r14d
2:      cmp r14d, [r12 + N_AUX]
        jae 3f
        mov rdi, rbx
        mov esi, r14d
        mov edx, r13d
        call data_sep
        mov rdi, rbx
        mov rsi, [r12 + N_DATA + r14*8]
        mov edx, r13d
        call data_value
        inc r14d
        jmp 2b
3:      mov rdi, rbx
        mov rsi, [rsp + 8]
        mov edx, r13d
        call data_close
.Ldv_done:
        add rsp, 16
        LEAVE
ENDF data_value

# data_len_begin(sb, tag) -> rax: the tag and a length to come (its
# offset in the builder)
FUNC data_len_begin
        push rbx
        mov rbx, rdi
        call sb_append_char
        mov rdi, rbx
        xor esi, esi
        call data_u32
        mov rax, [rbx + SB_LEN]
        sub rax, 4
        pop rbx
        ret
ENDF data_len_begin

# data_len_end(sb, offset): the length, of what follows it
FUNC data_len_end
        mov rax, [rdi + SB_LEN]
        sub rax, rsi
        sub rax, 4
        mov rcx, [rdi + SB_BUF]
        mov [rcx + rsi], eax
        ret
ENDF data_len_end

# json_string(sb, ptr, len): json.dumps of a string (ensure_ascii): the
# quote, the backslash and \b \f \n \r \t escaped, the other characters
# outside ' '..'~' as \uXXXX (the ones past U+FFFF as surrogate pairs)
FUNC json_string
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        lea r13, [rsi + rdx]            # the end
        mov esi, '"'
        call sb_append_char
.Ljs_loop:
        cmp r12, r13
        jae .Ljs_end
        # a run of plain characters, appended at once
        mov r14, r12
1:      cmp r14, r13
        jae 2f
        movzx eax, byte ptr [r14]
        cmp eax, 0x20
        jb 2f
        cmp eax, 0x7e
        ja 2f
        cmp eax, '"'
        je 2f
        cmp eax, '\\'
        je 2f
        inc r14
        jmp 1b
2:      cmp r14, r12
        je 3f
        mov rdi, rbx
        mov rsi, r12
        mov rdx, r14
        sub rdx, r12
        call sb_append
        mov r12, r14
        cmp r12, r13
        jae .Ljs_end
3:      movzx eax, byte ptr [r12]
        cmp eax, 0x80
        jae .Ljs_utf8
        inc r12
        mov ecx, 'b'
        cmp eax, 0x08
        je .Ljs_short
        mov ecx, 'f'
        cmp eax, 0x0c
        je .Ljs_short
        mov ecx, 'n'
        cmp eax, 0x0a
        je .Ljs_short
        mov ecx, 'r'
        cmp eax, 0x0d
        je .Ljs_short
        mov ecx, 't'
        cmp eax, 0x09
        je .Ljs_short
        mov ecx, eax
        cmp eax, '"'
        je .Ljs_short
        cmp eax, '\\'
        je .Ljs_short
        mov esi, eax                    # the other controls, and DEL
        call .Ljs_u
        jmp .Ljs_loop
.Ljs_short:
        mov [rsp], rcx
        mov rdi, rbx
        mov esi, '\\'
        call sb_append_char
        mov rdi, rbx
        mov rsi, [rsp]
        call sb_append_char
        jmp .Ljs_loop
.Ljs_utf8:
        # the code point of a UTF-8 sequence (a byte that doesn't start
        # a valid one stands for itself)
        mov ecx, 1
        mov esi, eax
        cmp eax, 0xc2
        jb 5f
        mov edx, 0x1f
        mov ecx, 2
        cmp eax, 0xe0
        jb 4f
        mov edx, 0x0f
        mov ecx, 3
        cmp eax, 0xf0
        jb 4f
        mov edx, 0x07
        mov ecx, 4
        cmp eax, 0xf5
        jb 4f
        mov ecx, 1
        jmp 5f
4:      mov rdi, r13
        sub rdi, r12
        cmp rdi, rcx
        jb 6f                           # (cut short)
        and esi, edx
        mov edi, 1
7:      cmp edi, ecx
        jae 5f
        movzx edx, byte ptr [r12 + rdi]
        mov r8d, edx
        and r8d, 0xc0
        cmp r8d, 0x80
        jne 6f
        shl esi, 6
        and edx, 0x3f
        or esi, edx
        inc edi
        jmp 7b
6:      mov ecx, 1
        movzx esi, byte ptr [r12]
5:      add r12, rcx
        cmp esi, 0x10000
        jae 8f
        call .Ljs_u
        jmp .Ljs_loop
8:      sub esi, 0x10000                # a surrogate pair
        mov [rsp], rsi
        shr esi, 10
        add esi, 0xd800
        call .Ljs_u
        mov rsi, [rsp]
        and esi, 0x3ff
        add esi, 0xdc00
        call .Ljs_u
        jmp .Ljs_loop
.Ljs_end:
        mov rdi, rbx
        mov esi, '"'
        call sb_append_char
        add rsp, 16
        LEAVE
# \uXXXX of esi (lowercase), to rbx
.Ljs_u:
        sub rsp, 24
        mov byte ptr [rsp], '\\'
        mov byte ptr [rsp + 1], 'u'
        lea rcx, [rip + .Ls_hex]
        mov eax, esi
        shr eax, 12
        and eax, 15
        movzx eax, byte ptr [rcx + rax]
        mov [rsp + 2], al
        mov eax, esi
        shr eax, 8
        and eax, 15
        movzx eax, byte ptr [rcx + rax]
        mov [rsp + 3], al
        mov eax, esi
        shr eax, 4
        and eax, 15
        movzx eax, byte ptr [rcx + rax]
        mov [rsp + 4], al
        mov eax, esi
        and eax, 15
        movzx eax, byte ptr [rcx + rax]
        mov [rsp + 5], al
        mov rdi, rbx
        mov rsi, rsp
        mov edx, 6
        call sb_append
        add rsp, 24
        ret
ENDF json_string

# contract_data(contract, sb, mode): python's decompilation.json
FUNC contract_data
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov r13d, edx
        mov rdi, r12
        mov esi, '{'
        mov edx, 3
        mov ecx, r13d
        call data_open
        # the problems: {hash: name}
        mov rdi, r12
        lea rsi, [rip + .Ls_problems]
        mov edx, r13d
        call data_key
        mov rax, [rbx + CT_PROBLEMS]
        mov [rsp], rax
        mov rdi, r12
        mov esi, '{'
        mov edx, [rax + N_AUX]
        mov ecx, r13d
        call data_open
        xor r14d, r14d
1:      mov rax, [rsp]
        cmp r14d, [rax + N_AUX]
        jae 2f
        mov rdi, r12
        mov esi, r14d
        mov edx, r13d
        call data_sep
        mov rax, [rsp]
        mov rax, [rax + N_DATA + r14*8] # (hash, name)
        mov rsi, [rax + N_DATA]
        mov [rsp + 8], rax
        mov rdi, r12
        mov edx, r13d
        call data_value
        mov rdi, r12
        mov esi, r13d
        call data_colon
        mov rax, [rsp + 8]
        mov rsi, [rax + N_DATA + 8]
        mov rdi, r12
        mov edx, r13d
        call data_value
        inc r14d
        jmp 1b
2:      mov rdi, r12
        mov esi, '{'
        mov edx, r13d
        call data_close
        # the storage definitions
        mov rdi, r12
        mov esi, 1
        mov edx, r13d
        call data_sep
        mov rdi, r12
        lea rsi, [rip + .Ls_stor_defs]
        mov edx, r13d
        call data_key
        cmp qword ptr [rbx + CT_STOR_FAILED], 0
        jne 5f
        mov rdi, r12
        mov rsi, [rbx + CT_STOR_DEFS]
        mov edx, r13d
        call data_value
        jmp 6f
5:      mov rdi, r12                    # (python's {} when it failed)
        mov esi, r13d
        call data_empty_dict
6:      # the functions
        mov rdi, r12
        mov esi, 2
        mov edx, r13d
        call data_sep
        mov rdi, r12
        lea rsi, [rip + .Ls_functions]
        mov edx, r13d
        call data_key
        mov rax, [rbx + CT_FUNCS]
        mov [rsp], rax
        mov rdi, r12
        mov esi, '['
        mov edx, [rax + VEC_LEN]
        mov ecx, r13d
        call data_open
        xor r14d, r14d
3:      mov rax, [rsp]
        cmp r14, [rax + VEC_LEN]
        jae 4f
        mov rdi, r12
        mov esi, r14d
        mov edx, r13d
        call data_sep
        mov rax, [rsp]
        mov rax, [rax + VEC_DATA]
        mov rdi, [rax + r14*8]
        mov rsi, r12
        mov edx, r13d
        call function_data
        inc r14
        jmp 3b
4:      mov rdi, r12
        mov esi, '['
        mov edx, r13d
        call data_close
        mov rdi, r12
        mov esi, '{'
        mov edx, r13d
        call data_close
        add rsp, 16
        LEAVE
ENDF contract_data

# data_colon(sb, mode): between a key and its value (json)
FUNC data_colon
        test esi, esi
        jnz 1f
        ret
1:      lea rsi, [rip + .Ls_colon]
        jmp sb_append_c
ENDF data_colon

# data_empty_dict(sb, mode): {} - python's json when it has none (no
# code; the serialization failed)
FUNC data_empty_dict
        ENTER
        mov rbx, rdi
        mov r12d, esi
        mov esi, '{'
        xor edx, edx
        mov ecx, r12d
        call data_open
        mov rdi, rbx
        mov esi, '{'
        mov edx, r12d
        call data_close
        LEAVE
ENDF data_empty_dict

# function_data(fn, sb, mode): Function.serialize()
FUNC function_data
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov r13d, edx
        mov rdi, r12
        mov esi, '{'
        mov edx, 11
        mov ecx, r13d
        call data_open
        xor r14d, r14d                  # the index of the key
        lea rsi, [rip + .Ls_k_hash]
        mov rdx, [rbx + FN_HASH]
        call .Lfd_field
        lea rsi, [rip + .Ls_k_name]
        mov rdx, [rbx + FN_NAME]
        call .Lfd_field
        lea rsi, [rip + .Ls_k_color_name]
        mov rdx, [rbx + FN_COLOR_NAME]
        call .Lfd_field
        lea rsi, [rip + .Ls_k_abi_name]
        mov rdx, [rbx + FN_ABI_NAME]
        call .Lfd_field
        # the length: (lines, characters) of the printed text
        lea rsi, [rip + .Ls_k_length]
        call .Lfd_key
        mov rdi, rbx
        call fn_print
        mov [rsp], rax
        mov rdi, r12
        mov esi, '('
        mov edx, 2
        mov ecx, r13d
        call data_open
        mov rdi, [rsp]
        mov esi, 10
        call str_count_char
        lea rsi, [rax + 1]
        mov rdi, r12
        mov edx, r13d
        call data_small
        mov rdi, r12
        mov esi, 1
        mov edx, r13d
        call data_sep
        mov rdi, [rsp]
        call str_charlen
        mov rsi, rax
        mov rdi, r12
        mov edx, r13d
        call data_small
        mov rdi, r12
        mov esi, '('
        mov edx, r13d
        call data_close
        lea rsi, [rip + .Ls_k_getter]
        mov rdx, [rbx + FN_GETTER]      # (0: None)
        call .Lfd_field
        lea rsi, [rip + .Ls_k_const]
        mov rdx, [rbx + FN_CONST]
        call .Lfd_field
        lea rsi, [rip + .Ls_k_payable]
        call .Lfd_key
        mov esi, SP_FALSE
        mov eax, SP_TRUE
        cmp qword ptr [rbx + FN_PAYABLE], 0
        cmovne esi, eax
        mov rdi, r12
        mov edx, r13d
        call data_special
        lea rsi, [rip + .Ls_k_print]
        mov rdx, [rsp]
        call .Lfd_field
        lea rsi, [rip + .Ls_k_trace]
        mov rdx, [rbx + FN_TRACE]
        call .Lfd_field
        # the parameters: {idx: (kind, name)}
        lea rsi, [rip + .Ls_k_params]
        call .Lfd_key
        mov rax, [rbx + FN_PARAMS]
        mov [rsp + 8], rax
        mov rdi, r12
        mov esi, '{'
        mov edx, [rax + N_AUX]
        mov ecx, r13d
        call data_open
        xor r14d, r14d
5:      mov rax, [rsp + 8]
        cmp r14d, [rax + N_AUX]
        jae 6f
        mov rdi, r12
        mov esi, r14d
        mov edx, r13d
        call data_sep
        mov rax, [rsp + 8]
        mov rax, [rax + N_DATA + r14*8] # (idx, kind, name)
        mov [rsp], rax
        mov rsi, [rax + N_DATA]
        test r13d, r13d
        jz 7f
        # json: the key as a string
        mov rdi, r12
        mov esi, '"'
        call sb_append_char
        mov rax, [rsp]
        mov rdi, r12
        mov rsi, [rax + N_DATA]
        mov edx, 10
        call sb_append_int
        mov rdi, r12
        mov esi, '"'
        call sb_append_char
        jmp 8f
7:      mov rdi, r12
        mov edx, r13d
        call data_value
8:      mov rdi, r12
        mov esi, r13d
        call data_colon
        mov rdi, r12
        mov esi, '('
        mov edx, 2
        mov ecx, r13d
        call data_open
        mov rax, [rsp]
        mov rsi, [rax + N_DATA + 8]
        mov rdi, r12
        mov edx, r13d
        call data_value
        mov rdi, r12
        mov esi, 1
        mov edx, r13d
        call data_sep
        mov rax, [rsp]
        mov rsi, [rax + N_DATA + 16]
        mov rdi, r12
        mov edx, r13d
        call data_value
        mov rdi, r12
        mov esi, '('
        mov edx, r13d
        call data_close
        inc r14d
        jmp 5b
6:      mov rdi, r12
        mov esi, '{'
        mov edx, r13d
        call data_close
        mov rdi, r12
        mov esi, '{'
        mov edx, r13d
        call data_close
        add rsp, 16
        LEAVE
# the key rsi (after the separator), then the value rdx
.Lfd_field:
        push rdx
        call .Lfd_key
        pop rsi
        push rsi                        # (aligned for the call)
        mov rdi, r12
        mov edx, r13d
        call data_value
        pop rsi
        ret
# the separator, and the key rsi
.Lfd_key:
        push rsi
        mov rdi, r12
        mov esi, r14d
        mov edx, r13d
        call data_sep
        inc r14d
        pop rsi
        push rsi                        # (aligned for the call)
        mov rdi, r12
        mov edx, r13d
        call data_key
        pop rsi
        ret
ENDF function_data

        .section .note.GNU-stack,"",@progbits
