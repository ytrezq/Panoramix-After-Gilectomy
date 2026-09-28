# The C-callable API (used by the CPython module).
#
#   int pan_init(void);
#   int pan_disasm(const uint8_t *code, size_t len, char **out, size_t *outlen);
#   void pan_free(void *p);
#
# `code` is raw bytecode. The results are malloc'ed strings, released
# with pan_free.

.include "defs.inc"

        .text

FUNC pan_init
        ENTER
        call rt_init
        call log_init
        xor eax, eax
        LEAVE
ENDF pan_init

FUNC pan_disasm
        push r15
        ENTER
        sub rsp, 40
        mov [rsp], rdi                  # code
        mov [rsp + 8], rsi              # len
        mov [rsp + 16], rdx             # out
        mov [rsp + 24], rcx             # outlen
        call pan_init
        call ctx_current
        mov [rsp + 32], rax             # previous binding, restored on exit
        call ctx_new
        mov r15, rax
        mov rdi, r15
        call ctx_bind
        call loader_new
        mov rbx, rax
        mov rdi, rbx
        mov rsi, [rsp]
        mov rdx, [rsp + 8]
        call loader_load
        call sb_new
        mov r12, rax
        mov rdi, rbx
        mov rsi, r12
        call loader_disasm
        mov rax, [rsp + 16]
        mov rcx, [r12 + SB_BUF]
        mov [rax], rcx
        mov rax, [rsp + 24]
        mov rcx, [r12 + SB_LEN]
        mov [rax], rcx
        mov rdi, r12
        call free@PLT                   # the builder, not its buffer
        mov rdi, rbx
        call loader_free
        mov rdi, r15
        call ctx_free
        mov rdi, [rsp + 32]
        call ctx_bind
        xor eax, eax
        add rsp, 40
        LEAVE_NORET
        pop r15
        ret
ENDF pan_disasm

FUNC pan_free
        jmp free@PLT
ENDF pan_free

# int pan_decompile(const uint8_t *code, size_t len, size_t threads,
#                   const char *only_func, char **out, size_t *outlen)
FUNC pan_decompile
        push r15
        ENTER
        sub rsp, 56
        mov [rsp], rdi                  # code
        mov [rsp + 8], rsi              # len
        mov [rsp + 16], rdx             # threads
        mov [rsp + 24], rcx             # only_func
        mov [rsp + 32], r8              # out
        mov [rsp + 40], r9              # outlen
        call pan_init
        call ctx_current
        mov [rsp + 48], rax
        call ctx_new
        mov r15, rax
        mov rdi, r15
        call ctx_bind
        call sb_new
        mov r12, rax
        mov rdi, [rsp]
        mov rsi, [rsp + 8]
        mov rdx, [rsp + 16]
        mov rcx, [rsp + 24]
        mov r8, r12
        call decompile
        mov rax, [rsp + 32]
        mov rcx, [r12 + SB_BUF]
        mov [rax], rcx
        mov rax, [rsp + 40]
        mov rcx, [r12 + SB_LEN]
        mov [rax], rcx
        mov rdi, r12
        call free@PLT                   # the builder, not its buffer
        mov rdi, r15
        call ctx_free
        mov rdi, [rsp + 48]
        call ctx_bind
        xor eax, eax
        add rsp, 56
        LEAVE_NORET
        pop r15
        ret
ENDF pan_decompile

        .section .note.GNU-stack,"",@progbits
