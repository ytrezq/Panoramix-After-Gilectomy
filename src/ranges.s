# Ranges (port of algebra.value_range and what it rests on): what an
# expression can be, as the integer it is, for any value of the words it's
# made of. The comparisons (ge_zero, lt_op, le_op, max_op...) are decided
# by them and by nothing else - they used to be decided by trying values
# (add_ge_zero's variants), which knew the sign only for these values.
#
# A range is two integer values: lo in rax, hi in rdx. `top` is 0 for
# WORD_TOP (2^256 - 1) and 1 for MEMORY_TOP (2^64 - 1, see memory_range).
# `bounds` is 0 or an emap {expression: (lo, hi)}, what's known of some
# of the words: python's bounds dict, and as there nothing is remembered
# then.
#
# What set_variables sets - python's module globals _VARIABLES, _CYCLIC,
# _SMALL - is the context's: CTX_VR_ARGS holds what it was given, as one
# value a compaction imports (ctx_compact), and the tables are made from
# it (vr_rebuild).

.include "defs.inc"

        .set VR_MASKS_NONE, 0           # (python's masks=False)
        .set VR_MASKS_ALL, 1            # (True: floor32(x)... as x minus a number)
        .set VR_MASKS_EXACT, 2          # ("exact": 2 * x..., nothing subtracted)

        .section .bss
        .align 8
        .globl vr_word_top_v, vr_memory_top_v
        .hidden vr_word_top_v, vr_memory_top_v
vr_word_top_v:     .quad 0              # 2^256 - 1 (values of the global context)
vr_memory_top_v:   .quad 0              # 2^64 - 1
vr_neg_word_top_v: .quad 0              # -(2^256 - 1)
        .text

# ranges_init(): the constants, on the global context (rt_init)
FUNC ranges_init
        ENTER
        lea rdi, [r15 + CTX_MPZ_R]
        lea rsi, [rip + mpz_max256]
        call __gmpz_set@PLT
        call arith_result
        mov [rip + vr_word_top_v], rax
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, -1
        call __gmpz_set_ui@PLT
        call arith_result
        mov [rip + vr_memory_top_v], rax
        mov rdi, [rip + vr_word_top_v]
        call int_neg
        mov [rip + vr_neg_word_top_v], rax
        LEAVE
ENDF ranges_init

# ---------------------------------------------------------------------
# helpers

# vr_number(v) -> rax: v as an integer value when it's an int or a bool
# (python's `type(exp) in (int, bool)`, and the matcher's ":int:", which is
# isinstance: True is 1), else 0. Only rax.
FUNC vr_number
        mov rax, rdi
        test dil, 1
        jnz 9f
        test rdi, rdi
        jz 8f
        cmp dword ptr [rdi + N_KIND], K_INT
        je 9f
        lea rax, [rip + sp_true]
        cmp rdi, rax
        jne 1f
        mov eax, 3                      # 1
        ret
1:      lea rax, [rip + sp_false]
        cmp rdi, rax
        jne 8f
        mov eax, 1                      # 0
        ret
8:      xor eax, eax
9:      ret
ENDF vr_number

# int_min(a, b) / int_max(a, b) -> rax: python's min and max of two
# integers (the first when they're equal)
FUNC int_min
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call int_cmp
        test eax, eax
        mov rax, rbx
        cmovg rax, r12
        LEAVE
ENDF int_min

FUNC int_max
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call int_cmp
        test eax, eax
        mov rax, rbx
        cmovl rax, r12
        LEAVE
ENDF int_max

# vr_top(top) -> rax: WORD_TOP or MEMORY_TOP
FUNC vr_top
        mov rax, [rip + vr_word_top_v]
        test edi, edi
        jz 1f
        mov rax, [rip + vr_memory_top_v]
1:      ret
ENDF vr_top

# vr_is_word(lo, hi) -> eax: 0 <= lo and hi <= WORD_TOP
FUNC vr_is_word
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call int_sign
        test eax, eax
        js 1f
        mov rdi, r12
        mov rsi, [rip + vr_word_top_v]
        call int_cmp
        cmp eax, 0
        jg 1f
        mov eax, 1
        LEAVE
1:      xor eax, eax
        LEAVE
ENDF vr_is_word

# vr_free_memory_pointer() -> eax: python's variants.FREE_MEMORY_POINTER -
# whether mem[64] is solidity's free memory pointer, at least 0x60 (the
# loader's decision about the contract; a context without one: the test
# hook's, else yes)
FUNC vr_free_memory_pointer
        mov rax, [r15 + CTX_LOADER]
        test rax, rax
        jz 1f
        cmp byte ptr [rax + LD_NO_FREE_MEM], 0
        sete al
        movzx eax, al
        ret
1:      cmp qword ptr [r15 + CTX_VR_NO_FMP], 0
        sete al
        movzx eax, al
        ret
ENDF vr_free_memory_pointer

# ---------------------------------------------------------------------
# value_range

# value_range(exp, bounds, top) -> rax: lo, rdx: hi (python's _value_range:
# remembered when there are no bounds)
FUNC value_range
        STACK_CHECK
        test rsi, rsi
        jnz vr_of
        mov rsi, rdx
        jmp vr_cached
ENDF value_range

# memory_range(exp) -> rax, rdx: value_range(exp, top=MEMORY_TOP)
FUNC memory_range
        mov esi, 1
        jmp vr_cached
ENDF memory_range

# vr_cached(exp, top) -> rax, rdx: python's _cached_value_range (a number
# is its own range: no table for them)
FUNC vr_cached
        STACK_CHECK
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        call vr_number
        test rax, rax
        jz 1f
        mov rdx, rax
        add rsp, 16
        LEAVE
1:      lea edi, [r12d + MEMO_VR_W]
        mov rsi, rbx
        call memo_get
        test rax, rax
        jz 2f
        mov rdx, [rax + N_DATA + 8]
        mov rax, [rax + N_DATA]
        add rsp, 16
        LEAVE
2:      mov rdi, rbx
        xor esi, esi
        mov rdx, r12
        call vr_of
        mov [rsp], rax
        mov [rsp + 8], rdx
        mov rdi, rax
        mov rsi, rdx
        call mk2
        lea edi, [r12d + MEMO_VR_W]
        mov rsi, rbx
        mov rdx, rax
        call memo_put
        mov rax, [rsp]
        mov rdx, [rsp + 8]
        add rsp, 16
        LEAVE
ENDF vr_cached

# vr_of(exp, bounds, top) -> rax, rdx: python's _value_range_of - the
# masks read three ways (as numbers minus the bits they clear, as numbers
# only where they clear none, not at all), each of which holds: what they
# all say
FUNC vr_of
        STACK_CHECK
        ENTER
        sub rsp, 48
        .set VO_LO, 0
        .set VO_HI, 8
        .set VO_BOUNDS, 16
        .set VO_TOP, 24
        mov rbx, rdi
        mov [rsp + VO_BOUNDS], rsi
        mov [rsp + VO_TOP], rdx
        mov rcx, rdx
        mov edx, VR_MASKS_ALL
        lea r8, [rsp + 32]              # (whether it read a mask as a number)
        mov qword ptr [r8], 0
        call vr_sum
        mov [rsp + VO_LO], rax
        mov [rsp + VO_HI], rdx
        cmp qword ptr [rsp + 32], 0
        je 9f                           # (no mask read: the other two are the same)
        mov r12d, VR_MASKS_EXACT
1:      mov rdi, rbx
        mov rsi, [rsp + VO_BOUNDS]
        mov edx, r12d
        mov rcx, [rsp + VO_TOP]
        xor r8d, r8d
        call vr_sum
        mov r13, rdx
        mov rdi, [rsp + VO_LO]
        mov rsi, rax
        call int_max
        mov [rsp + VO_LO], rax
        mov rdi, [rsp + VO_HI]
        mov rsi, r13
        call int_min
        mov [rsp + VO_HI], rax
        cmp r12d, VR_MASKS_EXACT
        jne 9f
        mov r12d, VR_MASKS_NONE
        jmp 1b
9:      mov rax, [rsp + VO_LO]
        mov rdx, [rsp + VO_HI]
        add rsp, 48
        LEAVE
ENDF vr_of

# vr_sum(exp, bounds, masks, top, read) -> rax, rdx: python's _sum_range -
# exp as a sum of terms times numbers plus a number, each term somewhere in
# its range. read: 0, or where to note that a mask was read as a number.
FUNC vr_sum
        STACK_CHECK
        ENTER
        sub rsp, 64
        .set VS_BOUNDS, 0
        .set VS_TOP, 8
        .set VS_LO, 16
        .set VS_HI, 24
        .set VS_I, 32
        .set VS_ACC, 40
        mov [rsp + VS_BOUNDS], rsi
        mov [rsp + VS_TOP], rcx
        mov rbx, rdi
        mov r12d, edx
        mov r13, r8
        mov edi, 16                     # the terms: [vec, read]
        call arena_alloc
        mov [rsp + VS_ACC], rax
        mov [rax + 8], r13
        call vec_new
        mov rcx, [rsp + VS_ACC]
        mov [rcx], rax
        mov rdi, rbx
        mov rsi, [rsp + VS_BOUNDS]
        mov edx, r12d
        mov rcx, [rsp + VS_TOP]
        mov r8d, 3                      # times 1
        mov r9, [rsp + VS_ACC]
        call vr_linear
        mov [rsp + VS_LO], rax
        mov [rsp + VS_HI], rax
        mov qword ptr [rsp + VS_I], 0
1:      mov rax, [rsp + VS_ACC]
        mov r13, [rax]
        mov rax, [rsp + VS_I]
        cmp rax, [r13 + VEC_LEN]
        jae 9f
        mov rcx, [r13 + VEC_DATA]
        mov r14, [rcx + rax*8 + 8]      # its coefficient
        mov rdi, [rcx + rax*8]          # the term
        add qword ptr [rsp + VS_I], 2
        cmp r14, 1                      # (0: python's `if c == 0: continue`)
        je 1b
        mov rsi, [rsp + VS_BOUNDS]
        mov rdx, [rsp + VS_TOP]
        call vr_term_range
        mov rbx, rax
        mov r12, rdx
        mov rdi, r14
        call int_sign
        test eax, eax
        jns 2f
        xchg rbx, r12                   # (below 0: its lowest makes the highest)
2:      mov rdi, r14
        mov rsi, rbx
        call int_mul
        mov rdi, [rsp + VS_LO]
        mov rsi, rax
        call int_add
        mov [rsp + VS_LO], rax
        mov rdi, r14
        mov rsi, r12
        call int_mul
        mov rdi, [rsp + VS_HI]
        mov rsi, rax
        call int_add
        mov [rsp + VS_HI], rax
        jmp 1b
9:      mov rax, [rsp + VS_LO]
        mov rdx, [rsp + VS_HI]
        add rsp, 64
        LEAVE
ENDF vr_sum

# vr_acc_add(acc, term, coef): python's terms[term] = terms.get(term, 0) +
# coef (the terms are hash-consed: one pointer each)
FUNC vr_acc_add
        ENTER
        mov rbx, [rdi]
        mov r12, rsi
        mov r13, rdx
        mov rcx, [rbx + VEC_DATA]
        mov rdx, [rbx + VEC_LEN]
        xor eax, eax
1:      cmp rax, rdx
        jae 3f
        cmp [rcx + rax*8], r12
        je 2f
        add rax, 2
        jmp 1b
2:      lea r14, [rcx + rax*8 + 8]
        mov rdi, [r14]
        mov rsi, r13
        call int_add
        mov [r14], rax
        LEAVE
3:      mov rdi, rbx
        mov rsi, r12
        call vec_push
        mov rdi, rbx
        mov rsi, r13
        call vec_push
        LEAVE
ENDF vr_acc_add

# vr_linear(exp, bounds, masks, top, mult, acc) -> rax: python's _linear,
# its terms times mult added to acc, its number times mult returned (the
# number python's _linear adds to them, (d_lo, d_hi), is always 0: what a
# mask clears is a term of its own, ("cleared", mask))
FUNC vr_linear
        STACK_CHECK
        ENTER
        sub rsp, 96
        .set VL_BOUNDS, 0
        .set VL_MASKS, 8
        .set VL_TOP, 16
        .set VL_MULT, 24
        .set VL_ACC, 32
        .set VL_CONST, 40
        .set VL_I, 48
        .set VL_K, 56
        .set VL_OFF, 64
        .set VL_HI, 72
        mov rbx, rdi
        mov [rsp + VL_BOUNDS], rsi
        mov [rsp + VL_MASKS], rdx
        mov [rsp + VL_TOP], rcx
        mov [rsp + VL_MULT], r8
        mov [rsp + VL_ACC], r9
        call vr_number
        test rax, rax
        jz 1f
        mov rdi, [rsp + VL_MULT]
        mov rsi, rax
        call int_mul
        jmp .Lvl_ret
1:      mov rdi, rbx
        call opcode_of
        cmp eax, OP_ADD
        je .Lvl_add
        cmp eax, OP_MUL
        je .Lvl_mul
        cmp eax, OP_MASK_SHL
        je .Lvl_mask
.Lvl_term:
        mov rdi, [rsp + VL_ACC]
        mov rsi, rbx
        mov rdx, [rsp + VL_MULT]
        call vr_acc_add
        mov eax, 1                      # 0
.Lvl_ret:
        add rsp, 96
        LEAVE

.Lvl_add:
        mov qword ptr [rsp + VL_CONST], 1
        mov qword ptr [rsp + VL_I], 1
2:      mov rax, [rsp + VL_I]
        mov ecx, [rbx + N_AUX]
        cmp rax, rcx
        jae 3f
        mov rdi, [rbx + N_DATA + rax*8]
        inc qword ptr [rsp + VL_I]
        mov rsi, [rsp + VL_BOUNDS]
        mov rdx, [rsp + VL_MASKS]
        mov rcx, [rsp + VL_TOP]
        mov r8, [rsp + VL_MULT]
        mov r9, [rsp + VL_ACC]
        call vr_linear
        mov rdi, [rsp + VL_CONST]
        mov rsi, rax
        call int_add
        mov [rsp + VL_CONST], rax
        jmp 2b
3:      mov rax, [rsp + VL_CONST]
        jmp .Lvl_ret

.Lvl_mul:
        # ("mul", k, ...): k times the rest, k an int (python's `type() is
        # int`: not a bool)
        mov ecx, [rbx + N_AUX]
        cmp ecx, 3
        jb .Lvl_term
        mov rdi, [rbx + N_DATA + 8]
        call is_int
        test eax, eax
        jz .Lvl_term
        mov rdi, [rsp + VL_MULT]
        mov rsi, [rbx + N_DATA + 8]
        call int_mul
        mov [rsp + VL_MULT], rax
        mov ecx, [rbx + N_AUX]
        cmp ecx, 3
        jne 4f
        mov rdi, [rbx + N_DATA + 16]    # the one factor left
        jmp 5f
4:      # ("mul",) + exp[2:]
        lea rdi, [rcx*8 - 8]
        call arena_alloc_raw
        mov rdx, rax
        mov rcx, [rbx + N_DATA]
        mov [rdx], rcx
        mov ecx, [rbx + N_AUX]
        mov r8d, 2
6:      cmp r8, rcx
        jae 7f
        mov r9, [rbx + N_DATA + r8*8]
        mov [rdx + r8*8 - 8], r9
        inc r8
        jmp 6b
7:      lea rdi, [rcx - 1]
        mov rsi, rdx
        call mk_tuple
        mov rdi, rax
5:      mov rsi, [rsp + VL_BOUNDS]
        mov rdx, [rsp + VL_MASKS]
        mov rcx, [rsp + VL_TOP]
        mov r8, [rsp + VL_MULT]
        mov r9, [rsp + VL_ACC]
        call vr_linear
        jmp .Lvl_ret

.Lvl_mask:
        # ("mask_shl", size, off, shl, x), size > 0, 0 <= off <= 16 (0 for
        # "exact"), shl >= 0: x with its lowest off bits cleared, times
        # 2**shl - when the mask cuts nothing at the top of x, nor the word
        # at the top of where it's moved
        cmp qword ptr [rsp + VL_MASKS], VR_MASKS_NONE
        je .Lvl_term
        cmp dword ptr [rbx + N_AUX], 5
        jne .Lvl_term
        mov rdi, [rbx + N_DATA + 8]
        call vr_number
        test rax, rax
        jz .Lvl_term
        mov r12, rax                    # size
        mov rdi, [rbx + N_DATA + 16]
        call vr_number
        test rax, rax
        jz .Lvl_term
        mov [rsp + VL_OFF], rax
        mov rdi, [rbx + N_DATA + 24]
        call vr_number
        test rax, rax
        jz .Lvl_term
        mov r13, rax                    # shl
        mov rdi, r12
        call int_sign
        cmp eax, 0
        jle .Lvl_term
        mov rax, [rsp + VL_OFF]         # 0 <= off <= 16: a small int
        test al, 1
        jz .Lvl_term
        sar rax, 1
        cmp rax, 16
        ja .Lvl_term                    # (below 0 too)
        mov [rsp + VL_OFF], rax
        test rax, rax
        jz 1f
        cmp qword ptr [rsp + VL_MASKS], VR_MASKS_ALL
        jne .Lvl_term
1:      mov rdi, r13
        call int_sign
        test eax, eax
        js .Lvl_term
        mov rdi, [rbx + N_DATA + 32]
        mov rsi, [rsp + VL_BOUNDS]
        mov rdx, [rsp + VL_TOP]
        call value_range
        mov [rsp + VL_HI], rdx
        mov rdi, rax
        call int_sign
        test eax, eax
        js .Lvl_term
        mov rdi, [rsp + VL_HI]
        call int_sign
        test eax, eax
        js 3f                           # (hi below 0: below both)
        # hi < 2 ** (off + size): its bits no more than them
        mov rdi, [rsp + VL_HI]
        call int_bit_length
        mov r14, rax
        test r12b, 1
        jz 2f                           # (a size past 2^62: no bound)
        mov rcx, r12
        sar rcx, 1
        add rcx, [rsp + VL_OFF]
        cmp r14, rcx
        jg .Lvl_term
2:      # hi << shl <= WORD_TOP: 0, or its bits and the shift within 256
        test r14, r14
        jz 3f
        test r13b, 1
        jz .Lvl_term
        mov rcx, r13
        sar rcx, 1
        add rcx, r14
        cmp rcx, 256
        jg .Lvl_term
3:      mov rdi, r13                    # k = 2 ** shl
        call clamp_bits
        mov rdi, rax
        call pow2
        mov [rsp + VL_K], rax
        mov rdi, [rsp + VL_ACC]         # (read as a number)
        mov rax, [rdi + 8]
        test rax, rax
        jz 4f
        mov qword ptr [rax], 1
4:      mov rdi, [rsp + VL_MULT]
        mov rsi, [rsp + VL_K]
        call int_mul
        mov r8, rax
        mov rdi, [rbx + N_DATA + 32]
        mov rsi, [rsp + VL_BOUNDS]
        mov rdx, [rsp + VL_MASKS]
        mov rcx, [rsp + VL_TOP]
        mov r9, [rsp + VL_ACC]
        call vr_linear
        mov [rsp + VL_CONST], rax
        cmp qword ptr [rsp + VL_OFF], 0
        je 5f
        # the bits it clears: ("cleared", mask) times -k
        LOADS rdi, CLEARED
        mov rsi, rbx
        call mk2
        mov r12, rax
        mov rdi, [rsp + VL_K]
        call int_neg
        mov rdi, [rsp + VL_MULT]
        mov rsi, rax
        call int_mul
        mov rdi, [rsp + VL_ACC]
        mov rsi, r12
        mov rdx, rax
        call vr_acc_add
5:      mov rax, [rsp + VL_CONST]
        jmp .Lvl_ret
ENDF vr_linear

# vr_word_top(exp, bounds, top) -> rax: python's _word_top - the highest
# exp can be, as a word
FUNC vr_word_top
        STACK_CHECK
        ENTER
        call value_range
        mov rbx, rdx
        mov rdi, rax
        mov rsi, rdx
        call vr_is_word
        test eax, eax
        mov rax, rbx
        jnz 1f
        mov rax, [rip + vr_word_top_v]
1:      LEAVE
ENDF vr_word_top

# ---------------------------------------------------------------------
# the terms

# vr_term_range(t, bounds, top) -> rax, rdx: python's _term_range
FUNC vr_term_range
        test rsi, rsi
        jnz vr_term_range_of
        STACK_CHECK
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rdx
        lea edi, [r12d + MEMO_TR_W]
        mov rsi, rbx
        call memo_get
        test rax, rax
        jz 1f
        mov rdx, [rax + N_DATA + 8]
        mov rax, [rax + N_DATA]
        add rsp, 16
        LEAVE
1:      mov rdi, rbx
        xor esi, esi
        mov rdx, r12
        call vr_term_range_of
        mov [rsp], rax
        mov [rsp + 8], rdx
        mov rdi, rax
        mov rsi, rdx
        call mk2
        lea edi, [r12d + MEMO_TR_W]
        mov rsi, rbx
        mov rdx, rax
        call memo_put
        mov rax, [rsp]
        mov rdx, [rsp + 8]
        add rsp, 16
        LEAVE
ENDF vr_term_range

# vr_term_range_of(t, bounds, top) -> rax, rdx: python's _term_range_of -
# with MEMORY_TOP, a term of an address or a size is below it, unless it's
# made of what may not be a word (a mask of -x) or of what the contract is
# given, unchecked - but for the words known to be small
FUNC vr_term_range_of
        STACK_CHECK
        ENTER
        sub rsp, 32
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        call vr_whole_term_range
        mov [rsp], rax
        mov [rsp + 8], rdx
        test r13, r13
        jz 9f
        mov rdi, rax
        mov rsi, [rip + vr_memory_top_v]
        call int_cmp
        cmp eax, 0
        jg 9f                           # (lo above it)
        mov rdi, [r15 + CTX_VR_SMALL]
        test rdi, rdi
        jz 1f
        mov rsi, rbx
        call emap_get
        test rax, rax
        jnz 2f
1:      mov rdi, rbx
        mov rsi, r12
        call vr_of_wrapped
        test eax, eax
        jnz 9f
        mov rdi, rbx
        call vr_of_unchecked
        test eax, eax
        jnz 9f
2:      mov rdi, [rsp + 8]
        mov rsi, [rip + vr_memory_top_v]
        call int_min
        mov [rsp + 8], rax
9:      mov rax, [rsp]
        mov rdx, [rsp + 8]
        add rsp, 32
        LEAVE
ENDF vr_term_range_of

# vr_of_wrapped(t, bounds) -> eax: python's _of_wrapped - t is a word made
# of what may not be one (a mask of -x...)
FUNC vr_of_wrapped
        STACK_CHECK
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov [rsp], rsi
        call opcode_of
        mov r13d, 4                     # the first of the arguments looked at
        cmp eax, OP_MASK_SHL
        jne 1f
        cmp dword ptr [rbx + N_AUX], 5
        je 2f
        jmp 8f
1:      mov r13d, 1
        cmp eax, OP_DIV
        je 2f
        cmp eax, OP_MOD
        je 2f
        cmp eax, OP_AND
        je 2f
        cmp eax, OP_OR
        je 2f
        cmp eax, OP_XOR
        je 2f
        cmp eax, OP_MIN
        je 2f
        cmp eax, OP_MAX
        jne 8f
2:      mov eax, [rbx + N_AUX]
        cmp r13, rax
        jae 8f
        mov rdi, [rbx + N_DATA + r13*8]
        inc r13
        mov r12, rdi
        call is_int
        test eax, eax
        jz 3f
        mov rax, r12                    # (a number: itself)
        mov rdx, r12
        jmp 4f
3:      mov rdi, r12
        mov rsi, [rsp]
        xor edx, edx
        call value_range
4:      mov rdi, rax
        mov rsi, rdx
        call vr_is_word
        test eax, eax
        jnz 2b
        mov eax, 1
        add rsp, 16
        LEAVE
8:      xor eax, eax
        add rsp, 16
        LEAVE
ENDF vr_of_wrapped

# vr_of_unchecked(t) -> eax: python's _of_unchecked (remembered)
FUNC vr_of_unchecked
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov edi, MEMO_UNCHECKED
        mov rsi, rbx
        call memo_get
        test rax, rax
        jz 1f
        cmp rax, MEMO_TRUE
        sete al
        movzx eax, al
        LEAVE
1:      mov rdi, rbx
        mov rsi, [r15 + CTX_VR_VARS]
        mov rdx, [r15 + CTX_VR_SMALL]
        call unchecked
        mov r12d, eax
        mov edx, MEMO_FALSE
        mov ecx, MEMO_TRUE
        test eax, eax
        cmovnz edx, ecx
        mov edi, MEMO_UNCHECKED
        mov rsi, rbx
        call memo_put
        mov eax, r12d
        LEAVE
ENDF vr_of_unchecked

# vr_whole_term_range(t, bounds, top) -> rax, rdx: python's _whole_term_range
FUNC vr_whole_term_range
        STACK_CHECK
        ENTER
        sub rsp, 64
        .set VW_BOUNDS, 0
        .set VW_TOP, 8
        .set VW_LO, 16
        .set VW_HI, 24
        .set VW_I, 32
        mov rbx, rdi
        mov [rsp + VW_BOUNDS], rsi
        mov [rsp + VW_TOP], rdx
        # what bounds says
        test rsi, rsi
        jz 1f
        mov rdi, rsi
        mov rsi, rbx
        call emap_get
        test rax, rax
        jz 1f
        mov rdx, [rax + N_DATA + 8]
        mov rax, [rax + N_DATA]
        jmp .Lvw_ret
1:      mov rdi, rbx
        call opcode_of
        mov r12d, eax
        cmp eax, OP_CLEARED
        je .Lvw_cleared
        cmp eax, OP_VAR
        je .Lvw_var
.Lvw_not_var:
        mov rdi, rbx
        call vr_number
        test rax, rax
        jz 2f
        mov rdx, rax
        jmp .Lvw_ret
2:      mov rdi, rbx
        call is_str
        test eax, eax
        jnz .Lvw_str
        # (the operations python's BOOL_OPS names: 0 or 1)
        mov eax, r12d
        IN_OPSET vr_bool_ops, rax
        jne .Lvw_bool
        cmp r12d, OP_MUL
        je .Lvw_mul
        cmp r12d, OP_MOD
        je .Lvw_mod
        cmp r12d, OP_DIV
        je .Lvw_div
        cmp r12d, OP_MASK_SHL
        je .Lvw_mask
.Lvw_storage:
        cmp r12d, OP_STORAGE
        jne .Lvw_mem64
        cmp dword ptr [rbx + N_AUX], 4
        jne .Lvw_mem64
        mov rdi, [rbx + N_DATA + 8]
        call vr_number
        test rax, rax
        jz .Lvw_mem64
        mov r13, rax                    # size
        mov rdi, [rbx + N_DATA + 16]
        call vr_number
        test rax, rax
        jz .Lvw_mem64
        mov rdi, rax
        call int_sign
        test eax, eax
        js .Lvw_mem64
        # 2 ** max(0, min(size, 256)) - 1
        mov rdi, r13
        call clamp_bits
        mov rdi, rax
        cmp rdi, 256
        jle 3f
        mov edi, 256
3:      test rdi, rdi
        jns 4f
        xor edi, edi
4:      call pow2
        mov rdi, rax
        mov esi, 3
        call int_sub
        mov rdx, rax
        mov eax, 1
        jmp .Lvw_ret
.Lvw_mem64:
        mov rdi, rbx
        call is_mem64
        test eax, eax
        jz .Lvw_and
        call vr_free_memory_pointer
        test eax, eax
        jz .Lvw_and
        mov eax, (0x60 << 1) | 1        # solidity's free memory pointer
        mov rdx, [rip + vr_word_top_v]
        jmp .Lvw_ret
.Lvw_and:
        cmp r12d, OP_AND
        jne .Lvw_or
        cmp dword ptr [rbx + N_AUX], 1
        jbe .Lvw_any
        # 0, the lowest of the highest of its operands
        mov r13, [rip + vr_word_top_v]  # (python's min of what follows: the first, at least)
        mov qword ptr [rsp + VW_I], 1
        mov qword ptr [rsp + VW_HI], 0
5:      mov rax, [rsp + VW_I]
        mov ecx, [rbx + N_AUX]
        cmp rax, rcx
        jae 6f
        mov rdi, [rbx + N_DATA + rax*8]
        inc qword ptr [rsp + VW_I]
        mov rsi, [rsp + VW_BOUNDS]
        xor edx, edx
        call vr_word_top
        cmp qword ptr [rsp + VW_HI], 0
        je 7f
        mov rdi, [rsp + VW_HI]
        mov rsi, rax
        call int_min
7:      mov [rsp + VW_HI], rax
        jmp 5b
6:      mov eax, 1
        mov rdx, [rsp + VW_HI]
        jmp .Lvw_ret
.Lvw_or:
        cmp r12d, OP_OR
        je 1f
        cmp r12d, OP_XOR
        jne .Lvw_minmax
1:      cmp dword ptr [rbx + N_AUX], 1
        jbe .Lvw_any
        # 2 ** (the most bits of its operands) - 1
        mov qword ptr [rsp + VW_I], 1
        xor r13d, r13d
2:      mov rax, [rsp + VW_I]
        mov ecx, [rbx + N_AUX]
        cmp rax, rcx
        jae 3f
        mov rdi, [rbx + N_DATA + rax*8]
        inc qword ptr [rsp + VW_I]
        mov rsi, [rsp + VW_BOUNDS]
        xor edx, edx
        call vr_word_top
        mov rdi, rax
        call int_bit_length
        cmp rax, r13
        cmova r13, rax
        jmp 2b
3:      mov rdi, r13
        call pow2
        mov rdi, rax
        mov esi, 3
        call int_sub
        mov rdx, rax
        mov eax, 1
        jmp .Lvw_ret
.Lvw_minmax:
        cmp r12d, OP_MIN
        je 1f
        cmp r12d, OP_MAX
        jne .Lvw_any
1:      cmp dword ptr [rbx + N_AUX], 1
        jbe .Lvw_any
        # the lowest (highest) of its operands' lowest, and of their
        # highest - when they're all words
        mov qword ptr [rsp + VW_I], 1
        mov qword ptr [rsp + VW_LO], 0
        mov qword ptr [rsp + VW_HI], 0
2:      mov rax, [rsp + VW_I]
        mov ecx, [rbx + N_AUX]
        cmp rax, rcx
        jae 4f
        mov rdi, [rbx + N_DATA + rax*8]
        inc qword ptr [rsp + VW_I]
        mov rsi, [rsp + VW_BOUNDS]
        xor edx, edx
        call value_range
        mov r13, rax
        mov r14, rdx
        mov rdi, rax
        mov rsi, rdx
        call vr_is_word
        test eax, eax
        jz .Lvw_any
        cmp qword ptr [rsp + VW_LO], 0
        jne 3f
        mov [rsp + VW_LO], r13
        mov [rsp + VW_HI], r14
        jmp 2b
3:      mov rdi, [rsp + VW_LO]
        mov rsi, r13
        cmp r12d, OP_MIN
        jne 31f
        call int_min
        mov [rsp + VW_LO], rax
        mov rdi, [rsp + VW_HI]
        mov rsi, r14
        call int_min
        mov [rsp + VW_HI], rax
        jmp 2b
31:     call int_max
        mov [rsp + VW_LO], rax
        mov rdi, [rsp + VW_HI]
        mov rsi, r14
        call int_max
        mov [rsp + VW_HI], rax
        jmp 2b
4:      mov rax, [rsp + VW_LO]
        mov rdx, [rsp + VW_HI]
        jmp .Lvw_ret
.Lvw_any:
        mov eax, 1
        mov rdx, [rip + vr_word_top_v]
.Lvw_ret:
        add rsp, 64
        LEAVE

.Lvw_cleared:
        # the bits a mask clears (see vr_linear): 0 to 2 ** off - 1
        mov rax, [rbx + N_DATA + 8]
        mov rdi, [rax + N_DATA + 16]
        call vr_number                  # (True: 1)
        mov rdi, rax
        call clamp_bits
        mov rdi, rax
        call pow2
        mov rdi, rax
        mov esi, 3
        call int_sub
        mov rdx, rax
        mov eax, 1
        jmp .Lvw_ret

.Lvw_bool:
        mov eax, 1
        mov edx, 3
        jmp .Lvw_ret

.Lvw_str:
        # 2 ** 64 - 1 for what gas pays for (python's BOUNDED_SYMBOLS), a
        # word for the rest
        mov eax, [rbx + N_AUX]
        and eax, STR_ID_MASK
        IN_OPSET vr_bounded, rax
        mov rdx, [rip + vr_word_top_v]
        je 1f
        mov rdx, [rip + vr_memory_top_v]
1:      mov eax, 1
        jmp .Lvw_ret

.Lvw_var:
        # ("var", name), name one of set_variables': one of the values it's
        # set to - unless one of them is made of it (a loop's counter), or
        # it's being looked at: then any word
        cmp dword ptr [rbx + N_AUX], 2
        jne .Lvw_not_var
        mov rdi, [r15 + CTX_VR_VARS]
        test rdi, rdi
        jz .Lvw_not_var
        mov r13, [rbx + N_DATA + 8]     # the name
        mov rsi, r13
        call emap_get
        test rax, rax
        jz .Lvw_not_var
        mov r14, rax                    # its values
        mov rdi, [r15 + CTX_VR_CYCLIC]
        mov rsi, r13
        call emap_get
        test rax, rax
        jnz .Lvw_not_var
        call vr_visiting
        mov rdi, rax
        mov rsi, r13
        call emap_get
        test rax, rax
        jnz .Lvw_not_var
        mov rdi, r13
        mov rsi, r14
        mov rdx, [rsp + VW_BOUNDS]
        mov rcx, [rsp + VW_TOP]
        call vr_var_values
        mov [rsp + VW_LO], rax
        mov [rsp + VW_HI], rdx
        mov rdi, [rsp + VW_LO]
        mov rsi, [rsp + VW_HI]
        call vr_is_word
        test eax, eax
        jz .Lvw_any
        mov rax, [rsp + VW_LO]
        mov rdx, [rsp + VW_HI]
        jmp .Lvw_ret

.Lvw_mul:
        # a product of what isn't numbers
        mov qword ptr [rsp + VW_LO], 3
        mov qword ptr [rsp + VW_HI], 3
        mov qword ptr [rsp + VW_I], 1
1:      mov rax, [rsp + VW_I]
        mov ecx, [rbx + N_AUX]
        cmp rax, rcx
        jae 2f
        mov rdi, [rbx + N_DATA + rax*8]
        inc qword ptr [rsp + VW_I]
        mov rsi, [rsp + VW_BOUNDS]
        xor edx, edx
        call value_range
        mov rdi, [rsp + VW_LO]
        mov rsi, [rsp + VW_HI]
        mov rcx, rdx
        mov rdx, rax
        call vr_product
        mov [rsp + VW_LO], rax
        mov [rsp + VW_HI], rdx
        jmp 1b
2:      mov rax, [rsp + VW_LO]
        mov rdx, [rsp + VW_HI]
        jmp .Lvw_ret

.Lvw_mod:
        cmp dword ptr [rbx + N_AUX], 3
        jne .Lvw_storage
        mov rdi, [rbx + N_DATA + 16]
        call vr_number
        test rax, rax
        jz .Lvw_mod_any
        mov r13, rax                    # c
        mov rdi, rax
        call int_sign
        cmp eax, 0
        jle .Lvw_mod_any
        # 0, min(c - 1, the highest of x)
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, [rsp + VW_BOUNDS]
        xor edx, edx
        call vr_word_top
        mov r14, rax
        mov rdi, r13
        mov esi, 3
        call int_sub
        mov rdi, rax
        mov rsi, r14
        call int_min
        mov rdx, rax
        mov eax, 1
        jmp .Lvw_ret
.Lvw_mod_any:
        # (python's division test comes before: a div isn't a mod) below
        # what it's divided by: 0, max(the highest of y - 1, 0)
        mov rdi, [rbx + N_DATA + 16]
        mov rsi, [rsp + VW_BOUNDS]
        mov rdx, [rsp + VW_TOP]
        call vr_word_top
        mov rdi, rax
        mov esi, 3
        call int_sub
        mov rdi, rax
        mov esi, 1
        call int_max
        mov rdx, rax
        mov eax, 1
        jmp .Lvw_ret

.Lvw_div:
        cmp dword ptr [rbx + N_AUX], 3
        jne .Lvw_storage
        mov rdi, [rbx + N_DATA + 16]
        call vr_number
        test rax, rax
        jz .Lvw_storage
        mov r13, rax                    # c
        mov rdi, rax
        call int_sign
        cmp eax, 0
        jle .Lvw_storage
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, [rsp + VW_BOUNDS]
        xor edx, edx
        call vr_word_top
        mov rdi, rax
        mov rsi, r13
        call int_floordiv
        mov rdx, rax
        mov eax, 1
        jmp .Lvw_ret

.Lvw_mask:
        cmp dword ptr [rbx + N_AUX], 5
        jne .Lvw_storage
        mov rdi, [rbx + N_DATA + 8]
        call vr_number
        test rax, rax
        jz .Lvw_storage
        mov r13, rax                    # size
        mov rdi, [rbx + N_DATA + 16]
        call vr_number
        test rax, rax
        jz .Lvw_storage
        mov r14, rax                    # off
        mov rdi, [rbx + N_DATA + 24]
        call vr_number
        test rax, rax
        jz .Lvw_storage
        mov [rsp + VW_I], rax           # shl
        # high_bit = clamp(off + size), down to the bits of x when it isn't
        # wider than a word
        mov rdi, r14
        mov rsi, r13
        call int_add
        mov rdi, rax
        call clamp_bits
        mov r13, rax                    # high_bit
        mov rdi, [rbx + N_DATA + 32]
        call may_be_wide
        test eax, eax
        jnz 1f
        mov rdi, [rbx + N_DATA + 32]
        mov rsi, [rsp + VW_BOUNDS]
        xor edx, edx
        call vr_word_top
        mov rdi, rax
        call int_bit_length
        cmp rax, r13
        cmovl r13, rax
1:      # bottom = max(off, 0): nothing when it's at or above high_bit
        mov rdi, r14
        call int_sign
        xor r12d, r12d                  # bottom
        test eax, eax
        js 2f
        test r14b, 1
        jz .Lvw_zero                    # (an offset past 2^62: above any high_bit)
        mov r12, r14
        sar r12, 1
2:      cmp r13, r12
        jle .Lvw_zero
        # high = 2 ** high_bit - 2 ** bottom, moved by shl
        mov rdi, r13
        call pow2
        mov r13, rax
        mov rdi, r12
        call pow2
        mov rdi, r13
        mov rsi, rax
        call int_sub
        mov r13, rax
        mov rdi, [rsp + VW_I]
        call int_sign
        test eax, eax
        js 3f
        mov rdi, [rsp + VW_I]
        call clamp_bits
        mov rdi, r13
        mov rsi, rax
        call int_shl_bits
        jmp 4f
3:      mov rdi, [rsp + VW_I]           # >> -shl
        call int_neg
        mov rdi, r13
        mov rsi, rax
        call vr_shr
4:      mov rdi, rax
        mov rsi, [rip + vr_word_top_v]
        call int_min
        mov rdx, rax
        mov eax, 1
        jmp .Lvw_ret
.Lvw_zero:
        mov eax, 1
        mov edx, 1
        jmp .Lvw_ret
ENDF vr_whole_term_range

# vr_var_values(name, values, bounds, top) -> rax, rdx: vr_var_ranges, the
# name being looked at meanwhile (python's _VISITING.add, and its discard
# in a finally: an error goes on, the name discarded)
FUNC vr_var_values
        STACK_CHECK
        ENTER
        sub rsp, ERR_SIZEOF + 32
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov r14, rcx
        call vr_visiting
        mov rdi, rax
        mov rsi, rbx
        mov edx, 1
        call emap_put
        mov rdi, rsp
        call err_catch
        test eax, eax
        jnz 1f
        mov rdi, r12
        mov rsi, r13
        mov rdx, r14
        call vr_var_ranges
        mov [rsp + ERR_SIZEOF], rax
        mov [rsp + ERR_SIZEOF + 8], rdx
        call err_end
        call vr_visiting
        mov rdi, rax
        mov rsi, rbx
        xor edx, edx
        call emap_put
        mov rax, [rsp + ERR_SIZEOF]
        mov rdx, [rsp + ERR_SIZEOF + 8]
        add rsp, ERR_SIZEOF + 32
        LEAVE
1:      mov [rsp + ERR_SIZEOF], rax     # the error's code
        call vr_visiting
        mov rdi, rax
        mov rsi, rbx
        xor edx, edx
        call emap_put
        mov rdi, [rsp + ERR_SIZEOF]
        mov rsi, [r15 + CTX_ERR_MSG]
        call err_throw
ENDF vr_var_values

# vr_var_ranges(values, bounds, top) -> rax, rdx: the lowest of their
# lowest and the highest of their highest. A variable is set to one value
# at least (python's min() of none is a ValueError).
FUNC vr_var_ranges
        STACK_CHECK
        ENTER
        sub rsp, 48
        mov rbx, rdi
        mov [rsp], rsi                  # bounds
        mov [rsp + 8], rdx              # top
        mov qword ptr [rsp + 16], 0     # lo
        mov qword ptr [rsp + 24], 0     # hi
        xor r12d, r12d
        cmp dword ptr [rbx + N_AUX], 0
        jne 1f
        mov edi, E_VALUE
        lea rsi, [rip + .Ls_min_empty]
        call err_throw
1:      mov eax, [rbx + N_AUX]
        cmp r12, rax
        jae 9f
        mov rdi, [rbx + N_DATA + r12*8]
        inc r12
        mov rsi, [rsp]
        mov rdx, [rsp + 8]
        call value_range
        mov r13, rax
        mov r14, rdx
        cmp qword ptr [rsp + 16], 0
        jne 2f
        mov [rsp + 16], r13
        mov [rsp + 24], r14
        jmp 1b
2:      mov rdi, [rsp + 16]
        mov rsi, r13
        call int_min
        mov [rsp + 16], rax
        mov rdi, [rsp + 24]
        mov rsi, r14
        call int_max
        mov [rsp + 24], rax
        jmp 1b
9:      mov rax, [rsp + 16]
        mov rdx, [rsp + 24]
        add rsp, 48
        LEAVE
ENDF vr_var_ranges

        .section .rodata
.Ls_min_empty: .asciz "min() arg is an empty sequence"
        .text

# vr_product(lo, hi, f_lo, f_hi) -> rax, rdx: the lowest and the highest of
# lo * f_lo, lo * f_hi, hi * f_lo, hi * f_hi
FUNC vr_product
        ENTER
        sub rsp, 48
        mov [rsp], rdi
        mov [rsp + 8], rsi
        mov [rsp + 16], rdx
        mov [rsp + 24], rcx
        mov rsi, rdx
        call int_mul                    # lo * f_lo
        mov rbx, rax
        mov r12, rax
        mov rdi, [rsp]
        mov rsi, [rsp + 24]
        call int_mul                    # lo * f_hi
        mov r13, rax
        mov rdi, rbx
        mov rsi, r13
        call int_min
        mov rbx, rax
        mov rdi, r12
        mov rsi, r13
        call int_max
        mov r12, rax
        mov rdi, [rsp + 8]
        mov rsi, [rsp + 16]
        call int_mul                    # hi * f_lo
        mov r13, rax
        mov rdi, rbx
        mov rsi, r13
        call int_min
        mov rbx, rax
        mov rdi, r12
        mov rsi, r13
        call int_max
        mov r12, rax
        mov rdi, [rsp + 8]
        mov rsi, [rsp + 24]
        call int_mul                    # hi * f_hi
        mov r13, rax
        mov rdi, rbx
        mov rsi, r13
        call int_min
        mov rbx, rax
        mov rdi, r12
        mov rsi, r13
        call int_max
        mov rdx, rax
        mov rax, rbx
        add rsp, 48
        LEAVE
ENDF vr_product

# vr_shr(v, k) -> rax: v >> k (python's, of a number >= 0; k a value >= 0:
# 0 past v's bits)
FUNC vr_shr
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov rdi, rbx
        call int_bit_length
        test r12b, 1
        jz 1f                           # (k past 2^62)
        mov rcx, r12
        sar rcx, 1
        cmp rcx, rax
        jae 1f
        mov r12, rcx
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, rbx
        call value_set_mpz
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, rdi
        mov rdx, r12
        call __gmpz_fdiv_q_2exp@PLT
        call arith_result
        LEAVE
1:      mov eax, 1
        LEAVE
ENDF vr_shr

# vr_visiting() -> rax: the set of the variables being looked at (made on
# demand)
FUNC vr_visiting
        mov rax, [r15 + CTX_VR_VISITING]
        test rax, rax
        jz 1f
        ret
1:      ENTER
        call emap_new
        mov [r15 + CTX_VR_VISITING], rax
        LEAVE
ENDF vr_visiting

# may_be_wide(exp) -> eax: python's may_be_wide - exp may have more than 256
# bits: a value from memory may be longer than a word (a string, the
# arguments of a call), and a mask of 256 bits of it doesn't leave it as
# it is
FUNC may_be_wide
        ENTER
        mov rbx, rdi
        call is_int
        test eax, eax
        jz 1f
        mov rdi, rbx
        mov rsi, [rip + vr_word_top_v]
        call int_cmp
        cmp eax, 0
        setg al
        movzx eax, al
        LEAVE
1:      mov rdi, rbx
        call opcode_of
        cmp eax, OP_DATA
        je 7f
        cmp eax, OP_BYTES
        je .Lmw_bytes
        cmp eax, OP_MEM
        je .Lmw_mem
        IN_OPSET vr_wide_ops, rax
        jne .Lmw_array
        xor eax, eax
        LEAVE
.Lmw_bytes:
        # not if it's of a number of bytes up to 32
        cmp dword ptr [rbx + N_AUX], 2
        jb 7f
        mov rdi, [rbx + N_DATA + 8]
        jmp .Lmw_length
.Lmw_mem:
        # ("mem", ("range", x, length)): not if length is a number up to 32
        cmp dword ptr [rbx + N_AUX], 2
        jb 7f
        mov rdi, [rbx + N_DATA + 8]
        mov esi, OP_RANGE
        mov edx, 3
        call is_op_n
        test eax, eax
        jz 7f
        mov rax, [rbx + N_DATA + 8]
        mov rdi, [rax + N_DATA + 16]
        jmp .Lmw_length
.Lmw_array:
        # (op, x, length): the same
        cmp dword ptr [rbx + N_AUX], 3
        jne 7f
        mov rdi, [rbx + N_DATA + 16]
.Lmw_length:
        # a number (not a bool: python's type() is int) up to 32: no
        mov r12, rdi
        call is_int
        test eax, eax
        jz 7f
        mov rdi, r12
        mov esi, (32 << 1) | 1
        call int_cmp
        cmp eax, 0
        jg 7f
        xor eax, eax
        LEAVE
7:      mov eax, 1
        LEAVE
ENDF may_be_wide

# ---------------------------------------------------------------------
# what the variables are (python's set_variables and its globals)

# set_variables(args): python's set_variables(values, small). args is 0
# (python's set_variables({})) or (vars, small): vars a tuple of (name,
# values) - what each variable of the trace being simplified is set to,
# anywhere in it - and small a tuple of the words of it known to be below
# 2**64 (see simplify.small_words). What was decided under others is
# forgotten (clear_caches).
FUNC set_variables
        ENTER
        mov [r15 + CTX_VR_ARGS], rdi
        call vr_rebuild
        call clear_caches
        LEAVE
ENDF set_variables

# vr_rebuild(): CTX_VR_VARS, CTX_VR_SMALL and CTX_VR_CYCLIC from
# CTX_VR_ARGS (set_variables, and a compaction: they're of the arena)
FUNC vr_rebuild
        ENTER
        sub rsp, 16
        xor eax, eax
        mov [r15 + CTX_VR_VARS], rax
        mov [r15 + CTX_VR_SMALL], rax
        mov [r15 + CTX_VR_CYCLIC], rax
        mov [r15 + CTX_VR_VISITING], rax
        mov [r15 + CTX_VR_SEEN_U], rax
        mov [r15 + CTX_VR_SEEN_M], rax
        mov rbx, [r15 + CTX_VR_ARGS]
        test rbx, rbx
        jz 9f
        mov r12, [rbx + N_DATA]         # vars
        mov r13, [rbx + N_DATA + 8]     # small
        mov ecx, [r12 + N_AUX]
        test ecx, ecx
        jz 3f
        call emap_new
        mov [r15 + CTX_VR_VARS], rax
        xor r14d, r14d
1:      mov eax, [r12 + N_AUX]
        cmp r14, rax
        jae 2f
        mov rax, [r12 + N_DATA + r14*8]
        inc r14
        mov rdi, [r15 + CTX_VR_VARS]
        mov rsi, [rax + N_DATA]
        mov rdx, [rax + N_DATA + 8]
        call emap_put
        jmp 1b
2:      # the variables a value of which is made of them
        call emap_new
        mov [r15 + CTX_VR_CYCLIC], rax
        xor r14d, r14d
21:     mov eax, [r12 + N_AUX]
        cmp r14, rax
        jae 3f
        mov rax, [r12 + N_DATA + r14*8]
        inc r14
        mov rbx, [rax + N_DATA]         # the name
        mov rax, [rax + N_DATA + 8]     # its values
        mov [rsp], rax
        mov qword ptr [rsp + 8], 0
22:     mov rax, [rsp]
        mov rcx, [rsp + 8]
        cmp ecx, [rax + N_AUX]
        jae 21b
        mov rdi, [rax + N_DATA + rcx*8]
        inc qword ptr [rsp + 8]
        mov rsi, rbx
        call mentions_var
        test eax, eax
        jz 22b
        mov rdi, [r15 + CTX_VR_CYCLIC]
        mov rsi, rbx
        mov edx, 1
        call emap_put
        jmp 21b
3:      mov ecx, [r13 + N_AUX]
        test ecx, ecx
        jz 9f
        call emap_new
        mov [r15 + CTX_VR_SMALL], rax
        xor r14d, r14d
4:      mov eax, [r13 + N_AUX]
        cmp r14, rax
        jae 9f
        mov rdi, [r15 + CTX_VR_SMALL]
        mov rsi, [r13 + N_DATA + r14*8]
        inc r14
        mov edx, 1
        call emap_put
        jmp 4b
9:      add rsp, 16
        LEAVE
ENDF vr_rebuild

# clear_caches(): python's helpers.clear_caches - what was computed and
# remembered is forgotten, when what it rests on changes. Python clears its
# @cached functions' (simplify, add_op, lt_op, le_op, the ranges, to_mask,
# simplify_exp, find_mems, replace_mem_exp, range_overlaps...): the memo
# tables here, but for mask_op's (python's mask_dict isn't one of them) and
# the ones of what no comparison decides (the signature database, an
# import's, the lines' variables, the tests' nodes).
        .set CLEAR_CACHES_KEEP, (1 << MEMO_MASK) | (1 << MEMO_TEST_NODES) | (1 << MEMO_SIGDB) | (1 << MEMO_IMPORT) | (1 << MEMO_LINE_VARS) | (1 << MEMO_LINE_SETVARS)

FUNC clear_caches
        xor eax, eax
        xor ecx, ecx
        mov rdx, CLEAR_CACHES_KEEP
1:      cmp ecx, MEMO_COUNT
        jae 3f
        bt rdx, rcx
        jc 2f
        mov [r15 + CTX_MEMO + rcx*8], rax
2:      inc ecx
        jmp 1b
3:      ret
ENDF clear_caches

# mentions_var(exp, name) -> eax: python's mentions_var - exp reads the
# variable, or one whose values do (see set_variables)
FUNC mentions_var
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov rax, [r15 + CTX_VR_SEEN_M]
        test rax, rax
        jnz 1f
        call emap_new
        mov [r15 + CTX_VR_SEEN_M], rax
1:      mov rdi, rax
        call emap_begin
        mov rdi, rbx
        mov rsi, r12
        call mentions_var_f
        LEAVE
ENDF mentions_var

FUNC mentions_var_f
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        xor r14d, r14d
        test bl, 1
        jnz 8f
        test rbx, rbx
        jz 8f
        cmp dword ptr [rbx + N_KIND], K_TUPLE
        jne 8f
        mov rdi, rbx
        mov esi, OP_VAR
        mov edx, 2
        call is_op_n
        test eax, eax
        jz .Lmv_walk
        mov r13, [rbx + N_DATA + 8]
        mov rdi, r13
        mov rsi, r12
        call py_equal
        test eax, eax
        jnz 7f
        mov rdi, [r15 + CTX_VR_VARS]
        test rdi, rdi
        jz 8f
        mov rsi, r13
        call emap_get
        test rax, rax
        jz 8f
        mov r14, rax                    # its values
        mov rdi, [r15 + CTX_VR_SEEN_M]
        mov rsi, r13
        call emap_add
        test eax, eax
        jz 8f
        mov rbx, r14
.Lmv_walk:
        # any of the elements (from the second: python's e[1:]) - or, for
        # a variable's values, any of them
        mov r13d, 1
        cmp rbx, r14
        jne 1f
        xor r13d, r13d
1:      mov eax, [rbx + N_AUX]
        cmp r13, rax
        jae 8f
        mov rdi, [rbx + N_DATA + r13*8]
        inc r13
        mov rsi, r12
        call mentions_var_f
        test eax, eax
        jz 1b
7:      mov eax, 1
        LEAVE
8:      xor eax, eax
        LEAVE
ENDF mentions_var_f

# unchecked(exp, values, small) -> eax: python's unchecked - exp is made of
# a word the contract is given (INPUTS: cd, call.data, ext_call.return_data)
# that isn't in small, computed from it (COMPUTED), or a variable set to
# it. values: an emap {name: values} or 0; small: an emap or 0.
FUNC unchecked
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov rax, [r15 + CTX_VR_SEEN_U]
        test rax, rax
        jnz 1f
        call emap_new
        mov [r15 + CTX_VR_SEEN_U], rax
1:      mov rdi, rax
        call emap_begin
        mov rdi, rbx
        mov rsi, r12
        mov rdx, r13
        call unchecked_f
        LEAVE
ENDF unchecked

FUNC unchecked_f
        STACK_CHECK
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        test bl, 1
        jnz 8f
        test rbx, rbx
        jz 8f
        cmp dword ptr [rbx + N_KIND], K_TUPLE
        jne 8f
        cmp dword ptr [rbx + N_AUX], 0
        je 8f
        test r13, r13
        jz 1f
        mov rdi, r13
        mov rsi, rbx
        call emap_get
        test rax, rax
        jnz 8f
1:      mov rdi, rbx
        call opcode_of
        mov r14d, eax
        IN_OPSET vr_inputs, rax
        jne 7f
        cmp r14d, OP_VAR
        jne 4f
        cmp dword ptr [rbx + N_AUX], 2
        jne 4f
        # a variable: one of the values it's set to, the first time
        test r12, r12
        jz 8f
        mov rdi, r12
        mov rsi, [rbx + N_DATA + 8]
        call emap_get
        test rax, rax
        jz 8f
        mov [rsp], rax
        mov rdi, [r15 + CTX_VR_SEEN_U]
        mov rsi, [rbx + N_DATA + 8]
        call emap_add
        test eax, eax
        jz 8f
        mov rbx, [rsp]
        xor r14d, r14d
        jmp 5f
4:      mov eax, r14d
        IN_OPSET vr_computed, rax
        je 8f
        mov r14d, 1
5:      mov eax, [rbx + N_AUX]
        cmp r14, rax
        jae 8f
        mov rdi, [rbx + N_DATA + r14*8]
        inc r14
        mov rsi, r12
        mov rdx, r13
        call unchecked_f
        test eax, eax
        jz 5b
7:      mov eax, 1
        add rsp, 16
        LEAVE
8:      xor eax, eax
        add rsp, 16
        LEAVE
ENDF unchecked_f

# ---------------------------------------------------------------------
# what the comparisons and the masks ask

# is_word(exp, bounds) -> eax: python's is_word - exp, as an integer, is a
# word
FUNC is_word
        ENTER
        xor edx, edx
        call value_range
        mov rdi, rax
        mov rsi, rdx
        call vr_is_word
        LEAVE
ENDF is_word

# shift_sign(exp) -> eax: python's shift_sign - 1 if exp is a word (a shift
# left by it), -1 if minus it is (a shift right), 0 if it's 0, 2 for None
# (not known which)
FUNC shift_sign
        ENTER
        mov rbx, rdi
        cmp rdi, 1                      # 0 (python's exp == 0: False too)
        je 0f
        lea rax, [rip + sp_false]
        cmp rdi, rax
        jne 1f
0:      xor eax, eax
        LEAVE
1:      xor esi, esi
        xor edx, edx
        call value_range
        mov r12, rax
        mov r13, rdx
        mov rdi, rax
        mov rsi, rdx
        call vr_is_word
        test eax, eax
        jz 2f
        mov eax, 1
        LEAVE
2:      # -WORD_TOP <= lo and hi <= 0
        mov rdi, r12
        mov rsi, [rip + vr_neg_word_top_v]
        call int_cmp
        test eax, eax
        js 3f
        mov rdi, r13
        call int_sign
        cmp eax, 0
        jg 3f
        mov eax, -1
        LEAVE
3:      mov eax, 2
        LEAVE
ENDF shift_sign

# readable_mask(size, offset, shl) -> eax: python's readable_mask - a mask
# with these can be printed as what it is
FUNC readable_mask
        ENTER
        mov rbx, rsi
        mov r12, rdx
        xor esi, esi
        call is_word
        test eax, eax
        jz 9f
        mov rdi, rbx
        xor esi, esi
        call is_word
        test eax, eax
        jz 9f
        mov rdi, r12
        call shift_sign
        cmp eax, 2
        setne al
        movzx eax, al
        LEAVE
9:      xor eax, eax
        LEAVE
ENDF readable_mask

# proven_le(left, right) -> eax: python's proven_le - left <= right for any
# value of what they're made of
FUNC proven_le
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov rdi, rsi
        mov rsi, rbx
        call alg_sub_op
        mov rdi, rax
        xor esi, esi
        xor edx, edx
        call value_range
        mov rdi, rax
        call int_sign
        test eax, eax
        setns al
        movzx eax, al
        LEAVE
ENDF proven_le

# ---------------------------------------------------------------------
# the sets of opcodes

        OPSET_MEMBER vr_bool_ops, OP_BOOL
        OPSET_MEMBER vr_bool_ops, OP_ISZERO
        OPSET_MEMBER vr_bool_ops, OP_LT
        OPSET_MEMBER vr_bool_ops, OP_GT
        OPSET_MEMBER vr_bool_ops, OP_LE
        OPSET_MEMBER vr_bool_ops, OP_GE
        OPSET_MEMBER vr_bool_ops, OP_EQ
        OPSET_MEMBER vr_bool_ops, OP_SLT
        OPSET_MEMBER vr_bool_ops, OP_SGT
        OPSET_MEMBER vr_bool_ops, OP_SLE
        OPSET_MEMBER vr_bool_ops, OP_SGE
        OPSET_END vr_bool_ops, OP_COUNT

# is_bool_op(id) -> eax: one of python's BOOL_OPS (bool, iszero, lt...: 0 or 1)
        OPSET_FUNC is_bool_op, vr_bool_ops

        OPSET_MEMBER vr_bounded, OP_CALLDATASIZE
        OPSET_MEMBER vr_bounded, OP_RETURNDATASIZE
        OPSET_MEMBER vr_bounded, OP_CODESIZE
        OPSET_MEMBER vr_bounded, OP_MSIZE
        OPSET_MEMBER vr_bounded, OP_GAS
        OPSET_END vr_bounded, OP_COUNT

# is_bounded_symbol(id) -> eax: one of python's BOUNDED_SYMBOLS (64 bits)
        OPSET_FUNC is_bounded_symbol, vr_bounded

        OPSET_MEMBER vr_wide_ops, OP_CALL_DATA
        OPSET_MEMBER vr_wide_ops, OP_CODE_DATA
        OPSET_MEMBER vr_wide_ops, OP_EXT_CALL_RETURN_DATA
        OPSET_MEMBER vr_wide_ops, OP_DELEGATE_RETURN_DATA
        OPSET_MEMBER vr_wide_ops, OP_CALLCODE_RETURN_DATA
        OPSET_MEMBER vr_wide_ops, OP_STATICCALL_RETURN_DATA
        OPSET_END vr_wide_ops, OP_COUNT

        OPSET_MEMBER vr_inputs, OP_CD
        OPSET_MEMBER vr_inputs, OP_CALL_DATA
        OPSET_MEMBER vr_inputs, OP_EXT_CALL_RETURN_DATA
        OPSET_END vr_inputs, OP_COUNT

        OPSET_MEMBER vr_computed, OP_ADD
        OPSET_MEMBER vr_computed, OP_MUL
        OPSET_MEMBER vr_computed, OP_DIV
        OPSET_MEMBER vr_computed, OP_SDIV
        OPSET_MEMBER vr_computed, OP_MOD
        OPSET_MEMBER vr_computed, OP_SMOD
        OPSET_MEMBER vr_computed, OP_EXP
        OPSET_MEMBER vr_computed, OP_ADDMOD
        OPSET_MEMBER vr_computed, OP_MULMOD
        OPSET_MEMBER vr_computed, OP_SIGNEXTEND
        OPSET_MEMBER vr_computed, OP_AND
        OPSET_MEMBER vr_computed, OP_OR
        OPSET_MEMBER vr_computed, OP_XOR
        OPSET_MEMBER vr_computed, OP_NOT
        OPSET_MEMBER vr_computed, OP_MASK_SHL
        OPSET_MEMBER vr_computed, OP_SHL
        OPSET_MEMBER vr_computed, OP_SHR
        OPSET_MEMBER vr_computed, OP_SAR
        OPSET_MEMBER vr_computed, OP_BYTE
        OPSET_MEMBER vr_computed, OP_MIN
        OPSET_MEMBER vr_computed, OP_MAX
        OPSET_MEMBER vr_computed, OP_BYTES
        OPSET_MEMBER vr_computed, OP_DATA
        OPSET_END vr_computed, OP_COUNT

        .section .note.GNU-stack,"",@progbits
