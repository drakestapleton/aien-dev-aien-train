#!/bin/sh
# Throwaway allen-chat (read-only /opt/allen-chat code) pointed at ollm serve on a spare port.
# ollm on 127.0.0.1:18292, allen-chat on 127.0.0.1:18293. Stops only the PIDs it started.
set -u
S=/dev/shm/hive/OwnModelCoord
OUT=${OUT:-$S/ac}
OLLM=${OLLM:-$S/final-aarch64/ollm}
CK=${CK:-/tmp/gk/r10/run/ck60000.bin}
MERGES=${MERGES:-$HOME/handoffs/omega-llm-20261101/v1-data/merges4096.bin}
WARM=${WARM:-0}
mkdir -p "$OUT"
for p in 18292 18293; do
  if [ -n "$(ss -Hltn "sport = :$p")" ]; then echo "PORT_BUSY $p"; exit 3; fi
done
printf 'You are Allen.\n' > "$OUT/system.txt"
BW="bwrap --dev-bind / / --dev /dev --bind /dev/shm /dev/shm --proc /proc --"
taskset -c 8-9 nice -n 10 $BW "$OLLM" serve 18292 "$CK" "$MERGES" > "$OUT/ollm.log" 2>&1 &
L1=$!
i=0; while [ $i -lt 100 ] && ! grep -q '^PORT 18292' "$OUT/ollm.log"; do sleep 0.2; i=$((i+1)); done
taskset -c 8-9 nice -n 10 $BW /usr/bin/python3 -I /opt/allen-chat/allen_chat.py \
  --listen 127.0.0.1:18293 --upstream 127.0.0.1:18292 --system-prompt "$OUT/system.txt" \
  --omc /opt/allen-chat/omc --irwasm /opt/allen-chat/irwasm --max-tokens 8 --temperature 0 \
  --warm-every "$WARM" --regen-per-hour 0 --stats-every 3600 \
  --open-user "Hi." --open-user-anon "Hello." --greeting-remember "Hi." --greeting-anon "Hello." \
  > "$OUT/allen.log" 2>&1 &
L2=$!
i=0; while [ $i -lt 100 ] && ! grep -q 'allen-chat listening' "$OUT/allen.log"; do sleep 0.2; i=$((i+1)); done
sleep "${SETTLE:-1}"
for q in "What is Omega?" "Tell me a story."; do
  echo "== POST /allen/api/chat: $q"
  curl -sS -m 120 -H 'Content-Type: application/json' \
    -d "{\"messages\":[{\"role\":\"user\",\"content\":\"$q\"}]}" http://127.0.0.1:18293/allen/api/chat
  echo "== curl rc=$?"
done > "$OUT/chat.txt" 2>&1
sleep 1
P1=$(ss -Hltnp 'sport = :18292' | sed -n 's/.*pid=\([0-9]*\).*/\1/p' | head -1)
P2=$(ss -Hltnp 'sport = :18293' | sed -n 's/.*pid=\([0-9]*\).*/\1/p' | head -1)
echo "launchers $L1 $L2 servers ${P1:-none} ${P2:-none}" > "$OUT/pids.txt"
for p in $P1 $P2 $L1 $L2; do kill "$p" 2>/dev/null; done
wait 2>/dev/null
sleep 1
echo "after: $(ss -Hltn 'sport = :18292' | wc -l) $(ss -Hltn 'sport = :18293' | wc -l)" >> "$OUT/pids.txt"
cat "$OUT/chat.txt"; echo "--- ollm.log"; cat "$OUT/ollm.log"; echo "--- allen.log"; cat "$OUT/allen.log"; cat "$OUT/pids.txt"
