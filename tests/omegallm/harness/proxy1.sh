#!/bin/sh
# proxy1.sh DIR HOST PORT: one HTTP/1.1 exchange, run by socat (runner proxy) per connection:
# reads one request from stdin, saves its head and exact body as DIR/req-N.head, DIR/req-N.body,
# forwards it to HOST:PORT and copies the answer to stdout and DIR/resp-N.raw (status line,
# headers and body as received). The upstream side is never half-closed (ignoreeof), so a server
# that reads a peer's EOF as "client left" keeps generating.
set -u
d=$1 up=$2:$3
cr=$(printf '\r')
exec 9>>"$d/.lock"
flock 9
n=$(($(cat "$d/.count" 2>/dev/null || echo 0) + 1))
echo $n >"$d/.count"
flock -u 9
cl=0
while IFS= read -r l; do
	l=${l%"$cr"}
	[ -z "$l" ] && break
	printf '%s\n' "$l" >>"$d/req-$n.head"
	case $l in [Cc]ontent-[Ll]ength:*) cl=$(echo ${l#*:}) ;; esac
done
head -c "$cl" >"$d/req-$n.body"
date +%s%N >"$d/req-$n.t0"
{ sed 's/$/\r/' "$d/req-$n.head"; printf '\r\n'; cat "$d/req-$n.body"; } >"$d/req-$n.wire"
socat -t 0.2 OPEN:"$d/req-$n.wire",rdonly,ignoreeof!!STDOUT TCP:"$up" | tee "$d/resp-$n.raw"
date +%s%N >"$d/resp-$n.t1"
rm -f "$d/req-$n.wire"
