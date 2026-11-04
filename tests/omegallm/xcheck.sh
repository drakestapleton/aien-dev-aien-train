#!/bin/sh
# Run the oracle self-test and every cross-check against one `ollm` binary.
# Usage: tests/omegallm/xcheck.sh OLLM LABEL OUTDIR [v0]
#   DATA (env) = TinyStoriesV2-GPT4-valid.txt; WORK (env) = scratch dir for derived .bin files.
#   Paths are logged exactly as given; pass relative ones so committed receipts name no private paths.
#   The oracle's temporary checkpoints go under WORK/LABEL/tmp (OLLM_TMP) for the same reason.
#   CORE (env, default 8) = the taskset core every check runs on.
# Writes OUTDIR/LABEL/{CHECK.json,CHECK.log,summary.tsv}. Exit 0 only if every check passed.
set -u
BIN=$1 LABEL=$2 OUT=$3/$2 MODE=${4:-}
ORACLE="$(dirname "$0")/oracle.py"
: "${DATA:?set DATA to TinyStoriesV2-GPT4-valid.txt}" "${WORK:?set WORK to a scratch dir}"
RUN="taskset -c ${CORE:-8} nice -n 19"
export PYTHONDONTWRITEBYTECODE=1 OLLM_TMP="$WORK/$2/tmp"
mkdir -p "$OUT" "$WORK/$LABEL"
SUM="$OUT/summary.tsv"
printf 'check\trc\tcommand\n' > "$SUM"
fail=0
one() {
	name=$1; shift
	echo "\$ $RUN python3 $*" > "$OUT/$name.log"
	$RUN python3 "$@" >> "$OUT/$name.log" 2>&1
	rc=$?
	echo "rc=$rc" >> "$OUT/$name.log"
	printf '%s\t%s\t%s\n' "$name" "$rc" "$RUN python3 $*" >> "$SUM"
	[ "$rc" -eq 0 ] || fail=1
	echo "$name rc=$rc"
}
sha256sum "$BIN" "$ORACLE" "$DATA" > "$OUT/sha256.txt"
one selftest "$ORACLE" selftest
one xprep "$ORACLE" xprep --ollm "$BIN" --data "$DATA" --outdir "$WORK/$LABEL" --receipt "$OUT/xprep.json"
# Later checks use the oracle's own prep output so that a prep defect cannot mask a model defect.
TRAIN="$WORK/$LABEL/oracle-train.bin" HELD="$WORK/$LABEL/oracle-held.bin"
if [ ! -s "$TRAIN" ] || [ ! -s "$HELD" ]; then
	# record why every later check is about to fail, instead of leaving only their errors
	printf '%s\t%s\t%s\n' xprep-output 1 "missing $TRAIN or $HELD" >> "$SUM"
	fail=1
	echo "xprep-output missing $TRAIN or $HELD"
fi
head -c 65536 "$TRAIN" > "$WORK/$LABEL/train64k.bin"
one xbase "$ORACLE" xbase --ollm "$BIN" --train "$TRAIN" --held "$HELD" --receipt "$OUT/xbase.json"
one xinit "$ORACLE" xinit --ollm "$BIN" --receipt "$OUT/xinit.json"
one xgrad "$ORACLE" xgrad --ollm "$BIN" --data "$WORK/$LABEL/train64k.bin" --receipt "$OUT/xgrad.json"
one xstep "$ORACLE" xstep --ollm "$BIN" --data "$WORK/$LABEL/train64k.bin" --receipt "$OUT/xstep.json"
one xeval "$ORACLE" xeval --ollm "$BIN" --held "$HELD" --receipt "$OUT/xeval.json"
if [ "$MODE" = v0 ]; then
	one xinit-v0 "$ORACLE" xinit --cfg v0 --ollm "$BIN" --receipt "$OUT/xinit-v0.json"
	one xgrad-v0 "$ORACLE" xgrad --cfg v0 --ollm "$BIN" --data "$TRAIN" --receipt "$OUT/xgrad-v0.json"
	one xstep-v0 "$ORACLE" xstep --cfg v0 --ollm "$BIN" --data "$TRAIN" --receipt "$OUT/xstep-v0.json"
	one xeval-v0 "$ORACLE" xeval --cfg v0 --ollm "$BIN" --held "$HELD" --receipt "$OUT/xeval-v0.json"
fi
exit $fail
