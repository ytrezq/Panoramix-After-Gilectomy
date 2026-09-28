# Loop parsing (port of the loop part of simplify.py): the counters of a
# while, what its variables are after it, the memory it touches, and the
# loops that are really memory copies.

.include "defs.inc"

        .section .rodata
.Ls_logname:        .asciz "panoramix.simplify"
.Ls_counter_not_in: .asciz "counter %v not in the start values"
.Ls_counter_step:   .asciz "counter not in stepvars"
.Ls_find_setmems:   .asciz "Error in find_setmems"
.Ls_unknown:        .asciz "unknown"
.Ls_assert_while:   .asciz "not a while"
.Ls_assert_counter: .asciz "parse_counters: unexpected counter step"
.Ls_assert_memloc:  .asciz "not a memory location"
.Ls_assert_move:    .asciz "move_right: a list"
.Ls_assert_normalize: .asciz "normalize: unexpected variables"

        .text

.macro B reg, n
        mov \reg, [rsp + 8*(\n)]
.endm

# --- the counters of a loop (parse_counters) ---
#
# The result is a PC struct (in the arena): the fields are 0 when python's
# dict doesn't have the key. Dicts of variables are lists of (idx, value).

# pc_new() -> rax: all fields absent (python's {})
FUNC pc_new
        ENTER
        mov edi, PC_SIZEOF
        call arena_alloc
        LEAVE
ENDF pc_new

# dict_get(pairs, key) -> rax: the value for the key (by value), or 0
FUNC dict_get
        ENTER
        mov rbx, rdi
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
2:      xor eax, eax
        LEAVE
3:      mov rax, [rbx + N_DATA + r13*8]
        mov rax, [rax + N_DATA + 8]
        LEAVE
ENDF dict_get

# dict_put(vec, key, value): set the key in a vec of pairs (kept in
# insertion order)
FUNC dict_put
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        xor r14d, r14d
1:      cmp r14, [rbx + VEC_LEN]
        jae 2f
        mov rax, [rbx + VEC_DATA]
        mov rax, [rax + r14*8]
        mov rdi, [rax + N_DATA]
        mov rsi, r12
        call values_equal
        test eax, eax
        jnz 3f
        inc r14
        jmp 1b
2:      mov rdi, r12
        mov rsi, r13
        call mk2
        mov rdi, rbx
        mov rsi, rax
        call vec_push
        LEAVE
3:      mov rdi, r12
        mov rsi, r13
        call mk2
        mov rcx, [rbx + VEC_DATA]
        mov [rcx + r14*8], rax
        LEAVE
ENDF dict_put

# assert_while(line)
FUNC assert_while
        ENTER
        call is_while_line
        test eax, eax
        jz 1f
        LEAVE
1:      mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_while]
        call err_throw
ENDF assert_while

# collect_continue(line, arg, out)
FUNC collect_continue
        ENTER
        mov rbx, rdi
        mov r12, rdx
        call opcode_of
        cmp eax, OP_CONTINUE
        jne 1f
        mov rdi, r12
        mov rsi, rbx
        call vec_push
1:      LEAVE
ENDF collect_continue

# find_conts(trace) -> vec: the continue lines anywhere in the trace
FUNC find_conts
        ENTER
        mov rbx, rdi
        call vec_new
        mov r12, rax
        mov rdi, rbx
        lea rsi, [rip + collect_continue]
        mov rdx, r12
        call walk_collect_lines
        mov rax, r12
        LEAVE
ENDF find_conts

# swap_cond(cond) -> (the mirrored op, right, left)
FUNC swap_cond
        ENTER
        mov rbx, rdi
        call opcode_of
        LOADS rdi, GT
        cmp eax, OP_LT
        je 1f
        LOADS rdi, GE
        cmp eax, OP_LE
        je 1f
        LOADS rdi, LT
        cmp eax, OP_GT
        je 1f
        LOADS rdi, LE
1:      mov rsi, [rbx + N_DATA + 16]
        mov rdx, [rbx + N_DATA + 8]
        call mk3
        LEAVE
ENDF swap_cond

# move_right(left, right, exp) -> value or 0: solves left = right for
# exp, when exp is a direct term of a sum or a product
FUNC move_right
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        call is_list
        test eax, eax
        jnz .Lmr_assert
        mov rdi, r12
        call is_list
        test eax, eax
        jnz .Lmr_assert
        mov rdi, rbx
        mov rsi, r13
        call values_equal
        test eax, eax
        jz 1f
        mov rax, r12
        LEAVE
1:      mov rdi, rbx
        call opcode_of
        cmp eax, OP_ADD
        je .Lmr_add
        cmp eax, OP_MUL
        je .Lmr_mul
        xor eax, eax
        LEAVE
.Lmr_add:
        mov rdi, rbx
        mov rsi, r13
        call seq_index_from1
        cmp rax, -1
        je .Lmr_none                    # deep embedding unsupported
        mov r14d, 1
2:      cmp r14d, [rbx + N_AUX]
        jae 4f
        mov rdi, [rbx + N_DATA + r14*8]
        mov rsi, r13
        call values_equal
        test eax, eax
        jnz 3f
        mov rdi, [rbx + N_DATA + r14*8]
        call to_real_int                # (ints only: others pass through)
        mov rdi, r12
        mov rsi, rax
        call alg_sub_op
        mov r12, rax
3:      inc r14d
        jmp 2b
4:      mov rax, r12
        LEAVE
.Lmr_mul:
        mov rdi, rbx
        mov rsi, r13
        call seq_index_from1
        cmp rax, -1
        je .Lmr_none
        mov r14d, 1
5:      cmp r14d, [rbx + N_AUX]
        jae 7f
        mov rdi, [rbx + N_DATA + r14*8]
        mov rsi, r13
        call values_equal
        test eax, eax
        jnz 6f
        mov rdi, r12
        mov rsi, [rbx + N_DATA + r14*8]
        call alg_div_op
        mov r12, rax
6:      inc r14d
        jmp 5b
7:      mov rax, r12
        LEAVE
.Lmr_none:
        xor eax, eax
        LEAVE
.Lmr_assert:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_move]
        call err_throw
ENDF move_right

# loop_vars_of(exp) -> vec: the ('var', int) subexpressions (the loop
# variables, as opposed to the named ones)
FUNC loop_vars_of
        ENTER
        mov rbx, rdi
        call vec_new
        mov r12, rax
        mov rdi, rbx
        mov esi, OP_VAR
        mov rdx, r12
        call find_op_list
        call vec_new
        mov r13, rax
        xor r14d, r14d
1:      cmp r14, [r12 + VEC_LEN]
        jae 3f
        mov rax, [r12 + VEC_DATA]
        mov rdi, [rax + r14*8]
        cmp dword ptr [rdi + N_AUX], 2
        jne 2f
        mov rsi, rdi
        mov rdi, [rdi + N_DATA + 8]
        push rsi
        push rsi
        call is_int
        pop rsi
        pop rsi
        test eax, eax
        jz 2f
        mov rdi, r13
        call vec_push
2:      inc r14
        jmp 1b
3:      mov rax, r13
        LEAVE
ENDF loop_vars_of

# normalize(cond) -> value or 0: the condition as (le/ge, ('var', int),
# bound), when it's about one loop variable
FUNC normalize
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 16
        mov rbx, rdi
        call is_tuple
        test eax, eax
        jz 1f
        mov rdi, rbx
        call pp_cleanup_elements
        mov rbx, rax
1:      mov rdi, rbx
        call opcode_of
        IN_OPSET cmp4, rax              # lt, le, gt, ge
        jne 2f
        # 0 < cond
        LOADS rdi, LT
        mov esi, 1
        mov rdx, rbx
        call mk3
        mov rdi, rax
        call normalize
        jmp .Lnm_done
2:      mov rdi, [rbx + N_DATA + 8]
        call loop_vars_of
        mov r12, rax                    # left_vars
        mov rdi, [rbx + N_DATA + 16]
        call loop_vars_of
        mov r13, rax                    # right_vars
        mov rax, [r12 + VEC_LEN]
        add rax, [r13 + VEC_LEN]
        cmp rax, 1
        jne .Lnm_none
        cmp qword ptr [r13 + VEC_LEN], 1
        jne 3f
        mov rdi, rbx
        call swap_cond
        mov rdi, rax
        call normalize
        jmp .Lnm_done
3:      mov rax, [r12 + VEC_DATA]
        mov r14, [rax]                  # the variable
        mov rdi, [rbx + N_DATA + 8]
        call opcode_of
        cmp eax, OP_VAR
        je 4f
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, [rbx + N_DATA + 16]
        mov rdx, r14
        call move_right
        test rax, rax
        jz .Lnm_none
        mov rdx, rax
        mov rsi, r14
        mov rdi, [rbx + N_DATA]
        call mk3
        mov rbx, rax
4:      PAT rsi, "('lt', ':left', ':right')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 5f
        B rdi, 1
        mov esi, 3
        call alg_sub_op
        mov rdx, rax
        B rsi, 0
        LOADS rdi, LE
        call mk3
        mov rbx, rax
5:      PAT rsi, "('gt', ':left', ':right')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 6f
        B rdi, 1
        mov esi, 3
        call alg_add2
        mov rdx, rax
        B rsi, 0
        LOADS rdi, GE
        call mk3
        mov rbx, rax
6:      mov rax, rbx
        jmp .Lnm_done
.Lnm_none:
        xor eax, eax
.Lnm_done:
        add rsp, MATCH_BINDINGS_SIZE + 16
        LEAVE
ENDF normalize

        OPSET_MEMBER cmp4, OP_LT
        OPSET_MEMBER cmp4, OP_LE
        OPSET_MEMBER cmp4, OP_GT
        OPSET_MEMBER cmp4, OP_GE
        OPSET_END cmp4, OP_COUNT

# parse_counters(line) -> PC*: the counters of a while (see PC_* fields)
FUNC parse_counters
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 64
        .set PC_L_A, MATCH_BINDINGS_SIZE
        .set PC_L_CONTS, MATCH_BINDINGS_SIZE + 8
        .set PC_L_STARTVARS, MATCH_BINDINGS_SIZE + 16
        .set PC_L_COND, MATCH_BINDINGS_SIZE + 24
        .set PC_L_DIFF, MATCH_BINDINGS_SIZE + 32
        .set PC_L_I, MATCH_BINDINGS_SIZE + 40
        .set PC_L_STEPVARS, MATCH_BINDINGS_SIZE + 48
        mov rbx, rdi
        call assert_while
        call pc_new
        mov r12, rax
        mov [rsp + PC_L_A], rax
        mov rax, [rbx + N_DATA + 32]
        mov [r12 + PC_SETVARS], rax
        mov rax, [rbx + N_DATA + 24]
        mov [r12 + PC_JDS], rax
        # the continues of this loop, not of the ones nested in it
        mov rdi, [rbx + N_DATA + 16]
        call find_conts
        mov r13, rax
        call vec_new
        mov [rsp + PC_L_CONTS], rax
        xor r14d, r14d
1:      cmp r14, [r13 + VEC_LEN]
        jae 2f
        mov rax, [r13 + VEC_DATA]
        mov rsi, [rax + r14*8]
        mov rax, [rsi + N_DATA + 8]
        cmp rax, [rbx + N_DATA + 24]
        jne 11f
        mov rdi, [rsp + PC_L_CONTS]
        call vec_push
11:     inc r14
        jmp 1b
2:      # startvars: what the variables are set to before the loop
        call vec_new
        mov [rsp + PC_L_STARTVARS], rax
        mov r13, [rbx + N_DATA + 32]
        xor r14d, r14d
3:      cmp r14d, [r13 + N_AUX]
        jae 4f
        mov rax, [r13 + N_DATA + r14*8] # ('setvar', vidx, vval)
        mov rdi, [rsp + PC_L_STARTVARS]
        mov rsi, [rax + N_DATA + 8]
        mov rdx, [rax + N_DATA + 16]
        call dict_put
        inc r14d
        jmp 3b
4:      mov rdi, [rbx + N_DATA + 8]
        call normalize
        mov [rsp + PC_L_COND], rax
        test rax, rax
        jz .Lpc_empty
        mov rax, [rsp + PC_L_CONTS]
        cmp qword ptr [rax + VEC_LEN], 0
        je .Lpc_empty
        # stepvars: from the first continue
        mov rax, [rax + VEC_DATA]
        mov r13, [rax]                  # cont
        mov r13, [r13 + N_DATA + 16]    # its setvars
        call vec_new
        mov [rsp + PC_L_STEPVARS], rax
        xor r14d, r14d
5:      cmp r14d, [r13 + N_AUX]
        jae 6f
        mov rax, [r13 + N_DATA + r14*8]
        mov rdi, [rsp + PC_L_STEPVARS]
        mov rsi, [rax + N_DATA + 8]
        mov rdx, [rax + N_DATA + 16]
        call dict_put
        inc r14d
        jmp 5b
6:      mov rdi, [rsp + PC_L_STEPVARS]
        call vec_to_list
        mov [r12 + PC_STEPVARS], rax
        mov [rsp + PC_L_STEPVARS], rax
        mov rax, [rsp + PC_L_COND]
        mov rcx, [rax + N_DATA + 8]     # ('var', counter)
        mov rcx, [rcx + N_DATA + 8]
        mov [r12 + PC_COUNTER], rcx
        mov rax, [rax + N_DATA + 16]
        mov [r12 + PC_STOP], rax
        mov rdi, [rsp + PC_L_STARTVARS]
        call vec_to_list
        mov rdi, rax
        mov rsi, [r12 + PC_COUNTER]
        call dict_get
        test rax, rax
        jnz 7f
        mov edi, LOG_WARNING
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_counter_not_in]
        mov rcx, [r12 + PC_COUNTER]
        call log_fmt
        jmp .Lpc_empty
7:      mov [r12 + PC_START], rax
        mov rdi, [rsp + PC_L_STEPVARS]
        mov rsi, [r12 + PC_COUNTER]
        call dict_get
        mov [rsp + PC_L_DIFF], rax
        test rax, rax
        jnz 8f
        mov edi, LOG_WARNING
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_counter_step]
        call log_fmt
        mov qword ptr [rsp + PC_L_DIFF], 1      # 0
8:      mov rax, [rsp + PC_L_CONTS]
        cmp qword ptr [rax + VEC_LEN], 1
        ja .Lpc_done
        mov rdi, [rsp + PC_L_DIFF]
        call opcode_of
        cmp eax, OP_ADD
        jne .Lpc_done
        # counter_diff = ('add', to_real_int(diff[1]), diff[2]), with a
        # ('mul', 1, x) as diff[2] being x
        mov r13, [rsp + PC_L_DIFF]
        mov rdi, [r13 + N_DATA + 8]
        call is_int
        test eax, eax
        jz .Lpc_assert
        mov r14, [r13 + N_DATA + 16]
        mov rdi, r14
        call opcode_of
        cmp eax, OP_MUL
        jne 9f
        cmp qword ptr [r14 + N_DATA + 8], 3
        jne 9f
        mov r14, [r14 + N_DATA + 16]
9:      LOADS rdi, VAR
        mov rsi, [r12 + PC_COUNTER]
        call mk2
        cmp rax, r14
        jne .Lpc_assert
        mov rdi, [r13 + N_DATA + 8]
        call to_real_int
        mov [r12 + PC_STEP], rax
        # num_loops = (stop - start + step) / step
        mov rdi, [r12 + PC_STOP]
        mov rsi, [r12 + PC_START]
        call alg_sub_op
        mov rdi, rax
        mov rsi, [r12 + PC_STEP]
        call alg_add2
        mov rdi, rax
        mov rsi, [r12 + PC_STEP]
        call alg_div_op
        mov [rsp + PC_L_COND], rax      # (reused: num_loops)
        mov rdi, rax
        call opcode_of
        cmp eax, OP_DIV
        je .Lpc_done                    # so, no obvious divider
        mov rax, [rsp + PC_L_COND]
        mov [r12 + PC_NUM_LOOPS], rax
        # endvars: the value of every variable after the loop, when it
        # gets incremented on every iteration
        call vec_new
        mov [rsp + PC_L_STARTVARS], rax # (reused: endvars)
        mov r13, [r12 + PC_SETVARS]
        mov qword ptr [rsp + PC_L_I], 0
10:     mov rcx, [rsp + PC_L_I]
        cmp ecx, [r13 + N_AUX]
        jae 14f
        mov r14, [r13 + N_DATA + rcx*8] # ('setvar', var_idx, var_val)
        mov rdi, [rsp + PC_L_STEPVARS]
        mov rsi, [r14 + N_DATA + 8]
        call dict_get
        mov [rsp + PC_L_DIFF], rax      # step
        test rax, rax
        jz .Lpc_done                    # (no step: not incremented on every iteration)
        PAT rsi, "('add', ':diff', ('var', ':var_idx'))"
        mov rdi, rax
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 12f
        B rax, 1
        cmp rax, [r14 + N_DATA + 8]
        je 13f
12:     PAT rsi, "('add', ':diff', ('mul', 1, ('var', ':var_idx')))"
        mov rdi, [rsp + PC_L_DIFF]
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz .Lpc_done
        B rax, 1
        cmp rax, [r14 + N_DATA + 8]
        jne .Lpc_done
13:     # var_stop = to_real_int(var_val) + to_real_int(diff) * num_loops
        mov rax, [rsp + PC_L_DIFF]
        mov rdi, [rax + N_DATA + 8]
        call to_real_int
        mov rdi, rax
        mov rsi, [r12 + PC_NUM_LOOPS]
        call alg_mul2
        mov [rsp + PC_L_DIFF], rax
        mov rdi, [r14 + N_DATA + 16]
        call to_real_int
        mov rdi, rax
        mov rsi, [rsp + PC_L_DIFF]
        call alg_add2
        mov rdi, [rsp + PC_L_STARTVARS]
        mov rsi, [r14 + N_DATA + 8]
        mov rdx, rax
        call dict_put
        inc qword ptr [rsp + PC_L_I]
        jmp 10b
14:     mov rdi, [rsp + PC_L_STARTVARS]
        call vec_to_list
        mov [r12 + PC_ENDVARS], rax
.Lpc_done:
        mov rax, r12
        add rsp, MATCH_BINDINGS_SIZE + 64
        LEAVE
.Lpc_empty:
        call pc_new
        add rsp, MATCH_BINDINGS_SIZE + 64
        LEAVE
.Lpc_assert:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_counter]
        call err_throw
ENDF parse_counters

# --- the memory a loop touches ---

# collect_setmems(line, arg, out): find_setmems' check (walk_trace)
FUNC collect_setmems
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE
        mov rbx, rdi
        mov r12, rdx
        PAT rsi, "('while', 'Any', ':path', '...')"
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 1f
        B rdi, 0
        call find_setmems
        mov rdi, r12
        mov rsi, rax
        call vec_extend_seq
        jmp 2f
1:      mov rdi, rbx
        call opcode_of
        cmp eax, OP_SETMEM
        jne 2f
        mov rdi, r12
        mov rsi, rbx
        call vec_push
2:      add rsp, MATCH_BINDINGS_SIZE
        LEAVE
ENDF collect_setmems

# find_setmems(trace) -> list: the setmems of the trace, nested loops included
FUNC find_setmems
        ENTER
        mov rbx, rdi
        call vec_new
        mov r12, rax
        mov rdi, rbx
        lea rsi, [rip + collect_setmems]
        xor edx, edx
        mov rcx, r12
        call walk_trace
        mov rdi, r12
        call vec_to_list
        LEAVE
ENDF find_setmems

# memloc_left(setmem) / memloc_right(setmem): the bounds of the range of
# a ('setmem', range, ...) or ('mem', range)
FUNC memloc_left
        ENTER
        call memloc_of
        mov rax, [rax + N_DATA + 8]
        LEAVE
ENDF memloc_left

FUNC memloc_right
        ENTER
        call memloc_of
        mov rdi, [rax + N_DATA + 8]
        mov rsi, [rax + N_DATA + 16]
        call alg_add2
        LEAVE
ENDF memloc_right

FUNC memloc_of
        ENTER
        mov rbx, rdi
        call opcode_of
        cmp eax, OP_SETMEM
        je 1f
        cmp eax, OP_MEM
        jne 2f
1:      mov rdi, [rbx + N_DATA + 8]
        mov rbx, rdi
        call assert_range
        mov rax, rbx
        LEAVE
2:      mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_memloc]
        call err_throw
ENDF memloc_of

# make_range(left, right) -> ('range', left, right - left), of length 0
# when that's negative for sure
FUNC make_range
        ENTER
        mov rbx, rdi
        mov rdi, rsi
        mov rsi, rbx
        call alg_sub_op
        mov r12, rax
        mov rdi, rax
        call alg_safe_ge_zero
        cmp eax, TRI_FALSE
        jne 1f
        mov r12d, 1
1:      mov rdi, rbx
        mov rsi, r12
        call mk_range
        LEAVE
ENDF make_range

# while_max_memidx(line) -> value: the rightmost memory index a loop writes
FUNC while_max_memidx
        ENTER
        sub rsp, ERR_SIZEOF + 48
        .set WM_A, ERR_SIZEOF
        .set WM_SETMEMS, ERR_SIZEOF + 8
        .set WM_BEGIN, ERR_SIZEOF + 16
        .set WM_END, ERR_SIZEOF + 24
        .set WM_COLLECTED, ERR_SIZEOF + 32
        mov rbx, rdi
        call parse_counters
        mov [rsp + WM_A], rax
        mov rdi, rbx
        call assert_while
        mov rdi, rsp
        call err_catch
        test eax, eax
        jnz .Lwm_error
        mov rdi, [rbx + N_DATA + 16]
        call find_setmems
        mov [rsp + WM_SETMEMS], rax
        call err_end
        mov r12, [rsp + WM_SETMEMS]
        cmp dword ptr [r12 + N_AUX], 0
        jne 1f
        mov eax, 1
        jmp .Lwm_done
1:      mov qword ptr [rsp + WM_COLLECTED], 1
        mov rax, [rsp + WM_A]
        cmp qword ptr [rax + PC_ENDVARS], 0
        jne 3f
        xor r13d, r13d
2:      cmp r13d, [r12 + N_AUX]
        jae .Lwm_collected
        mov rdi, [r12 + N_DATA + r13*8]
        call memloc_right
        mov rdi, [rsp + WM_COLLECTED]
        mov rsi, rax
        call alg_max_op2
        mov [rsp + WM_COLLECTED], rax
        inc r13d
        jmp 2b
3:      # with the variables at their first and last values
        mov rdi, r12
        mov rsi, [rsp + WM_A]
        call setmems_at_bounds          # -> rax = begin, rdx = end
        mov [rsp + WM_BEGIN], rax
        mov [rsp + WM_END], rdx
        xor r13d, r13d
4:      cmp r13d, [r12 + N_AUX]
        jae .Lwm_collected
        mov rax, [rsp + WM_BEGIN]
        mov rdi, [rax + N_DATA + r13*8]
        call memloc_right
        mov rdi, [rsp + WM_COLLECTED]
        mov rsi, rax
        call alg_max_op2
        mov [rsp + WM_COLLECTED], rax
        mov rax, [rsp + WM_END]
        mov rdi, [rax + N_DATA + r13*8]
        call memloc_right
        mov rdi, [rsp + WM_COLLECTED]
        mov rsi, rax
        call alg_max_op2
        mov [rsp + WM_COLLECTED], rax
        inc r13d
        jmp 4b
.Lwm_collected:
        mov rax, [rsp + WM_COLLECTED]
.Lwm_done:
        add rsp, ERR_SIZEOF + 48
        LEAVE
.Lwm_error:
        mov edi, LOG_ERROR
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_find_setmems]
        call log_fmt
        lea rdi, [rip + .Ls_unknown]
        call str_intern_c
        add rsp, ERR_SIZEOF + 48
        LEAVE
ENDF while_max_memidx

# setmems_at_bounds(lines, pc) -> rax, rdx: the lines (setmems or mems)
# with every loop variable at its start value, and at its end value
FUNC setmems_at_bounds
        ENTER
        sub rsp, 32
        mov [rsp], rdi                  # begin
        mov [rsp + 8], rdi              # end
        mov r12, [rsi + PC_SETVARS]
        mov r13, [rsi + PC_ENDVARS]
        xor r14d, r14d
1:      cmp r14d, [r12 + N_AUX]
        jae 3f
        mov rax, [r12 + N_DATA + r14*8] # ('setvar', v_idx, v_start)
        mov rdi, [rsp]
        mov rsi, [rax + N_DATA + 8]
        mov rdx, [rax + N_DATA + 16]
        call replace_var
        mov [rsp], rax
        mov rax, [r12 + N_DATA + r14*8]
        mov rdi, r13
        mov rsi, [rax + N_DATA + 8]
        call dict_get
        mov rdx, rax
        mov rax, [r12 + N_DATA + r14*8]
        mov rsi, [rax + N_DATA + 8]
        mov rdi, [rsp + 8]
        call replace_var
        mov [rsp + 8], rax
        inc r14d
        jmp 1b
3:      mov rax, [rsp]
        mov rdx, [rsp + 8]
        add rsp, 32
        LEAVE
ENDF setmems_at_bounds

# extract_paths(while) -> list of paths: the lines on every path leading
# to a continue (with the conditions as requires)
FUNC extract_paths
        ENTER
        mov rbx, rdi
        call assert_while
        mov rdi, [rbx + N_DATA + 16]
        xor esi, esi
        xor edx, edx
        call mk_list
        mov rsi, rax
        call extract_paths_f
        LEAVE
ENDF extract_paths

# extract_paths_f(trace, so_far) -> list of paths
FUNC extract_paths_f
        ENTER
        sub rsp, 32
        mov rbx, rdi
        mov r12, rsi
        cmp dword ptr [rbx + N_AUX], 0
        je .Lep_none
        mov r13, [rbx + N_DATA]         # the first line
        mov rdi, r13
        call is_if_line
        test eax, eax
        jz 1f
        # both branches, followed by the rest (non-empty when the
        # branches merge again)
        mov rdi, rbx
        mov esi, 1
        call list_from
        mov r14, rax                    # rest
        mov rdi, [r13 + N_DATA + 16]
        mov rsi, r14
        call list_concat
        mov [rsp], rax
        mov rsi, [r13 + N_DATA + 8]
        LOADS rdi, REQUIRE
        call mk2
        mov rdi, r12
        mov rsi, rax
        call list_append
        mov rdi, [rsp]
        mov rsi, rax
        call extract_paths_f
        mov [rsp + 8], rax              # res_true
        mov rdi, [r13 + N_DATA + 24]
        mov rsi, r14
        call list_concat
        mov [rsp], rax
        mov rdi, [r13 + N_DATA + 8]
        call is_zero
        mov rsi, rax
        LOADS rdi, REQUIRE
        call mk2
        mov rdi, r12
        mov rsi, rax
        call list_append
        mov rdi, [rsp]
        mov rsi, rax
        call extract_paths_f
        mov rdi, [rsp + 8]
        mov rsi, rax
        call list_concat
        jmp .Lep_done
1:      cmp dword ptr [rbx + N_AUX], 1
        jne 2f
        mov rdi, r13
        call opcode_of
        cmp eax, OP_CONTINUE
        jne .Lep_none
        mov rdi, r12
        call mk_list1
        jmp .Lep_done
2:      mov rdi, rbx
        mov esi, 1
        call list_from
        mov [rsp], rax
        mov rdi, r12
        mov rsi, r13
        call list_append
        mov rdi, [rsp]
        mov rsi, rax
        call extract_paths_f
        jmp .Lep_done
.Lep_none:
        xor edi, edi
        xor esi, esi
        call mk_list
.Lep_done:
        add rsp, 32
        LEAVE
ENDF extract_paths_f

# list_append(list, x) -> list + [x]
FUNC list_append
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call vec_new
        mov r13, rax
        mov rdi, rax
        mov rsi, rbx
        call vec_extend_seq
        mov rdi, r13
        mov rsi, r12
        call vec_push
        mov rdi, r13
        call vec_to_list
        LEAVE
ENDF list_append

# extract_setmems(while) -> list: the setmems of the loop body that are
# on a path to a continue, without duplicates
FUNC extract_setmems
        ENTER
        sub rsp, 16
        mov rbx, rdi
        call assert_while
        mov rdi, [rbx + N_DATA + 16]
        xor esi, esi
        lea rdx, [rsp]
        call extract_setmems_f
        mov rbx, rax
        # list(dict.fromkeys(res))
        call vec_new
        mov r12, rax
        xor r13d, r13d
1:      cmp r13d, [rbx + N_AUX]
        jae 2f
        mov rdi, r12
        mov rsi, [rbx + N_DATA + r13*8]
        call vec_push_unique
        inc r13d
        jmp 1b
2:      mov rdi, r12
        call vec_to_list
        add rsp, 16
        LEAVE
ENDF extract_setmems

# extract_setmems_f(trace, after, &reach) -> list: `after` says whether a
# continue is reachable from the end of the trace; *reach whether there
# are paths through it that reach one
FUNC extract_setmems_f
        ENTER
        sub rsp, 48
        mov rbx, rdi
        mov [rsp], rsi                  # reach
        mov [rsp + 8], rdx              # &reach out
        xor edi, edi
        xor esi, esi
        call mk_list
        mov r12, rax                    # res
        mov r13d, [rbx + N_AUX]
1:      test r13d, r13d
        jz 6f
        dec r13d
        mov r14, [rbx + N_DATA + r13*8]
        mov rdi, r14
        call opcode_of
        cmp eax, OP_CONTINUE
        jne 2f
        mov qword ptr [rsp], 1
        jmp 1b
2:      mov edi, eax
        call is_ends_execution_op
        test eax, eax
        jz 3f
        mov qword ptr [rsp], 0
        jmp 1b
3:      mov rdi, r14
        call is_if_line
        test eax, eax
        jz 4f
        mov rdi, [r14 + N_DATA + 16]
        mov rsi, [rsp]
        lea rdx, [rsp + 16]
        call extract_setmems_f
        mov [rsp + 24], rax             # res_true
        mov rdi, [r14 + N_DATA + 24]
        mov rsi, [rsp]
        lea rdx, [rsp + 32]
        call extract_setmems_f
        mov [rsp + 40], rax             # res_false
        mov rdi, [rsp + 24]
        mov rsi, rax
        call list_concat
        mov rdi, rax
        mov rsi, r12
        call list_concat
        mov r12, rax
        mov rax, [rsp + 16]
        or rax, [rsp + 32]
        mov [rsp], rax
        jmp 1b
4:      cmp qword ptr [rsp], 0
        je 1b
        mov rdi, r14
        call opcode_of
        cmp eax, OP_SETMEM
        je 5f
        cmp eax, OP_WHILE
        jne 1b
5:      mov rdi, r14
        call mk_list1
        mov rdi, rax
        call find_setmems
        mov rdi, rax
        mov rsi, r12
        call list_concat
        mov r12, rax
        jmp 1b
6:      mov rax, [rsp + 8]
        mov rcx, [rsp]
        mov [rax], rcx
        mov rax, r12
        add rsp, 48
        LEAVE
ENDF extract_setmems_f

# is_ends_execution_op(id) -> eax: revert, return, stop, invalid,
# assert_fail, selfdestruct
        OPSET_FUNC is_ends_execution_op, ends_execution
        OPSET_MEMBER ends_execution, OP_REVERT
        OPSET_MEMBER ends_execution, OP_RETURN
        OPSET_MEMBER ends_execution, OP_STOP
        OPSET_MEMBER ends_execution, OP_INVALID
        OPSET_MEMBER ends_execution, OP_ASSERT_FAIL
        OPSET_MEMBER ends_execution, OP_SELFDESTRUCT
        OPSET_END ends_execution, OP_COUNT

# vec_push_unique(vec, v): push unless present (by value)
FUNC vec_push_unique
        ENTER
        mov rbx, rdi
        mov r12, rsi
        xor r13d, r13d
1:      cmp r13, [rbx + VEC_LEN]
        jae 2f
        mov rax, [rbx + VEC_DATA]
        mov rdi, [rax + r13*8]
        mov rsi, r12
        call values_equal
        test eax, eax
        jnz 3f
        inc r13
        jmp 1b
2:      mov rdi, rbx
        mov rsi, r12
        call vec_push
3:      LEAVE
ENDF vec_push_unique

# ranges_overlap_at_bounds(lines, mem_idx, pc) -> eax: for setmems/mems
# of a loop with known counters, whether the memory index overlaps any
# of them over the whole run of the loop
FUNC ranges_overlap_at_bounds
        ENTER
        sub rsp, 32
        mov rbx, rdi
        mov r12, rsi
        mov rdi, rbx
        mov rsi, rdx
        call setmems_at_bounds
        mov [rsp], rax                  # begin
        mov [rsp + 8], rdx              # end
        xor r13d, r13d
1:      cmp r13d, [rbx + N_AUX]
        jae 3f
        # [begin.left, end.right] and [end.left, begin.right]
        mov rax, [rsp]
        mov rdi, [rax + N_DATA + r13*8]
        call memloc_left
        mov [rsp + 16], rax
        mov rax, [rsp + 8]
        mov rdi, [rax + N_DATA + r13*8]
        call memloc_right
        mov rdi, [rsp + 16]
        mov rsi, rax
        call make_range
        mov rdi, r12
        mov rsi, rax
        call range_overlaps
        cmp eax, TRI_FALSE
        jne 2f
        mov rax, [rsp + 8]
        mov rdi, [rax + N_DATA + r13*8]
        call memloc_left
        mov [rsp + 16], rax
        mov rax, [rsp]
        mov rdi, [rax + N_DATA + r13*8]
        call memloc_right
        mov rdi, [rsp + 16]
        mov rsi, rax
        call make_range
        mov rdi, r12
        mov rsi, rax
        call range_overlaps
        cmp eax, TRI_FALSE
        jne 2f
        inc r13d
        jmp 1b
2:      mov eax, 1
        add rsp, 32
        LEAVE
3:      xor eax, eax
        add rsp, 32
        LEAVE
ENDF ranges_overlap_at_bounds

# ranges_overlap_any(lines, mem_idx) -> eax: without known counters,
# comparing with the variables as they are
FUNC ranges_overlap_any
        ENTER
        mov rbx, rdi
        mov r12, rsi
        xor r13d, r13d
1:      cmp r13d, [rbx + N_AUX]
        jae 3f
        mov rax, [rbx + N_DATA + r13*8]
        mov rdi, r12
        mov rsi, [rax + N_DATA + 8]
        call range_overlaps
        cmp eax, TRI_FALSE
        jne 2f
        inc r13d
        jmp 1b
2:      mov eax, 1
        LEAVE
3:      xor eax, eax
        LEAVE
ENDF ranges_overlap_any

# while_touches_mem(line, mem_idx) -> eax: the loop may write the memory
FUNC while_touches_mem
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        call parse_counters
        mov r13, rax
        mov rdi, rbx
        call assert_while
        mov rdi, rbx
        call extract_setmems
        mov r14, rax
        cmp dword ptr [r14 + N_AUX], 0
        je .Lwt_no
        cmp qword ptr [r13 + PC_ENDVARS], 0
        jne 1f
        # no endvars: comparing just with a 'var' assumes 'var' is any natural number
        mov rdi, r14
        mov rsi, r12
        call ranges_overlap_any
        jmp .Lwt_done
1:      mov rdi, r14
        mov rsi, r12
        mov rdx, r13
        call ranges_overlap_at_bounds
        jmp .Lwt_done
.Lwt_no:
        xor eax, eax
.Lwt_done:
        add rsp, 16
        LEAVE
ENDF while_touches_mem

# while_uses_mem(line, mem_idx) -> eax: the loop may read the memory
FUNC while_uses_mem
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        call assert_while
        mov rdi, rbx
        call parse_counters
        mov r13, rax
        mov rdi, rbx
        call find_mems
        mov r14, rax
        cmp dword ptr [r14 + N_AUX], 0
        je .Lwu_no
        cmp qword ptr [r13 + PC_ENDVARS], 0
        jne 1f
        mov rdi, r14
        mov rsi, r12
        call ranges_overlap_any
        jmp .Lwu_done
1:      mov rdi, r14
        mov rsi, r12
        mov rdx, r13
        call ranges_overlap_at_bounds
        jmp .Lwu_done
.Lwu_no:
        xor eax, eax
.Lwu_done:
        add rsp, 16
        LEAVE
ENDF while_uses_mem

# exp_uses_mem(exp, mem_idx) -> eax: a memory read in exp may overlap mem_idx
FUNC exp_uses_mem
        ENTER
        mov r12, rsi
        call find_mems
        mov rbx, rax
        xor r13d, r13d
1:      cmp r13d, [rbx + N_AUX]
        jae 3f
        mov rax, [rbx + N_DATA + r13*8]
        mov rdi, [rax + N_DATA + 8]
        mov rsi, r12
        call range_overlaps
        cmp eax, TRI_FALSE
        jne 2f
        inc r13d
        jmp 1b
2:      mov eax, 1
        LEAVE
3:      xor eax, eax
        LEAVE
ENDF exp_uses_mem

# collect_mem(exp, arg, out): find_mems' f
FUNC collect_mem
        ENTER
        mov rbx, rdi
        mov r12, rdx
        call opcode_of
        cmp eax, OP_MEM
        jne 1f
        mov rdi, r12
        mov rsi, rbx
        call vec_push_unique
1:      LEAVE
ENDF collect_mem

# find_mems(exp) -> list: the ('mem', ...) subexpressions (a set: no
# duplicates), memoized
FUNC find_mems
        ENTER
        mov rbx, rdi
        test dil, 1
        jnz .Lfm_none
        test rdi, rdi
        jz .Lfm_none
        mov edi, MEMO_FIND_MEMS
        mov rsi, rbx
        call memo_get
        test rax, rax
        jnz 1f
        call vec_new
        mov r12, rax
        mov rdi, rbx
        lea rsi, [rip + collect_mem]
        mov rdx, r12
        call walk_collect_lines
        mov rdi, r12
        call vec_to_list
        mov r12, rax
        mov edi, MEMO_FIND_MEMS
        mov rsi, rbx
        mov rdx, r12
        call memo_put
        mov rax, r12
1:      LEAVE
.Lfm_none:
        xor edi, edi
        xor esi, esi
        call mk_list
        LEAVE
ENDF find_mems

# --- loops that are really memory copies ---

# vars_in_expr(expr) -> vec: the ids of the variables in the expression
FUNC vars_in_expr
        ENTER
        mov rbx, rdi
        call vec_new
        mov r12, rax
        mov rdi, rbx
        mov rsi, r12
        call vars_in_expr_into
        mov rax, r12
        LEAVE
ENDF vars_in_expr

FUNC vars_in_expr_into
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE
        mov rbx, rdi
        mov r12, rsi
        PAT rsi, "('var', ':var_id')"
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 1f
        mov rdi, r12
        B rsi, 0
        call vec_push_unique
        jmp 3f
1:      mov rdi, rbx
        call is_seq
        test eax, eax
        jz 3f
        xor r13d, r13d
2:      cmp r13d, [rbx + N_AUX]
        jae 3f
        mov rdi, [rbx + N_DATA + r13*8]
        mov rsi, r12
        call vars_in_expr_into
        inc r13d
        jmp 2b
3:      add rsp, MATCH_BINDINGS_SIZE
        LEAVE
ENDF vars_in_expr_into

# only_add_in_expr(op) -> eax: the expression only adds things to
# variables (sha3 of a constant allowed)
FUNC only_add_in_expr
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE
        mov rbx, rdi
        PAT rsi, "('setvar', ':idx', ':val')"
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 1f
        B rdi, 1
        call only_add_in_expr
        jmp .Loa_done
1:      mov rdi, rbx
        call opcode_of
        cmp eax, OP_ADD
        jne 2f
        mov r12d, 1
11:     cmp r12d, [rbx + N_AUX]
        jae .Loa_yes
        mov rdi, [rbx + N_DATA + r12*8]
        call only_add_in_expr
        test eax, eax
        jz .Loa_done
        inc r12d
        jmp 11b
2:      PAT rsi, "('var', 'Any')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jnz .Loa_yes
        PAT rsi, "('sha3', ':term')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 3f
        B rdi, 0
        call opcode_of
        test eax, eax
        setz al
        movzx eax, al
        jmp .Loa_done
3:      mov rdi, rbx
        call opcode_of
        test eax, eax
        jz .Loa_yes
        xor eax, eax
        jmp .Loa_done
.Loa_yes:
        mov eax, 1
.Loa_done:
        add rsp, MATCH_BINDINGS_SIZE
        LEAVE
ENDF only_add_in_expr

# storage_sha3(value) -> value or 0: a sha3 (of something that isn't a
# small int) among the terms of a sum
FUNC storage_sha3
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE
        mov rbx, rdi
        call opcode_of
        cmp eax, OP_ADD
        jne 2f
        mov r12d, 1
1:      cmp r12d, [rbx + N_AUX]
        jae 2f
        mov rdi, [rbx + N_DATA + r12*8]
        call storage_sha3
        test rax, rax
        jnz .Lss_done
        inc r12d
        jmp 1b
2:      PAT rsi, "('sha3', ':val')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz .Lss_none
        B rdi, 0
        call is_int
        test eax, eax
        jz 3f
        B rdi, 0
        test dil, 1
        jz .Lss_none                    # (a big int is >= 1000)
        cmp rdi, (1000 << 1) | 1
        jge .Lss_none
3:      mov rax, rbx
        jmp .Lss_done
.Lss_none:
        xor eax, eax
.Lss_done:
        add rsp, MATCH_BINDINGS_SIZE
        LEAVE
ENDF storage_sha3

# path_only_add_in_continue(path) -> eax
FUNC path_only_add_in_continue
        ENTER
        mov rbx, rdi
        xor r12d, r12d
1:      cmp r12d, [rbx + N_AUX]
        jae .Lpo_yes
        mov r13, [rbx + N_DATA + r12*8]
        mov rdi, r13
        call opcode_of
        cmp eax, OP_CONTINUE
        jne 3f
        mov r13, [r13 + N_DATA + 16]    # instrs
        xor r14d, r14d
2:      cmp r14d, [r13 + N_AUX]
        jae 3f
        mov rdi, [r13 + N_DATA + r14*8]
        call only_add_in_expr
        test eax, eax
        jz .Lpo_no
        inc r14d
        jmp 2b
3:      inc r12d
        jmp 1b
.Lpo_yes:
        mov eax, 1
        LEAVE
.Lpo_no:
        xor eax, eax
        LEAVE
ENDF path_only_add_in_continue

# add_sha3(t, arg) -> value or 0: replace_f_stop's f in
# propagate_storage_in_loop; arg = (('var', var_id), sha3)
FUNC add_sha3
        ENTER
        mov rbx, rdi
        mov r12, rsi
        cmp rdi, [r12 + N_DATA]
        jne 1f
        mov rsi, [r12 + N_DATA + 8]
        call alg_add2
        LEAVE
1:      # for a continue we don't want to touch the variable
        mov rdi, rbx
        call opcode_of
        cmp eax, OP_CONTINUE
        jne 2f
        mov rax, rbx
        LEAVE
2:      xor eax, eax
        LEAVE
ENDF add_sha3

# propagate_storage_in_loop(line) -> list: the sha3 of the storage index
# variables moved out of the loop
FUNC propagate_storage_in_loop
        ENTER
        sub rsp, 64
        .set PS_COND, 0
        .set PS_PATH, 8
        .set PS_NEW, 16
        .set PS_SHA3, 24
        .set PS_ARG, 32
        .set PS_SETVAR, 40
        mov rbx, rdi
        call assert_while
        mov rax, [rbx + N_DATA + 8]
        mov [rsp + PS_COND], rax
        mov rax, [rbx + N_DATA + 16]
        mov [rsp + PS_PATH], rax
        call vec_new
        mov [rsp + PS_NEW], rax
        mov r12, [rbx + N_DATA + 32]    # setvars
        xor r13d, r13d
1:      cmp r13d, [r12 + N_AUX]
        jae 5f
        mov r14, [r12 + N_DATA + r13*8] # ('setvar', var_id, value)
        mov [rsp + PS_SETVAR], r14
        mov rdi, [r14 + N_DATA + 16]
        call storage_sha3
        mov [rsp + PS_SHA3], rax
        test rax, rax
        jz 2f
        # if the continues don't only add to the index variable, it isn't
        # safe to proceed
        mov rdi, [rsp + PS_PATH]
        call path_only_add_in_continue
        test eax, eax
        jz 2f
        # ('setvar', var_id, value - sha3)
        mov rdi, [r14 + N_DATA + 16]
        mov rsi, [rsp + PS_SHA3]
        call alg_sub_op
        mov rdx, rax
        mov rsi, [r14 + N_DATA + 8]
        LOADS rdi, SETVAR
        call mk3
        mov rdi, [rsp + PS_NEW]
        mov rsi, rax
        call vec_push
        # the variable becomes var + sha3 in the path and the condition
        mov rsi, [r14 + N_DATA + 8]
        LOADS rdi, VAR
        call mk2
        mov rdi, rax
        mov rsi, [rsp + PS_SHA3]
        call mk2
        mov [rsp + PS_ARG], rax
        mov rdi, [rsp + PS_PATH]
        lea rsi, [rip + add_sha3]
        mov rdx, rax
        call replace_f_stop
        mov [rsp + PS_PATH], rax
        mov rdi, [rsp + PS_COND]
        lea rsi, [rip + add_sha3]
        mov rdx, [rsp + PS_ARG]
        call replace_f_stop
        mov [rsp + PS_COND], rax
        jmp 3f
2:      mov rdi, [rsp + PS_NEW]
        mov rsi, r14
        call vec_push
3:      inc r13d
        jmp 1b
5:      mov rdi, [rsp + PS_NEW]
        call vec_to_list
        mov rcx, rax
        mov rdi, [rsp + PS_COND]
        mov rsi, [rsp + PS_PATH]
        mov rdx, [rbx + N_DATA + 24]
        call mk_while
        mov rdi, rax
        call mk_list1
        add rsp, 64
        LEAVE
ENDF propagate_storage_in_loop

# propagate_storage_in_loops(trace) -> list
FUNC propagate_storage_in_loops
        ENTER
        lea rsi, [rip + propagate_touch]
        xor edx, edx
        call rewrite_trace
        LEAVE
ENDF propagate_storage_in_loops

FUNC propagate_touch
        ENTER
        mov rbx, rdi
        mov r12, rdx
        call is_while_line
        test eax, eax
        jz 1f
        mov rdi, rbx
        call propagate_storage_in_loop
        mov rdi, r12
        mov rsi, rax
        call vec_extend_seq
        LEAVE
1:      mov rdi, r12
        mov rsi, rbx
        call vec_push
        LEAVE
ENDF propagate_touch

# memidx_to_memrange(mem_idx, setvars, stepvars, endvars) -> rax, rdx:
# the range a memory index covers over the loop, and the step (32 or
# -32); 0 when the step isn't a word
FUNC memidx_to_memrange
        ENTER
        sub rsp, 48
        .set MM_IDX, 0
        .set MM_SETVARS, 8
        .set MM_STEPVARS, 16
        .set MM_ENDVARS, 24
        .set MM_NEXT, 32
        .set MM_LAST, 40
        mov [rsp + MM_IDX], rdi
        mov [rsp + MM_SETVARS], rsi
        mov [rsp + MM_STEPVARS], rdx
        mov [rsp + MM_ENDVARS], rcx
        mov rbx, rdi
        # mem_idx_next: with the step applied
        mov rdi, rbx
        mov rsi, rdx
        call replace_vars_by_setvars
        mov [rsp + MM_NEXT], rax
        mov rdi, rax
        mov rsi, rbx
        call alg_sub_op
        mov r12, rax                    # diff
        cmp rax, (32 << 1) | 1
        je 1f
        cmp rax, (-32 << 1) | 1
        jne .Lmm_none
1:      mov rdi, rbx
        mov rsi, [rsp + MM_ENDVARS]
        call replace_vars_by_pairs
        mov [rsp + MM_LAST], rax
        mov rdi, rbx
        mov rsi, [rsp + MM_SETVARS]
        call replace_vars_by_setvars
        mov r13, rax                    # first
        cmp r12, (32 << 1) | 1
        jne 2f
        # ('range', first, last - first), 32
        mov rdi, [rsp + MM_LAST]
        mov rsi, r13
        call alg_sub_op
        mov rdi, r13
        mov rsi, rax
        call mk_range
        mov rdx, r12
        add rsp, 48
        LEAVE
2:      # ('range', last + 32, (first + 32) - (last + 32)), -32
        mov edi, (32 << 1) | 1
        mov rsi, [rsp + MM_LAST]
        call alg_add2
        mov [rsp + MM_LAST], rax
        mov edi, (32 << 1) | 1
        mov rsi, r13
        call alg_add2
        mov rdi, rax
        mov rsi, [rsp + MM_LAST]
        call alg_sub_op
        mov rdi, [rsp + MM_LAST]
        mov rsi, rax
        call mk_range
        mov rdx, r12
        add rsp, 48
        LEAVE
.Lmm_none:
        xor eax, eax
        xor edx, edx
        add rsp, 48
        LEAVE
ENDF memidx_to_memrange

# replace_vars_by_setvars(exp, setvars) -> exp with every ('var', idx)
# replaced by its value in the ('setvar', idx, value) sequence
FUNC replace_vars_by_setvars
        ENTER
        mov rbx, rdi
        mov r12, rsi
        xor r13d, r13d
1:      cmp r13d, [r12 + N_AUX]
        jae 2f
        mov rax, [r12 + N_DATA + r13*8]
        mov rsi, [rax + N_DATA + 8]
        LOADS rdi, VAR
        call mk2
        mov rsi, rax
        mov rax, [r12 + N_DATA + r13*8]
        mov rdx, [rax + N_DATA + 16]
        mov rdi, rbx
        call replace
        mov rbx, rax
        inc r13d
        jmp 1b
2:      mov rax, rbx
        LEAVE
ENDF replace_vars_by_setvars

# replace_vars_by_pairs(exp, pairs): the same for a dict of (idx, value)
FUNC replace_vars_by_pairs
        ENTER
        mov rbx, rdi
        mov r12, rsi
        xor r13d, r13d
1:      cmp r13d, [r12 + N_AUX]
        jae 2f
        mov rax, [r12 + N_DATA + r13*8]
        mov rsi, [rax + N_DATA]
        LOADS rdi, VAR
        call mk2
        mov rsi, rax
        mov rax, [r12 + N_DATA + r13*8]
        mov rdx, [rax + N_DATA + 8]
        mov rdi, rbx
        call replace
        mov rbx, rax
        inc r13d
        jmp 1b
2:      mov rax, rbx
        LEAVE
ENDF replace_vars_by_pairs

# loop_to_setmem_impl(line) -> list or 0: a loop that writes one word
# per iteration becomes a setmem of the whole range
FUNC loop_to_setmem_impl
        ENTER
        sub rsp, 64
        .set LS_A, 0
        .set LS_MEM_IDX, 8
        .set LS_MEM_VAL, 16
        .set LS_STEPVARS, 24
        .set LS_RNG, 32
        .set LS_DIFF, 40
        .set LS_RES, 48
        mov rbx, rdi
        call assert_while
        mov r12, [rbx + N_DATA + 16]    # path
        cmp dword ptr [r12 + N_AUX], 2
        jne .Lls_none
        mov rdi, [r12 + N_DATA + 8]
        call opcode_of
        cmp eax, OP_CONTINUE
        jne .Lls_none
        mov rdi, [r12 + N_DATA]
        call opcode_of
        cmp eax, OP_SETMEM
        jne .Lls_none
        mov r13, [r12 + N_DATA]         # setmem
        mov r14, [r12 + N_DATA + 8]     # cont
        mov rax, [r13 + N_DATA + 16]
        mov [rsp + LS_MEM_VAL], rax
        mov rdi, [r13 + N_DATA + 8]
        call assert_range
        mov rax, [r13 + N_DATA + 8]
        cmp qword ptr [rax + N_DATA + 16], (32 << 1) | 1
        jne .Lls_none
        mov rax, [rax + N_DATA + 8]
        mov [rsp + LS_MEM_IDX], rax
        mov rax, [r14 + N_DATA + 16]
        mov [rsp + LS_STEPVARS], rax
        mov rdi, rbx
        call parse_counters
        mov [rsp + LS_A], rax
        cmp qword ptr [rax + PC_ENDVARS], 0
        je .Lls_none
        mov rdi, [rsp + LS_MEM_IDX]
        mov rsi, [rax + PC_SETVARS]
        mov rdx, [rsp + LS_STEPVARS]
        mov rcx, [rax + PC_ENDVARS]
        call memidx_to_memrange
        test rax, rax
        jz .Lls_none
        mov [rsp + LS_RNG], rax
        mov [rsp + LS_DIFF], rdx
        cmp qword ptr [rsp + LS_MEM_VAL], 1
        jne 1f
        # [('setmem', rng, 0)]
        mov rsi, rax
        LOADS rdi, SETMEM
        mov edx, 1
        call mk3
        jmp 3f
1:      mov rdi, [rsp + LS_MEM_VAL]
        call opcode_of
        cmp eax, OP_MEM
        jne .Lls_none
        mov rax, [rsp + LS_MEM_VAL]
        mov rdi, [rax + N_DATA + 8]
        mov r13, rdi
        call assert_range
        cmp qword ptr [r13 + N_DATA + 16], (32 << 1) | 1
        jne .Lls_none
        mov rax, [rsp + LS_A]
        mov rdi, [r13 + N_DATA + 8]
        mov rsi, [rax + PC_SETVARS]
        mov rdx, [rsp + LS_STEPVARS]
        mov rcx, [rax + PC_ENDVARS]
        call memidx_to_memrange
        test rax, rax
        jz .Lls_none
        cmp rdx, [rsp + LS_DIFF]
        jne .Lls_none                   # possible but unsupported
        # [('setmem', rng, ('mem', val_rng))]
        mov rsi, rax
        LOADS rdi, MEM
        call mk2
        mov rdx, rax
        mov rsi, [rsp + LS_RNG]
        LOADS rdi, SETMEM
        call mk3
3:      mov [rsp + LS_RES], rax
        call vec_new
        mov r13, rax
        mov rdi, rax
        mov rsi, [rsp + LS_RES]
        call vec_push
        # the variables after the loop
        mov rax, [rsp + LS_A]
        mov r12, [rax + PC_ENDVARS]
        xor r14d, r14d
4:      cmp r14d, [r12 + N_AUX]
        jae 5f
        mov rax, [r12 + N_DATA + r14*8]
        mov rsi, [rax + N_DATA]
        mov rdx, [rax + N_DATA + 8]
        LOADS rdi, SETVAR
        call mk3
        mov rdi, r13
        mov rsi, rax
        call vec_push
        inc r14d
        jmp 4b
5:      mov rdi, r13
        call vec_to_list
        add rsp, 64
        LEAVE
.Lls_none:
        xor eax, eax
        add rsp, 64
        LEAVE
ENDF loop_to_setmem_impl

# loop_to_setmem_from_storage(line) -> list or 0: a loop copying storage
# words to memory becomes a setmem of a storage range
FUNC loop_to_setmem_from_storage
        ENTER
        sub rsp, 96
        .set LF_MEM_IDX, 0
        .set LF_MEM_VAL, 8
        .set LF_IDX_VAR, 16
        .set LF_KEY_VAR, 24
        .set LF_KEY, 32
        .set LF_UPD_IDX, 40
        .set LF_UPD_KEY, 48
        .set LF_IDX_START, 56
        .set LF_KEY_START, 64
        .set LF_IDX_INIT, 72
        .set LF_COUNT, 80
        mov rbx, rdi
        call assert_while
        mov r12, [rbx + N_DATA + 16]    # path
        cmp dword ptr [r12 + N_AUX], 2
        jne .Llf_none
        mov rdi, [r12 + N_DATA]
        call opcode_of
        cmp eax, OP_SETMEM
        jne .Llf_none
        mov rdi, [r12 + N_DATA + 8]
        call opcode_of
        cmp eax, OP_CONTINUE
        jne .Llf_none
        mov r13, [r12 + N_DATA]         # setmem
        mov r14, [r12 + N_DATA + 8]     # cont
        mov rax, [r13 + N_DATA + 8]
        mov [rsp + LF_MEM_IDX], rax
        mov rax, [r13 + N_DATA + 16]
        mov [rsp + LF_MEM_VAL], rax
        # the variable of the memory index
        mov rdi, [rsp + LF_MEM_IDX]
        call vars_in_expr
        cmp qword ptr [rax + VEC_LEN], 1
        jne .Llf_none
        mov rax, [rax + VEC_DATA]
        mov rax, [rax]
        mov [rsp + LF_IDX_VAR], rax
        mov rdi, [rsp + LF_MEM_IDX]
        call only_add_in_expr
        test eax, eax
        jz .Llf_none
        # and the one of the storage key
        mov rdi, [rsp + LF_MEM_VAL]
        call vars_in_expr
        cmp qword ptr [rax + VEC_LEN], 1
        jne .Llf_none
        mov rax, [rax + VEC_DATA]
        mov rax, [rax]
        mov [rsp + LF_KEY_VAR], rax
        mov rdi, [rsp + LF_MEM_VAL]
        call opcode_of
        cmp eax, OP_STORAGE
        jne .Llf_none
        mov rax, [rsp + LF_MEM_VAL]
        cmp qword ptr [rax + N_DATA + 8], (256 << 1) | 1
        jne .Llf_none
        cmp qword ptr [rax + N_DATA + 16], 1
        jne .Llf_none
        mov rax, [rax + N_DATA + 24]
        mov [rsp + LF_KEY], rax
        mov rdi, rax
        call only_add_in_expr
        test eax, eax
        jz .Llf_none
        # the continue must be {idx += 32, key += 1}
        mov rsi, [rsp + LF_IDX_VAR]
        LOADS rdi, VAR
        call mk2
        mov rdx, rax
        LOADS rdi, ADD
        mov esi, (32 << 1) | 1
        call mk3
        mov rdx, rax
        mov rsi, [rsp + LF_IDX_VAR]
        LOADS rdi, SETVAR
        call mk3
        mov [rsp + LF_UPD_IDX], rax
        mov rsi, [rsp + LF_KEY_VAR]
        LOADS rdi, VAR
        call mk2
        mov rdx, rax
        LOADS rdi, ADD
        mov esi, 3
        call mk3
        mov rdx, rax
        mov rsi, [rsp + LF_KEY_VAR]
        LOADS rdi, SETVAR
        call mk3
        mov [rsp + LF_UPD_KEY], rax
        mov rdi, [r14 + N_DATA + 16]
        lea rsi, [rsp + LF_UPD_IDX]
        mov edx, 2
        call set_equals
        test eax, eax
        jz .Llf_none
        # the start values
        mov qword ptr [rsp + LF_IDX_START], 0
        mov qword ptr [rsp + LF_KEY_START], 0
        mov qword ptr [rsp + LF_IDX_INIT], 0
        mov r12, [rbx + N_DATA + 32]    # setvars
        xor r13d, r13d
1:      cmp r13d, [r12 + N_AUX]
        jae 4f
        mov r14, [r12 + N_DATA + r13*8]
        mov rax, [r14 + N_DATA + 8]
        cmp rax, [rsp + LF_IDX_VAR]
        jne 2f
        mov rsi, rax
        LOADS rdi, VAR
        call mk2
        mov rsi, rax
        mov rdi, [rsp + LF_MEM_IDX]
        mov rdx, [r14 + N_DATA + 16]
        call replace
        mov [rsp + LF_IDX_START], rax
        mov rax, [r14 + N_DATA + 16]
        mov [rsp + LF_IDX_INIT], rax
        jmp 3f
2:      cmp rax, [rsp + LF_KEY_VAR]
        jne .Llf_none
        mov rsi, rax
        LOADS rdi, VAR
        call mk2
        mov rsi, rax
        mov rdi, [rsp + LF_KEY]
        mov rdx, [r14 + N_DATA + 16]
        call replace
        mov [rsp + LF_KEY_START], rax
3:      inc r13d
        jmp 1b
4:      # the condition: idx < count
        mov rdi, [rbx + N_DATA + 8]
        call vars_in_expr
        mov rdi, rax
        mov rsi, [rsp + LF_IDX_VAR]
        call vec_contains
        test eax, eax
        jz .Llf_none
        mov rdi, [rbx + N_DATA + 8]
        call opcode_of
        cmp eax, OP_GT
        jne .Llf_none
        # mem_count = (cond[1] + -1 * cond[2]) with the index at its start
        mov r12, [rbx + N_DATA + 8]
        mov rdx, [r12 + N_DATA + 16]
        LOADS rdi, MUL
        mov rsi, -1
        TAG rsi
        call mk3
        mov rdx, rax
        mov rsi, [r12 + N_DATA + 8]
        LOADS rdi, ADD
        call mk3
        mov r13, rax
        mov rsi, [rsp + LF_IDX_VAR]
        LOADS rdi, VAR
        call mk2
        mov rdi, r13
        mov rsi, rax
        mov rdx, [rsp + LF_IDX_INIT]
        call replace
        mov [rsp + LF_COUNT], rax
        # [('setmem', ('range', idx_start, count), ('storage', 256, 0, ('range', key_start, count / 32)))]
        mov rdi, [rsp + LF_IDX_START]
        call none_if_nil
        mov rdi, rax
        mov rsi, [rsp + LF_COUNT]
        call mk_range
        mov r13, rax
        LOADS rdi, DIV
        mov rsi, [rsp + LF_COUNT]
        mov edx, (32 << 1) | 1
        call mk3
        mov [rsp + LF_COUNT], rax
        mov rdi, [rsp + LF_KEY_START]
        call none_if_nil
        mov rdi, rax
        mov rsi, [rsp + LF_COUNT]
        call mk_range
        mov rcx, rax
        LOADS rdi, STORAGE
        mov esi, (256 << 1) | 1
        mov edx, 1
        call mk4
        mov rdx, rax
        mov rsi, r13
        LOADS rdi, SETMEM
        call mk3
        mov rdi, rax
        call mk_list1
        add rsp, 96
        LEAVE
.Llf_none:
        xor eax, eax
        add rsp, 96
        LEAVE
ENDF loop_to_setmem_from_storage

# set_equals(seq, values, count) -> eax: the sequence holds exactly these
# values (as a set)
FUNC set_equals
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        # every element of the sequence is one of the values
        xor r14d, r14d
1:      cmp r14d, [rbx + N_AUX]
        jae 3f
        mov rdi, [rbx + N_DATA + r14*8]
        mov rsi, r12
        mov rdx, r13
        call in_values
        test eax, eax
        jz .Lseq_no
        inc r14d
        jmp 1b
3:      # and every value is in the sequence
        xor r14d, r14d
4:      cmp r14, r13
        jae .Lseq_yes
        mov rdi, rbx
        mov rsi, [r12 + r14*8]
        call seq_index
        cmp rax, -1
        je .Lseq_no
        inc r14
        jmp 4b
.Lseq_yes:
        mov eax, 1
        LEAVE
.Lseq_no:
        xor eax, eax
        LEAVE
ENDF set_equals

# in_values(x, values, count) -> eax
FUNC in_values
        xor eax, eax
1:      cmp rax, rdx
        jae 2f
        cmp [rsi + rax*8], rdi
        je 3f
        inc rax
        jmp 1b
2:      xor eax, eax
        ret
3:      mov eax, 1
        ret
ENDF in_values

# vec_contains(vec, x) -> eax (by value)
FUNC vec_contains
        ENTER
        mov rbx, rdi
        mov r12, rsi
        xor r13d, r13d
1:      cmp r13, [rbx + VEC_LEN]
        jae 2f
        mov rax, [rbx + VEC_DATA]
        mov rdi, [rax + r13*8]
        mov rsi, r12
        call values_equal
        test eax, eax
        jnz 3f
        inc r13
        jmp 1b
2:      xor eax, eax
        LEAVE
3:      mov eax, 1
        LEAVE
ENDF vec_contains

# loop_to_setmem(line, arg, out): rewrite_trace's f
FUNC loop_to_setmem
        ENTER
        mov rbx, rdi
        mov r12, rdx
        call is_while_line
        test eax, eax
        jz 2f
        mov rdi, rbx
        call loop_to_setmem_impl
        test rax, rax
        jnz 1f
        mov rdi, rbx
        call loop_to_setmem_from_storage
        test rax, rax
        jz 2f
1:      mov rdi, r12
        mov rsi, rax
        call vec_extend_seq
        LEAVE
2:      mov rdi, r12
        mov rsi, rbx
        call vec_push
        LEAVE
ENDF loop_to_setmem

        .section .note.GNU-stack,"",@progbits
