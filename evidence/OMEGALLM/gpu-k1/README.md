# GB10 kernels k1: one-warp softmax, split-K weight gradients, spin wait, gprof (aien-train#52)

Rung 6 (`../gpu-r6/`) trained at 0.3771 s/step with every launch synchronous. Its per-kernel picture
came from the launch counters of `gk.om` only, so this change first adds `gprof` (one `GP id gx gy gz
m n k wait_ns` line per launch of the last profiled step, then 64 bare launches) and then attacks what
it showed:

- `gr.om` softmax forward and backward (ids 15, 16) reduce each row in one warp with a shuffle
  butterfly instead of a shared-memory loop. Mutant s (`OMUTS`) drops the lane-1 butterfly step.
- `gg.om` `ggks` splits the weight-gradient GEMMs (depth R = B·T) into up to 16 slices along R when
  the plain grid would leave SMs idle, and a second launch sums the slices. Mutant p (`OMUTP`) drops
  the last slice.
- `gk.om` `gkwait` spins on the semaphore with `gkpoll` instead of sleeping between polls.

A launch-batching variant (one wait per group of launches) was tried in three earlier windows of
this session and dropped: it never passed `gcmp2`, and the most it could save on the measured wait
profile was 0.69% of the step. This tree has no batching.

Status: EXERCISED on one GB10, window `20261102T132349Z-43ab46` (`win-c1-chk1.txt`), opened
`--gb10 shared --quiet none`. `spark-window` printed "quiet machine", but the quiet lock was not
taken: the rung-6 P5 CPU `eval` held core 7 and the load average was 4.03 at open and 5.08 at close
(`open.json`, `close.json`), so the timings are non-quiet. Not QUALIFIED.

## Setup

- Binaries (`build.txt`): product C 6a4c97a1…, mutant s 4fef03af…, mutant p 0746a333…, omc
  2c824805… (omega-mv e5b32567). After the window the committed tree was rebuilt and gave the same
  three sha256s.
- Timing base A e50ccfa3… is a scratch build with only the one-warp softmax; it is in no commit and
  is used only for the `t200` comparison.
- `prereg.txt` was written before the window opened; `prereg.sha256` holds its hash and that of
  `run.sh`. In the committed `run.sh`, `win-c1-chk1.txt` and `open.json` the home prefix is replaced
  by `~/`, so the committed `run.sh` hashes to 6e7d4873… instead of the registered 95d2d7b7…;
  nothing else differs. `prereg.txt` is unchanged (80dde8a7…).
- Checkpoints: `gc2-small` uses the small-shape checkpoint, `gc2-max` rung 5's `ckb8`, `ga-max`
  rung 5's `ck250`, `ge-max-9000` rung 5's `ck9000`, `ge-max-30000` rung 6's `ck30000`, `t200` a fresh
  copy of rung 6's `ck9000` per binary.

## Results

| prediction (`prereg.txt`) | receipt | result |
|---|---|---|
| C `gcmp2` small, 3 steps, rc 0 | `gc2-small-s3-C.txt` GCMP2 PASS rc=0 | PASS |
| C `gcmp2` max, 7 steps, rc 0 | `gc2-max-s7-C.txt` GCMP2 PASS rc=0 | PASS |
| C `gacmp` max rc 0 | `ga-max-C.txt` GACMP PASS rc=0 | PASS |
| mutant s FAIL rc 47 at small and max | `gc2-small-s3-CS.txt`, `gc2-max-s7-CS.txt` GCMP2 FAIL rc=47 | PASS (caught) |
| mutant p FAIL rc 47 at max; small reported only | `gc2-max-s7-CP.txt` rc=47; `gc2-small-s3-CP.txt` also rc=47 | PASS (caught at both) |
| C `geval` of rung 5 `ck9000` = E 9000 2243 1445466 539226 | `ge-max-9000-C.txt` | PASS (identical) |
| C `geval` of rung 6 `ck30000` = E 30000 2243 1338156 499194 | `ge-max-30000-C.txt` | PASS (identical) |
| `gprof` C, report only | `prof-C.txt` rc=0, 383 GP lines | reported |
| `t200` A and C both rc 0 before any speed claim | `t200-A.txt`, `t200-C.txt` rc=0 | PASS |

## Speed (non-quiet)

`t200` runs 200 `gtrainf` steps (9000→9200) from rung 6's `ck9000`, including process start and the
checkpoint load and save.

| binary | wall | GPU wait (GT field 9) | launches | wait per launch |
|---|---|---|---|---|
| A, softmax only | 56.862 s | 52.498 s | 57400 | 0.9146 ms |
| C, this tree | 48.108 s | 44.271 s | 63800 | 0.6939 ms |

C is 1.1820× faster than A in wall time and 1.1858× in GPU wait (WolframLanguageEvaluator:
56.862/48.108, 52.497924775/44.271395857); the wait is 92.02% of C's wall. Split-K adds 32 launches
per step (287 → 319) and still lowers the total wait. The losses differ (A T 9200 1508278, C T 9200
1507707) because split-K sums the weight gradients in a different order; both are within `gcmp2`'s
tolerances against the CPU model.

`prof-C.txt` attributes 146.07 ms of the profiled step's GPU wait to the GEMMs (ids 0-7) and 86.79 ms
to the row kernels (ids 9-24), 232.85 ms in all. `../gpu-k2/` retiles the GEMMs.
