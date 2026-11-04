# GB10 kernels k3: warp-per-row RMS norm (aien-train#52)

After `../gpu-k2/`, `prof-C2.txt` put 22.36 ms of the profiled step's 203.30 ms GPU wait in the two
RMS norm kernels (`gr.om` ids 10 `grrmsf` and 11 `grrmsb`), which ran one thread per row: each thread
walked its row's D columns, so a warp's loads touched 32 rows at a stride of 4·D bytes, and both
kernels read their inputs twice (sum pass, then output pass). This change runs one warp per row:

- Lane l of row r holds columns l + 32u (u < D/32) in registers, so every warp load and store is one
  coalesced 128-byte line. `grrmsf` reads v once (k2 read it twice); `grrmsb` fuses its two passes
  and reads v, g, da, dh and s once.
- Row sums are a per-lane FFMA chain followed by a 16-8-4-2-1 `SHFL.BFLY` butterfly (`grwred`). The
  summation order differs from k2, so results are not bit-identical to k2; every element-wise
  operation keeps k2's order.
- `gg.om` launches R·32 threads for these two kernels (arg 0 = R·32, grid `ggcd r 64 1 1`). `grall`
  refuses D or T that is not a multiple of 32 (the model's shapes are D 256, T 256; the small test
  shape is D 64).
- New build-time mutant r (`build.sh --mutant r`, `gr.om` `OMUTR 0`): `grrmsb`'s row sum
  sum(da·g·v) skips the lane-1 butterfly step. Mutants s, p and t still build from this tree but were
  not rerun; the kernels they mutate did not change (`disasm.txt`: only slots 10 and 11 differ).

Status: EXERCISED on one GB10, window `20261102T135748Z-ed1c5b` (`win-k3-chk2.txt`), opened
`--gb10 shared --quiet none`. The quiet lock was not taken; the rung-6 P5 CPU `eval` held core 7 and
the load average was 1.52 at open and 3.77 at close (`open.json`, `close.json`), so the timings are
non-quiet. The first attempt, window `20261102T135737Z-bafe66` (`win-k3-chk1.txt`), ran nothing:
`run.sh` was not executable (exec rc 126). Its mode was changed, not its content, and the same
`run.sh` ran in k3-chk2. Not QUALIFIED.

## Setup

- Binaries (`build.txt`): product K3 836d3be1…, mutant r fcd3fe11…, omc 2c824805… (omega-mv
  e5b32567). After the window the committed tree was rebuilt and gave the same two sha256s. The
  timing base C2 44ea8a17… is the parent commit's product (`../gpu-k2/`), run again in this window.
- Static checks before the window, as recorded in `prereg.txt`, and repeated on this commit's tree
  in `disasm.txt` (`tests/omegallm/gpu-disasm.sh 10 11`, nvdisasm `-b SM121`): the 64-slot code dump
  differs from the parent commit's dump in slots 10 and 11 only; slot 10 (864 B) has 5 `SHFL.BFLY`
  and one `MUFU.RSQ`, slot 11 (1216 B) has 5 `SHFL.BFLY`; mutant r's slot 11 has 4, masks 0x10 0x8
  0x4 0x2. Each slot has two EXITs: the out-of-range row guard and the end.
- `prereg.txt` was written before the window opened; `prereg.sha256` holds its hash (42be5b4e…) and
  that of `run.sh` (99bfa445…). The `run.sh` hash was taken after the window; the file was not edited
  between writing and running (only its mode changed). In the committed `run.sh`, the `win-*.txt`
  files and the window JSON the home prefix is replaced by `~/`, so the committed `run.sh` hashes to
  6c5c79cb…; nothing else differs.
- Checkpoints as in `../gpu-k2/`: `gc2-small` the small-shape checkpoint, `gc2-max` rung 5's `ckb8`,
  `ga-max` rung 5's `ck250`, `ge-max-9000` rung 5's `ck9000`, `ge-max-30000` rung 6's `ck30000`,
  `t200` a fresh copy of rung 6's `ck9000` per binary.

## Results

| prediction (`prereg.txt`) | receipt | result |
|---|---|---|
| K3 `gcmp2` small, 3 steps, rc 0 | `gc2-small-s3-K3.txt` GCMP2 PASS rc=0 | PASS |
| K3 `gcmp2` max, 7 steps, rc 0 | `gc2-max-s7-K3.txt` GCMP2 PASS rc=0 | PASS |
| K3 `gacmp` max rc 0 | `ga-max-K3.txt` GACMP PASS rc=0 | PASS |
| mutant r `gcmp2` max FAIL rc 47 | `gc2-max-s7-KR.txt` GCMP2 FAIL rc=47 | PASS (caught) |
| mutant r `gcmp2` small FAIL rc 47 | `gc2-small-s3-KR.txt` GCMP2 FAIL rc=47 | PASS (caught) |
| K3 `geval` of rung 5 `ck9000`: \|E − 1445466\| < 10 (CPU `eval`) | `ge-max-9000-K3.txt` E 9000 2243 1445466 539226 | PASS (Δ 0) |
| K3 `geval` of rung 6 `ck30000`: \|E − 1338156\| < 10 (C2 chip value) | `ge-max-30000-K3.txt` E 30000 2243 1338156 499194 | PASS (Δ 0) |
| `gprof` K3: ids 10 and 11 launch gx = R·32/64 | `prof-K3.txt` rc=0: 17 launches each, gx 8192 at the max shape (k2: 256) | PASS |
| `t200` C2 then K3, both rc 0; K3 T line reported | `t200-C2.txt` T 9200 1507707, `ck_after` fde1fae9… (same as `../gpu-k2/`); `t200-K3.txt` T 9200 1508121, `ck_after` 70ede05c… | PASS (both rc 0) |

The K3 training loss after 200 steps is 414 µnats above C2's. The two runs differ only in the RMS
sum order, so the trajectories diverge after the first step; one pair of 200-step runs says nothing
about whether either order trains better [INFERENCE: one sample, no repeat].

## Speed (non-quiet)

`t200`: 200 `gtrainf` steps 9000→9200 from rung 6's `ck9000`, both binaries in this window, C2 first.

| binary | wall | GPU wait (GT field 9) | launches | wait per launch |
|---|---|---|---|---|
| C2, k2 | 44.674 s | 40.848 s | 63800 | 0.6402 ms |
| K3, this tree | 42.241 s | 38.398 s | 63800 | 0.6019 ms |

K3 is 1.0576× faster than C2 in wall time (−5.45%) and 1.0638× in GPU wait (WolframLanguageEvaluator:
44674481439/42241119437 → 1.05761, 40847864725/38398155652 → 1.06380). The wait is 90.90% of K3's
wall. C2 ran 0.231 s faster here than in the k2 window (44.906 s).

`prof-K3.txt` (one profiled step, ns summed over launches):

| id | kernel | launches | k2 ms | k3 ms | speed-up | k3 ms per launch | k3 GB/s |
|---|---|---|---|---|---|---|---|
| 10 | `grrmsf` | 17 | 6.022 | 2.406 | 2.503 | 0.1415 | 237.6 |
| 11 | `grrmsb` | 17 | 16.338 | 6.614 | 2.470 | 0.3890 | 215.8 |

GB/s counts the bytes the k3 kernel must move at the max shape (16384 rows × 256 columns, f32):
`grrmsf` reads v and writes y (2 × 16 MiB) plus s and g; `grrmsb` reads v, da, dh and writes dh, w
(5 × 16 MiB) plus s and g (WolframLanguageEvaluator: (2·16777216+65536+1024)/(2405773/17) → 237.58,
(5·16777216+65536+1024)/(6613658/17) → 215.80). Counted the same way, k2 moved 94.9 and 87.4 GB/s.
The two kernels saved 13.34 ms of the profile; its total fell from 203.30 ms to 192.63 ms (1.0554×),
so the other kernels came out 2.67 ms slower in this single profiled step, which is within the
run-to-run spread of one profile [INFERENCE: one profile per binary, no repeat]. The RMS kernels are
now 4.68% of the profiled wait.

## Next targets

Unchanged from `../gpu-k2/` apart from the RMS kernels: `grce` (id 21, one thread per row, 13.2 ms in
k2's profile) is next, but a warp-parallel sum changes the Kahan sum that mutant k removes, so it
needs a new mutant design; then the attention batched GEMMs (QK^T id 35 writes the T×T score tensor),
via causal tile skipping or a fused attention kernel; then the softmax kernels.
