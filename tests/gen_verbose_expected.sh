#!/bin/bash
# python's output with --verbose or --explain, for tests/test_verbose.py:
#   tests/gen_verbose_expected.sh PYTHON REPO FILE.hex MODE OUT
# (no time limits: PANORAMIX_TIMEOUT=0; again when another python held
# the signatures' shelve - gdbm's lock - which fails its lookups)
PYTHON=$1; REPO=$2; HEX=$(realpath $3); MODE=$4; OUT=$5
for try in 1 2 3 4 5 6 7 8; do
  (cd $REPO && PANORAMIX_TIMEOUT=0 PYTHONPATH=$REPO PYTHONINTMAXSTRDIGITS=0 \
     $PYTHON -m panoramix $(cat $HEX) $MODE > $OUT.tmp 2> $OUT.err)
  grep -q "Resource temporarily unavailable" $OUT.err || break
  sleep $((5 * try))
done
mv $OUT.tmp $OUT
rm -f $OUT.err
