#!/bin/sh
D=~/handoffs/omega-llm-20261101/v1-data
C=/tmp/gk/c1/out/ollm-gb10
CS=/tmp/gk/c1/outs/ollm-mut-s-gb10
CP=/tmp/gk/c1/outp/ollm-mut-p-gb10
A=/tmp/gk/sm/out/ollm-gb10
cd /tmp/gk/c1/w || exit 2
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
run gc2-small-s3-C.txt $C /tmp/gk/gt/ck.bin gcmp2 train.dec 3
run gc2-small-s3-CS.txt $CS /tmp/gk/gt/ck.bin gcmp2 train.dec 3
run gc2-small-s3-CP.txt $CP /tmp/gk/gt/ck.bin gcmp2 train.dec 3
run gc2-max-s7-C.txt $C /tmp/gk/r5/ckb8.bin gcmp2 train.tok 7
run gc2-max-s7-CS.txt $CS /tmp/gk/r5/ckb8.bin gcmp2 train.tok 7
run gc2-max-s7-CP.txt $CP /tmp/gk/r5/ckb8.bin gcmp2 train.tok 7
run ga-max-C.txt $C /tmp/gk/r5/ck250.bin gacmp train.tok 7
run ge-max-9000-C.txt $C /tmp/gk/r5/ck9000.bin geval 2243
run ge-max-30000-C.txt $C /tmp/gk/r6/ck30000.bin geval 2243
run prof-C.txt $C /tmp/gk/prof/ck.bin gprof 3
for x in A C; do cp /tmp/gk/r6/ck9000.bin ck$x.bin; done
run t200-A.txt $A ckA.bin gtrainf 9200 200
run t200-C.txt $C ckC.bin gtrainf 9200 200
rm -f ckA.bin ckC.bin
exit 0
