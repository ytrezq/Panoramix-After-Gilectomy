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
        mov \reg, [rsp + 8*(\n)]
.endm

# --- conditions ---

# cleanup_conds(trace) -> list: removes the ifs/whiles whose conditions
# are obviously true or false
FUNC cleanup_conds
        STACK_CHECK
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
        lea rsi, [rip + sp_true]        # (python's known_true=True)
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
        lea rsi, [rip + sp_true]        # (python's known_true=True)
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
        lea rcx, [rip + .Lset_msize_cmp]        # lt, le, gt, ge
        cmp byte ptr [rcx + rax], 0
        je .Lem_none
        mov rdi, [rbx + N_DATA + 8]
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

        OPSET_MEMBER msize_cmp, OP_LT
        OPSET_MEMBER msize_cmp, OP_LE
        OPSET_MEMBER msize_cmp, OP_GT
        OPSET_MEMBER msize_cmp, OP_GE
        OPSET_END msize_cmp, OP_COUNT

# cleanup_msize(trace) -> list: msize replaced by the memory size where
# it is known
FUNC cleanup_msize
        ENTER
        sub rsp, 16
        # a trace that doesn't mention msize comes back as it is: the msize
        # python computes along the way (a max of every memory write, whose
        # terms are compared with each other - the costliest part of some
        # contracts) is only ever used to replace msize
        mov rbx, rdi
        mov rsi, HF_MSIZE
        call mentions
        test eax, eax
        jz 1f
        mov rdi, rbx
        mov esi, 1
        lea rdx, [rsp]
        call cleanup_msize_impl
        add rsp, 16
        LEAVE
1:      mov rax, rbx
        add rsp, 16
        LEAVE
ENDF cleanup_msize

# cleanup_msize_impl(trace, current_msize, &msize_out) -> list
FUNC cleanup_msize_impl
        STACK_CHECK
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
        mov rsi, HF_MSIZE
        call mentions
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
        push rax
        push rax
        LOADS rax, MSIZE
        pop rdx                         # max_to_add(current_msize)
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
        VEQ rax, [rsp + CM_FALSE]
        je 41f
        # we could take the max of both, but that gets expensive quickly,
        # and msize isn't used by any recent compiler
        LOADS rax, MSIZE
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
        LOADS rax, MSIZE
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
        STACK_CHECK
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE
        mov rbx, rdi
        mov r12, rsi
        mov esi, OP_SETMEM              # ('setmem', set_idx, Any)
        mov edx, 3
        call is_op_n
        test eax, eax
        jz 1f
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, r12
        call range_overlaps
        cmp eax, TRI_FALSE
        setne al
        movzx eax, al
        jmp .Lom_done
1:      mov rdi, rbx
        OPCODE_OF_RDI
        cmp eax, OP_WHILE
        je 3f
        mov rdi, rbx
        call is_if_line
        test eax, eax
        jz .Lom_no
3:      # a while or an if: its walk remembered for the pair (the ifs nest,
        # and replace_mem asks it of each level, then of the ones inside
        # when it goes into the branches)
        mov edi, MEMO_OVERWRITES
        mov rsi, rbx
        mov rdx, r12
        call memo2_get
        test rax, rax
        jz 4f
        cmp rax, MEMO_TRUE
        sete al
        movzx eax, al
        jmp .Lom_done
4:      mov rdi, rbx
        OPCODE_OF_RDI
        cmp eax, OP_WHILE
        jne 5f
        mov rdi, rbx
        mov rsi, r12
        call while_touches_mem
        jmp 6f
5:      # matters for what comes after the if, when its branches merge again
        mov rdi, [rbx + N_DATA + 16]
        mov rsi, r12
        call any_overwrites_mem
        test eax, eax
        jnz 6f
        mov rdi, [rbx + N_DATA + 24]
        mov rsi, r12
        call any_overwrites_mem
6:      mov [rsp], eax
        mov ecx, MEMO_FALSE
        test eax, eax
        jz 7f
        mov ecx, MEMO_TRUE
7:      mov edi, MEMO_OVERWRITES
        mov rsi, rbx
        mov rdx, r12
        call memo2_put
        mov eax, [rsp]
        jmp .Lom_done
.Lom_no:
        xor eax, eax
.Lom_done:
        add rsp, MATCH_BINDINGS_SIZE
        LEAVE
ENDF overwrites_mem

# any_overwrites_mem(trace, mem_idx) -> eax
FUNC any_overwrites_mem
        STACK_CHECK
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
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov rdi, r12
        call is_tuple
        test eax, eax
        jnz 1f
        LOADS rax, MSIZE
        cmp r12, rax
        jne .Laf_no
1:      mov rdi, r12
        mov rsi, HF_MSIZE
        call mentions
        test eax, eax
        jz 2f
        LOADS rax, UNDEFINED
        mov rsi, rax
        mov edi, 1
        call mk_range
        mov rdi, rbx
        mov rsi, rax
        call overwrites_mem
        test eax, eax
        jnz .Laf_yes
2:      mov rdi, r12
        mov rsi, HF_MEM
        call mentions
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
        STACK_CHECK
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
        mov rdi, r14                    # ('setmem', memloc, memval)
        mov esi, OP_SETMEM
        mov edx, 3
        call is_op_n
        test eax, eax
        jz 2f
        mov rax, [r14 + N_DATA + 8]
        mov [rsp], rax
        mov rax, [r14 + N_DATA + 16]
        mov [rsp + 8], rax
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
        OPCODE_OF_RDI
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
        OPCODE_OF_RDI
        cmp eax, OP_CONTINUE
        je .Lmu_used
        mov rdi, r14
        mov rsi, r12
        call exp_uses_mem
        test eax, eax
        jnz .Lmu_used
        mov rdi, r14
        OPCODE_OF_RDI
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
        STACK_CHECK
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
        STACK_CHECK
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
# `used_after` (a list, or 0) is what gets executed after `trace`.
# Remembered for the pair (a pure function of the two: simplify_trace's
# rounds, and its three calls at the end, give it the trace it made the
# round before once nothing changes any more - and the rests of the trace
# after the last change, the branches, are asked again whatever changed)
FUNC cleanup_mems
        STACK_CHECK
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
        mov edi, MEMO_CLEANUP_MEMS
        mov rdx, rsi
        mov rsi, rbx
        call memo2_get
        test rax, rax
        jz 2f
        add rsp, MATCH_BINDINGS_SIZE + 48
        LEAVE
2:      call vec_new
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
        JT_SWITCH ce, OP_COUNT, .Lce_other
        JT_CASE ce, OP_CALL, .Lce_call
        JT_CASE ce, OP_STATICCALL, .Lce_call
        JT_CASE ce, OP_DELEGATECALL, .Lce_call
        JT_CASE ce, OP_SETMEM, .Lce_setmem
        JT_CASE ce, OP_WHILE, .Lce_while
        JT_END ce, OP_COUNT, .Lce_other
.Lce_other:
        mov rdi, r14
        call is_if_line
        test eax, eax
        jnz 6f
        jmp .Lce_push
.Lce_call:
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
.Lce_setmem:
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
.Lce_while:
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
        mov rsi, rbx
        call vec_to_list_like           # (the trace itself when unchanged)
        mov r12, rax
        mov edi, MEMO_CLEANUP_MEMS
        mov rsi, rbx
        mov rdx, [rsp + CE_AFTER]
        mov rcx, rax
        call memo2_put
        mov rax, r12
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
        STACK_CHECK
        ENTER
        sub rsp, 32
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        call is_tuple
        test eax, eax
        jz 0f
        # without "mem" anywhere in it (its mention flags), nothing to
        # replace: no read of the memory, no call pattern (('mem', ...)
        # arguments), the tuple unchanged - python's walk gives it back
        movabs rax, HF_MEM
        test [rbx + N_HASH], rax
        jnz 1f
0:      mov rax, rbx
        add rsp, 32
        LEAVE
1:      mov edi, MEMO_REPLACE_MEM_EXP   # (a memo of triples: no key tuple made)
        mov rsi, rbx
        mov rdx, r12
        mov rcx, r13
        call memo3_get
        test rax, rax
        jnz 2f
        mov rdi, rbx
        mov rsi, r12
        mov rdx, r13
        call replace_mem_exp_impl
        mov [rsp], rax
        mov edi, MEMO_REPLACE_MEM_EXP
        mov rsi, rbx
        mov rdx, r12
        mov rcx, r13
        mov r8, rax
        call memo3_put
        mov rax, [rsp]
2:      add rsp, 32
        LEAVE
ENDF replace_mem_exp

FUNC replace_mem_exp_impl
        STACK_CHECK
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
        call arena_alloc_raw   # (every element written)
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
3:      mov rdi, rbx
        mov rsi, [rsp + RM_ELEMS]
        call mk_seq_like
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
        mov rdi, [rsp + RM_RES]
        mov esi, OP_DELEGATECALL
        mov edx, 5
        call is_op_n
        test eax, eax
        jz 4f
        PAT rsi, "('delegatecall', ':gas', ':addr', ('mem', ':func'), ('mem', ':args'))"
        mov rdi, [rsp + RM_RES]
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 4f
        B rdi, 2
        B rsi, 3
        call merged_call_range
        VEQ rax, r12
        jne 4f
        B rsi, 0
        B rdx, 1
        lea rcx, [rip + sp_none]
        mov r8, r13
        LOADS rdi, DELEGATECALL
        call mk5
        mov [rsp + RM_RES], rax
4:      mov rdi, [rsp + RM_RES]
        mov esi, OP_CALL
        mov edx, 6
        call is_op_n
        test eax, eax
        jz 6f
        PAT rsi, "('call', ':gas', ':addr', ':value', ('mem', ':func'), ('mem', ':args'))"
        mov rdi, [rsp + RM_RES]
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 6f
        B rdi, 3
        B rsi, 4
        call merged_call_range
        VEQ rax, r12
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
        VEQ rax, rbx
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
# replaced with its value, up until it may be overwritten. Remembered for
# the three (a pure function of them: cleanup_mems asks it of the rest of
# the trace after each setmem, round after round - the rest the same
# when what changed came before the setmem - and of the branches)
FUNC replace_mem
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov edi, MEMO_REPLACE_MEM
        mov rsi, rbx
        mov rdx, r12
        mov rcx, r13
        call memo3_get
        test rax, rax
        jnz 1f
        mov rdi, rbx
        mov rsi, r12
        mov rdx, r13
        call replace_mem_impl
        mov r14, rax
        mov edi, MEMO_REPLACE_MEM
        mov rsi, rbx
        mov rdx, r12
        mov rcx, r13
        mov r8, rax
        call memo3_put
        mov rax, r14
1:      LEAVE
ENDF replace_mem

FUNC replace_mem_impl
        STACK_CHECK
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
        mov rdi, r14                    # ('setmem', memloc, Any)
        mov esi, OP_SETMEM
        mov edx, 3
        call is_op_n
        test eax, eax
        jz 3f
        mov rax, [r14 + N_DATA + 8]
        mov [rsp], rax
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
        # after the if (if anything) is left alone. (Even an if without
        # "mem" in it is rebuilt: python's replace_mem turns the vars of
        # the whiles it goes through into lists.)
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
5:      # (affects() can only be true of a while here: overwrites_mem is
        # false of every line but a setmem, a while and an if)
        mov rdi, r14
        OPCODE_OF_RDI
        cmp eax, OP_WHILE
        jne 7f
        mov rdi, r14
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
        mov rsi, HF_MEM
        call mentions
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
        mov rsi, rbx                    # (unchanged: the trace itself)
        call vec_to_list_like
        add rsp, MATCH_BINDINGS_SIZE + 64
        LEAVE
ENDF replace_mem_impl

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
        call arena_alloc_raw   # (every element written)
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
2:      mov rdi, rbx
        mov rsi, [rsp]
        call mk_seq_like
        add rsp, 16
        LEAVE
ENDF map_seq_with

# --- variables cleanup ---

# The `required_after` of cleanup_vars: the variables that what follows a
# branch or a loop may still use. Python concatenates lists of every
# occurrence and searches them (`("var", idx) in required_after`) - here a
# chain of levels, one per `req_new`, each the variables of a trace (the
# rest of a trace after an if or a while), searched by `req_has`. A
# level's map of them is made at its first search: most levels are never
# searched (a few thousand searches for as many levels on UniV3Pool, whose
# lines mention variables 30 times each).
.set RQ_MAP, 0                          # the map, or 0 until searched
.set RQ_PARENT, 8
.set RQ_TRACE, 16                       # the trace whose variables they are
.set RQ_SIZEOF, 24

# req_new(parent, trace) -> req: the parent's variables plus the ones the
# trace mentions (required_after + find_op_list(trace, "var"))
FUNC req_new
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov edi, RQ_SIZEOF
        call arena_alloc
        mov [rax + RQ_PARENT], rbx
        mov [rax + RQ_TRACE], r12
        mov qword ptr [rax + RQ_MAP], 0
        LEAVE
ENDF req_new

# req_map(req) -> rax: the map of the level's variables, made the first
# time (the variables of each line remembered: line_vars)
FUNC req_map
        mov rax, [rdi + RQ_MAP]
        test rax, rax
        jz 1f
        ret
1:      ENTER
        sub rsp, 16
        mov rbx, rdi
        call map_new
        mov r13, rax
        mov r12, [rbx + RQ_TRACE]
        xor r14d, r14d
2:      cmp r14d, [r12 + N_AUX]
        jae 4f
        mov rdi, [r12 + N_DATA + r14*8]
        inc r14
        call line_vars
        mov [rsp], rax
        mov qword ptr [rsp + 8], 0
3:      mov rax, [rsp]
        mov rcx, [rsp + 8]
        cmp ecx, [rax + N_AUX]
        jae 2b
        mov rsi, [rax + N_DATA + rcx*8]
        inc qword ptr [rsp + 8]
        mov rdi, r13
        mov edx, 2                      # (any non-zero value)
        call map_put
        jmp 3b
4:      mov [rbx + RQ_MAP], r13
        mov rax, r13
        add rsp, 16
        LEAVE
ENDF req_map

# line_vars(line) -> list: the ('var', ...) the line mentions -
# find_op_list(line, "var"), each once, in no particular order -
# remembered. An if's or a while's from the variables of the lines of
# its branches, remembered too (replace_var rebuilds an if with a branch
# changed: the lines it kept are known)
FUNC line_vars
        STACK_CHECK
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov edi, MEMO_LINE_VARS
        mov rsi, rbx
        call memo_get
        test rax, rax
        jnz 9f
        call vec_new
        mov r12, rax
        mov rdi, rbx
        OPCODE_OF_RDI
        cmp eax, OP_IF
        je 10f
        cmp eax, OP_WHILE
        je 10f
        mov rdi, rbx
        mov esi, OP_VAR
        mov rdx, r12
        call find_op_list
        jmp 0f
10:     # its elements: a list (of lines) line by line, the rest walked
        xor r13d, r13d
11:     cmp r13d, [rbx + N_AUX]
        jae 0f
        mov r14, [rbx + N_DATA + r13*8]
        inc r13d
        mov rdi, r14
        call is_list
        test eax, eax
        jnz 12f
        mov rdi, r14
        mov esi, OP_VAR
        mov rdx, r12
        call find_op_list
        jmp 11b
12:     mov qword ptr [rsp], 0          # the lines of the list
13:     mov rcx, [rsp]
        cmp ecx, [r14 + N_AUX]
        jae 11b
        mov rdi, [r14 + N_DATA + rcx*8]
        inc qword ptr [rsp]
        call line_vars
        mov rdi, r12
        mov rsi, rax
        call vec_extend_seq
        jmp 13b
0:      # each variable once (hash-consed: the same pointer - made so
        # first when the context doesn't hash-cons)
        cmp qword ptr [r15 + CTX_DEDUP], DEDUP_EAGER
        je 15f
        mov rdx, [r12 + VEC_DATA]
        mov rcx, [r12 + VEC_LEN]
14:     dec rcx
        js 15f
        mov rdi, [rdx + rcx*8]
        call canon                      # (every register but rax kept)
        mov [rdx + rcx*8], rax
        jmp 14b
15:     mov rcx, [r12 + VEC_LEN]
        cmp rcx, 64
        ja 5f
        mov rdx, [r12 + VEC_DATA]       # few: in place
        xor r8d, r8d                    # the ones kept
        xor r9d, r9d                    # the one looked at
1:      cmp r9, rcx
        jae 4f
        mov rax, [rdx + r9*8]
        xor r10d, r10d
2:      cmp r10, r8
        jae 3f
        cmp rax, [rdx + r10*8]
        je 31f                          # (kept already)
        inc r10
        jmp 2b
3:      mov [rdx + r8*8], rax
        inc r8
31:     inc r9
        jmp 1b
4:      mov [r12 + VEC_LEN], r8
        jmp 8f
5:      # many: in place too, the ones kept in a set (the context's
        # scratch one, emptied: the recursion is over)
        mov r13, [r15 + CTX_LV_SET]
        test r13, r13
        jnz 51f
        call emap_new
        mov r13, rax
        mov [r15 + CTX_LV_SET], rax
51:     mov rdi, r13
        call emap_begin
        xor r14d, r14d                  # the one looked at
        mov qword ptr [rsp], 0          # the ones kept
6:      cmp r14, [r12 + VEC_LEN]
        jae 7f
        mov rax, [r12 + VEC_DATA]
        mov rsi, [rax + r14*8]
        mov [rsp + 8], rsi
        inc r14
        mov rdi, r13
        call emap_add
        test eax, eax
        jz 6b                           # (kept already)
        mov rax, [r12 + VEC_DATA]
        mov rcx, [rsp]
        mov rsi, [rsp + 8]
        mov [rax + rcx*8], rsi
        inc qword ptr [rsp]
        jmp 6b
7:      mov rax, [rsp]
        mov [r12 + VEC_LEN], rax
8:      mov rdi, r12
        call vec_to_list
        mov r12, rax
        mov edi, MEMO_LINE_VARS
        mov rsi, rbx
        mov rdx, rax
        call memo_put
        mov rax, r12
9:      add rsp, 16
        LEAVE
ENDF line_vars

# line_has_var(line, var) -> eax: the variable (a ('var', ...) tuple) is
# somewhere in the line - replace() of it would change the line. From the
# line's variables, remembered (cleanup_vars replaces every variable in
# the rest of the trace: each line is asked once per variable before it)
FUNC line_has_var
        xor eax, eax
        test dil, 1
        jnz 1f
        test rdi, rdi
        jz 1f
        movabs rcx, HF_VAR              # (no "var" in it: none)
        test [rdi + N_HASH], rcx
        jz 1f
        ENTER
        mov rbx, rsi
        call line_vars
        mov ecx, [rax + N_AUX]
        xor edx, edx
2:      cmp edx, ecx
        jae 3f
        VEQ rbx, [rax + N_DATA + rdx*8]
        je 4f
        inc edx
        jmp 2b
3:      xor eax, eax
        LEAVE
4:      mov eax, 1
        LEAVE
1:      ret
ENDF line_has_var

# trace_has_var(trace, var) -> eax: contains(trace, var) - a line of the
# trace holds the variable (its lines' variables, remembered: the lines
# were just asked the same by replace_var)
FUNC trace_has_var
        ENTER
        mov rbx, rdi
        mov r12, rsi
        xor r13d, r13d
1:      cmp r13d, [rbx + N_AUX]
        jae 2f
        mov rdi, [rbx + N_DATA + r13*8]
        mov rsi, r12
        call line_has_var
        inc r13d
        test eax, eax
        jz 1b
        LEAVE
2:      xor eax, eax
        LEAVE
ENDF trace_has_var

# req_has(req, var) -> eax: the variable is required after
FUNC req_has
        ENTER
        mov rbx, rdi
        mov r12, rsi
1:      test rbx, rbx
        jz 2f
        mov rdi, rbx
        call req_map
        mov rdi, rax
        mov rsi, r12
        call map_get
        test rax, rax
        jnz 3f
        mov rbx, [rbx + RQ_PARENT]
        jmp 1b
2:      xor eax, eax
        LEAVE
3:      mov eax, 1
        LEAVE
ENDF req_has

# req_from_list(list) -> req: the tests' required_after, a list of variables
FUNC req_from_list
        ENTER
        mov rbx, rdi
        test rbx, rbx
        jz 1f
        cmp dword ptr [rbx + N_AUX], 0
        je 1f
        xor edi, edi
        mov rsi, rbx
        call req_new                    # (find_op_list finds the variables of the list)
        LEAVE
1:      xor eax, eax
        LEAVE
ENDF req_from_list

# cleanup_vars(trace, required_after) -> list: for every variable, its
# value replaces the uses that follow when possible, and a variable no
# longer used is dropped (simplify.cleanup_vars). required_after: a req
# (see above), 0 for none.
FUNC cleanup_vars
        STACK_CHECK
        ENTER
        sub rsp, 48
        .set CV_REQ, 0
        .set CV_REMAINING, 8
        .set CV_TMP, 16
        .set CV_TMP2, 24
        .set CV_REQ2, 32
        mov rbx, rdi
        mov [rsp + CV_REQ], rsi
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
        call trace_has_var
        test eax, eax
        jnz 3f
        mov rdi, [rsp + CV_REQ]
        mov rsi, [rsp + CV_TMP]
        call req_has
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
        mov rdi, [rsp + CV_REQ]
        mov rsi, rax
        call req_new
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
        # branches merge again (the variables of the rest of the trace:
        # made when a branch goes on, most end with a revert)
        mov qword ptr [rsp + CV_REQ2], 0
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
        mov rsi, rbx
        call vec_to_list_like           # (the trace itself when unchanged)
        add rsp, 48
        LEAVE
.Lcv_branch:
        sub rsp, 24
        mov [rsp], rdi
        call trace_ends_execution
        mov rsi, [rsp + 24 + 8 + CV_REQ]
        test eax, eax
        jnz 7f
        mov rsi, [rsp + 24 + 8 + CV_REQ2]
        test rsi, rsi
        jnz 7f
        mov rdi, rbx                    # required_after + find_op_list(trace[idx + 1:], "var")
        mov rsi, r13
        call list_from
        mov rdi, [rsp + 24 + 8 + CV_REQ]
        mov rsi, rax
        call req_new
        mov [rsp + 24 + 8 + CV_REQ2], rax
        mov rsi, rax
7:      mov rdi, [rsp]
        call cleanup_vars
        add rsp, 24
        ret
ENDF cleanup_vars

# replace_var(trace, var_idx, var_val) -> list: the occurrences of the
# variable replaced, where possible
FUNC replace_var
        STACK_CHECK
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
        # a line without the variable anywhere (its branches, its loop's
        # body included) comes out as it is from every case below: only
        # whether it ends the replacement is left to decide (affects(),
        # false of all but a setmem, a while, an if)
        mov rdi, r14
        mov rsi, [rsp + RV_ID]
        call line_has_var
        test eax, eax
        jnz 0f
        mov rdi, r12
        mov rsi, r14
        call vec_push
        mov rdi, r14
        OPCODE_OF_RDI
        cmp eax, OP_WHILE
        je 91f
        mov rdi, r14
        call is_if_line
        test eax, eax
        jnz 91f
        mov rdi, r14
        mov esi, OP_SETMEM
        mov edx, 3
        call is_op_n
        test eax, eax
        jz .Lrv_line
91:     mov rdi, r14
        mov rsi, [rsp + RV_VAL]
        call affects
        test eax, eax
        jz .Lrv_line
        jmp .Lrv_rest
0:      mov rdi, r14                    # ('setmem', mem_idx, Any)
        mov esi, OP_SETMEM
        mov edx, 3
        call is_op_n
        test eax, eax
        jz 1f
        mov rax, [r14 + N_DATA + 8]
        mov [rsp], rax
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
4:      mov rdi, r14                    # (affects() is false of a line other
        OPCODE_OF_RDI                   # than a setmem, a while or an if)
        cmp eax, OP_WHILE
        jne 5f
        mov rdi, r14
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
        mov rsi, rbx                    # (unchanged: the trace itself)
        call vec_to_list_like
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
        call lines_have_var             # contains(rest, ('var', new_idx))
        test eax, eax
        jz 2f
        add r13, 2                      # (tagged: += 1)
        jmp 1b
2:      mov rdi, rbx
        mov rsi, r12
        mov rdx, r13
        call rename_var                 # replace_f(rest, r)
        mov rdi, rax
        call simplify_exp
        mov rdx, r13
        add rsp, 32
        LEAVE
ENDF replace_while_var

# lines_have_var(lines, var) -> eax: contains(lines, var) for a list of
# lines and a ('var', ...) tuple: from the variables of each line
# (line_vars, remembered - replace_while_var asks it of the rest of the
# trace for every variable of every loop, renaming one at a time)
FUNC lines_have_var
        ENTER
        mov rbx, rdi
        mov r12, rsi
        test bl, 1
        jnz 8f
        test rbx, rbx
        jz 8f
        cmp dword ptr [rbx + N_KIND], K_LIST
        jne 8f                          # (not a list: as python does)
        VEQ rbx, r12
        je 7f
        xor r13d, r13d
1:      cmp r13d, [rbx + N_AUX]
        jae 6f
        mov rdi, [rbx + N_DATA + r13*8]
        inc r13d
        VEQ rdi, r12
        je 7f
        test dil, 1
        jnz 1b                          # (a number: not the tuple)
        test rdi, rdi
        jz 1b
        cmp dword ptr [rdi + N_KIND], K_TUPLE
        jne 2f
        mov rsi, r12
        call line_has_var
        test eax, eax
        jnz 7f
        jmp 1b
2:      mov rsi, r12                    # (a list, a string...: walked)
        call contains
        test eax, eax
        jnz 7f
        jmp 1b
6:      xor eax, eax
        LEAVE
7:      mov eax, 1
        LEAVE
8:      mov rdi, rbx
        mov rsi, r12
        call contains
        LEAVE
ENDF lines_have_var

# line_has_setvar(line, idx) -> eax: a ('setvar', idx, v) somewhere in
# the line (python's `match(exp, ('setvar', idx, ':val'))` in
# replace_while_var's r), from the line's setvars' indices, remembered
FUNC line_has_setvar
        xor eax, eax
        test dil, 1
        jnz 3f
        test rdi, rdi
        jz 3f
        movabs rcx, HF_SETVAR           # (no "setvar" in it: none)
        test [rdi + N_HASH], rcx
        jz 3f
        ENTER
        mov rbx, rsi
        mov r12, rdi
        mov edi, MEMO_LINE_SETVARS
        mov rsi, r12
        call memo_get
        test rax, rax
        jnz 1f
        call vec_new
        mov r13, rax
        mov rdi, r12
        mov rsi, r13
        call setvar_idxs
        mov edi, K_TUPLE
        mov rsi, [r13 + VEC_LEN]
        mov rdx, [r13 + VEC_DATA]
        call mk_seq
        mov r14, rax
        mov edi, MEMO_LINE_SETVARS
        mov rsi, r12
        mov rdx, rax
        call memo_put
        mov rax, r14
1:      mov ecx, [rax + N_AUX]
        xor edx, edx
2:      cmp edx, ecx
        jae 6f
        mov rdi, [rax + N_DATA + rdx*8]
        VEQ rdi, rbx
        je 7f
        test dil, 1                     # (python's ==: big ints by value)
        jnz 8f
        test rdi, rdi
        jz 8f
        cmp dword ptr [rdi + N_KIND], K_INT
        jne 8f
        push rax
        push rcx
        push rdx
        push rdx
        mov rsi, rbx
        call values_equal
        mov esi, eax
        pop rdx
        pop rdx
        pop rcx
        pop rax
        test esi, esi
        jnz 7f
8:      inc edx
        jmp 2b
6:      xor eax, eax
        LEAVE
7:      mov eax, 1
        LEAVE
3:      ret
ENDF line_has_setvar

# setvar_idxs(exp, vec): the indices of the ('setvar', idx, v) in exp,
# at any depth (into them too), appended to vec
FUNC setvar_idxs
        STACK_CHECK
        test dil, 1
        jnz 9f
        test rdi, rdi
        jz 9f
        mov eax, [rdi + N_KIND]
        sub eax, K_TUPLE
        cmp eax, K_LIST - K_TUPLE
        ja 9f
        movabs rax, HF_SETVAR
        test [rdi + N_HASH], rax
        jz 9f                           # no 'setvar' in there
        ENTER
        mov rbx, rdi
        mov r12, rsi
        cmp dword ptr [rbx + N_KIND], K_TUPLE
        jne 2f
        cmp dword ptr [rbx + N_AUX], 3
        jne 2f
        OPCODE_OF_RDI
        cmp eax, OP_SETVAR
        jne 2f
        mov rdi, r12
        mov rsi, [rbx + N_DATA + 8]
        call vec_push
2:      xor r13d, r13d
3:      cmp r13d, [rbx + N_AUX]
        jae 4f
        mov rdi, [rbx + N_DATA + r13*8]
        inc r13d
        mov rsi, r12
        call setvar_idxs
        jmp 3b
4:      LEAVE
9:      ret
ENDF setvar_idxs

# rename_var(exp, old, new) -> python's replace_f(exp, r) of
# replace_while_var: ('var', old) becomes ('var', new), ('setvar', old,
# v) ('setvar', new, v). The subtrees without a variable or a setvar
# (the mention flags HF_VAR, HF_SETVAR) are kept as they are, and each
# subtree is done once (the trace is a DAG): the same result as the
# walk of every node, bottom-up, python makes
        .set RV_OLD, 0
        .set RV_NEW, 8
        .set RV_VAR_OLD, 16
        .set RV_VAR_NEW, 24
        .set RV_MAP, 32
        .set RV_SIZEOF, 48
FUNC rename_var
        ENTER
        sub rsp, RV_SIZEOF
        mov rbx, rdi
        mov [rsp + RV_OLD], rsi
        mov [rsp + RV_NEW], rdx
        LOADS rdi, VAR
        mov rsi, [rsp + RV_OLD]
        call mk2
        mov [rsp + RV_VAR_OLD], rax
        LOADS rdi, VAR
        mov rsi, [rsp + RV_NEW]
        call mk2
        mov [rsp + RV_VAR_NEW], rax
        mov rax, [r15 + CTX_RV_MAP]     # the context's, emptied (an epoch)
        test rax, rax
        jnz 1f
        call emap_new
        mov [r15 + CTX_RV_MAP], rax
1:      mov [rsp + RV_MAP], rax
        mov rdi, rax
        call emap_begin
        test bl, 1
        jnz 2f
        test rbx, rbx
        jz 2f
        cmp dword ptr [rbx + N_KIND], K_LIST
        je 3f
2:      mov rdi, rbx
        mov rsi, rsp
        call rv_walk
        add rsp, RV_SIZEOF
        LEAVE
3:      # a list of lines: a line without the variable nor a setvar of it
        # (line_vars, line_setvars: remembered) is kept as it is, unwalked
        mov edi, [rbx + N_AUX]
        shl rdi, 3
        call arena_alloc_raw
        mov r13, rax                    # the lines, renamed
        xor r14d, r14d
4:      cmp r14d, [rbx + N_AUX]
        jae 6f
        mov r12, [rbx + N_DATA + r14*8]
        test r12b, 1
        jnz 5f
        test r12, r12
        jz 5f
        cmp dword ptr [r12 + N_KIND], K_TUPLE
        jne 5f
        VEQ r12, [rsp + RV_VAR_OLD]
        je 5f
        mov rdi, r12
        mov rsi, [rsp + RV_VAR_OLD]
        call line_has_var
        test eax, eax
        jnz 5f
        mov rdi, r12
        mov rsi, [rsp + RV_OLD]
        call line_has_setvar
        test eax, eax
        jnz 5f
        mov rax, r12                    # kept
        jmp 7f
5:      mov rdi, r12
        mov rsi, rsp
        call rv_walk
7:      mov [r13 + r14*8], rax
        inc r14d
        jmp 4b
6:      mov rdi, rbx
        mov rsi, r13
        call mk_seq_like
        add rsp, RV_SIZEOF
        LEAVE
ENDF rename_var

# rv_walk(exp, block) -> exp renamed (block: rename_var's)
FUNC rv_walk
        STACK_CHECK
        VEQ rdi, [rsi + RV_VAR_OLD]
        je 7f
        mov rax, rdi
        test dil, 1
        jnz 9f
        test rdi, rdi
        jz 9f
        mov ecx, [rdi + N_KIND]
        cmp ecx, K_TUPLE
        je 1f
        cmp ecx, K_LIST
        jne 9f
1:      mov rcx, HF_VAR | HF_SETVAR
        test [rdi + N_HASH], rcx
        jz 9f                           # no variable in there
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov rdi, [r12 + RV_MAP]
        mov rsi, rbx
        call emap_get
        test rax, rax
        jnz 8f                          # done already
        mov edi, [rbx + N_AUX]
        shl rdi, 3
        call arena_alloc_raw
        mov r13, rax                    # the elements, renamed
        xor r14d, r14d
2:      cmp r14d, [rbx + N_AUX]
        jae 3f
        mov rdi, [rbx + N_DATA + r14*8]
        mov rsi, r12
        call rv_walk
        mov [r13 + r14*8], rax
        inc r14d
        jmp 2b
3:      mov rdi, rbx
        mov rsi, r13
        call mk_seq_like
        # ('setvar', old, v): ('setvar', new, v)
        cmp dword ptr [rax + N_KIND], K_TUPLE
        jne 5f
        cmp dword ptr [rax + N_AUX], 3
        jne 5f
        mov rcx, [rax + N_DATA + 8]
        VEQ rcx, [r12 + RV_OLD]
        jne 5f
        mov rdi, rax
        mov [rsp], rax
        call opcode_of
        cmp eax, OP_SETVAR
        mov rax, [rsp]
        jne 5f
        mov rdx, [rax + N_DATA + 16]
        mov rsi, [r12 + RV_NEW]
        LOADS rdi, SETVAR
        call mk3
5:      mov [rsp], rax
        mov rdi, [r12 + RV_MAP]
        mov rsi, rbx
        mov rdx, rax
        call emap_put
        mov rax, [rsp]
8:      add rsp, 16
        LEAVE
7:      mov rax, [rsi + RV_VAR_NEW]
9:      ret
ENDF rv_walk

# readability(trace) -> list: nicer variable names, and the msize
# expressions in setmems named
FUNC readability
        STACK_CHECK
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
        call replace_f_memo
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
        VEQ rsi, [rsp + RD_COUNTER]
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
        call replace_f_stop_memo
        LEAVE
ENDF replace_bytes_or_string_length

FUNC string_length_cb
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 16
        mov rbx, rdi
        # (for speed: both patterns are a mask_shl by -1 of an and)
        mov esi, OP_MASK_SHL
        mov edx, 5
        call is_op_n
        test eax, eax
        jz .Lsl_none
        cmp qword ptr [rbx + N_DATA + 24], -1   # -1, tagged
        jne .Lsl_none
        mov rdi, rbx
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
