#!/bin/sh
# CPU only. Product implementation is Omega; sh/sed/git are build composition tools.
# Composition: om2, SHA layout, ollm (main -> wpollm), SHA functions, wpatch.
# Layouts must precede the first fn (error 29 otherwise). SHA functions still append
# after ollm. SHA export fn becomes fn; om2 is emitted once. Rename only non-note
# tokens: kinit->wskinit, iv->wsiv, sched->wssched, rounds->wsround,
# compress->wscomp, run->wsrun, blocks->wsblks, finish->wsfin,
# tobuf->wstobuf, absorb->wsabsb. Full mechanical diff is saved in OUT/sha256.diff.
set -eu
here=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
: "${OUT:?set OUT to a private build directory}"
OMC=${OMC:-$here/../omega-mv/seed/out/omc}
OMEGA_MV=${OMEGA_MV:-$here/../omega-mv}
CORE=${CORE:-0}
export OUT OMC CORE
pin=e5b32567a7aff3ce594e3254a622a846a6cd190b
sha=dbf002dd6aa36585632b9d01d98ac3f0bd2fa0f0475082940de53638847994bb
TARGET=aarch64 sh "$here/tests/omegallm/build.sh"
git -C "$OMEGA_MV" show "$pin:om/sha256/sha256-om2.om" > "$OUT/sha256-source.om"
test "$(sha256sum "$OUT/sha256-source.om" | cut -d' ' -f1)" = "$sha"
test "$(grep -c '^fn main to int$' "$OUT/ollm.om")" = 1
sed -n '/^layout shactx 104$/,/^end$/p' "$OUT/sha256-source.om" > "$OUT/sha256-layout.om"
sed -e '/^om2$/d' -e '/^layout shactx 104$/,/^end$/d' \
  -e 's/^export fn /fn /' \
  -e '/^note/!{s/\bkinit\b/wskinit/g;s/\biv\b/wsiv/g;s/\bsched\b/wssched/g;s/\brounds\b/wsround/g;s/\bcompress\b/wscomp/g;s/\brun\b/wsrun/g;s/\bblocks\b/wsblks/g;s/\bfinish\b/wsfin/g;s/\btobuf\b/wstobuf/g;s/\babsorb\b/wsabsb/g;}' \
  "$OUT/sha256-source.om" > "$OUT/sha256-functions.om"
{ printf 'om2\n'; cat "$OUT/sha256-layout.om" "$OUT/sha256-functions.om"; } > "$OUT/sha256-vendored.om"
diff -u "$OUT/sha256-source.om" "$OUT/sha256-vendored.om" > "$OUT/sha256.diff" || test "$?" = 1
{
  printf 'om2\n'
  cat "$OUT/sha256-layout.om"
  sed -e '/^om2$/d' -e 's/^fn main to int$/fn wpollm to int/' "$OUT/ollm.om"
  cat "$OUT/sha256-functions.om" "$here/tools/omegallm/wpatch/wpatch.om"
} > "$OUT/wpatch-all.om"
if taskset -c "$CORE" nice -n 19 "$OMC" < "$OUT/wpatch-all.om" > "$OUT/wpatch.new"; then
  chmod +x "$OUT/wpatch.new"
  mv "$OUT/wpatch.new" "$OUT/wpatch"
else
  rc=$?
  rm -f "$OUT/wpatch.new"
  exit "$rc"
fi
sha256sum "$OMC" "$OUT/sha256-source.om" "$OUT/wpatch-all.om" "$OUT/wpatch"
