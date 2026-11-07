#!/bin/sh
# DRA-124 controls (PREREG.md section 6): protocol controls, labelled NOT capability.
# Usage: OMC=<pinned omc> CORE=<core> sh tests/omegallm/accept/controls.sh WORKDIR [PORT]
#  C1 ref stub (always correct by construction): every deterministic gated row PASS, harness NOT_RUN.
#  C2 garbage stub (always wrong): 0 PASS rows.
#  C3 crit / glob control items under the ref stub: expect-fail families all FAIL, expect-pass all PASS.
#  M1 build mutant line (glob matches anything) vs garbage: some hive row must PASS (the mutant is caught).
#  M2 build mutant exec (test exit and nonce ignored) vs garbage: some coding row must PASS (caught).
#  M3 build mutant crit (scan finds nothing) vs ref + controls: some crit-expect-fail row must PASS (caught).
#  M4 runtime MUTANTOP exact (the exact rule inverted) vs ref: hive test must FAIL (caught).
#  C4 (with HARNESS and VERIFY set): the harness lane's fixture:ref must PASS and fixture:plain FAIL the 18
#     held-out harness tasks through the ingestion path (fixture on PORT, proxy on HPPORT, default 18297).
# The verdict tables are printed by `accept sum`; this driver only compares their counts.
set -eu
HARNESS_HOME=${HARNESS_HOME:-$HOME/work/hive/ownmodel/accept/hh}; export HARNESS_HOME
W=$1; PORT=${2:-18298}
D=$(cd "$(dirname "$0")" && pwd)
: "${OMC:?}"; : "${CORE:?}"
HOLDOUT=${HOLDOUT:-$HOME/work/hive/ownmodel/accept/holdout}
rm -rf "$W"; mkdir -p "$W/bin" "$W/suite"; chmod 700 "$W"
OUT="$W/bin" sh "$D/build.sh" >/dev/null
for m in line exec crit; do OUT="$W/bin" sh "$D/build.sh" --mutant $m >/dev/null; done
cp "$W/bin/accept" "$W/bin/stub"
( cd "$D/suite" && sha256sum -c --quiet SHA256SUMS )
[ "$(grep ' items-test.jsonl$' "$D/suite/HOLDOUT.sha256" | cut -c1-64)" = "$(sha256sum "$HOLDOUT/items-test.jsonl" | cut -c1-64)" ]
cat "$D/suite/items-dev.jsonl" "$HOLDOUT/items-test.jsonl" "$D/suite/controls.jsonl" > "$W/suite/items.jsonl"
cp "$D/suite/ifeval.jsonl" "$D/suite/humaneval.jsonl" "$D/suite/harness.jsonl" "$D/suite/hive-system.txt" "$D/suite/critical.txt" "$W/suite/"
TH="$D/suite/thresholds.tsv"
SPID=
stub() { [ -z "$SPID" ] || { kill "$SPID"; wait "$SPID" 2>/dev/null || true; }
  taskset -c "$CORE" nice -n 10 "$W/bin/stub" stub "$PORT" "$1" "$W/suite" > "$W/stub-$1.log" 2>&1 & SPID=$!; sleep 0.5; }
trap '[ -z "$SPID" ] || kill "$SPID" 2>/dev/null || true' EXIT
run() { # run NAME BINARY [MUTANTOP]
  mkdir -p "$W/$1"
  taskset -c "$CORE" nice -n 10 "$2" run 127.0.0.1 "$PORT" "$W/suite" "$W/$1" "$OMC" control 0 1 0 2 ${3:-} &
  a=$!
  taskset -c "$CORE" nice -n 10 "$2" run 127.0.0.1 "$PORT" "$W/suite" "$W/$1" "$OMC" control 0 1 1 2 ${3:-} &
  b=$!
  wait $a; wait $b
  set +e; "$W/bin/accept" sum "$W/$1" "$TH" > "$W/$1.sum"; echo "$1 sum rc $?" >> "$W/controls.txt"; set -e
}
famp() { awk -F'\t' -v f="$2" '$3==f {p+=$4; n+=$5} END {print p+0, n+0}' "$W/$1.sum"; }
gated() { awk -F'\t' -v r="$2" '$1==r && $2=="test" {print $16}' "$W/$1.sum"; }
passes() { awk -F'\t' -v r="$2" '$1==r && NF>=16 {p+=$4} END {print p+0}' "$W/$1.sum"; }
famsum() { awk -F'\t' -v f="$2" 'NF==5 && $3!=f && $3!="family" {p+=$4} END {print p+0}' "$W/$1.sum"; }
fail=0
ok() { echo "PASS $*" >> "$W/controls.txt"; }
bad() { echo "FAIL $*" >> "$W/controls.txt"; fail=1; }
: > "$W/controls.txt"
stub ref
run ref "$W/bin/accept"
for r in assistant coding hive; do [ "$(gated ref $r)" = PASS ] && ok "C1 ref $r test PASS" || bad "C1 ref $r test $(gated ref $r)"; done
[ "$(gated ref harness)" = NOT_RUN ] && ok "C1 ref harness NOT_RUN (no harness results)" || bad "C1 harness $(gated ref harness)"
for r in assistant coding hive; do set -- $(awk -F'\t' -v r=$r '$1==r && $2=="dev" {print $3, $4}' "$W/ref.sum")
  [ "$1" = "$2" ] && ok "C1 ref $r dev $2/$1" || bad "C1 ref $r dev $2/$1"; done
for f in control-crit-expect-fail control-glob-expect-fail; do set -- $(famp ref $f)
  [ "$1" = 0 ] && [ "$2" -gt 0 ] && ok "C3 $f 0/$2 PASS" || bad "C3 $f $1/$2 PASS"; done
for f in control-crit-expect-pass control-glob-expect-pass; do set -- $(famp ref $f)
  [ "$1" = "$2" ] && [ "$2" -gt 0 ] && ok "C3 $f $1/$2 PASS" || bad "C3 $f $1/$2 PASS"; done
run m4 "$W/bin/accept" exact
[ "$(gated m4 hive)" = FAIL ] && ok "M4 MUTANTOP exact caught (hive test FAIL)" || bad "M4 not caught: $(gated m4 hive)"
run m3 "$W/bin/accept-mut-crit"
set -- $(famp m3 control-crit-expect-fail)
[ "$1" -gt 0 ] && ok "M3 mutant crit caught ($1/$2 crit-expect-fail rows PASS)" || bad "M3 mutant crit not caught"
stub garbage
run garbage "$W/bin/accept"
# IFEval prompt-level strict accuracy gives a floor to the constant reply "zq": the upstream oracle
# (oracle/ifeval_oracle.py, recorded in suite/selftest.jsonl) passes exactly 50 registered rows with it.
set -- $(famp garbage ifeval-public)
[ "$1" = 50 ] && ok "C2 garbage ifeval-public $1/$2 PASS = the upstream-oracle floor 50 for reply zq" || bad "C2 garbage ifeval-public $1/$2 (oracle floor 50)"
t=$(famsum garbage ifeval-public)
[ "$t" = 0 ] && ok "C2 garbage 0 PASS rows in every other family (own items, HumanEval, controls)" || bad "C2 garbage $t PASS rows outside ifeval-public"
for r in assistant coding hive; do [ "$(gated garbage $r)" = FAIL ] && ok "C2 garbage $r test FAIL" || bad "C2 garbage $r test $(gated garbage $r)"; done
run m1 "$W/bin/accept-mut-line"
[ "$(passes m1 hive)" -gt 0 ] && ok "M1 mutant line caught ($(passes m1 hive) hive rows PASS on garbage)" || bad "M1 mutant line not caught"
run m2 "$W/bin/accept-mut-exec"
[ "$(passes m2 coding)" -gt 0 ] && ok "M2 mutant exec caught ($(passes m2 coding) coding rows PASS on garbage)" || bad "M2 mutant exec not caught"
if [ -n "${HARNESS:-}" ]; then
  # C4: the harness lane's scripted fixtures through the ingestion path (protocol only, not capability)
  [ -z "$SPID" ] || { kill "$SPID"; wait "$SPID" 2>/dev/null || true; SPID=; }
  : "${VERIFY:?set VERIFY with HARNESS}"
  mkdir -p "$W/hsuite"; cp "$D/suite/harness.jsonl" "$D/suite/critical.txt" "$W/hsuite/"
  [ "$(grep ' harness-test.txt$' "$D/suite/HOLDOUT.sha256" | cut -c1-64)" = "$(sha256sum "$HOLDOUT/harness-test.txt" | cut -c1-64)" ]
  for fx in ref plain; do
    FPORT=$PORT PPORT=${HPPORT:-18297} CORES=$CORE VERIFY=$VERIFY sh "$HARNESS/run.sh" fixture:$fx "$HOLDOUT/harness-test.txt" "$W/h-$fx" > "$W/h-$fx.log" 2>&1 || true
    mkdir -p "$W/h$fx"
    ACCEPT_HARNESS_TSV=$W/h-$fx/summary.txt "$W/bin/accept" run 127.0.0.1 "$PORT" "$W/hsuite" "$W/h$fx" "$OMC" control 0 1 0 1
    set +e; "$W/bin/accept" sum "$W/h$fx" "$TH" > "$W/h$fx.sum"; set -e
  done
  set -- $(awk -F'\t' '$1=="harness" && $2=="test" && NF>=16 {print $3, $4, $16}' "$W/href.sum")
  [ "${3:-}" = PASS ] && ok "C4 harness fixture:ref $2/$1 PASS" || bad "C4 harness fixture:ref ${2:-?}/${1:-?} ${3:-?}"
  set -- $(awk -F'\t' '$1=="harness" && $2=="test" && NF>=16 {print $3, $4, $16}' "$W/hplain.sum")
  [ "${2:-x}" = 0 ] && ok "C4 harness fixture:plain 0/$1 PASS" || bad "C4 harness fixture:plain ${2:-?}/${1:-?}"
fi
{ echo "accept $(sha256sum "$W/bin/accept" | cut -c1-64)"; for m in line exec crit; do echo "accept-mut-$m $(sha256sum "$W/bin/accept-mut-$m" | cut -c1-64)"; done; } >> "$W/controls.txt"
cat "$W/controls.txt"
[ $fail = 0 ] && echo "CONTROLS PASS" || { echo "CONTROLS FAIL"; exit 1; }
