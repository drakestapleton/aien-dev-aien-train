# GB10 training at the rung-5 shape (aien-train#52)

Rung 5 is the largest v1 shape trained here: V 4096, T 256, D 256, H 8, F 1024, L 8, P 7,409,920
parameters, batch B 64 (R = B T = 16384 tokens per step), the v1 schedule (9000 steps, lr 0.003).
Every chip run went through `spark-window --gb10 shared --quiet none` with other lanes and the CPU
night run `ollm-night` live. **Every time below is non-quiet.** Status: EXERCISED on one DGX Spark
GB10, not QUALIFIED. No CUDA: the kernels are SASS emitted by `native/omegallm/gpu/*.om`.

`build.txt` lists the binaries and sources. Data: `v1-data/train.tok`. Checkpoints (not committed,
sha256 prefix…suffix): `ck0` init 63fed3c3…69eba9a2; `ckb8` the same weights with B 8 for the gradient
gates (R = 2048) bd839cb2…81defdc2; `ck250` c0f22736…4d454801; `ck2000` 62d7c706…b67c8d; final `ck9000`
f022797f…2b69bd. The rung-4 gate receipts of the other shapes are in `../gpu/`.

## Windows

| window | name | ran |
|---|---|---|
| 20261102T051604Z-6c7761 | gg-r5a | `gc-max*.txt`, `gtrainf-0-250.txt`, `ga-max*.txt` (rung-4 binaries) |
| 20261102T052317Z-dc87f8 | gg-r5k | probe trapped BOUNDS in 1 s (offset bug in the probe), nothing recorded |
| 20261102T052512Z-97f3a1 | gg-r5k2 | `probe/k-s7.txt`, `probe/k-s11.txt` |
| 20261102T054014Z-6d5fc0 | gg-v2 | `gc2-*.txt` except the repeat |
| 20261102T060451Z-a79c2d | gg-r5t2 | `probe/k-s7-repeat.txt`, `gc2-max-s7-repeat.txt`, `gtrainf-250-9000.txt` 2000→3750 |
| 20261102T055327Z-ae42cd | gg-r5t1 | `gtrainf-250-9000.txt` 250→2000 |
| 20261102T062023Z-56282f | gg-r5t3 | `gtrainf-250-9000.txt` 3750→5500 |
| 20261102T063143Z-62dd87 | gg-r5t4 | `gtrainf-250-9000.txt` 5500→7250 |
| 20261102T064302Z-8acda9 | gg-r5t5 | `gtrainf-250-9000.txt` 7250→9000 |

Window records: `~/yardsticks/windows/<id>/` on the Spark.

## gcmp fails at this shape, and why

`gc-max.txt`: the rung-4 gate `gcmp` on `ckb8`, batch 7, **FAIL rc 45**, rel 1.58053e-4 against
γ_R = 2048·2^-24 = 1.22070e-4, with |Δloss| 0. Mutant g fails far above it (`gc-max-mut-g.txt`, rel
6.48e-3). On-chip Adam passes (`ga-max.txt`, resid 1.36e-7; mutant h FAIL rc 46, `ga-max-mut-h.txt`).

A gate failure is not waved through. The diagnosis (`probe/`, a throwaway build not in the tree,
sha256 in `build.txt`) computes the CPU f64 gradient twice: K0 with its own ReLU mask, as `gcmp`
does, and K1 with the mask taken from the sign of the chip's f32 FFN pre-activation FP. Lines are
`K maxabs_e12 maxref_e12 rel_e9 … flips fpdiff_e12 … vflip_e12 loss_micro`.

| receipt | rel, own mask (K0) | rel, chip mask (K1) | flipped units | max \|FP_ref\| at a flip |
|---|---|---|---|---|
| `probe/k-s7.txt` | 1.58053e-4 | 7.86e-7 | 4 | 2.28e-7 |
| `probe/k-s11.txt` | 4.64807e-4 | 1.272e-6 | 6 | 2.36e-7 |

Out of 2048·1024·8 = 16.8M ReLU units, four (batch 7) or six (batch 11) have a reference
pre-activation within 2.4e-7 of zero, and f32 rounding puts the chip's value on the other side. ReLU's
derivative jumps at zero, so each such unit moves the gradient by a full term, not by rounding; with
the chip's mask the error falls 200-fold to 7.9e-7, 155 times under γ_R. γ_R bounds rounding of sums
and was never a bound on a branch decision. At the rung-4 night shape the same effect happened to fit
under it (`../gpu/README.md`); here it does not. The kernels are not at fault, and no tolerance was
loosened: the gate below replaces the question.

## Branch-conditioned parity: `gcmp2`

`gcmp2 CK DATA S` (exit 47 on FAIL) splits the comparison in two checks, each against its own bound,
designed and pre-registered before its first run (the mutant expectations and the rule "if rho fails
on a passing shape, split rho into GEMM-local and upstream parts, do not raise tolf" were written
down before window gg-v2):

1. **Forward check.** For every FFN pre-activation of every row and layer, rho = |FP_chip − FP_ref| / s_j
   with s_j = Σ_k |bn_k||W1[k, j]|, the magnitude sum of the dot product the chip rounds. Gate:
   rho < tolf = max(D, F, T)·2^-24, the γ_n of the longest reduction feeding the forward pass. FP_chip
   is read from the chip arena (left there by the gradient pass); FP_ref is the CPU f64 value.
2. **Gradient check given the branch.** K1 is the CPU f64 gradient with every ReLU mask taken from the
   chip's FP sign (`ogmask`, the hook `ogkm` in `model.om`). Gate: rel1 = max|G_chip − K1| / max|K0| <
   γ_R = R·2^-24, `gcmp`'s bound, now applied to the quantity it bounds.
3. Every FP, chip gradient, K0 and K1 value must be finite, and |chip loss − K0 loss| < 1e-5.

The line is `GC2 P rel0_e9 rel1_e9 tolr_e9 rho_e9 tolf_e9 rho_layer flips vflip_e12 fpdiff_e12
nonfinite cpu_loss_micro gpu_loss_micro gpu_ns fails`; rel0 is `gcmp`'s rel, printed for comparison.
`fails` is a bit set: 1 non-finite, 2 rho ≥ tolf, 4 rel1 ≥ tolr, 8 loss.

Why this is sound: a flipped unit is only acceptable if the chip computed its pre-activation
correctly to within rounding, which check 1 bounds for every unit, flipped or not; given those
branches, check 2 holds the backward pass to the same γ_R as before. A wrong forward kernel fails 1, a
wrong backward kernel fails 2, and a wrong mask kernel fails 2 because K1 uses the chip's FP, not its
mask. **gcmp2 is a different gate from gcmp; a gcmp2 PASS is not a gcmp PASS**, and the gcmp FAIL
receipts above stay as recorded.

It also closes a hole in gcmp: its running max (`ggmaxd`, `if gt dd get ggcm 0`) skips NaN, because
every ordered comparison with NaN is false in the pinned omc (a 0/0 program takes neither `gt n 1.0`,
`lt n 1.0` nor `gt 1.0 n`; with n = 2.0 the first branch is taken). A NaN gradient entry therefore
could not raise rel. gcmp2 counts non-finite values and fails on any. gcmp itself is unchanged.

| receipt | shape | rel0 (gcmp) | rel1 / tolr | rho / tolf | flips | fails | result |
|---|---|---|---|---|---|---|---|
| `gc2-max-s7.txt` | rung 5, batch 7 | 1.58053e-4 | 7.86e-7 / 1.22070e-4 | 4.47e-7 / 6.1035e-5 | 4 | 0 | PASS rc 0 |
| `gc2-max-s7-repeat.txt` | same, next window | 1.58053e-4 | 7.86e-7 | 4.47e-7 | 4 | 0 | PASS, GC2 fields identical but gpu_ns |
| `gc2-max-s11.txt` | rung 5, batch 11 | 4.64807e-4 | 1.272e-6 / 1.22070e-4 | 4.83e-7 / 6.1035e-5 | 6 | 0 | PASS rc 0 |
| `gc2-night-s7.txt` | rung-4 night shape | 1.61428e-4 | 4.1012e-5 / 3.05176e-4 | 2.052e-6 / 4.5776e-5 | 2 | 0 | PASS rc 0 |
| `gc2-small-s3.txt` | small shape | 2.35e-7 | 2.35e-7 / 3.815e-6 | 2.26e-7 / 7.629e-6 | 0 | 0 | PASS rc 0 |
| `gc2-max-s7-mut-g.txt` | mutant g: DK = −DSᵀQ | 6.48e-3 | 6.47e-3 | 4.47e-7 | 4 | 4 | FAIL rc 47 |
| `gc2-max-s7-mut-m.txt` | mutant m: chip ReLU mask at FP > 2^-10 | 7.39e-3 | 7.38e-3 | 4.47e-7 | 4 | 4 | FAIL rc 47 |
| `gc2-max-s7-mut-f.txt` | mutant f: layer-0 W1 uploaded × (1 + 2^-10) | 2.48e-3 | 5.71e-4 | 4.117e-4 | 2745 | 14 | FAIL rc 47 |

Margins (WolframLanguageEvaluator): rel1 sits 155× (s7), 96× (s11), 7.4× (night), 16× (small) under
tolr; rho 137×, 126×, 22×, 34× under tolf. Mutant f's rho is 6.7× over tolf, and it also fails the
gradient and loss checks (bits 2+4+8). Mutants m and f are new in this tree (`build.sh --mutant m|f`,
constants `OMUTM` in `gr.om` and `OMUTF` in `gg.om`); each fails on exactly the check it was built to
hit. The repeat run and the probe repeat (`probe/k-s7-repeat.txt`) reproduce their first runs
bit for bit, so the chip side is deterministic on this batch.

The CPU path of this tree is unchanged (`cpu-unchanged.txt`): on the small checkpoint, `gcheck` and a
3-step `train` print the same lines as the v1-night binary b9b4e02d, and both write the same checkpoint
(sha256 ad804153…). `nogpu.om` gives non-gb10 builds an `ogmask` that exits 2; `ogkm[0]` is 0 outside
gcmp2, so it is never called.

## Training

`gtrainf CK train.tok UNTIL 250`, starting from `ck0`, in six windows of ≤1750 steps each (lease 20
min). The step-250 leg ran the rung-4 binary 371ff177; 250→9000 ran this tree's b3d844b1. Times are
wall clock between the ns stamps of each leg (WolframLanguageEvaluator).

| leg | steps | wall | per step |
|---|---|---|---|
| `gtrainf-0-250.txt` | 0→250 | 97.0 s | 0.388 s |
| `gtrainf-250-9000.txt` gg-r5t1 | 250→2000 | 665.8 s | 0.3805 s |
| gg-r5t2 | 2000→3750 | 670.2 s | 0.3830 s |
| gg-r5t3 | 3750→5500 | 670.1 s | 0.3829 s |
| gg-r5t4 | 5500→7250 | 665.5 s | 0.3803 s |
| gg-r5t5 | 7250→9000 | 660.4 s | 0.3774 s |

250→9000 took 3332.1 s of chip time (55.5 min), 0.3808 s/step: 43,023 tokens/s, about 1.91 TFLOP/s by
the 6·P·tokens rule (attention excluded). The last step's phases (GT line, ms): upload 0.88, forward
140.6, backward 229.6, loss 3.2, Adam 2.09. The rung-4 night shape ran at 0.0538 s/step (95,256
tokens/s).

Batch loss at save points falls from 2.890 (step 250) to 1.482 (step 9000); the mean of the last four
save points is 1.4978 nats, against 1.7752 for the rung-4 night shape under `gtrainf` 0→9000.

## Held-out eval

CPU `eval` of this tree's `ollm` (bfd92d15…), W 2243 at T 256: the same target set as the night shape's
W 4486 at T 128 (W 4486 at T 256 exits 23).

| checkpoint | receipt | held-out nats | bpb |
|---|---|---|---|
| rung-5 step 2000 | `eval2000.txt` | 1.789590 | 0.667600 |
| rung-5 step 9000 | `eval9000.txt` | 1.445466 | 0.539226 |
| rung-4 night shape, `gtrainf` step 9000 (`../gpu/eval9000-gtrainf.txt`) | | 1.826877 | 0.681510 |

Rung 5 ends 0.381411 nats below the night shape, 20.9% fewer bits per byte (WolframLanguageEvaluator).
The chip's `geval` prints both E lines exactly (`../geval/`).
