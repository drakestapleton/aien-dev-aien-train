#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# DRA-146 loss-mask checks on the host CPU (native/omegallm/data.om omkopen; native/personal/mpack.om).
# Usage: OLLM=path/to/ollm MPACK=path/to/mpack [OLLM_MUT=path/to/ollm-mut-z] [OLLM_MAIN=ollm built from
#        origin/main] sh tests/personal/mask-check.sh
# Data: bytes of the repository LICENSE as tokens of a V 512 model (public, fixed bytes), packed by mpack
# with a synthetic mask. Prints one PASS/FAIL line per check, then MASK_PASS, or MASK_FAIL and exit 1.
# With OLLM_MUT (build.sh --mutant z: every weight read as 1) the two zero-contribution checks are
# rerun and must FAIL there (printed as `negative control caught`).
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OLLM=${OLLM:?set OLLM to the built ollm}
MPACK=${MPACK:?set MPACK to the built mpack}
W=$(mktemp -d "${TMPDIR:-/tmp}/mask.XXXXXX")
L=$ROOT/LICENSE
bad=0
ok() { echo "PASS $*"; }
no() { echo "FAIL $*"; bad=1; }
want() { [ "$2" = "$3" ] && ok "$1: $2" || no "$1: got [$2] want [$3]"; }
echo "ollm_sha256=$(sha256sum "$OLLM" | cut -d' ' -f1)"
echo "mpack_sha256=$(sha256sum "$MPACK" | cut -d' ' -f1)"
echo "license_sha256=$(sha256sum "$L" | cut -d' ' -f1)"
# u64 little-endian offsets file
u64le() { v=$1; i=0; while [ $i -lt 8 ]; do printf "\\$(printf %o $((v % 256)))"; v=$((v / 256)); i=$((i + 1)); done; }
off2() { { u64le "$1"; u64le "$2"; } > "$3"; }
cut_() { tail -c +"$(($2 + 1))" "$L" | head -c "$3" > "$1"; }
# Stream layout (T = 64): [0,32) weight 0, [32,64) weight 1, token 64 = the variable byte (weight 0),
# [65,600) alternating 0/1 segments of 107 bytes, [600,1000) weight 0 (Z1), [1000,1400) weight 0 (Z2),
# [1400,3400) alternating 0/1 segments of 100 bytes.
cut_ "$W/a0" 0 32; cut_ "$W/a1" 32 32; printf 'x' > "$W/vx"; printf 'q' > "$W/vq"
for i in 0 1 2 3 4; do cut_ "$W/m$i" $((100 + 107 * i)) 107; done
cut_ "$W/z1" 2000 400; cut_ "$W/z2" 4000 400
for i in $(seq 0 19); do cut_ "$W/r$i" $((6000 + 100 * i)) 100; done
mklist() { # $1 variable-byte file, $2 list
  { echo "0b $W/a0"; echo "1b $W/a1"; echo "0b $1"
    for i in 0 1 2 3 4; do echo "$((i % 2))b $W/m$i"; done
    echo "0b $W/z1"; echo "0b $W/z2"
    for i in $(seq 0 19); do echo "$((i % 2))b $W/r$i"; done; } > "$2"; }
mklist "$W/vx" "$W/lx"; mklist "$W/vq" "$W/lq"
want "mpack" "$("$MPACK" "$W/lx" "$W/x.tok" "$W/x.mask")" "MP 3400 1246 2154 30"
"$MPACK" "$W/lq" "$W/q.tok" "$W/q.mask" > /dev/null
cmp -s "$W/x.mask" "$W/q.mask"; want "the two streams have the same mask" $? 0
want "the two streams differ in exactly one token" "$(cmp -l "$W/x.tok" "$W/q.tok" | wc -l | tr -d ' ')" 1
head -c 3400 /dev/zero | tr '\000' '\001' > "$W/ones.mask"
head -c 3400 /dev/zero > "$W/zero.mask"
cp "$W/x.mask" "$W/two.mask"; printf '\002' | dd of="$W/two.mask" bs=1 seek=620 conv=notrunc 2> /dev/null
head -c 3399 "$W/x.mask" > "$W/short.mask"
off2 0 610 "$W/o1"; off2 0 1010 "$W/o2"; off2 610 1010 "$W/oz"
checks() { # $1 binary, $2 label; prints the two zero-contribution verdicts as words
  B=$1
  "$B" init "$W/c.ck" 512 64 64 2 128 2 2 7 40 1000 > /dev/null
  "$B" grad "$W/c.ck" "$W/x.tok" "$W/o1" "$W/g1x" "$W/x.mask" > "$W/l1x"
  "$B" grad "$W/c.ck" "$W/q.tok" "$W/o1" "$W/g1q" "$W/q.mask" > "$W/l1q"
  cmp -s "$W/g1x" "$W/g1q" && cmp -s "$W/l1x" "$W/l1q" && echo same || echo differ
  "$B" grad "$W/c.ck" "$W/x.tok" "$W/o2" "$W/g2x" "$W/x.mask" > "$W/l2x"
  cmp -s "$W/g1x" "$W/g2x" && cmp -s "$W/l1x" "$W/l2x" && echo same || echo differ
}
"$OLLM" init "$W/c.ck" 512 64 64 2 128 2 2 7 40 1000 > "$W/i.txt"; want init "$(cut -d' ' -f1 "$W/i.txt")" I
set -- $(checks "$OLLM" product)
want "masked final target: changing token 64 (weight 0, last target of window 0) leaves gradient and loss bit-identical" "$1" same
want "fully masked window: replacing window 1 (offset 610, all 64 targets weight 0) by another (offset 1010) leaves gradient and loss bit-identical" "$2" same
"$OLLM" grad "$W/c.ck" "$W/x.tok" "$W/o1" "$W/gn" > "$W/ln"; "$OLLM" grad "$W/c.ck" "$W/q.tok" "$W/o1" "$W/gnq" > /dev/null
cmp -s "$W/gn" "$W/gnq"; [ $? -ne 0 ] && ok "control: without the mask the same token change moves the gradient" || no "control: unmasked gradient did not move"
"$OLLM" grad "$W/c.ck" "$W/x.tok" "$W/o1" "$W/go" "$W/ones.mask" > "$W/lo"
cmp -s "$W/gn" "$W/go"; want "all-ones mask: gradient bit-identical to no mask (scale 1/sum(w) = 1/(T B))" $? 0
lo=$(cut -d' ' -f3 "$W/lo"); lnm=$(cut -d' ' -f3 "$W/ln"); d=$((lo - lnm)); [ ${d#-} -le 1 ] && ok "all-ones mask: loss within 1 micro-nat of no mask ($lo vs $lnm)" || no "all-ones loss $lo vs $lnm"
cmp -s "$W/g1x" "$W/gn"; [ $? -ne 0 ] && ok "control: the partial mask changes the gradient" || no "partial mask changed nothing"
"$OLLM" grad "$W/c.ck" "$W/x.tok" "$W/oz" "$W/gz" "$W/zero.mask" > /dev/null 2>&1; want "all-zero batch refused" $? 83
[ -e "$W/gz" ] && no "refused grad wrote a gradient" || ok "refused grad wrote no gradient"
"$OLLM" grad "$W/c.ck" "$W/x.tok" "$W/o1" "$W/gb" "$W/two.mask" > /dev/null 2>&1; want "mask byte 2 in a read window refused" $? 82
"$OLLM" grad "$W/c.ck" "$W/x.tok" "$W/o1" "$W/gb" "$W/short.mask" > /dev/null 2>&1; want "mask length != token count refused" $? 82
# masked training on a stream of 40 alternating 0/1 segments of 50 bytes (every 64-token window holds
# weight-1 targets, so no batch is all zero): deterministic resume, loss falls, refusals
for i in $(seq 0 39); do cut_ "$W/s$i" $((9000 + 50 * i)) 50; echo "$((i % 2))b $W/s$i"; done > "$W/lt"
want "mpack training stream" "$("$MPACK" "$W/lt" "$W/t.tok" "$W/t.mask")" "MP 2000 1000 1000 40"
cp "$W/c.ck" "$W/t1.ck"; cp "$W/c.ck" "$W/t2.ck"
"$OLLM" train "$W/t1.ck" "$W/t.tok" 40 20 1 "$W/t.mask" > "$W/t1.txt"; want "masked train 0..40 rc" $? 0
want "masked train saves" "$(cut -d' ' -f1-2 "$W/t1.txt" | tr '\n' ,)" "T 20,T 40,"
"$OLLM" train "$W/t2.ck" "$W/t.tok" 20 20 1 "$W/t.mask" > /dev/null; "$OLLM" train "$W/t2.ck" "$W/t.tok" 40 20 1 "$W/t.mask" > /dev/null
cmp -s "$W/t1.ck" "$W/t2.ck"; want "masked train resume 0..20..40 bit-identical to 0..40" $? 0
off2 300 1500 "$W/oe"
"$OLLM" grad "$W/c.ck" "$W/t.tok" "$W/oe" "$W/ge0" "$W/t.mask" > "$W/le0"; "$OLLM" grad "$W/t1.ck" "$W/t.tok" "$W/oe" "$W/ge1" "$W/t.mask" > "$W/le1"
a=$(cut -d' ' -f3 "$W/le0"); b=$(cut -d' ' -f3 "$W/le1"); [ "$b" -lt "$a" ] && ok "masked train lowered the masked loss at fixed offsets (micro-nats $a to $b)" || no "masked loss $a to $b"
"$OLLM" train "$W/t1.ck" "$W/t.tok" 40 20 1 "$W/t.mask" extra > /dev/null 2>&1; want "train argument count 9 refused" $? 2
# unmasked training unchanged against an origin/main build
if [ -n "${OLLM_MAIN:-}" ]; then
  cp "$W/c.ck" "$W/u1.ck"; cp "$W/c.ck" "$W/u2.ck"
  "$OLLM" train "$W/u1.ck" "$W/x.tok" 20 20 > /dev/null; "$OLLM_MAIN" train "$W/u2.ck" "$W/x.tok" 20 20 > /dev/null
  cmp -s "$W/u1.ck" "$W/u2.ck"; want "no mask: train 0..20 checkpoint bit-identical to the origin/main build ($(sha256sum "$OLLM_MAIN" | cut -c1-12))" $? 0
  "$OLLM_MAIN" grad "$W/c.ck" "$W/x.tok" "$W/o1" "$W/gm" > "$W/lm"
  cmp -s "$W/gm" "$W/gn" && cmp -s "$W/lm" "$W/ln"; want "no mask: grad and loss bit-identical to the origin/main build" $? 0
else
  echo "SKIP no-mask equivalence to origin/main (OLLM_MAIN unset)"
fi
if [ -n "${OLLM_MUT:-}" ]; then
  echo "mutant_sha256=$(sha256sum "$OLLM_MUT" | cut -d' ' -f1)"
  set -- $(checks "$OLLM_MUT" mutant)
  [ "$1" = differ ] && ok "negative control caught: mask ignored, the weight-0 final target moves the gradient" || no "negative control not caught (final target)"
  [ "$2" = differ ] && ok "negative control caught: mask ignored, the fully masked window contributes" || no "negative control not caught (masked window)"
fi
rm -rf "$W"
[ $bad = 0 ] && echo MASK_PASS || { echo MASK_FAIL; exit 1; }
