# The variables of the storage (storage.py's Regroup and Storage): what's
# at every root slot, the names from the getters, the definitions, and the
# traces rewritten with the paths (rewrite_functions, rewrite_raw).

.include "defs.inc"
.include "storage.inc"

.set E_STFAIL, 40
.set E_ZERO_DIV, 42

# Regroup: the stores of the variables of a slot, not of the parts a store
# of the whole word was split in
.set RG_CLS, 0                  # od: (size, off, idx) -> class (sp_none: None)
.set RG_FIELDS, 8               # od: class -> [(off, end)] (layout)
.set RG_SIZEOF, 16

# what rg_store gives (python's (class, size, off, value, idx))
.set RS_CLS, 0
.set RS_SIZE, 8
.set RS_OFF, 16
.set RS_VAL, 24
.set RS_IDX, 32
.set RS_SIZEOF, 40

        .section .rodata
.Ls_logname:    .asciz "panoramix.storage"
.Ls_path_exc:   .asciz "storage path of %v"
.Ls_type_exc:   .asciz "storage type at %v"
.Ls_no_read:    .asciz "storage access %v printed as %v doesn't read as it"
        .text

# st_catch_all(code): what python's `except Exception` lets through (the
# time limit, python's TimeoutInterrupt) thrown again
FUNC st_catch_all
        cmp edi, E_TIMEOUT
        jne 1f
        mov rsi, [r15 + CTX_ERR_MSG]
        jmp err_throw
1:      ret
ENDF st_catch_all

# st_class_of(idx, lang) -> rax: slot_class(steps(parse(idx, lang))), 0
# (None) when it raises
FUNC st_class_of
        ENTER
        sub rsp, ERR_SIZEOF + 16
        mov rbx, rdi
        mov r12, rsi
        mov rdi, rsp
        call err_catch
        test eax, eax
        jnz 1f
        mov rdi, rbx
        mov rsi, r12
        call st_parse
        mov rdi, rax
        call st_steps
        mov rdi, rax
        call st_slot_class
        mov rbx, rax
        call err_end
        mov rax, rbx
        add rsp, ERR_SIZEOF + 16
        LEAVE
1:      mov edi, eax
        call st_catch_all
        xor eax, eax
        add rsp, ERR_SIZEOF + 16
        LEAVE
ENDF st_class_of

# st_functions_accesses(functions) -> od: find_accesses of every trace
FUNC st_functions_accesses
        ENTER
        mov rbx, rdi
        call od_new
        mov r12, rax
        xor r13d, r13d
1:      cmp r13, [rbx + VEC_LEN]
        jae 2f
        mov rax, [rbx + VEC_DATA]
        mov rax, [rax + r13*8]
        mov rdi, [rax + FN_TRACE]
        mov rsi, r12
        call st_find_accesses
        inc r13
        jmp 1b
2:      mov rax, r12
        LEAVE
ENDF st_functions_accesses

# st_od_group(od, key) -> rax: the vec of a key, made on demand (python's
# setdefault(key, []))
FUNC st_od_group
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call od_get
        test rax, rax
        jnz 1f
        call vec_new
        mov r13, rax
        mov rdi, rbx
        mov rsi, r12
        mov rdx, rax
        call od_put
        mov rax, r13
1:      LEAVE
ENDF st_od_group

# rg_new(functions, lang) -> rg: python's Regroup(functions, lang)
FUNC rg_new
        ENTER
        sub rsp, 48
        .set RN_ACC, 0
        .set RN_BY, 8
        .set RN_LANG, 16
        .set RN_RG, 24
        .set RN_I, 32
        mov [rsp + RN_LANG], rsi
        call st_functions_accesses
        mov [rsp + RN_ACC], rax
        mov edi, RG_SIZEOF
        call arena_alloc
        mov [rsp + RN_RG], rax
        mov rbx, rax
        call od_new
        mov [rbx + RG_CLS], rax
        call od_new
        mov [rsp + RN_BY], rax
        mov qword ptr [rsp + RN_I], 0
1:      mov rdi, [rsp + RN_ACC]
        call od_len
        cmp [rsp + RN_I], rax
        jae 3f
        mov rdi, [rsp + RN_ACC]
        mov rsi, [rsp + RN_I]
        call od_key
        mov r12, rax                    # (size, off, idx)
        mov rdi, [rsp + RN_ACC]
        mov rsi, [rsp + RN_I]
        call od_val
        mov r13, rax                    # written
        inc qword ptr [rsp + RN_I]
        mov rdi, [r12 + N_DATA + 16]
        mov rsi, [rsp + RN_LANG]
        call st_class_of
        mov r14, rax
        mov rdx, rax
        test rax, rax
        jnz 2f
        lea rdx, [rip + sp_none]
2:      mov rbx, [rsp + RN_RG]
        mov rdi, [rbx + RG_CLS]
        mov rsi, r12
        call od_put
        test r14, r14
        jz 1b
        mov rdi, [rsp + RN_BY]
        mov rsi, r14
        call st_od_group
        mov rbx, rax
        mov rdi, [r12 + N_DATA]
        mov rsi, [r12 + N_DATA + 8]
        mov rdx, r13
        call mk3
        mov rdi, rbx
        mov rsi, rax
        call vec_push
        jmp 1b
3:      # the fields of the classes whose accesses are all of known bits
        call od_new
        mov rbx, [rsp + RN_RG]
        mov [rbx + RG_FIELDS], rax
        mov qword ptr [rsp + RN_I], 0
4:      mov rdi, [rsp + RN_BY]
        call od_len
        cmp [rsp + RN_I], rax
        jae 8f
        mov rdi, [rsp + RN_BY]
        mov rsi, [rsp + RN_I]
        call od_key
        mov r12, rax
        mov rdi, [rsp + RN_BY]
        mov rsi, [rsp + RN_I]
        call od_val
        mov r13, rax
        inc qword ptr [rsp + RN_I]
        xor r14d, r14d
5:      cmp r14, [r13 + VEC_LEN]
        jae 6f
        mov rax, [r13 + VEC_DATA]
        mov rbx, [rax + r14*8]
        inc r14
        mov rdi, [rbx + N_DATA]
        call is_int
        test eax, eax
        jz 4b
        mov rdi, [rbx + N_DATA + 8]
        call is_int
        test eax, eax
        jz 4b
        jmp 5b
6:      mov rdi, r13
        call st_layout
        mov rbx, [rsp + RN_RG]
        mov rdi, [rbx + RG_FIELDS]
        mov rsi, r12
        mov rdx, rax
        call od_put
        jmp 4b
8:      mov rax, [rsp + RN_RG]
        add rsp, 48
        LEAVE
ENDF rg_new

# rg_store(rg, line, out) -> rax: python's Regroup.store - the class of a
# store of bits of a slot of known fields (out: RS_*), 0 (None) otherwise
FUNC rg_store
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov rdi, r12
        OP_N_CHECK OP_STORE, 5, 9f
        mov rdi, [r12 + N_DATA + 8]
        call is_int
        test eax, eax
        jz 9f
        mov rdi, [r12 + N_DATA + 16]
        call is_int
        test eax, eax
        jz 9f
        mov rdi, [r12 + N_DATA + 8]
        mov rsi, [r12 + N_DATA + 16]
        mov rdx, [r12 + N_DATA + 24]
        call mk3
        mov rdi, [rbx + RG_CLS]
        mov rsi, rax
        call od_get
        test rax, rax
        jz 9f
        lea rcx, [rip + sp_none]
        cmp rax, rcx
        je 9f
        mov r14, rax
        mov rdi, [rbx + RG_FIELDS]
        mov rsi, rax
        call od_get
        test rax, rax
        jz 9f
        mov [r13 + RS_CLS], r14
        mov rax, [r12 + N_DATA + 8]
        mov [r13 + RS_SIZE], rax
        mov rax, [r12 + N_DATA + 16]
        mov [r13 + RS_OFF], rax
        mov rax, [r12 + N_DATA + 24]
        mov [r13 + RS_IDX], rax
        mov rax, [r12 + N_DATA + 32]
        mov [r13 + RS_VAL], rax
        mov rax, r14
        LEAVE
9:      xor eax, eax
        LEAVE
ENDF rg_store

# rg_trace(rg, trace) -> trace: python's Regroup.trace
FUNC rg_trace
        STACK_CHECK
        ENTER
        sub rsp, 2*RS_SIZEOF + 48
        .set RT_RG, 2*RS_SIZEOF
        .set RT_LINES, 2*RS_SIZEOF + 8
        .set RT_RES, 2*RS_SIZEOF + 16
        .set RT_I, 2*RS_SIZEOF + 24
        .set RT_J, 2*RS_SIZEOF + 32
        mov [rsp + RT_RG], rdi
        mov rbx, rsi
        mov rdi, rsi
        call is_list
        test eax, eax
        jz .Lrt_asis
        # the lines, the traces in them done first
        call vec_new
        mov [rsp + RT_LINES], rax
        xor r12d, r12d
1:      cmp r12d, [rbx + N_AUX]
        jae 4f
        mov r13, [rbx + N_DATA + r12*8]
        inc r12d
        mov rdi, r13
        call is_tuple
        test eax, eax
        jz 3f
        mov edi, [r13 + N_AUX]
        shl rdi, 3
        jz 3f
        call arena_alloc_raw
        mov r14, rax
        xor ecx, ecx
2:      cmp ecx, [r13 + N_AUX]
        jae 21f
        mov rsi, [r13 + N_DATA + rcx*8]
        mov [r14 + rcx*8], rsi
        push rcx
        push rcx
        mov rdi, rsi
        call is_list
        pop rcx
        pop rcx
        test eax, eax
        jz 22f
        push rcx
        push rcx
        mov rdi, [rsp + 16 + RT_RG]
        mov rsi, [r13 + N_DATA + rcx*8]
        call rg_trace
        pop rcx
        pop rcx
        mov [r14 + rcx*8], rax
22:     inc ecx
        jmp 2b
21:     mov edi, [r13 + N_AUX]
        mov rsi, r14
        call mk_tuple
        mov r13, rax
3:      mov rdi, [rsp + RT_LINES]
        mov rsi, r13
        call vec_push
        jmp 1b
4:      call vec_new
        mov [rsp + RT_RES], rax
        mov qword ptr [rsp + RT_I], 0
5:      mov rax, [rsp + RT_LINES]
        mov rcx, [rsp + RT_I]
        cmp rcx, [rax + VEC_LEN]
        jae 9f
        mov rax, [rax + VEC_DATA]
        mov rdi, [rsp + RT_RG]
        mov rsi, [rax + rcx*8]
        mov rdx, rsp                    # first
        call rg_store
        mov r12, rax
        mov rax, [rsp + RT_I]
        inc rax
        mov [rsp + RT_J], rax
        test r12, r12
        jz 7f
6:      mov rax, [rsp + RT_LINES]       # the stores after it in the same slot
        mov rcx, [rsp + RT_J]
        cmp rcx, [rax + VEC_LEN]
        jae 61f
        mov rax, [rax + VEC_DATA]
        mov rdi, [rsp + RT_RG]
        mov rsi, [rax + rcx*8]
        lea rdx, [rsp + RS_SIZEOF]
        call rg_store
        test rax, rax
        jz 61f
        mov rax, [rsp + RS_SIZEOF + RS_IDX]
        cmp rax, [rsp + RS_IDX]
        jne 61f
        inc qword ptr [rsp + RT_J]
        jmp 6b
61:     mov rax, [rsp + RT_LINES]
        mov rcx, [rsp + RT_I]
        mov rax, [rax + VEC_DATA]
        lea rsi, [rax + rcx*8]
        mov rdx, [rsp + RT_J]
        sub rdx, rcx
        mov rdi, [rsp + RT_RG]
        mov rcx, [rsp + RT_RES]
        call rg_run
        jmp 8f
7:      mov rax, [rsp + RT_LINES]
        mov rcx, [rsp + RT_I]
        mov rax, [rax + VEC_DATA]
        mov rdi, [rsp + RT_RES]
        mov rsi, [rax + rcx*8]
        call vec_push
8:      mov rax, [rsp + RT_J]
        mov [rsp + RT_I], rax
        jmp 5b
9:      mov rdi, [rsp + RT_RES]
        call vec_to_list
        jmp .Lrt_ret
.Lrt_asis:
        mov rax, rbx
.Lrt_ret:
        add rsp, 2*RS_SIZEOF + 48
        LEAVE
ENDF rg_trace

# st_int_bits(v, shift, width) -> value: python's (v >> shift) % 2**width
FUNC st_int_bits
        ENTER
        mov rbx, rsi
        mov r12, rdx
        mov rsi, rdi
        lea rdi, [r15 + CTX_MPZ_R]
        call value_set_mpz
        mov rdi, rbx
        call int_to_i64
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, rdi
        mov rdx, rax
        call __gmpz_fdiv_q_2exp@PLT
        mov rdi, r12
        call int_to_i64
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, rdi
        mov rdx, rax
        call __gmpz_fdiv_r_2exp@PLT
        call arith_result
        LEAVE
ENDF st_int_bits

# st_int_shl(v, k) -> value: python's v << k (k >= 0, exact)
FUNC st_int_shl
        ENTER
        mov rbx, rsi
        mov rsi, rdi
        lea rdi, [r15 + CTX_MPZ_R]
        call value_set_mpz
        mov rdi, rbx
        call int_to_i64
        lea rdi, [r15 + CTX_MPZ_R]
        mov rsi, rdi
        mov rdx, rax
        call __gmpz_mul_2exp@PLT
        call arith_result
        LEAVE
ENDF st_int_shl

# rg_whole(fields, size, off) -> eax: python's run.whole - the bits
# [off, off + size) are whole variables of the fields
FUNC rg_whole
        ENTER
        sub rsp, 32
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov rdi, rdx
        mov rsi, r12
        call int_add
        mov [rsp], rax                  # off + size
        mov qword ptr [rsp + 8], 1      # the bits inside
        xor r14d, r14d
1:      cmp r14d, [rbx + N_AUX]
        jae 3f
        mov rax, [rbx + N_DATA + r14*8]
        mov [rsp + 16], rax             # (lo, hi)
        inc r14d
        mov rdi, [rax + N_DATA]         # lo < off + size and off < hi
        mov rsi, [rsp]
        call int_cmp
        cmp eax, -1
        jne 1b
        mov rax, [rsp + 16]
        mov rdi, r13
        mov rsi, [rax + N_DATA + 8]
        call int_cmp
        cmp eax, -1
        jne 1b
        mov rax, [rsp + 16]             # off <= lo and hi <= off + size
        mov rdi, r13
        mov rsi, [rax + N_DATA]
        call int_cmp
        cmp eax, 1
        je 8f
        mov rax, [rsp + 16]
        mov rdi, [rax + N_DATA + 8]
        mov rsi, [rsp]
        call int_cmp
        cmp eax, 1
        je 8f
        mov rax, [rsp + 16]
        mov rdi, [rax + N_DATA + 8]
        mov rsi, [rax + N_DATA]
        call int_sub
        mov rdi, [rsp + 8]
        mov rsi, rax
        call int_add
        mov [rsp + 8], rax
        jmp 1b
3:      mov rdi, [rsp + 8]
        mov rsi, r12
        call py_equal
        add rsp, 32
        LEAVE
8:      xor eax, eax                    # (all(...) is False: the sum isn't asked)
        add rsp, 32
        LEAVE
ENDF rg_whole

# rg_store_line(size, off, idx, val) -> ('store', size, off, idx, val)
FUNC rg_store_line
        mov r8, rcx
        mov rcx, rdx
        mov rdx, rsi
        mov rsi, rdi
        LOADS rdi, STORE
        jmp mk5
ENDF rg_store_line

# rg_line_off_lt(a, b, arg) -> eax: a[2] < b[2] (sorted(res, key=line[2]))
FUNC rg_line_off_lt
        ENTER
        mov rdi, [rdi + N_DATA + 16]
        mov rsi, [rsi + N_DATA + 16]
        call int_cmp
        cmp eax, -1
        sete al
        movzx eax, al
        LEAVE
ENDF rg_line_off_lt

# rg_size_offs(lines, n) -> vec: sorted (size, off) of store lines
FUNC rg_size_offs
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call vec_new
        mov r13, rax
        xor r14d, r14d
1:      cmp r14, r12
        jae 2f
        mov rax, [rbx + r14*8]
        inc r14
        mov rdi, [rax + N_DATA + 8]
        mov rsi, [rax + N_DATA + 16]
        call mk2
        mov rdi, r13
        mov rsi, rax
        call vec_push
        jmp 1b
2:      mov rdi, r13
        lea rsi, [rip + py_lt]
        xor edx, edx
        call py_sort
        mov rax, r13
        LEAVE
ENDF rg_size_offs

# rg_run(rg, lines, n, res): python's Regroup.run - stores one after the
# other in the same slot (n lines at lines), per variable of it, appended
# to the vec res
FUNC rg_run
        ENTER
        sub rsp, 160
        .set RR_RG, 0
        .set RR_LINES, 8
        .set RR_N, 16
        .set RR_RES, 24
        .set RR_RUN, 32                 # the stores' RS records (n * RS_SIZEOF)
        .set RR_CLS, 40
        .set RR_IDX, 48
        .set RR_FIELDS, 56
        .set RR_OUT, 64                 # the lines made
        .set RR_KEEP, 72                # the stores still to place (a vec of records)
        .set RR_PARTS, 80
        .set RR_I, 88
        .set RR_LO, 96
        .set RR_HI, 104
        .set RR_A, 112
        .set RR_B, 120
        .set RR_T, 128
        .set RR_U, 136
        mov [rsp + RR_RG], rdi
        mov [rsp + RR_LINES], rsi
        mov [rsp + RR_N], rdx
        mov [rsp + RR_RES], rcx
        imul rdi, rdx, RS_SIZEOF
        call arena_alloc
        mov [rsp + RR_RUN], rax
        xor r12d, r12d
1:      cmp r12, [rsp + RR_N]
        jae 2f
        mov rax, [rsp + RR_LINES]
        mov rsi, [rax + r12*8]
        imul rdx, r12, RS_SIZEOF
        add rdx, [rsp + RR_RUN]
        mov rdi, [rsp + RR_RG]
        call rg_store
        inc r12
        jmp 1b
2:      mov rax, [rsp + RR_RUN]
        mov rcx, [rax + RS_CLS]
        mov [rsp + RR_CLS], rcx
        mov rcx, [rax + RS_IDX]
        mov [rsp + RR_IDX], rcx
        # parts of different bits
        call vec_new
        mov rbx, rax
        xor r12d, r12d
3:      cmp r12, [rsp + RR_N]
        jae 4f
        imul r13, r12, RS_SIZEOF
        add r13, [rsp + RR_RUN]
        inc r12
        mov rdi, [r13 + RS_OFF]
        mov rsi, [r13 + RS_SIZE]
        call int_add
        mov rsi, rax
        mov rdi, [r13 + RS_OFF]
        call mk2
        mov rdi, rbx
        mov rsi, rax
        call vec_push
        jmp 3b
4:      mov rdi, rbx
        lea rsi, [rip + py_lt]
        xor edx, edx
        call py_sort
        mov r12d, 1
5:      cmp r12, [rbx + VEC_LEN]
        jae 6f
        mov rax, [rbx + VEC_DATA]
        mov rcx, [rax + r12*8 - 8]
        mov rdx, [rax + r12*8]
        inc r12
        mov rdi, [rcx + N_DATA + 8]     # a[1] > b[0]: overlapping
        mov rsi, [rdx + N_DATA]
        call int_cmp
        cmp eax, 1
        je .Lrr_asis
        jmp 5b
6:      # their values not reading the slot, nor another of the same place
        xor r12d, r12d
7:      cmp r12, [rsp + RR_N]
        jae 9f
        imul r13, r12, RS_SIZEOF
        add r13, [rsp + RR_RUN]
        inc r12
        call od_new
        mov r14, rax
        mov rdi, [r13 + RS_VAL]
        mov rsi, r14
        call st_find_accesses
        xor ebx, ebx
8:      mov rdi, r14
        call od_len
        cmp rbx, rax
        jae 7b
        mov rdi, r14
        mov rsi, rbx
        call od_key
        inc rbx
        mov rsi, rax
        mov rax, [rsp + RR_RG]
        mov rdi, [rax + RG_CLS]
        call od_get
        test rax, rax
        jz .Lrr_asis
        lea rcx, [rip + sp_none]
        cmp rax, rcx
        je .Lrr_asis
        cmp rax, [rsp + RR_CLS]
        je .Lrr_asis
        jmp 8b
9:      mov rax, [rsp + RR_RG]
        mov rdi, [rax + RG_FIELDS]
        mov rsi, [rsp + RR_CLS]
        call od_get
        mov [rsp + RR_FIELDS], rax
        # a number in whole variables (0 in the word: a delete) stays one
        call vec_new
        mov [rsp + RR_OUT], rax
        call vec_new
        mov [rsp + RR_KEEP], rax
        xor r12d, r12d
10:     cmp r12, [rsp + RR_N]
        jae 12f
        imul r13, r12, RS_SIZEOF
        add r13, [rsp + RR_RUN]
        inc r12
        mov rdi, [r13 + RS_VAL]
        call is_int
        test eax, eax
        jz 11f
        mov rdi, [rsp + RR_FIELDS]
        mov rsi, [r13 + RS_SIZE]
        mov rdx, [r13 + RS_OFF]
        call rg_whole
        test eax, eax
        jz 11f
        mov rdi, [r13 + RS_SIZE]
        mov rsi, [r13 + RS_OFF]
        mov rdx, [rsp + RR_IDX]
        mov rcx, [r13 + RS_VAL]
        call rg_store_line
        mov rdi, [rsp + RR_OUT]
        mov rsi, rax
        call vec_push
        jmp 10b
11:     mov rdi, [rsp + RR_KEEP]
        mov rsi, r13
        call vec_push
        jmp 10b
12:     # each variable: the parts of the stores in it
        mov qword ptr [rsp + RR_I], 0
.Lrr_field:
        mov rax, [rsp + RR_FIELDS]
        mov rcx, [rsp + RR_I]
        cmp ecx, [rax + N_AUX]
        jae .Lrr_check
        mov rax, [rax + N_DATA + rcx*8]
        inc qword ptr [rsp + RR_I]
        mov rcx, [rax + N_DATA]
        mov [rsp + RR_LO], rcx
        mov rcx, [rax + N_DATA + 8]
        mov [rsp + RR_HI], rcx
        call vec_new
        mov [rsp + RR_PARTS], rax
        xor r12d, r12d
1:      mov rax, [rsp + RR_KEEP]
        cmp r12, [rax + VEC_LEN]
        jae 5f
        mov rax, [rax + VEC_DATA]
        mov r13, [rax + r12*8]
        inc r12
        mov rdi, [rsp + RR_LO]          # a, b = max(lo, off), min(hi, off + size)
        mov rsi, [r13 + RS_OFF]
        call int_max
        mov [rsp + RR_A], rax
        mov rdi, [r13 + RS_OFF]
        mov rsi, [r13 + RS_SIZE]
        call int_add
        mov [rsp + RR_T], rax           # off + size
        mov rdi, [rsp + RR_HI]
        mov rsi, rax
        call int_min
        mov [rsp + RR_B], rax
        mov rdi, [rsp + RR_A]
        mov rsi, rax
        call int_cmp
        cmp eax, -1
        jne 1b
        mov rdi, [r13 + RS_VAL]
        call is_int
        test eax, eax
        jz 3f
        # a number's bits in this variable
        mov rdi, [rsp + RR_A]
        mov rsi, [r13 + RS_OFF]
        call int_sub
        mov r14, rax
        mov rdi, [rsp + RR_B]
        mov rsi, [rsp + RR_A]
        call int_sub
        mov [rsp + RR_U], rax           # b - a
        mov rdi, [r13 + RS_VAL]
        mov rsi, r14
        mov rdx, rax
        call st_int_bits
        mov rcx, rax
        mov rdi, [rsp + RR_U]
        mov rsi, [rsp + RR_A]
        mov rdx, rcx
        call mk3
        mov rdi, [rsp + RR_PARTS]
        mov rsi, rax
        call vec_push
        jmp 1b
3:      mov rax, [rsp + RR_A]           # (a, b) == (off, off + size): the
        cmp rax, [r13 + RS_OFF]         # value whole
        jne .Lrr_asis
        mov rax, [rsp + RR_B]
        cmp rax, [rsp + RR_T]
        jne .Lrr_asis
        mov rdi, [r13 + RS_SIZE]
        mov rsi, [r13 + RS_OFF]
        mov rdx, [r13 + RS_VAL]
        call mk3
        mov rdi, [rsp + RR_PARTS]
        mov rsi, rax
        call vec_push
        jmp 1b
5:      mov rax, [rsp + RR_PARTS]
        cmp qword ptr [rax + VEC_LEN], 0
        je .Lrr_field
        # covered: their sizes sum to the variable's
        mov qword ptr [rsp + RR_T], 1
        mov qword ptr [rsp + RR_U], 0   # the parts that aren't numbers
        xor r12d, r12d
6:      mov rax, [rsp + RR_PARTS]
        cmp r12, [rax + VEC_LEN]
        jae 7f
        mov rax, [rax + VEC_DATA]
        mov r13, [rax + r12*8]
        inc r12
        mov rdi, [rsp + RR_T]
        mov rsi, [r13 + N_DATA]
        call int_add
        mov [rsp + RR_T], rax
        mov rdi, [r13 + N_DATA + 16]
        call is_int
        test eax, eax
        jnz 6b
        mov rax, [rsp + RR_U]
        test rax, rax
        jnz 61f
        mov [rsp + RR_U], r13           # (the first other)
        jmp 6b
61:     mov qword ptr [rsp + RR_U], -1  # (more than one)
        jmp 6b
7:      mov rdi, [rsp + RR_HI]
        mov rsi, [rsp + RR_LO]
        call int_sub
        mov r14, rax                    # hi - lo
        mov rdi, [rsp + RR_T]
        mov rsi, rax
        call py_equal
        test eax, eax
        jz .Lrr_parts
        cmp qword ptr [rsp + RR_U], 0
        jne 8f
        # numbers only: one number
        mov qword ptr [rsp + RR_T], 1
        xor r12d, r12d
71:     mov rax, [rsp + RR_PARTS]
        cmp r12, [rax + VEC_LEN]
        jae 72f
        mov rax, [rax + VEC_DATA]
        mov r13, [rax + r12*8]
        inc r12
        mov rdi, [r13 + N_DATA + 8]     # val << (off - lo)
        mov rsi, [rsp + RR_LO]
        call int_sub
        mov rdi, [r13 + N_DATA + 16]
        mov rsi, rax
        call st_int_shl
        mov rdi, [rsp + RR_T]
        mov rsi, rax
        call int_add
        mov [rsp + RR_T], rax
        jmp 71b
72:     mov rdi, r14
        mov rsi, [rsp + RR_LO]
        mov rdx, [rsp + RR_T]
        call .Lrr_one_part
        jmp .Lrr_parts
8:      # one value at the low end, as wide as the variable, zeros above
        mov r13, [rsp + RR_U]
        cmp r13, -1
        je .Lrr_parts
        mov rax, [r13 + N_DATA + 8]
        cmp rax, [rsp + RR_LO]
        jne .Lrr_parts
        mov rdi, [r13 + N_DATA + 16]
        call value_bits
        mov rdi, rax
        mov rsi, [r13 + N_DATA]
        call int_cmp
        cmp eax, 1
        je .Lrr_parts
        xor r12d, r12d
81:     mov rax, [rsp + RR_PARTS]
        cmp r12, [rax + VEC_LEN]
        jae 82f
        mov rax, [rax + VEC_DATA]
        mov rcx, [rax + r12*8]
        inc r12
        mov rdi, [rcx + N_DATA + 16]
        call is_int
        test eax, eax
        jz 81b
        mov rax, [rsp + RR_PARTS]
        mov rax, [rax + VEC_DATA]
        mov rcx, [rax + r12*8 - 8]
        cmp qword ptr [rcx + N_DATA + 16], 1
        jne .Lrr_parts
        jmp 81b
82:     mov rdi, r14
        mov rsi, [rsp + RR_LO]
        mov rax, [rsp + RR_U]
        mov rdx, [rax + N_DATA + 16]
        call .Lrr_one_part
.Lrr_parts:
        xor r12d, r12d
1:      mov rax, [rsp + RR_PARTS]
        cmp r12, [rax + VEC_LEN]
        jae .Lrr_field
        mov rax, [rax + VEC_DATA]
        mov r13, [rax + r12*8]
        inc r12
        mov rdi, [r13 + N_DATA]
        mov rsi, [r13 + N_DATA + 8]
        mov rdx, [rsp + RR_IDX]
        mov rcx, [r13 + N_DATA + 16]
        call rg_store_line
        mov rdi, [rsp + RR_OUT]
        mov rsi, rax
        call vec_push
        jmp 1b
.Lrr_check:
        # the same stores - or some still not of whole variables: as they were
        mov rax, [rsp + RR_OUT]
        mov rdi, [rax + VEC_DATA]
        mov rsi, [rax + VEC_LEN]
        call rg_size_offs
        mov rbx, rax
        mov rdi, [rsp + RR_LINES]
        mov rsi, [rsp + RR_N]
        call rg_size_offs
        mov rcx, [rbx + VEC_LEN]
        cmp rcx, [rax + VEC_LEN]
        jne 2f
        xor edx, edx
1:      cmp rdx, rcx
        jae .Lrr_asis
        mov r8, [rbx + VEC_DATA]
        mov r9, [rax + VEC_DATA]
        mov r8, [r8 + rdx*8]
        cmp r8, [r9 + rdx*8]
        jne 2f
        inc rdx
        jmp 1b
2:      xor r12d, r12d
3:      mov rax, [rsp + RR_OUT]
        cmp r12, [rax + VEC_LEN]
        jae 4f
        mov rax, [rax + VEC_DATA]
        mov r13, [rax + r12*8]
        inc r12
        mov rdi, [rsp + RR_FIELDS]
        mov rsi, [r13 + N_DATA + 8]
        mov rdx, [r13 + N_DATA + 16]
        call rg_whole
        test eax, eax
        jz .Lrr_asis
        jmp 3b
4:      # the stores of the variables: their accesses of this class too
        xor r12d, r12d
5:      mov rax, [rsp + RR_OUT]
        cmp r12, [rax + VEC_LEN]
        jae 6f
        mov rax, [rax + VEC_DATA]
        mov r13, [rax + r12*8]
        inc r12
        mov rdi, [r13 + N_DATA + 8]
        mov rsi, [r13 + N_DATA + 16]
        mov rdx, [r13 + N_DATA + 24]
        call mk3
        mov rcx, [rsp + RR_RG]
        mov rdi, [rcx + RG_CLS]
        mov rsi, rax
        mov rdx, [rsp + RR_CLS]
        call od_put
        jmp 5b
6:      mov rdi, [rsp + RR_OUT]
        lea rsi, [rip + rg_line_off_lt]
        xor edx, edx
        call py_sort
        mov rax, [rsp + RR_OUT]
        mov rdi, [rsp + RR_RES]
        mov rsi, [rax + VEC_DATA]
        mov rdx, [rax + VEC_LEN]
        call vec_extend
        jmp .Lrr_ret
.Lrr_asis:
        mov rdi, [rsp + RR_RES]
        mov rsi, [rsp + RR_LINES]
        mov rdx, [rsp + RR_N]
        call vec_extend
.Lrr_ret:
        add rsp, 160
        LEAVE
# the parts: [(size, off, value)] alone (rdi, rsi, rdx)
.Lrr_one_part:
        sub rsp, 8
        call mk3
        mov [rsp], rax
        call vec_new
        mov [rsp + 16 + RR_PARTS], rax
        mov rdi, rax
        mov rsi, [rsp]
        call vec_push
        add rsp, 8
        ret
ENDF rg_run


# ---------------------------------------------------------------------
# Storage

# (the Storage's fields: include/storage.inc)

# st_steps_of(idx, lang) -> rax: steps(parse(idx, lang)), 0 (None); python's
# exception logged ("storage path of"), and None
FUNC st_steps_of
        ENTER
        sub rsp, ERR_SIZEOF + 16
        mov rbx, rdi
        mov r12, rsi
        mov rdi, rsp
        call err_catch
        test eax, eax
        jnz 1f
        mov rdi, rbx
        mov rsi, r12
        call st_parse
        mov rdi, rax
        call st_steps
        mov rbx, rax
        call err_end
        mov rax, rbx
        add rsp, ERR_SIZEOF + 16
        LEAVE
1:      mov edi, eax
        call st_catch_all
        mov edi, LOG_ERROR
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_path_exc]
        mov rcx, rbx
        call log_fmt
        xor eax, eax
        add rsp, ERR_SIZEOF + 16
        LEAVE
ENDF st_steps_of

# st_nil_none(v) -> rax: sp_none for 0
FUNC st_nil_none
        mov rax, rdi
        test rdi, rdi
        jnz 1f
        lea rax, [rip + sp_none]
1:      ret
ENDF st_nil_none

# st_none_nil(v) -> rax: 0 for sp_none
FUNC st_none_nil
        lea rax, [rip + sp_none]
        cmp rdi, rax
        mov rax, rdi
        jne 1f
        xor eax, eax
1:      ret
ENDF st_none_nil

# sg_new(functions, lang) -> sg: python's Storage(functions, lang)
FUNC sg_new
        ENTER
        sub rsp, 48
        .set SN_FUNCS, 0
        .set SN_BY, 8
        .set SN_I, 16
        mov [rsp + SN_FUNCS], rdi
        mov r12, rsi
        mov edi, SG_SIZEOF
        call arena_alloc
        mov rbx, rax
        mov [rbx + SG_LANG], r12
        mov rdi, [rsp + SN_FUNCS]
        call st_functions_accesses
        mov [rbx + SG_ACCESSES], rax
        call od_new
        mov [rbx + SG_STEPS], rax
        call od_new
        mov [rsp + SN_BY], rax
        mov qword ptr [rsp + SN_I], 0
1:      mov rdi, [rbx + SG_ACCESSES]
        call od_len
        cmp [rsp + SN_I], rax
        jae 3f
        mov rdi, [rbx + SG_ACCESSES]
        mov rsi, [rsp + SN_I]
        call od_key
        mov r12, rax                    # a = (size, off, idx)
        mov rdi, [rbx + SG_ACCESSES]
        mov rsi, [rsp + SN_I]
        call od_val
        mov r14, rax                    # written
        inc qword ptr [rsp + SN_I]
        mov rdi, [r12 + N_DATA + 16]
        mov rsi, [rbx + SG_LANG]
        call st_steps_of
        mov r13, rax
        mov rdi, rax
        call st_nil_none
        mov rdi, [rbx + SG_STEPS]
        mov rsi, r12
        mov rdx, rax
        call od_put
        test r13, r13
        jz 1b
        mov rdi, [r12 + N_DATA]
        call is_int
        test eax, eax
        jz 1b
        mov rdi, [rsp + SN_BY]          # by_root[root] += (st, size, off, written)
        mov rsi, [r13 + N_DATA]
        call st_od_group
        mov [rsp + 24], rax
        mov rdi, [r13 + N_DATA + 8]
        mov rsi, [r12 + N_DATA]
        mov rdx, [r12 + N_DATA + 8]
        mov rcx, r14
        call mk4
        mov rdi, [rsp + 24]
        mov rsi, rax
        call vec_push
        jmp 1b
3:      mov rdi, rbx
        mov rsi, [rsp + SN_BY]
        call sg_type_roots
        # the fixed arrays whose length the functions check: the slots after
        # the first are theirs, not other variables
        mov rdi, rbx
        mov rsi, [rsp + SN_FUNCS]
        call sg_fixed_lengths
        mov [rbx + SG_LENGTHS], rax
        mov rdi, rbx
        mov rsi, [rsp + SN_BY]
        call sg_move_fixed
        test eax, eax
        jz 4f
        mov rdi, rbx
        mov rsi, [rsp + SN_BY]
        call sg_type_roots
4:      # the functions that return a bytes (or string) of the storage
        call od_new
        mov [rbx + SG_BG], rax
        mov rax, [rsp + SN_FUNCS]
        mov qword ptr [rsp + SN_I], 0
5:      mov rax, [rsp + SN_FUNCS]
        mov rcx, [rsp + SN_I]
        cmp rcx, [rax + VEC_LEN]
        jae 6f
        mov rax, [rax + VEC_DATA]
        mov r12, [rax + rcx*8]
        inc qword ptr [rsp + SN_I]
        mov rdi, rbx
        mov rsi, r12
        call sg_bytes_getter
        test rax, rax
        jz 5b
        mov rdi, [rbx + SG_BG]
        mov rsi, r12
        mov rdx, rax
        call od_put
        jmp 5b
6:      mov rdi, rbx
        mov rsi, [rsp + SN_FUNCS]
        call sg_names
        mov rax, rbx
        add rsp, 48
        LEAVE
ENDF sg_new

# sg_type_roots(sg, by_root): python's Storage.type_roots - what's at each
# root (a value 0 in by_root: popped)
FUNC sg_type_roots
        ENTER
        sub rsp, ERR_SIZEOF + 48
        .set TR_BY, ERR_SIZEOF
        .set TR_I, ERR_SIZEOF + 8
        .set TR_N, ERR_SIZEOF + 16
        .set TR_ACCS, ERR_SIZEOF + 24
        .set TR_VEC, ERR_SIZEOF + 32
        mov rbx, rdi
        mov [rsp + TR_BY], rsi
        call od_new
        mov [rbx + SG_TYPES], rax
        call od_new
        mov [rbx + SG_FIELDS], rax
        mov qword ptr [rsp + TR_I], 0
.Ltr_next:
        mov rdi, [rsp + TR_BY]
        call od_len
        cmp [rsp + TR_I], rax
        jae .Ltr_done
        mov rdi, [rsp + TR_BY]
        mov rsi, [rsp + TR_I]
        call od_key
        mov [rsp + TR_N], rax
        mov rdi, [rsp + TR_BY]
        mov rsi, [rsp + TR_I]
        call od_val
        inc qword ptr [rsp + TR_I]
        test rax, rax
        jz .Ltr_next                    # (popped)
        mov [rsp + TR_ACCS], rax
        mov r12, rax
        xor r13d, r13d                  # all of the slot itself, at known bits?
1:      cmp r13, [r12 + VEC_LEN]
        jae 2f
        mov rax, [r12 + VEC_DATA]
        mov r14, [rax + r13*8]
        inc r13
        mov rax, [r14 + N_DATA]
        cmp dword ptr [rax + N_AUX], 0
        jne .Ltr_typeof
        jmp 1b
2:      xor r13d, r13d
3:      cmp r13, [r12 + VEC_LEN]
        jae 4f
        mov rax, [r12 + VEC_DATA]
        mov r14, [rax + r13*8]
        inc r13
        mov rdi, [r14 + N_DATA + 16]
        call is_int
        test eax, eax
        jz .Ltr_typeof
        jmp 3b
4:      # (size, off): a bytes, else the variables of the slot
        mov edi, 1
        call .Ltr_project
        mov rdi, rax
        call st_is_bytes_slot
        test eax, eax
        jz 5f
        LOADS rdi, BYTES
        call mk1
        mov rdx, rax
        mov rdi, [rbx + SG_TYPES]
        mov rsi, [rsp + TR_N]
        call od_put
        jmp .Ltr_next
5:      mov edi, 2
        call .Ltr_project
        mov rdi, rax
        call st_layout
        mov rdx, rax
        mov rdi, [rbx + SG_FIELDS]
        mov rsi, [rsp + TR_N]
        call od_put
        jmp .Ltr_next
.Ltr_typeof:
        xor edi, edi
        call .Ltr_project
        mov [rsp + TR_VEC], rax
        mov rdi, rsp
        call err_catch
        test eax, eax
        jnz 6f
        mov rdi, [rsp + TR_VEC]
        call st_typeof
        mov rdx, rax
        mov rdi, [rbx + SG_TYPES]
        mov rsi, [rsp + TR_N]
        call od_put
        call err_end
        jmp .Ltr_next
6:      mov edi, eax
        call st_catch_all
        mov edi, LOG_ERROR
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_type_exc]
        mov rcx, [rsp + TR_N]
        call log_fmt
        jmp .Ltr_next
.Ltr_done:
        add rsp, ERR_SIZEOF + 48
        LEAVE
# the accesses (st, size, off, written) of TR_ACCS as (st, size, off) (edi
# 0), (size, off) (1) or (size, off, written) (2): a vec
.Ltr_project:
        push r12
        push r13
        push r14
        push rbp
        sub rsp, 8
        mov ebp, edi
        call vec_new
        mov r14, rax
        mov r12, [rsp + 48 + TR_ACCS]
        xor r13d, r13d
1:      cmp r13, [r12 + VEC_LEN]
        jae 9f
        mov rax, [r12 + VEC_DATA]
        mov rax, [rax + r13*8]
        inc r13
        cmp ebp, 1
        je 2f
        cmp ebp, 2
        je 3f
        mov rdi, [rax + N_DATA]
        mov rsi, [rax + N_DATA + 8]
        mov rdx, [rax + N_DATA + 16]
        call mk3
        jmp 4f
2:      mov rdi, [rax + N_DATA + 8]
        mov rsi, [rax + N_DATA + 16]
        call mk2
        jmp 4f
3:      mov rdi, [rax + N_DATA + 8]
        mov rsi, [rax + N_DATA + 16]
        mov rdx, [rax + N_DATA + 24]
        call mk3
4:      mov rdi, r14
        mov rsi, rax
        call vec_push
        jmp 1b
9:      mov rax, r14
        add rsp, 8
        pop rbp
        pop r14
        pop r13
        pop r12
        ret
ENDF sg_type_roots

# sg_steps_get(sg, a) -> rax: self.steps.get(a): 0 for None (or absent)
FUNC sg_steps_get
        ENTER
        mov rdi, [rdi + SG_STEPS]
        call od_get
        mov rdi, rax
        call st_none_nil
        LEAVE
ENDF sg_steps_get

# sg_fixed_lengths(sg, functions) -> od: python's Storage.fixed_lengths -
# root -> the length of the fixed array there, when the functions that
# index it check the index is below a number first (and all the same)
FUNC sg_fixed_lengths
        ENTER
        sub rsp, 96
        .set FL_FUNCS, 0
        .set FL_FOUND, 8
        .set FL_I, 16
        .set FL_ACC, 24
        .set FL_CHECKED, 32
        .set FL_J, 40
        .set FL_LIN, 48                 # linear's (24 bytes)
        .set FL_T, 72
        .set FL_A, 80
        mov rbx, rdi
        mov [rsp + FL_FUNCS], rsi
        call od_new
        mov [rsp + FL_FOUND], rax
        mov qword ptr [rsp + FL_I], 0
.Lfl_func:
        mov rax, [rsp + FL_FUNCS]
        mov rcx, [rsp + FL_I]
        cmp rcx, [rax + VEC_LEN]
        jae .Lfl_done
        mov rax, [rax + VEC_DATA]
        mov r12, [rax + rcx*8]
        inc qword ptr [rsp + FL_I]
        call od_new
        mov [rsp + FL_ACC], rax
        mov rdi, [r12 + FN_TRACE]
        mov rsi, rax
        call st_find_accesses
        mov rdi, [r12 + FN_TRACE]
        call st_checked_below
        mov [rsp + FL_CHECKED], rax
        mov rdi, rax
        call od_len
        test rax, rax
        jz .Lfl_func
        mov qword ptr [rsp + FL_J], 0
.Lfl_acc:
        mov rdi, [rsp + FL_ACC]
        call od_len
        cmp [rsp + FL_J], rax
        jae .Lfl_func
        mov rdi, [rsp + FL_ACC]
        mov rsi, [rsp + FL_J]
        call od_key
        inc qword ptr [rsp + FL_J]
        mov [rsp + FL_A], rax
        mov rdi, rbx
        mov rsi, rax
        call sg_steps_get
        test rax, rax
        jz .Lfl_acc
        mov r13, rax                    # (n, sts): sts[0] an ('off', e) of a
        mov rax, [r13 + N_DATA + 8]     # symbolic e
        cmp dword ptr [rax + N_AUX], 0
        je .Lfl_acc
        mov r14, [rax + N_DATA]
        mov rdi, r14
        call opcode_of
        cmp eax, OP_OFF
        jne .Lfl_acc
        mov rdi, [r14 + N_DATA + 8]
        call is_int
        test eax, eax
        jnz .Lfl_acc
        mov rdi, [rbx + SG_TYPES]       # t: a fixed array
        mov rsi, [r13 + N_DATA]
        call od_get
        test rax, rax
        jz .Lfl_acc
        mov [rsp + FL_T], rax
        mov rdi, rax
        call opcode_of
        cmp eax, OP_FIXED
        jne .Lfl_acc
        mov r14, [r14 + N_DATA + 8]     # e
        mov rax, [rsp + FL_T]
        mov rdi, [rax + N_DATA + 8]
        call st_elem_width
        cmp rax, (256 << 1) | 1
        jge 1f
        mov rax, [rsp + FL_A]
        mov rdi, [rax + N_DATA]
        call is_int
        test eax, eax
        jz 1f
        mov rax, [rsp + FL_A]           # i = packed(e, off, size)
        mov rdi, r14
        mov rsi, [rax + N_DATA + 8]
        mov rdx, [rax + N_DATA]
        call st_packed
        jmp 2f
1:      mov rdi, r14                    # i if s == stride and c == 0
        lea rsi, [rsp + FL_LIN]
        call st_linear
        mov rax, [rsp + FL_T]
        mov rdi, [rsp + FL_LIN + 8]
        mov rsi, [rax + N_DATA + 16]
        call py_equal
        test eax, eax
        jz .Lfl_acc
        cmp qword ptr [rsp + FL_LIN + 16], 1
        jne .Lfl_acc
        mov rax, [rsp + FL_LIN]
2:      test rax, rax
        jz .Lfl_acc
        mov rdi, [rsp + FL_CHECKED]
        mov rsi, rax
        call od_get
        test rax, rax
        jz .Lfl_acc
        mov r14, rax                    # found[n].add(checked[i])
        mov rdi, [rsp + FL_FOUND]
        mov rsi, [r13 + N_DATA]
        call st_od_group
        mov rdi, rax
        mov rsi, r14
        call set_add
        jmp .Lfl_acc
.Lfl_done:
        call od_new                     # the roots of one length
        mov r12, rax
        xor r13d, r13d
3:      mov rdi, [rsp + FL_FOUND]
        call od_len
        cmp r13, rax
        jae 4f
        mov rdi, [rsp + FL_FOUND]
        mov rsi, r13
        call od_val
        mov r14, rax
        mov rdi, [rsp + FL_FOUND]
        mov rsi, r13
        call od_key
        inc r13
        cmp qword ptr [r14 + VEC_LEN], 1
        jne 3b
        mov rcx, [r14 + VEC_DATA]
        mov rdx, [rcx]
        mov rdi, r12
        mov rsi, rax
        call od_put
        jmp 3b
4:      mov rax, r12
        add rsp, 96
        LEAVE
ENDF sg_fixed_lengths

# sg_move_fixed(sg, by_root) -> eax: the slots after the first of a fixed
# array whose length is known, moved from roots of their own to it (by_root
# changed; the steps of their accesses too) - 1 when some were
FUNC sg_move_fixed
        ENTER
        sub rsp, 96
        .set MF_BY, 0
        .set MF_ITEMS, 8
        .set MF_I, 16
        .set MF_N, 24
        .set MF_END, 32                 # n + slots
        .set MF_RS, 40
        .set MF_J, 48
        .set MF_MOVED, 56
        .set MF_STEP, 64                # [('off', r - n)]
        .set MF_R, 72
        mov rbx, rdi
        mov [rsp + MF_BY], rsi
        mov qword ptr [rsp + MF_MOVED], 0
        call vec_new                    # sorted(self.lengths.items())
        mov [rsp + MF_ITEMS], rax
        xor r12d, r12d
1:      mov rdi, [rbx + SG_LENGTHS]
        call od_len
        cmp r12, rax
        jae 2f
        mov rdi, [rbx + SG_LENGTHS]
        mov rsi, r12
        call od_key
        mov r13, rax
        mov rdi, [rbx + SG_LENGTHS]
        mov rsi, r12
        call od_val
        inc r12
        mov rdi, r13
        mov rsi, rax
        call mk2
        mov rdi, [rsp + MF_ITEMS]
        mov rsi, rax
        call vec_push
        jmp 1b
2:      mov rdi, [rsp + MF_ITEMS]
        lea rsi, [rip + py_lt]
        xor edx, edx
        call py_sort
        mov qword ptr [rsp + MF_I], 0
.Lmf_item:
        mov rax, [rsp + MF_ITEMS]
        mov rcx, [rsp + MF_I]
        cmp rcx, [rax + VEC_LEN]
        jae .Lmf_done
        mov rax, [rax + VEC_DATA]
        mov r12, [rax + rcx*8]          # (n, length)
        inc qword ptr [rsp + MF_I]
        mov rax, [r12 + N_DATA]
        mov [rsp + MF_N], rax
        mov rdi, [rsp + MF_BY]
        mov rsi, rax
        call od_get
        test rax, rax
        jz .Lmf_item
        mov rdi, [rbx + SG_TYPES]
        mov rsi, [rsp + MF_N]
        call od_get
        test rax, rax
        jz .Lmf_item
        mov r13, rax                    # t
        mov rdi, rax
        call opcode_of
        cmp eax, OP_FIXED
        jne .Lmf_item
        mov rdi, [r13 + N_DATA + 8]
        call st_elem_width
        mov r14, rax
        cmp rax, (256 << 1) | 1
        jge 3f
        # -(-length // (256 // width))
        mov rcx, rax
        sar rcx, 1
        mov eax, 256
        xor edx, edx
        div ecx
        TAG rax
        mov [rsp + MF_R], rax
        mov rdi, [r12 + N_DATA + 8]
        call int_neg
        mov rdi, rax
        mov rsi, [rsp + MF_R]
        call int_floordiv
        mov rdi, rax
        call int_neg
        jmp 4f
3:      mov rdi, [r12 + N_DATA + 8]     # length * stride
        mov rsi, [r13 + N_DATA + 16]
        call int_mul
4:      mov rdi, [rsp + MF_N]
        mov rsi, rax
        call int_add
        mov [rsp + MF_END], rax
        # the roots r of known fields with n < r < n + slots, in order
        call vec_new
        mov [rsp + MF_RS], rax
        xor r12d, r12d
5:      mov rdi, [rbx + SG_FIELDS]
        call od_len
        cmp r12, rax
        jae 6f
        mov rdi, [rbx + SG_FIELDS]
        mov rsi, r12
        call od_key
        inc r12
        mov r13, rax
        mov rdi, [rsp + MF_N]
        mov rsi, rax
        call int_cmp
        cmp eax, -1
        jne 5b
        mov rdi, r13
        mov rsi, [rsp + MF_END]
        call int_cmp
        cmp eax, -1
        jne 5b
        mov rdi, [rsp + MF_RS]
        mov rsi, r13
        call vec_push
        jmp 5b
6:      mov rdi, [rsp + MF_RS]
        lea rsi, [rip + py_lt]
        xor edx, edx
        call py_sort
        mov qword ptr [rsp + MF_J], 0
.Lmf_r:
        mov rax, [rsp + MF_RS]
        mov rcx, [rsp + MF_J]
        cmp rcx, [rax + VEC_LEN]
        jae .Lmf_item
        mov rax, [rax + VEC_DATA]
        mov rax, [rax + rcx*8]
        mov [rsp + MF_R], rax
        inc qword ptr [rsp + MF_J]
        mov rdi, [rsp + MF_BY]          # (r in by_root: not moved yet)
        mov rsi, rax
        call od_get
        test rax, rax
        jz .Lmf_r
        mov r14, rax                    # its accesses
        mov rdi, [rsp + MF_R]           # [('off', r - n)]
        mov rsi, [rsp + MF_N]
        call int_sub
        mov rsi, rax
        LOADS rdi, OFF
        call mk2
        mov rdi, rax
        call mk_list1
        mov [rsp + MF_STEP], rax
        # the accesses at (r, []) now at (n, [('off', r - n)])
        xor edi, edi
        xor esi, esi
        call mk_list
        mov rdi, [rsp + MF_R]
        mov rsi, rax
        call mk2
        mov r13, rax                    # (r, [])
        mov rdi, [rsp + MF_N]
        mov rsi, [rsp + MF_STEP]
        call mk2
        mov [rsp + 88], rax             # (n, [('off', r - n)])
        xor r12d, r12d
7:      mov rdi, [rbx + SG_STEPS]
        call od_len
        cmp r12, rax
        jae 8f
        mov rdi, [rbx + SG_STEPS]
        mov rsi, r12
        call od_val
        inc r12
        cmp rax, r13
        jne 7b
        mov rdi, [rbx + SG_STEPS]
        lea rsi, [r12 - 1]
        mov rdx, [rsp + 88]
        call od_set_val
        jmp 7b
8:      mov rdi, [rsp + MF_BY]          # by_root.pop(r)
        mov rsi, [rsp + MF_R]
        xor edx, edx
        call od_put
        mov rdi, [rsp + MF_BY]
        mov rsi, [rsp + MF_N]
        call od_get
        mov r13, rax                    # by_root[n] += ...
        xor r12d, r12d
9:      cmp r12, [r14 + VEC_LEN]
        jae 10f
        mov rax, [r14 + VEC_DATA]
        mov rax, [rax + r12*8]
        inc r12
        mov rdi, [rsp + MF_STEP]
        mov rsi, [rax + N_DATA + 8]
        mov rdx, [rax + N_DATA + 16]
        mov rcx, [rax + N_DATA + 24]
        call mk4
        mov rdi, r13
        mov rsi, rax
        call vec_push
        jmp 9b
10:     mov qword ptr [rsp + MF_MOVED], 1
        jmp .Lmf_r
.Lmf_done:
        mov rax, [rsp + MF_MOVED]
        add rsp, 96
        LEAVE
ENDF sg_move_fixed


# --- the names ---

        .section .rodata
.Ls_get:        .asciz "get"
.Ls_unknown_pfx: .asciz "unknown"
.Ls_stor:       .asciz "stor"
.Ls_uint:       .asciz "uint"
.Ls_int:        .asciz "int"
.Ls_bytes:      .asciz "bytes"
        # what a name of the output means already (python's RESERVED)
reserved_names:
        .asciz "stor", "mem", "call", "calldata", "block", "tx", "msg", "this"
        .asciz "caller", "Mask", "Bytes", "Array", "concat", "sha3", "bool"
        .asciz "address", "ceil32", "floor32", "addmod", "mulmod", "max", "min"
        .asciz "ext_call", "ext_code", "eth", "transient", "not", "and", "or"
        .asciz "if", "while", "return", "revert"
        .byte 0
        .text

# st_cstr_in(cstr, list) -> eax: the C string among the NUL-separated list
# (ended by an empty one)
FUNC st_cstr_in
        ENTER
        mov rbx, rdi
        mov r12, rsi
1:      cmp byte ptr [r12], 0
        je 8f
        mov rdi, rbx
        mov rsi, r12
        call strcmp@PLT
        test eax, eax
        jz 9f
        mov rdi, r12
        call strlen@PLT
        lea r12, [r12 + rax + 1]
        jmp 1b
8:      xor eax, eax
        LEAVE
9:      mov eax, 1
        LEAVE
ENDF st_cstr_in

# st_is_ident_char(c, first) -> eax: python's identifier characters (the
# bytes of a character past ASCII taken as a letter's)
FUNC st_is_ident_char
        xor eax, eax
        cmp dil, '_'
        je 1f
        cmp dil, 0x80
        jae 1f
        mov ecx, edi
        or cl, 0x20
        cmp cl, 'a'
        jb 2f
        cmp cl, 'z'
        jbe 1f
2:      test esi, esi
        jnz 3f
        cmp dil, '0'
        jb 3f
        cmp dil, '9'
        jbe 1f
3:      ret
1:      mov eax, 1
        ret
ENDF st_is_ident_char

# st_digits(p) -> rax: the ASCII digits at p (python's \d*, ASCII)
FUNC st_digits
        xor eax, eax
1:      movzx ecx, byte ptr [rdi + rax]
        sub ecx, '0'
        cmp ecx, 9
        ja 2f
        inc rax
        jmp 1b
2:      ret
ENDF st_digits

# st_prefix(p, cstr) -> rax: the length of cstr if p starts with it, else -1
FUNC st_prefix
        xor eax, eax
1:      movzx ecx, byte ptr [rsi + rax]
        test ecx, ecx
        jz 2f
        cmp cl, [rdi + rax]
        jne 3f
        inc rax
        jmp 1b
2:      ret
3:      mov rax, -1
        ret
ENDF st_prefix

# st_default_like(cstr) -> eax: python's re.fullmatch(r"(u?int|bytes|stor)
# \d*|stor[0-9A-F]+(_\d+)?|stor\d+_\d+", name) - a name of the output's own
FUNC st_default_like
        ENTER
        mov rbx, rdi
        lea r12, [rip + .Ls_uint]       # (u?int|bytes|stor)\d*
        call .Ldl_type_digits
        lea r12, [rip + .Ls_int]
        call .Ldl_type_digits
        lea r12, [rip + .Ls_bytes]
        call .Ldl_type_digits
        lea r12, [rip + .Ls_stor]
        call .Ldl_type_digits
        mov rdi, rbx                    # stor[0-9A-F]+(_\d+)?
        lea rsi, [rip + .Ls_stor]
        call st_prefix
        test rax, rax
        js 8f
        lea r12, [rbx + rax]
        xor r13d, r13d
1:      movzx ecx, byte ptr [r12 + r13]
        lea edx, [ecx - '0']
        cmp edx, 9
        jbe 2f
        lea edx, [ecx - 'A']
        cmp edx, 5
        ja 3f
2:      inc r13
        jmp 1b
3:      test r13, r13
        jz 8f
        add r12, r13
        cmp byte ptr [r12], 0
        je 9f
        cmp byte ptr [r12], '_'
        jne 8f
        lea rdi, [r12 + 1]
        call st_digits
        test rax, rax
        jz 8f
        cmp byte ptr [r12 + 1 + rax], 0
        je 9f
8:      xor eax, eax
        LEAVE
9:      mov eax, 1
        LEAVE
# the name is r12's text then digits only: return 1 from the function
.Ldl_type_digits:
        mov rdi, rbx
        mov rsi, r12
        call st_prefix
        test rax, rax
        js 1f
        lea rdi, [rbx + rax]
        mov r13, rdi
        call st_digits
        cmp byte ptr [r13 + rax], 0
        jne 1f
        add rsp, 8
        mov eax, 1
        LEAVE
1:      ret
ENDF st_default_like

# st_good_name(name) -> eax: python's good_name - whether a getter's name
# can name its variable
FUNC st_good_name
        ENTER
        lea rbx, [rdi + N_DATA + 4]     # the text
        movzx edi, byte ptr [rbx]       # an identifier
        test edi, edi
        jz 8f
        mov esi, 1
        call st_is_ident_char
        test eax, eax
        jz 8f
        lea r12, [rbx + 1]
1:      movzx edi, byte ptr [r12]
        test edi, edi
        jz 2f
        xor esi, esi
        call st_is_ident_char
        test eax, eax
        jz 8f
        inc r12
        jmp 1b
2:      mov rdi, rbx
        lea rsi, [rip + .Ls_unknown_pfx]
        call st_prefix
        test rax, rax
        jns 8f
        cmp byte ptr [rbx], '_'
        je 8f
        mov rdi, rbx
        lea rsi, [rip + reserved_names]
        call st_cstr_in
        test eax, eax
        jnz 8f
        mov rdi, rbx
        call st_default_like
        test eax, eax
        jnz 8f
        mov eax, 1
        LEAVE
8:      xor eax, eax
        LEAVE
ENDF st_good_name

# st_getter_name(fname) -> str: the name a getter gives its variable - its
# own before the params, getBalance: balance (interned)
FUNC st_getter_name
        ENTER
        mov rbx, rdi
        lea rdi, [rbx + N_DATA + 4]
        mov esi, '('
        call strchr@PLT
        lea r12, [rbx + N_DATA + 4]
        mov r13d, [rbx + N_DATA]        # the length before the '('
        test rax, rax
        jz 1f
        mov r13, rax
        sub r13, r12
1:      cmp r13, 3
        jbe 3f
        mov rdi, r12
        lea rsi, [rip + .Ls_get]
        call st_prefix
        test rax, rax
        js 3f
        movzx eax, byte ptr [r12 + 3]   # name[3].isupper(): name[3].lower() + name[4:]
        sub eax, 'A'
        cmp eax, 25
        ja 3f
        lea rdi, [r13 - 3 + 16]
        call arena_alloc_raw
        mov r14, rax
        lea rsi, [r12 + 3]
        mov rdi, r14
        lea rdx, [r13 - 3]
        call memcpy@PLT
        or byte ptr [r14], 0x20
        mov rdi, r14
        lea rsi, [r13 - 3]
        call str_intern
        LEAVE
3:      mov rdi, r12
        mov rsi, r13
        call str_intern
        LEAVE
ENDF st_getter_name

# st_append_hex_part(sb, n, a, b, upper): hex(n)[a:b] (upper-cased)
FUNC st_append_hex_part
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rdx
        mov r13, rcx
        mov [rsp], r8
        mov [rsp + 8], rsi
        call sb_new
        mov r14, rax
        mov rdi, rax
        mov rsi, [rsp + 8]
        mov edx, 16
        call sb_append_int
        mov rcx, [r14 + SB_LEN]         # hex(n)[a:b] of "0x..."
        cmp r13, rcx
        jbe 1f
        mov r13, rcx
1:      cmp r12, r13
        jae 3f
        mov rax, [r14 + SB_BUF]
        movzx esi, byte ptr [rax + r12]
        cmp qword ptr [rsp], 0
        je 2f
        cmp esi, 'a'
        jb 2f
        cmp esi, 'z'
        ja 2f
        sub esi, 32
2:      mov rdi, rbx
        call sb_append_char
        inc r12
        jmp 1b
3:      mov rdi, r14
        call sb_free
        add rsp, 16
        LEAVE
ENDF st_append_hex_part

# st_default_name(n, off) -> str: python's names.default - stor{n}, or
# stor + 4 hex digits for a hash, then _{off} (interned)
FUNC st_default_name
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_stor]
        call sb_append_c
        mov rdi, rbx
        mov rsi, (1 << 33) | 1
        call int_cmp
        cmp eax, -1
        jne 1f
        mov rdi, r13
        mov rsi, rbx
        mov edx, 10
        call sb_append_int
        jmp 2f
1:      mov rdi, r13
        mov rsi, rbx
        mov edx, 2
        mov ecx, 6
        mov r8d, 1
        call st_append_hex_part
2:      cmp r12, 1
        je 3f
        mov rdi, r13
        mov esi, '_'
        call sb_append_char
        mov rdi, r13
        mov rsi, r12
        mov edx, 10
        call sb_append_int
3:      mov rdi, r13
        call sb_finish_intern
        LEAVE
ENDF st_default_name

# st_unique(taken, name, n) -> str: python's names.unique - the name, made
# unique among the taken (an od used as a set), and taken
FUNC st_unique
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov rdi, rbx
        call od_get
        test rax, rax
        jz 2f
        call sb_new                     # {name}_{n or 8 hex digits}
        mov r14, rax
        mov rdi, rax
        mov rsi, r12
        call sb_append_str
        mov rdi, r14
        mov esi, '_'
        call sb_append_char
        mov rdi, r13
        mov rsi, (1 << 33) | 1
        call int_cmp
        cmp eax, -1
        jne 1f
        mov rdi, r14
        mov rsi, r13
        mov edx, 10
        call sb_append_int
        jmp 11f
1:      mov rdi, r14
        mov rsi, r13
        mov edx, 2
        mov ecx, 10
        xor r8d, r8d
        call st_append_hex_part
11:     mov rdi, r14
        call sb_finish_intern
        mov r12, rax
2:      mov [rsp], r12                  # base
        mov r13d, 2                     # k
3:      mov rdi, rbx
        mov rsi, r12
        call od_get
        test rax, rax
        jz 4f
        call sb_new                     # {base}_{k}
        mov r14, rax
        mov rdi, rax
        mov rsi, [rsp]
        call sb_append_str
        mov rdi, r14
        mov esi, '_'
        call sb_append_char
        mov rdi, r14
        mov rsi, r13
        call sb_append_u64
        mov rdi, r14
        call sb_finish_intern
        mov r12, rax
        inc r13
        jmp 3b
4:      mov rdi, rbx
        mov rsi, r12
        mov edx, 3
        call od_put
        mov rax, r12
        add rsp, 16
        LEAVE
ENDF st_unique

# st_getter_access(fn) -> rax: python's getter_access - (size, off, idx) of
# what a getter returns, or ('root', n) for the members of a struct at n;
# 0 (None)
FUNC st_getter_access
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 16
        mov rbx, rdi
        mov rdi, [rbx + FN_GETTER]
        test rdi, rdi
        jz .Lga_none
        call py_truthy
        test eax, eax
        jz .Lga_none
        PAT rsi, "('struct', ('loc', ':int:n'))"
        mov rdi, [rbx + FN_GETTER]
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 1f
        LOADS rdi, ROOT
        mov rsi, [rsp]
        call mk2
        jmp .Lga_ret
1:      mov rax, [rbx + FN_RETURNS]
        test rax, rax
        jz .Lga_none
        cmp dword ptr [rax + N_AUX], 1
        jne .Lga_none
        mov rax, [rax + N_DATA]
        mov rdi, rax
        call is_seq
        test eax, eax
        jz .Lga_none                    # (len() of something else: python's TypeError)
        mov rax, [rbx + FN_RETURNS]
        mov rax, [rax + N_DATA]
        cmp dword ptr [rax + N_AUX], 2
        jne .Lga_none
        mov rdi, [rax + N_DATA + 8]
        call st_word
        mov rdi, rax
        lea rsi, [rip + st_narrow]
        xor edx, edx
        call replace_f
        mov r12, rax                    # ret
        PAT rsi, "('bool', ':s')"
        mov rdi, r12
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 2f
        mov r12, [rsp]
2:      PAT rsi, "('signextend', 'Any', ':s')"
        mov rdi, r12
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 3f
        mov r12, [rsp]
3:      PAT rsi, "('mask_shl', ':int:size', 0, ':int:shl', ':s')"
        mov rdi, r12
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 5f
        mov r13, [rsp + 16]             # s: a storage
        mov rdi, r13
        call opcode_of
        cmp eax, OP_STORAGE
        jne 5f
        cmp dword ptr [r13 + N_AUX], 2
        jb .Lga_index
        mov r14, [r13 + N_DATA + 8]     # s_size
        cmp qword ptr [rsp + 8], 1      # shl == 0 and size >= s_size
        jne 4f
        mov rdi, r14
        call is_int
        test eax, eax
        jz .Lga_type
        mov rdi, [rsp]
        mov rsi, r14
        call int_cmp
        cmp eax, -1
        jne 41f
4:      mov rdi, [rsp]                  # size == s_size and shl == 256 - size
        mov rsi, r14
        call py_equal
        test eax, eax
        jz 5f
        mov edi, (256 << 1) | 1
        mov rsi, [rsp]
        call int_sub
        mov rdi, [rsp + 8]
        mov rsi, rax
        call py_equal
        test eax, eax
        jz 5f
41:     mov r12, r13
5:      mov rdi, r12
        OP_N_CHECK OP_STORAGE, 4, .Lga_none
        mov rdi, [r12 + N_DATA + 8]
        mov rsi, [r12 + N_DATA + 16]
        mov rdx, [r12 + N_DATA + 24]
        call mk3
        jmp .Lga_ret
.Lga_none:
        xor eax, eax
.Lga_ret:
        add rsp, MATCH_BINDINGS_SIZE + 16
        LEAVE
.Lga_index:
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_gtindex]
        call err_throw
.Lga_type:
        mov edi, E_TYPE
        lea rsi, [rip + .Ls_gtype]
        call err_throw
ENDF st_getter_access

        .section .rodata
.Ls_gtindex:    .asciz "tuple index out of range"
.Ls_gtype:      .asciz "'>=' not supported between instances"
.Ls_unpack_none: .asciz "cannot unpack non-iterable NoneType object"
.Ls_key_length: .asciz "storage: the length of a bytes getter without its steps"
        .text

# st_getter_path(t, sts, size, off) -> eax: python's getter_path - the
# access of what's at the steps sts from a root of type t (0: None) is
# what a getter of it returns: a value of it, reached by keys and indexes
# that are the getter's params
FUNC st_getter_path
        ENTER
        sub rsp, 32
        mov rbx, rdi
        mov r12, rsi
        test rbx, rbx
        jz 8f
        mov [rsp], rdx
        mov [rsp + 8], rcx
        mov rdi, rbx
        call opcode_of
        cmp eax, OP_BYTES
        jne 1f
        cmp dword ptr [r12 + N_AUX], 0
        je 8f
1:      LOADS rdi, SV
        lea rsi, [rip + sp_none]
        call mk2
        mov rdi, rax
        mov rsi, rbx
        mov rdx, r12
        mov rcx, [rsp]
        mov r8, [rsp + 8]
        call st_form
        test rax, rax
        jz 8f
        mov r13, rax
        mov rdi, rax
        call opcode_of
        cmp eax, OP_ST
        jne 8f
        mov r13, [r13 + N_DATA + 16]    # loc
        mov rdi, r13                    # the length of a bytes: its slot
        call opcode_of
        cmp eax, OP_SBL
        jne 2f
        mov ecx, [r12 + N_AUX]
        test ecx, ecx
        jz 2f
        mov rdi, [r12 + N_DATA + rcx*8 - 8]
        call opcode_of
        cmp eax, OP_BLEN
        jne 2f
        mov r13, [r13 + N_DATA + 8]
2:      call vec_new
        mov r14, rax                    # the keys
3:      mov rdi, r13
        call opcode_of
        cmp eax, OP_SV
        je 5f
        cmp eax, OP_SI
        jne 4f
        mov rdi, r14
        mov rsi, [r13 + N_DATA + 16]
        call vec_push
        jmp 41f
4:      cmp eax, OP_SF
        jne 8f
41:     mov r13, [r13 + N_DATA + 8]
        jmp 3b
5:      xor ebx, ebx                    # all from the calldata
6:      cmp rbx, [r14 + VEC_LEN]
        jae 7f
        mov rax, [r14 + VEC_DATA]
        mov rdi, [rax + rbx*8]
        inc rbx
        call st_from_calldata
        test eax, eax
        jz 8f
        jmp 6b
7:      xor ebx, ebx                    # and all different
71:     cmp rbx, [r14 + VEC_LEN]
        jae 9f
        mov rax, [r14 + VEC_DATA]
        mov rcx, [rax + rbx*8]
        inc rbx
        mov rdx, rbx
72:     cmp rdx, [r14 + VEC_LEN]
        jae 71b
        cmp rcx, [rax + rdx*8]
        je 8f
        inc rdx
        jmp 72b
8:      xor eax, eax
        add rsp, 32
        LEAVE
9:      mov eax, 1
        add rsp, 32
        LEAVE
ENDF st_getter_path

# st_int_add_checked(a, b) -> value: python's a + b of two ints, its
# TypeError for anything else (an expression)
FUNC st_int_add_checked
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call is_int
        test eax, eax
        jz 1f
        mov rdi, r12
        call is_int
        test eax, eax
        jz 1f
        mov rdi, rbx
        mov rsi, r12
        call int_add
        LEAVE
1:      mov edi, E_TYPE
        lea rsi, [rip + .Ls_add_type]
        call err_throw
ENDF st_int_add_checked

        .section .rodata
.Ls_add_type:   .asciz "unsupported operand type(s) for +"
        .text

# st_fn_name_lt(a, b, arg) -> eax: a.name < b.name
FUNC st_fn_name_lt
        mov rdi, [rdi + FN_NAME]
        mov rsi, [rsi + FN_NAME]
        jmp py_lt
ENDF st_fn_name_lt

# st_od_setdefault(od, key, value)
FUNC st_od_setdefault
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        call od_get
        test rax, rax
        jnz 1f
        mov rdi, rbx
        mov rsi, r12
        mov rdx, r13
        call od_put
1:      LEAVE
ENDF st_od_setdefault

# sg_names(sg, functions): python's Storage.names - the names of the
# variables, one each, from the getters; the definitions
FUNC sg_names
        ENTER
        sub rsp, 112
        .set NA_FUNCS, 0
        .set NA_GETTERS, 8
        .set NA_I, 16
        .set NA_NAME, 24
        .set NA_A, 32
        .set NA_KEYS, 40
        .set NA_TAKEN, 48
        .set NA_N, 56
        .set NA_J, 64
        .set NA_FLD, 72
        mov rbx, rdi
        mov r12, rsi
        call vec_new                    # sorted(functions, key=name)
        mov [rsp + NA_FUNCS], rax
        mov rdi, rax
        mov rsi, [r12 + VEC_DATA]
        mov rdx, [r12 + VEC_LEN]
        call vec_extend
        mov rdi, [rsp + NA_FUNCS]
        lea rsi, [rip + st_fn_name_lt]
        xor edx, edx
        call py_sort
        call od_new
        mov [rsp + NA_GETTERS], rax
        mov qword ptr [rsp + NA_I], 0
.Lna_func:
        mov rax, [rsp + NA_FUNCS]
        mov rcx, [rsp + NA_I]
        cmp rcx, [rax + VEC_LEN]
        jae .Lna_defs
        mov rax, [rax + VEC_DATA]
        mov r12, [rax + rcx*8]          # f
        inc qword ptr [rsp + NA_I]
        mov rdi, [rbx + SG_BG]
        mov rsi, r12
        call od_get
        mov r13, rax                    # its bytes getter, or 0
        test rax, rax
        jnz 1f
        mov rdi, [r12 + FN_GETTER]
        test rdi, rdi
        jz .Lna_func
        call py_truthy
        test eax, eax
        jz .Lna_func
1:      mov rdi, [r12 + FN_NAME]
        call st_getter_name
        mov [rsp + NA_NAME], rax
        mov rdi, rax
        call st_good_name
        test eax, eax
        jz .Lna_func
        test r13, r13
        jz 3f
        # a bytes getter: the variable of its length
        LOADS rdi, LENGTH
        mov rsi, [r13 + N_DATA]
        call mk2
        mov edi, (256 << 1) | 1
        mov esi, 1
        mov rdx, rax
        call mk3
        mov rdi, [rbx + SG_STEPS]
        mov rsi, rax
        call od_get
        test rax, rax
        jz .Lna_key
        lea rcx, [rip + sp_none]
        cmp rax, rcx
        je .Lna_unpack
        mov r13, rax                    # (n, sts)
        mov rdi, [rbx + SG_TYPES]
        mov rsi, [r13 + N_DATA]
        call od_get
        mov rdi, rax
        mov rsi, [r13 + N_DATA + 8]
        mov edx, (256 << 1) | 1
        mov ecx, 1
        call st_getter_path
        test eax, eax
        jz .Lna_func
        mov rsi, [r13 + N_DATA]
        jmp .Lna_root
3:      mov rdi, r12
        call st_getter_access
        test rax, rax
        jz .Lna_func
        mov [rsp + NA_A], rax
        LOADS rcx, ROOT
        cmp [rax + N_DATA], rcx
        jne 4f
        mov rsi, [rax + N_DATA + 8]
        jmp .Lna_root
4:      mov rdi, rbx                    # its steps
        mov rsi, rax
        call sg_steps_get
        test rax, rax
        jnz 5f
        mov rax, [rsp + NA_A]
        mov rdi, [rax + N_DATA + 16]
        mov rsi, [rbx + SG_LANG]
        call st_parse
        mov rdi, rax
        call st_steps
        test rax, rax
        jz .Lna_func
5:      mov r13, rax                    # (n, sts)
        mov rdi, [rbx + SG_FIELDS]
        mov rsi, [r13 + N_DATA]
        call od_get
        test rax, rax
        jz 6f
        mov rax, [r13 + N_DATA + 8]
        cmp dword ptr [rax + N_AUX], 0
        jne 6f
        mov rax, [rsp + NA_A]           # ('field', n, off, off + size)
        mov rdi, [rax + N_DATA + 8]
        mov rsi, [rax + N_DATA]
        call st_int_add_checked
        mov rcx, rax
        mov rax, [rsp + NA_A]
        mov rdx, [rax + N_DATA + 8]
        mov rsi, [r13 + N_DATA]
        LOADS rdi, FIELD
        call mk4
        mov rdi, [rsp + NA_GETTERS]
        mov rsi, rax
        mov rdx, [rsp + NA_NAME]
        call st_od_setdefault
        jmp .Lna_func
6:      mov rdi, [rbx + SG_TYPES]
        mov rsi, [r13 + N_DATA]
        call od_get
        mov rdi, rax
        mov rsi, [r13 + N_DATA + 8]
        mov rax, [rsp + NA_A]
        mov rdx, [rax + N_DATA]
        mov rcx, [rax + N_DATA + 8]
        call st_getter_path
        test eax, eax
        jz .Lna_func
        mov rsi, [r13 + N_DATA]
.Lna_root:
        LOADS rdi, ROOT                 # getters.setdefault(('root', n), name)
        call mk2
        mov rdi, [rsp + NA_GETTERS]
        mov rsi, rax
        mov rdx, [rsp + NA_NAME]
        call st_od_setdefault
        jmp .Lna_func
.Lna_defs:
        call od_new
        mov [rbx + SG_DEFS], rax
        call od_new
        mov [rbx + SG_VAR_OF], rax
        call od_new
        mov [rsp + NA_TAKEN], rax
        call vec_new                    # sorted(set(types) | set(fields))
        mov [rsp + NA_KEYS], rax
        mov r12, [rbx + SG_TYPES]
        call .Lna_keys
        mov r12, [rbx + SG_FIELDS]
        call .Lna_keys
        mov rdi, [rsp + NA_KEYS]
        lea rsi, [rip + py_lt]
        xor edx, edx
        call py_sort
        mov qword ptr [rsp + NA_I], 0
.Lna_n:
        mov rax, [rsp + NA_KEYS]
        mov rcx, [rsp + NA_I]
        cmp rcx, [rax + VEC_LEN]
        jae .Lna_done
        mov rax, [rax + VEC_DATA]
        mov rax, [rax + rcx*8]
        mov [rsp + NA_N], rax
        inc qword ptr [rsp + NA_I]
        mov rdi, [rbx + SG_FIELDS]
        mov rsi, rax
        call od_get
        test rax, rax
        jz .Lna_root_def
        mov [rsp + NA_FLD], rax
        mov qword ptr [rsp + NA_J], 0
1:      mov rax, [rsp + NA_FLD]
        mov rcx, [rsp + NA_J]
        cmp ecx, [rax + N_AUX]
        jae .Lna_n
        mov r12, [rax + N_DATA + rcx*8] # (off, end)
        inc qword ptr [rsp + NA_J]
        LOADS rdi, FIELD
        mov rsi, [rsp + NA_N]
        mov rdx, [r12 + N_DATA]
        mov rcx, [r12 + N_DATA + 8]
        call mk4
        mov r13, rax                    # ('field', n, off, end)
        mov rdi, [rsp + NA_GETTERS]
        mov rsi, rax
        call od_get
        test rax, rax
        jnz 2f
        mov rdi, [rsp + NA_N]
        mov rsi, [r12 + N_DATA]
        call st_default_name
2:      mov rdi, [rsp + NA_TAKEN]
        mov rsi, rax
        mov rdx, [rsp + NA_N]
        call st_unique
        mov r14, rax
        mov rdi, [rbx + SG_VAR_OF]
        mov rsi, r13
        mov rdx, rax
        call od_put
        mov rdi, [r12 + N_DATA + 8]     # (n, off, ('value', end - off))
        mov rsi, [r12 + N_DATA]
        call int_sub
        mov rsi, rax
        LOADS rdi, VALUE
        call mk2
        mov rdx, rax
        mov rdi, [rsp + NA_N]
        mov rsi, [r12 + N_DATA]
        call mk3
        mov rdi, [rbx + SG_DEFS]
        mov rsi, r14
        mov rdx, rax
        call od_put
        jmp 1b
.Lna_root_def:
        LOADS rdi, ROOT
        mov rsi, [rsp + NA_N]
        call mk2
        mov r13, rax
        mov rdi, [rsp + NA_GETTERS]
        mov rsi, rax
        call od_get
        test rax, rax
        jnz 3f
        mov rdi, [rsp + NA_N]
        mov esi, 1
        call st_default_name
3:      mov rdi, [rsp + NA_TAKEN]
        mov rsi, rax
        mov rdx, [rsp + NA_N]
        call st_unique
        mov r14, rax
        mov rdi, [rbx + SG_VAR_OF]
        mov rsi, r13
        mov rdx, rax
        call od_put
        mov rdi, [rbx + SG_TYPES]
        mov rsi, [rsp + NA_N]
        call od_get
        mov rdx, rax
        mov rdi, [rsp + NA_N]
        mov esi, 1
        call mk3
        mov rdi, [rbx + SG_DEFS]
        mov rsi, r14
        mov rdx, rax
        call od_put
        jmp .Lna_n
.Lna_done:
        add rsp, 112
        LEAVE
.Lna_key:
        mov edi, E_KEY
        lea rsi, [rip + .Ls_key_length]
        call err_throw
.Lna_unpack:
        mov edi, E_TYPE
        lea rsi, [rip + .Ls_unpack_none]
        call err_throw
# the keys of the od r12 added to NA_KEYS, once each
.Lna_keys:
        push r13
        push r14
        sub rsp, 8
        xor r13d, r13d
1:      mov rdi, r12
        call od_len
        cmp r13, rax
        jae 2f
        mov rdi, r12
        mov rsi, r13
        call od_key
        inc r13
        mov rdi, [rsp + 32 + NA_KEYS]
        mov rsi, rax
        call set_add
        jmp 1b
2:      add rsp, 8
        pop r14
        pop r13
        ret
ENDF sg_names

# --- the printed accesses ---

# sg_path_form(sg, n, sts, size, off) -> rax: python's Storage.path_form,
# 0 for a Fail
FUNC sg_path_form
        ENTER
        sub rsp, 48
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov [rsp], rcx                  # size
        mov [rsp + 8], r8               # off
        mov rdi, [rbx + SG_FIELDS]
        mov rsi, r12
        call od_get
        test rax, rax
        jz 5f
        mov r14, rax                    # a root of values: off in one of them
        cmp dword ptr [r13 + N_AUX], 0
        jne 8f
        mov rdi, [rsp + 8]
        call is_int
        test eax, eax
        jz 8f
        mov rdi, [rsp + 8]
        mov rsi, [rsp]
        call int_add
        mov [rsp + 16], rax             # off + size
        xor r13d, r13d
1:      cmp r13d, [r14 + N_AUX]
        jae 8f
        mov rax, [r14 + N_DATA + r13*8]
        mov [rsp + 24], rax             # (o, e)
        inc r13d
        mov rdi, [rax + N_DATA]
        mov rsi, [rsp + 8]
        call int_cmp
        cmp eax, 1
        je 1b
        mov rax, [rsp + 24]
        mov rdi, [rsp + 16]
        mov rsi, [rax + N_DATA + 8]
        call int_cmp
        cmp eax, 1
        je 1b
        mov rax, [rsp + 24]             # form(('sv', name), ('value', e - o),
        LOADS rdi, FIELD                # [], size, off - o)
        mov rsi, r12
        mov rdx, [rax + N_DATA]
        mov rcx, [rax + N_DATA + 8]
        call mk4
        mov rdi, [rbx + SG_VAR_OF]
        mov rsi, rax
        call od_get
        mov rsi, rax
        LOADS rdi, SV
        call mk2
        mov [rsp + 32], rax
        mov rax, [rsp + 24]
        mov rdi, [rax + N_DATA + 8]
        mov rsi, [rax + N_DATA]
        call int_sub
        mov rsi, rax
        LOADS rdi, VALUE
        call mk2
        mov [rsp + 40], rax
        mov rax, [rsp + 24]
        mov rdi, [rsp + 8]
        mov rsi, [rax + N_DATA]
        call int_sub
        mov r8, rax
        xor edi, edi
        xor esi, esi
        push r8
        push r8
        call mk_list
        pop r8
        pop r8
        mov rdx, rax
        mov rdi, [rsp + 32]
        mov rsi, [rsp + 40]
        mov rcx, [rsp]
        call st_form
        jmp 9f
5:      LOADS rdi, ROOT
        mov rsi, r12
        call mk2
        mov rdi, [rbx + SG_VAR_OF]
        mov rsi, rax
        call od_get
        test rax, rax
        jz 8f
        mov rsi, rax
        LOADS rdi, SV
        call mk2
        mov r14, rax
        mov rdi, [rbx + SG_TYPES]
        mov rsi, r12
        call od_get
        mov rsi, rax
        mov rdi, r14
        mov rdx, r13
        mov rcx, [rsp]
        mov r8, [rsp + 8]
        call st_form
        jmp 9f
8:      xor eax, eax
9:      add rsp, 48
        LEAVE
ENDF sg_path_form

# sg_form(sg, size, off, idx, write) -> rax: python's Storage.form - the
# printed access, checked, else raw
FUNC sg_form
        ENTER
        sub rsp, 48
        .set SF_SIZE, 0
        .set SF_OFF, 8
        .set SF_IDX, 16
        .set SF_WRITE, 24
        mov rbx, rdi
        mov [rsp + SF_SIZE], rsi
        mov [rsp + SF_OFF], rdx
        mov [rsp + SF_IDX], rcx
        mov [rsp + SF_WRITE], r8
        mov rdi, rsi
        mov rsi, rdx
        mov rdx, rcx
        call mk3
        mov rdi, rbx
        mov rsi, rax
        call sg_steps_get
        test rax, rax
        jz .Lsf_raw
        mov r13, rax
        mov rdi, [rsp + SF_SIZE]
        call is_int
        test eax, eax
        jz .Lsf_raw
        mov rdi, rbx
        mov rsi, [r13 + N_DATA]
        mov rdx, [r13 + N_DATA + 8]
        mov rcx, [rsp + SF_SIZE]
        mov r8, [rsp + SF_OFF]
        call sg_path_form
        mov r12, rax                    # f, or 0
        test rax, rax
        jz .Lsf_raw
        cmp qword ptr [rsp + SF_WRITE], 0
        je 2f
        # some bits of a variable at the bit 0 of its slot
        mov rdi, r12
        call opcode_of
        cmp eax, OP_MASK_SHL
        jne 1f
        mov r14, [r12 + N_DATA + 32]
        mov rdi, r14
        call opcode_of
        cmp eax, OP_ST
        jne 1f
        mov r14, [r14 + N_DATA + 16]
        mov rdi, r14
        call opcode_of
        cmp eax, OP_SV
        jne 1f
        mov rdi, [rbx + SG_DEFS]
        mov rsi, [r14 + N_DATA + 8]
        call od_get
        test rax, rax
        jz .Lsf_key
        cmp qword ptr [rax + N_DATA + 8], 1
        jne 1f
        LOADS rdi, SF                   # ('st', size, ('sf', sv, off), 256 - off)
        mov rsi, r14
        mov rdx, [rsp + SF_OFF]
        call mk3
        mov r12, rax
        mov edi, (256 << 1) | 1
        mov rsi, [rsp + SF_OFF]
        call int_sub
        mov rdx, rax
        mov rdi, [rsp + SF_SIZE]
        mov rsi, r12
        call st_mk_st
        mov r12, rax
1:      mov rdi, r12                    # a write: an st only
        call opcode_of
        cmp eax, OP_ST
        jne .Lsf_raw
2:      mov rdi, r12
        mov rsi, [rsp + SF_SIZE]
        mov rdx, [rsp + SF_OFF]
        mov rcx, [rsp + SF_IDX]
        mov r8, [rbx + SG_DEFS]
        mov r9, [rbx + SG_LANG]
        call ck_checks
        test eax, eax
        jnz 3f
        mov rdi, [rsp + SF_SIZE]
        mov rsi, [rsp + SF_OFF]
        mov rdx, [rsp + SF_IDX]
        call mk3
        mov rcx, rax
        mov edi, LOG_WARNING
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_no_read]
        mov r8, r12
        call log_fmt
        jmp .Lsf_raw
3:      mov rax, r12
        add rsp, 48
        LEAVE
.Lsf_raw:
        mov rdi, [rsp + SF_SIZE]
        mov rsi, [rsp + SF_OFF]
        mov rdx, [rsp + SF_IDX]
        mov rcx, [rsp + SF_WRITE]
        call st_raw
        add rsp, 48
        LEAVE
.Lsf_key:
        mov edi, E_KEY
        lea rsi, [rip + .Ls_key_length]
        call err_throw
ENDF sg_form

# sg_header(sg) -> list: python's Storage.header - the definitions, as the
# output lists them: ('sdef', name, slot, off, type), by (slot, off, name)
FUNC sg_header
        ENTER
        sub rsp, 16
        mov rbx, rdi
        call vec_new
        mov r12, rax                    # (slot, off, name, type) to sort
        xor r13d, r13d
1:      mov rdi, [rbx + SG_DEFS]
        call od_len
        cmp r13, rax
        jae 3f
        mov rdi, [rbx + SG_DEFS]
        mov rsi, r13
        call od_key
        mov r14, rax
        mov rdi, [rbx + SG_DEFS]
        mov rsi, r13
        call od_val
        inc r13
        mov rdi, [rax + N_DATA]
        mov rsi, [rax + N_DATA + 8]
        mov rdx, r14
        mov rcx, [rax + N_DATA + 16]
        call mk4
        mov rdi, r12
        mov rsi, rax
        call vec_push
        jmp 1b
3:      mov rdi, r12
        lea rsi, [rip + st_def_lt]
        xor edx, edx
        call py_sort
        call vec_new
        mov r13, rax
        xor r14d, r14d
4:      cmp r14, [r12 + VEC_LEN]
        jae 6f
        mov rax, [r12 + VEC_DATA]
        mov rax, [rax + r14*8]
        mov [rsp], rax
        inc r14
        mov rcx, [rax + N_DATA + 24]    # t, with the length of a fixed array
        mov [rsp + 8], rcx
        mov rdi, rcx
        call opcode_of
        cmp eax, OP_FIXED
        jne 5f
        mov rax, [rsp]
        mov rdi, [rbx + SG_LENGTHS]
        mov rsi, [rax + N_DATA]
        call od_get
        test rax, rax
        jz 5f
        call vec_new
        push rax
        push rax
        mov rdi, rax
        mov rsi, [rsp + 16 + 8]
        call vec_extend_seq
        mov rax, [rsp + 16]
        mov rdi, [rbx + SG_LENGTHS]
        mov rsi, [rax + N_DATA]
        call od_get
        mov rdi, [rsp]
        mov rsi, rax
        call vec_push
        pop rdi
        pop rdi
        call vec_to_tuple
        mov [rsp + 8], rax
5:      mov rax, [rsp]
        LOADS rdi, SDEF
        mov rsi, [rax + N_DATA + 16]
        mov rdx, [rax + N_DATA]
        mov rcx, [rax + N_DATA + 8]
        mov r8, [rsp + 8]
        call mk5
        mov rdi, r13
        mov rsi, rax
        call vec_push
        jmp 4b
6:      mov rdi, r13
        call vec_to_list
        add rsp, 16
        LEAVE
ENDF sg_header

# st_def_lt(a, b, arg) -> eax: (slot, off, name) of a < b's
FUNC st_def_lt
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov edi, 3
        lea rsi, [rbx + N_DATA]
        call mk_tuple
        mov r13, rax
        mov edi, 3
        lea rsi, [r12 + N_DATA]
        call mk_tuple
        mov rdi, r13
        mov rsi, rax
        xor edx, edx
        call py_lt
        add rsp, 16
        LEAVE
ENDF st_def_lt

# --- the traces rewritten ---

# sg_get_form(sg, size, off, idx, write) -> rax: the form of an access,
# made once per rewrite (python's rewrite_accesses.get)
FUNC sg_get_form
        ENTER
        sub rsp, 48
        mov rbx, rdi
        mov [rsp], rsi
        mov [rsp + 8], rdx
        mov [rsp + 16], rcx
        mov [rsp + 24], r8
        lea rax, [rip + sp_false]
        lea rcx, [rip + sp_true]
        test r8, r8
        cmovnz rax, rcx
        mov rdi, rsi
        mov rsi, rdx
        mov rdx, [rsp + 16]
        mov rcx, rax
        call mk4
        mov r12, rax                    # the key
        mov rdi, [rbx + SG_FORMS]
        mov rsi, rax
        call map_get
        test rax, rax
        jnz 9f
        cmp qword ptr [rbx + SG_FORMFN], 0
        jne 1f
        mov rdi, rbx
        mov rsi, [rsp]
        mov rdx, [rsp + 8]
        mov rcx, [rsp + 16]
        mov r8, [rsp + 24]
        call sg_form
        jmp 2f
1:      mov rdi, [rsp]
        mov rsi, [rsp + 8]
        mov rdx, [rsp + 16]
        mov rcx, [rsp + 24]
        call st_raw
2:      mov r13, rax
        mov rdi, [rbx + SG_FORMS]
        mov rsi, r12
        mov rdx, rax
        call map_put
        mov rax, r13
9:      add rsp, 48
        LEAVE
ENDF sg_get_form

# sg_rewrite(sg, trace) -> trace: python's rewrite_accesses - the trace
# with each access as the form of it (sg_form, or raw: SG_FORMFN)
FUNC sg_rewrite
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call map_new
        mov [rbx + SG_FORMS], rax
        call map_new
        mov [rbx + SG_MEMO], rax
        mov rdi, rbx
        mov rsi, r12
        call sg_rw
        LEAVE
ENDF sg_rewrite

# sg_rw(sg, exp) -> value: rewrite_accesses' f (each subtree once: the walk
# is a pure function of it, in python's order)
FUNC sg_rw
        STACK_CHECK
        ENTER
        sub rsp, 48
        mov rbx, rdi
        mov r12, rsi
        test r12b, 1
        jnz .Lrw_leaf
        test r12, r12
        jz .Lrw_leaf
        mov eax, [r12 + N_KIND]
        cmp eax, K_TUPLE
        je 1f
        cmp eax, K_LIST
        jne .Lrw_leaf
1:      mov rdi, [rbx + SG_MEMO]
        mov rsi, r12
        call map_get
        test rax, rax
        jnz .Lrw_ret
        cmp dword ptr [r12 + N_KIND], K_LIST
        je .Lrw_elems
        mov rdi, r12
        call opcode_of
        cmp eax, OP_STORAGE
        jne 2f
        cmp dword ptr [r12 + N_AUX], 4
        jne .Lrw_elems
        mov rdi, rbx                    # f(get(size, off, idx, False))
        mov rsi, [r12 + N_DATA + 8]
        mov rdx, [r12 + N_DATA + 16]
        mov rcx, [r12 + N_DATA + 24]
        xor r8d, r8d
        call sg_get_form
        mov rdi, rbx
        mov rsi, rax
        call sg_rw
        jmp .Lrw_done
2:      cmp eax, OP_STORE
        jne .Lrw_elems
        cmp dword ptr [r12 + N_AUX], 5
        jne .Lrw_elems
        mov rdi, rbx
        mov rsi, [r12 + N_DATA + 8]
        mov rdx, [r12 + N_DATA + 16]
        mov rcx, [r12 + N_DATA + 24]
        mov r8d, 1
        call sg_get_form
        mov r13, rax                    # target
        mov rdi, rax
        call opcode_of
        cmp eax, OP_ST
        jne .Lrw_whole
        cmp dword ptr [r13 + N_AUX], 2
        jb .Lrw_index
        mov rdi, [r13 + N_DATA + 8]
        call is_int
        test eax, eax
        jz .Lrw_whole
        cmp dword ptr [r13 + N_AUX], 3
        jb .Lrw_index
        mov r14, [r13 + N_DATA + 16]
        mov rdi, r14
        call opcode_of
        cmp eax, OP_SF
        jne 3f
        cmp dword ptr [r14 + N_AUX], 3
        jb .Lrw_index
        mov rdi, [r14 + N_DATA + 16]
        call is_int
        test eax, eax
        jz .Lrw_whole
3:      mov rdi, rbx                    # ('set', f(target), f(val))
        mov rsi, r13
        call sg_rw
        mov [rsp], rax
        mov rdi, rbx
        mov rsi, [r12 + N_DATA + 32]
        call sg_rw
        mov rdx, rax
        mov rsi, [rsp]
        LOADS rdi, SET
        call mk3
        jmp .Lrw_done
.Lrw_whole:
        # bits at an offset computed at runtime: the whole word
        LOADS rdi, SR
        mov rsi, [r12 + N_DATA + 24]
        call mk2
        mov edi, (256 << 1) | 1
        mov rsi, rax
        mov edx, (256 << 1) | 1
        call st_mk_st
        mov r13, rax                    # whole
        call st_word_mask
        mov r8, rax
        LOADS rdi, MASK_SHL             # mask = ('mask_shl', size, 0, off, M)
        mov rsi, [r12 + N_DATA + 8]
        mov edx, 1
        mov rcx, [r12 + N_DATA + 16]
        call mk5
        mov rsi, rax
        LOADS rdi, NOT
        call mk2
        mov rdx, rax
        LOADS rdi, AND
        mov rsi, r13
        call mk3
        mov r14, rax                    # ('and', whole, ('not', mask))
        LOADS rdi, MASK_SHL
        mov rsi, [r12 + N_DATA + 8]
        mov edx, 1
        mov rcx, [r12 + N_DATA + 16]
        mov r8, [r12 + N_DATA + 32]
        call mk5
        mov rdx, rax
        LOADS rdi, OR
        mov rsi, r14
        call mk3
        mov [rsp + 8], rax              # merged
        mov rdi, rbx
        mov rsi, r13
        call sg_rw
        mov [rsp], rax
        mov rdi, rbx
        mov rsi, [rsp + 8]
        call sg_rw
        mov rdx, rax
        mov rsi, [rsp]
        LOADS rdi, SET
        call mk3
        jmp .Lrw_done
.Lrw_elems:
        mov edi, [r12 + N_AUX]
        shl rdi, 3
        jz .Lrw_same
        call arena_alloc_raw
        mov r13, rax
        xor r14d, r14d
4:      cmp r14d, [r12 + N_AUX]
        jae 5f
        mov rdi, rbx
        mov rsi, [r12 + N_DATA + r14*8]
        call sg_rw
        mov [r13 + r14*8], rax
        inc r14d
        jmp 4b
5:      mov rdi, r12
        mov rsi, r13
        call mk_seq_like
        jmp .Lrw_done
.Lrw_same:
        mov rax, r12
.Lrw_done:
        mov r13, rax
        mov rdi, [rbx + SG_MEMO]
        mov rsi, r12
        mov rdx, rax
        call map_put
        mov rax, r13
        jmp .Lrw_ret
.Lrw_leaf:
        mov rax, r12
.Lrw_ret:
        add rsp, 48
        LEAVE
.Lrw_index:
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_gtindex]
        call err_throw
ENDF sg_rw

# st_word_mask() -> rax: M = 2**256 - 1
FUNC st_word_mask
        ENTER
        sub rsp, 32
        mov rax, -1
        mov [rsp], rax
        mov [rsp + 8], rax
        mov [rsp + 16], rax
        mov [rsp + 24], rax
        mov rdi, rsp
        call w_to_value
        add rsp, 32
        LEAVE
ENDF st_word_mask


# --- the whole contract ---

# st_rewrite_functions(functions, code, len) -> rax: python's
# rewrite_functions - the definitions (a list of ('sdef', name, slot, off,
# type)), rdx: the language (1: vyper); the functions' traces get the
# paths of the storage (FN_TRACE, function after function, as python's)
FUNC st_rewrite_functions
        ENTER
        sub rsp, 48
        .set RF_FUNCS, 0
        .set RF_CODE, 8
        .set RF_LEN, 16
        .set RF_LANG, 24
        .set RF_SG, 32
        mov [rsp + RF_FUNCS], rdi
        mov [rsp + RF_CODE], rsi
        mov [rsp + RF_LEN], rdx
        mov rbx, rdi
        xor r12d, r12d                  # the reads as wide as what's used of them
1:      cmp r12, [rbx + VEC_LEN]
        jae 2f
        mov rax, [rbx + VEC_DATA]
        mov r13, [rax + r12*8]
        inc r12
        mov rdi, [r13 + FN_TRACE]
        lea rsi, [rip + st_narrow]
        xor edx, edx
        call replace_f_memo
        mov [r13 + FN_TRACE], rax
        jmp 1b
2:      mov rdi, rbx
        call st_functions_accesses
        mov rdx, rax
        mov rdi, [rsp + RF_CODE]
        mov rsi, [rsp + RF_LEN]
        call st_language
        mov [rsp + RF_LANG], rax
        mov rdi, rbx                    # the stores of whole variables
        mov rsi, rax
        call rg_new
        mov r14, rax
        xor r12d, r12d
3:      cmp r12, [rbx + VEC_LEN]
        jae 4f
        mov rax, [rbx + VEC_DATA]
        mov r13, [rax + r12*8]
        inc r12
        mov rdi, r14
        mov rsi, [r13 + FN_TRACE]
        call rg_trace
        mov [r13 + FN_TRACE], rax
        jmp 3b
4:      mov rdi, rbx
        mov rsi, [rsp + RF_LANG]
        call sg_new
        mov [rsp + RF_SG], rax
        xor r12d, r12d
5:      cmp r12, [rbx + VEC_LEN]
        jae 7f
        mov rax, [rbx + VEC_DATA]
        mov r13, [rax + r12*8]
        inc r12
        mov rdi, [rsp + RF_SG]          # getter_trace(f) or rewrite(f.trace)
        mov rsi, r13
        call sg_getter_trace
        test rax, rax
        jz 6f
        cmp dword ptr [rax + N_AUX], 0
        jne 61f
6:      mov rdi, [rsp + RF_SG]
        mov rsi, [r13 + FN_TRACE]
        call sg_rewrite
61:     mov [r13 + FN_TRACE], rax
        jmp 5b
7:      mov rdi, [rsp + RF_SG]
        call sg_header
        mov rdx, [rsp + RF_LANG]
        add rsp, 48
        LEAVE
ENDF st_rewrite_functions

# st_rewrite_raw(functions): python's rewrite_raw - every access as the
# slot it is, when the paths can't be found
FUNC st_rewrite_raw
        ENTER
        mov rbx, rdi
        mov edi, SG_SIZEOF
        call arena_alloc
        mov r14, rax
        mov qword ptr [r14 + SG_FORMFN], 1
        xor r12d, r12d
1:      cmp r12, [rbx + VEC_LEN]
        jae 2f
        mov rax, [rbx + VEC_DATA]
        mov r13, [rax + r12*8]
        inc r12
        mov rdi, r14
        mov rsi, [r13 + FN_TRACE]
        call sg_rewrite
        mov [r13 + FN_TRACE], rax
        jmp 1b
2:      LEAVE
ENDF st_rewrite_raw

# --- the definitions, printed ---

        .section .rodata
.Ls_address:    .asciz "address"
.Ls_uint_t:     .asciz "uint"
.Ls_struct:     .asciz "struct"
.Ls_struct_of:  .asciz "struct of "
.Ls_slot:       .asciz " slot"
.Ls_mapping_of: .asciz "mapping of "
.Ls_array_of:   .asciz "array of "
.Ls_fixed_of:   .asciz "fixed array of "
.Ls_bytes_t:    .asciz "bytes"
.Ls_def_pfx:    .asciz "  "
.Ls_is:         .asciz " is "
.Ls_at_storage: .asciz "at storage "
.Ls_offset:     .asciz " offset "
        .text

# st_pretty_type_sb(sb, t): python's storage.pretty_type, appended
FUNC st_pretty_type_sb
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov rdi, rsi
        call opcode_of
        cmp eax, OP_VALUE
        je .Lpt_value
        cmp eax, OP_STRUCT
        je .Lpt_struct
        cmp eax, OP_MAPPING
        je .Lpt_mapping
        cmp eax, OP_ARRAY
        je .Lpt_array
        cmp eax, OP_FIXED
        je .Lpt_fixed
        cmp eax, OP_BYTES
        je .Lpt_bytes
        mov rdi, rbx                    # str(t)
        mov rsi, r12
        call value_print
        LEAVE
.Lpt_value:
        mov r13, [r12 + N_DATA + 8]
        cmp r13, (160 << 1) | 1
        jne 1f
        mov rdi, rbx
        lea rsi, [rip + .Ls_address]
        call sb_append_c
        LEAVE
1:      mov rdi, rbx
        lea rsi, [rip + .Ls_uint_t]
        call sb_append_c
        mov rdi, rbx
        mov rsi, r13
        call st_sb_str
        LEAVE
.Lpt_struct:
        mov r13, [r12 + N_DATA + 8]
        mov rdi, r13
        call is_none
        test eax, eax
        jz 1f
        mov rdi, rbx
        lea rsi, [rip + .Ls_struct]
        call sb_append_c
        LEAVE
1:      mov rdi, rbx                    # struct of {n} slot(s)
        lea rsi, [rip + .Ls_struct_of]
        call sb_append_c
        mov rdi, rbx
        mov rsi, r13
        call st_sb_str
        mov rdi, rbx
        lea rsi, [rip + .Ls_slot]
        call sb_append_c
        mov rdi, r13
        mov esi, 3
        call py_equal
        test eax, eax
        jnz 2f
        mov rdi, rbx
        mov esi, 's'
        call sb_append_char
2:      LEAVE
.Lpt_mapping:
        lea rsi, [rip + .Ls_mapping_of]
        jmp .Lpt_of
.Lpt_array:
        lea rsi, [rip + .Ls_array_of]
.Lpt_of:
        mov rdi, rbx
        call sb_append_c
        mov rdi, rbx
        mov rsi, [r12 + N_DATA + 8]
        call st_pretty_type_sb
        LEAVE
.Lpt_fixed:
        cmp dword ptr [r12 + N_AUX], 3
        jbe 2f
        mov rdi, [r12 + N_DATA + 8]     # with its length: a value's t[length]
        call opcode_of
        cmp eax, OP_VALUE
        jne 1f
        mov rdi, rbx
        mov rsi, [r12 + N_DATA + 8]
        call st_pretty_type_sb
        mov rdi, rbx
        mov esi, '['
        call sb_append_char
        mov rdi, rbx
        mov rsi, [r12 + N_DATA + 24]
        call st_sb_str
        mov rdi, rbx
        mov esi, ']'
        call sb_append_char
        LEAVE
1:      mov rdi, rbx                    # fixed array of {length} {t}
        lea rsi, [rip + .Ls_fixed_of]
        call sb_append_c
        mov rdi, rbx
        mov rsi, [r12 + N_DATA + 24]
        call st_sb_str
        mov rdi, rbx
        mov esi, ' '
        call sb_append_char
        mov rdi, rbx
        mov rsi, [r12 + N_DATA + 8]
        call st_pretty_type_sb
        LEAVE
2:      lea rsi, [rip + .Ls_fixed_of]
        jmp .Lpt_of
.Lpt_bytes:
        mov rdi, rbx
        lea rsi, [rip + .Ls_bytes_t]
        call sb_append_c
        LEAVE
ENDF st_pretty_type_sb

# st_sb_str(sb, v): python's str(v) appended
FUNC st_sb_str
        ENTER
        mov rbx, rdi
        mov rdi, rsi
        call value_str
        mov rdi, rbx
        mov rsi, rax
        call sb_append_str
        LEAVE
ENDF st_sb_str

# st_pretty_type(t) -> str: python's storage.pretty_type
FUNC st_pretty_type
        ENTER
        mov rbx, rdi
        call sb_new
        mov r12, rax
        mov rdi, rax
        mov rsi, rbx
        call st_pretty_type_sb
        mov rdi, r12
        call sb_finish
        LEAVE
ENDF st_pretty_type

# st_pretty_def(d) -> str: python's storage.pretty_def - a line of the
# definitions, ('sdef', name, slot, off, type): `  name is type at storage
# slot offset off` (colored)
FUNC st_pretty_def
        ENTER
        mov rbx, rdi
        call sb_new
        mov r12, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_def_pfx]
        call sb_append_c
        mov rdi, r12
        lea rsi, [rip + C_GREEN]
        call sb_append_c
        mov rdi, r12
        mov rsi, [rbx + N_DATA + 8]
        call st_sb_str
        mov rdi, r12
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        mov rdi, r12
        lea rsi, [rip + .Ls_is]
        call sb_append_c
        mov rdi, r12
        mov rsi, [rbx + N_DATA + 32]
        call st_pretty_type_sb
        mov rdi, r12
        mov esi, ' '
        call sb_append_char
        mov rdi, r12
        lea rsi, [rip + C_GRAY]
        call sb_append_c
        mov rdi, r12
        lea rsi, [rip + .Ls_at_storage]
        call sb_append_c
        mov r13, [rbx + N_DATA + 16]    # hex(slot) for 2**32 and up
        mov rdi, r13
        mov rsi, (1 << 33) | 1
        call int_cmp
        mov edx, 10
        cmp eax, -1
        je 1f
        mov edx, 16
1:      mov rdi, r12
        mov rsi, r13
        call sb_append_int
        mov r13, [rbx + N_DATA + 24]    # offset, if not 0
        mov rdi, r13
        call py_truthy
        test eax, eax
        jz 2f
        mov rdi, r12
        lea rsi, [rip + .Ls_offset]
        call sb_append_c
        mov rdi, r12
        mov rsi, r13
        call st_sb_str
2:      mov rdi, r12
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        mov rdi, r12
        call sb_finish
        LEAVE
ENDF st_pretty_def

        .section .note.GNU-stack,"",@progbits
