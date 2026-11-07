#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# DRA-146 personal memory checks on SYNTHETIC stores (native/personal/mem.om).
# Usage: MEM=path/to/mem MEMNS=path/to/mem-nosup sh tests/personal/mem-check.sh
# Each case prints `CASE name rc=N bytes=N` and the exact stdout bytes (indented), then PASS/FAIL. The
# supersession cases are rerun on MEMNS (OMSUP 0, supersession disabled) and must FAIL there
# (`negative control caught`). Ends MEM_PASS or MEM_FAIL (exit 1).
set -u
MEM=${MEM:?}; MEMNS=${MEMNS:?}
W=$(mktemp -d "${TMPDIR:-/tmp}/memck.XXXXXX")
bad=0
ok() { echo "PASS $*"; }
no() { echo "FAIL $*"; bad=1; }
echo "mem_sha256=$(sha256sum "$MEM" | cut -d' ' -f1)"
echo "mem_nosup_sha256=$(sha256sum "$MEMNS" | cut -d' ' -f1)"
T1=2026-09-01T10:00:00Z; T2=2026-10-05T10:00:00Z; T3=2026-10-20T08:30:00Z
show() { echo "CASE $1 rc=$2 bytes=$(wc -c < "$3" | tr -d ' ')"; sed 's/^/    | /' "$3"; }
# run QUERY on store S with binary B, compare with expected file E
qcase() { # name bin store k text expected
  "$2" query "$3" "$4" "$5" > "$W/out" 2>&1; r=$?
  [ "$2" = "$MEM" ] && show "$1" $r "$W/out"
  [ $r -eq 0 ] && cmp -s "$W/out" "$6"
}
build() { # bin store-name: the synthetic stores
  B=$1; S=$W/$2; rm -f "$S"
  case ${2#ns-} in
  stale)  "$B" add "$S" preference "editor indent" "use tabs" $T1 syn:c1:r1 > /dev/null
          "$B" add "$S" preference "editor indent" "never use tabs, use 4 spaces" $T2 syn:c2:r7 > /dev/null ;;
  chain)  "$B" add "$S" fact "deploy host" "alpha" $T1 syn:c3:r1 > /dev/null
          "$B" correct "$S" 1 fact "deploy host" "beta" $T2 syn:c3:r4 > /dev/null
          "$B" correct "$S" 2 fact "deploy host" "gamma" $T3 syn:c4:r2 > /dev/null ;;
  retract) "$B" add "$S" decision "gpu lease mode" "exclusive" $T1 syn:c5:r1 > /dev/null
          "$B" retract "$S" 1 $T2 syn:c5:r9 > /dev/null ;;
  retchain) "$B" add "$S" fact "mirror url" "old mirror" $T1 syn:c6:r1 > /dev/null
          "$B" correct "$S" 1 fact "mirror url" "new mirror" $T2 syn:c6:r2 > /dev/null
          "$B" retract "$S" 2 $T3 syn:c6:r3 > /dev/null ;;
  tie)    "$B" add "$S" preference "login shell" "bash" $T2 syn:c7:r1 > /dev/null
          "$B" add "$S" preference "login shell" "zsh" $T2 syn:c7:r2 > /dev/null ;;
  kinds)  "$B" add "$S" preference "deploy" "manual approval" $T1 syn:c8:r1 > /dev/null
          "$B" add "$S" project_fact "deploy" "runs via ci" $T2 syn:c8:r2 > /dev/null ;;
  old)    "$B" add "$S" preference "editor" "use emacs" $T1 syn:c9:r1 > /dev/null
          "$B" add "$S" preference "Editor" "use vim" $T2 syn:c9:r2 > /dev/null ;;
  esac
}
for s in stale chain retract retchain tie kinds old; do build "$MEM" $s; build "$MEMNS" ns-$s 2> /dev/null; done
printf '[memory: 1 current]\n- editor indent: never use tabs, use 4 spaces (preference, 2026-10-05)\n- superseded: editor indent: use tabs (2026-09-01) -> now: never use tabs, use 4 spaces (2026-10-05)\n' > "$W/e.stale"
printf '[memory: 0 current]\n- superseded: deploy host: alpha (2026-09-01) -> now: gamma (2026-10-20)\n' > "$W/e.chain"
: > "$W/e.retract"
printf '[memory: 0 current]\n- superseded: mirror url: old mirror (2026-09-01) -> retracted\n' > "$W/e.retchain"
printf '[memory: 1 current]\n- login shell: zsh (preference, 2026-10-05)\n- superseded: login shell: bash (2026-10-05) -> now: zsh (2026-10-05)\n' > "$W/e.tie"
printf '[memory: 2 current]\n- deploy: manual approval (preference, 2026-09-01)\n- deploy: runs via ci (project_fact, 2026-10-05)\n' > "$W/e.kinds"
printf '[memory: 0 current]\n- superseded: editor: use emacs (2026-09-01) -> now: use vim (2026-10-05)\n' > "$W/e.old"
qcase stale "$MEM" "$W/stale" 3 "indent tabs" "$W/e.stale" && ok "stale preference: the newer 'never use tabs' is current, 'use tabs' only as superseded" || no "stale preference"
qcase chain "$MEM" "$W/chain" 3 "deploy host alpha" "$W/e.chain" && ok "chained supersession alpha -> beta -> gamma: the query matching only alpha reports alpha superseded with the chain end gamma" || no "chained supersession"
qcase retract "$MEM" "$W/retract" 3 "gpu lease mode" "$W/e.retract" && ok "retract: a retracted record is never returned (empty block)" || no "retract"
qcase retchain "$MEM" "$W/retchain" 3 "old mirror url" "$W/e.retchain" && ok "chain ending in a retraction reported as retracted, nothing current" || no "retract chain"
qcase tie "$MEM" "$W/tie" 3 "login shell" "$W/e.tie" && ok "same-ts tie: the larger rid wins" || no "same-ts tie"
qcase kinds "$MEM" "$W/kinds" 3 "deploy" "$W/e.kinds" && ok "key collision across kinds: preference and project_fact both current" || no "kinds"
qcase old "$MEM" "$W/old" 3 "emacs" "$W/e.old" && ok "query matching only the old text: reported superseded with its replacement, never current" || no "old text"
for s in stale chain retract retchain tie old; do
  k="indent tabs"; [ $s = chain ] && k="deploy host alpha"; [ $s = retract ] && k="gpu lease mode"; [ $s = retchain ] && k="old mirror url"
  [ $s = tie ] && k="login shell"; [ $s = old ] && k="emacs"
  qcase ns-$s "$MEMNS" "$W/ns-$s" 3 "$k" "$W/e.$s" && no "negative control NOT caught: $s passes with supersession disabled" || ok "negative control caught: $s fails with supersession disabled ($("$MEMNS" query "$W/ns-$s" 3 "$k" | head -n 2 | tail -n 1))"
done
# unicode: bytes kept, ASCII tokens match, a cut value ends on a UTF-8 boundary
S=$W/uni; "$MEM" add "$S" fact "café menu" "crème brûlée 日本語" $T1 syn:u:1 > /dev/null
"$MEM" query "$S" 3 "café menu" > "$W/out"; r=$?; show unicode $r "$W/out"
printf '[memory: 1 current]\n- café menu: crème brûlée 日本語 (fact, 2026-09-01)\n' | cmp -s - "$W/out" && ok "unicode bytes kept, ASCII tokens matched" || no "unicode"
v="x$(i=0; while [ $i -lt 150 ]; do printf 'é'; i=$((i + 1)); done)"
S=$W/uni2; "$MEM" add "$S" fact "long accent" "$v" $T1 syn:u:2 > /dev/null
"$MEM" query "$S" 3 "long accent" > "$W/out"; r=$?
iconv -f UTF-8 -t UTF-8 "$W/out" > /dev/null 2>&1 && ok "a 301-byte value cut to <= 200 bytes on a UTF-8 boundary (rc $r, $(wc -c < "$W/out" | tr -d ' ') bytes)" || no "cut split a UTF-8 sequence"
# empty store and missing store
"$MEM" query "$W/none.tsv" 3 "anything" > "$W/out"; r=$?; show missing-store $r "$W/out"
[ $r -eq 0 ] && [ ! -s "$W/out" ] && ok "missing store: empty block, rc 0" || no "missing store"
: > "$W/empty.tsv"; "$MEM" query "$W/empty.tsv" 3 "anything" > "$W/out"; r=$?
[ $r -eq 0 ] && [ ! -s "$W/out" ] && ok "empty store: empty block, rc 0" || no "empty store"
"$MEM" check "$W/empty.tsv" | head -n 1 > "$W/out"; [ "$(cat "$W/out")" = "MEM 0 0 0 0 0" ] && ok "check of an empty store: MEM 0 0 0 0 0" || no "check empty"
# 600-byte cap
S=$W/cap; i=1; while [ $i -le 8 ]; do "$MEM" add "$S" fact "budget item $i" "$(printf 'budget %0150d' $i)" $T1 syn:b:$i > /dev/null; i=$((i + 1)); done
"$MEM" query "$S" 8 "budget item" > "$W/out"; r=$?; n=$(wc -c < "$W/out" | tr -d ' ')
[ $r -eq 0 ] && [ "$n" -le 600 ] && [ "$n" -gt 0 ] && ok "block cap: 8 matching 170-byte records -> $n bytes <= 600, whole lines only" || no "cap $n"
tail -c 1 "$W/out" | od -An -c | grep -q '\\n' && ok "block ends with a whole line" || no "block cut mid-line"
# history, dump, check
"$MEM" history "$W/kinds" "DEPLOY" > "$W/out"; show history $? "$W/out"
[ "$(cut -f1,2,4 "$W/out" | tr '\t\n' ' |')" = "1 active preference|2 active project_fact|" ] && ok "history by normalized key across kinds" || no "history"
"$MEM" history "$W/chain" "deploy host" | cut -f1-3 | tr '\t\n' ' |' > "$W/out"
[ "$(cat "$W/out")" = "1 superseded 2|2 superseded 3|3 active 0|" ] && ok "history of the chain: 1 by 2, 2 by 3, 3 active" || no "chain history: $(cat "$W/out")"
"$MEM" dump "$W/retchain" | cut -f1-3 | tr '\t\n' ' |' > "$W/out"
[ "$(cat "$W/out")" = "1 superseded 2|2 retracted 0|3 event 0|" ] && ok "dump: superseded, retracted, event" || no "dump: $(cat "$W/out")"
"$MEM" dump "$W/chain" > "$W/d1"; "$MEM" dump "$W/chain" > "$W/d2"; cmp -s "$W/d1" "$W/d2" && ok "deterministic rebuild: two dumps identical" || no "dump differs"
cp "$W/chain" "$W/chain2"; cmp -s "$W/chain" "$W/chain2"; "$MEM" dump "$W/chain2" | cmp -s - "$W/d1" && ok "rebuild from a copy of the log is identical" || no "copy rebuild"
"$MEM" check "$W/retchain" | head -n 1 > "$W/out"; [ "$(cat "$W/out")" = "MEM 3 0 1 1 1" ] && ok "check counts: records active superseded retracted events" || no "check: $(cat "$W/out")"
# refusals leave the store unchanged
S=$W/stale; h0=$(sha256sum "$S" | cut -d' ' -f1)
"$MEM" add "$S" opinion "k" "v" $T1 p > /dev/null 2>&1; r1=$?
"$MEM" add "$S" fact "k" "v" 2026-10-05 p > /dev/null 2>&1; r2=$?
"$MEM" correct "$S" 9 fact "k" "v" $T1 p > /dev/null 2>&1; r3=$?
"$MEM" add "$S" fact "k" "$(printf 'a\tb')" $T1 p > /dev/null 2>&1; r4=$?
"$MEM" add "$S" fact "k" "v" $T1 > /dev/null 2>&1; r5=$?
"$MEM" retract "$W/retract" 1 $T3 p > /dev/null 2>&1; r6=$?
[ "$r1 $r2 $r3 $r4 $r5 $r6" = "22 22 22 22 2 22" ] && ok "refused: bad kind, bad ts, unknown rid, TAB in value, argument count, retract of a retracted record (rc $r1 $r2 $r3 $r4 $r5 $r6)" || no "refusals rc $r1 $r2 $r3 $r4 $r5 $r6"
[ "$(sha256sum "$S" | cut -d' ' -f1)" = "$h0" ] && ok "refused edits left the store byte-identical" || no "store changed by a refused edit"
printf 'add\t2\t%s\tfact\tk\tv\tp\t-\n' $T1 > "$W/bad.tsv"; "$MEM" query "$W/bad.tsv" 3 k > /dev/null 2>&1; r=$?
[ $r -eq 22 ] && ok "a log whose rid is not its record number is refused (22)" || no "rid order rc $r"
rm -rf "$W"
[ $bad = 0 ] && echo MEM_PASS || { echo MEM_FAIL; exit 1; }
