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
OLLM=$O CK=/tmp/gk/r10/run/ck60000.bin MERGES=/home/drakestapleton/handoffs/omega-llm-20261101/v1-data/merges4096.bin OUT=$S/g/v1-par1 CORES=4 PORT=18291 TPORT=18292 SARGS=par=1 sh tests/omegallm/serve-check.sh >$S/g/v1-par1.txt 2>&1
echo "v1 par=1 rc $? $(grep '^SUMMARY' $S/g/v1-par1.txt) $(date -u +%T)"
OLLM=$O CK=$HOME/work/hive/ownmodel/wide4/ck/s1.ck MERGES=$M32 OUT=$S/g/par-s1 TEXT=$TXT CORES=4 PORT=18291 TPORT=18292 LEN=500 GEN=16 sh tests/omegallm/serve-par-check.sh >$S/g/par-s1.txt 2>&1
echo "par-check s1 rc $? $(date -u +%T)"
