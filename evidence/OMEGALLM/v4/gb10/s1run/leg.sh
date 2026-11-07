#!/bin/sh
# one S1 training leg (run inside spark-window run): gtrain4 s1run.ck to UNTIL (save every 250), then
# geval4 of the saved CK on the held-out va4.u16 (first 4 MB of ~/data-omega/base/val.txt, merges32k), W 256
cd "$HOME/work/hive/ownmodel/gpu4/ref" || exit 2
B=/dev/shm/hive/ownmodel/gpu4/L4/ollm-gb10
U=$1
echo "leg until=$U binary=$(sha256sum $B | cut -c1-64) window=$SPARK_WINDOW utc=$(date -u +%FT%TZ)"
timeout 1000 taskset -c 5 nice -n 10 $B gtrain4 s1run.ck ../tr40.u16 "$U" 250
echo "gtrain4 rc $?"
echo "ck sha256 $(sha256sum s1run.ck | cut -c1-64)"
timeout 200 taskset -c 5 nice -n 10 $B geval4 s1run.ck ../va4.u16 256
echo "geval4 rc $?"
