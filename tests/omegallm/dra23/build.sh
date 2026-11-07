#!/bin/sh
# build.sh: compose and compile dra23live, the DRA-23 live identity probe, with the pinned seeded omc.
# Usage: sh tests/omegallm/dra23/build.sh [--mutant m1|m2|m3]
# Env: OMC (default ../omega-mv/seed/out/omc beside this clone, omega-mv e5b32567, the aarch64 pin
#      tests/omegallm/build.sh uses), OUT (default ../build/dra23 beside this clone).
# Source = sha256-om2.om, vendored unmodified from omega-mv e5b32567 om/sha256/sha256-om2.om
# (git blob 748c8711d2358a94429ed63fdf9ecc7f844163df, sha256 pinned below), followed by live.om.
# The four `export fn` lines of the vendored unit become `fn` in the composed copy only (program
# mode refuses `export`, error 9); the number of changed lines is checked.
# Mutants (one changed line each, checked) plant defects that check.sh must catch:
#   m1 hexeq never sees a differing digit (an exe/file sha256 mismatch would pass)
#   m2 gclass never reports nvrm (raw NVIDIA RM device nodes would be invisible)
#   m3 lbso never matches (a mapped shared object would pass)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../.." && pwd)
OMC=${OMC:-$root/../omega-mv/seed/out/omc}
OUT=${OUT:-$root/../build/dra23}
PIN=2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f
SHAPIN=dbf002dd6aa36585632b9d01d98ac3f0bd2fa0f0475082940de53638847994bb
got=$(sha256sum "$OMC" | cut -d' ' -f1)
[ "$got" = "$PIN" ] || { echo "OMC_PIN_MISMATCH $got" >&2; exit 3; }
sha=$here/sha256-om2.om
got=$(sha256sum "$sha" | cut -d' ' -f1)
[ "$got" = "$SHAPIN" ] || { echo "SHA_UNIT_PIN_MISMATCH $got" >&2; exit 3; }
mkdir -p "$OUT"
name=dra23live
sed 's/^export fn /fn /' "$sha" > "$OUT/sha.fn.om"
n=$(diff "$sha" "$OUT/sha.fn.om" | grep -c '^>' || true)
[ "$n" = 4 ] || { echo "EXPORT_EDIT $n lines, want 4" >&2; exit 4; }
cat "$OUT/sha.fn.om" "$here/live.om" > "$OUT/$name.om"
rm -f "$OUT/sha.fn.om"
if [ $# -ge 1 ]; then
  [ "$1" = --mutant ] && [ $# -eq 2 ] || { echo "usage: build.sh [--mutant m1|m2|m3]" >&2; exit 2; }
  case $2 in
    m1) pat='s/^if ne get hx j get ex j$/if eq ulong 1 ulong 0/' ;;
    m2) pat='s/^if lbpre tdnv$/if eq ulong 1 ulong 0/' ;;
    m3) pat='s/^if eq get lb add j 2 111$/if eq ulong 1 ulong 0/' ;;
    *) echo "usage: build.sh [--mutant m1|m2|m3]" >&2; exit 2 ;;
  esac
  sed "$pat" "$OUT/$name.om" > "$OUT/$name-$2.om"
  n=$(diff "$OUT/$name.om" "$OUT/$name-$2.om" | grep -c '^>' || true)
  [ "$n" = 1 ] || { echo "SED_CHANGED $n lines, want 1" >&2; exit 4; }
  name=$name-$2
fi
set +e
"$OMC" < "$OUT/$name.om" > "$OUT/$name.tmp"
rc=$?
set -e
if [ $rc -ne 0 ]; then rm -f "$OUT/$name.tmp"; echo "BUILD_FAIL omc rc=$rc" >&2; exit 1; fi
chmod +x "$OUT/$name.tmp"
mv "$OUT/$name.tmp" "$OUT/$name"
echo "BUILD_OK $(sha256sum "$OUT/$name" | cut -d' ' -f1) $OUT/$name source_sha256 $(sha256sum "$OUT/$name.om" | cut -d' ' -f1)"
