#!/bin/sh
# run1 driver (pre-registered in PREREG.md): one exclusive spark-window lease per leg, queued with
# --wait (first come, first served), until stage B step 7300, the first failure, or a stop rule.
# Stage A -> B between leases: tune4 on CPU core 5 (T 4096 B 4 G 1, TOTAL 7300, lr 0.001).
R=/home/drakestapleton/work/hive/ownmodel/run1
cd "$R" || exit 2
[ -f stage.txt ] || echo A > stage.txt
board() { flock /home/drakestapleton/handoffs/BOARD.md.lock sh -c "echo \"$1\" >> /home/drakestapleton/handoffs/BOARD.md"; }
i=$(wc -l < windows.txt 2>/dev/null || echo 0)
while :; do
  stage=$(cat stage.txt)
  cur=$(grep -h '^T ' "train-$stage.txt" 2>/dev/null | tail -n 1 | cut -d' ' -f2)
  if [ "$stage" = A ] && [ -n "$cur" ] && [ "$cur" -ge 24000 ]; then
    cp ck.bin ckA-final.bin
    taskset -c 5 nice -n 10 "$R/bin/ollm" tune4 ckA-final.bin ck.bin 7300 1000 4096 4 1 > tune-AB.txt 2>&1 || { echo "tune4 failed" >> windows.txt; exit 7; }
    echo B > stage.txt
    continue
  fi
  [ "$stage" = B ] && [ -n "$cur" ] && [ "$cur" -ge 7300 ] && break
  # stop rule S2: after stage-A step 6000 the held-out E must be below 5.5 nats/token
  e=$(grep -h '^E ' geval.txt 2>/dev/null | tail -n 1 | cut -d' ' -f4)
  st=$(grep -h '^step=' geval.txt 2>/dev/null | tail -n 1 | sed 's/^step=\([0-9]*\).*/\1/')
  if [ "$stage" = A ] && [ -n "$e" ] && [ -n "$st" ] && [ "$st" -ge 6000 ] && [ "$e" -ge 5500000 ]; then
    echo "STOP RULE S2: stage A step $st E $e >= 5500000" >> windows.txt; exit 5
  fi
  [ "$i" -ge 40 ] && { echo "leg cap 40 reached" >> windows.txt; exit 6; }
  i=$((i + 1)); n=own1-leg$i
  board "$(date -u +%Y-%m-%dT%H:%M:%SZ) ownmodel STARTING WINDOW $n (DRA-120/DRA-183 run1 S2 V32768 D384 L8 stage $stage BF16 gtrain4 leg from ${cur:-0} + geval4; --gb10 exclusive --quiet none --wait, <=20 min)"
  timeout 14400 spark-window open "$n" --ledger L904 --lease 20 --gb10 exclusive --quiet none --wait > "win-$i.txt" 2>&1
  o=$?
  r=99
  if [ $o -eq 0 ]; then
    spark-window run "$R/leg.sh" >> "win-$i.txt" 2>&1; r=$?
    spark-window close >> "win-$i.txt" 2>&1
  fi
  id=$(grep -o '20[0-9]\{6\}T[0-9]\{6\}Z-[0-9a-f]\{6\}' "win-$i.txt" | head -n 1)
  board "$(date -u +%Y-%m-%dT%H:%M:%SZ) ownmodel DONE WINDOW $n $id (open rc $o, leg rc $r)"
  echo "$n $id stage=$stage open=$o leg=$r" >> windows.txt
  [ $o -ne 0 ] && exit 3
  [ $r -ne 0 ] && exit 4
done
echo finished >> windows.txt
