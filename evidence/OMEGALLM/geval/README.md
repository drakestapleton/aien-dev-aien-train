# Held-out eval on the chip: `geval`, and the CE sum fix (aien-train#52)

`geval CK HELD W [MERGES]` is `eval` (cli.om `cmdeval`) with the forward pass on the GB10 in f32: the
same windows, the same per-window mean row loss summed in window order, the same decoded byte count
for bpb, the same `E step W loss_micro bpb_micro` line. Code: `native/omegallm/gpu/gg.om` (`ggeval`,
`ggevw`, `ggevc`, `ggevr`, `ggevpr`). Every chip run went through `spark-window --gb10 shared --quiet
none` with other lanes and the CPU night run live; **every time below is non-quiet.** Status:
EXERCISED on one DGX Spark GB10, not QUALIFIED. `build.txt` lists the binaries.

## Gate (pre-registered)

`prereg.txt`, written before the first window: PASS for a checkpoint when the `geval` and CPU `eval`
E lines agree on step and W and |loss_micro_gpu − loss_micro_cpu| < 10 (1e-5 nats, gcmp's loss
tolerance). Negative control: a mutant on the same checkpoint counts as discriminating only if its
|Δ| ≥ 10. A repeat run must print the same E line. The gate was not changed at any point.

`geval` has no loss gate: whenever it completes it exits 0 (non-zero only when an argument check, a
load or the chip fails, e.g. exit 84 in `a1/`). The 10 µnat gate is the E-line comparison
against CPU `eval`, applied by the reviewer. The mutant receipts `ge-max-9000-mut-k.txt` and
`ge-night-gtrainf-mut-k.txt` have rc=0 and FAIL by that comparison (Δ −11).

## First attempt: FAIL (`plain/`, windows gg-ev1 20261102T070800Z-3bc294, gg-ev2 20261102T071111Z-32d026)

| checkpoint | chip E line | CPU E line | Δ µnats |
|---|---|---|---|
| night `gtrainf` step 9000 (d11b2ec6…) | E 9000 4486 1826866 681506 | E 9000 4486 1826877 681510 (`../gpu/eval9000-gtrainf.txt`) | −11 FAIL |
| night `gtrain` step 9000 (f7128843…) | E 9000 4486 1824642 680676 | E 9000 4486 1824653 680680 (`../gpu/eval9000-gtrain.txt`) | −11 FAIL |

Mutant f (layer-0 W1 × (1 + 2^-10)) moved the night loss by −3 µnats from the CPU value (1826874),
less than the defect itself: not discriminating.

`gdiag CK DATA S` compares the CE kernel's per-row stats with the CPU's f64 values for the same
forward (night ck d11b2ec6 and rung-5 ck9000 on batch 7). Mean over rows, ×1e9:

| receipt | R | d m | d l_y | d log Σ | d loss | Σp − 1 | d (l_y − m) |
|---|---|---|---|---|---|---|---|
| `plain/gd-night.txt` | 5120 | −341 | −257 | −10447 | −10531 | 10514 | 84 |
| `plain/gd-max.txt` | 16384 | −180 | −124 | −10401 | −10457 | 10435 | 56 |

The max logit and l_y agree to ~3e-7; the log of the sum of exp is low by ~1.04e-5. The CE kernel
summed exp(l − m) over V = 4096 sequentially in one f32 register: once the running sum is large,
every term below half its ulp is dropped, so the sum is biased low and every row's loss with it.
The chip's probabilities sum to 1 + 1.04e-5 for the same reason.

## Fix: compensated sum in the CE kernel

`gr.om grce` now carries the lost low part (Kahan: R40 compensation, R41, R42); `const OMUTK 1`.
Mutant k (`build.sh --mutant k`, OMUTK 0) restores the plain sum and is the gate's control.
`prereg-k.txt` (written before window gg-ev3) states predictions P1-P6, and P7 in its addendum.

**gg-ev3 (20261102T072103Z-3376a7), `a1/`: rc 84.** The first version used R69-R71. Every run whose
CE kernel used the Kahan sum died in kernel 21 with `GX 121 -110 …` (launch wait timed out), rc 84;
the mutant k binary, which writes R69 but not R70/R71, ran and reproduced the gg-ev1 E lines. The
kernels launch with 72 GPRs (`put gkgpr id 72` in `grall`). That registers R70 and R71 are not usable
at 72 GPRs is [INFERENCE] from these runs; it was not traced further. The fix moved the sum to the
unused R40-R42 (source of this tree).

**gg-ev4 (20261102T072455Z-a35040), top-level receipts, this tree's binaries:**

| prediction | receipt | result |
|---|---|---|
| P1 gdiag \|d log Σ\| and \|Σp − 1\| < 1000 ×1e9 | `gd-night.txt` 5120 −341 −257 65 −19 3 84; `gd-max.txt` 16384 −180 −124 33 −23 1 56 | PASS |
| P2 night `gtrainf` and `gtrain` \|Δ\| < 10 | `ge-night-gtrainf.txt` E 9000 4486 1826877 681510 (Δ 0); `ge-night-gtrain.txt` E 9000 4486 1824653 680680 (Δ 0) | PASS |
| P3 mutant k \|Δ\| ≥ 10 | `ge-night-gtrainf-mut-k.txt` E 9000 4486 1826866 681506 (Δ −11, rc=0) | PASS: discriminates |
| P4 gcmp2 max s7, night s7, small s3 PASS; mutants g m f FAIL rc 47 | `gc2-*.txt` | PASS |
| P5 gacmp ck250 s7 PASS; mutant h FAIL rc 46 | `ga-max.txt`, `ga-max-mut-h.txt` | PASS |
| P6 max ck9000 repeat, same E line | `ge-max-9000.txt`, `ge-max-9000-rep.txt`: E 9000 2243 1445466 539226 both | PASS |
| P7 no rc 84 | every top-level receipt rc 0, 47 or 46 as predicted | PASS |

Both night checkpoints now print the CPU's E line exactly. Mutant f (`ge-night-gtrainf-mut-f.txt`,
1826885, Δ +8) is again under 10 and is reported as non-discriminating.

The sum fix also tightens the gradient (WolframLanguageEvaluator ratios): on the night shape the
gcmp2 gradient error rel1 drops from 41012 to 8764 ×1e-9 (4.68×) and the chip's batch loss equals the
CPU's (2514497, was 2514490); at the max shape rel1 goes from 786 to 738. Mutants g, m, f, h fail as
before, their error figures within 0.002% of the old ones (`../gpu-max/` for the old receipts).

The rung-5 training (`../gpu-max/`) and the rung-4 runs (`../gpu/`) used the plain sum: each row's chip
loss was ~1.05e-5 nats low and its probabilities summed to ~1 + 1.04e-5, which the softmax gradient
carried.

## Rung-5 checkpoints

GE is the chip time of the whole eval (upload, forwards, loss reads), non-quiet:
`ge-max-9000.txt` 8.47 s for W 2243 at T 256; night W 4486 at T 128 3.07 s.

The CPU `eval` of the same checkpoints (`../gpu-max/eval2000.txt`, `eval9000.txt`, W 2243 at T 256,
this tree's CPU `ollm` bfd92d15…) finished after gg-ev4. Gate: |chip − CPU| < 10 µnats.

| checkpoint | CPU E (µnats, µbpb) | chip, Kahan (this tree) | chip, plain sum (`plain/`) | mutant k |
|---|---|---|---|---|
| rung-5 step 2000 | 1789590 667600 | 1789590 667600 (Δ 0), PASS | 1789579 667596 (Δ −11), FAIL | — |
| rung-5 step 9000 | 1445466 539226 | 1445466 539226 (Δ 0, twice), PASS | 1445455 539222 (Δ −11), FAIL | 1445455 (Δ −11, rc=0, `ge-max-9000-mut-k.txt`), FAIL |

The CPU evals ran 5812 s (step 2000, core 5) and 7323 s (step 9000, core 7) at nice 19 beside the
night run; the chip's GE for the same work was 8.52 s and 8.47 s, 682× and 865× less
(WolframLanguageEvaluator; both sides non-quiet, different resources, so this is a wall-time ratio,
not an efficiency figure).
