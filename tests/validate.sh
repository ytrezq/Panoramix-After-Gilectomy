#!/bin/bash
# The validation of a change, as run before every commit:
#
#   tests/validate.sh [--quick] [SEED]
#
# - the corpora against python's references - tests/corpus and
#   tests/synthetic, and the one of $NPM_CORPUS (tests/corpus_from_npm.py's
#   .hex files) when $NPM_REFS has pypy's outputs for them (NAME.pan:
#   `python -m panoramix`, colors removed, with the signature database) -
#   three times: as they are, with the VM's own checks
#   (PANORAMIX_CHECK_LCA=1: its shortcuts compared with python's walks),
#   and with a compaction at every round (PANORAMIX_COMPACT_MIB=1);
# - the random differential unit tests, with SEED (default: the day of
#   the year);
# - the differential tests of the layers on tests/corpus (test_vm
#   --functions, test_whiles, test_simplify: an hour or so; not with
#   --quick);
# - make check.
#
# The python implementation is found as the tests find it ($PANORAMIX_PY,
# or ../panoramix), the signature database as tests/run_corpus.sh does.
# A line per step (its time, the last line of its output, kept in
# build/validate/NAME.txt); exits 1 when one of them failed.
cd "$(dirname "$0")/.."
quick=0
[ "$1" = "--quick" ] && { quick=1; shift; }
seed=${1:-$(date +%j)}
unset PANORAMIX_SIGDB           # the unit tests compare without one
out=build/validate
mkdir -p $out
failed=0
step() {        # step NAME CMD...: runs it, its output in $out/NAME.txt
    local name=$1; shift
    local t0=$(date +%s)
    if "$@" > $out/$name.txt 2>&1; then
        printf "ok    %-16s %5ds  %s\n" "$name" $(( $(date +%s) - t0 )) "$(tail -n 1 $out/$name.txt | cut -c1-70)"
    else
        failed=1
        printf "FAIL  %-16s %5ds  %s\n" "$name" $(( $(date +%s) - t0 )) "$(tail -n 1 $out/$name.txt | cut -c1-70)"
    fi
}
with() {        # with VAR=VALUE CMD...
    ( export "$1"; shift; "$@" )
}
corpus() {      # corpus DIR REFDIR SUFFIX [DIR REFDIR SUFFIX...]: every DIR/*.hex against REFDIR/NAME.SUFFIX
    local n=0 bad=0
    while [ $# -ge 3 ]; do
        local dir=$1 refs=$2 suffix=$3
        shift 3
        for f in "$dir"/*.hex; do
            local name=$(basename "$f" .hex)
            [ -f "$refs/$name$suffix" ] || continue
            n=$((n + 1))
            if ! PANORAMIX_SIGDB=$PWD/build/abi_db.bin PANORAMIX_ABI_DUMP=$dump build/panasm decompile "$f" --no-color 2>/dev/null \
                    | cmp -s - "$refs/$name$suffix"; then
                bad=$((bad + 1))
                echo "DIFF $name"
            fi
        done
    done
    echo "$n contracts, $bad differences"
    [ $bad -eq 0 ] && [ $n -gt 0 ]
}
make -s all || exit 1
dump=$(realpath "${PANORAMIX_ABI_DUMP:-../panoramix/panoramix/data/abi_dump.xz}")
if [ ! -f build/abi_db.bin ]; then
    build/panasm build-db "$dump" build/abi_db.bin 2>/dev/null \
        || { echo "no signature database: set PANORAMIX_ABI_DUMP"; exit 2; }
fi
C=(tests/corpus tests/corpus/expected .txt tests/synthetic tests/synthetic/expected .txt)
step corpus corpus "${C[@]}"
step corpus_check with PANORAMIX_CHECK_LCA=1 corpus "${C[@]}"
step corpus_compact with PANORAMIX_COMPACT_MIB=1 corpus "${C[@]}"
if [ -n "$NPM_CORPUS" ] && [ -n "$NPM_REFS" ]; then
    N=("$NPM_CORPUS" "$NPM_REFS" .pan)
    step npm corpus "${N[@]}"
    step npm_check with PANORAMIX_CHECK_LCA=1 corpus "${N[@]}"
    step npm_compact with PANORAMIX_COMPACT_MIB=1 corpus "${N[@]}"
fi
step algebra with BIG=1 python3 tests/test_algebra.py $seed 300
step agz python3 tests/test_agz.py $seed 1000
step agz_family python3 tests/test_agz_family.py $seed 300
step simplify_exp python3 tests/test_simplify_exp.py $seed 300
step memloc python3 tests/test_memloc.py $seed
step arith python3 tests/test_arith.py $seed
step matcher python3 tests/test_matcher.py $seed 2000
step stack python3 tests/test_stack.py $seed
step prettify_random python3 tests/test_prettify_random.py $seed 500
step fold_random python3 tests/test_fold_random.py $seed 1000
step trace_random with PANORAMIX_CHECK_LCA=1 python3 tests/test_trace_random.py $seed 150
if [ $quick -eq 0 ]; then
    step vm with PANORAMIX_CHECK_LCA=1 python3 tests/test_vm.py --functions
    step whiles with PANORAMIX_CHECK_LCA=1 python3 tests/test_whiles.py
    step simplify python3 tests/test_simplify.py
fi
step make_check make check
exit $failed
