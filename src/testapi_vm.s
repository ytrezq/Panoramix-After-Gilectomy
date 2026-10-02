# The test hooks of the VM, the stack and the loader (see testapi.s: each
# takes the parsed python literal and returns a value, printed as python's
# repr)

.include "defs.inc"

        .text

# tv_loader(hexcode) -> rax: a loader of the code (malloc'ed; the caller
# frees it with loader_free)
FUNC tv_loader
        ENTER
        mov rbx, rdi
        call tf_hex_bytes
        mov r12, rax
        mov r13, rdx
        call loader_new
        mov r14, rax
        mov rdi, rax
        mov rsi, r12
        mov rdx, r13
        call loader_load
        mov rax, r14
        LEAVE
ENDF tv_loader

# sets_fmp(hexcode) -> python's loader.sets_free_memory_pointer of its
# instructions (the loader's LD_NO_FREE_MEM, the other way round)
FUNC tf_sets_fmp
        ENTER
        call tv_loader
        mov rbx, rax
        lea r12, [rip + sp_true]
        cmp byte ptr [rbx + LD_NO_FREE_MEM], 0
        je 1f
        lea r12, [rip + sp_false]
1:      mov rdi, rbx
        call loader_free
        mov rax, r12
        LEAVE
ENDF tf_sets_fmp

# stack_vars((first, positions, depth)) -> (folded, vars): positions a
# tuple of indices
FUNC tf_stack_vars
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, [rbx + N_DATA]         # first
        mov edi, [r12 + N_AUX]
        inc edi
        call arena_alloc                # (zeroed)
        mov r13, rax
        mov r14, [rbx + N_DATA + 8]     # positions
        xor ecx, ecx
1:      cmp ecx, [r14 + N_AUX]
        jae 2f
        mov rax, [r14 + N_DATA + rcx*8]
        sar rax, 1
        mov byte ptr [r13 + rax], 1
        inc ecx
        jmp 1b
2:      mov rdi, r12
        mov rsi, r13
        mov rdx, [rbx + N_DATA + 16]
        sar rdx, 1
        lea rcx, [rsp]
        call stack_vars
        mov rdi, rax
        mov rsi, [rsp]
        call mk2
        add rsp, 16
        LEAVE
ENDF tf_stack_vars

# emap_items(map) -> tuple of (key, value): the entries of an emap of the
# current epoch, in the order of the slots (0: ())
FUNC emap_items
        ENTER
        mov rbx, rdi
        call vec_new
        mov r12, rax
        test rbx, rbx
        jz 3f
        xor r13d, r13d
1:      cmp r13, [rbx + EMAP_CAP]
        jae 3f
        mov rax, r13
        shl rax, 5
        add rax, [rbx + EMAP_ENTRIES]
        inc r13
        mov rcx, [rbx + EMAP_EPOCH]
        cmp [rax + 16], rcx
        jne 1b
        mov rdi, [rax]
        mov rsi, [rax + 8]
        call mk2
        mov rdi, r12
        mov rsi, rax
        call vec_push
        jmp 1b
3:      mov rdi, r12
        call vec_to_tuple
        LEAVE
ENDF emap_items

# nil_none(v) -> rax: v, NIL as None
FUNC nil_none
        mov rax, rdi
        test rdi, rdi
        jnz 1f
        lea rax, [rip + sp_none]
1:      ret
ENDF nil_none

        .section .rodata
.Lvh_mask_value:    .asciz "mask_value"
.Lvh_read_memory:   .asciz "read_memory"
.Lvh_write_memory:  .asciz "write_memory"
.Lvh_known_zeroes:  .asciz "known_zeroes"
.Lvh_forget:        .asciz "forget"
.Lvh_upper_bound:   .asciz "upper_bound"
.Lvh_known_bounds:  .asciz "known_bounds"
.Lvh_bound:         .asciz "bound"
.Lvh_write_range:   .asciz "write_range"
.Lvh_and_op:        .asciz "and_op"
.Lvh_decided:       .asciz "decided"
.Lvh_switch_values: .asciz "switch_values"
.Lvh_entry_memory:  .asciz "entry_memory"
.Lvh_is_known:      .asciz "is_known"
.Lvh_float:         .asciz "float"
        .text

# vm_helper((name, a, b, c, d)): the VM's helpers (vmmem.s) - see
# tests/test_vmmem.py for the arguments of each
FUNC tf_vm_helper
        ENTER
        mov rbx, rdi
        mov r12, [rbx + N_DATA]         # the name
        mov r13, [rbx + N_DATA + 8]     # a
        mov r14, [rbx + N_DATA + 16]    # b
.macro VH_IS name, label
        mov rdi, r12
        lea rsi, [rip + .Lvh_\name]
        call str_eq_c
        test eax, eax
        jnz \label
.endm
        VH_IS mask_value, .Lvh_mv
        VH_IS read_memory, .Lvh_rm
        VH_IS write_memory, .Lvh_wm
        VH_IS known_zeroes, .Lvh_kz
        VH_IS forget, .Lvh_fg
        VH_IS upper_bound, .Lvh_ub
        VH_IS known_bounds, .Lvh_kb
        VH_IS bound, .Lvh_bd
        VH_IS write_range, .Lvh_wr
        VH_IS and_op, .Lvh_ao
        VH_IS decided, .Lvh_dc
        VH_IS switch_values, .Lvh_sv
        VH_IS entry_memory, .Lvh_em
        VH_IS is_known, .Lvh_ik
        lea rax, [rip + sp_none]
        LEAVE
.Lvh_mv:
        mov rdi, r13
        mov rsi, r14
        mov rdx, [rbx + N_DATA + 24]
        mov rcx, [rbx + N_DATA + 32]
        call mask_value
        LEAVE
.Lvh_rm:
        mov rdi, r13
        mov rsi, r14
        call read_memory
        mov rdi, rax
        call nil_none
        LEAVE
.Lvh_wm:
        mov rdi, r13
        mov rsi, r14
        mov rdx, [rbx + N_DATA + 24]
        call write_memory
        LEAVE
.Lvh_kz:
        mov rdi, r13
        mov rsi, r14
        mov rdx, [rbx + N_DATA + 24]
        call known_zeroes
        mov edi, eax                    # (TRI_TRUE, TRI_FALSE)
        call tri_value
        LEAVE
.Lvh_fg:
        mov rdi, r13
        mov rsi, r14
        sar rsi, 1
        call forget
        LEAVE
.Lvh_ub:
        mov rdi, r13
        mov rsi, r14
        call upper_bound
        mov rdi, rax
        call nil_none
        LEAVE
.Lvh_kb:
        mov rdi, r13
        call known_bounds
        mov rdi, rax
        call emap_items
        LEAVE
.Lvh_bd:
        mov rdi, r13
        mov rsi, r14
        call bound
        mov rdi, rax
        call nil_none
        LEAVE
.Lvh_wr:
        mov rdi, r13
        mov rsi, r14
        mov rdx, [rbx + N_DATA + 24]
        call write_range
        test rax, rax
        jz 1f
        js 2f
        mov rdi, rax
        mov rsi, rdx
        call mk2
        LEAVE
1:      lea rax, [rip + sp_none]
        LEAVE
2:      lea rdi, [rip + .Lvh_float]
        call str_intern_c
        LEAVE
.Lvh_ao:
        mov rdi, r13
        mov rsi, r14
        mov rdx, [rbx + N_DATA + 24]
        call and_op
        LEAVE
.Lvh_dc:
        mov rdi, r13
        mov rsi, r14
        call decided
        LEAVE
.Lvh_sv:
        mov rdi, r13
        call switch_values
        test rax, rax
        jz 1b
        mov r12, rax
        mov rdi, rdx
        call vec_to_tuple
        mov rsi, rax
        mov rdi, r12
        call mk2
        LEAVE
.Lvh_em:
        mov rdi, r13
        call entry_memory
        LEAVE
.Lvh_ik:
        mov rdi, r13
        mov rsi, r14
        call is_known
        mov edi, eax
        call tri_value
        LEAVE
ENDF tf_vm_helper

        .section .rodata
.Leh_is_dispatch:   .asciz "is_dispatch"
.Leh_selector_test: .asciz "selector_test"
.Leh_reverts:       .asciz "reverts"
.Leh_strip_markers: .asciz "strip_markers"
.Leh_entry_paths:   .asciz "entry_paths"
.Leh_apply_entry:   .asciz "apply_entry"
.Leh_entry_known:   .asciz "entry_known"
.Leh_common_entry:  .asciz "common_entry"
        .text

# entry_helper((name, a, b, c)): the loader's entry functions (entry.s) -
# see tests/test_entry.py
FUNC tf_entry_helper
        ENTER
        mov rbx, rdi
        mov r12, [rbx + N_DATA]         # the name
        mov r13, [rbx + N_DATA + 8]     # a
        mov r14, [rbx + N_DATA + 16]    # b
.macro EH_IS name, label
        mov rdi, r12
        lea rsi, [rip + .Leh_\name]
        call str_eq_c
        test eax, eax
        jnz \label
.endm
        EH_IS is_dispatch, .Leh_id
        EH_IS selector_test, .Leh_st
        EH_IS reverts, .Leh_rv
        EH_IS strip_markers, .Leh_sm
        EH_IS entry_paths, .Leh_ep
        EH_IS apply_entry, .Leh_ae
        EH_IS entry_known, .Leh_ek
        EH_IS common_entry, .Leh_ce
        lea rax, [rip + sp_none]
        LEAVE
.Leh_id:
        mov rdi, r13
        call is_dispatch
        mov edi, eax
        call tri_value
        LEAVE
.Leh_st:
        mov rdi, r13
        call selector_test
        test rax, rax
        jz 1f
        lea rsi, [rip + sp_true]
        lea rcx, [rip + sp_false]
        test edx, edx
        cmovz rsi, rcx
        mov rdi, rax
        call mk2
        LEAVE
1:      lea rax, [rip + sp_none]
        LEAVE
.Leh_rv:
        mov rdi, r13
        call reverts
        mov edi, eax
        call tri_value
        LEAVE
.Leh_sm:
        mov rdi, r13
        call strip_markers
        LEAVE
.Leh_ep:
        call vec_new
        mov r12, rax
        mov rdi, r13                    # trace
        mov rsi, r14                    # leaf: 0 funccall, 1 jd
        sar rsi, 1
        mov rdx, [rbx + N_DATA + 24]    # arg
        xor edi, edi                    # (the empty entry)
        push rdx
        push rsi
        xor esi, esi
        call mk_tuple
        mov rcx, rax
        pop rsi
        pop rdx
        mov rdi, r13
        mov r8, r12
        call entry_paths
        mov rdi, r12
        call vec_to_list
        LEAVE
.Leh_ae:
        mov rdi, r13
        mov rsi, r14
        call apply_entry
        LEAVE
.Leh_ek:
        mov rdi, r13
        call entry_known
        LEAVE
.Leh_ce:
        mov rdi, r13
        call common_entry
        LEAVE
ENDF tf_entry_helper

# vm_func((hexcode, hash[, flags])): the trace of the function `hash` (its string:
# '0x12345678' or '_fallback'), as the decompiler gets it - the loader's
# functions found (loader_find_functions), the VM run from the function's
# target (past its jumpdest) with what the dispatcher did before it
# (vm_run_function)
FUNC tf_vm_func
        ENTER
        sub rsp, 96                     # the error handler, the loader, the result
        mov rbx, rdi
        cmp dword ptr [rbx + N_AUX], 3  # (python's --verbose, --explain: VB_*)
        jb 1f
        mov rax, [rbx + N_DATA + 16]
        sar rax, 1
        mov [r15 + CTX_VERBOSE], rax
1:      mov rdi, [rbx + N_DATA]
        call tv_loader
        mov [rsp + 72], rax
        mov r12, rax
        mov rdi, rsp
        call err_catch
        test eax, eax
        jnz 8f
        mov rdi, r12
        mov rsi, 60000000000            # 60 s
        call loader_find_functions
        call err_end
        jmp 1f
8:      # python's "Loader issue": the default function only, at 0
        lea rdi, [rip + .Ltv_fallback]
        call str_intern_c
        mov [rsp + 80], rax
        xor edi, edi
        xor esi, esi
        call mk_tuple
        mov rdx, rax
        mov rdi, [rsp + 80]
        mov esi, 1
        call mk3
        mov rdi, rax
        call mk_list1
        mov [r12 + LD_FUNCS], rax
        xor edi, edi
        xor esi, esi
        call mk_tuple
        mov [r12 + LD_FALLBACK_KNOWN], rax
1:      # the function asked for
        mov r13, [r12 + LD_FUNCS]
        xor r14d, r14d
2:      cmp r14d, [r13 + N_AUX]
        jae 7f
        mov rax, [r13 + N_DATA + r14*8]
        inc r14d
        mov rcx, [rbx + N_DATA + 8]
        cmp [rax + N_DATA], rcx
        jne 2b
        mov [rsp + 80], rax             # (hash, target, stack)
        mov rdi, r12
        xor esi, esi
        call vm_new
        mov rdi, rsp
        call err_catch
        test eax, eax
        jnz 6f
        # past the jumpdest it starts at (the decompiler's target += 1 -
        # python's KeyError where the target isn't an instruction)
        mov rax, [rsp + 80]
        mov rsi, [rax + N_DATA + 8]
        mov [rsp + 88], rsi
        cmp rsi, (1 << 1) | 1
        jle 3f
        test sil, 1
        jz 4f
        sar rsi, 1
        mov rdi, r12
        call loader_instr_at
        test rax, rax
        jz 4f
        cmp byte ptr [rax + IN_OP], 0x5b
        jne 3f
        add qword ptr [rsp + 88], 2
        jmp 3f
4:      mov edi, E_KEY
        lea rsi, [rip + .Ltv_key]
        call err_throw
3:      mov rax, [rsp + 80]
        mov rdi, r12
        mov rsi, [rax + N_DATA]
        mov rdx, [rsp + 88]
        mov rcx, [rax + N_DATA + 16]
        xor r8d, r8d
        call vm_run_function
        mov [rsp + 80], rax
        call err_end
        jmp 9f
6:      call tf_exc_value
        mov [rsp + 80], rax
        jmp 9f
7:      lea rax, [rip + sp_none]        # no such function
        mov [rsp + 80], rax
9:      mov rdi, r12
        call loader_free
        mov rax, [rsp + 80]
        add rsp, 96
        LEAVE
ENDF tf_vm_func

        .section .rodata
.Ltv_fallback: .asciz "_fallback"
.Ltv_key: .asciz "the target is not an instruction"
        .text

        .section .note.GNU-stack,"",@progbits
