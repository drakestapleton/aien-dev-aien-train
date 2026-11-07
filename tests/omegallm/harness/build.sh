#!/bin/sh
# build.sh: build the harness programs with the pinned seeded omc (omega-mv e5b32567, aarch64):
#   verify  (tests/omegallm/harness/verify.om) the task tool and independent verifier
#   sftgen  (native/omegallm/sftgen/{sghead,sgprompt,sglogic}.om concatenated) the tool-use SFT
#           conversation generator
# Env: OMC (required), OUT (default ../build beside the clone), CORES (taskset list, required).
# --mutant NAME builds OUT/verify-NAME instead, a deliberately broken verifier for negative
# controls: eqtrue (every byte comparison succeeds), absentok (absent always holds); and
# OUT/sftgen-NAME: sgcount (line counts off by one), sgnostrip (a tool output keeps its final
# newline), sgsys (one byte of the system prompt changed).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../.." && pwd)
: "${OMC:?set OMC}" "${CORES:?set CORES}"
OUT=${OUT:-$root/../build}
PIN=2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f
got=$(sha256sum "$OMC" | cut -d' ' -f1)
[ "$got" = "$PIN" ] || { echo "harness/build: omc sha256 $got is not the pin $PIN" >&2; exit 2; }
mkdir -p "$OUT"
one() { # NAME SRC
	taskset -c "$CORES" nice -n 10 "$OMC" <"$2" >"$OUT/$1.part" || {
		rc=$?; rm -f "$OUT/$1.part"; echo "harness/build: $1 omc exit $rc" >&2; exit "$rc"; }
	chmod 755 "$OUT/$1.part"
	mv "$OUT/$1.part" "$OUT/$1"
	echo "harness/build: $OUT/$1 sha256 $(sha256sum "$OUT/$1" | cut -d' ' -f1) src $(sha256sum "$2" | cut -d' ' -f1) omc $PIN"
}
if [ "${1:-}" = --mutant ]; then
	m=${2:?mutant name}
	sg=$root/native/omegallm/sftgen
	case $m in
	sgcount | sgnostrip | sgsys)
		cat "$sg/sghead.om" "$sg/sgprompt.om" "$sg/sglogic.om" >"$OUT/sftgen.om"
		case $m in
		sgcount) sed "s/^sgnum RN nl\$/sgnum RN add nl 1/" "$OUT/sftgen.om" >"$OUT/sftgen-$m.om" ;;
		sgnostrip) sed "s/^if eq sgat q sub n 1 10\$/if eq sgat q sub n 1 11/" "$OUT/sftgen.om" >"$OUT/sftgen-$m.om" ;;
		sgsys) sed "s/^text sgq3 \"\\\\nModel: ollm/text sgq3 \"\\\\nModel: olm/" "$OUT/sftgen.om" >"$OUT/sftgen-$m.om" ;;
		esac
		cmp -s "$OUT/sftgen.om" "$OUT/sftgen-$m.om" && { echo "harness/build: mutant $m changed nothing" >&2; exit 2; }
		one "sftgen-$m" "$OUT/sftgen-$m.om"
		exit 0 ;;
	esac
	case $m in
	eqtrue) sed "s/^fn hveq a ulong b ulong s ulong e ulong to bool\$/fn hveq a ulong b ulong s ulong e ulong to bool\\nret true\\nend\\nfn hveqx a ulong b ulong s ulong e ulong to bool/" "$here/verify.om" >"$OUT/verify-$m.om" ;;
	absentok) awk '/^if hvline ks ke hvka$/ {a = 1} a && /^if ge fd 0$/ {print "if lt fd -100000"; a = 0; next} {print}' "$here/verify.om" >"$OUT/verify-$m.om" ;;
	*) echo "harness/build: unknown mutant $m" >&2; exit 2 ;;
	esac
	cmp -s "$here/verify.om" "$OUT/verify-$m.om" && { echo "harness/build: mutant $m changed nothing" >&2; exit 2; }
	one "verify-$m" "$OUT/verify-$m.om"
	exit 0
fi
one verify "$here/verify.om"
sg=$root/native/omegallm/sftgen
cat "$sg/sghead.om" "$sg/sgprompt.om" "$sg/sglogic.om" >"$OUT/sftgen.om"
one sftgen "$OUT/sftgen.om"
