#!/bin/sh
# proxy1.sh DIR HOST PORT [INJDIR]: one HTTP/1.1 exchange, run by socat (the runner's logging
# proxy) per connection: reads one request from stdin, saves its head and exact body as
# DIR/req-N.head, DIR/req-N.body, forwards it to HOST:PORT and copies the answer to stdout and
# DIR/resp-N.raw (status line, headers and body as received). The upstream side is never
# half-closed (ignoreeof), so a server that reads a peer's EOF as "client left" keeps generating.
# INJDIR (protocol checks against `ollm serve ... test=1` only): the K-th chat completion POST
# gets the member "ollm_test_output" set to the bytes of INJDIR/K.txt (else INJDIR/default.txt)
# before it is forwarded; the forwarded body is saved as DIR/req-N.sent. Never used for a
# capability run: the answer is then scripted, not generated.
set -u
d=$1 up=$2:$3 inj=${4:-}
cr=$(printf '\r')
exec 9>>"$d/.lock"
flock 9
n=$(($(cat "$d/.count" 2>/dev/null || echo 0) + 1))
echo $n >"$d/.count"
flock -u 9
cl=0
first=
while IFS= read -r l; do
	l=${l%"$cr"}
	[ -z "$first" ] && first=$l
	[ -z "$l" ] && break
	printf '%s\n' "$l" >>"$d/req-$n.head"
	case $l in [Cc]ontent-[Ll]ength:*) cl=$(echo ${l#*:}) ;; esac
done
head -c "$cl" >"$d/req-$n.body"
date +%s%N >"$d/req-$n.t0"
sent=$d/req-$n.body
case $first in
"POST "*/chat/completions*)
	if [ -n "$inj" ]; then
		flock 9
		k=$(($(cat "$d/.chat" 2>/dev/null || echo 0) + 1))
		echo $k >"$d/.chat"
		flock -u 9
		f=$inj/$k.txt
		[ -r "$f" ] || f=$inj/default.txt
		if [ -r "$f" ]; then
			jq -cj --rawfile o "$f" '. + {ollm_test_output: $o}' "$d/req-$n.body" >"$d/req-$n.sent"
			sent=$d/req-$n.sent
		fi
	fi ;;
esac
{
	grep -iv '^content-length:' "$d/req-$n.head" | sed 's/$/\r/'
	printf 'Content-Length: %s\r\n\r\n' "$(wc -c <"$sent")"
	cat "$sent"
} >"$d/req-$n.wire"
socat -t 0.2 OPEN:"$d/req-$n.wire",rdonly,ignoreeof!!STDOUT TCP:"$up" | tee "$d/resp-$n.raw"
date +%s%N >"$d/resp-$n.t1"
rm -f "$d/req-$n.wire"
