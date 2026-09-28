# Growable arrays of values, allocated in the arena (no free: they die with
# the arena; a grown buffer just leaves its old one behind).

.include "defs.inc"

        .text

# vec_new() -> rax
FUNC vec_new
        ENTER
        mov edi, VEC_SIZEOF + 16*8
        call arena_alloc_raw
        lea rcx, [rax + VEC_SIZEOF]
        mov [rax + VEC_DATA], rcx
        mov qword ptr [rax + VEC_LEN], 0
        mov qword ptr [rax + VEC_CAP], 16
        LEAVE
ENDF vec_new

# vec_new_cap(n) -> rax: with room for n
FUNC vec_new_cap
        ENTER
        mov rbx, rdi
        cmp rbx, 4
        jae 1f
        mov ebx, 4
1:      lea rdi, [rbx*8 + VEC_SIZEOF]
        call arena_alloc_raw
        lea rcx, [rax + VEC_SIZEOF]
        mov [rax + VEC_DATA], rcx
        mov qword ptr [rax + VEC_LEN], 0
        mov [rax + VEC_CAP], rbx
        LEAVE
ENDF vec_new_cap

# vec_push(vec, value)
FUNC vec_push
        mov rax, [rdi + VEC_LEN]
        cmp rax, [rdi + VEC_CAP]
        jae 1f
        mov rcx, [rdi + VEC_DATA]
        mov [rcx + rax*8], rsi
        inc qword ptr [rdi + VEC_LEN]
        ret
1:      ENTER
        mov rbx, rdi
        mov r12, rsi
        mov rdi, [rbx + VEC_CAP]
        shl rdi, 4                      # (twice the room, in bytes)
        call arena_alloc_raw            # (first: past the memory limit it
        mov rdi, rax                    # throws, and the vector must stay whole)
        mov r13, rax
        mov rsi, [rbx + VEC_DATA]
        mov rdx, [rbx + VEC_LEN]
        shl rdx, 3
        call memcpy@PLT
        mov [rbx + VEC_DATA], r13
        shl qword ptr [rbx + VEC_CAP], 1
        mov rax, [rbx + VEC_LEN]
        mov [r13 + rax*8], r12
        inc qword ptr [rbx + VEC_LEN]
        LEAVE
ENDF vec_push

# vec_extend(vec, values_ptr, count): the room made once, the values
# copied (values_ptr may point into the vector itself: a grown vector
# leaves its old buffer as it was)
FUNC vec_extend
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        test r13, r13
        jz 9f
        mov rax, [rbx + VEC_LEN]
        add rax, r13                    # the length needed
        cmp rax, [rbx + VEC_CAP]
        jbe 2f
        mov rcx, [rbx + VEC_CAP]
        shl rcx, 1
        cmp rcx, rax
        cmovb rcx, rax
        push rcx
        push rcx
        lea rdi, [rcx*8]
        call arena_alloc_raw            # (first: see vec_push)
        mov r14, rax
        mov rdi, rax
        mov rsi, [rbx + VEC_DATA]
        mov rdx, [rbx + VEC_LEN]
        shl rdx, 3
        call memcpy@PLT
        mov [rbx + VEC_DATA], r14
        pop rcx
        pop rcx
        mov [rbx + VEC_CAP], rcx
2:      mov rdi, [rbx + VEC_LEN]
        shl rdi, 3
        add rdi, [rbx + VEC_DATA]
        mov rsi, r12
        mov rdx, r13
        shl rdx, 3
        call memcpy@PLT
        add [rbx + VEC_LEN], r13
9:      LEAVE
ENDF vec_extend

# vec_extend_seq(vec, tuple_or_list)
FUNC vec_extend_seq
        mov edx, [rsi + N_AUX]
        add rsi, N_DATA
        jmp vec_extend
ENDF vec_extend_seq

# vec_to_list(vec) -> rax / vec_to_tuple(vec) -> rax
FUNC vec_to_list
        mov rsi, [rdi + VEC_DATA]
        mov rdi, [rdi + VEC_LEN]
        jmp mk_list
ENDF vec_to_list

# vec_to_list_like(vec, orig) -> rax: vec_to_list(vec) - orig itself
# when it is a list of these very elements (a pass over a trace that
# changed none of its lines: no hashing, no lookup of a long list)
FUNC vec_to_list_like
        test sil, 1
        jnz 9f
        test rsi, rsi
        jz 9f
        cmp dword ptr [rsi + N_KIND], K_LIST
        jne 9f
        mov rcx, [rdi + VEC_LEN]
        mov eax, [rsi + N_AUX]
        cmp rcx, rax
        jne 9f
        mov rdx, [rdi + VEC_DATA]
        xor eax, eax
1:      cmp rax, rcx
        jae 8f
        mov r8, [rdx + rax*8]
        cmp r8, [rsi + N_DATA + rax*8]
        jne 9f
        inc rax
        jmp 1b
8:      mov rax, rsi
        ret
9:      jmp vec_to_list
ENDF vec_to_list_like

FUNC vec_to_tuple
        mov rsi, [rdi + VEC_DATA]
        mov rdi, [rdi + VEC_LEN]
        jmp mk_tuple
ENDF vec_to_tuple

# vec_pop(vec) -> rax (NIL if empty)
FUNC vec_pop
        mov rax, [rdi + VEC_LEN]
        test rax, rax
        jz 1f
        dec rax
        mov [rdi + VEC_LEN], rax
        mov rcx, [rdi + VEC_DATA]
        mov rax, [rcx + rax*8]
        ret
1:      xor eax, eax
        ret
ENDF vec_pop

        .section .note.GNU-stack,"",@progbits
