#!/bin/bash
# The corpus against python's output (tests/corpus/expected: pypy's
# `python -m panoramix`, colors removed, with the signature database),
# and the synthetic programs of tests/synthetic.
#
#   tests/run_corpus.sh [name...]
#
# The signature database is built once into build/abi_db.bin from
# panoramix's data/abi_dump.xz ($PANORAMIX_ABI_DUMP, or the python
# repository next to this one).
cd "$(dirname "$0")/.."
DUMP=${PANORAMIX_ABI_DUMP:-../panoramix/panoramix/data/abi_dump.xz}
export PANORAMIX_SIGDB=$PWD/build/abi_db.bin
if [ ! -f "$PANORAMIX_SIGDB" ]; then
    [ -f "$DUMP" ] || { echo "no signature dump ($DUMP): set PANORAMIX_ABI_DUMP"; exit 2; }
    build/panasm build-db "$DUMP" "$PANORAMIX_SIGDB" 2>/dev/null || exit 2
fi
mkdir -p build/corpus
bad=0; n=0
start=$(date +%s.%N)
for f in tests/corpus/*.hex tests/synthetic/*.hex; do
    name=$(basename "$f" .hex)
    dir=$(dirname "$f")
    [ $# -gt 0 ] && [[ " $* " != *" $name "* ]] && continue
    n=$((n + 1))
    build/panasm decompile "$f" --no-color > "build/corpus/$name.txt" 2> "build/corpus/$name.err"
    if cmp -s "$dir/expected/$name.txt" "build/corpus/$name.txt"; then
        echo "ok   $name"
    else
        bad=$((bad + 1))
        echo "DIFF $name ($(diff "$dir/expected/$name.txt" "build/corpus/$name.txt" | grep -c '^[<>]') lines)"
    fi
done
printf "%d contracts, %d differences, %.1f s\n" $n $bad "$(echo "$(date +%s.%N) - $start" | bc)"
[ $bad -eq 0 ]
