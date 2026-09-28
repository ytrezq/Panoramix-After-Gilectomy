# The cleanup passes of the simplifier (port of simplify.py): conditions
# that are always true, msize, memory and variables inlined where they
# can be, and the readability pass.

.include "defs.inc"

        .section .rodata
.Ls_msize:          .asciz "msize"
.Ls_mem:            .asciz "mem"
.Ls_msize_var:      .asciz "_msize"
.Ls_assert_msize:   .asciz "_eval_msize: unsupported comparison"
.Ls_assert_max:     .asciz "_eval_msize: not a max"
.Ls_assert_mem:     .asciz "replace_mem_exp: a mem of the wrong shape"
.Ls_assert_affects: .asciz "replace_var: a loop affecting the value"
.Ls_assert_range:   .asciz "not a range"

        .text

.macro B reg, n
        mov \reg, [rsp + 8*\n]
.endm

# --- conditions ---

# cleanup_conds(trace) -> list: removes the ifs/whiles whose conditions
# are obviously true or false
FUNC cleanup_conds
        ENTER
        sub rsp, 32
        mov rbx, rdi
        call vec_new
        mov r12, rax
        xor r13d, r13d
.Lcc_line:
        cmp r13d, [rbx + N_AUX]
        jae .Lcc_done
        mov r14, [rbx + N_DATA + r13*8]
        inc r13d
        mov rdi, r14
        call is_while_line
        test eax, eax
        jz 2f
        # not evaluating symbolically: stuff like stor0 <= stor0 + 1 would
        # get evaluated to True (masks truncated)
        mov rdi, [r14 + N_DATA + 16]
        call cleanup_conds
        mov [rsp], rax
        mov rdi, [r14 + N_DATA + 8]
        lea rsi, [rip + sp_none]
        xor edx, edx
        call eval_bool
        cmp eax, TRI_FALSE
        je .Lcc_line                    # removing the loop altogether
        mov rdi, [r14 + N_DATA + 8]
        cmp eax, TRI_TRUE
        jne 1f
        LOADS rdi, BOOL
        mov esi, 3
        call mk2
        mov rdi, rax
1:      mov rsi, [rsp]
        mov rdx, [r14 + N_DATA + 24]
        mov rcx, [r14 + N_DATA + 32]
        call mk_while
        mov rdi, r12
        mov rsi, rax
        call vec_push
        jmp .Lcc_line
2:      mov rdi, r14
        call is_if_line
        test eax, eax
        jz 5f
        mov rdi, [r14 + N_DATA + 16]
        call cleanup_conds
        mov [rsp], rax
        mov rdi, [r14 + N_DATA + 24]
        call cleanup_conds
        mov [rsp + 8], rax
        mov rdi, [r14 + N_DATA + 8]
        lea rsi, [rip + sp_none]
        xor edx, edx
        call eval_bool
        cmp eax, TRI_TRUE
        jne 3f
        mov rdi, r12
        mov rsi, [rsp]
        call vec_extend_seq
        jmp .Lcc_line
3:      cmp eax, TRI_FALSE
        jne 4f
        mov rdi, r12
        mov rsi, [rsp + 8]
        call vec_extend_seq
        jmp .Lcc_line
4:      mov rax, [rsp]
        cmp dword ptr [rax + N_AUX], 0
        jne 41f
        mov rax, [rsp + 8]
        cmp dword ptr [rax + N_AUX], 0
        je .Lcc_line                    # both branches empty: nothing left
        # only the false branch: the if on the negated condition
        mov rdi, [r14 + N_DATA + 8]
        call is_zero
        mov rdi, rax
        mov rsi, [rsp + 8]
        mov rdx, [rsp]
        call mk_if
        mov rdi, r12
        mov rsi, rax
        call vec_push
        jmp .Lcc_line
41:     mov rdi, [r14 + N_DATA + 8]
        mov rsi, [rsp]
        mov rdx, [rsp + 8]
        call mk_if
        mov rdi, r12
        mov rsi, rax
        call vec_push
        jmp .Lcc_line
5:      mov rdi, r12
        mov rsi, r14
        call vec_push
        jmp .Lcc_line
.Lcc_done:
        mov rdi, r12
        call vec_to_list
        add rsp, 32
        LEAVE
ENDF cleanup_conds

# --- msize ---

# eval_msize(cond) -> eax: TRI_TRUE / TRI_FALSE / TRI_NONE for a
# comparison of a max with something
FUNC eval_msize
        ENTER
        sub rsp, 16
        mov rbx, rdi
        call opcode_of
        cmp eax, OP_LT
        je 1f
        cmp eax, OP_LE
        je 1f
        cmp eax, OP_GT
        je 1f
        cmp eax, OP_GE
        jne .Lem_none
1:      mov rdi, [rbx + N_DATA + 8]
        call opcode_of
        mov r12d, eax
        mov rdi, [rbx + N_DATA + 16]
        call opcode_of
        mov r13d, eax
        cmp r12d, OP_MAX
        je 2f
        cmp r13d, OP_MAX
        jne .Lem_none
2:      cmp r12d, OP_MAX
        jne 3f
        cmp r13d, OP_MAX
        je .Lem_none
3:      cmp r13d, OP_MAX
        jne 4f
        mov rdi, rbx
        call swap_cond
        mov rbx, rax
4:      mov rdi, rbx
        call opcode_of
        cmp eax, OP_LT
        je 5f
        cmp eax, OP_LE
        jne .Lem_assert                 # gt/ge: unsupported yet
        # max(...) <= right is max(...) < right + 1
        mov edi, 3
        mov rsi, [rbx + N_DATA + 16]
        call alg_add2
        mov rdx, rax
        mov rsi, [rbx + N_DATA + 8]
        LOADS rdi, LT
        call mk3
        mov rbx, rax
5:      mov r12, [rbx + N_DATA + 8]     # ('max', ...)
        mov r13, [rbx + N_DATA + 16]    # right
        # all(l < right) -> False
        mov r14d, 1
6:      cmp r14d, [r12 + N_AUX]
        jae .Lem_false
        mov rdi, [r12 + N_DATA + r14*8]
        mov rsi, r13
        call alg_safe_lt_op
        cmp eax, TRI_TRUE
        jne 7f
        inc r14d
        jmp 6b
7:      # any(right < l is False) -> False
        mov r14d, 1
8:      cmp r14d, [r12 + N_AUX]
        jae 9f
        mov rdi, r13
        mov rsi, [r12 + N_DATA + r14*8]
        call alg_safe_lt_op
        cmp eax, TRI_FALSE
        je .Lem_false
        inc r14d
        jmp 8b
9:      # all(right <= l) -> True
        mov r14d, 1
10:     cmp r14d, [r12 + N_AUX]
        jae .Lem_true
        mov rdi, r13
        mov rsi, [r12 + N_DATA + r14*8]
        call alg_safe_le_op
        cmp eax, TRI_TRUE
        jne .Lem_none
        inc r14d
        jmp 10b
.Lem_true:
        mov eax, TRI_TRUE
        add rsp, 16
        LEAVE
.Lem_false:
        mov eax, TRI_FALSE
        add rsp, 16
        LEAVE
.Lem_none:
        mov eax, TRI_NONE
        add rsp, 16
        LEAVE
.Lem_assert:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_msize]
        call err_throw
ENDF eval_msize

# cleanup_msize(trace) -> list: msize replaced by the memory size where
# it is known
FUNC cleanup_msize
        ENTER
        sub rsp, 16
        mov esi, 1
        lea rdx, [rsp]
        call cleanup_msize_impl
        add rsp, 16
        LEAVE
ENDF cleanup_msize

# cleanup_msize_impl(trace, current_msize, &msize_out) -> list
FUNC cleanup_msize_impl
        ENTER
        sub rsp, 48
        .set CM_MSIZE, 0
        .set CM_OUT, 8
        .set CM_COND, 16
        .set CM_TRUE, 24
        .set CM_FALSE, 32
        .set CM_MSIZE_TRUE, 40
        mov rbx, rdi
        mov [rsp + CM_MSIZE], rsi
        mov [rsp + CM_OUT], rdx
        call vec_new
        mov r12, rax
        xor r13d, r13d
.Lcm_line:
        cmp r13d, [rbx + N_AUX]
        jae .Lcm_done
        mov r14, [rbx + N_DATA + r13*8]
        inc r13d
        mov rdi, r14
        call opcode_of
        cmp eax, OP_SETMEM
        jne 1f
        mov rdi, r14
        call .Lcm_replace_msize
        mov r14, rax
        mov rdi, r14
        call memloc_right
        mov rdi, [rsp + CM_MSIZE]
        mov rsi, rax
        call alg_max_op2
        mov [rsp + CM_MSIZE], rax
        jmp .Lcm_push
1:      cmp eax, OP_WHILE
        jne 2f
        mov rdi, r14
        call while_max_memidx
        mov rdi, [rsp + CM_MSIZE]
        mov rsi, rax
        call alg_max_op2
        mov [rsp + CM_MSIZE], rax
        jmp .Lcm_push
2:      mov rdi, r14
        call is_if_line
        test eax, eax
        jz 5f
        mov rax, [r14 + N_DATA + 8]
        mov [rsp + CM_COND], rax
        mov rdi, rax
        lea rsi, [rip + .Ls_msize]
        call mentions_c
        test eax, eax
        jz 3f
        mov rdi, [rsp + CM_MSIZE]
        call opcode_of
        cmp eax, OP_MAX
        jne 3f
        mov rdi, [rsp + CM_COND]
        call .Lcm_replace_msize
        mov rdi, rax
        call eval_msize
        cmp eax, TRI_NONE
        je 4f
        mov ecx, 3
        cmp eax, TRI_TRUE
        je 31f
        mov ecx, 1
31:     mov [rsp + CM_COND], rcx
        jmp 4f
3:      mov rdi, [rsp + CM_MSIZE]
        call alg_max_to_add
        mov rdi, [rsp + CM_COND]
        lea rsi, [rip + .Ls_msize]
        push rax
        push rax
        call str_intern_c
        pop rdx
        pop rdx
        mov rsi, rax
        mov rdi, [rsp + CM_COND]
        call replace
        mov [rsp + CM_COND], rax
4:      mov rdi, [r14 + N_DATA + 16]
        mov rsi, [rsp + CM_MSIZE]
        lea rdx, [rsp + CM_MSIZE_TRUE]
        call cleanup_msize_impl
        mov [rsp + CM_TRUE], rax
        mov rdi, [r14 + N_DATA + 24]
        mov rsi, [rsp + CM_MSIZE]
        lea rdx, [rsp + CM_FALSE]       # (the msize after the false branch, reused below)
        call cleanup_msize_impl
        mov rdx, rax
        mov rdi, [rsp + CM_COND]
        mov rsi, [rsp + CM_TRUE]
        call mk_if
        mov rdi, r12
        mov rsi, rax
        call vec_push
        # for what follows the if, when its branches merge again
        mov rax, [rsp + CM_MSIZE_TRUE]
        cmp rax, [rsp + CM_FALSE]
        je 41f
        # we could take the max of both, but that gets expensive quickly,
        # and msize isn't used by any recent compiler
        lea rdi, [rip + .Ls_msize]
        call str_intern_c
41:     mov [rsp + CM_MSIZE], rax
        jmp .Lcm_line
5:      mov rdi, r14
        call .Lcm_replace_msize
        mov r14, rax
.Lcm_push:
        mov rdi, r12
        mov rsi, r14
        call vec_push
        jmp .Lcm_line
.Lcm_done:
        mov rax, [rsp + CM_OUT]
        mov rcx, [rsp + CM_MSIZE]
        mov [rax], rcx
        mov rdi, r12
        call vec_to_list
        add rsp, 48
        LEAVE

# local: replace(rdi, 'msize', current_msize)
.Lcm_replace_msize:
        sub rsp, 24
        mov [rsp], rdi
        lea rdi, [rip + .Ls_msize]
        call str_intern_c
        mov rsi, rax
        mov rdi, [rsp]
        mov rdx, [rsp + 24 + 8 + CM_MSIZE]      # (the caller's frame: past the return address)
        call replace
        add rsp, 24
        ret
ENDF cleanup_msize_impl

# --- what a line affects ---

# overwrites_mem(line, mem_idx) -> eax: the line may overwrite any part
# of the memory range
FUNC overwrites_mem
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE
        mov rbx, rdi
        mov r12, rsi
        PAT rsi, "('setmem', ':set_idx', 'Any')"
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 1f
        B rdi, 0
        mov rsi, r12
        call range_overlaps
        cmp eax, TRI_FALSE
        setne al
        movzx eax, al
        jmp .Lom_done
1:      mov rdi, rbx
        call opcode_of
        cmp eax, OP_WHILE
        jne 2f
        mov rdi, rbx
        mov rsi, r12
        call while_touches_mem
        jmp .Lom_done
2:      mov rdi, rbx
        call is_if_line
        test eax, eax
        jz .Lom_no
        # matters for what comes after the if, when its branches merge again
        mov rdi, [rbx + N_DATA + 16]
        mov rsi, r12
        call any_overwrites_mem
        test eax, eax
        jnz .Lom_done
        mov rdi, [rbx + N_DATA + 24]
        mov rsi, r12
        call any_overwrites_mem
        jmp .Lom_done
.Lom_no:
        xor eax, eax
.Lom_done:
        add rsp, MATCH_BINDINGS_SIZE
        LEAVE
ENDF overwrites_mem

# any_overwrites_mem(trace, mem_idx) -> eax
FUNC any_overwrites_mem
        ENTER
        mov rbx, rdi
        mov r12, rsi
        xor r13d, r13d
1:      cmp r13d, [rbx + N_AUX]
        jae 2f
        mov rdi, [rbx + N_DATA + r13*8]
        mov rsi, r12
        call overwrites_mem
        test eax, eax
        jnz 3f
        inc r13d
        jmp 1b
2:      xor eax, eax
        LEAVE
3:      mov eax, 1
        LEAVE
ENDF any_overwrites_mem

# affects(line, exp) -> eax: the line may change the value of the
# expression (a memory it reads, or msize)
FUNC affects
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov rdi, r12
        call is_tuple
        test eax, eax
        jnz 1f
        lea rdi, [rip + .Ls_msize]
        call str_intern_c
        cmp r12, rax
        jne .Laf_no
1:      mov rdi, r12
        lea rsi, [rip + .Ls_msize]
        call mentions_c
        test eax, eax
        jz 2f
        lea rdi, [rip + .Ls_undefined]
        call str_intern_c
        mov rsi, rax
        mov edi, 1
        call mk_range
        mov rdi, rbx
        mov rsi, rax
        call overwrites_mem
        test eax, eax
        jnz .Laf_yes
2:      mov rdi, r12
        lea rsi, [rip + .Ls_mem]
        call mentions_c
        test eax, eax
        jz .Laf_no
        mov rdi, r12
        call find_mems
        mov r13, rax
        xor r14d, r14d
3:      cmp r14d, [r13 + N_AUX]
        jae .Laf_no
        mov rax, [r13 + N_DATA + r14*8]
        mov rdi, rbx
        mov rsi, [rax + N_DATA + 8]
        call overwrites_mem
        test eax, eax
        jnz .Laf_yes
        inc r14d
        jmp 3b
.Laf_yes:
        mov eax, 1
        LEAVE
.Laf_no:
        xor eax, eax
        LEAVE
ENDF affects

        .section .rodata
.Ls_undefined: .asciz "undefined"
        .text

# --- memory use ---

.set MU_USED, 1
.set MU_OVERWRITTEN, 2
.set MU_NEITHER, 3

# trace_uses_mem(trace, mem_idx) -> eax
FUNC trace_uses_mem
        ENTER
        call mem_use
        cmp eax, MU_USED
        sete al
        movzx eax, al
        LEAVE
ENDF trace_uses_mem

# mem_use(trace, mem_idx) -> eax: USED if the trace reads the memory,
# OVERWRITTEN if every path through it overwrites the memory (or ends)
# before reading it, NEITHER otherwise
FUNC mem_use
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 32
        .set MU_RES, MATCH_BINDINGS_SIZE
        .set MU_SPLIT, MATCH_BINDINGS_SIZE + 8
        .set MU_REST, MATCH_BINDINGS_SIZE + 16
        .set MU_I, MATCH_BINDINGS_SIZE + 24
        mov rbx, rdi
        mov r12, rsi
        xor r13d, r13d
.Lmu_line:
        cmp r13d, [rbx + N_AUX]
        jae .Lmu_neither
        mov r14, [rbx + N_DATA + r13*8]
        inc r13d
        PAT rsi, "('setmem', ':memloc', ':memval')"
        mov rdi, r14
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 2f
        B rdi, 1
        call simplify_exp
        mov rdi, rax
        mov rsi, r12
        call exp_uses_mem
        test eax, eax
        jnz .Lmu_used
        # the parts not overwritten: what follows must not read them
        mov rdi, r12
        B rsi, 0
        call memloc_overwrite
        mov [rsp + MU_SPLIT], rax
        mov rdi, rbx
        mov rsi, r13
        call list_from
        mov [rsp + MU_REST], rax
        mov dword ptr [rsp + MU_RES], MU_OVERWRITTEN
        mov qword ptr [rsp + MU_I], 0
1:      mov rcx, [rsp + MU_I]
        mov rax, [rsp + MU_SPLIT]
        cmp ecx, [rax + N_AUX]
        jae 11f
        mov rdi, [rsp + MU_REST]
        mov rsi, [rax + N_DATA + rcx*8]
        call mem_use
        cmp eax, MU_USED
        je .Lmu_used
        cmp eax, MU_NEITHER
        jne 12f
        mov dword ptr [rsp + MU_RES], MU_NEITHER
12:     inc qword ptr [rsp + MU_I]
        jmp 1b
11:     mov eax, [rsp + MU_RES]
        jmp .Lmu_done
2:      mov rdi, r14
        call opcode_of
        cmp eax, OP_WHILE
        jne 3f
        mov rdi, r14
        mov rsi, r12
        call while_uses_mem
        test eax, eax
        jnz .Lmu_used
        jmp .Lmu_line
3:      mov rdi, r14
        call is_if_line
        test eax, eax
        jz 5f
        mov rdi, [r14 + N_DATA + 8]
        mov rsi, r12
        call exp_uses_mem
        test eax, eax
        jnz .Lmu_used
        mov rdi, [r14 + N_DATA + 16]
        mov rsi, r12
        call branch_mem_use
        cmp eax, MU_USED
        je .Lmu_used
        mov [rsp + MU_RES], eax
        mov rdi, [r14 + N_DATA + 24]
        mov rsi, r12
        call branch_mem_use
        cmp eax, MU_USED
        je .Lmu_used
        cmp eax, MU_OVERWRITTEN
        jne .Lmu_line
        cmp dword ptr [rsp + MU_RES], MU_OVERWRITTEN
        jne .Lmu_line
        mov eax, MU_OVERWRITTEN
        jmp .Lmu_done
5:      mov rdi, r14
        call opcode_of
        cmp eax, OP_CONTINUE
        je .Lmu_used
        mov rdi, r14
        mov rsi, r12
        call exp_uses_mem
        test eax, eax
        jnz .Lmu_used
        mov rdi, r14
        call opcode_of
        mov edi, eax
        call is_ends_execution_op
        test eax, eax
        jz .Lmu_line
        mov eax, MU_OVERWRITTEN
        jmp .Lmu_done
.Lmu_used:
        mov eax, MU_USED
        jmp .Lmu_done
.Lmu_neither:
        mov eax, MU_NEITHER
.Lmu_done:
        add rsp, MATCH_BINDINGS_SIZE + 32
        LEAVE
ENDF mem_use

# branch_mem_use(branch, mem_idx) -> eax: mem_use, NEITHER counting as
# OVERWRITTEN when the branch ends the execution
FUNC branch_mem_use
        ENTER
        mov rbx, rdi
        call mem_use
        cmp eax, MU_NEITHER
        jne 1f
        mov rdi, rbx
        call trace_ends_execution
        test eax, eax
        jz 2f
        mov eax, MU_OVERWRITTEN
        LEAVE
2:      mov eax, MU_NEITHER
1:      LEAVE
ENDF branch_mem_use

# trace_ends_execution(trace) -> eax: every path through the trace ends
# the execution
FUNC trace_ends_execution
        ENTER
        mov rbx, rdi
        call seq_last
        test rax, rax
        jz .Lte_no
        mov r12, rax
        mov rdi, rax
        call is_if_line
        test eax, eax
        jz 1f
        mov rdi, [r12 + N_DATA + 16]
        call trace_ends_execution
        test eax, eax
        jz .Lte_no
        mov rdi, [r12 + N_DATA + 24]
        call trace_ends_execution
        LEAVE
1:      mov rdi, r12
        call opcode_of
        mov edi, eax
        call is_ends_execution_op
        LEAVE
.Lte_no:
        xor eax, eax
        LEAVE
ENDF trace_ends_execution

# --- memory cleanup ---

# cleanup_mems(trace, used_after) -> list: for every setmem, the future
# occurrences of the memory replaced with its value where possible;
# `used_after` (a list, or 0) is what gets executed after `trace`
FUNC cleanup_mems
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 48
        .set CE_AFTER, MATCH_BINDINGS_SIZE
        .set CE_REMAINING, MATCH_BINDINGS_SIZE + 8
        .set CE_TMP, MATCH_BINDINGS_SIZE + 16
        .set CE_TMP2, MATCH_BINDINGS_SIZE + 24
        mov rbx, rdi
        test rsi, rsi
        jnz 1f
        xor edi, edi
        xor esi, esi
        call mk_list
        mov rsi, rax
1:      mov [rsp + CE_AFTER], rsi
        call vec_new
        mov r12, rax
        xor r13d, r13d
.Lce_line:
        cmp r13d, [rbx + N_AUX]
        jae .Lce_done
        mov r14, [rbx + N_DATA + r13*8]
        inc r13d
        # mem[x] = mem[x]: nothing
        PAT rsi, "('setmem', ':rng', ('mem', ':rng'))"
        mov rdi, r14
        mov rdx, rsp
        call pat_match
        test eax, eax
        jnz .Lce_line
        mov rdi, r14
        call opcode_of
        cmp eax, OP_CALL
        je 2f
        cmp eax, OP_STATICCALL
        je 2f
        cmp eax, OP_DELEGATECALL
        je 2f
        cmp eax, OP_SETMEM
        je 3f
        cmp eax, OP_WHILE
        je 5f
        mov rdi, r14
        call is_if_line
        test eax, eax
        jnz 6f
        jmp .Lce_push
2:      # a call with -4 bytes of arguments: none
        mov rdi, r14
        call seq_last
        PAT rsi, "('mem', ('range', 'Any', -4))"
        mov rdi, rax
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz .Lce_push
        mov edi, [r14 + N_AUX]
        sub edi, 2
        lea rsi, [r14 + N_DATA]
        call mk_tuple
        mov rdi, rax
        call tuple_append_none2
        mov r14, rax
        jmp .Lce_push
3:      PAT rsi, "('setmem', ':mem_idx', ':mem_val')"
        mov rdi, r14
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz .Lce_push
        # find all the future occurrences of the memory and replace them
        # where possible
        mov rdi, rbx
        mov rsi, r13
        call list_from
        mov [rsp + CE_REMAINING], rax
        mov rdi, r14
        B rsi, 1
        call affects
        test eax, eax
        jnz 4f
        # (the cause of the O(N^2): the rest of the trace is rewritten
        # for every setmem)
        mov rdi, [rsp + CE_REMAINING]
        B rsi, 0
        B rdx, 1
        call replace_mem
        mov [rsp + CE_REMAINING], rax
4:      mov rdi, [rsp + CE_REMAINING]
        mov rsi, [rsp + CE_AFTER]
        call list_concat
        mov rdi, rax
        B rsi, 0
        call trace_uses_mem
        test eax, eax
        jz 41f
        mov rdi, r12
        mov rsi, r14
        call vec_push
41:     mov rdi, [rsp + CE_REMAINING]
        mov rsi, [rsp + CE_AFTER]
        call cleanup_mems
        mov rdi, r12
        mov rsi, rax
        call vec_extend_seq
        jmp .Lce_done
5:      # ('while', cond, cleanup_mems(path)) + the rest
        mov rdi, [r14 + N_DATA + 16]
        xor esi, esi
        call cleanup_mems
        mov rsi, rax
        mov rdi, [r14 + N_DATA + 8]
        mov rdx, [r14 + N_DATA + 24]
        mov rcx, [r14 + N_DATA + 32]
        call mk_while
        mov r14, rax
        jmp .Lce_push
6:      mov rdi, rbx
        mov rsi, r13
        call list_from
        mov rdi, rax
        mov rsi, [rsp + CE_AFTER]
        call list_concat
        mov [rsp + CE_TMP], rax         # after
        mov rdi, [r14 + N_DATA + 16]
        mov rsi, rax
        call cleanup_mems
        mov [rsp + CE_TMP2], rax
        mov rdi, [r14 + N_DATA + 24]
        mov rsi, [rsp + CE_TMP]
        call cleanup_mems
        mov rdx, rax
        mov rsi, [rsp + CE_TMP2]
        mov rdi, [r14 + N_DATA + 8]
        call mk_if
        mov r14, rax
.Lce_push:
        mov rdi, r12
        mov rsi, r14
        call vec_push
        jmp .Lce_line
.Lce_done:
        mov rdi, r12
        call vec_to_list
        add rsp, MATCH_BINDINGS_SIZE + 48
        LEAVE
ENDF cleanup_mems

# tuple_append_none2(tuple) -> tuple + (None, None)
FUNC tuple_append_none2
        ENTER
        lea rsi, [rip + sp_none]
        call tuple_append
        mov rdi, rax
        lea rsi, [rip + sp_none]
        call tuple_append
        LEAVE
ENDF tuple_append_none2

# replace_mem_exp(exp, mem_idx, mem_val) -> value: the reads of the
# memory in the expression replaced by the value (memoized on the three)
FUNC replace_mem_exp
        ENTER
        sub rsp, 32
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        call is_tuple
        test eax, eax
        jnz 1f
        mov rax, rbx
        add rsp, 32
        LEAVE
1:      mov rdi, rbx
        mov rsi, r12
        mov rdx, r13
        call mk3
        mov r14, rax                    # the key
        mov edi, MEMO_REPLACE_MEM_EXP
        mov rsi, r14
        call memo_get
        test rax, rax
        jnz 2f
        mov rdi, rbx
        mov rsi, r12
        mov rdx, r13
        call replace_mem_exp_impl
        mov [rsp], rax
        mov edi, MEMO_REPLACE_MEM_EXP
        mov rsi, r14
        mov rdx, rax
        call memo_put
        mov rax, [rsp]
2:      add rsp, 32
        LEAVE
ENDF replace_mem_exp

FUNC replace_mem_exp_impl
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 32
        .set RM_RES, MATCH_BINDINGS_SIZE
        .set RM_ELEMS, MATCH_BINDINGS_SIZE + 8
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        # the elements that are tuples, replaced
        mov edi, [rbx + N_AUX]
        shl rdi, 3
        call arena_alloc
        mov [rsp + RM_ELEMS], rax
        xor r14d, r14d
1:      cmp r14d, [rbx + N_AUX]
        jae 3f
        mov rdi, [rbx + N_DATA + r14*8]
        call is_tuple
        mov rcx, rax
        mov rax, [rbx + N_DATA + r14*8]
        test ecx, ecx
        jz 2f
        mov rdi, rax
        mov rsi, r12
        mov rdx, r13
        call replace_mem_exp
2:      mov rcx, [rsp + RM_ELEMS]
        mov [rcx + r14*8], rax
        inc r14d
        jmp 1b
3:      mov edi, [rbx + N_AUX]
        mov rsi, [rsp + RM_ELEMS]
        call mk_tuple
        mov [rsp + RM_RES], rax
        mov rdi, r13
        call opcode_of
        cmp eax, OP_MEM
        je 6f
        cmp eax, OP_VAR
        je 6f
        cmp eax, OP_DATA
        je 6f
        # a call whose function selector and arguments are two memory
        # reads next to each other: one memory, replaced as a whole
        PAT rsi, "('delegatecall', ':gas', ':addr', ('mem', ':func'), ('mem', ':args'))"
        mov rdi, [rsp + RM_RES]
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 4f
        B rdi, 2
        B rsi, 3
        call merged_call_range
        cmp rax, r12
        jne 4f
        B rsi, 0
        B rdx, 1
        lea rcx, [rip + sp_none]
        mov r8, r13
        LOADS rdi, DELEGATECALL
        call mk5
        mov [rsp + RM_RES], rax
4:      PAT rsi, "('call', ':gas', ':addr', ':value', ('mem', ':func'), ('mem', ':args'))"
        mov rdi, [rsp + RM_RES]
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 6f
        B rdi, 3
        B rsi, 4
        call merged_call_range
        cmp rax, r12
        jne 6f
        B rsi, 0
        B rdx, 1
        B rcx, 2
        lea r8, [rip + sp_none]
        mov r9, r13
        LOADS rdi, CALL
        call mk6
        mov [rsp + RM_RES], rax
6:      mov rax, [rsp + RM_RES]
        cmp rax, rbx
        je 7f
        mov rdi, rax
        call simplify_exp
        mov [rsp + RM_RES], rax
7:      mov rdi, [rsp + RM_RES]
        call opcode_of
        cmp eax, OP_MEM
        jne 8f
        mov rax, [rsp + RM_RES]
        cmp dword ptr [rax + N_AUX], 2
        jne .Lrm_assert
        mov rdi, rax
        mov rsi, r12
        mov rdx, r13
        call fill_mem
        mov [rsp + RM_RES], rax
8:      mov rax, [rsp + RM_RES]
        add rsp, MATCH_BINDINGS_SIZE + 32
        LEAVE
.Lrm_assert:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_mem]
        call err_throw
ENDF replace_mem_exp_impl

# merged_call_range(func_range, args_range) -> the range covering the
# 4-byte selector and the arguments when they are adjacent (simplified),
# else 0
FUNC merged_call_range
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        call assert_range
        mov rdi, r12
        call assert_range
        cmp qword ptr [rbx + N_DATA + 16], (4 << 1) | 1
        jne 1f
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, [rbx + N_DATA + 16]
        call alg_add2
        mov rdi, rax
        mov rsi, [r12 + N_DATA + 8]
        call alg_sub_op
        cmp rax, 1
        jne 1f
        mov rdi, [rbx + N_DATA + 16]
        mov rsi, [r12 + N_DATA + 16]
        call alg_add2
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, rax
        call mk_range
        mov rdi, rax
        call simplify_exp
        add rsp, 16
        LEAVE
1:      xor eax, eax
        add rsp, 16
        LEAVE
ENDF merged_call_range

# replace_mem(trace, mem_idx, mem_val) -> list: the reads of the memory
# replaced with its value, up until it may be overwritten
FUNC replace_mem
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 64
        .set RP_IDX, MATCH_BINDINGS_SIZE
        .set RP_VAL, MATCH_BINDINGS_SIZE + 8
        .set RP_ID, MATCH_BINDINGS_SIZE + 16
        .set RP_MEMLOC, MATCH_BINDINGS_SIZE + 24
        .set RP_SPLIT, MATCH_BINDINGS_SIZE + 32
        .set RP_REST, MATCH_BINDINGS_SIZE + 40
        .set RP_I, MATCH_BINDINGS_SIZE + 48
        .set RP_COND, MATCH_BINDINGS_SIZE + 56
        mov rbx, rdi
        mov [rsp + RP_VAL], rdx
        mov rdi, rsi
        call simplify_exp
        mov [rsp + RP_IDX], rax
        mov rdi, [rsp + RP_VAL]
        call simplify_exp
        mov [rsp + RP_VAL], rax
        LOADS rdi, MEM
        mov rsi, [rsp + RP_IDX]
        call mk2
        mov [rsp + RP_ID], rax
        mov rdi, [rsp + RP_VAL]
        call is_tuple
        test eax, eax
        jz 1f
        mov rdi, [rsp + RP_VAL]
        call opcode_of
        cmp eax, OP_MEM
        je 1f
        mov rdi, [rsp + RP_VAL]
        call arith_eval
        mov [rsp + RP_VAL], rax
1:      call vec_new
        mov r12, rax
        xor r13d, r13d
.Lrp_line:
        cmp r13d, [rbx + N_AUX]
        jae .Lrp_done
        mov r14, [rbx + N_DATA + r13*8]
        inc r13d
        PAT rsi, "('setmem', ':memloc', 'Any')"
        mov rdi, r14
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 3f
        B rdi, 0
        call simplify_exp
        mov [rsp + RP_MEMLOC], rax
        mov rdi, r14
        mov rsi, [rsp + RP_IDX]
        mov rdx, [rsp + RP_VAL]
        call replace_mem_exp
        mov rdi, r12
        mov rsi, rax
        call vec_push
        mov rdi, [rsp + RP_MEMLOC]
        mov rsi, [rsp + RP_IDX]
        call range_overlaps
        cmp eax, TRI_TRUE
        jne 2f
        # the parts of the memory left: replaced in the rest
        mov rdi, [rsp + RP_IDX]
        mov rsi, [rsp + RP_MEMLOC]
        mov rdx, [rsp + RP_VAL]
        xor ecx, ecx
        call splits_mem
        mov [rsp + RP_SPLIT], rax
        mov rdi, rbx
        mov rsi, r13
        call list_from
        mov [rsp + RP_REST], rax
        mov qword ptr [rsp + RP_I], 0
21:     mov rcx, [rsp + RP_I]
        mov rax, [rsp + RP_SPLIT]
        cmp ecx, [rax + N_AUX]
        jae 22f
        mov rax, [rax + N_DATA + rcx*8]
        mov rdi, [rsp + RP_REST]
        mov rsi, [rax + N_DATA]
        mov rdx, [rax + N_DATA + 8]
        call replace_mem
        mov [rsp + RP_REST], rax
        inc qword ptr [rsp + RP_I]
        jmp 21b
22:     mov rdi, r12
        mov rsi, [rsp + RP_REST]
        call vec_extend_seq
        jmp .Lrp_done
2:      mov rdi, r14
        mov rsi, [rsp + RP_VAL]
        call affects
        test eax, eax
        jz .Lrp_line
        jmp .Lrp_rest
3:      mov rdi, r14
        call is_if_line
        test eax, eax
        jz 5f
        mov rdi, [r14 + N_DATA + 8]
        mov rsi, [rsp + RP_IDX]
        mov rdx, [rsp + RP_VAL]
        call replace_mem_exp
        mov [rsp + RP_COND], rax
        # (apply_constraint is a no-op)
        mov rdi, [r14 + N_DATA + 16]
        mov rsi, [rsp + RP_IDX]
        mov rdx, [rsp + RP_VAL]
        call replace_mem
        mov [rsp + RP_REST], rax
        mov rdi, [r14 + N_DATA + 24]
        mov rsi, [rsp + RP_IDX]
        mov rdx, [rsp + RP_VAL]
        call replace_mem
        mov rdx, rax
        mov rdi, [rsp + RP_COND]
        mov rsi, [rsp + RP_REST]
        call mk_if
        mov rdi, r12
        mov rsi, rax
        call vec_push
        # one of the branches may have changed the memory: what comes
        # after the if (if anything) is left alone
        mov rdi, r14
        mov rsi, [rsp + RP_VAL]
        call affects
        test eax, eax
        jnz .Lrp_rest
        mov rdi, r14
        mov rsi, [rsp + RP_ID]
        call affects
        test eax, eax
        jnz .Lrp_rest
        jmp .Lrp_line
5:      mov rdi, r14
        mov rsi, [rsp + RP_VAL]
        call affects
        test eax, eax
        jnz .Lrp_from_here
        mov rdi, r14
        mov rsi, [rsp + RP_ID]
        call affects
        test eax, eax
        jnz .Lrp_from_here
        mov rdi, r14
        call is_while_line
        test eax, eax
        jz 7f
        # the loop's variables get the value; its body and condition
        # too when the loop doesn't affect the memory or the value
        mov rdi, [r14 + N_DATA + 32]
        lea rsi, [rip + replace_mem_exp_cb]
        mov rdx, rsp                    # (idx, val at [rsp + RP_IDX..]: passed as the frame)
        call map_seq_with
        mov rdi, rax
        call seq_to_list                # (a list, as python's comprehension makes)
        mov [rsp + RP_SPLIT], rax       # vars
        mov rax, [r14 + N_DATA + 8]
        mov [rsp + RP_COND], rax
        mov rax, [r14 + N_DATA + 16]
        mov [rsp + RP_REST], rax
        mov rdi, r14
        mov rsi, [rsp + RP_ID]
        call affects
        test eax, eax
        jnz 6f
        mov rdi, r14
        mov rsi, [rsp + RP_VAL]
        call affects
        test eax, eax
        jnz 6f
        mov rdi, [rsp + RP_COND]
        mov rsi, [rsp + RP_IDX]
        mov rdx, [rsp + RP_VAL]
        call replace_mem_exp
        mov [rsp + RP_COND], rax
        mov rdi, [rsp + RP_REST]
        mov rsi, [rsp + RP_IDX]
        mov rdx, [rsp + RP_VAL]
        call replace_mem
        mov [rsp + RP_REST], rax
6:      mov rdi, [rsp + RP_COND]
        mov rsi, [rsp + RP_REST]
        mov rdx, [r14 + N_DATA + 24]
        mov rcx, [rsp + RP_SPLIT]
        call mk_while
        mov rdi, r12
        mov rsi, rax
        call vec_push
        jmp .Lrp_line
7:      # (for speed) only the lines mentioning memory - and the variable
        # of the index, when it has one - get the replacement
        mov rdi, r14
        lea rsi, [rip + .Ls_mem]
        call mentions_c
        test eax, eax
        jz 8f
        PAT rsi, "('add', 'Any', ('var', ':num'))"
        mov rdi, [rsp + RP_IDX]
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 71f
        B rsi, 0
        LOADS rdi, VAR
        call mk2
        mov rdi, r14
        mov rsi, rax
        call contains_value
        test eax, eax
        jz 8f
71:     mov rdi, r14
        mov rsi, [rsp + RP_IDX]
        mov rdx, [rsp + RP_VAL]
        call replace_mem_exp
        mov r14, rax
8:      mov rdi, r12
        mov rsi, r14
        call vec_push
        jmp .Lrp_line
.Lrp_from_here:
        # this line and the rest, untouched
        dec r13d
.Lrp_rest:
        mov edx, [rbx + N_AUX]
        sub edx, r13d
        lea rsi, [rbx + N_DATA + r13*8]
        mov rdi, r12
        call vec_extend
.Lrp_done:
        mov rdi, r12
        call vec_to_list
        add rsp, MATCH_BINDINGS_SIZE + 64
        LEAVE
ENDF replace_mem

# replace_mem_exp_cb(v, frame): replace_mem_exp(v, idx, val) with the
# index and value taken from replace_mem's frame
FUNC replace_mem_exp_cb
        mov rdx, [rsi + RP_VAL]
        mov rsi, [rsi + RP_IDX]
        jmp replace_mem_exp
ENDF replace_mem_exp_cb

# seq_to_list(seq) -> list with the same elements
FUNC seq_to_list
        mov esi, [rdi + N_AUX]
        lea rdx, [rdi + N_DATA]
        mov edi, K_LIST
        jmp mk_seq
ENDF seq_to_list

# map_seq_with(seq, f, arg) -> a sequence of the same kind with f(e, arg)
# applied to every element
FUNC map_seq_with
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov edi, [rbx + N_AUX]
        shl rdi, 3
        call arena_alloc
        mov [rsp], rax
        xor r14d, r14d
1:      cmp r14d, [rbx + N_AUX]
        jae 2f
        mov rdi, [rbx + N_DATA + r14*8]
        mov rsi, r13
        call r12
        mov rcx, [rsp]
        mov [rcx + r14*8], rax
        inc r14d
        jmp 1b
2:      mov edi, [rbx + N_KIND]
        mov esi, [rbx + N_AUX]
        mov rdx, [rsp]
        call mk_seq
        add rsp, 16
        LEAVE
ENDF map_seq_with

# --- variables cleanup ---

# cleanup_vars(trace, required_after) -> list: for every variable, its
# future occurrences replaced with its value if possible, and the
# declarations no longer in use removed. `required_after` (a list, or 0)
# are the variables used after the trace.
FUNC cleanup_vars
        ENTER
        sub rsp, 48
        .set CV_REQ, 0
        .set CV_REMAINING, 8
        .set CV_TMP, 16
        .set CV_TMP2, 24
        .set CV_REQ2, 32
        mov rbx, rdi
        test rsi, rsi
        jnz 1f
        xor edi, edi
        xor esi, esi
        call mk_list
        mov rsi, rax
1:      mov [rsp + CV_REQ], rsi
        call vec_new
        mov r12, rax
        xor r13d, r13d
.Lcv_line:
        cmp r13d, [rbx + N_AUX]
        jae .Lcv_done
        mov r14, [rbx + N_DATA + r13*8]
        inc r13d
        mov rdi, r14
        call opcode_of
        cmp eax, OP_SETVAR
        je .Lcv_setvar
        cmp eax, OP_WHILE
        je .Lcv_while
        mov rdi, r14
        call is_if_line
        test eax, eax
        jnz .Lcv_if
        mov rdi, r12
        mov rsi, r14
        call vec_push
        jmp .Lcv_line
.Lcv_setvar:
        mov rdi, [r14 + N_DATA + 16]
        mov esi, MAX_EXP_SIZE
        call exp_size_over
        test eax, eax
        jz 2f
        # the vm gave a name to this expression because it's huge,
        # inlining it would make everything else huge as well
        mov rdi, r12
        mov rsi, r14
        call vec_push
        mov rdi, rbx
        mov rsi, r13
        call list_from
        mov rdi, rax
        mov rsi, [rsp + CV_REQ]
        call cleanup_vars
        mov rdi, r12
        mov rsi, rax
        call vec_extend_seq
        jmp .Lcv_done
2:      mov rdi, rbx
        mov rsi, r13
        call list_from
        mov rdi, rax
        mov rsi, [r14 + N_DATA + 8]
        mov rdx, [r14 + N_DATA + 16]
        call replace_var
        mov [rsp + CV_REMAINING], rax
        # kept when the variable is still used
        LOADS rdi, VAR
        mov rsi, [r14 + N_DATA + 8]
        call mk2
        mov [rsp + CV_TMP], rax
        mov rdi, [rsp + CV_REMAINING]
        mov rsi, rax
        call contains
        test eax, eax
        jnz 3f
        mov rdi, [rsp + CV_REQ]
        mov rsi, [rsp + CV_TMP]
        call seq_contains
        test eax, eax
        jz 4f
3:      mov rdi, r12
        mov rsi, r14
        call vec_push
4:      mov rdi, [rsp + CV_REMAINING]
        mov rsi, [rsp + CV_REQ]
        call cleanup_vars
        mov rdi, r12
        mov rsi, rax
        call vec_extend_seq
        jmp .Lcv_done
.Lcv_while:
        # the body, with the variables of what follows required
        mov rdi, rbx
        mov rsi, r13
        call list_from
        mov rdi, rax
        call vars_of_trace
        mov rdi, [rsp + CV_REQ]
        mov rsi, rax
        call list_concat
        mov [rsp + CV_REQ2], rax
        mov rdi, [r14 + N_DATA + 16]
        mov rsi, rax
        call cleanup_vars
        mov rsi, rax
        mov rdi, [r14 + N_DATA + 8]
        mov rdx, [r14 + N_DATA + 24]
        mov rcx, [r14 + N_DATA + 32]
        call mk_while
        mov rdi, r12
        mov rsi, rax
        call vec_push
        mov rdi, r14
        call parse_counters
        cmp qword ptr [rax + PC_ENDVARS], 0
        je .Lcv_line
        # the variables are known after the loop: replaced in the rest
        mov rax, [rax + PC_ENDVARS]
        mov [rsp + CV_TMP], rax
        mov rdi, rbx
        mov rsi, r13
        call list_from
        mov [rsp + CV_REMAINING], rax
        mov qword ptr [rsp + CV_TMP2], 0
5:      mov rcx, [rsp + CV_TMP2]
        mov rax, [rsp + CV_TMP]
        cmp ecx, [rax + N_AUX]
        jae 6f
        mov rax, [rax + N_DATA + rcx*8]
        mov rdi, [rsp + CV_REMAINING]
        mov rsi, [rax + N_DATA]
        mov rdx, [rax + N_DATA + 8]
        call replace_var
        mov [rsp + CV_REMAINING], rax
        inc qword ptr [rsp + CV_TMP2]
        jmp 5b
6:      mov rdi, [rsp + CV_REMAINING]
        mov rsi, [rsp + CV_REQ2]
        call cleanup_vars
        mov rdi, r12
        mov rsi, rax
        call vec_extend_seq
        jmp .Lcv_done
.Lcv_if:
        # a variable set in a branch may be used after the if, when the
        # branches merge again
        mov rdi, rbx
        mov rsi, r13
        call list_from
        mov rdi, rax
        call vars_of_trace
        mov rdi, [rsp + CV_REQ]
        mov rsi, rax
        call list_concat
        mov [rsp + CV_REQ2], rax
        mov rdi, [r14 + N_DATA + 16]
        call .Lcv_branch
        mov [rsp + CV_TMP], rax
        mov rdi, [r14 + N_DATA + 24]
        call .Lcv_branch
        mov rdx, rax
        mov rsi, [rsp + CV_TMP]
        mov rdi, [r14 + N_DATA + 8]
        call mk_if
        mov rdi, r12
        mov rsi, rax
        call vec_push
        jmp .Lcv_line
.Lcv_done:
        mov rdi, r12
        call vec_to_list
        add rsp, 48
        LEAVE

# local: cleanup_vars(branch, required or required_after when the branch
# ends the execution)
.Lcv_branch:
        sub rsp, 24
        mov [rsp], rdi
        call trace_ends_execution
        mov rsi, [rsp + 24 + 8 + CV_REQ2]
        test eax, eax
        jz 7f
        mov rsi, [rsp + 24 + 8 + CV_REQ]
7:      mov rdi, [rsp]
        call cleanup_vars
        add rsp, 24
        ret
ENDF cleanup_vars

# vars_of_trace(trace) -> list: the ('var', ...) expressions in it
FUNC vars_of_trace
        ENTER
        mov rbx, rdi
        call vec_new
        mov r12, rax
        mov rdi, rbx
        mov esi, OP_VAR
        mov rdx, r12
        call find_op_list
        mov rdi, r12
        call vec_to_list
        LEAVE
ENDF vars_of_trace

# replace_var(trace, var_idx, var_val) -> list: the occurrences of the
# variable replaced, where possible
FUNC replace_var
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 48
        .set RV_IDX, MATCH_BINDINGS_SIZE
        .set RV_VAL, MATCH_BINDINGS_SIZE + 8
        .set RV_ID, MATCH_BINDINGS_SIZE + 16
        .set RV_COND, MATCH_BINDINGS_SIZE + 24
        .set RV_PATH, MATCH_BINDINGS_SIZE + 32
        .set RV_SETVARS, MATCH_BINDINGS_SIZE + 40
        mov rbx, rdi
        mov [rsp + RV_IDX], rsi
        mov [rsp + RV_VAL], rdx
        LOADS rdi, VAR
        call mk2
        mov [rsp + RV_ID], rax
        call vec_new
        mov r12, rax
        xor r13d, r13d
.Lrv_line:
        cmp r13d, [rbx + N_AUX]
        jae .Lrv_done
        mov r14, [rbx + N_DATA + r13*8]
        inc r13d
        PAT rsi, "('setmem', ':mem_idx', 'Any')"
        mov rdi, r14
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 1f
        # (this all seems incorrect, plus the 'affects' checks below:
        # to be revisited)
        mov rdi, r14
        mov rsi, [rsp + RV_ID]
        mov rdx, [rsp + RV_VAL]
        call replace
        mov rdi, r12
        mov rsi, rax
        call vec_push
        mov rdi, r14
        mov rsi, [rsp + RV_VAL]
        call affects
        test eax, eax
        jz .Lrv_line
        jmp .Lrv_rest
1:      mov rdi, r14
        call is_while_line
        test eax, eax
        jz 3f
        mov rdi, [r14 + N_DATA + 32]
        mov rsi, [rsp + RV_ID]
        mov rdx, [rsp + RV_VAL]
        call replace
        mov [rsp + RV_SETVARS], rax
        mov rax, [r14 + N_DATA + 8]
        mov [rsp + RV_COND], rax
        mov rax, [r14 + N_DATA + 16]
        mov [rsp + RV_PATH], rax
        mov rdi, r14
        mov rsi, [rsp + RV_VAL]
        call affects
        test eax, eax
        jnz 2f
        mov rdi, [rsp + RV_COND]
        mov rsi, [rsp + RV_ID]
        mov rdx, [rsp + RV_VAL]
        call replace
        mov [rsp + RV_COND], rax
        mov rdi, [rsp + RV_PATH]
        mov rsi, [rsp + RV_IDX]
        mov rdx, [rsp + RV_VAL]
        call replace_var
        mov [rsp + RV_PATH], rax
2:      mov rdi, [rsp + RV_COND]
        mov rsi, [rsp + RV_PATH]
        mov rdx, [r14 + N_DATA + 24]
        mov rcx, [rsp + RV_SETVARS]
        call mk_while
        mov r14, rax
        # then, as in python: when the (rebuilt) loop affects the value,
        # it and the rest are left alone
        mov rdi, r12
        mov rsi, r14
        call vec_push
        mov rdi, r14
        mov rsi, [rsp + RV_VAL]
        call affects
        test eax, eax
        jnz .Lrv_rest
        jmp .Lrv_line
3:      mov rdi, r14
        call is_if_line
        test eax, eax
        jz 4f
        mov rdi, [r14 + N_DATA + 8]
        mov rsi, [rsp + RV_ID]
        mov rdx, [rsp + RV_VAL]
        call replace
        mov [rsp + RV_COND], rax
        mov rdi, [r14 + N_DATA + 16]
        mov rsi, [rsp + RV_IDX]
        mov rdx, [rsp + RV_VAL]
        call replace_var
        mov [rsp + RV_PATH], rax
        mov rdi, [r14 + N_DATA + 24]
        mov rsi, [rsp + RV_IDX]
        mov rdx, [rsp + RV_VAL]
        call replace_var
        mov rdx, rax
        mov rdi, [rsp + RV_COND]
        mov rsi, [rsp + RV_PATH]
        call mk_if
        mov rdi, r12
        mov rsi, rax
        call vec_push
        # one of the branches may have changed the memory the value
        # depends on: what comes after the if is left alone
        mov rdi, r14
        mov rsi, [rsp + RV_VAL]
        call affects
        test eax, eax
        jz .Lrv_line
        jmp .Lrv_rest
4:      mov rdi, r14
        mov rsi, [rsp + RV_VAL]
        call affects
        test eax, eax
        jz 5f
        mov rdi, r12
        mov rsi, r14
        call vec_push
        jmp .Lrv_rest
5:      mov rdi, r14
        mov rsi, [rsp + RV_ID]
        mov rdx, [rsp + RV_VAL]
        call replace
        mov rdi, r12
        mov rsi, rax
        call vec_push
        jmp .Lrv_line
.Lrv_rest:
        mov edx, [rbx + N_AUX]
        sub edx, r13d
        lea rsi, [rbx + N_DATA + r13*8]
        mov rdi, r12
        call vec_extend
.Lrv_done:
        mov rdi, r12
        call vec_to_list
        add rsp, MATCH_BINDINGS_SIZE + 48
        LEAVE
ENDF replace_var

# --- readability ---

# replace_while_var(rest, counter_idx, new_idx) -> rax = the trace with
# the variable renamed, rdx = the index used (the first free one)
FUNC replace_while_var
        ENTER
        sub rsp, 32
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
1:      LOADS rdi, VAR
        mov rsi, r13
        call mk2
        mov rdi, rbx
        mov rsi, rax
        call contains
        test eax, eax
        jz 2f
        add r13, 2                      # (tagged: += 1)
        jmp 1b
2:      mov rdi, r12
        mov rsi, r13
        call mk2
        mov [rsp], rax                  # (counter_idx, new_idx)
        mov rdi, rbx
        lea rsi, [rip + rename_var_cb]
        mov rdx, rax
        call replace_f
        mov rdi, rax
        call simplify_exp
        mov rdx, r13
        add rsp, 32
        LEAVE
ENDF replace_while_var

# rename_var_cb(exp, (old, new)) -> exp with the variable old renamed new
FUNC rename_var_cb
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE
        mov rbx, rdi
        mov r12, rsi
        LOADS rdi, VAR
        mov rsi, [r12 + N_DATA]
        call mk2
        cmp rax, rbx
        jne 1f
        LOADS rdi, VAR
        mov rsi, [r12 + N_DATA + 8]
        call mk2
        jmp 3f
1:      PAT rsi, "('setvar', ':idx', ':val')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 2f
        B rax, 0
        cmp rax, [r12 + N_DATA]
        jne 2f
        B rdx, 1
        mov rsi, [r12 + N_DATA + 8]
        LOADS rdi, SETVAR
        call mk3
        jmp 3f
2:      mov rax, rbx
3:      add rsp, MATCH_BINDINGS_SIZE
        LEAVE
ENDF rename_var_cb

# readability(trace) -> list: nicer variable names, and the msize
# expressions in setmems named
FUNC readability
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 64
        .set RD_RES, MATCH_BINDINGS_SIZE
        .set RD_REST, MATCH_BINDINGS_SIZE + 8
        .set RD_M, MATCH_BINDINGS_SIZE + 16
        .set RD_A, MATCH_BINDINGS_SIZE + 24
        .set RD_COUNTER, MATCH_BINDINGS_SIZE + 32
        .set RD_NEW, MATCH_BINDINGS_SIZE + 40
        .set RD_I, MATCH_BINDINGS_SIZE + 48
        lea rsi, [rip + canonise_max_cb]
        xor edx, edx
        call replace_f
        mov rbx, rax
        call vec_new
        mov [rsp + RD_RES], rax
        xor r13d, r13d
.Lrd_line:
        cmp r13d, [rbx + N_AUX]
        jae .Lrd_done
        mov r14, [rbx + N_DATA + r13*8]
        PAT rsi, "('setmem', ('range', ('add', '...'), 'Any'), ':mem_val')"
        mov rdi, r14
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 3f
        # a max among the terms of the memory index: msize
        mov rax, [r14 + N_DATA + 8]
        mov r12, [rax + N_DATA + 8]     # the add
        mov qword ptr [rsp + RD_I], 1
1:      mov rcx, [rsp + RD_I]
        cmp ecx, [r12 + N_AUX]
        jae 2f
        mov rdi, [r12 + N_DATA + rcx*8]
        mov [rsp + RD_M], rdi
        call opcode_of
        cmp eax, OP_MAX
        je 11f
        inc qword ptr [rsp + RD_I]
        jmp 1b
11:     lea rdi, [rip + .Ls_msize_var]
        call str_intern_c
        mov rsi, rax
        mov rdx, [rsp + RD_M]
        LOADS rdi, SETVAR
        call mk3
        mov rdi, [rsp + RD_RES]
        mov rsi, rax
        call vec_push
        # the rest, with the max replaced by the variable
        lea rdi, [rip + .Ls_msize_var]
        call str_intern_c
        mov rsi, rax
        LOADS rdi, VAR
        call mk2
        mov rdi, [rsp + RD_M]
        mov rsi, rax
        call mk2
        mov [rsp + RD_M], rax           # (max, ('var', '_msize'))
        mov rdi, rbx
        mov rsi, r13
        call list_from
        mov rdi, rax
        lea rsi, [rip + replace_pair_cb]
        mov rdx, [rsp + RD_M]
        call rewrite_trace
        mov rdi, rax
        call readability
        mov rdi, [rsp + RD_RES]
        mov rsi, rax
        call vec_extend_seq
        jmp .Lrd_done
2:      jmp .Lrd_asis
3:      mov rdi, r14
        call is_if_line
        test eax, eax
        jz 5f
        # `if x: ... else: revert` becomes `if not x: revert else: ...`
        mov rax, [r14 + N_DATA + 24]
        cmp dword ptr [rax + N_AUX], 1
        jne 4f
        mov rdi, [rax + N_DATA]
        call opcode_of
        cmp eax, OP_REVERT
        jne 4f
        mov rdi, [r14 + N_DATA + 8]
        call is_zero
        mov [rsp + RD_M], rax
        mov rdi, [r14 + N_DATA + 24]
        call readability
        mov [rsp + RD_REST], rax
        mov rdi, [r14 + N_DATA + 16]
        call readability
        mov rdx, rax
        mov rdi, [rsp + RD_M]
        mov rsi, [rsp + RD_REST]
        call mk_if
        jmp 41f
4:      mov rdi, [r14 + N_DATA + 16]
        call readability
        mov [rsp + RD_REST], rax
        mov rdi, [r14 + N_DATA + 24]
        call readability
        mov rdx, rax
        mov rdi, [r14 + N_DATA + 8]
        mov rsi, [rsp + RD_REST]
        call mk_if
41:     mov rdi, [rsp + RD_RES]
        mov rsi, rax
        call vec_push
        inc r13d
        jmp .Lrd_line
5:      mov rdi, r14
        call opcode_of
        cmp eax, OP_WHILE
        jne .Lrd_asis
        # the variables of a loop get normalized names: the counter 0,
        # the others from 1
        mov rdi, r14
        call parse_counters
        mov [rsp + RD_A], rax
        mov rdi, rbx
        mov rsi, r13
        call list_from
        mov [rsp + RD_REST], rax
        mov rax, [rsp + RD_A]
        mov rax, [rax + PC_COUNTER]
        mov [rsp + RD_COUNTER], rax
        test rax, rax
        jnz 51f
        mov qword ptr [rsp + RD_COUNTER], -1    # (no counter: nothing matches)
        jmp 52f
51:     mov rdi, [rsp + RD_REST]
        mov rsi, rax
        mov edx, 1                      # 0
        call replace_while_var
        mov [rsp + RD_REST], rax
52:     mov qword ptr [rsp + RD_NEW], 3 # new_idx = 1
        mov r12, [r14 + N_DATA + 32]    # vars
        mov qword ptr [rsp + RD_I], 0
6:      mov rcx, [rsp + RD_I]
        cmp ecx, [r12 + N_AUX]
        jae 7f
        mov rax, [r12 + N_DATA + rcx*8]
        mov rsi, [rax + N_DATA + 8]     # v_idx
        cmp rsi, [rsp + RD_COUNTER]
        je 61f
        mov rdi, [rsp + RD_REST]
        mov rdx, [rsp + RD_NEW]
        call replace_while_var
        mov [rsp + RD_REST], rax
        mov [rsp + RD_NEW], rdx
61:     inc qword ptr [rsp + RD_I]
        jmp 6b
7:      mov rax, [rsp + RD_REST]
        mov r14, [rax + N_DATA]         # the renamed while
        mov rdi, [r14 + N_DATA + 16]
        call readability
        mov rsi, rax
        mov rdi, [r14 + N_DATA + 8]
        mov rdx, [r14 + N_DATA + 24]
        mov rcx, [r14 + N_DATA + 32]
        call mk_while
        mov rdi, [rsp + RD_RES]
        mov rsi, rax
        call vec_push
        mov rdi, [rsp + RD_REST]
        mov esi, 1
        call list_from
        mov rdi, rax
        call readability
        mov rdi, [rsp + RD_RES]
        mov rsi, rax
        call vec_extend_seq
        jmp .Lrd_done
.Lrd_asis:
        mov rdi, [rsp + RD_RES]
        mov rsi, r14
        call vec_push
        inc r13d
        jmp .Lrd_line
.Lrd_done:
        mov rdi, [rsp + RD_RES]
        call vec_to_list
        add rsp, MATCH_BINDINGS_SIZE + 64
        LEAVE
ENDF readability

FUNC canonise_max_cb
        jmp canonise_max
ENDF canonise_max_cb

# replace_pair_cb(line, (what, by), out): the line with `what` replaced
FUNC replace_pair_cb
        ENTER
        mov rbx, rdx
        mov rdx, [rsi + N_DATA + 8]
        mov rsi, [rsi + N_DATA]
        call replace
        mov rdi, rbx
        mov rsi, rax
        call vec_push
        LEAVE
ENDF replace_pair_cb

# replace_bytes_or_string_length(trace) -> list: the length of a
# storage string/bytes (see the unicorn contract)
FUNC replace_bytes_or_string_length
        ENTER
        lea rsi, [rip + string_length_cb]
        xor edx, edx
        call replace_f_stop
        LEAVE
ENDF replace_bytes_or_string_length

FUNC string_length_cb
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 16
        mov rbx, rdi
        PAT rsi, "('mask_shl', ':size', ':offset', -1, ('and', ('storage', 'Any', 0, ':key'), ('add', -1, ('mask_shl', 'Any', 'Any', 'Any', ('iszero', ('storage', 'Any', 0, ':key'))))))"
        mov rdx, rsp
        call pat_match
        test eax, eax
        jnz 1f
        PAT rsi, "('mask_shl', ':size', ':offset', -1, ('and', ('add', -1, ('mask_shl', 'Any', 'Any', 'Any', ('iszero', ('storage', 'Any', 0, ':key')))), ('storage', 'Any', 0, ':key')))"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz .Lsl_none
1:      # key: size [rsp], offset [rsp + 8], key [rsp + 16]
        B rdi, 2
        call is_int
        test eax, eax
        jz 2f
        LOADS rdi, LOC
        B rsi, 2
        call mk2
        mov [rsp + 16], rax
2:      LOADS rdi, LENGTH
        B rsi, 2
        call mk2
        mov rcx, rax
        LOADS rdi, STORAGE
        mov esi, (256 << 1) | 1
        mov edx, 1
        call mk4
        mov r12, rax                    # ('storage', 256, 0, ('length', key))
        B rax, 0
        cmp rax, (255 << 1) | 1
        jne 3f
        B rax, 1
        cmp rax, 3
        jne 3f
        mov rax, r12
        jmp .Lsl_done
3:      B rax, 1
        cmp rax, 3
        jl .Lsl_assert
        sub rax, 2                      # offset - 1
        mov rdx, rax
        B rsi, 0
        mov r8, r12
        LOADS rdi, MASK_SHL
        mov ecx, 1
        call mk5
        jmp .Lsl_done
.Lsl_none:
        xor eax, eax
.Lsl_done:
        add rsp, MATCH_BINDINGS_SIZE + 16
        LEAVE
.Lsl_assert:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_range]
        call err_throw
ENDF string_length_cb

        .section .note.GNU-stack,"",@progbits
