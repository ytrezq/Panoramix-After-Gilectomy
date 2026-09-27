# Command line tool.
#   panasm disasm <file.hex>      the disassembly, like Loader.disasm()
#   panasm decompile <file.hex>   (later)

.include "defs.inc"

        .section .rodata
.Lusage:  .ascii "usage: panasm disasm <file.hex>\n"
          .ascii "       panasm decompile <file.hex> [-j threads]\n"
.Lusage_end:
.Ls_disasm: .asciz "disasm"
.Ls_badhex: .asciz "not a valid hex file\n"
.Ls_noread: .asciz "can't read the file\n"
.Ls_main:   .asciz "panoramix.main"
.Lf_loaded: .asciz "%u bytes of code, %u instructions, %u jumpdests"

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
        xor esi, esi
        mov edx, 2                      # SEEK_END
        call lseek@PLT
        mov r13, rax                    # size
        mov edi, ebx
        xor esi, esi
        xor edx, edx                    # SEEK_SET
        call lseek@PLT
        lea rdi, [r13 + 1]
        call malloc@PLT
        mov r14, rax
        xor ecx, ecx                    # read so far
1:      cmp rcx, r13
        jae 2f
        push rcx
        push rcx
        mov edi, ebx
        lea rsi, [r14 + rcx]
        mov rdx, r13
        sub rdx, rcx
        call read@PLT
        pop rcx
        pop rcx
        test rax, rax
        jle 2f
        add rcx, rax
        jmp 1b
2:      mov byte ptr [r14 + rcx], 0
        mov [r12], rcx
        mov edi, ebx
        push rcx
        push rcx
        call close@PLT
        pop rcx
        pop rcx
        mov rax, r14
        LEAVE
.Lrf_fail:
        xor eax, eax
        LEAVE
ENDF read_file

FUNC main
        push r15
        ENTER
        sub rsp, 40                     # 5 pushes + r15: 40 keeps rsp aligned
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
        mov rdi, [r13 + 8]
        lea rsi, [rip + .Ls_disasm]
        call strcmp@PLT
        test eax, eax
        jnz .Lusage_exit
        # read the hex file
        mov rdi, [r13 + 16]
        lea rsi, [rsp]
        call read_file
        test rax, rax
        jz .Lnoread
        mov rbx, rax                    # hex text
        mov rdi, [rsp]
        call malloc@PLT
        mov r14, rax                    # bytes
        mov rdi, rbx
        mov rsi, [rsp]
        mov rdx, r14
        call hex_decode
        cmp rax, -1
        je .Lbadhex
        mov [rsp + 8], rax              # code length
        call loader_new
        mov [rsp + 16], rax
        mov rdi, rax
        mov rsi, r14
        mov rdx, [rsp + 8]
        call loader_load
        mov rdi, LOG_DEBUG
        lea rsi, [rip + .Ls_main]
        lea rdx, [rip + .Lf_loaded]
        mov rax, [rsp + 16]
        mov rcx, [rax + LD_CODELEN]
        mov r8, [rax + LD_NINSTR]
        mov r9, [rax + LD_NJUMPDESTS]
        call log_fmt
        call sb_new
        mov rbx, rax
        mov rdi, [rsp + 16]
        mov rsi, rbx
        call loader_disasm
        mov edi, 1
        mov rsi, [rbx + SB_BUF]
        mov rdx, [rbx + SB_LEN]
        call write@PLT
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
        add rsp, 40
        LEAVE_NORET
        pop r15
        ret
ENDF main

        .section .note.GNU-stack,"",@progbits
