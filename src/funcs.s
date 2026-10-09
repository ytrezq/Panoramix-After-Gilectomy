# Function discovery (port of Loader.run): runs the dispatcher of the
# contract symbolically in the "just_fdests" mode, where a comparison of
# the selector with a constant becomes a ('funccall', hash, target, stack)
# line, and collects the functions from the trace.

.include "defs.inc"

        .section .rodata
.Ls_fallback:   .asciz "_fallback"
.Ls_hash_fmt:   .asciz "0x%08lx"
.Ls_unknown_hash: .asciz "????????"

        .text

# loader_find_functions(loader, timeout_ns): python's Loader.run - fills
# LD_FUNCS with the list of (hash, target, stack) - hash being the padded
# hex string, or "_fallback" -, LD_FALLBACK_KNOWN, and LD_ENTRIES: what runs
# before each function (see entry_paths), by hash
FUNC loader_find_functions
        ENTER
        sub rsp, 64
        .set FF_TARGETS, 0              # hash -> (target, stack) (a map)
        .set FF_I, 8
        .set FF_LINE, 16
        .set FF_HASH, 24
        .set FF_DEFAULT, 32             # the default function's (target, stack), or 0
        .set FF_ENTRIES, 40             # an ordered dict: hash -> a vec of entries
        .set FF_TIMEOUT, 48
        mov rbx, rdi
        mov [rsp + FF_TIMEOUT], rsi
        mov rdi, rbx
        mov esi, 1
        call vm_new
        xor edi, edi
        xor esi, esi
        call mk_tuple                   # ()
        mov rsi, rax
        mov rdx, rax
        mov r8, rax                     # entry=()
        mov r9, rax                     # memory=()
        mov edi, 1                      # start = 0
        mov rcx, [rsp + FF_TIMEOUT]
        call vm_run
        mov r12, rax                    # the trace
        # the function calls, and the targets they lead to
        call vec_new
        mov r13, rax
        mov rdi, r12
        lea rsi, [rip + pred_funccall]
        mov rdx, r13
        call walk_collect
        # hash_targets: hash string -> (target, stack), in order of
        # appearance, a later call for the same hash replacing the entry
        call vec_new
        mov r14, rax                    # the hash strings, in order
        call map_new
        mov [rsp + FF_TARGETS], rax
        xor ecx, ecx
1:      cmp rcx, [r13 + VEC_LEN]
        jae 3f
        mov [rsp + FF_I], rcx
        mov rax, [r13 + VEC_DATA]
        mov rax, [rax + rcx*8]          # ('funccall', hash, target, stack)
        mov [rsp + FF_LINE], rax
        mov rdi, [rax + N_DATA + 8]
        call padded_hex8
        mov [rsp + FF_HASH], rax
        mov rdi, [rsp + FF_TARGETS]
        mov rsi, rax
        call map_get
        test rax, rax
        jnz 2f
        mov rdi, r14
        mov rsi, [rsp + FF_HASH]
        call vec_push
2:      mov rax, [rsp + FF_LINE]
        mov rdi, [rax + N_DATA + 16]
        mov rsi, [rax + N_DATA + 24]
        call mk2
        mov rdi, [rsp + FF_TARGETS]
        mov rsi, [rsp + FF_HASH]
        mov rdx, rax
        call map_put
        mov rcx, [rsp + FF_I]
        inc rcx
        jmp 1b
3:      # what runs before each function: the entry of every path to it
        call od_new
        mov [rsp + FF_ENTRIES], rax
        call vec_new
        mov [rsp + FF_LINE], rax        # (entry, line) pairs
        xor edi, edi
        xor esi, esi
        call mk_tuple
        mov rcx, rax
        mov rdi, r12
        xor esi, esi                    # the funccalls
        xor edx, edx
        mov r8, [rsp + FF_LINE]
        call entry_paths
        mov qword ptr [rsp + FF_I], 0
4:      mov rcx, [rsp + FF_I]
        mov rax, [rsp + FF_LINE]
        cmp rcx, [rax + VEC_LEN]
        jae 5f
        inc qword ptr [rsp + FF_I]
        mov rax, [rax + VEC_DATA]
        mov rax, [rax + rcx*8]          # (entry, line)
        mov [rsp + FF_HASH], rax
        mov rax, [rax + N_DATA + 8]
        mov rdi, [rax + N_DATA + 8]
        call padded_hex8
        mov rdi, [rsp + FF_ENTRIES]
        mov rsi, rax
        mov rdx, [rsp + FF_HASH]
        mov rdx, [rdx + N_DATA]
        call entries_add
        jmp 4b
5:      # what's known in the default function: no selector matched
        mov rdi, r12
        call selector_checks
        mov [rbx + LD_FALLBACK_KNOWN], rax
        # the default function: where the dispatcher goes when no function
        # matches - a branch of its ifs without a function - if it's always
        # the same place (not if there's a receive function for no
        # calldata, or if the dispatcher reverts in some cases itself: the
        # default function is then all of the dispatcher)
        mov qword ptr [rsp + FF_DEFAULT], 0
        cmp qword ptr [r13 + VEC_LEN], 0
        je 6f
        mov rdi, r12
        call find_default
        mov [rsp + FF_DEFAULT], rax
6:      lea rdi, [rip + .Ls_fallback]
        call str_intern_c
        mov [rsp + FF_HASH], rax
        mov rdi, r14
        mov rsi, rax
        call vec_push
        mov rax, [rsp + FF_DEFAULT]
        test rax, rax
        jz 7f
        mov rdi, [rsp + FF_TARGETS]     # (target, stack)
        mov rsi, [rsp + FF_HASH]
        mov rdx, rax
        call map_put
        # its entries: those of the paths to its jumpdest
        call vec_new
        mov [rsp + FF_LINE], rax
        mov rax, [rsp + FF_DEFAULT]
        mov rdi, [rax + N_DATA]
        sar rdi, 1
        call str_of_int
        mov rdx, rax
        xor edi, edi
        xor esi, esi
        push rdx
        push rdx
        call mk_tuple
        pop rdx
        pop rdx
        mov rcx, rax
        mov rdi, r12
        mov esi, 1                      # the jd lines of the target
        mov r8, [rsp + FF_LINE]
        call entry_paths
        mov qword ptr [rsp + FF_I], 0
71:     mov rcx, [rsp + FF_I]
        mov rax, [rsp + FF_LINE]
        cmp rcx, [rax + VEC_LEN]
        jae 8f
        inc qword ptr [rsp + FF_I]
        mov rax, [rax + VEC_DATA]
        mov rax, [rax + rcx*8]
        mov rdx, [rax + N_DATA]
        mov rdi, [rsp + FF_ENTRIES]
        mov rsi, [rsp + FF_HASH]
        call entries_add
        jmp 71b
7:      # all of the dispatcher, from 0
        xor edi, edi
        xor esi, esi
        call mk_tuple
        mov rsi, rax
        mov edi, 1
        call mk2
        mov rdi, [rsp + FF_TARGETS]
        mov rsi, [rsp + FF_HASH]
        mov rdx, rax
        call map_put
        xor edi, edi                    # entries["_fallback"] = [()]
        xor esi, esi
        call mk_tuple
        mov rdx, rax
        mov rdi, [rsp + FF_ENTRIES]
        mov rsi, [rsp + FF_HASH]
        call entries_add
8:      # the list of (hash, target, stack)
        call vec_new
        mov r13, rax
        xor ecx, ecx
9:      cmp rcx, [r14 + VEC_LEN]
        jae 10f
        mov [rsp + FF_I], rcx
        mov rax, [r14 + VEC_DATA]
        mov rsi, [rax + rcx*8]
        mov [rsp + FF_LINE], rsi
        mov rdi, [rsp + FF_TARGETS]
        call map_get
        mov rdx, [rax + N_DATA + 8]
        mov rsi, [rax + N_DATA]
        mov rdi, [rsp + FF_LINE]
        call mk3
        mov rdi, r13
        mov rsi, rax
        call vec_push
        mov rcx, [rsp + FF_I]
        inc rcx
        jmp 9b
10:     mov rdi, r13
        call vec_to_list
        mov [rbx + LD_FUNCS], rax
        # the entries: a tuple of (hash, list of entries)
        mov rdi, [rsp + FF_ENTRIES]
        call entries_value
        mov [rbx + LD_ENTRIES], rax
        add rsp, 64
        LEAVE
ENDF loader_find_functions

# entries_add(od, hash, entry): python's entries.setdefault(hash, []).append(entry)
FUNC entries_add
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        call od_get
        test rax, rax
        jnz 1f
        call vec_new
        mov r14, rax
        mov rdi, rbx
        mov rsi, r12
        mov rdx, rax
        call od_put
        mov rax, r14
1:      mov rdi, rax
        mov rsi, r13
        call vec_push
        LEAVE
ENDF entries_add

# entries_value(od) -> tuple of (hash, list of entries)
FUNC entries_value
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
        call od_val
        mov rdi, rax
        call vec_to_list
        mov r14, rax
        mov rdi, rbx
        mov rsi, r13
        call od_key
        mov rdi, rax
        mov rsi, r14
        call mk2
        mov rdi, r12
        mov rsi, rax
        call vec_push
        inc r13
        jmp 1b
2:      mov rdi, r12
        call vec_to_tuple
        LEAVE
ENDF entries_value

# loader_entries(loader, hash) -> rax: the entries of the function (a
# list), 0 when there are none (python's loader.entries.get(hash): None)
FUNC loader_entries
        mov rax, [rdi + LD_ENTRIES]
        test rax, rax
        jz 2f
        xor ecx, ecx
1:      cmp ecx, [rax + N_AUX]
        jae 2f
        mov rdx, [rax + N_DATA + rcx*8]
        inc ecx
        cmp [rdx + N_DATA], rsi
        jne 1b
        mov rax, [rdx + N_DATA + 8]
        ret
2:      xor eax, eax
        ret
ENDF loader_entries

# padded_hex8(hash) -> string: python's padded_hex(hash, 8) - '0x' and 8
# hex digits (of a negative one, a word written as the negative number it
# is, the 8 lowest digits of the word), or '????????' when there are more
FUNC padded_hex8
        ENTER
        sub rsp, 32
        mov rbx, rdi
        call int_sign
        cmp eax, -1
        jne 2f
        mov rdi, rbx
        mov esi, 32
        call int_mod_2exp
        mov rbx, rax
2:      test bl, 1
        jz 1f
        mov rcx, rbx
        sar rcx, 1
        mov rax, rcx
        shr rax, 32
        jnz 1f
        mov rdi, rsp
        mov esi, 32
        lea rdx, [rip + .Ls_hash_fmt]
        xor eax, eax
        call snprintf@PLT
        mov rdi, rsp
        call str_intern_c
        add rsp, 32
        LEAVE
1:      lea rdi, [rip + .Ls_unknown_hash]
        call str_intern_c
        add rsp, 32
        LEAVE
ENDF padded_hex8

# walk_collect(exp, pred, out): the sub-expressions (tuples and lists,
# the expression itself included) for which pred(exp) is true, in the
# order of a depth-first walk (find_f_list)
FUNC walk_collect
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        IS_SEQ_RDI
        test eax, eax
        jz 3f
        mov rdi, rbx
        call r12
        test eax, eax
        jz 1f
        mov rdi, r13
        mov rsi, rbx
        call vec_push
1:      xor r14d, r14d
2:      cmp r14d, [rbx + N_AUX]
        jae 3f
        mov rdi, [rbx + N_DATA + r14*8]
        mov rsi, r12
        mov rdx, r13
        call walk_collect
        inc r14
        jmp 2b
3:      LEAVE
ENDF walk_collect

# walk_find(exp, pred) -> rax: the first sub-expression for which pred
# returns a value (non-zero), depth first (find_f); 0 if none
FUNC walk_find
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        IS_SEQ_RDI
        test eax, eax
        jz 3f
        mov rdi, rbx
        call r12
        test rax, rax
        jnz 4f
        xor r14d, r14d
2:      cmp r14d, [rbx + N_AUX]
        jae 3f
        mov rdi, [rbx + N_DATA + r14*8]
        mov rsi, r12
        call walk_find
        test rax, rax
        jnz 4f
        inc r14
        jmp 2b
3:      xor eax, eax
4:      LEAVE
ENDF walk_find

# is_seq(v) -> eax: a tuple or a list
FUNC is_seq
        xor eax, eax
        test dil, 1
        jnz 1f
        test rdi, rdi
        jz 1f
        mov ecx, [rdi + N_KIND]
        cmp ecx, K_TUPLE
        sete al
        cmp ecx, K_LIST
        sete cl
        or al, cl
        movzx eax, al
1:      ret
ENDF is_seq

# pred_funccall(exp) -> eax: ('funccall', hash, target, stack)
FUNC pred_funccall
        ENTER
        mov rbx, rdi
        call opcode_of
        cmp eax, OP_FUNCCALL
        jne 1f
        xor eax, eax
        cmp dword ptr [rbx + N_AUX], 4
        sete al
        LEAVE
1:      xor eax, eax
        LEAVE
ENDF pred_funccall

# branch_ends_funccall(branch) -> eax: the branch (a sequence) isn't empty
# and its last line is a ('funccall', hash, target, stack)
FUNC branch_ends_funccall
        ENTER
        mov rbx, rdi
        call is_seq
        test eax, eax
        jz 1f
        mov ecx, [rbx + N_AUX]
        test ecx, ecx
        jz 1f
        mov rdi, [rbx + N_DATA + rcx*8 - 8]
        call pred_funccall
        LEAVE
1:      xor eax, eax
        LEAVE
ENDF branch_ends_funccall

# pred_selector_if(exp) -> eax: an ('if', cond, if_true, if_false) one of
# whose branches ends with a function call
FUNC pred_selector_if
        ENTER
        mov rbx, rdi
        OPCODE_OF_RDI
        cmp eax, OP_IF
        jne 1f
        cmp dword ptr [rbx + N_AUX], 4
        jne 1f
        mov rdi, [rbx + N_DATA + 16]
        call branch_ends_funccall
        test eax, eax
        jnz 2f
        mov rdi, [rbx + N_DATA + 24]
        call branch_ends_funccall
        LEAVE
1:      xor eax, eax
        LEAVE
2:      mov eax, 1
        LEAVE
ENDF pred_selector_if

# selector_checks(trace) -> tuple: what holds in the default function - for
# every if one of whose branches calls a function at its end, the
# condition of the other (is_zero(cond) when it's the true branch, else
# cond)
FUNC selector_checks
        ENTER
        mov r12, rdi
        call vec_new
        mov rbx, rax                    # the ifs
        mov rdi, r12
        lea rsi, [rip + pred_selector_if]
        mov rdx, rbx
        call walk_collect
        call vec_new
        mov r13, rax                    # the facts
        xor r14d, r14d
1:      cmp r14, [rbx + VEC_LEN]
        jae 2f
        mov rax, [rbx + VEC_DATA]
        mov r12, [rax + r14*8]
        mov rdi, [r12 + N_DATA + 16]
        call branch_ends_funccall
        mov rdi, [r12 + N_DATA + 8]     # the condition
        test eax, eax
        jz 3f
        call is_zero
        mov rdi, rax
3:      mov rsi, rdi
        mov rdi, r13
        call vec_push
        inc r14
        jmp 1b
2:      mov rdi, r13
        call vec_to_tuple
        LEAVE
ENDF selector_checks

# has_funccall(exp) -> eax
FUNC has_funccall
        ENTER
        mov rbx, rdi
        call vec_new
        mov r12, rax
        mov rdi, rbx
        lea rsi, [rip + pred_funccall]
        mov rdx, r12
        call walk_collect
        xor eax, eax
        cmp qword ptr [r12 + VEC_LEN], 0
        setne al
        LEAVE
ENDF has_funccall

# find_default(trace) -> rax: python's default - (target, stack) where the
# default function starts, or 0: for every if on the dispatch (is_dispatch
# of its condition), each branch without a function call gives (int(jd),
# stack) when it starts with ('jd', jd, stack), None otherwise; the first
# of them when they all start at the same place
FUNC find_default
        ENTER
        sub rsp, 16
        mov r12, rdi
        call vec_new
        mov rbx, rax                    # the ifs
        mov rdi, r12
        lea rsi, [rip + pred_dispatch_if]
        mov rdx, rbx
        call walk_collect
        mov qword ptr [rsp], 0          # the first start
        mov qword ptr [rsp + 8], 0      # how many
        xor r13d, r13d
1:      cmp r13, [rbx + VEC_LEN]
        jae 5f
        mov rax, [rbx + VEC_DATA]
        mov r14, [rax + r13*8]
        inc r13
        mov rdi, [r14 + N_DATA + 16]
        call .Lfd_branch
        mov rdi, [r14 + N_DATA + 24]
        call .Lfd_branch
        jmp 1b
5:      xor eax, eax
        cmp qword ptr [rsp + 8], 0
        je 6f
        mov rax, [rsp]
        cmp rax, 1                      # (a None among them)
        jne 6f
        xor eax, eax
6:      add rsp, 16
        LEAVE
# local: a branch rdi -> its start, compared with the first: [rsp + 8]
# (the caller's [rsp]) 0 when they differ (or a None)
.Lfd_branch:
        push r12
        push r13
        sub rsp, 8
        mov r12, rdi
        call has_funccall
        test eax, eax
        jnz 9f                          # (a branch with functions: nothing)
        mov rdi, r12
        call branch_jd                  # (target, stack), or 0 for None
        test rax, rax
        jnz 2f
        mov eax, 1                      # None
2:      inc qword ptr [rsp + 24 + 8 + 8]        # how many
        cmp qword ptr [rsp + 24 + 8 + 8], 1
        jne 3f
        mov [rsp + 24 + 8], rax         # the first
        jmp 9f
3:      mov rcx, [rsp + 24 + 8]
        cmp rcx, 1
        je 9f                           # (the first a None: no default)
        test rcx, rcx
        jz 9f                           # (they differ already)
        cmp rax, 1
        je 4f                           # a None: they differ
        mov rdx, [rcx + N_DATA]         # the same target? (s and s[0])
        cmp rdx, [rax + N_DATA]
        je 9f
4:      mov qword ptr [rsp + 24 + 8], 0
        mov qword ptr [rsp + 24 + 8 + 8], 2
9:      add rsp, 8
        pop r13
        pop r12
        ret
ENDF find_default

# pred_dispatch_if(exp) -> eax: an ('if', cond, if_true, if_false) on the
# dispatch (is_dispatch of cond)
FUNC pred_dispatch_if
        ENTER
        mov rbx, rdi
        OPCODE_OF_RDI
        cmp eax, OP_IF
        jne 1f
        cmp dword ptr [rbx + N_AUX], 4
        jne 1f
        mov rdi, [rbx + N_DATA + 8]
        call is_dispatch
        LEAVE
1:      xor eax, eax
        LEAVE
ENDF pred_dispatch_if

# branch_jd(branch) -> rax: when the branch starts with ('jd', s, stack),
# (int(s), stack); else 0
FUNC branch_jd
        ENTER
        mov rbx, rdi
        call is_seq
        test eax, eax
        jz 1f
        cmp dword ptr [rbx + N_AUX], 0
        je 1f
        mov r12, [rbx + N_DATA]         # the first line
        mov rdi, r12
        mov esi, OP_JD
        mov edx, 3
        call is_op_n
        test eax, eax
        jz 1f
        mov rdi, [r12 + N_DATA + 8]
        test dil, 1
        jnz 1f
        cmp dword ptr [rdi + N_KIND], K_STR
        jne 1f
        lea rdi, [rdi + N_DATA + 4]
        xor esi, esi
        mov edx, 10
        call strtol@PLT
        mov rdi, rax
        TAG rdi
        mov rsi, [r12 + N_DATA + 16]
        call mk2
        LEAVE
1:      xor eax, eax
        LEAVE
ENDF branch_jd

        .section .note.GNU-stack,"",@progbits
