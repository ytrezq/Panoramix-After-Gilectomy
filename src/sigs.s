# Function signatures and parameter names, as the printer needs them
# (utils/signatures.py, utils/supplement.py's hashes_to, Loader.find_sig,
# and masks.py's type names).
#
# An abi entry is a tuple (name, inputs[, type]) where inputs is a list of
# inputs (see input_components below), or NIL when the signature is
# unknown (python: no "inputs" key). sig_db_lookup finds the entry of a
# selector in the signature database; the current function's entry is on
# the context.

.include "defs.inc"

        .section .rodata
.Ls_bool:       .asciz "bool"
.Ls_uint8:      .asciz "uint8"
.Ls_uint16:     .asciz "uint16"
.Ls_uint32:     .asciz "uint32"
.Ls_uint64:     .asciz "uint64"
.Ls_uint128:    .asciz "uint128"
.Ls_address:    .asciz "address"
.Ls_uint256:    .asciz "uint256"
.Ls_big:        .asciz "big"
.Ls_dot_length: .asciz ".length"
.Ls_qqq:        .asciz "???"
.Ls_unknown:    .asciz "unknown"
.Ls_lparen:     .asciz "("
.Ls_rparen:     .asciz ")"
.Ls_comma_sp:   .asciz ", "
.Ls_space:      .asciz " "
.Ls_lbracket:   .asciz "["
.Ls_rbracket:   .asciz "]"

        # mask sizes and their type names, in python's lookup order
        .section .data.rel.ro
        .align 8
mask_types:
        .quad 1,   .Ls_bool
        .quad 8,   .Ls_uint8
        .quad 16,  .Ls_uint16
        .quad 32,  .Ls_uint32
        .quad 64,  .Ls_uint64
        .quad 128, .Ls_uint128
        .quad 160, .Ls_address
        .quad 256, .Ls_uint256
        .quad 0, 0

        # type names and their mask sizes (type_to_mask)
type_masks:
        .quad .Ls_bool, 1
        .quad .Ls_uint8, 8
        .quad .Ls_uint16, 16
        .quad .Ls_uint32, 32
        .quad .Ls_uint64, 64
        .quad .Lt_int8, 8
        .quad .Lt_bytes1, 8
        .quad .Lt_int16, 16
        .quad .Lt_bytes2, 16
        .quad .Lt_int32, 32
        .quad .Lt_bytes4, 32
        .quad .Lt_int64, 64
        .quad .Lt_bytes8, 64
        .quad .Lt_int128, 128
        .quad .Ls_uint128, 128
        .quad .Lt_bytes16, 128
        .quad .Ls_address, 160
        .quad .Ls_uint256, 256
        .quad .Lt_bytes32, 256
        .quad .Lt_int256, 256
        .quad .Lt_int, 256
        .quad .Lt_uint, 256
        .quad 0, 0
        .section .rodata
.Lt_int8:    .asciz "int8"
.Lt_bytes1:  .asciz "bytes1"
.Lt_int16:   .asciz "int16"
.Lt_bytes2:  .asciz "bytes2"
.Lt_int32:   .asciz "int32"
.Lt_bytes4:  .asciz "bytes4"
.Lt_int64:   .asciz "int64"
.Lt_bytes8:  .asciz "bytes8"
.Lt_int128:  .asciz "int128"
.Lt_bytes16: .asciz "bytes16"
.Lt_bytes32: .asciz "bytes32"
.Lt_int256:  .asciz "int256"
.Lt_int:     .asciz "int"
.Lt_uint:    .asciz "uint"

        .text

.macro B reg, n
        mov \reg, [rsp + 8*(\n)]
.endm

# mask_to_type(num, force) -> value: the type name of a mask size (a
# string), num itself when it isn't an int, 0 (None) when unknown - unless
# force, which gives "big<num>" above 256 and the smallest type that fits
# otherwise
FUNC mask_to_type
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call is_int
        test eax, eax
        jz .Lmt_asis
        lea r13, [rip + mask_types]
1:      mov rax, [r13]
        test rax, rax
        jz 2f
        TAG rax
        cmp rax, rbx
        je .Lmt_found
        add r13, 16
        jmp 1b
2:      test r12, r12
        jz .Lmt_none
        mov rdi, rbx
        mov rsi, 256
        TAG rsi
        call int_cmp
        cmp eax, 1
        jne 3f
        # "big" + str(num)
        call sb_new
        mov r13, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_big]
        call sb_append_c
        mov rdi, r13
        mov rsi, rbx
        mov edx, 10
        call sb_append_int
        mov rdi, r13
        call sb_finish
        LEAVE
3:      lea r13, [rip + mask_types]
4:      mov rax, [r13]
        test rax, rax
        jz .Lmt_assert
        TAG rax
        mov rdi, rax
        mov rsi, rbx
        call int_cmp
        cmp eax, 1
        je .Lmt_found
        add r13, 16
        jmp 4b
.Lmt_found:
        mov rdi, [r13 + 8]
        call str_intern_c
        LEAVE
.Lmt_asis:
        mov rax, rbx
        LEAVE
.Lmt_none:
        xor eax, eax
        LEAVE
.Lmt_assert:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_mt_assert]
        call err_throw
ENDF mask_to_type

        .section .rodata
.Ls_mt_assert: .asciz "mask_to_type: no type fits"
        .text

# type_to_mask(type_str) -> value: the mask size of a type name, or 0
FUNC type_to_mask
        ENTER
        mov rbx, rdi
        lea r12, [rip + type_masks]
1:      mov rsi, [r12]
        test rsi, rsi
        jz 2f
        mov rdi, rbx
        call str_eq_c
        test eax, eax
        jnz 3f
        add r12, 16
        jmp 1b
2:      xor eax, eax
        LEAVE
3:      mov rax, [r12 + 8]
        TAG rax
        LEAVE
ENDF type_to_mask

# hex_digits(sb, v): the hex digits of an integer, without 0x nor sign
FUNC hex_digits
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call sb_new
        mov r13, rax
        mov rdi, rax
        mov rsi, r12
        mov edx, 16
        call sb_append_int
        mov rsi, [r13 + SB_BUF]
        cmp byte ptr [rsi], '-'
        jne 1f
        inc rsi
1:      add rsi, 2                      # past "0x"
        mov rdi, rbx
        call sb_append_c
        mov rdi, r13
        call sb_free
        LEAVE
ENDF hex_digits

# padded_hex(v, n) -> str: helpers.padded_hex - "0x" and the hex digits
# padded with zeros to n of them, or n question marks when there are more
FUNC padded_hex
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        call sb_new
        mov r13, rax
        mov rdi, rax
        mov rsi, rbx
        call hex_digits
        mov r14, [r13 + SB_LEN]         # the digits
        cmp r14, r12
        ja 2f
        call sb_new
        mov [rsp], rax
        mov rdi, rax
        lea rsi, [rip + .Ls_0x]
        call sb_append_c
        mov rcx, r12
        sub rcx, r14
1:      test rcx, rcx
        jz 3f
        push rcx
        push rcx
        mov rdi, [rsp + 16]
        mov esi, '0'
        call sb_append_char
        pop rcx
        pop rcx
        dec rcx
        jmp 1b
3:      mov rdi, [rsp]
        mov rsi, [r13 + SB_BUF]
        mov rdx, r14
        call sb_append
        mov rdi, r13
        call sb_free
        mov rdi, [rsp]
        call sb_finish
        add rsp, 16
        LEAVE
2:      mov rdi, r13
        call sb_reset
4:      test r12, r12
        jz 5f
        mov rdi, r13
        mov esi, '?'
        call sb_append_char
        dec r12
        jmp 4b
5:      mov rdi, r13
        call sb_finish
        add rsp, 16
        LEAVE
ENDF padded_hex

        .section .rodata
.Ls_0x: .asciz "0x"
        .text

# --- the signature database ---

# sig_db_lookup(selector) -> rax: the abi entry (name, inputs) of a
# selector (an integer below 2^32), or 0. The database comes later: without
# one, every selector is unknown.
FUNC sig_db_lookup
        mov rax, [rip + sig_db_hook]
        test rax, rax
        jz 1f
        jmp rax
1:      ENTER
        mov rbx, rdi
        call sigdb_load                 # (once: the state is kept)
        test eax, eax
        jz 2f
        mov rdi, rbx
        call [rip + sig_db_hook]
        LEAVE
2:      xor eax, eax
        LEAVE
ENDF sig_db_lookup

        .section .bss
        .align 8
        .globl sig_db_hook
        .hidden sig_db_hook
sig_db_hook: .quad 0                    # a function(selector) -> entry, once there is a database
        .text

# sig_of_hex(sigstr) -> rax: python's int(sigstr, 16) for the prefixes of
# a hex number that find_sig gets, or -1 when it isn't one that a selector
# could be (a sign, question marks, more than 8 digits)
FUNC sig_of_hex
        mov ecx, [rdi + N_DATA]
        lea rsi, [rdi + N_DATA + 4]
        cmp ecx, 2
        jbe 4f
        cmp word ptr [rsi], 0x7830      # "0x"
        jne 4f
        add rsi, 2
        sub ecx, 2
        cmp ecx, 8
        ja 4f
        xor eax, eax
1:      test ecx, ecx
        jz 3f
        movzx edx, byte ptr [rsi]
        sub edx, '0'
        cmp edx, 9
        jbe 2f
        sub edx, 'a' - '0'
        cmp edx, 5
        ja 4f
        add edx, 10
2:      shl rax, 4
        or rax, rdx
        inc rsi
        dec ecx
        jmp 1b
3:      ret
4:      mov rax, -1
        ret
ENDF sig_of_hex

# --- the params of an abi ---
#
# An input is a tuple (type, name) - or (type, name, components,
# indexed) when it has components (a tuple's: a list of inputs, or NIL
# when python's dict has no "components") or is indexed (an event's: 1,
# else 0). An abi entry is (name, inputs[, type]): the type ("function",
# "event"...) for the entries of the database.

# input_components(input) -> rax: its components (a list), or 0 (None)
FUNC input_components
        xor eax, eax
        cmp dword ptr [rdi + N_AUX], 3
        jb 1f
        mov rax, [rdi + N_DATA + 16]
1:      ret
ENDF input_components

# input_indexed(input) -> eax: python's `i.get("indexed")`, truthy
FUNC input_indexed
        xor eax, eax
        cmp dword ptr [rdi + N_AUX], 4
        jb 1f
        cmp qword ptr [rdi + N_DATA + 24], 3
        sete al
1:      ret
ENDF input_indexed

# canonical_type(kind, components) -> str: signatures.canonical_type -
# the type as in a signature: a tuple is its components in parentheses
FUNC canonical_type
        ENTER
        mov rbx, rdi
        mov r12, rsi
        test rsi, rsi
        jz 1f
        call sb_new
        mov r13, rax
        mov rdi, rax
        mov rsi, rbx
        mov rdx, r12
        call sb_append_canonical
        mov rdi, r13
        call sb_finish
        LEAVE
1:      mov rax, rbx
        LEAVE
ENDF canonical_type

# sb_append_canonical(sb, kind, components): canonical_type appended
FUNC sb_append_canonical
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        test r13, r13
        jz 8f
        mov rdi, r12
        lea rsi, [rip + .Ls_tuple]
        call str_startswith_c
        test eax, eax
        jz 8f
        # "(" + ",".join(canonical types of the components) + ")" + kind[5:]
        mov rdi, rbx
        mov esi, '('
        call sb_append_char
        xor r14d, r14d
1:      cmp r14d, [r13 + N_AUX]
        jae 2f
        test r14d, r14d
        jz 11f
        mov rdi, rbx
        mov esi, ','
        call sb_append_char
11:     mov rsi, [r13 + N_DATA + r14*8]
        mov rdi, rbx
        call sb_append_canonical_type
        inc r14d
        jmp 1b
2:      mov rdi, rbx
        mov esi, ')'
        call sb_append_char
        lea rsi, [r12 + N_DATA + 4 + 5]
        mov edx, [r12 + N_DATA]
        sub edx, 5
        mov rdi, rbx
        call sb_append
        LEAVE
8:      mov rdi, rbx
        mov rsi, r12
        call sb_append_str
        LEAVE
ENDF sb_append_canonical

# sb_append_canonical_type(sb, input): the canonical type of an input
FUNC sb_append_canonical_type
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov rdi, rsi
        call input_components
        mov rdx, rax
        mov rdi, rbx
        mov rsi, [r12 + N_DATA]
        call sb_append_canonical
        LEAVE
ENDF sb_append_canonical_type

# kind_array_split(kind) -> rax: the index of its last "[", -1 when it
# doesn't end with "]" (python's kind.endswith("]") and kind.rindex("["):
# a ValueError when there is none)
FUNC kind_array_split
        mov ecx, [rdi + N_DATA]
        test ecx, ecx
        jz 8f
        cmp byte ptr [rdi + N_DATA + 4 + rcx - 1], ']'
        jne 8f
1:      dec ecx
        js 9f
        cmp byte ptr [rdi + N_DATA + 4 + rcx], '['
        jne 1b
        mov eax, ecx
        ret
8:      mov rax, -1
        ret
9:      mov edi, E_VALUE
        lea rsi, [rip + .Ls_no_bracket]
        jmp err_throw
ENDF kind_array_split

# kind_count(kind, at) -> rax: the count between the "[" at `at` and the
# closing "]" - python's int(count) when count.isdigit() - or -1
FUNC kind_count
        mov ecx, [rdi + N_DATA]
        dec ecx                         # the "]"
        lea rdx, [rsi + 1]              # after the "["
        cmp rdx, rcx
        jae 9f                          # (empty: not isdigit())
        xor eax, eax
1:      cmp rdx, rcx
        jae 2f
        movzx r8d, byte ptr [rdi + N_DATA + 4 + rdx]
        sub r8d, '0'
        cmp r8d, 9
        ja 9f
        mov r9, 1 << 40
        cmp rax, r9
        jae 3f                          # (past what can be made: as big)
        imul rax, rax, 10
        add rax, r8
3:      inc rdx
        jmp 1b
2:      ret
9:      mov rax, -1
        ret
ENDF kind_count

# is_dynamic(kind, components) -> eax: signatures.is_dynamic - a param of
# the type is dynamic: in the head, only its offset
FUNC is_dynamic
        STACK_CHECK
        ENTER
        mov rbx, rdi
        mov r12, rsi
        lea rsi, [rip + .Ls_bytes]
        call str_eq_c
        test eax, eax
        jnz 8f
        mov rdi, rbx
        lea rsi, [rip + .Ls_string]
        call str_eq_c
        test eax, eax
        jnz 8f
        mov ecx, [rbx + N_DATA]
        cmp ecx, 2
        jb 1f
        cmp word ptr [rbx + N_DATA + 4 + rcx - 2], 0x5d5b      # "[]"
        je 8f
1:      mov rdi, rbx
        call kind_array_split
        test rax, rax
        js 3f
        # a static array, unless its count isn't one: of a dynamic type?
        mov r13, rax
        mov rdi, rbx
        mov rsi, rax
        call kind_count
        test rax, rax
        js 8f
        lea rdi, [rbx + N_DATA + 4]
        mov rsi, r13
        call str_new
        mov rdi, rax
        mov rsi, r12
        call is_dynamic
        LEAVE
3:      mov rdi, rbx
        lea rsi, [rip + .Ls_tuple]
        call str_eq_c
        test eax, eax
        jz 9f
        # without its components, where it ends isn't known
        test r12, r12
        jz 8f
        xor r13d, r13d
4:      cmp r13d, [r12 + N_AUX]
        jae 9f
        mov r14, [r12 + N_DATA + r13*8]
        mov rdi, r14
        call input_components
        mov rsi, rax
        mov rdi, [r14 + N_DATA]
        call is_dynamic
        test eax, eax
        jnz 8f
        inc r13d
        jmp 4b
8:      mov eax, 1
        LEAVE
9:      xor eax, eax
        LEAVE
ENDF is_dynamic

# head_words(vec, kind, name, components): signatures.head_words - the
# (type, name) of the words a param takes in the head of the calldata
# (all the elements of a static tuple or array, the offset to anything
# dynamic), pushed
FUNC head_words
        STACK_CHECK
        ENTER
        sub rsp, 48
        .set HW_VEC, 0
        .set HW_BASE, 8
        .set HW_COUNT, 16
        .set HW_I, 24
        mov [rsp + HW_VEC], rdi
        mov rbx, rsi
        mov r12, rdx
        mov r13, rcx
        mov rdi, rsi
        mov rsi, rcx
        call is_dynamic
        test eax, eax
        jnz .Lhw_word
        mov rdi, rbx
        call kind_array_split
        test rax, rax
        js 3f
        # a static array: the words of each of its elements
        mov r14, rax
        mov rdi, rbx
        mov rsi, rax
        call kind_count
        mov [rsp + HW_COUNT], rax
        lea rdi, [rbx + N_DATA + 4]
        mov rsi, r14
        call str_new
        mov [rsp + HW_BASE], rax
        mov qword ptr [rsp + HW_I], 0
1:      mov rax, [rsp + HW_I]
        cmp rax, [rsp + HW_COUNT]
        jae 9f
        mov rax, [rsp + HW_VEC]         # (python's list: a million words at
        cmp qword ptr [rax + VEC_LEN], 1 << 20  # most here, its MemoryError past)
        ja .Lhw_too_many
        # f"{name}[{idx}]"
        call sb_new
        mov r14, rax
        mov rdi, rax
        mov rsi, r12
        call sb_append_str
        mov rdi, r14
        mov esi, '['
        call sb_append_char
        mov rdi, r14
        mov rsi, [rsp + HW_I]
        call sb_append_u64
        mov rdi, r14
        mov esi, ']'
        call sb_append_char
        mov rdi, r14
        call sb_finish
        mov rdi, [rsp + HW_VEC]
        mov rsi, [rsp + HW_BASE]
        mov rdx, rax
        mov rcx, r13
        call head_words
        inc qword ptr [rsp + HW_I]
        jmp 1b
3:      mov rdi, rbx
        lea rsi, [rip + .Ls_tuple]
        call str_eq_c
        test eax, eax
        jz .Lhw_word
        # a static tuple: the words of its components, f"{name}.{c_name}"
        # (an unnamed one _param<idx + 1>)
        mov qword ptr [rsp + HW_I], 0
4:      mov rax, [rsp + HW_I]
        cmp eax, [r13 + N_AUX]
        jae 9f
        mov r14, [r13 + N_DATA + rax*8]
        call sb_new
        mov [rsp + HW_BASE], rax
        mov rdi, rax
        mov rsi, r12
        call sb_append_str
        mov rdi, [rsp + HW_BASE]
        mov esi, '.'
        call sb_append_char
        mov rsi, [r14 + N_DATA + 8]
        cmp dword ptr [rsi + N_DATA], 0
        je 5f
        mov rdi, [rsp + HW_BASE]
        call sb_append_str
        jmp 6f
5:      mov rdi, [rsp + HW_BASE]
        lea rsi, [rip + .Ls_param]
        call sb_append_c
        mov rsi, [rsp + HW_I]
        inc rsi
        mov rdi, [rsp + HW_BASE]
        call sb_append_u64
6:      mov rdi, [rsp + HW_BASE]
        call sb_finish
        mov [rsp + HW_COUNT], rax
        mov rdi, r14
        call input_components
        mov rcx, rax
        mov rdi, [rsp + HW_VEC]
        mov rsi, [r14 + N_DATA]
        mov rdx, [rsp + HW_COUNT]
        call head_words
        inc qword ptr [rsp + HW_I]
        jmp 4b
.Lhw_word:
        mov rdi, rbx
        mov rsi, r12
        call mk2
        mov rdi, [rsp + HW_VEC]
        mov rsi, rax
        call vec_push
9:      add rsp, 48
        LEAVE
.Lhw_too_many:
        mov edi, E_MEMORY
        lea rsi, [rip + .Ls_too_many]
        call err_throw
ENDF head_words

# calldata_params(inputs) -> list: signatures.calldata_params - the
# (type, name) of the words of the params, the i-th at 4 + 32 i in the
# calldata (python's dict of those positions)
FUNC calldata_params
        ENTER
        mov rbx, rdi
        call vec_new
        mov r12, rax
        xor r13d, r13d
1:      cmp r13d, [rbx + N_AUX]
        jae 2f
        mov r14, [rbx + N_DATA + r13*8]
        mov rdi, r14
        call input_components
        mov rcx, rax
        mov rdi, r12
        mov rsi, [r14 + N_DATA]
        mov rdx, [r14 + N_DATA + 8]
        call head_words
        inc r13d
        jmp 1b
2:      mov rdi, r12
        call vec_to_list
        LEAVE
ENDF calldata_params

# has_length(kind) -> eax: signatures.has_length - the data a param
# points to starts with its length
FUNC has_length
        ENTER
        mov rbx, rdi
        call is_str
        test eax, eax
        jz 9f
        mov rdi, rbx
        lea rsi, [rip + .Ls_bytes]
        call str_eq_c
        test eax, eax
        jnz 8f
        mov rdi, rbx
        lea rsi, [rip + .Ls_string]
        call str_eq_c
        test eax, eax
        jnz 8f
        mov rdi, rbx
        lea rsi, [rip + .Ls_array]
        call str_eq_c
        test eax, eax
        jnz 8f
        mov ecx, [rbx + N_DATA]
        cmp ecx, 2
        jb 9f
        cmp word ptr [rbx + N_DATA + 4 + rcx - 2], 0x5d5b      # "[]"
        jne 9f
8:      mov eax, 1
        LEAVE
9:      xor eax, eax
        LEAVE
ENDF has_length

        .section .rodata
.Ls_tuple:      .asciz "tuple"
.Ls_bytes:      .asciz "bytes"
.Ls_string:     .asciz "string"
.Ls_array:      .asciz "array"
.Ls_no_bracket: .asciz "ValueError: substring not found (a type ending with ] without [)"
.Ls_too_many:   .asciz "MemoryError: the words of a static array"
.Ls_dot_length2: .asciz ".length"
        .text

# --- the abis ---

# abi_of(hash) -> (name, inputs): signatures.make_abi's entry of a
# function - the signature database's for a selector (its unnamed inputs
# named), else "unknown<selector>" without inputs (or the name itself for
# "_fallback")
FUNC abi_of
        ENTER
        mov rbx, rdi
        lea rsi, [rip + .Ls_0x]
        call str_startswith_c
        test eax, eax
        jz .Lab_named                   # "_fallback", or an unknown selector
        lea rdi, [rbx + N_DATA + 4 + 2]
        call parse_hex_int
        mov rdi, rax
        call int_to_i64
        mov rdi, rax
        call sig_db_lookup
        test rax, rax
        jz 1f
        mov r12, [rax + N_DATA]
        mov rdi, [rax + N_DATA + 8]
        call fix_inputs
        mov rdi, r12
        mov rsi, rax
        call mk2
        LEAVE
1:      # ("unknown" + hash[2:], no inputs)
        call sb_new
        mov r12, rax
        mov rdi, rax
        lea rsi, [rip + .Ls_unknown]
        call sb_append_c
        mov rdi, r12
        lea rsi, [rbx + N_DATA + 4 + 2]
        call sb_append_c
        mov rdi, r12
        call sb_finish_intern
        mov rdi, rax
        xor esi, esi
        call mk2
        LEAVE
.Lab_named:
        mov rdi, rbx
        xor esi, esi
        call mk2
        LEAVE
ENDF abi_of

# fix_input_names(abi) -> abi: signatures.fix_input_names of its inputs
# - the unnamed ones called _param<n> (the rest of the entry as it is)
FUNC fix_input_names
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov rdi, [rbx + N_DATA + 8]
        test rdi, rdi
        jz 1f
        call fix_inputs
        cmp rax, [rbx + N_DATA + 8]
        je 1f
        # (the same entry with them)
        mov r12, rax
        mov edi, [rbx + N_AUX]
        shl edi, 3
        call arena_alloc
        mov r13, rax
        mov rdi, rax
        lea rsi, [rbx + N_DATA]
        mov edx, [rbx + N_AUX]
        shl edx, 3
        call memcpy@PLT
        mov [r13 + 8], r12
        mov rdi, rbx
        mov rsi, r13
        call mk_seq_like
        add rsp, 16
        LEAVE
1:      mov rax, rbx
        add rsp, 16
        LEAVE
ENDF fix_input_names

# fix_inputs(inputs) -> list: the inputs, the unnamed ones called
# _param<i + 1>
FUNC fix_inputs
        ENTER
        sub rsp, 16
        mov r12, rdi
        call vec_new
        mov r13, rax
        xor r14d, r14d
1:      cmp r14d, [r12 + N_AUX]
        jae 3f
        mov rbx, [r12 + N_DATA + r14*8]
        mov rcx, [rbx + N_DATA + 8]
        cmp dword ptr [rcx + N_DATA], 0
        jne 2f
        call sb_new
        mov [rsp], rax
        mov rdi, rax
        lea rsi, [rip + .Ls_param]
        call sb_append_c
        mov rdi, [rsp]
        lea rsi, [r14 + 1]
        call sb_append_u64
        mov rdi, [rsp]
        call sb_finish_intern
        mov [rsp + 8], rax
        # the input with that name
        mov edi, [rbx + N_AUX]
        shl edi, 3
        call arena_alloc
        mov [rsp], rax
        mov rdi, rax
        lea rsi, [rbx + N_DATA]
        mov edx, [rbx + N_AUX]
        shl edx, 3
        call memcpy@PLT
        mov rax, [rsp]
        mov rcx, [rsp + 8]
        mov [rax + 8], rcx
        mov rdi, rbx
        mov rsi, rax
        call mk_seq_like
        mov rbx, rax
2:      mov rdi, r13
        mov rsi, rbx
        call vec_push
        inc r14d
        jmp 1b
3:      mov rdi, r12
        mov rsi, [r13 + VEC_DATA]
        call mk_seq_like
        add rsp, 16
        LEAVE
ENDF fix_inputs

# abi_func_name(abi, flags) -> str: signatures.get_func_name - "name(type
# pname, ...)" (the names green when PF_COLOR; a tuple as the types it's
# made of, see canonical_type), or "name(?)"
FUNC abi_func_name
        ENTER
        mov rbx, rdi
        mov r12, rsi
        call sb_new
        mov r13, rax
        mov rdi, rax
        mov rsi, [rbx + N_DATA]
        call sb_append_str
        mov r14, [rbx + N_DATA + 8]
        test r14, r14
        jz 3f
        mov rdi, r13
        mov esi, '('
        call sb_append_char
        push r14
        push r14
        xor ecx, ecx
1:      cmp ecx, [r14 + N_AUX]
        jae 2f
        mov [rsp], rcx
        test ecx, ecx
        jz 11f
        mov rdi, r13
        lea rsi, [rip + .Ls_comma_sp]
        call sb_append_c
11:     mov rcx, [rsp]
        mov rsi, [r14 + N_DATA + rcx*8]
        mov rdi, r13
        call sb_append_canonical_type
        mov rdi, r13
        mov esi, ' '
        call sb_append_char
        mov rcx, [rsp]
        mov rax, [r14 + N_DATA + rcx*8]
        mov rdi, r13
        mov rsi, [rax + N_DATA + 8]
        lea rdx, [rip + C_GREEN]
        mov rcx, r12
        call sb_append_col
        mov rcx, [rsp]
        inc ecx
        jmp 1b
2:      pop r14
        pop r14
        mov rdi, r13
        mov esi, ')'
        call sb_append_char
        jmp 4f
3:      mov rdi, r13
        lea rsi, [rip + .Ls_lparen_q]
        call sb_append_c
4:      mov rdi, r13
        call sb_finish
        LEAVE
ENDF abi_func_name

# abi_name(abi) -> str: signatures.get_abi_name - "name(type,type)" (the
# canonical types) or "name(?)"
FUNC abi_name
        ENTER
        mov rbx, rdi
        call sb_new
        mov r13, rax
        mov rdi, rax
        mov rsi, [rbx + N_DATA]
        call sb_append_str
        mov r14, [rbx + N_DATA + 8]
        test r14, r14
        jz 3f
        mov rdi, r13
        mov rsi, r14
        call sb_append_signature_types
        jmp 4f
3:      mov rdi, r13
        lea rsi, [rip + .Ls_lparen_q]
        call sb_append_c
4:      mov rdi, r13
        call sb_finish
        LEAVE
ENDF abi_name

# sb_append_signature_types(sb, inputs): "(" + ",".join(canonical types)
# + ")"
FUNC sb_append_signature_types
        ENTER
        mov rbx, rdi
        mov r14, rsi
        mov esi, '('
        call sb_append_char
        xor r12d, r12d
1:      cmp r12d, [r14 + N_AUX]
        jae 2f
        test r12d, r12d
        jz 11f
        mov rdi, rbx
        mov esi, ','
        call sb_append_char
11:     mov rsi, [r14 + N_DATA + r12*8]
        mov rdi, rbx
        call sb_append_canonical_type
        inc r12d
        jmp 1b
2:      mov rdi, rbx
        mov esi, ')'
        call sb_append_char
        LEAVE
ENDF sb_append_signature_types

# abi_hashes_to(abi, selector) -> eax: supplement.hashes_to - the
# signature of the abi (its name and canonical types) hashes to the
# selector (an int below 2^32): as it is, or without its spaces (the
# selectors of the libraries of old compilers hash a storage pointer
# without its space, `getMin(uint32[]storage)`)
FUNC abi_hashes_to
        ENTER
        sub rsp, 32
        mov rbx, rdi
        mov r12, rsi
        call sb_new
        mov r13, rax
        mov rdi, rax
        mov rsi, [rbx + N_DATA]
        call sb_append_str
        mov rsi, [rbx + N_DATA + 8]
        test rsi, rsi
        jnz 1f
        xor edi, edi                    # (abi.get("inputs", []))
        xor esi, esi
        call mk_list
        mov rsi, rax
1:      mov rdi, r13
        call sb_append_signature_types
        mov rdi, [r13 + SB_BUF]
        mov rsi, [r13 + SB_LEN]
        mov rdx, rsp
        call keccak256
        call .Lht_check
        test eax, eax
        jnz 8f
        # without its spaces
        mov rsi, [r13 + SB_BUF]
        mov rcx, [r13 + SB_LEN]
        xor edx, edx                    # (in place: the text isn't needed after)
        xor r14d, r14d
2:      cmp r14, rcx
        jae 3f
        mov al, [rsi + r14]
        inc r14
        cmp al, ' '
        je 2b
        mov [rsi + rdx], al
        inc rdx
        jmp 2b
3:      cmp rdx, rcx
        je 9f                           # (no space: the same text)
        mov rdi, rsi
        mov rsi, rdx
        mov rdx, rsp
        call keccak256
        call .Lht_check
        test eax, eax
        jnz 8f
9:      mov rdi, r13
        call sb_free
        xor eax, eax
        add rsp, 32
        LEAVE
8:      mov rdi, r13
        call sb_free
        mov eax, 1
        add rsp, 32
        LEAVE
# a local: eax 1 when the first 4 bytes of the digest (abi_hashes_to's
# frame, 8 bytes up) are the selector
.Lht_check:
        mov eax, [rsp + 8]
        bswap eax
        xor ecx, ecx
        cmp rax, r12
        sete cl
        mov eax, ecx
        ret
ENDF abi_hashes_to

# sig_db_present() -> eax: there is a signature database
FUNC sig_db_present
        cmp qword ptr [rip + sig_db_hook], 0
        je 1f
        mov eax, 1
        ret
1:      jmp sigdb_load
ENDF sig_db_present

# event_abi(topic) -> abi or 0: prettify.event_abi - the abi of the event
# whose signature is topic, if it's known (the database is by the first
# 4 bytes: the whole signature must match)
FUNC event_abi
        ENTER
        sub rsp, 32
        mov rbx, rdi
        call is_int
        test eax, eax
        jz 9f
        mov rdi, rbx
        mov esi, 64
        call padded_hex
        mov r12, rax
        cmp byte ptr [r12 + N_DATA + 4], '?'
        jne 1f
        # more than 64 digits: python's int("??????????", 16), with a
        # database (without one, fetch_sig is never asked)
        call sig_db_present
        test eax, eax
        jz 9f
        mov edi, E_VALUE
        lea rsi, [rip + .Ls_invalid_literal]
        call err_throw
1:      mov rdi, r12
        xor esi, esi
        mov edx, 10
        call str_slice
        mov rdi, rax
        call sig_of_hex
        mov rdi, rax
        call sig_db_lookup
        test rax, rax
        jz 9f
        mov r12, rax
        cmp dword ptr [r12 + N_AUX], 3
        jb 9f
        mov rdi, [r12 + N_DATA + 16]
        lea rsi, [rip + .Ls_event]
        call str_eq_c
        test eax, eax
        jz 9f
        # topic.to_bytes(32): python's OverflowError for a negative one
        mov rdi, rbx
        call int_sign
        cmp eax, -1
        je .Lea_overflow
        call sb_new
        mov r13, rax
        mov rdi, rax
        mov rsi, [r12 + N_DATA]
        call sb_append_str
        mov rdi, r13
        mov rsi, [r12 + N_DATA + 8]
        call sb_append_signature_types
        mov rdi, [r13 + SB_BUF]
        mov rsi, [r13 + SB_LEN]
        call keccak_value
        mov r14, rax
        mov rdi, r13
        call sb_free
        mov rdi, r14
        mov rsi, rbx
        call values_equal
        test eax, eax
        jz 9f
        mov rax, r12
        add rsp, 32
        LEAVE
9:      xor eax, eax
        add rsp, 32
        LEAVE
.Lea_overflow:
        mov edi, E_OVERFLOW
        lea rsi, [rip + .Ls_negative_bytes]
        call err_throw
ENDF event_abi

        .section .rodata
.Ls_event:      .asciz "event"
.Ls_invalid_literal: .asciz "ValueError: invalid literal for int() with base 16"
.Ls_negative_bytes: .asciz "OverflowError: can't convert negative int to unsigned"
.Ls_0x_sig:     .asciz "0x"
        .text

# find_sig(sigstr, flags) -> str or 0: Loader.find_sig - the signature of
# a selector given as the first 10 characters of a hex number, formatted as
# "name(type name, type name)", the types gray when PF_COLOR (a tuple as
# the types it's made of: its selector is the hash of that)
FUNC find_sig
        ENTER
        sub rsp, 16
        mov rbx, rdi
        mov r12, rsi
        cmp dword ptr [rbx + N_DATA], 8
        jb .Lfs_none
        call sig_of_hex
        cmp rax, -1
        je .Lfs_none
        mov rdi, rax
        call sig_db_lookup
        test rax, rax
        jz .Lfs_none
        mov r13, rax
        cmp qword ptr [r13 + N_DATA + 8], 0
        je .Lfs_assert                  # assert "inputs" in a
        call sb_new
        mov r14, rax
        mov rdi, rax
        mov rsi, [r13 + N_DATA]
        call sb_append_str
        mov rdi, r14
        mov esi, '('
        call sb_append_char
        mov r13, [r13 + N_DATA + 8]     # the inputs
        mov qword ptr [rsp], 0
1:      mov rcx, [rsp]
        cmp ecx, [r13 + N_AUX]
        jae 2f
        test ecx, ecx
        jz 3f
        mov rdi, r14
        lea rsi, [rip + .Ls_comma_sp]
        call sb_append_c
3:      mov rcx, [rsp]
        mov rbx, [r13 + N_DATA + rcx*8]
        mov rdi, rbx
        call input_components
        mov rdi, [rbx + N_DATA]
        mov rsi, rax
        call canonical_type
        mov rdi, r14
        mov rsi, rax
        lea rdx, [rip + C_GRAY]
        mov rcx, r12
        call sb_append_col
        mov rdi, r14
        mov esi, ' '
        call sb_append_char
        mov rsi, [rbx + N_DATA + 8]
        cmp dword ptr [rsi + N_DATA], 0
        je 4f
        mov rdi, r14
        call sb_append_str
        inc qword ptr [rsp]
        jmp 1b
4:      # an unnamed input: _param<i+1>, as signatures.fix_input_names
        mov rdi, r14
        lea rsi, [rip + .Ls_param]
        call sb_append_c
        mov rdi, r14
        mov rsi, [rsp]
        lea rsi, [rsi*2 + 3]
        mov edx, 10
        call sb_append_int
        inc qword ptr [rsp]
        jmp 1b
2:      mov rdi, r14
        mov esi, ')'
        call sb_append_char
        mov rdi, r14
        call sb_finish
        add rsp, 16
        LEAVE
.Lfs_none:
        xor eax, eax
        add rsp, 16
        LEAVE
.Lfs_assert:
        mov edi, E_ASSERT
        lea rsi, [rip + .Ls_fs_assert]
        call err_throw
ENDF find_sig

        .section .rodata
.Ls_fs_assert: .asciz "find_sig: a signature without inputs"
.Ls_param:     .asciz "_param"
.Ls_lparen_q:  .asciz "(?)"
.Ls_unknown_n: .asciz "unknown"
        .text

# --- the parameters of the function being printed ---

# get_param_name(cd, flags) -> value: signatures.get_param_name - the name
# of a calldata parameter (a green string), or the ('cd', loc) itself
# (cleaned of its multiplications by 1 when loc isn't a number) when there
# is no name for it. A param is where the data it points to is (after
# the selector); an element of an array of words or of offsets is
# name[i].
FUNC get_param_name
        STACK_CHECK
        ENTER
        sub rsp, MATCH_BINDINGS_SIZE + 32
        .set GP_INPUTS, MATCH_BINDINGS_SIZE
        .set GP_PARAMS, MATCH_BINDINGS_SIZE + 8
        .set GP_KIND, MATCH_BINDINGS_SIZE + 16
        .set GP_NAME, MATCH_BINDINGS_SIZE + 24
        mov rbx, rdi
        mov r12, rsi
        mov rax, [r15 + CTX_FUNC]
        test rax, rax
        jz .Lgp_cd
        mov rax, [rax + FN_INPUTS]
        test rax, rax
        jz .Lgp_cd
        mov [rsp + GP_INPUTS], rax
        mov rdi, rax
        call calldata_params
        mov [rsp + GP_PARAMS], rax
        mov r13, [rbx + N_DATA + 8]     # loc
        mov rdi, r13
        call is_int
        test eax, eax
        jnz .Lgp_int
        mov rdi, rbx
        call cleanup_mul_1
        mov rbx, rax
        mov r13, [rbx + N_DATA + 8]
        # ('add', 4, ('param', name)), of a param whose data starts with its
        # length: name.length
        PAT rsi, "('add', 4, ('param', ':name'))"
        mov rdi, r13
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz 2f
        B rdi, 0
        call param_kind_of_name
        mov rdi, rax
        call has_length
        test eax, eax
        jz 2f
        B rdi, 0
        call value_str
        mov rdi, rax
        jmp .Lgp_length
2:      PAT rsi, "('add', ':int:offset', ('cd', ':int:point_loc'))"
        mov rdi, r13
        mov rdx, rsp
        call pat_match
        test eax, eax
        jz .Lgp_cd
        B rdi, 1
        call .Lgp_word                  # params[point_loc], or 0
        test rax, rax
        jz .Lgp_cd
        mov rcx, [rax + N_DATA]
        mov [rsp + GP_KIND], rcx
        mov rcx, [rax + N_DATA + 8]
        mov [rsp + GP_NAME], rcx
        cmp qword ptr [rsp], (4 << 1) | 1
        jne 3f
        mov rdi, [rsp + GP_KIND]
        call has_length
        test eax, eax
        jz 3f
        mov rdi, [rsp + GP_NAME]
        jmp .Lgp_length
3:      # an element of an array of words or of offsets: name[i]
        xor r14d, r14d                  # element: 0 (None), else its count
        mov rdi, [rsp + GP_KIND]
        call str_ends_brackets
        test eax, eax
        jz 4f
        # head_words(kind[:-2], name, the components of the param of that name)
        call vec_new
        mov r14, rax
        mov rdi, [rsp + GP_NAME]
        call param_components_of_name
        mov rcx, rax
        mov rax, [rsp + GP_KIND]
        mov esi, [rax + N_DATA]
        sub esi, 2
        lea rdi, [rax + N_DATA + 4]
        push rcx
        push rcx
        call str_new
        pop rcx
        pop rcx
        mov rdi, r14
        mov rsi, rax
        mov rdx, [rsp + GP_NAME]
        call head_words
        mov r14, [r14 + VEC_LEN]
        inc r14                         # (count + 1: 0 stays None)
4:      # offset >= 36 and (offset - 36) % 32 == 0
        B rdi, 0
        mov rsi, (36 << 1) | 1
        call int_cmp
        cmp eax, -1
        je .Lgp_cd
        B rdi, 0
        mov rsi, (36 << 1) | 1
        call int_sub
        mov r13, rax
        mov rdi, rax
        mov rsi, (32 << 1) | 1
        call int_mod
        cmp rax, 1
        jne .Lgp_cd
        # (kind == "array" or element is not None) and (element is None or
        # len(element) == 1)
        test r14, r14
        jnz 5f
        mov rdi, [rsp + GP_KIND]
        lea rsi, [rip + .Ls_array]
        call str_eq_c
        test eax, eax
        jz .Lgp_cd
        jmp 6f
5:      cmp r14, 2
        jne .Lgp_cd
6:      # f"{name}[{(offset - 36) // 32}]"
        call sb_new
        mov r14, rax
        mov rdi, rax
        mov rsi, [rsp + GP_NAME]
        call sb_append_str
        mov rdi, r14
        mov esi, '['
        call sb_append_char
        mov rdi, r13
        mov rsi, (32 << 1) | 1
        call int_floordiv
        mov rdi, r14
        mov rsi, rax
        mov edx, 10
        call sb_append_int
        mov rdi, r14
        mov esi, ']'
        call sb_append_char
        mov rdi, r14
        call sb_finish
        mov rdi, rax
        lea rsi, [rip + C_GREEN]
        mov rdx, r12
        call colorize
        jmp .Lgp_ret
.Lgp_length:
        # colorize(name + ".length", GREEN)
        mov r13, rdi
        call sb_new
        mov r14, rax
        mov rdi, rax
        mov rsi, r13
        call sb_append_str
        mov rdi, r14
        lea rsi, [rip + .Ls_dot_length2]
        call sb_append_c
        mov rdi, r14
        call sb_finish
        mov rdi, rax
        lea rsi, [rip + C_GREEN]
        mov rdx, r12
        call colorize
        jmp .Lgp_ret
.Lgp_int:
        # a param's word: its name
        mov rdi, r13
        call .Lgp_word
        test rax, rax
        jz .Lgp_cd
        mov rdi, [rax + N_DATA + 8]
        lea rsi, [rip + C_GREEN]
        mov rdx, r12
        call colorize
        jmp .Lgp_ret
.Lgp_cd:
        mov rax, rbx
.Lgp_ret:
        add rsp, MATCH_BINDINGS_SIZE + 32
        LEAVE
# a local: the (type, name) of the word at loc rdi (an int) of the params
# (get_param_name's frame 8 bytes up), or 0
.Lgp_word:
        test dil, 1
        jz 1f                           # (a big int: none)
        sar rdi, 1
        sub rdi, 4
        js 1f
        test rdi, 31
        jnz 1f
        shr rdi, 5
        mov rax, [rsp + 8 + GP_PARAMS]
        cmp edi, [rax + N_AUX]
        jae 1f
        mov rax, [rax + N_DATA + rdi*8]
        ret
1:      xor eax, eax
        ret
# a local, through the frame: python's names.get(name, "") - the kind of
# the last word of that name
param_kind_of_name:
        push rbx
        push r12
        push r13
        mov rbx, rdi
        mov r12, [rsp + 24 + 8 + GP_PARAMS]
        mov r13d, [r12 + N_AUX]
1:      dec r13d
        js 2f
        mov rax, [r12 + N_DATA + r13*8]
        mov rdi, [rax + N_DATA + 8]
        mov rsi, rbx
        call str_values_equal
        test eax, eax
        jz 1b
        mov rax, [r12 + N_DATA + r13*8]
        mov rax, [rax + N_DATA]
        jmp 3f
2:      xor eax, eax
3:      pop r13
        pop r12
        pop rbx
        ret
# a local, through the frame: the components of the last input of that
# name (python's {p["name"]: p.get("components")}.get(name)), or 0
param_components_of_name:
        push rbx
        push r12
        push r13
        mov rbx, rdi
        mov r12, [rsp + 24 + 8 + GP_INPUTS]
        mov r13d, [r12 + N_AUX]
1:      dec r13d
        js 2f
        mov rax, [r12 + N_DATA + r13*8]
        mov rdi, [rax + N_DATA + 8]
        mov rsi, rbx
        call str_values_equal
        test eax, eax
        jz 1b
        mov rdi, [r12 + N_DATA + r13*8]
        call input_components
        jmp 3f
2:      xor eax, eax
3:      pop r13
        pop r12
        pop rbx
        ret
ENDF get_param_name

# str_values_equal(a, b) -> eax: python's == of two values that may be
# strings of the arena (not interned): their texts compared
FUNC str_values_equal
        ENTER
        mov rbx, rdi
        mov r12, rsi
        cmp rdi, rsi
        je 8f
        call is_str
        test eax, eax
        jz 7f
        mov rdi, r12
        call is_str
        test eax, eax
        jz 9f
        mov rdi, rbx
        mov rsi, r12
        call str_eq
        LEAVE
7:      mov rdi, rbx
        mov rsi, r12
        call values_equal
        LEAVE
8:      mov eax, 1
        LEAVE
9:      xor eax, eax
        LEAVE
ENDF str_values_equal

# str_ends_brackets(str) -> eax: kind.endswith("[]")
FUNC str_ends_brackets
        xor eax, eax
        mov ecx, [rdi + N_DATA]
        cmp ecx, 2
        jb 1f
        cmp word ptr [rdi + N_DATA + 4 + rcx - 2], 0x5d5b
        sete al
1:      ret
ENDF str_ends_brackets

# value_str(v) -> str: python's str() of a value - the string itself, the
# repr of anything else
FUNC value_str
        ENTER
        mov rbx, rdi
        call is_str
        test eax, eax
        jnz 1f
        call sb_new
        mov r12, rax
        mov rdi, rax
        mov rsi, rbx
        call value_print
        mov rdi, r12
        call sb_finish
        LEAVE
1:      mov rax, rbx
        LEAVE
ENDF value_str

# --- colors (helpers.py) ---

        .section .rodata
        .globl C_HEADER, C_BLUE, C_OKGREEN, C_WARNING, C_FAIL, C_ENDC, C_BOLD, C_UNDERLINE, C_GREEN, C_GRAY, C_ASM, C_GREEN_BACK, C_BLUE_BACK
        .hidden C_HEADER, C_BLUE, C_OKGREEN, C_WARNING, C_FAIL, C_ENDC, C_BOLD, C_UNDERLINE, C_GREEN, C_GRAY, C_ASM, C_GREEN_BACK, C_BLUE_BACK
C_HEADER:     .asciz "\033[95m"
C_BLUE:       .asciz "\033[94m"
C_OKGREEN:    .asciz "\033[92m"
C_WARNING:    .asciz "\033[93m"
C_FAIL:       .asciz "\033[91m"
C_ENDC:       .asciz "\033[0m"
C_BOLD:       .asciz "\033[1m"
C_UNDERLINE:  .asciz "\033[4m"
C_GREEN:      .asciz "\033[32m"
C_GRAY:       .asciz "\033[38;5;8m"
C_ASM:        .asciz "\033[38;5;33m"
C_GREEN_BACK: .asciz "\033[42;1m\033[38;5;0m"
C_BLUE_BACK:  .asciz "\033[43;1m\033[38;5;0m"
        # the codes clean_color removes (C.every)
        .section .data.rel.ro
        .align 8
every_color:
        .quad C_HEADER, C_BLUE, C_OKGREEN, C_WARNING, C_FAIL, C_BOLD, C_UNDERLINE, C_GREEN, C_GRAY, C_ENDC, 0
        .text

# colorize(str, color_cstr, flags) -> str: helpers.color - the text
# between the color and ENDC when PF_COLOR (an empty text stays empty),
# else the text itself
FUNC colorize
        ENTER
        mov rbx, rdi
        mov r12, rsi
        test rdx, PF_COLOR
        jz 1f
        cmp dword ptr [rbx + N_DATA], 0
        je 1f
        call sb_new
        mov r13, rax
        mov rdi, rax
        mov rsi, r12
        call sb_append_c
        mov rdi, r13
        mov rsi, rbx
        call sb_append_str
        mov rdi, r13
        lea rsi, [rip + C_ENDC]
        call sb_append_c
        mov rdi, r13
        call sb_finish
        LEAVE
1:      mov rax, rbx
        LEAVE
ENDF colorize

# colorize_c(cstr, color_cstr, flags) -> str
FUNC colorize_c
        ENTER
        mov rbx, rsi
        mov r12, rdx
        call str_new_c
        mov rdi, rax
        mov rsi, rbx
        mov rdx, r12
        call colorize
        LEAVE
ENDF colorize_c

# sb_append_col(sb, str, color_cstr, flags): colorize, appended
FUNC sb_append_col
        ENTER
        mov rbx, rdi
        mov rdi, rsi
        mov rsi, rdx
        mov rdx, rcx
        call colorize
        mov rdi, rbx
        mov rsi, rax
        call sb_append_str
        LEAVE
ENDF sb_append_col

# sb_append_col_c(sb, cstr, color_cstr, flags)
FUNC sb_append_col_c
        ENTER
        mov rbx, rdi
        mov rdi, rsi
        mov rsi, rdx
        mov rdx, rcx
        call colorize_c
        mov rdi, rbx
        mov rsi, rax
        call sb_append_str
        LEAVE
ENDF sb_append_col_c

# clean_color(str) -> str: the text without the color codes
FUNC clean_color
        ENTER
        sub rsp, 16
        mov rbx, rdi
        call sb_new
        mov r12, rax
        lea r13, [rbx + N_DATA + 4]
        mov r14d, [rbx + N_DATA]
        add r14, r13                    # the end
1:      cmp r13, r14
        jae 5f
        cmp byte ptr [r13], 0x1b
        jne 3f
        # one of the codes?
        lea rcx, [rip + every_color]
2:      mov rsi, [rcx]
        test rsi, rsi
        jz 3f
        mov [rsp], rcx
        mov [rsp + 8], rsi
        mov rdi, rsi
        call strlen@PLT
        mov rdx, rax
        mov rdi, r13
        mov rsi, [rsp + 8]
        push rdx
        push rdx
        call strncmp@PLT
        pop rdx
        pop rdx
        mov rcx, [rsp]
        test eax, eax
        jnz 4f
        add r13, rdx                    # skip the code
        jmp 1b
4:      add rcx, 8
        jmp 2b
3:      mov rdi, r12
        movzx esi, byte ptr [r13]
        call sb_append_char
        inc r13
        jmp 1b
5:      mov rdi, r12
        call sb_finish
        add rsp, 16
        LEAVE
ENDF clean_color

        .section .note.GNU-stack,"",@progbits
