# Files: reading them whole, writing buffers.

.include "defs.inc"

        .text

        # the biggest file read whole, the same an answer from a node gets
        # (RESP_MAX): past it, "can't read the file" rather than a
        # truncated contract
        .set READ_FILE_MAX, 256 << 20

# read_file(path, &len) -> rax: malloc'ed contents (NUL-terminated), or 0.
# A regular file only, of READ_FILE_MAX at most: the command line tries
# its argument as a path, and a character device or a fifo named there
# was read without end - /dev/zero took the memory until malloc failed
# (which aborts), a fifo waited for ever.
FUNC read_file
        ENTER
        sub rsp, 160                    # a struct stat (144 bytes)
        mov r12, rsi                    # &len
        mov esi, 2048                   # O_RDONLY | O_NONBLOCK: opening a
        call open@PLT                   # fifo waits for a writer, which is
        test eax, eax                   # before the fstat below could refuse
        js .Lrf_fail                    # it (a regular file reads the same)
        mov ebx, eax                    # fd
        mov edi, ebx
        mov rsi, rsp
        call fstat@PLT
        test eax, eax
        js .Lrf_close_fail
        mov eax, [rsp + 24]             # st_mode
        and eax, 0xf000                 # S_IFMT
        cmp eax, 0x8000                 # S_IFREG
        jne .Lrf_close_fail
        mov rax, [rsp + 48]             # st_size
        cmp rax, READ_FILE_MAX
        ja .Lrf_close_fail
        mov edi, ebx
        mov esi, READ_FILE_MAX          # (a backstop: a file can grow
        call read_fd_max                # between the fstat and the read)
        mov r14, rax
        mov [r12], rdx
        mov edi, ebx
        call close@PLT
        mov rax, r14
        add rsp, 160
        LEAVE
.Lrf_close_fail:
        mov edi, ebx
        call close@PLT
.Lrf_fail:
        xor eax, eax
        add rsp, 160
        LEAVE
ENDF read_file

# read_fd(fd) -> rax: malloc'ed contents (NUL-terminated), rdx: the
# length - of READ_FILE_MAX at most (the bytecode on standard input: what
# is piped in has to end somewhere, whoever pipes it)
FUNC read_fd
        mov esi, READ_FILE_MAX
        jmp read_fd_max
ENDF read_fd

# read_fd_max(fd, max) -> rax, rdx: the same, no more than max bytes read
# (0: no limit) - what a socket gives has to end somewhere, whoever is at
# the other end
FUNC read_fd_max
        ENTER
        sub rsp, 16
        mov [rsp], rsi                  # max
        mov ebx, edi
        mov r13d, 65536                 # the capacity
        mov rdi, r13
        call xmalloc
        mov r14, rax
        xor r12d, r12d                  # read so far
1:      mov rcx, [rsp]                  # past the limit: what came so far
        test rcx, rcx
        jz 4f
        cmp r12, rcx
        jae 3f
4:      mov rax, r13
        sub rax, r12
        cmp rax, 1
        ja 2f
        shl r13, 1
        mov rdi, r14
        mov rsi, r13
        call xrealloc
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

# write_all(fd, buf, len) -> eax: the whole buffer, whatever write() takes at
# a time (0), or -1 on an error
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
        jle 3f
        add r12, rax
        sub r13, rax
        jmp 1b
2:      xor eax, eax
        LEAVE
3:      js 4f
        mov eax, -1                     # nothing written: stop
        LEAVE
4:      call __errno_location@PLT
        cmp dword ptr [rax], 4          # EINTR: again
        je 1b
        mov eax, -1
        LEAVE
ENDF write_all

        .section .note.GNU-stack,"",@progbits
