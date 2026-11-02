#!/bin/sh
# Omega LLM v1 tokenizer check (CONTRACT-V1 §2, §7): bpefit, bpeenc and bpedec of the ollm binary
# against the referee tests/omegallm/oracle.py on small generated texts, every tokenizer exit code,
# and two negative controls. Needs no data directory; runs in seconds.
#
#   BIN=path/to/ollm  sh tests/omegallm/bpe-check.sh
#
# Environment: BIN (required; an x86linux binary runs through binfmt), WORK (scratch, default
# ../../scratch-bpe-check from here), CORE (taskset core, default 6; everything runs at nice 19).
# One PASS/FAIL line per case, then `SUMMARY pass=N fail=M`; exit 0 iff fail=0.
# Negative controls: a merges file with one pair altered (rehashed) must change the tokens, and a
# merges file with one flipped payload byte must be refused with 26. A third control runs the
# comparison itself on a deliberately different token file and must see the difference.
set -u
here=$(cd "$(dirname "$0")" && pwd)
ORACLE="$here/oracle.py"
WORK=${WORK:-$here/../../scratch-bpe-check}
CORE=${CORE:-6}
BIN=${BIN:?set BIN to the ollm binary}
if [ -z "${BPE_CHECK_PINNED:-}" ]; then
    BPE_CHECK_PINNED=1 exec taskset -c "$CORE" nice -n 19 sh "$0" "$@"
fi
export PYTHONDONTWRITEBYTECODE=1
BIN=$(cd "$(dirname "$BIN")" && pwd)/$(basename "$BIN")
[ -x "$BIN" ] || { echo "bpe-check: BIN $BIN is not executable" >&2; exit 2; }
mkdir -p "$WORK"
WORK=$(cd "$WORK" && pwd)
REF="$WORK/ref" GOT="$WORK/bin"
rm -rf "$REF" "$GOT" "$WORK/tmp"
mkdir -p "$REF" "$GOT" "$WORK/tmp"
export OLLM_TMP="$WORK/tmp"
echo "bpe-check: bin=$(basename "$BIN") sha256=$(sha256sum "$BIN" | cut -c1-16)"

pass=0 fail=0
ok() { echo "PASS $1${2:+ ($2)}"; pass=$((pass + 1)); }
ko() { echo "FAIL $1${2:+ ($2)}" | sed "s|$WORK/||g"; fail=$((fail + 1)); }
r() { _d=$1 _t=$2; shift 2; (cd "$_d" && "$@" >"$_t.out" 2>"$_t.err"; echo $? >"$_t.rc"); }
both() { _t=$1; shift; r "$REF" "$_t" python3 "$ORACLE" ollm "$@"; r "$GOT" "$_t" "$BIN" "$@"; }
gotonly() { _t=$1; shift; r "$GOT" "$_t" "$BIN" "$@"; }
# chk NAME TAG RC [FILE|!FILE]...: referee exit must be RC; binary exit, stdout and FILEs equal
chk() {
    _n=$1 _t=$2 _rc=$3; shift 3
    _rr=$(cat "$REF/$_t.rc") _gr=$(cat "$GOT/$_t.rc")
    [ "$_rr" = "$_rc" ] || { ko "$_n" "referee exit $_rr, want $_rc"; return; }
    [ "$_gr" = "$_rc" ] || { ko "$_n" "exit $_gr, want $_rc"; return; }
    _d=$(cmp "$GOT/$_t.out" "$REF/$_t.out" 2>&1) || { ko "$_n" "stdout: $_d"; return; }
    for _f; do
        case $_f in
        !*) [ ! -e "$GOT/${_f#!}" ] && [ ! -e "$GOT/${_f#!}.tmp" ] || { ko "$_n" "binary left ${_f#!}"; return; } ;;
        *) _d=$(cmp "$GOT/$_f" "$REF/$_f" 2>&1) || { ko "$_n" "$_f: $_d"; return; } ;;
        esac
    done
    ok "$_n" "exit $_rc, $(tr -d '\n' <"$GOT/$_t.out")"
}
# rc NAME TAG RC [!FILE]: binary-only exit code (usage refusals the referee does not model)
rc() {
    _n=$1 _t=$2 _rc=$3; shift 3
    _gr=$(cat "$GOT/$_t.rc")
    [ "$_gr" = "$_rc" ] || { ko "$_n" "exit $_gr, want $_rc"; return; }
    for _f; do [ ! -e "$GOT/${_f#!}" ] || { ko "$_n" "binary left ${_f#!}"; return; }; done
    ok "$_n" "exit $_rc"
}
wr() { python3 -c "import sys,struct; open(sys.argv[1],'wb').write($2)" "$1"; }

# Texts: a story mix with every chunk rule (A runs, space+A, single bytes, pieces of 64, UTF-8,
# controls, byte 0 terminators), the tie text, one without byte 0, an empty one.
for d in "$REF" "$GOT"; do
    wr "$d/mix.txt" "b''.join(b'Once upon a time, %d little cats sat on the mat. The cat said: \"hi!\"\\n  It was 3.14 o\\'clock.\\0' % i for i in range(60))+b'  x'+b'A'*150+b' '+'caf\\u00e9 na\\u00efve \\u65e5\\u672c'.encode()+b'!!?  9z\\t\\r\\n\\0'+bytes(range(256))+b'\\0'"
    wr "$d/tie.txt" "b'ab cd ef\\0ab cd ef\\0'"
    wr "$d/no0.txt" "b'abc def ghi'"
    wr "$d/empty.txt" "b''"
done

both fit256 bpefit mix.txt m256.bin 256; rc fit-v256-2 fit256 2 '!m256.bin'
both fit4097 bpefit mix.txt m4097.bin 4097; rc fit-v4097-2 fit4097 2 '!m4097.bin'
both fit bpefit mix.txt mix.bin 400
chk fit-mix fit 0 mix.bin
[ ! -e "$GOT/mix.bin.tmp" ] && ok fit-no-tmp-left || ko fit-no-tmp-left
both fitmax bpefit mix.txt mixmax.bin 300 2000
chk fit-maxbytes-cut fitmax 0 mixmax.bin
both fittie bpefit tie.txt tie.bin 261
chk fit-tie fittie 0 tie.bin
want=$(python3 -c "import struct; print(struct.pack('<10H',32,99,32,101,97,98,256,100,257,102).hex())")
have=$(python3 -c "import sys; print(open(sys.argv[1],'rb').read()[24:].hex())" "$GOT/tie.bin")
[ "$want" = "$have" ] && ok fit-tie-kat "binary merges = known answer" || ko fit-tie-kat "$have"
both fit28 bpefit tie.txt tie28.bin 262
chk fit-out-of-pairs-28 fit28 28 '!tie28.bin'
both fit21 bpefit no0.txt no0.bin 300 5
chk fit-maxbytes-no-0-21 fit21 21 '!no0.bin'
both fitempty bpefit empty.txt e.bin 300
chk fit-empty-28 fitempty 28 '!e.bin'

for v in 400 300 257; do
    both enc$v bpeenc mix.bin $v mix.txt mix$v.tok
    chk enc-mix-v$v enc$v 0 mix$v.tok
done
both encempty bpeenc mix.bin 400 empty.txt empty.tok
chk enc-empty encempty 0 empty.tok
both dec bpedec mix.bin mix400.tok mix.dec
chk dec-mix dec 0 mix.dec
cmp -s "$GOT/mix.dec" "$GOT/mix.txt" && ok roundtrip-mix "decode(encode(mix)) == mix" || ko roundtrip-mix
both decempty bpedec mix.bin empty.tok empty.dec
chk dec-empty decempty 0 empty.dec

# negative control 1: merge 20 altered to (101, 32), rehashed; the tokens must change
for d in "$REF" "$GOT"; do
    python3 -c "
import sys, struct
sys.path.insert(0, sys.argv[3]); import oracle
raw = bytearray(open(sys.argv[1], 'rb').read())
struct.pack_into('<2H', raw, 24 + 4 * 20, 101, 32)
struct.pack_into('<Q', raw, 16, oracle.fnv1a64(bytes(raw[24:])))
open(sys.argv[2], 'wb').write(raw)" "$REF/mix.bin" "$d/alt.bin" "$here"
done
both encalt bpeenc alt.bin 400 mix.txt alt.tok
chk enc-altered-pair encalt 0 alt.tok
if cmp -s "$GOT/alt.tok" "$GOT/mix400.tok"; then ko neg-altered-pair-changes-tokens "tokens unchanged"
else ok neg-altered-pair-changes-tokens "$(cmp "$GOT/alt.tok" "$GOT/mix400.tok" | sed 's/.*differ: //')"; fi
# negative control 2: one flipped payload byte -> 26, nothing written (enc and dec)
for d in "$REF" "$GOT"; do
    python3 -c "import sys; b=bytearray(open(sys.argv[1],'rb').read()); b[30]^=1; open(sys.argv[2],'wb').write(b)" "$REF/mix.bin" "$d/flip.bin"
    python3 -c "import sys; b=bytearray(open(sys.argv[1],'rb').read()); b[0]^=1; open(sys.argv[2],'wb').write(b)" "$REF/mix.bin" "$d/magic.bin"
    python3 -c "import sys; b=open(sys.argv[1],'rb').read(); open(sys.argv[2],'wb').write(b[:-4])" "$REF/mix.bin" "$d/short.bin"
    head -c 101 "$REF/mix400.tok" >"$d/odd.tok"
    wr "$d/big.tok" "struct.pack('<4H', 72, 105, 400, 33)"
    wr "$d/bigodd.tok" "struct.pack('<4H', 72, 105, 400, 33)+b'x'"
done
both r26 bpeenc flip.bin 400 mix.txt r26.tok
chk neg-flipped-byte-26 r26 26 '!r26.tok'
both r26d bpedec flip.bin mix400.tok r26.dec
chk dec-flipped-byte-26 r26d 26 '!r26.dec'
both r26m bpeenc magic.bin 400 mix.txt r26m.tok
chk bad-magic-26 r26m 26 '!r26m.tok'
both r26s bpeenc short.bin 400 mix.txt r26s.tok
chk short-file-26 r26s 26 '!r26s.tok'
both r27 bpeenc mix.bin 401 mix.txt r27.tok
chk v-over-merges-27 r27 27 '!r27.tok'
both r27b bpeenc mix.bin 256 mix.txt r27b.tok
chk enc-v256-27 r27b 27 '!r27b.tok'
both r2627 bpeenc flip.bin 401 mix.txt r2627.tok
chk order-26-before-27 r2627 26 '!r2627.tok'
both r21 bpedec mix.bin odd.tok odd.dec
chk odd-token-file-21 r21 21 '!odd.dec'
both r25 bpedec mix.bin big.tok big.dec
chk token-over-v-25 r25 25 '!big.dec'
both r2125 bpedec mix.bin bigodd.tok bigodd.dec
chk odd-before-25 r2125 21 '!bigodd.dec'
gotonly u1 bpeenc mix.bin 400 mix.txt; rc enc-usage-2 u1 2
gotonly u2 bpedec mix.bin mix400.tok; rc dec-usage-2 u2 2
gotonly u3 bpefit mix.txt; rc fit-usage-2 u3 2
# control of the comparison: a different token file must be seen as different
cp "$REF/mix300.tok" "$WORK/tmp/c.tok"
if cmp -s "$WORK/tmp/c.tok" "$REF/mix400.tok"; then ko neg-cmp-sees-difference; else ok neg-cmp-sees-difference; fi

echo "SUMMARY pass=$pass fail=$fail"
[ "$fail" = 0 ]
