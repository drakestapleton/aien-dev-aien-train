#!/bin/sh
# respond.sh DIR: one HTTP/1.1 exchange on stdin/stdout, run by socat (capture.sh) per connection.
# Saves the request head and exact body as DIR/req-N.head, DIR/req-N.body (N = 1, 2, ... in
# arrival order). GET answers a models list; POST .../chat/completions number K (1, 2, ...)
# answers DIR/script/K.json (stream false) or DIR/script/K.sse (stream true) when present, else
# DIR/script/default.json|.sse, else 400; other POSTs 404. A capture and protocol fixture only:
# every answer is scripted, never model output.
set -u
d=$1
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
reply() { # STATUS CTYPE FILE
	printf 'HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %s\r\nConnection: close\r\n\r\n' "$1" "$2" "$(wc -c <"$3")"
	cat "$3"
}
case $first in
GET*)
	printf '{"object":"list","data":[{"id":"ollm","object":"model","created":0,"owned_by":"ollm"}]}' >"$d/resp-$n.body"
	reply "200 OK" application/json "$d/resp-$n.body"
	exit 0 ;;
"POST "*/chat/completions*) ;;
*)
	printf '{"error":{"message":"not found","type":"invalid_request_error","param":null,"code":"not_found"}}' >"$d/resp-$n.body"
	reply "404 Not Found" application/json "$d/resp-$n.body"
	exit 0 ;;
esac
flock 9
k=$(($(cat "$d/.chat" 2>/dev/null || echo 0) + 1))
echo $k >"$d/.chat"
flock -u 9
echo "$n" >"$d/chat-$k.n"
ext=json; ct=application/json
grep -q '"stream": *true' "$d/req-$n.body" && { ext=sse; ct=text/event-stream; }
f=$d/script/$k.$ext
[ -r "$f" ] || f=$d/script/default.$ext
if [ -r "$f" ]; then
	cp "$f" "$d/resp-$n.body"
	reply "200 OK" $ct "$d/resp-$n.body"
else
	printf '{"error":{"message":"capture only","type":"invalid_request_error","param":null,"code":"capture"}}' >"$d/resp-$n.body"
	reply "400 Bad Request" application/json "$d/resp-$n.body"
fi
