#!/bin/sh
# check 5 (rerun of the train part only; the first run was killed with the session at ~22:42Z)
set -u
D=/dev/shm/ollm-v3/c5; cd $D
B=/dev/shm/ollm-v3/b-aarch64/ollm
DATA=$HOME/handoffs/omega-llm-20261101/v1-data/train.tok
T="/usr/bin/time -v"
rm -f done; cp ck0.ck A.ck; cp ck0.ck B.ck
( $T taskset -c 1 nice -n 19 $B train A.ck $DATA 1 1 > A1.out 2> A1.time; echo "rc=$?" >> A1.out
  $T taskset -c 1 nice -n 19 $B train A.ck $DATA 2 1 > A2.out 2> A2.time; echo "rc=$?" >> A2.out ) &
( $T taskset -c 3 nice -n 19 $B train B.ck $DATA 2 2 > B.out 2> B.time; echo "rc=$?" >> B.out ) &
wait
cmp A.ck B.ck > cmpAB.txt 2>&1; echo "cmp rc=$?" >> cmpAB.txt
sha256sum A.ck B.ck >> cmpAB.txt
echo done > done
