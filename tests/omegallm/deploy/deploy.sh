#!/bin/sh
# deploy.sh: thin POSIX sh driver for the DRA-125 staged deployment of `ollm serve`
# (docs/omegallm/DEPLOY.md). The checks are in Omega: mancheck.om (manifests, files, the running
# process) and osup.om (the supervisor). Host dependencies, recorded in every receipt: sha256sum,
# curl, ss, taskset, nice, git. Everything runs under `taskset -c $CORES nice -n 10` (CORES default 6).
#
#   deploy.sh build OUT                      ollm (tests/omegallm/build.sh), mancheck, osup with $OMC
#   deploy.sh stage DIR CKSRC TOKSRC OLLM NAME PORT
#                                            copy the files into the stage DIR (checkpoint.ck,
#                                            merges.tok, bin/ollm) and write model.manifest
#                                            (OLLM-MANIFEST-1) and deploy.manifest (OLLM-DEPLOY-1)
#   deploy.sh sums DIR                       fresh sha256sum lines (SUMS) for DIR, on stdout
#   deploy.sh gate DIR                       fresh SUMS, then `mancheck check`
#   deploy.sh live DIR PORT                  the process listening on 127.0.0.1:PORT against DIR:
#                                            its /health, /proc/PID/exe sha256 and command line
#   deploy.sh start ROOT PORT [OPTS...]      osup on ROOT/current (a symlink to a stage dir):
#                                            ROOT/current/bin/ollm serve PORT ROOT/current/checkpoint.ck
#                                            ROOT/current/merges.tok [OPTS...]; prints the osup pid
#   deploy.sh switch ROOT DIR PORT           gate DIR, point ROOT/current at it, SIGTERM the served
#                                            child so osup restarts it on DIR
#   deploy.sh stop ROOT PORT                 stop file, wait for osup, prove nothing is left, write
#                                            ROOT/STATE.PORT (UNAVAILABLE)
# Env: OMC (pinned omc, required for build/stage/gate/live/switch), BIN (dir with mancheck, osup;
# default $OUT of build), CORES (default 6), REPO (aien-train checkout, default this one).
set -u
here=$(cd "$(dirname "$0")" && pwd)
REPO=${REPO:-$(cd "$here/../../.." && pwd)}
CORES=${CORES:-6}
run() { taskset -c "$CORES" nice -n 10 "$@"; }
die() { echo "DEPLOY_FAIL $*" >&2; exit 1; }
now() { date -u +%FT%TZ; }
cmd=${1:-}
[ $# -ge 1 ] && shift

pid_on() { # the pid listening on 127.0.0.1:$1, or empty
	ss -Hltnp "sport = :$1" 2>/dev/null | grep -o 'pid=[0-9]*' | head -1 | cut -d= -f2
}
health_ok() { curl -s -m 2 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$1/health" 2>/dev/null | grep -q '^200$'; }

case "$cmd" in
build)
	OUT=${1:?OUT}
	: "${OMC:?}"
	mkdir -p "$OUT"
	OMC=$OMC OUT=$OUT CORE=$CORES sh "$REPO/tests/omegallm/build.sh" || die build ollm
	for u in mancheck osup; do
		run "$OMC" <"$here/$u.om" >"$OUT/$u.tmp" || { rm -f "$OUT/$u.tmp"; die "omc $u"; }
		chmod +x "$OUT/$u.tmp" && mv "$OUT/$u.tmp" "$OUT/$u"
		echo "BUILD_OK $(sha256sum "$OUT/$u" | cut -d' ' -f1) $OUT/$u source_sha256 $(sha256sum "$here/$u.om" | cut -d' ' -f1)"
	done
	;;
stage)
	[ $# -eq 6 ] || die "usage: stage DIR CKSRC TOKSRC OLLM NAME PORT"
	DIR=$1 CKSRC=$2 TOKSRC=$3 OLLM=$4 NAME=$5 PORT=$6
	: "${OMC:?}" "${BIN:?}"
	git -C "$REPO" diff --quiet HEAD -- native/omegallm tests/omegallm/build.sh || die "source tree differs from HEAD"
	commit=$(git -C "$REPO" rev-parse HEAD)
	[ -e "$DIR" ] && die "stage dir exists: $DIR"
	mkdir -p "$DIR/bin"
	cp "$CKSRC" "$DIR/checkpoint.ck" && cp "$TOKSRC" "$DIR/merges.tok" && cp "$OLLM" "$DIR/bin/ollm" || die copy
	chmod 444 "$DIR/checkpoint.ck" "$DIR/merges.tok"
	chmod 555 "$DIR/bin/ollm"
	ids=$(run "$BIN/mancheck" id "$DIR" checkpoint.ck merges.tok) || die "mancheck id: $ids"
	ck=$(sha256sum "$DIR/checkpoint.ck" | cut -d' ' -f1)
	tk=$(sha256sum "$DIR/merges.tok" | cut -d' ' -f1)
	sv=$(sha256sum "$DIR/bin/ollm" | cut -d' ' -f1)
	om=$(sha256sum "$OMC" | cut -d' ' -f1)
	cks=$(wc -c <"$DIR/checkpoint.ck")
	tks=$(wc -c <"$DIR/merges.tok")
	mag=$(head -c 8 "$DIR/checkpoint.ck")
	{
		echo "format OLLM-MANIFEST-1"
		echo "name $NAME"
		echo "owner aien-dev/aien-train"
		echo "source local"
		echo "checkpoint $mag $ck"
		echo "tokenizer OLLMTOK1 $tk"
		echo "serve $sv"
		echo "omc $om"
		echo "bytes $((cks + tks))"
		echo "files 2"
		echo "$ck $cks checkpoint.ck"
		echo "$tk $tks merges.tok"
	} >"$DIR/model.manifest"
	{
		echo "format OLLM-DEPLOY-1"
		echo "manifest $(sha256sum "$DIR/model.manifest" | cut -d' ' -f1)"
		echo "commit $commit"
		echo "$ids"
		echo "launch bin/ollm serve $PORT checkpoint.ck merges.tok"
	} >"$DIR/deploy.manifest"
	chmod 444 "$DIR/model.manifest" "$DIR/deploy.manifest"
	echo "STAGED $DIR model.manifest $(sha256sum "$DIR/model.manifest" | cut -d' ' -f1) deploy.manifest $(sha256sum "$DIR/deploy.manifest" | cut -d' ' -f1)"
	;;
sums)
	DIR=${1:?DIR}
	: "${OMC:?}"
	(cd "$DIR" && sha256sum model.manifest bin/ollm $(awk 'length($1) == 64 && NF == 3 {print $3}' model.manifest)) || exit 1
	echo "$(sha256sum "$OMC" | cut -d' ' -f1)  omc"
	;;
gate)
	DIR=${1:?DIR}
	: "${BIN:?}"
	t=$(mktemp "${TMPDIR:-/tmp}/deploy-sums.XXXXXX")
	sh "$0" sums "$DIR" >"$t" || { rm -f "$t"; die "sums $DIR"; }
	run "$BIN/mancheck" check "$DIR" "$t"
	rc=$?
	rm -f "$t"
	exit $rc
	;;
live)
	DIR=${1:?DIR} PORT=${2:?PORT}
	: "${BIN:?}"
	pid=$(pid_on "$PORT")
	[ -n "$pid" ] || die "nothing listens on :$PORT"
	t=$(mktemp -d "${TMPDIR:-/tmp}/deploy-live.XXXXXX")
	sh "$0" sums "$DIR" >"$t/sums" || die "sums $DIR"
	curl -s -m 10 "http://127.0.0.1:$PORT/health" >"$t/health" || die "no /health on :$PORT"
	{
		echo "exe $(sha256sum "/proc/$pid/exe" | cut -d' ' -f1)"
		echo "path $(readlink "/proc/$pid/exe")"
		echo "argv $(tr '\0' ' ' <"/proc/$pid/cmdline" | sed 's/ $//')"
	} >"$t/live"
	echo "LIVE pid=$pid exe=$(readlink "/proc/$pid/exe") listen=$(ss -Hltn "sport = :$PORT" | awk '{print $4}' | tr '\n' ' ')"
	echo "LIVE health $(cat "$t/health")"
	sed 's/^/LIVE /' "$t/live"
	run "$BIN/mancheck" live "$(readlink -f "$DIR")" "$t/sums" "$t/health" "$t/live"
	rc=$?
	rm -rf "$t"
	exit $rc
	;;
start)
	ROOT=${1:?ROOT} PORT=${2:?PORT}
	shift 2
	: "${BIN:?}"
	[ -L "$ROOT/current" ] || die "no $ROOT/current"
	[ -z "$(pid_on "$PORT")" ] || die ":$PORT is taken"
	rm -f "$ROOT/stop.$PORT"
	C=$ROOT/current
	# no shell function here: taskset and nice exec, so $! is the osup process itself
	taskset -c "$CORES" nice -n 10 "$BIN/osup" "$ROOT/stop.$PORT" "$ROOT/serve.$PORT.log" "$C/bin/ollm" serve "$PORT" \
		"$C/checkpoint.ck" "$C/merges.tok" "$@" >>"$ROOT/osup.$PORT.out" 2>&1 &
	sp=$!
	echo $sp >"$ROOT/osup.$PORT.pid"
	sleep 0.2
	[ "$(readlink "/proc/$sp/exe")" = "$(readlink -f "$BIN/osup")" ] || die "pid $sp is not osup"
	echo "STARTED osup=$sp exe=$(readlink "/proc/$sp/exe") port=$PORT at $(now)"
	;;
switch)
	ROOT=${1:?ROOT} DIR=${2:?DIR} PORT=${3:?PORT}
	sh "$0" gate "$DIR" || die "gate refused $DIR: not switching"
	ln -sfn "$DIR" "$ROOT/current.new" && mv -T "$ROOT/current.new" "$ROOT/current" || die "symlink"
	sp=$(cat "$ROOT/osup.$PORT.pid")
	c=$(pid_on "$PORT")
	[ -n "$c" ] || die "nothing listens on :$PORT"
	[ "$(awk '{print $4}' "/proc/$c/stat")" = "$sp" ] || die "listener $c is not a child of osup $sp"
	kill -TERM "$c"
	echo "SWITCHED current=$(readlink "$ROOT/current") old_child=$c at $(now)"
	;;
stop)
	ROOT=${1:?ROOT} PORT=${2:?PORT}
	sp=$(cat "$ROOT/osup.$PORT.pid")
	touch "$ROOT/stop.$PORT"
	i=0
	while kill -0 "$sp" 2>/dev/null; do
		i=$((i + 1))
		[ $i -gt 300 ] && die "osup $sp still running after 30 s"
		sleep 0.1
	done
	left=$(pgrep -f "$ROOT/current/bin/ollm serve $PORT" || true)
	lis=$(ss -Hltn "sport = :$PORT" | wc -l)
	code=$(curl -s -m 2 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/health" 2>/dev/null)
	crc=$?
	tail -1 "$ROOT/osup.$PORT.out"
	echo "STOPPED osup=$sp processes_left=[${left}] listeners=$lis health_http=$code curl_rc=$crc at $(now)"
	if [ -z "$left" ] && [ "$lis" = 0 ] && [ "$code" = 000 ]; then
		echo "UNAVAILABLE port $PORT: no ollm process, no listener, /health connection refused (curl rc $crc); stopped cleanly at $(now) by deploy.sh stop" >"$ROOT/STATE.$PORT"
		cat "$ROOT/STATE.$PORT"
	else
		echo "UNKNOWN port $PORT: stop left processes=[$left] listeners=$lis health=$code at $(now)" >"$ROOT/STATE.$PORT"
		exit 1
	fi
	;;
*)
	sed -n '2,25p' "$0" >&2
	exit 2
	;;
esac
