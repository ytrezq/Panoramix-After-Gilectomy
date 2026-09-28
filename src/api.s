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

# pan_set_log_level(level): python's logging levels (10 debug, 20 info,
# 30 warning, 40 error)
FUNC pan_set_log_level
        ENTER
        mov rbx, rdi
        call pan_init
        mov [rip + log_level], rbx
        LEAVE
ENDF pan_set_log_level

# pan_log_level_from_name(name) -> the level of "debug", "INFO"..., or -1
FUNC pan_log_level_from_name
        jmp log_level_from_name
ENDF pan_log_level_from_name

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
# strip_color(sb): the color codes removed from the builder's text
FUNC strip_color
        ENTER
        mov rbx, rdi
        call sb_to_str
        mov rdi, rax
        call clean_color
        mov r12, rax
        mov rdi, rbx
        call sb_reset
        mov rdi, rbx
        mov rsi, r12
        call sb_append_str
        LEAVE
ENDF strip_color

# int pan_decompile(code, len, threads, only_func, &out, &outlen): the
# decompilation with colors, as `python -m panoramix` prints it
FUNC pan_decompile
        push 0                          # the 7th argument, flags (rsp aligned at the call)
        call pan_decompile_ex
        add rsp, 8
        ret
ENDF pan_decompile

# int pan_decompile_ex(code, len, threads, only_func, &out, &outlen, flags)
# flags: PAN_NO_COLOR (1) - the text without the color codes
.set PAN_NO_COLOR, 1
FUNC pan_decompile_ex
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
        test qword ptr [rbp + 24], PAN_NO_COLOR     # (the 7th argument: above rbp, r15, the return address)
        jz 1f
        mov rdi, r12
        call strip_color
1:      mov rax, [rsp + 32]
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
ENDF pan_decompile_ex


# int pan_build_sigdb(const char *xz_path, const char *out_path)
FUNC pan_build_sigdb
        push r15
        ENTER
        sub rsp, 24
        mov [rsp], rdi
        mov [rsp + 8], rsi
        call pan_init
        call ctx_current
        mov [rsp + 16], rax
        call ctx_new
        mov r15, rax
        mov rdi, r15
        call ctx_bind
        mov rdi, [rsp]
        mov rsi, [rsp + 8]
        call sigdb_build
        mov [rsp], rax
        mov rdi, r15
        call ctx_free
        mov rdi, [rsp + 16]
        call ctx_bind
        mov rax, [rsp]
        add rsp, 24
        LEAVE_NORET
        pop r15
        ret
ENDF pan_build_sigdb
        .section .note.GNU-stack,"",@progbits
