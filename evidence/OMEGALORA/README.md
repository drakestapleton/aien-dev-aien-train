# omegalora host evidence (core v1)

Source commit: `e4140effeb91366d74d61fc45b7d9de07bb96d2b`. Base: train main `77cffb6`.
Host: Linux 7.0.0-1019-nvidia aarch64 (DGX Spark GB10 host CPU), CPU only. No GPU ran.
Compiler: pinned seeded omc, sha256 `2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f`.
Command: `OMC=<pinned omc> sh tests/omegalora/run.sh`. Raw outputs are in `run/`, sealed by
`run/raw.sha256`. Binary sha256 `966f9994de1b854fc1c7ca11c7e27aabb10cb5ae35b269f8ce9d9498a4842071`.

The same source also compiled and ran in the omega harness sandbox (bwrap, no network, cleared
environment) on 2026-11-06: same binary sha256, exit 0, identical stdout.

## Results (MEASURED, run/mutant0.stdout)

| check | value | gate |
|---|---|---|
| exp(1) | 2.718281828459 | within 1e-14 of e |
| log(10) | 2.302585092994 | within 1e-14 of ln 10 |
| gradient check, worst relative error | 0.000000018729 | at most 1e-6 |
| loss before / after 400 AdamW steps | 2.000809231083 / 0.000382919481 | after at most half of before |
| accuracy before / after | 0.3125 / 1.0 | rise of at least 0.2 |

## Negative controls (MEASURED)

| build | break | exit | expected |
|---|---|---|---|
| mutant1 | SiLU derivative | 10 | 10 |
| mutant2 | RMSNorm backward | 10 | 10 |
| mutant3 | AdamW sign | 11 (loss 49994.28) | 11 |

## Limits

Host CPU, f64, one MLP block, synthetic teacher labels. This qualifies the adapter math only;
it is not a language model fine-tune and says nothing about GPU speed. Contract: `docs/omegalora/CONTRACT.md`.
Constants: `wolfram.txt`.
