#!/bin/sh
# DRA-146 example validator test: compiles native/personal/exvalid.om with the pinned omc and runs the
# SYNTHETIC fixtures in tests/personal/exvalid/. ok.tsv must pass every check (exit 0); each bad_*.tsv
# plants one violation (negative controls) and must print the named FAIL line with the stated exit.
#
#   OMC=path/to/omc  sh tests/personal/exvalid.sh
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
if [ -z "${EXVALID_PINNED:-}" ]; then
    EXVALID_PINNED=1 exec taskset -c "$CORE" nice -n 10 sh "$0" "$@"
fi
got=$(sha256sum "$OMC" | cut -d' ' -f1)
[ "$got" = "$PIN" ] || { echo "exvalid-test: omc sha256 $got is not the pin $PIN" >&2; exit 2; }
WORK=${WORK:-$(mktemp -d)}
mkdir -p "$WORK"
"$OMC" < "$root/native/personal/exvalid.om" > "$WORK/exvalid"; rc=$?
echo "exvalid-test: omc=${PIN%"${PIN#????????????????}"} compile=$rc"
[ $rc -eq 0 ] || { echo "FAIL compile (omc exit $rc)"; echo "SUMMARY pass=0 fail=1"; exit 1; }
chmod +x "$WORK/exvalid"
pass=0 fail=0
# case FILE EXIT [EXPECTED_LINE...]: exit status must match and every expected line must appear
case_() {
    f=$1 want=$2; shift 2
    "$WORK/exvalid" < "$here/exvalid/$f" > "$WORK/$f.out"; rc=$?
    ok=1
    [ "$rc" -eq "$want" ] || ok=0
    for l in "$@"; do grep -qxF "$l" "$WORK/$f.out" || ok=0; done
    nfail=$(grep -c '^FAIL ' "$WORK/$f.out")
    [ "$nfail" -eq $# ] || ok=0
    if [ $ok -eq 1 ]; then echo "PASS $f (exit $rc, FAIL lines $nfail)"; pass=$((pass + 1));
    else echo "FAIL $f (exit $rc want $want, FAIL lines $nfail want $#)"; sed 's/^/  | /' "$WORK/$f.out"; fail=$((fail + 1)); fi
}
case_ ok.tsv 0
case_ bad_user_target.tsv 1 "FAIL target_role_agent violations=1"
case_ bad_allowed_unverified.tsv 1 "FAIL allowed_only_verified_or_approved violations=1"
case_ bad_allowed_rejected.tsv 1 "FAIL allowed_only_verified_or_approved violations=1"
case_ bad_conv_two_splits.tsv 1 "FAIL conv_one_split violations=1"
case_ bad_shared_train_dev.tsv 1 "FAIL no_shared_hash_train_dev violations=1"
case_ bad_shared_train_test.tsv 1 "FAIL no_shared_hash_train_test violations=1"
case_ bad_shared_dev_test.tsv 1 "FAIL no_shared_hash_dev_test violations=1"
case_ bad_cond_oversize.tsv 1 "FAIL cond_bytes_le_600 violations=1"
case_ bad_target_oversize.tsv 1 "FAIL target_bytes_le_400 violations=1"
case_ bad_malformed.tsv 2 "FAIL well_formed_rows violations=1"
case_ ok_zero_one.tsv 0
case_ bad_same_zero.tsv 1 "FAIL no_shared_hash_train_dev violations=1"
case_ ok_dash.tsv 0
for m in bad_allowed_empty bad_allowed_two bad_hashes_empty bad_hashes_comma bad_hashes_hyphen bad_hashes_trailing bad_hashes_dash_more; do
    case_ $m.tsv 2 "FAIL well_formed_rows violations=1"
done
grep -qx "exvalid rows=6 convs=4 hashes=8 target_allowed=4" "$WORK/ok.tsv.out" \
    && { echo "PASS ok.tsv counts"; pass=$((pass + 1)); } || { echo "FAIL ok.tsv counts"; fail=$((fail + 1)); }
echo "SUMMARY pass=$pass fail=$fail"
[ $fail -eq 0 ]
