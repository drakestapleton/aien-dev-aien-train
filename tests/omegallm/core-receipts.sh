#!/bin/sh
# Produce the .om lane receipts for aien-train#52 under evidence/OMEGALLM/core/.
# Usage: sh tests/omegallm/core-receipts.sh
# Env: BUILD (dir with ollm, ollm-mut-a|b|c and ollm.om; default build beside this clone),
#      DATA (TinyStoriesV2-GPT4-valid.txt; default data/ beside it), WORK (scratch for checkpoints),
#      CORE (taskset core, default 6). Derived .bin files go beside DATA and are never committed.
# The script runs from the clone's parent directory and every path is relative to it, so the
# committed receipts name no absolute (private) paths. Give BUILD/DATA/WORK relative to that parent.
# Each receipt holds the exact command, stdout+stderr, exit code, wall seconds, and the sha256 of the
# binary and of its concatenated source. The script exits 1 if any check disagrees with its expectation.
set -u
here=$(cd "$(dirname "$0")/../.." && pwd)
cd "$here/.." || exit 70
r=$(basename "$here")
BUILD=${BUILD:-build}
DATA=${DATA:-data/TinyStoriesV2-GPT4-valid.txt}
WORK=${WORK:-scratch-core/work}
CORE=${CORE:-6}
E=$r/evidence/OMEGALLM/core
DD=$(dirname "$DATA")
TR=$DD/train.bin
HE=$DD/held.bin
RUN="taskset -c $CORE nice -n 19"
mkdir -p "$E" "$WORK"
fail=0
SUM=$E/summary.tsv
printf 'receipt\trc\texpect\tverdict\n' > "$SUM"

# rec NAME EXPECT_RC BIN ARGS... : run one command and write $E/NAME.txt
rec() {
	name=$1 want=$2 bin=$3
	shift 3
	f=$E/$name.txt
	{
		echo "receipt: $name"
		echo "host_cpu: core $CORE ($(lscpu -e=CPU,MODELNAME 2>/dev/null | awk -v c="$CORE" '$1==c {$1=""; print substr($0,2)}'))"
		echo "binary: $bin sha256 $(sha256sum "$BUILD/$bin" | cut -d' ' -f1)"
		echo "source: $bin.om sha256 $(sha256sum "$BUILD/$bin.om" | cut -d' ' -f1)"
		echo "\$ $RUN $BUILD/$bin $*"
		echo "--- output"
	} > "$f"
	t0=$(date +%s%N)
	$RUN "$BUILD/$bin" "$@" >> "$f" 2>&1
	rc=$?
	t1=$(date +%s%N)
	{
		echo "--- end"
		echo "rc=$rc expect=$want"
		echo "wall_ns=$((t1 - t0))"
	} >> "$f"
	v=PASS
	[ "$rc" = "$want" ] || { v=FAIL; fail=1; }
	printf '%s\t%s\t%s\t%s\n' "$name" "$rc" "$want" "$v" >> "$SUM"
	echo "$name rc=$rc expect=$want $v"
}

sha256sum "$DATA" > "$E/data-sha256.txt"

# 1. prep on the real data, then the derived file hashes
rec prep 0 ollm prep "$DATA" "$TR" "$HE"
sha256sum "$TR" "$HE" >> "$E/prep.txt"

# 2. baselines
rec base 0 ollm base "$TR" "$HE"

# 3. v0 init + 50 train steps (shapes of CONTRACT section 1)
rm -f "$WORK/v0.ck"
rec init-v0 0 ollm init "$WORK/v0.ck" 256 64 64 4 256 2 16 52 20000 3000
rec train-v0-50 0 ollm train "$WORK/v0.ck" "$TR" 50 5

# 4. resume equality: 0->40 straight vs 0->20 then ->40, compared with cmp
rm -f "$WORK/ra.ck" "$WORK/rb.ck"
rec resume-init-a 0 ollm init "$WORK/ra.ck" 256 64 64 4 256 2 16 52 20000 3000
rec resume-init-b 0 ollm init "$WORK/rb.ck" 256 64 64 4 256 2 16 52 20000 3000
rec resume-a-0-40 0 ollm train "$WORK/ra.ck" "$TR" 40 40
rec resume-b-0-20 0 ollm train "$WORK/rb.ck" "$TR" 20 20
rec resume-b-20-40 0 ollm train "$WORK/rb.ck" "$TR" 40 20
{
	echo "\$ cmp $WORK/ra.ck $WORK/rb.ck"
	cmp "$WORK/ra.ck" "$WORK/rb.ck"
	c=$?
	echo "rc=$c expect=0"
	sha256sum "$WORK/ra.ck" "$WORK/rb.ck"
} > "$E/resume-cmp.txt" 2>&1
grep -q '^rc=0 ' "$E/resume-cmp.txt" && v=PASS || { v=FAIL; fail=1; }
printf 'resume-cmp\t%s\t0\t%s\n' "$(sed -n 's/^rc=\([0-9]*\) .*/\1/p' "$E/resume-cmp.txt")" "$v" >> "$SUM"

# 5. checkpoint refusals (exit codes of CONTRACT section 7)
cp "$WORK/ra.ck" "$WORK/flip.ck"
printf '\377' | dd of="$WORK/flip.ck" bs=1 seek=5000 conv=notrunc 2>/dev/null
cmp -l "$WORK/ra.ck" "$WORK/flip.ck" > "$E/refuse-flip-diff.txt" 2>&1
rec refuse-flip-payload 14 ollm eval "$WORK/flip.ck" "$HE" 4
cp "$WORK/ra.ck" "$WORK/magic.ck"
printf 'X' | dd of="$WORK/magic.ck" bs=1 seek=0 conv=notrunc 2>/dev/null
rec refuse-flip-magic 11 ollm eval "$WORK/magic.ck" "$HE" 4
head -c $(($(stat -c %s "$WORK/ra.ck") - 1)) "$WORK/ra.ck" > "$WORK/trunc.ck"
rec refuse-truncated 10 ollm eval "$WORK/trunc.ck" "$HE" 4

# 6. eval and sample on the 50-step v0 checkpoint
rec eval-v0 0 ollm eval "$WORK/v0.ck" "$HE" 256
rec sample-v0-argmax 0 ollm sample "$WORK/v0.ck" 7 200 0 "Once upon a time"
rec sample-v0-t800 0 ollm sample "$WORK/v0.ck" 7 200 800 "Once upon a time"

# 7. self-checks: gradient check (small shape, fresh v0 init with seed 1, 50-step v0 checkpoint),
#    Adam check, exp/log check
rm -f "$WORK/s.ck"
rec init-small 0 ollm init "$WORK/s.ck" 256 8 16 2 32 2 2 52 200 1000
rec gcheck 0 ollm gcheck "$WORK/s.ck" "$TR"
rm -f "$WORK/g0.ck"
rec init-v0-g0 0 ollm init "$WORK/g0.ck" 256 64 64 4 256 2 16 1 20000 3000
rec gcheck-v0-init 0 ollm gcheck "$WORK/g0.ck" "$TR"
rec gcheck-v0-step50 0 ollm gcheck "$WORK/v0.ck" "$TR"
rec adamck 0 ollm adamck
rec mathck 0 ollm mathck "$r/tests/omegallm/mathref.txt"

# 8. mutants: a (dK sign) must fail gcheck; c (no bias correction) must fail adamck;
#    b (targets shifted) passes self-checks by construction and is killed by the oracle (xgrad).
rec mut-a-gcheck 40 ollm-mut-a gcheck "$WORK/s.ck" "$TR"
rec mut-a-gcheck-v0 40 ollm-mut-a gcheck "$WORK/g0.ck" "$TR"
rec mut-c-adamck 41 ollm-mut-c adamck
rec mut-b-gcheck 0 ollm-mut-b gcheck "$WORK/s.ck" "$TR"

echo "summary: $SUM"
exit $fail
