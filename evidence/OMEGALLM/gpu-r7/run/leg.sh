#!/bin/sh
# one rung-7 leg: gtrainf to the next stop, then geval of the saved checkpoint
D=~/handoffs/omega-llm-20261101/v1-data
B=/tmp/gk/r7/gpu2/ollm-gb10
S=3000
cd /tmp/gk/r7/run || exit 2
cur=$(grep -h '^T ' train.txt 2>/dev/null | tail -n 1 | cut -d' ' -f2)
[ -z "$cur" ] && cur=0
if [ "$cur" -eq 0 ]; then u=250; else u=$((cur + S)); fi
for m in 2000 9000 30000; do [ $cur -lt $m ] && [ $u -gt $m ] && u=$m; done
echo "from=$cur until=$u binary=$(sha256sum $B | cut -c1-16)" >> train.txt
date -u +%s%N >> train.txt
timeout 1100 $B gtrainf ck.bin $D/train.tok $u 250 >> train.txt 2>&1
r=$?
echo rc=$r >> train.txt
date -u +%s%N >> train.txt
[ $r -ne 0 ] && exit $r
case $u in 2000|9000|30000) cp ck.bin ck$u.bin ;; esac
{ echo "step=$u ck=$(sha256sum ck.bin | cut -c1-64)"; date -u +%s%N
  timeout 300 $B geval ck.bin $D/held.tok 2243 $D/merges4096.bin 2>&1; echo rc=$?; date -u +%s%N; } >> geval.txt
exit 0
