#!/bin/sh
D=~/handoffs/omega-llm-20261101/v1-data
K7=/tmp/gk/k7/bin/ollm-gb10
KT=/tmp/gk/k7/bin/ollm-mut-t-gb10
R0=/tmp/gk/k7/bin/ollm-var-r0-gb10
B0=/tmp/gk/k7/bin/ollm-var-b0-gb10
K6=/tmp/gk/k6/bin/ollm-gb10
cd /tmp/gk/k7/w || exit 2
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
run gc2-small-s3-K7.txt $K7 /tmp/gk/gt/ck.bin gcmp2 train.dec 3
run gc2-small-s3-KT.txt $KT /tmp/gk/gt/ck.bin gcmp2 train.dec 3
run ge-max-9000-K7.txt $K7 /tmp/gk/r5/ck9000.bin geval 2243
run ge-max-30000-K7.txt $K7 /tmp/gk/r6/ck30000.bin geval 2243
run gc2-max-s7-K7.txt $K7 /tmp/gk/r5/ckb8.bin gcmp2 train.tok 7
run gc2-max-s7-KT.txt $KT /tmp/gk/r5/ckb8.bin gcmp2 train.tok 7
run ga-max-K7.txt $K7 /tmp/gk/r5/ck250.bin gacmp train.tok 7
run prof-K6a.txt $K6 /tmp/gk/prof/ck.bin gprof 3
run prof-K7.txt $K7 /tmp/gk/prof/ck.bin gprof 3
run prof-R0.txt $R0 /tmp/gk/prof/ck.bin gprof 3
run prof-B0.txt $B0 /tmp/gk/prof/ck.bin gprof 3
run prof-K6b.txt $K6 /tmp/gk/prof/ck.bin gprof 3
for x in K6 K7; do cp /tmp/gk/r6/ck9000.bin ck$x.bin; done
run t200-K6.txt $K6 ckK6.bin gtrainf 9200 200
run t200-K7.txt $K7 ckK7.bin gtrainf 9200 200
rm -f ckK6.bin ckK7.bin
exit 0
