# The storage of a contract (port of storage.py): what its variables are,
# from every access of the functions - ('storage', size, off, slot) read,
# ('store', size, off, slot, value) written - each at a path from a
# variable of the contract (parse, steps); their types (typeof), their
# names (from the getters); each access then printed as its path
# (name[key], name[i].field_N, name.length: form) when that reads, on
# random values of what the slot is computed from, as the slot and the
# bits it is (the check, storage_check.s), else raw (stor[slot]).
#
# The printed forms (see prettify's pretty_st):
#     ('st', size, loc, width)
#     loc: ('sv', name) ('si', base, key) ('sl', base) ('sbl', base)
#          ('sf', base, n) ('sr', slot)
#
# The paths: ('var', n) ('map', p, key, kind) ('data', p) ('off', p, e)
# ('blen', p) ('raw', idx); the steps from a root slot: a list of
# ('map', key, kind) ('data',) ('off', e) ('blen',); the types: ('value',
# width) ('struct', slots or None) ('mapping', t) ('array', t, stride)
# ('fixed', t, stride) ('bytes',).
#
# Python's exceptions: a Fail (an access that can't be printed as its
# path) is NIL from the functions that make the forms; storage's Unknown
# (the check) is E_UNKNOWN, a ZeroDivisionError E_ZERO_DIV; the others are
# the runtime's (E_TYPE, E_INDEX...). The language is a flag: 1 for
# vyper, 0 for solidity.

.include "defs.inc"
.include "storage.inc"

.set E_STFAIL, 40               # a Fail that python lets through (raw's)
.set E_UNKNOWN, 41              # storage's Unknown (the check)
.set E_ZERO_DIV, 42             # python's ZeroDivisionError

# the hashes a compiler writes as numbers (hash_table): keccak(n) for the
# DATA_SLOTS first slots, keccak(key . n) of the MAP_KEYS first keys of the
# MAP_SLOTS first slots - per language, sorted
.set DATA_SLOTS, 4096
.set MAP_KEYS, 16
.set MAP_SLOTS, 64
.set HT_COUNT, DATA_SLOTS + MAP_KEYS * MAP_SLOTS
.set HT_HASH, 0                 # 32 bytes, big-endian (memcmp: the order of the numbers)
.set HT_N, 32                   # u32: the slot
.set HT_K, 36                   # u32: the key, -1 for keccak(n)
.set HT_ENTRY, 40
.set HT_SIZE, HT_COUNT * HT_ENTRY
.set MAX_DELTA, 65536           # what's added to a hash to reach a member

        # (made at build time: tools/gen_htab.c, with keccak.s - every
        # process made them at its first storage constant, 10240 hashes)
        .section .rodata
        .p2align 6
st_htabs:       .incbin "build/storage_htab.bin"
        .if . - st_htabs - 2 * HT_SIZE
        .error "build/storage_htab.bin: not the two tables of HT_COUNT entries"
        .endif

        .section .rodata
.Ls_index:      .asciz "list index out of range"
.Ls_tindex:     .asciz "tuple index out of range"
.Ls_zero_div:   .asciz "integer division or modulo by zero"
.Ls_max_empty:  .asciz "max() arg is an empty sequence"
.Ls_steps_kind: .asciz "steps: a path of an unknown kind"
.Ls_raw_fail:   .asciz "storage: a write of the length of a bytes (raw's Fail)"
.Ls_cmp_type:   .asciz "'<' not supported between instances"
        .text

# ---------------------------------------------------------------------
# the hash table

# st_htab(lang) -> rax: the table of the language (hash_table: python's
# lru_cache - here, made at build time, read only)
FUNC st_htab
        and edi, 1
        imul rax, rdi, HT_SIZE
        lea rcx, [rip + st_htabs]
        add rax, rcx
        ret
ENDF st_htab

# st_be32(dst, v): (v % 2**256).to_bytes(32, "big") of an int v
FUNC st_be32
        ENTER
        sub rsp, 32
        mov rbx, rdi
        mov rdi, rsp
        call w_from_value
        .irp i, 0, 1, 2, 3
        mov rax, [rsp + 8*\i]
        bswap rax
        mov [rbx + 24 - 8*\i], rax
        .endr
        add rsp, 32
        LEAVE
ENDF st_be32

# st_hash_constant(c, lang) -> rax: python's hash_constant - (path, delta)
# when the number c (mod 2^256) is delta < MAX_DELTA after a hash of the
# table, else 0 (None)
FUNC st_hash_constant
        ENTER
        sub rsp, 96
        .set HC_BE, 0                   # c, big-endian
        .set HC_W, 32                   # c - the hash, little-endian limbs
        .set HC_H, 64
        mov rbx, rdi
        mov r12d, esi
        lea rdi, [rsp + HC_BE]
        mov rsi, rbx
        call st_be32
        mov edi, r12d
        call st_htab
        mov r13, rax
        xor r12d, r12d                  # lo
        mov r14d, HT_COUNT              # hi: bisect_right of (c, ("~",))
1:      cmp r12d, r14d
        jae 3f
        lea ebx, [r12d + r14d]
        shr ebx, 1
        imul rdi, rbx, HT_ENTRY
        add rdi, r13
        lea rsi, [rsp + HC_BE]
        mov edx, 32
        call memcmp@PLT
        test eax, eax
        jg 2f
        lea r12d, [ebx + 1]             # table[mid] <= c: lo = mid + 1
        jmp 1b
2:      mov r14d, ebx
        jmp 1b
3:      test r12d, r12d
        jz .Lhc_none
        dec r12d
        imul rbx, r12, HT_ENTRY
        add rbx, r13                    # the entry
        # c - its hash (c >= it): below MAX_DELTA?
        .irp i, 0, 1, 2, 3
        mov rax, [rsp + HC_BE + 24 - 8*\i]
        bswap rax
        mov [rsp + HC_W + 8*\i], rax
        mov rax, [rbx + HT_HASH + 24 - 8*\i]
        bswap rax
        mov [rsp + HC_H + 8*\i], rax
        .endr
        mov rax, [rsp + HC_W]
        sub rax, [rsp + HC_H]
        mov rcx, [rsp + HC_W + 8]
        sbb rcx, [rsp + HC_H + 8]
        mov rdx, [rsp + HC_W + 16]
        sbb rdx, [rsp + HC_H + 16]
        mov r8, [rsp + HC_W + 24]
        sbb r8, [rsp + HC_H + 24]
        or rcx, rdx
        or rcx, r8
        jnz .Lhc_none
        cmp rax, MAX_DELTA
        jae .Lhc_none
        TAG rax
        mov [rsp + HC_W], rax           # delta
        mov edi, [rbx + HT_N]
        TAG rdi
        mov rsi, rdi
        LOADS rdi, VAR
        call mk2                        # ('var', n)
        mov r12, rax
        cmp dword ptr [rbx + HT_K], -1
        jne 4f
        mov rsi, r12
        LOADS rdi, DATA
        call mk2                        # ('data', ('var', n))
        jmp 5f
4:      mov edx, [rbx + HT_K]
        TAG rdx
        mov rsi, r12
        LOADS rdi, MAP
        LOADS rcx, WORD
        call mk4                        # ('map', ('var', n), k, 'word')
5:      mov rdi, rax
        mov rsi, [rsp + HC_W]
        call mk2
        add rsp, 96
        LEAVE
.Lhc_none:
        xor eax, eax
        add rsp, 96
        LEAVE
ENDF st_hash_constant

# ---------------------------------------------------------------------
# parsing the slots

# st_throw_index(): python's IndexError
FUNC st_throw_index
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_index]
        jmp err_throw
ENDF st_throw_index

# st_word(e) -> value: python's word - a word of a data, as its value
FUNC st_word
        ENTER
        mov rbx, rdi
        OP_N_CHECK OP_BYTES, 3, 1f      # ('bytes', 32, v), v not sized
        cmp qword ptr [rbx + N_DATA + 8], (32 << 1) | 1
        jne 1f
        mov rdi, [rbx + N_DATA + 16]
        call sized
        test eax, eax
        jnz 1f
        mov rax, [rbx + N_DATA + 16]
        LEAVE
1:      mov rax, rbx
        LEAVE
ENDF st_word

# st_is_word(e) -> eax: python's is_word - e, as an element of a data, is
# a word (an IndexError for a ('bytes',) too short, as python's)
FUNC st_is_word
        ENTER
        mov rbx, rdi
        call opcode_of
        cmp eax, OP_BYTES
        jne 2f
        cmp dword ptr [rbx + N_AUX], 2
        jb .Liw_index
        cmp qword ptr [rbx + N_DATA + 8], (32 << 1) | 1
        jne 8f
        cmp dword ptr [rbx + N_AUX], 3
        jb .Liw_index
        mov rdi, [rbx + N_DATA + 16]
        call sized
        xor eax, 1
        LEAVE
2:      mov rdi, rbx
        call sized
        test eax, eax
        jnz 8f
        mov rdi, rbx
        call sizeof_nil                 # (NIL: python's AssertionError)
        cmp rax, (256 << 1) | 1
        jne 8f
        mov eax, 1
        LEAVE
8:      xor eax, eax
        LEAVE
.Liw_index:
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_tindex]
        call err_throw
ENDF st_is_word

# st_from_calldata(e) -> eax: python's from_calldata - e is a param, or
# masks and shifts of one
FUNC st_from_calldata
        STACK_CHECK
        ENTER
        mov rbx, rdi
1:      mov rdi, rbx
        call opcode_of
        cmp eax, OP_CD
        je 8f
        cmp eax, OP_PARAM
        je 8f
        cmp eax, OP_MASK_SHL
        jne 9f
        cmp dword ptr [rbx + N_AUX], 5
        jb .Lfc_index
        mov rbx, [rbx + N_DATA + 32]
        jmp 1b
8:      mov eax, 1
        LEAVE
9:      xor eax, eax
        LEAVE
.Lfc_index:
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_tindex]
        call err_throw
ENDF st_from_calldata

# st_mk_raw(idx) -> ('raw', idx)
FUNC st_mk_raw
        mov rsi, rdi
        LOADS rdi, RAW
        jmp mk2
ENDF st_mk_raw

# st_is_raw(path) -> eax: path[0] == 'raw'
FUNC st_is_raw
        call opcode_of
        cmp eax, OP_RAW
        sete al
        movzx eax, al
        ret
ENDF st_is_raw

# st_parse(idx, lang) -> path: python's parse
FUNC st_parse
        STACK_CHECK
        ENTER
        sub rsp, 80
        .set PA_LANG, 0
        .set PA_PARTS, 8                # the parts of a sha3: a pointer
        .set PA_N, 16                   # and their count
        .set PA_SLOT, 24
        .set PA_KEY, 32                 # the key: a pointer, a count
        .set PA_NKEY, 40
        .set PA_TERMS, 48               # an add's terms (a vec)
        .set PA_TMP, 56
        mov [rsp + PA_LANG], rsi
        call st_word
        mov rbx, rax
        mov rdi, rax
        call is_int
        test eax, eax
        jz .Lpa_loc
        mov rdi, rbx                    # a number: a hash of the table,
        mov esi, 256                    # or the slot itself
        call int_mod_2exp
        mov rbx, rax
        mov rdi, rax
        mov rsi, [rsp + PA_LANG]
        call st_hash_constant
        test rax, rax
        jz 1f
        mov rsi, [rax + N_DATA]         # path
        mov rdx, [rax + N_DATA + 8]     # delta
        cmp rdx, 1
        je 2f
        LOADS rdi, OFF
        call mk3                        # ('off', path, delta)
        jmp .Lpa_ret
2:      mov rax, rsi
        jmp .Lpa_ret
1:      mov rsi, rbx
        LOADS rdi, VAR
        call mk2
        jmp .Lpa_ret
.Lpa_loc:
        mov rdi, rbx                    # ('loc', int n): the slot n
        OP_N_CHECK OP_LOC, 2, .Lpa_length
        mov rdi, [rbx + N_DATA + 8]
        call is_int
        test eax, eax
        jz .Lpa_length
        mov rsi, [rbx + N_DATA + 8]
        LOADS rdi, VAR
        call mk2
        jmp .Lpa_ret
.Lpa_length:
        mov rdi, rbx                    # ('length', key): the length of the
        OP_N_CHECK OP_LENGTH, 2, .Lpa_op       # bytes at the slot key
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, [rsp + PA_LANG]
        call st_parse
        mov r12, rax
        mov rdi, rax
        call st_is_raw
        test eax, eax
        jnz .Lpa_raw
        mov rsi, r12
        LOADS rdi, BLEN
        call mk2
        jmp .Lpa_ret
.Lpa_op:
        mov rdi, rbx
        call opcode_of
        cmp eax, OP_SHA3
        je .Lpa_sha3
        cmp eax, OP_ADD
        je .Lpa_add
        mov rdi, rbx
        call st_from_calldata
        test eax, eax
        jz .Lpa_raw
        # a slot computed from a param: the element of an array at 0 (as
        # vyper puts them)
        LOADS rdi, VAR
        mov esi, 1
        call mk2
        mov rsi, rax
        mov rdx, rbx
        LOADS rdi, OFF
        call mk3
        jmp .Lpa_ret
.Lpa_raw:
        mov rdi, rbx
        call st_mk_raw
.Lpa_ret:
        add rsp, 80
        LEAVE

.Lpa_sha3:
        # the parts: of the data it hashes, or its own
        lea rax, [rbx + N_DATA + 8]
        mov ecx, [rbx + N_AUX]
        dec ecx
        cmp dword ptr [rbx + N_AUX], 2
        jne 1f
        mov rdi, [rbx + N_DATA + 8]
        call opcode_of
        cmp eax, OP_DATA
        jne 2f
        mov rdx, [rbx + N_DATA + 8]
        lea rax, [rdx + N_DATA + 8]
        mov ecx, [rdx + N_AUX]
        dec ecx
        jmp 1f
2:      lea rax, [rbx + N_DATA + 8]
        mov ecx, 1
1:      mov [rsp + PA_PARTS], rax
        mov [rsp + PA_N], rcx
        test rcx, rcx
        jz .Lpa_raw
        cmp rcx, 1
        jne 3f
        mov rdi, [rax]
        call st_is_word
        test eax, eax
        jz 3f
        # keccak(slot): the data of an array (or a bytes)
        mov rax, [rsp + PA_PARTS]
        mov rdi, [rax]
        mov rsi, [rsp + PA_LANG]
        call st_parse
        mov r12, rax
        mov rdi, rax
        call st_is_raw
        test eax, eax
        jnz .Lpa_raw
        mov rsi, r12
        LOADS rdi, DATA
        call mk2
        jmp .Lpa_ret
3:      # keccak(key . slot) - vyper: slot . key
        mov rax, [rsp + PA_PARTS]
        mov rcx, [rsp + PA_N]
        cmp qword ptr [rsp + PA_LANG], 0
        je 4f
        mov rdx, [rax]                  # slot = parts[0], key = parts[1:]
        mov [rsp + PA_SLOT], rdx
        add rax, 8
        mov [rsp + PA_KEY], rax
        dec rcx
        mov [rsp + PA_NKEY], rcx
        jmp 5f
4:      mov rdx, [rax + rcx*8 - 8]      # slot = parts[-1], key = parts[:-1]
        mov [rsp + PA_SLOT], rdx
        mov [rsp + PA_KEY], rax
        dec rcx
        mov [rsp + PA_NKEY], rcx
5:      mov rdi, [rsp + PA_SLOT]
        call st_is_word
        test eax, eax
        jz .Lpa_raw
        mov rdi, [rsp + PA_SLOT]
        mov rsi, [rsp + PA_LANG]
        call st_parse
        mov r12, rax
        mov rdi, rax
        call st_is_raw
        test eax, eax
        jnz .Lpa_raw
        cmp qword ptr [rsp + PA_NKEY], 1
        jne 6f
        mov rax, [rsp + PA_KEY]
        mov rdi, [rax]
        call st_is_word
        test eax, eax
        jz 6f
        mov rax, [rsp + PA_KEY]         # ('map', inner, word(key), 'word')
        mov rdi, [rax]
        call st_word
        mov rdx, rax
        mov rsi, r12
        LOADS rdi, MAP
        LOADS rcx, WORD
        call mk4
        jmp .Lpa_ret
6:      # ('map', inner, ('data',) + key, 'bytes')
        call vec_new
        mov r13, rax
        mov rdi, rax
        LOADS rsi, DATA
        call vec_push
        mov rdi, r13
        mov rsi, [rsp + PA_KEY]
        mov rdx, [rsp + PA_NKEY]
        call vec_extend
        mov rdi, r13
        call vec_to_tuple
        mov rdx, rax
        mov rsi, r12
        LOADS rdi, MAP
        LOADS rcx, BYTES
        call mk4
        jmp .Lpa_ret

.Lpa_add:
        # the terms, a sum of sums one
        call vec_new
        mov [rsp + PA_TERMS], rax
        mov r12d, 1
1:      cmp r12d, [rbx + N_AUX]
        jae 3f
        mov r13, [rbx + N_DATA + r12*8]
        inc r12d
        mov rdi, r13
        call opcode_of
        cmp eax, OP_ADD
        je 2f
        mov rdi, [rsp + PA_TERMS]
        mov rsi, r13
        call vec_push
        jmp 1b
2:      mov rdi, [rsp + PA_TERMS]
        lea rsi, [r13 + N_DATA + 8]
        mov edx, [r13 + N_AUX]
        dec edx
        call vec_extend
        jmp 1b
3:      # the base: a hash, or a number that is one
        mov qword ptr [rsp + PA_N], 0           # how many
        mov qword ptr [rsp + PA_SLOT], -1       # the first one's index
        xor r12d, r12d
4:      mov rax, [rsp + PA_TERMS]
        cmp r12, [rax + VEC_LEN]
        jae 7f
        mov rax, [rax + VEC_DATA]
        mov r13, [rax + r12*8]
        mov rdi, r13
        call opcode_of
        cmp eax, OP_SHA3
        je 5f
        mov rdi, r13
        call is_int
        test eax, eax
        jz 6f
        mov rdi, r13
        mov rsi, [rsp + PA_LANG]
        call st_hash_constant
        test rax, rax
        jz 6f
5:      inc qword ptr [rsp + PA_N]
        mov [rsp + PA_SLOT], r12
6:      inc r12
        jmp 4b
7:      cmp qword ptr [rsp + PA_N], 1
        jne .Lpa_nobase
        mov rdi, [rsp + PA_TERMS]       # base = terms.pop(bases[0])
        mov rsi, [rsp + PA_SLOT]
        call st_vec_pop_at
        mov r13, rax
        mov rdi, rax
        call is_int
        test eax, eax
        jz 8f
        mov rdi, r13
        mov rsi, [rsp + PA_LANG]
        call st_hash_constant
        mov r12, [rax + N_DATA]         # path
        mov rsi, [rax + N_DATA + 8]
        cmp rsi, 1                      # delta: a term of the offset
        je 9f
        mov rdi, [rsp + PA_TERMS]
        call vec_push
        jmp 9f
8:      mov rdi, r13
        mov rsi, [rsp + PA_LANG]
        call st_parse
        mov r12, rax
        mov rdi, rax
        call st_is_raw
        test eax, eax
        jnz .Lpa_raw
9:      mov rdi, [rsp + PA_TERMS]
        call st_add_terms
        mov rdx, rax
        mov rsi, r12
        LOADS rdi, OFF
        call mk3
        jmp .Lpa_ret
.Lpa_nobase:
        cmp qword ptr [rsp + PA_N], 0
        jne .Lpa_raw
        # a number: the slot, the rest the offset from it
        mov qword ptr [rsp + PA_N], 0
        xor r12d, r12d
1:      mov rax, [rsp + PA_TERMS]
        cmp r12, [rax + VEC_LEN]
        jae 2f
        mov rax, [rax + VEC_DATA]
        mov rdi, [rax + r12*8]
        call is_int
        test eax, eax
        jz 3f
        inc qword ptr [rsp + PA_N]
        mov [rsp + PA_SLOT], r12
3:      inc r12
        jmp 1b
2:      cmp qword ptr [rsp + PA_N], 1
        jne .Lpa_raw
        mov rdi, [rsp + PA_TERMS]
        mov rsi, [rsp + PA_SLOT]
        call st_vec_pop_at
        mov rdi, rax
        mov esi, 256
        call int_mod_2exp
        mov rsi, rax
        LOADS rdi, VAR
        call mk2
        mov r12, rax
        mov rdi, [rsp + PA_TERMS]
        call st_add_terms
        mov rdx, rax
        mov rsi, r12
        LOADS rdi, OFF
        call mk3
        jmp .Lpa_ret
ENDF st_parse

# st_vec_pop_at(vec, i) -> rax: vec.pop(i)
FUNC st_vec_pop_at
        mov rcx, [rdi + VEC_DATA]
        mov rax, [rcx + rsi*8]
        mov rdx, [rdi + VEC_LEN]
        dec rdx
        mov [rdi + VEC_LEN], rdx
1:      cmp rsi, rdx
        jae 2f
        mov r8, [rcx + rsi*8 + 8]
        mov [rcx + rsi*8], r8
        inc rsi
        jmp 1b
2:      ret
ENDF st_vec_pop_at

# st_add_terms(vec) -> value: add_op(*terms) if len(terms) > 1 else
# terms[0] (an IndexError for none)
FUNC st_add_terms
        mov rsi, [rdi + VEC_DATA]
        mov rdi, [rdi + VEC_LEN]
        cmp rdi, 1
        ja alg_add_n
        jb st_throw_index
        mov rax, [rsi]
        ret
ENDF st_add_terms

# st_list_plus(list, x) -> list: list + [x]
FUNC st_list_plus
        ENTER
        mov rbx, rdi
        mov rdi, rsi
        call mk_list1
        mov rdi, rbx
        mov rsi, rax
        call list_concat
        LEAVE
ENDF st_list_plus

# st_steps(path) -> rax: python's steps - (root slot, [steps]) of a path, 0
# (None) if it's raw
FUNC st_steps
        STACK_CHECK
        ENTER
        sub rsp, 16
        mov rbx, rdi
        call opcode_of
        cmp eax, OP_VAR
        je .Lsp_var
        cmp eax, OP_RAW
        je .Lsp_none
        mov r14d, eax
        cmp eax, OP_MAP
        je 1f
        cmp eax, OP_DATA
        je 1f
        cmp eax, OP_BLEN
        je 1f
        cmp eax, OP_OFF
        je 1f
        mov edi, E_VALUE
        lea rsi, [rip + .Ls_steps_kind]
        call err_throw
1:      mov rdi, [rbx + N_DATA + 8]
        call st_steps
        test rax, rax
        jz .Lsp_none
        mov r12, [rax + N_DATA]         # root
        mov r13, [rax + N_DATA + 8]     # st
        cmp r14d, OP_MAP
        jne 2f
        LOADS rdi, MAP                  # ('map', key, kind)
        mov rsi, [rbx + N_DATA + 16]
        mov rdx, [rbx + N_DATA + 24]
        call mk3
        jmp .Lsp_append
2:      cmp r14d, OP_DATA
        jne 3f
        LOADS rdi, DATA
        call mk1
        jmp .Lsp_append
3:      cmp r14d, OP_BLEN
        jne 4f
        LOADS rdi, BLEN
        call mk1
        jmp .Lsp_append
4:      mov r14, [rbx + N_DATA + 16]    # off: e
        cmp dword ptr [r13 + N_AUX], 0
        jne 5f
        mov rdi, r14
        call is_int
        test eax, eax
        jz 6f
        # a slot after the root is another variable
        mov rdi, r12
        mov rsi, r14
        call int_add
        mov rdi, rax
        mov esi, 256
        call int_mod_2exp
        mov rdi, rax
        mov rsi, r13
        call mk2
        jmp .Lsp_ret
5:      mov ecx, [r13 + N_AUX]          # offsets one after the other are one
        mov rax, [r13 + N_DATA + rcx*8 - 8]
        mov [rsp], rax
        mov rdi, rax
        call opcode_of
        cmp eax, OP_OFF
        jne 6f
        mov rax, [rsp]
        mov rdi, [rax + N_DATA + 8]
        mov rsi, r14
        call alg_add2
        mov rsi, rax
        LOADS rdi, OFF
        call mk2
        mov [rsp], rax
        mov rdi, r13                    # st[:-1]
        mov esi, [r13 + N_AUX]
        dec esi
        call st_list_head
        mov rdi, rax
        mov rsi, [rsp]
        call st_list_plus
        mov rsi, rax
        mov rdi, r12
        call mk2
        jmp .Lsp_ret
6:      LOADS rdi, OFF
        mov rsi, r14
        call mk2
.Lsp_append:
        mov rdi, r13
        mov rsi, rax
        call st_list_plus
        mov rsi, rax
        mov rdi, r12
        call mk2
        jmp .Lsp_ret
.Lsp_var:
        xor edi, edi
        xor esi, esi
        call mk_list
        mov rsi, rax
        mov rdi, [rbx + N_DATA + 8]
        call mk2
        jmp .Lsp_ret
.Lsp_none:
        xor eax, eax
.Lsp_ret:
        add rsp, 16
        LEAVE
ENDF st_steps

# st_list_head(seq, n) -> list: seq[:n]
FUNC st_list_head
        mov eax, esi
        lea rsi, [rdi + N_DATA]
        mov edi, eax
        jmp mk_list
ENDF st_list_head

# ---------------------------------------------------------------------
# elements: the index and the member an offset from the start of an
# array is

# st_log2(n) -> rax: python's log2 - k (tagged) when the int n is 2^k > 0,
# else 0 (None)
FUNC st_log2
        xor eax, eax
        test dil, 1
        jz 1f                           # (a big one: never asked, see packed)
        mov rcx, rdi
        sar rcx, 1
        jle 1f
        lea rdx, [rcx - 1]
        test rcx, rdx
        jnz 1f
        bsr rax, rcx
        TAG rax
1:      ret
ENDF st_log2

# st_linear(e, out): python's linear - out[0..2] = (index, stride,
# constant) with e == stride * index + constant
FUNC st_linear
        STACK_CHECK
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 32
        .set LI_OUT, MATCH_BINDINGS_SIZE
        .set LI_C, MATCH_BINDINGS_SIZE + 8
        .set LI_REST, MATCH_BINDINGS_SIZE + 16
        mov rbx, rdi
        mov [rsp + LI_OUT], rsi
        call is_int
        test eax, eax
        jz 1f
        mov rcx, [rsp + LI_OUT]         # a number: (0, 0, e)
        mov qword ptr [rcx], 1
        mov qword ptr [rcx + 8], 1
        mov [rcx + 16], rbx
        jmp .Lli_ret
1:      mov rdi, rbx
        call opcode_of
        cmp eax, OP_ADD
        jne .Lli_mul
        # the numbers summed, the rest
        mov qword ptr [rsp + LI_C], 1
        call vec_new
        mov [rsp + LI_REST], rax
        mov r12d, 1
2:      cmp r12d, [rbx + N_AUX]
        jae 4f
        mov r13, [rbx + N_DATA + r12*8]
        inc r12d
        mov rdi, r13
        call is_int
        test eax, eax
        jz 3f
        mov rdi, [rsp + LI_C]
        mov rsi, r13
        call int_add
        mov [rsp + LI_C], rax
        jmp 2b
3:      mov rdi, [rsp + LI_REST]
        mov rsi, r13
        call vec_push
        jmp 2b
4:      mov rax, [rsp + LI_REST]
        cmp qword ptr [rax + VEC_LEN], 1
        jne 5f
        mov rcx, [rax + VEC_DATA]       # one: its linear form, plus c
        mov rdi, [rcx]
        mov rsi, [rsp + LI_OUT]
        call st_linear
        mov rcx, [rsp + LI_OUT]
        mov rdi, [rsp + LI_C]
        mov rsi, [rcx + 16]
        call int_add
        mov rcx, [rsp + LI_OUT]
        mov [rcx + 16], rax
        jmp .Lli_ret
5:      mov rdi, [rax + VEC_LEN]        # (add_op(*rest), 1, c)
        mov rsi, [rax + VEC_DATA]
        call alg_add_n
        mov rcx, [rsp + LI_OUT]
        mov [rcx], rax
        mov qword ptr [rcx + 8], 3
        mov rax, [rsp + LI_C]
        mov [rcx + 16], rax
        jmp .Lli_ret
.Lli_mul:
        PAT rsi, "('mul', ':int:s', ':i')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz .Lli_mask
        mov rdi, [rsp]
        call int_sign
        cmp eax, 1
        jne .Lli_mask
        mov rcx, [rsp + LI_OUT]         # (i, s, 0)
        mov rax, [rsp + 8]
        mov [rcx], rax
        mov rax, [rsp]
        mov [rcx + 8], rax
        mov qword ptr [rcx + 16], 1
        jmp .Lli_ret
.Lli_mask:
        PAT rsi, "('mask_shl', ':int:size', 0, ':int:shl', ':i')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz .Lli_plain
        # i << shl, the bits shifted out lost: 2**shl * i
        mov rdi, [rsp]
        mov rsi, [rsp + 8]
        call int_add
        cmp rax, (256 << 1) | 1
        jne .Lli_plain
        mov rax, [rsp + 8]
        cmp rax, 1
        jle .Lli_plain                  # (0 or less, or a big int: not in 1..255)
        test al, 1
        jz .Lli_plain
        cmp rax, (256 << 1) | 1
        jge .Lli_plain
        sar rax, 1
        mov rdi, rax
        call pow2
        mov rcx, [rsp + LI_OUT]
        mov [rcx + 8], rax
        mov rax, [rsp + 16]
        mov [rcx], rax
        mov qword ptr [rcx + 16], 1
        jmp .Lli_ret
.Lli_plain:
        mov rcx, [rsp + LI_OUT]         # (e, 1, 0)
        mov [rcx], rbx
        mov qword ptr [rcx + 8], 3
        mov qword ptr [rcx + 16], 1
.Lli_ret:
        add rsp, MATCH_BINDINGS_SIZE + 32
        LEAVE
ENDF st_linear

# st_packed(e, off, width) -> rax: python's packed - the index of the
# element of `width` bits at slot + e, bits off, of an array packed
# 256 / width in a slot, or 0 (None) if it isn't one
FUNC st_packed
        ENTER
        sub rsp, 48
        .set PK_PER, 0
        .set PK_LP, 8
        .set PK_LW, 16
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov rdi, rdx                    # (an access of a size computed at
        call is_int                     # runtime, say: none)
        test eax, eax
        jz .Lpk_none
        cmp r13, 1
        jle .Lpk_none
        cmp r13, (256 << 1) | 1
        jg .Lpk_none
        mov edi, (256 << 1) | 1
        mov rsi, r13
        call int_floordiv               # per = 256 // width
        mov [rsp + PK_PER], rax
        mov rdi, rax
        call st_log2
        mov [rsp + PK_LP], rax
        mov rdi, r13
        call st_log2
        mov [rsp + PK_LW], rax
        cmp qword ptr [rsp + PK_LP], 0
        je .Lpk_none
        cmp qword ptr [rsp + PK_LW], 0
        je .Lpk_none
        mov rax, [rsp + PK_PER]
        cmp rax, (2 << 1) | 1           # per < 2 (a power of 2: small)
        jl .Lpk_none
        mov rdi, r12
        call is_int
        test eax, eax
        jz 2f
        # a number of bits: an element at a constant index
        mov rdi, rbx
        call is_int
        test eax, eax
        jz .Lpk_none
        mov rdi, r12
        mov rsi, r13
        call int_mod
        cmp rax, 1
        jne .Lpk_none
        mov rdi, rbx
        call int_sign
        test eax, eax
        js .Lpk_none
        mov rdi, rbx                    # e * per + off // width
        mov rsi, [rsp + PK_PER]
        call int_mul
        mov r14, rax
        mov rdi, r12
        mov rsi, r13
        call int_floordiv
        mov rdi, r14
        mov rsi, rax
        call int_add
        jmp .Lpk_ret
2:      # off ~ ('mask_shl', int a, 0, lw, x)
        mov rdi, r12
        OP_N_CHECK OP_MASK_SHL, 5, .Lpk_none
        mov rdi, [r12 + N_DATA + 8]
        call is_int
        test eax, eax
        jz .Lpk_none
        mov rdi, [r12 + N_DATA + 16]
        mov esi, 1
        call py_equal
        test eax, eax
        jz .Lpk_none
        mov rdi, [r12 + N_DATA + 24]
        mov rsi, [rsp + PK_LW]
        call py_equal
        test eax, eax
        jz .Lpk_none
        mov r14, [r12 + N_DATA + 8]     # a
        cmp r14, [rsp + PK_LP]
        jne 3f
        # e == ('mask_shl', 256 - lp, lp, -lp, x): x
        mov rax, [rsp + PK_LP]
        sar rax, 1
        mov esi, 256
        sub rsi, rax
        TAG rsi
        mov rdx, [rsp + PK_LP]
        neg rax
        mov rcx, rax
        TAG rcx
        mov r8, [r12 + N_DATA + 32]
        LOADS rdi, MASK_SHL
        call mk5
        cmp rax, rbx
        jne .Lpk_none
        mov rax, [r12 + N_DATA + 32]
        jmp .Lpk_ret
3:      mov rdi, r14                    # a < lp and e == 0:
        mov rsi, [rsp + PK_LP]          # ('mask_shl', a, 0, 0, x)
        call int_cmp
        cmp eax, -1
        jne .Lpk_none
        mov rdi, rbx
        mov esi, 1
        call py_equal
        test eax, eax
        jz .Lpk_none
        LOADS rdi, MASK_SHL
        mov rsi, r14
        mov edx, 1
        mov ecx, 1
        mov r8, [r12 + N_DATA + 32]
        call mk5
        jmp .Lpk_ret
.Lpk_none:
        xor eax, eax
.Lpk_ret:
        add rsp, 48
        LEAVE
ENDF st_packed

# st_element_offset(st) -> rax: the offset from the start of the elements,
# rdx: the steps after it (python's element_offset)
FUNC st_element_offset
        ENTER
        mov rbx, rdi
        cmp dword ptr [rbx + N_AUX], 0
        je 1f
        mov r12, [rbx + N_DATA]
        mov rdi, r12
        call opcode_of
        cmp eax, OP_OFF
        jne 1f
        mov rdi, rbx
        mov esi, 1
        call list_from
        mov rdx, rax
        mov rax, [r12 + N_DATA + 8]
        LEAVE
1:      mov eax, 1
        mov rdx, rbx
        LEAVE
ENDF st_element_offset

# st_elem_width(t) -> rax: python's elem_width - the bits an element of
# type t takes in its slot (a packed array's), tagged
FUNC st_elem_width
        ENTER
        mov rbx, rdi
        call opcode_of
        cmp eax, OP_VALUE
        jne 8f
        mov r12, [rbx + N_DATA + 8]     # w < 256 and 256 % w == 0 and w >= 8
        mov rdi, r12
        call is_int
        test eax, eax
        jz .Lew_type
        mov rdi, r12
        mov esi, (256 << 1) | 1
        call int_cmp
        cmp eax, -1
        jne 8f
        cmp r12, 1
        je .Lew_zero
        mov edi, (256 << 1) | 1
        mov rsi, r12
        call int_mod
        cmp rax, 1
        jne 8f
        mov rdi, r12
        mov esi, (8 << 1) | 1
        call int_cmp
        cmp eax, -1
        je 8f
        mov rax, r12
        LEAVE
8:      mov eax, (256 << 1) | 1
        LEAVE
.Lew_type:
        mov edi, E_TYPE
        lea rsi, [rip + .Ls_cmp_type]
        call err_throw
.Lew_zero:
        mov edi, E_ZERO_DIV
        lea rsi, [rip + .Ls_zero_div]
        call err_throw
ENDF st_elem_width

# st_int_in(v, lo, hi) -> eax: lo <= v < hi for an int v (tagged bounds)
FUNC st_int_in
        ENTER
        mov rbx, rdi
        mov r12, rdx
        call int_cmp
        cmp eax, -1
        je 8f
        mov rdi, rbx
        mov rsi, r12
        call int_cmp
        cmp eax, -1
        jne 8f
        mov eax, 1
        LEAVE
8:      xor eax, eax
        LEAVE
ENDF st_int_in

# ---------------------------------------------------------------------
# the types: what's at a slot, from how the functions reach it

# st_pair_is(pairs, size, off) -> eax: (size, off) among the pairs (a vec
# of (size, off) tuples), as python's == compares them
FUNC st_pair_is
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        xor r14d, r14d
1:      cmp r14, [rbx + VEC_LEN]
        jae 8f
        mov rax, [rbx + VEC_DATA]
        mov rax, [rax + r14*8]
        inc r14
        mov rdi, [rax + N_DATA]
        mov rsi, r12
        call py_equal
        test eax, eax
        jz 1b
        mov rax, [rbx + VEC_DATA]
        mov rax, [rax + r14*8 - 8]
        mov rdi, [rax + N_DATA + 8]
        mov rsi, r13
        call py_equal
        test eax, eax
        jz 1b
        mov eax, 1
        LEAVE
8:      xor eax, eax
        LEAVE
ENDF st_pair_is

# st_is_bytes_slot(pairs) -> eax: python's is_bytes_slot - the fields
# (size, off) read from the slot of a bytes or a string: its lowest bit
# tells a long one from a short one, the length being the rest
FUNC st_is_bytes_slot
        ENTER
        mov rbx, rdi
        mov esi, 3
        mov edx, 1
        call st_pair_is                 # (1, 0)
        test eax, eax
        jz 8f
        mov rdi, rbx
        mov esi, (255 << 1) | 1
        mov edx, 3
        call st_pair_is
        test eax, eax
        jnz 9f
        mov rdi, rbx
        mov esi, (7 << 1) | 1
        mov edx, 3
        call st_pair_is
        test eax, eax
        jnz 9f
        mov rdi, rbx
        mov esi, (248 << 1) | 1
        mov edx, (8 << 1) | 1
        call st_pair_is
        test eax, eax
        jnz 9f
8:      xor eax, eax
        LEAVE
9:      mov eax, 1
        LEAVE
ENDF st_is_bytes_slot

# st_reads_bytes_length(pairs) -> eax: the fields (size, off) read are
# all of those of a bytes' length, {(1, 0), (7, 1), (255, 1)} <= pairs
FUNC st_reads_bytes_length
        ENTER
        mov rbx, rdi
        mov esi, 3
        mov edx, 1
        call st_pair_is                 # (1, 0)
        test eax, eax
        jz 8f
        mov rdi, rbx
        mov esi, (7 << 1) | 1
        mov edx, 3
        call st_pair_is                 # (7, 1)
        test eax, eax
        jz 8f
        mov rdi, rbx
        mov esi, (255 << 1) | 1
        mov edx, 3
        call st_pair_is                 # (255, 1)
        LEAVE
8:      xor eax, eax
        LEAVE
ENDF st_reads_bytes_length

# st_step_kind(st) -> eax: the kind of the first step of a list of steps:
# 0 none, OP_MAP, OP_DATA, OP_BLEN, OP_OFF
FUNC st_step_kind
        xor eax, eax
        cmp dword ptr [rdi + N_AUX], 0
        je 1f
        mov rdi, [rdi + N_DATA]
        jmp opcode_of
1:      ret
ENDF st_step_kind

.set TK_DATA, 0                 # typeof's kinds, in the order of their names
.set TK_FIXED, 1
.set TK_MAP, 2
.set TK_MEMBER, 3

# st_typeof(accs) -> type: python's typeof - the type of what's at a slot,
# from its accesses (a vec of (steps, size, off) tuples): the most of them
FUNC st_typeof
        STACK_CHECK
        ENTER
        sub rsp, 96
        .set TY_COUNTS, 0               # the kinds' counts (4)
        .set TY_DIRECT, 32              # the (size, off) of the accesses of the slot itself
        .set TY_KIND, 40
        .set TY_VEC, 48
        .set TY_MAX, 56
        .set TY_MIN, 64
        .set TY_FLAG, 72
        mov rbx, rdi
        xor eax, eax
        mov [rsp + TY_COUNTS], rax
        mov [rsp + TY_COUNTS + 8], rax
        mov [rsp + TY_COUNTS + 16], rax
        mov [rsp + TY_COUNTS + 24], rax
        call vec_new
        mov [rsp + TY_DIRECT], rax
        xor r12d, r12d
1:      cmp r12, [rbx + VEC_LEN]
        jae 5f
        mov rax, [rbx + VEC_DATA]
        mov r13, [rax + r12*8]          # (st, size, off)
        inc r12
        mov rdi, [r13 + N_DATA]
        call st_step_kind
        test eax, eax
        jnz 2f
        mov rdi, [r13 + N_DATA + 8]     # direct: (size, off)
        mov rsi, [r13 + N_DATA + 16]
        call mk2
        mov rdi, [rsp + TY_DIRECT]
        mov rsi, rax
        call vec_push
        jmp 1b
2:      mov ecx, TK_DATA
        cmp eax, OP_BLEN
        je 4f
        cmp eax, OP_DATA
        je 4f
        mov ecx, TK_MAP
        cmp eax, OP_MAP
        je 4f
        mov rax, [r13 + N_DATA]         # ('off', e): a member, or an element
        mov rax, [rax + N_DATA]
        mov rdi, [rax + N_DATA + 8]
        call is_int
        mov ecx, TK_FIXED
        test eax, eax
        jz 4f
        mov ecx, TK_MEMBER
4:      inc qword ptr [rsp + TY_COUNTS + rcx*8]
        jmp 1b
5:      # the kind of the most of them (ties: the greatest name)
        mov qword ptr [rsp + TY_KIND], -1
        xor r12d, r12d                  # the best count
        xor ecx, ecx
6:      mov rax, [rsp + TY_COUNTS + rcx*8]
        test rax, rax
        jz 7f
        cmp rax, r12
        jb 7f
        mov r12, rax
        mov [rsp + TY_KIND], rcx
7:      inc ecx
        cmp ecx, 4
        jb 6b
        cmp qword ptr [rsp + TY_KIND], -1
        je .Lty_direct
        # elements at the slot plus an index: some at a constant one (a
        # Vyper string's length, its first word)
        cmp qword ptr [rsp + TY_COUNTS + 8*TK_FIXED], 0
        je 8f
        cmp qword ptr [rsp + TY_COUNTS + 8*TK_MEMBER], 0
        je 8f
        cmp qword ptr [rsp + TY_COUNTS + 8*TK_DATA], 0
        jne 8f
        cmp qword ptr [rsp + TY_COUNTS + 8*TK_MAP], 0
        jne 8f
        mov qword ptr [rsp + TY_KIND], TK_FIXED
8:      mov rax, [rsp + TY_KIND]
        cmp eax, TK_MAP
        je .Lty_map
        cmp eax, TK_MEMBER
        je .Lty_member
        cmp eax, TK_DATA
        je .Lty_data
        # a fixed array: its elements at the slot plus their index
        mov esi, OP_OFF
        xor edx, edx
        call .Lty_select
        mov rdi, rax
        call st_array_type
        mov rsi, rax
        LOADS rdi, FIXED
        call mk3
        jmp .Lty_ret
.Lty_map:
        mov esi, OP_MAP
        mov edx, 1
        call .Lty_select
        mov rdi, rax
        call st_typeof
        mov rsi, rax
        LOADS rdi, MAPPING
        call mk2
        jmp .Lty_ret
.Lty_member:
        # ('struct', max(members) + 1 if min(members) >= 0 else None)
        mov qword ptr [rsp + TY_MAX], 0
        xor r12d, r12d
1:      cmp r12, [rbx + VEC_LEN]
        jae 3f
        mov rax, [rbx + VEC_DATA]
        mov r13, [rax + r12*8]
        inc r12
        mov rdi, [r13 + N_DATA]
        call st_step_kind
        cmp eax, OP_OFF
        jne 1b
        mov rax, [r13 + N_DATA]
        mov rax, [rax + N_DATA]
        mov r14, [rax + N_DATA + 8]     # the member
        mov rdi, r14
        call is_int
        test eax, eax
        jz 1b
        cmp qword ptr [rsp + TY_MAX], 0
        jne 2f
        mov [rsp + TY_MAX], r14
        mov [rsp + TY_MIN], r14
        jmp 1b
2:      mov rdi, r14
        mov rsi, [rsp + TY_MAX]
        call int_max
        mov [rsp + TY_MAX], rax
        mov rdi, r14
        mov rsi, [rsp + TY_MIN]
        call int_min
        mov [rsp + TY_MIN], rax
        jmp 1b
3:      mov rdi, [rsp + TY_MIN]
        call int_sign
        lea rsi, [rip + sp_none]
        test eax, eax
        js 4f
        mov rdi, [rsp + TY_MAX]
        mov esi, 3
        call int_add
        mov rsi, rax
4:      LOADS rdi, STRUCT
        call mk2
        jmp .Lty_ret
.Lty_data:
        # the length of a bytes read: a bytes - else an array
        xor r12d, r12d
1:      cmp r12, [rbx + VEC_LEN]
        jae 2f
        mov rax, [rbx + VEC_DATA]
        mov r13, [rax + r12*8]
        inc r12
        mov rdi, [r13 + N_DATA]
        call st_step_kind
        cmp eax, OP_BLEN
        je .Lty_bytes
        jmp 1b
2:      mov rdi, [rsp + TY_DIRECT]
        call st_is_bytes_slot
        test eax, eax
        jnz .Lty_bytes
        mov esi, OP_DATA
        mov edx, 1
        call .Lty_select
        mov rdi, rax
        call st_array_type
        mov rsi, rax
        LOADS rdi, ARRAY
        call mk3
        jmp .Lty_ret
.Lty_bytes:
        LOADS rdi, BYTES
        call mk1
        jmp .Lty_ret
.Lty_direct:
        # no steps: a value of the bits read, if all at the bit 0
        mov rax, [rsp + TY_DIRECT]
        cmp qword ptr [rax + VEC_LEN], 0
        je .Lty_empty
        xor r12d, r12d
1:      mov rax, [rsp + TY_DIRECT]
        cmp r12, [rax + VEC_LEN]
        jae 2f
        mov rax, [rax + VEC_DATA]
        mov r13, [rax + r12*8]
        inc r12
        mov rdi, [r13 + N_DATA + 8]
        mov esi, 1
        call py_equal
        test eax, eax
        jz .Lty_widths
        jmp 1b
2:      xor r12d, r12d
3:      mov rax, [rsp + TY_DIRECT]
        cmp r12, [rax + VEC_LEN]
        jae 4f
        mov rax, [rax + VEC_DATA]
        mov r13, [rax + r12*8]
        inc r12
        mov rdi, [r13 + N_DATA]
        call is_int
        test eax, eax
        jz .Lty_widths
        jmp 3b
4:      xor r12d, r12d                  # ('value', max(sizes))
        mov qword ptr [rsp + TY_MAX], 0
5:      mov rax, [rsp + TY_DIRECT]
        cmp r12, [rax + VEC_LEN]
        jae 7f
        mov rax, [rax + VEC_DATA]
        mov r13, [rax + r12*8]
        inc r12
        mov r14, [r13 + N_DATA]
        cmp qword ptr [rsp + TY_MAX], 0
        je 6f
        mov rdi, r14
        mov rsi, [rsp + TY_MAX]
        call int_max
        mov r14, rax
6:      mov [rsp + TY_MAX], r14
        jmp 5b
7:      mov rsi, [rsp + TY_MAX]
        LOADS rdi, VALUE
        call mk2
        jmp .Lty_ret
.Lty_widths:
        # the elements of a packed array, at bits computed at runtime
        mov qword ptr [rsp + TY_MAX], 0         # the one width
        mov qword ptr [rsp + TY_FLAG], 0        # more than one
        xor r12d, r12d
1:      mov rax, [rsp + TY_DIRECT]
        cmp r12, [rax + VEC_LEN]
        jae 3f
        mov rax, [rax + VEC_DATA]
        mov r13, [rax + r12*8]
        inc r12
        mov rdi, [r13 + N_DATA + 8]
        call is_int
        test eax, eax
        jnz 1b
        mov r14, [r13 + N_DATA]
        mov rax, [rsp + TY_MAX]
        test rax, rax
        jz 2f
        mov rdi, rax
        mov rsi, r14
        call py_equal
        test eax, eax
        jnz 1b
        mov qword ptr [rsp + TY_FLAG], 1
        jmp 1b
2:      mov [rsp + TY_MAX], r14
        jmp 1b
3:      cmp qword ptr [rsp + TY_MAX], 0
        je .Lty_struct1
        cmp qword ptr [rsp + TY_FLAG], 0
        jne .Lty_struct1
        LOADS rdi, VALUE
        mov rsi, [rsp + TY_MAX]
        call mk2
        mov r14, rax
        mov rdi, rax
        call st_elem_width
        cmp rax, (256 << 1) | 1
        je .Lty_struct1
        mov rsi, r14                    # ('fixed', ('value', w), 1)
        mov edx, 3
        LOADS rdi, FIXED
        call mk3
        jmp .Lty_ret
.Lty_struct1:
        LOADS rdi, STRUCT
        mov esi, 3
        call mk2
.Lty_ret:
        add rsp, 96
        LEAVE
.Lty_empty:
        mov edi, E_VALUE
        lea rsi, [rip + .Ls_max_empty]
        call err_throw
# .Lty_select: the accesses whose first step is of the kind esi, as (steps
# from it (edx 1) or from the start (edx 0), size, off) - a vec
.Lty_select:
        push r12
        push r13
        push r14
        push rbp
        sub rsp, 24
        mov [rsp], esi
        mov [rsp + 4], edx
        call vec_new
        mov [rsp + 8], rax
        xor r12d, r12d
1:      cmp r12, [rbx + VEC_LEN]
        jae 3f
        mov rax, [rbx + VEC_DATA]
        mov r13, [rax + r12*8]
        inc r12
        mov rdi, [r13 + N_DATA]
        call st_step_kind
        cmp eax, [rsp]
        jne 1b
        mov rdi, [r13 + N_DATA]
        cmp dword ptr [rsp + 4], 0
        je 2f
        mov esi, 1
        call list_from
        mov rdi, rax
2:      mov rsi, [r13 + N_DATA + 8]
        mov rdx, [r13 + N_DATA + 16]
        call mk3
        mov rdi, [rsp + 8]
        mov rsi, rax
        call vec_push
        jmp 1b
3:      mov rax, [rsp + 8]
        add rsp, 24
        pop rbp
        pop r14
        pop r13
        pop r12
        ret
ENDF st_typeof

# st_array_type(elems) -> rax: (element type, stride) of an array, from
# the accesses of its elements (python's array_type; a vec of (steps,
# size, off))
FUNC st_array_type
        STACK_CHECK
        ENTER
        sub rsp, 96
        .set AT_W, 0                    # the one width of the packed elements
        .set AT_WN, 8                   # more than one
        .set AT_LIN, 16                 # each one's linear form (i, s, c): a vec of 3 words
        .set AT_STRIDE, 24
        .set AT_INNER, 32
        .set AT_OUT, 40                 # st_linear's (24 bytes)
        .set AT_E, 64
        .set AT_REST, 72
        mov rbx, rdi
        mov qword ptr [rsp + AT_W], 0
        mov qword ptr [rsp + AT_WN], 0
        xor r12d, r12d
1:      cmp r12, [rbx + VEC_LEN]
        jae 3f
        mov rax, [rbx + VEC_DATA]
        mov r13, [rax + r12*8]
        inc r12
        mov rdi, [r13 + N_DATA]
        call st_element_offset
        cmp dword ptr [rdx + N_AUX], 0
        jne 1b
        mov [rsp + AT_E], rax
        mov r14, [r13 + N_DATA + 8]     # size: an int in [8, 256)
        mov rdi, r14
        call is_int
        test eax, eax
        jz 1b
        mov rdi, r14
        mov esi, (8 << 1) | 1
        mov edx, (256 << 1) | 1
        call st_int_in
        test eax, eax
        jz 1b
        mov rdi, [rsp + AT_E]
        mov rsi, [r13 + N_DATA + 16]
        mov rdx, r14
        call st_packed
        test rax, rax
        jz 1b
        mov rax, [rsp + AT_W]
        test rax, rax
        jz 2f
        cmp rax, r14
        je 1b
        mov qword ptr [rsp + AT_WN], 1
        jmp 1b
2:      mov [rsp + AT_W], r14
        jmp 1b
3:      cmp qword ptr [rsp + AT_W], 0
        je .Lat_strides
        cmp qword ptr [rsp + AT_WN], 0
        jne .Lat_strides
        # all of them elements of the width: a packed array of values
        xor r12d, r12d
4:      cmp r12, [rbx + VEC_LEN]
        jae 5f
        mov rax, [rbx + VEC_DATA]
        mov r13, [rax + r12*8]
        inc r12
        mov rdi, [r13 + N_DATA]
        call st_element_offset
        cmp dword ptr [rdx + N_AUX], 0
        jne .Lat_strides
        mov rdi, rax
        mov rsi, [r13 + N_DATA + 16]
        mov rdx, [r13 + N_DATA + 8]
        call st_packed
        test rax, rax
        jz .Lat_strides
        jmp 4b
5:      LOADS rdi, VALUE
        mov rsi, [rsp + AT_W]
        call mk2
        mov rdi, rax
        mov esi, 3
        call mk2
        jmp .Lat_ret
.Lat_strides:
        # the stride: the gcd of the strides of the elements
        mov rdi, [rbx + VEC_LEN]
        lea rdi, [rdi + rdi*2]
        call vec_new_cap
        mov [rsp + AT_LIN], rax
        mov qword ptr [rsp + AT_STRIDE], 0
        xor r12d, r12d
1:      cmp r12, [rbx + VEC_LEN]
        jae 3f
        mov rax, [rbx + VEC_DATA]
        mov r13, [rax + r12*8]
        inc r12
        mov rdi, [r13 + N_DATA]
        call st_element_offset
        mov rdi, rax
        lea rsi, [rsp + AT_OUT]
        call st_linear
        .irp i, 0, 1, 2
        mov rdi, [rsp + AT_LIN]
        mov rsi, [rsp + AT_OUT + 8*\i]
        call vec_push
        .endr
        mov r14, [rsp + AT_OUT + 8]     # s
        cmp r14, 1
        je 1b
        mov rax, [rsp + AT_STRIDE]
        test rax, rax
        jnz 2f
        mov [rsp + AT_STRIDE], r14
        jmp 1b
2:      mov rdi, rax
        mov rsi, r14
        call st_int_gcd
        mov [rsp + AT_STRIDE], rax
        jmp 1b
3:      cmp qword ptr [rsp + AT_STRIDE], 0
        jne 4f
        mov qword ptr [rsp + AT_STRIDE], 3
4:      # the members: the constant modulo the stride, before the rest
        call vec_new
        mov [rsp + AT_INNER], rax
        xor r12d, r12d
5:      cmp r12, [rbx + VEC_LEN]
        jae 7f
        mov rax, [rbx + VEC_DATA]
        mov r13, [rax + r12*8]
        mov rdi, [r13 + N_DATA]
        call st_element_offset
        mov [rsp + AT_REST], rdx
        mov rax, [rsp + AT_LIN]
        mov rax, [rax + VEC_DATA]
        lea rcx, [r12 + r12*2]
        mov rdi, [rax + rcx*8 + 16]     # c
        inc r12
        mov rsi, [rsp + AT_STRIDE]
        call int_mod
        cmp rax, 1
        je 6f
        mov rsi, rax
        LOADS rdi, OFF
        call mk2
        mov rdi, rax
        call mk_list1
        mov rdi, rax
        mov rsi, [rsp + AT_REST]
        call list_concat
        mov [rsp + AT_REST], rax
6:      mov rdi, [rsp + AT_REST]
        mov rsi, [r13 + N_DATA + 8]
        mov rdx, [r13 + N_DATA + 16]
        call mk3
        mov rdi, [rsp + AT_INNER]
        mov rsi, rax
        call vec_push
        jmp 5b
7:      mov rdi, [rsp + AT_INNER]
        call st_typeof
        mov r14, rax
        mov rdi, rax
        call opcode_of
        cmp eax, OP_STRUCT
        je 8f
        cmp qword ptr [rsp + AT_STRIDE], 3      # stride > 1 (it's >= 1)
        je 9f
8:      LOADS rdi, STRUCT
        mov rsi, [rsp + AT_STRIDE]
        call mk2
        mov r14, rax
9:      mov rdi, r14
        mov rsi, [rsp + AT_STRIDE]
        call mk2
.Lat_ret:
        mov rdx, [rax + N_DATA + 8]
        mov rax, [rax + N_DATA]
        add rsp, 96
        LEAVE
ENDF st_array_type

# st_int_gcd(a, b) -> value: math.gcd of two ints
FUNC st_int_gcd
        ENTER
        call arith_load
        lea rdi, [r15 + CTX_MPZ_R]
        lea rsi, [r15 + CTX_MPZ_A]
        lea rdx, [r15 + CTX_MPZ_B]
        call __gmpz_gcd@PLT
        call arith_result
        LEAVE
ENDF st_int_gcd

# ---------------------------------------------------------------------
# the printed accesses

# st_value_width(t) -> rax: python's value_width - the bits of a value,
# else a word
FUNC st_value_width
        ENTER
        mov rbx, rdi
        call opcode_of
        mov ecx, eax
        mov eax, (256 << 1) | 1
        cmp ecx, OP_VALUE
        jne 1f
        mov rax, [rbx + N_DATA + 8]
1:      LEAVE
ENDF st_value_width

# st_mk_st(size, loc, width) -> ('st', size, loc, width)
FUNC st_mk_st
        mov rcx, rdx
        mov rdx, rsi
        mov rsi, rdi
        LOADS rdi, ST
        jmp mk4
ENDF st_mk_st

# st_form(base, t, st, size, off) -> rax: python's form - the printed access
# of `size` bits at `off` of what's at the steps st from base, a loc of
# type t; 0 for a Fail
FUNC st_form
        STACK_CHECK
        ENTER
        sub rsp, 64
        .set FO_BASE, 0
        .set FO_T, 8
        .set FO_ST, 16
        .set FO_SIZE, 24
        .set FO_OFF, 32
        .set FO_TK, 40
        .set FO_TMP, 48
        mov [rsp + FO_BASE], rdi
        mov [rsp + FO_T], rsi
        mov [rsp + FO_ST], rdx
        mov [rsp + FO_SIZE], rcx
        mov [rsp + FO_OFF], r8
        mov rdi, rsi
        call opcode_of
        mov [rsp + FO_TK], rax
        mov rbx, [rsp + FO_ST]
        cmp dword ptr [rbx + N_AUX], 0
        je .Lfo_slot
        mov r12, [rbx + N_DATA]         # s = st[0]
        mov rdi, r12
        call opcode_of
        cmp eax, OP_MAP
        je .Lfo_map
        cmp eax, OP_BLEN
        je .Lfo_blen
        cmp eax, OP_DATA
        je .Lfo_data
        cmp eax, OP_OFF
        je .Lfo_off
        jmp .Lfo_fail
.Lfo_map:
        cmp dword ptr [rsp + FO_TK], OP_MAPPING
        jne .Lfo_fail
        LOADS rdi, SI
        mov rsi, [rsp + FO_BASE]
        mov rdx, [r12 + N_DATA + 8]
        call mk3
        mov [rsp + FO_TMP], rax
        mov rdi, rbx
        mov esi, 1
        call list_from
        mov rdx, rax
        mov rdi, [rsp + FO_TMP]
        mov rsi, [rsp + FO_T]
        mov rsi, [rsi + N_DATA + 8]
        mov rcx, [rsp + FO_SIZE]
        mov r8, [rsp + FO_OFF]
        call st_form
        jmp .Lfo_ret
.Lfo_blen:
        cmp dword ptr [rsp + FO_TK], OP_BYTES
        jne .Lfo_fail
        cmp dword ptr [rbx + N_AUX], 1
        jne .Lfo_fail
        LOADS rdi, SBL
        mov rsi, [rsp + FO_BASE]
        call mk2
        mov edi, (256 << 1) | 1
        mov rsi, rax
        mov edx, (256 << 1) | 1
        call st_mk_st
        mov r13, rax                    # loc
        mov rdi, [rsp + FO_OFF]
        mov esi, 1
        call py_equal
        test eax, eax
        jz 1f
        mov rdi, [rsp + FO_SIZE]
        mov esi, (256 << 1) | 1
        call py_equal
        test eax, eax
        jz 1f
        mov rax, r13
        jmp .Lfo_ret
1:      mov rdi, -1                     # (mul_op(-1, off): of an offset
        mov rsi, [rsp + FO_OFF]         # computed at runtime too)
        call alg_mul2
        mov rcx, rax
        LOADS rdi, MASK_SHL
        mov rsi, [rsp + FO_SIZE]
        mov rdx, [rsp + FO_OFF]
        mov r8, r13
        call mk5
        jmp .Lfo_ret
.Lfo_data:
        cmp dword ptr [rsp + FO_TK], OP_BYTES
        jne 2f
        mov rdi, rbx                    # a word of the data of a bytes
        mov esi, 1
        call list_from
        mov rdi, rax
        call st_element_offset
        cmp dword ptr [rdx + N_AUX], 0
        jne .Lfo_fail
        mov rdx, rax
        LOADS rdi, SI
        mov rsi, [rsp + FO_BASE]
        call mk3
        mov rdi, rax
        mov esi, 1
        mov rdx, [rsp + FO_SIZE]
        mov rcx, [rsp + FO_OFF]
        mov r8d, 1
        call st_field
        jmp .Lfo_ret
2:      cmp dword ptr [rsp + FO_TK], OP_ARRAY
        jne .Lfo_fail
        mov rdi, rbx
        mov esi, 1
        call list_from
        mov rdx, rax
        mov rdi, [rsp + FO_BASE]
        mov rsi, [rsp + FO_T]
        mov rcx, [rsp + FO_SIZE]
        mov r8, [rsp + FO_OFF]
        call st_element
        jmp .Lfo_ret
.Lfo_off:
        cmp dword ptr [rsp + FO_TK], OP_FIXED
        jne 3f
        mov rdi, [rsp + FO_BASE]
        mov rsi, [rsp + FO_T]
        mov rdx, rbx
        mov rcx, [rsp + FO_SIZE]
        mov r8, [rsp + FO_OFF]
        call st_element
        jmp .Lfo_ret
3:      mov r13, [r12 + N_DATA + 8]     # a member of a struct
        mov rdi, r13
        call is_int
        test eax, eax
        jz .Lfo_fail
        cmp dword ptr [rsp + FO_TK], OP_STRUCT
        jne .Lfo_fail
        cmp dword ptr [rbx + N_AUX], 1
        jne .Lfo_fail
        mov edi, (256 << 1) | 1
        mov rsi, r13
        call int_mul
        mov rsi, rax
        mov rdi, [rsp + FO_BASE]
        mov rdx, [rsp + FO_SIZE]
        mov rcx, [rsp + FO_OFF]
        mov r8d, 1
        call st_field
        jmp .Lfo_ret
.Lfo_slot:
        mov eax, [rsp + FO_TK]
        cmp eax, OP_VALUE
        jne .Lfo_array
        mov rax, [rsp + FO_T]
        mov r12, [rax + N_DATA + 8]     # width
        mov rdi, [rsp + FO_OFF]         # off == 0 and size <= width
        mov esi, 1
        call py_equal
        test eax, eax
        jz 1f
        mov rdi, [rsp + FO_SIZE]
        call is_int
        test eax, eax
        jz 1f
        mov rdi, [rsp + FO_SIZE]
        mov rsi, r12
        call int_cmp
        cmp eax, 1
        je 1f
        mov rdi, [rsp + FO_SIZE]
        mov rsi, [rsp + FO_BASE]
        mov rdx, r12
        call st_mk_st
        jmp .Lfo_ret
1:      # some bits of the value: 0 < off and off + size <= width
        mov rdi, [rsp + FO_OFF]
        call is_int
        test eax, eax
        jz .Lfo_array
        mov rdi, [rsp + FO_SIZE]
        call is_int
        test eax, eax
        jz .Lfo_array
        mov rdi, [rsp + FO_OFF]
        call int_sign
        cmp eax, 1
        jne .Lfo_array
        mov rdi, [rsp + FO_OFF]
        mov rsi, [rsp + FO_SIZE]
        call int_add
        mov rdi, rax
        mov rsi, r12
        call int_cmp
        cmp eax, 1
        je .Lfo_array
        mov rdi, r12
        mov rsi, [rsp + FO_BASE]
        mov rdx, r12
        call st_mk_st
        mov r13, rax
        mov rdi, [rsp + FO_OFF]
        call int_neg
        mov rcx, rax
        LOADS rdi, MASK_SHL
        mov rsi, [rsp + FO_SIZE]
        mov rdx, [rsp + FO_OFF]
        mov r8, r13
        call mk5
        jmp .Lfo_ret
.Lfo_array:
        mov eax, [rsp + FO_TK]
        cmp eax, OP_ARRAY
        jne 2f
        mov rdi, [rsp + FO_OFF]         # the slot of an array is its length
        mov esi, 1
        call py_equal
        test eax, eax
        jz .Lfo_field
        LOADS rdi, SL
        mov rsi, [rsp + FO_BASE]
        call mk2
        mov rdi, [rsp + FO_SIZE]
        mov rsi, rax
        mov edx, (256 << 1) | 1
        call st_mk_st
        jmp .Lfo_ret
2:      cmp eax, OP_BYTES
        jne 3f
        mov rdi, [rsp + FO_OFF]         # the slot of a bytes, whatever it holds
        mov esi, 1
        call py_equal
        test eax, eax
        jz .Lfo_field
        mov rdi, [rsp + FO_SIZE]
        mov rsi, [rsp + FO_BASE]
        mov edx, (256 << 1) | 1
        call st_mk_st
        jmp .Lfo_ret
3:      cmp eax, OP_FIXED
        jne .Lfo_field
        xor edi, edi                    # elements of a packed array in the slot
        xor esi, esi
        call mk_list
        mov rdx, rax
        mov rdi, [rsp + FO_BASE]
        mov rsi, [rsp + FO_T]
        mov rcx, [rsp + FO_SIZE]
        mov r8, [rsp + FO_OFF]
        call st_element
        jmp .Lfo_ret
.Lfo_field:
        # (the first word of a struct of more slots is its .field_0)
        mov r8d, 1
        cmp dword ptr [rsp + FO_TK], OP_STRUCT
        jne 4f
        mov rax, [rsp + FO_T]
        mov rdi, [rax + N_DATA + 8]
        mov esi, 3
        call py_equal
        mov r8d, eax
4:      mov rdi, [rsp + FO_BASE]
        mov esi, 1
        mov rdx, [rsp + FO_SIZE]
        mov rcx, [rsp + FO_OFF]
        call st_field
        jmp .Lfo_ret
.Lfo_fail:
        xor eax, eax
.Lfo_ret:
        add rsp, 64
        LEAVE
ENDF st_form

# st_field(base, bit, size, off, whole) -> rax: python's field - the bits
# [off, off + size) of the slot bit / 256 from base (the whole word at the
# bit 0 as base itself, when whole); 0 for a Fail
FUNC st_field
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov r14, rcx
        mov [rsp], r8
        mov rdi, rcx
        call is_int
        test eax, eax
        jz 8f
        mov rdi, r13
        call is_int
        test eax, eax
        jz 8f
        mov rdi, r12                    # n = bit + off
        mov rsi, r14
        call int_add
        mov r12, rax
        cmp rax, 1
        jne 1f
        cmp r13, (256 << 1) | 1
        jne 1f
        cmp qword ptr [rsp], 0
        je 1f
        mov edi, (256 << 1) | 1
        mov rsi, rbx
        mov edx, (256 << 1) | 1
        call st_mk_st
        jmp 9f
1:      LOADS rdi, SF
        mov rsi, rbx
        mov rdx, r12
        call mk3
        mov r14, rax
        mov rdi, r12                    # 256 - n % 256
        mov esi, 8
        call int_mod_2exp
        mov edi, (256 << 1) | 1
        mov rsi, rax
        call int_sub
        mov rdx, rax
        mov rdi, r13
        mov rsi, r14
        call st_mk_st
        jmp 9f
8:      xor eax, eax
9:      add rsp, 16
        LEAVE
ENDF st_field

# st_element(base, t, st, size, off) -> rax: python's element - an access
# of an element of the array base (st: from its start); 0 for a Fail
FUNC st_element
        STACK_CHECK
        ENTER
        sub rsp, 96
        .set EL_BASE, 0
        .set EL_ET, 8
        .set EL_STRIDE, 16
        .set EL_SIZE, 24
        .set EL_OFF, 32
        .set EL_E, 40
        .set EL_REST, 48
        .set EL_LIN, 56                 # (i, s, c)
        .set EL_INDEX, 80
        mov [rsp + EL_BASE], rdi
        mov rax, [rsi + N_DATA + 8]
        mov [rsp + EL_ET], rax
        mov rax, [rsi + N_DATA + 16]
        mov [rsp + EL_STRIDE], rax
        mov [rsp + EL_SIZE], rcx
        mov [rsp + EL_OFF], r8
        mov rdi, rdx
        call st_element_offset
        mov [rsp + EL_E], rax
        mov [rsp + EL_REST], rdx
        mov rdi, [rsp + EL_ET]
        call st_elem_width
        mov rbx, rax
        cmp rbx, (256 << 1) | 1
        jge 2f
        mov rax, [rsp + EL_REST]
        cmp dword ptr [rax + N_AUX], 0
        jne 2f
        # an element of a packed array
        mov rdi, [rsp + EL_E]
        mov rsi, [rsp + EL_OFF]
        mov rdx, [rsp + EL_SIZE]
        call st_packed
        test rax, rax
        jz .Lel_fail
        mov r12, rax
        mov rdi, [rsp + EL_SIZE]
        mov rsi, rbx
        call py_equal
        test eax, eax
        jz .Lel_fail
        LOADS rdi, SI
        mov rsi, [rsp + EL_BASE]
        mov rdx, r12
        call mk3
        mov rdi, [rsp + EL_SIZE]
        mov rsi, rax
        mov rdx, rbx
        call st_mk_st
        jmp .Lel_ret
2:      mov rdi, [rsp + EL_E]
        lea rsi, [rsp + EL_LIN]
        call st_linear
        mov rdi, [rsp + EL_LIN + 8]     # s % stride
        mov rsi, [rsp + EL_STRIDE]
        call int_mod
        cmp rax, 1
        jne .Lel_fail
        cmp qword ptr [rsp + EL_LIN + 8], 1
        je 4f
        mov rax, [rsp + EL_LIN]         # index = i, times s // stride
        mov [rsp + EL_INDEX], rax
        mov rdi, [rsp + EL_LIN + 8]
        mov rsi, [rsp + EL_STRIDE]
        call py_equal
        test eax, eax
        jnz 3f
        mov rdi, [rsp + EL_LIN + 8]
        mov rsi, [rsp + EL_STRIDE]
        call int_floordiv
        mov rdi, rax
        mov rsi, [rsp + EL_LIN]
        call alg_mul2
        mov [rsp + EL_INDEX], rax
3:      mov rdi, [rsp + EL_LIN + 16]    # plus c // stride
        mov rsi, [rsp + EL_STRIDE]
        call int_floordiv
        cmp rax, 1
        je 5f
        mov rdi, [rsp + EL_INDEX]
        mov rsi, rax
        call alg_add2
        mov [rsp + EL_INDEX], rax
        jmp 5f
4:      mov rdi, [rsp + EL_LIN + 16]    # index = c // stride
        mov rsi, [rsp + EL_STRIDE]
        call int_floordiv
        mov [rsp + EL_INDEX], rax
5:      mov rdi, [rsp + EL_LIN + 16]    # the member: c % stride
        mov rsi, [rsp + EL_STRIDE]
        call int_mod
        cmp rax, 1
        je 6f
        mov rsi, rax
        LOADS rdi, OFF
        call mk2
        mov rdi, rax
        call mk_list1
        mov rdi, rax
        mov rsi, [rsp + EL_REST]
        call list_concat
        mov [rsp + EL_REST], rax
6:      LOADS rdi, SI
        mov rsi, [rsp + EL_BASE]
        mov rdx, [rsp + EL_INDEX]
        call mk3
        mov rdi, rax
        mov rsi, [rsp + EL_ET]
        mov rdx, [rsp + EL_REST]
        mov rcx, [rsp + EL_SIZE]
        mov r8, [rsp + EL_OFF]
        call st_form
        jmp .Lel_ret
.Lel_fail:
        xor eax, eax
.Lel_ret:
        add rsp, 96
        LEAVE
ENDF st_element

# st_mul_neg1(off) -> ('mul', -1, off)
FUNC st_mul_neg1
        mov rdx, rdi
        LOADS rdi, MUL
        mov rsi, -1
        jmp mk3
ENDF st_mul_neg1

# st_raw(size, off, idx, write) -> rax: python's raw - the access as the
# slot it is: stor[idx] (a write of the length of a bytes: python's Fail,
# which nothing catches, E_STFAIL)
FUNC st_raw
        ENTER
        sub rsp, 48
        .set RW_SIZE, 0
        .set RW_OFF, 8
        .set RW_WRITE, 16
        .set RW_TMP, 24
        mov [rsp + RW_SIZE], rdi
        mov [rsp + RW_OFF], rsi
        mov rbx, rdx
        mov [rsp + RW_WRITE], rcx
        mov rdi, rbx
        OP_N_CHECK OP_LENGTH, 2, .Lrw_slot
        # the length of a bytes (see simplify.replace_bytes_or_string_length)
        mov r12, [rbx + N_DATA + 8]     # key
        mov rdi, r12
        call opcode_of
        cmp eax, OP_LOC
        jne 1f
        cmp dword ptr [r12 + N_AUX], 2
        jb .Lrw_index
        mov r12, [r12 + N_DATA + 8]
1:      LOADS rdi, SR
        mov rsi, r12
        call mk2
        mov r12, rax                    # ('sr', key)
        mov edi, (256 << 1) | 1
        mov rsi, rax
        mov edx, (256 << 1) | 1
        call st_mk_st
        mov r13, rax                    # slot
        mov edi, 3
        mov rsi, r12
        mov edx, (256 << 1) | 1
        call st_mk_st
        mov rsi, rax
        LOADS rdi, ISZERO
        call mk2
        mov r8, rax
        LOADS rdi, MASK_SHL
        mov esi, (248 << 1) | 1
        mov edx, 1
        mov ecx, (8 << 1) | 1
        call mk5
        mov rdx, rax
        LOADS rdi, ADD
        mov rsi, -1
        call mk3
        mov rdx, rax
        LOADS rdi, AND
        mov rsi, r13
        call mk3
        mov r8, rax
        LOADS rdi, MASK_SHL
        mov esi, (255 << 1) | 1
        mov edx, 3
        mov rcx, -1
        call mk5
        mov r13, rax                    # length
        cmp qword ptr [rsp + RW_WRITE], 0
        jne .Lrw_fail
        mov rdi, [rsp + RW_OFF]         # off != 0 or size != 256: a mask
        mov esi, 1
        call py_equal
        test eax, eax
        jz 2f
        mov rdi, [rsp + RW_SIZE]
        mov esi, (256 << 1) | 1
        call py_equal
        test eax, eax
        jz 2f
        mov rax, r13
        jmp .Lrw_ret
2:      mov rdi, [rsp + RW_OFF]
        call st_mul_neg1
        mov rcx, rax
        LOADS rdi, MASK_SHL
        mov rsi, [rsp + RW_SIZE]
        mov rdx, [rsp + RW_OFF]
        mov r8, r13
        call mk5
        jmp .Lrw_ret
.Lrw_slot:
        mov rdi, rbx
        call opcode_of
        cmp eax, OP_LOC
        jne 1f
        cmp dword ptr [rbx + N_AUX], 2
        jb .Lrw_index
        mov rbx, [rbx + N_DATA + 8]
1:      LOADS rdi, SR
        mov rsi, rbx
        call mk2
        mov r12, rax                    # base
        mov rdi, [rsp + RW_SIZE]
        call is_int
        test eax, eax
        jnz 3f
        # as many bits as computed at runtime
        cmp qword ptr [rsp + RW_WRITE], 0
        jne .Lrw_sf_none
        jmp .Lrw_mask
3:      mov rdi, [rsp + RW_OFF]
        mov esi, 1
        call py_equal
        test eax, eax
        jz 4f
        mov rdi, [rsp + RW_SIZE]
        mov rsi, r12
        mov edx, (256 << 1) | 1
        call st_mk_st
        jmp .Lrw_ret
4:      mov rdi, [rsp + RW_OFF]
        call is_int
        test eax, eax
        jz 5f
        mov rdi, [rsp + RW_OFF]
        call int_sign
        cmp eax, 1
        jne 5f
        LOADS rdi, SF                   # ('st', size, ('sf', base, off), 256 - off)
        mov rsi, r12
        mov rdx, [rsp + RW_OFF]
        call mk3
        mov [rsp + RW_TMP], rax
        mov edi, (256 << 1) | 1
        mov rsi, [rsp + RW_OFF]
        call int_sub
        mov rdx, rax
        mov rdi, [rsp + RW_SIZE]
        mov rsi, [rsp + RW_TMP]
        call st_mk_st
        jmp .Lrw_ret
5:      cmp qword ptr [rsp + RW_WRITE], 0
        jne .Lrw_sf_none
.Lrw_mask:
        mov edi, (256 << 1) | 1         # ('mask_shl', size, off, -off, stor[idx])
        mov rsi, r12
        mov edx, (256 << 1) | 1
        call st_mk_st
        mov [rsp + RW_TMP], rax
        mov rdi, [rsp + RW_OFF]
        call st_mul_neg1
        mov rcx, rax
        LOADS rdi, MASK_SHL
        mov rsi, [rsp + RW_SIZE]
        mov rdx, [rsp + RW_OFF]
        mov r8, [rsp + RW_TMP]
        call mk5
        jmp .Lrw_ret
.Lrw_sf_none:
        LOADS rdi, SF                   # ('st', size, ('sf', base, off), None)
        mov rsi, r12
        mov rdx, [rsp + RW_OFF]
        call mk3
        mov rdi, [rsp + RW_SIZE]
        mov rsi, rax
        lea rdx, [rip + sp_none]
        call st_mk_st
.Lrw_ret:
        add rsp, 48
        LEAVE
.Lrw_fail:
        mov edi, E_STFAIL
        lea rsi, [rip + .Ls_raw_fail]
        call err_throw
.Lrw_index:
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_tindex]
        call err_throw
ENDF st_raw

# ---------------------------------------------------------------------
# the variables of a slot

# st_pair_lt(a, b, arg) -> eax: python's a < b of two tuples of ints
FUNC st_pair_lt
        jmp py_lt
ENDF st_pair_lt

# st_merge_ranges(fields) -> list: python's merge_ranges - the intervals
# (off, end) the fields (a vec of (size, off)) cover, overlapping ones
# merged
FUNC st_merge_ranges
        ENTER
        sub rsp, 16
        mov rbx, rdi
        call vec_new
        mov r12, rax                    # (off, off + size), sorted
        xor r13d, r13d
1:      cmp r13, [rbx + VEC_LEN]
        jae 2f
        mov rax, [rbx + VEC_DATA]
        mov r14, [rax + r13*8]
        inc r13
        mov rdi, [r14 + N_DATA + 8]
        mov rsi, [r14 + N_DATA]
        call int_add
        mov rsi, rax
        mov rdi, [r14 + N_DATA + 8]
        call mk2
        mov rdi, r12
        mov rsi, rax
        call vec_push
        jmp 1b
2:      mov rdi, r12
        lea rsi, [rip + py_lt]
        xor edx, edx
        call py_sort
        call vec_new
        mov r13, rax                    # res
        xor r14d, r14d
3:      cmp r14, [r12 + VEC_LEN]
        jae 6f
        mov rax, [r12 + VEC_DATA]
        mov rbx, [rax + r14*8]          # (off, end)
        inc r14
        mov rcx, [r13 + VEC_LEN]
        test rcx, rcx
        jz 5f
        mov rax, [r13 + VEC_DATA]
        mov rax, [rax + rcx*8 - 8]      # res[-1]
        mov [rsp], rax
        mov rdi, [rbx + N_DATA]
        mov rsi, [rax + N_DATA + 8]
        call int_cmp
        cmp eax, -1
        jne 5f
        mov rax, [rsp]                  # (res[-1][0], max(res[-1][1], end))
        mov rdi, [rax + N_DATA + 8]
        mov rsi, [rbx + N_DATA + 8]
        call int_max
        mov rsi, rax
        mov rax, [rsp]
        mov rdi, [rax + N_DATA]
        call mk2
        mov rcx, [r13 + VEC_LEN]
        mov rdx, [r13 + VEC_DATA]
        mov [rdx + rcx*8 - 8], rax
        jmp 3b
5:      mov rdi, r13
        mov rsi, rbx
        call vec_push
        jmp 3b
6:      mov rdi, r13
        call vec_to_list
        add rsp, 16
        LEAVE
ENDF st_merge_ranges

# st_uncovered(parts, ranges) -> vec: python's uncovered - the (size, off)
# of the bits of the parts (a vec of (size, off)) no range (a list of
# (off, end)) has
FUNC st_uncovered
        ENTER
        sub rsp, 64
        .set UC_PARTS, 0
        .set UC_RANGES, 8
        .set UC_RES, 16
        .set UC_I, 24
        .set UC_POS, 32
        .set UC_END, 40
        .set UC_J, 48
        mov [rsp + UC_PARTS], rdi
        mov [rsp + UC_RANGES], rsi
        call vec_new                    # sorted(ranges)
        mov rbx, rax
        mov rdi, rax
        mov rsi, [rsp + UC_RANGES]
        call vec_extend_seq
        mov rdi, rbx
        lea rsi, [rip + py_lt]
        xor edx, edx
        call py_sort
        call vec_new
        mov [rsp + UC_RES], rax
        mov qword ptr [rsp + UC_I], 0
1:      mov rax, [rsp + UC_PARTS]
        mov rcx, [rsp + UC_I]
        cmp rcx, [rax + VEC_LEN]
        jae 6f
        mov rax, [rax + VEC_DATA]
        mov r12, [rax + rcx*8]          # (size, off)
        inc qword ptr [rsp + UC_I]
        mov rax, [r12 + N_DATA + 8]
        mov [rsp + UC_POS], rax
        mov rdi, rax
        mov rsi, [r12 + N_DATA]
        call int_add
        mov [rsp + UC_END], rax
        xor r13d, r13d
2:      cmp r13, [rbx + VEC_LEN]
        jae 5f
        mov rax, [rbx + VEC_DATA]
        mov r14, [rax + r13*8]          # (o, e)
        inc r13
        mov rdi, [r14 + N_DATA + 8]     # e <= pos or o >= end: not in it
        mov rsi, [rsp + UC_POS]
        call int_cmp
        cmp eax, 1
        jne 2b
        mov rdi, [r14 + N_DATA]
        mov rsi, [rsp + UC_END]
        call int_cmp
        cmp eax, -1
        jne 2b
        mov rdi, [r14 + N_DATA]
        mov rsi, [rsp + UC_POS]
        call int_cmp
        cmp eax, 1
        jne 3f
        mov rdi, [r14 + N_DATA]         # (o - pos, pos)
        mov rsi, [rsp + UC_POS]
        call int_sub
        mov rdi, rax
        mov rsi, [rsp + UC_POS]
        call mk2
        mov rdi, [rsp + UC_RES]
        mov rsi, rax
        call vec_push
3:      mov rdi, [rsp + UC_POS]
        mov rsi, [r14 + N_DATA + 8]
        call int_max
        mov [rsp + UC_POS], rax
        jmp 2b
5:      mov rdi, [rsp + UC_POS]         # pos < end: (end - pos, pos)
        mov rsi, [rsp + UC_END]
        call int_cmp
        cmp eax, -1
        jne 1b
        mov rdi, [rsp + UC_END]
        mov rsi, [rsp + UC_POS]
        call int_sub
        mov rdi, rax
        mov rsi, [rsp + UC_POS]
        call mk2
        mov rdi, [rsp + UC_RES]
        mov rsi, rax
        call vec_push
        jmp 1b
6:      mov rax, [rsp + UC_RES]
        add rsp, 64
        LEAVE
ENDF st_uncovered

# st_layout(accs) -> list: python's layout - the variables of a slot,
# (off, end) each, from its accesses (a vec of (size, off, written)):
# what's written, else what's read. A number written says nothing of how
# wide it is, so its bits are variables of their own only where nothing
# else is written
FUNC st_layout
        ENTER
        sub rsp, 48
        .set LY_ACCS, 0
        .set LY_WRITTEN, 8
        .set LY_NUMBERS, 16
        .set LY_FIELDS, 24
        .set LY_ALL, 32
        mov [rsp + LY_ACCS], rdi
        call vec_new
        mov [rsp + LY_WRITTEN], rax
        call vec_new
        mov [rsp + LY_NUMBERS], rax
        call vec_new
        mov [rsp + LY_ALL], rax
        mov rbx, [rsp + LY_ACCS]
        xor r12d, r12d
1:      cmp r12, [rbx + VEC_LEN]
        jae 4f
        mov rax, [rbx + VEC_DATA]
        mov r13, [rax + r12*8]
        inc r12
        mov rdi, [r13 + N_DATA]
        mov rsi, [r13 + N_DATA + 8]
        call mk2
        mov r14, rax                    # (size, off)
        mov rdi, [rsp + LY_ALL]
        mov rsi, rax
        call vec_push
        mov rax, [r13 + N_DATA + 16]    # written: True, "const" or False
        lea rcx, [rip + sp_true]
        cmp rax, rcx
        jne 2f
        mov rdi, [rsp + LY_WRITTEN]
        mov rsi, r14
        call vec_push
        jmp 1b
2:      LOADS rcx, CONST
        cmp rax, rcx
        jne 1b
        mov rdi, [rsp + LY_NUMBERS]
        mov rsi, r14
        call vec_push
        jmp 1b
4:      mov rdi, [rsp + LY_WRITTEN]
        call st_merge_ranges
        mov [rsp + LY_FIELDS], rax
        mov rdi, [rsp + LY_NUMBERS]
        mov rsi, rax
        call st_uncovered
        mov rdi, rax
        call st_merge_ranges
        mov r13, rax                    # numbers
        call vec_new                    # (e - o, o) of fields + numbers
        mov r14, rax
        mov rdi, [rsp + LY_FIELDS]
        call .Lly_sizes
        mov rdi, r13
        call .Lly_sizes
        cmp qword ptr [r14 + VEC_LEN], 0
        jne 5f
        mov r14, [rsp + LY_ALL]
5:      mov rdi, r14
        call st_merge_ranges
        add rsp, 48
        LEAVE
# the (end - off, off) of a list of (off, end), pushed on r14
.Lly_sizes:
        push rbx
        push r12
        push r13
        mov rbx, rdi
        xor r12d, r12d
1:      cmp r12d, [rbx + N_AUX]
        jae 2f
        mov r13, [rbx + N_DATA + r12*8]
        inc r12d
        mov rdi, [r13 + N_DATA + 8]
        mov rsi, [r13 + N_DATA]
        call int_sub
        mov rdi, rax
        mov rsi, [r13 + N_DATA]
        call mk2
        mov rdi, r14
        mov rsi, rax
        call vec_push
        jmp 1b
2:      pop r13
        pop r12
        pop rbx
        ret
ENDF st_layout

# st_slot_class(st) -> rax: python's slot_class - what the slots of the
# same place of a variable have in common, the steps to them without
# their keys and indexes: (root, (('map', kind) | ('data',) | ('off',
# stride, c), ...)), 0 (None) for a None or a length
FUNC st_slot_class
        ENTER
        sub rsp, 48
        test rdi, rdi
        jz 8f
        mov rbx, rdi
        call vec_new
        mov r12, rax
        mov r13, [rbx + N_DATA + 8]     # the steps
        xor r14d, r14d
1:      cmp r14d, [r13 + N_AUX]
        jae 5f
        mov rax, [r13 + N_DATA + r14*8]
        mov [rsp + 32], rax
        inc r14d
        mov rdi, rax
        call opcode_of
        cmp eax, OP_MAP
        jne 2f
        LOADS rdi, MAP
        mov rax, [rsp + 32]
        mov rsi, [rax + N_DATA + 16]
        call mk2
        jmp 4f
2:      cmp eax, OP_DATA
        jne 3f
        LOADS rdi, DATA
        call mk1
        jmp 4f
3:      cmp eax, OP_OFF
        jne 8f
        mov rax, [rsp + 32]
        mov rdi, [rax + N_DATA + 8]
        mov rsi, rsp
        call st_linear
        LOADS rdi, OFF
        mov rsi, [rsp + 8]
        mov rdx, [rsp + 16]
        call mk3
4:      mov rdi, r12
        mov rsi, rax
        call vec_push
        jmp 1b
5:      mov rdi, r12
        call vec_to_tuple
        mov rsi, rax
        mov rdi, [rbx + N_DATA]
        call mk2
        add rsp, 48
        LEAVE
8:      xor eax, eax
        add rsp, 48
        LEAVE
ENDF st_slot_class

# ---------------------------------------------------------------------
# the whole contract

# st_find_accesses(exp, od): python's find_accesses - the accesses in exp:
# (size, off, idx) -> False when it's only read, "const" when it's written
# numbers only, True when it's written others (od: an ordered dict)
FUNC st_find_accesses
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        test bl, 1
        jnz 9f
        test rbx, rbx
        jz 9f
        mov eax, [rbx + N_KIND]
        cmp eax, K_LIST
        je 5f
        cmp eax, K_TUPLE
        jne 9f
        mov rdi, rbx
        call opcode_of
        cmp eax, OP_STORAGE
        jne 2f
        cmp dword ptr [rbx + N_AUX], 4
        jne 5f
        mov rdi, [rbx + N_DATA + 8]     # setdefault(exp[1:], False)
        mov rsi, [rbx + N_DATA + 16]
        mov rdx, [rbx + N_DATA + 24]
        call mk3
        mov r13, rax
        mov rdi, r12
        mov rsi, rax
        call od_get
        test rax, rax
        jnz 5f
        mov rdi, r12
        mov rsi, r13
        lea rdx, [rip + sp_false]
        call od_put
        jmp 5f
2:      cmp eax, OP_STORE
        jne 5f
        cmp dword ptr [rbx + N_AUX], 5
        jne 5f
        mov rdi, [rbx + N_DATA + 8]
        mov rsi, [rbx + N_DATA + 16]
        mov rdx, [rbx + N_DATA + 24]
        call mk3
        mov r13, rax
        mov rdi, [rbx + N_DATA + 32]
        call is_int
        lea rdx, [rip + sp_true]
        test eax, eax
        jz 4f
        mov rdi, r12                    # a number: "const", unless written
        mov rsi, r13                    # another value before
        call od_get
        lea rcx, [rip + sp_true]
        cmp rax, rcx
        je 5f
        LOADS rdx, CONST
4:      mov rdi, r12
        mov rsi, r13
        call od_put
5:      xor r13d, r13d                  # every element (of a list, a tuple)
6:      cmp r13d, [rbx + N_AUX]
        jae 9f
        mov rdi, [rbx + N_DATA + r13*8]
        inc r13d
        test dil, 1
        jnz 6b
        test rdi, rdi
        jz 6b
        mov eax, [rdi + N_KIND]
        cmp eax, K_TUPLE
        je 7f
        cmp eax, K_LIST
        jne 6b
7:      mov rsi, r12
        call st_find_accesses
        jmp 6b
9:      LEAVE
ENDF st_find_accesses

# st_sha3_parts(h) -> rax: the parts of a sha3 (a pointer), rdx: their
# count - of the data it hashes, or its own
FUNC st_sha3_parts
        ENTER
        mov rbx, rdi
        cmp dword ptr [rbx + N_AUX], 2
        jne 1f
        mov rdi, [rbx + N_DATA + 8]
        call opcode_of
        cmp eax, OP_DATA
        jne 1f
        mov rcx, [rbx + N_DATA + 8]
        lea rax, [rcx + N_DATA + 8]
        mov edx, [rcx + N_AUX]
        dec edx
        LEAVE
1:      lea rax, [rbx + N_DATA + 8]
        mov edx, [rbx + N_AUX]
        dec edx
        LEAVE
ENDF st_sha3_parts

# st_hash_votes(exp) -> rax: language's votes over the hashes in exp
# (find_hashes): +1 for a number and something else hashed (vyper's slot
# . key), -1 the other way round
FUNC st_hash_votes
        STACK_CHECK
        ENTER
        sub rsp, 16
        mov rbx, rdi
        xor r12d, r12d
        mov rdi, rbx
        call is_tuple
        test eax, eax
        jz 9f
        mov rdi, rbx
        call opcode_of
        cmp eax, OP_SHA3
        jne 5f
        mov rdi, rbx
        call st_sha3_parts
        cmp rdx, 2
        jne 5f
        mov r13, rax
        mov rdi, [r13]
        call st_word
        mov rdi, rax
        call is_int
        mov r14d, eax                   # a is a number
        mov rdi, [r13 + 8]
        call st_word
        mov rdi, rax
        call is_int                     # b is a number
        cmp r14d, eax
        je 5f
        mov r12, 1
        test r14d, r14d
        jnz 5f
        mov r12, -1
5:      mov r13d, 1                     # exp[1:]
6:      cmp r13d, [rbx + N_AUX]
        jae 9f
        mov rdi, [rbx + N_DATA + r13*8]
        inc r13d
        call st_hash_votes
        add r12, rax
        jmp 6b
9:      mov rax, r12
        add rsp, 16
        LEAVE
ENDF st_hash_votes

        .section .rodata
.Ls_b_vyper:    .ascii "vyper"
.Ls_b_solc:     .ascii "solc"
.Ls_b_bzzr:     .ascii "bzzr"
.Ls_b_ipfs:     .ascii "ipfs"
        .text

# st_language(code, len, accesses) -> eax: python's language - 1 for
# "vyper", 0 for "solidity": from the metadata (the code's 80 last bytes;
# code 0: None), else from how the mappings hash (accesses: an od)
FUNC st_language
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        test rbx, rbx
        jz 3f
        cmp r12, 80
        jbe 1f
        lea rbx, [rbx + r12 - 80]
        mov r12d, 80
1:      mov rdi, rbx
        mov rsi, r12
        lea rdx, [rip + .Ls_b_vyper]
        mov ecx, 5
        call memmem@PLT
        test rax, rax
        jnz 8f
        .irp w, solc, bzzr, ipfs
        mov rdi, rbx
        mov rsi, r12
        lea rdx, [rip + .Ls_b_\w]
        mov ecx, 4
        call memmem@PLT
        test rax, rax
        jnz 9f
        .endr
3:      xor r14d, r14d                  # the votes
        xor ebx, ebx
4:      mov rdi, r13
        call od_len
        cmp rbx, rax
        jae 5f
        mov rdi, r13
        mov rsi, rbx
        call od_key
        inc rbx
        mov rdi, [rax + N_DATA + 16]    # idx
        call st_hash_votes
        add r14, rax
        jmp 4b
5:      test r14, r14
        jg 8f
9:      xor eax, eax
        add rsp, 16
        LEAVE
8:      mov eax, 1
        add rsp, 16
        LEAVE
ENDF st_language

# st_checked_below(trace, flags) -> od: python's checked_below - {x: n} for
# the checks that x < n, that revert otherwise; with CB_LOOPS the
# conditions x < n of the loops as well (in their bodies); with CB_ANY, x
# < y whatever y is (a length read from the storage), n None
FUNC st_checked_below
        ENTER
        mov rbx, rdi
        mov r13, rsi
        call od_new
        mov r12, rax
        mov rdi, rbx
        mov rsi, r12
        mov rdx, r13
        call st_cb_visit
        mov rax, r12
        LEAVE
ENDF st_checked_below

# st_cb_reverts(branch) -> eax: a branch of one revert or invalid
FUNC st_cb_reverts
        ENTER
        xor eax, eax
        cmp dword ptr [rdi + N_AUX], 1
        jne 1f
        mov rdi, [rdi + N_DATA]
        call opcode_of
        cmp eax, OP_REVERT
        sete cl
        cmp eax, OP_INVALID
        sete al
        or al, cl
        movzx eax, al
1:      LEAVE
ENDF st_cb_reverts

# st_cb_visit(lines, od, flags)
FUNC st_cb_visit
        STACK_CHECK
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        mov [rsp], rdx                  # flags
        xor r13d, r13d
1:      cmp r13d, [rbx + N_AUX]
        jae 9f
        mov r14, [rbx + N_DATA + r13*8]
        inc r13d
        mov rdi, r14
        call opcode_of
        cmp eax, OP_WHILE
        je 5f
        cmp eax, OP_IF
        jne 1b
        cmp dword ptr [r14 + N_AUX], 4
        jne 1b
        mov rdi, [r14 + N_DATA + 24]    # if_false reverts: cond holds
        call st_cb_reverts
        test eax, eax
        jz 2f
        mov rdi, [r14 + N_DATA + 8]
        mov rsi, r12
        mov rdx, [rsp]
        call st_cb_add
2:      mov rdi, [r14 + N_DATA + 16]    # if_true reverts: not cond
        call st_cb_reverts
        test eax, eax
        jz 3f
        LOADS rdi, ISZERO
        mov rsi, [r14 + N_DATA + 8]
        call mk2
        mov rdi, rax
        mov rsi, r12
        mov rdx, [rsp]
        call st_cb_add
3:      mov rdi, [r14 + N_DATA + 16]
        mov rsi, r12
        mov rdx, [rsp]
        call st_cb_visit
        mov rdi, [r14 + N_DATA + 24]
        mov rsi, r12
        mov rdx, [rsp]
        call st_cb_visit
        jmp 1b
5:      test qword ptr [rsp], CB_LOOPS  # (a loop goes on while its cond
        jz 6f                           # holds, in its body)
        cmp dword ptr [r14 + N_AUX], 2
        jb .Lcv_index
        mov rdi, [r14 + N_DATA + 8]
        mov rsi, r12
        mov rdx, [rsp]
        call st_cb_add
6:      cmp dword ptr [r14 + N_AUX], 3
        jb .Lcv_index
        mov rdi, [r14 + N_DATA + 16]
        mov rsi, r12
        mov rdx, [rsp]
        call st_cb_visit
        jmp 1b
9:      add rsp, 16
        LEAVE
.Lcv_index:
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_tindex]
        call err_throw
ENDF st_cb_visit

# st_cb_add(cond, od, flags): cond must hold for the execution to go on
FUNC st_cb_add
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 16
        .set CA_OD, MATCH_BINDINGS_SIZE
        .set CA_FLAGS, MATCH_BINDINGS_SIZE + 8
        mov rbx, rdi
        mov [rsp + CA_OD], rsi
        mov [rsp + CA_FLAGS], rdx
1:      PAT rsi, "('iszero', ('iszero', ':c'))"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 2f
        mov rbx, [rsp]
        jmp 1b
2:      # (pattern, delta): x < n, x <= n - 1...
        test qword ptr [rsp + CA_FLAGS], CB_ANY
        jnz 3f
        PAT rsi, "('lt', ':x', ':int:n')"
        xor r12d, r12d
        call .Lca_try
        PAT rsi, "('gt', ':int:n', ':x')"
        xor r12d, r12d
        call .Lca_try_nx
        PAT rsi, "('le', ':x', ':int:n')"
        mov r12d, 1
        call .Lca_try
        PAT rsi, "('ge', ':int:n', ':x')"
        mov r12d, 1
        call .Lca_try_nx
        PAT rsi, "('iszero', ('ge', ':x', ':int:n'))"
        xor r12d, r12d
        call .Lca_try
        PAT rsi, "('iszero', ('le', ':int:n', ':x'))"
        xor r12d, r12d
        call .Lca_try_nx
        PAT rsi, "('iszero', ('gt', ':x', ':int:n'))"
        mov r12d, 1
        call .Lca_try
        PAT rsi, "('iszero', ('lt', ':int:n', ':x'))"
        mov r12d, 1
        call .Lca_try_nx
        add rsp, MATCH_BINDINGS_SIZE + 16
        LEAVE
3:      # (whatever n is)
        PAT rsi, "('lt', ':x', ':n')"
        call .Lca_try
        PAT rsi, "('gt', ':n', ':x')"
        call .Lca_try_nx
        PAT rsi, "('le', ':x', ':n')"
        call .Lca_try
        PAT rsi, "('ge', ':n', ':x')"
        call .Lca_try_nx
        PAT rsi, "('iszero', ('ge', ':x', ':n'))"
        call .Lca_try
        PAT rsi, "('iszero', ('le', ':n', ':x'))"
        call .Lca_try_nx
        PAT rsi, "('iszero', ('gt', ':x', ':n'))"
        call .Lca_try
        PAT rsi, "('iszero', ('lt', ':n', ':x'))"
        call .Lca_try_nx
        add rsp, MATCH_BINDINGS_SIZE + 16
        LEAVE
# a pattern binding x then n (.Lca_try) or n then x (.Lca_try_nx), rsi;
# r12: the delta
.Lca_try:
        mov r13d, 0                     # the slot of x
        jmp 1f
.Lca_try_nx:
        mov r13d, 1
1:      sub rsp, 8
        mov rdi, rbx
        lea rdx, [rsp + 16]
        call pat_match
        test eax, eax
        jz 9f
        mov r14, [rsp + 16 + r13*8]     # x
        xor r13d, 1
        mov rax, [rsp + 16 + r13*8]     # n
        mov [rsp], rax
        mov rdi, r14
        call is_int
        test eax, eax
        jnz 9f
        test qword ptr [rsp + 16 + CA_FLAGS], CB_ANY
        jz 3f
        mov rdi, [rsp + 16 + CA_OD]     # res[x] = None
        mov rsi, r14
        lea rdx, [rip + sp_none]
        call od_put
        jmp 9f
3:      mov rdi, [rsp]                  # 0 < n + delta < 2**32
        mov rsi, r12
        TAG rsi
        call int_add
        mov [rsp], rax
        mov rdi, rax
        mov esi, 1
        mov rdx, (1 << 33) | 1
        call st_int_in
        test eax, eax
        jz 9f
        cmp qword ptr [rsp], 1
        je 9f
        mov rax, [rsp + 16 + CA_OD]
        mov rdi, rax
        mov rsi, r14
        call od_get                     # min(res.get(x, v), v)
        test rax, rax
        jz 2f
        mov rdi, rax
        mov rsi, [rsp]
        call int_min
        mov [rsp], rax
2:      mov rdi, [rsp + 16 + CA_OD]
        mov rsi, r14
        mov rdx, [rsp]
        call od_put
9:      add rsp, 8
        ret
ENDF st_cb_add

# st_var_values(trace) -> od: python's var_values - name -> the values (a
# vec) a variable is set to in a trace: by setvars, at the start of a
# loop, by its steps
FUNC st_var_values
        ENTER
        mov rbx, rdi
        call od_new
        mov r12, rax
        mov rdi, rbx
        mov rsi, r12
        call st_vv_visit
        mov rax, r12
        LEAVE
ENDF st_var_values

# st_vv_visit(lines, od)
FUNC st_vv_visit
        STACK_CHECK
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        call is_seq
        test eax, eax
        jz 9f
        xor r13d, r13d
1:      cmp r13d, [rbx + N_AUX]
        jae 9f
        mov r14, [rbx + N_DATA + r13*8]
        inc r13d
        mov rdi, r14
        call opcode_of
        cmp eax, OP_SETVAR
        je 2f
        cmp eax, OP_IF
        je 3f
        cmp eax, OP_WHILE
        je 5f
        cmp eax, OP_CONTINUE
        je 6f
        jmp 1b
2:      cmp dword ptr [r14 + N_AUX], 3  # res[name] += [value]
        jne 1b
        mov rdi, r12
        mov rsi, [r14 + N_DATA + 8]
        call st_od_group
        mov rdi, rax
        mov rsi, [r14 + N_DATA + 16]
        call vec_push
        jmp 1b
3:      mov qword ptr [rsp], 2          # the branches of an if
4:      mov rcx, [rsp]
        cmp ecx, [r14 + N_AUX]
        jae 1b
        mov rdi, [r14 + N_DATA + rcx*8]
        inc qword ptr [rsp]
        mov rsi, r12
        call st_vv_visit
        jmp 4b
5:      cmp dword ptr [r14 + N_AUX], 5  # the body of a loop, its start
        jb .Lvv_index
        mov rdi, [r14 + N_DATA + 16]
        mov rsi, r12
        call st_vv_visit
        mov rdi, [r14 + N_DATA + 32]
        mov rsi, r12
        call st_vv_visit
        jmp 1b
6:      cmp dword ptr [r14 + N_AUX], 3  # the steps of a continue
        jb .Lvv_index
        mov rdi, [r14 + N_DATA + 16]
        mov rsi, r12
        call st_vv_visit
        jmp 1b
9:      add rsp, 16
        LEAVE
.Lvv_index:
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_tindex]
        call err_throw
ENDF st_vv_visit

# st_points(v) -> eax: python's points - v may be a slot a storage pointer
# holds: a hash, a number that big (not within 2**32 of 0), a word of the
# memory (where solidity keeps them) - in it
FUNC st_points
        STACK_CHECK
        ENTER
        mov rbx, rdi
        call is_int
        test eax, eax
        jz 1f
        mov rdi, rbx
        mov rsi, (-(1 << 32) + 1) * 2 + 1
        mov rdx, (1 << 33) | 1
        call st_int_in
        xor eax, 1
        LEAVE
1:      mov rdi, rbx
        call is_seq
        test eax, eax
        jz 8f
        mov rdi, rbx
        call opcode_of
        cmp eax, OP_SHA3
        je 7f
        cmp eax, OP_MEM
        je 7f
        xor r12d, r12d
2:      cmp r12d, [rbx + N_AUX]
        jae 8f
        mov rdi, [rbx + N_DATA + r12*8]
        inc r12d
        call st_points
        test eax, eax
        jz 2b
7:      mov eax, 1
        LEAVE
8:      xor eax, eax
        LEAVE
ENDF st_points

# st_index_like(e, bounded, values, seen) -> eax: python's index_like -
# whether e is an index, of a fixed array its element at the slot plus e:
# made of numbers, of what the code checks is below something (a param, a
# loop's counter), of variables set to such (from 0 on), of numbers of a
# few bits (a uint16) or remainders. Not a pointer to the storage (a hash,
# a slot read from the memory, a param it doesn't check): the slot it
# points to plus a member's offset is no element of an array at that
# offset. bounded: an od of what the code checks is below something (see
# st_checked_below); values: the values of the variables (st_var_values);
# seen: a vec of the names of the variables looked into (their steps, from
# themselves)
FUNC st_index_like
        STACK_CHECK
        ENTER
        sub rsp, 32
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov [rsp], rcx                  # seen
        call is_int
        test eax, eax
        jz 1f
        mov rdi, rbx                    # -(2**32) < e < 2**32
        mov rsi, (-(1 << 32) + 1) * 2 + 1
        mov rdx, (1 << 33) | 1
        call st_int_in
        jmp .Lil_ret
1:      mov rdi, rbx
        call opcode_of
        mov r14d, eax
        cmp eax, OP_VAR
        jne 5f
        cmp dword ptr [rbx + N_AUX], 2
        jb .Lil_index
        mov rax, [rbx + N_DATA + 8]     # its name
        mov [rsp + 8], rax
        mov rdi, [rsp]                  # (its step, from itself: s + 1)
        mov rsi, rax
        call .Lil_in_vec
        test eax, eax
        jnz .Lil_yes
        mov rdi, r13                    # vs = values.get(name, [])
        mov rsi, [rsp + 8]
        call od_get
        mov [rsp + 16], rax             # (0: none)
        test rax, rax
        jz 3f
        xor r14d, r14d                  # (a pointer, below the end of what
2:      mov rax, [rsp + 16]             # it points to, say)
        cmp r14, [rax + VEC_LEN]
        jae 3f
        mov rax, [rax + VEC_DATA]
        mov rdi, [rax + r14*8]
        inc r14
        call st_points
        test eax, eax
        jnz .Lil_no
        jmp 2b
3:      mov rdi, r12                    # checked below something
        mov rsi, rbx
        call od_get
        test rax, rax
        jnz .Lil_yes
        mov rax, [rsp + 16]             # all of its values (some)
        test rax, rax
        jz .Lil_no
        cmp qword ptr [rax + VEC_LEN], 0
        je .Lil_no
        call vec_new                    # seen + (name,)
        mov [rsp + 24], rax
        mov rdi, rax
        mov rsi, [rsp]
        mov rdx, [rsi + VEC_LEN]
        mov rsi, [rsi + VEC_DATA]
        call vec_extend
        mov rdi, [rsp + 24]
        mov rsi, [rsp + 8]
        call vec_push
        xor r14d, r14d
4:      mov rax, [rsp + 16]
        cmp r14, [rax + VEC_LEN]
        jae .Lil_yes
        mov rax, [rax + VEC_DATA]
        mov rdi, [rax + r14*8]
        inc r14
        mov rsi, r12
        mov rdx, r13
        mov rcx, [rsp + 24]
        call st_index_like
        test eax, eax
        jz .Lil_no
        jmp 4b
5:      mov rdi, r12                    # checked below something
        mov rsi, rbx
        call od_get
        test rax, rax
        jnz .Lil_yes
        cmp r14d, OP_ADD                # sums, products, quotients of them
        je 6f
        cmp r14d, OP_MUL
        je 6f
        cmp r14d, OP_DIV
        je 6f
        cmp r14d, OP_MOD                # (a remainder: below what it's
        je .Lil_yes                     # taken of)
        cmp r14d, OP_MASK_SHL
        jne .Lil_no
        mov r14d, 1                     # (a mask's size, offset, shift
51:     cmp r14d, 4                     # numbers)
        jae 52f
        cmp r14d, [rbx + N_AUX]
        jae 52f
        mov rdi, [rbx + N_DATA + r14*8]
        inc r14d
        call is_int
        test eax, eax
        jz .Lil_no
        jmp 51b
52:     cmp dword ptr [rbx + N_AUX], 2  # of a few bits, or of an index
        jb .Lil_index
        mov rdi, [rbx + N_DATA + 8]
        mov esi, (64 << 1) | 1
        call int_cmp
        cmp eax, 0
        jle .Lil_yes
        cmp dword ptr [rbx + N_AUX], 5
        jb .Lil_index
        mov rdi, [rbx + N_DATA + 32]
        mov rsi, r12
        mov rdx, r13
        mov rcx, [rsp]
        call st_index_like
        jmp .Lil_ret
6:      mov r14d, 1
7:      cmp r14d, [rbx + N_AUX]
        jae .Lil_yes
        mov rdi, [rbx + N_DATA + r14*8]
        inc r14d
        mov rsi, r12
        mov rdx, r13
        mov rcx, [rsp]
        call st_index_like
        test eax, eax
        jz .Lil_no
        jmp 7b
.Lil_yes:
        mov eax, 1
        jmp .Lil_ret
.Lil_no:
        xor eax, eax
.Lil_ret:
        add rsp, 32
        LEAVE
.Lil_index:
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_tindex]
        call err_throw
# local: eax 1 when the value rsi is in the vec rdi (python's ==)
.Lil_in_vec:
        push rbx
        push r12
        push r13
        mov rbx, rdi
        mov r12, rsi
        xor r13d, r13d
1:      cmp r13, [rbx + VEC_LEN]
        jae 2f
        mov rax, [rbx + VEC_DATA]
        mov rdi, [rax + r13*8]
        inc r13
        mov rsi, r12
        call py_equal
        test eax, eax
        jz 1b
        mov eax, 1
        jmp 3f
2:      xor eax, eax
3:      pop r13
        pop r12
        pop rbx
        ret
ENDF st_index_like

# st_narrow(exp, arg) -> value: python's narrow - a read of the storage as
# wide as what's used of it
FUNC st_narrow
        OPCODE_OF_RDI                   # (('mask_shl', ...) only)
        cmp eax, OP_MASK_SHL
        je 1f
        mov rax, rdi
        ret
1:      ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 16
        mov rbx, rdi
        PAT rsi, "('mask_shl', ':int:size', ':int:moff', ':shl', ('storage', ':int:s_size', ':int:s_off', ':idx'))"
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz .Lnw_asis
        # 0 < size, 0 <= moff, moff + size <= s_size, (size, moff) !=
        # (s_size, 0)
        mov rdi, [rsp]
        call int_sign
        cmp eax, 1
        jne .Lnw_asis
        mov rdi, [rsp + 8]
        call int_sign
        test eax, eax
        js .Lnw_asis
        mov rdi, [rsp + 8]
        mov rsi, [rsp]
        call int_add
        mov rdi, rax
        mov rsi, [rsp + 24]
        call int_cmp
        cmp eax, 1
        je .Lnw_asis
        mov rax, [rsp]
        cmp rax, [rsp + 24]
        jne 1f
        cmp qword ptr [rsp + 8], 1
        je .Lnw_asis
1:      # not a word times 2**shl (32 * x): the bits it loses on top are no
        # field of it
        cmp qword ptr [rsp + 24], (256 << 1) | 1
        jne 2f
        cmp qword ptr [rsp + 32], 1
        jne 2f
        cmp qword ptr [rsp + 8], 1
        jne 2f
        mov edi, (256 << 1) | 1         # shl == 256 - size
        mov rsi, [rsp]
        call int_sub
        mov rdi, [rsp + 16]
        mov rsi, rax
        call py_equal
        test eax, eax
        jz 2f
        mov rdi, [rsp]                  # and size % 8
        mov esi, 3
        call int_mod_2exp
        cmp rax, 1
        jne .Lnw_asis
2:      mov r12, [rsp + 16]             # shl + moff
        cmp qword ptr [rsp + 8], 1
        je 3f
        mov rdi, r12
        mov rsi, [rsp + 8]
        call alg_add2
        mov r12, rax
3:      mov rdi, [rsp + 32]             # ('storage', size, s_off + moff, idx)
        mov rsi, [rsp + 8]
        call int_add
        mov rdx, rax
        LOADS rdi, STORAGE
        mov rsi, [rsp]
        mov rcx, [rsp + 40]
        call mk4
        mov r8, rax
        LOADS rdi, MASK_SHL
        mov rsi, [rsp]
        mov edx, 1
        mov rcx, r12
        call mk5
        add rsp, MATCH_BINDINGS_SIZE + 16
        LEAVE
.Lnw_asis:
        mov rax, rbx
        add rsp, MATCH_BINDINGS_SIZE + 16
        LEAVE
ENDF st_narrow

# @@PART5@@

        .section .note.GNU-stack,"",@progbits
