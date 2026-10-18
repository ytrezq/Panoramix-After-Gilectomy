# Files: reading them whole, writing buffers.

.include "defs.inc"

        .text

        # the most bytecode read whole from a file or standard input, the
        # same an answer from a node gets (RESP_MAX): past it, a refusal
        # rather than a contract cut short
        .set READ_FILE_MAX, 256 << 20
        # (and READ_DUMP_MAX, defs.inc: the most of a signature dump read
        # whole - /dev/zero named there was read until malloc failed, then
        # the buffer and the descriptor left behind, gigabytes a call)

# read_file(path, &len) -> rax: malloc'ed contents (NUL-terminated), or 0
# - a file of the operator's (the dump build-db or $PANORAMIX_ABI_DUMP
# names): any kind of file, a fifo or <(xz -c ...) too, of READ_DUMP_MAX
# at most. What throws meanwhile (the system's memory) closes it first.
# The command line's argument and the dump a database names, which may be
# anybody's, are read_regular_file's.
FUNC read_file
        ENTER
        sub rsp, ERR_SIZEOF + 16
        mov r12, rsi                    # &len
        xor esi, esi                    # O_RDONLY
        call open@PLT
        test eax, eax
        js .Lrf_fail
        mov ebx, eax                    # fd
        mov rdi, rsp
        call err_catch
        test eax, eax
        jnz .Lrf_threw
        mov edi, ebx
        mov esi, READ_DUMP_MAX + 1
        call read_fd_max
        mov r14, rax
        mov r13, rdx
        call err_end
        mov edi, ebx
        call close@PLT
        cmp r13, READ_DUMP_MAX
        ja .Lrf_free_fail
        mov [r12], r13
        mov rax, r14
        add rsp, ERR_SIZEOF + 16
        LEAVE
.Lrf_free_fail:
        mov rdi, r14
        call free@PLT
.Lrf_fail:
        xor eax, eax
        add rsp, ERR_SIZEOF + 16
        LEAVE
.Lrf_threw:                             # (read_fd_until freed its buffer)
        mov r13d, eax
        mov edi, ebx
        call close@PLT
        mov edi, r13d
        mov rsi, [r15 + CTX_ERR_MSG]
        call err_throw
ENDF read_file

# read_code_file(path, &len) -> rax: the same of the bytecode the command
# line was given as a path, or 0: read_regular_file's, of READ_FILE_MAX at
# most
FUNC read_code_file
        mov edx, READ_FILE_MAX
        jmp read_regular_file
ENDF read_code_file

# read_regular_file(path, &len, max) -> rax: the same, or 0: a regular file
# only, of max bytes at most - for a path that may be anybody's (the
# command line's argument, tried as a path; the dump a signature database
# names): a character device or a fifo named there was read without end
# (/dev/zero until malloc failed, which aborts; a fifo for ever).
FUNC read_regular_file
        ENTER
        sub rsp, 160 + ERR_SIZEOF
        .set RR_MAX, 144                # (a struct stat at 0: 144 bytes)
        .set RR_ERR, 160                # (what throws: the descriptor closed)
        mov r12, rsi                    # &len
        mov [rsp + RR_MAX], rdx
        mov esi, 2048                   # O_RDONLY | O_NONBLOCK: opening a
        call open@PLT                   # fifo waits for a writer, which is
        test eax, eax                   # before the fstat below could refuse
        js .Lrc_fail                    # it (a regular file reads the same)
        mov ebx, eax                    # fd
        mov edi, ebx
        mov rsi, rsp
        call fstat@PLT
        test eax, eax
        js .Lrc_close_fail
        mov eax, [rsp + 24]             # st_mode
        and eax, 0xf000                 # S_IFMT
        cmp eax, 0x8000                 # S_IFREG
        jne .Lrc_close_fail
        mov rax, [rsp + 48]             # st_size
        cmp rax, [rsp + RR_MAX]
        ja .Lrc_close_fail
        lea rdi, [rsp + RR_ERR]
        call err_catch
        test eax, eax
        jnz .Lrc_threw
        mov edi, ebx                    # one byte more than the limit, so
        mov rsi, [rsp + RR_MAX]         # that a file grown since the fstat
        inc rsi                         # is refused, not cut short
        call read_fd_max
        mov r14, rax
        mov r13, rdx
        call err_end
        mov edi, ebx
        call close@PLT
        cmp r13, [rsp + RR_MAX]
        ja .Lrc_free_fail
        mov [r12], r13
        mov rax, r14
        add rsp, 160 + ERR_SIZEOF
        LEAVE
.Lrc_free_fail:
        mov rdi, r14
        call free@PLT
        jmp .Lrc_fail
.Lrc_close_fail:
        mov edi, ebx
        call close@PLT
.Lrc_fail:
        xor eax, eax
        add rsp, 160 + ERR_SIZEOF
        LEAVE
.Lrc_threw:                             # (read_fd_until freed its buffer)
        mov r13d, eax
        mov edi, ebx
        call close@PLT
        mov edi, r13d
        mov rsi, [r15 + CTX_ERR_MSG]
        call err_throw
ENDF read_regular_file

# read_fd(fd) -> rax: malloc'ed contents (NUL-terminated), rdx: the
# length - or rax 0 past READ_FILE_MAX (the bytecode on standard input:
# what is piped in has to end somewhere, and what went past the limit was
# cut there and decompiled as if it were the contract)
FUNC read_fd
        ENTER
        mov esi, READ_FILE_MAX + 1
        call read_fd_max
        cmp rdx, READ_FILE_MAX
        jbe 1f
        mov rdi, rax
        call free@PLT
        xor eax, eax
        xor edx, edx
1:      LEAVE
ENDF read_fd

# read_fd_max(fd, max) -> rax, rdx: the same, no more than max bytes read
# (0: no limit) - what a socket gives has to end somewhere, whoever is at
# the other end
FUNC read_fd_max
        xor edx, edx                    # (no deadline)
        jmp read_fd_until
ENDF read_fd_max

# read_fd_until(fd, max, deadline) -> rax, rdx: the same, and no read begun
# once monotonic_ns has passed deadline (0: none) - ecx 1 when it stopped
# for that. A node's answer has to end in time as well as in size: each
# read has the socket's own timeout, but an answer of a byte every few
# seconds went on for as long as the node liked, and with it the call (and
# a CTRL+C, which only takes effect when the call returns). Without a
# deadline (standard input, a file), a descriptor with nothing to read yet
# (EAGAIN: O_NONBLOCK) is waited for - it was the end, the bytecode cut
# where a pipe had run dry; with one (a socket), EAGAIN is its own timeout
# that ran out. The memory the system refuses: E_MEMORY, as xmalloc's, the
# buffer freed first (it was left behind, a gigabyte at a time).
FUNC read_fd_until
        ENTER
        sub rsp, 32
        mov [rsp], rsi                  # max
        mov [rsp + 8], rdx              # the deadline (-1 once it is past)
        .set RU_POLL, 16                # (a struct pollfd)
        mov ebx, edi
        mov r13d, 65536                 # the capacity
        mov rdi, r13
        call malloc@PLT
        test rax, rax
        jz .Lru_oom0
        mov r14, rax
        xor r12d, r12d                  # read so far
1:      mov rcx, [rsp]                  # past the limit: what came so far
        test rcx, rcx
        jz 4f
        cmp r12, rcx
        jae 3f
4:      cmp qword ptr [rsp + 8], 0      # past the deadline: the same
        je 7f
        call monotonic_ns
        cmp rax, [rsp + 8]
        jb 7f
        mov qword ptr [rsp + 8], -1
        jmp 3f
7:      mov rax, r13
        sub rax, r12
        cmp rax, 1
        ja 2f
        shl r13, 1                      # (doubled, but no more than the
        mov rax, [rsp]                  # limit and its NUL: the buffer of
        test rax, rax                   # an answer of 256 MiB was 512)
        jz 71f
        inc rax
        cmp r13, rax
        cmova r13, rax
71:     mov rdi, r14
        mov rsi, r13
        call realloc@PLT
        test rax, rax
        jz .Lru_oom
        mov r14, rax
2:      mov edi, ebx
        lea rsi, [r14 + r12]
        mov rdx, r13
        sub rdx, r12
        dec rdx
        mov rcx, [rsp]                  # no read past the limit either: a
        test rcx, rcx                   # read of a whole buffer took the
        jz 21f                          # length past it, by as much as had
        sub rcx, r12                    # been read (what the limit is for:
        cmp rdx, rcx                    # max bytes, no more - > 0 here)
        cmova rdx, rcx
21:     call read@PLT
        test rax, rax
        jle 5f
        add r12, rax
        jmp 1b
5:      js 6f                           # 0: the end
3:      mov byte ptr [r14 + r12], 0
        xor ecx, ecx                    # (1: the deadline passed)
        cmp qword ptr [rsp + 8], -1
        sete cl
        mov rax, r14
        mov rdx, r12
        add rsp, 32
        LEAVE
6:      call __errno_location@PLT       # a signal is not the end: EINTR
        cmp dword ptr [rax], 4          # cut a bytecode on standard input
        je 1b                           # or a node's answer where the signal
        cmp dword ptr [rax], 11         # came (as write_all does it: again,
        jne 3b                          # the deadline checked first)
        cmp qword ptr [rsp + 8], 0      # EAGAIN, without a deadline: until
        jne 3b                          # there's something to read (or the
        mov [rsp + RU_POLL], ebx        # end, or an error: the read says)
        mov dword ptr [rsp + RU_POLL + 4], 1    # POLLIN (revents 0)
        lea rdi, [rsp + RU_POLL]
        mov esi, 1
        mov edx, -1
        call poll@PLT
        jmp 1b
.Lru_oom:
        mov rdi, r14
        call free@PLT
.Lru_oom0:
        add rsp, 32
        LEAVE_NORET
        jmp xalloc_oom
ENDF read_fd_until

# send_all(fd, buf, len) -> eax: write_all's, on a socket, with
# MSG_NOSIGNAL: a node that closed it is EPIPE, not a SIGPIPE - that the
# library had the process ignore, for a program it is in, whatever that
# program wanted of the signal (the command line ignores it itself)
FUNC send_all
        ENTER
        mov ebx, edi
        mov r12, rsi
        mov r13, rdx
1:      test r13, r13
        jz 2f
        mov edi, ebx
        mov rsi, r12
        mov rdx, r13
        mov ecx, 0x4000                 # MSG_NOSIGNAL
        call send@PLT
        test rax, rax
        jle 3f
        add r12, rax
        sub r13, rax
        jmp 1b
2:      xor eax, eax
        LEAVE
3:      js 4f
        mov eax, -1
        LEAVE
4:      call __errno_location@PLT
        cmp dword ptr [rax], 4          # EINTR: again
        je 1b
        mov eax, -1
        LEAVE
ENDF send_all

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
