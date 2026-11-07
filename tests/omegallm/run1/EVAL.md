# run1 evaluation pipeline (`tests/omegallm/run1/eval.sh`)

Lane: ownmodel-evalprep (branch `feat/ollm-run1-eval`, from `feat/ollm-path-integ3` 915d9b8). This file is
normative for `eval.sh`: every step, its pass rule and its receipt. The script is a thin POSIX sh driver: the
checks themselves are the existing Omega programs (`mancheck.om`, `verify.om`, `sftgen`, `accept.om`, `ollm`).

**Pass rules are protocol rules** (the step ran, its receipts are complete, its negative control failed).
**Capability numbers** (harness PASS counts, DRA-124 table, demo verdict) are reported, never a pass rule of
`eval.sh`; they are judged against run1 PREREG.md P4 and the DRA-124 PREREG.

## Command (final evaluation, lead)

    cd ~/work/hive/ownmodel/aien-train            # at feat/ollm-run1-eval merged into the integration branch
    OMC=/home/drakestapleton/workspace/hive-worktrees/arch-scale-x/omc/seed/out/omc \
      sh tests/omegallm/run1/eval.sh ~/work/hive/ownmodel/run1/ckB7300.bin B ~/work/hive/ownmodel/run1-eval/B7300

then the chip half of step 2 (printed by the script, `OUT/step2/chip-command.txt`) inside a lease, then

    CHIP_E="$(grep '^E ' OUT/step2/geval4-chip.txt)" STEPS=2 OMC=... sh tests/omegallm/run1/eval.sh CK B OUT

(re-runs only step 2; it re-creates the same retimed copy byte-identically and compares the two E lines).

Defaults: cores `4,6`, server port 18296, harness proxy port 18298, `STEPS="1 2 3 4 5 6"` (0 build and
7 stop always run), merges `~/work/hive/ownmodel/data/merges32k.bin`, data `~/work/hive/ownmodel/data`, run1
dir `~/work/hive/ownmodel/run1` (read only), large copies in `WORK` (`~/work/hive/ownmodel/evalprep/work`),
Hermes data root `HARNESS_HOME` (`~/work/hive/ownmodel/evalprep/hh`, a scratch root, not a profile), DRA-124
transcripts in `AOUT` (`~/work/hive/ownmodel/accept/runs/run1-STAGE-CK8-DATE`, parent forced to mode 0700).
`DRY=1` selects the dry-run subsets and labels every receipt `DRY-RUN STAGE-x (not the candidate)`.
Exit 0 only when every step that ran met its pass rule. `OUT/summary.txt` has one `STEP n NAME RESULT ms=..`
row per step and is printed at the end.

## Steps

| # | Step | What it does | Pass rule | Receipts (`OUT/...`) |
|---|---|---|---|---|
| 0 | build | `tests/omegallm/build.sh` (ollm), `harness/build.sh` (verify, sftgen), `accept/build.sh` (accept), omc of `deploy/mancheck.om`; all with the pinned omc (the harness build refuses another omc) | every build rc 0 | `build.txt`, `bin/` |
| 1 | identity | sha256 of CK, merges, omc and the 5 binaries; commit and dirty count; `mancheck id` (CK03 header fields recomputed: magic V T D H F L B step P bytes payload-FNV; tokenizer V and FNV); provenance: the CK's sha256 must appear in run1 `geval.txt` as `step=N stage=STAGE ck=SHA` | mancheck rc 0, magic OLLMCK03, CK V = tokenizer V, provenance line found for STAGE; **negative control**: a copy with one flipped payload byte (offset 8128) must be refused by `mancheck id` | `step1/identity.txt`, `mancheck-id.txt`, `neg-flip.txt` |
| 2 | xcheck | `tune4 CK X 24000 3000 1024 16 1` (retime to T 1024 B 16 G 1, the CPU training layout); `cmp` of the 8 P parameter bytes after the 128-byte header; CPU `eval4 X base-val.u16 64`; writes the exact chip `geval4` command (run1's `ollm-gb10`, same X, same W) for the lead; with `CHIP_E` compares the two E lines | tune4 and eval4 rc 0, parameters byte-identical, an E line printed; result `PENDING_CHIP` until `CHIP_E` is given, then PASS only when the strings are equal (CONTRACT-V4-GB10 section 3); **negative control**: the same cmp shifted by one value must differ | `step2/xcheck.txt`, `tune4.txt`, `eval4.txt`, `chip-command.txt` |
| 3 | serve | when CK's T is not `SERVE_T` (4096), a `tune4 ... SERVE_T 4 1` copy (parameters cmp-checked identical; the copy's header step reads 0); `ollm serve PORT SCK MERGES par=2` under `taskset -c CORES nice -n 10`; waits for `/health` 200; records pid, workers, `/proc/PID/exe` sha256, argv, affinity, listener; then 3 plain chat requests (max_tokens 48) and 2 requests declaring a `terminal` tool (max_tokens 64), temperature 0 | health 200; the `/health` `model` member equals the served file's mancheck fields (ck line + tokenizer V/FNV); exe sha256 = built ollm; all 5 requests HTTP 200; **negative control**: a body with `messages` not an array must get a 4xx | `step3/health.json`, `live.txt`, `ready.txt`, `serve-copy.txt`, `req-N.json`, `resp-N.{head,json}`, `requests.txt` (http, ms, finish, tool_calls, usage), `serve.log`, `serve-C-lines.txt` |
| 4 | harness | (a) `sftgen TRAINSEED TRAINN` WORLD output = new instances of the TRAIN families in TASKS.md format (default seed 20261109, 30 tasks); `sftgen 20261107 20000` and `sftgen 99 500` are regenerated and must hash to run1's `sft-train.jsonl` / `sft-val.jsonl` (DATA/sft.sha256), and any new task whose @file/@prompt/@expect content equals one of those 20,500 tasks is dropped (`SEEN`); (b) `tasks.txt` held-out t14-t20 and controls c01 c02. Both through `harness/run.sh http://127.0.0.1:PORT/v1` (Hermes v0.22.5 `-t terminal --max-turns 4`, TMO 300 s, proxy PPORT); verify.om verdict per task | pools regenerate byte-exactly; no INVALID or SETUP_FAIL row (each pre-check FAILed before Hermes ran); every task made at least one chat request to the server (`noreq.txt` empty); controls c01, c02 FAIL; the server still runs afterwards; **negative control**: the first training task, renamed, must be caught as SEEN | `step4/unseen.txt`, `pools.txt`, `train-new.txt`, `{train,heldout}/summary.txt` (rows `ID FAMILY SPLIT RESULT rc ms chats first_status`), per-task `prompt.txt pre.txt hermes.* verify.txt wire/ work/`, `capability.txt` (counts + the Wolfram Wilson expression) |
| 5 | accept | `tests/omegallm/accept/run.sh 127.0.0.1 PORT AOUT run1-STAGE-CK8` with HARNESS (this checkout's harness dir), VERIFY, HPPORT=PPORT; default splits `dev test`, PUBLIC 1, REPEATS 3 (the DRA-124 PREREG protocol; `ACCEPT_ENV` may cut arms, e.g. `REPEATS=0`, and any cut is NOT_RUN in the report) | runner rc 0 path (no `runner failed`, no hash mismatch), a `t0.summary` exists, no result row with reason `conn` (`conn-rows.txt` empty: the endpoint was reachable), the server still runs; AOUT's parent is mode 700 | `step5/command.txt`, `receipt.txt`, `t0.summary`, `s*.summary`, `pair-*.tsv` (aggregate rows only); transcripts stay in AOUT |
| 6 | demo | a task file with `d01`: "Create a file named directive.txt whose content is exactly: use your best judgement and get this done" (Drake's public hive directive) run through `harness/run.sh` (real Hermes, real tool execution, the served model); then `verify check` re-run on the copied work dir | the pre-check FAILed before Hermes ran; Hermes made at least one chat request; **negative control**: the same work dir against a deliberately different text (`d01x`) must FAIL | `step6/demo.txt`, `run/` (hermes.out, wire/ = every request and raw response, work/), `verify-d01.txt`, `verify-d01x.txt`, `serve-lines.txt` (the server log lines of the demo), `session.jsonl` + `session-md/` (Hermes's own session export), `result.txt` (DEMO_PASS / DEMO_FAIL: capability) |
| 7 | stop | kills the server pid and its par workers (also on any exit, via trap), deletes the serve copy | the server was still alive (a server found dead at any point is a `SERVER_DIED rc=..` line in `summary.txt` and fails the step), no process left, PORT and PPORT free | `summary.txt` |

Dry-run subsets (`DRY=1`): step 4 runs the first 3 train-family tasks of distinct families and held-out t14
t16 (no controls); step 5 runs `SPLITS=dev DEVN=10 PUBLIC=0 REPEATS=0`: 10 own dev items taken round-robin over
roles (accept/run.sh `DEVN`, recorded in its receipt), never the test split.

## Wilson 95% intervals

`capability.txt` holds a Wolfram Language expression with the observed counts filled in:
`wilson[k_,n_]:=With[{z=Quantile[NormalDistribution[],0.975],p=k/n},N[{(p+z^2/(2n)-z Sqrt[p(1-p)/n+z^2/(4n^2)])/(1+z^2/n),(p+z^2/(2n)+z Sqrt[p(1-p)/n+z^2/(4n^2)])/(1+z^2/n)}]]`.
Evaluate it with the Wolfram tool (`mcp__wolfram__WolframLanguageEvaluator`); there is no wolframscript on the
Spark. DRA-124 rows get their Wilson interval from `accept sum` (Omega).

## Budget (MEASURED in the dry run, see below)

MEASURED in dry run dry3 (stage-A step 9850 served at T 4096, cores 4,6 shared with other work, 2026-11-07
07:27-07:59Z; `evidence/OMEGALLM/v4/run1/dryrun/`), per-unit figures, and MODELED totals for the final run
(Wolfram; linear in the measured per-unit times; a stage-B model that ends its turns with `<|end|>` should be
faster than stage A, which mostly generates to T):

| Step | MEASURED (dry3) | Unit | Final run (MODELED) |
|---|---|---|---|
| 0 build | 0.14 s | | 0.2 s |
| 1 identity | 2.8 s | 3 sha256 of 642 MB + mancheck | 3 s (plus a 642 MB copy for the control) |
| 2 xcheck | 48.9 s at W 1 (eval4 41.5 s incl. load) | eval4 window | W 64: about 44 min CPU (64 x 41.5 s, upper bound); chip geval4 about 5 s in a lease (run1 legs: GE 4.7-4.8 s) |
| 3 serve | 20.6 s (ready 2.6 s; 5 requests 6-20 s each) | | 0.5 min |
| 4 harness | 1,005 s for 5 tasks | Hermes task: 88-294 s, mean 192 s (TMO 300 s) | 30 train-new + 7 held-out + 2 controls = 39 tasks: 2.1 h at the mean, at most 3.25 h (TMO) |
| 5 accept | 700 s for 10 own dev items | p50 per item: assistant 13.5 s, coding 163 s, hive 24.4 s | t0 arm, own dev + test (54 assistant, 40 coding, 62 hive): 2.4 h (p50) .. 7.3 h (p95) + 18 harness tasks 1.0 h; each stochastic arm the same again; the 533 public IFEval/HumanEval rows (max_tokens 2048/1024) are not budgetable in one session |
| 6 demo | 112 s | one Hermes task | 2 min |
| 7 stop | 1.2 s | | |

Recommended final command (pre-registered arms cut explicitly; every cut is NOT_RUN in the report, never a
pass), about 6 h MODELED:

    OMC=/home/drakestapleton/workspace/hive-worktrees/arch-scale-x/omc/seed/out/omc ACCEPT_ENV="PUBLIC=0 REPEATS=0" \
      sh tests/omegallm/run1/eval.sh ~/work/hive/ownmodel/run1/ckB7300.bin B ~/work/hive/ownmodel/run1-eval/B7300 \
      > ~/work/hive/ownmodel/run1-eval/B7300.out 2>&1

Shorter: `TRAINN=10` (about 1.2 h less in step 4) or `STEPS="1 3 4 6"` first and step 5 in a second call.

## Operating notes (from the dry runs)

- Ports: :18296 and :18298 must be free for the whole run. `deploy/rehearse.sh` uses both and stops whatever
  listens on :18296 (it killed dry1's server); do not run the rehearsal gate during an evaluation.
- Hermes v0.22.5 refuses models under 64,000 tokens of context once it has learned the window from a
  `context_length_exceeded` reply (`context_length_cache.yaml` in HARNESS_HOME). `harness/hermes1.sh` moves
  that cache aside before every task (receipt `hermes.ctxcache`), so each task starts from the same Hermes
  state; step 4 fails if any task made no request to the server (`noreq.txt`). Real Hermes use of a T 4096
  ollm hits the same refusal: a deployment issue, not hidden by this pipeline (counted in `ctxcache.txt`).
- The first Hermes run in a fresh HARNESS_HOME installs its runtime (about 1 min, counted in the first task);
  Hermes also starts an idle-exit gateway in HARNESS_HOME that exits by itself after 600 s idle.
- A stage-A checkpoint is T 1024: step 3 serves a tune4 copy at T 4096 (parameters byte-identical, header step
  0); the stage-B checkpoint is already T 4096 B 4 and is served as is.
- `eval.sh` never edits itself mid-run, but do not edit it while a run is going: sh reads the script lazily.
