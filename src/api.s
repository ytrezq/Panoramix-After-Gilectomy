# The C-callable API (used by the CPython module).
#
#   int pan_init(void);
#   int pan_disasm(const uint8_t *code, size_t len, char **out, size_t *outlen);
#   int pan_decompile(...), pan_decompile_ex(...), pan_decompile_data(...)
#   void pan_free(void *p);
#
# `code` is raw bytecode. The results are malloc'ed strings, released
# with pan_free.

.include "defs.inc"

        .text

API pan_init
        ENTER
        call rt_init
        call log_init
        xor eax, eax
        LEAVE
ENDF pan_init

# pan_set_log_level(level): python's logging levels (10 debug, 20 info,
# 30 warning, 40 error)
API pan_set_log_level
        ENTER
        mov rbx, rdi
        call pan_init
        mov [rip + log_level], rbx
        LEAVE
ENDF pan_set_log_level

# pan_log_level_from_name(name) -> the level of "debug", "INFO"..., or -1
API pan_log_level_from_name
        jmp log_level_from_name
ENDF pan_log_level_from_name

API pan_disasm
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
        call ctx_try_new
        test rax, rax
        jz .Ldis_no_ctx
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
.Ldis_no_ctx:                           # (no memory: -1, nothing)
        mov rax, [rsp + 16]
        mov qword ptr [rax], 0
        mov rax, [rsp + 24]
        mov qword ptr [rax], 0
        mov eax, -1
        add rsp, 40
        LEAVE_NORET
        pop r15
        ret
ENDF pan_disasm

API pan_free
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
API pan_decompile
        push 0                          # the 7th argument, flags (rsp aligned at the call)
        call pan_decompile_ex
        add rsp, 8
        ret
ENDF pan_decompile

# int pan_decompile_ex(code, len, threads, only_func, &out, &outlen, flags)
# flags: PAN_NO_COLOR (1) - the text without the color codes. Returns 0,
# or -1 with the error's message in *out (what python would have raised
# out of the postprocessing).
.set PAN_NO_COLOR, 1
.set PAN_JSON, 4
.set PAN_WANT_DATA, 1 << 16             # (internal: pan_decompile_data's)
.set PO_TEXT, 0                         # struct pan_output
.set PO_TEXTLEN, 8
.set PO_DATA, 16
.set PO_DATALEN, 24
.set PO_SIZEOF, 32
API pan_decompile_ex
        push rbp
        mov rbp, rsp
        push r8                         # &out
        push r9                         # &outlen
        sub rsp, PO_SIZEOF
        mov r8, [rbp + 16]              # flags (the 7th argument)
        and r8, ~PAN_WANT_DATA
        mov r9, rsp
        call decompile_api
        mov rcx, [rbp - 8]
        mov rdx, [rsp + PO_TEXT]
        mov [rcx], rdx
        mov rcx, [rbp - 16]
        mov rdx, [rsp + PO_TEXTLEN]
        mov [rcx], rdx
        mov rsp, rbp                    # (not `leave`: the macro LEAVE, for gas)
        pop rbp
        ret
ENDF pan_decompile_ex

# int pan_decompile_data(code, len, threads, only_func, flags, pan_output *po)
# the text, as pan_decompile_ex's, and python's decompilation.json in
# po->data: its JSON text (flags: PAN_JSON), or the binary form data.s
# describes (for the python module, which makes python's objects of it).
# Returns 0, or -1 with the error's message as the text (and no data).
API pan_decompile_data
        or r8, PAN_WANT_DATA
        jmp decompile_api
ENDF pan_decompile_data

# decompile_api(code, len, threads, only_func, flags, po) -> eax: 0 or -1
FUNC decompile_api
        push r15
        ENTER
        sub rsp, 72
        mov [rsp], rdi                  # code
        mov [rsp + 8], rsi              # len
        mov [rsp + 16], rdx             # threads
        mov [rsp + 24], rcx             # only_func
        mov [rsp + 32], r8              # flags
        mov [rsp + 40], r9              # po
        call pan_init
        call ctx_current
        mov [rsp + 48], rax
        call ctx_try_new
        test rax, rax
        jz .Lda_no_ctx
        mov r15, rax
        mov rdi, r15
        call ctx_bind
        call sb_new
        mov r12, rax                    # the text
        xor r13d, r13d                  # the data (its builder)
        test qword ptr [rsp + 32], PAN_WANT_DATA
        jz 1f
        call sb_new
        mov r13, rax
        mov [r15 + CTX_DATA_SB], rax
        xor eax, eax
        test qword ptr [rsp + 32], PAN_JSON
        setnz al
        mov [r15 + CTX_DATA_MODE], rax
1:      mov rdi, [rsp]
        mov rsi, [rsp + 8]
        mov rdx, [rsp + 16]
        mov rcx, [rsp + 24]
        mov r8, r12
        call decompile_run
        mov ebx, eax                    # 0, or the error (the message in the text's builder)
        test eax, eax
        jnz 2f
        test qword ptr [rsp + 32], PAN_NO_COLOR
        jz 3f
        mov rdi, r12
        call strip_color
        jmp 3f
2:      test r13, r13                   # (failed: no data)
        jz 3f
        mov rdi, [r13 + SB_BUF]
        call free@PLT
        mov qword ptr [r13 + SB_BUF], 0
        mov qword ptr [r13 + SB_LEN], 0
3:      mov rax, [rsp + 40]
        mov rcx, [r12 + SB_BUF]
        mov [rax + PO_TEXT], rcx
        mov rcx, [r12 + SB_LEN]
        mov [rax + PO_TEXTLEN], rcx
        xor ecx, ecx
        xor edx, edx
        test r13, r13
        jz 4f
        mov rcx, [r13 + SB_BUF]
        mov rdx, [r13 + SB_LEN]
4:      mov [rax + PO_DATA], rcx
        mov [rax + PO_DATALEN], rdx
        mov rdi, r12
        call free@PLT                   # the builders, not their buffers
        test r13, r13
        jz 5f
        mov rdi, r13
        call free@PLT
5:      mov qword ptr [r15 + CTX_DATA_SB], 0
        mov rdi, r15
        call ctx_free
        mov edi, CHUNK_POOL_KEEP        # (the memory of the arenas back, but a little)
        call chunk_pool_trim
        mov rdi, [rsp + 48]
        call ctx_bind
        xor eax, eax
        test ebx, ebx
        jz 6f
        mov eax, -1
6:      add rsp, 72
        LEAVE_NORET
        pop r15
        ret
.Lda_no_ctx:                            # (no memory for a context: -1, the message)
        lea rdi, [rip + .Ls_no_memory]
        call strdup@PLT
        mov rcx, [rsp + 40]
        mov [rcx + PO_TEXT], rax
        xor edx, edx
        test rax, rax
        jz 7f
        mov edx, .Ls_no_memory_end - .Ls_no_memory - 1
7:      mov [rcx + PO_TEXTLEN], rdx
        mov qword ptr [rcx + PO_DATA], 0
        mov qword ptr [rcx + PO_DATALEN], 0
        mov eax, -1
        jmp 6b
ENDF decompile_api

        .section .rodata
.Ls_no_memory:  .asciz "out of memory: the system gave no more (mmap failed)"
.Ls_no_memory_end:
        .text


# int pan_build_sigdb(const char *xz_path, const char *out_path)
API pan_build_sigdb
        push r15
        ENTER
        sub rsp, 24
        mov [rsp], rdi
        mov [rsp + 8], rsi
        call pan_init
        call ctx_current
        mov [rsp + 16], rax
        call ctx_try_new
        test rax, rax
        jz 1f
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
1:      mov eax, -1                     # (no memory for a context)
        add rsp, 24
        LEAVE_NORET
        pop r15
        ret
ENDF pan_build_sigdb
        .section .note.GNU-stack,"",@progbits
