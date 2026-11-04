# GB10 GPU training receipts (aien-train#52, rung 4)

Every chip run here went through `spark-window` with `--gb10 shared --quiet none`: other lanes and the
CPU night run `ollm-night` (cores 0-19, nice 19) were live. spark-window still printed "verdict for its
timings: quiet machine"; that verdict does not apply to a window opened with `--quiet none`. **Every
time below is non-quiet.** Status: EXERCISED on one DGX Spark GB10, not QUALIFIED. Nothing here is CUDA:
the kernels are SASS emitted by `native/omegallm/gpu/gk.om` and `gr.om` and launched by `launch.om` on
the raw driver. nvdisasm 13.0.85 is the read-only oracle for the emitted code (`disasm-slot23-24.txt`,
reproduced by `sh tests/omegallm/gpu-disasm.sh 23 24`).

`build.txt` lists every binary and source sha256. Data: `v1-data/train.dec` (small checkpoint, batch
index 3) and `v1-data/train.tok` (night checkpoint, batch index 7); held-out eval
`held.tok 4486 merges4096.bin`.

## Windows

| window | name | ran |
|---|---|---|
| 20261102T031634Z-621b44 | gg-night | `probe/gc-*-ogg*.txt`, `probe/gx-night.txt` |
| 20261102T034237Z-eba1bd | gg-kink | `probe/gy-night.txt` |
| 20261102T035547Z-9b5d74 | gg-train1 | `probe/gz-night.txt`, `gtrain1.txt` |
| 20261102T035842Z-4e4e61 | gg-train2 | `gc-small*.txt`, `gc-night.txt`, `gc-night-mut-g.txt`, `gtrain2.txt` |
| 20261102T041247Z-447f07 | gg-train3 | `gtrain3.txt` |
| 20261102T042848Z-a0e98e | gg-adam4 | `gc-night-371ff177.txt`, `ga-*.txt`, `gtrainf-2000-5000.txt` |
| 20261102T043306Z-d91236 | gg-full5 | `gtrainf-0-9000.txt` |

`probe/fl-night.txt` ran on the CPU only. Window records: `~/yardsticks/windows/<id>/` on the Spark.

## Gradient gate: `gcmp`

`gcmp CK DATA S` computes the batch-S loss and gradient twice, on the CPU in f64 (`ograd`) and on the
chip in f32 over all R = B T rows at once, and prints
`GC P maxabs_e12 maxref_e12 rel_e9 cpu_loss_micro gpu_loss_micro gpu_ns tol_e9`. PASS needs
rel = maxabs / maxref < tol and |Δloss| < 1e-5; FAIL exits 45. tol = R·2^-24 (γ_R to first order), the
error bound of an f32 sum of R terms relative to the sum of magnitudes; R is the longest reduction in
the weight gradients. Small: R = 64, tol 3.815e-6. Night: R = 5120, tol 3.05176e-4.

| receipt | P | rel | tol | result |
|---|---|---|---|---|
| `gc-small.txt` | 84288 | 2.35e-7 | 3.815e-6 | PASS rc 0 |
| `gc-small-mut-g.txt` (mutant g: DK = −DSᵀQ) | 84288 | 4.41e-3 | 3.815e-6 | FAIL rc 45 |
| `gc-night.txt` | 2582208 | 1.614e-4 | 3.05e-4 | PASS rc 0 |
| `gc-night-mut-g.txt` | 2582208 | 1.079 | 3.05e-4 | FAIL rc 45 |
| `gc-night-371ff177.txt` (binary with on-chip Adam) | 2582208 | 1.614e-4 | 3.05e-4 | PASS rc 0, same GC fields as `gc-night.txt` |

### Why the gate is γ_R and not 1e-4

The first night-shape run (`probe/gc-night-ogg.txt`, earlier binary, fixed tol 1e-4) failed at
rel 1.61e-4 with |Δloss| 7e-6, while the small shape passed at 2.35e-7. The diagnostics:

- `probe/gx-night.txt`: the per-parameter-segment `GS` lines put the maximum, 7772936e-12, in the
  segment starting at parameter 1844352.
- `probe/gy-night.txt`: that maximum sits in weight column 408 (`WC 408 7772936`), and the `NZ` lines
  list ReLU units whose f64 pre-activation is within f32 resolution of zero; unit 408 is one of them.
  Rounding puts such a unit on the other side of the kink on the chip. Both sides are valid
  subgradients, so this is not a defect in either path.
- `probe/gz-night.txt`: with the CPU forced to the chip's side of those kinks, maxabs falls to
  3410257e-12 and rel to 7.08e-5.
- `probe/fl-night.txt`: the CPU gradient computed with f32 rounding against the f64 one, the floor any
  f32 implementation meets on this shape.

The probe binaries are throwaway builds whose sources are not in the tree; their receipts are kept as
the record of the diagnosis only. The γ_R gate replaced the ad hoc 1e-4. γ_R is a rounding bound and
cannot cover a kink: a unit whose pre-activation the two paths put on different sides of zero changes
the gradient by a full term, not by rounding. On this shape the kink error happened to fit under γ_R;
on the rung-5 shape it does not (`../gpu-max/gc-max.txt`, rel 1.58e-4 against γ_R 1.22e-4). The kink
case is now checked by `gcmp2`, branch-conditioned parity (`../gpu-max/README.md`), which reruns this
shape as `../gpu-max/gc2-night-s7.txt`.

## On-chip Adam gate: `gacmp`

`gacmp CK DATA S` takes one step from CK with the chip gradient, once with `oadam` on the CPU in f64 and
once with `ggadam` (SQN partial sums of g², clip, schedule and bias corrections on the host in f64, then
the ADAM kernel, slot 24) on the chip in f32. It prints
`GA P maxd_e12 maxu_e12 rel_e9 resid_e9 tol_e9 adam_ns loss_micro`. With w0 the parameter before the
step, c the CPU result and g the chip result: u = c − w0, d = (g − f32(w0)) − u; resid =
max(|d| − 2^-24|c|) / max|u|, the part of d above the half-ulp rounding of the f32 master weight.
PASS needs resid < 2^-16; FAIL exits 46. The mutant h binary uses β1 = 0.8 in the kernel.

| receipt | step in CK | rel | resid | Adam on chip | result |
|---|---|---|---|---|---|
| `ga-small.txt` | 0 | 1.957e-3 | 2.34e-7 | 0.341 ms | PASS rc 0 |
| `ga-small-mut-h.txt` | 0 | 1.957e-3 | 2.34e-7 | 0.357 ms | PASS rc 0 (see below) |
| `ga-night.txt` | 1000 | 1.53e-5 | 1.28e-7 | 0.808 ms | PASS rc 0 |
| `ga-night-mut-h.txt` | 1000 | 0.114 | 0.114 | 0.692 ms | FAIL rc 46 |

The small checkpoint is at step 0, so m = 0 and m ← β1·m + (1 − β1)·g does not depend on β1 on its
first step; mutant h is invisible there by construction (identical GA fields). The night checkpoint
(step 1000, m ≠ 0) is the negative control, and it fails. The raw rel of the small case is the half-ulp
rounding of f32 weights near 1 against a first-step update of about 3e-5; resid removes it.

## Training

`gtrain CK TRAIN UNTIL EVERY` is `train` with the gradient from the chip and Adam on the CPU in f64
(upload f32 weights, download the gradient every step). `gtrainf` keeps parameters and Adam moments on
the chip in f32 and uploads only the batch; at save points the state comes back to f64 for the
checkpoint. Both print `T step loss_micro` at save points, like `train`. Times are wall clock between
the ns stamps on the first and last lines of each receipt (WolframLanguageEvaluator arithmetic).

| receipt | binary | steps | wall | per step |
|---|---|---|---|---|
| `gtrain1.txt` | 3568922 | 1750→2000 | 62.0 s | 0.248 s |
| `gtrain2.txt` | 3568922 | 2000→5000 | 720.6 s | 0.240 s |
| `gtrain3.txt` | 3568922 | 5000→9000 | 941.4 s | 0.2354 s |
| `gtrainf-2000-5000.txt` | 371ff177 | 2000→5000 | 161.0 s | 0.05367 s |
| `gtrainf-0-9000.txt` | 371ff177 | 0→9000 | 483.8 s | 0.05375 s |

gtrain legs 1-3 started from a copy of the night run's step-1750 checkpoint; `gtrainf-2000-5000`
started from gtrain's step-2000 checkpoint (sha256 295e7999…ec65) and `gtrainf-0-9000` from a copy of
the night run's init checkpoint `v1-night/ck0.bin` (sha256 d2efaf93…e42b). Phase times from the GT line
of `gtrainf-0-9000.txt` (last step, ns): upload 0.64 ms, forward 19.4 ms, backward 27.0 ms, loss
1.0 ms, Adam 0.71 ms.

Trajectories (batch losses, so noisy):

- `gtrainf-2000-5000` against `gtrain2` at the same 12 save points: max relative difference 0.34%,
  mean 0.15%. Same start, same batches; the paths differ in f32 against f64 Adam.
- `gtrainf-0-9000` against `gtrain3` over 5250-9000: max 1.14%, mean 0.45%; mean of the last four
  save points 1.7752 vs 1.7722 nats.
- `gtrainf-0-9000` against the CPU night run at its first nine save points (250-2250): max relative
  difference 0.70%, mean 0.33%.

## Held-out eval

Both final checkpoints evaluated by the CPU `ollm eval` (v1 binary b9b4e02d…997b, the night run's) on
`held.tok` with W 4486: `E step W loss_micro bpb_micro`.

| receipt | checkpoint | loss (nats/token) | bpb |
|---|---|---|---|
| `eval9000-gtrain.txt` | gtrain step 9000, f7128843…8d3e | 1.824653 | 0.680680 |
| `eval9000-gtrainf.txt` | gtrainf step 9000 from scratch, d11b2ec6…fc2e | 1.826877 | 0.681510 |

The from-scratch on-chip run ends 0.12% above the mixed CPU/GPU run in both loss and bpb
(WolframLanguageEvaluator). v0 ended at 1.463036 bpb after 20000 CPU steps on its byte-level shape.

`geval` on the chip now prints both E lines exactly (`../geval/README.md`); its first build, with the
plain f32 CE sum the training above used, printed 11 µnats less for each.
