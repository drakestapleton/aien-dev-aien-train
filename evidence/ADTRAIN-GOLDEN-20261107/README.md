# evidence/ADTRAIN-GOLDEN-20261107: golden receipts in the adtrain suite, own gradient-check step

Kanban card t_e4d6c8e9 (Hermes worker, claude-opus-5-5, anthropic), 2026-11-07, DGX Spark
host (`host.txt`), cores 10-11 at nice 10 through `~/handoffs/hive/queen/pool-10-11.lock`.
No GPU. Follow-up of the DRA-14 replay (`evidence/ADTRAIN-REPLAY-20261107/`, card t_3dad9df7),
stacked on its branch head `7732a5f3a735d48c8e5bc62d7daa99351bb241e2`.

Inputs (`inputs.sha256`): adtrain compiler `seed/out/omc` from omega-mv `bf54b19f`, sha256
`62775d2a…712b` (the pin in `docs/adtrain/dependencies.json`); OMEGA = omega-mv
`19b8340d` (the #930 merge the replay pinned) and `6efc4572` (omega-mv main on Radicle at
the time of the run). Code under test: commit `50f40581131aa71af119fec9e999b788f817eb36`,
run from a clean worktree (`*/info.txt`: `dirty=0`).

## What changed

1. `docs/adtrain/golden.json` records the sha256 of PR #42's receipts `evidence/ADTRAIN/run/T.stdout`,
   `frozen/adtrain.ck.good` (the step-120 checkpoint of mode S) and `run/G.stdout`.
   `tests/adtrain/run-adtrain.sh` checks them after the T, G and S runs and fails as
   `golden-T-stdout`, `golden-G-stdout` or `golden-ck120`, also when the entry is missing or
   duplicated.
2. `tests/adtrain/main.om`: `dgc` takes its step from `dgeps` (1/64, its own constant) instead of
   `mllr`. 1/64 = 2^-6 is exact in binary32 (bits 0x3C800000) and 1/(2·(1/64)) = 32, the factor
   already in `dgc` (Wolfram `WolframLanguageEvaluator`: `{1/64 == 2^-6, 1/(2*(1/64))}` →
   `{True, 32}`; `BitShiftLeft[127-6,23] == 16^^3C800000` → `True`).
3. `tests/adtrain/replay/run-replay.sh`: G of the reference build against the receipt,
   `GOLDEN-PIN` (golden.json against the evidence files), `golden_G` per trainer mutant, and
   section 6 `GOLDCTL`, the negative controls in `tests/adtrain/replay/mutants-golden.txt`.

## Results

| run | result |
|---|---|
| `run-adtrain.sh`, OMEGA 19b8340d (`clean-suite-pin/`) | `ADTRAIN_SUITE_PASS`; `golden.txt` want = have for all three |
| `run-adtrain.sh`, OMEGA 6efc4572 (`clean-suite-main/`) | `ADTRAIN_SUITE_PASS` |
| `run-replay.sh`, OMEGA 19b8340d (`clean-replay-pin/`) | `REPLAY_PASS fail=0 invalid=0 gap=2` |
| `run-replay.sh`, OMEGA 6efc4572 (`clean-replay-main/`) | `REPLAY_PASS fail=0 invalid=0 gap=2`, verdict lines identical to the pin run |
| control: base `7732a5f3` replay, OMEGA 943d9555 (`base-replay/`) | `REPLAY_PASS fail=0 invalid=0 gap=5`, as reported by t_3dad9df7 |
| control: base `7732a5f3` suite, OMEGA 943d9555 (`base-suite/`) | `ADTRAIN_SUITE_PASS` |

G output unchanged: `run/{T,G,D,R,S}.stdout` of the branch (`clean-suite-pin/run-stdout.sha256`)
are byte-identical to the base (`base-suite/run-stdout.sha256`); `G.stdout` sha256
`dcfead80…feba` equals PR #42's receipt. The C M21 host arm reads `exact=75/75 max_ulp=0
verdict=PASS` with the mutant-sign control failing, identical to the base. The CK, CKMUT,
TAPEMUT and PADPROBE lines of the replay are identical to the base replay.

Trainer mutants (`clean-replay-pin/replay.txt`, last line of each suite in `suite-*.last`):

| mutant | before (base) | now |
|---|---|---|
| m-lr32 | KILLED by `gradcheck` (only through ε = lr) | KILLED by `golden-T-stdout`; its G output equals the receipt (`golden_G=SAME`), so the gradient check no longer depends on lr |
| m-db2-index | KILLED by `gradcheck` | KILLED by `golden-T-stdout` (T runs first; G also differs, rc 1) |
| m-skip-last-param | SURVIVED (GAP) | KILLED by `golden-T-stdout` |
| m-hash-T15 | SURVIVED (GAP) | KILLED by `golden-ck120` (T and G equal the receipts) |
| m-lr-update-only | SURVIVED (GAP) | KILLED by `golden-T-stdout` |
| m-no-fsync | SURVIVED (GAP) | SURVIVED (GAP): T, checkpoint and G equal the receipts; not observable on the host |

The other remaining GAP is `t-e1-pad-pos0` (omega-mv `tape-test.om`, PADPROBE: sum of four
−0 is +0 in the mutant, −0 in the pinned tape), which belongs to omega-mv.

Negative controls (`GOLDCTL`, all PASS in both clean replays; `gsuite-*.last`):

| control | edit | suite ends |
|---|---|---|
| g-T-hex / g-ck-hex / g-G-hex | last hex digit of one golden sha256 | `ADTRAIN_SUITE_FAIL golden-T-stdout` / `golden-ck120` / `golden-G-stdout` (observed sha printed) |
| g-ck-missing | ck entry renamed | `ADTRAIN_SUITE_FAIL golden-ck120 (no single golden.json entry)` |
| g-T-dup | G entry renamed to the T gate | `ADTRAIN_SUITE_FAIL golden-T-stdout (no single golden.json entry)` |
| e-h128-scale64 | step 1/128 and factor 64 (a consistent central difference) | gradcheck passes (58 rows), `ADTRAIN_SUITE_FAIL golden-G-stdout` |
| e-h32 | step 1/32, factor unchanged | `ADTRAIN_SUITE_FAIL gradcheck` |
| e-eps-mllr | `eps = mllr` restored | `ADTRAIN_SUITE_PASS` (same value, same G bytes) |

Controls of the replay itself (`ctl-goldctl/`, `ctl-goldpin/`, each a worktree of `50f40581`
with one edit): a wrong GOLDCTL expectation (e-eps-mllr expected to fail) gives
`GOLDCTL e-eps-mllr … FAIL` and `REPLAY_FAIL fail=1 invalid=0 gap=2`, exit 1; one hex digit
of the ck sha256 changed in `golden.json` gives a `GOLDEN-PIN golden-ck120 … FAIL`, an
INVALID g-ck-hex setup and `REPLAY_FAIL fail=2 invalid=1 gap=1`, exit 1.

Zero-legacy closure (aien-architecture-mv `4c195641` `tools/zero-legacy/closure.om`,
omc `734f0a39`, release mode; `zero-legacy/`): base and branch both rc 1 (pre-existing),
`OUTSTANDING 103`, `UNKNOWN 876` on both. The only new rows are `DATA docs/adtrain/golden.json`
and `DOC tests/adtrain/replay/mutants-golden.txt`. This directory is declared `data` in
`.zero-legacy`.

## NOT_RUN

GB10 arm, any GPU execution, x86, crash durability of the checkpoint (m-no-fsync), the
omega-mv `tape-test.om` padding fix (t-e1-pad-pos0, separate follow-up), performance.
The golden values bind this compiler pin and these dependencies: a deliberate change of
either needs new receipts and a new `golden.json`.
