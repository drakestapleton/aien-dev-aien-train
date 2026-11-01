#!/bin/sh
# Compose the ollm UEFI boot image (aien-train#52): a GPT disk with one FAT EFI system partition
# holding \EFI\BOOT\BOOTX64.EFI (the x86efi ollm) and the job files under \OLLM.
# Usage: sh tests/omegallm/efi-image.sh EFI IMG SRC:NAME...
#   each SRC:NAME copies file SRC to \OLLM\NAME; one NAME must be JOB.TXT.
# Env: IMAC_IMAGE (required): the Omega-built imac-image tool, which writes imac-boot.img (96 MiB
#      GPT + FAT, partition 1 at sector 2048) around ./BOOTX64.EFI in the current directory.
# mtools (mmd, mcopy) adds the \OLLM files and reads every member back (cmp) before IMG is
# published; IMG must not exist yet. Prints every member's sha256, then the image's.
# File dates come from SOURCE_DATE_EPOCH (default 1793491200 = 2026-11-01T00:00:00Z), so the same
# inputs give the same image bytes.
set -eu
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-1793491200}"
[ $# -ge 3 ] || { echo "usage: efi-image.sh EFI IMG SRC:NAME..." >&2; exit 2; }
EFI=$1 IMG=$2
shift 2
[ -n "${IMAC_IMAGE:-}" ] && [ -x "$IMAC_IMAGE" ] || { echo "IMAC_IMAGE must name the imac-image tool" >&2; exit 2; }
[ ! -e "$IMG" ] || { echo "fresh output required: $IMG exists" >&2; exit 73; }
[ -f "$EFI" ] || { echo "missing $EFI" >&2; exit 66; }
job=0
for m in "$@"; do
  src=${m%:*} name=${m##*:}
  [ "$src" != "$m" ] && [ -n "$name" ] || { echo "member must be SRC:NAME: $m" >&2; exit 2; }
  [ -f "$src" ] || { echo "missing $src" >&2; exit 66; }
  [ "$name" != JOB.TXT ] || job=1
done
[ "$job" = 1 ] || { echo "no member named JOB.TXT" >&2; exit 2; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
cp "$EFI" "$tmp/BOOTX64.EFI"
(cd "$tmp" && "$IMAC_IMAGE" > imac-image.log 2>&1) || { cat "$tmp/imac-image.log" >&2; exit 1; }
d="$tmp/imac-boot.img@@1M"
mmd -i "$d" ::/OLLM
check() {
  mcopy -n -i "$d" "::/$1" "$tmp/back"
  cmp "$tmp/back" "$2" || { echo "readback differs: $1" >&2; exit 1; }
  rm -f "$tmp/back"
  echo "$(sha256sum "$2" | cut -d' ' -f1)  ::/$1"
}
check EFI/BOOT/BOOTX64.EFI "$EFI"
for m in "$@"; do
  mcopy -i "$d" "${m%:*}" "::/OLLM/${m##*:}"
  check "OLLM/${m##*:}" "${m%:*}"
done
mv "$tmp/imac-boot.img" "$IMG"
echo "$(sha256sum "$IMG" | cut -d' ' -f1)  $(basename "$IMG")"
