# The manual review, round 4: the regressions left to fix

Round 3 (`../r3/summary.md`) made the readability check automatic and left
`tests/readability/allow.txt` with 237 lines: 33 proven exceptions and 204
regressions to fix. Round 4 removes as many of them as it can, with changes
that hold for any EVM code - nothing keyed on a language, a compiler or a
library. Three agents worked on the decompiler (memory and the free-memory
pointer; the decoded forms; the structure and the naming) while main kept
the yardstick honest, merged, measured and checked.

## The numbers

`allow.txt` went from 237 lines (33 proven, 204 to fix) at the start
(ea386becc8) to 160 lines (11 proven, 149 to fix) at the end (8776f1a1a8).

| rule | to fix: start | end |
|---|---|---|
| ptr_diff | 104 | 92 |
| lost_forms | 22 | 10 |
| rounded | 13 | 2 |
| raw_args | 13 | 13 |
| raw_return | 10 | 10 |
| raw_stor | 8 | 8 |
| long | 7 | 2 |
| split_args | 4 | 0 |
| lost_errors | 4 | 3 |
| depth | 4 | 0 |
| raw_revert | 3 | 3 |
| copy_loops | 3 | 3 |
| raw_error | 2 | 0 |
| mean_depth | 2 | 0 |
| structs | 1 | 0 |
| raw_fn | 1 | 1 |
| partial_store | 1 | 1 |
| mem_writes | 1 | 1 |
| lost_strings | 1 | 0 |
| **total** | **204** | **149** |

Where the 55 went: 44 fixed in the decompiler, 3 moved to the proven part
with their proof, 8 false regressions of the yardstick (below). The proven
part went from 33 to 11: 25 `while True` lines no longer needed once the
yardstick counted the loops' three prints together, 3 lines moved in.

The texts at the end against those at the start of the round (the texts of
ea386becc8), with the final yardstick: 0 regressions in either set.

| count | npm: start | end | the 400: start | end |
|---|---|---|---|---|
| reverts printed as raw memory | 2,521 | 2,521 | 3,652 | 3,649 |
| returns printed as raw memory | 630 | 627 | 482 | 468 |
| calls' arguments holding raw memory | 1,609 | 1,595 | 4,071 | 3,982 |
| events whose data hold raw memory | 311 | 300 | 1,091 | 1,035 |
| differences of free-pointer reads left unfolded | 2,036 | 1,873 | 5,572 | 5,276 |
| storage keys or hashes of raw memory | 1,059 | 963 | 2,042 | 1,830 |
| arguments split in byte slices | 60 | 42 | 95 | 7 |
| memory copies left as loops | 4,655 | 4,638 | 5,290 | 5,275 |
| aborted paths | 325 | 325 | 115 | 114 |
| GAS read inside an expression | 306 | 306 | 51 | 47 |
| lines over 240 characters | 4,824 | 4,308 | 12,272 | 11,455 |
| lines with four or more rounded lengths | 2,150 | 1,770 | 3,073 | 2,427 |
| raw memory writes | 126,194 | 126,098 | 210,963 | 210,827 |
| the deepest nesting | 9,993 | 9,973 | 19,028 | 18,991 |
| the function's size in characters | 27,195,805 | 26,690,997 | 54,243,580 | 53,617,079 |
| lines | 501,468 | 502,762 | 935,127 | 939,218 |

## The yardstick's corrections

Each came from a false regression a worker showed; each has selftest cases.

- **Nesting** (5770e8518f). A wrapped statement's lines - a revert's or a
  log's arguments aligned past it - take its nesting. The mean nesting is a
  regression only when the summed nesting grew too: a mean that rose because
  shallow lines left the text (raw memory writes now decoded) is none.
- **Loops and forms** (c4fc030a27). `while True` is counted with the rotated
  loops and the labelled jumps, the three prints of a loop whose exit is no
  plain test at its head: a rotated or labelled loop now `while True` is no
  regression, a plain head test now `while True` still is. A decoded form is
  a kind: the `Array` another function gained is not the one a function
  lost. `compare --prune` rewrites the allow file.
- **Copies and counts kept together** (ecce399498). The long lines and the
  lines of four rounded lengths are counted with the copies left as loops:
  a loop that copied a buffer word by word and is now the one write of what
  it holds is no regression. A rule kept with others is a regression only
  when its own count grew: a raw revert more is not also an `Error(...)`
  revert more.

After each, the baseline was made again from the saved texts of the builds
it is made of; with the tool before the change, those texts give the
committed baseline byte for byte.

## The causes fixed

**Memory** (the pointer worker).

- cefeee9cca: the words of memory a text reads again and again - the
  free-memory pointer, a length kept in memory - get one name, `_8 =
  mem[64]`, read while the floors prove the word unchanged; past a write
  that may be the word's, the reads are as they were. Nothing is assumed of
  the word. 13 lines (ERC721's `safeTransferFrom`, `setZonehash`, gnosis's
  `reset`).

**Decoded forms** (the forms worker).

- ba1e2ceda4: an ABI `bytes` as wide as its length, a multiple of 32 by its
  form, is one array.
- 86a2ef1a4a: a run of zero bytes is cut where an offset points (an empty
  tail inside the padding before it).
- d030c70405: ABI arrays whose length agrees with their content where the
  path's conditions hold (`AbiFacts`: facts dropped at the first line that
  may change what they read).
- 9d0a4dfbb1, fc5927c759: a value's adjacent bytes in two parts are one
  part; two adjacent fields of one storage slot are one read.
- 84c34f8d09: an ABI head word in two parts - zeros, then the low bytes of a
  word of memory - is that word, masked, where its address provably doesn't
  wrap; the arrays after it are read again.
- 9c0725c8eb: a constant ending with the zeros of a word, then the word's
  low bytes, is the constant and the word: 14 reverts of npm and 114 of the
  400 show the custom error's selector or name they hid
  (`SenderAddressResult(address), address(ext_call.return_data[0])`).

**Structure and naming** (the structure worker).

- e8d5317b61: the base of positions a line of four rounded lengths or more
  repeats is named (`_k + 64` where `p + ceil32(n) + 64` was written out).
- d39c600602: an iteration's skip is a guard and its long main path one
  level up (aave311 SupplyLogic: mean nesting 2.08 -> 1.27).
- f95c331faf: a long line's storage key that a variable of the trace holds
  is written as that variable.
- 2c3c9103d2: a long line's storage key no variable holds gets a name - the
  slot's hash and its place as they were, so the storage sections are the
  same. Taken on the user's decision: three functions of c00058 nest
  deeper (mean 2.16 -> 2.64), under the tool's tolerance.
- 7e69b80ca4: a hash two lines or more read gets one name, whatever it
  reads (long lines -215 on npm, -417 on the 400); in a storage slot only as
  a key the storage's forms read under either layout.

## What round 4 accepts

The 11 proven lines of `allow.txt`, each with its proof: the `while (true)`
of ENS's RRUtils, GAS reads in a loop, the P3 do-whiles, a revert and a
message never reached, and a storage access now resolved.

## What is left

- **The pointer in the uniswap tests' loops** (90 of the 92 `ptr_diff`
  lines, uniswa410's tests). The
  return encoding `mem[s] = v - mem[64] - 64`, `v` a loop variable whose
  floor isn't known. The pointer worker's loop floors (`wip/
  pointer_loop_floors.diff`, its parts still behind environment switches)
  free 105 lines but lose forms elsewhere: ENS's `OffchainLookup` in
  `resolve`, the 400's `InvalidLinkWeiPrice` (c00004, c00007) and a revert
  string (c00022) - `wip/pointer_loop_floors_regressions.txt`. Two causes
  found: the two normal forms of `3 * ceil32(n)` (the mask readings below
  fix it), and `cleanup_vars` substituting a read at a non-constant address
  into positions once more floors are known (c00004).
- **The mask readings** (`wip/mask_readings.patch`, exact, with its test).
  The ranges' linear reading takes `96 * (n + 31 >> 5)` as `3 * ceil32(n)`
  and the bits one value's masks clear as one atom, so more memory reads
  resolve: 18 lines go (openze496 ERC777's 8 `Array` forms, ENS's
  `resolveCallback`), and raw memory drops on both sets. Not merged: with
  the hashes named (7e69b80ca4), 5 counts of 2 texts of the 400 are still
  worse than at the start of the round: three functions of c00089 and
  c00172 whose resolved hashes sit in storage slots the forms may read as a
  mapping (a name there would change the storage section), and two of
  c00089 that print `2 * Mask(250, 5, x + 31) + ceil32(x)`. They need the
  printer to write that as `3 * ceil32(x)`, and the storage forms to read a
  slot through a name.
- **Memory after a selector's zeros**: reverts whose custom error hides in
  `Bytes(16, selector...)` followed by memory - 36 places at constant
  addresses (a no-wrap proof as 84c34f8d09's would do), the rest at
  addresses not proven to be past the zeros.
- uniswa410 PoolTest `unknownef87a6ec` (10 errors): its decompilation is
  aborted in every build; the old text got further.
- uniswa314 NFTDescriptor (`long`): 512-bit multiplication checks whose
  `mulmod` a check reads, memory places the long pass doesn't enter.
- The routers' `raw_args`, aave311's `raw_stor` (keys hashed from
  `concat(mem[0])`), QuoterV2's `raw_return`.

Four errors in behaviour found by round 2's reviewers are still not fixed:
c00158 and c00160 (a checked subtraction inside an `and`), c00144 and
c00157 (getActions' ABI offset).

## The execution checks

Each fix was checked by its worker on every text it changed (npm and the
400): `stagecheck --stage folded` and `text_check` with the world's seeds 0
and 6, before the merge; main checked again where it applied a change
itself. At the end, at 8776f1a1a8:

| set | stagecheck `--stage folded` | text_check, seed 0 | text_check, seed 6 |
|---|---|---|---|
| npm (861) | 861 contracts, 78,122 calls: 0 different, 0 bugs | 39,059 and 39,063 calls (the empty world, a random one): 0 different, no line unparsed | 39,075 calls in each world: 0 different, no line unparsed |
| the 400 | 400 contracts, 123,664 calls: 0 different, 0 bugs | 61,832 calls in each world: 0 different, no line unparsed | 61,844 calls in each world: 0 different, no line unparsed |

`make check` passes (484 test cases, the python tests and the
yardstick's selftest included).

## How it ran

Three agents and main on a machine of 2 CPUs: one worktree per agent, the
heavy jobs (builds, a corpus decompiled, the checks) under one lock. A fix
that traded one row for another anywhere was not committed as it was: the
agent looked for the form that loses nothing, or reported the trade with
its numbers, and the user decided (2c3c9103d2 taken; the mask readings
after the hashes' names, and not yet).
