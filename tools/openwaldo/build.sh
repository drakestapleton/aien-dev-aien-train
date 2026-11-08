#!/bin/sh
set -eu
# Usage: build.sh OMEGA_CHECKOUT NEW_OUTPUT_DIRECTORY
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$here/../.." && pwd)
omega=$(CDPATH= cd -- "$1" && pwd)
out=$2
[ ! -e "$out" ] || { echo 'output exists' >&2; exit 1; }
[ "$(git -C "$omega" rev-parse HEAD)" = 049356cbf40e7238fa1c206a9f58f58d60575bdd ] || exit 1
mkdir -p "$out"
# Pin the source bytes independently of mutable worktree contents.
for f in seed/out/omc om/sha256/sha256-om2.om seed/catalog/resolve.om seed/catalog/total.om seed/catalog/tests/total.lock.b; do
  git -C "$omega" show "HEAD:$f" > "$out/$(basename "$f")"
done
chmod +x "$out/omc"
{
  sed 's/^export fn /fn /' "$out/sha256-om2.om"
  cat "$root/native/omegallm/net/json.om" "$here/exchange.om"
} > "$out/exchange.full.om"
nice -n 19 "$out/omc" < "$out/exchange.full.om" > "$out/exchange"
{
  sed 's/^export fn /fn /' "$out/sha256-om2.om"
  cat "$out/resolve.om"
} > "$out/resolve.full.om"
nice -n 19 "$out/omc" < "$out/resolve.full.om" > "$out/resolve"
chmod +x "$out/exchange" "$out/resolve"
