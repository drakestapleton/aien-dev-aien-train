#!/bin/sh
# tests/omegallm/v4-wide-check.sh: receipts of the v4 wte banks (docs/omegallm/CONTRACT-V4.md section 2).
# Run from anywhere: sh tests/omegallm/v4-wide-check.sh. Env: OMC (pinned omc), BUILD, WORK, CORES
# (taskset list, default 6), EV (evidence dir), OLD (the commit before the banks, default 63353c9,
# whose binaries write the reference checkpoints and outputs). Training text is this repository's
# own .om sources and docs at OLD (first-party), split into stories every 40 lines; the V 32768 receipts
# use the same bytes as u16 tokens.
here=$(cd "$(dirname "$0")/../.." && pwd)
cd "$here" || exit 70
# C collation: the file order of the training text (and so its story splits) must not depend on the locale
export LC_ALL=C
BUILD=${BUILD:-scratch-v4w/build}
WORK=${WORK:-scratch-v4w/work}
CORES=${CORES:-6}
OLD=${OLD:-63353c9}
E=${EV:-evidence/OMEGALLM/v4/wide}
RUN="taskset -c $CORES nice -n 10"
mkdir -p "$E" "$WORK" "$BUILD/old"
# receipts print BUILD and WORK as given (pass relative paths so they name no private path)

: > "$E/build.txt"
for a in "" "--variant wx" "--mutant j" "--mutant jd"; do
	# shellcheck disable=SC2086
	OUT=$BUILD CORE=${CORES%%[-,]*} sh tests/omegallm/build.sh $a >> "$E/build.txt" 2>&1 || {
		echo "BUILD_FAIL $a" | tee -a "$E/build.txt"
		exit 1
	}
done
# the reference: the same build script and sources at $OLD (wte in the one window ow)
rm -rf "$WORK/oldsrc"
mkdir -p "$WORK/oldsrc"
git archive "$OLD" native/omegallm docs/omegallm tests/omegallm/build.sh | tar -x -C "$WORK/oldsrc" || exit 70
OUT=$BUILD/old CORE=${CORES%%[-,]*} sh "$WORK/oldsrc/tests/omegallm/build.sh" >> "$E/build.txt" 2>&1 || {
	echo "BUILD_FAIL old" | tee -a "$E/build.txt"
	exit 1
}
echo "old source: $OLD $(git rev-parse "$OLD")" >> "$E/build.txt"
cat "$E/build.txt"
# the training text is $OLD's sources and docs, so it does not change with later commits (gcheck4's
# worst coordinate depends on the text: evidence/OMEGALLM/v4/wide/gcheck-textdep.txt)
( cd "$WORK/oldsrc" && cat native/omegallm/*.om docs/omegallm/*.md ) | awk '{print} NR%40==0 {print "<|endoftext|>"}' > "$WORK/in.txt"
TR=$WORK/train.bin
HE=$WORK/held.bin
SUM=$E/summary.tsv
printf 'receipt\trc\texpect\tverdict\n' > "$SUM"
fail=0
# rec NAME EXPECT_RC BIN ARGS... : run one command, write $E/NAME.txt (stdout in $WORK/NAME.out too)
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
	$RUN "$BUILD/$bin" "$@" > "$WORK/$name.out" 2>&1
	rc=$?
	t1=$(date +%s%N)
	head -c 4000 "$WORK/$name.out" >> "$f"
	echo "--- rc $rc ms $(( (t1 - t0) / 1000000 ))" >> "$f"
	v=PASS
	[ "$rc" = "$want" ] || { v=FAIL; fail=1; }
	printf '%s\t%s\t%s\t%s\n' "$name" "$rc" "$want" "$v" >> "$SUM"
}
# same NAME A B: files A and B byte-identical
same() {
	if cmp -s "$2" "$3"; then v=PASS; else v=FAIL; fail=1; fi
	printf '%s\t-\t-\t%s\n' "$1" "$v" >> "$SUM"
	echo "$1: cmp $2 $3 -> $v" >> "$E/same.txt"
}
: > "$E/same.txt"
rec prep 0 ollm prep "$WORK/in.txt" "$TR" "$HE"
# u16 copies of the byte tokens for the V 32768 receipts
for f in train held; do
	od -An -v -tu1 "$WORK/$f.bin" | LC_ALL=C awk '{for (i = 1; i <= NF; i++) printf "%c%c", $i, 0}' > "$WORK/$f.u16"
done
# 1. a CK03 written by the one-window build loads and gives identical outputs; training from it
#    gives a byte-identical checkpoint
rec old-init4 0 old/ollm init4 "$WORK/o.ck" 256 64 16 2 32 2 4 1 100 1000 2
rec old-train4 0 old/ollm train4 "$WORK/o.ck" "$TR" 3 3 1
rec new-init4 0 ollm init4 "$WORK/n.ck" 256 64 16 2 32 2 4 1 100 1000 2
rec new-train4 0 ollm train4 "$WORK/n.ck" "$TR" 3 3 1
same ck03-init-train-identical "$WORK/o.ck" "$WORK/n.ck"
for c in eval4 gcheck4 kvck sample4; do
	case $c in
		eval4) a="$HE 4" ;;
		gcheck4) a=$TR ;;
		kvck) a=$HE ;;
		sample4) a="7 40 800 fn" ;;
	esac
	# shellcheck disable=SC2086
	rec old-$c 0 old/ollm $c "$WORK/o.ck" $a
	# shellcheck disable=SC2086
	rec new-$c 0 ollm $c "$WORK/o.ck" $a
	same ck03-$c-identical "$WORK/old-$c.out" "$WORK/new-$c.out"
done
cp "$WORK/o.ck" "$WORK/o2.ck"
rec old-train4-more 0 old/ollm train4 "$WORK/o.ck" "$TR" 6 6 2
rec new-train4-more 0 ollm train4 "$WORK/o2.ck" "$TR" 6 6 2
same ck03-continue-identical "$WORK/o.ck" "$WORK/o2.ck"
# 2. the bank crossing: variant wx (XWB1 2000: R1 = 111 of 256 rows, layers and activations staged)
rec x-init4 0 ollm init4 "$WORK/x.ck" 256 32 18 3 32 4 4 3 100 1000 2
rec wx-gcheck4 0 ollm-var-wx gcheck4 "$WORK/x.ck" "$TR"
# (the old build holds this shape in one window: no staging, no banks; the bits must agree)
rec old-gcheck4-x 0 old/ollm gcheck4 "$WORK/x.ck" "$TR"
same wx-gcheck4-eq-old "$WORK/wx-gcheck4.out" "$WORK/old-gcheck4-x.out"
rec mut-j-gcheck4 40 ollm-mut-j gcheck4 "$WORK/x.ck" "$TR"
for k in 1 2; do
	cp "$WORK/x.ck" "$WORK/x$k.ck"
	rec wx-train4-k$k 0 ollm-var-wx train4 "$WORK/x$k.ck" "$TR" 6 3 $k
done
same wx-k1-eq-k2 "$WORK/x1.ck" "$WORK/x2.ck"
cp "$WORK/x.ck" "$WORK/xo.ck"
rec old-train4-x 0 old/ollm train4 "$WORK/xo.ck" "$TR" 6 3 2
same wx-train-eq-old "$WORK/x1.ck" "$WORK/xo.ck"
rec wx-kvck 0 ollm-var-wx kvck "$WORK/x2.ck" "$HE"
rec mut-jd-kvck 44 ollm-mut-jd kvck "$WORK/x2.ck" "$HE"
rec wx-eval4 0 ollm-var-wx eval4 "$WORK/x2.ck" "$HE" 3
rec old-eval4-x 0 old/ollm eval4 "$WORK/x2.ck" "$HE" 3
same wx-eval4-eq-old "$WORK/wx-eval4.out" "$WORK/old-eval4-x.out"
# 3. V 32768 at the S1 width (D 512, H 8, F 2048) on L 2: R1 = 27660 rows, so the product build
#    crosses the banks; kvck bit-exact; K = 1 and K = 2 identical
rec w-init4 0 ollm init4 "$WORK/w.ck" 32768 32 512 8 2048 2 2 5 100 1000 2
cp "$WORK/w.ck" "$WORK/w2.ck"
rec w-train4-k1 0 ollm train4 "$WORK/w.ck" "$WORK/train.u16" 1 1 1
rec w-train4-k2 0 ollm train4 "$WORK/w2.ck" "$WORK/train.u16" 1 1 2
same w-k1-eq-k2 "$WORK/w.ck" "$WORK/w2.ck"
rec w-kvck 0 ollm kvck "$WORK/w.ck" "$WORK/held.u16"
rec w-eval4-tok 0 ollm eval4 "$WORK/w.ck" "$WORK/held.u16" 2
head -c 16 "$WORK/held.u16" > "$WORK/p.u16"
rec w-sample4-tok 0 ollm sample4 "$WORK/w.ck" 3 8 0 "$WORK/p.u16"
rm -f "$WORK/w.ck" "$WORK/w2.ck"
# 4. D 768 at V 32768 on the product build (R1 = 18440 of 32768 rows): seed 17 puts two of
#    gcheck4's four wte coordinates in bank 1 and two in bank 2 (14906211 and 15863246 >= R1 D)
rec d768-init4 0 ollm init4 "$WORK/d.ck" 32768 8 768 12 3072 1 2 17 100 1000 2
rec d768-gcheck4 0 ollm gcheck4 "$WORK/d.ck" "$WORK/train.u16"
cp "$WORK/d.ck" "$WORK/d2.ck"
rec d768-train4-k1 0 ollm train4 "$WORK/d.ck" "$WORK/train.u16" 1 1 1
rec d768-train4-k2 0 ollm train4 "$WORK/d2.ck" "$WORK/train.u16" 1 1 2
same d768-k1-eq-k2 "$WORK/d.ck" "$WORK/d2.ck"
rec d768-kvck 0 ollm kvck "$WORK/d.ck" "$WORK/held.u16"
rec d768-sample4-tok 0 ollm sample4 "$WORK/d.ck" 3 4 0 "$WORK/p.u16"
rec d768-tune4 0 ollm tune4 "$WORK/d.ck" "$WORK/dt.ck" 10 100
rm -f "$WORK/d.ck" "$WORK/d2.ck" "$WORK/dt.ck"
# 5. limits: V D past the banks refused (12)
rec d1024-init4 12 ollm init4 "$WORK/e.ck" 32768 64 1024 16 4096 1 1 1 10 1000 1
rec v65536-d512-init4 12 ollm init4 "$WORK/e.ck" 65536 64 512 8 2048 1 1 1 10 1000 1
cat "$SUM"
rm -rf "$WORK"
exit $fail
