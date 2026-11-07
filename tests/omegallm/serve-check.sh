#!/bin/sh
# serve-check.sh: run `ollm serve` on loopback and referee it with serve-check.py (DRA-119).
# Env: OLLM (an aarch64 build with serve, or a gb10 build), CK (checkpoint), MERGES (V > 256 merges),
# VERB (serve, default, or gserve on a gb10 build in a GPU window: the per-token forward on the chip),
# PORT (default 18291), TPORT (default 18292: a second server with `tplmax=4000 test=1`), CORES
# (taskset list, default 8-9), OUT (receipt directory), ALLEN (allen-chat system prompt, default
# /opt/allen-chat/system-prompt.txt; absent gives NOT_RUN). The servers run under
# taskset/nice/bwrap; this script stops only the PIDs it started. Exit 0 only when every check
# passes and both servers listened on 127.0.0.1 alone.
set -u
: "${OLLM:?}" "${CK:?}" "${MERGES:?}" "${OUT:?}"
PORT=${PORT:-18291}
TPORT=${TPORT:-18292}
CORES=${CORES:-8-9}
ALLEN=${ALLEN:-/opt/allen-chat/system-prompt.txt}
VERB=${VERB:-serve}
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$OUT"
bw="bwrap --dev-bind / / --dev /dev --bind /dev/shm /dev/shm --proc /proc --"
# gserve opens the chip through /dev/nvidia*, which a fresh --dev /dev does not hold
[ "$VERB" = gserve ] && bw="bwrap --dev-bind / / --proc /proc --"
{
	echo "date $(date -u +%FT%TZ)"
	echo "host $(hostname) $(uname -m)"
	echo "ollm $(sha256sum "$OLLM") verb $VERB"
	echo "ck $(sha256sum "$CK")"
	echo "merges $(sha256sum "$MERGES")"
	echo "referee $(sha256sum "$here/serve-check.py")"
	[ -r "$ALLEN" ] && echo "allen_prompt $(sha256sum "$ALLEN") $(wc -c <"$ALLEN") bytes"
} >"$OUT/env.txt"

pids=
spids=
bind_ok=1
# start NAME PORT [OPTIONS...]: launch one server, wait for its PORT line, record its listener
start() {
	name=$1
	port=$2
	shift 2
	taskset -c "$CORES" nice -n 10 $bw "$OLLM" "$VERB" "$port" "$CK" "$MERGES" "$@" >"$OUT/$name.log" 2>&1 &
	pid=$!
	pids="$pids $pid"
	i=0
	until grep -q "^PORT $port" "$OUT/$name.log" 2>/dev/null; do
		i=$((i + 1))
		if [ $i -gt 600 ] || ! kill -0 $pid 2>/dev/null; then
			echo "SERVE_START_FAIL $name"
			cat "$OUT/$name.log"
			stop
			exit 1
		fi
		sleep 0.1
	done
	ss -Hltnp "sport = :$port" >"$OUT/listen-$name.txt"
	# bwrap does not pass SIGTERM on: stop the listening ollm too, the one this script started
	spid=$(grep -o 'pid=[0-9]*' "$OUT/listen-$name.txt" | head -1 | cut -d= -f2)
	[ -n "$spid" ] && [ "$(readlink /proc/$spid/exe)" = "$(readlink -f "$OLLM")" ] && spids="$spids $spid"
	awk '{print $4}' "$OUT/listen-$name.txt" | grep -qv "^127\.0\.0\.1:$port$" && bind_ok=0
	[ -s "$OUT/listen-$name.txt" ] || bind_ok=0
}
stop() {
	for p in $pids $spids; do kill $p 2>/dev/null; done
	for p in $pids; do wait $p 2>/dev/null; done
	echo "stopped launchers=$pids servers=$spids" >>"$OUT/env.txt"
}

start server "$PORT"
start server-test "$TPORT" tplmax=4000 test=1
SERVE_TLOG="$OUT/server-test.log" taskset -c "$CORES" nice -n 10 $bw python3 "$here/serve-check.py" "$PORT" "$OLLM" "$CK" "$MERGES" "$TPORT" "$ALLEN" | tee "$OUT/referee.txt"
rc=$?
grep -q "^SUMMARY pass=[0-9]* fail=0$" "$OUT/referee.txt" || rc=1
stop
echo "bind_loopback_only $bind_ok $(cat "$OUT/listen-server.txt" "$OUT/listen-server-test.txt" | tr '\n' ' ')" | tee -a "$OUT/referee.txt"
[ $bind_ok -eq 1 ] || rc=1
if [ $rc -eq 0 ]; then echo "SERVE_CHECK PASS" | tee -a "$OUT/referee.txt"; else echo "SERVE_CHECK FAIL" | tee -a "$OUT/referee.txt"; fi
exit $rc
