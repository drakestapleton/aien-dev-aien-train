# Rung 6: 30000 GB10 steps at the largest v1 shape (aien-train#52)

Rung 5 (`../gpu-max/`) trained the largest shape the v1 contract allows (V 4096, T 256, D 256, H 8,
F 1024, L 8, B 64, P 7,409,920) for the v1 schedule of 9000 steps, 19.9 tokens per parameter. Rung 6
keeps the shape, the seed and the learning rate, lengthens the schedule to 30000 steps (491,520,000
tokens, 0.963 of `train.tok`, 66.3 tokens per parameter), and trains with the compensated CE sum of
`../geval/`. A `geval` of the saved checkpoint follows every window, so the held-out curve is measured
during training rather than after it.

Status: EXERCISED on one GB10. Every window was opened `--gb10 shared --quiet none`. `spark-window`
printed the verdict "quiet machine" for all 18 windows (`windows-log.txt`), but the quiet lock was not
taken and the CPU night run `ollm-night` held the CPU throughout (load average 14.4-16.8 at the last
close, `close.json` of 20261102T114504Z-6fe1ac), so the timings below are labelled non-quiet. Not
QUALIFIED.

## Setup

- Binary: this tree's GB10 build `ollm-gb10` sha256 576bf296…6224485 (`../geval/build.txt`), omc
  2c824805… (omega-mv e5b32567). CPU `ollm` bfd92d15…368e for `init` and `eval`.
- Init (`init.txt`, rc 0): `ollm init ckL0.bin 4096 256 256 8 1024 8 64 1 30000 3000 16`, sha256
  11d6d39f…0dec. It differs from rung 5's `ck0` (made with TOTAL 9000) in exactly the 2 bytes of the
  TOTAL field at byte 81; the weights are identical.
- `drive.sh` opens one `spark-window` per leg (lease 20 min) and posts STARTING/DONE lines to the
  board. `leg.sh` runs `gtrainf ck.bin train.tok UNTIL 250` to the next stop (250, then 1750 steps per
  leg), then `geval ck.bin held.tok 2243 merges4096.bin`. Both resume from the last `T` line. In the
  committed `leg.sh` and `windows-log.txt` the home prefix is replaced by `~/`; nothing else differs.
- Learning rate (`adam.om` `olrs`): linear warmup to 0.003 over 100 steps, then
  0.003·(1 − 0.9·(s − 100)/(TOTAL − 100)). At step 9000 rung 5 is at 0.0003 and rung 6 at 0.002196;
  at step 2000, 0.002424 and 0.002828 (WolframLanguageEvaluator).
- Pre-registration `prereg.txt` was written before the first chip step.

## Results

| prediction | receipt | result |
|---|---|---|
| P1 every leg and every `geval` rc 0 | `windows.txt` 18 × `open=0 leg=0`, `finished`; `train.txt` 18 × rc=0; `geval.txt` 18 × rc=0 | PASS |
| P2 per-step time within 5% of 0.3808 s | 250→30000 mean 0.37712 s/step (−0.97%); legs 0.37465-0.38780 (max +1.84%) | PASS |
| P3 final E below 1445466 µnats | `geval.txt` step 30000: E 30000 2243 1338156 499194 | PASS (−7.42%) |
| P4 held-out curve non-increasing within 2000 µnats | 18 geval points, every one below the last | PASS (strictly decreasing) |
| P5 CPU `eval` of step 30000 within 10 µnats of the chip | `eval30000.txt`: CPU `ollm` bfd92d15… on core 7, rc 0, E 30000 2243 1338156 499194 | PASS (Δ 0: the chip E line exactly) |

Per-step times are wall clock between the ns stamps of each leg in `train.txt`, divided by the leg's
steps (WolframLanguageEvaluator). 250→30000 took 11,219 s of chip time, 43,445 tokens/s, about 1.93
TFLOP/s by the 6·P·tokens rule (attention excluded); the whole run, including the 97.7 s step-0→250
leg, is 3.14 h. Each `geval` took 6.82-7.37 s of chip time (GE), mean 7.00 s. The CPU `eval` of the
same checkpoint took 5519 s on one core at nice 19 (non-quiet).

## Held-out curve (chip `geval`, W 2243 at T 256)

| step | nats | bpb | rung 5 at the same step (CPU `eval`) |
|---|---|---|---|
| 250 | 2.840107 | 1.059492 | |
| 2000 | 1.797226 | 0.670449 | 1.789590 |
| 3750 | 1.650271 | 0.615628 | |
| 5500 | 1.581132 | 0.589836 | |
| 7250 | 1.534578 | 0.572469 | |
| 9000 | 1.502144 | 0.560370 | 1.445466 (end of its schedule) |
| 10750 | 1.476483 | 0.550797 | |
| 12500 | 1.455657 | 0.543028 | |
| 14250 | 1.437440 | 0.536232 | |
| 16000 | 1.420924 | 0.530071 | |
| 17750 | 1.407861 | 0.525198 | |
| 19500 | 1.394495 | 0.520211 | |
| 21250 | 1.384640 | 0.516535 | |
| 23000 | 1.373468 | 0.512367 | |
| 24750 | 1.364160 | 0.508895 | |
| 26500 | 1.354723 | 0.505375 | |
| 28250 | 1.345539 | 0.501949 | |
| 30000 | **1.338156** | **0.499194** | |

At equal steps rung 6 trails rung 5 (step 9000: +56,678 µnats) because its learning rate has not
decayed; it passes rung 5's final value between steps 12500 and 14250. Against the rung-4 night shape
(1.826877 nats) the step-30000 model is 26.8% lower. The last leg (28250→30000) still gained 7,383
µnats, at a learning rate near its floor, so the curve has not flattened. Batch loss at the last four save points averages 1.2933
nats (rung 5: 1.4978); batch losses are noisy (`T 28750 1372351`, `T 29250 1266171`).

Checkpoints are kept outside the repository (177,838,200 bytes each): step 2000 5bfb32e3…9a37, step 9000
e91349fb…206d, step 30000 8ccaa099…5509.
