# GB10 kernels k7: FFMA operand reuse and a register-bank remap in the GEMMs (aien-train#52)

After `../gpu-k6/` the GEMMs (ids 0-7 32×32, ids 32-39 64×64) held about two thirds of the profiled
step. Their FFMAs had two defects that issue order cannot hide:

- No FFMA carried a reuse bit. Each row run of the k loop (4 FFMAs in 32×32, 8 in 64×64) reads the
  same a register, which is fetched from the register file again for every FFMA.
- In every k-loop FFMA the b register (R36+j, R88+j, R104+j) and the accumulator (R16+4i+j, R16+8i+j)
  have the same low two index bits. In the published Volta-to-Ampere register-file models that puts Rb
  and Rc in the same bank. The sm_121 bank model is unpublished.

Two switches in `gk.om` address them:

- `OKREU 1`: `gkffma` takes a reuse mask `ru` (control word 3 bits 26-28: Ra 1, Rb 2, Rc 4). `gkfrag`
  and `gkstep64` set Ra reuse on every FFMA of a row run except the last (`gkru`), so the last FFMA
  releases the operand.
- Control bit 109 (word 3 bit 13) is set with every nonzero reuse mask. nvdisasm (CUDA 13.0 V13.0.88,
  `-b SM121`) prints `.reuse` only when bit 109 is also set, and ptxas 13.0 `-arch sm_121` sets it on
  all 49 `.reuse` instructions of a register-blocked probe kernel (it also sets it on 155 of the 175
  other instructions). `gkcw` never sets it, so it is clear on every k1-k6 instruction. What bit 109
  does on its own is not known; k7 sets it only alongside reuse, so every attribution below is to the
  pair.
- `OKBNK 1`: C column j lives in accumulator column j xor 1 (`gkcol`), in the k loop and in both
  epilogues (`gkacc32`, `gkacc64`). The b register and the accumulator then differ in their low two
  bits in every k-loop FFMA.

Neither switch changes what is computed: the remap renames registers, and reuse and bit 109 are issue
hints. Each C element's FFMA chain keeps its operands, order and rounding, so the prediction was
**bit-identical to K6**. The window confirmed it: the checkpoint after 200 steps is byte-equal to K6's.

`build.sh` gains `--variant r0` (`OKREU 0`, remap only) and `--variant b0` (`OKBNK 0`, reuse only),
which run in the same window to attribute the change. Mutant t (`OMUTT 0`) is unchanged. It drops the
k = 7 product of the thread's C element at row 0, column 0, which now lives in R17.

Status: EXERCISED on one GB10, window `20261102T150912Z-072e61` (`win-k7.txt`), opened
`--gb10 shared --quiet none`. `spark-window` printed the verdict "quiet machine", but the quiet lock
was not taken, and the load average was 2.89 at open and 2.07 at close (`open.json`, `close.json`).
The timings are therefore non-quiet. Not QUALIFIED.

## Setup

- Binaries (`build.txt`): product K7 53ff5f71…, variant r0 34c04e99…, variant b0 c37449e6…, mutant t
  eb53ebe2…, omc 2c824805… (omega-mv e5b32567). After the window the tree was rebuilt and gave the
  same four sha256s. The base, K6 e49491c5…, is the parent commit's product (`../gpu-k6/`), run again
  in this window.
- Static checks were done before the window (`prereg.txt`) and repeated on this commit's tree
  (`disasm.txt`):
  - At both shapes the code differs from K6 in slots 0-7 and 32-39 only.
  - With both switches at 0 the max-shape code is byte-equal to K6's (9646adef…).
  - Of the 6464 FFMAs, 5120 print `.reuse`. Each is followed by an FFMA that reads the same Ra.
  - Apart from the 64 alpha/beta epilogue FFMAs, no FFMA has b and accumulator equal mod 4.
- `prereg.txt` was written at 15:09:06Z, 6 s before the window opened (15:09:12Z). `prereg.sha256`
  (written before the open) hashes it (53adab2b…) and the `run.sh` the window ran (7fb749db…). In the
  committed `run.sh`, `win-k7.txt` and the window JSON the home prefix is replaced by `~/`, so the
  committed `run.sh` hashes to 9bd2f3ea…. Nothing else differs.
- Checkpoints are as in `../gpu-k4/`. `gprof` runs on rung 6's `ck30000` (8ccaa099…), and `t200` starts
  from rung 6's `ck9000` (e91349fb…).

## Results

GC2 field 14 (`gpu_ns`) and GA field 7 (`adam_ns`) are wall times and exempt from equality, as
`prereg.txt` states. Every other field equals the k6 receipts.

| prediction (`prereg.txt`) | receipt | result |
|---|---|---|
| K7 `gcmp2` small, 3 steps, rc 0, K6 line | `gc2-small-s3-K7.txt` GCMP2 PASS rc=0 | PASS |
| K7 `gcmp2` max, 7 steps, rc 0, K6 line | `gc2-max-s7-K7.txt` GCMP2 PASS rc=0 | PASS |
| K7 `gacmp` max rc 0, K6 line | `ga-max-K7.txt` GACMP PASS rc=0 | PASS |
| mutant t `gcmp2` max FAIL rc 47 | `gc2-max-s7-KT.txt` GCMP2 FAIL rc=47, fails 14 | PASS (caught) |
| mutant t `gcmp2` small, report only | `gc2-small-s3-KT.txt` GCMP2 FAIL rc=47, fails 14 | caught |
| K7 `geval` of rung 5 `ck9000`: E 9000 2243 1445466 539226 | `ge-max-9000-K7.txt` same line | PASS (Δ 0) |
| K7 `geval` of rung 6 `ck30000`: E 30000 2243 1338156 499194 | `ge-max-30000-K7.txt` same line | PASS (Δ 0) |
| `t200` K6 then K7: rc 0, T 9200 1508182, `ck_after` ec4a8c21… for both | `t200-K6.txt`, `t200-K7.txt` | PASS (byte-equal) |
| `gprof`: K7 GEMM wait below both K6 runs (direction only, not a gate) | below | PASS |

## Speed (non-quiet)

`t200`: 200 `gtrainf` steps 9000→9200, K6 first.

| binary | wall | GPU wait (GT field 9) | launches | wait per launch |
|---|---|---|---|---|
| K6, parent | 35.438 s | 31.695 s | 63800 | 0.4968 ms |
| K7, this tree | 34.260 s | 30.289 s | 63800 | 0.4748 ms |

K7 is 1.0344× faster than K6 in wall time (−3.32%) and 1.0464× in GPU wait. That is 5.89 ms per step,
and the wait is 88.41% of K7's wall (WolframLanguageEvaluator: 35437660887/34260371063 → 1.03436,
31694700976/30289445669 → 1.04639, (1 − 34260371063/35437660887)·100 → 3.3221,
(35437660887 − 34260371063)/200/10^6 → 5.8864, 30289445669/34260371063 → 0.88410,
31694700976/63800/10^6 → 0.49678, 30289445669/63800/10^6 → 0.47476). K6 ran 0.651 s faster here than
in the k6 window (36.089 s).

`gprof 3` (one profiled step each, 383 launches; ns summed over each id's launches), in run order
K6a, K7, R0, B0, K6b:

| binary | ids 0-1 (32×32) | ids 32-39 (64×64) | GEMM total | all ids |
|---|---|---|---|---|
| K6a | 16659669 | 94527070 | 111186739 | 162258372 |
| K7 (remap + reuse) | 16641318 | 85648429 | 102289747 | 151854008 |
| R0 (remap only) | 16675556 | 92229574 | 108905130 | 158875514 |
| B0 (reuse only) | 16595369 | 83559436 | 100154805 | 149959265 |
| K6b | 16340930 | 92019795 | 108360725 | 157781861 |

Against the mean of K6a and K6b (WolframLanguageEvaluator: Mean[{94527070, 92019795}] → 9.32734×10^7):

- 64×64 GEMM wait: K7 0.9183, B0 0.8959, R0 0.9888. K6a and K6b differ by 2.69% of their mean
  (85648429/k6 → 0.91825, 83559436/k6 → 0.89585, 92229574/k6 → 0.98881, (94527070 − 92019795)/k6 →
  0.026881).
- GEMM total: K7 0.9318, B0 0.9124 (102289747/Mean[{111186739, 108360725}] → 0.93182, 100154805/… →
  0.91237). Profile total: K6 mean/K7 → 1.05378.
- 32×32 (ids 0-1): all five binaries lie within 16.34-16.68 ms. Neither change moves them.

Attribution: the gain is reuse plus bit 109, in the 64×64 kernels only. R0 (remap without reuse) is
inside the K6 spread, and B0 (reuse without remap) is 2.09 ms below K7 in the 64×64 ids, which is
inside the same spread [INFERENCE: one profile per binary]. So the remap has no measured benefit on
sm_121 for these kernels. Against K6a, K7 is lower in ids 32 (−3.16 ms), 35 (−2.17), 33 (−1.20), 37
(−0.84) and 36 (−0.61). Id 39 (4.88 ms) lies between K6a (5.78) and K6b (4.78).

## Next

The remap is dead weight on this measurement. The next commit removes `OKBNK`, `gkcol` and variant b0,
which makes the product the reuse-only code, and runs it through its own window with repeated,
interleaved profiles (K6, K7, reuse-only). Then comes the 128×128 retile, then fusion.
