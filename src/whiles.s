# Loops -> whiles (port of whiles.py): the labels and gotos of the VM's
# trace become ('while', cond, body, jd, vars) and ('continue', jd,
# setvars) lines.

.include "defs.inc"

        .section .rodata
.Ls_logname:    .asciz "panoramix.whiles"
.Ls_no_if:      .asciz "no if after label?"

        .text

# make_whiles(trace, timeout_ns) -> list
FUNC make_whiles
        ENTER
        mov r12, rsi
        call whiles_make
        mov rbx, rax
        lea rdi, [rip + .Ls_loops_whiles]       # (explain.s)
        mov rsi, rax
        call explain
        mov rdi, rbx
        mov rbx, r12
        # clean up jumpdests
        lea rsi, [rip + drop_jumpdests]
        xor edx, edx
        call rewrite_trace
        mov rdi, rax
        mov rsi, rbx
        call simplify_trace
        LEAVE
ENDF make_whiles

        .section .rodata
.Ls_loops_whiles: .asciz "Loops -> whiles"
        .text

# drop_jumpdests(line, arg, out)
FUNC drop_jumpdests
        ENTER
        mov rbx, rdi
        mov r12, rdx
        call opcode_of
        cmp eax, OP_JUMPDEST
        je 1f
        mov rdi, r12
        mov rsi, rbx
        call vec_push
1:      LEAVE
ENDF drop_jumpdests

# whiles_make(trace) -> list: python's whiles.make - the labels become
# whiles, the gotos continues. A loop that can't be made fails the function
# (to_while's error goes through): without it, what follows the label would
# read as run once.
FUNC whiles_make
        STACK_CHECK
        ENTER
        sub rsp, 64                     # res, vars, before, inside, remaining, cond
        .set WM_RES, 0
        .set WM_TMP, 8
        .set WM_OUT, 16
        mov rbx, rdi
        call vec_new
        mov [rsp + WM_RES], rax
        xor r12d, r12d
.Lmk_line:
        cmp r12d, [rbx + N_AUX]
        jae .Lmk_done
        mov r13, [rbx + N_DATA + r12*8]
        mov rdi, r13
        call is_if_line
        test eax, eax
        jnz .Lmk_if
        mov rdi, r13
        call opcode_of
        cmp eax, OP_LABEL
        je .Lmk_label
        cmp eax, OP_GOTO
        je .Lmk_goto
.Lmk_asis:
        mov rdi, [rsp + WM_RES]
        mov rsi, r13
        call vec_push
.Lmk_next:
        inc r12
        jmp .Lmk_line
.Lmk_if:
        mov rdi, [r13 + N_DATA + 16]
        call whiles_make
        mov [rsp + WM_TMP], rax
        mov rdi, [r13 + N_DATA + 24]
        call whiles_make
        mov rdx, rax
        mov rsi, [rsp + WM_TMP]
        mov rdi, [r13 + N_DATA + 8]
        call mk_if
        mov rdi, [rsp + WM_RES]
        mov rsi, rax
        call vec_push
        jmp .Lmk_next
.Lmk_goto:
        cmp dword ptr [r13 + N_AUX], 3
        jne .Lmk_asis
        # ('continue', repr(jd), setvars)
        mov rdi, [r13 + N_DATA + 8]
        call str_of_value
        mov rsi, rax
        mov rdx, [r13 + N_DATA + 16]
        LOADS rdi, CONTINUE
        call mk3
        mov rdi, [rsp + WM_RES]
        mov rsi, rax
        call vec_push
        jmp .Lmk_next
.Lmk_label:
        cmp dword ptr [r13 + N_AUX], 3
        jb .Lmk_asis
        # before, inside, remaining, cond = to_while(trace[idx + 1:], jd,
        # begin, loop_vars)
        mov rdi, rbx
        lea rsi, [r12 + 1]
        call list_from
        mov rdi, rax
        mov rsi, [r13 + N_DATA + 8]
        lea rdx, [rsp + WM_OUT]         # -> before, inside, remaining, cond
        mov rcx, [r13 + N_DATA + 16]    # vars
        call to_while
        mov rdi, [rsp + WM_OUT + 8]
        call whiles_make
        mov [rsp + WM_OUT + 8], rax     # inside
        mov rdi, [rsp + WM_OUT + 16]
        call whiles_make
        mov [rsp + WM_OUT + 16], rax    # remaining
        # the loop variables take their initial values before the loop (all
        # at once)
        mov r14, [r13 + N_DATA + 16]    # vars
        mov rdi, r14
        call pairs_of_setvars
        mov rsi, rax
        mov rdi, [rsp + WM_OUT]
        call replace_vars
        mov rdi, rax
        call whiles_make
        mov rdi, [rsp + WM_RES]
        mov rsi, rax
        call vec_extend_seq
        # ('while', cond, inside, repr(jd), vars)
        mov rdi, [r13 + N_DATA + 8]
        call str_of_value
        mov rdx, rax
        mov rdi, [rsp + WM_OUT + 24]
        mov rsi, [rsp + WM_OUT + 8]
        mov rcx, r14
        call mk_while
        mov rdi, [rsp + WM_RES]
        mov rsi, rax
        call vec_push
        mov rdi, [rsp + WM_RES]
        mov rsi, [rsp + WM_OUT + 16]
        call vec_extend_seq
.Lmk_done:
        mov rdi, [rsp + WM_RES]
        call vec_to_list
        add rsp, 64
        LEAVE
ENDF whiles_make

# is_revert(trace) -> eax: a single revert/invalid line
FUNC is_revert
        ENTER
        cmp dword ptr [rdi + N_AUX], 1
        jne 1f
        mov rdi, [rdi + N_DATA]
        call opcode_of
        cmp eax, OP_REVERT
        je 2f
        cmp eax, OP_INVALID
        je 2f
1:      xor eax, eax
        LEAVE
2:      mov eax, 1
        LEAVE
ENDF is_revert

# collect_gotos(line, arg, out): the jd of a goto line
FUNC collect_gotos
        ENTER
        mov rbx, rdi
        mov r12, rdx
        call opcode_of
        cmp eax, OP_GOTO
        jne 1f
        cmp dword ptr [rbx + N_AUX], 2
        jb 1f
        mov rdi, r12
        mov rsi, [rbx + N_DATA + 8]
        call vec_push
1:      LEAVE
ENDF collect_gotos

# goes_to(trace, jd) -> eax: a goto to jd somewhere in the trace (python's
# `jd in find_f_list(trace, get_jds)`)
FUNC goes_to
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call vec_new
        mov r13, rax
        mov rdi, rbx
        lea rsi, [rip + collect_gotos]
        mov rdx, r13
        mov rcx, HF_GOTO                # (only where a "goto" is)
        call walk_collect_flag
        xor r14d, r14d
1:      cmp r14, [r13 + VEC_LEN]
        jae 2f
        mov rax, [r13 + VEC_DATA]
        cmp [rax + r14*8], r12
        je 3f
        inc r14
        jmp 1b
2:      xor eax, eax
        LEAVE
3:      mov eax, 1
        LEAVE
ENDF goes_to

# walk_collect_lines(exp, f, out): f(x, 0, out) for every tuple and list
# in exp, depth first (find_f_list with a collecting f)
FUNC walk_collect_lines
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        call is_seq
        test eax, eax
        jz 3f
        mov rdi, rbx
        xor esi, esi
        mov rdx, r13
        call r12
        xor r14d, r14d
2:      cmp r14d, [rbx + N_AUX]
        jae 3f
        mov rdi, [rbx + N_DATA + r14*8]
        mov rsi, r12
        mov rdx, r13
        call walk_collect_lines
        inc r14
        jmp 2b
3:      LEAVE
ENDF walk_collect_lines

# walk_collect_flag(exp, f, out, flag): walk_collect_lines' walk for an f
# that only finds the tuples of an opcode whose mention flag is `flag`:
# the tuples and lists without it are skipped (nothing there for f)
FUNC walk_collect_flag
        STACK_CHECK
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov [rsp], rcx
        call is_seq
        test eax, eax
        jz 3f
        mov rax, [rsp]
        test [rbx + N_HASH], rax
        jz 3f
        mov rdi, rbx
        xor esi, esi
        mov rdx, r13
        call r12
        xor r14d, r14d
2:      cmp r14d, [rbx + N_AUX]
        jae 3f
        mov rdi, [rbx + N_DATA + r14*8]
        mov rsi, r12
        mov rdx, r13
        mov rcx, [rsp]
        call walk_collect_flag
        inc r14
        jmp 2b
3:      add rsp, 16
        LEAVE
ENDF walk_collect_flag

# --- what the lines before a loop's exit condition do ---

# falls_through(trace) -> eax: python's falls_through - a path of trace gets
# to its end: goes on with what follows it, rather than to a label (goto) or
# out of the call
FUNC falls_through
        STACK_CHECK
        ENTER
        mov rbx, rdi
        call seq_last
        test rax, rax
        jz 8f
        mov r12, rax
        mov rdi, rax
        OPCODE_OF_RDI
        cmp eax, OP_IF
        jne 2f
        cmp dword ptr [r12 + N_AUX], 4
        jb .Lft_index
        mov rdi, [r12 + N_DATA + 16]
        call falls_through
        test eax, eax
        jnz 8f
        mov rdi, [r12 + N_DATA + 24]
        call falls_through
        LEAVE
2:      cmp eax, OP_GOTO
        je 9f
        cmp eax, OP_UNDEFINED
        je 9f
        cmp eax, OP_LEAVE
        je 9f
        mov edi, eax
        call is_ends_execution_op
        test eax, eax
        jnz 9f
8:      mov eax, 1
        LEAVE
9:      xor eax, eax
        LEAVE
.Lft_index:
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_wl_index]
        call err_throw
ENDF falls_through

        OPSET_MEMBER pure_lines, OP_SETVAR
        OPSET_MEMBER pure_lines, OP_IF
        OPSET_MEMBER pure_lines, OP_WHILE
        OPSET_MEMBER pure_lines, OP_LABEL
        OPSET_MEMBER pure_lines, OP_GOTO
        OPSET_MEMBER pure_lines, OP_CONTINUE
        OPSET_MEMBER pure_lines, OP_JUMP
        OPSET_MEMBER pure_lines, OP_JUMPDEST
        OPSET_MEMBER pure_lines, OP_UNDEFINED
        OPSET_MEMBER pure_lines, OP_LEAVE
        OPSET_MEMBER pure_lines, OP_LOG
        OPSET_MEMBER pure_lines, OP_REVERT
        OPSET_MEMBER pure_lines, OP_RETURN
        OPSET_MEMBER pure_lines, OP_STOP
        OPSET_MEMBER pure_lines, OP_INVALID
        OPSET_MEMBER pure_lines, OP_ASSERT_FAIL
        OPSET_MEMBER pure_lines, OP_SELFDESTRUCT
        OPSET_END pure_lines, OP_COUNT

# wl_writes(trace) -> eax: python's whiles.writes - trace may change what an
# expression reads: memory, storage... (a line other than the PURE_LINES)
FUNC wl_writes
        STACK_CHECK
        ENTER
        mov rbx, rdi
        IS_SEQ_RDI
        test eax, eax
        jz .Lww_type
        xor r12d, r12d
1:      cmp r12d, [rbx + N_AUX]
        jae 8f
        mov r13, [rbx + N_DATA + r12*8]
        inc r12d
        mov rdi, r13
        call is_list
        test eax, eax
        jz 2f
        mov rdi, r13
        call wl_writes
        test eax, eax
        jnz 9f
        jmp 1b
2:      mov rdi, r13
        OPCODE_OF_RDI
        cmp eax, OP_IF
        je 3f
        cmp eax, OP_WHILE
        je 4f
        mov r14d, eax
        mov rdi, r13
        call is_tuple
        test eax, eax
        jz 1b
        IN_OPSET pure_lines, r14
        je 9f
        jmp 1b
3:      cmp dword ptr [r13 + N_AUX], 4
        jb .Lww_index
        mov rdi, [r13 + N_DATA + 16]
        call wl_writes
        test eax, eax
        jnz 9f
        mov rdi, [r13 + N_DATA + 24]
        call wl_writes
        test eax, eax
        jnz 9f
        jmp 1b
4:      cmp dword ptr [r13 + N_AUX], 3
        jb .Lww_index
        mov rdi, [r13 + N_DATA + 16]
        call wl_writes
        test eax, eax
        jnz 9f
        jmp 1b
8:      xor eax, eax
        LEAVE
9:      mov eax, 1
        LEAVE
.Lww_index:
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_wl_index]
        call err_throw
.Lww_type:
        mov edi, E_TYPE
        lea rsi, [rip + .Ls_wl_type]
        call err_throw
ENDF wl_writes

# collect_setvar_name(e, arg, out): wl_sets' f - the name of a setvar
# (python's [e[1]] for an e of opcode setvar), once
FUNC collect_setvar_name
        ENTER
        mov rbx, rdi
        mov r12, rdx
        OPCODE_OF_RDI
        cmp eax, OP_SETVAR
        jne 1f
        cmp dword ptr [rbx + N_AUX], 2
        jb .Lcs_index
        mov rdi, r12
        mov rsi, [rbx + N_DATA + 8]
        call vec_push_unique
1:      LEAVE
.Lcs_index:
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_wl_index]
        call err_throw
ENDF collect_setvar_name

# wl_sets(trace) -> vec: python's whiles.sets - the variables trace sets, at
# any depth
FUNC wl_sets
        ENTER
        mov rbx, rdi
        call vec_new
        mov r12, rax
        mov rdi, rbx
        lea rsi, [rip + collect_setvar_name]
        mov rdx, r12
        mov rcx, HF_SETVAR
        call walk_collect_flag
        mov rax, r12
        LEAVE
ENDF wl_sets

# wl_reads_any(exp, names) -> eax: a ('var', name) of one of the names (a
# vec) anywhere in exp (python's whiles.reads, of a name or a set of them)
FUNC wl_reads_any
        STACK_CHECK
        test dil, 1
        jnz 8f
        test rdi, rdi
        jz 8f
        mov eax, [rdi + N_KIND]
        cmp eax, K_TUPLE
        je 1f
        cmp eax, K_LIST
        jne 8f
1:      movabs rcx, HF_VAR
        test [rdi + N_HASH], rcx
        jz 8f                           # (no ('var', ...) in it)
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov rdi, rbx
        mov esi, OP_VAR
        mov edx, 2
        call is_op_n
        test eax, eax
        jz 2f
        mov rdi, r12
        mov rsi, [rbx + N_DATA + 8]
        call vec_contains
        test eax, eax
        jnz 9f
2:      xor r13d, r13d
3:      cmp r13d, [rbx + N_AUX]
        jae 7f
        mov rdi, [rbx + N_DATA + r13*8]
        inc r13d
        mov rsi, r12
        call wl_reads_any
        test eax, eax
        jz 3b
9:      mov eax, 1
        LEAVE
7:      xor eax, eax
        LEAVE
8:      xor eax, eax
        ret
ENDF wl_reads_any

# wl_reads(trace, name) -> eax: python's whiles.reads - trace reads the
# variable
FUNC wl_reads
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call vec_new
        mov r13, rax
        mov rdi, rax
        mov rsi, r12
        call vec_push
        mov rdi, rbx
        mov rsi, r13
        call wl_reads_any
        LEAVE
ENDF wl_reads

# evaluated_after(path, values) -> eax: python's evaluated_after - the
# values (of loop variables, a list) are the same evaluated after path as
# before it: none reads a variable path sets, nor what it may write
FUNC evaluated_after
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call wl_sets
        mov rdi, r12
        mov rsi, rax
        call wl_reads_any
        test eax, eax
        jnz 9f
        mov rdi, rbx
        call wl_writes
        test eax, eax
        jz 8f
        xor r13d, r13d
1:      cmp r13d, [r12 + N_AUX]
        jae 8f
        mov rdi, [r12 + N_DATA + r13*8]
        inc r13d
        call is_volatile
        test eax, eax
        jz 1b
9:      xor eax, eax
        LEAVE
8:      mov eax, 1
        LEAVE
ENDF evaluated_after

# collect_goto_values(e, jd, out): tw_rotates' f - the values of the setvars
# of a ('goto', jd, setvars)
FUNC collect_goto_values
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov esi, OP_GOTO
        mov edx, 3
        call is_op_n
        test eax, eax
        jz 9f
        cmp [rbx + N_DATA + 8], r12
        jne 9f
        mov rbx, [rbx + N_DATA + 16]
        mov rdi, rbx
        IS_SEQ_RDI
        test eax, eax
        jz .Lcg_type
        xor r14d, r14d
1:      cmp r14d, [rbx + N_AUX]
        jae 9f
        mov rax, [rbx + N_DATA + r14*8]
        inc r14d
        test al, 1
        jnz .Lcg_type
        cmp dword ptr [rax + N_KIND], K_TUPLE
        jne .Lcg_type
        cmp dword ptr [rax + N_AUX], 3
        jne .Lcg_unpack
        mov rdi, r13
        mov rsi, [rax + N_DATA + 16]
        call vec_push
        jmp 1b
9:      LEAVE
.Lcg_unpack:
        mov edi, E_VALUE
        lea rsi, [rip + .Ls_wl_unpack]
        call err_throw
.Lcg_type:
        mov edi, E_TYPE
        lea rsi, [rip + .Ls_wl_type]
        call err_throw
ENDF collect_goto_values

# walk_goto_values(exp, jd, out): the walk of collect_goto_values (where a
# "goto" is), the jd passed along
FUNC walk_goto_values
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        IS_SEQ_RDI
        test eax, eax
        jz 3f
        movabs rax, HF_GOTO
        test [rbx + N_HASH], rax
        jz 3f
        mov rdi, rbx
        mov rsi, r12
        mov rdx, r13
        call collect_goto_values
        xor r14d, r14d
2:      cmp r14d, [rbx + N_AUX]
        jae 3f
        mov rdi, [rbx + N_DATA + r14*8]
        inc r14d
        mov rsi, r12
        mov rdx, r13
        call walk_goto_values
        jmp 2b
3:      LEAVE
ENDF walk_goto_values

# tw_rotates(body, path, jd, begin) -> eax: to_while's rotates - the lines
# before the exit condition (path, a list) can be done before the loop,
# with the values the loop starts with (begin), and at the end of each
# iteration that goes on (add_path), with the values of the next one: the
# variables are set after them then (the while's, a continue's). The values
# have to be the same evaluated there: `prev = index + n` with index read in
# the body, read again there, is the next one. And a continue in the lines
# would be before the loop.
FUNC tw_rotates
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov r14, rcx
        call vec_new
        push rax
        push rax
        mov rdi, rbx
        mov rsi, r13
        mov rdx, rax
        call walk_goto_values           # nexts
        mov rdi, [rsp]
        mov rsi, r14
        call vec_extend_seq             # nexts + list(begin)
        mov rdi, r12
        mov rsi, r13
        call goes_to
        test eax, eax
        jnz 9f
        mov rdi, [rsp]
        call vec_to_list
        mov rsi, rax
        mov rdi, r12
        call evaluated_after
        add rsp, 16
        LEAVE
9:      xor eax, eax
        add rsp, 16
        LEAVE
ENDF tw_rotates

# exit_values(out, body, after, loop_vars) -> rax, rdx: python's
# exit_values - `out` is the branch of a loop's exit condition, `body` the
# other one, and `after` what both go on with: the exit and the breaks of
# the body merged (see vm.merge_branches), each setting the variables of the
# merge for what differs on the stack - what a break leaves there, a local
# of the body in solc 0.4, which keeps its previous value on the exit.
# (body, after) for out written as nothing, rax 0 (None) if it can't be:
# each variable it sets has to be one that `after` doesn't read, or one it
# sets to a loop variable, that `after` doesn't read otherwise - which
# stands for it then, the breaks setting it instead.
FUNC exit_values
        ENTER
        sub rsp, 48
        .set EV_BODY, 0
        .set EV_AFTER, 8
        .set EV_VARS, 16
        .set EV_RENAMES, 24
        .set EV_PAIRS, 32
        mov rbx, rdi
        mov [rsp + EV_BODY], rsi
        mov [rsp + EV_AFTER], rdx
        mov [rsp + EV_VARS], rcx
        call vec_new
        mov [rsp + EV_RENAMES], rax     # flat pairs name, loop variable
        mov rdi, rbx
        IS_SEQ_RDI
        test eax, eax
        jz .Lev_type
        xor r12d, r12d
1:      cmp r12d, [rbx + N_AUX]
        jae 5f
        mov r13, [rbx + N_DATA + r12*8]
        inc r12d
        mov rdi, r13
        OPCODE_OF_RDI
        cmp eax, OP_SETVAR
        jne .Lev_none
        cmp dword ptr [r13 + N_AUX], 3
        jne .Lev_unpack
        mov rdi, [rsp + EV_AFTER]
        mov rsi, [r13 + N_DATA + 8]
        call wl_reads
        test eax, eax
        jz 1b                           # (not read after: as it is)
        mov r14, [r13 + N_DATA + 16]    # value: a loop variable...
        mov rdi, r14
        mov esi, OP_VAR
        mov edx, 2
        call is_op_n
        test eax, eax
        jz .Lev_none
        mov r14, [r14 + N_DATA + 8]
        mov rdi, [rsp + EV_VARS]
        mov rsi, r14
        call seq_contains
        test eax, eax
        jz .Lev_none
        mov rax, [rsp + EV_RENAMES]     # ... not one renamed already
        xor ecx, ecx
2:      cmp rcx, [rax + VEC_LEN]
        jae 3f
        mov rdx, [rax + VEC_DATA]
        cmp r14, [rdx + rcx*8 + 8]
        je .Lev_none
        add rcx, 2
        jmp 2b
3:      mov rdi, [rsp + EV_AFTER]       # ... after doesn't read, nor sets
        mov rsi, r14
        call wl_reads
        test eax, eax
        jnz .Lev_none
        mov rdi, [rsp + EV_AFTER]
        call wl_sets
        mov rdi, rax
        mov rsi, r14
        call vec_contains
        test eax, eax
        jnz .Lev_none
        # renames[name] = value[1]
        mov rax, [rsp + EV_RENAMES]
        xor ecx, ecx
4:      cmp rcx, [rax + VEC_LEN]
        jae 41f
        mov rdx, [rax + VEC_DATA]
        mov rsi, [r13 + N_DATA + 8]
        cmp rsi, [rdx + rcx*8]
        je 42f
        add rcx, 2
        jmp 4b
42:     mov [rdx + rcx*8 + 8], r14
        jmp 1b
41:     mov rdi, rax
        mov rsi, [r13 + N_DATA + 8]
        call vec_push
        mov rdi, [rsp + EV_RENAMES]
        mov rsi, r14
        call vec_push
        jmp 1b
5:      mov rax, [rsp + EV_RENAMES]
        cmp qword ptr [rax + VEC_LEN], 0
        jne 6f
        mov rax, [rsp + EV_BODY]
        mov rdx, [rsp + EV_AFTER]
        add rsp, 48
        LEAVE
6:      # {name: ('var', loop variable)} for replace_vars
        call vec_new
        mov [rsp + EV_PAIRS], rax
        mov rbx, [rsp + EV_RENAMES]
        xor r12d, r12d
7:      cmp r12, [rbx + VEC_LEN]
        jae 8f
        mov rax, [rbx + VEC_DATA]
        mov rdi, [rsp + EV_PAIRS]
        mov rsi, [rax + r12*8]
        call vec_push
        mov rax, [rbx + VEC_DATA]
        mov rsi, [rax + r12*8 + 8]
        LOADS rdi, VAR
        call mk2
        mov rdi, [rsp + EV_PAIRS]
        mov rsi, rax
        call vec_push
        add r12, 2
        jmp 7b
8:      mov rdi, [rsp + EV_BODY]
        call .Lev_renamed
        mov [rsp + EV_BODY], rax
        mov rdi, [rsp + EV_AFTER]
        call .Lev_renamed
        mov rdx, rax
        mov rax, [rsp + EV_BODY]
        add rsp, 48
        LEAVE
.Lev_none:
        xor eax, eax
        xor edx, edx
        add rsp, 48
        LEAVE
.Lev_unpack:
        mov edi, E_VALUE
        lea rsi, [rip + .Ls_wl_unpack]
        call err_throw
.Lev_type:
        mov edi, E_TYPE
        lea rsi, [rip + .Ls_wl_type]
        call err_throw
# renamed(trace) -> rax: the variables renamed, and their setvars
.Lev_renamed:
        sub rsp, 8
        mov rsi, [rsp + 16 + EV_PAIRS]
        call replace_vars
        mov rdi, rax
        lea rsi, [rip + ev_rename_f]
        mov rdx, [rsp + 16 + EV_RENAMES]
        call replace_f
        add rsp, 8
        ret
ENDF exit_values

# ev_rename_f(e, renames): exit_values' rename - a setvar of a renamed
# variable sets the variable it's renamed to
FUNC ev_rename_f
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov esi, OP_SETVAR
        mov edx, 3
        call is_op_n
        test eax, eax
        jz 9f
        xor ecx, ecx
1:      cmp rcx, [r12 + VEC_LEN]
        jae 9f
        mov rdx, [r12 + VEC_DATA]
        mov rax, [rdx + rcx*8]
        cmp rax, [rbx + N_DATA + 8]
        je 2f
        add rcx, 2
        jmp 1b
2:      mov rsi, [rdx + rcx*8 + 8]
        mov rdx, [rbx + N_DATA + 16]
        LOADS rdi, SETVAR
        call mk3
        LEAVE
9:      mov rax, rbx
        LEAVE
ENDF ev_rename_f

# seq_contains(seq, x) -> eax: x among the elements (by value)
FUNC seq_contains
        ENTER
        mov rbx, rdi
        mov r12, rsi
        xor r13d, r13d
1:      cmp r13d, [rbx + N_AUX]
        jae 2f
        mov rdi, [rbx + N_DATA + r13*8]
        inc r13d
        mov rsi, r12
        call values_equal
        test eax, eax
        jz 1b
        mov eax, 1
        LEAVE
2:      xor eax, eax
        LEAVE
ENDF seq_contains

# add_path(line, ctx, out): rewrite_trace's f in to_while (ctx: [path, jd])
# - a goto to the loop's label gets the lines preceding the exit condition
# in front of it, with the values of the next iteration (all at once), as
# they are executed again before it. A continue of an outer loop leaves
# this one: as it is.
FUNC add_path
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov esi, OP_GOTO
        mov edx, 3
        call is_op_n
        test eax, eax
        jz 3f
        mov rax, [rbx + N_DATA + 8]
        cmp rax, [r12 + 8]
        jne 3f
        mov rdi, [rbx + N_DATA + 16]
        call pairs_of_setvars
        mov rsi, rax
        mov rdi, [r12]
        call replace_vars
        mov rdi, r13
        mov rsi, rax
        call vec_extend_seq
3:      mov rdi, r13
        mov rsi, rbx
        call vec_push
        LEAVE
ENDF add_path

# to_while(trace, jd, out, vars): python's to_while - `trace` is what
# follows a loop label, `jd` the label, vars its setvars (the values of
# the loop variables at the start, `begin`, and their names, `loop_vars`).
# Fills out[0..3] with (before, inside, remaining, cond) so that the loop
# can be written as: before; while cond: inside; remaining
FUNC to_while
        ENTER
        sub rsp, 112
        .set TW_JD, 0
        .set TW_OUT, 8
        .set TW_BEGIN, 16
        .set TW_VARS, 24
        .set TW_BEFORE, 32
        .set TW_INSIDE, 40
        .set TW_REMAINING, 48
        .set TW_COND, 56
        .set TW_T, 64                   # jd in jds_true
        .set TW_F, 72                   # jd in jds_false
        .set TW_BODY, 80
        .set TW_OUTB, 88                # the exit branch
        .set TW_CTX, 96                 # add_path's: path, jd
        mov [rsp + TW_JD], rsi
        mov [rsp + TW_OUT], rdx
        mov r13, rdi                    # what's left of the trace (a list)
        # begin = [v_val for _, _, v_val in vars], loop_vars = [v_idx ...]
        mov rbx, rcx
        call vec_new
        mov r12, rax
        call vec_new
        mov r14, rax
        xor ecx, ecx
1:      cmp ecx, [rbx + N_AUX]
        jae 2f
        mov rax, [rbx + N_DATA + rcx*8]
        inc ecx
        push rcx
        push rcx
        cmp dword ptr [rax + N_AUX], 3
        jne .Ltw_unpack
        mov [rsp], rax
        mov rdi, r12
        mov rsi, [rax + N_DATA + 16]
        call vec_push
        mov rax, [rsp]
        mov rdi, r14
        mov rsi, [rax + N_DATA + 8]
        call vec_push
        pop rcx
        pop rcx
        jmp 1b
2:      mov rdi, r12
        call vec_to_list
        mov [rsp + TW_BEGIN], rax
        mov rdi, r14
        call vec_to_list
        mov [rsp + TW_VARS], rax
        xor r14d, r14d                  # position in the trace
        call vec_new
        mov rbx, rax                    # path: the lines seen so far
.Ltw_line:
        cmp r14d, [r13 + N_AUX]
        jae .Ltw_no_if
        mov r12, [r13 + N_DATA + r14*8]
        inc r14
        mov rdi, r12
        call is_if_line
        test eax, eax
        jnz .Ltw_if
        mov rdi, r12
        call opcode_of
        cmp eax, OP_LABEL
        je .Ltw_label
        cmp eax, OP_GOTO
        jne .Ltw_path
        cmp dword ptr [r12 + N_AUX], 2
        jb .Ltw_path
        mov rax, [r12 + N_DATA + 8]
        cmp rax, [rsp + TW_JD]
        jne .Ltw_path
        # the path loops back unconditionally: the exits, if any, are the
        # reverts and returns along the way - the loop as it is (the lines
        # before done again after it would skip the first iteration's)
        jmp .Ltw_as_is
.Ltw_label:
        # a loop in this one, before its exit condition (Vyper tests it at
        # the end): the rest of the trace is that loop, and what follows it,
        # where this one goes on or ends. ([], path + [line] + trace, [],
        # True)
        mov rdi, rbx
        mov rsi, r12
        call vec_push
        call .Ltw_rest
        mov rdi, rbx
        mov rsi, rax
        call vec_extend_seq
        mov rdi, rbx
        call vec_to_list
        mov [rsp + TW_INSIDE], rax
        call .Ltw_empty
        mov [rsp + TW_REMAINING], rax
        call .Ltw_empty
        mov [rsp + TW_BEFORE], rax
        call .Ltw_true
        mov [rsp + TW_COND], rax
        jmp .Ltw_return
.Ltw_path:
        mov rdi, rbx
        mov rsi, r12
        call vec_push
        jmp .Ltw_line
.Ltw_if:
        # `trace` is what comes after the if - if its branches merge again
        # (see vm.merge_branches), that's what follows on the merged path.
        # Nothing otherwise.
        #
        # a branch that reverts is a check on the way to the exit
        # condition, kept as it is: a require would drop the data of the
        # revert (a Panic code, a message), and tell an invalid from a
        # revert no more
        mov rdi, [r12 + N_DATA + 16]
        call is_revert
        test eax, eax
        jz 1f
        call .Ltw_empty                 # ('if', cond, if_true, [])
        mov rcx, rax
        mov rdx, [r12 + N_DATA + 16]
        mov rsi, [r12 + N_DATA + 8]
        LOADS rdi, IF
        call mk4
        mov rdi, rbx
        mov rsi, rax
        call vec_push
        mov rdi, [r12 + N_DATA + 24]
        call .Ltw_prepend
        jmp .Ltw_line
1:      mov rdi, [r12 + N_DATA + 24]
        call is_revert
        test eax, eax
        jz 2f
        mov rdi, [r12 + N_DATA + 8]     # ('if', not cond, if_false, [])
        call is_zero
        mov [rsp + TW_COND], rax
        call .Ltw_empty
        mov rcx, rax
        mov rdx, [r12 + N_DATA + 24]
        mov rsi, [rsp + TW_COND]
        LOADS rdi, IF
        call mk4
        mov rdi, rbx
        mov rsi, rax
        call vec_push
        mov rdi, [r12 + N_DATA + 16]
        call .Ltw_prepend
        jmp .Ltw_line
2:      mov rdi, [r12 + N_DATA + 16]
        mov rsi, [rsp + TW_JD]
        call goes_to
        mov [rsp + TW_T], rax           # jd in jds_true
        mov rdi, [r12 + N_DATA + 24]
        mov rsi, [rsp + TW_JD]
        call goes_to
        mov [rsp + TW_F], rax           # jd in jds_false
        mov eax, r14d
        cmp eax, [r13 + N_AUX]
        jae .Ltw_last                   # nothing follows the if
        mov rax, [rsp + TW_T]
        or rax, [rsp + TW_F]
        jz .Ltw_stmt
        call .Ltw_rest
        mov rdi, rax
        mov rsi, [rsp + TW_JD]
        call goes_to
        test eax, eax
        jnz .Ltw_stmt
        # The branches merge again, but the loop doesn't go on after that:
        # what follows the if is where the loop ends up when it is left -
        # by the exit condition, a break, a return from inside it... The if
        # is the body of the loop, which it leaves when it doesn't
        # continue, and that follows it.
        mov rax, [rsp + TW_T]
        cmp rax, [rsp + TW_F]
        je .Ltw_as_is
        call .Ltw_body_out
        call .Ltw_rest
        mov rdx, rax
        mov rdi, [rsp + TW_OUTB]
        mov rsi, [rsp + TW_BODY]
        mov rcx, [rsp + TW_VARS]
        call exit_values
        test rax, rax
        jz .Ltw_as_is
        mov [rsp + TW_INSIDE], rax      # (body, trace) = exits
        mov [rsp + TW_REMAINING], rdx
        mov rdi, [rsp + TW_BODY]
        call .Ltw_rotates
        test eax, eax
        jz .Ltw_as_is
        # An exit condition, and the paths of the body that get to its end
        # are breaks (see prettify.add_breaks): all go on with what follows
        # the if - its other branch, written as nothing (see exit_values).
        mov rax, [r12 + N_DATA + 8]
        cmp qword ptr [rsp + TW_T], 0
        jne 3f
        mov rdi, rax
        call is_zero
3:      mov [rsp + TW_COND], rax
        mov rdi, [rsp + TW_INSIDE]
        call .Ltw_rewrite_with_path
        mov [rsp + TW_INSIDE], rax
        mov rdi, rbx
        call vec_to_list
        mov [rsp + TW_BEFORE], rax
        jmp .Ltw_return
.Ltw_stmt:
        # The branches merge again and the loop goes on after that: a
        # statement of the loop body (a goto inside it is a `continue`),
        # not the exit condition, which is the last thing on its path.
        mov rdi, rbx
        mov rsi, r12
        call vec_push
        jmp .Ltw_line
.Ltw_last:
        mov rax, [rsp + TW_T]
        or rax, [rsp + TW_F]
        jz .Ltw_stmt
        cmp qword ptr [rsp + TW_T], 0
        je 4f
        cmp qword ptr [rsp + TW_F], 0
        # the loop goes on whichever way the if goes - if it can be left at
        # all, it's from inside the branches (a return, or an if with an
        # exit of its own)
        jne .Ltw_as_is
4:      call .Ltw_body_out
        # A path of the body gets to its end: it leaves the loop - a break,
        # an early return (solc's return code, shared) - and goes on with
        # what follows the if, not with the exit branch. After a `while
        # cond:`, it would.
        mov rax, [rsp + TW_OUTB]
        cmp dword ptr [rax + N_AUX], 0
        je 5f
        mov rdi, [rsp + TW_BODY]
        call falls_through
        test eax, eax
        jnz .Ltw_as_is
5:      mov rdi, [rsp + TW_BODY]
        call .Ltw_rotates
        test eax, eax
        jz .Ltw_as_is                   # the loop as it is: its exit inside
        # (path, add_path(body), out + rest, cond or not cond)
        mov rdi, [rsp + TW_BODY]
        call .Ltw_rewrite_with_path
        mov [rsp + TW_INSIDE], rax
        call .Ltw_rest
        mov rdi, [rsp + TW_OUTB]
        mov rsi, rax
        call list_concat
        mov [rsp + TW_REMAINING], rax
        mov rax, [r12 + N_DATA + 8]
        cmp qword ptr [rsp + TW_T], 0
        jne 6f
        mov rdi, rax
        call is_zero
6:      mov [rsp + TW_COND], rax
        mov rdi, rbx
        call vec_to_list
        mov [rsp + TW_BEFORE], rax
        jmp .Ltw_return
.Ltw_as_is:
        # ([], path + [line], rest, True)
        call .Ltw_rest
        mov [rsp + TW_REMAINING], rax
        mov rdi, rbx
        mov rsi, r12
        call vec_push
        mov rdi, rbx
        call vec_to_list
        mov [rsp + TW_INSIDE], rax
        call .Ltw_empty
        mov [rsp + TW_BEFORE], rax
        call .Ltw_true
        mov [rsp + TW_COND], rax
.Ltw_return:
        mov rdi, [rsp + TW_OUT]
        mov rax, [rsp + TW_BEFORE]
        mov [rdi], rax
        mov rax, [rsp + TW_INSIDE]
        mov [rdi + 8], rax
        mov rax, [rsp + TW_REMAINING]
        mov [rdi + 16], rax
        mov rax, [rsp + TW_COND]
        mov [rdi + 24], rax
        add rsp, 112
        LEAVE
.Ltw_no_if:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_no_if]
        call err_throw
.Ltw_unpack:
        mov edi, E_VALUE
        lea rsi, [rip + .Ls_wl_unpack]
        call err_throw

# local: rax = what's left of the trace, as a list
.Ltw_rest:
        sub rsp, 8
        mov rdi, r13
        mov rsi, r14
        call list_from
        add rsp, 8
        ret

# local: rax = []
.Ltw_empty:
        sub rsp, 8
        xor edi, edi
        xor esi, esi
        call mk_list
        add rsp, 8
        ret

# local: rax = ('bool', 1)
.Ltw_true:
        sub rsp, 8
        LOADS rdi, BOOL
        mov esi, 3
        call mk2
        add rsp, 8
        ret

# local: TW_BODY, TW_OUTB := the branch that goes on at the label, and the
# other one (r12 the if)
.Ltw_body_out:
        mov rax, [r12 + N_DATA + 16]
        mov rcx, [r12 + N_DATA + 24]
        cmp qword ptr [rsp + 8 + TW_T], 0
        jne 1f
        xchg rax, rcx
1:      mov [rsp + 8 + TW_BODY], rax
        mov [rsp + 8 + TW_OUTB], rcx
        ret

# local: eax = rotates(rdi) (the path so far, the jd, begin)
.Ltw_rotates:
        sub rsp, 24
        mov [rsp], rdi
        mov rdi, rbx
        call vec_to_list
        mov rsi, rax
        mov rdi, [rsp]
        mov rdx, [rsp + 32 + TW_JD]
        mov rcx, [rsp + 32 + TW_BEGIN]
        call tw_rotates
        add rsp, 24
        ret

# local: trace := branch + what's left
.Ltw_prepend:
        sub rsp, 24
        mov [rsp], rdi
        call .Ltw_rest
        mov rdi, [rsp]
        mov rsi, rax
        call list_concat
        mov r13, rax
        xor r14d, r14d
        add rsp, 24
        ret

# local: rax = rewrite_trace(rdi, add_path) with the path so far
.Ltw_rewrite_with_path:
        sub rsp, 24
        mov [rsp], rdi
        mov rdi, rbx
        call vec_to_list
        mov [rsp + 32 + TW_CTX], rax
        mov rax, [rsp + 32 + TW_JD]
        mov [rsp + 32 + TW_CTX + 8], rax
        mov rdi, [rsp]
        lea rsi, [rip + add_path]
        lea rdx, [rsp + 32 + TW_CTX]
        call rewrite_trace
        add rsp, 24
        ret
ENDF to_while

        .section .rodata
.Ls_wl_index:   .asciz "tuple index out of range"
.Ls_wl_type:    .asciz "object is not iterable"
.Ls_wl_unpack:  .asciz "not enough values to unpack (expected 3)"
        .text

        .section .note.GNU-stack,"",@progbits
