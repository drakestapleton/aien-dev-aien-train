#!/bin/sh
set -eu
# Public fixture only. No caller-selected corpus and no trainer integration.
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build=$(CDPATH= cd -- "$1" && pwd)
out=$2
[ ! -e "$out" ] || { echo 'output exists' >&2; exit 1; }
mkdir -p "$out"
cp "$here/public.jsonl" "$out/original.jsonl"
cp "$here/ORIGIN.json" "$out/ORIGIN.json"
"$build/exchange" import < "$out/original.jsonl" > "$out/imported.jsonl"
"$build/exchange" extract < "$out/imported.jsonl" > "$out/compact.om"
"$build/exchange" export < "$out/imported.jsonl" > "$out/exported.jsonl"
cmp "$out/original.jsonl" "$out/exported.jsonl"
cp "$build/total.om" "$out/catalog.om"
cp "$build/total.lock.b" "$out/catalog.lock"
"$build/resolve" build "$out/catalog.om" "$out/catalog.lock" "$out/compact.om" "$out/resolve.map" > "$out/expanded.om" 2> "$out/resolve.log"
"$build/omc" < "$out/expanded.om" > "$out/program"
chmod +x "$out/program"
"$out/program"
cp "$build/omc" "$out/compiler"
cp "$build/exchange" "$out/exchange"
cp "$build/resolve" "$out/resolver"
(
  cd "$out"
  sha256sum original.jsonl imported.jsonl exported.jsonl ORIGIN.json compact.om expanded.om catalog.om catalog.lock resolve.map compiler exchange resolver program > SHA256SUMS
  sha256sum -c SHA256SUMS
)
printf '%s\n' '{"kind":"aien-openwaldo-exchange-pilot","schema":1,"status":"host-tested","original_record_retained":true,"roundtrip":"byte-identical","compiler_exit":0,"program_exit":0,"identities":"SHA256SUMS","training_eligible":false,"evaluation_eligible":false,"upstream_bom_verified":false,"model_conversion":"REFUSED_ARCHITECTURE_TOKENIZER_NOT_SUPPORTED","training":"NOT_RUN","runtime":"UNCHANGED"}' > "$out/RECEIPT.json"
