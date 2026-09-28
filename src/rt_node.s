# Nodes: tagged values, tuples/lists (hash-consed), big ints (GMP).

.include "defs.inc"

        .text

# hash_mix(rdi) -> rax. Murmur3's 64-bit finalizer. Clobbers rcx.
FUNC hash_mix
        mov rax, rdi
        mov rcx, rax
        shr rcx, 33
        xor rax, rcx
        movabs rcx, 0xff51afd7ed558ccd
        imul rax, rcx
        mov rcx, rax
        shr rcx, 33
        xor rax, rcx
        movabs rcx, 0xc4ceb9fe1a85ec53
        imul rax, rcx
        mov rcx, rax
        shr rcx, 33
        xor rax, rcx
        ret
ENDF hash_mix

# value_hash(rdi) -> rax. Clobbers rcx.
FUNC value_hash
        test dil, 1
        jz 1f
        jmp hash_mix
1:      test rdi, rdi
        jz 2f
        mov rax, [rdi + N_HASH]
        ret
2:      movabs rax, 0x9e3779b97f4a7c15
        ret
ENDF value_hash

# hash_seq(kind, count, elems) -> rax: the hash, its top byte the mention
# flags (HF_*) of the elements
FUNC hash_seq
        ENTER
        sub rsp, 16
        mov r12, rsi                    # count
        mov r13, rdx                    # elems
        mov qword ptr [rsp], 0          # the flags
        movabs rax, 0x9e3779b97f4a7c15
        imul rdi, rax
        xor rdi, rsi
        call hash_mix
        mov rbx, rax
        xor r14d, r14d
1:      cmp r14, r12
        jae 2f
        mov rdi, [r13 + r14*8]
        call value_hash
        test byte ptr [r13 + r14*8], 1
        jnz 3f
        cmp qword ptr [r13 + r14*8], 0
        je 3f
        mov rcx, rax                    # a node: its flags
        mov rdx, HF_MASK
        and rcx, rdx
        or [rsp], rcx
3:      mov rdi, rax
        xor rdi, rbx
        movabs rcx, 0x9e3779b97f4a7c15
        add rdi, rcx
        call hash_mix
        mov rbx, rax
        inc r14
        jmp 1b
2:      mov rax, rbx
        mov rcx, HF_MASK
        not rcx
        and rax, rcx
        or rax, [rsp]
        add rsp, 16
        LEAVE
ENDF hash_seq

# values_equal(a, b) -> eax 0/1. Pointer equality, except big ints which
# are compared by value.
FUNC values_equal
        cmp rdi, rsi
        je .Lveq_yes
        test dil, 1
        jnz .Lveq_no
        test sil, 1
        jnz .Lveq_no
        test rdi, rdi
        jz .Lveq_no
        test rsi, rsi
        jz .Lveq_no
        cmp dword ptr [rdi + N_KIND], K_INT
        jne .Lveq_no
        cmp dword ptr [rsi + N_KIND], K_INT
        jne .Lveq_no
        mov rax, [rdi + N_HASH]
        cmp rax, [rsi + N_HASH]
        jne .Lveq_no
        ENTER
        add rdi, N_DATA
        add rsi, N_DATA
        call __gmpz_cmp@PLT
        test eax, eax
        sete al
        movzx eax, al
        LEAVE
.Lveq_yes:
        mov eax, 1
        ret
.Lveq_no:
        xor eax, eax
        ret
ENDF values_equal

# seq_equal(node, kind, count, elems) -> eax: does the tuple/list node hold
# exactly these elements?
FUNC seq_equal
        ENTER
        mov rbx, rdi
        cmp [rbx + N_KIND], esi
        jne .Lseq_no
        cmp [rbx + N_AUX], edx
        jne .Lseq_no
        mov r12, rdx
        mov r13, rcx
        xor r14d, r14d
1:      cmp r14, r12
        jae .Lseq_yes
        mov rdi, [rbx + N_DATA + r14*8]
        mov rsi, [r13 + r14*8]
        call values_equal
        test eax, eax
        jz .Lseq_no
        inc r14
        jmp 1b
.Lseq_yes:
        mov eax, 1
        LEAVE
.Lseq_no:
        xor eax, eax
        LEAVE
ENDF seq_equal

# hc_grow(): double the hash-cons table
FUNC hc_grow
        ENTER
        sub rsp, 16
        mov r12, [r15 + CTX_HC_TABLE]
        mov r13, [r15 + CTX_HC_CAP]
        lea rdi, [r13 * 2]
        mov [r15 + CTX_HC_CAP], rdi
        mov esi, 8
        call calloc@PLT
        mov [r15 + CTX_HC_TABLE], rax
        mov rbx, rax
        xor r14d, r14d
1:      cmp r14, r13
        jae 3f
        mov rdi, [r12 + r14*8]
        test rdi, rdi
        jz 2f
        # reinsert
        mov rax, [rdi + N_HASH]
        mov rcx, [r15 + CTX_HC_CAP]
        dec rcx
        and rax, rcx
4:      cmp qword ptr [rbx + rax*8], 0
        je 5f
        inc rax
        and rax, rcx
        jmp 4b
5:      mov [rbx + rax*8], rdi
2:      inc r14
        jmp 1b
3:      mov rdi, r12
        call free@PLT
        add rsp, 16
        LEAVE
ENDF hc_grow

# mk_seq(kind, count, elems) -> rax: the unique node for this sequence
FUNC mk_seq
        ENTER
        sub rsp, 32
        mov [rsp], rdi                  # kind
        mov [rsp + 8], rsi              # count
        mov [rsp + 16], rdx             # elems
        call hash_seq
        mov [rsp + 24], rax             # hash
        # grow if the table is half full
        mov rax, [r15 + CTX_HC_COUNT]
        shl rax, 1
        cmp rax, [r15 + CTX_HC_CAP]
        jb 1f
        call hc_grow
1:      mov rbx, [r15 + CTX_HC_TABLE]
        mov r13, [r15 + CTX_HC_CAP]
        dec r13                         # mask
        mov r12, [rsp + 24]
        and r12, r13                    # slot
2:      mov rdi, [rbx + r12*8]
        test rdi, rdi
        jz .Lmk_new
        mov rax, [rsp + 24]
        cmp [rdi + N_HASH], rax
        jne 3f
        mov rsi, [rsp]
        mov rdx, [rsp + 8]
        mov rcx, [rsp + 16]
        call seq_equal
        test eax, eax
        jz 3f
        mov rax, [rbx + r12*8]
        add rsp, 32
        LEAVE
3:      inc r12
        and r12, r13
        jmp 2b
.Lmk_new:
        mov rdi, [rsp + 8]
        shl rdi, 3
        add rdi, N_DATA
        call arena_alloc
        mov r14, rax
        mov rcx, [rsp]
        mov [r14 + N_KIND], ecx
        mov rcx, [rsp + 8]
        mov [r14 + N_AUX], ecx
        mov rcx, [rsp + 24]
        mov [r14 + N_HASH], rcx
        lea rdi, [r14 + N_DATA]
        mov rsi, [rsp + 16]
        mov rdx, [rsp + 8]
        shl rdx, 3
        call memcpy@PLT
        mov [rbx + r12*8], r14
        inc qword ptr [r15 + CTX_HC_COUNT]
        inc qword ptr [r15 + CTX_NODE_COUNT]
        mov rax, r14
        add rsp, 32
        LEAVE
ENDF mk_seq

# mk_tuple(count, elems) / mk_list(count, elems)
FUNC mk_tuple
        mov rdx, rsi
        mov rsi, rdi
        mov edi, K_TUPLE
        jmp mk_seq
ENDF mk_tuple

FUNC mk_list
        mov rdx, rsi
        mov rsi, rdi
        mov edi, K_LIST
        jmp mk_seq
ENDF mk_list

# mk1(a) ... mk6(a, b, c, d, e, f): tuples from registers
FUNC mk1
        ENTER
        sub rsp, 16
        mov [rsp], rdi
        mov edi, 1
        mov rsi, rsp
        call mk_tuple
        add rsp, 16
        LEAVE
ENDF mk1

FUNC mk2
        ENTER
        sub rsp, 16
        mov [rsp], rdi
        mov [rsp + 8], rsi
        mov edi, 2
        mov rsi, rsp
        call mk_tuple
        add rsp, 16
        LEAVE
ENDF mk2

FUNC mk3
        ENTER
        sub rsp, 32
        mov [rsp], rdi
        mov [rsp + 8], rsi
        mov [rsp + 16], rdx
        mov edi, 3
        mov rsi, rsp
        call mk_tuple
        add rsp, 32
        LEAVE
ENDF mk3

FUNC mk4
        ENTER
        sub rsp, 32
        mov [rsp], rdi
        mov [rsp + 8], rsi
        mov [rsp + 16], rdx
        mov [rsp + 24], rcx
        mov edi, 4
        mov rsi, rsp
        call mk_tuple
        add rsp, 32
        LEAVE
ENDF mk4

FUNC mk5
        ENTER
        sub rsp, 48
        mov [rsp], rdi
        mov [rsp + 8], rsi
        mov [rsp + 16], rdx
        mov [rsp + 24], rcx
        mov [rsp + 32], r8
        mov edi, 5
        mov rsi, rsp
        call mk_tuple
        add rsp, 48
        LEAVE
ENDF mk5

FUNC mk6
        ENTER
        sub rsp, 48
        mov [rsp], rdi
        mov [rsp + 8], rsi
        mov [rsp + 16], rdx
        mov [rsp + 24], rcx
        mov [rsp + 32], r8
        mov [rsp + 40], r9
        mov edi, 6
        mov rsi, rsp
        call mk_tuple
        add rsp, 48
        LEAVE
ENDF mk6

# --- integers ---

# int_hash_mpz(mpz) -> rax: hash of the value from its limbs
FUNC int_hash_mpz
        ENTER
        mov rbx, rdi
        movsxd r12, dword ptr [rbx + MPZ_SIZE]
        mov rdi, r12
        movabs rax, 0x9e3779b97f4a7c15
        xor rdi, rax
        call hash_mix
        mov r13, rax
        mov r14, r12
        test r14, r14
        jns 1f
        neg r14
1:      mov rbx, [rbx + MPZ_D]
2:      test r14, r14
        jz 3f
        dec r14
        mov rdi, [rbx + r14*8]
        xor rdi, r13
        call hash_mix
        mov r13, rax
        jmp 2b
3:      mov rax, r13
        mov rcx, HF_MASK                # (no mention flags in a number)
        not rcx
        and rax, rcx
        LEAVE
ENDF int_hash_mpz

# mk_int_mpz(mpz) -> rax: a value for this integer (small if it fits)
FUNC mk_int_mpz
        ENTER
        mov rbx, rdi
        call __gmpz_fits_slong_p@PLT
        test eax, eax
        jz 1f
        mov rdi, rbx
        call __gmpz_get_si@PLT
        mov rcx, SMALL_MAX
        cmp rax, rcx
        jg 1f
        mov rcx, SMALL_MIN
        cmp rax, rcx
        jl 1f
        TAG rax
        LEAVE
1:      mov edi, NODE_INT_SIZE
        call arena_alloc
        mov r12, rax
        mov dword ptr [r12 + N_KIND], K_INT
        lea rdi, [r12 + N_DATA]
        mov rsi, rbx
        call __gmpz_init_set@PLT
        lea rdi, [r12 + N_DATA]
        call int_hash_mpz
        mov [r12 + N_HASH], rax
        inc qword ptr [r15 + CTX_NODE_COUNT]
        mov rax, r12
        LEAVE
ENDF mk_int_mpz

# mk_int_i64(x) -> rax
FUNC mk_int_i64
        mov rcx, SMALL_MAX
        cmp rdi, rcx
        jg 1f
        mov rcx, SMALL_MIN
        cmp rdi, rcx
        jl 1f
        lea rax, [rdi + rdi + 1]
        ret
1:      ENTER
        mov rbx, rdi
        lea rdi, [r15 + CTX_TMPZ]
        mov rsi, rbx
        call __gmpz_set_si@PLT
        lea rdi, [r15 + CTX_TMPZ]
        call mk_int_mpz
        LEAVE
ENDF mk_int_i64

# mk_int_u64(x) -> rax
FUNC mk_int_u64
        mov rcx, SMALL_MAX
        cmp rdi, rcx
        ja 1f
        lea rax, [rdi + rdi + 1]
        ret
1:      ENTER
        mov rbx, rdi
        lea rdi, [r15 + CTX_TMPZ]
        mov rsi, rbx
        call __gmpz_set_ui@PLT
        lea rdi, [r15 + CTX_TMPZ]
        call mk_int_mpz
        LEAVE
ENDF mk_int_u64

# mk_int_bytes_be(ptr, len) -> rax: big-endian unsigned integer
FUNC mk_int_bytes_be
        ENTER
        cmp rsi, 8
        ja 1f
        # fits in u64
        xor eax, eax
        xor ecx, ecx
2:      cmp rcx, rsi
        jae 3f
        shl rax, 8
        movzx edx, byte ptr [rdi + rcx]
        or rax, rdx
        inc rcx
        jmp 2b
3:      mov rdi, rax
        call mk_int_u64
        LEAVE
1:      # mpz_import(rop, count=len, order=1, size=1, endian=0, nails=0, op)
        mov r8, rdi                     # op (the bytes)
        sub rsp, 16
        mov [rsp], r8                   # 7th argument, on the stack
        lea rdi, [r15 + CTX_TMPZ]       # rop
        mov edx, 1                      # order: most significant first
        mov ecx, 1                      # size: 1-byte words
        xor r8d, r8d                    # endian
        xor r9d, r9d                    # nails
        call __gmpz_import@PLT
        add rsp, 16
        lea rdi, [r15 + CTX_TMPZ]
        call mk_int_mpz
        LEAVE
ENDF mk_int_bytes_be

# value_set_mpz(mpz_dst, v): mpz_dst := integer value v (small or K_INT)
FUNC value_set_mpz
        test sil, 1
        jz 1f
        UNTAG rsi
        jmp __gmpz_set_si@PLT
1:      add rsi, N_DATA
        jmp __gmpz_set@PLT
ENDF value_set_mpz

# value_mpz(v) -> rax: a read-only mpz_t pointer for the integer value v.
# For small ints it is the context's scratch CTX_TMPZ2 (only one at a time!).
FUNC value_mpz
        test dil, 1
        jz 1f
        ENTER
        mov rsi, rdi
        UNTAG rsi
        lea rdi, [r15 + CTX_TMPZ2]
        call __gmpz_set_si@PLT
        lea rax, [r15 + CTX_TMPZ2]
        LEAVE
1:      lea rax, [rdi + N_DATA]
        ret
ENDF value_mpz

# is_int(v) -> eax: 1 if v is a small int or a K_INT node
FUNC is_int
        test dil, 1
        jnz 1f
        test rdi, rdi
        jz 2f
        cmp dword ptr [rdi + N_KIND], K_INT
        jne 2f
1:      mov eax, 1
        ret
2:      xor eax, eax
        ret
ENDF is_int

# --- specials ---
        .section .data
        .align 16
        .globl sp_none, sp_true, sp_false
        .hidden sp_none, sp_true, sp_false
sp_none:  .long K_SPECIAL, SP_NONE
          .quad 0x0011111111111111     # (the top byte: no mention flags)
sp_true:  .long K_SPECIAL, SP_TRUE
          .quad 0x0022222222222222
sp_false: .long K_SPECIAL, SP_FALSE
          .quad 0x0033333333333333
        .text

# opcode_of(v) -> eax: the opcode id of a tuple/list whose first element is
# an opcode string, else 0
FUNC opcode_of
        test dil, 1
        jnz 1f
        test rdi, rdi
        jz 1f
        cmp dword ptr [rdi + N_KIND], K_TUPLE   # (not lists, like python's opcode())
        jne 1f
        cmp dword ptr [rdi + N_AUX], 0
        je 1f
        mov rax, [rdi + N_DATA]
        test al, 1
        jnz 1f
        test rax, rax
        jz 1f
        cmp dword ptr [rax + N_KIND], K_STR
        jne 1f
        mov eax, [rax + N_AUX]
        and eax, STR_ID_MASK
        ret
1:      xor eax, eax
        ret
ENDF opcode_of

# str_id(strnode) -> eax: the opcode id of a string node
FUNC str_id
        mov eax, [rdi + N_AUX]
        and eax, STR_ID_MASK
        ret
ENDF str_id

# value_import(v) -> rax: the value rebuilt on this context. Tuples and
# lists are consed per thread, so a structure made by another thread (a
# function's trace, the loader's values) is imported before being
# compared by pointer with this thread's - and before that thread's
# arena is freed, which also holds its big integers (copied here).
# Strings are global: kept.
FUNC value_import
        ENTER
        sub rsp, 16
        mov rbx, rdi
        test dil, 1
        jnz 3f
        test rdi, rdi
        jz 3f
        cmp dword ptr [rdi + N_KIND], K_INT
        jne 4f
        lea rdi, [rdi + N_DATA]
        call mk_int_mpz
        add rsp, 16
        LEAVE
4:      call is_seq
        test eax, eax
        jz 3f
        mov edi, [rbx + N_AUX]
        shl rdi, 3
        call arena_alloc
        mov [rsp], rax
        xor r12d, r12d
1:      cmp r12d, [rbx + N_AUX]
        jae 2f
        mov rdi, [rbx + N_DATA + r12*8]
        call value_import
        mov rcx, [rsp]
        mov [rcx + r12*8], rax
        inc r12d
        jmp 1b
2:      mov edi, [rbx + N_KIND]
        mov esi, [rbx + N_AUX]
        mov rdx, [rsp]
        call mk_seq
        add rsp, 16
        LEAVE
3:      mov rax, rbx
        add rsp, 16
        LEAVE
ENDF value_import

        .section .note.GNU-stack,"",@progbits
