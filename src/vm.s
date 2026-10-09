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
.Ls_jump:           .asciz "jump"
.Ls_stack_underflow: .asciz "stack underflow"
.Ls_safe:           .asciz "safe"
.Ls_storage:        .asciz "storage"
.Ls_var_fmt:        .asciz "_%lu"
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
        mov qword ptr [rax + VM_LOOP_KEY], 1    # (loop_key's next number)
        mov qword ptr [rax + VM_INTERNAL], 0
        mov qword ptr [rax + VM_FOUND], 0
        mov qword ptr [rax + VM_INSIDE], 0
        mov [r15 + CTX_VM], rax
        mov r12, rax
        # the context works on the loader's contract: the memory model's
        # free memory pointer is the loader's (vr_free_memory_pointer;
        # python's variants.FREE_MEMORY_POINTER, global, whose caches are
        # forgotten when it changes)
        call vr_free_memory_pointer
        mov r13d, eax
        mov [r15 + CTX_LOADER], rbx
        call vr_free_memory_pointer
        cmp eax, r13d
        je 1f
        call clear_caches
1:      mov rbx, r12
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

# vm_should_quit() -> eax: too many nodes (MAX_NODE_COUNT, or
# MAX_FDESTS_NODE_COUNT finding the functions; past WIDE_NODE_COUNT, the
# exploration goes on only while fewer than one node of 16 is still to
# explore - VM_FRONTIER, as last counted), or out of time
FUNC vm_should_quit
        ENTER
        mov rbx, [r15 + CTX_VM]
        mov rax, [rbx + VM_NODE_COUNT]
        cmp rax, [rbx + VM_MAX_NODES]
        ja 1f
        cmp rax, WIDE_NODE_COUNT
        jbe 3f
        mov rcx, [rbx + VM_FRONTIER]
        shl rcx, 4
        cmp rcx, rax
        ja 1f
3:      cmp qword ptr [rbx + VM_TIMEOUT], 0
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

# vm_name_past(stack, known, entry, memory): python's VM.name_past - the
# VM's own variables named past those in what it's given: a function's
# stack, what's known there and what runs before it come from the
# dispatcher, whose variables another VM named - the same name would be two
# variables. The next loop number (VM_LOOP_KEY: a loop's variables are
# 1000 * its number + a place on the stack), the counter of the _1, _2...
# names (VM_COUNTER), the counters of the precompiles' results (signer,
# signer2...: VM_PRECOMPILES)
FUNC vm_name_past
        ENTER
        sub rsp, 16
        .set NP_I, 0                    # the precompile looked at (1..8)
        .set NP_COUNT, 8                # its count, in the name
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov r14, rcx
        call vec_new
        mov rdi, rbx
        mov rbx, rax                    # the variables in them
        mov esi, OP_VAR
        mov rdx, rbx
        call find_op_list
        mov rdi, r12
        mov esi, OP_VAR
        mov rdx, rbx
        call find_op_list
        mov rdi, r13
        mov esi, OP_VAR
        mov rdx, rbx
        call find_op_list
        mov rdi, r14
        mov esi, OP_VAR
        mov rdx, rbx
        call find_op_list
        mov r14, [r15 + CTX_VM]
        xor r12d, r12d
1:      cmp r12, [rbx + VEC_LEN]
        jae 9f
        mov rax, [rbx + VEC_DATA]
        mov rax, [rax + r12*8]
        inc r12
        cmp dword ptr [rax + N_AUX], 2
        jne 1b
        mov rdi, [rax + N_DATA + 8]     # its name
        test dil, 1
        jz 3f
        # a loop's (see loop_key): name // 1000 + 1 (one below 0 isn't
        # past anything)
        sar rdi, 1
        js 1b
        mov rax, rdi
        xor edx, edx
        mov ecx, 1000
        div rcx
        inc rax
        cmp rax, [r14 + VM_LOOP_KEY]
        jbe 1b
        mov [r14 + VM_LOOP_KEY], rax
        jmp 1b
3:      test rdi, rdi
        jz 1b
        cmp dword ptr [rdi + N_KIND], K_STR
        jne 1b
        lea r13, [rdi + N_DATA + 4]     # its text
        cmp byte ptr [r13], '_'
        jne 4f
        # _1, _2...
        lea rdi, [r13 + 1]
        call vm_name_count
        test rax, rax
        jle 1b
        cmp rax, [r14 + VM_COUNTER]
        jbe 1b
        mov [r14 + VM_COUNTER], rax
        jmp 1b
4:      # a precompile's result: signer, signer2...
        mov qword ptr [rsp + NP_I], 0
5:      mov rcx, [rsp + NP_I]
        inc rcx
        cmp rcx, 8
        ja 1b
        mov [rsp + NP_I], rcx
        imul rax, rcx, 24
        lea rdx, [rip + precompiled_names]
        mov rsi, [rdx + rax + 8]        # the name of its result
        test rsi, rsi
        jz 5b
        mov rdi, r13
        call st_prefix
        test rax, rax
        js 5b
        lea rdi, [r13 + rax]
        mov qword ptr [rsp + NP_COUNT], 1       # the name itself: the first
        cmp byte ptr [rdi], 0
        je 6f
        call vm_name_count
        test rax, rax
        js 5b
        mov [rsp + NP_COUNT], rax
6:      imul rax, [rsp + NP_I], 24
        lea rdx, [rip + precompiled_names]
        mov rax, [rdx + rax + 16]       # its counter
        lea rsi, [r14 + VM_PRECOMPILES + rax*8]
        mov rdx, [rsp + NP_COUNT]
        cmp rdx, [rsi]
        jbe 5b
        mov [rsi], rdx
        jmp 5b
9:      add rsp, 16
        LEAVE
ENDF vm_name_past

# vm_name_count(p) -> rax: the number the ASCII digits at p (up to the NUL)
# make, -1 if there are none, or something else, or more than 18 of them
FUNC vm_name_count
        xor eax, eax
        xor edx, edx                    # how many
1:      movzx ecx, byte ptr [rdi + rdx]
        test ecx, ecx
        jz 3f
        sub ecx, '0'
        cmp ecx, 9
        ja 2f
        cmp edx, 18
        jae 2f
        imul rax, rax, 10
        add rax, rcx
        inc edx
        jmp 1b
2:      mov rax, -1
        ret
3:      test edx, edx
        jz 2b
        ret
ENDF vm_name_count

# vm_run(start, stack, known, timeout_ns, entry, memory) -> rax: the
# decompiled trace (a list) of the function starting at `start` with
# `stack` (a tuple), given the conditions `known` to hold there. entry:
# what runs before start (see loader.entry_paths), NIL when it isn't known
# (python's None: the free memory pointer is assumed to be 0x60 then, as
# the old compilers set it - if it's solidity's), the beginning of the
# trace; memory: what's known of the memory then (see entry_memory).
FUNC vm_run
        ENTER
        sub rsp, 64
        mov rbx, [r15 + CTX_VM]
        mov [rsp], rdi                  # start
        mov [rsp + 8], rsi              # stack
        mov [rsp + 16], rdx             # known
        mov [rbx + VM_TIMEOUT], rcx
        mov [rsp + 48], r8              # entry
        mov [rsp + 56], r9              # memory
        mov rdi, rsi
        mov rsi, rdx
        mov rdx, r8
        mov rcx, r9
        call vm_name_past
        call monotonic_ns
        mov [rbx + VM_TIME_START], rax
        mov qword ptr [rbx + VM_NODE_COUNT], 0
        mov qword ptr [rbx + VM_FRONTIER], 0
        mov eax, MAX_NODE_COUNT
        mov ecx, MAX_FDESTS_NODE_COUNT
        cmp qword ptr [rbx + VM_JUST_FDESTS], 0
        cmovne eax, ecx
        mov [rbx + VM_MAX_NODES], rax
        call vec_new
        mov r13, rax                    # the root's trace: before, then the jump
        cmp qword ptr [rbx + VM_INSIDE], 0      # (an internal function's: nothing
        jne 2f                                  # runs before, nothing's known)
        cmp qword ptr [rsp + 48], 0
        jne 1f
        # no entry: mem[64] = 0x60, if it's the free memory pointer
        call vr_free_memory_pointer
        test eax, eax
        jz 2f
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
        jmp 2f
1:      # what the entry says holds, a memory of zeroes where the run starts
        # at the beginning of the code, what's known of the memory, and no
        # data returned yet (the dispatcher makes no call: minimal proxies
        # use returndatasize as a cheap 0)
        mov rdi, [rsp + 48]
        call entry_known
        mov rdi, [rsp + 16]
        mov rsi, rax
        call tuple_concat
        mov [rsp + 16], rax
        cmp qword ptr [rsp], 1          # start == 0 and len(entry) == 0
        jne 3f
        mov rax, [rsp + 48]
        cmp dword ptr [rax + N_AUX], 0
        jne 3f
        LOADS rdi, MEMORY_FRESH
        call mk1
        mov rdi, [rsp + 16]
        mov rsi, rax
        call tuple_append
        mov [rsp + 16], rax
3:      mov r12, [rsp + 56]             # the memory facts not known yet
        xor r14d, r14d
4:      cmp r14d, [r12 + N_AUX]
        jae 6f
        mov rsi, [r12 + N_DATA + r14*8]
        inc r14d
        mov rax, [rsp + 16]
        xor ecx, ecx
5:      cmp ecx, [rax + N_AUX]
        jae 51f
        cmp [rax + N_DATA + rcx*8], rsi
        je 4b
        inc ecx
        jmp 5b
51:     mov rdi, rax
        call tuple_append
        mov [rsp + 16], rax
        jmp 4b
6:      LOADS rdi, RETURNDATASIZE_ZERO
        call mk1
        mov rdi, [rsp + 16]
        mov rsi, rax
        call tuple_append
        mov [rsp + 16], rax
2:      # func_node = Node(start, safe=True, stack, known)
        mov rdi, [rsp]
        mov esi, 1
        mov rdx, [rsp + 8]
        lea rcx, [rip + sp_true]
        mov r8, [rsp + 16]
        call node_new
        mov r12, rax
        # trace = before + [('jump', func_node, 'safe', ())]
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
        mov [rsp + 40], rax
        mov rdi, r14
        mov rsi, rax
        call vm_replace_loops
        # the calls of a function in its own call: not unrolled (vmrec.s)
        mov rdi, r14
        mov rsi, [rsp + 40]
        call vm_replace_recursions
        mov qword ptr [rsp + 40], 0
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
        mov rcx, [rax + VEC_LEN]
        mov [rbx + VM_FRONTIER], rcx
        test rcx, rcx
        jz .Linner_done
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
        # preceded by what runs before (a non-empty entry)
        mov rdi, [rsp + 48]
        test rdi, rdi
        jz 2f
        cmp dword ptr [rdi + N_AUX], 0
        je 2f
        mov rsi, rax
        call apply_entry
2:      add rsp, 64
        LEAVE
ENDF vm_run

# vm_run_function(loader, hash, target, stack, timeout_ns) -> rax: the
# trace of a function, as python's decompiler runs the VM for it (on this
# context's VM): known what no selector matched where the default function
# is all of the dispatcher (target 0), the entry of the function (what all
# the paths of the dispatcher to it have in common, see loader.entry) and
# what's known of the memory then (entry_memory of its entries). hash: the
# function's string, the loader's (imported here, with what goes with it).
FUNC vm_run_function
        ENTER
        sub rsp, 48
        mov rbx, rdi                    # loader
        mov [rsp], rsi                  # hash
        mov [rsp + 8], rdx              # target
        mov [rsp + 16], rcx             # stack
        mov [rsp + 24], r8              # timeout
        xor edi, edi
        xor esi, esi
        call mk_tuple
        mov r12, rax                    # known
        cmp qword ptr [rsp + 8], 1
        jne 1f
        mov rdi, [rsp]
        lea rsi, [rip + .Ls_fallback_name]
        call str_eq_c
        test eax, eax
        jz 1f
        mov rdi, [rbx + LD_FALLBACK_KNOWN]
        call value_import_root
        mov r12, rax
1:      xor r13d, r13d                  # entry: None
        mov rdi, rbx
        mov rsi, [rsp]
        call loader_entries
        test rax, rax
        jz 2f
        mov rdi, rax
        call value_import_root
        mov r14, rax                    # the entries
        mov rdi, rax
        call common_entry
        mov r13, rax
        mov rdi, r14
        call entry_memory
        jmp 3f
2:      xor edi, edi
        call entry_memory
3:      mov r9, rax
        mov r8, r13
        mov rdi, [rsp + 8]
        mov rsi, [rsp + 16]
        mov rdx, r12
        mov rcx, [rsp + 24]
        call vm_run
        add rsp, 48
        LEAVE
ENDF vm_run_function
        .section .rodata
.Ls_fallback_name: .asciz "_fallback"
        .text

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
# Finding the functions only (just_fdests), the dispatcher first: the
# nodes in_dispatcher, if any - a function's body with the nodes left once
# it's done (the default function's body, which takes the paths no
# selector matches, branches as it goes: explored with it, it took all of
# the nodes, and the functions past where the dispatcher was cut were left
# to the default function, as its ifs on the selector).
# Gives the unexpanded nodes after (what replace_loops' find_nodes would
# give): the unexpanded ones are leaves, found in the order of the leaves,
# and running one only gives it new nodes below (its children - unexpanded
# but for just_fdests' funccalls - and the cases of a switch below its
# ifs, see code_switch): they take its place in that order.
FUNC vm_expand_trace
        ENTER
        sub rsp, 32
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
        # just_fdests: the nodes of the dispatcher only, if there are some
        # (a byte per node: run it)
        mov rdi, [rbx + VEC_LEN]
        inc rdi
        call arena_alloc
        mov [rsp + 16], rax
        xor r12d, r12d
        mov qword ptr [rsp + 24], 0     # how many in the dispatcher
        mov rax, [r15 + CTX_VM]
        cmp qword ptr [rax + VM_JUST_FDESTS], 0
        je 11f
10:     cmp r12, [rbx + VEC_LEN]
        jae 12f
        mov rax, [rbx + VEC_DATA]
        mov rdi, [rax + r12*8]
        call in_dispatcher
        mov rcx, [rsp + 16]
        mov [rcx + r12], al
        add [rsp + 24], rax
        inc r12
        jmp 10b
12:     cmp qword ptr [rsp + 24], 0
        jne 13f
11:     mov rdi, [rsp + 16]             # all of them
        mov esi, 1
        mov rdx, [rbx + VEC_LEN]
        call memset@PLT
13:     xor r12d, r12d
        mov qword ptr [rsp + 24], 0     # 1: stopped (should_quit)
1:      cmp r12, [rbx + VEC_LEN]
        jae 2f
        mov rax, [rbx + VEC_DATA]
        mov rdi, [rax + r12*8]
        mov [rsp], rdi
        mov rcx, [rsp + 16]
        cmp byte ptr [rcx + r12], 0
        je 7f                           # not run: as it is
        cmp qword ptr [rsp + 24], 0
        jne 7f
        # symbolic execution of a single node can take very long when the
        # expressions get big, so the timeout is checked here too
        call vm_should_quit
        test eax, eax
        jz 6f
        mov qword ptr [rsp + 24], 1
        mov rdi, [rsp]
        jmp 7f
6:      mov rdi, [rsp]
        call node_run
        # the unexpanded nodes below it, in find_nodes' order
        mov rdi, [rsp]
        lea rsi, [rip + pred_unexpanded]
        xor edx, edx
        mov rcx, r14
        call find_nodes_into
        inc r12
        jmp 1b
7:      mov rsi, rdi
        mov rdi, r14
        call vec_push
        inc r12
        jmp 1b
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
        jne 8f
        mov rsi, [rax + VEC_DATA]
        mov rdi, [r14 + VEC_DATA]
4:      dec rcx
        js 5f
        mov rdx, [rsi + rcx*8]
        cmp rdx, [rdi + rcx*8]
        jne 8f
        jmp 4b
5:      mov rax, r14
        add rsp, 32
        LEAVE
8:      lea rdi, [rip + .Ls_unexp_mismatch]
        call rt_fatal
ENDF vm_expand_trace

        .section .rodata
.Ls_unexp_mismatch: .asciz "vm_expand_trace: the unexpanded nodes after the runs and python's walk disagree"
        .text

# vm_replace_loops(root, nodes): an unexpanded node at a point of
# execution already seen on its path (same jumpdest, same stack layout)
# is a loop - nodes: the unexpanded nodes (vm_expand_trace's), or 0 to
# find them. ('loop', earlier, stack, folded, vars): folded a list, as
# python's fold_stacks gives it.
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
        mov rdi, r14
        call loop_key
        mov rdx, rax
        mov rdi, [r14 + ND_STACK]
        mov rsi, [r13 + ND_STACK]
        lea rcx, [rsp]
        call fold_stacks
        mov rdi, rax
        call seq_to_list
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
        # these, as no other node's trace is ever a loop, unless
        # continue_loops left some: VM_LOOPS_STALE)
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
# vm_replace_loops made so since (VM_LOOPS, in the same order), emptied;
# or, when the last call returned early (it may: the tree changed), a walk
# of the tree (VM_LOOPS_STALE)
FUNC vm_continue_loops
        ENTER
        sub rsp, 64
        .set CL_DEST, 0                 # loop_dest
        .set CL_SETVARS, 8
        .set CL_BEGINVARS, 16
        .set CL_I, 24
        .set CL_VARS, 32
        .set CL_MASK, 40
        mov [rsp + 56], rdi             # root
        mov rax, [r15 + CTX_VM]
        mov rbx, [rax + VM_LOOPS]
        cmp qword ptr [rax + VM_LOOPS_STALE], 0
        je 1f
        mov qword ptr [rax + VM_LOOPS_STALE], 0
        mov rdi, [rsp + 56]             # python's walk
        lea rsi, [rip + pred_loop]
        xor edx, edx
        call find_nodes
        mov rcx, [r15 + CTX_VM]
        mov rdx, [rcx + VM_LOOPS]
        test rdx, rdx
        jz 2f
        mov qword ptr [rdx + VEC_LEN], 0
2:      mov rbx, rax
        mov [rcx + VM_LOOPS], rax
1:      test rbx, rbx
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
        mov [rsp + CL_DEST], rax
        cmp qword ptr [rax + ND_LABEL], 0
        je .Lcl_new_loop
        # loop_dest is already the body of a loop: this is another way
        # back to its head. What was assumed in memory at the start of the
        # loop (see node_set_label) and isn't any more here: explored again
        # without it.
        mov rdi, [rax + ND_ASSUMED_MEM]
        mov rsi, [r13 + ND_KNOWN]
        call facts_missing
        test rax, rax
        jnz .Lcl_broken
        # set_vars = [('setvar', var_idx, stack[stack_pos]) for (_, var_idx,
        # val, stack_pos) in loop_dest.label.begin_vars]
        call vec_new
        mov [rsp + CL_SETVARS], rax
        mov rax, [rsp + CL_DEST]
        mov rax, [rax + ND_LABEL]
        mov rax, [rax + ND_BEGIN_VARS]
        mov [rsp + CL_BEGINVARS], rax
        mov qword ptr [rsp + CL_I], 0
1:      mov rcx, [rsp + CL_I]
        mov rax, [rsp + CL_BEGINVARS]
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
        mov rdi, [rsp + CL_SETVARS]
        mov rsi, rax
        call vec_push
        inc qword ptr [rsp + CL_I]
        jmp 1b
2:      mov rax, [rsp + CL_SETVARS]
        cmp qword ptr [rax + VEC_LEN], 0
        jne .Lcl_vars
        # (a loop of its own, from loop_dest: see set_label) - fold the
        # stacks again, numbered after loop_dest
        mov rdi, [rsp + CL_DEST]
        call loop_key
        mov rdx, rax
        mov rdi, [rsp + CL_DEST]
        mov rdi, [rdi + ND_STACK]
        mov rsi, [r14 + N_DATA + 16]
        lea rcx, [rsp + CL_VARS]
        call fold_stacks
        mov rcx, [rsp + CL_VARS]
        cmp dword ptr [rcx + N_AUX], 0
        je 3f
        mov rdi, rax
        call seq_to_list
        mov rcx, rax
        mov qword ptr [r13 + ND_TRACE], 0
        mov rdi, r13
        mov rsi, [rsp + CL_DEST]
        mov rdx, [rsp + CL_VARS]
        call node_set_label
        jmp .Lcl_next
3:      # nothing on the stack changes from one iteration to the next (the
        # loop keeps what it changes in memory, as Vyper does): back to the
        # start, rather than a label again
        xor edi, edi
        xor esi, esi
        call mk_tuple
        mov rdx, rax
        mov rdi, r13
        mov rsi, [rsp + CL_DEST]
        call cl_set_goto
        jmp .Lcl_next
.Lcl_vars:
        # The loop variables were found by comparing the stack before and
        # after the first iteration, and this one changes something else
        # (`s += i * i` leaves s at 0 the first time): the loop gets
        # explored again, with a variable there too.
        mov rax, [rsp + CL_DEST]
        mov rax, [rax + ND_STACK]       # old_stack
        mov edi, [rax + N_AUX]
        inc edi
        call arena_alloc
        mov [rsp + CL_MASK], rax        # var_positions | changed
        mov rax, [rsp + CL_BEGINVARS]
        xor ecx, ecx
4:      cmp ecx, [rax + N_AUX]
        jae 5f
        mov rdx, [rax + N_DATA + rcx*8]
        mov rdx, [rdx + N_DATA + 24]    # stack_pos
        sar rdx, 1
        mov rsi, [rsp + CL_MASK]
        mov byte ptr [rsi + rdx], 1
        inc ecx
        jmp 4b
5:      xor r8d, r8d                    # changed: idx not a variable's, before != after
        mov rax, [rsp + CL_DEST]
        mov rax, [rax + ND_STACK]
        mov rcx, [r14 + N_DATA + 16]
        mov edx, [rax + N_AUX]
        cmp edx, [rcx + N_AUX]
        cmova edx, [rcx + N_AUX]        # (zip: the shortest)
        xor esi, esi
6:      cmp esi, edx
        jae 7f
        mov rdi, [rsp + CL_MASK]
        cmp byte ptr [rdi + rsi], 0
        jne 61f
        mov rdi, [rax + N_DATA + rsi*8]
        cmp rdi, [rcx + N_DATA + rsi*8]
        je 61f
        push rax
        push rcx
        push rdx
        push rsi
        push r8
        sub rsp, 8
        mov rsi, [rcx + N_DATA + rsi*8]
        call values_equal
        add rsp, 8
        pop r8
        pop rsi
        pop rdx
        pop rcx
        mov rdi, rax
        pop rax
        test edi, edi
        jnz 61f
        mov rdi, [rsp + CL_MASK]
        mov byte ptr [rdi + rsi], 2     # (changed)
        inc r8d
61:     inc esi
        jmp 6b
7:      test r8d, r8d
        jz .Lcl_goto
        # first = loop_dest.label: the head; stack_vars of its stack
        mov rax, [rsp + CL_DEST]
        mov rdi, [rax + ND_LABEL]
        call loop_key
        mov rdx, rax
        mov rax, [rsp + CL_DEST]
        mov rax, [rax + ND_LABEL]
        mov rdi, [rax + ND_STACK]
        mov rsi, [rsp + CL_MASK]
        lea rcx, [rsp + CL_VARS]
        call stack_vars
        mov rdi, rax
        call seq_to_list
        mov rcx, rax
        mov rdi, [rsp + CL_DEST]
        mov qword ptr [rdi + ND_TRACE], 0
        lea rax, [rdi + ND_NEXT_VEC]    # loop_dest.next = [] (set_label makes
        mov [rdi + ND_NEXT], rax        # the head's again)
        mov qword ptr [rax + VEC_LEN], 0
        mov rsi, [rdi + ND_LABEL]
        mov rdx, [rsp + CL_VARS]
        call node_set_label
        # the other loops found in this pass may be in the part of the tree
        # that was just thrown away
        jmp .Lcl_return
.Lcl_goto:
        # node.trace = [('goto', loop_dest, set_vars)]
        mov rdi, [rsp + CL_SETVARS]
        call vec_to_tuple
        mov rdx, rax
        mov rdi, r13
        mov rsi, [rsp + CL_DEST]
        call cl_set_goto
        jmp .Lcl_next
.Lcl_broken:
        # an iteration changes what was assumed in memory at the start of
        # the loop: explored again without it
        mov [rsp + CL_VARS], rax        # broken
        mov rdi, [rsp + CL_DEST]
        mov rdi, [rdi + ND_REJECTED_MEM]
        test rdi, rdi
        jnz 8f
        xor edi, edi
        xor esi, esi
        call mk_tuple
        mov rdi, rax
8:      mov rsi, [rsp + CL_VARS]
        call tuple_concat
        mov rcx, [rsp + CL_DEST]
        mov [rcx + ND_REJECTED_MEM], rax
        mov rdi, [rcx + ND_ASSUMED_MEM]
        mov rsi, [rsp + CL_VARS]
        call facts_without
        mov rcx, [rsp + CL_DEST]
        mov [rcx + ND_ASSUMED_MEM], rax
        mov rdi, [rcx + ND_KNOWN]
        mov rsi, [rsp + CL_VARS]
        call facts_without
        mov rdi, [rsp + CL_DEST]
        mov [rdi + ND_KNOWN], rax
        mov qword ptr [rdi + ND_TRACE], 0
        call vec_new
        mov rdi, [rsp + CL_DEST]
        mov [rdi + ND_NEXT], rax
        call node_touch
.Lcl_return:
        # the loops not processed are left in the tree: the next call walks it
        mov rax, [r15 + CTX_VM]
        mov qword ptr [rax + VM_LOOPS_STALE], 1
        jmp .Lcl_done
.Lcl_new_loop:
        # node.trace = None; node.set_label(loop_dest, vars, new_stack)
        mov qword ptr [r13 + ND_TRACE], 0
        mov rdi, r13
        mov rsi, [rsp + CL_DEST]
        mov rdx, [r14 + N_DATA + 32]
        mov rcx, [r14 + N_DATA + 24]
        call node_set_label
        jmp .Lcl_next
.Lcl_done:
        mov rax, [r15 + CTX_VM]
        mov rax, [rax + VM_LOOPS]
        test rax, rax
        jz 1f
        mov qword ptr [rax + VEC_LEN], 0
1:      add rsp, 64
        LEAVE
ENDF vm_continue_loops

# cl_set_goto(node, loop_dest, setvars): node.trace = [('goto', loop_dest, setvars)]
FUNC cl_set_goto
        ENTER
        mov rbx, rdi
        mov rdx, rdx
        LOADS rdi, GOTO
        call mk3
        mov r12, rax
        call vec_new
        mov [rbx + ND_TRACE], rax
        mov rdi, rax
        mov rsi, r12
        call vec_push
        mov rdi, rbx
        call node_touch
        LEAVE
ENDF cl_set_goto

# pred_loop(node) -> eax: the node's trace is one ('loop', ...)
FUNC pred_loop
        xor eax, eax
        mov rcx, [rdi + ND_TRACE]
        test rcx, rcx
        jz 1f
        cmp qword ptr [rcx + VEC_LEN], 1
        jne 1f
        mov rcx, [rcx + VEC_DATA]
        mov rdi, [rcx]
        OPCODE_OF_RDI
        cmp eax, OP_LOOP
        sete al
        movzx eax, al
1:      ret
ENDF pred_loop

# facts_missing(facts, known) -> rax: the facts (a tuple, or 0) not in known,
# a tuple - 0 when there's none
FUNC facts_missing
        ENTER
        mov rbx, rdi
        mov r12, rsi
        xor eax, eax
        test rbx, rbx
        jz 9f
        call vec_new
        mov r13, rax
        xor r14d, r14d
1:      cmp r14d, [rbx + N_AUX]
        jae 4f
        mov rsi, [rbx + N_DATA + r14*8]
        inc r14d
        xor ecx, ecx
2:      cmp ecx, [r12 + N_AUX]
        jae 3f
        cmp [r12 + N_DATA + rcx*8], rsi
        je 1b
        inc ecx
        jmp 2b
3:      mov rdi, r13
        call vec_push
        jmp 1b
4:      xor eax, eax
        cmp qword ptr [r13 + VEC_LEN], 0
        je 9f
        mov rdi, r13
        call vec_to_tuple
9:      LEAVE
ENDF facts_missing

# facts_without(facts, gone) -> tuple: the facts not in gone
FUNC facts_without
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call vec_new
        mov r13, rax
        test rbx, rbx
        jz 4f
        xor r14d, r14d
1:      cmp r14d, [rbx + N_AUX]
        jae 4f
        mov rsi, [rbx + N_DATA + r14*8]
        inc r14d
        xor ecx, ecx
2:      cmp ecx, [r12 + N_AUX]
        jae 3f
        cmp [r12 + N_DATA + rcx*8], rsi
        je 1b
        inc ecx
        jmp 2b
3:      mov rdi, r13
        call vec_push
        jmp 1b
4:      mov rdi, r13
        call vec_to_tuple
        LEAVE
ENDF facts_without

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
# of the `if` (see merge_branches in vm.py). First the merges that were
# too early to tell at the head of a loop - its exits, maybe -, the oldest
# first (VM_PENDING); then those at the jumpdests the unexpanded nodes got
# to (python's _merge_unexpanded).
FUNC vm_merge_branches
        ENTER
        sub rsp, 48
        mov rax, [r15 + CTX_VM]
        cmp qword ptr [rax + VM_JUST_FDESTS], 0
        jne .Lmb_done
        mov rbx, rdi                    # root
        mov [rsp + 40], rdi
        # the pending merges: dropped when p was thrown away, or when it's
        # told (True or False)
        mov r12, [rax + VM_PENDING]
        test r12, r12
        jz .Lmb_unexpanded
        xor r13d, r13d                  # read
        xor r14d, r14d                  # written
1:      cmp r13, [r12 + VEC_LEN]
        jae 3f
        mov rax, [r12 + VEC_DATA]
        mov rdi, [rax + r13*8]          # p
        mov rsi, [rax + r13*8 + 8]      # jd
        add r13, 2
        mov [rsp], rdi
        mov [rsp + 8], rsi
        mov rsi, [rsp + 40]
        call vm_attached
        test eax, eax
        jz 1b
        mov rdi, [rsp]
        mov rsi, [rsp + 8]
        mov edx, 1                      # loop_exit
        call vm_merge_at
        cmp eax, TRI_NONE
        jne 1b
        mov rax, [r12 + VEC_DATA]
        mov rcx, [rsp]
        mov [rax + r14*8], rcx
        mov rcx, [rsp + 8]
        mov [rax + r14*8 + 8], rcx
        add r14, 2
        jmp 1b
3:      mov [r12 + VEC_LEN], r14
.Lmb_unexpanded:
        # every node, in find_nodes' order (one walk: the unexpanded ones
        # are those of them whose trace is None, in the same order)
        mov rdi, [rsp + 40]
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
        cmp qword ptr [rbx + ND_SWITCHED], 0
        jne .Lmb_next                   # a path of a switch, where what it copies is known
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
        xor edx, edx
        call vm_merge_at
        cmp eax, TRI_TRUE
        je .Lmb_next
        cmp eax, TRI_NONE
        jne .Lmb_other
        mov rax, [rsp + 24]             # at the head of a loop: its exits,
        cmp qword ptr [rax + ND_LABEL], 0       # maybe - tried again later
        je .Lmb_other
        mov rdi, rax
        mov rsi, [rbx + ND_JD]
        call vm_pending_add
        jmp .Lmb_other
.Lmb_done:
        add rsp, 48
        LEAVE
ENDF vm_merge_branches

# vm_pending_add(p, jd): pending_merges[(id(p), jd)] = (p, jd) - appended
# unless it's there already (a dict keeps its place)
FUNC vm_pending_add
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov rax, [r15 + CTX_VM]
        mov r13, [rax + VM_PENDING]
        test r13, r13
        jnz 1f
        call vec_new
        mov r13, rax
        mov rax, [r15 + CTX_VM]
        mov [rax + VM_PENDING], r13
1:      xor ecx, ecx
        mov rax, [r13 + VEC_DATA]
2:      cmp rcx, [r13 + VEC_LEN]
        jae 3f
        cmp [rax + rcx*8], rbx
        jne 21f
        cmp [rax + rcx*8 + 8], r12
        je 9f
21:     add rcx, 2
        jmp 2b
3:      mov rdi, r13
        mov rsi, rbx
        call vec_push
        mov rdi, r13
        mov rsi, r12
        call vec_push
9:      LEAVE
ENDF vm_pending_add

# vm_attached(node, root) -> eax: python's attached - node is still in the
# tree of root, not in a part thrown away since (a loop explored again, a
# path cut by a merge): one of its parent's children, up to the root
FUNC vm_attached
1:      cmp rdi, rsi
        je 8f
        mov rax, [rdi + ND_PREV]
        test rax, rax
        jz 9f
        mov rcx, [rax + ND_NEXT]
        mov rdx, [rcx + VEC_LEN]
        mov rcx, [rcx + VEC_DATA]
2:      test rdx, rdx
        jz 9f
        dec rdx
        cmp [rcx + rdx*8], rdi
        jne 2b
        mov rdi, rax
        jmp 1b
8:      mov eax, 1
        ret
9:      xor eax, eax
        ret
ENDF vm_attached

# vm_below(node, p) -> eax: python's below - node is p, or a node of the
# tree below it: python's walk up; by the jump pointers while the depths
# are consistent, as vm_common_ancestor (both, compared, with
# PANORAMIX_CHECK_LCA set) - merge_branches asks it of every merged node
# it meets, and the walk took three quarters of the time of a function
# twenty thousand nodes deep (aave3's MockReentrantInitializableImple)
FUNC vm_below
        mov rax, [r15 + CTX_VM]
        cmp qword ptr [rax + VM_STALE_DEPTHS], 0
        jne vm_below_walk
        cmp qword ptr [rax + VM_CHECK_LCA], 0
        je vm_below_jumps
        push rbx
        push rdi
        push rsi
        call vm_below_jumps
        mov ebx, eax
        mov rsi, [rsp]
        mov rdi, [rsp + 8]
        call vm_below_walk
        cmp eax, ebx
        jne 1f
        pop rsi
        pop rdi
        pop rbx
        ret
1:      lea rdi, [rip + .Ls_below_mismatch]
        call rt_fatal
ENDF vm_below

        .section .rodata
.Ls_below_mismatch: .asciz "vm_below: the jump pointers and the walk disagree"
        .text

# vm_below_walk(node, p) -> eax: python's walk up, a step at a time
FUNC vm_below_walk
1:      test rdi, rdi
        jz 9f
        cmp rdi, rsi
        je 8f
        mov rdi, [rdi + ND_PREV]
        jmp 1b
8:      mov eax, 1
        ret
9:      xor eax, eax
        ret
ENDF vm_below_walk

# vm_below_jumps(node, p) -> eax: node's ancestor at p's depth is p - up
# by the jump pointers (vm_common_ancestor_jumps) where they don't go
# past that depth
FUNC vm_below_jumps
        xor eax, eax
        test rdi, rdi
        jz 9f
        mov rdx, [rsi + ND_DEPTH]
1:      cmp [rdi + ND_DEPTH], rdx
        jle 3f
        mov r8, [rdi + ND_JUMP]
        cmp [r8 + ND_DEPTH], rdx
        jl 2f
        mov rdi, r8
        jmp 1b
2:      mov rdi, [rdi + ND_PREV]
        jmp 1b
3:      cmp rdi, rsi
        sete al
9:      ret
ENDF vm_below_jumps

# vm_in_merged_branch(node, p) -> eax: python's in_merged_branch - node,
# below the `if` node p, is in a branch of an `if` between them whose
# paths were merged: a path that ends at node goes on in the continuation
# of that `if`, not in what follows p
FUNC vm_in_merged_branch
        ENTER
        mov rbx, rdi                    # child
        mov r12, [rdi + ND_PREV]        # a
        mov r13, rsi                    # p
1:      test r12, r12
        jz 9f
        cmp r12, r13
        je 9f
        mov rax, [r12 + ND_TRACE]
        test rax, rax
        jz 2f
        mov rcx, [rax + VEC_LEN]
        cmp rcx, 2
        jb 2f
        mov rax, [rax + VEC_DATA]
        mov rdi, [rax + rcx*8 - 8]
        OPCODE_OF_RDI
        cmp eax, OP_JUMP
        jne 2f
        mov rax, [r12 + ND_TRACE]
        mov rcx, [rax + VEC_LEN]
        mov rax, [rax + VEC_DATA]
        mov rdi, [rax + rcx*8 - 16]
        OPCODE_OF_RDI
        cmp eax, OP_IF
        jne 2f
        cmp dword ptr [rdi + N_AUX], 4
        jb 2f
        cmp [rdi + N_DATA + 16], rbx
        je 8f
        cmp [rdi + N_DATA + 24], rbx
        je 8f
2:      mov rbx, r12
        mov r12, [r12 + ND_PREV]
        jmp 1b
8:      mov eax, 1
        LEAVE
9:      xor eax, eax
        LEAVE
ENDF vm_in_merged_branch

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
        OPSET_MEMBER terminal, OP_LEAVE
        OPSET_MEMBER terminal, OP_GOTO
        OPSET_END terminal, OP_COUNT

# mv_visit(start, p, jd, hits, continues) -> eax: python's visit (vm.py,
# _merge_at) - TRI_TRUE if every path below `start` either ends, reaches
# `jd` (a hit, pushed on hits; not one in a branch of an if between p and
# it whose paths were merged already), or loops back (a goto: one to p or
# its label - the loop p is the head of - pushed on continues); TRI_FALSE
# if one is the head of a loop at jd, or a merged node whose paths go on
# above p; TRI_NONE if it's too early to tell. Depth first, the children
# in order, on the VM's scratch stack (find_nodes': not in use meanwhile).
FUNC mv_visit
        ENTER
        sub rsp, 48
        .set MV_P, 0
        .set MV_JD, 8
        .set MV_HITS, 16
        .set MV_CONTS, 24
        .set MV_RES, 32
        mov rbx, rdi
        mov [rsp + MV_P], rsi
        mov [rsp + MV_JD], rdx
        mov [rsp + MV_HITS], rcx
        mov [rsp + MV_CONTS], r8
        mov qword ptr [rsp + MV_RES], TRI_TRUE
        mov rax, [r15 + CTX_VM]
        mov r14, [rax + VM_SCR_VISIT]
        test r14, r14
        jnz 1f
        call vec_new
        mov r14, rax
        mov rax, [r15 + CTX_VM]
        mov [rax + VM_SCR_VISIT], r14
1:      mov qword ptr [r14 + VEC_LEN], 0
        mov rdi, r14
        mov rsi, rbx
        call vec_push
.Lmv_pop:
        mov rcx, [r14 + VEC_LEN]
        test rcx, rcx
        jz .Lmv_end
        dec rcx
        mov [r14 + VEC_LEN], rcx
        mov rax, [r14 + VEC_DATA]
        mov rbx, [rax + rcx*8]          # n
        cmp qword ptr [rbx + ND_MERGED], 0
        je 2f
        # goes on in the continuation of the `if` it was merged at, which
        # will be visited as well - if that's below p; one above it: the
        # path would go on in what follows p instead
        mov rdi, [rbx + ND_MERGE_POINT]
        mov rsi, [rsp + MV_P]
        call vm_below
        test eax, eax
        jz .Lmv_false
        jmp .Lmv_pop
2:      mov rax, [rbx + ND_JD]
        cmp qword ptr [rbx + ND_LABEL], 0
        je 3f
        cmp rax, [rsp + MV_JD]          # the head of a loop: let's keep it that way
        je .Lmv_false
        jmp 4f
3:      cmp rax, [rsp + MV_JD]
        jne 4f
        mov rdi, rbx
        mov rsi, [rsp + MV_P]
        call vm_in_merged_branch
        test eax, eax
        jnz 4f
        mov rdi, [rsp + MV_HITS]        # a hit
        mov rsi, rbx
        call vec_push
        jmp .Lmv_pop
4:      mov rax, [rbx + ND_TRACE]
        test rax, rax
        jnz 5f
        mov qword ptr [rsp + MV_RES], TRI_NONE
        jmp .Lmv_pop
5:      mov rcx, [rbx + ND_NEXT]
        mov rdx, [rcx + VEC_LEN]
        test rdx, rdx
        jz 7f
        mov rsi, [rcx + VEC_DATA]       # its children, reversed
6:      dec rdx
        js .Lmv_pop
        mov [rsp + 40], rdx
        push rsi
        push rsi
        mov rdi, r14
        mov rsi, [rsi + rdx*8]
        call vec_push
        pop rsi
        pop rsi
        mov rdx, [rsp + 40]
        jmp 6b
7:      mov rcx, [rax + VEC_LEN]
        test rcx, rcx
        jz 9f
        mov rax, [rax + VEC_DATA]
        mov r12, [rax + rcx*8 - 8]      # the last line
        mov rdi, r12
        OPCODE_OF_RDI
        mov r13d, eax
        cmp eax, OP_GOTO
        jne 8f
        mov rax, [r12 + N_DATA + 8]     # to p, or to p's label: it goes on with the loop
        mov rcx, [rsp + MV_P]
        cmp rax, rcx
        je 71f
        mov rcx, [rcx + ND_LABEL]
        test rcx, rcx
        jz 8f
        cmp rax, rcx
        jne 8f
71:     mov rdi, [rsp + MV_CONTS]
        mov rsi, rbx
        call vec_push
8:      IN_OPSET terminal, r13
        jne .Lmv_pop
9:      mov qword ptr [rsp + MV_RES], TRI_NONE  # (e.g. 'loop', not yet processed by continue_loops)
        jmp .Lmv_pop
.Lmv_end:
        mov eax, [rsp + MV_RES]
        add rsp, 48
        LEAVE
.Lmv_false:
        mov eax, TRI_FALSE
        add rsp, 48
        LEAVE
ENDF mv_visit

# pred_merged_out(m, h) -> eax: m is a merged node whose merge point isn't
# h nor below it (_merge_at's check of the hits)
FUNC pred_merged_out
        xor eax, eax
        cmp qword ptr [rdi + ND_MERGED], 0
        je 1f
        mov rdi, [rdi + ND_MERGE_POINT]
        call vm_below
        xor eax, 1
1:      ret
ENDF pred_merged_out

# vm_merge_at(p, jd, loop_exit) -> eax: python's _merge_at - merge the
# paths going out of the `if` node p at jumpdest jd. TRI_TRUE if it was
# done, TRI_NONE if it can't be told yet (some paths were not explored
# yet), TRI_FALSE if not. loop_exit: only where jd is where the loop p is
# the head of goes on when it's left - its exit condition jumps there, and
# a path of the body goes on with the loop without getting there.
FUNC vm_merge_at
        ENTER
        sub rsp, 96
        .set MA_LEN, 0                  # the stacks' length
        .set MA_MERGED, 8               # the merged stack's elements
        .set MA_SETVARS, 16             # a vec per hit
        .set MA_IDX, 24
        .set MA_K, 32
        .set MA_VALS, 40                # the values at idx, a vec
        .set MA_NAME, 48
        .set MA_CONTS, 56
        .set MA_LOOPEXIT, 64
        .set MA_SEEN, 72
        mov rbx, rdi                    # p
        mov r12, rsi                    # jd
        mov [rsp + MA_LOOPEXIT], rdx
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
        call vec_new
        mov r13, rax                    # hits
        call vec_new
        mov [rsp + MA_CONTS], rax
        mov rdi, [r14 + N_DATA + 16]
        mov rsi, rbx
        mov rdx, r12
        mov rcx, r13
        mov r8, [rsp + MA_CONTS]
        call mv_visit
        cmp eax, TRI_FALSE
        je .Lma_false
        mov [rsp + MA_SEEN], rax
        mov rdi, [r14 + N_DATA + 24]
        mov rsi, rbx
        mov rdx, r12
        mov rcx, r13
        mov r8, [rsp + MA_CONTS]
        call mv_visit
        cmp eax, TRI_FALSE
        je .Lma_false
        cmp eax, TRI_NONE
        je .Lma_none
        cmp dword ptr [rsp + MA_SEEN], TRI_NONE
        je .Lma_none
        cmp qword ptr [r13 + VEC_LEN], 2
        jb .Lma_false
        cmp qword ptr [rsp + MA_LOOPEXIT], 0
        je 2f
        # the exits of the loop: some path goes on with it, and a side of
        # the if gets to jd at once
        mov rax, [rsp + MA_CONTS]
        cmp qword ptr [rax + VEC_LEN], 0
        je .Lma_false
        mov rcx, [r13 + VEC_LEN]
        mov rax, [r13 + VEC_DATA]
1:      dec rcx
        js .Lma_false
        mov rdx, [rax + rcx*8]
        cmp rdx, [r14 + N_DATA + 16]
        je 2f
        cmp rdx, [r14 + N_DATA + 24]
        je 2f
        jmp 1b
2:      # the path from a hit merged with others further down, at an `if`
        # above p: cut at the hit, it wouldn't get to that merge any more
        mov qword ptr [rsp + MA_K], 0
3:      mov rcx, [rsp + MA_K]
        cmp rcx, [r13 + VEC_LEN]
        jae 4f
        mov rax, [r13 + VEC_DATA]
        mov rdi, [rax + rcx*8]
        lea rsi, [rip + pred_merged_out]
        mov rdx, rdi
        call find_nodes
        cmp qword ptr [rax + VEC_LEN], 0
        jne .Lma_false
        inc qword ptr [rsp + MA_K]
        jmp 3b
4:      # merged = the stack of the first hit, with a variable wherever the
        # hits' stacks differ (what a path knows of a value it has of its
        # own decides it first); setvars[k] = the assignments on path k
        mov rax, [r13 + VEC_DATA]
        mov rax, [rax]
        mov rax, [rax + ND_STACK]
        mov ecx, [rax + N_AUX]
        mov [rsp + MA_LEN], rcx
        lea rdi, [rcx*8 + 8]
        call arena_alloc
        mov [rsp + MA_MERGED], rax
        mov rdi, rax
        mov rax, [r13 + VEC_DATA]
        mov rax, [rax]
        mov rax, [rax + ND_STACK]
        lea rsi, [rax + N_DATA]
        mov rdx, [rsp + MA_LEN]
        shl rdx, 3
        call memcpy@PLT
        mov rdi, [r13 + VEC_LEN]
        shl rdi, 3
        call arena_alloc
        mov [rsp + MA_SETVARS], rax
        xor ecx, ecx
5:      cmp rcx, [r13 + VEC_LEN]
        jae 6f
        mov [rsp + MA_K], rcx
        call vec_new
        mov rcx, [rsp + MA_K]
        mov rdx, [rsp + MA_SETVARS]
        mov [rdx + rcx*8], rax
        inc rcx
        jmp 5b
6:      call vec_new
        mov [rsp + MA_VALS], rax
        mov qword ptr [rsp + MA_IDX], 0
.Lma_idx:
        mov rcx, [rsp + MA_IDX]
        cmp rcx, [rsp + MA_LEN]
        jae .Lma_apply
        # vals = [h.stack[idx] for h in hits]; all equal?
        mov rax, [rsp + MA_VALS]
        mov qword ptr [rax + VEC_LEN], 0
        xor ecx, ecx
7:      cmp rcx, [r13 + VEC_LEN]
        jae 8f
        mov [rsp + MA_K], rcx
        mov rax, [r13 + VEC_DATA]
        mov rax, [rax + rcx*8]
        mov rax, [rax + ND_STACK]
        mov rdx, [rsp + MA_IDX]
        mov rsi, [rax + N_DATA + rdx*8]
        mov rdi, [rsp + MA_VALS]
        call vec_push
        mov rcx, [rsp + MA_K]
        inc rcx
        jmp 7b
8:      call .Lma_all_equal
        test eax, eax
        jnz .Lma_same
        # decided(v, h.known)
        xor ecx, ecx
9:      cmp rcx, [r13 + VEC_LEN]
        jae 10f
        mov [rsp + MA_K], rcx
        mov rax, [rsp + MA_VALS]
        mov rax, [rax + VEC_DATA]
        mov rdi, [rax + rcx*8]
        mov rax, [r13 + VEC_DATA]
        mov rax, [rax + rcx*8]
        mov rsi, [rax + ND_KNOWN]
        call decided
        mov rcx, [rsp + MA_K]
        mov rdx, [rsp + MA_VALS]
        mov rdx, [rdx + VEC_DATA]
        mov [rdx + rcx*8], rax
        inc rcx
        jmp 9b
10:     call .Lma_all_equal
        test eax, eax
        jz 11f
        mov rax, [rsp + MA_VALS]        # merged[idx] = vals[0]
        mov rax, [rax + VEC_DATA]
        mov rax, [rax]
        mov rcx, [rsp + MA_IDX]
        mov rdx, [rsp + MA_MERGED]
        mov [rdx + rcx*8], rax
        jmp .Lma_same
11:     # let's not turn a jump destination into a variable
        xor ecx, ecx
12:     cmp rcx, [r13 + VEC_LEN]
        jae 13f
        mov rax, [rsp + MA_VALS]
        mov rax, [rax + VEC_DATA]
        mov rsi, [rax + rcx*8]
        inc rcx
        test sil, 1
        jz 12b
        sar rsi, 1
        js 12b
        mov [rsp + MA_K], rcx
        mov rdi, [r15 + CTX_VM]
        mov rdi, [rdi + VM_LOADER]
        call loader_is_jumpdest
        mov rcx, [rsp + MA_K]
        test eax, eax
        jnz .Lma_false
        jmp 12b
13:     call vm_new_var_name
        mov [rsp + MA_NAME], rax
        mov rsi, rax
        LOADS rdi, VAR
        call mk2
        mov rcx, [rsp + MA_IDX]
        mov rdx, [rsp + MA_MERGED]
        mov [rdx + rcx*8], rax          # merged[idx] = ('var', name)
        xor ecx, ecx
14:     cmp rcx, [r13 + VEC_LEN]
        jae .Lma_same
        mov [rsp + MA_K], rcx
        mov rax, [rsp + MA_VALS]
        mov rax, [rax + VEC_DATA]
        mov rdx, [rax + rcx*8]
        mov rsi, [rsp + MA_NAME]
        LOADS rdi, SETVAR
        call mk3
        mov rcx, [rsp + MA_K]
        mov rdi, [rsp + MA_SETVARS]
        mov rdi, [rdi + rcx*8]
        mov rsi, rax
        call vec_push
        mov rcx, [rsp + MA_K]
        inc rcx
        jmp 14b
.Lma_same:
        inc qword ptr [rsp + MA_IDX]
        jmp .Lma_idx
.Lma_apply:
        mov rax, [r15 + CTX_VM]         # (merge_branches' unexpanded nodes
        mov qword ptr [rax + VM_UNEXP_VALID], 0         # change)
        # each hit now just sets the variables and goes on in the merged node
        xor ecx, ecx
15:     cmp rcx, [r13 + VEC_LEN]
        jae 16f
        mov [rsp + MA_K], rcx
        mov rax, [r13 + VEC_DATA]
        mov rax, [rax + rcx*8]
        mov rdx, [rsp + MA_SETVARS]
        mov rdx, [rdx + rcx*8]
        mov [rax + ND_TRACE], rdx
        mov qword ptr [rax + ND_MERGED], 1
        mov [rax + ND_MERGE_POINT], rbx
        mov [rsp + MA_IDX], rax
        call vec_new
        mov rcx, [rsp + MA_IDX]
        mov [rcx + ND_NEXT], rax
        mov rdi, rcx
        call node_touch
        mov rcx, [rsp + MA_K]
        inc rcx
        jmp 15b
16:     # what's known at the merge point is what's known on every path, and
        # what only some of them wrote in memory isn't (not even that it's
        # still zero)
        mov rdi, r13
        call merged_known
        mov [rsp + MA_IDX], rax
        mov rdi, [rsp + MA_LEN]
        mov rsi, [rsp + MA_MERGED]
        call mk_tuple
        mov rdx, rax
        mov rdi, [r12 + N_DATA]         # jd[0]
        mov rax, [r13 + VEC_DATA]
        mov rax, [rax]
        mov rsi, [rax + ND_SAFE]
        lea rcx, [rip + sp_true]
        mov r8, [rsp + MA_IDX]
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
        mov eax, TRI_TRUE
        add rsp, 96
        LEAVE
.Lma_none:
        mov eax, TRI_NONE
        add rsp, 96
        LEAVE
.Lma_false:
        mov eax, TRI_FALSE
        add rsp, 96
        LEAVE

# local: eax 1 if all of MA_VALS (the caller's frame, 8 bytes up) are equal
# to the first (python's ==)
.Lma_all_equal:
        push r12
        push r13
        push r14
        mov rax, [rsp + 32 + MA_VALS]
        mov r12, [rax + VEC_DATA]
        mov r13, [rax + VEC_LEN]
        mov r14d, 1
1:      cmp r14, r13
        jae 2f
        mov rdi, [r12]
        mov rsi, [r12 + r14*8]
        call py_equal
        test eax, eax
        jz 3f
        inc r14
        jmp 1b
2:      mov eax, 1
3:      pop r14
        pop r13
        pop r12
        ret
ENDF vm_merge_at

# merged_known(hits) -> tuple: the facts known on every path, then for
# each memory fact of a path not among them, the place with an unknown
# value ('memory', start, size, None), once
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
5:      # the memory facts of each path not known on every path
        xor r14d, r14d                  # the hit
.Lmk_hit:
        cmp r14, [rbx + VEC_LEN]
        jae .Lmk_done
        mov rax, [rbx + VEC_DATA]
        mov rax, [rax + r14*8]
        inc r14
        mov r13, [rax + ND_KNOWN]
        mov qword ptr [rsp], 0
.Lmk_fact:
        mov rcx, [rsp]
        cmp ecx, [r13 + N_AUX]
        jae .Lmk_hit
        mov rdi, [r13 + N_DATA + rcx*8]
        inc qword ptr [rsp]
        mov rsi, rdi
        OPCODE_OF_RDI
        cmp eax, OP_MEMORY
        jne .Lmk_fact
        mov rdi, r12                    # fact not in known
        call vec_has_ptr
        test eax, eax
        jnz .Lmk_fact
        mov rcx, [rsp]
        mov rax, [r13 + N_DATA + rcx*8 - 8]
        mov rsi, [rax + N_DATA + 8]
        mov rdx, [rax + N_DATA + 16]
        lea rcx, [rip + sp_none]
        LOADS rdi, MEMORY
        call mk4
        mov rsi, rax                    # unknown not in known: added
        mov rdi, r12
        call vec_has_ptr
        test eax, eax
        jnz .Lmk_fact
        mov rdi, r12
        call vec_push
        jmp .Lmk_fact
.Lmk_done:
        mov rdi, r12
        call vec_to_tuple
        add rsp, 16
        LEAVE
ENDF merged_known

# vec_has_ptr(vec, v) -> eax: v is in the vec (the same pointer); rsi kept
# (leaf)
FUNC vec_has_ptr
        mov rcx, [rdi + VEC_LEN]
        mov rax, [rdi + VEC_DATA]
1:      test rcx, rcx
        jz 2f
        dec rcx
        cmp [rax + rcx*8], rsi
        jne 1b
        mov eax, 1
        ret
2:      xor eax, eax
        ret
ENDF vec_has_ptr

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
        mov rdi, r14                    # (what's known of the memory, and
        call is_path_fact               # of the bits of a variable: not a
        test eax, eax                   # condition)
        jz .Lik_fact
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
        mov rdi, [r12 + N_DATA + r13*8]
        call is_path_fact
        test eax, eax
        jz .Lik_plain
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

# is_path_fact(fact) -> eax: the fact is a condition is_known asks about -
# not one of the memory's ('memory', ...), ('memory_fresh',), nor a
# ('var_bits', ...) (leaf)
FUNC is_path_fact
        OPCODE_OF_RDI
        cmp eax, OP_MEMORY
        je 1f
        cmp eax, OP_MEMORY_FRESH
        je 1f
        cmp eax, OP_VAR_BITS
        je 1f
        mov eax, 1
        ret
1:      xor eax, eax
        ret
ENDF is_path_fact

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
        cmp qword ptr [rbx + VM_INTERNAL], 0    # the call of a recursive internal
        je 01f                                  # function (vmrec.s)
        mov rdi, [rsp]
        mov rsi, [rsp + 16]
        call vm_internal_call_at
        test eax, eax
        jz 01f
        mov rdi, [rsp]
        mov rsi, [rsp + 24]
        call vm_internal_call
        jmp .Lex_done
01:     mov r12, [rbx + VM_LOADER]
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
        jz .Lex_no_line
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
        jz .Lex_stop                    # (the last instruction: past it,
        mov r14, rax                    # the code stops)
.Lex_loop:
        # fewer words on the stack than the instruction uses: the code
        # halts there, as at an invalid instruction
        movzx eax, byte ptr [r14 + IN_OP]
        lea rcx, [rip + stack_inputs]
        movzx eax, byte ptr [rcx + rax]
        mov rcx, [rbx + VM_STACK]
        cmp [rcx + VEC_LEN], rax
        jb .Lex_underflow
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
        jz .Lex_stop                    # (past the last instruction: the
        mov r14, rax                    # code stops there)
        jmp .Lex_loop
.Lex_no_line:
        # what follows the last instruction (a jumpi's other branch): the
        # code stops there, as at a stop
        cmp qword ptr [rsp + 8], 0
        je .Lex_bad_jumdest
        cmp r13, [r12 + LD_LASTLINE]
        jne .Lex_bad_jumdest
.Lex_stop:
        LOADS rdi, STOP
        call mk1
        call .Lex_push_line
        jmp .Lex_done
.Lex_underflow:
        LOADS rdi, INVALID
        lea rsi, [rip + .Ls_stack_underflow]
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

# vm_jumpdest_target(target) -> rax: where a jump to target goes - target,
# or -1 where it can't, an int where there's no jumpdest (python's
# lines.get(target, (None, None))[1] != "jumpdest")
FUNC vm_jumpdest_target
        ENTER
        mov rbx, rdi
        call is_int
        test eax, eax
        jz 1f
        mov rax, -1                     # (a tagged -1)
        test bl, 1
        jz 2f                           # (past 2^62: no instruction)
        mov rsi, rbx
        sar rsi, 1
        js 2f
        mov rdi, [r15 + CTX_VM]
        mov rdi, [rdi + VM_LOADER]
        call loader_instr_at
        mov rcx, rax
        mov rax, -1
        test rcx, rcx
        jz 2f
        cmp byte ptr [rcx + IN_OP], 0x5b
        jne 2f
1:      mov rax, rbx
2:      LEAVE
ENDF vm_jumpdest_target

# --- one instruction: handle_jumps + apply_stack ---

.macro VPOP reg
        call vm_pop
        mov \reg, rax
.endm

.macro VPUSH reg
        mov rdi, \reg
        call vm_push
.endm

# a line of the trace (python's trace() of apply_stack: a setmem tells
# what's known of the memory, see vm_add_line)
.macro VTRACE reg
        mov rdi, \reg
        call vm_add_line
.endm

        .section .data.rel.ro
        .align 8
step_table:
        .quad .Lop_stop, .Lop_add, .Lop_mul, .Lop_sub, .Lop_arith, .Lop_arith, .Lop_arith, .Lop_arith    # 00-07
        .quad .Lop_mulmod, .Lop_mulmod, .Lop_arith, .Lop_arith, .Lop_unknown, .Lop_unknown, .Lop_unknown, .Lop_unknown   # 08-0f
        .quad .Lop_arith, .Lop_arith, .Lop_arith, .Lop_arith, .Lop_arith, .Lop_iszero, .Lop_and, .Lop_or   # 10-17
        .quad .Lop_arith, .Lop_unary, .Lop_byte, .Lop_shl, .Lop_shr, .Lop_sar, .Lop_unary, .Lop_unknown   # 18-1f
        .quad .Lop_sha3, .Lop_unknown, .Lop_unknown, .Lop_unknown, .Lop_unknown, .Lop_unknown, .Lop_unknown, .Lop_unknown   # 20-27
        .quad .Lop_unknown, .Lop_unknown, .Lop_unknown, .Lop_unknown, .Lop_unknown, .Lop_unknown, .Lop_unknown, .Lop_unknown   # 28-2f
        .quad .Lop_env, .Lop_balance, .Lop_env, .Lop_env, .Lop_env, .Lop_calldataload, .Lop_env, .Lop_calldatacopy   # 30-37
        .quad .Lop_codesize, .Lop_codecopy, .Lop_env, .Lop_unary, .Lop_extcodecopy, .Lop_returndatasize, .Lop_returndatacopy, .Lop_unary   # 38-3f
        .quad .Lop_unary, .Lop_env, .Lop_env, .Lop_env, .Lop_env, .Lop_env, .Lop_env, .Lop_selfbalance   # 40-47
        .quad .Lop_env, .Lop_unary, .Lop_env, .Lop_unknown, .Lop_unknown, .Lop_unknown, .Lop_unknown, .Lop_unknown   # 48-4f
        .quad .Lop_pop, .Lop_mload, .Lop_mstore, .Lop_mstore8, .Lop_sload, .Lop_sstore, .Lop_jump, .Lop_jumpi   # 50-57
        .quad .Lop_pc, .Lop_msize, .Lop_env, .Lop_jumpdest, .Lop_tload, .Lop_tstore, .Lop_mcopy, .Lop_push   # 58-5f
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

# what happens before an instruction of apply_stack (the others, of
# handle_jumps, end the node): 0 nothing, 1 a snapshot of what an sstore
# or a tstore changes and what's known of it forgotten, 2 the same for
# what a call or a creation changes, 3 handle_jumps' (no apply_stack)
step_class:
        .byte 3                         # 00 stop
        .rept 0x55 - 1
        .byte 0
        .endr
        .byte 1                         # 55 sstore
        .byte 3, 3                      # 56 jump, 57 jumpi
        .rept 0x5b - 0x58
        .byte 0
        .endr
        .byte 3                         # 5b jumpdest
        .byte 0                         # 5c tload
        .byte 1                         # 5d tstore
        .rept 0xf0 - 0x5e
        .byte 0
        .endr
        .byte 2, 2, 2, 3, 2, 2          # f0 create, f1 call, f2 callcode, f3 return, f4 delegatecall, f5 create2
        .byte 0, 0, 0, 0                # f6-f9
        .byte 2                         # fa staticcall
        .byte 0, 0                      # fb, fc
        .byte 3, 3, 3                   # fd revert, fe invalid, ff selfdestruct

# stack_inputs: the words of the stack each instruction uses (python's
# stack_inputs, from its stack_diffs: dup n n, swap n n + 1, an invalid
# instruction none)
stack_inputs:
        .byte 0, 2, 2, 2, 2, 2, 2, 2, 3, 3, 2, 2, 0, 0, 0, 0   # 00-0f
        .byte 2, 2, 2, 2, 2, 1, 2, 2, 2, 1, 2, 2, 2, 2, 0, 0   # 10-1f
        .byte 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0   # 20-2f
        .byte 0, 1, 0, 0, 0, 1, 0, 3, 0, 3, 0, 1, 4, 0, 3, 1   # 30-3f
        .byte 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0   # 40-4f
        .byte 1, 1, 2, 2, 1, 2, 1, 2, 0, 0, 0, 0, 1, 2, 3, 0   # 50-5f
        .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0   # 60-6f
        .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0   # 70-7f
        .byte 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16   # 80-8f
        .byte 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17   # 90-9f
        .byte 2, 3, 4, 5, 6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0   # a0-af
        .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0   # b0-bf
        .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0   # c0-cf
        .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0   # d0-df
        .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0   # e0-ef
        .byte 3, 7, 7, 2, 6, 4, 0, 0, 0, 0, 6, 0, 0, 2, 0, 1   # f0-ff

        .text

# vm_add_line(line): python's trace() of apply_stack - the line added to the
# trace; a setmem tells what's known of the memory (write_memory)
FUNC vm_add_line
        ENTER
        mov rbx, rdi
        mov r12, [r15 + CTX_VM]
        mov rdi, [r12 + VM_TRACE]
        mov rsi, rbx
        call vec_push
        mov rdi, rbx
        OPCODE_OF_RDI
        cmp eax, OP_SETMEM
        jne 1f
        cmp dword ptr [rbx + N_AUX], 3
        jb 1f
        mov rdi, [r12 + VM_KNOWN]
        mov rsi, [rbx + N_DATA + 8]
        mov rdx, [rbx + N_DATA + 16]
        call write_memory
        mov [r12 + VM_KNOWN], rax
1:      LEAVE
ENDF vm_add_line

# vm_known_add(fact): self.known += (fact,)
FUNC vm_known_add
        ENTER
        mov rbx, [r15 + CTX_VM]
        mov rsi, rdi
        mov rdi, [rbx + VM_KNOWN]
        call tuple_append
        mov [rbx + VM_KNOWN], rax
        LEAVE
ENDF vm_known_add

# vm_rdz_known() -> eax: RETURNDATASIZE_ZERO, ('returndatasize_zero',), is
# known: no call was made yet, no data was returned
FUNC vm_rdz_known
        mov rax, [r15 + CTX_VM]
        mov rax, [rax + VM_KNOWN]
        xor ecx, ecx
1:      cmp ecx, [rax + N_AUX]
        jae 2f
        mov rdx, [rax + N_DATA + rcx*8]
        inc ecx
        test dl, 1
        jnz 1b
        test rdx, rdx
        jz 1b
        cmp dword ptr [rdx + N_KIND], K_TUPLE
        jne 1b
        cmp dword ptr [rdx + N_AUX], 1
        jne 1b
        mov rdx, [rdx + N_DATA]
        test dl, 1
        jnz 1b
        cmp dword ptr [rdx + N_KIND], K_STR
        jne 1b
        mov edx, [rdx + N_AUX]
        and edx, STR_ID_MASK
        cmp edx, OP_RETURNDATASIZE_ZERO
        jne 1b
        mov eax, 1
        ret
2:      xor eax, eax
        ret
ENDF vm_rdz_known

# vm_step(instr, condition) -> eax: 1 when the instruction ends the trace
# (a jump, the end of the execution, a returndatacopy past the data). rbx =
# vm, r12 = instr, r13 = the mnemonic, r14 = the parameter; [rsp..] hold the
# operands.
FUNC vm_step
        ENTER
        sub rsp, 80
        mov rbx, [r15 + CTX_VM]
        mov r12, rdi
        mov [rsp + 72], rsi             # condition
        movzx eax, byte ptr [r12 + IN_OP]
        lea rcx, [rip + step_class]
        movzx ecx, byte ptr [rcx + rax]
        mov [rsp + 64], rcx             # the class
        # handle_jumps: --explain's lines of the instructions that end a node
        cmp ecx, 3
        jne 1f
        test byte ptr [r15 + CTX_VERBOSE], VB_ASM
        jz .Lstep_dispatch
        mov rdi, r12
        call vm_trace_asm
        jmp .Lstep_dispatch
1:      cmp eax, 0x39                   # a codecopy of a switch (see code_switch)
        jne 2f
        mov edi, [r12 + IN_PC]
        call vm_code_switch
        test rax, rax
        jz 2f
        mov rdi, [rbx + VM_TRACE]
        mov rsi, rax
        call vec_push
        jmp .Lstep_finished
        # apply_stack: before an instruction that changes the state, what
        # was read from it gets a variable (snapshot), and what's known of
        # it is forgotten
2:      mov rcx, [rsp + 64]
        test ecx, ecx
        jz 4f
        movzx eax, byte ptr [r12 + IN_OP]
        lea rdx, [rip + evm_op_nodes]
        mov rdi, [rdx + rax*8]
        mov eax, [rdi + N_AUX]
        and eax, STR_ID_MASK
        mov [rsp + 56], rax             # the op's id
        xor esi, esi                    # target
        cmp ecx, 1
        jne 3f
        mov rax, [rbx + VM_STACK]       # sstore, tstore: their slot, the top
        mov rcx, [rax + VEC_LEN]
        test rcx, rcx
        jz 3f                           # (python's IndexError, at the pop below)
        mov rax, [rax + VEC_DATA]
        mov rsi, [rax + rcx*8 - 8]
3:      mov edi, [rsp + 56]
        call vm_snapshot
        mov rdi, [rbx + VM_KNOWN]
        mov esi, 1                      # sstore: ("storage",)
        cmp qword ptr [rsp + 56], OP_SSTORE
        je 31f
        mov esi, 2                      # tstore: ("tload",)
        cmp qword ptr [rsp + 56], OP_TSTORE
        je 31f
        xor esi, esi                    # anything can happen in the callee,
31:     call forget                     # reentering this contract included
        mov [rbx + VM_KNOWN], rax
4:      test byte ptr [r15 + CTX_VERBOSE], VB_ASM
        jz .Lstep_dispatch
        mov rdi, r12
        call vm_trace_asm
.Lstep_dispatch:
        movzx eax, byte ptr [r12 + IN_OP]
        lea rcx, [rip + evm_op_nodes]
        mov r13, [rcx + rax*8]
        mov r14, [r12 + IN_PARAM]
        lea rcx, [rip + step_table]
        jmp [rcx + rax*8]

# exp, eq, div, lt, gt, slt, sgt, mod, xor, signextend, smod, sdiv:
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

# and: a mask when one of them is one - of 256 ** e - 1 when the known
# conditions say what e is (and_op)
.Lop_and:
        VPOP [rsp]
        VPOP rsi
        mov rdi, [rsp]
        mov rdx, [rbx + VM_KNOWN]
        call and_op
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

# mulmod, addmod: (op, a, b, c)
.Lop_mulmod:
        VPOP [rsp]
        VPOP [rsp + 8]
        VPOP rcx
        mov rdx, [rsp + 8]
        mov rsi, [rsp]
        mov rdi, r13
        call mk4
        VPUSH rax
        jmp .Lstep_epilogue

.Lop_shl:
        VPOP [rsp]                       # off
        VPOP [rsp + 8]                   # exp
        call .Lboth_int
        test eax, eax
        jz 1f
        mov rdi, [rsp + 8]              # exp << off (0 for an off of 256 or more)
        mov rsi, [rsp]
        call int_shl
        VPUSH rax
        jmp .Lstep_epilogue
1:      mov rdi, [rsp + 8]
        mov rsi, [rsp]
        call alg_shl_op
        VPUSH rax
        jmp .Lstep_epilogue

.Lop_shr:
        VPOP [rsp]                       # off
        VPOP [rsp + 8]                   # exp
        call .Lboth_int
        test eax, eax
        jz 1f
        mov rdi, [rsp + 8]
        mov rsi, [rsp]
        call int_shr
        VPUSH rax
        jmp .Lstep_epilogue
1:      mov rdi, [rsp + 8]
        mov rsi, [rsp]
        call alg_shr_op
        VPUSH rax
        jmp .Lstep_epilogue

.Lop_sar:
        VPOP [rsp]                       # off
        VPOP [rsp + 8]                   # exp
        call .Lboth_int
        test eax, eax
        jz 1f
        mov rdi, [rsp + 8]
        mov rsi, [rsp]
        call int_sar
        VPUSH rax
        jmp .Lstep_epilogue
1:      # left as it is: no mask copies the sign bit into the bits shifted in
        mov rdx, [rsp + 8]
        mov rsi, [rsp]
        mov rdi, r13
        call mk3
        VPUSH rax
        jmp .Lstep_epilogue

# not, iszero, clz, extcodesize, extcodehash, blockhash, blobhash: (op, x)
.Lop_unary:
        VPOP rsi
        mov rdi, r13
        call mk2
        VPUSH rax
        jmp .Lstep_epilogue

# iszero of a number: the number (the cleanup would make ('iszero', n) a
# ('bool', n), which the algebra doesn't compute with - a jump to
# iszero(0) * 12 + 13)
.Lop_iszero:
        mov rax, [rbx + VM_STACK]
        mov rcx, [rax + VEC_LEN]
        mov rax, [rax + VEC_DATA]
        mov rdi, [rax + rcx*8 - 8]      # (the top: vm_exec saw it's there)
        call is_int
        test eax, eax
        jz .Lop_unary
        VPOP rcx
        xor eax, eax
        cmp rcx, 1                      # (0)
        sete al
        lea rdi, [rax + rax + 1]
        call vm_push
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

# byte i of x, the most significant first - 0 for an i of 32 or more: as
# it is when i isn't known (a mask at an offset computed from it wouldn't
# say that)
.Lop_byte:
        VPOP [rsp]                       # i
        VPOP [rsp + 8]                   # x
        mov rdi, [rsp]
        call is_int
        test eax, eax
        jnz 1f
        mov rdx, [rsp + 8]
        mov rsi, [rsp]
        mov rdi, r13
        call mk3
        VPUSH rax
        jmp .Lstep_epilogue
1:      mov rdi, [rsp]
        mov esi, (32 << 1) | 1
        call int_cmp
        cmp eax, 0
        jl 2f
        mov edi, 1                      # 0
        VPUSH rdi
        jmp .Lstep_epilogue
2:      mov rax, [rsp]                  # off = 248 - 8 i: mask_value(x,
        sar rax, 1                      # 8, off, -off) (of a number, the
        shl rax, 3                      # number)
        mov edx, 248
        sub rdx, rax
        mov rcx, rdx
        neg rcx
        TAG rdx
        TAG rcx
        mov rdi, [rsp + 8]
        mov esi, (8 << 1) | 1
        call mask_value
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
        mov esi, OP_MASK_SHL
        mov edx, 5
        call is_op_n
        test eax, eax
        jz 1f
        mov rax, [rsp]                  # (the address: the low 160 bits of the word, as printed)
        cmp qword ptr [rax + N_DATA + 8], (160 << 1) | 1
        jne 1f
        mov rdi, [rax + N_DATA + 16]
        mov esi, 1
        call py_equal
        test eax, eax
        jz 1f
        mov rax, [rsp]
        mov rdi, [rax + N_DATA + 24]
        mov esi, 1
        call py_equal
        test eax, eax
        jz 1f
        mov rax, [rsp]
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
        VPOP [rsp]                       # sloc
        VPOP r8                          # val
        mov rcx, [rsp]
        LOADS rdi, STORE
        mov esi, (256 << 1) | 1
        mov edx, 1
        call mk5
        VTRACE rax
        jmp .Lstep_epilogue

.Lop_tload:
        VPOP rsi
        mov rdi, r13
        call mk2
        VPUSH rax
        jmp .Lstep_epilogue

.Lop_tstore:
        VPOP rsi                         # key
        mov [rsp], rsi
        VPOP rdx                         # val
        mov rsi, [rsp]
        mov rdi, r13
        call mk3
        VTRACE rax
        jmp .Lstep_epilogue

# a word read from where what's there is known is that, not a variable
.Lop_mload:
        VPOP [rsp]
        mov rdi, [rbx + VM_KNOWN]
        mov rsi, [rsp]
        call read_memory
        test rax, rax
        jz 1f
        VPUSH rax
        jmp .Lstep_epilogue
1:      mov rdi, [rsp]
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
        VPOP rdi                         # memloc
        mov esi, (32 << 1) | 1
        call mk_range
        mov [rsp], rax
        VPOP rdx                         # val
        mov rsi, [rsp]
        LOADS rdi, SETMEM
        call mk3
        VTRACE rax
        jmp .Lstep_epilogue

# the lowest byte of val, into one byte of memory
.Lop_mstore8:
        VPOP rdi                         # memloc
        mov esi, (1 << 1) | 1
        call mk_range
        mov [rsp], rax
        VPOP rdi                         # val: mask_value(val, 8) (of a
        mov esi, (8 << 1) | 1           # number, the number)
        mov edx, 1
        mov ecx, 1
        call mask_value
        mov rdx, rax
        mov rsi, [rsp]
        LOADS rdi, SETMEM
        call mk3
        VTRACE rax
        jmp .Lstep_epilogue

.Lop_mcopy:
        VPOP [rsp]                       # dst
        VPOP [rsp + 8]                   # src
        VPOP [rsp + 16]                  # size
        mov rdi, [rsp + 16]
        mov esi, 1
        call py_equal
        test eax, eax
        jnz .Lstep_epilogue
        mov rdi, [rsp + 8]
        mov rsi, [rsp + 16]
        call mk_mem_range
        mov [rsp + 8], rax
        mov rdi, [rsp]
        mov rsi, [rsp + 16]
        call mk_range
        mov rsi, rax
        mov rdx, [rsp + 8]
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

# the bytes of the code, and zeroes past its end (solc fills a new array
# with them, copying from codesize), for a copy of known place and size
# up to MAX_CODECOPY_SIZE; else ('code.data', pos, len)
.Lop_codecopy:
        VPOP [rsp]                       # mem_pos
        VPOP [rsp + 8]                   # call_pos
        VPOP [rsp + 16]                  # data_len
        mov rdi, [rsp + 8]
        mov rsi, [rsp + 16]
        call code_bytes_value
        test rax, rax
        jnz 1f
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
        VPOP [rsp]                       # mem_pos
        VPOP [rsp + 8]                   # call_pos
        VPOP [rsp + 16]                  # data_len
        mov rdi, [rsp + 16]
        mov esi, 1
        call py_equal
        test eax, eax
        jnz .Lstep_epilogue
        LOADS rdi, CALL_DATA
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

# a copy of more than there is halts, as an invalid opcode does
.Lop_returndatacopy:
        VPOP [rsp]                       # mem_pos
        VPOP [rsp + 8]                   # ret_pos
        VPOP [rsp + 16]                  # data_len
        mov rdi, [rsp + 8]              # end = add_op(ret_pos, data_len)
        mov rsi, [rsp + 16]
        call alg_add2
        mov [rsp + 24], rax
        LOADS rax, RETURNDATASIZE       # size: 0 when no call was made
        mov [rsp + 32], rax
        call vm_rdz_known
        test eax, eax
        jz 1f
        mov qword ptr [rsp + 32], 1
1:      LOADS rdi, LT                   # beyond = ('lt', size, end)
        mov rsi, [rsp + 32]
        mov rdx, [rsp + 24]
        call mk3
        mov [rsp + 40], rax
        mov rdi, [rsp + 32]             # (sizes: far from 2**256)
        mov rsi, [rsp + 24]
        call alg_lt_op
        cmp eax, TRI_CANNOT
        jne 2f
        mov rdi, [rsp + 40]
        mov rsi, [rbx + VM_KNOWN]
        call is_known
2:      cmp eax, TRI_TRUE
        je .Lrdc_beyond
        cmp eax, TRI_FALSE
        je .Lrdc_copy
        # ('if', beyond, [('invalid', 'returndatacopy')], []), and what holds after
        LOADS rdi, INVALID
        lea rsi, [rip + .Ls_returndatacopy]
        call .Lstep_line_c_value
        mov [rsp + 48], rax
        mov edi, 1
        lea rsi, [rsp + 48]
        call mk_list
        mov [rsp + 48], rax
        xor edi, edi
        xor esi, esi
        call mk_list
        mov rcx, rax
        mov rdx, [rsp + 48]
        mov rsi, [rsp + 40]
        LOADS rdi, IF
        call mk4
        VTRACE rax
        mov rdi, [rsp + 40]
        call is_zero
        mov rdi, rax
        call vm_known_add
.Lrdc_copy:
        mov rdi, [rsp + 16]
        mov esi, 1
        call py_equal
        test eax, eax
        jnz .Lstep_epilogue
        LOADS rdi, EXT_CALL_RETURN_DATA
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
.Lrdc_beyond:
        LOADS rdi, INVALID
        lea rsi, [rip + .Ls_returndatacopy]
        call .Lstep_line_c_value
        VTRACE rax
        jmp .Lstep_finished             # (the instruction ended the path)

.Lop_returndatasize:
        call vm_rdz_known
        mov edi, 1                      # 0
        test eax, eax
        jnz 1f
        mov rdi, r13
1:      VPUSH rdi
        jmp .Lstep_epilogue

.Lop_call:
        call vm_handle_call
        jmp .Lstep_epilogue

.Lop_delegatecall:
        VPOP [rsp]                       # gas
        VPOP [rsp + 8]                   # addr
        VPOP [rsp + 24]                  # arg_start
        VPOP [rsp + 32]                  # arg_len
        VPOP [rsp + 40]                  # ret_start
        VPOP [rsp + 48]                  # ret_len
        mov rdi, [rsp + 24]
        mov rsi, [rsp + 32]
        call vm_call_data
        mov r8, rdx
        mov rcx, rax
        mov rdx, [rsp + 8]
        mov rsi, [rsp]
        mov rdi, r13
        call mk5
        VTRACE rax
        LOADS rdi, DELEGATE_RETURN_CODE
        VPUSH rdi
        jmp .Lcall_output

.Lop_callcode:
        VPOP [rsp]                       # gas
        VPOP [rsp + 8]                   # addr
        VPOP [rsp + 16]                  # value
        VPOP [rsp + 24]                  # arg_start
        VPOP [rsp + 32]                  # arg_len
        VPOP [rsp + 40]                  # ret_start
        VPOP [rsp + 48]                  # ret_len
        mov rdi, [rsp + 24]
        mov rsi, [rsp + 32]
        call vm_call_data
        mov r9, rdx
        mov r8, rax
        mov rcx, [rsp + 16]
        mov rdx, [rsp + 8]
        mov rsi, [rsp]
        mov rdi, r13
        call mk6
        VTRACE rax
        LOADS rdi, CALLCODE_RETURN_CODE
        VPUSH rdi
.Lcall_output:
        mov rdi, [rsp + 40]
        mov rsi, [rsp + 48]
        call vm_output_write
        jmp .Lstep_epilogue

.Lop_create:
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
# difficulty, gasprice, coinbase, gaslimit, calldatasize, basefee,
# blobbasefee: the name itself
.Lop_env:
        VPUSH r13
        jmp .Lstep_epilogue

# --- the ones that end the trace (handle_jumps) ---

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
        call .Lstep_push_line
        jmp .Lstep_finished

.Lop_jump:
        VPOP [rsp]                       # target
        mov rax, [rsp]                   # the end of the internal function
        test al, 1                       # decompiled apart (vmrec.s): what's
        jnz 1f                           # on the stack, its results
        call vm_return_address
        cmp rax, [rsp]
        jne 1f
        mov rdi, [rbx + VM_STACK]
        call vec_to_tuple
        mov rsi, rax
        LOADS rdi, LEAVE
        call mk2
        call .Lstep_push_line
        jmp .Lstep_finished
1:      mov rdi, [rbx + VM_STACK]
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
        call .Lstep_push_line
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
        # the selector compared with a function's hash: the function
        # follows the jump where they're equal, the fall through where
        # they differ (a difference: zero when equal)
        mov rdi, [rsp + 8]
        call selector_test
        test rax, rax
        jz 1f
        mov [rsp + 48], rax             # fx_hash
        test edx, edx
        jnz 4f
        mov rsi, [rsp + 40]             # not taken: the fall through
        mov rcx, [rsi + ND_START]
        jmp 5f
4:      # taken: where it jumps - where a jump can't go (no jumpdest), the
        # function is that invalid jump, as it is from where no
        # instruction is (-1)
        mov rdi, [rsp]
        call vm_jumpdest_target
        mov rcx, rax
        mov rsi, [rsp + 24]
5:      mov [rsp + 56], rsi
        mov rdx, rcx
        mov rcx, [rsp + 16]
        mov rsi, [rsp + 48]
        LOADS rdi, FUNCCALL
        call mk4                        # ('funccall', fx_hash, target, tuple_stack)
        mov [rsp + 48], rax
        call vec_new
        mov rcx, [rsp + 56]
        mov [rcx + ND_TRACE], rax
        mov rdi, rax
        mov rsi, [rsp + 48]
        call vec_push
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
        call .Lstep_push_line
        jmp .Lstep_finished
3:      mov rcx, [rsp + 40]
        mov rdx, [rsp + 24]
        mov rsi, [rsp + 8]
        LOADS rdi, IF
        call mk4
        call .Lstep_push_line
        jmp .Lstep_finished

.Lop_return:
        VPOP [rsp]                       # p
        VPOP [rsp + 8]                   # n
        mov rdi, [rsp + 8]
        mov esi, 1
        call py_equal
        test eax, eax
        jz 2f
        cmp byte ptr [r12 + IN_OP], 0xf3
        jne 1f
        # returning nothing is the same as stopping, while ('return', 0)
        # returns a word, 0
        LOADS rdi, STOP
        call mk1
        call .Lstep_push_line
        jmp .Lstep_finished
1:      # likewise, ('revert', 0) reverts with a word, 0
        mov rdi, r13
        lea rsi, [rip + sp_none]
        call mk2
        call .Lstep_push_line
        jmp .Lstep_finished
2:      mov rdi, [rsp]
        mov rsi, [rsp + 8]
        call mk_mem_range
        mov rsi, rax
        mov rdi, r13
        call mk2
        call .Lstep_push_line
        jmp .Lstep_finished

.Lop_selfdestruct:
        VPOP rsi
        mov rdi, r13
        call mk2
        call .Lstep_push_line
        jmp .Lstep_finished

.Lop_stop:
.Lop_invalid:
        mov rdi, r13
        call mk1
        call .Lstep_push_line
        jmp .Lstep_finished

.Lop_unknown:
        LOADS rdi, INVALID
        call mk1
        call .Lstep_push_line
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

# local: are [rsp + 8] and [rsp + 16] (the caller's [rsp], [rsp + 8]) both
# ints? (python's all_concrete: no bool)
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

# local: the line rax added to the trace as it is (handle_jumps')
.Lstep_push_line:
        sub rsp, 8
        mov rdi, [rbx + VM_TRACE]
        mov rsi, rax
        call vec_push
        add rsp, 8
        ret

# local: (op rdi, the string of the C string rsi) -> rax
.Lstep_line_c_value:
        sub rsp, 24
        mov [rsp], rdi
        mov rdi, rsi
        call str_intern_c
        mov rdi, [rsp]
        mov rsi, rax
        call mk2
        add rsp, 24
        ret
ENDF vm_step

        .section .rodata
.Ls_returndatacopy: .asciz "returndatacopy"
        .text

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

# vm_call_data(arg_start, arg_len) -> rax, rdx: python's call_data -
# (selector, params): the data of a call, the arg_len bytes of memory at
# arg_start - its 4 first bytes and the others, where it has 4 bytes or
# more for sure (a number, or a word whose range says so); else (None, all
# of them): the data of a param (x.call(data)) can be shorter, and then it
# has no selector. (None, None): no data.
FUNC vm_call_data
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov rdi, rsi
        mov esi, 1
        call py_equal
        test eax, eax
        jz 1f
        lea rax, [rip + sp_none]
        mov rdx, rax
        LEAVE
1:      mov rdi, r12
        mov esi, (4 << 1) | 1
        call py_equal
        test eax, eax
        jz 2f
        mov rdi, rbx
        mov esi, (4 << 1) | 1
        call mk_mem_range
        lea rdx, [rip + sp_none]
        LEAVE
2:      mov rdi, r12
        call is_int
        test eax, eax
        jz 3f
        mov rdi, r12                    # split = arg_len > 4
        mov esi, (4 << 1) | 1
        call int_cmp
        cmp eax, 0
        jg .Lcd_split
        jmp .Lcd_whole
3:      # (as the word it is: a sum that can't wrap)
        mov rax, [r15 + CTX_VM]
        mov rdi, [rax + VM_KNOWN]
        call known_bounds
        mov rsi, rax
        mov rdi, r12
        xor edx, edx                    # (WORD_TOP)
        call value_range
        mov r13, rax                    # lo
        mov r14, rdx                    # hi
        mov rdi, rax
        mov esi, (4 << 1) | 1
        call int_cmp
        cmp eax, 0
        jl .Lcd_whole
        mov rdi, r14
        mov rsi, [rip + vr_word_top_v]
        call int_cmp
        cmp eax, 0
        jg .Lcd_whole
.Lcd_split:
        mov rdi, rbx
        mov esi, (4 << 1) | 1
        call mk_mem_range
        mov r13, rax
        mov rdi, rbx
        mov esi, (4 << 1) | 1
        call alg_add2
        mov r14, rax
        mov rdi, r12
        mov esi, (4 << 1) | 1
        call alg_sub_op
        mov rsi, rax
        mov rdi, r14
        call mk_mem_range
        mov rdx, rax
        mov rax, r13
        LEAVE
.Lcd_whole:
        mov rdi, rbx
        mov rsi, r12
        call mk_mem_range
        mov rdx, rax
        lea rax, [rip + sp_none]
        LEAVE
ENDF vm_call_data

# vm_output_write(ret_start, ret_len): python's output_write - what a call
# returns, written to the ret_len bytes of memory at ret_start it gives for
# it: min(ret_len, return_data.size) of them (a callee may return less) -
# or, where the memory is known to be zeroes, all of them: the return data
# padded with zeroes. Nothing when ret_len is 0.
FUNC vm_output_write
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov edi, 1
        call alg_lt_op
        cmp eax, TRI_FALSE
        je 9f
        mov rax, [r15 + CTX_VM]
        mov rdi, [rax + VM_KNOWN]
        mov rsi, rbx
        mov rdx, r12
        call known_zeroes
        test eax, eax
        jnz 1f
        LOADS rdi, MIN                  # size = ('min', ret_len, 'returndatasize')
        mov rsi, r12
        LOADS rdx, RETURNDATASIZE
        call mk3
        mov r12, rax
1:      LOADS rdi, EXT_CALL_RETURN_DATA
        mov esi, 1
        mov rdx, r12
        call mk3
        mov r13, rax
        mov rdi, rbx
        mov rsi, r12
        call mk_range
        mov rsi, rax
        mov rdx, r13
        LOADS rdi, SETMEM
        call mk3
        mov rdi, rax
        call vm_add_line
9:      LEAVE
ENDF vm_output_write

        .section .data.rel.ro
        .align 8
# the precompiled contracts 1..8 (4, the identity, is handled apart): name,
# the name of its result, and its counter (VM_PRECOMPILES: "hash" is
# sha256hash's and ripemd160hash's)
precompiled_names:
        .quad 0, 0, 0
        .quad .Ls_ecrecover, .Ls_signer, 0
        .quad .Ls_sha256hash, .Ls_hash, 1
        .quad .Ls_ripemd160hash, .Ls_hash, 1
        .quad 0, 0, 0
        .quad .Ls_bigModExp, .Ls_mod_exp, 2
        .quad .Ls_bn256Add, .Ls_bn_add, 3
        .quad .Ls_bn256ScalarMul, .Ls_bn_scalar_mul, 4
        .quad .Ls_bn256Pairing, .Ls_bn_pairing, 5
        .section .rodata
.Ls_ecrecover:      .asciz "ecrecover"
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
.Ls_result_fmt:     .asciz "%s.result"
.Ls_name_count_fmt: .asciz "%s%ld"
.Ls_copied:         .asciz "copied"
.Ls_identity:       .asciz "identity"
        .text

# vm_handle_call(): call / staticcall (rbx = vm, r12 = instr, r13 = op) -
# python's handle_call: the identity precompile (its return data is what
# it's given: as much of it as there's room for is written), the other
# precompiled contracts (a name for each result: signer, signer2...), and
# the external calls
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
        mov rdi, [rsp + 8]
        mov esi, (4 << 1) | 1
        call py_equal
        test eax, eax
        jnz .Lhc_identity
        mov rax, [rsp + 8]
        test al, 1
        jz .Lhc_call
        sar rax, 1
        cmp rax, 1
        jl .Lhc_call
        cmp rax, 8
        ja .Lhc_call
        imul rax, rax, 24
        lea rcx, [rip + precompiled_names]
        cmp qword ptr [rcx + rax], 0
        je .Lhc_call
        # a precompiled contract
        add rax, rcx
        mov [rsp + 56], rax             # its entry
        mov rdi, [rsp + 24]
        mov rsi, [rsp + 32]
        call mk_mem_range
        mov [rsp + 64], rax             # args
        # the name of the result: base, base2, base3...
        mov rax, [rsp + 56]
        mov rcx, [rax + 16]
        mov rdx, [r15 + CTX_VM]
        lea rdx, [rdx + VM_PRECOMPILES + rcx*8]
        inc qword ptr [rdx]
        mov rcx, [rdx]                  # count
        mov rdi, [rax + 8]
        cmp rcx, 1
        je 2f
        sub rsp, 64                     # f"{base}{count}"
        mov rax, [rsp + 64 + 56]
        mov r8, rcx
        mov rcx, [rax + 8]
        mov rdi, rsp
        mov esi, 64
        lea rdx, [rip + .Ls_name_count_fmt]
        xor eax, eax
        call snprintf@PLT
        mov rdi, rsp
        call str_intern_c
        add rsp, 64
        jmp 3f
2:      call str_intern_c
3:      mov [rsp + 72], rax             # var_name
        mov rax, [rsp + 56]
        mov rdi, [rax]
        call str_intern_c
        mov rdx, rax                    # ('precompiled', var_name, name, args)
        mov rsi, [rsp + 72]
        mov rcx, [rsp + 64]
        LOADS rdi, PRECOMPILED
        call mk4
        VTRACE rax
        # the word it returns, or zeroes (ecrecover of a wrong signature
        # returns nothing): the result, where the memory is of zeroes
        mov rdi, [rsp + 48]
        mov esi, (32 << 1) | 1
        call py_equal
        test eax, eax
        jz 4f
        mov rdi, [rbx + VM_KNOWN]
        mov rsi, [rsp + 40]
        mov edx, (32 << 1) | 1
        call known_zeroes
        test eax, eax
        jz 4f
        mov rsi, [rsp + 72]
        LOADS rdi, VAR
        call mk2
        mov [rsp + 64], rax
        mov rdi, [rsp + 40]
        mov esi, (32 << 1) | 1
        call mk_range
        mov rsi, rax
        mov rdx, [rsp + 64]
        LOADS rdi, SETMEM
        call mk3
        VTRACE rax
        jmp 5f
4:      mov rdi, [rsp + 40]
        mov rsi, [rsp + 48]
        call vm_output_write
5:      # "{}.result"
        mov rax, [rsp + 56]
        mov rcx, [rax]
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
        # its return data is what it's given: ('precompiled', 'copied',
        # 'identity', args), and as much of it as there's room for written
        # (what the next returndatacopy copies)
        mov rdi, [rsp + 24]
        mov rsi, [rsp + 32]
        call mk_mem_range
        mov [rsp + 56], rax
        lea rdi, [rip + .Ls_copied]
        call str_intern_c
        mov [rsp + 64], rax
        lea rdi, [rip + .Ls_identity]
        call str_intern_c
        mov rdx, rax
        mov rsi, [rsp + 64]
        mov rcx, [rsp + 56]
        LOADS rdi, PRECOMPILED
        call mk4
        VTRACE rax
        # size: ret_len when it's arg_len, the least of two numbers, else
        # ('min', ret_len, arg_len)
        mov rax, [rsp + 48]
        mov [rsp + 56], rax
        mov rdi, [rsp + 48]
        mov rsi, [rsp + 32]
        call py_equal
        test eax, eax
        jnz 7f
        mov rdi, [rsp + 48]
        call is_int
        test eax, eax
        jz 6f
        mov rdi, [rsp + 32]
        call is_int
        test eax, eax
        jz 6f
        mov rdi, [rsp + 48]
        mov rsi, [rsp + 32]
        call int_min
        mov [rsp + 56], rax
        jmp 7f
6:      LOADS rdi, MIN
        mov rsi, [rsp + 48]
        mov rdx, [rsp + 32]
        call mk3
        mov [rsp + 56], rax
7:      mov edi, 1                      # 0 < size (or can't tell): written
        mov rsi, [rsp + 56]
        call alg_lt_op
        cmp eax, TRI_FALSE
        je 8f
        mov rdi, [rsp + 24]
        mov rsi, [rsp + 56]
        call mk_mem_range
        mov [rsp + 64], rax
        mov rdi, [rsp + 40]
        mov rsi, [rsp + 56]
        call mk_range
        mov rsi, rax
        mov rdx, [rsp + 64]
        LOADS rdi, SETMEM
        call mk3
        VTRACE rax
8:      LOADS rdi, MEMCOPY_SUCCESS
        VPUSH rdi
        add rsp, 80
        LEAVE
.Lhc_call:
        # (op, gas, addr, wei, selector, params)
        mov rdi, [rsp + 24]
        mov rsi, [rsp + 32]
        call vm_call_data
        mov r9, rdx
        mov r8, rax
        mov rcx, [rsp + 16]
        mov rdx, [rsp + 8]
        mov rsi, [rsp]
        mov rdi, r13
        call mk6
        VTRACE rax
        LOADS rdi, EXT_CALL_SUCCESS
        VPUSH rdi
        mov rdi, [rsp + 40]
        mov rsi, [rsp + 48]
        call vm_output_write
        add rsp, 80
        LEAVE
ENDF vm_handle_call

# exp_size(exp) -> rax: python's exp_size - the leaves of a tuple (a list
# is one)
FUNC exp_size
        STACK_CHECK
        mov eax, 1
        test dil, 1
        jnz 9f
        test rdi, rdi
        jz 9f
        cmp dword ptr [rdi + N_KIND], K_TUPLE
        jne 9f
        ENTER
        mov rbx, rdi
        xor r12d, r12d                  # the sum
        xor r13d, r13d
1:      cmp r13d, [rbx + N_AUX]
        jae 2f
        mov rdi, [rbx + N_DATA + r13*8]
        inc r13d
        call exp_size
        add r12, rax
        jmp 1b
2:      mov rax, r12
        LEAVE
9:      ret
ENDF exp_size

# snap_name(e, names) -> rax: the variable a read was given (snapshot's
# with_names: replace_f_stop's callback), 0 for none
FUNC snap_name
        xor eax, eax
        test dil, 1
        jnz 1f
        test rdi, rdi
        jz 1f
        mov eax, [rdi + N_KIND]
        cmp eax, K_TUPLE
        je 2f
        cmp eax, K_STR
        je 2f
        xor eax, eax
1:      ret
2:      push rdi
        mov rax, rsi
        mov rsi, rdi
        mov rdi, rax
        call emap_get
        pop rdi
        ret
ENDF snap_name

# size_pair_lt((s1, r1), (s2, r2), -) -> eax: s1 < s2 (exp_size's key)
FUNC size_pair_lt
        mov rax, [rdi + N_DATA]
        cmp rax, [rsi + N_DATA]
        setl al
        movzx eax, al
        ret
ENDF size_pair_lt

# vm_snapshot(op, target): python's snapshot - before an instruction that
# changes the state (op: its id; target the slot or key an sstore or a
# tstore writes, else NIL), what was read from it and is still on the stack
# (or in what the memory was written with) gets a variable: afterwards, the
# expression of the read stands for what's there then. All read at once,
# the smaller ones first, the stack's outermost read replaced; a read of a
# few bits says so (('var_bits', var, bits): a size, for where memory is
# written).
FUNC vm_snapshot
        ENTER
        sub rsp, 32
        mov [rsp], rdi                  # op
        mov [rsp + 8], rsi              # target
        mov rbx, [r15 + CTX_VM]
        call vec_new
        mov r12, rax                    # reads
        mov r13, [rbx + VM_STACK]
        xor r14d, r14d
1:      cmp r14, [r13 + VEC_LEN]
        jae 2f
        mov rax, [r13 + VEC_DATA]
        mov rdi, [rax + r14*8]
        inc r14
        mov esi, [rsp]
        mov rdx, [rsp + 8]
        mov rcx, r12
        call changed_reads
        jmp 1b
2:      mov r13, [rbx + VM_KNOWN]       # (and what the memory was written with)
        xor r14d, r14d
3:      cmp r14d, [r13 + N_AUX]
        jae 4f
        mov rdi, [r13 + N_DATA + r14*8]
        inc r14d
        mov rsi, rdi
        OPCODE_OF_RDI
        cmp eax, OP_MEMORY
        jne 3b
        mov rdi, [rsi + N_DATA + 24]
        lea rax, [rip + sp_none]
        cmp rdi, rax
        je 3b
        mov esi, [rsp]
        mov rdx, [rsp + 8]
        mov rcx, r12
        call changed_reads
        jmp 3b
4:      cmp qword ptr [r12 + VEC_LEN], 0
        je .Lsn_done
        # sorted by exp_size (stable): (size, read) pairs
        xor r14d, r14d
5:      cmp r14, [r12 + VEC_LEN]
        jae 6f
        mov rax, [r12 + VEC_DATA]
        mov r13, [rax + r14*8]
        mov rdi, r13
        call exp_size
        lea rdi, [rax + rax + 1]
        mov rsi, r13
        call mk2
        mov rcx, [r12 + VEC_DATA]
        mov [rcx + r14*8], rax
        inc r14
        jmp 5b
6:      mov rdi, r12
        lea rsi, [rip + size_pair_lt]
        xor edx, edx
        call py_sort
        call emap_new
        mov [rsp + 16], rax             # names
        xor r14d, r14d
7:      cmp r14, [r12 + VEC_LEN]
        jae 8f
        mov rax, [r12 + VEC_DATA]
        mov rax, [rax + r14*8]
        mov r13, [rax + N_DATA + 8]     # r
        inc r14
        call vm_new_var_name
        mov [rsp + 24], rax
        mov rdi, r13                    # ('setvar', name, with_names(r))
        lea rsi, [rip + snap_name]
        mov rdx, [rsp + 16]
        call replace_f_stop
        mov rdx, rax
        mov rsi, [rsp + 24]
        LOADS rdi, SETVAR
        call mk3
        mov rdi, rax
        call vm_add_line
        LOADS rdi, VAR
        mov rsi, [rsp + 24]
        call mk2
        mov rdi, [rsp + 16]
        mov rsi, r13
        mov rdx, rax
        call emap_put
        # what it was is as small as that (a size, say): for where memory
        # is written (see bound), not to decide conditions
        mov rdi, r13
        xor esi, esi
        call max_value_bits
        cmp rax, (128 << 1) | 1
        jg 7b
        mov [rsp + 8], rax              # (the target: not needed any more)
        LOADS rdi, VAR
        mov rsi, [rsp + 24]
        call mk2
        mov rdx, [rsp + 8]
        mov rsi, rax
        LOADS rdi, VAR_BITS
        call mk3
        mov rdi, rax
        call vm_known_add
        jmp 7b
8:      # the stack, and the values of what's known of the memory, with the names
        mov r13, [rbx + VM_STACK]
        xor r14d, r14d
9:      cmp r14, [r13 + VEC_LEN]
        jae 10f
        mov rax, [r13 + VEC_DATA]
        mov rdi, [rax + r14*8]
        lea rsi, [rip + snap_name]
        mov rdx, [rsp + 16]
        call replace_f_stop
        mov rcx, [r13 + VEC_DATA]
        mov [rcx + r14*8], rax
        inc r14
        jmp 9b
10:     mov qword ptr [rbx + VM_CLEAN], 0       # (the stack changed: cleaned up again)
        call vec_new
        mov r12, rax
        mov r13, [rbx + VM_KNOWN]
        xor r14d, r14d
11:     cmp r14d, [r13 + N_AUX]
        jae 13f
        mov rdi, [r13 + N_DATA + r14*8]
        inc r14d
        mov rsi, rdi
        OPCODE_OF_RDI
        cmp eax, OP_MEMORY
        jne 12f
        mov rdi, [rsi + N_DATA + 24]
        lea rax, [rip + sp_none]
        cmp rdi, rax
        je 12f
        mov [rsp + 24], rsi
        lea rsi, [rip + snap_name]
        mov rdx, [rsp + 16]
        call replace_f_stop
        mov rcx, rax
        mov rax, [rsp + 24]
        mov rsi, [rax + N_DATA + 8]
        mov rdx, [rax + N_DATA + 16]
        LOADS rdi, MEMORY
        call mk4
        mov rsi, rax
12:     mov rdi, r12
        call vec_push
        jmp 11b
13:     mov rdi, r12
        call vec_to_tuple
        mov [rbx + VM_KNOWN], rax
.Lsn_done:
        add rsp, 32
        LEAVE
ENDF vm_snapshot

# vm_code_switch(pc) -> rax: python's code_switch - a codecopy of a few
# bytes of the code from where one of few numbers says, x % n (Vyper's
# dispatcher, 0.3.10 on, copies from a table where the code of a selector
# is, and jumps there): one path for each of the values, where the copy
# is from a known place - the line ('if', x % n == k0, node, rest), rest
# the ifs of the other values, made here, the last without its test. 0
# when it isn't that, or when x % n is known (then the stack is the one
# where it's that value).
FUNC vm_code_switch
        ENTER
        sub rsp, 64
        .set CS_PC, 0
        .set CS_M, 8
        .set CS_VALUES, 16
        .set CS_CASES, 24
        .set CS_NODES, 32               # (cond, node) pairs, a vec of 2 per case
        .set CS_STACK, 40               # the stack, a tuple
        .set CS_TMP, 48
        mov rax, rdi
        TAG rax
        mov [rsp + CS_PC], rax
        mov rbx, [r15 + CTX_VM]
        mov r12, [rbx + VM_STACK]
        mov rcx, [r12 + VEC_LEN]
        cmp rcx, 3
        jb .Lcs_none
        mov rax, [r12 + VEC_DATA]
        lea r13, [rax + rcx*8 - 24]     # size, code_pos, mem_pos
        mov rdi, [r13 + 16]             # mem_pos: an int
        call is_int
        test eax, eax
        jz .Lcs_none
        mov rdi, [r13]                  # size: an int, at most 32
        call is_int
        test eax, eax
        jz .Lcs_none
        mov rdi, [r13]
        mov esi, (32 << 1) | 1
        call int_cmp
        cmp eax, 0
        jg .Lcs_none
        mov rdi, [r13 + 8]              # code_pos: not an int
        call is_int
        test eax, eax
        jnz .Lcs_none
        mov rdi, [r13 + 8]
        call switch_values
        test rax, rax
        jz .Lcs_none
        mov [rsp + CS_M], rax
        mov [rsp + CS_VALUES], rdx
        # the cases: the values not known to be other than it
        call vec_new
        mov [rsp + CS_CASES], rax
        xor r14d, r14d
1:      mov rax, [rsp + CS_VALUES]
        cmp r14, [rax + VEC_LEN]
        jae 2f
        mov rax, [rax + VEC_DATA]
        mov r13, [rax + r14*8]
        inc r14
        LOADS rdi, EQ
        mov rsi, [rsp + CS_M]
        mov rdx, r13
        call mk3
        mov rdi, rax
        mov rsi, [rbx + VM_KNOWN]
        call is_known
        cmp eax, TRI_FALSE
        je 1b
        mov rdi, [rsp + CS_CASES]
        mov rsi, r13
        call vec_push
        jmp 1b
2:      # a fact ('eq', x % n, k) says which (the last one)
        mov r13, [rbx + VM_KNOWN]
        xor r14d, r14d
3:      cmp r14d, [r13 + N_AUX]
        jae 4f
        mov rdi, [r13 + N_DATA + r14*8]
        inc r14d
        mov rsi, rdi
        mov [rsp + CS_TMP], rdi
        mov esi, OP_EQ
        mov edx, 3
        call is_op_n
        test eax, eax
        jz 3b
        mov rax, [rsp + CS_TMP]
        mov rcx, [rsp + CS_M]
        cmp [rax + N_DATA + 8], rcx
        jne 3b
        mov rdi, [rax + N_DATA + 16]
        call int_or_bool
        test rax, rax
        jz 3b
        mov rax, [rsp + CS_CASES]
        mov qword ptr [rax + VEC_LEN], 0
        mov rdi, rax
        mov rsi, [rsp + CS_TMP]
        mov rsi, [rsi + N_DATA + 16]
        call vec_push
        jmp 3b
4:      mov rdi, [r12 + VEC_LEN]        # the stack as it is: a tuple
        mov rsi, [r12 + VEC_DATA]
        call mk_tuple
        mov [rsp + CS_STACK], rax
        mov rax, [rsp + CS_CASES]
        cmp qword ptr [rax + VEC_LEN], 2
        jae 6f
        cmp qword ptr [rax + VEC_LEN], 0
        je .Lcs_none
        # one case: the stack where x % n is it
        mov rax, [rax + VEC_DATA]
        mov rdi, [rax]
        call .Lcs_value
        mov rdi, [rbx + VM_STACK]
        mov qword ptr [rdi + VEC_LEN], 0
        mov rsi, rax
        call vec_extend_seq
        mov qword ptr [rbx + VM_CLEAN], 0
        jmp .Lcs_none
6:      # a node for each case, where the copy is from a known place
        call vec_new
        mov [rsp + CS_NODES], rax
        xor r14d, r14d
7:      mov rax, [rsp + CS_CASES]
        cmp r14, [rax + VEC_LEN]
        jae 8f
        mov rax, [rax + VEC_DATA]
        mov r13, [rax + r14*8]          # k
        inc r14
        LOADS rdi, EQ
        mov rsi, [rsp + CS_M]
        mov rdx, r13
        call mk3
        mov r13, rax                    # cond
        mov rdi, [rsp + CS_NODES]
        mov rsi, rax
        call vec_push
        mov rax, [rsp + CS_CASES]
        mov rax, [rax + VEC_DATA]
        mov rdi, [rax + r14*8 - 8]
        call .Lcs_value
        mov [rsp + CS_TMP], rax         # the stack where it's k
        mov rdi, [rbx + VM_KNOWN]
        mov rsi, r13
        call tuple_append
        mov r8, rax
        mov rdi, [rsp + CS_PC]
        mov esi, 1
        mov rdx, [rsp + CS_TMP]
        mov rcx, r13
        call node_new
        mov qword ptr [rax + ND_SWITCHED], 1    # (not to be merged again)
        mov rdi, [rsp + CS_NODES]
        mov rsi, rax
        call vec_push
        jmp 7b
8:      # rest: the last case's node; the ifs of the cases between, from the end
        mov rax, [rsp + CS_NODES]
        mov rcx, [rax + VEC_LEN]
        mov rax, [rax + VEC_DATA]
        mov r13, [rax + rcx*8 - 8]      # rest
        sub rcx, 4                      # the one before the last
9:      cmp rcx, 2
        jb 10f
        mov [rsp + CS_TMP], rcx
        mov rax, [rsp + CS_NODES]
        mov rax, [rax + VEC_DATA]
        mov rdx, [rax + rcx*8]          # cond
        mov rcx, [rax + rcx*8 + 8]      # n
        mov rsi, rdx
        mov rdx, rcx
        mov rcx, r13
        LOADS rdi, IF
        call mk4
        mov [rsp + CS_VALUES], rax      # ('if', cond, n, rest)
        LOADS rdi, SWITCH               # start = ('switch', pc, k)
        mov rsi, [rsp + CS_PC]
        mov rax, [rsp + CS_NODES]
        mov rax, [rax + VEC_DATA]
        mov rcx, [rsp + CS_TMP]
        mov rdx, [rax + rcx*8]
        mov rdx, [rdx + N_DATA + 16]
        call mk3
        mov rdi, rax
        mov esi, 1
        mov rdx, [rsp + CS_STACK]
        lea rcx, [rip + sp_true]
        mov r8, [rbx + VM_KNOWN]
        call node_new
        mov r13, rax
        call vec_new
        mov [r13 + ND_TRACE], rax
        mov rdi, rax
        mov rsi, [rsp + CS_VALUES]
        call vec_push
        mov rcx, [rsp + CS_TMP]
        sub rcx, 2
        jmp 9b
10:     mov rax, [rsp + CS_NODES]
        mov rax, [rax + VEC_DATA]
        mov rsi, [rax]
        mov rdx, [rax + 8]
        mov rcx, r13
        LOADS rdi, IF
        call mk4
        add rsp, 64
        LEAVE
.Lcs_none:
        xor eax, eax
        add rsp, 64
        LEAVE

# local: the stack where x % n is k (rdi) -> rax, a tuple:
# [simplify(replace(e, m, k)) for e in stack]
.Lcs_value:
        push r12
        push r13
        push r14
        sub rsp, 16
        mov r12, rdi                    # k
        call vec_new
        mov r13, rax
        xor r14d, r14d
1:      mov rax, [rsp + 40 + 8 + CS_STACK]
        cmp r14d, [rax + N_AUX]
        jae 2f
        mov rdi, [rax + N_DATA + r14*8]
        inc r14d
        mov rsi, [rsp + 40 + 8 + CS_M]
        mov rdx, r12
        call replace
        mov rdi, rax
        call alg_simplify
        mov rdi, r13
        mov rsi, rax
        call vec_push
        jmp 1b
2:      mov rdi, r13
        call vec_to_tuple
        add rsp, 16
        pop r14
        pop r13
        pop r12
        ret
ENDF vm_code_switch

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
# integer, and zeroes past its end (solc fills a new array with them,
# copying from codesize), when both are ints, 0 <= pos and 0 <= len <=
# MAX_CODECOPY_SIZE (more would be unreadable anyway: python's limit of
# the digits of a number it prints); else 0
FUNC code_bytes_value
        ENTER
        sub rsp, 16
        test dil, 1
        jz .Lcb_no
        test sil, 1
        jz .Lcb_no
        sar rdi, 1
        sar rsi, 1
        js .Lcb_no
        test rdi, rdi
        js .Lcb_no
        cmp rsi, MAX_CODECOPY_SIZE
        jg .Lcb_no
        mov rbx, rdi                    # pos
        mov r12, rsi                    # len
        test r12, r12
        jz .Lcb_zero
        mov rax, [r15 + CTX_VM]
        mov r13, [rax + VM_LOADER]
        mov rdi, r12
        call xcalloc_bytes
        mov r14, rax
        # the bytes pos .. min(pos + len, codelen), then zeroes
        mov rcx, [r13 + LD_CODELEN]
        cmp rbx, rcx
        jae 1f
        lea rdx, [rbx + r12]
        cmp rdx, rcx
        cmova rdx, rcx
        sub rdx, rbx
        mov rdi, r14
        mov rsi, [r13 + LD_CODE]
        add rsi, rbx
        call memcpy@PLT
1:      mov rdi, r14
        mov rsi, r12
        call mk_int_bytes_be
        mov [rsp], rax
        mov rdi, r14
        call free@PLT
        mov rax, [rsp]
        add rsp, 16
        LEAVE
.Lcb_zero:
        mov eax, 1                      # (the small int 0)
        add rsp, 16
        LEAVE
.Lcb_no:
        xor eax, eax
        add rsp, 16
        LEAVE
ENDF code_bytes_value

# xcalloc_bytes(n) -> rax: n zeroed bytes (malloc'ed)
FUNC xcalloc_bytes
        ENTER
        mov esi, 1
        call xcalloc
        LEAVE
ENDF xcalloc_bytes

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
