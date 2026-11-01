# Omega LLM v0 (aien-train#52)

Omega LLM v0 is a proof of concept. It is a byte-level, decoder-only transformer with 119,104
parameters:

- V 256, T 64, D 64, H 4, F 256, L 2, B 16.
- It is trained from random initialization entirely in seeded `.om` (omc, omega-mv e5b32567).
- Training runs single-threaded on the DGX Spark Grace CPU, with no GPU.

The normative spec is [CONTRACT.md](CONTRACT.md). The receipts are under
`evidence/OMEGALLM/core/` (the `.om` lane) and `evidence/OMEGALLM/oracle/` (the Python-stdlib referee).

## Status

Evidence for every row is in `evidence/OMEGALLM/core/summary.tsv` (26/26 as expected). Every receipt
names the binary and source sha256 it ran:

- `ollm` a9b5f3ec8291c1b046d350dcb7ee6550a271a9e06ee30ba13062d28732aa6137, source cb80250d;
- mutants: a f1747fcd, b 4b12510f, c 73afec79.

| What | Status | Receipt (`evidence/OMEGALLM/core/`) |
|---|---|---|
| `prep` on TinyStoriesV2-GPT4-valid.txt | EXERCISED | `prep.txt`: `P 27630 24867 2763 19883834 2220914` |
| `base` unigram/bigram bpb | EXERCISED | `base.txt`: `B 4415645 3295113` (4.415645 / 3.295113 bpb) |
| `init` v0 | EXERCISED | `init-v0.txt`: `I 119104` |
| `train`, 50 v0 steps | EXERCISED | `train-v0-50.txt`: loss 5.429638 at step 5 to 3.110411 at step 50 nats; ln 256 = 5.545177 |
| resume is bit-identical | EXERCISED | `resume-cmp.txt`: steps 0→40 in one run and 0→20→40 in two runs give the same checkpoint; `cmp` rc 0 |
| checkpoint refusal | EXERCISED | `refuse-flip-payload.txt` (rc 14), `refuse-flip-magic.txt` (rc 11), `refuse-truncated.txt` (rc 10) |
| `eval` | EXERCISED | `eval-v0.txt`: `E 50 256 3049318 4399237` |
| `sample` | EXERCISED (runs; output is not cross-checked) | `sample-v0-argmax.txt`, `sample-v0-t800.txt` |
| gradient check | EXERCISED | `gcheck.txt` (small shape) maxrel 3.08146e-4; `gcheck-v0-init.txt` (v0, seed 1) 1.05146e-4; `gcheck-v0-step50.txt` (v0, 50 steps) 5.15267e-4; 76 indices each, 0 retries |
| Adam check | EXERCISED | `adamck.txt` |
| exp/log against Wolfram | EXERCISED | `mathck.txt`: exp at most 1 ulp, log at most 2 ulp |
| mutants a (dK sign), c (no bias correction) | EXERCISED, killed | `mut-a-gcheck.txt` and `mut-a-gcheck-v0.txt` (rc 40, maxrel 2.0), `mut-c-adamck.txt` (rc 41) |
| mutant b (targets shifted) | killed by the oracle only | `mut-b-gcheck.txt` passes the self-check, as expected; the kill is in `evidence/OMEGALLM/oracle/` |
| cross-check against the referee | EXERCISED by the oracle lane, on a9b5f3ec and the three mutants | `evidence/OMEGALLM/oracle/` and `tests/omegallm/ORACLE.md` |
| refusal codes 12, 13, 15 | NOT_RUN | — |
| the v0 run, 20000 steps (`tests/omegallm/v0-run.sh`) | RUNNING since 2026-11-01T15:24:54Z on core 9 | `evidence/OMEGALLM/v0/` when it finishes |

## Build

```sh
sh tests/omegallm/build.sh               # -> ../build/ollm
sh tests/omegallm/build.sh --mutant a    # also b, c: -> ../build/ollm-mut-X
```

The build script does four things:

1. It checks the omc sha256 (`2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f`).
2. It concatenates the units in this order: `math.om data.om model.om adam.om ckpt.om cli.om`.
3. For a mutant, it changes exactly one line of the concatenated copy (`OMUTA`, `OMUTB`, `OMUTC`).
4. It compiles under `taskset -c $CORE nice -n 19` and prints
   `BUILD_OK <bin sha256> <path> source_sha256 <sha>`.

## Run

```sh
B=../build/ollm; R="taskset -c 6 nice -n 19"
$R $B prep TinyStoriesV2-GPT4-valid.txt train.bin held.bin
$R $B base train.bin held.bin
$R $B init v0.ck 256 64 64 4 256 2 16 SEED TOTAL LRMICRO
$R $B train v0.ck train.bin UNTIL EVERY
$R $B eval v0.ck held.bin 256
$R $B sample v0.ck SEED 200 800 "Once upon a time"
```

Never commit the data or the `.bin` and `.ck` files. Every receipt in the table can be reproduced
with `sh tests/omegallm/core-receipts.sh`; set `CORE`, `BUILD`, `DATA` or `WORK` to override the
defaults. The exit codes are listed in CONTRACT §7.

## Throughput

All timings ran on Spark GB10 Grace core 6. `lscpu` reports it as a Cortex-X925 with a 3900 MHz
maximum. The process ran single-threaded under `nice -n 19` on a shared host, so the step time
depends on what else runs on that core.

- `train-v0-50.txt`: 50 steps took 35.360512365 s wall, including 10 checkpoint saves.
  - Per step: WolframLanguageEvaluator `35.360512365/50` → 0.70721 s.
  - Throughput: `50*1024/35.360512365` → 1447.94 training bytes/s.
- `resume-a-0-40.txt`: 40 steps with one save took 28.171673987 s. Per step: `28.171673987/40` →
  0.70429 s. Saving every 5 steps therefore adds `100*(sps-s40)/s40` → 0.41% per step.
- `gcheck-v0-init.txt`: 44.7 s for 76 indices.
- A checkpoint is `112+24*119104` → 2,858,608 B.

## The v0 run

`tests/omegallm/v0-run.sh` is the script of the first full run. It is the init line of the receipts
with seed 1 and TOTAL 20000, trained in 1000-step chunks; each chunk is followed by a held-out eval
at W=256 and a saved checkpoint. Chunking does not change the result, because resume is
bit-identical (`resume-cmp.txt`). After the last chunk it runs one eval at W=4096 and writes three
samples at TEMPMILLI 800 and one argmax sample, each 400 bytes after the prompt "Once upon a time".

Planned length, WolframLanguageEvaluator with sps = 0.70721 s/step from `train-v0-50.txt`:

- Duration: `20000*sps/3600` → 3.93 h of training on one uncontended X925 core, plus the evals.
- Data seen: `20000*16*64/19883834` → 1.03 passes over the training bytes, in expectation.
- LRMICRO 3000 is the only learning rate exercised.

The outputs (without checkpoints) and the result are in `evidence/OMEGALLM/v0/`.

## Self-check constants

- `MCTOL 1e-15`: the allowed relative error of first-party `fexp`/`flog` against the correctly rounded
  Wolfram value.
  - In ulps: WolframLanguageEvaluator `10.^-15/2.^-52` → 4.50 ulp-equivalents.
  - Observed (`mathck.txt`): exp 2.70e-16 (`2.70*^-16/2.^-52` → 1.22) and log 3.37e-16 (→ 1.52).
  - The margin is `10.^-15/3.37*^-16` → 2.97×.
- `tests/omegallm/mathref.txt` is the reference: 3017 `e` lines and 2122 `l` lines.
  - Each RBITS value is the round-half-even f64 of a 60-digit Wolfram `Exp`/`Log` at the exact
    XBITS value. The bits are constructed explicitly, including the subnormal, overflow and zero
    cases.
  - The exp grid covers k/1000 on [−1, 1], 1000 points on [−745, 709.78], and the
    overflow/underflow thresholds.
  - The log grid covers 1/2 + k/1000 up to 2, 10^k for k = −307..307, the subnormals, the largest
    f64, and 1 ± 1 ulp.
- The generator is `tests/omegallm/mathref.wl` (sha256
  `fd94187c1e267c527f9876bb4dd076e5a0b7487d1ba82149375e09d199f3bf75`). Running it, then evaluating
  `{StringLength[text], IntegerString[Hash[text,"SHA256"],16,64]}` in WolframLanguageEvaluator,
  gives 185004 and `3ecc26a3cdf64d640e098eb057e2adfbe390e78fef20b64d5f83e5fa907e961a`. That is the
  same as `sha256sum tests/omegallm/mathref.txt`, so the committed file is exactly what the generator
  writes.
- gcheck takes four indices per tensor instance, drawn by splitmix64, and computes the central
  difference `(L(p+h)−L(p−h))/((p+h)−(p−h))` against the hand gradient. For each index,
  `rel = |num−g|/max(|num|,|g|,GCFLOOR)`. GCFLOOR 1e-6 and GCTOL 1e-3 are unchanged.
- `GCH` was 1e-5, and at v0 one index reached rel 6.95e-3 (Main's run on the GCH 1e-5 binary; no
  receipt in this tree). The oracle
  matched that gradient to 1e-12, and the outliers fell to ≤ 2.9e-6 at h = 1e-6. That is the
  signature of `p ± h` moving a ReLU pre-activation across 0, where the loss has a kink: the
  difference then measures a one-sided slope, not the gradient.
- `GCH` is now 1e-6. An index over GCTOL is redone once at `GCH2 = 2.5e-7`, and the smaller rel is
  kept; the `C` line counts these retries. A smaller h narrows the band of pre-activations whose
  kink it can cross. The cost is more f64 rounding noise in L(p±h)/h.
  - Roundoff in the difference is about `eps·L/h` with eps = 2^-53 and L ≈ 5.545 (the init loss).
    WolframLanguageEvaluator `With[{e=2.^-53,L=5.545},{e*L/10.^-6, e*L/(2.5*^-7), e*L/10.^-7}]` →
    6.16e-10, 2.46e-9, 6.16e-9 absolute. Divided by GCFLOOR 1e-6 that is a worst-case rel of 6.2e-4,
    2.5e-3 and 6.2e-3 for a gradient at the floor.
  - h = 1e-7 was tried on the same v0 init checkpoint and failed (rc 40, rel 1.88e-3 at index 27146)
    on roundoff, as that bound predicts; h = 1e-6 passed at 1.05e-4 (Main's test builds, no receipt
    in this tree). The h/4 retry can exceed GCTOL from roundoff alone, but only replaces rel when it is
    smaller, so it cannot turn a pass into a fail, and a wrong gradient (mutant a, rel 2.0) fails at
    both step sizes.
- Observed rels: small shape 3.08146e-4 (WolframLanguageEvaluator `10.^-3/3.08146*^-4` → 3.2×
  margin), v0 init 1.05146e-4 (9.5×), v0 at step 50 5.15267e-4 (1.9×), mutant-b small shape
  4.72375e-4 (2.1×). All of these have 0 retries.
- Mutant a reaches 2.0, with 23 retries on the small shape and 38 at v0. It exits 40 on both.
- These constants are deterministic per checkpoint, so a pass is reproducible. The 1.9× margin at a
  trained v0 checkpoint is the tightest; recheck it if the shapes change.
