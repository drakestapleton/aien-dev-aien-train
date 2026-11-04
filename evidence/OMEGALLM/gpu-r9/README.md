# Rung 9: BF16 training on rung 7's schedule matches f32 held-out loss (aien-train#52)

Drake adopted BF16 tensor-core training on 2026-11-03 (`docs/omegallm/CONTRACT-BF16.md` section 7).
Adoption was based on bf-t1, which only compared step 2000. Rung 9 is the first long BF16 run and
the quality check the contract requires. It replays rung 7 (`gpu-r7/` on #57) step for step, with
the same init checkpoint, data, seed, schedule and legs, and with `gtrainb` in place of `gtrainf`.
Held-out loss is measured as in rung 7: chip `geval` of `held.tok`, W 2243 windows at T 256,
`merges4096.bin`. `geval` runs on the f32 kernels in both rungs.

Status: EXERCISED on one GB10. It is not QUALIFIED. All 12 windows were opened with
`--gb10 shared --quiet none`, so timings are labelled non-quiet (last close, `run/close.json`: load
average 1.41).

## Result

Final chip line (`run/geval.txt`): `E 30000 2243 1251860 467002`, which is 1.251860 nats and
0.467002 bpb. Rung 7 (f32) ended at `E 30000 2243 1254741 468077`.

Curve (µnats). The schedules are identical, so every step is comparable:

| step | rung 9 BF16 | rung 7 f32 | Δ | Δ % |
|---|---|---|---|---|
| 250 | 2751292 | 2773849 | −22557 | −0.813 |
| 2000 | 1749889 | 1756935 | −7046 | −0.401 |
| 5000 | 1532310 | 1538276 | −5966 | −0.388 |
| 8000 | 1447221 | 1451128 | −3907 | −0.269 |
| 9000 | 1429109 | 1432166 | −3057 | −0.213 |
| 12000 | 1381952 | 1385827 | −3875 | −0.280 |
| 15000 | 1350732 | 1354082 | −3350 | −0.247 |
| 18000 | 1325229 | 1327337 | −2108 | −0.159 |
| 21000 | 1302949 | 1305437 | −2488 | −0.191 |
| 24000 | 1283814 | 1285618 | −1804 | −0.140 |
| 27000 | 1266412 | 1268895 | −2483 | −0.196 |
| 30000 | **1251860** | 1254741 | −2881 | −0.230 |

(WolframLanguageEvaluator: `b9-r7` over the two 12-point lists -> the Δ column,
`N[100 (b9-r7)/r7,4]` -> the Δ % column.)

BF16 is below f32 at every point, but by no more than 0.81%. That is one run per arm, one seed,
and one data order. The prereg asked whether BF16 matches f32 within +0.5%, not whether it is
better. Seed-to-seed spread was not measured, so this run does not show that BF16 is better.

## Pre-registered predictions (`run/prereg.txt`, committed at 8deb268 before the first window)

`run/prereg.sha256` covers `prereg.txt`, `drive.sh` and `leg.sh`, and was checked against the
committed copies before launch. That check is unreceipted: no `sha256sum -c` output was kept.

| prediction | receipt | result |
|---|---|---|
| Q1 (decisive) E at 30000 ≤ 1261014 (Wolfram `Floor[1254741*1.005] -> 1261014`) | E 30000 2243 1251860 467002 | PASS (9,154 µnats of margin; −2,881 against rung 7) |
| Q2 stop rule: E at 2000 ≤ 1765719 | E 2000 2243 1749889 652790 | PASS |
| Q3 determinism: ck2000 and E 2000 equal bf-t1's | ck2000 d8955c2a… and `E 2000 2243 1749889 652790`, both identical | PASS |
| Q4 chip geval curve strictly decreasing | 12 points; Wolfram `AllTrue[Differences[b9],Negative] -> True` (largest difference −14552) | PASS |
| Q5 CPU `eval` of ck30000 within 10 µnats of the chip | `run/eval30000.txt`: `E 30000 2243 1251860 467002`, rc 0 (bin 6da13670…, ck beb5f976…, core 8, nice 19, 11,005.4 s non-quiet) | PASS (Δ 0, identical line) |
| Q6 summed `gtrainb` wall 250→30000 < 7,110.6 s | 5,740.26 s (modeled 6,019.98 s) | PASS |

Q6 (WolframLanguageEvaluator over the ns stamps around each `gtrainb` in `run/train.txt`; they
include checkpoint load and save): the 11 legs 250→30000 sum to 5,740.26 s, which is 0.19295
s/step and 84,913 tokens/s. Rung 7 ran at 0.23901 s/step, so rung 9 is 1.2387x faster
(`7110.62/5740.26`). The measurement came out at 0.954 of the model scaled from bf-t1. The 0→250
leg took 54.67 s. Everything is non-quiet.

Q3 shows that `gtrainb` is deterministic across windows on one chip. The same binary, input and
legs reproduce bf-t1's step-2000 checkpoint byte for byte.

What this does not show:

- A seed or data-order spread for either arm.
- BF16 at other shapes or schedules, including rung 8's 60000 steps.
- Any hardware other than this one GB10.

CONTRACT-BF16 section 7 still holds: a `gtrainb` step is not bitwise equal to the f64 CPU step.
Only the f32 held-out measure is compared.

## Setup

- Binary: `ollm-gb10` 54fb8233… is the bf-g1/bf-t1 product (`gpu-bf/build-2.txt`). This branch
  adds no source change; the last source change on #58 is f28e6ad. The CPU build for Q5 is rung 7's
  `ollm` 6da13670….
- Init: rung 7's `ckL0.bin` fc8835fe…
  (`ollm init ckL0.bin 4096 256 384 12 1536 8 64 1 30000 3000 16`).
- `run/drive.sh` opens one `spark-window` per leg (lease 22 min) and posts STARTING/DONE lines on
  the board. `run/leg.sh` trains 0→250, then runs 3000-step legs that stop exactly at 2000, 9000 and
  30000, and runs `geval` on the saved checkpoint after each leg. Both scripts are rung 8's, with the
  binary, `gtrainb`, the milestones and the stop rule changed.
- `run/leg.sh` does not check the `geval` exit code or the `cp ck.bin ckN.bin` result. This had no
  effect here: all 12 `geval` blocks in `run/geval.txt` end `rc=0`, and the hashes of ck2000, ck9000
  and ck30000 in `run/checkpoints.sha256` equal the `step=N ck=` hashes recorded in `run/geval.txt`.
- `run/leg.sh` line 3 contains the absolute data path under the operator's home directory. The file
  is sha-covered by `run/prereg.sha256`, so it is committed verbatim with the path.
- Q5 driver: `run/cpu-eval.sh` is `/tmp/gk/cpu-eval.sh` copied verbatim; it is byte-identical to the
  copy on rung 8 (#59). Its mtime (2026-11-02T23:03:05Z) precedes this eval's start
  (2026-11-03T14:15:25Z), so `run/eval30000.txt` was produced by this content. It writes the cmd,
  binary and checkpoint sha256, start/end stamps and rc around the `ollm eval` output, and holds an
  absolute home path.
- Checkpoints stay outside the repository; their hashes are in `run/checkpoints.sha256`.
- Window logs: `run/windows.txt` has one line per window. `run/windows-log.txt` holds all 12
  `win-*.txt` files with the home prefix replaced by `~/`.
- `run/drive.out` holds one line, `drive.sh: 5: cannot open windows.txt`. On the first iteration
  the shell applies `< windows.txt` before `2>/dev/null`. The `|| echo 0` fallback set the window
  index to 0 as intended. The same line runs in rung 8's driver.

No infrastructure events occurred. All 12 windows opened with rc 0 and every leg returned rc 0. No
leg was rerun.
