#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Build wprobe (DRA-187): ollm.om from tests/omegallm/build.sh with its main renamed, then wprobe.om.
# Needs OUT (a directory holding ollm.om, or where to build it) and the pinned omc in OMC
# (default ../omega-mv/seed/out/omc beside the aien-train checkout).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../.." && pwd)
: "${OUT:?set OUT}"
OMC=${OMC:-$root/../omega-mv/seed/out/omc}
CORE=${CORE:-0}
[ -f "$OUT/ollm.om" ] || OUT="$OUT" OMC="$OMC" CORE="$CORE" sh "$root/tests/omegallm/build.sh"
n=$(grep -c '^fn main to int$' "$OUT/ollm.om")
[ "$n" = 1 ] || { echo "expected one main in ollm.om, found $n" >&2; exit 1; }
sed 's/^fn main to int$/fn ollmmain to int/' "$OUT/ollm.om" > "$OUT/wprobe-all.om"
cat "$here/wprobe.om" >> "$OUT/wprobe-all.om"
taskset -c "$CORE" nice -n 19 "$OMC" < "$OUT/wprobe-all.om" > "$OUT/wprobe.tmp" 2> "$OUT/wprobe.err" || {
	cat "$OUT/wprobe.err" >&2; rm -f "$OUT/wprobe.tmp"; exit 1; }
chmod +x "$OUT/wprobe.tmp"
mv "$OUT/wprobe.tmp" "$OUT/wprobe"
echo "BUILD_OK $(sha256sum < "$OUT/wprobe" | cut -c1-64) $OUT/wprobe source_sha256 $(sha256sum < "$OUT/wprobe-all.om" | cut -c1-64) omc $(sha256sum < "$OMC" | cut -c1-64)"
