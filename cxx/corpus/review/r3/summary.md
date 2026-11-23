# The manual review, round 3: the readability regressions fixed

Round 2 (`../r2/summary.md`) found no change in behaviour but 249 readability
regressions in the first tranche of 400 contracts, most of them from a few
causes. Round 3 fixes them before the review goes on, and makes the check
automatic: `tools/readability.py` measures what the reviewers looked for, and
`make readability` runs it over the npm corpus against a committed baseline
(`BUILD.md`, "The readability check").

## The yardstick

`tools/readability.py` compares each function of two texts of the same
contract. A regression is a revert string, called function, event, custom
error or decoded form that the old text showed and the new one doesn't, or a
count past its tolerance: raw memory in reverts, returns, call arguments,
call targets and event data; free-pointer differences left unfolded; storage
keys hashed from raw memory; split arguments; copies left as loops; `while
True` loops, labels, rotated loops; unused GAS reads; long lines, lines
with four rounded lengths; the nesting; the size.

Four sets of texts are compared:

| set | what |
|---|---|
| the 400 against round 1 (`t01`) | what round 2's fixes made worse and must come back |
| the 400 against round 2 (`r2`) | what round 3 must not make worse |
| npm (861) against the build before the fixes (`old`) | the same on contracts outside the review |
| npm against round 2's build (`cur`, cxx23 at bc67cddf5c) | |

The yardstick itself was corrected while it was used, each time a worker
showed a false regression: labelled loops, nested copies, overloads paired by
their types, a message moved to a call site or into a helper's def, a raw
revert become an `Error(...)`, the mean nesting of short functions. All the
numbers below are measured with the final tool.

## The numbers

Regressions not allowed (`allow.txt`). "Start" is round 2's texts (cxx23 at
bc67cddf5c); "after the merges" is 63cf853191 (the first fixes); "final" is
f53800acd4.

| rule | 400: start | after the merges | final | npm: start | after the merges | final |
|---|---|---|---|---|---|---|
| ptr_diff | 141 | 36 | 30 | 248 | 238 | 103 |
| rounded | 264 | 71 | 70 | 76 | 13 | 13 |
| long | 225 | 127 | 70 | 67 | 23 | 7 |
| partial_store | 162 | 22 | 1 | 79 | 24 | 1 |
| while_true | 138 | 0 | 0 | 22 | 0 | 0 |
| raw_stor | 84 | 23 | 22 | 18 | 8 | 8 |
| split_args | 80 | 2 | 2 | 13 | 4 | 4 |
| chars | 45 | 5 | 4 | 17 | 2 | 0 |
| raw_args | 38 | 14 | 14 | 13 | 12 | 12 |
| lost_forms | 22 | 23 | 23 | 26 | 22 | 22 |
| raw_revert | 42 | 15 | 15 | 3 | 3 | 3 |
| raw_fn | 41 | 34 | 33 | 0 | 1 | 1 |
| raw_log | 37 | 20 | 20 | 0 | 0 | 0 |
| raw_error | 34 | 9 | 9 | 2 | 2 | 2 |
| mem_writes | 33 | 13 | 12 | 3 | 1 | 1 |
| lost_calls | 34 | 9 | 9 | 0 | 0 | 0 |
| lost_strings | 32 | 9 | 8 | 1 | 1 | 1 |
| copy_loops | 21 | 16 | 16 | 4 | 3 | 3 |
| mean_depth | 15 | 2 | 2 | 9 | 0 | 2 |
| raw_return | 12 | 1 | 1 | 10 | 10 | 10 |
| lost_errors | 11 | 7 | 7 | 6 | 4 | 4 |
| depth | 8 | 2 | 2 | 8 | 4 | 4 |
| lost_events | 9 | 9 | 9 | 0 | 0 | 0 |
| unused_gas | 8 | 0 | 0 | 0 | 0 | 0 |
| structs | 6 | 3 | 2 | 1 | 1 | 1 |
| labels | 5 | 0 | 0 | 0 | 0 | 0 |
| offset_loop | 5 | 0 | 0 | 0 | 0 | 0 |
| **total** | **1552** | **472** | **381** | **626** | **376** | **202** |

In texts: 219 of the 400 at the start, 128 at the end; 144 of the 861 npm
texts at the start, 104 at the end.

What round 3 made worse than round 2, net of what it made better in the same
functions: 35 regressions in 13 of the 400 texts and 4 in 3 npm texts
(`regressions_r_vs_r2.jsonl`, `regressions_npm_vs_cur.jsonl`). Against the
merged head, round 3's second part added 2, in one function (c00114, below),
and none on npm.

## The causes fixed

Round 2's causes, in its order:

1. **The free-memory pointer after loops and joins.**
   - A rising loop variable that starts at the pointer gets the pointer's
     floor (7fcf60400c).
   - The backward memory pass asks for the floors of each place, not those
     shared by every place (2685ead556).
   - The floor is kept past an allocation whose size reads the pointer
     (`p + floor32(end - p + 31)` after its overflow check), when the path's
     facts prove the new value at least the old (48a916e306).
   - `2 * ceil32(x) - ceil32(x)` is `ceil32(x)` (f177462781).
   - Twelve zero bytes and the last twenty of a word of return data or
     calldata are that word, masked: `address(ext_call.return_data[0])`
     (1fb5d1040a).
2. **The pointer's value written in full.**
   - Long sums of positions and hashes of buffers are named: a buffer's base
     is written once (58139e27ce).
   - A line that would print over 240 characters gets the parts it repeats
     named right before it (8cebfa5e79). Only values that can't fail and
     don't read the gas are named; a name is read only while what it reads
     is unchanged.
   - A check that an earlier check already decides keeps its condition
     unnamed, so the last condition cleanup still drops it (e9d4ca00ad).
3. **Loops.**
   - The rotation weighs what would print twice; a test of the next
     iteration's values becomes the head's when it holds at the first head;
     a failing check is no rival of an exit test (cf6dd3e381).
   - A loop variable stepping by additions moves (no `s = sha3(s + h0) -
     h0`, 87a9f50078).
4. **Shared reverts.** The folder doesn't share an ending of one terminal
   line with the main path (9ba4a2e336); a custom error of up to three
   simple parameters prints whole, so its guards stay guards (6cd352700d).
5. **Split arguments.** A selector stored over the first argument's top
   bytes is the write of its four bytes (7431c4b9c5); a write of the bytes a
   read of the same range gives is no write (d056b3c97f).
6. **SafeMath's exact revert data.** Unchanged: the raw `Error(...)` payload
   with the padding memory holds is the exact one unless memory is provably
   fresh.

Also: a GAS read nothing uses is dropped where no read of the gas left runs
after it (2e9a8de8fc); a storage `bytes` copied as a range of slots is typed
`bytes` again (6e6e749ffb).

Each fix has a unit test that fails without it.

## What round 3 accepts

`allow.txt`, each line with its reason:

- **`while True` loops (P3).** Do-whiles whose test reads what the iteration
  computes have no exact test at the head. Round 1 rotated them and printed
  the first iteration twice before the loop; `while True` is the honest
  form. 26 lines.
- **Exactness.** gnosis MockContract `_fallback`: GAS reads in a loop, each
  followed by the next iteration's read. c00106: a memory word read inline in
  the arguments instead of through `_20`.
- **c00175 `structs`.** stor2 and stor3 are now resolved, and each element
  packs fields the code reads; round 2's "fixed array of uint256" only fit
  because those accesses were unresolved.

## What is left

- **c00114 `unknown4d6e7ce3`** (against the merged head: 8 to 18 long lines,
  1 to 7 rounded). The floor fix (48a916e306) turns a copy loop into a range
  and removes the function's pointer differences, but the allocations after
  it now print the pointer as its sum (`_34 + ceil32(...) + 352`) where the
  merged head read `_36 = mem[64]`. Over the whole text: 2 long lines fewer,
  12 pointer differences fewer, 5 loops fewer. Naming the pointer at its
  writes was tried; it added more rounded and long lines elsewhere than it
  removed.
- **The pointer**, 103 npm rows (uniswap tests): the return encoding
  `mem[s] = v - mem[64] - 64`, v a loop variable with no floor, its start
  reading `mem[128]` in a loop that writes memory.
- **Calls whose target is raw memory** (c00027, c00028: 11 raw_fn, 2
  lost_calls): the selector at the pointer can't be placed apart from the
  copy loops' writes.
- **Long lines** the naming can't shorten: call arguments (c00149: one line
  of 13 decoded arguments), allocation overflow checks over position sums
  and EIP-712 hashes (c00090, c00099, c00124), storage reads with long slot
  hashes (c00029).
- **Not yet looked at**: c00093 (SafeERC20's message not read back at the
  revert), c00104, c00108, c00113's lost `Array` form, c00168 (a named hash
  inside a storage slot), the remaining `rounded`, `lost_forms` and
  `copy_loops` rows against round 1.

Four errors in behaviour found by round 2's reviewers predate round 3 and
are not fixed yet: c00158 and c00160 (a checked subtraction inside an `and`),
c00144 and c00157 (getActions' ABI offset).

## The execution checks

At f53800acd4. `stagecheck --stage folded` runs evmone against every
stage's trace; `text_check` runs the printed text against evmone, with the
world's seeds 0 and 6, in the empty world and a random one.

| set | stagecheck | text_check, seed 0 | text_check, seed 6 |
|---|---|---|---|
| the 400 | 400 contracts, 123,664 calls: 0 different, 0 bugs | 61,832 calls in each world: 0 different, no line unparsed | 61,844 calls in each world: 0 different |
| npm (861) | 861 contracts, 78,122 calls: 0 different, 0 bugs | 39,059 and 39,063 calls: 0 different, no line unparsed | 39,075 calls in each world: 0 different |

`make check` passes (455 test cases, the python tests included). Before each
merge, the worker that made a fix ran the same checks on every text it
changed.

## The automatic check

- `tools/readability.py selftest`, in `make check` (`tests/readability_selftest.py`).
- `make readability`: the npm corpus decompiled and compared with
  `tests/readability/npm.jsonl.xz`, which holds, function by function, the
  best of three builds' texts (the build before round 2's fixes, round 2's,
  round 3's). What round 3 left is listed, not folded into the baseline:
  `tests/readability/allow.txt` has 33 proven exceptions (the P3 loops, the
  source's `while (true)`, GAS reads in a loop) and 204 regressions to fix,
  each with today's count as the most it may reach. `make readability`
  passes, and lists the lines a fix makes useless.
- `make readability-baseline` moves the baseline forward as a ratchet: no
  count goes up, nothing shown is dropped.
- The files here: `allow.txt` (round 3's acceptances against the older
  texts) and the six comparisons' regressions (`regressions_*.jsonl`: `name`,
  `function`, `rule`, `old`, `new`, `allowed`).
