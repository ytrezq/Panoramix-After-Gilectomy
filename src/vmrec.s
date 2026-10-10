# The recursive internal functions (port of the PR's vm.py: VM.internal,
# replace_recursions, recursion_of, call_entry, internal_call_at,
# internal_call). A call of one isn't unrolled - it would be until the VM
# stops, the EVM's stack of 1024 words being what bounds the recursion -
# it's a line, ('internal', entry, args, the names of its results), and
# the function is decompiled apart (decompiler.s): those the VM is given
# (VM_INTERNAL: the function decompiled apart), and those it finds (also
# in VM_FOUND, in the order found) - where a function is called again in
# its own call. A record: (entry, n, m, frame), numbers - the words of its
# arguments, of its results, of the stack a call of itself takes.

.include "defs.inc"

        .text

# vm_internal_find(entry) -> rax: the VM's record of the recursive
# internal function at entry, or 0
FUNC vm_internal_find
        mov rax, [r15 + CTX_VM]
        mov rax, [rax + VM_INTERNAL]
        test rax, rax
        jz 9f
        mov rcx, [rax + VEC_DATA]
        mov rdx, [rax + VEC_LEN]
1:      test rdx, rdx
        jz 9f
        mov rax, [rcx]
        cmp [rax + N_DATA], rdi
        je 2f
        add rcx, 8
        dec rdx
        jmp 1b
9:      xor eax, eax
2:      ret
ENDF vm_internal_find

# vm_internal_add(record): the VM knows the recursive internal function -
# found (VM_FOUND too) when found is 1
FUNC vm_internal_add
        ENTER
        mov rbx, rdi
        mov r12d, esi
        mov r13, [r15 + CTX_VM]
        mov rdi, [r13 + VM_INTERNAL]
        test rdi, rdi
        jnz 1f
        call vec_new
        mov [r13 + VM_INTERNAL], rax
        mov rdi, rax
1:      mov rsi, rbx
        call vec_push
        test r12d, r12d
        jz 3f
        mov rdi, [r13 + VM_FOUND]
        test rdi, rdi
        jnz 2f
        call vec_new
        mov [r13 + VM_FOUND], rax
        mov rdi, rax
2:      mov rsi, rbx
        call vec_push
3:      LEAVE
ENDF vm_internal_add

# vm_found_buffer() -> rax: the recursive internal functions the VM found
# (python's vm.found), out of the context (its arena may be compacted, the
# VM with it, before the decompiler reads them): a buffer (xmalloc'd) of
# their count then the four numbers of each record, tagged, in the order
# found - or 0 for none
FUNC vm_found_buffer
        ENTER
        mov rax, [r15 + CTX_VM]
        mov rbx, [rax + VM_FOUND]
        test rbx, rbx
        jz 9f
        mov r12, [rbx + VEC_LEN]
        test r12, r12
        jz 9f
        mov rdi, r12
        shl rdi, 5
        add rdi, 8
        call xmalloc
        mov [rax], r12
        lea rdi, [rax + 8]
        mov rsi, [rbx + VEC_DATA]
1:      mov rcx, [rsi]                  # (entry, n, m, frame)
        mov rdx, [rcx + N_DATA]
        mov [rdi], rdx
        mov rdx, [rcx + N_DATA + 8]
        mov [rdi + 8], rdx
        mov rdx, [rcx + N_DATA + 16]
        mov [rdi + 16], rdx
        mov rdx, [rcx + N_DATA + 24]
        mov [rdi + 24], rdx
        add rdi, 32
        add rsi, 8
        dec r12
        jnz 1b
        LEAVE
9:      xor eax, eax
        LEAVE
ENDF vm_found_buffer

# vm_internal_stack(n) -> tuple: the stack a recursive internal function
# decompiled apart starts with - its params where its calls push them, n
# of them (tagged), above the address it returns to: (RETURN_ADDRESS,
# ('param', '_param1'), ...)
FUNC vm_internal_stack
        ENTER
        mov rbx, rdi
        call vec_new
        mov r12, rax
        call vm_return_address
        mov rdi, r12
        mov rsi, rax
        call vec_push
        mov rdi, rbx
        call internal_param_names
        mov r13, rax
        xor r14d, r14d
1:      cmp r14d, [r13 + N_AUX]
        jae 2f
        LOADS rdi, PARAM
        mov rsi, [r13 + N_DATA + r14*8]
        call mk2
        mov rdi, r12
        mov rsi, rax
        call vec_push
        inc r14d
        jmp 1b
2:      mov rdi, r12
        call vec_to_tuple
        LEAVE
ENDF vm_internal_stack

# vm_return_address() -> rax: vm.py's RETURN_ADDRESS, ('return_address',) -
# where a recursive internal function decompiled apart returns: the
# address below its arguments, as its caller pushed it
FUNC vm_return_address
        ENTER
        LOADS rdi, RETURN_ADDRESS
        call mk1
        LEAVE
ENDF vm_return_address

# vm_is_dest(v) -> eax: v is a number, a jumpdest of the code (python's
# type(v) is int and v in loader.jump_dests)
FUNC vm_is_dest
        test dil, 1
        jz 9f
        mov rsi, rdi
        sar rsi, 1
        js 9f
        mov rax, [r15 + CTX_VM]
        mov rdi, [rax + VM_LOADER]
        jmp loader_is_jumpdest
9:      xor eax, eax
        ret
ENDF vm_is_dest

# vm_top_dest(stack) -> rax: the index of the topmost jumpdest on the
# stack (a tuple), or -1
FUNC vm_top_dest
        ENTER
        mov rbx, rdi
        mov r12d, [rbx + N_AUX]
1:      dec r12
        js 9f
        mov rdi, [rbx + N_DATA + r12*8]
        call vm_is_dest
        test eax, eax
        jz 1b
        mov rax, r12
        LEAVE
9:      mov rax, -1
        LEAVE
ENDF vm_top_dest

# vm_prefix_equal(a, b, k) -> eax: the first k elements of the tuples a and
# b are equal (python's tuple(a[:k]) == tuple(b[:k]), both that long)
FUNC vm_prefix_equal
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        xor r14d, r14d
1:      cmp r14, r13
        jae 8f
        mov rdi, [rbx + N_DATA + r14*8]
        mov rsi, [r12 + N_DATA + r14*8]
        inc r14
        cmp rdi, rsi
        je 1b
        call values_equal
        test eax, eax
        jnz 1b
        LEAVE
8:      mov eax, 1
        LEAVE
ENDF vm_prefix_equal

# vm_internal_call_at(start, stack) -> eax: python's internal_call_at -
# start, with stack, is the call of a recursive internal function the VM
# knows: an address of the code below its n arguments
FUNC vm_internal_call_at
        ENTER
        mov rbx, rsi
        test dil, 1
        jz 9f
        call vm_internal_find
        test rax, rax
        jz 9f
        mov rcx, [rax + N_DATA + 8]
        sar rcx, 1                      # n
        mov edx, [rbx + N_AUX]
        cmp rdx, rcx
        jbe 9f
        sub rdx, rcx
        mov rdi, [rbx + N_DATA + rdx*8 - 8]
        call vm_is_dest
        LEAVE
9:      xor eax, eax
        LEAVE
ENDF vm_internal_call_at

# vm_internal_call(start, condition): python's internal_call - the trace
# (VM_TRACE) of the call of the recursive internal function at start,
# the VM's stack and what it knows those of the node: ('internal', start,
# its arguments, the names of the variables of its results), then where
# it returns - the address below its arguments - with them on the stack,
# the state as a call may leave it (the storage written, the memory too)
FUNC vm_internal_call
        ENTER
        sub rsp, 48
        .set IC_START, 0
        .set IC_COND, 8
        .set IC_REC, 16
        .set IC_RESULTS, 24
        .set IC_ARGS, 32
        mov [rsp + IC_START], rdi
        mov [rsp + IC_COND], rsi
        call vm_internal_find
        mov [rsp + IC_REC], rax
        mov rbx, [r15 + CTX_VM]
        mov edi, OP_DELEGATECALL
        xor esi, esi
        call vm_snapshot
        mov r12, [rbx + VM_STACK]
        mov rax, [rsp + IC_REC]
        mov r13, [rax + N_DATA + 8]
        sar r13, 1                      # n
        mov r14, [r12 + VEC_LEN]
        sub r14, r13                    # where the arguments begin
        mov edi, r13d
        mov rsi, [r12 + VEC_DATA]
        lea rsi, [rsi + r14*8]
        call mk_tuple
        mov [rsp + IC_ARGS], rax
        # the names of its results, after those the snapshot made
        call vec_new
        mov [rsp + IC_RESULTS], rax
        mov rax, [rsp + IC_REC]
        mov r13, [rax + N_DATA + 16]
        sar r13, 1                      # m
1:      test r13, r13
        jz 2f
        call vm_new_var_name
        mov rdi, [rsp + IC_RESULTS]
        mov rsi, rax
        call vec_push
        dec r13
        jmp 1b
2:      mov rdi, [rsp + IC_RESULTS]
        call vec_to_tuple
        mov [rsp + IC_RESULTS], rax
        LOADS rdi, INTERNAL
        mov rsi, [rsp + IC_START]
        mov rdx, [rsp + IC_ARGS]
        mov rcx, rax
        call mk4
        mov rdi, [rbx + VM_TRACE]
        mov rsi, rax
        call vec_push
        # what's known after: not what may have changed, nor the memory
        mov rdi, [rbx + VM_KNOWN]
        xor esi, esi                    # (VOLATILE's names)
        call forget
        mov rdi, rax
        call vm_without_memory_facts
        mov [rbx + VM_KNOWN], rax
        # where it returns: the stack below the address, the results on it
        call vec_new
        mov r13, rax
        mov rdi, rax
        mov rsi, [r12 + VEC_DATA]
        lea rdx, [r14 - 1]
        call vec_extend
        mov rax, [r12 + VEC_DATA]
        mov rax, [rax + r14*8 - 8]
        mov [rsp + IC_ARGS], rax        # (the address)
        mov rax, [rsp + IC_RESULTS]
        xor r14d, r14d
3:      cmp r14d, [rax + N_AUX]
        jae 4f
        LOADS rdi, VAR
        mov rsi, [rax + N_DATA + r14*8]
        call mk2
        mov rdi, r13
        mov rsi, rax
        call vec_push
        inc r14d
        mov rax, [rsp + IC_RESULTS]
        jmp 3b
4:      mov rdi, r13
        call vec_to_tuple
        mov rdx, rax
        mov rdi, [rsp + IC_ARGS]
        xor esi, esi
        mov rcx, [rsp + IC_COND]
        mov r8, [rbx + VM_KNOWN]
        call node_new
        mov rsi, rax
        LOADS rdi, JUMP
        call mk2
        mov rdi, [rbx + VM_TRACE]
        mov rsi, rax
        call vec_push
        add rsp, 48
        LEAVE
ENDF vm_internal_call

# vm_without_memory_facts(known) -> tuple: the facts but those of the
# memory (MEMORY_FACTS: ('memory', ...), ('memory_fresh',))
FUNC vm_without_memory_facts
        ENTER
        mov rbx, rdi
        call vec_new
        mov r12, rax
        xor r13d, r13d
1:      cmp r13d, [rbx + N_AUX]
        jae 3f
        mov rdi, [rbx + N_DATA + r13*8]
        inc r13d
        OPCODE_OF_RDI
        cmp eax, OP_MEMORY
        je 1b
        cmp eax, OP_MEMORY_FRESH
        je 1b
        mov rdi, r12
        mov rsi, [rbx + N_DATA + r13*8 - 8]
        call vec_push
        jmp 1b
3:      mov rdi, r12
        call vec_to_tuple
        LEAVE
ENDF vm_without_memory_facts

# vm_replace_recursions(root, nodes): python's replace_recursions - where a
# node starts the call of an internal function in its own call (see
# vm_recursion_of), the function is a recursive one: every call of it is
# a line (vm_internal_call) - those of the path explored, the first one
# included, explored again as such. nodes: the unexpanded ones
# (vm_expand_trace's, python's find_nodes order), those vm_replace_loops
# made loops since skipped.
FUNC vm_replace_recursions
        ENTER
        sub rsp, 16
        mov [rsp], rdi                  # root
        mov rax, [r15 + CTX_VM]
        cmp qword ptr [rax + VM_JUST_FDESTS], 0
        jne 9f
        mov rbx, rsi
        test rbx, rbx
        jnz 1f
        lea rsi, [rip + pred_unexpanded]
        xor edx, edx
        call find_nodes
        mov rbx, rax
1:      xor r12d, r12d
2:      cmp r12, [rbx + VEC_LEN]
        jae 9f
        mov rax, [rbx + VEC_DATA]
        mov r13, [rax + r12*8]
        inc r12
        cmp qword ptr [r13 + ND_TRACE], 0
        jne 2b
        mov rdi, [r13 + ND_START]       # (a call already, once it runs)
        mov rsi, [r13 + ND_STACK]
        call vm_internal_call_at
        test eax, eax
        jnz 2b
        mov rdi, r13
        call vm_recursion_of
        test rax, rax
        jz 2b
        mov r14, rax
        mov rdi, [r14 + N_DATA]
        call vm_internal_find
        test rax, rax
        jnz 2b
        mov rdi, r14
        mov esi, 1
        call vm_internal_add
        # its calls explored so far, explored again as such
        mov rdi, [rsp]
        lea rsi, [rip + pred_internal_call]
        mov rdx, [r14 + N_DATA]
        call find_nodes
        mov rbx, rax
        xor r12d, r12d
3:      cmp r12, [rbx + VEC_LEN]
        jae 4f
        mov rax, [rbx + VEC_DATA]
        mov r13, [rax + r12*8]
        inc r12
        mov qword ptr [r13 + ND_TRACE], 0
        call vec_new
        mov [r13 + ND_NEXT], rax
        mov rdi, r13
        call node_touch
        jmp 3b
4:      # (the loops replace_loops found may be gone with them: continue_loops
        # walks the tree)
        mov rax, [r15 + CTX_VM]
        mov qword ptr [rax + VM_LOOPS_STALE], 1
        mov qword ptr [rax + VM_UNEXP_VALID], 0
9:      add rsp, 16
        LEAVE
ENDF vm_replace_recursions

# pred_internal_call(node, entry): a node at entry run already, the call of
# the recursive internal function there
FUNC pred_internal_call
        xor eax, eax
        cmp [rdi + ND_START], rsi
        jne 1f
        cmp qword ptr [rdi + ND_TRACE], 0
        je 1f
        mov rax, rdi
        mov rdi, [rax + ND_START]
        mov rsi, [rax + ND_STACK]
        jmp vm_internal_call_at
1:      ret
ENDF pred_internal_call

# vm_recursion_of(node) -> rax: python's recursion_of - (entry, n, m,
# frame) if node starts the call of an internal function in its own call:
# an ancestor starts there too, with the address its call returns to (the
# topmost on its stack) on node's stack, all below it the same, and above
# it as many words as node has above its own; m the words of its results,
# as one of the calls of it returned them (none known: 0 - the recursion
# is unrolled another level, until one is). 0 if node isn't one.
FUNC vm_recursion_of
        # (at the entry, before anything is touched: the walks below have
        # no STACK_CHECK of their own to be timed out at - see
        # find_nodes_into)
        STACK_CHECK
        ENTER
        sub rsp, 96
        .set RO_Q, 0
        .set RO_KNOWN, 8                # 1: RO_REC is known (python's n not None)
        .set RO_REC, 16                 # vm_call_entry's: entry, n, frame
        .set RO_ARGS, 40                # pred_returned's: ret, p, the ancestor's stack
        .set RO_TUPLE, 64               # entry, n, m, frame
        mov rbx, rdi                    # node
        mov rdi, [rbx + ND_START]
        call vm_is_dest
        test eax, eax
        jz .Lro_none
        mov rdi, [rbx + ND_STACK]
        call vm_top_dest
        test rax, rax
        js .Lro_none
        mov [rsp + RO_Q], rax
        mov qword ptr [rsp + RO_KNOWN], 0
        mov r12, [rbx + ND_PREV]        # the ancestors, the nearest first
.Lro_prev:
        test r12, r12
        jz .Lro_none
        mov rax, [r12 + ND_START]
        cmp rax, [rbx + ND_START]
        jne .Lro_next
        mov rax, [r12 + ND_STACK]
        mov ecx, [rax + N_AUX]
        mov rdx, [rbx + ND_STACK]
        cmp ecx, [rdx + N_AUX]
        jae .Lro_next
        mov rdi, rax
        call vm_top_dest
        test rax, rax
        js .Lro_next
        cmp rax, [rsp + RO_Q]
        jae .Lro_next
        mov r13, rax                    # p
        mov rcx, [r12 + ND_STACK]       # len(prev.stack) - p == len(node.stack) - q
        mov ecx, [rcx + N_AUX]
        sub rcx, r13
        mov rdx, [rbx + ND_STACK]
        mov edx, [rdx + N_AUX]
        sub rdx, [rsp + RO_Q]
        cmp rcx, rdx
        jne .Lro_next
        mov rdi, [r12 + ND_STACK]
        mov rsi, [rbx + ND_STACK]
        lea rdx, [r13 + 1]
        call vm_prefix_equal
        test eax, eax
        jz .Lro_next
        cmp qword ptr [rsp + RO_KNOWN], 0
        jne 1f
        mov qword ptr [rsp + RO_KNOWN], 1
        mov rdi, r12
        mov rsi, r13
        mov rdx, rbx
        mov rcx, [rsp + RO_Q]
        lea r8, [rsp + RO_REC]
        call vm_call_entry
1:      # its results: where its call returns, the stack below the address
        # the same, and the address gone - not the code there while the
        # call runs (solc's optimizer makes the end of a function, which
        # returns to the address the stack has, the end of others too)
        mov rax, [r12 + ND_STACK]
        mov rcx, [rax + N_DATA + r13*8]
        mov [rsp + RO_ARGS], rcx        # ret
        mov [rsp + RO_ARGS + 8], r13    # p
        mov [rsp + RO_ARGS + 16], rax   # below: the ancestor's stack, to p
        mov rdi, r12
        lea rsi, [rip + pred_returned]
        lea rdx, [rsp + RO_ARGS]
        call find_nodes
        cmp qword ptr [rax + VEC_LEN], 0
        je .Lro_next
        mov rax, [rax + VEC_DATA]
        mov rax, [rax]
        mov rax, [rax + ND_STACK]
        mov ecx, [rax + N_AUX]
        sub rcx, r13                    # m
        TAG rcx
        mov [rsp + RO_TUPLE + 16], rcx
        mov rax, [rsp + RO_REC]
        mov [rsp + RO_TUPLE], rax       # entry (a value)
        mov rax, [rsp + RO_REC + 8]
        TAG rax
        mov [rsp + RO_TUPLE + 8], rax   # n
        mov rax, [rsp + RO_REC + 16]
        TAG rax
        mov [rsp + RO_TUPLE + 24], rax  # frame
        mov edi, 4
        lea rsi, [rsp + RO_TUPLE]
        call mk_tuple
        add rsp, 96
        LEAVE
.Lro_next:
        mov r12, [r12 + ND_PREV]
        jmp .Lro_prev
.Lro_none:
        xor eax, eax
        add rsp, 96
        LEAVE
ENDF vm_recursion_of

# pred_returned(x, args): python's return of the call of recursion_of's
# ancestor - x at the address the call returns to (args: ret, p, the
# ancestor's stack), the stack below it the same, and the address gone
FUNC pred_returned
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov rax, [r12]
        cmp [rbx + ND_START], rax
        jne 9f
        mov rax, [rbx + ND_STACK]
        mov ecx, [rax + N_AUX]
        mov r13, [r12 + 8]              # p
        cmp rcx, r13
        jb 9f
        mov rdi, rax
        mov rsi, [r12 + 16]
        mov rdx, r13
        call vm_prefix_equal
        test eax, eax
        jz 9f
        mov rax, [rbx + ND_STACK]       # not (len(x.stack) > p and x.stack[p] == ret)
        mov ecx, [rax + N_AUX]
        cmp rcx, r13
        jbe 8f
        mov rdi, [rax + N_DATA + r13*8]
        mov rsi, [r12]
        call values_equal
        test eax, eax
        jnz 9f
8:      mov eax, 1
        LEAVE
9:      xor eax, eax
        LEAVE
ENDF pred_returned

# vm_call_entry(prev, p, node, q, out): python's call_entry - out[0] the
# entry of the function prev and node are the calls of (the address it
# returns to at p on prev's stack, at q on node's), out[1] n, out[2] the
# frame: where it starts, the outermost node of the call of prev that the
# call of node has too (one where as many words are above the address) -
# not a block the first ones go to, which would make what they push before
# arguments of it. Numbers, untagged.
FUNC vm_call_entry
        ENTER
        sub rsp, 64
        .set CE_PREV, 0
        .set CE_P, 8
        .set CE_NODE, 16
        .set CE_Q, 24
        .set CE_OUT, 32
        .set CE_OUTER, 40
        .set CE_INNER, 48
        mov [rsp + CE_PREV], rdi
        mov [rsp + CE_P], rsi
        mov [rsp + CE_NODE], rdx
        mov [rsp + CE_Q], rcx
        mov [rsp + CE_OUT], r8
        call vec_new
        mov [rsp + CE_OUTER], rax
        mov rbx, [rsp + CE_PREV]
1:      test rbx, rbx                   # outer: from prev up, within its call
        jz 2f
        mov rdi, rbx
        mov rsi, [rsp + CE_P]
        mov rdx, [rsp + CE_PREV]
        call ce_within
        test eax, eax
        jz 2f
        mov rdi, [rsp + CE_OUTER]
        mov rsi, rbx
        call vec_push
        mov rbx, [rbx + ND_PREV]
        jmp 1b
2:      call vec_new
        mov [rsp + CE_INNER], rax
        mov rbx, [rsp + CE_NODE]
3:      test rbx, rbx                   # inner: from node up, within its call
        jz 4f
        mov rdi, rbx
        mov rsi, [rsp + CE_Q]
        mov rdx, [rsp + CE_NODE]
        call ce_within
        test eax, eax
        jz 4f
        mov rdi, [rsp + CE_INNER]
        mov rsi, rbx
        call vec_push
        mov rbx, [rbx + ND_PREV]
        jmp 3b
4:      mov rax, [rsp + CE_OUTER]       # the outermost first
        mov r12, [rax + VEC_LEN]
5:      dec r12
        js 8f
        mov rax, [rsp + CE_OUTER]
        mov rax, [rax + VEC_DATA]
        mov rbx, [rax + r12*8]          # x
        mov rax, [rbx + ND_STACK]
        mov r14d, [rax + N_AUX]
        sub r14, [rsp + CE_P]           # len(x.stack) - p
        xor r13d, r13d
6:      mov rax, [rsp + CE_INNER]
        cmp r13, [rax + VEC_LEN]
        jae 5b
        mov rax, [rax + VEC_DATA]
        mov rcx, [rax + r13*8]          # y
        inc r13
        mov rax, [rcx + ND_START]
        cmp rax, [rbx + ND_START]
        jne 6b
        mov rax, [rcx + ND_STACK]
        mov eax, [rax + N_AUX]
        sub rax, [rsp + CE_Q]
        cmp rax, r14
        jne 6b
        mov rax, [rcx + ND_STACK]       # found: x.start, len(x.stack) - p - 1,
        mov edx, [rax + N_AUX]          # len(y.stack) - len(x.stack)
        mov rax, [rbx + ND_STACK]
        mov eax, [rax + N_AUX]
        sub rdx, rax
        mov rdi, [rsp + CE_OUT]
        mov rcx, [rbx + ND_START]
        mov [rdi], rcx
        lea rcx, [r14 - 1]
        mov [rdi + 8], rcx
        mov [rdi + 16], rdx
        jmp 9f
8:      # (never: prev and node are such a pair)
        mov rbx, [rsp + CE_PREV]
        mov rdi, [rsp + CE_OUT]
        mov rcx, [rbx + ND_START]
        mov [rdi], rcx
        mov rax, [rbx + ND_STACK]
        mov eax, [rax + N_AUX]
        mov rcx, rax
        sub rcx, [rsp + CE_P]
        dec rcx
        mov [rdi + 8], rcx
        mov rdx, [rsp + CE_NODE]
        mov rdx, [rdx + ND_STACK]
        mov edx, [rdx + N_AUX]
        sub rdx, rax
        mov [rdi + 16], rdx
9:      add rsp, 64
        LEAVE
ENDF vm_call_entry

# ce_within(x, k, y) -> eax: call_entry's within - x's stack holds more than
# k words, the first k + 1 those of y's
FUNC ce_within
        ENTER
        mov rax, [rdi + ND_STACK]
        mov ecx, [rax + N_AUX]
        cmp rcx, rsi
        jbe 9f
        mov rdi, rax
        mov rax, [rdx + ND_STACK]
        mov ecx, [rax + N_AUX]          # (y's has them too)
        cmp rcx, rsi
        jbe 9f
        lea rdx, [rsi + 1]
        mov rsi, rax
        call vm_prefix_equal
        LEAVE
9:      xor eax, eax
        LEAVE
ENDF ce_within

        .section .note.GNU-stack,"",@progbits
