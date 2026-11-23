# The manual review of the decompiled contracts

Every contract of the corpus is compared by hand with its source, by reviewers
(agents), in tranches of 400. The review looks at three things:

- loop detection;
- the exactness of the semantics;
- simplification.

The fixes it leads to are not specific to a language or a compiler.

| File | What |
|---|---|
| `contracts.jsonl` | the contracts to review, in review order, with their tranche |
| `INSTRUCTIONS.md` | what a reviewer does, and the schema of its result file |
| `tNN/results/ID.json` | a tranche's results: one file per contract |
| `tNN/summary.md`, `tNN/findings.jsonl` | a tranche's results put together, by `tools/review_summary.py` |
| `r2/` | round 2 over the first tranche of 400, after the fixes round 1 led to: its instructions, one result per contract, `summary.md`, `regressions.jsonl`, `new_findings.jsonl` (by `tools/review_round2.py`) |

## The contracts

`tools/review_select.py` makes the list from the compiled corpus (`../compiled/`):

- **Which contracts:** a project's own contracts whose ABI has a function, a
  fallback or a receive. Contracts under `lib/`, `node_modules/`,
  `dependencies/`, `.deps/` or `vendor/` are left out, and so are tests, mocks,
  scripts and harnesses.
- **Which build:** a contract's builds count as one contract. The build
  reviewed is chosen in this order:
  - the newest compiler;
  - then the newest EVM version;
  - then the optimizer's build before `-noopt`;
  - then the legacy code generator before via-IR.
- **Duplicates:** contracts whose reviewed bytecode is the same are reviewed
  once.
- **Order:** first the contracts `compare_largest.py` compared (each project's
  largest own contract), then the others, the largest bytecode first.

The result is 9,859 contracts, of which 8,838 have distinct bytecode, in 23
tranches of 400. Round 1 cut them in tranches of 600, so its `t01` covers the
first 600 ids.

## Running a tranche

    tools/unpack_build.sh BUILD
    tools/review_select.py --build BUILD --compare results/full-2026-11-08/results.jsonl --out review/contracts.jsonl
    tools/review_pack.py --build BUILD --sources immunefi --contracts review/contracts.jsonl --tranche N \
        --pancxx .../pancxx --sigdb .../sigdb2.bin --out WORK --batches 20

`review_pack.py` writes three things into WORK:

- `dec/ID.txt` and `dec/ID.json`, the decompiled text and its JSON;
- `packs/ID.md`, the pack: function by function, the source beside the
  decompiled code;
- `batches/bNN.txt`, the ids split into batches balanced by the packs' lines.

Each reviewer reads `INSTRUCTIONS.md` and one batch, and writes
`WORK/results/ID.json`. Then:

    tools/review_summary.py --contracts review/contracts.jsonl --results WORK/results --out review/tNN --tranche N

The results are copied into `review/tNN/results/`. The packs and the texts can be
made again, so they aren't kept.

## Round 2: after the fixes

Round 1 (`t01`, 586 of its 600 contracts) led to fixes:

- GAS reads;
- the free-memory pointer;
- SafeMath's exact revert data and check order;
- ABI data with several dynamic arguments;
- unknown functions' parameters by place;
- hex in whole bytes and durations;
- dead lines after ending branches;
- rotations.

Round 2 runs on the first tranche of 400 with the decompiler after those
fixes (cxx23 at bc67cddf5c). It decompiles the 400 again. For each contract, a
reviewer reads the diff from round 1's text to the new one, beside the source
and round 1's findings. The reviewer checks every change, gives each round-1
finding a status (`fixed`, `still`, `partly`, `worse`, `gone`), and reports
regressions. The contracts round 1 hadn't reviewed are reviewed whole.

`r2/summary.md` has the result: the statuses, the regressions by kind and
severity, the causes the reviewers name, and the execution checks of the same
400.


## Round 3: the readability regressions fixed

Round 2's regressions are fixed before the review goes on to the next
tranche. `tools/readability.py` measures what the reviewers looked for and
compares two sets of texts function by function; `make readability` runs it
over the npm corpus against the committed baseline
`tests/readability/npm.jsonl.xz` (`BUILD.md`, "The readability check"), so a
change that makes texts less readable fails without a manual review.

`r3/summary.md` has the numbers (on the 400: 1,552 regressions against round
1's texts at the start, 381 at the end; on npm: 626 and 202), the causes
fixed, what round 3 accepts (`r3/allow.txt`) and what is left. The
`r3/regressions_*.jsonl` files list the regressions of the six comparisons
at the end.
