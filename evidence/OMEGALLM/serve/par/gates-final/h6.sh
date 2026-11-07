#!/bin/sh
# h6.sh: final-binary gates on core 6 (ports 18293, 18295)
B=$HOME/work/hive/ownmodel/servefast
S=/dev/shm/hive/ownmodel/servefast
R=$B/aien-train
O=$B/b5/ollm
M32=$HOME/work/hive/ownmodel/data/merges32k.bin
TXT=$HOME/data-omega/base/val.txt
cd "$R" || exit 1
mkdir -p $S/h
echo "start $(date -u +%FT%TZ) ollm $(sha256sum $O | cut -c1-64)"
for p in 1 2; do
	OLLM=$O CK=$S/../serve4/t.ck MERGES=$M32 OUT=$S/h/chat1-par$p CORES=6 PORT=18293 TPORT=18295 SARGS=par=$p sh tests/omegallm/serve-check.sh >$S/h/chat1-par$p.txt 2>&1
	echo "chat1 par=$p rc $? $(grep '^SUMMARY' $S/h/chat1-par$p.txt) $(date -u +%T)"
done
for b in ollm ollm-mut-lw; do
	OLLM=$B/b5/$b CK=$HOME/work/hive/ownmodel/ck/s2.ck MERGES=$M32 OUT=$S/h/life-$b TEXT=$TXT CORES=6 PORT=18293 sh tests/omegallm/serve-par-life.sh >$S/h/life-$b.txt 2>&1
	echo "life $b rc $? $(date -u +%T)"
done
OLLM=$O CK=$HOME/work/hive/ownmodel/wide4/ck/s1.ck MERGES=$M32 OUT=$S/h/par-s1 TEXT=$TXT CORES=6 PORT=18293 TPORT=18295 LEN=500 GEN=16 sh tests/omegallm/serve-par-check.sh >$S/h/par-s1.txt 2>&1
echo "par-check s1 rc $? $(date -u +%T)"
OLLM=$O CK=/tmp/gk/r10/run/ck60000.bin MERGES=/home/drakestapleton/handoffs/omega-llm-20261101/v1-data/merges4096.bin OUT=$S/h/v1-par2 CORES=6 PORT=18293 TPORT=18295 SARGS=par=2 sh tests/omegallm/serve-check.sh >$S/h/v1-par2.txt 2>&1
echo "v1 par=2 rc $? $(grep '^SUMMARY' $S/h/v1-par2.txt) $(date -u +%T)"
echo "done $(date -u +%FT%TZ)"
