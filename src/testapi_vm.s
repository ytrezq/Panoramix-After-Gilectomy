# The test hooks of the VM, the stack and the loader (see testapi.s: each
# takes the parsed python literal and returns a value, printed as python's
# repr)

.include "defs.inc"

        .text

# tv_loader(hexcode) -> rax: a loader of the code (malloc'ed; the caller
# frees it with loader_free)
FUNC tv_loader
        ENTER
        mov rbx, rdi
        call tf_hex_bytes
        mov r12, rax
        mov r13, rdx
        call loader_new
        mov r14, rax
        mov rdi, rax
        mov rsi, r12
        mov rdx, r13
        call loader_load
        mov rax, r14
        LEAVE
ENDF tv_loader

# sets_fmp(hexcode) -> python's loader.sets_free_memory_pointer of its
# instructions (the loader's LD_NO_FREE_MEM, the other way round)
FUNC tf_sets_fmp
        ENTER
        call tv_loader
        mov rbx, rax
        lea r12, [rip + sp_true]
        cmp byte ptr [rbx + LD_NO_FREE_MEM], 0
        je 1f
        lea r12, [rip + sp_false]
1:      mov rdi, rbx
        call loader_free
        mov rax, r12
        LEAVE
ENDF tf_sets_fmp

# stack_vars((first, positions, depth)) -> (folded, vars): positions a
# tuple of indices
FUNC tf_stack_vars
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, [rbx + N_DATA]         # first
        mov edi, [r12 + N_AUX]
        inc edi
        call arena_alloc                # (zeroed)
        mov r13, rax
        mov r14, [rbx + N_DATA + 8]     # positions
        xor ecx, ecx
1:      cmp ecx, [r14 + N_AUX]
        jae 2f
        mov rax, [r14 + N_DATA + rcx*8]
        sar rax, 1
        mov byte ptr [r13 + rax], 1
        inc ecx
        jmp 1b
2:      mov rdi, r12
        mov rsi, r13
        mov rdx, [rbx + N_DATA + 16]
        sar rdx, 1
        lea rcx, [rsp]
        call stack_vars
        mov rdi, rax
        mov rsi, [rsp]
        call mk2
        add rsp, 16
        LEAVE
ENDF tf_stack_vars

        .section .note.GNU-stack,"",@progbits
