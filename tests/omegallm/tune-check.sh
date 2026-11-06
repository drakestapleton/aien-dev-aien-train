#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Checks for `ollm tune` (fine-tune entry, cli.om). Host CPU only.
# Usage: OLLM=path/to/ollm OMC=path/to/pinned/omc sh tests/omegallm/tune-check.sh   (build with tests/omegallm/build.sh)
# Data: the repository LICENSE as V 256 byte data (public, fixed bytes). Scratch in a temp dir.
# Prints one line per check and TUNE_PASS, or TUNE_FAIL and exit 1.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OLLM=${OLLM:?set OLLM to the built ollm}
OMC=${OMC:?set OMC to the pinned omc (builds the negative control)}
W=$(mktemp -d "${TMPDIR:-/tmp}/tune.XXXXXX")
D=$ROOT/LICENSE
bad=0
ok() { echo "PASS $*"; }
no() { echo "FAIL $*"; bad=1; }
want() { [ "$2" = "$3" ] && ok "$1: $2" || no "$1: got [$2] want [$3]"; }
echo "ollm_sha256=$(sha256sum "$OLLM" | cut -d" " -f1)"
echo "data_sha256=$(sha256sum "$D" | cut -d" " -f1)"
"$OLLM" init "$W/a.ck" 256 64 64 4 256 2 16 1 30 1000 > "$W/i.txt"; want init "$(cat "$W/i.txt")" "I 119104"
"$OLLM" train "$W/a.ck" "$D" 30 10 > "$W/t.txt"; want "train base 0..30 rc" $? 0
cp "$W/a.ck" "$W/b.ck"
"$OLLM" train "$W/b.ck" "$D" 40 10 > "$W/t2.txt"; want "train past TOTAL makes no step (why tune exists)" "$(wc -c < "$W/t2.txt" | tr -d " ")" 0
cmp -s "$W/a.ck" "$W/b.ck"; want "checkpoint unchanged past TOTAL" $? 0
"$OLLM" tune "$W/a.ck" "$W/u.ck" 20 500 > "$W/u.txt"; want tune "$(cat "$W/u.txt")" "U 119104"
e1=$("$OLLM" eval "$W/a.ck" "$D" 4 | cut -d" " -f3-)
e2=$("$OLLM" eval "$W/u.ck" "$D" 4 | cut -d" " -f3-)
want "weights kept (eval loss and bpb equal)" "$e2" "$e1"
s2=$("$OLLM" eval "$W/u.ck" "$D" 4 | cut -d" " -f2); want "step reset" "$s2" 0
P=119104; H=112
z=$(tail -c +$((H + 8 * P + 1)) "$W/u.ck" | head -c $((16 * P)) | tr -d "\000" | wc -c | tr -d " ")
want "Adam m and v zeroed" "$z" 0
z0=$(tail -c +$((H + 8 * P + 1)) "$W/a.ck" | head -c $((16 * P)) | tr -d "\000" | wc -c | tr -d " ")
[ "$z0" -gt 0 ] && ok "control: base checkpoint moments nonzero ($z0 bytes)" || no "control: base moments zero"
cp "$W/u.ck" "$W/u1.ck"; cp "$W/u.ck" "$W/u2.ck"
"$OLLM" train "$W/u1.ck" "$D" 20 10 > "$W/f.txt"; want "fine-tune 0..20 rc" $? 0
want "fine-tune saves" "$(cut -d" " -f1-2 "$W/f.txt" | tr "\n" ,)" "T 10,T 20,"
"$OLLM" train "$W/u2.ck" "$D" 10 10 > /dev/null; "$OLLM" train "$W/u2.ck" "$D" 20 10 > /dev/null
cmp -s "$W/u1.ck" "$W/u2.ck"; want "fine-tune resume 0..10..20 bit-identical to 0..20" $? 0
cmp -s "$W/u1.ck" "$W/u.ck"; [ $? -ne 0 ] && ok "fine-tune changed the weights" || no "fine-tune changed nothing"
l0=$("$OLLM" eval "$W/u.ck" "$D" 4 | cut -d" " -f4); l1=$("$OLLM" eval "$W/u1.ck" "$D" 4 | cut -d" " -f4)
[ "$l1" -lt "$l0" ] && ok "fine-tune lowered eval loss (micro-nats $l0 to $l1)" || no "fine-tune loss $l0 to $l1"
"$OLLM" tune "$W/a.ck" "$W/v.ck" 20 500 > /dev/null; cmp -s "$W/u.ck" "$W/v.ck"; want "tune deterministic" $? 0
"$OLLM" tune "$W/a.ck" "$W/x.ck" 0 500 > /dev/null 2>&1; want "TOTAL 0 refused" $? 12
"$OLLM" tune "$W/a.ck" "$W/x.ck" 1000000 500 > /dev/null 2>&1; want "TOTAL 1000000 refused" $? 12
"$OLLM" tune "$W/a.ck" "$W/x.ck" 20 > /dev/null 2>&1; want "argument count refused" $? 2
head -c 1000 "$W/a.ck" > "$W/short.ck"; "$OLLM" tune "$W/short.ck" "$W/x.ck" 20 500 > /dev/null 2>&1; want "truncated checkpoint refused" $? 10
[ -e "$W/x.ck" ] && no "refused tune left an output file" || ok "refused tune wrote no output"
# Negative control: the same source with the moment reset removed must fail the zero check.
[ -f "$OLLM.om" ] || no "negative control: $OLLM.om (build.sh concatenated source) missing"
if [ -f "$OLLM.om" ]; then
  n=$(grep -c "^ozerom mul 2 get og 8\$" "$OLLM.om")
  want "negative control: one moment-reset line to remove" "$n" 1
  grep -v "^ozerom mul 2 get og 8\$" "$OLLM.om" > "$W/mut.om"
  "$OMC" < "$W/mut.om" > "$W/mut" && chmod +x "$W/mut"
  "$W/mut" tune "$W/a.ck" "$W/m.ck" 20 500 > /dev/null
  zm=$(tail -c +$((H + 8 * P + 1)) "$W/m.ck" | head -c $((16 * P)) | tr -d "\000" | wc -c | tr -d " ")
  [ "$zm" -gt 0 ] && ok "negative control caught: moments not reset ($zm nonzero bytes)" || no "negative control not caught"
fi
rm -rf "$W"
[ $bad = 0 ] && echo TUNE_PASS || { echo TUNE_FAIL; exit 1; }
