# Omega LLM oracle (v0 and v1)

`oracle.py` is a referee for `docs/omegallm/CONTRACT.md` (v0) and `docs/omegallm/CONTRACT-V1.md` (v1). It uses only the Python 3 standard library (`math.exp`, `math.log`, `math.sqrt` on f64 floats; no numpy). It was written from the contracts, not ported from `native/omegallm/*.om`. It is for verification only and is never part of the build. The v1 part is described in [v1 referee](#v1-referee-contract-v1); everything before it is v0 and unchanged.

## What it implements

- `OLLMCK01` and `OLLMGR01` read and write, including FNV-1a 64 and the refusals.
- The §5 init.
- The §4 batch offsets: splitmix64 with every product masked to 2^64.
- The §3 forward pass and a hand-written analytic backward pass for the whole model.
- One Adam step with the clip and the LR schedule.
- §4 `prep`, §4 held-out `eval`, and the §7 `base` add-one unigram and bigram models.

## Commands

Run everything on core 8 at nice 19. Core 8 is a Cortex-X925 on the GB10 Grace (MIDR `0x410fd851` in `/sys/devices/system/cpu/cpu8/regs/identification/midr_el1`).

```sh
taskset -c 8 nice -n 19 python3 tests/omegallm/oracle.py selftest
taskset -c 8 nice -n 19 python3 tests/omegallm/oracle.py prep IN TRAIN HELD   # prints P ...
taskset -c 8 nice -n 19 python3 tests/omegallm/oracle.py base TRAIN HELD      # prints B ...
# Cross-checks against an ollm binary. Each writes a JSON receipt with argv, rc, stdout, stderr,
# seconds, the binary sha256 and per-check results.
oracle.py xprep --ollm BIN --data IN --outdir DIR [--receipt R.json]   # sha256 of TRAIN, HELD + stdout
oracle.py xbase --ollm BIN --train TRAIN --held HELD                  # exact micro values
oracle.py xinit --ollm BIN [--cfg small|v0]                           # params bit-for-bit, whole file sha256
oracle.py xgrad --ollm BIN --data DATA [--cfg small|v0] [--batch B]   # loss + every gradient entry
oracle.py xstep --ollm BIN --data DATA [--cfg small|v0]               # train s -> s+1: params, m, v, step
oracle.py xeval --ollm BIN --held HELD [--cfg small|v0]               # eval stdout
# All checks for one binary, with receipts under OUTDIR/LABEL (relative paths, so receipts name none):
DATA=data/TinyStoriesV2-GPT4-valid.txt WORK=scratch-oracle/work tests/omegallm/xcheck.sh BIN LABEL OUTDIR [v0]
```

`selftest` checks:

- The analytic gradient against central differences (h = 1e-5, relative error < 1e-5). It takes 3 to 4 coordinates in every tensor of the small config, at perturbed parameters and with B = 2.
- Known answers for FNV-1a 64, splitmix64, a batch offset and an init draw.
- A checkpoint round trip and the refusal of a corrupted checkpoint.
- The Adam step-0 value and the clip.
- Known answers for prep and for base.

Negative control: flipping the dK sign in the attention backward, or the sign of the one-hot term in the cross-entropy gradient, makes `selftest` fail. See `evidence/OMEGALLM/oracle/README.md`.

The cases in `xgrad` and `xstep`:

- `xgrad`:
  - `init`: a fresh init at step 0;
  - `perturbed`: init plus seeded Gaussian noise of σ 0.3.

  Offsets come from the §4 batch rule on DATA.
- `xstep`:
  - `step0-init`;
  - `step1-chain`: from the binary's own step-1 output, so m and v are nonzero;
  - `step2-unclipped`: gf = 0.1, so the gradient norm stays below 1;
  - `step150-synthetic-clip`: the post-warm-up decay branch, with nonzero m and v.

  Each case asserts that it covers the clip branch it names.

## Known answers

The values were computed with Wolfram (query W1):

```
fnv[s_]:=Fold[Mod[BitXor[#1,#2]*1099511628211,2^64]&,14695981039346656037,ToCharacterCode[s]];
sm[x_]:=Module[{z=Mod[x+16^^9E3779B97F4A7C15,2^64]},z=Mod[BitXor[z,BitShiftRight[z,30]]*16^^BF58476D1CE4E5B9,2^64];
  z=Mod[BitXor[z,BitShiftRight[z,27]]*16^^94D049BB133111EB,2^64];BitXor[z,BitShiftRight[z,31]]];
{fnv[""],fnv["a"],fnv["foobar"],fnv["OLLMCK01"],sm[0],sm[1],sm[2^64-1],sm[42],
 Mod[sm[BitXor[7,Mod[7*16^^9E3779B97F4A7C15,2^64]]],1000], BitShiftRight[sm[47],11]}
-> cbf29ce484222325 af63dc4c8601ec8c 85944171f73967e8 29c48bb36358f164
   e220a8397b1dcdaf 910a2dec89025cc1 e4d971771b652c20 bdd732262feb6e95  533  4352384759967643
```

## Tolerance

`xgrad` and `xstep` compare each entry with

err = |got − ref| / max(|ref|, 10⁻³ · max|ref in that tensor|), and require err ≤ 10⁻⁹.

Both sides are f64, but their summation orders differ. The longest reduction behind any gradient entry is at most n = 4096 terms: B·T·(the inner dimension) stays below that in the small config, and the per-entry accumulation over B·T = 1024 positions in v0 does too. The classical worst-case relative bound is γₙ = n·u/(1 − n·u).

The floor of 10⁻³ of the tensor maximum caps the amplification of cancellation in entries near zero at 10³. Wolfram (query W2):

`u=2^-53; g[n_]:=n u/(1-n u); {N[u],N[g[4096]],N[10^3 g[4096]],N[10^-9/(10^3 g[4096])]} -> {1.11*10^-16, 4.547*10^-13, 4.547*10^-10, 2.2}`

So 10⁻⁹ is 2.2 times the heuristic bound 10³·γ₄₀₉₆. This is a forward-error heuristic, not a proof; the receipts give the observed maximum per tensor.

The loss must also agree to a relative 10⁻⁹, and the printed `loss_micro` must match exactly. Init must agree bit for bit. Prep must be byte-identical. Base and eval must print the same micro integers.

## Contract readings agreed with the core lane

These readings were agreed with OllmCore and are written into CONTRACT.md by that lane:

- A1: the batch input is `S xor ((s·B + b)·0x9E3779B97F4A7C15 mod 2^64)`.
- A2: `wo` and `w2` use `((2r−1)·0.0346…)·(1.0/sqrt(2L))`.
- A3, the clip: `n = sqrt(Σg²)`; if n > 1, then `g ← g·(1/n)`.
- A3, Adam:
  - m = β1·m + (1−β1)·g and v = β2·v + (1−β2)·g², with (1−β) computed in f64;
  - the powers β^(s+1) come from repeated multiplication;
  - p ← p − (lr_s·m̂)/(sqrt(v̂)+ε), where m̂ = m/(1−β1^(s+1)) and v̂ = v/(1−β2^(s+1));
  - lr_s = (lr·(s+1))/100, then lr·(1 − (0.9·(s−100))/max(1, TOTAL−100)).
- A4, `OLLMGR01`:
  - the header copies CK, with step = B;
  - OFFS holds exactly 8·B bytes, and every o ≤ N−T−1.
- A5, `base`:
  - the unigram counts every TRAIN byte;
  - the bigram counts every adjacent TRAIN pair, crossing the 0 separators, and its row denominator is the pair-row sum + 256;
  - both are scored on the M−1 HELD transitions, as mean −log2 p.
- A6, `prep` stdout: `P total train held train_bytes held_bytes`, where the byte counts include the 0 terminators.
- A7, `*_micro`: round half away from zero of the single f64 product v·1e6.
- A7, `train`: prints `T s+1 loss`, using the loss at the pre-update parameters.
- A8: `lr = f64(LRMICRO)/1000000.0`, a single division. For 5784 of the values 1..20000 it differs in bits from `LRMICRO·1e-6`, for example 5, 10 and 15. For 3000 the two agree.

## v1 referee (CONTRACT-V1)

### What it implements

- §2 tokenizer:
  - the chunk rule;
  - `bpefit`, including MAXBYTES cut back to the last 0, the tie rule (smallest a, then smallest b) and overlapping pair counts;
  - `OLLMBPE1` write and load, with exits 26 and 27;
  - `bpeenc` and `bpedec`, u16 token files, exit 21 for an odd file and 25 for a token ≥ V.
- §4 v1 shapes and the over-maximum exit 12.
- §5 G gradient blocks, and the K check (exit 29).
- §6 `OLLMCK02` and `OLLMGR01` with G.
- `train`, `grad`, `eval` with the §7.1 bits per byte, and `sample` (§7.2) with the MERGES argument.

The model arithmetic reuses the v0 forward, backward and Adam code. Only the block grouping, the shapes and the file formats are new.

### Commands

```sh
taskset -c 8 nice -n 19 python3 tests/omegallm/oracle.py selftest-v1
# The ollm command line of CONTRACT-V1 §7; same stdout, files and exit codes as the product:
python3 tests/omegallm/oracle.py ollm bpefit TEXT MERGES V [MAXBYTES]
python3 tests/omegallm/oracle.py ollm train CK DATA UNTIL EVERY [K]          # etc., every §7 command
# Compare a product file with a referee file:
python3 tests/omegallm/oracle.py cmp ck|gr GOT REF   # header bytes exact, payload within the tolerance below
python3 tests/omegallm/oracle.py cmp gline GOT REF   # G line: loss_micro exact, loss bits within the tolerance
python3 tests/omegallm/oracle.py cmp tok|bytes GOT REF
# Every v1 case against a binary; one PASS/FAIL/NOT_RUN line per case, then SUMMARY:
BIN=path/to/ollm DATA=data WORK=scratch-v1-oracle sh tests/omegallm/v1-oracle.sh
```

`selftest-v1` checks:

- known answers for the chunk rule, an overlapping count ((a,a) = 2 in `aaa`), the tie rule and exit 28;
- that rank-order encoding equals applying the merges in sequence;
- `decode(encode(text)) == text`;
- an `OLLMBPE1` round trip with prefix use, and exit 26 for a corrupted hash;
- the CK02 round trip;
- that a G = 2 gradient equals the G = 1 gradient within the tolerance.

`v1-oracle.sh` reads `DATA/TinyStoriesV2-GPT4-valid.txt` and runs everything on `CORE` (default 8) at nice 19, the script itself included. Its cases:

- Tokenizer (§9.2), all byte-exact:
  - prep;
  - a V = 512 fit on TRAIN, and a V = 300 fit with MAXBYTES 1000000;
  - the tie known answer `ab cd ef\0ab cd ef\0` at V = 261, whose merges must be (32,99) (32,101) (97,98) (256,100) (257,102). This is checked even without BIN.
  - V = 262 on the same text → 28 with no file left; MAXBYTES with no 0 → 21;
  - an edge text: a run of more than 64 letters, UTF-8, doubled spaces, tabs and CR;
  - encodings at V = 512 and V = 300 of TRAIN and HELD; `bpedec`; and `decode(encode(TRAIN)) == TRAIN`;
  - the altered-pair negative control: merge 100 is replaced and the file rehashed, and the tokens must change;
  - exits 26 (hash), 27 (V over the merges, and `bpeenc` at V = 256), 21 (odd token file) and 25 (token ≥ V).
- Model (§9.3 to §9.5), small config `V=300 T=8 D=16 H=2 F=32 L=2 B=4 S=5 TOTAL=50 LRMICRO=3000`, data = the V = 300 encoding of TRAIN:
  - `init` at G = 2, G = 4 and with no G (CK01), bit for bit;
  - G = 3 → 12, and each of the seven shapes one over its maximum → 12;
  - `grad` at OFFS 0, 777777, 5000000, 13000000 for G = 2 and G = 4: the G line, then the gradient within the tolerance;
  - a 20-step chain, one `train` call per step from the binary's own checkpoint: T lines exact and the checkpoint within the tolerance at every step;
  - one-process 20-step runs with K = 1 and K = 2: byte-identical to each other and to the chain, and their T lines equal the referee's own 20-step run;
  - K = 3 and K = 0 → 29;
  - `eval` W = 4 with merges512 on the V = 300 HELD encoding, exact;
  - `eval` and `sample` without MERGES at V = 300 → 2; W too big → 23;
  - `sample` at TEMPMILLI 0 and 800, compared byte for byte;
  - data refusals: odd → 21, shorter than T + 1 → 20, a token ≥ V inside a read row → 25 (and exit 0 with a gradient when the bad token is in no row read), an offset ≥ N − T → 22, an OFFS file of the wrong size → 21.
  - With `V0BIN` set: a V = 256 CK01 from the v1 binary equals the v0 binary's, at init and after 20 steps (§9.4).
- With `EXT_MERGES EXT_V EXT_TEXT EXT_TOK` set: the referee encodes `EXT_TEXT` and compares the result with the product's `EXT_TOK` (the Tok lane's merges4096 and held.tok check).

The referee's own exit code is checked even without BIN. A referee that refuses where the contract expects success is a FAIL, not a NOT_RUN.

### Tolerance

§9.3 (amended) sets these comparison rules:

- the model is checked at the v0 tolerance above, entry by entry, err ≤ 10⁻⁹;
- init is compared bit for bit;
- the printed micro integers and the CK02 header must match exactly;
- tokenizer outputs must be byte-identical.

The longest reduction behind any entry in the small config is far below the 4096 terms the v0 bound assumes:

- B·T = 32 positions;
- the inner dimensions D = 16 and F = 32;
- a softmax over V = 300;
- G − 1 block additions.

So the W2 bound carries over unchanged.

`sample` and `eval` are compared byte for byte. That goes beyond §9.3; a mismatch there is reported with the first differing byte.

### Negative controls

`OLLM_ORACLE_MUTANT=NAME`, or `MUTANT=NAME` for the script, plants a defect in the referee. With an honest product, each mutant must produce FAIL lines.

| Mutant | Defect | Cases that FAIL |
|---|---|---|
| `tiemaxa` | ties go to the largest a | referee-selftest-v1, fit-tie, fit-tie-kat, fit-edge, enc-edge |
| `chunk63` | long chunks are cut into 63-byte pieces instead of 64 | referee-selftest-v1, fit-edge, enc-edge |
| `blockscale` | block gradients are scaled by 1/(T·R) instead of 1/(T·B) | referee-selftest-v1, grad-g2, grad-g4, data-lazy |
| `bpbv0` | eval at V > 256 prints v0's loss/ln 2 instead of the §7.1 bits per byte | eval-w4-bpb |

`blockscale` passes the train cases. Adam's update m̂/(√v̂ + ε) does not change when the gradient is scaled, apart from ε. So a gradient-scale defect is caught by `grad`, not by `train`.

Reversing the order in which blocks are summed (`blockrev`) changes the result only at rounding level. It is invisible within the tolerance, so it is not a mutant. Only .om against .om comparisons, which are bit-exact (§9.4 K identity), can catch it.

### Readings

These are the referee's literal readings of points that CONTRACT-V1 leaves implicit:

- MAXBYTES ≥ the text length still cuts back to the last 0.
- The merges loader checks the hash (26) before V (27). `bpeenc` with V ≤ 256 loads first, then exits 27.
- `bpefit` with V outside 257..4096 exits 2. This is unspecified and not tested.
- At V = 256, `eval` and `sample` accept an extra MERGES argument and ignore it. `sample` at V = 256 is v0's (context 4096, no merges).
- Data checks: an odd file exits 21. N < T + 1 exits 20. The offset check (22) comes before the token check, and tokens ≥ V are checked lazily (25), only in the rows actually read.
- The v1 `prep` is v0's `prep`. Its outputs are byte-identical to `data/train.bin` and `data/held.bin`.

### Measured

All runs below were on GB10 Grace core 8 (Cortex-X925), at nice 19, using `/usr/bin/time`.

| Step | Wall time | Peak RSS | Output |
|---|---|---|---|
| `ollm prep` of the valid text | 0.09 s | | `P 27630 24867 2763 19883834 2220914` |
| `ollm bpefit` TRAIN V = 512 | 0.94 s | 145 MB | `M 512 13055 4975460 19883834` |
| `ollm bpeenc` TRAIN V = 512 | 1.06 s | | `K 19883834 8320463` |
| the whole `v1-oracle.sh`, with the referee itself as BIN | 21.5 s | 788 MB | `SUMMARY pass=53 fail=0 not_run=1` |

In the full-script run, the one NOT_RUN case is `v0-v1-ck01`, which needs `V0BIN`.
