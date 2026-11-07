#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Checks for `ollm tune4 CK OUT TOTAL LRMICRO [T B G]` (native/omegallm/v4.om xctune and xtunes;
# docs/omegallm/CONTRACT-V4.md sections 3 and 4). Host CPU only.
# Usage: [BIN=path/to/ollm] [OMC=path/to/pinned/omc] [CORES=6] [OUT=dir] [BASE_REV=cfec44b^]
#        sh tests/omegallm/tune4-check.sh
# Without BIN the script builds ollm with tests/omegallm/build.sh (OMC, OUT, CORE=$CORES). It also
# builds the pre-[T B G] tune4 (git revision BASE_REV, the parent of cfec44b) from `git archive`, and a
# source mutant of BIN.om (xtunes stores G as B), both with OMC.
# CK03 layout (CONTRACT-V4 section 4, v4.om xhdr): 128-byte header of u64 LE at byte offsets
#   0 magic, 8 V, 16 T, 24 D, 32 H, 40 F, 48 L, 56 B, 64 seed, 72 step, 80 TOTAL, 88 lr bits, 96 P,
#   104 G, 112 rope base bits, 120 FNV-1a 64 of the payload; payload 24 P bytes: params (8 P), m, v.
# Data: the first 16384 bytes of the repository LICENSE read as 8192 u16 LE tokens (ASCII bytes, so
# every token is < 32768 = V): fixed, public, deterministic.
# Expected lr bits: f64(LRMICRO / 10^6) for 1000, 500 and 250 (Wolfram ExportByteArray Real64:
# 3f50624dd2f1a9fc, 3f40624dd2f1a9fc, 3f30624dd2f1a9fc).
# Self-controls: a copy of a tuned CK with one flipped param byte and one with one nonzero Adam byte
# must fail the same byte-range comparisons; the mutant must fail the B field check.
# Prints one line per assertion, then TUNE4_CHECK PASS n=N (exit 0) or TUNE4_CHECK FAIL ... (exit 1).
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
CORES=${CORES:-6}
OMC=${OMC:-$ROOT/../omega-mv/seed/out/omc}
BASE_REV=${BASE_REV:-cfec44b^}
W=$(mktemp -d "${TMPDIR:-/tmp}/tune4.XXXXXX")
OUT=${OUT:-$W/b}
n=0 nf=0 fl=
ok() { n=$((n + 1)); echo "PASS $*"; }
no() { n=$((n + 1)); nf=$((nf + 1)); fl="$fl;$1"; echo "FAIL $*"; }
want() { [ "$2" = "$3" ] && ok "$1: $2" || no "$1: got [$2] want [$3]"; }
R=
command -v taskset > /dev/null 2>&1 && R="taskset -c $CORES"
if [ -z "${BIN:-}" ]; then
  OMC=$OMC OUT=$OUT CORE=$CORES sh "$ROOT/tests/omegallm/build.sh" > "$W/build.txt" 2>&1
  want "build ollm rc" $? 0
  BIN=$OUT/ollm
fi
[ -x "$BIN" ] || { echo "TUNE4_CHECK FAIL no binary $BIN"; rm -rf "$W"; exit 1; }
echo "ollm_sha256=$(sha256sum "$BIN" | cut -d" " -f1)"
echo "omc_sha256=$(sha256sum "$OMC" | cut -d" " -f1)"
O() { $R "$BIN" "$@"; }
u8() { od -An -tu8 -j "$2" -N8 "$1" | tr -d " "; }
x8() { od -An -tx8 -j "$2" -N8 "$1" | tr -d " "; }
# same NAME A B OFF LEN: bytes OFF .. OFF+LEN-1 of A and B equal
same() { cmp -s -i "$4:$4" -n "$5" "$2" "$3"; want "$1" $? 0; }
# zero NAME F OFF LEN: bytes OFF .. OFF+LEN-1 of F are all zero
zero() { cmp -s -i "$3:0" -n "$4" "$2" /dev/zero; want "$1" $? 0; }
D=$W/tok.u16
head -c 16384 "$ROOT/LICENSE" > "$D"
echo "data_sha256=$(sha256sum "$D" | cut -d" " -f1)"
# Input: V 32768 T 256 D 32 H 2 F 64 L 2 B 4 seed 7 TOTAL 100 lr 1000 G 2, one train4 step (m, v nonzero)
A=$W/a.ck
want "init4 V32768 T256 D32 H2 F64 L2 B4 G2" "$(O init4 "$A" 32768 256 32 2 64 2 4 7 100 1000 2)" "I 1065120"
O train4 "$A" "$D" 1 1 > "$W/t.txt"; want "train4 1 step rc" $? 0
P=$(u8 "$A" 96); want "input P" "$P" 1065120
want "input step" "$(u8 "$A" 72)" 1
want "input size 128 + 24 P" "$(wc -c < "$A" | tr -d " ")" $((128 + 24 * P))
cmp -s -i $((128 + 8 * P)):0 -n $((16 * P)) "$A" /dev/zero
[ $? -ne 0 ] && ok "control: input Adam m, v nonzero" || no "control: input Adam m, v all zero"
E0=$(O eval4 "$A" "$D" 2); want "eval4 input rc" $? 0
echo "eval4 input: $E0"
# fields of a tuned CK U from A: everything but T B G, step, TOTAL, lr and FNV equals A's; params equal;
# m and v zero; T B G TOTAL lr as given
tuned() { # tuned NAME U T B G TOTAL LRHEX
  want "$1 magic" "$(x8 "$2" 0)" "$(x8 "$A" 0)"
  same "$1 V header bytes 8..15" "$A" "$2" 8 8
  same "$1 D H F L header bytes 24..55" "$A" "$2" 24 32
  same "$1 seed header bytes 64..71" "$A" "$2" 64 8
  same "$1 P header bytes 96..103" "$A" "$2" 96 8
  same "$1 rope base header bytes 112..119" "$A" "$2" 112 8
  want "$1 T" "$(u8 "$2" 16)" "$3"
  want "$1 B" "$(u8 "$2" 56)" "$4"
  want "$1 G" "$(u8 "$2" 104)" "$5"
  want "$1 step" "$(u8 "$2" 72)" 0
  want "$1 TOTAL" "$(u8 "$2" 80)" "$6"
  want "$1 lr bits" "$(x8 "$2" 88)" "$7"
  want "$1 size 128 + 24 P" "$(wc -c < "$2" | tr -d " ")" $((128 + 24 * P))
  same "$1 params bytes 128 .. 128+8P-1" "$A" "$2" 128 $((8 * P))
  zero "$1 Adam m, v bytes 128+8P .. 128+24P-1 zero" "$2" $((128 + 8 * P)) $((16 * P))
}
# 1. new context, batch and blocks: T 512 B 8 G 4
U1=$W/u1.ck
want "tune4 T512 B8 G4" "$(O tune4 "$A" "$U1" 40 500 512 8 4)" "U $P"
tuned "T512 B8 G4" "$U1" 512 8 4 40 3f40624dd2f1a9fc
E1=$(O eval4 "$U1" "$D" 2); want "eval4 at T 512 rc" $? 0
want "eval4 at T 512 step and W" "$(echo "$E1" | cut -d" " -f1-3)" "E 0 2"
# self-control: one flipped param byte and one nonzero m byte must fail the same comparisons
cp "$U1" "$W/c.ck"
o=$((128 + 4 * P + 3))
b=$(od -An -tu1 -j $o -N1 "$W/c.ck" | tr -d " ")
printf "\\$(printf %o $(((b + 1) % 256)))" | dd of="$W/c.ck" bs=1 seek=$o conv=notrunc 2> /dev/null
cmp -s -i 128:128 -n $((8 * P)) "$A" "$W/c.ck"
[ $? -ne 0 ] && ok "self-control: flipped param byte $o caught by the params cmp" || no "self-control: flipped param byte not caught"
cp "$U1" "$W/c.ck"
printf "\\001" | dd of="$W/c.ck" bs=1 seek=$((128 + 16 * P + 5)) conv=notrunc 2> /dev/null
cmp -s -i $((128 + 8 * P)):0 -n $((16 * P)) "$W/c.ck" /dev/zero
[ $? -ne 0 ] && ok "self-control: nonzero Adam v byte caught by the zero cmp" || no "self-control: nonzero Adam byte not caught"
O tune4 "$W/c.ck" "$W/x.ck" 10 500 > /dev/null 2>&1; want "self-control: corrupted CK refused on load (FNV)" $? 14
rm -f "$W/c.ck" "$W/x.ck"
# the tuned CK trains at its new shape
O train4 "$U1" "$D" 1 1 > "$W/t1.txt"; want "train4 on T512 B8 G4 rc" $? 0
want "train4 on T512 B8 G4 step, T B G kept" "$(u8 "$U1" 72) $(u8 "$U1" 16) $(u8 "$U1" 56) $(u8 "$U1" 104)" "1 512 8 4"
rm -f "$U1"
# 2. T unchanged, B and G changed: eval4 token mode gives the same W, loss and bits per token
U2=$W/u2.ck
want "tune4 T256 B8 G8" "$(O tune4 "$A" "$U2" 30 250 256 8 8)" "U $P"
tuned "T256 B8 G8" "$U2" 256 8 8 30 3f30624dd2f1a9fc
E2=$(O eval4 "$U2" "$D" 2); want "eval4 T unchanged rc" $? 0
want "eval4 T unchanged: W loss bpt equal to input" "$(echo "$E2" | cut -d" " -f3-)" "$(echo "$E0" | cut -d" " -f3-)"
want "eval4 T unchanged: step field 0 (input 1)" "$(echo "$E2" | cut -d" " -f2)" 0
rm -f "$U2"
# 3. without T B G: T B G kept; byte-identical to the pre-cfec44b tune4
U3=$W/u3.ck
want "tune4 6 args" "$(O tune4 "$A" "$U3" 20 500)" "U $P"
tuned "6 args" "$U3" 256 4 2 20 3f40624dd2f1a9fc
E3=$(O eval4 "$U3" "$D" 2)
want "eval4 6 args: W loss bpt equal to input" "$(echo "$E3" | cut -d" " -f3-)" "$(echo "$E0" | cut -d" " -f3-)"
mkdir -p "$W/old"
git -C "$ROOT" archive "$BASE_REV" native tests/omegallm/build.sh | tar -x -C "$W/old"
OMC=$OMC OUT=$W/old/b CORE=$CORES sh "$W/old/tests/omegallm/build.sh" > "$W/old.txt" 2>&1
want "build tune4 at $BASE_REV rc" $? 0
echo "old_ollm_sha256=$(sha256sum "$W/old/b/ollm" | cut -d" " -f1) rev=$(git -C "$ROOT" rev-parse "$BASE_REV")"
want "old tune4 6 args" "$($R "$W/old/b/ollm" tune4 "$A" "$W/o.ck" 20 500)" "U $P"
cmp -s "$U3" "$W/o.ck"; want "6 args byte-identical to the $BASE_REV tune4" $? 0
$R "$W/old/b/ollm" tune4 "$A" "$W/x.ck" 20 500 512 8 4 > /dev/null 2>&1; want "control: $BASE_REV tune4 refuses T B G" $? 2
rm -rf "$W/old" "$W/o.ck" "$W/x.ck" "$U3"
# 4. range boundaries accepted; the outputs load again (tune4 reloads them through xload)
for c in "2 1 1" "16384 4096 4096" "16384 4096 1"; do
  set -- $c
  want "tune4 T$1 B$2 G$3 accepted" "$(O tune4 "$A" "$W/e.ck" 10 500 $1 $2 $3)" "U $P"
  want "T$1 B$2 G$3 header" "$(u8 "$W/e.ck" 16) $(u8 "$W/e.ck" 56) $(u8 "$W/e.ck" 104)" "$1 $2 $3"
  want "T$1 B$2 G$3 output loads again" "$(O tune4 "$W/e.ck" "$W/f.ck" 10 500)" "U $P"
  rm -f "$W/e.ck" "$W/f.ck"
done
# 5. refused T B G: exit 12, no output file
for c in "1 4 2" "16385 4 2" "0 4 2" "256 0 1" "256 4097 1" "256 4 0" "256 4 8" "256 6 4" "256 8 3"; do
  set -- $c
  O tune4 "$A" "$W/r.ck" 20 500 $1 $2 $3 > /dev/null 2>&1; want "tune4 T$1 B$2 G$3 refused" $? 12
  [ -e "$W/r.ck" ] && no "tune4 T$1 B$2 G$3 left an output file" || ok "tune4 T$1 B$2 G$3 wrote no output"
  rm -f "$W/r.ck"
done
O tune4 "$A" "$W/r.ck" 20 500 512 > /dev/null 2>&1; want "tune4 7 args refused" $? 2
O tune4 "$A" "$W/r.ck" 20 500 512 8 > /dev/null 2>&1; want "tune4 8 args refused" $? 2
O tune4 "$A" "$W/r.ck" 0 500 512 8 4 > /dev/null 2>&1; want "tune4 TOTAL 0 with T B G refused" $? 12
[ -e "$W/r.ck" ] && no "refused tune4 left an output file" || ok "refused tune4 (args, TOTAL) wrote no output"
# 5b. a T in 2..16384 whose layout does not fit (CONTRACT-V4 section 2.1; here the decode layout
# 8D + 2F + 4 + V + T + 2TD > OAC at V 256 D 512 T 16384) is refused like init4 refuses it, rather
# than written as a checkpoint that no command can load
G=$W/g.ck
want "init4 V256 T256 D512 H8 F64 L1" "$(O init4 "$G" 256 256 512 8 64 1 4 7 100 1000 2)" "I 1246720"
O init4 "$W/r.ck" 256 16384 512 8 64 1 4 7 100 1000 2 > /dev/null 2>&1; want "control: init4 at T 16384 of that shape refused" $? 12
rm -f "$W/r.ck"
O tune4 "$G" "$W/r.ck" 10 500 16384 4 2 > /dev/null 2>&1; want "tune4 to T 16384 of that shape refused" $? 12
[ -e "$W/r.ck" ] && no "tune4 to a non-fitting T left an output file (load: rc $(O tune4 "$W/r.ck" "$W/x.ck" 10 500 > /dev/null 2>&1; echo $?))" || ok "tune4 to a non-fitting T wrote no output"
want "tune4 T 8192 of that shape accepted" "$(O tune4 "$G" "$W/r.ck" 10 500 8192 4 2)" "U 1246720"
want "T 8192 output loads again" "$(O tune4 "$W/r.ck" "$W/x.ck" 10 500)" "U 1246720"
rm -f "$G" "$W/r.ck" "$W/x.ck"
# 6. v3 checkpoints (OLLMCK01 from init, OLLMCK02 from init with G): 9 arguments exit 2; 6 run v3 tune
V3=$W/v3.ck
for c in "OLLMCK01" "OLLMCK02 2"; do
  set -- $c
  want "init v3 $1" "$(O init "$V3" 256 64 64 4 256 2 16 1 30 1000 ${2:-})" "I 119104"
  want "v3 magic" "$(head -c 8 "$V3")" "$1"
  O tune4 "$V3" "$W/r.ck" 20 500 128 8 4 > /dev/null 2>&1; want "$1 CK with T B G refused" $? 2
  [ -e "$W/r.ck" ] && no "$1 refused tune4 left an output file" || ok "$1 refused tune4 wrote no output"
  want "$1 CK 6 args (v3 tune)" "$(O tune4 "$V3" "$W/v3u.ck" 20 500)" "U 119104"
  want "$1 tune output magic" "$(head -c 8 "$W/v3u.ck")" "$1"
  rm -f "$V3" "$W/v3u.ck" "$W/r.ck"
done
# 7. negative control: a mutant of BIN.om whose xtunes stores G as B must fail the B check
if [ -f "$BIN.om" ]; then
  want "mutant: one 'put xg 6 b2' line" "$(grep -c "^put xg 6 b2\$" "$BIN.om")" 1
  sed "s/^put xg 6 b2\$/put xg 6 g2/" "$BIN.om" > "$W/mut.om"
  $R "$OMC" < "$W/mut.om" > "$W/mut" && chmod +x "$W/mut"
  want "mutant build rc" $? 0
  $R "$W/mut" tune4 "$A" "$W/m.ck" 40 500 512 8 4 > /dev/null; want "mutant tune4 rc" $? 0
  mb=$(u8 "$W/m.ck" 56)
  [ "$mb" != 8 ] && ok "negative control caught: mutant B $mb, want 8" || no "negative control not caught (mutant B 8)"
  rm -f "$W/mut" "$W/mut.om" "$W/m.ck"
else
  no "negative control: $BIN.om (build.sh concatenated source) missing"
fi
rm -rf "$W"
[ $nf = 0 ] && { echo "TUNE4_CHECK PASS n=$n"; exit 0; }
echo "TUNE4_CHECK FAIL failed=$nf of n=$n$fl"
exit 1
