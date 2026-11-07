# Omega LLM v4: the scaled architecture (DRA-162)

Source: [`native/omegallm/v4.om`](../../native/omegallm/v4.om) (its header notes are the normative
detail). Built by [`tests/omegallm/build.sh`](../../tests/omegallm/build.sh) after `cli.om` on the
Linux targets (aarch64, gb10, x86linux); x86efi gets [`no4.om`](../../native/omegallm/no4.om), whose
v4 commands exit 2. Receipts: [`tests/omegallm/v4-check.sh`](../../tests/omegallm/v4-check.sh).
Compiler: omega-mv `e5b32567` omc (sha256 `2c824805…`). No outside weights, tokenizers or models.

## 1. Model

Decoder-only, pre-RMSNorm, ReLU FFN, tied embedding, **rotary positions (RoPE, no `wpe`)**:

- shape `V T D H F L` with 256 ≤ V ≤ 65536, 2 ≤ T ≤ 16384, D ≤ 8192, H ≤ 64, D mod H = 0 and the
  head width E = D/H even, F ≤ 65536, L ≤ 4096; batch B ≤ 4096 in G gradient blocks (G divides B).
- per layer: `g1[D] Wq Wk Wv Wo [D][D] g2[D] W1[D][F] W2[F][D]`, LSTR = 4D² + 2DF + 2D;
  P = V·D + L·LSTR + D (wte first, gf last).
- RoPE: pair i of a head at position m rotates by m·base^(−2i/E), base 10000 (stored in the
  header). Q and K are rotated after projection; the backward applies the inverse rotation Rᵀ.
- v3 checkpoints keep v3's V ≤ 4096 cap; only CK03 accepts the larger vocabularies.

## 2. Memory outside the omc globals limit

The 2^30-byte globals limit (omc error 23) bounded v3's P. v4 keeps the master state in host
mappings (`mapnew`/`mapget`/`mapset`) and stages layers through the existing windows:

| Mapping | Contents | Size |
|---|---|---|
| 0 private | params, Adam m, Adam v | 3P f64 |
| 1 shared | G gradient regions + B sequence losses (train4/gcheck4 workers) | G·P + B f64 |
| 2 private, lazy | saved activations of layers that do not fit `oa` | ASTR4 = 6TD + 2T + TF + HT per layer |
| 3 private, lazy | KV cache of decode layers that do not fit | 2TD per layer |

Window `ow` (and `ogr` for gradients) holds wte at 0, gf at V·D, then the resident layers from
WS = V·D + D; when not every layer fits, one staging slot follows. **Limit:** WS + one LSTR must
fit min(OWC, OGC) = 15,833,472 f64, so wte and gf are always resident:

- V 32768, D 384, F 1536: V·D = 12,582,912, LSTR = 1,770,240, total 14,353,536 — fits.
- V 32768, D 512: V·D = 16,777,216 alone exceeds the window — `init4` refuses (exit 12).

Map access costs ~31 ns (`mapset`) and ~28 ns (`mapget`) per f64, against ~2.9 ns per dot-product
multiply-add (MEASURED, core 4), so staged layers pay a copy per step but no per-element map call
inside the kernels.

## 3. Commands

| Command | Arguments | Output / exits |
|---|---|---|
| `init4` | `CK V T D H F L B SEED TOTAL LRMICRO G` | fresh CK03; `I P`; 12 shape refused |
| `train4` | `CK TRAIN UNTIL EVERY [K]` | `T step loss_micro`; K worker processes (29 when K∤G) |
| `eval4` | `CK HELD W [MERGES]` | as `eval` |
| `sample4` | `CK SEED N TEMPMILLI PROMPT [MERGES]` | KV-cache decode; MERGES required when V > 256 |
| `tune4` | `CK OUT TOTAL LRMICRO` | `U P` |
| `gcheck4` | `CK TRAIN` | central differences at 4 indices of every tensor; 40 over tolerance |
| `ropeck` | `REF` | sin/cos vs Wolfram + shift identity; 43 |
| `kvck` | `CK DATA` | training forward vs KV decode, bit-exact logits; 44 |

Given an OLLMCK01/02 file, `train4 eval4 sample4 gcheck4 tune4` run the v3 command. Data files are
u8 tokens when V ≤ 256 and u16 little-endian otherwise (as v3; a wrong width is exit 21).
`sample4`/`eval4` with MERGES use the v3 BPE loader, which holds at most 4096 tokens (exit 27
beyond): V = 32768 text I/O needs the 32k tokenizer unit; training and evaluation on
pre-tokenized u16 files work at V = 32768 now.

## 4. Checkpoint OLLMCK03

128-byte header: magic `OLLMCK03`, V T D H F L B, seed, step, TOTAL, lr bits, P, G, rope base
bits, FNV-1a 64 of the payload; payload 24·P bytes (params, m, v; f64 little-endian). Load exits:
10 short, 11 magic (any other version, including `OLLMCK04`), 12 shapes, 13 P, 14 FNV, 15 long,
70 I/O. v3 commands refuse CK03 with 11.

## 5. Mutants

`build.sh --mutant i` rotates K with the wrong sign in the forward (the backward keeps the true
inverse): `gcheck4` and `ropeck`'s shift check must fail. `--mutant z` applies R instead of Rᵀ in
the backward: `gcheck4` must fail.

## 6. GB10 path

The chip path (`ginit4`, `gtrain4`, `geval4`, `gcmp4`, …; f32 master and Adam resident on the chip, CK03
through mapping 0) is [CONTRACT-V4-GB10.md](CONTRACT-V4-GB10.md).

## 7. Receipts

MEASURED 2026-11-06 on Spark cores 4-5 (nice 10), aarch64 build, training text = this repository's
own `.om` and docs (byte tokens; u16 copies for V > 256):

| Check | Result |
|---|---|
| `gcheck4` (V256 T64 D16 H2 F32 L2 B4 G2), 72 coordinates | PASS rc 0, 0 over tolerance |
| mutant i / mutant z `gcheck4` | FAIL as required: rc 40 (18 / 24 over tolerance) |
| `ropeck roperef.txt` (128 lines, sha256 `94fe7c6c…`) | PASS: max \|err\| 1.11e-16 sin and cos; shift 3.1e-13 |
| mutant i `ropeck` | rc 43 as required (shift difference 1.0e-2) |
| `train4` 40 steps, K = 1 vs K = 2 | loss 5.522 → 5.331; checkpoints byte-identical |
| `OLLMCK04` header on `eval4`/`train4`; v3 `eval` on CK03 | rc 11 each |
| T = 2048 (D128 H4 F512 L2): `eval4` forward, 2 `train4` steps | rc 0; 2.95 s; 19.97 s |
| over 1 GiB: V256 T64 D1024 H16 F4096 L12, P 151,282,688 (CK 3.63 GB) | `init4`, `eval4`, one `train4` step rc 0 (101 s, 4.99 GB RSS) |
| V 32768 T256 D384 H6 F1536 L6 B4 G2 (P 23,204,736), u16 data, K = 2 | 3 `train4` steps rc 0, loss 10.407 → 9.701, 289.7 s (≈10.6 tok/s incl. load); `kvck` rc 0, 0 of 256 positions differ; byte data refused rc 21 |

NOT_RUN: x86linux and x86efi builds (no x86 pin on Spark), `sample4` at
V > 4096 (needs the 32k tokenizer unit), a long training run.

MODELED (Wolfram, 6·P·tokens, attention excluded) for P = 23,204,736 at the GB10's MEASURED
end-to-end v1 rate of 1.91 TFLOP/s (`evidence/OMEGALLM/gpu-max/README.md`; v4 has no GPU path
yet when written, so this assumes one; the measured chip rates are in CONTRACT-V4-GB10): 13,718 tok/s, i.e. 1.19e9 tokens in 24 h, 8.30e9 in 7 d, 3.56e10 in
30 d; one epoch of the 550M-token base text 11.1 h, of a 3M-token personal corpus 3.6 min.
