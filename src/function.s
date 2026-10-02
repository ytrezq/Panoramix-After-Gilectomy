# A decompiled function (port of function.py's Function): its name from
# the abi, the types of its parameters, whether it is payable, read-only,
# a constant or a getter, and its text.
#
# The struct is FN_* (defs.inc). The abi entry is (name, inputs), inputs
# being a list of (type, name) or NIL.

.include "defs.inc"

        .section .rodata
.Ls_logname:    .asciz "panoramix.function"
.Ls_unaligned:  .asciz "unusual cd (not aligned)"
.Ls_unusual_ref: .asciz "unusual calldata reference %v"
.Ls_unknown:    .asciz "unknown"
.Ls_lparen_q:   .asciz "(?)"
.Ls_comma_sp:   .asciz ", "
.Ls_comma:      .asciz ","
.Ls_param_:     .asciz "_param"
.Ls_tuple:      .asciz "tuple"
.Ls_array:      .asciz "array"
.Ls_bool:       .asciz "bool"
.Ls_callvalue:  .asciz "callvalue"
.Ls_q_store:    .asciz "'store'"
.Ls_q_selfdestruct: .asciz "'selfdestruct'"
.Ls_q_call:     .asciz "'call'"
.Ls_q_delegatecall: .asciz "'delegatecall'"
.Ls_q_codecall: .asciz "'codecall'"
.Ls_q_create:   .asciz "'create'"
.Ls_storage:    .asciz "storage"
.Ls_calldata:   .asciz "calldata"
.Ls_calldataload: .asciz "calldataload"
.Ls_store:      .asciz "store"
.Ls_cd:         .asciz "cd"
.Ls_selfdestruct: .asciz "selfdestruct"
.Ls_const_:     .asciz "const "
.Ls_eq_sp:      .asciz " = "
.Ls_def_:       .asciz "def "
.Ls_payable:    .asciz " payable"
.Ls_colon_sp:   .asciz ": "
.Ls_not_payable: .asciz "# not payable"
.Ls_default:    .asciz "# default function"
.Ls_not_payable_default: .asciz "# not payable, default function"
.Ls_fallback_q: .asciz "_fallback(?)"
.Ls_stop_line:  .asciz "  stop"
.Ls_empty_paren: .asciz "()"
.Ls_newline:    .asciz "\n"
.Ls_assert_trace: .asciz "function: an empty trace"
.Ls_assert_payable: .asciz "function: payable undecided"

        .section .data.rel.ro
        .align 8
        # the opcodes that make a function not read-only, quoted as in
        # python's str(trace)
not_read_only:
        .quad .Ls_q_store, .Ls_q_selfdestruct, .Ls_q_call, .Ls_q_delegatecall, .Ls_q_codecall, .Ls_q_create, 0
        # what a constant function's trace doesn't mention
not_const:
        .quad .Ls_storage, .Ls_calldata, .Ls_calldataload, .Ls_store, .Ls_cd, 0

        .text

.macro B reg, n
        mov \reg, [rsp + 8*(\n)]
.endm

# (the names, signatures.get_func_name and get_abi_name: abi_func_name and
# abi_name in sigs.s)

# --- the parameters ---

# params_get(fn, idx) -> rax: the (idx, kind, name) of a parameter, or 0
FUNC params_get
        mov rax, [rdi + FN_PARAMS]
        xor ecx, ecx
1:      cmp ecx, [rax + N_AUX]
        jae 2f
        mov rdx, [rax + N_DATA + rcx*8]
        cmp [rdx + N_DATA], rsi
        je 3f
        inc ecx
        jmp 1b
2:      xor eax, eax
        ret
3:      mov rax, rdx
        ret
ENDF params_get

# make_params(fn) -> list of (idx, kind, name): the parameters from the
# abi, or guessed from how the calldata is used
FUNC make_params
        ENTER
        sub rsp, 64
        .set MP_SIZES, 0                # list of (idx, size) pairs, in order (a vec)
        .set MP_OUT, 8
        .set MP_I, 16
        .set MP_COUNT, 24
        .set MP_IDX, 32
        .set MP_SIZE, 40
        mov rbx, rdi
        mov rax, [rbx + FN_ABI]
        mov r12, [rax + N_DATA + 8]     # inputs
        test r12, r12
        jz .Lmp_guess
        cmp dword ptr [r12 + N_AUX], 0
        je .Lmp_guess
        # {4 + 32 i: (type, name)}
        call vec_new
        mov r13, rax
        xor r14d, r14d
1:      cmp r14d, [r12 + N_AUX]
        jae 2f
        mov rax, [r12 + N_DATA + r14*8]
        mov rsi, [rax + N_DATA]
        mov rdx, [rax + N_DATA + 8]
        lea rdi, [r14*4]
        lea rdi, [rdi*8 + 4]            # 4 + 32 i
        TAG rdi
        call mk3
        mov rdi, r13
        mov rsi, rax
        call vec_push
        inc r14d
        jmp 1b
2:      mov rdi, r13
        call vec_to_list
        add rsp, 64
        LEAVE
.Lmp_guess:
        # the calldata references: ('mask_shl', _, _, _, ('cd', _)) and ('cd', _)
        call vec_new
        mov r13, rax
        mov rdi, [rbx + FN_TRACE]
        lea rsi, [rip + pred_cd_ref]
        mov rdx, r13
        call walk_collect
        call vec_new
        mov [rsp + MP_SIZES], rax
        xor r14d, r14d
.Lmp_occ:
        cmp r14, [r13 + VEC_LEN]
        jae .Lmp_check
        mov rax, [r13 + VEC_DATA]
        mov r12, [rax + r14*8]
        inc r14
        mov rdi, r12
        call opcode_of
        cmp eax, OP_MASK_SHL
        jne 3f
        mov rax, [r12 + N_DATA + 8]
        mov [rsp + MP_SIZE], rax        # size
        mov rax, [r12 + N_DATA + 32]
        mov rax, [rax + N_DATA + 8]
        mov [rsp + MP_IDX], rax         # idx
        jmp 4f
3:      mov rax, [r12 + N_DATA + 8]
        mov [rsp + MP_IDX], rax
        mov qword ptr [rsp + MP_SIZE], 513      # 256
4:      cmp qword ptr [rsp + MP_IDX], 1         # idx == 0: the selector
        je .Lmp_occ
        # ('add', 4, ('cd', in_idx)): a pointer, size -1
        mov rdi, [rsp + MP_IDX]
        call .Lmp_pointer_of
        test rax, rax
        jz 5f
        mov rdi, [rsp + MP_SIZES]
        mov rsi, rax
        mov rdx, -1
        TAG rdx
        call .Lmp_sizes_set
        jmp .Lmp_occ
5:      # a new index gets its size (python never lowers it: `==`, but
        # it compares them: TypeError for an expression and an int)
        mov rdi, [rsp + MP_SIZES]
        mov rsi, [rsp + MP_IDX]
        call .Lmp_sizes_find
        test rax, rax
        jz 51f
        mov rdi, [rsp + MP_SIZE]
        mov rsi, [rax + N_DATA + 8]
        xor edx, edx
        call py_lt                      # size < sizes[idx]
        jmp .Lmp_occ
51:
        mov rdi, [rsp + MP_SIZES]
        mov rsi, [rsp + MP_IDX]
        mov rdx, [rsp + MP_SIZE]
        call .Lmp_sizes_set
        jmp .Lmp_occ
.Lmp_check:
        # every index is an int, 4 modulo 32
        mov r13, [rsp + MP_SIZES]
        xor r14d, r14d
6:      cmp r14, [r13 + VEC_LEN]
        jae 7f
        mov rax, [r13 + VEC_DATA]
        mov rdi, [rax + r14*8]
        mov rdi, [rdi + N_DATA]
        mov [rsp + MP_IDX], rdi
        call is_int
        test eax, eax
        jz .Lmp_unaligned
        mov rdi, [rsp + MP_IDX]
        mov rsi, 4
        TAG rsi
        call int_sub
        mov rdi, rax
        mov rsi, 32
        TAG rsi
        call int_mod
        cmp rax, 1
        jne .Lmp_unaligned
        inc r14
        jmp 6b
7:      # a bool: only used under bool, if, iszero
        xor r14d, r14d
8:      cmp r14, [r13 + VEC_LEN]
        jae 9f
        mov rax, [r13 + VEC_DATA]
        mov rax, [rax + r14*8]
        mov rdi, [rax + N_DATA]
        call .Lmp_is_bool
        test eax, eax
        jz 81f
        mov rax, [r13 + VEC_DATA]
        mov rax, [rax + r14*8]
        mov qword ptr [rax + N_DATA + 8], 3     # size 1
81:     inc r14
        jmp 8b
9:      # sorted by index: (kind, _param<n>)
        mov rdi, r13
        call .Lmp_sort
        call vec_new
        mov [rsp + MP_OUT], rax
        mov qword ptr [rsp + MP_COUNT], 1
        xor r14d, r14d
10:     cmp r14, [r13 + VEC_LEN]
        jae 12f
        mov rax, [r13 + VEC_DATA]
        mov r12, [rax + r14*8]          # (idx, size)
        mov rdi, [r12 + N_DATA + 8]
        cmp rdi, -3                     # tagged -2
        jne 101f
        lea rdi, [rip + .Ls_tuple]
        call str_intern_c
        jmp 104f
101:    cmp rdi, -1                     # tagged -1
        jne 102f
        lea rdi, [rip + .Ls_array]
        call str_intern_c
        jmp 104f
102:    cmp rdi, 3                      # 1
        jne 103f
        lea rdi, [rip + .Ls_bool]
        call str_intern_c
        jmp 104f
103:    mov esi, 1
        call mask_to_type
104:    mov [rsp + MP_SIZE], rax        # the kind
        call sb_new
        mov rdi, rax
        push rax
        push rax
        lea rsi, [rip + .Ls_param_]
        call sb_append_c
        mov rdi, [rsp]
        mov rsi, [rsp + 16 + MP_COUNT]
        call sb_append_u64
        pop rdi
        pop rdi
        call sb_finish_intern
        mov rdx, rax
        mov rdi, [r12 + N_DATA]
        mov rsi, [rsp + MP_SIZE]
        call mk3
        mov rdi, [rsp + MP_OUT]
        mov rsi, rax
        call vec_push
        inc qword ptr [rsp + MP_COUNT]
        inc r14
        jmp 10b
12:     mov rdi, [rsp + MP_OUT]
        call vec_to_list
        add rsp, 64
        LEAVE
.Lmp_unaligned:
        mov edi, LOG_WARNING
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_unaligned]
        call log_fmt
        xor edi, edi
        xor esi, esi
        call mk_list
        add rsp, 64
        LEAVE

# locals of make_params
# ('add', 4, ('cd', in_idx)) -> in_idx, else 0
.Lmp_pointer_of:
        sub rsp, 8
        mov [rsp], rdi
        call opcode_of
        cmp eax, OP_ADD
        jne 1f
        mov rdi, [rsp]
        cmp dword ptr [rdi + N_AUX], 3
        jne 1f
        cmp qword ptr [rdi + N_DATA + 8], 9     # 4
        jne 1f
        mov rdi, [rdi + N_DATA + 16]
        call opcode_of
        cmp eax, OP_CD
        jne 1f
        mov rdi, [rsp]
        mov rdi, [rdi + N_DATA + 16]
        cmp dword ptr [rdi + N_AUX], 2
        jne 1f
        mov rax, [rdi + N_DATA + 8]
        add rsp, 8
        ret
1:      xor eax, eax
        add rsp, 8
        ret
# the (idx, size) node of a vec of pairs for idx (values compared like
# python), or 0
.Lmp_sizes_find:
        sub rsp, 24
        mov [rsp], rdi
        mov [rsp + 8], rsi
        mov qword ptr [rsp + 16], 0
1:      mov rdi, [rsp]
        mov rcx, [rsp + 16]
        cmp rcx, [rdi + VEC_LEN]
        jae 2f
        mov rax, [rdi + VEC_DATA]
        mov rdi, [rax + rcx*8]
        mov rdi, [rdi + N_DATA]
        mov rsi, [rsp + 8]
        call py_equal
        test eax, eax
        jnz 3f
        inc qword ptr [rsp + 16]
        jmp 1b
3:      mov rdi, [rsp]
        mov rcx, [rsp + 16]
        mov rax, [rdi + VEC_DATA]
        mov rax, [rax + rcx*8]
        add rsp, 24
        ret
2:      xor eax, eax
        add rsp, 24
        ret
# sizes[idx] = size: the pair replaced in place, or appended (the pairs
# are 2-element arena tuples of our own - mutable, not hash-consed)
.Lmp_sizes_set:
        sub rsp, 24
        mov [rsp], rdi
        mov [rsp + 8], rsi
        mov [rsp + 16], rdx
        call .Lmp_sizes_find
        test rax, rax
        jz 1f
        mov rdx, [rsp + 16]
        mov [rax + N_DATA + 8], rdx
        add rsp, 24
        ret
1:      mov edi, N_DATA + 16
        call arena_alloc
        mov dword ptr [rax + N_KIND], K_TUPLE
        mov dword ptr [rax + N_AUX], 2
        mov rcx, [rsp + 8]
        mov [rax + N_DATA], rcx
        mov rcx, [rsp + 16]
        mov [rax + N_DATA + 8], rcx
        mov rdi, [rsp]
        mov rsi, rax
        call vec_push
        add rsp, 24
        ret
# eax: every parent of ('cd', idx) in the trace is a bool, an if or an iszero
.Lmp_is_bool:
        sub rsp, 24
        mov rsi, rdi
        LOADS rdi, CD
        call mk2
        mov [rsp], rax
        call vec_new
        mov [rsp + 8], rax
        mov rdi, [rbx + FN_TRACE]
        mov rsi, [rsp]
        mov rdx, rax
        call find_parents
        mov qword ptr [rsp + 16], 0
1:      mov rax, [rsp + 8]
        mov rcx, [rsp + 16]
        cmp rcx, [rax + VEC_LEN]
        jae 2f
        mov rax, [rax + VEC_DATA]
        mov rdi, [rax + rcx*8]
        call opcode_of
        cmp eax, OP_BOOL
        je 3f
        cmp eax, OP_IF
        je 3f
        cmp eax, OP_ISZERO
        je 3f
        xor eax, eax
        add rsp, 24
        ret
3:      inc qword ptr [rsp + 16]
        jmp 1b
2:      mov eax, 1
        add rsp, 24
        ret
# the (idx, size) pairs sorted by idx (insertion sort; the indexes are ints)
.Lmp_sort:
        sub rsp, 24
        mov [rsp], rdi
        mov qword ptr [rsp + 8], 1
1:      mov rdi, [rsp]
        mov rcx, [rsp + 8]
        cmp rcx, [rdi + VEC_LEN]
        jae 5f
        mov [rsp + 16], rcx
2:      mov rcx, [rsp + 16]
        test rcx, rcx
        jz 4f
        mov rdi, [rsp]
        mov rax, [rdi + VEC_DATA]
        mov rdi, [rax + rcx*8 - 8]
        mov rdi, [rdi + N_DATA]
        mov rsi, [rax + rcx*8]
        mov rsi, [rsi + N_DATA]
        call int_cmp
        cmp eax, 1
        jne 4f
        mov rdi, [rsp]
        mov rcx, [rsp + 16]
        mov rax, [rdi + VEC_DATA]
        mov rdi, [rax + rcx*8 - 8]
        xchg rdi, [rax + rcx*8]
        mov [rax + rcx*8 - 8], rdi
        dec qword ptr [rsp + 16]
        jmp 2b
4:      inc qword ptr [rsp + 8]
        jmp 1b
5:      add rsp, 24
        ret
ENDF make_params

# pred_cd_ref(exp) -> eax: ('mask_shl', _, _, _, ('cd', _)) or ('cd', _)
FUNC pred_cd_ref
        ENTER
        mov rbx, rdi
        call opcode_of
        cmp eax, OP_CD
        jne 1f
        cmp dword ptr [rbx + N_AUX], 2
        sete al
        movzx eax, al
        LEAVE
1:      cmp eax, OP_MASK_SHL
        jne 2f
        cmp dword ptr [rbx + N_AUX], 5
        jne 2f
        mov rdi, [rbx + N_DATA + 32]
        call opcode_of
        cmp eax, OP_CD
        jne 2f
        mov rdi, [rbx + N_DATA + 32]
        cmp dword ptr [rdi + N_AUX], 2
        sete al
        movzx eax, al
        LEAVE
2:      xor eax, eax
        LEAVE
ENDF pred_cd_ref

# find_parents(exp, child, out): the tuples and lists that contain child
# directly, depth first, once per occurrence
FUNC find_parents
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        call is_seq
        test eax, eax
        jz 3f
        xor r14d, r14d
1:      cmp r14d, [rbx + N_AUX]
        jae 3f
        mov rdi, [rbx + N_DATA + r14*8]
        mov rsi, r12
        call py_equal
        test eax, eax
        jz 2f
        mov rdi, r13
        mov rsi, rbx
        call vec_push
2:      mov rdi, [rbx + N_DATA + r14*8]
        mov rsi, r12
        mov rdx, r13
        call find_parents
        inc r14d
        jmp 1b
3:      LEAVE
ENDF find_parents

# make_names(fn): the names from the inferred parameters, for an unknown
# function
FUNC make_names
        ENTER
        sub rsp, 16
        mov rbx, rdi
        # new_name = name.split("(")[0]
        mov rax, [rbx + FN_NAME]
        lea rdi, [rax + N_DATA + 4]
        mov esi, '('
        call strchr@PLT
        mov rdx, [rbx + FN_NAME]
        lea rdi, [rdx + N_DATA + 4]
        test rax, rax
        jz 1f
        mov rsi, rax
        sub rsi, rdi
        jmp 2f
1:      mov esi, [rdx + N_DATA]
2:      call str_new
        mov r12, rax                    # new_name
        # name: "new_name(kind name, ...)", color_name with green names,
        # abi_name: "new_name(kind,kind)"
        mov rdi, r12
        xor esi, esi
        call .Lmn_with_params
        mov [rbx + FN_NAME], rax
        mov rdi, r12
        mov esi, PF_COLOR
        call .Lmn_with_params
        mov [rbx + FN_COLOR_NAME], rax
        mov rdi, r12
        mov esi, 2                      # (the abi form)
        call .Lmn_with_params
        mov [rbx + FN_ABI_NAME], rax
        add rsp, 16
        LEAVE
# rdi = new_name, esi = flags (2: kinds only, joined by ",")
.Lmn_with_params:
        sub rsp, 40
        mov [rsp], rdi
        mov [rsp + 8], rsi
        call sb_new
        mov [rsp + 16], rax
        mov rdi, rax
        mov rsi, [rsp]
        call sb_append_str
        mov rdi, [rsp + 16]
        mov esi, '('
        call sb_append_char
        mov qword ptr [rsp + 24], 0
1:      mov rax, [rbx + FN_PARAMS]
        mov rcx, [rsp + 24]
        cmp ecx, [rax + N_AUX]
        jae 3f
        test ecx, ecx
        jz 2f
        lea rsi, [rip + .Ls_comma_sp]
        cmp qword ptr [rsp + 8], 2
        jne 11f
        lea rsi, [rip + .Ls_comma]
11:     mov rdi, [rsp + 16]
        call sb_append_c
2:      mov rax, [rbx + FN_PARAMS]
        mov rcx, [rsp + 24]
        mov rax, [rax + N_DATA + rcx*8] # (idx, kind, name)
        mov [rsp + 32], rax
        mov rdi, [rax + N_DATA + 8]
        call is_str
        test eax, eax
        jz .Lmn_not_str                 # (the size of an expression: python's kind + " ")
        mov rax, [rsp + 32]
        mov rdi, [rsp + 16]
        mov rsi, [rax + N_DATA + 8]
        call sb_append_str
        cmp qword ptr [rsp + 8], 2
        je 21f
        mov rdi, [rsp + 16]
        mov esi, ' '
        call sb_append_char
        mov rax, [rsp + 32]
        mov rdi, [rsp + 16]
        mov rsi, [rax + N_DATA + 16]
        lea rdx, [rip + C_GREEN]
        mov rcx, [rsp + 8]
        call sb_append_col
21:     inc qword ptr [rsp + 24]
        jmp 1b
3:      mov rdi, [rsp + 16]
        mov esi, ')'
        call sb_append_char
        mov rdi, [rsp + 16]
        call sb_finish
        add rsp, 40
        ret
.Lmn_not_str:
        mov rdi, [rsp + 16]
        call sb_free
        mov edi, E_TYPE
        lea rsi, [rip + .Ls_concat]
        call err_throw
ENDF make_names

        .section .rodata
.Ls_concat: .asciz "can only concatenate tuple (not \"str\") to tuple"
        .text

# cleanup_masks(fn, trace) -> list: the masks on the parameters whose
# type already says so are removed
FUNC cleanup_masks
        mov rdx, rdi
        mov rdi, rsi
        lea rsi, [rip + rem_masks]
        jmp replace_f
ENDF cleanup_masks

# rem_masks(exp, fn)
FUNC rem_masks
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 16
        mov rbx, rdi
        mov r12, rsi
        mov rdi, rbx
        PATXD "('bool', ('cd', ':int:idx'))"
        test eax, eax
        jz 1f
        mov rdi, r12
        B rsi, 0
        call params_get
        test rax, rax
        jz .Lrm_asis
        mov rdi, [rax + N_DATA + 8]
        lea rsi, [rip + .Ls_bool]
        call str_eq_c
        test eax, eax
        jz .Lrm_asis
        jmp .Lrm_cd
1:      mov rdi, rbx
        PATXD "('mask_shl', ':size', 0, 0, ('cd', ':int:idx'))"
        test eax, eax
        jz .Lrm_asis
        mov rdi, r12
        B rsi, 1
        call params_get
        test rax, rax
        jz .Lrm_asis
        mov rdi, [rax + N_DATA + 8]
        call type_to_mask
        test rax, rax
        jz .Lrm_asis
        mov rdi, rax
        B rsi, 0
        call py_equal
        test eax, eax
        jz .Lrm_asis
        mov rax, [rsp + 8]
        mov [rsp], rax
.Lrm_cd:
        B rsi, 0
        LOADS rdi, CD
        call mk2
        add rsp, MATCH_BINDINGS_SIZE + 16
        LEAVE
.Lrm_asis:
        mov rax, rbx
        add rsp, MATCH_BINDINGS_SIZE + 16
        LEAVE
ENDF rem_masks

# --- the analysis ---

# trace_text(trace) -> sb: python's str(trace), for the searches below,
# in a builder (sb_free it): its text isn't made a string node - one
# would hash and scan all of it, which took more than printing it
FUNC trace_text
        ENTER
        mov rbx, rdi
        call sb_new
        mov r12, rax
        mov rdi, rax
        mov rsi, rbx
        call value_print
        mov rax, r12
        LEAVE
ENDF trace_text

# text_mentions_any(sb, table) -> eax: one of the C strings of the table
# (0-terminated) occurs in the builder's text (no NUL in it: value_print
# escapes them)
FUNC text_mentions_any
        ENTER
        mov rbx, [rdi + SB_BUF]
        mov r12, rsi
1:      mov rsi, [r12]
        test rsi, rsi
        jz 2f
        mov rdi, rbx
        call strstr@PLT
        test rax, rax
        jnz 3f
        add r12, 8
        jmp 1b
2:      xor eax, eax
        LEAVE
3:      mov eax, 1
        LEAVE
ENDF text_mentions_any

# pred_return(exp) -> eax
FUNC pred_return
        ENTER
        call opcode_of
        cmp eax, OP_RETURN
        sete al
        movzx eax, al
        LEAVE
ENDF pred_return

# is_revert_or_invalid(line) -> eax: ('revert', 0) or an invalid
FUNC is_revert_or_invalid
        ENTER
        mov rbx, rdi
        PAT rsi, "('revert', 0)"
        call pat_match_nobind
        test eax, eax
        jnz 1f
        mov rdi, rbx
        call opcode_of
        cmp eax, OP_INVALID
        sete al
        movzx eax, al
1:      LEAVE
ENDF is_revert_or_invalid

# fn_analyse(fn): returns, payable, read_only, const, getter
FUNC fn_analyse
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 48
        .set FA_TEXT, MATCH_BINDINGS_SIZE
        .set FA_T1, MATCH_BINDINGS_SIZE + 8
        .set FA_T2, MATCH_BINDINGS_SIZE + 16
        .set FA_T3, MATCH_BINDINGS_SIZE + 24
        mov rbx, rdi
        mov rax, [rbx + FN_TRACE]
        cmp dword ptr [rax + N_AUX], 0
        je .Lfa_assert_trace
        # the returns
        call vec_new
        mov r12, rax
        mov rdi, [rbx + FN_TRACE]
        lea rsi, [rip + pred_return]
        mov rdx, r12
        call walk_collect
        mov rdi, r12
        call vec_to_list
        mov [rbx + FN_RETURNS], rax
        # payable, unless the function starts by refusing a value
        mov rax, [rbx + FN_TRACE]
        mov r12, [rax + N_DATA]         # first
        mov rdi, r12
        call opcode_of
        cmp eax, OP_IF
        jne .Lfa_payable
        cmp dword ptr [r12 + N_AUX], 4
        jne .Lfa_payable
        mov rdi, [r12 + N_DATA + 8]
        call simplify_bool
        mov r13, rax
        LOADS rdi, CALLVALUE
        cmp rax, rdi
        jne 1f
        mov rdi, [r12 + N_DATA + 16]
        call .Lfa_first_line
        mov rdi, rax
        call is_revert_or_invalid
        test eax, eax
        jz .Lfa_payable
        mov rax, [r12 + N_DATA + 24]
        mov [rbx + FN_TRACE], rax
        mov qword ptr [rbx + FN_PAYABLE], 0
        jmp .Lfa_read_only
1:      PAT rsi, "('iszero', 'callvalue')"
        mov rdi, r13
        call pat_match_nobind
        test eax, eax
        jz .Lfa_payable
        mov rdi, [r12 + N_DATA + 24]
        call .Lfa_first_line
        mov rdi, rax
        call is_revert_or_invalid
        test eax, eax
        jz .Lfa_payable
        mov rax, [r12 + N_DATA + 16]
        mov [rbx + FN_TRACE], rax
        mov qword ptr [rbx + FN_PAYABLE], 0
        jmp .Lfa_read_only
.Lfa_payable:
        mov qword ptr [rbx + FN_PAYABLE], 1
.Lfa_read_only:
        # read-only: no store, call, create... in str(trace)
        mov rdi, [rbx + FN_TRACE]
        call trace_text
        mov [rsp + FA_TEXT], rax
        mov rdi, rax
        lea rsi, [rip + not_read_only]
        call text_mentions_any
        xor eax, 1
        mov [rbx + FN_READ_ONLY], rax
        # a constant: read-only, one return, no storage nor calldata
        mov qword ptr [rbx + FN_CONST], 0
        test rax, rax
        jz .Lfa_getter
        mov rax, [rbx + FN_RETURNS]
        cmp dword ptr [rax + N_AUX], 1
        jne .Lfa_getter
        mov rdi, [rsp + FA_TEXT]
        lea rsi, [rip + not_const]
        call text_mentions_any
        test eax, eax
        jnz .Lfa_getter
        mov rax, [rbx + FN_RETURNS]
        mov r12, [rax + N_DATA]
        # (a 3-element return's data / mask_shl / int - legacy shapes)
        cmp dword ptr [r12 + N_AUX], 3
        jne 2f
        mov rdi, [r12 + N_DATA + 16]
        call opcode_of
        cmp eax, OP_DATA
        je 21f
        cmp eax, OP_MASK_SHL
        je 21f
        mov rdi, [r12 + N_DATA + 16]
        call is_int
        test eax, eax
        jz 2f
21:     mov r12, [r12 + N_DATA + 16]
2:      mov [rbx + FN_CONST], r12
.Lfa_getter:
        mov rdi, [rsp + FA_TEXT]        # (str(trace) done with)
        call sb_free
        mov qword ptr [rbx + FN_GETTER], 0
        mov rdi, rbx
        call simplify_string_getter
        cmp qword ptr [rbx + FN_CONST], 0
        jne .Lfa_done
        cmp qword ptr [rbx + FN_READ_ONLY], 0
        je .Lfa_done
        mov rax, [rbx + FN_RETURNS]
        cmp dword ptr [rax + N_AUX], 1
        jne .Lfa_done
        mov rax, [rax + N_DATA]
        cmp dword ptr [rax + N_AUX], 2
        jb .Lfa_index
        mov r12, [rax + N_DATA + 8]     # ret
        PAT rsi, "('bool', ('storage', 'Any', 'Any', ':loc'))"
        mov rdi, r12
        call pat_match_nobind
        test eax, eax
        jz 3f
        mov [rbx + FN_GETTER], r12
        jmp .Lfa_done
3:      mov rdi, r12
        call opcode_of
        mov r13d, eax
        cmp eax, OP_MASK_SHL
        jne 4f
        cmp dword ptr [r12 + N_AUX], 5
        jb .Lfa_index
        mov rdi, [r12 + N_DATA + 32]
        call opcode_of
        cmp eax, OP_STORAGE
        jne .Lfa_done
        mov rax, [r12 + N_DATA + 32]
        mov [rbx + FN_GETTER], rax
        jmp .Lfa_done
4:      cmp r13d, OP_STORAGE
        jne 5f
        mov [rbx + FN_GETTER], r12
        jmp .Lfa_done
5:      cmp r13d, OP_DATA
        jne .Lfa_done
        # a struct: every term a storage at the same location...
        cmp dword ptr [r12 + N_AUX], 2
        jb .Lfa_index
        mov r13, [r12 + N_DATA + 8]     # t0
        PAT rsi, "('storage', 256, 0, ':loc')"
        mov rdi, r13
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 7f
        B rax, 0
        mov [rsp + FA_T1], rax          # loc
        mov r14d, 2
6:      cmp r14d, [r12 + N_AUX]
        jae 61f
        mov rdi, [r12 + N_DATA + r14*8]
        mov rsi, [rsp + FA_T1]
        call .Lfa_is_storage_add_loc
        test eax, eax
        jz 7f
        inc r14d
        jmp 6b
61:     mov [rbx + FN_GETTER], r13
7:      cmp qword ptr [rbx + FN_GETTER], 0
        jne .Lfa_done
        # ...or every term hashing the same small location
        mov qword ptr [rsp + FA_T2], 0  # prev_loc (python's -1: none yet)
        mov r14d, 1
8:      cmp r14d, [r12 + N_AUX]
        jae 9f
        mov rdi, [r12 + N_DATA + r14*8]
        lea rsi, [rip + small_sha3_loc]
        call walk_find
        test rax, rax
        jz .Lfa_done                    # no loc
        cmp rax, 1                      # loc 0 is falsy in python
        je .Lfa_done
        cmp qword ptr [rsp + FA_T2], 0
        je 81f
        mov rdi, rax
        mov rsi, [rsp + FA_T2]
        push rax
        push rax
        call py_equal
        pop rdx
        pop rdx
        test eax, eax
        jz .Lfa_done
        mov rax, rdx
81:     mov [rsp + FA_T2], rax
        inc r14d
        jmp 8b
9:      mov rsi, [rsp + FA_T2]
        LOADS rdi, LOC
        call mk2
        mov rsi, rax
        LOADS rdi, STRUCT
        call mk2
        mov [rbx + FN_GETTER], rax
.Lfa_done:
        mov rdi, rbx                    # (--explain: explain_text, explain.s)
        call explain_traits
        add rsp, MATCH_BINDINGS_SIZE + 48
        LEAVE
# locals
# the first line of a branch (python: branch[0])
.Lfa_first_line:
        cmp dword ptr [rdi + N_AUX], 0
        je .Lfa_index
        mov rax, [rdi + N_DATA]
        ret
# eax: rdi ~ ('storage', 256, 0, ('add', Any, rsi))
.Lfa_is_storage_add_loc:
        sub rsp, 24
        mov [rsp], rdi
        mov [rsp + 8], rsi
        call opcode_of
        cmp eax, OP_STORAGE
        jne 1f
        mov rdi, [rsp]
        cmp dword ptr [rdi + N_AUX], 4
        jne 1f
        cmp qword ptr [rdi + N_DATA + 8], 513
        jne 1f
        cmp qword ptr [rdi + N_DATA + 16], 1
        jne 1f
        mov rdi, [rdi + N_DATA + 24]
        mov [rsp + 16], rdi
        call opcode_of
        cmp eax, OP_ADD
        jne 1f
        mov rdi, [rsp + 16]
        cmp dword ptr [rdi + N_AUX], 3
        jne 1f
        mov rdi, [rdi + N_DATA + 16]
        mov rsi, [rsp + 8]
        call py_equal
        add rsp, 24
        ret
1:      xor eax, eax
        add rsp, 24
        ret
.Lfa_assert_trace:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_trace]
        call err_throw
.Lfa_index:
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_index]
        call err_throw
ENDF fn_analyse

        .section .rodata
.Ls_index: .asciz "function: an empty branch or return"
        .text

# small_sha3_loc(x) -> rax: the location of ('sha3', ('data', _, l)) or
# ('sha3', l, ...) when l is an int below 1000 (a truthy value: the loc
# itself, so 0 gives 0 - python's `not loc` treats it the same)
FUNC small_sha3_loc
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE
        mov rbx, rdi
        PAT rsi, "('sha3', ('data', 'Any', ':l'))"
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 1f
        mov rdi, [rsp]
        call .Lss_small
        test rax, rax
        jnz 2f
1:      mov rdi, rbx
        call opcode_of
        cmp eax, OP_SHA3
        jne 3f
        cmp dword ptr [rbx + N_AUX], 2
        jb 3f
        mov rdi, [rbx + N_DATA + 8]
        call .Lss_small
        test rax, rax
        jnz 2f
3:      xor eax, eax
2:      add rsp, MATCH_BINDINGS_SIZE
        LEAVE
# the value if an int below 1000, else 0
.Lss_small:
        sub rsp, 24
        mov [rsp], rdi
        call is_int
        test eax, eax
        jz 1f
        mov rdi, [rsp]
        mov rsi, 1000
        TAG rsi
        call int_cmp
        cmp eax, -1
        jne 1f
        mov rax, [rsp]
        add rsp, 24
        ret
1:      xor eax, eax
        add rsp, 24
        ret
ENDF small_sha3_loc

# simplify_string_getter(fn): a read-only function returning a string
# from storage becomes a getter of it
FUNC simplify_string_getter
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 16
        mov rbx, rdi
        cmp qword ptr [rbx + FN_READ_ONLY], 0
        je .Lsg_done
        mov r12, [rbx + FN_RETURNS]
        cmp dword ptr [r12 + N_AUX], 0
        je .Lsg_done
        xor r13d, r13d
1:      cmp r13d, [r12 + N_AUX]
        jae 2f
        PAT rsi, "('return', ('data', ('arr', ('storage', 256, 0, ('length', ':loc')), '...')))"
        mov rdi, [r12 + N_DATA + r13*8]
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz .Lsg_done
        inc r13d
        jmp 1b
2:      # [('return', ('storage', 256, 0, ('array', ('range', 0, ('storage', 256, 0, ('length', loc))), loc)))]
        B rsi, 0
        LOADS rdi, LENGTH
        call mk2
        mov rcx, rax
        LOADS rdi, STORAGE
        mov esi, 513
        mov edx, 1
        call mk4
        mov rdx, rax
        LOADS rdi, RANGE
        mov esi, 1
        call mk3
        mov rsi, rax
        B rdx, 0
        LOADS rdi, ARRAY
        call mk3
        mov rcx, rax
        LOADS rdi, STORAGE
        mov esi, 513
        mov edx, 1
        call mk4
        mov [rbx + FN_GETTER], rax
        mov rsi, rax
        LOADS rdi, RETURN
        call mk2
        mov rdi, rax
        call mk_list1
        mov [rbx + FN_TRACE], rax
.Lsg_done:
        add rsp, MATCH_BINDINGS_SIZE + 16
        LEAVE
ENDF simplify_string_getter

# --- the function ---

# function_new(hash, trace, abi) -> fn: Function(hash, trace)
FUNC function_new
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov edi, FN_SIZEOF
        call arena_alloc
        mov r14, rax
        mov [r14 + FN_HASH], rbx
        mov [r14 + FN_ABI], r13
        mov rax, [r13 + N_DATA + 8]
        mov [r14 + FN_INPUTS], rax
        mov rdi, r13
        xor esi, esi
        call abi_func_name
        mov [r14 + FN_NAME], rax
        mov rdi, r13
        mov esi, PF_COLOR
        call abi_func_name
        mov [r14 + FN_COLOR_NAME], rax
        mov rdi, r13
        call abi_name
        mov [r14 + FN_ABI_NAME], rax
        mov [r14 + FN_TRACE], r12
        mov [r14 + FN_ORIG_TRACE], r12
        mov rdi, r14
        call make_params
        mov [r14 + FN_PARAMS], rax
        mov rdi, [r14 + FN_NAME]
        lea rsi, [rip + .Ls_unknown]
        call str_contains_c
        test eax, eax
        jz 1f
        mov rdi, r14
        call make_names
1:      mov rdi, r14
        mov rsi, [r14 + FN_TRACE]
        call cleanup_masks
        mov [r14 + FN_TRACE], rax
        mov qword ptr [r14 + FN_AST], 0
        mov rdi, r14
        call fn_analyse
        xor eax, eax
        cmp qword ptr [r14 + FN_CONST], 0
        jne 2f
        cmp qword ptr [r14 + FN_GETTER], 0
        jne 2f
        mov eax, 1
2:      mov [r14 + FN_IS_REGULAR], rax
        mov rax, r14
        LEAVE
ENDF function_new

# --- the text ---

# fn_print_lines(fn) -> list of str: Function._print
FUNC fn_print_lines
        ENTER
        sub rsp, 32
        mov rbx, rdi
        mov r12, [r15 + CTX_FUNC]
        mov [rsp], r12                  # (restored after)
        mov [r15 + CTX_FUNC], rbx
        # the parameters for get_param_name, when the abi had none
        cmp qword ptr [rbx + FN_INPUTS], 0
        jne 1f
        mov rdi, [rbx + FN_PARAMS]
        lea rsi, [rip + param_kind_name]
        call map_seq
        mov [rbx + FN_INPUTS], rax
1:      cmp qword ptr [rbx + FN_CONST], 0
        je .Lfp_def
        # "const name = value"
        mov r12, [rbx + FN_CONST]
        mov rdi, r12
        call opcode_of
        cmp eax, OP_RETURN
        jne 2f
        cmp dword ptr [r12 + N_AUX], 2
        jb .Lfp_index
        mov r12, [r12 + N_DATA + 8]
2:      call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + C_HEADER]
        call sb_append_c
        mov rdi, r13
        lea rsi, [rip + .Ls_const_]
        call sb_append_c
        mov rdi, r13
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        # color_name.split("()")[0]
        mov rax, [rbx + FN_COLOR_NAME]
        lea rdi, [rax + N_DATA + 4]
        lea rsi, [rip + .Ls_empty_paren]
        call strstr@PLT
        mov rdx, [rbx + FN_COLOR_NAME]
        lea rsi, [rdx + N_DATA + 4]
        test rax, rax
        jz 3f
        mov rdx, rax
        sub rdx, rsi
        jmp 4f
3:      mov edx, [rdx + N_DATA]
4:      mov rdi, r13
        call sb_append
        mov rdi, r13
        lea rsi, [rip + .Ls_eq_sp]
        call sb_append_c
        mov rdi, r13
        lea rsi, [rip + C_BOLD]
        call sb_append_c
        mov rdi, r13
        mov rsi, r12
        mov edx, PF_PARENS
        call sb_append_pret
        mov rdi, r13
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        mov rdi, r13
        call sb_finish
        mov rdi, rax
        call mk_list1
        jmp .Lfp_ret
.Lfp_def:
        # "def name[ payable]: # comment"
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_def_]
        lea rdx, [rip + C_HEADER]
        mov ecx, PF_COLOR
        call sb_append_col_c
        mov rdi, r13
        mov rsi, [rbx + FN_COLOR_NAME]
        call sb_append_str
        cmp qword ptr [rbx + FN_PAYABLE], 0
        je 5f
        mov rdi, r13
        lea rsi, [rip + .Ls_payable]
        lea rdx, [rip + C_HEADER]
        mov ecx, PF_COLOR
        call sb_append_col_c
5:      mov rdi, r13
        lea rsi, [rip + .Ls_colon_sp]
        call sb_append_c
        # the comment
        lea r14, [rip + .Ls_not_payable]
        cmp qword ptr [rbx + FN_PAYABLE], 0
        je 6f
        xor r14d, r14d
6:      mov rdi, [rbx + FN_NAME]
        lea rsi, [rip + .Ls_fallback_q]
        call str_eq_c
        test eax, eax
        jz 7f
        lea r14, [rip + .Ls_default]
        cmp qword ptr [rbx + FN_PAYABLE], 0
        jne 7f
        lea r14, [rip + .Ls_not_payable_default]
7:      test r14, r14
        jz 8f
        mov rdi, r13
        mov rsi, r14
        lea rdx, [rip + C_GRAY]
        mov ecx, PF_COLOR
        call sb_append_col_c
8:      mov rdi, r13
        call sb_finish
        mov rdi, rax
        call mk_list1
        mov r14, rax                    # the header line
        mov rdi, [rbx + FN_AST]
        test rdi, rdi
        jnz 9f
        mov rdi, [rbx + FN_TRACE]
9:      mov esi, 2
        call pprint_logic
        cmp dword ptr [rax + N_AUX], 0
        jne 10f
        lea rdi, [rip + .Ls_stop_line]
        call str_new_c
        mov rdi, rax
        call mk_list1
10:     mov rdi, r14
        mov rsi, rax
        call list_concat
.Lfp_ret:
        mov rcx, [rsp]
        mov [r15 + CTX_FUNC], rcx
        add rsp, 32
        LEAVE
.Lfp_index:
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_index]
        call err_throw
ENDF fn_print_lines

# param_kind_name((idx, kind, name), arg) -> (kind, name)
FUNC param_kind_name
        mov rsi, [rdi + N_DATA + 16]
        mov rdi, [rdi + N_DATA + 8]
        jmp mk2
ENDF param_kind_name

# fn_print(fn) -> str: the lines joined with newlines (kept on the
# function, as python's priority prints it repeatedly)
FUNC fn_print
        ENTER
        mov rbx, rdi
        mov rax, [rbx + FN_PRINT]
        test rax, rax
        jnz 1f
        call fn_print_lines
        lea rdi, [rip + .Ls_newline]
        mov rsi, rax
        call str_join
        mov [rbx + FN_PRINT], rax
1:      LEAVE
ENDF fn_print

# fn_priority(fn) -> rax: the sort key of the functions in the output -
# the self-destructing ones first, then by the length of their text
FUNC fn_priority
        ENTER
        mov rbx, rdi
        mov rax, [rbx + FN_PRIORITY]
        test rax, rax
        jz 3f
        sub rax, 2
        LEAVE
3:      cmp qword ptr [rbx + FN_TRACE], 0
        je 1f
        mov rdi, [rbx + FN_TRACE]       # "selfdestruct" in str(self.trace)
        lea rsi, [rip + .Ls_selfdestruct]
        call mentions_c
        test eax, eax
        jnz 2f
        mov rdi, rbx
        call fn_print
        mov rdi, rax
        call str_charlen
        jmp 4f
1:      xor eax, eax
        jmp 4f
2:      mov rax, -1
4:      lea rcx, [rax + 2]
        mov [rbx + FN_PRIORITY], rcx
        LEAVE
ENDF fn_priority

# --- the functions printed on threads ---

        # an iteration of print_many
        .set PT_TEXT, 0                 # the text (malloc'd), or 0 when it failed
        .set PT_LEN, 8
        .set PT_PRIORITY, 16            # FN_PRIORITY's value
        .set PT_SIZEOF, 24
        # print_many's shared state
        .set PM_FUNCS, 0                # the vec of functions
        .set PM_TASKS, 8
        .set PM_LIMIT, 16
        .set PM_LOADER, 24
        .set PM_SIZEOF, 32

# print_many(funcs, threads): every function printed (fn_print) and its
# priority computed (fn_priority), on threads - what the contract's text
# and json take of the functions, the same work for each. Each function
# is printed on a context of its own, from a copy of it whose values are
# imported there (the printer compares what it makes with what it reads,
# by pointer: both must be of the same context). The texts are made
# strings of this context after, in order. A function whose printing
# fails is left as it was: fn_print, later, fails the same way where
# python does.
FUNC print_many
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r13, rsi
        cmp r13, 1
        jbe 9f
        cmp qword ptr [rbx + VEC_LEN], 1
        jbe 9f
        mov edi, PM_SIZEOF
        call arena_alloc
        mov r12, rax
        mov [r12 + PM_FUNCS], rbx
        mov rdi, [rbx + VEC_LEN]
        imul rdi, rdi, PT_SIZEOF
        call arena_alloc
        mov [r12 + PM_TASKS], rax
        mov rax, [r15 + CTX_CHILD_LIMIT]
        mov [r12 + PM_LIMIT], rax
        mov rax, [r15 + CTX_LOADER]
        mov [r12 + PM_LOADER], rax
        mov rdi, [rbx + VEC_LEN]
        mov rsi, r13
        lea rdx, [rip + print_one]
        mov rcx, r12
        call par_for
        # the texts, strings of this context now
        xor r14d, r14d
1:      cmp r14, [rbx + VEC_LEN]
        jae 9f
        imul r13, r14, PT_SIZEOF
        add r13, [r12 + PM_TASKS]
        mov rdi, [r13 + PT_TEXT]
        test rdi, rdi
        jz 2f
        mov rsi, [r13 + PT_LEN]
        call str_new
        mov rcx, [rbx + VEC_DATA]
        mov rcx, [rcx + r14*8]
        mov [rcx + FN_PRINT], rax
        mov rax, [r13 + PT_PRIORITY]
        mov [rcx + FN_PRIORITY], rax
        mov rdi, [r13 + PT_TEXT]
        call free@PLT
2:      inc r14
        jmp 1b
9:      add rsp, 16
        LEAVE
ENDF print_many

# print_one(i, pm): print_many's iteration i (see there)
FUNC print_one
        push r15
        ENTER
        sub rsp, ERR_SIZEOF + 24        # (with r15 pushed: 8 mod 16 keeps rsp aligned)
        .set PO1_CTX, ERR_SIZEOF
        .set PO1_MAIN, ERR_SIZEOF + 8
        mov [rsp + PO1_MAIN], r15
        mov rbx, rsi                    # pm
        imul r12, rdi, PT_SIZEOF
        add r12, [rbx + PM_TASKS]       # the task
        mov rax, [rbx + PM_FUNCS]
        mov rax, [rax + VEC_DATA]
        mov r13, [rax + rdi*8]          # the function (the main context's)
        call ctx_try_new                # (bound to this thread)
        test rax, rax
        jz 8f
        mov [rsp + PO1_CTX], rax
        mov r15, rax
        call ctx_set_stack
        mov rax, [rbx + PM_LIMIT]
        mov [r15 + CTX_MEM_LIMIT], rax
        mov rax, [rbx + PM_LOADER]
        mov [r15 + CTX_LOADER], rax
        mov rdi, rsp
        call err_catch
        test eax, eax
        jnz 7f
        # the copy, its values imported
        mov edi, FN_SIZEOF
        call arena_alloc
        mov r14, rax
        mov rdi, rax
        mov rsi, r13
        mov edx, FN_SIZEOF
        call memcpy@PLT
        mov qword ptr [r14 + FN_PRINT], 0
        mov qword ptr [r14 + FN_PRIORITY], 0
        lea rbx, [rip + fn_value_fields]
3:      mov ecx, [rbx]
        cmp ecx, -1
        je 4f
        mov rdi, [r14 + rcx]
        call value_import_root
        mov ecx, [rbx]
        mov [r14 + rcx], rax
        add rbx, 4
        jmp 3b
4:      mov rdi, r14
        call fn_print
        mov rdi, r14
        call fn_priority
        call err_end
        mov rax, [r14 + FN_PRIORITY]
        mov [r12 + PT_PRIORITY], rax
        mov rax, [r14 + FN_PRINT]       # its text, for the main thread
        mov ebx, [rax + N_DATA]
        mov [r12 + PT_LEN], rbx
        lea rdi, [rbx + 1]
        call malloc@PLT
        test rax, rax
        jz 7f
        mov [r12 + PT_TEXT], rax
        mov rdi, rax
        mov rsi, [r14 + FN_PRINT]
        add rsi, N_DATA + 4
        lea rdx, [rbx + 1]
        call memcpy@PLT
7:      mov rdi, [rsp + PO1_CTX]
        call ctx_free
8:      mov r15, [rsp + PO1_MAIN]
        add rsp, ERR_SIZEOF + 24
        LEAVE_NORET
        pop r15
        ret
ENDF print_one

        .section .rodata
        .align 4
# the fields of a function that hold values of its context
fn_value_fields:
        .long FN_ABI, FN_INPUTS, FN_TRACE, FN_ORIG_TRACE, FN_PARAMS, FN_CONST
        .long FN_GETTER, FN_RETURNS, FN_AST, -1
        .text

        .section .note.GNU-stack,"",@progbits
