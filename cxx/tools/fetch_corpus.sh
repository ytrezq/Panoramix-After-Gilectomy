#!/bin/bash
# The validation corpus: the runtime bytecode of the compiled artifacts that
# npm packages ship (tests/corpus_from_npm.py), plus the repository's own
# contracts (tests/corpus, tests/fixtures). Reproducible: pinned versions.
#
#   cxx/tools/fetch_corpus.sh OUT        # OUT/npm/*.tgz, OUT/hex/*.hex, OUT/all_hex.txt
#
# (The first corpus of 1,121 contracts lived in /tmp and was lost with its
# container; this one is built the same way from the same families of
# packages: OpenZeppelin 2-5, Uniswap v2/v3/v4, Aave v3, Safe, 0x,
# ERC-4337, ENS.)
set -u
OUT=${1:?usage: fetch_corpus.sh OUT}
REPO=$(cd "$(dirname "$0")/../.." && pwd)
mkdir -p "$OUT/npm" "$OUT/hex"
OUT=$(cd "$OUT" && pwd)
PKGS=(
  openzeppelin-solidity@2.5.1
  @openzeppelin/contracts@3.0.0
  @openzeppelin/contracts@3.4.2
  @openzeppelin/contracts@4.9.6
  @openzeppelin/contracts@5.0.2
  @openzeppelin/contracts@5.4.0
  @uniswap/v2-core@1.0.1
  @uniswap/v2-periphery@1.1.0-beta.0
  @uniswap/v3-core@1.0.1
  @uniswap/v3-periphery@1.4.4
  @uniswap/v4-core@1.0.2
  @aave/core-v3@1.19.3
  @gnosis.pm/safe-contracts@1.3.0
  @safe-global/safe-contracts@1.4.1
  @account-abstraction/contracts@0.6.0
  @account-abstraction/contracts@0.7.0
  @ensdomains/ens-contracts@1.2.2
  @0x/contracts-exchange@3.2.38
  @0x/contracts-coordinator@3.1.38
  @0x/contracts-staking@2.0.45
  @0x/contracts-exchange-forwarder@4.2.38
  @0x/contracts-dev-utils@1.3.36
  @0x/contracts-erc20@3.3.57
)
fail=0
for p in "${PKGS[@]}"; do
  if ! (cd "$OUT/npm" && timeout 300 npm pack --silent "$p" > /dev/null 2>> "$OUT/npm/errors.txt"); then
    echo "not fetched: $p" >&2; fail=$((fail + 1))
  fi
done
python3 "$REPO/tests/corpus_from_npm.py" "$OUT/npm" "$OUT/hex"
for d in "$REPO/tests/corpus" "$REPO/tests/fixtures"; do
  for f in "$d"/*.hex; do [ -f "$f" ] && cp --update=none "$f" "$OUT/hex/repo_$(basename "$f")"; done
done
ls "$OUT"/hex/*.hex > "$OUT/all_hex.txt"
echo "$(wc -l < "$OUT/all_hex.txt") contracts in $OUT/all_hex.txt ($fail packages not fetched)"
