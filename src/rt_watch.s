# The watchdog: python's time limit of a function (3 minutes, a SIGALRM
# that interrupts it wherever it is) for the port's workers.
#
# The steps check their own limits between their rounds (the VM's loop,
# simplify_trace's rounds), as python's do; but a single pass can take
# longer than all of them (an expression that doubles at every variable
# inlined), and python's alarm cuts it: here, a thread wakes every 50 ms
# and, for a context past its deadline, sets CTX_TIMED_OUT and makes
# CTX_STACK_LOW unreachable - the next STACK_CHECK of any recursion,
# which costs nothing more than it did, goes to stack_overflow, which
# throws E_TIMEOUT instead of E_RECURSION (and puts the stack's limit
# back first). The handlers that stand for python's `except Exception`
# let E_TIMEOUT through, as python's TimeoutInterrupt is a
# BaseException (err_rethrow_timeout).

.include "defs.inc"

        .set WD_MAX, 1024               # the contexts watched at once
        .set WD_PERIOD_NS, 50000000

        .section .bss
        .align 64
wd_mutex:       .zero 64                # a pthread_mutex_t (40 bytes)
wd_ctxs:        .zero WD_MAX * 8
wd_started:     .quad 0
wd_thread:      .quad 0
wd_atfork:      .quad 0

        .section .rodata
.Ls_timed_out:  .asciz "the function took more than 3 minutes"
        .text

# watch_start(ctx, deadline_ns): ctx is watched until watch_stop; the
# first call starts the thread
FUNC watch_start
        ENTER
        mov rbx, rdi
        mov r12, rsi
        lea rdi, [rip + wd_mutex]
        call pthread_mutex_lock@PLT
        mov [rbx + CTX_DEADLINE], r12
        mov qword ptr [rbx + CTX_TIMED_OUT], 0
        xor ecx, ecx
1:      cmp ecx, WD_MAX
        jae 3f                          # (all taken: not watched)
        lea rax, [rip + wd_ctxs]
        cmp qword ptr [rax + rcx*8], 0
        je 2f
        inc ecx
        jmp 1b
2:      mov [rax + rcx*8], rbx
3:      cmp qword ptr [rip + wd_started], 0
        jne 4f
        mov qword ptr [rip + wd_started], 1
        cmp qword ptr [rip + wd_atfork], 0
        jne 5f
        mov qword ptr [rip + wd_atfork], 1
        xor edi, edi
        xor esi, esi
        lea rdx, [rip + watch_atfork_child]
        call pthread_atfork@PLT
5:
        sub rsp, 64                     # a pthread_attr_t
        mov rdi, rsp
        call pthread_attr_init@PLT
        mov rdi, rsp
        mov esi, 1                      # PTHREAD_CREATE_DETACHED
        call pthread_attr_setdetachstate@PLT
        lea rdi, [rip + wd_thread]
        mov rsi, rsp
        lea rdx, [rip + watch_loop]
        xor ecx, ecx
        call pthread_create@PLT
        mov rdi, rsp
        call pthread_attr_destroy@PLT
        add rsp, 64
4:      lea rdi, [rip + wd_mutex]
        call pthread_mutex_unlock@PLT
        LEAVE
ENDF watch_start

# watch_stop(ctx): no longer watched (its stack's limit as it was)
FUNC watch_stop
        ENTER
        mov rbx, rdi
        lea rdi, [rip + wd_mutex]
        call pthread_mutex_lock@PLT
        mov qword ptr [rbx + CTX_DEADLINE], 0
        call watch_disarm_locked
        xor ecx, ecx
        lea rax, [rip + wd_ctxs]
1:      cmp ecx, WD_MAX
        jae 3f
        cmp [rax + rcx*8], rbx
        jne 2f
        mov qword ptr [rax + rcx*8], 0
2:      inc ecx
        jmp 1b
3:      lea rdi, [rip + wd_mutex]
        call pthread_mutex_unlock@PLT
        LEAVE
ENDF watch_stop

# watch_disarm_locked(rbx: ctx): the stack's limit back, if the watchdog
# had taken it away (the lock held)
FUNC watch_disarm_locked
        cmp qword ptr [rbx + CTX_TIMED_OUT], 0
        je 1f
        mov rax, [rbx + CTX_STACK_LOW_REAL]
        mov [rbx + CTX_STACK_LOW], rax
        mov qword ptr [rbx + CTX_TIMED_OUT], 0
1:      ret
ENDF watch_disarm_locked

# watch_loop(arg): the thread
FUNC watch_loop
        push r15
        ENTER
        sub rsp, 24                     # a timespec
1:      mov qword ptr [rsp], 0
        mov qword ptr [rsp + 8], WD_PERIOD_NS
        mov rdi, rsp
        xor esi, esi
        call nanosleep@PLT
        call monotonic_ns
        mov r12, rax                    # now
        lea rdi, [rip + wd_mutex]
        call pthread_mutex_lock@PLT
        xor r13d, r13d
2:      cmp r13d, WD_MAX
        jae 4f
        lea rax, [rip + wd_ctxs]
        mov rbx, [rax + r13*8]
        test rbx, rbx
        jz 3f
        mov rax, [rbx + CTX_DEADLINE]
        test rax, rax
        jz 3f
        cmp r12, rax
        jbe 3f
        cmp qword ptr [rbx + CTX_TIMED_OUT], 0
        jne 3f
        # past its deadline: the next STACK_CHECK throws
        mov rax, [rbx + CTX_STACK_LOW]
        mov [rbx + CTX_STACK_LOW_REAL], rax
        mov qword ptr [rbx + CTX_TIMED_OUT], 1
        mov qword ptr [rbx + CTX_STACK_LOW], -1
3:      inc r13d
        jmp 2b
4:      lea rdi, [rip + wd_mutex]
        call pthread_mutex_unlock@PLT
        jmp 1b
ENDF watch_loop

# watch_expired(): called by stack_overflow for r15 - E_TIMEOUT (never
# returns) if the watchdog took the stack's limit away, else returns
FUNC watch_expired
        cmp qword ptr [r15 + CTX_TIMED_OUT], 0
        jne 1f
        ret
1:      push rbx
        mov rbx, r15
        lea rdi, [rip + wd_mutex]
        call pthread_mutex_lock@PLT
        mov qword ptr [rbx + CTX_DEADLINE], 0   # (once: the handlers run on)
        call watch_disarm_locked
        lea rdi, [rip + wd_mutex]
        call pthread_mutex_unlock@PLT
        pop rbx
        mov edi, E_TIMEOUT
        lea rsi, [rip + .Ls_timed_out]
        jmp err_throw
ENDF watch_expired

# watch_atfork_child(): in the child of a fork, the thread is gone (and
# the lock may have been held by another thread): all anew, started again
# by the next watch_start
FUNC watch_atfork_child
        push rdi
        lea rdi, [rip + wd_mutex]
        xor esi, esi
        mov edx, 64 + WD_MAX * 8
        call memset@PLT                 # (the mutex, then the table)
        mov qword ptr [rip + wd_started], 0
        pop rdi
        ret
ENDF watch_atfork_child

# err_rethrow_timeout(code): for the handlers of python's `except
# Exception`: a timeout goes on to the next handler
FUNC err_rethrow_timeout
        cmp edi, E_TIMEOUT
        je 1f
        ret
1:      mov rsi, [r15 + CTX_ERR_MSG]
        jmp err_throw
ENDF err_rethrow_timeout

        .section .note.GNU-stack,"",@progbits
