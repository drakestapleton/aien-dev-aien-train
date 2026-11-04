#!/bin/sh
# usage: cpu-eval.sh CK OUT CORE  -- P-check CPU eval of a checkpoint with the v2 CPU build, one core, nice 19
set -u
CK=$1; OUT=$2; CORE=$3
D=/home/drakestapleton/handoffs/omega-llm-20261101/v1-data
B=/tmp/gk/r7/cpu/ollm
{
echo "cmd: taskset -c $CORE nice -n 19 cpu/ollm eval $(basename $CK) held.tok 2243 merges4096.bin"
echo "bin_sha256 $(sha256sum $B | cut -d' ' -f1)"
echo "ck_sha256 $(sha256sum $CK | cut -d' ' -f1)"
echo "start_utc $(date -u +%FT%TZ) start_ns $(date +%s%N)"
echo "--- output"
} > $OUT
taskset -c $CORE nice -n 19 $B eval $CK $D/held.tok 2243 $D/merges4096.bin >> $OUT 2>&1
rc=$?
{ echo "--- end"; echo "rc=$rc"; echo "end_utc $(date -u +%FT%TZ) end_ns $(date +%s%N)"; } >> $OUT
