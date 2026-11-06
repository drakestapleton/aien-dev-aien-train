#!/bin/sh
# Own BPE tokenizer check (tests/omegallm/tok/FORMAT.md): ollm-tok toktrain, tokenc, tokdec and
# tokinfo against the test oracle tests/omegallm/tok/oracle.py (Python, verification only) on
# synthetic texts and fixtures, exact round trips on random bytes and Unicode, determinism, every
# exit code, and refusal of corrupted merges files. Needs no data directory; runs in about a minute.
#
#   BIN=path/to/ollm-tok  sh tests/omegallm/tok/check.sh
#
# Environment: BIN (required, from tests/omegallm/tok/build.sh), WORK (scratch, default
# scratch-tok-check beside the clone), CORES (taskset core list, default 18-19). The whole script
# runs at nice 10 inside bwrap with no network; only WORK is writable.
# One PASS/FAIL line per case, then `SUMMARY pass=N fail=M`; exit 0 iff fail=0.
# Negative controls: the comparison must see a deliberately changed token file, and every
# corrupted merges file (flipped byte, wrong length, rehashed bad pair) must be refused with 26.
set -u
here=$(cd "$(dirname "$0")" && pwd)
BIN=${BIN:?set BIN to the ollm-tok binary}
BIN=$(cd "$(dirname "$BIN")" && pwd)/$(basename "$BIN")
WORK=${WORK:-$here/../../../../scratch-tok-check}
CORES=${CORES:-18-19}
if [ -z "${TOK_CHECK_PINNED:-}" ]; then
    mkdir -p "$WORK"
    WORK=$(cd "$WORK" && pwd)
    export TOK_CHECK_PINNED=1 WORK BIN
    exec taskset -c "$CORES" nice -n 10 bwrap --ro-bind / / --dev /dev --proc /proc --tmpfs /tmp \
        --bind "$WORK" "$WORK" --unshare-net --die-with-parent -- sh "$0" "$@"
fi
export PYTHONDONTWRITEBYTECODE=1
ORACLE="$here/oracle.py"
[ -x "$BIN" ] || { echo "tok-check: BIN $BIN is not executable" >&2; exit 2; }
IN="$WORK/in" REF="$WORK/ref" GOT="$WORK/bin"
rm -rf "$IN" "$REF" "$GOT"
mkdir -p "$IN" "$REF" "$GOT"
echo "tok-check: bin sha256=$(sha256sum "$BIN" | cut -c1-16) cores=$CORES"

pass=0 fail=0
ok() { echo "PASS $1${2:+ ($2)}"; pass=$((pass + 1)); }
ko() { echo "FAIL $1${2:+ ($2)}" | sed "s|$WORK/||g"; fail=$((fail + 1)); }
# r DIR TAG CMD...: run CMD in DIR; TAG.out, TAG.err, TAG.rc
r() { _d=$1 _t=$2; shift 2; (cd "$_d" && "$@" >"$_t.out" 2>"$_t.err"; echo $? >"$_t.rc"); }
both() { _t=$1; shift; r "$REF" "$_t" python3 "$ORACLE" "$@"; r "$GOT" "$_t" "$BIN" "$@"; }
rc() { cat "$1/$2.rc"; }
# chk NAME TAG RC [FILE|!FILE]...: both exits must be RC, both stdouts equal (the binary's T line
# cut to six fields), each FILE equal in both dirs, each !FILE absent from both dirs
chk() {
    _n=$1 _t=$2 _rc=$3; shift 3
    _a=$(rc "$REF" "$_t") _b=$(rc "$GOT" "$_t")
    if [ "$_a" != "$_rc" ] || [ "$_b" != "$_rc" ]; then ko "$_n" "exit oracle=$_a bin=$_b want $_rc"; return; fi
    if [ "$(cat "$REF/$_t.out")" != "$(cut -d' ' -f1-6 "$GOT/$_t.out")" ]; then
        ko "$_n" "stdout oracle='$(cat "$REF/$_t.out")' bin='$(cat "$GOT/$_t.out")'"; return; fi
    for _f in "$@"; do
        case $_f in
        !*) _f=${_f#!}
            if [ -e "$REF/$_f" ] || [ -e "$GOT/$_f" ]; then ko "$_n" "$_f left behind"; return; fi ;;
        *) if ! cmp -s "$REF/$_f" "$GOT/$_f"; then ko "$_n" "$_f differs"; return; fi ;;
        esac
    done
    ok "$_n" "$(cut -d' ' -f1-6 "$GOT/$_t.out" | tr -d '\n')"
}
# rt NAME MERGES MODE TEXT: binary encode then decode must give TEXT back byte for byte
rt() {
    _n=$1 _m=$2 _mode=$3 _x=$4
    r "$GOT" rt "$BIN" tokenc "$_mode" "$_m" "$_x" rt.tok
    r "$GOT" rtd "$BIN" tokdec "$_m" rt.tok rt.back
    if [ "$(rc "$GOT" rt)" != 0 ] || [ "$(rc "$GOT" rtd)" != 0 ]; then
        ko "$_n" "exit enc=$(rc "$GOT" rt) dec=$(rc "$GOT" rtd)"; return; fi
    if cmp -s "$_x" "$GOT/rt.back"; then ok "$_n" "$(cat "$GOT/rt.out")"; else ko "$_n" "decoded bytes differ"; fi
}
# flip FILE OFFSET: xor the byte at OFFSET with 1
flip() {
    _v=$(od -An -tu1 -j"$2" -N1 "$1" | tr -d ' ')
    printf "\\$(printf %03o $((_v ^ 1)))" | dd of="$1" bs=1 seek="$2" conv=notrunc 2>/dev/null
}
# spec FILE: how many u16 tokens of FILE are special ids (256 .. 271)
spec() { od -An -tu2 -v "$1" | tr -s ' ' '\n' | awk '$1 >= 256 && $1 < 272 { n++ } END { print n + 0 }'; }

python3 "$ORACLE" gen 400000 1 "$IN/g1.txt"
python3 "$ORACLE" gen 3200000 2 "$IN/g2.txt"
head -c 200000 /dev/urandom > "$IN/rand200k.bin"
head -c 1048576 /dev/urandom > "$IN/rand1m.bin"
cat "$here/chat.txt" "$IN/g1.txt" "$here/chat.txt" > "$IN/chatmix.txt"
cat "$here/unicode.txt" > "$IN/uni.txt"
printf '\377\376\303(\355\240\200\300\257 \360\237\230 end\200\n' >> "$IN/uni.txt"
echo "tok-check: inputs rand1m sha256=$(sha256sum "$IN/rand1m.bin" | cut -c1-16) g2=$(wc -c < "$IN/g2.txt") bytes"

# 1. usage and argument errors
r "$GOT" u0 "$BIN"
both u1 bogus
both u2 toktrain raw "$IN/g1.txt" m.bin 1000
both u3 toktrain RAW "$IN/g1.txt" m.bin 1000 0
both u4 toktrain raw "$IN/g1.txt" m.bin 271 0
both u5 toktrain raw "$IN/g1.txt" m.bin 32769 0
both u6 toktrain raw "$IN/g1.txt" m.bin 10a0 0
[ "$(rc "$GOT" u0)" = 2 ] && ok "usage: no command exits 2" || ko "usage: no command" "exit $(rc "$GOT" u0)"
chk "usage: unknown command" u1 2
chk "usage: wrong argument count" u2 2 '!m.bin'
chk "usage: unknown mode" u3 2 '!m.bin'
chk "usage: V 271 below 272" u4 2 '!m.bin'
chk "usage: V 32769 above 32768" u5 2 '!m.bin'
chk "usage: V not a number" u6 2 '!m.bin'
r "$GOT" u7 "$BIN" tokinfo "$IN/absent.bin"
[ "$(rc "$GOT" u7)" = 70 ] && ok "missing merges file exits 70" || ko "missing merges file" "exit $(rc "$GOT" u7)"

# 2. against the oracle: training, encoding, decoding, raw and chat
both tr1 toktrain raw "$IN/g1.txt" m1.bin 1500 0
chk "train raw V=1500 on 400 kB synthetic: same merges file" tr1 0 m1.bin
both tr2 toktrain chat "$IN/chatmix.txt" m2.bin 1200 0
chk "train chat V=1200 on chat fixture + synthetic: same merges file" tr2 0 m2.bin
both tr3 toktrain raw "$IN/g2.txt" m3.bin 800 250000
chk "train raw MAXBYTES=250000 of a 3.2 MB text: same merges file" tr3 0 m3.bin
both tr4 toktrain raw "$IN/rand200k.bin" m4.bin 600 0
chk "train raw V=600 on 200 kB random bytes: same merges file" tr4 0 m4.bin
both in1 tokinfo "$IN/g1.txt"
chk "tokinfo refuses a text file" in1 26
cp "$GOT/m1.bin" "$IN/m1.bin"; cp "$GOT/m2.bin" "$IN/m2.bin"; cp "$GOT/m4.bin" "$IN/m4.bin"
both in2 tokinfo "$IN/m1.bin"
chk "tokinfo V, merges, checksum" in2 0
both en1 tokenc raw "$IN/m1.bin" "$IN/g2.txt" t1.tok
chk "encode raw 3.2 MB (window refills): same tokens" en1 0 t1.tok
both en2 tokenc chat "$IN/m2.bin" "$IN/chatmix.txt" t2.tok
chk "encode chat: same tokens and markers" en2 0 t2.tok
both en3 tokenc raw "$IN/m2.bin" "$IN/chatmix.txt" t3.tok
chk "encode raw text holding markers: same tokens" en3 0 t3.tok
both en4 tokenc raw "$IN/m4.bin" "$IN/rand1m.bin" t4.tok
chk "encode raw 1 MiB random bytes: same tokens" en4 0 t4.tok
both en5 tokenc chat "$IN/m1.bin" "$IN/uni.txt" t5.tok
chk "encode chat Unicode + invalid UTF-8: same tokens" en5 0 t5.tok
cp "$GOT/t1.tok" "$IN/t1.tok"; cp "$GOT/t2.tok" "$IN/t2.tok"
both de1 tokdec "$IN/m1.bin" "$IN/t1.tok" d1.txt
chk "decode raw 3.2 MB: same bytes" de1 0 d1.txt
both de2 tokdec "$IN/m2.bin" "$IN/t2.tok" d2.txt
chk "decode chat: same bytes" de2 0 d2.txt

# 3. exact round trips
rt "round trip raw 1 MiB random bytes (merges from random)" "$IN/m4.bin" raw "$IN/rand1m.bin"
rt "round trip chat 1 MiB random bytes (merges from text)" "$IN/m2.bin" chat "$IN/rand1m.bin"
rt "round trip raw Unicode + invalid UTF-8" "$IN/m1.bin" raw "$IN/uni.txt"
rt "round trip chat Unicode + invalid UTF-8" "$IN/m2.bin" chat "$IN/uni.txt"
rt "round trip chat fixture (chat mode)" "$IN/m2.bin" chat "$here/chat.txt"
rt "round trip chat fixture (raw mode)" "$IN/m2.bin" raw "$here/chat.txt"
rt "round trip 3.2 MB synthetic (chat mode)" "$IN/m1.bin" chat "$IN/g2.txt"
: > "$IN/empty.txt"
rt "round trip empty text" "$IN/m1.bin" raw "$IN/empty.txt"

# 4. chat special tokens
r "$GOT" sp1 "$BIN" tokenc chat "$IN/m2.bin" "$here/chat.txt" sp1.tok
r "$GOT" sp2 "$BIN" tokenc raw "$IN/m2.bin" "$here/chat.txt" sp2.tok
n1=$(spec "$GOT/sp1.tok") n2=$(spec "$GOT/sp2.tok") f1=$(cut -d' ' -f6 "$GOT/sp1.out") f2=$(cut -d' ' -f6 "$GOT/sp2.out")
nm=$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import oracle; t = open(sys.argv[2], "rb").read(); print(sum(1 for s, c in oracle.pieces(t, True) if s))' "$here" "$here/chat.txt")
if [ "$n1" = "$nm" ] && [ "$f1" = "$nm" ] && [ "$nm" -gt 20 ]; then ok "chat mode: every exact marker is one special token" "$n1 of $nm"; else ko "chat mode specials" "tokens=$n1 field=$f1 oracle=$nm"; fi
if [ "$n2" = 0 ] && [ "$f2" = 0 ]; then ok "raw mode: no special token, markers stay text"; else ko "raw mode specials" "tokens=$n2 field=$f2"; fi
od -An -tu2 -v "$GOT/sp1.tok" | tr -s ' ' '\n' | awk '$1 >= 256 && $1 < 264 { s[$1] = 1 } END { for (k = 256; k < 264; k++) if (!(k in s)) exit 1 }' \
    && ok "chat fixture uses all eight markers 256..263" || ko "chat fixture lacks a marker id"

# 5. determinism
r "$GOT" dt1 "$BIN" toktrain chat "$IN/chatmix.txt" dt1.bin 1200 0
r "$GOT" dt2 "$BIN" toktrain chat "$IN/chatmix.txt" dt2.bin 1200 0
h1=$(sha256sum "$GOT/dt1.bin" | cut -d' ' -f1) h2=$(sha256sum "$GOT/dt2.bin" | cut -d' ' -f1) h0=$(sha256sum "$IN/m2.bin" | cut -d' ' -f1)
[ "$h1" = "$h2" ] && [ "$h1" = "$h0" ] && ok "determinism: three trainings, one merges sha256" "${h1%"${h1#????????????????}"}" || ko "determinism" "$h0 $h1 $h2"
r "$GOT" dt3 "$BIN" tokenc chat "$GOT/dt1.bin" "$IN/chatmix.txt" dt3.tok
cmp -s "$GOT/dt3.tok" "$GOT/t2.tok" && ok "determinism: same tokens from a retrained file" || ko "determinism tokens"
ls "$GOT"/*.tmp >/dev/null 2>&1 && ko "atomic save: a .tmp file was left" || ok "atomic save: no .tmp file left"

# 6. refusals of corrupted merges files (each exit 26 from tokinfo, tokenc and tokdec, no output)
bad() {
    _n=$1 _f=$2
    both b1 tokinfo "$_f"
    both b2 tokenc raw "$_f" "$IN/g1.txt" b2.tok
    both b3 tokdec "$_f" "$IN/t1.tok" b3.txt
    for _t in b1 b2 b3; do
        if [ "$(rc "$REF" $_t)" != 26 ] || [ "$(rc "$GOT" $_t)" != 26 ]; then
            ko "refuse $_n" "$_t exit oracle=$(rc "$REF" $_t) bin=$(rc "$GOT" $_t)"; return; fi
    done
    if [ -e "$GOT/b2.tok" ] || [ -e "$GOT/b3.txt" ]; then ko "refuse $_n" "output left behind"; return; fi
    ok "refuse $_n" "26 x3"
}
sz=$(wc -c < "$IN/m1.bin")
for o in 0 8 16 24 32 $((sz / 2)) $((sz - 1)); do
    cp "$IN/m1.bin" "$IN/f$o.bin"; flip "$IN/f$o.bin" "$o"; bad "flipped byte at $o" "$IN/f$o.bin"
done
head -c $((sz - 1)) "$IN/m1.bin" > "$IN/short1.bin"; bad "one byte short" "$IN/short1.bin"
head -c $((sz - 4)) "$IN/m1.bin" > "$IN/short4.bin"; bad "one pair short" "$IN/short4.bin"
head -c 31 "$IN/m1.bin" > "$IN/short31.bin"; bad "31-byte header" "$IN/short31.bin"
cat "$IN/m1.bin" "$IN/empty.txt" > "$IN/extra.bin"; printf x >> "$IN/extra.bin"; bad "one extra byte" "$IN/extra.bin"
bad "empty file" "$IN/empty.txt"
for k in special reserved forward self dup long; do
    python3 "$ORACLE" mkbad $k "$IN/m1.bin" "$IN/k$k.bin"; bad "rehashed bad pair: $k" "$IN/k$k.bin"
done

# 7. token file errors and an exhausted text
printf '\010\001' > "$IN/tres.tok"
printf '\334\005' > "$IN/tbig.tok"
printf 'abc' > "$IN/todd.tok"
both te1 tokdec "$IN/m1.bin" "$IN/tres.tok" te1.txt
chk "decode refuses reserved id 264 (25, no output)" te1 25 '!te1.txt'
both te2 tokdec "$IN/m1.bin" "$IN/tbig.tok" te2.txt
chk "decode refuses id 1500 = V (25, no output)" te2 25 '!te2.txt'
both te3 tokdec "$IN/m1.bin" "$IN/todd.tok" te3.txt
chk "decode refuses an odd-length token file (21, no output)" te3 21 '!te3.txt'
printf 'ab ab ab' > "$IN/tiny.txt"
both te4 toktrain raw "$IN/tiny.txt" te4.bin 300 0
chk "train exits 28 when no pair is left (no file)" te4 28 '!te4.bin' '!te4.bin.tmp'

# 8. negative control: the comparison sees one changed token
cp "$GOT/t1.tok" "$WORK/neg.tok"; flip "$WORK/neg.tok" 1000
cmp -s "$WORK/neg.tok" "$REF/t1.tok" && ko "negative control: changed token not seen" || ok "negative control: changed token file differs from the oracle's"

echo "SUMMARY pass=$pass fail=$fail"
[ "$fail" = 0 ]
