#!/bin/sh
# check.sh: DRA-23 probe gate. Builds dra23live and its mutants (build.sh), then runs positive cases
# and negative controls against processes this script starts itself on loopback test ports
# (never :18091). The script stops only the PIDs it started.
# Env: OLLM (an aarch64 `ollm serve` build from tests/omegallm/build.sh), CK (checkpoint), MERGES
#      (tokenizer merges), PORT (default 18923, the test server), FPORT (default 18924, a dynamically
#      linked fixture listener, python3 -m http.server), GPUPID (optional: a running process of this
#      user that holds raw NVIDIA RM device nodes, inspected read-only through /proc; absent gives
#      NOT_RUN rows), CORES (taskset list, default 10-11), OMC, BOUT (build dir, default
#      ../build/dra23 beside this clone), OUT (receipt directory, default $BOUT/check).
# Each row prints `CASE name expect=... got=... PASS|FAIL`. Exit 0 only when every run row matched.
set -u
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../.." && pwd)
: "${OLLM:?}" "${CK:?}" "${MERGES:?}"
PORT=${PORT:-18923}
FPORT=${FPORT:-18924}
CORES=${CORES:-10-11}
BOUT=${BOUT:-$root/../build/dra23}
OUT=${OUT:-$BOUT/check}
if [ "$PORT" = 18091 ] || [ "$FPORT" = 18091 ]; then echo "refusing to use :18091" >&2; exit 2; fi
mkdir -p "$OUT"
for p in "$PORT" "$FPORT"; do
  if ss -Hltn "sport = :$p" | grep -q .; then echo "PORT_BUSY $p" >&2; exit 2; fi
done
for m in "" m1 m2 m3; do
  if [ -z "$m" ]; then r=$(OUT=$BOUT taskset -c "$CORES" nice -n 19 sh "$here/build.sh" 2>&1)
  else r=$(OUT=$BOUT taskset -c "$CORES" nice -n 19 sh "$here/build.sh" --mutant "$m" 2>&1); fi
  echo "$r" | grep -q '^BUILD_OK' || { echo "BUILD_FAIL $m: $r"; exit 1; }
  echo "$r" >> "$OUT/builds.txt"
done
L=$BOUT/dra23live
XS=$(sha256sum "$OLLM" | cut -d' ' -f1)
CKS=$(sha256sum "$CK" | cut -d' ' -f1)
MGS=$(sha256sum "$MERGES" | cut -d' ' -f1)
# a different valid digest for the mismatch rows: the probe's own binary
WRONG=$(sha256sum "$L" | cut -d' ' -f1)
{
  echo "date $(date -u +%FT%TZ)"
  echo "host $(hostname) $(uname -m)"
  echo "aien_train $(git -C "$root" rev-parse HEAD)"
  echo "dra23live $WRONG"
  echo "ollm $XS"
  echo "ck $CKS"
  echo "merges $MGS"
} > "$OUT/env.txt"
srv=
fix=
stop() {
  [ -n "$srv" ] && kill "$srv" 2>/dev/null && wait "$srv" 2>/dev/null
  [ -n "$fix" ] && kill "$fix" 2>/dev/null && wait "$fix" 2>/dev/null
  echo "stopped server=$srv fixture=$fix" >> "$OUT/env.txt"
}
trap stop EXIT
taskset -c "$CORES" nice -n 10 "$OLLM" serve "$PORT" "$CK" "$MERGES" > "$OUT/serve.log" 2>&1 &
srv=$!
i=0
until grep -q "^PORT $PORT" "$OUT/serve.log" 2>/dev/null; do
  i=$((i + 1))
  if [ $i -gt 1200 ] || ! kill -0 "$srv" 2>/dev/null; then echo "SERVE_START_FAIL"; cat "$OUT/serve.log"; exit 1; fi
  sleep 0.1
done
taskset -c "$CORES" nice -n 10 python3 -m http.server --bind 127.0.0.1 "$FPORT" > "$OUT/fixture.log" 2>&1 &
fix=$!
i=0
until ss -Hltn "sport = :$FPORT" | grep -q .; do
  i=$((i + 1)); [ $i -gt 100 ] && { echo "FIXTURE_START_FAIL"; exit 1; }; sleep 0.1
done
bad=0
# row NAME EXPECT_RC EXPECT_FAIL_REASON|- BINARY ARGS...
row() {
  name=$1 erc=$2 ereason=$3 bin=$4
  shift 4
  taskset -c "$CORES" nice -n 10 "$bin" "$@" > "$OUT/$name.txt" 2>&1
  rc=$?
  ok=1
  [ "$rc" = "$erc" ] || ok=0
  if [ "$ereason" != - ]; then grep -qx "fail $ereason" "$OUT/$name.txt" || ok=0; fi
  if [ "$erc" = 0 ]; then grep -q '^fail ' "$OUT/$name.txt" && ok=0; fi
  v=$(tail -1 "$OUT/$name.txt")
  if [ $ok = 1 ]; then echo "CASE $name expect=rc$erc/$ereason got=rc$rc PASS ($v)"
  else echo "CASE $name expect=rc$erc/$ereason got=rc$rc FAIL ($v)"; bad=1; fi
}
row p1-own-model-cpu 0 - "$L" "$PORT" "$XS" none "$CK" "$CKS" "$MERGES" "$MGS"
row n1-wrong-exe 1 exe_sha256_mismatch "$L" "$PORT" "$WRONG" none "$CK" "$CKS"
row n2-expect-nvrm 1 gpu_expect_mismatch "$L" "$PORT" "$XS" nvrm "$CK" "$CKS"
row n3-wrong-ck 1 file_sha256_mismatch "$L" "$PORT" "$XS" none "$CK" "$WRONG"
row n4-ck-not-in-cmdline 1 file_not_in_cmdline "$L" "$PORT" "$XS" none "$(dirname "$CK")/./$(basename "$CK")" "$CKS"
row n5-dynamic-fixture 1 shared_object_mapped "$L" "$FPORT" - none
row n6-fixture-http 1 http_health_not_200 "$L" "$FPORT" - none
row n7-usage 2 - "$L" "$PORT" "$XS" cuda
# mutants: each must flip the verdict of the row it targets
row m1-mutant-wrong-exe 0 - "$BOUT/dra23live-m1" "$PORT" "$WRONG" none
row m3-mutant-dynamic 1 http_health_not_200 "$BOUT/dra23live-m3" "$FPORT" - none
if grep -q '^fail shared_object_mapped' "$OUT/m3-mutant-dynamic.txt"; then
  echo "CASE m3-mutant-killed FAIL (mutant still reports shared objects)"; bad=1
else echo "CASE m3-mutant-killed PASS (mutant misses the shared objects n5 reports)"; fi
if [ -n "${GPUPID:-}" ]; then
  row p2-gpu-pid-nvrm 0 - "$L" --pid "$GPUPID" nvrm
  row n8-gpu-pid-none 1 gpu_expect_mismatch "$L" --pid "$GPUPID" none
  row m2-mutant-gpu-pid 1 gpu_expect_mismatch "$BOUT/dra23live-m2" --pid "$GPUPID" nvrm
else
  echo "CASE p2-gpu-pid-nvrm NOT_RUN (no GPUPID)"
  echo "CASE n8-gpu-pid-none NOT_RUN (no GPUPID)"
  echo "CASE m2-mutant-gpu-pid NOT_RUN (no GPUPID)"
fi
row n9-no-listener 3 - "$L" 18925 - none
if [ $bad = 0 ]; then echo "DRA23CHECK PASS"; exit 0; fi
echo "DRA23CHECK FAIL"
exit 1
