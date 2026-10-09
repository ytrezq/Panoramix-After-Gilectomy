# What the simplifier knows of the variables and the words of a trace
# while it simplifies it (port of simplify.py's variable_values,
# small_words, immutable, spine, reverts, goes_elsewhere and
# memory_ranges): what each variable is set to, anywhere - its value is one
# of these - and the words the contract is given that are small, wherever
# they are (see algebra.set_variables, ranges.s).

.include "defs.inc"

        .section .rodata
.Ls_sv_index:   .asciz "tuple index out of range"
.Ls_sv_type:    .asciz "can only concatenate list (not another type) to list"
.Ls_calldatasize: .asciz "calldatasize"
        .text

.macro B reg, n
        mov \reg, [rsp + 8*(\n)]
.endm

# --- what the variables are set to ---

# collect_setvar(e, arg, out): walk_collect_flag's f - a ('setvar', name,
# value) of three elements
FUNC collect_setvar
        ENTER
        mov rbx, rdi
        mov r12, rdx
        mov esi, OP_SETVAR
        mov edx, 3
        call is_op_n
        test eax, eax
        jz 1f
        mov rdi, r12
        mov rsi, rbx
        call vec_push
1:      LEAVE
ENDF collect_setvar

# variable_values(trace) -> rax: python's variable_values - {name: [values]}:
# what each variable is set to in the trace, anywhere. A tuple of (name,
# values) pairs, the names in the order they first come (set_variables'
# vars).
FUNC variable_values
        ENTER
        sub rsp, 32
        mov rbx, rdi
        call vec_new
        mov r12, rax                    # the setvars, in order
        mov rdi, rbx
        lea rsi, [rip + collect_setvar]
        mov rdx, r12
        mov rcx, HF_SETVAR
        call walk_collect_flag
        call vec_new
        mov r13, rax                    # the names, in order
        call vec_new
        mov [rsp], rax                  # their values: a vec each
        call emap_new
        mov [rsp + 8], rax              # name -> its index + 1
        xor r14d, r14d
1:      cmp r14, [r12 + VEC_LEN]
        jae 3f
        mov rax, [r12 + VEC_DATA]
        mov rax, [rax + r14*8]
        inc r14
        mov [rsp + 16], rax
        mov rdi, [rsp + 8]
        mov rsi, [rax + N_DATA + 8]
        call emap_get
        test rax, rax
        jnz 2f
        mov rax, [rsp + 16]             # a name first seen
        mov rdi, r13
        mov rsi, [rax + N_DATA + 8]
        call vec_push
        call vec_new
        mov rdi, [rsp]
        mov rsi, rax
        call vec_push
        mov rax, [rsp + 16]
        mov rdi, [rsp + 8]
        mov rsi, [rax + N_DATA + 8]
        mov rdx, [r13 + VEC_LEN]
        call emap_put
        mov rax, [r13 + VEC_LEN]
2:      dec rax
        mov rcx, [rsp]
        mov rcx, [rcx + VEC_DATA]
        mov rdi, [rcx + rax*8]
        mov rax, [rsp + 16]
        mov rsi, [rax + N_DATA + 16]
        call vec_push
        jmp 1b
3:      # the (name, values) pairs
        call vec_new
        mov [rsp + 16], rax
        xor r14d, r14d
4:      cmp r14, [r13 + VEC_LEN]
        jae 5f
        mov rax, [rsp]
        mov rax, [rax + VEC_DATA]
        mov rdi, [rax + r14*8]
        call vec_to_tuple
        mov rsi, rax
        mov rax, [r13 + VEC_DATA]
        mov rdi, [rax + r14*8]
        inc r14
        call mk2
        mov rdi, [rsp + 16]
        mov rsi, rax
        call vec_push
        jmp 4b
5:      mov rdi, [rsp + 16]
        call vec_to_tuple
        add rsp, 32
        LEAVE
ENDF variable_values

# values_map(vars) -> rax: an emap {name: values} of variable_values'
# pairs (as set_variables makes it)
FUNC values_map
        ENTER
        mov rbx, rdi
        call emap_new
        mov r12, rax
        xor r13d, r13d
1:      cmp r13d, [rbx + N_AUX]
        jae 2f
        mov rax, [rbx + N_DATA + r13*8]
        inc r13d
        mov rdi, r12
        mov rsi, [rax + N_DATA]
        mov rdx, [rax + N_DATA + 8]
        call emap_put
        jmp 1b
2:      mov rax, r12
        LEAVE
ENDF values_map

# immutable(exp, values, seen) -> eax: python's immutable - exp is the same
# word wherever it is in the trace: made of numbers and of the calldata,
# computed from them (algebra.COMPUTED), or a variable set to one of these
# once (values: an emap {name: values}; seen: a vec of the names being
# looked at). Not what's read where it says - storage, memory, what a call
# returned, the same every time only until it changes.
FUNC immutable
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        call is_int
        test eax, eax
        jnz 8f
        mov rdi, rbx
        call is_str
        test eax, eax
        jz 1f
        lea rdi, [rbx + N_DATA + 4]
        lea rsi, [rip + .Ls_calldatasize]
        call strcmp@PLT
        test eax, eax
        jz 8f
        jmp 9f
1:      mov rdi, rbx
        OPCODE_OF_RDI
        mov r14d, eax
        cmp eax, OP_CD
        je 2f
        cmp eax, OP_CALL_DATA
        je 2f
        mov edi, eax
        call is_computed_op
        test eax, eax
        jz 4f
2:      mov r14d, 1                     # every operand
3:      cmp r14d, [rbx + N_AUX]
        jae 8f
        mov rdi, [rbx + N_DATA + r14*8]
        inc r14d
        mov rsi, r12
        mov rdx, r13
        call immutable
        test eax, eax
        jnz 3b
        jmp 9f
4:      cmp r14d, OP_VAR
        jne 9f
        cmp dword ptr [rbx + N_AUX], 2
        jne 9f
        mov rdi, r13                    # a variable set once, to what is
        mov rsi, [rbx + N_DATA + 8]
        call vec_contains
        test eax, eax
        jnz 9f
        mov rdi, r12
        mov rsi, [rbx + N_DATA + 8]
        call emap_get
        test rax, rax
        jz 9f
        cmp dword ptr [rax + N_AUX], 1
        jne 9f
        mov r14, [rax + N_DATA]
        mov rdi, r13
        mov rsi, [rbx + N_DATA + 8]
        call vec_push
        mov rdi, r14
        mov rsi, r12
        mov rdx, r13
        call immutable
        dec qword ptr [r13 + VEC_LEN]   # (seen + (name,): for that one)
        LEAVE
8:      mov eax, 1
        LEAVE
9:      xor eax, eax
        LEAVE
ENDF immutable

# --- what every execution goes through ---

        OPSET_MEMBER sv_exits, OP_RETURN
        OPSET_MEMBER sv_exits, OP_STOP
        OPSET_MEMBER sv_exits, OP_SELFDESTRUCT
        OPSET_MEMBER sv_exits, OP_GOTO
        OPSET_MEMBER sv_exits, OP_CONTINUE
        OPSET_MEMBER sv_exits, OP_UNDEFINED
        OPSET_END sv_exits, OP_COUNT

        OPSET_MEMBER sv_reverts, OP_REVERT
        OPSET_MEMBER sv_reverts, OP_INVALID
        OPSET_MEMBER sv_reverts, OP_ASSERT_FAIL
        OPSET_END sv_reverts, OP_COUNT

# goes_elsewhere(trace, jd) -> eax: python's goes_elsewhere - a path of the
# trace may end other than by reverting, or by going on with what follows
# it: a return, a jump back (EXITS, anywhere in it) - but a continue of the
# loop of jd (NIL: None), the trace being its body
FUNC goes_elsewhere
        STACK_CHECK
        test dil, 1
        jnz 8f
        test rdi, rdi
        jz 8f
        mov eax, [rdi + N_KIND]
        cmp eax, K_TUPLE
        je 1f
        cmp eax, K_LIST
        jne 8f
1:      ENTER
        mov rbx, rdi
        mov r12, rsi
        cmp eax, K_TUPLE
        jne 3f
        OPCODE_OF_RDI
        IN_OPSET sv_exits, rax
        je 3f
        cmp eax, OP_CONTINUE
        jne 9f
        cmp dword ptr [rbx + N_AUX], 2
        jb 9f
        cmp r12, [rbx + N_DATA + 8]
        jne 9f                          # (a continue of another loop)
3:      xor r13d, r13d
4:      cmp r13d, [rbx + N_AUX]
        jae 7f
        mov rdi, [rbx + N_DATA + r13*8]
        inc r13d
        mov rsi, r12
        call goes_elsewhere
        test eax, eax
        jz 4b
9:      mov eax, 1
        LEAVE
7:      xor eax, eax
        LEAVE
8:      xor eax, eax
        ret
ENDF goes_elsewhere

# trace_reverts(trace) -> eax: python's simplify.reverts - the trace reverts (or runs an
# invalid opcode), on every path
FUNC trace_reverts
        STACK_CHECK
        ENTER
        mov rbx, rdi
        call seq_last
        test rax, rax
        jz 9f
        mov r12, rax
        mov rdi, rax
        OPCODE_OF_RDI
        cmp eax, OP_IF
        jne 1f
        cmp dword ptr [r12 + N_AUX], 4
        jne 1f
        mov rdi, [r12 + N_DATA + 16]
        call trace_reverts
        test eax, eax
        jz 9f
        mov rdi, [r12 + N_DATA + 24]
        call trace_reverts
        test eax, eax
        jz 9f
        jmp 2f
1:      IN_OPSET sv_reverts, rax
        je 9f
2:      # and nothing before goes elsewhere
        xor r13d, r13d
3:      mov eax, [rbx + N_AUX]
        dec eax
        cmp r13d, eax
        jae 8f
        mov rdi, [rbx + N_DATA + r13*8]
        inc r13d
        xor esi, esi
        call goes_elsewhere
        test eax, eax
        jz 3b
9:      xor eax, eax
        LEAVE
8:      mov eax, 1
        LEAVE
ENDF trace_reverts

# spine_into(trace, lines, checks): python's spine - what every execution
# of the trace that doesn't revert goes through, in order: the lines it
# runs (or the condition of an if, of a loop) pushed on lines, the
# conditions that hold from there on - where an if's other branch reverts:
# a check - on checks. Until an execution may go elsewhere: a return in a
# branch, a loop back...
FUNC spine_into
        STACK_CHECK
        ENTER
        sub rsp, 32
        .set SP_LINES, 0
        .set SP_CHECKS, 8
        .set SP_NZ, 16
        mov rbx, rdi
        mov [rsp + SP_LINES], rsi
        mov [rsp + SP_CHECKS], rdx
        IS_SEQ_RDI
        test eax, eax
        jz .Lsp_type
        xor r13d, r13d
.Lsp_line:
        cmp r13d, [rbx + N_AUX]
        jae .Lsp_done
        mov r14, [rbx + N_DATA + r13*8]
        inc r13d
        mov rdi, r14
        OPCODE_OF_RDI
        cmp eax, OP_IF
        je .Lsp_if
        cmp eax, OP_WHILE
        je .Lsp_while
        cmp eax, OP_LABEL
        je .Lsp_done
.Lsp_other:
        mov rdi, [rsp + SP_LINES]
        mov rsi, r14
        call vec_push
        mov rdi, r14
        OPCODE_OF_RDI
        IN_OPSET sv_exits, rax
        jne .Lsp_done
        IN_OPSET sv_reverts, rax
        jne .Lsp_done
        jmp .Lsp_line
.Lsp_if:
        cmp dword ptr [r14 + N_AUX], 4
        jne .Lsp_other
        mov rdi, [rsp + SP_LINES]
        mov rsi, [r14 + N_DATA + 8]
        call vec_push
        mov rdi, [r14 + N_DATA + 8]
        call is_zero
        mov [rsp + SP_NZ], rax
        # a branch that reverts: the other's condition holds after it
        mov rdi, [r14 + N_DATA + 16]
        call trace_reverts
        test eax, eax
        jz 1f
        mov rdi, [rsp + SP_CHECKS]
        mov rsi, [rsp + SP_NZ]
        call vec_push
        mov r12, [r14 + N_DATA + 24]    # other
        jmp 2f
1:      mov rdi, [r14 + N_DATA + 24]
        call trace_reverts
        test eax, eax
        jz 3f
        mov rdi, [rsp + SP_CHECKS]
        mov rsi, [r14 + N_DATA + 8]
        call vec_push
        mov r12, [r14 + N_DATA + 16]
2:      # spine(other + trace[idx + 1:])
        mov rdi, r12
        IS_SEQ_RDI
        test eax, eax
        jz .Lsp_type
        mov rdi, rbx
        mov rsi, r13
        call list_from
        mov rsi, rax
        mov rdi, r12
        call list_concat
        mov rdi, rax
        mov rsi, [rsp + SP_LINES]
        mov rdx, [rsp + SP_CHECKS]
        call spine_into
        jmp .Lsp_done
3:      mov rdi, [r14 + N_DATA + 16]
        xor esi, esi
        call goes_elsewhere
        test eax, eax
        jnz .Lsp_done
        mov rdi, [r14 + N_DATA + 24]
        xor esi, esi
        call goes_elsewhere
        test eax, eax
        jnz .Lsp_done
        jmp .Lsp_line
.Lsp_while:
        cmp dword ptr [r14 + N_AUX], 5
        jne .Lsp_other
        # (run 0 times or more: what follows is, if it's left at its end)
        mov rdi, [rsp + SP_LINES]
        mov rsi, [r14 + N_DATA + 8]
        call vec_push
        mov rdi, [r14 + N_DATA + 16]
        mov rsi, [r14 + N_DATA + 24]
        call goes_elsewhere
        test eax, eax
        jnz .Lsp_done
        jmp .Lsp_line
.Lsp_done:
        add rsp, 32
        LEAVE
.Lsp_type:
        mov edi, E_TYPE
        lea rsi, [rip + .Ls_sv_type]
        call err_throw
ENDF spine_into

# --- the words that are small ---

# collect_memory_range(e, arg, out): walk_collect_lines' f - python's
# memory_ranges: the range of memory e reads or writes, if it does
FUNC collect_memory_range
        ENTER
        mov rbx, rdi
        mov r12, rdx
        OPCODE_OF_RDI
        cmp eax, OP_MEM
        je 1f
        cmp eax, OP_SETMEM
        jne 9f
1:      cmp dword ptr [rbx + N_AUX], 2
        jb 9f
        mov rdi, [rbx + N_DATA + 8]
        mov esi, OP_RANGE
        mov edx, 3
        call is_op_n
        test eax, eax
        jz 9f
        mov rdi, r12
        mov rsi, [rbx + N_DATA + 8]
        call vec_push
9:      LEAVE
ENDF collect_memory_range

# the state of small_words, on its frame (rbx: the frame)
        .set SW_VALUES, 0               # the variables' emap
        .set SW_RES, 8                  # the words found small, in order (a vec)
        .set SW_MAP, 16                 # ... and as an emap (unchecked's small)
        .set SW_SEEN, 24                # immutable's seen (a vec)
        .set SW_LINES, 32
        .set SW_CHECKS, 40
        .set SW_I, 48
        .set SW_CHANGED, 56
        .set SW_TMP, 64
        .set SW_ONCE, 72
        .set SW_J, 80
        .set SW_VARS, 88                # variable_values' pairs
        .set SW_SIZE, 96

# sw_small(x, frame): python's small(x) - a word (not a sum, nor a product,
# see algebra.value_range) that's the same wherever it is: small
FUNC sw_small
        ENTER
        mov rbx, rsi
        mov r12, rdi
        call is_int
        test eax, eax
        jnz 9f
        mov rdi, r12
        OPCODE_OF_RDI
        cmp eax, OP_ADD
        je 9f
        cmp eax, OP_MUL
        je 9f
        mov rdi, [rbx + SW_SEEN]
        mov qword ptr [rdi + VEC_LEN], 0
        mov rdi, r12
        mov rsi, [rbx + SW_VALUES]
        mov rdx, [rbx + SW_SEEN]
        call immutable
        test eax, eax
        jz 9f
        mov rdi, [rbx + SW_MAP]
        mov rsi, r12
        call emap_get
        test rax, rax
        jnz 9f                          # (in the set already)
        mov rdi, [rbx + SW_MAP]
        mov rsi, r12
        mov edx, 1
        call emap_put
        mov rdi, [rbx + SW_RES]
        mov rsi, r12
        call vec_push
9:      LEAVE
ENDF sw_small

# small_words(trace, vars) -> rax: python's small_words - the words of the
# trace that are below 2**64 (see algebra.set_variables), a tuple. The
# others the contract is given (its params, what a call returned) may be
# anything: a param added to a pointer, unchecked, in assembly, may make an
# address wrap around 2**256. A word of the calldata, or computed from it
# (immutable), is small wherever it is when every execution that doesn't
# revert goes through what shows it (spine) - solc checks params before it
# uses them:
# - the size of a range of memory (`mem[a len x]`), the address of one of
#   a known size (`mem[x]`): no execution pays for that much memory - not a
#   sum, that may be small only modulo 2**256;
# - a check that it's below a number (solc's checks of the offsets and
#   lengths of params: `if x > 2**64 - 1: revert`), or below what's small
#   (an index, `require i < x`).
# vars: variable_values' pairs.
FUNC small_words
        ENTER
        sub rsp, SW_SIZE + MATCH_BINDINGS_SIZE
        mov rbx, rsp
        mov r12, rdi                    # the trace
        mov [rbx + SW_VARS], rsi
        mov rdi, rsi
        call values_map
        mov [rbx + SW_VALUES], rax
        call vec_new
        mov [rbx + SW_RES], rax
        call emap_new
        mov [rbx + SW_MAP], rax
        call vec_new
        mov [rbx + SW_SEEN], rax
        call vec_new
        mov [rbx + SW_LINES], rax
        call vec_new
        mov [rbx + SW_CHECKS], rax
        mov rdi, r12
        mov rsi, [rbx + SW_LINES]
        mov rdx, [rbx + SW_CHECKS]
        call spine_into
        # the ranges of memory of the lines: their sizes, and the addresses
        # of the ones of a known size
        call vec_new
        mov r13, rax
        mov rdi, [rbx + SW_LINES]
        call vec_to_list
        mov rdi, rax
        lea rsi, [rip + collect_memory_range]
        mov rdx, r13
        call walk_collect_lines
        xor r14d, r14d
1:      cmp r14, [r13 + VEC_LEN]
        jae 2f
        mov rax, [r13 + VEC_DATA]
        mov rax, [rax + r14*8]          # ('range', addr, size)
        inc r14
        mov [rbx + SW_TMP], rax
        mov rdi, [rax + N_DATA + 16]
        mov rsi, rbx
        call sw_small
        mov rax, [rbx + SW_TMP]
        mov rdi, [rax + N_DATA + 16]
        call is_int
        test eax, eax
        jz 1b
        mov rax, [rbx + SW_TMP]
        mov rdi, [rax + N_DATA + 16]
        call int_sign
        cmp eax, 0
        jle 1b
        mov rax, [rbx + SW_TMP]
        mov rdi, [rax + N_DATA + 8]
        mov rsi, rbx
        call sw_small
        jmp 1b
2:      # the checks: what they bound below 2**64
        mov qword ptr [rbx + SW_I], 0
3:      mov rcx, [rbx + SW_I]
        mov rax, [rbx + SW_CHECKS]
        cmp rcx, [rax + VEC_LEN]
        jae 5f
        mov rax, [rax + VEC_DATA]
        mov rdi, [rax + rcx*8]
        inc qword ptr [rbx + SW_I]
        call cond_bounds
        test rax, rax
        jz 3b
        mov r13, rax
        xor r14d, r14d
4:      cmp r14, [r13 + VEC_LEN]
        jae 3b
        mov rax, [r13 + VEC_DATA]
        mov rdi, [rax + r14*8 + 16]     # hi
        mov rsi, [rip + vr_memory_top_v]
        call int_cmp
        cmp eax, 0
        jg 41f
        mov rax, [r13 + VEC_DATA]
        mov rdi, [rax + r14*8]
        mov rsi, rbx
        call sw_small
41:     add r14, 3
        jmp 4b
5:      # below what's small: until nothing changes
        mov qword ptr [rbx + SW_CHANGED], 0
        mov qword ptr [rbx + SW_I], 0
6:      mov rcx, [rbx + SW_I]
        mov rax, [rbx + SW_CHECKS]
        cmp rcx, [rax + VEC_LEN]
        jae 69f
        mov rax, [rax + VEC_DATA]
        mov rdi, [rax + rcx*8]
        inc qword ptr [rbx + SW_I]
        PAT rsi, "(':op', ':x', ':y')"
        lea rdx, [rbx + SW_SIZE]
        call pat_match
        test eax, eax
        jz 6b
        mov rdi, [rbx + SW_SIZE]
        call str_id
        mov ecx, eax
        mov r13, [rbx + SW_SIZE + 8]    # below
        mov r14, [rbx + SW_SIZE + 16]   # above
        cmp ecx, OP_LT
        je 61f
        cmp ecx, OP_LE
        je 61f
        cmp ecx, OP_GT
        je 60f
        cmp ecx, OP_GE
        jne 6b
60:     xchg r13, r14
61:     mov rdi, [rbx + SW_MAP]
        mov rsi, r13
        call emap_get
        test rax, rax
        jnz 6b
        # is_small(above): a number up to 2**64 - 1, or not made of what
        # the contract is given unchecked
        mov rdi, r14
        call is_int
        test eax, eax
        jz 62f
        mov rdi, r14
        call int_sign
        test eax, eax
        js 6b
        mov rdi, r14
        mov rsi, [rip + vr_memory_top_v]
        call int_cmp
        cmp eax, 0
        jg 6b
        jmp 63f
62:     mov rdi, r14
        mov rsi, [rbx + SW_VALUES]
        mov rdx, [rbx + SW_MAP]
        call unchecked
        test eax, eax
        jnz 6b
63:     mov rdi, r13
        mov rsi, rbx
        call sw_small
        mov rdi, [rbx + SW_MAP]
        mov rsi, r13
        call emap_get
        test rax, rax
        jz 6b
        mov qword ptr [rbx + SW_CHANGED], 1
        jmp 6b
69:     cmp qword ptr [rbx + SW_CHANGED], 0
        jne 5b
        # (as they'll be once the variables set once are replaced by their
        # values, see cleanup_vars)
        call vec_new
        mov [rbx + SW_ONCE], rax
        mov r13, [rbx + SW_VARS]
        xor r14d, r14d
64:     cmp r14d, [r13 + N_AUX]
        jae 65f
        mov rax, [r13 + N_DATA + r14*8] # (name, values)
        inc r14d
        mov rcx, [rax + N_DATA + 8]
        cmp dword ptr [rcx + N_AUX], 1
        jne 64b
        mov [rbx + SW_TMP], rax
        mov rdi, [rbx + SW_ONCE]
        mov rsi, [rax + N_DATA]
        call vec_push
        mov rax, [rbx + SW_TMP]
        mov rcx, [rax + N_DATA + 8]
        mov rdi, [rbx + SW_ONCE]
        mov rsi, [rcx + N_DATA]
        call vec_push
        jmp 64b
65:     mov rax, [rbx + SW_ONCE]
        cmp qword ptr [rax + VEC_LEN], 0
        je 9f
        mov rax, [rbx + SW_RES]
        mov rcx, [rax + VEC_LEN]
        mov [rbx + SW_I], rcx           # (the ones found so far)
        mov qword ptr [rbx + SW_J], 0
7:      mov rcx, [rbx + SW_J]
        cmp rcx, [rbx + SW_I]
        jae 9f
        mov rax, [rbx + SW_RES]
        mov rax, [rax + VEC_DATA]
        mov r13, [rax + rcx*8]
        inc qword ptr [rbx + SW_J]
        mov r14d, 10                    # inline(x): at most 10 times
71:     mov rdi, r13
        mov rsi, [rbx + SW_ONCE]
        call replace_vars
        cmp rax, r13
        je 72f
        mov r13, rax
        dec r14d
        jnz 71b
72:     mov rdi, r13
        mov rsi, rbx
        call sw_small
        jmp 7b
9:      mov rax, [rbx + SW_RES]
        mov rdi, rax
        call vec_to_tuple
        add rsp, SW_SIZE + MATCH_BINDINGS_SIZE
        LEAVE
ENDF small_words

        .section .note.GNU-stack,"",@progbits
