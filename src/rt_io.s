# Files: reading them whole, writing buffers.

.include "defs.inc"

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
