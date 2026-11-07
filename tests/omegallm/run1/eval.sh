#!/bin/sh
# tests/omegallm/run1/eval.sh CK STAGE OUTDIR: the run1 evaluation pipeline for one OLLMCK03 checkpoint
# (STAGE A or B). Every step, its pass rule and its receipt: tests/omegallm/run1/EVAL.md (normative).
#   0 build    ollm, verify, sftgen, accept, mancheck from this checkout with the pinned omc
#   1 identity sha256 of CK, merges, binaries; CK03 header (mancheck id); provenance in run1 geval.txt;
#              negative control: one flipped payload byte must be refused
#   2 xcheck   tune4 copy at T 1024 B 16 G 1 (params byte-identical), CPU eval4 W 64 on base-val; prints the
#              chip geval4 command for the lead (this script never touches the GPU); CHIP_E compares
#   3 serve    ollm serve PORT SCK MERGES par=2 on CORES (SCK = CK, or a tune4 copy at SERVE_T when CK's T
#              differs, params unchanged), /health identity, 3 plain + 2 tool-declared requests, 1 refused
#   4 harness  (a) new train-family instances from `sftgen TRAINSEED` (none equal to a seed 20261107/99 task)
#              (b) the held-out families of tasks.txt, plus controls c01 c02; verify.om verdict per task
#   5 accept   DRA-124 tests/omegallm/accept/run.sh against the endpoint; transcripts stay in the 0700 area
#   6 demo     one Hermes oneshot creating a file holding Drake's public words, verified on disk by verify.om
#   7 stop     stops what this script started; prints the summary block
# Env: OMC (pinned omc, required), MERGES (default ~/work/hive/ownmodel/data/merges32k.bin), DATA (default
#   ~/work/hive/ownmodel/data), RUN1 (default ~/work/hive/ownmodel/run1, read-only), CORES (default 4,6),
#   PORT (server, default 18296), PPORT (harness proxy, default 18298), STEPS (default "1 2 3 4 5 6"; 0 and 7
#   always run; 4-6 start the server when 3 is not listed), DRY (1: dry-run subsets, every receipt labelled
#   "DRY-RUN STAGE-x (not the candidate)"), WORK (large scratch: tune4 copies, default
#   ~/work/hive/ownmodel/evalprep/work), HARNESS_HOME (Hermes data root, default
#   ~/work/hive/ownmodel/evalprep/hh), AOUT (accept OUTDIR, default ~/work/hive/ownmodel/accept/runs/NAME,
#   must sit under a 0700 dir), TRAINSEED (default 20261109), TRAINN (default 30), SERVE_T (default 4096),
#   TMO (Hermes per-task seconds, default 300), XW (eval4/geval4 windows, default 64 = PREREG; smaller only
#   for a code-path check), CHIP_E (the chip geval4 E line, to compare in step 2),
#   ACCEPT_ENV (extra env words for step 5, e.g. "REPEATS=0").
# Exit 0 when every step that ran met its pass rule (capability results are reported, never a pass rule).
set -u
[ $# -eq 3 ] || { echo "usage: eval.sh CK STAGE OUTDIR" >&2; exit 2; }
CK=$(readlink -f "$1") STAGE=$2 OUT=$3
case $STAGE in A | B) ;; *) echo "eval.sh: STAGE must be A or B" >&2; exit 2 ;; esac
: "${OMC:?set OMC to the pinned omc}"
[ -r "$CK" ] || { echo "eval.sh: no CK $CK" >&2; exit 2; }
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../.." && pwd)
H=$repo/tests/omegallm/harness
DATA=${DATA:-$HOME/work/hive/ownmodel/data}
MERGES=$(readlink -f "${MERGES:-$DATA/merges32k.bin}")
RUN1=${RUN1:-$HOME/work/hive/ownmodel/run1}
CORES=${CORES:-4,6}
c1=${CORES%%[,-]*}
PORT=${PORT:-18296} PPORT=${PPORT:-18298}
STEPS=${STEPS:-1 2 3 4 5 6}
DRY=${DRY:-0}
SERVE_T=${SERVE_T:-4096}
XW=${XW:-64}
TRAINSEED=${TRAINSEED:-20261109} TRAINN=${TRAINN:-30}
WORK=${WORK:-$HOME/work/hive/ownmodel/evalprep/work}
HARNESS_HOME=${HARNESS_HOME:-$HOME/work/hive/ownmodel/evalprep/hh}
export HARNESS_HOME
mkdir -p "$OUT" "$WORK" "$HARNESS_HOME"
OUT=$(cd "$OUT" && pwd)
ck8=$(sha256sum "$CK" | cut -c1-8)
NAME=run1-$STAGE-$ck8-$(date -u +%Y%m%dT%H%M%SZ)
AOUT=${AOUT:-$HOME/work/hive/ownmodel/accept/runs/$NAME}
if [ "$DRY" = 1 ]; then LABEL="DRY-RUN STAGE-$STAGE (not the candidate)"; else LABEL="RUN1 STAGE-$STAGE CANDIDATE EVALUATION"; fi
B=$OUT/bin
SUM=$OUT/summary.txt
echo "$LABEL" >"$OUT/LABEL"
{ echo "LABEL $LABEL"; echo "script $(sha256sum "$0" | cut -c1-64) commit $(git -C "$repo" rev-parse HEAD)"; echo "start $(date -u +%FT%TZ) ck $CK stage $STAGE steps $STEPS dry $DRY cores $CORES port $PORT pport $PPORT"; } >"$SUM"
now() { date +%s%N; }
secs() { echo $((($(now) - $1) / 1000000)); }
# rec STEP NAME RESULT MS DETAIL: one summary row
rec() { echo "STEP $1 $2 $3 ms=$4 $5" | tee -a "$SUM"; }
want() { case " $STEPS " in *" $1 "*) return 0 ;; esac; return 1; }
run() { taskset -c "$CORES" nice -n 10 "$@"; }
FAILS=0
spid=
wpids=
# whatever ends this script, the server it started stops (step 7 does it in order)
cleanup() { [ -n "$spid" ] && kill "$spid" $wpids 2>/dev/null; }
trap cleanup EXIT
trap 'exit 130' INT TERM

# ---- 0 build
t=$(now)
mkdir -p "$B"
r=PASS
{
	OMC=$OMC OUT=$B CORE=$c1 sh "$repo/tests/omegallm/build.sh" &&
		OMC=$OMC OUT=$B CORES=$c1 sh "$H/build.sh" &&
		OMC=$OMC OUT=$B CORE=$c1 sh "$repo/tests/omegallm/accept/build.sh" &&
		taskset -c "$c1" nice -n 10 "$OMC" <"$repo/tests/omegallm/deploy/mancheck.om" >"$B/mancheck.part" &&
		chmod 755 "$B/mancheck.part" && mv "$B/mancheck.part" "$B/mancheck"
} >"$OUT/build.txt" 2>&1 || r=FAIL
rec 0 build $r "$(secs "$t")" "ollm=$(sha256sum "$B/ollm" 2>/dev/null | cut -c1-16)"
[ $r = PASS ] || { echo "eval.sh: build failed (build.txt)" >&2; exit 1; }
O=$B/ollm

# ckid FILE: the mancheck `ck` line of FILE (header fields recomputed)
ckid() {
	idd=$(mktemp -d "$WORK/id.XXXXXX")
	ln -s "$1" "$idd/ck" && ln -s "$MERGES" "$idd/tok"
	taskset -c "$c1" nice -n 10 "$B/mancheck" id "$idd" ck tok
	x=$?
	rm -rf "$idd"
	return $x
}

# ---- 1 identity
if want 1; then
	t=$(now)
	d=$OUT/step1
	mkdir -p "$d"
	r=PASS
	{
		echo "LABEL $LABEL"
		echo "date $(date -u +%FT%TZ) host $(hostname) $(uname -m)"
		echo "commit $(git -C "$repo" rev-parse HEAD) dirty $(git -C "$repo" status --porcelain -- native tests/omegallm docs | wc -l)"
		for f in "$CK" "$MERGES" "$OMC" "$B/ollm" "$B/verify" "$B/sftgen" "$B/accept" "$B/mancheck"; do echo "sha256 $(sha256sum "$f")"; done
	} >"$d/identity.txt"
	ckid "$CK" >"$d/mancheck-id.txt" 2>&1 || r=FAIL
	cat "$d/mancheck-id.txt" >>"$d/identity.txt"
	set -- $(grep '^ck ' "$d/mancheck-id.txt")
	[ "${2:-}" = OLLMCK03 ] || r=FAIL
	tv=$(grep '^tok ' "$d/mancheck-id.txt" | cut -d' ' -f3)
	[ "${3:-x}" = "${tv:-y}" ] || r=FAIL
	sha=$(sha256sum "$CK" | cut -c1-64)
	prov=$(grep "ck=$sha" "$RUN1/geval.txt" 2>/dev/null | head -1)
	echo "provenance ${prov:-NONE}" >>"$d/identity.txt"
	case $prov in *"stage=$STAGE ck=$sha") ;; *) r=FAIL ;; esac
	# negative control: one flipped payload byte (offset 128 + 8*1000) must be refused by mancheck id
	n=$WORK/neg-$ck8.ck
	cp "$CK" "$n" && chmod u+w "$n"
	printf '\377' | dd of="$n" bs=1 seek=8128 conv=notrunc status=none
	if ckid "$n" >"$d/neg-flip.txt" 2>&1; then r=FAIL; echo "neg_flip ACCEPTED (control failed)"; else echo "neg_flip refused rc=$? $(cat "$d/neg-flip.txt")"; fi >>"$d/identity.txt"
	rm -f "$n"
	rec 1 identity $r "$(secs "$t")" "$(grep '^ck ' "$d/mancheck-id.txt") ${prov:-no-provenance}"
	[ $r = PASS ] || FAILS=$((FAILS + 1))
fi

# params region of a CK03 (bytes after the 128-byte header, 8 P bytes); P is field 11 of the ck line
pbytes() { echo $(($(ckid "$1" | grep '^ck ' | cut -d' ' -f11) * 8)); }

# ---- 2 xcheck
if want 2; then
	t=$(now)
	d=$OUT/step2
	mkdir -p "$d"
	r=PASS
	X=$WORK/x1024-$ck8.ck
	echo "LABEL $LABEL" >"$d/xcheck.txt"
	run "$O" tune4 "$CK" "$X" 24000 3000 1024 16 1 >"$d/tune4.txt" 2>&1
	x=$?
	[ $x -eq 0 ] || r=FAIL
	echo "tune4 $CK -> $X T 1024 B 16 G 1 rc=$x $(cat "$d/tune4.txt")" >>"$d/xcheck.txt"
	pb=$(pbytes "$CK")
	if cmp -s -i 128 -n "$pb" "$CK" "$X"; then echo "params identical ($pb bytes after the header)"; else r=FAIL; echo "params DIFFER"; fi >>"$d/xcheck.txt"
	# negative control of the comparison: the same files offset by one value must differ
	if cmp -s -i 128:136 -n "$pb" "$CK" "$X"; then r=FAIL; echo "neg_shift EQUAL (control failed)"; else echo "neg_shift differs (control ok)"; fi >>"$d/xcheck.txt"
	echo "x1024 $(sha256sum "$X") $(ckid "$X" | grep '^ck ')" >>"$d/xcheck.txt"
	t2=$(now)
	run "$O" eval4 "$X" "$DATA/base-val.u16" "$XW" >"$d/eval4.txt" 2>&1
	x=$?
	[ $x -eq 0 ] || r=FAIL
	echo "cpu_eval4 W $XW rc=$x ms=$(secs "$t2") ollm $(sha256sum "$O" | cut -c1-64)" >>"$d/xcheck.txt"
	E=$(grep '^E ' "$d/eval4.txt")
	echo "CPU_E $E" >>"$d/xcheck.txt"
	G=$RUN1/bin/ollm-gb10
	cat >"$d/chip-command.txt" <<EOF
# chip geval4 of the same retimed copy (the lead runs this inside a lease; this script never uses the GPU)
flock ~/handoffs/BOARD.md.lock sh -c 'echo "\$(date -u +%FT%TZ) ownmodel STARTING WINDOW run1-xchk-$ck8 (geval4 W $XW of $X, ~3 min)" >> ~/handoffs/BOARD.md'
spark-window open run1-xchk-$ck8 --ledger L904 --lease 20 --gb10 exclusive --quiet none --wait
spark-window run $G geval4 $X $DATA/base-val.u16 $XW > $d/geval4-chip.txt 2>&1
spark-window close
flock ~/handoffs/BOARD.md.lock sh -c 'echo "\$(date -u +%FT%TZ) ownmodel DONE WINDOW run1-xchk-$ck8 ID (rc RC)" >> ~/handoffs/BOARD.md'
# then: CHIP_E="\$(grep '^E ' $d/geval4-chip.txt)" STEPS=2 OMC=... sh $here/eval.sh $CK $STAGE $OUT
#   (ollm-gb10 $(sha256sum "$G" 2>/dev/null | cut -c1-64))
EOF
	if [ -z "$E" ]; then
		r=FAIL
	elif [ -n "${CHIP_E:-}" ]; then
		if [ "$CHIP_E" = "$E" ]; then echo "CHIP_E $CHIP_E EQUAL"; else r=FAIL; echo "CHIP_E $CHIP_E DIFFERS"; fi >>"$d/xcheck.txt"
	else
		[ $r = PASS ] && r=PENDING_CHIP
	fi
	echo "== chip geval4 command (lead, inside a lease):"
	cat "$d/chip-command.txt"
	rec 2 xcheck $r "$(secs "$t")" "$E"
	[ $r = FAIL ] && FAILS=$((FAILS + 1))
fi

# ---- 3 serve
listen_pid() { ss -Hltnp "sport = :$1" 2>/dev/null | grep -o 'pid=[0-9]*' | head -1 | cut -d= -f2; }
start_server() {
	d=$OUT/step3
	mkdir -p "$d"
	SCK=$CK
	st=$(ckid "$CK" | grep '^ck ' | cut -d' ' -f4)
	if [ "$st" != "$SERVE_T" ]; then
		SCK=$WORK/serve-t$SERVE_T-$ck8.ck
		run "$O" tune4 "$CK" "$SCK" 7300 1000 "$SERVE_T" 4 1 >"$d/tune4-serve.txt" 2>&1 || return 1
		pb=$(pbytes "$CK")
		cmp -s -i 128 -n "$pb" "$CK" "$SCK" || { echo "serve copy params DIFFER" >"$d/serve-copy.txt"; return 1; }
		echo "serve copy $(sha256sum "$SCK") from T $st to T $SERVE_T B 4 G 1 (tune4), params identical ($pb bytes)" >"$d/serve-copy.txt"
	fi
	[ -n "$(listen_pid "$PORT")" ] && { echo "port $PORT busy" >"$d/serve-copy.txt"; return 1; }
	ckid "$SCK" >"$d/serve-ck-id.txt" 2>&1
	t3=$(now)
	taskset -c "$CORES" nice -n 10 "$O" serve "$PORT" "$SCK" "$MERGES" par=2 >"$d/serve.log" 2>&1 &
	spid=$!
	i=0
	until curl -s -m 2 -o "$d/health.json" -w '%{http_code}' "http://127.0.0.1:$PORT/health" 2>/dev/null | grep -q '^200$'; do
		i=$((i + 1))
		{ [ $i -gt 1200 ] || ! kill -0 "$spid" 2>/dev/null; } && return 1
		sleep 0.25
	done
	echo "ready_ms $(secs "$t3")" >"$d/ready.txt"
	wpids=$(pgrep -P "$spid" | tr '\n' ' ')
	lp=$(listen_pid "$PORT")
	ss -Hltnp "sport = :$PORT" >"$d/listen.txt"
	{
		echo "pid $spid workers $wpids listener $lp"
		echo "exe $(sha256sum /proc/"$spid"/exe | cut -c1-64) path $(readlink /proc/"$spid"/exe)"
		echo "argv $(tr '\0' ' ' </proc/"$spid"/cmdline)"
		echo "affinity $(taskset -pc "$spid" 2>&1)"
	} >"$d/live.txt"
	curl -s -m 5 "http://127.0.0.1:$PORT/v1/models" >"$d/models.json"
	return 0
}
chat() { # N BODYFILE -> resp-N.{head,json}, a row in requests.txt
	t4=$(now)
	code=$(curl -s -m 900 -D "$d/resp-$1.head" -o "$d/resp-$1.json" -w '%{http_code}' -H 'Content-Type: application/json' \
		--data-binary @"$2" "http://127.0.0.1:$PORT/v1/chat/completions")
	tc=$(jq -r 'if .choices then (.choices[0].message.tool_calls // [] | length) else "-" end' "$d/resp-$1.json" 2>/dev/null)
	fin=$(jq -r '.choices[0].finish_reason // .error.code // "-"' "$d/resp-$1.json" 2>/dev/null)
	echo "$1 http=$code ms=$(secs "$t4") finish=$fin tool_calls=$tc usage=$(jq -c '.usage // {}' "$d/resp-$1.json" 2>/dev/null)" >>"$d/requests.txt"
	echo "$code"
}
TOOLS='[{"type":"function","function":{"name":"terminal","description":"Run a shell command and return its output.","parameters":{"type":"object","properties":{"command":{"type":"string","description":"The command to run"}},"required":["command"]}}}]'
if want 3 || want 4 || want 5 || want 6; then
	t=$(now)
	r=PASS
	if start_server; then
		d=$OUT/step3
		echo "LABEL $LABEL" >"$d/requests.txt"
		# loaded identity: the health "model" member must name the served file's header fields
		hm=$(jq -r '.model | "ck \(.ck) \(.V) \(.T) \(.D) \(.H) \(.F) \(.L) \(.B) \(.step) \(.P) \(.ck_bytes) \(.ck_fnv) tok \(.tok_V) \(.tok_fnv)"' "$d/health.json")
		fm=$(awk '/^ck /{c = $0} /^tok /{t = "tok " $3 " " $4} END {print c, t}' "$d/serve-ck-id.txt")
		{ echo "health_model $hm"; echo "file_ident   $fm"; } >>"$d/live.txt"
		if [ "$hm" = "$fm" ]; then echo "identity EQUAL" >>"$d/live.txt"; else r=FAIL; echo "identity DIFFERS" >>"$d/live.txt"; fi
		[ "$(sha256sum /proc/"$spid"/exe | cut -c1-64)" = "$(sha256sum "$O" | cut -c1-64)" ] || r=FAIL
		if want 3; then
			n=0
			for p in "Hello! Who are you?" "Write one sentence about the sea." "What is 2 + 2?"; do
				n=$((n + 1))
				jq -nc --arg p "$p" '{model:"ollm",temperature:0,max_tokens:48,messages:[{role:"user",content:$p}]}' >"$d/req-$n.json"
				[ "$(chat $n "$d/req-$n.json")" = 200 ] || r=FAIL
			done
			for p in "Create a file named notes.txt containing hello world." "List the files in the current directory."; do
				n=$((n + 1))
				jq -nc --arg p "$p" --argjson t "$TOOLS" '{model:"ollm",temperature:0,max_tokens:64,tools:$t,messages:[{role:"system",content:"You are a helpful assistant with a terminal tool."},{role:"user",content:$p}]}' >"$d/req-$n.json"
				[ "$(chat $n "$d/req-$n.json")" = 200 ] || r=FAIL
			done
			# negative control: a malformed body must be refused (4xx), not answered
			printf '{"model":"ollm","messages":"not-an-array"}' >"$d/req-neg.json"
			c=$(chat neg "$d/req-neg.json")
			case $c in 4??) ;; *) r=FAIL ;; esac
		fi
		grep '^C ' "$d/serve.log" >"$d/serve-C-lines.txt"
	else
		r=FAIL
	fi
	rec 3 serve $r "$(secs "$t")" "ready_ms=$(cut -d' ' -f2 "$OUT/step3/ready.txt" 2>/dev/null) $(grep -c . "$OUT/step3/requests.txt" 2>/dev/null) rows; health $(jq -c '.model' "$OUT/step3/health.json" 2>/dev/null | cut -c1-160)"
	[ $r = PASS ] || FAILS=$((FAILS + 1))
fi
# up: the server still runs; the first time it is found gone, its exit status is recorded (SERVER_DIED)
up() {
	[ -n "$spid" ] || return 1
	kill -0 "$spid" 2>/dev/null && return 0
	if [ -z "${srvrc:-}" ]; then
		wait "$spid"
		srvrc=$?
		echo "SERVER_DIED rc=$srvrc found $(date -u +%FT%TZ) log_mtime $(date -u -r "$OUT/step3/serve.log" +%FT%TZ) last: $(tail -1 "$OUT/step3/serve.log")" | tee -a "$SUM"
	fi
	return 1
}

# ---- 4 harness
if want 4 && up; then
	t=$(now)
	d=$OUT/step4
	mkdir -p "$d"
	r=PASS
	echo "LABEL $LABEL" >"$d/LABEL"
	# (a) new train-family instances: sftgen's WORLD output (TASKS.md format) for TRAINSEED; drop any task whose
	# @file/@prompt/@expect content equals a task of the training seed (20261107, 20000) or the sft-val seed (99, 500)
	G=$WORK/sg
	mkdir -p "$G"
	run "$B/sftgen" "$TRAINSEED" "$TRAINN" "$G/new.jsonl" "$d/train-new-raw.txt" >"$d/sftgen.txt" 2>&1 || r=FAIL
	run "$B/sftgen" 20261107 20000 "$G/tr.jsonl" "$G/tr.world" >>"$d/sftgen.txt" 2>&1 || r=FAIL
	run "$B/sftgen" 99 500 "$G/va.jsonl" "$G/va.world" >>"$d/sftgen.txt" 2>&1 || r=FAIL
	# the regenerated pools must be the bytes run1 trained / validated on (DATA/sft.sha256)
	for p in tr:sft-train.jsonl va:sft-val.jsonl; do
		w=$(grep " ${p#*:}\$" "$DATA/sft.sha256" | cut -c1-64)
		g=$(sha256sum "$G/${p%%:*}.jsonl" | cut -c1-64)
		if [ -n "$w" ] && [ "$w" = "$g" ]; then echo "pool ${p#*:} regenerated $g EQUAL"; else r=FAIL; echo "pool ${p#*:} regenerated $g want ${w:-none} DIFFERS"; fi
	done >"$d/pools.txt"
	norm() { awk '/^@task /{if (b != "") print b; b = ""; id = $2; next} {b = b $0 "\001"} END {if (b != "") print b}' "$1"; }
	norm "$G/tr.world" >"$G/seen"
	norm "$G/va.world" >>"$G/seen"
	sort -u "$G/seen" -o "$G/seen"
	unseen() { # IN OUT: copy the tasks of IN whose content is not in the seen pool; SEEN ID lines on stderr
		awk 'NR == FNR {s[$0] = 1; next}
		/^@task /{if (id != "") out(); id = $2; hdr = $0; b = ""; body = ""; next}
		{b = b $0 "\001"; body = body $0 "\n"}
		function out() { if (b in s) print "SEEN " id > "/dev/stderr"; else printf "%s\n%s", hdr, body }
		END {if (id != "") out()}' "$G/seen" "$1" >"$2"
	}
	unseen "$d/train-new-raw.txt" "$d/train-new.txt" 2>"$d/train-seen.txt"
	echo "trainseed $TRAINSEED n $TRAINN kept $(grep -c '^@task ' "$d/train-new.txt") seen $(grep -c . "$d/train-seen.txt") seen_pool $(wc -l <"$G/seen")" >"$d/unseen.txt"
	# negative control: the first training task (renamed) must be caught as seen
	awk '/^@task /{n++} n == 1' "$G/tr.world" | sed '1s/^@task [^ ]*/@task negseen/' >"$G/neg.world"
	unseen "$G/neg.world" "$G/neg.out" 2>"$G/neg.err"
	if grep -q '^SEEN negseen$' "$G/neg.err" && ! grep -q . "$G/neg.out"; then echo "neg_seen caught (control ok)"; else r=FAIL; echo "neg_seen MISSED (control failed)"; fi >>"$d/unseen.txt"
	rm -rf "$G"
	if [ "$DRY" = 1 ]; then
		otr=$("$B/verify" list "$d/train-new.txt" | awk '!s[$2]++' | head -3 | cut -d' ' -f1 | tr '\n' ' ')
		ohe="t14 t16"
	else
		otr=$("$B/verify" list "$d/train-new.txt" | cut -d' ' -f1 | tr '\n' ' ')
		ohe="t14 t15 t16 t17 t18 t19 t20 c01 c02"
	fi
	echo "only_train $otr" >>"$d/unseen.txt"
	echo "only_heldout $ohe" >>"$d/unseen.txt"
	ONLY=$otr PPORT=$PPORT CORES=$CORES VERIFY=$B/verify TMO=${TMO:-300} sh "$H/run.sh" "http://127.0.0.1:$PORT/v1" "$d/train-new.txt" "$d/train" >"$d/train.log" 2>&1 || r=FAIL
	ONLY=$ohe PPORT=$PPORT CORES=$CORES VERIFY=$B/verify TMO=${TMO:-300} sh "$H/run.sh" "http://127.0.0.1:$PORT/v1" "$H/tasks.txt" "$d/heldout" >"$d/heldout.log" 2>&1 || r=FAIL
	# pass rule (protocol): every row ran (no INVALID / SETUP_FAIL) and every control FAILed
	for s in train heldout; do grep -q 'INVALID\|SETUP_FAIL' "$d/$s/summary.txt" && r=FAIL; done
	# every task reached the server at least once (0 chat POSTs = Hermes never asked the model: not a verdict)
	awk 'NF == 8 && $7 == 0 {print FILENAME, $1}' "$d/train/summary.txt" "$d/heldout/summary.txt" >"$d/noreq.txt"
	[ -s "$d/noreq.txt" ] && r=FAIL
	ls "$d"/train/*/hermes.ctxcache "$d"/heldout/*/hermes.ctxcache >"$d/ctxcache.txt" 2>/dev/null
	awk '$3 == "control" && $4 == "PASS"' "$d/heldout/summary.txt" | grep -q . && r=FAIL
	up || r=FAIL
	ktr=$(awk 'NF == 8 && $3 == "train" && $4 == "PASS"' "$d/train/summary.txt" | wc -l)
	ntr=$(awk 'NF == 8 && $3 == "train"' "$d/train/summary.txt" | wc -l)
	khe=$(awk 'NF == 8 && $3 == "heldout" && $4 == "PASS"' "$d/heldout/summary.txt" | wc -l)
	nhe=$(awk 'NF == 8 && $3 == "heldout"' "$d/heldout/summary.txt" | wc -l)
	{
		echo "LABEL $LABEL"
		echo "CAPABILITY train_new pass=$ktr/$ntr heldout pass=$khe/$nhe (verify.om verdicts; rows in train/summary.txt heldout/summary.txt)"
		echo "WOLFRAM wilson[k_,n_]:=With[{z=Quantile[NormalDistribution[],0.975],p=k/n},N[{(p+z^2/(2n)-z Sqrt[p(1-p)/n+z^2/(4n^2)])/(1+z^2/n),(p+z^2/(2n)+z Sqrt[p(1-p)/n+z^2/(4n^2)])/(1+z^2/n)}]]; {wilson[$ktr,$ntr],wilson[$khe,$nhe]}"
	} >"$d/capability.txt"
	rec 4 harness $r "$(secs "$t")" "train_new $ktr/$ntr heldout $khe/$nhe noreq $(grep -c . "$d/noreq.txt") ctxcache $(grep -c . "$d/ctxcache.txt") controls $(awk '$3 == "control"{print $1 "=" $4}' "$d/heldout/summary.txt" | tr '\n' ' ')"
	[ $r = PASS ] || FAILS=$((FAILS + 1))
elif want 4; then
	rec 4 harness NOT_RUN 0 "no server"
fi

# ---- 5 accept (DRA-124)
if want 5 && up; then
	t=$(now)
	d=$OUT/step5
	mkdir -p "$d" "$(dirname "$AOUT")"
	r=PASS
	pm=$(stat -c %a "$(dirname "$AOUT")")
	case $AOUT in "$HOME"/work/hive/ownmodel/accept/*) chmod 700 "$(dirname "$AOUT")" ;; esac
	pm=$(stat -c %a "$(dirname "$AOUT")")
	[ "$pm" = 700 ] || { r=FAIL; echo "AOUT parent mode $pm is not 700" >"$d/accept.err"; }
	if [ $r = PASS ]; then
		if [ "$DRY" = 1 ]; then aenv="SPLITS=dev DEVN=10 PUBLIC=0 REPEATS=0"; else aenv=""; fi
		echo "env $aenv ${ACCEPT_ENV:-} HPPORT=$PPORT" >"$d/command.txt"
		echo "AOUT $AOUT" >>"$d/command.txt"
		env $aenv ${ACCEPT_ENV:-} ACCEPT="$B/accept" OMC="$OMC" CORES="$CORES" HARNESS="$H" VERIFY="$B/verify" HPPORT="$PPORT" \
			sh "$repo/tests/omegallm/accept/run.sh" 127.0.0.1 "$PORT" "$AOUT" "run1-$STAGE-$ck8" >"$d/accept.out" 2>&1
		arc=$?
		echo "rc $arc (0 = every gate met; 1 = a gate failed; capability verdicts are not this step's pass rule)" >>"$d/command.txt"
		# aggregate rows only into OUTDIR (the transcripts stay in AOUT, 0700)
		{ echo "LABEL $LABEL"; cat "$AOUT/receipt.txt"; } >"$d/receipt.txt" 2>/dev/null
		for f in "$AOUT"/*.summary "$AOUT"/pair-*.tsv; do [ -e "$f" ] && { echo "LABEL $LABEL"; cat "$f"; } >"$d/$(basename "$f")"; done
		[ -s "$AOUT/t0.summary" ] || r=FAIL
		# every request reached the server (a conn row means the endpoint was gone, not a model verdict)
		cat "$AOUT"/*/results-*.tsv 2>/dev/null | awk -F'\t' '$6 == "conn"' >"$d/conn-rows.txt"
		[ -s "$d/conn-rows.txt" ] && r=FAIL
		up || r=FAIL
		grep -q 'runner failed\|mismatch' "$d/accept.out" && r=FAIL
	fi
	rec 5 accept $r "$(secs "$t")" "rc=${arc:-none} $(grep -c . "$AOUT/t0.summary" 2>/dev/null) summary rows; transcripts $AOUT"
	[ $r = PASS ] || FAILS=$((FAILS + 1))
elif want 5; then
	rec 5 accept NOT_RUN 0 "no server"
fi

# ---- 6 demo: Drake's own public words (hive directive), through real Hermes, verified on disk
if want 6 && up; then
	t=$(now)
	d=$OUT/step6
	mkdir -p "$d"
	r=PASS
	cat >"$d/demo.txt" <<'EOF'
# run1 end-to-end demo task (eval.sh step 6). The content is Drake's own public hive directive.
@task d01 create train
@prompt
Create a file named directive.txt whose content is exactly: use your best judgement and get this done
@end
@ref
printf 'use your best judgement and get this done\n' > directive.txt
@end
@expect trim directive.txt
use your best judgement and get this done
@end

# negative control: the same outcome checked against a deliberately different text must FAIL
@task d01x create control
@prompt
(control only, never sent)
@end
@expect trim directive.txt
use your best judgement and get this done!
@end
EOF
	l0=$(wc -l <"$OUT/step3/serve.log")
	ONLY=d01 PPORT=$PPORT CORES=$CORES VERIFY=$B/verify TMO=${TMO:-300} sh "$H/run.sh" "http://127.0.0.1:$PORT/v1" "$d/demo.txt" "$d/run" >"$d/run.log" 2>&1 || r=FAIL
	tail -n +"$((l0 + 1))" "$OUT/step3/serve.log" >"$d/serve-lines.txt"
	# independent verifier, re-run here on the copied work dir, plus the control on the same dir
	"$B/verify" check "$d/demo.txt" d01 "$d/run/d01/work" >"$d/verify-d01.txt" 2>&1
	v=$?
	"$B/verify" check "$d/demo.txt" d01x "$d/run/d01/work" >"$d/verify-d01x.txt" 2>&1 && r=FAIL
	[ -e "$d/run/d01/pre.txt" ] && grep -q '^FAIL' "$d/run/d01/pre.txt" || r=FAIL
	[ "$(grep -c . "$d/run/d01/wire/chat.txt" 2>/dev/null)" -ge 1 ] || r=FAIL
	# the full Hermes transcript: stdout, every wire request/response, and the session export
	hb=${HERMES_BIN:-$HOME/workspace/hermes-agent/.hermes/bin/hermes}
	env -i HOME="$HOME" HERMES_HOME="$HARNESS_HOME" PATH=/usr/bin:/bin TERM=dumb "$hb" sessions list >"$d/sessions-list.txt" 2>&1
	sid=$(grep 'hw-d01\.' "$d/sessions-list.txt" | grep -o 'local-[0-9a-f]*' | head -1)
	echo "session ${sid:-NONE}" >"$d/export.txt"
	if [ -n "$sid" ]; then
		env -i HOME="$HOME" HERMES_HOME="$HARNESS_HOME" PATH=/usr/bin:/bin TERM=dumb "$hb" sessions export --format jsonl --session-id "$sid" --yes "$d/session.jsonl" >>"$d/export.txt" 2>&1
		env -i HOME="$HOME" HERMES_HOME="$HARNESS_HOME" PATH=/usr/bin:/bin TERM=dumb "$hb" sessions export --format md --session-id "$sid" --yes "$d/session-md/" >>"$d/export.txt" 2>&1
	fi
	if [ $v -eq 0 ]; then res="DEMO_PASS"; else res="DEMO_FAIL $(cat "$d/verify-d01.txt")"; fi
	{ echo "LABEL $LABEL"; echo "$res"; echo "control d01x $(cat "$d/verify-d01x.txt")"; echo "hermes rc $(cat "$d/run/d01/hermes.rc") ms $(cat "$d/run/d01/hermes.ms")"; } >"$d/result.txt"
	up || r=FAIL
	rec 6 demo $r "$(secs "$t")" "$res (capability, not the step's pass rule)"
	[ $r = PASS ] || FAILS=$((FAILS + 1))
elif want 6; then
	rec 6 demo NOT_RUN 0 "no server"
fi

# ---- 7 stop
t=$(now)
r=PASS
if [ -n "$spid" ]; then
	up || r=FAIL
	grep '^C ' "$OUT/step3/serve.log" >"$OUT/step3/serve-C-lines.txt" 2>/dev/null
	kill "$spid" $wpids 2>/dev/null
	wait "$spid" 2>/dev/null
	sleep 1
	for p in "$spid" $wpids; do kill -0 "$p" 2>/dev/null && { kill -9 "$p"; r=FAIL; }; done
	[ -n "$(listen_pid "$PORT")" ] && r=FAIL
	[ -n "$(listen_pid "$PPORT")" ] && r=FAIL
fi
rm -f "$WORK"/serve-t*-"$ck8".ck
rec 7 stop $r "$(secs "$t")" "server $spid workers $wpids; port $PORT free"
spid=
[ $r = PASS ] || FAILS=$((FAILS + 1))
echo "end $(date -u +%FT%TZ) fails $FAILS" >>"$SUM"
echo "================ run1 eval summary: $LABEL"
cat "$SUM"
[ $FAILS -eq 0 ]
