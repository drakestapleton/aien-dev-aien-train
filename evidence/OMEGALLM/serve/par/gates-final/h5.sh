B=$HOME/work/hive/ownmodel/servefast
S=/dev/shm/hive/ownmodel/servefast
cd $B/aien-train || exit 1
for b in ollm ollm-mut-lw; do
	OLLM=$B/b5/$b CK=$HOME/work/hive/ownmodel/ck/s2.ck MERGES=$HOME/work/hive/ownmodel/data/merges32k.bin OUT=$S/h/life3-$b TEXT=$HOME/data-omega/base/val.txt CORES=4,6 PORT=18291 sh tests/omegallm/serve-par-life.sh >$S/h/life3-$b.txt 2>&1
	echo "life $b rc $? $(date -u +%T)"
done
