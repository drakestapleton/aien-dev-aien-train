#!/bin/zsh
set -eu
export PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin
root="$HOME/Applications/Omega/Aienux"
runtime="$HOME/workspace/aien-train-macbook/local-mac"
qwen="$HOME/workspace/ggml-omega-macbook"
uid=$(id -u)
running=0
if [[ -f "$root/qemu.pid" ]]; then
  pid=$(cat "$root/qemu.pid")
  command=$(ps -p "$pid" -o command= 2>/dev/null || true)
  if [[ "$command" == *qemu-system-x86_64* && "$command" == *"$root/model.img"* ]]; then running=1; fi
fi
if (( ! running )); then
  (cd "$root" && shasum -a 256 -c SHA256SUMS)
  : > "$root/boot.log"
  vm_label=dev.aien.omega-aienux-vm
  if ! launchctl print "gui/$uid/$vm_label" >/dev/null 2>&1; then
    launchctl bootstrap "gui/$uid" "$HOME/Library/LaunchAgents/$vm_label.plist"
  fi
  launchctl kickstart "gui/$uid/$vm_label"
  vm_pid=$(launchctl print "gui/$uid/$vm_label" | awk '/pid =/{print $3; exit}')
  [[ -n "$vm_pid" ]] || { print 'Aienux VM did not start.'; exit 1; }
  print "$vm_pid" > "$root/qemu.pid"
  sleep 1
  nohup /usr/bin/nc -d -U "$root/serial.sock" >> "$root/boot.log" 2>&1 < /dev/null &
  reader=$!
  disown
  print 'Aienux is loading Astra’s model. This uses emulation and can take several minutes.'
  ready=0
  for attempt in {1..600}; do
    if grep -q '^LMREADY' "$root/boot.log"; then ready=1; break; fi
    if ! kill -0 "$vm_pid" 2>/dev/null; then break; fi
    sleep 1
  done
  kill "$reader" 2>/dev/null || true
  if (( ! ready )); then
    kill "$vm_pid" 2>/dev/null || true
    print 'Aienux did not load. The boot log is in Applications/Omega/Aienux.'
    exit 1
  fi
  # The model is ready; avoid firmware polling consuming a core while the browser opens.
  print 'stop' | /usr/bin/nc -U -w 1 "$root/monitor.sock" >/dev/null || true
fi
if ! curl -fsS http://127.0.0.1:8097/health >/dev/null; then
  (cd "$qwen" && export GGML_BACKEND_PATH="$qwen/build-mac/prepared/libggml-omega.dylib" OMEGA_GGML_DEVICES=host && exec nohup "$qwen/build-mac/runtime/llama-b11913/llama-server" -m build-mac/qwen.gguf --device Omega -ngl 0 -fa off -c 2048 -b 64 -ub 64 -t 2 --parallel 1 --host 127.0.0.1 --port 8097 --fit off) >"$runtime/qwen-ui.log" 2>&1 </dev/null &
  disown
fi
label=dev.aien.omega-aienux-ui
if ! launchctl print "gui/$uid/$label" >/dev/null 2>&1; then
  launchctl bootstrap "gui/$uid" "$HOME/Library/LaunchAgents/$label.plist"
fi
launchctl kickstart "gui/$uid/$label"
for attempt in {1..30}; do
  if curl -fsS http://127.0.0.1:8099/props >/dev/null; then
    open http://127.0.0.1:8099
    print 'Choose Omega-Astra-Aienux. Enter one short story beginning. Each reply is limited to eight tokens.'
    print 'This experimental firmware path is slow. After pressing Stop, reopen this launcher to restart Aienux.'
    exit 0
  fi
  sleep 1
done
print 'The Aienux browser adapter did not start.'
exit 1
