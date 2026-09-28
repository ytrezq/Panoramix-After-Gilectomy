# Nodes of the symbolic execution (port of vm.py's Node): a point in the
# execution and the trace from there to the next jump. See defs.inc for
# the fields. A node is a value (K_VMNODE) so that the trace lines that
# refer to one - ('jump', node), ('if', cond, node, node), ('label', node,
# vars), ('goto', node, setvars) - are ordinary hash-consed tuples.

.include "defs.inc"

        .section .rodata
.Ls_node_open:      .asciz "Node("
.Ls_didnt_finish:   .asciz "decompilation didn't finish"
.Ls_question:       .asciz "?"
.Ls_ld:             .asciz "%ld"

        .text

# node_new(start, safe, stack, condition, known) -> rax
FUNC node_new
        ENTER
        sub rsp, 48
        mov [rsp], rdi                  # start
        mov [rsp + 8], rsi              # safe
        mov [rsp + 16], rdx             # stack (tuple)
        mov [rsp + 24], rcx             # condition
        mov [rsp + 32], r8              # known
        mov rax, [r15 + CTX_VM]
        inc qword ptr [rax + VM_NODE_COUNT]
        mov edi, ND_SIZEOF
        call arena_alloc
        mov rbx, rax
        mov dword ptr [rbx + N_KIND], K_VMNODE
        mov dword ptr [rbx + N_AUX], 0
        mov rdi, rbx
        call hash_mix                   # identity: nodes are never equal
        mov rcx, HF_MASK
        not rcx
        and rax, rcx
        mov [rbx + N_HASH], rax
        mov qword ptr [rbx + ND_TRACE], 0
        mov qword ptr [rbx + ND_PREV], 0
        call vec_new
        mov [rbx + ND_NEXT], rax
        mov rax, [rsp]
        mov [rbx + ND_START], rax
        mov rax, [rsp + 8]
        mov [rbx + ND_SAFE], rax
        mov rax, [rsp + 16]
        mov [rbx + ND_STACK], rax
        mov qword ptr [rbx + ND_DEPTH], 0
        mov qword ptr [rbx + ND_LABEL], 0
        mov rax, [rsp + 24]
        mov [rbx + ND_CONDITION], rax
        mov rax, [rsp + 32]
        mov [rbx + ND_KNOWN], rax
        mov qword ptr [rbx + ND_MERGED], 0
        mov qword ptr [rbx + ND_BEGIN_VARS], 0
        # jd = (start, len(stack), jump_dests(stack)): what identifies the
        # point of execution when looking for loops
        mov rdi, [rsp + 16]
        call stack_jump_dests
        mov rdx, rax
        mov rdi, [rsp]
        mov rax, [rsp + 16]
        mov esi, [rax + N_AUX]
        TAG rsi
        call mk3
        mov [rbx + ND_JD], rax
        mov rax, rbx
        add rsp, 48
        LEAVE
ENDF node_new

# stack_jump_dests(stack) -> tuple of the decimal strings of the stack
# values that are jumpdests (or look like ones: 2000 < v < 5000)
FUNC stack_jump_dests
        ENTER
        mov rbx, rdi
        call vec_new
        mov r12, rax
        xor r13d, r13d
1:      cmp r13d, [rbx + N_AUX]
        jae 5f
        mov rdi, [rbx + N_DATA + r13*8]
        test dil, 1
        jz 4f
        sar rdi, 1
        mov r14, rdi
        cmp rdi, 2000
        jle 2f
        cmp rdi, 5000
        jl 3f
2:      mov rsi, rdi
        mov rdi, [r15 + CTX_VM]
        mov rdi, [rdi + VM_LOADER]
        call loader_is_jumpdest
        test eax, eax
        jz 4f
3:      mov rdi, r14
        call str_of_int
        mov rdi, r12
        mov rsi, rax
        call vec_push
4:      inc r13
        jmp 1b
5:      mov rdi, r12
        call vec_to_tuple
        LEAVE
ENDF stack_jump_dests

# str_of_int(i64) -> rax: the interned decimal string. The jumpdests on
# the stack are made strings for every node's jd: those of the numbers
# below STR_OF_INT_CACHED are kept (the interned strings live as long as
# the process; two threads filling the same slot write the same string)
        .set STR_OF_INT_CACHED, 32768
FUNC str_of_int
        cmp rdi, STR_OF_INT_CACHED
        jae 1f                          # (a negative one too: unsigned)
        lea rax, [rip + str_of_int_cache]
        mov rax, [rax + rdi*8]
        test rax, rax
        jz 1f
        ret
1:      ENTER
        sub rsp, 32
        mov rbx, rdi
        mov rcx, rdi
        mov rdi, rsp
        mov esi, 32
        lea rdx, [rip + .Ls_ld]
        xor eax, eax
        call snprintf@PLT
        mov rdi, rsp
        mov esi, eax
        call str_intern
        cmp rbx, STR_OF_INT_CACHED
        jae 2f
        lea rcx, [rip + str_of_int_cache]
        mov [rcx + rbx*8], rax
2:      add rsp, 32
        LEAVE
ENDF str_of_int

        .bss
        .p2align 4
str_of_int_cache:   .zero STR_OF_INT_CACHED * 8
        .text

# str_of_value(v) -> rax: the interned python repr of a value (str(jd[0])
# for a symbolic jump target)
FUNC str_of_value
        ENTER
        mov r12, rdi
        call sb_new
        mov rbx, rax
        mov rdi, rax
        mov rsi, r12
        call value_print
        mov rdi, [rbx + SB_BUF]
        mov rsi, [rbx + SB_LEN]
        call str_intern
        mov r12, rax
        mov rdi, rbx
        call sb_free
        mov rax, r12
        LEAVE
ENDF str_of_value

# node_touch(node): the node changed - its trace, its children, its label,
# merged - so it and the nodes above it take the current generation
# (VM_GEN): merge_visit's answer for a subtree holds while the subtree's
# root keeps the stamp it had then. A new generation begins at the first
# change after an answer was remembered; a node already of the current
# one has its ancestors of it too (the walk up stops there).
FUNC node_touch
        mov rax, [r15 + CTX_VM]
        test rax, rax
        jz 3f
        mov rcx, [rax + VM_GEN]
        cmp qword ptr [rax + VM_VISITED], 0
        je 1f
        inc rcx
        mov [rax + VM_GEN], rcx
        mov qword ptr [rax + VM_VISITED], 0
1:      test rdi, rdi
        jz 3f
        cmp [rdi + ND_STAMP], rcx
        je 3f
        mov [rdi + ND_STAMP], rcx
        mov rdi, [rdi + ND_PREV]
        jmp 1b
3:      ret
ENDF node_touch

# node_set_prev(node, prev): hang node below prev
FUNC node_set_prev
        ENTER
        mov rbx, rsi
        mov [rdi + ND_PREV], rsi
        mov rax, [rsi + ND_DEPTH]
        inc rax
        mov [rdi + ND_DEPTH], rax
        mov rax, rdi
        mov rdi, [rsi + ND_NEXT]
        mov rsi, rax
        call vec_push
        mov rdi, rbx                    # (prev's children changed)
        call node_touch
        LEAVE
ENDF node_set_prev

# node_history(node) -> rax: the nearest ancestor at the same point of
# execution (python: node.history[node.jd]), or 0
FUNC node_history
        mov rax, [rdi + ND_JD]
        mov rcx, [rdi + ND_PREV]
1:      test rcx, rcx
        jz 2f
        cmp [rcx + ND_JD], rax
        je 3f
        mov rcx, [rcx + ND_PREV]
        jmp 1b
2:      xor eax, eax
        ret
3:      mov rax, rcx
        ret
ENDF node_history

# node_set_label(node, loop_dest, vars, stack): node becomes the body of
# the loop whose head is loop_dest
FUNC node_set_label
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov [rbx + ND_LABEL], r12
        mov [r12 + ND_BEGIN_VARS], rdx
        mov [rbx + ND_STACK], rcx
        # loop_dest.trace = [('jump', node)]; loop_dest.next = []
        call vec_new
        mov r13, rax
        LOADS rdi, JUMP
        mov rsi, rbx
        call mk2
        mov rdi, r13
        mov rsi, rax
        call vec_push
        mov [r12 + ND_TRACE], r13
        call vec_new
        mov [r12 + ND_NEXT], rax
        mov rdi, rbx
        mov rsi, r12
        call node_set_prev
        # what was learned during the first iteration about things that
        # can change doesn't hold for the next ones
        mov rdi, [rbx + ND_KNOWN]
        call forget_volatile
        mov [rbx + ND_KNOWN], rax
        mov rdi, rbx                    # (a label now, below loop_dest)
        call node_touch
        LEAVE
ENDF node_set_label

# node_run(node): symbolic execution from the node to the next jump
FUNC node_run
        ENTER
        mov rbx, rdi
        mov rdi, [rbx + ND_START]
        mov rsi, [rbx + ND_SAFE]
        mov rdx, [rbx + ND_STACK]
        mov rcx, [rbx + ND_CONDITION]
        mov r8, [rbx + ND_KNOWN]
        call vm_exec
        mov [rbx + ND_TRACE], rax
        mov r13, rax
        mov rdi, rbx
        call node_touch
        mov rax, r13
        # the nodes the trace ends with are the children
        mov rcx, [rax + VEC_LEN]
        mov rax, [rax + VEC_DATA]
        mov r12, [rax + rcx*8 - 8]      # the last line
        mov rdi, r12
        OPCODE_OF_RDI
        cmp eax, OP_JUMP
        je 1f
        cmp eax, OP_IF
        je 2f
        LEAVE
1:      mov rdi, [r12 + N_DATA + 8]
        mov rsi, rbx
        call node_set_prev
        LEAVE
2:      mov rdi, [r12 + N_DATA + 16]
        mov rsi, rbx
        call node_set_prev
        mov rdi, [r12 + N_DATA + 24]
        mov rsi, rbx
        call node_set_prev
        LEAVE
ENDF node_run

# find_nodes(root, pred, arg) -> vec: the nodes below root (itself
# included) for which pred(node, arg) is true, in depth-first order
FUNC find_nodes
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        call vec_new
        mov [rsp], rax
        mov rdi, rbx
        mov rsi, r12
        mov rdx, r13
        mov rcx, rax
        call find_nodes_into
        mov rax, [rsp]
        add rsp, 16
        LEAVE
ENDF find_nodes

# find_nodes_into(root, pred, arg, out): find_nodes' nodes appended to
# the vec out. The stack of the walk is the VM's, reused: python's lists
# are garbage when the call returns, the arena's would stay (the rounds
# of a long VM run called it thousands of times over thousands of nodes).
# The walk runs over every node at every round: its stack is handled
# here, and the predicate the rounds ask the most (pred_unexpanded) too.
FUNC find_nodes_into
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi                    # pred
        mov r13, rdx                    # arg
        mov [rsp], rcx                  # out
        mov rax, [r15 + CTX_VM]
        test rax, rax
        jz 5f
        mov r14, [rax + VM_SCR_VISIT]
        test r14, r14
        jnz 6f
        call vec_new
        mov r14, rax
        mov rax, [r15 + CTX_VM]
        mov [rax + VM_SCR_VISIT], r14
6:      mov qword ptr [r14 + VEC_LEN], 0
        jmp 7f
5:      call vec_new
        mov r14, rax                    # to_visit
7:      mov rdi, r14
        mov rsi, rbx
        call vec_push
.Lfn_pop:
        mov rax, [r14 + VEC_LEN]
        test rax, rax
        jz .Lfn_done
        dec rax
        mov [r14 + VEC_LEN], rax
        mov rcx, [r14 + VEC_DATA]
        mov rbx, [rcx + rax*8]          # n = to_visit.pop()
        lea rax, [rip + pred_unexpanded]
        cmp r12, rax
        jne 1f
        cmp qword ptr [rbx + ND_TRACE], 0
        jne .Lfn_next
        jmp 2f
1:      mov rdi, rbx
        mov rsi, r13
        call r12
        test eax, eax
        jz .Lfn_next
2:      mov rdi, [rsp]
        mov rsi, rbx
        call vec_push
.Lfn_next:
        # to_visit.extend(reversed(n.next))
        mov rax, [rbx + ND_NEXT]
        mov rcx, [rax + VEC_LEN]
        test rcx, rcx
        jz .Lfn_pop
        mov rdx, [r14 + VEC_LEN]
        add rdx, rcx
        cmp rdx, [r14 + VEC_CAP]
        ja .Lfn_grow
        mov rsi, [rax + VEC_DATA]
        mov rdi, [r14 + VEC_DATA]
        mov rdx, [r14 + VEC_LEN]
        lea r8, [rdx + rcx]
        mov [r14 + VEC_LEN], r8
3:      dec rcx
        mov r9, [rsi + rcx*8]
        mov [rdi + rdx*8], r9
        inc rdx
        test rcx, rcx
        jnz 3b
        jmp .Lfn_pop
.Lfn_grow:
        # (no room: one by one, vec_push growing the stack)
        mov [rsp + 8], rcx
4:      mov rcx, [rsp + 8]
        test rcx, rcx
        jz .Lfn_pop
        dec rcx
        mov [rsp + 8], rcx
        mov rax, [rbx + ND_NEXT]
        mov rdx, [rax + VEC_DATA]
        mov rsi, [rdx + rcx*8]
        mov rdi, r14
        call vec_push
        jmp 4b
.Lfn_done:
        add rsp, 16
        LEAVE
ENDF find_nodes_into

# the predicates
FUNC pred_unexpanded
        xor eax, eax
        cmp qword ptr [rdi + ND_TRACE], 0
        sete al
        ret
ENDF pred_unexpanded

FUNC pred_any
        mov eax, 1
        ret
ENDF pred_any

# pred_goto_back(node, label): the node's trace ends with a goto to the
# label or to its loop head
FUNC pred_goto_back
        mov rax, [rdi + ND_TRACE]
        test rax, rax
        jz 1f
        mov rcx, [rax + VEC_LEN]
        test rcx, rcx
        jz 1f
        mov rax, [rax + VEC_DATA]
        mov rdi, [rax + rcx*8 - 8]
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call opcode_of
        cmp eax, OP_GOTO
        jne 2f
        mov rax, [rbx + N_DATA + 8]
        cmp rax, r12
        je 3f
        cmp rax, [r12 + ND_LABEL]
        je 3f
2:      xor eax, eax
        LEAVE
3:      mov eax, 1
        LEAVE
1:      xor eax, eax
        ret
ENDF pred_goto_back

# node_make_trace(node) -> list: the decompiled trace from the node on.
# The nodes form long chains (a jump at the end of each), walked in a loop;
# the recursion is only as deep as the ifs are nested.
FUNC node_make_trace
        STACK_CHECK
        ENTER
        sub rsp, 16
        mov rbx, rdi
        call vec_new
        mov r12, rax                    # res
.Lmt_node:
        test rbx, rbx
        jz .Lmt_done
        mov rdi, rbx
        mov rsi, r12
        call node_begin_trace
        mov r13, [rbx + ND_TRACE]
        test r13, r13
        jz .Lmt_done
        mov qword ptr [rsp], 0          # next node
        xor r14d, r14d
1:      cmp r14, [r13 + VEC_LEN]
        jae 4f
        mov rax, [r13 + VEC_DATA]
        mov rdi, [rax + r14*8]
        mov [rsp + 8], rdi              # line
        OPCODE_OF_RDI
        cmp eax, OP_JUMP
        jne 2f
        mov rdi, [rsp + 8]
        mov rdi, [rdi + N_DATA + 8]
        call is_vmnode
        test eax, eax
        jz 3f
        # always the last line
        mov rdi, [rsp + 8]
        mov rdi, [rdi + N_DATA + 8]
        mov [rsp], rdi
        jmp 5f
2:      cmp eax, OP_IF
        jne 3f
        mov rdi, [rsp + 8]
        mov rdi, [rdi + N_DATA + 16]
        call is_vmnode
        test eax, eax
        jz 3f
        # the last line, unless the paths merge again after the if - see
        # merge_branches - in which case a jump to the merged node follows
        mov rdi, [rsp + 8]
        mov rdi, [rdi + N_DATA + 16]
        call node_make_trace
        mov rbx, rax                    # (rbx is reloaded below)
        mov rdi, [rsp + 8]
        mov rdi, [rdi + N_DATA + 24]
        call node_make_trace
        mov rcx, rax
        mov rdx, rbx
        mov rax, [rsp + 8]
        mov rsi, [rax + N_DATA + 8]
        LOADS rdi, IF
        call mk4
        mov rdi, r12
        mov rsi, rax
        call vec_push
        jmp 5f
3:      mov rdi, r12
        mov rsi, [rsp + 8]
        call vec_push
5:      inc r14
        jmp 1b
4:      mov rbx, [rsp]
        jmp .Lmt_node
.Lmt_done:
        mov rdi, r12
        call vec_to_list
        add rsp, 16
        LEAVE
ENDF node_make_trace

# is_vmnode(v) -> eax
FUNC is_vmnode
        xor eax, eax
        test dil, 1
        jnz 1f
        test rdi, rdi
        jz 1f
        cmp dword ptr [rdi + N_KIND], K_VMNODE
        sete al
1:      ret
ENDF is_vmnode

# node_begin_trace(node, out): what goes before the node's own lines
FUNC node_begin_trace
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        cmp qword ptr [rbx + ND_TRACE], 0
        jne 1f
        lea rdi, [rip + .Ls_didnt_finish]
        call str_intern_c
        mov rsi, rax
        LOADS rdi, UNDEFINED
        call mk2
        mov rdi, r12
        mov rsi, rax
        call vec_push
        add rsp, 16
        LEAVE
1:      mov r13, [r15 + CTX_VM]
        cmp qword ptr [r13 + VM_JUST_FDESTS], 0
        je .Lbt_label
        # the loader looks for the jumpdests to find the default function
        cmp qword ptr [rbx + ND_SAFE], 0
        je 2f
        mov rdi, [r13 + VM_LOADER]
        mov rsi, [rbx + ND_START]
        test sil, 1
        jz 2f
        sar rsi, 1
        call loader_instr_at
        test rax, rax
        jz 2f
        cmp byte ptr [rax + IN_OP], 0x5b
        jne 2f
        call .Lpush_jd
        jmp .Lbt_label
2:      # trace != [('revert', 0)]
        mov r14, [rbx + ND_TRACE]
        cmp qword ptr [r14 + VEC_LEN], 1
        jne 3f
        LOADS rdi, REVERT
        mov esi, 1
        call mk2
        mov rcx, [r14 + VEC_DATA]
        cmp [rcx], rax
        je .Lbt_label
3:      mov rax, [r14 + VEC_DATA]
        mov rdi, [rax]
        mov r14, rdi
        call opcode_of
        cmp eax, OP_JUMP
        jne 4f
        mov rdi, [r14 + N_DATA + 8]
        call is_vmnode
        test eax, eax
        jz 4f
        call .Lpush_jd
        jmp .Lbt_label
4:      lea rdi, [rip + .Ls_question]
        call str_intern_c
        mov rdi, r12
        mov rsi, rax
        call vec_push
.Lbt_label:
        mov r13, [rbx + ND_LABEL]
        test r13, r13
        jz .Lbt_done
        # begin_vars = [('setvar', var_idx, var_val) for (_, var_idx, var_val, _) in label.begin_vars]
        call vec_new
        mov r14, rax
        mov r13, [r13 + ND_BEGIN_VARS]
        xor ecx, ecx
5:      cmp ecx, [r13 + N_AUX]
        jae 6f
        mov [rsp], rcx
        mov rax, [r13 + N_DATA + rcx*8]
        mov rsi, [rax + N_DATA + 8]
        mov rdx, [rax + N_DATA + 16]
        LOADS rdi, SETVAR
        call mk3
        mov rdi, r14
        mov rsi, rax
        call vec_push
        mov rcx, [rsp]
        inc rcx
        jmp 5b
6:      mov rdi, rbx
        lea rsi, [rip + pred_goto_back]
        mov rdx, rbx
        call find_nodes
        cmp qword ptr [rax + VEC_LEN], 0
        je 7f
        mov rdi, r14
        call vec_to_tuple
        mov rdx, rax
        mov rsi, rbx
        LOADS rdi, LABEL
        call mk3
        mov rdi, r12
        mov rsi, rax
        call vec_push
        jmp .Lbt_done
7:      # Nothing loops back here any more: a merge (see merge_branches)
        # took the paths that did to the continuation of an if above,
        # where the loop is found again. What's left here is the first
        # iteration.
        mov rdi, r12
        mov rsi, [r14 + VEC_DATA]
        mov rdx, [r14 + VEC_LEN]
        call vec_extend
.Lbt_done:
        add rsp, 16
        LEAVE

# local: push ('jd', str(jd[0])) on r12
.Lpush_jd:
        push r13
        mov rax, [rbx + ND_JD]
        mov rdi, [rax + N_DATA]
        test dil, 1
        jz 8f
        sar rdi, 1
        call str_of_int
        jmp 9f
8:      call str_of_value
9:      mov rsi, rax
        LOADS rdi, JD
        call mk2
        mov rdi, r12
        mov rsi, rax
        call vec_push
        pop r13
        ret
ENDF node_begin_trace

# node_print(sb, node): Node(jd), like the python __str__
FUNC node_print
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        lea rsi, [rip + .Ls_node_open]
        call sb_append_c
        mov rdi, rbx
        mov rsi, [r12 + ND_JD]
        call value_print
        mov rdi, rbx
        mov esi, ')'
        call sb_append_char
        LEAVE
ENDF node_print

        .section .note.GNU-stack,"",@progbits
