# The symbolic EVM (port of vm.py): executes the contract symbolically and
# returns the resulting trace of execution, which is the decompiled form.
#
# The loop detection and the branch merging follow the python version, see
# the comments there. Traces are vecs of lines (tuples) while the nodes
# are being expanded, and become lists in node_make_trace.

.include "defs.inc"

        .section .rodata
.Ls_logname:        .asciz "panoramix.vm"
.Ls_stopped:        .asciz "VM stopped prematurely. Node count %d, after %d ms."
.Ls_runtime_param:  .asciz "jump to a parameter computed at runtime"
.Ls_jumdest:        .asciz "jumdest"
.Ls_jumpdest:       .asciz "jumpdest"
.Ls_jump:           .asciz "jump"
.Ls_eof:            .asciz "eof?"
.Ls_safe:           .asciz "safe"
.Ls_storage:        .asciz "storage"
.Ls_var_fmt:        .asciz "_%lu"
.Ls_result_fmt:     .asciz "%s.result"
.Ls_erecover:       .asciz "erecover"
.Ls_sha256hash:     .asciz "sha256hash"
.Ls_ripemd160hash:  .asciz "ripemd160hash"
.Ls_bigModExp:      .asciz "bigModExp"
.Ls_bn256Add:       .asciz "bn256Add"
.Ls_bn256ScalarMul: .asciz "bn256ScalarMul"
.Ls_bn256Pairing:   .asciz "bn256Pairing"
.Ls_signer:         .asciz "signer"
.Ls_hash:           .asciz "hash"
.Ls_mod_exp:        .asciz "mod_exp"
.Ls_bn_add:         .asciz "bn_add"
.Ls_bn_scalar_mul:  .asciz "bn_scalar_mul"
.Ls_bn_pairing:     .asciz "bn_pairing"

        .section .data.rel.ro
        .align 8
# the precompiled contracts 1..8 (4, the identity, is handled apart):
# name, variable name
precompiled_names:
        .quad 0, 0
        .quad .Ls_erecover, .Ls_signer
        .quad .Ls_sha256hash, .Ls_hash
        .quad .Ls_ripemd160hash, .Ls_hash
        .quad 0, 0
        .quad .Ls_bigModExp, .Ls_mod_exp
        .quad .Ls_bn256Add, .Ls_bn_add
        .quad .Ls_bn256ScalarMul, .Ls_bn_scalar_mul
        .quad .Ls_bn256Pairing, .Ls_bn_pairing

        .section .bss
        .align 8
        .globl evm_op_nodes
        .hidden evm_op_nodes
evm_op_nodes:   .skip 256*8     # opcode byte -> interned mnemonic (0: unknown)

        .text

# vm_module_init(): the mnemonics as string nodes
FUNC vm_module_init
        ENTER
        xor ebx, ebx
1:      cmp ebx, 256
        jae 2f
        lea rax, [rip + evm_opnames]
        mov rdi, [rax + rbx*8]
        test rdi, rdi
        jz 3f
        call str_intern_c
        lea rcx, [rip + evm_op_nodes]
        mov [rcx + rbx*8], rax
3:      inc ebx
        jmp 1b
2:      LEAVE
ENDF vm_module_init

# vm_new(loader, just_fdests) -> rax: a VM for this thread, bound to the
# context (CTX_VM)
FUNC vm_new
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov edi, VM_SIZEOF
        call arena_alloc
        mov [rax + VM_LOADER], rbx
        mov [rax + VM_JUST_FDESTS], r12
        mov qword ptr [rax + VM_COUNTER], 0
        mov qword ptr [rax + VM_NODE_COUNT], 0
        mov qword ptr [rax + VM_TIMEOUT], 0
        mov qword ptr [rax + VM_GEN], 1 # (a new node's stamp, 0, is never the current one)
        mov [r15 + CTX_VM], rax
        mov rbx, rax
        lea rdi, [rip + .Ls_env_check_lca]
        call getenv@PLT
        xor ecx, ecx
        test rax, rax
        setnz cl
        mov [rbx + VM_CHECK_LCA], rcx
        mov rax, rbx
        LEAVE
ENDF vm_new

        .section .rodata
.Ls_env_check_lca: .asciz "PANORAMIX_CHECK_LCA"
.Ls_lca_mismatch: .asciz "vm_common_ancestor: the jump pointers and python's walk disagree"
        .text

# monotonic_ns() -> rax
FUNC monotonic_ns
        ENTER
        sub rsp, 16
        mov edi, 1                      # CLOCK_MONOTONIC
        mov rsi, rsp
        call clock_gettime@PLT
        imul rax, qword ptr [rsp], 1000000000
        add rax, [rsp + 8]
        add rsp, 16
        LEAVE
ENDF monotonic_ns

# vm_should_quit() -> eax: too many nodes, or out of time
FUNC vm_should_quit
        ENTER
        mov rbx, [r15 + CTX_VM]
        cmp qword ptr [rbx + VM_NODE_COUNT], MAX_NODE_COUNT
        ja 1f
        cmp qword ptr [rbx + VM_TIMEOUT], 0
        je 2f
        call monotonic_ns
        sub rax, [rbx + VM_TIME_START]
        cmp rax, [rbx + VM_TIMEOUT]
        jg 1f
2:      xor eax, eax
        LEAVE
1:      mov eax, 1
        LEAVE
ENDF vm_should_quit

# vm_run(start, stack, known, timeout_ns) -> rax: the decompiled trace (a
# list) of the function starting at `start` with `stack` (a tuple), given
# the conditions `known` to hold there.
FUNC vm_run
        ENTER
        sub rsp, 48
        mov rbx, [r15 + CTX_VM]
        mov [rsp], rdi                  # start
        mov [rsp + 8], rsi              # stack
        mov [rsp + 16], rdx             # known
        mov [rbx + VM_TIMEOUT], rcx
        call monotonic_ns
        mov [rbx + VM_TIME_START], rax
        mov qword ptr [rbx + VM_NODE_COUNT], 0
        # func_node = Node(start, safe=True, stack, known)
        mov rdi, [rsp]
        mov esi, 1
        mov rdx, [rsp + 8]
        lea rcx, [rip + sp_true]
        mov r8, [rsp + 16]
        call node_new
        mov r12, rax
        # trace = [('setmem', ('range', 0x40, 32), 0x60), ('jump', func_node, 'safe', ())]
        call vec_new
        mov r13, rax
        LOADS rdi, RANGE
        mov esi, (0x40 << 1) | 1
        mov edx, (32 << 1) | 1
        call mk3
        mov rsi, rax
        LOADS rdi, SETMEM
        mov edx, (0x60 << 1) | 1
        call mk3
        mov rdi, r13
        mov rsi, rax
        call vec_push
        xor edi, edi
        xor esi, esi
        call mk_tuple
        mov rcx, rax
        lea rdi, [rip + .Ls_safe]
        mov [rsp + 24], rcx
        call str_intern_c
        mov rdx, rax
        mov rcx, [rsp + 24]
        LOADS rdi, JUMP
        mov rsi, r12
        call mk4
        mov rdi, r13
        mov rsi, rax
        call vec_push
        # root = Node(trace, start, safe=True, stack, known)
        mov rdi, [rsp]
        mov esi, 1
        mov rdx, [rsp + 8]
        lea rcx, [rip + sp_true]
        mov r8, [rsp + 16]
        call node_new
        mov r14, rax
        mov [r14 + ND_TRACE], r13
        mov rdi, r12
        mov rsi, r14
        call node_set_prev
        # BFS symbolic execution, ends up with a decompiled code, with
        # labels and gotos. (Depth-first would be way easier, but it tends
        # to work way slower because of the loops.)
        mov qword ptr [rsp + 24], 0     # j
        mov qword ptr [rsp + 40], 0     # the unexpanded nodes, when just found
.Louter:
        mov qword ptr [rsp + 32], 0     # i
.Linner:
        # find all the jumps, and expand them until the next jump (the
        # unexpanded nodes the loop's condition just found: nothing
        # changed since)
        mov rdi, r14
        mov rsi, [rsp + 40]
        call vm_expand_trace
        mov qword ptr [rsp + 40], 0
        # find all the jumps that lead to an already reached jumpdest
        # (with a similar stack, otherwise we'd catch function calls as
        # all), replace them with 'loop' identifiers (the unexpanded
        # nodes: the ones expand_trace just made, see there)
        mov rdi, r14
        mov rsi, rax
        call vm_replace_loops
        # turn them into loops right away: the later this is done, the
        # bigger the subtree that gets thrown away and explored again
        mov rdi, r14
        call vm_continue_loops
        # find the ifs whose branches all end up at the same jumpdest, and
        # continue from there only once
        mov rax, [r15 + CTX_VM]
        mov qword ptr [rax + VM_UNEXP_VALID], 0
        mov rdi, r14
        call vm_merge_branches
        # repeat until there are no more jumps to explore: the nodes not
        # run yet, merge_branches' when it merged none (its walk found them)
        mov rdi, r14
        call vm_unexpanded_after_merges
        mov [rsp + 40], rax
        cmp qword ptr [rax + VEC_LEN], 0
        je .Linner_done
        call vm_should_quit
        test eax, eax
        jnz .Linner_done
        inc qword ptr [rsp + 32]
        cmp qword ptr [rsp + 32], 200
        jb .Linner
.Linner_done:
        mov rdi, r14
        call vm_continue_loops
        mov rdi, r14
        lea rsi, [rip + pred_unexpanded]
        xor edx, edx
        call find_nodes
        mov [rsp + 40], rax
        cmp qword ptr [rax + VEC_LEN], 0
        je .Lrun_done
        call vm_should_quit
        test eax, eax
        jnz .Lrun_done
        inc qword ptr [rsp + 24]
        cmp qword ptr [rsp + 24], 20
        jb .Louter
.Lrun_done:
        call vm_should_quit
        test eax, eax
        jz 1f
        call monotonic_ns
        sub rax, [rbx + VM_TIME_START]
        xor edx, edx
        mov ecx, 1000000
        div rcx
        mov r8, rax
        mov rcx, [rbx + VM_NODE_COUNT]
        mov edi, LOG_WARNING
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_stopped]
        call log_fmt
1:      mov rdi, r14
        call node_make_trace
        add rsp, 48
        LEAVE
ENDF vm_run

# vm_unexpanded_after_merges(root) -> rax: python's find_nodes(root, the
# nodes not run yet), after merge_branches: the ones its walk found, when
# it merged none (VM_UNEXP_VALID), else a walk (PANORAMIX_CHECK_LCA=1:
# both, compared)
FUNC vm_unexpanded_after_merges
        ENTER
        mov r12, rdi
        mov rbx, [r15 + CTX_VM]
        cmp qword ptr [rbx + VM_UNEXP_VALID], 0
        je 5f
        call vec_new                    # (a copy: the scratch is the next
        mov r13, rax                    # round's)
        mov rsi, [rbx + VM_SCR_UNEXP]
        mov rdx, [rsi + VEC_LEN]
        mov rsi, [rsi + VEC_DATA]
        mov rdi, r13
        call vec_extend
        cmp qword ptr [rbx + VM_CHECK_LCA], 0
        je 4f
        mov rdi, r12
        lea rsi, [rip + pred_unexpanded]
        xor edx, edx
        call find_nodes
        mov rcx, [rax + VEC_LEN]
        cmp rcx, [r13 + VEC_LEN]
        jne 7f
        mov rsi, [rax + VEC_DATA]
        mov rdi, [r13 + VEC_DATA]
6:      dec rcx
        js 4f
        mov rdx, [rsi + rcx*8]
        cmp rdx, [rdi + rcx*8]
        jne 7f
        jmp 6b
4:      mov rax, r13
        LEAVE
5:      mov rdi, r12
        lea rsi, [rip + pred_unexpanded]
        xor edx, edx
        call find_nodes
        LEAVE
7:      lea rdi, [rip + .Ls_unexp_mb_mismatch]
        call rt_fatal
ENDF vm_unexpanded_after_merges
        .section .rodata
.Ls_unexp_mb_mismatch: .asciz "vm_run: merge_branches' unexpanded nodes and python's walk disagree"
        .text

# vm_expand_trace(root, nodes) -> rax: run the nodes that haven't been
# yet - nodes: them, as find_nodes just gave them, or 0 to find them.
# Gives the unexpanded nodes after (what replace_loops' find_nodes would
# give): the unexpanded ones are leaves, found in the order of the
# leaves, and running one only gives it children, new (unexpanded, but
# for just_fdests' funccalls) - they take its place in that order, in the
# order of its next.
FUNC vm_expand_trace
        ENTER
        sub rsp, 16
        mov r13, rdi
        mov rbx, rsi
        test rbx, rbx
        jnz 3f
        lea rsi, [rip + pred_unexpanded]
        xor edx, edx
        call find_nodes
        mov rbx, rax
3:      call vec_new
        mov r14, rax                    # the unexpanded ones after
        xor r12d, r12d
1:      cmp r12, [rbx + VEC_LEN]
        jae 2f
        # symbolic execution of a single node can take very long when the
        # expressions get big, so the timeout is checked here too
        call vm_should_quit
        test eax, eax
        jnz 4f
        mov rax, [rbx + VEC_DATA]
        mov rdi, [rax + r12*8]
        mov [rsp], rdi
        call node_run
        mov rax, [rsp]                  # its children not run (with a
        mov rax, [rax + ND_NEXT]        # trace from the start: just_fdests'
        mov [rsp + 8], rax              # funccalls)
        xor ecx, ecx
8:      mov rax, [rsp + 8]
        cmp rcx, [rax + VEC_LEN]
        jae 9f
        mov rax, [rax + VEC_DATA]
        mov rsi, [rax + rcx*8]
        inc rcx
        cmp qword ptr [rsi + ND_TRACE], 0
        jne 8b
        mov [rsp], rcx
        mov rdi, r14
        call vec_push
        mov rcx, [rsp]
        jmp 8b
9:      inc r12
        jmp 1b
4:      mov rax, [rbx + VEC_DATA]       # the ones not run, as they are
        lea rsi, [rax + r12*8]
        mov rdx, [rbx + VEC_LEN]
        sub rdx, r12
        mov rdi, r14
        call vec_extend
2:      mov rax, [r15 + CTX_VM]
        cmp qword ptr [rax + VM_CHECK_LCA], 0
        je 5f
        # PANORAMIX_CHECK_LCA=1: python's walk, compared
        mov rdi, r13
        lea rsi, [rip + pred_unexpanded]
        xor edx, edx
        call find_nodes
        mov rcx, [rax + VEC_LEN]
        cmp rcx, [r14 + VEC_LEN]
        jne 7f
        mov rsi, [rax + VEC_DATA]
        mov rdi, [r14 + VEC_DATA]
6:      dec rcx
        js 5f
        mov rdx, [rsi + rcx*8]
        cmp rdx, [rdi + rcx*8]
        jne 7f
        jmp 6b
5:      mov rax, r14
        add rsp, 16
        LEAVE
7:      mov rcx, [rax + VEC_LEN]
        mov r8, [r14 + VEC_LEN]
        mov edi, LOG_ERROR
        lea rsi, [rip + .Ls_unexp_dbgn]
        lea rdx, [rip + .Ls_unexp_dbgf]
        call log_fmt
        lea rdi, [rip + .Ls_unexp_mismatch]
        call rt_fatal
ENDF vm_expand_trace
        .section .rodata
.Ls_unexp_dbgn: .asciz "unexpdbg"
.Ls_unexp_dbgf: .asciz "walk %u derived %u"
        .text

        .section .rodata
.Ls_unexp_mismatch: .asciz "vm_expand_trace: the unexpanded nodes after the runs and python's walk disagree"
        .text

# vm_replace_loops(root, nodes): an unexpanded node at a point of
# execution already seen on its path (same jumpdest, same stack layout)
# is a loop - nodes: the unexpanded nodes (vm_expand_trace's), or 0 to
# find them
FUNC vm_replace_loops
        ENTER
        sub rsp, 16
        mov rbx, rsi
        test rbx, rbx
        jnz 5f
        lea rsi, [rip + pred_unexpanded]
        xor edx, edx
        call find_nodes
        mov rbx, rax
5:
        xor r12d, r12d
1:      cmp r12, [rbx + VEC_LEN]
        jae 4f
        mov rax, [rbx + VEC_DATA]
        mov r13, [rax + r12*8]          # node
        mov rdi, r13
        call node_history
        test rax, rax
        jz 3f
        mov r14, rax                    # the earlier node
        mov rax, [r13 + ND_JD]
        cmp qword ptr [rax + N_DATA + 8], 1     # jd[1] > 0: a non-empty stack
        je 3f
        mov rax, [r14 + ND_STACK]
        mov ecx, [rax + N_AUX]
        mov rax, [r13 + ND_STACK]
        cmp ecx, [rax + N_AUX]
        jne 3f
        # ('loop', earlier, stack, folded, vars)
        mov rdi, [r14 + ND_STACK]
        mov rsi, [r13 + ND_STACK]
        mov rdx, [r13 + ND_DEPTH]
        lea rcx, [rsp]
        call fold_stacks
        mov r8, [rsp]
        mov rcx, rax
        mov rdx, [r13 + ND_STACK]
        mov rsi, r14
        LOADS rdi, LOOP
        call mk5
        mov r14, rax
        call vec_new
        mov [r13 + ND_TRACE], rax
        mov rdi, rax
        mov rsi, r14
        call vec_push
        mov rdi, r13
        call node_touch
        # (for continue_loops, in this order: find_nodes' - the loops are
        # these, as no other node's trace is ever a loop)
        mov rax, [r15 + CTX_VM]
        mov rdi, [rax + VM_LOOPS]
        test rdi, rdi
        jnz 2f
        call vec_new
        mov rdi, rax
        mov rax, [r15 + CTX_VM]
        mov [rax + VM_LOOPS], rdi
2:      mov rsi, r13
        call vec_push
3:      inc r12
        jmp 1b
4:      add rsp, 16
        LEAVE
ENDF vm_replace_loops

# vm_continue_loops(root): set up the loops found by vm_replace_loops -
# python's find_nodes(root, a trace of one 'loop'): the nodes
# vm_replace_loops made so since (VM_LOOPS, in the same order), emptied
FUNC vm_continue_loops
        ENTER
        sub rsp, 48
        mov rax, [r15 + CTX_VM]
        mov rbx, [rax + VM_LOOPS]
        test rbx, rbx
        jz .Lcl_done
        xor r12d, r12d
.Lcl_next:
        cmp r12, [rbx + VEC_LEN]
        jae .Lcl_done
        mov rax, [rbx + VEC_DATA]
        mov r13, [rax + r12*8]          # node
        inc r12
        mov rax, [r13 + ND_TRACE]
        mov rax, [rax + VEC_DATA]
        mov r14, [rax]                  # ('loop', loop_dest, stack, new_stack, vars)
        mov rax, [r14 + N_DATA + 8]
        mov [rsp], rax                  # loop_dest
        cmp qword ptr [rax + ND_LABEL], 0
        je .Lcl_new_loop
        # loop_dest is already the body of a loop: this is another way
        # back to its head. set_vars = [('setvar', var_idx, stack[stack_pos])
        # for (_, var_idx, val, stack_pos) in loop_dest.label.begin_vars]
        call vec_new
        mov [rsp + 8], rax              # set_vars
        mov rax, [rsp]
        mov rax, [rax + ND_LABEL]
        mov rax, [rax + ND_BEGIN_VARS]
        mov [rsp + 16], rax             # beginvars
        mov qword ptr [rsp + 24], 0     # index
1:      mov rcx, [rsp + 24]
        mov rax, [rsp + 16]
        cmp ecx, [rax + N_AUX]
        jae 2f
        mov rax, [rax + N_DATA + rcx*8] # ('var', var_idx, val, stack_pos)
        mov rsi, [rax + N_DATA + 8]
        mov rdx, [rax + N_DATA + 24]
        sar rdx, 1
        mov rcx, [r14 + N_DATA + 16]    # stack
        mov rdx, [rcx + N_DATA + rdx*8]
        LOADS rdi, SETVAR
        call mk3
        mov rdi, [rsp + 8]
        mov rsi, rax
        call vec_push
        inc qword ptr [rsp + 24]
        jmp 1b
2:      mov rax, [rsp + 8]
        cmp qword ptr [rax + VEC_LEN], 0
        jne 3f
        # no variables: fold the stacks again from the loop's own
        mov rdi, [rsp]
        mov rdi, [rdi + ND_STACK]
        mov rsi, [r14 + N_DATA + 16]
        mov rax, [rsp]
        mov rax, [rax + ND_LABEL]
        mov rdx, [rax + ND_DEPTH]
        lea rcx, [rsp + 32]
        call fold_stacks
        mov qword ptr [r13 + ND_TRACE], 0
        mov rdi, r13
        mov rsi, [rsp]
        mov rdx, [rsp + 32]
        mov rcx, rax
        call node_set_label
        jmp .Lcl_next
3:      # node.trace = [('goto', loop_dest, set_vars)]
        mov rdi, [rsp + 8]
        call vec_to_tuple
        mov rdx, rax
        mov rsi, [rsp]
        LOADS rdi, GOTO
        call mk3
        mov [rsp + 8], rax
        call vec_new
        mov [r13 + ND_TRACE], rax
        mov rdi, rax
        mov rsi, [rsp + 8]
        call vec_push
        mov rdi, r13
        call node_touch
        jmp .Lcl_next
.Lcl_new_loop:
        # node.trace = None; node.set_label(loop_dest, vars, new_stack)
        mov qword ptr [r13 + ND_TRACE], 0
        mov rdi, r13
        mov rsi, [rsp]
        mov rdx, [r14 + N_DATA + 32]
        mov rcx, [r14 + N_DATA + 24]
        call node_set_label
        jmp .Lcl_next
.Lcl_done:
        test rbx, rbx
        jz 1f
        mov qword ptr [rbx + VEC_LEN], 0
1:      add rsp, 48
        LEAVE
ENDF vm_continue_loops

# vm_common_ancestor(a, b) -> rax: the closest common ancestor (python's
# walk; by the jump pointers while the depths are consistent - both,
# compared, with PANORAMIX_CHECK_LCA set: the fuzzers' check)
FUNC vm_common_ancestor
        mov rax, [r15 + CTX_VM]
        cmp qword ptr [rax + VM_STALE_DEPTHS], 0
        jne vm_common_ancestor_walk
        cmp qword ptr [rax + VM_CHECK_LCA], 0
        je vm_common_ancestor_jumps
        push rbx
        push rdi
        push rsi
        call vm_common_ancestor_jumps
        mov rbx, rax
        mov rsi, [rsp]
        mov rdi, [rsp + 8]
        call vm_common_ancestor_walk
        cmp rax, rbx
        jne 1f
        pop rsi
        pop rdi
        pop rbx
        ret
1:      lea rdi, [rip + .Ls_lca_mismatch]
        call rt_fatal
ENDF vm_common_ancestor

# vm_common_ancestor_walk(a, b) -> rax: python's walk up, a step at a time
FUNC vm_common_ancestor_walk
        mov rax, rdi
        mov rcx, rsi
1:      test rax, rax
        jz 4f
        mov rdx, [rax + ND_DEPTH]
        cmp rdx, [rcx + ND_DEPTH]
        jle 2f
        mov rax, [rax + ND_PREV]
        jmp 1b
2:      test rcx, rcx
        jz 4f
        mov rdx, [rcx + ND_DEPTH]
        cmp rdx, [rax + ND_DEPTH]
        jle 3f
        mov rcx, [rcx + ND_PREV]
        jmp 2b
3:      test rax, rax
        jz 4f
        cmp rax, rcx
        je 4f
        mov rax, [rax + ND_PREV]
        mov rcx, [rcx + ND_PREV]
        jmp 3b
4:      ret
ENDF vm_common_ancestor_walk

# vm_common_ancestor_jumps(a, b) -> rax: python's walk up (the deeper one
# to the other's depth, then both until they meet), with the jump
# pointers (node_set_prev): the depths are consistent (a node is hung
# elsewhere only as a leaf - a loop's body, a merge's node) and the jumps
# of two nodes of the same depth go to the same depth, so both jump
# when their jumps differ (the meeting is above) and step up otherwise -
# a logarithmic number of steps where the walk took the depth (38% of
# safe_MockContract's instructions)
FUNC vm_common_ancestor_jumps
        mov rax, rdi
        mov rcx, rsi
        mov rdx, [rcx + ND_DEPTH]       # a up to b's depth
1:      cmp [rax + ND_DEPTH], rdx
        jle 3f
        mov r8, [rax + ND_JUMP]
        cmp [r8 + ND_DEPTH], rdx
        jl 2f
        mov rax, r8
        jmp 1b
2:      mov rax, [rax + ND_PREV]
        jmp 1b
3:      mov rdx, [rax + ND_DEPTH]       # b up to a's
4:      cmp [rcx + ND_DEPTH], rdx
        jle 6f
        mov r8, [rcx + ND_JUMP]
        cmp [r8 + ND_DEPTH], rdx
        jl 5f
        mov rcx, r8
        jmp 4b
5:      mov rcx, [rcx + ND_PREV]
        jmp 4b
6:      cmp rax, rcx                    # both up until they meet
        je 8f
        mov r8, [rax + ND_JUMP]
        mov r9, [rcx + ND_JUMP]
        cmp r8, r9
        je 7f
        mov rax, r8
        mov rcx, r9
        jmp 6b
7:      mov rax, [rax + ND_PREV]
        mov rcx, [rcx + ND_PREV]
        jmp 6b
8:      ret
ENDF vm_common_ancestor_jumps

# vm_ends_execution(start) -> eax: the basic block starting at `start` (a
# value) can only end the execution
FUNC vm_ends_execution
        ENTER
        test dil, 1
        jz .Lee_no
        mov rbx, [r15 + CTX_VM]
        mov rbx, [rbx + VM_LOADER]
        mov r12, rdi
        sar r12, 1
1:      mov rdi, rbx
        mov rsi, r12
        call loader_instr_at
        test rax, rax
        jz .Lee_no
        movzx eax, byte ptr [rax + IN_OP]
        cmp al, 0xfd                    # revert
        je .Lee_yes
        cmp al, 0xf3                    # return
        je .Lee_yes
        cmp al, 0x00                    # stop
        je .Lee_yes
        cmp al, 0xfe                    # invalid
        je .Lee_yes
        cmp al, 0xff                    # selfdestruct
        je .Lee_yes
        cmp al, 0x56                    # jump
        je .Lee_no
        cmp al, 0x57                    # jumpi
        je .Lee_no
        mov rdi, rbx
        mov rsi, r12
        call loader_next_line
        mov r12, rax
        jmp 1b
.Lee_yes:
        mov eax, 1
        LEAVE
.Lee_no:
        xor eax, eax
        LEAVE
ENDF vm_ends_execution

# is_if_node(p) -> eax: p has a trace ending with an if
FUNC is_if_node
        mov rax, [rdi + ND_TRACE]
        test rax, rax
        jz 1f
        mov rcx, [rax + VEC_LEN]
        test rcx, rcx
        jz 1f
        mov rax, [rax + VEC_DATA]
        mov rdi, [rax + rcx*8 - 8]
        ENTER
        call opcode_of
        cmp eax, OP_IF
        sete al
        movzx eax, al
        LEAVE
1:      xor eax, eax
        ret
ENDF is_if_node

# vm_merge_branches(root): when every path going out of an `if` either
# ends the execution or reaches the same jumpdest with the same stack
# layout, decompile what follows that jumpdest once, as the continuation
# of the `if` (see merge_branches in vm.py)
FUNC vm_merge_branches
        ENTER
        sub rsp, 48
        mov rax, [r15 + CTX_VM]
        cmp qword ptr [rax + VM_JUST_FDESTS], 0
        jne .Lmb_done
        mov rbx, rdi                    # root
        # every node, in find_nodes' order (one walk: the unexpanded ones
        # are those of them whose trace is None, in the same order)
        mov rdi, rbx
        call mb_all_nodes
        mov r12, rax                    # unexpanded
        mov rax, [r15 + CTX_VM]         # (the rounds' next list, unless a
        mov qword ptr [rax + VM_UNEXP_VALID], 1         # merge changes it)
        cmp qword ptr [r12 + VEC_LEN], 0
        je .Lmb_done
        # by_jd: the nodes by jd, in find_nodes' order
        call mb_by_jd
        call map_new
        mov r14, rax                    # tried: (p, jd) pairs
        mov qword ptr [rsp], 0          # index into unexpanded
.Lmb_next:
        mov rcx, [rsp]
        cmp rcx, [r12 + VEC_LEN]
        jae .Lmb_done
        inc qword ptr [rsp]
        mov rax, [r12 + VEC_DATA]
        mov rbx, [rax + rcx*8]          # node
        cmp qword ptr [rbx + ND_TRACE], 0
        jne .Lmb_next                   # merged into another node during this pass
        mov rax, [r15 + CTX_VM]
        mov rdi, [rax + VM_SCR_BYJD]
        mov rsi, [rbx + ND_JD]
        call emap_get                   # its group + 1
        test rax, rax
        jz .Lmb_next
        mov rcx, [r15 + CTX_VM]
        mov rcx, [rcx + VM_SCR_HEADS]
        mov rcx, [rcx + VEC_DATA]
        shl rax, 4
        mov rdx, [rcx + rax - 16]       # the group's first
        cmp rdx, [rcx + rax - 8]
        je .Lmb_next                    # nothing to merge with (itself only)
        mov [rsp + 8], rdx              # the next other to try
        mov rax, [rbx + ND_JD]
        mov rdi, [rax + N_DATA]
        call vm_ends_execution
        test eax, eax
        jnz .Lmb_next                   # no point (e.g. a shared revert block)
.Lmb_other:
        mov rcx, [rsp + 8]
        cmp rcx, -1
        je .Lmb_next
        mov rax, [r15 + CTX_VM]
        mov rdx, [rax + VM_SCR_NEXT]
        mov rdx, [rdx + VEC_DATA]
        mov rdx, [rdx + rcx*8]
        mov [rsp + 8], rdx              # (the one after it)
        mov rdx, [rax + VM_SCR_ALL]
        mov rdx, [rdx + VEC_DATA]
        mov rsi, [rdx + rcx*8]          # other
        cmp rsi, rbx
        je .Lmb_other
        # the paths to node and other diverged at their closest common
        # ancestor. if it's an `if`, that's where they could be merged.
        mov rdi, rbx
        call vm_common_ancestor
        test rax, rax
        jz .Lmb_other
        mov [rsp + 24], rax             # p
        mov rdi, rax
        call is_if_node
        test eax, eax
        jz .Lmb_other
        mov rdi, [rsp + 24]
        mov rsi, [rbx + ND_JD]
        call mk2
        mov [rsp + 32], rax             # (p, jd)
        mov rdi, r14
        mov rsi, rax
        call map_get
        test rax, rax
        jnz .Lmb_other                  # tried already
        mov rdi, r14
        mov rsi, [rsp + 32]
        mov edx, 1
        call map_put
        mov rdi, [rsp + 24]
        mov rsi, [rbx + ND_JD]
        call vm_merge_at
        test eax, eax
        jz .Lmb_other
        jmp .Lmb_next
.Lmb_done:
        add rsp, 48
        LEAVE
ENDF vm_merge_branches

# mb_all_nodes(root) -> rax: the nodes below root in VM_SCR_ALL
# (find_nodes' order), and those not run yet, in the same order, in
# VM_SCR_UNEXP (returned). merge_branches' scratch is the VM's, reused at
# every round: python's dict of lists is garbage when the call returns,
# the arena's would stay - GBs over the rounds of a long run.
FUNC mb_all_nodes
        ENTER
        mov rbx, [r15 + CTX_VM]
        mov r12, rdi
        cmp qword ptr [rbx + VM_SCR_ALL], 0
        jne 1f
        call vec_new
        mov [rbx + VM_SCR_ALL], rax
        call vec_new
        mov [rbx + VM_SCR_NEXT], rax
        call vec_new
        mov [rbx + VM_SCR_HEADS], rax
        call emap_new
        mov [rbx + VM_SCR_BYJD], rax
        call vec_new
        mov [rbx + VM_SCR_UNEXP], rax
1:      mov rax, [rbx + VM_SCR_ALL]
        mov qword ptr [rax + VEC_LEN], 0
        mov rax, [rbx + VM_SCR_UNEXP]
        mov qword ptr [rax + VEC_LEN], 0
        mov rdi, r12
        lea rsi, [rip + pred_any]
        xor edx, edx
        mov rcx, [rbx + VM_SCR_ALL]
        call find_nodes_into
        xor r13d, r13d
        mov r12, [rbx + VM_SCR_ALL]
2:      cmp r13, [r12 + VEC_LEN]
        jae 3f
        mov rax, [r12 + VEC_DATA]
        mov rsi, [rax + r13*8]
        inc r13
        cmp qword ptr [rsi + ND_TRACE], 0
        jne 2b
        mov rdi, [rbx + VM_SCR_UNEXP]
        call vec_push
        jmp 2b
3:      mov rax, [rbx + VM_SCR_UNEXP]
        LEAVE
ENDF mb_all_nodes

# mb_by_jd(): merge_branches' by_jd, from the nodes mb_all_nodes put in
# VM_SCR_ALL: jd -> its group + 1 in VM_SCR_BYJD, the groups' (first,
# last) indexes into ALL in VM_SCR_HEADS, the next index in the same
# group (-1 after the last) in VM_SCR_NEXT. Only the groups of the jds of
# the nodes not run yet (VM_SCR_UNEXP): no other is asked for.
FUNC mb_by_jd
        ENTER
        mov rbx, [r15 + CTX_VM]
        mov rax, [rbx + VM_SCR_HEADS]
        mov qword ptr [rax + VEC_LEN], 0
        mov rdi, [rbx + VM_SCR_BYJD]
        call emap_begin
        xor r13d, r13d                  # the jds asked for: -1, no group yet
1:      mov rax, [rbx + VM_SCR_UNEXP]
        cmp r13, [rax + VEC_LEN]
        jae 11f
        mov rax, [rax + VEC_DATA]
        mov rax, [rax + r13*8]
        inc r13
        mov rdi, [rbx + VM_SCR_BYJD]
        mov rsi, [rax + ND_JD]
        mov rdx, -1
        call emap_put
        jmp 1b
11:     mov rax, [rbx + VM_SCR_ALL]     # NEXT as long as ALL (written for
        mov r12, [rax + VEC_LEN]        # the groups' nodes only)
        mov rdi, [rbx + VM_SCR_NEXT]
        mov rsi, r12
        call vec_resize
        xor r13d, r13d                  # i
2:      cmp r13, r12
        jae 9f
        mov rax, [rbx + VM_SCR_ALL]
        mov rax, [rax + VEC_DATA]
        mov rax, [rax + r13*8]
        mov r14, [rax + ND_JD]
        mov rdi, [rbx + VM_SCR_BYJD]
        mov rsi, r14
        call emap_get
        test rax, rax
        jz 4f                           # (a group nobody asks for)
        mov rcx, [rbx + VM_SCR_NEXT]
        mov rcx, [rcx + VEC_DATA]
        mov qword ptr [rcx + r13*8], -1 # next[i] = -1
        cmp rax, -1
        jne 3f
        mov rdi, [rbx + VM_SCR_HEADS]   # a new group: (i, i)
        mov rsi, r13
        call vec_push
        mov rdi, [rbx + VM_SCR_HEADS]
        mov rsi, r13
        call vec_push
        mov rax, [rbx + VM_SCR_HEADS]
        mov rdx, [rax + VEC_LEN]
        shr rdx, 1                      # its number + 1
        mov rdi, [rbx + VM_SCR_BYJD]
        mov rsi, r14
        call emap_put
        jmp 4f
3:      mov rcx, [rbx + VM_SCR_HEADS]   # after the group's last
        mov rcx, [rcx + VEC_DATA]
        shl rax, 4
        mov rdx, [rcx + rax - 8]        # the last
        mov [rcx + rax - 8], r13
        mov rax, [rbx + VM_SCR_NEXT]
        mov rax, [rax + VEC_DATA]
        mov [rax + rdx*8], r13
4:      inc r13
        jmp 2b
9:      LEAVE
ENDF mb_by_jd

# is_terminal_op(id) -> eax: the line ends the execution (or is a goto)
        OPSET_FUNC is_terminal_op, terminal
        OPSET_MEMBER terminal, OP_REVERT
        OPSET_MEMBER terminal, OP_RETURN
        OPSET_MEMBER terminal, OP_STOP
        OPSET_MEMBER terminal, OP_INVALID
        OPSET_MEMBER terminal, OP_ASSERT_FAIL
        OPSET_MEMBER terminal, OP_SELFDESTRUCT
        OPSET_MEMBER terminal, OP_UNDEFINED
        OPSET_MEMBER terminal, OP_GOTO
        OPSET_END terminal, OP_COUNT

# merge_visit(start, jd, hits) -> rax: python's visit (vm.py, _merge_at)
# - true if every path below `start` either ends, reaches `jd` (a hit),
# or loops back; false if one is the head of a loop at jd; none if it's
# too early to tell -, as _merge_at uses it: -1 when it isn't true (false
# or none: the merge isn't done, either way - the walk stops at the first
# path that says so), else the number of hits below (2 for 2 or more);
# the hits are pushed on `hits`, in python's order, when it isn't 0.
# _merge_at asks without the hits first (both sides true, 2 hits at least:
# then again for them). Python walks the subtree at every try, and
# merge_branches tries the same ones round after round when only the
# nodes run since changed: the answer of each inner node's subtree is
# remembered in the node, for the last jd asked (ND_VC_JD, ND_VC: -1, or
# the hits below), and holds while the node keeps its stamp (node_touch);
# a subtree with hits is walked again when they're asked for. Depth
# first, the children in order (python's order of the hits), on the VM's
# scratch stack (find_nodes' - not in use meanwhile): a frame of 4 words
# for each inner node being walked - the node, its next child, the hits
# below it so far, the nodes walked below it (an answer is remembered
# past MV_MIN_WALK of them); the leaves, the subtrees answered already and
# the chains of nodes of one child are looked at without a frame.
        .set MC_NOT, 1                  # the codes remembered (ND_VC & 7)
        .set MC_T0, 2                   # true: MC_T0 + the hits below (0, 1, 2)
        .set MV_MIN_WALK, 4

# MV_QUICK: the node rbx's own answer, eax = its hits (0, 1, 2; a hit
# pushed on hits), or a jump to .Lmv_not (not true: a path not run yet,
# a loop head at jd) or to .Lmv_push (an inner node to walk)
.macro MV_QUICK
        cmp qword ptr [rbx + ND_MERGED], 0
        jne 97f                         # goes on in the continuation of an if below
        mov rax, [rbx + ND_JD]
        cmp qword ptr [rbx + ND_LABEL], 0
        je 91f
        # the head of a loop: keep it that way. Otherwise the paths inside
        # the loop body are fair game (the loop may get peeled, see vm.py)
        cmp rax, r12
        je .Lmv_not
        jmp 92f
91:     cmp rax, r12
        jne 92f
        test r13, r13                   # a hit
        jz 90f
        mov rdi, r13
        mov rsi, rbx
        call vec_push
90:     mov eax, 1
        jmp 99f
92:     cmp qword ptr [rbx + ND_TRACE], 0
        je .Lmv_not
        mov rax, [rbx + ND_NEXT]
        cmp qword ptr [rax + VEC_LEN], 0
        jne 93f
        mov rax, [rbx + ND_TRACE]       # a leaf: it ends, or not yet
        mov rcx, [rax + VEC_LEN]
        test rcx, rcx
        jz .Lmv_not
        mov rax, [rax + VEC_DATA]
        mov rdi, [rax + rcx*8 - 8]
        OPCODE_OF_RDI
        IN_OPSET terminal, rax
        jne 97f
        jmp .Lmv_not                    # (e.g. 'loop', not yet processed by continue_loops)
93:     # an inner node: what its subtree answered, if it didn't change
        cmp [rbx + ND_VC_JD], r12
        jne .Lmv_push
        mov rax, [rbx + ND_VC]
        mov rcx, rax
        shr rcx, 3
        cmp rcx, [rbx + ND_STAMP]
        jne .Lmv_push
        and eax, 7
        cmp eax, MC_NOT
        je .Lmv_not
        sub eax, MC_T0
        jz 99f
        test r13, r13                   # hits below: walked again for them
        jz 99f
        jmp .Lmv_push
97:     xor eax, eax
99:
.endm

FUNC merge_visit
        ENTER
        sub rsp, 48
        .set MV_FRAME, 0                # a frame to push (4 words)
        mov rbx, rdi
        mov r12, rsi                    # jd
        mov r13, rdx                    # hits, or 0
        mov rax, [r15 + CTX_VM]
        mov r14, [rax + VM_SCR_VISIT]
        test r14, r14
        jnz 1f
        call vec_new
        mov r14, rax
        mov rax, [r15 + CTX_VM]
        mov [rax + VM_SCR_VISIT], r14
1:      mov qword ptr [r14 + VEC_LEN], 0
        MV_QUICK                        # the start
        jmp .Lmv_answer
.Lmv_push:                              # rbx: an inner node to walk
        mov rax, [rbx + ND_NEXT]
        cmp qword ptr [rax + VEC_LEN], 1
        jne .Lmv_frame
        # one child (a chain of them: straight code between jumps): the
        # child answers in its place, without a frame (nor a memory)
        mov rax, [rax + VEC_DATA]
        mov rbx, [rax]
        MV_QUICK
        cmp qword ptr [r14 + VEC_LEN], 0
        je .Lmv_answer
        jmp .Lmv_combine
.Lmv_frame:
        mov rcx, [r14 + VEC_LEN]
        lea r8, [rcx + 4]
        cmp r8, [r14 + VEC_CAP]
        ja 2f
        mov rdx, [r14 + VEC_DATA]
        lea rdx, [rdx + rcx*8]
        mov [rdx], rbx
        mov qword ptr [rdx + 8], 0
        mov qword ptr [rdx + 16], 0
        mov qword ptr [rdx + 24], 1
        mov [r14 + VEC_LEN], r8
        jmp .Lmv_children
2:      mov [rsp + MV_FRAME], rbx       # (no room: vec_extend makes some)
        mov qword ptr [rsp + MV_FRAME + 8], 0
        mov qword ptr [rsp + MV_FRAME + 16], 0
        mov qword ptr [rsp + MV_FRAME + 24], 1
        mov rdi, r14
        lea rsi, [rsp + MV_FRAME]
        mov edx, 4
        call vec_extend
.Lmv_children:                          # the top frame's next child
        mov rax, [r14 + VEC_LEN]
        mov rdx, [r14 + VEC_DATA]
        lea rdx, [rdx + rax*8 - 32]
        mov rbx, [rdx]
        mov rcx, [rdx + 8]
        mov rax, [rbx + ND_NEXT]
        cmp rcx, [rax + VEC_LEN]
        jae .Lmv_node_done
        inc qword ptr [rdx + 8]
        mov rax, [rax + VEC_DATA]
        mov rbx, [rax + rcx*8]
        MV_QUICK
.Lmv_combine:
        mov rcx, [r14 + VEC_LEN]        # its hits added to the frame's
        mov rdx, [r14 + VEC_DATA]       # (2 at most)
        lea rdx, [rdx + rcx*8 - 32]
        inc qword ptr [rdx + 24]
        add rax, [rdx + 16]
        mov ecx, 2
        cmp rax, rcx
        cmova rax, rcx
        mov [rdx + 16], rax
        jmp .Lmv_children
.Lmv_node_done:                         # rdx: the frame, rbx: its node
        mov rax, [rdx + 16]
        cmp qword ptr [rdx + 24], MV_MIN_WALK
        jb 3f                           # (a small subtree: not remembered)
        lea esi, [eax + MC_T0]
        mov [rbx + ND_VC_JD], r12
        mov rcx, [rbx + ND_STAMP]
        shl rcx, 3
        or rcx, rsi
        mov [rbx + ND_VC], rcx
        mov rcx, [r15 + CTX_VM]
        mov qword ptr [rcx + VM_VISITED], 1     # (the next change: a new generation)
3:      mov r8, [rdx + 24]              # popped; its hits added to its
        mov rcx, [r14 + VEC_LEN]        # parent's
        sub rcx, 4
        mov [r14 + VEC_LEN], rcx
        jz .Lmv_answer
        sub rdx, 32
        add [rdx + 24], r8
        add rax, [rdx + 16]
        mov ecx, 2
        cmp rax, rcx
        cmova rax, rcx
        mov [rdx + 16], rax
        jmp .Lmv_children
.Lmv_answer:                            # eax: the start's hits
        add rsp, 48
        LEAVE
.Lmv_not:
        # a path not run yet, or a loop head at jd, below every node of the
        # stack: not true for each
        mov rcx, [r14 + VEC_LEN]
5:      test rcx, rcx
        jz 6f
        sub rcx, 4
        mov [r14 + VEC_LEN], rcx
        mov rax, [r14 + VEC_DATA]
        mov rdi, [rax + rcx*8]
        mov [rdi + ND_VC_JD], r12
        mov rax, [rdi + ND_STAMP]
        shl rax, 3
        or rax, MC_NOT
        mov [rdi + ND_VC], rax
        jmp 5b
6:      mov rax, [r15 + CTX_VM]
        mov qword ptr [rax + VM_VISITED], 1
        mov rax, -1
        add rsp, 48
        LEAVE
ENDF merge_visit

# merge_visit_py(start, jd, hits) -> eax: python's visit as it is (the
# walk of every node, TRI_TRUE, TRI_FALSE or TRI_NONE, the hits pushed),
# for PANORAMIX_CHECK_LCA=1's comparison with merge_visit
FUNC merge_visit_py
        ENTER
        sub rsp, 16
        mov rbx, rsi                    # jd
        mov r12, rdx                    # hits
        mov r13, rdi
        call vec_new
        mov r14, rax                    # to_visit
        mov rdi, r14
        mov rsi, r13
        call vec_push
        mov r13d, TRI_TRUE              # result
1:      mov rcx, [r14 + VEC_LEN]
        test rcx, rcx
        jz 9f
        dec rcx
        mov [r14 + VEC_LEN], rcx
        mov rax, [r14 + VEC_DATA]
        mov rdi, [rax + rcx*8]          # n
        cmp qword ptr [rdi + ND_MERGED], 0
        jne 1b
        mov rax, [rdi + ND_JD]
        cmp qword ptr [rdi + ND_LABEL], 0
        je 2f
        cmp rax, rbx
        je 8f                           # the head of a loop at jd
        jmp 3f
2:      cmp rax, rbx
        jne 3f
        mov rsi, rdi                    # a hit
        mov rdi, r12
        call vec_push
        jmp 1b
3:      mov rax, [rdi + ND_TRACE]
        test rax, rax
        jnz 4f
        mov r13d, TRI_NONE
        jmp 1b
4:      mov rcx, [rdi + ND_NEXT]
        mov rdx, [rcx + VEC_LEN]
        test rdx, rdx
        jz 6f
        mov [rsp], rcx                  # the children, reversed
5:      dec rdx
        js 1b
        mov [rsp + 8], rdx
        mov rax, [rsp]
        mov rax, [rax + VEC_DATA]
        mov rsi, [rax + rdx*8]
        mov rdi, r14
        call vec_push
        mov rdx, [rsp + 8]
        jmp 5b
6:      mov rcx, [rax + VEC_LEN]        # a leaf
        test rcx, rcx
        jz 7f
        mov rax, [rax + VEC_DATA]
        mov rdi, [rax + rcx*8 - 8]
        OPCODE_OF_RDI
        IN_OPSET terminal, rax
        jne 1b
7:      mov r13d, TRI_NONE
        jmp 1b
8:      mov r13d, TRI_FALSE
9:      mov eax, r13d
        add rsp, 16
        LEAVE
ENDF merge_visit_py

# merge_check(ifx, jd, hits): PANORAMIX_CHECK_LCA=1 - python's visits of
# the sides of the if ifx must agree with merge_visit's: no merge when
# hits is 0, else a merge at the same hits
FUNC merge_check
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        call vec_new
        mov r14, rax
        mov rdi, [rbx + N_DATA + 16]
        mov rsi, r12
        mov rdx, r14
        call merge_visit_py
        cmp eax, TRI_TRUE
        jne 2f
        mov rdi, [rbx + N_DATA + 24]
        mov rsi, r12
        mov rdx, r14
        call merge_visit_py
        cmp eax, TRI_TRUE
        jne 2f
        cmp qword ptr [r14 + VEC_LEN], 2
        jb 2f
        test r13, r13                   # python merges: at the same hits?
        jz 8f
        mov rcx, [r14 + VEC_LEN]
        cmp rcx, [r13 + VEC_LEN]
        jne 8f
        mov rsi, [r14 + VEC_DATA]
        mov rdi, [r13 + VEC_DATA]
1:      dec rcx
        js 9f
        mov rax, [rsi + rcx*8]
        cmp rax, [rdi + rcx*8]
        jne 8f
        jmp 1b
2:      test r13, r13                   # python doesn't
        jz 9f
8:      lea rdi, [rip + .Ls_merge_mismatch]
        call rt_fatal
9:      LEAVE
ENDF merge_check
        .section .rodata
.Ls_merge_mismatch: .asciz "vm_merge_at: merge_visit and python's walk disagree"
        .text

# vm_merge_at(p, jd) -> eax: merge the paths going out of the `if` node p
# at jumpdest jd. False if it couldn't be done (it will be tried again
# when another node reaches jd).
FUNC vm_merge_at
        ENTER
        sub rsp, 80
        mov rbx, rdi                    # p
        mov r12, rsi                    # jd
        cmp [rbx + ND_JD], r12
        je .Lma_false                   # a loop rather than a merge
        mov rdi, rbx
        call is_if_node
        test eax, eax
        jz .Lma_false                   # p isn't an if any more
        mov rax, [rbx + ND_TRACE]
        mov rcx, [rax + VEC_LEN]
        mov rax, [rax + VEC_DATA]
        mov r14, [rax + rcx*8 - 8]      # ('if', cond, if_true, if_false)
        mov rdi, [r14 + N_DATA + 16]    # both sides true, 2 hits at least?
        mov rsi, r12
        xor edx, edx
        call merge_visit
        test rax, rax
        js .Lma_no
        mov [rsp + 56], rax
        mov rdi, [r14 + N_DATA + 24]
        mov rsi, r12
        xor edx, edx
        call merge_visit
        test rax, rax
        js .Lma_no
        add rax, [rsp + 56]
        cmp rax, 2
        jb .Lma_no
        call vec_new                    # then the hits
        mov r13, rax
        mov rdi, [r14 + N_DATA + 16]
        mov rsi, r12
        mov rdx, r13
        call merge_visit
        mov rdi, [r14 + N_DATA + 24]
        mov rsi, r12
        mov rdx, r13
        call merge_visit
        mov rax, [r15 + CTX_VM]
        cmp qword ptr [rax + VM_CHECK_LCA], 0
        je 1f
        mov rdi, r14
        mov rsi, r12
        mov rdx, r13
        call merge_check
1:
        # merged = the stack of the first hit, with a variable wherever
        # the hits' stacks differ; setvars[k] = the assignments on path k
        mov rax, [r13 + VEC_DATA]
        mov rax, [rax]
        mov rax, [rax + ND_STACK]
        mov ecx, [rax + N_AUX]
        mov [rsp], rcx                  # stack length
        lea rdi, [rcx*8]
        call arena_alloc
        mov [rsp + 8], rax              # merged elements
        mov rdi, rax
        mov rax, [r13 + VEC_DATA]
        mov rax, [rax]
        mov rax, [rax + ND_STACK]
        lea rsi, [rax + N_DATA]
        mov rdx, [rsp]
        shl rdx, 3
        call memcpy@PLT
        mov rdi, [r13 + VEC_LEN]
        shl rdi, 3
        call arena_alloc
        mov [rsp + 16], rax             # setvars: a vec per hit
        xor ecx, ecx
1:      cmp rcx, [r13 + VEC_LEN]
        jae 2f
        mov [rsp + 24], rcx
        call vec_new
        mov rcx, [rsp + 24]
        mov rdx, [rsp + 16]
        mov [rdx + rcx*8], rax
        inc rcx
        jmp 1b
2:      mov qword ptr [rsp + 24], 0     # idx
.Lma_idx:
        mov rcx, [rsp + 24]
        cmp rcx, [rsp]
        jae .Lma_apply
        # vals = [h.stack[idx] for h in hits]; all equal?
        mov rax, [r13 + VEC_DATA]
        mov rax, [rax]
        mov rax, [rax + ND_STACK]
        mov rax, [rax + N_DATA + rcx*8]
        mov [rsp + 32], rax             # vals[0]
        mov qword ptr [rsp + 40], 1     # k
3:      mov rcx, [rsp + 40]
        cmp rcx, [r13 + VEC_LEN]
        jae .Lma_same
        mov rax, [r13 + VEC_DATA]
        mov rax, [rax + rcx*8]
        mov rax, [rax + ND_STACK]
        mov rcx, [rsp + 24]
        mov rsi, [rax + N_DATA + rcx*8]
        mov rdi, [rsp + 32]
        call values_equal
        test eax, eax
        jz .Lma_differ
        inc qword ptr [rsp + 40]
        jmp 3b
.Lma_differ:
        # let's not turn a jump destination into a variable
        mov qword ptr [rsp + 40], 0
4:      mov rcx, [rsp + 40]
        cmp rcx, [r13 + VEC_LEN]
        jae 5f
        mov rax, [r13 + VEC_DATA]
        mov rax, [rax + rcx*8]
        mov rax, [rax + ND_STACK]
        mov rcx, [rsp + 24]
        mov rsi, [rax + N_DATA + rcx*8]
        test sil, 1
        jz 6f
        sar rsi, 1
        mov rdi, [r15 + CTX_VM]
        mov rdi, [rdi + VM_LOADER]
        call loader_is_jumpdest
        test eax, eax
        jnz .Lma_false
6:      inc qword ptr [rsp + 40]
        jmp 4b
5:      call vm_new_var_name
        mov [rsp + 48], rax             # name
        mov rsi, rax
        LOADS rdi, VAR
        call mk2
        mov rcx, [rsp + 24]
        mov rdx, [rsp + 8]
        mov [rdx + rcx*8], rax          # merged[idx] = ('var', name)
        mov qword ptr [rsp + 40], 0
7:      mov rcx, [rsp + 40]
        cmp rcx, [r13 + VEC_LEN]
        jae .Lma_same
        mov rax, [r13 + VEC_DATA]
        mov rax, [rax + rcx*8]
        mov rax, [rax + ND_STACK]
        mov rcx, [rsp + 24]
        mov rdx, [rax + N_DATA + rcx*8]
        mov rsi, [rsp + 48]
        LOADS rdi, SETVAR
        call mk3
        mov rcx, [rsp + 40]
        mov rdi, [rsp + 16]
        mov rdi, [rdi + rcx*8]
        mov rsi, rax
        call vec_push
        inc qword ptr [rsp + 40]
        jmp 7b
.Lma_same:
        inc qword ptr [rsp + 24]
        jmp .Lma_idx
.Lma_apply:
        mov rax, [r15 + CTX_VM]         # (merge_branches' unexpanded nodes
        mov qword ptr [rax + VM_UNEXP_VALID], 0         # change)
        # each hit now just sets the variables and goes on in the merged node
        mov qword ptr [rsp + 24], 0
8:      mov rcx, [rsp + 24]
        cmp rcx, [r13 + VEC_LEN]
        jae 9f
        mov rax, [r13 + VEC_DATA]
        mov rax, [rax + rcx*8]
        mov rdx, [rsp + 16]
        mov rdx, [rdx + rcx*8]
        mov [rax + ND_TRACE], rdx
        mov qword ptr [rax + ND_MERGED], 1
        mov [rsp + 32], rax
        call vec_new
        mov rcx, [rsp + 32]
        mov [rcx + ND_NEXT], rax
        mov rdi, rcx
        call node_touch
        inc qword ptr [rsp + 24]
        jmp 8b
9:      # what's known at the merge point is what's known on every path
        mov rdi, r13
        call merged_known
        mov [rsp + 32], rax
        mov rdi, [rsp]
        mov rsi, [rsp + 8]
        call mk_tuple
        mov rdx, rax
        mov rdi, [r12 + N_DATA]         # jd[0]
        mov rax, [r13 + VEC_DATA]
        mov rax, [rax]
        mov rsi, [rax + ND_SAFE]
        lea rcx, [rip + sp_true]
        mov r8, [rsp + 32]
        call node_new
        mov r14, rax
        mov rdi, r14
        mov rsi, rbx
        call node_set_prev
        LOADS rdi, JUMP
        mov rsi, r14
        call mk2
        mov rdi, [rbx + ND_TRACE]
        mov rsi, rax
        call vec_push
        mov eax, 1
        add rsp, 80
        LEAVE
.Lma_no:
        mov rax, [r15 + CTX_VM]
        cmp qword ptr [rax + VM_CHECK_LCA], 0
        je .Lma_false
        mov rdi, r14
        mov rsi, r12
        xor edx, edx
        call merge_check
.Lma_false:
        xor eax, eax
        add rsp, 80
        LEAVE
ENDF vm_merge_at

# merged_known(hits) -> tuple: the facts known on every path
FUNC merged_known
        ENTER
        sub rsp, 16
        mov rbx, rdi
        call vec_new
        mov r12, rax
        mov rax, [rbx + VEC_DATA]
        mov rax, [rax]
        mov r13, [rax + ND_KNOWN]       # hits[0].known
        xor r14d, r14d
1:      cmp r14d, [r13 + N_AUX]
        jae 5f
        mov rdi, [r13 + N_DATA + r14*8] # fact
        mov ecx, 1                      # k
2:      cmp rcx, [rbx + VEC_LEN]
        jae 4f
        mov rax, [rbx + VEC_DATA]
        mov rax, [rax + rcx*8]
        mov rax, [rax + ND_KNOWN]
        # fact in h.known?
        xor edx, edx
3:      cmp edx, [rax + N_AUX]
        jae 6f                          # not there: drop the fact
        cmp [rax + N_DATA + rdx*8], rdi
        je 7f
        inc edx
        jmp 3b
7:      inc rcx
        jmp 2b
4:      mov rsi, rdi
        mov rdi, r12
        call vec_push
6:      inc r14
        jmp 1b
5:      mov rdi, r12
        call vec_to_tuple
        add rsp, 16
        LEAVE
ENDF merged_known

# vm_new_var_name() -> rax: the next '_N' name
FUNC vm_new_var_name
        ENTER
        sub rsp, 32
        mov rax, [r15 + CTX_VM]
        inc qword ptr [rax + VM_COUNTER]
        mov rcx, [rax + VM_COUNTER]
        mov rdi, rsp
        mov esi, 32
        lea rdx, [rip + .Ls_var_fmt]
        xor eax, eax
        call snprintf@PLT
        mov rdi, rsp
        mov esi, eax
        call str_intern
        add rsp, 32
        LEAVE
ENDF vm_new_var_name

# --- path conditions ---

# forget_volatile(known) -> tuple: without the facts about things that can
# change while the contract runs
FUNC forget_volatile
        ENTER
        mov rbx, rdi
        call vec_new
        mov r12, rax
        xor r13d, r13d
1:      cmp r13d, [rbx + N_AUX]
        jae 3f
        mov rdi, [rbx + N_DATA + r13*8]
        call is_volatile
        test eax, eax
        jnz 2f
        mov rdi, r12
        mov rsi, [rbx + N_DATA + r13*8]
        call vec_push
2:      inc r13
        jmp 1b
3:      mov rdi, r12
        call vec_to_tuple
        LEAVE
ENDF forget_volatile

# forget_storage(known) -> tuple: without the facts mentioning storage
FUNC forget_storage
        ENTER
        mov rbx, rdi
        call vec_new
        mov r12, rax
        xor r13d, r13d
1:      cmp r13d, [rbx + N_AUX]
        jae 3f
        mov rdi, [rbx + N_DATA + r13*8]
        mov rsi, HF_STORAGE
        call mentions
        test eax, eax
        jnz 2f
        mov rdi, r12
        mov rsi, [rbx + N_DATA + r13*8]
        call vec_push
2:      inc r13
        jmp 1b
3:      mov rdi, r12
        call vec_to_tuple
        LEAVE
ENDF forget_storage

# mentions(exp, HF_flag) -> eax: a string anywhere in exp contains the
# word of the flag (python's `"mem" in str(exp)`, from the flags kept in
# the hashes, see hash_seq)
FUNC mentions
        xor eax, eax
        test dil, 1
        jnz 1f
        test rdi, rdi
        jz 1f
        test [rdi + N_HASH], rsi
        setnz al
1:      ret
ENDF mentions

# mentions_c(exp, cstr) -> eax: a string anywhere in exp contains cstr
# (python's `word in str(exp)` for a word of letters: the repr of a
# string escapes none of them, nor makes one out of what it escapes)
FUNC mentions_c
        STACK_CHECK
        test dil, 1
        jnz .Lmc_no
        test rdi, rdi
        jz .Lmc_no
        mov eax, [rdi + N_KIND]
        cmp eax, K_STR
        jne 1f
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov rdi, rsi
        call strlen@PLT
        mov rcx, rax                    # (memmem: the string's NULs are in it)
        mov esi, [rbx + N_DATA]
        lea rdi, [rbx + N_DATA + 4]
        mov rdx, r12
        call memmem@PLT
        test rax, rax
        setnz al
        movzx eax, al
        LEAVE
1:      cmp eax, K_TUPLE
        je 2f
        cmp eax, K_LIST
        jne .Lmc_no
2:      ENTER
        mov rbx, rdi
        mov r12, rsi
        xor r13d, r13d
3:      cmp r13d, [rbx + N_AUX]
        jae 4f
        mov rdi, [rbx + N_DATA + r13*8]
        mov rsi, r12
        call mentions_c
        test eax, eax
        jnz 5f
        inc r13
        jmp 3b
4:      xor eax, eax
        LEAVE
5:      mov eax, 1
        LEAVE
.Lmc_no:
        xor eax, eax
        ret
ENDF mentions_c

# is_known(exp, known) -> eax: TRI_TRUE/TRI_FALSE if exp is decided by
# the known conditions, TRI_NONE otherwise. Python asks eval_bool(exp,
# fact) of every fact, from the last one (some 150 of them on the paths
# of aave's logic libraries, nearly all answering None). eval_bool looks
# at the fact only where it compares it with exp or with a part it goes
# into (the operand of a bool or an iszero, the terms of an or or an
# and): the fact itself, its is_zero, and an lt/le of the same first
# operand; a fact equal to none of those gives what any other such fact
# gives - asked once, of the first one. The parts' is_zero are computed
# first, under a handler: on an error there (python may not have come to
# it), the facts are asked one by one, as python does.
        .set IK_MAXP, 16
        .set IK_ERR, 0
        .set IK_NP, ERR_SIZEOF          # the number of parts
        .set IK_FB, ERR_SIZEOF + 8      # the answer of the facts that match nothing (IK_UNASKED)
        .set IK_F, ERR_SIZEOF + 16      # the fact, unwrapped
        .set IK_P, ERR_SIZEOF + 24      # the parts
        .set IK_Z, IK_P + IK_MAXP * 8   # their is_zero
        .set IK_FRAME, (IK_Z + IK_MAXP * 8 + 15) & -16
        .set IK_UNASKED, -3
FUNC is_known
        ENTER
        sub rsp, IK_FRAME
        mov rbx, rdi
        mov r12, rsi
        mov r13d, [r12 + N_AUX]
        cmp r13d, 4
        jb .Lik_plain
        mov rdi, rbx
        lea rsi, [rsp + IK_P]
        call ik_parts
        test rax, rax
        js .Lik_plain
        mov [rsp + IK_NP], rax
        mov rdi, rsp
        call err_catch
        test eax, eax
        jnz .Lik_caught
        xor r14d, r14d
1:      cmp r14, [rsp + IK_NP]
        jae 2f
        mov rdi, [rsp + IK_P + r14*8]
        call is_zero
        mov [rsp + IK_Z + r14*8], rax
        inc r14
        jmp 1b
2:      call err_end
        mov qword ptr [rsp + IK_FB], IK_UNASKED
.Lik_fact:                              # the facts, from the last
        test r13d, r13d
        jz .Lik_none
        dec r13d
        mov r14, [r12 + N_DATA + r13*8]
        mov rax, r14                    # a known-true ('bool', x) is a known-true x
        test al, 1
        jnz 3f
        test rax, rax
        jz .Lik_ask
        cmp dword ptr [rax + N_KIND], K_TUPLE
        jne 4f
        mov rdi, rax
        OPCODE_OF_RDI
        cmp eax, OP_BOOL
        mov rax, r14
        jne 3f
        cmp dword ptr [rax + N_AUX], 2
        jne 3f
        mov rax, [rax + N_DATA + 8]
        # a bool still (unwrapped again below), or a big number: asked
        test al, 1
        jnz 3f
        test rax, rax
        jz .Lik_ask
        cmp dword ptr [rax + N_KIND], K_TUPLE
        jne 4f
        mov rdi, rax
        OPCODE_OF_RDI
        cmp eax, OP_BOOL
        je .Lik_ask
        mov rax, [r14 + N_DATA + 8]
        jmp 3f
4:      cmp dword ptr [rax + N_KIND], K_INT
        je .Lik_ask
3:      mov [rsp + IK_F], rax
        # a part, or a part's is_zero
        mov rcx, [rsp + IK_NP]
5:      dec rcx
        js 6f
        cmp rax, [rsp + IK_P + rcx*8]
        je .Lik_ask
        cmp rax, [rsp + IK_Z + rcx*8]
        je .Lik_ask
        jmp 5b
6:      # its is_zero a part
        mov rdi, rax
        call is_zero
        mov rcx, [rsp + IK_NP]
7:      dec rcx
        js 8f
        cmp rax, [rsp + IK_P + rcx*8]
        je .Lik_ask
        jmp 7b
8:      # an lt / le with the first operand of a part of the same opcode
        mov rdi, [rsp + IK_F]
        OPCODE_OF_RDI
        cmp eax, OP_LT
        je 9f
        cmp eax, OP_LE
        jne .Lik_neutral
9:      mov rdi, [rsp + IK_F]
        cmp dword ptr [rdi + N_AUX], 3
        jne .Lik_neutral
        mov [rsp + IK_ERR], rax         # (the handler's buffer, free now)
        mov rax, [rsp + IK_NP]
        mov [rsp + IK_ERR + 8], rax
10:     dec qword ptr [rsp + IK_ERR + 8]
        js .Lik_neutral
        mov rcx, [rsp + IK_ERR + 8]
        mov rdi, [rsp + IK_P + rcx*8]
        test dil, 1
        jnz 10b
        test rdi, rdi
        jz 10b
        cmp dword ptr [rdi + N_KIND], K_TUPLE
        jne 10b
        cmp dword ptr [rdi + N_AUX], 3
        jne 10b
        OPCODE_OF_RDI
        cmp rax, [rsp + IK_ERR]
        jne 10b
        mov rcx, [rsp + IK_ERR + 8]
        mov rdi, [rsp + IK_P + rcx*8]
        mov rdi, [rdi + N_DATA + 8]
        mov rsi, [rsp + IK_F]
        mov rsi, [rsi + N_DATA + 8]
        call values_equal
        test eax, eax
        jnz .Lik_ask
        jmp 10b
.Lik_neutral:                           # what the facts matching nothing give
        mov rax, [rsp + IK_FB]
        cmp rax, IK_UNASKED
        jne 11f
        mov rdi, rbx
        mov rsi, r14
        xor edx, edx
        call eval_bool
        movsxd rax, eax
        mov [rsp + IK_FB], rax
11:     cmp eax, TRI_NONE
        je .Lik_fact
        jmp .Lik_ret
.Lik_ask:
        mov rdi, rbx
        mov rsi, r14
        xor edx, edx
        call eval_bool
        cmp eax, TRI_NONE
        je .Lik_fact
        jmp .Lik_ret
.Lik_caught:                            # (python's timeout, its memory and
        cmp eax, E_TIMEOUT              # recursion errors: the handler's above)
        je 12f
        cmp eax, E_MEMORY
        je 12f
        cmp eax, E_RECURSION
        jne .Lik_plain
12:     mov edi, eax
        mov rsi, [r15 + CTX_ERR_MSG]
        call err_throw
.Lik_plain:                             # python's loop
        test r13d, r13d
        jz .Lik_none
        dec r13d
        mov rdi, rbx
        mov rsi, [r12 + N_DATA + r13*8]
        xor edx, edx
        call eval_bool
        cmp eax, TRI_NONE
        je .Lik_plain
        jmp .Lik_ret
.Lik_none:
        mov eax, TRI_NONE
.Lik_ret:
        add rsp, IK_FRAME
        LEAVE
ENDF is_known

# ik_parts(exp, out) -> rax: the parts of exp eval_bool goes into (exp,
# the operand of a bool or an iszero, the terms of an or or an and, and
# theirs), in out (IK_MAXP at most), their number; -1 for more, or for a
# big number among them (compared by value)
FUNC ik_parts
        ENTER
        mov [rsi], rdi
        mov r12, rsi
        mov ebx, 1                      # the parts found
        xor r13d, r13d                  # the next to look into
1:      cmp r13, rbx
        jae 9f
        mov rdi, [r12 + r13*8]
        inc r13
        test dil, 1
        jnz 1b
        test rdi, rdi
        jz 1b
        mov eax, [rdi + N_KIND]
        cmp eax, K_INT
        je 8f
        cmp eax, K_TUPLE
        jne 1b
        mov r14, rdi
        OPCODE_OF_RDI
        cmp eax, OP_BOOL
        je 2f
        cmp eax, OP_ISZERO
        je 2f
        cmp eax, OP_OR
        je 3f
        cmp eax, OP_AND
        jne 1b
3:      mov ecx, 1                      # the terms
4:      cmp ecx, [r14 + N_AUX]
        jae 1b
        cmp rbx, IK_MAXP
        jae 8f
        mov rax, [r14 + N_DATA + rcx*8]
        mov [r12 + rbx*8], rax
        inc rbx
        inc ecx
        jmp 4b
2:      cmp dword ptr [r14 + N_AUX], 2
        jne 1b
        cmp rbx, IK_MAXP
        jae 8f
        mov rax, [r14 + N_DATA + 8]
        mov [r12 + rbx*8], rax
        inc rbx
        jmp 1b
8:      mov rax, -1
        LEAVE
9:      mov rax, rbx
        LEAVE
ENDF ik_parts

# contains_value(exp, v) -> eax: v is exp or one of its subterms
FUNC contains_value
        STACK_CHECK
        cmp rdi, rsi
        je .Lcv_yes
        test dil, 1
        jnz .Lcv_no
        test rdi, rdi
        jz .Lcv_no
        mov eax, [rdi + N_KIND]
        cmp eax, K_TUPLE
        je 1f
        cmp eax, K_LIST
        jne .Lcv_no
1:      ENTER
        mov rbx, rdi
        mov r12, rsi
        xor r13d, r13d
2:      cmp r13d, [rbx + N_AUX]
        jae 3f
        mov rdi, [rbx + N_DATA + r13*8]
        mov rsi, r12
        call contains_value
        test eax, eax
        jnz 4f
        inc r13
        jmp 2b
3:      xor eax, eax
        LEAVE
4:      mov eax, 1
        LEAVE
.Lcv_yes:
        mov eax, 1
        ret
.Lcv_no:
        xor eax, eax
        ret
ENDF contains_value

# tuple_append(tuple, v) -> tuple: python's `t + (v,)`
FUNC tuple_append
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
        call vec_push
        mov rdi, r13
        call vec_to_tuple
        LEAVE
ENDF tuple_append

# --- running one node ---

# vm_pop() -> rax: the top of the symbolic stack (an error when empty,
# like python's pop from an empty list)
FUNC vm_pop
        mov rcx, [r15 + CTX_VM]
        mov rdi, [rcx + VM_STACK]
        mov rax, [rdi + VEC_LEN]
        test rax, rax
        jz 1f
        dec rax
        mov [rdi + VEC_LEN], rax
        cmp [rcx + VM_CLEAN], rax       # (stack_cleanup's start: below the top)
        jbe 2f
        mov [rcx + VM_CLEAN], rax
2:      mov rcx, [rdi + VEC_DATA]
        mov rax, [rcx + rax*8]
        ret
1:      mov edi, E_STACK_UNDERFLOW
        lea rsi, [rip + .Ls_underflow]
        jmp err_throw
ENDF vm_pop

        .section .rodata
.Ls_underflow: .asciz "pop from an empty stack"
.Ls_stack_index: .asciz "list index out of range (dup or swap below the stack)"
        .text

# vm_push(v): push on the symbolic stack, simplified
FUNC vm_push
        ENTER
        call stack_simplify
        mov rdi, [r15 + CTX_VM]
        mov rdi, [rdi + VM_STACK]
        mov rsi, rax
        call vec_push
        LEAVE
ENDF vm_push

# mk_mem_range(pos, size) -> ('mem', ('range', pos, size))
FUNC mk_mem_range
        ENTER
        mov rdx, rsi
        mov rsi, rdi
        LOADS rdi, RANGE
        call mk3
        mov rsi, rax
        LOADS rdi, MEM
        call mk2
        LEAVE
ENDF mk_mem_range

# mk_range(pos, size) -> ('range', pos, size)
FUNC mk_range
        mov rdx, rsi
        mov rsi, rdi
        LOADS rdi, RANGE
        jmp mk3
ENDF mk_range

# vm_exec(start, safe, stack, condition, known) -> vec: the trace of the
# execution from `start` to the next jump (VM._run)
FUNC vm_exec
        ENTER
        sub rsp, 32
        mov rbx, [r15 + CTX_VM]
        mov [rsp], rdi                  # start
        mov [rsp + 8], rsi              # safe
        mov [rsp + 16], rdx             # stack (tuple)
        mov [rsp + 24], rcx             # condition
        mov [rbx + VM_KNOWN], r8
        call vec_new
        mov [rbx + VM_STACK], rax
        mov qword ptr [rbx + VM_CLEAN], 0
        mov rdi, rax
        mov rsi, [rsp + 16]
        call vec_extend_seq
        call vec_new
        mov [rbx + VM_TRACE], rax
        mov r12, [rbx + VM_LOADER]
        mov rdi, [rsp]
        test dil, 1
        jnz 0f
        test rdi, rdi
        jz .Lex_runtime_param
        cmp dword ptr [rdi + N_KIND], K_INT
        je .Lex_bad_jumdest             # an int too big to be a line: python's invalid jumdest
        jmp .Lex_runtime_param
0:      mov r13, rdi
        sar r13, 1                      # pc
        js .Lex_bad_jumdest
        mov rdi, r12
        mov rsi, r13
        call loader_instr_at
        test rax, rax
        jz .Lex_bad_jumdest
        mov r14, rax                    # the instruction
        cmp qword ptr [rsp + 8], 0
        jne 1f
        cmp byte ptr [r14 + IN_OP], 0x5b
        jne .Lex_bad_jump
1:      cmp byte ptr [r14 + IN_OP], 0x5b
        jne .Lex_loop
        # This node stands for this jumpdest already: don't create another
        # one for it below, it would look like a one-node loop.
        mov rdi, r12
        mov rsi, r13
        call loader_next_line
        mov r13, rax
        mov rdi, r12
        mov rsi, r13
        call loader_instr_at
        test rax, rax
        jz .Lex_eof
        mov r14, rax
.Lex_loop:
        mov rdi, r14
        mov rsi, [rsp + 24]
        call vm_step
        test eax, eax
        jnz .Lex_done
        mov rdi, r12
        mov rsi, r13
        call loader_next_line
        mov r13, rax
        mov rdi, r12
        mov rsi, r13
        call loader_instr_at
        test rax, rax
        jz .Lex_past_end
        mov r14, rax
        jmp .Lex_loop
.Lex_past_end:
        LOADS rdi, INVALID
        lea rsi, [rip + .Ls_jumpdest]
        call .Lex_line_c
        jmp .Lex_done
.Lex_runtime_param:
        lea rdi, [rip + .Ls_runtime_param]
        call str_intern_c
        mov rsi, rax
        mov rdx, [rsp]
        LOADS rdi, UNDEFINED
        call mk3
        call .Lex_push_line
        jmp .Lex_done
.Lex_bad_jumdest:
        lea rdi, [rip + .Ls_jumdest]
        call str_intern_c
        mov rsi, rax
        mov rdx, [rsp]
        LOADS rdi, INVALID
        call mk3
        call .Lex_push_line
        jmp .Lex_done
.Lex_bad_jump:
        LOADS rdi, INVALID
        lea rsi, [rip + .Ls_jump]
        call .Lex_line_c
        jmp .Lex_done
.Lex_eof:
        LOADS rdi, INVALID
        lea rsi, [rip + .Ls_eof]
        call .Lex_line_c
.Lex_done:
        mov rax, [rbx + VM_TRACE]
        add rsp, 32
        LEAVE

# local: append (op, cstring) to the trace
.Lex_line_c:
        sub rsp, 24
        mov [rsp], rdi
        mov rdi, rsi
        call str_intern_c
        mov rdi, [rsp]
        mov rsi, rax
        call mk2
        mov rdi, [rbx + VM_TRACE]
        mov rsi, rax
        call vec_push
        add rsp, 24
        ret
# local: append the line rax to the trace
.Lex_push_line:
        sub rsp, 8
        mov rdi, [rbx + VM_TRACE]
        mov rsi, rax
        call vec_push
        add rsp, 8
        ret
ENDF vm_exec

# --- one instruction: handle_jumps + apply_stack ---

.macro VPOP reg
        call vm_pop
        mov \reg, rax
.endm

.macro VPUSH reg
        mov rdi, \reg
        call vm_push
.endm

.macro VTRACE reg
        mov rdi, [rbx + VM_TRACE]
        mov rsi, \reg
        call vec_push
.endm

        .section .data.rel.ro
        .align 8
step_table:
        .quad .Lop_stop, .Lop_add, .Lop_mul, .Lop_sub, .Lop_arith, .Lop_arith, .Lop_arith, .Lop_arith    # 00-07
        .quad .Lop_mulmod, .Lop_mulmod, .Lop_arith, .Lop_arith, .Lop_unknown, .Lop_unknown, .Lop_unknown, .Lop_unknown   # 08-0f
        .quad .Lop_arith, .Lop_arith, .Lop_arith, .Lop_arith, .Lop_arith, .Lop_unary, .Lop_arith, .Lop_or   # 10-17
        .quad .Lop_arith, .Lop_unary, .Lop_byte, .Lop_shl, .Lop_shr, .Lop_sar, .Lop_unknown, .Lop_unknown   # 18-1f
        .quad .Lop_sha3, .Lop_unknown, .Lop_unknown, .Lop_unknown, .Lop_unknown, .Lop_unknown, .Lop_unknown, .Lop_unknown   # 20-27
        .quad .Lop_unknown, .Lop_unknown, .Lop_unknown, .Lop_unknown, .Lop_unknown, .Lop_unknown, .Lop_unknown, .Lop_unknown   # 28-2f
        .quad .Lop_env, .Lop_balance, .Lop_env, .Lop_env, .Lop_env, .Lop_calldataload, .Lop_env, .Lop_calldatacopy   # 30-37
        .quad .Lop_codesize, .Lop_codecopy, .Lop_env, .Lop_unary, .Lop_extcodecopy, .Lop_env, .Lop_returndatacopy, .Lop_unary   # 38-3f
        .quad .Lop_unary, .Lop_env, .Lop_env, .Lop_env, .Lop_env, .Lop_env, .Lop_env, .Lop_selfbalance   # 40-47
        .quad .Lop_env, .Lop_unknown, .Lop_unknown, .Lop_unknown, .Lop_unknown, .Lop_unknown, .Lop_unknown, .Lop_unknown   # 48-4f
        .quad .Lop_pop, .Lop_mload, .Lop_mstore, .Lop_mstore8, .Lop_sload, .Lop_sstore, .Lop_jump, .Lop_jumpi   # 50-57
        .quad .Lop_pc, .Lop_msize, .Lop_env, .Lop_jumpdest, .Lop_unknown, .Lop_unknown, .Lop_unknown, .Lop_push   # 58-5f
        .rept 32
        .quad .Lop_push                 # 60-7f
        .endr
        .rept 16
        .quad .Lop_dup                  # 80-8f
        .endr
        .rept 16
        .quad .Lop_swap                 # 90-9f
        .endr
        .quad .Lop_log, .Lop_log, .Lop_log, .Lop_log, .Lop_log, .Lop_unknown, .Lop_unknown, .Lop_unknown   # a0-a7
        .rept 72
        .quad .Lop_unknown              # a8-ef
        .endr
        .quad .Lop_create, .Lop_call, .Lop_callcode, .Lop_return, .Lop_delegatecall, .Lop_create2, .Lop_unknown, .Lop_unknown   # f0-f7
        .quad .Lop_unknown, .Lop_unknown, .Lop_call, .Lop_unknown, .Lop_unknown, .Lop_return, .Lop_invalid, .Lop_selfdestruct   # f8-ff

        .text

# vm_step(instr, condition) -> eax: 1 when the instruction ends the trace
# (a jump, or the end of the execution). rbx = vm, r12 = instr, r13 = the
# mnemonic, r14 = the parameter; [rsp..] hold the operands.
FUNC vm_step
        ENTER
        sub rsp, 80
        mov rbx, [r15 + CTX_VM]
        mov r12, rdi
        mov [rsp + 72], rsi             # condition
        test byte ptr [r15 + CTX_VERBOSE], VB_ASM
        jnz .Lstep_asm
.Lstep_dispatch:
        movzx eax, byte ptr [r12 + IN_OP]
        lea rcx, [rip + evm_op_nodes]
        mov r13, [rcx + rax*8]
        mov r14, [r12 + IN_PARAM]
        lea rcx, [rip + step_table]
        jmp [rcx + rax*8]
.Lstep_asm:
        # --verbose, --explain: the instruction's lines of assembly first
        mov rdi, r12
        call vm_trace_asm
        jmp .Lstep_dispatch

# exp, and, eq, div, lt, gt, slt, sgt, mod, xor, signextend, smod, sdiv:
# arithmetic.eval((op, a, b))
.Lop_arith:
        VPOP [rsp]
        VPOP rdx
        mov rsi, [rsp]
        mov rdi, r13
        call mk3
        mov rdi, rax
        call arith_eval
        VPUSH rax
        jmp .Lstep_epilogue

.Lop_push:
        VPUSH r14
        jmp .Lstep_cleanup

.Lop_pop:
        VPOP rax
        jmp .Lstep_epilogue

.Lop_dup:
        mov rax, r14
        sar rax, 1
        mov rdi, [rbx + VM_STACK]
        mov rcx, [rdi + VEC_LEN]
        sub rcx, rax
        jb .Lop_stack_index             # stack[-n] of a shorter stack: IndexError
        mov rdx, [rdi + VEC_DATA]
        mov rsi, [rdx + rcx*8]
        call vec_push
        jmp .Lstep_cleanup

.Lop_swap:
        mov rax, r14
        sar rax, 1
        mov rdi, [rbx + VM_STACK]
        mov rcx, [rdi + VEC_LEN]
        cmp rcx, rax
        jbe .Lop_stack_index            # stack[-n - 1] of a shorter stack
        mov rdx, [rdi + VEC_DATA]
        lea rdx, [rdx + rcx*8 - 8]      # the top
        sub rcx, rax
        dec rcx                         # (its index: stack_cleanup starts there at most)
        cmp [rbx + VM_CLEAN], rcx
        jbe 1f
        mov [rbx + VM_CLEAN], rcx
1:      neg rax
        mov rsi, [rdx]
        mov rdi, [rdx + rax*8]
        mov [rdx], rdi
        mov [rdx + rax*8], rsi
        jmp .Lstep_cleanup

.Lop_stack_index:
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_stack_index]
        call err_throw

.Lop_mul:
        VPOP [rsp]
        VPOP rsi
        mov rdi, [rsp]
        call alg_mul2
        VPUSH rax
        jmp .Lstep_epilogue

.Lop_or:
        VPOP [rsp]
        VPOP rsi
        mov rdi, [rsp]
        call alg_or2
        VPUSH rax
        jmp .Lstep_epilogue

.Lop_add:
        VPOP [rsp]
        VPOP rsi
        mov rdi, [rsp]
        call alg_add2
        VPUSH rax
        jmp .Lstep_epilogue

.Lop_sub:
        VPOP [rsp]
        VPOP [rsp + 8]
        mov rdi, [rsp]
        call is_int
        test eax, eax
        jz 1f
        mov rdi, [rsp + 8]
        call is_int
        test eax, eax
        jz 1f
        mov rdi, [rsp]
        mov rsi, [rsp + 8]
        call arith_sub
        VPUSH rax
        jmp .Lstep_epilogue
1:      mov rdi, [rsp]
        mov rsi, [rsp + 8]
        call alg_sub_op
        VPUSH rax
        jmp .Lstep_epilogue

.Lop_mulmod:
        VPOP [rsp]
        VPOP [rsp + 8]
        VPOP rcx
        mov rdx, [rsp + 8]
        mov rsi, [rsp]
        LOADS rdi, MULMOD
        call mk4
        VPUSH rax
        jmp .Lstep_epilogue

.Lop_shl:
        VPOP [rsp]                       # off
        VPOP [rsp + 8]                   # exp
        call .Lboth_int
        test eax, eax
        jz 1f
        mov rdi, [rsp + 8]
        mov rsi, [rsp]
        call int_shl
        VPUSH rax
        jmp .Lstep_epilogue
1:      # mask_op(exp, shl=off)
        mov rdi, [rsp + 8]
        mov esi, (256 << 1) | 1
        mov edx, 1
        mov rcx, [rsp]
        mov r8d, 1
        call alg_mask_op
        VPUSH rax
        jmp .Lstep_epilogue

.Lop_shr:
        VPOP [rsp]                       # off
        VPOP [rsp + 8]                   # exp
        call .Lboth_int
        test eax, eax
        jz .Lshr_symbolic
        mov rdi, [rsp + 8]
        mov rsi, [rsp]
        call int_shr
        VPUSH rax
        jmp .Lstep_epilogue
.Lshr_symbolic:
        # mask_op(exp, offset=minus_op(off), shr=off)
        mov rdi, [rsp]
        call alg_minus_op
        mov rdx, rax
        mov rdi, [rsp + 8]
        mov esi, (256 << 1) | 1
        mov ecx, 1
        mov r8, [rsp]
        call alg_mask_op
        VPUSH rax
        jmp .Lstep_epilogue

.Lop_sar:
        VPOP [rsp]                       # off
        VPOP [rsp + 8]                   # exp
        call .Lboth_int
        test eax, eax
        jz .Lshr_symbolic               # FIXME (as in python): not the right result
        mov rdi, [rsp + 8]
        mov rsi, [rsp]
        call int_sar
        VPUSH rax
        jmp .Lstep_epilogue

# not, iszero, extcodesize, extcodehash, blockhash: (op, x)
.Lop_unary:
        VPOP rsi
        mov rdi, r13
        call mk2
        VPUSH rax
        jmp .Lstep_epilogue

.Lop_sha3:
        VPOP [rsp]
        VPOP rsi
        mov rdi, [rsp]
        call mk_mem_range
        mov rsi, rax
        LOADS rdi, SHA3
        call mk2
        mov [rsp], rax
        call vm_new_var_name
        mov [rsp + 8], rax
        mov rsi, rax
        mov rdx, [rsp]
        LOADS rdi, SETVAR
        call mk3
        VTRACE rax
        mov rsi, [rsp + 8]
        LOADS rdi, VAR
        call mk2
        VPUSH rax
        jmp .Lstep_epilogue

.Lop_calldataload:
        VPOP rsi
        LOADS rdi, CD
        call mk2
        VPUSH rax
        jmp .Lstep_epilogue

# byte i of x, the most significant first: mask_op(x, 8, 248 - 8 i, shr=248 - 8 i)
.Lop_byte:
        VPOP [rsp]                       # i
        VPOP [rsp + 8]                   # x
        mov edi, (8 << 1) | 1
        mov rsi, [rsp]
        call alg_mul2
        mov rsi, rax
        mov edi, (248 << 1) | 1
        call alg_sub_op
        mov [rsp], rax
        mov rdi, [rsp + 8]
        mov esi, (8 << 1) | 1
        mov rdx, rax
        mov ecx, 1
        mov r8, rax
        call alg_mask_op
        VPUSH rax
        jmp .Lstep_epilogue

.Lop_selfbalance:
        LOADS rsi, ADDRESS
        LOADS rdi, BALANCE
        call mk2
        VPUSH rax
        jmp .Lstep_epilogue

.Lop_balance:
        VPOP [rsp]
        mov rdi, [rsp]
        call is_tuple
        test eax, eax
        jz 1f
        mov rax, [rsp]
        cmp dword ptr [rax + N_AUX], 5
        jne 1f
        mov rdi, rax
        call opcode_of
        cmp eax, OP_MASK_SHL
        jne 1f
        mov rax, [rsp]
        cmp qword ptr [rax + N_DATA + 8], (160 << 1) | 1
        jne 1f
        cmp qword ptr [rax + N_DATA + 16], 1
        jne 1f
        cmp qword ptr [rax + N_DATA + 24], 1
        jne 1f
        mov rax, [rax + N_DATA + 32]
        mov [rsp], rax
1:      mov rsi, [rsp]
        LOADS rdi, BALANCE
        call mk2
        VPUSH rax
        jmp .Lstep_epilogue

.Lop_log:
        VPOP [rsp]                       # p
        VPOP rsi                         # s
        mov rdi, [rsp]
        call mk_mem_range
        mov [rsp], rax
        call vec_new
        mov [rsp + 8], rax
        mov rdi, rax
        LOADS rsi, LOG
        call vec_push
        mov rdi, [rsp + 8]
        mov rsi, [rsp]
        call vec_push
        movzx eax, byte ptr [r12 + IN_OP]
        sub eax, 0xa0
        mov [rsp + 16], rax             # the number of topics
1:      cmp qword ptr [rsp + 16], 0
        je 2f
        dec qword ptr [rsp + 16]
        VPOP rsi
        mov rdi, [rsp + 8]
        call vec_push
        jmp 1b
2:      mov rdi, [rsp + 8]
        call vec_to_tuple
        VTRACE rax
        jmp .Lstep_epilogue

.Lop_sload:
        VPOP rcx
        LOADS rdi, STORAGE
        mov esi, (256 << 1) | 1
        mov edx, 1
        call mk4
        VPUSH rax
        jmp .Lstep_epilogue

.Lop_sstore:
        mov rdi, [rbx + VM_KNOWN]
        call forget_storage
        mov [rbx + VM_KNOWN], rax
        VPOP [rsp]                       # sloc
        VPOP r8                          # val
        mov rcx, [rsp]
        LOADS rdi, STORE
        mov esi, (256 << 1) | 1
        mov edx, 1
        call mk5
        VTRACE rax
        jmp .Lstep_epilogue

.Lop_mload:
        VPOP rdi
        mov esi, (32 << 1) | 1
        call mk_mem_range
        mov [rsp], rax
        call vm_new_var_name
        mov [rsp + 8], rax
        mov rsi, rax
        mov rdx, [rsp]
        LOADS rdi, SETVAR
        call mk3
        VTRACE rax
        mov rsi, [rsp + 8]
        LOADS rdi, VAR
        call mk2
        VPUSH rax
        jmp .Lstep_epilogue

.Lop_mstore:
        mov qword ptr [rsp + 16], (32 << 1) | 1
        jmp 1f
.Lop_mstore8:
        mov qword ptr [rsp + 16], (8 << 1) | 1
1:      VPOP rdi                         # memloc
        mov rsi, [rsp + 16]
        call mk_range
        mov [rsp], rax
        VPOP rdx                         # val
        mov rsi, [rsp]
        LOADS rdi, SETMEM
        call mk3
        VTRACE rax
        jmp .Lstep_epilogue

.Lop_extcodecopy:
        VPOP [rsp]                       # addr
        VPOP [rsp + 8]                   # mem_pos
        VPOP [rsp + 16]                  # code_pos
        VPOP [rsp + 24]                  # data_len
        mov rdi, [rsp + 16]
        mov rsi, [rsp + 24]
        call mk_range
        mov rdx, rax
        mov rsi, [rsp]
        LOADS rdi, EXTCODECOPY
        call mk3
        mov [rsp], rax
        mov rdi, [rsp + 8]
        mov rsi, [rsp + 24]
        call mk_range
        mov rsi, rax
        mov rdx, [rsp]
        LOADS rdi, SETMEM
        call mk3
        VTRACE rax
        jmp .Lstep_epilogue

.Lop_codecopy:
        VPOP [rsp]                       # mem_pos
        VPOP [rsp + 8]                   # call_pos
        VPOP [rsp + 16]                  # data_len
        mov rdi, [rsp + 8]
        mov rsi, [rsp + 16]
        call code_bytes_value
        test rax, rax
        jnz 1f
        # ('code.data', call_pos, data_len)
        mov rsi, [rsp + 8]
        mov rdx, [rsp + 16]
        LOADS rdi, CODE_DATA
        call mk3
1:      mov [rsp + 24], rax
        mov rdi, [rsp]
        mov rsi, [rsp + 16]
        call mk_range
        mov rsi, rax
        mov rdx, [rsp + 24]
        LOADS rdi, SETMEM
        call mk3
        VTRACE rax
        jmp .Lstep_epilogue

.Lop_codesize:
        mov rax, [rbx + VM_LOADER]
        mov rdi, [rax + LD_CODELEN]
        TAG rdi
        VPUSH rdi
        jmp .Lstep_epilogue

.Lop_calldatacopy:
        LOADS rax, CALL_DATA
        mov [rsp + 32], rax
        jmp .Lcopy_data
.Lop_returndatacopy:
        LOADS rax, EXT_CALL_RETURN_DATA
        mov [rsp + 32], rax
.Lcopy_data:
        VPOP [rsp]                       # mem_pos
        VPOP [rsp + 8]                   # src_pos
        VPOP [rsp + 16]                  # data_len
        cmp qword ptr [rsp + 16], 1     # data_len != 0
        je .Lstep_epilogue
        mov rdi, [rsp + 32]
        mov rsi, [rsp + 8]
        mov rdx, [rsp + 16]
        call mk3
        mov [rsp + 24], rax
        mov rdi, [rsp]
        mov rsi, [rsp + 16]
        call mk_range
        mov rsi, rax
        mov rdx, [rsp + 24]
        LOADS rdi, SETMEM
        call mk3
        VTRACE rax
        jmp .Lstep_epilogue

.Lop_call:
        mov rdi, [rbx + VM_KNOWN]
        call forget_volatile
        mov [rbx + VM_KNOWN], rax
        call vm_handle_call
        jmp .Lstep_epilogue

.Lop_delegatecall:
        mov rdi, [rbx + VM_KNOWN]
        call forget_volatile
        mov [rbx + VM_KNOWN], rax
        VPOP [rsp]                       # gas
        VPOP [rsp + 8]                   # addr
        mov qword ptr [rsp + 16], 0     # (no value)
        VPOP [rsp + 24]                  # arg_start
        VPOP [rsp + 32]                  # arg_len
        VPOP [rsp + 40]                  # ret_start
        VPOP [rsp + 48]                  # ret_len
        mov edi, 1
        call call_fname_params          # -> [rsp + 56], [rsp + 64]
        mov r8, [rsp + 64]
        mov rcx, [rsp + 56]
        mov rdx, [rsp + 8]
        mov rsi, [rsp]
        LOADS rdi, DELEGATECALL
        call mk5
        VTRACE rax
        LOADS rdi, DELEGATE_RETURN_CODE
        VPUSH rdi
        LOADS rax, DELEGATE_RETURN_DATA
        mov [rsp + 32], rax
        jmp .Lcall_return_data

.Lop_callcode:
        mov rdi, [rbx + VM_KNOWN]
        call forget_volatile
        mov [rbx + VM_KNOWN], rax
        VPOP [rsp]                       # gas
        VPOP [rsp + 8]                   # addr
        VPOP [rsp + 16]                  # value
        VPOP [rsp + 24]                  # arg_start
        VPOP [rsp + 32]                  # arg_len
        VPOP [rsp + 40]                  # ret_start
        VPOP [rsp + 48]                  # ret_len
        mov edi, 1
        call call_fname_params
        mov r9, [rsp + 64]
        mov r8, [rsp + 56]
        mov rcx, [rsp + 16]
        mov rdx, [rsp + 8]
        mov rsi, [rsp]
        LOADS rdi, CALLCODE
        call mk6
        VTRACE rax
        LOADS rdi, CALLCODE_RETURN_CODE
        VPUSH rdi
        LOADS rax, CALLCODE_RETURN_DATA
        mov [rsp + 32], rax
.Lcall_return_data:
        # if 0 != ret_len: setmem(range(ret_start, ret_len), (X.return_data, 0, ret_len))
        cmp qword ptr [rsp + 48], 1
        je .Lstep_epilogue
        mov rdi, [rsp + 32]
        mov esi, 1
        mov rdx, [rsp + 48]
        call mk3
        mov [rsp + 56], rax
        mov rdi, [rsp + 40]
        mov rsi, [rsp + 48]
        call mk_range
        mov rsi, rax
        mov rdx, [rsp + 56]
        LOADS rdi, SETMEM
        call mk3
        VTRACE rax
        jmp .Lstep_epilogue

.Lop_create:
        mov rdi, [rbx + VM_KNOWN]
        call forget_volatile
        mov [rbx + VM_KNOWN], rax
        VPOP [rsp]                       # wei
        VPOP [rsp + 8]                   # mem_start
        VPOP rsi                         # mem_len
        mov rdi, [rsp + 8]
        call mk_mem_range
        mov rdx, rax
        mov rsi, [rsp]
        LOADS rdi, CREATE
        call mk3
        VTRACE rax
        LOADS rdi, CREATE_NEW_ADDRESS
        VPUSH rdi
        jmp .Lstep_epilogue

.Lop_create2:
        mov rdi, [rbx + VM_KNOWN]
        call forget_volatile
        mov [rbx + VM_KNOWN], rax
        VPOP [rsp]                       # wei
        VPOP [rsp + 8]                   # mem_start
        VPOP rsi                         # mem_len
        mov rdi, [rsp + 8]
        call mk_mem_range
        mov [rsp + 8], rax
        VPOP rcx                         # salt
        mov rdx, [rsp + 8]
        mov rsi, [rsp]
        LOADS rdi, CREATE2
        call mk4
        VTRACE rax
        LOADS rdi, CREATE2_NEW_ADDRESS
        VPUSH rdi
        jmp .Lstep_epilogue

.Lop_pc:
        mov edi, [r12 + IN_PC]
        TAG rdi
        VPUSH rdi
        jmp .Lstep_epilogue

.Lop_msize:
        call vm_new_var_name
        mov [rsp], rax
        mov rsi, rax
        LOADS rdx, MSIZE
        LOADS rdi, SETVAR
        call mk3
        VTRACE rax
        mov rsi, [rsp]
        LOADS rdi, VAR
        call mk2
        VPUSH rax
        jmp .Lstep_epilogue

# callvalue, caller, address, number, gas, origin, timestamp, chainid,
# difficulty, gasprice, coinbase, gaslimit, calldatasize, returndatasize,
# basefee: the name itself
.Lop_env:
        VPUSH r13
        jmp .Lstep_epilogue

# --- the ones that end the trace ---

.Lop_jumpdest:
        # a new node stands for what follows
        mov rdi, [rbx + VM_STACK]
        call vec_to_tuple
        mov rdx, rax
        mov edi, [r12 + IN_PC]
        TAG rdi
        xor esi, esi
        mov rcx, [rsp + 72]
        mov r8, [rbx + VM_KNOWN]
        call node_new
        mov rsi, rax
        LOADS rdi, JUMP
        call mk2
        VTRACE rax
        jmp .Lstep_finished

.Lop_jump:
        VPOP [rsp]                       # target
        mov rdi, [rbx + VM_STACK]
        call vec_to_tuple
        mov rdx, rax
        mov rdi, [rsp]
        xor esi, esi
        mov rcx, [rsp + 72]
        mov r8, [rbx + VM_KNOWN]
        call node_new
        mov rsi, rax
        LOADS rdi, JUMP
        call mk2
        VTRACE rax
        jmp .Lstep_finished

.Lop_jumpi:
        VPOP [rsp]                       # target
        VPOP rdi
        call simplify_bool
        mov [rsp + 8], rax              # if_condition
        mov rdi, [rbx + VM_STACK]
        call vec_to_tuple
        mov [rsp + 16], rax             # tuple_stack
        # n_true = Node(target, safe=False, stack, cond, known + (cond,))
        mov rdi, [rbx + VM_KNOWN]
        mov rsi, [rsp + 8]
        call tuple_append
        mov r8, rax
        mov rdi, [rsp]
        xor esi, esi
        mov rdx, [rsp + 16]
        mov rcx, [rsp + 8]
        call node_new
        mov [rsp + 24], rax             # n_true
        # n_false = Node(next_line(i), safe=True, stack, is_zero(cond), known + (is_zero(cond),))
        mov rdi, [rsp + 8]
        call is_zero
        mov [rsp + 32], rax
        mov rdi, [rbx + VM_KNOWN]
        mov rsi, rax
        call tuple_append
        mov r8, rax
        mov rdi, [rbx + VM_LOADER]
        mov esi, [r12 + IN_PC]
        call loader_next_line
        mov rdi, rax
        TAG rdi
        mov esi, 1
        mov rdx, [rsp + 16]
        mov rcx, [rsp + 32]
        call node_new
        mov [rsp + 40], rax             # n_false
        cmp qword ptr [rbx + VM_JUST_FDESTS], 0
        je 1f
        call .Ljumpi_funccall
1:      # decided by the arithmetic, or by what's known on the path here?
        mov rdi, [rsp + 8]
        lea rsi, [rip + sp_true]        # (python's known_true=True)
        xor edx, edx
        call eval_bool
        cmp eax, TRI_NONE
        jne 2f
        mov rdi, [rsp + 8]
        mov rsi, [rbx + VM_KNOWN]
        call is_known
        cmp eax, TRI_NONE
        je 3f
2:      mov rsi, [rsp + 40]
        cmp eax, TRI_TRUE
        cmovne rax, rsi
        mov rsi, [rsp + 24]
        cmove rax, rsi
        mov rsi, rax
        LOADS rdi, JUMP
        call mk2
        VTRACE rax
        jmp .Lstep_finished
3:      mov rcx, [rsp + 40]
        mov rdx, [rsp + 24]
        mov rsi, [rsp + 8]
        LOADS rdi, IF
        call mk4
        VTRACE rax
        jmp .Lstep_finished

# local: in the function discovery mode, a comparison of the selector
# ('cd', 0) with a constant means a function call: n_true.trace =
# [('funccall', fx_hash, target, tuple_stack)]. The caller's frame is at
# rsp + 32: target, if_condition, tuple_stack, n_true.
.Ljumpi_funccall:
        sub rsp, 24
        mov rdi, [rsp + 32 + 8]
        call opcode_of
        cmp eax, OP_EQ
        jne 9f
        mov rax, [rsp + 32 + 8]
        cmp dword ptr [rax + N_AUX], 3
        jne 9f
        # ('eq', fx_hash, is_cd) or ('eq', is_cd, fx_hash)
        mov rdi, [rax + N_DATA + 8]
        mov rsi, [rax + N_DATA + 16]
        call .Lis_selector_check
        test eax, eax
        jnz 8f
        mov rax, [rsp + 32 + 8]
        mov rdi, [rax + N_DATA + 16]
        mov rsi, [rax + N_DATA + 8]
        call .Lis_selector_check
        test eax, eax
        jz 9f
8:      mov [rsp], rdi                  # fx_hash
        call vec_new
        mov [rsp + 8], rax
        mov rcx, [rsp + 32 + 16]        # tuple_stack
        mov rdx, [rsp + 32]             # target
        mov rsi, [rsp]
        LOADS rdi, FUNCCALL
        call mk4
        mov rdi, [rsp + 8]
        mov rsi, rax
        call vec_push
        mov rax, [rsp + 32 + 24]        # n_true
        mov rcx, [rsp + 8]
        mov [rax + ND_TRACE], rcx
9:      add rsp, 24
        ret

# local: (fx_hash, is_cd) -> eax: fx_hash is an int and is_cd mentions
# ('cd', 0). rdi is preserved.
.Lis_selector_check:
        sub rsp, 24
        mov [rsp], rdi
        mov [rsp + 8], rsi
        call is_int
        test eax, eax
        jz 7f
        LOADS rdi, CD
        mov esi, 1
        call mk2
        mov rdi, [rsp + 8]
        mov rsi, rax
        call contains_value
7:      mov rdi, [rsp]
        add rsp, 24
        ret

.Lop_return:
        VPOP [rsp]                       # p
        VPOP rsi                         # n
        cmp rsi, 1
        jne 1f
        mov rdi, r13
        call mk2                        # (op, 0)
        VTRACE rax
        jmp .Lstep_finished
1:      mov rdi, [rsp]
        call mk_mem_range
        mov rsi, rax
        mov rdi, r13
        call mk2
        VTRACE rax
        jmp .Lstep_finished

.Lop_selfdestruct:
        VPOP rsi
        mov rdi, r13
        call mk2
        VTRACE rax
        jmp .Lstep_finished

.Lop_stop:
.Lop_invalid:
        mov rdi, r13
        call mk1
        VTRACE rax
        jmp .Lstep_finished

.Lop_unknown:
        LOADS rdi, INVALID
        call mk1
        VTRACE rax
        jmp .Lstep_finished

# --- the ends ---

.Lstep_epilogue:
        # Some arithmetic (e.g. the Newton iterations in mulDiv) makes
        # expressions grow exponentially, and the algebra with them. Give
        # the big ones a name, as is done for memory reads.
        mov rax, [rbx + VM_STACK]
        mov rcx, [rax + VEC_LEN]
        test rcx, rcx
        jz .Lstep_cleanup
        mov rax, [rax + VEC_DATA]
        mov rdi, [rax + rcx*8 - 8]
        mov [rsp], rdi
        call is_tuple
        test eax, eax
        jz .Lstep_cleanup
        mov rdi, [rsp]
        mov esi, MAX_EXP_SIZE
        call exp_size_over
        test eax, eax
        jz .Lstep_cleanup
        VPOP [rsp]
        call vm_new_var_name
        mov [rsp + 8], rax
        mov rsi, rax
        mov rdx, [rsp]
        LOADS rdi, SETVAR
        call mk3
        VTRACE rax
        mov rsi, [rsp + 8]
        LOADS rdi, VAR
        call mk2
        VPUSH rax
.Lstep_cleanup:
        mov rdi, [rbx + VM_STACK]
        mov rsi, [rbx + VM_CLEAN]
        call stack_cleanup_from
        mov [rbx + VM_CLEAN], rax
        xor eax, eax
        add rsp, 80
        LEAVE
.Lstep_finished:
        mov eax, 1
        add rsp, 80
        LEAVE

# local: are [rsp + 8] and [rsp + 16] (the caller's [rsp], [rsp + 8]) both ints?
.Lboth_int:
        sub rsp, 8
        mov rdi, [rsp + 16]
        call is_int
        test eax, eax
        jz 1f
        mov rdi, [rsp + 24]
        call is_int
1:      add rsp, 8
        ret
ENDF vm_step

# --- the lines of assembly (python's --verbose, --explain) ---

        .section .rodata
.Ls_asm_stack:  .asciz "       ["
.Ls_comma_sp:   .asciz ", "
.Ls_asm_close:  .asciz "]"
.Ls_rquote_sp:  .asciz " \342\200\235"         # " ”"
.Ls_rquote:     .asciz "\342\200\235"          # "”"
.Ls_dup:        .asciz "dup"
.Ls_swap:       .asciz "swap"
.Ls_fmt_close:  .asciz "Single '}' encountered in format string"
.Ls_fmt_open:   .asciz "Single '{' encountered in format string"
.Ls_fmt_field:  .asciz "Replacement index 0 out of range for positional args tuple"
        .text

# vm_trace_asm(instr): python's lines of assembly, put in the trace before
# an instruction runs. With "--verbose" or "--explain" (VB_ASM), those of
# apply_stack: the stack (`C.asm("       " + str(stack))`, which python
# passes through str.format), an empty line, and "[pc] op" - with the
# parameter of a push, dup or swap. With "--explain" (VB_EXPLAIN) also
# those of handle_jumps, for the instructions a node ends with: the stack,
# an empty line, "[pc] op". None for a jumpdest nor an unknown opcode.
FUNC vm_trace_asm
        ENTER
        mov rbx, [r15 + CTX_VM]
        mov r12, rdi
        movzx r13d, byte ptr [r12 + IN_OP]
        lea rax, [rip + evm_op_nodes]
        cmp qword ptr [rax + r13*8], 0
        je .Lta_done                    # UNKNOWN: handle_jumps' invalid
        cmp r13d, 0x5b
        je .Lta_done                    # jumpdest: where a node begins
        # handle_jumps': stop, jump, jumpi, return, revert, invalid, selfdestruct
        test r13d, r13d
        jz .Lta_jumps
        cmp r13d, 0x56
        je .Lta_jumps
        cmp r13d, 0x57
        je .Lta_jumps
        cmp r13d, 0xf3
        je .Lta_jumps
        cmp r13d, 0xfd
        jae .Lta_jumps
        test qword ptr [r15 + CTX_VERBOSE], VB_ASM
        jz .Lta_done
        mov edi, 1                      # (through str.format)
        call .Lta_stack_line
        call .Lta_empty_line
        call .Lta_op_start
        cmp r13d, 0x5f
        jb .Lta_op_end                  # (no parameter)
        cmp r13d, 0x9f
        ja .Lta_op_end
        # " " + C.asm(the parameter)
        mov rdi, r14
        mov esi, ' '
        call sb_append_char
        mov rdi, r14
        lea rsi, [rip + C_ASM]
        call sb_append_c
        mov rsi, [r12 + IN_PARAM]
        cmp r13d, 0x80
        jae 2f                          # dup n, swap n: str(n)
        test sil, 1
        jz 1f
        mov rax, rsi                    # a push: hex above 0x1000000000
        sar rax, 1
        mov rcx, 0x1000000000
        cmp rax, rcx
        jg 3f
2:      mov rdi, r14
        mov edx, 10
        call sb_append_int
        jmp 4f
1:      cmp dword ptr [rsi + N_KIND], K_STR
        jne 3f
        # a string (pretty_bignum's): " ”" + line[2] + "”"
        mov rdi, r14
        lea rsi, [rip + .Ls_rquote_sp]
        call sb_append_c
        mov rdi, r14
        mov rsi, [r12 + IN_PARAM]
        call sb_append_str
        mov rdi, r14
        lea rsi, [rip + .Ls_rquote]
        call sb_append_c
        jmp 4f
3:      mov rdi, r14
        mov rsi, [r12 + IN_PARAM]
        mov edx, 16
        call sb_append_int
4:      mov rdi, r14
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        jmp .Lta_op_end
.Lta_jumps:
        test qword ptr [r15 + CTX_VERBOSE], VB_EXPLAIN
        jz .Lta_done
        xor edi, edi                    # (appended as it is)
        call .Lta_stack_line
        call .Lta_empty_line
        call .Lta_op_start
.Lta_op_end:
        call .Lta_push_sb
.Lta_done:
        LEAVE

# local: the scratch builder, emptied -> rax and r14
.Lta_sb:
        sub rsp, 8
        mov rax, [r15 + CTX_ASM_SB]
        test rax, rax
        jnz 1f
        call sb_new
        mov [r15 + CTX_ASM_SB], rax
1:      mov r14, rax
        mov rdi, rax
        call sb_reset
        mov rax, r14
        add rsp, 8
        ret
# local: the builder's text, interned, added to the trace
.Lta_push_sb:
        sub rsp, 8
        mov rdi, [r14 + SB_BUF]
        mov rsi, [r14 + SB_LEN]
        call str_intern
        mov rdi, [rbx + VM_TRACE]
        mov rsi, rax
        call vec_push
        add rsp, 8
        ret
# local: "", added to the trace
.Lta_empty_line:
        sub rsp, 8
        call .Lta_sb
        call .Lta_push_sb
        add rsp, 8
        ret
# local: C.asm("       " + str(stack)) - str.format'ed when edi is 1
.Lta_stack_line:
        push rdi
        call .Lta_sb
        mov rdi, r14
        lea rsi, [rip + C_ASM]
        call sb_append_c
        mov rdi, r14
        lea rsi, [rip + .Ls_asm_stack]
        call sb_append_c
        xor r13d, r13d                  # (the opcode is reloaded below)
1:      mov rax, [rbx + VM_STACK]
        cmp r13, [rax + VEC_LEN]
        jae 2f
        test r13, r13
        jz 3f
        mov rdi, r14
        lea rsi, [rip + .Ls_comma_sp]
        call sb_append_c
3:      mov rax, [rbx + VM_STACK]
        mov rax, [rax + VEC_DATA]
        mov rsi, [rax + r13*8]
        mov rdi, r14
        xor edx, edx                    # prettify(el, parentheses=False)
        call sb_append_pret
        inc r13
        jmp 1b
2:      mov rdi, r14
        lea rsi, [rip + .Ls_asm_close]
        call sb_append_c
        mov rdi, r14
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        movzx r13d, byte ptr [r12 + IN_OP]
        cmp qword ptr [rsp], 0
        je 4f
        mov rdi, r14
        call fmt_noargs
4:      pop rdi
        jmp .Lta_push_sb
# local: "[pc] " + C.asm(op) in the builder (r14)
.Lta_op_start:
        sub rsp, 8
        call .Lta_sb
        mov rdi, r14
        mov esi, '['
        call sb_append_char
        mov rdi, r14
        mov esi, [r12 + IN_PC]
        call sb_append_u64
        mov rdi, r14
        mov esi, ']'
        call sb_append_char
        mov rdi, r14
        mov esi, ' '
        call sb_append_char
        mov rdi, r14
        lea rsi, [rip + C_ASM]
        call sb_append_c
        lea rsi, [rip + .Ls_dup]        # (python's names: dup n, swap n)
        cmp r13d, 0x80
        jb 1f
        cmp r13d, 0x8f
        jbe 2f
        lea rsi, [rip + .Ls_swap]
        cmp r13d, 0x9f
        jbe 2f
1:      lea rax, [rip + evm_op_nodes]
        mov rsi, [rax + r13*8]
        mov rdi, r14
        call sb_append_str
        jmp 3f
2:      mov rdi, r14
        call sb_append_c
3:      mov rdi, r14
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        add rsp, 8
        ret
ENDF vm_trace_asm

# fmt_noargs(sb): python's text.format() with no arguments, in place: "{{"
# and "}}" become "{" and "}", a lone brace or a replacement field (which
# would want an argument) raise (ValueError, IndexError: E_VALUE here)
FUNC fmt_noargs
        mov rsi, [rdi + SB_BUF]
        mov rcx, [rdi + SB_LEN]
        xor eax, eax
1:      cmp rax, rcx                    # (most have no brace at all)
        jae 9f
        movzx edx, byte ptr [rsi + rax]
        cmp dl, '{'
        je 2f
        cmp dl, '}'
        je 2f
        inc rax
        jmp 1b
2:      mov r8, rax                     # where the text goes
3:      cmp rax, rcx
        jae 8f
        movzx edx, byte ptr [rsi + rax]
        cmp dl, '{'
        je 4f
        cmp dl, '}'
        je 5f
        mov [rsi + r8], dl
        inc rax
        inc r8
        jmp 3b
4:      lea r9, [rax + 1]
        cmp r9, rcx
        jae .Lfmt_open
        cmp byte ptr [rsi + r9], '{'
        jne .Lfmt_field
        jmp 6f
5:      lea r9, [rax + 1]
        cmp r9, rcx
        jae .Lfmt_close
        cmp byte ptr [rsi + r9], '}'
        jne .Lfmt_close
6:      mov [rsi + r8], dl
        inc r8
        add rax, 2
        jmp 3b
8:      mov [rdi + SB_LEN], r8
        mov byte ptr [rsi + r8], 0
9:      ret
.Lfmt_open:
        lea rsi, [rip + .Ls_fmt_open]
        jmp 7f
.Lfmt_close:
        lea rsi, [rip + .Ls_fmt_close]
        jmp 7f
.Lfmt_field:
        lea rsi, [rip + .Ls_fmt_field]
7:      sub rsp, 8
        mov edi, E_VALUE
        call err_throw
ENDF fmt_noargs

# call_fname_params(params4): the function name and parameters of a call
# from the caller's frame (arg_start at its [rsp + 24], arg_len at
# [rsp + 32]) into its [rsp + 56] and [rsp + 64]. params4 is the value of
# the parameters for a 4-byte call (the python version puts 0 there for
# delegatecall/callcode and None for call/staticcall).
FUNC call_fname_params
        push rbp
        mov rbp, rsp
        # the caller's frame: rbp + 16 is its rsp
        lea rax, [rbp + 16]
        mov rcx, [rax + 32]             # arg_len
        cmp rcx, 1                      # arg_len == 0
        jne 1f
        lea rcx, [rip + sp_none]
        mov [rax + 56], rcx
        mov [rax + 64], rcx
        pop rbp
        ret
1:      cmp rcx, (4 << 1) | 1           # arg_len == 4
        jne 2f
        push rdi
        push rdi
        mov rdi, [rax + 24]
        mov esi, (4 << 1) | 1
        call mk_mem_range
        pop rdi
        pop rdi
        lea rcx, [rbp + 16]
        mov [rcx + 56], rax
        mov [rcx + 64], rdi
        pop rbp
        ret
2:      mov rdi, [rax + 24]
        mov esi, (4 << 1) | 1
        call mk_mem_range
        lea rcx, [rbp + 16]
        mov [rcx + 56], rax
        # fparams = mem_load(add_op(arg_start, 4), sub_op(arg_len, 4))
        mov rdi, [rcx + 24]
        mov esi, (4 << 1) | 1
        call alg_add2
        push rax
        push rax
        lea rcx, [rbp + 16]
        mov rdi, [rcx + 32]
        mov esi, (4 << 1) | 1
        call alg_sub_op
        mov rsi, rax
        pop rdi
        pop rdi
        call mk_mem_range
        lea rcx, [rbp + 16]
        mov [rcx + 64], rax
        pop rbp
        ret
ENDF call_fname_params

# vm_handle_call(): call / staticcall (rbx = vm, r12 = instr, r13 = op)
FUNC vm_handle_call
        ENTER
        sub rsp, 80
        VPOP [rsp]                       # gas
        VPOP [rsp + 8]                   # addr
        mov qword ptr [rsp + 16], 1     # wei = 0 for a staticcall
        cmp byte ptr [r12 + IN_OP], 0xf1
        jne 1f
        VPOP [rsp + 16]                  # wei
1:      VPOP [rsp + 24]                  # arg_start
        VPOP [rsp + 32]                  # arg_len
        VPOP [rsp + 40]                  # ret_start
        VPOP [rsp + 48]                  # ret_len
        mov rax, [rsp + 8]
        cmp rax, (4 << 1) | 1
        je .Lhc_identity
        test al, 1
        jz .Lhc_call
        sar rax, 1
        cmp rax, 1
        jb .Lhc_call
        cmp rax, 8
        ja .Lhc_call
        shl rax, 4
        lea rcx, [rip + precompiled_names]
        cmp qword ptr [rcx + rax], 0
        je .Lhc_call
        # a precompiled contract: ('precompiled', var_name, name, args);
        # setmem(range(ret_start, ret_len), ('var', var_name)); push name.result
        mov [rsp + 56], rax
        mov rdi, [rcx + rax + 8]
        call str_intern_c
        mov [rsp + 64], rax             # var_name
        mov rax, [rsp + 56]
        lea rcx, [rip + precompiled_names]
        mov rdi, [rcx + rax]
        call str_intern_c
        mov [rsp + 72], rax             # name
        mov rdi, [rsp + 24]
        mov rsi, [rsp + 32]
        call mk_mem_range
        mov rcx, rax
        mov rdx, [rsp + 72]
        mov rsi, [rsp + 64]
        LOADS rdi, PRECOMPILED
        call mk4
        VTRACE rax
        mov rsi, [rsp + 64]
        LOADS rdi, VAR
        call mk2
        mov [rsp + 56], rax
        mov rdi, [rsp + 40]
        mov rsi, [rsp + 48]
        call mk_range
        mov rsi, rax
        mov rdx, [rsp + 56]
        LOADS rdi, SETMEM
        call mk3
        VTRACE rax
        # "{}.result"
        mov rax, [rsp + 72]
        lea rcx, [rax + N_DATA + 4]
        lea rdi, [rsp + 56]
        mov esi, 24
        lea rdx, [rip + .Ls_result_fmt]
        xor eax, eax
        call snprintf@PLT
        lea rdi, [rsp + 56]
        call str_intern_c
        VPUSH rax
        add rsp, 80
        LEAVE
.Lhc_identity:
        # memory copy: setmem(range(ret_start, arg_len), mem(arg_start, arg_len))
        mov rdi, [rsp + 24]
        mov rsi, [rsp + 32]
        call mk_mem_range
        mov [rsp + 56], rax
        mov rdi, [rsp + 40]
        mov rsi, [rsp + 32]
        call mk_range
        mov rsi, rax
        mov rdx, [rsp + 56]
        LOADS rdi, SETMEM
        call mk3
        VTRACE rax
        LOADS rdi, MEMCOPY_SUCCESS
        VPUSH rdi
        add rsp, 80
        LEAVE
.Lhc_call:
        # (op, gas, addr, wei, fname, fparams)
        lea rdi, [rip + sp_none]
        call call_fname_params
        mov r9, [rsp + 64]
        mov r8, [rsp + 56]
        mov rcx, [rsp + 16]
        mov rdx, [rsp + 8]
        mov rsi, [rsp]
        mov rdi, r13
        call mk6
        VTRACE rax
        LOADS rdi, EXT_CALL_SUCCESS
        VPUSH rdi
        # the return data, when there is some (or when we can't tell)
        mov edi, 1
        mov rsi, [rsp + 48]
        call alg_lt_op
        cmp eax, TRI_FALSE
        je 2f
        mov esi, 1
        mov rdx, [rsp + 48]
        LOADS rdi, EXT_CALL_RETURN_DATA
        call mk3
        mov [rsp + 56], rax
        mov rdi, [rsp + 40]
        mov rsi, [rsp + 48]
        call mk_range
        mov rsi, rax
        mov rdx, [rsp + 56]
        LOADS rdi, SETMEM
        call mk3
        VTRACE rax
2:      add rsp, 80
        LEAVE
ENDF vm_handle_call

# --- helpers ---

# arith_sub(a, b) -> (a - b) mod 2^256 (arithmetic.sub)
FUNC arith_sub
        ENTER
        call int_sub
        mov rdi, rax
        mov esi, 256
        call int_mod_2exp
        LEAVE
ENDF arith_sub

# int_shl(x, k) / int_shr(x, k) -> value: python's x << k, x >> k for
# non-negative x and k (the results are reduced to 256 bits by the push)
FUNC int_shl
        ENTER
        mov rbx, rdi
        mov rdi, rsi
        call int_to_i64
        cmp rax, 256
        jae .Lshift_zero
        mov r12, rax
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, rbx
        call value_set_mpz
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, rdi
        mov rdx, r12
        call __gmpz_mul_2exp@PLT
        call arith_wrap_r
        call arith_result
        LEAVE
.Lshift_zero:
        mov eax, 1
        LEAVE
ENDF int_shl

FUNC int_shr
        ENTER
        mov rbx, rdi
        mov rdi, rsi
        call int_to_i64
        cmp rax, 256
        jae .Lshift_zero
        mov r12, rax
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, rbx
        call value_set_mpz
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, rdi
        mov rdx, r12
        call __gmpz_fdiv_q_2exp@PLT
        call arith_result
        LEAVE
ENDF int_shr

# int_sar(x, k) -> value: arithmetic shift right of the 256-bit x
FUNC int_sar
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov esi, 255
        call int_tstbit
        mov r13d, eax                   # the sign
        mov rdi, r12
        call int_to_i64
        cmp rax, 256
        jb 1f
        test r13d, r13d
        jz .Lshift_zero
        # all ones
        lea rdi, [r15 + CTX_MPZ_R]
        mov esi, 1
        call __gmpz_set_ui@PLT
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, rdi
        mov edx, 256
        call __gmpz_mul_2exp@PLT
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, rdi
        mov edx, 1
        call __gmpz_sub_ui@PLT
        call arith_result
        LEAVE
1:      mov r12, rax
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, rbx
        call value_set_mpz
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, rdi
        mov rdx, r12
        call __gmpz_fdiv_q_2exp@PLT
        test r13d, r13d
        jz 2f
        # shifted |= (2^256 - 1) << (256 - k): set the bits 256-k .. 255
        mov r14d, 256
        sub r14, r12
3:      cmp r14, 256
        jae 2f
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, r14
        call __gmpz_setbit@PLT
        inc r14
        jmp 3b
2:      call arith_result
        LEAVE
ENDF int_sar

# code_bytes_value(pos, len) -> rax: the bytes of the code at pos as an
# integer, when both are ints and in range, else 0. (As in python:
# starting one byte early, which is probably a bug there but is what the
# output shows.)
FUNC code_bytes_value
        ENTER
        sub rsp, 16
        test dil, 1
        jz .Lcb_no
        test sil, 1
        jz .Lcb_no
        sar rdi, 1
        sar rsi, 1
        mov rbx, rdi                    # pos
        mov r12, rsi                    # len
        mov rax, [r15 + CTX_VM]
        mov r13, [rax + VM_LOADER]
        lea rax, [rbx + r12]
        cmp rax, [r13 + LD_CODELEN]
        jae .Lcb_no
        test rbx, rbx
        js .Lcb_no
        test r12, r12
        js .Lcb_no
        # the bytes pos-1 .. pos+len-2, the first being the last byte of
        # the code when pos is 0 (python's negative index)
        lea rdi, [r12 + 1]
        call xmalloc
        mov r14, rax
        mov rdi, r14
        mov rsi, [r13 + LD_CODE]
        lea rsi, [rsi + rbx - 1]
        mov rdx, r12
        test rbx, rbx
        jnz 1f
        mov rcx, [r13 + LD_CODE]
        mov rax, [r13 + LD_CODELEN]
        mov al, [rcx + rax - 1]
        mov [r14], al
        inc rdi
        inc rsi
        dec rdx
1:      call memcpy@PLT
        mov rdi, r14
        mov rsi, r12
        call mk_int_bytes_be
        mov [rsp], rax
        mov rdi, r14
        call free@PLT
        mov rax, [rsp]
        add rsp, 16
        LEAVE
.Lcb_no:
        xor eax, eax
        add rsp, 16
        LEAVE
ENDF code_bytes_value

# exp_size_over(exp, limit) -> eax: more than `limit` leaves in the
# expression (python's exp_size(exp) > limit, without counting them all)
FUNC exp_size_over
        ENTER
        mov rbx, rsi                    # the budget
        mov r13, rdi
        call vec_new
        mov r12, rax                    # what's left to count
        mov rdi, r12
        mov rsi, r13
        call vec_push
        xor r14d, r14d                  # leaves seen
1:      mov rdi, r12
        call vec_pop
        test rax, rax
        jz 3f
        mov r13, rax
        mov rdi, rax
        call is_tuple
        test eax, eax
        jnz 2f
        inc r14
        cmp r14, rbx
        ja 4f
        jmp 1b
2:      mov rdi, r12
        lea rsi, [r13 + N_DATA]
        mov edx, [r13 + N_AUX]
        call vec_extend
        jmp 1b
3:      xor eax, eax
        LEAVE
4:      mov eax, 1
        LEAVE
ENDF exp_size_over

        .section .note.GNU-stack,"",@progbits
