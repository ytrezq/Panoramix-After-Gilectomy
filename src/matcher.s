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
        mov rdi, rax
        call pattern_compile
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

# pattern_compile(pat) -> rax: the pattern with its wildcards made
# K_WILD nodes (aux: the binding's slot | the type << 8 | a repeat of a
# name bound before << 16), numbered in the order match_helper meets
# them - depth first, a sequence's elements up to a '...' - which is the
# order of the bindings. The strings of the wildcards were read for every
# match: the prefix of the type (strncmp), the name (strchr), the names
# bound before (strcmp).
FUNC pattern_compile
        ENTER
        sub rsp, MATCH_NAMES_SIZE + 8
        mov qword ptr [rsp], 0          # [count, names...]
        mov rsi, rsp
        call pc_walk
        add rsp, MATCH_NAMES_SIZE + 8
        LEAVE
ENDF pattern_compile

# pc_walk(v, state) -> rax
FUNC pc_walk
        STACK_CHECK
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        test bl, 1
        jnz .Lpc_asis
        test rbx, rbx
        jz .Lpc_asis
        mov eax, [rbx + N_KIND]
        cmp eax, K_STR
        je .Lpc_str
        cmp eax, K_TUPLE
        je .Lpc_seq
        cmp eax, K_LIST
        je .Lpc_seq
.Lpc_asis:
        mov rax, rbx
        add rsp, 16
        LEAVE
.Lpc_str:
        cmp byte ptr [rbx + N_DATA + 4], ':'
        jne .Lpc_asis
        lea r13, [rbx + N_DATA + 5]     # after the ':'
        xor r14d, r14d                  # the type
        mov rdi, r13
        lea rsi, [rip + .Ls_int]
        mov edx, 4
        call strncmp@PLT
        mov ecx, 1
        test eax, eax
        jz 1f
        mov rdi, r13
        lea rsi, [rip + .Ls_str]
        mov edx, 4
        call strncmp@PLT
        mov ecx, 2
        test eax, eax
        jz 1f
        mov rdi, r13
        lea rsi, [rip + .Ls_tuple]
        mov edx, 6
        call strncmp@PLT
        mov ecx, 3
        test eax, eax
        jz 1f
        mov rdi, r13
        lea rsi, [rip + .Ls_list]
        mov edx, 5
        call strncmp@PLT
        mov ecx, 4
        test eax, eax
        jz 1f
        xor ecx, ecx
1:      mov r14d, ecx
        shl r14d, 8
        mov rdi, r13
        call wildcard_name
        mov [rsp], rax                  # the name
        # bound before? then a repeat of its slot
        mov qword ptr [rsp + 8], 0
2:      mov rcx, [rsp + 8]
        cmp rcx, [r12]
        jae 3f
        mov rdi, [r12 + 8 + rcx*8]
        mov rsi, [rsp]
        call strcmp@PLT
        test eax, eax
        jz 4f
        inc qword ptr [rsp + 8]
        jmp 2b
4:      mov eax, [rsp + 8]
        or r14d, eax
        or r14d, 1 << 16
        jmp 5f
3:      cmp rcx, MATCH_MAX
        jae .Lpc_too_many
        mov rax, [rsp]
        mov [r12 + 8 + rcx*8], rax
        inc qword ptr [r12]
        or r14d, ecx
5:      mov edi, N_DATA
        call arena_alloc
        mov r13, rax
        mov dword ptr [r13 + N_KIND], K_WILD
        mov [r13 + N_AUX], r14d
        lea rdi, [r14 + 0x5bd1e995]
        call hash_mix
        mov rcx, HF_MASK
        not rcx
        and rax, rcx
        mov [r13 + N_HASH], rax
        mov rax, r13
        add rsp, 16
        LEAVE
.Lpc_seq:
        call vec_new
        mov r13, rax
        xor r14d, r14d
6:      cmp r14d, [rbx + N_AUX]
        jae 8f
        mov rsi, [rbx + N_DATA + r14*8]
        cmp rsi, [rip + s_ellipsis]
        je 7f
        mov rdi, rsi
        mov rsi, r12
        call pc_walk
        mov rdi, r13
        mov rsi, rax
        call vec_push
        inc r14d
        jmp 6b
7:      # '...': the rest is never matched, kept as it is
        mov rsi, [rbx + N_DATA + r14*8]
        mov rdi, r13
        call vec_push
        inc r14d
        cmp r14d, [rbx + N_AUX]
        jb 7b
8:      mov edi, [rbx + N_KIND]
        mov esi, [rbx + N_AUX]
        mov rdx, [r13 + VEC_DATA]
        call mk_seq
        add rsp, 16
        LEAVE
.Lpc_too_many:
        lea rdi, [rip + .Ls_too_many]
        call rt_fatal
ENDF pc_walk

        .section .rodata
.Ls_too_many:   .asciz "a pattern with more names than MATCH_MAX"
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
        STACK_CHECK
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
        cmp eax, K_WILD
        je .Lmh_wild
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
.Lmh_wild:                              # a compiled wildcard
        mov eax, [r13 + N_AUX]
        shr eax, 8
        and eax, 0xff
        jz 2f
        mov rdi, r12
        cmp eax, 1
        jne 11f
        call is_int
        jmp 14f
11:     cmp eax, 2
        jne 12f
        call is_str
        jmp 14f
12:     cmp eax, 3
        jne 13f
        call is_tuple
        jmp 14f
13:     call is_list
14:     test eax, eax
        jz .Lmh_no
2:      mov eax, [r13 + N_AUX]
        movzx ecx, al                   # the slot
        test eax, 1 << 16
        jnz 3f
        mov [rbx + rcx*8], r12
        jmp .Lmh_yes
3:      mov rdi, r12                    # a name bound before: the same value
        mov rsi, [rbx + rcx*8]
        call values_equal
        add rsp, 16
        LEAVE
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
