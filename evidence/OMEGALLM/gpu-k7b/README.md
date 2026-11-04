# GB10 kernels k7b: the accumulator remap removed, Ra reuse kept (aien-train#52)

`../gpu-k7/` added two switches to the GEMMs (ids 0-7 32×32, ids 32-39 64×64): Ra operand reuse with
control bit 109 (`OKREU`) and an accumulator column remap (`OKBNK`, C column j in accumulator column
j xor 1). Its one profile per binary put all the gain on reuse. The remap-only variant r0 fell inside
the K6 spread, and the reuse-only variant b0 was at least as fast as both together. k7b removes the
remap:

- `gk.om`: `OKBNK`, `gkcol` and `gkacc32` are gone. `gkfrag` and `gkstep64` index the accumulator as
  `16 + k` again, the 32×32 epilogue uses `add 16 k`, and `gkacc64` is back to its k6 formula. `gkffma`'s
  reuse mask, `OKREU`, `gkru` and mutant t (`OMUTT`) are unchanged.
- `build.sh`: `--variant b0` is gone. `--variant r0` (`OKREU 0`, the K6 code) remains.

The product's GPU code is byte-equal to k7's variant b0 at both shapes (`disasm.txt`). It is still a
new binary (50dcd16e… against b0's c37449e6…), so it is gated in its own window. This window also
repeats the profiles in three rotated rounds, because k7 had only two K6 runs to estimate the spread.

Status: EXERCISED on one GB10, window `20261102T151944Z-8e7470` (`win-k7b.txt`), opened
`--gb10 shared --quiet none`. `spark-window` printed the verdict "quiet machine", but the quiet lock
was not taken, and the load average was 1.64 at open and 2.60 at close (`open.json`, `close.json`).
The timings are therefore non-quiet. Not QUALIFIED.

## Setup

- Binaries (`build.txt`): product P 50dcd16e…, mutant t PT 69724d09…, omc 2c824805… (omega-mv
  e5b32567), built from this commit's tree before the window. The same window ran two bases: K6
  e49491c5… (`../gpu-k6/`) and K7a 53ff5f71…, the parent commit's product (`../gpu-k7/`, d3d4551).
- Static checks before the window (`prereg.txt`), recorded in `disasm.txt`:
  - P's 64-slot code is byte-equal to k7 b0's (max shape cd777d34…, parity shape 9659b361…).
  - This tree with `OKREU 0` is byte-equal to K6's code (max 9646adef…, parity ac8e5ff1…).
  - P differs from K6 only in slots 0-7 and 32-39. Of their 6464 FFMAs, 5120 print `.reuse`, as in k7.
- `prereg.txt` was written at 15:19:37Z and the window opened at 15:19:44Z. `prereg.sha256` (written
  before the open) hashes it (726a0ecf…) and the `run.sh` the window ran (47444baa…). In the committed
  `run.sh`, `win-k7b.txt` and the window JSON the home prefix is replaced by `~/`, so the committed
  `run.sh` hashes to efcd1f70…. Nothing else differs.
- Checkpoints are as in `../gpu-k7/`: `gprof` on rung 6's `ck30000` (8ccaa099…) and `t200` from
  rung 6's `ck9000` (e91349fb…).

## Results

GC2 field 14 (`gpu_ns`) and GA field 7 (`adam_ns`) are wall times and exempt from equality, as
`prereg.txt` states. Every other field equals the k6 and k7 receipts.

| prediction (`prereg.txt`) | receipt | result |
|---|---|---|
| P `gcmp2` small, 3 steps, rc 0, K6 line | `gc2-small-s3-P.txt` GCMP2 PASS rc=0 | PASS |
| P `gcmp2` max, 7 steps, rc 0, K6 line | `gc2-max-s7-P.txt` GCMP2 PASS rc=0 | PASS |
| P `gacmp` max rc 0, K6 line | `ga-max-P.txt` GACMP PASS rc=0 | PASS |
| PT `gcmp2` max FAIL rc 47 | `gc2-max-s7-PT.txt` GCMP2 FAIL rc=47, fails 14 | PASS (caught) |
| PT `gcmp2` small FAIL rc 47 | `gc2-small-s3-PT.txt` GCMP2 FAIL rc=47, fails 14 | PASS (caught) |
| P `geval` of rung 5 `ck9000`: E 9000 2243 1445466 539226 | `ge-max-9000-P.txt` same line | PASS (Δ 0) |
| P `geval` of rung 6 `ck30000`: E 30000 2243 1338156 499194 | `ge-max-30000-P.txt` same line | PASS (Δ 0) |
| `t200` K6, K7a, P: rc 0, T 9200 1508182, `ck_after` ec4a8c21… for all three | `t200-{K6,K7a,P}.txt` | PASS (byte-equal) |
| (1) max P GEMM total < min K6 | 105.08 ms < 106.25 ms | holds |
| (2) P and K7a GEMM ranges overlap | P 100.30-105.08, K7a 100.23-101.34 ms | holds |

Neither withdrawal rule fires: the k7 speed claim stands, and the remap removal stays.

## Speed (non-quiet)

`t200`: 200 `gtrainf` steps 9000→9200, in the order K6, K7a, P.

| binary | wall | GPU wait (GT field 9) | launches | wait per launch |
|---|---|---|---|---|
| K6 | 35.659 s | 31.883 s | 63800 | 0.4997 ms |
| K7a (reuse + remap) | 34.092 s | 30.354 s | 63800 | 0.4758 ms |
| P (reuse only) | 34.101 s | 30.371 s | 63800 | 0.4760 ms |

P is 1.0457× faster than K6 in wall time (−4.37%, 7.79 ms per step) and 1.0498× in GPU wait. P and
K7a differ by 9.1 ms over 200 steps (P/K7a 1.00027 wall, 1.00056 wait). Wait is 89.06% of P's wall
(WolframLanguageEvaluator: 35659251962/34100849240 → 1.04570, 31882952613/30371025229 → 1.04978,
(1 − 34100849240/35659251962)·100 → 4.3703, (35659251962 − 34100849240)/200/10^6 → 7.7920,
34100849240/34091751388 → 1.00027, 30371025229/30354176610 → 1.00056,
30371025229/34100849240 → 0.89062, 30371025229/63800/10^6 → 0.47603, 30354176610/63800/10^6 → 0.47577,
31882952613/63800/10^6 → 0.49973). K6 ran 0.222 s slower here than in the k7 window (35.438 s).

`gprof 3` (one profiled step each, 383 launches; ns summed over each id's launches), three rounds in
rotated order: K6 K7a P / K7a P K6 / P K6 K7a.

| round | binary | ids 0-1 (32×32) | ids 32-39 (64×64) | GEMM total (0-7, 32-39) | all ids |
|---|---|---|---|---|---|
| 1 | K6 | 16608254 | 92524427 | 109132681 | 159130652 |
| 1 | K7a | 16489434 | 84238132 | 100727566 | 151509448 |
| 1 | P | 16624829 | 88450518 | 105075347 | 156016530 |
| 2 | K7a | 16357641 | 83870373 | 100228014 | 149839120 |
| 2 | P | 16702907 | 83598192 | 100301099 | 149919847 |
| 2 | K6 | 16445626 | 89806310 | 106251936 | 155609841 |
| 3 | P | 16594781 | 87185470 | 103780251 | 153763841 |
| 3 | K6 | 16494715 | 91883344 | 108378059 | 158457842 |
| 3 | K7a | 16597755 | 84743951 | 101341706 | 150940521 |

GEMM total, mean over the three rounds (WolframLanguageEvaluator: Mean of each triple):

| binary | mean | range / K6 mean | sd | mean / K6 mean |
|---|---|---|---|---|
| K6 | 107.921 ms | 0.0267 | 1.49 ms | 1 |
| K7a | 100.766 ms | 0.0103 | 0.56 ms | 0.93370 |
| P | 103.052 ms | 0.0442 | 2.47 ms | 0.95489 |

- P/K6 per round: 0.9628, 0.9440, 0.9576. 64×64 mean: K7a 0.9221 of K6, P 0.9454.
- Ids 0-1 (32×32): all nine profiles lie within 16.36-16.70 ms. Reuse does not move them.
- P is the noisiest binary. In round 1, P's ids 32 (21.57 ms) and 35 (33.78 ms) ran at K6 level (K6:
  21.64-21.81 and 33.18-33.54), and in round 3 they sat between K6 and K7a. In round 2 P equals K7a
  (100.30 against 100.23 ms). K7a's ids 32 and 35 stayed within 18.62-19.06 and 31.28-31.75 ms in
  every round.

Reading: the 200-step run is the decision measure for training speed, and there P equals K7a to 0.03%
in wall time. The single-step profile adds a P-only spread in ids 32 and 35 that the remap seemed to
damp. Three profiles cannot say whether that spread is a property of the code or of the box
[INFERENCE]: 9.1 ms over 200 steps is 45 µs per step, far below the 2.3 ms mean profile gap
(WolframLanguageEvaluator: (34100849240 − 34091751388)/200/10^3 → 45.489 µs,
(103052232.333 − 100765762)/10^6 → 2.2865 ms). Both pre-registered directions hold, so k7b keeps the
removal. If a later window shows P's 64×64 spread again, the remap comes back as a measured damper,
not as a bank fix.

## Next

The 128×128 retile (256 threads, 8×8 per thread) of the 64×64 GEMMs, then fusion of the softmax into
the attention GEMMs.
