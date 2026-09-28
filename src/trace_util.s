# Generic walks and rewrites of traces and expressions (the helpers of
# utils/helpers.py). Traces are lists of lines; an ('if', cond, if_true,
# if_false) line holds two traces, a ('while', cond, body, jd, setvars)
# one.
#
# Callbacks take (x, arg) plus, for the rewrites, the vec to append the
# replacement lines to: f(line, arg, out).

.include "defs.inc"

        .text

# mk_list1(x) -> [x]
FUNC mk_list1
        ENTER
        sub rsp, 16
        mov [rsp], rdi
        mov edi, 1
        mov rsi, rsp
        call mk_list
        add rsp, 16
        LEAVE
ENDF mk_list1

# list_concat(a, b) -> list: a + b (sequences of either kind)
FUNC list_concat
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call vec_new
        mov r13, rax
        mov rdi, rax
        mov rsi, rbx
        call vec_extend_seq
        mov rdi, r13
        mov rsi, r12
        call vec_extend_seq
        mov rdi, r13
        call vec_to_list
        LEAVE
ENDF list_concat

# list_from(seq, start) -> list: seq[start:]
FUNC list_from
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call vec_new
        mov r13, rax
        mov edx, [rbx + N_AUX]
        sub rdx, r12
        jle 1f
        mov rdi, r13
        lea rsi, [rbx + N_DATA + r12*8]
        call vec_extend
1:      mov rdi, r13
        call vec_to_list
        LEAVE
ENDF list_from

# seq_index(seq, x) -> rax: the index of x in the sequence, or -1
FUNC seq_index
        xor eax, eax
1:      cmp eax, [rdi + N_AUX]
        jae 2f
        cmp [rdi + N_DATA + rax*8], rsi
        je 3f
        inc eax
        jmp 1b
2:      mov rax, -1
3:      ret
ENDF seq_index

# seq_contains(seq, x) -> eax
FUNC seq_contains
        ENTER
        call seq_index
        cmp rax, -1
        setne al
        movzx eax, al
        LEAVE
ENDF seq_contains

# seq_last(seq) -> rax: the last element, or 0 when empty
FUNC seq_last
        mov ecx, [rdi + N_AUX]
        test ecx, ecx
        jz 1f
        mov rax, [rdi + N_DATA + rcx*8 - 8]
        ret
1:      xor eax, eax
        ret
ENDF seq_last

# is_if_line(line) -> eax: ('if', cond, if_true, if_false)
FUNC is_if_line
        OP_N_CHECK OP_IF, 4, 1f           # (a leaf: only rax is changed)
        mov eax, 1
        ret
1:      xor eax, eax
        ret
ENDF is_if_line

# is_while_line(line) -> eax: ('while', cond, body, jd, setvars)
FUNC is_while_line
        OP_N_CHECK OP_WHILE, 5, 1f           # (a leaf: only rax is changed)
        mov eax, 1
        ret
1:      xor eax, eax
        ret
ENDF is_while_line

# mk_if(cond, if_true, if_false) / mk_while(cond, body, jd, setvars)
FUNC mk_if
        mov rcx, rdx
        mov rdx, rsi
        mov rsi, rdi
        LOADS rdi, IF
        jmp mk4
ENDF mk_if

FUNC mk_while
        mov r8, rcx
        mov rcx, rdx
        mov rdx, rsi
        mov rsi, rdi
        LOADS rdi, WHILE
        jmp mk5
ENDF mk_while

# rewrite_trace(trace, f, arg) -> list: every line but the ifs goes
# through f(line, arg, out); the ifs' branches are rewritten
FUNC rewrite_trace
        STACK_CHECK
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        call vec_new
        mov [rsp], rax
        xor r14d, r14d
1:      cmp r14d, [rbx + N_AUX]
        jae 5f
        mov rdi, [rbx + N_DATA + r14*8]
        mov [rsp + 8], rdi
        call is_if_line
        test eax, eax
        jz 2f
        mov rdi, [rsp + 8]
        mov rdi, [rdi + N_DATA + 16]
        mov rsi, r12
        mov rdx, r13
        call rewrite_trace
        mov rdi, [rsp + 8]
        mov [rsp + 8], rax
        mov rdi, [rdi + N_DATA + 24]
        mov rsi, r12
        mov rdx, r13
        call rewrite_trace
        mov rdx, rax
        mov rsi, [rsp + 8]
        mov rax, [rbx + N_DATA + r14*8]
        mov rdi, [rax + N_DATA + 8]
        call mk_if
        mov rdi, [rsp]
        mov rsi, rax
        call vec_push
        jmp 4f
2:      mov rdi, [rsp + 8]
        mov rsi, r13
        mov rdx, [rsp]
        call r12
4:      inc r14
        jmp 1b
5:      mov rdi, [rsp]
        call vec_to_list
        add rsp, 16
        LEAVE
ENDF rewrite_trace

# rewrite_trace_full(trace, f, arg) -> list: like rewrite_trace, the
# whiles' bodies rewritten too
FUNC rewrite_trace_full
        STACK_CHECK
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        call vec_new
        mov [rsp], rax
        xor r14d, r14d
1:      cmp r14d, [rbx + N_AUX]
        jae 5f
        mov rdi, [rbx + N_DATA + r14*8]
        mov [rsp + 8], rdi
        call is_if_line
        test eax, eax
        jz 2f
        mov rdi, [rsp + 8]
        mov rdi, [rdi + N_DATA + 16]
        mov rsi, r12
        mov rdx, r13
        call rewrite_trace_full
        mov rdi, [rsp + 8]
        mov [rsp + 8], rax
        mov rdi, [rdi + N_DATA + 24]
        mov rsi, r12
        mov rdx, r13
        call rewrite_trace_full
        mov rdx, rax
        mov rsi, [rsp + 8]
        mov rax, [rbx + N_DATA + r14*8]
        mov rdi, [rax + N_DATA + 8]
        call mk_if
        mov rdi, [rsp]
        mov rsi, rax
        call vec_push
        jmp 4f
2:      mov rdi, [rsp + 8]
        call is_while_line
        test eax, eax
        jz 3f
        mov rdi, [rsp + 8]
        mov rdi, [rdi + N_DATA + 16]
        mov rsi, r12
        mov rdx, r13
        call rewrite_trace_full
        mov rsi, rax
        mov rax, [rsp + 8]
        mov rdi, [rax + N_DATA + 8]
        mov rdx, [rax + N_DATA + 24]
        mov rcx, [rax + N_DATA + 32]
        call mk_while
        mov rdi, [rsp]
        mov rsi, rax
        call vec_push
        jmp 4f
3:      mov rdi, [rsp + 8]
        mov rsi, r13
        mov rdx, [rsp]
        call r12
4:      inc r14
        jmp 1b
5:      mov rdi, [rsp]
        call vec_to_list
        add rsp, 16
        LEAVE
ENDF rewrite_trace_full

# rewrite_trace_ifs(trace, f, arg) -> list: f sees the ifs too; when it
# leaves an if alone its branches are rewritten, otherwise what it
# returned is
FUNC rewrite_trace_ifs
        STACK_CHECK
        ENTER
        sub rsp, 32
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        call vec_new
        mov [rsp], rax
        xor r14d, r14d
1:      cmp r14d, [rbx + N_AUX]
        jae 6f
        mov rdi, [rbx + N_DATA + r14*8]
        mov [rsp + 8], rdi
        call is_if_line
        test eax, eax
        jz 3f
        call vec_new
        mov [rsp + 16], rax
        mov rdi, [rsp + 8]
        mov rsi, r13
        mov rdx, rax
        call r12
        mov rax, [rsp + 16]
        cmp qword ptr [rax + VEC_LEN], 1
        jne 2f
        mov rax, [rax + VEC_DATA]
        mov rax, [rax]
        cmp rax, [rsp + 8]
        jne 2f
        # unchanged: into the branches
        mov rdi, [rsp + 8]
        mov rdi, [rdi + N_DATA + 16]
        mov rsi, r12
        mov rdx, r13
        call rewrite_trace_ifs
        mov [rsp + 16], rax
        mov rdi, [rsp + 8]
        mov rdi, [rdi + N_DATA + 24]
        mov rsi, r12
        mov rdx, r13
        call rewrite_trace_ifs
        mov rdx, rax
        mov rsi, [rsp + 16]
        mov rax, [rsp + 8]
        mov rdi, [rax + N_DATA + 8]
        call mk_if
        mov rdi, [rsp]
        mov rsi, rax
        call vec_push
        jmp 5f
2:      # replaced: rewrite the new lines
        mov rdi, [rsp + 16]
        call vec_to_list
        mov rdi, rax
        mov rsi, r12
        mov rdx, r13
        call rewrite_trace_ifs
        mov rdi, [rsp]
        mov rsi, rax
        call vec_extend_seq
        jmp 5f
3:      mov rdi, [rsp + 8]
        call is_while_line
        test eax, eax
        jz 4f
        mov rdi, [rsp + 8]
        mov rdi, [rdi + N_DATA + 16]
        mov rsi, r12
        mov rdx, r13
        call rewrite_trace_ifs
        mov rsi, rax
        mov rax, [rsp + 8]
        mov rdi, [rax + N_DATA + 8]
        mov rdx, [rax + N_DATA + 24]
        mov rcx, [rax + N_DATA + 32]
        call mk_while
        mov rdi, [rsp]
        mov rsi, rax
        call vec_push
        jmp 5f
4:      mov rdi, [rsp + 8]
        mov rsi, r13
        mov rdx, [rsp]
        call r12
5:      inc r14
        jmp 1b
6:      mov rdi, [rsp]
        call vec_to_list
        add rsp, 32
        LEAVE
ENDF rewrite_trace_ifs

# rewrite_trace_multiline(trace, f, arg, number) -> list: f(window, arg)
# sees `number` consecutive lines (as a list) and returns their
# replacement (a list) or 0 to leave them
FUNC rewrite_trace_multiline
        STACK_CHECK
        ENTER
        sub rsp, 32
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov [rsp + 16], rcx             # number
        call vec_new
        mov [rsp], rax
        xor r14d, r14d
1:      cmp r14d, [rbx + N_AUX]
        jae 6f
        mov eax, r14d
        add rax, [rsp + 16]
        cmp eax, [rbx + N_AUX]
        ja 2f
        mov rdi, [rsp + 16]
        lea rsi, [rbx + N_DATA + r14*8]
        call mk_list
        mov rdi, rax
        mov rsi, r13
        call r12
        test rax, rax
        jz 2f
        mov rdi, [rsp]
        mov rsi, rax
        call vec_extend_seq
        add r14, [rsp + 16]
        jmp 1b
2:      mov rdi, [rbx + N_DATA + r14*8]
        mov [rsp + 8], rdi
        call is_if_line
        test eax, eax
        jz 3f
        mov rdi, [rsp + 8]
        mov rdi, [rdi + N_DATA + 16]
        mov rsi, r12
        mov rdx, r13
        mov rcx, [rsp + 16]
        call rewrite_trace_multiline
        mov [rsp + 24], rax
        mov rdi, [rsp + 8]
        mov rdi, [rdi + N_DATA + 24]
        mov rsi, r12
        mov rdx, r13
        mov rcx, [rsp + 16]
        call rewrite_trace_multiline
        mov rdx, rax
        mov rsi, [rsp + 24]
        mov rax, [rsp + 8]
        mov rdi, [rax + N_DATA + 8]
        call mk_if
        mov rdi, [rsp]
        mov rsi, rax
        call vec_push
        jmp 5f
3:      mov rdi, [rsp + 8]
        call is_while_line
        test eax, eax
        jz 4f
        mov rdi, [rsp + 8]
        mov rdi, [rdi + N_DATA + 16]
        mov rsi, r12
        mov rdx, r13
        mov rcx, [rsp + 16]
        call rewrite_trace_multiline
        mov rsi, rax
        mov rax, [rsp + 8]
        mov rdi, [rax + N_DATA + 8]
        mov rdx, [rax + N_DATA + 24]
        mov rcx, [rax + N_DATA + 32]
        call mk_while
        mov rdi, [rsp]
        mov rsi, rax
        call vec_push
        jmp 5f
4:      mov rdi, [rsp]
        mov rsi, [rsp + 8]
        call vec_push
5:      inc r14
        jmp 1b
6:      mov rdi, [rsp]
        call vec_to_list
        add rsp, 32
        LEAVE
ENDF rewrite_trace_multiline

# replace_lines(trace, f, arg) -> list: f(x, arg) -> x' applied to the
# conditions and setvars of the ifs and whiles, and to the other lines
FUNC replace_lines
        STACK_CHECK
        ENTER
        sub rsp, 32
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        call vec_new
        mov [rsp], rax
        xor r14d, r14d
1:      cmp r14d, [rbx + N_AUX]
        jae 6f
        mov rdi, [rbx + N_DATA + r14*8]
        mov [rsp + 8], rdi
        call is_while_line
        test eax, eax
        jz 2f
        mov rax, [rsp + 8]
        mov rdi, [rax + N_DATA + 8]
        mov rsi, r13
        call r12
        mov [rsp + 16], rax             # cond
        mov rax, [rsp + 8]
        mov rdi, [rax + N_DATA + 16]
        mov rsi, r12
        mov rdx, r13
        call replace_lines
        mov [rsp + 24], rax             # path
        mov rax, [rsp + 8]
        mov rdi, [rax + N_DATA + 32]
        mov rsi, r13
        call r12
        mov rcx, rax                    # setvars
        mov rax, [rsp + 8]
        mov rdx, [rax + N_DATA + 24]
        mov rdi, [rsp + 16]
        mov rsi, [rsp + 24]
        call mk_while
        jmp 4f
2:      mov rdi, [rsp + 8]
        call is_if_line
        test eax, eax
        jz 3f
        mov rax, [rsp + 8]
        mov rdi, [rax + N_DATA + 8]
        mov rsi, r13
        call r12
        mov [rsp + 16], rax
        mov rax, [rsp + 8]
        mov rdi, [rax + N_DATA + 16]
        mov rsi, r12
        mov rdx, r13
        call replace_lines
        mov [rsp + 24], rax
        mov rax, [rsp + 8]
        mov rdi, [rax + N_DATA + 24]
        mov rsi, r12
        mov rdx, r13
        call replace_lines
        mov rdx, rax
        mov rdi, [rsp + 16]
        mov rsi, [rsp + 24]
        call mk_if
        jmp 4f
3:      mov rdi, [rsp + 8]
        mov rsi, r13
        call r12
4:      mov rdi, [rsp]
        mov rsi, rax
        call vec_push
        inc r14
        jmp 1b
6:      mov rdi, [rsp]
        call vec_to_list
        add rsp, 32
        LEAVE
ENDF replace_lines

# walk_trace(trace, f, arg, out): f(line, arg, out) for every line, the
# ifs' branches (and nested lists) included
FUNC walk_trace
        STACK_CHECK
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov [rsp], rcx
        xor r14d, r14d
1:      cmp r14d, [rbx + N_AUX]
        jae 4f
        mov rdi, [rbx + N_DATA + r14*8]
        mov [rsp + 8], rdi
        call is_list
        test eax, eax
        jz 2f
        mov rdi, [rsp + 8]
        mov rsi, r12
        mov rdx, r13
        mov rcx, [rsp]
        call walk_trace
        jmp 3f
2:      mov rdi, [rsp + 8]
        mov rsi, r13
        mov rdx, [rsp]
        call r12
        mov rdi, [rsp + 8]
        call is_if_line
        test eax, eax
        jz 3f
        mov rdi, [rsp + 8]
        mov rdi, [rdi + N_DATA + 16]
        mov rsi, r12
        mov rdx, r13
        mov rcx, [rsp]
        call walk_trace
        mov rdi, [rsp + 8]
        mov rdi, [rdi + N_DATA + 24]
        mov rsi, r12
        mov rdx, r13
        mov rcx, [rsp]
        call walk_trace
3:      inc r14
        jmp 1b
4:      add rsp, 16
        LEAVE
ENDF walk_trace

# is_list(v) -> eax
FUNC is_list
        xor eax, eax
        test dil, 1
        jnz 1f
        test rdi, rdi
        jz 1f
        cmp dword ptr [rdi + N_KIND], K_LIST
        sete al
1:      ret
ENDF is_list

# replace(exp, what, by) -> exp with every occurrence of `what` replaced
FUNC replace
        # the mention flags of `what` (a string's, or a tuple's: the or of
        # its elements'): a tuple without all of them can't hold it, and
        # is kept as it is without a walk
        xor ecx, ecx
        test sil, 1
        jnz replace_fl
        test rsi, rsi
        jz replace_fl
        mov eax, [rsi + N_KIND]
        cmp eax, K_STR
        je 1f
        cmp eax, K_TUPLE
        je 1f
        cmp eax, K_LIST
        jne replace_fl
1:      mov rcx, [rsi + N_HASH]
        mov rax, HF_MASK
        and rcx, rax
        jmp replace_fl
ENDF replace

# replace_fl(exp, what, by_what, flags): replace's walk - the leaves
# (numbers, strings, the sequences without all the flags) looked at in
# the loop, without a call (a replace visits them by the million)
FUNC replace_fl
        STACK_CHECK
        cmp rdi, rsi
        je .Lrp_by0
        test dil, 1
        jnz .Lrp_asis0
        test rdi, rdi
        jz .Lrp_asis0
        mov eax, [rdi + N_KIND]
        cmp eax, K_INT
        je .Lrp_int0
        cmp eax, K_TUPLE
        je 1f
        cmp eax, K_LIST
        jne .Lrp_asis0
1:      mov rax, [rdi + N_HASH]
        and rax, rcx
        cmp rax, rcx
        jne .Lrp_asis0
        ENTER
        sub rsp, 32
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov [rsp + 16], rcx             # the flags
        mov qword ptr [rsp], 0          # the copy of the elements, once one changes
        xor r14d, r14d
2:      cmp r14d, [rbx + N_AUX]
        jae 5f
        mov rdi, [rbx + N_DATA + r14*8]
        # the element's replacement, rax (rdi itself mostly)
        mov rax, r13
        cmp rdi, r12
        je 3f
        mov rax, rdi
        test dil, 1
        jnz 3f
        test rdi, rdi
        jz 3f
        mov ecx, [rdi + N_KIND]
        cmp ecx, K_TUPLE
        je 21f
        cmp ecx, K_LIST
        je 21f
        cmp ecx, K_INT
        jne 3f                          # a string, a special: itself
        mov rsi, r12                    # a number: equal to what? (a
        call values_equal               # constant of the global context)
        test eax, eax
        mov rax, [rbx + N_DATA + r14*8]
        cmovnz rax, r13
        jmp 3f
21:     mov rcx, [rsp + 16]
        mov rdx, [rdi + N_HASH]
        and rdx, rcx
        cmp rdx, rcx
        jne 3f                          # without the flags: itself
        mov rsi, r12
        mov rdx, r13
        call replace_fl
3:      cmp qword ptr [rsp], 0
        jne 4f
        cmp rax, [rbx + N_DATA + r14*8]
        je 41f                          # (unchanged so far: no copy yet)
        # the first change: the copy, with the elements before it
        mov [rsp + 8], rax
        mov edi, [rbx + N_AUX]
        shl rdi, 3
        call arena_alloc_raw
        mov [rsp], rax
        mov rdi, rax
        lea rsi, [rbx + N_DATA]
        mov edx, r14d
        shl edx, 3
        call memcpy@PLT
        mov rax, [rsp + 8]
4:      mov rcx, [rsp]
        mov [rcx + r14*8], rax
41:     inc r14d
        jmp 2b
5:      mov rax, rbx
        cmp qword ptr [rsp], 0
        je 6f
        mov edi, [rbx + N_KIND]
        mov esi, [rbx + N_AUX]
        mov rdx, [rsp]
        call mk_seq
6:      add rsp, 32
        LEAVE
.Lrp_int0:
        push rdi
        push rdx
        sub rsp, 8
        call values_equal
        add rsp, 8
        pop rdx
        pop rdi
        test eax, eax
        jz .Lrp_asis0
.Lrp_by0:
        mov rax, rdx
        ret
.Lrp_asis0:
        mov rax, rdi
        ret
ENDF replace_fl

# replace_many(exp, n, whats, bys) -> exp with every occurrence of whats[i]
# replaced by bys[i], all at once (an outer expression wins over the
# expressions it contains: mem[_5] is replaced before _5)
FUNC replace_many
        STACK_CHECK
        ENTER
        sub rsp, 32
        .set RM_BYS, 0
        .set RM_ELEMS, 8
        .set RM_CHANGED, 16
        mov rbx, rdi
        mov r12, rsi                    # n
        mov r13, rdx                    # whats
        mov [rsp + RM_BYS], rcx
        xor r14d, r14d
1:      cmp r14, r12
        jae 2f
        mov rdi, rbx
        mov rsi, [r13 + r14*8]
        call values_equal
        test eax, eax
        jnz .Lrm_by
        inc r14
        jmp 1b
2:      mov rdi, rbx
        call is_seq
        test eax, eax
        jz .Lrm_asis
        mov edi, [rbx + N_AUX]
        shl rdi, 3
        call arena_alloc
        mov [rsp + RM_ELEMS], rax
        mov qword ptr [rsp + RM_CHANGED], 0
        xor r14d, r14d
3:      cmp r14d, [rbx + N_AUX]
        jae 4f
        mov rdi, [rbx + N_DATA + r14*8]
        mov rsi, r12
        mov rdx, r13
        mov rcx, [rsp + RM_BYS]
        call replace_many
        mov rcx, [rsp + RM_ELEMS]
        mov [rcx + r14*8], rax
        cmp rax, [rbx + N_DATA + r14*8]
        je 5f
        mov qword ptr [rsp + RM_CHANGED], 1
5:      inc r14
        jmp 3b
4:      cmp qword ptr [rsp + RM_CHANGED], 0
        je .Lrm_asis
        mov edi, [rbx + N_KIND]
        mov esi, [rbx + N_AUX]
        mov rdx, [rsp + RM_ELEMS]
        call mk_seq
        add rsp, 32
        LEAVE
.Lrm_by:
        mov rax, [rsp + RM_BYS]
        mov rax, [rax + r14*8]
        add rsp, 32
        LEAVE
.Lrm_asis:
        mov rax, rbx
        add rsp, 32
        LEAVE
ENDF replace_many

# replace_f(exp, f, arg) -> f applied bottom-up: the leaves through
# f(leaf, arg), then each rebuilt sequence through f as well
FUNC replace_f
        STACK_CHECK
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        call is_seq
        test eax, eax
        jnz 1f
        mov rdi, rbx
        mov rsi, r13
        call r12
        add rsp, 16
        LEAVE
1:      mov edi, [rbx + N_AUX]
        shl rdi, 3
        call arena_alloc
        mov [rsp], rax
        xor r14d, r14d
2:      cmp r14d, [rbx + N_AUX]
        jae 3f
        mov rdi, [rbx + N_DATA + r14*8]
        mov rsi, r12
        mov rdx, r13
        call replace_f
        mov rcx, [rsp]
        mov [rcx + r14*8], rax
        inc r14
        jmp 2b
3:      mov rdi, rbx
        mov rsi, [rsp]
        call mk_seq_like
        mov rdi, rax
        mov rsi, r13
        call r12
        add rsp, 16
        LEAVE
ENDF replace_f

# replace_f_memo(exp, f, arg) -> value: replace_f for an f that is a pure
# function of the expression it is given (simplify_exp, max_to_add...):
# a subtree met again - the trace is a DAG, hash-consed, and python walks
# it as a tree - gives what it gave the first time
FUNC replace_f_memo
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov rax, [r15 + CTX_RFM_MAP]    # the context's, emptied (an epoch)
        test rax, rax
        jnz 1f
        call emap_new
        mov [r15 + CTX_RFM_MAP], rax
1:      mov r14, rax
        mov rdi, rax
        call emap_begin
        mov rcx, r14
        mov rdi, rbx
        mov rsi, r12
        mov rdx, r13
        call rfm_walk
        LEAVE
ENDF replace_f_memo

# rfm_walk(exp, f, arg, map)
FUNC rfm_walk
        STACK_CHECK
        ENTER
        sub rsp, 32
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov [rsp + 8], rcx              # the memo: a sequence -> its result
        call is_seq
        test eax, eax
        jnz 1f
        mov rdi, rbx
        mov rsi, r13
        call r12
        add rsp, 32
        LEAVE
1:      mov rdi, [rsp + 8]
        mov rsi, rbx
        call emap_get
        test rax, rax
        jz 4f
        add rsp, 32
        LEAVE
4:      mov edi, [rbx + N_AUX]
        shl rdi, 3
        call arena_alloc_raw
        mov [rsp], rax
        xor r14d, r14d
2:      cmp r14d, [rbx + N_AUX]
        jae 3f
        mov rdi, [rbx + N_DATA + r14*8]
        mov rsi, r12
        mov rdx, r13
        mov rcx, [rsp + 8]
        call rfm_walk
        mov rcx, [rsp]
        mov [rcx + r14*8], rax
        inc r14
        jmp 2b
3:      mov rdi, rbx
        mov rsi, [rsp]
        call mk_seq_like
        mov rdi, rax
        mov rsi, r13
        call r12
        mov [rsp + 16], rax
        test rax, rax
        jz 5f                           # (NIL isn't remembered: done again)
        mov rdi, [rsp + 8]
        mov rsi, rbx
        mov rdx, rax
        call emap_put
5:      mov rax, [rsp + 16]
        add rsp, 32
        LEAVE
ENDF rfm_walk

# replace_f_stop(exp, f, arg) -> f(exp, arg) when it returns a value,
# else the sequence with its elements replaced (top-down, stopping at
# the first replacement)
FUNC replace_f_stop
        STACK_CHECK
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov rdi, rbx
        mov rsi, r13
        call r12
        test rax, rax
        jnz 4f
        mov rdi, rbx
        call is_seq
        test eax, eax
        jz 5f
        mov edi, [rbx + N_AUX]
        shl rdi, 3
        call arena_alloc
        mov [rsp], rax
        xor r14d, r14d
2:      cmp r14d, [rbx + N_AUX]
        jae 3f
        mov rdi, [rbx + N_DATA + r14*8]
        mov rsi, r12
        mov rdx, r13
        call replace_f_stop
        mov rcx, [rsp]
        mov [rcx + r14*8], rax
        inc r14
        jmp 2b
3:      mov rdi, rbx
        mov rsi, [rsp]
        call mk_seq_like
4:      add rsp, 16
        LEAVE
5:      mov rax, rbx
        add rsp, 16
        LEAVE
ENDF replace_f_stop

# find_op_list(exp, op, out): the sub-expressions with the opcode `op`,
# depth first (an expression found is not searched further). For 'var',
# the trees without the mention flag HF_VAR are skipped: cleanup_vars
# asks for the variables of the rest of the trace at every if.
FUNC find_op_list
        STACK_CHECK
        test dil, 1
        jnz 9f
        test rdi, rdi
        jz 9f
        mov eax, [rdi + N_KIND]
        sub eax, K_TUPLE
        cmp eax, K_LIST - K_TUPLE
        ja 9f                           # a leaf: not a sequence
        cmp esi, OP_VAR
        jne 1f
        mov rax, HF_VAR
        test [rdi + N_HASH], rax
        jz 9f                           # no 'var' in there
1:      ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        OPCODE_OF_RDI
        cmp eax, r12d
        jne 2f
        mov rdi, r13
        mov rsi, rbx
        call vec_push
        LEAVE
2:      xor r14d, r14d
3:      cmp r14d, [rbx + N_AUX]
        jae 4f
        mov rdi, [rbx + N_DATA + r14*8]
        inc r14
        test dil, 1
        jnz 3b                          # (the leaves, without a call)
        test rdi, rdi
        jz 3b
        mov eax, [rdi + N_KIND]
        sub eax, K_TUPLE
        cmp eax, K_LIST - K_TUPLE
        ja 3b
        mov rsi, r12
        mov rdx, r13
        call find_op_list
        jmp 3b
4:      LEAVE
9:      ret
ENDF find_op_list

        .section .note.GNU-stack,"",@progbits
