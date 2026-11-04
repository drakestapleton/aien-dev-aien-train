# GB10 kernels k8: pipelined 64×64 GEMM and per-kernel shared-memory TARGET (aien-train#52)

k8 software-pipelines the K loop of the 64×64 GEMM (`gk.om` `gkgemm64`, `gkld64`, `gksts64`). Each K tile
issues the global loads of the next tile into staging registers R142-R157 (predicated `@P1`, P1 = at
least two K tiles left), runs its 64 FFMA steps from the current shared buffer, then stores the staging
into the other buffer (two 4352-byte buffers, 8704 bytes) behind one barrier. k7b had two barriers per
tile and exposed the global-load latency on every tile. The kernels are 17008 bytes, so they move from
ids 32-39 (one 16 KiB slot each) to ids 40, 42, …, 54 (two slots each).

It took three windows. Every attempt is kept here, including the failed and the null one:

| dir | window | what ran | outcome |
|---|---|---|---|
| `a1/` | `20261102T153743Z-8dfb45` | k8 with `gkgpr` 160 | FAIL: every k8 run hung (rc 84) |
| `a2/` | `20261102T160003Z-6bddbf` | k8 with `gkgpr` 168 | bit-identical, slower: NULL under its prereg |
| `a3/` | `20261102T161059Z-25de8f` | new prereg: TARGET rule (`gksmw`), with and without k8 | k8 ADOPTED, product Q |

This commit is a3's product Q: k8, `gkgpr` 168 for ids 40-54, and the `gksmw` TARGET rule for every
`gk.om` kernel. It also adds the static GPR guard to `gpu-disasm.sh` / `gpu-dump.om`.

Status: EXERCISED on one GB10. All three windows were opened `--gb10 shared --quiet none`.
`spark-window` printed "quiet machine" at close, but the quiet lock was not taken, and the load average
was 1.27-2.15 at open and 2.09-2.79 at close (`a*/open.json`, `a*/close.json`). Timings are non-quiet.
Not QUALIFIED.

## Setup

- omc 2c824805… (omega-mv e5b32567). Binaries: `build.txt`. This commit's tree rebuilds a3's Q
  (0b701583…) and QT (3619ef31…) byte for byte. Only a `gk.om` note changed after the window, which
  moves the source sha256 and nothing else.
- Each `a*/prereg.txt` was written before its window opened (file times: a1 15:37:41Z, window
  15:37:43Z; a2 15:59:59Z, window 16:00:03Z; a3 16:10:55Z, `prereg.sha256` 16:10:59.29Z, window
  directory created 16:10:59.31Z). `a*/prereg.sha256` hashes the prereg (a1 65ad423d…, a2 828feaf0…,
  a3 fbeecfaa…). a1 and a2 also hash `run.sh` (57fa5a67…, c09972e3…). a3's `run.sh` hashed to 5b826f92…
  before the window, but that hash was printed rather than written into `prereg.sha256`. In the committed
  `run.sh`, `win-*.txt` and `open.json` the home prefix is replaced by `~/`, so the committed `run.sh`
  files hash differently (63d61758…, e9f62b57…, 7aac3c71…). Nothing else differs.
- Gates and checkpoints are as in `../gpu-k7b/`: GC2 and GA fields other than the wall timings (GC2
  field 14, GA field 7) must equal the k7b receipts, `geval` reruns rung 5 `ck9000` and rung 6
  `ck30000`, `t200` runs 200 `gtrainf` steps from rung 6 `ck9000`, and `gprof 3` profiles rung 6
  `ck30000`. Mutant t (`--mutant t`) must fail `gcmp2` with rc 47.

## a1: the hang, and the GPR guard

Every k8 run (P 115f984f…, PT 66df07bb…) printed `GX 99 -110 42 3 0 0 1` and exited rc 84: `gkmm`
false, launch wait timeout -110 at the 5 s `gkwait`, after 3 launches. B (k7b, 50dcd16e…) was healthy
in the same window: `t200-B.txt` gives T 9200 1508182 and `ck_after` ec4a8c21…, and every `prof-*-B.txt`
gives T 30003 1298769.

Cause: the 64×64 kernels use R158 (the buffer step) but declared `gkgpr` 160. On Volta and later, two
GPRs of the QMD count go to the program counter (Mesa NAK `src/nouveau/compiler/nak/sm70.rs:101`
`hw_reserved_gprs`, and `api.rs:275`, where the QMD count is `num_gprs + 2`). R158 and R159 therefore fall
outside the allocation. gr.om had the same failure with R69-R71 under 72 (`../geval/a1`). The rule is
that `gkgpr` must be at least the highest GPR + 3.

Fix: `gkgpr` 168 for ids 40-54. The kernel code is unchanged. At 64 threads, occupancy is 6 blocks per
SM under 160 and 168 alike (WolframLanguageEvaluator: `Floor[65536/(168*64)]` → 6;
`Floor[65536/(144*64)]` → 7 for k7b).

Guard: `gpu-dump.om` now also emits the `gkgpr` table (bytes 0-63 of its stderr record), and
`gpu-disasm.sh` prints `GPR <id> max R<n> need <n+3> declared <g> OK|LOW` for each slot. It ends with
`GPR_LOW` and exit 4 if any slot is LOW. Negative control `disasm-neg-gpr160.txt` (the a2 tree with
160): slots 40 and 54 LOW, exit 4. This commit's tree: all 31 slots OK at both shapes
(`disasm-parity.txt`, `disasm-max.txt`).

## a2: correct and slower (NULL)

Correctness held. Every gate line equals k7b's: `gc2-small-s3-P`, `gc2-max-s7-P` and `ga-max-P` PASS rc 0;
`ge-max-9000-P` E 9000 2243 1445466 539226; `ge-max-30000-P` E 30000 2243 1338156 499194; PT FAIL rc 47 at
both shapes. `t200-B` and `t200-P` both give T 9200 1508182, `ck_after` ec4a8c21…, so P is bit-identical
to B over 200 steps.

The pre-registered direction (max P GEMM < min B GEMM) failed. P was slower in every round:

| round | B 64×64 (32-39) | P 64×64 (40-54) | B GEMM | P GEMM | B all | P all |
|---|---|---|---|---|---|---|
| 1 | 84601623 | 96179499 | 101512980 | 112729398 | 151255111 | 162922346 |
| 2 | 85861212 | 97654966 | 102465130 | 114242228 | 152718879 | 163696258 |
| 3 | 87105521 | 100626839 | 103915264 | 117865096 | 154157322 | 168759697 |

(ns of GPU wait summed over each id's launches in one profiled step.) P/B means: 64×64 1.14324, GEMM
1.11999. `t200` wall: P/B 1.06900 (WolframLanguageEvaluator: `Mean[p64]/Mean[b64]` → 1.14324,
`Mean[pg]/Mean[bg]` → 1.11999, `Min[p64] > Max[b64]` → True, `36796113367/34420909746` → 1.06900). k8
as pre-registered is a NULL result, and this record stands.

## a3: why it was slower, as a new hypothesis

a2's prereg had flagged one occupancy risk [INFERENCE]: QMD word 36 was the fixed 78923776 + smem,
which encodes the SM shared-memory config MIN 9 / MAX 26 / TARGET 9 (32 / 100 / 32 KiB) for every kernel.
Mesa NAK sizes TARGET per kernel instead (`src/nouveau/compiler/nak/qmd.rs:580-606`,
`gv100_get_hw_smem_sizes`): it takes the smallest carveout that holds the shared memory of every
resident workgroup. The GB10 (sm121) carveouts are 0, 8, 16, 32, 64 and 100 KiB
(`src/nouveau/winsys/nouveau_device.c:218-231`).

`gksmw id` now computes word 36 that way. Residency is register-limited here, so it uses
`Floor[65536/(gkgpr·gkthr)]` blocks (WolframLanguageEvaluator, `a3/prereg.txt`):

| kernels | blocks × smem | need | TARGET |
|---|---|---|---|
| 32×32 GEMM (ids 0-7) | 9 × 4608 B | 41472 B | 17 (64 KiB) |
| 64×64 k7b (ids 32-39) | 7 × 4352 B | 30464 B | 9 (32 KiB, as before) |
| 64×64 k8 (ids 40-54) | 6 × 8704 B | 52224 B | 17 (64 KiB) |
| gr.om (64 threads, 72 GPR) | 14 × 1024 B | 14336 B | 9 (as before) |

MIN and MAX are unchanged (packed 3426304; with TARGET 9 that gives the old 78923776). `gpu-dump.om`
emits each id's TARGET (stderr bytes 64-127), and `gpu-disasm.sh` prints `SMEM <id> target <t>`. In this
commit's tree, ids 0-7 and 40-54 report 17 and ids 9-24 report 9, at both shapes.

The a3 arms isolate the two changes. Both add the same 28-line TARGET delta (`a3/srcdiff-b-to-c.txt`
and `a3/srcdiff-p-to-q.txt`):

| arm | binary | code |
|---|---|---|
| B | 50dcd16e… | k7b (`git archive fc9af27`, rebuilt byte-equal) |
| C | 58c207ea… | k7b + TARGET rule. Kernel bytes equal k7b's (code_sha256 9659b361… / cd777d34…); only word 36 of ids 0-7 moves |
| Q | 0b701583… | a2's k8 + TARGET rule. Kernel bytes equal a2's (70e215af… / 9b2e6d92…) |
| QT | 3619ef31… | Q mutant t |

Pre-registered decision rules [INFERENCE, not gates]. The metric is GPU wait per id group per profile:
R1 compares C and B on the 32×32 GEMM (GAIN if max C < min B, HARM if min C > max B, otherwise NULL).
R2 compares Q ids 40-54 with C ids 32-39 (ADOPT k8 if max Q < min C). The product table maps k8 adopted
and R1 not HARM to Q.

### Gates

| prediction (`a3/prereg.txt`) | receipt | result |
|---|---|---|
| Q, C `gcmp2` small, 3 steps: rc 0, k7b line | `gc2-small-s3-{Q,C}.txt` GCMP2 PASS rc=0 | PASS |
| Q, C `gcmp2` max, 7 steps: rc 0, k7b line | `gc2-max-s7-{Q,C}.txt` GCMP2 PASS rc=0 | PASS |
| Q, C `gacmp` max rc 0 | `ga-max-{Q,C}.txt` GACMP PASS rc=0 | PASS |
| QT `gcmp2` small and max FAIL rc 47 | `gc2-*-QT.txt` GCMP2 FAIL rc=47 | PASS (caught) |
| Q, C `geval` E 9000 2243 1445466 539226 | `ge-max-9000-{Q,C}.txt` same line | PASS (Δ 0) |
| Q, C `geval` E 30000 2243 1338156 499194 | `ge-max-30000-{Q,C}.txt` same line | PASS (Δ 0) |
| `t200` B, C, Q: rc 0, T 9200 1508182, `ck_after` ec4a8c21… | `t200-{B,C,Q}.txt` | PASS (byte-equal) |
| every `gprof` run T 30003 1298769 | `prof-*-{B,C,Q}.txt` | PASS |

### Speed (non-quiet)

`gprof 3`, three rounds in rotated order (B C Q / Q B C / C Q B). The ns are summed over each id's
launches. The 32×32 GEMM launches only ids 0-1 at this shape.

| round | B 32×32 | C 32×32 | Q 32×32 | B 64×64 (32-39) | C 64×64 (32-39) | Q 64×64 (40-54) |
|---|---|---|---|---|---|---|
| 1 | 16459108 | 16524177 | 16441792 | 84905231 | 83783796 | 75138393 |
| 2 | 16663587 | 16413906 | 16948421 | 85800560 | 83075824 | 75750789 |
| 3 | 16749091 | 16819606 | 16777507 | 84865330 | 84192404 | 78239735 |

| round | B GEMM | C GEMM | Q GEMM | B all | C all | Q all |
|---|---|---|---|---|---|---|
| 1 | 101364339 | 100307973 | 91580185 | 151227974 | 150338927 | 141531873 |
| 2 | 102464147 | 99489730 | 92699210 | 152679985 | 149689072 | 142690663 |
| 3 | 101614421 | 101012010 | 95017242 | 151650481 | 151432860 | 145193708 |

- R1: NULL. GAIN False, HARM False. Means B 16.6239 ms, C 16.5859 ms, C/B 0.997712.
- R2: ADOPT k8. Max Q (78.240 ms) < min C (83.076 ms). Means C 83.6840 ms, Q 76.3763 ms, Q/C 0.912675.
- Product: Q.
- GEMM means: B 101.814, C 100.270, Q 93.0989 ms. Q/B 0.914399, Q/C 0.928483.
- All ids: B 151.853, C 150.487, Q 143.139 ms. Q/B 0.942615.

(WolframLanguageEvaluator over the triples above: `Max[c32]<Min[b32]` → False, `Min[c32]>Max[b32]` →
False, `Mean[c32]/Mean[b32]` → 0.997712, `Max[q64]<Min[c64]` → True, `Mean[q64]/Mean[c64]` → 0.912675,
`Mean[qg]/Mean[bg]` → 0.914399, `Mean[qg]/Mean[cg]` → 0.928483, `Mean[qt]/Mean[bt]` → 0.942615.)

`t200`, run in the order B, C, Q:

| binary | wall | GPU wait (GT field 9) | launches | wait per launch |
|---|---|---|---|---|
| B (k7b) | 34.205 s | 30.402 s | 63800 | 0.4765 ms |
| C (k7b + TARGET) | 34.490 s | 30.636 s | 63800 | 0.4802 ms |
| Q (product) | 33.144 s | 29.237 s | 63800 | 0.4583 ms |

Q/B: wall 0.968991 (−3.10%, 5.30 ms per step) and wait 0.961688. Q/C: wall 0.960984, wait 0.954339. B ran
1.0031× the k7b window's 34.101 s (WolframLanguageEvaluator: `33144257073/34204930629` → 0.968991,
`29236810718/30401563512` → 0.961688, `(1 − 33144257073/34204930629)·100` → 3.10094,
`(34204930629 − 33144257073)/200/10^6` → 5.30337, `33144257073/34489929937` → 0.960984,
`29236810718/30635671386` → 0.954339, `29236810718/63800/10^6` → 0.458257,
`34204930629/34100849240` → 1.00305).

### Caveat: the identical-kernel spread

C's ids 32-39 run exactly B's kernel bytes and QMD (TARGET 9 in both), yet C was below B in every
round: C/B 0.982318, max C < min B True. That ~1.8% is an artifact of the non-quiet box and of the run
order, not of code. R2's gain (1 − 0.912675) is 4.93854× that artifact, and min C / max Q is 1.06181
(WolframLanguageEvaluator: `Mean[c64]/Mean[b64]` → 0.982318, `Max[c64]<Min[b64]` → True,
`(1 − Mean[q64]/Mean[c64])/(1 − Mean[c64]/Mean[b64])` → 4.93854, `Min[c64]/Max[q64]` → 1.06181).

## Reading

The TARGET mechanism itself was not measured. Nothing here reads the carveout the hardware chose. The
reversal is what TARGET-limited residency predicts: under TARGET 9 the pipelined kernel was 1.12× slower
than k7b, and under its own TARGET 17 it is 0.913× of the same-window k7b kernel [INFERENCE]. Under a
32 KiB carveout, 8704 B blocks allow `Floor[32768/8704]` = 3 per SM against 6 by registers. For the
32×32 GEMM, R1 found no effect beyond the spread, and Q's ids 0-1 sit at Q/B 1.00593. The rule stays
because the 64×64 kernel needs it and because it is the Mesa policy, not because it sped up the 32×32
GEMM.

## Next

Fusion: softmax into the attention GEMMs, id 46 (256×256×32; k7b id 35, mapped 32 + i → 40 + 2i) and
ids 0-1 (256×32×256).
