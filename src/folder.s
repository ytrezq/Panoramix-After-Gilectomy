# The folder (port of folder.py): takes all the execution paths of a
# function and merges them into one, as concise as possible - the form
# that is easy to read by humans.
#
# Paths are lists of lines; ('or', path, path...) tuples hold alternative
# paths while folding.

.include "defs.inc"

        .section .rodata
.Ls_logname:        .asciz "panoramix.folder"
.Ls_folder_failed:  .asciz "folder failed in a function: %s"
.Ls_assert_or:      .asciz "folder: an or with more than two sides"
.Ls_assert_cond:    .asciz "folder: the conditions of the two sides don't match"
.Ls_assert_if:      .asciz "folder: an if of the wrong shape"
.Ls_assert_fold:    .asciz "folder: the paths don't start with two conditions"
.Ls_assert_ending:  .asciz "folder: an empty ending"
.Ls_assert_merged:  .asciz "folder: a merged if left"
.Ls_index_if:       .asciz "folder: an if without an else"
.Ls_index_path:     .asciz "folder: an empty path"

        .text

.macro B reg, n
        mov \reg, [rsp + 8*\n]
.endm

# --- the entry point ---

# fold(trace) -> list: the folded trace (the trace itself when folding
# fails, which is logged)
FUNC fold
        ENTER
        sub rsp, ERR_SIZEOF + 16
        mov rbx, rdi
        mov rdi, rsp
        call err_catch
        test eax, eax
        jnz .Lfold_failed
        mov rdi, rbx
        call as_paths
        mov rdi, rax
        call meta_fold_paths
        mov rdi, rax
        call fold_aux
        mov [rsp + ERR_SIZEOF], rax
        mov rdi, rax
        call has_merged_if
        test eax, eax
        jnz .Lfold_assert
        call err_end
        mov rax, [rsp + ERR_SIZEOF]
        add rsp, ERR_SIZEOF + 16
        LEAVE
.Lfold_failed:
        mov edi, LOG_ERROR
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_folder_failed]
        mov rcx, [r15 + CTX_ERR_MSG]
        call log_fmt
        mov rax, rbx
        add rsp, ERR_SIZEOF + 16
        LEAVE
.Lfold_assert:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_merged]
        call err_throw
ENDF fold

# has_merged_if(exp) -> eax: a ('merged_if', ...) anywhere
FUNC has_merged_if
        ENTER
        mov rbx, rdi
        call vec_new
        mov r12, rax
        mov rdi, rbx
        mov esi, OP_MERGED_IF
        mov rdx, r12
        call find_op_list
        xor eax, eax
        cmp qword ptr [r12 + VEC_LEN], 0
        setne al
        LEAVE
ENDF has_merged_if

# make_fands(exp, arg) / unmake_fands(exp, arg): the ors and ands of the
# expressions renamed while folding (the folder has its own or)
FUNC make_fands
        ENTER
        mov rbx, rdi
        call opcode_of
        LOADS rsi, FOR
        cmp eax, OP_OR
        je 1f
        LOADS rsi, FAND
        cmp eax, OP_AND
        je 1f
        mov rax, rbx
        LEAVE
1:      mov rdi, rbx
        call replace_head
        LEAVE
ENDF make_fands

FUNC unmake_fands
        ENTER
        mov rbx, rdi
        call opcode_of
        LOADS rsi, OR
        cmp eax, OP_FOR
        je 1f
        LOADS rsi, AND
        cmp eax, OP_FAND
        je 1f
        mov rax, rbx
        LEAVE
1:      mov rdi, rbx
        call replace_head
        LEAVE
ENDF unmake_fands

# replace_head(tuple, head) -> (head,) + tuple[1:]
FUNC replace_head
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call vec_new
        mov r13, rax
        mov rdi, rax
        mov rsi, r12
        call vec_push
        mov edx, [rbx + N_AUX]
        dec edx
        lea rsi, [rbx + N_DATA + 8]
        mov rdi, r13
        call vec_extend
        mov rdi, r13
        call vec_to_tuple
        LEAVE
ENDF replace_head

# as_paths(trace) -> list of paths: the trace unfolded into the
# branchless paths the contract can take, the ifs turned into conditions
FUNC as_paths
        ENTER
        lea rsi, [rip + make_fands]
        xor edx, edx
        call replace_f
        mov rbx, rax
        call vec_new
        mov r12, rax                    # the lines of the path so far
        call vec_new
        mov r13, rax                    # the paths
        mov rdi, rbx
        mov rsi, r12
        mov rdx, r13
        call as_paths_f
        mov rdi, r13
        call vec_to_list
        LEAVE
ENDF as_paths

# as_paths_f(trace, path, out): the paths of the trace appended to out,
# each starting with the lines of path (a vec, left as it was)
FUNC as_paths_f
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov [rsp], rdx
        mov rax, [r12 + VEC_LEN]
        mov [rsp + 8], rax              # the path's length on entry
        xor r13d, r13d
1:      cmp r13d, [rbx + N_AUX]
        jae 5f
        mov r14, [rbx + N_DATA + r13*8]
        mov rdi, r14
        call is_if_line
        test eax, eax
        jz 3f
        cmp dword ptr [r14 + N_AUX], 4
        jne .Lap_index
        lea eax, [r13 + 1]
        cmp eax, [rbx + N_AUX]
        jae 2f
        # The branches merge again and the trace goes on after the if.
        # Fold each branch on its own and keep the if as a single line -
        # unfolding it would double the number of paths.
        mov rdi, [r14 + N_DATA + 16]
        call fold
        push rax
        push rax
        mov rdi, [r14 + N_DATA + 24]
        call fold
        pop rdx
        pop rdx
        mov rcx, rax
        mov rsi, [r14 + N_DATA + 8]
        LOADS rdi, MERGED_IF
        call mk4
        mov rdi, r12
        mov rsi, rax
        call vec_push
        jmp 4f
2:      # both branches, with the condition and its negation
        mov rdi, r12
        mov rsi, [r14 + N_DATA + 8]
        call vec_push
        mov rdi, [r14 + N_DATA + 16]
        mov rsi, r12
        mov rdx, [rsp]
        call as_paths_f
        dec qword ptr [r12 + VEC_LEN]   # (the branch left the path as it found it)
        mov rdi, [r14 + N_DATA + 8]
        call is_zero
        mov rdi, r12
        mov rsi, rax
        call vec_push
        mov rdi, [r14 + N_DATA + 24]
        mov rsi, r12
        mov rdx, [rsp]
        call as_paths_f
        jmp 6f
3:      mov rdi, r14
        call opcode_of
        cmp eax, OP_LOOP_UPPER
        jne 31f
        # ('LOOP', trace, jd): the loop's id then its trace
        LOADS rdi, LOOP_UPPER
        mov rsi, [r14 + N_DATA + 16]
        call mk2
        mov rdi, r12
        mov rsi, rax
        call vec_push
        mov rdi, [r14 + N_DATA + 8]
        mov rsi, r12
        mov rdx, [rsp]
        call as_paths_f
        jmp 6f
31:     mov rdi, r12
        mov rsi, r14
        call vec_push
4:      inc r13d
        jmp 1b
5:      mov rdi, r12
        call vec_to_list
        mov rdi, [rsp]
        mov rsi, rax
        call vec_push
6:      mov rax, [rsp + 8]
        mov [r12 + VEC_LEN], rax
        add rsp, 16
        LEAVE
.Lap_index:
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_index_if]
        call err_throw
ENDF as_paths_f

# --- the final folding rules (fold_aux) ---

# is_terminating_op(id) -> eax: return, stop, selfdestruct, invalid,
# assert_fail, revert, continue, undefined
FUNC is_terminating_op
        mov eax, 1
        cmp edi, OP_RETURN
        je 1f
        cmp edi, OP_STOP
        je 1f
        cmp edi, OP_SELFDESTRUCT
        je 1f
        cmp edi, OP_INVALID
        je 1f
        cmp edi, OP_ASSERT_FAIL
        je 1f
        cmp edi, OP_REVERT
        je 1f
        cmp edi, OP_CONTINUE
        je 1f
        cmp edi, OP_UNDEFINED
        je 1f
        xor eax, eax
1:      ret
ENDF is_terminating_op

# car_opcode(seq) -> eax: the opcode of the first element (0 when empty)
FUNC car_opcode
        cmp dword ptr [rdi + N_AUX], 0
        je 1f
        mov rdi, [rdi + N_DATA]
        jmp opcode_of
1:      xor eax, eax
        ret
ENDF car_opcode

# fold_aux(trace) -> list
FUNC fold_aux
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 48
        .set FA_OUT, MATCH_BINDINGS_SIZE
        .set FA_TRUE, MATCH_BINDINGS_SIZE + 8
        .set FA_FALSE, MATCH_BINDINGS_SIZE + 16
        .set FA_LINES, MATCH_BINDINGS_SIZE + 24
        .set FA_MERGED, MATCH_BINDINGS_SIZE + 32
        mov rbx, rdi
        call vec_new
        mov [rsp + FA_OUT], rax
        xor r13d, r13d
.Lfa_line:
        cmp r13d, [rbx + N_AUX]
        jae .Lfa_done
        mov r14, [rbx + N_DATA + r13*8]
        inc r13d
        mov rdi, r14
        call opcode_of
        cmp eax, OP_WHILE
        jne 1f
        mov rdi, [r14 + N_DATA + 16]
        call fold
        mov rsi, rax
        mov rdi, [r14 + N_DATA + 8]
        mov rdx, [r14 + N_DATA + 24]
        mov rcx, [r14 + N_DATA + 32]
        call mk_while
        mov r14, rax
        jmp .Lfa_push
1:      cmp eax, OP_MERGED_IF
        jne 2f
        # the branches are folded already
        mov rdi, [r14 + N_DATA + 8]
        mov rsi, [r14 + N_DATA + 16]
        mov rdx, [r14 + N_DATA + 24]
        lea rcx, [rsp + FA_LINES]
        call try_merge_ifs
        mov rdi, [rsp + FA_OUT]
        mov rsi, [rsp + FA_LINES]
        call vec_extend_seq
        mov rax, [rsp + FA_MERGED]
        mov rdi, [rax + N_DATA + 8]
        mov rsi, [rax + N_DATA + 16]
        mov rdx, [rax + N_DATA + 24]
        call join_if
        mov rdi, [rsp + FA_OUT]
        mov rsi, rax
        call vec_extend_seq
        jmp .Lfa_line
2:      cmp eax, OP_IF
        jne .Lfa_push
        PAT rsi, "('if', ':cond', ':if_true')"
        mov rdi, r14
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 4f
        # a one-sided if: what follows is its else
        mov rdi, rbx
        mov rsi, r13
        call list_from
        mov [rsp + FA_FALSE], rax
        B rax, 1
        mov [rsp + FA_TRUE], rax
        # if_false == [('return', 0)] or [('revert', 0)] or starts with invalid
        mov rdi, [rsp + FA_FALSE]
        call is_end_block
        test eax, eax
        jz 3f
        # the end goes into the if, unless the if ends already
        mov rdi, [rsp + FA_TRUE]
        call seq_last
        test rax, rax
        jz 21f
        mov rdi, rax
        call opcode_of
        mov edi, eax
        call is_terminating_op
        test eax, eax
        jnz 22f
21:     mov rax, [rsp + FA_FALSE]
        mov rsi, [rax + N_DATA]
        mov rdi, [rsp + FA_TRUE]
        call list_append
        mov [rsp + FA_TRUE], rax
22:     mov rdi, [rsp + FA_TRUE]
        call fold_aux
        mov rsi, rax
        B rdi, 0
        mov rdx, [rsp + FA_FALSE]
        call mk_if
        mov rdi, [rsp + FA_OUT]
        mov rsi, rax
        call vec_push
        jmp .Lfa_done
3:      mov rdi, [rsp + FA_TRUE]
        call fold_aux
        mov rsi, rax
        B rdi, 0
        call mk_if1
        mov r14, rax
        jmp .Lfa_push
4:      PAT rsi, "('if', ':cond', ':if_true', ':if_false')"
        mov rdi, r14
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz .Lfa_assert
        B rdi, 1
        call fold_aux
        mov [rsp + FA_TRUE], rax
        B rdi, 2
        call fold_aux
        mov rdx, rax
        B rdi, 0
        mov rsi, [rsp + FA_TRUE]
        call join_if
        mov rdi, [rsp + FA_OUT]
        mov rsi, rax
        call vec_extend_seq
        jmp .Lfa_line
.Lfa_push:
        mov rdi, [rsp + FA_OUT]
        mov rsi, r14
        call vec_push
        jmp .Lfa_line
.Lfa_done:
        mov rdi, [rsp + FA_OUT]
        call vec_to_list
        add rsp, MATCH_BINDINGS_SIZE + 48
        LEAVE
.Lfa_assert:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_if]
        call err_throw
ENDF fold_aux

# is_end_block(trace) -> eax: [('return', 0)], [('revert', 0)], or a trace
# starting with invalid
FUNC is_end_block
        ENTER
        mov rbx, rdi
        cmp dword ptr [rbx + N_AUX], 0
        je 2f
        mov rdi, [rbx + N_DATA]
        call opcode_of
        cmp eax, OP_INVALID
        je 3f
        cmp dword ptr [rbx + N_AUX], 1
        jne 2f
        LOADS rdi, RETURN
        mov esi, 1
        call mk2
        cmp rax, [rbx + N_DATA]
        je 3f
        LOADS rdi, REVERT
        mov esi, 1
        call mk2
        cmp rax, [rbx + N_DATA]
        je 3f
2:      xor eax, eax
        LEAVE
3:      mov eax, 1
        LEAVE
ENDF is_end_block

# mk_if1(cond, if_true) -> ('if', cond, if_true)
FUNC mk_if1
        mov rdx, rsi
        mov rsi, rdi
        LOADS rdi, IF
        jmp mk3
ENDF mk_if1

# join_if(cond, if_true, if_false) -> list: an if without an else when
# the else isn't needed
FUNC join_if
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        cmp dword ptr [r12 + N_AUX], 0
        jne 1f
        cmp dword ptr [r13 + N_AUX], 0
        jne 1f
        xor edi, edi
        xor esi, esi
        call mk_list
        jmp .Lji_done
1:      cmp dword ptr [r12 + N_AUX], 0
        jne 2f
        # the else on the negated condition
        mov rdi, rbx
        call is_zero
        mov rbx, rax
        mov r12, r13
        xor edi, edi
        xor esi, esi
        call mk_list
        mov r13, rax
2:      cmp dword ptr [r13 + N_AUX], 0
        jne 3f
        mov rdi, rbx
        mov rsi, r12
        call mk_if1
        mov rdi, rax
        call mk_list1
        jmp .Lji_done
3:      # the if ends the execution: the else just follows it
        mov rdi, r12
        call seq_last
        mov rdi, rax
        call opcode_of
        mov edi, eax
        call is_terminating_op
        test eax, eax
        jz 4f
        mov rdi, r13
        call car_opcode
        cmp eax, OP_INVALID
        je 4f
        cmp eax, OP_REVERT
        je 4f
        mov rdi, rbx
        mov rsi, r12
        call mk_if1
        mov rdi, rax
        call mk_list1
        mov rdi, rax
        mov rsi, r13
        call list_concat
        jmp .Lji_done
4:      mov rdi, rbx
        mov rsi, r12
        mov rdx, r13
        call mk_if
        mov rdi, rax
        call mk_list1
.Lji_done:
        add rsp, 16
        LEAVE
ENDF join_if

# try_merge_ifs(cond, if_true, if_false, &out): the common beginning of
# the branches (out[0], a list) moved before the if (out[1])
FUNC try_merge_ifs
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov [rsp], rcx
        xor r14d, r14d
1:      cmp r14d, [r12 + N_AUX]
        jae 2f
        cmp r14d, [r13 + N_AUX]
        jae 2f
        mov rax, [r12 + N_DATA + r14*8]
        cmp rax, [r13 + N_DATA + r14*8]
        jne 2f
        inc r14d
        jmp 1b
2:      mov edi, r14d
        lea rsi, [r12 + N_DATA]
        call mk_list
        mov rcx, [rsp]
        mov [rcx], rax
        mov rdi, r12
        mov rsi, r14
        call list_from
        mov [rsp + 8], rax
        mov rdi, r13
        mov rsi, r14
        call list_from
        mov rdx, rax
        mov rdi, rbx
        mov rsi, [rsp + 8]
        call mk_if
        mov rcx, [rsp]
        mov [rcx + 8], rax
        add rsp, 16
        LEAVE
ENDF try_merge_ifs

# --- the folder proper ---

# meta_fold_paths(paths) -> list
FUNC meta_fold_paths
        ENTER
        mov rbx, rdi
        call vec_new
        mov r12, rax
        xor r13d, r13d
1:      cmp r13d, [rbx + N_AUX]
        jae 2f
        mov rax, [rbx + N_DATA + r13*8]
        cmp dword ptr [rax + N_AUX], 0
        je 11f
        mov rdi, r12
        mov rsi, rax
        call vec_push
11:     inc r13d
        jmp 1b
2:      mov rdi, r12
        call fold_paths_vec
        mov rdi, rax
        call flatten                    # if-else statements into if statements, if possible
        mov rdi, rax
        call cleanup_ors
        mov rdi, rax
        call make_ifs
        mov rdi, rax
        call merge_ifs
        mov rdi, rax
        lea rsi, [rip + unmake_fands]
        xor edx, edx
        call replace_f
        LEAVE
ENDF meta_fold_paths

# ends_exec(path) -> eax: the last line ends the execution (a two-sided
# or: both sides do)
FUNC ends_exec
        ENTER
        mov rbx, rdi
        cmp dword ptr [rbx + N_AUX], 0
        je .Lee_index
        call seq_last
        mov r12, rax
        mov rdi, rax
        call opcode_of
        cmp eax, OP_OR
        je 1f
        mov edi, eax
        call is_terminating_op
        LEAVE
1:      cmp dword ptr [r12 + N_AUX], 3
        jne .Lee_assert
        mov rdi, [r12 + N_DATA + 8]
        call ends_exec
        test eax, eax
        jz 2f
        mov rdi, [r12 + N_DATA + 16]
        call ends_exec
2:      LEAVE
.Lee_assert:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_or]
        call err_throw
.Lee_index:
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_index_path]
        call err_throw
ENDF ends_exec

# flatten(path) -> list: the ors whose first side ends the execution
# become an if without an else
FUNC flatten
        ENTER
        sub rsp, 16
        mov rbx, rdi
        call vec_new
        mov r12, rax
        xor r13d, r13d
1:      cmp r13d, [rbx + N_AUX]
        jae 5f
        mov r14, [rbx + N_DATA + r13*8]
        inc r13d
        mov rdi, r14
        call opcode_of
        cmp eax, OP_OR
        jne 4f
        cmp dword ptr [r14 + N_AUX], 3
        jne .Lfl_assert
        # sometimes, after folding, both paths are identical (a single
        # line each: their conditions), so the if can be skipped
        mov rax, [r14 + N_DATA + 8]
        cmp dword ptr [rax + N_AUX], 1
        jne 2f
        mov rax, [r14 + N_DATA + 16]
        cmp dword ptr [rax + N_AUX], 1
        je 1b
2:      mov rdi, [r14 + N_DATA + 8]
        call ends_exec
        test eax, eax
        jz 3f
        mov rdi, [r14 + N_DATA + 8]
        call flatten
        mov [rsp], rax
        mov rdi, [r14 + N_DATA + 16]
        call flatten
        mov rdi, [rsp]
        mov rsi, rax
        call try_merge
        mov rdi, r12
        mov rsi, rax
        call vec_extend_seq
        jmp 1b
3:      mov rdi, [r14 + N_DATA + 8]
        call flatten
        mov [rsp], rax
        mov rdi, [r14 + N_DATA + 16]
        call flatten
        mov rdx, rax
        mov rsi, [rsp]
        LOADS rdi, OR
        call mk3
        mov r14, rax
4:      mov rdi, r12
        mov rsi, r14
        call vec_push
        jmp 1b
5:      mov rdi, r12
        call vec_to_list
        add rsp, 16
        LEAVE
.Lfl_assert:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_or]
        call err_throw
ENDF flatten

# try_merge(one, two) -> list: the common ending of the two paths moved
# after a one-sided or
FUNC try_merge
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        # the shorter
        mov r13d, [rbx + N_AUX]
        mov eax, [r12 + N_AUX]
        cmp r13d, eax
        jbe 1f
        mov r13d, eax
1:      test r13d, r13d
        jz .Ltm_index
        mov r14d, 1                     # idx
2:      cmp r14d, r13d
        jae 3f
        mov ecx, [rbx + N_AUX]
        sub ecx, r14d
        mov rax, [rbx + N_DATA + rcx*8]
        mov ecx, [r12 + N_AUX]
        sub ecx, r14d
        cmp rax, [r12 + N_DATA + rcx*8]
        jne 3f
        inc r14d
        jmp 2b
3:      dec r14d
        jz 5f
        # [('or', one[:-idx], two[:-idx])] + one[-idx:]
        mov edi, [rbx + N_AUX]
        sub edi, r14d
        lea rsi, [rbx + N_DATA]
        call mk_list
        mov [rsp], rax
        mov edi, [r12 + N_AUX]
        sub edi, r14d
        lea rsi, [r12 + N_DATA]
        call mk_list
        mov rdx, rax
        mov rsi, [rsp]
        LOADS rdi, OR
        call mk3
        mov rdi, rax
        call mk_list1
        mov [rsp], rax
        mov ecx, [rbx + N_AUX]
        sub ecx, r14d
        mov rdi, rbx
        mov rsi, rcx
        call list_from
        mov rdi, [rsp]
        mov rsi, rax
        call list_concat
        add rsp, 16
        LEAVE
5:      # [('or', one)] + two
        LOADS rdi, OR
        mov rsi, rbx
        call mk2
        mov rdi, rax
        call mk_list1
        mov rdi, rax
        mov rsi, r12
        call list_concat
        add rsp, 16
        LEAVE
.Ltm_index:
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_index_path]
        call err_throw
ENDF try_merge

# cleanup_ors(path) -> list: the conditions leave the ors (the second
# side's, which is the negation of the first's)
FUNC cleanup_ors
        ENTER
        sub rsp, 16
        mov rbx, rdi
        call vec_new
        mov r12, rax
        xor r13d, r13d
.Lco_line:
        cmp r13d, [rbx + N_AUX]
        jae .Lco_done
        mov r14, [rbx + N_DATA + r13*8]
        mov rdi, r14
        call is_list
        test eax, eax
        jz 1f
        # a list in the path: spliced in
        mov edi, r13d
        lea rsi, [rbx + N_DATA]
        call mk_list
        mov rdi, rax
        mov rsi, r14
        call list_concat
        mov [rsp], rax
        mov rdi, rbx
        lea rsi, [r13 + 1]
        call list_from
        mov rdi, [rsp]
        mov rsi, rax
        call list_concat
        mov rbx, rax
        mov r14, [rbx + N_DATA + r13*8]
1:      inc r13d
        mov rdi, r14
        call opcode_of
        cmp eax, OP_OR
        jne .Lco_push
        cmp dword ptr [r14 + N_AUX], 2
        jne 2f
        # a one-sided or: the inside cleaned up, the next line of the
        # main path skipped
        mov rdi, [r14 + N_DATA + 8]
        call cleanup_ors
        mov rsi, rax
        LOADS rdi, OR
        call mk2
        mov r14, rax
        inc r13d
        jmp .Lco_push
2:      cmp dword ptr [r14 + N_AUX], 3
        jne .Lco_assert
        mov rax, [r14 + N_DATA + 8]
        cmp dword ptr [rax + N_AUX], 1
        jne 3f
        # the first side is just its condition: the second side alone
        mov rdi, [rax + N_DATA]
        call simplify_bool
        mov [rsp], rax
        mov rax, [r14 + N_DATA + 16]
        mov rdi, [rax + N_DATA]
        call is_zero
        mov rdi, [rsp]
        mov rsi, rax
        call comp_bool_check
        mov rdi, [r14 + N_DATA + 16]
        call cleanup_ors
        mov rsi, rax
        LOADS rdi, OR
        call mk2
        mov r14, rax
        jmp .Lco_push
3:      mov rdi, [rax + N_DATA]
        call is_zero
        mov [rsp], rax
        mov rax, [r14 + N_DATA + 16]
        mov rdi, [rax + N_DATA]
        call simplify_bool
        mov rdi, [rsp]
        mov rsi, rax
        call comp_bool_check
        mov rdi, [r14 + N_DATA + 8]
        call cleanup_ors
        mov [rsp], rax
        mov rdi, [r14 + N_DATA + 16]
        mov esi, 1
        call list_from
        mov rdi, rax
        call cleanup_ors
        mov rdx, rax
        mov rsi, [rsp]
        LOADS rdi, OR
        call mk3
        mov r14, rax
.Lco_push:
        mov rdi, r12
        mov rsi, r14
        call vec_push
        jmp .Lco_line
.Lco_done:
        mov rdi, r12
        call vec_to_list
        add rsp, 16
        LEAVE
.Lco_assert:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_or]
        call err_throw
ENDF cleanup_ors

# comp_bool_check(a, b): asserts comp_bool(a, b)
FUNC comp_bool_check
        ENTER
        call comp_bool
        cmp eax, TRI_TRUE
        jne 1f
        LEAVE
1:      mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_cond]
        call err_throw
ENDF comp_bool_check

# make_ifs(path) -> list: the ors become ifs, the first line of a side
# being its condition
FUNC make_ifs
        ENTER
        sub rsp, 16
        mov rbx, rdi
        call vec_new
        mov r12, rax
        xor r13d, r13d
1:      cmp r13d, [rbx + N_AUX]
        jae 4f
        mov r14, [rbx + N_DATA + r13*8]
        inc r13d
        mov rdi, r14
        call opcode_of
        cmp eax, OP_OR
        jne 3f
        mov rax, [r14 + N_DATA + 8]
        mov rdi, rax
        mov esi, 1
        call list_from
        mov rdi, rax
        call make_ifs
        mov [rsp], rax
        cmp dword ptr [r14 + N_AUX], 2
        jne 2f
        mov rax, [r14 + N_DATA + 8]
        mov rdi, [rax + N_DATA]
        mov rsi, [rsp]
        call mk_if1
        mov r14, rax
        jmp 3f
2:      cmp dword ptr [r14 + N_AUX], 3
        jne .Lmi_assert
        mov rdi, [r14 + N_DATA + 16]
        call make_ifs
        mov rdx, rax
        mov rax, [r14 + N_DATA + 8]
        mov rdi, [rax + N_DATA]
        mov rsi, [rsp]
        call mk_if
        mov r14, rax
3:      mov rdi, r12
        mov rsi, r14
        call vec_push
        jmp 1b
4:      mov rdi, r12
        call vec_to_list
        add rsp, 16
        LEAVE
.Lmi_assert:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_or]
        call err_throw
ENDF make_ifs

# merge_ifs(path) -> list: if-else sections with the same beginnings get
# the common lines moved before the if
FUNC merge_ifs
        ENTER
        sub rsp, 32
        mov rbx, rdi
        call vec_new
        mov r12, rax
        xor r13d, r13d
1:      cmp r13d, [rbx + N_AUX]
        jae .Lmg_done
        mov r14, [rbx + N_DATA + r13*8]
        inc r13d
        mov rdi, r14
        call opcode_of
        cmp eax, OP_IF
        jne .Lmg_push
        cmp dword ptr [r14 + N_AUX], 3
        jne 2f
        # a one-sided if: what follows is its else, merged and moved back
        mov rdi, [r14 + N_DATA + 16]
        call merge_ifs
        mov [rsp], rax
        mov rdi, rbx
        mov rsi, r13
        call list_from
        mov rdi, rax
        call merge_ifs
        mov rdx, rax
        mov rdi, [r14 + N_DATA + 8]
        mov rsi, [rsp]
        lea rcx, [rsp + 16]
        call try_merge_ifs
        mov rdi, r12
        mov rsi, [rsp + 16]
        call vec_extend_seq
        mov rax, [rsp + 24]             # ('if', cond, true, false)
        mov rdi, [rax + N_DATA + 8]
        mov rsi, [rax + N_DATA + 16]
        call mk_if1
        mov rdi, r12
        mov rsi, rax
        call vec_push
        mov rax, [rsp + 24]
        mov rdi, r12
        mov rsi, [rax + N_DATA + 24]
        call vec_extend_seq
        jmp .Lmg_done
2:      cmp dword ptr [r14 + N_AUX], 4
        jne .Lmg_assert
        mov rdi, [r14 + N_DATA + 16]
        call merge_ifs
        mov [rsp], rax
        mov rdi, [r14 + N_DATA + 24]
        call merge_ifs
        mov rdx, rax
        mov rdi, [r14 + N_DATA + 8]
        mov rsi, [rsp]
        lea rcx, [rsp + 16]
        call try_merge_ifs
        mov rdi, r12
        mov rsi, [rsp + 16]
        call vec_extend_seq
        mov rdi, r12
        mov rsi, [rsp + 24]
        call vec_push
        jmp 1b
.Lmg_push:
        mov rdi, r12
        mov rsi, r14
        call vec_push
        jmp 1b
.Lmg_done:
        mov rdi, r12
        call vec_to_list
        add rsp, 32
        LEAVE
.Lmg_assert:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_if]
        call err_throw
ENDF merge_ifs

# --- the folder's own or/and ---

# sorted_or(elems, count) -> ('or', ...) with the list elements sorted by
# length (stable, the shortest first), the others counting as length 0
FUNC sorted_or
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        # insertion sort on the array itself (stable)
        mov r13d, 1
1:      cmp r13, r12
        jae 4f
        mov r14, r13
2:      test r14, r14
        jz 3f
        mov rdi, [rbx + r14*8 - 8]
        call or_key
        mov [rsp], rax
        mov rdi, [rbx + r14*8]
        call or_key
        cmp [rsp], rax
        jle 3f
        mov rax, [rbx + r14*8 - 8]
        xchg rax, [rbx + r14*8]
        mov [rbx + r14*8 - 8], rax
        dec r14
        jmp 2b
3:      inc r13
        jmp 1b
4:      call vec_new
        mov r13, rax
        mov rdi, rax
        LOADS rsi, OR
        call vec_push
        mov rdi, r13
        mov rsi, rbx
        mov rdx, r12
        call vec_extend
        mov rdi, r13
        call vec_to_tuple
        add rsp, 16
        LEAVE
ENDF sorted_or

# or_key(v) -> rax: len(v) for a list, else 0
FUNC or_key
        ENTER
        mov rbx, rdi
        call is_list
        test eax, eax
        jz 1f
        mov eax, [rbx + N_AUX]
        LEAVE
1:      xor eax, eax
        LEAVE
ENDF or_key

# folder_or(args, count) -> ('or', ...): the lists ANDed, the ors flattened
FUNC folder_or
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call vec_new
        mov r13, rax
        xor r14d, r14d
1:      cmp r14, r12
        jae 4f
        mov rdi, [rbx + r14*8]
        mov rax, rdi
        push rax
        push rax
        call is_list
        pop rdi
        pop rdi
        test eax, eax
        jz 2f
        mov esi, [rdi + N_AUX]
        lea rdi, [rdi + N_DATA]
        call folder_and
        mov rdi, rax
2:      push rdi
        push rdi
        call opcode_of
        pop rdi
        pop rdi
        cmp eax, OP_OR
        jne 3f
        mov edx, [rdi + N_AUX]
        dec edx
        lea rsi, [rdi + N_DATA + 8]
        mov rdi, r13
        call vec_extend
        jmp 31f
3:      mov rsi, rdi
        mov rdi, r13
        call vec_push
31:     inc r14
        jmp 1b
4:      mov rdi, [r13 + VEC_DATA]
        mov rsi, [r13 + VEC_LEN]
        call sorted_or
        LEAVE
ENDF folder_or

# folder_and(args, count) -> list (or an or of lists when an argument is
# an or): the arguments concatenated, without ors inside
FUNC folder_and
        ENTER
        sub rsp, 32
        mov rbx, rdi
        mov r12, rsi
        call vec_new
        mov r13, rax
        xor r14d, r14d
1:      cmp r14, r12
        jae 5f
        mov rdi, [rbx + r14*8]
        mov [rsp], rdi
        call is_list
        test eax, eax
        jz 2f
        mov rdi, r13
        mov rsi, [rsp]
        call vec_extend_seq
        jmp 3f
2:      mov rdi, r13
        mov rsi, [rsp]
        call vec_push
3:      mov rdi, [rsp]
        call opcode_of
        cmp eax, OP_OR
        jne 4f
        # an or among the arguments: one and per variant, ored
        call vec_new
        mov r13, rax                    # the variants' ands
        mov rax, [rsp]
        mov [rsp + 8], rax
        mov qword ptr [rsp + 16], 1
31:     mov rcx, [rsp + 16]
        mov rax, [rsp + 8]
        cmp ecx, [rax + N_AUX]
        jae 32f
        # args[:idx] + (variant,) + args[idx+1:]
        lea rdi, [r12*8]
        call arena_alloc
        mov [rsp + 24], rax
        mov rdi, rax
        mov rsi, rbx
        lea rdx, [r12*8]
        call memcpy@PLT
        mov rcx, [rsp + 16]
        mov rax, [rsp + 8]
        mov rax, [rax + N_DATA + rcx*8]
        mov rdx, [rsp + 24]
        mov [rdx + r14*8], rax
        mov rdi, rdx
        mov rsi, r12
        call folder_and
        mov rdi, r13
        mov rsi, rax
        call vec_push
        inc qword ptr [rsp + 16]
        jmp 31b
32:     mov rdi, [r13 + VEC_DATA]
        mov rsi, [r13 + VEC_LEN]
        call folder_or
        add rsp, 32
        LEAVE
4:      inc r14
        jmp 1b
5:      mov rdi, r13
        call vec_to_list
        add rsp, 32
        LEAVE
ENDF folder_and

# starting_with(or_tuple, starting) -> list of the sides (lists) that
# start with the lines of `starting`, without them
FUNC starting_with
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call vec_new
        mov r13, rax
        mov r14d, 1
1:      cmp r14d, [rbx + N_AUX]
        jae 3f
        mov rdi, [rbx + N_DATA + r14*8]
        mov rsi, r12
        call starts_with
        test eax, eax
        jz 2f
        mov rdi, [rbx + N_DATA + r14*8]
        mov esi, [r12 + N_AUX]
        call list_from
        mov rdi, r13
        mov rsi, rax
        call vec_push
2:      inc r14d
        jmp 1b
3:      mov rdi, r13
        call vec_to_list
        LEAVE
ENDF starting_with

# starts_with(seq, prefix) -> eax
FUNC starts_with
        mov ecx, [rsi + N_AUX]
        cmp ecx, [rdi + N_AUX]
        ja 2f
        xor eax, eax
1:      cmp eax, ecx
        jae 3f
        mov rdx, [rdi + N_DATA + rax*8]
        cmp rdx, [rsi + N_DATA + rax*8]
        jne 2f
        inc eax
        jmp 1b
2:      xor eax, eax
        ret
3:      mov eax, 1
        ret
ENDF starts_with

# ending_with(or_tuple, ending) -> list of the sides that end with the
# lines of `ending`, without them
FUNC ending_with
        ENTER
        mov rbx, rdi
        mov r12, rsi
        cmp dword ptr [r12 + N_AUX], 0
        je .Lew_assert
        call vec_new
        mov r13, rax
        mov r14d, 1
1:      cmp r14d, [rbx + N_AUX]
        jae 3f
        mov rdi, [rbx + N_DATA + r14*8]
        mov rsi, r12
        call ends_with
        test eax, eax
        jz 2f
        mov rdi, [rbx + N_DATA + r14*8]
        mov edi, [rdi + N_AUX]
        sub edi, [r12 + N_AUX]
        mov rax, [rbx + N_DATA + r14*8]
        lea rsi, [rax + N_DATA]
        call mk_list
        mov rdi, r13
        mov rsi, rax
        call vec_push
2:      inc r14d
        jmp 1b
3:      mov rdi, r13
        call vec_to_list
        LEAVE
.Lew_assert:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_ending]
        call err_throw
ENDF ending_with

# ends_with(seq, suffix) -> eax
FUNC ends_with
        mov ecx, [rsi + N_AUX]
        mov edx, [rdi + N_AUX]
        cmp ecx, edx
        ja 2f
        sub edx, ecx                    # where the suffix would start
        xor eax, eax
1:      cmp eax, ecx
        jae 3f
        lea r8d, [rdx + rax]
        mov r9, [rdi + N_DATA + r8*8]
        cmp r9, [rsi + N_DATA + rax*8]
        jne 2f
        inc eax
        jmp 1b
2:      xor eax, eax
        ret
3:      mov eax, 1
        ret
ENDF ends_with

# fold_paths_vec(vec of paths) -> list
FUNC fold_paths_vec
        ENTER
        call vec_to_list
        mov rdi, rax
        call fold_paths
        LEAVE
ENDF fold_paths_vec

# sort_by_length_desc(vec): stable, the longest first
FUNC sort_by_length_desc
        ENTER
        mov rbx, [rdi + VEC_DATA]
        mov r12, [rdi + VEC_LEN]
        mov r13d, 1
1:      cmp r13, r12
        jae 4f
        mov r14, r13
2:      test r14, r14
        jz 3f
        mov rax, [rbx + r14*8 - 8]
        mov eax, [rax + N_AUX]
        mov rcx, [rbx + r14*8]
        mov ecx, [rcx + N_AUX]
        cmp eax, ecx
        jae 3f
        mov rax, [rbx + r14*8 - 8]
        xchg rax, [rbx + r14*8]
        mov [rbx + r14*8 - 8], rax
        dec r14
        jmp 2b
3:      inc r13
        jmp 1b
4:      LEAVE
ENDF sort_by_length_desc

# fold_paths(paths) -> list: merges the beginnings and the endings of the
# paths recursively
FUNC fold_paths
        ENTER
        sub rsp, 64
        .set FP_OR, 0
        .set FP_BEGIN, 8
        .set FP_END, 16
        .set FP_MERGED, 24
        .set FP_OUT, 32
        .set FP_I, 40
        .set FP_ORS, 48                 # fold_or's two results: the or...
        .set FP_REST, 56                # ...and the paths left to fold
        mov rbx, rdi
        cmp dword ptr [rbx + N_AUX], 0
        jne 1f
        xor edi, edi
        xor esi, esi
        call mk_list
        jmp .Lfp_done
1:      cmp dword ptr [rbx + N_AUX], 1
        jne 2f
        mov rax, [rbx + N_DATA]
        jmp .Lfp_done
2:      # the longest first
        call vec_new
        mov r12, rax
        mov rdi, rax
        mov rsi, rbx
        call vec_extend_seq
        mov rdi, r12
        call sort_by_length_desc
        mov rdi, r12
        call vec_to_list
        mov rbx, rax
        mov rdi, r12
        LOADS rsi, OR
        call vec_prepend
        mov rdi, r12
        call vec_to_tuple
        mov [rsp + FP_OR], rax          # ('or',) + paths
        mov r13, [rbx + N_DATA]         # the first (longest) path
        # merge the beginnings: how many lines do all the paths share?
        xor r14d, r14d
3:      cmp r14d, [r13 + N_AUX]
        ja 4f                           # (all the paths equal: python never ends)
        mov edi, r14d
        lea rsi, [r13 + N_DATA]
        call mk_list
        mov rdi, [rsp + FP_OR]
        mov rsi, rax
        call starting_with
        mov eax, [rax + N_AUX]
        cmp eax, [rbx + N_AUX]
        jne 4f
        inc r14d
        jmp 3b
4:      dec r14d
        mov [rsp + FP_BEGIN], r14       # begin_offset
        # and the endings
        mov r14d, 1
5:      cmp r14d, [r13 + N_AUX]
        ja 6f                           # (python: for_merge[0][-idx:] with idx > len is the whole path)
        mov edi, [r13 + N_AUX]
        sub edi, r14d
        mov rdi, rdi
        mov rsi, r13
        xchg rdi, rsi
        call list_from
        mov rdi, [rsp + FP_OR]
        mov rsi, rax
        call ending_with
        mov eax, [rax + N_AUX]
        cmp eax, [rbx + N_AUX]
        jne 6f
        inc r14d
        jmp 5b
6:      dec r14d
        mov [rsp + FP_END], r14         # end_offset
        # the paths without the common beginning...
        mov edi, [rsp + FP_BEGIN]
        lea rsi, [r13 + N_DATA]
        call mk_list
        mov [rsp + FP_MERGED], rax      # the beginning
        mov rdi, [rsp + FP_OR]
        mov rsi, rax
        call starting_with
        mov r12, rax                    # s_with
        cmp qword ptr [rsp + FP_END], 0
        je 8f
        # ...and without the common ending: beginning + [or(e_with)] + ending
        mov rdi, r12
        LOADS rsi, OR
        call list_prepend
        mov rdi, rax
        mov esi, [r13 + N_AUX]
        sub rsi, [rsp + FP_END]
        push rdi
        push rdi
        mov rdi, r13
        call list_from
        pop rdi
        pop rdi
        mov rsi, rax
        call ending_with
        mov rdi, rax
        mov esi, [rax + N_AUX]
        lea rdi, [rax + N_DATA]
        call folder_or
        mov rdi, rax
        call mk_list1
        mov rdi, [rsp + FP_MERGED]
        mov rsi, rax
        call list_concat
        mov [rsp + FP_MERGED], rax
        mov edi, [r13 + N_AUX]
        sub rdi, [rsp + FP_END]
        mov rsi, rdi
        mov rdi, r13
        call list_from
        mov rdi, [rsp + FP_MERGED]
        mov rsi, rax
        call list_concat
        mov [rsp + FP_MERGED], rax
        jmp 9f
8:      mov esi, [r12 + N_AUX]
        lea rdi, [r12 + N_DATA]
        call folder_or
        mov rdi, rax
        call mk_list1
        mov rdi, [rsp + FP_MERGED]
        mov rsi, rax
        call list_concat
        mov [rsp + FP_MERGED], rax
9:      # the ors in the merged path get folded further
        call vec_new
        mov [rsp + FP_OUT], rax
        mov qword ptr [rsp + FP_I], 0
10:     mov rcx, [rsp + FP_I]
        mov rax, [rsp + FP_MERGED]
        cmp ecx, [rax + N_AUX]
        jae 12f
        mov r14, [rax + N_DATA + rcx*8]
        inc qword ptr [rsp + FP_I]
        mov rdi, r14
        call opcode_of
        cmp eax, OP_OR
        je 11f
        mov rdi, [rsp + FP_OUT]
        mov rsi, r14
        call vec_push
        jmp 10b
11:     mov rdi, r14
        lea rsi, [rsp + FP_ORS]
        call fold_or
        mov rdi, [rsp + FP_OUT]
        mov rsi, [rsp + FP_ORS]
        call vec_push
        mov rdi, [rsp + FP_REST]
        call fold_paths
        mov rdi, [rsp + FP_OUT]
        mov rsi, rax
        call vec_extend_seq
        jmp 10b
12:     mov rdi, [rsp + FP_OUT]
        call vec_to_list
.Lfp_done:
        add rsp, 64
        LEAVE
ENDF fold_paths

# list_prepend(list, x) -> [x] + list
FUNC list_prepend
        ENTER
        mov rbx, rdi
        mov rdi, rsi
        call mk_list1
        mov rdi, rax
        mov rsi, rbx
        call list_concat
        LEAVE
ENDF list_prepend

# fold_or(('or', paths...), &out): out[0] = the or of the two stretches
# that split the paths in two, out[1] = the paths left to fold
FUNC fold_or
        ENTER
        sub rsp, 80
        .set FO_OUT, 0
        .set FO_LONGEST, 8
        .set FO_SHORTEST, 16
        .set FO_BEST_S, 40
        .set FO_S1, 48
        .set FO_S2, 56
        .set FO_ARGS, 64                # two slots: the arguments of or/and
        mov rbx, rdi
        mov [rsp + FO_OUT], rsi
        # every side has a first line
        mov r12d, 1
1:      cmp r12d, [rbx + N_AUX]
        jae 2f
        mov rax, [rbx + N_DATA + r12*8]
        cmp dword ptr [rax + N_AUX], 0
        je .Lfo_index
        inc r12d
        jmp 1b
2:      mov ecx, [rbx + N_AUX]
        mov rax, [rbx + N_DATA + rcx*8 - 8]
        mov [rsp + FO_LONGEST], rax     # the last side is the longest (sorted_or)
        # the first side whose first line differs from the longest's
        mov r12d, 1
3:      cmp r12d, [rbx + N_AUX]
        jae .Lfo_index
        mov rax, [rbx + N_DATA + r12*8]
        mov rax, [rax + N_DATA]
        mov rcx, [rsp + FO_LONGEST]
        cmp rax, [rcx + N_DATA]
        jne 4f
        inc r12d
        jmp 3b
4:      mov rax, [rbx + N_DATA + r12*8]
        mov [rsp + FO_SHORTEST], rax
        # every side starts with one of the two first lines
        mov r12d, 1
5:      cmp r12d, [rbx + N_AUX]
        jae 6f
        mov rax, [rbx + N_DATA + r12*8]
        mov rax, [rax + N_DATA]
        mov rcx, [rsp + FO_LONGEST]
        cmp rax, [rcx + N_DATA]
        je 51f
        mov rcx, [rsp + FO_SHORTEST]
        cmp rax, [rcx + N_DATA]
        jne .Lfo_assert
51:     inc r12d
        jmp 5b
6:      # find the two longest stretches that split the or into exactly
        # two parts
        mov r12d, 1                     # idx1
7:      mov rax, [rsp + FO_SHORTEST]
        cmp r12d, [rax + N_AUX]
        jae .Lfo_cut
        mov edi, r12d
        lea rsi, [rax + N_DATA]
        call mk_list
        mov rdi, rbx
        mov rsi, rax
        call starting_with
        mov [rsp + FO_S1], rax
        mov r13d, 1                     # idx2
8:      mov rax, [rsp + FO_LONGEST]
        cmp r13d, [rax + N_AUX]
        jae 9f
        mov edi, r13d
        lea rsi, [rax + N_DATA]
        call mk_list
        mov rdi, rbx
        mov rsi, rax
        call starting_with
        mov r14, rax                    # s2
        cmp r14, [rsp + FO_S1]          # (lists are hash-consed: same content, same node)
        jne 81f
        mov eax, [r14 + N_AUX]
        add eax, [r14 + N_AUX]
        inc eax
        cmp eax, [rbx + N_AUX]
        je .Lfo_best
81:     inc r13d
        jmp 8b
9:      inc r12d
        jmp 7b
.Lfo_best:
        # or_op(shortest[:idx1], longest[:idx2]), s1
        mov [rsp + FO_BEST_S], r14
        mov rax, [rsp + FO_SHORTEST]
        mov edi, r12d
        lea rsi, [rax + N_DATA]
        call mk_list
        mov [rsp + FO_ARGS], rax
        mov rax, [rsp + FO_LONGEST]
        mov edi, r13d
        lea rsi, [rax + N_DATA]
        call mk_list
        mov [rsp + FO_ARGS + 8], rax
        lea rdi, [rsp + FO_ARGS]
        mov esi, 2
        call folder_or
        mov rcx, [rsp + FO_OUT]
        mov [rcx], rax
        mov rax, [rsp + FO_BEST_S]
        mov [rcx + 8], rax
        add rsp, 80
        LEAVE
.Lfo_cut:
        # cut the first line, merge the remaining paths if possible
        mov rax, [rsp + FO_SHORTEST]
        mov rdi, [rax + N_DATA]
        call mk_list1
        mov rdi, rbx
        mov rsi, rax
        call starting_with
        mov rdi, rax
        call fold_paths
        mov [rsp + FO_S1], rax
        mov rax, [rsp + FO_LONGEST]
        mov rdi, [rax + N_DATA]
        call mk_list1
        mov rdi, rbx
        mov rsi, rax
        call starting_with
        mov rdi, rax
        call fold_paths
        mov [rsp + FO_S2], rax
        # ('or', and(shortest[0], s1), and(longest[0], s2)), []
        mov rax, [rsp + FO_SHORTEST]
        mov rax, [rax + N_DATA]
        mov [rsp + FO_ARGS], rax
        mov rax, [rsp + FO_S1]
        mov [rsp + FO_ARGS + 8], rax
        lea rdi, [rsp + FO_ARGS]
        mov esi, 2
        call folder_and
        mov [rsp + FO_S1], rax          # the shorter path
        mov rax, [rsp + FO_LONGEST]
        mov rax, [rax + N_DATA]
        mov [rsp + FO_ARGS], rax
        mov rax, [rsp + FO_S2]
        mov [rsp + FO_ARGS + 8], rax
        lea rdi, [rsp + FO_ARGS]
        mov esi, 2
        call folder_and
        mov rdx, rax                    # the longer path
        mov rsi, [rsp + FO_S1]
        LOADS rdi, OR
        call mk3
        mov rcx, [rsp + FO_OUT]
        mov [rcx], rax
        xor edi, edi
        xor esi, esi
        call mk_list
        mov rcx, [rsp + FO_OUT]
        mov [rcx + 8], rax
        add rsp, 80
        LEAVE
.Lfo_assert:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_fold]
        call err_throw
.Lfo_index:
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_index_path]
        call err_throw
ENDF fold_or

        .section .note.GNU-stack,"",@progbits
