#!/bin/sh
# Dedicated inference executable. Training is unreachable; absent storage retains bounds checks.
set -eu
[ "$#" -ge 2 ] && [ "$#" -le 3 ] || { echo 'usage: build-resident.sh PINNED_OMC FRESH_OUTPUT [scalar|neon]' >&2; exit 64; }
omc=$1 out=$2 mode=${3:-neon}
case "$mode" in scalar|neon) ;; *) echo invalid-kernel >&2; exit 64;; esac
here=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
pin=c54c9a149a23fc86fb96e08b433e09b555f690a0266c43a4b0e6095449035496
[ "$(sha256sum "$omc" | cut -d' ' -f1)" = "$pin" ] || { echo OMC_PIN_MISMATCH >&2; exit 65; }
[ ! -e "$out" ] && [ ! -L "$out" ] || { echo 'fresh output required' >&2; exit 73; }
mkdir -p "$out"
src=$here/native/omegallm
{
  for f in math data epool model adam ckpt bpe cli; do cat "$src/$f.om"; done
  cat "$src/lio.om" "$src/nogpu.om"
} | sed -e 's/^fn main to int$/fn oldmain to int/' \
  -e 's/^fn oflush to void$/fn oldflush to void/' \
  -e 's/^fn oargr /fn oldarg /' \
  -e 's/^fn oipoll to bool$/fn oldpoll to bool/' \
  -e 's/^global ogr f64 15833472$/global ogr f64 1/' \
  -e 's/^global opa f64 16777216$/global opa f64 256/' \
  -e 's/^global oa f64 15016192$/global oa f64 5242880/' \
  -e 's/^const OAC ulong 15016192$/const OAC ulong 5242880/' > "$out/resident.om"
cat "$src/resident.om" >> "$out/resident.om"
if [ "$mode" = neon ]; then
  sed 's/kvmb xo xe add wo j c/kvmbneon xo xe add wo j c/g' "$out/resident.om" > "$out/vector.om"
  cat "$src/neon.om" >> "$out/vector.om"
  mv "$out/vector.om" "$out/resident.om"
fi
"$omc" < "$out/resident.om" > "$out/resident.tmp"
[ -s "$out/resident.tmp" ] || exit 65
chmod +x "$out/resident.tmp"
mv "$out/resident.tmp" "$out/resident"
sha256sum "$omc" "$out/resident.om" "$out/resident"
