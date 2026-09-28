# Command line tool.
#   panasm disasm <file.hex>                    the disassembly, like Loader.disasm()
#   panasm decompile <file.hex|-> [options]     the decompilation, like `python -m panoramix`
# Options: -j N / --threads N (default: the CPUs), --function NAME (only
# the functions whose name starts with NAME), --no-color.
# The file holds the bytecode in hex (0x optional); - reads it from stdin.

.include "defs.inc"

        .section .rodata
.Lusage:  .ascii "usage: panasm disasm <file.hex>\n"
          .ascii "       panasm decompile <file.hex|-> [-j threads] [--function name] [--no-color]\n"
.Lusage_end:
.Ls_disasm:     .asciz "disasm"
.Ls_decompile:  .asciz "decompile"
.Ls_dash:       .asciz "-"
.Ls_j:          .asciz "-j"
.Ls_threads:    .asciz "--threads"
.Ls_function:   .asciz "--function"
.Ls_no_color:   .asciz "--no-color"
.Ls_badhex:     .asciz "not a valid hex file\n"
.Ls_noread:     .asciz "can't read the file\n"
.Ls_main:       .asciz "panoramix.main"
.Lf_loaded:     .asciz "%u bytes of code, %u instructions, %u jumpdests"

        .text

# read_file(path, &len) -> rax: malloc'ed contents (NUL-terminated), or 0
FUNC read_file
        ENTER
        mov r12, rsi                    # &len
        xor esi, esi                    # O_RDONLY
        call open@PLT
        test eax, eax
        js .Lrf_fail
        mov ebx, eax                    # fd
        mov edi, ebx
        call read_fd
        mov r14, rax
        mov [r12], rdx
        mov edi, ebx
        call close@PLT
        mov rax, r14
        LEAVE
.Lrf_fail:
        xor eax, eax
        LEAVE
ENDF read_file

# read_fd(fd) -> rax: malloc'ed contents (NUL-terminated), rdx: the length
FUNC read_fd
        ENTER
        sub rsp, 16
        mov ebx, edi
        mov r13d, 65536                 # the capacity
        mov rdi, r13
        call malloc@PLT
        mov r14, rax
        xor r12d, r12d                  # read so far
1:      mov rax, r13
        sub rax, r12
        cmp rax, 1
        ja 2f
        shl r13, 1
        mov rdi, r14
        mov rsi, r13
        call realloc@PLT
        mov r14, rax
2:      mov edi, ebx
        lea rsi, [r14 + r12]
        mov rdx, r13
        sub rdx, r12
        dec rdx
        call read@PLT
        test rax, rax
        jle 3f
        add r12, rax
        jmp 1b
3:      mov byte ptr [r14 + r12], 0
        mov rax, r14
        mov rdx, r12
        add rsp, 16
        LEAVE
ENDF read_fd

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
        # the options
        mov edi, 84                     # _SC_NPROCESSORS_ONLN
        call sysconf@PLT
        test rax, rax
        jg 1f
        mov eax, 1
1:      mov [rsp + M_THREADS], rax
        mov qword ptr [rsp + M_FUNCTION], 0
        mov qword ptr [rsp + M_NOCOLOR], 0
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
        jz .Lnoread
7:      mov rbx, rax                    # hex text
        mov rdi, [rsp + M_LEN]
        call malloc@PLT
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
        call sb_new
        mov rbx, rax
        mov rdi, r14
        mov rsi, [rsp + M_CODELEN]
        mov rdx, [rsp + M_THREADS]
        mov rcx, [rsp + M_FUNCTION]
        mov r8, rbx
        call decompile
        mov rdi, rbx
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

# write_all(fd, buf, len): the whole buffer, whatever write() takes at a time
FUNC write_all
        ENTER
        mov ebx, edi
        mov r12, rsi
        mov r13, rdx
1:      test r13, r13
        jz 2f
        mov edi, ebx
        mov rsi, r12
        mov rdx, r13
        call write@PLT
        test rax, rax
        jle 2f
        add r12, rax
        sub r13, rax
        jmp 1b
2:      LEAVE
ENDF write_all

        .section .note.GNU-stack,"",@progbits
