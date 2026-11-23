# Round 4's changes not merged

Two exact changes, kept for the next round with the reason they wait.

- `mask_readings.patch` (`git am`, on cxx23 at 894f006e4b or later): the
  ranges' linear reading takes `k * (y >> off)`, 2^off dividing k, as k /
  2^off times the field in place, and the bits below `off` that the masks
  of one value clear as one atom - `96 * (n + 31 >> 5)` and `3 *
  ceil32(n)` compare equal, and more memory reads resolve. Its test fails
  without it. It frees 18 lines of `allow.txt`; it waits for the printer to
  write `2 * Mask(250, 5, x + 31) + ceil32(x)` as `3 * ceil32(x)` and for
  the storage forms to read a slot through a name (`../summary.md`, "What
  is left").
- `pointer_loop_floors.diff` (on cxx23 at cefeee9cca): the pointer
  worker's floors for loops - `var_floor` of a positive multiple of a
  floored atom, a rising loop variable's floor its memory-reading start,
  `forget_loop` reading a moved word as its floor plus an atom - and the
  mask readings' first form. Its parts are still behind environment
  switches (`PAN_NB1A`, `PAN_NB1B`, `PAN_NB1C`, `PAN_NVF1`, `PAN_NP1`,
  `PAN_NDEPTH`: set means off), which go before any commit.
  `pointer_loop_floors_regressions.txt` lists what each configuration loses.
