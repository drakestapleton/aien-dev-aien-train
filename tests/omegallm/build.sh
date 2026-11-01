#!/bin/sh
# Build ollm (aien-train#52) from native/omegallm/*.om with the pinned seeded omc.
# Usage: sh tests/omegallm/build.sh [--mutant a|b|c]
# Env: OMC (default ../omega-mv/seed/out/omc beside this clone), OUT (default ../build beside it),
#      CORE (taskset core, default 6).
# The mutant is made by sed on the concatenated copy only; exactly one line must change.
set -eu
here=$(cd "$(dirname "$0")/../.." && pwd)
OMC=${OMC:-$here/../omega-mv/seed/out/omc}
OUT=${OUT:-$here/../build}
CORE=${CORE:-6}
PIN=2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f
mut=
if [ $# -ge 1 ]; then
  [ "$1" = --mutant ] && [ $# -eq 2 ] || { echo "usage: build.sh [--mutant a|b|c]" >&2; exit 2; }
  mut=$2
fi
got=$(sha256sum "$OMC" | cut -d' ' -f1)
[ "$got" = "$PIN" ] || { echo "OMC_PIN_MISMATCH $got" >&2; exit 3; }
mkdir -p "$OUT"
src=$here/native/omegallm
name=ollm
cat "$src/math.om" "$src/data.om" "$src/model.om" "$src/adam.om" "$src/ckpt.om" "$src/cli.om" > "$OUT/ollm.om"
case "$mut" in
  '') ;;
  a) pat='s/^const OMUTA ulong 1$/const OMUTA ulong 0/' ;;
  b) pat='s/^const OMUTB ulong 1$/const OMUTB ulong 2/' ;;
  c) pat='s/^const OMUTC ulong 1$/const OMUTC ulong 0/' ;;
  *) echo "usage: build.sh [--mutant a|b|c]" >&2; exit 2 ;;
esac
if [ -n "$mut" ]; then
  name=ollm-mut-$mut
  sed "$pat" "$OUT/ollm.om" > "$OUT/$name.om"
  n=$(diff "$OUT/ollm.om" "$OUT/$name.om" | grep -c '^>' || true)
  [ "$n" = 1 ] || { echo "MUTANT_SED_CHANGED $n lines" >&2; exit 4; }
fi
set +e
taskset -c "$CORE" nice -n 19 "$OMC" < "$OUT/$name.om" > "$OUT/$name.tmp"
rc=$?
set -e
if [ $rc -ne 0 ]; then
  rm -f "$OUT/$name.tmp"
  echo "BUILD_FAIL omc rc=$rc" >&2
  exit 1
fi
chmod +x "$OUT/$name.tmp"
mv "$OUT/$name.tmp" "$OUT/$name"
echo "BUILD_OK $(sha256sum "$OUT/$name" | cut -d' ' -f1) $OUT/$name source_sha256 $(sha256sum "$OUT/$name.om" | cut -d' ' -f1)"
