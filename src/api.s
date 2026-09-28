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
# strip_color(sb): the color codes removed from the builder's text, in
# place - every "\x1b[" digits and semicolons "m" (python's C.every, and
# the colors of --verbose and --explain)
FUNC strip_color
        mov rsi, [rdi + SB_BUF]
        mov rcx, [rdi + SB_LEN]
        xor eax, eax                    # read
        xor edx, edx                    # write
1:      cmp rax, rcx
        jae 5f
        mov r8b, [rsi + rax]
        cmp r8b, 0x1b
        jne 4f
        lea r9, [rax + 1]               # "[" (digit | ";")* "m"?
        cmp r9, rcx
        jae 4f
        cmp byte ptr [rsi + r9], '['
        jne 4f
2:      inc r9
        cmp r9, rcx
        jae 4f
        movzx r10d, byte ptr [rsi + r9]
        cmp r10b, 'm'
        je 3f
        cmp r10b, ';'
        je 2b
        sub r10d, '0'
        cmp r10d, 9
        jbe 2b
        jmp 4f
3:      lea rax, [r9 + 1]               # (the sequence skipped)
        jmp 1b
4:      mov [rsi + rdx], r8b
        inc rax
        inc rdx
        jmp 1b
5:      mov [rdi + SB_LEN], rdx
        mov byte ptr [rsi + rdx], 0
        ret
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
# flags: PAN_NO_COLOR (1) - the text without the color codes; PAN_VERBOSE
# (8) and PAN_EXPLAIN (16) - python's --verbose and --explain, the text
# after what --explain printed; PAN_REPR (32), PAN_RETURNS (64) - the
# traces and the returns of the functions after them, as python prints
# them when sys.argv holds --repr, --returns. Returns 0, or -1 with the error's message
# in *out (what python would have raised out of the postprocessing).
.set PAN_NO_COLOR, 1
.set PAN_JSON, 4
.set PAN_VERBOSE, 8
.set PAN_EXPLAIN, 16
.set PAN_REPR, 32
.set PAN_RETURNS, 64
.set PAN_WANT_DATA, 1 << 16             # (internal: pan_decompile_data's)
.set PO_TEXT, 0                         # struct pan_output
.set PO_TEXTLEN, 8
.set PO_DATA, 16
.set PO_DATALEN, 24
.set PO_EXPLAIN, 32                     # (written with PAN_EXPLAIN only)
.set PO_EXPLAINLEN, 40
.set PO_SIZEOF, 48
API pan_decompile_ex
        push rbp
        mov rbp, rsp
        push r8                         # &out
        push r9                         # &outlen
        push rbx
        push r12
        sub rsp, PO_SIZEOF
        mov r8, [rbp + 16]              # flags (the 7th argument)
        and r8, ~PAN_WANT_DATA
        mov r9, rsp
        call decompile_api
        mov ebx, eax
        test qword ptr [rbp + 16], PAN_EXPLAIN
        jz 1f
        mov rax, [rsp + PO_EXPLAIN]     # what --explain printed, then the text
        test rax, rax
        jz 1f
        mov rdi, [rsp + PO_EXPLAINLEN]
        add rdi, [rsp + PO_TEXTLEN]
        inc rdi
        call malloc@PLT
        test rax, rax
        jz 2f
        mov r12, rax
        mov rdi, rax
        mov rsi, [rsp + PO_EXPLAIN]
        mov rdx, [rsp + PO_EXPLAINLEN]
        call memcpy@PLT
        mov rdi, r12
        add rdi, [rsp + PO_EXPLAINLEN]
        mov rsi, [rsp + PO_TEXT]
        mov rdx, [rsp + PO_TEXTLEN]
        inc rdx                         # (and the NUL)
        call memcpy@PLT
        mov rdi, [rsp + PO_TEXT]
        call free@PLT
        mov [rsp + PO_TEXT], r12
        mov rax, [rsp + PO_EXPLAINLEN]
        add [rsp + PO_TEXTLEN], rax
2:      mov rdi, [rsp + PO_EXPLAIN]
        call free@PLT
1:      mov rcx, [rbp - 8]
        mov rdx, [rsp + PO_TEXT]
        mov [rcx], rdx
        mov rcx, [rbp - 16]
        mov rdx, [rsp + PO_TEXTLEN]
        mov [rcx], rdx
        mov eax, ebx
        mov rbx, [rbp - 24]
        mov r12, [rbp - 32]
        mov rsp, rbp                    # (not `leave`: the macro LEAVE, for gas)
        pop rbp
        ret
ENDF pan_decompile_ex

# int pan_decompile_data(code, len, threads, only_func, flags, pan_output *po)
# the text, as pan_decompile_ex's, and python's decompilation.json in
# po->data: its JSON text (flags: PAN_JSON), or the binary form data.s
# describes (for the python module, which makes python's objects of it).
# With PAN_EXPLAIN, what python's --explain printed in po->explain (and
# not before the text). Returns 0, or -1 with the error's message as the
# text (and no data).
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
        # python's "--verbose" / "--explain" in sys.argv
        xor eax, eax
        mov rcx, [rsp + 32]
        test rcx, PAN_VERBOSE
        jz 01f
        or eax, VB_ASM
01:     test rcx, PAN_EXPLAIN
        jz 05f
        or eax, VB_ASM | VB_EXPLAIN
05:     test rcx, PAN_REPR
        jz 06f
        or eax, VB_REPR
06:     test rcx, PAN_RETURNS
        jz 02f
        or eax, VB_RETURNS
02:     mov [r15 + CTX_VERBOSE], rax
        mov qword ptr [rsp + 56], 0     # --explain's builder
        test eax, VB_EXPLAIN
        jz 03f
        call sb_new
        mov [rsp + 56], rax
        mov [r15 + CTX_EXPLAIN_SB], rax
03:     xor r13d, r13d                  # the data (its builder)
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
        mov rdi, [rsp + 56]             # --explain's text: its colors, like the text's
        test rdi, rdi
        jz 04f
        test qword ptr [rsp + 32], PAN_NO_COLOR
        jz 04f
        call strip_color
04:     test ebx, ebx
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
        test qword ptr [rsp + 32], PAN_EXPLAIN
        jz 41f
        xor ecx, ecx
        xor edx, edx
        mov rdi, [rsp + 56]
        test rdi, rdi
        jz 42f
        mov rcx, [rdi + SB_BUF]
        mov rdx, [rdi + SB_LEN]
42:     mov [rax + PO_EXPLAIN], rcx
        mov [rax + PO_EXPLAINLEN], rdx
        test rdi, rdi
        jz 41f
        call free@PLT                   # (the builder, not its buffer)
41:     mov rdi, r12
        call free@PLT                   # the builders, not their buffers
        test r13, r13
        jz 5f
        mov rdi, r13
        call free@PLT
5:      mov qword ptr [r15 + CTX_DATA_SB], 0
        mov qword ptr [r15 + CTX_EXPLAIN_SB], 0
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
        test qword ptr [rsp + 32], PAN_EXPLAIN
        jz 8f
        mov qword ptr [rcx + PO_EXPLAIN], 0
        mov qword ptr [rcx + PO_EXPLAINLEN], 0
8:      mov eax, -1
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
