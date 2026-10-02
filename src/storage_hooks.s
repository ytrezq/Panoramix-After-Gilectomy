# The test hooks of the storage (storage.py's functions, one by one):
# tf_storage((name, args...)) applies the function `name` to the args and
# returns what python's would - a Fail as the string 'Fail', None as None.
# See tests/test_storage.py.

.include "defs.inc"

        .section .data.rel.ro
        .align 8
sth_table:
        .quad .Lh_hash_constant, sth_hash_constant
        .quad .Lh_parse, sth_parse
        .quad .Lh_steps, sth_steps
        .quad .Lh_word, sth_word
        .quad .Lh_is_word, sth_is_word
        .quad .Lh_from_calldata, sth_from_calldata
        .quad .Lh_linear, sth_linear
        .quad .Lh_packed, sth_packed
        .quad .Lh_elem_width, sth_elem_width
        .quad .Lh_typeof, sth_typeof
        .quad .Lh_form, sth_form
        .quad .Lh_raw, sth_raw
        .quad .Lh_layout, sth_layout
        .quad .Lh_slot_class, sth_slot_class
        .quad .Lh_find_accesses, sth_find_accesses
        .quad .Lh_language, sth_language
        .quad .Lh_checked_below, sth_checked_below
        .quad .Lh_narrow, sth_narrow
        .quad .Lh_ev, sth_ev
        .quad .Lh_evb, sth_evb
        .quad .Lh_read, sth_read
        .quad .Lh_checks, sth_checks
        .quad 0, 0

        .section .rodata
.Lh_hash_constant: .asciz "hash_constant"
.Lh_parse:      .asciz "parse"
.Lh_steps:      .asciz "steps"
.Lh_word:       .asciz "word"
.Lh_is_word:    .asciz "is_word"
.Lh_from_calldata: .asciz "from_calldata"
.Lh_linear:     .asciz "linear"
.Lh_packed:     .asciz "packed"
.Lh_elem_width: .asciz "elem_width"
.Lh_typeof:     .asciz "typeof"
.Lh_form:       .asciz "form"
.Lh_raw:        .asciz "raw"
.Lh_layout:     .asciz "layout"
.Lh_slot_class: .asciz "slot_class"
.Lh_find_accesses: .asciz "find_accesses"
.Lh_language:   .asciz "language"
.Lh_checked_below: .asciz "checked_below"
.Lh_narrow:     .asciz "narrow"
.Lh_ev:         .asciz "ev"
.Lh_evb:        .asciz "evb"
.Lh_read:       .asciz "read"
.Lh_checks:     .asciz "checks"
.Ls_fail:       .asciz "Fail"
.Ls_unknown:    .asciz "no such storage hook"
.Ls_vyper:      .asciz "vyper"
.Ls_solidity:   .asciz "solidity"
        .text

# tf_storage((name, args...)) -> value
FUNC tf_storage
        ENTER
        mov rbx, rdi
        call ctx_set_stack              # (STACK_CHECK as in a worker)
        mov rax, [rbx + N_DATA]         # the name
        lea r13, [rax + N_DATA + 4]
        lea r12, [rip + sth_table]
1:      mov rdi, [r12]
        test rdi, rdi
        jz 9f
        mov rsi, r13
        call strcmp@PLT
        test eax, eax
        jz 2f
        add r12, 16
        jmp 1b
2:      mov rdi, rbx
        call [r12 + 8]
        LEAVE
9:      mov edi, E_VALUE
        lea rsi, [rip + .Ls_unknown]
        call err_throw
ENDF tf_storage

# sth_arg(args, i) -> rax: args[1 + i]
.macro ARG reg, i
        mov \reg, [rbx + N_DATA + 8 + 8*\i]
.endm

# sth_lang(v) -> eax: 1 for the string "vyper"
FUNC sth_lang
        ENTER
        lea rsi, [rip + .Ls_vyper]
        call str_eq_c
        LEAVE
ENDF sth_lang

# sth_fail(v) -> rax: v, or 'Fail' for NIL
FUNC sth_fail
        mov rax, rdi
        test rdi, rdi
        jnz 1f
        lea rdi, [rip + .Ls_fail]
        jmp str_intern_c
1:      ret
ENDF sth_fail

FUNC sth_none
        mov rax, rdi
        test rdi, rdi
        jnz 1f
        lea rax, [rip + sp_none]
1:      ret
ENDF sth_none

FUNC sth_bool
        lea rax, [rip + sp_true]
        test eax, eax
        test edi, edi
        jnz 1f
        lea rax, [rip + sp_false]
1:      ret
ENDF sth_bool

# ('hash_constant', c, lang) -> (path, delta) or None
FUNC sth_hash_constant
        ENTER
        mov rbx, rdi
        ARG rdi, 1
        call sth_lang
        mov esi, eax
        ARG rdi, 0
        call st_hash_constant
        mov rdi, rax
        call sth_none
        LEAVE
ENDF sth_hash_constant

# ('parse', idx, lang) -> path
FUNC sth_parse
        ENTER
        mov rbx, rdi
        ARG rdi, 1
        call sth_lang
        mov esi, eax
        ARG rdi, 0
        call st_parse
        LEAVE
ENDF sth_parse

# ('steps', path) -> (root, st) or None
FUNC sth_steps
        ENTER
        mov rbx, rdi
        ARG rdi, 0
        call st_steps
        mov rdi, rax
        call sth_none
        LEAVE
ENDF sth_steps

FUNC sth_word
        ENTER
        mov rbx, rdi
        ARG rdi, 0
        call st_word
        LEAVE
ENDF sth_word

FUNC sth_is_word
        ENTER
        mov rbx, rdi
        ARG rdi, 0
        call st_is_word
        mov edi, eax
        call sth_bool
        LEAVE
ENDF sth_is_word

FUNC sth_from_calldata
        ENTER
        mov rbx, rdi
        ARG rdi, 0
        call st_from_calldata
        mov edi, eax
        call sth_bool
        LEAVE
ENDF sth_from_calldata

# ('linear', e) -> (i, s, c)
FUNC sth_linear
        ENTER
        sub rsp, 32
        mov rbx, rdi
        ARG rdi, 0
        mov rsi, rsp
        call st_linear
        mov edi, 3
        mov rsi, rsp
        call mk_tuple
        add rsp, 32
        LEAVE
ENDF sth_linear

# ('packed', e, off, width) -> value or None
FUNC sth_packed
        ENTER
        mov rbx, rdi
        ARG rdi, 0
        ARG rsi, 1
        ARG rdx, 2
        call st_packed
        mov rdi, rax
        call sth_none
        LEAVE
ENDF sth_packed

FUNC sth_elem_width
        ENTER
        mov rbx, rdi
        ARG rdi, 0
        call st_elem_width
        LEAVE
ENDF sth_elem_width

# sth_vec_of(seq) -> vec: the elements of a list
FUNC sth_vec_of
        ENTER
        mov rbx, rdi
        call vec_new
        mov r12, rax
        mov rdi, rax
        mov rsi, rbx
        call vec_extend_seq
        mov rax, r12
        LEAVE
ENDF sth_vec_of

# ('typeof', [(st, size, off)...]) -> type
FUNC sth_typeof
        ENTER
        mov rbx, rdi
        ARG rdi, 0
        call sth_vec_of
        mov rdi, rax
        call st_typeof
        LEAVE
ENDF sth_typeof

# ('form', base, t, st, size, off) -> form or 'Fail'
FUNC sth_form
        ENTER
        mov rbx, rdi
        ARG rdi, 0
        ARG rsi, 1
        ARG rdx, 2
        ARG rcx, 3
        ARG r8, 4
        call st_form
        mov rdi, rax
        call sth_fail
        LEAVE
ENDF sth_form

# ('raw', size, off, idx, write) -> form
FUNC sth_raw
        ENTER
        mov rbx, rdi
        ARG rdi, 3
        call py_truthy
        mov ecx, eax
        ARG rdi, 0
        ARG rsi, 1
        ARG rdx, 2
        call st_raw
        LEAVE
ENDF sth_raw

# ('layout', [(size, off, wr)...]) -> [(off, end)...] (wr: True, 'const',
# False)
FUNC sth_layout
        ENTER
        mov rbx, rdi
        ARG rdi, 0
        call sth_vec_of
        mov rdi, rax
        call st_layout
        LEAVE
ENDF sth_layout

# ('slot_class', st or None) -> value
FUNC sth_slot_class
        ENTER
        mov rbx, rdi
        ARG rdi, 0
        call tf_none_nil
        mov rdi, rax
        call st_slot_class
        mov rdi, rax
        call sth_none
        LEAVE
ENDF sth_slot_class

# sth_od_items(od) -> [(key, value)...]
FUNC sth_od_items
        ENTER
        mov rbx, rdi
        call vec_new
        mov r12, rax
        xor r13d, r13d
1:      mov rdi, rbx
        call od_len
        cmp r13, rax
        jae 2f
        mov rdi, rbx
        mov rsi, r13
        call od_key
        mov r14, rax
        mov rdi, rbx
        mov rsi, r13
        call od_val
        mov rsi, rax
        mov rdi, r14
        call mk2
        mov rdi, r12
        mov rsi, rax
        call vec_push
        inc r13
        jmp 1b
2:      mov rdi, r12
        call vec_to_list
        LEAVE
ENDF sth_od_items

# ('find_accesses', exp) -> [((size, off, idx), wr)...]
FUNC sth_find_accesses
        ENTER
        mov rbx, rdi
        call od_new
        mov r12, rax
        ARG rdi, 0
        mov rsi, r12
        call st_find_accesses
        mov rdi, r12
        call sth_od_items
        LEAVE
ENDF sth_find_accesses

# ('language', code hex or None, [(size, off, idx)...]) -> 'vyper' or
# 'solidity'
FUNC sth_language
        ENTER
        sub rsp, 16
        mov rbx, rdi
        call od_new
        mov r12, rax
        ARG r13, 1
        xor r14d, r14d
1:      cmp r14d, [r13 + N_AUX]
        jae 2f
        mov rdi, r12
        mov rsi, [r13 + N_DATA + r14*8]
        lea rdx, [rip + sp_false]
        call od_put
        inc r14d
        jmp 1b
2:      ARG rdi, 0
        call is_none
        xor edi, edi
        xor esi, esi
        test eax, eax
        jnz 3f
        ARG rdi, 0
        call tf_hex_bytes
        mov rdi, rax
        mov rsi, rdx
3:      mov rdx, r12
        call st_language
        lea rdi, [rip + .Ls_solidity]
        lea rcx, [rip + .Ls_vyper]
        test eax, eax
        cmovnz rdi, rcx
        call str_intern_c
        add rsp, 16
        LEAVE
ENDF sth_language

# ('checked_below', trace) -> [(x, n)...]
FUNC sth_checked_below
        ENTER
        mov rbx, rdi
        ARG rdi, 0
        call st_checked_below
        mov rdi, rax
        call sth_od_items
        LEAVE
ENDF sth_checked_below

# ('narrow', exp) -> replace_f(exp, narrow)
FUNC sth_narrow
        ENTER
        mov rbx, rdi
        ARG rdi, 0
        lea rsi, [rip + st_narrow]
        xor edx, edx
        call replace_f
        LEAVE
ENDF sth_narrow

# ('ev', e, seed) -> int
FUNC sth_ev
        ENTER
        sub rsp, 32
        mov rbx, rdi
        ARG rdi, 1
        call int_to_i64
        mov rdi, rax
        call ck_new
        mov rdx, rax
        mov rdi, rsp
        ARG rsi, 0
        call ck_ev
        mov rdi, rsp
        call w_to_value
        add rsp, 32
        LEAVE
ENDF sth_ev

# ('evb', e, seed) -> the hex of the bytes
FUNC sth_evb
        ENTER
        mov rbx, rdi
        ARG rdi, 1
        call int_to_i64
        mov rdi, rax
        call ck_new
        mov r12, rax
        ARG rdi, 0
        mov rsi, r12
        call ck_evb
        mov rdi, [r12 + 8]
        mov rsi, [r12 + 16]
        call tf_hex_str
        LEAVE
ENDF sth_evb

# sth_defs(list of (name, slot, off, type)) -> od: name -> (slot, off, type)
FUNC sth_defs
        ENTER
        mov rbx, rdi
        call od_new
        mov r12, rax
        xor r13d, r13d
1:      cmp r13d, [rbx + N_AUX]
        jae 2f
        mov r14, [rbx + N_DATA + r13*8]
        inc r13d
        mov rdi, [r14 + N_DATA + 8]
        mov rsi, [r14 + N_DATA + 16]
        mov rdx, [r14 + N_DATA + 24]
        call mk3
        mov rdi, r12
        mov rsi, [r14 + N_DATA]
        mov rdx, rax
        call od_put
        jmp 1b
2:      mov rax, r12
        LEAVE
ENDF sth_defs

# ('read', f, defs, lang, seed) -> (slot or ('blen', slot), off, size)
FUNC sth_read
        ENTER
        sub rsp, 96
        mov rbx, rdi
        ARG rdi, 3
        call int_to_i64
        mov rdi, rax
        call ck_new
        mov r12, rax
        ARG rdi, 1
        call sth_defs
        mov r13, rax
        ARG rdi, 2
        call sth_lang
        mov ecx, eax
        mov rdi, rsp
        ARG rsi, 0
        mov rdx, r13
        mov r8, r12
        call ck_read
        mov [rsp + 64], rax
        mov [rsp + 72], rdx
        mov rdi, rsp
        call w_to_value
        cmp qword ptr [rsp + 32], 0
        je 1f
        mov rsi, rax
        LOADS rdi, BLEN
        call mk2
1:      mov rdi, rax
        mov rsi, [rsp + 64]
        mov rdx, [rsp + 72]
        call mk3
        add rsp, 96
        LEAVE
ENDF sth_read

# ('checks', f, size, off, idx, defs, lang) -> bool
FUNC sth_checks
        ENTER
        mov rbx, rdi
        ARG rdi, 4
        call sth_defs
        mov r12, rax
        ARG rdi, 5
        call sth_lang
        mov r9d, eax
        ARG rdi, 0
        ARG rsi, 1
        ARG rdx, 2
        ARG rcx, 3
        mov r8, r12
        call ck_checks
        mov edi, eax
        call sth_bool
        LEAVE
ENDF sth_checks

        .section .note.GNU-stack,"",@progbits
