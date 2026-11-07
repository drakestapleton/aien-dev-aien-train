# Omega LLM v4: the scaled architecture (DRA-162)

Source: [`native/omegallm/v4.om`](../../native/omegallm/v4.om) (its header notes are the normative
detail). Built by [`tests/omegallm/build.sh`](../../tests/omegallm/build.sh) after `cli.om` on the
Linux targets (aarch64, gb10, x86linux); x86efi gets [`no4.om`](../../native/omegallm/no4.om), whose
v4 commands exit 2. Receipts: [`tests/omegallm/v4-check.sh`](../../tests/omegallm/v4-check.sh) and, for the wte banks,
[`tests/omegallm/v4-wide-check.sh`](../../tests/omegallm/v4-wide-check.sh).
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

### 2.1 Windows and the wte banks (wide4)

Window `ow` (and `ogr` for gradients) holds **gf at 0, then the resident layers from WS = D**; when
not every layer fits, one staging slot follows. `wte` and its gradient do not live in a window: they
sit in two banks each, the v3 pools that v4 never otherwise uses (`opa` from `model.om`, `oww`,
`ogb`, `oab` from `lpool.om`; no new globals, no larger ones):

| Rows of wte | wte (parameters) | dwte (gradient) |
|---|---|---|
| bank 1: c < R1 | `opa[c·D ..]` | `ogb[c·D ..]` |
| bank 2: R1 ≤ c < V | `oww[RT + (c − R1)·D ..]`, RT = T·E (after the RoPE table) | `oab[(c − R1)·D ..]` |

with R1 = min(V, ⌊XWB1 / D⌋), XWB1 = 14,161,920 = OGBN ≤ OPAN, XWB2 = 15,733,760 = OABN. Every row
lies in one bank. The embedding gather (`xcpe`), the tied logits (`xlogit`, one ascending sum per
logit), the gradient outer product (`xgerw`), the embedding backward (`xembg`) and the
dz = dl·wte column sums (`xdz`) address the banks directly; the column sums run over bank 1's rows and
then on over bank 2's in the same accumulator, so every result has the bits of the one-window layout
(the virtual parameter order and the CK03 payload are unchanged; receipts in section 6.1).

**Limits** (Wolfram; `init4` exits 12 past any of them):

- layers: D + one LSTR ≤ min(OWC, OGC) = 15,833,472;
- wte: (V − R1)·D ≤ XWB2 and T·E + (V − R1)·D ≤ OWWN = 15,932,160, i.e. V·D ≲ XWB1 + XWB2 =
  29,895,680. At V = 32768 the widest even D is 912; D 1024 (bank 2 would need 19,392,512) and
  V 65536 D 512 (the same) are refused;
- decode (`xgd`): 8D + 2F + 4 + V + T + 2·T·D ≤ OAC (one KV slot);
- training forward (`train4`, `eval4`, `gcheck4`, `kvck`): the activation layout `xga`, one layer
  slot ASTR4 = 6TD + 2T + TF + HT after 5TD + 3T + 5D + F + V. These commands exit 12 when it does
  not fit; `init4`, `tune4` and `sample4` need only the weights and the decode layout. For S1 the
  training forward fits up to T = 1947, so a T = 4096 S1 checkpoint loads for `sample4` (3 KV slots:
  2 resident layers and the staging slot) but trains on the CPU only at T ≤ 1947.

| Shape (V 32768) | V·D | R1 | bank-2 values | LSTR | RW at L 8 (old layout) |
|---|---|---|---|---|---|
| D 384 H 6 F 1536 | 12,582,912 | 32,768 | 0 | 1,770,240 | 8, all resident (0: every layer staged) |
| S1: D 512 H 8 F 2048 | 16,777,216 | 27,660 | 2,615,296 | 3,146,752 | 4 + staging (refused) |
| D 768 H 12 F 3072 | 25,165,824 | 18,440 | 11,003,904 | 7,079,424 | 1 + staging (refused) |
| D 912 F 3648 | 29,884,416 | 15,528 | 15,722,880 | 9,982,752 | 0 + staging (refused) |
| D 1024 F 4096 (refused) | 33,554,432 | 13,830 | 19,392,512 > XWB2 | 12,584,960 | — |

Why banks and not tiling the logits over chunks of wte staged from mapping 0 (option b): map access
costs ~28 ns (`mapget`) / ~31 ns (`mapset`) per f64 against ~2.9 ns per multiply-add (MEASURED, core
4). The head reads every wte row once per position, so staging rows per position costs V·D·28 ns =
0.470 s per token at S1 against 0.146 s of head arithmetic (3·V·D multiply-adds; MODELED from the
measured unit costs, Wolfram), and staging once per sequence needs T·V stored logits (T ≤ 458 even with all of
`oa`, at V 32768). The banks cost nothing per step beyond the one-window layout: the per-step copies
are the same V·D values as before (master to wte after Adam, dwte to the gradient region).

Map access costs ~31 ns (`mapset`) and ~28 ns (`mapget`) per f64, against ~2.9 ns per dot-product
multiply-add (MEASURED, core 4), so staged layers pay a copy per step but no per-element map call
inside the kernels.

`build.sh --variant wx` (bx's window sizes plus XWB1 2000) makes the small shape
V 256 T 32 D 18 H 3 F 32 L 4 cross the bank boundary (R1 = 111 of 256 rows) with staged layers and
activations; `--mutant j` (wx plus OMUTJ 0) restarts the dz sums at bank 2 and `--mutant jd` (wx plus
OMUTJD 0) embeds a bank-2 token from row c xor 1 in decode only. Receipts:
[`tests/omegallm/v4-wide-check.sh`](../../tests/omegallm/v4-wide-check.sh).

## 3. Commands

| Command | Arguments | Output / exits |
|---|---|---|
| `init4` | `CK V T D H F L B SEED TOTAL LRMICRO G` | fresh CK03; `I P`; 12 shape refused (section 2.1 limits) |
| `train4` | `CK TRAIN UNTIL EVERY [K]` | `T step loss_micro`; K worker processes (29 when K∤G); 12 when the training layout does not fit |
| `eval4` | `CK HELD W [MERGES]` | as `eval`; at V > 256 without MERGES (token mode) the last field is bits per token |
| `sample4` | `CK SEED N TEMPMILLI PROMPT [MERGES]` | KV-cache decode; at V > 256 without MERGES (token mode) PROMPT is a file of u16 LE tokens (≤ T; 21 odd length, 25 a token ≥ V) and the output is u16 LE tokens, which `ollm-tok tokdec` decodes |
| `tune4` | `CK OUT TOTAL LRMICRO` | `U P` |
| `gcheck4` | `CK TRAIN` | central differences at 4 indices of every tensor; 40 over tolerance |
| `ropeck` | `REF` | sin/cos vs Wolfram + shift identity; 43 |
| `kvck` | `CK DATA` | training forward vs KV decode, bit-exact logits; 44 |

Given an OLLMCK01/02 file, `train4 eval4 sample4 gcheck4 tune4` run the v3 command. Data files are
u8 tokens when V ≤ 256 and u16 little-endian otherwise (as v3; a wrong width is exit 21).
`sample4`/`eval4` with MERGES use the v3 BPE loader, which holds at most 4096 tokens (exit 27
beyond): V = 32768 text I/O inside ollm needs the 32k tokenizer unit; until then token mode composes
with `ollm-tok tokenc`/`tokdec` (OLLMTOK1). `train4`, `eval4`, `gcheck4` and `kvck` exit 12 when the
training activation layout does not fit (section 2.1).

## 4. Checkpoint OLLMCK03

128-byte header: magic `OLLMCK03`, V T D H F L B, seed, step, TOTAL, lr bits, P, G, rope base
bits, FNV-1a 64 of the payload; payload 24·P bytes (params, m, v; f64 little-endian). Load exits:
10 short, 11 magic (any other version, including `OLLMCK04`), 12 shapes, 13 P, 14 FNV, 15 long,
70 I/O. v3 commands refuse CK03 with 11.

## 5. Mutants

`build.sh --mutant i` rotates K with the wrong sign in the forward (the backward keeps the true
inverse): `gcheck4` and `ropeck`'s shift check must fail. `--mutant z` applies R instead of Rᵀ in
the backward: `gcheck4` must fail.

Mutants j and jd and variant wx of the wte banks: section 2.1.

## 6. Receipts

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

### 6.1 Wide receipts (wte banks, wide4)

MEASURED 2026-11-07 on Spark core 6 (nice 10; core 6 was shared with other lanes' processes, so wall
times are noisy and the per-step costs below are user + sys CPU seconds), aarch64 product binary
`aa6cceda…` (source of this commit), reference binary `beecf5fa…` (63353c9, wte in `ow`). Evidence:
[`evidence/OMEGALLM/v4/wide/`](../../evidence/OMEGALLM/v4/wide/).

| Check | Result |
|---|---|
| `v4-wide-check.sh` | 46 of 46 PASS |
| CK03 written by the reference build: `eval4`, `gcheck4`, `kvck`, `sample4` on the bank build | outputs byte-identical; 3 more `train4` steps (K = 2): checkpoints byte-identical |
| crossing shape V 256 T 32 D 18 H 3 F 32 L 4 on `--variant wx` (R1 = 111, layers and activations staged) | `gcheck4` PASS rc 0, output byte-identical to the reference build's; `train4` K = 1, K = 2 and reference byte-identical; `kvck` 0 of 32 differ |
| mutant j `gcheck4` / mutant jd `kvck` | rc 40 (max relative error 1.99, tolerance 1e-3) / rc 44 (30 of 32 positions differ), as required |
| V 32768 D 512 H 8 F 2048 L 2 (R1 = 27,660, product build) | K = 1 vs K = 2 byte-identical; `kvck` 0 of 32 differ; token-mode `eval4`, `sample4` rc 0 |
| `init4` V 32768 D 768 (L 1 and L 8, P 81,801,984) / D 1024 / V 65536 D 512 | rc 0 / 12 / 12 |
| old `v4-check.sh` on the bank build (tree snapshot `ce3bb2d`) | 17 of 17 PASS |
| v3 `equiv.sh` reference vs bank build, product and `--variant bx` | EQUAL (eval lines, checkpoints after 5 steps) |
| V 32768 D 384 H 6 F 1536 L 6 B 4, one `train4` step | checkpoints byte-identical; 115.5 s CPU vs 129.8 s on the reference (−11.0 %: every layer is now resident) |

`v4-check.sh` trains on this repository's own text, which changes with every commit; its `gcheck4`
receipt can exceed GCTOL on some texts with the reference build too (`gcheck-textdep.txt`: max
relative error 1.44e-3, rc 40, byte-identical on both builds).

Full S1 (V 32768 T 256 D 512 H 8 F 2048 L 8 B 2 G 2, P = 41,951,744, CK03 1,006,841,984 bytes) on
public text (the first 3,000,000 bytes of the base `val.txt`, 32K-tokenized):

| Command | Result |
|---|---|
| `init4` | rc 0, 4.9 s, 558 MB RSS |
| `train4` | loss 10.548, 10.325, 9.996 (steps 1–3); RSS 2.24 GB; marginal step 107.0 s CPU (512 tokens, 4.79 tok/s per core), load + save 14.7 s CPU |
| `eval4` (token mode, 2 windows) | rc 0, 14.71 bits per token |
| `sample4` (token mode, 16 tokens, KV decode) | rc 0; decoded with `ollm-tok tokdec` |
| `kvck` | 0 of 256 positions differ |
| `tune4` | rc 0 |
| S1 at T 4096: `init4`, `sample4` / `train4` | rc 0 (decode: 2 resident KV layers + staging) / 12 (training layout) |
| D 768 H 12 F 3072 L 8 (P 81,801,984): `init4`, `eval4` | rc 0, rc 0 (RSS 2.34 GB) |

NOT_RUN: x86linux and x86efi builds (no x86 pin on Spark), GB10 kernels for v4, `sample4` text I/O at
V > 4096 inside ollm (needs the 32k tokenizer unit; token mode covers it), a long training run,
S1 `gcheck4` (gcheck4 runs on the wx crossing shape and the small shapes).

MODELED (Wolfram, 6·P·tokens, attention excluded) for P = 23,204,736 at the GB10's MEASURED
end-to-end v1 rate of 1.91 TFLOP/s (`evidence/OMEGALLM/gpu-max/README.md`; v4 has no GPU path
yet, so this assumes one): 13,718 tok/s, i.e. 1.19e9 tokens in 24 h, 8.30e9 in 7 d, 3.56e10 in
30 d; one epoch of the 550M-token base text 11.1 h, of a 3M-token personal corpus 3.6 min.
