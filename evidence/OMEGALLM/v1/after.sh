#!/bin/sh
# After ollm-night writes train.rc: held-out eval and samples from the final checkpoint, logged with times and shas.
cd "$(dirname "$0")/.."
while [ ! -s v1-night/train.rc ]; do sleep 60; done
o=v1-night/after.txt
{
  echo "start $(date -u +%FT%TZ)"
  cat v1-night/train.rc
  tail -1 v1-night/train.txt
  sha256sum v1-night/ollm v1-night/ck.bin v1-data/held.tok v1-data/merges4096.bin
  a=$(date +%s)
  taskset -c 6 v1-night/ollm eval v1-night/ck.bin v1-data/held.tok 4486 v1-data/merges4096.bin
  echo "eval rc=$? wall_s=$(( $(date +%s) - a ))"
} >> $o 2>&1
for p in "Once upon a time" "The little dog" "Lily wanted to"; do
  for t in 0 800; do
    {
      echo "--- sample seed 1 N 200 temp $t prompt [$p]"
      taskset -c 7 v1-night/ollm sample v1-night/ck.bin 1 200 $t "$p" v1-data/merges4096.bin
      r=$?
      echo
      echo "rc=$r"
    } >> v1-night/samples.txt 2>&1
  done
done
echo "end $(date -u +%FT%TZ)" >> $o
