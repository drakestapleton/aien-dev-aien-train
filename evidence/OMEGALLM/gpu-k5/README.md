# GB10 kernels k5: causal attention GEMMs (aien-train#52)

After `../gpu-k4/`, the attention block was the largest part of the profiled step. The six attention
GEMMs ran dense, although half of each product meets only the causal zeros of P (or of DS, whose
zeros come from P). This change skips that work at run time through the GEMM argument words. No new
kernel ids are added and every non-attention GEMM is unchanged in behaviour.

- `gg.om` `ggbh m n k bt cz` sets a causal mode with `gk.om` `gkopz` before `ggmm`. `gkmm` reads and
  clears it (`gkczarg`), so a GEMM issued without `gkopz` is dense. `gkczok` refuses (nverr −22) a
  mode whose shape does not fit: modes 1 and 2 need k = m, mode 3 needs m = n.
- Arg words: 22 = K-tile count base, 26 = ka, 27 = kc, 28 = X. The GEMM prologue (32 and 64 tiles)
  exits the block when R2 (column tile) > R3 (row tile) + X. It then reads kn = R3·ka + word 22 K
  tiles, starting R3·kc tiles in. Dense: ka 0, kc 0, X 2^30.
  - Mode 3 (S = Q·Kᵀ in `ggatt`, DP = DO·Uᵀ in `ggbatt`): X = 0, so the blocks above the diagonal
    exit. 10 of 16 blocks run at T 256 with the 64 tile.
  - Mode 1 (o = P·U, DQ = DS·K): ka = pt (K tiles per row tile), word 22 = pt. Row tile r reads
    K tiles 0 … (r+1)·pt − 1.
  - Mode 2 (DU = Pᵀ·DO, DK = DSᵀ·Q): ka = −pt, kc = pt. Row tile r starts at K tile r·pt.
  - In modes 1 and 2, 36 of 64 (row tile, K tile) pairs run at T 256 with the 32 tile.
- `gr.om` `grsoftb` (id 16) zeroes dp for columns > t (`ISETP.GT.U32`, `FSEL RZ`). The DP tiles
  above the diagonal are no longer written and hold stale data, and p·(stale Inf or NaN) would be
  NaN even with p = 0.
- The ISETP, register-form IMAD.WIDE.U32 and predicated-EXIT encoders moved from `gr.om` to `gk.om`
  (`gkisetp`, `gkimadwr`, `gkexitp`), because `gk.om` comes first in the concatenation. The slots
  that use only these encoders are byte-identical to k4.
- New build-time mutant q (`build.sh --mutant q`, `gk.om` `OMUTQ 0`): mode 1 sets word 22 = pt − 1,
  so each row tile stops one K tile short. It is host-only, so its device code equals the product's.

Every skipped FFMA term is ±0, which predicts a result **bit-identical to k4**. P above the diagonal is
exactly +0 (softf FSELs −inf there). Mode 1 drops a tail of ±0 terms after the real ones. Mode 2 drops
a head of ±0 terms from a +0 accumulator, which under round-to-nearest stays +0 (+0 + −0 = +0). The
softb row sum sees +0 terms where it saw ±0 terms. The window confirmed the prediction: the
checkpoint after 200 steps is byte-equal to k4's.

Status: EXERCISED on one GB10, window `20261102T143009Z-08b44a` (`win-k5.txt`), opened
`--gb10 shared --quiet none`. `spark-window` printed the verdict "quiet machine", but the quiet lock
was not taken and the rung-6 P5 CPU `eval` held core 7. The load average was 2.55 at open and 3.75 at
close (`open.json`, `close.json`), so the timings are non-quiet. Not QUALIFIED.

## Setup

- Binaries (`build.txt`): product K5 5c38d237…, mutant q 18791a82…, omc 2c824805… (omega-mv
  e5b32567). After the window the tree was rebuilt and gave the same two sha256s. The base, K4
  72289c19…, is the parent commit's product (`../gpu-k4/`), run again in this window.
- Static checks were done before the window (`prereg.txt`) and repeated on this commit's tree
  (`disasm.txt`, `tests/omegallm/gpu-disasm.sh`, nvdisasm `-b SM121`).
  - The 64-slot code dump (code 5840a49b…) differs from the parent's (7f45d37b…) in slots 0-7, 16
    and 32-39 only.
  - GEMM prologue: `LDC R12 c[0x3f0]`; `IADD3 R12 = R12 + R3`; `ISETP.GT.U32 P0 R2 R12`;
    `@P0 EXIT`. It then loads kn, ka and kc (`c[0x3d8]`, `c[0x3e8]`, `c[0x3ec]`), forms kn = R3·ka + kn
    and R13 = R3·kc, and advances both tile pointers by `IMAD.WIDE.U32` R13 × tile step. This happens
    after the step registers (R99/R100, or R139/R140 in the 64 tile) are loaded.
  - Slot 16 gains the per-column `ISETP.GT.U32 P1 col t` / `FSEL R48 RZ R48 P1`.
  - A mutant-q tree dumps to the same code sha256 5840a49b….
- The first build failed before any chip run. The softb mask loop had lost its `end` (omc error 10,
  duplicate name, at the next `for u`). The window ran only the corrected build.
- `prereg.txt` was written before the window opened, and `prereg.sha256` holds its hash (2f079ce8…)
  and that of `run.sh` (b4736dc6…). In the committed `run.sh`, `win-k5.txt` and the window JSON, the
  home prefix is replaced by `~/`, so the committed `run.sh` hashes to 0eff8119…. Nothing else differs.
- Checkpoints are as in `../gpu-k4/`.

## Results

| prediction (`prereg.txt`) | receipt | result |
|---|---|---|
| K5 `gcmp2` small, 3 steps, rc 0 | `gc2-small-s3-K5.txt` GCMP2 PASS rc=0 | PASS |
| K5 `gcmp2` max, 7 steps, rc 0 | `gc2-max-s7-K5.txt` GCMP2 PASS rc=0 | PASS |
| K5 `gacmp` max rc 0 | `ga-max-K5.txt` GACMP PASS rc=0 | PASS |
| mutant q `gcmp2` small FAIL | `gc2-small-s3-KQ.txt` GCMP2 FAIL rc=47 | PASS (caught) |
| mutant q `gcmp2` max FAIL | `gc2-max-s7-KQ.txt` GCMP2 FAIL rc=47 | PASS (caught) |
| K5 `geval` of rung 5 `ck9000`: E 9000 2243 1445466 539226 exactly (gate \|Δ\| < 10) | `ge-max-9000-K5.txt` E 9000 2243 1445466 539226 | PASS (Δ 0) |
| K5 `geval` of rung 6 `ck30000`: E 30000 2243 1338156 499194 exactly | `ge-max-30000-K5.txt` E 30000 2243 1338156 499194 | PASS (Δ 0) |
| `t200` K4 then K5: both rc 0, T 9200 1508182, `ck_after` equal to each other and to ec4a8c21… | `t200-K4.txt` and `t200-K5.txt`: T 9200 1508182, `ck_after` ec4a8c21… both | PASS (byte-equal) |
| `gprof` K4 and K5: K5 lower in the attention GEMMs | below | PASS |

The byte-equal checkpoint covers 200 full training steps, forward and backward, at the max shape. It
is a stronger check than the `gcmp2` tolerance: the skipped work is not merely numerically harmless,
it changes no bit of the result.

## Speed (non-quiet)

`t200`: 200 `gtrainf` steps 9000→9200 from rung 6's `ck9000`, both binaries in this window, K4 first.

| binary | wall | GPU wait (GT field 9) | launches | wait per launch |
|---|---|---|---|---|
| K4, k4 | 40.232 s | 36.398 s | 63800 | 0.5705 ms |
| K5, this tree | 37.997 s | 34.113 s | 63800 | 0.5347 ms |

K5 is 1.0588× faster than K4 in wall time (−5.56%) and 1.0670× in GPU wait (WolframLanguageEvaluator:
40232470931/37997016015 → 1.05883, 36397765703/34113356807 → 1.06697, (1 − 37997016015/40232470931)·100
→ 5.556). That is 11.18 ms per step (WolframLanguageEvaluator: (40232470931 − 37997016015)/200/10^6 →
11.177). The wait is 89.78% of K5's wall. K4 ran 0.057 s faster here than in the k4 window (40.289 s).

`prof-K4.txt` and `prof-K5.txt` (one profiled step each, 383 launches, ns summed per kernel and grid):

| id | GEMM | grid | launches | k4 ms | k5 ms | speed-up |
|---|---|---|---|---|---|---|
| 35 | S, DP (mode 3, 64 tile) | 4×4×512 | 16 | 14.047 | 10.424 | 1.348 |
| 1 | o, DQ (mode 1, 32 tile) | 1×8×512 | 16 | 12.949 | 8.498 | 1.524 |
| 0 | DU, DK (mode 2, 32 tile) | 1×8×512 | 16 | 11.972 | 8.430 | 1.420 |

(WolframLanguageEvaluator: 14047121/10424452 → 1.34752, 12949007/8497566 → 1.52385,
11972090/8429740 → 1.42022.) Together these three save 11.616 ms per profiled step, against the
15.838 ms modelled in `prereg.txt` (WolframLanguageEvaluator: 13.876·6/16 + (12.580 + 11.728)·7/16 →
15.83825). The model assumed time proportional to the tiles run. The measured speed-ups are below the
tile ratios (1.6× for mode 3, 16/9 ≈ 1.78× for modes 1 and 2) [INFERENCE: the diagonal blocks still
do full work, and in modes 1 and 2 the row tiles become unequal, so the last row tile sets the
kernel's length]. The profile total fell from 180.94 ms to 168.54 ms (1.0736×, WolframLanguageEvaluator:
180941593/168543961 → 1.07356). Other kernels moved by up to ±0.6 ms each, which is within the
run-to-run spread of one profile [INFERENCE: one profile per binary, no repeat].

## Next targets

In `prof-K5.txt` the attention block (ids 35, 1 and 0 at batch 512, plus the softmax kernels: id 16
`grsoftb` 14.097 ms and id 15 `grsoftf` 9.569 ms) totals 51.02 ms, 30.27% of the 168.54 ms profile
(WolframLanguageEvaluator: (8497566 + 10424452 + 8429740 + 14096979 + 9568788)/168543961 → 0.30270).
The softmax kernels are now the largest part of it. They are next, then fusion.
