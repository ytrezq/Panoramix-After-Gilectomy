# The free-memory floor: copies proven disjoint, no assumption about the compiler

## The question, and the answer

On 20 October one question was left to the user: should the decompiler assume
solc's allocation discipline ("memory is only ever allocated upwards from
`mem[64]`, and a pointer designates an object allocated earlier"), so that
the memory copies still printed as loops are converted, as the asm and python
convert them? The copies left were 1,055 printed loop lines in 92 contracts,
against the asm's 242. On the corpus rebuilt on 7 November
(`tools/fetch_corpus.sh`, 861 contracts), `tools/loop_lines.py` counts 5,262
while loops with a plain copy line in their body, in 241 contracts, out of
8,997 while loops.

The user's answer (7 November): **assume nothing about the compiler**; the
bytecode is not necessarily solidity's. It may come from Vyper, from Yul or
inline assembly, from Huff, Fe, LLL, or be written by hand, and hostile code
may imitate a compiler's idioms to mislead a reader. So:

1. Nothing is converted on the strength of a compiler's conventions. A copy
   becomes a memory range only when the trace itself proves the conversion
   exact. The option designed on 7 November (`--assume-alloc`, solc's
   allocation stated as an assumption) is **dropped**.
2. What the conventions gave is recovered by **proofs** from the facts the
   trace holds: a lower bound of the words the code keeps at constant
   addresses (the *floor*, part 1), and where a pointer came from (its
   *provenance*, part 2).
3. The assumptions about solidity the decompiler inherited from python are
   **removed** (part 3) and replaced by the same proofs.

`mem[64]` has no special status anywhere below. It is the word solc keeps its
free memory pointer in, so it is the word the floor helps most on the corpus,
but the floor is computed for whatever constant-address word the code reads
and writes, from the code's own writes; for code that keeps no such word
(Vyper's static allocation) it is simply unknown and changes nothing.

## What the remaining copies look like

`tools/loop_lines.py` and a shape count on the 861 contracts (destination,
source):

| destination | source | loops | example |
|---|---|---|---|
| `mem[64] + k` | an expression of the contract's words | 1,479 | `mem[idx + mem[64] + 160] = mem[idx + ceil32(return_data.size) + ceil32(assetData.length) + 192]` |
| an expression | an expression with a decoded offset | 1,240 | `mem[idx + ceil32(rds) + ceil32(a.length) + 192] = mem[_9 + idx + ceil32(a.length) + 192]` |
| an expression | a pointer read from memory | 158 | `mem[u] = mem[mem[t]]` |
| constant / other | constant / other | about 380 | `mem[idx + mem[64] + 64] = mem[idx + 160]` |

**First shape: the destination reads `mem[64]`.** The forward pass of
`cleanup_mems` lost `mem[64]`'s value, typically at the join of an IF
whose branches set it to different values. OpenZeppelin 4.9's TokenTimelock
is an example: `_callOptionalReturn` copies the return data only when there
is some. After the join, `mem[mem[64]] = 0x08c379a0...` writes at an
unknown place, and every piece known below it is forgotten, among them the
length word of the revert string at `ceil32(_1) + 228`. So the length isn't
forwarded, the loop's trip count isn't known, and the destination can't be
compared with the source. Both branches left `mem[64] >= ceil32(_1) + 292`,
above that piece: a floor carried through the join keeps the piece, the loop
runs once on known bytes, and the destination, at or above the floor, is
apart from the source below it.

**Second shape: a decoded offset.** An offset decoded from data (return data,
calldata) places the source inside a buffer the trace copied earlier, and the
destination lies past it. The decoder's checks (`require _9 + 32 + len <=
return_data.size`...) are path facts bounding the source's end by the
buffer's end; the buffer's end is proven at most the floor when the buffer
was written below it; the destination is at or above the floor. That is a
comparison chained through a relational fact, not a constant bound.

**Third shape: a pointer stored in memory.** Proven only when the trace
shows where the stored pointer came from (part 2). Otherwise it stays a loop.

## Part 1: the floor

### Definition

For a constant address `A` (a word `MEM(RANGE(A, 32))` the code reads; `A =
64` in practice), at a point p of a function's trace, the floor `F_A(p)` is an
expression made of values available at p (never of `mem[A]` itself) such that
on every run reaching p:

    word(mem[A]) >= word(F_A(p))      (unsigned; F_A(p) itself doesn't wrap)

A floor is NIL when nothing is known. Nothing in the definition presumes what
the word is used for.

### Transfer

- **Start of a function.** The entry lines (the dispatcher's own writes, e.g.
  `mem[64] = 128` when the code wrote that) set it. For an internal function,
  or a trace without entry lines, every floor is NIL.
- **`SETMEM(RANGE(A, 32), v)`.** `F_A = v`: exact, needs no monotonicity (the
  floor bounds the word, not the allocations). A write that may lower the
  word (inline assembly restoring a saved pointer) is just another value.
- **Any other memory write** (a SETMEM, a call's or a copy's output, a loop's
  writes as lot 6's `LoopSummary::mem_writes` summarizes them) leaves `F_A`
  when its range provably misses `[A, A + 32)` (`mem::overlaps(range,
  RANGE(A, 32), facts) == Tri::False`); otherwise `F_A` becomes NIL. A write
  that may go anywhere (`writes_any & S_MEM`, an INTERNAL, an UNDEFINED) makes
  every floor NIL.
- **A line that sets a variable F reads** (a SETVAR, setvars, a call's
  results), **other state changes** (storage, calls, transient storage) and a
  write over memory F reads: F keeps what the line leaves of it (`weaker`:
  the terms the line may change dropped, when what's left is proven at most
  F, `Top::Memory`: `160 + mem[128]` is `160` once `mem[128]` is written);
  otherwise NIL.
- **A variable's floor** (`FactKind::Floor` keyed by a TMP or a loop
  variable): `x = v` where `floored(v)` is a sum in which each `d` is a term
  of its own gives `x >= v` without the `d`'s (`_12 = mem[64]`: `_12 >= F`;
  `_17 = _12 + 64`: `_17 >= F + 64`); `x` set to exactly a word's floor (the
  value the forward pass resolved) gets that. Kept while `x` isn't set again
  and what its floor reads isn't changed; at most 24 at once.
- **A compound line** (an IF's summary, a loop's), decided at once: the
  floors none of its writes may change, each write decided with the floors
  that stay - a floor one of them may change dropped (or weakened) and the
  others decided again without it, to a fixpoint (`stable_floors`). One pass
  was unsound: an IF that sets the word at 96 to 64 and then writes at
  `mem[96]` kept the floor of 64, decided with the floor of 96 it changed.
- **IF / MERGED_IF.** Each branch starts from F. After the IF, a branch that
  ends (halts, jumps away) is ignored. When both go on, the join is the first
  candidate among `F_then`, `F_else` and `F_before` proven `<=` both
  branches' floors (`alg::le`, `Top::Memory`, the facts), else NIL.
  `F_before` qualifies only when `le(F_before, F_then)` and `le(F_before,
  F_else)` are proven: a branch may have lowered the word.
- **WHILE (a loop's head).** By induction over the iterations
  (`loop_floors`): the candidates are the floors before the loop, but those
  of the variables it sets (dropped; a rising variable's made anew) and those
  reading what it changes but memory (weakened or dropped); the body is
  walked from them, with the path's conditions (an IF's in its branches, a
  require's after it: a length checked before a copy bounds it), each
  candidate kept when it stays what it was at every point of a path that
  goes on - an iteration that reverts never gets back to the head nor past
  the loop (`LoopSummary::cont_effects`) - and the walk done again without
  the ones that don't, until none goes. They hold at the head, throughout
  those paths and after the loop. A word the body writes only by
  allocations, `mem[A] = mem[A] + s` with `s` in `[0, 2^255)` where it is,
  never goes down: it stays while it has a floor. A loop variable set only by
  the CONTINUEs, each to itself plus such an amount, is at least its start
  value. The variables the body sets get their floors too (`inside`, made of
  what the loop doesn't change, for the decisions about the loop's own lines
  - its summary - not past it). `floor_loop_all`: the same over every path,
  for the backward pass, whose head holds the reverting paths' reads.
- **LABEL / LOOP_PATH (a raw loop).** NIL.

### Uses

A decision that involves the current `mem[A]` gets the floor through a
substitution: where an expression reads `MEM(RANGE(A, 32))`, the question sees
`F_A + δ` instead, δ one fresh atom per point, non-negative and bounded as the
memory model bounds an address the run accesses (`Top::Memory`). The existing
decisions (`mem::overlaps`, `alg::le` with `Top::Memory` and the path facts)
then decide `mem[64] + 4 >= ceil32(_1) + 260` from `F = ceil32(_1) + 292`
with no new algebra. The substitution is only for deciding: the trace keeps
`mem[A]`.

`floored` substitutes through the arithmetic of positions only (sums,
products, masks, minimums, maximums, ranges): a read's address or a calldata
word's offset stays as it is - an atom the path's conditions may bound
(`require cd[s] <= 2^64 - 1` with `s` a rising variable: `cd[s]` must stay
`cd[s]` for the bound to apply).

1. **Forwarding** (`simplify/mems.cpp`, the forward pass): MemState's overlap
   decisions for a write, and the pieces a read is made of, see the floor; a
   write at `mem[64] + k` keeps the pieces below the floor. At a loop's head,
   what its lines write (`forget_loop`) is decided with the loop's inside
   floors.
2. **Copy proofs** (`loops/rewrite.cpp`, `to_setmem`, called from
   `SetmemWalk`): the same substitution in the `apart` / `ahead` proofs and in
   `misses`; `SetmemWalk` carries the floors next to its path facts.
3. **Conditions** (what part 3 removes from the ranges): the decisions of the
   simplifier that read `mem[A]` (`cleanup_conds` and the others that decide
   with the path facts) get `mem[A] >= F_A` as a path fact at that point.
   (Not needed on the npm corpus: what `cleanup_conds` decided with the old
   range was keeping a condition past a write - use 5 -, no condition about
   `mem[64]` itself.)
4. **Relational facts** (the second shape): the copy proof chains `src_end <=
   buffer_end <= F <= dst_start` through the decoder's requires; where
   `alg::le` can't chain a relational fact with `ceil32` and sums, the
   decision procedure gets the missing step (an `int_le` through one fact `a
   <= b` with offsets, sound under the no-wrap conditions it already proves).
   Only what the corpus needs.
5. **The other walks that decide about memory**: `cleanup_vars`' forward walk
   (a variable's value kept past a write the floors place apart from what it
   reads: `changes(w, r, facts)`), `cleanup_conds` (a condition kept past such
   a write), the backward memory pass (a forward walk first, `FloorsAt`, keeps
   the floors before each line by its place; `Live`'s `read`, `overwrite`
   and `before` decide with them - a live range is read after the line, but
   when the line may change what that range's address reads, it may write a
   range that is live too, the read's summary having it, so a dead write's
   decision never rests on a floor the line changes). A compound line's
   summary is decided with `floors_through`.

One small module, `simplify/floor.{hpp,cpp}`, computes the floors for every
walk, so the walks can't disagree. The floors are path facts
(`alg::FactKind::Floor`: the address A, the expression F), carried by the
`alg::Facts` the walks already keep: `floor_transfer(facts, line)` after each
line, `floor_join(into, before, then, else)` where two paths meet,
`floor_loop(facts, while_line)` at a loop's head (its body walked from the
floors before it, to a fixpoint; `floor_loop_inside` with the body's
variables' floors, `floor_loop_all` over every path), `floors_through(facts,
line)` for the decisions about a compound line's summary, `floor_walk(facts,
v)` over a block. The substitution is `alg::floored(v, facts)`, applied by
the decisions about positions only (`Top::Memory`): `alg::int_lt`, `int_le`,
`decide_cmp` (`algebra/compare.cpp`), `alg::range` (`algebra/ranges.cpp`)
and `mem::pos_le` / `pos_lt` (`mem/memory.cpp`, where facts made only of
floors are decided by substituting and deciding without facts, memoized).

What it costs: read by every walk, the floors first made decompiling up to
seven times slower (ENS' TestRRUtils, whose functions nest a loop in the
exit of the one before, 16 deep). So a loop's floors are memoized by the
floors they depend on - those of the words, and of the variables the loop
reads up to `floored()`'s depth of four floors; a floor that only passes
through the loop is kept when the loop doesn't set its variable nor write
what it reads, decided with the loop's inside floors -, an IF's floors in
the copy walk by the floors before it, `floored()` by the facts' identity;
and a floor of 0, or of 2^63 and more, is never kept: it says nothing, and
`floored()` would read its variable as a fresh atom, the conditions about
the variable lost. Then (8 November): a pass makes floors only of the words its trace
reads at a constant address, or gives a value that isn't a constant
(`FloorScope`: `floored()` reads a word's floor only where an expression
reads the word, and a variable set to a word's floor gets it - a
selector, revert data, a string's words written at constant places get
none); and a comparison of positions with floors is decided without them
first (`mem::pos_le`, memoized: what holds whatever the words are holds
with them - and reading a variable as its floor plus d may lose what the
ranges know of its value). What is left of the cost is mostly the forward
memory pass's comparisons of each write with the pieces it keeps, now
that the floors keep more of them and the variables' floors make the
positions compared larger. Measured on the 861 texts in one run, the
builds interleaved: 85e7ce3123 (before the floors) 51.2 s of user time,
cxx23 at 33930c6935 (the floors, and the bytes getter's boundary worlds)
84.6 s, with these two changes 78.3 s (0x032_Exchange 16.4, 28.8, 23.0 s);
the 834 contracts under 0.3 s each 17.3, 29.3, 29.1 s.

Then the walks remember what they decide - nothing decided differently (the
861 texts byte-identical to cxx23 0d986fed75's). The profiles (a sampling
profiler on a frame-pointer build) showed three costs: `floor_transfer`'s
overlap decisions (31% of aave311_BorrowLogic: 72% of its calls are the
same line with the same facts, met again by the other walks and the next
rounds - but a Facts list rebuilt the same was new cells, so nothing could
be remembered); the fresh decisions about positions (51% of 0x032_Exchange:
3.3 million pairs, each expanding both sides into their linear readings,
though the pairs are made of a few thousand values - BorrowLogic's 262,504
of 7,039); and the bytes getter's check (73% of openze300_ERC721, 91% of
uniswa410_MockHooks: its worlds of up to 16,320 words, a virtual sload, two
GMP calls and an append per word). So: the path facts are hash-consed (a
fact on a given list is one cell: a list rebuilt the same is the same
cells, its identity a key); `floor_transfer` is memoized by (line, facts,
scope), `kept_conditions` by (line, facts), a scope's id names its words
exactly; `loop_info`'s two walks over every path are one; the decisions
without facts read each value's linear readings once (`SideState` in
`algebra/ranges.cpp`, cleared with the variables), XInt's products by 1 and
-1 are the other factor; the trace machine copies a run of storage words
the host has at hand at once (`exec::Host::sload_run`, the same checks in
the same order). Measured on the 861 texts in one run, the builds
interleaved, one contract at a time: 85e7ce3123 56.7 s, cxx23 0d986fed75
84.1 s (1.48 times), these changes 61.2 s (1.08 times); 0x032_Exchange
18.1, 22.9, 14.3 s; the 831 contracts under 0.3 s 18.6, 32.1, 23.6 s (what
is left there is mostly the bytes getter's check), the 30 others 38.1,
52.0, 37.6 s.

### Soundness

By induction on the trace: a floor is only made equal to a value the word was
given; it is kept only across lines that provably don't change the word; it is
rewritten through the assignments of the variables it reads; at a join it is
lowered to a value proven at most both branches'. The substitution reads the
question as "for some δ >= 0", which is exactly what the invariant gives.
Every rewrite keeps its own checks (`apart`, `ahead`, `misses`, the
induction's trips); the floor only adds facts.

The floors live under the memory model's premise (`Top::Memory`, lot 4: the
words an address is made of are below 2^64, as python's `MEMORY_TOP`): an
allocation `mem[A] + s` is taken not to wrap, and a join's `c <= F` is
decided with the words of `c` and `F` below 2^64. A contract that stores a
word of 2^64 or more in the free word and later compares positions with what
it became is outside the model - as it is for every decision about positions
(`a + b >= b` with `a` a word of the address). The walks use only facts that
hold where they decide: a walk through an IF's branches has the floors alone,
a loop's floors are decided with what holds in every iteration.

## Part 2: provenance (the third shape, exact)

A source address read from memory, `mem[t]`, is placed below the floor only
when the forward pass knows the value stored at `t` (a piece of MemState) and
that value is itself an earlier floor value `F_A(q)` of a point q where the
word was then advanced past the object: the trace wrote `mem[A] = F_A(q) + s`
with `s` proven at least the object's extent the copy reads. Then
`src + n <= F_A(q) + s <= F_A(p) <= dst`. Every link is a fact of the trace;
when one is missing (the pointer came through a merge, a call, a loop, or
data the contract was given), the copy stays a loop. No convention of any
compiler is used: a hand-written allocator that bumps another word gets the
same proof through its own `F_A`.

## Part 3: the assumptions inherited from python, removed

1. **`mem[64] >= 0x60` everywhere** (`algebra/ranges.cpp`, the range of
   `MEM(RANGE(64, 32))` is `[0x60, 2^256)` when `ContractShared::
   free_memory_pointer`, i.e. when the code's first instructions write
   `mem[0x40]`, and by default; python's `variants.FREE_MEMORY_POINTER`). The
   code may later write any value there (solady and other inline assembly do).
   Removed; the floor gives the proven bound where there is one (use 3).
2. **`mem[0x40] = 0x60` before a function whose entry state isn't known**
   (`vm/vm.cpp`, "as the old compilers set it"). Removed: an unknown entry
   leaves memory unknown, and the function's trace is made from what the code
   does (when that leaves the validation's machine without the dispatcher's
   writes, the function is decompiled from where the dispatcher starts
   instead).
3. **The others found by the audit** (the dispatcher's idioms, the storage
   layouts, SafeMath's and the traits' patterns, the loops' shapes...) are
   listed with their status in `DESIGN.md`: a pattern of one compiler may be
   *recognized* (that is reading, and every rewrite it leads to is checked
   exact), never *assumed*.

## Validation

1. **Unit tests (doctest)**, `simplify_floor_test.cpp` and the loops/simplify
   tests: the transfer rules (a write of the word, a write missing it, an
   unknown write, a variable of F set again, the joins: each candidate and
   none, a loop that writes or doesn't write the word); forwarding through a
   join (the TokenTimelock shape) and the copy shapes converted; the negative
   cases run in the trace machine against the loop, as `loops_rewrite_test`
   does: the word lowered in a branch, a write over the word at an unknown
   place, an in-place move, a stored pointer of unknown provenance; and
   part 3: a trace that lowers `mem[64]` below 0x60, decided as the machine
   runs it.
2. **The corpora**, every stage and the printed text, **0 different**:
   - the 861 contracts of `tools/fetch_corpus.sh` (solidity);
   - a corpus of code not from solc's high-level output, built reproducibly
     the same way (pinned packages): Vyper contracts compiled by pinned Vyper
     versions, solidity whose assembly ignores the allocation discipline,
     Yul objects;
   - copy loops and while loops before and after (`tools/loop_lines.py`), and
     what part 3's removal costs before the floor recovers it;
   - CPU time before and after.
3. **The existing suites**: release and ASan/UBSan, and the python tests.

## What the old range decided (8 November)

An experiment build (not committed) put python's range of `MEM(RANGE(64,
32))`, `[0x60, 2^256)`, back behind a mask of the pipeline's phases
(`PAN_OLDFMP`: the VM, the whiles, each pass of the simplifier, the cleanup
of memory's two walks apart, the final passes, the stages after), the caches
cleared where the mask switches. All the phases on gives the old texts byte
for byte (aave311_DelegationAwareAToken, ensdom122_ETHRegistrarController,
...), none of them today's. On 44 contracts sampled from the 346 whose text
changed, four phases give all of it (but a loop variable's name in 6):

| phase | what the old range decided there |
|---|---|
| `cleanup_vars`, forward | a variable `p = mem[64]` kept past `mem[p] = x`: the write at `RANGE(mem[64], 32)` misses `RANGE(64, 32)` - solidity's `return x` (`return(mload(0x40), p + 32 - mload(0x40))`), 4,394 of today's `len _N - mem[64]` lines |
| `cleanup_mems`, forward | the same for MemState's pieces; and through a pointer taken before the word moved on (`_12 = mem[64]; mem[64] = _12 + 64; mem[_12] = ...`): the old range bounded `_12` by its value's range, `[0x60, ...)`; and in loops - a check with a message in a loop body (`mem[_44 + 4] = 32` where `_44 = mem[64]`, on a path that reverts) made the loop's writes go anywhere, every piece forgotten at its head |
| `cleanup_mems`, backward | a write at `mem[64]` (or below the word) dead though a read at `mem[64] + k` follows: the dead writes of totalSupply (`mem[64] = 128`, the call's arguments) |
| `cleanup_conds` | a condition kept past a write that misses what it reads (`commitments[sha3(mem[_31 + 32 len mem[_31]])]` past `mem[0] = ...`, `_31 = mem[64]`) |

The VM, the whiles, `loops_to_setmems`, `simplify_exps` and the final passes
decided nothing with it on that sample.

So the floors were right but read in one walk only, and the old range gave
three things they didn't have: a bound for a variable that holds the word's
old value, a bound where a loop's iterations that revert write at such
variables, and a bound after a loop that allocates at every iteration.

What makes them provable now is in part 1: the floors read by every walk
that decides about memory (Uses 1, 5), the floors of variables, a loop's
floors made by walking its body from its head (the iterations that revert
left out, the rising variables, the words that only grow, the body's
variables' floors for its own lines), a floor weakened rather than dropped,
and `floored` kept to the arithmetic of positions.

## Results (7-8 Nov 2026)

Parts 1 and 3 implemented (part 2 not yet); the npm corpus, 861 contracts
(the texts' lines: the printed lines of all 861):

| tree | copy loops left | `while` lines | lines | stagecheck, text_check |
|---|---|---|---|---|
| python's assumption (`mem[64] >= 0x60`) | 5,262 in 241 contracts | 8,997 | 545,648 | 0 different |
| part 3 alone (nothing assumed) | 5,579 in 247 | 9,568 | 647,045 | 0 different |
| parts 3 and 1, the floors in two walks (7 Nov) | 5,579 in 247 | 9,568 | 647,045 | 0 different |
| cxx23 with the Vyper agent's merge (storage copies as ranges...) | 5,540 in 247 | 9,151 | 643,886 | 0 different |
| that and the floors in every walk (8 Nov) | 5,094 in 227 | 8,144 | 573,577 | 0 different |

On 7 November, assuming nothing cost 317 copy loops (aave311's SupplyLogic
and BorrowLogic, ENS' NameWrapper, OpenZeppelin's ERC1155...), 571 `while`
lines, about 100,000 printed lines and some dead writes kept (`mem[64] =
128` and the call's arguments in aave311_DelegationAwareAToken's
totalSupply); the floors, read by two walks only, gave none of it back.
Read by every walk (8 November: "What the old range decided" above), they
give back more than the copies and the loops - 168 copy loops and 853
`while` lines fewer than with the assumption, every stage of the 861
contracts and their texts 0 different (stagecheck: 78,021 calls at the
folded stage, 77,732 the same, 289 inconclusive - one contract at the time
limit, as before;
text_check: empty world 39,059 calls, 39,017 the same, random world 39,063,
38,549 the same) - and 72% of the lines: 27,929 more than the assumption's
texts (0x032_Exchange 9,355, 0x042_Forwarder 3,390, uniswa410_SkipCallsTest
1,524...).

What is left:

- copy loops still worse than the assumption in 14 contracts (36 loops:
  aave311_BorrowLogic 14, repo_UniversalRouter 4, aave311_LiquidationLogic
  and SupplyLogic 4 and 3...) - decoded offsets (the second shape: Uses 4)
  and stored pointers (part 2), not yet done;
- `while` lines more than cxx23's in 8 contracts (13). 10 are loops whose
  copy the backward pass now finds dead, left stepping their variables
  (`while idx < _param3 + 32 * _param3.length + 36: s = s + 32; idx = idx
  + 32`, OpenZeppelin's ERC1155Holder and TimelockController, ENS'
  TestNameWrapperReentrancy): cxx23 converted the copy whole and dropped
  it, the trip count proven with the copy's memory address; a loop that
  does nothing, with no address to bound it, isn't proven to end. The 3
  others, and 3 copies not converted any more (0x013_LibAssetData 2,
  ensdom122_DummyExtendedDNSSECResolver 1), not analysed yet;
- an internal function's trace starts with no floor (no entry lines);
- the cost (8 November, after the memos above): the 861 texts take 1.08
  times the user time of 85e7ce3123, the tree before the floors (61.2 s
  against 56.7 s, interleaved); the contracts below 0.3 s 1.27 times
  (the bytes getter's check, its worlds), aave311_BorrowLogic 2.1 times
  (1.40 s against 0.66 s), ENS' TestRRUtils 1.75 times, 0x032_Exchange
  0.79 times.
