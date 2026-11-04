# Omega LLM BF16 tensor-core contract

This contract adds a BF16 tensor-core GEMM path to the GB10 build (`TARGET=gb10`). It extends
`CONTRACT-V2.md`, which remains normative for everything this file does not change. The CPU
product and the Python referee do not change. The BF16 path is opt-in, and every existing command
keeps its exact behaviour.

Compatibility rule: every kernel slot except the new BF16 slots 27..36 keeps its exact code and
register bytes. The AArch64 build is byte-identical to the base 273ca2a build. Host evidence for both
statements is in `evidence/OMEGALLM/gpu-bf/` (`f32-identity.txt`, `build.txt`).

## 1. Numerics

| Quantity | Format |
|---|---|
| Master weights, Adam moments, checkpoint | f32 / f64 as v2 (unchanged) |
| GEMM operands on the BF16 path | f32 in memory, rounded to bf16 by round to nearest even (F2FP.BF16.F32.PACK_AB) while staged into shared memory |
| GEMM accumulation | f32 (HMMA.16816.F32.BF16) |
| GEMM epilogue (alpha, beta, fused epilogues 1 and 2) | f32, identical to the f32 kernels' gkepi64 |
| GEMMs with n = E (32x32 tiles) | f32 kernels, unchanged |
| geval | f32 kernels only, so the held-out loss metric does not change |

The bf16 unit roundoff is u = 2^-8, compared with 2^-24 for f32. All weight updates stay in f32,
and only GEMM inputs lose precision.

## 2. Kernels

There are ten kernels, slots 27..36 (`gk.om` gkgemmb). Each 128-thread block computes one 64x64
tile of C. K advances in tiles of 32, with two 8192-byte shared-memory buffers. Each warp issues
eight HMMA.16816 per k16 step.

| Slot | Operand modes / epilogue |
|---|---|
| 27 + ma + 2 mb + 4 beta | the eight plain kernels (ma, mb in {0, 1}: 1 = K-contiguous) |
| 35 | fused epilogue 1 (ma 1, mb 0) |
| 36 | fused epilogue 2 (ma 1, mb 1) |

Preconditions are checked on the host. Operand pointers and batch strides must be 16-byte
aligned. Loads are 16-byte: mode 1 needs a stride that is a multiple of 16, and mode 0 needs
outer stride 4 with a depth stride that is a multiple of 16. k must be a multiple of 32. There is
no fallback: a GEMM the kernels cannot take fails with nverr -22.

`gkbf 1` selects the path. It is set only by `gtrainb`, `gprofb` and the gb.om gates. With
`gkbf 0` (every pre-existing command) the dispatch is unchanged.

Encoding provenance: the instruction words were verified with `nvdisasm -b SM121` against ptxas
13.0 sm_121 output for `mma.sync.aligned.m16n8k16.row.col.f32.bf16.bf16.f32`,
`cvt.rn.bf16x2.f32` and `ld.global.v4.f32`.

| Instruction | Words |
|---|---|
| HMMA.16816.F32.BF16 | `0x000000060c08723c 0x010fe20000041808` |
| F2FP.BF16.F32.PACK_AB | `0x000000000309723e 0x000fe200000010ff` |

## 3. Commands

| Command | Arguments | Meaning | Failure exit |
|---|---|---|---|
| `gtrainb` | CK TRAIN UNTIL EVERY | `gtrainf` with gkbf 1 | as gtrainf |
| `gprofb` | CK TRAIN N | `gprof` with gkbf 1 | as gprof |
| `gbcmp` | CK DATA S | sampled check of every BF16 GEMM of one gradient pass | 48 |
| `gbcmp2` | CK DATA S | `gcmp2` step parity with the BF16 bound | 49 |
| `gbfrag` | CK | exact check of all ten kernels on fixed data | 50 |

## 4. Gates

### 4.1 gbfrag (exact)

gbfrag runs thirteen cases: eight plain kernels, epilogues 1 and 2, and cz 1, 2 and 3 (cz 1 and 2
need k = m, so those cases use k = 128). Each case runs twice, once with the operand roles swapped.
The data uses nz 6, h2 3 and padded strides, and every operand word the kernel must not read is NaN.
These cases reach at most four K tiles (k = 128).

- One operand holds integers in [-5, 5].
- The other holds (n - 2) + j·2^-9, with n < 5 and j < 64.

Every product is therefore a multiple of 2^-9 (2^-10 with alpha 1/2), and every partial sum stays
below 2^11, so the f32 accumulation is exact. The reference applies bf16 RNE to the operands, and
the chip result must equal it element by element. The fractional values need more than eight
significand bits, so a kernel that skips the rounding or rounds toward zero differs from the
reference.

Every C row has eight padding columns after column n - 1 (row stride n + 8). Before each case
gbfrag writes NaN into them, and into the same columns of Y (epilogue 1) or M (epilogue 2). After
the launch, every padding word that is no longer NaN counts as a mismatch, so a store outside
columns 0..n-1 of its row, such as a wrong column offset, fails the case. The BF16 dispatch takes
only m and n that are multiples of 64 (`gk.om` gktile), so these cases have no partial tiles. This
check was added after bf-g1 (2026-11-04, `evidence/OMEGALLM/gpu-bf/fix-pad/`); its chip run is
NOT_RUN until the integrator's pre-registered window.

Eight long-K cases (`GFL pass ma mb bad`) then cover the K loop: m = n = 64, k = 16384 (512 K
tiles), nz 1, beta 0, alpha 1, all four operand-mode pairs, both role passes. Operands are zero
except at kk ≡ 0 (mod 29), 565 terms, at least one in every 32-wide K tile, so a dropped, repeated
or misplaced tile changes C. Sums stay below 565·5·17/8 < 2^13 (`565*5*17/8 -> 48025/8 = 6003.125`,
Wolfram) in multiples of 2^-9, so the f32 result
is exact. The logits buffer is NaN-filled first (A at 0, B at 6 MiB, C at 12 MiB, at least 4 Mi
floats needed), and C's eight padding columns per row must still be NaN afterwards.

### 4.2 gbcmp (sampled, every BF16 GEMM of a step)

gbcmp runs one gradient pass (gggrad, no Adam) with every BF16 launch checked. Each launch checks
66 samples: 64 random positions (31-bit LCG) plus the two corners. Each sample is compared with an
f64 sum over the bf16-rounded operands, over the K range that the kernel reads. The bound is

    |chip - ref| <= (kn·2^-23 + 2^-22)·(|alpha|·Σ|a·b| + |old C|)

The first term is the f32 accumulation error over kn terms, with kn·u_f32 and u_f32 = 2^-24
doubled for slack; the second covers the epilogue's rounding. Wolfram:
`N[2^-23] -> 1.1920928955078125*^-7`, `N[2^-22] -> 2.384185791015625*^-7`.

Fused epilogues are checked exactly:

- Epilogue 1: Y = C when C > 0, otherwise +0.
- Epilogue 2: C is +0 where M is not > 0.

The gate also fails when no BF16 GEMM ran, or when coverage misses any combination the step uses:
epilogues 1 and 2, cz 3, and beta false and true. Which kernel ids ran is printed, not gated;
gbfrag covers every id.

The bound grows with kn. At B 64 (kn = 16384) it is about one K tile's share of Σ|a·b|
(`16384*2^-23+2^-22 -> 0.00195336` against `32/16384 -> 0.001953125`), so gbcmp at the training
shape cannot see a single wrong K tile; at B 8 (kn = 2048) the margin is 64x. Long K loops are
therefore checked exactly by gbfrag's long-K cases, not by gbcmp.

Because the bf16 rounding is in the reference, gbcmp checks the kernel against the stated
numerics. It does not measure how far bf16 is from f32. That is the job of 4.3 and 4.4.

### 4.3 gbcmp2 (step parity, heuristic bound)

gbcmp2 is gcmp2 (the chip gradient compared with the CPU f64 gradient on the same batch) run with
gkbf 1. Its tolerance is the first-order normwise heuristic tolb = n_c·(2u + u²), with u = 2^-8 and
n_c = 10L + 3. n_c counts the BF16 GEMMs on a step's longest dependency chain:

- per layer, forward: QKV, S, WO, W1, W2;
- per layer, backward: dF, dA of W1, dN, DP, dA of QKV;
- plus the logits GEMM, dlogits to dH, and the last weight gradient.

The fail bits are 1 (non-finite), 2 (rho >= tolb), 4 (rel1 >= tolb) and 8 (|dloss| >= tolb·loss).
At L 8: `u=2^-8; nc=10*8+3; nc*(2u+u^2) -> 42579/65536 = 0.6497039794921875` (Wolfram). The bound
is loose: it catches gross failures, such as non-finite values or a wrong layout. No mutant shows
what it catches, and it is not a precision claim.

### 4.4 Training (decisive)

BF16 is adopted for training only if a pre-registered `gtrainb` run from the rung-7 start
checkpoint reaches a chip geval held-out loss at step 2000 within +0.5% of the f32 rung-7 value.
The rung-7 value is E 2000 = 1756935 µnats, so the bound is 1765719. Wolfram:
`Floor[1756935*1.005] -> 1765719`. Step time is compared with rung 7's 0.2390 s/step. The
pre-registration fixes the exact procedure.

### 4.5 f32 regressions

On the BF16 binary, the f32 commands must reproduce the rung-7 gate receipts exactly:

- geval of r6 ck30000;
- the bit-identical t200 checkpoint;
- the gcmp2 small GC2 fields;
- gcmp2 and gacmp at the v2 maximum.

## 5. Mutants

Each mutant is a build flag (`--mutant X`). Each must fail at least one gate on the chip.

| Mutant | Constant | Defect | Expected to fail |
|---|---|---|---|
| u | gb.om OMUTU 0 | the reference skips the bf16 rounding | gbfrag (exit 50); gbcmp reported only |
| l | gk.om OMUTL 0 | A rows of lanes g and g ^ 1 swapped in the LDS layout | gbfrag, gbcmp |
| o | gk.om OMUTO 0 | one K tile fewer than the tile count | gbfrag (k ≥ 64 cases, long-K cases), gbcmp |
| v | gk.om OMUTV 0 | F2FP rounds toward zero instead of to nearest even | gbfrag, gbcmp |

For mutant u, gbcmp is reported only, because the RNE-vs-exact difference per sample can fall
within the f32 accumulation bound when Σ|a·b| is large. Mutant o cannot change a GEMM with a single
K tile (k = 32): the K loop is a do-while and runs once regardless.

## 6. Host evidence

- `evidence/OMEGALLM/gpu-bf/disasm-27-36.txt`: in each of slots 27..36, GPR max R142, need 145,
  declared 152, OK; SMEM target 17; 16 HMMA.16816.F32.BF16 per slot (160 in total); no illegal
  instruction.
- `evidence/OMEGALLM/gpu-bf/f32-identity.txt`: compared with base 273ca2a, gpu-code.bin differs
  only in slots 27..36, and gpu-gpr.bin differs only at register offsets 27..36 and SMEM offsets
  91..100 (the same slots).
- `evidence/OMEGALLM/gpu-bf/build.txt`: build hashes at e329675 for the product, the AArch64 CPU
  build (identical to the base) and the four mutants.
- `evidence/OMEGALLM/gpu-bf/build-2.txt`: build hashes after the gbfrag amendment (case 10 shape,
  long-K cases); gpu-dump code_sha256 is unchanged, so no kernel byte differs from e329675.
- `evidence/OMEGALLM/gpu-bf/fix-pad/`: the C padding check of 4.1 (2026-11-04). gpu-dump
  code_sha256 and gpu-gpr.bin are unchanged, so no kernel byte differs; new build hashes; chip
  commands and expected results for its pending run.

Chip gates 4.1-4.5 ran in two pre-registered windows, each EXERCISED on one GB10 (non-quiet),
before the padding check existed:

- bf-g1 (`evidence/OMEGALLM/gpu-bf/g1/REPORT.txt`): B1-B12 PASS. Mutants l, o and v fail both
  gbfrag and gbcmp. Mutant u fails gbfrag; gbcmp only reports it (u failed both; gbcmp is not
  required to catch u).
- bf-t1 (`evidence/OMEGALLM/gpu-bf/t1/REPORT.txt`): T1-T3 PASS. E 2000 is 1749889, within the 4.4
  bound of 1765719, and the 250→2000 leg took 367.6 s against 434.2 s for f32.

## 7. Adoption

Drake approved adopting BF16 for training on 2026-11-03, after bf-t1 met the 4.4 rule. From then
on, long training runs use `gtrainb`. The rest of the contract does not change:

- `gtrainf` and every f32 command keep their exact behaviour.
- `geval` stays on the f32 kernels, so held-out numbers stay comparable across f32 and BF16 runs.
- The CPU `eval` of a final checkpoint must still print the chip `geval` line, since both evaluate
  in f32.

What adoption gives up: a `gtrainb` step no longer matches the f64 CPU step bitwise. For BF16
runs, gbfrag and gbcmp check the kernels against the bf16 numerics instead, and gbcmp2 is the
heuristic step check of 4.3. A binary used for `gtrainb` runs must pass 4.1-4.5 on the chip first.

Adoption is not a quality claim. 4.4 compares step 2000 only. The first long `gtrainb` run carries
its own pre-registration and compares its final value with the f32 run on the same schedule.
