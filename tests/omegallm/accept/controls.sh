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
#  C5 ref stub declaring context 4096 in GET /health (model.T): every gated role (harness too) FAILS with
#     verdict_reason context_below_prereg although its rows pass (CHANGES.md C1); C1 runs the same stub at 8192.
#  M5 build mutant ctx (the verdict skips the context check) summing C5's rows: some gated role PASSES (caught).
#  C6 ref stub whose /health has no model.T and no CTX: every gated role FAILS with context_unknown.
#  C7 the same stub with CTX=8192 (declared): the chat roles PASS as in C1.
#  C8 sum's CTX fallback on C5's rows with the context records removed: no CTX -> context_unknown,
#     CTX=8191 -> context_below_prereg, CTX=8192 -> the chat roles PASS.
#  C4 (with HARNESS and VERIFY set): the harness lane's fixture:ref must PASS and fixture:plain FAIL the 18
#     held-out harness tasks through the ingestion path (fixture on PORT, proxy on HPPORT, default 18297).
#     The scripted fixture serves no model.T, so its runner is given CTX=8192 (declared).
# The verdict tables are printed by `accept sum`; this driver only compares their counts.
set -eu
unset CTX
HARNESS_HOME=${HARNESS_HOME:-$HOME/work/hive/ownmodel/accept/hh}; export HARNESS_HOME
W=$1; PORT=${2:-18298}
D=$(cd "$(dirname "$0")" && pwd)
: "${OMC:?}"; : "${CORE:?}"
HOLDOUT=${HOLDOUT:-$HOME/work/hive/ownmodel/accept/holdout}
rm -rf "$W"; mkdir -p "$W/bin" "$W/suite"; chmod 700 "$W"
OUT="$W/bin" sh "$D/build.sh" >/dev/null
for m in line exec crit ctx; do OUT="$W/bin" sh "$D/build.sh" --mutant $m >/dev/null; done
cp "$W/bin/accept" "$W/bin/stub"
( cd "$D/suite" && sha256sum -c --quiet SHA256SUMS )
[ "$(grep ' items-test.jsonl$' "$D/suite/HOLDOUT.sha256" | cut -c1-64)" = "$(sha256sum "$HOLDOUT/items-test.jsonl" | cut -c1-64)" ]
cat "$D/suite/items-dev.jsonl" "$HOLDOUT/items-test.jsonl" "$D/suite/controls.jsonl" > "$W/suite/items.jsonl"
cp "$D/suite/ifeval.jsonl" "$D/suite/humaneval.jsonl" "$D/suite/harness.jsonl" "$D/suite/hive-system.txt" "$D/suite/critical.txt" "$W/suite/"
TH="$D/suite/thresholds.tsv"
SPID=
stub() { # stub MODE T: T > 0 declares context T in GET /health (model.T); 0 serves /health without model
  [ -z "$SPID" ] || { kill "$SPID"; wait "$SPID" 2>/dev/null || true; }
  taskset -c "$CORE" nice -n 10 "$W/bin/stub" stub "$PORT" "$1" "$W/suite" 1000000000 "$2" > "$W/stub-$1-$2.log" 2>&1 & SPID=$!; sleep 0.5; }
trap '[ -z "$SPID" ] || kill "$SPID" 2>/dev/null || true' EXIT
RUNCTX=
run() { # run NAME BINARY [MUTANTOP]; RUNCTX non-empty gives the runners CTX=RUNCTX
  mkdir -p "$W/$1"
  env ${RUNCTX:+CTX=$RUNCTX} taskset -c "$CORE" nice -n 10 "$2" run 127.0.0.1 "$PORT" "$W/suite" "$W/$1" "$OMC" control 0 1 0 2 ${3:-} &
  a=$!
  env ${RUNCTX:+CTX=$RUNCTX} taskset -c "$CORE" nice -n 10 "$2" run 127.0.0.1 "$PORT" "$W/suite" "$W/$1" "$OMC" control 0 1 1 2 ${3:-} &
  b=$!
  wait $a; wait $b
  set +e; "$W/bin/accept" sum "$W/$1" "$TH" > "$W/$1.sum"; echo "$1 sum rc $?" >> "$W/controls.txt"; set -e
}
famp() { awk -F'\t' -v f="$2" '$3==f {p+=$4; n+=$5} END {print p+0, n+0}' "$W/$1.sum"; }
gated() { awk -F'\t' -v r="$2" '$1==r && $2=="test" {print $16}' "$W/$1.sum"; }
passes() { awk -F'\t' -v r="$2" '$1==r && NF>=16 {p+=$4} END {print p+0}' "$W/$1.sum"; }
vr() { awk -F'\t' -v r="$2" '$1==r && $2=="test" && NF>=17 {print $16 "/" $17}' "$W/$1.sum"; }
ctxl() { awk -F'\t' '$1=="context" {print $2, $3}' "$W/$1.sum"; }
famsum() { awk -F'\t' -v f="$2" 'NF==5 && $3!=f && $3!="family" {p+=$4} END {print p+0}' "$W/$1.sum"; }
fail=0
ok() { echo "PASS $*" >> "$W/controls.txt"; }
bad() { echo "FAIL $*" >> "$W/controls.txt"; fail=1; }
: > "$W/controls.txt"
stub ref 8192
run ref "$W/bin/accept"
[ "$(ctxl ref)" = "8192 health" ] && ok "C1 ref context 8192 health" || bad "C1 ref context $(ctxl ref)"
for r in assistant coding hive; do [ "$(vr ref $r)" = PASS/ok ] && ok "C1 ref $r verdict_reason ok" || bad "C1 ref $r $(vr ref $r)"; done
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
G4="assistant coding hive harness"
stub ref 4096
run ref4096 "$W/bin/accept"
[ "$(ctxl ref4096)" = "4096 health" ] && ok "C5 ref4096 context 4096 health" || bad "C5 ref4096 context $(ctxl ref4096)"
for r in $G4; do [ "$(vr ref4096 $r)" = FAIL/context_below_prereg ] && ok "C5 ref4096 $r test FAIL context_below_prereg" || bad "C5 ref4096 $r $(vr ref4096 $r)"; done
for r in assistant coding hive; do set -- $(awk -F'\t' -v r=$r '$1==r && $2=="test" {print $3, $4}' "$W/ref4096.sum")
  [ "${1:-0}" -gt 0 ] && [ "$1" = "$2" ] && ok "C5 ref4096 $r test rows $2/$1 PASS (the context alone fails it)" || bad "C5 ref4096 $r test rows ${2:-?}/${1:-?}"; done
set +e; "$W/bin/accept-mut-ctx" sum "$W/ref4096" "$TH" > "$W/m5.sum"; echo "m5 sum rc $?" >> "$W/controls.txt"; set -e
t=0; for r in assistant coding hive; do [ "$(gated m5 $r)" = PASS ] && t=$((t + 1)); done
[ $t -gt 0 ] && ok "M5 mutant ctx caught ($t gated roles PASS at context 4096)" || bad "M5 mutant ctx not caught"
stub ref 0
run refunk "$W/bin/accept"
[ "$(ctxl refunk)" = "- unknown" ] && ok "C6 refunk context unknown" || bad "C6 refunk context $(ctxl refunk)"
for r in $G4; do [ "$(vr refunk $r)" = FAIL/context_unknown ] && ok "C6 refunk $r test FAIL context_unknown" || bad "C6 refunk $r $(vr refunk $r)"; done
RUNCTX=8192
run refdecl "$W/bin/accept"
RUNCTX=
[ "$(ctxl refdecl)" = "8192 declared" ] && ok "C7 refdecl context 8192 declared" || bad "C7 refdecl context $(ctxl refdecl)"
for r in assistant coding hive; do [ "$(vr refdecl $r)" = PASS/ok ] && ok "C7 refdecl $r test PASS" || bad "C7 refdecl $r $(vr refdecl $r)"; done
mkdir -p "$W/nctx"; cp "$W"/ref4096/results-*.tsv "$W/nctx/"
for c in none 8191 8192; do
  set +e; if [ $c = none ]; then "$W/bin/accept" sum "$W/nctx" "$TH" > "$W/nctx-$c.sum"; else CTX=$c "$W/bin/accept" sum "$W/nctx" "$TH" > "$W/nctx-$c.sum"; fi
  echo "nctx-$c sum rc $?" >> "$W/controls.txt"; set -e
done
for r in $G4; do [ "$(vr nctx-none $r)" = FAIL/context_unknown ] && ok "C8 sum no record no CTX $r FAIL context_unknown" || bad "C8 nctx-none $r $(vr nctx-none $r)"; done
for r in $G4; do [ "$(vr nctx-8191 $r)" = FAIL/context_below_prereg ] && ok "C8 sum CTX=8191 $r FAIL context_below_prereg" || bad "C8 nctx-8191 $r $(vr nctx-8191 $r)"; done
[ "$(ctxl nctx-8192)" = "8192 sum_env" ] && ok "C8 sum CTX=8192 context 8192 sum_env" || bad "C8 nctx-8192 context $(ctxl nctx-8192)"
for r in assistant coding hive; do [ "$(vr nctx-8192 $r)" = PASS/ok ] && ok "C8 sum CTX=8192 $r PASS" || bad "C8 nctx-8192 $r $(vr nctx-8192 $r)"; done
stub garbage 8192
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
    CTX=8192 ACCEPT_HARNESS_TSV=$W/h-$fx/summary.txt "$W/bin/accept" run 127.0.0.1 "$PORT" "$W/hsuite" "$W/h$fx" "$OMC" control 0 1 0 1
    set +e; "$W/bin/accept" sum "$W/h$fx" "$TH" > "$W/h$fx.sum"; set -e
  done
  set -- $(awk -F'\t' '$1=="harness" && $2=="test" && NF>=16 {print $3, $4, $16}' "$W/href.sum")
  [ "${3:-}" = PASS ] && ok "C4 harness fixture:ref $2/$1 PASS" || bad "C4 harness fixture:ref ${2:-?}/${1:-?} ${3:-?}"
  set -- $(awk -F'\t' '$1=="harness" && $2=="test" && NF>=16 {print $3, $4, $16}' "$W/hplain.sum")
  [ "${2:-x}" = 0 ] && ok "C4 harness fixture:plain 0/$1 PASS" || bad "C4 harness fixture:plain ${2:-?}/${1:-?}"
fi
{ echo "accept $(sha256sum "$W/bin/accept" | cut -c1-64)"; for m in line exec crit ctx; do echo "accept-mut-$m $(sha256sum "$W/bin/accept-mut-$m" | cut -c1-64)"; done; } >> "$W/controls.txt"
cat "$W/controls.txt"
[ $fail = 0 ] && echo "CONTROLS PASS" || { echo "CONTROLS FAIL"; exit 1; }
