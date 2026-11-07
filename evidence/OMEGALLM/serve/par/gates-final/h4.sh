#!/bin/sh
# h4.sh: final-binary gates needing core 4 (ports 18291, 18292), then both cores
B=$HOME/work/hive/ownmodel/servefast
S=/dev/shm/hive/ownmodel/servefast
R=$B/aien-train
O=$B/b5/ollm
M32=$HOME/work/hive/ownmodel/data/merges32k.bin
TXT=$HOME/data-omega/base/val.txt
cd "$R" || exit 1
mkdir -p $S/h
echo "start $(date -u +%FT%TZ) ollm $(sha256sum $O | cut -c1-64)"
OLLM=$O CK=/tmp/gk/r10/run/ck60000.bin MERGES=/home/drakestapleton/handoffs/omega-llm-20261101/v1-data/merges4096.bin OUT=$S/h/v1-par1 CORES=4 PORT=18291 TPORT=18292 SARGS=par=1 sh tests/omegallm/serve-check.sh >$S/h/v1-par1.txt 2>&1
echo "v1 par=1 rc $? $(grep '^SUMMARY' $S/h/v1-par1.txt) $(date -u +%T)"
while pgrep -f h6.sh >/dev/null; do sleep 5; done
OLLM=$O CK=$HOME/work/hive/ownmodel/ck/s2.ck MERGES=$M32 OUT=$S/h/par-s2 TEXT=$TXT CORES=4,6 PORT=18291 TPORT=18292 LEN=1500 GEN=24 sh tests/omegallm/serve-par-check.sh >$S/h/par-s2.txt 2>&1
echo "par-check s2 (par=2 vs par=1 same binary) rc $? $(date -u +%T)"
OLLM=$O ONE_OLLM=$B/b0/ollm CK=$HOME/work/hive/ownmodel/ck/s2.ck MERGES=$M32 OUT=$S/h/par-s2-old TEXT=$TXT CORES=4,6 PORT=18291 TPORT=18292 LEN=1500 GEN=24 sh tests/omegallm/serve-par-check.sh >$S/h/par-s2-old.txt 2>&1
echo "par-check s2 (par=2 vs the before-binary par=1) rc $? $(date -u +%T)"
for b in ollm ollm-mut-lw; do
	OLLM=$B/b5/$b CK=$HOME/work/hive/ownmodel/ck/s2.ck MERGES=$M32 OUT=$S/h/life2-$b TEXT=$TXT CORES=4,6 PORT=18291 sh tests/omegallm/serve-par-life.sh >$S/h/life2-$b.txt 2>&1
	echo "life $b rc $? $(date -u +%T)"
done
echo "done $(date -u +%FT%TZ)"
