# The manual review of the decompiled contracts

Every contract of the corpus is compared by hand with its source, by reviewers
(agents), in tranches of 600. The review looks at three things:

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

The result is 9,859 contracts, of which 8,838 have distinct bytecode, in 15
tranches.

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
