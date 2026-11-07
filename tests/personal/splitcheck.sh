#!/bin/sh
# DRA-146 v4 split checker test: compiles native/personal/splitcheck.om with the pinned omc and runs the
# SYNTHETIC fixtures in tests/personal/splitcheck/. ok.tsv must pass every check (exit 0); each bad_*.tsv
# plants one violation (negative controls) and must print the named FAIL line with the stated exit.
#
#   OMC=path/to/omc  sh tests/personal/splitcheck.sh
#
# Environment: OMC (required; must be omega-mv e5b32567 seed omc, sha256 2c824805...), WORK (scratch,
# default a mktemp dir), CORE (taskset core, default 0). Prints one PASS/FAIL line per case, then
# `SUMMARY pass=N fail=M`; exit 0 iff fail=0. No private data: the fixtures are synthetic.
set -u
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
PIN=2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f
OMC=${OMC:?set OMC to the pinned omc}
CORE=${CORE:-0}
if [ -z "${SPLITCHECK_PINNED:-}" ]; then
    SPLITCHECK_PINNED=1 exec taskset -c "$CORE" nice -n 10 sh "$0" "$@"
fi
got=$(sha256sum "$OMC" | cut -d' ' -f1)
[ "$got" = "$PIN" ] || { echo "splitcheck-test: omc sha256 $got is not the pin $PIN" >&2; exit 2; }
WORK=${WORK:-$(mktemp -d)}
mkdir -p "$WORK"
"$OMC" < "$root/native/personal/splitcheck.om" > "$WORK/splitcheck"; rc=$?
echo "splitcheck-test: omc=${PIN%"${PIN#????????????????}"} compile=$rc"
[ $rc -eq 0 ] || { echo "FAIL compile (omc exit $rc)"; echo "SUMMARY pass=0 fail=1"; exit 1; }
chmod +x "$WORK/splitcheck"
pass=0 fail=0
# case FILE EXIT [EXPECTED_LINE...]: exit status must match and every expected line must appear
case_() {
    f=$1 want=$2; shift 2
    "$WORK/splitcheck" < "$here/splitcheck/$f" > "$WORK/$f.out"; rc=$?
    ok=1
    [ "$rc" -eq "$want" ] || ok=0
    for l in "$@"; do grep -qxF "$l" "$WORK/$f.out" || ok=0; done
    nfail=$(grep -c '^FAIL ' "$WORK/$f.out")
    [ "$nfail" -eq $# ] || ok=0
    if [ $ok -eq 1 ]; then echo "PASS $f (exit $rc, FAIL lines $nfail)"; pass=$((pass + 1));
    else echo "FAIL $f (exit $rc want $want, FAIL lines $nfail want $#)"; sed 's/^/  | /' "$WORK/$f.out"; fail=$((fail + 1)); fi
}
case_ ok.tsv 0
case_ ok_dash.tsv 0
case_ bad_two_splits.tsv 1 "FAIL conv_one_split violations=1" "FAIL split_matches_cutoffs violations=1"
case_ bad_cutoff.tsv 1 "FAIL split_matches_cutoffs violations=1"
case_ bad_start_ts.tsv 1 "FAIL conv_one_start_ts violations=1"
case_ bad_train_dev_text.tsv 1 "FAIL no_shared_hash_train_dev violations=1"
case_ bad_train_test_shingle.tsv 1 "FAIL no_shared_hash_train_test violations=1"
case_ bad_dev_test_shingle.tsv 1 "FAIL no_shared_hash_dev_test violations=1"
case_ bad_malformed.tsv 2 "FAIL well_formed_rows violations=1"
case_ ok_zero_one.tsv 0
case_ bad_zero_shared.tsv 1 "FAIL no_shared_hash_train_dev violations=1"
case_ ok_ts_forms.tsv 0
for m in bad_split_prefix_trash bad_split_prefix_d bad_split_testing bad_ts_junk bad_ts_calendar bad_ts_feb29 \
         bad_ts_offset bad_ts_nofrac bad_hash_empty bad_hash_dash_inside bad_shingle_empty_token bad_shingle_trailing; do
    case_ $m.tsv 2 "FAIL well_formed_rows violations=1"
done
# declared conversation capacity: 786432 distinct conversations pass, one more is a full table (exit 2)
awk 'BEGIN { for (i = 1; i <= 786432; i++) printf "syn:k%d\ttrain\t2026-10-20T10:00:00Z\t-\t-\n", i }' > "$WORK/cap_ok.tsv"
{ cat "$WORK/cap_ok.tsv"; printf 'syn:k786433\ttrain\t2026-10-20T10:00:00Z\t-\t-\n'; } > "$WORK/cap_over.tsv"
"$WORK/splitcheck" < "$WORK/cap_ok.tsv" > "$WORK/cap_ok.out"; r1=$?
"$WORK/splitcheck" < "$WORK/cap_over.tsv" > "$WORK/cap_over.out"; r2=$?
if [ $r1 -eq 0 ] && [ $r2 -eq 2 ] && grep -qxF "FAIL table_capacity violations=1" "$WORK/cap_over.out"; then
    echo "PASS conversation capacity (786432 exit $r1, 786433 exit $r2)"; pass=$((pass + 1))
else echo "FAIL conversation capacity (786432 exit $r1, 786433 exit $r2)"; fail=$((fail + 1)); fi
grep -qx "splitcheck rows=8 convs=6 hashes=12 train=4 dev=2 test=2" "$WORK/ok.tsv.out" \
    && { echo "PASS ok.tsv counts"; pass=$((pass + 1)); } || { echo "FAIL ok.tsv counts"; fail=$((fail + 1)); }
echo "SUMMARY pass=$pass fail=$fail"
[ $fail -eq 0 ]
