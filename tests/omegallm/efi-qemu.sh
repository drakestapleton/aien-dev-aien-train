#!/bin/sh
# Boot a copy of an ollm UEFI image under QEMU (TCG) with OVMF as a USB stick, wait for the
# application to print `OLLM DONE`, press Enter for it (it waits for a key), and copy \OLLM back
# from the copy with mtools. EMULATED evidence only: this is not the iMac.
# Usage: sh tests/omegallm/efi-qemu.sh IMG OUTDIR [SECONDS]
# Env: CORES (taskset list, default 6), OVMF_CODE / OVMF_VARS (default /usr/share/OVMF/*_4M.fd).
# Writes OUTDIR/serial.log (the console: OVMF copies ConOut to the serial port) and OUTDIR/vol/, a
# copy of every file in \OLLM after the run (OUT.TXT and what the jobs wrote, e.g. TR.BIN, S.CK),
# with one `vol: SHA256 NAME` line each. Prints `done=1 seconds=S` when OLLM DONE was seen, `done=0`
# when the deadline passed or QEMU ended first (an ollm refusal ends the application before OLLM
# DONE; OUT.TXT then stops at that job). Under TCG on one GB10 core (core 7, MIDR 0x410fd851) the
# efi-job.txt run took 1006 s (evidence/OMEGALLM/efi/main/qemu.txt), so SECONDS defaults to 2700.
# Exit 0 only if OLLM DONE was seen and OUT.TXT was read.
set -u
[ $# -ge 2 ] || { echo "usage: efi-qemu.sh IMG OUTDIR [SECONDS]" >&2; exit 2; }
IMG=$1 OUT=$2 LIM=${3:-2700}
CORES=${CORES:-6}
CODE=${OVMF_CODE:-/usr/share/OVMF/OVMF_CODE_4M.fd}
VARS=${OVMF_VARS:-/usr/share/OVMF/OVMF_VARS_4M.fd}
mkdir -p "$OUT"
rm -f "$OUT/serial.log" "$OUT/mon"
cp "$IMG" "$OUT/disk.img"
cp "$VARS" "$OUT/vars.fd"
echo "qemu: $(qemu-system-x86_64 --version | head -1)"
echo "ovmf: $(sha256sum "$CODE" | cut -d' ' -f1) $(basename "$CODE")"
echo "image: $(sha256sum "$IMG" | cut -d' ' -f1)"
taskset -c "$CORES" nice -n 19 qemu-system-x86_64 -machine q35 -cpu max -m 2048 -smp 1 \
  -display none -vga std -nic none \
  -drive if=pflash,format=raw,readonly=on,file="$CODE" \
  -drive if=pflash,format=raw,file="$OUT/vars.fd" \
  -device qemu-xhci,id=xhci -drive if=none,id=stick,format=raw,file="$OUT/disk.img" \
  -device usb-storage,bus=xhci.0,drive=stick -device usb-kbd,bus=xhci.0 \
  -serial file:"$OUT/serial.log" -no-reboot -monitor unix:"$OUT/mon",server,nowait \
  > "$OUT/qemu.log" 2>&1 &
qp=$!
say() { printf '%s\n' "$1" | socat - unix-connect:"$OUT/mon" > /dev/null 2>&1 || true; }
t=0 done=0
while [ "$t" -lt "$LIM" ]; do
  sleep 1
  t=$((t + 1))
  if grep -aq 'OLLM DONE' "$OUT/serial.log" 2> /dev/null; then done=1; break; fi
  kill -0 "$qp" 2> /dev/null || break
done
if [ "$done" = 1 ]; then
  say "sendkey ret"
  sleep 5
fi
say quit
sleep 2
kill "$qp" 2> /dev/null
wait "$qp" 2> /dev/null
echo "done=$done seconds=$t"
rm -rf "$OUT/vol"
mkdir "$OUT/vol"
mcopy -n -i "$OUT/disk.img@@1M" '::/OLLM/*' "$OUT/vol/" 2> /dev/null
rm -f "$OUT/disk.img" "$OUT/vars.fd" "$OUT/mon"
for f in "$OUT"/vol/*; do
  [ -f "$f" ] && echo "vol: $(sha256sum "$f" | cut -d' ' -f1) $(basename "$f")"
done
[ -r "$OUT/vol/OUT.TXT" ] || { echo "OUT.TXT not readable"; exit 1; }
[ "$done" = 1 ]
