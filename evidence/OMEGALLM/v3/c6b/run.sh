#!/bin/sh
set -u
D=/dev/shm/ollm-v3/c6b; cd $D
B=/dev/shm/ollm-v3/b-aarch64/ollm
V2=/tmp/gk/r7/cpu/ollm
H=$HOME/handoffs/omega-llm-20261101/v1-data
CK=/tmp/gk/r7/run/ck30000.bin
n=0
for blk in 1 2 3 4 5; do
  for v in v2 v3 v3 v2; do
    n=$((n+1)); [ $v = v2 ] && X=$V2 || X=$B
    /usr/bin/time -v taskset -c 4 nice -n 19 $X eval $CK $H/held.tok 4 $H/merges4096.bin > r$n-$v.out 2> r$n-$v.time; echo "rc=$?" >> r$n-$v.out
  done
done
echo done > done
