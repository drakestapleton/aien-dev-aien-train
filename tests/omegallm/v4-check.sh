#!/bin/sh
# tests/omegallm/v4-check.sh: v4 receipts (docs/omegallm/CONTRACT-V4.md).
# Run from anywhere: sh native/../tests/omegallm/v4-check.sh. Env: OMC (pinned omc), BUILD, WORK,
# CORES (taskset list, default 4-5), EV (evidence dir). Training text is this repository's own
# .om sources and docs (first-party, no outside data), split into stories every 40 lines.
here=$(cd "$(dirname "$0")/../.." && pwd)
cd "$here" || exit 70
BUILD=${BUILD:-scratch-v4/build}
WORK=${WORK:-scratch-v4/work}
CORES=${CORES:-4-5}
E=${EV:-evidence/OMEGALLM/v4}
RUN="taskset -c $CORES nice -n 10"
mkdir -p "$E" "$WORK" "$BUILD"
: > "$E/build.txt"
for a in "" "--mutant i" "--mutant z"; do
	# shellcheck disable=SC2086
	OUT=$BUILD CORE=${CORES%%-*} sh tests/omegallm/build.sh $a >> "$E/build.txt" 2>&1 || {
		echo "BUILD_FAIL $a" | tee -a "$E/build.txt"
		exit 1
	}
done
cat "$E/build.txt"
cat native/omegallm/*.om docs/omegallm/*.md | awk '{print} NR%40==0 {print "<|endoftext|>"}' > "$WORK/in.txt"
TR=$WORK/train.bin
HE=$WORK/held.bin
SUM=$E/summary.tsv
printf 'receipt\trc\texpect\tverdict\n' > "$SUM"
fail=0
# rec NAME EXPECT_RC BIN ARGS... : run one command, write $E/NAME.txt, append to summary.tsv
rec() {
	name=$1 want=$2 bin=$3
	shift 3
	f=$E/$name.txt
	{
		echo "receipt: $name"
		echo "binary: $bin sha256 $(sha256sum "$BUILD/$bin" | cut -d' ' -f1)"
		echo "\$ $RUN $BUILD/$bin $*"
		echo "--- output"
	} > "$f"
	t0=$(date +%s%N)
	$RUN "$BUILD/$bin" "$@" >> "$f" 2>&1
	rc=$?
	t1=$(date +%s%N)
	echo "--- rc $rc ms $(( (t1 - t0) / 1000000 ))" >> "$f"
	v=PASS
	[ "$rc" = "$want" ] || { v=FAIL; fail=1; }
	printf '%s\t%s\t%s\t%s\n' "$name" "$rc" "$want" "$v" >> "$SUM"
}
rec prep 0 ollm prep "$WORK/in.txt" "$TR" "$HE"
# 1. small model: gcheck against finite differences, RoPE mutants must fail it
rec init4-s 0 ollm init4 "$WORK/s.ck" 256 64 16 2 32 2 4 1 100 1000 2
rec gcheck4 0 ollm gcheck4 "$WORK/s.ck" "$TR"
rec mut-i-gcheck4 40 ollm-mut-i gcheck4 "$WORK/s.ck" "$TR"
rec mut-z-gcheck4 40 ollm-mut-z gcheck4 "$WORK/s.ck" "$TR"
# 2. RoPE sin/cos against Wolfram (roperef.wl) and the relative-position shift identity
rec ropeck 0 ollm ropeck tests/omegallm/roperef.txt
rec mut-i-ropeck 43 ollm-mut-i ropeck tests/omegallm/roperef.txt
# 3. training: loss falls, K = 1 and K = 2 workers give byte-identical checkpoints
cp "$WORK/s.ck" "$WORK/t1.ck"
cp "$WORK/s.ck" "$WORK/t2.ck"
rec train4-k1 0 ollm train4 "$WORK/t1.ck" "$TR" 40 10 1
rec train4-k2 0 ollm train4 "$WORK/t2.ck" "$TR" 40 10 2
if cmp -s "$WORK/t1.ck" "$WORK/t2.ck"; then v=PASS; else v=FAIL; fail=1; fi
printf 'k-invariant\t-\t-\t%s\n' "$v" >> "$SUM"
rec kvck 0 ollm kvck "$WORK/t2.ck" "$HE"
# 4. checkpoint versions: CK04 refused (11), v3 eval refuses CK03 (11)
{ printf OLLMCK04; tail -c +9 "$WORK/s.ck"; } > "$WORK/bad4.ck"
rec ck04-eval4 11 ollm eval4 "$WORK/bad4.ck" "$HE" 2
rec ck04-train4 11 ollm train4 "$WORK/bad4.ck" "$TR" 1 1
rec ck03-v3eval 11 ollm eval "$WORK/s.ck" "$HE" 2
# 5. T = 2048 forward and train steps
rec init4-l 0 ollm init4 "$WORK/l.ck" 256 2048 128 4 512 2 1 7 10 1000 1
rec eval4-t2048 0 ollm eval4 "$WORK/l.ck" "$HE" 1
rec train4-t2048 0 ollm train4 "$WORK/l.ck" "$TR" 2 1 1
cat "$SUM"
rm -rf "$WORK"
exit $fail
