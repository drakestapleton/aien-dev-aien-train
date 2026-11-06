#!/bin/sh
# verify-check.sh VERIFY TASKS SCRATCH: the verifier's own gate, no model or harness involved.
# For every task: setup, the check before any work must FAIL (the outcome is not already there),
# the @ref command is run in the work dir, then the check must PASS (SPLIT train/heldout) or FAIL
# (SPLIT control: deliberately wrong expectations). Then refusals: unknown id exit 3, malformed
# task files exit 2 (path with "..", absolute path, unterminated block, unknown expect kind).
# Prints one line per check and `GATE PASS n=N` or `GATE FAIL bad=M n=N` (exit 1).
set -u
v=$1 tf=$2 s=$3
rm -rf "$s"
mkdir -p "$s"
n=0 bad=0
ok() { n=$((n + 1)); echo "ok   $*"; }
no() { n=$((n + 1)); bad=$((bad + 1)); echo "BAD  $*"; }
for id in $("$v" list "$tf" | cut -d' ' -f1); do
	sp=$("$v" list "$tf" | awk -v i="$id" '$1 == i {print $3}')
	d=$s/w-$id
	mkdir -p "$d"
	"$v" setup "$tf" "$id" "$d" || no "$id setup rc $?"
	pre=$("$v" check "$tf" "$id" "$d")
	[ $? -eq 1 ] && ok "$id pre FAIL ($pre)" || no "$id pre not FAIL ($pre)"
	"$v" ref "$tf" "$id" "$s/$id.ref" || no "$id ref rc $?"
	(cd "$d" && sh "$s/$id.ref") >/dev/null 2>&1
	post=$("$v" check "$tf" "$id" "$d")
	rc=$?
	if [ "$sp" = control ]; then
		[ $rc -eq 1 ] && ok "$id control FAIL after ref ($post)" || no "$id control rc $rc ($post)"
	else
		[ $rc -eq 0 ] && ok "$id PASS after ref" || no "$id rc $rc after ref ($post)"
	fi
done
"$v" check "$tf" no-such-task "$s" >/dev/null; rc=$?
[ $rc -eq 3 ] && ok "unknown id exit 3" || no "unknown id exit $rc"
bad1() { # NAME CONTENT: a malformed one-task file must be refused with exit 2
	printf '%s' "$2" >"$s/bad-$1.txt"
	mkdir -p "$s/wb-$1"
	"$v" setup "$s/bad-$1.txt" x "$s/wb-$1" >/dev/null 2>&1; r1=$?
	"$v" check "$s/bad-$1.txt" x "$s/wb-$1" >/dev/null 2>&1; r2=$?
	[ $r1 -eq 2 ] && [ $r2 -eq 2 ] && ok "malformed $1 exit 2" || no "malformed $1 setup $r1 check $r2"
}
bad1 dotdot '@task x f train
@file ../escape.txt
x
@end
@expect exact ../escape.txt
x
@end
'
bad1 abspath '@task x f train
@file /tmp/escape.txt
x
@end
@expect exact /tmp/escape.txt
x
@end
'
bad1 noend '@task x f train
@file a.txt
x
@expect exact a.txt
x
'
bad1 kind '@task x f train
@file a.txt
x
@end
@expect fuzzy a.txt
x
@end
'
[ -e "$s/../escape.txt" ] && no "dotdot wrote outside" || ok "nothing written outside the work dir"
printf '@task y f train\n@prompt\nhi\n@end\n' >"$s/noexp.txt"
mkdir -p "$s/wn"
out=$("$v" check "$s/noexp.txt" y "$s/wn"); rc=$?
[ $rc -eq 1 ] && ok "no expectations FAIL ($out)" || no "no expectations rc $rc"
if [ $bad -eq 0 ]; then echo "GATE PASS n=$n"; exit 0; fi
echo "GATE FAIL bad=$bad n=$n"
exit 1
