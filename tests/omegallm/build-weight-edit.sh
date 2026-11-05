#!/bin/sh
# Build the bounded experimental checkpoint editor; no GPU code is added.
set -eu
here=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
: "${OUT:?set OUT to a private build directory}"
: "${OMC:?set OMC to the compiler pinned by build.sh}"
TARGET=aarch64 sh "$here/tests/omegallm/build.sh"
test "$(grep -c '^fn main to int$' "$OUT/ollm.om")" = 1
sed 's/^fn main to int$/fn oldmain to int/' "$OUT/ollm.om" > "$OUT/weight-edit-all.om"
cat "$here/tests/omegallm/weight-edit.om" >> "$OUT/weight-edit-all.om"
"$OMC" < "$OUT/weight-edit-all.om" > "$OUT/weight-edit.new"
chmod +x "$OUT/weight-edit.new"
mv "$OUT/weight-edit.new" "$OUT/weight-edit"
sha256sum "$OUT/weight-edit" "$OUT/weight-edit-all.om"
