# The last-minute rewrites (port of rewriter.py and postprocess.py):
# heuristics that make a lot of contracts more readable.

.include "defs.inc"

        .section .rodata
.Ls_assert_mul:     .asciz "cleanup_mul_1: a mul with too few terms"
.Ls_assert_arr:     .asciz "postprocess_exp: array offset"
.Ls_empty:          .asciz ""

        .text

.macro B reg, n
        mov \reg, [rsp + 8*\n]
.endm

# --- postprocess.cleanup_mul_1 ---

# pp_cleanup_exp(exp) -> value
FUNC pp_cleanup_exp
        ENTER
        sub rsp, 16
        mov rbx, rdi
        call is_tuple
        test eax, eax
        jz .Lpce_asis
        mov rdi, rbx
        call opcode_of
        mov r12d, eax
        cmp eax, OP_MASK_SHL
        jne 3f
        cmp dword ptr [rbx + N_AUX], 5
        jne 3f
        # mask_shl storage -> storage, when the mask is the storage's own
        mov r13, [rbx + N_DATA + 32]
        mov rdi, r13
        call opcode_of
        cmp eax, OP_STORAGE
        jne 1f
        cmp dword ptr [r13 + N_AUX], 4
        jb 1f
        mov rax, [rbx + N_DATA + 8]
        cmp rax, [r13 + N_DATA + 8]
        jne 1f
        mov rdi, [rbx + N_DATA + 16]
        call is_int
        test eax, eax
        jz 1f
        mov rdi, [rbx + N_DATA + 24]
        call alg_minus_op
        cmp rax, [rbx + N_DATA + 16]
        jne 1f
        mov rax, [rbx + N_DATA + 16]
        cmp rax, [r13 + N_DATA + 16]
        jne 1f
        mov rdi, r13
        call pp_cleanup_exp
        jmp .Lpce_done
1:      # ('mask_shl', 160, 0, 0, 'caller') -> 'caller'
        cmp qword ptr [rbx + N_DATA + 8], (160 << 1) | 1
        jne 2f
        cmp qword ptr [rbx + N_DATA + 16], 1
        jne 2f
        cmp qword ptr [rbx + N_DATA + 24], 1
        jne 2f
        LOADS rax, CALLER
        cmp r13, rax
        jne 2f
        mov rax, r13
        jmp .Lpce_done
2:      # a mask over a string constant of exactly its size: the string
        mov rdi, [rbx + N_DATA + 8]
        call is_int
        test eax, eax
        jz 21f
        mov rdi, [rbx + N_DATA + 16]
        call is_int
        test eax, eax
        jz 21f
        mov rdi, [rbx + N_DATA + 24]
        call is_int
        test eax, eax
        jz 21f
        mov rdi, r13
        call is_str
        test eax, eax
        jz 21f
        mov rax, [rbx + N_DATA + 8]
        add rax, [rbx + N_DATA + 16]
        cmp rax, (256 << 1) | 2         # size + offset == 256 (two tags)
        jne 21f
        cmp qword ptr [rbx + N_DATA + 24], 1
        jne 21f
        mov ecx, [r13 + N_DATA]         # length
        cmp ecx, 2
        jb 21f
        cmp byte ptr [r13 + N_DATA + 4], '\''
        jne 21f
        cmp byte ptr [r13 + N_DATA + 4 + rcx - 1], '\''
        jne 21f
        # len(s) * 8 == size
        sub ecx, 2
        shl rcx, 3
        TAG rcx
        cmp rcx, [rbx + N_DATA + 8]
        jne 21f
        lea rdi, [r13 + N_DATA + 5]
        mov esi, [r13 + N_DATA]
        sub esi, 2
        call str_intern
        jmp .Lpce_done
21:     # ('mask_shl', 256, 0, 0, x): x when it's an int below 2^256 or a sha3
        cmp qword ptr [rbx + N_DATA + 8], (256 << 1) | 1
        jne 3f
        cmp qword ptr [rbx + N_DATA + 16], 1
        jne 3f
        cmp qword ptr [rbx + N_DATA + 24], 1
        jne 3f
        mov rdi, r13
        call pp_cleanup_exp
        mov [rsp], rax
        mov rdi, rax
        call is_int
        test eax, eax
        jz 22f
        mov rdi, [rsp]
        call int_bit_length
        cmp rax, 256
        ja 3f
        mov rax, [rsp]
        jmp .Lpce_done
22:     mov rdi, [rsp]
        call opcode_of
        cmp eax, OP_SHA3
        jne 3f
        mov rax, [rsp]
        jmp .Lpce_done
3:      cmp r12d, OP_BOOL
        jne 4f
        cmp dword ptr [rbx + N_AUX], 2
        jb 4f
        mov rdi, [rbx + N_DATA + 8]
        call is_int
        test eax, eax
        jz 4f
        # ('bool', int) -> 1 or 0
        mov eax, 3
        cmp qword ptr [rbx + N_DATA + 8], 1
        jne .Lpce_done
        mov eax, 1
        jmp .Lpce_done
4:      cmp r12d, OP_MUL
        jne 5f
        cmp dword ptr [rbx + N_AUX], 2
        jb 5f
        cmp qword ptr [rbx + N_DATA + 8], 3
        jne 5f
        cmp dword ptr [rbx + N_AUX], 3
        jne 41f
        mov rdi, [rbx + N_DATA + 16]
        call pp_cleanup_exp
        jmp .Lpce_done
41:     cmp dword ptr [rbx + N_AUX], 3
        jb .Lpce_assert
        # ('mul',) + the other terms cleaned up
        mov edi, [rbx + N_AUX]
        sub edi, 2
        lea rsi, [rbx + N_DATA + 16]
        call mk_tuple
        mov rdi, rax
        lea rsi, [rip + pp_cleanup_cb]
        call map_seq
        mov rdi, rax
        call tuple_prepend_mul
        jmp .Lpce_done
5:      mov rdi, rbx
        lea rsi, [rip + pp_cleanup_cb]
        call map_seq
        jmp .Lpce_done
.Lpce_asis:
        mov rax, rbx
.Lpce_done:
        add rsp, 16
        LEAVE
.Lpce_assert:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_mul]
        call err_throw
ENDF pp_cleanup_exp

FUNC pp_cleanup_cb
        jmp pp_cleanup_exp
ENDF pp_cleanup_cb

# tuple_prepend_mul(tuple) -> ('mul',) + tuple
FUNC tuple_prepend_mul
        ENTER
        mov rbx, rdi
        call vec_new
        mov r12, rax
        mov rdi, rax
        LOADS rsi, MUL
        call vec_push
        mov rdi, r12
        mov rsi, rbx
        call vec_extend_seq
        mov rdi, r12
        call vec_to_tuple
        LEAVE
ENDF tuple_prepend_mul

# pp_cleanup_elements(tuple) -> tuple: postprocess.cleanup_mul_1 applied
# to a tuple as if it were a trace (normalize does that to conditions):
# each element cleaned up on its own
FUNC pp_cleanup_elements
        ENTER
        lea rsi, [rip + pp_cleanup_line_cb]
        call map_seq
        LEAVE
ENDF pp_cleanup_elements

# pp_cleanup_line_cb(line, arg): a line of a trace cleaned up
FUNC pp_cleanup_line_cb
        ENTER
        sub rsp, 16
        mov rbx, rdi
        call is_if_line
        test eax, eax
        jz 1f
        mov rdi, [rbx + N_DATA + 8]
        call pp_cleanup_exp
        mov [rsp], rax
        mov rdi, [rbx + N_DATA + 16]
        call pp_cleanup_mul_1
        mov [rsp + 8], rax
        mov rdi, [rbx + N_DATA + 24]
        call pp_cleanup_mul_1
        mov rdx, rax
        mov rdi, [rsp]
        mov rsi, [rsp + 8]
        call mk_if
        jmp 3f
1:      mov rdi, rbx
        call is_while_line
        test eax, eax
        jz 2f
        mov rdi, [rbx + N_DATA + 8]
        call pp_cleanup_exp
        mov [rsp], rax
        mov rdi, [rbx + N_DATA + 16]
        call pp_cleanup_mul_1
        mov [rsp + 8], rax
        mov rdi, [rbx + N_DATA + 32]
        call pp_cleanup_exp
        mov rcx, rax
        mov rdi, [rsp]
        mov rsi, [rsp + 8]
        mov rdx, [rbx + N_DATA + 24]
        call mk_while
        jmp 3f
2:      mov rdi, rbx
        call pp_cleanup_exp
3:      add rsp, 16
        LEAVE
ENDF pp_cleanup_line_cb

# pp_cleanup_mul_1(trace) -> list: postprocess.cleanup_mul_1
FUNC pp_cleanup_mul_1
        ENTER
        lea rsi, [rip + pp_cleanup_line_cb]
        call map_seq
        LEAVE
ENDF pp_cleanup_mul_1

# --- rewriter.postprocess_exp ---

# postprocess_exp(exp, arg) -> value: arrays in data
FUNC postprocess_exp
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 48
        .set PE_LOC, MATCH_BINDINGS_SIZE
        .set PE_CONCRETE, MATCH_BINDINGS_SIZE + 8
        .set PE_ARR, MATCH_BINDINGS_SIZE + 16
        .set PE_VEC, MATCH_BINDINGS_SIZE + 24
        .set PE_I, MATCH_BINDINGS_SIZE + 32
        mov rbx, rdi
        call opcode_of
        cmp eax, OP_DATA
        jne .Lpe_arr
        # one term a multiple of 32: potentially the offset of an array
        mov qword ptr [rsp + PE_CONCRETE], 0
        xor r12d, r12d                  # how many
        mov r13d, 1
1:      cmp r13d, [rbx + N_AUX]
        jae 2f
        mov rax, [rbx + N_DATA + r13*8]
        test al, 1
        jz 11f
        sar rax, 1
        test rax, 31
        jnz 11f
        inc r12d
        mov [rsp + PE_LOC], r13
        mov [rsp + PE_CONCRETE], rax    # (untagged)
11:     inc r13d
        jmp 1b
2:      cmp r12d, 1
        jne .Lpe_arr
        mov rax, [rsp + PE_CONCRETE]
        sar rax, 5                      # loc = concrete // 32
        mov r14, rax
        # loc + 1 < len(terms) and loc > terms.index(concrete)
        mov ecx, [rbx + N_AUX]
        dec ecx                         # len(terms)
        lea rdx, [r14 + 1]
        cmp rdx, rcx
        jge .Lpe_arr
        mov rdx, [rsp + PE_LOC]
        dec rdx                         # index among the terms
        cmp r14, rdx
        jle .Lpe_arr
        # arr = ('arr',) + terms[loc:]
        call vec_new
        mov [rsp + PE_VEC], rax
        mov rdi, rax
        LOADS rsi, ARR
        call vec_push
        mov ecx, [rbx + N_AUX]
        dec ecx
        sub rcx, r14                    # the terms from loc on
        lea rsi, [rbx + N_DATA + 8 + r14*8]
        mov rdi, [rsp + PE_VEC]
        mov rdx, rcx
        call vec_extend
        mov rdi, [rsp + PE_VEC]
        call vec_to_tuple
        mov [rsp + PE_ARR], rax
        # heuristics for cleaning up various misprocessed stuff
        PAT rsi, "('arr', ':l', (':op', 'Any', ':l'), '...')"
        mov rdi, rax
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 3f
        B rdi, 1
        call str_id
        mov edi, eax
        call is_array_op
        test eax, eax
        jz 3f
        mov rax, [rsp + PE_ARR]
        mov edi, 3
        lea rsi, [rax + N_DATA]
        call mk_tuple
        mov [rsp + PE_ARR], rax
        jmp 4f
3:      PAT rsi, "('arr', ':l', ('mask_shl', ('mask_shl', 253, 0, 3, ':l'), 'Any', 'Any', ('data', (':op', ':st', ':l'), '...'), '...'))"
        mov rdi, [rsp + PE_ARR]
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 4f
        B rdi, 1
        call str_id
        mov edi, eax
        call is_array_op
        test eax, eax
        jz 4f
        # ('arr', l, (op, st, l))
        B rdi, 1
        B rsi, 2
        B rdx, 0
        call mk3
        mov rdx, rax
        B rsi, 0
        LOADS rdi, ARR
        call mk3
        mov [rsp + PE_ARR], rax
4:      # ('data',) + the terms before loc, the offset replaced by the array
        call vec_new
        mov [rsp + PE_VEC], rax
        mov rdi, rax
        LOADS rsi, DATA
        call vec_push
        mov qword ptr [rsp + PE_I], 0
5:      mov rcx, [rsp + PE_I]
        cmp rcx, r14
        jae 6f
        mov rsi, [rbx + N_DATA + 8 + rcx*8]
        mov rax, [rsp + PE_CONCRETE]
        TAG rax
        cmp rsi, rax
        jne 51f
        mov rsi, [rsp + PE_ARR]
51:     mov rdi, [rsp + PE_VEC]
        call vec_push
        inc qword ptr [rsp + PE_I]
        jmp 5b
6:      mov rdi, [rsp + PE_VEC]
        call vec_to_tuple
        jmp .Lpe_done
.Lpe_arr:
        PAT rsi, "('arr', ':l', ('mask_shl', ('mask_shl', 'Any', 0, 3, ':l'), ('add', 256, 'Any'), ('add', -256, 'Any'), ('data', ('call.data', ':s', ':l'), '...'), '...'))"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz .Lpe_asis
        # ('arr', l, ('call.data', s, l))
        B rsi, 1
        B rdx, 0
        LOADS rdi, CALL_DATA
        call mk3
        mov rdx, rax
        B rsi, 0
        LOADS rdi, ARR
        call mk3
        jmp .Lpe_done
.Lpe_asis:
        mov rax, rbx
.Lpe_done:
        add rsp, MATCH_BINDINGS_SIZE + 48
        LEAVE
ENDF postprocess_exp

# --- rewriter.postprocess_trace ---

# collect_arr_storage(exp, arg, out): ('arr', ('storage', 256, 0, l), ...) with l = arg
FUNC collect_arr_storage
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        PAT rsi, "('arr', ('storage', 256, 0, ':l'), '...')"
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 1f
        B rdi, 0
        mov rsi, r12
        call values_equal
        test eax, eax
        jz 1f
        mov rdi, r13
        mov rsi, rbx
        call vec_push
1:      add rsp, MATCH_BINDINGS_SIZE
        LEAVE
ENDF collect_arr_storage

# collect_arr_l(exp, arg, out): ('arr', l, ...) with l = arg
FUNC collect_arr_l
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        PAT rsi, "('arr', ':l', '...')"
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 1f
        B rdi, 0
        mov rsi, r12
        call values_equal
        test eax, eax
        jz 1f
        mov rdi, r13
        mov rsi, rbx
        call vec_push
1:      add rsp, MATCH_BINDINGS_SIZE
        LEAVE
ENDF collect_arr_l

# walk_collect_with(exp, f, arg, out): f(x, arg, out) for every tuple
# and list in exp, depth first (find_f_list with an argument)
FUNC walk_collect_with
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov [rsp], rcx
        call is_seq
        test eax, eax
        jz 3f
        mov rdi, rbx
        mov rsi, r13
        mov rdx, [rsp]
        call r12
        xor r14d, r14d
2:      cmp r14d, [rbx + N_AUX]
        jae 3f
        mov rdi, [rbx + N_DATA + r14*8]
        mov rsi, r12
        mov rdx, r13
        mov rcx, [rsp]
        call walk_collect_with
        inc r14d
        jmp 2b
3:      add rsp, 16
        LEAVE
ENDF walk_collect_with

# count_found(exp, f, arg) -> rax: how many f finds
FUNC count_found
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        call vec_new
        mov r14, rax
        mov rdi, rbx
        mov rsi, r12
        mov rdx, r13
        mov rcx, r14
        call walk_collect_with
        mov rax, [r14 + VEC_LEN]
        LEAVE
ENDF count_found

# postprocess_trace(line, arg, out): rewrite_trace_ifs' f
FUNC postprocess_trace
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 32
        .set PT_OUT, MATCH_BINDINGS_SIZE
        .set PT_L, MATCH_BINDINGS_SIZE + 8
        .set PT_TRUE, MATCH_BINDINGS_SIZE + 16
        mov rbx, rdi
        mov [rsp + PT_OUT], rdx
        # an if on the length of a storage string/array whose branches
        # both hold the array: the true branch alone
        PAT rsi, "('if', ('iszero', ('storage', 5, 0, ':l')), ':if_true', ':if_false')"
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 1f
        B rax, 0
        mov [rsp + PT_L], rax
        B rax, 1
        mov [rsp + PT_TRUE], rax
        mov rdi, rax
        lea rsi, [rip + collect_arr_storage]
        mov rdx, [rsp + PT_L]
        call count_found
        test rax, rax
        jz 1f
        # (sic: both counts are taken on the true branch)
        mov rax, [rsp + PT_TRUE]
        jmp .Lpt_replace
1:      PAT rsi, "('if', ('iszero', ('mask_shl', 5, 0, 0, ':l')), ':if_true', ':if_false')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 2f
        B rax, 0
        mov [rsp + PT_L], rax
        B rax, 1
        mov [rsp + PT_TRUE], rax
        mov rdi, rax
        lea rsi, [rip + collect_arr_l]
        mov rdx, [rsp + PT_L]
        call count_found
        test rax, rax
        jz 2f
        mov rax, [rsp + PT_TRUE]
        jmp .Lpt_replace
2:      # a string written to storage: only the case of a long one shown
        PAT rsi, "('if', ('lt', 31, ':some_len'), ':if_true', ':if_false')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 3f
        B r12, 1                        # if_true
        cmp dword ptr [r12 + N_AUX], 2
        jb 3f
        mov r13, [r12 + N_DATA]         # first
        mov rdi, r13
        call opcode_of
        cmp eax, OP_STORE
        jne 3f
        mov rdi, r13
        B rsi, 0
        call contains
        test eax, eax
        jz 3f
        B rdi, 0
        call mk_iszero_of
        mov [rsp + PT_L], rax
        mov rax, [r12 + N_DATA + 8]     # second
        mov [rsp + PT_TRUE], rax
        mov rdi, rax
        call is_if_line
        test eax, eax
        jz 3f
        mov rax, [rsp + PT_TRUE]
        mov rax, [rax + N_DATA + 8]
        cmp rax, [rsp + PT_L]
        jne 3f
        # [first] + deep_false + rest
        mov rdi, [rsp + PT_OUT]
        mov rsi, r13
        call vec_push
        mov rax, [rsp + PT_TRUE]
        mov rdi, [rsp + PT_OUT]
        mov rsi, [rax + N_DATA + 24]
        call vec_extend_seq
        mov edx, [r12 + N_AUX]
        sub edx, 2
        lea rsi, [r12 + N_DATA + 16]
        mov rdi, [rsp + PT_OUT]
        call vec_extend
        jmp .Lpt_done
3:      PAT rsi, "('if', ('iszero', ('mask_shl', 255, 1, 0, ('and', ('storage', 256, 0, ':loc'), ('add', -1, ('mask_shl', 248, 0, 8, ('iszero', ('storage', 1, 0, ':loc'))))))), ':if_true', ':if_false')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jnz 4f
        PAT rsi, "('if', ('iszero', ('mask_shl', 255, 1, 0, ('and', ('add', -1, ('mask_shl', 248, 0, 8, ('iszero', ('storage', 1, 0, ':loc')))), ('storage', 256, 0, ':loc')))), ':if_true', ':if_false')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz .Lpt_asis
4:      B r12, 2                        # if_false
        cmp dword ptr [r12 + N_AUX], 1
        jne .Lpt_asis
        mov r13, [r12 + N_DATA]         # first
        B rax, 0
        mov [rsp + PT_L], rax           # loc
        # ('if', ('lt', 31, ('storage', 256, 0, ('length', loc))), deep_true, ...)
        # or with ('loc', loc)
        mov rdi, r13
        call is_if_line
        test eax, eax
        jz .Lpt_asis
        LOADS rdi, LENGTH
        mov rsi, [rsp + PT_L]
        call mk2
        mov rdi, rax
        call .Lpt_lt31_storage
        cmp rax, [r13 + N_DATA + 8]
        je 5f
        LOADS rdi, LOC
        mov rsi, [rsp + PT_L]
        call mk2
        mov rsi, rax
        LOADS rdi, LENGTH
        call mk2
        mov rdi, rax
        call .Lpt_lt31_storage
        cmp rax, [r13 + N_DATA + 8]
        jne .Lpt_asis
5:      mov rax, [r13 + N_DATA + 16]    # deep_true
.Lpt_replace:
        mov rdi, [rsp + PT_OUT]
        mov rsi, rax
        call vec_extend_seq
        jmp .Lpt_done
.Lpt_asis:
        mov rdi, [rsp + PT_OUT]
        mov rsi, rbx
        call vec_push
.Lpt_done:
        add rsp, MATCH_BINDINGS_SIZE + 32
        LEAVE

# local: ('lt', 31, ('storage', 256, 0, rdi))
.Lpt_lt31_storage:
        sub rsp, 8
        mov rcx, rdi
        LOADS rdi, STORAGE
        mov esi, (256 << 1) | 1
        mov edx, 1
        call mk4
        mov rdx, rax
        LOADS rdi, LT
        mov esi, (31 << 1) | 1
        call mk3
        add rsp, 8
        ret
ENDF postprocess_trace

# --- rewriter.rewrite_string_stores ---

# string_store(trace, idx, &end) -> the merged store, or 0: a string
# written to storage at trace[idx] (the length, a copying loop, then a
# clearing loop)
FUNC string_store
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 48
        .set SS_IDX, MATCH_BINDINGS_SIZE
        .set SS_SRC, MATCH_BINDINGS_SIZE + 8
        .set SS_SETVARS, MATCH_BINDINGS_SIZE + 16
        .set SS_END, MATCH_BINDINGS_SIZE + 24
        .set SS_OUT, MATCH_BINDINGS_SIZE + 32
        mov rbx, rdi
        mov r12, rsi
        mov [rsp + SS_OUT], rdx
        PAT rsi, "('store', 256, 0, ':idx', ('add', 1, ('mask_shl', 255, 0, 1, ':src')))"
        mov rdi, [rbx + N_DATA + r12*8]
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz .Lss_none
        B rax, 0
        mov [rsp + SS_IDX], rax
        B rax, 1
        mov [rsp + SS_SRC], rax
        lea eax, [r12 + 1]
        cmp eax, [rbx + N_AUX]
        jae .Lss_none
        PAT rsi, "('while', ('gt', 'Any', 'Any'), ':path2', 'Any', ':setvars')"
        mov rdi, [rbx + N_DATA + r12*8 + 8]
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz .Lss_none
        B rax, 1
        mov [rsp + SS_SETVARS], rax
        B r13, 0                        # path2
        cmp dword ptr [r13 + N_AUX], 2
        jne .Lss_none
        PAT rsi, "('store', 256, 0, ('add', ('var', 'Any'), 'Any'), ('mem', ('range', ('var', 'Any'), 32)))"
        mov rdi, [r13 + N_DATA]
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz .Lss_none
        # end: past the setvars that follow
        lea r14, [r12 + 2]
1:      cmp r14d, [rbx + N_AUX]
        jae .Lss_none
        mov rdi, [rbx + N_DATA + r14*8]
        call opcode_of
        cmp eax, OP_SETVAR
        jne 2f
        inc r14
        jmp 1b
2:      PAT rsi, "('while', ('gt', '...'), ':path3', '...')"
        mov rdi, [rbx + N_DATA + r14*8]
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz .Lss_none
        # ('store', 256, 0, ('array', '', ('sha3', idx)), ('arr', src, ('mem', ('range', setvars[1][2], src))))
        mov rax, [rsp + SS_SETVARS]
        mov rax, [rax + N_DATA + 8]
        mov rdi, [rax + N_DATA + 16]
        mov rsi, [rsp + SS_SRC]
        call mk_mem_range
        mov rdx, rax
        mov rsi, [rsp + SS_SRC]
        LOADS rdi, ARR
        call mk3
        mov [rsp + SS_SRC], rax
        LOADS rdi, SHA3
        mov rsi, [rsp + SS_IDX]
        call mk2
        mov [rsp + SS_IDX], rax
        lea rdi, [rip + .Ls_empty]
        call str_intern_c
        mov rsi, rax
        mov rdx, [rsp + SS_IDX]
        LOADS rdi, ARRAY
        call mk3
        mov rcx, rax
        mov r8, [rsp + SS_SRC]
        LOADS rdi, STORE
        mov esi, (256 << 1) | 1
        mov edx, 1
        call mk5
        mov rcx, [rsp + SS_OUT]
        lea rdx, [r14 + 1]
        mov [rcx], rdx
        add rsp, MATCH_BINDINGS_SIZE + 48
        LEAVE
.Lss_none:
        xor eax, eax
        add rsp, MATCH_BINDINGS_SIZE + 48
        LEAVE
ENDF string_store

# rewrite_string_stores(trace, after) -> list; `after` is what follows
# the trace in the enclosing traces
FUNC rewrite_string_stores
        ENTER
        sub rsp, 64
        .set RS_AFTER, 0
        .set RS_RES, 8
        .set RS_END, 16
        .set RS_REST, 24
        .set RS_KEPT, 32
        .set RS_K, 40
        .set RS_TMP, 48
        mov rbx, rdi
        mov [rsp + RS_AFTER], rsi
        call vec_new
        mov [rsp + RS_RES], rax
        xor r12d, r12d                  # idx
.Lrs_line:
        cmp r12d, [rbx + N_AUX]
        jae .Lrs_done
        mov r13, [rbx + N_DATA + r12*8]
        mov rdi, r13
        call opcode_of
        cmp eax, OP_STORE
        jne 1f
        mov rdi, rbx
        mov rsi, r12
        lea rdx, [rsp + RS_END]
        call string_store
        test rax, rax
        jz 1f
        mov rdi, [rsp + RS_RES]
        mov rsi, rax
        call vec_push
        # the variables set between the two loops were for the second
        # one, unless they're used further on
        mov rdi, rbx
        mov rsi, [rsp + RS_END]
        call list_from
        mov rdi, rax
        mov rsi, [rsp + RS_AFTER]
        call list_concat
        mov [rsp + RS_REST], rax
        xor edi, edi
        xor esi, esi
        call mk_list
        mov [rsp + RS_KEPT], rax
        mov rax, [rsp + RS_END]
        sub rax, 2
        mov [rsp + RS_K], rax           # from end - 2 down to idx + 2
2:      mov rax, [rsp + RS_K]
        lea rcx, [r12 + 2]
        cmp rax, rcx
        jl 3f
        mov r14, [rbx + N_DATA + rax*8] # a setvar
        LOADS rdi, VAR
        mov rsi, [r14 + N_DATA + 8]
        call mk2
        mov [rsp + RS_TMP], rax
        mov rdi, [rsp + RS_KEPT]
        mov rsi, [rsp + RS_REST]
        call list_concat
        mov rdi, rax
        mov rsi, [rsp + RS_TMP]
        call contains
        test eax, eax
        jz 21f
        mov rdi, r14
        call mk_list1
        mov rdi, rax
        mov rsi, [rsp + RS_KEPT]
        call list_concat
        mov [rsp + RS_KEPT], rax
21:     dec qword ptr [rsp + RS_K]
        jmp 2b
3:      mov rdi, [rsp + RS_RES]
        mov rsi, [rsp + RS_KEPT]
        call vec_extend_seq
        mov r12, [rsp + RS_END]
        jmp .Lrs_line
1:      mov rdi, r13
        call is_if_line
        test eax, eax
        jz 4f
        mov rdi, rbx
        lea rsi, [r12 + 1]
        call list_from
        mov rdi, rax
        mov rsi, [rsp + RS_AFTER]
        call list_concat
        mov [rsp + RS_REST], rax
        mov rdi, [r13 + N_DATA + 16]
        mov rsi, rax
        call rewrite_string_stores
        mov [rsp + RS_KEPT], rax
        mov rdi, [r13 + N_DATA + 24]
        mov rsi, [rsp + RS_REST]
        call rewrite_string_stores
        mov rdx, rax
        mov rsi, [rsp + RS_KEPT]
        mov rdi, [r13 + N_DATA + 8]
        call mk_if
        mov r13, rax
        jmp 5f
4:      mov rdi, r13
        call is_while_line
        test eax, eax
        jz 5f
        mov rdi, rbx
        mov rsi, r12
        call list_from
        mov rdi, rax
        mov rsi, [rsp + RS_AFTER]
        call list_concat
        mov rdi, [r13 + N_DATA + 16]
        mov rsi, rax
        call rewrite_string_stores
        mov rsi, rax
        mov rdi, [r13 + N_DATA + 8]
        mov rdx, [r13 + N_DATA + 24]
        mov rcx, [r13 + N_DATA + 32]
        call mk_while
        mov r13, rax
5:      mov rdi, [rsp + RS_RES]
        mov rsi, r13
        call vec_push
        inc r12d
        jmp .Lrs_line
.Lrs_done:
        mov rdi, [rsp + RS_RES]
        call vec_to_list
        add rsp, 64
        LEAVE
ENDF rewrite_string_stores

        .section .note.GNU-stack,"",@progbits
