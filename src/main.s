# Command line tool.
#   panasm disasm <input>                       the disassembly, like Loader.disasm()
#   panasm decompile <input[,input...]> [options]   the decompilation, like `python -m panoramix`
# Options: -j N / --threads N (default: the CPUs), --function NAME (only
# the functions whose name starts with NAME), --no-color, --json (python's
# decompilation.json instead of the text, as json.dumps writes it), -v
# LEVEL (the log level, a number or a name, as python -m panoramix's).
# An input is a file holding the bytecode in hex (0x optional), - (the
# bytecode on stdin), an address (0x and 40 hex digits: its code fetched
# from a node, as python's decompile_address does - see fetch.s), or the
# bytecode itself in hex (as python -m panoramix takes it). A
# comma-separated list of them is decompiled one after the other, as
# python -m panoramix does.

.include "defs.inc"

        .section .rodata
.Lusage:  .ascii "usage: panasm disasm <file.hex|->\n"
          .ascii "       panasm decompile <file.hex|-|address|bytecode>[,...] [-j threads] [--function name]\n"
          .ascii "                        [--no-color] [--json] [-v level] [--verbose] [--explain] [--repr] [--returns]\n"
          .ascii "       panasm build-db <abi_dump.xz> [out.bin]\n"
.Lusage_end:
.Ls_disasm:     .asciz "disasm"
.Ls_decompile:  .asciz "decompile"
.Ls_build_db:   .asciz "build-db"
.Ls_dash:       .asciz "-"
.Ls_j:          .asciz "-j"
.Ls_threads:    .asciz "--threads"
.Ls_function:   .asciz "--function"
.Ls_no_color:   .asciz "--no-color"
.Ls_json:       .asciz "--json"
.Ls_verbose:    .asciz "--verbose"
.Ls_explain:    .asciz "--explain"
.Ls_repr:       .asciz "--repr"
.Ls_returns:    .asciz "--returns"
.Ls_v:          .asciz "-v"
.Ls_badlevel:   .asciz "Logging should be DEBUG/INFO/WARNING/ERROR.\n"
.Ls_badlevel_end:
.Ls_badhex:     .asciz "not a valid hex file: "
.Ls_noread:     .asciz "can't read the file: "
.Ls_main:       .asciz "panoramix.main"
.Lf_loaded:     .asciz "%u bytes of code, %u instructions, %u jumpdests"

        # main's frame, which decompile_one reads the options from
        .set M_LEN, 0
        .set M_CODELEN, 8
        .set M_LOADER, 16
        .set M_THREADS, 24
        .set M_FUNCTION, 32
        .set M_NOCOLOR, 40
        .set M_PATH, 48
        .set M_I, 56
        .set M_JSON, 64
        .set M_VERBOSE, 72              # VB_ASM, VB_EXPLAIN...
        .set M_STATUS, 80
        .set M_SIZEOF, 88

        .text

# is_hex_arg(cstr) -> eax: hex digits (at least one), 0x first or not
FUNC is_hex_arg
        xor eax, eax
        cmp byte ptr [rdi], '0'
        jne 1f
        mov cl, [rdi + 1]
        or cl, 0x20
        cmp cl, 'x'
        jne 1f
        add rdi, 2
1:      cmp byte ptr [rdi], 0
        je 4f
2:      movzx ecx, byte ptr [rdi]
        test ecx, ecx
        jz 3f
        inc rdi
        sub ecx, '0'
        cmp ecx, 9
        jbe 2b
        or ecx, 0x20
        sub ecx, 'a' - '0'
        cmp ecx, 5
        jbe 2b
        ret                             # (not a hex digit)
3:      mov eax, 1
4:      ret
ENDF is_hex_arg

# is_address_arg(cstr) -> eax: 42 characters starting with 0x - what
# python -m panoramix takes for an address (len(arg) == 42)
FUNC is_address_arg
        xor eax, eax
        cmp byte ptr [rdi], '0'
        jne 1f
        movzx ecx, byte ptr [rdi + 1]
        or ecx, 0x20
        cmp ecx, 'x'
        jne 1f
        ENTER
        call strlen@PLT
        cmp rax, 42
        sete al
        movzx eax, al
        LEAVE
1:      ret
ENDF is_address_arg

# err_line(msg, arg): "msg" "arg" and a newline, on stderr
FUNC err_line
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call sb_new
        mov r13, rax
        mov rdi, r13
        mov rsi, rbx
        call sb_append_c
        mov rdi, r13
        mov rsi, r12
        call sb_append_c
        mov rdi, r13
        mov esi, 10
        call sb_append_char
        mov edi, 2
        mov rsi, [r13 + SB_BUF]
        mov rdx, [r13 + SB_LEN]
        call write_all
        mov rdi, r13
        call sb_free
        LEAVE
ENDF err_line

# input_code(input) -> rax: the bytecode (malloc'ed), rdx its length; or
# rax 0, the reason printed on stderr. The input: a file, "-" (stdin), an
# address (fetched), or the bytecode in hex.
FUNC input_code
        ENTER
        sub rsp, 16
        mov rbx, rdi
        lea rsi, [rip + .Ls_dash]
        call strcmp@PLT
        test eax, eax
        jnz 1f
        xor edi, edi
        call read_fd
        mov rbx, rax                    # stripped (python's .strip()): an address?
        lea rcx, [rax + rdx]
71:     cmp rcx, rbx
        jbe 72f
        movzx eax, byte ptr [rcx - 1]
        cmp eax, ' '
        ja 72f
        dec rcx
        jmp 71b
72:     mov byte ptr [rcx], 0
73:     movzx eax, byte ptr [rbx]
        test eax, eax
        jz 74f
        cmp eax, ' '
        ja 74f
        inc rbx
        jmp 73b
74:     mov rdi, rbx
        call is_address_arg
        test eax, eax
        jnz .Lic_address
        mov rdi, rbx
        call strlen@PLT
        mov rdx, rax
        mov rax, rbx
        jmp .Lic_hex
1:      mov rdi, rbx
        mov rsi, rsp
        call read_file
        test rax, rax
        jz 2f
        mov rdx, [rsp]
        jmp .Lic_hex
2:      mov rdi, rbx                    # no file: an address?
        call is_address_arg
        test eax, eax
        jz 3f
.Lic_address:
        call sb_new
        mov r12, rax
        mov rdi, rbx
        mov rsi, r12
        call fetch_code
        test eax, eax
        jnz .Lic_fetch_failed
        mov rax, [r12 + SB_BUF]
        mov rdx, [r12 + SB_LEN]
        mov rdi, r12
        push rax
        push rdx
        call free@PLT                   # (the builder, not its buffer)
        pop rdx
        pop rax
        jmp .Lic_hex
3:      mov rdi, rbx                    # the bytecode itself?
        call is_hex_arg
        test eax, eax
        jz .Lic_noread
        mov rdi, rbx
        call strlen@PLT
        mov rdx, rax
        mov rax, rbx
.Lic_hex:
        mov r12, rax                    # the hex text
        mov r13, rdx
        lea rdi, [rdx + 1]
        call xmalloc
        mov r14, rax
        mov rdi, r12
        mov rsi, r13
        mov rdx, r14
        call hex_decode
        cmp rax, -1
        je .Lic_badhex
        mov rdx, rax
        mov rax, r14
        add rsp, 16
        LEAVE
.Lic_badhex:
        mov rdi, r14
        call free@PLT
        lea rdi, [rip + .Ls_badhex]
        mov rsi, rbx
        call err_line
        xor eax, eax
        add rsp, 16
        LEAVE
.Lic_fetch_failed:
        mov rdi, [r12 + SB_BUF]
        lea rsi, [rip + .Ls_dash + 1]   # ("")
        call err_line
        mov rdi, r12
        call sb_free
        xor eax, eax
        add rsp, 16
        LEAVE
.Lic_noread:
        lea rdi, [rip + .Ls_noread]
        mov rsi, rbx
        call err_line
        xor eax, eax
        add rsp, 16
        LEAVE
ENDF input_code

# decompile_one(frame, input) -> eax: 0, or 1 when it failed (the message
# printed). The options are read from main's frame.
FUNC decompile_one
        ENTER
        sub rsp, 32
        .set DO_EXPLAIN, 0              # --explain's builder
        .set DO_CODE, 8
        .set DO_CODELEN, 16
        .set DO_STATUS, 24
        mov rbx, rdi                    # the frame
        mov rdi, rsi
        call input_code
        test rax, rax
        jz .Ldo_no_input
        mov [rsp + DO_CODE], rax
        mov [rsp + DO_CODELEN], rdx
        mov qword ptr [r15 + CTX_DATA_SB], 0
        mov qword ptr [r15 + CTX_DATA_MODE], 0
        cmp qword ptr [rbx + M_JSON], 0
        je 1f
        call sb_new                     # python's json, as json.dumps writes it
        mov [r15 + CTX_DATA_SB], rax
        mov qword ptr [r15 + CTX_DATA_MODE], 1
1:      mov rax, [rbx + M_VERBOSE]
        mov [r15 + CTX_VERBOSE], rax
        mov qword ptr [rsp + DO_EXPLAIN], 0
        mov qword ptr [r15 + CTX_EXPLAIN_SB], 0
        test rax, VB_EXPLAIN
        jz 2f
        call sb_new                     # (what python prints as it goes)
        mov [rsp + DO_EXPLAIN], rax
        mov [r15 + CTX_EXPLAIN_SB], rax
2:      call sb_new
        mov r12, rax                    # the text
        mov rdi, [rsp + DO_CODE]
        mov rsi, [rsp + DO_CODELEN]
        mov rdx, [rbx + M_THREADS]
        mov rcx, [rbx + M_FUNCTION]
        mov r8, r12
        call decompile_run
        mov [rsp + DO_STATUS], rax
        mov rdi, [rsp + DO_EXPLAIN]     # --explain's text first
        test rdi, rdi
        jz 4f
        cmp qword ptr [rbx + M_NOCOLOR], 0
        je 3f
        call strip_color
3:      mov rax, [rsp + DO_EXPLAIN]
        mov edi, 1
        mov rsi, [rax + SB_BUF]
        mov rdx, [rax + SB_LEN]
        call write_all
        mov rdi, [rsp + DO_EXPLAIN]
        call sb_free
        mov qword ptr [r15 + CTX_EXPLAIN_SB], 0
4:      mov eax, [rsp + DO_STATUS]
        test eax, eax
        jnz .Ldo_failed
        mov r13, r12
        cmp qword ptr [rbx + M_JSON], 0
        je 5f
        mov r13, [r15 + CTX_DATA_SB]    # the json instead of the text
        mov rdi, r13
        mov esi, 10
        call sb_append_char
        jmp 6f
5:      mov rdi, r12
        mov esi, 10                     # (python's print adds a newline)
        call sb_append_char
        cmp qword ptr [rbx + M_NOCOLOR], 0
        je 6f
        mov rdi, r12
        call strip_color
6:      mov edi, 1
        mov rsi, [r13 + SB_BUF]
        mov rdx, [r13 + SB_LEN]
        call write_all
        mov qword ptr [rsp + DO_STATUS], 0
        jmp .Ldo_done
.Ldo_failed:
        mov rdi, r12                    # the message, on stderr
        mov esi, 10
        call sb_append_char
        mov edi, 2
        mov rsi, [r12 + SB_BUF]
        mov rdx, [r12 + SB_LEN]
        call write_all
        mov qword ptr [rsp + DO_STATUS], 1
.Ldo_done:
        mov rdi, r12
        call sb_free
        mov rdi, [r15 + CTX_DATA_SB]
        test rdi, rdi
        jz 7f
        call sb_free
        mov qword ptr [r15 + CTX_DATA_SB], 0
7:      mov rdi, [rsp + DO_CODE]
        call free@PLT
        mov eax, [rsp + DO_STATUS]
        add rsp, 32
        LEAVE
.Ldo_no_input:
        mov eax, 1
        add rsp, 32
        LEAVE
ENDF decompile_one

FUNC main
        push r15
        ENTER
        sub rsp, M_SIZEOF               # 5 pushes + r15: 8 mod 16 keeps rsp aligned
        mov r12, rdi                    # argc
        mov r13, rsi                    # argv
        call rt_init
        call log_init
        call ctx_new
        mov r15, rax
        mov rdi, r15
        call ctx_bind
        cmp r12, 3
        jl .Lusage_exit
        # build-db <xz> [out]
        mov rdi, [r13 + 8]
        lea rsi, [rip + .Ls_build_db]
        call strcmp@PLT
        test eax, eax
        jnz 0f
        xor esi, esi
        cmp r12, 4
        jb 01f
        mov rsi, [r13 + 24]
01:     mov rdi, [r13 + 16]
        call sigdb_build
        jmp .Lmain_exit
0:      # the options
        mov edi, 84                     # _SC_NPROCESSORS_ONLN
        call sysconf@PLT
        test rax, rax
        jg 1f
        mov eax, 1
1:      mov [rsp + M_THREADS], rax
        mov qword ptr [rsp + M_FUNCTION], 0
        mov qword ptr [rsp + M_NOCOLOR], 0
        mov qword ptr [rsp + M_JSON], 0
        mov qword ptr [rsp + M_VERBOSE], 0
        mov rax, [r13 + 16]
        mov [rsp + M_PATH], rax
        mov qword ptr [rsp + M_I], 3
2:      mov rax, [rsp + M_I]
        cmp rax, r12
        jae 5f
        mov rbx, [r13 + rax*8]
        mov rdi, rbx
        lea rsi, [rip + .Ls_no_color]
        call strcmp@PLT
        test eax, eax
        jnz 3f
        mov qword ptr [rsp + M_NOCOLOR], 1
        inc qword ptr [rsp + M_I]
        jmp 2b
3:      mov rdi, rbx                    # --verbose: the lines of assembly
        lea rsi, [rip + .Ls_verbose]
        call strcmp@PLT
        test eax, eax
        jnz 33f
        or qword ptr [rsp + M_VERBOSE], VB_ASM
        inc qword ptr [rsp + M_I]
        jmp 2b
33:     mov rdi, rbx                    # --explain: every stage's trace too
        lea rsi, [rip + .Ls_explain]
        call strcmp@PLT
        test eax, eax
        jnz 34f
        or qword ptr [rsp + M_VERBOSE], VB_ASM | VB_EXPLAIN
        inc qword ptr [rsp + M_I]
        jmp 2b
34:     mov rdi, rbx                    # --repr, --returns: python's, from sys.argv
        lea rsi, [rip + .Ls_repr]
        call strcmp@PLT
        test eax, eax
        jnz 35f
        or qword ptr [rsp + M_VERBOSE], VB_REPR
        inc qword ptr [rsp + M_I]
        jmp 2b
35:     mov rdi, rbx
        lea rsi, [rip + .Ls_returns]
        call strcmp@PLT
        test eax, eax
        jnz 36f
        or qword ptr [rsp + M_VERBOSE], VB_RETURNS
        inc qword ptr [rsp + M_I]
        jmp 2b
36:     mov rdi, rbx
        lea rsi, [rip + .Ls_json]
        call strcmp@PLT
        test eax, eax
        jnz 32f
        mov qword ptr [rsp + M_JSON], 1
        inc qword ptr [rsp + M_I]
        jmp 2b
32:     mov rdi, rbx
        lea rsi, [rip + .Ls_j]
        call strcmp@PLT
        test eax, eax
        jz 31f
        mov rdi, rbx
        lea rsi, [rip + .Ls_threads]
        call strcmp@PLT
        test eax, eax
        jnz 4f
31:     mov rax, [rsp + M_I]
        inc rax
        cmp rax, r12
        jae .Lusage_exit
        mov rdi, [r13 + rax*8]
        call atol@PLT
        mov [rsp + M_THREADS], rax
        add qword ptr [rsp + M_I], 2
        jmp 2b
4:      mov rdi, rbx
        lea rsi, [rip + .Ls_v]
        call strcmp@PLT
        test eax, eax
        jnz 41f
        mov rax, [rsp + M_I]            # -v LEVEL: a number, or a name
        inc rax
        cmp rax, r12
        jae .Lusage_exit
        mov rbx, [r13 + rax*8]
        movzx eax, byte ptr [rbx]
        sub eax, '0'
        cmp eax, 9
        ja 42f
        mov rdi, rbx
        call atol@PLT
        jmp 43f
42:     mov rdi, rbx
        call log_level_from_name
        test rax, rax
        js .Lbadlevel
43:     mov rdi, rax
        call pan_set_log_level
        add qword ptr [rsp + M_I], 2
        jmp 2b
41:     mov rdi, rbx
        lea rsi, [rip + .Ls_function]
        call strcmp@PLT
        test eax, eax
        jnz .Lusage_exit
        mov rax, [rsp + M_I]
        inc rax
        cmp rax, r12
        jae .Lusage_exit
        mov rdi, [r13 + rax*8]
        mov [rsp + M_FUNCTION], rdi
        add qword ptr [rsp + M_I], 2
        jmp 2b
5:      # the command
        mov rdi, [r13 + 8]
        lea rsi, [rip + .Ls_decompile]
        call strcmp@PLT
        test eax, eax
        jz .Ldecompile
        mov rdi, [r13 + 8]
        lea rsi, [rip + .Ls_disasm]
        call strcmp@PLT
        test eax, eax
        jnz .Lusage_exit
        mov rdi, [rsp + M_PATH]
        call input_code
        test rax, rax
        jz .Lfail_exit
        mov r14, rax
        mov [rsp + M_CODELEN], rdx
        call loader_new
        mov [rsp + M_LOADER], rax
        mov rdi, rax
        mov rsi, r14
        mov rdx, [rsp + M_CODELEN]
        call loader_load
        mov rdi, LOG_DEBUG
        lea rsi, [rip + .Ls_main]
        lea rdx, [rip + .Lf_loaded]
        mov rax, [rsp + M_LOADER]
        mov rcx, [rax + LD_CODELEN]
        mov r8, [rax + LD_NINSTR]
        mov r9, [rax + LD_NJUMPDESTS]
        call log_fmt
        call sb_new
        mov rbx, rax
        mov rdi, [rsp + M_LOADER]
        mov rsi, rbx
        call loader_disasm
        mov edi, 1
        mov rsi, [rbx + SB_BUF]
        mov rdx, [rbx + SB_LEN]
        call write_all
        xor eax, eax
        jmp .Lmain_exit
.Ldecompile:
        # a list separated by commas (unless it is a file's name): each
        # in turn, as python -m panoramix does
        mov qword ptr [rsp + M_STATUS], 0
        mov rdi, [rsp + M_PATH]
        mov esi, ','
        call strchr@PLT
        test rax, rax
        jz 7f
        mov rdi, [rsp + M_PATH]
        mov esi, 4                      # R_OK
        call access@PLT
        test eax, eax
        jz 7f
        mov rdi, [rsp + M_PATH]
        call strdup@PLT
        mov rbx, rax                    # the part's start
6:      mov rdi, rbx
        mov esi, ','
        call strchr@PLT
        mov r14, rax                    # its end (0: the last one)
        test rax, rax
        jz 61f
        mov byte ptr [rax], 0
61:     mov rdi, rsp
        mov rsi, rbx
        call decompile_one
        or [rsp + M_STATUS], rax
        test r14, r14
        jz 8f
        lea rbx, [r14 + 1]
        jmp 6b
7:      mov rdi, rsp
        mov rsi, [rsp + M_PATH]
        call decompile_one
        mov [rsp + M_STATUS], rax
8:      mov eax, [rsp + M_STATUS]
        jmp .Lmain_exit
.Lbadlevel:
        mov edi, 2
        lea rsi, [rip + .Ls_badlevel]
        mov edx, .Ls_badlevel_end - .Ls_badlevel - 1
        call write@PLT
.Lfail_exit:
        mov eax, 1
        jmp .Lmain_exit
.Lusage_exit:
        mov edi, 2
        lea rsi, [rip + .Lusage]
        mov edx, .Lusage_end - .Lusage
        call write@PLT
        mov eax, 2
.Lmain_exit:
        add rsp, M_SIZEOF
        LEAVE_NORET
        pop r15
        ret
ENDF main


        .section .note.GNU-stack,"",@progbits
