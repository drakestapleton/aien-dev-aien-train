#!/bin/sh
# Disassemble the GB10 kernels that native/omegallm/gpu/ emits (rung 4), with nvdisasm as a read-only
# oracle. Builds the gb10 sources without gg.om plus tests/omegallm/gpu-dump.om, runs the dump on the
# CPU (no GPU), cuts slot N (16 KiB at N * 16384), trims trailing zero bytes to a 16-byte multiple
# (an untrimmed slot disassembles its zero tail as illegal instructions) and prints the listing.
# Usage: sh tests/omegallm/gpu-disasm.sh SLOT...   (0-7 GEMM 32x32, 9-24 gr.om, 32-39 GEMM 64x64)
# Env: OMC (default ../omega-mv/seed/out/omc), OUT (default ../build), NVDISASM
#      (default /usr/local/cuda/bin/nvdisasm), CORE (default 6), SHAPE (grset V T D H F B, default the
#      parity shape "256 32 64 2 128 2"; "4096 256 256 8 1024 8" is the max shape, whose T 256 gives
#      the softmax kernels 8 column chunks where the parity shape gives 1).
set -eu
here=$(cd "$(dirname "$0")/../.." && pwd)
PIN=2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f
OMC=${OMC:-$here/../omega-mv/seed/out/omc}
OUT=${OUT:-$here/../build}
NVDISASM=${NVDISASM:-/usr/local/cuda/bin/nvdisasm}
CORE=${CORE:-6}
SHAPE=${SHAPE:-256 32 64 2 128 2}
[ $# -ge 1 ] || { echo "usage: gpu-disasm.sh SLOT..." >&2; exit 2; }
got=$(sha256sum "$OMC" | cut -d' ' -f1)
[ "$got" = "$PIN" ] || { echo "OMC_PIN_MISMATCH $got" >&2; exit 3; }
mkdir -p "$OUT"
src=$here/native/omegallm
g=$src/gpu
# The dump has no gg.om, so model.om's ogmask hook comes from nogpu.om (never reached here).
cat "$src/math.om" "$src/data.om" "$src/model.om" "$src/adam.om" "$src/ckpt.om" "$src/bpe.om" "$src/cli.om" "$src/lio.om" "$src/nogpu.om" |
  sed 's/^fn main to int$/fn ocpumain to int/' > "$OUT/gpu-dump.om"
sed "s/^grset 256 32 64 2 128 2\$/grset $SHAPE/" "$here/tests/omegallm/gpu-dump.om" > "$OUT/gpu-dump-main.om"
grep -qx "grset $SHAPE" "$OUT/gpu-dump-main.om" || { echo "SHAPE_NOT_SET $SHAPE" >&2; exit 2; }
cat "$g/context.om" "$g/vector.om" "$g/launch.om" "$g/gk.om" "$g/gr.om" "$OUT/gpu-dump-main.om" >> "$OUT/gpu-dump.om"
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
  [ "$n" -eq 0 ] && { echo "SLOT $s empty"; continue; }
  "$NVDISASM" -b SM121 "$OUT/gpu-slot$s.t.bin"
done
