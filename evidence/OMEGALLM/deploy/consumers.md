# :18091 consumers inventory for the DRA-125 cutover to `ollm serve` (read-only)

Written 2026-11-07T04:31Z (2026-11-06 22:31 CST) on spark-b87b by a read-only subagent of lead `ownmodel`, deploy lane.
Nothing was changed, restarted or killed, and no request went to :18091, :18110 or any other service.
Sources: `ss -ltnp`, `ps`, `systemctl show` (read only), `sudo -n` used only to print the key **names** in
`/etc/allen-chat/env` (values not read into this file), plus plain file reads. Inventory leads came from
`~/handoffs/hive/parity-35b.md` §1 (lines 22-41) and `~/handoffs/BOARD.md`. BOARD.md has no consumer config
for 18091; it matches only `omp-ollm` lane window lines (BOARD.md:8-71), so it adds no consumers.
Secrets are shown as [REDACTED].

Server contract assumed at cutover (lead brief; checked against the deploy checkout
`~/work/hive/ownmodel/deploy/aien-train` branch `feat/ollm-deploy` head `2114454`, `native/omegallm/serve.om` header lines 1-62):
127.0.0.1 only; `/v1/models` id `"ollm"` (serve.om:142 `text svollm "ollm"`); `model` member ignored (serve.om:36);
POST /v1/chat/completions JSON+SSE; GET /health; one generation at a time, 32-slot FIFO (serve.om:17-24);
T = 4096 tokens; no auth. **Contract details that matter for consumers below (serve.om header):**
- `/health` body: header line 17 says `{"status":"ok","in_flight":0,"queued":0,"capacity":32,"busy":false}`; the
  literal at serve.om:85 is `{"status":"ok","in_flight":0,"busy":false}` and serve.om:86 is
  `{"status":"ok","in_flight":1,"busy":true}`. `in_flight` is only ever 0 or 1 (serve.om:19).
- Each connection gets one request, then `Connection: close` (serve.om:11-12). No keep-alive.
- At this head, `tools`/`tool_choice` are parsed. Tool calls come back as `<tool_call>` blocks under the interim
  template (serve.om:33-37, 49-55). Content arrays of text parts are accepted (serve.om:27-28). `stop`, `top_k` and
  `top_p` are honoured (serve.om:30-33). This is **newer than parity-35b.md §2**, which was written at c73d4f33
  and lists these as MISSING.
- The template is capped at `tplmax`, default 65536 bytes (serve.om:14-15). A prompt with CT0 >= T gets 400
  `context_length_exceeded` (serve.om:42-44).

## 1. Listeners now

`ss -ltnp | grep -E ':18091|:18110'` (2026-11-07T04:2xZ, verbatim):

```
LISTEN 0      64              100.64.0.2:18110      0.0.0.0:*
```

- **:18091: nothing listening.** No `ss` line, and no ESTAB socket to or from :18091 (`ss -tn state all '( dport = :18091 or sport = :18091 )'` printed only the header).
- **:18110**: bound on 100.64.0.2. `ss` shows no owner because the unit runs as system user `allen-chat`. The owner is
  pid **7867** (`ps`: `/usr/bin/python3 -I /opt/allen-chat/allen_chat.py --listen 100.64.0.2:18110 --trusted-proxy 100.64.0.3 --upstream 127.0.0.1:18091 ...`),
  and `systemctl show allen-chat` gives `MainPID=7867`, `ActiveState=active`, `ExecMainStartTimestamp=Wed 2026-10-28 19:07:21 CDT`.
- Stale pidfile: `~/.local/state/aien-q36/serve.pid` = `3367878` (mtime Oct 31 08:32). That process is gone (no `/proc/3367878`).

`ss -ltnp | grep -E ':180[0-9][0-9]|:181[0-9][0-9]'` (verbatim):

```
LISTEN 0      128              127.0.0.1:18096      0.0.0.0:*
LISTEN 0      128              127.0.0.1:18080      0.0.0.0:*    users:(("cortex-rs",pid=4051454,fd=12))
LISTEN 0      128              127.0.0.1:18092      0.0.0.0:*    users:(("spark-mail",pid=4051523,fd=10))
LISTEN 0      128              127.0.0.1:18095      0.0.0.0:*    users:(("spark-cockpit-r",pid=4051483,fd=12))
LISTEN 0      16               127.0.0.1:18173      0.0.0.0:*    users:(("server",pid=1178099,fd=3))
LISTEN 0      4096             127.0.0.1:18171      0.0.0.0:*
LISTEN 0      64              100.64.0.2:18112      0.0.0.0:*
LISTEN 0      64              100.64.0.2:18132      0.0.0.0:*
LISTEN 0      4096            100.64.0.2:18174      0.0.0.0:*
LISTEN 0      64              100.64.0.2:18110      0.0.0.0:*
LISTEN 0      4096   [fd7a:115c:a1e0::2]:18174         [::]:*
```

Summary: 10 sockets in 18000-18199, and **none is 18091**. :18112 is the allen-chat console (`allen-chat.service:36`
`--console-listen 100.64.0.2:18112`). pid 1178099 is `~/.local/share/omega-tool-model/round40-workbench/server`.
Not in the 180xx/181xx range, but relevant: lane test servers `ollm serve 18291 ...` (pid 1918254) and
`ollm serve 18294 ...` (pid 1986641) were running at inventory time.

### Anything configured to start on :18091

`grep -rn 18091 ~/.config/systemd/user /etc/systemd/system ~/.config/aien/` (verbatim):

```
~/.config/systemd/user/tlsfuzz-watch.service:4:Description=om/tls fuzz watchdog (pause on quiet/window/lock/load/18091 triggers)
~/.config/systemd/user/allen-imac-courier.service.bak-20261028T172905Z:7:ExecStart=%h/.local/libexec/allen-imac-courier-da55660e --udp 47033 ... --model 127.0.0.1:18091 ...
/etc/systemd/system/allen-chat.service:20:  --upstream 127.0.0.1:18091 \
```

- **No unit, timer or supervisor config starts a server on :18091.** All three hits are clients or a description.
  The `.bak` file is not a loaded unit.
- `~/.config/aien/supervisor.toml` and `~/.config/aien/supervisor-interim.toml` have no `18091` (grep rc=1).
- No user unit is named `*q36*`, `*aien-serve*`, `*35b*`, `*motor*`, `*ollm*` or `*omega*`, except
  `omega-tool-model.service` and `omega-tool-web.service`, neither of which contains `18091`.
- crontab (`crontab -l`) has no line that starts a server on 18091.
- The old manual launchers still exist: `~/.local/state/aien-q36/start-35b.sh` and `start-35b-batch.sh` (Oct 30, executable).
  Nothing schedules them.

## 2. Consumers

Legend:
- **running** = a live process holds the config now.
- **restart?** = whether that process needs a restart to pick up a config change.
- **cutover** = what the consumer needs to work against `ollm serve` on 127.0.0.1:18091.
- **rollback** = the current value, verbatim.
- **aien-keep**: `/srv/aien-keep/home/...` targets are owned `aien-keeper:drakestapleton`, mode 0644/0755, under
  root-owned 0755 dirs. `/srv/aien-keep/LOCKED` lists `.hermes/config.yaml`, `.local/bin/local-coder`,
  `.config/opencode/opencode.jsonc`, `.omp/agent/models.yml`, `.local/bin/aien` and `.local/share/aien/aien.yml`.
  drakestapleton cannot write them; edits need aien-keeper or root, which is the queen/Drake's decision.

### 2a. Table

| # | consumer | file (→ real path) | key / line | current value (verbatim) | cutover need (ollm on 127.0.0.1:18091) | running? (pid) | restart? | rollback |
|---|---|---|---|---|---|---|---|---|
| 1 | **allen-chat** public gateway (www.aienos.com/allen/) | `/etc/systemd/system/allen-chat.service` | line 20 | `  --upstream 127.0.0.1:18091 \` | URL already matches; no change. | **yes, 7867** (since 2026-10-28 19:07 CDT) | yes, `systemctl restart allen-chat` (root) if any unit/env/code changes; `daemon-reload` for unit edits | same line |
| 1a | allen-chat | `/opt/allen-chat/allen_chat.py` | line 102 | `MODEL = "qwen3.6-35b-a3b-fp8"` | Can stay: ollm ignores `model`. Hard-coded, not a flag. | 7867 | yes (code is loaded at start) | same |
| 1b | allen-chat | `/opt/allen-chat/allen_chat.py` | line 2534 (default) | `ap.add_argument("--upstream", default="127.0.0.1:18091")` | none | 7867 | — | same |
| 1c | allen-chat | `/opt/allen-chat/allen_chat.py` | lines 2545-2546 | `ap.add_argument("--busy-at", type=int, default=6,` / `help="do not start a public request while /health in_flight >= this")` | Not set in the unit, so 6 applies. ollm `in_flight` is 0/1, so this never trips and every request goes to ollm's FIFO. To get a real back-off, add `--busy-at 1` to the unit's ExecStart. | 7867 | yes | flag absent (default 6) |
| 1d | allen-chat | `/opt/allen-chat/allen_chat.py` | lines 606-611 (`Upstream.admit`) | `c.request("GET", "/health", headers=self.headers)` … `self.health_inflight = int(body.get("in_flight", 0))` / `self.health_ok = r.status == 200 and body.get("status") == "ok"` | Compatible: needs `status:"ok"` and an int `in_flight`, and ollm sends both. | 7867 | — | — |
| 1e | allen-chat | `/etc/allen-chat/env` (root 0600, `EnvironmentFile=-` at unit line 16) | line 1 | `ALLEN_UPSTREAM_TOKEN=` (**empty**, checked by length only) | Nothing to do (ollm ignores Authorization; empty means no header, allen_chat.py:557). Other keys: line 2 `ALLEN_VISITOR_SECRET=`[REDACTED], line 3 `CORTEX_VISITORS_TOKEN=`[REDACTED], line 4 `ALLEN_CONSOLE_TOKEN_SHA256=`[REDACTED]. Do not touch these. | 7867 | env changes need a restart | `ALLEN_UPSTREAM_TOKEN=` |
| 1f | allen-chat | `/opt/allen-chat/system-prompt.txt` (unit line 21) | whole file | 14,364 bytes (mtime Nov 6 15:23) | Below ollm's default `tplmax` 65536 B. Parity measured a median of **6,852 Qwen tokens** per live prompt, more than T = 4096. With ollm's tokenizer the count is NOT_RUN. If it is over 4096, every chat, warm ping, regen and introduce gets 400 `context_length_exceeded`. **Blocker** unless the prompt is cut down or allen is pointed elsewhere. | 7867 | prompt read at start: restart | current file; backups `system-prompt.txt.before-twitter-20261106`, `.bak-20261026T231625Z` |
| 1g | allen-chat speed test (`allen_infer`, imported at allen_chat.py:67, `init` :854) | `/opt/allen-chat/allen_infer.py` | lines 58-71 | `MODEL = "qwen3.6-35b-a3b-fp8"`, `SERVER_ROOM = 6`, `SLOTS = 4`, `HEAVY_TOKENS = 4096`, `MAX_TOKENS = 4096`, `MAX_PROMPT_TOKENS = 32768`, `SWEEP_MAXES = (4096, 8192, 16384, 32768)`, `QUEUE_DEPTH = 8` | Assumes 8 batch rows ("in_flight + rows <= SERVER_ROOM (6)", line 19) and runs concurrent 2-4-stream modes. On ollm, concurrent tests serialize in the FIFO (wrong aggregate tok/s), sweeps above 4096 tokens get 400, and its `in_flight` gate always passes. Fixing it needs code changes. | 7867 | yes | same |
| 2 | **Hermes gateway** (default profile, `HERMES_HOME=/home/drakestapleton/.hermes`, unit line 13) | `~/.hermes/config.yaml` → `/srv/aien-keep/home/.hermes/config.yaml` (aien-keep locked) | lines 2, 3 | `  default: qwen3.6-35b-a3b-fp8` / `  provider: aienmotor` | The model name can stay (ignored). The gateway's **main** model is this provider. | **yes, hermes-gateway.service MainPID 3653278** (since 2026-11-05 11:23:58 CST) | yes, `systemctl --user restart hermes-gateway` (INFERENCE: config is read at start; parity §1 cites the "Model context warmed" start log) | same |
| 2a | Hermes gateway | same file | line 7 | `    base_url: http://127.0.0.1:18091/v1` | none | 3653278 | — | same |
| 2b | Hermes gateway | same file | line 8 | `    api_key: `[REDACTED] (5 chars) | Ignored by ollm. No change. | 3653278 | — | same |
| 2c | Hermes gateway | same file | lines 9, 10 | `    model: qwen3.6-35b-a3b-fp8` / `    api_mode: chat_completions` | none (model ignored) | 3653278 | — | same |
| 2d | Hermes gateway | same file | lines 12-13 | `      qwen3.6-35b-a3b-fp8:` / `        context_length: 131072` | Must say **4096**, or Hermes sends 131k-sized agent prompts and gets 400s. **Blocker (INFERENCE, NOT_RUN):** Hermes's system prompt plus tool schemas alone probably exceed 4096 tokens, and Hermes may enforce a minimum context. Check before cutover. | 3653278 | yes | `context_length: 131072` |
| 2e | Hermes bot relay | `~/.hermes/bot_relay/roster.json` | line 1 | `"description": "Chat with the 35B on AIEN's own engine (the motor) on the Spark, via 127.0.0.1:18091", "handle": "aienmotor"` | Text only. Update the wording ("ollm") if wanted. | via gateway 3653278 | INFERENCE: restart | same |
| 2f | Hermes credential pool | `~/.hermes/auth.json` | lines 49, 52 | `"label": "aienmotor",` / `"source": "config:aienmotor",` | none (derived from config). `active_provider` line 67 is `"xai-oauth"`. | — | — | same |
| 2g | other Hermes profiles (not default provider) | `~/.hermes/profiles/{desk,queen,worker}/config.yaml` (real files, 0600, not aien-keep) | lines 5-13 | `  aienmotor:` … `    base_url: http://127.0.0.1:18091/v1` … `    model: qwen3.6-35b-a3b-fp8` … `        context_length: 131072` | Only used when `--provider aienmotor` is selected (each profile's default is anthropic). Set `context_length` to 4096 if they will be used. The reviewer profile, line 55 `- "*18091*"`, is a command deny-pattern, not a client. | profile workers run on anthropic | per-session | same |
| 3 | **local-coder** | `~/.local/bin/local-coder` → `/srv/aien-keep/home/.local/bin/local-coder` (aien-keep locked) | lines 21-23, 26 | `PROVIDER="${LOCAL_CODER_PROVIDER:-aienmotor}"` / `MODEL="${LOCAL_CODER_MODEL:-qwen3.6-35b-a3b-fp8}"` / `PORT=18091` / `MAXTURNS=25` | **Model-name check, lines 49-50:** `curl -s -m 5 "http://127.0.0.1:$PORT/v1/models" \| grep -q "$MODEL"` then `local-coder: $PORT is not serving $MODEL (live server down or swapped?)`, exit 3. Against ollm it **always exits 3** unless the caller sets `LOCAL_CODER_MODEL=ollm` (no file change) or the default on line 22 becomes `ollm`. Then it runs `hermes chat --provider aienmotor` (lines 56, 63), with the same 4096-context and agent-loop limits as row 2d. | no process found | no (per invocation) | lines 21-23 as quoted |
| 4 | **opencode** (Spark) | `~/.config/opencode/opencode.jsonc` → `/srv/aien-keep/home/.config/opencode/opencode.jsonc` (aien-keep locked) | line 41 | `        "baseURL": "http://127.0.0.1:18091/v1"` (provider `"omega"`, line 37; `"npm": "@ai-sdk/openai-compatible"`) | none | no `opencode` process found | per launch | same |
| 4a | opencode | same | lines 44-48 | `        "qwen3.6-35b-a3b-fp8": {` … `            "context": 49152,` / `            "output": 16384` | context → **4096**, output ≤ 4096 minus prompt. The model key can stay (name ignored). | — | per launch | same |
| 4b | opencode | same | line 73 | `  "model": "omega/qwen3.6-35b-a3b-fp8",` | This is the **default model**, so every opencode launch hits :18091. Change the default if the coding agent should not run on a TinyStories-scale model. | — | per launch | same |
| 5 | **omp** provider `spark` | `~/.omp/agent/models.yml` → `/srv/aien-keep/home/.omp/agent/models.yml` (aien-keep locked, 414 B) | lines 2-13 | `  spark:` / `    baseUrl: http://127.0.0.1:18091/v1` / `    api: openai-completions` / `    auth: none` / `      - id: qwen3.6-35b-a3b-fp8` / `        tokenizer: qwen3` / `        contextWindow: 49152` / `        maxTokens: 16384` | contextWindow → **4096**, maxTokens ≤ 4096. `tokenizer: qwen3` is wrong for ollm (it miscounts tokens), and no ollm tokenizer id is known: NOT_FOUND. The id can stay (ignored). Note: parity §1 places this file on the MacBook, but it is **on the Spark** (aien-keep symlink). | **yes: pid 1690205 `omp --model spark/qwen3.6-35b-a3b-fp8`**, tmux `omp-hub`, cwd `~/handoffs`, started 2026-11-06 18:20 | yes (models.yml is read at omp start, INFERENCE). As it stands, this live session's next turn goes to :18091. | same |
| 6 | **aien harness** (`aien`, omp + swarm on the 35B) — **not in parity §1** | `~/.local/bin/aien` → `/srv/aien-keep/home/.local/bin/aien` (locked); `/srv/aien-keep/home/.local/share/aien/aien.yml` (locked) | aien:13-14, 17; aien.yml:2, 6-10, 12, 32-35 | `curl -sf -m 5 http://127.0.0.1:18091/v1/models >/dev/null \|\| {` / `model=spark/qwen3.6-35b-a3b-fp8`; aien.yml `  default: spark/qwen3.6-35b-a3b-fp8` (also smol/slow/plan/judge, swarm task/reviewer/security-reviewer/scout), `  modelFallback: false`, comment `(127.0.0.1:18091, 49,152-token window)` | The pre-check only needs 200 from /v1/models, so it passes against ollm. It then runs an omp **swarm**: several agents in parallel, all on `spark/…`. ollm serializes them through its 32-slot FIFO and refuses 4096+ prompts. **Relies on parallelism and long context.** | no `aien` process found | per launch | same |
| 7 | **aien-manager** (cron `7,37 * * * *`, crontab line 38) | `~/.local/bin/aien-manager` | line 21 | `  echo "18091 (Omega): $(curl -s -m4 127.0.0.1:18091/v1/models \| grep -o '"id":"[^"]*"' \| head -1 \|\| echo down)"` | Status text only. It will show `"id":"ollm"`. No change needed. | cron, every 30 min | no | same |
| 8 | **aien-board-snapshot** | `~/.local/bin/aien-board-snapshot` (`motor()`, lines 103-123) | lines 104, 107, 112, 120 | `    txt = sh("curl -s -m 4 127.0.0.1:18091/v1/models", timeout=8)` / `        model = json.loads(txt)["data"][0]["id"]` / `    log = os.path.join(HOME, ".local/state/aien-q36/serve.log")` / `    pid = sh("cat ~/.local/state/aien-q36/serve.pid 2>/dev/null", timeout=5).strip()` | It will show `up: true, model: "ollm"`. But the `last_request` and `pid`/`alive` fields come from the **35B's** serve.log and serve.pid (stale pid 3367878), so they will be wrong for ollm. Repoint them at ollm's log and pidfile if the dashboard matters. **Caller NOT_FOUND:** not in crontab or user units, and no script in `~/.local/bin`, `~/.local/lib`, `~/bin` or `~/.config/systemd/user` references it (only its own `.bak` and `.pyc`). Header line 2: "one JSON blob of live AIEN state, for the dashboard." | not running | per invocation | same |
| 9 | **spark-baseline** | `~/.local/bin/spark-baseline` | lines 18, 34, 40-41, 61 | `  27b) port=${SPARK_BASELINE_PORT:-18091}; mid=qwen3.8-27b-fp8 ;;` / request `"model": "%s"` = `$mid`, `"temperature": 0, "seed": %s` (SEED=1), N=64 / `case $models in *"\"$mid\""*) ;; *) echo "spark-baseline: server on :$port does not serve $mid: $models" >&2; exit 1 ;; esac` / `case $(curl -s --max-time 2 "$6") in *"\"busy\":false"*)` | **The model-name check fails** (exits 1, because `qwen3.8-27b-fp8` is not in ollm's `/v1/models`). `mid` is hard-coded and not env-overridable; only the port is. Needs a code change (for example a new `ollm) port=18091; mid=ollm ;;` case). The /health `"busy":false` poll is **compatible** with ollm (serve.om:85 literal has no spaces). It also requires that `ss -ltnpH` shows a pid (line 38): as user drakestapleton that works only if ollm runs as drakestapleton. | not running | per invocation | line 18 as quoted |
| 10 | **guards** (formerly treated "18091 up" as "35B live") | `~/.local/lib/omtls-fuzz/service/fuzz-watchdog.sh` (tlsfuzz-watch.service, MainPID 4051540) | line 37 | `PORT=${FUZZ_GUARD_PORT:-}` (lines 8-10: "The port trigger is off by default ... the 35B is retired (Drake 2026-11-06, DRA-162)") | **Already neutralised.** The unit sets no `FUZZ_GUARD_PORT` (unit lines 6-13). Parity's `fuzz-watchdog.sh:34 FUZZ_GUARD_PORT=18091` is outdated. No action. | yes 4051540 | no | — |
| 10a | guard | `~/.local/bin/q36-extra` | lines 21, 27-31 | `  curl --noproxy '*' -s -o /dev/null -m 2 http://127.0.0.1:18091/health` (inside `extra_down`), then `slots() { echo 0; }` and an unconditional `exit 75` "the 35B is retired" | Already neutralised (DRA-162). It never loads, whatever is on 18091. No action. | no | — | — |
| 10b | guard | `~/handoffs/pdra4-hive/bin/heavy.sh` | lines 4-6 | `# ... :18091 down is the normal state ... :18091 is not probed any more.` | Already neutralised. No action. | — | — | — |
| 11 | aien-translate (H) | `~/.local/state/aien-translate/server.log` (+ cache.sqlite) | — | config/source NOT_FOUND (looked in `~/.local/state/aien-translate/`, user units, crontab) | Dormant since 2026-10-20 (parity §1 row). | not running | — | — |
| 12 | allen-imac-courier (H) | `~/.config/systemd/user/allen-imac-courier.service.bak-20261028T172905Z` | line 7 | `--model 127.0.0.1:18091` | None. The live courier (pid 4051408) uses `--model 127.0.0.1:18300`. | no (bak) | — | — |
| 13 | Renda 1/2 PR desk (H) | crontab | lines 23-26 | `# USER-STOP 20261023T122104Z * * * * * ... renda-checked --name renda1 ...` | None. Commented out. | no | — | — |

### 2b. Counts

- **Live configs that point at :18091: 9 consumers** (rows 1-9). Five run now or on a schedule:
  - allen-chat, pid 7867
  - Hermes gateway, pid 3653278
  - omp, pid 1690205
  - aien-manager, cron
  - tlsfuzz-watch, pid 4051540 (neutralised)
- **3 guards already neutralised** by DRA-162 (rows 10, 10a, 10b). **3 historical** (rows 11-13).
- **Need a restart to pick up a change:**
  - allen-chat: system unit, root, `systemctl restart allen-chat`.
  - hermes-gateway: user unit.
  - The live omp session pid 1690205 (tmux `omp-hub`).
  - local-coder, opencode, aien, spark-baseline, aien-board-snapshot and aien-manager read their config per invocation.

### 2c. Name checks, parallelism, context, tools, /health — flags for the runbook

- **Model-name checks that FAIL against id `ollm`:**
  - local-coder:49-50: `grep -q "$MODEL"`, exits 3. Workaround with no file change: `LOCAL_CODER_MODEL=ollm`.
  - spark-baseline:41: exact `"qwen3.8-27b-fp8"` match, exits 1. Needs a code change.
- **Name checks that pass** (presence or display only): aien:13 (`curl -sf` 200 only), aien-manager:21, aien-board-snapshot:107.
- **Model name sent but ignored by ollm:** allen-chat `MODEL` (line 102), allen_infer `MODEL` (line 58), Hermes, opencode and omp.
  The 35B used to answer 404 on a mismatch (parity: `prefix_warm_status_404` 14,494). ollm cannot do that.
- **Parallelism assumptions:**
  - allen-chat `--cap` 2 (default, line 2542) and `--busy-at` 6.
  - allen_infer `SLOTS = 4` / `SERVER_ROOM = 6`, with 2-4-stream concurrent mode.
  - The `aien` swarm.
  - All of these serialize behind ollm's single generation slot and 32-slot FIFO. The 33rd waiter gets 503 `queue_full`.
- **/health readers:**
  - allen-chat `in_flight`/`status`: compatible, but the busy-at 6 threshold is meaningless with 0/1.
  - allen_infer `in_flight`.
  - spark-baseline `"busy":false`: compatible.
  - q36-extra: neutralised.
- **Context > 4096:** every agent config declares much more:
  - Hermes 131072
  - opencode 49152/16384
  - omp 49152/16384
  - aien.yml "49,152-token window"
  - allen_infer up to 32768
  - allen-chat prompt median 6,852 Qwen tokens (parity, MEASURED on the 35B). Count under ollm's tokenizer is NOT_RUN.
- **Tool calling** (Hermes, local-coder, opencode, omp, aien): the deploy-head serve.om accepts `tools` and parses
  `<tool_call>` blocks. Whether the model emits valid tool calls is NOT_RUN. allen-chat runs without `--tools`
  (absent from the unit, lines 17-40), so it sends no tools.
- **Keep-alive:** allen-chat pools upstream connections (POOL_IDLE 4 s, line 127). ollm closes after each response.
  allen recovers through `STALE_CONN` retry (lines 130-131, 1774-1780), at the cost of one extra failed send per
  pooled reuse.
- **Uses of 18091 that work unchanged** (same URL, auth ignored, model ignored): the URLs in rows 1, 2a, 4, 5 and 6
  need no edit. Every row's rollback is "leave the file as it is now". At cutover the work is in context limits,
  the two name checks, allen's prompt size and the parallelism assumptions, not in base URLs.

## 3. Not found / not checked

- Who invokes `aien-board-snapshot`: NOT_FOUND (see row 8).
- aien-translate source and config: NOT_FOUND (see row 11).
- An ollm tokenizer id for omp's `tokenizer:` field: NOT_FOUND.
- Whether Hermes enforces a minimum `context_length` above 4096: not checked (no Hermes source read). Verify before
  setting 4096.
- Token count of `/opt/allen-chat/system-prompt.txt` under ollm's tokenizer: NOT_RUN (nothing executed against any server).
- MacBook-side omp config: not reachable from here. Parity says a Mac copy points at 127.0.0.1:18091 through an SSH
  forward [INFERENCE in parity]. The Spark copy is row 5.
