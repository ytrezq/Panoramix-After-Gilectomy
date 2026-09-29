# Storage (port of sparser.py): the storage references of all the
# functions turned into locations, arrays and maps, named after the
# getters, and the storage definitions of the contract.
#
# rewrite_functions(functions) -> list of ('def', name, loc, type) and
# the functions' traces rewritten with 'stor' references.

.include "defs.inc"

        .section .rodata
.Ls_logname:    .asciz "panoramix.sparser"
.Ls_weird_idx:  .asciz "Weird storage index, %v"
.Ls_not_found:  .asciz "storage pattern not found"
.Ls_assert_stor: .asciz "sparser: not a stor"
.Ls_assert_getter: .asciz "sparser: a getter that isn't a storage"
.Ls_assert_storage_left: .asciz "sparser: a storage left in a definition"
.Ls_assert_def: .asciz "sparser: not a def"
.Ls_key_error:  .asciz "sparser: a storage without a definition"
.Ls_get:        .asciz "get"
.Ls_Address:    .asciz "Address"
.Ls_address:    .asciz "address"
.Ls_addr:       .asciz "addr"
.Ls_account:    .asciz "account"
.Ls_owner:      .asciz "owner"
.Ls_stor:       .asciz "stor"
.Ls_struct:     .asciz "struct"

        # the sha3 of the small locations and of (0/1, location), as
        # hex text (rainbow_sha3): loc 0..19, then (map 0 loc), (map 1 loc)
.Lsha3_keys:
        .asciz "0x290decd9548b62a8d60345a988386fc84ba6bc95484008f6362f93160ef3e563"
        .asciz "0xb10e2d527612073b26eecdfd717e6a320cf44b4afac2b0732d9fcbe2b7fa0cf6"
        .asciz "0x405787fa12a823e0f2b7631cc41b3ba8828b3321ca811111fa75cd3aa3bb5ace"
        .asciz "0xc2575a0e9e593c00f959f8c92f12db2869c3395a3b0502d05e2516446f71f85b"
        .asciz "0x8a35acfbc15ff81a39ae7d344fd709f28e8600b4aa8c65c6b64bfe7fe36bd19b"
        .asciz "0x036b6384b5eca791c62761152d0c79bb0604c104a5fb6f4eb0703f3154bb3db0"
        .asciz "0xf652222313e28459528d920b65115c16c04f3efc82aaedc97be59f3f377c0d3f"
        .asciz "0xa66cc928b5edb82af9bd49922954155ab7b0942694bea4ce44661d9a8736c688"
        .asciz "0xf3f7a9fe364faab93b216da50a3214154f22a0a2b415b23a84c8169e8b636ee3"
        .asciz "0x6e1540171b6c0c960b71a7020d9f60077f6af931a8bbf590da0223dacf75c7af"
        .asciz "0xc65a7bb8d6351c1cf70c95a316cc6a92839c986682d98bc35f958f4883f9d2a8"
        .asciz "0x0175b7a638427703f0dbe7bb9bbf987a2551717b34e79f33b5b1008d1fa01db9"
        .asciz "0xdf6966c971051c3d54ec59162606531493a51404a002842f56009d7e5cf4a8c7"
        .asciz "0xd7b6990105719101dabeb77144f2a3385c8033acd3af97e9423a695e81ad1eb5"
        .asciz "0xbb7b4a454dc3493923482f07822329ed19e8244eff582cc204f8554c3620c3fd"
        .asciz "0x8d1108e10bcb7c27dddfc02ed9d693a074039d026cf4ea4240b40f7d581ac802"
        .asciz "0x1b6847dc741a1b0cd08d278845f9d819d87b734759afb55fe2de5cb82a9ae672"
        .asciz "0x31ecc21a745e3968a04e9570e4425bc18fa8019c68028196b546d1669c200c68"
        .asciz "0xbb8a6a4669ba250d26cd7a459eca9d215f8307e33aebe50379bc5a3617ec3444"
        .asciz "0x66de8ffda797e3de9c05e8fc57b3bf0ec28a930d40b0d285d93c06501cf6a090"
        .asciz "0xad3228b676f7d3cd4284a5443f17f1962b36e491b30a40b2405849e597ba5fb5"
        .asciz "0xa6eef7e35abe7026729641147f7915573c7e97b47efa546f5f6e3230263bcb49"
        .asciz "0xac33ff75c19e70fe83507db0d683fd3465c996598dc972688b7ace676c89077b"
        .asciz "0x3617319a054d772f909f7c479a2cebe5066e836a939412e32403c99029b92eff"
        .asciz "0x17ef568e3e12ab5b9c7254a8d58478811de00f9e6eb34345acd53bf8fd09d3ec"
        .asciz "0x05b8ccbb9d4d8fb16ea74ce3c29a41f1b461fbdaff4714a0d9a8eb05499746bc"
        .asciz "0x54cdd369e4e8a8515e52ca72ec816c2101831ad1f18bf44102ed171459c9b4f8"
        .asciz "0x6d5257204ebe7d88fd91ae87941cb2dd9d8062b64ae5a2bd2d28ec40b9fbf6df"
        .asciz "0x5eff886ea0ce6ca488a3d6e336d6c0f75f46d19b42c06ce5ee98e42c96d256c7"
        .asciz "0xec8156718a8372b1db44bb411437d0870f3e3790d4a08526d024ce1b0b668f6b"
        .asciz "0x13da86008ba1c6922daee3e07db95305ef49ebced9f5467a0b8613fcc6b343e3"
        .asciz "0xdf7de25b7f1fd6d0b5205f0e18f1f35bd7b8d84cce336588d184533ce43a6f76"
        .asciz "0x13649b2456f1b42fef0f0040b3aaeabcd21a76a0f3f5defd4f583839455116e8"
        .asciz "0x81955a0a11e65eac625c29e8882660bae4e165a75d72780094acae8ece9a29ee"
        .asciz "0xe710864318d4a32f37d6ce54cb3fadbef648dd12d8dbdf53973564d56b7f881c"
        .asciz "0xf4803e074bd026baaf6ed2e288c9515f68c72fb7216eebdd7cae1718a53ec375"
        .asciz "0x6e0956cda88cad152e89927e53611735b61a5c762d1428573c6931b0a5efcb01"
        .asciz "0x4ad3b33220dddc71b994a52d72c06b10862965f7d926534c05c00fb7e819e7b7"
        .asciz "0x7e7fa33969761a458e04f477e039a608702b4f924981d6653935a8319a08ad7b"
        .asciz "0x8fa6efc3be94b5b348b21fea823fe8d100408cee9b7f90524494500445d8ff6c"
        .asciz "0xada5013122d395ba3c54772283fb069b10426056ef8ca54750cb9bb552a59e7d"
        .asciz "0xcc69885fda6bcc1a4ace058b4a62bf5e179ea78fd58a1ccd71c22cc9b688792f"
        .asciz "0xe90b7bceb6e7df5418fb78d8ee546e97c83a08bbccc01a0644d599ccd2a7c2e0"
        .asciz "0xa15bc60c955c405d20d9149c709e2460f1c2d9a497496a7f46004d1772c3054c"
        .asciz "0xabd6e7cb50984ff9c2f3e18a2660c3353dadf4e3291deeb275dae2cd1e44fe05"
        .asciz "0x1471eb6eb2c5e789fc3de43f8ce62938c7d1836ec861730447e2ada8fd81017b"
        .asciz "0x3e5fec24aa4dc4e5aee2e025e51e1392c72a2500577559fae9665c6d52bd6a31"
        .asciz "0xb39221ace053465ec3453ce2b36430bd138b997ecea25c1043da0c366812b828"
        .asciz "0xad67d757c34507f157cacfa2e3153e9f260a2244f30428821be7be64587ac55f"
        .asciz "0x92e85d02570a8092d09a6e3a57665bc3815a2699a4074001bf1ccabf660f5a36"
        .asciz "0xbbc70db1b6c7afd11e79c0fb0051300458f1a3acb8ee9789d9b6b26c61ad9bc7"
        .asciz "0x72c6bfb7988af3a1efa6568f02a999bc52252641c659d85961ca3d372b57d5cf"
        .asciz "0xd421a5181c571bba3f01190c922c3b2a896fc1d84e86c9f17ac10e67ebef8b5c"
        .asciz "0xfd54ff1ed53f34a900b24c5ba64f85761163b5d82d98a47b9bd80e45466993c5"
        .asciz "0xa7c5ba7114a813b50159add3a36832908dc83db71d0b9a24c2ad0f83be958207"
        .asciz "0x169f97de0d9a84d840042b17d3c6b9638b3d6fd9024c9eb0c7a306a17b49f88f"
        .asciz "0x8c6065603763fec3f5742441d3833f3f43b982453612d76adb39a885e3006b5f"
        .asciz "0x17bc176d2408558f6e4111feebc3cab4e16b63e967be91cde721f4c8a488b552"
        .asciz "0x71a67924699a20698523213e55fe499d539379d7769cd5567e2c45d583f815a3"
        .asciz "0x4155c2f711f2cdd34f8262ab8fb9b7020a700fe7b6948222152f7670d1fdf34d"
        .set SHA3_KEY_LEN, 67           # with the NUL
        .set SHA3_KEYS, 60

        .text

.macro B reg, n
        mov \reg, [rsp + 8*(\n)]
.endm

# --- helpers ---

# stor_inner(exp) -> value: the index expression of a storage reference,
# as get_loc and get_name see it (the successive unwrappings of python)
FUNC stor_inner
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE
        mov rbx, rdi
        PAT rsi, "('type', 'Any', ('field', 'Any', ':m_idx'))"
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 1f
        mov rbx, [rsp]
1:      PAT rsi, "('storage', 'Any', 'Any', ':e')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 2f
        mov rbx, [rsp]
2:      PAT rsi, "('stor', 'Any', 'Any', ':e')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 3f
        mov rbx, [rsp]
3:      PAT rsi, "('stor', ':e')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 4f
        mov rbx, [rsp]
4:      mov rax, rbx
        add rsp, MATCH_BINDINGS_SIZE
        LEAVE
ENDF stor_inner

# get_loc(exp) -> value or 0: the location number of a storage reference
FUNC get_loc
        ENTER
        call stor_inner
        mov rdi, rax
        call loc_of
        LEAVE
ENDF get_loc

# loc_of(exp) -> value or 0: the num of the first ('loc', num) or
# ('name', _, num) in a tuple, without entering storage references
FUNC loc_of
        STACK_CHECK
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE
        mov rbx, rdi
        call is_tuple
        test eax, eax
        jz .Llo_none
        mov rdi, rbx
        call opcode_of
        cmp eax, OP_STORAGE
        je .Llo_none
        cmp eax, OP_STOR
        je .Llo_none
        PAT rsi, "('loc', ':num')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jnz .Llo_found
        PAT rsi, "('name', 'Any', ':num')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jnz .Llo_found
        xor r12d, r12d
1:      cmp r12d, [rbx + N_AUX]
        jae .Llo_none
        mov rdi, [rbx + N_DATA + r12*8]
        call loc_of
        test rax, rax
        jnz 2f
        inc r12d
        jmp 1b
.Llo_found:
        mov rax, [rsp]
2:      add rsp, MATCH_BINDINGS_SIZE
        LEAVE
.Llo_none:
        xor eax, eax
        add rsp, MATCH_BINDINGS_SIZE
        LEAVE
ENDF loc_of

# get_name(exp) -> str or 0: the name of a named storage reference
FUNC get_name
        ENTER
        call stor_inner
        mov rdi, rax
        call name_of
        test rax, rax
        jz 1f
        mov rax, [rax + N_DATA + 8]
1:      LEAVE
ENDF get_name

# name_of(exp) -> ('name', name, _) or 0, like loc_of
FUNC name_of
        STACK_CHECK
        ENTER
        mov rbx, rdi
        call is_tuple
        test eax, eax
        jz .Lno_none
        mov rdi, rbx
        call opcode_of
        cmp eax, OP_STORAGE
        je .Lno_none
        cmp eax, OP_STOR
        je .Lno_none
        PAT rsi, "('name', ':name', 'Any')"
        mov rdi, rbx
        call pat_match_nobind
        test eax, eax
        jz 1f
        mov rax, rbx
        LEAVE
1:      xor r12d, r12d
2:      cmp r12d, [rbx + N_AUX]
        jae .Lno_none
        mov rdi, [rbx + N_DATA + r12*8]
        call name_of
        test rax, rax
        jnz 3f
        inc r12d
        jmp 2b
3:      LEAVE
.Lno_none:
        xor eax, eax
        LEAVE
ENDF name_of

# find_stores(exp, out): the storage references (as ('storage', size,
# off, idx)) of the stores and reads in exp, each once (a set: out is a
# vec without duplicates)
FUNC find_stores
        STACK_CHECK
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE
        mov rbx, rdi
        mov r12, rsi
        PATXD "('store', ':size', ':off', ':idx', ':val')"
        test eax, eax
        jz 1f
        B rsi, 0
        B rdx, 1
        B rcx, 2
        LOADS rdi, STORAGE
        call mk4
        mov rdi, r12
        mov rsi, rax
        call set_add
        jmp 2f
1:      mov rdi, rbx
        call opcode_of
        cmp eax, OP_STORAGE
        jne 2f
        mov rdi, r12
        mov rsi, rbx
        call set_add
2:      mov rdi, rbx
        call is_seq
        test eax, eax
        jz 4f
        xor r13d, r13d
3:      cmp r13d, [rbx + N_AUX]
        jae 4f
        mov rdi, [rbx + N_DATA + r13*8]
        mov rsi, r12
        call find_stores
        inc r13d
        jmp 3b
4:      add rsp, MATCH_BINDINGS_SIZE
        LEAVE
ENDF find_stores

# --- the sparser proper ---

# rainbow_sha3(v) -> value: an integer that starts like the sha3 of a
# small location (or of a 0/1 key in one) becomes ('loc', n) or ('map',
# 0/1, ('loc', n))
FUNC rainbow_sha3
        ENTER
        mov rbx, rdi
        call is_int
        test eax, eax
        jz .Lrs_asis
        call sb_new
        mov r12, rax
        mov rdi, rax
        mov rsi, rbx
        mov edx, 16
        call sb_append_int
        cmp qword ptr [r12 + SB_LEN], 40
        jbe .Lrs_free
        lea r13, [rip + .Lsha3_keys]
        xor r14d, r14d
1:      cmp r14d, SHA3_KEYS
        jae .Lrs_free
        mov rdi, r13
        mov rsi, [r12 + SB_BUF]
        call strstr@PLT
        test rax, rax
        jnz 2f
        add r13, SHA3_KEY_LEN
        inc r14d
        jmp 1b
2:      mov rdi, r12
        call sb_free
        # key i: loc i (i < 20), (map 0 loc i-20), (map 1 loc i-40)
        mov eax, r14d
        xor edx, edx
        mov ecx, 20
        div ecx                         # eax = 0/1/2, edx = the loc
        mov r13d, eax
        mov rsi, rdx
        TAG rsi
        LOADS rdi, LOC
        call mk2
        test r13d, r13d
        jz 3f
        mov rdx, rax
        lea rsi, [r13 - 1]
        TAG rsi
        LOADS rdi, MAP
        call mk3
3:      LEAVE
.Lrs_free:
        mov rdi, r12
        call sb_free
.Lrs_asis:
        mov rax, rbx
        LEAVE
ENDF rainbow_sha3

# simplify_sha3(e, arg) -> value
FUNC simplify_sha3
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE
        call rainbow_sha3
        mov rbx, rax
        # ('sha3', ('data', ...)) -> ('sha3',) + terms
        PAT rsi, "('sha3', ('data', '...'))"
        mov rdi, rbx
        call pat_match_nobind
        test eax, eax
        jz 1f
        mov rdi, [rbx + N_DATA + 8]
        mov esi, 1
        call list_from
        mov rdi, rax
        LOADS rsi, SHA3
        call list_prepend
        mov rdi, rax
        call seq_to_tuple
        mov rbx, rax
1:      PAT rsi, "('sha3', ':int:loc')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 2f
        B rsi, 0
        LOADS rdi, LOC
        call mk2
        jmp .Lss_ret
2:      PAT rsi, "('sha3', ('sha3', '...'), ':int:loc')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 3f
        # ('map', ('data', *e[1][1:]), ('loc', loc))
        B rsi, 0
        LOADS rdi, LOC
        call mk2
        mov r12, rax
        mov rdi, [rbx + N_DATA + 8]
        mov esi, 1
        call list_from
        mov rdi, rax
        LOADS rsi, DATA
        call list_prepend
        mov rdi, rax
        call seq_to_tuple
        mov rsi, rax
        mov rdx, r12
        LOADS rdi, MAP
        call mk3
        jmp .Lss_ret
3:      PAT rsi, "('sha3', ':idx', ':int:loc')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 4f
        B rsi, 1
        LOADS rdi, LOC
        call mk2
        mov rdx, rax
        B rsi, 0
        LOADS rdi, MAP
        call mk3
        jmp .Lss_ret
4:      mov rax, rbx
.Lss_ret:
        add rsp, MATCH_BINDINGS_SIZE
        LEAVE
ENDF simplify_sha3

# stor_internal_f(exp, f) -> value: f applied bottom-up to the tuples,
# without entering storage references
FUNC stor_internal_f
        STACK_CHECK
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        call opcode_of
        cmp eax, OP_STORAGE
        je 3f
        mov rdi, rbx
        call is_tuple
        test eax, eax
        jz 4f
        mov edi, [rbx + N_AUX]
        shl rdi, 3
        call arena_alloc
        mov [rsp], rax
        xor r13d, r13d
1:      cmp r13d, [rbx + N_AUX]
        jae 2f
        mov rdi, [rbx + N_DATA + r13*8]
        mov rsi, r12
        call stor_internal_f
        mov rcx, [rsp]
        mov [rcx + r13*8], rax
        inc r13d
        jmp 1b
2:      mov edi, [rbx + N_AUX]
        mov rsi, [rsp]
        call mk_tuple
        mov rbx, rax
4:      mov rdi, rbx
        xor esi, esi
        call r12
        add rsp, 16
        LEAVE
3:      mov rax, rbx
        add rsp, 16
        LEAVE
ENDF stor_internal_f

# stor_replace_f(stors, f): every ('stor', size, off, idx) of the vec
# gets its idx through stor_internal_f, in place
FUNC stor_replace_f
        ENTER
        mov rbx, rdi
        mov r12, rsi
        xor r13d, r13d
1:      cmp r13, [rbx + VEC_LEN]
        jae 2f
        mov rax, [rbx + VEC_DATA]
        mov r14, [rax + r13*8]
        mov rdi, r14
        call assert_stor
        mov rdi, [r14 + N_DATA + 24]
        mov rsi, r12
        call stor_internal_f
        mov rcx, rax
        mov rsi, [r14 + N_DATA + 8]
        mov rdx, [r14 + N_DATA + 16]
        LOADS rdi, STOR
        call mk4
        mov rcx, [rbx + VEC_DATA]
        mov [rcx + r13*8], rax
        inc r13
        jmp 1b
2:      LEAVE
ENDF stor_replace_f

# assert_stor(v): a 4-element ('stor', ...)
FUNC assert_stor
        ENTER
        mov rbx, rdi
        call opcode_of
        cmp eax, OP_STOR
        jne 1f
        cmp dword ptr [rbx + N_AUX], 4
        jne 1f
        LEAVE
1:      mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_stor]
        call err_throw
ENDF assert_stor

# mask_to_mul(exp, arg) -> value: a mask that multiplies or divides by
# a small power of two
FUNC mask_to_mul
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 16
        mov rbx, rdi
        PAT rsi, "('mask_shl', ':int:size', ':int:offset', ':int:shl', ':val')"
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz .Lmm_asis
        # shl > 0 and offset == 0 and size == 256 - shl, shl <= 8: mul 2^shl
        B rdi, 2
        call int_sign
        cmp eax, 1
        jne 1f
        cmp qword ptr [rsp + 8], 1
        jne 1f
        # size == 256 - shl  <=>  size + shl == 256
        B rdi, 0
        B rsi, 2
        call int_add
        cmp rax, 513
        jne 1f
        B rdi, 2
        mov rsi, 8
        TAG rsi
        call int_cmp
        cmp eax, 1
        je 1f
        B rdi, 2
        call int_to_i64
        mov rdi, rax
        call pow2
        mov rsi, rax
        B rdx, 3
        LOADS rdi, MUL
        call mk3
        jmp .Lmm_ret
1:      # shl < 0 and offset == -shl and size == 256 - offset, shl >= -8:
        # ('div', 2 ** shl, val) - a float in python
        B rdi, 2
        call int_sign
        cmp eax, -1
        jne .Lmm_asis
        B rdi, 2
        call int_neg
        cmp rax, [rsp + 8]
        jne .Lmm_asis
        B rdi, 0
        B rsi, 1
        call int_add
        cmp rax, 513
        jne .Lmm_asis
        B rdi, 2
        mov rsi, -8
        TAG rsi
        call int_cmp
        cmp eax, -1
        je .Lmm_asis
        B rdi, 2
        call int_to_i64
        mov rdi, rax
        call pow2_or_float
        mov rsi, rax
        B rdx, 3
        LOADS rdi, DIV
        call mk3
        jmp .Lmm_ret
.Lmm_asis:
        mov rax, rbx
.Lmm_ret:
        add rsp, MATCH_BINDINGS_SIZE + 16
        LEAVE
ENDF mask_to_mul

# add_to_arr(exp, arg): ('add', x, ('loc', n)) (either way round) ->
# ('array', x, ('loc', n))
FUNC add_to_arr
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE
        mov rbx, rdi
        PAT rsi, "('add', ':left', ':right')"
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 2f
        B rdi, 0
        call opcode_of
        cmp eax, OP_LOC
        jne 1f
        mov rax, [rsp]
        mov rcx, [rsp + 8]
        mov [rsp], rcx
        mov [rsp + 8], rax
1:      B rdi, 1
        call opcode_of
        cmp eax, OP_LOC
        jne 2f
        B rsi, 0
        B rdx, 1
        LOADS rdi, ARRAY
        call mk3
        add rsp, MATCH_BINDINGS_SIZE
        LEAVE
2:      mov rax, rbx
        add rsp, MATCH_BINDINGS_SIZE
        LEAVE
ENDF add_to_arr

# double_map(exp, arg): the nested maps and arrays
FUNC double_map
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 16
        mov rbx, rdi
        PAT rsi, "('add', ':exp')"
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 1f
        mov rbx, [rsp]                  # a single-term add unwrapped
1:      PAT rsi, "('sha3', ('map', '...'))"
        mov rdi, rbx
        call pat_match_nobind
        test eax, eax
        jz 2f
        # ('map', *terms)
        mov rdi, [rbx + N_DATA + 8]
        mov esi, 1
        call list_from
        mov rdi, rax
        LOADS rsi, MAP
        call list_prepend
        mov rdi, rax
        call seq_to_tuple
        jmp .Ldm_ret
2:      PAT rsi, "('sha3', ':idx', ('map', '...'))"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 3f
        # ('map', idx, ('map', *terms))
        mov rdi, [rbx + N_DATA + 16]
        mov esi, 1
        call list_from
        mov rdi, rax
        LOADS rsi, MAP
        call list_prepend
        mov rdi, rax
        call seq_to_tuple
        mov rdx, rax
        B rsi, 0
        LOADS rdi, MAP
        call mk3
        jmp .Ldm_ret
3:      PAT rsi, "('add', ':idx', ('map', '...'))"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 4f
        # ('array', idx, ('map', *terms))
        mov rdi, [rbx + N_DATA + 16]
        mov esi, 1
        call list_from
        mov rdi, rax
        LOADS rsi, MAP
        call list_prepend
        mov rdi, rax
        call seq_to_tuple
        mov rdx, rax
        B rsi, 0
        LOADS rdi, ARRAY
        call mk3
        jmp .Ldm_ret
4:      PAT rsi, "('sha3', ':idx', ':loc')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 5f
        B rsi, 0
        B rdx, 1
        LOADS rdi, MAP
        call mk3
        jmp .Ldm_ret
5:      PAT rsi, "('add', ('sha3', ('array', '...')), ':num')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 6f
        mov rax, [rbx + N_DATA + 8]
        mov rdi, [rax + N_DATA + 8]     # the ('array', ...)
        B rsi, 0
        call .Ldm_array_of
        jmp .Ldm_ret
6:      PAT rsi, "('add', ':num', ('sha3', ('array', '...')))"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 7f
        mov rax, [rbx + N_DATA + 16]
        mov rdi, [rax + N_DATA + 8]
        B rsi, 0
        call .Ldm_array_of
        jmp .Ldm_ret
7:      PAT rsi, "('sha3', ('array', ':idx', ':loc'))"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 8f
        B rsi, 0
        B rdx, 1
        LOADS rdi, ARRAY
        call mk3
        jmp .Ldm_ret
8:      PAT rsi, "('add', ('map', '...'), ':num')"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 9f
        mov rdi, [rbx + N_DATA + 8]
        B rsi, 0
        call .Ldm_array_of
        jmp .Ldm_ret
9:      PAT rsi, "('add', ':num', ('map', '...'))"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 10f
        mov rdi, [rbx + N_DATA + 16]
        B rsi, 0
        call .Ldm_array_of
        jmp .Ldm_ret
10:     PAT rsi, "('add', ('var', ':x'), ('array', ':idx', ':loc'))"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 11f
        # ('array', ('add', idx, ('var', x)), loc)
        B rsi, 1
        B rdx, 0
        jmp 12f
11:     PAT rsi, "('add', ('array', ':idx', ':loc'), ('var', ':x'))"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz .Ldm_asis
        B rsi, 0
        B rdx, 2
        mov rax, [rsp + 8]
        mov [rsp + 16], rax             # loc kept for below (slot 2)
12:     # rsi = idx, rdx = x
        push rsi
        push rsi
        mov rsi, rdx
        LOADS rdi, VAR
        call mk2
        pop rsi
        pop rsi
        mov rdx, rax
        LOADS rdi, ADD
        call mk3
        mov rsi, rax
        mov rdx, [rsp + 16]             # loc (slot 2 in both cases)
        LOADS rdi, ARRAY
        call mk3
        jmp .Ldm_ret
.Ldm_asis:
        mov rax, rbx
.Ldm_ret:
        add rsp, MATCH_BINDINGS_SIZE + 16
        LEAVE
# ('array', num, (head,) + terms) for rdi = the (head, ...) sequence,
# rsi = num
.Ldm_array_of:
        sub rsp, 24
        mov [rsp], rsi
        mov rax, [rdi + N_DATA]
        mov [rsp + 8], rax              # the head
        mov esi, 1
        call list_from
        mov rdi, rax
        mov rsi, [rsp + 8]
        call list_prepend
        mov rdi, rax
        call seq_to_tuple
        mov rdx, rax
        mov rsi, [rsp]
        LOADS rdi, ARRAY
        call mk3
        add rsp, 24
        ret
ENDF double_map

# sparser(storages) -> od: every ('storage', ...) reference of the vec
# mapped to its ('stor', ...) form with locations, arrays and maps
FUNC sparser
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 64
        .set SP_ORIG, MATCH_BINDINGS_SIZE
        .set SP_STORS, MATCH_BINDINGS_SIZE + 8
        .set SP_I, MATCH_BINDINGS_SIZE + 16
        .set SP_TEXT, MATCH_BINDINGS_SIZE + 24
        .set SP_RES, MATCH_BINDINGS_SIZE + 32
        .set SP_T1, MATCH_BINDINGS_SIZE + 40
        mov [rsp + SP_ORIG], rdi
        mov rbx, rdi
        # ('stor',) + s[1:]
        call vec_new
        mov r12, rax
        mov [rsp + SP_STORS], rax
        xor r13d, r13d
1:      cmp r13, [rbx + VEC_LEN]
        jae 2f
        mov rax, [rbx + VEC_DATA]
        mov rdi, [rax + r13*8]
        LOADS rsi, STOR
        call replace_head
        mov rdi, r12
        mov rsi, rax
        call vec_push
        inc r13
        jmp 1b
2:      mov rdi, r12
        lea rsi, [rip + simplify_sha3]
        call stor_replace_f
        # is add a struct or a loc?
        xor r13d, r13d
3:      cmp r13, [r12 + VEC_LEN]
        jae 5f
        mov rax, [r12 + VEC_DATA]
        mov r14, [rax + r13*8]
        PAT rsi, "('stor', ':size', ('mask_shl', ':o_size', ':o_off', ':o_shl', ':arr_idx'), ':idx')"
        mov rdi, r14
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 4f
        # size == 2 ** o_shl (o_shl an int; a negative one gives a
        # float, never equal)
        B rdi, 3
        call is_int
        test eax, eax
        jz .Lsp_type_error
        B rdi, 3
        call int_sign
        cmp eax, -1
        je 4f
        B rdi, 3
        call int_to_i64
        mov rdi, rax
        call pow2
        mov rdi, rax
        B rsi, 0
        call py_equal
        test eax, eax
        jz 4f
        # idx = num of ('add', int num, Any)
        B rdi, 5
        PAT rsi, "('add', ':int:num', 'Any')"
        lea rdx, [rsp + 48]             # (a binding slot past the six used)
        call pat_match
        test eax, eax
        jz 31f
        mov rax, [rsp + 48]
        mov [rsp + 40], rax
31:     # ('stor', size, 0, ('array', ('mask_shl', o_size + o_shl, o_off, 0, arr_idx), ('loc', idx)))
        B rdi, 1
        B rsi, 3
        call int_add
        mov rsi, rax
        B rdx, 2
        mov ecx, 1
        B r8, 4
        LOADS rdi, MASK_SHL
        call mk5
        mov [rsp + SP_T1], rax
        B rsi, 5
        LOADS rdi, LOC
        call mk2
        mov rdx, rax
        mov rsi, [rsp + SP_T1]
        LOADS rdi, ARRAY
        call mk3
        mov rcx, rax
        B rsi, 0
        mov edx, 1
        LOADS rdi, STOR
        call mk4
        mov rcx, [r12 + VEC_DATA]
        mov [rcx + r13*8], rax
4:      inc r13
        jmp 3b
5:      mov rdi, r12
        lea rsi, [rip + mask_to_mul]
        call stor_replace_f
        # ('add', int num, *terms) with a loc among the terms: the num
        # goes to the offset
        xor r13d, r13d
6:      cmp r13, [r12 + VEC_LEN]
        jae 8f
        mov rax, [r12 + VEC_DATA]
        mov r14, [rax + r13*8]
        mov rdi, r14
        call assert_stor
        PAT rsi, "('add', ':int:num', '...')"
        mov rdi, [r14 + N_DATA + 24]
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 7f
        mov rdi, [r14 + N_DATA + 24]
        mov esi, 2
        call list_from
        mov rdi, rax
        call seq_to_tuple
        mov [rsp + SP_T1], rax          # terms
        mov rdi, rax
        call get_loc
        test rax, rax
        jz 7f
        # offset += 256 * num; idx = ('add',) + terms
        B rdi, 0
        mov rsi, 513
        call int_mul
        mov rdi, [r14 + N_DATA + 16]
        mov rsi, rax
        call int_add
        mov [rsp + 8], rax              # (the new offset, in a free slot)
        mov rdi, [rsp + SP_T1]
        LOADS rsi, ADD
        call list_prepend
        mov rdi, rax
        call seq_to_tuple
        mov rcx, rax
        mov rsi, [r14 + N_DATA + 8]
        mov rdx, [rsp + 8]
        LOADS rdi, STOR
        call mk4
        mov rcx, [r12 + VEC_DATA]
        mov [rcx + r13*8], rax
7:      inc r13
        jmp 6b
8:      # array is when you add to a loc
        mov rdi, r12
        lea rsi, [rip + add_to_arr]
        call .Lsp_replace_all
        # (s 256 0 (add 3 (mul 0.125 idx)))
        xor r13d, r13d
9:      cmp r13, [r12 + VEC_LEN]
        jae 12f
        mov rax, [r12 + VEC_DATA]
        mov r14, [rax + r13*8]
        mov rdi, r14
        call assert_stor
        mov rdi, [r14 + N_DATA + 24]
        mov [rsp + SP_T1], rdi          # idx
        PAT rsi, "('add', ':e')"
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 10f
        mov rax, [rsp]
        mov [rsp + SP_T1], rax
10:     mov rdi, [rsp + SP_T1]
        call opcode_of
        cmp eax, OP_ADD
        jne 11f
        mov rdi, [rsp + SP_T1]
        call get_loc
        test rax, rax
        jnz 11f
        PAT rsi, "('add', ':int:loc', ':pos')"
        mov rdi, [rsp + SP_T1]
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 101f
        # ('stor', size, offset, ('array', pos, ('loc', loc)))
        B rsi, 0
        LOADS rdi, LOC
        call mk2
        mov rdx, rax
        B rsi, 1
        LOADS rdi, ARRAY
        call mk3
        mov rcx, rax
        mov rsi, [r14 + N_DATA + 8]
        mov rdx, [r14 + N_DATA + 16]
        LOADS rdi, STOR
        call mk4
        mov rcx, [r12 + VEC_DATA]
        mov [rcx + r13*8], rax
        jmp 11f
101:    mov edi, LOG_WARNING
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_weird_idx]
        mov rcx, [rsp + SP_T1]
        call log_fmt
11:     inc r13
        jmp 9b
12:     # the plain numbers: lengths of what is also referenced through
        # a loc, locs otherwise
        mov rdi, r12
        call vec_to_list
        mov rdi, rax
        call value_str
        mov [rsp + SP_TEXT], rax        # str(storages)
        xor r13d, r13d
13:     cmp r13, [r12 + VEC_LEN]
        jae 15f
        mov rax, [r12 + VEC_DATA]
        mov r14, [rax + r13*8]
        mov rdi, [r14 + N_DATA + 24]
        call is_int
        test eax, eax
        jz 14f
        mov rsi, [r14 + N_DATA + 24]
        LOADS rdi, LOC
        call mk2
        mov [rsp + SP_T1], rax          # ('loc', idx)
        mov rdi, rax
        call value_str
        lea rdi, [rax + N_DATA + 4]
        mov rax, [rsp + SP_TEXT]
        lea rsi, [rax + N_DATA + 4]
        xchg rdi, rsi
        call strstr@PLT
        test rax, rax
        jz 131f
        mov rsi, [rsp + SP_T1]
        LOADS rdi, LENGTH
        call mk2
        mov [rsp + SP_T1], rax
131:    mov rcx, [rsp + SP_T1]
        mov rsi, [r14 + N_DATA + 8]
        mov rdx, [r14 + N_DATA + 16]
        LOADS rdi, STOR
        call mk4
        mov rcx, [r12 + VEC_DATA]
        mov [rcx + r13*8], rax
14:     inc r13
        jmp 13b
15:     # cleanup of nested maps
        xor r13d, r13d
16:     cmp r13, [r12 + VEC_LEN]
        jae 18f
        mov rax, [r12 + VEC_DATA]
        mov r14, [rax + r13*8]
        PAT rsi, "('stor', ':size', ':off', ('range', ('array', ':beg', ':loc'), ':end'))"
        mov rdi, r14
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 17f
        # ('stor', size, off, ('array', ('range', beg, end), loc))
        B rsi, 2
        B rdx, 4
        LOADS rdi, RANGE
        call mk3
        mov rsi, rax
        B rdx, 3
        LOADS rdi, ARRAY
        call mk3
        mov rcx, rax
        B rsi, 0
        B rdx, 1
        LOADS rdi, STOR
        call mk4
        mov rcx, [r12 + VEC_DATA]
        mov [rcx + r13*8], rax
17:     inc r13
        jmp 16b
18:     mov rdi, r12
        lea rsi, [rip + double_map]
        call .Lsp_replace_all
        # the dict, then the storage references inside the definitions
        # replaced by theirs, recursively
        call od_new
        mov [rsp + SP_RES], rax
        xor r13d, r13d
19:     mov rax, [rsp + SP_ORIG]
        cmp r13, [rax + VEC_LEN]
        jae 20f
        mov rax, [rax + VEC_DATA]
        mov rsi, [rax + r13*8]
        mov rax, [r12 + VEC_DATA]
        mov rdx, [rax + r13*8]
        mov rdi, [rsp + SP_RES]
        call od_put
        inc r13
        jmp 19b
20:     call od_new
        mov r14, rax
        xor r13d, r13d
21:     mov rdi, [rsp + SP_RES]
        call od_len
        cmp r13, rax
        jae 22f
        mov rdi, [rsp + SP_RES]
        mov rsi, r13
        call od_val
        mov rdi, rax
        mov rsi, [rsp + SP_RES]
        call repl_res
        mov [rsp + SP_T1], rax
        mov rdi, rax
        call value_str
        mov rdi, rax
        lea rsi, [rip + .Ls_storage_word]
        call str_contains_c
        test eax, eax
        jnz .Lsp_assert_left
        mov rdi, [rsp + SP_RES]
        mov rsi, r13
        call od_key
        mov rdi, r14
        mov rsi, rax
        mov rdx, [rsp + SP_T1]
        call od_put
        inc r13
        jmp 21b
22:     mov rax, r14
        add rsp, MATCH_BINDINGS_SIZE + 64
        LEAVE
.Lsp_type_error:
        mov edi, E_TYPE
        lea rsi, [rip + .Ls_type_error]
        call err_throw
.Lsp_assert_left:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_storage_left]
        call err_throw
# replace_f(f) on every element of the vec rdi (python applies it to
# the list too, where it never matches)
.Lsp_replace_all:
        sub rsp, 24
        mov [rsp], rdi
        mov [rsp + 8], rsi
        mov qword ptr [rsp + 16], 0
1:      mov rdi, [rsp]
        mov rcx, [rsp + 16]
        cmp rcx, [rdi + VEC_LEN]
        jae 2f
        mov rax, [rdi + VEC_DATA]
        mov rdi, [rax + rcx*8]
        mov rsi, [rsp + 8]
        xor edx, edx
        call replace_f
        mov rdi, [rsp]
        mov rcx, [rsp + 16]
        mov rdi, [rdi + VEC_DATA]
        mov [rdi + rcx*8], rax
        inc qword ptr [rsp + 16]
        jmp 1b
2:      add rsp, 24
        ret
ENDF sparser

        .section .rodata
.Ls_storage_word: .asciz "storage"
.Ls_type_error: .asciz "sparser: 2 ** shl of an expression"
        .text

# repl_res(exp, res) -> value: the storage references replaced by their
# definitions, inside the definitions too
FUNC repl_res
        STACK_CHECK
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        call is_tuple
        test eax, eax
        jz 3f
        mov rdi, r12
        mov rsi, rbx
        call od_get
        test rax, rax
        jz 1f
        mov rbx, rax
1:      mov edi, [rbx + N_AUX]
        shl rdi, 3
        call arena_alloc
        mov [rsp], rax
        xor r13d, r13d
2:      cmp r13d, [rbx + N_AUX]
        jae 4f
        mov rdi, [rbx + N_DATA + r13*8]
        mov rsi, r12
        call repl_res
        mov rcx, [rsp]
        mov [rcx + r13*8], rax
        inc r13d
        jmp 2b
4:      mov edi, [rbx + N_AUX]
        mov rsi, [rsp]
        call mk_tuple
        add rsp, 16
        LEAVE
3:      mov rax, rbx
        add rsp, 16
        LEAVE
ENDF repl_res

# --- the names of the storages, from the getters ---

# find_storage_names(functions) -> od: getter -> name
FUNC find_storage_names
        ENTER
        sub rsp, 32
        mov rbx, rdi
        call od_new
        mov r12, rax
        xor r13d, r13d
1:      cmp r13, [rbx + VEC_LEN]
        jae .Lfn_done
        mov rax, [rbx + VEC_DATA]
        mov r14, [rax + r13*8]          # fn
        inc r13
        mov rdi, [r14 + FN_GETTER]
        test rdi, rdi
        jz 1b
        call opcode_of
        cmp eax, OP_STORAGE
        je 2f
        cmp eax, OP_STRUCT
        je 2f
        cmp eax, OP_BOOL
        jne .Lfn_assert
2:      # the function's name: without a leading "get", the first letter
        # lowered unless all caps, without the parameters
        mov rdi, [r14 + FN_NAME]
        call .Lfn_name_of
        mov [rsp], rax
        # an address: "Address" appended unless the name says so
        PAT rsi, "('storage', 160, '...')"
        mov rdi, [r14 + FN_GETTER]
        call pat_match_nobind
        test eax, eax
        jz 3f
        mov rdi, [rsp]
        call str_lower
        mov [rsp + 8], rax
        lea rsi, [rip + .Ls_address]
        mov rdi, rax
        call str_contains_c
        test eax, eax
        jnz 3f
        mov rdi, [rsp + 8]
        lea rsi, [rip + .Ls_addr]
        call str_contains_c
        test eax, eax
        jnz 3f
        mov rdi, [rsp + 8]
        lea rsi, [rip + .Ls_account]
        call str_contains_c
        test eax, eax
        jnz 3f
        mov rdi, [rsp + 8]
        lea rsi, [rip + .Ls_owner]
        call str_contains_c
        test eax, eax
        jnz 3f
        lea rdi, [rip + .Ls_Address]
        call str_new_c
        mov rdi, [rsp]
        mov rsi, rax
        call str_cat2
        mov [rsp], rax
3:      mov rdi, [rsp]
        call str_interned               # (the name goes into expressions)
        mov rdi, r12
        mov rsi, [r14 + FN_GETTER]
        mov rdx, rax
        call od_put
        jmp 1b
.Lfn_done:
        mov rax, r12
        add rsp, 32
        LEAVE
.Lfn_assert:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_assert_getter]
        call err_throw
# the storage name from a function name (rdi)
.Lfn_name_of:
        sub rsp, 24
        mov [rsp], rdi
        # name[:3] == "get" and len(name.split("(")[0]) > 3
        lea rsi, [rip + .Ls_get]
        call str_startswith_c
        test eax, eax
        jz 1f
        mov rdi, [rsp]
        call .Lfn_before_paren
        cmp eax, 3
        jbe 1f
        mov rdi, [rsp]
        mov esi, 3
        mov edx, 0x7fffffff
        call str_slice
        mov [rsp], rax
1:      # name != name.upper(): the first letter lowered
        mov rdi, [rsp]
        call str_upper
        mov rdi, rax
        mov rsi, [rsp]
        call str_eq
        test eax, eax
        jnz 2f
        mov rdi, [rsp]
        cmp dword ptr [rdi + N_DATA], 0
        je 2f
        mov rdi, [rsp]
        mov esi, 1
        mov edx, 0x7fffffff
        call str_slice
        mov [rsp + 8], rax
        mov rdi, [rsp]
        xor esi, esi
        mov edx, 1
        call str_slice
        mov rdi, rax
        call str_lower
        mov rdi, rax
        mov rsi, [rsp + 8]
        call str_cat2
        mov [rsp], rax
2:      # name.split("(")[0]
        mov rdi, [rsp]
        call .Lfn_before_paren
        mov rdi, [rsp]
        xor esi, esi
        mov edx, eax
        call str_slice
        add rsp, 24
        ret
# eax: the length of the text before the first "(" (or all of it)
.Lfn_before_paren:
        sub rsp, 8
        mov [rsp], rdi
        lea rdi, [rdi + N_DATA + 4]
        mov esi, '('
        call strchr@PLT
        mov rdi, [rsp]
        test rax, rax
        jz 1f
        lea rcx, [rdi + N_DATA + 4]
        sub rax, rcx
        add rsp, 8
        ret
1:      mov eax, [rdi + N_DATA]
        add rsp, 8
        ret
ENDF find_storage_names

# str_lower(str) / str_upper(str) -> str (ASCII)
FUNC str_lower
        ENTER
        mov rbx, rdi
        mov esi, [rdi + N_DATA]
        lea rdi, [rdi + N_DATA + 4]
        call str_new
        mov ecx, [rax + N_DATA]
        lea rdx, [rax + N_DATA + 4]
1:      test ecx, ecx
        jz 2f
        movzx esi, byte ptr [rdx]
        lea edi, [rsi - 'A']
        cmp edi, 26
        jae 3f
        add sil, 32
        mov [rdx], sil
3:      inc rdx
        dec ecx
        jmp 1b
2:      LEAVE
ENDF str_lower

FUNC str_upper
        ENTER
        mov rbx, rdi
        mov esi, [rdi + N_DATA]
        lea rdi, [rdi + N_DATA + 4]
        call str_new
        mov ecx, [rax + N_DATA]
        lea rdx, [rax + N_DATA + 4]
1:      test ecx, ecx
        jz 2f
        movzx esi, byte ptr [rdx]
        lea edi, [rsi - 'a']
        cmp edi, 26
        jae 3f
        sub sil, 32
        mov [rdx], sil
3:      inc rdx
        dec ecx
        jmp 1b
2:      LEAVE
ENDF str_upper

# replace_names_in_assoc(names, assoc, used_locs)
FUNC replace_names_in_assoc
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 64
        .set RN_NAMES, MATCH_BINDINGS_SIZE
        .set RN_ASSOC, MATCH_BINDINGS_SIZE + 8
        .set RN_USED, MATCH_BINDINGS_SIZE + 16
        .set RN_I, MATCH_BINDINGS_SIZE + 24
        .set RN_NAME, MATCH_BINDINGS_SIZE + 32
        .set RN_STOR_ID, MATCH_BINDINGS_SIZE + 40
        .set RN_J, MATCH_BINDINGS_SIZE + 48
        .set RN_LOC, MATCH_BINDINGS_SIZE + 56
        mov [rsp + RN_NAMES], rdi
        mov [rsp + RN_ASSOC], rsi
        mov [rsp + RN_USED], rdx
        mov qword ptr [rsp + RN_I], 0
.Lrn_next:
        mov rdi, [rsp + RN_NAMES]
        call od_len
        cmp [rsp + RN_I], rax
        jae .Lrn_done
        mov rdi, [rsp + RN_NAMES]
        mov rsi, [rsp + RN_I]
        call od_key
        mov rbx, rax                    # pattern (the getter)
        mov rdi, [rsp + RN_NAMES]
        mov rsi, [rsp + RN_I]
        call od_val
        mov [rsp + RN_NAME], rax
        inc qword ptr [rsp + RN_I]
        mov rdi, rbx
        call opcode_of
        cmp eax, OP_BOOL
        je .Lrn_next
        mov r12, rbx
        cmp eax, OP_STRUCT
        je 1f
        mov rdi, [rsp + RN_ASSOC]
        mov rsi, rbx
        call od_get
        test rax, rax
        jz .Lrn_key_error
        mov r12, rax                    # stor_id
1:      mov [rsp + RN_STOR_ID], r12
        PAT rsi, "('stor', ':size', ':off', ('loc', ':num'))"
        mov rdi, r12
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz .Lrn_arrays
        # every reference (key) at this location must be a plain one
        # (python looks at the keys: raw storages, which never hold a
        # loc - so this always holds, and the name is used)
        mov qword ptr [rsp + RN_J], 0
2:      mov rdi, [rsp + RN_ASSOC]
        call od_len
        cmp [rsp + RN_J], rax
        jae 3f
        mov rdi, [rsp + RN_ASSOC]
        mov rsi, [rsp + RN_J]
        call od_key
        mov r13, rax
        mov rdi, rax
        call get_loc
        mov rdi, rax
        B rsi, 2
        call py_equal
        test eax, eax
        jz 21f
        PAT rsi, "('stor', 'Any', 'Any', ('loc', 'Any'))"
        mov rdi, r13
        call pat_match_nobind
        test eax, eax
        jz .Lrn_next
21:     inc qword ptr [rsp + RN_J]
        jmp 2b
3:      mov rdi, [rsp + RN_USED]
        mov rsi, r12
        call set_add
        # the renamed stor: ('stor', size, off, ('name', name, num))
        mov rsi, [rsp + RN_NAME]
        B rdx, 2
        LOADS rdi, NAME
        call mk3
        mov rcx, rax
        B rsi, 0
        B rdx, 1
        LOADS rdi, STOR
        call mk4
        mov r13, rax
        mov qword ptr [rsp + RN_J], 0
4:      mov rdi, [rsp + RN_ASSOC]
        call od_len
        cmp [rsp + RN_J], rax
        jae .Lrn_next
        mov rdi, [rsp + RN_ASSOC]
        mov rsi, [rsp + RN_J]
        call od_val
        cmp rax, r12
        jne 41f
        mov rdi, [rsp + RN_ASSOC]
        mov rsi, [rsp + RN_J]
        mov rdx, r13
        call od_set_val
41:     inc qword ptr [rsp + RN_J]
        jmp 4b
.Lrn_arrays:
        PAT rsi, "('stor', 'Any', 'Any', ('map', 'Any', ':loc'))"
        mov rdi, r12
        mov rdx, rsp
        call pat_match
        test eax, eax
        jnz 5f
        PAT rsi, "('stor', 'Any', 'Any', ('array', 'Any', ':loc'))"
        mov rdi, r12
        mov rdx, rsp
        call pat_match
        test eax, eax
        jnz 5f
        PAT rsi, "('struct', ':loc')"
        mov rdi, r12
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz .Lrn_warn
5:      # no "Address" at the end of an array's name
        mov rdi, [rsp + RN_NAME]
        lea rsi, [rip + .Ls_Address]
        call str_split
        mov rax, [rax + N_DATA]
        cmp dword ptr [rax + N_DATA], 0
        je 6f
        mov rdi, rax
        call str_interned
        mov [rsp + RN_NAME], rax
6:      B rdi, 0
        call get_loc
        mov [rsp + RN_LOC], rax         # loc_id (0 for python's None)
        mov rdi, rax
        call none_if_nil
        mov [rsp + RN_STOR_ID], rax     # (as a value)
        mov rsi, rax
        LOADS rdi, ARRAY
        call mk2
        mov rdi, [rsp + RN_USED]
        mov rsi, rax
        call set_add
        # ('loc', loc_id) -> ('name', name, loc_id) wherever the loc is
        mov rsi, [rsp + RN_STOR_ID]
        LOADS rdi, LOC
        call mk2
        mov r13, rax
        mov rsi, [rsp + RN_NAME]
        mov rdx, [rsp + RN_STOR_ID]
        LOADS rdi, NAME
        call mk3
        mov r14, rax
        mov qword ptr [rsp + RN_J], 0
7:      mov rdi, [rsp + RN_ASSOC]
        call od_len
        cmp [rsp + RN_J], rax
        jae .Lrn_next
        mov rdi, [rsp + RN_ASSOC]
        mov rsi, [rsp + RN_J]
        call od_val
        mov r12, rax
        mov rdi, rax
        call get_loc
        mov rdi, rax
        mov rsi, [rsp + RN_LOC]
        call .Lrn_same_loc
        test eax, eax
        jz 71f
        mov rdi, r12
        mov rsi, r13
        mov rdx, r14
        call replace
        mov rdi, [rsp + RN_ASSOC]
        mov rsi, [rsp + RN_J]
        mov rdx, rax
        call od_set_val
71:     inc qword ptr [rsp + RN_J]
        jmp 7b
.Lrn_warn:
        mov edi, LOG_WARNING
        lea rsi, [rip + .Ls_logname]
        lea rdx, [rip + .Ls_not_found]
        call log_fmt
        jmp .Lrn_next
.Lrn_done:
        add rsp, MATCH_BINDINGS_SIZE + 64
        LEAVE
.Lrn_key_error:
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_key_error]
        call err_throw
# eax: two get_loc results are equal (None == None included)
.Lrn_same_loc:
        test rdi, rdi
        jnz 1f
        xor eax, eax
        test rsi, rsi
        sete al
        ret
1:      test rsi, rsi
        jnz 2f
        xor eax, eax
        ret
2:      sub rsp, 8
        call py_equal
        add rsp, 8
        ret
ENDF replace_names_in_assoc

# replace_names_in_assoc_bool(names, assoc, used_locs): the bool getters
# name their storage, unless it is used otherwise
FUNC replace_names_in_assoc_bool
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 48
        .set RB_NAMES, MATCH_BINDINGS_SIZE
        .set RB_ASSOC, MATCH_BINDINGS_SIZE + 8
        .set RB_USED, MATCH_BINDINGS_SIZE + 16
        .set RB_I, MATCH_BINDINGS_SIZE + 24
        .set RB_J, MATCH_BINDINGS_SIZE + 32
        mov [rsp + RB_NAMES], rdi
        mov [rsp + RB_ASSOC], rsi
        mov [rsp + RB_USED], rdx
        mov qword ptr [rsp + RB_I], 0
.Lrb_next:
        mov rdi, [rsp + RB_NAMES]
        call od_len
        cmp [rsp + RB_I], rax
        jae .Lrb_done
        mov rdi, [rsp + RB_NAMES]
        mov rsi, [rsp + RB_I]
        call od_key
        mov rbx, rax
        mov rdi, [rsp + RB_NAMES]
        mov rsi, [rsp + RB_I]
        call od_val
        mov r12, rax                    # name
        inc qword ptr [rsp + RB_I]
        PAT rsi, "('bool', ('storage', ':size', ':off', ':int:loc'))"
        mov rdi, rbx
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz .Lrb_next
        B rsi, 2
        LOADS rdi, ARRAY
        call mk2
        mov rdi, [rsp + RB_USED]
        mov rsi, rax
        call set_has
        test eax, eax
        jnz .Lrb_next
        B rsi, 0
        B rdx, 1
        B rcx, 2
        LOADS rdi, STOR
        call mk4
        mov rdi, [rsp + RB_USED]
        mov rsi, rax
        call set_has
        test eax, eax
        jnz .Lrb_next
        # ('stor', size, off, ('loc', loc)) -> ('stor', size, off, ('name', name, loc))
        B rsi, 2
        LOADS rdi, LOC
        call mk2
        mov rcx, rax
        B rsi, 0
        B rdx, 1
        LOADS rdi, STOR
        call mk4
        mov r13, rax
        mov rsi, r12
        B rdx, 2
        LOADS rdi, NAME
        call mk3
        mov rcx, rax
        B rsi, 0
        B rdx, 1
        LOADS rdi, STOR
        call mk4
        mov r14, rax
        mov qword ptr [rsp + RB_J], 0
1:      mov rdi, [rsp + RB_ASSOC]
        call od_len
        cmp [rsp + RB_J], rax
        jae .Lrb_next
        mov rdi, [rsp + RB_ASSOC]
        mov rsi, [rsp + RB_J]
        call od_val
        cmp rax, r13
        jne 2f
        mov rdi, [rsp + RB_ASSOC]
        mov rsi, [rsp + RB_J]
        mov rdx, r14
        call od_set_val
2:      inc qword ptr [rsp + RB_J]
        jmp 1b
.Lrb_done:
        add rsp, MATCH_BINDINGS_SIZE + 48
        LEAVE
ENDF replace_names_in_assoc_bool

# repl_stor(exp, assoc) -> value: the storage references of a trace
# replaced by their definitions
FUNC repl_stor
        STACK_CHECK
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 16
        mov rbx, rdi
        mov r12, rsi
        call is_list
        test eax, eax
        jnz .Lrp_seq
        mov rdi, rbx
        PATXD "('store', ':size', ':off', ':idx', ':val')"
        test eax, eax
        jz 1f
        # ('store',) + dest[1:] + (repl_stor(val),)
        B rsi, 0
        B rdx, 1
        B rcx, 2
        LOADS rdi, STORAGE
        call mk4
        mov rdi, r12
        mov rsi, rax
        call od_get
        test rax, rax
        jz .Lrp_key_error
        mov rdi, rax
        LOADS rsi, STORE
        call replace_head
        mov r13, rax
        B rdi, 3
        mov rsi, r12
        call repl_stor
        mov rdi, r13
        mov rsi, rax
        call tuple_append
        jmp .Lrp_ret
1:      mov rdi, r12
        mov rsi, rbx
        call od_get
        test rax, rax
        jnz .Lrp_ret
        mov rdi, rbx
        call is_tuple
        test eax, eax
        jz 2f
.Lrp_seq:
        mov edi, [rbx + N_AUX]
        shl rdi, 3
        call arena_alloc
        mov [rsp + MATCH_BINDINGS_SIZE], rax
        xor r13d, r13d
3:      cmp r13d, [rbx + N_AUX]
        jae 4f
        mov rdi, [rbx + N_DATA + r13*8]
        mov rsi, r12
        call repl_stor
        mov rcx, [rsp + MATCH_BINDINGS_SIZE]
        mov [rcx + r13*8], rax
        inc r13d
        jmp 3b
4:      mov rdi, rbx
        mov rsi, [rsp + MATCH_BINDINGS_SIZE]
        call mk_seq_like
        jmp .Lrp_ret
2:      mov rax, rbx
.Lrp_ret:
        add rsp, MATCH_BINDINGS_SIZE + 16
        LEAVE
.Lrp_key_error:
        mov edi, E_INDEX
        lea rsi, [rip + .Ls_key_error]
        call err_throw
ENDF repl_stor

# --- the definitions ---

# get_type(stordefs) -> value: the type of the elements of the arrays
# and maps at a location, from the masks used on them (a vec of stors)
FUNC get_type
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 32
        .set GT_SIZES, MATCH_BINDINGS_SIZE
        .set GT_OFFSETS, MATCH_BINDINGS_SIZE + 8
        mov rbx, rdi
        call vec_new
        mov [rsp + GT_SIZES], rax
        call vec_new
        mov [rsp + GT_OFFSETS], rax
        xor r12d, r12d
1:      cmp r12, [rbx + VEC_LEN]
        jae 3f
        mov rax, [rbx + VEC_DATA]
        mov r13, [rax + r12*8]
        inc r12
        mov rdi, r13
        call .Lgt_map_or_array
        test eax, eax
        jz 1b
        mov rdi, [rsp + GT_SIZES]
        mov rsi, [r13 + N_DATA + 8]
        call set_add
        mov edi, 1
        mov rsi, [r13 + N_DATA + 16]
        call alg_safe_le_op
        cmp eax, TRI_TRUE
        jne 1b
        mov rdi, [rsp + GT_OFFSETS]
        mov rsi, [r13 + N_DATA + 16]
        call set_add
        jmp 1b
3:      mov rdi, [rsp + GT_SIZES]
        mov esi, 513
        call set_remove
        mov rdi, [rsp + GT_OFFSETS]
        mov esi, 1
        call set_remove
        mov rax, [rsp + GT_OFFSETS]
        cmp qword ptr [rax + VEC_LEN], 0
        je 6f
        # structs: their size from how the index is multiplied
        xor r12d, r12d
4:      cmp r12, [rbx + VEC_LEN]
        jae 5f
        mov rax, [rbx + VEC_DATA]
        mov r13, [rax + r12*8]
        inc r12
        mov rdi, r13
        call .Lgt_map_or_array
        test eax, eax
        jz 4b
        mov rax, [r13 + N_DATA + 24]
        mov rdi, [rax + N_DATA + 8]     # idx
        PAT rsi, "('stor', 'Any', ':int:siz', ('length', '...'))"
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 4b
        B rdi, 0
        call int_sign
        cmp eax, -1
        jne 4b
        B rdi, 0
        call int_neg
        mov rdi, rax
        mov rsi, 3
        call int_add
        mov rsi, rax
        LOADS rdi, STRUCT
        call mk2
        jmp .Lgt_ret
5:      LOADS rax, STRUCT
        jmp .Lgt_ret
6:      mov rax, [rsp + GT_SIZES]
        cmp qword ptr [rax + VEC_LEN], 0
        jne 7f
        mov eax, 513
        jmp .Lgt_ret
7:      mov rdi, rax
        call vec_min_int
.Lgt_ret:
        add rsp, MATCH_BINDINGS_SIZE + 32
        LEAVE
# eax: rdi ~ ('stor', size, off, (op, idx, ...)) with op a map or an array
.Lgt_map_or_array:
        sub rsp, 8
        mov [rsp], rdi
        call assert_stor
        mov rdi, [rsp]
        mov rdi, [rdi + N_DATA + 24]
        cmp dword ptr [rdi + N_AUX], 2
        jb 1f
        call opcode_of
        cmp eax, OP_MAP
        je 2f
        cmp eax, OP_ARRAY
        je 2f
1:      xor eax, eax
        add rsp, 8
        ret
2:      mov eax, 1
        add rsp, 8
        ret
ENDF get_type

# set_remove(vec, v): removes v if present (values compared like python)
FUNC set_remove
        ENTER
        mov rbx, rdi
        mov r12, rsi
        xor r13d, r13d
1:      cmp r13, [rbx + VEC_LEN]
        jae 3f
        mov rax, [rbx + VEC_DATA]
        mov rdi, [rax + r13*8]
        mov rsi, r12
        call py_equal
        test eax, eax
        jnz 2f
        inc r13
        jmp 1b
2:      mov rax, [rbx + VEC_DATA]
        mov rcx, [rbx + VEC_LEN]
        dec rcx
        mov [rbx + VEC_LEN], rcx
4:      cmp r13, rcx
        jae 3f
        mov rdx, [rax + r13*8 + 8]
        mov [rax + r13*8], rdx
        inc r13
        jmp 4b
3:      LEAVE
ENDF set_remove

# vec_min_int(vec) -> value: min() of integers (python raises on mixed
# types: E_TYPE)
FUNC vec_min_int
        ENTER
        mov rbx, rdi
        mov rax, [rbx + VEC_DATA]
        mov r12, [rax]
        mov r13d, 1
1:      cmp r13, [rbx + VEC_LEN]
        jae 3f
        mov rax, [rbx + VEC_DATA]
        mov rdi, [rax + r13*8]
        mov rsi, r12
        xor edx, edx
        call py_lt
        test eax, eax
        jz 2f
        mov rax, [rbx + VEC_DATA]
        mov r12, [rax + r13*8]
2:      inc r13
        jmp 1b
3:      mov rax, r12
        LEAVE
ENDF vec_min_int

# rewrite_functions(functions) -> list of ('def', name, loc, type): the
# functions' traces get 'stor' references, named after the getters
FUNC rewrite_functions
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 96
        .set RF_FUNCS, MATCH_BINDINGS_SIZE
        .set RF_ASSOC, MATCH_BINDINGS_SIZE + 8
        .set RF_NAMES, MATCH_BINDINGS_SIZE + 16
        .set RF_USED, MATCH_BINDINGS_SIZE + 24
        .set RF_STORDEFS, MATCH_BINDINGS_SIZE + 32     # od: loc -> vec of stors
        .set RF_DEFS, MATCH_BINDINGS_SIZE + 40
        .set RF_I, MATCH_BINDINGS_SIZE + 48
        .set RF_LOC, MATCH_BINDINGS_SIZE + 56
        .set RF_LOCS, MATCH_BINDINGS_SIZE + 64
        .set RF_STORS, MATCH_BINDINGS_SIZE + 72
        .set RF_J, MATCH_BINDINGS_SIZE + 80
        .set RF_NAME, MATCH_BINDINGS_SIZE + 88
        mov [rsp + RF_FUNCS], rdi
        mov rbx, rdi
        # the storage references of every function
        call vec_new
        mov r12, rax
        xor r13d, r13d
1:      cmp r13, [rbx + VEC_LEN]
        jae 2f
        mov rax, [rbx + VEC_DATA]
        mov rax, [rax + r13*8]
        mov rdi, [rax + FN_TRACE]
        mov rsi, r12
        call find_stores
        inc r13
        jmp 1b
2:      mov rdi, r12
        call sparser
        mov [rsp + RF_ASSOC], rax
        mov rdi, rbx
        call find_storage_names
        mov [rsp + RF_NAMES], rax
        call vec_new
        mov [rsp + RF_USED], rax
        mov rdi, [rsp + RF_NAMES]
        mov rsi, [rsp + RF_ASSOC]
        mov rdx, rax
        call replace_names_in_assoc
        mov rdi, [rsp + RF_NAMES]
        mov rsi, [rsp + RF_ASSOC]
        mov rdx, [rsp + RF_USED]
        call replace_names_in_assoc_bool
        # the traces rewritten
        xor r13d, r13d
3:      cmp r13, [rbx + VEC_LEN]
        jae 4f
        mov rax, [rbx + VEC_DATA]
        mov r12, [rax + r13*8]
        mov rdi, [r12 + FN_TRACE]
        mov rsi, [rsp + RF_ASSOC]
        call repl_stor
        mov [r12 + FN_TRACE], rax
        inc r13
        jmp 3b
4:      # the definitions by location (99 for none; the locations that
        # aren't numbers get no definitions but stay as keys)
        call od_new
        mov [rsp + RF_STORDEFS], rax
        mov qword ptr [rsp + RF_I], 0
5:      mov rdi, [rsp + RF_ASSOC]
        call od_len
        cmp [rsp + RF_I], rax
        jae 8f
        mov rdi, [rsp + RF_ASSOC]
        mov rsi, [rsp + RF_I]
        call od_val
        mov r12, rax                    # dest
        inc qword ptr [rsp + RF_I]
        mov rdi, rax
        call get_loc
        test rax, rax
        jnz 6f
        mov eax, 199                    # tagged 99
6:      mov [rsp + RF_LOC], rax
        mov rdi, [rsp + RF_STORDEFS]
        mov rsi, rax
        call od_get
        test rax, rax
        jnz 7f
        call vec_new
        mov rdi, [rsp + RF_STORDEFS]
        mov rsi, [rsp + RF_LOC]
        mov rdx, rax
        push rax
        push rax
        call od_put
        pop rax
        pop rax
7:      mov r13, rax
        mov rdi, [rsp + RF_LOC]
        call is_int
        test eax, eax
        jz 5b
        mov rdi, r13
        mov rsi, r12
        call set_add
        jmp 5b
8:      # the definitions, by sorted location
        call vec_new
        mov [rsp + RF_DEFS], rax
        mov rdi, [rsp + RF_STORDEFS]
        mov rdi, [rdi + OD_KEYS]
        call py_sorted
        mov [rsp + RF_LOCS], rax
        mov qword ptr [rsp + RF_I], 0
.Lrf_loc:
        mov rax, [rsp + RF_LOCS]
        mov rcx, [rsp + RF_I]
        cmp rcx, [rax + VEC_LEN]
        jae .Lrf_done
        mov rax, [rax + VEC_DATA]
        mov rax, [rax + rcx*8]
        mov [rsp + RF_LOC], rax
        inc qword ptr [rsp + RF_I]
        mov rdi, [rsp + RF_STORDEFS]
        mov rsi, rax
        call od_get
        mov rdi, rax
        call py_sorted
        mov [rsp + RF_STORS], rax
        # the first stor that isn't a plain loc/name decides: a mapping,
        # an array, or nothing
        mov qword ptr [rsp + RF_J], 0
9:      mov rax, [rsp + RF_STORS]
        mov rcx, [rsp + RF_J]
        cmp rcx, [rax + VEC_LEN]
        jae .Lrf_masks
        mov rax, [rax + VEC_DATA]
        mov r12, [rax + rcx*8]          # l
        inc qword ptr [rsp + RF_J]
        PAT rsi, "('stor', ':int:a', ':int:b', ('loc', 'Any'))"
        mov rdi, r12
        call pat_match_nobind
        test eax, eax
        jnz 9b
        PAT rsi, "('stor', ':int:a', ':int:b', ('name', '...'))"
        mov rdi, r12
        call pat_match_nobind
        test eax, eax
        jnz 9b
        mov rdi, r12
        call get_name
        test rax, rax
        jnz 10f
        mov rdi, [rsp + RF_LOC]
        xor esi, esi
        call .Lrf_stor_name
10:     mov [rsp + RF_NAME], rax
        PAT rsi, "('stor', ':int:a', ':int:b', ':idx')"
        mov rdi, r12
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz .Lrf_loc
        B rdi, 2
        call opcode_of
        LOADS r13, MAPPING
        cmp eax, OP_MAP
        je 11f
        LOADS r13, ARRAY
        cmp eax, OP_ARRAY
        je 11f
        cmp eax, OP_LENGTH
        jne .Lrf_loc
11:     mov rdi, [rsp + RF_STORDEFS]
        mov rsi, [rsp + RF_LOC]
        call od_get
        mov rdi, rax
        call get_type
        mov rdi, r13
        mov rsi, rax
        call mk2
        mov rcx, rax
        mov rsi, [rsp + RF_NAME]
        mov rdx, [rsp + RF_LOC]
        LOADS rdi, DEF
        call mk4
        mov rdi, [rsp + RF_DEFS]
        mov rsi, rax
        call vec_push
        jmp .Lrf_loc
.Lrf_masks:
        # all plain: one definition per mask
        mov qword ptr [rsp + RF_J], 0
12:     mov rax, [rsp + RF_STORS]
        mov rcx, [rsp + RF_J]
        cmp rcx, [rax + VEC_LEN]
        jae .Lrf_loc
        mov rax, [rax + VEC_DATA]
        mov r12, [rax + rcx*8]
        inc qword ptr [rsp + RF_J]
        mov rdi, r12
        call get_name
        test rax, rax
        jnz 13f
        mov rdi, [rsp + RF_LOC]
        mov esi, 1
        call .Lrf_stor_name
13:     mov [rsp + RF_NAME], rax
        mov rsi, [r12 + N_DATA + 8]
        mov rdx, [r12 + N_DATA + 16]
        LOADS rdi, MASK
        call mk3
        mov rcx, rax
        mov rsi, [rsp + RF_NAME]
        mov rdx, [rsp + RF_LOC]
        LOADS rdi, DEF
        call mk4
        mov rdi, [rsp + RF_DEFS]
        mov rsi, rax
        call vec_push
        jmp 12b
.Lrf_done:
        mov rdi, [rsp + RF_DEFS]
        call vec_to_list
        add rsp, MATCH_BINDINGS_SIZE + 96
        LEAVE
# "stor" + str(loc), or (esi = 1) "stor" + the first four hex digits
# upper-cased for a loc of 1000 or more
.Lrf_stor_name:
        sub rsp, 24
        mov [rsp], rdi
        mov [rsp + 8], rsi
        call sb_new
        mov [rsp + 16], rax
        mov rdi, rax
        lea rsi, [rip + .Ls_stor]
        call sb_append_c
        cmp qword ptr [rsp + 8], 0
        je 1f
        mov rdi, [rsp]
        call is_int
        test eax, eax
        jz 1f
        mov rdi, [rsp]
        mov rsi, 1000
        TAG rsi
        call int_cmp
        cmp eax, -1
        je 1f
        # hex(loc)[2:6].upper()
        call sb_new
        mov rdi, rax
        mov [rsp + 8], rdi
        mov rsi, [rsp]
        mov edx, 16
        call sb_append_int
        mov rdi, [rsp + 8]
        call sb_finish
        mov rdi, rax
        mov esi, 2
        mov edx, 6
        call str_slice
        mov rdi, rax
        call str_upper
        mov rdi, [rsp + 16]
        mov rsi, rax
        call sb_append_str
        jmp 2f
1:      mov rdi, [rsp]
        call value_str
        mov rdi, [rsp + 16]
        mov rsi, rax
        call sb_append_str
2:      mov rdi, [rsp + 16]
        call sb_finish_intern
        add rsp, 24
        ret
ENDF rewrite_functions

        .section .note.GNU-stack,"",@progbits
