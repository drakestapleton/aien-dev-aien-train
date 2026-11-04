#!/bin/sh
# Produce the .om lane receipts for aien-train#52 under evidence/OMEGALLM/core/.
# Usage: sh tests/omegallm/core-receipts.sh
# Env: BUILD (output dir for ollm, ollm-mut-a|b|c, ollm-var-h5|h7 and their .om; default build beside
#      this clone), DATA (TinyStoriesV2-GPT4-valid.txt; default data/ beside it), WORK (scratch for
#      checkpoints), CORE (taskset core, default 6). Derived .bin files go beside DATA and are never
#      committed.
#      TARGET (aarch64, the default, or x86linux; passed to build.sh) and EV (receipt directory,
#      default evidence/OMEGALLM/core in this clone). An x86linux run executes the x86-64 ELFs through
#      the host's qemu-x86_64 binfmt handler; each receipt then names the emulator (EMULATED, not a
#      physical x86 run). The pinned value lines are the same for both targets.
# The script runs from the clone's parent directory and every path is relative to it, so the
# committed receipts name no absolute (private) paths. Give BUILD/DATA/WORK relative to that parent.
# Step 0 builds every binary from this tree with tests/omegallm/build.sh, so the receipts always
# describe the committed source. Each receipt holds the exact command, stdout+stderr, exit code, wall
# time, and the sha256 of the binary and of its concatenated source. Exit codes are checked for every
# command; the deterministic value lines the oracle also checks (P, B, I, T 50, E) are pinned with
# `want`. The script exits 1 if any check disagrees with its expectation.
set -u
here=$(cd "$(dirname "$0")/../.." && pwd)
cd "$here/.." || exit 70
r=$(basename "$here")
BUILD=${BUILD:-build}
DATA=${DATA:-data/TinyStoriesV2-GPT4-valid.txt}
WORK=${WORK:-scratch-core/work}
CORE=${CORE:-6}
TARGET=${TARGET:-aarch64}
E=${EV:-$r/evidence/OMEGALLM/core}
EMUL=
if [ "$TARGET" = x86linux ]; then
	EMUL="x86linux EMULATED: $(qemu-x86_64 --version | head -n 1), binfmt $(sed -n 's/^flags: /flags /p' /proc/sys/fs/binfmt_misc/qemu-x86_64)"
fi
DD=$(dirname "$DATA")
TR=$DD/train.bin
HE=$DD/held.bin
RUN="taskset -c $CORE nice -n 19"
mkdir -p "$E" "$WORK"

# 0. build from this tree (build.sh refuses an omc that is not the pinned one)
: > "$E/build.txt"
for a in "" "--mutant a" "--mutant b" "--mutant c" "--variant h5" "--variant h7"; do
	# shellcheck disable=SC2086
	OUT=$BUILD CORE=$CORE TARGET=$TARGET sh "$r/tests/omegallm/build.sh" $a >> "$E/build.txt" 2>&1 || {
		echo "BUILD_FAIL $a" | tee -a "$E/build.txt"
		exit 1
	}
done
cat "$E/build.txt"
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
		[ -z "$EMUL" ] || echo "target: $EMUL"
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

# want NAME LINE : the receipt NAME.txt must contain LINE exactly (a pinned deterministic value)
want() {
	v=PASS
	grep -qxF "$2" "$E/$1.txt" || { v=FAIL; fail=1; }
	printf '%s\t%s\t%s\t%s\n' "$1:value" "-" "$2" "$v" >> "$SUM"
	echo "$1 value '$2' $v"
}

sha256sum "$DATA" > "$E/data-sha256.txt"
# the core's identification register (0x410fd851: Arm, part 0xd85 Cortex-X925) and its maximum clock
{
	echo "core $CORE midr_el1 $(cat /sys/devices/system/cpu/cpu$CORE/regs/identification/midr_el1)"
	echo "core $CORE cpuinfo_max_freq_khz $(cat /sys/devices/system/cpu/cpu$CORE/cpufreq/cpuinfo_max_freq)"
	lscpu -e=CPU,MODELNAME,MAXMHZ 2>/dev/null | awk -v c="$CORE" 'NR==1 || $1==c'
	[ -z "$EMUL" ] || echo "target: $EMUL"
} > "$E/host.txt"

# 1. prep on the real data, then the derived file hashes
rec prep 0 ollm prep "$DATA" "$TR" "$HE"
sha256sum "$TR" "$HE" >> "$E/prep.txt"
want prep "P 27630 24867 2763 19883834 2220914"

# 2. baselines
rec base 0 ollm base "$TR" "$HE"
want base "B 4415645 3295113"

# 3. v0 init + 50 train steps (shapes of CONTRACT section 1)
rm -f "$WORK/v0.ck"
rec init-v0 0 ollm init "$WORK/v0.ck" 256 64 64 4 256 2 16 52 20000 3000
want init-v0 "I 119104"
rec train-v0-50 0 ollm train "$WORK/v0.ck" "$TR" 50 5
want train-v0-50 "T 50 3110411"

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
# D (header offset 24, low byte 0x40) set to 0: a zero shape
cp "$WORK/ra.ck" "$WORK/shape.ck"
printf '\000' | dd of="$WORK/shape.ck" bs=1 seek=24 conv=notrunc 2>/dev/null
rec refuse-shape 12 ollm eval "$WORK/shape.ck" "$HE" 4
# P (header offset 96, 119104 = 0x1D140, low byte 0x40) set to 0x41: P disagrees with the shapes
cp "$WORK/ra.ck" "$WORK/count.ck"
printf '\101' | dd of="$WORK/count.ck" bs=1 seek=96 conv=notrunc 2>/dev/null
rec refuse-count 13 ollm eval "$WORK/count.ck" "$HE" 4
# one byte appended: longer than 112 + 24 P
cp "$WORK/ra.ck" "$WORK/long.ck"
printf '\000' >> "$WORK/long.ck"
rec refuse-long 15 ollm eval "$WORK/long.ck" "$HE" 4

# 5b. the largest shape (CONTRACT section 1 maxima) round-trips: file 112 + 24 P_max bytes
rm -f "$WORK/max.ck"
rec init-max 0 ollm init "$WORK/max.ck" 256 64 64 8 256 4 16 1 100 3000
want init-max "I 217664"
stat -c '%s %n' "$WORK/max.ck" >> "$E/init-max.txt"
rec eval-max 0 ollm eval "$WORK/max.ck" "$HE" 2

# 5c. data-range refusals that a wrapping u64 sum would let through: W = 2^58 windows (W T wraps to
#     0 at T 64) and 16 offsets of 2^64 - 1 (o + T wraps)
rec refuse-eval-hugew 23 ollm eval "$WORK/ra.ck" "$HE" 288230376151711744
head -c 128 /dev/zero | tr '\000' '\377' > "$WORK/offs-huge.bin"
rec refuse-grad-hugeoff 22 ollm grad "$WORK/ra.ck" "$TR" "$WORK/offs-huge.bin" "$WORK/huge.gr"

# 5d. the exact boundaries of the same two checks, on 193-byte slices (T = 64):
#     eval accepts W = floor((193 - 1) / 64) = 3 and refuses W = 4 with 23;
#     grad accepts o = 193 - 64 - 1 = 128 (window o..o+T ends on the last byte) and refuses 129 with
#     22. The refusing offset file holds fifteen offsets 128 and one 129, so the last row decides.
head -c 193 "$HE" > "$WORK/held-193.bin"
head -c 193 "$TR" > "$WORK/train-193.bin"
rec eval-edge-w3 0 ollm eval "$WORK/ra.ck" "$WORK/held-193.bin" 3
rec refuse-eval-edge-w4 23 ollm eval "$WORK/ra.ck" "$WORK/held-193.bin" 4
: > "$WORK/offs-128.bin"
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do printf '\200\0\0\0\0\0\0\0' >> "$WORK/offs-128.bin"; done
head -c 120 "$WORK/offs-128.bin" > "$WORK/offs-129.bin"
printf '\201\0\0\0\0\0\0\0' >> "$WORK/offs-129.bin"
rec grad-edge-o128 0 ollm grad "$WORK/ra.ck" "$WORK/train-193.bin" "$WORK/offs-128.bin" "$WORK/e128.gr"
rec refuse-grad-edge-o129 22 ollm grad "$WORK/ra.ck" "$WORK/train-193.bin" "$WORK/offs-129.bin" "$WORK/e129.gr"

# 6. eval and sample on the 50-step v0 checkpoint
rec eval-v0 0 ollm eval "$WORK/v0.ck" "$HE" 256
want eval-v0 "E 50 256 3049318 4399237"
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

# 9. gcheck step-size variants (README, "Self-check constants"): with the correct gradient, h = 1e-5
#    (ReLU kinks) and h = 1e-7 (roundoff) both exceed GCTOL at v0, which is why GCH is 1e-6 with
#    the 2.5e-7 retry. Each `c index g_e12 num_e12` line gives the hand gradient and the difference.
rec var-h5-gcheck-v0-init 40 ollm-var-h5 gcheck "$WORK/g0.ck" "$TR"
rec var-h5-gcheck-v0-step50 40 ollm-var-h5 gcheck "$WORK/v0.ck" "$TR"
rec var-h7-gcheck-v0-init 40 ollm-var-h7 gcheck "$WORK/g0.ck" "$TR"
rec var-h7-gcheck-v0-step50 40 ollm-var-h7 gcheck "$WORK/v0.ck" "$TR"

echo "summary: $SUM"
exit $fail
