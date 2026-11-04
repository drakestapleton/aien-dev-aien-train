#!/bin/sh
# drive rung-9 legs (BF16 gtrainb, rung-7 schedule), one spark-window per leg, until step 30000, the first failure, or the
# pre-registered step-2000 stop rule (chip geval at 2000 must be at most 1765719 micro-nats, CONTRACT-BF16 4.4)
cd /tmp/gk/r9/run || exit 2
i=$(wc -l < windows.txt 2>/dev/null || echo 0)
while :; do
  cur=$(grep -h '^T ' train.txt 2>/dev/null | tail -n 1 | cut -d' ' -f2)
  [ -n "$cur" ] && [ "$cur" -ge 30000 ] && break
  if [ -n "$cur" ] && [ "$cur" -ge 2000 ]; then
    e=$(grep -A3 '^step=2000 ' geval.txt | grep '^E ' | cut -d' ' -f4)
    [ -z "$e" ] && { echo "no step-2000 E line" >> windows.txt; exit 6; }
    [ "$e" -le 1765719 ] || { echo "STOP RULE: step-2000 E $e above 1765719" >> windows.txt; exit 5; }
  fi
  i=$((i + 1)); n=gg-r9t$i
  echo "$(date -u +%Y-%m-%dT%H:%MZ) omp-ollm STARTING $n WINDOW (rung 9 v2-shape BF16 gtrainb leg, rung-7 schedule, from ${cur:-0} + geval, ~12 min, --quiet none)" >> ~/handoffs/BOARD.md
  touch /tmp/aien-q36-live-down-for-tests
  timeout 3600 spark-window open $n --ledger omp-ollm-$n --lease 22 --gb10 shared --quiet none --wait > win-$i.txt 2>&1
  o=$?
  r=99
  if [ $o -eq 0 ]; then
    spark-window run /tmp/gk/r9/run/leg.sh >> win-$i.txt 2>&1; r=$?
    spark-window close >> win-$i.txt 2>&1
  fi
  id=$(grep -o '20[0-9]\{6\}T[0-9]\{6\}Z-[0-9a-f]\{6\}' win-$i.txt | head -n 1)
  echo "$(date -u +%Y-%m-%dT%H:%MZ) omp-ollm DONE WINDOW $n $id closed (open rc $o, leg rc $r)" >> ~/handoffs/BOARD.md
  rm -f /tmp/aien-q36-live-down-for-tests
  echo "$n $id open=$o leg=$r" >> windows.txt
  [ $o -ne 0 ] && exit 3
  [ $r -ne 0 ] && exit 4
done
echo finished >> windows.txt
