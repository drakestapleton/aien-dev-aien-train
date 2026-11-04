#!/bin/sh
# open spark-window bf-t1 (queued behind any rung-8 leg, first come first served), run t1/run.sh, close
cd /dev/shm/ollm-bf/chip/t1 || exit 2
sha256sum -c prereg.sha256 > win.txt 2>&1 || exit 7
echo "$(date -u +%Y-%m-%dT%H:%MZ) omp-ollm STARTING bf-t1 WINDOW (BF16 profile + gtrainb 0->250->2000 from rung-7 start, pre-registered aien-train f28e6ad, g1 gates all PASS, ~25 min, --quiet none)" >> ~/handoffs/BOARD.md
timeout 7200 spark-window open bf-t1 --ledger omp-ollm-bf-t1 --lease 40 --gb10 shared --quiet none --wait >> win.txt 2>&1
o=$?
r=99
if [ $o -eq 0 ]; then
  spark-window run sh /dev/shm/ollm-bf/chip/t1/run.sh >> win.txt 2>&1; r=$?
  spark-window close >> win.txt 2>&1
fi
id=$(grep -o '20[0-9]\{6\}T[0-9]\{6\}Z-[0-9a-f]\{6\}' win.txt | head -n 1)
echo "$(date -u +%Y-%m-%dT%H:%MZ) omp-ollm DONE WINDOW bf-t1 $id closed (open rc $o, run rc $r)" >> ~/handoffs/BOARD.md
echo "bf-t1 $id open=$o run=$r"
