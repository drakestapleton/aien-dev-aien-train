#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Identity-line edge cases for the ollm UEFI build (CONTRACT section 9): boot EFI under QEMU/OVMF with
# a one-job JOB.TXT (adamck) and check the second OUT.TXT line for a CPUID brand string of only NULs
# or only blanks and for SMBIOS type 1 strings or structures that end before what eio.om reads.
# EMULATED evidence only: this is not the iMac.
# Usage: sh tests/omegallm/efi-ident.sh EFI OUTDIR
# Env: IMAC_IMAGE (required; see efi-image.sh), CORES (taskset list for QEMU, default 6).
# Cases (the SMBIOS ones on machine q35,smbios-entry-point-type=64 with one raw -smbios file, which
# QEMU puts first; it adds no type 1 of its own when the file starts with one):
#   nul      -cpu max,model-id=              (brand all NULs)             cpu=-
#   blank    -cpu max,model-id=<48 blanks>                                cpu=-
#   n2       type 1 whose Version names string 3 of a one-string set      smbios=OmegaTest/-/-
#   capwalk  type 1 Version 255 followed by 2 x 100 strings of 60 bytes   smbios=OmegaTest/-/-
#   capscan  5 x type 11 with 255 strings (77805 bytes), no type 1 under the 64 KiB copy  smbios=-/-/-
# A case passes when the console shows OLLM DONE and no trap (`failed to start ...: 00000067`) and
# OUT.TXT's second line starts `ID ` and contains the wanted field. OUTDIR/summary.tsv has one row
# per case (case, want, got, verdict); OUTDIR/CASE/ keeps serial.log, qemu.txt and vol/OUT.TXT.
# Exits 1 if any case fails.
set -u
[ $# -eq 2 ] || { echo "usage: efi-ident.sh EFI OUTDIR" >&2; exit 2; }
EFI=$1 O=$2
t=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$O"
w=$(mktemp -d "${TMPDIR:-/tmp}/efi-ident.XXXXXX")
trap 'rm -rf "$w"' EXIT
printf 'adamck\n' > "$w/job.txt"
sh "$t/efi-image.sh" "$EFI" "$w/img" "$w/job.txt:JOB.TXT" > "$O/image.txt" || { echo "efi-image failed" >&2; exit 1; }
o8() { printf "\\$(printf %03o "$1")"; }
# t1 VER: type 1, handle 0x0100, Manufacturer 1, Product 2, Version VER, one string "OmegaTest".
t1() { printf '\001\033\000\001\001\002'; o8 "$1"; printf '\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\006\000\000OmegaTest\000\000'; }
# t11 H N: type 11 (OEM strings), handle 0x0B00+H, N strings of 60 characters.
t11() {
  printf '\013\005'; o8 "$1"; printf '\013'; o8 "$2"
  s=$(printf '%060d' 0) i=0
  while [ "$i" -lt "$2" ]; do printf '%s\000' "$s"; i=$((i + 1)); done
  printf '\000'
}
t1 3 > "$w/n2.bin"
{ t1 255; t11 1 100; t11 2 100; } > "$w/capwalk.bin"
{ for h in 1 2 3 4 5; do t11 "$h" 255; done; } > "$w/capscan.bin"
for b in n2 capwalk capscan; do echo "blob: $(sha256sum "$w/$b.bin" | cut -d' ' -f1) $b.bin ($(wc -c < "$w/$b.bin") bytes)"; done > "$O/blobs.txt"
printf 'case\twant\tgot\tverdict\n' > "$O/summary.tsv"
fail=0
run() { # case want machine cpu smbios
  c=$1 want=$2; d=$O/$c
  QEMU_MACHINE=$3 QEMU_CPU=$4 QEMU_SMBIOS=$5 sh "$t/efi-qemu.sh" "$w/img" "$d" 600 > "$d.qemu.txt" 2>&1
  mkdir -p "$d"; mv "$d.qemu.txt" "$d/qemu.txt"
  if tr -d '\r' < "$d/serial.log" | grep -aq 'failed to start .*: 00000067'; then got=trap3
  elif ! grep -q '^done=1' "$d/qemu.txt"; then got=no-done
  else got=$(sed -n 2p "$d/vol/OUT.TXT"); fi
  case $got in "ID "*"$want"*) v=PASS ;; *) v=FAIL; fail=1 ;; esac
  printf '%s\t%s\t%s\t%s\n' "$c" "$want" "$got" "$v" >> "$O/summary.tsv"
  echo "$v $c: $got"
}
run nul 'cpu=- ' q35 'max,model-id=' ''
run blank 'cpu=- ' q35 "max,model-id=$(printf '%48s' '')" ''
run n2 'smbios=OmegaTest/-/-' q35,smbios-entry-point-type=64 max "file=$w/n2.bin"
run capwalk 'smbios=OmegaTest/-/-' q35,smbios-entry-point-type=64 max "file=$w/capwalk.bin"
run capscan 'smbios=-/-/-' q35,smbios-entry-point-type=64 max "file=$w/capscan.bin"
[ "$fail" = 0 ]
