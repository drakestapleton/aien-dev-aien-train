#!/bin/sh
# rung-7 gate window: v1 regression on the v2 binary, then the v2-shape gradient/Adam gates
D=~/handoffs/omega-llm-20261101/v1-data
P=/tmp/gk/r7/gpu2/ollm-gb10
PR=/tmp/gk/r7/gpur2/ollm-mut-r-gb10
cd /tmp/gk/r7/g2 || exit 2
run() {
  o=$1; b=$2; c=$3; shift 3
  { echo "binary: $(sha256sum $b | cut -c1-64)"; echo "ck: $(sha256sum $c | cut -c1-64)"; echo "cmd: $*"
    s=$(date -u +%s%N)
    case $1 in
      gcmp2|gacmp) timeout 900 $b $1 $c $D/$2 $3 2>&1 ;;
      geval) timeout 600 $b geval $c $D/held.tok $2 $D/merges4096.bin 2>&1 ;;
      gtrainf) timeout 900 $b gtrainf $c $D/train.tok $2 $3 2>&1 ;;
    esac
    echo rc=$?; echo wall_ns=$(( $(date -u +%s%N) - s ))
    [ "$1" = gtrainf ] && echo "ck_after: $(sha256sum $c | cut -c1-64)"; } > $o
}
run gc2-v2max-s7.txt $P /tmp/gk/r7/ckb8.bin gcmp2 train.tok 7
run gc2-v2max-s7-R.txt $PR /tmp/gk/r7/ckb8.bin gcmp2 train.tok 7
run gc2-small-s3.txt $P /tmp/gk/gt/ck.bin gcmp2 train.dec 3
run ge-v1-30000.txt $P /tmp/gk/r6/ck30000.bin geval 2243
run ge-v1-0.txt $P /tmp/gk/r6/ckL0.bin geval 2243
cp /tmp/gk/r6/ck9000.bin ckv1.bin
run t200-v1.txt $P ckv1.bin gtrainf 9200 200
rm -f ckv1.bin
run ga-v2-250.txt $P /tmp/gk/r7/g/ckg.bin gacmp train.tok 7
exit 0
