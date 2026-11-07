#!/bin/sh
# gates.sh: the servefast gates on the final binary (cores 4,6; ports 18291-18293, 18295)
B=$HOME/work/hive/ownmodel/servefast
S=/dev/shm/hive/ownmodel/servefast
R=$B/aien-train
O=$B/b3/ollm
M32=$HOME/work/hive/ownmodel/data/merges32k.bin
TXT=$HOME/data-omega/base/val.txt
cd "$R" || exit 1
mkdir -p $S/g
echo "start $(date -u +%FT%TZ) ollm $(sha256sum $O | cut -c1-64)"
for p in 1 2; do
	OLLM=$O CK=$S/../serve4/t.ck MERGES=$M32 OUT=$S/g/chat1-par$p CORES=6 PORT=18293 TPORT=18295 SARGS=par=$p sh tests/omegallm/serve-check.sh >$S/g/chat1-par$p.txt 2>&1
	echo "chat1 par=$p rc $? $(grep '^SUMMARY' $S/g/chat1-par$p.txt) $(date -u +%T)"
done
OLLM=$O CK=/tmp/gk/r10/run/ck60000.bin MERGES=/home/drakestapleton/handoffs/omega-llm-20261101/v1-data/merges4096.bin OUT=$S/g/v1-par2 CORES=6 PORT=18293 TPORT=18295 SARGS=par=2 sh tests/omegallm/serve-check.sh >$S/g/v1-par2.txt 2>&1
echo "v1 par=2 rc $? $(grep '^SUMMARY' $S/g/v1-par2.txt) $(date -u +%T)"
