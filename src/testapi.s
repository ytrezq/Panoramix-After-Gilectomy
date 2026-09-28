# Test entry point: pan_test(name, text, len, &out, &outlen) parses the
# python literal `text`, applies the function called `name` to it and
# renders the result with value_print. The functions take one value
# (a tuple of arguments when there are several) and return a value.

.include "defs.inc"

        .section .data.rel.ro
        .align 8
test_table:
        .quad .Ln_roundtrip, tf_roundtrip
        .quad .Ln_hash, tf_hash
        .quad .Ln_opcode, tf_opcode
        .quad .Ln_eval, arith_eval
        .quad .Ln_is_zero, is_zero
        .quad .Ln_simplify_bool, simplify_bool
        .quad .Ln_eval_bool, tf_eval_bool
        .quad .Ln_to_real_int, to_real_int
        .quad .Ln_add_op, tf_add_op
        .quad .Ln_mul_op, tf_mul_op
        .quad .Ln_sub_op, tf_2args_sub
        .quad .Ln_or_op, tf_or_op
        .quad .Ln_mask_op, tf_mask_op
        .quad .Ln_div_op, tf_div_op
        .quad .Ln_neg_mask_op, tf_neg_mask_op
        .quad .Ln_simplify, alg_simplify
        .quad .Ln_calc_max, alg_calc_max
        .quad .Ln_max_to_add, alg_max_to_add
        .quad .Ln_lt_op, tf_lt_op
        .quad .Ln_le_op, tf_le_op
        .quad .Ln_ge_zero, tf_ge_zero
        .quad .Ln_max_op, tf_max_op
        .quad .Ln_min_op, tf_min_op
        .quad .Ln_get_sign, tf_get_sign
        .quad .Ln_to_exp2, tf_to_exp2
        .quad .Ln_to_mask, tf_to_mask
        .quad .Ln_to_neg_mask, tf_to_neg_mask
        .quad .Ln_stack_simplify, stack_simplify
        .quad .Ln_stack_cleanup, tf_stack_cleanup
        .quad .Ln_fold_stacks, tf_fold_stacks
        .quad .Ln_vm_run, tf_vm_run
        .quad .Ln_find_functions, tf_find_functions
        .quad .Ln_whiles_make, tf_whiles_make
        .quad .Ln_match, tf_match
        .quad .Ln_to_bytes, tf_to_bytes
        .quad .Ln_divisible_bytes, tf_divisible_bytes
        .quad .Ln_find_mask, tf_find_mask
        .quad .Ln_apply_mask_to_range, tf_apply_mask_to_range
        .quad .Ln_split_or, split_or
        .quad .Ln_sizeof, sizeof
        .quad .Ln_split_setmem, tf_split_setmem
        .quad .Ln_split_store, tf_split_store
        .quad .Ln_memloc_overwrite, tf_2args_memloc_overwrite
        .quad .Ln_slice_exp, tf_slice_exp
        .quad .Ln_splits_mem, tf_splits_mem
        .quad .Ln_fill_mem, tf_fill_mem
        .quad .Ln_range_overlaps, tf_range_overlaps
        .quad .Ln_range_contains, tf_range_contains
        .quad .Ln_simplify_exp, simplify_exp
        .quad .Ln_simplify_mask, simplify_mask
        .quad .Ln_cleanup_mask_data, cleanup_mask_data
        .quad .Ln_canonise_max, canonise_max
        .quad .Ln_sizeof_s, tf_sizeof_s
        .quad .Ln_cleanup_conds, cleanup_conds
        .quad .Ln_cleanup_msize, cleanup_msize
        .quad .Ln_cleanup_mems, tf_cleanup_mems
        .quad .Ln_cleanup_vars, tf_cleanup_vars
        .quad .Ln_cleanup_vars_req, tf_cleanup_vars_req
        .quad .Ln_replace_var, tf_replace_var
        .quad .Ln_replace_mem, tf_replace_mem
        .quad .Ln_parse_counters, tf_parse_counters
        .quad .Ln_loop_to_setmem, tf_loop_to_setmem
        .quad .Ln_propagate_storage_in_loops, propagate_storage_in_loops
        .quad .Ln_readability, readability
        .quad .Ln_replace_bytes_or_string_length, replace_bytes_or_string_length
        .quad .Ln_postprocess_exp, tf_postprocess_exp
        .quad .Ln_postprocess_trace, tf_postprocess_trace
        .quad .Ln_rewrite_string_stores, tf_rewrite_string_stores
        .quad .Ln_pp_cleanup_mul_1, pp_cleanup_mul_1
        .quad .Ln_simplify_trace, tf_simplify_trace
        .quad .Ln_make_whiles, tf_make_whiles
        .quad .Ln_while_max_memidx, while_max_memidx
        .quad .Ln_extract_setmems, extract_setmems
        .quad .Ln_extract_paths, extract_paths
        .quad .Ln_while_touches_mem, tf_while_touches_mem
        .quad .Ln_while_uses_mem, tf_while_uses_mem
        .quad .Ln_exp_uses_mem, tf_exp_uses_mem
        .quad .Ln_affects, tf_affects
        .quad .Ln_overwrites_mem, tf_overwrites_mem
        .quad .Ln_mem_use, tf_mem_use
        .quad .Ln_trace_ends_execution, tf_trace_ends_execution
        .quad .Ln_normalize, tf_normalize
        .quad .Ln_find_mems, find_mems
        .quad .Ln_split_setmem_trace, tf_split_setmem_trace
        .quad .Ln_split_store_trace, tf_split_store_trace
        .quad .Ln_fold, fold
        .quad .Ln_as_paths, as_paths
        .quad .Ln_fold_paths, fold_paths
        .quad .Ln_fold_aux, fold_aux
        .quad .Ln_prettify, tf_prettify
        .quad .Ln_pretty_stor, tf_pretty_stor
        .quad .Ln_pretty_type, pretty_type
        .quad .Ln_pretty_memory, tf_pretty_memory
        .quad .Ln_pretty_num, tf_pretty_num
        .quad .Ln_pretty_fname, tf_pretty_fname
        .quad .Ln_pretty_bignum, tf_pretty_bignum
        .quad .Ln_mask_to_type, tf_mask_to_type
        .quad .Ln_padded_hex, tf_padded_hex
        .quad .Ln_clean_color, clean_color
        .quad 0, 0

        .section .rodata
.Ln_roundtrip: .asciz "roundtrip"
.Ln_hash:      .asciz "hash"
.Ln_opcode:    .asciz "opcode"
.Ln_eval:      .asciz "eval"
.Ln_is_zero:   .asciz "is_zero"
.Ln_simplify_bool: .asciz "simplify_bool"
.Ln_eval_bool: .asciz "eval_bool"
.Ln_to_real_int: .asciz "to_real_int"
.Ln_add_op:    .asciz "add_op"
.Ln_mul_op:    .asciz "mul_op"
.Ln_sub_op:    .asciz "sub_op"
.Ln_or_op:     .asciz "or_op"
.Ln_mask_op:   .asciz "mask_op"
.Ln_div_op:    .asciz "div_op"
.Ln_neg_mask_op: .asciz "neg_mask_op"
.Ln_simplify:  .asciz "simplify"
.Ln_calc_max:  .asciz "calc_max"
.Ln_max_to_add: .asciz "max_to_add"
.Ln_lt_op:     .asciz "lt_op"
.Ln_le_op:     .asciz "le_op"
.Ln_ge_zero:   .asciz "ge_zero"
.Ln_max_op:    .asciz "max_op"
.Ln_min_op:    .asciz "min_op"
.Ln_get_sign:  .asciz "get_sign"
.Ln_to_exp2:   .asciz "to_exp2"
.Ln_to_mask:   .asciz "to_mask"
.Ln_to_neg_mask: .asciz "to_neg_mask"
.Ln_stack_simplify: .asciz "stack_simplify"
.Ln_stack_cleanup: .asciz "stack_cleanup"
.Ln_fold_stacks: .asciz "fold_stacks"
.Ln_vm_run:    .asciz "vm_run"
.Ln_find_functions: .asciz "find_functions"
.Ln_whiles_make: .asciz "whiles_make"
.Ln_match:     .asciz "match"
.Ln_to_bytes:  .asciz "to_bytes"
.Ln_divisible_bytes: .asciz "divisible_bytes"
.Ln_find_mask: .asciz "find_mask"
.Ln_apply_mask_to_range: .asciz "apply_mask_to_range"
.Ln_split_or:  .asciz "split_or"
.Ln_sizeof:    .asciz "sizeof"
.Ln_split_setmem: .asciz "split_setmem"
.Ln_split_store: .asciz "split_store"
.Ln_memloc_overwrite: .asciz "memloc_overwrite"
.Ln_slice_exp: .asciz "slice_exp"
.Ln_splits_mem: .asciz "splits_mem"
.Ln_fill_mem:  .asciz "fill_mem"
.Ln_range_overlaps: .asciz "range_overlaps"
.Ln_range_contains: .asciz "range_contains"
.Ln_simplify_exp: .asciz "simplify_exp"
.Ln_simplify_mask: .asciz "simplify_mask"
.Ln_cleanup_mask_data: .asciz "cleanup_mask_data"
.Ln_canonise_max: .asciz "canonise_max"
.Ln_sizeof_s:  .asciz "sizeof_s"
.Ln_cleanup_conds: .asciz "cleanup_conds"
.Ln_cleanup_msize: .asciz "cleanup_msize"
.Ln_cleanup_mems: .asciz "cleanup_mems"
.Ln_cleanup_vars: .asciz "cleanup_vars"
.Ln_cleanup_vars_req: .asciz "cleanup_vars_req"
.Ln_replace_var: .asciz "replace_var"
.Ln_replace_mem: .asciz "replace_mem"
.Ln_parse_counters: .asciz "parse_counters"
.Ln_loop_to_setmem: .asciz "loop_to_setmem"
.Ln_propagate_storage_in_loops: .asciz "propagate_storage_in_loops"
.Ln_readability: .asciz "readability"
.Ln_replace_bytes_or_string_length: .asciz "replace_bytes_or_string_length"
.Ln_postprocess_exp: .asciz "postprocess_exp"
.Ln_postprocess_trace: .asciz "postprocess_trace"
.Ln_rewrite_string_stores: .asciz "rewrite_string_stores"
.Ln_pp_cleanup_mul_1: .asciz "pp_cleanup_mul_1"
.Ln_simplify_trace: .asciz "simplify_trace"
.Ln_make_whiles: .asciz "make_whiles"
.Ln_while_max_memidx: .asciz "while_max_memidx"
.Ln_extract_setmems: .asciz "extract_setmems"
.Ln_extract_paths: .asciz "extract_paths"
.Ln_while_touches_mem: .asciz "while_touches_mem"
.Ln_while_uses_mem: .asciz "while_uses_mem"
.Ln_exp_uses_mem: .asciz "exp_uses_mem"
.Ln_affects: .asciz "affects"
.Ln_overwrites_mem: .asciz "overwrites_mem"
.Ln_mem_use: .asciz "mem_use"
.Ln_trace_ends_execution: .asciz "trace_ends_execution"
.Ln_normalize: .asciz "normalize"
.Ln_fold: .asciz "fold"
.Ln_as_paths: .asciz "as_paths"
.Ln_fold_paths: .asciz "fold_paths"
.Ln_fold_aux: .asciz "fold_aux"
.Ln_prettify: .asciz "prettify"
.Ln_pretty_stor: .asciz "pretty_stor"
.Ln_pretty_type: .asciz "pretty_type"
.Ln_pretty_memory: .asciz "pretty_memory"
.Ln_pretty_num: .asciz "pretty_num"
.Ln_pretty_fname: .asciz "pretty_fname"
.Ln_pretty_bignum: .asciz "pretty_bignum"
.Ln_mask_to_type: .asciz "mask_to_type"
.Ln_padded_hex: .asciz "padded_hex"
.Ln_clean_color: .asciz "clean_color"
.Ln_find_mems: .asciz "find_mems"
.Ln_split_setmem_trace: .asciz "split_setmem_trace"
.Ln_split_store_trace: .asciz "split_store_trace"
.Ls_unknown_fn: .asciz "<unknown test function>"
.Ls_parse_err:  .asciz "<parse error at %u>"

        .text

FUNC tf_roundtrip
        mov rax, rdi
        ret
ENDF tf_roundtrip

# hash(v) -> the value's hash, as an integer
FUNC tf_hash
        ENTER
        call value_hash
        mov rdi, rax
        call mk_int_u64
        LEAVE
ENDF tf_hash

# opcode(v) -> the opcode id of a tuple
FUNC tf_opcode
        ENTER
        call opcode_of
        mov edi, eax
        call mk_int_u64
        LEAVE
ENDF tf_opcode

# eval_bool((exp, known_true, symbolic)) -> True/False/None
FUNC tf_eval_bool
        ENTER
        mov rbx, rdi
        mov rdi, [rbx + N_DATA]
        mov rsi, [rbx + N_DATA + 8]
        mov rdx, [rbx + N_DATA + 16]
        sar rdx, 1
        call eval_bool
        lea rcx, [rip + sp_none]
        lea rdx, [rip + sp_true]
        cmp eax, TRI_TRUE
        cmove rcx, rdx
        lea rdx, [rip + sp_false]
        cmp eax, TRI_FALSE
        cmove rcx, rdx
        mov rax, rcx
        LEAVE
ENDF tf_eval_bool

# variadic ones take the tuple of arguments
FUNC tf_add_op
        mov esi, [rdi + N_AUX]
        add rdi, N_DATA
        xchg rdi, rsi
        jmp alg_add_n
ENDF tf_add_op

FUNC tf_mul_op
        mov esi, [rdi + N_AUX]
        add rdi, N_DATA
        xchg rdi, rsi
        jmp alg_mul_n
ENDF tf_mul_op

FUNC tf_or_op
        mov esi, [rdi + N_AUX]
        add rdi, N_DATA
        xchg rdi, rsi
        jmp alg_or_n
ENDF tf_or_op

FUNC tf_2args_sub
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        jmp alg_sub_op
ENDF tf_2args_sub

FUNC tf_div_op
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        jmp alg_div_op
ENDF tf_div_op

# mask_op((exp, size, offset, shl, shr))
FUNC tf_mask_op
        mov r8, [rdi + N_DATA + 32]
        mov rcx, [rdi + N_DATA + 24]
        mov rdx, [rdi + N_DATA + 16]
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        jmp alg_mask_op
ENDF tf_mask_op

FUNC tf_neg_mask_op
        mov rdx, [rdi + N_DATA + 16]
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        jmp alg_neg_mask_op
ENDF tf_neg_mask_op

# tri_value(eax) -> rax: True/False/None/'CannotCompare'
FUNC tri_value
        ENTER
        mov ebx, edi
        lea rax, [rip + sp_true]
        cmp ebx, TRI_TRUE
        je 1f
        lea rax, [rip + sp_false]
        cmp ebx, TRI_FALSE
        je 1f
        lea rax, [rip + sp_none]
        cmp ebx, TRI_NONE
        je 1f
        lea rdi, [rip + .Ls_cannot]
        call str_intern_c
1:      LEAVE
ENDF tri_value

        .section .rodata
.Ls_cannot: .asciz "CannotCompare"
        .text

FUNC tf_lt_op
        ENTER
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        call alg_lt_op
        mov edi, eax
        call tri_value
        LEAVE
ENDF tf_lt_op

FUNC tf_le_op
        ENTER
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        call alg_le_op
        mov edi, eax
        call tri_value
        LEAVE
ENDF tf_le_op

FUNC tf_ge_zero
        ENTER
        call alg_ge_zero
        mov edi, eax
        call tri_value
        LEAVE
ENDF tf_ge_zero

FUNC tf_get_sign
        ENTER
        call alg_get_sign
        cmp eax, TRI_CANNOT
        je 1f
        cmp eax, SIGN_NONE
        je 2f
        movsxd rdi, eax
        call mk_int_i64
        LEAVE
1:      mov edi, TRI_CANNOT
        call tri_value
        LEAVE
2:      lea rax, [rip + sp_none]
        LEAVE
ENDF tf_get_sign

# max_op / min_op -> value or 'CannotCompare'
FUNC tf_max_op
        ENTER
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        call alg_max_op
        test rax, rax
        jnz 1f
        mov edi, TRI_CANNOT
        call tri_value
1:      LEAVE
ENDF tf_max_op

FUNC tf_min_op
        ENTER
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        call alg_min_op
        test rax, rax
        jnz 1f
        mov edi, TRI_CANNOT
        call tri_value
1:      LEAVE
ENDF tf_min_op

FUNC tf_to_exp2
        ENTER
        call to_exp2
        cmp rax, -1
        je 1f
        mov rdi, rax
        call mk_int_i64
        LEAVE
1:      lea rax, [rip + sp_none]
        LEAVE
ENDF tf_to_exp2

# to_mask(v) / to_neg_mask(v) -> (size, offset) or None
FUNC tf_to_mask
        ENTER
        call to_mask
        jmp tf_pair_or_none
ENDF tf_to_mask

FUNC tf_to_neg_mask
        ENTER
        call to_neg_mask
        jmp tf_pair_or_none
ENDF tf_to_neg_mask

# (entered with the frame of the caller above)
FUNC tf_pair_or_none
        test rax, rax
        jz 1f
        mov rdi, rax
        mov rsi, rdx
        call mk2
        LEAVE
1:      lea rax, [rip + sp_none]
        LEAVE
ENDF tf_pair_or_none

# stack_cleanup(elements) -> the cleaned up stack, as a tuple
FUNC tf_stack_cleanup
        ENTER
        mov rbx, rdi
        call vec_new
        mov r12, rax
        mov rdi, rax
        mov rsi, rbx
        call vec_extend_seq
        mov rdi, r12
        call stack_cleanup
        mov rdi, r12
        call vec_to_tuple
        LEAVE
ENDF tf_stack_cleanup

# fold_stacks((first, second, depth)) -> (folded, vars)
FUNC tf_fold_stacks
        ENTER
        sub rsp, 16
        mov rdx, [rdi + N_DATA + 16]
        sar rdx, 1
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        mov rcx, rsp
        call fold_stacks
        mov rdi, rax
        mov rsi, [rsp]
        call mk2
        add rsp, 16
        LEAVE
ENDF tf_fold_stacks

# vm_run((hexcode, start, just_fdests, stack, known)) -> the trace
FUNC tf_vm_run
        ENTER
        sub rsp, 80                     # loader, result, the error handler
        mov rbx, rdi
        mov r12, [rbx + N_DATA]         # the code, as a hex string
        mov edi, [r12 + N_DATA]
        shr edi, 1
        inc rdi
        call malloc@PLT
        mov r13, rax
        lea rdi, [r12 + N_DATA + 4]
        mov esi, [r12 + N_DATA]
        mov rdx, r13
        call hex_decode
        mov r14, rax
        call loader_new
        mov [rsp], rax
        mov rdi, rax
        mov rsi, r13
        mov rdx, r14
        call loader_load
        mov rdi, r13
        call free@PLT
        mov rdi, [rsp]
        mov rsi, [rbx + N_DATA + 16]
        sar rsi, 1
        call vm_new
        lea rdi, [rsp + 16]
        call err_catch
        test eax, eax
        jnz 1f
        mov rdi, [rbx + N_DATA + 8]     # start
        mov rsi, [rbx + N_DATA + 24]    # stack
        mov rdx, [rbx + N_DATA + 32]    # known
        xor ecx, ecx
        call vm_run
        mov [rsp + 8], rax
        call err_end
2:      mov rdi, [rsp]
        call loader_free
        mov rax, [rsp + 8]
        add rsp, 80
        LEAVE
1:      # an error: '<exc message>'
        call tf_exc_value
        mov [rsp + 8], rax
        jmp 2b
ENDF tf_vm_run

# find_functions(hexcode) -> (functions, fallback_known)
FUNC tf_find_functions
        ENTER
        sub rsp, 80
        mov r12, rdi                    # the code, as a hex string
        mov edi, [r12 + N_DATA]
        shr edi, 1
        inc rdi
        call malloc@PLT
        mov r13, rax
        lea rdi, [r12 + N_DATA + 4]
        mov esi, [r12 + N_DATA]
        mov rdx, r13
        call hex_decode
        mov r14, rax
        call loader_new
        mov rbx, rax
        mov rdi, rax
        mov rsi, r13
        mov rdx, r14
        call loader_load
        mov rdi, r13
        call free@PLT
        lea rdi, [rsp + 16]
        call err_catch
        test eax, eax
        jnz 1f
        mov rdi, rbx
        mov rsi, 60000000000            # 60 s
        call loader_find_functions
        call err_end
        mov rdi, [rbx + LD_FUNCS]
        mov rsi, [rbx + LD_FALLBACK_KNOWN]
        call mk2
        mov [rsp + 8], rax
2:      mov rdi, rbx
        call loader_free
        mov rax, [rsp + 8]
        add rsp, 80
        LEAVE
1:      call tf_exc_value
        mov [rsp + 8], rax
        jmp 2b
ENDF tf_find_functions

# whiles_make(trace) -> list, or the error
FUNC tf_whiles_make
        ENTER
        sub rsp, 80
        mov rbx, rdi
        lea rdi, [rsp + 16]
        call err_catch
        test eax, eax
        jnz 1f
        mov rdi, rbx
        call whiles_make
        mov [rsp + 8], rax
        call err_end
2:      mov rax, [rsp + 8]
        add rsp, 80
        LEAVE
1:      call tf_exc_value
        mov [rsp + 8], rax
        jmp 2b
ENDF tf_whiles_make

# match((exp, pattern)) -> the list of bindings, or None
FUNC tf_match
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE
        mov rbx, rdi
        mov rdi, [rbx + N_DATA]
        mov rsi, [rbx + N_DATA + 8]
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 1f
        # how many: count the wildcards of the pattern (the names differ)
        mov rdi, [rbx + N_DATA + 8]
        call count_wildcards
        mov rdi, rax
        mov rsi, rsp
        call mk_list
        add rsp, MATCH_BINDINGS_SIZE
        LEAVE
1:      lea rax, [rip + sp_none]
        add rsp, MATCH_BINDINGS_SIZE
        LEAVE
ENDF tf_match

# count_wildcards(pattern) -> rax: the distinct named wildcards
FUNC count_wildcards
        ENTER
        sub rsp, MATCH_NAMES_SIZE + 16
        mov rbx, rdi
        mov qword ptr [rsp], 0
        mov rdi, rbx
        mov rsi, rsp
        call collect_wildcards
        mov rax, [rsp]
        add rsp, MATCH_NAMES_SIZE + 16
        LEAVE
ENDF count_wildcards

FUNC collect_wildcards
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call is_str
        test eax, eax
        jz 2f
        cmp rbx, [rip + s_any]
        je 5f
        cmp byte ptr [rbx + N_DATA + 4], ':'
        jne 5f
        lea rdi, [rbx + N_DATA + 5]
        call wildcard_name
        mov r13, rax
        xor ecx, ecx
1:      cmp rcx, [r12]
        jae 3f
        push rcx
        push rcx
        mov rdi, [r12 + 8 + rcx*8]
        mov rsi, r13
        call strcmp@PLT
        pop rcx
        pop rcx
        test eax, eax
        jz 5f
        inc rcx
        jmp 1b
3:      mov [r12 + 8 + rcx*8], r13
        inc qword ptr [r12]
        jmp 5f
2:      mov rdi, rbx
        call is_seq
        test eax, eax
        jz 5f
        xor r13d, r13d
4:      cmp r13d, [rbx + N_AUX]
        jae 5f
        mov rdi, [rbx + N_DATA + r13*8]
        mov rsi, r12
        call collect_wildcards
        inc r13
        jmp 4b
5:      LEAVE
ENDF collect_wildcards

# the memloc functions
FUNC tf_to_bytes
        ENTER
        call to_bytes
        mov rdi, rax
        mov rsi, rdx
        call mk2
        LEAVE
ENDF tf_to_bytes

FUNC tf_divisible_bytes
        ENTER
        call divisible_bytes
        mov edi, eax
        call tri_value
        LEAVE
ENDF tf_divisible_bytes

FUNC tf_find_mask
        ENTER
        call find_mask
        mov rdi, rax
        mov rsi, rdx
        call mk2
        LEAVE
ENDF tf_find_mask

FUNC tf_apply_mask_to_range
        mov rdx, [rdi + N_DATA + 16]
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        jmp apply_mask_to_range
ENDF tf_apply_mask_to_range

# the rewrite callbacks: (line) -> the list of lines
FUNC tf_split_setmem
        ENTER
        mov rbx, rdi
        call vec_new
        mov r12, rax
        mov rdi, rbx
        xor esi, esi
        mov rdx, r12
        call split_setmem
        mov rdi, r12
        call vec_to_list
        LEAVE
ENDF tf_split_setmem

FUNC tf_split_store
        ENTER
        mov rbx, rdi
        call vec_new
        mov r12, rax
        mov rdi, rbx
        xor esi, esi
        mov rdx, r12
        call split_store
        mov rdi, r12
        call vec_to_list
        LEAVE
ENDF tf_split_store

FUNC tf_2args_memloc_overwrite
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        jmp memloc_overwrite
ENDF tf_2args_memloc_overwrite

FUNC tf_slice_exp
        ENTER
        mov rdx, [rdi + N_DATA + 16]
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        call slice_exp
        mov rdi, rax
        call none_if_nil
        LEAVE
ENDF tf_slice_exp

# splits_mem((memloc, split, memval, split_val or None))
FUNC tf_splits_mem
        ENTER
        mov rbx, rdi
        mov rcx, [rbx + N_DATA + 24]
        lea rax, [rip + sp_none]
        cmp rcx, rax
        jne 1f
        xor ecx, ecx
1:      mov rdx, [rbx + N_DATA + 16]
        mov rsi, [rbx + N_DATA + 8]
        mov rdi, [rbx + N_DATA]
        call splits_mem
        LEAVE
ENDF tf_splits_mem

FUNC tf_fill_mem
        mov rdx, [rdi + N_DATA + 16]
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        jmp fill_mem
ENDF tf_fill_mem

FUNC tf_range_overlaps
        ENTER
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        call range_overlaps
        mov edi, eax
        call tri_value
        LEAVE
ENDF tf_range_overlaps

FUNC tf_range_contains
        ENTER
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        call range_contains
        mov edi, eax
        call tri_value
        LEAVE
ENDF tf_range_contains

FUNC tf_sizeof_s
        ENTER
        call sizeof_s
        mov rdi, rax
        call none_if_nil
        LEAVE
ENDF tf_sizeof_s

# the simplifier passes
FUNC tf_cleanup_mems
        xor esi, esi
        jmp cleanup_mems
ENDF tf_cleanup_mems

FUNC tf_cleanup_vars
        xor esi, esi
        jmp cleanup_vars
ENDF tf_cleanup_vars

FUNC tf_cleanup_vars_req
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        jmp cleanup_vars
ENDF tf_cleanup_vars_req

FUNC tf_replace_var
        mov rdx, [rdi + N_DATA + 16]
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        jmp replace_var
ENDF tf_replace_var

FUNC tf_replace_mem
        mov rdx, [rdi + N_DATA + 16]
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        jmp replace_mem
ENDF tf_replace_mem

# parse_counters(line) -> (setvars, jds, stepvars, counter, start, stop, step, num_loops, endvars), None for absent
FUNC tf_parse_counters
        ENTER
        sub rsp, 80
        call parse_counters
        mov rbx, rax
        xor r12d, r12d
1:      cmp r12d, 9
        jae 2f
        mov rdi, [rbx + r12*8]
        call none_if_nil
        mov [rsp + r12*8], rax
        inc r12d
        jmp 1b
2:      mov edi, 9
        mov rsi, rsp
        call mk_tuple
        add rsp, 80
        LEAVE
ENDF tf_parse_counters

FUNC tf_loop_to_setmem
        ENTER
        mov rbx, rdi
        call vec_new
        mov r12, rax
        mov rdi, rbx
        xor esi, esi
        mov rdx, r12
        call loop_to_setmem
        mov rdi, r12
        call vec_to_list
        LEAVE
ENDF tf_loop_to_setmem

FUNC tf_postprocess_exp
        xor esi, esi
        jmp postprocess_exp
ENDF tf_postprocess_exp

FUNC tf_postprocess_trace
        ENTER
        mov rbx, rdi
        call vec_new
        mov r12, rax
        mov rdi, rbx
        xor esi, esi
        mov rdx, r12
        call postprocess_trace
        mov rdi, r12
        call vec_to_list
        LEAVE
ENDF tf_postprocess_trace

FUNC tf_rewrite_string_stores
        ENTER
        mov rbx, rdi
        xor edi, edi
        xor esi, esi
        call mk_list
        mov rdi, rbx
        mov rsi, rax
        call rewrite_string_stores
        LEAVE
ENDF tf_rewrite_string_stores

# (exp, flags) -> str
FUNC tf_prettify
        mov rsi, [rdi + N_DATA + 8]
        UNTAG rsi
        mov rdi, [rdi + N_DATA]
        jmp prettify
ENDF tf_prettify

FUNC tf_pretty_stor
        mov rsi, [rdi + N_DATA + 8]
        UNTAG rsi
        mov rdi, [rdi + N_DATA]
        jmp pretty_stor
ENDF tf_pretty_stor

FUNC tf_pretty_memory
        mov rsi, [rdi + N_DATA + 8]
        UNTAG rsi
        mov rdi, [rdi + N_DATA]
        jmp pretty_memory
ENDF tf_pretty_memory

FUNC tf_pretty_num
        mov rsi, [rdi + N_DATA + 8]
        UNTAG rsi
        mov rdi, [rdi + N_DATA]
        jmp pretty_num
ENDF tf_pretty_num

# (v, flags, force)
FUNC tf_pretty_fname
        mov rsi, [rdi + N_DATA + 8]
        UNTAG rsi
        mov rdx, [rdi + N_DATA + 16]
        UNTAG rdx
        mov rdi, [rdi + N_DATA]
        jmp pretty_fname
ENDF tf_pretty_fname

# (num, force)
FUNC tf_mask_to_type
        mov rsi, [rdi + N_DATA + 8]
        UNTAG rsi
        mov rdi, [rdi + N_DATA]
        jmp mask_to_type
ENDF tf_mask_to_type

# (v, n)
FUNC tf_padded_hex
        mov rsi, [rdi + N_DATA + 8]
        UNTAG rsi
        mov rdi, [rdi + N_DATA]
        jmp padded_hex
ENDF tf_padded_hex

# pretty_bignum(v): the number itself when it isn't a string (python)
FUNC tf_pretty_bignum
        ENTER
        mov rbx, rdi
        call pretty_bignum_int
        test rax, rax
        jnz 1f
        mov rax, rbx
1:      LEAVE
ENDF tf_pretty_bignum

FUNC tf_simplify_trace
        xor esi, esi
        jmp simplify_trace
ENDF tf_simplify_trace

FUNC tf_make_whiles
        xor esi, esi
        jmp make_whiles
ENDF tf_make_whiles

FUNC tf_while_touches_mem
        ENTER
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        call while_touches_mem
        mov edi, eax
        call tri_value
        LEAVE
ENDF tf_while_touches_mem

FUNC tf_while_uses_mem
        ENTER
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        call while_uses_mem
        mov edi, eax
        call tri_value
        LEAVE
ENDF tf_while_uses_mem

FUNC tf_exp_uses_mem
        ENTER
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        call exp_uses_mem
        mov edi, eax
        call tri_value
        LEAVE
ENDF tf_exp_uses_mem

FUNC tf_affects
        ENTER
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        call affects
        mov edi, eax
        call tri_value
        LEAVE
ENDF tf_affects

FUNC tf_overwrites_mem
        ENTER
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        call overwrites_mem
        mov edi, eax
        call tri_value
        LEAVE
ENDF tf_overwrites_mem

# mem_use((trace, idx)) -> 'used' / 'overwritten' / 'neither'
FUNC tf_mem_use
        ENTER
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        call mem_use
        lea rdi, [rip + .Ls_used]
        cmp eax, 1
        je 1f
        lea rdi, [rip + .Ls_overwritten]
        cmp eax, 2
        je 1f
        lea rdi, [rip + .Ls_neither]
1:      call str_intern_c
        LEAVE
ENDF tf_mem_use

        .section .rodata
.Ls_used: .asciz "used"
.Ls_overwritten: .asciz "overwritten"
.Ls_neither: .asciz "neither"
        .text

FUNC tf_trace_ends_execution
        ENTER
        call trace_ends_execution
        mov edi, eax
        call tri_value
        LEAVE
ENDF tf_trace_ends_execution

FUNC tf_normalize
        ENTER
        call normalize
        mov rdi, rax
        call none_if_nil
        LEAVE
ENDF tf_normalize

FUNC tf_split_setmem_trace
        lea rsi, [rip + split_setmem]
        xor edx, edx
        jmp rewrite_trace
ENDF tf_split_setmem_trace

FUNC tf_split_store_trace
        lea rsi, [rip + split_store]
        xor edx, edx
        jmp rewrite_trace_full
ENDF tf_split_store_trace

# tf_exc_value() -> the string '<exc code: message>' for the error thrown
FUNC tf_exc_value
        ENTER
        call sb_new
        mov rbx, rax
        mov rdi, rbx
        lea rsi, [rip + .Ls_exc_fmt]
        lea rdx, [r15 + CTX_ERR_CODE]   # code, message: consecutive in the context
        call sb_format
        mov rdi, [rbx + SB_BUF]
        mov rsi, [rbx + SB_LEN]
        call str_intern
        mov r12, rax
        mov rdi, rbx
        call sb_free
        mov rax, r12
        LEAVE
ENDF tf_exc_value

        .section .rodata
.Ls_exc_fmt: .asciz "<exc %d: %s>"
        .text

# pan_test(name, text, len, &out, &outlen) -> int
FUNC pan_test
        push r15
        ENTER
        sub rsp, 120                    # 48 of locals + the error handler
        mov [rsp], rdi                  # name
        mov [rsp + 8], rsi              # text
        mov [rsp + 16], rdx             # len
        mov [rsp + 24], rcx             # &out
        mov [rsp + 32], r8              # &outlen
        call pan_init
        call ctx_current
        mov [rsp + 40], rax
        call ctx_new
        mov r15, rax
        mov rdi, r15
        call ctx_bind
        call sb_new
        mov rbx, rax                    # output builder
        # find the function
        lea r12, [rip + test_table]
1:      mov rdi, [r12]
        test rdi, rdi
        jz .Lt_unknown
        mov rsi, [rsp]
        call strcmp@PLT
        test eax, eax
        jz 2f
        add r12, 16
        jmp 1b
2:      mov r13, [r12 + 8]              # the function
        mov rdi, [rsp + 8]
        mov rsi, [rsp + 16]
        call parse_literal
        test rax, rax
        jz .Lt_parse_err
        mov r14, rax
        lea rdi, [rsp + 48]
        call err_catch
        test eax, eax
        jnz 3f
        mov rdi, r14
        call r13
        mov r14, rax
        call err_end
        mov rdi, rbx
        mov rsi, r14
        call value_print
        jmp .Lt_out
3:      call tf_exc_value
        mov rdi, rbx
        mov rsi, rax
        call value_print
        jmp .Lt_out
.Lt_unknown:
        mov rdi, rbx
        lea rsi, [rip + .Ls_unknown_fn]
        call sb_append_c
        jmp .Lt_out
.Lt_parse_err:
        mov rdi, rbx
        lea rsi, [rip + .Ls_parse_err]
        lea rdx, [rip + parse_error_pos]
        call sb_format
.Lt_out:
        mov rax, [rsp + 24]
        mov rcx, [rbx + SB_BUF]
        mov [rax], rcx
        mov rax, [rsp + 32]
        mov rcx, [rbx + SB_LEN]
        mov [rax], rcx
        mov rdi, rbx
        call free@PLT
        mov rdi, r15
        call ctx_free
        mov rdi, [rsp + 40]
        call ctx_bind
        xor eax, eax
        add rsp, 120
        LEAVE_NORET
        pop r15
        ret
ENDF pan_test

        .section .note.GNU-stack,"",@progbits
