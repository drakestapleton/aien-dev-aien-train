#!/bin/sh
# DRA-420 loaded-identity smoke: BUILD=old|new. Port 18283, core 1, nice 19.
# T1 restage-in-place: serve DIR (s2), then rename s1's checkpoint and manifests over DIR.
#    `deploy.sh live` must refuse (the process still runs s2). Old build: /health re-reads disk.
# T2 rename during load: serve a path, rename s1 over it once a third of s2 is read.
#    The server must load s2 whole (identity = s2) or refuse; never report anything else.
B=$1; Q=/home/drakestapleton/work/hive/queen-infer; R=$Q/loaded-identity; BIN=$Q/li-$B
[ "$B" = old ] && R=$Q/loaded-identity-old
set -u
W=$Q/li-smoke/$B; rm -rf "$W"; mkdir -p "$W"; P=18283
export OMC=/home/drakestapleton/workspace/hive-worktrees/arch-scale-x/omc/seed/out/omc BIN CORES=1 REPO=$R
CK2=/home/drakestapleton/work/hive/ownmodel/ck/s2.ck CK1=/home/drakestapleton/work/hive/ownmodel/ck/s1.ck
TOK=/home/drakestapleton/work/hive/ownmodel/data/merges32k.bin
D=sh\ $R/tests/omegallm/deploy/deploy.sh
waitup(){ i=0; while [ $i -lt 600 ]; do curl -s -m 2 http://127.0.0.1:$P/health > "$1" 2>/dev/null && [ -s "$1" ] && return 0; kill -0 $2 2>/dev/null || return 1; sleep 1; i=$((i+1)); done; return 1; }
stop(){ kill $1 2>/dev/null; wait $1 2>/dev/null; echo "server rc=$?"; }
ss -ltn | grep -q ":$P " && { echo "port $P busy"; exit 3; }

echo "== T1 $B"
sh $R/tests/omegallm/deploy/deploy.sh stage $W/a $CK2 $TOK $BIN/ollm s2 $P > $W/stage-a.log 2>&1; echo "stage a rc=$?"
sh $R/tests/omegallm/deploy/deploy.sh stage $W/b $CK1 $TOK $BIN/ollm s1 $P > $W/stage-b.log 2>&1; echo "stage b rc=$?"
sh $R/tests/omegallm/deploy/deploy.sh gate $W/a > $W/gate-a.log 2>&1; echo "gate a rc=$? $(tail -1 $W/gate-a.log)"
taskset -c 1 nice -n 19 $W/a/bin/ollm serve $P $W/a/checkpoint.ck $W/a/merges.tok > $W/t1-server.log 2>&1 & S=$!
waitup $W/t1-health-0.txt $S || { echo "T1 server did not come up"; stop $S; exit 4; }
sh $R/tests/omegallm/deploy/deploy.sh live $W/a $P > $W/live-0.log 2>&1; echo "live before restage rc=$? $(tail -1 $W/live-0.log)"
for f in checkpoint.ck model.manifest deploy.manifest; do mv $W/b/$f $W/a/$f; done
curl -s -m 5 http://127.0.0.1:$P/health > $W/t1-health-1.txt
sh $R/tests/omegallm/deploy/deploy.sh live $W/a $P > $W/live-1.log 2>&1; echo "live after restage rc=$? $(tail -1 $W/live-1.log)"
cmp -s $W/t1-health-0.txt $W/t1-health-1.txt && echo "T1 health unchanged" || echo "T1 health CHANGED"
grep -o '"model":{.*' $W/t1-health-0.txt; grep -o '"model":{.*' $W/t1-health-1.txt
stop $S

echo "== T2 $B"
cp $CK2 $W/t2.ck; cp $CK1 $W/t2-next.ck
N=$(stat -c %s $CK2)
taskset -c 1 nice -n 19 $BIN/ollm serve $P $W/t2.ck $TOK > $W/t2-server.log 2>&1 & S=$!
i=0; while [ $i -lt 6000 ]; do rb=$(awk '/^rchar/{print $2}' /proc/$S/io 2>/dev/null); [ -n "$rb" ] && [ "$rb" -gt $((N/3)) ] && break; kill -0 $S 2>/dev/null || break; sleep 0.05; i=$((i+1)); done
mv $W/t2-next.ck $W/t2.ck; echo "renamed at rchar=$rb of $N"
if waitup $W/t2-health.txt $S; then grep -o '"model":{.*' $W/t2-health.txt; stop $S; else stop $S; echo "T2 server exited before /health"; tail -2 $W/t2-server.log; fi
echo "s2 identity: $(grep -o '"model":{.*' $W/t1-health-0.txt | head -c 400)"
rm -f $W/t2.ck $W/t2-next.ck $W/a/checkpoint.ck $W/b/checkpoint.ck
