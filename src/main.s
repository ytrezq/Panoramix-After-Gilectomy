# Command line tool.
#   panasm disasm <file.hex>                    the disassembly, like Loader.disasm()
#   panasm decompile <file.hex|-> [options]     the decompilation, like `python -m panoramix`
# Options: -j N / --threads N (default: the CPUs), --function NAME (only
# the functions whose name starts with NAME), --no-color, --json (python's
# decompilation.json instead of the text, as json.dumps writes it).
# The file holds the bytecode in hex (0x optional); - reads it from stdin;
# an argument that is no file but hex is the bytecode itself (as python -m
# panoramix takes it).

.include "defs.inc"

        .section .rodata
.Lusage:  .ascii "usage: panasm disasm <file.hex>\n"
          .ascii "       panasm decompile <file.hex|-> [-j threads] [--function name] [--no-color] [--json]\n"
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
.Ls_badhex:     .asciz "not a valid hex file\n"
.Ls_noread:     .asciz "can't read the file\n"
.Ls_main:       .asciz "panoramix.main"
.Lf_loaded:     .asciz "%u bytes of code, %u instructions, %u jumpdests"

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

FUNC main
        push r15
        ENTER
        sub rsp, 72                     # 5 pushes + r15: 8 mod 16 keeps rsp aligned
        .set M_LEN, 0
        .set M_CODELEN, 8
        .set M_LOADER, 16
        .set M_THREADS, 24
        .set M_FUNCTION, 32
        .set M_NOCOLOR, 40
        .set M_PATH, 48
        .set M_I, 56
        .set M_JSON, 64
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
3:      mov rdi, rbx
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
5:      # the hex, from the file or stdin
        mov rdi, [rsp + M_PATH]
        lea rsi, [rip + .Ls_dash]
        call strcmp@PLT
        test eax, eax
        jnz 6f
        xor edi, edi
        call read_fd
        mov [rsp + M_LEN], rdx
        jmp 7f
6:      mov rdi, [rsp + M_PATH]
        lea rsi, [rsp + M_LEN]
        call read_file
        test rax, rax
        jnz 7f
        mov rdi, [rsp + M_PATH]         # no file: the bytecode itself?
        call is_hex_arg
        test eax, eax
        jz .Lnoread
        mov rdi, [rsp + M_PATH]
        call strlen@PLT
        mov [rsp + M_LEN], rax
        mov rax, [rsp + M_PATH]
7:      mov rbx, rax                    # hex text
        mov rdi, [rsp + M_LEN]
        call xmalloc
        mov r14, rax                    # bytes
        mov rdi, rbx
        mov rsi, [rsp + M_LEN]
        mov rdx, r14
        call hex_decode
        cmp rax, -1
        je .Lbadhex
        mov [rsp + M_CODELEN], rax
        # the command
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
        jmp .Lwrite_exit
.Ldecompile:
        cmp qword ptr [rsp + M_JSON], 0
        je 8f
        call sb_new                     # python's json, as json.dumps writes it
        mov [r15 + CTX_DATA_SB], rax
        mov qword ptr [r15 + CTX_DATA_MODE], 1
8:      call sb_new
        mov rbx, rax
        mov rdi, r14
        mov rsi, [rsp + M_CODELEN]
        mov rdx, [rsp + M_THREADS]
        mov rcx, [rsp + M_FUNCTION]
        mov r8, rbx
        call decompile_run
        test eax, eax
        jnz .Lfailed
        cmp qword ptr [rsp + M_JSON], 0
        je 9f
        mov rbx, [r15 + CTX_DATA_SB]    # the json instead of the text
        mov rdi, rbx
        mov esi, 10
        call sb_append_char
        jmp .Lwrite_exit
9:      mov rdi, rbx
        mov esi, 10                     # (python's print adds a newline)
        call sb_append_char
        cmp qword ptr [rsp + M_NOCOLOR], 0
        je .Lwrite_exit
        mov rdi, rbx
        call strip_color
.Lwrite_exit:
        mov edi, 1
        mov rsi, [rbx + SB_BUF]
        mov rdx, [rbx + SB_LEN]
        call write_all
        xor eax, eax
        jmp .Lmain_exit
.Lfailed:
        mov rdi, rbx                    # the message, on stderr
        mov esi, 10
        call sb_append_char
        mov edi, 2
        mov rsi, [rbx + SB_BUF]
        mov rdx, [rbx + SB_LEN]
        call write_all
        mov eax, 1
        jmp .Lmain_exit
.Lusage_exit:
        mov edi, 2
        lea rsi, [rip + .Lusage]
        mov edx, .Lusage_end - .Lusage
        call write@PLT
        mov eax, 2
        jmp .Lmain_exit
.Lbadhex:
        mov edi, 2
        lea rsi, [rip + .Ls_badhex]
        mov edx, 21
        call write@PLT
        mov eax, 1
        jmp .Lmain_exit
.Lnoread:
        mov edi, 2
        lea rsi, [rip + .Ls_noread]
        mov edx, 20
        call write@PLT
        mov eax, 1
.Lmain_exit:
        add rsp, 72
        LEAVE_NORET
        pop r15
        ret
ENDF main


        .section .note.GNU-stack,"",@progbits
