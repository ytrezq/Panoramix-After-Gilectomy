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
  results): F is rewritten to the variable's old value when the line gives it
  (`assignments` + `substitute`, as `Live::assign` does); otherwise NIL.
- **Other state changes** (storage, calls, transient storage) make F NIL only
  when F reads what they change (F_STORAGE, F_STATE...).
- **IF / MERGED_IF.** Each branch starts from F. After the IF, a branch that
  ends (halts, jumps away) is ignored. When both go on, the join is the first
  candidate among `F_then`, `F_else` and `F_before` proven `<=` both
  branches' floors (`alg::le`, `Top::Memory`, the facts), else NIL.
  `F_before` qualifies only when `le(F_before, F_then)` and `le(F_before,
  F_else)` are proven: a branch may have lowered the word.
- **WHILE / LABEL (a loop's head).** The floor before the loop when no
  iteration's write may touch `[A, A + 32)` (the loop's summary), NIL
  otherwise. (Later: keep the floor of a loop whose writes of the word are
  each proven `>=` the word's value before them.)

### Uses

A decision that involves the current `mem[A]` gets the floor through a
substitution: where an expression reads `MEM(RANGE(A, 32))`, the question sees
`F_A + δ` instead, δ one fresh atom per point, non-negative and bounded as the
memory model bounds an address the run accesses (`Top::Memory`). The existing
decisions (`mem::overlaps`, `alg::le` with `Top::Memory` and the path facts)
then decide `mem[64] + 4 >= ceil32(_1) + 260` from `F = ceil32(_1) + 292`
with no new algebra. The substitution is only for deciding: the trace keeps
`mem[A]`.

1. **Forwarding** (`simplify/mems.cpp`, the forward pass): MemState's overlap
   decisions for a write, and the pieces a read is made of, see the floor; a
   write at `mem[64] + k` keeps the pieces below the floor.
2. **Copy proofs** (`loops/rewrite.cpp`, `to_setmem`, called from
   `SetmemWalk`): the same substitution in the `apart` / `ahead` proofs and in
   `misses`; `SetmemWalk` carries the floors next to its path facts.
3. **Conditions** (what part 3 removes from the ranges): the decisions of the
   simplifier that read `mem[A]` (`cleanup_conds` and the others that decide
   with the path facts) get `mem[A] >= F_A` as a path fact at that point.
4. **Relational facts** (the second shape): the copy proof chains `src_end <=
   buffer_end <= F <= dst_start` through the decoder's requires; where
   `alg::le` can't chain a relational fact with `ceil32` and sums, the
   decision procedure gets the missing step (an `int_le` through one fact `a
   <= b` with offsets, sound under the no-wrap conditions it already proves).
   Only what the corpus needs.

One small module, `simplify/floor.{hpp,cpp}`, computes the floors for every
walk, so the walks can't disagree. The floors are path facts
(`alg::FactKind::Floor`: the address A, the expression F), carried by the
`alg::Facts` the walks already keep: `floor_transfer(facts, line)` after each
line, `floor_join(into, before, then, else)` where two paths meet,
`floor_loop(facts, while_line)` at a loop's head (the loop's summary: every
iteration's writes, decided with the floors before it), `floor_walk(facts,
v)` over a block. The substitution is `alg::floored(v, facts)`, applied by
the decisions about positions only (`Top::Memory`): `alg::int_lt`, `int_le`,
`decide_cmp` (`algebra/compare.cpp`), `alg::range` (`algebra/ranges.cpp`)
and `mem::pos_le` / `pos_lt` (`mem/memory.cpp`, where facts made only of
floors are decided by substituting and deciding without facts, memoized).

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

## Results (7-8 Nov 2026)

Parts 1 and 3 implemented (part 2 not yet); the npm corpus, 861 contracts:

| tree | copy loops left | `while` lines | stagecheck, text_check |
|---|---|---|---|
| python's assumption (`mem[64] >= 0x60`) | 5,262 in 241 contracts | 8,997 | 0 different |
| part 3 alone (nothing assumed) | 5,579 in 247 | 9,568 | 0 different |
| parts 3 and 1 (the floors) | 5,579 in 247 | 9,568 | 0 different |

Assuming nothing costs 317 copy loops (aave311's SupplyLogic and BorrowLogic,
ENS' NameWrapper, OpenZeppelin's ERC1155...) and some dead writes kept
(`mem[64] = 128` and the call's arguments in aave311_DelegationAwareAToken's
totalSupply); the floors, as the walks carry them now, give none of it back.
The first reason found: the copy conversion's walk started with no floor -
the dispatcher's write of the free word is in the entry lines, which only the
forward memory pass walked (to do: start `loops_to_setmems` with the entry
lines' floors, then the conditions of use 3 and part 2).
