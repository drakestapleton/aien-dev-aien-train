#!/bin/sh
# BF16 gate window bf-g1: gbfrag, gbcmp, gbcmp2 on the product and the four mutants, then the
# f32 regressions of the BF16 binary against the rung-7 binary
D=~/handoffs/omega-llm-20261101/v1-data
G=/dev/shm/ollm-bf/build-gb10
P=$G/ollm-gb10
P7=/tmp/gk/r7/gpu2/ollm-gb10
CKB8=/tmp/gk/r7/ckb8.bin
cd /dev/shm/ollm-bf/chip/g1 || exit 2
run() {
  o=$1; b=$2; c=$3; shift 3
  { echo "binary: $(sha256sum $b | cut -c1-64)"; echo "ck: $(sha256sum $c | cut -c1-64)"; echo "cmd: $*"
    s=$(date -u +%s%N)
    case $1 in
      gbfrag) timeout 300 $b gbfrag $c 2>&1 ;;
      gbcmp|gbcmp2|gcmp2|gacmp) timeout 900 $b $1 $c $D/$2 $3 2>&1 ;;
      geval) timeout 600 $b geval $c $D/held.tok $2 $D/merges4096.bin 2>&1 ;;
      gtrainf) timeout 900 $b gtrainf $c $D/train.tok $2 $3 2>&1 ;;
    esac
    echo rc=$?; echo wall_ns=$(( $(date -u +%s%N) - s ))
    [ "$1" = gtrainf ] && echo "ck_after: $(sha256sum $c | cut -c1-64)"; } > $o
}
run bf-frag-P.txt $P $CKB8 gbfrag
for m in u l o v; do run bf-frag-$m.txt $G/ollm-mut-$m-gb10 $CKB8 gbfrag; done
run bf-cmp-b8-P.txt $P $CKB8 gbcmp train.tok 7
cp /tmp/gk/r7/ckL0.bin ckL0.bin
run bf-cmp-L0-P.txt $P ckL0.bin gbcmp train.tok 7
rm -f ckL0.bin
for m in l o v u; do run bf-cmp-b8-$m.txt $G/ollm-mut-$m-gb10 $CKB8 gbcmp train.tok 7; done
run bf-c2-b8-P.txt $P $CKB8 gbcmp2 train.tok 7
run f32-ge-r7-30000.txt $P /tmp/gk/r7/run/ck30000.bin geval 2243
run f32-ge-r6-30000.txt $P /tmp/gk/r6/ck30000.bin geval 2243
cp /tmp/gk/r6/ck9000.bin ckv1.bin
run f32-t200-v1.txt $P ckv1.bin gtrainf 9200 200
rm -f ckv1.bin
run f32-c2-small-P.txt $P cks.bin gcmp2 train.dec 3
run f32-c2-small-P7.txt $P7 cks.bin gcmp2 train.dec 3
run f32-c2-v2max-P.txt $P $CKB8 gcmp2 train.tok 7
run f32-ga-v2-250-P.txt $P /tmp/gk/r7/g/ckg.bin gacmp train.tok 7
exit 0
