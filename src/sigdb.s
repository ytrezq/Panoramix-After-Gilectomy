# The signature database (utils/supplement.py): the names and parameters
# of the functions by selector. The source is panoramix's abi_dump.xz
# (one JSON object per line, sorted by selector); it is converted once,
# with liblzma and the small JSON parser below, into a flat file that is
# mmap'ed and searched by dichotomy afterwards:
#
#   header:  "PANSIGS1" (8), u32 count, u32 strings size, u32 inputs
#            count, u32 pad                                    (24 bytes)
#   entries: count * { u32 selector, u32 name, u32 inputs, u32 ninputs }
#            (name: an offset in the strings; inputs: an index in the
#            inputs)
#   inputs:  inputs count * { u32 type, u32 name }   (offsets in the strings)
#   strings: NUL-terminated, deduplicated
#
# The file lives in the cache directory ($XDG_CACHE_HOME/panoramix or
# ~/.cache/panoramix, as python's), or where $PANORAMIX_SIGDB points.

.include "defs.inc"

        .set SH_MAGIC, 0
        .set SH_COUNT, 8
        .set SH_STRINGS, 12
        .set SH_NINPUTS, 16
        .set SH_SIZEOF, 24
        .set SE_SELECTOR, 0
        .set SE_NAME, 4
        .set SE_INPUTS, 8
        .set SE_NINPUTS, 12
        .set SE_SIZEOF, 16
        .set SI_TYPE, 0
        .set SI_NAME, 4
        .set SI_SIZEOF, 8

        # lzma_stream (liblzma)
        .set LZ_NEXT_IN, 0
        .set LZ_AVAIL_IN, 8
        .set LZ_NEXT_OUT, 24
        .set LZ_AVAIL_OUT, 32
        .set LZ_SIZEOF, 136
        .set LZMA_OK, 0
        .set LZMA_STREAM_END, 1
        .set LZMA_CONCATENATED, 8

        .section .rodata
.Ls_magic:      .ascii "PANSIGS1"
.Ls_env_db:     .asciz "PANORAMIX_SIGDB"
.Ls_env_xdg:    .asciz "XDG_CACHE_HOME"
.Ls_env_home:   .asciz "HOME"
.Ls_cache_sub:  .asciz "/panoramix"
.Ls_dot_cache:  .asciz "/.cache"
.Ls_db_file:    .asciz "/abi_db.bin"
.Ls_logname:    .asciz "panoramix.sigdb"
.Ls_loaded:     .asciz "%u signatures loaded from %s"
.Ls_no_db:      .asciz "no signature database (%s): the functions will be unknown; build one with `panasm build-db abi_dump.xz`"
.Ls_bad_db:     .asciz "%s isn't a signature database"
.Ls_building:   .asciz "Loading %s into %s..."
.Ls_built:      .asciz "%s is ready: %u signatures"
.Ls_cant_read:  .asciz "can't read %s"
.Ls_cant_write: .asciz "can't write %s"
.Ls_lzma_error: .asciz "%s: lzma error %d"
.Ls_json_error: .asciz "%s: line %u: not the json expected"
.Ls_selector:   .asciz "selector"
.Ls_abi:        .asciz "abi"
.Ls_name:       .asciz "name"
.Ls_inputs:     .asciz "inputs"
.Ls_type:       .asciz "type"
.Ls_true:       .asciz "true"
.Ls_false:      .asciz "false"
.Ls_null:       .asciz "null"
.Ls_tmp_suffix: .asciz ".tmp"

        .section .bss
        .align 8
sigdb_base:     .quad 0                 # the mmap'ed file
sigdb_size:     .quad 0
sigdb_entries:  .quad 0
sigdb_inputs:   .quad 0
sigdb_strings:  .quad 0
sigdb_count:    .quad 0
sigdb_ninputs:  .quad 0
sigdb_nstrings: .quad 0                 # the size of the strings
sigdb_state:    .quad 0                 # 0 not tried, 1 loaded, 2 none
sigdb_lock:     .quad 0

        .text

# --- the cache path ---

# sigdb_path(sb): the path of the database file appended
FUNC sigdb_path
        ENTER
        mov rbx, rdi
        lea rdi, [rip + .Ls_env_db]
        call getenv@PLT
        test rax, rax
        jz 1f
        mov rdi, rbx
        mov rsi, rax
        call sb_append_c
        LEAVE
1:      mov rdi, rbx
        call cache_dir_path
        mov rdi, rbx
        lea rsi, [rip + .Ls_db_file]
        call sb_append_c
        LEAVE
ENDF sigdb_path

# cache_dir_path(sb): $XDG_CACHE_HOME/panoramix or ~/.cache/panoramix
FUNC cache_dir_path
        ENTER
        mov rbx, rdi
        lea rdi, [rip + .Ls_env_xdg]
        call getenv@PLT
        test rax, rax
        jz 1f
        cmp byte ptr [rax], 0
        je 1f
        mov rdi, rbx
        mov rsi, rax
        call sb_append_c
        jmp 2f
1:      lea rdi, [rip + .Ls_env_home]
        call getenv@PLT
        test rax, rax
        jz 3f
        mov rdi, rbx
        mov rsi, rax
        call sb_append_c
3:      mov rdi, rbx
        lea rsi, [rip + .Ls_dot_cache]
        call sb_append_c
2:      mov rdi, rbx
        lea rsi, [rip + .Ls_cache_sub]
        call sb_append_c
        LEAVE
ENDF cache_dir_path

# --- loading ---

# sigdb_load() -> eax: the database mapped (once), 1 if there is one
FUNC sigdb_load
        ENTER
        sub rsp, 160
        .set SL_ST, 0                   # struct stat (144 bytes)
        .set SL_SB, 144
        .set SL_FD, 152
        cmp qword ptr [rip + sigdb_state], 0
        jne .Lsl_done
        lea rdi, [rip + sigdb_lock]
        call spin_lock
        cmp qword ptr [rip + sigdb_state], 0
        jne .Lsl_unlock
        call sb_new
        mov [rsp + SL_SB], rax
        mov rdi, rax
        call sigdb_path
        mov rax, [rsp + SL_SB]
        mov rdi, [rax + SB_BUF]
        xor esi, esi                    # O_RDONLY
        call open@PLT
        test eax, eax
        js .Lsl_none
        mov [rsp + SL_FD], rax
        mov edi, eax
        lea rsi, [rsp + SL_ST]
        call fstat@PLT
        mov rax, [rsp + SL_ST + 48]     # st_size
        mov [rip + sigdb_size], rax
        cmp rax, SH_SIZEOF
        jb .Lsl_bad
        xor edi, edi
        mov rsi, rax
        mov edx, 1                      # PROT_READ
        mov ecx, 2                      # MAP_PRIVATE
        mov r8, [rsp + SL_FD]
        xor r9d, r9d
        call mmap@PLT
        mov rbx, rax
        mov rdi, [rsp + SL_FD]
        call close@PLT
        cmp rbx, -1
        je .Lsl_none
        mov [rip + sigdb_base], rbx
        lea rdi, [rip + .Ls_magic]
        mov rsi, rbx
        mov edx, 8
        call memcmp@PLT
        test eax, eax
        jnz .Lsl_bad
        # the sections must fill the file exactly, the strings end with a
        # NUL (a file cut short by an interrupted build is refused)
        mov eax, [rbx + SH_COUNT]
        imul rax, rax, SE_SIZEOF
        mov ecx, [rbx + SH_NINPUTS]
        imul rcx, rcx, SI_SIZEOF
        add rax, rcx
        mov ecx, [rbx + SH_STRINGS]
        test ecx, ecx
        jz .Lsl_bad
        add rax, rcx
        add rax, SH_SIZEOF
        cmp rax, [rip + sigdb_size]
        jne .Lsl_bad
        cmp byte ptr [rbx + rax - 1], 0
        jne .Lsl_bad
        mov eax, [rbx + SH_STRINGS]
        mov [rip + sigdb_nstrings], rax
        mov eax, [rbx + SH_NINPUTS]
        mov [rip + sigdb_ninputs], rax
        mov eax, [rbx + SH_COUNT]
        mov [rip + sigdb_count], rax
        lea rcx, [rbx + SH_SIZEOF]
        mov [rip + sigdb_entries], rcx
        imul rax, rax, SE_SIZEOF
        add rcx, rax
        mov [rip + sigdb_inputs], rcx
        mov eax, [rbx + SH_NINPUTS]
        imul rax, rax, SI_SIZEOF
        add rcx, rax
        mov [rip + sigdb_strings], rcx
        lea rax, [rip + sigdb_lookup]
        mov [rip + sig_db_hook], rax
        mov qword ptr [rip + sigdb_state], 1
        mov edi, LOG_INFO
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_loaded]
        mov rcx, [rip + sigdb_count]
        mov rax, [rsp + SL_SB]
        mov r8, [rax + SB_BUF]
        call log_fmt
        jmp .Lsl_unlock
.Lsl_bad:
        mov edi, LOG_WARNING
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_bad_db]
        mov rax, [rsp + SL_SB]
        mov rcx, [rax + SB_BUF]
        call log_fmt
        jmp 1f
.Lsl_none:
        mov edi, LOG_WARNING
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_no_db]
        mov rax, [rsp + SL_SB]
        mov rcx, [rax + SB_BUF]
        call log_fmt
1:      mov qword ptr [rip + sigdb_state], 2
.Lsl_unlock:
        lea rdi, [rip + sigdb_lock]
        call spin_unlock
.Lsl_done:
        xor eax, eax
        cmp qword ptr [rip + sigdb_state], 1
        sete al
        add rsp, 160
        LEAVE
ENDF sigdb_load

# spin_lock(&word) / spin_unlock(&word)
FUNC spin_lock
1:      xor eax, eax
        mov ecx, 1
        lock cmpxchg [rdi], rcx
        jz 2f
        pause
        jmp 1b
2:      ret
ENDF spin_lock

FUNC spin_unlock
        mov qword ptr [rdi], 0
        ret
ENDF spin_unlock

# sigdb_lookup(selector) -> rax: the (name, inputs) of a selector, or 0
# (memoized on the context: the same entry is asked for repeatedly)
FUNC sigdb_lookup
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov edi, MEMO_SIGDB
        mov rsi, rbx
        TAG rsi
        call memo_get
        test rax, rax
        jz 1f
        cmp rax, 1                      # the "no entry" mark
        jne .Lsq_ret
        xor eax, eax
        jmp .Lsq_ret
1:      # dichotomy on the sorted selectors
        xor r12d, r12d                  # lo
        mov r13, [rip + sigdb_count]    # hi
2:      cmp r12, r13
        jae .Lsq_none
        lea rax, [r12 + r13]
        shr rax, 1
        mov rcx, rax
        imul rcx, rcx, SE_SIZEOF
        add rcx, [rip + sigdb_entries]
        mov edx, [rcx + SE_SELECTOR]
        cmp rdx, rbx
        je 3f
        jb 4f
        mov r13, rax
        jmp 2b
4:      lea r12, [rax + 1]
        jmp 2b
3:      mov r14, rcx                    # the entry
        # its offsets within the file (else: as if it wasn't there)
        mov eax, [r14 + SE_INPUTS]
        mov ecx, [r14 + SE_NINPUTS]
        add rax, rcx
        cmp rax, [rip + sigdb_ninputs]
        ja .Lsq_none
        mov eax, [r14 + SE_NAME]
        cmp rax, [rip + sigdb_nstrings]
        jae .Lsq_none
        xor ecx, ecx
31:     cmp ecx, [r14 + SE_NINPUTS]
        jae 32f
        mov eax, [r14 + SE_INPUTS]
        add rax, rcx
        imul rax, rax, SI_SIZEOF
        add rax, [rip + sigdb_inputs]
        mov edx, [rax + SI_TYPE]
        cmp rdx, [rip + sigdb_nstrings]
        jae .Lsq_none
        mov edx, [rax + SI_NAME]
        cmp rdx, [rip + sigdb_nstrings]
        jae .Lsq_none
        inc ecx
        jmp 31b
32:     # (name, [(type, name), ...])
        call vec_new
        mov [rsp], rax
        xor r12d, r12d
5:      cmp r12d, [r14 + SE_NINPUTS]
        jae 6f
        mov eax, [r14 + SE_INPUTS]
        add rax, r12
        imul rax, rax, SI_SIZEOF
        add rax, [rip + sigdb_inputs]
        mov edi, [rax + SI_TYPE]
        add rdi, [rip + sigdb_strings]
        call str_intern_c
        mov [rsp + 8], rax
        mov eax, [r14 + SE_INPUTS]
        add rax, r12
        imul rax, rax, SI_SIZEOF
        add rax, [rip + sigdb_inputs]
        mov edi, [rax + SI_NAME]
        add rdi, [rip + sigdb_strings]
        call str_intern_c
        mov rdi, [rsp + 8]
        mov rsi, rax
        call mk2
        mov rdi, [rsp]
        mov rsi, rax
        call vec_push
        inc r12d
        jmp 5b
6:      mov rdi, [rsp]
        call vec_to_list
        mov r12, rax
        mov edi, [r14 + SE_NAME]
        add rdi, [rip + sigdb_strings]
        call str_intern_c
        mov rdi, rax
        mov rsi, r12
        call mk2
        mov r12, rax
        mov edi, MEMO_SIGDB
        mov rsi, rbx
        TAG rsi
        mov rdx, rax
        call memo_put
        mov rax, r12
        jmp .Lsq_ret
.Lsq_none:
        mov edi, MEMO_SIGDB
        mov rsi, rbx
        TAG rsi
        mov edx, 1
        call memo_put
        xor eax, eax
.Lsq_ret:
        add rsp, 16
        LEAVE
ENDF sigdb_lookup

# --- building ---

        # the builder's state
        .set BD_ENTRIES, 0              # u32[4] * count, malloc'ed
        .set BD_NENTRIES, 8
        .set BD_CAPENTRIES, 16
        .set BD_INPUTS, 24              # u32[2] * count
        .set BD_NINPUTS, 32
        .set BD_CAPINPUTS, 40
        .set BD_STRINGS, 48             # the blob
        .set BD_NSTRINGS, 56
        .set BD_CAPSTRINGS, 64
        .set BD_TABLE, 72               # hash -> offset + 1, for the dedup
        .set BD_TABLECAP, 80
        .set BD_TABLECOUNT, 88
        .set BD_LINES, 96
        .set BD_SIZEOF, 104

# sigdb_build(xz_path, out_path) -> eax: 0 on success. out_path 0 means
# the cache path.
FUNC sigdb_build
        ENTER
        sub rsp, LZ_SIZEOF + 104        # (a multiple of 16)
        .set BF_LZ, 0
        .set BF_XZ, LZ_SIZEOF
        .set BF_OUT, LZ_SIZEOF + 8
        .set BF_IN, LZ_SIZEOF + 16      # the compressed input (malloc'ed)
        .set BF_INLEN, LZ_SIZEOF + 24
        .set BF_BUF, LZ_SIZEOF + 32     # the decoded text buffer
        .set BF_BUFCAP, LZ_SIZEOF + 40
        .set BF_BUFLEN, LZ_SIZEOF + 48
        .set BF_BD, LZ_SIZEOF + 56
        .set BF_OUTSB, LZ_SIZEOF + 64
        .set BF_LINE, LZ_SIZEOF + 72
        .set BF_RC, LZ_SIZEOF + 80
        mov [rsp + BF_XZ], rdi
        mov [rsp + BF_OUT], rsi
        call sb_new
        mov [rsp + BF_OUTSB], rax
        mov rsi, [rsp + BF_OUT]
        test rsi, rsi
        jz 1f
        mov rdi, rax
        call sb_append_c
        jmp 2f
1:      mov rdi, rax
        call sigdb_path
2:      mov edi, LOG_INFO
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_building]
        mov rcx, [rsp + BF_XZ]
        mov rax, [rsp + BF_OUTSB]
        mov r8, [rax + SB_BUF]
        call log_fmt
        # the compressed file
        mov rdi, [rsp + BF_XZ]
        lea rsi, [rsp + BF_INLEN]
        call read_file
        test rax, rax
        jz .Lsb_cant_read
        mov [rsp + BF_IN], rax
        # the decoder
        lea rdi, [rsp + BF_LZ]
        xor esi, esi
        mov edx, LZ_SIZEOF
        call memset@PLT
        lea rdi, [rsp + BF_LZ]
        mov rsi, -1                     # no memory limit
        mov edx, LZMA_CONCATENATED
        call lzma_stream_decoder@PLT
        test eax, eax
        jnz .Lsb_lzma_error
        mov rax, [rsp + BF_IN]
        mov [rsp + BF_LZ + LZ_NEXT_IN], rax
        mov rax, [rsp + BF_INLEN]
        mov [rsp + BF_LZ + LZ_AVAIL_IN], rax
        mov edi, 4 << 20
        call xmalloc
        mov [rsp + BF_BUF], rax
        mov qword ptr [rsp + BF_BUFCAP], 4 << 20
        mov qword ptr [rsp + BF_BUFLEN], 0
        call builder_new
        mov [rsp + BF_BD], rax
.Lsb_decode:
        # decode into the free part of the buffer, then take the complete
        # lines out of it
        mov rax, [rsp + BF_BUF]
        add rax, [rsp + BF_BUFLEN]
        mov [rsp + BF_LZ + LZ_NEXT_OUT], rax
        mov rax, [rsp + BF_BUFCAP]
        sub rax, [rsp + BF_BUFLEN]
        mov [rsp + BF_LZ + LZ_AVAIL_OUT], rax
        lea rdi, [rsp + BF_LZ]
        xor esi, esi                    # LZMA_RUN, LZMA_FINISH once the input is consumed
        cmp qword ptr [rsp + BF_LZ + LZ_AVAIL_IN], 0
        jne 21f
        mov esi, 3
21:     call lzma_code@PLT
        mov [rsp + BF_RC], rax
        cmp eax, LZMA_OK
        je 3f
        cmp eax, LZMA_STREAM_END
        jne .Lsb_lzma_error
3:      mov rax, [rsp + BF_BUFCAP]
        sub rax, [rsp + BF_LZ + LZ_AVAIL_OUT]
        mov [rsp + BF_BUFLEN], rax
        # the lines
        mov rbx, [rsp + BF_BUF]         # the start of the current line
        mov r12, rbx
        add r12, [rsp + BF_BUFLEN]      # the end of the text
4:      mov rdi, rbx
        mov esi, 10
        mov rdx, r12
        sub rdx, rbx
        call memchr@PLT
        test rax, rax
        jz 5f
        mov r13, rax                    # the newline
        mov rdi, [rsp + BF_BD]
        mov rsi, rbx
        mov rdx, r13
        call builder_line
        test eax, eax
        jnz .Lsb_json_error
        lea rbx, [r13 + 1]
        jmp 4b
5:      # the partial line moves to the front
        mov rdx, r12
        sub rdx, rbx
        mov [rsp + BF_BUFLEN], rdx
        mov rdi, [rsp + BF_BUF]
        mov rsi, rbx
        call memmove@PLT
        cmp qword ptr [rsp + BF_RC], LZMA_STREAM_END
        je 6f
        # a line longer than the buffer? grow it
        mov rax, [rsp + BF_BUFLEN]
        cmp rax, [rsp + BF_BUFCAP]
        jb .Lsb_decode
        mov rax, [rsp + BF_BUFCAP]
        shl rax, 1
        mov [rsp + BF_BUFCAP], rax
        mov rdi, [rsp + BF_BUF]
        mov rsi, rax
        call xrealloc
        mov [rsp + BF_BUF], rax
        jmp .Lsb_decode
6:      # the last line, without a newline
        cmp qword ptr [rsp + BF_BUFLEN], 0
        je 7f
        mov rdi, [rsp + BF_BD]
        mov rsi, [rsp + BF_BUF]
        mov rdx, rsi
        add rdx, [rsp + BF_BUFLEN]
        call builder_line
        test eax, eax
        jnz .Lsb_json_error
7:      lea rdi, [rsp + BF_LZ]
        call lzma_end@PLT
        mov rdi, [rsp + BF_IN]
        call free@PLT
        mov rdi, [rsp + BF_BUF]
        call free@PLT
        # the file
        mov rdi, [rsp + BF_BD]
        mov rax, [rsp + BF_OUTSB]
        mov rsi, [rax + SB_BUF]
        call builder_write
        test eax, eax
        jnz .Lsb_cant_write
        mov edi, LOG_INFO
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_built]
        mov rax, [rsp + BF_OUTSB]
        mov rcx, [rax + SB_BUF]
        mov rax, [rsp + BF_BD]
        mov r8, [rax + BD_NENTRIES]
        call log_fmt
        xor eax, eax
        add rsp, LZ_SIZEOF + 104
        LEAVE
.Lsb_cant_read:
        mov edi, LOG_ERROR
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_cant_read]
        mov rcx, [rsp + BF_XZ]
        call log_fmt
        jmp .Lsb_fail
.Lsb_cant_write:
        mov edi, LOG_ERROR
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_cant_write]
        mov rax, [rsp + BF_OUTSB]
        mov rcx, [rax + SB_BUF]
        call log_fmt
        jmp .Lsb_fail
.Lsb_lzma_error:
        mov r8d, eax
        mov edi, LOG_ERROR
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_lzma_error]
        mov rcx, [rsp + BF_XZ]
        call log_fmt
        jmp .Lsb_fail
.Lsb_json_error:
        mov edi, LOG_ERROR
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_json_error]
        mov rcx, [rsp + BF_XZ]
        mov rax, [rsp + BF_BD]
        mov r8, [rax + BD_LINES]
        call log_fmt
.Lsb_fail:
        mov eax, 1
        add rsp, LZ_SIZEOF + 104
        LEAVE
ENDF sigdb_build

# builder_new() -> rax
FUNC builder_new
        ENTER
        mov edi, 1
        mov esi, BD_SIZEOF
        call xcalloc
        mov rbx, rax
        mov edi, 1 << 20
        mov esi, 16
        call xcalloc
        mov [rbx + BD_ENTRIES], rax
        mov qword ptr [rbx + BD_CAPENTRIES], 1 << 20
        mov edi, 1 << 20
        mov esi, 8
        call xcalloc
        mov [rbx + BD_INPUTS], rax
        mov qword ptr [rbx + BD_CAPINPUTS], 1 << 20
        mov edi, 16 << 20
        call xmalloc
        mov [rbx + BD_STRINGS], rax
        mov qword ptr [rbx + BD_CAPSTRINGS], 16 << 20
        mov byte ptr [rax], 0           # offset 0: the empty string
        mov qword ptr [rbx + BD_NSTRINGS], 1
        mov edi, 1 << 21
        mov esi, 8
        call xcalloc
        mov [rbx + BD_TABLE], rax
        mov qword ptr [rbx + BD_TABLECAP], 1 << 21
        mov rax, rbx
        LEAVE
ENDF builder_new

# builder_string(bd, ptr, len) -> eax: the offset of the string in the
# blob, added if new
FUNC builder_string
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        test r13, r13
        jz .Lbs_empty
        mov rdi, r12
        mov rsi, r13
        call hash_bytes
        mov r14, rax
        # the table doubles when half full
        mov rax, [rbx + BD_TABLECOUNT]
        shl rax, 1
        cmp rax, [rbx + BD_TABLECAP]
        jb 1f
        mov rdi, rbx
        call builder_grow_table
1:      mov rcx, [rbx + BD_TABLECAP]
        dec rcx
        mov rax, r14
        and rax, rcx
        mov [rsp], rax                  # the slot
2:      mov rdx, [rbx + BD_TABLE]
        mov rax, [rsp]
        mov rdi, [rdx + rax*8]
        test rdi, rdi
        jz .Lbs_new
        dec rdi
        add rdi, [rbx + BD_STRINGS]     # the string at this slot
        push rdi
        push rdi
        call strlen@PLT
        pop rdi
        pop rdi
        cmp rax, r13
        jne 3f
        mov rsi, r12
        mov rdx, r13
        call memcmp@PLT
        test eax, eax
        jnz 3f
        mov rdx, [rbx + BD_TABLE]
        mov rax, [rsp]
        mov rax, [rdx + rax*8]
        dec rax
        add rsp, 16
        LEAVE
3:      mov rax, [rsp]
        inc rax
        mov rcx, [rbx + BD_TABLECAP]
        dec rcx
        and rax, rcx
        mov [rsp], rax
        jmp 2b
.Lbs_new:
        # appended to the blob (grown when needed)
        mov rax, [rbx + BD_NSTRINGS]
        lea rcx, [rax + r13 + 1]
        cmp rcx, [rbx + BD_CAPSTRINGS]
        jb 4f
        mov rax, [rbx + BD_CAPSTRINGS]
        shl rax, 1
        mov [rbx + BD_CAPSTRINGS], rax
        mov rdi, [rbx + BD_STRINGS]
        mov rsi, rax
        call xrealloc
        mov [rbx + BD_STRINGS], rax
4:      mov rdi, [rbx + BD_STRINGS]
        add rdi, [rbx + BD_NSTRINGS]
        mov rsi, r12
        mov rdx, r13
        call memcpy@PLT
        mov rax, [rbx + BD_NSTRINGS]
        mov rcx, [rbx + BD_STRINGS]
        add rcx, r13
        mov byte ptr [rcx + rax], 0
        mov r14, rax                    # the offset
        lea rcx, [rax + r13 + 1]
        mov [rbx + BD_NSTRINGS], rcx
        mov rdx, [rbx + BD_TABLE]
        mov rax, [rsp]
        lea rcx, [r14 + 1]
        mov [rdx + rax*8], rcx
        inc qword ptr [rbx + BD_TABLECOUNT]
        mov rax, r14
        add rsp, 16
        LEAVE
.Lbs_empty:
        xor eax, eax
        add rsp, 16
        LEAVE
ENDF builder_string

# builder_grow_table(bd): the dedup table doubled
FUNC builder_grow_table
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, [rbx + BD_TABLE]
        mov r13, [rbx + BD_TABLECAP]
        lea rdi, [r13 * 2]
        mov [rbx + BD_TABLECAP], rdi
        mov esi, 8
        call xcalloc
        mov [rbx + BD_TABLE], rax
        xor r14d, r14d
1:      cmp r14, r13
        jae 3f
        mov rax, [r12 + r14*8]
        test rax, rax
        jz 2f
        mov [rsp], rax
        dec rax
        add rax, [rbx + BD_STRINGS]
        mov rdi, rax
        mov [rsp + 8], rax
        call strlen@PLT
        mov rdi, [rsp + 8]
        mov rsi, rax
        call hash_bytes
        mov rcx, [rbx + BD_TABLECAP]
        dec rcx
        and rax, rcx
        mov rdx, [rbx + BD_TABLE]
4:      cmp qword ptr [rdx + rax*8], 0
        je 5f
        inc rax
        and rax, rcx
        jmp 4b
5:      mov rdi, [rsp]
        mov [rdx + rax*8], rdi
2:      inc r14
        jmp 1b
3:      mov rdi, r12
        call free@PLT
        add rsp, 16
        LEAVE
ENDF builder_grow_table

# builder_line(bd, start, end) -> eax: one JSON line parsed and added
# (0 on success; a repeated selector replaces the previous entry, as
# python's dict does)
FUNC builder_line
        ENTER
        sub rsp, 64
        .set BL_P, 0                    # the cursor
        .set BL_END, 8
        .set BL_SELECTOR, 16
        .set BL_NAME, 24                # an offset in the strings
        .set BL_INPUTS, 32              # the index of the first input
        .set BL_NINPUTS, 40
        .set BL_KEY, 48                 # an sb for the keys and strings
        mov rbx, rdi
        mov [rsp + BL_P], rsi
        mov [rsp + BL_END], rdx
        inc qword ptr [rbx + BD_LINES]
        mov qword ptr [rsp + BL_SELECTOR], -1
        mov qword ptr [rsp + BL_NAME], 0
        mov rax, [rbx + BD_NINPUTS]
        mov [rsp + BL_INPUTS], rax
        mov qword ptr [rsp + BL_NINPUTS], 0
        call sb_new
        mov [rsp + BL_KEY], rax
        # an empty line is nothing
        lea rdi, [rsp + BL_P]
        call js_ws
        mov rax, [rsp + BL_P]
        cmp rax, [rsp + BL_END]
        jae .Lbl_ok
        lea rdi, [rsp + BL_P]
        mov esi, '{'
        call js_expect
        test eax, eax
        jz .Lbl_bad
.Lbl_key:
        lea rdi, [rsp + BL_P]
        call js_ws
        mov rax, [rsp + BL_P]
        cmp byte ptr [rax], '}'
        je .Lbl_end
        lea rdi, [rsp + BL_P]
        mov rsi, [rsp + BL_KEY]
        call js_string
        test eax, eax
        jz .Lbl_bad
        lea rdi, [rsp + BL_P]
        mov esi, ':'
        call js_expect
        test eax, eax
        jz .Lbl_bad
        mov rax, [rsp + BL_KEY]
        mov rdi, [rax + SB_BUF]
        lea rsi, [rip + .Ls_selector]
        call strcmp@PLT
        test eax, eax
        jnz 1f
        lea rdi, [rsp + BL_P]
        mov rsi, [rsp + BL_KEY]
        call js_string
        test eax, eax
        jz .Lbl_bad
        mov rax, [rsp + BL_KEY]
        mov rdi, [rax + SB_BUF]
        call js_selector
        mov [rsp + BL_SELECTOR], rax
        jmp .Lbl_next
1:      mov rax, [rsp + BL_KEY]
        mov rdi, [rax + SB_BUF]
        lea rsi, [rip + .Ls_abi]
        call strcmp@PLT
        test eax, eax
        jnz 2f
        mov rdi, rbx
        mov rsi, rsp
        call bl_abi
        test eax, eax
        jz .Lbl_bad
        jmp .Lbl_next
2:      lea rdi, [rsp + BL_P]
        call js_skip
        test eax, eax
        jz .Lbl_bad
.Lbl_next:
        lea rdi, [rsp + BL_P]
        call js_ws
        mov rax, [rsp + BL_P]
        cmp byte ptr [rax], ','
        jne .Lbl_key
        inc qword ptr [rsp + BL_P]
        jmp .Lbl_key
.Lbl_end:
        cmp qword ptr [rsp + BL_SELECTOR], -1
        je .Lbl_bad
        # the entry (replacing the last one when it has the same selector)
        mov rax, [rbx + BD_NENTRIES]
        test rax, rax
        jz 3f
        dec rax
        shl rax, 4
        add rax, [rbx + BD_ENTRIES]
        mov ecx, [rax + SE_SELECTOR]
        cmp rcx, [rsp + BL_SELECTOR]
        jne 3f
        dec qword ptr [rbx + BD_NENTRIES]
3:      mov rax, [rbx + BD_NENTRIES]
        cmp rax, [rbx + BD_CAPENTRIES]
        jb 4f
        mov rax, [rbx + BD_CAPENTRIES]
        shl rax, 1
        mov [rbx + BD_CAPENTRIES], rax
        mov rdi, [rbx + BD_ENTRIES]
        mov rsi, rax
        shl rsi, 4
        call xrealloc
        mov [rbx + BD_ENTRIES], rax
        mov rax, [rbx + BD_NENTRIES]
4:      shl rax, 4
        add rax, [rbx + BD_ENTRIES]
        mov rcx, [rsp + BL_SELECTOR]
        mov [rax + SE_SELECTOR], ecx
        mov rcx, [rsp + BL_NAME]
        mov [rax + SE_NAME], ecx
        mov rcx, [rsp + BL_INPUTS]
        mov [rax + SE_INPUTS], ecx
        mov rcx, [rsp + BL_NINPUTS]
        mov [rax + SE_NINPUTS], ecx
        inc qword ptr [rbx + BD_NENTRIES]
.Lbl_ok:
        mov rdi, [rsp + BL_KEY]
        call sb_free
        xor eax, eax
        add rsp, 64
        LEAVE
.Lbl_bad:
        mov rdi, [rsp + BL_KEY]
        call sb_free
        mov eax, 1
        add rsp, 64
        LEAVE
ENDF builder_line

# bl_abi(bd, frame) -> eax: the "abi" object of a line - its "name" and
# "inputs" - over builder_line's locals (frame = its rsp)
FUNC bl_abi
        ENTER
        mov rbx, rdi
        mov r12, rsi
        lea rdi, [r12 + BL_P]
        mov esi, '{'
        call js_expect
        test eax, eax
        jz 9f
1:      lea rdi, [r12 + BL_P]
        call js_ws
        mov rax, [r12 + BL_P]
        cmp byte ptr [rax], '}'
        je 8f
        lea rdi, [r12 + BL_P]
        mov rsi, [r12 + BL_KEY]
        call js_string
        test eax, eax
        jz 9f
        lea rdi, [r12 + BL_P]
        mov esi, ':'
        call js_expect
        test eax, eax
        jz 9f
        mov rax, [r12 + BL_KEY]
        mov rdi, [rax + SB_BUF]
        lea rsi, [rip + .Ls_name]
        call strcmp@PLT
        test eax, eax
        jnz 2f
        lea rdi, [r12 + BL_P]
        mov rsi, [r12 + BL_KEY]
        call js_string
        test eax, eax
        jz 9f
        mov rax, [r12 + BL_KEY]
        mov rdi, rbx
        mov rsi, [rax + SB_BUF]
        mov rdx, [rax + SB_LEN]
        call builder_string
        mov [r12 + BL_NAME], rax
        jmp 4f
2:      mov rax, [r12 + BL_KEY]
        mov rdi, [rax + SB_BUF]
        lea rsi, [rip + .Ls_inputs]
        call strcmp@PLT
        test eax, eax
        jnz 3f
        mov rdi, rbx
        mov rsi, r12
        call bl_inputs
        test eax, eax
        jz 9f
        jmp 4f
3:      lea rdi, [r12 + BL_P]
        call js_skip
        test eax, eax
        jz 9f
4:      lea rdi, [r12 + BL_P]
        call js_ws
        mov rax, [r12 + BL_P]
        cmp byte ptr [rax], ','
        jne 1b
        inc qword ptr [r12 + BL_P]
        jmp 1b
8:      inc qword ptr [r12 + BL_P]
        mov eax, 1
        LEAVE
9:      xor eax, eax
        LEAVE
ENDF bl_abi

# bl_inputs(bd, frame) -> eax: the "inputs" array - the "name" and "type"
# of each, recorded
FUNC bl_inputs
        ENTER
        sub rsp, 16
        .set BI_TYPE, 0
        .set BI_NAME, 8
        mov rbx, rdi
        mov r12, rsi
        lea rdi, [r12 + BL_P]
        mov esi, '['
        call js_expect
        test eax, eax
        jz 9f
1:      lea rdi, [r12 + BL_P]
        call js_ws
        mov rax, [r12 + BL_P]
        cmp byte ptr [rax], ']'
        je 8f
        # one input
        mov qword ptr [rsp + BI_TYPE], 0
        mov qword ptr [rsp + BI_NAME], 0
        lea rdi, [r12 + BL_P]
        mov esi, '{'
        call js_expect
        test eax, eax
        jz 9f
2:      lea rdi, [r12 + BL_P]
        call js_ws
        mov rax, [r12 + BL_P]
        cmp byte ptr [rax], '}'
        je 6f
        lea rdi, [r12 + BL_P]
        mov rsi, [r12 + BL_KEY]
        call js_string
        test eax, eax
        jz 9f
        lea rdi, [r12 + BL_P]
        mov esi, ':'
        call js_expect
        test eax, eax
        jz 9f
        mov rax, [r12 + BL_KEY]
        mov rdi, [rax + SB_BUF]
        lea rsi, [rip + .Ls_name]
        call strcmp@PLT
        test eax, eax
        jnz 3f
        lea rdi, [r12 + BL_P]
        mov rsi, [r12 + BL_KEY]
        call js_string
        test eax, eax
        jz 9f
        mov rax, [r12 + BL_KEY]
        mov rdi, rbx
        mov rsi, [rax + SB_BUF]
        mov rdx, [rax + SB_LEN]
        call builder_string
        mov [rsp + BI_NAME], rax
        jmp 5f
3:      mov rax, [r12 + BL_KEY]
        mov rdi, [rax + SB_BUF]
        lea rsi, [rip + .Ls_type]
        call strcmp@PLT
        test eax, eax
        jnz 4f
        lea rdi, [r12 + BL_P]
        mov rsi, [r12 + BL_KEY]
        call js_string
        test eax, eax
        jz 9f
        mov rax, [r12 + BL_KEY]
        mov rdi, rbx
        mov rsi, [rax + SB_BUF]
        mov rdx, [rax + SB_LEN]
        call builder_string
        mov [rsp + BI_TYPE], rax
        jmp 5f
4:      lea rdi, [r12 + BL_P]
        call js_skip
        test eax, eax
        jz 9f
5:      lea rdi, [r12 + BL_P]
        call js_ws
        mov rax, [r12 + BL_P]
        cmp byte ptr [rax], ','
        jne 2b
        inc qword ptr [r12 + BL_P]
        jmp 2b
6:      inc qword ptr [r12 + BL_P]
        # the input recorded
        mov rax, [rbx + BD_NINPUTS]
        cmp rax, [rbx + BD_CAPINPUTS]
        jb 7f
        mov rax, [rbx + BD_CAPINPUTS]
        shl rax, 1
        mov [rbx + BD_CAPINPUTS], rax
        mov rdi, [rbx + BD_INPUTS]
        mov rsi, rax
        shl rsi, 3
        call xrealloc
        mov [rbx + BD_INPUTS], rax
        mov rax, [rbx + BD_NINPUTS]
7:      shl rax, 3
        add rax, [rbx + BD_INPUTS]
        mov rcx, [rsp + BI_TYPE]
        mov [rax + SI_TYPE], ecx
        mov rcx, [rsp + BI_NAME]
        mov [rax + SI_NAME], ecx
        inc qword ptr [rbx + BD_NINPUTS]
        inc qword ptr [r12 + BL_NINPUTS]
        lea rdi, [r12 + BL_P]
        call js_ws
        mov rax, [r12 + BL_P]
        cmp byte ptr [rax], ','
        jne 1b
        inc qword ptr [r12 + BL_P]
        jmp 1b
8:      inc qword ptr [r12 + BL_P]
        mov eax, 1
        add rsp, 16
        LEAVE
9:      xor eax, eax
        add rsp, 16
        LEAVE
ENDF bl_inputs

# js_selector(cstr) -> rax: the value of "0x12345678"
FUNC js_selector
        ENTER
        add rdi, 2
        xor esi, esi
        mov edx, 16
        call strtoul@PLT
        LEAVE
ENDF js_selector

# builder_write(bd, path) -> eax: the file written (0 on success)
FUNC builder_write
        ENTER
        sub rsp, 32
        mov rbx, rdi
        mov r12, rsi
        # the directory, if needed
        mov rdi, r12
        call make_parent_dirs
        # written to <path>.tmp, renamed when complete: a reader never sees
        # a file cut short
        call sb_new
        mov r14, rax
        mov rdi, rax
        mov rsi, r12
        call sb_append_c
        mov rdi, r14
        lea rsi, [rip + .Ls_tmp_suffix]
        call sb_append_c
        mov rdi, [r14 + SB_BUF]
        mov esi, 0x241                  # O_WRONLY | O_CREAT | O_TRUNC
        mov edx, 0644
        call open@PLT
        test eax, eax
        js .Lbw_fail
        mov r13d, eax
        # the header
        lea rax, [rip + .Ls_magic]
        mov rax, [rax]
        mov [rsp], rax
        mov rax, [rbx + BD_NENTRIES]
        mov [rsp + 8], eax
        mov rax, [rbx + BD_NSTRINGS]
        mov [rsp + 12], eax
        mov rax, [rbx + BD_NINPUTS]
        mov [rsp + 16], eax
        mov dword ptr [rsp + 20], 0
        mov edi, r13d
        mov rsi, rsp
        mov edx, SH_SIZEOF
        call write_all
        test eax, eax
        jnz .Lbw_write_fail
        mov edi, r13d
        mov rsi, [rbx + BD_ENTRIES]
        mov rdx, [rbx + BD_NENTRIES]
        shl rdx, 4
        call write_all
        test eax, eax
        jnz .Lbw_write_fail
        mov edi, r13d
        mov rsi, [rbx + BD_INPUTS]
        mov rdx, [rbx + BD_NINPUTS]
        shl rdx, 3
        call write_all
        test eax, eax
        jnz .Lbw_write_fail
        mov edi, r13d
        mov rsi, [rbx + BD_STRINGS]
        mov rdx, [rbx + BD_NSTRINGS]
        call write_all
        test eax, eax
        jnz .Lbw_write_fail
        mov edi, r13d
        call fsync@PLT
        mov edi, r13d
        call close@PLT
        test eax, eax
        jnz .Lbw_fail
        mov rdi, [r14 + SB_BUF]
        mov rsi, r12
        call rename@PLT
        test eax, eax
        jnz .Lbw_fail
        xor eax, eax
        add rsp, 32
        LEAVE
.Lbw_write_fail:
        mov edi, r13d
        call close@PLT
.Lbw_fail:
        mov eax, 1
        add rsp, 32
        LEAVE
ENDF builder_write

# make_parent_dirs(path): mkdir -p of the directories of a path
FUNC make_parent_dirs
        ENTER
        mov rbx, rdi
        call strlen@PLT
        lea rdi, [rax + 1]
        call xmalloc
        mov r12, rax
        mov rdi, rax
        mov rsi, rbx
        call strcpy@PLT
        lea r13, [r12 + 1]
1:      mov rdi, r13
        mov esi, '/'
        call strchr@PLT
        test rax, rax
        jz 2f
        mov r13, rax
        mov byte ptr [r13], 0
        mov rdi, r12
        mov esi, 0755
        call mkdir@PLT
        mov byte ptr [r13], '/'
        inc r13
        jmp 1b
2:      mov rdi, r12
        call free@PLT
        LEAVE
ENDF make_parent_dirs

# --- a JSON reader, over a cursor (a pointer to the pointer) ---

# js_ws(&p): the blanks skipped
FUNC js_ws
        mov rax, [rdi]
        lea rdx, [rip + .Lset_json_blank]
1:      movzx ecx, byte ptr [rax]
        cmp byte ptr [rdx + rcx], 0     # ' ', tab, newline, carriage return
        je 3f
        inc rax
        jmp 1b
3:      mov [rdi], rax
        ret
ENDF js_ws

        OPSET_MEMBER json_blank, ' '
        OPSET_MEMBER json_blank, 9
        OPSET_MEMBER json_blank, 10
        OPSET_MEMBER json_blank, 13
        OPSET_END json_blank, 255

# js_expect(&p, c) -> eax: the blanks, then the character c
FUNC js_expect
        ENTER
        mov rbx, rdi
        mov r12d, esi
        call js_ws
        mov rax, [rbx]
        movzx ecx, byte ptr [rax]
        cmp ecx, r12d
        jne 1f
        inc rax
        mov [rbx], rax
        mov eax, 1
        LEAVE
1:      xor eax, eax
        LEAVE
ENDF js_expect

# js_string(&p, sb) -> eax: a quoted string, decoded (its escapes
# resolved, \uXXXX to UTF-8) into the builder, emptied first
FUNC js_string
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov rdi, r12
        call sb_reset
        mov rdi, rbx
        call js_ws
        mov r13, [rbx]
        cmp byte ptr [r13], '"'
        jne .Ljs_bad
        inc r13
1:      movzx eax, byte ptr [r13]
        test eax, eax
        jz .Ljs_bad
        cmp eax, '"'
        je .Ljs_end
        cmp eax, '\\'
        je 2f
        mov rdi, r12
        mov esi, eax
        call sb_append_char
        inc r13
        jmp 1b
2:      movzx eax, byte ptr [r13 + 1]
        add r13, 2
        cmp eax, 'u'
        je 3f
        cmp eax, 'n'
        jne 21f
        mov eax, 10
        jmp 4f
21:     cmp eax, 't'
        jne 22f
        mov eax, 9
        jmp 4f
22:     cmp eax, 'r'
        jne 23f
        mov eax, 13
        jmp 4f
23:     cmp eax, 'b'
        jne 24f
        mov eax, 8
        jmp 4f
24:     cmp eax, 'f'
        jne 4f
        mov eax, 12
4:      mov rdi, r12
        mov esi, eax                    # (\" \\ \/ and the rest as they are)
        call sb_append_char
        jmp 1b
3:      # \uXXXX, with the surrogate pairs
        mov rdi, r13
        call .Ljs_hex4
        cmp rax, -1
        je .Ljs_bad
        add r13, 4
        mov r14, rax
        cmp r14, 0xd800
        jb 5f
        cmp r14, 0xdbff
        ja 5f
        cmp byte ptr [r13], '\\'
        jne 5f
        cmp byte ptr [r13 + 1], 'u'
        jne 5f
        lea rdi, [r13 + 2]
        call .Ljs_hex4
        cmp rax, 0xdc00
        jb 5f
        cmp rax, 0xdfff
        ja 5f
        add r13, 6
        sub r14, 0xd800
        shl r14, 10
        sub rax, 0xdc00
        add r14, rax
        add r14, 0x10000
5:      mov rdi, r12
        mov rsi, r14
        call sb_append_utf8
        jmp 1b
.Ljs_end:
        inc r13
        mov [rbx], r13
        mov eax, 1
        add rsp, 16
        LEAVE
.Ljs_bad:
        xor eax, eax
        add rsp, 16
        LEAVE
# four hex digits at rdi -> rax, or -1
.Ljs_hex4:
        xor eax, eax
        mov ecx, 4
1:      movzx edx, byte ptr [rdi]
        sub edx, '0'
        cmp edx, 9
        jbe 2f
        sub edx, 'a' - '0'
        cmp edx, 5
        jbe 3f
        sub edx, 'A' - 'a'
        cmp edx, 5
        ja 4f
3:      add edx, 10
2:      shl eax, 4
        or eax, edx
        inc rdi
        dec ecx
        jnz 1b
        ret
4:      mov rax, -1
        ret
ENDF js_string

# sb_append_utf8(sb, codepoint)
FUNC sb_append_utf8
        ENTER
        mov rbx, rdi
        mov r12, rsi
        cmp r12, 0x80
        jae 1f
        mov esi, r12d
        call sb_append_char
        LEAVE
1:      cmp r12, 0x800
        jae 2f
        mov esi, r12d
        shr esi, 6
        or esi, 0xc0
        call sb_append_char
        jmp 4f
2:      cmp r12, 0x10000
        jae 3f
        mov esi, r12d
        shr esi, 12
        or esi, 0xe0
        call sb_append_char
        jmp 5f
3:      mov esi, r12d
        shr esi, 18
        or esi, 0xf0
        call sb_append_char
        mov rdi, rbx
        mov esi, r12d
        shr esi, 12
        and esi, 0x3f
        or esi, 0x80
        call sb_append_char
5:      mov rdi, rbx
        mov esi, r12d
        shr esi, 6
        and esi, 0x3f
        or esi, 0x80
        call sb_append_char
4:      mov rdi, rbx
        mov esi, r12d
        and esi, 0x3f
        or esi, 0x80
        call sb_append_char
        LEAVE
ENDF sb_append_utf8

# js_skip(&p) -> eax: any value skipped
FUNC js_skip
        STACK_CHECK
        ENTER
        sub rsp, 16
        mov rbx, rdi
        call js_ws
        mov rax, [rbx]
        movzx ecx, byte ptr [rax]
        cmp ecx, '"'
        jne 1f
        call sb_new
        mov r12, rax
        mov rdi, rbx
        mov rsi, rax
        call js_string
        mov r13d, eax
        mov rdi, r12
        call sb_free
        mov eax, r13d
        jmp .Ljk_ret
1:      cmp ecx, '{'
        je 2f
        cmp ecx, '['
        jne 5f
2:      # an object or an array: its elements skipped
        mov r12d, ecx
        inc rax
        mov [rbx], rax
3:      mov rdi, rbx
        call js_ws
        mov rax, [rbx]
        movzx ecx, byte ptr [rax]
        cmp ecx, '}'
        je 4f
        cmp ecx, ']'
        je 4f
        test ecx, ecx
        jz .Ljk_bad
        cmp ecx, ','
        jne 31f
        inc rax
        mov [rbx], rax
        jmp 3b
31:     cmp ecx, ':'
        jne 32f
        inc rax
        mov [rbx], rax
        jmp 3b
32:     mov rdi, rbx
        call js_skip
        test eax, eax
        jz .Ljk_bad
        jmp 3b
4:      inc rax
        mov [rbx], rax
        mov eax, 1
        jmp .Ljk_ret
5:      # a number or a literal: up to a delimiter
6:      movzx ecx, byte ptr [rax]
        test ecx, ecx
        jz 7f
        cmp ecx, ','
        je 7f
        cmp ecx, '}'
        je 7f
        cmp ecx, ']'
        je 7f
        cmp ecx, ' '
        je 7f
        inc rax
        jmp 6b
7:      cmp rax, [rbx]
        je .Ljk_bad
        mov [rbx], rax
        mov eax, 1
.Ljk_ret:
        add rsp, 16
        LEAVE
.Ljk_bad:
        xor eax, eax
        add rsp, 16
        LEAVE
ENDF js_skip

        .section .note.GNU-stack,"",@progbits
