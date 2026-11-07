#!/bin/sh
# serve-par-life.sh: worker lifecycle of `ollm serve par=N` (servefast). Env: OLLM, CK (CK03),
# MERGES, OUT, TEXT, CORES (default 4,6), PORT (default 18291), PAR (default 2), LEN (prompt
# bytes, default 6000: a prefill of several seconds). Steps: (1) a client that leaves 3 s into a
# cold prefill (curl --max-time 3): the prefill workers must end with the prefill and the server
# must answer /health afterwards with only its N - 1 logits workers left; (2) SIGTERM to the
# server 3 s into another cold prefill: within 2 s no worker (prefill or logits) may remain.
# Prints `L name pass|fail ...` and `PAR_LIFE PASS|FAIL`; exit 0 only on pass. Negative control:
# build.sh --mutant lw (a logits worker ignores the end of file of its down pipe) must fail step 2.
set -u
: "${OLLM:?}" "${CK:?}" "${MERGES:?}" "${OUT:?}" "${TEXT:?}"
CORES=${CORES:-4,6}
PORT=${PORT:-18291}
PAR=${PAR:-2}
LEN=${LEN:-6000}
mkdir -p "$OUT"
res=$OUT/par-life.txt
: >"$res"
say() { echo "$*" | tee -a "$res"; }
fails=0
pass() { say "L $1 pass $2"; }
fail() { say "L $1 fail $2"; fails=$((fails + 1)); }
say "env date=$(date -u +%FT%TZ) ollm=$(sha256sum "$OLLM" | cut -c1-64) par=$PAR len=$LEN"
LC_ALL=C tr -cd '\12\40-\176' <"$TEXT" | head -c 100000 >"$OUT/text.txt"
u=$(head -c "$LEN" "$OUT/text.txt" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | awk 'BEGIN{ORS=""} {if (NR>1) printf "\\n"; print}')
printf '{"messages":[{"role":"user","content":"%s"}],"max_tokens":4,"temperature":0,"ollm_test_cold":true}' "$u" >"$OUT/req.json"
start() {
	taskset -c "$CORES" nice -n 10 "$OLLM" serve "$PORT" "$CK" "$MERGES" test=1 "par=$PAR" >"$OUT/$1.log" 2>&1 &
	spid=$!
	until grep -q "^PORT $PORT" "$OUT/$1.log" 2>/dev/null; do kill -0 $spid 2>/dev/null || { say "start_fail"; exit 1; }; sleep 0.1; done
}
kids() { pgrep -P "$1" | tr '\n' ' '; }
# (1) a client that leaves during the prefill
start s1
# the logits workers are forked just after the PORT line: wait for them (at most 10 s)
i=0
while [ "$(pgrep -P $spid | wc -l)" -lt $((PAR - 1)) ] && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
idle=$(kids $spid)
curl -s -o /dev/null --max-time 3 -H 'Content-Type: application/json' --data-binary @"$OUT/req.json" "http://127.0.0.1:$PORT/v1/chat/completions"
during=$(kids $spid)
nd=$(echo $during | wc -w)
i=0
until grep -q '^C ' "$OUT/s1.log" || [ $i -gt 600 ]; do sleep 0.5; i=$((i + 1)); done
sleep 0.5
h=$(curl -s --max-time 5 "http://127.0.0.1:$PORT/health")
after=$(kids $spid)
na=$(echo $after | wc -w)
if [ "$nd" -eq $((2 * (PAR - 1))) ] && [ "$na" -eq $((PAR - 1)) ] && [ "$after" = "$idle" ] && echo "$h" | grep -q '"in_flight":0' &&
	grep -q '^C 499 ' "$OUT/s1.log"; then
	pass client_left_mid_prefill "idle=[$idle] during=[$during] after=[$after] log=[$(grep '^C ' "$OUT/s1.log" | tr '\n' ';')] health=$h"
else
	fail client_left_mid_prefill "idle=[$idle] during=[$during] after=[$after] log=[$(grep '^C ' "$OUT/s1.log" | tr '\n' ';')] health=$h"
fi
# (2) SIGTERM during a prefill
curl -s -o /dev/null --max-time 60 -H 'Content-Type: application/json' --data-binary @"$OUT/req.json" "http://127.0.0.1:$PORT/v1/chat/completions" &
cpid=$!
sleep 3
during=$(kids $spid)
kill -TERM $spid
wait $spid 2>/dev/null
sleep 2
left=
for k in $during; do kill -0 "$k" 2>/dev/null && left="$left $k"; done
wait $cpid 2>/dev/null
nd=$(echo $during | wc -w)
if [ "$nd" -eq $((2 * (PAR - 1))) ] && [ -z "$left" ]; then pass sigterm_mid_prefill "workers=[$during] left=[]"; else fail sigterm_mid_prefill "workers=[$during] left=[$left]"; fi
# a leaked worker (a failing build) is stopped here, after it was counted
for k in $left; do [ "$(readlink /proc/$k/exe)" = "$(readlink -f "$OLLM")" ] && kill -9 "$k" 2>/dev/null; done
if [ $fails -eq 0 ]; then say "PAR_LIFE PASS"; exit 0; fi
say "PAR_LIFE FAIL fails=$fails"
exit 1
