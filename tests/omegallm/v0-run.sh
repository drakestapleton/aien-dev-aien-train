#!/bin/sh
set -eu
cd "$(dirname "$0")"
sha256sum ollm train.bin held.bin > shas.txt
date -u +%FT%TZ > started.txt
./ollm init ck.bin 256 64 64 4 256 2 16 1 20000 3000 > init.txt
./ollm eval ck.bin held.bin 256 >> evals.txt
u=1000
while [ $u -le 20000 ]; do
  ./ollm train ck.bin train.bin $u 250 >> train.txt
  ./ollm eval ck.bin held.bin 256 >> evals.txt
  cp ck.bin ck-$u.bin.tmp && mv ck-$u.bin.tmp ck-$u.bin
  u=$((u+1000))
done
./ollm eval ck.bin held.bin 4096 > final-eval.txt
for s in 1 2 3; do ./ollm sample ck.bin $s 400 800 "Once upon a time" > sample-$s.txt; echo >> sample-$s.txt; done
./ollm sample ck.bin 0 400 0 "Once upon a time" > sample-argmax.txt
date -u +%FT%TZ > finished.txt
