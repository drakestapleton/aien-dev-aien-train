#!/bin/sh
# open spark-window bf-g1 (queued behind any rung-8 leg, first come first served), run g1/run.sh, close
cd /dev/shm/ollm-bf/chip/g1 || exit 2
sha256sum -c prereg.sha256 > win.txt 2>&1 || exit 7
echo "$(date -u +%Y-%m-%dT%H:%MZ) omp-ollm STARTING bf-g1 WINDOW (BF16 gates gbfrag/gbcmp/gbcmp2 + f32 regressions, pre-registered aien-train f28e6ad, ~40 min, --quiet none)" >> ~/handoffs/BOARD.md
timeout 7200 spark-window open bf-g1 --ledger omp-ollm-bf-g1 --lease 40 --gb10 shared --quiet none --wait >> win.txt 2>&1
o=$?
r=99
if [ $o -eq 0 ]; then
  spark-window run sh /dev/shm/ollm-bf/chip/g1/run.sh >> win.txt 2>&1; r=$?
  spark-window close >> win.txt 2>&1
fi
id=$(grep -o '20[0-9]\{6\}T[0-9]\{6\}Z-[0-9a-f]\{6\}' win.txt | head -n 1)
echo "$(date -u +%Y-%m-%dT%H:%MZ) omp-ollm DONE WINDOW bf-g1 $id closed (open rc $o, run rc $r)" >> ~/handoffs/BOARD.md
echo "bf-g1 $id open=$o run=$r"
