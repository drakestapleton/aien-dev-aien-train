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
| 4 | harness | (a) `sftgen TRAINSEED TRAINN` WORLD output = new instances of the TRAIN families in TASKS.md format (default seed 20261109, 30 tasks); `sftgen 20261107 20000` and `sftgen 99 500` are regenerated and must hash to run1's `sft-train.jsonl` / `sft-val.jsonl` (DATA/sft.sha256), and any new task whose @file/@prompt/@expect content equals one of those 20,500 tasks is dropped (`SEEN`); (b) `tasks.txt` held-out t14-t20 and controls c01 c02. Both through `harness/run.sh http://127.0.0.1:PORT/v1` (Hermes v0.22.5 `-t terminal --max-turns 4`, TMO 300 s, proxy PPORT); verify.om verdict per task | pools regenerate byte-exactly; no INVALID or SETUP_FAIL row (each pre-check FAILed before Hermes ran); controls c01, c02 FAIL; **negative control**: the first training task, renamed, must be caught as SEEN | `step4/unseen.txt`, `pools.txt`, `train-new.txt`, `{train,heldout}/summary.txt` (rows `ID FAMILY SPLIT RESULT rc ms chats first_status`), per-task `prompt.txt pre.txt hermes.* verify.txt wire/ work/`, `capability.txt` (counts + the Wolfram Wilson expression) |
| 5 | accept | `tests/omegallm/accept/run.sh 127.0.0.1 PORT AOUT run1-STAGE-CK8` with HARNESS (this checkout's harness dir), VERIFY, HPPORT=PPORT; default splits `dev test`, PUBLIC 1, REPEATS 3 (the DRA-124 PREREG protocol; `ACCEPT_ENV` may cut arms, e.g. `REPEATS=0`, and any cut is NOT_RUN in the report) | runner rc 0 path (no `runner failed`, no hash mismatch) and a `t0.summary` exists; AOUT's parent is mode 700 | `step5/command.txt`, `receipt.txt`, `t0.summary`, `s*.summary`, `pair-*.tsv` (aggregate rows only); transcripts stay in AOUT |
| 6 | demo | a task file with `d01`: "Create a file named directive.txt whose content is exactly: use your best judgement and get this done" (Drake's public hive directive) run through `harness/run.sh` (real Hermes, real tool execution, the served model); then `verify check` re-run on the copied work dir | the pre-check FAILed before Hermes ran; **negative control**: the same work dir against a deliberately different text (`d01x`) must FAIL | `step6/demo.txt`, `run/` (hermes.out, wire/ = every request and raw response, work/), `verify-d01.txt`, `verify-d01x.txt`, `serve-lines.txt` (the server log lines of the demo), `session.jsonl` + `session-md/` (Hermes's own session export), `result.txt` (DEMO_PASS / DEMO_FAIL: capability) |
| 7 | stop | kills the server pid and its par workers (also on any exit, via trap), deletes the serve copy | no process left, PORT and PPORT free | `summary.txt` |

Dry-run subsets (`DRY=1`): step 4 runs the first 3 train-family tasks of distinct families and held-out t14
t16 (no controls); step 5 runs `SPLITS=dev DEVN=10 PUBLIC=0 REPEATS=0`: 10 own dev items taken round-robin over
roles (accept/run.sh `DEVN`, recorded in its receipt), never the test split.

## Wilson 95% intervals

`capability.txt` holds a Wolfram Language expression with the observed counts filled in:
`wilson[k_,n_]:=With[{z=Quantile[NormalDistribution[],0.975],p=k/n},N[{(p+z^2/(2n)-z Sqrt[p(1-p)/n+z^2/(4n^2)])/(1+z^2/n),(p+z^2/(2n)+z Sqrt[p(1-p)/n+z^2/(4n^2)])/(1+z^2/n)}]]`.
Evaluate it with the Wolfram tool (`mcp__wolfram__WolframLanguageEvaluator`); there is no wolframscript on the
Spark. DRA-124 rows get their Wilson interval from `accept sum` (Omega).

## Budget (MEASURED in the dry run, see below)

DRYRUN_TIMING_PLACEHOLDER
