#!/bin/sh
# tests/omegallm/v4-gb10-check.sh: v4 on the GB10 (docs/omegallm/CONTRACT-V4-GB10.md, native/omegallm/gpu/g4.om).
# Usage: sh tests/omegallm/v4-gb10-check.sh PHASE
#   build   gb10 product and mutants rs ri cc into $BUILD (no chip)
#   refs    CPU references (no chip): init4 + ggrad4 for the parity shapes p1..p4 into $WORK
#   parity  CHIP (inside a spark-window lease): gcmp4 p1..p4 must PASS, mutants rs/ri/cc must FAIL
#           with rc 51, gcmp4b (BF16 bound) reported and gated
#   speedck S1 checkpoints (ginit4, CPU) for speed
#   speed   CHIP, --quiet exclusive: gtrain4 at S1 (V 32768 D 512 H 8 F 2048 L 8) for T 1024/2048/4096
#   big     CHIP: smoke of the shapes beyond S1 (ginit4'd beforehand: s1t8192.ck, big.ck in WORK)
#   resume  CHIP: save/reload/continue == uninterrupted (cmp), geval4 of the trained CK
#   trainref / trained  CPU ggrad4 of the chip-trained r200, then CHIP gcmp4 on it (+ mutants)
#   trajcpu / traj  CPU train4 40 steps on p1, then CHIP gtrain4f / gtrain4 from the same CK: loss
#           trajectories within 1e-4 (f32) / 2^-6 (BF16) relative; v3 mutant h (Adam beta1) must fail
#   resumes1 CHIP: the continuation check at S1 T 1024 (1 GB CK03)
#   evalcpu CPU eval4 of the chip-trained CK (no chip), compared with the chip geval4 E line
# Env: OMC (pinned omc), BUILD, WORK (large files), DATA (byte-token train file), DATA16 (the same as
#      u16), EV (receipts dir, default evidence/OMEGALLM/v4/gb10), G4CORES (taskset list, default 5; a
#      lane-specific name so a CORES exported for another script cannot move these runs).
# Each command writes EV/NAME.txt (command, binary sha256, output, rc, ms) and a line in EV/summary.tsv.
here=$(cd "$(dirname "$0")/../.." && pwd)
cd "$here" || exit 70
PH=${1:-}
BUILD=${BUILD:-/dev/shm/hive/ownmodel/gpu4/L}
WORK=${WORK:-$HOME/work/hive/ownmodel/gpu4/ref}
DATA=${DATA:-/dev/shm/hive/ownmodel/gpu4/tr8.bin}
DATA16=${DATA16:-/dev/shm/hive/ownmodel/gpu4/tr8.u16}
DATA32=${DATA32:-$HOME/work/hive/ownmodel/gpu4/tr40.u16}
HELD=${HELD:-/dev/shm/hive/ownmodel/gpu4/he8.bin}
E=${EV:-evidence/OMEGALLM/v4/gb10}
CORES=${G4CORES:-5}
RUN="taskset -c $CORES nice -n 10"
mkdir -p "$E" "$WORK" "$BUILD"
SUM=$E/summary.tsv
[ -f "$SUM" ] || printf 'receipt\trc\texpect\tverdict\n' > "$SUM"
fail=0
# rec NAME EXPECT_RC TIMEOUT BIN ARGS...
rec() {
	name=$1 want=$2 to=$3 bin=$4
	shift 4
	f=$E/$name.txt
	{
		echo "receipt: $name"
		echo "utc: $(date -u +%Y-%m-%dT%H:%M:%SZ) window: ${SPARK_WINDOW:-none}"
		echo "binary: $bin sha256 $(sha256sum "$BUILD/$bin" | cut -d' ' -f1)"
		echo "\$ timeout $to $RUN $BUILD/$bin $*"
		echo "--- output"
	} > "$f"
	t0=$(date +%s%N)
	timeout "$to" /usr/bin/time -f 'maxrss_kb %M' $RUN "$BUILD/$bin" "$@" >> "$f" 2>&1
	rc=$?
	t1=$(date +%s%N)
	echo "--- rc $rc ms $(( (t1 - t0) / 1000000 ))" >> "$f"
	v=PASS
	[ "$rc" = "$want" ] || { v=FAIL; fail=1; }
	printf '%s\t%s\t%s\t%s\n' "$name" "$rc" "$want" "$v" >> "$SUM"
	echo "$name rc $rc want $want $v"
}
# parity shapes: name V T D H F L B (seed 7, TOTAL 1000, lr 3000 micro, G 1) and data
shp() {
	case $1 in
	p1) echo "256 64 64 2 128 2 2" ;;
	p2) echo "256 512 64 2 128 2 2" ;;
	p4) echo "4096 1024 512 8 2048 1 2" ;;
	p3) echo "16384 256 512 8 2048 2 2" ;;
	esac
}
dat() { case $1 in p1|p2) echo "$DATA" ;; *) echo "$DATA16" ;; esac; }
case $PH in
build)
	: > "$E/build.txt"
	for a in "" "--mutant rs" "--mutant ri" "--mutant cc" "--mutant sv" "--mutant h" "--mutant od"; do
		# shellcheck disable=SC2086
		TARGET=gb10 OUT=$BUILD CORE=${CORES%%-*} sh tests/omegallm/build.sh $a >> "$E/build.txt" 2>&1 || { echo "BUILD_FAIL $a" | tee -a "$E/build.txt"; exit 1; }
	done
	cat "$E/build.txt"
	;;
refs)
	for p in p1 p2 p4 p3; do
		# shellcheck disable=SC2046
		rec "init4-$p" 0 600 ollm-gb10 init4 "$WORK/$p.ck" $(shp $p) 7 1000 3000 1
		rec "ggrad4-$p" 0 1800 ollm-gb10 ggrad4 "$WORK/$p.ck" "$(dat $p)" "$WORK/$p.gr"
	done
	;;
parity)
	for p in p1 p2 p4 p3; do
		rec "gcmp4-$p" 0 300 ollm-gb10 gcmp4 "$WORK/$p.ck" "$(dat $p)" "$WORK/$p.gr"
	done
	for m in rs ri cc; do
		for p in p1 p3; do
			rec "mut-$m-gcmp4-$p" 51 300 "ollm-mut-$m-gb10" gcmp4 "$WORK/$p.ck" "$(dat $p)" "$WORK/$p.gr"
		done
	done
	# od changes only the looped-softmax path (T a multiple of 256): p2 and p3, not p1
	for p in p2 p3; do
		rec "mut-od-gcmp4-$p" 51 300 ollm-mut-od-gb10 gcmp4 "$WORK/$p.ck" "$(dat $p)" "$WORK/$p.gr"
	done
	for p in p1 p4 p3; do
		rec "gcmp4b-$p" 0 300 ollm-gb10 gcmp4b "$WORK/$p.ck" "$(dat $p)" "$WORK/$p.gr"
	done
	;;
speedck)
	# S1 checkpoints for the speed phase (CPU, before the lease): name T B
	for x in "s1t1024 1024 16" "s1t2048 2048 8" "s1t4096 4096 4"; do
		set -- $x
		[ -f "$WORK/$1.ck" ] || rec "ginit4-$1" 0 900 ollm-gb10 ginit4 "$WORK/$1.ck" 32768 "$2" 512 8 2048 8 "$3" 7 100000 3000 1
	done
	;;
speed)
	# --quiet exclusive lease: N gtrain4 steps per S1 context length from a copy of the init CK
	N=${N:-10}
	for x in s1t1024 s1t2048 s1t4096; do
		cp "$WORK/$x.ck" "$WORK/run.ck"
		rec "speed-$x" 0 600 ollm-gb10 gtrain4 "$WORK/run.ck" "$DATA32" "$N" "$N"
	done
	rm -f "$WORK/run.ck"
	;;
big)
	# beyond S1 (non-quiet smoke, N steps): S1 at T 8192 B 1, and V 32768 T 1024 D 1024 H 16 F 4096 L 16 B 4
	N=${N:-3}
	for x in s1t8192 big; do
		cp "$WORK/$x.ck" "$WORK/run.ck"
		rec "big-$x" 0 900 ollm-gb10 gtrain4 "$WORK/run.ck" "$DATA32" "$N" "$N"
	done
	rm -f "$WORK/run.ck"
	;;
resumes1)
	# CHIP: the continuation check at S1 T 1024 B 16 (1 GB CK03): 0 -> 4 against 0 -> 2, reload, 2 -> 4
	cp "$WORK/s1t1024.ck" "$WORK/su.ck"
	cp "$WORK/s1t1024.ck" "$WORK/ss.ck"
	rec resumes1-u 0 600 ollm-gb10 gtrain4 "$WORK/su.ck" "$DATA32" 4 4
	rec resumes1-s1 0 600 ollm-gb10 gtrain4 "$WORK/ss.ck" "$DATA32" 2 2
	rec resumes1-s2 0 600 ollm-gb10 gtrain4 "$WORK/ss.ck" "$DATA32" 4 2
	{ echo "u $(sha256sum "$WORK/su.ck")"; echo "s $(sha256sum "$WORK/ss.ck")"; cmp "$WORK/su.ck" "$WORK/ss.ck" && echo SAME || echo DIFFER; } > "$E/resumes1-cmp.txt" 2>&1
	cat "$E/resumes1-cmp.txt"
	grep -q SAME "$E/resumes1-cmp.txt" || fail=1
	rm -f "$WORK/su.ck" "$WORK/ss.ck"
	;;
resume)
	# r: V256 T256 D128 H4 F512 L2 B8 (byte data); uninterrupted 0 -> 200 against 0 -> 100, reload, 100 -> 200
	R=$WORK/r
	mkdir -p "$R"
	[ -f "$R/r0.ck" ] || rec resume-init 0 120 ollm-gb10 ginit4 "$R/r0.ck" 256 256 128 4 512 2 8 11 400 3000 1
	for b in ollm-gb10 ollm-mut-sv-gb10; do
		cp "$R/r0.ck" "$R/u-$b.ck"
		cp "$R/r0.ck" "$R/s-$b.ck"
		rec "resume-u-$b" 0 300 "$b" gtrain4 "$R/u-$b.ck" "$DATA" 200 200
		rec "resume-s1-$b" 0 300 "$b" gtrain4 "$R/s-$b.ck" "$DATA" 100 100
		rec "resume-s2-$b" 0 300 "$b" gtrain4 "$R/s-$b.ck" "$DATA" 200 100
		{ echo "u $(sha256sum "$R/u-$b.ck")"; echo "s $(sha256sum "$R/s-$b.ck")"; cmp "$R/u-$b.ck" "$R/s-$b.ck" && echo SAME || echo DIFFER; } > "$E/resume-cmp-$b.txt" 2>&1
		cat "$E/resume-cmp-$b.txt"
	done
	grep -q SAME "$E/resume-cmp-ollm-gb10.txt" || fail=1
	grep -q DIFFER "$E/resume-cmp-ollm-mut-sv-gb10.txt" || fail=1
	cp "$R/u-ollm-gb10.ck" "$R/r200.ck"
	rec geval4-r200 0 300 ollm-gb10 geval4 "$R/r200.ck" "$HELD" 146
	;;
trainref)
	# CPU reference gradient of the chip-trained r200 checkpoint (resume phase output), no chip
	rec ggrad4-r200 0 1800 ollm-gb10 ggrad4 "$WORK/r/r200.ck" "$DATA" "$WORK/r/r200.gr"
	;;
trained)
	# CHIP: gcmp4 on the chip-trained r200 (step 200: attention far from uniform), mutants must fail
	rec gcmp4-r200 0 300 ollm-gb10 gcmp4 "$WORK/r/r200.ck" "$DATA" "$WORK/r/r200.gr"
	for m in rs ri cc; do
		rec "mut-$m-gcmp4-r200" 51 300 "ollm-mut-$m-gb10" gcmp4 "$WORK/r/r200.ck" "$DATA" "$WORK/r/r200.gr"
	done
	rec gcmp4b-r200 0 300 ollm-gb10 gcmp4b "$WORK/r/r200.ck" "$DATA" "$WORK/r/r200.gr"
	;;
trajcpu)
	# CPU train4 on p1 for 40 steps (save every 10): the reference loss trajectory, no chip
	cp "$WORK/p1.ck" "$WORK/tc.ck"
	rec traj-cpu 0 1800 ollm-gb10 train4 "$WORK/tc.ck" "$DATA" 40 10
	;;
traj)
	# CHIP: gtrain4f (f32 GEMMs) and gtrain4 (BF16) from the same p1 CK, 40 steps; mutant h (v3 gr.om
	# OMUTH: on-chip Adam beta1 0.8) must leave the f32 bound. Gate: every T line within 10^-4 relative
	# of the CPU's (f32), 2^-6 (BF16).
	for b in ollm-gb10 ollm-mut-h-gb10; do
		cp "$WORK/p1.ck" "$WORK/tg.ck"
		rec "traj-chipf-$b" 0 300 "$b" gtrain4f "$WORK/tg.ck" "$DATA" 40 10
	done
	cp "$WORK/p1.ck" "$WORK/tg.ck"
	rec traj-chipb 0 300 ollm-gb10 gtrain4 "$WORK/tg.ck" "$DATA" 40 10
	trj() { grep '^T ' "$E/$1.txt" | cut -d' ' -f3 | tr '\n' ' '; }
	c=$(trj traj-cpu)
	for x in "traj-chipf-ollm-gb10 0.0001 PASS" "traj-chipf-ollm-mut-h-gb10 0.0001 FAIL" "traj-chipb 0.015625 PASS"; do
		set -- $x
		g=$(trj "$1")
		v=$(echo "$c|$g" | awk -F'|' -v tol="$2" '{n=split($1,a," "); m=split($2,b," "); if (n != 4 || m != 4) {print "FAIL"; exit} ok="PASS"; for (i=1;i<=n;i++) {d=(a[i]-b[i])/a[i]; if (d<0) d=-d; if (d>tol) ok="FAIL"} print ok}')
		echo "$1 cpu [$c] chip [$g] tol $2 -> $v (want $3)" | tee -a "$E/traj-cmp.txt"
		[ "$v" = "$3" ] || fail=1
	done
	;;
evalcpu)
	rec eval4-r200 0 3600 ollm-gb10 eval4 "$WORK/r/r200.ck" "$HELD" 146
	a=$(grep '^E ' "$E/geval4-r200.txt")
	b=$(grep '^E ' "$E/eval4-r200.txt")
	{ echo "chip: $a"; echo "cpu:  $b"; [ -n "$a" ] && [ "$a" = "$b" ] && echo SAME || echo DIFFER; } > "$E/eval-cmp.txt"
	cat "$E/eval-cmp.txt"
	grep -q SAME "$E/eval-cmp.txt" || fail=1
	;;
*)
	echo "usage: v4-gb10-check.sh build|refs|parity|speedck|speed|big|resume|evalcpu|trainref|trained|trajcpu|traj|resumes1" >&2
	exit 2
	;;
esac
exit $fail
