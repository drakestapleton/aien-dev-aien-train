#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Compare a UEFI run's \OLLM\OUT.TXT with a Linux reference made by efi-ref.sh (CONTRACT section 9).
# Usage: sh tests/omegallm/efi-check.sh OUT.TXT REF JOBS
# Checks that OUT.TXT starts with `OLLM efi N`, ends with `OLLM DONE JOBS ms`, has one `J ms` line per
# job, and that the remaining bytes equal REF. Prints EQUAL (exit 0) or the first difference (exit 1).
set -u
[ $# -eq 3 ] || { echo "usage: efi-check.sh OUT.TXT REF JOBS" >&2; exit 2; }
OUT=$1 REF=$2 JOBS=$3
f=$(mktemp)
trap 'rm -f "$f"' EXIT HUP INT TERM
bad=0
head -n 1 "$OUT" | grep -Eqx 'OLLM efi [0-9]+' || { echo "no OLLM efi banner"; bad=1; }
tail -n 1 "$OUT" | grep -Eqx "OLLM DONE $JOBS [0-9]+" || { echo "last line is not OLLM DONE $JOBS ms"; bad=1; }
j=$(grep -Ecx 'J [0-9]+' "$OUT")
[ "$j" = "$JOBS" ] || { echo "J lines $j, want $JOBS"; bad=1; }
grep -avEx 'OLLM efi [0-9]+|J [0-9]+|OLLM DONE [0-9]+ [0-9]+' "$OUT" > "$f"
if cmp "$f" "$REF"; then echo "body EQUAL"; else bad=1; fi
[ "$bad" = 0 ] && echo EQUAL && exit 0
echo DIFFERENT
exit 1
