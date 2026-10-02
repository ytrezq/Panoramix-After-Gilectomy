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

        .section .note.GNU-stack,"",@progbits
