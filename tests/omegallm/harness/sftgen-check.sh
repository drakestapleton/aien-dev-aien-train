#!/bin/sh
# sftgen-check.sh SFTGEN VERIFY CAPTURE SCRATCH [N]: the SFT generator's gate (no model involved).
# CAPTURE is a real Hermes `-t terminal` request body (evidence/OMEGALLM/harness/captures/
# hermes-terminal-chat1.json). Checks, on N conversations (default 200) of seed 11:
#  determinism (same seed same bytes, another seed different bytes); every line is JSON with the
#  Hermes message shape (system, user, then assistant tool_calls + tool pairs, final assistant);
#  tools equal to the captured array byte for byte (jq -c); the system prompt equals the captured
#  one with only home, HERMES_HOME, working directory and date replaced; every date is what GNU
#  date prints for America/Chicago; only TRAIN families appear; and a real replay: each
#  conversation's world (TASKS.md format) is set up by verify, every tool call's command is run
#  with bash in that directory, its stdout+stderr (final newlines stripped) and exit status must
#  give exactly the simulated tool message content, and the claimed outcome must PASS verify.
# Prints one line per failing item, counts, and `GATE PASS ...` or `GATE FAIL ...` (exit 1).
set -u
g=$1 v=$2 cap=$3 s=$4 n=${5:-200}
rm -rf "$s"
mkdir -p "$s"
bad=0 checks=0
ok() { checks=$((checks + 1)); echo "ok   $*"; }
no() { checks=$((checks + 1)); bad=$((bad + 1)); echo "BAD  $*"; }
"$g" 11 "$n" "$s/a.jsonl" "$s/a.world"; r1=$?
"$g" 11 "$n" "$s/b.jsonl" "$s/b.world"; r2=$?
"$g" 12 "$n" "$s/c.jsonl"; r3=$?
[ $r1 -eq 0 ] && [ $r2 -eq 0 ] && [ $r3 -eq 0 ] && ok "sftgen rc 0 x3" || no "sftgen rc $r1 $r2 $r3"
cmp -s "$s/a.jsonl" "$s/b.jsonl" && cmp -s "$s/a.world" "$s/b.world" && ok "seed 11 twice: identical bytes" || no "seed 11 not deterministic"
cmp -s "$s/a.jsonl" "$s/c.jsonl" && no "seed 12 equals seed 11" || ok "seed 12 differs"
lines=$(wc -l <"$s/a.jsonl")
[ "$lines" -eq "$n" ] && ok "$lines lines" || no "lines $lines want $n"
# shape: one result per line, "ok" or the reason
jq -r '. as $r | ($r.messages) as $m | ($m|length) as $L |
  if $L < 5 or ($L % 2) != 1 then "bad length"
  elif $m[0].role != "system" or $m[1].role != "user" then "bad head"
  elif $m[-1].role != "assistant" or ($m[-1]|has("tool_calls")) or ($m[-1].content|length) == 0 then "bad final"
  elif ([range(2; $L - 1; 2) | . as $j | ($m[$j].role == "assistant" and $m[$j].content == "" and
      ($m[$j].tool_calls|length) == 1 and $m[$j].tool_calls[0].type == "function" and
      $m[$j].tool_calls[0].function.name == "terminal" and
      ($m[$j].tool_calls[0].function.arguments|fromjson|keys) == ["command"] and
      $m[$j+1].role == "tool" and $m[$j+1].tool_call_id == $m[$j].tool_calls[0].id)] | all | not) then "bad tool pairs"
  else "ok" end' "$s/a.jsonl" >"$s/shape.txt" 2>"$s/shape.err" || no "jq shape failed: $(head -c 200 "$s/shape.err")"
nb=$(grep -vc '^ok$' "$s/shape.txt")
[ "$nb" -eq 0 ] && [ "$(wc -l <"$s/shape.txt")" -eq "$n" ] && ok "message shape x$n" || no "shape: $nb bad ($(grep -v '^ok$' "$s/shape.txt" | sort | uniq -c | head -3))"
jq -c .tools "$cap" >"$s/cap.tools"
jq -c .tools "$s/a.jsonl" | sort -u >"$s/gen.tools"
cmp -s "$s/cap.tools" "$s/gen.tools" && ok "tools == captured tools (one distinct array)" || no "tools differ from the capture"
# system prompt: the capture's text with its 4 machine values replaced by each line's values
jq -nr '
  def val($k): capture($k + ": (?<v>[^\n]*)").v;
  def vals: { home: val("User home directory"), cwd: val("Current working directory"),
    date: val("Conversation started"),
    hh: (capture("live under (?<v>[^ ]*)/profiles/<name>/").v) };
  def tpl($c): (.messages[0].content) as $t | ($t|vals) as $o |
    $t | split($o.hh) | join("\u0001H") | split($o.cwd) | join("\u0001C") | split($o.home) | join("\u0001O")
       | split($o.date) | join("\u0001D");
  def fill($t; $o): $t | split("\u0001H") | join($o.hh) | split("\u0001C") | join($o.cwd)
       | split("\u0001O") | join($o.home) | split("\u0001D") | join($o.date);
  (input | tpl(0)) as $T | inputs | (.messages[0].content) as $g | ($g|vals) as $o |
  if fill($T; $o) == $g then "ok" else "differs" end' "$cap" "$s/a.jsonl" >"$s/sys.txt" 2>"$s/sys.err" || no "jq sys failed: $(head -c 200 "$s/sys.err")"
nb=$(grep -vc '^ok$' "$s/sys.txt")
[ "$nb" -eq 0 ] && [ "$(wc -l <"$s/sys.txt")" -eq "$n" ] && ok "system prompt == capture template x$n" || no "system prompt: $nb differ"
jq -r '.messages[0].content | capture("User home directory: (?<v>[^\n]*)").v' "$s/a.jsonl" | grep -q drakestapleton && no "captured user name emitted" || ok "captured user name never emitted"
# dates
jq -r '.messages[0].content | capture("Conversation started: (?<v>[^\n]*)").v' "$s/a.jsonl" | sort -u >"$s/dates.txt"
nd=0 dbad=0
while IFS= read -r d; do
	nd=$((nd + 1))
	day=$(echo "$d" | sed 's/^[A-Za-z]*, //; s/ (.*//')
	want=$(TZ=America/Chicago date -d "$day 12:00" "+%A, %B %d, %Y (%Z, UTC%:z)")
	[ "$want" = "$d" ] || { dbad=$((dbad + 1)); echo "BAD  date '$d' want '$want'"; }
done <"$s/dates.txt"
[ $dbad -eq 0 ] && ok "dates: $nd distinct, all equal GNU date America/Chicago" || no "dates: $dbad of $nd wrong"
# families
grep '^@task ' "$s/a.world" | cut -d' ' -f3,4 | sort | uniq -c >"$s/families.txt"
if grep -Eqv ' (create|append|count_lines|list_dir|rename|copy|mkdir_file|first_line|delete|count_words) train$' "$s/families.txt"; then
	no "a non-train family: $(cat "$s/families.txt" | tr '\n' ' ')"
else
	ok "train families only: $(awk '{printf "%s=%s ", $2, $1}' "$s/families.txt")"
fi
# replay
k=0 rbad=0 calls=0 vpass=0
while [ $k -lt "$n" ]; do
	d=$s/r/$k
	mkdir -p "$d"
	"$v" setup "$s/a.world" "s$k" "$d" || { rbad=$((rbad + 1)); echo "BAD  s$k setup"; k=$((k + 1)); continue; }
	sed -n "$((k + 1))p" "$s/a.jsonl" | jq -r '.messages[] | select(.role == "assistant" and has("tool_calls")) |
		.tool_calls[0].function.arguments | fromjson | .command | @base64' >"$s/cmds"
	sed -n "$((k + 1))p" "$s/a.jsonl" | jq -r '.messages[] | select(.role == "tool") | .content | @base64' >"$s/outs"
	i=1
	while IFS= read -r cb; do
		calls=$((calls + 1))
		cmd=$(printf '%s' "$cb" | base64 -d)
		got=$(cd "$d" && bash -c "$cmd" 2>&1)
		rc=$?
		want=$(sed -n "${i}p" "$s/outs" | base64 -d)
		real=$(jq -nr --arg o "$got" --argjson e "$rc" '"{\"output\": " + ($o|tojson) + ", \"exit_code\": " + ($e|tostring) + ", \"error\": null}"')
		[ "$real" = "$want" ] || { rbad=$((rbad + 1)); echo "BAD  s$k call $i: \`$cmd\` gave $real, simulated $want"; }
		i=$((i + 1))
	done <"$s/cmds"
	"$v" check "$s/a.world" "s$k" "$d" >"$s/vres" && vpass=$((vpass + 1)) || { rbad=$((rbad + 1)); echo "BAD  s$k outcome: $(cat "$s/vres")"; }
	k=$((k + 1))
done
[ $rbad -eq 0 ] && ok "replay: $calls tool calls equal real bash, $vpass/$n outcomes PASS verify" || no "replay: $rbad mismatches ($calls calls, $vpass/$n outcomes PASS)"
if [ $bad -eq 0 ]; then echo "GATE PASS checks=$checks n=$n calls=$calls"; exit 0; fi
echo "GATE FAIL bad=$bad checks=$checks n=$n"
exit 1
