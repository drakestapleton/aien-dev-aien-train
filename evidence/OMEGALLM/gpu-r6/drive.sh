#!/bin/sh
# drive rung-6 legs, one spark-window per leg, until step 30000 or the first failure
cd /tmp/gk/r6 || exit 2
i=0
while :; do
  cur=$(grep -h '^T ' train.txt 2>/dev/null | tail -n 1 | cut -d' ' -f2)
  [ -n "$cur" ] && [ "$cur" -ge 30000 ] && break
  i=$((i + 1)); n=gg-r6t$i
  echo "$(date -u +%Y-%m-%dT%H:%MZ) omp-ollm STARTING $n WINDOW (rung 6 gtrainf leg from ${cur:-0} + geval, ~12 min, --quiet none)" >> ~/handoffs/BOARD.md
  touch /tmp/aien-q36-live-down-for-tests
  timeout 3600 spark-window open $n --ledger omp-ollm-$n --lease 20 --gb10 shared --quiet none --wait > win-$i.txt 2>&1
  o=$?
  r=99
  if [ $o -eq 0 ]; then
    spark-window run /tmp/gk/r6/leg.sh >> win-$i.txt 2>&1; r=$?
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
