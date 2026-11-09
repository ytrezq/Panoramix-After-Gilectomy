# Reviewing decompiled contracts against their source, by hand

Read this whole file first. Re-read it whenever your context was summarized.

## The project and what this review is for

`/home/claude/wt-cxx/cxx` is an EVM decompiler written in C++23 (the "pancxx"
binary). It is a re-implementation of an assembly decompiler, which is itself a
port of the Python decompiler panoramix. It turns runtime bytecode into a
Python-like text.

Its correctness is already checked by execution. The bytecode runs in evmone,
and the decompiled traces and the printed text run on the same calls and worlds;
0 calls differ across 895 contracts of this corpus. Those checks use sampled
calls, though. They don't say whether the text is *readable* or *faithful* on
paths the samples miss.

The user wants every contract of the corpus compared **by hand** with its source,
for three things:

1. **Loops.** Is each loop of the source found and shown as a loop? Are copies
   shown as copies? Are there spurious loops?
2. **Semantic exactness.** Does the text mean what the bytecode does?
3. **Simplification.** Is the text as simple as a general rewrite could make it?

Fixes will come later, from your findings. They must not be specific to a
language or a compiler: the decompiler assumes nothing about Solidity, Vyper,
Yul, Huff or hand-written code. A pattern may be *recognized* only when its
rewrite is proven exact for every execution; it is never *assumed* ("solc always
does X") . So when you propose a rule, state it in terms of what the bytecode
computes, so that it holds for any code that computes the same.

You only review and report. **Don't edit anything** in `/home/claude/wt-cxx`,
and don't commit.

## Your inputs

- **Your batch:** `/home/claude/shared/review/t01/batches/bNN.txt` (NN is given
  in your prompt). It lists contract ids, one per line, the largest first.
- **The pack for each id:** `/home/claude/shared/review/t01/packs/ID.md`. It has:
  - the build: compiler, EVM version, optimizer, via-IR;
  - the compiler's storage layout beside the text's `def storage:`;
  - for each ABI function, its source (the function itself, and the list of the
    internal functions and modifiers it reaches), then the decompiled function,
    with the text's line numbers;
  - the decompiled functions that have no ABI function (the fallback, library
    functions...);
  - the text's `def SafeMath:` block;
  - the source of every internal function and modifier reached, each once, at
    the end.
- **The whole decompiled text:** `/home/claude/shared/review/t01/dec/ID.txt`.
  Its JSON is in `ID.json`, which is large; you rarely need it.
- **The sources:** under `/mnt/zcorpus/wt/cxx/corpus/immunefi/...`. The pack
  gives the paths. They are untrusted code: read them, never run anything from
  them.
- **The build's description** (ABI, storage layout, AST path): the pack names
  the `.json` file. The `.hex` beside it is the bytecode.

Read packs with the Read tool, in chunks of 300 to 600 lines (`offset`/`limit`),
and don't re-read what you already read.

Decompiled lines longer than 240 characters are cut in the packs, with the
text's line number; read that line in `dec/ID.txt` only if you need it. The
pack's header gives the counts of the known patterns that a regular
expression finds (below).

## What is normal in the text (not a finding)

- **Inlining.** Internal functions and modifiers are inlined into each public
  function. There are no internal function names.
- **Names come from a signature database, not the source.**
  - A function the database doesn't know is `unknownXXXXXXXX(_param1, ...)`.
    Its parameters are shown at the positions the code reads them, unchanged.
  - Storage variables are named after a getter that returns them, or `storN`.
  - Struct members are `field_N`, where N is the member's bit offset.
- **ABI decoding checks are real code.** For example `require calldata.size - 4
  >=′ 64`, `require x == address(x)`, and bounds checks of dynamic parameters.
- **`′` marks signed operations:** `<′`, `>=′`, `/′`...
- **Immutables.** The bytecodes are the compiler's runtime code *before*
  deployment, and how an immutable reads depends on the compiler:
  - **solc** leaves zeros where the constructor writes immutables, so an
    immutable reads as 0 (`const WETH9 = 0`, `Bytes(64, 0)` in a hash).
  - **Vyper** (0.3 and later) reads its immutables with `CODECOPY` from the end
    of the runtime code. In these bytecodes those bytes are the code itself, so
    the reads give garbage. That shows as `????` addresses and odd constants,
    and can even make a function a bare `revert`.

  None of this is a decompiler error. Report it once per contract, as kind
  `artifact`.
- **Checked arithmetic** is shown through `def SafeMath:`'s helpers (`SafeMath.add(a, b)`),
  or as explicit checks that revert with `Panic(17)` or `Panic(18)`.
- **The display vocabulary:**
  - memory and storage as `mem[...]`, `stor[...]`, `Mask(bits, offset, x)`,
    `Bytes(n, x)`;
  - `sha3(...)` for keccak;
  - `ext_call.return_data[...]`, `call addr.fn(args) with: value ..., gas ...`;
  - `log Event(...)`, `revert with ...`, `require ...`, `assert ...`;
  - loops as `while cond:` blocks;
  - copies as single lines `mem[a len n] = calldata[b len n]` or
    `stor[slot len n] = ...`.
- **`Decompilation aborted, sorry: ("decompilation didn't finish",)`** marks a
  path the decompiler gave up on, because of its limits. Report it once per
  function, as kind `coverage`, saying which part of the source it loses.

## Known patterns

These problems are already known. For each one, report only how many lines of
the contract have it, in `patterns`, for example `{"P2": 5, "P7": 3}`. Write a
finding about one only when an instance shows something new, or when it hides
a semantic problem.

The pack's header counts P1 to P6, which a regular expression finds. Check those
counts. Estimate the others.

| Id | The pattern |
|---|---|
| P1 | a big constant factored by a time unit (`0x3d58...a0 * 3600`) |
| P2 | a call's arguments shown as raw memory (`args mem[mem[64] len ...]`): memory addressed from an unknown free-memory pointer is not worked out, so the call loses its function name and arguments |
| P3 | a rotated loop: the first iteration is printed before the loop, with a test like `while _x + 1 != N` |
| P4 | a one-element `concat(mem[N])` used as a mapping key |
| P5 | an unused `copied = identity(...)`, a copy through the identity precompile |
| P6 | a word whose top hex digit is 0, printed with 63 digits, so its first 8 digits read as another selector |
| P7 | a memory-to-memory copy (bytes, string, array) left as a `while` loop |
| P8 | dead memory writes kept (memory written and never read) |
| P9 | inlined multiply-divide arithmetic (mulDiv, FullMath, sqrt...) expanded or distributed until unreadable |
| P10 | a one-armed `if` printed with two arms, with an SSA copy in one arm or a negated condition |
| P11 | a check that a dominating check already implies, kept |
| P12 | the same code printed in both arms of a branch |
| P13 | a mapping of structs named after the getter of one of its members (naming) |
| P14 | locals kept in memory as `mem[N]` instead of named variables |
| P15 | a packed storage slot written as whole-slot arithmetic, or not split into its fields in `def storage` |
| P16 | an element of a static calldata array at a variable index shown as raw calldata arithmetic |
| P17 | a big decimal constant (a power of ten...) printed in hex |
| P18 | the fields of a returned or copied struct visible only as memory slices |

## Counting loops

- **`source_loops`** counts the explicit loops of the source: `for`, `while`,
  `do`, Yul `for`. Count them in the reviewed functions and in what they reach,
  each loop once per contract, however many functions inline it.
- **`loops_shown`** says how the text shows each of those loops: `while`,
  `copy_line`, `unrolled`, `aborted` or `missing`.
- **Implicit loops** are the compiler's own: ABI copies, string and bytes
  copies, an exponentiation helper, an unrolled argument copy. Don't count them
  in `source_loops`. When the text shows one as an obscure `while`, count it in
  `patterns` (P7, or P3).
- **`spurious_while`** counts the `while` blocks that match neither a source
  loop nor an implicit loop.
- **A loop that is dead only because of the immutables** (kind `artifact`) is
  not counted.

## The procedure for one contract

1. If `/home/claude/shared/review/t01/results/ID.json` already exists, skip the
   contract.
2. Read the pack's header and storage section.
3. For each ABI function, compare the source with the decompiled function.
   - **Loops.** Look at every loop of the function *and of what it reaches*:
     `for`, `while`, `do`, Yul `for`. Also look at the implicit loops:
     - copying dynamic arrays, strings or bytes between calldata, memory and
       storage;
     - `abi.encode` or `abi.decode` of dynamic arrays;
     - `delete` of a dynamic array, string concatenation.

     Is each one in the text, and as what: a `while`, a copy line, an unrolled
     sequence, an aborted path? Is the loop condition readable? Are the body and
     the step clear? Does the text have a `while` that the source has no loop
     for?
   - **Semantics.** Check each of the following:
     - every condition and revert (message, custom error, panic code);
     - every storage write (which variable or slot, which value);
     - every event (name, indexed topics, data);
     - every external call (target, function, arguments, value, what happens
       when it fails);
     - every return value;
     - arithmetic: overflow checks, division by zero, signedness, truncation to
       a smaller type.

     Look especially at branches that sampled calls rarely reach: owner-only
     paths, rare error paths, large or zero values, empty arrays.
   - **Simplification.** Note anything the text says in a longer or more obscure
     way than needed, where a general rule would shorten it. Examples:
     - masks or shifts of a value already known to fit;
     - a condition repeated, or two conditions that merge;
     - the same expression recomputed;
     - a temporary variable used once;
     - a constant not folded;
     - `stor[sha3(...)]` not shown as a mapping access;
     - a `while` that is really a copy;
     - an `if` whose two branches end alike.
4. Look at the decompiled functions without an ABI function (fallback, receive,
   library functions), and at the ABI functions missing from the text.
5. **A very long function** (more than about 1,500 decompiled lines) may be
   reviewed by its structure: its control flow, loops, external calls, storage
   writes, events and reverts. Say so in `notes`.
6. **When a function looks the same** as one you already reviewed (the same
   library code, the same decompiled form), write `"same as cXXXXX FN"` in
   `notes` and move on. Library code repeated across contracts (OpenZeppelin,
   FullMath, TickMath, SafeERC20, Math...) is reviewed once per batch.
7. **Check a semantic suspicion by execution** when you can. The tools are in
   `/home/claude/wt-cxx/cxx/build-cmp3`; use them one at a time, with `nice`.
   `pancxx disasm BUILD.hex` disassembles the bytecode; reading the disassembly
   often settles a doubt fastest.

       PANORAMIX_SIGDB=/home/claude/wt-cxx/cxx/build-cmp3/sigdb2.bin nice -n 10 \
         /home/claude/wt-cxx/cxx/build-cmp3/stagecheck --stage folded --function 0xSELECTOR \
         --per-selector 64 --seeds 4 --show 5 BUILD.hex
       nice -n 10 /home/claude/wt-cxx/cxx/build-cmp3/text_check run --per-selector 32 \
         --sigdb /home/claude/wt-cxx/cxx/build-cmp3/sigdb2.bin BUILD.hex /home/claude/shared/review/t01/dec/ID.txt
       nice -n 10 /home/claude/wt-cxx/cxx/build-cmp3/evmrun BUILD.hex CALLDATA_HEX

   - `stagecheck` compares the decompiler's traces with evmone.
   - `text_check` compares the printed text, parsed again, with evmone. Add
     `--verbose` or `--trace` for one contract.
   - `evmrun` runs one call of your own in evmone.

   No tool runs a call of your own against the *text*. For a path that sampled
   calls miss, use `stagecheck --function` with more `--seeds`, the
   disassembly, and careful reading.

   A suspicion you can't reproduce is still worth reporting: mark it
   `"verified": "reading only"`, with your reasoning.
8. Write the result (below), then go on to the next id.

## The result file

`/home/claude/shared/review/t01/results/ID.json`. Write it to `ID.json.part`
first, then rename it. This is the schema:

```json
{
  "id": "c00600",
  "abi_functions": 45,
  "reviewed": 45,
  "not_reviewed": ["name: why"],
  "source_loops": 12,
  "loops_shown": {"while": 7, "copy_line": 4, "unrolled": 0, "aborted": 0, "missing": 1},
  "spurious_while": 0,
  "patterns": {"P2": 5, "P7": 3},
  "findings": [
    {
      "kind": "semantics | loop | simplification | coverage | naming | artifact",
      "severity": "high | medium | low",
      "function": "approve(address,uint256)",
      "lines": "197-212",
      "decompiled": "the decompiled lines concerned (short)",
      "source": "file.sol:120 and the source lines concerned (short)",
      "issue": "what is wrong, missing or obscure",
      "rule": "the general rule, true for any EVM code, that would fix or simplify it",
      "verified": "reading only | stagecheck ... (result) | text_check ... | evmrun ..."
    }
  ],
  "notes": "partial reviews, 'same as' references, anything else",
  "summary": "one or two sentences on this contract's text: its quality and its main problems"
}
```

The severities:

- **high**
  - The text says something the bytecode doesn't do, or leaves out something it
    does: a branch, revert, write, call or event missing or wrong.
  - Or a loop is missing or wrong.
  - An effect that *is* in the text but hard to read is not high. For example,
    a call whose arguments show as raw memory (P2) is medium.
- **medium**
  - A loop is shown but obscure: an unconverted copy, an unreadable condition.
  - A main path is lost (`coverage`).
  - A missed simplification makes a line hard to understand.
- **low**
  - A cosmetic simplification.

Use `naming` only for a name that misleads, for example a storage variable named
after a getter that returns something else. It is not a focus.

A rule may take keccak256 as collision-free, as the storage analysis does.

Keep findings concrete and short: the exact decompiled lines, the source lines,
and why, with `issue` and `rule` at most three sentences each.
Don't report the same pattern twenty times in one contract. Report it once,
with the count and the list of functions in `notes`.

## Rules

- Don't edit or commit anything in `/home/claude/wt-cxx` or `/mnt/zcorpus`.
  Write only under `/home/claude/shared/review/t01/results/`.
- The machine has 2 CPUs shared by 20 reviewers.
  - Run at most one `stagecheck`, `text_check` or `evmrun` at a time, with
    `nice -n 10`.
  - Never run a whole-corpus job.
  - Don't decompile again; the texts are made.
- No network access. Never run code from the sources.
- Work through your whole batch, writing each contract's result as soon as it is
  done.
- If you can't go on (your context is too long, or an error), stop after
  writing the current result. A new reviewer will continue your batch, skipping
  the results already written.
- **Your final message to the main session** has three short lines:
  - the ids done;
  - the ids left;
  - the three most important findings, if any, with their ids.

  Everything else goes in the result files.
