# panoramix-asm — design notes

An x86-64 assembly port of the [panoramix](https://github.com/palkeo/panoramix)
EVM decompiler. The only Python left is a thin CPython wrapper
(`src/pymod.c`) that hands the bytecode to the library and returns the text.
The library depends on libc, GMP (integers) and, for the signature
database, liblzma. Everything else is assembly (GNU as, Intel syntax).

## Layout

    include/defs.inc      constants, struct offsets, macros (read this first)
    include/opcodes.inc   generated: OP_* ids of the well-known strings
    src/rt_mem.s          thread contexts, arena allocator, GMP memory hooks
    src/rt_node.s         values, tuples/lists (hash-consed), big ints
    src/rt_str.s          global string interning, string builders, formatting
    src/rt_print.s        python-repr-like printing of values (tests, debug)
    src/rt_log.s          logging (coloredlogs' format)
    src/loader.s          bytecode -> instructions, jumpdests
    src/api.s             the C-callable entry points (pan_*)
    src/main.s            the `panasm` command line tool
    src/pymod.c           the CPython module `panoramix_asm`
    tools/gen_opcodes.py  generates opcodes.inc / opcodes_table.s
    tests/                comparisons with the python implementation

Build: `make` (needs python3 headers for the module). `build/panasm`
is the CLI, `build/panoramix_asm*.so` the module.

## Conventions

- System V ABI everywhere. `r15` = the thread context (`CTX_*`) in all
  the decompiler code; it is never used for anything else. Code called
  back by foreign code (GMP's memory hooks) gets the context from a
  pthread key (`ctx_current`).
- `ENTER`/`LEAVE` give a standard frame with rbx, r12, r13, r14 free and
  the stack 16-byte aligned; `sub rsp, 16*k` for locals.
- Values are tagged words: `(n << 1) | 1` small ints, otherwise a node
  pointer (16-byte aligned), 0 = NIL. Nodes: 16-byte header (kind, aux,
  hash) + payload. See defs.inc.
- Tuples and lists are hash-consed per thread (`mk_seq`): equal
  structures are the same pointer, so structural equality is `cmp`,
  and memo tables can be keyed by pointer. Strings are interned
  globally. Big ints (`K_INT`, GMP mpz inside) are compared by value
  (`values_equal`), small ints are inline.
- Memory: each thread has an arena (mmap'ed chunks, bump allocation)
  holding every node made while decompiling one function, and GMP's
  allocations are routed to it. `arena_reset` frees it all at once.
  Text results are malloc'ed and freed by the caller (`pan_free`).
- Opcode strings (tuple heads like `add`, `mask_shl`, `if`...) carry an
  id in their node (`N_AUX`), so dispatch on a tuple's opcode is a jump
  table: `opcode_of(v)` then `jmp [table + rax*8]`. `LOADS reg, NAME`
  loads the string node of an opcode.

## Roadmap

1. [x] runtime: arena, hash-consing, ints, strings, logging, printing
2. [x] loader: disassembly (identical to `Loader.disasm()` on the corpus)
3. [ ] literal parser (python repr subset) for the tests
4. [ ] arithmetic: 256-bit EVM semantics, `is_zero`, `eval_bool`...
5. [ ] masks + algebra (`add_op`, `mask_op`, `lt_op`, `ge_zero`...)
6. [ ] symbolic stack (`Stack.simplify` / `cleanup`)
7. [ ] VM: nodes, symbolic execution, loops, merges, path conditions
8. [ ] function discovery, signature database (xz + json -> flat file)
9. [ ] whiles, simplify passes, folder, prettify, storage naming
10. [ ] threads: one per function, shared read-only loader
11. [ ] `decompile()` in the module, CLI parity with `python -m panoramix`

## Testing

`tests/compare_disasm.py` runs both implementations on a corpus of
`.hex` files. Later stages compare python `repr()`s of intermediate
structures (the printing in `rt_print.s` follows python's format for
that) and the final text.
