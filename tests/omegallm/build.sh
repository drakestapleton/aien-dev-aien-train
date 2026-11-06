#!/bin/sh
# Build ollm (aien-train#52) from native/omegallm/*.om with the pinned seeded omc.
# Usage: sh tests/omegallm/build.sh [--mutant a|b|c|d|e|g|h|m|f|k|s|p|t|r|x|q|w|u|l|o|v|n|y | --variant h5|h7|r0|bx]
# Env: TARGET (aarch64, the default, gb10, x86linux or x86efi), OMC (default ../omega-mv/seed/out/omc
#      beside this clone for aarch64 and gb10, ../omega-mv-x86/seed/out/omc for x86linux,
#      ../omega-efi-ident/seed/out/omc for x86efi), OUT (default ../build beside it), CORE (taskset core,
#      default 6).
# Each target has its own pinned omc: aarch64 is omega-mv e5b32567 (the v0 pin); x86linux is
# omega-mv main ba5559d9, whose omc has the x86-64 Linux backend with SSE2 floats (docs/X86-LINUX.md);
# x86efi is omega-mv PR #1022 commit cf9fbda1a7be33964070a4ba3e2f89ab7aaa21e7 (branch feat/x86efi-ident:
# omega-mv main d3d1b1bc, where PR #1015's x86efi backend merged on 2026-11-04, plus efi 14, docs/X86-EFI.md),
# whose omc adds the UEFI x86-64 backend with efi 12 (files), efi 13 (console) and efi 14 (identity).
# The receipts in evidence/OMEGALLM/efi and imac were built with omc b4f45121 from #1015's commit
# 5ce9ecaa, an ancestor of d3d1b1bc (evidence/OMEGALLM/efi/repin-d3d1b1bc.txt).
# For x86linux and x86efi the concatenated source starts with the opt-in line `target x86linux` or
# `target x86efi`; every later line is the same as the aarch64 source except the platform unit, which
# is lio.om on Linux and eio.om on UEFI (CONTRACT §9). The x86efi output is ollm.efi, a PE32+ EFI
# application. The CPU-only targets end with nogpu.om, whose ogmask (model.om's gcmp2 ReLU mask
# hook) refuses with exit 2; gb10 takes ogmask from gpu/gg.om instead.
# gb10 is the aarch64 build plus native/omegallm/gpu/ (rung 4): the CPU `fn main` is renamed
# ocpumain (exactly one line) and gg.om's main adds the GPU commands gcmp, gcmp2, gtrain, gacmp,
# gtrainf, geval and gprof on the raw NVIDIA driver (no CUDA). gpu/context.om, vector.om and launch.om are vendored
# unmodified from aien-dev/CUDApp dcba8bb8 (native/nvrm/context.om, native/blackwell/vector.om and
# launch.om). The output is ollm-gb10; mutant g (gg.om OMUTG) breaks the attention DK backward for
# gcmp and gcmp2, mutant h (gr.om OMUTH) sets the on-chip Adam beta1 to 0.8 for gacmp, mutant m
# (gk.om OMUTM) makes the chip's fused dF ReLU mask (GEMM epilogue ep 2) FP > 2^-10 while its forward
# and FP stay unchanged,
# mutant f (gg.om OMUTF) uploads layer 0's W1 times 1 + 2^-10, a forward error gcmp2's FP check must
# name, mutant k (gr.om OMUTK) makes each CE lane's sum a plain sequential f32 sum (a lane of the
# warp-per-row CE kernel sums V/32 terms, so its effect is reported, not a control), mutant s
# (gr.om OMUTS) drops the lane-1 butterfly step of the softmax row sum, which gcmp and gcmp2 must
# catch, mutant p (gg.om OMUTP) drops the last split-K slice
# of the weight-gradient sum, which gcmp2 must catch, mutant t (gk.om OMUTT) drops one k = 7
# product per K tile from the first accumulator of every 64x64 GEMM thread, which gcmp2 must catch,
# mutant r (gr.om OMUTR) drops the lane-1 butterfly step of the RMS backward row sum
# sum(da g v), which gcmp2 must catch, mutant x (gr.om OMUTX) drops the lane-1 butterfly step
# of the CE kernel's warp sum of exp(l - m), which gcmp2 and geval must catch, mutant q (gk.om
# OMUTQ) stops each causal P U and DS K GEMM row tile one K tile before the diagonal block's end,
# which gcmp2 must catch, and mutant w (gr.om OMUTW) makes both softmax kernels skip loading the
# diagonal 32-column chunk of each row from chunk 1 on, which gcmp2 must catch.
# BF16 (gpu/gb.om, concatenated before gg.om; docs/omegallm/CONTRACT-BF16.md): gtrainb, gprofb, gbcmp,
# gbcmp2 and gbfrag. Mutant u (gb.om OMUTU) skips the bf16 rounding in the gates' reference, mutant l
# (gk.om OMUTL) swaps the A fragment rows of lanes g and g ^ 1, mutant o (gk.om OMUTO) runs one K tile
# fewer and mutant v (gk.om OMUTV) rounds the operands toward zero (F2FP RZ); gbfrag must catch all four;
# gbcmp must catch l, o and v (u is reported only). Mutant n (gb.om OMUTN) is the negative control of
# gbfrag's padding check: the host overwrites one C padding word after each short case's launch, which
# only that check can catch.
# The pool file (CONTRACT-V3 section 2) follows data.om: lpool.om holds the bank-B globals oww, ogb
# and oab on the Linux targets, epool.om one-element placeholders on x86efi (its v3 limit is the
# v2 bank-A capacity).
# serve (DRA-119, native/omegallm/serve.om): aarch64 starts with the line `om2` and concatenates
# net/http.om, net/json.om and net/jsonw.om (vendored unmodified from omega-mv e5b32567 seed/net/http.om,
# seed/json/json.om and seed/json/jsonw.om; sha256 below, checked at build) before the ollm units and
# serve.om after them. gb10, x86linux and x86efi take noserve.om, whose cmdserve exits 2.
# Mutants (ollm-mut-X, one changed line) plant a defect the checks must catch. Variants (ollm-var-X)
# h5 and h7 (two changed lines) set both gcheck steps GCH and GCH2 to 1e-5 (h5) or 1e-7 (h7), the step
# sizes that the README's GCH section rejects; r0 (gk.om OKREU 0, one changed line) clears the GEMM FFMA
# reuse bits, for attributing k7's GEMM timing; bx (three changed lines) shrinks the bank-A capacities
# to OWC 8400, OGC 5000 and OAC 12344, so the small shape 256 8 16 2 32 4 crosses every bank (LA = 1,
# LAA = 1, BLK past OGC) for the bank-crossing test. Mutant y (four changed lines) is bx plus OMUTY 0:
# ostw stages the first bank-B layer for every layer, which the bank-crossing test must catch. (Until
# the BF16 merge this mutant was called v, OMUTV; v is now BF16's gk.om mutant.)
# Variants are made by sed on the concatenated copy only, and the number of changed lines is checked.
set -eu
here=$(cd "$(dirname "$0")/../.." && pwd)
TARGET=${TARGET:-aarch64}
case "$TARGET" in
  aarch64|gb10) PIN=2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f
           OMC=${OMC:-$here/../omega-mv/seed/out/omc} lead= plat=lio.om pool=lpool.om ext= ;;
  x86linux) PIN=be8c51301307555254fc59e351d281aae1aa096d91521777e33a41c8b446448a
            OMC=${OMC:-$here/../omega-mv-x86/seed/out/omc} lead='target x86linux' plat=lio.om pool=lpool.om ext= ;;
  x86efi) PIN=3ad9f10f64309e7acf8a725082b28e23a2a4aeb07e98322fb4dc0fcd8fc93194
          OMC=${OMC:-$here/../omega-efi-ident/seed/out/omc} lead='target x86efi' plat=eio.om pool=epool.om ext=.efi ;;
  *) echo "TARGET must be aarch64, gb10, x86linux or x86efi" >&2; exit 2 ;;
esac
OUT=${OUT:-$here/../build}
CORE=${CORE:-6}
mut= kind=
if [ $# -ge 1 ]; then
  { [ "$1" = --mutant ] || [ "$1" = --variant ]; } && [ $# -eq 2 ] || { echo "usage: build.sh [--mutant a|b|c|d|e|g|h|m|f|k|s|p|t|r|x|q|w|u|l|o|v|n|y | --variant h5|h7|r0|bx]" >&2; exit 2; }
  kind=$1 mut=$2
fi
got=$(sha256sum "$OMC" | cut -d' ' -f1)
[ "$got" = "$PIN" ] || { echo "OMC_PIN_MISMATCH $got" >&2; exit 3; }
mkdir -p "$OUT"
src=$here/native/omegallm
name=ollm
if [ "$TARGET" = aarch64 ]; then
  ( cd "$src/net" && sha256sum -c --quiet - ) <<'EOF' || { echo "NET_PIN_MISMATCH" >&2; exit 3; }
aff258ecd3858454056811a5e6fe1f660f9d650a7207d6c41885105110e046a7  http.om
456254fc754ea35103ced480407b24fc1a3896d094b90ae0e9623e7b6594e2d2  json.om
464f649e8207495f5d67fe8795d31e42ea3ccebd9ed547274dab802d4f7c5f21  jsonw.om
EOF
  lead=om2
  pre="$src/net/http.om $src/net/json.om $src/net/jsonw.om" post=$src/serve.om
else
  pre= post=$src/noserve.om
fi
{
  [ -z "$lead" ] || printf '%s\n' "$lead"
  # shellcheck disable=SC2086
  [ -z "$pre" ] || cat $pre
  cat "$src/math.om" "$src/data.om" "$src/$pool" "$src/model.om" "$src/adam.om" "$src/ckpt.om" "$src/bpe.om" "$src/cli.om" "$src/$plat" "$post"
  [ "$TARGET" = gb10 ] || cat "$src/nogpu.om"
} > "$OUT/ollm.om"
if [ "$TARGET" = gb10 ]; then
  ext=-gb10
  n=$(grep -c '^fn main to int$' "$OUT/ollm.om" || true)
  [ "$n" = 1 ] || { echo "MAIN_COUNT $n, want 1" >&2; exit 4; }
  sed 's/^fn main to int$/fn ocpumain to int/' "$OUT/ollm.om" > "$OUT/ollm.tmp.om"
  g=$src/gpu
  cat "$OUT/ollm.tmp.om" "$g/context.om" "$g/vector.om" "$g/launch.om" "$g/gk.om" "$g/gr.om" "$g/gb.om" "$g/gg.om" > "$OUT/ollm.om"
  rm -f "$OUT/ollm.tmp.om"
fi
case "$kind$mut" in
  '') ;;
  --mutanta) pat='s/^const OMUTA ulong 1$/const OMUTA ulong 0/' want=1 ;;
  --mutantb) pat='s/^const OMUTB ulong 1$/const OMUTB ulong 2/' want=1 ;;
  --mutantc) pat='s/^const OMUTC ulong 1$/const OMUTC ulong 0/' want=1 ;;
  --mutantd) pat='s/^const OMUTD ulong 1$/const OMUTD ulong 0/' want=1 ;;
  --mutante) pat='s/^const OMUTE ulong 1$/const OMUTE ulong 0/' want=1 ;;
  --mutantg) pat='s/^const OMUTG ulong 1$/const OMUTG ulong 0/' want=1 ;;
  --mutanth) pat='s/^const OMUTH ulong 1$/const OMUTH ulong 0/' want=1 ;;
  --mutantm) pat='s/^const OMUTM ulong 1$/const OMUTM ulong 0/' want=1 ;;
  --mutantf) pat='s/^const OMUTF ulong 1$/const OMUTF ulong 0/' want=1 ;;
  --mutantk) pat='s/^const OMUTK ulong 1$/const OMUTK ulong 0/' want=1 ;;
  --mutants) pat='s/^const OMUTS ulong 1$/const OMUTS ulong 0/' want=1 ;;
  --mutantp) pat='s/^const OMUTP ulong 1$/const OMUTP ulong 0/' want=1 ;;
  --mutantt) pat='s/^const OMUTT ulong 1$/const OMUTT ulong 0/' want=1 ;;
  --mutantr) pat='s/^const OMUTR ulong 1$/const OMUTR ulong 0/' want=1 ;;
  --mutantx) pat='s/^const OMUTX ulong 1$/const OMUTX ulong 0/' want=1 ;;
  --mutantq) pat='s/^const OMUTQ ulong 1$/const OMUTQ ulong 0/' want=1 ;;
  --mutantw) pat='s/^const OMUTW ulong 1$/const OMUTW ulong 0/' want=1 ;;
  --mutantu) pat='s/^const OMUTU ulong 1$/const OMUTU ulong 0/' want=1 ;;
  --mutantl) pat='s/^const OMUTL ulong 1$/const OMUTL ulong 0/' want=1 ;;
  --mutanto) pat='s/^const OMUTO ulong 1$/const OMUTO ulong 0/' want=1 ;;
  --mutantv) pat='s/^const OMUTV ulong 1$/const OMUTV ulong 0/' want=1 ;;
  --mutantn) pat='s/^const OMUTN ulong 1$/const OMUTN ulong 0/' want=1 ;;
  --mutanty) pat='s/^const OWC ulong 15833472$/const OWC ulong 8400/;s/^const OGC ulong 15833472$/const OGC ulong 5000/;s/^const OAC ulong 15016192$/const OAC ulong 12344/;s/^const OMUTY ulong 1$/const OMUTY ulong 0/' want=4 ;;
  --varianth5) pat='s/^const GCH f64 0\.000001$/const GCH f64 0.00001/;s/^const GCH2 f64 0\.00000025$/const GCH2 f64 0.00001/' want=2 ;;
  --varianth7) pat='s/^const GCH f64 0\.000001$/const GCH f64 0.0000001/;s/^const GCH2 f64 0\.00000025$/const GCH2 f64 0.0000001/' want=2 ;;
  --variantr0) pat='s/^const OKREU ulong 1$/const OKREU ulong 0/' want=1 ;;
  --variantbx) pat='s/^const OWC ulong 15833472$/const OWC ulong 8400/;s/^const OGC ulong 15833472$/const OGC ulong 5000/;s/^const OAC ulong 15016192$/const OAC ulong 12344/' want=3 ;;
  *) echo "usage: build.sh [--mutant a|b|c|d|e|g|h|m|f|k|s|p|t|r|x|q|w|u|l|o|v|n|y | --variant h5|h7|r0|bx]" >&2; exit 2 ;;
esac
if [ -n "$mut" ]; then
  [ "$kind" = --mutant ] && name=ollm-mut-$mut || name=ollm-var-$mut
  sed "$pat" "$OUT/ollm.om" > "$OUT/$name.om"
  n=$(diff "$OUT/ollm.om" "$OUT/$name.om" | grep -c '^>' || true)
  [ "$n" = "$want" ] || { echo "SED_CHANGED $n lines, want $want" >&2; exit 4; }
fi
set +e
taskset -c "$CORE" nice -n 19 "$OMC" < "$OUT/$name.om" > "$OUT/$name.tmp"
rc=$?
set -e
if [ $rc -ne 0 ]; then
  rm -f "$OUT/$name.tmp"
  echo "BUILD_FAIL omc rc=$rc" >&2
  exit 1
fi
chmod +x "$OUT/$name.tmp"
mv "$OUT/$name.tmp" "$OUT/$name$ext"
echo "BUILD_OK $(sha256sum "$OUT/$name$ext" | cut -d' ' -f1) $OUT/$name$ext source_sha256 $(sha256sum "$OUT/$name.om" | cut -d' ' -f1)"
