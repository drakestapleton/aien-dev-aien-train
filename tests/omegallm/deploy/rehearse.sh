#!/bin/sh
# rehearse.sh: the DRA-125 candidate-endpoint rehearsal (docs/omegallm/DEPLOY.md section 3), end to
# end, with receipts. Never touches :18091 (it only reads `ss` for it). Ports: 18296 candidate,
# 18297 test=1 fixture (scripted tool-call output for serve-check), 18298 mutant-id server.
#   OMC=<pinned omc> WORK=<scratch dir> CKA=<candidate CK03> CKR=<rollback CK03> CKR_SHA=<its
#   recorded sha256> TOK=<OLLMTOK1> sh tests/omegallm/deploy/rehearse.sh
# Receipts go to $EV (default evidence/OMEGALLM/deploy/rehearsal): one file per step (command,
# output, rc) and summary.txt with `PASS name` / `FAIL name` lines and `REHEARSAL pass=N fail=M`.
# Exit 0 only when every step returned the rc it must (0 for a gate, 1 for a negative control).
set -u
here=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$here/../../.." && pwd)
: "${OMC:?}" "${WORK:?}" "${CKA:?}" "${CKR:?}" "${CKR_SHA:?}" "${TOK:?}"
CORES=${CORES:-6}
EV=${EV:-$REPO/evidence/OMEGALLM/deploy/rehearsal}
D="sh $here/deploy.sh"
B=$WORK/build
export OMC CORES BIN=$B REPO
mkdir -p "$EV" "$WORK"
: >"$EV/summary.txt"
pass=0 fail=0
now() { date -u +%FT%TZ; }
# step NAME WANT CMD...: run CMD, receipt $EV/NAME.txt, PASS when rc == WANT (and, for WANT 1, the
# refusal is a MANCHECK FAIL / DEPLOY_FAIL line, not a crash)
step() {
	n=$1 w=$2
	shift 2
	{
		echo "# $(now) $n want_rc=$w"
		echo "\$ $*"
	} >"$EV/$n.txt"
	"$@" >>"$EV/$n.txt" 2>&1
	rc=$?
	echo "rc $rc" >>"$EV/$n.txt"
	ok=0
	[ $rc -eq "$w" ] && ok=1
	if [ "$w" = 1 ] && ! grep -q "MANCHECK FAIL\|DEPLOY_FAIL" "$EV/$n.txt"; then ok=0; fi
	if [ $ok = 1 ]; then pass=$((pass + 1)); echo "PASS $n rc=$rc $(grep -h 'MANCHECK' "$EV/$n.txt" | tail -1)" >>"$EV/summary.txt"
	else fail=$((fail + 1)); echo "FAIL $n rc=$rc want=$w" >>"$EV/summary.txt"; fi
	tail -1 "$EV/summary.txt"
}
waith() { # wait up to 120 s for /health 200 on port $1; prints seconds waited (MEASURED, date resolution ms)
	t0=$(date +%s%N)
	i=0
	until [ "$(curl -s -m 2 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$1/health")" = 200 ]; do
		i=$((i + 1))
		[ $i -gt 1200 ] && { echo "HEALTH_TIMEOUT $1"; return 1; }
		sleep 0.1
	done
	echo "health_up_ms $((($(date +%s%N) - t0) / 1000000))"
}
model_of() { curl -s -m 5 "http://127.0.0.1:$1/health" | sed 's/.*"model"://; s/}$//'; }
ppid_of() { awk '{print $4}' "/proc/$1/stat"; }
chk_restart() { echo "before $1 after $2 parent $(ppid_of "$2") osup $3"; [ -n "$2" ] && [ "$1" != "$2" ] && [ "$(ppid_of "$2")" = "$3" ]; }
p91() { echo "ss :18091 at $(now): [$(ss -Hltnp 'sport = :18091' | tr '\n' ' ')]"; }

{
	echo "date $(now)"
	echo "host $(hostname) $(uname -m)"
	echo "commit $(git -C "$REPO" rev-parse HEAD) dirty=$(git -C "$REPO" status --porcelain -- native tests | wc -l)"
	echo "omc $(sha256sum "$OMC")"
	echo "cores $CORES"
	echo "aien-supervise: ~/.config/aien-supervise $( [ -d "$HOME/.config/aien-supervise" ] && echo present || echo absent); user processes: [$(pgrep -u "$(id -u)" -fa aien-supervise | tr '\n' ' ')]"
	echo "host deps: $(command -v sha256sum curl ss taskset nice git python3 | tr '\n' ' ')"
	p91
} >"$EV/env.txt"

# ---- build and stage ----
step build 0 $D build "$B"
step build_mutant_id 0 env OMC="$OMC" OUT="$B" CORE="$CORES" sh "$REPO/tests/omegallm/build.sh" --mutant id
step rollback_ck_recorded_sha 0 sh -c "echo '$CKR_SHA  $CKR' | sha256sum -c"
rm -rf "$WORK/stage" "$WORK/root" "$WORK/root-t" "$WORK/root-m" "$WORK/neg"
mkdir -p "$WORK/stage" "$WORK/root" "$WORK/root-t" "$WORK/root-m" "$WORK/neg"
A=$WORK/stage/A R=$WORK/stage/R
sa=$(od -A n -t u8 -j 72 -N 8 "$CKA" | tr -d ' ')
sr=$(od -A n -t u8 -j 72 -N 8 "$CKR" | tr -d ' ')
step stage_A 0 $D stage "$A" "$CKA" "$TOK" "$B/ollm" "ollm-s2-step$sa" 18296
if ! grep -q "^rc 0" "$EV/stage_A.txt"; then # the trainer may have rewritten CKA during the copy
	rm -rf "$A"
	step stage_A_retry 0 $D stage "$A" "$CKA" "$TOK" "$B/ollm" "ollm-s2-step$sa" 18296
fi
step stage_R 0 $D stage "$R" "$CKR" "$TOK" "$B/ollm" "ollm-s2-step$sr" 18296
cp "$A/model.manifest" "$EV/A.model.manifest"; cp "$A/deploy.manifest" "$EV/A.deploy.manifest"
cp "$R/model.manifest" "$EV/R.model.manifest"; cp "$R/deploy.manifest" "$EV/R.deploy.manifest"
step gate_A 0 $D gate "$A"
step gate_R 0 $D gate "$R"

# ---- static negative controls: each must be refused (rc 1, a MANCHECK FAIL line) ----
mkneg() { # mkneg NAME: a dir of hard links to A's files and copies of its manifests
	N=$WORK/neg/$1
	mkdir -p "$N/bin"
	ln "$A/checkpoint.ck" "$N/checkpoint.ck"; ln "$A/merges.tok" "$N/merges.tok"; ln "$A/bin/ollm" "$N/bin/ollm"
	cp "$A/model.manifest" "$A/deploy.manifest" "$N/"; chmod 644 "$N/model.manifest" "$N/deploy.manifest"
}
cka=$(sha256sum "$A/checkpoint.ck" | cut -d' ' -f1)
ckr=$(sha256sum "$R/checkpoint.ck" | cut -d' ' -f1)
flip() { c=$(echo "$1" | cut -c1); [ "$c" = 0 ] && r=1 || r=0; echo "$r$(echo "$1" | cut -c2-)"; } # first hex digit changed
fa=$(flip "$cka")
mkneg sha; sed -i "s/$cka/$fa/g" "$WORK/neg/sha/model.manifest"
step neg_wrong_ck_sha 1 $D gate "$WORK/neg/sha"
mkneg shakey; sed -i "s/^checkpoint OLLMCK03 $cka/checkpoint OLLMCK03 $fa/" "$WORK/neg/shakey/model.manifest"
step neg_ck_sha_not_a_file_line 1 $D gate "$WORK/neg/shakey"
mkneg swap; rm "$WORK/neg/swap/checkpoint.ck"; ln "$R/checkpoint.ck" "$WORK/neg/swap/checkpoint.ck"
step neg_swapped_checkpoint 1 $D gate "$WORK/neg/swap"
# swapped checkpoint with model.manifest rewritten to match it (same size): deploy.manifest still
# names A's identity, so only the recomputed header/FNV comparison can refuse it
mkneg swap2; rm "$WORK/neg/swap2/checkpoint.ck"; ln "$R/checkpoint.ck" "$WORK/neg/swap2/checkpoint.ck"
sed -i "s/$cka/$ckr/g" "$WORK/neg/swap2/model.manifest"
sed -i "s/^manifest .*/manifest $(sha256sum "$WORK/neg/swap2/model.manifest" | cut -d' ' -f1)/" "$WORK/neg/swap2/deploy.manifest"
step neg_swapped_checkpoint_rewritten_manifest 1 $D gate "$WORK/neg/swap2"
mkneg dfnv
awk '/^ck /{v=$NF; d=substr(v,1,1); n=(d=="0")?"1":"0"; $NF=n substr(v,2)} {print}' "$A/deploy.manifest" >"$WORK/neg/dfnv/deploy.manifest"
sed -i "s/^manifest .*/manifest $(sha256sum "$WORK/neg/dfnv/model.manifest" | cut -d' ' -f1)/" "$WORK/neg/dfnv/deploy.manifest"
step neg_deploy_ck_fnv 1 $D gate "$WORK/neg/dfnv"
mkneg qwen; sed -i 's/^name .*/name qwen3.6-35b/' "$WORK/neg/qwen/model.manifest"
step neg_forbidden_name 1 $D gate "$WORK/neg/qwen"
mkneg url; echo "url local" >>"$WORK/neg/url/model.manifest"
step neg_url_line 1 $D gate "$WORK/neg/url"
mkneg pend; SI=${SI_MANIFEST:-$HOME/work/hive/t_80844d23/sovereign-intelligence/installer/share/model.manifest}
if [ -r "$SI" ]; then
	cp "$SI" "$WORK/neg/pend/model.manifest"
	step neg_si_pending_manifest 1 $D gate "$WORK/neg/pend"
fi
mkneg dup; sed -i 's/^files 2$/files 2\nfiles 2/' "$WORK/neg/dup/model.manifest"
step neg_duplicate_key 1 $D gate "$WORK/neg/dup"
mkneg serve; rm "$WORK/neg/serve/bin/ollm"; cp "$B/ollm-mut-id" "$WORK/neg/serve/bin/ollm"
step neg_other_serve_binary 1 $D gate "$WORK/neg/serve"
# a checkpoint with one payload byte changed (a copy), its manifests rewritten to its sha256: the
# recomputed FNV-1a differs from the header (mancheck) and serve refuses to load it (exit 14)
N=$WORK/neg/payload
mkdir -p "$N/bin"; cp "$A/checkpoint.ck" "$N/checkpoint.ck"; chmod 644 "$N/checkpoint.ck"
ln "$A/merges.tok" "$N/merges.tok"; ln "$A/bin/ollm" "$N/bin/ollm"
printf '\377' | dd of="$N/checkpoint.ck" bs=1 seek=1000000 conv=notrunc status=none
ckp=$(sha256sum "$N/checkpoint.ck" | cut -d' ' -f1)
sed "s/$cka/$ckp/g" "$A/model.manifest" >"$N/model.manifest"
sed "s/^manifest .*/manifest $(sha256sum "$N/model.manifest" | cut -d' ' -f1)/" "$A/deploy.manifest" >"$N/deploy.manifest"
step neg_payload_byte 1 $D gate "$N"
step neg_payload_byte_id 1 taskset -c "$CORES" nice -n 10 "$B/mancheck" id "$N" checkpoint.ck merges.tok
step neg_payload_byte_serve_exit14 14 timeout 300 taskset -c "$CORES" nice -n 10 "$B/ollm" serve 18298 "$N/checkpoint.ck" "$N/merges.tok"
rm -f "$N/checkpoint.ck"
N=$WORK/neg/tok
mkneg tok; rm "$N/merges.tok"; cp "$A/merges.tok" "$N/merges.tok"; chmod 644 "$N/merges.tok"
printf 'Z' | dd of="$N/merges.tok" bs=1 seek=40 conv=notrunc status=none
tkp=$(sha256sum "$N/merges.tok" | cut -d' ' -f1); tka=$(sha256sum "$A/merges.tok" | cut -d' ' -f1)
sed -i "s/$tka/$tkp/g" "$N/model.manifest"
sed -i "s/^manifest .*/manifest $(sha256sum "$N/model.manifest" | cut -d' ' -f1)/" "$N/deploy.manifest"
step neg_tokenizer_byte 1 $D gate "$N"

# ---- live: the candidate on 18296 under osup ----
ln -sfn "$A" "$WORK/root/current"
step start_A 0 $D start "$WORK/root" 18296
step health_A 0 waith 18296
step live_A 0 $D live "$A" 18296
step neg_live_A_vs_R_manifest 1 $D live "$R" 18296
mkneg same
step neg_live_same_files_other_dir 1 $D live "$WORK/neg/same" 18296
IDA=$(model_of 18296)
echo "$IDA" >"$EV/identity_A.json"
# explicit cancellation on the candidate itself (no test mode): a streaming client that leaves
# after 3 s; the server must log status 499 finish 4 and return to idle
step cancel_client_leaves 28 curl -s -N -m 3 -o "$EV/cancel_stream_head.txt" -H 'Content-Type: application/json' \
	-d '{"messages":[{"role":"user","content":"Write a long story about a lighthouse."}],"stream":true,"max_tokens":900,"temperature":0.8,"seed":3}' \
	http://127.0.0.1:18296/v1/chat/completions
sleep 2
step cancel_logged_499 0 sh -c "grep '^C 499 ' '$WORK/root/serve.18296.log' && curl -s http://127.0.0.1:18296/health | grep -q '\"in_flight\":0,\"queued\":0'"
# the test fixture (scripted output) for serve-check's tool-call and timing checks
ln -sfn "$A" "$WORK/root-t/current"
step start_T 0 $D start "$WORK/root-t" 18297 tplmax=4000 test=1
step health_T 0 waith 18297
step serve_check 0 env SERVE_TLOG="$WORK/root-t/serve.18297.log" SERVE_IDENTITY="$IDA" \
	taskset -c "$CORES" nice -n 10 python3 "$REPO/tests/omegallm/serve-check.py" 18296 "$B/ollm" "$A/checkpoint.ck" "$A/merges.tok" 18297 \
	"${ALLEN:-/opt/allen-chat/system-prompt.txt}"
step serve_check_summary 0 grep -q "^SUMMARY pass=[0-9]* fail=0$" "$EV/serve_check.txt"

# ---- kill -9: osup restarts the server; same identity ----
p1=$(ss -Hltnp 'sport = :18296' | grep -o 'pid=[0-9]*' | head -1 | cut -d= -f2)
step kill9 0 kill -9 "$p1"
step health_after_kill9 0 waith 18296
p2=$(ss -Hltnp 'sport = :18296' | grep -o 'pid=[0-9]*' | head -1 | cut -d= -f2)
step new_pid_after_kill9 0 chk_restart "$p1" "$p2" "$(cat "$WORK/root/osup.18296.pid")"
step live_A_after_kill9 0 $D live "$A" 18296
step identity_same_after_kill9 0 sh -c "[ '$(model_of 18296)' = '$IDA' ] && echo same: $IDA"

# ---- rollback to R and back to A, identity proof each time ----
step switch_to_R 0 $D switch "$WORK/root" "$R" 18296
sleep 1
step health_R 0 waith 18296
step live_R 0 $D live "$R" 18296
step neg_live_R_vs_A_manifest 1 $D live "$A" 18296
model_of 18296 >"$EV/identity_R.json"
step identity_R_differs 0 sh -c "[ '$(model_of 18296)' != '$IDA' ] && echo differs"
step switch_back_to_A 0 $D switch "$WORK/root" "$A" 18296
sleep 1
step health_A_back 0 waith 18296
step live_A_back 0 $D live "$A" 18296
step identity_A_back 0 sh -c "[ '$(model_of 18296)' = '$IDA' ] && echo same"
# a switch to a stage that fails its gate must not happen
step neg_switch_refused 1 $D switch "$WORK/root" "$WORK/neg/swap" 18296
step still_A_after_refused_switch 0 $D live "$A" 18296

# ---- mutant id: a server that misreports its checkpoint FNV is refused by the live check ----
M=$WORK/stage/M
mkdir -p "$M/bin"; ln "$A/checkpoint.ck" "$M/checkpoint.ck"; ln "$A/merges.tok" "$M/merges.tok"; cp "$B/ollm-mut-id" "$M/bin/ollm"
ln -sfn "$M" "$WORK/root-m/current"
step start_M 0 $D start "$WORK/root-m" 18298
step health_M 0 waith 18298
step neg_live_mutant_id 1 $D live "$A" 18298

# ---- clean shutdown: nothing left, a truthful unavailable state ----
step stop_M 0 $D stop "$WORK/root-m" 18298
step stop_T 0 $D stop "$WORK/root-t" 18297
step stop_A 0 $D stop "$WORK/root" 18296
for r in root root-t root-m; do cp "$WORK/$r/"osup.*.out "$EV/$r.osup.out" 2>/dev/null; cp "$WORK/$r/"STATE.* "$EV/" 2>/dev/null; done
grep -v '^PORT' "$WORK/root/serve.18296.log" | tail -40 >"$EV/serve.18296.log.tail"
# only this rehearsal's processes and ports (18295 and 18299 may belong to other lanes)
left_check() {
	ps -eo pid,args | grep -v grep | grep -E "$WORK/(root|stage|build)"
	ss -Hltnp | grep -E ':1829[678] '
	[ -z "$(ps -eo args | grep -v grep | grep -E "$WORK/(root|stage|build)")" ] && [ -z "$(ss -Hltn | grep -E ':1829[678] ')" ] && echo "clean: no process under $WORK, no listener on 18296-18298"
}
step nothing_left 0 left_check
p91 >>"$EV/env.txt"
echo "REHEARSAL pass=$pass fail=$fail at $(now)" | tee -a "$EV/summary.txt"
[ $fail -eq 0 ]
