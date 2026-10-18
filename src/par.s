# par_for: a loop whose iterations run on threads, for the parts of the
# postprocessing that are the same work for every function (printing
# them): each iteration takes a context of its own, reads the main
# context's values (nobody writes them meanwhile: the main thread waits)
# and leaves its results where the main thread takes them after.

.include "defs.inc"

        .set PF_FN, 0                   # the body: fn(i, arg), any context
        .set PF_ARG, 8
        .set PF_N, 16
        .set PF_NEXT, 24                # the next iteration (atomic)
        .set PF_SIZEOF, 32
        .set PAR_STACK, 64 << 20        # (the printer recurses as deep as the traces nest)

        .text

# par_for(n, threads, fn, arg): fn(i, arg) for i in 0..n-1, on
# min(threads, n) threads (this one when threads <= 1 or none could be
# started). fn keeps r15 (the thread's context) as it found it, and
# handles its errors itself. Returns when all are done.
FUNC par_for
        push r15
        ENTER
        sub rsp, 88
        .set PR_ST, 0                   # the shared state (PF_SIZEOF bytes)
        .set PR_TIDS, 32
        .set PR_NT, 40
        .set PR_T, 48
        .set PR_ATTR, 56                # (a pthread_attr_t: 56 bytes... in the arena)
        mov [rsp + PF_FN], rdx
        mov [rsp + PF_ARG], rcx
        mov [rsp + PF_N], rdi
        mov qword ptr [rsp + PF_NEXT], 0
        mov qword ptr [rsp + PR_NT], 0
        cmp rsi, rdi
        cmova rsi, rdi
        mov [rsp + PR_T], rsi
        cmp rsi, 1
        jbe .Lpf_here
        lea rdi, [rsi*8]
        call arena_alloc
        mov [rsp + PR_TIDS], rax
        mov edi, 64
        call arena_alloc
        mov [rsp + PR_ATTR], rax
        mov rdi, rax
        call pthread_attr_init@PLT
        mov rdi, [rsp + PR_ATTR]
        mov esi, PAR_STACK
        call pthread_attr_setstacksize@PLT
1:      mov rax, [rsp + PR_NT]
        cmp rax, [rsp + PR_T]
        jae 2f
        mov rdi, [rsp + PR_TIDS]
        lea rdi, [rdi + rax*8]
        mov rsi, [rsp + PR_ATTR]
        lea rdx, [rip + par_worker]
        mov rcx, rsp                    # (the shared state, at PR_ST)
        call thread_create
        test eax, eax
        jnz 2f
        inc qword ptr [rsp + PR_NT]
        jmp 1b
2:      mov rdi, [rsp + PR_ATTR]
        call pthread_attr_destroy@PLT
        cmp qword ptr [rsp + PR_NT], 0
        je .Lpf_here
        xor ebx, ebx
3:      cmp rbx, [rsp + PR_NT]
        jae .Lpf_done
        mov rdi, [rsp + PR_TIDS]
        mov rdi, [rdi + rbx*8]
        xor esi, esi
        call pthread_join@PLT
        inc rbx
        jmp 3b
.Lpf_here:
        mov rdi, rsp
        call par_worker
        mov rdi, r15
        call ctx_bind                   # (the body's contexts were bound to this thread)
.Lpf_done:
        add rsp, 88
        LEAVE_NORET
        pop r15
        ret
ENDF par_for

# par_worker(state) -> 0: the iterations, until there are none left
FUNC par_worker
        push r15
        ENTER
        sub rsp, 8
        mov rbx, rdi
1:      mov eax, 1
        lock xadd [rbx + PF_NEXT], rax
        cmp rax, [rbx + PF_N]
        jae 2f
        mov rdi, rax
        mov rsi, [rbx + PF_ARG]
        call [rbx + PF_FN]
        jmp 1b
2:      xor eax, eax
        add rsp, 8
        LEAVE_NORET
        pop r15
        ret
ENDF par_worker

# thread_create(tid, attr, fn, arg) -> eax: pthread_create's, the thread
# started with the asynchronous signals blocked. Every thread the library
# starts is made so (the decompilation's, the workers, the folds', the
# printing's, the watchdog): they inherited the mask of whoever called the
# library, so a signal of the program's (SIGINT, a SIGALRM of its own...)
# could be delivered to one of them - its handler then ran on a thread the
# program knows nothing of, in the middle of our code, and cut our system
# calls short with EINTR. Now such a signal goes to one of the program's
# threads. The synchronous ones (a fault: SIGSEGV, SIGBUS, SIGFPE, SIGILL,
# SIGTRAP, SIGSYS, and SIGABRT) stay as they were: blocked, the kernel
# would kill the process without its handler (faulthandler's traceback).
# The creator's mask is back on return (what came for it meanwhile is
# delivered then).
FUNC thread_create
        ENTER
        sub rsp, 272                    # two sigset_t of 128 bytes, and 16
        .set TC_SET, 0
        .set TC_OLD, 128
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov r14, rcx
        lea rdi, [rsp + TC_SET]
        call sigfillset@PLT
        .irp sig, 4, 5, 6, 7, 8, 11, 31
        lea rdi, [rsp + TC_SET]
        mov esi, \sig
        call sigdelset@PLT
        .endr
        xor edi, edi                    # SIG_BLOCK
        lea rsi, [rsp + TC_SET]
        lea rdx, [rsp + TC_OLD]
        call pthread_sigmask@PLT
        mov rdi, rbx
        mov rsi, r12
        mov rdx, r13
        mov rcx, r14
        call pthread_create@PLT         # (the real one: this is its wrapper)
        mov ebx, eax
        mov edi, 2                      # SIG_SETMASK
        lea rsi, [rsp + TC_OLD]
        xor edx, edx
        call pthread_sigmask@PLT
        mov eax, ebx
        add rsp, 272
        LEAVE
ENDF thread_create

        .section .note.GNU-stack,"",@progbits
