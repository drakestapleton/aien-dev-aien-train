#!/bin/sh
# Build ollm-tok, the standalone own-BPE tokenizer program (tests/omegallm/tok/FORMAT.md), from
# native/omegallm/tok/*.om with the pinned seeded omc (omega-mv e5b32567, aarch64 Linux).
# Usage: sh tests/omegallm/tok/build.sh
# Env: OMC (default ../omega-mv/seed/out/omc beside this clone), OUT (default ../build beside it),
#      CORES (taskset core list, default 18-19; omc runs at nice 10).
# Units, in this order (a global must come before its first use): tkcore (format, chunker, encoder,
# decoder; host-free, small enough for a model unit to concatenate), tkio (the Linux platform unit
# and fn main), tkfit (merge learner, about 441 MiB of globals) and tkcli (the commands).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../.." && pwd)
src="$root/native/omegallm/tok"
OMC=${OMC:-$root/../omega-mv/seed/out/omc}
OUT=${OUT:-$root/../build}
CORES=${CORES:-18-19}
PIN=2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f
[ -x "$OMC" ] || { echo "tok/build: omc not found at $OMC (set OMC)" >&2; exit 2; }
got=$(sha256sum "$OMC" | cut -d' ' -f1)
[ "$got" = "$PIN" ] || { echo "tok/build: omc sha256 $got is not the pin $PIN" >&2; exit 2; }
mkdir -p "$OUT"
cat "$src/tkcore.om" "$src/tkio.om" "$src/tkfit.om" "$src/tkcli.om" > "$OUT/ollm-tok.om"
taskset -c "$CORES" nice -n 10 "$OMC" < "$OUT/ollm-tok.om" > "$OUT/ollm-tok.part" || {
    rc=$?; rm -f "$OUT/ollm-tok.part"; echo "tok/build: omc exit $rc" >&2; exit "$rc"; }
chmod 755 "$OUT/ollm-tok.part"
mv "$OUT/ollm-tok.part" "$OUT/ollm-tok"
echo "tok/build: $OUT/ollm-tok sha256 $(sha256sum "$OUT/ollm-tok" | cut -d' ' -f1) omc $PIN"
