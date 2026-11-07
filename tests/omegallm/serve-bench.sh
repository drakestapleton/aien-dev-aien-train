#!/bin/sh
# serve-bench.sh: measure `ollm serve` on a CK03 checkpoint with OLLMTOK1 merges (DRA-121).
# Env: OLLM, CK, MERGES, OUT (receipt dir), TEXT (public text, ASCII-filtered for the prompts),
# CORES (taskset list, default 4), PORT (default 18295), LENS (prompt token targets, default
# "256 1024"), DEC (decode tokens per run, default 32), ALLEN (allen-chat system prompt, optional).
# One server under taskset/nice with test=1 (ollm_test_cold for cold prefills); every time is the
# server's own log `ms` (monotonic clock in serve.om) unless named client_s. Prints `B ...` lines;
# the numbers are measurements of this host and core only.
set -u
: "${OLLM:?}" "${CK:?}" "${MERGES:?}" "${OUT:?}" "${TEXT:?}"
CORES=${CORES:-4}
PORT=${PORT:-18295}
LENS=${LENS:-256 1024}
DEC=${DEC:-32}
mkdir -p "$OUT"
log=$OUT/server.log
res=$OUT/bench.txt
: >"$res"
say() { echo "$*" | tee -a "$res"; }
say "B env date=$(date -u +%FT%TZ) host=$(hostname) cores=$CORES ollm=$(sha256sum "$OLLM" | cut -c1-64) ck=$(basename "$CK") ck_bytes=$(wc -c <"$CK")"
# ASCII text without control bytes but newline, JSON-escaped on one line
LC_ALL=C tr -cd '\12\40-\176' <"$TEXT" | head -c 400000 >"$OUT/text.txt"
jtext() { head -c "$1" "$OUT/text.txt" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | awk 'BEGIN{ORS=""} {if (NR>1) printf "\\n"; print}'; }
# prompt tokens (chatenc tokens + 259) of a user message of the first n bytes
ntok() {
	printf '{"messages":[{"role":"user","content":"%s"}]}\n' "$(jtext "$1")" >"$OUT/n.jsonl"
	"$OLLM" chatenc "$MERGES" "$OUT/n.jsonl" "$OUT/n.u16" | awk '{print $3 + 1}'
}
# smallest byte count whose prompt reaches the target (bisection)
bytes_for() {
	lo=1 hi=$(($1 * 8))
	while [ $lo -lt $hi ]; do
		mid=$(((lo + hi) / 2))
		if [ "$(ntok $mid)" -lt "$1" ]; then lo=$((mid + 1)); else hi=$mid; fi
	done
	echo $lo
}
body() { # bytes max_tokens extra-members
	printf '{"messages":[{"role":"user","content":"%s"}],"max_tokens":%s,"temperature":0%s}' "$(jtext "$1")" "$2" "$3"
}
post() { curl -s -o /dev/null -w '%{http_code} %{time_total}' -H 'Content-Type: application/json' --data-binary @"$1" "http://127.0.0.1:$PORT/v1/chat/completions"; }
lastlog() { grep '^C 200 ' "$log" | tail -1; }

t0=$(date +%s%N)
taskset -c "$CORES" nice -n 10 "$OLLM" serve "$PORT" "$CK" "$MERGES" test=1 >"$log" 2>&1 &
pid=$!
until grep -q '^PORT' "$log" 2>/dev/null; do kill -0 $pid 2>/dev/null || { say "B start_fail $(cat "$log")"; exit 1; }; sleep 0.01; done
t1=$(date +%s%N)
say "B startup_ms $(((t1 - t0) / 1000000)) rss_kb_after_start $(awk '/VmHWM/{print $2}' /proc/$pid/status)"

for L in $LENS; do
	nb=$(bytes_for "$L")
	body "$nb" 1 ',"ollm_test_cold":true' >"$OUT/p$L-1.json"
	body "$nb" $((DEC + 1)) ',"ollm_test_cold":true' >"$OUT/p$L-d.json"
	r1=$(post "$OUT/p$L-1.json"); l1=$(lastlog)
	r2=$(post "$OUT/p$L-d.json"); l2=$(lastlog)
	say "B prefill target=$L bytes=$nb http=$r1 log=[$l1]"
	say "B decode target=$L http=$r2 log=[$l2]"
done

# prefix reuse: a 2-turn conversation; turn 2 warm (cache of turn 1) against turn 2 cold
nb=$(bytes_for 900)
u1=$(jtext "$nb")
printf '{"messages":[{"role":"system","content":"You are a careful assistant."},{"role":"user","content":"%s"}],"max_tokens":8,"temperature":0}' "$u1" >"$OUT/t1.json"
for k in warm cold; do
	ex=
	[ $k = cold ] && ex=',"ollm_test_cold":true'
	printf '{"messages":[{"role":"system","content":"You are a careful assistant."},{"role":"user","content":"%s"},{"role":"assistant","content":"I read it."},{"role":"user","content":"Summarise the second paragraph in one sentence."}],"max_tokens":8,"temperature":0%s}' "$u1" "$ex" >"$OUT/t2$k.json"
	r=$(post "$OUT/t1.json"); lt1=$(lastlog)
	r=$(post "$OUT/t2$k.json"); lt2=$(lastlog)
	say "B reuse turn1 log=[$lt1]"
	say "B reuse turn2_$k http=$r log=[$lt2]"
done

# queue: 4 concurrent clients, each its own 256-token prompt (cold: different texts), 16 tokens
nb=$(bytes_for 256)
for i in 1 2 3 4; do
	printf '{"messages":[{"role":"user","content":"client %s: %s"}],"max_tokens":16,"temperature":0}' "$i" "$(jtext "$nb")" >"$OUT/q$i.json"
done
n0=$(grep -c '^C 200 ' "$log")
for i in 1 2 3 4; do (post "$OUT/q$i.json" >"$OUT/q$i.out") & done
wait
for i in 1 2 3 4; do say "B queue client=$i http_client_s=$(cat "$OUT/q$i.out")"; done
grep '^C 200 ' "$log" | tail -n +$((n0 + 1)) | while read -r l; do say "B queue log=[$l]"; done

if [ -n "${ALLEN:-}" ] && [ -r "$ALLEN" ]; then
	sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' "$ALLEN" | LC_ALL=C tr -d '\000-\010\013-\037' | awk 'BEGIN{ORS=""} {if (NR>1) printf "\\n"; print}' >"$OUT/allen.esc"
	printf '{"messages":[{"role":"system","content":"%s"},{"role":"user","content":"hi"}]}\n' "$(cat "$OUT/allen.esc")" >"$OUT/allen.jsonl"
	say "B allen_chatenc $("$OLLM" chatenc "$MERGES" "$OUT/allen.jsonl" "$OUT/allen.u16") bytes=$(wc -c <"$ALLEN")"
fi
say "B peak_rss_kb $(awk '/VmHWM/{print $2}' /proc/$pid/status)"
kill $pid
wait $pid 2>/dev/null
say "B done"
