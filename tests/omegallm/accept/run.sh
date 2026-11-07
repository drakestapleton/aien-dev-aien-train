#!/bin/sh
# DRA-124 acceptance run against one OpenAI-compatible endpoint (PREREG.md is normative).
# Usage: sh tests/omegallm/accept/run.sh HOST PORT OUTDIR [MODEL]
# Env: ACCEPT (runner binary, built by build.sh), OMC (pinned omc, for omega exec items), CORES (assigned
#   cores for taskset), SPLITS (default "dev test"; "train" for the public training split), HOLDOUT (the
#   private test split dir, default ~/work/hive/ownmodel/accept/holdout), NWORKERS (default 2: the
#   pre-registered concurrency), PUBLIC (default 1; 0 leaves the public IFEval / HumanEval dev rows out), REPEATS (stochastic seeds, default 3), STEMP (their temperature in
#   thousandths, default 700), HARNESS (the harness lane's tests/omegallm/harness dir on feat/ollm-harness;
#   with VERIFY, its verify binary, the private held-out harness tasks HOLDOUT/harness-test.txt run through its
#   run.sh against http://HOST:PORT/v1 with proxy port HPPORT, default 18298; else harness rows are NOT_RUN).
# Context window (PREREG section 4, >= 8192 tokens per gated role; CHANGES.md C1): every runner records the
#   endpoint's served context in OUTDIR/ARM/context-W.tsv from GET /health "model":{"T":..} (ollm serve);
#   for an endpoint whose /health has no model.T, CTX (decimal tokens) is REQUIRED and recorded as declared.
#   /health model.T wins over CTX. Unknown (neither) or below the gate's ctx_min FAILS every gated role
#   (verdict_reason context_unknown / context_below_prereg), whatever its rows say. `accept sum` on an
#   outdir without context records (runs before this fix) uses CTX from its environment (source sum_env).
# Arms: t0 (temperature 0, seed 1: the gated arm) and s1..sREPEATS (temperature STEMP, seed k).
# Every number is printed by the .om runner (`accept sum`, `accept pair`); this driver only assembles the
# suite, checks its frozen hashes and starts the workers.
set -eu
HARNESS_HOME=${HARNESS_HOME:-$HOME/work/hive/ownmodel/accept/hh}; export HARNESS_HOME
[ $# -ge 3 ] || { echo "usage: run.sh HOST PORT OUTDIR [MODEL]" >&2; exit 2; }
HOST=$1; PORT=$2; OUT=$3; MODEL=${4:-candidate}
D=$(cd "$(dirname "$0")" && pwd)
: "${ACCEPT:?set ACCEPT to the built runner}"; : "${OMC:?set OMC}"; : "${CORES:?set CORES}"
SPLITS=${SPLITS:-"dev test"}; HOLDOUT=${HOLDOUT:-$HOME/work/hive/ownmodel/accept/holdout}
NW=${NWORKERS:-2}; REPEATS=${REPEATS:-3}; STEMP=${STEMP:-700}
mkdir -p "$OUT/suite"
# 1. frozen hashes: the committed suite files and the private test split
( cd "$D/suite" && sha256sum -c --quiet SHA256SUMS ) || { echo "suite hash mismatch" >&2; exit 4; }
: > "$OUT/suite/items.jsonl"
for sp in $SPLITS; do
  case $sp in
    train|dev) cat "$D/suite/items-$sp.jsonl" >> "$OUT/suite/items.jsonl" ;;
    test) want=$(grep ' items-test.jsonl$' "$D/suite/HOLDOUT.sha256" | cut -c1-64); got=$(sha256sum "$HOLDOUT/items-test.jsonl" | cut -c1-64)
          [ "$want" = "$got" ] || { echo "holdout hash mismatch: $got != $want" >&2; exit 4; }
          cat "$HOLDOUT/items-test.jsonl" >> "$OUT/suite/items.jsonl"
          cp "$D/suite/harness.jsonl" "$OUT/suite/" ;;
    *) echo "unknown split $sp" >&2; exit 2 ;;
  esac
done
if [ "${PUBLIC:-1}" = 1 ]; then
  case " $SPLITS " in *" dev "*) cp "$D/suite/ifeval.jsonl" "$D/suite/humaneval.jsonl" "$OUT/suite/" ;; esac
fi
cp "$D/suite/hive-system.txt" "$D/suite/critical.txt" "$OUT/suite/"
chmod -R go-rwx "$OUT"
{ echo "accept $(sha256sum "$ACCEPT" | cut -c1-64)"; echo "omc $(sha256sum "$OMC" | cut -c1-64)"
  echo "prereg $(sha256sum "$D/PREREG.md" | cut -c1-64)"; echo "thresholds $(sha256sum "$D/suite/thresholds.tsv" | cut -c1-64)"
  echo "endpoint $HOST:$PORT model $MODEL splits $SPLITS public ${PUBLIC:-1} workers $NW repeats $REPEATS stemp $STEMP"
  echo "ctx-declared ${CTX:--}"
  echo "start $(date -u +%Y-%m-%dT%H:%M:%SZ)"; } > "$OUT/receipt.txt"
comb() { # verdict codes: FAIL 1 beats NOT_RUN 3 beats PASS 0
  if [ "$1" = 1 ] || [ "$2" = 1 ]; then echo 1; elif [ "$1" = 3 ] || [ "$2" = 3 ]; then echo 3; else echo "$2"; fi; }
arm() { # arm NAME TEMPMILLI SEED
  mkdir -p "$OUT/$1"; w=0; pids=
  while [ $w -lt "$NW" ]; do
    taskset -c "$CORES" nice -n 10 "$ACCEPT" run "$HOST" "$PORT" "$OUT/suite" "$OUT/$1" "$OMC" "$MODEL" "$2" "$3" $w "$NW" &
    pids="$pids $!"; w=$((w + 1))
  done
  rc=0; for p in $pids; do wait "$p" || rc=$?; done
  echo "arm $1 temp $2 seed $3 runner rc $rc" >> "$OUT/receipt.txt"
  [ $rc -eq 0 ] || { echo "runner failed rc=$rc (arm $1)" >&2; exit 4; }
}
if [ -n "${HARNESS:-}" ] && case " $SPLITS " in *" test "*) true ;; *) false ;; esac; then
  : "${VERIFY:?set VERIFY with HARNESS}"
  want=$(grep ' harness-test.txt$' "$D/suite/HOLDOUT.sha256" | cut -c1-64)
  [ "$want" = "$(sha256sum "$HOLDOUT/harness-test.txt" | cut -c1-64)" ] || { echo "harness holdout hash mismatch" >&2; exit 4; }
  echo "harness $(cd "$HARNESS" && git rev-parse HEAD) verify $(sha256sum "$VERIFY" | cut -c1-64)" >> "$OUT/receipt.txt"
  PPORT=${HPPORT:-18298} CORES=$CORES VERIFY=$VERIFY sh "$HARNESS/run.sh" "http://$HOST:$PORT/v1" "$HOLDOUT/harness-test.txt" "$OUT/harness" > "$OUT/harness.log" 2>&1 || true
  ACCEPT_HARNESS_TSV=$OUT/harness/summary.txt; export ACCEPT_HARNESS_TSV
fi
arm t0 0 1
set +e
"$ACCEPT" sum "$OUT/t0" "$D/suite/thresholds.tsv" > "$OUT/t0.summary"; v=$?
set -e
echo "sum t0 rc $v" >> "$OUT/receipt.txt"
grep '^context' "$OUT/t0.summary" >> "$OUT/receipt.txt" || true
k=1
while [ $k -le "$REPEATS" ]; do
  arm s$k "$STEMP" $k
  set +e
  "$ACCEPT" sum "$OUT/s$k" "$D/suite/thresholds-stochastic.tsv" > "$OUT/s$k.summary"; sv=$?
  "$ACCEPT" pair "$OUT/t0" "$OUT/s$k" > "$OUT/pair-t0-s$k.tsv"
  set -e
  echo "sum s$k rc $sv" >> "$OUT/receipt.txt"
  v=$(comb "$v" "$sv")
  k=$((k + 1))
done
echo "end $(date -u +%Y-%m-%dT%H:%M:%SZ) verdict-rc $v" >> "$OUT/receipt.txt"
cat "$OUT/t0.summary"
exit "$v"
