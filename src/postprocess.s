# The && and || of the code (port of postprocess.py's logical and
# short_circuits; its cleanup_mul_1 is in rewriter.s): the paths of a
# short circuit merge again after it (the VM's merge_branches), each
# setting the variable of the merge - an if whose branches only set that
# variable, to values that make it an and / an or of its condition, is
# that assignment, written as python's `and` / `or` (OUTPUT.md).

.include "defs.inc"

        .text

# logical(cond, if_true, if_false) -> value, or 0 (None): postprocess.logical
# - the value `if cond: v = if_true else: v = if_false` sets v to, as a
# python `and` / `or` of cond, where a branch sets it to what the
# condition decides there. Where cond holds, it isn't 0, where it doesn't,
# it's 0:
#
#     if c: v = c (or 1, c a truth value) else: v = f     c or f
#     if c: v = t else: v = 0 (or c)                      c and t
#     if c: v = 0 else: v = f                             not c and f
#     if c: v = t else: v = 1                             not c or t
FUNC logical
        ENTER
        mov rbx, rdi                    # cond
        mov r12, rsi                    # if_true
        mov r13, rdx                    # if_false
        # if_true == cond or (if_true == 1 and is_bool(cond))
        mov rdi, r12
        mov rsi, rbx
        call py_equal
        test eax, eax
        jnz 1f
        mov rdi, r12
        mov esi, 3                      # 1
        call py_equal
        test eax, eax
        jz 2f
        mov rdi, rbx
        call is_bool
        test eax, eax
        jz 2f
1:      LOADS rdi, LOR                  # ("lor", cond, if_false)
        mov rsi, rbx
        mov rdx, r13
        jmp .Llg_lor
2:      # if_false in (0, cond)
        mov rdi, r13
        mov esi, 1                      # 0
        call py_equal
        test eax, eax
        jnz 3f
        mov rdi, r13
        mov rsi, rbx
        call py_equal
        test eax, eax
        jz 4f
3:      mov rsi, rbx                    # ("land", cond, if_true)
        mov rdx, r12
        jmp .Llg_land
4:      # if_true == 0: ("land", is_zero(cond), if_false)
        mov rdi, r12
        mov esi, 1
        call py_equal
        test eax, eax
        jz 5f
        mov rdi, rbx
        call is_zero
        mov rsi, rax
        mov rdx, r13
        jmp .Llg_land
5:      # if_false == 1: ("lor", is_zero(cond), if_true)
        mov rdi, r13
        mov esi, 3
        call py_equal
        test eax, eax
        jz 9f
        mov rdi, rbx
        call is_zero
        mov rsi, rax
        mov rdx, r12
        jmp .Llg_lor
9:      xor eax, eax
        LEAVE
.Llg_lor:
        # c or 0: c, which is 0 where it's false
        mov rbx, rsi
        mov r12, rdx
        mov rdi, rdx
        mov esi, 1
        call py_equal
        test eax, eax
        jz 1f
        mov rax, rbx
        LEAVE
1:      LOADS rdi, LOR
        mov rsi, rbx
        mov rdx, r12
        call mk3
        LEAVE
.Llg_land:
        # c and 1: 1 where c isn't 0 - a truth value
        mov rbx, rsi
        mov r12, rdx
        mov rdi, rdx
        mov esi, 3
        call py_equal
        test eax, eax
        jz 1f
        mov rdi, rbx
        call is_bool
        test eax, eax
        jz 2f
        mov rax, rbx
        LEAVE
2:      LOADS rdi, BOOL
        mov rsi, rbx
        call mk2
        LEAVE
1:      LOADS rdi, LAND
        mov rsi, rbx
        mov rdx, r12
        call mk3
        LEAVE
ENDF logical

# short_circuits(trace) -> list: postprocess.short_circuits - the `&&`
# and `||` of the code, written as python's `and` and `or`: an if whose
# branches only set the same variable to values that make it an and / an
# or of the condition (see logical) is that assignment - inner ifs first,
# so that `a && (b || c)` is one
FUNC short_circuits
        STACK_CHECK
        ENTER
        sub rsp, 32
        .set SC_OUT, 0
        .set SC_TRUE, 8
        .set SC_FALSE, 16
        mov rbx, rdi
        call is_seq                     # (python iterates it)
        test eax, eax
        jz .Lsc_type
        call vec_new
        mov [rsp + SC_OUT], rax
        xor r12d, r12d
.Lsc_line:
        cmp r12d, [rbx + N_AUX]
        jae .Lsc_done
        mov r13, [rbx + N_DATA + r12*8]
        inc r12d
        mov rdi, r13
        call opcode_of
        cmp eax, OP_WHILE
        je .Lsc_while
        cmp eax, OP_IF
        jne .Lsc_push
        cmp dword ptr [r13 + N_AUX], 4
        jne .Lsc_push
        mov rdi, [r13 + N_DATA + 16]
        call short_circuits
        mov [rsp + SC_TRUE], rax
        mov rdi, [r13 + N_DATA + 24]
        call short_circuits
        mov [rsp + SC_FALSE], rax
        mov rdi, [r13 + N_DATA + 8]
        mov rsi, [rsp + SC_TRUE]
        mov rdx, rax
        call mk_if
        mov r14, rax                    # the line
        # both branches a setvar of the same variable
        mov rax, [rsp + SC_TRUE]
        cmp dword ptr [rax + N_AUX], 1
        jne .Lsc_if
        mov rcx, [rsp + SC_FALSE]
        cmp dword ptr [rcx + N_AUX], 1
        jne .Lsc_if
        mov rdi, [rax + N_DATA]
        OP_N_CHECK OP_SETVAR, 3, .Lsc_if
        mov rax, [rsp + SC_FALSE]
        mov rdi, [rax + N_DATA]
        OP_N_CHECK OP_SETVAR, 3, .Lsc_if
        mov rax, [rsp + SC_TRUE]
        mov rax, [rax + N_DATA]
        mov rcx, [rsp + SC_FALSE]
        mov rcx, [rcx + N_DATA]
        mov rdi, [rax + N_DATA + 8]
        mov rsi, [rcx + N_DATA + 8]
        call py_equal
        test eax, eax
        jz .Lsc_if
        mov rax, [rsp + SC_TRUE]
        mov rax, [rax + N_DATA]
        mov rcx, [rsp + SC_FALSE]
        mov rcx, [rcx + N_DATA]
        mov rdi, [r13 + N_DATA + 8]
        mov rsi, [rax + N_DATA + 16]
        mov rdx, [rcx + N_DATA + 16]
        call logical
        test rax, rax
        jz .Lsc_if
        mov rdx, rax                    # ("setvar", var, value)
        mov rax, [rsp + SC_TRUE]
        mov rax, [rax + N_DATA]
        mov rsi, [rax + N_DATA + 8]
        LOADS rdi, SETVAR
        call mk3
        mov r14, rax
.Lsc_if:
        mov r13, r14
        jmp .Lsc_push
.Lsc_while:
        # line[:2] + (short_circuits(line[2]),) + line[3:]
        cmp dword ptr [r13 + N_AUX], 3
        jb .Lsc_index
        mov rdi, [r13 + N_DATA + 16]
        call short_circuits
        mov r14, rax
        mov edi, [r13 + N_AUX]
        shl edi, 3
        call arena_alloc
        mov ecx, [r13 + N_AUX]
1:      dec ecx
        js 2f
        mov rdx, [r13 + N_DATA + rcx*8]
        mov [rax + rcx*8], rdx
        jmp 1b
2:      mov [rax + 16], r14
        mov rdi, r13
        mov rsi, rax
        call mk_seq_like
        mov r13, rax
.Lsc_push:
        mov rdi, [rsp + SC_OUT]
        mov rsi, r13
        call vec_push
        jmp .Lsc_line
.Lsc_done:
        mov rdi, [rsp + SC_OUT]
        call vec_to_list
        add rsp, 32
        LEAVE
.Lsc_index:
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_sc_index]
        call err_throw
.Lsc_type:
        mov edi, E_TYPE
        lea rsi, [rip + .Ls_sc_type]
        call err_throw
ENDF short_circuits

        .section .rodata
.Ls_sc_index: .asciz "IndexError: short_circuits: a while of fewer than 3 elements"
.Ls_sc_type: .asciz "TypeError: short_circuits: a branch that isn't a sequence"

        .section .note.GNU-stack,"",@progbits
