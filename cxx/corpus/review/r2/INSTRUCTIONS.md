# Round 2: checking the fixes, looking for regressions

Read this whole file first. Re-read it whenever your context was summarized.

## What happened since round 1

Round 1 compared 586 decompiled contracts with their sources, by hand. Its
instructions are `/home/claude/shared/review/INSTRUCTIONS.md`. Read these
sections of it, which still apply:

- "What is normal in the text";
- "Known patterns";
- "Counting loops";
- "The result file" (its findings' schema and severities);
- "Rules".

Since round 1, these fixes were merged into the decompiler (C++23, `pancxx`):

- **GAS:** every GAS read is its own value, a variable set where the code
  reads it. It is never moved, merged or taken as loop-invariant.
- **The free-memory pointer:** a read of `mem[64]` held by a variable is kept
  as what `mem[64]` held. Joins and loops keep a constant floor.
- **SafeMath:**
  - revert data are exact, past the message too;
  - checks that fail differently keep their order.
- **ABI data of several dynamic arguments** are decoded exactly.
- **Unknown functions' parameters** are `_paramN` for the N-th calldata word.
- **Display:**
  - hex constants show whole bytes;
  - multiples of 3600 or 86400 print as durations only for small counts.
- **Dead lines:** the lines after a line whose every path ends are dropped.
- **Rotations** copy two statements at most, so no first iteration appears
  before the loop (P3).

The texts were made again by the current build. **Your job, for each
contract:**

- check every change in its text: each must be right, and nothing may get
  worse;
- say what became of each round-1 finding;
- report any new problem the changes show.

Execution checks (stagecheck, text_check) also run over these 400 contracts,
apart from you. Your reading matters most where sampled calls don't reach:
rare branches, loops, names, readability.

## Your inputs, for each id

- **The round-1 result:** `/home/claude/shared/review/t01/results/ID.json`.
  Number its `findings` from 1.
- **The diff from the old text to the new:** `/home/claude/shared/review/r2/diffs/ID.diff`.
  Each hunk header names the enclosing `def`. **No diff file means the text
  did not change.**
- **The new pack:** `/home/claude/shared/review/r2/packs/ID.md`, with the source
  beside the new text, function by function.
- **The texts:** the new one is `r2/dec/ID.txt`, the old one
  `/home/claude/shared/review/t01/dec/ID.txt`.
- **Your batch:** `/home/claude/shared/review/r2/batches/bNN.txt`; NN is in
  your prompt.

Read in chunks of 300 to 600 lines (Read with `offset`/`limit`). Don't re-read.

## The procedure for one contract

1. If `/home/claude/shared/review/r2/results/ID.json` exists, skip the contract.
2. **No round-1 result:** 14 contracts have none. Review those whole, as
   round 1's instructions say, using the new pack, and write round 1's schema
   with `"round1": true` into `r2/results/ID.json`.
3. Read the round-1 result: its findings, notes and summary.
4. **No diff file:** every round-1 finding stays as it was. Write the result
   with `"text_changed": false` and go on.
5. **Read the diff hunk by hunk.** For each changed function, compare the new
   lines with the source (the pack's section for that function) and with the
   old lines. Decide:
   - **Regression.** The new text is wrong where the old text was right:
     - a condition, revert, write, event, call, return or argument now differs
       from what the bytecode does;
     - a loop is lost, or worse;
     - a line is harder to read than before;
     - a name is now wrong;
     - a new `Decompilation aborted`;
     - a path is lost.

     Use round 1's severities.
   - **New finding.** A problem in the changed lines that isn't a regression,
     such as a call decoded now but with something still off.
   - **Improvement or neutral change.** Note it briefly.
6. **Each round-1 finding** gets one status:
   - `fixed`;
   - `still`;
   - `partly`;
   - `worse`;
   - `gone`: the function changed so much that the finding no longer applies.
     Say why.
7. **A very long diff** (more than about 3,000 lines) may be reviewed by
   structure. For each changed function, check its control flow, calls,
   loops, storage writes, events and reverts, and say so in `notes`.
8. **A suspicion is checked by execution** when you can, with the tools in
   `/home/claude/wt-cxx/cxx/build-r2` (same use as round 1: `stagecheck
   --function`, `text_check run`, `evmrun`, `pancxx disasm`). Run them one at a
   time, with `nice -n 10`.

## The result file

`/home/claude/shared/review/r2/results/ID.json`. Write `ID.json.part` first,
then rename it:

```json
{
  "id": "c00001",
  "text_changed": true,
  "lines_old": 1234,
  "lines_new": 1100,
  "changed_functions": 12,
  "old_findings": [
    {"n": 1, "kind": "loop", "status": "fixed | still | partly | worse | gone", "note": "short"}
  ],
  "regressions": [
    {
      "kind": "semantics | loop | simplification | coverage | naming",
      "severity": "high | medium | low",
      "function": "name(types)",
      "lines": "new text lines",
      "decompiled": "the new lines (short)",
      "old": "the old lines (short)",
      "source": "file:line and the source lines (short)",
      "issue": "what got worse",
      "rule": "the general rule that would fix it, true for any EVM code",
      "verified": "reading only | stagecheck ... | text_check ... | evmrun ..."
    }
  ],
  "new_findings": [],
  "improvements": "a few sentences: what got better (calls named, loops, size...)",
  "patterns": {"P1": 0, "P2": 3},
  "notes": "structural reviews, anything else",
  "summary": "one or two sentences: the regressions, or none, and what improved"
}
```

- `new_findings` use round 1's findings schema.
- `patterns` holds the counts the new pack's header gives (P1 to P6).
- Keep every field short. Report a repeated pattern once, with its count.

## Rules

- Don't edit or commit anything in `/home/claude/wt-cxx` or `/mnt/zcorpus`.
  Write only under `/home/claude/shared/review/r2/results/`.
- The machine has 2 CPUs: at most one execution tool at a time, with `nice`,
  and never a whole-corpus run.
- Credits are limited, so work economically:
  - read diffs and packs in chunks, and never re-read;
  - review by structure where a diff is huge;
  - write each result as soon as the contract is done.
- If you can't go on, stop after writing the current result. A new reviewer
  will skip the results already written.
- **Your final message to the main session** has three short lines:
  - the ids done;
  - the ids left;
  - the most important regressions, if any, with their ids, or "no
    regression".
