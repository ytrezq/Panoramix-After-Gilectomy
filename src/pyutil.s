# Python's containers and orderings, where the decompiler relies on them:
# list.sort (with its comparisons in CPython's order, as they may raise),
# the ordering of values, and ordered dicts.

.include "defs.inc"

        .section .rodata
.Ls_type_error: .asciz "'<' not supported between these values"

        .text

# --- sorting ---

# py_sort(vec, lt, arg): list.sort with `<` being lt(a, b, arg) -> eax -
# for fewer than 64 elements, a run count then a binary insertion sort,
# with the comparisons in the same order as CPython's (they may raise)
FUNC py_sort
        ENTER
        sub rsp, 48
        .set PS_LT, 0
        .set PS_ARG, 8
        .set PS_L, 16
        .set PS_R, 24
        .set PS_P, 32
        mov [rsp + PS_LT], rsi
        mov [rsp + PS_ARG], rdx
        mov rbx, [rdi + VEC_DATA]
        mov r12, [rdi + VEC_LEN]
        cmp r12, 2
        jb .Lps_done
        # count_run: an initial ascending run, or a strictly descending
        # one (reversed)
        mov rdi, [rbx + 8]
        mov rsi, [rbx]
        call .Lps_lt
        mov r13d, 2                     # the run length
        test eax, eax
        jz 2f
1:      cmp r13, r12
        jae 3f
        mov rdi, [rbx + r13*8]
        mov rsi, [rbx + r13*8 - 8]
        call .Lps_lt
        test eax, eax
        jz 3f
        inc r13
        jmp 1b
3:      lea rdi, [rbx]
        lea rsi, [rbx + r13*8 - 8]
4:      cmp rdi, rsi
        jae 6f
        mov rax, [rdi]
        mov rcx, [rsi]
        mov [rdi], rcx
        mov [rsi], rax
        add rdi, 8
        sub rsi, 8
        jmp 4b
2:      cmp r13, r12
        jae 6f
        mov rdi, [rbx + r13*8]
        mov rsi, [rbx + r13*8 - 8]
        call .Lps_lt
        test eax, eax
        jnz 6f
        inc r13
        jmp 2b
6:      # binarysort from r13 on
        cmp r13, r12
        jae .Lps_done
        mov r14, [rbx + r13*8]          # pivot
        mov qword ptr [rsp + PS_L], 0
        mov [rsp + PS_R], r13
7:      mov rcx, [rsp + PS_L]
        mov rdx, [rsp + PS_R]
        cmp rcx, rdx
        jae 8f
        mov rax, rdx
        sub rax, rcx
        shr rax, 1
        add rax, rcx                    # p
        mov [rsp + PS_P], rax
        mov rdi, r14
        mov rsi, [rbx + rax*8]
        call .Lps_lt
        mov rdx, [rsp + PS_P]
        test eax, eax
        jz 9f
        mov [rsp + PS_R], rdx           # pivot < a[p]: r = p
        jmp 7b
9:      inc rdx
        mov [rsp + PS_L], rdx           # l = p + 1
        jmp 7b
8:      # insert the pivot at l
        mov rcx, [rsp + PS_L]
        mov rax, r13
10:     cmp rax, rcx
        jbe 11f
        mov rdx, [rbx + rax*8 - 8]
        mov [rbx + rax*8], rdx
        dec rax
        jmp 10b
11:     mov [rbx + rcx*8], r14
        inc r13
        jmp 6b
.Lps_done:
        add rsp, 48
        LEAVE
.Lps_lt:
        sub rsp, 8
        mov rdx, [rsp + 16 + PS_ARG]
        call [rsp + 16 + PS_LT]
        add rsp, 8
        ret
ENDF py_sort

# py_lt(a, b, arg) -> eax: python's a < b for ints, strings, tuples and
# lists; anything else raises TypeError (E_TYPE)
FUNC py_lt
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call is_int
        test eax, eax
        jz 1f
        mov rdi, r12
        call is_int
        test eax, eax
        jz .Lpl_type
        mov rdi, rbx
        mov rsi, r12
        call int_cmp
        cmp eax, -1
        sete al
        movzx eax, al
        LEAVE
1:      mov rdi, rbx
        call is_str
        test eax, eax
        jz 2f
        mov rdi, r12
        call is_str
        test eax, eax
        jz .Lpl_type
        lea rdi, [rbx + N_DATA + 4]
        lea rsi, [r12 + N_DATA + 4]
        call strcmp@PLT
        shr eax, 31                     # negative -> 1
        LEAVE
2:      mov rdi, rbx
        call is_seq
        test eax, eax
        jz .Lpl_type
        mov rdi, r12
        call is_seq
        test eax, eax
        jz .Lpl_type
        mov eax, [rbx + N_KIND]
        cmp eax, [r12 + N_KIND]
        jne .Lpl_type
        # the first elements that differ decide, else the lengths
        xor r13d, r13d
3:      cmp r13d, [rbx + N_AUX]
        jae 4f
        cmp r13d, [r12 + N_AUX]
        jae 4f
        mov rdi, [rbx + N_DATA + r13*8]
        mov rsi, [r12 + N_DATA + r13*8]
        call py_equal
        test eax, eax
        jz 5f
        inc r13d
        jmp 3b
5:      mov rdi, [rbx + N_DATA + r13*8]
        mov rsi, [r12 + N_DATA + r13*8]
        call py_lt
        LEAVE
4:      mov eax, [rbx + N_AUX]
        cmp eax, [r12 + N_AUX]
        setb al
        movzx eax, al
        LEAVE
.Lpl_type:
        mov edi, E_TYPE
        lea rsi, [rip + .Ls_type_error]
        call err_throw
ENDF py_lt

# py_sorted(vec) -> vec: sorted(it) with the fallback sorted(it, key=str)
# when the values can't be compared (sparser's sort)
FUNC py_sorted
        ENTER
        sub rsp, ERR_SIZEOF + 16
        mov rbx, rdi
        call vec_new
        mov r12, rax
        mov rdi, rax
        mov rsi, [rbx + VEC_DATA]
        mov rdx, [rbx + VEC_LEN]
        call vec_extend
        mov rdi, rsp
        call err_catch
        test eax, eax
        jnz 1f
        mov rdi, r12
        lea rsi, [rip + py_lt]
        xor edx, edx
        call py_sort
        call err_end
        mov rax, r12
        add rsp, ERR_SIZEOF + 16
        LEAVE
1:      # by str: (key, value) pairs sorted on the key
        cmp eax, E_TYPE
        jne .Lpsd_rethrow
        call vec_new
        mov r12, rax
        xor r13d, r13d
2:      cmp r13, [rbx + VEC_LEN]
        jae 3f
        mov rax, [rbx + VEC_DATA]
        mov r14, [rax + r13*8]
        mov rdi, r14
        call value_str
        mov rdi, rax
        mov rsi, r14
        call mk2
        mov rdi, r12
        mov rsi, rax
        call vec_push
        inc r13
        jmp 2b
3:      mov rdi, r12
        lea rsi, [rip + pair_key_lt]
        xor edx, edx
        call py_sort
        # the values back
        xor r13d, r13d
4:      cmp r13, [r12 + VEC_LEN]
        jae 5f
        mov rax, [r12 + VEC_DATA]
        mov rcx, [rax + r13*8]
        mov rcx, [rcx + N_DATA + 8]
        mov [rax + r13*8], rcx
        inc r13
        jmp 4b
5:      mov rax, r12
        add rsp, ERR_SIZEOF + 16
        LEAVE
.Lpsd_rethrow:
        mov edi, eax
        mov rsi, [r15 + CTX_ERR_MSG]
        call err_throw
ENDF py_sorted

# pair_key_lt((k, v), (k2, v2), arg) -> eax: k < k2 for strings
FUNC pair_key_lt
        mov rdi, [rdi + N_DATA]
        mov rsi, [rsi + N_DATA]
        ENTER
        lea rdi, [rdi + N_DATA + 4]
        lea rsi, [rsi + N_DATA + 4]
        call strcmp@PLT
        shr eax, 31
        LEAVE
ENDF pair_key_lt

# --- ordered dicts: keys in insertion order, values replaced in place ---
# Keys are values (pointers or tagged ints), looked up by pointer (the
# structures being hash-consed), and never 0; nor are the values.


# od_new() -> rax
FUNC od_new
        ENTER
        mov edi, OD_SIZEOF
        call arena_alloc
        mov rbx, rax
        call vec_new
        mov [rbx + OD_KEYS], rax
        call vec_new
        mov [rbx + OD_VALS], rax
        call map_new
        mov [rbx + OD_MAP], rax
        mov rax, rbx
        LEAVE
ENDF od_new

# od_index(od, key) -> rax: the index of a key, or -1
FUNC od_index
        ENTER
        mov rdi, [rdi + OD_MAP]
        call map_get
        dec rax
        LEAVE
ENDF od_index

# od_get(od, key) -> rax: the value, or 0
FUNC od_get
        ENTER
        mov rbx, rdi
        call od_index
        test rax, rax
        js 1f
        mov rcx, [rbx + OD_VALS]
        mov rcx, [rcx + VEC_DATA]
        mov rax, [rcx + rax*8]
        LEAVE
1:      xor eax, eax
        LEAVE
ENDF od_get

# od_put(od, key, value): d[key] = value
FUNC od_put
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        call od_index
        test rax, rax
        js 1f
        mov rcx, [rbx + OD_VALS]
        mov rcx, [rcx + VEC_DATA]
        mov [rcx + rax*8], r13
        LEAVE
1:      mov rdi, [rbx + OD_KEYS]
        mov rsi, r12
        call vec_push
        mov rdi, [rbx + OD_VALS]
        mov rsi, r13
        call vec_push
        mov rdi, [rbx + OD_MAP]
        mov rsi, r12
        mov rax, [rbx + OD_KEYS]
        mov rdx, [rax + VEC_LEN]
        call map_put
        LEAVE
ENDF od_put

# od_len(od) -> rax ; od_key(od, i) -> rax ; od_val(od, i) -> rax ;
# od_set_val(od, i, v)
FUNC od_len
        mov rax, [rdi + OD_KEYS]
        mov rax, [rax + VEC_LEN]
        ret
ENDF od_len

FUNC od_key
        mov rax, [rdi + OD_KEYS]
        mov rax, [rax + VEC_DATA]
        mov rax, [rax + rsi*8]
        ret
ENDF od_key

FUNC od_val
        mov rax, [rdi + OD_VALS]
        mov rax, [rax + VEC_DATA]
        mov rax, [rax + rsi*8]
        ret
ENDF od_val

FUNC od_set_val
        mov rax, [rdi + OD_VALS]
        mov rax, [rax + VEC_DATA]
        mov [rax + rsi*8], rdx
        ret
ENDF od_set_val

# --- sets: vecs without duplicates (pointer equality, as the values are
# hash-consed) ---

# set_add(vec, v) -> eax: 1 if added
FUNC set_add
        mov rcx, [rdi + VEC_LEN]
        mov rax, [rdi + VEC_DATA]
1:      test rcx, rcx
        jz 2f
        cmp [rax], rsi
        je 3f
        add rax, 8
        dec rcx
        jmp 1b
2:      ENTER
        call vec_push
        mov eax, 1
        LEAVE
3:      xor eax, eax
        ret
ENDF set_add

# set_has(vec, v) -> eax
FUNC set_has
        mov rcx, [rdi + VEC_LEN]
        mov rax, [rdi + VEC_DATA]
1:      test rcx, rcx
        jz 2f
        cmp [rax], rsi
        je 3f
        add rax, 8
        dec rcx
        jmp 1b
2:      xor eax, eax
        ret
3:      mov eax, 1
        ret
ENDF set_has

        .section .note.GNU-stack,"",@progbits
