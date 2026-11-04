#!/bin/sh
D=~/handoffs/omega-llm-20261101/v1-data
P=/tmp/gk/k8/bin/ollm-gb10
PT=/tmp/gk/k8/bint/ollm-mut-t-gb10
B=/tmp/gk/k7b/bin/ollm-gb10
cd /tmp/gk/k8/w || exit 2
run() {
  o=$1; b=$2; c=$3; shift 3
  { echo "binary: $(sha256sum $b | cut -c1-64)"; echo "ck: $(sha256sum $c | cut -c1-64)"; echo "cmd: $*"
    s=$(date -u +%s%N)
    case $1 in
      gcmp2|gacmp) timeout 600 $b $1 $c $D/$2 $3 2>&1 ;;
      geval) timeout 600 $b geval $c $D/held.tok $2 $D/merges4096.bin 2>&1 ;;
      gprof) timeout 600 $b gprof $c $D/train.tok $2 2>&1 ;;
      gtrainf) timeout 900 $b gtrainf $c $D/train.tok $2 $3 2>&1 ;;
    esac
    echo rc=$?; echo wall_ns=$(( $(date -u +%s%N) - s ))
    [ "$1" = gtrainf ] && echo "ck_after: $(sha256sum $c | cut -c1-64)"; } > $o
}
run gc2-small-s3-P.txt $P /tmp/gk/gt/ck.bin gcmp2 train.dec 3
run gc2-small-s3-PT.txt $PT /tmp/gk/gt/ck.bin gcmp2 train.dec 3
run ge-max-9000-P.txt $P /tmp/gk/r5/ck9000.bin geval 2243
run ge-max-30000-P.txt $P /tmp/gk/r6/ck30000.bin geval 2243
run gc2-max-s7-P.txt $P /tmp/gk/r5/ckb8.bin gcmp2 train.tok 7
run gc2-max-s7-PT.txt $PT /tmp/gk/r5/ckb8.bin gcmp2 train.tok 7
run ga-max-P.txt $P /tmp/gk/r5/ck250.bin gacmp train.tok 7
run prof-1-B.txt $B /tmp/gk/prof/ck.bin gprof 3
run prof-1-P.txt $P /tmp/gk/prof/ck.bin gprof 3
run prof-2-P.txt $P /tmp/gk/prof/ck.bin gprof 3
run prof-2-B.txt $B /tmp/gk/prof/ck.bin gprof 3
run prof-3-B.txt $B /tmp/gk/prof/ck.bin gprof 3
run prof-3-P.txt $P /tmp/gk/prof/ck.bin gprof 3
for x in B P; do cp /tmp/gk/r6/ck9000.bin ck$x.bin; done
run t200-B.txt $B ckB.bin gtrainf 9200 200
run t200-P.txt $P ckP.bin gtrainf 9200 200
rm -f ckB.bin ckP.bin
exit 0
