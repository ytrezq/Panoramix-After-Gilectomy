# The contract (port of contract.py): the storage definitions and the
# final form of the functions - the parameters named, the traces folded
# and rewritten for display (the asts).

.include "defs.inc"

        .section .rodata
.Ls_logname:    .asciz "panoramix.contract"
.Ls_storage_failed: .asciz "Storage postprocessing failed. This is very bad! (%s)"
.Ls_safemath_failed: .asciz "SafeMath failed: the arithmetic stays as it is. (%s)"
        .text

.macro B reg, n
        mov \reg, [rsp + 8*(\n)]
.endm

# contract_new(functions vec, problems list) -> contract: python's
# Contract(functions, problems, code) - the code is the loader's (python's
# bytes(loader.binary or [])), None without one (the tests')
FUNC contract_new
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov edi, CT_SIZEOF
        call arena_alloc
        mov [rax + CT_FUNCS], rbx
        mov [rax + CT_PROBLEMS], r12
        mov r13, rax
        xor edi, edi
        xor esi, esi
        call mk_list
        mov [r13 + CT_STOR_DEFS], rax
        call vec_new
        mov [r13 + CT_CONSTS], rax
        xor edi, edi
        xor esi, esi
        call mk_list
        mov [r13 + CT_SAFEMATH], rax
        call vec_new                    # (the decompiler's, see there)
        mov [r13 + CT_INTERNAL], rax
        mov rax, [r15 + CTX_LOADER]
        test rax, rax
        jz 1f
        mov rcx, [rax + LD_CODE]
        mov [r13 + CT_CODE], rcx
        mov rcx, [rax + LD_CODELEN]
        mov [r13 + CT_CODELEN], rcx
1:      mov rax, r13
        LEAVE
ENDF contract_new

# contract_postprocess(contract): the storage (storage.s), the parameter
# names, the constants, the asts - the storage, the asts and the SafeMath
# of the recursive internal functions too (after the others)
FUNC contract_postprocess
        ENTER
        sub rsp, ERR_SIZEOF + 16
        .set CP_NAMES, ERR_SIZEOF
        .set CP_ALL, ERR_SIZEOF + 8     # the functions, then the internal ones
        mov rbx, rdi
        mov rax, [rbx + CT_FUNCS]
        mov [rsp + CP_ALL], rax
        mov rax, [rbx + CT_INTERNAL]
        cmp qword ptr [rax + VEC_LEN], 0
        je 0f
        call vec_new
        mov [rsp + CP_ALL], rax
        mov rdi, rax
        mov rsi, [rbx + CT_FUNCS]
        mov rdx, [rsi + VEC_LEN]
        mov rsi, [rsi + VEC_DATA]
        call vec_extend
        mov rdi, [rsp + CP_ALL]
        mov rsi, [rbx + CT_INTERNAL]
        mov rdx, [rsi + VEC_LEN]
        mov rsi, [rsi + VEC_DATA]
        call vec_extend
0:      mov rdi, rsp
        call err_catch
        test eax, eax
        jnz 1f
        mov rdi, [rsp + CP_ALL]
        mov rsi, [rbx + CT_CODE]
        mov rdx, [rbx + CT_CODELEN]
        call st_rewrite_functions
        mov [rbx + CT_STOR_DEFS], rax
        mov [rbx + CT_LANG], rdx
        call err_end
        jmp 2f
1:      # this is critical, because it causes the full contract to
        # display very badly, and cannot be limited in scope to just one
        # affected function
        mov edi, eax
        call st_catch_all
        mov edi, LOG_ERROR
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_storage_failed]
        mov rcx, [r15 + CTX_ERR_MSG]
        call log_fmt
        xor edi, edi
        xor esi, esi
        call mk_list
        mov [rbx + CT_STOR_DEFS], rax
        mov rdi, [rsp + CP_ALL]         # the accesses as the slots they are
        call st_rewrite_raw
2:      # (not the names of variables nor of params, see prettify.set_names)
        call vec_new
        mov r12, rax
        mov r13, [rbx + CT_STOR_DEFS]
        xor r14d, r14d
3:      cmp r14d, [r13 + N_AUX]
        jae 4f
        mov rax, [r13 + N_DATA + r14*8]
        mov rdi, r12
        mov rsi, [rax + N_DATA + 8]
        call vec_push
        inc r14d
        jmp 3b
4:      mov rdi, r12
        call vec_to_list
        mov [rsp + CP_NAMES], rax
        mov rdi, rax
        xor esi, esi
        call set_names
        # the parameters by name
        mov r12, [rbx + CT_FUNCS]
        xor r13d, r13d
5:      cmp r13, [r12 + VEC_LEN]
        jae 6f
        mov rax, [r12 + VEC_DATA]
        mov r14, [rax + r13*8]
        mov rdi, r14
        mov rsi, [rsp + CP_NAMES]
        call fn_rename_params
        mov rdi, [r14 + FN_TRACE]
        lea rsi, [rip + replace_param_names]
        mov rdx, r14
        call replace_f
        mov [r14 + FN_TRACE], rax
        inc r13
        jmp 5b
6:      # the constants: the all-caps ones last, it looks better
        mov rdi, rbx
        xor esi, esi
        call contract_consts
        mov rdi, rbx
        mov esi, 1
        call contract_consts
        mov rdi, [rsp + CP_ALL]
        call make_asts
        mov rdi, rbx
        mov rsi, [rsp + CP_ALL]
        call contract_safemath
        add rsp, ERR_SIZEOF + 16
        LEAVE
ENDF contract_postprocess

# contract_safemath(contract, functions): python's postprocess's SafeMath -
# the asts' checked arithmetic calls of the functions of the contract's def
# SafeMath (safemath.s); an error leaves the asts as they are, the block
# empty
FUNC contract_safemath
        ENTER
        sub rsp, ERR_SIZEOF + 16
        mov rbx, rdi
        mov [rsp + ERR_SIZEOF], rsi
        mov rdi, rsp
        call err_catch
        test eax, eax
        jnz 8f
        mov r12, [rsp + ERR_SIZEOF]
        call vec_new
        mov r13, rax
        xor r14d, r14d
1:      cmp r14, [r12 + VEC_LEN]
        jae 2f
        mov rax, [r12 + VEC_DATA]
        mov rax, [rax + r14*8]
        mov rdi, r13
        mov rsi, [rax + FN_AST]
        call vec_push
        inc r14
        jmp 1b
2:      mov rdi, r13
        call vec_to_list
        mov rdi, rax
        call safemath_rewrite
        mov r13, rax                    # (asts, defs)
        call err_end
        mov rax, [r13 + N_DATA + 8]
        mov [rbx + CT_SAFEMATH], rax
        mov r13, [r13 + N_DATA]
        xor r14d, r14d
3:      cmp r14, [r12 + VEC_LEN]
        jae 9f
        mov rax, [r12 + VEC_DATA]
        mov rax, [rax + r14*8]
        mov rcx, [r13 + N_DATA + r14*8]
        mov [rax + FN_AST], rcx
        inc r14
        jmp 3b
8:      mov edi, eax
        call st_catch_all
        mov edi, LOG_ERROR
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_safemath_failed]
        mov rcx, [r15 + CTX_ERR_MSG]
        call log_fmt
        xor edi, edi
        xor esi, esi
        call mk_list
        mov [rbx + CT_SAFEMATH], rax
9:      add rsp, ERR_SIZEOF + 16
        LEAVE
ENDF contract_safemath

# contract_consts(contract, all_caps): the constant functions whose name
# is (or isn't) all caps, appended to the contract's constants
FUNC contract_consts
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, [rbx + CT_FUNCS]
        xor r14d, r14d
1:      cmp r14, [r13 + VEC_LEN]
        jae 3f
        mov rax, [r13 + VEC_DATA]
        mov rdi, [rax + r14*8]
        inc r14
        cmp qword ptr [rdi + FN_CONST], 0
        je 1b
        mov rdi, [rdi + FN_NAME]
        call str_upper
        mov rcx, [r13 + VEC_DATA]
        mov rcx, [rcx + r14*8 - 8]
        mov rdi, rax
        mov rsi, [rcx + FN_NAME]
        call str_eq
        cmp rax, r12
        jne 1b
        mov rax, [r13 + VEC_DATA]
        mov rsi, [rax + r14*8 - 8]
        mov rdi, [rbx + CT_CONSTS]
        call vec_push
        jmp 1b
3:      LEAVE
ENDF contract_consts

# str_upper(str) -> str: python's str.upper() of ASCII text (arena)
FUNC str_upper
        ENTER
        mov rbx, rdi
        mov edi, [rbx + N_DATA]
        inc edi
        call arena_alloc_raw
        mov r12, rax
        mov ecx, [rbx + N_DATA]
        xor edx, edx
1:      cmp edx, ecx
        jae 2f
        movzx eax, byte ptr [rbx + N_DATA + 4 + rdx]
        lea esi, [eax - 'a']
        cmp esi, 25
        ja 3f
        sub eax, 32
3:      mov [r12 + rdx], al
        inc edx
        jmp 1b
2:      mov rdi, r12
        mov esi, [rbx + N_DATA]
        call str_new
        LEAVE
ENDF str_upper

# replace_param_names(exp, fn): ('cd', idx) -> ('param', name) for the
# function's parameters
FUNC replace_param_names
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE
        mov rbx, rdi
        mov r12, rsi
        PATXD "('cd', ':int:idx')"
        test eax, eax
        jz 1f
        mov rdi, r12
        B rsi, 0
        call params_get
        test rax, rax
        jz 1f
        mov rsi, [rax + N_DATA + 16]
        LOADS rdi, PARAM
        call mk2
        add rsp, MATCH_BINDINGS_SIZE
        LEAVE
1:      mov rax, rbx
        add rsp, MATCH_BINDINGS_SIZE
        LEAVE
ENDF replace_param_names

# --- the asts ---

# make_asts(functions): python's make_asts - the ast of every function (a
# vec: the contract's, then its internal ones) (make_ast): short_circuits,
# the folds (all of them on threads: fold_many), then the rewrites for
# display (make_ast_folded)
FUNC make_asts
        ENTER
        sub rsp, 16
        mov r12, rdi
        call vec_new
        mov r13, rax
        xor r14d, r14d
1:      cmp r14, [r12 + VEC_LEN]
        jae 2f
        mov rax, [r12 + VEC_DATA]
        mov rax, [rax + r14*8]
        mov rdi, [rax + FN_TRACE]
        call short_circuits
        mov rdi, r13
        mov rsi, rax
        call vec_push
        inc r14
        jmp 1b
2:      mov rdi, r13
        call vec_to_list
        mov rdi, rax
        call fold_many
        mov [rsp], rax                  # the folded traces
        xor r13d, r13d
3:      cmp r13, [r12 + VEC_LEN]
        jae 4f
        mov rax, [r12 + VEC_DATA]
        mov r14, [rax + r13*8]
        mov rdi, [rsp]
        mov rdi, [rdi + N_DATA + r13*8]
        call make_ast_folded
        mov [r14 + FN_AST], rax
        inc r13
        jmp 3b
4:      add rsp, 16
        LEAVE
ENDF make_asts

# make_ast_folded(folded) -> list: python's contract.make_ast of a trace
# short-circuited and folded already (fold_many, fold_isolated): its
# widths fixed (prettify's fix_widths), rewritten for display
FUNC make_ast_folded
        ENTER
        call fix_widths
        mov rdi, rax
        lea rsi, [rip + other_1]        # (pure callbacks: replace_f_memo,
        xor edx, edx                    # each subtree once)
        call replace_f_memo
        mov rdi, rax
        lea rsi, [rip + other_2]
        xor edx, edx
        call replace_f_memo
        LEAVE
ENDF make_ast_folded

# other_1(exp, arg): a string constant under the mask of its own size
FUNC other_1
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE
        mov rbx, rdi
        PAT rsi, "('mask_shl', ':int:size', ':n_size', ':size_n', ':str:val')"
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz .Lo1_asis
        # 256 - size == n_size, size - 256 == size_n
        mov edi, 513
        B rsi, 0
        call int_sub
        mov rdi, rax
        B rsi, 1
        call py_equal
        test eax, eax
        jz .Lo1_asis
        B rdi, 0
        mov esi, 513
        call int_sub
        mov rdi, rax
        B rsi, 2
        call py_equal
        test eax, eax
        jz .Lo1_asis
        # size + 16 == len(val) * 8, len(val) > 0, quoted
        B rdi, 3
        call str_charlen
        test eax, eax
        jz .Lo1_asis
        shl eax, 3
        mov r12d, eax
        B rdi, 0
        mov esi, 16
        TAG rsi
        call int_add
        mov rdi, r12
        TAG rdi
        cmp rax, rdi
        jne .Lo1_asis
        B rax, 3
        cmp byte ptr [rax + N_DATA + 4], '\''
        jne .Lo1_asis
        mov ecx, [rax + N_DATA]
        cmp byte ptr [rax + N_DATA + 4 + rcx - 1], '\''
        jne .Lo1_asis
        add rsp, MATCH_BINDINGS_SIZE
        LEAVE
.Lo1_asis:
        mov rax, rbx
        add rsp, MATCH_BINDINGS_SIZE
        LEAVE
ENDF other_1

# other_2(exp, arg): a few display rewrites
FUNC other_2
        OPCODE_OF_RDI                   # (('if', ...), ('mask_shl', ...) only)
        cmp eax, OP_IF
        je 1f
        cmp eax, OP_MASK_SHL
        je 1f
        mov rax, rdi
        ret
1:      ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 16
        mov rbx, rdi
        PAT rsi, "('if', ('eq', ':a', ':b'), ':if_true')"
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 1f
        # if_true == [('return', ('eq', a, b))] -> [('return', ('bool', 1))]
        B rsi, 0
        B rdx, 1
        LOADS rdi, EQ
        call mk3
        mov r12, rax
        mov rsi, rax
        LOADS rdi, RETURN
        call mk2
        mov rdi, rax
        call mk_list1
        B rdi, 2
        mov rsi, rax
        call py_equal
        test eax, eax
        jz 1f
        LOADS rdi, BOOL
        mov esi, 3
        call mk2
        mov rsi, rax
        LOADS rdi, RETURN
        call mk2
        mov rdi, rax
        call mk_list1
        mov rdx, rax
        mov rsi, r12
        LOADS rdi, IF
        call mk3
        jmp .Lo2_ret
1:      PAT rsi, "('mask_shl', 160, 0, 0, ':str:e')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 2f
        B rdi, 0
        call str_id
        IN_OPSET addresses, rax         # address, coinbase, caller, origin
        je 2f
        B rax, 0
        jmp .Lo2_ret
2:      PAT rsi, "('mask_shl', ':int:size', ':int:off', ':int:m_off', ':e')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 3f
        # m_off == -off, off in 1..8, size + off in 8..256 (powers of two)
        B rdi, 1
        call int_neg
        cmp rax, [rsp + 16]
        jne 3f
        B rdi, 1
        call int_to_i64
        cmp rax, 1
        jb 3f
        cmp rax, 8
        ja 3f
        B rdi, 0
        B rsi, 1
        call int_add
        mov r12, rax
        cmp rax, 17                     # 8
        je 21f
        cmp rax, 33                     # 16
        je 21f
        cmp rax, 65                     # 32
        je 21f
        cmp rax, 129                    # 64
        je 21f
        cmp rax, 257                    # 128
        je 21f
        cmp rax, 513                    # 256
        jne 3f
21:     # a storage access no wider than the mask's top: ('div', e, 2 ** off)
        B rdi, 3
        call opcode_of
        cmp eax, OP_ST
        jne 22f
        B rax, 3
        cmp dword ptr [rax + N_AUX], 2
        jb .Lo2_index
        mov rdi, [rax + N_DATA + 8]
        call is_int
        test eax, eax
        jz 22f
        B rax, 3
        mov rdi, [rax + N_DATA + 8]
        mov rsi, r12
        call int_cmp
        cmp eax, 1
        je 22f
        B rdi, 1
        call int_to_i64
        mov rdi, rax
        call pow2
        mov rdx, rax
        B rsi, 3
        LOADS rdi, DIV
        call mk3
        jmp .Lo2_ret
22:     # ('div', ('mask', size + off, 0, e), 2 ** off)
        mov rsi, r12
        mov edx, 1
        B rcx, 3
        LOADS rdi, MASK
        call mk4
        mov r12, rax
        B rdi, 1
        call int_to_i64
        mov rdi, rax
        call pow2
        mov rdx, rax
        mov rsi, r12
        LOADS rdi, DIV
        call mk3
        jmp .Lo2_ret
3:
.Lo2_asis:
        mov rax, rbx
.Lo2_ret:
        add rsp, MATCH_BINDINGS_SIZE + 16
        LEAVE
.Lo2_index:
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_o2_index]
        call err_throw
ENDF other_2

        .section .rodata
.Ls_o2_index:   .asciz "tuple index out of range"
        .text

        OPSET_MEMBER addresses, OP_ADDRESS
        OPSET_MEMBER addresses, OP_COINBASE
        OPSET_MEMBER addresses, OP_CALLER
        OPSET_MEMBER addresses, OP_ORIGIN
        OPSET_END addresses, OP_COUNT

        .section .note.GNU-stack,"",@progbits
