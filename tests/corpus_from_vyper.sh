#!/bin/bash
# A corpus of vyper bytecode: the examples of vyper 0.3.10 and 0.4.3,
# Curve's stableswap-ng and tricrypto-ng (0.3.10) and snekmate's mocks
# (0.4.3), each compiled as it is (the selectors dispatched through a
# jump table in the code, which panoramix doesn't follow: the whole
# contract is one function) and without optimization (the selectors
# compared one after the other), and some of 0.4.3's with its venom
# backend.
#
#   python3 -m venv V310 && V310/bin/pip install vyper==0.3.10
#   python3 -m venv V43 && V43/bin/pip install vyper==0.4.3
#   git clone --depth 1 --branch v0.3.10 https://github.com/vyperlang/vyper SRC/vyper0310
#   git clone --depth 1 --branch v0.4.3 https://github.com/vyperlang/vyper SRC/vyper043
#   git clone --depth 1 https://github.com/curvefi/stableswap-ng SRC/stableswap-ng
#   git clone --depth 1 https://github.com/curvefi/tricrypto-ng SRC/tricrypto-ng
#   git clone --depth 1 --branch v0.1.2 https://github.com/pcaversaccio/snekmate SRC/snekmate
#   tests/corpus_from_vyper.sh V310/bin/vyper V43/bin/vyper SRC OUT
#
# OUT/<prefix>_<name>.hex, the duplicates dropped; a source whose pragma
# pins an optimization is compiled without the pragma when unoptimized.
# snekmate's math_mock unoptimized is left out: its one function goes
# past any memory limit.
V310=$1; V43=$2; SRC=$3; OUT=$4
[ -n "$OUT" ] || { sed -n '2,22p' "$0"; exit 2; }
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
comp() {        # comp VYPER PREFIX FILE [OPTIONS...]
    local vy=$1 pre=$2 f=$3
    shift 3
    local n=$(basename "$f" .vy) code
    case " $* " in *" none "*)
        # (a copy without the pragma, where there is one: the others are
        # compiled where they are, for their relative imports)
        if grep -q "pragma optimize" "$f"; then
            grep -v "pragma optimize" "$f" > "$tmp/$n.vy"
            f=$tmp/$n.vy
        fi;;
    esac
    if code=$("$vy" -f bytecode_runtime "$@" "$f" 2>/dev/null); then
        echo "${code#0x}" > "$OUT/${pre}_$n.hex"
    else
        echo "not compiled: ${pre}_$n" >&2
    fi
}
cd "$SRC" || exit 2
SS="stableswap-ng/contracts/main/*.vy stableswap-ng/contracts/mocks/*.vy"
TC="tricrypto-ng/contracts/main/*.vy tricrypto-ng/contracts/mocks/*.vy"
# as they are
for f in vyper0310/examples/*.vy vyper0310/examples/*/*.vy; do comp "$V310" vy0310 "$f"; done
for f in $SS stableswap-ng/contracts/ProxyAdmin.vy; do comp "$V310" ssng "$f"; done
for f in $TC; do comp "$V310" tcng "$f"; done
for f in vyper043/examples/*.vy vyper043/examples/*/*.vy; do comp "$V43" vy043 "$f"; done
for f in snekmate/src/snekmate/*/mocks/*.vy; do comp "$V43" snek "$f" -p snekmate/src; done
# unoptimized
for f in vyper0310/examples/*.vy vyper0310/examples/*/*.vy $SS $TC; do
    comp "$V310" n0310 "$f" --optimize none
done
for f in vyper043/examples/*.vy vyper043/examples/*/*.vy; do comp "$V43" n043 "$f" --optimize none; done
for f in snekmate/src/snekmate/*/mocks/*.vy; do
    [ "$(basename "$f")" = math_mock.vy ] && continue
    comp "$V43" nsnek "$f" -p snekmate/src --optimize none
done
# venom
for f in vyper043/examples/tokens/*.vy vyper043/examples/auctions/*.vy \
         snekmate/src/snekmate/tokens/mocks/*.vy; do
    comp "$V43" venom "$f" -p snekmate/src --optimize none --experimental-codegen
done
cd "$OUT"
md5sum *.hex | sort | awk 'seen[$1]++ {print $2}' | xargs -r rm -f
echo "$(ls *.hex | wc -l) contracts"
