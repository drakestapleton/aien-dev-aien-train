#!/bin/sh
# T3 (DRA-420 rope gap): serve DIR/checkpoint.ck holding s2 with only the rope base changed (header
# offset 112; not covered by the payload FNV), then rename the original s2 back over it after the load.
# The process runs the wrong rope; `deploy.sh live` must refuse. BUILD=old|new.
set -u
B=$1; Q=/home/drakestapleton/work/hive/queen-infer; R=$Q/loaded-identity; BIN=$Q/li-$B
[ "$B" = old ] && R=$Q/loaded-identity-old
W=$Q/li-smoke/t3-$B; rm -rf "$W"; mkdir -p "$W"; P=18283
export OMC=/home/drakestapleton/workspace/hive-worktrees/arch-scale-x/omc/seed/out/omc BIN CORES=1 REPO=$R
CK2=/home/drakestapleton/work/hive/ownmodel/ck/s2.ck TOK=/home/drakestapleton/work/hive/ownmodel/data/merges32k.bin
ss -ltn | grep -q ":$P " && { echo "port $P busy"; exit 3; }
sh $R/tests/omegallm/deploy/deploy.sh stage $W/a $CK2 $TOK $BIN/ollm s2 $P > $W/stage.log 2>&1; echo "stage rc=$?"
cp $W/a/checkpoint.ck $W/orig.ck
cp $W/a/checkpoint.ck $W/edit.ck; chmod u+w $W/edit.ck
# rope 40c3880000000000 (10000.0) -> 4090880000000000: header byte 118 0xc3 -> 0x90
printf '\220' | dd of=$W/edit.ck bs=1 seek=118 conv=notrunc status=none || exit 5
mv -f $W/edit.ck $W/a/checkpoint.ck
od -A d -t x1 -j 112 -N 8 $W/a/checkpoint.ck | head -1
taskset -c 1 nice -n 19 $W/a/bin/ollm serve $P $W/a/checkpoint.ck $W/a/merges.tok > $W/server.log 2>&1 & S=$!
i=0; until curl -s -m 2 http://127.0.0.1:$P/health > $W/health.txt 2>/dev/null && [ -s $W/health.txt ]; do kill -0 $S || { echo "server died"; tail -2 $W/server.log; exit 4; }; sleep 1; i=$((i+1)); [ $i -gt 600 ] && exit 4; done
mv $W/orig.ck $W/a/checkpoint.ck
grep -o '"ck_fnv[^,]*,"[a-z_]*":[^,]*' $W/health.txt
sh $R/tests/omegallm/deploy/deploy.sh live $W/a $P > $W/live.log 2>&1; echo "live rc=$? $(tail -1 $W/live.log | cut -c1-160)"
kill $S; wait $S 2>/dev/null; rm -f $W/a/checkpoint.ck
