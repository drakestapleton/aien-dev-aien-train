#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# DRA-14 independent replay of the bounded native autodiff-to-training path:
# checkpoint refusals with valid checksums, one-check-removed load mutants,
# independent semantic mutants of the native tape and of the trainer, and the
# negative controls of the suite's golden gates (mutants-golden.txt).
#   OMC=<pinned omc 62775d2a...> OMEGA=<omega-mv checkout> OUT=<new empty dir> \
#     sh tests/adtrain/replay/run-replay.sh
# Host glue only (concatenation, copies, comparisons); the mutant injection
# (subst.om), the image forging (ckforge.om) and everything measured is .om.
# Prints one line per case to stdout and $OUT/replay.txt. Last line:
#   REPLAY_PASS ...  (exit 0)  every refusal and load-bearing case as declared
#   REPLAY_FAIL ...  (exit 1)  otherwise, or any invalid mutant setup
# Mutants that no existing gate kills are reported as GAP lines; they are
# findings about the suites, not failures of this replay.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
HERE=$ROOT/tests/adtrain/replay
: "${OMC:?set OMC to the pinned seed/out/omc}"
: "${OMEGA:?set OMEGA to an omega-mv checkout}"
: "${OUT:?set OUT to a new empty directory}"
mkdir -p "$OUT"
[ -z "$(ls -A "$OUT")" ] || { echo "REPLAY_FAIL OUT not empty"; exit 1; }
OUT=$(cd "$OUT" && pwd)
DEPS=$ROOT/docs/adtrain/dependencies.json
EV=$ROOT/evidence/ADTRAIN
mkdir -p "$OUT/deps" "$OUT/b" "$OUT/w" "$OUT/m"
REP=$OUT/replay.txt
: > "$REP"
NFAIL=0; NGAP=0; NINV=0
say() { echo "$*" | tee -a "$REP"; }
bad() { NFAIL=$((NFAIL + 1)); say "$* FAIL"; }

# 0. Pinned compiler and dependencies, as tests/adtrain/run-adtrain.sh does.
want=$(jq -r .compiler.binary_sha256 "$DEPS")
have=$(sha256sum "$OMC" | cut -d' ' -f1)
[ "$have" = "$want" ] || { say "REPLAY_FAIL compiler-sha256 $have"; exit 1; }
say "omc $have"
n=$(jq '.dependencies | length' "$DEPS")
i=0
while [ "$i" -lt "$n" ]; do
    commit=$(jq -r ".dependencies[$i].commit" "$DEPS")
    path=$(jq -r ".dependencies[$i].path" "$DEPS")
    sha=$(jq -r ".dependencies[$i].sha256" "$DEPS")
    git -C "$OMEGA" show "$commit:$path" > "$OUT/deps/$i.om" 2> /dev/null || { say "REPLAY_FAIL dependency-missing $commit:$path"; exit 1; }
    echo "$sha  $OUT/deps/$i.om" | sha256sum -c --status || { say "REPLAY_FAIL dependency-sha256 $path"; exit 1; }
    say "dep $commit $path $sha"
    i=$((i + 1))
done
META=$OUT/deps/0.om
TAPE=$OUT/deps/1.om
TCOMMIT=$(jq -r '.dependencies[1].commit' "$DEPS")
git -C "$OMEGA" show "$TCOMMIT:tests/autodiff664/tape-test.om" > "$OUT/deps/tape-test.om" || { say "REPLAY_FAIL tape-test missing"; exit 1; }
say "dep $TCOMMIT tests/autodiff664/tape-test.om $(sha256sum "$OUT/deps/tape-test.om" | cut -d' ' -f1)"
MLP=$ROOT/native/adtrain/mlp.om
MAIN=$ROOT/tests/adtrain/main.om

build() { # $1 unit.om $2 out.elf ; rc of the compiler, no stale output kept
    "$OMC" < "$1" > "$2" 2> "$2.stderr"
    r=$?
    if [ "$r" != 0 ] || [ "$(od -An -tx1 -N4 "$2" | tr -d ' ')" != 7f454c46 ]; then
        : > "$2"; return 1
    fi
    chmod 700 "$2"
}
runm() { # $1 elf $2 mode $3 tag ; prints rc; runs in $OUT/w
    (cd "$OUT/w" && printf '%s' "$2" | "$1" > "$OUT/b/$3.stdout" 2> "$OUT/b/$3.stderr")
    echo $?
}
mut() { # $1 source $2 pattern $3 replacement $4 out ; exact-once substitution
    { printf '%b' "$2"; printf '\0'; printf '%b' "$3"; printf '\0'; cat "$1"; } | "$OUT/subst.elf" > "$4"
}
tailof() { awk '($1=="L"&&$2>=120)||$1=="P"' "$1"; }
rtail() { awk '$1=="L"||$1=="P"' "$1"; }

build "$HERE/subst.om" "$OUT/subst.elf" || { say "REPLAY_FAIL subst compile"; exit 1; }
build "$HERE/ckforge.om" "$OUT/ckforge.elf" || { say "REPLAY_FAIL ckforge compile"; exit 1; }
cat "$META" "$TAPE" "$MLP" "$MAIN" > "$OUT/ref.om"
build "$OUT/ref.om" "$OUT/ref.elf" || { say "REPLAY_FAIL reference compile"; exit 1; }
E=$OUT/ref.elf
CK=$OUT/w/adtrain.ck

# 1. Reference runs and the golden receipts of PR #42.
[ "$(runm "$E" T ref-T)" = 0 ] || { say "REPLAY_FAIL reference T"; exit 1; }
[ "$(runm "$E" S ref-S)" = 0 ] || { say "REPLAY_FAIL reference S"; exit 1; }
cp "$CK" "$OUT/good.ck"
[ "$(runm "$E" G ref-G)" = 0 ] || { say "REPLAY_FAIL reference G"; exit 1; }
tailof "$OUT/b/ref-T.stdout" > "$OUT/ref-T.tail"
for pair in "b/ref-T.stdout:run/T.stdout" "good.ck:frozen/adtrain.ck.good" "b/ref-G.stdout:run/G.stdout"; do
    a=${pair%%:*}; g=${pair#*:}
    if [ -f "$EV/$g" ] && cmp -s "$OUT/$a" "$EV/$g"; then say "GOLDEN $a == evidence/ADTRAIN/$g PASS"
    else bad "GOLDEN $a vs evidence/ADTRAIN/$g"; fi
done
# The suite's golden.json must name exactly these receipts and their sha256.
GJ=$ROOT/docs/adtrain/golden.json
for gate in golden-T-stdout golden-ck120 golden-G-stdout; do
    ev=$(jq -r --arg g "$gate" '[.receipts[] | select(.gate == $g)] | if length == 1 then .[0].evidence else "" end' "$GJ")
    gs=$(jq -r --arg g "$gate" '[.receipts[] | select(.gate == $g)] | if length == 1 then .[0].sha256 else "" end' "$GJ")
    if [ -n "$ev" ] && [ -f "$ROOT/$ev" ] && [ "$(sha256sum "$ROOT/$ev" | cut -d' ' -f1)" = "$gs" ]; then
        say "GOLDEN-PIN $gate == sha256($ev) $gs PASS"
    else bad "GOLDEN-PIN $gate ($ev $gs)"; fi
done
[ "$(jq '.receipts | length' "$GJ")" = 3 ] && say "GOLDEN-PIN golden.json has 3 receipts PASS" || bad "GOLDEN-PIN receipt count"

# 2. Checkpoint refusals: every structural check reached with a valid checksum.
forge() { # $1 mode $2 out
    { printf '%s' "$1"; cat "$OUT/good.ck"; } | "$OUT/ckforge.elf" > "$2"
}
image() { # $1 case -> $CK ; returns 1 when the forger fails
    case "$1" in
        size537) { cat "$OUT/good.ck"; printf '\0'; } > "$CK" ;;
        size0) : > "$CK" ;;
        missing) mv "$CK" "$OUT/w/gone.ck" 2> /dev/null; [ ! -e "$CK" ] ;;
        size535) head -c 535 "$OUT/good.ck" > "$CK" ;;
        *) forge "$1" "$CK" ;;
    esac
}
forge 0 "$OUT/f0.ck" && cmp -s "$OUT/f0.ck" "$OUT/good.ck" \
    && say "CKFORGE mode 0 reproduces the image byte for byte (FNV-1a 64 agrees) PASS" \
    || bad "CKFORGE mode 0 identity"
for spec in 0:0 S:0 m:65 v:65 s:65 c:65 l:65 p:65 u:65 n:65 i:65 x:65 h:66 \
            size537:65 size0:65 size535:65 missing:65; do
    c=${spec%%:*}; e=${spec#*:}
    if ! image "$c"; then NINV=$((NINV + 1)); say "CK $c INVALID (forger)"; continue; fi
    cp "$CK" "$OUT/b/ck-$c.img" 2> /dev/null
    r=$(runm "$E" R "ck-$c")
    if [ "$r" = "$e" ]; then say "CK $c expect=$e rc=$r PASS"; else bad "CK $c expect=$e rc=$r"; fi
    if [ "$c" = 0 ] && [ "$r" = 0 ]; then
        rtail "$OUT/b/ck-0.stdout" > "$OUT/ck0.tail"
        cmp -s "$OUT/ck0.tail" "$OUT/ref-T.tail" && say "CK 0 resumed tail == uninterrupted T PASS" || bad "CK 0 resumed tail"
    fi
done

# 3. One checkpoint check removed at a time: the matching image must stop
#    giving the refusal code, the good image must still load.
grep -v '^#' "$HERE/mutants-ck.txt" | while IFS='	' read -r id pat rep img code; do
    [ -n "$id" ] || continue
    src=$OUT/m/$id.mlp.om
    mut "$MLP" "$pat" "$rep" "$src"; r=$?
    if [ "$r" != 0 ]; then echo "CKMUT $id INVALID subst=$r" | tee -a "$REP"; echo x >> "$OUT/invalid"; continue; fi
    cat "$META" "$TAPE" "$src" "$MAIN" > "$OUT/m/$id.unit.om"
    if ! build "$OUT/m/$id.unit.om" "$OUT/m/$id.elf"; then echo "CKMUT $id INVALID compile" | tee -a "$REP"; echo x >> "$OUT/invalid"; continue; fi
    cp "$OUT/good.ck" "$CK"
    g=$(runm "$OUT/m/$id.elf" R "ckmut-$id-good")
    image "$img" || { echo "CKMUT $id INVALID image" | tee -a "$REP"; echo x >> "$OUT/invalid"; continue; }
    f=$(runm "$OUT/m/$id.elf" R "ckmut-$id-$img")
    if [ "$g" = 0 ] && [ "$f" != "$code" ]; then
        echo "CKMUT $id image=$img good_rc=$g forged_rc=$f (was $code) LOADBEARING PASS" | tee -a "$REP"
    else
        echo "CKMUT $id image=$img good_rc=$g forged_rc=$f (was $code) NOT_LOADBEARING FAIL" | tee -a "$REP"; echo x >> "$OUT/fail"
    fi
done

# 4. Independent tape mutants: omega-mv tape-test.om, and the adtrain T stdout.
grep -v '^#' "$HERE/mutants-tape.txt" | while IFS='	' read -r id pat rep; do
    [ -n "$id" ] || continue
    src=$OUT/m/$id.tape.om
    mut "$TAPE" "$pat" "$rep" "$src"; r=$?
    if [ "$r" != 0 ]; then echo "TAPEMUT $id INVALID subst=$r" | tee -a "$REP"; echo x >> "$OUT/invalid"; continue; fi
    cat "$META" "$src" "$OUT/deps/tape-test.om" > "$OUT/m/$id.tt.om"
    if ! build "$OUT/m/$id.tt.om" "$OUT/m/$id.tt.elf"; then echo "TAPEMUT $id INVALID compile" | tee -a "$REP"; echo x >> "$OUT/invalid"; continue; fi
    (cd "$OUT/w" && "$OUT/m/$id.tt.elf" > "$OUT/b/tt-$id.stdout" 2> "$OUT/b/tt-$id.stderr")
    t=$?
    cat "$META" "$src" "$MLP" "$MAIN" > "$OUT/m/$id.ad.om"
    if ! build "$OUT/m/$id.ad.om" "$OUT/m/$id.ad.elf"; then echo "TAPEMUT $id INVALID adtrain-compile" | tee -a "$REP"; echo x >> "$OUT/invalid"; continue; fi
    a=$(runm "$OUT/m/$id.ad.elf" T "ad-$id")
    if [ "$a" = 0 ] && cmp -s "$OUT/b/ad-$id.stdout" "$OUT/b/ref-T.stdout"; then d=SAME; else d=DIFFER; fi
    if [ "$t" != 0 ]; then k=KILLED; else k=SURVIVED; fi
    line="TAPEMUT $id tape_test_rc=$t $k $(head -n 1 "$OUT/b/tt-$id.stdout" | cut -c1-60) adtrain_T_rc=$a $d"
    if [ "$t" = 0 ]; then line="$line GAP"; echo x >> "$OUT/gap"; fi
    echo "$line" | tee -a "$REP"
done

# 4b. Is t-e1-pad-pos0 an equivalent mutant? padprobe.om sums four -0 leaves.
cat "$META" "$TAPE" "$HERE/padprobe.om" > "$OUT/m/padprobe.om"
pm=$OUT/m/t-e1-pad-pos0.tape.om
if build "$OUT/m/padprobe.om" "$OUT/m/padprobe.elf" && [ -s "$pm" ] \
    && cat "$META" "$pm" "$HERE/padprobe.om" > "$OUT/m/padprobe-mut.om" \
    && build "$OUT/m/padprobe-mut.om" "$OUT/m/padprobe-mut.elf"; then
    "$OUT/m/padprobe.elf"; po=$?
    "$OUT/m/padprobe-mut.elf"; pq=$?
    if [ "$po" = 11 ]; then say "PADPROBE pinned tape: sum of four -0 is -0 (rc=$po) PASS"; else bad "PADPROBE pinned tape rc=$po"; fi
    case "$pq" in
        10) say "PADPROBE t-e1-pad-pos0: sum of four -0 is +0 (rc=$pq): not equivalent, a real GAP of tape-test.om" ;;
        11) say "PADPROBE t-e1-pad-pos0: sum of four -0 is -0 (rc=$pq): equivalent on this probe" ;;
        *) bad "PADPROBE t-e1-pad-pos0 rc=$pq" ;;
    esac
else
    NINV=$((NINV + 1)); say "PADPROBE INVALID build"
fi

# 5. Independent trainer mutants: the full adtrain suite on a copy of the tree
#    with the mutant mlp.om, plus the golden receipts of PR #42.
grep -v '^#' "$HERE/mutants-mlp.txt" | while IFS='	' read -r id pat rep; do
    [ -n "$id" ] || continue
    tree=$OUT/m/tree-$id
    mkdir -p "$tree/docs" "$tree/native" "$tree/tests"
    cp -R "$ROOT/docs/adtrain" "$tree/docs/" && cp -R "$ROOT/native/adtrain" "$tree/native/" \
        && cp -R "$ROOT/tests/adtrain" "$tree/tests/" || { echo "MLPMUT $id INVALID copy" | tee -a "$REP"; echo x >> "$OUT/invalid"; continue; }
    mut "$MLP" "$pat" "$rep" "$tree/native/adtrain/mlp.om"; r=$?
    if [ "$r" != 0 ]; then echo "MLPMUT $id INVALID subst=$r" | tee -a "$REP"; echo x >> "$OUT/invalid"; continue; fi
    (cd "$tree" && OMC=$OMC OMEGA=$OMEGA OUT=$OUT/m/suite-$id sh tests/adtrain/run-adtrain.sh) > "$OUT/b/suite-$id.log" 2>&1
    s=$(tail -n 1 "$OUT/b/suite-$id.log")
    # A failure of the suite's own mutant injection (its pattern no longer
    # matches the mutated mlp.om) is a setup collision, never a kill.
    case "$s" in ADTRAIN_SUITE_PASS) k=SURVIVED ;; *-inject) k=UNKNOWN ;; ADTRAIN_SUITE_FAIL*) k=KILLED ;; *) k=UNKNOWN ;; esac
    if [ "$k" = UNKNOWN ]; then echo "MLPMUT $id INVALID suite-output ($s)" | tee -a "$REP"; echo x >> "$OUT/invalid"; continue; fi
    cat "$META" "$TAPE" "$tree/native/adtrain/mlp.om" "$MAIN" > "$OUT/m/$id.om"
    if ! build "$OUT/m/$id.om" "$OUT/m/$id.elf"; then gt=COMPILE_REFUSED; gc=COMPILE_REFUSED; gg=COMPILE_REFUSED
    else
        a=$(runm "$OUT/m/$id.elf" T "mlp-$id-T")
        if [ "$a" = 0 ] && cmp -s "$OUT/b/mlp-$id-T.stdout" "$EV/run/T.stdout"; then gt=SAME; else gt="DIFFER(rc=$a)"; fi
        b=$(runm "$OUT/m/$id.elf" S "mlp-$id-S")
        if [ "$b" = 0 ] && cmp -s "$CK" "$EV/frozen/adtrain.ck.good"; then gc=SAME; else gc="DIFFER(rc=$b)"; fi
        c=$(runm "$OUT/m/$id.elf" G "mlp-$id-G")
        if [ "$c" = 0 ] && cmp -s "$OUT/b/mlp-$id-G.stdout" "$EV/run/G.stdout"; then gg=SAME; else gg="DIFFER(rc=$c)"; fi
    fi
    line="MLPMUT $id suite=$k ($s) golden_T=$gt golden_ck=$gc golden_G=$gg"
    if [ "$k" = SURVIVED ]; then line="$line GAP"; echo x >> "$OUT/gap"; fi
    echo "$line" | tee -a "$REP"
done

# 6. Negative controls of the golden gates and of dgeps: the suite on a copy of
#    the tree with one declared edit must end with the declared line.
grep -v '^#' "$HERE/mutants-golden.txt" | while IFS='	' read -r id f pat rep want pat2 rep2; do
    [ -n "$id" ] || continue
    tree=$OUT/m/gtree-$id
    mkdir -p "$tree/docs" "$tree/native" "$tree/tests"
    cp -R "$ROOT/docs/adtrain" "$tree/docs/" && cp -R "$ROOT/native/adtrain" "$tree/native/" \
        && cp -R "$ROOT/tests/adtrain" "$tree/tests/" || { echo "GOLDCTL $id INVALID copy" | tee -a "$REP"; echo x >> "$OUT/invalid"; continue; }
    mut "$ROOT/$f" "$pat" "$rep" "$tree/$f"; r=$?
    if [ "$r" = 0 ] && [ -n "$pat2" ]; then
        cp "$tree/$f" "$OUT/m/$id.first"
        mut "$OUT/m/$id.first" "$pat2" "$rep2" "$tree/$f"; r=$?
    fi
    if [ "$r" != 0 ]; then echo "GOLDCTL $id INVALID subst=$r" | tee -a "$REP"; echo x >> "$OUT/invalid"; continue; fi
    (cd "$tree" && OMC=$OMC OMEGA=$OMEGA OUT=$OUT/m/gsuite-$id sh tests/adtrain/run-adtrain.sh) > "$OUT/b/gsuite-$id.log" 2>&1
    s=$(tail -n 1 "$OUT/b/gsuite-$id.log")
    case "$s" in
        "$want"*) echo "GOLDCTL $id ($s) PASS" | tee -a "$REP" ;;
        *) echo "GOLDCTL $id want=($want) got=($s) FAIL" | tee -a "$REP"; echo x >> "$OUT/fail" ;;
    esac
done

[ -f "$OUT/fail" ] && NFAIL=$((NFAIL + $(wc -l < "$OUT/fail")))
[ -f "$OUT/invalid" ] && NINV=$((NINV + $(wc -l < "$OUT/invalid")))
[ -f "$OUT/gap" ] && NGAP=$(wc -l < "$OUT/gap")
(cd "$OUT" && sha256sum ref.om ref.elf good.ck subst.elf ckforge.elf deps/* b/*.stdout b/*.img) > "$OUT/artifacts.sha256" 2> /dev/null
if [ "$NFAIL" = 0 ] && [ "$NINV" = 0 ]; then
    say "REPLAY_PASS fail=0 invalid=0 gap=$NGAP"; exit 0
fi
say "REPLAY_FAIL fail=$NFAIL invalid=$NINV gap=$NGAP"; exit 1
