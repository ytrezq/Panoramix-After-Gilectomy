#!/bin/bash
# Pack the compiled corpus: one PROGRAM.tar.xz per program of BUILD into OUT,
# with index.jsonl and errors.jsonl copied as they are. Programs already
# packed (OUT/PROGRAM.tar.xz present) are skipped, so the script resumes.
#   tools/pack_build.sh BUILD OUT
set -euo pipefail
BUILD=$1
OUT=$2
mkdir -p "$OUT"
cp -p "$BUILD/index.jsonl" "$BUILD/errors.jsonl" "$OUT/"
cd "$BUILD"
for p in $(ls -d */ | sed 's#/$##' | sort); do
  [ -e "$OUT/$p.tar.xz" ] && continue
  # A fixed order, owner and time, so the same build packs to the same bytes.
  tar --sort=name --owner=0 --group=0 --numeric-owner --mtime='2026-11-08 00:00Z' \
      -cf - "$p" | nice -n 10 xz -9 -T2 > "$OUT/$p.tar.xz.part"
  mv "$OUT/$p.tar.xz.part" "$OUT/$p.tar.xz"
  echo "$p $(du -s --apparent-size --block-size=1M "$p" | cut -f1)MB -> $(( $(stat -c %s "$OUT/$p.tar.xz") / 1024 / 1024 ))MB"
done
echo "== all packed"
