#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Build the DRA-146 personal tools with the pinned omc (omega-mv e5b32567, the aarch64 pin of
# tests/omegallm/build.sh): mpack (masked token streams) and peval (eval splitter, scorers, aggregator).
# Usage: OMC=path/to/omc [OUT=dir] [CORE=n] sh tests/personal/build.sh
set -eu
here=$(cd "$(dirname "$0")/../.." && pwd)
PIN=2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f
OMC=${OMC:?set OMC to the pinned omc}
OUT=${OUT:-$here/../build-personal}
CORE=${CORE:-2}
got=$(sha256sum "$OMC" | cut -d' ' -f1)
[ "$got" = "$PIN" ] || { echo "OMC_PIN_MISMATCH $got" >&2; exit 3; }
mkdir -p "$OUT"
src=$here/native/personal
cp "$src/mpack.om" "$OUT/mpack.om"
{ printf 'om2\n'; cat "$here/native/omegallm/net/json.om" "$src/peval.om"; } > "$OUT/peval.om"
for n in mpack peval; do
  set +e
  taskset -c "$CORE" nice -n 10 "$OMC" < "$OUT/$n.om" > "$OUT/$n.tmp"
  rc=$?
  set -e
  [ $rc -eq 0 ] || { rm -f "$OUT/$n.tmp"; echo "BUILD_FAIL $n omc rc=$rc" >&2; exit 1; }
  chmod +x "$OUT/$n.tmp"; mv "$OUT/$n.tmp" "$OUT/$n"
  echo "BUILD_OK $(sha256sum "$OUT/$n" | cut -d' ' -f1) $OUT/$n source_sha256 $(sha256sum "$OUT/$n.om" | cut -d' ' -f1)"
done
