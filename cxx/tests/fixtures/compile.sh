#!/bin/bash
# The fixtures' bytecode (tests/fixtures_test.cpp checks each .hex): code that
# isn't solc's high-level output, compiled by pinned compilers into its
# runtime code, one line of hex.
#   SOLC=solc-0.8.30 VYPER_DIR=dir-of-vyper-VERSION-venvs compile.sh
# yul/X.yul      solc --strict-assembly (an object without a constructor: its
#                code is the runtime code)               -> yul/X.hex
# vyper/X_03.vy  vyper 0.3.7, 0.3.10 -f bytecode_runtime -> vyper/X-0.3.7.hex...
# vyper/X_04.vy  vyper 0.4.0, 0.4.3                      -> vyper/X-0.4.0.hex...
# asm/X.asm      hand-written (asm/assemble.py)          -> asm/X.hex
set -eo pipefail
here=$(cd "$(dirname "$0")" && pwd)
SOLC=${SOLC:-/home/claude/solc-cache/solc-0.8.30}
VYPER_DIR=${VYPER_DIR:-/home/claude/solc-cache}
for f in "$here"/yul/*.yul; do
    out="${f%.yul}.hex"
    "$SOLC" --strict-assembly --bin "$f" | awk '/Binary representation:/ { getline; print; exit }' > "$out"
done
for f in "$here"/vyper/*_03.vy "$here"/vyper/*_04.vy; do
    base=$(basename "$f" .vy)
    name=${base%_0?}
    case $base in
        *_03) versions="0.3.7 0.3.10" ;;
        *_04) versions="0.4.0 0.4.3" ;;
    esac
    for v in $versions; do
        "$VYPER_DIR/vyper-$v/bin/vyper" -f bytecode_runtime "$f" | sed 's/^0x//' > "$here/vyper/$name-$v.hex"
    done
done
for f in "$here"/asm/*.asm; do
    python3 "$here/asm/assemble.py" "$f" > "${f%.asm}.hex"
done
