# GB10 kernels k2: 64×64 f32 GEMM tile (aien-train#52)

After `../gpu-k1/`, `prof-C.txt` put 146.07 ms of the profiled step's 232.85 ms GPU wait in the
f32 GEMMs, which ran a 32×32 output tile per 64-thread block (4×4 per thread). This change adds a
64×64 tile to `gk.om`:

- Kernel ids 32-39 (id = md0 + 2·md1 + 4·beta + 32): 64 threads, an 8×8 output microtile per
  thread, K8 shared-memory tiles, 4352 B of shared memory, 144 GPR. `gktile` picks them when m and n
  are both multiples of 64; the 32×32 kernels (ids 0-7, 104 GPR, 4608 B) stay for every other shape,
  which in this model means the n = 32 per-head attention products (gz 512).
- Each output element keeps the 32 kernel's FFMA chain order over k, so the result is meant to be
  bit-identical to k1, not merely within tolerance.
- The runtime mutant switch (`gkmut`, id 8) is replaced by build-time mutant t (`OMUTT`): kernels
  32-39 drop the depth-7 product of each thread's first accumulator in every K tile (one FFMA per
  tile). Mutants s and p of k1 still build from this tree
  but were not rerun; the kernels they mutate did not change.

Status: EXERCISED on one GB10, window `20261102T133802Z-ff7028` (`win-c2-chk1.txt`), opened
`--gb10 shared --quiet none`. The quiet lock was not taken: the rung-6 P5 CPU `eval` held core 7 and
the load average was 4.08 at open and 4.04 at close (`open.json`, `close.json`), so the timings are
non-quiet. `prereg.txt` names ollm-night as the load; that is out of date, because ollm-night had
ended at 13:15Z, before this window opened. Not QUALIFIED.

## Setup

- Binaries (`build.txt`): product C2 44ea8a17…, mutant t 254c249b…, omc 2c824805… (omega-mv
  e5b32567). After the window the committed tree was rebuilt and gave the same two sha256s. The
  timing and bit-identity base C1 6a4c97a1… is the parent commit's product (`../gpu-k1/`).
- Static checks before the window, as recorded in `prereg.txt` (nvdisasm `-b SM121` on code slots
  dumped by a scratch harness): slots 0 and 32-39 decode with one EXIT each and are each under
  16384 B; slot 0 is byte-identical between product and mutant t; mutant t differs only in slots
  32-39, with 511 FFMA in slot 32 (product 512) and 575 in slot 36 (product 576).
- `tests/omegallm/gpu-disasm.sh` had been failing since rung 5 (omc error 5: `model.om` calls
  `ogmask`, which the dump's source list did not contain) and `gpu-dump.om` wrote only 32 slots.
  This commit adds `nogpu.om` to the list and dumps all 64 slots; `disasm.txt` is its run on this
  tree: slots 0, 32 and 36 hash the same as the scratch dumps, and the product FFMA counts match.
- `prereg.txt` was written before the window opened; `prereg.sha256` holds its hash (b65cb509…)
  and that of `run.sh` (6d6031c9…). In the committed `run.sh`, `win-c2-chk1.txt` and the window JSON
  the home prefix is replaced by `~/`, so the committed `run.sh` hashes to b02592ef…; nothing else
  differs.
- Checkpoints as in `../gpu-k1/`: `gc2-small` the small-shape checkpoint, `gc2-max` rung 5's `ckb8`,
  `ga-max` rung 5's `ck250`, `ge-max-9000` rung 5's `ck9000`, `ge-max-30000` rung 6's `ck30000`,
  `t200` a fresh copy of rung 6's `ck9000` per binary.

## Results

| prediction (`prereg.txt`) | receipt | result |
|---|---|---|
| C2 `gcmp2` small, 3 steps, rc 0 | `gc2-small-s3-C2.txt` GCMP2 PASS rc=0 | PASS |
| C2 `gcmp2` max, 7 steps, rc 0 | `gc2-max-s7-C2.txt` GCMP2 PASS rc=0, 124.98 s | PASS |
| C2 `gacmp` max rc 0 | `ga-max-C2.txt` GACMP PASS rc=0 | PASS |
| mutant t `gcmp2` max FAIL rc 47 | `gc2-max-s7-CT.txt` GCMP2 FAIL rc=47 | PASS (caught) |
| mutant t `gcmp2` small, report only | `gc2-small-s3-CT.txt` GCMP2 FAIL rc=47 | caught at small too |
| C2 `geval` of rung 5 `ck9000` = E 9000 2243 1445466 539226 | `ge-max-9000-C2.txt` | PASS (identical) |
| C2 `geval` of rung 6 `ck30000` = E 30000 2243 1338156 499194 | `ge-max-30000-C2.txt` | PASS (identical) |
| `gprof` C2 shows ids 32-39 for m, n multiples of 64 | `prof-C2.txt` rc=0 | PASS: all 131 such launches ran 32-39; the 32 launches with n = 32 ran ids 0 and 1 |
| `t200` C1 then C2, both rc 0; C2 T line and `ck_after` equal to C1 | `t200-C1.txt`, `t200-C2.txt`: both T 9200 1507707, both `ck_after` fde1fae9… | PASS (bit-identical checkpoint after 200 steps) |

## Speed (non-quiet)

`t200` as in `../gpu-k1/`: 200 `gtrainf` steps 9000→9200 from rung 6's `ck9000`, both binaries in
this window, C1 first.

| binary | wall | GPU wait (GT field 9) | launches | wait per launch |
|---|---|---|---|---|
| C1, k1 | 47.650 s | 43.840 s | 63800 | 0.6872 ms |
| C2, this tree | 44.906 s | 41.135 s | 63800 | 0.6448 ms |

C2 is 1.0611× faster than C1 in wall time (−5.76%) and 1.0658× in GPU wait (WolframLanguageEvaluator:
47.649948632/44.905925594, 43.840489630/41.135334842). Against the softmax-only build A of
`../gpu-k1/` (56.862 s, a different window) C2 is 1.2662× (56.862/44.906). The wait is 91.60% of
C2's wall. C1 ran 0.458 s faster here than in the k1 window (48.108 s), which is the run-to-run spread
at this load.

`prof-C2.txt` puts 120.59 ms of the profiled step's GPU wait in the GEMMs, against 146.07 ms in
`../gpu-k1/prof-C.txt` (1.2113×, −17.45%), and 82.71 ms in the row kernels; the GEMMs are now 59.31% of
the 203.30 ms profile. Per GEMM shape (sum over the profiled step's launches; TFLOP/s = 2·m·n·k·gz·count
over the summed wait, WolframLanguageEvaluator):

| m×n×k, gz | launches | C1 id, ms | C2 id, ms | C1 TFLOP/s | C2 TFLOP/s | speed-up |
|---|---|---|---|---|---|---|
| 256×32×256, 512 (attention, n = 32) | 32 | 0/1, 25.578 | 0/1, 24.340 | 2.687 | 2.823 | 1.051 |
| 16384×256×1024, 1 | 16 | 3/5, 18.040 | 35/37, 16.743 | 7.619 | 8.209 | 1.077 |
| 256×256×32, 512 (attention, k = 32) | 16 | 3, 14.670 | 35, 14.281 | 2.342 | 2.406 | 1.027 |
| 16384×1024×256, 1 | 16 | 1/3, 18.369 | 33/35, 13.960 | 7.482 | 9.845 | 1.316 |
| 16384×256×256, 1 | 40 | 3/5/7, 16.007 | 35/37/39, 11.981 | 5.366 | 7.169 | 1.336 |
| 1024×256×4096, 4 (split-K) | 8 | 0, 11.709 | 32, 7.690 | 5.869 | 8.937 | 1.523 |
| 256×1024×4096, 4 (split-K) | 8 | 0, 11.603 | 32, 6.787 | 5.923 | 10.126 | 1.710 |
| 16384×256×256, 3 | 8 | 1, 6.958 | 33, 6.044 | 7.407 | 8.527 | 1.151 |
| 256×256×2048, 24 (split-K) | 8 | 0, 8.100 | 32, 5.583 | 6.363 | 9.232 | 1.451 |
| 4096×256×16384, 1 | 1 | 4, 4.420 | 36, 3.990 | 7.774 | 8.611 | 1.108 |
| 16384×256×4096, 1 | 1 | 1, 3.684 | 33, 3.979 | 9.327 | 8.636 | 0.926 |
| 16384×4096×256, 1 (logits) | 1 | 3, 3.983 | 35, 3.208 | 8.626 | 10.710 | 1.242 |
| 256×256×1024, 16 (split-K) | 8 | 0, 2.944 | 32, 1.998 | 5.835 | 8.597 | 1.474 |

One shape got slower: 16384×256×4096 (k = 4096, one launch) takes 0.295 ms more (3.979/3.684 =
1.0800). Its 64×64 grid is 4×256 = 1024 blocks against 8×512 = 4096 for the 32 tile, each block
four times longer [INFERENCE: tail of the last wave; not measured]. The two attention batched
products (gz 512, k or n = 32) barely moved and run at 2.4-2.8 TFLOP/s.

## Next targets

Row kernels in `prof-C2.txt` (ns summed over the profiled step; ids per `gr.om` `grall`):

| id | kernel | launches | ms |
|---|---|---|---|
| 11 | `grrmsb` RMS norm backward | 17 | 16.338 |
| 16 | `grsoftb` softmax backward | 8 | 14.200 |
| 21 | `grce` cross-entropy | 1 | 13.206 |
| 15 | `grsoftf` softmax forward | 8 | 9.754 |
| 18 | `grew` element-wise | 8 | 7.880 |
| 10 | `grrmsf` RMS norm forward | 17 | 6.022 |

With the attention batched GEMMs (38.62 ms for ids 0, 1 and 35 at gz 512) these are the next work,
then fusion. BF16 tensor cores need a gate decision first: the f64-CPU µnat gates would not hold.
