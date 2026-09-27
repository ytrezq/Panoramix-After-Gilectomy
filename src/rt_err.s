# Errors: what python does with an exception, i.e. abandon the current
# function and report the problem. err_catch(buf) sets up a handler and
# returns 0; err_throw(code, message) unwinds to the innermost handler,
# where err_catch returns again, this time with the code. Handlers nest
# (the previous one is kept in the buffer) and must be dropped with
# err_end when the protected code finishes normally.
#
# Like setjmp/longjmp, this relies on the code between the two keeping
# its state in callee-saved registers or in memory, which all the
# decompiler code does (ENTER/LEAVE frames).

.include "defs.inc"

        .text

# err_catch(buf) -> eax: 0 now, the error code if err_throw is called
FUNC err_catch
        mov [rdi + ERR_RBX], rbx
        mov [rdi + ERR_RBP], rbp
        mov [rdi + ERR_R12], r12
        mov [rdi + ERR_R13], r13
        mov [rdi + ERR_R14], r14
        lea rax, [rsp + 8]
        mov [rdi + ERR_RSP], rax
        mov rax, [rsp]
        mov [rdi + ERR_RIP], rax
        mov rax, [r15 + CTX_ERR_BUF]
        mov [rdi + ERR_PREV], rax
        mov [r15 + CTX_ERR_BUF], rdi
        xor eax, eax
        ret
ENDF err_catch

# err_end(): leave the protected region normally
FUNC err_end
        mov rax, [r15 + CTX_ERR_BUF]
        mov rax, [rax + ERR_PREV]
        mov [r15 + CTX_ERR_BUF], rax
        ret
ENDF err_end

# err_throw(code, message): never returns. With no handler, fatal.
FUNC err_throw
        mov rax, [r15 + CTX_ERR_BUF]
        test rax, rax
        jz 1f
        mov [r15 + CTX_ERR_MSG], rsi
        mov [r15 + CTX_ERR_CODE], rdi
        mov rcx, [rax + ERR_PREV]
        mov [r15 + CTX_ERR_BUF], rcx
        mov rbx, [rax + ERR_RBX]
        mov rbp, [rax + ERR_RBP]
        mov r12, [rax + ERR_R12]
        mov r13, [rax + ERR_R13]
        mov r14, [rax + ERR_R14]
        mov rsp, [rax + ERR_RSP]
        mov rcx, [rax + ERR_RIP]
        mov eax, edi
        jmp rcx
1:      mov rdi, rsi
        jmp rt_fatal
ENDF err_throw

        .section .note.GNU-stack,"",@progbits
