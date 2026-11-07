# DEPLOY: staged deployment of `ollm serve` (DRA-125)

Status (2026-11-07): **NOT DEPLOYED.** Lead decision D8 keeps `127.0.0.1:18091` unbound. This page
is the procedure and the tooling; the rehearsal below ran on the candidate ports 18296-18298 only.
The lead or the queen runs the cutover (section 5), and only for a candidate that has passed every
gate in section 4. Mark DEPLOYED only after the observations in section 5.6 are recorded.

## 1. Identity: what is frozen

One deployment is one **stage directory**:

```
STAGE/
  model.manifest     OLLM-MANIFEST-1 (the SI installer format, sovereign-intelligence
                     installer/share/MODEL-MANIFEST.md, hive/t_80844d23-own-manifest)
  deploy.manifest    OLLM-DEPLOY-1 (this repository, below)
  checkpoint.ck      the own checkpoint (OLLMCK03; OLLMCK01/02 also load)
  merges.tok         the own tokenizer (OLLMTOK1)
  bin/ollm           the server executable (`tests/omegallm/build.sh`, aarch64)
```

`model.manifest` is byte-compatible with SI's OLLM-MANIFEST-1: ten keys (`format name owner source
checkpoint tokenizer serve omc bytes files`), then one `SHA256 SIZE FILE` line per file. The SI
rollback harness (t_fceb3625) asks for the tuple *ckpt OLLMCK0N sha256, tok OLLMTOK1 sha256, ollm serve
sha256 + aien-train commit, omc sha256*: the first, second, third and fifth come from
`model.manifest` (`checkpoint`, `tokenizer`, `serve`, `omc`), the commit from `deploy.manifest`.

`deploy.manifest` (OLLM-DEPLOY-1) adds what the SI format has no key for:

```
format OLLM-DEPLOY-1
manifest SHA256                                    sha256 of model.manifest
commit HEX40                                       aien-train commit bin/ollm was built from
ck MAGIC V T D H F L B STEP P BYTES FNV16          header fields, size, payload FNV-1a 64
tok OLLMTOK1 V FNV16                               tokenizer V, header checksum
launch bin/ollm serve PORT checkpoint.ck merges.tok
```

The running server proves what it loaded: `GET /health` ends with a `"model"` member (serve.om
section *loaded identity*), filled once at start after both loaders succeeded:

```
{"status":"ok","in_flight":0,"queued":0,"capacity":32,"busy":false,"model":{"ck":"OLLMCK03","V":32768,
"T":1024,"D":384,"H":6,"F":1536,"L":8,"B":16,"step":2450,"P":26745216,"ck_bytes":641885312,
"ck_fnv":"0604f180eef533cb","tok":"OLLMTOK1","tok_V":32768,"tok_fnv":"920b3046a17db9be"}}
```

`ck_fnv` is the payload FNV-1a 64 the loader recomputed over every payload byte it decoded and found
equal to the header (load exits 14 otherwise); `tok_fnv` is the OLLMTOK1 checksum `tkload` verified
(exit 26 otherwise). The queue fields are unchanged, so `/health` readers (allen-chat `status` and
`in_flight`, spark-baseline's `"busy":false` substring) keep working.

## 2. Tools (tests/omegallm/deploy/)

| File | What |
|---|---|
| `mancheck.om` | the checker (Omega). `id DIR CK TOK` recomputes and prints the `ck`/`tok` lines; `check DIR SUMS` admits `model.manifest` by SI's ten refusal rules, checks every sha256 and size against SUMS and the files, recomputes the checkpoint (size = header + 24 P, header fields, payload FNV-1a 64) and the tokenizer (FORMAT.md section 2, checksum), and compares them with `deploy.manifest`; `live DIR SUMS HEALTH LIVE` adds the running process: the `/health` `"model"` member byte for byte, the sha256 of `/proc/PID/exe`, the kernel's resolved exe path (`DIR/bin/ollm`) and the command line against the launch line. One line `MANCHECK PASS ...` or `MANCHECK FAIL reason`, exit 0 / 1. |
| `osup.om` | the supervisor (Omega) for hosts without aien-supervise: fork + exec, log append, restart 500 ms after any exit (kill -9 included), stop file -> SIGTERM, 10 s, SIGKILL, reap, exit 0; crash loop (11 restarts with no child living 30 s) -> exit 3 with nothing running. |
| `deploy.sh` | thin sh driver: `build`, `stage`, `sums`, `gate`, `live`, `start`, `switch`, `stop` (usage in its header). sha256 comes from the host's `sha256sum` (recorded host dependency; also `curl`, `ss`, `taskset`, `git`). |
| `rehearse.sh` | the whole candidate-endpoint rehearsal with receipts (section 3). |

Supervision: `aien-supervise` (aien-dev/spark-supervisor) is **not installed for this user** on the
Spark (no `~/.config/aien-supervise`; the only aien-supervise processes are root's
`/usr/local/libexec/aien-supervise/*` units for other services). Until it is, the candidate runs under
`osup`. When it is installed, the service file is `~/.config/aien-supervise/services/ollm-serve.svc`
with the same command line as `deploy.sh start` (section 5.3), and `deploy.sh live` is unchanged.

## 3. Rehearsal (candidate ports only) and its receipts

```
OMC=<pinned omc 2c824805...> WORK=~/work/hive/ownmodel/deploy/w \
CKA=<candidate CK03> CKR=<previous verified CK03> CKR_SHA=<its recorded sha256> TOK=<OLLMTOK1> \
sh tests/omegallm/deploy/rehearse.sh
```

Steps (each a receipt in `evidence/OMEGALLM/deploy/rehearsal/NAME.txt`, summary in `summary.txt`):
build (ollm, mancheck, osup, mutant id); the rollback checkpoint's recorded sha256; stage A
(candidate) and R (rollback); `gate` A and R; 17 negative controls that must be refused (wrong
checkpoint sha256, a checkpoint sha256 that is no file line, swapped checkpoint, swapped checkpoint
with model.manifest rewritten to match it, wrong FNV in deploy.manifest, a forbidden name, a `url`
line, SI's shipped PENDING manifest, a duplicate key, another serve binary, one changed payload byte
(gate, `id`, and serve itself exit 14), one changed tokenizer byte, a live check against the other
manifest, a live check of identical files in another directory, a refused switch, the id mutant);
start A under osup on 18296; `live`; cancellation (a streaming client that leaves after 3 s: `C 499`
logged, server idle again); the test fixture on 18297 (`tplmax=4000 test=1`, scripted tool-call
output); `serve-check.py` (streaming and non-streaming, CHAT1 identity of prompts, tool-call
schema JSON and SSE with negative controls, prefix reuse bit-exactness, queue FIFO / 503 /
disconnect, identity stable and equal to deploy.manifest on both ports); kill -9 of the server,
osup restart, same identity and new pid with osup as parent; switch to R and back to A with live
proof each time; clean stop of all three supervisors with `STATE.PORT` = UNAVAILABLE.

## 4. Gates a candidate must pass before the cutover

1. `deploy.sh gate STAGE` prints `MANCHECK PASS` for the candidate stage built with port 18091.
2. `rehearse.sh` with CKA = the candidate and CKR = the previous verified own checkpoint ends
   `REHEARSAL pass=N fail=0`, `serve-check` `SUMMARY ... fail=0`.
3. The lead's quality gates for that checkpoint (DRA-124 holdout, harness) — outside this page.
4. Consumer readiness (section 6): at least the consumers to be switched fit T and the name checks.
5. The frozen tuple is posted once on the BOARD (section 5.6) so SI's installer/rollback can admit it.

The rehearsal candidate of 2026-11-07 (run1 stage A step 2450, T 1024) is a **rehearsal artifact,
not a release candidate**: it has not passed gate 3, and T 1024 is below the allen-chat system
prompt (3,678 CHAT1 tokens with OLLMTOK1 32K, MEASURED, `ollm chatenc` on `/opt/allen-chat/system-prompt.txt`
sha256 d44a61dd..., 14,364 bytes, plus a one-word user turn).

## 5. Cutover runbook (lead / queen only)

Variables: `R=~/.local/share/aien/ollm-deploy` (the deploy root; `current` is a symlink to one stage),
`OMC=/home/drakestapleton/workspace/hive-worktrees/arch-scale-x/omc/seed/out/omc`, `BIN=$R/bin`
(mancheck, osup), `D="sh <aien-train>/tests/omegallm/deploy/deploy.sh"`, `CORES=<the serving cores>`.

### 5.1 Before: record the current state (read-only)

```
ss -Hltnp 'sport = :18091'            # expected: empty (D8). Anything else: stop, ask the lead.
ss -Hltnp | grep -E ':18110 '          # allen-chat gateway, upstream 127.0.0.1:18091
systemctl show allen-chat -p MainPID,ActiveState
```

### 5.2 Build and stage for 18091

```
export OMC BIN CORES
$D build $BIN
$D stage $R/stage/<NAME> <candidate.ck> <merges32k.bin> $BIN/ollm <NAME> 18091
$D stage $R/stage/<PREV> <previous.ck>  <merges32k.bin> $BIN/ollm <PREV> 18091
$D gate $R/stage/<NAME>  &&  $D gate $R/stage/<PREV>        # both MANCHECK PASS
```

`stage` refuses a tree whose `native/omegallm` or `build.sh` differs from HEAD and records HEAD as
`commit`. The checkpoint is copied (never linked to a training directory that a trainer rewrites).

### 5.3 Bind :18091

```
ln -sfn $R/stage/<NAME> $R/current
$D start $R 18091            # osup: $R/current/bin/ollm serve 18091 $R/current/checkpoint.ck $R/current/merges.tok
until curl -sf -m 2 http://127.0.0.1:18091/health >/dev/null; do sleep 1; done     # ~20 s load
$D live $R/stage/<NAME> 18091                 # MANCHECK PASS ... live=exe,path,argv,health
```

With aien-supervise installed instead: the same command line in
`~/.config/aien-supervise/services/ollm-serve.svc`, then the same `live` check.

### 5.4 Smoke on :18091 (before any consumer is changed)

```
curl -s http://127.0.0.1:18091/v1/models                       # {"object":"list","data":[{"id":"ollm",...}]}
curl -s http://127.0.0.1:18091/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","content":"Say hello."}],"max_tokens":16,"temperature":0}'
curl -sN http://127.0.0.1:18091/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","content":"Say hello."}],"max_tokens":16,"stream":true}'   # ends data: [DONE]
kill -9 $(ss -Hltnp 'sport = :18091' | grep -o 'pid=[0-9]*' | cut -d= -f2)    # osup restarts it
until curl -sf -m 2 http://127.0.0.1:18091/health >/dev/null; do sleep 1; done
$D live $R/stage/<NAME> 18091                  # same identity, new pid
```

The full `serve-check.py` fills the queue (32 waiting completions) and the context; run it against
:18091 only while no consumer points at it.

### 5.5 Consumers, one at a time (each: change, restart if needed, verify, or roll back)

Details, file:line and current values: `evidence/OMEGALLM/deploy/consumers.md` (read-only inventory,
2026-11-07T04:31Z). Most configs already point at `127.0.0.1:18091/v1`; the work is context, name
checks and parallelism, not URLs. The aien-keep files (`/srv/aien-keep/LOCKED`) need aien-keeper or
root: a queen / Drake decision.

| Consumer | Change at cutover | Verify | Rollback |
|---|---|---|---|
| allen-chat (`/etc/systemd/system/allen-chat.service:20` `--upstream 127.0.0.1:18091`, pid 7867) | none to the URL; T must hold the 3,678-token system prompt (T 4096 candidate only); optionally `--busy-at 1` (ollm `in_flight` is 0/1); `systemctl restart allen-chat` (root) | a public chat answers; server log `C 200` | `deploy.sh stop`: allen sees upstream down (truthful unavailable); or restore the previous unit and restart |
| Hermes gateway (`~/.hermes/config.yaml` aienmotor, aien-keep, pid 3653278) | `context_length: 131072` -> 4096 (lines 12-13); restart `hermes-gateway` | NOT_RUN: Hermes's system prompt + tool schemas may exceed 4096 tokens; measure with `ollm chatenc` first | restore 131072, restart |
| local-coder (`~/.local/bin/local-coder:49-50` greps /v1/models for the model name) | run with `LOCAL_CODER_MODEL=ollm` (no file change) | exit status not 3 | unset the variable |
| opencode (`~/.config/opencode/opencode.jsonc:44-48,73`) | `context` 49152 -> 4096, `output` <= 4096 minus prompt; reconsider the default model | one opencode turn | restore the values |
| omp (`~/.omp/agent/models.yml:2-13`, live pid 1690205) | `contextWindow` 4096, `maxTokens` <= 4096; `tokenizer: qwen3` has no ollm equivalent (NOT_FOUND) | one omp turn | restore, restart omp |
| aien harness (`~/.local/bin/aien`, `aien.yml`) | relies on a parallel swarm and a 49,152-token window: do not switch until ollm serves those | — | — |
| aien-manager, aien-board-snapshot | none (display); board snapshot reads the 35B's stale serve.pid/serve.log | display shows `"id":"ollm"` | — |
| spark-baseline (`~/.local/bin/spark-baseline:18,41`) | exact-name check on `qwen3.8-27b-fp8`: needs a code change (a new `ollm` case) | — | — |

### 5.6 Mark DEPLOYED only after this is observed and written to the BOARD and DRA-125

- endpoint `127.0.0.1:18091`, `ss -Hltnp` line, pid, `readlink /proc/PID/exe`, sha256 of `/proc/PID/exe`;
- `model.manifest` and `deploy.manifest` sha256, the frozen tuple (checkpoint, tokenizer, serve sha256,
  commit, omc sha256), the `deploy.sh live` output;
- the commands of 5.2-5.5 as run, with their outputs; the consumers switched, each verification;
- the rollback target (`<PREV>` stage) and the result of one rehearsed `switch` to it and back.

### 5.7 Rollback

- To the previous verified own checkpoint (seconds of 503/refused while it loads, ~20 s MEASURED):
  `$D switch $R $R/stage/<PREV> 18091` (gates `<PREV>` first; refuses a stage that fails), then
  `$D live $R/stage/<PREV> 18091`. Back: the same with `<NAME>`.
- Clean shutdown with a truthful unavailable state: `$D stop $R 18091` -> `$R/STATE.18091`
  `UNAVAILABLE port 18091: no ollm process, no listener, /health connection refused`. Consumers then
  get connection refused, never a stand-in. Revert consumer changes per the table.
- Never restore or download outside weights; the only rollback targets are own stages that pass `gate`.

## 6. Known limits

- The `/health` identity is read from the header after the loaders verified it; a file changed after
  the server started is not re-read (the server holds the decoded weights in memory). `deploy.sh live`
  re-hashes the files on disk, so it fails if the stage was modified after start.
- `osup` restarts any exit, including a deliberate `exit 2` from a bad launch line, up to its crash-loop
  limit.
- mancheck computes no sha256 itself (host `sha256sum`); the FNV-1a 64 checks are its own.
- SI's own admission code (`wizard/steps.om` `mown`, omc 62775d2a) was not run on these manifests:
  NOT_RUN. mancheck implements the same ten refusal rules from MODEL-MANIFEST.md.
