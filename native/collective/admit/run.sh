#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# DRA-15 / aien-train#26 P0 admission refusal contract: native replay of
# native/collective/admit_p0.om against an oracle it does not carry.
#
#   OMC=/path/to/seed/out/omc sh native/collective/admit/run.sh OUTDIR
#
# Runs from the repository root. OMC must hash to the aien-train aarch64 pin
# (omega-mv e5b32567, omc sha256 2c824805...); any other compiler exits 77
# (NOT_RUN). Linux AArch64 only (omc writes a static AArch64 ELF).
#
# What it checks:
#  1. the unit's self-test compiles and exits 0, three times, with identical
#     binaries;
#  2. observation build A1 (every line of admit_p0.om before "fn main to int",
#     byte-identical, plus admit/a1emit-main.om) runs all 46 cases of
#     fixtures/admission_v0.json in one process; its stdout must equal
#     admit/expected-a1.out, the string Wolfram returned for
#     evidence/COLLECTIVE-P0-ADMIT/oracle-query.wl (sha256 pinned below).
#     Status, response and counters after every case are in that string, so a
#     refused case that writes a response or moves a counter is caught;
#  3. process build CLI (same prefix plus admit/cli-main.om) runs each case in
#     its own process; exit status and stdout must equal admit/expected-cli.out
#     (Wolfram): an admitted case exits 0 and prints one line, a refused case
#     exits with minus its status and prints nothing;
#  4. the comparators refuse one-byte-corrupted expectations, and the CLI tail
#     refuses bad arguments with a nonzero exit and no output;
#  5. one compiled guard-removal mutant per guard (17), plus a mutant that
#     computes before the admission verdict (state change on refusal), a
#     selection-order mutant and a coordinated mutant that also rewrites the
#     self-test's own expectations: each must be killed by the A1 oracle;
#  6. four score/permission swap mutants must be refused by the compiler
#     (omc error 7): the abstract types make the swap unrepresentable.
# Output: OUTDIR/receipt.tsv, raw stdout/stderr/status per build and run, and a
# final line "ADMITP0 PASS ..." or "ADMITP0 FAIL ..." (exit 0 / 1).
set -u
PIN=2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f
A1_SHA=a41baa404a15e90d2dabcc25ee4f6830754a67930be65015b5496fb3799fc66a
CLI_SHA=90c11b093b9d0038fcb1db2911f38268cead7df78ca5332a1bb4dfce3d356ab8
NCASE=46
SRC=native/collective/admit_p0.om
EMIT=native/collective/admit/a1emit-main.om
CLIT=native/collective/admit/cli-main.om
EXPA=native/collective/admit/expected-a1.out
EXPC=native/collective/admit/expected-cli.out
OUT=${1:?usage: OMC=... sh run.sh OUTDIR}
OMC=${OMC:?set OMC}
[ "$(uname -m)" = aarch64 ] || { echo "ADMITP0 NOT_RUN host $(uname -m) is not aarch64"; exit 77; }
got=$(sha256sum "$OMC" | cut -d' ' -f1)
[ "$got" = "$PIN" ] || { echo "ADMITP0 NOT_RUN omc $got is not the pin $PIN"; exit 77; }
[ "$(sha256sum "$EXPA" | cut -d' ' -f1)" = "$A1_SHA" ] || { echo "ADMITP0 FAIL $EXPA is not the Wolfram result"; exit 1; }
[ "$(sha256sum "$EXPC" | cut -d' ' -f1)" = "$CLI_SHA" ] || { echo "ADMITP0 FAIL $EXPC is not the Wolfram result"; exit 1; }
[ "$(grep -c '^fn main to int$' "$SRC")" = 1 ] || { echo "ADMITP0 FAIL $SRC must have exactly one fn main"; exit 1; }
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
# run NAME [ARG]: execute a built binary with a 10 s ceiling.
run() {
  rexit=-; osha=-
  if [ "$crc" = 0 ]; then
    timeout 10 "$OUT/$1.bin" ${2+"$2"} > "$OUT/$1.stdout" 2> "$OUT/$1.stderr"
    rexit=$?
    echo "$rexit" > "$OUT/$1.status"
    osha=$(sha256sum "$OUT/$1.stdout" | cut -d' ' -f1)
  fi
}
row() { # case build source verdict
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$(sha256sum "$3" | cut -d' ' -f1)" "$crc" "$bsha" "$rexit" "$osha" "$4" >> "$R"
}
# prefix SRCFILE TAIL DEST: every line before "fn main to int" + tail.
prefix() { sed '/^fn main to int$/,$d' "$1" > "$3"; cat "$2" >> "$3"; }
# clirun NAME: run the built CLI binary NAME once per case; write NAME.cli.out
# in the expected-cli.out format: "case exit stdout-line" or "case exit -".
clirun() {
  : > "$OUT/$1.cli.out"
  n=0
  while [ "$n" -lt "$NCASE" ]; do
    timeout 10 "$OUT/$1.bin" "$n" > "$OUT/$1.c$n.stdout" 2> "$OUT/$1.c$n.stderr"
    ex=$?
    f="$OUT/$1.c$n.stdout"
    if [ ! -s "$f" ]; then body=-
    elif [ "$(wc -l < "$f")" = 1 ] && [ "$(tail -c 1 "$f" | od -An -tx1 | tr -d ' ')" = 0a ]; then body=$(cat "$f")
    else body=BADFORM
    fi
    printf '%s %s %s\n' "$n" "$ex" "$body" >> "$OUT/$1.cli.out"
    n=$((n+1))
  done
}

# 1+2. Self-test and A1 observation, three repeats each.
prefix "$SRC" "$EMIT" "$OUT/a1.om"
prefix "$SRC" "$CLIT" "$OUT/cli.om"
for k in 1 2 3; do
  build "selftest-$k" "$SRC"; run "selftest-$k"
  v=FAIL; [ "$crc" = 0 ] && [ "$rexit" = 0 ] && v=PASS
  [ "$v" = PASS ] || fails=$((fails+1))
  row original selftest "$SRC" "$v"
  build "a1-$k" "$OUT/a1.om"; run "a1-$k"
  v=FAIL; [ "$crc" = 0 ] && [ "$rexit" = 0 ] && cmp -s "$OUT/a1-$k.stdout" "$EXPA" && v=PASS
  [ "$v" = PASS ] || fails=$((fails+1))
  row original oracle-a1 "$OUT/a1.om" "$v"
done
[ "$(sha256sum "$OUT/selftest-1.bin" | cut -d' ' -f1)" = "$(sha256sum "$OUT/selftest-3.bin" | cut -d' ' -f1)" ] || { note "nondeterministic compile"; fails=$((fails+1)); }

# 3. One case per process.
build cli "$OUT/cli.om"
v=FAIL
if [ "$crc" = 0 ]; then clirun cli; cmp -s "$OUT/cli.cli.out" "$EXPC" && v=PASS; fi
[ "$v" = PASS ] || fails=$((fails+1))
rexit=-; osha=-; [ -f "$OUT/cli.cli.out" ] && osha=$(sha256sum "$OUT/cli.cli.out" | cut -d' ' -f1)
row original oracle-cli "$OUT/cli.om" "$v"
nref=$(grep -c ' -$' "$EXPC"); nadm=$(grep -c ' Y ' "$EXPC")

# 4. Negative controls of the judges themselves.
sed '2s/ -4 / -5 /' "$EXPA" > "$OUT/expected-a1-corrupt.out"
if cmp -s "$OUT/a1-1.stdout" "$OUT/expected-a1-corrupt.out"; then v=FAIL; fails=$((fails+1)); else v=PASS; fi
crc=0; bsha=-; rexit=-; osha=$(sha256sum "$OUT/expected-a1-corrupt.out" | cut -d' ' -f1)
row comparator-corrupt-a1 oracle-a1 "$OUT/expected-a1-corrupt.out" "$v"
sed '2s/^1 4 -$/1 0 -/' "$EXPC" > "$OUT/expected-cli-corrupt.out"
if cmp -s "$OUT/cli.cli.out" "$OUT/expected-cli-corrupt.out"; then v=FAIL; fails=$((fails+1)); else v=PASS; fi
osha=$(sha256sum "$OUT/expected-cli-corrupt.out" | cut -d' ' -f1)
row comparator-corrupt-cli oracle-cli "$OUT/expected-cli-corrupt.out" "$v"
crc=$(cat "$OUT/cli.compile.status"); bsha=$(sha256sum "$OUT/cli.bin" | cut -d' ' -f1)
for a in none:99 46:96 x:97 12345:98; do
  arg=${a%%:*}; want=${a#*:}
  if [ "$arg" = none ]; then run cli; else run cli "$arg"; fi
  cp "$OUT/cli.stdout" "$OUT/cli-arg-$arg.stdout"
  v=FAIL; [ "$rexit" = "$want" ] && [ ! -s "$OUT/cli.stdout" ] && v=PASS
  [ "$v" = PASS ] || fails=$((fails+1))
  row "cli-arg-$arg" usage "$OUT/cli.om" "$v"
done

# 5+6. Mutants. mutate NAME LINE 'OLD' 'NEW' [LINE 'OLD' 'NEW' ...] on top of
#      SRC, applied in the order given (an insert shifts later lines).
#      NEW of "+STATEMENT" inserts that statement after LINE instead.
OFF='if eq ulong 1 ulong 0'
mutate() {
  m=$1; shift
  cp "$SRC" "$OUT/$m.om"
  while [ $# -ge 3 ]; do
    ln=$1; old=$2; new=$3; shift 3
    cur=$(sed -n "${ln}p" "$OUT/$m.om")
    [ "$cur" = "$old" ] || { note "mutant $m: line $ln is '$cur', wanted '$old'"; fails=$((fails+1)); return 1; }
    case $new in
      +*) sed "${ln}a\\
${new#+}" "$OUT/$m.om" > "$OUT/$m.tmp" ;;
      *) sed "${ln}s/.*/$new/" "$OUT/$m.om" > "$OUT/$m.tmp" ;;
    esac
    mv "$OUT/$m.tmp" "$OUT/$m.om"
  done
}
killed=0; mutants=0
mutcase() { # NAME: self-test, A1 oracle and CLI oracle for $OUT/NAME.om
  m=$1
  mutants=$((mutants+1))
  build "$m-selftest" "$OUT/$m.om"; run "$m-selftest"
  if [ "$crc" = 0 ] && [ "$rexit" = 0 ]; then st=SELFTEST_MISSED; else st=SELFTEST_CAUGHT; fi
  [ "$crc" = 0 ] || { st="MUTANT_INVALID_compile$crc"; fails=$((fails+1)); }
  row "$m" selftest "$OUT/$m.om" "$st"
  prefix "$OUT/$m.om" "$EMIT" "$OUT/$m-a1.om"
  build "$m-a1" "$OUT/$m-a1.om"; run "$m-a1"
  if [ "$crc" = 0 ] && [ "$rexit" = 0 ] && cmp -s "$OUT/$m-a1.stdout" "$EXPA"; then va=ORACLE_MISSED; fails=$((fails+1)); else va=ORACLE_KILLED; killed=$((killed+1)); fi
  [ "$crc" = 0 ] || { va="MUTANT_INVALID_compile$crc"; fails=$((fails+1)); }
  row "$m" oracle-a1 "$OUT/$m-a1.om" "$va"
  prefix "$OUT/$m.om" "$CLIT" "$OUT/$m-cli.om"
  build "$m-cli" "$OUT/$m-cli.om"
  vc="MUTANT_INVALID_compile$crc"
  if [ "$crc" = 0 ]; then
    clirun "$m-cli"
    if cmp -s "$OUT/$m-cli.cli.out" "$EXPC"; then vc=CLI_MISSED; else vc=CLI_KILLED; fi
  else fails=$((fails+1)); fi
  rexit=-; osha=-; [ -f "$OUT/$m-cli.cli.out" ] && osha=$(sha256sum "$OUT/$m-cli.cli.out" | cut -d' ' -f1)
  row "$m" oracle-cli "$OUT/$m-cli.om" "$vc"
  printf '%s %s %s %s\n' "$m" "$st" "$va" "$vc"
}
compref() { # NAME: must be refused by omc with error 7
  m=$1
  build "$m" "$OUT/$m.om"
  rexit=-; osha=-
  if [ "$crc" = 7 ]; then v=COMPILE_REFUSED_7; else v="NOT_REFUSED_rc$crc"; fails=$((fails+1)); fi
  row "$m" compile "$OUT/$m.om" "$v"
  printf '%s %s %s\n' "$m" "$v" "$(cat "$OUT/$m.compile.stderr")"
}
mutate g01-rank 221 'if or ne get Dsc 0 1 ne get Req 0 get Dsc 0' "$OFF" && mutcase g01-rank
mutate g02-shape 224 'if shapebad' "$OFF" && mutcase g02-shape
mutate g03-missing-base 227 'if or eq get Dsc 3 0 eq get Req 3 0' "$OFF" && mutcase g03-missing-base
mutate g04-wrong-base-req 230 'if ne get Req 3 get Dsc 3' "$OFF" && mutcase g04-wrong-base-req
mutate g05-wrong-base-content 233 'if ne bdigest get Dsc 3' "$OFF" && mutcase g05-wrong-base-content
mutate g06-generation 236 'if ne get Req 4 get Dsc 4' "$OFF" && mutcase g06-generation
mutate g07-perm-valid 240 'if permbad permat i' "$OFF" && mutcase g07-perm-valid
mutate g08-mode 245 'if gt md 1' "$OFF" && mutcase g08-mode
mutate g09-budget-zero 249 'if eq k 0' "$OFF" && mutcase g09-budget-zero
mutate g10-budget-ceiling 252 'if gt k KMAX' "$OFF" && mutcase g10-budget-ceiling
mutate g11-all-denied 260 'if ge id NCAND' "$OFF" && mutcase g11-all-denied
mutate g12-index 270 'if ge id NCAND' "$OFF" && mutcase g12-index
mutate g13-denied 273 'if denied permat id' "$OFF" && mutcase g13-denied
mutate g14-stale 276 'if ne get Cgen id get Dsc 4' "$OFF" && mutcase g14-stale
mutate g15-phase 280 'if and ne ph 1 ne ph -1' "$OFF" && mutcase g15-phase
mutate g16-duplicate 283 'if dupat j id' "$OFF" && mutcase g16-duplicate
mutate g17-range 287 'if rangebad k' "$OFF" && mutcase g17-range
mutate m18-compute-before-verdict 335 'compute get Req 5' 'note compute moved before the verdict' 331 'st = admit' '+compute get Req 5' && mutcase m18-compute-before-verdict
mutate m19-select-order 194 'if above s bsc' 'if above bsc s' && mutcase m19-select-order
mutate m20-coordinated 276 'if ne get Cgen id get Dsc 4' "$OFF" 538 'put Exp 13 -9' 'put Exp 13 0' 539 'put Exp 14 -9' 'put Exp 14 0' 570 'put Exp 45 -9' 'put Exp 45 0' 591 'if ne get Counts 0 14' 'if ne get Counts 0 17' 594 'if ne get Counts 1 28' 'if ne get Counts 1 34' && mutcase m20-coordinated
[ "$mutants" = 20 ] || { note "expected 20 mutants, ran $mutants"; fails=$((fails+1)); }
# Overflow backstop: with the range guard removed, case 41 (x2 = 2^62) must
# trap 1 (exit 101) in its own process, not print a wrapped response.
ovf=$(sed -n '42p' "$OUT/g17-range-cli.cli.out" 2>/dev/null)
if [ "$ovf" = "41 101 -" ]; then v=TRAP1; else v="NOT_TRAP1:$ovf"; fails=$((fails+1)); fi
crc=0; bsha=-; rexit=101; osha=-
row g17-range-case41 overflow-backstop "$OUT/g17-range-cli.om" "$v"
mutate x1-swap-denied 273 'if denied permat id' 'if denied scoreat id' && compref x1-swap-denied
mutate x2-swap-pick 188 's = scoreat id' 's = permat id' && compref x2-swap-pick
mutate x3-raw-perm 273 'if denied permat id' 'if denied get PermA id' && compref x3-raw-perm
mutate x4-swap-valid 240 'if permbad permat i' 'if permbad scoreat i' && compref x4-swap-valid
nx=$(grep -c "	compile	.*	COMPILE_REFUSED_7$" "$R")

note "omc $got"
note "selftest binary $(sha256sum "$OUT/selftest-1.bin" | cut -d' ' -f1) exit $(cat "$OUT/selftest-1.status")"
note "a1 binary $(sha256sum "$OUT/a1-1.bin" | cut -d' ' -f1) exit $(cat "$OUT/a1-1.status")"
note "cli binary $(sha256sum "$OUT/cli.bin" | cut -d' ' -f1) cases admitted=$nadm refused=$nref"
if [ "$fails" = 0 ]; then note "ADMITP0 PASS selftest+a1 x3 cli=$NCASE/$NCASE comparators=refuse usage=4/4 mutants_killed=$killed/$mutants overflow=trap1 swap_compile_refused=$nx/4"; exit 0; fi
note "ADMITP0 FAIL failures=$fails mutants_killed=$killed/$mutants swap_compile_refused=$nx/4"; exit 1
