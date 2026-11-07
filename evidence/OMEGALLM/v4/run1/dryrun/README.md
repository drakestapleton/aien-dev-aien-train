# run1 evaluation pipeline: DRY-RUN STAGE-A (not the candidate)

Every result in this directory is **DRY-RUN STAGE-A (not the candidate)**: run1 stage-A checkpoint step 9850
(sha256 `8a94d7c3e473899168490cc1e3a39fa4f855c4565c5c974083ea62aef97c2482`, equal to run1 `geval.txt`
`step=9850 stage=A`; copied from `run1/ck.bin` at 06:35Z while leg 7 was still queued). Stage A has no tool-use
or chat training, so every capability number here is a floor, not the candidate's. The point of the run is
the pipeline: every step ran, met its protocol pass rule and produced its receipts.

Driver: `tests/omegallm/run1/eval.sh` (EVAL.md is normative), commit 048905d, script sha256 6dd4010a...
(the committed script differs only in step 2's rc capture, re-run below as `step2-rerun/`). ollm
`9e6441d4...` (feat/ollm-path-integ3 915d9b8 + this branch: no native change), verify `f1adcad1...`,
sftgen `22b1add4...`, accept `8c4fb0cb...`, mancheck `6d09b1e9...`, omc `2c824805...`. Cores 4,6; server
:18296, harness proxy :18298.

    OMC=<pinned omc> DRY=1 XW=1 STEPS="1 2 3 4 5 6" sh tests/omegallm/run1/eval.sh \
      ~/work/hive/ownmodel/evalprep/ck9850.bin A ~/work/hive/ownmodel/evalprep/dry3        # rc 0, fails 0

## Results (dry3, 2026-11-07T07:27:18Z .. 07:58:49Z)

| Step | Result | MEASURED ms | What ran |
|---|---|---|---|
| 0 build | PASS | 138 | 5 binaries from this checkout |
| 1 identity | PASS | 2,787 | `ck OLLMCK03 32768 1024 384 6 1536 8 16 9850 26745216 641885312 7cbfd48b0b64ba2e`, tok `OLLMTOK1 32768 920b3046a17db9be`, provenance found; neg flip refused (`MANCHECK FAIL checkpoint payload FNV differs from its header`) |
| 2 xcheck | PENDING_CHIP | 48,887 | code-path check only: **W 1, not the PREREG W 64**. tune4 to T 1024 B 16 G 1 (params identical, 213,961,728 bytes; copy sha256 bb1c3512..., byte-identical on the re-run), CPU `eval4` W 1 41,453 ms: `E 0 1 3805562 5490266`; chip command printed (`step2/chip-command.txt`), GPU not used |
| 3 serve | PASS | 20,600 | stage-A CK is T 1024, so a tune4 copy at T 4096 B 4 G 1 is served (params cmp-identical; header step reads 0); ready 2,569 ms; `/health` model = file identity (EQUAL); exe sha256 = built ollm; 5/5 requests HTTP 200, malformed body 400 |
| 4 harness | PASS | 1,005,122 | train-new 0/3 (s0 list_dir, s1 first_line, s2 mkdir_file), held-out 0/2 (t14 sha256, t16 replace_word); 0 tasks without a model request; 2 tasks found a learned Hermes context cache and reset it (see finding F2); pools regenerate byte-exactly; 30 new seed-20261109 tasks, 0 of them equal to any of the 20,500 seed-20261107/99 tasks; neg_seen caught |
| 5 accept | PASS | 700,261 | 10 own dev items (`SPLITS=dev DEVN=10 PUBLIC=0 REPEATS=0`, never the test split): assistant 0/3, coding 0/4, hive 0/3 (reasons rule=3, exec=4, rule=3); `accept sum` rc 3 = overall NOT_RUN (no test split); 0 conn rows |
| 6 demo | PASS | 112,370 | Hermes rc 0 after 91,871 ms, 1 model request (2525 prompt tokens, 99 generated), no tool call: **DEMO_FAIL** `directive.txt missing`; pre-check FAIL before Hermes; control d01x FAIL |
| 7 stop | PASS | 1,176 | server + 1 par worker stopped, :18296 and :18298 free |

Capability (verify.om / accept verdicts, DRY-RUN STAGE-A): Wilson 95% (Wolfram) train-new 0/3 [0, 0.5615],
held-out 0/2 [0, 0.6576]; DRA-124 dev rows from `accept sum`: assistant 0/3 [0, 0.5615], coding 0/4
[0, 0.4899], hive 0/3 [0, 0.5615]. Stage-A outputs are fluent-looking public-corpus text with no CHAT1 tool
calls (`step3/resp-*.json`, `step4/*/*/hermes.out`); Hermes stopped one turn as a repetition loop.

Step-2 compare logic (`step2-rerun/`, `CHIP_E` given by hand, **not a chip result**): a CHIP_E differing in
one digit gives `CHIP_E ... DIFFERS`, step FAIL, rc 1; the equal string gives EQUAL, step PASS.

## Negative controls (all behaved as required)

neg_flip (mancheck refuses a one-byte payload change), neg_shift (params cmp offset by one value differs),
malformed request 400, neg_seen (a training task renamed is caught), harness pre-checks FAIL before Hermes on
all 5 tasks + the demo, demo control d01x FAIL, CHIP_E mismatch FAIL.

## Findings from the earlier dry runs (`earlier-runs/`)

- **F1 port collision with the lead's gates.** dry1 (06:48Z) lost its server at about 07:12Z: the lead's
  `gates3.sh` (header: "ports 18291-18293, 18296-18298") ran `deploy/rehearse.sh`, which uses :18296 and
  :18298 and stops the pid listening there. My dry1 step 5 rows were all `conn` and step 6 found no server;
  eval.sh now records `SERVER_DIED rc=..` and fails a step on `conn` rows or a dead server. The rehearsal's own
  fail=21 at 07:16Z also overlaps my server (and its missing `ckA6000.bin`). The final run needs :18296/:18298
  free of rehearsals.
- **F2 Hermes v0.22.5 refuses a 4,096-token model once it learns the window.** After one
  `context_length_exceeded` reply (Hermes turn 2 grows past T 4096), Hermes writes
  `context_length_cache.yaml` (`ollm@http://127.0.0.1:18298/v1: 4096`) and every later run aborts before any
  request: "Model ollm has a context window of 4,096 tokens, which is below the minimum 64,000 required by
  Hermes Agent" (`hermes-refusal-managed-worker.txt`; dry1 t16 and the dry2 demo: 0 requests). The harness
  driver `hermes1.sh` now moves that cache aside before each task (kept as `hermes.ctxcache`), so each task
  starts from the same state. This is a deployment blocker in its own right: real Hermes use of ollm at
  T 4096 will hit the same refusal unless the served context reaches 64K or Hermes is configured otherwise.
- dry1's harness step under CPU contention: decode about 4 tok/s (1581 tokens in 389 s); dry3 about 9 tok/s.
