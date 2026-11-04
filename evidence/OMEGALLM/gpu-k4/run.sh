#!/bin/sh
D=~/handoffs/omega-llm-20261101/v1-data
K4=/tmp/gk/k4/bin/ollm-gb10
KX=/tmp/gk/k4/bin/ollm-mut-x-gb10
KK=/tmp/gk/k4/bin/ollm-mut-k-gb10
K3=/tmp/gk/k3/bin/ollm-gb10
cd /tmp/gk/k4/w || exit 2
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
run gc2-small-s3-K4.txt $K4 /tmp/gk/gt/ck.bin gcmp2 train.dec 3
run gc2-small-s3-KX.txt $KX /tmp/gk/gt/ck.bin gcmp2 train.dec 3
run ge-max-9000-K4.txt $K4 /tmp/gk/r5/ck9000.bin geval 2243
run ge-max-30000-K4.txt $K4 /tmp/gk/r6/ck30000.bin geval 2243
run ge-max-9000-KX.txt $KX /tmp/gk/r5/ck9000.bin geval 2243
run ge-max-9000-KK.txt $KK /tmp/gk/r5/ck9000.bin geval 2243
run ge-max-30000-KK.txt $KK /tmp/gk/r6/ck30000.bin geval 2243
run gc2-max-s7-K4.txt $K4 /tmp/gk/r5/ckb8.bin gcmp2 train.tok 7
run gc2-max-s7-KX.txt $KX /tmp/gk/r5/ckb8.bin gcmp2 train.tok 7
run ga-max-K4.txt $K4 /tmp/gk/r5/ck250.bin gacmp train.tok 7
run prof-K3.txt $K3 /tmp/gk/prof/ck.bin gprof 3
run prof-K4.txt $K4 /tmp/gk/prof/ck.bin gprof 3
for x in K3 K4; do cp /tmp/gk/r6/ck9000.bin ck$x.bin; done
run t200-K3.txt $K3 ckK3.bin gtrainf 9200 200
run t200-K4.txt $K4 ckK4.bin gtrainf 9200 200
rm -f ckK3.bin ckK4.bin
exit 0
