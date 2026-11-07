#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Build the DRA-146 personal memory (native/personal/mem.om) with the pinned omc (omega-mv e5b32567), and
# the negative-control build mem-nosup (OMSUP 0: supersession disabled; exactly one changed line).
# Usage: OMC=path/to/omc [OUT=dir] [CORE=n] sh tests/personal/build-mem.sh
set -eu
here=$(cd "$(dirname "$0")/../.." && pwd)
PIN=2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f
OMC=${OMC:?set OMC to the pinned omc}
OUT=${OUT:-$here/../build-memory}
CORE=${CORE:-2}
got=$(sha256sum "$OMC" | cut -d' ' -f1)
[ "$got" = "$PIN" ] || { echo "OMC_PIN_MISMATCH $got" >&2; exit 3; }
mkdir -p "$OUT"
cp "$here/native/personal/mem.om" "$OUT/mem.om"
sed 's/^const OMSUP ulong 1$/const OMSUP ulong 0/' "$OUT/mem.om" > "$OUT/mem-nosup.om"
n=$(diff "$OUT/mem.om" "$OUT/mem-nosup.om" | grep -c '^>' || true)
[ "$n" = 1 ] || { echo "SED_CHANGED $n lines, want 1" >&2; exit 4; }
for b in mem mem-nosup; do
  set +e
  taskset -c "$CORE" nice -n 10 "$OMC" < "$OUT/$b.om" > "$OUT/$b.tmp"
  rc=$?
  set -e
  [ $rc -eq 0 ] || { rm -f "$OUT/$b.tmp"; echo "BUILD_FAIL $b omc rc=$rc" >&2; exit 1; }
  chmod +x "$OUT/$b.tmp"; mv "$OUT/$b.tmp" "$OUT/$b"
  echo "BUILD_OK $(sha256sum "$OUT/$b" | cut -d' ' -f1) $OUT/$b source_sha256 $(sha256sum "$OUT/$b.om" | cut -d' ' -f1)"
done
