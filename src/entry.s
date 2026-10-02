# What the contract does before it gets to a function (port of the PR's
# loader.py: entry_paths and its helpers). The functions are decompiled
# from where the dispatcher jumps to them, but what the dispatcher did on
# the way still holds: the memory it wrote (the free memory pointer) and
# the checks it made. An entry is that, in order: the setmem lines, and
# ('check', cond, taken, other) for every if on the path whose other
# branch reverts - not the ones looking at the selector, the dispatch.

.include "defs.inc"

        .section .rodata
.Ls_cd0:        .asciz "('cd', 0)"
        .text

# is_marker(line) -> eax: python's is_marker - a string (a '?', the lines of
# assembly) or a ('jd', ...) line (leaf)
FUNC is_marker
        xor eax, eax
        test dil, 1
        jnz 1f
        test rdi, rdi
        jz 1f
        cmp dword ptr [rdi + N_KIND], K_STR
        je 2f
        OPCODE_OF_RDI
        cmp eax, OP_JD
        sete al
        movzx eax, al
1:      ret
2:      mov eax, 1
        ret
ENDF is_marker

# reverts(trace) -> eax: python's reverts - the trace (a list or a tuple)
# always reverts, without calling any function: its last line that isn't
# a marker reverts (or is invalid) with no funccall nor if before it, or is
# an if both of whose branches revert
FUNC reverts
        STACK_CHECK
        ENTER
        mov rbx, rdi
        # the last line that isn't a marker
        mov r12d, [rbx + N_AUX]
1:      test r12d, r12d
        jz .Lrv_no
        dec r12d
        mov rdi, [rbx + N_DATA + r12*8]
        call is_marker
        test eax, eax
        jnz 1b
        mov r13, [rbx + N_DATA + r12*8] # last
        mov rdi, r13
        OPCODE_OF_RDI
        cmp eax, OP_IF
        jne 3f
        cmp dword ptr [r13 + N_AUX], 4
        jb .Lrv_no                      # (python's IndexError)
        mov rdi, [r13 + N_DATA + 16]
        call reverts_seq
        test eax, eax
        jz .Lrv_no
        mov rdi, [r13 + N_DATA + 24]
        call reverts_seq
        LEAVE
3:      cmp eax, OP_REVERT
        je 4f
        cmp eax, OP_INVALID
        jne .Lrv_no
4:      # no funccall nor if before it (markers or not)
        xor r14d, r14d
5:      cmp r14d, r12d
        jae .Lrv_yes
        mov rdi, [rbx + N_DATA + r14*8]
        inc r14d
        OPCODE_OF_RDI
        cmp eax, OP_FUNCCALL
        je .Lrv_no
        cmp eax, OP_IF
        je .Lrv_no
        jmp 5b
.Lrv_yes:
        mov eax, 1
        LEAVE
.Lrv_no:
        xor eax, eax
        LEAVE
ENDF reverts

# reverts_seq(v) -> eax: reverts of a sequence (a branch that isn't one:
# python iterates it - the port says no)
FUNC reverts_seq
        STACK_CHECK
        IS_SEQ_RDI
        test eax, eax
        jz 1f
        jmp reverts
1:      ret
ENDF reverts_seq

# is_dispatch(cond) -> eax: python's is_dispatch - a condition on the
# selector (('cd', 0) in str(cond)), or on calldatasize being at least 4:
# every int and str in it (at any depth) is one of calldatasize, 3, 4, lt,
# gt, le, ge, iszero, bool
FUNC is_dispatch
        ENTER
        mov rbx, rdi
        LOADS rdi, CD
        mov esi, 1
        call mk2
        mov rdi, rbx
        mov rsi, rax
        call contains_value
        test eax, eax
        jnz 9f
        mov rdi, rbx                    # (or in a string)
        lea rsi, [rip + .Ls_cd0]
        call mentions_c
        test eax, eax
        jnz 9f
        mov rdi, rbx
        call dispatch_leaves
9:      LEAVE
ENDF is_dispatch

# dispatch_leaves(exp) -> eax: every int and str of exp, at any depth, is
# one of is_dispatch's
FUNC dispatch_leaves
        STACK_CHECK
        test dil, 1
        jnz .Ldl_small
        test rdi, rdi
        jz .Ldl_yes
        mov eax, [rdi + N_KIND]
        cmp eax, K_INT
        je .Ldl_no                      # (a big one: neither 3 nor 4)
        cmp eax, K_STR
        je .Ldl_str
        cmp eax, K_TUPLE
        je 1f
        cmp eax, K_LIST
        jne .Ldl_yes                    # (None, True...: not leaves)
1:      ENTER
        mov rbx, rdi
        xor r12d, r12d
2:      cmp r12d, [rbx + N_AUX]
        jae 3f
        mov rdi, [rbx + N_DATA + r12*8]
        inc r12d
        call dispatch_leaves
        test eax, eax
        jnz 2b
        LEAVE
3:      mov eax, 1
        LEAVE
.Ldl_small:
        cmp rdi, (3 << 1) | 1
        je .Ldl_yes
        cmp rdi, (4 << 1) | 1
        je .Ldl_yes
.Ldl_no:
        xor eax, eax
        ret
.Ldl_str:
        mov eax, [rdi + N_AUX]
        test eax, STR_FLOAT
        jnz .Ldl_yes                    # (a python float: not a leaf)
        and eax, STR_ID_MASK
        cmp eax, OP_CALLDATASIZE
        je .Ldl_yes
        cmp eax, OP_LT
        je .Ldl_yes
        cmp eax, OP_GT
        je .Ldl_yes
        cmp eax, OP_LE
        je .Ldl_yes
        cmp eax, OP_GE
        je .Ldl_yes
        cmp eax, OP_ISZERO
        je .Ldl_yes
        cmp eax, OP_BOOL
        jne .Ldl_no
.Ldl_yes:
        mov eax, 1
        ret
ENDF dispatch_leaves

# mentions_cd0(exp) -> eax: python's str(('cd', 0)) in str(exp)
FUNC mentions_cd0
        ENTER
        mov rbx, rdi
        LOADS rdi, CD
        mov esi, 1
        call mk2
        mov rdi, rbx
        mov rsi, rax
        call contains_value
        test eax, eax
        jnz 9f
        mov rdi, rbx
        lea rsi, [rip + .Ls_cd0]
        call mentions_c
9:      LEAVE
ENDF mentions_cd0

# selector_test(cond) -> rax: python's selector_test - the hash cond
# compares the selector with (rax, a number), rdx: whether cond holds when
# they're equal (1) or not (0); rax 0 (None) when it isn't a comparison of
# the selector. The dispatcher jumps to a function when the selector
# equals its hash, or past it when they differ: a difference (a sub, a
# xor), zero when they're equal.
FUNC selector_test
        STACK_CHECK
        ENTER
        sub rsp, 32
        mov rbx, rdi
        OPCODE_OF_RDI
        cmp eax, OP_ISZERO
        jne 1f
        cmp dword ptr [rbx + N_AUX], 2
        jb .Lst_none
        mov rdi, [rbx + N_DATA + 8]
        call selector_test
        test rax, rax
        jz .Lst_none
        xor edx, 1                      # (num, not taken)
        jmp .Lst_ret
1:      cmp eax, OP_AND
        je 2f
        cmp eax, OP_OR
        jne 5f
2:      # the selector is the hash and something else holds (Vyper's
        # dispatchers from 0.3.10: calldata.size > 3) - or, negated, it
        # isn't or something else doesn't: the function where it is. The
        # one test of the terms taken (and) or not (or).
        xor r12d, r12d
        cmp eax, OP_AND
        sete r12b                       # taken
        mov qword ptr [rsp], 0          # the test found
        mov qword ptr [rsp + 8], 0      # how many
        mov r13d, 1
3:      cmp r13d, [rbx + N_AUX]
        jae 4f
        mov rdi, [rbx + N_DATA + r13*8]
        inc r13d
        call selector_test
        test rax, rax
        jz 3b
        cmp edx, r12d
        jne 3b
        inc qword ptr [rsp + 8]
        mov [rsp], rax
        mov [rsp + 16], rdx
        jmp 3b
4:      cmp qword ptr [rsp + 8], 1
        jne .Lst_none
        mov rax, [rsp]
        mov rdx, [rsp + 16]
        jmp .Lst_ret
5:      cmp eax, OP_EQ
        je 6f
        cmp eax, OP_XOR
        jne .Lst_add
6:      cmp dword ptr [rbx + N_AUX], 3
        jne .Lst_add
        mov r12d, eax                   # eq or xor
        # (num, other) = (cond[1], cond[2]), then (cond[2], cond[1])
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, [rbx + N_DATA + 16]
        call .Lst_num_other
        test rax, rax
        jnz .Lst_ret
        mov rdi, [rbx + N_DATA + 16]
        mov rsi, [rbx + N_DATA + 8]
        call .Lst_num_other
        test rax, rax
        jnz .Lst_ret
.Lst_add:
        # ('add', num, other) with the selector in other: num - selector (a
        # ('mul', -1, selector)), or selector - (-num)
        mov rdi, rbx
        mov esi, OP_ADD
        mov edx, 3
        call is_op_n
        test eax, eax
        jz .Lst_none
        mov rdi, [rbx + N_DATA + 8]
        call int_or_bool
        test rax, rax
        jz .Lst_none
        mov r12, rax                    # num
        mov r13, [rbx + N_DATA + 16]    # other
        mov rdi, r13
        call mentions_cd0
        test eax, eax
        jz .Lst_none
        mov rdi, r13
        mov esi, OP_MUL
        mov edx, 3
        call is_op_n
        test eax, eax
        jz 7f
        cmp qword ptr [r13 + N_DATA + 8], -1    # ('mul', -1, selector)
        jne 7f
        mov r13, [r13 + N_DATA + 16]
        jmp 8f
7:      mov rdi, r12                    # -num % 2^256
        call int_neg
        mov rdi, rax
        mov esi, 256
        call int_mod_2exp
        mov r12, rax
8:      mov rdi, r12                    # num < 2^32
        mov rsi, (0x100000000 << 1) | 1
        call int_cmp
        cmp eax, 0
        jge .Lst_none
        mov rdi, r13
        call mentions_cd0
        test eax, eax
        jz .Lst_none
        mov rax, r12
        xor edx, edx
        jmp .Lst_ret
.Lst_none:
        xor eax, eax
        xor edx, edx
.Lst_ret:
        add rsp, 32
        LEAVE

# local: (num, other) of an eq or a xor (r12d) -> rax: num (a number) when
# other mentions the selector - rdx 1 for an eq; for a xor, num < 2^32,
# rdx 0 - else 0
.Lst_num_other:
        push r13
        push r14
        sub rsp, 8
        mov r13, rdi
        mov r14, rsi
        call is_int                     # (type(num) is int: no bool)
        test eax, eax
        jz 1f
        mov rdi, r14
        call mentions_cd0
        test eax, eax
        jz 1f
        mov rax, r13
        mov edx, 1
        cmp r12d, OP_EQ
        je 2f
        mov rdi, r13
        mov rsi, (0x100000000 << 1) | 1
        call int_cmp
        cmp eax, 0
        jge 1f
        mov rax, r13
        xor edx, edx
        jmp 2f
1:      xor eax, eax
2:      add rsp, 8
        pop r14
        pop r13
        ret
ENDF selector_test

# strip_markers(trace) -> list: python's strip_markers - the trace without
# its markers, in the branches of its ifs too
FUNC strip_markers
        STACK_CHECK
        ENTER
        mov rbx, rdi
        call vec_new
        mov r12, rax
        xor r13d, r13d
1:      cmp r13d, [rbx + N_AUX]
        jae 3f
        mov r14, [rbx + N_DATA + r13*8]
        inc r13d
        mov rdi, r14
        call is_marker
        test eax, eax
        jnz 1b
        mov rdi, r14
        mov esi, OP_IF
        mov edx, 4
        call is_op_n
        test eax, eax
        jz 2f
        mov rdi, [r14 + N_DATA + 16]
        call strip_markers
        push rax
        push rax
        mov rdi, [r14 + N_DATA + 24]
        call strip_markers
        mov rcx, rax
        pop rdx
        pop rdx
        mov rsi, [r14 + N_DATA + 8]
        LOADS rdi, IF
        call mk4
        mov r14, rax
2:      mov rdi, r12
        mov rsi, r14
        call vec_push
        jmp 1b
3:      mov rdi, r12
        call vec_to_list
        LEAVE
ENDF strip_markers

# entry_paths(trace, leaf, arg, entry, out): python's entry_paths - (entry,
# line) pairs pushed on out, for every line of the dispatcher's trace that
# is a leaf: leaf 0 a ('funccall', ...) line, 1 a ('jd', arg, ...) line
# (arg the string of a jumpdest). entry: what runs before (a tuple).
FUNC entry_paths
        STACK_CHECK
        ENTER
        sub rsp, 48
        .set EP_TRACE, 0
        .set EP_LEAF, 8
        .set EP_ARG, 16
        .set EP_ENTRY, 24
        .set EP_OUT, 32
        .set EP_I, 40
        mov [rsp + EP_TRACE], rdi
        mov [rsp + EP_LEAF], rsi
        mov [rsp + EP_ARG], rdx
        mov [rsp + EP_ENTRY], rcx
        mov [rsp + EP_OUT], r8
        mov qword ptr [rsp + EP_I], 0
.Lep_line:
        mov rax, [rsp + EP_TRACE]
        mov rcx, [rsp + EP_I]
        cmp ecx, [rax + N_AUX]
        jae .Lep_done
        mov rbx, [rax + N_DATA + rcx*8]
        inc qword ptr [rsp + EP_I]
        mov rdi, rbx
        OPCODE_OF_RDI
        mov r12d, eax
        # a leaf?
        cmp qword ptr [rsp + EP_LEAF], 0
        jne 1f
        cmp r12d, OP_FUNCCALL
        jne 2f
        jmp .Lep_leaf
1:      cmp r12d, OP_JD
        jne 2f
        cmp dword ptr [rbx + N_AUX], 2
        jb 2f
        mov rax, [rbx + N_DATA + 8]
        cmp rax, [rsp + EP_ARG]
        je .Lep_leaf
2:      cmp r12d, OP_SETMEM
        jne 3f
        mov rdi, [rsp + EP_ENTRY]
        mov rsi, rbx
        call tuple_append
        mov [rsp + EP_ENTRY], rax
        jmp .Lep_line
3:      cmp r12d, OP_IF
        jne .Lep_line
        cmp dword ptr [rbx + N_AUX], 4
        jne .Lep_line                   # (python's ValueError)
        # the branch taken, then the other: each with a check of the
        # condition when the other reverts (and it isn't the dispatch)
        mov r12d, 1
4:      mov r13, [rbx + N_DATA + 16]    # branch
        mov r14, [rbx + N_DATA + 24]    # other
        test r12d, r12d
        jnz 5f
        xchg r13, r14
5:      mov rdi, r14
        call reverts_seq
        test eax, eax
        jz 6f
        mov rdi, [rbx + N_DATA + 8]
        call is_dispatch
        test eax, eax
        jnz 6f
        mov rdi, r14                    # ('check', cond, taken, tuple(strip_markers(other)))
        call strip_markers
        mov rdi, rax
        call seq_to_tuple
        mov r8, rax
        lea rdx, [rip + sp_true]
        lea rax, [rip + sp_false]
        test r12d, r12d
        cmovz rdx, rax
        mov rcx, r8
        mov rsi, [rbx + N_DATA + 8]
        LOADS rdi, CHECK
        call mk4
        mov rdi, [rsp + EP_ENTRY]
        mov rsi, rax
        call tuple_append
        mov rcx, rax
        jmp 7f
6:      mov rcx, [rsp + EP_ENTRY]
7:      mov rdi, r13
        mov rsi, [rsp + EP_LEAF]
        mov rdx, [rsp + EP_ARG]
        mov r8, [rsp + EP_OUT]
        call entry_paths_seq
        dec r12d
        jz 4b
        jmp .Lep_line
.Lep_leaf:
        mov rdi, [rsp + EP_ENTRY]
        mov rsi, rbx
        call mk2
        mov rdi, [rsp + EP_OUT]
        mov rsi, rax
        call vec_push
        jmp .Lep_line
.Lep_done:
        add rsp, 48
        LEAVE
ENDF entry_paths

# entry_paths_seq(...): entry_paths of a branch that is a sequence
FUNC entry_paths_seq
        STACK_CHECK
        push rcx                        # (IS_SEQ_RDI changes rcx)
        IS_SEQ_RDI
        pop rcx
        test eax, eax
        jz 1f
        jmp entry_paths
1:      ret
ENDF entry_paths_seq


# apply_entry(entry, trace) -> list: python's apply_entry - the trace of a
# function, preceded by what runs before it: its setmems, and its checks
# as the ifs they are, around it
FUNC apply_entry
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov rdi, rsi
        call seq_to_list
        mov r12, rax                    # res
        mov r13d, [rbx + N_AUX]
1:      test r13d, r13d
        jz 9f
        dec r13d
        mov r14, [rbx + N_DATA + r13*8] # item
        mov rdi, r14
        OPCODE_OF_RDI
        cmp eax, OP_CHECK
        jne 3f
        mov rdi, [r14 + N_DATA + 24]    # list(other)
        call seq_to_list
        mov [rsp], rax
        mov rdi, [r14 + N_DATA + 16]    # taken: ('if', cond, res, other),
        call py_falsy                   # else ('if', cond, other, res)
        mov rdx, r12
        mov rcx, [rsp]
        test eax, eax
        jz 2f
        mov rdx, [rsp]
        mov rcx, r12
2:      mov rsi, [r14 + N_DATA + 8]
        LOADS rdi, IF
        call mk4
        mov [rsp], rax                  # [the if]
        mov edi, 1
        mov rsi, rsp
        call mk_list
        mov r12, rax
        jmp 1b
3:      # [item] + res
        mov edi, [r12 + N_AUX]
        inc edi
        shl edi, 3
        call arena_alloc_raw
        mov [rax], r14
        mov rcx, rax
        mov edx, [r12 + N_AUX]
        xor esi, esi
4:      cmp esi, edx
        jae 5f
        mov r8, [r12 + N_DATA + rsi*8]
        mov [rcx + rsi*8 + 8], r8
        inc esi
        jmp 4b
5:      lea edi, [edx + 1]
        mov rsi, rcx
        call mk_list
        mov r12, rax
        jmp 1b
9:      mov rax, r12
        add rsp, 16
        LEAVE
ENDF apply_entry

# entry_known(entry) -> tuple: python's entry_known - the conditions that
# hold once past the entry: of each check, its condition (taken) or its
# is_zero
FUNC entry_known
        ENTER
        mov rbx, rdi
        call vec_new
        mov r12, rax
        xor r13d, r13d
1:      cmp r13d, [rbx + N_AUX]
        jae 9f
        mov r14, [rbx + N_DATA + r13*8]
        inc r13d
        mov rdi, r14
        OPCODE_OF_RDI
        cmp eax, OP_CHECK
        jne 1b
        mov rdi, [r14 + N_DATA + 16]
        call py_falsy
        mov rdi, [r14 + N_DATA + 8]
        test eax, eax
        jz 2f
        call is_zero
        mov rdi, rax
2:      mov rsi, rdi
        mov rdi, r12
        call vec_push
        jmp 1b
9:      mov rdi, r12
        call vec_to_tuple
        LEAVE
ENDF entry_known

# common_entry(entries) -> tuple: python's common_entry - what all the
# given entries (a sequence of tuples) start with
FUNC common_entry
        ENTER
        mov rbx, rdi
        call vec_new
        mov r12, rax
        cmp dword ptr [rbx + N_AUX], 0
        je 9f
        xor r13d, r13d                  # the position
1:      # zip: as long as the shortest
        xor ecx, ecx
2:      cmp ecx, [rbx + N_AUX]
        jae 3f
        mov rax, [rbx + N_DATA + rcx*8]
        cmp r13d, [rax + N_AUX]
        jae 9f
        inc ecx
        jmp 2b
3:      mov rax, [rbx + N_DATA]
        mov r14, [rax + N_DATA + r13*8] # items[0]
        mov ecx, 1
4:      cmp ecx, [rbx + N_AUX]
        jae 5f
        mov rax, [rbx + N_DATA + rcx*8]
        mov rdi, [rax + N_DATA + r13*8]
        mov rsi, r14
        push rcx
        push rcx
        call py_equal
        pop rcx
        pop rcx
        test eax, eax
        jz 9f
        inc ecx
        jmp 4b
5:      mov rdi, r12
        mov rsi, r14
        call vec_push
        inc r13d
        jmp 1b
9:      mov rdi, r12
        call vec_to_tuple
        LEAVE
ENDF common_entry

        .section .note.GNU-stack,"",@progbits
