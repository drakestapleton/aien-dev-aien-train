#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# DRA-15 / aien-train#26 P0 native replay of native/collective/shared_bank_p0.om.
#
#   OMC=/path/to/seed/out/omc sh native/collective/replay/run.sh OUTDIR
#
# Runs from the repository root. OMC must hash to the aien-train aarch64 pin
# (omega-mv e5b32567, omc sha256 2c824805...); any other compiler exits 77
# (NOT_RUN). Linux AArch64 only (omc writes a static AArch64 ELF).
#
# What it checks:
#  1. the merged self-test program compiles and exits 0 (its own embedded check);
#  2. an observation build (every line of the program before "fn main to int",
#     byte-identical, plus
#     replay/p0emit-main.om) prints every observable, and its stdout must equal
#     replay/expected-p0e1.out byte for byte. That file is the Wolfram result
#     (sha256 829b9a67..., see evidence/COLLECTIVE-P0/oracle-query.wl), so the
#     judge is not a value the program carries;
#  3. the comparator itself refuses a one-byte-corrupted expectation;
#  4. eight compiled mutants (adapter sign, routing order, factor, base reuse,
#     admission mask, phase refusal, index refusal, and a coordinated mutant
#     that also rewrites the program's own expected tables) must each be
#     detected by the independent oracle. The self-test verdict is recorded
#     beside it; the coordinated mutant is expected to pass the self-test.
# Output: OUTDIR/receipt.tsv, raw stdout/stderr/status per build and run, and a
# final line "P0REPLAY PASS ..." or "P0REPLAY FAIL ..." (exit 0 / 1).
set -u
PIN=2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f
ORACLE_SHA=829b9a67f432f070dd4fbaa44fab8401d6d9c614ceec3dd0d12555549881cfff
SRC=native/collective/shared_bank_p0.om
TAIL=native/collective/replay/p0emit-main.om
EXP=native/collective/replay/expected-p0e1.out
OUT=${1:?usage: OMC=... sh run.sh OUTDIR}
OMC=${OMC:?set OMC}
[ "$(uname -m)" = aarch64 ] || { echo "P0REPLAY NOT_RUN host $(uname -m) is not aarch64"; exit 77; }
got=$(sha256sum "$OMC" | cut -d' ' -f1)
[ "$got" = "$PIN" ] || { echo "P0REPLAY NOT_RUN omc $got is not the pin $PIN"; exit 77; }
[ "$(sha256sum "$EXP" | cut -d' ' -f1)" = "$ORACLE_SHA" ] || { echo "P0REPLAY FAIL expected file is not the Wolfram result"; exit 1; }
[ "$(sed -n 150p "$SRC")" = "fn main to int" ] && [ "$(sed -n 148p "$SRC")" = end ] || { echo "P0REPLAY FAIL line 150 of $SRC is not fn main"; exit 1; }
mkdir -p "$OUT"
R="$OUT/receipt.tsv"
printf 'case\tbuild\tsource_sha256\tcompile_rc\tbinary_sha256\trun_exit\tstdout_sha256\tverdict\n' > "$R"
fails=0
note() { printf '%s\n' "$*"; }

# build NAME SOURCE: compile; never run a refused compile's output.
build() {
  "$OMC" < "$2" > "$OUT/$1.bin" 2> "$OUT/$1.compile.stderr"
  crc=$?
  echo "$crc" > "$OUT/$1.compile.status"
  bsha=-
  if [ "$crc" = 0 ]; then chmod 755 "$OUT/$1.bin"; bsha=$(sha256sum "$OUT/$1.bin" | cut -d' ' -f1); fi
}
# run NAME: execute a built binary with a 10 s ceiling.
run() {
  rexit=-; osha=-
  if [ "$crc" = 0 ]; then
    timeout 10 "$OUT/$1.bin" > "$OUT/$1.stdout" 2> "$OUT/$1.stderr"
    rexit=$?
    echo "$rexit" > "$OUT/$1.status"
    osha=$(sha256sum "$OUT/$1.stdout" | cut -d' ' -f1)
  fi
}
row() { # case build source verdict
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$(sha256sum "$3" | cut -d' ' -f1)" "$crc" "$bsha" "$rexit" "$osha" "$4" >> "$R"
}
# emitsrc SRCFILE DEST: observation unit = every line before "fn main to int" + tail.
emitsrc() { sed '/^fn main to int$/,$d' "$1" > "$2"; cat "$TAIL" >> "$2"; }

# 1+2. The merged program, three repeats each.
for k in 1 2 3; do
  build "selftest-$k" "$SRC"; run "selftest-$k"
  v=FAIL; [ "$crc" = 0 ] && [ "$rexit" = 0 ] && v=PASS
  [ "$v" = PASS ] || fails=$((fails+1))
  row original selftest "$SRC" "$v"
  emitsrc "$SRC" "$OUT/emit.om"
  build "emit-$k" "$OUT/emit.om"; run "emit-$k"
  v=FAIL; [ "$crc" = 0 ] && [ "$rexit" = 0 ] && cmp -s "$OUT/emit-$k.stdout" "$EXP" && v=PASS
  [ "$v" = PASS ] || fails=$((fails+1))
  row original oracle "$OUT/emit.om" "$v"
done
[ "$(sha256sum "$OUT/selftest-1.bin" | cut -d' ' -f1)" = "$(sha256sum "$OUT/selftest-3.bin" | cut -d' ' -f1)" ] || { note "nondeterministic compile"; fails=$((fails+1)); }

# 3. Comparator negative control: one byte of the expectation changed.
sed '2s/-2 -2$/-2 -3/' "$EXP" > "$OUT/expected-corrupt.out"
if cmp -s "$OUT/emit-1.stdout" "$OUT/expected-corrupt.out"; then v=FAIL; fails=$((fails+1)); else v=PASS; fi
crc=0; bsha=-; rexit=-; osha=$(sha256sum "$OUT/expected-corrupt.out" | cut -d' ' -f1)
row comparator-corrupt-expectation oracle "$OUT/expected-corrupt.out" "$v"

# 4. Mutants. mutate NAME LINE 'OLD' 'NEW' [LINE 'OLD' 'NEW' ...] on top of SRC.
#    NEW of "+makebase" inserts that statement after LINE instead.
mutate() {
  m=$1; shift
  cp "$SRC" "$OUT/$m.om"
  while [ $# -ge 3 ]; do
    ln=$1; old=$2; new=$3; shift 3
    cur=$(sed -n "${ln}p" "$OUT/$m.om")
    [ "$cur" = "$old" ] || { note "mutant $m: line $ln is '$cur', wanted '$old'"; return 1; }
    case $new in
      +*) sed "${ln}a\\
${new#+}" "$OUT/$m.om" > "$OUT/$m.tmp" ;;
      *) sed "${ln}s/.*/$new/" "$OUT/$m.om" > "$OUT/$m.tmp" ;;
    esac
    mv "$OUT/$m.tmp" "$OUT/$m.om"
  done
}
swaptables() { # coordinated mutant: swap the program's own Plus/Minus tables (lines 52..83)
  sed '52,83{s/put Plus/put Tmpx/;s/put Minus/put Plus/;s/put Tmpx/put Minus/;}' "$OUT/$1.om" > "$OUT/$1.tmp"
  mv "$OUT/$1.tmp" "$OUT/$1.om"
}
mutcase() { # NAME: self-test + oracle verdict for an already written $OUT/NAME.om
  m=$1
  build "$m-selftest" "$OUT/$m.om"; run "$m-selftest"
  if [ "$crc" = 0 ] && [ "$rexit" = 0 ]; then st=SELFTEST_MISSED; else st=SELFTEST_CAUGHT; fi
  [ "$crc" = 0 ] || { st="MUTANT_INVALID_compile$crc"; fails=$((fails+1)); }
  row "$m" selftest "$OUT/$m.om" "$st"
  emitsrc "$OUT/$m.om" "$OUT/$m-emit.om"
  build "$m-emit" "$OUT/$m-emit.om"; run "$m-emit"
  if [ "$crc" = 0 ] && [ "$rexit" = 0 ] && cmp -s "$OUT/$m-emit.stdout" "$EXP"; then v=ORACLE_MISSED; fails=$((fails+1)); else v=ORACLE_KILLED; fi
  [ "$crc" = 0 ] || { v="MUTANT_INVALID_compile$crc"; fails=$((fails+1)); }
  row "$m" oracle "$OUT/$m-emit.om" "$v"
  printf '%s %s %s\n' "$m" "$st" "$v"
}
mutate m1-sign 143 'result = add get Shared row mul phase diff' 'result = sub get Shared row mul phase diff' && mutcase m1-sign
mutate m2-route 109 'if gt score bscore' 'if lt score bscore' && mutcase m2-route
mutate m3-factor 44 'put U ui sub sid 3' 'put U ui sub sid 4' && mutcase m3-factor
mutate m4-rebase 133 'end' '+makebase' && mutcase m4-rebase
mutate m5-mask 105 'if eq get Allowed id 1' 'if eq uchar 1 uchar 1' && mutcase m5-mask
mutate m6-phase 131 'ret -3' 'ret 0' && mutcase m6-phase
mutate m7-index 123 'if ge id 8' 'if ge id 9' && mutcase m7-index
mutate m8-coordinated 143 'result = add get Shared row mul phase diff' 'result = sub get Shared row mul phase diff' && swaptables m8-coordinated && mutcase m8-coordinated
nm=$(grep -c -E '^m[0-9]-[a-z]+	oracle' "$R")
[ "$nm" = 8 ] || { note "expected 8 mutant oracle rows, got $nm"; fails=$((fails+1)); }

# 5. Overflow refusal control: an input whose base matvec overflows signed
#    64-bit must trap (trap 1, exit 101) before any END line, never print a
#    wrapped result. This exercises the language's checked arithmetic, not a
#    check the P0 program implements itself.
mutate c1-overflow 30 'put X 2 5' 'put X 2 9223372036854775807' && {
  emitsrc "$OUT/c1-overflow.om" "$OUT/c1-overflow-emit.om"
  build c1-overflow-emit "$OUT/c1-overflow-emit.om"; run c1-overflow-emit
  if [ "$crc" = 0 ] && [ "$rexit" = 101 ] && ! grep -q '^END$' "$OUT/c1-overflow-emit.stdout"; then v=REFUSED_TRAP1; else v=NOT_REFUSED; fails=$((fails+1)); fi
  row c1-overflow oracle "$OUT/c1-overflow-emit.om" "$v"
  printf 'c1-overflow %s exit %s\n' "$v" "$rexit"
}
grep -q '^c1-overflow	oracle	' "$R" || { note "overflow control did not run"; fails=$((fails+1)); }

note "omc $got"
note "selftest binary $(sha256sum "$OUT/selftest-1.bin" | cut -d' ' -f1) exit $(cat "$OUT/selftest-1.status")"
note "oracle binary $(sha256sum "$OUT/emit-1.bin" | cut -d' ' -f1) exit $(cat "$OUT/emit-1.status")"
if [ "$fails" = 0 ]; then note "P0REPLAY PASS original=selftest+oracle x3 comparator=refuses mutants_killed=8/8 overflow=trap1"; exit 0; fi
note "P0REPLAY FAIL failures=$fails"; exit 1
