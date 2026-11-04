#!/bin/sh
# open spark-window v3-g1 (queued, first come first served), run run.sh, close.
# Run from this directory: sh window.sh
cd "$(dirname "$0")" || exit 2
E=$(pwd)
sha256sum -c prereg.sha256 > win.txt 2>&1 || exit 7
echo "$(date -u +%Y-%m-%dT%H:%MZ) omp-ollm STARTING v3-g1 WINDOW (v3 integrated: f32 regressions, L16 gcmp2/gacmp, BF16 gates; pre-registered aien-train evidence/OMEGALLM/v3/chip-g1, ~45 min, --quiet none)" >> ~/handoffs/BOARD.md
timeout 7200 spark-window open v3-g1 --ledger omp-ollm-v3-g1 --lease 75 --gb10 shared --quiet none --wait >> win.txt 2>&1
o=$?
r=99
if [ $o -eq 0 ]; then
  spark-window run sh $E/run.sh >> win.txt 2>&1; r=$?
  spark-window close >> win.txt 2>&1
fi
id=$(grep -o '20[0-9]\{6\}T[0-9]\{6\}Z-[0-9a-f]\{6\}' win.txt | head -n 1)
echo "$(date -u +%Y-%m-%dT%H:%MZ) omp-ollm DONE WINDOW v3-g1 $id closed (open rc $o, run rc $r)" >> ~/handoffs/BOARD.md
echo "v3-g1 $id open=$o run=$r"
