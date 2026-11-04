# Rung 8: the v2 shape on a 60000-step schedule beats rung 7 (aien-train#52)

Rung 7 (`../gpu-r7/`) trained the v2 maximum shape (V 4096, T 256, D 384, H 12, F 1536, L 8, B 64,
P 15,833,472) for 30000 steps and ended at a chip `geval` of 1.254741 nats on `held.tok`. Rung 8
asks whether doubling the schedule, with nothing else changed, lowers held-out loss further. It needs
no code change: the same chip binary trains it. The held-out measure is the same: chip `geval` of
`held.tok`, W 2243 windows at T 256, `merges4096.bin`.

Status: EXERCISED on one GB10. Not QUALIFIED. All 24 windows were opened
`--gb10 shared --quiet none`; `spark-window` printed "quiet machine" for 23 of them (`run/windows-log.txt`;
the 24th, t9, was closed by hand after its leg was killed, see Infrastructure), but the quiet lock was
not taken and host CPU jobs ran beside it, so timings are labelled non-quiet (last close,
`run/close.json`: load average 4.61).

## Result

Final chip line (`run/geval.txt`): `E 60000 2243 1206290 450002`, 1.206290 nats, 0.450002 bpb.

| run | steps | final nats | Δ vs rung 8 µnats | Δ % |
|---|---|---|---|---|
| rung 8 (v2, 60000-step schedule) | 60000 | **1.206290** | — | — |
| rung 7 (v2, 30000-step schedule) | 30000 | 1.254741 | −48,451 | −3.86 |
| rung 6 (v1 max, 30000-step schedule) | 30000 | 1.338156 | −131,866 | −9.85 |

(WolframLanguageEvaluator: `1206290-1254741 -> -48451`, `100 (1206290-1254741)/1254741 -> -3.86143`,
`1206290-1338156 -> -131866`, `100 (1206290-1338156)/1338156 -> -9.85431`.)

Full curve (`run/geval.txt`, µnats): 250 2770468, 2000 1755511, 5000 1542027, 8000 1455842,
9000 1439681, 12000 1396706, 15000 1366174, 18500 1339629, 21500 1321001, 24500 1305906,
27500 1294503, 30000 1285107, 33000 1273683, 36000 1263591, 39000 1254744, 42000 1246470,
45000 1238858, 48000 1231977, 51000 1224376, 54000 1218204, 57000 1211673, 60000 1206290.
The legs after 15000 start at 15500, 18500, … because leg t9 was killed (see Infrastructure).

Observation, not a pass condition (the schedules differ after step 100): at step 30000 rung 8 is at
1285107, 30,366 µnats above rung 7's final value, because its learning rate is still 0.5508 of peak
there against 0.1 for rung 7. It passes rung 7's final value between steps 39000 (1254744, 3 µnats
above) and 42000. The last leg (57000→60000) still gained 5,383 µnats, the smallest step of the curve
(`Max[Differences[ev]] -> -5383`).

## Pre-registered predictions (`run/prereg.txt`)

`run/prereg.txt` and `run/prereg.sha256` were written locally before the first window: the run
directory's `prereg.txt` has mtime 2026-11-02T20:56:25Z, 7 s before window 20261102T205632Z (t1)
opened. They were first committed in f41d814, with the evidence, after the run. The file mtime is the
only timing evidence; there is no commit or other receipt from before the run.

| prediction | receipt | result |
|---|---|---|
| P1 final E at 60000 < 1254741 | `run/geval.txt`: E 60000 2243 1206290 450002 | PASS (−48,451 µnats) |
| P2 stop rule: E at 2000 < 1797226 | E 2000 2243 1755511 | PASS |
| P3 chip geval curve strictly decreasing | 22 points; Wolfram `And@@Thread[Differences[ev]<0] -> True` | PASS |
| P4 CPU `eval` of ck60000 within 10 µnats of the chip | `run/eval60000.txt`: `E 60000 2243 1206290 450002`, rc 0 (bin 6da13670…, ck 45a73a3a…, core 8, nice 19, 11,520.1 s non-quiet) | PASS (Δ 0, identical line) |
| P5 summed `gtrainf` wall 250→60000 < 15,709 s | 14,688.1-14,864.0 s | PASS |

P5 (WolframLanguageEvaluator over the ns stamps around each `gtrainf` in `run/train.txt`): the 22
legs with an end stamp, including the ENOSPC leg that wrote no step (62.2 s), sum to 14,561.29 s. The
killed leg t9 has a start stamp (1793659229187893163) and no end stamp; its wall is bounded below by
the write of T 15500 (22:42:36Z, +126.81 s) and above by the next leg's start (+302.68 s). Total
14,688.11-14,863.98 s, at most 0.9462 of the bound. Excluding the two disturbed legs, 59,250 steps
took 14,499.09 s: 0.24471 s/step, 66,953 tokens/s (rung 7: 0.23901 s/step on the same binary;
non-quiet).

What this does not show: whether the gain comes from more distinct data or from more passes over the
same data (the sampler draws hashed windows with replacement, `data.om` `obatch`; 983,040,000 token
positions, 62.09 per parameter). Rung 8 also spends twice rung 7's chip time; a rung-7-length run of a
larger shape at equal chip time was not run.

## Setup

- Binary: rung 7's `ollm-gb10` 1853303e… (`../gpu-r7/build.txt`, sources b312942; this branch
  adds no source change). CPU build for P4: `ollm` 6da13670… (same file).
- Init: `ollm init ckL0.bin 4096 256 384 12 1536 8 64 1 60000 3000 16`, sha256 e02c6234…. `cmp -l`
  against rung 7's ckL0 shows bytes 81-82 only (TOTAL 30000→60000): same seed, parameters, data,
  batch and peak LR 3e-3; the LR decay runs over 60000 steps.
- `run/drive.sh` opens one `spark-window` per leg (lease 22 min) and posts STARTING/DONE board lines.
  `run/leg.sh` trains 0→250, then 3000-step legs that stop exactly at 2000, 9000, 30000 and 60000, then
  runs `geval` of the saved checkpoint. `run/prereg.sha256` covers `prereg.txt` only; the scripts
  were not hashed before the first window and are committed as they ran.
- `run/leg.sh` does not check the `geval` exit code or the `cp ck.bin ckN.bin` result. This had no
  effect here: all 22 `geval` blocks in `run/geval.txt` end `rc=0`, and the hashes of ck2000, ck9000,
  ck30000 and ck60000 in `run/checkpoints.sha256` equal the `step=N ck=` hashes `leg.sh` recorded in
  `run/geval.txt` before each `geval`.
- `run/leg.sh` line 3 contains the absolute data path under the operator's home directory. The file is
  committed as it ran, so the path was not rewritten.
- `run/drive.sh` touches and removes `/tmp/aien-q36-live-down-for-tests` around each window. The
  marker is legacy from earlier lanes; nothing in this run reads it, and it is harmless.
- There is no `run/drive.out` receipt. The first driver ran with its output not kept; the relaunched
  driver's `drive.out` (mtime 22:45:29Z) is 0 bytes, so nothing was committed.
- P4 driver: `run/cpu-eval.sh` is `/tmp/gk/cpu-eval.sh` copied verbatim (mtime 2026-11-02T23:03:05Z,
  before the eval started at 2026-11-03T01:48:30Z, so it was not edited after producing
  `run/eval60000.txt`). `sh cpu-eval.sh ck60000.bin eval60000.txt 8` writes the cmd, binary and
  checkpoint sha256, start/end stamps and rc around the `ollm eval` output. It also holds an
  absolute home path.
- Checkpoints stay outside the repository (380,003,448 bytes each); hashes in `run/checkpoints.sha256`.
- Window logs: `run/windows.txt` (one line per window), `run/windows-log.txt` (all 24 `win-*.txt`,
  home prefix replaced with `~/`).

## Infrastructure events (`run/infra-note.txt`)

1. Window gg-r8t3, 2026-11-02 21:04Z: the root file system reached 0 bytes free and `gtrainf` exited
   rc 70 (ENOSPC) on the checkpoint write before any T line. `gtrainf` saves via `ck.bin.tmp` and
   rename, so `ck.bin` stayed the step-2000 checkpoint (4563191b…). The run directory moved to
   `/dev/shm` behind a symlink, the partial `.tmp` was removed, and the driver resumed from 2000. The
   failed leg is a disk failure, not a training failure; its 62.2 s are in the P5 sum.
2. Window gg-r8t9, 22:42Z: the agent session that owned `drive.sh` ended and took the leg with it
   after T 15500 (no rc line). `ck.bin` held step 15500 and no `.tmp` was left. Batches derive from
   (seed, step), so resuming from 15500 trains the same steps. The orphaned window was closed by hand,
   the run directory was copied back to `/tmp/gk/r8/run` (`ck.bin` cmp equal), and `drive.sh` was
   relaunched under `setsid nohup`.

No leg was rerun to replace a failing receipt; both events are counted in P5.
