# Pattern matching (port of matcher.py). A pattern is a value like the
# expressions, written as a python literal, with wildcards:
#   ':name'        matches anything, bound to `name` (a second ':name'
#                  must then be equal to the first)
#   ':int:name'    ... when it's an int (also :str:, :tuple:, :list:)
#   'Any'          matches anything, no binding
#   '...'          matches the rest of a sequence
# A pattern sequence matches tuples and lists alike, like in python.
#
# pat_match(exp, pattern, bindings) -> eax: 1 if it matches; the
# bindings (up to MATCH_MAX) are stored in the caller's array in the
# order the names first appear in the pattern, so that the code can
# name the slots: ('mask_shl', ':int:size', ':int:off', ':val') -> size
# is [b], off [b + 8], val [b + 16].
#
# PAT reg, "literal" loads the pattern for a literal, parsed once.

.include "defs.inc"

        .section .rodata
.Ls_any:        .asciz "Any"
.Ls_ellipsis:   .asciz "..."
.Ls_int:        .ascii "int:"
.Ls_str:        .ascii "str:"
.Ls_tuple:      .ascii "tuple:"
.Ls_list:       .ascii "list:"
.Ls_bad_pattern: .asciz "bad pattern literal"

        .section .bss
        .align 8
        .globl s_any, s_ellipsis
        .hidden s_any, s_ellipsis
s_any:          .quad 0
s_ellipsis:     .quad 0

        .text

# matcher_init(): the special strings
FUNC matcher_init
        ENTER
        lea rdi, [rip + .Ls_any]
        call str_intern_c
        mov [rip + s_any], rax
        lea rdi, [rip + .Ls_ellipsis]
        call str_intern_c
        mov [rip + s_ellipsis], rax
        LEAVE
ENDF matcher_init

# patterns_init(): parse every PAT literal (on the global context, which
# is bound at this point)
FUNC patterns_init
        ENTER
        lea rbx, [rip + __start_pattern_table]
1:      lea rax, [rip + __stop_pattern_table]
        cmp rbx, rax
        jae 3f
        mov rdi, [rbx + 8]
        call strlen@PLT
        mov rdi, [rbx + 8]
        mov rsi, rax
        call parse_literal
        test rax, rax
        jz 2f
        mov [rbx], rax
        add rbx, 16
        jmp 1b
2:      lea rdi, [rip + .Ls_bad_pattern]
        call rt_fatal
3:      LEAVE
ENDF patterns_init

        .hidden __start_pattern_table, __stop_pattern_table
        # (the section exists even when no pattern is used yet)
        .section pattern_table,"aw",@progbits
        .align 8
        .text

# pat_match(exp, pattern, bindings) -> eax
FUNC pat_match
        ENTER
        sub rsp, MATCH_NAMES_SIZE + 16
        mov rbx, rdx                    # the bindings
        mov qword ptr [rsp], 0          # how many so far
        mov rdx, rsp
        call match_helper
        add rsp, MATCH_NAMES_SIZE + 16
        LEAVE
ENDF pat_match

# match_helper(exp, pattern, state) -> eax; rbx = the bindings array,
# state = [count, names...]
FUNC match_helper
        ENTER
        sub rsp, 16
        mov r12, rdi                    # exp
        mov r13, rsi                    # pattern
        mov r14, rdx                    # state
        test sil, 1
        jnz .Lmh_equal                  # a small int: must be equal
        test rsi, rsi
        jz .Lmh_equal
        mov eax, [r13 + N_KIND]
        cmp eax, K_STR
        je .Lmh_str
        cmp eax, K_TUPLE
        je .Lmh_seq
        cmp eax, K_LIST
        je .Lmh_seq
.Lmh_equal:
        mov rdi, r12
        mov rsi, r13
        call values_equal
        add rsp, 16
        LEAVE
.Lmh_str:
        cmp r13, [rip + s_any]
        je .Lmh_yes
        cmp byte ptr [r13 + N_DATA + 4], ':'
        jne .Lmh_equal
        # a wildcard: ':name' or ':type:name'
        lea rdi, [r13 + N_DATA + 5]
        call wildcard_type_ok
        test eax, eax
        jz .Lmh_no
        lea rdi, [r13 + N_DATA + 5]
        call wildcard_name
        mov [rsp], rax                  # the name (after the type, if any)
        # bound already? then it must be the same
        mov qword ptr [rsp + 8], 0
1:      mov rcx, [rsp + 8]
        cmp rcx, [r14]
        jae 2f
        mov rdi, [r14 + 8 + rcx*8]
        mov rsi, [rsp]
        call strcmp@PLT
        test eax, eax
        jz 3f
        inc qword ptr [rsp + 8]
        jmp 1b
3:      mov rcx, [rsp + 8]
        mov rdi, r12
        mov rsi, [rbx + rcx*8]
        call values_equal
        add rsp, 16
        LEAVE
2:      cmp rcx, MATCH_MAX
        jae .Lmh_no
        mov rax, [rsp]
        mov [r14 + 8 + rcx*8], rax
        mov [rbx + rcx*8], r12
        inc qword ptr [r14]
        jmp .Lmh_yes
.Lmh_seq:
        mov rdi, r12
        call is_seq
        test eax, eax
        jz .Lmh_no
        mov qword ptr [rsp], 0          # position in both
4:      mov rcx, [rsp]
        cmp ecx, [r13 + N_AUX]
        jb 5f
        # the pattern is exhausted: the expression must be too
        cmp ecx, [r12 + N_AUX]
        je .Lmh_yes
        jmp .Lmh_no
5:      mov rsi, [r13 + N_DATA + rcx*8]
        cmp rsi, [rip + s_ellipsis]
        je .Lmh_yes
        cmp ecx, [r12 + N_AUX]
        jae .Lmh_no
        mov rdi, [r12 + N_DATA + rcx*8]
        mov rdx, r14
        call match_helper
        test eax, eax
        jz .Lmh_no
        inc qword ptr [rsp]
        jmp 4b
.Lmh_yes:
        mov eax, 1
        add rsp, 16
        LEAVE
.Lmh_no:
        xor eax, eax
        add rsp, 16
        LEAVE
ENDF match_helper

# wildcard_type_ok(text) -> eax: for the text after the ':' of a
# wildcard, whether r12 (the expression) has the type it asks for, if any
FUNC wildcard_type_ok
        ENTER
        mov rbx, rdi
        lea rsi, [rip + .Ls_int]
        mov edx, 4
        call strncmp@PLT
        test eax, eax
        jnz 1f
        mov rdi, r12
        call is_int
        LEAVE
1:      mov rdi, rbx
        lea rsi, [rip + .Ls_str]
        mov edx, 4
        call strncmp@PLT
        test eax, eax
        jnz 2f
        mov rdi, r12
        call is_str
        LEAVE
2:      mov rdi, rbx
        lea rsi, [rip + .Ls_tuple]
        mov edx, 6
        call strncmp@PLT
        test eax, eax
        jnz 3f
        mov rdi, r12
        call is_tuple
        LEAVE
3:      mov rdi, rbx
        lea rsi, [rip + .Ls_list]
        mov edx, 5
        call strncmp@PLT
        test eax, eax
        jnz 4f
        mov rdi, r12
        call is_list
        LEAVE
4:      mov eax, 1
        LEAVE
ENDF wildcard_type_ok

# wildcard_name(text) -> rax: the name of a wildcard, i.e. what follows
# the type prefix if there is one (':int:x' -> 'x')
FUNC wildcard_name
        ENTER
        mov rbx, rdi
        mov esi, ':'
        call strchr@PLT
        test rax, rax
        jz 1f
        inc rax
        LEAVE
1:      mov rax, rbx
        LEAVE
ENDF wildcard_name

# is_str(v) -> eax
FUNC is_str
        xor eax, eax
        test dil, 1
        jnz 1f
        test rdi, rdi
        jz 1f
        cmp dword ptr [rdi + N_KIND], K_STR
        sete al
1:      ret
ENDF is_str

        .section .note.GNU-stack,"",@progbits
