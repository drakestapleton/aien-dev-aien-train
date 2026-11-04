#!/bin/sh
D=~/handoffs/omega-llm-20261101/v1-data
Q=/tmp/gk/k8c/binq/ollm-gb10
QT=/tmp/gk/k8c/binqt/ollm-mut-t-gb10
C=/tmp/gk/k8c/binc/ollm-gb10
B=/tmp/gk/k7b/bin/ollm-gb10
cd /tmp/gk/k8c/w || exit 2
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
run gc2-small-s3-Q.txt $Q /tmp/gk/gt/ck.bin gcmp2 train.dec 3
run gc2-small-s3-QT.txt $QT /tmp/gk/gt/ck.bin gcmp2 train.dec 3
run gc2-small-s3-C.txt $C /tmp/gk/gt/ck.bin gcmp2 train.dec 3
run ge-max-9000-Q.txt $Q /tmp/gk/r5/ck9000.bin geval 2243
run ge-max-30000-Q.txt $Q /tmp/gk/r6/ck30000.bin geval 2243
run ge-max-9000-C.txt $C /tmp/gk/r5/ck9000.bin geval 2243
run ge-max-30000-C.txt $C /tmp/gk/r6/ck30000.bin geval 2243
run gc2-max-s7-Q.txt $Q /tmp/gk/r5/ckb8.bin gcmp2 train.tok 7
run gc2-max-s7-QT.txt $QT /tmp/gk/r5/ckb8.bin gcmp2 train.tok 7
run gc2-max-s7-C.txt $C /tmp/gk/r5/ckb8.bin gcmp2 train.tok 7
run ga-max-Q.txt $Q /tmp/gk/r5/ck250.bin gacmp train.tok 7
run ga-max-C.txt $C /tmp/gk/r5/ck250.bin gacmp train.tok 7
run prof-1-B.txt $B /tmp/gk/prof/ck.bin gprof 3
run prof-1-C.txt $C /tmp/gk/prof/ck.bin gprof 3
run prof-1-Q.txt $Q /tmp/gk/prof/ck.bin gprof 3
run prof-2-Q.txt $Q /tmp/gk/prof/ck.bin gprof 3
run prof-2-B.txt $B /tmp/gk/prof/ck.bin gprof 3
run prof-2-C.txt $C /tmp/gk/prof/ck.bin gprof 3
run prof-3-C.txt $C /tmp/gk/prof/ck.bin gprof 3
run prof-3-Q.txt $Q /tmp/gk/prof/ck.bin gprof 3
run prof-3-B.txt $B /tmp/gk/prof/ck.bin gprof 3
for x in B C Q; do cp /tmp/gk/r6/ck9000.bin ck$x.bin; done
run t200-B.txt $B ckB.bin gtrainf 9200 200
run t200-C.txt $C ckC.bin gtrainf 9200 200
run t200-Q.txt $Q ckQ.bin gtrainf 9200 200
rm -f ckB.bin ckC.bin ckQ.bin
exit 0
