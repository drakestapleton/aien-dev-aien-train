#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Compare a UEFI run's \OLLM\OUT.TXT with a Linux reference made by efi-ref.sh (CONTRACT section 9).
# Usage: sh tests/omegallm/efi-check.sh OUT.TXT REF JOBS BYTES
# Order required:
#   1. first line is exactly `OLLM efi BYTES` (BYTES is the JOB.TXT size)
#   2. second line is the identity line `ID cpu=... fw=... fwrev=XXXXXXXX smbios=.../.../...`
#      (8 lowercase hex digits; its text depends on the machine, so only its shape is checked)
#   3. each reference job, in order, then exactly one `J <ms>` line; a `> ` line holding only
#      spaces and tabs (a JOB.TXT line with no tokens: eio.om main echoes it and runs nothing) has
#      no J line and is not counted in JOBS
#   4. last line is `OLLM DONE JOBS <ms>`
# A reference job is the lines from one `> ` line up to the next. Those lines are compared with
# REF as they stand. A line shaped like `J n` or `OLLM DONE a b` inside a job is part of that
# comparison: it is not removed. Prints EQUAL (exit 0) or the first problems (exit 1).
set -u
[ $# -eq 4 ] || { echo "usage: efi-check.sh OUT.TXT REF JOBS BYTES" >&2; exit 2; }
OUT=$1 REF=$2 JOBS=$3 BYTES=$4
case $JOBS in *[!0-9]*|'') echo "JOBS must be a decimal number" >&2; exit 2 ;; esac
case $BYTES in *[!0-9]*|'') echo "BYTES must be a decimal number" >&2; exit 2 ;; esac
body=$(mktemp)
trap 'rm -f "$body"' EXIT HUP INT TERM
# awk exits 0 when the walk finished (body is the job lines only), 1 when it did not.
awk -v jobs="$JOBS" -v bytes="$BYTES" -v body="$body" '
function note(msg) { print msg; struct = 1 }
NR == FNR { ref[++rn] = $0; next }
{ out[++on] = $0 }
END {
  if (on < 1) { note("empty OUT.TXT"); exit 1 }
  banner = "OLLM efi " bytes
  if (out[1] != banner) note("banner is not " banner)
  if (on < 2 || out[2] !~ /^ID cpu=.* fw=.* fwrev=([0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]|-) smbios=[^\/]*\/[^\/]*\/.*$/) note("second line is not the ID identity line")
  if (out[on] !~ ("^OLLM DONE " jobs " [0-9]+$")) note("last line is not OLLM DONE " jobs " ms")
  ri = 1
  oi = 3
  nj = 0
  while (ri <= rn) {
    if (ref[ri] !~ /^> /) { note("reference line " ri " does not start a job"); exit 1 }
    blank = (ref[ri] ~ /^> [ \t]*$/)
    if (!blank) nj++
    while (ri <= rn) {
      if (oi >= on) { note("OUT ended during job " nj); exit 1 }
      if (out[oi] != ref[ri]) {
        note("job " nj " line mismatch")
        print "  out: " out[oi]
        print "  ref: " ref[ri]
        exit 1
      }
      print out[oi] >> body
      oi++
      ri++
      if (ri <= rn && ref[ri] ~ /^> /) break
    }
    if (blank) continue
    if (oi >= on) { note("missing J line after job " nj); exit 1 }
    if (out[oi] !~ /^J [0-9]+$/) {
      note("expected one J line after job " nj)
      print "  out: " out[oi]
      exit 1
    }
    oi++
    if (oi < on && out[oi] ~ /^J [0-9]+$/) {
      note("extra J line after job " nj)
      exit 1
    }
  }
  close(body)
  if (nj + 0 != jobs + 0) note("jobs " nj ", want " jobs)
  if (oi != on) note("extra line before DONE")
  exit (struct ? 2 : 0)
}
' "$REF" "$OUT"
arc=$?
bad=0
if [ "$arc" -eq 0 ] || [ "$arc" -eq 2 ]; then
  if cmp "$body" "$REF"; then echo "body EQUAL"; else bad=1; fi
else
  bad=1
fi
[ "$arc" -eq 0 ] && [ "$bad" -eq 0 ] && echo EQUAL && exit 0
echo DIFFERENT
exit 1
