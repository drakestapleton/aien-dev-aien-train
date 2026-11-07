#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# DRA-146 three-arm personal eval harness (PREREG: ~/private/omegallm/dra146/eval/PREREG.md; public copy
# docs/personal/PREREG-dra146.md). Shell plumbing only; scoring and aggregation are native Omega (peval).
#   arm A: base checkpoint, prompt only
#   arm B: base checkpoint, memory block prepended (MEMCMD)
#   arm C: personalized checkpoint, same memory block
# Usage: sh tests/personal/harness.sh TASKS.jsonl OUTDIR
# Tasks: the peval split schema, which also reads the dra146 eval_tasks.jsonl builder's fields (scorer.type
#   regex: must / must_not; compile_run: expect_stdout, expect_exit). Regexes: peval rx subset (Python re subset
#   with groups, alternation, classes, quantifiers incl. {m,n}, \b, ^ $, leading (?i), literal (?!...)); an
#   unsupported construct is refused (exit 22) and the row counts as failed with reason rx (see detail.txt).
# Env (required): PEVAL (built peval), OLLM (sampler binary, `ollm sample` CLI), CKA (base ck), MERGES
# Env (optional): CKC (personalized ck; arm C is NOT_RUN without it), ARMS (default "A B C"), SEEDS (default
#   "0" = greedy; any other seed samples at TEMP), TEMP (milli, default 700 for seeds != 0), NTOK (default 96),
#   MEMCMD (command; gets the memory query text as its last argument and prints the block; default: cat the
#   synthetic fixture), MEMMAX (bytes, default 600; a longer block is cut at a line boundary), OMC (pinned omc
#   for omc_stdout tasks; without it those tasks fail with reason omc_unset), LEAKIDX (peval shingle index of
#   the private TRAIN text; without it the copy detector is NOT_RUN and only patterns count),
#   SAMPLER (overrides the sampler: a command run as `$SAMPLER CK SEED NTOK TEMP PROMPTFILE`, printing the answer)
# Prompt format (V 4096 merges4096, encoded by the sampler):
#   [arms B, C]  "Memory:\n" BLOCK "\n"
#   "Task: " PROMPT "\nAnswer:\n"
# The model's answer ends at token 0 (after "\nDone.\n" in the trained format). Rows go to OUTDIR/results.tsv:
#   arm category id seed pass leak tokens ns, and OUTDIR/summary.txt is `peval agg` of it. detail.txt has the
#   reason: rx, omc1 (compile refused), omc2 (program exit != 0 or timeout), omc3 (OMC unset), omc4 (stdout differs),
#   samplerN; omc2 means the exit status differs from omcexit (default 0). Generated programs run in bwrap --unshare-all (no network, no files) with a 5 s timeout.
set -u
TASKS=${1:?TASKS.jsonl}; OUT=${2:?OUTDIR}
HERE=$(cd "$(dirname "$0")" && pwd)
PEVAL=${PEVAL:?}; CKA=${CKA:?}; MERGES=${MERGES:?}
ARMS=${ARMS:-A B C}; SEEDS=${SEEDS:-0}; NTOK=${NTOK:-96}; TEMP=${TEMP:-700}; MEMMAX=${MEMMAX:-600}
MEMCMD=${MEMCMD:-cat $HERE/fixtures/memory-synthetic.txt #}
mkdir -p "$OUT/tasks" "$OUT/rows"
"$PEVAL" split "$TASKS" "$OUT/tasks" > "$OUT/split.txt" || { echo "HARNESS split failed rc $?"; exit 2; }
n=$(cut -d' ' -f2 "$OUT/split.txt")
: > "$OUT/results.tsv"
{ echo "tasks_sha256 $(sha256sum "$TASKS" | cut -d' ' -f1) n $n"
  echo "peval_sha256 $(sha256sum "$PEVAL" | cut -d' ' -f1)"
  echo "cka_sha256 $(sha256sum "$CKA" | cut -d' ' -f1)"
  [ -n "${CKC:-}" ] && echo "ckc_sha256 $(sha256sum "$CKC" | cut -d' ' -f1)"
  [ -n "${OLLM:-}" ] && echo "ollm_sha256 $(sha256sum "$OLLM" | cut -d' ' -f1)"
  [ -n "${OMC:-}" ] && echo "omc_sha256 $(sha256sum "$OMC" | cut -d' ' -f1)"
  [ -n "${LEAKIDX:-}" ] && echo "leakidx_sha256 $(sha256sum "$LEAKIDX" | cut -d' ' -f1)"
  echo "arms $ARMS seeds $SEEDS ntok $NTOK temp $TEMP memmax $MEMMAX"; } > "$OUT/identity.txt"
sample() { # ck seed promptfile -> stdout answer
  t=0; [ "$2" = 0 ] || t=$TEMP
  if [ -n "${SAMPLER:-}" ]; then $SAMPLER "$1" "$2" "$NTOK" "$t" "$3"
  else "$OLLM" sample "$1" "$2" "$NTOK" "$t" "$(cat "$3")" "$MERGES"; fi
}
memblock() { # query text -> block of at most MEMMAX bytes, cut at a line boundary
  $MEMCMD "$1" 2> /dev/null | head -c "$MEMMAX" > "$OUT/mem.tmp"
  if [ "$(wc -c < "$OUT/mem.tmp")" -ge "$MEMMAX" ]; then
    awk -v m="$MEMMAX" '{ s += length($0) + 1; if (s <= m) print }' "$OUT/mem.tmp"
  else cat "$OUT/mem.tmp"; fi
}
omccheck() { # answerfile expectedstdout expectedexit -> 0 pass (locals prefixed oc_)
  [ -n "${OMC:-}" ] || return 3
  oc_d=$(mktemp -d "${TMPDIR:-/tmp}/omcck.XXXXXX")
  awk '/^Done\.$/ { exit } { print }' "$1" > "$oc_d/p.om"
  timeout 20 "$OMC" < "$oc_d/p.om" > "$oc_d/p" 2> /dev/null || { rm -rf "$oc_d"; return 1; }
  chmod +x "$oc_d/p"
  timeout 5 bwrap --unshare-all --die-with-parent --new-session --ro-bind "$oc_d/p" /p /p > "$oc_d/out" 2> /dev/null
  oc_r=$?
  cmp -s "$oc_d/out" "$2" && [ $oc_r -eq "$3" ]; oc_v=$?
  rm -rf "$oc_d"; [ $oc_v -eq 0 ] && return 0; [ $oc_r -ne "$3" ] && return 2; return 4
}
for arm in $ARMS; do
  ck=$CKA; [ "$arm" = C ] && ck=${CKC:-}
  i=1
  while [ $i -le "$n" ]; do
    f=$(printf '%s/tasks/%04d' "$OUT" $i)
    id=$(sed -n 's/^id //p' "$f.rules" | head -n 1); cat=$(sed -n 's/^cat //p' "$f.rules" | head -n 1)
    for seed in $SEEDS; do
      r=$(printf '%s/rows/%s-%04d-%s' "$OUT" "$arm" $i "$seed")
      if [ -z "$ck" ]; then echo "$arm $id NOT_RUN no personalized checkpoint" >> "$OUT/notrun.txt"; continue; fi
      : > "$r.prompt"
      if [ "$arm" != A ]; then
        q=$f.prompt; [ -f "$f.mq" ] && q=$f.mq
        { printf 'Memory:\n'; memblock "$(cat "$q")"; printf '\n'; } >> "$r.prompt"
      fi
      { printf 'Task: '; cat "$f.prompt"; printf '\nAnswer:\n'; } >> "$r.prompt"
      t0=$(date +%s%N)
      sample "$ck" "$seed" "$r.prompt" > "$r.answer" 2> "$r.err"
      sr=$?
      t1=$(date +%s%N)
      ntk=0
      if [ -s "$r.answer" ] && [ -n "${OLLM:-}" ]; then
        "$OLLM" bpeenc "$MERGES" 4096 "$r.answer" "$r.tok" > /dev/null 2>&1 && ntk=$(( $(wc -c < "$r.tok") / 2 ))
      fi
      pass=0; why=ok
      "$PEVAL" rx "$f.rules" "$r.answer" > "$r.rx"
      grep -q '^RX pass' "$r.rx" && pass=1 || why=rx
      if [ -f "$f.omcout" ]; then ox=$(sed -n 's/^omcexit //p' "$f.rules" | head -n 1); omccheck "$r.answer" "$f.omcout" "${ox:-0}"; oc=$?; [ $oc -eq 0 ] || { pass=0; why=omc$oc; }; fi
      [ $sr -eq 0 ] || { pass=0; why=sampler$sr; }
      leak=0
      if [ -n "${LEAKIDX:-}" ]; then "$PEVAL" leak "$LEAKIDX" "$r.answer" "$r.prompt" > "$r.leak"
      else "$PEVAL" leak /dev/null "$r.answer" "$r.prompt" > "$r.leak"; fi
      set -- $(cat "$r.leak"); [ "$2" -gt 0 ] || [ "$4" -gt 0 ] || [ "$5" -gt 0 ] || [ "$6" -gt 0 ] && leak=1
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$arm" "$cat" "$id" "$seed" $pass $leak $ntk $((t1 - t0)) >> "$OUT/results.tsv"
      echo "$arm $id $seed pass=$pass why=$why leak=$leak $(cat "$r.rx") $(cat "$r.leak")" >> "$OUT/detail.txt"
    done
    i=$((i + 1))
  done
done
"$PEVAL" agg "$OUT/results.tsv" > "$OUT/summary.txt"; echo "AGG rc $?" >> "$OUT/identity.txt"
cat "$OUT/summary.txt"
