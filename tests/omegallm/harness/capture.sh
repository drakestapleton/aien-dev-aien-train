#!/bin/sh
# capture.sh PORT DIR TOOLSETS QUERYFILE: serve respond.sh on 127.0.0.1:PORT (socat, one child
# per connection), run one Hermes oneshot (hermes1.sh) against it in DIR/work, stop the
# listener. DIR receives req-N.head/body, resp-N.body and hermes.{out,rc,ms}; DIR/script holds
# optional scripted answers (respond.sh). Capture and protocol fixture only.
set -u
here=$(cd "$(dirname "$0")" && pwd)
port=$1 d=$2 ts=$3 q=$4
mkdir -p "$d/work"
taskset -c "${CORES:-6}" nice -n 10 socat TCP-LISTEN:"$port",bind=127.0.0.1,reuseaddr,fork \
	EXEC:"sh $here/respond.sh $d" &
sp=$!
i=0
until ss -Hltn "sport = :$port" | grep -q .; do i=$((i + 1)); [ $i -gt 50 ] && break; sleep 0.1; done
sh "$here/hermes1.sh" "http://127.0.0.1:$port/v1" "$d/work" "$q" "$ts" "${TMO:-120}" "$d/hermes"
kill $sp
wait $sp 2>/dev/null
exit 0
