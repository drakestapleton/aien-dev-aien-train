#!/bin/sh
# Run an ollm JOB.TXT (the UEFI job format, CONTRACT section 9) with a Linux ollm build, to give the
# reference the UEFI run's OUT.TXT is compared with.
# Usage: sh tests/omegallm/efi-ref.sh BIN JOB DIR
# Prints, per job, `> line` and the command's output (with a line feed added when it does not end in
# one), like OUT.TXT without its `OLLM efi`, `ID` (identity), `J` and `OLLM DONE` lines; stops at the
# first command that exits nonzero (as the UEFI app does) and then prints `rc=N`. As in eio.om main:
# empty lines and lines starting with # are skipped; a line of only spaces and tabs has no tokens, so
# it is echoed as `> line` and runs nothing (no output, no J line in OUT.TXT, not counted as a job).
# Env: CORE (taskset core, default 6). The job lines are trusted (shell-split).
set -u
[ $# -eq 3 ] || { echo "usage: efi-ref.sh BIN JOB DIR" >&2; exit 2; }
BIN=$1 JOB=$2 DIR=$3
CORE=${CORE:-6}
ws=$(printf ' \t')
o=$(mktemp)
trap 'rm -f "$o"' EXIT HUP INT TERM
tr -d '\r' < "$JOB" | while IFS= read -r line; do
  case "$line" in '' | '#'*) continue ;; esac
  printf '> %s\n' "$line"
  case "$line" in *[!"$ws"]*) ;; *) continue ;; esac
  args=$(printf '%s\n' "$line" | sed 's/\\OLLM\\/'"$(printf '%s' "$DIR/" | sed 's/[\/&]/\\&/g')"'/g')
  eval "set -- $args"
  taskset -c "$CORE" nice -n 19 "$BIN" "$@" > "$o"
  rc=$?
  cat "$o"
  [ ! -s "$o" ] || [ "$(tail -c 1 "$o" | od -An -tu1 | tr -d ' ')" = 10 ] || echo
  [ "$rc" = 0 ] || { echo "rc=$rc"; exit 1; }
done
