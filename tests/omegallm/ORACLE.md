# Omega LLM v0 oracle

`oracle.py` is a referee for `docs/omegallm/CONTRACT.md`. It uses only the Python 3 standard library (`math.exp`, `math.log`, `math.sqrt` on f64 floats; no numpy). It was written from the contract alone, without reading `native/omegallm/*.om`. It is for verification only and is never part of the build.

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
