#!/bin/sh
# run1 leg: one spark-window lease = gtrain4 (BF16, CONTRACT-V4-GB10) to the next stop + geval4.
# Pre-registered in PREREG.md (same directory). Called by drive.sh through `spark-window run`.
R=/home/drakestapleton/work/hive/ownmodel/run1
D=/home/drakestapleton/work/hive/ownmodel/data
B=$R/bin/ollm-gb10
cd "$R" || exit 2
stage=$(cat stage.txt)
cur=$(grep -h '^T ' "train-$stage.txt" 2>/dev/null | tail -n 1 | cut -d' ' -f2)
[ -z "$cur" ] && cur=0
if [ "$stage" = A ]; then TR=$D/base-train.u16; END=24000; else TR=$D/mixB.u16; END=7300; fi
# steps this leg: 780 s of steps at the last measured step time (G4 line: field 2 steps, field 4 the
# summed step_ns of those steps), else 1200
sn=$(grep -h '^G4 ' "train-$stage.txt" 2>/dev/null | tail -n 1 | awk '$2 > 0 {printf "%d", $4 / $2}')
if [ -n "$sn" ] && [ "$sn" -gt 0 ]; then S=$((780000000000 / sn)); else S=1200; fi
S=$(( (S / 50) * 50 )); [ "$S" -lt 50 ] && S=50
u=$((cur + S)); [ "$u" -gt "$END" ] && u=$END
{ echo "leg from=$cur until=$u stage=$stage binary=$(sha256sum "$B" | cut -c1-16) data=$(basename "$TR")"; date -u +%s%N; } >> "train-$stage.txt"
timeout 1000 "$B" gtrain4 ck.bin "$TR" "$u" 500 >> "train-$stage.txt" 2>&1
r=$?
{ echo "rc=$r"; date -u +%s%N; } >> "train-$stage.txt"
[ $r -ne 0 ] && exit $r
case $u in 6000|12000|18000|24000) [ "$stage" = A ] && cp ck.bin "ckA$u.bin" ;; esac
[ "$stage" = B ] && [ "$u" -eq 7300 ] && cp ck.bin ckB7300.bin
if [ "$stage" = A ]; then
  { echo "step=$u stage=A ck=$(sha256sum ck.bin | cut -c1-64)"; date -u +%s%N
    timeout 200 "$B" geval4 ck.bin "$D/base-val.u16" 64 2>&1; echo rc=$?; date -u +%s%N; } >> geval.txt
else
  { echo "step=$u stage=B ck=$(sha256sum ck.bin | cut -c1-64)"; date -u +%s%N
    timeout 120 "$B" geval4 ck.bin "$D/base-val.u16" 16 2>&1; echo rc=$?
    timeout 120 "$B" geval4 ck.bin "$D/sft-val.u16" 16 2>&1; echo rc=$?; date -u +%s%N; } >> geval.txt
fi
exit 0
