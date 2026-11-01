#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Receipts for the ollm UEFI rung (aien-train#52, CONTRACT section 9): build ollm.efi, compose the boot
# image, boot it under QEMU/OVMF and compare its \OLLM\OUT.TXT and written files with a Linux build
# running the same job, plus three controls. EMULATED evidence only: this is not the iMac.
# Usage: sh tests/omegallm/efi-receipts.sh
# Env: IMAC_IMAGE (required; see efi-image.sh), EOMC (x86efi omc; build.sh's default when unset),
#      ABUILD (aarch64 reference build dir, default build), EBUILD (x86efi build dir, default
#      build-efi), DATA (TinyStoriesV2-GPT4-valid.txt, default data/...), CK (the v0 checkpoint,
#      default run/v0/ck-20000.bin), WORK (scratch, default scratch-efi), CORE (taskset core for the
#      reference and the main boot, default 6), MCORE (core for the mutant boot, run in parallel,
#      default CORE), EV (receipt dir, default evidence/OMEGALLM/efi in this clone).
# Runs from the clone's parent directory; give every path relative to it, so the receipts name no
# absolute (private) path. Checks, each a line in summary.tsv (name, want, got, verdict):
#   main      efi-job.txt: efi-check EQUAL and TR.BIN, HE.BIN, S.CK equal to the reference's files
#   mut-b     the same job on ollm-mut-b.efi: the body differs from the reference at a byte (not only
#             a shorter run cut off by the deadline)
#   ckbad     `eval` on a CK.BIN with one byte changed: OUT.TXT stops after the job line (no J, no
#             OLLM DONE) and its body equals the Linux build's stdout for the same file
#   job65535  a 65535-byte JOB.TXT (comment lines + adamck) runs: EQUAL with the Linux reference
#   job65536  a 65536-byte JOB.TXT is refused: the console shows `OLLM efi JOB.TXT?`, no OUT.TXT
# Exits 1 if any check disagrees.
set -u
here=$(cd "$(dirname "$0")/../.." && pwd)
cd "$here/.." || exit 70
r=$(basename "$here")
t=$r/tests/omegallm
[ -n "${IMAC_IMAGE:-}" ] && [ -x "$IMAC_IMAGE" ] || { echo "IMAC_IMAGE must name the imac-image tool" >&2; exit 2; }
ABUILD=${ABUILD:-build}
EBUILD=${EBUILD:-build-efi}
DATA=${DATA:-data/TinyStoriesV2-GPT4-valid.txt}
CK=${CK:-run/v0/ck-20000.bin}
WORK=${WORK:-scratch-efi}
CORE=${CORE:-6}
MCORE=${MCORE:-$CORE}
E=${EV:-$r/evidence/OMEGALLM/efi}
rm -rf "$WORK" "$E"
mkdir -p "$WORK" "$E"
fail=0
row() { # name want got
	if [ "$2" = "$3" ]; then v=PASS; else v=FAIL; fail=1; fi
	printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$v" >> "$E/summary.tsv"
}
body() { grep -avEx 'OLLM efi [0-9]+|J [0-9]+|OLLM DONE [0-9]+ [0-9]+' "$1"; }
printf 'name\twant\tgot\tverdict\n' > "$E/summary.tsv"

# 0. tools and builds (the reference is the aarch64 build; build.sh checks each omc against its pin)
{
	echo "qemu: $(qemu-system-x86_64 --version | head -n 1)"
	echo "ovmf: $(sha256sum /usr/share/OVMF/OVMF_CODE_4M.fd | cut -d' ' -f1) OVMF_CODE_4M.fd ($(dpkg-query -W -f '${Package} ${Version}' ovmf 2> /dev/null))"
	echo "mtools: $(mtools --version | head -n 1)"
	echo "sgdisk: $(sgdisk --version | head -n 1)"
	echo "imac-image: $(sha256sum "$IMAC_IMAGE" | cut -d' ' -f1)"
	echo "core $CORE midr_el1 $(cat /sys/devices/system/cpu/cpu$CORE/regs/identification/midr_el1)"
} > "$E/tools.txt"
{
	OMC= TARGET=aarch64 OUT=$here/../$ABUILD CORE=$CORE sh "$t/build.sh"
	OMC=${EOMC:-} TARGET=x86efi OUT=$here/../$EBUILD CORE=$CORE sh "$t/build.sh"
	OMC=${EOMC:-} TARGET=x86efi OUT=$here/../$EBUILD CORE=$CORE sh "$t/build.sh" --mutant b
} > "$WORK/build.log" 2>&1 || { cat "$WORK/build.log" >&2; exit 1; }
sed "s|$here/\.\./||g" "$WORK/build.log" > "$E/build.txt"
sha256sum "$DATA" "$CK" "$t/mathref.txt" "$t/efi-job.txt" > "$E/inputs.txt"

# 1. Linux reference for efi-job.txt
mkdir "$WORK/ref"
cp "$CK" "$WORK/ref/CK.BIN"
cp "$DATA" "$WORK/ref/STORIES.TXT"
cp "$t/mathref.txt" "$WORK/ref/MATHREF.TXT"
CORE=$CORE sh "$t/efi-ref.sh" "$ABUILD/ollm" "$t/efi-job.txt" "$WORK/ref" > "$E/ref.out"
(cd "$WORK/ref" && sha256sum TR.BIN HE.BIN S.CK) > "$E/ref-files.txt"
jobs=$(grep -cvE '^(#|$)' "$t/efi-job.txt")

# 2. images
img() { # efi img job [extra SRC:NAME...]
	e=$1 i=$2 j=$3
	shift 3
	IMAC_IMAGE=$IMAC_IMAGE sh "$t/efi-image.sh" "$e" "$i" "$j:JOB.TXT" "$@"
}
img "$EBUILD/ollm.efi" "$WORK/ollm.img" "$t/efi-job.txt" "$CK:CK.BIN" "$DATA:STORIES.TXT" \
	"$t/mathref.txt:MATHREF.TXT" > "$E/image.txt"
img "$EBUILD/ollm-mut-b.efi" "$WORK/mutb.img" "$t/efi-job.txt" "$CK:CK.BIN" "$DATA:STORIES.TXT" \
	"$t/mathref.txt:MATHREF.TXT" > "$E/image-mut-b.txt"

# 3. main boot and mutant boot, in parallel
boot() { # img name seconds core
	mkdir -p "$E/$2"
	CORES=$4 sh "$t/efi-qemu.sh" "$1" "$WORK/q-$2" "$3" > "$E/$2/qemu.txt" 2>&1
	cp "$WORK/q-$2/serial.log" "$E/$2/serial.log"
	[ ! -f "$WORK/q-$2/vol/OUT.TXT" ] || cp "$WORK/q-$2/vol/OUT.TXT" "$E/$2/OUT.TXT"
}
boot "$WORK/ollm.img" main 2700 "$CORE" &
p1=$!
boot "$WORK/mutb.img" mut-b 900 "$MCORE" &
p2=$!
wait "$p1"
wait "$p2"
sh "$t/efi-check.sh" "$E/main/OUT.TXT" "$E/ref.out" "$jobs" > "$E/main/check.txt" 2>&1
row main EQUAL "$(tail -n 1 "$E/main/check.txt")"
for f in TR.BIN HE.BIN S.CK; do
	want=$(grep " $f\$" "$E/ref-files.txt" | cut -d' ' -f1)
	got=$(sha256sum "$WORK/q-main/vol/$f" 2> /dev/null | cut -d' ' -f1 || true)
	row "main-$f" "$want" "${got:-missing}"
done
body "$E/mut-b/OUT.TXT" > "$WORK/mutb.body" 2> /dev/null
cmp "$WORK/mutb.body" "$E/ref.out" > "$E/mut-b/check.txt" 2>&1
grep -q ' differ: ' "$E/mut-b/check.txt" && got=differs || got=same-or-prefix
row mut-b differs "$got"

# 4. controls (each boot ends in a refusal, so a short deadline)
# ckbad: one byte of CK.BIN changed (0x00, or 0x01 where it already was 0x00)
cp "$CK" "$WORK/ckbad.bin"
printf '\000' | dd of="$WORK/ckbad.bin" bs=1 seek=200000 conv=notrunc 2> /dev/null
cmp -s "$CK" "$WORK/ckbad.bin" && printf '\001' | dd of="$WORK/ckbad.bin" bs=1 seek=200000 conv=notrunc 2> /dev/null
printf 'eval \\OLLM\\CK.BIN \\OLLM\\MATHREF.TXT 4\n' > "$WORK/ckbad-job.txt"
mkdir "$WORK/ckbad"
cp "$WORK/ckbad.bin" "$WORK/ckbad/CK.BIN"
cp "$t/mathref.txt" "$WORK/ckbad/MATHREF.TXT"
CORE=$CORE sh "$t/efi-ref.sh" "$ABUILD/ollm" "$WORK/ckbad-job.txt" "$WORK/ckbad" > "$WORK/ckbad.ref"
img "$EBUILD/ollm.efi" "$WORK/ckbad.img" "$WORK/ckbad-job.txt" "$WORK/ckbad.bin:CK.BIN" \
	"$t/mathref.txt:MATHREF.TXT" > /dev/null
boot "$WORK/ckbad.img" ckbad 300 "$CORE"
cp "$WORK/ckbad.ref" "$E/ckbad/ref.out"
grep -v '^rc=' "$WORK/ckbad.ref" > "$WORK/ckbad.want"
got=$(body "$E/ckbad/OUT.TXT" 2> /dev/null | cmp -s - "$WORK/ckbad.want" && echo body-equal || echo body-differs)
grep -q '^rc=1[0-5]$' "$WORK/ckbad.ref" && got="$got,ref-refused" || got="$got,ref-ran"
grep -aqE '^(J [0-9]+|OLLM DONE .*)$' "$E/ckbad/OUT.TXT" 2> /dev/null && got="$got,ran-on"
row ckbad body-equal,ref-refused "$got"

# job65535 / job65536: comment lines padding JOB.TXT to exactly that size, adamck last
pad() { # size file
	{
		n=$(($1 - 7))
		while [ "$n" -gt 64 ]; do printf '#%062d\n' 0; n=$((n - 64)); done
		printf '#%0*d\n' $((n - 2)) 0
		printf 'adamck\n'
	} > "$2"
	[ "$(wc -c < "$2")" = "$1" ] || { echo "pad $1 gave $(wc -c < "$2") bytes" >&2; exit 1; }
}
pad 65535 "$WORK/job65535.txt"
pad 65536 "$WORK/job65536.txt"
mkdir "$WORK/j"
CORE=$CORE sh "$t/efi-ref.sh" "$ABUILD/ollm" "$WORK/job65535.txt" "$WORK/j" > "$WORK/job65535.ref"
for s in 65535 65536; do
	img "$EBUILD/ollm.efi" "$WORK/job$s.img" "$WORK/job$s.txt" > /dev/null
done
boot "$WORK/job65535.img" job65535 300 "$CORE"
sh "$t/efi-check.sh" "$E/job65535/OUT.TXT" "$WORK/job65535.ref" 1 > "$E/job65535/check.txt" 2>&1
row job65535 EQUAL "$(tail -n 1 "$E/job65535/check.txt")"
boot "$WORK/job65536.img" job65536 300 "$CORE"
grep -aq 'OLLM efi JOB.TXT?' "$E/job65536/serial.log" && got=refused || got=no-message
[ ! -f "$E/job65536/OUT.TXT" ] || got="$got,OUT.TXT"
row job65536 refused "$got"

cat "$E/summary.tsv"
exit "$fail"
