# Rung 7: the v2 shape (D 384, F 1536) beats rung 6 on the same data, seed and schedule (aien-train#52)

Rung 6 (`../gpu-r6/`) trained the largest v1 shape (D 256, F 1024, H 8, P 7,409,920) for 30000 steps
and ended at a chip `geval` of 1.338156 nats (0.499194 bpb) on `held.tok`. Rung 7 widens the model
under a new contract (`docs/omegallm/CONTRACT-V2.md`: D ≤ 384, F ≤ 1536, nothing else changes) and
trains V 4096, T 256, D 384, H 12, F 1536, L 8, B 64 (P 15,833,472, 2.137× rung 6, Wolfram) with the
same seed, data, learning-rate schedule, batch and step count. The held-out measure is the same: chip
`geval` of `held.tok`, W 2243 windows at T 256, `merges4096.bin`.

Status: EXERCISED on one GB10 and on host CPU. Not QUALIFIED, not MERGED. All 12 training windows were
opened `--gb10 shared --quiet none`; `spark-window` printed "quiet machine" for each, but the quiet
lock was not taken, so timings are labelled non-quiet (last close, `run/close.json`: load average 2.96).

## Result

| step | rung 7 (v2) nats | rung 6 (v1) nats | Δ µnats | Δ % |
|---|---|---|---|---|
| 250 | 2.773849 | 2.840107 | −66,258 | −2.33 |
| 2000 | 1.756935 | 1.797226 | −40,291 | −2.24 |
| 9000 | 1.432166 | 1.502144 | −69,978 | −4.66 |
| 30000 | **1.254741** (0.468077 bpb) | 1.338156 (0.499194 bpb) | **−83,415** | **−6.23** |

(Δ by WolframLanguageEvaluator: `{2773849,1756935,1432166,1254741}-{2840107,1797226,1502144,1338156}`.)

Full rung-7 curve (`run/geval.txt`): 250 2773849, 2000 1756935, 5000 1538276, 8000 1451128,
9000 1432166, 12000 1385827, 15000 1354082, 18000 1327337, 21000 1305437, 24000 1285618,
27000 1268895, 30000 1254741. At step 18000 (60% of the tokens) rung 7 is already 10,819 µnats below
rung 6's step-30000 value. The last leg (27000→30000) still gained 14,154 µnats, so the curve has
not flattened.

## Pre-registered predictions (`run/prereg.txt`, written before the first training window)

| prediction | receipt | result |
|---|---|---|
| P1 final E < 1338156 | `run/geval.txt` step 30000: E 30000 2243 1254741 468077 | PASS (−6.23%) |
| P2 stop rule: step-2000 E < 1797226 | E 2000 2243 1756935 655418 | PASS |
| P3 below rung 6 at 250, 2000, 9000, 30000 | table above | PASS (4/4) |
| P4 chip geval curve strictly decreasing | 12 points, each below the last | PASS |
| P5 CPU `eval` of ck30000 within 10 µnats of the chip | `run/eval30000.txt`: E 30000 2243 1254741 468077, rc 0 (bin 6da13670…, ck 378d5a2d…, core 9, nice 19, 15,370.9 s non-quiet) | PASS (Δ 0, identical line) |
| P6 summed `gtrainf` wall 250→30000 < 11,219 s | 7,110.6 s (modeled 7,930.6 s) | PASS |

Timing (wall clock between the ns stamps around each `gtrainf` in `run/train.txt`, includes
checkpoint load and save; WolframLanguageEvaluator): 250→30000 took 7,110.6 s, 0.23901 s/step,
68,549 tokens/s, about 6.51 TFLOP/s by the 6·P·tokens rule (attention excluded). Legs ranged
0.23547-0.24809 s/step. The whole run including the 0→250 leg is 1.99 h of chip time. Each `geval`
took 5.44-5.56 s (GE). Rung 6 ran on the pre-k1 binary 576bf296 (0.3771 s/step); the speed gain is
the k1-k9 kernel rounds (`../gpu-k1/`…`../gpu-k9/`), not the shape. On the same k9 kernels the v2 step
costs about 1.7× the v1 step (gate G7 below).

What this does not show: it compares equal steps and tokens (491,520,000 tokens, 31.0 tokens per
parameter for v2 vs 66.3 for v1). A v1 run given the same chip time on today's kernels (about 45,800
steps at the gate G7 rate of 0.1554 s/step, Wolfram `7110.62/0.1554 -> 45756.9`) was not run, so
"v2 beats v1 at equal chip time on k9 kernels" is NOT_RUN. Rung 6 with its actual 11,219 s did lose
to rung 7's 7,110.6 s.

Determinism check: the step-250 checkpoint of the training run (sha256 1ab162bf…, `run/geval.txt`)
equals the step-250 checkpoint made in gate window gg-r7g (`gate1/`), in a different window 30 minutes
earlier.

## Setup

- Source: this commit's `native/omegallm/` (v2 storage split in `model.om`, `adam.om`, `ckpt.om`;
  GPU RMS register banks and caps in `gpu/gr.om`; `ggfs` capacity in `gpu/gg.om`). omc 2c824805…
  (omega-mv e5b32567). Builds in `build.txt`: GB10 `ollm-gb10` 1853303e…, mutant r 360f3bd9…, CPU
  `ollm` 6da13670….
- Init: `ollm init ckL0.bin 4096 256 384 12 1536 8 64 1 30000 3000 16`, sha256 fc8835fe…. The same
  command as rung 6 with D 256→384, H 8→12, F 1024→1536.
- `run/drive.sh` opens one `spark-window` per leg (lease 22 min) and posts STARTING/DONE board lines.
  `run/leg.sh` trains 0→250, then 3000-step legs that stop exactly at 2000, 9000 and 30000, then runs
  `geval` of the saved checkpoint. `run/prereg.sha256` holds the hashes taken before the first
  window; the committed `leg.sh` differs from the hashed file only by the home prefix replaced with
  `~/`. The first `drive.sh` call printed `cannot open windows.txt` (its resume count before the file
  existed; it then counted 0, as intended).
- Checkpoints are kept outside the repository (380,003,448 bytes each); hashes in
  `run/checkpoints.sha256`.

## Gates before the run

CPU (host, nice 19):
- `tests/omegallm/core-receipts.sh` on this tree: 48/48 PASS; the name/rc/expect rows
  (`cpu/core-summary.tsv`) equal the committed `../core/summary.tsv`.
- `tests/omegallm/v1-oracle.sh` with the v2 limits: `cpu/v1-oracle.txt`, pass=54 fail=0 not_run=1
  (the v0→v1 checkpoint case needs a v0 binary). D 386 and F 1537 refuse with exit 12; D 384, F 1536
  is accepted with its files checked against the referee (`limit-max-d384-f1536`).
- One v2 training step: max RSS 785,280 kB (`cpu/rss-train.txt`).
- v1-shape GPU code: `gpu-code.bin` and `gpu-gpr.bin` at the rung-6 shape are byte-identical before
  and after the v2 edits (`build.txt`).

Chip, window gg-r7g (`gate1/`, prereg written first): G1 (v1 r6 final E line reproduced), G2 (t200 v1
checkpoint bit-identical), G8 (gacmp at v2) and G9 PASS. G3 was a mis-stated prediction (it included
`gpu_ns`, a timing field). G4/G5 FAILED: `gcmp2` at the v2 maximum trapped (exit 103, BOUNDS) because
the host scratch `ggfs` in `gpu/gg.om` held 1024 rows < F 1536. G6 FAILED: v2 init E 0 8.398671 was
0.080905 above ln 4096, over a 0.05 bound. G7 (report only): 250 v2 steps took 0.2666 s/step against
0.1554 for v1 200 steps on the same kernels, ratio 1.715 (Wolfram). The run did not start.

Fix and re-gate, window gg-r7g2 (`gate2/`, new prereg): `ggfs` 1536. H1 `gcmp2` at the v2 maximum PASS
(rel1 991e-9 vs tolerance 122070e-9; chip loss = CPU loss 8408630), H2 mutant r caught (rc 47, 4
fails), H3, H5 (v1 r6 final E line), H6 (v1 t200 checkpoint bit-identical) and H7 PASS. H4 FAILED:
the replacement for G6, written after G6 missed and disclosed in the prereg, asked the v2 init E 0
to sit within 50000 µnats of the v1 init (8344166); it is 54505 above.

H4 follow-up (`cpu/refeval-w1.txt`, host CPU): the Python referee (`oracle.py ollm eval`) and the
product (`cpu/ollm eval`) give the same line on window 0 of the v2 init, `E 0 1 8416208 3083688`.
With the init bytes equal to the referee's and H1's chip loss equal to the CPU loss, the init loss is
the contract's init (uniform, sd 0.02, independent of D) at a wider model, not a v2 defect; the 50000
bound had no derivation. `gate2/REPORT.txt` records the decision to start rung 7 despite H4, written
and hashed into `run/prereg.sha256` before the first training window. It is a departure from the
gate-2 run-start rule and is disclosed here; the run's own predictions P1-P6 were not changed.
