# The contract (port of contract.py): the storage definitions and the
# final form of the functions - the parameters named, the traces folded
# and rewritten for display (the asts).

.include "defs.inc"

        .section .rodata
.Ls_logname:    .asciz "panoramix.contract"
.Ls_storage_failed: .asciz "Storage postprocessing failed. This is very bad! (%s)"
.Ls_two_locs:   .asciz "Seems like we have two locations / storages with the same name: %v %v %v"
.Ls_assert_mask: .asciz "contract: a storage mask of an unexpected shape"
.Ls_assert_def: .asciz "contract: not a def"
.Ls_stor:       .asciz "stor"

        .text

.macro B reg, n
        mov \reg, [rsp + 8*(\n)]
.endm

# contract_new(functions vec, problems list) -> contract
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
        mov rax, r13
        LEAVE
ENDF contract_new

# contract_postprocess(contract): the storage, the parameter names, the
# constants, the asts
FUNC contract_postprocess
        ENTER
        sub rsp, ERR_SIZEOF + 16
        mov rbx, rdi
        mov rdi, rsp
        call err_catch
        test eax, eax
        jnz 1f
        mov rdi, [rbx + CT_FUNCS]
        call rewrite_functions
        mov [rbx + CT_STOR_DEFS], rax
        call err_end
        jmp 2f
1:      # this is critical, because it causes the full contract to
        # display very badly, and cannot be limited in scope to just one
        # affected function
        mov edi, LOG_ERROR
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_storage_failed]
        mov rcx, [r15 + CTX_ERR_MSG]
        call log_fmt
        xor edi, edi
        xor esi, esi
        call mk_list
        mov [rbx + CT_STOR_DEFS], rax
        mov qword ptr [rbx + CT_STOR_FAILED], 1
2:      # the parameters by name
        mov r12, [rbx + CT_FUNCS]
        xor r13d, r13d
3:      cmp r13, [r12 + VEC_LEN]
        jae 4f
        mov rax, [r12 + VEC_DATA]
        mov r14, [rax + r13*8]
        mov rdi, [r14 + FN_TRACE]
        lea rsi, [rip + replace_param_names]
        mov rdx, r14
        call replace_f
        mov [r14 + FN_TRACE], rax
        inc r13
        jmp 3b
4:      # the constants: the all-caps ones last, it looks better
        mov rdi, rbx
        xor esi, esi
        call contract_consts
        mov rdi, rbx
        mov esi, 1
        call contract_consts
        mov rdi, rbx
        call make_asts
        add rsp, ERR_SIZEOF + 16
        LEAVE
ENDF contract_postprocess

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

# replace_param_names(exp, fn): ('cd', idx) -> ('param', name) for the
# function's parameters
FUNC replace_param_names
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE
        mov rbx, rdi
        mov r12, rsi
        PAT rsi, "('cd', ':int:idx')"
        mov rdx, rsp
        call pat_match
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

# pred_type(exp) -> eax: a ('type', ...) tuple
FUNC pred_type
        ENTER
        call opcode_of
        cmp eax, OP_TYPE
        sete al
        movzx eax, al
        LEAVE
ENDF pred_type

# make_asts(contract): the ast of every function, then the storage
# types and fields that every use agrees on are dropped - which takes
# the whole contract, not one function
FUNC make_asts
        ENTER
        sub rsp, 32
        .set MA_LOCS, 0                 # od: loc -> vec of masks
        .set MA_NAMES, 8                # od: name -> vec of masks
        .set MA_MASKS, 16
        mov rbx, rdi
        mov r12, [rbx + CT_FUNCS]
        # the folds first, all of them (on threads: fold_many)
        call vec_new
        mov r13, rax
        xor r14d, r14d
0:      cmp r14, [r12 + VEC_LEN]
        jae 01f
        mov rax, [r12 + VEC_DATA]
        mov rax, [rax + r14*8]
        mov rdi, r13
        mov rsi, [rax + FN_TRACE]
        call vec_push
        inc r14
        jmp 0b
01:     mov rdi, r13
        call vec_to_list
        mov rdi, rax
        call fold_many
        mov [rsp + MA_MASKS], rax       # (the folded traces, for now)
        xor r13d, r13d
1:      cmp r13, [r12 + VEC_LEN]
        jae 2f
        mov rax, [r12 + VEC_DATA]
        mov r14, [rax + r13*8]
        mov rdi, rbx
        mov rsi, [rsp + MA_MASKS]
        mov rsi, [rsi + N_DATA + r13*8]
        call make_ast_folded
        mov [r14 + FN_AST], rax
        inc r13
        jmp 1b
2:      # the storage masks, by location and by name
        call vec_new
        mov [rsp + MA_MASKS], rax
        xor r13d, r13d
3:      cmp r13, [r12 + VEC_LEN]
        jae 4f
        mov rax, [r12 + VEC_DATA]
        mov rax, [rax + r13*8]
        mov rdi, [rax + FN_AST]
        lea rsi, [rip + pred_type]
        mov rdx, [rsp + MA_MASKS]
        call walk_collect
        inc r13
        jmp 3b
4:      call od_new
        mov [rsp + MA_LOCS], rax
        call od_new
        mov [rsp + MA_NAMES], rax
        mov r13, [rsp + MA_MASKS]
        xor r14d, r14d
5:      cmp r14, [r13 + VEC_LEN]
        jae 7f
        mov rax, [r13 + VEC_DATA]
        mov r12, [rax + r14*8]
        inc r14
        mov rdi, r12
        call get_loc
        mov rdi, rax
        call none_if_nil
        mov rdi, [rsp + MA_LOCS]
        mov rsi, rax
        call .Lma_group
        mov rdi, rax
        mov rsi, r12
        call set_add
        mov rdi, r12
        call get_name
        mov rdi, rax
        call none_if_nil
        mov rdi, [rsp + MA_NAMES]
        mov rsi, rax
        call .Lma_group
        mov rdi, rax
        mov rsi, r12
        call set_add
        jmp 5b
7:      mov r12, [rbx + CT_FUNCS]
        xor r13d, r13d
8:      cmp r13, [r12 + VEC_LEN]
        jae 9f
        mov rax, [r12 + VEC_DATA]
        mov r14, [rax + r13*8]
        mov rdi, [r14 + FN_AST]
        lea rsi, [rip + ast_cleanup]
        mov rdx, rsp                    # (the two dicts)
        call replace_f
        mov [r14 + FN_AST], rax
        inc r13
        jmp 8b
9:      add rsp, 32
        LEAVE
# the vec of masks of a key in a dict (rdi), made on demand (a defaultdict)
.Lma_group:
        sub rsp, 24
        mov [rsp], rdi
        mov [rsp + 8], rsi
        call od_get
        test rax, rax
        jnz 1f
        call vec_new
        mov [rsp + 16], rax
        mov rdi, [rsp]
        mov rsi, [rsp + 8]
        mov rdx, rax
        call od_put
        mov rax, [rsp + 16]
1:      add rsp, 24
        ret
ENDF make_asts

# ast_cleanup(exp, dicts): the cleanup of make_asts. dicts points at the
# loc dict, then the name dict.
FUNC ast_cleanup
        # (its patterns are ('field', ...) and ('type', ...): the others
        # are left as they are without trying them - every node goes here)
        OPCODE_OF_RDI
        cmp eax, OP_FIELD
        je 1f
        cmp eax, OP_TYPE
        je 1f
        mov rax, rdi
        ret
1:      ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 48
        .set AC_DICTS, MATCH_BINDINGS_SIZE
        .set AC_MASKS, MATCH_BINDINGS_SIZE + 8
        .set AC_I, MATCH_BINDINGS_SIZE + 16
        .set AC_LOC, MATCH_BINDINGS_SIZE + 24
        mov rbx, rdi
        mov [rsp + AC_DICTS], rsi
        PAT rsi, "('field', 0, ('stor', ('length', ':idx')))"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jnz .Lac_length
        PAT rsi, "('type', 256, ('field', 0, ('stor', ('length', ':idx'))))"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jnz .Lac_length
        PAT rsi, "('type', 256, ('stor', ('length', ':idx')))"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jnz .Lac_length
        PAT rsi, "('type', ':e_type', ('field', ':e_field', ('stor', ('name', ':e_name', ':loc'))))"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 2f
        # every mask of this name must have the same type and field
        mov rax, [rsp + AC_DICTS]
        mov rdi, [rax + 8]
        B rsi, 2
        call od_get
        test rax, rax
        jz 12f
        mov [rsp + AC_MASKS], rax
        mov qword ptr [rsp + AC_I], 0
11:     mov rax, [rsp + AC_MASKS]
        mov rcx, [rsp + AC_I]
        cmp rcx, [rax + VEC_LEN]
        jae 12f
        mov rax, [rax + VEC_DATA]
        mov r12, [rax + rcx*8]          # mask
        inc qword ptr [rsp + AC_I]
        mov rdi, r12
        call get_loc
        mov [rsp + AC_LOC], rax
        mov rdi, rax
        B rsi, 3
        call .Lac_same
        test eax, eax
        jnz 111f
        mov rdi, [rsp + AC_LOC]
        call none_if_nil
        mov r9, rax
        mov edi, LOG_ERROR
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_two_locs]
        mov rcx, r12
        B r8, 3
        call log_fmt
111:    PAT rsi, "('type', ':m_type', ('field', ':m_field', 'Any'))"
        mov rdi, r12
        lea rdx, [rsp + 32]             # (slots 4, 5)
        call pat_match
        test eax, eax
        jz .Lac_assert
        B rdi, 5
        B rsi, 1
        call py_equal
        test eax, eax
        jz .Lac_asis
        B rdi, 4
        B rsi, 0
        call py_equal
        test eax, eax
        jz .Lac_asis
        jmp 11b
12:     # ('stor', ('name', e_name, loc))
        B rsi, 2
        B rdx, 3
        LOADS rdi, NAME
        call mk3
        mov rsi, rax
        LOADS rdi, STOR
        call mk2
        jmp .Lac_ret
2:      PAT rsi, "('type', ':e_type', ':stor')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 3f
        # every mask at this location (but the lengths) must have this type
        B rdi, 1
        call .Lac_masks_at
        test rax, rax
        jz 22f
        mov [rsp + AC_MASKS], rax
        mov qword ptr [rsp + AC_I], 0
21:     mov rax, [rsp + AC_MASKS]
        mov rcx, [rsp + AC_I]
        cmp rcx, [rax + VEC_LEN]
        jae 22f
        mov rax, [rax + VEC_DATA]
        mov r12, [rax + rcx*8]
        inc qword ptr [rsp + AC_I]
        mov rdi, r12
        call .Lac_is_length_mask
        test eax, eax
        jnz 21b
        PAT rsi, "('type', ':m_type', 'Any')"
        mov rdi, r12
        lea rdx, [rsp + 32]
        call pat_match
        test eax, eax
        jz .Lac_assert
        B rdi, 4
        B rsi, 0
        call py_equal
        test eax, eax
        jz .Lac_asis
        jmp 21b
22:     B rax, 1
        jmp .Lac_ret
3:      PAT rsi, "('field', ':e_off', ':stor')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz .Lac_asis
        B rdi, 1
        call .Lac_masks_at
        test rax, rax
        jz 32f
        mov [rsp + AC_MASKS], rax
        mov qword ptr [rsp + AC_I], 0
31:     mov rax, [rsp + AC_MASKS]
        mov rcx, [rsp + AC_I]
        cmp rcx, [rax + VEC_LEN]
        jae 32f
        mov rax, [rax + VEC_DATA]
        mov r12, [rax + rcx*8]
        inc qword ptr [rsp + AC_I]
        mov rdi, r12
        call .Lac_is_length_mask
        test eax, eax
        jnz 31b
        PAT rsi, "('type', 'Any', ('field', ':m_off', 'Any'))"
        mov rdi, r12
        lea rdx, [rsp + 32]
        call pat_match
        test eax, eax
        jz .Lac_assert
        B rdi, 4
        B rsi, 0
        call py_equal
        test eax, eax
        jz .Lac_asis
        jmp 31b
32:     B rax, 1
        jmp .Lac_ret
.Lac_length:
        B rsi, 0
        LOADS rdi, LENGTH
        call mk2
        mov rsi, rax
        LOADS rdi, STOR
        call mk2
        jmp .Lac_ret
.Lac_asis:
        mov rax, rbx
.Lac_ret:
        add rsp, MATCH_BINDINGS_SIZE + 48
        LEAVE
.Lac_assert:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_mask]
        call err_throw
# the masks at the location of the storage reference rdi (0 if none)
.Lac_masks_at:
        sub rsp, 8
        call get_loc
        mov rdi, rax
        call none_if_nil
        mov rsi, rax
        mov rax, [rsp + 8 + 8 + AC_DICTS]
        mov rdi, [rax]
        call od_get
        add rsp, 8
        ret
# eax: rdi ~ ('type', 256, ('field', 0, ('stor', ('length', Any))))
.Lac_is_length_mask:
        sub rsp, 8
        PAT rsi, "('type', 256, ('field', 0, ('stor', ('length', 'Any'))))"
        call pat_match_nobind
        add rsp, 8
        ret
# eax: a get_loc result (0 for None) equals a value (None == None too)
.Lac_same:
        test rdi, rdi
        jnz 1f
        sub rsp, 8
        mov rdi, rsi
        call is_none
        add rsp, 8
        ret
1:      sub rsp, 8
        call py_equal
        add rsp, 8
        ret
ENDF ast_cleanup

# make_ast_folded(contract, folded) -> list: python's contract.make_ast
# of a trace folded already (fold_many, fold_isolated): rewritten for
# display
FUNC make_ast_folded
        ENTER
        mov rbx, rdi
        mov rdi, rsi
        lea rsi, [rip + store_to_set]
        xor edx, edx
        call replace_f
        mov rdi, rax
        lea rsi, [rip + loc_to_name]
        xor edx, edx
        call replace_f
        mov rdi, rax
        lea rsi, [rip + arr_rem_mul]
        mov rdx, rbx
        call replace_f
        mov rdi, rax
        lea rsi, [rip + mask_storage]
        xor edx, edx
        call replace_f
        mov rdi, rax
        lea rsi, [rip + other_1]
        xor edx, edx
        call replace_f
        mov rdi, rax
        lea rsi, [rip + other_2]
        xor edx, edx
        call replace_f
        LEAVE
ENDF make_ast_folded

# store_to_set(line, arg): ('store', size, off, idx, val) -> ('set', ('stor', size, off, idx), val)
FUNC store_to_set
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE
        mov rbx, rdi
        PAT rsi, "('store', ':size', ':off', ':idx', ':val')"
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 1f
        B rsi, 0
        B rdx, 1
        B rcx, 2
        LOADS rdi, STOR
        call mk4
        mov rsi, rax
        B rdx, 3
        LOADS rdi, SET
        call mk3
        add rsp, MATCH_BINDINGS_SIZE
        LEAVE
1:      mov rax, rbx
        add rsp, MATCH_BINDINGS_SIZE
        LEAVE
ENDF store_to_set

# loc_to_name(exp, arg): ('loc', num) -> ('name', "stor<num>", num)
FUNC loc_to_name
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 16
        mov rbx, rdi
        PAT rsi, "('loc', ':num')"
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz .Lln_asis
        call sb_new
        mov r12, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_stor]
        call sb_append_c
        B rdi, 0
        call is_int
        test eax, eax
        jz 2f
        B rdi, 0
        mov rsi, 1000
        TAG rsi
        call int_cmp
        cmp eax, -1
        jne 1f
        mov rdi, r12
        B rsi, 0
        mov edx, 10
        call sb_append_int
        jmp 3f
1:      # hex(num)[2:6].upper()
        call sb_new
        mov r13, rax
        mov rdi, rax
        B rsi, 0
        mov edx, 16
        call sb_append_int
        mov rdi, r13
        call sb_finish
        mov rdi, rax
        mov esi, 2
        mov edx, 6
        call str_slice
        mov rdi, rax
        call str_upper
        mov rdi, r12
        mov rsi, rax
        call sb_append_str
        jmp 3f
2:      # prettify(num, add_color=False, parentheses=True)
        mov rdi, r12
        B rsi, 0
        mov edx, PF_PARENS
        call sb_append_pret
3:      mov rdi, r12
        call sb_finish_intern
        mov rsi, rax
        B rdx, 0
        LOADS rdi, NAME
        call mk3
        add rsp, MATCH_BINDINGS_SIZE + 16
        LEAVE
.Lln_asis:
        mov rax, rbx
        add rsp, MATCH_BINDINGS_SIZE + 16
        LEAVE
ENDF loc_to_name

# arr_rem_mul(exp, contract): the multiplier of an array index that is
# the size of the struct stored there is dropped
FUNC arr_rem_mul
        OPCODE_OF_RDI                   # (('array', ...) only)
        cmp eax, OP_ARRAY
        je 1f
        mov rax, rdi
        ret
1:      ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 32
        .set AR_R, MATCH_BINDINGS_SIZE
        .set AR_LOC, MATCH_BINDINGS_SIZE + 8
        mov rbx, rdi
        mov r12, rsi
        PAT rsi, "('array', ('mask_shl', ':size', ':off', ':int:shl', ':idx'), ':loc')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 2f
        # r = 2 ** shl (a float below zero: never a struct size)
        B rdi, 2
        call int_sign
        cmp eax, -1
        je .Lar_asis
        B rdi, 2
        call int_to_i64
        mov rdi, rax
        call pow2
        mov [rsp + AR_R], rax
        B rdi, 4
        call .Lar_is_struct_array
        test eax, eax
        jz .Lar_asis
        # ('array', ('mask_shl', size, off, 0, idx), loc)
        B rsi, 0
        B rdx, 1
        mov ecx, 1
        B r8, 3
        LOADS rdi, MASK_SHL
        call mk5
        mov rsi, rax
        B rdx, 4
        LOADS rdi, ARRAY
        call mk3
        jmp .Lar_ret
2:      PAT rsi, "('array', ('mul', ':int:r', ':idx'), ':loc')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz .Lar_asis
        mov rax, [rsp]
        mov [rsp + AR_R], rax
        B rdi, 2
        call .Lar_is_struct_array
        test eax, eax
        jz .Lar_asis
        B rsi, 1
        B rdx, 2
        LOADS rdi, ARRAY
        call mk3
        jmp .Lar_ret
.Lar_asis:
        mov rax, rbx
.Lar_ret:
        add rsp, MATCH_BINDINGS_SIZE + 32
        LEAVE
# eax: a ('def', Any, get_loc(rdi), ('array', ('struct', r))) exists
.Lar_is_struct_array:
        sub rsp, 24
        call get_loc
        mov rdi, rax
        call none_if_nil
        mov [rsp], rax                  # e_loc
        mov rsi, [rsp + 24 + 8 + AR_R]
        LOADS rdi, STRUCT
        call mk2
        mov rsi, rax
        LOADS rdi, ARRAY
        call mk2
        mov [rsp + 8], rax              # ('array', ('struct', r))
        mov qword ptr [rsp + 16], 0
1:      mov rax, [r12 + CT_STOR_DEFS]
        mov rcx, [rsp + 16]
        cmp ecx, [rax + N_AUX]
        jae 3f
        mov rdi, [rax + N_DATA + rcx*8]
        inc qword ptr [rsp + 16]
        push rdi
        push rdi
        PAT rsi, "('def', 'Any', ':d_loc', ':d_def')"
        call pat_match_nobind
        pop rdi
        pop rdi
        test eax, eax
        jz .Lar_assert
        push rdi
        push rdi
        mov rdi, [rdi + N_DATA + 16]
        mov rsi, [rsp + 16]
        call py_equal
        pop rdi
        pop rdi
        test eax, eax
        jz 1b
        mov rax, [rdi + N_DATA + 24]
        cmp rax, [rsp + 8]
        jne 1b
        mov eax, 1
        add rsp, 24
        ret
3:      xor eax, eax
        add rsp, 24
        ret
.Lar_assert:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_def]
        call err_throw
ENDF arr_rem_mul

# mask_storage(exp, arg): ('stor', size, off, idx) -> ('type', size, ('field', off, ('stor', idx)))
FUNC mask_storage
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE
        mov rbx, rdi
        PAT rsi, "('stor', ':size', ':off', ':idx')"
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 2f
        B rdi, 1
        call is_int
        test eax, eax
        jz 1f
        B rdi, 1
        call int_sign
        cmp eax, -1
        jne 1f
        mov qword ptr [rsp + 8], 1      # a negative offset is 0
1:      B rsi, 2
        LOADS rdi, STOR
        call mk2
        mov rdx, rax
        B rsi, 1
        LOADS rdi, FIELD
        call mk3
        mov rdx, rax
        B rsi, 0
        LOADS rdi, TYPE
        call mk3
        add rsp, MATCH_BINDINGS_SIZE
        LEAVE
2:      mov rax, rbx
        add rsp, MATCH_BINDINGS_SIZE
        LEAVE
ENDF mask_storage

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
21:     # ('div', ('mask', size + off, 0, e), 2 ** off)
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
3:      PAT rsi, "('mask_shl', 32, 224, 0, ('cd', 0))"
        mov rdi, rbx
        call pat_match_nobind
        test eax, eax
        jz 4f
        LOADS rdi, CD
        mov esi, 1
        call mk2
        jmp .Lo2_ret
4:      PAT rsi, "('mask_shl', 160, 0, 96, ':val')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz .Lo2_asis
        # nasty hack for stuff like 0xF8DFaC6CAe56736FD2a05e45108490C6Cb40147D approve
        B r8, 0
        LOADS rdi, MASK_SHL
        mov esi, 321                    # 160
        mov edx, 1
        mov ecx, 1
        call mk5
        jmp .Lo2_ret
.Lo2_asis:
        mov rax, rbx
.Lo2_ret:
        add rsp, MATCH_BINDINGS_SIZE + 16
        LEAVE
ENDF other_2

        OPSET_MEMBER addresses, OP_ADDRESS
        OPSET_MEMBER addresses, OP_COINBASE
        OPSET_MEMBER addresses, OP_CALLER
        OPSET_MEMBER addresses, OP_ORIGIN
        OPSET_END addresses, OP_COUNT

        .section .note.GNU-stack,"",@progbits
