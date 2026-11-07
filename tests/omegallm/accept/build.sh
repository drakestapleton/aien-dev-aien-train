#!/bin/sh
# Build the DRA-124 acceptance runner: om2 + net/http.om + net/json.om + accept.om -> $OUT/accept.
# Usage: OMC=<pinned omc> OUT=<dir> CORE=<core> sh tests/omegallm/accept/build.sh [--mutant line|exec|crit|ctx]
# A mutant build sets const ACMUT in accept.om (1 line glob matches anything, 2 exec ignores the test
# exit status, 3 the critical-command scan finds nothing, 4 the gate verdict skips the context-window check);
# controls.sh requires each mutant to be caught.
set -eu
R=$(cd "$(dirname "$0")/../../.." && pwd)
: "${OMC:?set OMC to the pinned omc}"
: "${OUT:?set OUT}"
: "${CORE:?set CORE (assigned core)}"
M=0
NAME=accept
if [ "${1:-}" = "--mutant" ]; then
  case "${2:-}" in
    line) M=1 ;; exec) M=2 ;; crit) M=3 ;; ctx) M=4 ;;
    *) echo "unknown mutant ${2:-}" >&2; exit 2 ;;
  esac
  NAME=accept-mut-$2
fi
mkdir -p "$OUT"
{ printf 'om2\n'; cat "$R/native/omegallm/net/http.om" "$R/native/omegallm/net/json.om"
  sed "s/^const ACMUT ulong 0\$/const ACMUT ulong $M/" "$R/tests/omegallm/accept/accept.om"; } > "$OUT/$NAME.om"
if [ "$M" != 0 ] && ! grep -q "^const ACMUT ulong $M\$" "$OUT/$NAME.om"; then echo "mutant not applied" >&2; exit 3; fi
set +e
taskset -c "$CORE" nice -n 10 "$OMC" < "$OUT/$NAME.om" > "$OUT/$NAME" 2> "$OUT/$NAME.err"
rc=$?
set -e
if [ $rc -ne 0 ]; then cat "$OUT/$NAME.err" >&2; rm -f "$OUT/$NAME"; echo "omc rc=$rc" >&2; exit 1; fi
chmod +x "$OUT/$NAME"
echo "built $OUT/$NAME $(sha256sum "$OUT/$NAME" | cut -c1-64)"
