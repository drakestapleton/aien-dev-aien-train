#!/bin/sh
# Rerun of the PR #54 "Checks run" rows that had no saved log (2026-11-04, spark-b87b, one core).
# Usage, from the directory that holds the aien-train clone, data/ and v1-data/:
#   CLONE=wt/v1 OMC=<omc 2c824805> CORE=5 OUT=fixv1/s1 sh wt/v1/evidence/OMEGALLM/v1/checks/reruns.sh
# Every path is relative to that directory; absolute paths printed by v1-oracle.sh have the
# directory's prefix removed (sed below) so the receipts name no private path.
# Rows:
#   build      ollm, ollm-mut-d, ollm-mut-e from CLONE (build.sh), and the v0 reference ollm from
#              the base commit e08443c (git archive of native/omegallm and tests/omegallm)
#   oracle     v1-oracle.sh on ollm with V0BIN: want SUMMARY pass=54 fail=0 not_run=0
#   mut-e      v1-oracle.sh on ollm-mut-e: want FAIL lines (exit 1)
#   kgroup     CFG of v1-oracle.sh at G = 4, 5 steps on the referee's train300.tok: K = 1, 2, 4
#              byte-identical
#   mut-d      the same with ollm-mut-d, K = 1 vs K = 2: want different checkpoints
#   config-a   V4096 T128 D128 H4 F512 L4 B16 G4 on v1-data/train.tok, 2 steps: K = 1 vs K = 4
#              byte-identical
set -u
CLONE=${CLONE:?} OMC=${OMC:?} CORE=${CORE:?} OUT=${OUT:?}
RUN="taskset -c $CORE nice -n 19"
B=$OUT/build
mkdir -p "$B" "$OUT/v0src" "$OUT/k" "$OUT/a"
echo "date $(date -u +%FT%TZ) host $(hostname) core $CORE"
echo "clone $(git -C "$CLONE" rev-parse HEAD)"
echo "omc $(sha256sum "$OMC" | cut -d' ' -f1)"
echo "--- build"
for a in "" "--mutant d" "--mutant e"; do
	# shellcheck disable=SC2086
	OMC=$OMC OUT=$B CORE=$CORE sh "$CLONE/tests/omegallm/build.sh" $a 2>&1
	echo "rc=$?"
done
git -C "$CLONE" archive e08443c3332bdd3b81a549bb76815f688b763ff5 native/omegallm tests/omegallm/build.sh | tar -x -C "$OUT/v0src"
OMC=$OMC OUT=$OUT/v0build CORE=$CORE sh "$OUT/v0src/tests/omegallm/build.sh" 2>&1
echo "rc=$? (v0 reference, base e08443c)"
strip() { sed "s|$(pwd)/||g"; }
# v1-oracle.sh runs the referee inside WORK, so DATA must be absolute
DATA=$(pwd)/data
bad=0
# t LABEL CMD...: run CMD, print LABEL rc=N; a nonzero rc invalidates the comparisons below
t() { _l=$1; shift; $RUN "$@"; _r=$?; echo "$_l rc=$_r"; [ $_r = 0 ] || bad=$((bad + 1)); }
# same A B: verdict on two checkpoints that must both differ from the init checkpoint I
same() { [ $bad = 0 ] || { echo "INVALID: $bad command(s) exited nonzero"; return; }
	cmp -s "$1" "$3" && { echo "INVALID: $1 equals the init checkpoint"; return; }
	cmp "$1" "$2" && echo "EQUAL $1 $2" || echo "DIFFERENT $1 $2"; }
echo "--- oracle"
BIN=$B/ollm V0BIN=$OUT/v0build/ollm DATA=$DATA WORK=$OUT/vo CORE=$CORE sh "$CLONE/tests/omegallm/v1-oracle.sh" 2>&1 | strip
echo "--- mut-e"
BIN=$B/ollm-mut-e V0BIN=$OUT/v0build/ollm DATA=$DATA WORK=$OUT/vo-e CORE=$CORE sh "$CLONE/tests/omegallm/v1-oracle.sh" > "$OUT/vo-e.log" 2>&1
echo "rc=$? (want 1)"
strip < "$OUT/vo-e.log"
echo "--- kgroup (want: K=2 and K=4 EQUAL to K=1)"
TR=$OUT/vo/ref/train300.tok
sha256sum "$TR" || bad=$((bad + 1))
K=$OUT/k
mkdir -p "$K"
rm -f "$K"/*.ck
t init "$B/ollm" init "$K/i4.ck" 300 8 16 2 32 2 4 5 50 3000 4
for k in 1 2 4; do
	cp "$K/i4.ck" "$K/k$k.ck"
	t "train K=$k" "$B/ollm" train "$K/k$k.ck" "$TR" 5 5 $k
done
sha256sum "$K/i4.ck" "$K/k1.ck" "$K/k2.ck" "$K/k4.ck"
same "$K/k1.ck" "$K/k2.ck" "$K/i4.ck"
same "$K/k1.ck" "$K/k4.ck" "$K/i4.ck"
echo "--- mut-d (want: K=1 vs K=2 DIFFERENT)"
for k in 1 2; do
	cp "$K/i4.ck" "$K/d$k.ck"
	t "mut-d train K=$k" "$B/ollm-mut-d" train "$K/d$k.ck" "$TR" 5 5 $k
done
sha256sum "$K/d1.ck" "$K/d2.ck"
same "$K/d1.ck" "$K/d2.ck" "$K/i4.ck"
echo "--- config-a (want: K=4 EQUAL to K=1)"
A=$OUT/a
mkdir -p "$A"
rm -f "$A"/*.ck
sha256sum v1-data/train.tok
t init "$B/ollm" init "$A/a.ck" 4096 128 128 4 512 4 16 1 20000 3000 4
for k in 1 4; do
	cp "$A/a.ck" "$A/a.k$k.ck"
	t0=$(date +%s)
	t "train K=$k" "$B/ollm" train "$A/a.k$k.ck" v1-data/train.tok 2 2 $k
	echo "wall_s=$(($(date +%s) - t0))"
done
sha256sum "$A/a.ck" "$A/a.k1.ck" "$A/a.k4.ck"
same "$A/a.k1.ck" "$A/a.k4.ck" "$A/a.ck"
echo "end $(date -u +%FT%TZ)"
