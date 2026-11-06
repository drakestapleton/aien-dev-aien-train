#!/bin/sh
# Own BPE compression measurement: train ollm-tok merges on a prefix of a training text, then
# encode a public-domain sample and a held-out text, prove both round trips exact, and print the
# byte and token counts (the ratio bytes/tokens is computed outside this script).
#
#   BIN=path/to/ollm-tok TRAIN=text V=8192 MAXBYTES=100000000 PD=pg1342.txt HELD=valid.txt \
#       sh tests/omegallm/tok/ratio.sh
#
# PD is Project Gutenberg eBook #1342 (Pride and Prejudice, public domain in the USA), fetched by the
# operator from https://www.gutenberg.org/cache/epub/1342/pg1342.txt and checked by sha256 below;
# only the text between the START and END lines is encoded. It is never committed. A missing or
# different PD file gives NOT_RUN for that sample. HELD (optional) is any held-out text.
# Environment: WORK (scratch, default scratch-tok-ratio beside the clone; keep it under a private
# directory when TRAIN is private), CORES (default 18-19), MODE (raw or chat, default raw).
# Runs at nice 10 inside bwrap with no network; only WORK is writable.
set -u
here=$(cd "$(dirname "$0")" && pwd)
BIN=${BIN:?set BIN}
TRAIN=${TRAIN:?set TRAIN}
V=${V:-8192}
MAXBYTES=${MAXBYTES:-0}
PD=${PD:-}
HELD=${HELD:-}
MODE=${MODE:-raw}
WORK=${WORK:-$here/../../../../scratch-tok-ratio}
CORES=${CORES:-18-19}
PDSHA=3f6bb9d6f78e0293b56acd4714dd68cb7d6d1d293402031ce9d5a216bcaf9d75
if [ -z "${TOK_RATIO_PINNED:-}" ]; then
    mkdir -p "$WORK"
    WORK=$(cd "$WORK" && pwd)
    export TOK_RATIO_PINNED=1 WORK BIN TRAIN V MAXBYTES PD HELD MODE
    exec taskset -c "$CORES" nice -n 10 bwrap --ro-bind / / --dev /dev --proc /proc --tmpfs /tmp \
        --bind "$WORK" "$WORK" --unshare-net --die-with-parent -- sh "$0" "$@"
fi
cd "$WORK" || exit 2
echo "tok-ratio: bin sha256=$(sha256sum "$BIN" | cut -c1-16) mode=$MODE V=$V maxbytes=$MAXBYTES train_bytes=$(wc -c < "$TRAIN")"
/usr/bin/time -f "TIME toktrain %e s %M KiB" "$BIN" toktrain "$MODE" "$TRAIN" merges.bin "$V" "$MAXBYTES" || { echo "FAIL toktrain exit $?"; exit 1; }
echo "MERGES sha256=$(sha256sum merges.bin | cut -d' ' -f1) bytes=$(wc -c < merges.bin)"
fail=0
sample() {
    _n=$1 _f=$2
    /usr/bin/time -f "TIME tokenc $_n %e s" "$BIN" tokenc "$MODE" merges.bin "$_f" "$_n.tok" || { echo "FAIL $_n tokenc"; fail=1; return; }
    "$BIN" tokdec merges.bin "$_n.tok" "$_n.back" >/dev/null || { echo "FAIL $_n tokdec"; fail=1; return; }
    if cmp -s "$_f" "$_n.back"; then
        echo "MEASURED $_n bytes=$(wc -c < "$_f") tokens=$(( $(wc -c < "$_n.tok") / 2 )) round_trip=PASS"
    else
        echo "FAIL $_n round trip"; fail=1
    fi
    rm -f "$_n.back"
}
if [ -n "$PD" ] && [ -r "$PD" ] && [ "$(sha256sum "$PD" | cut -d' ' -f1)" = "$PDSHA" ]; then
    sed -n '/^\*\*\* START OF THE PROJECT GUTENBERG EBOOK/,/^\*\*\* END OF THE PROJECT GUTENBERG EBOOK/p' "$PD" \
        | sed '1d;$d' > pd-body.txt
    sample pg1342-body pd-body.txt
else
    echo "NOT_RUN pg1342-body: PD sample absent or not sha256 $PDSHA"
fi
if [ -n "$HELD" ] && [ -r "$HELD" ]; then
    sample held "$HELD"
else
    echo "NOT_RUN held: no HELD text"
fi
[ "$fail" = 0 ]
