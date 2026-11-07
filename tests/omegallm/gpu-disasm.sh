#!/bin/sh
# Disassemble the GB10 kernels that native/omegallm/gpu/ emits (rung 4), with nvdisasm as a read-only
# oracle. Builds the gb10 sources (gg.om's main renamed ggmain) plus tests/omegallm/gpu-dump.om, runs
# the dump on the CPU (no GPU), cuts slot N (16 KiB at N * 16384; two slots for the 64x64 GEMM ids 40-58, whose kernels
# span two), trims trailing zero bytes to a 16-byte multiple (an untrimmed slot disassembles its zero tail
# as illegal instructions) and prints the listing. Then it checks the slot's declared GPR count gkgpr
# (the dump's stderr, one byte per id) against the highest GPR in the listing: the hardware burns 2 GPRs
# of the QMD count for the program counter (Mesa NAK sm70.rs hw_reserved_gprs), so gkgpr must be at
# least max + 3, else the kernel hangs on the chip (evidence/OMEGALLM/gpu-k8 attempt 1). The max is an
# upper bound: a .128/.64/.WIDE opcode widens every register operand outside brackets, a bracketed
# R.64 counts as a pair. Prints "GPR s max R m need k declared d OK|LOW"; any LOW exits 4. Then
# "SMEM s target t" with the slot's QMD TARGET_SM_CONFIG hw value (gk.om gksmw; KiB = (t - 1) * 4).
# Usage: sh tests/omegallm/gpu-disasm.sh SLOT...   (0-7 GEMM 32x32, 9-24 gr.om, 25-26 fused-epilogue
#        GEMM 32x32, 27-36 BF16 GEMM 64x64 (27-34 plain, 35/36 fused epilogue), 40-54 even GEMM 64x64,
#        56/58 fused-epilogue GEMM 64x64)
# Env: OMC (default ../omega-mv/seed/out/omc), OUT (default ../build), NVDISASM
#      (default /usr/local/cuda/bin/nvdisasm), CORE (default 6), SHAPE (grset V T D H F B, default the
#      parity shape "256 32 64 2 128 2"; "4096 256 256 8 1024 8" is the max shape, whose T 256 gives
#      the softmax kernels 8 column chunks where the parity shape gives 1), V4 (1: v4 mode, g4.om).
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
# gk.om calls gb.om's BF16 check hooks and gb.om calls gg.om, so the dump takes the whole gb10 source;
# gg.om's main becomes ggmain (gpu-dump.om's main runs) and gg.om supplies model.om's ogmask hook.
cat "$src/math.om" "$src/data.om" "$src/lpool.om" "$src/model.om" "$src/adam.om" "$src/ckpt.om" "$src/bpe.om" "$src/cli.om" "$src/v4.om" "$src/lio.om" "$src/noserve.om" |
  sed 's/^fn main to int$/fn ocpumain to int/' > "$OUT/gpu-dump.om"
sed "s/^grset 256 32 64 2 128 2\$/grset $SHAPE/" "$here/tests/omegallm/gpu-dump.om" > "$OUT/gpu-dump-main.om"
grep -qx "grset $SHAPE" "$OUT/gpu-dump-main.om" || { echo "SHAPE_NOT_SET $SHAPE" >&2; exit 2; }
# V4=1 dumps the v4 mode (gr.om grd 6 = 1: slots 12, 17, 18, the D <= 1024 RMS banks and grall4's
# slots 60, 61; g4.om), T a multiple of 256
if [ "${V4:-0}" = 1 ]; then
  sed "s/^grset $SHAPE\$/grset $SHAPE\nput grd 6 1/;s/^if not grall\$/if not and grall grall4/" "$OUT/gpu-dump-main.om" > "$OUT/gpu-dump-main4.om"
  grep -qx "put grd 6 1" "$OUT/gpu-dump-main4.om" || { echo "V4_NOT_SET" >&2; exit 2; }
  mv "$OUT/gpu-dump-main4.om" "$OUT/gpu-dump-main.om"
fi
cat "$g/context.om" "$g/vector.om" "$g/launch.om" "$g/gk.om" "$g/gr.om" "$g/gb.om" >> "$OUT/gpu-dump.om"
n=$(grep -c '^fn main to int$' "$g/gg.om" || true)
[ "$n" = 1 ] || { echo "GG_MAIN_COUNT $n, want 1" >&2; exit 4; }
sed 's/^fn main to int$/fn ggmain to int/' "$g/gg.om" >> "$OUT/gpu-dump.om"
cat "$g/g4.om" >> "$OUT/gpu-dump.om"
cat "$OUT/gpu-dump-main.om" >> "$OUT/gpu-dump.om"
taskset -c "$CORE" nice -n 19 "$OMC" < "$OUT/gpu-dump.om" > "$OUT/gpu-dump"
chmod +x "$OUT/gpu-dump"
"$OUT/gpu-dump" > "$OUT/gpu-code.bin" 2> "$OUT/gpu-gpr.bin"
[ "$(wc -c < "$OUT/gpu-gpr.bin")" -eq 128 ] || { echo "GPR_TABLE_SIZE $(wc -c < "$OUT/gpu-gpr.bin")" >&2; exit 2; }
echo "DUMP $(sha256sum "$OUT/gpu-dump" | cut -d' ' -f1) source_sha256 $(sha256sum "$OUT/gpu-dump.om" | cut -d' ' -f1) code_sha256 $(sha256sum "$OUT/gpu-code.bin" | cut -d' ' -f1)"
for s in "$@"; do
  ns=1
  [ "$s" -ge 40 ] && [ "$s" -le 58 ] && ns=2
  dd if="$OUT/gpu-code.bin" of="$OUT/gpu-slot$s.bin" bs=16384 skip="$s" count="$ns" status=none
  last=$(od -An -v -tu1 "$OUT/gpu-slot$s.bin" | tr -s ' ' '\n' | awk 'NF { n++; if ($1 != 0) l = n } END { print l + 0 }')
  n=$(( (last + 15) / 16 * 16 ))
  head -c "$n" "$OUT/gpu-slot$s.bin" > "$OUT/gpu-slot$s.t.bin"
  echo "SLOT $s bytes $n sha256 $(sha256sum "$OUT/gpu-slot$s.t.bin" | cut -d' ' -f1)"
  [ "$n" -eq 0 ] && { echo "SLOT $s empty"; continue; }
  "$NVDISASM" -b SM121 "$OUT/gpu-slot$s.t.bin" > "$OUT/gpu-slot$s.sass"
  cat "$OUT/gpu-slot$s.sass"
  d=$(od -An -tu1 -j "$s" -N1 "$OUT/gpu-gpr.bin" | tr -d ' ')
  awk -v s="$s" -v d="$d" '
    function scan(x, ext,   t, e, v) {
      x = " " x
      while (match(x, /[^A-Za-z0-9_.]R[0-9]+(\.64)?/)) {
        t = substr(x, RSTART + 2, RLENGTH - 2); e = ext
        if (t ~ /\.64$/) { e = 1; sub(/\.64$/, "", t) }
        v = t + e; if (v > mx) mx = v
        x = substr(x, RSTART + RLENGTH)
      }
    }
    BEGIN { mx = -1 }
    match($0, /\/\*[0-9a-f]+\*\//) {
      r = substr($0, RSTART + RLENGTH); sub(/;.*/, "", r); sub(/^[ \t]+/, "", r)
      if (r ~ /^@/) sub(/^[^ \t]+[ \t]+/, "", r)
      op = r; sub(/[ \t].*/, "", op); sub(/^[^ \t]+/, "", r)
      w = 1; if (op ~ /\.128/) w = 4; else if (op ~ /\.64|\.WIDE/) w = 2
      while (match(r, /\[[^]]*\]/)) {
        p = RSTART; l = RLENGTH
        scan(substr(r, p, l), 0)
        r = substr(r, 1, p - 1) " " substr(r, p + l)
      }
      scan(r, w - 1)
    }
    END { k = mx + 3; printf "GPR %s max R%d need %d declared %d %s\n", s, mx, k, d, (d >= k ? "OK" : "LOW"); exit (d >= k ? 0 : 4) }
  ' "$OUT/gpu-slot$s.sass" || bad=1
  echo "SMEM $s target $(od -An -tu1 -j $((64 + s)) -N1 "$OUT/gpu-gpr.bin" | tr -d ' ')"
done
[ "${bad:-0}" -eq 0 ] || { echo "GPR_LOW" >&2; exit 4; }
