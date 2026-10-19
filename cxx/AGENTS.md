# The C++23 decompiler — rules for every worker

`cxx/` is a new EVM decompiler in C++23 (g++-14, `-std=gnu++23`): an
idiomatic, high-level re-implementation of the assembly decompiler of this
repository (`../src/*.s`, `../docs/DESIGN.md`), itself a port of the python
decompiler panoramix (`/home/claude/panoramix`, branch merge-branches). The
asm and python are references for the algorithms, not for the exact output.

## The user's rules

1. **No string processing inside the decompiler**, except for the strings
   that really come from the contract (revert messages, string constants:
   raw bytes, made text only when printed). Opcodes are integers: an EVM
   instruction is its exact byte (ADD = 0x01, SSTORE = 0x55), the
   decompiler's own operations (mask_shl, setmem, var...) come from 0x100
   (16 bits); the opcode lives in the node's header, the node holds only the
   arguments. The names the decompiler makes (variables, storage, params,
   labels) are integer ids, made into text only when printing. True / False
   / None are native immediates. No `"mem" in str(exp)`-style textual
   tricks of python: the real semantics only. No ordering by text.
2. **Every parser is a Ragel machine** (ragel 6.10, `-G2`, one machine per
   function). The bytecode is converted from ASCII hex to binary first;
   Ragel then works on the opcode bytes directly, the way Chrome's NaCl
   validator works on x86 bytes (`/home/claude/nacl/native_client/src/
   trusted/validator_ragel`). Where Ragel doesn't apply: `switch` on integer
   ids, never a comparison of names.
3. **Threads: the standard library's** (`std::thread`, `std::mutex`,
   `std::atomic`...), no pthread; anything POSIX isolated in a `*_posix.cpp`
   (a MinGW port will add `*_win32.cpp`).
4. **Always the same flags**: `-march=native -mtune=native -Ofast -flto
   -fmerge-all-constants -fweb` (and PGO later). The optimized builds (release, the PGO
   instrumented build, its training run, the PGO build) never use
   sanitizers: ASan/UBSan only in `VARIANT=debug`. `-Ofast` is `-ffast-math`:
   no floating point anywhere in the algorithms (python's few floats are
   gone: integers only). Never rely on two constants having distinct
   addresses.
5. **Correctness is validated by execution**, not by comparing texts with
   the asm: the contracts' bytecode runs in evmone, the decompiled result
   (the final internal trace, and the printed text reparsed on a sample) runs
   on the same inputs and the same world, and the effects must agree:
   return data / revert, storage writes, logs, external calls. Outputs may
   differ from the asm's; the decompilation must be at least as correct.
   The display style stays the asm's.
6. **Unit tests: native C++ with doctest.**
7. **Interfaces kept**: the command line and its options, the python module
   (without `_test`). The C API and the JSON format are free.
8. Protections against hostile contracts are kept: memory limit per
   function, timeouts, recursion depth, size caps (PANORAMIX_MAX_MEMORY,
   PANORAMIX_TIMEOUT...).
9. C++ is a higher-level language: classes, RAII, value types, std::optional,
   std::variant, structs instead of python's data tuples, a hierarchy of
   exceptions (Unsupported, MemoryLimit, Timeout, ...).

## Working together

- Worktree `/home/claude/wt-cxx` (branch cxx23). Do NOT commit, don't switch
  branches, never `git stash`. Absolute paths; don't `cd`.
- The machine has 2 CPUs shared by many workers: build only what you need,
  `-j2` at most, and don't run long jobs needlessly.
- Stay in your own files and directories; message the main session
  ("main") for anything shared, or a worker directly (its id) about its
  interfaces.
- Third-party code goes in `cxx/third_party/NAME` at a pinned version (a tag
  at least two weeks old), with a NOTICE (origin, version, license, local
  changes).
