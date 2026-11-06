#!/bin/sh
# run.sh ENDPOINT TASKFILE OUTDIR: run every harness task (TASKS.md) through Hermes against
# ENDPOINT and verify each outcome on disk with the independent verifier (verify.om).
# ENDPOINT is an OpenAI base URL http://HOST:PORT/v1 (a candidate server), or a protocol fixture
# that this script starts on FPORT for each task (scripted answers, never model output):
#   fixture:ref    turn 1 calls `terminal` with the task's @ref command, then answers "Done."
#   fixture:plain  every turn is a plain answer claiming success, no tool call (negative control)
# Per task, in OUTDIR/ID: prompt.txt, pre.txt (the check before Hermes runs: must FAIL, else the
# task is INVALID), hermes.{out,rc,ms} (stdout+stderr, exit status, wall ms), wire/ (every HTTP
# request head and exact body Hermes sent and every raw response, through a logging proxy on
# PPORT: req-N.head, req-N.body, resp-N.raw, chat.txt = "N status request_bytes" per chat POST),
# work/ (the work dir after the run), verify.txt (PASS/FAIL line). OUTDIR/summary.txt holds the
# environment, one row per task `ID FAMILY SPLIT RESULT rc ms chats first_status` and SUMMARY lines.
# Env: VERIFY (the verify binary, required), TOOLSETS (default terminal), TMO (per-task seconds,
# default 300), MAXTURNS (default 4), PPORT (default 18296), FPORT (default 18299), CORES
# (default 6), ONLY (space-separated task ids), WORKROOT (temp work dirs, default $TMPDIR),
# HARNESS_HOME (Hermes data root, see hermes1.sh).
# Exit 0 when every task ran (whatever its result), 2 on usage or a busy port.
set -u
here=$(cd "$(dirname "$0")" && pwd)
[ $# -eq 3 ] || { echo "usage: run.sh ENDPOINT TASKFILE OUTDIR" >&2; exit 2; }
ep=$1 tf=$2 out=$3
: "${VERIFY:?set VERIFY}"
ts=${TOOLSETS:-terminal}
tmo=${TMO:-300}
pport=${PPORT:-18296}
fport=${FPORT:-18299}
export CORES=${CORES:-6}
wroot=${WORKROOT:-${TMPDIR:-/tmp}}
mkdir -p "$out" "$wroot"
busy() { ss -Hltn "sport = :$1" | grep -q .; }
waitport() { i=0; until busy "$1"; do i=$((i + 1)); [ $i -gt 100 ] && return 1; sleep 0.1; done; }
case $ep in
fixture:ref | fixture:plain) mode=${ep#fixture:} host=127.0.0.1 port=$fport ;;
http://*/v1)
	mode=server
	hp=${ep#http://}
	hp=${hp%/v1}
	host=${hp%:*} port=${hp##*:} ;;
*) echo "run.sh: ENDPOINT must be http://HOST:PORT/v1, fixture:ref or fixture:plain" >&2; exit 2 ;;
esac
busy "$pport" && { echo "run.sh: proxy port $pport is busy" >&2; exit 2; }
[ "$mode" != server ] && busy "$fport" && { echo "run.sh: fixture port $fport is busy" >&2; exit 2; }
sum=$out/summary.txt
{
	echo "date $(date -u +%FT%TZ)"
	echo "endpoint $ep mode $mode toolsets $ts tmo $tmo maxturns ${MAXTURNS:-4} cores $CORES"
	echo "verify $(sha256sum "$VERIFY")"
	echo "tasks $(sha256sum "$tf")"
	echo "runner $(cat "$here"/run.sh "$here"/hermes1.sh "$here"/proxy1.sh "$here"/respond.sh "$here"/sse.sh | sha256sum | cut -d' ' -f1)"
	echo "hermes $(${HERMES_BIN:-$HOME/workspace/hermes-agent/.hermes/bin/hermes} --version 2>/dev/null | head -1)"
} >"$sum"
"$VERIFY" list "$tf" >"$out/tasks.list" || { echo "run.sh: verify list failed" >&2; exit 2; }
while read -r id fam sp; do
	if [ -n "${ONLY:-}" ]; then case " $ONLY " in *" $id "*) ;; *) continue ;; esac; fi
	d=$out/$id
	rm -rf "$d"
	mkdir -p "$d/wire"
	wd=$(mktemp -d "$wroot/hw-$id.XXXXXX")
	"$VERIFY" setup "$tf" "$id" "$wd" || { echo "$id $fam $sp SETUP_FAIL" >>"$sum"; continue; }
	"$VERIFY" check "$tf" "$id" "$wd" >"$d/pre.txt"
	prc=$?
	"$VERIFY" prompt "$tf" "$id" "$d/prompt.txt"
	fpid=
	if [ "$mode" != server ]; then
		f=$d/fixture
		mkdir -p "$f/script"
		if [ "$mode" = ref ]; then
			"$VERIFY" ref "$tf" "$id" "$f/ref.sh"
			sh "$here/sse.sh" call "$id" terminal "$(jq -Rsc '{command: .}' "$f/ref.sh")" >"$f/script/1.sse"
			sh "$here/sse.sh" text "$id-done" "Done." >"$f/script/default.sse"
		else
			sh "$here/sse.sh" text "$id-plain" "I have completed the task: the requested file is in place." >"$f/script/default.sse"
		fi
		taskset -c "$CORES" nice -n 10 socat TCP-LISTEN:"$fport",bind=127.0.0.1,reuseaddr,fork \
			EXEC:"sh $here/respond.sh $f" 2>/dev/null &
		fpid=$!
		waitport "$fport"
	fi
	taskset -c "$CORES" nice -n 10 socat TCP-LISTEN:"$pport",bind=127.0.0.1,reuseaddr,fork \
		EXEC:"sh $here/proxy1.sh $d/wire $host $port" 2>/dev/null &
	ppid_=$!
	waitport "$pport"
	sh "$here/hermes1.sh" "http://127.0.0.1:$pport/v1" "$wd" "$d/prompt.txt" "$ts" "$tmo" "$d/hermes"
	kill $ppid_ 2>/dev/null
	wait $ppid_ 2>/dev/null
	if [ -n "$fpid" ]; then kill $fpid 2>/dev/null; wait $fpid 2>/dev/null; fi
	"$VERIFY" check "$tf" "$id" "$wd" >"$d/verify.txt"
	vrc=$?
	cp -a "$wd" "$d/work"
	rm -rf "$wd"
	: >"$d/wire/chat.txt"
	for h in "$d"/wire/req-*.head; do
		[ -e "$h" ] || continue
		head -1 "$h" | grep -q '^POST .*/chat/completions' || continue
		n=${h##*/req-}
		n=${n%.head}
		st=$(head -1 "$d/wire/resp-$n.raw" 2>/dev/null | cut -d' ' -f2)
		echo "$n ${st:-none} $(wc -c <"$d/wire/req-$n.body")" >>"$d/wire/chat.txt"
	done
	nch=$(wc -l <"$d/wire/chat.txt")
	st1=$(sort -n "$d/wire/chat.txt" | head -1 | cut -d' ' -f2)
	res=FAIL
	[ $vrc -eq 0 ] && res=PASS
	[ $prc -eq 0 ] && res=INVALID
	echo "$id $fam $sp $res $(cat "$d/hermes.rc") $(cat "$d/hermes.ms") $nch ${st1:-none}" >>"$sum"
	echo "$id $fam $sp $res"
done <"$out/tasks.list"
awk '
NF == 8 && ($3 == "train" || $3 == "heldout" || $3 == "control") {
	n[$3]++; if ($4 == "PASS") p[$3]++; if ($4 == "INVALID") inv++
}
END {
	printf "SUMMARY train pass=%d/%d heldout pass=%d/%d control fail=%d/%d invalid=%d\n",
		p["train"], n["train"], p["heldout"], n["heldout"], n["control"] - p["control"], n["control"], inv
}' "$sum" | tee -a "$sum"
exit 0
