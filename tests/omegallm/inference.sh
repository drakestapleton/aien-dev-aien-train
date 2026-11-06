#!/bin/sh
# Focused CPU-only parity gate. No model download and no GPU. Output must be fresh.
set -eu
[ "$#" -ge 2 ] && [ "$#" -le 3 ] || { echo 'usage: inference.sh REFERENCE_OMC FRESH_OUTPUT [VECTOR_OMC]' >&2; exit 64; }
here=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
omc=$1 out=$2
pin=2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f
[ "$(sha256sum "$omc" | cut -d' ' -f1)" = "$pin" ] || { echo OMC_PIN_MISMATCH >&2; exit 65; }
[ ! -e "$out" ] && [ ! -L "$out" ] || { echo 'fresh output required' >&2; exit 73; }
mkdir -p "$out"
OMC="$omc" OUT="$out" CORE=${CORE:-0} sh "$here/tests/omegallm/build.sh"
src=$here/native/omegallm
{
  for f in math data lpool model adam ckpt bpe cli; do cat "$src/$f.om"; done
  sed 's/^fn main to int$/fn oldmain to int/' "$src/lio.om"
  cat "$src/nogpu.om" "$here/tests/omegallm/inference.om"
} > "$out/parity.om"
"$omc" < "$out/parity.om" > "$out/parity"
chmod +x "$out/parity"
"$out/ollm" init "$out/tiny.ck" 256 8 8 2 16 2 1 52 20 3000 > "$out/init.txt"
"$out/parity" 0 "$out/tiny.ck" > "$out/scalar.txt"
"$out/parity" 1 "$out/tiny.ck" > "$out/cache.txt"
cmp "$out/scalar.txt" "$out/cache.txt"
echo 'PASS exact logits and seeded draws: prefill, decode, rollover, repeated requests'
for seed in 0 42 4294967295; do
  for temp in 0 700 2000; do
    "$out/ollm" sample "$out/tiny.ck" "$seed" 20 "$temp" 'A little robot.' > "$out/scalar-$seed-$temp.bin"
    "$out/ollm" samplekv "$out/tiny.ck" "$seed" 20 "$temp" 'A little robot.' > "$out/cache-$seed-$temp.bin"
    cmp "$out/scalar-$seed-$temp.bin" "$out/cache-$seed-$temp.bin"
  done
done
echo 'PASS sampled bytes: greedy and seeded, context overflow'
# Deliberately retain stale learned positions at rollover. The exact-logit oracle must reject it.
sed '/^fn ocpush /,/^end$/s/^put oicount 0 0$/put oicount 0 get oicount 0/' "$out/parity.om" > "$out/stale.om"
"$omc" < "$out/stale.om" > "$out/stale"
chmod +x "$out/stale"
"$out/stale" 1 "$out/tiny.ck" > "$out/stale.txt"
if cmp -s "$out/scalar.txt" "$out/stale.txt"; then echo 'FAIL stale-cache mutant survived' >&2; exit 1; fi
echo 'PASS stale-cache negative control rejected'
# A changed optimizer byte must fail even though those bytes are never retained.
cp "$out/tiny.ck" "$out/corrupt.ck"
size=$(wc -c < "$out/corrupt.ck")
printf '\377' | dd of="$out/corrupt.ck" bs=1 seek="$((size - 1))" conv=notrunc 2>/dev/null
rc=0
"$out/ollm" samplekv "$out/corrupt.ck" 42 1 0 test > "$out/corrupt.txt" || rc=$?
[ "$rc" = 14 ] || { echo "FAIL corrupt optimizer exit $rc" >&2; exit 1; }
echo 'PASS corrupt optimizer refused'
head -c 100 "$out/tiny.ck" > "$out/short.ck"
cp "$out/tiny.ck" "$out/long.ck"
printf x >> "$out/long.ck"
for pair in short:10 long:15; do
  name=${pair%:*} want=${pair#*:} rc=0
  "$out/ollm" samplekv "$out/$name.ck" 42 1 0 test > "$out/$name.txt" || rc=$?
  [ "$rc" = "$want" ] || { echo "FAIL $name checkpoint exit $rc" >&2; exit 1; }
done
echo 'PASS truncated and overlong checkpoints refused'
printf wrong > "$out/wrong-omc"
rc=0
sh "$here/tests/omegallm/inference.sh" "$out/wrong-omc" "$out/wrong-output" > "$out/wrong-pin.txt" 2>&1 || rc=$?
[ "$rc" = 65 ] && [ ! -e "$out/wrong-output" ] || { echo 'FAIL wrong pin accepted' >&2; exit 1; }
echo 'PASS wrong compiler pin refused before output creation'
sha256sum "$omc" "$out/ollm" "$out/parity" "$out/scalar.txt" "$out/cache.txt"

if [ "$#" = 3 ]; then
  vector=$3
  [ "$(sha256sum "$vector" | cut -d' ' -f1)" = c54c9a149a23fc86fb96e08b433e09b555f690a0266c43a4b0e6095449035496 ] || { echo VECTOR_OMC_PIN_MISMATCH >&2; exit 65; }
  sed 's/kvmb xo xe add wo j c/kvmbneon xo xe add wo j c/g' "$out/parity.om" > "$out/neon.om"
  cat "$src/neon.om" >> "$out/neon.om"
  "$vector" < "$out/neon.om" > "$out/neon"
  chmod +x "$out/neon"
  "$out/neon" 1 "$out/tiny.ck" > "$out/neon.txt"
  cmp "$out/scalar.txt" "$out/neon.txt"
  echo 'PASS ordered NEON exact logits and seeded draws, including rollover'
  sha256sum "$vector" "$out/neon.om" "$out/neon" "$out/neon.txt"
fi
