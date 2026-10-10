# Conditions (port of simplify.py's cond_bounds, decide_le,
# apply_constraint, min_ifs, precompiled_results, changes_reads and
# changes_value): what a condition says of the values it compares, the
# mins it decides, the results of the precompiled contracts read as the
# words they return, and what a line changes of what an expression reads.

.include "defs.inc"

        .section .rodata
.Ls_cn_index:   .asciz "tuple index out of range"
.Ls_cn_type:    .asciz "can only concatenate list (not another type) to list"
.Ls_min:        .asciz "min"
.Ls_po_sha256:  .asciz "sha256hash.result"
.Ls_po_ripemd:  .asciz "ripemd160hash.result"
.Ls_po_add:     .asciz "bn256Add.result"
.Ls_po_mul:     .asciz "bn256ScalarMul.result"
.Ls_po_pairing: .asciz "bn256Pairing.result"
        .text

.macro B reg, n
        mov \reg, [rsp + 8*(\n)]
.endm

# cn_index_error(): python's IndexError (a line too short for what's read
# of it)
FUNC cn_index_error
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_cn_index]
        jmp err_throw
ENDF cn_index_error

# tuple_with(t, i, v) -> rax: the tuple t with its element i replaced by v
FUNC tuple_with
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov edi, [rbx + N_AUX]
        shl rdi, 3
        call arena_alloc_raw            # (every element written)
        mov r14, rax
        xor ecx, ecx
1:      cmp ecx, [rbx + N_AUX]
        jae 2f
        mov rax, [rbx + N_DATA + rcx*8]
        mov [r14 + rcx*8], rax
        inc ecx
        jmp 1b
2:      mov [r14 + r12*8], r13
        mov edi, [rbx + N_AUX]
        mov rsi, r14
        call mk_tuple
        LEAVE
ENDF tuple_with

# tuple_prepend(t, v) -> rax: python's (v,) + t
FUNC tuple_prepend
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov edi, [rbx + N_AUX]
        inc edi
        shl rdi, 3
        call arena_alloc_raw            # (every element written)
        mov r13, rax
        mov [r13], r12
        xor ecx, ecx
1:      cmp ecx, [rbx + N_AUX]
        jae 2f
        mov rax, [rbx + N_DATA + rcx*8]
        mov [r13 + rcx*8 + 8], rax
        inc ecx
        jmp 1b
2:      mov edi, [rbx + N_AUX]
        inc edi
        mov rsi, r13
        call mk_tuple
        LEAVE
ENDF tuple_prepend

# --- what a condition says of what it compares ---

# precompiled_output(v) -> rax: the bytes the precompiled contract whose
# result v names returns every time its call goes through (python's
# PRECOMPILED_OUTPUT: a word, or two), tagged; 0 when v isn't one
FUNC precompiled_output
        ENTER
        mov rbx, rdi
        test dil, 1
        jnz 8f
        test rdi, rdi
        jz 8f
        cmp dword ptr [rdi + N_KIND], K_STR
        jne 8f
        lea r12, [rbx + N_DATA + 4]
        mov rdi, r12
        lea rsi, [rip + .Ls_po_sha256]
        call strcmp@PLT
        test eax, eax
        jz 1f
        mov rdi, r12
        lea rsi, [rip + .Ls_po_ripemd]
        call strcmp@PLT
        test eax, eax
        jz 1f
        mov rdi, r12
        lea rsi, [rip + .Ls_po_pairing]
        call strcmp@PLT
        test eax, eax
        jz 1f
        mov rdi, r12
        lea rsi, [rip + .Ls_po_add]
        call strcmp@PLT
        test eax, eax
        jz 2f
        mov rdi, r12
        lea rsi, [rip + .Ls_po_mul]
        call strcmp@PLT
        test eax, eax
        jz 2f
8:      xor eax, eax
        LEAVE
1:      mov eax, (32 << 1) | 1
        LEAVE
2:      mov eax, (64 << 1) | 1
        LEAVE
ENDF precompiled_output

        OPSET_MEMBER cb_ops, OP_LT
        OPSET_MEMBER cb_ops, OP_GT
        OPSET_MEMBER cb_ops, OP_LE
        OPSET_MEMBER cb_ops, OP_GE
        OPSET_MEMBER cb_ops, OP_EQ
        OPSET_MEMBER cb_ops, OP_SLT
        OPSET_MEMBER cb_ops, OP_SGT
        OPSET_MEMBER cb_ops, OP_SLE
        OPSET_MEMBER cb_ops, OP_SGE
        OPSET_END cb_ops, OP_COUNT

# cond_bounds(cond) -> rax: python's cond_bounds - {x: (lowest, highest)}:
# the values an expression x can have where the condition holds, when it's
# a comparison of x with a number (unsigned) - or the success of a call to
# a precompiled contract that returns as many bytes every time: then
# returndatasize is that. A vec of triples x, lo, hi; NIL for {}.
FUNC cond_bounds
        STACK_CHECK
        ENTER
        sub rsp, 48
        .set CB_NEG, 0
        .set CB_OP, 8
        .set CB_A, 16
        .set CB_B, 24
        .set CB_LO, 32
        .set CB_HI, 40
        mov rbx, rdi
        mov qword ptr [rsp + CB_NEG], 0
1:      mov rdi, rbx
        OPCODE_OF_RDI
        cmp eax, OP_ISZERO
        je 2f
        cmp eax, OP_BOOL
        jne 3f
        jmp 21f
2:      xor qword ptr [rsp + CB_NEG], 1
21:     cmp dword ptr [rbx + N_AUX], 2
        jb .Lcb_index
        mov rbx, [rbx + N_DATA + 8]
        jmp 1b
3:      mov rdi, rbx
        call precompiled_output
        test rax, rax
        jz 4f
        cmp qword ptr [rsp + CB_NEG], 0
        jne .Lcb_none
        mov [rsp + CB_LO], rax
        mov [rsp + CB_HI], rax
        LOADS rax, RETURNDATASIZE
        mov [rsp + CB_A], rax
        jmp .Lcb_one
4:      mov rdi, rbx
        OPCODE_OF_RDI
        mov [rsp + CB_OP], rax
        IN_OPSET cb_ops, rax
        je .Lcb_none
        cmp dword ptr [rbx + N_AUX], 3
        jne .Lcb_none
        mov rax, [rbx + N_DATA + 8]
        mov [rsp + CB_A], rax
        mov rax, [rbx + N_DATA + 16]
        mov [rsp + CB_B], rax
        # c < x is x > c...
        mov rdi, [rsp + CB_A]
        call is_int
        test eax, eax
        jz 5f
        mov rdi, [rsp + CB_B]
        call is_int
        test eax, eax
        jnz 5f
        mov rax, [rsp + CB_A]
        mov rcx, [rsp + CB_B]
        mov [rsp + CB_A], rcx
        mov [rsp + CB_B], rax
        mov rax, [rsp + CB_OP]
        mov ecx, OP_GT
        cmp eax, OP_LT
        je 41f
        mov ecx, OP_LT
        cmp eax, OP_GT
        je 41f
        mov ecx, OP_GE
        cmp eax, OP_LE
        je 41f
        mov ecx, OP_LE
        cmp eax, OP_GE
        je 41f
        mov ecx, OP_SGT
        cmp eax, OP_SLT
        je 41f
        mov ecx, OP_SLT
        cmp eax, OP_SGT
        je 41f
        mov ecx, OP_SGE
        cmp eax, OP_SLE
        je 41f
        mov ecx, OP_SLE
        cmp eax, OP_SGE
        je 41f
        mov ecx, eax                    # eq
41:     mov [rsp + CB_OP], rcx
5:      mov rdi, [rsp + CB_B]           # a number, the other side not one,
        call is_int                     # 0 <= b < 2**256
        test eax, eax
        jz .Lcb_none
        mov rdi, [rsp + CB_A]
        call is_int
        test eax, eax
        jnz .Lcb_none
        mov rdi, [rsp + CB_B]
        call int_sign
        test eax, eax
        js .Lcb_none
        mov rdi, [rsp + CB_B]
        call int_bit_length
        cmp rax, 256
        ja .Lcb_none
        # signed: as unsigned, of a size far below 2**255 (see
        # memloc.max_value_bits) and a positive number
        mov rax, [rsp + CB_OP]
        mov ecx, OP_LT
        cmp eax, OP_SLT
        je 6f
        mov ecx, OP_GT
        cmp eax, OP_SGT
        je 6f
        mov ecx, OP_LE
        cmp eax, OP_SLE
        je 6f
        mov ecx, OP_GE
        cmp eax, OP_SGE
        jne 7f
6:      mov [rsp + CB_OP], rcx
        mov rdi, [rsp + CB_A]
        xor esi, esi
        call max_value_bits
        mov rdi, rax
        mov esi, (255 << 1) | 1
        call int_cmp
        test eax, eax
        jns .Lcb_none
        mov rdi, [rsp + CB_B]
        call int_bit_length
        cmp rax, 255
        ja .Lcb_none
7:      cmp qword ptr [rsp + CB_NEG], 0
        je 8f
        mov rax, [rsp + CB_OP]
        cmp eax, OP_EQ
        je .Lcb_none
        mov ecx, OP_GE
        cmp eax, OP_LT
        je 71f
        mov ecx, OP_LT
        cmp eax, OP_GE
        je 71f
        mov ecx, OP_LE
        cmp eax, OP_GT
        je 71f
        mov ecx, OP_GT
71:     mov [rsp + CB_OP], rcx
8:      # lo, hi
        mov rax, [rsp + CB_OP]
        cmp eax, OP_LT
        je 81f
        cmp eax, OP_LE
        je 82f
        cmp eax, OP_GT
        je 83f
        cmp eax, OP_GE
        je 84f
        mov rax, [rsp + CB_B]           # eq: (b, b)
        mov [rsp + CB_LO], rax
        mov [rsp + CB_HI], rax
        jmp 89f
81:     mov qword ptr [rsp + CB_LO], 1  # lt: (0, b - 1)
        mov rdi, [rsp + CB_B]
        mov esi, 3
        call int_sub
        mov [rsp + CB_HI], rax
        jmp 89f
82:     mov qword ptr [rsp + CB_LO], 1  # le: (0, b)
        mov rax, [rsp + CB_B]
        mov [rsp + CB_HI], rax
        jmp 89f
83:     mov rdi, [rsp + CB_B]           # gt: (b + 1, top)
        mov esi, 3
        call int_add
        mov [rsp + CB_LO], rax
        mov rax, [rip + vr_word_top_v]
        mov [rsp + CB_HI], rax
        jmp 89f
84:     mov rax, [rsp + CB_B]           # ge: (b, top)
        mov [rsp + CB_LO], rax
        mov rax, [rip + vr_word_top_v]
        mov [rsp + CB_HI], rax
89:     mov rdi, [rsp + CB_LO]
        mov rsi, [rsp + CB_HI]
        call int_cmp
        test eax, eax
        jg .Lcb_none
.Lcb_one:
        call vec_new
        mov r12, rax
        mov rdi, rax
        mov rsi, [rsp + CB_A]
        mov rdx, [rsp + CB_LO]
        mov rcx, [rsp + CB_HI]
        call bounds_put
        # (each of a min's terms is at least what the smaller one is)
        mov rdi, [rsp + CB_A]
        OPCODE_OF_RDI
        cmp eax, OP_MIN
        jne 99f
        mov rbx, [rsp + CB_A]
        mov r13d, 1
91:     cmp r13d, [rbx + N_AUX]
        jae 99f
        mov r14, [rbx + N_DATA + r13*8]
        inc r13d
        mov rdi, r14
        call is_int
        test eax, eax
        jnz 91b
        mov rdi, r12
        mov rsi, r14
        mov rdx, [rsp + CB_LO]
        mov rcx, [rip + vr_word_top_v]
        call bounds_put
        jmp 91b
99:     mov rax, r12
        add rsp, 48
        LEAVE
.Lcb_none:
        xor eax, eax
        add rsp, 48
        LEAVE
.Lcb_index:
        call cn_index_error
ENDF cond_bounds

# bounds_put(bounds, x, lo, hi): python's bounds[x] = (lo, hi)
FUNC bounds_put
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov r14, rcx
        call bounds_get
        test rax, rax
        jz 1f
        mov [rax], r13
        mov [rax + 8], r14
        LEAVE
1:      mov rdi, rbx
        mov rsi, r12
        call vec_push
        mov rdi, rbx
        mov rsi, r13
        call vec_push
        mov rdi, rbx
        mov rsi, r14
        call vec_push
        LEAVE
ENDF bounds_put

# bounds_get(bounds, x) -> rax: where bounds[x]'s (lo, hi) are (two words),
# or 0 when x isn't a key
FUNC bounds_get
        ENTER
        mov rbx, rdi
        mov r12, rsi
        xor r13d, r13d
1:      cmp r13, [rbx + VEC_LEN]
        jae 2f
        mov rax, [rbx + VEC_DATA]
        mov rdi, [rax + r13*8]
        mov rsi, r12
        call values_equal
        test eax, eax
        jnz 3f
        add r13, 3
        jmp 1b
2:      xor eax, eax
        LEAVE
3:      mov rax, [rbx + VEC_DATA]
        lea rax, [rax + r13*8 + 8]
        LEAVE
ENDF bounds_get

# decide_le(a, b, bounds) -> eax: python's decide_le - a <= b by the bounds
# of cond_bounds, TRI_NONE if they don't say - as the words they are, as the
# bounds are (-1 is 2**256 - 1)
FUNC decide_le
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        call is_int
        test eax, eax
        jz 2f
        mov rdi, r13
        mov rsi, r12
        call bounds_get
        test rax, rax
        jz 2f
        mov r14, rax
        mov rdi, rbx
        mov esi, 256
        call int_mod_2exp
        mov [rsp], rax
        mov rdi, [r14]                  # lo >= a: True
        mov rsi, rax
        call int_cmp
        test eax, eax
        jns .Ldl_true
        mov rdi, [r14 + 8]              # hi < a: False
        mov rsi, [rsp]
        call int_cmp
        test eax, eax
        js .Ldl_false
        jmp .Ldl_none
2:      mov rdi, r12
        call is_int
        test eax, eax
        jz .Ldl_none
        mov rdi, r13
        mov rsi, rbx
        call bounds_get
        test rax, rax
        jz .Ldl_none
        mov r14, rax
        mov rdi, r12
        mov esi, 256
        call int_mod_2exp
        mov [rsp], rax
        mov rdi, [r14 + 8]              # hi <= b: True
        mov rsi, rax
        call int_cmp
        cmp eax, 0
        jle .Ldl_true
        mov rdi, [r14]                  # lo > b: False
        mov rsi, [rsp]
        call int_cmp
        cmp eax, 0
        jg .Ldl_false
.Ldl_none:
        mov eax, TRI_NONE
        add rsp, 16
        LEAVE
.Ldl_true:
        mov eax, TRI_TRUE
        add rsp, 16
        LEAVE
.Ldl_false:
        mov eax, TRI_FALSE
        add rsp, 16
        LEAVE
ENDF decide_le


# apply_constraint(exp, constr) -> rax: python's apply_constraint - exp,
# where the condition constr holds: a min of two values it decides is one
# of them - min(32, return_data.size), the size of what a call wrote, is 32
# once return_data.size >= 32
FUNC apply_constraint
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call mentions_min               # ("min" in str(exp))
        test eax, eax
        jz 9f
        mov rdi, r12
        call cond_bounds
        test rax, rax
        jz 9f
        mov rdx, rax
        mov rdi, rbx
        lea rsi, [rip + apply_constraint_f]
        call replace_f
        LEAVE
9:      mov rax, rbx
        LEAVE
ENDF apply_constraint

# mentions_min(exp) -> eax: python's "min" in str(exp) (mentions_c), a
# tuple's and a list's remembered (MEMO_MENTIONS_MIN): replace_mem asks
# it of the memory it replaces and of its value at every if of the rest
# of the trace, for both branches - the same expressions, walked whole
# each time (a memmem of every string: 1.4% of the corpus' time)
FUNC mentions_min
        test dil, 1
        jnz 8f
        test rdi, rdi
        jz 8f
        mov eax, [rdi + N_KIND]
        cmp eax, K_TUPLE
        je 1f
        cmp eax, K_LIST
        je 1f
        lea rsi, [rip + .Ls_min]
        jmp mentions_c
1:      ENTER
        mov rbx, rdi
        mov edi, MEMO_MENTIONS_MIN
        mov rsi, rbx
        call memo_get
        test rax, rax
        jz 2f
        cmp rax, MEMO_TRUE
        sete al
        movzx eax, al
        LEAVE
2:      mov rdi, rbx
        lea rsi, [rip + .Ls_min]
        call mentions_c
        mov r12d, eax
        mov edi, MEMO_MENTIONS_MIN
        mov rsi, rbx
        mov edx, MEMO_FALSE
        mov ecx, MEMO_TRUE
        test r12d, r12d
        cmovnz edx, ecx
        call memo_put
        mov eax, r12d
        LEAVE
8:      xor eax, eax
        ret
ENDF mentions_min

# apply_constraint_f(e, bounds): a min of two that the bounds decide
FUNC apply_constraint_f
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov esi, OP_MIN
        mov edx, 3
        call is_op_n
        test eax, eax
        jz 9f
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, [rbx + N_DATA + 16]
        mov rdx, r12
        call decide_le
        cmp eax, TRI_TRUE
        jne 1f
        mov rax, [rbx + N_DATA + 8]
        LEAVE
1:      cmp eax, TRI_FALSE
        jne 9f
        mov rax, [rbx + N_DATA + 16]
        LEAVE
9:      mov rax, rbx
        LEAVE
ENDF apply_constraint_f

# --- the mins of the ifs, the results of the precompiled contracts ---

# min_ifs(trace) -> list: python's min_ifs - `if a > b: v = b else: v = a`
# is `v = min(a, b)`: the size of what a call returned that solc decodes,
# at most as much as it expects
FUNC min_ifs
        STACK_CHECK
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 48
        .set MI_COND, MATCH_BINDINGS_SIZE
        .set MI_TRUE, MATCH_BINDINGS_SIZE + 8
        .set MI_FALSE, MATCH_BINDINGS_SIZE + 16
        .set MI_V, MATCH_BINDINGS_SIZE + 24
        .set MI_X, MATCH_BINDINGS_SIZE + 32
        .set MI_Y, MATCH_BINDINGS_SIZE + 40
        # the trace, python's TypeError for what isn't one: the recursion
        # below goes into a while's body (line[2]) on the opcode alone,
        # and a body that is a number had its N_AUX read from that
        # address. The VM and whiles build the lines whole, so no
        # bytecode reaches this; a trace handed to the test interface can
        IS_SEQ_RDI
        test eax, eax
        jz .Lmi_type
        mov rbx, rdi
        call vec_new
        mov r12, rax
        xor r13d, r13d
.Lmi_line:
        cmp r13d, [rbx + N_AUX]
        jae .Lmi_done
        mov r14, [rbx + N_DATA + r13*8]
        inc r13d
        mov rdi, r14
        OPCODE_OF_RDI
        cmp eax, OP_WHILE
        jne 2f
        # ('while', line[1], min_ifs(line[2])) + tuple(line[3:])
        cmp dword ptr [r14 + N_AUX], 3
        jb .Lmi_index
        mov rdi, [r14 + N_DATA + 16]
        call min_ifs
        mov rdi, r14
        mov esi, 2
        mov rdx, rax
        call tuple_with
        mov r14, rax
        jmp .Lmi_push
2:      mov rdi, r14
        call is_if_line
        test eax, eax
        jz .Lmi_push
        mov rax, [r14 + N_DATA + 8]
        mov [rsp + MI_COND], rax
        mov rdi, [r14 + N_DATA + 16]
        call min_ifs
        mov [rsp + MI_TRUE], rax
        mov rdi, [r14 + N_DATA + 24]
        call min_ifs
        mov [rsp + MI_FALSE], rax
        mov rdi, [rsp + MI_COND]
        mov rsi, [rsp + MI_TRUE]
        mov rdx, rax
        call mk_if
        mov r14, rax
        # one setvar of the same variable in each branch
        mov rax, [rsp + MI_TRUE]
        cmp dword ptr [rax + N_AUX], 1
        jne .Lmi_push
        mov rax, [rsp + MI_FALSE]
        cmp dword ptr [rax + N_AUX], 1
        jne .Lmi_push
        mov rax, [rsp + MI_TRUE]
        mov rdi, [rax + N_DATA]
        PATXD "('setvar', ':v', ':x')"
        test eax, eax
        jz .Lmi_push
        B rax, 0
        mov [rsp + MI_V], rax
        B rax, 1
        mov [rsp + MI_X], rax
        mov rax, [rsp + MI_FALSE]
        mov rdi, [rax + N_DATA]
        PATXD "('setvar', ':v', ':y')"
        test eax, eax
        jz .Lmi_push
        B rdi, 0
        mov rsi, [rsp + MI_V]
        call py_equal
        test eax, eax
        jz .Lmi_push
        B rax, 1
        mov [rsp + MI_Y], rax
3:      mov rdi, [rsp + MI_COND]        # not x is x the other way round
        OPCODE_OF_RDI
        cmp eax, OP_ISZERO
        jne 4f
        mov rax, [rsp + MI_COND]
        cmp dword ptr [rax + N_AUX], 2
        jb .Lmi_index
        mov rax, [rax + N_DATA + 8]
        mov [rsp + MI_COND], rax
        mov rax, [rsp + MI_X]
        mov rcx, [rsp + MI_Y]
        mov [rsp + MI_X], rcx
        mov [rsp + MI_Y], rax
        jmp 3b
4:      mov rcx, [rsp + MI_COND]
        cmp eax, OP_LT
        je 5f
        cmp eax, OP_LE
        je 5f
        cmp eax, OP_GT
        je 6f
        cmp eax, OP_GE
        jne .Lmi_push
6:      cmp dword ptr [rcx + N_AUX], 3  # gt, ge: a, b = b, a
        jne .Lmi_push
        mov rax, [rcx + N_DATA + 16]
        mov rcx, [rcx + N_DATA + 8]
        jmp 7f
5:      cmp dword ptr [rcx + N_AUX], 3
        jne .Lmi_push
        mov rax, [rcx + N_DATA + 8]
        mov rcx, [rcx + N_DATA + 16]
7:      mov [rsp + MI_COND], rax        # a
        mov [rsp + MI_TRUE], rcx        # b
        # v is x where a < b (a <= b), y where it isn't: (x, y) == (a, b)
        mov rdi, [rsp + MI_X]
        mov rsi, rax
        call py_equal
        test eax, eax
        jz .Lmi_push
        mov rdi, [rsp + MI_Y]
        mov rsi, [rsp + MI_TRUE]
        call py_equal
        test eax, eax
        jz .Lmi_push
        LOADS rdi, MIN
        mov rsi, [rsp + MI_COND]
        mov rdx, [rsp + MI_TRUE]
        call mk3
        mov rdx, rax
        LOADS rdi, SETVAR
        mov rsi, [rsp + MI_V]
        call mk3
        mov r14, rax
.Lmi_push:
        mov rdi, r12
        mov rsi, r14
        call vec_push
        jmp .Lmi_line
.Lmi_done:
        mov rdi, r12
        mov rsi, rbx
        call vec_to_list_like
        add rsp, MATCH_BINDINGS_SIZE + 48
        LEAVE
.Lmi_index:
        call cn_index_error
.Lmi_type:
        mov edi, E_TYPE
        lea rsi, [rip + .Ls_cn_type]
        call err_throw
ENDF min_ifs

# precompiled_results(trace, name) -> list: python's precompiled_results -
# `hash = sha256hash(x) # precompiled`: hash is the first word it returns,
# 0 if none - what ext_call.return_data[0] is, until what calls return
# changes. Read as the result it is. (name: the result of the one that
# returned last, before the trace; NIL for None)
FUNC precompiled_results
        STACK_CHECK
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 32
        .set PR_NAME, MATCH_BINDINGS_SIZE
        .set PR_FW, MATCH_BINDINGS_SIZE + 8
        .set PR_COND, MATCH_BINDINGS_SIZE + 16
        .set PR_TRUE, MATCH_BINDINGS_SIZE + 24
        mov rbx, rdi
        mov [rsp + PR_NAME], rsi
        LOADS rdi, EXT_CALL_RETURN_DATA # first_word
        mov esi, 1
        mov edx, (32 << 1) | 1
        call mk3
        mov [rsp + PR_FW], rax
        call vec_new
        mov r12, rax
        xor r13d, r13d
.Lpr_line:
        cmp r13d, [rbx + N_AUX]
        jae .Lpr_done
        mov r14, [rbx + N_DATA + r13*8]
        inc r13d
        mov rdi, r14
        call is_if_line
        test eax, eax
        jz 3f
        mov rax, [r14 + N_DATA + 8]
        mov [rsp + PR_COND], rax
        cmp qword ptr [rsp + PR_NAME], 0
        je 2f
        LOADS rdi, VAR
        mov rsi, [rsp + PR_NAME]
        call mk2
        mov rdx, rax
        mov rdi, [rsp + PR_COND]
        mov rsi, [rsp + PR_FW]
        call replace
        mov [rsp + PR_COND], rax
2:      mov rdi, [r14 + N_DATA + 16]
        mov rsi, [rsp + PR_NAME]
        call precompiled_results
        mov [rsp + PR_TRUE], rax
        mov rdi, [r14 + N_DATA + 24]
        mov rsi, [rsp + PR_NAME]
        call precompiled_results
        mov rdx, rax
        mov rsi, [rsp + PR_TRUE]
        mov rdi, [rsp + PR_COND]
        call mk_if
        mov r14, rax
        jmp .Lpr_changes
3:      mov rdi, r14
        OPCODE_OF_RDI
        cmp eax, OP_WHILE
        jne 4f
        # (what it's in isn't known at its start: it may have been changed)
        cmp dword ptr [r14 + N_AUX], 3
        jb .Lpr_index
        mov rdi, [r14 + N_DATA + 16]
        xor esi, esi
        call precompiled_results
        mov rdi, r14
        mov esi, 2
        mov rdx, rax
        call tuple_with
        mov r14, rax
.Lpr_changes:
        mov rdi, r14
        mov rsi, [rsp + PR_FW]
        call changes_reads
        test eax, eax
        jz .Lpr_precompiled
        mov qword ptr [rsp + PR_NAME], 0
        jmp .Lpr_precompiled
4:      cmp qword ptr [rsp + PR_NAME], 0
        je .Lpr_precompiled
        mov rdi, r14
        mov rsi, [rsp + PR_FW]
        call changes_reads
        test eax, eax
        jz 5f
        mov qword ptr [rsp + PR_NAME], 0
        jmp .Lpr_precompiled
5:      LOADS rdi, VAR
        mov rsi, [rsp + PR_NAME]
        call mk2
        mov rdx, rax
        mov rdi, r14
        mov rsi, [rsp + PR_FW]
        call replace
        mov r14, rax
.Lpr_precompiled:
        # (the data identity returns is the data it's given: read as that)
        mov rdi, r14
        PATXD "('precompiled', ':name', ':func', 'Any')"
        test eax, eax
        jz 6f
        mov qword ptr [rsp + PR_NAME], 0
        B rax, 1
        LOADS rcx, IDENTITY
        cmp rax, rcx
        je 6f
        B rax, 0
        lea rcx, [rip + sp_none]
        cmp rax, rcx
        je 6f
        mov [rsp + PR_NAME], rax
6:      mov rdi, r12
        mov rsi, r14
        call vec_push
        jmp .Lpr_line
.Lpr_done:
        mov rdi, r12
        mov rsi, rbx
        call vec_to_list_like
        add rsp, MATCH_BINDINGS_SIZE + 32
        LEAVE
.Lpr_index:
        call cn_index_error
ENDF precompiled_results

# --- what a line changes ---

# changes_reads(line, exp) -> eax: python's changes_reads - the line may
# change something that exp reads from the state (see
# arithmetic.changed_by): the storage it writes, what a call can change...
# The ifs and the whiles are asked of again and again, for one expression
# after the other (replace_mem: does each if affect what it replaces, then
# each if in it, and so on): what they hold is summarized once
# (line_summary), and one that writes none of the state exp reads isn't
# walked again - the answer is no, as python's walk gives it, and that
# walk has no error on the way (the summary says so; where it would, it's
# the walk, as python's).
FUNC changes_reads
        ENTER
        sub rsp, 16
        mov qword ptr [rsp], -1         # the kinds of state exp reads: not known yet
        mov rdx, rsp
        call cr_walk
        add rsp, 16
        LEAVE
ENDF changes_reads

# cr_walk(line, exp, kinds) -> eax: changes_reads, kinds pointing to what
# state_kinds(exp) is (-1 until it's asked: once for the whole walk)
FUNC cr_walk
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        OPCODE_OF_RDI
        cmp eax, OP_STORE
        je .Lcr_store
        cmp eax, OP_TSTORE
        je .Lcr_tstore
        cmp eax, OP_CALL
        je .Lcr_call
        cmp eax, OP_STATICCALL
        je .Lcr_call
        cmp eax, OP_DELEGATECALL
        je .Lcr_call
        cmp eax, OP_CALLCODE
        je .Lcr_call
        cmp eax, OP_CODECALL
        je .Lcr_call
        cmp eax, OP_CREATE
        je .Lcr_call
        cmp eax, OP_CREATE2
        je .Lcr_call
        cmp eax, OP_PRECOMPILED
        je .Lcr_precompiled
        cmp eax, OP_INTERNAL
        je .Lcr_internal
        cmp eax, OP_IF
        je .Lcr_if
        cmp eax, OP_WHILE
        je .Lcr_while
.Lcr_no:
        xor eax, eax
        LEAVE
.Lcr_store:
        cmp dword ptr [rbx + N_AUX], 4
        jb .Lcr_index
        mov rdx, [rbx + N_DATA + 24]
        mov esi, OP_STORE
        jmp 1f
.Lcr_tstore:
        cmp dword ptr [rbx + N_AUX], 2
        jb .Lcr_index
        mov rdx, [rbx + N_DATA + 8]
        mov esi, OP_TSTORE
        jmp 1f
.Lcr_internal:
        # a recursive internal function (vm.s, vm_internal_call): it may do
        # anything a call does
        mov eax, OP_DELEGATECALL
        jmp .Lcr_call
.Lcr_precompiled:
        # a call too: what calls return is what it returns
        mov eax, OP_STATICCALL
.Lcr_call:
        mov esi, eax
        xor edx, edx
1:      mov rdi, r12
        call changed_any
        LEAVE
.Lcr_if:
        cmp dword ptr [rbx + N_AUX], 4
        jb .Lcr_index
        mov rdi, rbx
        mov rsi, r12
        mov rdx, r13
        call cr_settled
        test eax, eax
        jnz .Lcr_no
        mov rdi, [rbx + N_DATA + 16]
        mov rsi, r12
        mov rdx, r13
        call cr_walk_lines
        test eax, eax
        jnz 2f
        mov rdi, [rbx + N_DATA + 24]
        mov rsi, r12
        mov rdx, r13
        call cr_walk_lines
2:      LEAVE
.Lcr_while:
        cmp dword ptr [rbx + N_AUX], 3
        jb .Lcr_index
        mov rdi, rbx
        mov rsi, r12
        mov rdx, r13
        call cr_settled
        test eax, eax
        jnz .Lcr_no
        mov rdi, [rbx + N_DATA + 16]
        mov rsi, r12
        mov rdx, r13
        call cr_walk_lines
        LEAVE
.Lcr_index:
        call cn_index_error
ENDF cr_walk

# cr_walk_lines(lines, exp, kinds) -> eax: cr_walk of one of the lines
FUNC cr_walk_lines
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        IS_SEQ_RDI
        test eax, eax
        jz 9f
        xor r14d, r14d
1:      cmp r14d, [rbx + N_AUX]
        jae 2f
        mov rdi, [rbx + N_DATA + r14*8]
        inc r14d
        mov rsi, r12
        mov rdx, r13
        call cr_walk
        test eax, eax
        jz 1b
        LEAVE
2:      xor eax, eax
        LEAVE
9:      mov edi, E_TYPE
        lea rsi, [rip + .Ls_cn_type]
        call err_throw
ENDF cr_walk_lines

# cr_settled(line, exp, kinds) -> eax: 1 when the line (an if, a while)
# writes none of the kinds of state exp reads, and the walk of it has no
# error (its summary: then cr_walk's answer is 0, without the walk); 0
# when it's for the walk to say. The kinds are worked out here, the
# first time they're needed.
FUNC cr_settled
        ENTER
        mov r12, rsi
        mov r13, rdx
        call line_summary
        test eax, LS_OK
        jz 8f
        test eax, LS_WRITERS
        jz 9f                           # (no writer: whatever exp reads)
        mov ebx, eax
        mov eax, [r13]
        test eax, eax
        jns 1f
        mov rdi, r12
        call state_kinds
        mov [r13], eax
1:      test eax, eax
        jz 9f                           # (exp reads none of the state)
        test ebx, LS_CALL
        jnz 8f
        test eax, ebx
        jnz 8f
9:      mov eax, 1
        LEAVE
8:      xor eax, eax
        LEAVE
ENDF cr_settled

# line_summary(line) -> eax: what cr_walk finds in the line, LS_ bits: the
# writers in it, and LS_OK if it walks the whole of it without an error
# of its own (a line too short for what's read of it, branches that
# aren't sequences). An if's and a while's memoized (MEMO_LINE_SUMMARY):
# they're asked of again and again.
FUNC line_summary
        STACK_CHECK
        OPCODE_OF_RDI
        cmp eax, OP_STORE
        je 3f
        cmp eax, OP_TSTORE
        je 4f
        cmp eax, OP_IF
        je 5f
        cmp eax, OP_WHILE
        je 5f
        cmp eax, OP_STATICCALL
        je 2f
        cmp eax, OP_PRECOMPILED
        je 2f
        cmp eax, OP_CALL
        je 1f
        cmp eax, OP_DELEGATECALL
        je 1f
        cmp eax, OP_CALLCODE
        je 1f
        cmp eax, OP_CODECALL
        je 1f
        cmp eax, OP_CREATE
        je 1f
        cmp eax, OP_CREATE2
        je 1f
        cmp eax, OP_INTERNAL
        je 1f
        mov eax, LS_OK
        ret
1:      mov eax, LS_OK | LS_CALL
        ret
2:      mov eax, LS_OK | LS_STATIC
        ret
3:      xor eax, eax                    # (too short: cr_walk's IndexError)
        cmp dword ptr [rdi + N_AUX], 4
        jb 9f
        mov eax, LS_OK | LS_STORE
9:      ret
4:      xor eax, eax
        cmp dword ptr [rdi + N_AUX], 2
        jb 9b
        mov eax, LS_OK | LS_TSTORE
        ret
5:      ENTER
        mov rbx, rdi
        mov r12d, eax
        mov edi, MEMO_LINE_SUMMARY
        mov rsi, rbx
        call memo_get
        test rax, rax
        jz 1f
        shr eax, 1                      # (tagged)
        LEAVE
1:      xor r13d, r13d                  # (too short: cr_walk's IndexError)
        cmp r12d, OP_IF
        jne 2f
        cmp dword ptr [rbx + N_AUX], 4
        jb 6f
        mov rdi, [rbx + N_DATA + 16]
        call lines_summary
        mov r13d, eax
        mov rdi, [rbx + N_DATA + 24]
        call lines_summary
        mov ecx, eax
        and eax, r13d                   # LS_OK if in both
        or ecx, r13d                    # the writers of either
        and eax, LS_OK
        and ecx, LS_WRITERS
        or eax, ecx
        mov r13d, eax
        jmp 6f
2:      cmp dword ptr [rbx + N_AUX], 3
        jb 6f
        mov rdi, [rbx + N_DATA + 16]
        call lines_summary
        mov r13d, eax
6:      mov edi, MEMO_LINE_SUMMARY
        mov rsi, rbx
        lea rdx, [r13*2 + 1]
        call memo_put
        mov eax, r13d
        LEAVE
ENDF line_summary

# lines_summary(lines) -> eax: line_summary of a branch, a body - LS_OK if
# it's a sequence and in every line of it
FUNC lines_summary
        STACK_CHECK
        ENTER
        mov rbx, rdi
        IS_SEQ_RDI
        test eax, eax
        jz 9f
        mov r12d, LS_OK
        xor r13d, r13d
1:      cmp r13d, [rbx + N_AUX]
        jae 8f
        mov rdi, [rbx + N_DATA + r13*8]
        inc r13d
        call line_summary
        mov ecx, eax
        and eax, LS_WRITERS
        or ecx, ~LS_OK
        or r12d, eax                    # the writers of any
        and r12d, ecx                   # LS_OK if in each
        jmp 1b
8:      mov eax, r12d
9:      LEAVE
ENDF lines_summary

# changed_any(exp, op, target) -> eax: python's bool(changed_reads(exp, op,
# target)) - a read of the state in exp that op may change. A tuple
# without a volatile string (HF_VOLATILE) reads none of the state, in it or
# in its parts (state_kinds): not walked.
FUNC changed_any
        STACK_CHECK
        test dil, 1
        jnz 8f                          # (a number reads nothing)
        test rdi, rdi
        jz 0f
        cmp dword ptr [rdi + N_KIND], K_TUPLE
        jne 0f
        movabs rax, HF_VOLATILE
        test [rdi + N_HASH], rax
        jz 8f
0:      ENTER
        mov rbx, rdi
        mov r12d, esi
        mov r13, rdx
        call changed_by
        test eax, eax
        jnz 9f
        mov rdi, rbx
        call is_tuple
        test eax, eax
        jz 7f
        xor r14d, r14d
1:      cmp r14d, [rbx + N_AUX]
        jae 7f
        mov rdi, [rbx + N_DATA + r14*8]
        inc r14d
        mov esi, r12d
        mov rdx, r13
        call changed_any
        test eax, eax
        jz 1b
9:      mov eax, 1
        LEAVE
7:      xor eax, eax
        LEAVE
8:      xor eax, eax
        ret
ENDF changed_any

# changes_value(line, exp) -> eax: python's changes_value - the line
# changes what exp reads: of the state, or of memory it writes over for
# sure (where the parts of it may overlap is how memory is, a copy's
# source and destination: taken as apart, as elsewhere)
FUNC changes_value
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call changes_reads
        test eax, eax
        jnz 9f
        mov rdi, rbx
        OPCODE_OF_RDI
        cmp eax, OP_SETMEM
        je 1f
        cmp eax, OP_IF
        je 3f
        cmp eax, OP_WHILE
        je 5f
        xor eax, eax
        LEAVE
1:      cmp dword ptr [rbx + N_AUX], 2
        jb .Lcv_index
        mov rdi, r12
        call find_mems
        mov r13, rax
        xor r14d, r14d
2:      cmp r14d, [r13 + N_AUX]
        jae 8f
        mov rax, [r13 + N_DATA + r14*8]
        inc r14d
        mov rsi, [rax + N_DATA + 8]
        mov rdi, [rbx + N_DATA + 8]
        call range_overlaps
        cmp eax, TRI_TRUE
        jne 2b
        jmp 9f
3:      cmp dword ptr [rbx + N_AUX], 4
        jb .Lcv_index
        mov rdi, [rbx + N_DATA + 16]
        mov rsi, r12
        call any_changes_value
        test eax, eax
        jnz 9f
        mov rdi, [rbx + N_DATA + 24]
        mov rsi, r12
        call any_changes_value
        LEAVE
5:      cmp dword ptr [rbx + N_AUX], 3
        jb .Lcv_index
        mov rdi, [rbx + N_DATA + 16]
        mov rsi, r12
        call any_changes_value
        LEAVE
8:      xor eax, eax
        LEAVE
9:      mov eax, 1
        LEAVE
.Lcv_index:
        call cn_index_error
ENDF changes_value

# any_changes_value(lines, exp) -> eax
FUNC any_changes_value
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        IS_SEQ_RDI
        test eax, eax
        jz 9f
        xor r13d, r13d
1:      cmp r13d, [rbx + N_AUX]
        jae 2f
        mov rdi, [rbx + N_DATA + r13*8]
        inc r13d
        mov rsi, r12
        call changes_value
        test eax, eax
        jz 1b
        LEAVE
2:      xor eax, eax
        LEAVE
9:      mov edi, E_TYPE
        lea rsi, [rip + .Ls_cn_type]
        call err_throw
ENDF any_changes_value

        .section .note.GNU-stack,"",@progbits
