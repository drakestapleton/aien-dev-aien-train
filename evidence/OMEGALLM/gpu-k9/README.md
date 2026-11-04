# GB10 kernels k9: ReLU fused into the FFN GEMM epilogues (aien-train#52)

k9 removes the two elementwise ReLU kernels (`gr.om` RELUF id 17 and RELUB id 18) and does their work in
the GEMM epilogues that produce or consume the same tensors (`gk.om` `gkepi`, `gkepi64`, `gkquad64`):

- ep 1 (ids 25 for the 32×32 GEMM, 56 for the 64×64 GEMM; operand modes ma 1 mb 0, the FFN W1 forward
  `ggxw`) stores C = FP as before. It also stores Y = FP > 0 ? FP : 0 to a second pointer.
- ep 2 (ids 26 and 58; ma 1 mb 1, the FFN dF backward `ggxwt`) loads FP from the second pointer and
  stores C = FP > 0 ? C : 0.

`gkope ep y` arms the next `gkmm` (arg words 30/31, arg count 32). `gkepok` makes `gkmm` refuse any
other combination of ep, operand modes or beta with `nverr` -22. The select is the same `FSETP.GT` vs
RZ plus `FSEL` that RELUF/RELUB used, so NaN still maps to 0. `gg.om` `ggffn` / `ggbffn` call `gkope`
in place of `ggew 17/18`. FP (arena `l 10`) is still written, so the `gcmp2` FP mask check is unchanged.
Mutant m (`--mutant m`) moves from `gr.om` to `gk.om`: the ep 2 threshold becomes 2^-10 while the forward
and FP stay unchanged.

Status: EXERCISED on one GB10, window `20261102T164003Z-8a32e1`, `--gb10 shared --quiet none`.
`spark-window` printed "quiet machine" at close, but the quiet lock was not taken, and the load average
was 1.60 at open and 2.52 at close (`open.json`, `close.json`). Timings are non-quiet. Not QUALIFIED.
Flash-style attention (about 41.7 ms/step in the k8 profile) is deferred to a later round.

## Setup

- omc 2c824805… (omega-mv e5b32567). Binaries: `build.txt`. This commit's tree rebuilds the window's
  P (89ce7107…), PT (2ce7fd6e…) and PM (73d45399…) byte for byte. Only a `gk.om` note changed after the
  window. The baseline Q is the k8 product 0b701583… (`../gpu-k8/`). `srcdiff-q-to-p.txt` is the 366-line
  diff of the concatenated sources (Q 60db63c0… → P fc8a1e2e…).
- `prereg.txt` was written at 16:39:52Z, `prereg.sha256` at 16:40:01Z, and the window directory was
  created at 16:40:03Z. `prereg.sha256` hashes the prereg (abe0b43c…). `run.sh` (16:39:21Z, unchanged)
  hashes to c34ecf6a…. That hash was taken after the window, from the unmodified file. In `win-k9.txt`,
  `open.json` and `close.json` the home prefix is replaced by `~/`.
- Odd shape: `ollm init ck-odd.bin 256 32 64 2 96 2 3 7 100 1000` (sha 7ac2a238…, not committed) gives
  R = B T = 96 and F = 96. `gktile` therefore picks 32, and the FFN GEMMs use ids 25/26. The parity and max
  shapes use 56/58.
- Static checks (`disasm-parity.txt`, `disasm-max.txt`, rc 0, no GPR LOW): slots 17 and 18 are empty.
  Slots 25/26 have max R101, need 104, declared 104. Slots 56/58 have max R158, need 161, declared 168.
  All GEMMs have SMEM target 17. Slots 25/26 are 8832 bytes (2/3: 7776); 56/58 are 20176 (42/46: 15984).

## Gates (all as pre-registered)

| run | expected | observed |
|---|---|---|
| `gc2-small-s3-P` | k8 GC2 line, PASS | `GC2 84288 177 177 3815 211 7629 1 0 0 194221 0 5529261 5529261 * 0`, PASS rc 0 |
| `gc2-max-s7-P` | k8 GC2 line, PASS | `GC2 7409920 159783 758 122070 450 61035 6 3 358192 1557866 0 8339291 8339291 * 0`, PASS rc 0 |
| `gc2-odd-s3-P` vs `-Q` | P PASS; fields 1-13, 15 equal to Q | both `GC2 76096 237 237 5722 187 5722 1 0 0 171373 0 5520714 5520714 * 0`, PASS rc 0 |
| `ga-max-P` | `GA 7409920 59554 4021923359 14807 125 15259 * 2841667` | equal, GACMP PASS rc 0 |
| `ge-max-9000-P` | E 9000 2243 1445466 539226 | equal, rc 0 |
| `ge-max-30000-P` | E 30000 2243 1338156 499194 | equal, rc 0 |
| `t200-Q`, `t200-P` | T 9200 1508182, `ck_after` ec4a8c21… | both equal, rc 0 |
| `gc2-small-s3-PT`, `gc2-max-s7-PT` | FAIL rc 47 | FAIL rc 47 |
| `gc2-max-s7-PM` | FAIL rc 47 | FAIL rc 47 (field 2 7388459) |
| `gc2-odd-s3-PM` | FAIL (controls the 32×32 ep 2 path) | FAIL rc 47 (field 2 16792069) |
| `gc2-small-s3-PM` | reported | FAIL rc 47 (field 2 25987030) |

P is bit-identical to k8 over 200 training steps: the checkpoint and the loss line are the same.

## Speed

Pre-registered rule: ADOPT if the gates hold and the largest P summed GPU wait (GT field 9) is below the
smallest Q over three rotated rounds (Q P / P Q / Q P, `gprof 3` from rung 6 `ck30000`). GT covers the
3 steps plus 64 ZERO probe launches, which both arms share. Launches: Q 1021 = 3·319 + 64 and
P 973 = 3·303 + 64.

| round | Q GT wait / 3 (ms) | P GT wait / 3 (ms) |
|---|---|---|
| 1 | 143.62 | 133.42 |
| 2 | 146.22 | 133.60 |
| 3 | 143.84 | 133.60 |

Max P is 400810630 ns and min Q is 430865863 ns, so k9 is ADOPTED. The means are 144.56 and 133.54 ms/step,
which is −11.02 ms/step (−7.62%). The pre-registered model predicted −8.49 to −14.15 ms/step
(WolframLanguageEvaluator; inputs in `prereg.txt`). t200 wall: Q 32.672 s, P 30.762 s, ratio 0.9415.

Last profiled step, per-id GP wait (ms; Q ids 42+17 vs P 42+56 for the W1 forward plus ReLU, Q 46+18 vs
P 46+58 for the dF backward plus mask):

| round | Q fwd | P fwd | Q bwd | P bwd | Q step | P step |
|---|---|---|---|---|---|---|
| 1 | 20.12 | 16.03 | 38.25 | 32.29 | 143.78 | 133.29 |
| 2 | 21.22 | 17.38 | 40.83 | 32.67 | 151.18 | 135.49 |
| 3 | 20.42 | 16.80 | 37.56 | 32.12 | 142.77 | 134.14 |

The forward group is 18.7% smaller and the backward group 16.8% smaller (means). The fused 64×64
kernels cost 1.804 ms (56) and 2.295 ms (58) more than the plain GEMM wait they absorb, which is the drop
in ids 42 and 46 from Q to P. Removed against that: RELUF 5.886 ms and RELUB 8.264 ms. These are round-1
values, and the split is by subtraction because Q has no separate W1/dF GEMM id.

All arithmetic: WolframLanguageEvaluator over the receipt values (group sums, means, ratios, ns→ms).
