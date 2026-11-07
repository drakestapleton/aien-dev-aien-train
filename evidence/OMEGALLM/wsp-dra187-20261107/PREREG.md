# DRA-187 pre-registration: one targeted weight edit against a demonstrated failure

Written and committed 2026-11-07 before any intervention, edit or held-out evaluation. Owner: lane wsp
(omp, tmux `wsp`). Linear DRA-187. Nothing below may change after this commit except by a new dated
section that says what changed and why; results that follow a change are labelled with it.

## 1. Model, failure and evidence so far

- Model: the deployed round40 Omega tool model, `~/.local/share/omega-tool-model/round40/model.ck`, sha256
  `7c7b5b5260f2d9453b6076b64e7f23e88341d96498584f2dfaa229c31ad2e346` (OLLMCK02, V 4096, T 256, D 384,
  H 12, F 1536, L 8, P 15,833,472, step 600), tokenizer `merges.bin` sha256 `73a29baf97619a74…`. Read in place,
  never written. Edited checkpoints are separate files under `~/work/wsp/ck/`.
- Failure (MEASURED by others, cited): in its first `read_file` action the model truncates long numeric file
  IDs. round40 copy grid (`round40/grid-selected.json`, unread state): `jobs/item` with 6 digits 7/18 exact;
  round41 diagnosis (`round41/c2/diag/TABLE.md`, round40 column, failed-state prompts): 7 digits 0/24,
  8 digits 0/24, 3 to 5 digits 66/66.
  The second failure in the same grid (stem substitution, `examples/unit` 0/72) is NOT the target: it needs a
  token mapping the model lacks (round41 RESULTS, C5/C6), which is new knowledge rather than a misrouted signal.
- Diagnosis so far (MEASURED, `wprobe probe`, one record `jobs/item234567.om`, before this file): at the
  answer position after `…6` the model predicts `.` (logit 21.02) over the correct `7` (17.52), gap -3.49.
  Heads 6.6, 6.11, 7.11 and 7.0 attend 0.56 to 0.70 to the prompt's `7` and push `7` by +5.52, +5.12, +4.81,
  +3.01; the MLPs of layers 0, 3, 4, 5 and 7 push `.` (-7.46, -3.60, -9.47, -5.68, -6.32). The readout
  parts sum to the logit gap within 2e-4. Reading: the copy circuit finds the right digit, and a
  number-length prior written by many MLP neurons outvotes it.

## 2. Tools (first-party `.om`)

- `tools/omegallm/wprobe/wprobe.om` (this branch), built by `tools/omegallm/wprobe/build.sh` with omc
  sha256 `2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f` (omega-mv `e5b32567`). Binary
  sha256 `9ca14368c5f0217d9d4d57de25ad3729ee9e273b98fc60ecf6a6c53fbb0de2e4`.
  - `gen`: greedy decoding with the model.om row kernels and a reused prefix. MEASURED parity: identical
    bytes to `ollm sample … 0` on 4 records and to the recorded round40 GPU outputs for the 3 grid records;
    hook kind 5 (f32 rounding) gave identical output on the same 4 records. About 5 s a record on one core.
  - `probe`: teacher-forced readout (logit-gap decomposition, head and neuron parts, attention).
  - Hooks: weight scaling of a head's `wo` rows (1) or a neuron's `w2` row (2), answer-row activation
    scaling of a head (3), a digit-conditioned logit penalty (4), f32 rounding of every weight (5).
    Negative argument tests exit 2 (9 cases MEASURED).
- `tools/omegallm/wpatch/` (lane wsp, separate PR): the checked patch format that records, applies,
  verifies and reverts the selected edit. The final edited checkpoint is produced and reverted through it.
- External instruments (Python, not product): `make_splits.py`, `score.py`; Wolfram for every statistic.

## 3. Splits (sha256 of the generated files; generator `make_splits.py` sha256 `1e58c7a3…efdebe`)

| Split | Use | Rows | Content | JSON sha256 |
|---|---|---|---|---|
| D | diagnosis, causal tests, readouts | 372 | round40 copy grid (144) + round41 d-item diagnosis (228), existing files | existing files |
| S | edit selection (and decoding-penalty selection) | 96 | fresh IDs, `jobs/item` + 6/7/8 digits ×24 (target), 3/4/5 ×8 (control) | `bf846f8b…dbc1e20` |
| H | locked held-out, evaluated once per arm at the end | 288 | fresh IDs, 6/7/8 ×64 (target), 3/4/5 ×32 (control) | `75ef8489…c7cd06c` |
| G | secondary generalisation, no gate | 96 | fresh `hello<ID>` print tasks (round40 copy-final form), 6/7/8 ×24, 4/5 ×12 | `06398f29…77dbf44` |

All IDs are absent from every JSON under round40/data and round41 and disjoint across S, H and G. Prompts
use the 47 Task lines and 3 Goal forms of the round40/round41 copy prompts with fresh Goal numbers.
H and G are not run on any arm until the edit, the decoding penalty and the control edits are frozen in
a later commit.

## 4. Search space (fixed now; selection on S only)

Every candidate is a scaling edit with no gradient. Families:
- E1 copy-head gain: `wo` rows of the k heads with the largest mean positive part on D failure rows,
  k in {1, 2, 3, 4}, scale α in {1.10, 1.25, 1.50, 1.75, 2.00}.
- E2 length-prior suppression: `w2` rows of the m neurons with the most negative mean part on D failure
  rows, m in {4, 8, 16, 32}, scale β in {0.75, 0.50, 0.25, 0.00}.
- E1+E2: the best E1 and best E2 combined, one candidate.
Head and neuron rankings come from `wprobe probe` on D failure rows only. At most 40 candidates on S.
Selection rule: highest S target exact count among candidates with S control exact ≥ base S control
exact; ties go to fewer changed weights, then smaller |scale - 1|.

## 5. Causal test before any edit (on D, recorded before the search)

Prediction P1: scaling the output of the top copy heads up (activation hook 3, ×1.5, answer rows only)
raises 6/7/8-digit exact copies on D. Prediction P2: zeroing them (×0) breaks 3/4/5-digit copies on D
that the base model gets right. Both are run and reported, PASS or FAIL, before section 4 starts. If
neither holds, the copy-head reading is wrong and E1 is dropped (E2 still runs).

## 6. Arms evaluated on H (and G), greedy, 64 tokens

1. Base (round40, unchanged).
2. Selected edit, in the deployed representation (weights rounded to f32, hook 5), and in f64.
3. Decoding adjustment: logit penalty on `.` (token 46) after a digit token, value b chosen on S from
   {1, 2, 3, 4, 6, 8} with the same rule as section 4.
4. Fine-tune comparators (ownmodel/DRA-147 lease, already trained, read in place): round41 C2 step1000 and
   step2000 (`round41/c2/checkpoints/`); their training cost is cited from round41 RESULTS.
5. Control edits: the selected edit's operation applied to randomly chosen heads (E1) or neurons (E2) of the
   same layers, excluding the selected ones, with scales matched so the Frobenius norm of the weight change
   equals the selected edit's within 1%; 3 seeds (187101, 187102, 187103).

## 7. Acceptance (primary, on H, deployed representation)

- Gain: target exact (lengths 6 to 8, 192 rows) of the edit minus base ≥ 25 percentage points AND exact
  one-sided McNemar (binomial on discordant pairs) p < 0.01.
- Locality: control exact (lengths 3 to 5, 96 rows) of the edit ≥ base minus 1.
- Control edit: each of the 3 control edits gains < half the selected edit's gain on H targets.
- Numerical validity: every changed weight finite, |w| ≤ 1e6; f32-surviving changed entries counted and
  reported; the f32 and f64 arms agree on ≥ 95% of H rows.
- Retention (round40 gates, GPU batch harness under a posted reservation): 8-action screen 8/8, dev-jobs
  logic/controls/pairs not below round40's 72/12/24, regression 685/685, retention 847/847, copies 64/64,
  story W256 loss ≤ round40 × 1.0025. If the GPU reservation is not granted these are NOT_RUN and the
  result cannot be IMPROVE.
- Latency: the edit changes no shapes; per-token GPU latency of the edit within 2% of base on the same
  harness (MEASURED with the retention run), CPU `gen` wall time per record reported.
- Restore: `wpatch revert` reproduces the base checkpoint byte for byte (sha256 equal to `7c7b5b52…e346`).

Outcome labels: IMPROVE (all primary and retention gates pass), RETAIN-FAIL (gain passes, a retention or
locality gate fails), REJECT (gain fails). A negative outcome is reported as such.
Secondary (no gate): G target exact, comparator ranking, the optimizer-state policy check (section 9).

## 8. Compute limits

- Diagnosis + causal tests + search: at most 40 CPU core-hours on pool cores (`flock` pool locks,
  `taskset`, nice 10), no gradients, no GPU.
- Held-out evaluation: at most 10 arms × (288 + 96) records on CPU (about 6 core-hours).
- GPU: only for the final retention gates, at most 2 hours under a reservation posted on the BOARD and
  coordinated with ownmodel. Never :18091; never the round40-fast server process.
- Agent and wall time are logged in `COSTS.md` with every run (start, end, cores, records).
- Energy: whole-system wall energy BLOCKED_INPUT (no qualified meter); GPU/SoC telemetry, where read, is
  labelled partial.

## 9. Optimizer-state policy (separate check, secondary)

The edited checkpoint keeps Adam m and v unchanged (wpatch policy 0). Check: one CPU `ollm train` step from
the edited checkpoint under policy 0 and policy 2 (zero m and v of changed entries), on round40 training
data, measuring how much of the edit survives the step. Reported; not a gate.

## 10. Promotion

Only an IMPROVE result is offered to ownmodel's promotion path (DRA-146/DRA-183 owner) with the patch,
receipts and review. This lane does not install, deploy or restart any service.
