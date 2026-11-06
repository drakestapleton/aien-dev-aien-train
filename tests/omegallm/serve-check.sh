#!/bin/sh
# serve-check.sh: run `ollm serve` on loopback and referee it with serve-check.py (DRA-119).
# Env: OLLM (an aarch64 build with serve), CK (checkpoint), MERGES (V > 256 merges), PORT (default
# 18291), CORES (taskset list, default 8-9), OUT (receipt directory). The server runs under
# taskset/nice/bwrap; this script stops only the PID it started. Exit 0 only when every check
# passes and the server listened on 127.0.0.1 alone.
set -u
: "${OLLM:?}" "${CK:?}" "${MERGES:?}" "${OUT:?}"
PORT=${PORT:-18291}
CORES=${CORES:-8-9}
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$OUT"
bw="bwrap --dev-bind / / --dev /dev --bind /dev/shm /dev/shm --proc /proc --"
{
	echo "date $(date -u +%FT%TZ)"
	echo "host $(hostname) $(uname -m)"
	echo "ollm $(sha256sum "$OLLM")"
	echo "ck $(sha256sum "$CK")"
	echo "merges $(sha256sum "$MERGES")"
	echo "referee $(sha256sum "$here/serve-check.py")"
} >"$OUT/env.txt"
taskset -c "$CORES" nice -n 10 $bw "$OLLM" serve "$PORT" "$CK" "$MERGES" >"$OUT/server.log" 2>&1 &
pid=$!
i=0
until grep -q "^PORT $PORT" "$OUT/server.log" 2>/dev/null; do
	i=$((i + 1))
	if [ $i -gt 600 ] || ! kill -0 $pid 2>/dev/null; then
		echo "SERVE_START_FAIL"
		cat "$OUT/server.log"
		kill $pid 2>/dev/null
		exit 1
	fi
	sleep 0.1
done
ss -Hltnp "sport = :$PORT" >"$OUT/listen.txt"
# bwrap does not pass SIGTERM on: stop the listening ollm too, the one this script started
spid=$(grep -o 'pid=[0-9]*' "$OUT/listen.txt" | head -1 | cut -d= -f2)
[ -n "$spid" ] && [ "$(readlink /proc/$spid/exe)" = "$(readlink -f "$OLLM")" ] || spid=
bind_ok=1
awk '{print $4}' "$OUT/listen.txt" | grep -qv "^127\.0\.0\.1:$PORT$" && bind_ok=0
[ -s "$OUT/listen.txt" ] || bind_ok=0
taskset -c "$CORES" nice -n 10 $bw python3 "$here/serve-check.py" "$PORT" "$OLLM" "$CK" "$MERGES" | tee "$OUT/referee.txt"
rc=$?
grep -q "^SUMMARY pass=[0-9]* fail=0$" "$OUT/referee.txt" || rc=1
kill $pid
[ -n "$spid" ] && kill $spid
wait $pid 2>/dev/null
echo "stopped launcher=$pid server=${spid:-none}" >>"$OUT/env.txt"
echo "bind_loopback_only $bind_ok $(cat "$OUT/listen.txt")" | tee -a "$OUT/referee.txt"
[ $bind_ok -eq 1 ] || rc=1
if [ $rc -eq 0 ]; then echo "SERVE_CHECK PASS" | tee -a "$OUT/referee.txt"; else echo "SERVE_CHECK FAIL" | tee -a "$OUT/referee.txt"; fi
exit $rc
