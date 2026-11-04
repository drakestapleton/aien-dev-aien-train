# Omega LLM v0 contract (aien-train#52)

The proof of concept is a byte-level decoder-only transformer, trained from random initialization in
seeded `.om` on the Spark Grace CPU, single-threaded, with no GPU. This file fixes the model, the data
handling, the file formats and the command line. Two separate implementations must agree with it:
the `.om` product (`native/omegallm/`) and the Python-stdlib referee (`tests/omegallm/oracle.py`,
verification only, never in the build).

Compiler: omega-mv `e5b32567a7aff3ce594e3254a622a846a6cd190b`, `seed/out/omc` sha256
`2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f` (aarch64 static ELF output).

## 1. Shapes

The dimensions are run-time values stored in the checkpoint header. Arrays are fixed globals sized
for the maxima below, and the code refuses a header that exceeds them.

| Name | Meaning | v0 | Small (oracle) config | Max |
|---|---|---|---|---|
| V | vocabulary (bytes) | 256 | 256 | 256 |
| T | context length | 64 | 8 | 64 |
| D | model width | 64 | 16 | 64 |
| H | heads, head size E = D/H | 4 | 2 | 8 |
| F | FFN width | 256 | 32 | 256 |
| L | layers | 2 | 2 | 4 |
| B | sequences per step | 16 | 2 | 16 |

The v0 parameter count is P = V·D + T·D + L·(4D² + 2DF + 2D) + D = 119,104 (Wolfram:
`params[V_,T_,D_,F_,L_]:=V D+T D+L(4D^2+2D F+2D)+D; params[256,64,64,256,2] -> 119104`).

## 2. Parameter layout

All values are f64. In memory and in files the parameters form one flat vector in this order. A
matrix written `[R][C]` is row-major, and `y = x · W` means `y[c] = Σ_r x[r] · W[r][c]`.

1. `wte[V][D]` token embedding (also the output head: weights tied).
2. `wpe[T][D]` position embedding.
3. For each layer l = 0..L-1, in this order:
   1. `g1[D]`;
   2. `wq[D][D]`, `wk[D][D]`, `wv[D][D]`, `wo[D][D]`;
   3. `g2[D]`;
   4. `w1[D][F]`, `w2[F][D]`.
4. `gf[D]` final norm gain.

## 3. Forward pass for one sequence

The input is bytes `x[0..T-1]` with targets `y[0..T-1]`.

1. `h[t] = wte[x[t]] + wpe[t]`.
2. For each layer:
   1. `a = rms(h[t], g1)`, where `rms(v, g)[i] = v[i] / sqrt(mean_j(v[j]^2) + 1e-5) · g[i]`.
   2. `q = a·wq`, `k = a·wk`, `u = a·wv`. Head n uses columns `n·E .. n·E+E-1`.
   3. For each head, `s[t][j] = (q[t]·k[j]) / sqrt(E)` for j ≤ t (causal). Then
      `p[t] = softmax_j(s[t])`, computed with the max subtracted, and `o[t] = Σ_j p[t][j] · u[j]`.
   4. `h[t] += o[t]·wo`.
   5. `b = rms(h[t], g2)`; `h[t] += relu(b·w1)·w2`.
3. `z = rms(h[t], gf)`; logits `ℓ[t][c] = z · wte[c]`.
4. The loss for one sequence is `(1/T) Σ_t −log softmax(ℓ[t])[y[t]]`. The step loss is the mean over
   the B sequences, in natural log. Bits per byte = loss / ln 2.

`exp`, `log` and `sqrt` must be first-party `.om`; `sqrt` may use the compiler intrinsic.
`exp`/`log` accuracy must be checked against Wolfram values with a stated maximum relative error.

## 4. Data

- `prep IN TRAIN HELD`:
  - Split IN on the literal bytes `<|endoftext|>`.
  - Trim ASCII whitespace (9, 10, 13, 32) from both ends of each story, and drop any story that is
    then empty.
  - Number the remaining stories i = 0,1,…. Story i goes to HELD when `i mod 10 == 9` and to TRAIN
    otherwise.
  - Each story is written as its bytes followed by one byte 0 (end of story).
- Batch for step s (s counts from 0) with run seed S: for b = 0..B-1,
  `o = splitmix64(S xor (s·B + b)·0x9E3779B97F4A7C15) mod (N − T)`, where N is the TRAIN length.
  Then `x = data[o .. o+T−1]` and `y = data[o+1 .. o+T]`.
  - splitmix64 is the standard function: `z += 0x9E3779B97F4A7C15`;
    `z = (z ^ z>>30)·0xBF58476D1CE4E5B9`; `z = (z ^ z>>27)·0x94D049BB133111EB`; `z ^ z>>31`.
  - It is applied once to the given 64-bit input. All arithmetic is mod 2^64.
- Held-out evaluation uses W windows at offsets `0, T, 2T, …, (W−1)T` (non-overlapping), with the
  same x/y rule.

## 5. Training

- Init from seed S. For flat parameter index i, `r_i = (splitmix64(S + i) >> 11) · 2^-53`, a value in
  [0,1); S + i wraps mod 2^64.
  - Every matrix entry (`wte`, `wpe`, the weights) is `(2·r_i − 1) · 0.034641016151377546`. This is
    uniform with a standard deviation of 0.02 (Wolfram: `N[0.02 Sqrt[3]] -> 0.034641016151377546`).
  - `wo` and `w2` are also multiplied by `1/sqrt(2L)`.
  - Every gain (`g1`, `g2`, `gf`) is 1, and its draw is skipped. Index i still counts it.
- Optimizer: Adam with β1 = 0.9, β2 = 0.99, ε = 1e-8, no weight decay, bias-corrected.
  - Gradients are clipped to a global L2 norm of 1.0 before the update.
  - The learning rate at step s is `lr·(s+1)/100` for s < 100. After that it is
    `lr·(1 − 0.9·(s−100)/max(1, TOTAL−100))`, a linear decay to 0.1·lr. The update uses the
    pre-increment step s and the bias corrections `1−β1^(s+1)`, `1−β2^(s+1)`.
- One step means: compute the batch, the forward and backward passes and the clip, update the
  parameters, then increment `step`.

## 6. Checkpoint `OLLMCK01`

All integers are u64 little-endian and all floats are f64 little-endian.

| Offset | Field |
|---|---|
| 0 | magic `OLLMCK01` (8 bytes) |
| 8 | V, T, D, H, F, L, B (7 × u64) |
| 64 | seed S, step, TOTAL, lr (f64 bits), count P (u64) |
| 104 | FNV-1a 64 of every byte from offset 112 to the end |
| 112 | params[P], m[P], v[P] (f64) |

A loader refuses a bad magic, a short file, a P that disagrees with the shapes, a shape over the
maximum, and a hash mismatch, each with its own exit code below 100. Saving writes `CK.tmp`, then
renames it to `CK`. Resuming from a saved checkpoint must give byte-identical results to an
uninterrupted run.

The gradient file `OLLMGR01` uses the same header with the step field holding the batch size used.
Its payload is the gradient `grad[P]` only, and the hash covers that payload.

## 7. Command line (`ollm`)

| Command | Effect | stdout |
|---|---|---|
| `prep IN TRAIN HELD` | §4 | `P stories train_stories held_stories train_bytes held_bytes` |
| `init CK V T D H F L B SEED TOTAL LRMICRO` | writes a step-0 checkpoint; lr = f64(LRMICRO)/1000000.0 (one division, reading A8) | `I P` |
| `grad CK DATA OFFS OUT` | OFFS is B u64 LE offsets. Writes the loss gradient at the checkpoint parameters (no update) | `G loss_bits_hex loss_micro` |
| `train CK TRAIN UNTIL EVERY` | trains to step min(UNTIL, TOTAL), saving every EVERY steps and at the end | `T step loss_micro` once per EVERY steps (the loss of that step) |
| `eval CK HELD W` | §4 held-out | `E step W loss_micro bpb_micro` |
| `base TRAIN HELD` | unigram and bigram add-one byte models fit on TRAIN, scored on HELD over every byte transition | `B uni_bpb_micro bi_bpb_micro` |
| `sample CK SEED N TEMPMILLI PROMPT` | generates up to N bytes after PROMPT (an argument string), stopping at byte 0. TEMPMILLI 0 = argmax; otherwise the temperature is TEMPMILLI/1000, sampling via splitmix64(SEED) (§8.3) | the generated bytes |

`*_micro` means round(value × 10^6) printed in decimal (reading A7). `loss_bits_hex` means the 16
lowercase hex digits of the f64 bits. Exit codes: 0 ok; 2 usage; 10–15 checkpoint refusals (10 short
file, 11 bad magic, 12 a shape zero or over the maximum, D mod H ≠ 0, or TOTAL over 999999, 13 P
disagrees with the shapes, 14 hash mismatch, 15 file longer than 112 + 24·P, the size its header
implies; a file of 5224050 B or more, longer than the largest checkpoint 112 + 24·217664 = 5224048 B
plus the one spare buffer byte, is refused with 15 while it is read, and a file of exactly 5224049 B
is read and then refused by the header checks: 11–13 if the header is also invalid, else 15);
20 data file shorter than T + 1 bytes;
21 data over 2^25 bytes, OFFS not exactly 8·B bytes, or a mathck reference not a whole number of
36-byte lines; 22 an OFFS offset with o + T ≥ N; 23 eval W = 0 or W·T + 1 > M; 24 prep story over
999999 bytes; 40 gcheck over tolerance; 41 adamck over tolerance; 42 mathck over tolerance; 70 I/O.

## 8. Readings agreed between the two implementations (normative)

These were agreed between the `.om` lane (OllmCore) and the referee (OllmOracle) on 2026-11-01 and
bind both implementations; tests/omegallm/ORACLE.md carries the same list.

### 8.1 A1–A8

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
  - the bigram counts every adjacent TRAIN pair, crossing the 0 separators, and its row
    denominator is the pair-row sum + 256;
  - both are scored on the M−1 HELD transitions, as mean −log2 p.
- A6, `prep` stdout: `P total train held train_bytes held_bytes`, where the byte counts include the
  0 terminators.
- A7, `*_micro`: round half away from zero of the single f64 product v·1e6.
- A7, `train`: prints `T s+1 loss`, using the loss at the pre-update parameters, after the save.
- A8: `lr = f64(LRMICRO)/1000000.0`, a single division. It differs in bits from `LRMICRO·1e-6` for
  some values (for example 5, 10, 15); the division is the contract.

### 8.2 Forward and backward details

- rms(v, g): s = sqrt((Σ v²)/D + 1e-5); y = (v/s)·g.
- Attention score = (q·k)/sqrt(f64 E); softmax subtracts the row maximum before exp.
- Per-position loss = log(Σ exp(ℓ − max)) − (ℓ_y − max), in nats; every sum runs in ascending index
  order.
- relu′(x) = 1 when x > 0 and 0 otherwise, so the derivative at exactly 0 is 0.
- eval `bpb = loss/ln 2` with ln 2 the f64 0.6931471805599453.

### 8.3 sample

The context starts as byte 0 followed by PROMPT and keeps only its last T bytes; each step reads
the logits at the last context position. TEMPMILLI 0 takes the argmax (lowest index on ties) and
consumes no random draw. Otherwise logits are divided by TEMPMILLI/1000, softmaxed with the maximum
subtracted, and u = (out >> 11)·2^−53 with the splitmix64 stream state = SEED, out = mix(state +=
0x9E3779B97F4A7C15), one draw per generated byte. The byte is the smallest c with
u < p[0] + … + p[c], else the last c with p[c] > 0. A generated byte 0 ends the output and is not
written.

### 8.4 Self-check commands (`.om` only)

`gcheck CK TRAIN` (central differences against the hand gradient, exit 40), `adamck` (Adam on a
constant gradient from zero moments, exit 41) and `mathck REF` (first-party exp/log against a
correctly rounded reference, exit 42) are diagnostics of the `.om` product; the referee does not
implement them.

- gcheck uses the step h = 1e-6 (GCH). An index whose relative error exceeds GCTOL = 1e-3 is measured
  once more at h/4 (GCH2) and keeps the smaller error, because a difference whose step crosses a ReLU
  kink is not a derivative. A wrong hand gradient fails at both steps. Output ends with
  `C count maxrel_bits_hex maxrel_e9 worst_index retries`.
- mathck fails (exit 42) when REF has no `e` line or no `l` line, because a check that checks
  nothing must not pass.
- The smoke and v0 runs use LRMICRO = 3000 (lr 3e-3). This contract fixes the reading of LRMICRO,
  not its value.

## 9. Platform units and the UEFI job file

The shared units (`math data model adam ckpt cli`) do no I/O of their own. They call one platform
unit, concatenated last, which defines `main`, `oargc`, `oargr`, `oflush`, `ocwrite`, `ocread`,
`odread`, `owflush`, `owopen`, `owclose` and `ooffrd`, and calls `ocmd` (cli.om) once per command.

| Unit | Target | Arguments | Output |
|---|---|---|---|
| `lio.om` | `aarch64` (Linux), `x86linux` | the process command line | stdout; checkpoints written to `PATH.tmp` then renamed |
| `eio.om` | `x86efi` (UEFI application) | one command per line of `\OLLM\JOB.TXT` | the console and `\OLLM\OUT.TXT`; checkpoints written in place |

`eio.om` reads every file from the volume the application was loaded from. `\OLLM\JOB.TXT` (at most
65535 bytes) holds one command per line without the program name; CR before LF is dropped, empty
lines and lines starting with `#` are skipped, tokens split on space or tab, and a token in double
quotes may hold spaces (at most 63 tokens, else exit 2). A missing or longer JOB.TXT prints
`OLLM efi JOB.TXT?`, waits for a key and exits 2. Otherwise `\OLLM\OUT.TXT` is recreated and receives,
byte for byte, what the console shows (the console shows bytes outside 9, 10, 13 and 32–126 as `?`):

```
OLLM efi <JOB.TXT bytes>
ID cpu=<brand> fw=<vendor> fwrev=<revision> smbios=<manufacturer>/<product>/<version>
> <job line>
<the command's stdout, as on Linux, plus LF when it does not end in LF>
J <wall milliseconds>
...
OLLM DONE <jobs> <wall milliseconds>
```

The application then waits up to 300 s for a key and returns 0. A command that refuses (`exit N`)
ends the application at once with status N, as on Linux; OUT.TXT then ends with the output flushed
so far. This needs the `x86efi` compiler of omega-mv#1015 (`5ce9ecaa`): its `exit` flushes and closes
the open `efi 12` file before returning to the firmware, so the bytes written before the refusal are
on the volume (`evidence/OMEGALLM/efi/ckbad/`: a refused checkpoint, and OUT.TXT equal to the Linux
body). Differences from `lio.om`: there is no rename, so a refused or interrupted checkpoint write
can leave a partial file; a path longer than 255 bytes is an I/O refusal (70). The banner
`OLLM efi <JOB.TXT bytes>` is first, the identity line `ID ...` is second, exactly one `J <ms>`
follows each job, and `OLLM DONE <jobs> <ms>` is last. Those four are wall clock, the job-file size
or the machine and are not part of the body comparison. Every other OUT.TXT line, including a line
shaped like `J n` or `OLLM DONE a b` inside a job, must equal what a Linux build prints for the same
lines (`tests/omegallm/efi-ref.sh`, checked in that order by `tests/omegallm/efi-check.sh`).

The identity line is read from the firmware with `efi 14` (omega-mv PR #1022 commit `ab572d8f2840`,
branch `feat/x86efi-ident`):
`cpu=` is the CPUID brand string (leaves 0x80000002–0x80000004) without leading or trailing spaces
and NULs; `fw=` is the SystemTable FirmwareVendor, one byte per UCS-2 code unit; `fwrev=` is the
SystemTable FirmwareRevision as 8 lowercase hex digits; `smbios=` is the SMBIOS type 1 (System
Information) Manufacturer, Product Name and Version strings, found through the SMBIOS 3 entry point
when the firmware publishes one, else the SMBIOS 2 one. A field the firmware does not provide is `-`;
a byte outside 32–126 is `?`. `efi 14` copies the table's first 64 KiB, so the serial number and UUID
are in memory, but they are never printed, and no MAC address is printed. The prefix is `ID`, not
`M`, so no identity line shares a prefix with mathck's `M e` and `M l` lines. Every SMBIOS read stays
below the copied length: a string number past the structure's string set, a type 1 field or string
cut off at that length, and a type 1 structure starting beyond it print `-`, and a brand string of
only blanks or NULs prints `cpu=-` (`tests/omegallm/efi-ident.sh EFI OUTDIR` boots these five cases
under QEMU; receipts in `evidence/OMEGALLM/efi-ident/`). Under QEMU 8.2 with Ubuntu OVMF
and `-smbios type=1,manufacturer=OmegaTest,product=IdentBox,version=7.1` the line is
`ID cpu=QEMU TCG CPU version 2.5+ fw=Ubuntu distribution of EDK II fwrev=00010000
smbios=OmegaTest/IdentBox/7.1` (one line).
