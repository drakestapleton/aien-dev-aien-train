# Omega LLM v4 on the GB10 (CONTRACT-V4 GPU path)

Source: [`native/omegallm/gpu/g4.om`](../../native/omegallm/gpu/g4.om) (header notes are normative),
the v4 kernels in [`gpu/gr.om`](../../native/omegallm/gpu/gr.om) (slots 12, 17, 18, emitted only in v4
mode), built by [`tests/omegallm/build.sh`](../../tests/omegallm/build.sh) `TARGET=gb10` (g4.om after
gg.om). Gates: [`tests/omegallm/v4-gb10-check.sh`](../../tests/omegallm/v4-gb10-check.sh). Receipts:
[`evidence/OMEGALLM/v4/gb10/`](../../evidence/OMEGALLM/v4/gb10/). Compiler: omega-mv `e5b32567` omc
(sha256 `2c824805…`). Raw NVIDIA driver through the vendored CUDApp `context.om`/`launch.om`; no CUDA,
no outside weights, tokenizers or engines.

## 1. Semantics on the chip

Same model, data, batches, schedule and checkpoint as CONTRACT-V4 (`train4`):

- **RoPE**: after the batched Q/K/V GEMM, kernel 12 (ROPE) rotates every pair (2j, 2j+1) of every Q
  and K row at position t by the f32 image of v4's own f64 table (`xrtab`: angle t·10000^(−2i/E),
  i = j mod E/2): y0 = x0 c − x1 s, y1 = x0 s + x1 c, one launch over Q and K (contiguous). The
  backward applies the inverse table (c, −s) = Rᵀ to dQ and dK before dA and the weight gradients.
- **No wpe**: the embedding kernel adds a zero row block (gga 43) instead of v3's wpe.
- **Tied logits and CE over V columns in row chunks**: RC = the largest multiple of 64 with
  RC·V ≤ 2^26 floats and RC ≤ T (V 32768: RC 2048, logits buffer 256 MiB). Per chunk: logits GEMM,
  v3's warp-per-row Kahan CE kernel (V a multiple of 256), dZ = L·wte into DA, dwte += Lᵀ Z.
- **Long context**: for T a multiple of 256 the causal softmax forward and backward are kernels 17/18
  (SOFTFL/SOFTBL): one warp per row, looped over the 256-column chunks c ≤ t/256 (three passes forward,
  two backward), columns above t read as −∞ / 0. T ≤ 512 otherwise uses v3's register kernels 15/16.
  P (B·H·T·T f32) is kept per layer in its own `nvalloc` (see section 3); DP is one buffer.
- **State on the chip**: f32 master weights, f32 Adam m and v (v3's kernels 23/24: clip to norm 1,
  bias correction, `olrs`) stay resident for the whole run. Only CK03 moves: load → mapping 0 (f64) →
  f32 upload; at a save point chip f32 → f64 (exact) → mapping 0 → `xsave` (v4's unchanged mapping 0
  layout and file format). The host window limit OWC (15,833,472 f64) does not apply: S1
  (V·D = 2^24) trains on the chip, while CPU `init4`/`train4` refuse it (exit 12).

**Compute choice: BF16 GEMMs (CONTRACT-BF16) with f32 master weights and Adam** for `gtrain4`, the
rung-10 choice Drake adopted 2026-11-03: the BF16 kernels are qualified exactly (gbfrag) and long
runs showed no loss regression against f32 (rung 9/10: −0.15 … −0.23 % held-out). `gtrain4f` keeps
every GEMM f32 (same results as the parity gate's numerics); `geval4` is f32 like v3's `geval`.

## 2. Commands (gb10 binary `ollm-gb10`)

| Command | Arguments | Output / exits |
|---|---|---|
| `ginit4` | `CK V T D H F L B SEED TOTAL LRMICRO G` | `init4` without the host window limit; byte-identical to `init4` where both run |
| `gtrain4` / `gtrain4f` | `CK TRAIN UNTIL EVERY` | `train4`'s `T step loss_micro` at save points, then `G4 steps tokens step_ns save_ns fwd_ns head_ns bwd_ns adam_ns device_bytes RC` |
| `geval4` | `CK HELD W [MERGES]` | `eval4`'s `E` line (bpb 0 for V > 256 without MERGES), `GE ns` |
| `ggrad4` | `CK TRAIN OUT` | CPU (v4.om f64) loss and gradient of the CK's step into OUT (`OLLMGR04`, P, step, loss, P f64) |
| `gcmp4` / `gcmp4b` | `CK TRAIN GRAD` | chip loss/gradient (f32 / BF16 GEMMs) vs GRAD: `GC4 k n rel_e9 maxd_e12 maxc_e12` per tensor class, `GL4`, `GN4`, `GT4 tol_e9`, `GCMP4 PASS` or exit 51 |
| `gprof4` | `CK TRAIN N` | N BF16 steps, last one profiled (`GP id gx gy gz m n k wait_ns`) |

Chip shape limits (exit 12): V a multiple of 256, ≤ 65536; D ≤ 1024 (RMS banks); E, F multiples of
32; T a multiple of 64, and of 256 above 512; B·H ≤ 65535; B·H·T·T·4 < 2^32 (32-bit GEMM operand
offsets); B·T ≤ 262144; L ≤ 64; arena ≤ 16.384·10^9 bytes. A driver open that reports nverr 81
(context.om nvchan: compute object in use) is torn down and retried up to 12 times (`G4R` lines).

## 3. Gates (pre-registered in g4.om and the check script)

**Parity (`gcmp4`)**: per tensor class (wte g1 Wq Wk Wv Wo g2 W1 W2 gf) rel = ‖g_chip − g_cpu‖₂/‖g_cpu‖₂,
and |ΔL|/L, against ggrad4's f64 CPU reference of the same CK03 and batch. f32 tolerance
tol = (10L + 3)·k·2^−24, k = max(R, D, F, V): the first-order bound γ_k of a length-k f32 sum (the
longest reduction) over the 10L + 3 GEMMs of the longest chain. BF16 (`gcmp4b`): CONTRACT-BF16's
gbcmp2 heuristic (10L + 3)(2u + u²), u = 2^−8 (gross failures only). Mutants (build.sh `--mutant`):
**rs** rotates K with the inverse table in the forward (the RoPE sign flip), **ri** skips Rᵀ on dQ/dK,
**cc** drops the head's last CE row chunk; each must exit 51. **sv** (saves no Adam v) is the resume
check's control.

MEASURED 2026-11-07 (GB10, windows g4-gates3 `20261107T002829Z-3db3e8` and g4-trained5
`20261107T004432Z-6a6d6c`, `--quiet none`, core 5, binary `405809ec…`); rel and tol ×10^9, tol values
recomputed by Wolfram:

| Shape (V T D H F L B) | gcmp4 max rel (class) | tol | ΔL µnat | gcmp4b max rel | BF16 tol |
|---|---|---|---|---|---|
| p1 256 64 64 2 128 2 2 | 436 (Wk) | 350,952 | 0 | 28,006,577 | 180,038,452 |
| p2 256 512 64 2 128 2 2 (SOFTFL/BL, 2 chunks) | 466 (g1) | 1,403,809 | 1 | – | – |
| p4 4096 1024 512 8 2048 1 2 (4 chunks) | 415,241 (Wk) | 3,173,828 | 0 | 21,371,711 | 101,760,864 |
| p3 16384 256 512 8 2048 2 2 (S1 width) | 1,791 (Wq) | 22,460,938 | 0 | 31,236,519 | 180,038,452 |
| r200 256 256 128 4 512 2 8, chip-trained 200 steps | 1,344 (Wk) | 2,807,617 | 0 | 36,910,600 | 180,038,452 |

Every mutant failed (rc 51) with its largest class rel ×10^9: rs 620,984,050 (p1), 609,848,161
(p3), 3,426,905,981 (r200, loss 2.112654 → 3.010336); ri 707,395,515 / 774,217,878 / 1,291,928,364
(loss unchanged: backward only); cc 633,978,947 / 598,816,638 / 357,193,110 (loss non-finite: the
dropped chunk's rows have no CE stats). 18 of 18 parity receipts as predicted.

**Checkpoint continuation**: r (V256 T256 D128 H4 F512 L2 B8, byte data, BF16 `gtrain4`):
uninterrupted 0 → 200 against 0 → 100, save, reload, 100 → 200: both CK03 files sha256
`af1875f4…dd9b4`, byte-identical (`resume-cmp-ollm-gb10.txt`); mutant sv's two files differ
(`resume-cmp-ollm-mut-sv-gb10.txt`). Same sha256 from two binaries (before and after the P-buffer
move), so the move left the arithmetic bit-identical.

**CPU eval of a chip-trained CK**: chip `geval4 r200.ck held 146` and CPU `eval4` printed the same
line `E 200 146 2342464 3379462` (`eval-cmp.txt`).

## 4. Throughput and memory (S1: V 32768 D 512 H 8 F 2048 L 8, P 41,951,744 by Wolfram)

MEASURED, window g4-trained5, **non-quiet** (`--quiet none`; a `--quiet exclusive` window waited on
load 14-15 > 10 and was withdrawn, see section 6), 10 BF16 `gtrain4` steps from `ginit4`, data
`tr40.u16` (first 40 MB of ~/data-omega/base/train.txt through merges32k); tok/s = tokens / summed
step wall (Wolfram):

| T | B | tokens/step | step ms | tok/s | device bytes (arena + P) | host max RSS |
|---|---|---|---|---|---|---|
| 1024 | 16 | 16384 | 550.8 | 29,744 | 10,385,138,176 (9.67 GiB) | 10.61 GiB |
| 2048 | 8 | 16384 | 686.2 | 23,876 | 15,357,469,184 (14.30 GiB) | 15.25 GiB |
| 4096 | 4 | 16384 | 1054.8 | 15,534 | 25,033,720,320 (23.31 GiB) | 24.26 GiB |

Beyond S1 (3-step smoke, non-quiet): S1 at T 8192 B 1 ran at 8,590 tok/s with 22,692,538,880 device
bytes; V 32768 T 1024 D 1024 H 16 F 4096 L 16 B 4 (P 234,914,816, CK 5.25 GiB) at 6,679 tok/s with
12,992,922,368 device bytes. These are the largest shapes run; host RSS counts the unified-memory
arena pages the CPU zero-fills at open. Profile (`prof/gprof4-s1t4096.txt`): the looped softmax kernels
take 302 ms of the step's ~1015 ms GPU wait at T 4096 (SOFTBL 25 ms/launch ≈ 53 GB/s of required
traffic), the first kernel to tune.

MODELED from the MEASURED non-quiet rates (pure step time; each run also paid, MEASURED, 11.1 / 14.4 /
19.4 s for CK load, open and upload and 7.7 / 7.6 / 8.0 s per 1 GB CK save at T 1024 / 2048 / 4096):

| T | tokens per 20-min window | tokens per 24 h |
|---|---|---|
| 1024 | 3.57·10^7 | 2.57·10^9 |
| 2048 | 2.87·10^7 | 2.06·10^9 |
| 4096 | 1.86·10^7 | 1.34·10^9 |

## 5. Limits found

- `context.om` `nvalloc` zero-fills a new allocation with a `while` of 16 KiB `mapwrite`s under the
  default bound of 10^6 passes: one allocation holds at most 16.384·10^9 bytes (S1 at T 4096 first
  trapped 4 in a single 25 GB arena). g4 puts each layer's P in its own allocation and refuses an
  arena above the cap; the vendored file is unchanged.
- The vendored nvchan's compute object returned nverr 81 for minutes at a time during window
  g4-parity1 (also for v3 `gprof`); g4 retries the whole open (section 2). Cause not identified.

## 6. NOT_RUN

- `--quiet exclusive` timing (the window waited for load ≤ 10; withdrawn); all speeds above are
  non-quiet.
- A long S1 training run and its held-out eval; `geval4` at V 32768 with OLLMTOK1 text decoding (the
  v3 BPE loader holds ≤ 4096 tokens).
- CPU parity at V 32768 D 512 (CPU v4 refuses V·D > OWC until the wide4 window change; the S1-width
  gate uses V 16384).
- x86 targets (gb10 only).
