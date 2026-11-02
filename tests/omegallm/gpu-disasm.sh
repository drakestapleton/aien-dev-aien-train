#!/bin/sh
# Disassemble the GB10 kernels that native/omegallm/gpu/ emits (rung 4), with nvdisasm as a read-only
# oracle. Builds the gb10 sources without gg.om plus tests/omegallm/gpu-dump.om, runs the dump on the
# CPU (no GPU), cuts slot N (16 KiB at N * 16384), trims trailing zero bytes to a 16-byte multiple
# (an untrimmed slot disassembles its zero tail as illegal instructions) and prints the listing.
# Usage: sh tests/omegallm/gpu-disasm.sh SLOT...   (23 = SQN, 24 = ADAM)
# Env: OMC (default ../omega-mv/seed/out/omc), OUT (default ../build), NVDISASM
#      (default /usr/local/cuda/bin/nvdisasm), CORE (default 6).
set -eu
here=$(cd "$(dirname "$0")/../.." && pwd)
PIN=2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f
OMC=${OMC:-$here/../omega-mv/seed/out/omc}
OUT=${OUT:-$here/../build}
NVDISASM=${NVDISASM:-/usr/local/cuda/bin/nvdisasm}
CORE=${CORE:-6}
[ $# -ge 1 ] || { echo "usage: gpu-disasm.sh SLOT..." >&2; exit 2; }
got=$(sha256sum "$OMC" | cut -d' ' -f1)
[ "$got" = "$PIN" ] || { echo "OMC_PIN_MISMATCH $got" >&2; exit 3; }
mkdir -p "$OUT"
src=$here/native/omegallm
g=$src/gpu
cat "$src/math.om" "$src/data.om" "$src/model.om" "$src/adam.om" "$src/ckpt.om" "$src/bpe.om" "$src/cli.om" "$src/lio.om" |
  sed 's/^fn main to int$/fn ocpumain to int/' > "$OUT/gpu-dump.om"
cat "$g/context.om" "$g/vector.om" "$g/launch.om" "$g/gk.om" "$g/gr.om" "$here/tests/omegallm/gpu-dump.om" >> "$OUT/gpu-dump.om"
taskset -c "$CORE" nice -n 19 "$OMC" < "$OUT/gpu-dump.om" > "$OUT/gpu-dump"
chmod +x "$OUT/gpu-dump"
"$OUT/gpu-dump" > "$OUT/gpu-code.bin"
echo "DUMP $(sha256sum "$OUT/gpu-dump" | cut -d' ' -f1) source_sha256 $(sha256sum "$OUT/gpu-dump.om" | cut -d' ' -f1) code_sha256 $(sha256sum "$OUT/gpu-code.bin" | cut -d' ' -f1)"
for s in "$@"; do
  dd if="$OUT/gpu-code.bin" of="$OUT/gpu-slot$s.bin" bs=16384 skip="$s" count=1 status=none
  last=$(od -An -v -tu1 "$OUT/gpu-slot$s.bin" | tr -s ' ' '\n' | awk 'NF { n++; if ($1 != 0) l = n } END { print l + 0 }')
  n=$(( (last + 15) / 16 * 16 ))
  head -c "$n" "$OUT/gpu-slot$s.bin" > "$OUT/gpu-slot$s.t.bin"
  echo "SLOT $s bytes $n sha256 $(sha256sum "$OUT/gpu-slot$s.t.bin" | cut -d' ' -f1)"
  "$NVDISASM" -b SM121 "$OUT/gpu-slot$s.t.bin"
done
