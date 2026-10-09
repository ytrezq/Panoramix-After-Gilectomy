# The getters of a bytes (or string) of the storage (storage.py's
# bytes_getter, bytes_tail, splits, getter_trace): a function that returns
# the bytes at a slot, ABI-encoded, whatever its code is - which is
# checked by running it (runtrace.s) and a rewrite of it, `return
# Array(len=b.length, data=b[all])` after a first part of it (its checks
# of the params), on bytes as the compiler keeps them, short and long, of
# every length the code may treat apart, with params clean and dirty.

.include "defs.inc"
.include "storage.inc"

.set MT_SIZEOF, 8 + 4 * 624     # (blake2b.s's)

# a world of bytes_tail: a calldata and the content of the bytes
.set BW_CD, 0
.set BW_CDLEN, 8
.set BW_CONTENT, 16
.set BW_CLEN, 24
.set BW_SIZEOF, 32

# a run's result (the original trace's, per world)
.set BR_KIND, 0                 # 0: None (the run couldn't be made)
.set BR_DATA, 8
.set BR_DLEN, 16
.set BR_REACHED, 24
.set BR_SIZEOF, 32

# bytes_tail's state (also the world's user: python's run's closure)
.set BT_TRACE, 0
.set BT_KEY, 8
.set BT_WORLDS, 16              # BW_* records
.set BT_NWORLDS, 24
.set BT_ORIG, 32                # BR_* records
.set BT_M, 40                   # the machine
.set BT_WORDS, 48               # an emap: slot -> word (the words of the bytes)
.set BT_CONTENT, 56             # the world being run
.set BT_CLEN, 64
.set BT_REACHED, 72
.set BT_N, 80                   # the candidates tried
.set BT_RESULT, 88              # the one found
.set BT_TAIL, 96
.set BT_SIZEOF, 104

        .section .data.rel.ro
        .align 8
bt_world:       .quad bt_sload, bt_bytes_length, bt_bytes_data
        .section .rodata
.Ls_another:    .asciz "another slot"
.Ls_overflow:   .asciz "int too big to convert"
.Ls_tindex:     .asciz "tuple index out of range"
bt_lengths:     .quad 0, 1, 2, 30, 31, 32, 33, 63, 64, 65, 96, 97, 300
.set BT_NLENGTHS, 13
        .text

# bt_sload(bt, slot) -> value: the word at the slot (Unsupported for
# another one)
FUNC bt_sload
        ENTER
        mov rdi, [rdi + BT_WORDS]
        call emap_get
        test rax, rax
        jz 1f
        LEAVE
1:      mov edi, E_UNSUPPORTED
        lea rsi, [rip + .Ls_another]
        call err_throw
ENDF bt_sload

# bt_bytes_length(bt, slot) -> value: (v - 1) // 2 if v & 1 else (v & 0xFF) // 2
FUNC bt_bytes_length
        ENTER
        sub rsp, 32
        call bt_sload
        mov rsi, rax
        mov rdi, rsp
        call w_from_value
        mov rax, [rsp]
        test al, 1
        jz 1f
        dec qword ptr [rsp]             # (odd: no borrow)
        jmp 2f
1:      and qword ptr [rsp], 0xff
        xor eax, eax
        mov [rsp + 8], rax
        mov [rsp + 16], rax
        mov [rsp + 24], rax
2:      mov rdi, rsp
        mov rsi, rsp
        mov edx, 1
        call w_shr
        mov rdi, rsp
        call w_to_value
        add rsp, 32
        LEAVE
ENDF bt_bytes_length

# bt_bytes_data(bt, slot) -> rax: the content, rdx: its length (reached)
FUNC bt_bytes_data
        mov qword ptr [rdi + BT_REACHED], 1
        mov rax, [rdi + BT_CONTENT]
        mov rdx, [rdi + BT_CLEN]
        ret
ENDF bt_bytes_data

# bt_word_be(bytes, n) -> value: the int of up to 32 big-endian bytes,
# padded with zeros on the right to 32 (python's padded.ljust(32))
FUNC bt_word_be
        ENTER
        sub rsp, 32
        mov rbx, rdi
        mov r12, rsi
        mov rdi, rsp
        xor esi, esi
        mov edx, 32
        call memset@PLT
        test r12, r12
        jz 1f
        mov rdi, rsp
        mov rsi, rbx
        mov rdx, r12
        call memcpy@PLT
1:      mov rdi, rsp
        mov esi, 32
        call mk_int_bytes_be
        add rsp, 32
        LEAVE
ENDF bt_word_be

# bt_run(bt, trace, world) -> eax: python's bytes_tail.run - 1 when the run
# could be made (the machine's RM_KIND, RM_DATA, RM_DLEN; BT_REACHED),
# 0 for None (the exceptions it catches)
FUNC bt_run
        ENTER
        sub rsp, ERR_SIZEOF + 48
        .set BU_TRACE, ERR_SIZEOF
        .set BU_SLOT, ERR_SIZEOF + 8
        .set BU_I, ERR_SIZEOF + 16
        .set BU_BASE, ERR_SIZEOF + 24
        .set BU_PLEN, ERR_SIZEOF + 32
        mov rbx, rdi
        mov [rsp + BU_TRACE], rsi
        mov r12, rdx
        mov rax, [r12 + BW_CONTENT]
        mov [rbx + BT_CONTENT], rax
        mov rax, [r12 + BW_CLEN]
        mov [rbx + BT_CLEN], rax
        mov qword ptr [rbx + BT_REACHED], 0
        mov rdi, [rbx + BT_WORDS]       # (python's words = {}: the map emptied)
        call emap_begin
        mov rdi, [rbx + BT_M]
        mov rsi, [r12 + BW_CD]
        mov rdx, [r12 + BW_CDLEN]
        call rt_machine_reset
        mov rdi, rsp
        call err_catch
        test eax, eax
        jnz .Lbu_caught
        mov rdi, [rbx + BT_M]           # slot = m.ev(key)
        mov rsi, [rbx + BT_KEY]
        call rt_ev
        mov [rsp + BU_SLOT], rax
        mov r13, [rbx + BT_CLEN]
        mov rax, r13                    # the padded length
        add rax, 31
        and rax, -32
        mov [rsp + BU_PLEN], rax
        cmp r13, 32
        jae 2f
        # a short one: its bytes, and twice its length in the low byte
        mov rdi, [rbx + BT_CONTENT]
        mov rsi, r13
        call bt_word_be
        mov rdi, rax
        lea rsi, [r13 + r13]
        TAG rsi
        call st_int_or
        mov rdx, rax
        mov rdi, [rbx + BT_WORDS]
        mov rsi, [rsp + BU_SLOT]
        call emap_put
        jmp 4f
2:      # a long one: 2 * length + 1, the words at keccak(slot) + i
        lea rdx, [r13 + r13 + 1]
        mov rdi, rdx
        call mk_int_u64
        mov rdx, rax
        mov rdi, [rbx + BT_WORDS]
        mov rsi, [rsp + BU_SLOT]
        call emap_put
        mov rdi, [rsp + BU_SLOT]
        call rt_keccak_word
        mov [rsp + BU_BASE], rax
        mov qword ptr [rsp + BU_I], 0
3:      mov rax, [rsp + BU_I]           # i in range(len(padded) // 32 + 1)
        shl rax, 5
        cmp rax, [rsp + BU_PLEN]
        ja 4f
        mov rsi, [rsp + BU_PLEN]        # the chunk (none past the end)
        sub rsi, rax
        cmp rsi, 32
        jbe 31f
        mov esi, 32
31:     mov rcx, r13                    # (the content's bytes in it, the
        sub rcx, rax                    # rest zeros)
        jg 32f
        xor ecx, ecx
32:     cmp rcx, rsi
        jbe 33f
        mov rcx, rsi
33:     mov rdi, [rbx + BT_CONTENT]
        add rdi, rax
        mov rsi, rcx
        call bt_word_be
        mov r14, rax
        mov rdi, [rsp + BU_BASE]
        mov rsi, [rsp + BU_I]
        TAG rsi
        call int_add
        mov rdi, rax
        mov esi, 256
        call int_mod_2exp
        mov rdi, [rbx + BT_WORDS]
        mov rsi, rax
        mov rdx, r14
        call emap_put
        inc qword ptr [rsp + BU_I]
        jmp 3b
4:      mov rdi, [rbx + BT_M]
        mov rsi, [rsp + BU_TRACE]
        call rt_run
        call err_end
        mov eax, 1
        add rsp, ERR_SIZEOF + 48
        LEAVE
.Lbu_caught:
        cmp eax, E_UNSUPPORTED
        je 1f
        cmp eax, E_RECURSION
        je 1f
        cmp eax, E_VALUE
        je 1f
        cmp eax, E_OVERFLOW
        je 1f
        cmp eax, E_KEY
        je 1f
        mov edi, eax
        mov rsi, [r15 + CTX_ERR_MSG]
        call err_throw
1:      xor eax, eax
        add rsp, ERR_SIZEOF + 48
        LEAVE
ENDF bt_run

# st_int_or(a, b) -> value: a | b of two non-negative ints
FUNC st_int_or
        ENTER
        call arith_load
        lea rdi, [r15 + CTX_MPZ_R]
        lea rsi, [r15 + CTX_MPZ_A]
        lea rdx, [r15 + CTX_MPZ_B]
        call __gmpz_ior@PLT
        call arith_result
        LEAVE
ENDF st_int_or

# bt_collect_ints(exp, set): python's find_f_list(trace, ints in (0, 4096))
# - the numbers, into a byte set of 4096
FUNC bt_collect_ints
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        test bl, 1
        jz 1f
        mov rax, rbx
        sar rax, 1
        jle 9f
        cmp rax, 4096
        jge 9f
        mov byte ptr [r12 + rax], 1
        jmp 9f
1:      test rbx, rbx
        jz 9f
        mov eax, [rbx + N_KIND]
        cmp eax, K_TUPLE
        je 2f
        cmp eax, K_LIST
        jne 9f
2:      xor r13d, r13d
3:      cmp r13d, [rbx + N_AUX]
        jae 9f
        mov rdi, [rbx + N_DATA + r13*8]
        inc r13d
        mov rsi, r12
        call bt_collect_ints
        jmp 3b
9:      LEAVE
ENDF bt_collect_ints

# bt_worlds(bt, trace, selector): python's worlds of bytes_tail - the
# lengths (13, and about the numbers of the code), contents from
# random.Random(0), params clean and dirty, and of the numbers the code
# compares with (bt_near); two calldatas too short
FUNC bt_worlds
        ENTER
        sub rsp, 112
        .set BX_SEL, 0
        .set BX_SET, 8                  # the numbers (a byte each, 4096 + 2)
        .set BX_AROUND, 16              # around - lengths, sorted (a byte set)
        .set BX_LENS, 24                # the lengths (a vec of u64)
        .set BX_MT, 32
        .set BX_I, 40
        .set BX_W, 48
        .set BX_TRACE, 56
        .set BX_NEAR, 64                # bt_near's numbers
        .set BX_WORD, 80                # (32 bytes)
        mov rbx, rdi
        mov [rsp + BX_SEL], rdx
        mov [rsp + BX_TRACE], rsi
        mov r12, rsi
        mov edi, 4096 + 16
        call arena_alloc
        mov [rsp + BX_SET], rax
        mov rdi, r12
        mov rsi, rax
        call bt_collect_ints
        mov edi, 4096 + 16
        call arena_alloc
        mov [rsp + BX_AROUND], rax
        mov r12, rax
        mov r13, [rsp + BX_SET]
        xor ecx, ecx                    # around |= {c-1, c, c+1, c//2, c//2+1}
1:      cmp ecx, 4096
        jae 2f
        cmp byte ptr [r13 + rcx], 0
        je 11f
        mov byte ptr [r12 + rcx - 1], 1
        mov byte ptr [r12 + rcx], 1
        mov byte ptr [r12 + rcx + 1], 1
        mov eax, ecx
        shr eax, 1
        mov byte ptr [r12 + rax], 1
        mov byte ptr [r12 + rax + 1], 1
11:     inc ecx
        jmp 1b
2:      call vec_new
        mov [rsp + BX_LENS], rax
        xor r14d, r14d
3:      cmp r14d, BT_NLENGTHS
        jae 4f
        lea rax, [rip + bt_lengths]
        mov rsi, [rax + r14*8]
        mov byte ptr [r12 + rsi], 0     # (around - set(lengths))
        mov rdi, [rsp + BX_LENS]
        call vec_push
        inc r14d
        jmp 3b
4:      xor ecx, ecx                    # sorted(...)[:48]
        xor r14d, r14d
5:      cmp ecx, 4097
        ja 6f
        cmp r14d, 48
        jae 6f
        cmp byte ptr [r12 + rcx], 0
        je 51f
        push rcx
        push rcx
        mov rdi, [rsp + 16 + BX_LENS]
        mov rsi, rcx
        call vec_push
        pop rcx
        pop rcx
        inc r14d
51:     inc ecx
        jmp 5b
6:      mov rdi, [rsp + BX_TRACE]
        call bt_near
        mov [rsp + BX_NEAR], rax
        # the worlds
        mov edi, MT_SIZEOF
        call arena_alloc
        mov [rsp + BX_MT], rax
        mov rdi, rax
        xor esi, esi
        call mt_seed
        mov rax, [rsp + BX_LENS]
        mov rdi, [rax + VEC_LEN]
        add rdi, 2
        mov rax, [rsp + BX_NEAR]
        add rdi, [rax + VEC_LEN]
        mov [rbx + BT_NWORLDS], rdi
        imul rdi, rdi, BW_SIZEOF
        call arena_alloc
        mov [rbx + BT_WORLDS], rax
        mov qword ptr [rsp + BX_I], 0
7:      mov rax, [rsp + BX_LENS]
        mov rcx, [rsp + BX_I]
        cmp rcx, [rax + VEC_LEN]
        jae 9f
        imul r13, rcx, BW_SIZEOF
        add r13, [rbx + BT_WORLDS]      # the world
        mov rax, [rax + VEC_DATA]
        mov r14, [rax + rcx*8]          # the length
        lea rdi, [r14 + 1]
        call arena_alloc_raw
        mov [r13 + BW_CONTENT], rax
        mov [r13 + BW_CLEN], r14
        xor r12d, r12d                  # bytes(rnd.randrange(1, 256) ...)
8:      cmp r12, r14
        jae 81f
        mov rdi, [rsp + BX_MT]
        mov esi, 255
        call mt_randrange
        inc eax
        mov rcx, [r13 + BW_CONTENT]
        mov [rcx + r12], al
        inc r12
        jmp 8b
81:     # the calldata: the selector, then 8 params
        mov edi, 4 + 8 * 32
        call arena_alloc
        mov [r13 + BW_CD], rax
        mov qword ptr [r13 + BW_CDLEN], 4 + 8 * 32
        mov rdi, rax
        mov rsi, [rsp + BX_SEL]
        call bt_put_selector
        xor r12d, r12d
82:     cmp r12d, 8
        jae 83f
        mov rax, [rsp + BX_I]           # values[(n + 3 * k) % 9]
        lea rax, [rax + r12*2]
        add rax, r12
        xor edx, edx
        mov ecx, 9
        div rcx
        mov rdi, [r13 + BW_CD]
        lea rdi, [rdi + 4 + r12*8]
        lea rdi, [rdi + r12*8]
        lea rdi, [rdi + r12*8]
        lea rdi, [rdi + r12*8]          # (+ 32 * k)
        mov esi, edx
        call bt_put_value
        inc r12d
        jmp 82b
83:     inc qword ptr [rsp + BX_I]
        jmp 7b
9:      # and params of the numbers the conditions of the code compare
        # with, and of the ones next to them: `if tokenId == 1337: return
        # ''` is a branch none of the values takes - of the lengths in turn
        mov qword ptr [rsp + BX_I], 0
91:     mov rax, [rsp + BX_NEAR]
        mov rcx, [rsp + BX_I]
        cmp rcx, [rax + VEC_LEN]
        jae 99f
        mov rax, [rsp + BX_LENS]
        add rcx, [rax + VEC_LEN]
        imul r13, rcx, BW_SIZEOF
        add r13, [rbx + BT_WORLDS]      # the world
        mov rax, [rsp + BX_I]           # lengths[n % len(lengths)]
        xor edx, edx
        mov rcx, [rsp + BX_LENS]
        div qword ptr [rcx + VEC_LEN]
        mov rax, [rcx + VEC_DATA]
        mov r14, [rax + rdx*8]
        lea rdi, [r14 + 1]
        call arena_alloc_raw
        mov [r13 + BW_CONTENT], rax
        mov [r13 + BW_CLEN], r14
        xor r12d, r12d
92:     cmp r12, r14
        jae 93f
        mov rdi, [rsp + BX_MT]
        mov esi, 255
        call mt_randrange
        inc eax
        mov rcx, [r13 + BW_CONTENT]
        mov [rcx + r12], al
        inc r12
        jmp 92b
93:     mov edi, 4 + 8 * 32             # the selector, then the number 8
        call arena_alloc                # times
        mov [r13 + BW_CD], rax
        mov qword ptr [r13 + BW_CDLEN], 4 + 8 * 32
        mov rdi, rax
        mov rsi, [rsp + BX_SEL]
        call bt_put_selector
        mov rax, [rsp + BX_NEAR]
        mov rax, [rax + VEC_DATA]
        mov rcx, [rsp + BX_I]
        mov rsi, [rax + rcx*8]
        lea rdi, [rsp + BX_WORD]
        call w_from_value
        xor r12d, r12d
94:     cmp r12d, 8
        jae 95f
        mov eax, r12d
        shl eax, 5
        mov rdi, [r13 + BW_CD]
        lea rdi, [rdi + rax + 4]
        mov esi, 32
        lea rdx, [rsp + BX_WORD]
        call ck_word_to_be
        inc r12d
        jmp 94b
95:     inc qword ptr [rsp + BX_I]
        jmp 91b
99:     # calldata too short for a param: b"\x01" * n, content b"ab"
        xor r12d, r12d
10:     cmp r12d, 2
        jae 12f
        mov rax, [rsp + BX_LENS]
        mov rcx, [rax + VEC_LEN]
        add rcx, r12
        mov rax, [rsp + BX_NEAR]
        add rcx, [rax + VEC_LEN]
        imul r13, rcx, BW_SIZEOF
        add r13, [rbx + BT_WORLDS]
        mov edi, 4 + 32
        call arena_alloc
        mov [r13 + BW_CD], rax
        mov rdi, rax
        mov rsi, [rsp + BX_SEL]
        call bt_put_selector
        xor eax, eax
        test r12d, r12d
        jz 11f
        mov rcx, [r13 + BW_CD]
        lea rdi, [rcx + 4]
        mov esi, 1
        mov edx, 31
        call memset@PLT
        mov eax, 31
11:     add rax, 4
        mov [r13 + BW_CDLEN], rax
        mov edi, 16
        call arena_alloc
        mov word ptr [rax], 0x6261      # "ab"
        mov [r13 + BW_CONTENT], rax
        mov qword ptr [r13 + BW_CLEN], 2
        inc r12d
        jmp 10b
12:     add rsp, 112
        LEAVE
ENDF bt_worlds

# bt_conds(exp, out): python's find_f_list(trace, the conditions of the
# ifs and the whiles) - pushed
FUNC bt_conds
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        test bl, 1
        jnz 9f
        test rbx, rbx
        jz 9f
        mov eax, [rbx + N_KIND]
        cmp eax, K_LIST
        je 2f
        cmp eax, K_TUPLE
        jne 9f
        cmp dword ptr [rbx + N_AUX], 2
        jb 2f
        mov rdi, rbx
        call opcode_of
        cmp eax, OP_IF
        je 1f
        cmp eax, OP_WHILE
        jne 2f
1:      mov rdi, r12
        mov rsi, [rbx + N_DATA + 8]
        call vec_push
2:      xor r13d, r13d
3:      cmp r13d, [rbx + N_AUX]
        jae 9f
        mov rdi, [rbx + N_DATA + r13*8]
        inc r13d
        mov rsi, r12
        call bt_conds
        jmp 3b
9:      LEAVE
ENDF bt_conds

# bt_ints(exp, out): python's find_f_list(exp, the ints) - pushed
FUNC bt_ints
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call is_int
        test eax, eax
        jz 1f
        mov rdi, r12
        mov rsi, rbx
        call vec_push
        jmp 9f
1:      mov rdi, rbx
        call is_seq
        test eax, eax
        jz 9f
        xor r13d, r13d
3:      cmp r13d, [rbx + N_AUX]
        jae 9f
        mov rdi, [rbx + N_DATA + r13*8]
        inc r13d
        mov rsi, r12
        call bt_ints
        jmp 3b
9:      LEAVE
ENDF bt_ints

# bt_near(trace) -> vec: python's near - the numbers the conditions of the
# trace compare with, and the ones next to them (mod 2**256), but the
# values of the params: sorted, the first 64 of them
FUNC bt_near
        ENTER
        sub rsp, 144
        .set BN_CONDS, 0
        .set BN_INTS, 8
        .set BN_NEAR, 16
        .set BN_OUT, 24
        .set BN_W, 48                   # (32 bytes)
        .set BN_BE, 80                  # (32 bytes)
        .set BN_TMP, 112                # (32 bytes)
        mov rbx, rdi
        call vec_new
        mov [rsp + BN_CONDS], rax
        mov rdi, rbx
        mov rsi, rax
        call bt_conds
        call vec_new
        mov [rsp + BN_INTS], rax
        xor r12d, r12d
1:      mov rax, [rsp + BN_CONDS]
        cmp r12, [rax + VEC_LEN]
        jae 2f
        mov rax, [rax + VEC_DATA]
        mov rdi, [rax + r12*8]
        inc r12
        mov rsi, [rsp + BN_INTS]
        call bt_ints
        jmp 1b
2:      call vec_new
        mov [rsp + BN_NEAR], rax
        xor r12d, r12d
3:      mov rax, [rsp + BN_INTS]
        cmp r12, [rax + VEC_LEN]
        jae 5f
        mov rax, [rax + VEC_DATA]
        mov r13, [rax + r12*8]          # c
        inc r12
        mov r14, -1                     # (c + d) % 2**256, d from -1 to 1
4:      mov rdi, r13
        lea rsi, [r14 + r14 + 1]
        call int_add
        mov rdi, rax
        mov esi, 256
        call int_mod_2exp
        mov rdi, [rsp + BN_NEAR]
        mov rsi, rax
        call vec_push_unique
        inc r14
        cmp r14, 1
        jle 4b
        jmp 3b
5:      call vec_new                    # but the values of the params
        mov [rsp + BN_OUT], rax
        xor r12d, r12d
6:      mov rax, [rsp + BN_NEAR]
        cmp r12, [rax + VEC_LEN]
        jae 8f
        mov rax, [rax + VEC_DATA]
        mov r13, [rax + r12*8]
        inc r12
        lea rdi, [rsp + BN_W]
        mov rsi, r13
        call w_from_value
        lea rdi, [rsp + BN_BE]
        mov esi, 32
        lea rdx, [rsp + BN_W]
        call ck_word_to_be
        xor r14d, r14d
7:      cmp r14d, 9
        jae 71f
        lea rdi, [rsp + BN_TMP]
        mov esi, r14d
        call bt_put_value
        lea rdi, [rsp + BN_BE]
        lea rsi, [rsp + BN_TMP]
        mov edx, 32
        call memcmp@PLT
        test eax, eax
        jz 6b
        inc r14d
        jmp 7b
71:     mov rdi, [rsp + BN_OUT]
        mov rsi, r13
        call vec_push
        jmp 6b
8:      mov rdi, [rsp + BN_OUT]         # sorted, the first 64
        lea rsi, [rip + py_lt]
        xor edx, edx
        call py_sort
        mov rax, [rsp + BN_OUT]
        cmp qword ptr [rax + VEC_LEN], 64
        jbe 9f
        mov qword ptr [rax + VEC_LEN], 64
9:      mov rax, [rsp + BN_OUT]
        add rsp, 144
        LEAVE
ENDF bt_near

# bt_put_selector(dst, selector): selector.to_bytes(4, "big")
FUNC bt_put_selector
        mov eax, esi
        bswap eax
        mov [rdi], eax
        ret
ENDF bt_put_selector

# bt_put_value(dst, i): values[i].to_bytes(32, "big") - 0, 1, 2, 255,
# 2**16 - 1, 2**160 - 1, 2**160, 2**255, 2**256 - 1
FUNC bt_put_value
        ENTER
        mov rbx, rdi
        mov r12d, esi
        xor esi, esi
        mov edx, 32
        call memset@PLT
        cmp r12d, 1
        je 1f
        cmp r12d, 2
        je 2f
        cmp r12d, 3
        je 3f
        cmp r12d, 4
        je 4f
        cmp r12d, 5
        je 5f
        cmp r12d, 6
        je 6f
        cmp r12d, 7
        je 7f
        cmp r12d, 8
        je 8f
        LEAVE
1:      mov byte ptr [rbx + 31], 1
        LEAVE
2:      mov byte ptr [rbx + 31], 2
        LEAVE
3:      mov byte ptr [rbx + 31], 255
        LEAVE
4:      mov word ptr [rbx + 30], 0xffff
        LEAVE
5:      lea rdi, [rbx + 12]
        mov esi, 0xff
        mov edx, 20
        call memset@PLT
        LEAVE
6:      mov byte ptr [rbx + 11], 1
        LEAVE
7:      mov byte ptr [rbx], 0x80
        LEAVE
8:      mov rdi, rbx
        mov esi, 0xff
        mov edx, 32
        call memset@PLT
        LEAVE
ENDF bt_put_value

# bt_ends(lines) -> eax: python's splits.ends - the lines end the call
FUNC bt_ends
        ENTER
        xor eax, eax
        mov ecx, [rdi + N_AUX]
        test ecx, ecx
        jz 1f
        mov rdi, [rdi + N_DATA + rcx*8 - 8]
        call opcode_of
        cmp eax, OP_REVERT
        je 2f
        cmp eax, OP_INVALID
        je 2f
        cmp eax, OP_RETURN
        je 2f
        cmp eax, OP_STOP
        je 2f
        xor eax, eax
1:      LEAVE
2:      mov eax, 1
        LEAVE
ENDF bt_ends

# a frame of splits' recursion: what a candidate of the lines inside is
# wrapped in - prefix + [('if', cond, a, sub)] (side 0) or [('if', cond,
# sub, b)] (side 1)
.set SP_PREFIX, 0
.set SP_COND, 8
.set SP_A, 16
.set SP_B, 24
.set SP_SIDE, 32
.set SP_NEXT, 40
.set SP_SIZEOF, 48

# bt_emit(bt, cand, ctx) -> eax: 1 to stop - the candidate, wrapped by the
# frames, tried
FUNC bt_emit
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
1:      test r13, r13
        jz 3f
        mov rsi, [r13 + SP_COND]
        cmp qword ptr [r13 + SP_SIDE], 0
        jne 2f
        mov rdx, [r13 + SP_A]
        mov rcx, r12
        jmp 21f
2:      mov rdx, r12
        mov rcx, [r13 + SP_B]
21:     LOADS rdi, IF
        call mk4
        mov rdi, rax
        call mk_list1
        mov rdi, [r13 + SP_PREFIX]
        mov rsi, rax
        call list_concat
        mov r12, rax
        mov r13, [r13 + SP_NEXT]
        jmp 1b
3:      mov rdi, rbx
        mov rsi, r12
        call bt_try
        LEAVE
ENDF bt_emit

# bt_splits(bt, trace, ctx) -> eax: python's splits - the trace with what's
# after a first part of it replaced by the tail, the least first, each
# tried (bt_try) until one stops it
FUNC bt_splits
        STACK_CHECK
        ENTER
        sub rsp, 48
        .set BS_CTX, 0
        .set BS_I, 8
        .set BS_REST, 16
        mov rbx, rdi
        mov r12, rsi
        mov [rsp + BS_CTX], rdx
        mov qword ptr [rsp + BS_I], 0
.Lbs_line:
        mov rcx, [rsp + BS_I]
        cmp ecx, [r12 + N_AUX]
        jae .Lbs_none
        mov rdi, r12                    # trace[:i] + tail
        mov rsi, rcx
        call st_list_head
        mov rdi, rax
        mov rsi, [rbx + BT_TAIL]
        call list_concat
        mov rdi, rbx
        mov rsi, rax
        mov rdx, [rsp + BS_CTX]
        call bt_emit
        test eax, eax
        jnz .Lbs_stop
        mov rcx, [rsp + BS_I]
        mov r13, [r12 + N_DATA + rcx*8]
        inc qword ptr [rsp + BS_I]
        mov rdi, r13
        OP_N_CHECK OP_IF, 4, .Lbs_line
        mov rdi, r12                    # rest = trace[i + 1:]
        mov rsi, [rsp + BS_I]
        call list_from
        mov [rsp + BS_REST], rax
        mov rdi, [r13 + N_DATA + 16]
        call bt_ends
        test eax, eax
        jz 1f
        xor esi, esi                    # the true branch ends: go on in the false one
        call .Lbs_frame
        mov rdi, [r13 + N_DATA + 24]
        call .Lbs_inner
        test eax, eax
        jnz .Lbs_stop
1:      mov rdi, [r13 + N_DATA + 24]
        call bt_ends
        test eax, eax
        jz .Lbs_line
        mov esi, 1                      # the false branch ends: go on in the true one
        call .Lbs_frame
        mov rdi, [r13 + N_DATA + 16]
        call .Lbs_inner
        test eax, eax
        jnz .Lbs_stop
        jmp .Lbs_line
.Lbs_none:
        xor eax, eax
        add rsp, 48
        LEAVE
.Lbs_stop:
        mov eax, 1
        add rsp, 48
        LEAVE
# r14 := a frame for the if r13, side esi
.Lbs_frame:
        sub rsp, 8
        mov [rsp], rsi
        mov edi, SP_SIZEOF
        call arena_alloc
        mov r14, rax
        mov rsi, [rsp]
        mov [r14 + SP_SIDE], rsi
        mov rax, [r13 + N_DATA + 8]
        mov [r14 + SP_COND], rax
        mov rax, [r13 + N_DATA + 16]
        mov [r14 + SP_A], rax
        mov rax, [r13 + N_DATA + 24]
        mov [r14 + SP_B], rax
        mov rax, [rsp + 16 + BS_CTX]
        mov [r14 + SP_NEXT], rax
        mov rdi, r12
        mov rsi, [rsp + 16 + BS_I]
        dec rsi
        call st_list_head
        mov [r14 + SP_PREFIX], rax
        add rsp, 8
        ret
# eax: bt_splits of list(branch rdi) + rest in the frame r14
.Lbs_inner:
        sub rsp, 8
        mov rsi, [rsp + 16 + BS_REST]
        call list_concat
        mov rdi, rbx
        mov rsi, rax
        mov rdx, r14
        call bt_splits
        add rsp, 8
        ret
ENDF bt_splits

# bt_same(bt, world, r) -> eax: the run of a candidate gives the original
# run r: (kind, data) the same - and where r returned the bytes of the
# world, the bytes the candidate's tail returns, not what's kept of the
# code (a branch kept returns something else: `return ''`)
FUNC bt_same
        ENTER
        mov rbx, rdi
        mov r13, rsi
        mov r12, rdx
        mov rax, [rbx + BT_M]
        mov rcx, [rax + RM_KIND]
        cmp rcx, [r12 + BR_KIND]
        jne 8f
        mov rdx, [rax + RM_DLEN]
        cmp rdx, [r12 + BR_DLEN]
        jne 8f
        mov rdi, [rax + RM_DATA]
        mov rsi, [r12 + BR_DATA]
        test rdx, rdx
        jz 1f
        call memcmp@PLT
        test eax, eax
        jnz 8f
1:      cmp qword ptr [r13 + BW_CLEN], 0
        je 9f
        cmp qword ptr [rbx + BT_REACHED], 0
        jne 9f
        mov rdi, r12
        mov rsi, r13
        call bt_returns_bytes
        test eax, eax
        jnz 8f
9:      mov eax, 1
        LEAVE
8:      xor eax, eax
        LEAVE
ENDF bt_same

# bt_returns_bytes(r, world) -> eax: python's returns_bytes - the run r
# returned the content of the world, ABI-encoded: 32, its length, its
# bytes padded with zeroes to whole words
FUNC bt_returns_bytes
        ENTER
        mov rbx, rdi
        mov r12, rsi
        xor eax, eax
        LOADS rcx, RETURN
        cmp [rbx + BR_KIND], rcx
        jne 9f
        mov r13, [r12 + BW_CLEN]
        lea rcx, [r13 + 31]
        and rcx, -32
        add rcx, 64
        cmp [rbx + BR_DLEN], rcx
        jne 9f
        mov r14, [rbx + BR_DATA]
        mov rax, [r14 + 24]             # the first word: 32
        bswap rax
        cmp rax, 32
        jne 8f
        mov rax, [r14]
        or rax, [r14 + 8]
        or rax, [r14 + 16]
        jnz 8f
        mov rax, [r14 + 56]             # the second: the length
        bswap rax
        cmp rax, r13
        jne 8f
        mov rax, [r14 + 32]
        or rax, [r14 + 40]
        or rax, [r14 + 48]
        jnz 8f
        lea rdi, [r14 + 64]             # the bytes
        mov rsi, [r12 + BW_CONTENT]
        mov rdx, r13
        call memcmp@PLT
        test eax, eax
        jnz 8f
        lea rcx, [r13 + 31]             # zeroes after them
        and rcx, -32
1:      cmp r13, rcx
        jae 2f
        cmp byte ptr [r14 + 64 + r13], 0
        jne 8f
        inc r13
        jmp 1b
2:      mov eax, 1
        LEAVE
8:      xor eax, eax
9:      LEAVE
ENDF bt_returns_bytes

# bt_try(bt, cand) -> eax: 1 to stop - when the candidate gives what the
# trace gives in every world, the bytes reached in one of them at least
# (BT_RESULT), or after 200 of them
FUNC bt_try
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov rax, [rbx + BT_N]
        inc qword ptr [rbx + BT_N]
        cmp rax, 200
        ja 8f
        mov qword ptr [rsp], 0          # reached
        xor r13d, r13d
1:      cmp r13, [rbx + BT_NWORLDS]
        jae 7f
        imul r14, r13, BW_SIZEOF
        add r14, [rbx + BT_WORLDS]
        mov rdi, rbx
        mov rsi, r12
        mov rdx, r14
        call bt_run
        test eax, eax
        jz 9f
        imul rdx, r13, BR_SIZEOF
        add rdx, [rbx + BT_ORIG]
        mov rdi, rbx
        mov rsi, r14
        call bt_same
        test eax, eax
        jz 9f
        mov rax, [rbx + BT_REACHED]
        or [rsp], rax
        inc r13
        jmp 1b
7:      cmp qword ptr [rsp], 0
        je 9f
        mov [rbx + BT_RESULT], r12
8:      mov eax, 1
        add rsp, 16
        LEAVE
9:      xor eax, eax
        add rsp, 16
        LEAVE
ENDF bt_try

# st_bytes_tail(trace, key, selector) -> rax: python's bytes_tail - the
# trace with what's after a first part of it replaced by the return of
# the bytes at the slot key, when that's the same; 0 (None)
FUNC st_bytes_tail
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov edi, BT_SIZEOF
        call arena_alloc
        mov r14, rax
        mov [r14 + BT_TRACE], rbx
        mov [r14 + BT_KEY], r12
        call emap_new
        mov [r14 + BT_WORDS], rax
        mov rdi, r14
        mov rsi, rbx
        mov rdx, r13
        call bt_worlds
        xor edi, edi
        xor esi, esi
        lea rdx, [rip + bt_world]
        mov rcx, r14
        call rt_machine_new
        mov [r14 + BT_M], rax
        # the trace in every world (all of them: python's list)
        mov rdi, [r14 + BT_NWORLDS]
        imul rdi, rdi, BR_SIZEOF
        call arena_alloc
        mov [r14 + BT_ORIG], rax
        xor r13d, r13d
        xor ebx, ebx                    # a None among them
        mov qword ptr [rsp], 0          # a return among them
1:      cmp r13, [r14 + BT_NWORLDS]
        jae 3f
        imul rdx, r13, BW_SIZEOF
        add rdx, [r14 + BT_WORLDS]
        mov rdi, r14
        mov rsi, [r14 + BT_TRACE]
        call bt_run
        imul r12, r13, BR_SIZEOF
        add r12, [r14 + BT_ORIG]
        inc r13
        test eax, eax
        jnz 2f
        mov ebx, 1
        jmp 1b
2:      mov rax, [r14 + BT_M]           # its kind, its data (copied), reached
        mov rcx, [rax + RM_KIND]
        mov [r12 + BR_KIND], rcx
        LOADS rdx, RETURN
        cmp rcx, rdx
        jne 21f
        mov qword ptr [rsp], 1
21:     mov rcx, [r14 + BT_REACHED]
        mov [r12 + BR_REACHED], rcx
        mov rdi, [rax + RM_DLEN]
        mov [r12 + BR_DLEN], rdi
        inc rdi
        call arena_alloc_raw
        mov [r12 + BR_DATA], rax
        mov rcx, [r14 + BT_M]
        mov rdi, rax
        mov rsi, [rcx + RM_DATA]
        mov rdx, [rcx + RM_DLEN]
        call memcpy@PLT
        jmp 1b
3:      test ebx, ebx
        jnz 8f
        cmp qword ptr [rsp], 0
        je 8f
        # the tail: return Array(len=b.length, data=b[all]), ABI-encoded
        LOADS rdi, LENGTH
        mov rsi, [r14 + BT_KEY]
        call mk2
        mov rcx, rax
        LOADS rdi, STORAGE
        mov esi, (256 << 1) | 1
        mov edx, 1
        call mk4
        mov r12, rax
        LOADS rdi, SBYTES
        mov rsi, [r14 + BT_KEY]
        call mk2
        mov rdx, rax
        LOADS rdi, ARR
        mov rsi, r12
        call mk3
        mov rsi, rax
        LOADS rdi, DATA
        call mk2
        mov rsi, rax
        LOADS rdi, RETURN
        call mk2
        mov rdi, rax
        call mk_list1
        mov [r14 + BT_TAIL], rax
        mov qword ptr [r14 + BT_N], 0
        mov qword ptr [r14 + BT_RESULT], 0
        mov rdi, r14
        mov rsi, [r14 + BT_TRACE]
        xor edx, edx
        call bt_splits
        mov rax, [r14 + BT_RESULT]
        add rsp, 16
        LEAVE
8:      xor eax, eax
        add rsp, 16
        LEAVE
ENDF st_bytes_tail

# st_selector(hash) -> rax: python's int(hash, 16) of a function's hash
# ("0x" and hex digits), -1 for its ValueError
FUNC st_selector
        ENTER
        mov rbx, rdi
        call is_str
        test eax, eax
        jz 9f
        lea r12, [rbx + N_DATA + 4]
        mov r13d, [rbx + N_DATA]
        cmp r13d, 2
        jb 1f
        cmp byte ptr [r12], '0'
        jne 1f
        mov al, [r12 + 1]
        or al, 0x20
        cmp al, 'x'
        jne 1f
        add r12, 2
        sub r13d, 2
1:      test r13d, r13d
        jz 9f
        xor eax, eax
        xor ecx, ecx
2:      cmp ecx, r13d
        jae 8f
        movzx edx, byte ptr [r12 + rcx]
        inc ecx
        lea esi, [edx - '0']
        cmp esi, 9
        jbe 3f
        or edx, 0x20
        lea esi, [edx - 'a' + 10]
        cmp esi, 10
        jb 9f
        cmp esi, 15
        ja 9f
3:      mov rdx, 0x0fffffffffffffff
        cmp rax, rdx
        ja .Lse_overflow
        shl rax, 4
        or rax, rsi
        jmp 2b
8:      LEAVE
9:      mov rax, -1
        LEAVE
.Lse_overflow:
        mov rax, -2                     # (too big for 4 bytes, surely)
        LEAVE
ENDF st_selector

# sg_bytes_getter(sg, f) -> rax: python's Storage.bytes_getter - (key,
# trace): the slot of the bytes of the storage f returns, and its trace
# returning them so; 0 (None)
FUNC sg_bytes_getter
        ENTER
        sub rsp, ERR_SIZEOF + 64
        .set BG_F, ERR_SIZEOF
        .set BG_SEL, ERR_SIZEOF + 8
        .set BG_KEYS, ERR_SIZEOF + 16
        .set BG_FOUND, ERR_SIZEOF + 24
        .set BG_I, ERR_SIZEOF + 32
        .set BG_KEY, ERR_SIZEOF + 40
        .set BG_LEN, ERR_SIZEOF + 48
        mov rbx, rdi
        mov [rsp + BG_F], rsi
        cmp qword ptr [rsi + FN_READ_ONLY], 0
        je .Lbg_none
        mov rdi, [rsi + FN_HASH]
        call st_selector
        cmp rax, -1
        je .Lbg_none
        mov [rsp + BG_SEL], rax
        # the slots of the bytes it reads: of a length, or of a low bit
        call vec_new
        mov [rsp + BG_FOUND], rax
        mov rax, [rsp + BG_F]
        mov rdi, [rax + FN_TRACE]
        mov esi, OP_STORAGE
        mov rdx, [rsp + BG_FOUND]
        call st_find_all
        call vec_new
        mov [rsp + BG_KEYS], rax
        xor r12d, r12d
1:      mov rax, [rsp + BG_FOUND]
        cmp r12, [rax + VEC_LEN]
        jae 5f
        mov rax, [rax + VEC_DATA]
        mov r13, [rax + r12*8]          # e
        inc r12
        cmp dword ptr [r13 + N_AUX], 4
        jb .Lbg_index
        mov r14, [r13 + N_DATA + 24]    # e[3]
        mov rdi, r14
        call opcode_of
        cmp eax, OP_LENGTH
        jne 2f
        cmp dword ptr [r14 + N_AUX], 2
        jb .Lbg_index
        mov r14, [r14 + N_DATA + 8]     # the key of a length
        jmp 3f
2:      mov rdi, [r13 + N_DATA + 8]     # e[1:3] == (1, 0): the low bit
        mov esi, 3
        call py_equal
        test eax, eax
        jz 1b
        mov rdi, [r13 + N_DATA + 16]
        mov esi, 1
        call py_equal
        test eax, eax
        jz 1b
3:      mov rdi, r14                    # ('loc', k): k
        call opcode_of
        cmp eax, OP_LOC
        jne 4f
        cmp dword ptr [r14 + N_AUX], 2
        jb .Lbg_index
        mov r14, [r14 + N_DATA + 8]
4:      mov rdi, [rsp + BG_KEYS]
        mov rsi, r14
        call set_add
        jmp 1b
5:      mov qword ptr [rsp + BG_I], 0
.Lbg_key:
        mov rax, [rsp + BG_KEYS]
        mov rcx, [rsp + BG_I]
        cmp rcx, 3
        jae .Lbg_none
        cmp rcx, [rax + VEC_LEN]
        jae .Lbg_none
        mov rax, [rax + VEC_DATA]
        mov r12, [rax + rcx*8]
        inc qword ptr [rsp + BG_I]
        mov rdi, r12                    # a number: ('loc', key)
        call is_int
        test eax, eax
        jz 1f
        LOADS rdi, LOC
        mov rsi, r12
        call mk2
        mov r12, rax
1:      mov [rsp + BG_KEY], r12
        LOADS rdi, LENGTH               # (256, 0, ('length', key))
        mov rsi, r12
        call mk2
        mov r13, rax
        mov edi, (256 << 1) | 1
        mov esi, 1
        mov rdx, rax
        call mk3
        mov [rsp + BG_LEN], rax
        mov rdi, [rbx + SG_STEPS]
        mov rsi, rax
        call od_get
        test rax, rax
        jnz 3f
        mov rdi, rsp                    # its steps, made (an exception: the
        call err_catch                  # next key)
        test eax, eax
        jnz 2f
        mov rdi, r13
        mov rsi, [rbx + SG_LANG]
        call st_parse
        mov rdi, rax
        call st_steps
        mov r14, rax
        call err_end
        mov rdi, r14
        call st_nil_none
        mov rdi, [rbx + SG_STEPS]
        mov rsi, [rsp + BG_LEN]
        mov rdx, rax
        call od_put
        jmp 3f
2:      mov edi, eax
        call st_catch_all
        jmp .Lbg_key
3:      mov rdi, rbx
        mov rsi, [rsp + BG_LEN]
        call sg_steps_get
        test rax, rax
        jz .Lbg_key
        mov r13, rax                    # (n, sts): n a typed root
        mov rdi, [rbx + SG_TYPES]
        mov rsi, [r13 + N_DATA]
        call od_get
        test rax, rax
        jz .Lbg_key
        mov r14, rax
        LOADS rdi, SV                   # form(('sv', None), t, sts, 256, 0)
        lea rsi, [rip + sp_none]
        call mk2
        mov rdi, rax
        mov rsi, r14
        mov rdx, [r13 + N_DATA + 8]
        mov ecx, (256 << 1) | 1
        mov r8d, 1
        call st_form
        test rax, rax
        jz .Lbg_key
        PAT rsi, "('st', 256, ('sbl', 'Any'), 256)"
        mov rdi, rax
        call pat_match_nobind
        test eax, eax
        jz .Lbg_key
        mov rax, [rsp + BG_SEL]
        cmp rax, -2
        je .Lbg_overflow
        shr rax, 32
        jnz .Lbg_overflow
        mov rax, [rsp + BG_F]
        mov rdi, [rax + FN_TRACE]
        mov rsi, [rsp + BG_KEY]
        mov rdx, [rsp + BG_SEL]
        call st_bytes_tail
        test rax, rax
        jz .Lbg_key
        mov rsi, rax
        mov rdi, [rsp + BG_KEY]
        call mk2
        add rsp, ERR_SIZEOF + 64
        LEAVE
.Lbg_none:
        xor eax, eax
        add rsp, ERR_SIZEOF + 64
        LEAVE
.Lbg_index:
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_tindex]
        call err_throw
.Lbg_overflow:
        mov edi, E_OVERFLOW
        lea rsi, [rip + .Ls_overflow]
        call err_throw
ENDF sg_bytes_getter

# st_find_all(exp, op, vec): python's find_f_list of the tuples headed by
# op - each one (and the ones in it), in the order of a walk
FUNC st_find_all
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12d, esi
        mov r13, rdx
        test bl, 1
        jnz 9f
        test rbx, rbx
        jz 9f
        mov eax, [rbx + N_KIND]
        cmp eax, K_LIST
        je 2f
        cmp eax, K_TUPLE
        jne 9f
        mov rdi, rbx
        call opcode_of
        cmp eax, r12d
        jne 2f
        mov rdi, r13
        mov rsi, rbx
        call vec_push
2:      xor r14d, r14d
3:      cmp r14d, [rbx + N_AUX]
        jae 9f
        mov rdi, [rbx + N_DATA + r14*8]
        inc r14d
        mov esi, r12d
        mov rdx, r13
        call st_find_all
        jmp 3b
9:      LEAVE
ENDF st_find_all

# sg_getter_trace(sg, f) -> rax: python's Storage.getter_trace - the trace
# of a bytes getter, `return name[all]`, ABI-encoded; 0 (None)
FUNC sg_getter_trace
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 16
        mov rbx, rdi
        mov rdi, [rbx + SG_BG]
        call od_get
        test rax, rax
        jz 9f
        mov r12, [rax + N_DATA]         # key
        mov r13, [rax + N_DATA + 8]     # trace
        LOADS rdi, LENGTH
        mov rsi, r12
        call mk2
        mov rcx, rax
        mov rdi, rbx
        mov esi, (256 << 1) | 1
        mov edx, 1
        xor r8d, r8d
        call sg_form
        PAT rsi, "('st', 256, ('sbl', ':loc'), 256)"
        mov rdi, rax
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 9f
        LOADS rdi, SBYTES               # ('sbytes', key) -> ('sall', loc)
        mov rsi, r12
        call mk2
        mov r12, rax
        LOADS rdi, SALL
        mov rsi, [rsp]
        call mk2
        mov rdi, r13
        mov rsi, r12
        mov rdx, rax
        call replace
        mov rsi, rax
        mov rdi, rbx
        call sg_rewrite
        add rsp, MATCH_BINDINGS_SIZE + 16
        LEAVE
9:      xor eax, eax
        add rsp, MATCH_BINDINGS_SIZE + 16
        LEAVE
ENDF sg_getter_trace

        .section .note.GNU-stack,"",@progbits
