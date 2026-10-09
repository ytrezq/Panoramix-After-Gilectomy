#!/bin/bash
# The corpus under a profiler, contract by contract, several at a time:
#
#   tools/prof_corpus.sh MODE BIN OUTDIR DIR[:DIR...] [WORKERS]
#
# MODE:
#   cachegrind  valgrind's, the caches and the branches simulated (the L1s
#               of a Sapphire Rapids, its 2 MiB L2 as the last level); the
#               AVX2 paths (PANORAMIX_ISA=avx2: no valgrind has AVX-512).
#               OUTDIR/NAME.out; then `cg_merge -o all.out OUTDIR/*.out`
#               and cg_annotate.
#   bbfreq      DynamoRIO's, natively (the AVX-512 paths), the executions of
#               every instruction (tools/bbfreq: $DYNAMORIO the build of
#               DynamoRIO, $BBFREQ its libbbfreq.so); OUTDIR/NAME/bbfreq.PID,
#               for tools/bbf_agg.py.
#   perf        perf record -g of the CPU clock (the kernel too: the page
#               faults, the TLB shootdowns), natively; OUTDIR/NAME.data
#               ($PERF: the perf binary).
# No time limits (PANORAMIX_TIMEOUT=0: the same work at any speed). A
# contract is claimed with a directory made in OUTDIR/.claims (mkdir is
# atomic): a second run of the same command goes on where the first
# stopped, and the workers share the list. OUTDIR/done: each contract's
# exit status and seconds.
mode=$1; bin=$(realpath "$2"); out=$3; dirs=$4; workers=${5:-1}
[ -n "$dirs" ] || { sed -n '2,30p' "$0"; exit 2; }
mkdir -p "$out/.claims"
export PANORAMIX_TIMEOUT=0 PANORAMIX_LOG=error
files=$(for d in $(echo "$dirs" | tr ':' ' '); do ls "$d"/*.hex; done)
worker() {
    local f n s
    for f in $files; do
        n=$(basename "$f" .hex)
        mkdir "$out/.claims/$n" 2>/dev/null || continue
        s=$(date +%s)
        case $mode in
        cachegrind)
            PANORAMIX_ISA=avx2 valgrind --tool=cachegrind --cache-sim=yes --branch-sim=yes \
                --I1=32768,8,64 --D1=49152,12,64 --LL=2097152,16,64 \
                --cachegrind-out-file="$out/$n.out" "$bin" decompile "$f" --no-color -j 1 \
                > /dev/null 2> "$out/$n.err" ;;
        bbfreq)
            mkdir -p "$out/$n"
            "$DYNAMORIO/bin64/drrun" -c "$BBFREQ" "$out/$n" -- "$bin" decompile "$f" --no-color -j 1 \
                > /dev/null 2> "$out/$n/err.txt" ;;
        perf)
            "${PERF:-perf}" record -e cpu-clock -F 1000 -g -o "$out/$n.data" -- \
                "$bin" decompile "$f" --no-color -j 1 > /dev/null 2> "$out/$n.err" ;;
        *)
            echo "unknown mode $mode"; exit 2 ;;
        esac
        echo "$n rc=$? $(( $(date +%s) - s ))s" >> "$out/done"
    done
}
for i in $(seq "$workers"); do
    worker &
done
wait
