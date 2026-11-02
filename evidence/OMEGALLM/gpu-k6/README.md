# GB10 kernels k6: causal predicated loads and stores in the softmax kernels (aien-train#52)

After `../gpu-k5/` the two softmax row kernels, `gr.om` `grsoftf` (id 15) and `grsoftb` (id 16), were
the largest attention kernels left: 9.569 and 14.097 ms per profiled step at about 224 and 228 GB/s of
required traffic, so bandwidth-bound. Only less traffic could make them faster. Row t of a T = 256
attention row needs columns 0 … t only, yet both kernels read and wrote all 256.

- Loads: lane l holds column l + 32u. Row t (R21) loads chunk u only if t ≥ 32u. The predicates P0 … P6
  = (t ≥ 32u) for u = 1 … 7 are set by `ISETP.GE` before the first load, because an ISETP placed
  between the loads would wait on their scoreboard. Chunk 0, and chunks from u = 8 on (T > 256), stay
  unpredicated: loaded, then masked as before.
- Stores: chunk u is stored only if t ≥ 64·⌊u/2⌋ (P1, P3, P5 on the chunk pairs 2-3, 4-5, 6-7). The
  predicates are recomputed before the stores because the mask loop reuses P1. Every consumer reads a P
  or DS row only up to the end of its diagonal tile: the 64 tile for S/DP (id 35) and the 32 tile in
  the k5 causal modes. So a chunk that is not stored is never read.
- `grsoftb` now also `FSEL`s p to RZ for columns > t, since unloaded p registers hold stale values. In K5
  p there was exactly +0 from softf, so the value is unchanged.
- New encoders `gk.om` `gkldgp`/`gkstgp` put the guard predicate in word 0 bits 12-15 (p 7 = PT, +8
  negates). `gkldg`/`gkstg` are now these with p 7, so their words are unchanged.
- `gk.om` `gkisge` fix: it wrote the destination predicate to word 0 bit 16. ISETP's field is word 2
  bit 17 (as in `gkisetp`), so every `gkisge` wrote P0. The first max-shape dump of the new softf showed
  all seven ISETPs writing P0. Every earlier caller passes p 0, so no other slot changed
  (`disasm.txt`).
- New build-time mutant w (`build.sh --mutant w`, `gr.om` `OMUTW 0`): load predicates t ≥ 32u + 32.
  From chunk 1 on, each row's diagonal chunk is then not loaded, and its stale register enters the
  softmax.
- `tests/omegallm/gpu-disasm.sh` takes `SHAPE="V T D H F B"` (the `grset` arguments; default the parity shape
  `256 32 64 2 128 2`), and it refuses with `SHAPE_NOT_SET` (rc 2) when the `grset` line in
  `gpu-dump.om` does not match. The predicated code exists only at T > 32, so the max shape needs it.
  Empty slots (8, 12, …) now print `SLOT n empty` instead of stopping the script under `set -e`.

Unloaded chunks lie wholly above the diagonal and are replaced by FSEL (−inf in softf, +0 in softb)
before any arithmetic, exactly as K5's loaded values were. That predicts a result **bit-identical to
K5**. The window confirmed it: the checkpoint after 200 steps is byte-equal to K5's.

Status: EXERCISED on one GB10, window `20261102T144557Z-bcd2c2` (`win-k6.txt`), opened
`--gb10 shared --quiet none`. `spark-window` printed the verdict "quiet machine", but the quiet lock
was not taken and the rung-6 P5 CPU `eval` held core 7. The load average was 2.32 at open and 4.66 at
close (`open.json`, `close.json`), so the timings are non-quiet. Not QUALIFIED.

## Setup

- Binaries (`build.txt`): product K6 e49491c5…, mutant w 67b1653d…, omc 2c824805… (omega-mv
  e5b32567). After the window the tree was rebuilt and gave the same two sha256s. The base, K5
  5c38d237…, is the parent commit's product (`../gpu-k5/`), run again in this window.
- Static checks were done before the window (`prereg.txt`) and repeated on this commit's tree with the
  committed `gpu-disasm.sh` (`disasm.txt`, nvdisasm `-b SM121`).
  - Parity shape: the code dump (ac8e5ff1…) differs from K5's (5840a49b…, `../gpu-k5/disasm.txt`) in
    slot 16 only, the p FSEL. T = 32 is one chunk, so no predicates are emitted, and the mutant-w code
    equals K6's.
  - Max shape: the dump (9646adef…) differs from K5's (4ace0156…) in slots 15 and 16 only. Slot 15:
    seven `ISETP.GE` R21 against 0x20 … 0xe0, `LDG R32`, `@P0 … @P6 LDG R33 … R39`; stores `STG R32`,
    `R33`, `@P1` R34 R35, `@P3` R36 R37, `@P5` R38 R39. Slot 16 does the same for p (R32 …) and dp
    (R48 …).
  - Mutant w at the max shape differs from K6 in slots 15 and 16 only, and only in the seven ISETP
    immediates (0x40 … 0x100).
- `prereg.txt` was written before the window opened, and `prereg.sha256` holds its hash (6e44833e…).
  The hash of `run.sh` (f83b696f…) was appended after the window. The file's mtime, 14:45:50Z, is
  7 s before the window opened, and the window ran it (`win-k6.txt`). In the committed `run.sh`,
  `win-k6.txt` and the window JSON the home prefix is replaced by `~/`, so the committed `run.sh`
  hashes to ecccb949…. Nothing else differs.
- Checkpoints are as in `../gpu-k4/`.

## Results

| prediction (`prereg.txt`) | receipt | result |
|---|---|---|
| K6 `gcmp2` small, 3 steps, rc 0, K5 line | `gc2-small-s3-K6.txt` GCMP2 PASS rc=0 | PASS |
| K6 `gcmp2` max, 7 steps, rc 0, K5 line | `gc2-max-s7-K6.txt` GCMP2 PASS rc=0 | PASS |
| K6 `gacmp` max rc 0, K5 line | `ga-max-K6.txt` GACMP PASS rc=0 | PASS |
| mutant w `gcmp2` max FAIL rc 47 | `gc2-max-s7-KW.txt` GCMP2 FAIL rc=47, 15 non-finite, fails 15 | PASS (caught) |
| mutant w `gcmp2` small rc 0 with the K6 line (shape control: at T = 32 its code is K6's) | `gc2-small-s3-KW.txt` GCMP2 PASS rc=0 | as predicted (control, not a catch) |
| K6 `geval` of rung 5 `ck9000`: E 9000 2243 1445466 539226 exactly (gate \|Δ\| < 10) | `ge-max-9000-K6.txt` E 9000 2243 1445466 539226 | PASS (Δ 0) |
| K6 `geval` of rung 6 `ck30000`: E 30000 2243 1338156 499194 exactly | `ge-max-30000-K6.txt` E 30000 2243 1338156 499194 | PASS (Δ 0) |
| `t200` K5 then K6: both rc 0, T 9200 1508182, `ck_after` equal to each other and to ec4a8c21… | `t200-K5.txt` and `t200-K6.txt`: T 9200 1508182, `ck_after` ec4a8c21… both | PASS (byte-equal) |
| `gprof` K5 and K6: K6 lower in ids 15 and 16 | below | PASS |

The prereg asked for GC2 and GA lines "equal to the k5 window's K5 lines" without exempting the timing
fields. Every field is equal except GC2 field 14 (`gpu_ns`) and GA field 7 (`adam_ns`), which are wall
times (`../gpu-max/README.md`, `../gpu/README.md`). The rung-5 repeat run already showed `gpu_ns`
varying between windows. That is a wording error in the prereg, not a numeric difference.

## Speed (non-quiet)

`t200`: 200 `gtrainf` steps 9000→9200 from rung 6's `ck9000`, both binaries in this window, K5 first.

| binary | wall | GPU wait (GT field 9) | launches | wait per launch |
|---|---|---|---|---|
| K5, k5 | 37.995 s | 34.115 s | 63800 | 0.5347 ms |
| K6, this tree | 36.089 s | 32.221 s | 63800 | 0.5050 ms |

K6 is 1.0528× faster than K5 in wall time (−5.02%) and 1.0588× in GPU wait (WolframLanguageEvaluator:
37994576841/36089035714 → 1.05280, 34114814982/32220574256 → 1.05879, (1 − 36089035714/37994576841)·100
→ 5.0153). That is 9.53 ms per step (WolframLanguageEvaluator: (37994576841 − 36089035714)/200/10^6 →
9.5277), and the wait is 89.28% of K6's wall (32220574256/36089035714 → 0.89281). K5 ran 0.002 s faster
here than in the k5 window (37.997 s).

`prof-K5.txt` and `prof-K6.txt` (one profiled step each, 383 launches, ns summed per kernel and grid):

| id | kernel | grid | launches | k5 ms | k6 ms | speed-up | k5 GB/s | k6 GB/s |
|---|---|---|---|---|---|---|---|---|
| 15 | `grsoftf` | 128×512×1 | 8 | 9.809 | 5.985 | 1.639 | 218.9 | 213.0 |
| 16 | `grsoftb` | 128×512×1 | 8 | 14.292 | 8.525 | 1.676 | 225.4 | 220.4 |

(WolframLanguageEvaluator: 9808887/5985038 → 1.63890, 14292215/8525359 → 1.67644. GB/s is required
traffic per launch over the launch's mean time, with b = 512·256·256·4. K5: 2b/(9808887/8) → 218.93
and 3b/(14292215/8) → 225.38. K6 scales the traffic by the modelled fractions 19/32 and 7/12:
(19/32)·2b/(5985038/8) → 213.04 and (7/12)·3b/(8525359/8) → 220.41.)

The two kernels save 9.591 ms per profiled step against the 9.761 ms modelled in `prereg.txt`, which is
98.25% of the model (WolframLanguageEvaluator: (14292215 − 8525359 + 9808887 − 5985038)/10^6 → 9.59071,
9590705/9761061.375 → 0.98255). The model assumed time proportional to the traffic, and K6 stays at
about the same bandwidth as K5, so the kernels remain bandwidth-bound. The profile total fell from
175.10 ms to 161.08 ms (1.0871×, WolframLanguageEvaluator: 175103615/161079860 → 1.08706). K5's profile
total in this window is 175.10 ms, against 168.54 ms in the k5 window. Unchanged kernels moved by up to
2.28 ms each (id 37 −2.28, id 33 −1.00, id 32 +0.75), which is the run-to-run spread of one profile
[INFERENCE: one profile per binary, no repeat].

## Next targets

In `prof-K6.txt` the GEMMs (ids 35, 32, 33, 37, 1 and 0) take 102.76 ms, 63.79% of the 161.08 ms
profile, and the softmax kernels take 14.51 ms, 9.01% (WolframLanguageEvaluator: (34202515 + 23633417 +
17320461 + 10819388 + 8470348 + 8311307)/10^6 → 102.757, ÷161079860 → 0.63793; (8525359 +
5985038)/161079860 → 0.09008). Next is fusion: softmax into the attention GEMMs, removing the P and DS
round trip through the arena. Then the GEMM tile. BF16 tensor cores wait on the gate decision
(f32 chip against the f64 CPU µnat gates).
