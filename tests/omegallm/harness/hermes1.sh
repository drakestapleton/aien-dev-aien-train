#!/bin/sh
# hermes1.sh BASEURL WORKDIR QUERYFILE TOOLSETS TIMEOUT OUTPREFIX: one isolated Hermes oneshot.
# Hermes runs with an empty environment except HOME, PATH, TERM and HERMES_HOME=$HARNESS_HOME
# TOOLSETS "-" omits -t (Hermes defaults).
# (default ~/work/hive/ownmodel/harness/hh: a scratch data root, not a profile; no existing
# profile's config, skills, memories or plugins are read or written), --safe-mode (no user
# config, rules, memory, plugins, MCP), in WORKDIR, under timeout(1). Writes OUTPREFIX.out
# (stdout+stderr), OUTPREFIX.rc and OUTPREFIX.ms (wall time).
set -u
base=$1 wd=$2 q=$3 ts=$4 tmo=$5 op=$6
hh=${HARNESS_HOME:-$HOME/work/hive/ownmodel/harness/hh}
hermes=${HERMES_BIN:-$HOME/workspace/hermes-agent/.hermes/bin/hermes}
cores=${CORES:-6}
mkdir -p "$hh"
tsarg="-t $ts"
[ "$ts" = - ] && tsarg=
t0=$(date +%s%N)
(cd "$wd" && env -i HOME="$HOME" HERMES_HOME="$hh" PATH=/usr/bin:/bin TERM=dumb \
	timeout -k 5 "$tmo" taskset -c "$cores" nice -n 10 "$hermes" chat --query-file "$q" --oneshot -Q \
	--provider custom --base-url "$base" -m ollm --api-key x --ignore-user-config --ignore-rules \
	--safe-mode --max-turns "${MAXTURNS:-4}" $tsarg --in "$wd" </dev/null >"$op.out" 2>&1)
echo $? >"$op.rc"
t1=$(date +%s%N)
echo $(((t1 - t0) / 1000000)) >"$op.ms"
