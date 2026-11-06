#!/bin/sh
# measure.sh MERGES OLLMTOK LABEL=BODY ...: one row per captured chat request body:
# `LABEL bytes tokens markers msgs tools`, tokens = CHAT1 tokens with tools and the generation
# prompt, counted by `ollm-tok tokenc chat` on chat1-render.sh's text (APPROX until `ollm
# chatenc` lands; equal to the per-segment raw sum when no content holds a marker string).
set -u
here=$(cd "$(dirname "$0")" && pwd)
m=$1 tk=$2
shift 2
tmp=${TMPDIR:-/tmp}/measure.$$
for a in "$@"; do
	lab=${a%%=*} b=${a#*=}
	sh "$here/chat1-render.sh" "$b" >"$tmp.txt" || { echo "$lab RENDER_FAIL"; continue; }
	e=$(taskset -c "${CORES:-6}" nice -n 10 "$tk" tokenc chat "$m" "$tmp.txt" "$tmp.u16")
	echo "$lab $(wc -c <"$b") $(echo "$e" | awk '{print $5, $6}') $(jq '.messages|length' "$b") $(jq '.tools // [] | length' "$b")"
done
rm -f "$tmp.txt" "$tmp.u16"
