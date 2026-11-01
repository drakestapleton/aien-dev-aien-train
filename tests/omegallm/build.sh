#!/bin/sh
# Build ollm (aien-train#52) from native/omegallm/*.om with the pinned seeded omc.
# Usage: sh tests/omegallm/build.sh [--mutant a|b|c | --variant h5|h7]
# Env: OMC (default ../omega-mv/seed/out/omc beside this clone), OUT (default ../build beside it),
#      CORE (taskset core, default 6).
# Mutants (ollm-mut-X, one changed line) plant a defect the checks must catch. Variants (ollm-var-X,
# two changed lines) set both gcheck steps GCH and GCH2 to 1e-5 (h5) or 1e-7 (h7), the step sizes
# that the README's GCH section rejects. Both are made by sed on the concatenated copy only, and the
# number of changed lines is checked.
set -eu
here=$(cd "$(dirname "$0")/../.." && pwd)
OMC=${OMC:-$here/../omega-mv/seed/out/omc}
OUT=${OUT:-$here/../build}
CORE=${CORE:-6}
PIN=2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f
mut= kind=
if [ $# -ge 1 ]; then
  { [ "$1" = --mutant ] || [ "$1" = --variant ]; } && [ $# -eq 2 ] || { echo "usage: build.sh [--mutant a|b|c | --variant h5|h7]" >&2; exit 2; }
  kind=$1 mut=$2
fi
got=$(sha256sum "$OMC" | cut -d' ' -f1)
[ "$got" = "$PIN" ] || { echo "OMC_PIN_MISMATCH $got" >&2; exit 3; }
mkdir -p "$OUT"
src=$here/native/omegallm
name=ollm
cat "$src/math.om" "$src/data.om" "$src/model.om" "$src/adam.om" "$src/ckpt.om" "$src/cli.om" > "$OUT/ollm.om"
case "$kind$mut" in
  '') ;;
  --mutanta) pat='s/^const OMUTA ulong 1$/const OMUTA ulong 0/' want=1 ;;
  --mutantb) pat='s/^const OMUTB ulong 1$/const OMUTB ulong 2/' want=1 ;;
  --mutantc) pat='s/^const OMUTC ulong 1$/const OMUTC ulong 0/' want=1 ;;
  --varianth5) pat='s/^const GCH f64 0\.000001$/const GCH f64 0.00001/;s/^const GCH2 f64 0\.00000025$/const GCH2 f64 0.00001/' want=2 ;;
  --varianth7) pat='s/^const GCH f64 0\.000001$/const GCH f64 0.0000001/;s/^const GCH2 f64 0\.00000025$/const GCH2 f64 0.0000001/' want=2 ;;
  *) echo "usage: build.sh [--mutant a|b|c | --variant h5|h7]" >&2; exit 2 ;;
esac
if [ -n "$mut" ]; then
  [ "$kind" = --mutant ] && name=ollm-mut-$mut || name=ollm-var-$mut
  sed "$pat" "$OUT/ollm.om" > "$OUT/$name.om"
  n=$(diff "$OUT/ollm.om" "$OUT/$name.om" | grep -c '^>' || true)
  [ "$n" = "$want" ] || { echo "SED_CHANGED $n lines, want $want" >&2; exit 4; }
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
