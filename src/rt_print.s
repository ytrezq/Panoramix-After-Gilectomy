# value_print(sb, v): python-repr-like rendering of a value, used for
# debugging and for comparing structures with the python implementation.

.include "defs.inc"

        .section .rodata
.Ls_nil:   .asciz "<nil>"
.Ls_none:  .asciz "None"
.Ls_true:  .asciz "True"
.Ls_false: .asciz "False"
.Ls_sep:   .asciz ", "
.Ls_1tuple: .asciz ",)"

        .text

FUNC value_print
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        test sil, 1
        jz 1f
        mov edx, 10
        call sb_append_int
        LEAVE
1:      test rsi, rsi
        jnz 2f
        lea rsi, [rip + .Ls_nil]
        call sb_append_c
        LEAVE
2:      mov eax, [r12 + N_KIND]
        JT_SWITCH kind, K_VMNODE, .Lp_nil
        JT_CASE kind, K_INT, .Lp_int
        JT_CASE kind, K_STR, .Lp_str
        JT_CASE kind, K_TUPLE, .Lp_tuple
        JT_CASE kind, K_LIST, .Lp_list
        JT_CASE kind, K_SPECIAL, .Lp_special
        JT_CASE kind, K_VMNODE, .Lp_vmnode
        JT_END kind, K_VMNODE, .Lp_nil
.Lp_vmnode:
        mov rsi, r12
        call node_print
        LEAVE
.Lp_nil:
        lea rsi, [rip + .Ls_nil]
        call sb_append_c
        LEAVE
.Lp_int:
        mov edx, 10
        call sb_append_int
        LEAVE
.Lp_str:
        mov rdi, rbx
        mov rsi, r12
        test dword ptr [r12 + N_AUX], STR_FLOAT
        jnz 5f
        call str_repr
        LEAVE
5:      call sb_append_str              # a float: bare, as python prints it
        LEAVE
.Lp_special:
        mov eax, [r12 + N_AUX]
        lea rsi, [rip + .Ls_none]
        cmp eax, SP_NONE
        je 3f
        lea rsi, [rip + .Ls_true]
        cmp eax, SP_TRUE
        je 3f
        lea rsi, [rip + .Ls_false]
3:      call sb_append_c
        LEAVE
.Lp_tuple:
        mov esi, '('
        call sb_append_char
        call .Lp_elems
        mov rdi, rbx
        cmp dword ptr [r12 + N_AUX], 1
        jne 4f
        lea rsi, [rip + .Ls_1tuple]
        call sb_append_c
        LEAVE
4:      mov esi, ')'
        call sb_append_char
        LEAVE
.Lp_list:
        mov esi, '['
        call sb_append_char
        call .Lp_elems
        mov rdi, rbx
        mov esi, ']'
        call sb_append_char
        LEAVE

# str_repr(sb, strnode): python's repr of a string: quoted with ' unless
# it contains a ' and no ", the quote and backslashes escaped, and the
# control characters as \n, \r, \t or \xNN
FUNC str_repr
        ENTER
        sub rsp, 16
        mov rbx, rdi
        lea r12, [rsi + N_DATA + 4]     # the characters
        mov r13d, [rsi + N_DATA]        # count
        mov r14d, '\''
        mov rdi, r12
        mov esi, '\''
        call strchr@PLT
        test rax, rax
        jz 1f
        mov rdi, r12
        mov esi, '"'
        call strchr@PLT
        test rax, rax
        jnz 1f
        mov r14d, '"'
1:      mov rdi, rbx
        mov esi, r14d
        call sb_append_char
        xor ecx, ecx
2:      cmp ecx, r13d
        jae 5f
        mov [rsp], rcx
        movzx eax, byte ptr [r12 + rcx]
        cmp eax, r14d
        je 3f
        cmp al, '\\'
        je 3f
        cmp al, 0x20
        jb 4f
        cmp al, 0x7f
        je 4f
        mov rdi, rbx
        mov esi, eax
        call sb_append_char
        jmp 6f
3:      mov [rsp + 8], rax
        mov rdi, rbx
        mov esi, '\\'
        call sb_append_char
        mov rdi, rbx
        mov esi, [rsp + 8]
        call sb_append_char
        jmp 6f
4:      # \n \r \t, or \xNN
        lea rsi, [rip + .Ls_n_esc]
        cmp al, 0x0a
        je 8f
        lea rsi, [rip + .Ls_r_esc]
        cmp al, 0x0d
        je 8f
        lea rsi, [rip + .Ls_t_esc]
        cmp al, 0x09
        je 8f
        lea rsi, [rip + .Ls_x_esc]
        mov [rsp + 8], rax
        mov rdi, rbx
        call sb_append_c
        mov rax, [rsp + 8]
        lea rcx, [rip + .Ls_hexdigits]
        mov edx, eax
        shr edx, 4
        movzx esi, byte ptr [rcx + rdx]
        mov rdi, rbx
        call sb_append_char
        mov rax, [rsp + 8]
        lea rcx, [rip + .Ls_hexdigits]
        and eax, 15
        movzx esi, byte ptr [rcx + rax]
        mov rdi, rbx
        call sb_append_char
        jmp 6f
8:      mov rdi, rbx
        call sb_append_c
6:      mov rcx, [rsp]
        inc rcx
        jmp 2b
5:      mov rdi, rbx
        mov esi, r14d
        call sb_append_char
        add rsp, 16
        LEAVE
ENDF str_repr

        .section .rodata
.Ls_x_esc: .asciz "\\x"
.Ls_hexdigits: .ascii "0123456789abcdef"
.Ls_n_esc: .asciz "\\n"
.Ls_r_esc: .asciz "\\r"
.Ls_t_esc: .asciz "\\t"
        .text

# local helper: print the elements of r12, comma separated (rbx = sb)
.Lp_elems:
        push r13
        push r14
        sub rsp, 8                      # the call pushed 8: realign
        xor r13d, r13d
5:      mov eax, [r12 + N_AUX]
        cmp r13, rax
        jae 6f
        test r13, r13
        jz 7f
        mov rdi, rbx
        lea rsi, [rip + .Ls_sep]
        call sb_append_c
7:      mov rdi, rbx
        mov rsi, [r12 + N_DATA + r13*8]
        call value_print
        inc r13
        jmp 5b
6:      add rsp, 8
        pop r14
        pop r13
        ret
ENDF value_print

        .section .note.GNU-stack,"",@progbits
