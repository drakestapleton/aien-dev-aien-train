# Omega LLM v1 contract (rung 3)

v1 extends the v0 contract (`CONTRACT.md`, which stays normative for everything this file does
not change). It adds a byte-pair tokenizer written in `.om`, larger shapes, token data files of any
size, a gradient block rule that makes multi-process training bit-reproducible, and a checkpoint
that records that rule. The same two implementations must agree with it: the `.om` product
(`native/omegallm/`) and the Python-stdlib referee (`tests/omegallm/oracle.py`, verification only).

Compatibility rule: every v0 command, file and test keeps its exact bytes. A v0 checkpoint
(`OLLMCK01`, V = 256) trains, evaluates and samples exactly as before. The only v0 statements that
change are the size limits of §1 and the refusal boundaries that follow from them (exit 15 and 21).

## 1. Shapes

| Name | Meaning | v0 max | v1 max |
|---|---|---|---|
| V | vocabulary: 256 = bytes, more = BPE tokens 0..V−1 | 256 | 4096 |
| T | context length | 64 | 256 |
| D | model width | 64 | 256 |
| H | heads, D mod H = 0 | 8 | 16 |
| F | FFN width | 256 | 1024 |
| L | layers | 4 | 8 |
| B | sequences per step | 16 | 64 |
| G | gradient blocks per step, G ≥ 1 and B mod G = 0 (§5) | 1 | B |

At the maxima P = 7,409,920 and a checkpoint is 112 + 24·P = 177,838,192 B (Wolfram:
`params[V_,T_,D_,F_,L_]:=V D+T D+L(4D^2+2D F+2D)+D; params[4096,256,256,1024,8] -> 7409920`;
`112+24*7409920 -> 177838192`). A CK02 file is 8 B longer (§6). Every process must stay under 2 GB
resident at the maxima.

## 2. Tokenizer

Bytes are classed: A(c) holds for c in 48–57, 65–90, 97–122 and c ≥ 128. Everything else (space,
newline, punctuation, the 0 story terminator) is not A.

### 2.1 Chunks

A text of n bytes is cut into chunks left to right. At position i:

1. if A(c_i): the chunk is the maximal run of A bytes starting at i;
2. else if c_i = 32 and i+1 < n and A(c_{i+1}): the chunk is byte 32 plus the maximal run of A
   bytes starting at i+1;
3. else the chunk is the single byte c_i.

A chunk longer than 64 bytes is cut into pieces of 64 bytes from its start (the last piece may be
shorter); each piece is a chunk. Merges never cross a chunk boundary, so byte 0 is always token 0.

### 2.2 Fit (`bpefit`)

The fit text is TEXT, or its first MAXBYTES bytes cut back to just after the last byte 0 inside
them (whole stories only; no byte 0 inside them is exit 21). Chunk types are the distinct chunk byte
strings with their counts. Starting from tokens 0..255 = bytes, merge k = 0, 1, …, V−257:

- the count of a pair (a, b) is Σ over chunk types of count × (number of positions j with
  tok[j] = a and tok[j+1] = b) in that type's current token string; overlapping occurrences count
  (`aaa` holds (a, a) twice);
- the chosen pair has the largest count; ties go to the smallest a, then the smallest b;
- if no pair has a count of at least 1, the fit refuses with exit 28 and writes nothing;
- the new token is 256 + k; every chunk type replaces its occurrences of (a, b) left to right,
  without overlap.

### 2.3 Merges file `OLLMBPE1`

| Offset | Field |
|---|---|
| 0 | magic `OLLMBPE1` |
| 8 | V (u64 LE) |
| 16 | FNV-1a 64 of every byte from offset 24 to the end (u64 LE) |
| 24 | V − 256 pairs, each `a` then `b` as u16 LE |

A loader refuses with exit 26 a bad magic, a V under 257 or over 4096, a length other than
24 + 4·(V − 256), a hash mismatch, and a pair whose a or b is not below 256 + k for merge k. A
merges file of V_m merges may be used at any vocabulary V with 256 < V ≤ V_m: only its first
V − 256 merges apply. V > V_m is exit 27.

### 2.4 Encode and decode

- Encode cuts the text into chunks (§2.1) and, for each chunk, applies merges k = 0, 1, …, V−257 in
  order, each left to right without overlap. The tokens of all chunks are concatenated. (An
  implementation may cache chunk encodings; the result is defined by this rule.)
- Token files are u16 LE, two bytes per token. A file of odd length is exit 21; a token ≥ V met by
  any command is exit 25.
- Decode expands a token t ≥ 256 into decode(a) followed by decode(b) for its merge; t < 256 is the
  byte t. Decoding the encoding of any text returns that text exactly.

## 3. Data

- `prep IN TRAIN HELD` reads IN as a stream. The v0 rule is unchanged (split on `<|endoftext|>`,
  trim, drop empty, i mod 10 = 9 to HELD, byte 0 after each story, a story over 999999 bytes is exit
  24); only the 2^25-byte limit on IN is removed. Its output files may exceed 2^25 bytes.
- A data file is bytes when V = 256 and u16 LE tokens when V > 256. N is its length in tokens. It
  may be of any size; it is read through positioned windows, never loaded whole. N < T + 1 is
  exit 20. The v0 exit 21 for data over 2^25 bytes no longer applies.
- The batch rule (§4 of v0) is unchanged with N in tokens: x = data[o .. o+T−1], y = data[o+1 ..
  o+T].
- Held-out windows are unchanged (offsets 0, T, …, (W−1)·T in tokens; W·T + 1 > N is exit 23).

## 4. Model

Unchanged from v0 §2–§3 and §8.2, with V tokens instead of 256 bytes. The tied embedding is
`wte[V][D]`.

## 5. Gradient blocks

The B sequences of a step form G blocks of R = B/G consecutive sequences; block j holds sequences
j·R .. j·R + R − 1.

- Block gradient: a buffer zeroed, then for each sequence of the block in ascending b the v0
  sequence gradient is accumulated exactly as v0 accumulates a batch (`obwd b sc`), with the same
  scale sc = 1/(T·B) (computed as v0 computes it).
- Step gradient: GRD = block 0; then for j = 1..G−1, GRD[i] = GRD[i] + block_j[i] for every i in
  ascending order. For G = 1 this is exactly v0's gradient.
- Step loss: the per-sequence losses `ofwd b` are summed in ascending b from 0.0 and divided by
  f64(B), exactly as v0, whatever G and K are.
- Clip and Adam are unchanged and act on GRD.

### 5.1 Workers (`train … K`)

K processes compute the blocks of a step. K ≥ 1, K ≤ G and G mod K = 0; otherwise exit 29. Worker
w (0 ≤ w < K) computes blocks w·G/K .. (w+1)·G/K − 1, each into its own buffer, and returns their
f64 bits and its sequences' losses; the parent combines blocks in ascending j and losses in
ascending b (§5). The checkpoint after any number of steps must be byte-identical for every valid K.
K > 1 needs process creation (`fork`, `pipefds`, `waitpid`), so it is a platform-unit service:
`lio.om` provides it; `eio.om` refuses K > 1 with exit 29.

Cost when G/K > 1 (not a correctness matter; noted 2026-11-04 from reading `lio.om`, not measured).
A worker writes each block to its pipe as soon as it is computed, and the pipe holds far less than
one block (8·P bytes), so the worker cannot start its next block until the parent reads the
previous one; the parent first computes its own G/K blocks, then reads the workers in ascending w.
With per = G/K and transfer time ignored, a step then takes about per + (K − 1)(per − 1)
block-times instead of per: 3 for G = 4, K = 2; for G = 20, K = 1, 2, 4, 5, 10, 20 give 20, 19,
17, 16, 11, 1. Use K = G (per = 1, the rung-3 setting G = K = 20) for full parallelism.

## 6. Checkpoint `OLLMCK02`

| Offset | Field |
|---|---|
| 0 | magic `OLLMCK02` |
| 8 | V, T, D, H, F, L, B (7 × u64) |
| 64 | seed S, step, TOTAL, lr (f64 bits), count P (u64) |
| 104 | G (u64) |
| 112 | FNV-1a 64 of every byte from offset 120 to the end |
| 120 | params[P], m[P], v[P] (f64) |

`OLLMCK01` stays valid at every v1 shape and means G = 1. `init` writes CK01 when G is omitted and
CK02 when G is given (even G = 1); a saved checkpoint keeps the magic it was loaded with. G = 0, G > B
or B mod G ≠ 0 is exit 12. The v0 refusal codes 10–15 apply to both magics with the header length
of each; the exit-15 file cap moves to the largest v1 checkpoint plus one spare byte. `OLLMGR01`
keeps its v0 layout (header from offset 0 to 111, payload at 112) for either checkpoint magic.

## 7. Command line changes

| Command | Effect | stdout |
|---|---|---|
| `bpefit TEXT MERGES V [MAXBYTES]` | §2.2; writes MERGES.tmp then renames | `M V types chunks fitbytes` (distinct chunk types, total chunks, bytes fitted) |
| `bpeenc MERGES V TEXT TOKS` | §2.4; writes u16 LE tokens | `K bytes tokens` |
| `bpedec MERGES TOKS OUT` | decodes every token (V = the file's V) | `D tokens bytes` |
| `init CK V T D H F L B SEED TOTAL LRMICRO [G]` | as v0; G per §6 | `I P` |
| `train CK DATA UNTIL EVERY [K]` | as v0; K per §5.1, default 1 | as v0 |
| `grad CK DATA OFFS OUT` | as v0, with the gradient of §5 | as v0 |
| `eval CK HELD W [MERGES]` | as v0; MERGES required when V > 256 (missing: exit 2) | `E step W loss_micro bpb_micro` |
| `sample CK SEED N TEMPMILLI PROMPT [MERGES]` | §7.2; MERGES required when V > 256 | the generated bytes |

### 7.1 eval for V > 256

loss is computed exactly as v0 (mean over windows of each window's mean token loss). With
nbytes = Σ over the W·T targets y of the decoded length of y (an integer),
`bpb = ((loss / ln2) · f64(W·T)) / f64(nbytes)`, evaluated in that order, ln2 as in v0 §8.2. For
V = 256 the v0 formula `bpb = loss/ln2` is kept.

### 7.2 sample for V > 256

The context is token 0 followed by the encoding (§2.4, at the checkpoint's V) of PROMPT, keeping its
last T tokens. Each step draws one token by the v0 §8.3 rule over V tokens (one random draw per
generated token, none for TEMPMILLI 0). A generated token 0 ends the output and is not written;
any other generated token writes its decoded bytes. N counts tokens. PROMPT is at most 4000 bytes
(longer: exit 2).

### 7.3 Exit codes added

21 also: odd token file length, MAXBYTES prefix with no byte 0; 25 token ≥ V; 26 merges file
refused; 27 V over the merges file's V, or V ≤ 256 given to `bpeenc`; 28 fit ran out of pairs;
29 bad K.

## 8. Interface between `bpe.om` and the model units

`bpe.om` is a shared unit (no I/O of its own beyond the platform calls). The model and cli code use
only these functions of it:

- `fn obload ai ulong v ulong to void`: load the merges file named by argument ai for vocabulary v
  (refusals 26/27 as §2.3); after it, the two functions below are valid.
- `fn obtlen t ulong to ulong`: decoded byte length of token t.
- `fn obtput t ulong to void`: append the decoded bytes of token t to stdout.
- `fn obprompt ai ulong to ulong`: encode the bytes of argument ai into the global `obtk`
  (ulong, capacity 4096) and return the token count.

## 9. Required checks

1. v0: every existing `tests/omegallm/*` check passes unchanged (except the exit-15/21 boundary
   cases, which move to the v1 caps), on aarch64 and x86linux, and the x86efi `efi-check`.
2. Tokenizer: merges and token files byte-identical to the referee for V = 512 fitted on
   `TinyStoriesV2-GPT4-valid.txt` prepped TRAIN, and decode(encode(text)) == text on the full prepped
   training text. Negative control: a merges file with one pair altered must change the tokens.
3. Model, against the referee, with the v0 standard of `tests/omegallm/ORACLE.md` ("Tolerance"):
   init bit for bit; `grad` and one `train` step per entry within the v0 relative 10⁻⁹ rule; printed
   loss, eval and base micro integers exact; CK02 header fields exact. Config V = 300, T = 8, D = 16,
   H = 2, F = 32, L = 2, B = 4, G = 2. Bit identity of model arithmetic is required only between `.om`
   runs (check 4), not against the referee.
4. Workers: after 20 steps at that config, K = 1 and K = 2 checkpoints are byte-identical. At the v0
   small byte config (V = 256), a CK01 checkpoint trained by the v1 binary equals the v0 binary's
   checkpoint byte for byte after 20 steps.
5. Limits: a shape one over each maximum is exit 12.
