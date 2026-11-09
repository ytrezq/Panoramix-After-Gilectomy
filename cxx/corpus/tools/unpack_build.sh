#!/bin/sh
# Unpack the compiled corpus (compiled/PROGRAM.tar.xz, compiled/index.jsonl,
# compiled/errors.jsonl) into DEST: the layout compare_largest.py --build DEST
# and compare_source.py DEST read. With PROGRAM arguments, those programs only
# (index.jsonl still lists every artifact).
#   tools/unpack_build.sh DEST [PROGRAM...]
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
[ $# -ge 1 ] || { echo "usage: $0 DEST [PROGRAM...]" >&2; exit 1; }
dest=$1
shift
mkdir -p "$dest"
if [ $# -eq 0 ]; then
  set -- $(cd "$here/compiled" && ls -- *.tar.xz | sed 's/\.tar\.xz$//')
fi
for p in "$@"; do
  tar -xJf "$here/compiled/$p.tar.xz" -C "$dest"
done
cp "$here/compiled/index.jsonl" "$here/compiled/errors.jsonl" "$dest/"
