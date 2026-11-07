#!/bin/sh
# keep.sh OUTDIR DEST: copy a run.sh result's receipts (summary, per task pre/verify/hermes
# output/rc/ms and the chat request list) into DEST, plus the full wire of the first task.
set -u
o=$1 dst=$2
mkdir -p "$dst"
cp "$o/summary.txt" "$o/tasks.list" "$dst/"
first=
for d in "$o"/*/; do
	id=$(basename "$d")
	[ -f "$d/verify.txt" ] || continue
	[ -z "$first" ] && first=$id
	mkdir -p "$dst/$id"
	for f in pre.txt verify.txt prompt.txt hermes.out hermes.rc hermes.ms wire/chat.txt; do
		[ -f "$d/$f" ] && cp "$d/$f" "$dst/$id/$(echo "$f" | tr / -)"
	done
done
[ -n "$first" ] && cp -r "$o/$first/wire" "$dst/$first/wire"
exit 0
