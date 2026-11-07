# The free-memory floor, and solc's allocation as an option

## The question

The question left to the user on 20 October was whether to accept the
assumption "solc always allocates memory upwards" so that the memory copies
still printed as loops would be converted, as the asm and python do. The
copies left were 1,055 printed loop lines in 92 contracts, against the
asm's 242. On the corpus rebuilt on 7 November (`tools/fetch_corpus.sh`,
861 contracts), `tools/loop_lines.py` counts 5,262 while loops with a
plain copy line in their body, in 241 contracts, out of 8,997 while
loops.

The two answers are not exclusive, and both are designed here:

1. **By default, exact.** Most of these copies can be *proven* disjoint from
   facts the trace already holds, if the analysis knows how far the free
   memory pointer has grown: a lower bound of `mem[64]`, the *floor*, carried
   along the trace (part 1). No assumption.
2. **As an option, solc's allocation.** What the floor can't prove,
   `--assume-alloc` takes from solc's allocation discipline, stated as a
   precise assumption that execution checks on every contract (part 2). It
   is narrower than python's unchecked rule (`RewriteOptions::dubious`,
   python's "we should check for overwrites here, but skipping for now"),
   which `loops_fuzz_test` shows to be unsound on overlapping copies.

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
whose branches allocate differently. OpenZeppelin 4.9's TokenTimelock is
an example: `_callOptionalReturn` copies the return data only when there
is some. After the join, `mem[mem[64]] = 0x08c379a0...` writes at an
unknown place. Every piece known below it is then forgotten, among them
the length word of the revert string at `ceil32(_1) + 228`. So the
length isn't forwarded, the loop's trip count isn't known, and the
destination can't be compared with the source.

Both branches left `mem[64] >= ceil32(_1) + 292`, above that piece. A
floor carried through the join keeps the piece. The loop then runs once
on known bytes, and the destination, at or above the floor, is apart from
the source below it.

**Second shape: a decoded offset.** An offset decoded from data (ABI
decoding of return data or calldata) places the source inside an earlier
allocation, and the destination is the allocation made after it. The
decoder's checks (`require _9 + 32 + len <= return_data.size`...) are path
facts that bound the source's end below the buffer's end. The buffer's end
is at most the floor, which is at most the destination. That is a
comparison chained through a relational fact, not a constant bound.

**Third shape: a pointer stored in memory.** These are proven only when
the forward pass knows where the stored pointer came from. Otherwise they
are exactly what part 2 assumes.

## Part 1: the floor (sound)

### Definition

At a point p of a function's trace, the floor `F(p)` is an expression made
of values available at p (never of `mem[64]` itself) such that on every
run reaching p:

    word(mem[64]) >= word(F(p))      (unsigned; F(p) itself doesn't wrap)

The floor is NIL when nothing is known.

### Transfer

- **Start of a function.** The entry lines (the dispatcher's `mem[64] =
  128`) set it. For an internal function or a trace without entry lines,
  the floor is NIL.
- **`SETMEM(RANGE(64, 32), v)`.** `F = v`. It is exact, and needs no
  monotonicity: the floor bounds `mem[64]`, not the allocations.
- **Any other memory write.** A SETMEM, a call's or a copy's output, or a
  loop's writes summarized by lot 6's `LoopSummary::mem_writes` leaves `F`
  as it is when its range provably misses `[64, 96)`
  (`mem::overlaps(range, RANGE(64, 32), facts) == Tri::False`). Otherwise
  F becomes NIL. A write that may go anywhere (`writes_any & S_MEM`, an
  INTERNAL, an UNDEFINED) also makes it NIL.
- **A line that sets a variable F reads.** A SETVAR, setvars, or a call's
  results: F is rewritten to the variable's old value when the line gives
  it (`assignments` + `substitute`, as `Live::assign` does). Otherwise F
  becomes NIL.
- **Other state changes.** Storage, calls and transient storage make F NIL
  only when F reads what they change (F_STORAGE, F_STATE...). A floor made
  of a call's result is rare.
- **IF / MERGED_IF.** Each branch starts from F. After the IF, a branch
  that ends (halts, jumps away) is ignored. When both go on, the join is
  the first candidate among `F_then`, `F_else` and `F_before` that is
  `alg::le` both branches' floors (`Top::Memory`, the facts). Otherwise it
  is NIL. `F_before` is a valid candidate only when `le(F_before, F_then)`
  and `le(F_before, F_else)` are proven: a branch could also lower
  `mem[64]`.
- **WHILE / LABEL (a loop's head).** The floor before the loop when no
  iteration's write may touch `[64, 96)` (the loop's summary), NIL
  otherwise. A later improvement could keep the floor of a loop that only
  ever bumps `mem[64]`.

### Uses

A comparison that involves the current `mem[64]` gets the floor through a
substitution. Wherever an address reads `MEM(RANGE(64, 32))`, the
comparison sees `F + δ` instead, δ being one fresh atom per point,
non-negative and bounded by the memory model (an address the run accesses
is below 2^64: `Top::Memory`). The existing decisions (`mem::overlaps`,
`alg::le` with `Top::Memory` and the path facts) then decide
`mem[64] + 4 >= ceil32(_1) + 260` from `F = ceil32(_1) + 292` with no new
algebra.

The substitution is only for deciding. The trace keeps `mem[64]` as it is.

1. **Forwarding** (`simplify/mems.cpp`, the forward pass). MemState's
   overlap decisions for a write, and the pieces a read is made of, see the
   floor. A write at `mem[64] + k` then keeps the pieces below the floor.
2. **Copy proofs** (`loops/rewrite.cpp`, `to_setmem`, called from
   `SetmemWalk`). The same substitution in the `apart` / `ahead` proofs and
   in `misses`: a destination at `mem[64] + k`, `k >= 0`, starts at or above
   the floor. `SetmemWalk` carries the floor next to its path facts.
3. **Relational path facts** (the second shape). The copy proof chains
   `src_end <= buffer_end <= F <= dst_start` through the decoder's
   requires. Where `alg::le` can't chain a relational Cond fact with
   `ceil32` and sums, the decision procedure gets the missing step: an
   `int_le` through one fact `a <= b` with offsets, sound under the
   no-wrap conditions it already proves. Only what the corpus needs.

The floor is computed by one small module, `mem/floor.{hpp,cpp}`, used by
both walks. It is a value type with `transfer(line)`, `branch()`,
`join(a, b)`, `loop_head(while_line)` and `substitute(expr)`, so the two
walks can't disagree.

### Soundness

The invariant holds by induction on the trace:

- the floor is only made equal to a value `mem[64]` was given;
- it is kept only across lines that provably don't change `mem[64]`;
- it is rewritten through the assignments of the variables it reads;
- at a join, it is lowered to a value proven at most both branches'.

The substitution reads the comparison as "for some δ >= 0". That is
exactly what the invariant gives.

Every rewrite keeps its own checks (`apart`, `ahead`, `misses`, the
induction's trips). The floor only adds facts. The stagecheck on the whole
corpus, at every stage, must stay at 0 different.

## Part 2: solc's allocation, as an option (`--assume-alloc`)

### The assumption

> **(A)** A memory range the function reads through an address that is
> neither a constant nor derived from the current `mem[64]` lies entirely
> below the free memory pointer whenever a later allocation is made. Such
> addresses are a pointer read from memory, an offset decoded from data,
> or a word the contract was given.

That is solc's discipline. Objects are allocated by bumping `mem[64]`, and
pointers designate allocated objects. Hand-written assembly can break it,
which is why it is an option.

### Its one use

The copy proof (`to_setmem`). When `apart` and `ahead` aren't proven, the
copy is converted under (A) exactly when:

- the **destination** starts at or above the floor (a fresh allocation:
  `mem[64] + k`, or an expression proven `>=` the floor);
- the **source**'s address reads memory or a decoded offset, or a word
  the contract was given, and isn't derived from the current `mem[64]`.

Never under (A):

- a copy whose source and destination are both relative to the same base
  (an in-place move);
- a copy whose source is at or above the floor (a temporary buffer, such
  as `abi.encode` scratch space);
- anything `dubious` would take beyond these.

### Interface

- `SimplifyOptions::assume_alloc` and `RunFlags::assume_alloc`;
  `loops::RewriteOptions::assume_alloc`.
- `driver::PipelineOptions`, `DecompileOptions`.
- The CLI's `--assume-alloc`, the environment's `PANORAMIX_ASSUME_ALLOC=1`,
  and the python module's `decompile(..., assume_alloc=False)` keyword.
  Every existing interface is unchanged when it is off.
- `stagecheck` and `text_check` accept `--assume-alloc`, to measure where
  (A) fails.
- **Display.** When the option is on, the contract's header gains one
  comment line saying the copies were converted assuming solc's allocation.
  Nothing else changes.

### Checking it

`stagecheck --stage folded --assume-alloc` on the whole corpus counts the
calls that differ. Any difference is a contract that breaks (A). It is
reported, and the option documented with that number.

## Validation

1. **Unit tests (doctest)**, `mem_floor_test.cpp`:
   - the transfer rules: a write of `mem[64]`, a write missing `[64,96)`,
     an unknown write, a variable of F set again, the joins (each
     candidate, and none), and a loop that writes or doesn't write
     `mem[64]`;
   - forwarding through a join (the TokenTimelock shape), and the copy
     shapes 1 and 2 converted;
   - negative cases: `mem[64]` lowered in a branch, a write over `[64,96)`
     at an unknown place, an in-place move. These run in the trace machine
     against the loop, as `loops_rewrite_test` does;
   - (A): a stored-pointer source converted only with the option, and an
     in-place move never.
2. **The corpus** (`tools/fetch_corpus.sh /home/claude/corpus`, 861
   contracts):
   - copy loops and while loops before and after (`tools/loop_lines.py`),
     with and without the option;
   - `stagecheck --stage folded` and `text_check` on every contract:
     **0 different** without the option, the count reported with it;
   - CPU time before and after: the floor must cost little, one
     substitution per comparison that reads `mem[64]`.
3. **The existing suites**: release and ASan/UBSan, and the python tests.
