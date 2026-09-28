# Memory: thread contexts, arenas, GMP glue.
#
# All the nodes a thread creates while decompiling a function live in its
# arena (a list of mmap'ed chunks, bump-allocated) and are freed at once
# with arena_reset. GMP's allocations are routed there too, so the limbs
# of the big ints die with the nodes that own them.

.include "defs.inc"

        .section .bss
        .align 8
ctx_key:        .quad 0          # pthread_key_t
rt_initialized: .quad 0
        .globl global_ctx
        .hidden global_ctx
global_ctx:     .quad 0          # a context for process-wide constants (never reset)

        .text

# rt_init(): process-wide initialization, idempotent.
FUNC rt_init
        ENTER
        cmp qword ptr [rip + rt_initialized], 0
        jne 9f
        mov qword ptr [rip + rt_initialized], 1
        lea rdi, [rip + ctx_key]
        xor esi, esi
        call pthread_key_create@PLT
        lea rdi, [rip + gmp_alloc]
        lea rsi, [rip + gmp_realloc]
        lea rdx, [rip + gmp_free]
        call __gmp_set_memory_functions@PLT
        call str_init
        call opcodes_init
        # the global context: bound while the constants get made, and left
        # bound for the calling thread if it had nothing (the CLI)
        call ctx_current
        mov rbx, rax
        call ctx_new
        mov [rip + global_ctx], rax
        push r15
        push r15
        mov r15, rax
        mov rdi, rax
        call ctx_bind
        call arith_init
        call arith_module_init
        call vm_module_init
        call matcher_init
        call prettify_init
        call patterns_init
        pop r15
        pop r15
        test rbx, rbx
        jz 9f
        mov rdi, rbx
        call ctx_bind
9:      LEAVE
ENDF rt_init

# ctx_new() -> rax: a fresh thread context, not yet bound (see ctx_bind).
FUNC ctx_new
        ENTER
        mov edi, CTX_SIZE
        call malloc@PLT
        mov rbx, rax
        mov rdi, rbx
        xor esi, esi
        mov edx, CTX_SIZE
        call memset@PLT
        mov qword ptr [rbx + CTX_ARENA_CHUNKSZ], ARENA_CHUNK_DEFAULT
        # first chunk
        mov rdi, rbx
        mov esi, ARENA_CHUNK_DEFAULT
        call arena_new_chunk
        # hash-cons table: 4096 entries to start with
        mov edi, 4096
        mov esi, 8
        call calloc@PLT
        mov [rbx + CTX_HC_TABLE], rax
        mov qword ptr [rbx + CTX_HC_CAP], 4096
        # scratch mpz
        lea rdi, [rbx + CTX_TMPZ]
        push r15
        push r15
        mov r15, rbx
        mov rdi, rbx
        call ctx_bind
        lea rdi, [r15 + CTX_MPZ_A]
        call __gmpz_init@PLT
        lea rdi, [r15 + CTX_MPZ_B]
        call __gmpz_init@PLT
        lea rdi, [r15 + CTX_MPZ_R]
        call __gmpz_init@PLT
        lea rdi, [r15 + CTX_MPZ_T]
        call __gmpz_init@PLT
        pop r15
        pop r15
        mov rax, rbx
        LEAVE
ENDF ctx_new

# ctx_bind(ctx): make ctx the current thread's context for the code that
# can't rely on r15 (GMP callbacks).
FUNC ctx_bind
        ENTER
        mov rsi, rdi
        mov rdi, [rip + ctx_key]
        call pthread_setspecific@PLT
        LEAVE
ENDF ctx_bind

# ctx_current() -> rax: the bound context (pthread key)
FUNC ctx_current
        ENTER
        mov rdi, [rip + ctx_key]
        call pthread_getspecific@PLT
        LEAVE
ENDF ctx_current

# ctx_free(ctx): release everything
FUNC ctx_free
        ENTER
        mov rbx, rdi
        mov r12, [rbx + CTX_ARENA_CHUNKS]
1:      test r12, r12
        jz 2f
        mov r13, [r12 + CHUNK_NEXT]
        mov rdi, r12
        mov rsi, [r12 + CHUNK_SIZE]
        call munmap@PLT
        mov r12, r13
        jmp 1b
2:      mov rdi, [rbx + CTX_HC_TABLE]
        call free@PLT
        mov rdi, rbx
        call free@PLT
        LEAVE
ENDF ctx_free

# arena_new_chunk(ctx, size): map a chunk of at least `size` payload bytes
# and make it the current one.
FUNC arena_new_chunk
        ENTER
        mov rbx, rdi
        mov r12, rsi
        add r12, CHUNK_DATA + 15
        and r12, -16
        mov rax, [rbx + CTX_ARENA_CHUNKSZ]
        cmp r12, rax
        cmovb r12, rax
        xor edi, edi
        mov rsi, r12
        mov edx, 3                      # PROT_READ | PROT_WRITE
        mov ecx, 0x22                   # MAP_PRIVATE | MAP_ANONYMOUS
        mov r8, -1
        xor r9d, r9d
        call mmap@PLT
        cmp rax, -1
        je .Lchunk_fail
        mov rcx, [rbx + CTX_ARENA_CHUNKS]
        mov [rax + CHUNK_NEXT], rcx
        mov [rax + CHUNK_SIZE], r12
        mov [rbx + CTX_ARENA_CHUNKS], rax
        lea rcx, [rax + CHUNK_DATA]
        mov [rbx + CTX_ARENA_CUR], rcx
        add rax, r12
        mov [rbx + CTX_ARENA_END], rax
        add [rbx + CTX_ARENA_TOTAL], r12
        LEAVE
.Lchunk_fail:
        lea rdi, [rip + .Lmsg_oom]
        call rt_fatal
ENDF arena_new_chunk

        .section .rodata
.Lmsg_oom: .asciz "panoramix-asm: out of memory (mmap failed)"
        .text

# arena_alloc_ctx(ctx, size) -> rax: 16-byte aligned, zeroed memory
FUNC arena_alloc_ctx
        ENTER
        mov rbx, rdi
        add rsi, 15
        and rsi, -16
        mov r12, rsi
        mov rax, [rbx + CTX_ARENA_CUR]
        lea rcx, [rax + r12]
        cmp rcx, [rbx + CTX_ARENA_END]
        ja 1f
        mov [rbx + CTX_ARENA_CUR], rcx
        LEAVE
1:      mov rdi, rbx
        mov rsi, r12
        call arena_new_chunk
        mov rax, [rbx + CTX_ARENA_CUR]
        lea rcx, [rax + r12]
        mov [rbx + CTX_ARENA_CUR], rcx
        LEAVE
ENDF arena_alloc_ctx

# arena_alloc(size) -> rax, on the r15 context. Memory is zero (fresh mmap
# pages are, and the arena is never reused without an arena_reset which
# doesn't zero - so callers that reuse must not rely on it after a reset;
# node constructors initialize every field anyway).
FUNC arena_alloc
        mov rsi, rdi
        mov rdi, r15
        jmp arena_alloc_ctx
ENDF arena_alloc

# arena_reset(): drop every chunk but the first, rewind. Also empties the
# hash-cons table (its nodes are gone).
FUNC arena_reset
        ENTER
        mov r12, [r15 + CTX_ARENA_CHUNKS]
1:      mov r13, [r12 + CHUNK_NEXT]
        test r13, r13
        jz 2f
        mov rdi, r12
        mov rsi, [r12 + CHUNK_SIZE]
        sub [r15 + CTX_ARENA_TOTAL], rsi
        call munmap@PLT
        mov r12, r13
        jmp 1b
2:      mov [r15 + CTX_ARENA_CHUNKS], r12
        lea rax, [r12 + CHUNK_DATA]
        mov [r15 + CTX_ARENA_CUR], rax
        mov rax, [r12 + CHUNK_SIZE]
        add rax, r12
        mov [r15 + CTX_ARENA_END], rax
        mov rdi, [r15 + CTX_HC_TABLE]
        xor esi, esi
        mov rdx, [r15 + CTX_HC_CAP]
        shl rdx, 3
        call memset@PLT
        mov qword ptr [r15 + CTX_HC_COUNT], 0
        mov qword ptr [r15 + CTX_NODE_COUNT], 0
        # the memo tables were in the arena
        lea rdi, [r15 + CTX_MEMO]
        xor esi, esi
        mov edx, MEMO_COUNT * 8
        call memset@PLT
        LEAVE
ENDF arena_reset

# --- GMP memory callbacks (C ABI, context from the pthread key) ---

FUNC gmp_alloc
        ENTER
        mov rbx, rdi
        call ctx_current
        mov rdi, rax
        mov rsi, rbx
        call arena_alloc_ctx
        LEAVE
ENDF gmp_alloc

# gmp_realloc(ptr, old_size, new_size)
FUNC gmp_realloc
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        call ctx_current
        mov rdi, rax
        mov rsi, r13
        call arena_alloc_ctx
        mov r14, rax
        mov rdi, rax
        mov rsi, rbx
        mov rdx, r12
        cmp r12, r13
        cmova rdx, r13
        call memcpy@PLT
        mov rax, r14
        LEAVE
ENDF gmp_realloc

FUNC gmp_free
        ret
ENDF gmp_free

# rt_fatal(msg): print and abort
FUNC rt_fatal
        ENTER
        mov rbx, rdi
        mov rdi, [rip + stderr@GOTPCREL]
        mov rdi, [rdi]
        lea rsi, [rip + .Lfatal_fmt]
        mov rdx, rbx
        xor eax, eax
        call fprintf@PLT
        call abort@PLT
ENDF rt_fatal

        .section .rodata
.Lfatal_fmt: .asciz "%s\n"
        .section .note.GNU-stack,"",@progbits
