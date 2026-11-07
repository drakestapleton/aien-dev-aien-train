#!/bin/sh
# live-18091.sh: the DRA-23 live row. Proves which binary serves 127.0.0.1:PORT (default 18091),
# that it is the reproducible build of a named aien-train revision, and which GPU backend it holds.
# Read-only toward the server: never starts, stops or signals it, never binds a port, never opens a
# GPU device. Run it after the own Omega LLM is deployed on :18091 (DRA-125, lead ownmodel).
# Env (required): REV (full aien-train commit that was deployed), CK and MERGES (checkpoint and
#   merges paths exactly as on the server's command line).
# Env (optional): TARGET (aarch64, the CPU serve build and the only build with `serve` at aien-train
#   main 0518c915; gb10 once a GPU serve build exists), GPU (none for aarch64, nvrm for gb10),
#   PORT (18091), CORES (10-11), OMC, BOUT (probe build dir, default ../build/dra23 beside this
#   clone), OUT (receipt dir), AIEN_TRAIN (a clean clone at REV; default a fresh shallow fetch in OUT).
# Exit: the probe's verdict (0 PASS, 1 FAIL, 3 NOT_RUN) or 4 when a static precondition fails.
set -u
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../.." && pwd)
: "${REV:?}" "${CK:?}" "${MERGES:?}"
TARGET=${TARGET:-aarch64}
case $TARGET in aarch64) GPU=${GPU:-none} ;; gb10) GPU=${GPU:-nvrm} ;; *) echo "TARGET aarch64|gb10" >&2; exit 2 ;; esac
PORT=${PORT:-18091}
CORES=${CORES:-10-11}
OMC=${OMC:-$root/../omega-mv/seed/out/omc}
BOUT=${BOUT:-$root/../build/dra23}
OUT=${OUT:-$BOUT/live-$(date -u +%Y%m%dT%H%M%SZ)}
mkdir -p "$OUT"
r=$(OMC=$OMC OUT=$BOUT sh "$here/build.sh" 2>&1)
echo "$r" | grep -q '^BUILD_OK' || { echo "PROBE_BUILD_FAIL $r"; exit 4; }
L=$BOUT/dra23live
# CUDApp device layer the own model vendors (aien-train native/omegallm/gpu/, from CUDApp dcba8bb8);
# git blob ids at CUDApp dcba8bb8 and at CUDApp main b774723f (only the SPDX note line differs; a
# gb10 build with either set is bit-identical, c35798fd at aien-train 0518c915).
VEND="context.om 5280fea0e47acd0f91e7616770b1679cd1a72e34 bafd9058ea296fa51dfe06827ee2e8508061f6fe
vector.om d2c1bc8305943374ed3cfe7ec3db020a4d21fa58 446d364b59c37d3570602ae762ae1ea309c81f1e
launch.om fb70bee4171cd30d8f28b41a5cbdceba283de816 1842982be00f62016267e85be1f051890edc4af6"
src=${AIEN_TRAIN:-$OUT/aien-train}
if [ ! -d "$src/.git" ]; then
  git init -q "$src" && git -C "$src" fetch -q --depth 1 https://github.com/aien-dev/aien-train.git "$REV" \
    && git -C "$src" checkout -q FETCH_HEAD || { echo "FETCH_FAIL $REV" | tee "$OUT/static.txt"; exit 4; }
fi
head=$(git -C "$src" rev-parse HEAD)
[ "$head" = "$REV" ] || { echo "REV_MISMATCH clone at $head, want $REV" | tee "$OUT/static.txt"; exit 4; }
dirty=$(git -C "$src" status --porcelain | wc -l)
[ "$dirty" = 0 ] || { echo "DIRTY_TREE $dirty" | tee "$OUT/static.txt"; exit 4; }
{
  echo "date $(date -u +%FT%TZ)"
  echo "aien_train $head target $TARGET gpu_expected $GPU port $PORT"
  echo "omc $(sha256sum "$OMC" | cut -d' ' -f1)"
  echo "dra23live $(sha256sum "$L" | cut -d' ' -f1)"
} > "$OUT/static.txt"
ok=1
# 1. two independent builds of the deployed revision must be bit-identical: that digest is the
#    expected /proc/PID/exe sha256.
x1=$(cd "$src" && TARGET=$TARGET OMC=$OMC OUT=$OUT/b1 CORE=$CORES sh tests/omegallm/build.sh 2>&1 | tail -1)
x2=$(cd "$src" && TARGET=$TARGET OMC=$OMC OUT=$OUT/b2 CORE=$CORES sh tests/omegallm/build.sh 2>&1 | tail -1)
echo "build1 $x1" >> "$OUT/static.txt"
echo "build2 $x2" >> "$OUT/static.txt"
d1=$(echo "$x1" | sed -n 's/^BUILD_OK \([0-9a-f]\{64\}\) .*/\1/p')
d2=$(echo "$x2" | sed -n 's/^BUILD_OK \([0-9a-f]\{64\}\) .*/\1/p')
if [ -z "$d1" ] || [ "$d1" != "$d2" ]; then echo "STATIC FAIL reproducible_build" >> "$OUT/static.txt"; cat "$OUT/static.txt"; exit 4; fi
comp=$OUT/b1/ollm.om
# 2. static backend census of the composed source: device node texts and devcall (ioctl) lines.
nodes=$(grep -c '^text [a-z0-9]* "/dev/' "$comp")
calls=$(grep -c 'devcall ' "$comp")
echo "census device_node_texts $nodes devcall_lines $calls" >> "$OUT/static.txt"
if [ "$TARGET" = aarch64 ]; then
  if [ "$nodes" != 0 ] || [ "$calls" != 0 ]; then echo "STATIC FAIL cpu_build_has_device_code" >> "$OUT/static.txt"; ok=0; fi
else
  # exactly the vendored CUDApp device layer, byte-equal to CUDApp at dcba8bb8 or main b774723f,
  # and no device node or devcall outside it
  echo "$VEND" | while read -r f b1 b2; do
    got=$(git -C "$src" hash-object "native/omegallm/gpu/$f")
    if [ "$got" = "$b1" ] || [ "$got" = "$b2" ]; then echo "vendored $f $got CUDApp_MATCH"; else echo "vendored $f $got CUDApp_MISMATCH"; fi
  done >> "$OUT/static.txt"
  if grep -q CUDApp_MISMATCH "$OUT/static.txt"; then echo "STATIC FAIL vendored_device_layer" >> "$OUT/static.txt"; ok=0; fi
  want=$(grep -c 'devcall ' "$src/native/omegallm/gpu/context.om")
  if [ "$nodes" != 3 ] || [ "$calls" != "$want" ]; then
    echo "STATIC FAIL second_device_layer nodes=$nodes calls=$calls want=3/$want" >> "$OUT/static.txt"; ok=0
  fi
fi
[ $ok = 1 ] || { cat "$OUT/static.txt"; exit 4; }
echo "STATIC PASS expected_exe_sha256 $d1" >> "$OUT/static.txt"
cat "$OUT/static.txt"
# 3. the live probe against the running server
cks=$(sha256sum "$CK" | cut -d' ' -f1)
mgs=$(sha256sum "$MERGES" | cut -d' ' -f1)
taskset -c "$CORES" nice -n 10 "$L" "$PORT" "$d1" "$GPU" "$CK" "$cks" "$MERGES" "$mgs" > "$OUT/live.txt" 2>&1
rc=$?
cat "$OUT/live.txt"
echo "LIVE rc=$rc receipt $OUT"
exit $rc
