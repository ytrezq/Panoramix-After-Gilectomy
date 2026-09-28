# Logging, in the format of coloredlogs' defaults:
#   2026-09-27 21:17:30,527 host module[pid] LEVEL message
# with colors when stderr is a terminal (or forced).

.include "defs.inc"

        .section .data
        .align 8
        .globl log_level, log_color
        .hidden log_level, log_color
log_level:      .quad LOG_INFO
log_color:      .quad -1        # -1: decide from isatty(2)

        .section .bss
        .align 8
log_hostname:   .space 72
log_pid:        .quad 0
log_lock:       .quad 0
log_initialized: .quad 0

        .section .rodata
.Lc_green:      .asciz "\033[32m"
.Lc_magenta:    .asciz "\033[35m"
.Lc_blue:       .asciz "\033[34m"
.Lc_yellow:     .asciz "\033[33m"
.Lc_red:        .asciz "\033[31m"
.Lc_bold:       .asciz "\033[1m"
.Lc_reset:      .asciz "\033[0m"
.Ltimefmt:      .asciz "%Y-%m-%d %H:%M:%S"
.Ls_debug:      .asciz "DEBUG"
.Ls_info:       .asciz "INFO"
.Ls_warning:    .asciz "WARNING"
.Ls_error:      .asciz "ERROR"
.Lenv_log:      .asciz "PANORAMIX_LOG"
.Ls_warn_lc:    .asciz "warn"
.Ls_critical:   .asciz "critical"
.Ls_fatal:      .asciz "fatal"

        .text

# log_init(): hostname, pid, color detection, and the level from
# PANORAMIX_LOG=debug|info|warning|error (once: a level set later by
# pan_set_log_level stays)
FUNC log_init
        ENTER
        cmp qword ptr [rip + log_initialized], 0
        jne 2f
        mov qword ptr [rip + log_initialized], 1
        lea rdi, [rip + log_hostname]
        mov esi, 64
        call gethostname@PLT
        call getpid@PLT
        mov [rip + log_pid], rax
        cmp qword ptr [rip + log_color], -1
        jne 1f
        mov edi, 2
        call isatty@PLT
        movsxd rax, eax
        mov [rip + log_color], rax
1:      lea rdi, [rip + .Lenv_log]
        call getenv@PLT
        test rax, rax
        jz 3f
        mov rdi, rax
        call log_level_from_name
        test rax, rax
        js 3f
        mov [rip + log_level], rax
3:      call simd_log                   # (chosen before the level was known)
2:      LEAVE
ENDF log_init

# log_level_from_name(cstr) -> rax: the level of a name (any case), or -1
FUNC log_level_from_name
        ENTER
        mov rbx, rdi
        lea r12, [rip + log_level_names]
1:      mov rsi, [r12]
        test rsi, rsi
        jz 2f
        mov rdi, rbx
        call strcasecmp@PLT
        test eax, eax
        jz 3f
        add r12, 16
        jmp 1b
2:      mov rax, -1
        LEAVE
3:      mov rax, [r12 + 8]
        LEAVE
ENDF log_level_from_name

        .section .data.rel.ro
        .align 8
log_level_names:                        # (name, level), as python's logging
        .quad .Ls_debug, LOG_DEBUG
        .quad .Ls_info, LOG_INFO
        .quad .Ls_warning, LOG_WARNING
        .quad .Ls_warn_lc, LOG_WARNING
        .quad .Ls_error, LOG_ERROR
        .quad .Ls_critical, 50
        .quad .Ls_fatal, 50
        .quad 0, 0
        .text

# log_enabled(level) -> eax
FUNC log_enabled
        xor eax, eax
        cmp rdi, [rip + log_level]
        setge al
        ret
ENDF log_enabled

# sb_color(sb, cstr): append an escape sequence if colors are on
FUNC sb_color
        cmp qword ptr [rip + log_color], 0
        jle 1f
        jmp sb_append_c
1:      ret
ENDF sb_color

# log_msg(level, name_cstr, msg_cstr): one line on stderr
FUNC log_msg
        ENTER
        sub rsp, 96
        cmp rdi, [rip + log_level]
        jl .Llog_skip
        mov r12, rdi                    # level
        mov r13, rsi                    # name
        mov r14, rdx                    # message
        call sb_new
        mov rbx, rax
        # timestamp
        mov edi, 0                      # CLOCK_REALTIME
        lea rsi, [rsp]                  # struct timespec (16 bytes)
        call clock_gettime@PLT
        lea rdi, [rsp]
        lea rsi, [rsp + 16]             # struct tm (56 bytes)
        call localtime_r@PLT
        mov rdi, rbx
        lea rsi, [rip + .Lc_green]
        call sb_color
        lea rdi, [rsp + 72]             # 24-byte buffer
        mov esi, 24
        lea rdx, [rip + .Ltimefmt]
        lea rcx, [rsp + 16]
        call strftime@PLT
        mov rdi, rbx
        lea rsi, [rsp + 72]
        call sb_append_c
        mov rdi, rbx
        mov esi, ','
        call sb_append_char
        mov rax, [rsp + 8]              # tv_nsec
        xor edx, edx
        mov ecx, 1000000
        div rcx                         # rax = milliseconds
        lea rdi, [rsp + 72]
        mov byte ptr [rdi + 3], 0
        mov ecx, 10
        xor edx, edx
        div ecx
        add dl, '0'
        mov [rdi + 2], dl
        xor edx, edx
        div ecx
        add dl, '0'
        mov [rdi + 1], dl
        add al, '0'
        mov [rdi], al
        mov rsi, rdi
        mov rdi, rbx
        call sb_append_c
        mov rdi, rbx
        lea rsi, [rip + .Lc_reset]
        call sb_color
        # hostname
        mov rdi, rbx
        mov esi, ' '
        call sb_append_char
        mov rdi, rbx
        lea rsi, [rip + .Lc_magenta]
        call sb_color
        mov rdi, rbx
        lea rsi, [rip + log_hostname]
        call sb_append_c
        mov rdi, rbx
        lea rsi, [rip + .Lc_reset]
        call sb_color
        # name[pid]
        mov rdi, rbx
        mov esi, ' '
        call sb_append_char
        mov rdi, rbx
        lea rsi, [rip + .Lc_blue]
        call sb_color
        mov rdi, rbx
        mov rsi, r13
        call sb_append_c
        mov rdi, rbx
        mov esi, '['
        call sb_append_char
        mov rdi, rbx
        mov rsi, [rip + log_pid]
        call sb_append_u64
        mov rdi, rbx
        mov esi, ']'
        call sb_append_char
        mov rdi, rbx
        lea rsi, [rip + .Lc_reset]
        call sb_color
        # level
        mov rdi, rbx
        mov esi, ' '
        call sb_append_char
        mov rdi, rbx
        lea rsi, [rip + .Lc_bold]
        call sb_color
        mov rdi, r12
        call log_level_name
        mov rsi, rax
        mov rdi, rbx
        call sb_append_c
        mov rdi, rbx
        lea rsi, [rip + .Lc_reset]
        call sb_color
        mov rdi, rbx
        mov esi, ' '
        call sb_append_char
        # message, colored by level
        cmp r12, LOG_WARNING
        jl 1f
        lea rsi, [rip + .Lc_yellow]
        cmp r12, LOG_ERROR
        jl 2f
        lea rsi, [rip + .Lc_red]
2:      mov rdi, rbx
        call sb_color
1:      cmp r12, LOG_DEBUG
        jne 3f
        mov rdi, rbx
        lea rsi, [rip + .Lc_green]
        call sb_color
3:      mov rdi, rbx
        mov rsi, r14
        call sb_append_c
        mov rdi, rbx
        lea rsi, [rip + .Lc_reset]
        call sb_color
        mov rdi, rbx
        mov esi, '\n'
        call sb_append_char
        # write it out under a lock so that lines from threads don't mix
        call log_lock_acquire
        mov edi, 2
        mov rsi, [rbx + SB_BUF]
        mov rdx, [rbx + SB_LEN]
        call write@PLT
        call log_lock_release
        mov rdi, rbx
        call sb_free
.Llog_skip:
        add rsp, 96
        LEAVE
ENDF log_msg

FUNC log_level_name
        lea rax, [rip + .Ls_debug]
        cmp rdi, LOG_INFO
        jl 1f
        lea rax, [rip + .Ls_info]
        cmp rdi, LOG_WARNING
        jl 1f
        lea rax, [rip + .Ls_warning]
        cmp rdi, LOG_ERROR
        jl 1f
        lea rax, [rip + .Ls_error]
1:      ret
ENDF log_level_name

FUNC log_lock_acquire
1:      mov eax, 1
        xchg eax, dword ptr [rip + log_lock]
        test eax, eax
        jz 2f
        pause
        jmp 1b
2:      ret
ENDF log_lock_acquire

FUNC log_lock_release
        mov dword ptr [rip + log_lock], 0
        ret
ENDF log_lock_release

# sb_free(sb): release a builder and its buffer
FUNC sb_free
        ENTER
        mov rbx, rdi
        mov rdi, [rbx + SB_BUF]
        call free@PLT
        mov rdi, rbx
        call free@PLT
        LEAVE
ENDF sb_free

# sb_format(sb, fmt, args): a tiny formatter. `args` points to an array
# of 64-bit arguments consumed in order by:
#   %s  C string        %d  signed decimal      %u  unsigned decimal
#   %x  0x hex          %i  integer value       %S  string node
#   %v  any value (see value_print)             %%  a percent sign
FUNC sb_format
        ENTER
        mov rbx, rdi                    # sb
        mov r12, rsi                    # fmt
        mov r13, rdx                    # args
1:      movzx eax, byte ptr [r12]
        test al, al
        jz .Lfmt_done
        cmp al, '%'
        je 2f
        # a run of ordinary characters
        mov r14, r12
3:      inc r12
        movzx eax, byte ptr [r12]
        test al, al
        jz 4f
        cmp al, '%'
        jne 3b
4:      mov rdi, rbx
        mov rsi, r14
        mov rdx, r12
        sub rdx, r14
        call sb_append
        jmp 1b
2:      movzx eax, byte ptr [r12 + 1]
        add r12, 2
        mov rsi, [r13]
        mov rdi, rbx
        cmp al, 's'
        jne 5f
        add r13, 8
        call sb_append_c
        jmp 1b
5:      cmp al, 'd'
        jne 6f
        add r13, 8
        call sb_append_i64
        jmp 1b
6:      cmp al, 'u'
        jne 7f
        add r13, 8
        call sb_append_u64
        jmp 1b
7:      cmp al, 'x'
        jne 8f
        add r13, 8
        call sb_append_hex
        jmp 1b
8:      cmp al, 'i'
        jne 9f
        add r13, 8
        mov edx, 10
        call sb_append_int
        jmp 1b
9:      cmp al, 'S'
        jne 10f
        add r13, 8
        call sb_append_str
        jmp 1b
10:     cmp al, 'v'
        jne 11f
        add r13, 8
        call value_print
        jmp 1b
11:     cmp al, '%'
        jne 12f
        mov esi, '%'
        call sb_append_char
        jmp 1b
12:     test al, al
        jz .Lfmt_done
        mov esi, '?'
        call sb_append_char
        jmp 1b
.Lfmt_done:
        LEAVE
ENDF sb_format

# log_fmt(level, name, fmt, a1, a2, a3): formatted logging
FUNC log_fmt
        ENTER
        sub rsp, 32
        cmp rdi, [rip + log_level]
        jl 1f
        mov r12, rdi
        mov r13, rsi
        mov r14, rdx
        mov [rsp], rcx
        mov [rsp + 8], r8
        mov [rsp + 16], r9
        call sb_new
        mov rbx, rax
        mov rdi, rbx
        mov rsi, r14
        mov rdx, rsp
        call sb_format
        mov rdi, r12
        mov rsi, r13
        mov rdx, [rbx + SB_BUF]
        call log_msg
        mov rdi, rbx
        call sb_free
1:      add rsp, 32
        LEAVE
ENDF log_fmt

        .section .note.GNU-stack,"",@progbits
