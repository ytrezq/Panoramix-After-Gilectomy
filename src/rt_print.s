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
        cmp eax, K_INT
        je .Lp_int
        cmp eax, K_STR
        je .Lp_str
        cmp eax, K_TUPLE
        je .Lp_tuple
        cmp eax, K_LIST
        je .Lp_list
        cmp eax, K_SPECIAL
        je .Lp_special
        lea rsi, [rip + .Ls_nil]
        call sb_append_c
        LEAVE
.Lp_int:
        mov edx, 10
        call sb_append_int
        LEAVE
.Lp_str:
        mov esi, '\''
        call sb_append_char
        mov rdi, rbx
        mov rsi, r12
        call sb_append_str
        mov rdi, rbx
        mov esi, '\''
        call sb_append_char
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
