# Loops -> whiles (port of whiles.py): the labels and gotos of the VM's
# trace become ('while', cond, body, jd, vars) and ('continue', jd,
# setvars) lines.

.include "defs.inc"

        .section .rodata
.Ls_logname:    .asciz "panoramix.whiles"
.Ls_no_loop:    .asciz "couldn't make loop for line %v, omitting it."
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

# whiles_make(trace) -> list
FUNC whiles_make
        STACK_CHECK
        ENTER
        sub rsp, 112                    # res, line, the error handler, before, inside, remaining, cond
        mov rbx, rdi
        call vec_new
        mov [rsp], rax
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
        mov rdi, [rsp]
        mov rsi, r13
        call vec_push
.Lmk_next:
        inc r12
        jmp .Lmk_line
.Lmk_if:
        mov rdi, [r13 + N_DATA + 16]
        call whiles_make
        mov [rsp + 8], rax
        mov rdi, [r13 + N_DATA + 24]
        call whiles_make
        mov rdx, rax
        mov rsi, [rsp + 8]
        mov rdi, [r13 + N_DATA + 8]
        call mk_if
        mov rdi, [rsp]
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
        mov rdi, [rsp]
        mov rsi, rax
        call vec_push
        jmp .Lmk_next
.Lmk_label:
        cmp dword ptr [r13 + N_AUX], 3
        jb .Lmk_asis
        # before, inside, remaining, cond = to_while(trace[idx + 1:], jd)
        lea rdi, [rsp + 16]
        call err_catch
        test eax, eax
        jnz .Lmk_no_loop
        mov rdi, rbx
        lea rsi, [r12 + 1]
        call list_from
        mov rdi, rax
        mov rsi, [r13 + N_DATA + 8]
        lea rdx, [rsp + 80]             # -> before, inside, remaining, cond
        call to_while
        call err_end
        mov rdi, [rsp + 88]
        call whiles_make
        mov [rsp + 88], rax             # inside
        mov rdi, [rsp + 96]
        call whiles_make
        mov [rsp + 96], rax             # remaining
        # the loop variables take their initial values before the loop
        mov r14, [r13 + N_DATA + 16]    # vars
        xor ecx, ecx
1:      cmp ecx, [r14 + N_AUX]
        jae 2f
        mov [rsp + 8], rcx
        mov rax, [r14 + N_DATA + rcx*8] # ('setvar', v_idx, v_val)
        mov rsi, [rax + N_DATA + 8]
        LOADS rdi, VAR
        call mk2
        mov rcx, [rsp + 8]
        mov rdx, [r14 + N_DATA + rcx*8]
        mov rdx, [rdx + N_DATA + 16]
        mov rdi, [rsp + 80]
        mov rsi, rax
        call replace
        mov [rsp + 80], rax
        mov rcx, [rsp + 8]
        inc rcx
        jmp 1b
2:      mov rdi, [rsp + 80]
        call whiles_make
        mov rdi, [rsp]
        mov rsi, rax
        call vec_extend_seq
        # ('while', cond, inside, repr(jd), vars)
        mov rdi, [r13 + N_DATA + 8]
        call str_of_value
        mov rdx, rax
        mov rdi, [rsp + 104]
        mov rsi, [rsp + 88]
        mov rcx, r14
        call mk_while
        mov rdi, [rsp]
        mov rsi, rax
        call vec_push
        mov rdi, [rsp]
        mov rsi, [rsp + 96]
        call vec_extend_seq
        jmp .Lmk_done
.Lmk_no_loop:
        mov edi, eax                    # (python's timeout isn't an Exception)
        call err_rethrow_timeout
        mov edi, LOG_ERROR
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_no_loop]
        mov rcx, r13
        call log_fmt
        jmp .Lmk_next
.Lmk_done:
        mov rdi, [rsp]
        call vec_to_list
        add rsp, 112
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

# goes_to(trace, jd) -> eax: a goto to jd somewhere in the trace
FUNC goes_to
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call vec_new
        mov r13, rax
        mov rdi, rbx
        lea rsi, [rip + collect_gotos]
        mov rdx, r13
        call walk_collect_lines
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

# add_path(line, path, out): rewrite_trace's f in to_while - a goto gets
# the lines preceding the exit condition in front of it (with its
# setvars applied), as they are executed again before the next iteration
FUNC add_path
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi                    # path (a list)
        mov r13, rdx                    # out
        call opcode_of
        cmp eax, OP_GOTO
        jne 3f
        cmp dword ptr [rbx + N_AUX], 3
        jne 3f
        mov r14, [rbx + N_DATA + 16]    # setvars
        xor ecx, ecx
1:      cmp ecx, [r14 + N_AUX]
        jae 2f
        mov [rsp], rcx
        mov rax, [r14 + N_DATA + rcx*8] # ('setvar', v_idx, v_val)
        mov rsi, [rax + N_DATA + 8]
        LOADS rdi, VAR
        call mk2
        mov rcx, [rsp]
        mov rdx, [r14 + N_DATA + rcx*8]
        mov rdx, [rdx + N_DATA + 16]
        mov rdi, r12
        mov rsi, rax
        call replace
        mov r12, rax
        mov rcx, [rsp]
        inc rcx
        jmp 1b
2:      mov rdi, r13
        mov rsi, r12
        call vec_extend_seq
3:      mov rdi, r13
        mov rsi, rbx
        call vec_push
        add rsp, 16
        LEAVE
ENDF add_path

# to_while(trace, jd, out): `trace` is what follows a loop label, `jd`
# the label. Fills out[0..3] with (before, inside, remaining, cond) so
# that the loop can be written as: before; while cond: inside; remaining
FUNC to_while
        ENTER
        sub rsp, 48
        mov [rsp], rsi                  # jd
        mov [rsp + 8], rdx              # out
        mov r13, rdi                    # what's left of the trace (a list)
        xor r14d, r14d                  # position in it
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
        cmp eax, OP_GOTO
        jne .Ltw_path
        cmp dword ptr [r12 + N_AUX], 2
        jb .Ltw_path
        mov rax, [r12 + N_DATA + 8]
        cmp rax, [rsp]
        jne .Ltw_path
        # the path loops back unconditionally: the exits, if any, are the
        # reverts and returns along the way. ([], add_path([line]), rest, True)
        call .Ltw_rest
        mov [rsp + 32], rax             # remaining
        mov rdi, r12
        call mk_list1
        mov rdi, rax
        call .Ltw_rewrite_with_path
        mov [rsp + 24], rax             # inside
        call .Ltw_empty
        mov [rsp + 16], rax             # before
        LOADS rdi, BOOL
        mov esi, 3
        call mk2
        mov [rsp + 40], rax
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
        mov rdi, [r12 + N_DATA + 16]
        call is_revert
        test eax, eax
        jz 1f
        # require(not cond), go on with the false branch
        mov rdi, [r12 + N_DATA + 8]
        call is_zero
        mov rsi, rax
        LOADS rdi, REQUIRE
        call mk2
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
        mov rsi, [r12 + N_DATA + 8]
        LOADS rdi, REQUIRE
        call mk2
        mov rdi, rbx
        mov rsi, rax
        call vec_push
        mov rdi, [r12 + N_DATA + 16]
        call .Ltw_prepend
        jmp .Ltw_line
2:      mov rdi, [r12 + N_DATA + 16]
        mov rsi, [rsp]
        call goes_to
        mov [rsp + 16], rax             # jd in jds_true
        mov rdi, [r12 + N_DATA + 24]
        mov rsi, [rsp]
        call goes_to
        mov [rsp + 24], rax             # jd in jds_false
        mov eax, r14d
        cmp eax, [r13 + N_AUX]
        jb 3f                           # something follows the if
        mov rax, [rsp + 16]
        or rax, [rsp + 24]
        jnz 4f
3:      # The branches merge again and the loop goes on after that: a
        # statement of the loop body (a goto inside it is a `continue`),
        # not the exit condition, which is the last thing on its path.
        mov rdi, rbx
        mov rsi, r12
        call vec_push
        jmp .Ltw_line
4:      cmp qword ptr [rsp + 16], 0
        je 5f
        cmp qword ptr [rsp + 24], 0
        je 5f
        # the loop goes on whichever way the if goes - if it can be left
        # at all, it's from inside the branches. ([], path + [line], rest, True)
        call .Ltw_rest
        mov [rsp + 32], rax
        mov rdi, rbx
        mov rsi, r12
        call vec_push
        mov rdi, rbx
        call vec_to_list
        mov [rsp + 24], rax
        call .Ltw_empty
        mov [rsp + 16], rax
        LOADS rdi, BOOL
        mov esi, 3
        call mk2
        mov [rsp + 40], rax
        jmp .Ltw_return
5:      cmp qword ptr [rsp + 16], 0
        je 6f
        # (path, add_path(if_true), if_false + rest, cond)
        mov rdi, [r12 + N_DATA + 16]
        call .Ltw_rewrite_with_path
        mov [rsp + 24], rax
        call .Ltw_rest
        mov rdi, [r12 + N_DATA + 24]
        mov rsi, rax
        call list_concat
        mov [rsp + 32], rax
        mov rax, [r12 + N_DATA + 8]
        mov [rsp + 40], rax
        jmp 7f
6:      # (path, add_path(if_false), if_true + rest, not cond)
        mov rdi, [r12 + N_DATA + 24]
        call .Ltw_rewrite_with_path
        mov [rsp + 24], rax
        call .Ltw_rest
        mov rdi, [r12 + N_DATA + 16]
        mov rsi, rax
        call list_concat
        mov [rsp + 32], rax
        mov rdi, [r12 + N_DATA + 8]
        call is_zero
        mov [rsp + 40], rax
7:      mov rdi, rbx
        call vec_to_list
        mov [rsp + 16], rax
.Ltw_return:
        mov rdi, [rsp + 8]
        mov rax, [rsp + 16]
        mov [rdi], rax
        mov rax, [rsp + 24]
        mov [rdi + 8], rax
        mov rax, [rsp + 32]
        mov [rdi + 16], rax
        mov rax, [rsp + 40]
        mov [rdi + 24], rax
        add rsp, 48
        LEAVE
.Ltw_no_if:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_no_if]
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
        mov rdi, [rsp]
        lea rsi, [rip + add_path]
        mov rdx, rax
        call rewrite_trace
        add rsp, 24
        ret
ENDF to_while

        .section .note.GNU-stack,"",@progbits
