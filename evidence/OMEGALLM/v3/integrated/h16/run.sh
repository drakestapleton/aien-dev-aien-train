#!/bin/sh
# CONTRACT-V3 check 5 supplement: the attention-probability bound L*H*T^2 = 2^24 reached
# (H 16, L 16, T 256) at a small width; product vs referee after init and after one train step.
set -u
D=/tmp/gk/v3i/h16; cd $D
B=/tmp/gk/v3i/b-aarch64/ollm
W=/tmp/wt-v3
DATA=$HOME/handoffs/omega-llm-20261101/v1-data/train.tok
S="4096 256 16 16 32 16 1 1 100 3000 1"
T="/usr/bin/time -v"
{
echo "binary $(sha256sum $B | cut -d' ' -f1)"
echo "oracle $(sha256sum $W/tests/omegallm/oracle.py | cut -d' ' -f1)"
echo "data $(sha256sum $DATA | cut -d' ' -f1)"
} > env.txt
( echo "\$ ollm init p.ck $S"; taskset -c 0 nice -n 19 $B init p.ck $S; echo "rc=$?"
  sha256sum p.ck > p0.sha256
  echo "\$ ollm train p.ck train.tok 1 1"; $T taskset -c 0 nice -n 19 $B train p.ck $DATA 1 1 2> p.time; echo "rc=$?" ) > p.out 2>&1 &
( echo "\$ oracle.py ollm init r.ck $S"; taskset -c 1 nice -n 19 python3 $W/tests/omegallm/oracle.py ollm init r.ck $S; echo "rc=$?"
  sha256sum r.ck > r0.sha256
  echo "\$ oracle.py ollm train r.ck train.tok 1 1"; $T taskset -c 1 nice -n 19 python3 $W/tests/omegallm/oracle.py ollm train r.ck $DATA 1 1 2> r.time; echo "rc=$?" ) > r.out 2>&1 &
wait
cmp p.ck r.ck > cmp.txt 2>&1; echo "cmp rc=$?" >> cmp.txt
sha256sum p.ck r.ck >> cmp.txt
echo done > done
