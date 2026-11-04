#!/bin/sh
# Build ollm (aien-train#52) from native/omegallm/*.om with the pinned seeded omc.
# Usage: sh tests/omegallm/build.sh [--mutant a|b|c | --variant h5|h7]
# Env: TARGET (aarch64, the default, x86linux or x86efi), OMC (default ../omega-mv/seed/out/omc
#      beside this clone for aarch64, ../omega-mv-x86/seed/out/omc for x86linux,
#      ../omega-efi-ident/seed/out/omc for x86efi), OUT (default ../build beside it), CORE (taskset core,
#      default 6).
# Each target has its own pinned omc: aarch64 is omega-mv e5b32567 (the v0 pin); x86linux is
# omega-mv main ba5559d9, whose omc has the x86-64 Linux backend with SSE2 floats (docs/X86-LINUX.md);
# x86efi is omega-mv PR #1022 commit ab572d8f2840a284f1230347c1a7d1406b33733e (branch feat/x86efi-ident:
# omega-mv main d3d1b1bc, where PR #1015's x86efi backend merged on 2026-11-04, plus efi 14, docs/X86-EFI.md),
# whose omc adds the UEFI x86-64 backend with efi 12 (files), efi 13 (console) and efi 14 (identity).
# The receipts in evidence/OMEGALLM/efi and imac were built with omc b4f45121 from #1015's commit
# 5ce9ecaa, an ancestor of d3d1b1bc (evidence/OMEGALLM/efi/repin-d3d1b1bc.txt).
# For x86linux and x86efi the concatenated source starts with the opt-in line `target x86linux` or
# `target x86efi`; every later line is the same as the aarch64 source except the platform unit, which
# is lio.om on Linux and eio.om on UEFI (CONTRACT §9). The x86efi output is ollm.efi, a PE32+ EFI
# application.
# Mutants (ollm-mut-X, one changed line) plant a defect the checks must catch. Variants (ollm-var-X,
# two changed lines) set both gcheck steps GCH and GCH2 to 1e-5 (h5) or 1e-7 (h7), the step sizes
# that the README's GCH section rejects. Both are made by sed on the concatenated copy only, and the
# number of changed lines is checked.
set -eu
here=$(cd "$(dirname "$0")/../.." && pwd)
TARGET=${TARGET:-aarch64}
case "$TARGET" in
  aarch64) PIN=2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f
           OMC=${OMC:-$here/../omega-mv/seed/out/omc} lead= plat=lio.om ext= ;;
  x86linux) PIN=be8c51301307555254fc59e351d281aae1aa096d91521777e33a41c8b446448a
            OMC=${OMC:-$here/../omega-mv-x86/seed/out/omc} lead='target x86linux' plat=lio.om ext= ;;
  x86efi) PIN=3ad9f10f64309e7acf8a725082b28e23a2a4aeb07e98322fb4dc0fcd8fc93194
          OMC=${OMC:-$here/../omega-efi-ident/seed/out/omc} lead='target x86efi' plat=eio.om ext=.efi ;;
  *) echo "TARGET must be aarch64, x86linux or x86efi" >&2; exit 2 ;;
esac
OUT=${OUT:-$here/../build}
CORE=${CORE:-6}
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
{
  [ -z "$lead" ] || printf '%s\n' "$lead"
  cat "$src/math.om" "$src/data.om" "$src/model.om" "$src/adam.om" "$src/ckpt.om" "$src/cli.om" "$src/$plat"
} > "$OUT/ollm.om"
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
mv "$OUT/$name.tmp" "$OUT/$name$ext"
echo "BUILD_OK $(sha256sum "$OUT/$name$ext" | cut -d' ' -f1) $OUT/$name$ext source_sha256 $(sha256sum "$OUT/$name.om" | cut -d' ' -f1)"
