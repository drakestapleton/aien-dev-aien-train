# GB10 kernels k4: warp-per-row cross-entropy (aien-train#52)

After `../gpu-k3/`, the cross-entropy kernel (`gr.om` id 21 `grce`) was among the largest single
kernels of the profiled step (13.511 ms in this window's `prof-K3.txt`). It ran one thread per row of
the R × V logit matrix: each thread walked its row's 4096 columns, so a warp's loads touched 32 rows
at a stride of 4·V bytes, and it made three read passes and two write passes over the matrix (max;
exp, sum and store e; scale and store). This change runs one warp per row:

- Lane l of row r reads columns l + 32u, 8 coalesced 128-byte lines per step of 256 columns.
- Pass 1: lane max, then a 16-8-4-2-1 `SHFL.BFLY` max (`grwred 1`). Pass 2: each lane Kahan-sums
  e = ex2(l·log2e − m·log2e) over its 128 columns and stores nothing; the lane total s − c is then
  summed by the butterfly. Pass 3 recomputes e with the same FFMA and `MUFU.EX2` as pass 2 (the
  same value), scales it by sc/sum and stores it. One full write pass is gone: 3 reads + 1 write of
  the matrix instead of 3 + 2.
- l_y is loaded before any store. The lane that owns column y (y & 31) is the lane that stored L[y]
  in pass 3; it alone subtracts sc from L[y] and writes the row stats (m, sum, l_y), so no lane
  reads another lane's store. The other lanes exit after pass 3.
- The sum order differs from k3 (per lane, then a tree), so results are not bit-identical to k3.
  `gg.om` launches R·32 threads (arg 0 = R·32, grid `ggcd r 64 1 1`). `grall` refuses V that is not
  a multiple of 256 (model V 4096; small test shape V 256).
- New build-time mutant x (`build.sh --mutant x`, `gr.om` `OMUTX 0`): the CE warp sum skips the
  lane-1 butterfly step. The letter c was taken by a CPU mutant.
- Mutant k (`OMUTK 0`) now removes Kahan from each lane's 128-term sum instead of from the
  4096-term row sum. It was run as an observation, not a control (below).

Status: EXERCISED on one GB10, window `20261102T141140Z-b2bc92` (`win-k4.txt`), opened
`--gb10 shared --quiet none`. `spark-window` printed the verdict "quiet machine", but the quiet lock
was not taken and the rung-6 P5 CPU `eval` held core 7 (load average 4.26 at open and 3.84 at close,
`open.json`, `close.json`), so the timings are non-quiet. Not QUALIFIED.

## Setup

- Binaries (`build.txt`): product K4 72289c19…, mutant x f6a7e8ec…, mutant k c81e340c…, omc
  2c824805… (omega-mv e5b32567). After the window the committed tree was rebuilt and gave the same
  three sha256s. The timing base K3 836d3be1… is the parent commit's product (`../gpu-k3/`), run
  again in this window.
- Static checks before the window, as recorded in `prereg.txt`, and repeated on this commit's tree
  in `disasm.txt` (`tests/omegallm/gpu-disasm.sh 21`, nvdisasm `-b SM121`): the 64-slot code dump
  differs from the parent commit's dump in slot 21 only; slot 21 (3360 B) has 10 `SHFL.BFLY` (5 max,
  5 sum), 16 `MUFU.EX2`, 1 `MUFU.RCP` and 3 EXITs (row guard, non-owner lanes, end); mutant x's slot
  21 has 9, its sum steps 0x10 0x8 0x4 0x2.
- The static check found one bug before any chip run: `grwred` uses R65 as shuffle scratch, and the
  first build's pass 3 read R65 as −m·log2e after the warp sum. Pass 3 now recomputes R65 = R43·R29
  from the saved max (`FMUL` at 0x0940). The window ran only the fixed build; the binary hashes in
  `prereg.txt` are the fixed ones.
- `prereg.txt` was written before the window opened; `prereg.sha256` holds its hash (a33c1ac8…) and
  that of `run.sh` (191b3918…). The `run.sh` hash was taken after the window; the file was not edited
  between writing and running. In the committed `run.sh`, `win-k4.txt` and the window JSON the home
  prefix is replaced by `~/`, so the committed `run.sh` hashes to c789b5e7…; nothing else differs.
- Checkpoints as in `../gpu-k3/`: `gc2-small` the small-shape checkpoint, `gc2-max` rung 5's `ckb8`,
  `ga-max` rung 5's `ck250`, `ge-max-9000` rung 5's `ck9000`, `ge-max-30000` rung 6's `ck30000`,
  `t200` a fresh copy of rung 6's `ck9000` per binary.

## Results

| prediction (`prereg.txt`) | receipt | result |
|---|---|---|
| K4 `gcmp2` small, 3 steps, rc 0 | `gc2-small-s3-K4.txt` GCMP2 PASS rc=0 | PASS |
| K4 `gcmp2` max, 7 steps, rc 0 | `gc2-max-s7-K4.txt` GCMP2 PASS rc=0 | PASS |
| K4 `gacmp` max rc 0 | `ga-max-K4.txt` GACMP PASS rc=0 | PASS |
| mutant x `gcmp2` small FAIL rc 47 | `gc2-small-s3-KX.txt` GCMP2 FAIL rc=47 | PASS (caught) |
| mutant x `gcmp2` max FAIL rc 47 | `gc2-max-s7-KX.txt` GCMP2 FAIL rc=47 | PASS (caught) |
| mutant x `geval` of rung 5 `ck9000`: \|E − 1445466\| ≥ 10 | `ge-max-9000-KX.txt` E 9000 2243 1083383 404152 | PASS (caught, Δ −362083) |
| K4 `geval` of rung 5 `ck9000`: \|E − 1445466\| < 10 (CPU `eval`) | `ge-max-9000-K4.txt` E 9000 2243 1445466 539226 | PASS (Δ 0) |
| K4 `geval` of rung 6 `ck30000`: \|E − 1338156\| < 10 (chip value) | `ge-max-30000-K4.txt` E 30000 2243 1338156 499194 | PASS (Δ 0) |
| mutant k `geval` `ck9000`, `ck30000`: reported only | `ge-max-9000-KK.txt` E 9000 2243 1445465 539226; `ge-max-30000-KK.txt` E 30000 2243 1338156 499194 | observation: Δ −1 and 0 |
| `gprof` K3 and K4: id 21 lower for K4 | `prof-K3.txt` GP 21 gx 256 13511312 ns; `prof-K4.txt` GP 21 gx 8192 3676255 ns | PASS |
| `t200` K3 then K4, both rc 0; K4 T line reported | `t200-K3.txt` T 9200 1508121, `ck_after` 70ede05c… (same as `../gpu-k3/`); `t200-K4.txt` T 9200 1508182, `ck_after` ec4a8c21… | PASS (both rc 0) |

A wrong half-warp sum (mutant x) moves the held-out loss by 0.362 nats, so the `geval` gate and both
`gcmp2` runs catch it. Without Kahan per lane (mutant k) the E line moves by at most 1 µnat, below
the 10 µnat gate. With 128 terms per lane the plain sum's rounding is too small for the gate to
see, so mutant k is no longer a control for this kernel and is not counted as one. The K4 training
loss after 200 steps is 61 µnats above K3's; the runs differ in the CE sum order, so the trajectories
diverge after the first step [INFERENCE: one sample, no repeat].

## Speed (non-quiet)

`t200`: 200 `gtrainf` steps 9000→9200 from rung 6's `ck9000`, both binaries in this window, K3 first.

| binary | wall | GPU wait (GT field 9) | launches | wait per launch |
|---|---|---|---|---|
| K3, k3 | 41.959 s | 38.160 s | 63800 | 0.5981 ms |
| K4, this tree | 40.289 s | 36.455 s | 63800 | 0.5714 ms |

K4 is 1.0415× faster than K3 in wall time (−3.98%) and 1.0468× in GPU wait (WolframLanguageEvaluator:
41959244921/40289056359 → 1.04146, 38159852007/36455215481 → 1.04676, (1 − 40289056359/41959244921)·100
→ 3.981). The wait is 90.48% of K4's wall. K3 ran 0.282 s faster here than in the k3 window (42.241 s).

`prof-K3.txt` and `prof-K4.txt` (one profiled step each, 383 launches, ns summed per line):

| id | kernel | launches | k3 ms | k4 ms | speed-up | k3 GB/s | k4 GB/s |
|---|---|---|---|---|---|---|---|
| 21 | `grce` | 1 | 13.511 | 3.676 | 3.675 | 99.3 | 292.1 |

GB/s counts the bytes each version must move at the max shape (16384 rows × 4096 columns, f32,
256 MiB per pass): k3 makes 5 passes, k4 makes 4 (WolframLanguageEvaluator: 5·16384·4096·4/13511312
→ 99.337, 4·16384·4096·4/3676255 → 292.07, 13511312/3676255 → 3.6753). The profile total fell from
196.03 ms to 179.84 ms (1.0901×, WolframLanguageEvaluator: 196034469/179835228 → 1.09008); `grce` saved
9.84 ms of that and the other kernels 6.36 ms, within the run-to-run spread of one profile
[INFERENCE: one profile per binary, no repeat]. `grce` is now 2.04% of the profiled wait.

## Next targets

In `prof-K4.txt` the largest remaining wait is the attention block: the 256×256×32 score GEMM
(id 35 at batch gz 512, 16 launches, 13.876 ms; id 35 also serves 33 other GEMM launches), the two
32-tile attention GEMMs at batch 512 (ids 1 and 0, 12.580 and 11.728 ms) and the softmax kernels
(id 16 `grsoftb` 14.018 ms, id 15 `grsoftf` 9.553 ms), 61.76 ms of the 179.84 ms together. Next is
causal tile skipping or a fused attention kernel, then the softmax kernels.
