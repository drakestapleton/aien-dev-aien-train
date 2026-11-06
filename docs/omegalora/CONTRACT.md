# omegalora: LoRA fine-tuning core in Omega (contract v1)

`native/omegalora/lora.om` is a first-party Omega unit that fine-tunes a frozen base with LoRA
(low-rank adapters) and checks its own math. It is the f64 reference that later GPU and
omegallm adapter kernels are compared against. Host CPU only; it does not qualify any chip.

## What it computes

One transformer MLP block shape, all f64:

- `h0 = rmsnorm(x)`, `p1 = (W1 + s B1 A1) h0`, `a1 = silu(p1)`, `n1 = rmsnorm(a1)`,
  `z = (W2 + s B2 A2) n1`, loss = mean softmax cross-entropy over 64 samples, 12 classes.
- Shapes: x 16, hidden 24, rank r = 4, alpha = 8, scale s = alpha / r = 2.
- `W1` (24x16) and `W2` (12x24) are frozen. Only `A1 B1 A2 B2` (304 values) learn.
- Init follows LoRA: A random, B zero, so step 0 equals the base model exactly.
- Optimizer: AdamW, beta1 0.9, beta2 0.999, eps 1e-8, weight decay 0.01, lr 0.02, 400 steps.
- `exp` and `log` are first-party (range reduction plus series); constants and error bounds
  are Wolfram receipts in `evidence/OMEGALORA/wolfram.txt`.
- Task: labels come from a hidden teacher `W + U V` with rank 4 changes on both layers, so a
  rank 4 adapter can represent it exactly.

## Gates (exit codes, decided inside the .om unit)

| exit | meaning |
|---|---|
| 0 | all gates pass |
| 13 | exp(1) or log(10) off by more than 1e-14 |
| 10 | analytic gradient vs central difference (h = 1e-5, every 3rd parameter, B nonzero): worst relative error above 1e-6 |
| 11 | training loss after 400 steps is not at most half the starting loss |
| 12 | accuracy did not rise by at least 0.2 |

## Negative controls

stdin selects a deliberately broken build. The gates must catch each one.

| stdin | break | must exit |
|---|---|---|
| 1 | SiLU derivative sign flipped | 10 |
| 2 | RMSNorm backward sign flipped | 10 |
| 3 | AdamW step sign flipped | 11 |

## Build and test

`sh tests/omegalora/run.sh` with `OMC` pointing at the pinned seeded omc (omega-mv `e5b32567`,
sha256 `2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f`). The script refuses
any other compiler, compiles, runs all four builds and writes `evidence/OMEGALORA/run/`.

## Limits

- Host CPU, f64, one block, synthetic teacher data. This is not a language model fine-tune yet.
- Omega today allows at most 16 live values per function and 6 parameters; the unit is split
  into small helpers for that reason.
- Next step: carry the same adapter math into omegallm (`native/omegallm/model.om`) so its
  checkpoints can take a LoRA adapter, checked against this unit.
