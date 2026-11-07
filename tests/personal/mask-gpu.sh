#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# DRA-146 loss mask on the GB10 (gpu/gr.om grce per-row scale, gpu/gg.om ggupsc), run INSIDE a spark-window
# lease (exclusive). Usage:
#   GB=path/to/ollm-gb10 GBJ=path/to/ollm-mut-j-gb10 GBMAIN=ollm-gb10 built from origin/main MPACK=path/to/mpack \
#   [BASE=checkpoint of the rung-10 shape] [TS=public TinyStories train.tok] sh tests/personal/mask-gpu.sh
# Tiny shape V 512 T 64 D 64 H 2 F 128 L 2 B 4 on LICENSE bytes (as tests/personal/mask-check.sh), then, with
# BASE and TS, a 20-step masked gtrainb of a `tune` copy of BASE at the full shape on public TinyStories tokens
# with a synthetic mask. BASE itself is only read. Prints PASS/FAIL lines and MASKGPU_PASS or MASKGPU_FAIL.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
GB=${GB:?}; GBJ=${GBJ:?}; GBMAIN=${GBMAIN:?}; MPACK=${MPACK:?}
W=$(mktemp -d "${WORK:-${TMPDIR:-/tmp}}/maskgpu.XXXXXX")
L=$ROOT/LICENSE
bad=0
ok() { echo "PASS $*"; }
no() { echo "FAIL $*"; bad=1; }
want() { [ "$2" = "$3" ] && ok "$1: $2" || no "$1: got [$2] want [$3]"; }
for b in "$GB" "$GBJ" "$GBMAIN" "$MPACK"; do echo "sha256 $(sha256sum "$b" | cut -d' ' -f1) $(basename "$b")"; done
cut_() { tail -c +"$(($2 + 1))" "$L" | head -c "$3" > "$1"; }
for i in $(seq 0 79); do cut_ "$W/s$i" $((9000 + 50 * i)) 50; echo "$((i % 2))b $W/s$i"; done > "$W/lt"
want "mpack" "$("$MPACK" "$W/lt" "$W/t.tok" "$W/t.mask")" "MP 4000 2000 2000 80"
"$GB" init "$W/c.ck" 512 64 64 2 128 2 4 7 40 1000 > /dev/null; want "init rc" $? 0
for s in 0 1 2; do
  "$GB" gcmp "$W/c.ck" "$W/t.tok" $s "$W/t.mask" > "$W/gc$s.txt" 2>&1; r=$?
  want "gcmp masked S=$s (CPU f64 mask vs chip mask): $(grep '^GC ' "$W/gc$s.txt")" "$r $(tail -n 1 "$W/gc$s.txt")" "0 GCMP PASS"
done
"$GBJ" gcmp "$W/c.ck" "$W/t.tok" 0 "$W/t.mask" > "$W/gj.txt" 2>&1; r=$?
[ $r -ne 0 ] && ok "negative control caught: mutant j (chip ignores the mask) gcmp rc $r: $(grep '^GC ' "$W/gj.txt")" || no "mutant j not caught: $(cat "$W/gj.txt")"
"$GB" gcmp "$W/c.ck" "$W/t.tok" 0 > "$W/gn.txt" 2>&1; r1=$?
"$GBMAIN" gcmp "$W/c.ck" "$W/t.tok" 0 > "$W/gm.txt" 2>&1; r2=$?
want "gcmp no mask, this build and origin/main (rc)" "$r1 $r2" "0 0"
want "gcmp no mask: GC numbers equal to origin/main (fields 2-7)" "$(grep '^GC ' "$W/gn.txt" | cut -d' ' -f2-7)" "$(grep '^GC ' "$W/gm.txt" | cut -d' ' -f2-7)"
cp "$W/c.ck" "$W/u1.ck"; cp "$W/c.ck" "$W/u2.ck"; cp "$W/c.ck" "$W/u3.ck"
"$GB" gtrainb "$W/u1.ck" "$W/t.tok" 20 10 > "$W/u1.txt"; "$GBMAIN" gtrainb "$W/u2.ck" "$W/t.tok" 20 10 > "$W/u2.txt"
cmp -s "$W/u1.ck" "$W/u2.ck"; r=$?
if [ $r -eq 0 ]; then ok "gtrainb no mask 0..20: checkpoint bit-identical to the origin/main build"
else
  "$GBMAIN" gtrainb "$W/u3.ck" "$W/t.tok" 20 10 > /dev/null; cmp -s "$W/u2.ck" "$W/u3.ck"
  [ $? -eq 0 ] && no "gtrainb no mask differs from origin/main while main is deterministic" || echo "INFO gtrainb not deterministic run to run; compare T lines: $(cut -d' ' -f1-3 "$W/u1.txt" | tr '\n' ,) vs $(cut -d' ' -f1-3 "$W/u2.txt" | tr '\n' ,)"
fi
cp "$W/c.ck" "$W/m1.ck"
"$GB" gtrainb "$W/m1.ck" "$W/t.tok" 40 20 "$W/t.mask" > "$W/m1.txt" 2>&1; r=$?
want "gtrainb masked 0..40 rc" $r 0
[ $r -eq 0 ] || sed 's/^/  out: /' "$W/m1.txt"
want "gtrainb masked saves" "$(grep '^T ' "$W/m1.txt" | cut -d' ' -f1-2 | tr '\n' ,)" "T 20,T 40,"
u64le() { v=$1; i=0; while [ $i -lt 8 ]; do printf "\\$(printf %o $((v % 256)))"; v=$((v / 256)); i=$((i + 1)); done; }
{ u64le 300; u64le 1500; u64le 2500; u64le 3500; } > "$W/oe"
"$GB" grad "$W/c.ck" "$W/t.tok" "$W/oe" "$W/g0" "$W/t.mask" > "$W/l0"; "$GB" grad "$W/m1.ck" "$W/t.tok" "$W/oe" "$W/g1" "$W/t.mask" > "$W/l1"
a=$(cut -d' ' -f3 "$W/l0"); b=$(cut -d' ' -f3 "$W/l1")
[ "$b" -lt "$a" ] && ok "chip masked training lowered the CPU masked loss at fixed offsets (micro-nats $a to $b)" || no "masked loss $a to $b"
if [ -n "${BASE:-}" ] && [ -n "${TS:-}" ]; then
  bs=$(sha256sum "$BASE" | cut -d' ' -f1); echo "base_sha256 $bs"
  head -c 2097152 "$TS" > "$W/ts.tok"
  { head -c 100 /dev/zero; head -c 156 /dev/zero | tr '\000' '\001'; } > "$W/p256"
  i=0; : > "$W/ts.mask"; while [ $i -lt 4096 ]; do cat "$W/p256"; i=$((i + 1)); done > "$W/ts.mask"
  want "full-shape smoke mask bytes = tokens" "$(wc -c < "$W/ts.mask" | tr -d ' ')" 1048576
  "$GB" tune "$BASE" "$W/f.ck" 20 300 > "$W/f.txt"; want "tune BASE (fresh optimizer, 20 steps, lr 300e-6)" "$(cut -d' ' -f1 "$W/f.txt")" U
  t0=$(date +%s%N)
  "$GB" gtrainb "$W/f.ck" "$W/ts.tok" 20 10 "$W/ts.mask" > "$W/f1.txt"; r=$?
  t1=$(date +%s%N)
  want "full-shape masked gtrainb 0..20 rc ($(grep '^T ' "$W/f1.txt" | tr '\n' ,) wall_ns $((t1 - t0)))" $r 0
  want "BASE unchanged" "$(sha256sum "$BASE" | cut -d' ' -f1)" "$bs"
fi
rm -rf "$W"
[ $bad = 0 ] && echo MASKGPU_PASS || { echo MASKGPU_FAIL; exit 1; }
