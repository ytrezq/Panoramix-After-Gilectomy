# A trace run on concrete values (port of panoramix/runtrace.py): what
# storage.bytes_getter rests on - a function's trace run on values of what
# it reads, to check a rewrite no rule of the algebra proves.
#
# The entry points (r15 the context; a machine lives in its arena):
#
#   rt_machine_new(calldata, len, world, user) -> m
#       python's Machine(calldata, sload, bytes_length, bytes_data): the
#       callbacks are world's (RW_SLOAD, RW_BYTES_LENGTH, RW_BYTES_DATA,
#       each called (user, slot), slot an int value; RW_BYTES_DATA 0 is
#       bytes_data=None). sload and bytes_length return an int in
#       [0, 2^256), bytes_data rax: the bytes, rdx: their count. callvalue
#       is 0 (RM_CALLVALUE, a word), max_steps 20000 (RM_MAX_STEPS): set
#       them before a run. The calldata is the caller's, read in place.
#   rt_machine_reset(m, calldata, len)
#       a new Machine with the same callbacks, on this calldata: the steps,
#       the variables, the memory gone, the buffers kept - storage runs a
#       trace thousands of times, and a machine reused makes no garbage.
#   rt_ev(m, exp) -> value
#       python's m.ev(exp): an int in [0, 2^256). Its steps count toward
#       the run's, as python's do.
#   rt_run(m, trace) -> rax: how it ends ("return", "revert", "stop",
#       "invalid": the interned string), rdx: the length of its data, the
#       data at [m + RM_DATA] until the machine runs again
#       python's m.run(trace).
#   rt_keccak_word(v) -> value
#       keccak(v.to_bytes(32, "big")) for v in [0, 2^256): where storage
#       puts the words of a long bytes at the slot v (keccak.s has the
#       hash of any bytes).
#
# What python raises comes out as: Unsupported E_UNSUPPORTED, IndexError
# E_INDEX, TypeError E_TYPE, ValueError E_VALUE, OverflowError E_OVERFLOW
# (of a shift count past 2^63 too: pypy's, CPython's only past 30 * 2^61),
# RecursionError E_RECURSION, a Continue out of its loops E_CONTINUE, and
# what the callbacks throw. MemoryError is E_MEMORY: python's for what it
# can't allocate, here for a byte string or a shift past RT_BYTES_MAX
# bytes, where python goes on, slower and slower, to what the machine has
# (its own memory stops at 1 MiB: past that, a size is a contract's
# absurd one). A run makes RT_WORK_MAX bytes of byte strings at most, then
# Unsupported("steps"): python has no bound but its steps, and would hash
# for minutes. storage.bytes_tail catches Unsupported, ValueError,
# OverflowError, RecursionError (and KeyError); the others fail the
# storage's analysis, in python too.
#
# Python's ints are words here (four limbs, the least significant first,
# GMP's mpn order), made without a node: garbage at once in python, they
# would stay in the arena for every step of every run. The byte strings
# evb makes are a stack in the machine (the scratch), r14 the machine
# everywhere in this file.

.include "defs.inc"

.set RT_BYTES_MAX, 1 << 24      # a byte string (and the scratch): 16 MiB
.set RT_BITS_MAX, 8 * RT_BYTES_MAX  # a number made by a shift, in bits
.set RT_WORK_MAX, 1 << 28       # the bytes a run may make (python has no
                                # bound but the steps; this, past them)
.set RT_MEM_MAX, 1 << 20        # python's memory

.set ST_HALT, 1                 # run_line's: the run ended (python's Halt)
.set ST_CONTINUE, 2             #   a continue goes up (RM_JD, RM_SETVARS)

        .section .rodata
.Ls_bytes:      .asciz "bytes"
.Ls_sbytes:     .asciz "sbytes"
.Ls_steps:      .asciz "steps"
.Ls_mask:       .asciz "mask"
.Ls_var:        .asciz "var"
.Ls_mem:        .asciz "mem"
.Ls_call_data:  .asciz "call.data"
.Ls_sha3:       .asciz "sha3"
.Ls_width:      .asciz "width"
.Ls_memory:     .asciz "memory"
.Ls_setmem:     .asciz "setmem"
.Ls_setmem_size: .asciz "setmem of another size"
.Ls_while:      .asciz "while"
.Ls_continue:   .asciz "continue"
.Ls_none:       .asciz "None"
.Ls_expr:       .asciz "an expression of no opcode"
.Ls_index:      .asciz "tuple index out of range"
.Ls_iter:       .asciz "a trace that isn't iterable"
.Ls_unhashable: .asciz "unhashable type: 'list'"
.Ls_no_callback: .asciz "'NoneType' object is not callable"
.Ls_not_int:    .asciz "a callback's value isn't an int"
.Ls_unpack:     .asciz "not enough values to unpack"
.Ls_unpack5:    .asciz "a while of other than 5 elements"
.Ls_neg_shift:  .asciz "negative shift count"
.Ls_overflow:   .asciz "cannot fit 'int' into an index-sized integer"
.Ls_shift_count: .asciz "shift count too large"
.Ls_too_big:    .asciz "a byte string past runtrace's limit (python's MemoryError)"
.Ls_cont_out:   .asciz "a continue out of its loops"
        .text

# ---------------------------------------------------------------------
# errors (jumped to)

FUNC rt_unsup                           # rt_unsup(message)
        mov rsi, rdi
        mov edi, E_UNSUPPORTED
        jmp err_throw
ENDF rt_unsup

FUNC rt_unsup_steps
        lea rsi, [rip + .Ls_steps]
        mov edi, E_UNSUPPORTED
        jmp err_throw
ENDF rt_unsup_steps

FUNC rt_index_error
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_index]
        jmp err_throw
ENDF rt_index_error

FUNC rt_type_error                      # rt_type_error(message)
        mov rsi, rdi
        mov edi, E_TYPE
        jmp err_throw
ENDF rt_type_error

FUNC rt_value_error                     # rt_value_error(message)
        mov rsi, rdi
        mov edi, E_VALUE
        jmp err_throw
ENDF rt_value_error

FUNC rt_too_big
        mov edi, E_MEMORY
        lea rsi, [rip + .Ls_too_big]
        jmp err_throw
ENDF rt_too_big

FUNC rt_shift_overflow
        mov edi, E_OVERFLOW
        lea rsi, [rip + .Ls_shift_count]
        jmp err_throw
ENDF rt_shift_overflow

# rt_unsup_op(head): Unsupported(op), the op's text as the message
FUNC rt_unsup_op
        lea rsi, [rip + .Ls_none]
        test dil, 1
        jnz 1f
        test rdi, rdi
        jz 1f
        cmp dword ptr [rdi + N_KIND], K_STR
        jne 1f
        lea rsi, [rdi + N_DATA + 4]
1:      mov edi, E_UNSUPPORTED
        jmp err_throw
ENDF rt_unsup_op

# ---------------------------------------------------------------------
# words

# w_zero(w)
FUNC w_zero
        xor eax, eax
        mov [rdi], rax
        mov [rdi + 8], rax
        mov [rdi + 16], rax
        mov [rdi + 24], rax
        ret
ENDF w_zero

# w_set_u64(w, x)
FUNC w_set_u64
        mov [rdi], rsi
        xor eax, eax
        mov [rdi + 8], rax
        mov [rdi + 16], rax
        mov [rdi + 24], rax
        ret
ENDF w_set_u64

# w_copy(dst, src)
FUNC w_copy
        movdqu xmm0, [rsi]
        movdqu xmm1, [rsi + 16]
        movdqu [rdi], xmm0
        movdqu [rdi + 16], xmm1
        ret
ENDF w_copy

# w_is_zero(w) -> eax: 1 when it is 0
FUNC w_is_zero
        mov rax, [rdi]
        or rax, [rdi + 8]
        or rax, [rdi + 16]
        or rax, [rdi + 24]
        sete al
        movzx eax, al
        ret
ENDF w_is_zero

# w_le_u64(w, x) -> eax: 1 when w <= x
FUNC w_le_u64
        xor eax, eax
        mov rcx, [rdi + 8]
        or rcx, [rdi + 16]
        or rcx, [rdi + 24]
        jnz 1f
        cmp [rdi], rsi
        setbe al
1:      ret
ENDF w_le_u64

# w_cmp(a, b) -> eax: -1, 0, 1
FUNC w_cmp
        mov ecx, 3
1:      mov rax, [rdi + rcx*8]
        cmp rax, [rsi + rcx*8]
        jne 2f
        dec ecx
        jns 1b
        xor eax, eax
        ret
2:      sbb eax, eax
        or eax, 1
        ret
ENDF w_cmp

# w_scmp(a, b) -> eax: -1, 0, 1, as python's signed() of both
FUNC w_scmp
        mov rax, [rdi + 24]
        cmp rax, [rsi + 24]
        jne 3f
        mov ecx, 2
1:      mov rax, [rdi + rcx*8]
        cmp rax, [rsi + rcx*8]
        jne 2f
        dec ecx
        jns 1b
        xor eax, eax
        ret
2:      sbb eax, eax
        or eax, 1
        ret
3:      mov eax, 1
        mov ecx, -1
        cmovl eax, ecx
        ret
ENDF w_scmp

# w_add(dst, a, b)
FUNC w_add
        mov rax, [rsi]
        add rax, [rdx]
        mov [rdi], rax
        mov rax, [rsi + 8]
        adc rax, [rdx + 8]
        mov [rdi + 8], rax
        mov rax, [rsi + 16]
        adc rax, [rdx + 16]
        mov [rdi + 16], rax
        mov rax, [rsi + 24]
        adc rax, [rdx + 24]
        mov [rdi + 24], rax
        ret
ENDF w_add

# w_neg(dst, a): 2^256 - a
FUNC w_neg
        xor eax, eax
        sub rax, [rsi]
        mov [rdi], rax
        mov eax, 0
        sbb rax, [rsi + 8]
        mov [rdi + 8], rax
        mov eax, 0
        sbb rax, [rsi + 16]
        mov [rdi + 16], rax
        mov eax, 0
        sbb rax, [rsi + 24]
        mov [rdi + 24], rax
        ret
ENDF w_neg

# w_abs(dst, a) -> eax: 1 when a is negative (python's signed): dst its
# magnitude (2^255 for -2^255, a word still)
FUNC w_abs
        cmp qword ptr [rsi + 24], 0
        jl 1f
        call w_copy
        xor eax, eax
        ret
1:      call w_neg
        mov eax, 1
        ret
ENDF w_abs

# w_mul(dst, a, b): the product's low 256 bits
FUNC w_mul
        ENTER
        sub rsp, 64
        mov rbx, rdi
        mov rdi, rsp
        mov ecx, 4
        call __gmpn_mul_n@PLT
        mov rdi, rbx
        mov rsi, rsp
        call w_copy
        add rsp, 64
        LEAVE
ENDF w_mul

# w_divmod(q, r, a, b): q = a // b, r = a % b, for b not 0 (a q or an r
# of 0: not wanted)
FUNC w_divmod
        ENTER
        sub rsp, 96
        .set DM_Q, 0                    # 4 limbs at most (nn - dn + 1)
        .set DM_R, 32
        .set DM_B, 64
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov [rsp + DM_B], rcx
        xor eax, eax
        mov ecx, 8
1:      mov [rsp + rcx*8 - 8], rax
        dec ecx
        jnz 1b
        mov rcx, [rsp + DM_B]
        mov eax, 4                      # b's limbs (its top one not 0)
2:      cmp qword ptr [rcx + rax*8 - 8], 0
        jne 3f
        dec eax
        jnz 2b
3:      sub rsp, 16
        mov [rsp], rax                  # dn: the 7th argument
        lea rdi, [rsp + 16 + DM_Q]
        lea rsi, [rsp + 16 + DM_R]
        xor edx, edx
        mov r9, rcx                     # dp
        mov rcx, r13                    # np
        mov r8d, 4                      # nn
        call __gmpn_tdiv_qr@PLT
        add rsp, 16
        test rbx, rbx
        jz 4f
        mov rdi, rbx
        lea rsi, [rsp + DM_Q]
        call w_copy
4:      test r12, r12
        jz 5f
        mov rdi, r12
        lea rsi, [rsp + DM_R]
        call w_copy
5:      add rsp, 96
        LEAVE
ENDF w_divmod

# w_shl(dst, a, n): (a << n) mod 2^256, n unsigned
FUNC w_shl
        sub rsp, 72
        xor eax, eax
        cmp rdx, 256
        jae 1f
        mov [rsp], rax                  # 4 limbs of 0, then a: limb i of
        mov [rsp + 8], rax              # the result is shld of a's limbs
        mov [rsp + 16], rax             # i - k and i - k - 1
        mov [rsp + 24], rax
        movdqu xmm0, [rsi]
        movdqu xmm1, [rsi + 16]
        movdqu [rsp + 32], xmm0
        movdqu [rsp + 48], xmm1
        mov rcx, rdx
        and ecx, 63
        shr rdx, 6
        shl rdx, 3
        lea r8, [rsp + 32]
        sub r8, rdx
        .irp i, 0, 1, 2, 3
        mov rax, [r8 + 8*\i]
        mov r9, [r8 + 8*\i - 8]
        shld rax, r9, cl
        mov [rdi + 8*\i], rax
        .endr
        add rsp, 72
        ret
1:      mov [rdi], rax
        mov [rdi + 8], rax
        mov [rdi + 16], rax
        mov [rdi + 24], rax
        add rsp, 72
        ret
ENDF w_shl

# w_shr_fill(dst, a, n, fill): a >> n, the bits above it fill's (0, or
# -1 for an arithmetic shift), n unsigned
FUNC w_shr_fill
        sub rsp, 72
        cmp rdx, 256
        jae 1f
        movdqu xmm0, [rsi]
        movdqu xmm1, [rsi + 16]
        movdqu [rsp], xmm0
        movdqu [rsp + 16], xmm1
        mov [rsp + 32], rcx
        mov [rsp + 40], rcx
        mov [rsp + 48], rcx
        mov [rsp + 56], rcx
        mov rcx, rdx
        and ecx, 63
        shr rdx, 6
        lea r8, [rsp + rdx*8]
        .irp i, 0, 1, 2, 3
        mov rax, [r8 + 8*\i]
        mov r9, [r8 + 8*\i + 8]
        shrd rax, r9, cl
        mov [rdi + 8*\i], rax
        .endr
        add rsp, 72
        ret
1:      mov [rdi], rcx
        mov [rdi + 8], rcx
        mov [rdi + 16], rcx
        mov [rdi + 24], rcx
        add rsp, 72
        ret
ENDF w_shr_fill

# w_shr(dst, a, n) / w_sar(dst, a, n)
FUNC w_shr
        xor ecx, ecx
        jmp w_shr_fill
ENDF w_shr

FUNC w_sar
        mov rcx, [rsi + 24]
        sar rcx, 63
        jmp w_shr_fill
ENDF w_sar

# w_lowbits(dst, a, k): a & (2^k - 1), k unsigned
FUNC w_lowbits
        xor r8d, r8d
1:      mov rax, [rsi + r8*8]
        cmp rdx, 64
        jae 2f
        mov rcx, rdx
        mov r9, -1
        shl r9, cl
        not r9
        and rax, r9
        xor edx, edx                    # (nothing of the limbs above)
        jmp 3f
2:      sub rdx, 64
3:      mov [rdi + r8*8], rax
        inc r8d
        cmp r8d, 4
        jb 1b
        ret
ENDF w_lowbits

# w_exp(dst, a, b): pow(a, b, 2^256)
FUNC w_exp
        ENTER
        sub rsp, 96
        .set WE_R, 0
        .set WE_BASE, 32
        .set WE_E, 64
        mov rbx, rdi
        lea rdi, [rsp + WE_BASE]
        call w_copy
        lea rdi, [rsp + WE_E]
        mov rsi, rdx
        call w_copy
        lea rdi, [rsp + WE_R]
        mov esi, 1
        call w_set_u64
        mov r12d, 255                   # the exponent's top bit
1:      mov rax, r12
        shr rax, 6
        mov rax, [rsp + WE_E + rax*8]
        bt rax, r12
        jc 2f
        dec r12
        jns 1b
        jmp 4f
2:      lea rdi, [rsp + WE_R]           # square, times the base for a 1
        lea rsi, [rsp + WE_R]
        lea rdx, [rsp + WE_R]
        call w_mul
        mov rax, r12
        shr rax, 6
        mov rax, [rsp + WE_E + rax*8]
        bt rax, r12
        jnc 3f
        lea rdi, [rsp + WE_R]
        lea rsi, [rsp + WE_R]
        lea rdx, [rsp + WE_BASE]
        call w_mul
3:      dec r12
        jns 2b
4:      mov rdi, rbx
        lea rsi, [rsp + WE_R]
        call w_copy
        add rsp, 96
        LEAVE
ENDF w_exp

# w_from_value(w, v): python's `v & M` of an int v (two's complement for a
# negative one)
FUNC w_from_value
        test sil, 1
        jz 1f
        mov rax, rsi
        sar rax, 1
        mov [rdi], rax
        sar rax, 63
        mov [rdi + 8], rax
        mov [rdi + 16], rax
        mov [rdi + 24], rax
        ret
1:      push rbx
        mov rbx, rdi
        xor eax, eax
        mov [rdi], rax
        mov [rdi + 8], rax
        mov [rdi + 16], rax
        mov [rdi + 24], rax
        movsxd rcx, dword ptr [rsi + N_DATA + MPZ_SIZE]
        mov rdx, [rsi + N_DATA + MPZ_D]
        mov r8, rcx
        test r8, r8
        jns 2f
        neg r8
2:      cmp r8, 4                       # the low four limbs of |v|
        jbe 3f
        mov r8d, 4
3:      xor r9d, r9d
4:      cmp r9, r8
        jae 5f
        mov rax, [rdx + r9*8]
        mov [rbx + r9*8], rax
        inc r9
        jmp 4b
5:      test rcx, rcx
        jns 6f
        mov rdi, rbx
        mov rsi, rbx
        call w_neg
6:      pop rbx
        ret
ENDF w_from_value

# w_to_value(w) -> value
FUNC w_to_value
        mov rax, [rdi + 8]
        or rax, [rdi + 16]
        or rax, [rdi + 24]
        jnz 1f
        mov rax, [rdi]
        mov rcx, SMALL_MAX
        cmp rax, rcx
        ja 1f
        lea rax, [rax + rax + 1]
        ret
1:      ENTER
        sub rsp, 16
        mov rsi, rdi
        mov edx, 4                      # the limbs, the top one not 0
2:      cmp qword ptr [rsi + rdx*8 - 8], 0
        jne 3f
        dec edx
        jmp 2b
3:      mov rdi, rsp                    # a read-only mpz on the limbs
        call __gmpz_roinit_n@PLT
        mov rdi, rsp
        call mk_int_mpz
        add rsp, 16
        LEAVE
ENDF w_to_value

# w_small(w) -> rax: python's signed(w), saturated to 64 bits; rdx: 1
# when it was (the number isn't an index)
FUNC w_small
        xor edx, edx
        mov rax, [rdi]
        mov rcx, [rdi + 24]
        test rcx, rcx
        js 2f
        or rcx, [rdi + 8]
        or rcx, [rdi + 16]
        jnz 1f
        test rax, rax
        js 1f
        ret
1:      mov rax, 0x7fffffffffffffff
        mov edx, 1
        ret
2:      and rcx, [rdi + 8]
        and rcx, [rdi + 16]
        cmp rcx, -1
        jne 3f
        test rax, rax
        jns 3f
        ret
3:      mov rax, 0x8000000000000000
        mov edx, 1
        ret
ENDF w_small

# w_from_be(w, bytes, n): the number of n <= 32 big-endian bytes
FUNC w_from_be
        xor eax, eax
        mov [rdi], rax
        mov [rdi + 8], rax
        mov [rdi + 16], rax
        mov [rdi + 24], rax
        xor ecx, ecx
1:      cmp rcx, rdx
        jae 2f
        mov rax, rdx
        sub rax, rcx
        movzx eax, byte ptr [rsi + rax - 1]
        mov [rdi + rcx], al
        inc rcx
        jmp 1b
2:      ret
ENDF w_from_be

# rt_put_be(dst, n, src, avail): the low n bytes of the number whose
# little-endian bytes are the avail at src, big-endian (zeros first when
# it has fewer): python's (v & (2^(8n) - 1)).to_bytes(n, "big")
FUNC rt_put_be
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        cmp rcx, rsi
        cmova rcx, rsi
        push rcx
        push rcx
        mov rdx, r12
        sub rdx, rcx
        xor esi, esi
        call memset@PLT
        pop rcx
        pop rcx
        lea r8, [rbx + r12 - 1]
        xor eax, eax
1:      cmp rax, rcx
        jae 2f
        mov dl, [r13 + rax]
        mov [r8], dl
        dec r8
        inc rax
        jmp 1b
2:      LEAVE
ENDF rt_put_be

# ---------------------------------------------------------------------
# the machine

# rt_machine_new(calldata, len, world, user) -> m
FUNC rt_machine_new
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov r14, rcx
        mov edi, RM_SIZEOF
        call arena_alloc
        mov [rax + RM_CALLDATA], rbx
        mov [rax + RM_CDLEN], r12
        mov [rax + RM_WORLD], r13
        mov [rax + RM_USER], r14
        mov qword ptr [rax + RM_MAX_STEPS], 20000
        mov rbx, rax
        lea rdi, [rip + .Ls_bytes]
        call str_intern_c
        mov [rbx + RM_S_BYTES], rax
        lea rdi, [rip + .Ls_sbytes]
        call str_intern_c
        mov [rbx + RM_S_SBYTES], rax
        mov rax, rbx
        LEAVE
ENDF rt_machine_new

# rt_machine_reset(m, calldata, len)
FUNC rt_machine_reset
        ENTER
        mov rbx, rdi
        mov [rbx + RM_CALLDATA], rsi
        mov [rbx + RM_CDLEN], rdx
        xor eax, eax
        mov [rbx + RM_STEPS], rax
        mov [rbx + RM_VCOUNT], rax
        mov [rbx + RM_MEMLEN], rax
        mov [rbx + RM_SCRTOP], rax
        mov [rbx + RM_WORK], rax
        mov [rbx + RM_KIND], rax
        mov [rbx + RM_DATA], rax
        mov [rbx + RM_DLEN], rax
        mov rdi, [rbx + RM_VARS]
        test rdi, rdi
        jz 1f
        call emap_begin
1:      LEAVE
ENDF rt_machine_reset

# rt_ev(m, exp) -> value
FUNC rt_ev
        ENTER
        sub rsp, 32
        mov r14, rdi
        mov rdi, rsi
        mov rsi, rsp
        call rt_evw
        mov rdi, rsp
        call w_to_value
        add rsp, 32
        LEAVE
ENDF rt_ev

# rt_run(m, trace) -> rax: the kind, rdx: the data's length ([m + RM_DATA])
FUNC rt_run
        ENTER
        mov r14, rdi
        mov qword ptr [r14 + RM_SCRTOP], 0
        mov qword ptr [r14 + RM_DATA], 0
        mov qword ptr [r14 + RM_DLEN], 0
        mov rdi, rsi
        call rt_run_trace
        cmp eax, ST_CONTINUE
        je 2f
        test eax, eax
        jnz 1f
        LOADS rax, STOP                 # the trace ran to its end
        mov [r14 + RM_KIND], rax
        mov qword ptr [r14 + RM_DLEN], 0
1:      mov rax, [r14 + RM_SCR]         # (the data's offset, made its address)
        add [r14 + RM_DATA], rax
        mov rax, [r14 + RM_KIND]
        mov rdx, [r14 + RM_DLEN]
        LEAVE
2:      mov edi, E_CONTINUE
        lea rsi, [rip + .Ls_cont_out]
        call err_throw
ENDF rt_run

# rt_keccak_word(v) -> value: python's keccak(v.to_bytes(32, "big")) of
# an int v in [0, 2^256) - storage's base of the words of a long bytes
FUNC rt_keccak_word
        ENTER
        sub rsp, 64
        mov rsi, rdi
        mov rdi, rsp
        call w_from_value
        lea rdi, [rsp + 32]
        mov esi, 32
        mov rdx, rsp
        mov ecx, 32
        call rt_put_be
        lea rdi, [rsp + 32]
        mov esi, 32
        call keccak_value
        add rsp, 64
        LEAVE
ENDF rt_keccak_word

# rt_steps_line(): a step of python's run_trace or while (the limit:
# max_steps)
FUNC rt_steps_line
        mov rax, [r14 + RM_STEPS]
        inc rax
        mov [r14 + RM_STEPS], rax
        cmp rax, [r14 + RM_MAX_STEPS]
        jg rt_unsup_steps
        ret
ENDF rt_steps_line

# ---------------------------------------------------------------------
# the scratch, the memory, the calldata

# rt_scr_alloc(n) -> rax: the offset of n bytes pushed on the scratch
FUNC rt_scr_alloc
        mov rax, [r14 + RM_SCRTOP]
        mov ecx, RT_BYTES_MAX
        sub rcx, rax
        cmp rdi, rcx
        ja rt_too_big
        add [r14 + RM_WORK], rdi
        cmp qword ptr [r14 + RM_WORK], RT_WORK_MAX
        ja rt_unsup_steps
        lea rdx, [rax + rdi]
        cmp rdx, [r14 + RM_SCRCAP]
        ja 1f
        mov [r14 + RM_SCRTOP], rdx
        ret
1:      ENTER
        mov rbx, rdx                    # the new top
        mov r12, [r14 + RM_SCRCAP]
        add r12, r12
        cmp r12, rdx
        cmovb r12, rdx
        mov eax, 4096
        cmp r12, rax
        cmovb r12, rax
        mov eax, RT_BYTES_MAX
        cmp r12, rax
        cmova r12, rax
        mov rdi, r12
        call arena_alloc_raw
        mov r13, rax
        mov rdi, rax
        mov rsi, [r14 + RM_SCR]
        mov rdx, [r14 + RM_SCRTOP]
        call memcpy@PLT
        mov [r14 + RM_SCR], r13
        mov [r14 + RM_SCRCAP], r12
        mov rax, [r14 + RM_SCRTOP]
        mov [r14 + RM_SCRTOP], rbx
        LEAVE
ENDF rt_scr_alloc

# rt_mem_extend(n): python's self.mem made n bytes long at least, the new
# ones 0 (n <= RT_MEM_MAX)
FUNC rt_mem_extend
        cmp rdi, [r14 + RM_MEMLEN]
        ja 1f
        ret
1:      ENTER
        mov rbx, rdi
        cmp rbx, [r14 + RM_MEMCAP]
        jbe 2f
        mov r12, [r14 + RM_MEMCAP]
        add r12, r12
        cmp r12, rbx
        cmovb r12, rbx
        mov eax, 1024
        cmp r12, rax
        cmovb r12, rax
        mov rdi, r12
        call arena_alloc_raw
        mov r13, rax
        mov rdi, rax
        mov rsi, [r14 + RM_MEM]
        mov rdx, [r14 + RM_MEMLEN]
        call memcpy@PLT
        mov [r14 + RM_MEM], r13
        mov [r14 + RM_MEMCAP], r12
2:      mov rdi, [r14 + RM_MEM]         # (a buffer reused: what's past the
        add rdi, [r14 + RM_MEMLEN]      # length is a run before's)
        xor esi, esi
        mov rdx, rbx
        sub rdx, [r14 + RM_MEMLEN]
        call memset@PLT
        mov [r14 + RM_MEMLEN], rbx
        LEAVE
ENDF rt_mem_extend

# rt_mem_range(off, n) -> rax: off, the memory made as long as off + n -
# python's `if off + size > 2**20: raise Unsupported("memory")` (both
# words), then its extend
FUNC rt_mem_range
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov esi, RT_MEM_MAX
        call w_le_u64
        test eax, eax
        jz 1f
        mov rdi, r12
        mov esi, RT_MEM_MAX
        call w_le_u64
        test eax, eax
        jz 1f
        mov rdi, [rbx]
        add rdi, [r12]
        cmp rdi, RT_MEM_MAX
        ja 1f
        call rt_mem_extend
        mov rax, [rbx]
        LEAVE
1:      lea rdi, [rip + .Ls_memory]
        call rt_unsup
ENDF rt_mem_range

# rt_mwrite(off, src, n): python's mwrite (off a word)
FUNC rt_mwrite
        ENTER
        sub rsp, 32
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov rdi, rsp
        mov rsi, rdx
        call w_set_u64
        mov rdi, rbx
        mov rsi, rsp
        call rt_mem_range
        mov rdi, [r14 + RM_MEM]
        add rdi, rax
        mov rsi, r12
        mov rdx, r13
        call memcpy@PLT
        add rsp, 32
        LEAVE
ENDF rt_mwrite

# rt_cd_word(off, n, w): python's int.from_bytes(cdbytes(off, n), "big")
# for n <= 32 (off a u64)
FUNC rt_cd_word
        ENTER
        sub rsp, 32
        mov rbx, rdx
        mov r12, rsi
        xor eax, eax
        mov [rsp], rax
        mov [rsp + 8], rax
        mov [rsp + 16], rax
        mov [rsp + 24], rax
        mov rax, [r14 + RM_CDLEN]
        sub rax, rdi
        jbe 1f                          # past the calldata: zeros
        cmp rax, rsi
        cmova rax, rsi
        mov rsi, [r14 + RM_CALLDATA]
        add rsi, rdi
        mov rdi, rsp
        mov rdx, rax
        call memcpy@PLT
1:      mov rdi, rbx
        mov rsi, rsp
        mov rdx, r12
        call w_from_be
        add rsp, 32
        LEAVE
ENDF rt_cd_word

# rt_cdbytes(off, n) -> rax: the offset of python's cdbytes(off, n) pushed
# on the scratch, rdx: n (off and n words)
FUNC rt_cdbytes
        ENTER
        sub rsp, 32
        mov rbx, rdi
        mov r12, rsi
        xor r13d, r13d                  # the calldata's bytes in it
        mov rsi, [r14 + RM_CDLEN]
        test rsi, rsi
        jz 1f
        dec rsi
        call w_le_u64                   # off < len(calldata)
        test eax, eax
        jz 1f
        mov r13, [r14 + RM_CDLEN]
        sub r13, [rbx]
        mov rdi, r12
        mov rsi, r13
        call w_le_u64
        test eax, eax
        jz 1f
        mov r13, [r12]                  # n bytes there
1:      # b"\0" * (n - len(chunk)): an index-sized count, or OverflowError
        mov rax, [r12 + 8]
        or rax, [r12 + 16]
        or rax, [r12 + 24]
        jnz .Lcdb_overflow
        mov rax, [r12]
        sub rax, r13
        js .Lcdb_overflow
        mov rdi, [r12]
        call rt_scr_alloc
        mov [rsp], rax
        mov rdi, [r14 + RM_SCR]
        add rdi, rax
        test r13, r13
        jz 2f
        mov rsi, [r14 + RM_CALLDATA]
        add rsi, [rbx]
        mov rdx, r13
        call memcpy@PLT
        mov rdi, [r14 + RM_SCR]
        add rdi, [rsp]
2:      add rdi, r13
        xor esi, esi
        mov rdx, [r12]
        sub rdx, r13
        call memset@PLT
        mov rax, [rsp]
        mov rdx, [r12]
        add rsp, 32
        LEAVE
.Lcdb_overflow:
        mov edi, E_OVERFLOW
        lea rsi, [rip + .Ls_overflow]
        call err_throw
ENDF rt_cdbytes

# ---------------------------------------------------------------------
# the variables: python's dict, keyed by the values (hash-consed: equal
# ones are one pointer)

# rt_hashable(v) -> eax: python's hash(v) wouldn't raise (no list in it)
FUNC rt_hashable
        STACK_CHECK
        ENTER
        mov eax, 1
        test dil, 1
        jnz 9f
        test rdi, rdi
        jz 9f
        mov ecx, [rdi + N_KIND]
        cmp ecx, K_LIST
        je 8f
        cmp ecx, K_TUPLE
        jne 9f
        mov rbx, rdi
        xor r12d, r12d
1:      cmp r12d, [rbx + N_AUX]
        jae 7f
        mov rdi, [rbx + N_DATA + r12*8]
        call rt_hashable
        test eax, eax
        jz 9f
        inc r12d
        jmp 1b
7:      mov eax, 1
        LEAVE
8:      xor eax, eax
9:      LEAVE
ENDF rt_hashable

# rt_var_find(key) -> rax: the variable's entry, or 0 (TypeError for a key
# python can't hash)
FUNC rt_var_find
        ENTER
        mov rbx, rdi
        mov rdi, [r14 + RM_VARS]
        test rdi, rdi
        jz 1f
        mov rsi, rbx
        call emap_get
        test rax, rax
        jz 1f
        dec rax
        imul rax, rax, RM_ENTRY
        add rax, [r14 + RM_VENT]
        LEAVE
1:      mov rdi, rbx
        call rt_hashable
        test eax, eax
        jz 2f
        xor eax, eax
        LEAVE
2:      lea rdi, [rip + .Ls_unhashable]
        call rt_type_error
ENDF rt_var_find

# rt_var_put(key, w): vars[key] = w (a key found hashable)
FUNC rt_var_put
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov rdi, [r14 + RM_VARS]
        test rdi, rdi
        jnz 1f
        call emap_new
        mov [r14 + RM_VARS], rax
        mov rdi, rax
1:      mov rsi, rbx
        call emap_get
        test rax, rax
        jz 2f
        dec rax
        imul rdi, rax, RM_ENTRY
        add rdi, [r14 + RM_VENT]
        add rdi, 16
        mov rsi, r12
        call w_copy
        LEAVE
2:      mov r13, [r14 + RM_VCOUNT]      # a new one, after the others
        cmp r13, [r14 + RM_VCAP]
        jb 3f
        mov rax, [r14 + RM_VCAP]
        lea rax, [rax + rax + 8]
        push rax
        push rax
        imul rdi, rax, RM_ENTRY
        call arena_alloc_raw
        mov rdi, rax
        mov rsi, [r14 + RM_VENT]
        imul rdx, r13, RM_ENTRY
        mov [r14 + RM_VENT], rax
        call memcpy@PLT
        pop rax
        pop rax
        mov [r14 + RM_VCAP], rax
3:      imul rdi, r13, RM_ENTRY
        add rdi, [r14 + RM_VENT]
        mov [rdi], rbx
        add rdi, 16
        mov rsi, r12
        call w_copy
        inc qword ptr [r14 + RM_VCOUNT]
        mov rdi, [r14 + RM_VARS]
        mov rsi, rbx
        lea rdx, [r13 + 1]
        call emap_put
        LEAVE
ENDF rt_var_put

# rt_var_set(key, w): python's vars[key] = w
FUNC rt_var_set
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call rt_var_find
        test rax, rax
        jz 1f
        lea rdi, [rax + 16]
        mov rsi, r12
        call w_copy
        LEAVE
1:      mov rdi, rbx
        mov rsi, r12
        call rt_var_put
        LEAVE
ENDF rt_var_set

# rt_setvars(setvars, message): a while's or a continue's values, all at
# once: every ('setvar', key, exp) evaluated, then set (python's
# new = {...}; vars.update(new)); Unsupported(message) for another line
FUNC rt_setvars
        ENTER
        sub rsp, 64
        mov rbx, rdi
        mov [rsp + 32], rsi
        xor r13d, r13d                  # the entries made
        test bl, 1
        jnz .Lsv_iter
        test rbx, rbx
        jz .Lsv_iter
        mov eax, [rbx + N_KIND]
        cmp eax, K_STR
        je .Lsv_str
        sub eax, K_TUPLE
        cmp eax, K_LIST - K_TUPLE
        ja .Lsv_iter
        xor r12d, r12d
1:      cmp r12d, [rbx + N_AUX]
        jae 5f
        mov rdi, [rbx + N_DATA + r12*8]
        OPCODE_OF_RDI
        cmp eax, OP_SETVAR
        jne .Lsv_unsup
        cmp dword ptr [rdi + N_AUX], 3
        jb rt_index_error
        mov rdi, [rdi + N_DATA + 16]
        mov rsi, rsp
        call rt_evw
        mov rax, [rbx + N_DATA + r12*8]
        mov rdi, [rax + N_DATA + 8]
        mov [rsp + 40], rdi
        call rt_var_find                # (its hash)
        cmp r13, [r14 + RM_NEWCAP]
        jb 2f
        mov rax, [r14 + RM_NEWCAP]      # (as many as the steps allow)
        lea rax, [rax + rax + 8]
        mov [rsp + 48], rax
        imul rdi, rax, RM_ENTRY
        call arena_alloc_raw
        mov rdi, rax
        mov rsi, [r14 + RM_NEW]
        imul rdx, r13, RM_ENTRY
        mov [r14 + RM_NEW], rax
        call memcpy@PLT
        mov rax, [rsp + 48]
        mov [r14 + RM_NEWCAP], rax
2:      imul rdi, r13, RM_ENTRY
        add rdi, [r14 + RM_NEW]
        mov rax, [rsp + 40]
        mov [rdi], rax
        add rdi, 16
        mov rsi, rsp
        call w_copy
        inc r13
        inc r12d
        jmp 1b
5:      xor r12d, r12d                  # all of them set
6:      cmp r12, r13
        jae 7f
        imul rax, r12, RM_ENTRY
        add rax, [r14 + RM_NEW]
        mov rdi, [rax]
        lea rsi, [rax + 16]
        call rt_var_put
        inc r12
        jmp 6b
7:      add rsp, 64
        LEAVE
.Lsv_str:                               # its characters: none, or a line
        cmp dword ptr [rbx + N_DATA], 0 # that isn't a setvar
        je 7b
.Lsv_unsup:
        mov rdi, [rsp + 32]
        call rt_unsup
.Lsv_iter:
        lea rdi, [rip + .Ls_iter]
        call rt_type_error
ENDF rt_setvars


# ---------------------------------------------------------------------
# expressions

# rt_small(exp) -> rax: python's small(exp): an int as it is, else
# signed(ev(exp)) - saturated to 64 bits, far past the bounds that matter;
# rdx: 1 when it was (python's OverflowError where it is a shift count)
FUNC rt_small
        STACK_CHECK
        test dil, 1
        jz 1f
        mov rax, rdi
        sar rax, 1
        xor edx, edx
        ret
1:      test rdi, rdi
        jz 2f
        cmp dword ptr [rdi + N_KIND], K_INT
        jne 2f
        ENTER
        lea rbx, [rdi + N_DATA]
        mov rdi, rbx
        call __gmpz_fits_slong_p@PLT
        test eax, eax
        jz 3f
        mov rdi, rbx
        call __gmpz_get_si@PLT
        xor edx, edx
        LEAVE
3:      mov rax, 0x7fffffffffffffff
        cmp dword ptr [rbx + MPZ_SIZE], 0
        jg 4f
        mov rax, 0x8000000000000000
4:      mov edx, 1
        LEAVE
2:      ENTER
        sub rsp, 32
        mov rsi, rsp
        call rt_evw
        mov rdi, rsp
        call w_small
        add rsp, 32
        LEAVE
ENDF rt_small

# rt_apply_mask(out, v, size, off, shl): python's apply_mask of the word v
FUNC rt_apply_mask
        ENTER
        sub rsp, 48
        mov eax, 4096
        cmp rdx, rax                    # 0 <= size <= 4096 (unsigned)
        ja 8f
        lea r9, [rcx + 4096]            # abs(off) <= 4096, abs(shl) too
        cmp r9, 8192
        ja 8f
        lea r9, [r8 + 4096]
        cmp r9, 8192
        ja 8f
        mov rbx, rdi
        mov r12, rsi
        mov r13, r8
        test rcx, rcx
        jns 1f
        add rdx, rcx                    # an offset below 0: the size less
        xor ecx, ecx
1:      test rdx, rdx
        jns 2f
        xor edx, edx
2:      mov [rsp + 32], rcx
        add rdx, rcx                    # v's bits off to off + size: the
        mov rdi, rbx                    # ones below off + size, without
        mov rsi, r12                    # the ones below off
        call w_lowbits
        mov rdi, rsp
        mov rsi, r12
        mov rdx, [rsp + 32]
        call w_lowbits
        .irp i, 0, 8, 16, 24
        mov rax, [rsp + \i]
        xor [rbx + \i], rax
        .endr
        mov rdi, rbx
        mov rsi, rbx
        mov rdx, r13
        test r13, r13
        js 3f
        call w_shl
        add rsp, 48
        LEAVE
3:      neg rdx
        call w_shr
        add rsp, 48
        LEAVE
8:      lea rdi, [rip + .Ls_mask]
        call rt_unsup
ENDF rt_apply_mask

# rt_field(out, v, size, off, big): python's storage at a negative
# offset, `((v & ((1 << size) - 1)) << -off) & M` (big: size saturated,
# past 2^63) - its ValueError, and for a shift count past 2^63 pypy's
# OverflowError (CPython's only past 30 * 2^61, its MemoryError before),
# past RT_BITS_MAX bits MemoryError
FUNC rt_field
        ENTER
        mov rbx, rdi
        mov r12, rcx
        test rdx, rdx
        js 8f
        test r8, r8
        jnz 7f
        cmp rdx, RT_BITS_MAX
        ja 9f
        call w_lowbits
        mov rdi, rbx
        call w_is_zero
        test eax, eax
        jnz 1f                          # 0 << anything: 0, no memory
        mov rdx, r12
        neg rdx
        jo 7f                           # -off >= 2^63
        cmp rdx, RT_BITS_MAX
        ja 9f
        mov rdi, rbx
        mov rsi, rbx
        call w_shl
1:      LEAVE
7:      call rt_shift_overflow
8:      lea rdi, [rip + .Ls_neg_shift]
        call rt_value_error
9:      call rt_too_big
ENDF rt_field

# rt_world_call(which, w) -> the callback RW_<which>'s answer for the
# slot w (rax, and rdx for bytes_data's)
FUNC rt_world_call
        ENTER
        mov rbx, [r14 + RM_WORLD]
        mov rbx, [rbx + rdi]
        test rbx, rbx
        jz 1f
        mov rdi, rsi
        call w_to_value
        mov rdi, [r14 + RM_USER]
        mov rsi, rax
        call rbx
        LEAVE
1:      lea rdi, [rip + .Ls_no_callback]
        call rt_type_error
ENDF rt_world_call

# rt_world_word(which, w): w := the callback's value for the slot w
FUNC rt_world_word
        ENTER
        mov rbx, rsi
        call rt_world_call
        mov r12, rax
        mov rdi, rax
        call is_int
        test eax, eax
        jz 1f
        mov rdi, rbx
        mov rsi, r12
        call w_from_value
        LEAVE
1:      lea rdi, [rip + .Ls_not_int]
        call rt_type_error
ENDF rt_world_word

# rt_evw(exp, out): python's Machine.ev(exp), the word at out
FUNC rt_evw
        STACK_CHECK
        ENTER
        sub rsp, 128
        .set EV_A, 0
        .set EV_B, 32
        .set EV_T, 64
        .set EV_SIZE, 96                # (small's)
        .set EV_OFF, 104
        .set EV_SHL, 112
        .set EV_BIG, 120                # (the size's: past 2^63)
        mov rbx, rdi
        mov r12, rsi
        mov rax, [r14 + RM_STEPS]
        inc rax
        mov [r14 + RM_STEPS], rax
        mov rcx, [r14 + RM_MAX_STEPS]
        imul rcx, rcx, 20
        jno 1f
        mov rcx, 0x7fffffffffffffff
1:      cmp rax, rcx
        jg rt_unsup_steps
        test bl, 1
        jnz .Lev_int
        test rbx, rbx
        jz .Lev_expr
        mov eax, [rbx + N_KIND]
        cmp eax, K_INT
        je .Lev_int
        cmp eax, K_STR
        je .Lev_str
        cmp eax, K_TUPLE
        jne .Lev_expr
        cmp dword ptr [rbx + N_AUX], 0
        je .Lev_expr
        mov rdi, [rbx + N_DATA]         # the head: a string, or Unsupported
        test dil, 1                     # before anything is evaluated
        jnz .Lev_expr
        test rdi, rdi
        jz .Lev_expr
        cmp dword ptr [rdi + N_KIND], K_STR
        jne .Lev_expr
        mov eax, [rdi + N_AUX]
        test eax, STR_FLOAT
        jnz .Lev_expr
        cmp rdi, [r14 + RM_S_BYTES]
        je .Lev_bytes
        and eax, STR_ID_MASK
        JT_SWITCH ev, OP_COUNT, .Lev_generic
        JT_CASE ev, OP_VAR, .Lev_var
        JT_CASE ev, OP_LOC, .Lev_loc
        JT_CASE ev, OP_CD, .Lev_cd
        JT_CASE ev, OP_MASK_SHL, .Lev_mask_shl
        JT_CASE ev, OP_STORAGE, .Lev_storage
        JT_CASE ev, OP_MEM, .Lev_mem
        JT_CASE ev, OP_CALL_DATA, .Lev_call_data
        JT_CASE ev, OP_SHA3, .Lev_sha3
        JT_CASE ev, OP_ADD, .Lev_add
        JT_CASE ev, OP_MUL, .Lev_mul
        JT_CASE ev, OP_AND, .Lev_and
        JT_CASE ev, OP_OR, .Lev_or
        JT_CASE ev, OP_XOR, .Lev_xor
        JT_END ev, OP_COUNT, .Lev_generic

.Lev_done:
        add rsp, 128
        LEAVE

.Lev_int:
        mov rdi, r12
        mov rsi, rbx
        call w_from_value
        jmp .Lev_done

.Lev_str:
        LOADS rax, CALLDATASIZE
        cmp rbx, rax
        jne 1f
        mov rdi, r12
        mov rsi, [r14 + RM_CDLEN]
        call w_set_u64
        jmp .Lev_done
1:      LOADS rax, CALLVALUE
        cmp rbx, rax
        jne .Lev_expr
        mov rdi, r12
        lea rsi, [r14 + RM_CALLVALUE]
        call w_copy
        jmp .Lev_done

.Lev_expr:
        lea rdi, [rip + .Ls_expr]
        call rt_unsup

.Lev_bytes:                             # ('bytes', size, v): v
        cmp dword ptr [rbx + N_AUX], 3
        jb rt_index_error
        mov rdi, [rbx + N_DATA + 16]
        mov rsi, r12
        call rt_evw
        jmp .Lev_done

.Lev_var:
        cmp dword ptr [rbx + N_AUX], 2
        jb rt_index_error
        mov rdi, [rbx + N_DATA + 8]
        call rt_var_find
        test rax, rax
        jz 1f
        mov rdi, r12
        lea rsi, [rax + 16]
        call w_copy
        jmp .Lev_done
1:      lea rdi, [rip + .Ls_var]
        call rt_unsup

.Lev_loc:
        cmp dword ptr [rbx + N_AUX], 2
        jb rt_index_error
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, r12
        call rt_evw
        jmp .Lev_done

.Lev_cd:                                # the word of calldata there, below 2^32
        cmp dword ptr [rbx + N_AUX], 2
        jb rt_index_error
        mov rdi, [rbx + N_DATA + 8]
        lea rsi, [rsp + EV_A]
        call rt_evw
        lea rdi, [rsp + EV_A]
        mov esi, 0xffffffff
        call w_le_u64
        test eax, eax
        jz .Lev_zero
        mov rdi, [rsp + EV_A]
        mov esi, 32
        mov rdx, r12
        call rt_cd_word
        jmp .Lev_done
.Lev_zero:
        mov rdi, r12
        call w_zero
        jmp .Lev_done

.Lev_mask_shl:
        # size, off, shl = (small(x) for x in e[1:4]): the ones there, then
        # python's ValueError for fewer than three
        mov r13d, [rbx + N_AUX]
        cmp r13d, 2
        jb .Lev_unpack
        mov rdi, [rbx + N_DATA + 8]
        call rt_small
        mov [rsp + EV_SIZE], rax
        cmp r13d, 3
        jb .Lev_unpack
        mov rdi, [rbx + N_DATA + 16]
        call rt_small
        mov [rsp + EV_OFF], rax
        cmp r13d, 4
        jb .Lev_unpack
        mov rdi, [rbx + N_DATA + 24]
        call rt_small
        mov [rsp + EV_SHL], rax
        cmp r13d, 5
        jb rt_index_error
        mov rdi, [rbx + N_DATA + 32]
        lea rsi, [rsp + EV_A]
        call rt_evw
        mov rdi, r12
        lea rsi, [rsp + EV_A]
        mov rdx, [rsp + EV_SIZE]
        mov rcx, [rsp + EV_OFF]
        mov r8, [rsp + EV_SHL]
        call rt_apply_mask
        jmp .Lev_done
.Lev_unpack:
        lea rdi, [rip + .Ls_unpack]
        call rt_value_error

.Lev_storage:
        mov r13d, [rbx + N_AUX]
        cmp r13d, 2
        jb rt_index_error
        mov rdi, [rbx + N_DATA + 8]
        call rt_small
        mov [rsp + EV_SIZE], rax
        mov [rsp + EV_BIG], rdx
        cmp r13d, 3
        jb rt_index_error
        mov rdi, [rbx + N_DATA + 16]
        call rt_small
        mov [rsp + EV_OFF], rax
        cmp r13d, 4
        jb rt_index_error
        mov rdi, [rbx + N_DATA + 24]
        OPCODE_OF_RDI
        cmp eax, OP_LENGTH
        jne 1f
        cmp dword ptr [rdi + N_AUX], 2  # ('length', slot): bytes_length
        jb rt_index_error
        mov rdi, [rdi + N_DATA + 8]
        lea rsi, [rsp + EV_A]
        call rt_evw
        mov edi, RW_BYTES_LENGTH
        jmp 2f
1:      lea rsi, [rsp + EV_A]           # anything else: sload
        call rt_evw
        mov edi, RW_SLOAD
2:      lea rsi, [rsp + EV_A]
        call rt_world_word
        mov rcx, [rsp + EV_OFF]
        test rcx, rcx
        js 3f
        mov rdi, r12
        lea rsi, [rsp + EV_A]
        mov rdx, [rsp + EV_SIZE]
        mov r8, rcx
        neg r8
        call rt_apply_mask
        jmp .Lev_done
3:      mov rdi, r12                    # a field moved left
        lea rsi, [rsp + EV_A]
        mov rdx, [rsp + EV_SIZE]
        mov r8, [rsp + EV_BIG]
        call rt_field
        jmp .Lev_done

.Lev_mem:
        cmp dword ptr [rbx + N_AUX], 2
        jb rt_index_error
        mov rdi, [rbx + N_DATA + 8]
        OPCODE_OF_RDI
        cmp eax, OP_RANGE
        jne .Lev_unsup_mem
        mov r13, rdi
        cmp dword ptr [r13 + N_AUX], 2
        jb rt_index_error
        mov rdi, [r13 + N_DATA + 8]
        lea rsi, [rsp + EV_A]
        call rt_evw
        cmp dword ptr [r13 + N_AUX], 3
        jb rt_index_error
        mov rdi, [r13 + N_DATA + 16]
        lea rsi, [rsp + EV_B]
        call rt_evw
        lea rdi, [rsp + EV_B]
        mov esi, 32
        call w_le_u64
        test eax, eax
        jz .Lev_unsup_mem
        lea rdi, [rsp + EV_A]
        lea rsi, [rsp + EV_B]
        call rt_mem_range
        mov rsi, [r14 + RM_MEM]
        add rsi, rax
        mov rdi, r12
        mov rdx, [rsp + EV_B]
        call w_from_be
        jmp .Lev_done
.Lev_unsup_mem:
        lea rdi, [rip + .Ls_mem]
        call rt_unsup

.Lev_call_data:
        cmp dword ptr [rbx + N_AUX], 2
        jb rt_index_error
        mov rdi, [rbx + N_DATA + 8]
        lea rsi, [rsp + EV_A]
        call rt_evw
        cmp dword ptr [rbx + N_AUX], 3
        jb rt_index_error
        mov rdi, [rbx + N_DATA + 16]
        lea rsi, [rsp + EV_B]
        call rt_evw
        lea rdi, [rsp + EV_B]
        mov esi, 32
        call w_le_u64
        test eax, eax
        jz 1f
        lea rdi, [rsp + EV_A]
        mov esi, 0xffffffff
        call w_le_u64
        test eax, eax
        jz 1f
        mov rdi, [rsp + EV_A]
        mov rsi, [rsp + EV_B]
        mov rdx, r12
        call rt_cd_word
        jmp .Lev_done
1:      lea rdi, [rip + .Ls_call_data]
        call rt_unsup

.Lev_sha3:
        cmp dword ptr [rbx + N_AUX], 2
        jne 1f
        mov rdi, [rbx + N_DATA + 8]
        call rt_evb
        mov r13, rax
        mov rdi, [r14 + RM_SCR]
        add rdi, rax
        mov rsi, rdx
        lea rdx, [rsp + EV_A]
        call keccak256
        mov [r14 + RM_SCRTOP], r13      # (popped)
        mov rdi, r12
        lea rsi, [rsp + EV_A]
        mov edx, 32
        call w_from_be
        jmp .Lev_done
1:      lea rdi, [rip + .Ls_sha3]
        call rt_unsup

.Lev_add:
        mov rdi, r12
        call w_zero
        jmp .Lev_fold
.Lev_mul:
        mov rdi, r12
        mov esi, 1
        call w_set_u64
        jmp .Lev_fold
.Lev_and:
        mov rax, -1
        mov [r12], rax
        mov [r12 + 8], rax
        mov [r12 + 16], rax
        mov [r12 + 24], rax
        jmp .Lev_fold
.Lev_or:
.Lev_xor:
        mov rdi, r12
        call w_zero
.Lev_fold:                              # every argument into out, in order
        mov r13d, 1
1:      cmp r13d, [rbx + N_AUX]
        jae .Lev_done
        mov rdi, [rbx + N_DATA + r13*8]
        lea rsi, [rsp + EV_A]
        call rt_evw
        mov rax, [rbx + N_DATA]
        mov eax, [rax + N_AUX]
        and eax, STR_ID_MASK
        cmp eax, OP_ADD
        je 2f
        cmp eax, OP_MUL
        je 3f
        cmp eax, OP_AND
        je 4f
        cmp eax, OP_OR
        je 5f
        .irp i, 0, 8, 16, 24            # xor
        mov rax, [rsp + EV_A + \i]
        xor [r12 + \i], rax
        .endr
        jmp 6f
2:      mov rdi, r12
        mov rsi, r12
        lea rdx, [rsp + EV_A]
        call w_add
        jmp 6f
3:      mov rdi, r12
        mov rsi, r12
        lea rdx, [rsp + EV_A]
        call w_mul
        jmp 6f
4:      .irp i, 0, 8, 16, 24
        mov rax, [rsp + EV_A + \i]
        and [r12 + \i], rax
        .endr
        jmp 6f
5:      .irp i, 0, 8, 16, 24
        mov rax, [rsp + EV_A + \i]
        or [r12 + \i], rax
        .endr
6:      inc r13d
        jmp 1b

.Lev_generic:
        # all the arguments first, the first two kept; then the op of one
        # or two of them
        mov r13d, 1
1:      cmp r13d, [rbx + N_AUX]
        jae 3f
        lea rsi, [rsp + EV_T]
        cmp r13d, 2
        ja 2f
        lea rsi, [rsp + EV_A]
        jb 2f
        lea rsi, [rsp + EV_B]
2:      mov rdi, [rbx + N_DATA + r13*8]
        call rt_evw
        inc r13d
        jmp 1b
3:      mov rax, [rbx + N_DATA]
        mov eax, [rax + N_AUX]
        and eax, STR_ID_MASK
        mov ecx, [rbx + N_AUX]
        cmp ecx, 2
        je .Lev_unary
        cmp ecx, 3
        je .Lev_binary
.Lev_unsup_op:
        mov rdi, [rbx + N_DATA]
        call rt_unsup_op

.Lev_unary:
        cmp eax, OP_NOT
        je 1f
        cmp eax, OP_ISZERO
        je 2f
        cmp eax, OP_BOOL
        jne .Lev_unsup_op
        lea rdi, [rsp + EV_A]           # bool
        call w_is_zero
        xor eax, 1
        jmp .Lev_bit
1:      .irp i, 0, 8, 16, 24
        mov rax, [rsp + EV_A + \i]
        not rax
        mov [r12 + \i], rax
        .endr
        jmp .Lev_done
2:      lea rdi, [rsp + EV_A]
        call w_is_zero
.Lev_bit:                               # out := eax (0 or 1)
        mov rdi, r12
        mov esi, eax
        call w_set_u64
        jmp .Lev_done

.Lev_binary:
        JT_SWITCH ev2, OP_COUNT, .Lev_unsup_op
        JT_CASE ev2, OP_DIV, .Lev_div
        JT_CASE ev2, OP_MOD, .Lev_mod
        JT_CASE ev2, OP_SDIV, .Lev_sdiv
        JT_CASE ev2, OP_SMOD, .Lev_smod
        JT_CASE ev2, OP_EXP, .Lev_exp
        JT_CASE ev2, OP_SIGNEXTEND, .Lev_signextend
        JT_CASE ev2, OP_LT, .Lev_lt
        JT_CASE ev2, OP_GT, .Lev_gt
        JT_CASE ev2, OP_LE, .Lev_le
        JT_CASE ev2, OP_GE, .Lev_ge
        JT_CASE ev2, OP_EQ, .Lev_eq
        JT_CASE ev2, OP_SLT, .Lev_slt
        JT_CASE ev2, OP_SGT, .Lev_sgt
        JT_CASE ev2, OP_SLE, .Lev_sle
        JT_CASE ev2, OP_SGE, .Lev_sge
        JT_CASE ev2, OP_SHR, .Lev_shr
        JT_CASE ev2, OP_SHL, .Lev_shl
        JT_CASE ev2, OP_SAR, .Lev_sar
        JT_CASE ev2, OP_BYTE, .Lev_byte
        JT_CASE ev2, OP_MAX, .Lev_max
        JT_CASE ev2, OP_MIN, .Lev_min
        JT_END ev2, OP_COUNT, .Lev_unsup_op

.Lev_div:
        lea rdi, [rsp + EV_B]
        call w_is_zero
        test eax, eax
        jnz .Lev_zero
        mov rdi, r12
        xor esi, esi
        lea rdx, [rsp + EV_A]
        lea rcx, [rsp + EV_B]
        call w_divmod
        jmp .Lev_done
.Lev_mod:
        lea rdi, [rsp + EV_B]
        call w_is_zero
        test eax, eax
        jnz .Lev_zero
        xor edi, edi
        mov rsi, r12
        lea rdx, [rsp + EV_A]
        lea rcx, [rsp + EV_B]
        call w_divmod
        jmp .Lev_done
.Lev_sdiv:                              # |a| // |b|, negated when the signs differ
        lea rdi, [rsp + EV_B]
        call w_is_zero
        test eax, eax
        jnz .Lev_zero
        lea rdi, [rsp + EV_A]
        lea rsi, [rsp + EV_A]
        call w_abs
        mov r13d, eax
        lea rdi, [rsp + EV_B]
        lea rsi, [rsp + EV_B]
        call w_abs
        xor r13d, eax
        mov rdi, r12
        xor esi, esi
        lea rdx, [rsp + EV_A]
        lea rcx, [rsp + EV_B]
        call w_divmod
        jmp .Lev_signed
.Lev_smod:                              # |a| % |b|, of a's sign
        lea rdi, [rsp + EV_B]
        call w_is_zero
        test eax, eax
        jnz .Lev_zero
        lea rdi, [rsp + EV_A]
        lea rsi, [rsp + EV_A]
        call w_abs
        mov r13d, eax
        lea rdi, [rsp + EV_B]
        lea rsi, [rsp + EV_B]
        call w_abs
        xor edi, edi
        mov rsi, r12
        lea rdx, [rsp + EV_A]
        lea rcx, [rsp + EV_B]
        call w_divmod
.Lev_signed:                            # out negated when r13d is 1
        test r13d, r13d
        jz .Lev_done
        mov rdi, r12
        mov rsi, r12
        call w_neg
        jmp .Lev_done
.Lev_exp:
        mov rdi, r12
        lea rsi, [rsp + EV_A]
        lea rdx, [rsp + EV_B]
        call w_exp
        jmp .Lev_done
.Lev_signextend:
        lea rdi, [rsp + EV_A]
        mov esi, 30
        call w_le_u64
        test eax, eax
        jz .Lev_b                       # a >= 31: b as it is
        mov r13, [rsp + EV_A]
        lea r13, [r13*8 + 7]            # the sign's bit
        mov rdi, r12
        lea rsi, [rsp + EV_B]
        lea rdx, [r13 + 1]
        call w_lowbits
        mov rax, r13
        shr rax, 6
        mov rax, [r12 + rax*8]
        bt rax, r13
        jnc .Lev_done
        lea rdi, [rsp + EV_T]           # set: every bit above it too
        mov rax, -1
        mov [rdi], rax
        mov [rdi + 8], rax
        mov [rdi + 16], rax
        mov [rdi + 24], rax
        mov rsi, rdi
        lea rdx, [r13 + 1]
        call w_lowbits
        .irp i, 0, 8, 16, 24
        mov rax, [rsp + EV_T + \i]
        not rax
        or [r12 + \i], rax
        .endr
        jmp .Lev_done
.Lev_b:
        mov rdi, r12
        lea rsi, [rsp + EV_B]
        call w_copy
        jmp .Lev_done
.Lev_lt:
        call .Lev_cmp
        shr eax, 31                     # -1: 1
        jmp .Lev_bit
.Lev_gt:
        call .Lev_cmp
        cmp eax, 1
        sete al
        movzx eax, al
        jmp .Lev_bit
.Lev_le:
        call .Lev_cmp
        cmp eax, 1
        setne al
        movzx eax, al
        jmp .Lev_bit
.Lev_ge:
        call .Lev_cmp
        not eax
        shr eax, 31                     # -1: 0
        jmp .Lev_bit
.Lev_eq:
        call .Lev_cmp
        test eax, eax
        sete al
        movzx eax, al
        jmp .Lev_bit
.Lev_slt:
        call .Lev_scmp
        shr eax, 31
        jmp .Lev_bit
.Lev_sgt:
        call .Lev_scmp
        cmp eax, 1
        sete al
        movzx eax, al
        jmp .Lev_bit
.Lev_sle:
        call .Lev_scmp
        cmp eax, 1
        setne al
        movzx eax, al
        jmp .Lev_bit
.Lev_sge:
        call .Lev_scmp
        not eax
        shr eax, 31
        jmp .Lev_bit
.Lev_cmp:                               # (called: the frame 8 bytes up)
        lea rdi, [rsp + 8 + EV_A]
        lea rsi, [rsp + 8 + EV_B]
        jmp w_cmp
.Lev_scmp:
        lea rdi, [rsp + 8 + EV_A]
        lea rsi, [rsp + 8 + EV_B]
        jmp w_scmp
.Lev_shr:                               # b >> a, 0 for a >= 256
        call .Lev_shift
        mov rdi, r12
        lea rsi, [rsp + EV_B]
        call w_shr
        jmp .Lev_done
.Lev_shl:
        call .Lev_shift
        mov rdi, r12
        lea rsi, [rsp + EV_B]
        call w_shl
        jmp .Lev_done
.Lev_sar:
        call .Lev_shift
        mov rdi, r12
        lea rsi, [rsp + EV_B]
        call w_sar
        jmp .Lev_done
.Lev_shift:                             # rdx := a, 256 for anything past
        lea rdi, [rsp + 8 + EV_A]
        mov esi, 255
        call w_le_u64
        mov edx, 256
        test eax, eax
        jz 1f
        mov rdx, [rsp + 8 + EV_A]
1:      ret
.Lev_byte:                              # b's byte a, from the top
        lea rdi, [rsp + EV_A]
        mov esi, 31
        call w_le_u64
        test eax, eax
        jz .Lev_zero
        mov eax, 31
        sub rax, [rsp + EV_A]
        movzx esi, byte ptr [rsp + EV_B + rax]
        mov rdi, r12
        call w_set_u64
        jmp .Lev_done
.Lev_max:
        call .Lev_cmp
        test eax, eax
        jns .Lev_a
        jmp .Lev_b
.Lev_min:
        call .Lev_cmp
        test eax, eax
        jle .Lev_a
        jmp .Lev_b
.Lev_a:
        mov rdi, r12
        lea rsi, [rsp + EV_A]
        call w_copy
        jmp .Lev_done
ENDF rt_evw

# ---------------------------------------------------------------------
# byte strings: python's evb, its bytes pushed on the scratch

# rt_evb(exp) -> rax: the offset of the bytes of exp as an element of a
# data (pushed), rdx: their count
FUNC rt_evb
        STACK_CHECK
        ENTER
        sub rsp, 128
        .set EB_W, -160                 # a word (rbp-relative: the data's
        .set EB_N, -128                 # elements move rsp)
        .set EB_ERR, -96                # an error handler, 64 bytes; or the
        .set EB_I, -40                  # data's locals: the element,
        .set EB_J, -48                  #   the arr's content, its padding
        .set EB_MARK, -56               #   the scratch's top before it
        .set EB_POS, -64                #   an arr's offset in the result
        .set EB_TOTAL, -72
        .set EB_RES, -80                #   where the result is made
        .set EB_CUR, -88                #   (and the address it's at)
        mov rbx, rdi
        test bl, 1
        jnz .Leb_value
        test rbx, rbx
        jz .Leb_value
        cmp dword ptr [rbx + N_KIND], K_TUPLE
        jne .Leb_value
        cmp dword ptr [rbx + N_AUX], 0
        je .Leb_value
        mov rdi, [rbx + N_DATA]
        cmp rdi, [r14 + RM_S_BYTES]
        je .Leb_bytes
        cmp rdi, [r14 + RM_S_SBYTES]
        je .Leb_sbytes
        call str_id
        cmp eax, OP_DATA
        je .Leb_data
        cmp eax, OP_MEM
        je .Leb_mem
        cmp eax, OP_CALL_DATA
        je .Leb_call_data
.Leb_value:
        # a value: as wide as the memory model makes it (memloc.sizeof);
        # its AssertionError is Unsupported
        lea rdi, [rbp + EB_ERR]
        call err_catch
        test eax, eax
        jnz .Leb_width_err
        mov rdi, rbx
        call rt_width
        mov r12, rax
        call err_end
        test r12b, 1                    # an int of 0 to 256, a multiple of 8
        jz .Leb_width
        mov r13, r12
        sar r13, 1
        cmp r13, 256
        ja .Leb_width
        test r13b, 7
        jnz .Leb_width
        mov rdi, rbx
        call is_int
        test eax, eax
        jz 1f
        lea rdi, [rbp + EB_W]           # an int as it is
        mov rsi, rbx
        call w_from_value
        jmp 2f
1:      mov rdi, rbx
        lea rsi, [rbp + EB_W]
        call rt_evw
2:      shr r13, 3
        mov rdi, r13
        call rt_scr_alloc
        mov r12, rax
        mov rdi, [r14 + RM_SCR]
        add rdi, rax
        mov rsi, r13
        lea rdx, [rbp + EB_W]
        mov ecx, 32
        call rt_put_be
        mov rax, r12
        mov rdx, r13
        LEAVE_DYN
.Leb_width_err:
        cmp eax, E_ASSERT
        je .Leb_width
        mov edi, eax
        mov rsi, [r15 + CTX_ERR_MSG]
        call err_throw
.Leb_width:
        lea rdi, [rip + .Ls_width]
        call rt_unsup

.Leb_bytes:
        # ('bytes', n, v): n bytes of v - of an int as it is when it is
        # past 2^256; past 32 bytes, of an int >= 0 only
        cmp dword ptr [rbx + N_AUX], 2
        jb rt_index_error
        mov rdi, [rbx + N_DATA + 8]
        lea rsi, [rbp + EB_N]
        call rt_evw
        lea rdi, [rbp + EB_N]
        mov esi, 32
        call w_le_u64
        test eax, eax
        jnz 2f
        cmp dword ptr [rbx + N_AUX], 3
        jb rt_index_error
        mov rdi, [rbx + N_DATA + 16]
        test dil, 1
        jz 1f
        test rdi, rdi                   # a small int: >= 0
        jns 2f
        jmp 3f
1:      test rdi, rdi
        jz 3f
        cmp dword ptr [rdi + N_KIND], K_INT
        jne 3f
        cmp dword ptr [rdi + N_DATA + MPZ_SIZE], 0
        jg 2f
3:      lea rdi, [rip + .Ls_bytes]
        call rt_unsup
2:      cmp dword ptr [rbx + N_AUX], 3
        jb rt_index_error
        mov rdi, [rbx + N_DATA + 16]
        test dil, 1
        jnz 4f
        test rdi, rdi
        jz 4f
        cmp dword ptr [rdi + N_KIND], K_INT
        jne 4f
        cmp dword ptr [rdi + N_DATA + MPZ_SIZE], 4
        jle 4f
        mov r12, [rdi + N_DATA + MPZ_D] # >= 2^256: its own limbs
        mov r13d, [rdi + N_DATA + MPZ_SIZE]
        shl r13, 3
        jmp 5f
4:      lea rsi, [rbp + EB_W]
        call rt_evw
        lea r12, [rbp + EB_W]
        mov r13d, 32
5:      lea rdi, [rbp + EB_N]           # 1 << (8 * n): a shift count past
        mov rsi, (1 << 60) - 1          # 2^63 is pypy's OverflowError, past
        call w_le_u64                   # RT_BITS_MAX python's MemoryError
        test eax, eax
        jz rt_shift_overflow
        lea rdi, [rbp + EB_N]
        mov esi, RT_BYTES_MAX
        call w_le_u64
        test eax, eax
        jz rt_too_big
        mov rdi, [rbp + EB_N]
        call rt_scr_alloc
        mov rbx, rax
        mov rdi, [r14 + RM_SCR]
        add rdi, rax
        mov rsi, [rbp + EB_N]
        mov rdx, r12
        mov rcx, r13
        call rt_put_be
        mov rax, rbx
        mov rdx, [rbp + EB_N]
        LEAVE_DYN

.Leb_sbytes:
        # the bytes of the storage at a slot, when there's a bytes_data
        mov rax, [r14 + RM_WORLD]
        cmp qword ptr [rax + RW_BYTES_DATA], 0
        je .Leb_value
        cmp dword ptr [rbx + N_AUX], 2
        jb rt_index_error
        mov rdi, [rbx + N_DATA + 8]
        lea rsi, [rbp + EB_W]
        call rt_evw
        mov edi, RW_BYTES_DATA
        lea rsi, [rbp + EB_W]
        call rt_world_call
        mov r12, rax
        mov r13, rdx
        mov rdi, rdx
        call rt_scr_alloc
        mov rbx, rax
        mov rdi, [r14 + RM_SCR]
        add rdi, rax
        mov rsi, r12
        mov rdx, r13
        call memcpy@PLT
        mov rax, rbx
        mov rdx, r13
        LEAVE_DYN

.Leb_mem:
        cmp dword ptr [rbx + N_AUX], 2
        jb rt_index_error
        mov rdi, [rbx + N_DATA + 8]
        OPCODE_OF_RDI
        cmp eax, OP_RANGE
        jne 1f
        mov r13, rdi
        cmp dword ptr [r13 + N_AUX], 2
        jb rt_index_error
        mov rdi, [r13 + N_DATA + 8]
        lea rsi, [rbp + EB_W]
        call rt_evw
        cmp dword ptr [r13 + N_AUX], 3
        jb rt_index_error
        mov rdi, [r13 + N_DATA + 16]
        lea rsi, [rbp + EB_N]
        call rt_evw
        lea rdi, [rbp + EB_W]
        lea rsi, [rbp + EB_N]
        call rt_mem_range
        mov r12, rax
        mov rdi, [rbp + EB_N]
        call rt_scr_alloc
        mov rbx, rax
        mov rdi, [r14 + RM_SCR]
        add rdi, rax
        mov rsi, [r14 + RM_MEM]
        add rsi, r12
        mov rdx, [rbp + EB_N]
        call memcpy@PLT
        mov rax, rbx
        mov rdx, [rbp + EB_N]
        LEAVE_DYN
1:      lea rdi, [rip + .Ls_mem]
        call rt_unsup

.Leb_call_data:
        cmp dword ptr [rbx + N_AUX], 2
        jb rt_index_error
        mov rdi, [rbx + N_DATA + 8]
        lea rsi, [rbp + EB_W]
        call rt_evw
        cmp dword ptr [rbx + N_AUX], 3
        jb rt_index_error
        mov rdi, [rbx + N_DATA + 16]
        lea rsi, [rbp + EB_N]
        call rt_evw
        lea rdi, [rbp + EB_W]
        lea rsi, [rbp + EB_N]
        call rt_cdbytes
        LEAVE_DYN

.Leb_data:
        # ('data', el...): the elements one after the other, an ('arr',
        # len, content...) ABI-encoded: its offset there, its length and
        # content (padded to 32 bytes) after all of them. Each element is
        # pushed as it comes - an arr as a room for its length, its content
        # and padding, then its length (evaluated last, as in python) -,
        # then the result is made above them and moved down.
        mov r12d, [rbx + N_AUX]
        dec r12                         # the elements
        mov rax, [r14 + RM_SCRTOP]
        mov [rbp + EB_MARK], rax
        mov rax, r12
        shl rax, 4
        STACK_ALLOC rax                 # each one's (offset, length | ARR)
        mov r13, rsp
        mov qword ptr [rbp + EB_I], 0
.Leb_d_next:
        mov rax, [rbp + EB_I]
        cmp rax, r12
        jae .Leb_d_built
        mov rdi, [rbx + N_DATA + 8 + rax*8]
        OPCODE_OF_RDI
        cmp eax, OP_ARR
        je .Leb_d_arr
        call rt_evb
        mov rcx, [rbp + EB_I]
        shl rcx, 4
        mov [r13 + rcx], rax
        mov [r13 + rcx + 8], rdx
        jmp .Leb_d_inc
.Leb_d_arr:
        mov edi, 32
        call rt_scr_alloc
        mov rcx, [rbp + EB_I]
        shl rcx, 4
        mov [r13 + rcx], rax
        mov qword ptr [rbp + EB_J], 2
1:      mov rax, [rbp + EB_I]
        mov rdi, [rbx + N_DATA + 8 + rax*8]
        mov rcx, [rbp + EB_J]
        cmp ecx, [rdi + N_AUX]
        jae 2f
        mov rdi, [rdi + N_DATA + rcx*8]
        call rt_evb
        inc qword ptr [rbp + EB_J]
        jmp 1b
2:      mov rcx, [rbp + EB_I]           # the padding: -(its length) % 32
        shl rcx, 4
        mov rax, [r13 + rcx]
        add rax, 32
        sub rax, [r14 + RM_SCRTOP]
        and eax, 31
        mov [rbp + EB_J], rax
        mov rdi, rax
        call rt_scr_alloc
        mov rdi, [r14 + RM_SCR]
        add rdi, rax
        xor esi, esi
        mov rdx, [rbp + EB_J]
        call memset@PLT
        mov rax, [rbp + EB_I]           # its length, now
        mov rdi, [rbx + N_DATA + 8 + rax*8]
        cmp dword ptr [rdi + N_AUX], 2
        jb rt_index_error
        mov rdi, [rdi + N_DATA + 8]
        lea rsi, [rbp + EB_W]
        call rt_evw
        mov rcx, [rbp + EB_I]
        shl rcx, 4
        mov rdi, [r14 + RM_SCR]
        add rdi, [r13 + rcx]
        mov esi, 32
        lea rdx, [rbp + EB_W]
        mov ecx, 32
        call rt_put_be
        mov rcx, [rbp + EB_I]
        shl rcx, 4
        mov rax, [r14 + RM_SCRTOP]
        sub rax, [r13 + rcx]
        bts rax, 63                     # (an arr's)
        mov [r13 + rcx + 8], rax
.Leb_d_inc:
        inc qword ptr [rbp + EB_I]
        jmp .Leb_d_next
.Leb_d_built:
        xor eax, eax                    # the heads' size
        xor edx, edx                    # the tails'
        xor ecx, ecx
1:      cmp rcx, r12
        jae 3f
        mov rsi, rcx
        shl rsi, 4
        mov rsi, [r13 + rsi + 8]
        btr rsi, 63
        jc 2f
        add rax, rsi
        inc rcx
        jmp 1b
2:      add rax, 32
        add rdx, rsi
        inc rcx
        jmp 1b
3:      mov [rbp + EB_POS], rax         # the first tail's offset
        lea rdi, [rax + rdx]
        mov [rbp + EB_TOTAL], rdi
        call rt_scr_alloc
        mov [rbp + EB_RES], rax
        add rax, [r14 + RM_SCR]
        mov [rbp + EB_CUR], rax
        mov qword ptr [rbp + EB_I], 0
.Leb_d_heads:
        mov rcx, [rbp + EB_I]
        cmp rcx, r12
        jae .Leb_d_tails0
        shl rcx, 4
        mov rdx, [r13 + rcx + 8]
        btr rdx, 63
        jc 1f
        mov rdi, [rbp + EB_CUR]         # a head: its bytes
        mov rsi, [r14 + RM_SCR]
        add rsi, [r13 + rcx]
        add [rbp + EB_CUR], rdx
        call memcpy@PLT
        jmp 2f
1:      mov rdi, [rbp + EB_CUR]         # an arr: where its tail is
        add qword ptr [rbp + EB_CUR], 32
        mov rax, [rbp + EB_POS]
        add [rbp + EB_POS], rdx
        xor ecx, ecx
        mov [rdi], rcx
        mov [rdi + 8], rcx
        mov [rdi + 16], rcx
        bswap rax
        mov [rdi + 24], rax
2:      inc qword ptr [rbp + EB_I]
        jmp .Leb_d_heads
.Leb_d_tails0:
        mov qword ptr [rbp + EB_I], 0
.Leb_d_tails:
        mov rcx, [rbp + EB_I]
        cmp rcx, r12
        jae .Leb_d_move
        shl rcx, 4
        mov rdx, [r13 + rcx + 8]
        btr rdx, 63
        jnc 1f
        mov rdi, [rbp + EB_CUR]
        mov rsi, [r14 + RM_SCR]
        add rsi, [r13 + rcx]
        add [rbp + EB_CUR], rdx
        call memcpy@PLT
1:      inc qword ptr [rbp + EB_I]
        jmp .Leb_d_tails
.Leb_d_move:
        mov rdi, [r14 + RM_SCR]
        mov rsi, rdi
        add rdi, [rbp + EB_MARK]
        add rsi, [rbp + EB_RES]
        mov rdx, [rbp + EB_TOTAL]
        call memmove@PLT
        mov rax, [rbp + EB_MARK]
        mov rdx, [rbp + EB_TOTAL]
        lea rcx, [rax + rdx]
        mov [r14 + RM_SCRTOP], rcx
        LEAVE_DYN
ENDF rt_evb

# rt_width(exp) -> value: memloc.sizeof(exp), as python has it now, of
# the values evb takes (a data, a mem, a call.data are taken before)
FUNC rt_width
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE
        mov rbx, rdi
        PAT rsi, "('bytes', ':size', 'Any')"
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 1f
        mov rdi, [rsp]
        call rt_bits
        jmp 9f
1:      mov rdi, rbx
        PAT rsi, "('storage', ':size', '...')"
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 2f
        mov rax, [rsp]
        jmp 9f
2:      mov rdi, rbx
        PAT rsi, "('mask_shl', ':size', ':off', ':shl', 'Any')"
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 3f
        mov rdi, [rsp]                  # add_op(size, off, shl): of three
        mov rsi, [rsp + 8]              # small ints, their sum
        mov rdx, [rsp + 16]
        mov eax, edi
        and eax, esi
        and eax, edx
        test al, 1
        jz 21f
        sar rdi, 1
        sar rsi, 1
        sar rdx, 1
        add rdi, rsi
        add rdi, rdx
        call mk_int_i64
        jmp 9f
21:     call alg_add3
        jmp 9f
3:      mov rdi, rbx
        PAT rsi, "(':op', 'Any', ':size_bytes')"
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 4f
        mov rdi, [rsp]
        call str_id
        mov edi, eax
        call is_array_op
        test eax, eax
        jz 4f
        mov rdi, [rsp + 8]
        call rt_bits
        jmp 9f
4:      mov rdi, rbx
        PAT rsi, "('mem', ('range', 'Any', ':size_bytes'))"
        mov rdx, rsp
        call pat_match
        test eax, eax
        jnz 5f
        mov rdi, rbx
        PAT rsi, "('extcodecopy', 'Any', ('range', 'Any', ':size_bytes'))"
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 6f
5:      mov rdi, [rsp]
        call rt_bits
        jmp 9f
6:      mov rdi, rbx
        PAT rsi, "('mem', ':idx')"
        mov rdx, rsp
        call pat_match
        test eax, eax
        jnz 8f
        mov rdi, rbx
        PAT rsi, "('arr', ':l', 'Any')"
        mov rdx, rsp
        call pat_match
        test eax, eax
        jnz 8f
        mov rdi, rbx
        call is_int
        test eax, eax
        jz 7f
        mov rdi, rbx                    # past 2^256: the bytes it needs
        call int_gt_pow2_256
        test eax, eax
        jz 7f
        mov rdi, rbx
        call int_bit_length
        add rax, 7
        shr rax, 3
        TAG rax
        mov rdi, rax
        call rt_bits
        jmp 9f
7:      mov eax, (256 << 1) | 1
9:      add rsp, MATCH_BINDINGS_SIZE
        LEAVE
8:      mov edi, E_ASSERT
        lea rsi, [rip + .Ls_width]
        call err_throw
ENDF rt_width

# rt_bits(exp) -> value: algebra.bits, as python has it now - the bits of
# exp bytes, a sum's term by term, a term subtracted as minus its bits
FUNC rt_bits
        STACK_CHECK
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE
        mov rbx, rdi
        OPCODE_OF_RDI
        cmp eax, OP_ADD
        jne 3f
        mov r12d, [rbx + N_AUX]
        dec r12                         # add_op(*[bits(e) for e in exp[1:]])
        lea rax, [r12*8 + 15]
        and rax, -16
        STACK_ALLOC rax
        mov r13, rsp
        mov qword ptr [rbp - 40], 0
1:      mov rax, [rbp - 40]
        cmp rax, r12
        jae 2f
        mov rdi, [rbx + N_DATA + 8 + rax*8]
        call rt_bits
        mov rcx, [rbp - 40]
        mov [r13 + rcx*8], rax
        inc qword ptr [rbp - 40]
        jmp 1b
2:      mov rdi, r12
        mov rsi, r13
        call alg_add_n
        LEAVE_DYN
3:      mov rdi, rbx
        PAT rsi, "('mul', ':int:k', ':x')"
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 5f
        mov rdi, [rsp]
        call int_sign
        test eax, eax
        jns 5f
        mov r12, [rsp + 8]              # minus_op(bits(x if k == -1 else
        cmp qword ptr [rsp], -1         # mul_op(-k, x)))
        je 4f
        mov edi, 1
        mov rsi, [rsp]
        call int_sub
        mov rdi, rax
        mov rsi, r12
        call alg_mul2
        mov r12, rax
4:      mov rdi, r12
        call rt_bits
        mov rdi, rax
        call alg_minus_op
        LEAVE_DYN
5:      mov rdi, rbx
        call alg_bits
        LEAVE_DYN
ENDF rt_bits

# ---------------------------------------------------------------------
# statements

# rt_run_trace(trace) -> eax: 0, ST_HALT or ST_CONTINUE (python's
# run_trace, its Halt and Continue)
FUNC rt_run_trace
        STACK_CHECK
        ENTER
        mov rbx, rdi
        test bl, 1
        jnz .Lrt_iter
        test rbx, rbx
        jz .Lrt_iter
        mov eax, [rbx + N_KIND]
        cmp eax, K_STR
        je .Lrt_str
        sub eax, K_TUPLE
        cmp eax, K_LIST - K_TUPLE
        ja .Lrt_iter
        xor r12d, r12d
1:      cmp r12d, [rbx + N_AUX]
        jae 2f
        call rt_steps_line
        mov rdi, [rbx + N_DATA + r12*8]
        call rt_run_line
        test eax, eax
        jnz 3f
        inc r12d
        jmp 1b
2:      xor eax, eax
3:      LEAVE
.Lrt_str:                               # its characters: none, or a line of
        cmp dword ptr [rbx + N_DATA], 0 # no opcode
        je 2b
        call rt_steps_line
        lea rdi, [rip + .Ls_none]
        call rt_unsup
.Lrt_iter:
        lea rdi, [rip + .Ls_iter]
        call rt_type_error
ENDF rt_run_trace

# rt_run_line(line) -> eax: 0, ST_HALT or ST_CONTINUE
FUNC rt_run_line
        STACK_CHECK
        ENTER
        sub rsp, 96
        .set RL_A, 0
        .set RL_B, 32
        .set RL_T, 64
        mov rbx, rdi
        OPCODE_OF_RDI
        JT_SWITCH line, OP_COUNT, .Lrl_unsup
        JT_CASE line, OP_SETVAR, .Lrl_setvar
        JT_CASE line, OP_SETMEM, .Lrl_setmem
        JT_CASE line, OP_IF, .Lrl_if
        JT_CASE line, OP_WHILE, .Lrl_while
        JT_CASE line, OP_CONTINUE, .Lrl_continue
        JT_CASE line, OP_RETURN, .Lrl_return
        JT_CASE line, OP_REVERT, .Lrl_return
        JT_CASE line, OP_STOP, .Lrl_stop
        JT_CASE line, OP_INVALID, .Lrl_stop
        JT_END line, OP_COUNT, .Lrl_unsup
.Lrl_unsup:                             # Unsupported(opcode(line))
        xor edi, edi
        test bl, 1
        jnz 1f
        test rbx, rbx
        jz 1f
        cmp dword ptr [rbx + N_KIND], K_TUPLE
        jne 1f
        cmp dword ptr [rbx + N_AUX], 0
        je 1f
        mov rdi, [rbx + N_DATA]
1:      call rt_unsup_op
.Lrl_done:
        xor eax, eax
.Lrl_ret:
        add rsp, 96
        LEAVE

.Lrl_setvar:                            # the value first, then the key's hash
        cmp dword ptr [rbx + N_AUX], 3
        jb rt_index_error
        mov rdi, [rbx + N_DATA + 16]
        lea rsi, [rsp + RL_A]
        call rt_evw
        mov rdi, [rbx + N_DATA + 8]
        lea rsi, [rsp + RL_A]
        call rt_var_set
        jmp .Lrl_done

.Lrl_setmem:
        cmp dword ptr [rbx + N_AUX], 2
        jb rt_index_error
        mov rdi, [rbx + N_DATA + 8]
        OPCODE_OF_RDI
        cmp eax, OP_RANGE
        jne .Lrl_unsup_setmem
        mov r13, rdi
        cmp dword ptr [r13 + N_AUX], 2
        jb rt_index_error
        mov rdi, [r13 + N_DATA + 8]
        lea rsi, [rsp + RL_A]
        call rt_evw
        cmp dword ptr [r13 + N_AUX], 3
        jb rt_index_error
        mov rdi, [r13 + N_DATA + 16]
        lea rsi, [rsp + RL_B]
        call rt_evw
        cmp dword ptr [rbx + N_AUX], 3
        jb rt_index_error
        mov rdi, [rbx + N_DATA + 16]
        call rt_evb
        mov r12, rax                    # the data's offset
        mov r13, rdx                    # and length
        lea rdi, [rsp + RL_B]
        mov rsi, rdx
        call w_le_u64
        test eax, eax
        jz 1f
        cmp [rsp + RL_B], r13
        jne 1f
        mov rsi, [r14 + RM_SCR]         # as long as the range: as it is
        add rsi, r12
        lea rdi, [rsp + RL_A]
        mov rdx, r13
        call rt_mwrite
        jmp 4f
1:      # another length: of a number, its low n bytes (n <= 32)
        mov rdi, [rbx + N_DATA + 16]
        OPCODE_OF_RDI
        cmp eax, OP_DATA
        je .Lrl_unsup_size
        cmp eax, OP_MEM
        je .Lrl_unsup_size
        cmp eax, OP_CALL_DATA
        je .Lrl_unsup_size
        test eax, eax                   # (a tuple whose head isn't an
        jz 2f                           # opcode: maybe "bytes")
        jmp 3f
2:      test dil, 1
        jnz 3f
        test rdi, rdi
        jz 3f
        cmp dword ptr [rdi + N_KIND], K_TUPLE
        jne 3f
        cmp dword ptr [rdi + N_AUX], 0
        je 3f
        mov rax, [rdi + N_DATA]
        cmp rax, [r14 + RM_S_BYTES]
        je .Lrl_unsup_size
3:      lea rdi, [rsp + RL_B]
        mov esi, 32
        call w_le_u64
        test eax, eax
        jz .Lrl_unsup_size
        lea rdi, [rsp + RL_T]
        call w_zero
        mov rdx, [rsp + RL_B]           # n
        mov rsi, [r14 + RM_SCR]
        add rsi, r12
        lea rdi, [rsp + RL_T]
        cmp r13, rdx
        jb 31f
        add rsi, r13                    # the data's last n bytes
        sub rsi, rdx
        jmp 32f
31:     add rdi, rdx                    # or all of it, zeros before
        sub rdi, r13
        mov rdx, r13
32:     call memcpy@PLT
        lea rdi, [rsp + RL_A]
        lea rsi, [rsp + RL_T]
        mov rdx, [rsp + RL_B]
        call rt_mwrite
4:      mov [r14 + RM_SCRTOP], r12      # (popped)
        jmp .Lrl_done
.Lrl_unsup_setmem:
        lea rdi, [rip + .Ls_setmem]
        call rt_unsup
.Lrl_unsup_size:
        lea rdi, [rip + .Ls_setmem_size]
        call rt_unsup

.Lrl_if:
        mov r13d, [rbx + N_AUX]
        cmp r13d, 2
        jb rt_index_error
        mov rdi, [rbx + N_DATA + 8]
        lea rsi, [rsp + RL_A]
        call rt_evw
        lea rdi, [rsp + RL_A]
        call w_is_zero
        cmp r13d, 3
        jne 2f
        test eax, eax                   # ('if', cond, then)
        jnz .Lrl_done
        mov rdi, [rbx + N_DATA + 16]
        jmp 4f
2:      test eax, eax                   # ('if', cond, then, else)
        jnz 3f
        cmp r13d, 3
        jb rt_index_error
        mov rdi, [rbx + N_DATA + 16]
        jmp 4f
3:      cmp r13d, 4
        jb rt_index_error
        mov rdi, [rbx + N_DATA + 24]
4:      call rt_run_trace
        jmp .Lrl_ret

.Lrl_while:
        # ('while', cond, body, jd, setvars): the setvars at once, then the
        # body while cond holds - the body ending without a continue of
        # this loop leaves it
        cmp dword ptr [rbx + N_AUX], 5
        jne .Lrl_unpack
        mov rdi, [rbx + N_DATA + 32]
        lea rsi, [rip + .Ls_while]
        call rt_setvars
1:      mov rdi, [rbx + N_DATA + 8]
        lea rsi, [rsp + RL_A]
        call rt_evw
        lea rdi, [rsp + RL_A]
        call w_is_zero
        test eax, eax
        jnz .Lrl_done
        call rt_steps_line
        mov rdi, [rbx + N_DATA + 16]
        call rt_run_trace
        test eax, eax
        jz .Lrl_done
        cmp eax, ST_CONTINUE
        jne .Lrl_ret                    # a halt
        mov rdi, [r14 + RM_JD]
        mov rsi, [rbx + N_DATA + 24]
        call values_equal
        test eax, eax
        jz 2f
        mov rdi, [r14 + RM_SETVARS]
        lea rsi, [rip + .Ls_continue]
        call rt_setvars
        jmp 1b
2:      mov eax, ST_CONTINUE            # another loop's: up
        jmp .Lrl_ret
.Lrl_unpack:
        lea rdi, [rip + .Ls_unpack5]
        call rt_value_error

.Lrl_continue:
        cmp dword ptr [rbx + N_AUX], 3
        jb rt_index_error
        mov rax, [rbx + N_DATA + 8]
        mov [r14 + RM_JD], rax
        mov rax, [rbx + N_DATA + 16]
        mov [r14 + RM_SETVARS], rax
        mov eax, ST_CONTINUE
        jmp .Lrl_ret

.Lrl_return:                            # ('return', data): None for no data
        cmp dword ptr [rbx + N_AUX], 2
        jb rt_index_error
        mov rax, [rbx + N_DATA]
        mov [r14 + RM_KIND], rax
        xor eax, eax
        mov [r14 + RM_DATA], rax
        mov [r14 + RM_DLEN], rax
        mov rdi, [rbx + N_DATA + 8]
        lea rax, [rip + sp_none]
        cmp rdi, rax
        je 1f
        call rt_evb
        mov [r14 + RM_DATA], rax        # (an offset until rt_run is done)
        mov [r14 + RM_DLEN], rdx
1:      mov eax, ST_HALT
        jmp .Lrl_ret

.Lrl_stop:
        mov rax, [rbx + N_DATA]
        mov [r14 + RM_KIND], rax
        xor eax, eax
        mov [r14 + RM_DATA], rax
        mov [r14 + RM_DLEN], rax
        mov eax, ST_HALT
        jmp .Lrl_ret
ENDF rt_run_line

        .section .note.GNU-stack,"",@progbits
