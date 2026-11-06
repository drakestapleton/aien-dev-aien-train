#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# omegalora host glue (POSIX sh): compile native/omegalora/lora.om with the pinned seeded omc,
# run the real build and the three mutants, and record every status. All math, training and
# verdicts are in the .om unit; this script only compiles, runs and compares exit codes.
# Usage: sh tests/omegalora/run.sh   Env: OMC (pinned omc), OUT (default evidence/OMEGALORA/run).
# Host CPU only (AArch64 Linux, the omc target). No GPU, network or service is touched.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT=${OUT:-$ROOT/evidence/OMEGALORA/run}
OMC=${OMC:-$ROOT/../omega-mv/seed/out/omc}
OMC_SHA=2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f
BUILD=$(mktemp -d "${TMPDIR:-/tmp}/omegalora.XXXXXX")
mkdir -p "$OUT"
SUM="$OUT/summary.txt"
: > "$SUM"
note() { echo "$*" | tee -a "$SUM"; }
fail() { note "OMEGALORA_FAIL $*"; exit 1; }
note "source_commit=$(git -C "$ROOT" rev-parse HEAD)"
note "host=$(uname -srm)"
set -- $(sha256sum "$OMC")
[ "$1" = "$OMC_SHA" ] || fail "compiler hash $1"
note "compiler_sha256=$1"
"$OMC" < "$ROOT/native/omegalora/lora.om" > "$BUILD/lora" 2> "$OUT/compile.stderr" || fail compile
chmod +x "$BUILD/lora"
set -- $(sha256sum "$ROOT/native/omegalora/lora.om"); note "source_sha256=$1"
set -- $(sha256sum "$BUILD/lora"); note "binary_sha256=$1"
# case MUTANT EXPECTED_EXIT: 0 real build, 1 silu grad, 2 rmsnorm grad, 3 adam sign
bad=0
for c in 0:0 1:10 2:10 3:11; do
  mu=${c%%:*}; want=${c##*:}
  printf '%s' "$mu" | "$BUILD/lora" > "$OUT/mutant$mu.stdout" 2> "$OUT/mutant$mu.stderr"
  rc=$?
  echo "$rc" > "$OUT/mutant$mu.rc"
  if [ "$rc" = "$want" ]; then note "mutant$mu exit=$rc expected=$want PASS"
  else note "mutant$mu exit=$rc expected=$want FAIL"; bad=1; fi
done
(cd "$OUT" && sha256sum mutant*.rc mutant*.stdout mutant*.stderr compile.stderr) > "$OUT/raw.sha256"
rm -rf "$BUILD"
[ $bad = 0 ] || fail "exit code mismatch"
note OMEGALORA_PASS
