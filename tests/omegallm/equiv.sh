#!/bin/sh
# Show that two ollm builds compute the same thing from one checkpoint: the same held-out eval line,
# and a byte-identical checkpoint after N more training steps.
# Usage: sh tests/omegallm/equiv.sh OLD NEW CK TRAIN HELD N WORK > receipt
# Env: CORE (taskset core, default 7). CK is only read; both arms train copies of it inside WORK.
# Pass relative paths so the receipt names no private path. Exit 0 only if both comparisons agree.
set -u
[ $# -eq 7 ] || { echo "usage: equiv.sh OLD NEW CK TRAIN HELD N WORK" >&2; exit 2; }
OLD=$1 NEW=$2 CK=$3 TRAIN=$4 HELD=$5 N=$6 WORK=$7
RUN="taskset -c ${CORE:-7} nice -n 19"
mkdir -p "$WORK"
sha256sum "$OLD" "$NEW" "$CK" "$TRAIN" "$HELD"
fail=0
step=$(od -An -tu8 -j72 -N8 "$CK" | tr -d ' ')
until=$((step + N))
for arm in old new; do
	[ $arm = old ] && b=$OLD || b=$NEW
	cp "$CK" "$WORK/$arm.ck"
	echo "\$ $RUN $b eval $CK $HELD 256"
	$RUN "$b" eval "$CK" "$HELD" 256 > "$WORK/$arm.eval" 2>&1
	echo "rc=$? $(cat "$WORK/$arm.eval")"
	echo "\$ $RUN $b train $WORK/$arm.ck $TRAIN $until $N"
	$RUN "$b" train "$WORK/$arm.ck" "$TRAIN" "$until" "$N" > "$WORK/$arm.train" 2>&1
	echo "rc=$? $(cat "$WORK/$arm.train")"
done
if cmp "$WORK/old.eval" "$WORK/new.eval"; then echo "eval lines equal"; else echo "eval lines DIFFER"; fail=1; fi
if cmp "$WORK/old.ck" "$WORK/new.ck"; then
	echo "checkpoints after step $until equal: $(sha256sum < "$WORK/new.ck" | cut -d' ' -f1)"
else
	echo "checkpoints after step $until DIFFER"; fail=1
fi
if cmp -s "$CK" "$WORK/new.ck"; then echo "training did not change the checkpoint"; fail=1; fi
echo "verdict $([ $fail -eq 0 ] && echo EQUAL || echo DIFFERENT)"
exit $fail
