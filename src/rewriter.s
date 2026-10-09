# The last-minute rewrites (port of rewriter.py and postprocess.py):
# heuristics that make a lot of contracts more readable.

.include "defs.inc"

        .section .rodata
.Ls_assert_mul:     .asciz "cleanup_mul_1: a mul with too few terms"
.Ls_empty:          .asciz ""

        .text

.macro B reg, n
        mov \reg, [rsp + 8*(\n)]
.endm

# --- postprocess.cleanup_mul_1 ---

# pp_cleanup_exp(exp) -> value (remembered for the tuples: a pure
# function, asked of the same expressions at every round)
FUNC pp_cleanup_exp
        STACK_CHECK
        ENTER
        mov rbx, rdi
        call is_tuple
        test eax, eax
        jz 1f
        mov edi, MEMO_PP_CLEANUP
        mov rsi, rbx
        call memo_get
        test rax, rax
        jnz 2f
        mov rdi, rbx
        call pp_cleanup_exp_impl
        mov r12, rax
        mov edi, MEMO_PP_CLEANUP
        mov rsi, rbx
        mov rdx, rax
        call memo_put
        mov rax, r12
2:      LEAVE
1:      mov rax, rbx
        LEAVE
ENDF pp_cleanup_exp

# pp_cleanup_exp_impl(tuple) -> value
FUNC pp_cleanup_exp_impl
        STACK_CHECK
        ENTER
        sub rsp, 16
        mov rbx, rdi
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
        call int_lt_pow2_256            # (python's e < 0x100**32: the
        test eax, eax                   # negative ones too)
        jz 3f
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
        mov rdi, rbx                    # (what's bytes as wide as it was)
        mov rsi, rax
        call keep_widths
.Lpce_done:
        add rsp, 16
        LEAVE
.Lpce_assert:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_mul]
        call err_throw
ENDF pp_cleanup_exp_impl

FUNC pp_cleanup_cb
        STACK_CHECK
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
        STACK_CHECK
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
        STACK_CHECK
        ENTER
        mov rbx, rdi
        test dil, 1
        jnz 1f
        test rdi, rdi
        jz 1f
        cmp dword ptr [rdi + N_KIND], K_LIST
        jne 1f
        mov edi, MEMO_PP_CLEANUP        # (a list: remembered, the lines
        mov rsi, rbx                    # of the rounds mostly the same)
        call memo_get
        test rax, rax
        jnz 2f
        mov rdi, rbx
        lea rsi, [rip + pp_cleanup_line_cb]
        call map_seq
        mov r12, rax
        mov edi, MEMO_PP_CLEANUP
        mov rsi, rbx
        mov rdx, rax
        call memo_put
        mov rax, r12
2:      LEAVE
1:      mov rdi, rbx
        lea rsi, [rip + pp_cleanup_line_cb]
        call map_seq
        LEAVE
ENDF pp_cleanup_mul_1

# --- rewriter.postprocess_exp ---

# postprocess_exp(exp, arg) -> value: an array in a list of data - its
# offset, then after the other words its length and content - as
# ('arr', len, data...), that is ABI-encoded: its content padded with
# zeroes to whole words. Where the data has that padding only: its content
# is whole words, or is as many bytes as its length followed by the
# zeroes up to them.
FUNC postprocess_exp
        ENTER
        sub rsp, 48
        .set PE_LOC, 0                  # the offset's index in exp
        .set PE_N, 8                    # len(terms)
        .set PE_KEEP, 16                # the content's elements kept
        .set PE_VEC, 24
        mov rbx, rdi
        call opcode_of
        cmp eax, OP_DATA
        jne .Lpe_asis
        # one term a number multiple of 32 (python's %: a negative or a
        # big one too)
        mov eax, [rbx + N_AUX]
        dec eax
        mov [rsp + PE_N], rax
        xor r12d, r12d                  # how many
        mov r13d, 1
1:      cmp r13d, [rbx + N_AUX]
        jae 2f
        mov rdi, [rbx + N_DATA + r13*8]
        inc r13d
        call is_int
        test eax, eax
        jz 1b
        mov rdi, [rbx + N_DATA + r13*8 - 8]
        mov esi, 5
        call int_mod_2exp
        cmp rax, 1
        jne 1b
        inc r12d
        lea rax, [r13 - 1]
        mov [rsp + PE_LOC], rax
        jmp 1b
2:      cmp r12d, 1
        jne .Lpe_asis
        # loc = concrete // 32: loc + 1 < len(terms) and loc > the
        # offset's index (a big loc is neither)
        mov rax, [rsp + PE_LOC]
        mov rdi, [rbx + N_DATA + rax*8]
        test dil, 1
        jz .Lpe_asis
        sar rdi, 6                      # (untagged, // 32)
        mov r14, rdi                    # loc
        lea rax, [r14 + 1]
        cmp rax, [rsp + PE_N]
        jge .Lpe_asis
        mov rax, [rsp + PE_LOC]
        dec rax                         # its index among the terms
        cmp r14, rax
        jle .Lpe_asis
        # the offset is one of words up to the length
        xor r12d, r12d
3:      cmp r12, r14
        ja 4f
        mov rdi, [rbx + N_DATA + 8 + r12*8]
        inc r12
        call sizeof
        cmp rax, (256 << 1) | 1
        jne .Lpe_asis
        jmp 3b
4:      mov rdi, [rbx + N_DATA + 8 + r14*8]     # terms[loc], terms[loc + 1:]
        lea rsi, [rbx + N_DATA + 16 + r14*8]
        mov rdx, [rsp + PE_N]
        sub rdx, r14
        dec rdx
        call abi_content
        test rax, rax
        js .Lpe_asis
        mov [rsp + PE_KEEP], rax
        # ('arr', length) + content
        call vec_new
        mov [rsp + PE_VEC], rax
        mov rdi, rax
        LOADS rsi, ARR
        call vec_push
        mov rdi, [rsp + PE_VEC]
        mov rsi, [rbx + N_DATA + 8 + r14*8]
        call vec_push
        mov rdi, [rsp + PE_VEC]
        lea rsi, [rbx + N_DATA + 16 + r14*8]
        mov rdx, [rsp + PE_KEEP]
        call vec_extend
        mov rdi, [rsp + PE_VEC]
        call vec_to_tuple
        mov r13, rax                    # arr
        # ('data',) + the terms before loc, the offset replaced by the array
        call vec_new
        mov [rsp + PE_VEC], rax
        mov rdi, rax
        LOADS rsi, DATA
        call vec_push
        mov r12, r14
        shl r12, 5
        TAG r12                         # loc * 32
        mov qword ptr [rsp + PE_KEEP], 0
5:      mov rcx, [rsp + PE_KEEP]
        cmp rcx, r14
        jae 6f
        mov rdi, [rbx + N_DATA + 8 + rcx*8]
        inc qword ptr [rsp + PE_KEEP]
        mov [rsp + PE_LOC], rdi
        mov rsi, r12
        call py_equal
        mov rsi, [rsp + PE_LOC]
        test eax, eax
        cmovnz rsi, r13
        mov rdi, [rsp + PE_VEC]
        call vec_push
        jmp 5b
6:      mov rdi, [rsp + PE_VEC]
        call vec_to_tuple
        add rsp, 48
        LEAVE
.Lpe_asis:
        mov rax, rbx
        add rsp, 48
        LEAVE
ENDF postprocess_exp

# abi_content(length, content, count) -> rax: what an Array(len=length,
# data=...) of the bytes of content (count values) is printed with, as how
# many of them it keeps - all of them if they're whole words (padding them
# adds nothing); without the zeroes after its `length` bytes up to whole
# words - -1 (python's None) if they're neither
FUNC abi_content
        ENTER
        sub rsp, 32
        .set AC_LENGTH, 0
        .set AC_SIZE, 8
        .set AC_WORDS, 16
        mov [rsp + AC_LENGTH], rdi
        mov rbx, rsi
        mov r12, rdx
        mov rdi, rsi
        mov rsi, rdx
        call byte_size
        mov [rsp + AC_SIZE], rax
        # the data without its zeroes at the end
        mov r13, r12
1:      test r13, r13
        jz 2f
        mov rdi, [rbx + r13*8 - 8]
        mov esi, 1
        call py_equal
        test eax, eax
        jnz 11f
        mov rdi, [rbx + r13*8 - 8]
        PATXD "('bytes', 'Any', 0)"
        test eax, eax
        jz 2f
11:     dec r13
        jmp 1b
2:      # ('mask_shl', 251, 5, 0, 31 + length): its whole words
        mov edi, (31 << 1) | 1
        mov rsi, [rsp + AC_LENGTH]
        call alg_add2
        mov r8, rax
        LOADS rdi, MASK_SHL
        mov esi, (251 << 1) | 1
        mov edx, (5 << 1) | 1
        mov ecx, 1
        call mk5
        mov [rsp + AC_WORDS], rax
        cmp qword ptr [rsp + AC_SIZE], 0
        je 9f
        mov rdi, rbx
        mov rsi, r13
        call byte_size
        mov rdi, rax
        call none_if_nil
        mov rdi, rax
        mov rsi, [rsp + AC_LENGTH]
        call alg_sub_op
        cmp rax, 1
        jne 3f
        mov rdi, [rsp + AC_SIZE]
        mov rsi, [rsp + AC_WORDS]
        call alg_sub_op
        cmp rax, 1
        jne 3f
        mov rax, r13
        jmp 8f
3:      mov rdi, [rsp + AC_SIZE]
        call low_zero_bits
        mov rdi, rax
        mov esi, (5 << 1) | 1
        call int_cmp
        test eax, eax
        js 9f
        mov rax, r12
8:      add rsp, 32
        LEAVE
9:      mov rax, -1
        add rsp, 32
        LEAVE
ENDF abi_content

# byte_size(terms, count) -> rax: how many bytes the elements of a data
# are, NIL if that's not known
FUNC byte_size
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 16
        mov rbx, rdi
        mov r12, rsi
        mov r13d, 1                     # res (0)
        xor r14d, r14d
1:      cmp r14, r12
        jae 8f
        mov rdi, [rbx + r14*8]
        inc r14
        PATXD "('bytes', ':n', 'Any')"
        test eax, eax
        jnz 5f
        mov rdi, [rbx + r14*8 - 8]
        PAT rsi, "(':op', 'Any', ':n')"
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 2f
        mov rdi, [rsp]
        call str_id
        mov edi, eax
        call is_array_op
        test eax, eax
        jz 2f
        mov rax, [rsp + 8]
        mov [rsp], rax
        jmp 5f
2:      mov rdi, [rbx + r14*8 - 8]
        PATXD "('mem', ('range', 'Any', ':n'))"
        test eax, eax
        jnz 5f
        mov rdi, [rbx + r14*8 - 8]
        call sizeof
        mov [rsp + MATCH_BINDINGS_SIZE], rax
        mov rdi, rax
        call is_int
        test eax, eax
        jz 9f
        mov rdi, [rsp + MATCH_BINDINGS_SIZE]
        mov esi, 3
        call int_mod_2exp
        cmp rax, 1
        jne 9f
        mov rdi, [rsp + MATCH_BINDINGS_SIZE]
        mov esi, (8 << 1) | 1
        call int_floordiv
        mov [rsp], rax
5:      mov rdi, r13
        mov rsi, [rsp]
        call alg_add2
        mov r13, rax
        jmp 1b
8:      mov rax, r13
        add rsp, MATCH_BINDINGS_SIZE + 16
        LEAVE
9:      xor eax, eax
        add rsp, MATCH_BINDINGS_SIZE + 16
        LEAVE
ENDF byte_size

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
        STACK_CHECK
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
        sub rsp, MATCH_BINDINGS_SIZE + 48
        .set PT_OUT, MATCH_BINDINGS_SIZE
        .set PT_L, MATCH_BINDINGS_SIZE + 8
        .set PT_TRUE, MATCH_BINDINGS_SIZE + 16
        .set PT_FALSE, MATCH_BINDINGS_SIZE + 24
        .set PT_COUNT, MATCH_BINDINGS_SIZE + 32
        mov rbx, rdi
        mov [rsp + PT_OUT], rdx
        # an if on the length of a storage string/array whose branches
        # both hold the array as many times: the true branch alone
        PAT rsi, "('if', ('iszero', ('storage', 5, 0, ':l')), ':if_true', ':if_false')"
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 1f
        lea rax, [rip + collect_arr_storage]
        jmp .Lpt_counts
1:      PAT rsi, "('if', ('iszero', ('mask_shl', 5, 0, 0, ':l')), ':if_true', ':if_false')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 2f
        lea rax, [rip + collect_arr_l]
.Lpt_counts:
        mov r12, rax
        B rax, 0
        mov [rsp + PT_L], rax
        B rax, 1
        mov [rsp + PT_TRUE], rax
        B rax, 2
        mov [rsp + PT_FALSE], rax
        mov rdi, [rsp + PT_TRUE]
        mov rsi, r12
        mov rdx, [rsp + PT_L]
        call count_found
        mov [rsp + PT_COUNT], rax
        mov rdi, [rsp + PT_FALSE]
        mov rsi, r12
        mov rdx, [rsp + PT_L]
        call count_found
        cmp qword ptr [rsp + PT_COUNT], 0
        je 11f
        cmp rax, [rsp + PT_COUNT]
        jne 11f
        mov rdi, [rsp + PT_OUT]
        mov rsi, [rsp + PT_TRUE]
        call vec_extend_seq
        jmp .Lpt_done
11:     jmp .Lpt_asis                   # (an iszero isn't the next patterns')
2:      # a string written to storage: when it's longer than 31 bytes, it
        # isn't empty - the check that it is can go
        PAT rsi, "('if', ('lt', 31, ':some_len'), ':if_true', ':if_false')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz .Lpt_asis
        B r12, 1                        # if_true
        mov rdi, r12
        call is_seq
        test eax, eax
        jz .Lpt_asis
        cmp dword ptr [r12 + N_AUX], 2
        jb .Lpt_asis
        mov r13, [r12 + N_DATA]         # first
        mov rdi, r13
        call opcode_of
        cmp eax, OP_STORE
        jne .Lpt_asis
        mov rdi, r13
        B rsi, 0
        call contains
        test eax, eax
        jz .Lpt_asis
        B rdi, 0
        call mk_iszero_of
        mov [rsp + PT_L], rax
        mov r14, [r12 + N_DATA + 8]     # second
        mov rdi, r14
        call is_if_line
        test eax, eax
        jz .Lpt_asis
        mov rax, [r14 + N_DATA + 8]
        cmp rax, [rsp + PT_L]
        jne .Lpt_asis
        # ('if', ('lt', 31, some_len), [first] + deep_false + rest, if_false)
        call vec_new
        mov [rsp + PT_COUNT], rax
        mov rdi, rax
        mov rsi, r13
        call vec_push
        mov rdi, [rsp + PT_COUNT]
        mov rsi, [r14 + N_DATA + 24]
        call vec_extend_seq
        mov edx, [r12 + N_AUX]
        sub edx, 2
        lea rsi, [r12 + N_DATA + 16]
        mov rdi, [rsp + PT_COUNT]
        call vec_extend
        mov rdi, [rsp + PT_COUNT]
        call vec_to_list
        mov r12, rax
        LOADS rdi, LT
        mov esi, (31 << 1) | 1
        B rdx, 0
        call mk3
        mov rdi, rax
        mov rsi, r12
        B rdx, 2
        call mk_if
        mov rdi, [rsp + PT_OUT]
        mov rsi, rax
        call vec_push
        jmp .Lpt_done
.Lpt_asis:
        mov rdi, [rsp + PT_OUT]
        mov rsi, rbx
        call vec_push
.Lpt_done:
        add rsp, MATCH_BINDINGS_SIZE + 48
        LEAVE
ENDF postprocess_trace


        .section .note.GNU-stack,"",@progbits
