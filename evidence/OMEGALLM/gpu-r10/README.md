# Rung 10: BF16 training on rung 8's 60000-step schedule matches f32 held-out loss (aien-train#52)

Rung 9 (#61) found that BF16 matches f32 on rung 7's 30000-step schedule. Rung 10 asks the same
question over twice as many BF16 steps, where BF16 rounding drift has longer to build up. It replays
rung 8 (`gpu-r8/`, aien-train #59) with the same init checkpoint, data, seed and schedule, and with `gtrainb`
in place of `gtrainf` (BF16, CONTRACT-BF16 section 7). Held-out loss is measured as in rung 8: chip
`geval` of `held.tok`, W 2243 windows at T 256, `merges4096.bin`. `geval` runs on the f32 kernels
in both rungs.

Status: EXERCISED on one GB10. It is not QUALIFIED. All 24 windows were opened with
`--gb10 shared --quiet none`, so timings are labelled non-quiet (last close, `run/close.json`: load
average 1.87).

## Result

Final chip line (`run/geval.txt`): `E 60000 2243 1204466 449322`, which is 1.204466 nats and
0.449322 bpb. Rung 8 (f32) ended at `E 60000 2243 1206290 450002`.

Curve (µnats). The schedules are identical, so the 22 shared steps are directly comparable. Rung 8
has no point at 15500 (see Setup).

| step | rung 10 BF16 | rung 8 f32 | Δ | Δ % |
|---|---|---|---|---|
| 250 | 2749422 | 2770468 | −21046 | −0.760 |
| 2000 | 1754092 | 1755511 | −1419 | −0.081 |
| 5000 | 1536516 | 1542027 | −5511 | −0.357 |
| 8000 | 1452673 | 1455842 | −3169 | −0.218 |
| 9000 | 1435723 | 1439681 | −3958 | −0.275 |
| 12000 | 1392303 | 1396706 | −4403 | −0.315 |
| 15000 | 1364626 | 1366174 | −1548 | −0.113 |
| 15500 | 1360214 | — | — | — |
| 18500 | 1338411 | 1339629 | −1218 | −0.091 |
| 21500 | 1320136 | 1321001 | −865 | −0.065 |
| 24500 | 1305232 | 1305906 | −674 | −0.052 |
| 27500 | 1293555 | 1294503 | −948 | −0.073 |
| 30000 | 1283062 | 1285107 | −2045 | −0.159 |
| 33000 | 1271739 | 1273683 | −1944 | −0.153 |
| 36000 | 1261813 | 1263591 | −1778 | −0.141 |
| 39000 | 1252963 | 1254744 | −1781 | −0.142 |
| 42000 | 1245306 | 1246470 | −1164 | −0.093 |
| 45000 | 1237228 | 1238858 | −1630 | −0.132 |
| 48000 | 1230423 | 1231977 | −1554 | −0.126 |
| 51000 | 1222401 | 1224376 | −1975 | −0.161 |
| 54000 | 1216634 | 1218204 | −1570 | −0.129 |
| 57000 | 1209850 | 1211673 | −1823 | −0.150 |
| 60000 | **1204466** | 1206290 | −1824 | −0.151 |

(WolframLanguageEvaluator: `d = Delete[b,8] - r8` gives the Δ column, and `N[100 d/r8,3]` gives the
Δ % column.)

BF16 is below f32 at all 22 shared points, by 0.05% to 0.76%. Over the second half (30000→60000)
the gap held between 0.09% and 0.16% and did not widen. Over this schedule, then, BF16 rounding shows
no drift that accumulates. As in rung 9 there is one run per arm, one seed and one data order.
Seed-to-seed spread was not measured, so this does not show that BF16 is better.

## Pre-registered predictions (`run/prereg.txt`, committed at a2e1111 before the first window)

`run/prereg.sha256` covers `prereg.txt`, `drive.sh` and `leg.sh`. It was checked against the run
directory after the first failed window and again when the receipts were copied. Both checks are
unreceipted: no `sha256sum -c` output was kept.

| prediction | receipt | result |
|---|---|---|
| R1 (decisive) E at 60000 ≤ 1212321 (Wolfram `Floor[1206290*1.005] -> 1212321`) | E 60000 2243 1204466 449322 | PASS (7,855 µnats of margin; −1,824 against rung 8) |
| R2 stop rule: E at 2000 ≤ 1764288 (Wolfram `Floor[1755511*1.005]`) | E 2000 2243 1754092 654358 | PASS |
| R3 chip geval curve strictly decreasing over 23 points | Wolfram `AllTrue[Differences[b],Negative] -> True` (largest difference −4412) | PASS |
| R4 CPU `eval` of ck60000 within 10 µnats of the chip | `run/eval60000.txt`: `E 60000 2243 1204466 449322`, rc 0, core 8 nice 19, 11,028.1 s (Wolfram `N[(1793770215034986987-1793759186891771461)/10^9,7] -> 11028.14`) | PASS (identical line, Δ 0) |
| R5 summed `gtrainb` wall 250→60000 < 14,688.1 s | 11,478.56 s (modeled 11,528.76 s) | PASS |

R5 (WolframLanguageEvaluator over the ns stamps around each `gtrainb` in `run/train.txt`; they
include checkpoint load and save): the 22 legs 250→60000 sum to 11,478.56 s. That is 0.192110
s/step and 85,285 tokens/s, and 0.9956 of the model scaled from rung 9 (#61). Rung 8 (#59) ran its undisturbed
legs at 0.24471 s/step, so rung 10 is 1.2738x faster per step. Against the lower end of rung 8's
total, the ratio is 1.2796x. The 0→250 leg took 50.87 s. Everything is non-quiet.

There is no determinism check against an earlier BF16 run. Rung 10's learning-rate schedule differs
from rung 9's after step 100, so no checkpoint is expected to match.

What this does not show:

- A seed or data-order spread for either arm.
- BF16 at other shapes.
- Any hardware other than this one GB10.
- Why both BF16 rungs land slightly below f32.

## Setup

- Binary: `/tmp/gk/r10/ollm-gb10` 54fb8233… is a copy of the rung-9 and bf-t1 binary. No source
  changed after f28e6ad on #58. The CPU build for R4 is rung 7's and rung 8's `ollm` 6da13670….
  `/tmp/gk/cpu-eval.sh` lacks the execute bit, so the first two detached launches started nothing
  and wrote no file. The eval that produced `run/eval60000.txt` was started with `sh cpu-eval.sh`.
  `run/cpu-eval.sh` is that script copied verbatim (byte-identical to the copies on #59 and #61); its
  mtime 2026-11-02T23:03:05Z precedes this eval's start (2026-11-04T02:26:26Z). It writes the cmd,
  binary and checkpoint sha256, start/end stamps and rc around the `ollm eval` output, and holds an
  absolute home path.
- Init: rung 8's `ckL0.bin` e02c6234…
  (`ollm init ckL0.bin 4096 256 384 12 1536 8 64 1 60000 3000 16`).
- Legs: `run/leg.sh` trains 0→250, then runs 3000-step legs that stop exactly at 2000, 9000, 15500,
  30000 and 60000, and runs `geval` on the saved checkpoint after each leg.
  - Rung 8 lost a leg mid-window and resumed from T 15500 (`gpu-r8/run/infra-note.txt`, aien-train #59). The 15500
    stop places rung 10's later eval points on rung 8's (18500, 21500, …).
  - Batches derive from (seed, step), so leg boundaries do not change what is trained.
- Driver: `run/drive.sh` opens one `spark-window` per leg (lease 22 min) and posts STARTING/DONE
  lines on the board.
- Scripts: both are rung 9's with the paths, names, milestones, final step and stop-rule bound
  changed. Line 5 of `drive.sh` now reads `windows.txt` through `cat`, so the harmless "cannot open
  windows.txt" line from rungs 8 and 9 no longer appears in `run/drive.out`. `leg.sh` is committed
  verbatim (it is sha-covered), including its absolute home path on line 3.
- `run/leg.sh` does not check the `geval` exit code or the `cp ck.bin ckN.bin` result. This had no
  effect here: all 23 `geval` blocks in `run/geval.txt` end `rc=0`, and the hashes of ck2000, ck9000,
  ck30000 and ck60000 in `run/checkpoints.sha256` equal the `step=N ck=` hashes recorded in
  `run/geval.txt`.
- Checkpoints stay outside the repository; their hashes are in `run/checkpoints.sha256`.
- Window logs: `run/windows.txt` has one line per window. `run/windows-log.txt` holds all 24
  `win-*.txt` files with the home prefix replaced by `~/`.

## Setup failure in the first window (disclosed)

Window gg-r10t1 (20261103T230815Z-5152a3) opened with rc 0, but the leg returned rc **126**.
`spark-window` could not execute `leg.sh` ("Permission denied"; `run/windows-log.txt`, win-1) because
the file was written without the execute bit. No training step ran and no `train.txt` or
`geval.txt` line was written. `ck.bin` still hashed e02c6234… afterwards.

The repair:

1. `chmod +x leg.sh`. The content is unchanged, and `sha256sum -c prereg.sha256` still passes.
2. The driver was restarted. It counts `windows.txt` lines, so the next window was gg-r10t2.
3. The board got a NOTE line.

The committed copies of `leg.sh` and `drive.sh` carry mode 100755. Windows t2 to t24 all opened with
rc 0 and every leg returned rc 0. No leg was rerun, and no other infrastructure events occurred.
