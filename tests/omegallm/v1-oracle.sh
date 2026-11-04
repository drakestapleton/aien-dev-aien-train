#!/bin/sh
# Omega LLM v1 referee checks (CONTRACT-V1 §9.2-§9.5): the `ollm` binary against oracle.py.
#
#   BIN=path/to/ollm  sh tests/omegallm/v1-oracle.sh
#
# Environment:
#   BIN      aarch64 v1 ollm binary; unset = referee outputs only, binary cases NOT_RUN
#   DATA     directory holding TinyStoriesV2-GPT4-valid.txt (default: ../../data from here)
#   WORK     scratch directory (default: scratch-v1-oracle beside the clone); ref/ and bin/ are rebuilt
#   CORE     core for taskset (default 8); every process runs at nice 19
#   MUTANT   planted referee defect (oracle.py MUTANTS); the run must then report FAIL lines
#   V0BIN    optional v0 ollm binary for the V = 256 CK01 identity case (§9.4)
#   EXT_MERGES EXT_V EXT_TEXT EXT_TOK  optional: referee-encode EXT_TEXT with EXT_MERGES at EXT_V
#            and compare with the product's token file EXT_TOK byte for byte
#
# One PASS/FAIL/NOT_RUN line per case, then `SUMMARY pass=N fail=M not_run=K`; exit 0 iff fail=0.
# Tokenizer outputs and init are compared byte for byte; grad and one train step per entry within
# the v0 tolerance (ORACLE.md "Tolerance"); printed micro integers exactly.
set -u
here=$(cd "$(dirname "$0")" && pwd)
ORACLE="$here/oracle.py"
DATA=${DATA:-$here/../../data}
WORK=${WORK:-$here/../../../scratch-v1-oracle}
CORE=${CORE:-8}
MUTANT=${MUTANT:-}
BIN=${BIN:-}
V0BIN=${V0BIN:-}
VALID="$DATA/TinyStoriesV2-GPT4-valid.txt"
RUN="taskset -c $CORE nice -n 19"
# every helper (cmp, python3 -c, sha256sum) runs on the same core too
if [ -z "${V1_ORACLE_PINNED:-}" ]; then
    V1_ORACLE_PINNED=1 exec taskset -c "$CORE" nice -n 19 sh "$0" "$@"
fi
export PYTHONDONTWRITEBYTECODE=1
export OLLM_ORACLE_MUTANT="$MUTANT"

[ -r "$VALID" ] || { echo "v1-oracle: cannot read $VALID (set DATA)" >&2; exit 2; }
mkdir -p "$WORK"
WORK=$(cd "$WORK" && pwd)
REF="$WORK/ref"
GOT="$WORK/bin"
rm -rf "$REF" "$GOT" "$WORK/tmp"
mkdir -p "$REF" "$GOT" "$WORK/tmp"
export OLLM_TMP="$WORK/tmp"
if [ -n "$BIN" ]; then
    BIN=$(cd "$(dirname "$BIN")" && pwd)/$(basename "$BIN")
    [ -x "$BIN" ] || { echo "v1-oracle: BIN $BIN is not executable" >&2; exit 2; }
fi
if [ -n "$V0BIN" ]; then
    V0BIN=$(cd "$(dirname "$V0BIN")" && pwd)/$(basename "$V0BIN")
    [ -x "$V0BIN" ] || { echo "v1-oracle: V0BIN $V0BIN is not executable" >&2; exit 2; }
fi
echo "v1-oracle: bin=${BIN:-none} mutant=${MUTANT:-none} core=$CORE"

pass=0 fail=0 notrun=0
ok() { echo "PASS $1${2:+ ($2)}"; pass=$((pass + 1)); }
ko() { echo "FAIL $1${2:+ ($2)}" | sed "s|$WORK/||g"; fail=$((fail + 1)); }
nr() { echo "NOT_RUN $1${2:+ ($2)}"; notrun=$((notrun + 1)); }

# r DIR TAG CMD...: run CMD in DIR; stdout -> TAG.out, stderr -> TAG.err, exit code -> TAG.rc
r() {
    _d=$1 _t=$2
    shift 2
    (cd "$_d" && $RUN "$@" >"$_t.out" 2>"$_t.err"; echo $? >"$_t.rc")
}
ref() { _t=$1; shift; r "$REF" "$_t" python3 "$ORACLE" ollm "$@"; }
got() { _t=$1; shift; [ -n "$BIN" ] && r "$GOT" "$_t" "$BIN" "$@"; return 0; }
both() { ref "$@"; got "$@"; }
py() { $RUN python3 "$ORACLE" "$@"; }

# chk NAME TAG RC [FILE|!FILE]...: the referee must exit RC; the binary must match its exit code,
# stdout bytes and each FILE byte for byte (!FILE: must not exist on either side).
chk() {
    _n=$1 _t=$2 _rc=$3
    shift 3
    _rr=$(cat "$REF/$_t.rc")
    [ "$_rr" = "$_rc" ] || { ko "$_n" "referee exit $_rr, want $_rc: $(cat "$REF/$_t.err" | tail -n 1)"; return; }
    for _f; do
        case $_f in !*) [ ! -e "$REF/${_f#!}" ] || { ko "$_n" "referee left ${_f#!}"; return; } ;; esac
    done
    [ -n "$BIN" ] || { nr "$_n" "no BIN"; return; }
    _gr=$(cat "$GOT/$_t.rc")
    [ "$_gr" = "$_rr" ] || { ko "$_n" "exit $_gr, want $_rr"; return; }
    _d=$(cmp "$GOT/$_t.out" "$REF/$_t.out" 2>&1) || { ko "$_n" "stdout: $_d; got '$(head -c 80 "$GOT/$_t.out")' want '$(head -c 80 "$REF/$_t.out")'"; return; }
    for _f; do
        case $_f in
        !*) [ ! -e "$GOT/${_f#!}" ] || { ko "$_n" "binary left ${_f#!}"; return; } ;;
        *) _d=$(cmp "$GOT/$_f" "$REF/$_f" 2>&1) || { ko "$_n" "$_f: $_d"; return; } ;;
        esac
    done
    ok "$_n" "exit $_rr${1:+, files checked}"
}

# tol NAME KIND GOTFILE REFFILE: oracle.py cmp (header exact, payload within rtol)
tol() {
    _o=$(py cmp "$2" "$3" "$4" 2>&1)
    _l=$(printf '%s\n' "$_o" | tail -n 1)
    case $_l in PASS*) ok "$1" "max relerr $(printf '%s\n' "$_o" | grep 'max relerr' | awk '{printf "%s=%s ", $2, $5}')" ;;
    *) ko "$1" "$(printf '%s\n' "$_o" | tr '\n' ' ')" ;; esac
}

wr() { python3 -c "import sys,struct; open(sys.argv[1],'wb').write($2)" "$1"; }

# ---------------------------------------------------------------- referee self-test
o=$(py selftest-v1 2>&1)
case $(printf '%s\n' "$o" | tail -n 1) in
*PASS*) ok referee-selftest-v1 ;;
*) ko referee-selftest-v1 "$(printf '%s\n' "$o" | grep FAIL | tr '\n' ';')" ;;
esac

# ---------------------------------------------------------------- tokenizer (§2, §9.2)
both prep prep "$VALID" train.bin held.bin
chk prep prep 0 train.bin held.bin
both fit512 bpefit train.bin merges512.bin 512
chk fit512 fit512 0 merges512.bin
both fit300mb bpefit train.bin m300mb.bin 300 1000000
chk fit300-maxbytes fit300mb 0 m300mb.bin
for d in "$REF" "$GOT"; do
    wr "$d/tie.txt" "b'ab cd ef\\0ab cd ef\\0'"
    wr "$d/no0.txt" "b'abc def ghi'"
    wr "$d/edge.txt" "b'  x'+b'A'*150+b' '+'caf\\u00e9 na\\u00efve \\u65e5\\u672c'.encode()+b'!!?  9z 3.14\\t\\r\\n\\0'+b' the  end\\0'*3"
done
both fittie bpefit tie.txt tie.bin 261
chk fit-tie fittie 0 tie.bin
# known answer, independent of the binary: pairs (32,99) (32,101) (97,98) (256,100) (257,102)
want=$(python3 -c "import struct; b=struct.pack('<10H',32,99,32,101,97,98,256,100,257,102); print(b.hex())")
have=$(python3 -c "import sys; print(open(sys.argv[1],'rb').read()[24:].hex())" "$REF/tie.bin" 2>/dev/null)
[ "$want" = "$have" ] && ok fit-tie-kat "smallest a, then smallest b" || ko fit-tie-kat "referee merges $have, want $want"
both fittie28 bpefit tie.txt tie28.bin 262
chk fit-out-of-pairs fittie28 28 '!tie28.bin'
both fit21 bpefit no0.txt no0.bin 300 5
chk fit-maxbytes-no-0 fit21 21 '!no0.bin'
both fitedge bpefit edge.txt edge.bin 280
chk fit-edge fitedge 0 edge.bin
both enc512 bpeenc merges512.bin 512 train.bin train512.tok
chk enc512-train enc512 0 train512.tok
both enc512h bpeenc merges512.bin 512 held.bin held512.tok
chk enc512-held enc512h 0 held512.tok
both enc300 bpeenc merges512.bin 300 train.bin train300.tok
chk enc300-train enc300 0 train300.tok
both enc300h bpeenc merges512.bin 300 held.bin held300.tok
chk enc300-held enc300h 0 held300.tok
both encedge bpeenc edge.bin 280 edge.txt edge.tok
chk enc-edge encedge 0 edge.tok
both dec512 bpedec merges512.bin train512.tok train.dec
chk dec512-train dec512 0 train.dec
for d in "$REF" "$GOT"; do [ -e "$d/train.dec" ] && ! cmp -s "$d/train.dec" "$d/train.bin" && echo "  decode != text in $d"; done
if cmp -s "$REF/train.dec" "$REF/train.bin" && { [ -z "$BIN" ] || cmp -s "$GOT/train.dec" "$GOT/train.bin"; }; then
    ok roundtrip "decode(encode(train)) == train"
else ko roundtrip "decode(encode(train)) != train"; fi
# negative control (§9.2): one pair altered (merge 100 -> (101, 32)), file rehashed; tokens change
for d in "$REF" "$GOT"; do
    python3 -c "
import sys, struct
sys.path.insert(0, sys.argv[3]); import oracle
raw = bytearray(open(sys.argv[1], 'rb').read())
struct.pack_into('<2H', raw, 24 + 4 * 100, 101, 32)
struct.pack_into('<Q', raw, 16, oracle.fnv1a64(bytes(raw[24:])))
open(sys.argv[2], 'wb').write(raw)" "$REF/merges512.bin" "$d/alt512.bin" "$here"
done
both encalt bpeenc alt512.bin 512 held.bin heldalt.tok
chk enc-altered-pair encalt 0 heldalt.tok
if cmp -s "$REF/heldalt.tok" "$REF/held512.tok"; then ko altered-pair-changes-tokens "referee tokens unchanged"
elif [ -n "$BIN" ] && cmp -s "$GOT/heldalt.tok" "$GOT/held512.tok"; then ko altered-pair-changes-tokens "binary tokens unchanged"
else ok altered-pair-changes-tokens "$(cmp "$REF/heldalt.tok" "$REF/held512.tok" | sed 's/.*differ: //')"; fi
# refusals
for d in "$REF" "$GOT"; do
    python3 -c "import sys; b=bytearray(open(sys.argv[1],'rb').read()); b[30]^=1; open(sys.argv[2],'wb').write(b)" "$REF/merges512.bin" "$d/badhash.bin"
    head -c 101 "$REF/held512.tok" >"$d/odd.tok"
    wr "$d/big.tok" "struct.pack('<4H', 72, 105, 600, 33)"
done
both r26 bpeenc badhash.bin 512 held.bin r26.tok
chk merges-hash-26 r26 26 '!r26.tok'
both r27 bpeenc merges512.bin 513 held.bin r27.tok
chk v-over-merges-27 r27 27 '!r27.tok'
both r27b bpeenc merges512.bin 256 held.bin r27b.tok
chk bpeenc-v256-27 r27b 27 '!r27b.tok'
both r21 bpedec merges512.bin odd.tok odd.dec
chk odd-token-file-21 r21 21
both r25 bpedec merges512.bin big.tok big.dec
chk token-over-v-25 r25 25
if [ -n "${EXT_MERGES:-}" ]; then
    ref ext bpeenc "$EXT_MERGES" "$EXT_V" "$EXT_TEXT" ext.tok
    if [ "$(cat "$REF/ext.rc")" != 0 ]; then ko ext-enc "referee exit $(cat "$REF/ext.rc")"
    elif d=$(cmp "$EXT_TOK" "$REF/ext.tok" 2>&1); then ok ext-enc "$(cat "$REF/ext.out")"
    else ko ext-enc "$d"; fi
fi

# ---------------------------------------------------------------- model (§4-§7, §9.3-§9.5)
TR="$REF/train300.tok"
HE="$REF/held300.tok"
M5="$REF/merges512.bin"
CFG="300 8 16 2 32 2 4 5 50 3000"
both init2 init init2.ck $CFG 2
chk init-ck02-g2 init2 0 init2.ck
both init1 init init1.ck $CFG
chk init-ck01 init1 0 init1.ck
both init4 init init4.ck $CFG 4
chk init-ck02-g4 init4 0 init4.ck
both initg3 init g3.ck $CFG 3
chk init-g3-12 initg3 12 '!g3.ck'
for s in "4097 8 16 2 32 2 4" "300 257 16 2 32 2 4" "300 8 258 2 32 2 4" "300 8 34 17 32 2 4" \
    "300 8 16 2 1025 2 4" "300 8 16 2 32 9 4" "300 8 16 2 32 2 65"; do
    both lim init lim.ck $s 5 50 3000
    chk "limit-12 [$s]" lim 12 '!lim.ck'
done
for d in "$REF" "$GOT"; do wr "$d/offs" "struct.pack('<4Q', 0, 777777, 5000000, 13000000)"; done
for g in 2 4; do
    both grad$g grad init$g.ck "$TR" offs g$g.gr
    if [ "$(cat "$REF/grad$g.rc")" != 0 ]; then ko "grad-g$g" "referee exit $(cat "$REF/grad$g.rc")"
    elif [ -z "$BIN" ]; then nr "grad-g$g" "no BIN"
    elif [ "$(cat "$GOT/grad$g.rc")" != 0 ]; then ko "grad-g$g" "exit $(cat "$GOT/grad$g.rc")"
    else
        o=$(py cmp gline "$GOT/grad$g.out" "$REF/grad$g.out")
        case $o in PASS*) tol "grad-g$g" gr "$GOT/g$g.gr" "$REF/g$g.gr" ;; *) ko "grad-g$g" "$o" ;; esac
    fi
done
# referee-only run (deliverable): 20 steps EVERY 5 from the referee's init, eval and samples
cp "$REF/init2.ck" "$REF/ref20.ck"
ref tr20 train ref20.ck "$TR" 20 5
ref ev20 eval ref20.ck "$HE" 4 "$M5"
ref s0 sample ref20.ck 7 40 0 "Once upon a time" "$M5"
ref s800 sample ref20.ck 7 40 800 "Once upon a time" "$M5"
for t in tr20 ev20 s0 s800; do
    [ "$(cat "$REF/$t.rc")" = 0 ] || ko "referee-$t" "exit $(cat "$REF/$t.rc")"
done
# §9.3: one train step per call from the binary's own checkpoints
if [ -z "$BIN" ]; then nr train-chain-20 "no BIN"
else
    cp "$GOT/init2.ck" "$GOT/c0.ck"
    bad=
    s=1
    while [ $s -le 20 ]; do
        cp "$GOT/c$((s - 1)).ck" "$GOT/c$s.ck"
        cp "$GOT/c$((s - 1)).ck" "$REF/c$s.ck"
        both ts$s train c$s.ck "$TR" $s 1
        if [ "$(cat "$GOT/ts$s.rc")" != 0 ] || ! cmp -s "$GOT/ts$s.out" "$REF/ts$s.out"; then
            bad="step $s: got '$(cat "$GOT/ts$s.out")' rc $(cat "$GOT/ts$s.rc"), want '$(cat "$REF/ts$s.out")'"
            break
        fi
        o=$(py cmp ck "$GOT/c$s.ck" "$REF/c$s.ck")
        case $(printf '%s\n' "$o" | tail -n 1) in PASS*) ;; *) bad="step $s: $(printf '%s\n' "$o" | tr '\n' ' ')"; break ;; esac
        s=$((s + 1))
    done
    [ -z "$bad" ] && ok train-chain-20 "T lines exact, ck within rtol at every step" || ko train-chain-20 "$bad"
fi
# §9.4 workers: one process, 20 steps, K = 1 and K = 2
if [ -z "$BIN" ]; then nr workers-k1-k2 "no BIN"; nr workers-tlines "no BIN"
else
    cp "$GOT/init2.ck" "$GOT/k1.ck"
    cp "$GOT/init2.ck" "$GOT/k2.ck"
    got trk1 train k1.ck "$TR" 20 5 1
    got trk2 train k2.ck "$TR" 20 5 2
    if [ "$(cat "$GOT/trk1.rc")$(cat "$GOT/trk2.rc")" != 00 ]; then ko workers-k1-k2 "exit $(cat "$GOT/trk1.rc") $(cat "$GOT/trk2.rc")"
    elif d=$(cmp "$GOT/k2.ck" "$GOT/k1.ck" 2>&1) && d=$(cmp "$GOT/k1.ck" "$GOT/c20.ck" 2>&1); then
        ok workers-k1-k2 "K=1, K=2 and the 20-call chain byte-identical"
    else ko workers-k1-k2 "$d"; fi
    if cmp -s "$GOT/trk1.out" "$REF/tr20.out" && cmp -s "$GOT/trk2.out" "$REF/tr20.out"; then
        ok workers-tlines "T lines = referee"
    else ko workers-tlines "got '$(cat "$GOT/trk1.out" | tr '\n' ';')' want '$(cat "$REF/tr20.out" | tr '\n' ';')'"; fi
fi
both k3 train init2.ck "$TR" 1 1 3
chk bad-k3-29 k3 29
both k0 train init2.ck "$TR" 1 1 0
chk bad-k0-29 k0 29
# eval and sample on the binary's 20-step checkpoint (the referee's when no BIN)
if [ -n "$BIN" ]; then cp "$GOT/c20.ck" "$GOT/b20.ck"; cp "$GOT/c20.ck" "$REF/b20.ck"
else cp "$REF/ref20.ck" "$REF/b20.ck"; fi
both evb eval b20.ck "$HE" 4 "$M5"
chk eval-w4-bpb evb 0
both evnom eval b20.ck "$HE" 4
chk eval-no-merges-2 evnom 2
both evw eval b20.ck "$HE" 999999 "$M5"
chk eval-w-23 evw 23
both sb0 sample b20.ck 7 40 0 "Once upon a time" "$M5"
chk sample-t0 sb0 0
both sb800 sample b20.ck 7 40 800 "Once upon a time" "$M5"
chk sample-t800 sb800 0
both snom sample b20.ck 7 40 0 "Once" 
chk sample-no-merges-2 snom 2
# data refusals (tokens checked lazily: only rows actually read)
for d in "$REF" "$GOT"; do
    head -c 4001 "$TR" >"$d/odd300.tok"
    head -c 16 "$TR" >"$d/short.tok"
    wr "$d/bad.tok" "struct.pack('<200H', *[400 if i == 100 else 5 + i % 200 for i in range(200)])"
    wr "$d/offs-bad" "struct.pack('<4Q', 0, 10, 20, 95)"
    wr "$d/offs-good" "struct.pack('<4Q', 0, 10, 20, 30)"
    wr "$d/offs-22" "struct.pack('<4Q', 0, 10, 20, 192)"
    wr "$d/offs-21" "struct.pack('<3Q', 0, 10, 20)"
done
both d21 train init2.ck odd300.tok 1 1
chk data-odd-21 d21 21
both d20 train init2.ck short.tok 1 1
chk data-short-20 d20 20
both d25 grad init2.ck bad.tok offs-bad d25.gr
chk data-token-25 d25 25 '!d25.gr'
both dlazy grad init2.ck bad.tok offs-good dlazy.gr
if [ "$(cat "$REF/dlazy.rc")" != 0 ]; then ko data-lazy "referee exit $(cat "$REF/dlazy.rc")"
elif [ -z "$BIN" ]; then nr data-lazy "no BIN"
elif [ "$(cat "$GOT/dlazy.rc")" != 0 ]; then ko data-lazy "exit $(cat "$GOT/dlazy.rc")"
else tol data-lazy gr "$GOT/dlazy.gr" "$REF/dlazy.gr"; fi
both o22 grad init2.ck bad.tok offs-22 o22.gr
chk offs-22 o22 22
both o21 grad init2.ck bad.tok offs-21 o21.gr
chk offs-size-21 o21 21
# §9.4 V = 256: a CK01 trained by the v1 binary equals the v0 binary's after 20 steps
if [ -z "$BIN" ] || [ -z "$V0BIN" ]; then nr v0-v1-ck01 "needs BIN and V0BIN"
else
    r "$GOT" v0i "$V0BIN" init v0.ck 256 8 16 2 32 2 2 5 50 3000
    got v1i init v1.ck 256 8 16 2 32 2 2 5 50 3000
    if ! d=$(cmp "$GOT/v1.ck" "$GOT/v0.ck" 2>&1); then ko v0-v1-ck01 "init: $d"
    else
        r "$GOT" v0t "$V0BIN" train v0.ck "$REF/held.bin" 20 5
        got v1t train v1.ck "$REF/held.bin" 20 5
        if d=$(cmp "$GOT/v1.ck" "$GOT/v0.ck" 2>&1) && cmp -s "$GOT/v1t.out" "$GOT/v0t.out"; then
            ok v0-v1-ck01 "init and 20 steps byte-identical, T lines equal"
        else ko v0-v1-ck01 "${d:-T lines differ}"; fi
    fi
fi

# referee outputs and their hashes
(cd "$REF" && sha256sum prep.out train.bin held.bin fit512.out merges512.bin train512.tok held512.tok \
    train300.tok held300.tok m300mb.bin tie.bin edge.bin edge.tok init2.ck init1.ck init4.ck \
    offs grad2.out g2.gr grad4.out g4.gr tr20.out ref20.ck ev20.out s0.out s800.out >SHA256SUMS 2>/dev/null)
echo "SUMMARY pass=$pass fail=$fail not_run=$notrun"
[ "$fail" = 0 ]
