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
        .quad .Ln_str_flags, tf_str_flags
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
        .quad .Ln_ge_zero_many, tf_ge_zero_many
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
        .quad .Ln_match_compiled, tf_match_compiled
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
        .quad .Ln_simplify_trace_deadline, tf_simplify_trace_deadline
        .quad .Ln_make_whiles, tf_make_whiles
        .quad .Ln_while_max_memidx, while_max_memidx
        .quad .Ln_extract_setmems, extract_setmems
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
        .quad .Ln_simplify_exps, tf_simplify_exps
        .quad .Ln_loop_to_setmem_trace, tf_loop_to_setmem_trace
        .quad .Ln_heuristics, tf_heuristics
        .quad .Ln_fix_storages_trace, tf_fix_storages_trace
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
        .quad .Ln_pretty_line, tf_pretty_line
        .quad .Ln_pprint_logic, tf_pprint_logic
        .quad .Ln_function, tf_function
        .quad .Ln_contract, tf_contract
        .quad .Ln_json_value, tf_json_value
        .quad .Ln_dump_version, tf_dump_version
        .quad .Ln_keccak, tf_keccak
        .quad .Ln_runtrace, tf_runtrace
        .quad .Ln_keccak_word, rt_keccak_word
        .quad .Ln_ranges, tf_ranges
        .quad .Ln_shr_op, tf_shr_op
        .quad .Ln_shl_op, tf_shl_op
        .quad .Ln_signextend_op, tf_signextend_op
        .quad .Ln_bits, alg_bits
        .quad .Ln_is_bool, tf_is_bool
        .quad .Ln_value_bits, value_bits
        .quad .Ln_max_value_bits, tf_max_value_bits
        .quad .Ln_max_value, max_value
        .quad .Ln_low_zero_bits, low_zero_bits
        .quad .Ln_width_of, tf_width_of
        .quad .Ln_sized, tf_sized
        .quad .Ln_implicit, tf_implicit
        .quad .Ln_keep_width, tf_keep_width
        .quad .Ln_keep_widths, tf_keep_widths
        .quad .Ln_keep_setmem_width, tf_keep_setmem_width
        .quad .Ln_resize_bytes, tf_resize_bytes
        .quad .Ln_with_width, tf_with_width
        .quad .Ln_byte_elements, tf_byte_elements
        .quad .Ln_words, tf_words
        .quad .Ln_to_mask_b, tf_to_mask_b
        .quad .Ln_to_neg_mask_b, tf_to_neg_mask_b
        .quad .Ln_state_read, tf_state_read
        .quad .Ln_may_alias, tf_may_alias
        .quad .Ln_changed_reads, tf_changed_reads
        .quad .Ln_lt_op_m, tf_lt_op_m
        .quad .Ln_le_op_m, tf_le_op_m
        .quad .Ln_ge_zero_m, tf_ge_zero_m
        .quad .Ln_get_sign_m, tf_get_sign_m
        .quad .Ln_max_op_m, tf_max_op_m
        .quad .Ln_min_op_m, tf_min_op_m
        .quad 0, 0

        .section .rodata
.Ln_roundtrip: .asciz "roundtrip"
.Ln_dump_version: .asciz "dump_version"
.Ln_keccak:    .asciz "keccak"
.Ln_runtrace:  .asciz "runtrace"
.Ln_keccak_word: .asciz "keccak_word"
.Ln_ranges:    .asciz "ranges"
.Ln_shr_op:    .asciz "shr_op"
.Ln_shl_op:    .asciz "shl_op"
.Ln_signextend_op: .asciz "signextend_op"
.Ln_bits:      .asciz "bits"
.Ln_lt_op_m:   .asciz "lt_op_m"
.Ln_is_bool:   .asciz "is_bool"
.Ln_value_bits: .asciz "value_bits"
.Ln_max_value_bits: .asciz "max_value_bits"
.Ln_max_value: .asciz "max_value"
.Ln_low_zero_bits: .asciz "low_zero_bits"
.Ln_width_of:  .asciz "width_of"
.Ln_sized:     .asciz "sized"
.Ln_implicit:  .asciz "implicit"
.Ln_keep_width: .asciz "keep_width"
.Ln_keep_widths: .asciz "keep_widths"
.Ln_keep_setmem_width: .asciz "keep_setmem_width"
.Ln_resize_bytes: .asciz "resize_bytes"
.Ln_with_width: .asciz "with_width"
.Ln_byte_elements: .asciz "byte_elements"
.Ln_words:     .asciz "words"
.Ln_to_mask_b: .asciz "to_mask_b"
.Ln_to_neg_mask_b: .asciz "to_neg_mask_b"
.Ln_state_read: .asciz "state_read"
.Ln_may_alias: .asciz "may_alias"
.Ln_changed_reads: .asciz "changed_reads"
.Ln_le_op_m:   .asciz "le_op_m"
.Ln_ge_zero_m: .asciz "ge_zero_m"
.Ln_get_sign_m: .asciz "get_sign_m"
.Ln_max_op_m:  .asciz "max_op_m"
.Ln_min_op_m:  .asciz "min_op_m"
.Ln_json_value: .asciz "json_value"
.Ln_hash:      .asciz "hash"
.Ln_str_flags: .asciz "str_flags"
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
.Ln_ge_zero_many: .asciz "ge_zero_many"
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
.Ln_match_compiled: .asciz "match_compiled"
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
.Ln_simplify_trace_deadline: .asciz "simplify_trace_deadline"
.Ln_make_whiles: .asciz "make_whiles"
.Ln_while_max_memidx: .asciz "while_max_memidx"
.Ln_extract_setmems: .asciz "extract_setmems"
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
.Ln_pretty_line: .asciz "pretty_line"
.Ln_pprint_logic: .asciz "pprint_logic"
.Ln_function: .asciz "function"
.Ln_contract: .asciz "contract"
.Ln_find_mems: .asciz "find_mems"
.Ln_split_setmem_trace: .asciz "split_setmem_trace"
.Ln_simplify_exps: .asciz "simplify_exps"
.Ln_loop_to_setmem_trace: .asciz "loop_to_setmem_trace"
.Ln_heuristics: .asciz "heuristics"
.Ln_fix_storages_trace: .asciz "fix_storages_trace"
.Ln_split_store_trace: .asciz "split_store_trace"
.Ls_unknown_fn: .asciz "<unknown test function>"
.Ls_parse_err:  .asciz "<parse error at %u>"

        .text

FUNC tf_roundtrip
        mov rax, rdi
        ret
ENDF tf_roundtrip

# json_value(v) -> str: the JSON text of the value (data.s), as json.dumps
FUNC tf_json_value
        ENTER
        mov rbx, rdi
        call sb_new
        mov r12, rax
        mov rdi, rax
        mov rsi, rbx
        mov edx, 1
        call data_value
        mov rdi, r12
        call sb_finish
        LEAVE
ENDF tf_json_value

# hash(v) -> the value's hash, as an integer
FUNC tf_hash
        ENTER
        call value_hash
        mov rdi, rax
        call mk_int_u64
        LEAVE
ENDF tf_hash

# str_flags(s) -> (volatile, hf): what str_scan_flags finds in the text
FUNC tf_str_flags
        ENTER
        lea r12, [rdi + N_DATA + 4]
        mov rdi, r12
        call strlen@PLT
        mov rdi, r12
        mov rsi, rax
        call str_scan_flags
        mov ebx, eax
        mov rdi, rdx
        shr rdi, HF_SHIFT
        TAG rdi
        mov rsi, rdi
        mov edi, ebx
        shr edi, 31                     # STR_VOLATILE: 1
        TAG rdi
        call mk2
        LEAVE
ENDF tf_str_flags

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
        mov rdi, [rbx + N_DATA + 16]    # symbolic: an int or a bool
        call vr_number
        sar rax, 1
        mov rdx, rax
        mov rdi, [rbx + N_DATA]
        mov rsi, [rbx + N_DATA + 8]
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

# memloc's widths (widths.s): max_value_bits((exp, bounds)) - bounds None
# or a tuple of (exp, bits) - width_of(exp), sized(exp), implicit((exp,
# width)), keep_width((old, new)), keep_widths((old, new)),
# keep_setmem_width((length, old, new)), resize_bytes((exp, size)),
# with_width((exp, size)), byte_elements(exp) (a tuple), words(exp)
FUNC tf_max_value_bits
        ENTER
        mov rbx, rdi
        xor r12d, r12d
        mov rax, [rbx + N_DATA + 8]
        lea rcx, [rip + sp_none]
        cmp rax, rcx
        je 2f
        call emap_new
        mov r12, rax
        mov r13, [rbx + N_DATA + 8]
        xor r14d, r14d
1:      cmp r14d, [r13 + N_AUX]
        jae 2f
        mov rax, [r13 + N_DATA + r14*8]
        inc r14d
        mov rdi, r12
        mov rsi, [rax + N_DATA]
        mov rdx, [rax + N_DATA + 8]
        call emap_put
        jmp 1b
2:      mov rdi, [rbx + N_DATA]
        mov rsi, r12
        call max_value_bits
        LEAVE
ENDF tf_max_value_bits

FUNC tf_width_of
        ENTER
        call width_of
        mov rdi, rax
        call none_if_nil
        LEAVE
ENDF tf_width_of

FUNC tf_sized
        ENTER
        call sized
        jmp tf_bool_ret
ENDF tf_sized

FUNC tf_words
        ENTER
        call mem_words
        jmp tf_bool_ret
ENDF tf_words

FUNC tf_implicit
        ENTER
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        call implicit
        jmp tf_bool_ret
ENDF tf_implicit

# (entered with the frame of the caller above: eax as True or False)
FUNC tf_bool_ret
        lea rcx, [rip + sp_true]
        lea rdx, [rip + sp_false]
        test eax, eax
        cmovz rcx, rdx
        mov rax, rcx
        LEAVE
ENDF tf_bool_ret

FUNC tf_keep_width
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        jmp keep_width
ENDF tf_keep_width

FUNC tf_keep_widths
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        jmp keep_widths
ENDF tf_keep_widths

FUNC tf_keep_setmem_width
        mov rdx, [rdi + N_DATA + 16]
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        jmp keep_setmem_width
ENDF tf_keep_setmem_width

FUNC tf_resize_bytes
        ENTER
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        call resize_bytes
        mov rdi, rax
        call none_if_nil
        LEAVE
ENDF tf_resize_bytes

FUNC tf_with_width
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        jmp with_width
ENDF tf_with_width

FUNC tf_byte_elements
        ENTER
        mov rbx, rdi
        call vec_new
        mov r12, rax
        xor r13d, r13d
        call is_tuple_rbx
1:      cmp r13d, r14d
        jae 2f
        mov rdi, rbx
        mov esi, r13d
        call is_byte_element
        test eax, eax
        jz 3f
        mov rdi, r12
        lea rsi, [r13 + r13 + 1]
        call vec_push
3:      inc r13d
        jmp 1b
2:      mov rdi, r12
        call vec_to_tuple
        LEAVE
ENDF tf_byte_elements

# is_tuple_rbx(): r14d := the number of elements of the tuple rbx, 0 for
# anything else (tf_byte_elements')
FUNC is_tuple_rbx
        xor r14d, r14d
        mov rdi, rbx
        push rbx
        call is_tuple
        pop rbx
        test eax, eax
        jz 1f
        mov r14d, [rbx + N_AUX]
1:      ret
ENDF is_tuple_rbx

# is_bool(exp) -> bool; state_read(exp) -> its kind (a string) or None;
# may_alias((a, b)) -> bool; changed_reads((exp, op, target)) -> a tuple
# (arithmetic's)
FUNC tf_is_bool
        ENTER
        call is_bool
        lea rcx, [rip + sp_true]
        lea rdx, [rip + sp_false]
        test eax, eax
        cmovz rcx, rdx
        mov rax, rcx
        LEAVE
ENDF tf_is_bool

FUNC tf_state_read
        ENTER
        call state_read
        lea rdi, [rip + .Ls_sr_kinds]
        mov rdi, [rdi + rax*8]
        test rdi, rdi
        jz 1f
        call str_intern_c
        LEAVE
1:      lea rax, [rip + sp_none]
        LEAVE
ENDF tf_state_read

        .section .data.rel.ro
        .align 8
.Ls_sr_kinds:   .quad 0, .Ls_sr_storage, .Ls_sr_tload, .Ls_sr_account, .Ls_sr_call
        .section .rodata
.Ls_sr_storage: .asciz "storage"
.Ls_sr_tload:   .asciz "tload"
.Ls_sr_account: .asciz "account"
.Ls_sr_call:    .asciz "call"
        .text

FUNC tf_may_alias
        ENTER
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        call may_alias
        lea rcx, [rip + sp_true]
        lea rdx, [rip + sp_false]
        test eax, eax
        cmovz rcx, rdx
        mov rax, rcx
        LEAVE
ENDF tf_may_alias

FUNC tf_changed_reads
        ENTER
        mov rbx, rdi
        call vec_new
        mov r12, rax
        mov rdi, [rbx + N_DATA + 8]     # the op, a string: its id
        call str_id
        mov esi, eax
        mov rdi, [rbx + N_DATA]
        mov rdx, [rbx + N_DATA + 16]
        mov rcx, r12
        call changed_reads
        mov rdi, r12
        call vec_to_tuple
        LEAVE
ENDF tf_changed_reads

# the comparisons with top=MEMORY_TOP (memloc's): lt_op_m((a, b))...
FUNC tf_lt_op_m
        ENTER
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        call mem_lt_op
        mov edi, eax
        call tri_value
        LEAVE
ENDF tf_lt_op_m

FUNC tf_le_op_m
        ENTER
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        call mem_le_op
        mov edi, eax
        call tri_value
        LEAVE
ENDF tf_le_op_m

FUNC tf_ge_zero_m
        ENTER
        call mem_ge_zero
        mov edi, eax
        call tri_value
        LEAVE
ENDF tf_ge_zero_m

FUNC tf_get_sign_m
        ENTER
        call mem_get_sign
        cmp eax, SIGN_NONE
        je 2f
        movsxd rdi, eax
        call mk_int_i64
        LEAVE
2:      lea rax, [rip + sp_none]
        LEAVE
ENDF tf_get_sign_m

FUNC tf_max_op_m
        ENTER
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        call mem_max_op
        test rax, rax
        jnz 1f
        mov edi, TRI_CANNOT
        call tri_value
1:      LEAVE
ENDF tf_max_op_m

FUNC tf_min_op_m
        ENTER
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        call mem_min_op
        test rax, rax
        jnz 1f
        mov edi, TRI_CANNOT
        call tri_value
1:      LEAVE
ENDF tf_min_op_m

FUNC tf_ge_zero
        ENTER
        call alg_ge_zero
        mov edi, eax
        call tri_value
        LEAVE
ENDF tf_ge_zero

# ge_zero_many(tuple) -> the tuple of ge_zero of its elements, asked one
# after the other in the same context (its memos: the ranges')
FUNC tf_ge_zero_many
        ENTER
        mov rbx, rdi
        call vec_new
        mov r12, rax
        xor r13d, r13d
1:      cmp r13d, [rbx + N_AUX]
        jae 2f
        mov rdi, [rbx + N_DATA + r13*8]
        call alg_ge_zero
        mov edi, eax
        call tri_value
        mov rdi, r12
        mov rsi, rax
        call vec_push
        inc r13d
        jmp 1b
2:      mov rdi, r12
        call vec_to_tuple
        LEAVE
ENDF tf_ge_zero_many

# ranges((args, fmp, queries)) -> the answers, a tuple (ranges.s):
# set_variables(args) - args None, or (vars, small) - mem[64] solidity's
# free memory pointer when fmp, then each query (kind, a, b, c), in the
# same context: 0 value_range(a, b, c) - b None or a tuple of (exp, lo, hi),
# c 0 (WORD_TOP) or 1 (MEMORY_TOP) - 1 memory_range(a), 2 is_word(a), 3
# shift_sign(a), 4 readable_mask(a, b, c), 5 proven_le(a, b), 6
# may_be_wide(a), 7 unchecked(a) (of the variables and the small words set),
# 8 mentions_var(a, b)
FUNC tf_ranges
        ENTER
        sub rsp, 16
        mov rbx, rdi
        lea rax, [rip + sp_false]
        xor ecx, ecx
        cmp [rbx + N_DATA + 8], rax
        sete cl
        mov [r15 + CTX_VR_NO_FMP], rcx
        mov rdi, [rbx + N_DATA]
        lea rax, [rip + sp_none]
        cmp rdi, rax
        jne 1f
        xor edi, edi
1:      call set_variables
        call vec_new
        mov r12, rax
        mov r13, [rbx + N_DATA + 16]    # the queries
        xor r14d, r14d
2:      cmp r14d, [r13 + N_AUX]
        jae 9f
        mov rbx, [r13 + N_DATA + r14*8]
        inc r14d
        mov rax, [rbx + N_DATA]         # the kind
        mov rdi, [rbx + N_DATA + 8]     # a
        mov rsi, [rbx + N_DATA + 16]    # b
        mov rdx, [rbx + N_DATA + 24]    # c
        cmp rax, (0 << 1) | 1
        je .Ltr_value_range
        cmp rax, (1 << 1) | 1
        je .Ltr_memory_range
        cmp rax, (2 << 1) | 1
        je .Ltr_is_word
        cmp rax, (3 << 1) | 1
        je .Ltr_shift_sign
        cmp rax, (4 << 1) | 1
        je .Ltr_readable_mask
        cmp rax, (5 << 1) | 1
        je .Ltr_proven_le
        cmp rax, (6 << 1) | 1
        je .Ltr_may_be_wide
        cmp rax, (7 << 1) | 1
        je .Ltr_unchecked
        call mentions_var
        jmp .Ltr_bool
.Ltr_value_range:
        mov [rsp], rdi
        mov [rsp + 8], rdx
        mov rdi, rsi
        call tr_bounds
        mov rsi, rax
        mov rdi, [rsp]
        mov rdx, [rsp + 8]
        sar rdx, 1
        call value_range
        jmp .Ltr_pair
.Ltr_memory_range:
        call memory_range
.Ltr_pair:
        mov rdi, rax
        mov rsi, rdx
        call mk2
        jmp .Ltr_push
.Ltr_is_word:
        xor esi, esi
        call is_word
        jmp .Ltr_bool
.Ltr_shift_sign:
        call shift_sign
        lea rcx, [rip + sp_none]
        cmp eax, 2
        je 3f
        movsxd rcx, eax
        lea rcx, [rcx + rcx + 1]
3:      mov rax, rcx
        jmp .Ltr_push
.Ltr_readable_mask:
        call readable_mask
        jmp .Ltr_bool
.Ltr_proven_le:
        call proven_le
        jmp .Ltr_bool
.Ltr_may_be_wide:
        call may_be_wide
        jmp .Ltr_bool
.Ltr_unchecked:
        mov rsi, [r15 + CTX_VR_VARS]
        mov rdx, [r15 + CTX_VR_SMALL]
        call unchecked
.Ltr_bool:
        lea rcx, [rip + sp_true]
        lea rdx, [rip + sp_false]
        test eax, eax
        cmovz rcx, rdx
        mov rax, rcx
.Ltr_push:
        mov rdi, r12
        mov rsi, rax
        call vec_push
        jmp 2b
9:      mov rdi, r12
        call vec_to_tuple
        add rsp, 16
        LEAVE
ENDF tf_ranges

# shr_op((exp, off)), shl_op((exp, off)), signextend_op((b, val))
FUNC tf_shr_op
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        jmp alg_shr_op
ENDF tf_shr_op

FUNC tf_shl_op
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        jmp alg_shl_op
ENDF tf_shl_op

FUNC tf_signextend_op
        mov rsi, [rdi + N_DATA + 8]
        mov rdi, [rdi + N_DATA]
        jmp alg_signextend_op
ENDF tf_signextend_op

# tr_bounds(b) -> rax: None as 0, a tuple of (exp, lo, hi) as an emap
# {exp: (lo, hi)}
FUNC tr_bounds
        ENTER
        mov rbx, rdi
        xor eax, eax
        lea rcx, [rip + sp_none]
        cmp rbx, rcx
        je 9f
        call emap_new
        mov r12, rax
        xor r13d, r13d
1:      cmp r13d, [rbx + N_AUX]
        jae 2f
        mov r14, [rbx + N_DATA + r13*8]
        inc r13d
        mov rdi, [r14 + N_DATA + 8]
        mov rsi, [r14 + N_DATA + 16]
        call mk2
        mov rdi, r12
        mov rsi, [r14 + N_DATA]
        mov rdx, rax
        call emap_put
        jmp 1b
2:      mov rax, r12
9:      LEAVE
ENDF tr_bounds

# dump_version(path) -> the version of the signature dump (sha256.s)
FUNC tf_dump_version
        ENTER
        lea rdi, [rdi + N_DATA + 4]
        call dump_version
        mov rdi, rax
        call mk_int_i64
        LEAVE
ENDF tf_dump_version

# keccak(hexstring) -> int.from_bytes(keccak(bytes), "big") (keccak.s)
FUNC tf_keccak
        ENTER
        call tf_hex_bytes
        mov rdi, rax
        mov rsi, rdx
        call keccak_value
        LEAVE
ENDF tf_keccak

# runtrace((calldatas, words, content, callvalue, max_steps, key, trace))
# -> a result per calldata (hex strings): the trace run by one machine,
# reset between them (runtrace.s) - (ev(key), kind, data, steps,
# len(mem), vars, the bytes reached), key and trace None for none, or the
# error. The world is storage.bytes_tail's: words a tuple of (slot, word),
# content the hex of the bytes, None for no bytes_data.
.set TW_WORDS, 0
.set TW_CONTENT, 8
.set TW_CLEN, 16
.set TW_REACHED, 24
.set TW_SIZEOF, 32

        .section .data.rel.ro
        .align 8
tw_world:        .quad tw_sload, tw_bytes_length, tw_bytes_data
tw_world_nodata: .quad tw_sload, tw_bytes_length, 0
        .section .rodata
.Ls_another_slot: .asciz "another slot"
        .text

FUNC tf_runtrace
        ENTER
        sub rsp, 176
        .set TR_ERR, 0                  # an error handler (64 bytes)
        .set TR_M, 64
        .set TR_USER, 72
        .set TR_RES, 80                 # the results (a vec)
        .set TR_I, 88
        .set TR_ELEMS, 96               # a result's 7 elements
        mov rbx, rdi
        call ctx_set_stack              # (STACK_CHECK as in a worker)
        mov edi, TW_SIZEOF
        call arena_alloc
        mov [rsp + TR_USER], rax
        mov rcx, [rbx + N_DATA + 8]
        mov [rax + TW_WORDS], rcx
        lea r12, [rip + tw_world_nodata]
        mov rdi, [rbx + N_DATA + 16]
        lea rax, [rip + sp_none]
        cmp rdi, rax
        je 1f
        call tf_hex_bytes
        mov rcx, [rsp + TR_USER]
        mov [rcx + TW_CONTENT], rax
        mov [rcx + TW_CLEN], rdx
        lea r12, [rip + tw_world]
1:      xor edi, edi
        xor esi, esi
        mov rdx, r12
        mov rcx, [rsp + TR_USER]
        call rt_machine_new
        mov [rsp + TR_M], rax
        lea rdi, [rax + RM_CALLVALUE]
        mov rsi, [rbx + N_DATA + 24]
        call w_from_value
        mov rdi, [rbx + N_DATA + 32]
        call int_to_i64
        mov rcx, [rsp + TR_M]
        mov [rcx + RM_MAX_STEPS], rax
        call vec_new
        mov [rsp + TR_RES], rax
        mov qword ptr [rsp + TR_I], 0
.Ltr_run:
        mov rcx, [rbx + N_DATA]
        mov rax, [rsp + TR_I]
        cmp eax, [rcx + N_AUX]
        jae .Ltr_done
        mov rdi, [rcx + N_DATA + rax*8]
        call tf_hex_bytes
        mov rdi, [rsp + TR_M]
        mov rsi, rax
        call rt_machine_reset
        mov rax, [rsp + TR_USER]
        mov qword ptr [rax + TW_REACHED], 0
        lea rdi, [rsp + TR_ERR]
        call err_catch
        test eax, eax
        jnz .Ltr_err
        lea rax, [rip + sp_none]
        mov [rsp + TR_ELEMS], rax
        mov [rsp + TR_ELEMS + 8], rax
        mov [rsp + TR_ELEMS + 16], rax
        mov rsi, [rbx + N_DATA + 40]
        lea rax, [rip + sp_none]
        cmp rsi, rax
        je 2f
        mov rdi, [rsp + TR_M]
        call rt_ev
        mov [rsp + TR_ELEMS], rax
2:      mov rsi, [rbx + N_DATA + 48]
        lea rax, [rip + sp_none]
        cmp rsi, rax
        je 3f
        mov rdi, [rsp + TR_M]
        call rt_run
        mov [rsp + TR_ELEMS + 8], rax
        mov rcx, [rsp + TR_M]
        mov rdi, [rcx + RM_DATA]
        mov rsi, rdx
        call tf_hex_str
        mov [rsp + TR_ELEMS + 16], rax
3:      call err_end
        mov r13, [rsp + TR_M]
        mov rdi, [r13 + RM_STEPS]
        call mk_int_u64
        mov [rsp + TR_ELEMS + 24], rax
        mov rdi, [r13 + RM_MEMLEN]
        call mk_int_u64
        mov [rsp + TR_ELEMS + 32], rax
        call vec_new                    # the variables, in their order
        mov r12, rax
        xor r14d, r14d
4:      cmp r14, [r13 + RM_VCOUNT]
        jae 5f
        imul rax, r14, RM_ENTRY
        add rax, [r13 + RM_VENT]
        mov [rsp + TR_ELEMS + 40], rax
        lea rdi, [rax + 16]
        call w_to_value
        mov rsi, rax
        mov rax, [rsp + TR_ELEMS + 40]
        mov rdi, [rax]
        call mk2
        mov rdi, r12
        mov rsi, rax
        call vec_push
        inc r14
        jmp 4b
5:      mov rdi, r12
        call vec_to_list
        mov [rsp + TR_ELEMS + 40], rax
        mov rax, [rsp + TR_USER]
        lea rcx, [rip + sp_false]
        lea rdx, [rip + sp_true]
        cmp qword ptr [rax + TW_REACHED], 0
        cmovne rcx, rdx
        mov [rsp + TR_ELEMS + 48], rcx
        mov edi, 7
        lea rsi, [rsp + TR_ELEMS]
        call mk_tuple
        jmp .Ltr_next
.Ltr_err:
        call tf_exc_value
.Ltr_next:
        mov rdi, [rsp + TR_RES]
        mov rsi, rax
        call vec_push
        inc qword ptr [rsp + TR_I]
        jmp .Ltr_run
.Ltr_done:
        mov rdi, [rsp + TR_RES]
        call vec_to_tuple
        add rsp, 176
        LEAVE
ENDF tf_runtrace

# tw_sload(user, slot) -> the word there, Unsupported for another slot
FUNC tw_sload
        ENTER
        mov rbx, [rdi + TW_WORDS]
        mov r12, rsi
        xor r13d, r13d
1:      cmp r13d, [rbx + N_AUX]
        jae 2f
        mov rax, [rbx + N_DATA + r13*8]
        mov rdi, [rax + N_DATA]
        mov rsi, r12
        call values_equal
        test eax, eax
        jnz 3f
        inc r13d
        jmp 1b
3:      mov rax, [rbx + N_DATA + r13*8]
        mov rax, [rax + N_DATA + 8]
        LEAVE
2:      mov edi, E_UNSUPPORTED
        lea rsi, [rip + .Ls_another_slot]
        call err_throw
ENDF tw_sload

# tw_bytes_length(user, slot): (v - 1) // 2 if v & 1 else (v & 0xFF) // 2
FUNC tw_bytes_length
        ENTER
        call tw_sload
        mov rbx, rax
        mov rdi, rax
        xor esi, esi
        call int_tstbit
        test eax, eax
        jz 1f
        mov rdi, rbx
        mov esi, 3
        call ev_sub
        jmp 2f
1:      mov rdi, rbx
        mov esi, (255 << 1) | 1
        call ev_and
2:      mov edi, 3
        mov rsi, rax
        call ev_shr
        LEAVE
ENDF tw_bytes_length

# tw_bytes_data(user, slot) -> rax: the content, rdx: its length
FUNC tw_bytes_data
        mov qword ptr [rdi + TW_REACHED], 1
        mov rax, [rdi + TW_CONTENT]
        mov rdx, [rdi + TW_CLEN]
        ret
ENDF tw_bytes_data

# tf_hex_str(bytes, n) -> the arena string of their hex digits
FUNC tf_hex_str
        ENTER
        mov rbx, rdi
        mov r12, rsi
        lea rdi, [r12*2 + 16]
        call arena_alloc_raw
        mov r13, rax
        xor ecx, ecx
        lea r8, [rip + .Ls_hexdigits]
1:      cmp rcx, r12
        jae 2f
        movzx eax, byte ptr [rbx + rcx]
        mov edx, eax
        shr eax, 4
        and edx, 15
        mov al, [r8 + rax]
        mov dl, [r8 + rdx]
        mov [r13 + rcx*2], al
        mov [r13 + rcx*2 + 1], dl
        inc rcx
        jmp 1b
2:      mov rdi, r13
        lea rsi, [r12*2]
        call str_new
        LEAVE
ENDF tf_hex_str

        .section .rodata
.Ls_hexdigits: .ascii "0123456789abcdef"
        .text

# tf_hex_bytes(hexstring) -> rax: its bytes (arena), rdx: their count
FUNC tf_hex_bytes
        ENTER
        mov rbx, rdi
        mov edi, [rbx + N_DATA]
        shr edi, 1
        inc rdi
        call arena_alloc_raw
        mov r12, rax
        lea rdi, [rbx + N_DATA + 4]
        mov esi, [rbx + N_DATA]
        mov rdx, r12
        call hex_decode
        mov rdx, rax
        mov rax, r12
        LEAVE
ENDF tf_hex_bytes

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
        xor esi, esi
        call to_mask
        jmp tf_pair_or_none
ENDF tf_to_mask

FUNC tf_to_neg_mask
        ENTER
        xor esi, esi
        call to_neg_mask
        jmp tf_pair_or_none
ENDF tf_to_neg_mask

# to_mask_b((num, bounds)), to_neg_mask_b((num, bounds)): with bounds None
# or a tuple of (exp, lo, hi)
FUNC tf_to_mask_b
        ENTER
        mov rbx, rdi
        mov rdi, [rbx + N_DATA + 8]
        call tr_bounds
        mov rsi, rax
        mov rdi, [rbx + N_DATA]
        call to_mask
        jmp tf_pair_or_none
ENDF tf_to_mask_b

FUNC tf_to_neg_mask_b
        ENTER
        mov rbx, rdi
        mov rdi, [rbx + N_DATA + 8]
        call tr_bounds
        mov rsi, rax
        mov rdi, [rbx + N_DATA]
        call to_neg_mask
        jmp tf_pair_or_none
ENDF tf_to_neg_mask_b

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
        call xmalloc
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
        call xmalloc
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

# match_compiled((exp, pattern)): the same as match, with the pattern
# compiled first (pattern_compile, as the PAT patterns are)
FUNC tf_match_compiled
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE
        mov rbx, rdi
        mov rdi, [rbx + N_DATA + 8]
        call pattern_compile
        mov rdi, [rbx + N_DATA]
        mov rsi, rax
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 1f
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
ENDF tf_match_compiled

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
        STACK_CHECK
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
        test rsi, rsi                   # (None)
        jnz 1f
        lea rsi, [rip + sp_none]
1:      call mk2
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
        xor ecx, ecx                    # (width: sizeof)
        cmp dword ptr [rdi + N_AUX], 4  # (exp, left, right[, width])
        jb 1f
        mov rcx, [rdi + N_DATA + 24]
        lea rax, [rip + sp_none]
        cmp rcx, rax
        jne 1f
        xor ecx, ecx
1:      mov rdx, [rdi + N_DATA + 16]
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
        ENTER
        mov rbx, rdi
        mov rdi, [rdi + N_DATA + 8]
        call req_from_list
        mov rsi, rax
        mov rdi, [rbx + N_DATA]
        call cleanup_vars
        LEAVE
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

# (line, flags) -> list of str
FUNC tf_pretty_line
        mov rsi, [rdi + N_DATA + 8]
        UNTAG rsi
        mov rdi, [rdi + N_DATA]
        jmp pretty_line
ENDF tf_pretty_line

# (exp, indent) -> list of str
FUNC tf_pprint_logic
        mov rsi, [rdi + N_DATA + 8]
        UNTAG rsi
        mov rdi, [rdi + N_DATA]
        jmp pprint_logic
ENDF tf_pprint_logic

# (hash, trace, (name, inputs or None)) -> (name, color_name, abi_name,
# params, trace, payable, read_only, const, getter, returns, is_regular,
# print lines, priority)
FUNC tf_function
        ENTER
        sub rsp, 112
        mov rbx, rdi
        mov rdx, [rbx + N_DATA + 16]
        mov rax, [rdx + N_DATA + 8]
        push rdx
        push rdx
        mov rdi, rax
        call is_none
        pop rdx
        pop rdx
        test eax, eax
        jz 1f
        mov rdi, [rdx + N_DATA]
        xor esi, esi
        call mk2                        # (name, NIL)
        mov rdx, rax
1:      mov rdi, [rbx + N_DATA]
        mov rsi, [rbx + N_DATA + 8]
        call function_new
        mov r12, rax
        mov rax, [r12 + FN_NAME]
        mov [rsp], rax
        mov rax, [r12 + FN_COLOR_NAME]
        mov [rsp + 8], rax
        mov rax, [r12 + FN_ABI_NAME]
        mov [rsp + 16], rax
        mov rax, [r12 + FN_PARAMS]
        mov [rsp + 24], rax
        mov rax, [r12 + FN_TRACE]
        mov [rsp + 32], rax
        mov rdi, [r12 + FN_PAYABLE]
        call tf_bool
        mov [rsp + 40], rax
        mov rdi, [r12 + FN_READ_ONLY]
        call tf_bool
        mov [rsp + 48], rax
        mov rdi, [r12 + FN_CONST]
        call tf_or_none
        mov [rsp + 56], rax
        mov rdi, [r12 + FN_GETTER]
        call tf_or_none
        mov [rsp + 64], rax
        mov rax, [r12 + FN_RETURNS]
        mov [rsp + 72], rax
        mov rdi, [r12 + FN_IS_REGULAR]
        call tf_bool
        mov [rsp + 80], rax
        mov rdi, r12
        call fn_print_lines
        mov [rsp + 88], rax
        mov rdi, r12
        call fn_priority
        TAG rax
        mov [rsp + 96], rax
        mov edi, 13
        mov rsi, rsp
        call mk_tuple
        add rsp, 112
        LEAVE
ENDF tf_function

# [(hash, trace, (name, inputs or None))...] -> (stor_defs, [(name, trace,
# ast, print lines, priority)...], [const names])
FUNC tf_contract
        ENTER
        sub rsp, 48
        mov rbx, rdi
        call vec_new
        mov r12, rax                    # the functions
        xor r13d, r13d
1:      cmp r13d, [rbx + N_AUX]
        jae 2f
        mov r14, [rbx + N_DATA + r13*8]
        mov rdx, [r14 + N_DATA + 16]
        mov rdi, [rdx + N_DATA + 8]
        push rdx
        push rdx
        call is_none
        pop rdx
        pop rdx
        test eax, eax
        jz 11f
        mov rdi, [rdx + N_DATA]
        xor esi, esi
        call mk2
        mov rdx, rax
11:     mov rdi, [r14 + N_DATA]
        mov rsi, [r14 + N_DATA + 8]
        call function_new
        mov rdi, r12
        mov rsi, rax
        call vec_push
        inc r13d
        jmp 1b
2:      xor edi, edi
        xor esi, esi
        call mk_list
        mov rdi, r12
        mov rsi, rax
        call contract_new
        mov rbx, rax
        mov rdi, rax
        call contract_postprocess
        mov rax, [rbx + CT_STOR_DEFS]
        mov [rsp], rax
        call vec_new
        mov r13, rax
        xor r14d, r14d
3:      cmp r14, [r12 + VEC_LEN]
        jae 5f
        mov rax, [r12 + VEC_DATA]
        mov rax, [rax + r14*8]
        mov [rsp + 40], rax
        mov rcx, [rax + FN_NAME]
        mov [rsp + 8], rcx
        mov rcx, [rax + FN_TRACE]
        mov [rsp + 16], rcx
        mov rcx, [rax + FN_AST]
        mov [rsp + 24], rcx
        mov rdi, rax
        call fn_print_lines
        mov [rsp + 32], rax
        mov rdi, [rsp + 40]
        call fn_priority
        TAG rax
        mov [rsp + 40], rax
        mov edi, 5
        lea rsi, [rsp + 8]
        call mk_tuple
        mov rdi, r13
        mov rsi, rax
        call vec_push
        inc r14
        jmp 3b
5:      mov rdi, r13
        call vec_to_list
        mov [rsp + 8], rax
        call vec_new
        mov r13, rax
        mov r12, [rbx + CT_CONSTS]
        xor r14d, r14d
6:      cmp r14, [r12 + VEC_LEN]
        jae 7f
        mov rax, [r12 + VEC_DATA]
        mov rax, [rax + r14*8]
        mov rdi, r13
        mov rsi, [rax + FN_NAME]
        call vec_push
        inc r14
        jmp 6b
7:      mov rdi, r13
        call vec_to_list
        mov [rsp + 16], rax
        mov edi, 3
        mov rsi, rsp
        call mk_tuple
        add rsp, 48
        LEAVE
ENDF tf_contract

FUNC tf_bool
        lea rax, [rip + sp_true]
        test rdi, rdi
        jnz 1f
        lea rax, [rip + sp_false]
1:      ret
ENDF tf_bool

FUNC tf_or_none
        mov rax, rdi
        test rdi, rdi
        jnz 1f
        lea rax, [rip + sp_none]
1:      ret
ENDF tf_or_none

FUNC tf_simplify_trace
        xor esi, esi
        jmp simplify_trace
ENDF tf_simplify_trace

FUNC tf_make_whiles
        xor esi, esi
        jmp make_whiles
ENDF tf_make_whiles

# simplify_trace_deadline((trace, ms)): simplify_trace watched by the
# watchdog with a deadline ms from now (its E_TIMEOUT comes back as an
# exception, the watch stopped)
FUNC tf_simplify_trace_deadline
        ENTER
        sub rsp, ERR_SIZEOF + 16
        mov rbx, rdi
        call monotonic_ns
        mov rcx, [rbx + N_DATA + 8]
        sar rcx, 1
        imul rcx, rcx, 1000000
        lea rsi, [rax + rcx]
        mov rdi, r15
        call watch_start
        mov rdi, rsp
        call err_catch
        test eax, eax
        jnz 1f
        mov rdi, [rbx + N_DATA]
        xor esi, esi
        call simplify_trace
        mov [rsp + ERR_SIZEOF], rax
        call err_end
        mov rdi, r15
        call watch_stop
        mov rax, [rsp + ERR_SIZEOF]
        add rsp, ERR_SIZEOF + 16
        LEAVE
1:      mov [rsp + ERR_SIZEOF], rax
        mov rdi, r15
        call watch_stop
        mov edi, [rsp + ERR_SIZEOF]
        mov rsi, [r15 + CTX_ERR_MSG]
        call err_throw
ENDF tf_simplify_trace_deadline

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

# the stages of simplify_trace that are a composition (for the tests that
# replay python's stages one by one)
FUNC tf_simplify_exps
        lea rsi, [rip + simplify_exp_cb]
        xor edx, edx
        jmp replace_f
ENDF tf_simplify_exps

FUNC tf_loop_to_setmem_trace
        lea rsi, [rip + loop_to_setmem]
        xor edx, edx
        jmp rewrite_trace
ENDF tf_loop_to_setmem_trace

FUNC tf_fix_storages_trace
        lea rsi, [rip + fix_storages]
        xor edx, edx
        jmp replace_f
ENDF tf_fix_storages_trace

# "using heuristics to clean up some things": max_to_add, postprocess_exp
# twice, postprocess_trace on the ifs, rewrite_string_stores
FUNC tf_heuristics
        ENTER
        lea rsi, [rip + max_to_add_cb]
        xor edx, edx
        call replace_f
        mov rdi, rax
        lea rsi, [rip + postprocess_exp]
        xor edx, edx
        call replace_f
        mov rdi, rax
        lea rsi, [rip + postprocess_exp]
        xor edx, edx
        call replace_f
        mov rdi, rax
        lea rsi, [rip + postprocess_trace]
        xor edx, edx
        call rewrite_trace_ifs
        mov rbx, rax
        xor edi, edi
        xor esi, esi
        call mk_list
        mov rdi, rbx
        mov rsi, rax
        call rewrite_string_stores
        LEAVE
ENDF tf_heuristics

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
