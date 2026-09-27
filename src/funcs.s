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

# loader_find_functions(loader, timeout_ns): fills LD_FUNCS with the list
# of (hash, target, stack) - hash being the padded hex string, or
# "_fallback" - and LD_FALLBACK_KNOWN
FUNC loader_find_functions
        ENTER
        sub rsp, 48
        mov rbx, rdi
        mov [rsp + 40], rsi
        mov rdi, rbx
        mov esi, 1
        call vm_new
        xor edi, edi
        xor esi, esi
        call mk_tuple                   # ()
        mov rsi, rax
        mov rdx, rax
        mov edi, 1                      # start = 0
        mov rcx, [rsp + 40]
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
        mov [rsp], rax                  # hash -> (target, stack)
        xor ecx, ecx
1:      cmp rcx, [r13 + VEC_LEN]
        jae 3f
        mov [rsp + 8], rcx
        mov rax, [r13 + VEC_DATA]
        mov rax, [rax + rcx*8]          # ('funccall', hash, target, stack)
        mov [rsp + 16], rax
        mov rdi, [rax + N_DATA + 8]
        call padded_hex8
        mov [rsp + 24], rax
        mov rdi, [rsp]
        mov rsi, rax
        call map_get
        test rax, rax
        jnz 2f
        mov rdi, r14
        mov rsi, [rsp + 24]
        call vec_push
2:      mov rax, [rsp + 16]
        mov rdi, [rax + N_DATA + 16]
        mov rsi, [rax + N_DATA + 24]
        call mk2
        mov rdi, [rsp]
        mov rsi, [rsp + 24]
        mov rdx, rax
        call map_put
        mov rcx, [rsp + 8]
        inc rcx
        jmp 1b
3:      # what's known in the default function: no selector matched
        mov rdi, r12
        call selector_checks
        mov [rbx + LD_FALLBACK_KNOWN], rax
        # the default function: where the dispatcher goes when nothing
        # matched, when there are functions at all
        mov qword ptr [rsp + 32], 1     # target 0
        cmp qword ptr [r13 + VEC_LEN], 0
        je 4f
        mov rdi, r12
        call find_default
        test rax, rax
        jz 4f
        mov [rsp + 32], rax
4:      lea rdi, [rip + .Ls_fallback]
        call str_intern_c
        mov [rsp + 24], rax
        mov rdi, r14
        mov rsi, rax
        call vec_push
        xor edi, edi
        xor esi, esi
        call mk_tuple
        mov rsi, rax
        mov rdi, [rsp + 32]
        call mk2
        mov rdi, [rsp]
        mov rsi, [rsp + 24]
        mov rdx, rax
        call map_put
        # the list of (hash, target, stack)
        call vec_new
        mov r13, rax
        xor ecx, ecx
5:      cmp rcx, [r14 + VEC_LEN]
        jae 6f
        mov [rsp + 8], rcx
        mov rax, [r14 + VEC_DATA]
        mov rsi, [rax + rcx*8]
        mov [rsp + 16], rsi
        mov rdi, [rsp]
        call map_get
        mov rdx, [rax + N_DATA + 8]
        mov rsi, [rax + N_DATA]
        mov rdi, [rsp + 16]
        call mk3
        mov rdi, r13
        mov rsi, rax
        call vec_push
        mov rcx, [rsp + 8]
        inc rcx
        jmp 5b
6:      mov rdi, r13
        call vec_to_list
        mov [rbx + LD_FUNCS], rax
        add rsp, 48
        LEAVE
ENDF loader_find_functions

# padded_hex8(hash) -> string: '0x' + 8 hex digits, or '????????' when
# it doesn't fit
FUNC padded_hex8
        ENTER
        sub rsp, 32
        test dil, 1
        jz 1f
        mov rcx, rdi
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
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        call is_seq
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
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call is_seq
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

# pred_selector_if(exp) -> eax: ('if', cond, if_true, _) whose if_true
# ends with a function call
FUNC pred_selector_if
        ENTER
        mov rbx, rdi
        call opcode_of
        cmp eax, OP_IF
        jne 1f
        cmp dword ptr [rbx + N_AUX], 4
        jne 1f
        mov rdi, [rbx + N_DATA + 16]
        call is_seq
        test eax, eax
        jz 1f
        mov rdi, [rbx + N_DATA + 16]
        mov ecx, [rdi + N_AUX]
        test ecx, ecx
        jz 1f
        mov rdi, [rdi + N_DATA + rcx*8 - 8]
        call pred_funccall
        LEAVE
1:      xor eax, eax
        LEAVE
ENDF pred_selector_if

# selector_checks(trace) -> tuple: is_zero(cond) for every if whose true
# branch is a function call (they all fail in the default function)
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
        mov rax, [rax + r14*8]
        mov rdi, [rax + N_DATA + 8]     # the condition
        call is_zero
        mov rdi, r13
        mov rsi, rax
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

# find_default(trace) -> rax: the target of the default function (tagged),
# or 0 when there's no telling
FUNC find_default
        lea rsi, [rip + pred_default]
        jmp walk_find
ENDF find_default

# pred_default(exp) -> rax: for an if on the selector - ('if', cond,
# if_true, if_false) with ('cd', 0) in cond - the jumpdest the branch
# without function calls starts with, if it does; else 0
FUNC pred_default
        ENTER
        mov rbx, rdi
        call opcode_of
        cmp eax, OP_IF
        jne 1f
        cmp dword ptr [rbx + N_AUX], 4
        jne 1f
        LOADS rdi, CD
        mov esi, 1
        call mk2
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, rax
        call contains_value
        test eax, eax
        jz 1f
        mov rdi, [rbx + N_DATA + 24]    # if_false
        call branch_jd
        test rax, rax
        jnz 2f
        mov rdi, [rbx + N_DATA + 16]    # if_true
        call branch_jd
2:      LEAVE
1:      xor eax, eax
        LEAVE
ENDF pred_default

# branch_jd(branch) -> rax: when the branch has no function call and
# starts with ('jd', s), the tagged int(s); else 0
FUNC branch_jd
        ENTER
        mov rbx, rdi
        call has_funccall
        test eax, eax
        jnz 1f
        mov rdi, rbx
        call is_seq
        test eax, eax
        jz 1f
        cmp dword ptr [rbx + N_AUX], 0
        je 1f
        mov r12, [rbx + N_DATA]         # the first line
        mov rdi, r12
        call opcode_of
        cmp eax, OP_JD
        jne 1f
        cmp dword ptr [r12 + N_AUX], 2
        jne 1f
        mov rdi, [r12 + N_DATA + 8]
        test dil, 1
        jnz 1f
        cmp dword ptr [rdi + N_KIND], K_STR
        jne 1f
        lea rdi, [rdi + N_DATA + 4]
        xor esi, esi
        mov edx, 10
        call strtol@PLT
        TAG rax
        LEAVE
1:      xor eax, eax
        LEAVE
ENDF branch_jd

        .section .note.GNU-stack,"",@progbits
