#!/bin/sh
# serve-par-check.sh: `ollm serve par=N` against par=1 and against the serial decode (servefast).
# Env: OLLM, CK (CK03), MERGES (OLLMTOK1), OUT (receipt dir), TEXT (public text for the prompts),
# CORES (taskset list, default 4,6), PORT (par=N server, default 18291), TPORT (par=1 server,
# default 18292), PAR (default 2), LEN (prompt bytes, default 1500), GEN (greedy tokens, default
# 24), ONE_OLLM (optional: another binary for the par=1 server, e.g. the build before a change;
# its logits_fnv_all is not compared). Both servers run test=1. For each request three answers must agree in every bit: the par=N
# server's (layer prefill on N processes), the same server's with ollm_test_serial (position by
# position decode, no layer prefill) and the par=1 server's: logits_fnv (the first step's V logits'
# FNV-1a 64), logits_fnv_all (every step's, folded) and the message. Requests: a cold prompt, then a
# second turn that reuses the first's cache (the prefill starts inside the cache: cv > 0), then
# the second turn cold. Prints `P name pass|fail ...`, `PAR_CHECK PASS|FAIL`; exit 0 only on pass.
# The par server's logits workers (N - 1 children between requests) must all be gone after SIGTERM.
set -u
: "${OLLM:?}" "${CK:?}" "${MERGES:?}" "${OUT:?}" "${TEXT:?}"
CORES=${CORES:-4,6}
PORT=${PORT:-18291}
TPORT=${TPORT:-18292}
PAR=${PAR:-2}
LEN=${LEN:-1500}
GEN=${GEN:-24}
mkdir -p "$OUT"
res=$OUT/par-check.txt
: >"$res"
say() { echo "$*" | tee -a "$res"; }
fails=0
pass() { say "P $1 pass $2"; }
fail() { say "P $1 fail $2"; fails=$((fails + 1)); }
say "env date=$(date -u +%FT%TZ) host=$(hostname) ollm=$(sha256sum "$OLLM" | cut -c1-64) ck=$(sha256sum "$CK" | cut -c1-64) par=$PAR len=$LEN gen=$GEN"
LC_ALL=C tr -cd '\12\40-\176' <"$TEXT" | head -c 200000 >"$OUT/text.txt"
jtext() { tail -c +"$1" "$OUT/text.txt" | head -c "$2" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | awk 'BEGIN{ORS=""} {if (NR>1) printf "\\n"; print}'; }

pids=
start() { # name port options...
	n=$1 p=$2
	shift 2
	taskset -c "$CORES" nice -n 10 "$OLLM" serve "$p" "$CK" "$MERGES" test=1 "$@" >"$OUT/$n.log" 2>&1 &
	pid=$!
	pids="$pids $pid"
	i=0
	until grep -q "^PORT $p" "$OUT/$n.log" 2>/dev/null; do
		i=$((i + 1))
		if [ $i -gt 1200 ] || ! kill -0 $pid 2>/dev/null; then say "start_fail $n $(cat "$OUT/$n.log")"; exit 1; fi
		sleep 0.1
	done
	eval "pid_$n=$pid"
}
start par "$PORT" "par=$PAR"
OLLM0=$OLLM
[ -n "${ONE_OLLM:-}" ] && OLLM=$ONE_OLLM
start one "$TPORT"
OLLM=$OLLM0

u1=$(jtext 1 "$LEN")
u2=$(jtext $((LEN + 1)) $((LEN / 3)))
m1="{\"role\":\"system\",\"content\":\"You are a careful assistant.\"},{\"role\":\"user\",\"content\":\"$u1\"}"
m2="$m1,{\"role\":\"assistant\",\"content\":\"I read it.\"},{\"role\":\"user\",\"content\":\"$u2\"}"
# post NAME PORT MESSAGES EXTRA: the response with id and created removed
post() {
	printf '{"messages":[%s],"max_tokens":%s,"temperature":0,"ollm_test_info":true%s}' "$3" "$GEN" "$4" >"$OUT/$1.json"
	curl -s -H 'Content-Type: application/json' --data-binary @"$OUT/$1.json" "http://127.0.0.1:$2/v1/chat/completions" |
		sed -e 's/"id":"[^"]*",//' -e 's/"created":[0-9]*,//' >"$OUT/$1.out"
}
fnv() { grep -o "\"$2\":[0-9]*" "$OUT/$1.out" | head -1 | cut -d: -f2; }
msg() { grep -o '"message":{[^}]*}' "$OUT/$1.out" | head -1; }
prompt_n() { grep -o '"prompt_tokens":[0-9]*' "$OUT/$1.out" | cut -d: -f2; }
cmp3() { # label a b c
	fa=$(fnv "$2" logits_fnv) fb=$(fnv "$3" logits_fnv) fc=$(fnv "$4" logits_fnv)
	ga=$(fnv "$2" logits_fnv_all) gb=$(fnv "$3" logits_fnv_all) gc=$(fnv "$4" logits_fnv_all)
	[ -n "${ONE_OLLM:-}" ] && gc=$ga # an older par=1 binary has no logits_fnv_all
	d="fnv=$fa/$fb/$fc all=$ga/$gb/$gc prompt_tokens=$(prompt_n "$2") reused=$(fnv "$2" reused) prefilled=$(fnv "$2" prefilled)"
	if [ -n "$fa" ] && [ "$fa" != 0 ] && [ "$fa" = "$fb" ] && [ "$fa" = "$fc" ] && [ -n "$ga" ] && [ "$ga" = "$gb" ] && [ "$ga" = "$gc" ] &&
		[ -n "$(msg "$2")" ] && [ "$(msg "$2")" = "$(msg "$3")" ] && [ "$(msg "$2")" = "$(msg "$4")" ]; then
		pass "$1" "$d"
	else
		fail "$1" "$d msg=[$(msg "$2")] serial=[$(msg "$3")] one=[$(msg "$4")]"
	fi
}
# turn 1 cold on all three; turn 2 warm (reuse) on par and one, serial cold; turn 2 cold on par
post a1 "$PORT" "$m1" ',"ollm_test_cold":true'
post s1 "$PORT" "$m1" ',"ollm_test_cold":true,"ollm_test_serial":true'
post o1 "$TPORT" "$m1" ',"ollm_test_cold":true'
cmp3 par_cold_turn1 a1 s1 o1
post a0 "$PORT" "$m1" ''
post o0 "$TPORT" "$m1" ''
post a2 "$PORT" "$m2" ''
post s2 "$PORT" "$m2" ',"ollm_test_cold":true,"ollm_test_serial":true'
post o2 "$TPORT" "$m2" ''
cmp3 par_warm_turn2 a2 s2 o2
r=$(fnv a2 reused)
if [ -n "$r" ] && [ "$r" -gt 2 ] && [ "$(fnv a2 prefilled)" -gt 2 ]; then pass par_warm_reused "reused=$r prefilled=$(fnv a2 prefilled)"; else fail par_warm_reused "reused=$r"; fi
post a3 "$PORT" "$m2" ',"ollm_test_cold":true'
cmp3 par_cold_turn2 a3 s2 o2
grep -h '^C ' "$OUT/par.log" "$OUT/one.log" >>"$res"
# between requests the par server has exactly its N - 1 logits workers (the prefill workers live
# only inside a prefill); after SIGTERM to the server none of them may remain (no leak)
eval "pp=\$pid_par"
kids=$(pgrep -P "$pp" | tr '\n' ' ')
nk=$(echo $kids | wc -w)
if [ "$nk" -eq $((PAR - 1)) ]; then pass par_workers_idle "children=$nk [$kids]"; else fail par_workers_idle "children=$nk [$kids] want $((PAR - 1))"; fi
for p in $pids; do kill "$p" 2>/dev/null; done
for p in $pids; do wait "$p" 2>/dev/null; done
sleep 1
left=
for k in $kids; do kill -0 "$k" 2>/dev/null && left="$left $k"; done
if [ -z "$left" ]; then pass par_workers_gone_after_sigterm "workers=[$kids]"; else fail par_workers_gone_after_sigterm "left=[$left]"; fi
if [ $fails -eq 0 ]; then say "PAR_CHECK PASS"; exit 0; fi
say "PAR_CHECK FAIL fails=$fails"
exit 1
