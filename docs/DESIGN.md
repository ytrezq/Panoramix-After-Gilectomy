# Panoramix after Gilectomy — design notes

An x86-64 assembly port of the [panoramix](https://github.com/palkeo/panoramix)
EVM decompiler. The only Python left is a thin CPython wrapper
(`src/pymod.c`) that hands the bytecode to the library and returns the text.
The library depends on libc, GMP (integers) and, for the signature
database, liblzma. Everything else is assembly (GNU as, Intel syntax).

## Layout

    include/defs.inc      constants, struct offsets, macros (read this first)
    include/opcodes.inc   generated: OP_* ids of the well-known strings
    src/rt_mem.s          thread contexts, arena allocator, compaction, GMP memory hooks
    src/rt_simd.s         the ISA detection and the vector loops (long hashes)
    src/rt_node.s         values, tuples/lists (hash-consed), big ints, value_import
    src/rt_str.s          global string interning, arena strings, builders, formatting
    src/rt_print.s        python-repr-like printing of values (tests, debug)
    src/rt_parse.s        python literals -> values (the tests)
    src/rt_log.s          logging (coloredlogs' format)
    src/rt_err.s          errors: python's exceptions (err_catch / err_throw)
    src/rt_map.s          pointer-keyed hash maps, memo tables
    src/rt_vec.s          growable arrays
    src/rt_io.s           files
    src/pyutil.s          python's sorts (CPython's comparison order), ordered dicts, sets
    src/matcher.s         the pattern matcher (matcher.py), PAT literals
    spec/evm.def          the instructions of the EVM, the decoder's source
    spec/evm_decoder.rl   the decoder's automaton (ragel): the instructions and the idioms
    src/decoder.s         the decoder: the automaton's tables (src/evm_dfa.s, generated)
                          run over the code - instructions, jumpdests, idioms
    src/decode_report.s   `panasm decode`: what the decoder finds in a code
    src/loader.s          bytecode -> the decoder's instructions, jumpdests, push values
    src/funcs.s           function discovery (Loader.run)
    src/arith.s           256-bit arithmetic, is_zero, eval_bool (core/arithmetic.py)
    src/algebra.s         add_op, mask_op, lt_op, ge_zero... (core/algebra.py)
    src/ranges.s          value_range: what an expression is as an integer, for any
                          value of its words - what decides the comparisons
                          (algebra.value_range, set_variables, _linear...)
    src/masks.s           to_mask, find_mask (core/masks.py)
    src/stack.s           the symbolic stack (stack.py)
    src/vmnode.s, vm.s    the symbolic VM (vm.py): nodes, jump tables of the opcodes
    src/vmrec.s           the recursive internal functions (vm.py's VM.internal,
                          replace_recursions): their calls, lines of the traces
    src/whiles.s          loops to whiles (whiles.py)
    src/memloc.s          memory locations (core/memloc.py)
    src/simplify_exp.s    simplify_exp and its helpers
    src/loops.s, cleanup.s, rewriter.s, simplify.s   the simplifier (simplify.py, postprocess.py)
    src/folder.s          the folder (folder.py)
    src/sigs.s            signatures (utils/signatures.py): the abis, get_param_name,
                          the params of tuples and arrays, the events of the logs
    src/sigdb.s           the signature database: abi_dump.xz -> a flat mmap'ed file,
                          built again when the dump changes (src/sha256.s: its version)
    src/prettify.s, pretty_line.s, pretty_mem.s   the printer (prettify.py): expressions
                          with python's precedences, lines and loops, memory data
    src/function.s        Function (function.py)
    src/sparser.s         the storage (sparser.py)
    src/runtrace.s        a trace run on concrete values (runtrace.py): what checks the
                          rewrite of a bytes getter (storage.bytes_getter)
    src/keccak.s          Keccak-256, the EVM's sha3 (eth_hash's keccak, runtrace's)
    src/contract.s        Contract (contract.py)
    src/safemath.s        the checked arithmetic of the asts as calls of the
                          contract's `def SafeMath:` functions (safemath.py)
    src/decompiler.s      decompile(): the thread pool, the contract's text (decompiler.py)
    src/data.s            python's decompilation.json: JSON text, or a binary form of
                          python's objects for the module
    src/explain.s         python's --explain: the traces of every stage, the traits
    src/fetch.s           an address's code from a node: web3's automatic provider,
                          JSON-RPC eth_getCode over HTTP/1.0 or an IPC socket
    src/api.s             the C interface (pan_*, include/panoramix_asm.h), exported
                          by build/libpanoramix_asm.so
    src/main.s            the `panasm` command line tool
    src/pymod.c           the CPython module `panoramix_asm`
    src/testapi.s         the hooks of the differential tests (`panoramix_asm._test`)
    tools/gen_opcodes.py  generates opcodes.inc / opcodes_table.s
    tools/gen_dfa.py, rl2asm.py   the decoder's generators: spec/evm.def into ragel
                          machines and opcode tables, ragel's automaton into tables
    tools/verify_dfa.py   the proof of the decoder's automaton (tools/evm_spec.py: the
                          instructions and the idioms by the letter of spec/evm.def)
    tools/psamp.c         a sampling profiler (perf_event_open's CPU clock, the
                          frames' return addresses), tools/psym.py its report
    tools/bench.py        the CPU time of a corpus, binaries compared: means of runs
    tools/prof_corpus.sh  the corpus under cachegrind, DynamoRIO (tools/bbfreq, a
                          client counting every instruction's executions:
                          tools/bbf_agg.py its report) or perf, several at a time
    tools/gen_htab.c      the storage's hash tables (keccak of slots), at build time
    tests/                comparisons with the python implementation

Build: `make` (needs python3 headers for the module). `build/panasm`
is the CLI, `build/panoramix_asm*.so` the module.

    panasm build-db panoramix/data/abi_dump.xz    # once: the signature database (built
                                                  # again when that dump, or $PANORAMIX_ABI_DUMP, changes)
    panasm decompile contract.hex [-j N] [--function NAME] [--no-color] [--json] [--verbose] [--explain]
    panasm decompile 0xADDRESS,other.hex      # an address's code from a node; lists, as python's
    panasm decode contract.hex                # what the decoder finds in the code
    python3 -c 'import panoramix_asm; print(panoramix_asm.decompile(open("contract.hex").read()))'

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
  globally, big ints (`K_INT`, GMP mpz inside) per context (the same
  table as the tuples), small ints are inline. Only the process-wide
  constants (made on the global context) need `values_equal`.
- Memory: each function is decompiled on a context of its own, whose
  arena (4 MiB chunks, bump allocation) holds every node it makes; GMP's
  allocations are routed to it. The context is freed at once when the
  function is done: its chunks go back to a pool (zeroed where they were
  used), where the next contexts take them from - fresh pages cost a
  fault each, which was half of the time on the bigger contracts; new
  chunks are aligned on 2 MiB and advised as huge pages. Text results
  are malloc'ed and freed by the caller (`pan_free`).
- Opcode strings (tuple heads like `add`, `mask_shl`, `if`...) carry an
  id in their node (`N_AUX`), so dispatch on a tuple's opcode is a jump
  table: `opcode_of(v)` then `JT_SWITCH` / `JT_CASE` / `JT_END` (a table
  of 32-bit offsets the assembler builds from the cases), and a
  membership test is a byte table (`OPSET_MEMBER` / `OPSET_END`,
  `IN_OPSET`, `OPSET_FUNC`). `LOADS reg, NAME` loads the string node of
  an opcode.
- `FUNC` functions are hidden; `API` ones (api.s) are the exported C
  interface.

## Errors, threads, strings

- Where python raises, `err_throw(code, msg)` unwinds to the innermost
  `err_catch` (setjmp-like, `rt_err.s`); every place python has a
  try/except has one. The test entry point reports them as
  `<exc code: message>`. Two come from the runtime: `E_RECURSION`
  (python's `RecursionError`) from `STACK_CHECK`, at the entry of every
  recursive function (`tools/recursion.py` finds them: the cycles of
  the call graph, callbacks included, and `make check` verifies that
  none lacks it), when the stack gets within 1 MiB of its end; and
  `E_MEMORY` (`MemoryError`) when a function's context passes
  `CTX_MEM_LIMIT`. A third one is python's time limit of a function
  (a SIGALRM there): a watchdog thread (`rt_watch.s`) takes the stack's
  limit of a worker past its deadline away, and the next `STACK_CHECK`
  throws `E_TIMEOUT` - which the handlers of python's `except
  Exception` let through, as python's `TimeoutInterrupt` is a
  `BaseException`. Where python lets an exception through (the
  postprocessing), `decompile_run` catches it and the text is the
  error's message; the decompilation runs on a thread of its own, with
  a stack as big as the workers' (64 MiB).
- `decompile()` runs the functions on a pool of threads: each function
  gets a context of its own, and its trace is imported into the main
  thread's context (`value_import`: hash-consed again, big ints copied)
  as soon as it is done, then the worker's arena is freed. The loader
  is shared read-only; strings are global (a spinlock).
- Two kinds of strings: interned ones (global, forever: opcodes, names
  that go into expressions - equal text, same node) and arena strings
  (`str_new`: the text being built for display, freed with the arena).
  Anything compared by pointer inside expressions must be interned.
- Python's floats appear in a few places (2 ** shl below zero, in
  prettify and sparser's mask_to_mul); they are carried as the interned
  text of their repr, flagged `STR_FLOAT` (printed bare, parsed from the
  tests' literals), which is all that is done with them.
- The top byte of a node's hash holds the "mention" flags (`HF_MEM`,
  `HF_MSIZE`, `HF_STORAGE`): which of these words a value contains
  anywhere in its tree. A string gets them when it is made (one
  table-driven pass over its text, which also gives `STR_VOLATILE`),
  `hash_seq` ORs them up. `mentions(exp, HF_x)` is what python does with
  `"mem" in str(exp)` (a walk, every time): the simplifier asks it
  millions of times.
- The postprocessing's work of every function runs on threads too, as
  many as the decompilation's: the folds of `make_asts` (`fold_many`:
  each on a context of its own, its result imported as it comes) and
  the printing (`print_many`, which the json and the text then take as
  they are: each function printed from a copy of it on a context of its
  own - the printer compares what it makes with what it reads by
  pointer, so the copy's values are imported there -, the text made a
  string of the main context after). The iterations read the main
  context, which nobody writes meanwhile (`par_for`: its thread waits).
  What is left on one thread is the storage's analysis and the rewrites
  of the asts, which take the whole contract.
- The folder (`fold_isolated`) runs on a context of its own too, its
  garbage going with that context; past 1 GiB the trace is left
  unfolded, as python does when folding fails. The corpora's folds take
  24 MiB at most. Its paths are folded on stretches of them
  (`fold_stretches`, as python's `fold_paths` now): each level of the
  recursion takes the same lines off the beginnings or the ends of all
  its paths, which python sliced, copying what was left of them - for n
  nested ifs (n paths of up to n lines, each level a line less) n^3 of
  the memory (1 GiB at 700 levels) and of the time, where the stretches
  (a start and a trim for all the paths of a level) take the n^2 of the
  paths themselves: 4000 levels, the most the VM's rounds go to, in
  0.2 s and 200 MiB. The paths with a line that's a list or an or, which `folder_or`
  and `folder_and` expand, are folded as lists (`fold_path_lists`,
  python's algorithm, as python does); an or that isn't of two groups of
  sides, each beginning with its line, too (`fold_or`, which fails on
  it).
- Python's floats: `2 ** k` for a negative k (the masks' printing), as
  the shortest decimal that reads back as the double (`float_repr`,
  python's repr), carried as a string flagged `STR_FLOAT`.
- The comparisons (`ge_zero`, `lt_op`, `le_op`, `max_op`...) are decided
  by `value_range` (src/ranges.s) and nothing else, as python's are since
  the PR's rewrite: the variants of an expression (`add_ge_zero`, which
  tried 0 and 2^230 for each word) are gone, with their scratch numbers.
  The ranges are remembered per expression and per top (`MEMO_VR_W`/`_M`,
  `MEMO_TR_W`/`_M`, `MEMO_UNCHECKED`), the memo tables forgotten when what
  they rest on changes (`set_variables`, python's `clear_caches`) - all of
  them but `mask_op`'s, whose python cache (`mask_dict`) isn't one of the
  cleared ones.

## Roadmap

1. [x] runtime: arena, hash-consing, ints, strings, logging, printing
2. [x] loader: disassembly (identical to `Loader.disasm()` on the corpus)
3. [x] literal parser (python repr subset) for the tests
4. [x] arithmetic: 256-bit EVM semantics, `is_zero`, `eval_bool`...
5. [x] masks + algebra (`add_op`, `mask_op`, `lt_op`, `ge_zero`...)
6. [x] symbolic stack (`Stack.simplify` / `cleanup`)
7. [x] VM: nodes, symbolic execution, loops, merges, path conditions
8. [x] function discovery, signature database (xz + json -> flat file)
9. [x] whiles, simplify passes, folder, prettify, storage naming
10. [x] threads: one per function, shared read-only loader
11. [x] `decompile()` in the module, CLI parity with `python -m panoramix`
12. [x] vectorization where it pays, chosen from the ISA at run time
    (`rt_simd.s`: cpuid + xgetbv; `PANORAMIX_ISA=scalar|sse2|avx2|avx512`
    forces a level). What pays is little: the profile is tree walks over
    small tuples (pointer chasing) and the hash-consing of them, and the
    only long loops are the hashes of the traces (lists of hundreds of
    lines), done 8 elements a step with AVX-512 (`vpmullq`,
    `vpgatherqq`, `vprolq`) or 4 with AVX2, and the scan of the text of
    every string made for the mention flags (`str_scan_flags`: the
    printed lines, hundreds of bytes), 32 bytes a step with AVX2 (16 with
    SSE2, the baseline every x86-64 has) - the
    positions where the first two bytes of one of the names are, found
    with `vpcmpeqb` and checked one by one (a third of the scalar
    loop's instructions). The wins came from the algorithms instead,
    see below.
13. [x] memory: the hash-cons table gives one node per distinct value on
    a thread, and `ctx_compact` drops the garbage of the rewrites between
    the rounds of `simplify_trace` once the arena passes 256 MiB (the
    trace is copied into a fresh arena, the comparison memos with it).
    The VM's rounds reuse their scratch (`merge_branches`' nodes by
    jump destination, `find_nodes`' stack): python's lists are garbage
    at the end of each call, an arena's would stay (3 GB over the 4000
    rounds of a contract the fuzzer mutated).
14. [x] python's `decompilation.json` (`data.s`): `decompile_bytecode`
    in the module gives python's `Decompilation` (text, asm, json - the
    json as python's own objects, through a binary form the module
    reads), `pan_decompile_data` and `panasm --json` its JSON text.
15. [x] no abort where the system runs out of memory: a context, a
    chunk, a hash-cons table that can't be had fail the function (or
    the fold, or the call of the C interface) as python's MemoryError
    would, and the process lives on (`robustness.sh` decompiles under
    address space limits). So does what the C allocator refuses
    (`xmalloc` and the like: the string builders, the interned strings,
    the loader, the signature database): python's MemoryError where the
    thread's own context has a handler for it (`xalloc_throw`), the locks
    of the string table and of the signature database's loading released
    on the way, a builder's capacity changed only once it's had; a
    function that failed for want of memory may not even get its name
    interned, and is reported under its selector then. Fatal only where
    nothing can take it.
    Sharing the table across threads (a lock-free one, with a global
    arena) was considered and rejected: `mk_seq` is the hottest
    function, and a global arena could never be freed per function,
    which is what keeps the memory bounded (~300 MiB per thread on the
    worst contracts of the corpus, where python takes GBs).
16. [x] python's `--verbose` and `--explain` (which python reads from
    `sys.argv`, anywhere). With either, the VM puts lines of assembly in
    its traces before every instruction it runs (`vm_trace_asm`): the
    stack, prettified - through python's `str.format` with no argument,
    so a stack holding a string constant with a lone brace makes the
    function fail, as in python -, an empty line, `[pc] op` and the
    parameter; they go through the whole simplifier as lines like any
    other (they change what python finds - no function is a constant
    any more, nor "not payable": its first line is no longer the check
    of the value sent - and the port finds the same), and come out as
    comments. With `--explain` also before the instructions that end a
    node, and `explain(title, trace)` prints the trace after every stage
    (`make_ast` and `pprint_logic`, unless it is the trace printed last:
    python's global `prev_trace`) and `explain_traits` what
    `Function.analyse` found; the assembly is dropped again after the
    first trace. Python prints as it goes, one function after the other;
    here each job prints into a builder of its own, and `decompile()`
    concatenates them in the order of the jobs, dropping a job's first
    trace when it equals the last one of the job before (both imported
    into the main context: they may hold VM nodes, whose copies keep
    their identity). `ctx_compact` carries the two traces the job keeps
    for this. The command line prints it before the text,
    `pan_decompile_data` gives it apart (`pan_output.explain`), the
    module prints it on `sys.stdout` and gives it as `.explain`.
    Interned strings being global, the lines of assembly stay in the
    string table for the life of the process. `--repr` and `--returns`
    (python's library reads them from `sys.argv` too; its command line
    refuses them) print each function's trace (`pprint_repr`,
    `format_exp`) and its returns after its text.

17. [x] python's `decompile_address` and the rest of its command line:
    an address (`0x` and 40 hex digits: `len(arg) == 42`, python's test)
    is fetched with `eth_getCode` at "latest" from the provider web3's
    `AutoProvider` finds (`fetch.s`): `$WEB3_PROVIDER_URI` (`file://` -
    an IPC socket - or `http://`; another scheme is python's
    NotImplementedError), else the first default IPC socket that exists
    (geth's, parity's, trinity's), else `$WEB3_HTTP_PROVIDER_URI` or
    `http://localhost:8545`, each tried when the one before can't be
    reached, with web3's 10 s. JSON-RPC over the unix socket (the answer
    read until it is a whole JSON value: geth keeps the connection), or
    POSTed in HTTP/1.0 (the server closes after its answer; a chunked
    one is put together anyway; requests' messages for the 4xx and
    5xx); the answer's `result` taken with a small JSON scanner, its
    `error` reported. No TLS nor websockets (a message says so). The
    argument may be a comma-separated list, decompiled in turn. The
    module has `decompile_address` (ConnectionError when the code can't
    be had), the C interface `pan_fetch_code`.

18. [x] the decoder, Native Client's way: see below.

19. [x] SafeMath (`safemath.s`, python's `safemath.py`): the checks a
    contract makes of its arithmetic before it uses the result -
    OpenZeppelin's SafeMath and ds-math (solidity < 0.8, inlined),
    solidity's own since 0.8 (`Panic(17)`, `Panic(18)`), the check of a
    division of solidity < 0.8 (an invalid opcode), Vyper's - each a
    function of the contract's `def SafeMath:` block, the result where
    it's used after them a call (`SafeMath.add(a, b)`, a message that
    differs from the other calls' its last argument). It runs on the
    asts once they're folded, on the main context (`contract_safemath`,
    after `make_asts`): the asts there are hash-consed in one table, so
    python's comparisons of the conditions with the forms of each check
    (`cond in (("lt", res, a), ...)`) are a tuple made and a pointer
    compared (`sm_in3`). Where python keys dicts by the checks (one
    function for each other operation and its checks), the keys are the
    hash-consed tuples themselves, looked up in a vector (a contract has
    a few); the messages are interned strings, compared by pointer too.
    An error (python's `except Exception`) leaves the asts as they are,
    the block empty, and logs it, as python does.

20. [x] recursive internal functions (`vmrec.s`, python's `VM.internal`
    and `replace_recursions`): the call of an internal function in its
    own call isn't unrolled until the VM stops - the EVM's stack of 1024
    words is what bounds such a recursion at run time, not anything the
    VM could see -, it's a line, `('internal', entry, args, results)`,
    after which the VM goes on where the call returns, variables for
    its results on the stack, the state as a call may leave it (what's
    known of the storage and of the memory forgotten, a `delegatecall`'s
    snapshot). A node is such a call (`vm_recursion_of`) when an ancestor
    started at the same jump destination with the address its call
    returns to - the topmost jump destination of its stack - on the
    node's stack, all below that the same and as many words above it;
    the function's entry is the outermost node of the ancestor's call
    that the node's call has too (not a block the first one jumps to,
    which would make what it pushes before arguments), its params the
    words above the address there, its results the words one of its
    calls left where it returned (none returned yet: the recursion is
    unrolled another level - and one that never returns, but by
    reverting, is unrolled as it was before), its frame the words
    between two of its entries, printed in its header (`# recursive, a
    call takes K of the 1024 words of the stack`). Once found, the calls
    of it the VM explored already are explored again as lines
    (`vm_replace_recursions`, between `replace_loops` and
    `continue_loops`; the loops found may be gone with them:
    `VM_LOOPS_STALE`). Each one is decompiled apart, as python's waves
    do: those the functions of the abi found, by entry, then those
    found by these, and so on, a batch of jobs each (`decompile`:
    `JB_INTERNAL`; the records found merged in the order of the jobs,
    those of the functions made only, `dc_merge_found`); its VM knows
    only itself, starts at its entry with its params, `('param',
    '_paramN')`, above `RETURN_ADDRESS` (`VM_INSIDE`: nothing ran
    before, nothing is known), and a jump to that address is its end,
    `('leave', values)`. What the VM found leaves its context in a
    buffer (`vm_found_buffer`): the compaction of the context drops the
    VM. The postprocessing takes them after the functions (the storage,
    the asts, the SafeMath; not the parameters, which have their names
    already); they're printed after the regular functions, under the
    calldata as it is (python's `_func` cleared: whichever function was
    printed before isn't theirs), and given in the json's `internal`. A
    function calling one isn't read-only; the passes over the memory
    take the line as a call - one that may read and write any memory
    but solidity's scratch space, which is read where it's written.

## The decoder

The bytecode isn't decoded by a loop written by hand but by an automaton
made from a description of the instructions, as Native Client's
validator decodes the machine code it lets run. `spec/evm.def` has an
opcode a line - its name (python's: what the disassembly prints), its
immediate's size, the words it takes and gives, the fork it came with.
`tools/gen_dfa.py` makes it a ragel machine for each instruction
(`spec/evm_insns.rl`: the opcode, then the immediate's bytes; `unknown`
for the bytes that aren't opcodes, python's `UNKNOWN`) and the tables of
what the decoder reads of an opcode (`src/evm_ops.s`: its kind, its
immediate's size, a dup's or a swap's n, its name). `spec/evm_decoder.rl`
puts the machines together: an instruction starts on its opcode and ends
on its immediate's last byte (the actions `insn_start`, `insn_end`),
the instructions one after the other, and among them the idioms - NaCl's
superinstructions: a push then a jump or a jumpi (`static_jump`,
`static_jumpi`: where the jump goes is known), solc's comparison of the
selector with a function's (`selector`: dup1, push4, eq, a push of the
destination, jumpi), solidity's free memory pointer set first (`fmp`:
mstore(0x40, v), v a push1 of 0x60 at least, where the code begins).
Ragel makes the automaton - 51 states: the bytes left of an immediate
are counted down, the same states for every push -, `tools/rl2asm.py`
makes tables of it (ragel's XML, `ragel -x`): for each state the mask of
a byte (0 when one transition goes for every byte, as in an immediate)
and the index of its transitions, for each transition the next state
and the actions on it, 12 KiB in all (`src/evm_dfa.s`, kept in the
repository: `make dfa` makes them again, with ragel). `decoder.s` runs
them: a byte, a lookup, and the actions when there are some - an
instruction's entry at its start, its parameter at its end, an idiom
noted with the index of its last instruction. A push the end of the
code cuts is the only instruction open at the end: its missing bytes
are zeroes, as the EVM reads them (and python's PR). The idioms change
nothing of what is decoded: the automaton follows every way the
instructions so far can be parts of idioms at once (ragel's subset
construction), and an idiom's action is on its last instruction's last
byte.

What it decodes is proven, as NaCl proved its validator's automaton
(`tools/verify_dfa.py`, run by `make dfa-check`): every state has a
transition for every byte; from every state an instruction can end in,
every instruction - every opcode, every value of its immediate, the
values the automaton and the idioms don't tell apart taken as one: they
lead to the same - starts on its opcode, ends on its last byte and only
there, an idiom's action only where an instruction ends; and the idioms
the automaton ends with an instruction are the ones the patterns of
`tools/evm_spec.py` (the spec by the letter: a few lines of python)
say end there, for any instructions before - a walk of the pairs (the
automaton's state, the beginnings of the idioms the last instructions
are), each pair with every instruction. There are 9 such pairs: the
automaton's state, where an instruction ends, is exactly what the
patterns need to know of the past. Changes of the grammar that break
any of this - an idiom's action a byte early, the destination of a
selector pushed by a push5, a byte missing from `unknown`, an
instruction's end on every byte - are caught (tried). `make dfa-check`
also compares the tables in the repository with the ones ragel makes
now, and `tests/test_decoder.py` the decoder itself with the spec's
decoding and with python's `Loader.load_binary` - every code of one and
two bytes, every opcode cut at every length, random codes dense with
the idioms' instructions, the corpora -, the tables it runs with
ragel's automaton byte by byte, and `panasm decode` with a report made
from the spec.

What python's decoder got wrong - a push the end of the code cuts,
Cancun's opcodes (`tload`, `tstore`, `mcopy`, `blobhash`,
`blobbasefee`), Osaka's CLZ (`0x1e`: `clz(x)`, the leading zero bits of
the word, 256 for 0 - computed for a number, 0 to 256 for the
comparisons) -, python's PR and the spec have right (CLZ as an
exception to the PR's opcode table taking no new instruction: it is the
EVM's since Osaka). The free memory
pointer's idiom spares the loader its run of the stack
(`sets_free_memory_pointer` would end on the same mstore with the same
answer). `panasm decode` prints what the decoder found - NaCl's `ncval`
for the EVM: the code's size, its instructions and jumpdests; the free
memory pointer set first; a push the end of the code cuts; the bytes
that aren't opcodes; the jumps to a number, and those to a place that
isn't a jumpdest (the EVM's jump fails there); the jumps to a computed
place; the functions solc's dispatcher compares the selector with.

## Testing

`make check` runs the C example, `tests/run_corpus.sh`,
`tests/robustness.sh`, `tests/test_watchdog.py`, `tests/test_json.py`,
`tests/test_verbose.py` and `tests/test_fetch.py`.
The first compares the 30 contracts of
`tests/corpus` (mainnet bytecode, see `SOURCES`) and the programs of
`tests/synthetic` (each one a difference the port had, and the
recursive internal functions of `recursion.sol`, compiled) with python's
output in their `expected` directories (pypy's `python -m panoramix`,
colors removed, with the signature database, which the script builds
from panoramix's `data/abi_dump.xz`). The second feeds it inputs that
must not take it down (thousands of nested ifs, a 20000-deep
expression, a function past its memory limit). The third checks that a
pass that would take forever (a random trace whose simplification
doubles an expression at every variable inlined) is cut at its deadline
by the watchdog, and cuts a real simplification at deadlines all along
it, with a compaction at every round (`PANORAMIX_COMPACT_MIB=1`, the
arena's size past which `simplify_trace` compacts): a compaction cut
midway puts the old arena back (`ctx_compact` has a handler), and every
call comes back whole or with the timeout, on a context that stays
sound. The corpus gives the same text with `PANORAMIX_COMPACT_MIB=1`.
The last compares the module's `decompile_bytecode` - the text, the
disassembly, and python's `json` object for object (a tuple isn't a
list, `True` isn't 1) - and `panasm --json` (against `json.dumps`) with
python's `decompile_bytecode` on the corpus, whose results `make
json-expected` pickles (pypy, `tests/gen_json_expected.py`).

`tests/validate.sh [--quick] [SEED]` is what a change goes through
before it is committed: the corpus and the synthetic programs - and the
npm corpus below when `$NPM_CORPUS` (its `.hex` files) and `$NPM_REFS`
(pypy's texts, `NAME.pan`) are given - as they are, with the VM's checks
(`PANORAMIX_CHECK_LCA=1`) and with a compaction at every round; the
random unit tests below with SEED (the day of the year by default); the
differential tests of the VM, the whiles and the simplifier on the
corpus (an hour, left out by `--quick`, which takes ten minutes); `make
check`. A line per step, with its time and the last line of its output
(the whole of it in `build/validate/`); the status is 1 when a step
failed.

`tests/difffuzz.py SEED COUNT` is a differential fuzzer: random
solidity-like programs (a selector dispatch; functions of storage and
memory writes, ifs, requires, loops, logs, calls, returns over random
expressions; for half of them internal functions, dynamic arrays,
calldata copies, static calls and the signed and modular operations)
decompiled by pypy and by the port, the texts compared, the programs
that differ kept in `build/difffuzz`; with `--mutate`, small contracts
of the corpora with a few instructions changed instead. It found the
loops without an exit condition, masks with offsets past 2^62, python's
floats in `Mask(-744, ...)`, the TypeErrors python raises on parameters
whose size is an expression (a crash here), and an `except
AssertionError` that caught everything. Python's timeouts make a case
inconclusive.

The random unit tests (`tests/test_algebra.py` - with `BIG=1`, masks
with numbers past 2^62 -, `test_arith.py`, `test_memloc.py`: the
memory model, the stores and setmems of several parts that read what the
others write among them; `test_rewriter.py`: datas with arrays, padded or
not, and the ifs on the lengths of strings; `test_stack.py`, `test_simplify_exp.py`, `test_prettify_random.py`,
`test_ranges.py`: what an expression is as an integer - `value_range`,
the comparisons it decides - under the states of `set_variables` (a
trace's variables, its small words) and both free memory pointer
assumptions; `test_conds.py`: what a condition says of what it compares,
the mins of the ifs, the results of the precompiled contracts, the small
words of random traces;
`test_fold_random.py`: paths sharing beginnings and endings, some in
two groups the folder's `fold_or` splits, through `fold_paths` and
`fold_path_lists`; the paths of traces whose ifs nest hundreds deep, and
the fold of traces nesting them a thousand deep;
`test_safemath.py`: asts with the checks of every operation, right and
wrong, one after the other (a library's and the compiler's), failing in
every way, their results used after lines that change what they read or
not, in branches and loops - the asts rewritten and the block's lines
(and, with `PANORAMIX_ASTS`, the asts of contracts, pickled);
`test_trace_random.py`: random traces - the lines of the VM, loops
included - through every pass of the simplifier and the whole
`simplify_trace`; a trace on which python takes more than `PY_LIMIT`
seconds, an expression doubling at every round, is skipped;
`test_runtrace.py`: random traces run on values by both machines, in
worlds made as `storage.bytes_tail` makes them - how a run ends, its
data, its steps, its memory's length, its variables, or its exception -,
one machine reset between the calldatas of a case, as storage would
reuse it; `test_keccak.py`: the digests of random bytes, the rate's
boundaries always)
take a seed; run over many seeds, they found the negative exponents of
`exp` (python's modular inverse), the order of the terms of a max
(python sorts them by `str()`, which has no quotes around a string), an
assertion of `flatten_adds`, a `try_add` that gives a number (python's
assertion in `add_op`, a crash here), rules of `simplify_exp` that
read numbers past 2^62 as small ones, conditions that simplify to None
(`mem[x len 0]`: python's `eval_bool` can't decide them, the port took
them for true), the ValueError of a negative shift, and the size python
gives a number written to memory (the bytes it needs only past 2^256,
never for a negative one). The cases they found are kept in their
`REGRESSIONS` lists. `tools/tmin.py PASS FILE` shrinks a trace or an
expression on which a pass differs. `PANASM_BUILD` points the tests to
another copy of the module (a fixed one, for a campaign that runs while
the build changes).

Every layer also has a differential test against the python
implementation on the corpus (`tests/test_*.py`, run with the system
python3, the module in `build/` and the python repository in
`$PANORAMIX_PY` or next to this one): the raw traces of the VM, the
functions found, the whiles, every simplifier pass on every corpus
trace, the folder, every sub-expression through prettify with every
combination of its flags, the function analysis, the whole contract
postprocessing; and the names the VM gives its variables when a function
is given the dispatcher's (`test_vm_names.py`, on small programs). `tests/compare_output.py` compares the final text with
`decompile_bytecode`'s (both without the signature database);
`corpus/run_one.sh` produces the references with the database, from
pypy, to diff against `panasm decompile --no-color`.

The function-level code - `Function`, the postprocessing's short
circuits, the folder - is also compared on python's own inputs, whatever
the port's VM and simplifier do meanwhile: `tests/gen_function_inputs.py`
(pypy) records what reached `Function(hash, trace)` in python's whole
decompilation of a contract (with the abi python had then, from the
signature database), the storage names `rename_params` got, and the
traces `make_ast` folded, into `build/fn_inputs/`; `test_function.py`
(each trace with that abi, without one, with made-up ones, then
renamed), `test_postprocess.py` and `test_folder.py` feed them to both
sides. `test_function_random.py` takes random traces made for the
checks of the params (`require x == address(x)`), the params guessed
from the uses of the calldata, the check of the value sent (an or, after
setmems), the constants and the getters; `test_postprocess.py` random
ifs whose branches set a variable (`logical`). The storage is compared
on python's own traces too: `tests/storage_capture.py` (pypy) records
what python's `storage.rewrite_functions` is given - `make storage-caps`,
into `build/storage_caps/` - and `test_storage.py` runs both sides'
functions of the storage on it, random inputs around it, then the
storage of each whole contract.

`make coverage` builds `build/cov/` - the tool and the module - with a
counter of the calls of every function (`COV_COUNT` in `FUNC`: `pushf`,
an increment, `popf`), written at exit to `$PANORAMIX_COVERAGE`;
`tools/cov_report.py` lists the functions no run called. The two
corpora, the random unit tests and a run of the fuzzer call 887 of the
999 functions there were; the functions no one called any more went, and
the rest are the C interface, the fetching of an address's code, the
building of the signature database, the test hooks, `--repr`, the
watchdog's expiry, the AVX2 hashing where AVX-512 is there, and python's
own unreachable code (`loop_to_setmem_from_storage` past
`only_add_in_expr` of a range, which is always false).

Python's nondeterminism had to be removed on its side first (the order
of the terms of a max, the variants of an expression, the substitution
order of the variants, the names of unnamed inputs of a signature):
commits of python's pull request (palkeo/panoramix#146, the branch
`merge-branches` of ytrezq/panoramix), whose code is the reference. Its
timeouts (60 s per step, 180 s per function) are scaled by
`PANORAMIX_TIMEOUT` there, so that a reference can be made without
the timeouts pypy hits and the assembly doesn't (Wyvern: 20x).

The whole corpus (30 contracts) decompiles identically to pypy's
references with the signature database; `panasm` takes 6.9 s of CPU
for all of them (one thread each) where pypy takes ~12 minutes.

A second corpus comes from the compiled artifacts npm packages ship
(`tests/corpus_from_npm.py`: OpenZeppelin 2/3/4, Uniswap v2/v3, Aave v3,
Gnosis Safe, 0x - 407 runtime bytecodes, from solc 0.5 to 0.8, with
libraries, mocks and proxies). All of them decompile identically to
pypy's output (27 s of CPU against 57 minutes), with one intended
difference:
python 3.11 (and pypy) refuse `str()` of an integer of more than 4300
digits, which `replace_mem` does on the lines of a trace, so python
fails on the functions that deploy a contract whose code is inlined
(`create2 ... code: 0x...`); the port prints them, exactly as python
does with `PYTHONINTMAXSTRDIGITS=0`. The fuzzer found another one:
`SHL` of two constants is `exp << off` in python's VM, which runs out
of memory (or overflows) for a shift of 2^255 before the result is
reduced to 256 bits; the port gives 0, and python reports the function
as a failure. And `BALANCE` of a constant address (`address(0x..).balance`)
makes python's VM slice an int (`addr[:4]`, a TypeError): the function
fails there, the port prints `eth.balance(0x..)`. Python's caches (`@cached`, dicts, sets) take `True` for `1`: a
storage of size 1 can come back from one as a storage of size `True`
(made from a boolean elsewhere), and its type can't be printed (an
AssertionError that ends the decompilation) - a mask of `True` fails
`apply_mask`'s assertion the same way; the port, whose `True` isn't the
number 1, prints the `bool` of size 1. `SAR` of two constants
by 256 or more of a negative value names `UINT_255_NEGATIVE_ONE`, which
python's arithmetic doesn't define (a NameError): the port gives -1. A
string in memory data whose length was -64 to -95 made the earlier
python's `pretty_memory` loop forever (its index went back by as much
as it went forward); the current one reads the bytes of a string
forward only, and the port with it. Its `data_bytes` makes
`2 ** (8 * size)` for any size of bytes (a MemoryError, or a long wait,
for a huge one; the port raises a MemoryError past 2^24 bytes, where
python still makes them), and `to_bytes` raises a ValueError for a
negative size down to -134 (`('bytes', -k, 0)`), as the port does.

Checked again against that pull request's final python (all four
corpora, 1116 contracts, pypy, `PANORAMIX_TIMEOUT=5`): the same texts
but for python's failures above (`BALANCE` of a constant address in
four Uniswap v4 test contracts), a `RecursionError` of pypy's in ENS's
NameGriefer, and python's timers - a function past its time limit, or
a VM stopped at a time where the port counts its nodes, when pypy runs
on a loaded machine (0x's DevUtils and Forwarder: the same texts on a
quiet one, or as the older references had them).

`tests/test_verbose.py` compares `panasm --verbose` / `--explain` and
the module's `decompile_bytecode(verbose=, explain=)` (what it prints,
then its text) with the output of `python -m panoramix --verbose` /
`--explain` on small contracts of the corpus (`make verbose-expected`
makes them, with pypy); `FUZZ_MODE=--verbose` (or `--explain`) runs
the differential fuzzer with those options on both sides.

`tests/test_fetch.py` runs a node of its own (HTTP, plain and chunked,
and an IPC socket that keeps the connection, as geth's does) answering
`eth_getCode` with contracts of the corpus: `panasm decompile ADDRESS`
must print the contract's text through every way of finding the
provider, a list its texts in turn, the module's `decompile_address`
give `decompile_bytecode`'s result, `python -m panoramix ADDRESS` (web3,
against the same node) the same text; the node's errors, an HTTP error,
no provider, TLS, an unknown scheme come back as messages.

`tests/test_threads.py` decompiles the corpus from several python
threads at once (each call with its own workers, 1 to 3) and compares
every text with the contract decompiled alone.

`tests/stage_compare.py contract.hex FUNCTION` finds the first stage of
python's `simplify_trace` whose port differs, replaying each stage on
python's input of that stage.

## Performance notes

Profiled with callgrind (`valgrind --tool=callgrind build/panasm ...`,
`callgrind_annotate --inclusive=yes`). What mattered, in order:
`"mem" in str(exp)` walks (the mention flags), the `required_after`
lists of `cleanup_vars` (a chain of maps), the variants of
`add_ge_zero` (evaluated with mpz scratches instead of built and
simplified), `hash_seq`/`seq_equal` without calls per element, the
walkers keeping a node whose elements came back unchanged
(`mk_seq_like`: 95% of the tuples built already existed), `try_add`
examining a term instead of building thirty patterns to compare with
it. What is left is python's own algorithms: `cleanup_vars` and
`cleanup_mems` rewrite the rest of the trace for every variable and
memory write (quadratic), and the printer.

Later, on Wyvern: `add_ge_zero` evaluates the terms of the sum by
groups that share no variable (the min and the max of each group over
its own variables' assignments, summed: the same tri-state as python's
3^k variants of the whole sum); the predicates `is_op_n`/`is_mul_int`
are leaves (60M calls with a frame each); `range_overlaps` is memoized
as python's `@cached` one is, and so are `try_add` and `mul_op` of two
terms (pure functions that python recomputes: `add_op` tries every pair
of its terms, at ~1000 instructions a pair); the memos of the functions
of two expressions hash the pair instead of making its tuple
(`memo2_get`); the pattern matcher's wildcards are compiled at startup
(the slot of the binding, the type) instead of their text read at every
match, and the hottest patterns (`('setmem', x, Any)` on every line)
are an opcode and arity check; `contains` skips the tuples that lack
the mention flags of what it looks for; the chunks of the pool are no
longer zeroed when released (up to 9% of the instructions, `memset` of
what had been used): `arena_alloc` zeroes the block it gives, in the
cache, and the nodes, vectors and strings, which are written whole,
take `arena_alloc_raw` (`PANORAMIX_POISON=1` fills the released chunks
with garbage instead, for the tests: the corpora give the same text
with it); the walker of the pure callbacks (`replace_f_memo`: the
trace is a DAG, hash-consed, that python walks as a tree at every round
of `simplify_trace`) remembers what each subtree gave (a map per
context, of the pairs (subtree, callback) since, kept from walk to walk
until a compaction: see below); `replace` skips the tuples that lack the
mention flags of what it replaces (a variable); the folder finds the
prefix and the suffix its paths share in one pass, and sorts its ors
with a merge sort. Without time limits (`PANORAMIX_TIMEOUT=0`: under
valgrind python's limits cut the simplification short, and the counts
of two builds weren't comparable), Wyvern went from 16.2G instructions
to 7.2G, zx_Exchange (the slowest of the npm corpus) from 58.6G to
43.2G.

Then, on Seaport15 and OneInchV5: `replace_while_var` (`readability`)
renames a loop's variables with a walk of its own that skips the
subtrees without a `var` or a `setvar` (a mention flag each: `HF_VAR`,
`HF_SETVAR`) and does each subtree once, where python's `replace_f`
calls its callback on every node (7% of Seaport15); `parse_counters`
and `extract_setmems` are remembered for their loop (the memory checks
of `cleanup_mems` and `cleanup_vars` ask them of the same loops
thousands of times: 8%); `replace` looks at the leaves in its loop
instead of calling itself on each; `pat_match` rejects without a frame
what doesn't start with the opcode heading the pattern (the simplifier
tries its rules one after the other); the VM's rounds keep their
scratch (see the memory item of the roadmap). Seaport15 went from 10.7G
instructions to 8.6G, OneInchV5 from 5.9G to 5.5G; the corpus takes
11.3 s of CPU (one thread per contract).

`contains` compares the leaves in its loop and recurses only into the
tuples that hold the mention flags of what it looks for. The folder's
`fold_or` looked for the two stretches that split an or in two by
trying every pair of lengths (python's two loops, each pair comparing
every side's beginning and remainder): the groups can only be the sides
starting with each of the two first lines, paired in order, which fixes
the difference of the two lengths, and the first length is where the
common endings of the pairs begin (unless that passes the beginning the
group shares) - one pass over the sides (`fold_or_split`). With
`--verbose`, whose paths have thousands of lines, UniV2Pair went from
13 s to 3 s. (The same on stretches, `fold_split_stretches`, is now
python's too, `_split_stretches`: the lines the groups share with the
shortest and the longest found a line at a time for all the sides, the
common endings of the pairs compared past the lower bound only.)

Then, on UniV3Pool: `cleanup_vars`' `required_after` (the variables of
the rest of the trace, at every if and while) makes each level's map at
its first search only, and a line's variables once each (its lines
mention them 30 times each: 1.8M insertions for 19K searches); the VM's
rounds walk the tree of nodes less - the nodes to run are the ones the
round's last walk found (nothing changed since), `merge_branches` walks
it once for all the nodes and the unexpanded ones among them (the same
order), `continue_loops` takes the loops `replace_loops` just made (no
other node's trace is a loop), and the walk handles its stack and the
usual predicate itself. 2.51G instructions to 2.27G.

Then, on zx_Forwarder and zx_Exchange: `cleanup_vars` asks whether a
line holds a variable from the variables of the line, remembered
(`line_vars`; an if's or a while's made of its lines', remembered too:
`replace_var` rebuilds an if around a branch it changed, and the lines
it kept are known), so that `replace_var` keeps a line without the
variable as it is - without walking it, nor its branches: only whether
it ends the replacement (`affects`) is left to decide - and "is the
variable still used" asks the rest's lines one by one instead of
walking it all; `replace_mem_exp` gives back at once an expression
without "mem" in it (its mention flags; no key tuple made for its memo);
`overwrites_mem` of an if or a while is remembered for the pair (the
ifs nest, and `replace_mem` asks each level, then the ones inside as
it goes into the branches); the priority of a function (`"selfdestruct"
in str(trace)`) looks at the strings of the trace instead of printing
it; the tables a compaction imports are made as big as the old ones.
zx_Forwarder went from 9.9G instructions to 7.3G. (An if without "mem"
can't be kept as it is by `replace_mem` the same way: python rebuilds
the whiles inside, their variables made a list.)

`merge_branches` tries to merge the paths of an if at a jumpdest by
walking the subtrees below it, round after round of the VM, for every
pair of nodes at a jumpdest - where only the nodes run since changed:
OpenZeppelin's ReentrancyMock (the VM stopped at its 5000 nodes) spent
77% of its time there. Each node carries a stamp, the generation of the
last change below it (`node_touch`, at every change of a trace, of
children, of a label; a generation begins at the first change after a
walk), and the answer of the walk below each branching node for the
last jumpdest asked (a false, a none, or a true without hits: a true
with hits is walked again, for them), good while the stamp holds; the
nodes of one child (straight code between jumps) are walked through,
without a frame. 4.74G instructions to 1.22G.

And then: `is_zero` and `arith_eval` of a tuple are remembered (pure
functions; the VM's `is_known` evaluates the condition, and `is_zero`
of it, once for every fact it knows: zx_DevUtils 11.5G to 10.8G); the
strings of the jumpdests in a node's jd are kept for the numbers below
32768 (a `snprintf` and an interning for each at every node made);
`replace_mem` and `replace_var` give back the trace itself when none of
its lines changed (no hashing of the long list); `replace_mem_exp`'s
memo is keyed by its three arguments (`memo3_get`) instead of a tuple
of them; the element arrays the walks write whole are taken unzeroed.
The npm corpus takes 30.7 s of CPU (41.8 s at the beginning of this
round, on the same machine).

Then, on zx_DevUtils and Seaport15, the walks of pure functions remember
what they gave from one call to the next: `replace_f_memo`'s map, of the
pairs (subtree, callback), stays until a compaction (the rounds of
`simplify_trace` walk mostly the same trees; the display rewrites of
`make_ast` and the folder's `make_fands` go through it too), the
top-down walk of `replace_bytes_or_string_length` has one of its own
(`replace_f_stop_memo`), `cleanup_mul_1` remembers the lists and the
expressions it cleaned, and `cleanup_mems` the pair (trace, what runs
after it): the rounds give it back the trace it made once nothing
changes any more, and the rests of a trace after its last change, the
branches, are asked again whatever changed. `line_vars` keeps the
variables of a long line once each with the context's scratch set (an
emap emptied by an epoch) instead of a map grown from nothing at every
line; `goes_to` and `find_conts` look only where the mention flags say
a `goto` or a `continue` is (`HF_GOTO`, `HF_CONTINUE`: the strings'
flags). zx_DevUtils went from 10.1G instructions to 8.3G, zx_Exchange
from 23.9G to 19.7G, Seaport15 from 4.7G to 3.7G.

On zx_Exchange: `replace_mem` is remembered for its three arguments (the
branches of the ifs are asked again and again, 38% of the time with the
same memory and value); `pretty_num` looks for the multiples of 10^9
and up and of 10^6 only in the numbers that are multiples of 10^6 (its
eleven divisions for every number printed: 7% of the printing); the
folder's `or` takes a path whose lines hold no list and no or as it is
(its `and` concatenated them into a list hashed again, for each path of
each or), and sorts the paths by length with a merge sort; the strings
are hashed eight bytes at a time (the printer makes a string of every
sub-expression it prints, each hashed: FNV-1a, a byte at a time, was 1%
of the instructions). 19.7G instructions to 17.7G. (Remembering
`mem_use` and `cleanup_vars` for their arguments gained nothing - the
traces they get change all over between two calls -, nor did walking
only the subtrees of the VM's tree that changed since the last walk,
reusing the rest of the last list: at every round the nodes run are all
over the tree, and the paths to them are most of it.) The npm corpus
takes 27.1 s of CPU (32.1 s before this round, on the same machine),
the mainnet one 6.9 s (8.0 s).

`merge_branches` asks for the common ancestor of every pair of nodes at
the same jumpdest, round after round: python walks up from both (the
deeper one to the other's depth, then both until they meet), as deep as
the paths are - 38% of safe_MockContract. The nodes carry a jump pointer
(Myers' skew-binary jumps, set with the parent: an ancestor at a depth
that only depends on the node's), and the walk jumps where python steps:
two nodes of the same depth jump to the same depth, so both jump when
their jumps differ (they meet above) and step otherwise, a logarithmic
number of steps. This gives python's answer as long as a node's depth is
one more than its parent's - a node is only hung elsewhere as a leaf (a
loop's body, a merge's node); one with children below would make their
depths stale (python's too), and the walk goes back to python's steps
for the rest of the run (`VM_STALE_DEPTHS`, never seen on the corpora:
a build comparing both answers at every call agreed on all of them;
`PANORAMIX_CHECK_LCA=1` does the same, aborting on a disagreement, and
`difffuzz.py` runs the port with it). 1.50G instructions to 0.98G.
`below` - whether a merged node's merge point is under the `if` being
merged, asked of every merged node `merge_branches`' visits meet - is the
same walk up, to the root when the answer is no: its jumps stop at the
`if`'s depth (aave3's MockReentrantInitializableImple, whose
`initialize` runs to the VM's 20000 nodes: three quarters of its time in
the walk; 19943 nodes in five minutes before, the 20000 in 100 s).
Then: `is_volatile` (the VM's `forget_volatile`, of every fact known at
every loop's head) reads a mention flag, `HF_VOLATILE`, set on the
strings that name a volatile thing and OR'ed up by the hash-consing,
instead of walking the fact; `find_nodes` keeps its stack in registers;
`extract_setmems`' `list(dict.fromkeys(...))` checks the setmems seen
in the context's scratch set rather than in the list; `list_from` and
`list_concat` (the rests of the traces, what runs after them) make their
lists from the elements directly, without a vector in between, and give
back the list itself when nothing is cut or added. 0.98G to 0.92G,
zx_Forwarder 4.64G to 4.49G, aave3_BorrowLogic 2.11G to 2.07G,
zx_Exchange 17.7G to 17.3G. `mem_use` (what reads a memory after a
setmem) asks `exp_uses_mem` of every line and `memloc_overwrite` of
every setmem: the first answers at once for a line without "mem" in it
(its flag), `find_mems` too, and keeps the ones it finds once each with
the scratch set; the second is remembered for its pair (the same
setmems for the same memories, round after round). zx_Staking 4.23G to
4.11G.

The comparisons of the memory ranges (`range_overlaps`, `fill_mem`: the
signs of differences of offsets, `lt_op`/`le_op`/`ge_zero`) come in
families: the same terms after different numbers - ('add', -64, x,
('mul', -1, y)), ('add', 32, x, ('mul', -1, y)) -, and python simplifies
each and evaluates its 2^k variants anew (277K `add_ge_zero` on
zx_Exchange, for 47K sets of terms). `add_op` combines the terms
without looking at the numbers, which it only sums: its combination of
the terms (`try_add`'s, in order) is remembered for the sequence of the
terms other than numbers (`MEMO_ADD_FAMILY`), whatever the numbers, and
the numbers' sum is added to the one the combination gave (then reduced
mod 2^256 when positive, as python does). `add_ge_zero` of an add is
answered from its family's record (`agz_by_family`): the fold of
`simplify` over the terms after the number (the same symbolic part as
the member's, its number the member's plus the family's, as long as no
sum of numbers on the way reaches 2^256: every number small, and no
`add_op` step that reduced one), then the extremes
of its variants (`agz_groups`); a member's answer is True when its
number plus the minimum is >= 0, False when its number plus the
maximum is < 0, None otherwise. `add_op` of two terms, the most asked,
is remembered for the pair (`MEMO_ADD2`) rather than for their tuple,
with whether it reduced a sum (the entry's fourth word). `tests/test_agz_family.py` asks, in one
context, families made as `add_op` and `sub_op` make them, and raw, with
the cases where a reduction mod 2^256 would change the answer. The
VM's `is_known` asks `eval_bool` of every fact known on the path, from
the last (some 150 on aave's logic libraries, nearly all answering
None): `eval_bool` looks at the fact only where it compares it with the
condition or a part it goes into (the operand of a bool or an iszero,
the terms of an or or an and) - equal, equal to its `is_zero`, `is_zero`
of it equal, an lt/le of the same first operand -, and a fact matching
none of those gives what any other one gives, asked once. The maps
(memo tables) keep a control byte per slot (0 empty, else the top bits of
the key's hash, compared before the key): only those are zeroed when a
table is made or doubled, where the whole table was (the zeroing was 5
to 9% of the instructions). The ranges a loop's memory writes cover
(`ranges_overlap_at_bounds`, which `overwrites_mem` asks for the loops of
the rest of the trace at every setmem) are remembered for the loop: its
bounds, then each range the first time python makes it, in python's
order (`MEMO_AT_BOUNDS`). The VM's `replace_loops` takes the unexpanded
nodes `expand_trace` leaves instead of walking the tree for them (the
unexpanded nodes are leaves, found in the order of the leaves, and
running one gives it new children only, which take its place in that
order; `PANORAMIX_CHECK_LCA=1` compares with the walk); the simplifier's
rules check the opcode heading their pattern before calling the matcher
(`PATXD`). `readability` renames the variables of every loop in the rest
of the trace, one at a time, after looking for a free name
(`contains(rest, ('var', n))`): both go by the variables of each line
(`line_vars`, remembered): the search asks the lines' lists, and the
renaming keeps as it is a line without the variable nor a setvar of it
(`line_setvars`, remembered too), without walking it. The hash-cons
table's slots hold, above a node's pointer, 16 bits of its hash (a tag,
`HC_TAG`): a probe reads a node only when the tags agree (the nodes are
all over the arena: most probes were a cache miss), and its doubling
reads the nodes' hashes ahead (`prefetcht0`).

Then, measured in time rather than instructions (`tools/psamp.c`: `perf`
isn't there, but `perf_event_open`'s software clock is - a sampler of the
instruction pointers and the frames' return addresses, the misses of the
caches included): 20% of the time went to the memo tables and 20% to
the hash-consing, most of it waiting on the memory, and 9 to 15% to
`merge_visit` on zx_Exchange and zx_Staking.
`_merge_at` gives up the same way when a side of the if answers false
or none, so `merge_visit` stops at the first path not run yet or looping
back at the jumpdest, remembers with a subtree's answer the number of
its hits (0, 1, 2 or more), and is asked without the hits first - for
them only when both sides are true with 2 hits at least
(`PANORAMIX_CHECK_LCA=1` compares every try with python's walk): 1% of
the time. The VM's nodes keep what the walks of the tree read in their
first two cache lines (64-byte aligned), with the vec of their children
and room for two of them (a jump has one child, an if two), where the
vec was allocated after the node; `find_nodes` prefetches the children
it pushes: its walks, 8% of zx_DevUtils' time, are 5% of it. A memo
table grows by four past 4096 slots (the rehashing of a doubling costs
as much as the entries: n entries have rehashed n of them by doublings,
n/3 past there), its rehashing without comparisons (the keys are all
different); `add_op` flattens its arguments in one pass. zx_Exchange
went from 17.2G instructions to 10.7G, zx_Staking from 4.1G to 3.1G;
the npm corpus takes 20.3 s of CPU (27.3 s before this round, on the
same machine), the mainnet one 5.4 s (6.8 s).
(`merge_visit` remembering the answer of a chain of nodes of one child
in its first node, as the node it leads to does, made it slower: the
answers are rarely asked again before the stamps change. Prefetching
the entry of a memo table with its control byte changed nothing: the
two misses were already overlapping.)

A memo table asked for answers it rarely has costs its lookups and its
entries for nothing. Counted (the hits and misses of each table, on the
corpus' biggest): `lt_op`'s questions came again 5 to 10% of the time,
`add_op`'s of more than two terms 0 to 12% (a tuple of the arguments
made for the key), `add_ge_zero`'s never (only `ge_zero` asks, after
its own memo): they are computed each time. Whether `add_op` reduced
its sum, which `agz_by_family` asks of every step of its fold, is the
fourth word of `MEMO_ADD2`'s entry (`map2_put_w`), where it was a table
of its own looked up at every step, nearly always without the pair;
`fill_mem` compares the range of the read with the split instead of
making the tuple ('mem', split) to compare the read with.
The VM's rounds walked the tree for the nodes not run yet right after
`merge_branches`, which had walked it at its beginning: when it merged
none, its list is the one (`PANORAMIX_CHECK_LCA=1` compares) - the walks
of the tree were 15% of safe_MockContract's time, 9% of zx_Broker's.
The big contracts of the npm corpus (zx_Exchange, zx_DevUtils,
zx_Staking, zx_Forwarder, zx_Broker, aave3_BorrowLogic,
safe_MockContract, oz2_ReentrancyMock) take 7.4 s of CPU, 8.0 s before.
(The machine's speed drifts by 5 to 10% from one minute to the next:
`tools/bench.py` has the binaries take turns, file by file, and keeps
the best of several runs. Tried, and left: a small cache of the last
node found for each 12 bits of the hash in front of the hash-cons table
(it hit too rarely to pay for itself), the answer of `fill_mem`'s first
comparisons remembered for the pair of ranges (133K calls on zx_Exchange,
5K pairs asked again), a filter of the jumpdests above a node in the
node for `node_history` (the walks of the tree slower by as much as it
gained: a fourth cache line per node), vectors made with room for 5
instead of 16 (no difference), a fast path of `le_op` for two numbers
plus the same terms (10% of its questions).)

Small changes weighed on a model rather than on the clock - cachegrind
with the L2 (2 MiB) as the last level, instructions + 10 L1 misses + 60
L2 misses, on four contracts: vectors made with room for 5 elements (64
bytes with their header) instead of 16, 3.3M of them on zx_Exchange,
most short and soon garbage (-0.4%); memo tables made with 256 slots
instead of 64 (-0.2%); the hash-cons table growing by four past 2^16
slots, as the memo tables do past 4096 (-0.6%).

Where the arena went, counted by caller (an experiment: `arena_alloc`
and `mk_seq`'s allocations summed by return address): on the function
of ENS's NameGriefer that takes 760 MiB, 58% to the memo tables'
growths (their slots held the entries, a pair's 32 bytes, half empty at
best and seven eighths just after a growth by four) - the arena is
fresh memory, a page fault per 4 KiB, and the sys time was a third of
the CPU time on the third corpus. The maps keep their entries dense
now, in chunks of 64, 128, 256... entries never moved, found through
32-bit slots (a tag of the hash above the entry's index): 1666 MiB
allocated to 1044, 888 MiB of RSS to 624, a third of the page faults,
and -1% on the model (1.5% more instructions for the chunk of an index,
12 to 20% fewer L2 misses). Contiguous entries copied at each doubling
were worse than the old tables (+1 to 3%: the copies and their garbage),
and so were slots grown by two past 4096 (+0.1 to 1.5%).

### The whole corpus, instruction by instruction

Then profiled on the whole corpus as a benchmark: the 1121 contracts of
tests/corpus, tests/synthetic, the npm, modern and vyper corpora, each
decompiled without time limits (`PANORAMIX_TIMEOUT=0`: the same work at
any speed), the measure being the corpus' total, its mean over several
runs (`tools/bench.py DIR[:DIR...] BIN BIN --runs 3`: the binaries take
turns contract by contract; the mean of the runs' user + system time, its
standard deviation, the elapsed time). Three tools, as none sees it all:

- valgrind's cachegrind, the caches and the branches simulated (the L1s
  of a Sapphire Rapids, 32 KiB and 48 KiB, its 2 MiB L2 as the last
  level), the cost of a function estimated as instructions + 10 L1
  misses + 60 last-level misses + 4 and 30 for the writes' + 15
  mispredictions. No valgrind has AVX-512 (Intel's port of 2022 was
  never merged): it runs the AVX2 paths (`PANORAMIX_ISA=avx2`).
- DynamoRIO, built from its sources, which runs AVX-512 natively, with a
  client of ours (`tools/bbfreq`): a counter per basic block, the
  executions of every instruction of the binary, summed over the corpus
  by function and by source line (`tools/bbf_agg.py`; the lines of the
  .s files are the instructions). A run of the corpus takes 20 minutes
  on two threads, where cachegrind takes hours.
- perf, sampling the CPU clock (this machine, a VM, has no hardware
  counters: no cycles, no cache events), natively, the kernel included:
  what the page faults, the zeroing of pages and the TLB shootdowns
  cost, and the callers (`perf record -g`; the frames are walked by
  their rbp).

`tools/prof_corpus.sh cachegrind|bbfreq|perf BIN OUTDIR DIR[:DIR...]
WORKERS` runs a profiler over the corpus, contract by contract, several
at a time.

The corpus took 484G instructions (DynamoRIO's count), and the time
went to:

- `changes_reads` and its walks, 28% of the instructions (135G:
  `replace_mem` asks it of every if of the rest of the trace, then of
  every if inside): the ifs and the whiles summarized (3.3G).
- `mv_visit`, python's visit of `_merge_at`, 10% (13% with its walks up
  the tree), 66% of zx_Staking's time: the rests of the walks that can
  only end false skipped (`mv_skip`; 62G to 10G).
- keccak, 5.6%: the storage's hash tables, made by every process,
  made at build time (`tools/gen_htab.c`, included read only; 26.9G to
  2.1G, the keccaks the contracts ask for).
- Wyvern's hash-consing, 3%: tuples of strings made again and again,
  each new (`calldata_params` remembered); and `"min" in str(exp)`,
  `apply_constraint`'s, 1.4% of the time (remembered).
- the page faults: cETH's 30140, two thirds of them in the first chunk
  of every context, mapped and unmapped for every function (its payload
  one chunk too big for the pool), and the growths of the hash-cons
  table; 4.0M on the corpus, 11% of the time in the kernel.

What they became, on the whole corpus (three runs each, one thread per
contract, then two):

                         before                   after
    -j 1   CPU    105.14 s +- 0.89        51.64 s +- 0.37   (-50.9%)
           user    93.75 s                45.42 s
           sys     11.40 s                 6.23 s
    -j 2   CPU    112.04 s +- 4.48        57.98 s +- 1.05   (-48.3%)
           elapsed 75.37 s                38.68 s
    page faults    4.0M                    0.62M
    instructions   484.1G                  225.9G   (-53.3%)

zx_Exchange 31.9 s to 8.5 s, Wyvern 8.8 s to 0.42 s, zx_Staking 7.4 s to
2.1 s; the same texts on the 1121 contracts, with the VM's checks and
with a compaction at every round. What's left is flat: `mk_seq` 5.5% of
the instructions, the hashing of sequences 4%, `mv_visit` 3.6%, the memo
tables' lookups 5%, the walks of the VM's tree 2.3%.

Madvise. The arenas' chunks of the default size were on huge pages
already (`chunk_map_huge`, `MADV_HUGEPAGE`): a page fault per 2 MiB
instead of per 4 KiB, and a TLB entry. A context's first chunk is one
of them now, from the pool, where it had a mapping of its own. A chunk
past the default size (a vector, a memo table's entries, from 4 MiB) is
on huge pages too, rounded up to whole ones, and so is a hash-cons table
of 2 MiB and more (`hc_table_alloc`), which the probes read all over (a
TLB miss each on 4 KiB pages): against calloc's, 3% of the CPU time with
two threads (fewer faults, less system time, a smaller RSS). Huge pages
cost their zeroing, 2 MiB at the first touch (8921 of them on the
corpus, 5% of the time, mostly memory used whole): a contract of a few
functions zeroes three to five, a few milliseconds where its 4 KiB pages
took one or two. Mapping a context's first chunk with 4 KiB pages when
the pool has none gave them back, and made the corpus 7% slower: those
chunks go to the pool, and serve the big contexts after.

Prefetches, measured (the time, as nothing else measures them here:
cachegrind ignores them; the corpus' contracts heaviest in the function,
rounds of them taking turns, an A/A of one binary against its copy at
+-1%):

- `prefetcht0` of the two cache lines of each child `mv_visit` pushes:
  6% slower. The DFS visits the first child at once (too soon for its
  prefetch) and the others after its subtree, their lines evicted from
  the L1 by then, and the prefetches took the place of lines in use.
- `prefetchw` of the arena past the bump pointer as `mk_seq` makes a
  node (the next nodes' lines, for writing): 0.9986 of the time over 20
  rounds, no difference. The arena is written in sequence, and the L2's
  streamer already fetches its lines for ownership; the other writes to
  cold lines read them first (a probe of the hash-cons table, of a memo
  table) or go in streams (the rehashing of a table doubled writes 2 or
  4 sequences).

Not kept either: filters of the ancestors' jumpdests and starts (64
bits, made when a node is hung) for `node_history` and
`vm_recursion_of` - the deep trees fill them, no fewer instructions;
the children pushed by `mv_visit` without `vec_push` (5% fewer
instructions on its heaviest contract; slower in the mean of the runs,
faster in the best ones).

Thread safety, change by change:

- The memo tables added (`MEMO_LINE_SUMMARY`, `MEMO_MENTIONS_MIN`,
  `MEMO_CALLDATA_PARAMS`) are the context's, a thread's own, and go with
  it; a compaction drops them or imports them by their kind
  (`memo_kinds`, now checked to have one per table).
- The subtree summaries of `mv_skip` are in the VM's nodes, the VM a
  context's; their validity is the nodes' stamps (`node_touch`, at
  every change), on the VM of the thread that runs it.
- The storage's hash tables were built at their first use, behind a
  `pthread_once` per table that every lookup called; they are read-only
  data now, shared by the threads without a lock.
- mmap, madvise and munmap act on mappings of the calling context, which
  no other thread knows of (a chunk goes from one thread to another only
  through the pool, under its spinlock). But munmap of pages present is
  a TLB shootdown: an interrupt to every CPU running a thread of the
  process, which waits for it - 2.4% of the time with two threads
  (`smp_call_function_many_cond`), from the old hash-cons tables freed at
  each doubling, the 64 MiB stacks of the workers at each join (past
  glibc's cache), the string table's growths. With more threads it costs
  more; a pool of tables would avoid most of it.
- Prefetches are hints, without effect on what a program computes; a
  `prefetchw` takes the line for writing, from the other cores' caches
  (as a write would): never on shared data - the string table, the
  loader, the signature database, the pool's lock - where it would
  invalidate the readers' copies. None was kept.

## Hostile input

The bytecode a decompiler is given is whoever's wrote it, so a server
that decompiles what it is sent runs this on input an attacker chooses
entirely. A review of the sources against that threat model (every file,
by twelve readers, plus fuzzing) found seven things worth fixing; they
are fixed, and `tests/security.sh` keeps the inputs that used to break
them.

Memory safety:

- `CODECOPY` of no bytes (offset 0, length 0) made `code_bytes_value`
  copy the whole code into a one-byte buffer: the length it computed was
  `0 - 1`, python's negative index of an empty range, as `SIZE_MAX`.
  A heap overrun from eight bytes of bytecode (`6000600060003900`), and
  the worst of the lot. An empty range is python's `0` now.
- `fetch_code` kept a 43-byte address in a 64-byte frame at offset 24:
  the last three bytes went into the saved `r14` below it.
- `pretty_memory` checked that a string's run of terms fits the tuple
  with a 32-bit compare of a 64-bit sum, so a length near 2^37 in the
  contract's data wrapped past it and the merge loop read past the end.
- `builder_string` doubled the signature blob once where the string
  needed more, and `memcpy`'d past it: the dump is trusted, but a dump
  is a file, and a 34 MiB name in one was enough. It doubles until the
  string fits, and refuses a blob past 4 GiB (the file's offsets are 32
  bits).
- The variable-size stack allocations (`sub rsp, count*8` for the
  elements of an expression, in `arith.s` and `algebra.s`) could step
  over the guard page: `STACK_CHECK` leaves a 1 MiB margin, and 131072
  elements are past it. `STACK_ALLOC` checks the new `rsp` before
  anything is written there.
- `fold_many` imports each fold's result as it comes, and the import can
  throw (its memory). The threads were left running on the tasks, the
  mutex and the condition variable of a context about to be freed. The
  collecting loop has a handler: no more folds are taken, the threads
  are joined, every context is freed, and the error goes on up.
- `build-db` never gave its context a stack limit, so `js_skip`'s
  `STACK_CHECK` compared against 0 and a dump nested deep enough ran off
  the stack. Both build paths call `ctx_set_stack`, and `sigdb_build`
  catches what its dump throws (a message and -1, where it aborted).

The rest, and what they cost:

- The signature database was written to `<db>.<pid>.tmp` with `O_CREAT`
  alone: in a cache directory others can write, that name could be a
  link planted beforehand, and the build would follow it. It is unlinked
  first and made with `O_EXCL | O_NOFOLLOW`.
- A node's answer was read until it ended; one that never stops ended
  the process instead (`xmalloc` aborts). 256 MiB is all it gets, and
  `SIGPIPE` is ignored, so a node that closes its socket gives `EPIPE`
  rather than killing the process.
- GMP's allocations go through the arena without its limit checked (GMP
  can't be left in the middle of an operation), but they count toward
  the total, so the next allocation that is checked throws. What is left
  is one allocation's overshoot; every shift and exponent that reaches
  GMP is clamped (`shift_amount`, `pow2`, `clamp_bits`, `powm` mod
  2^256), so none of them is the contract's number.
- A node's answer is bytes from the network, and its text ends up on a
  terminal: the error object, a `result` that isn't code, the answer
  when it isn't JSON-RPC at all, and the HTTP reason. They went through
  unescaped, so a node could write terminal escape sequences -- clear the
  screen, set the title, colour its own text. They go through
  `sb_append_clean` now, which writes anything that isn't printable
  ASCII as `\xNN`.
- A string constant of the contract can hold `\t \n \v \f \r`
  (`pretty_bignum` takes them as printable), so it can forge lines in
  the text - `def something(...)`, a comment. ESC is not among them, so
  there are no terminal escape sequences, and the JSON output escapes
  everything (`json_string`). Python does the same, and the text follows
  python, so it is left as it is and `tests/security.sh` checks that a
  constant of newlines forges nothing that reads as a function.

A second pass closed the shapes the readers could reach only in theory
-- an expression whose head or arity isn't what its opcode implies. None
of them has a path from bytecode that I could find, and each is one
comparison: `str_id` answers 0 for anything that isn't a string (the
patterns that bind a head, `(':op', ...)`, bind whatever is there, and a
tuple's count read as an opcode id would index the tables);
`variant_evaluable` refuses NIL and a `mask_shl` that isn't five
elements (`variant_eval` reads four arguments from it);
`alg_max_to_add` wants a `max` with at least one term (an empty one read
past the tuple, and `N_AUX` of 0 wrapped its count); and `pretty_type`
puts a storage offset through `must_int`, python's TypeError, where a
symbolic one would have been read as an mpz -- the one of these with a
consequence beyond a crash, since `mpz_get_str` of a bogus limb pointer
prints whatever is there.

What the review found safe is as much of the answer: the loader's scans
(truncated `PUSH` data, jumpdests, targets inside data), the symbolic
stack (`DUP`/`SWAP`/`POP` underflow), the copies with symbolic ranges,
the JSON scanner of the network answers (iterative, every byte bounded),
the chunked decoder, the database's header and its lookups (every offset
checked against the file's size before use), the interned strings and
the builders, and the vector, map and hash-cons growths. The recursions
all go through `STACK_CHECK` (`tools/recursion.py --check`, in `make
check`), so an expression nested arbitrarily deep is python's
`RecursionError`.

The machine that runs a trace on values (`runtrace.s`, for the storage's
check of a getter) computes in words of 32 bytes, made without a node,
and keeps its byte strings on a stack of its own, so a run leaves no
garbage in the arena (a machine is reset, not made again, between the
thousands of runs of a check). Python's bounds are its: 20000 lines, 20
times as many expressions, a memory of 1 MiB. What it doesn't bound, the
size of a byte string (a `call.data` or a `bytes` of the contract's
length) and of a shift, it bounds at 16 MiB (`RT_BYTES_MAX`): past that,
python's MemoryError, where python itself would go on, to what the
machine has; and a run makes 256 MiB of byte strings at most
(`RT_WORK_MAX`, python's Unsupported "steps"), where python would spend
minutes hashing them. A shift count past 2^63 is pypy's OverflowError
(CPython's only past 30 * 2^61, its MemoryError before it), which
storage's check catches where it doesn't catch a MemoryError.

Two things bound what a contract can spend: `CTX_MEM_LIMIT` per function
(`PANORAMIX_MAX_MEMORY`) and the watchdog's time limit, python's. The
folds have neither (they have their own arena limit, 1 GiB); a contract
that is expensive to fold burns CPU until the function's own limit ends
it. On a server, `PANORAMIX_MAX_MEMORY` and a process per request are
the way to bound it.

## Deduplication in a thread (tried, removed)

Tried: the duplicates merged by a thread of their own, as UKSM merges
the identical pages of processes - with the difference that the program
knows its objects (where each one is, its kind, its size, its hash),
where UKSM has to find and hash pages. Tuples were made as they are,
with a word before each for its canonical node, and put on a queue per
context; a merging thread gave each its canonical node (the equal one
of the context's hash-cons table, or itself, put there), the table
shared without a lock (slots only ever filled, by compare-and-swap;
grown by the context's thread alone, the merging one kept away as
during a compaction). Wherever the hash-consing makes a comparison of
pointers one of values (about 150 places), and for the keys of the
maps, the canonical nodes were compared instead. A `lazy` mode merged
without a thread, when a tuple was first compared or used as a key.

All the modes gave the same texts on the four corpora (1116 contracts)
once two races were fixed that only more threads than processors
showed: big ints interned in the table without the thread's lock (an
insertion lost now and then), and a table grown during a compaction,
which let the thread back in before its end, to merge nodes of the old
arena into the new table. But the thread didn't pay (npm corpus, 407
contracts, 2 vCPUs):

    -j 1    eager  22.2 s wall, 22.3 s CPU
            lazy   25.8 s,      25.9 s        +16%
            ksm    28.2 s,      30.8 s        +27% wall, +38% CPU
    -j 2    eager  15.6 s,      23.8 s
            lazy   18.3 s,      27.7 s
            ksm    18.1 s,      28.4 s

Most tuples are compared or used as keys soon after they are made: the
job's thread merged them itself before the merging thread got to them
(sampled: 4042 samples on the job's thread, 187 on the merging one),
and a lookup at creation costs less than later (the elements are in
the cache then, and a duplicate found is one not allocated). What the
thread did merge, it merged at the price of the cache lines of the
nodes the other thread was using. The duplicates, allocated before
being merged, raised the peak of memory by 11% (ENS's NameGriefer, 624
to 696 MiB) to 22% (Uniswap's NFTDescriptor), and the infrastructure
cost the hash-consing 1.1 to 1.5%. The hash-consing at creation stays
the only mode (the code: commit b6986cb and the ones before it).
