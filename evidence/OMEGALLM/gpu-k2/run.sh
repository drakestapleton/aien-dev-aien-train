#!/bin/sh
D=~/handoffs/omega-llm-20261101/v1-data
C2=/tmp/gk/c2/out/ollm-gb10
CT=/tmp/gk/c2/outt/ollm-mut-t-gb10
C1=/tmp/gk/c1/out/ollm-gb10
cd /tmp/gk/c2/w || exit 2
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
run gc2-small-s3-C2.txt $C2 /tmp/gk/gt/ck.bin gcmp2 train.dec 3
run gc2-small-s3-CT.txt $CT /tmp/gk/gt/ck.bin gcmp2 train.dec 3
run gc2-max-s7-C2.txt $C2 /tmp/gk/r5/ckb8.bin gcmp2 train.tok 7
run gc2-max-s7-CT.txt $CT /tmp/gk/r5/ckb8.bin gcmp2 train.tok 7
run ga-max-C2.txt $C2 /tmp/gk/r5/ck250.bin gacmp train.tok 7
run ge-max-9000-C2.txt $C2 /tmp/gk/r5/ck9000.bin geval 2243
run ge-max-30000-C2.txt $C2 /tmp/gk/r6/ck30000.bin geval 2243
run prof-C2.txt $C2 /tmp/gk/prof/ck.bin gprof 3
for x in C1 C2; do cp /tmp/gk/r6/ck9000.bin ck$x.bin; done
run t200-C1.txt $C1 ckC1.bin gtrainf 9200 200
run t200-C2.txt $C2 ckC2.bin gtrainf 9200 200
rm -f ckC1.bin ckC2.bin
exit 0
