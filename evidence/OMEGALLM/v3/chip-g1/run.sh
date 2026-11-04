#!/bin/sh
# v3 chip gate window v3-g1 on the integrated build (feat/omega-llm-v3 after the v2 and BF16 merges):
# F f32 regressions against the rung-7 receipts, L the CONTRACT-V3 L 16 gates, B the BF16 gates.
# Receipts land beside this script; scratch checkpoints in $S.
D=~/handoffs/omega-llm-20261101/v1-data
G=/tmp/gk/v3i/b-gb10
P=$G/ollm-gb10
P7=/tmp/gk/r7/gpu2/ollm-gb10
CKB8=/tmp/gk/r7/ckb8.bin
S=/tmp/gk/v3i/chip-g1
E=$(cd "$(dirname "$0")" && pwd)
cd $S || exit 2
run() {
  o=$1; b=$2; c=$3; tl=$4; shift 4
  { echo "binary: $(sha256sum $b | cut -c1-64)"; echo "ck: $(sha256sum $c | cut -c1-64)"; echo "cmd: $*"
    s=$(date -u +%s%N)
    case $1 in
      gbfrag) timeout $tl $b gbfrag $c 2>&1 ;;
      gbcmp|gbcmp2|gcmp2|gacmp) timeout $tl $b $1 $c $D/$2 $3 2>&1 ;;
      geval) timeout $tl $b geval $c $D/held.tok $2 $D/merges4096.bin 2>&1 ;;
      gtrainf) timeout $tl $b gtrainf $c $D/train.tok $2 $3 2>&1 ;;
    esac
    echo rc=$?; echo wall_ns=$(( $(date -u +%s%N) - s ))
    [ "$1" = gtrainf ] && echo "ck_after: $(sha256sum $c | cut -c1-64)"; } > $E/$o
}
# F: f32 regressions
cp /tmp/gk/r7/ckL0.bin ckg.bin
run F1-t250-v2.txt $P ckg.bin 900 gtrainf 250 250
run F2-ge-v2-250.txt $P ckg.bin 600 geval 2243
run F3-ga-v2-250.txt $P ckg.bin 900 gacmp train.tok 7
rm -f ckg.bin
cp /tmp/gk/r6/ck9000.bin ckv1.bin
run F4-t200-v1.txt $P ckv1.bin 900 gtrainf 9200 200
rm -f ckv1.bin
run F5-c2-v2max.txt $P $CKB8 900 gcmp2 train.tok 7
run F6-ge-r7-30000.txt $P /tmp/gk/r7/run/ck30000.bin 600 geval 2243
run F7-ge-r6-30000.txt $P /tmp/gk/r6/ck30000.bin 600 geval 2243
run F8-c2-small-P.txt $P cks.bin 900 gcmp2 train.dec 3
run F8-c2-small-P7.txt $P7 cks.bin 900 gcmp2 train.dec 3
# L: L 16 (v3 maximum depth)
run L1-c2-l16b8-P.txt $P ck16b8.bin 2400 gcmp2 train.tok 7
run L2-c2-l16b8-R.txt $G/ollm-mut-r-gb10 ck16b8.bin 2400 gcmp2 train.tok 7
run L3-ga-l16-P.txt $P ck16.bin 900 gacmp train.tok 7
run L4-bcmp-l16-P.txt $P ck16.bin 900 gbcmp train.tok 7
# B: BF16 gates (gpu-bf/g1 set) and the gbfrag padding check (gpu-bf/fix-pad)
run B1-frag-P.txt $P $CKB8 900 gbfrag
for m in u l o v n; do run B2-frag-$m.txt $G/ollm-mut-$m-gb10 $CKB8 900 gbfrag; done
run B3-bcmp-b8-P.txt $P $CKB8 900 gbcmp train.tok 7
cp /tmp/gk/r7/ckL0.bin ckL0.bin
run B4-bcmp-L0-P.txt $P ckL0.bin 900 gbcmp train.tok 7
rm -f ckL0.bin
for m in l o v u; do run B5-bcmp-b8-$m.txt $G/ollm-mut-$m-gb10 $CKB8 900 gbcmp train.tok 7; done
run B6-bc2-b8-P.txt $P $CKB8 900 gbcmp2 train.tok 7
exit 0
