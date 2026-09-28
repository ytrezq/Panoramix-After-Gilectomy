#!/bin/bash
# Inputs no compiler makes, that must not take the process down: the
# decompilation finishes (rc 0), within the memory it is given.
#   tests/robustness.sh [panasm]
cd "$(dirname "$0")/.."
PANASM=${1:-build/panasm}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

# hex of a 2-byte big-endian number
h2() { printf "%02x%02x" $(($1 >> 8 & 255)) $(($1 & 255)); }

# n nested ifs: require(!cd[4 + 32 i]) n times (python: a RecursionError
# from 700 on; the folder's paths grow as n^3)
nested_ifs() {
    local n=$1 code="6080604052" i len dest
    len=5
    for ((i = 0; i < n; i++)); do
        dest=$((len + 10))
        code+="61$(h2 $((4 + 32 * i)))351561$(h2 $dest)57fe5b"
        len=$((len + 11))
    done
    echo "${code}00"
}

# cd[cd[cd[...]]]: an expression n deep
cd_chain() {
    local n=$1 code="600435" i
    for ((i = 0; i < n; i++)); do code+="35"; done
    echo "${code}60005500"
}

run() {
    local name=$1 limit_s=$2
    shift 2
    local s e rc
    s=$(date +%s)
    PANORAMIX_LOG=error PANORAMIX_MAX_MEMORY=${MAXMEM:-2048} \
        timeout $((limit_s * 2)) "$PANASM" decompile "$tmp/$name.hex" --no-color \
        > "$tmp/$name.out" 2> "$tmp/$name.err"
    rc=$?
    e=$(date +%s)
    if [ $rc -ne 0 ] || ! grep -q "Palkeoramix decompiler" "$tmp/$name.out"; then
        echo "FAIL $name: rc=$rc"
        head -5 "$tmp/$name.err"
        fail=1
    elif [ $((e - s)) -gt "$limit_s" ]; then
        echo "SLOW $name: $((e - s)) s"
        fail=1
    else
        echo "ok   $name ($((e - s)) s)"
    fi
}

nested_ifs 2000 > "$tmp/nested_ifs_2000.hex"
run nested_ifs_2000 60
cd_chain 20000 > "$tmp/cd_chain_20000.hex"
run cd_chain_20000 60
echo "60" > "$tmp/truncated_push.hex"          # a push without its bytes
run truncated_push 5
echo "fe" > "$tmp/invalid.hex"
run invalid 5
# a function whose memory limit is reached: the function is reported
# as a problem, the rest goes on
MAXMEM=64 run nested_ifs_2000 60

exit $fail
