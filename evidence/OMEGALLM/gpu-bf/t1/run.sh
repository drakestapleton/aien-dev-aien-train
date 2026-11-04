#!/bin/sh
# BF16 window bf-t1: per-kernel profile f32 vs BF16 (alternating, 3 rounds), then gtrainb from the
# rung-7 start checkpoint for 0 -> 250 -> 2000 with a geval after each leg
D=~/handoffs/omega-llm-20261101/v1-data
P=/dev/shm/ollm-bf/build-gb10/ollm-gb10
L0=/tmp/gk/r7/ckL0.bin
cd /dev/shm/ollm-bf/chip/t1 || exit 2
run() {
  o=$1; c=$2; shift 2
  { echo "binary: $(sha256sum $P | cut -c1-64)"; echo "ck: $(sha256sum $c | cut -c1-64)"; echo "cmd: $*"
    s=$(date -u +%s%N)
    case $1 in
      gprof|gprofb) timeout 600 $P $1 $c $D/train.tok $2 2>&1 ;;
      gtrainb) timeout 1500 $P gtrainb $c $D/train.tok $2 $3 2>&1 ;;
      geval) timeout 600 $P geval $c $D/held.tok 2243 $D/merges4096.bin 2>&1 ;;
    esac
    echo rc=$?; echo wall_ns=$(( $(date -u +%s%N) - s ))
    [ "$1" = gtrainb ] && echo "ck_after: $(sha256sum $c | cut -c1-64)"; } > $o
}
for r in 1 2 3; do
  run prof-f32-$r.txt $L0 gprof 3
  run prof-bf-$r.txt $L0 gprofb 3
done
cp $L0 ck.bin
run tb-0-250.txt ck.bin gtrainb 250 250
run ge-250.txt ck.bin geval
cp ck.bin ck250.bin
run tb-250-2000.txt ck.bin gtrainb 2000 250
run ge-2000.txt ck.bin geval
exit 0
