# Omega LLM v2 contract (rung 7)

v2 extends the v1 contract (`CONTRACT-V1.md`, which stays normative for everything this file does
not change, and through it `CONTRACT.md`). It raises two shape maxima so the model can be wider;
nothing else changes. The same two implementations must agree with it: the `.om` product
(`native/omegallm/`, CPU and `TARGET=gb10`) and the Python-stdlib referee
(`tests/omegallm/oracle.py`, verification only).

Compatibility rule: every v0 and v1 command, file and test keeps its exact bytes. The only v1
statements that change are the D and F maxima of §1 and the refusal boundaries that follow from
them (exit 12 for a shape one over a maximum, exit 15 for a checkpoint over the larger image).

## 1. Shapes

| Name | Meaning | v1 max | v2 max |
|---|---|---|---|
| V | vocabulary | 4096 | 4096 |
| T | context length | 256 | 256 |
| D | model width | 256 | 384 |
| H | heads, D mod H = 0 | 16 | 16 |
| F | FFN width | 1024 | 1536 |
| L | layers | 8 | 8 |
| B | sequences per step | 64 | 64 |
| G | gradient blocks per step | B | B |

At the maxima P = 15,833,472, a CK01 checkpoint is 112 + 24·P = 380,003,440 B and a CK02 one
120 + 24·P = 380,003,448 B (Wolfram: `params[V_,T_,D_,F_,L_]:=V D+T D+L(4D^2+2D F+2D)+D;
params[4096,256,384,1536,8] -> 15833472`; `112+24*15833472 -> 380003440`;
`120+24*15833472 -> 380003448`). A file over 380,003,449 B is exit 15 before its header is read.
D = 512 stays out of reach: `params[4096,256,512,2048,8] -> 27394560` exceeds the compiler's
2^24 = 16,777,216 elements per array. Every process must stay under 2 GB resident at the maxima.

## 2. Storage layout (product only)

The product keeps parameters, gradients and Adam moments in f64. A pool that v1 sized 2·P
(gradient: block results in [0, P), the incoming block in [P, 2P); Adam: m in [0, P), v in
[P, 2P)) is now two arrays of OWN = 15,833,472 elements behind accessors (`ogrg/ogrp/ogra`,
`omvg/omvp`, `model.om`). Index i < OWN reads the first array, i ≥ OWN the second at i − OWN, so
every v1 index computes the same value at the same place in the arithmetic. Activations: 15,016,192
f64 at the maxima (Wolfram: `L(8TD+2T+2TF)+10TD+T+TV+TF+4096` at V 4096, T 256, D 384, F 1536,
L 8 -> 15016192); attention probabilities L·H·T² = 8,388,608 f64, unchanged from v1 because H and T
keep their maxima (`8*16*256*256 -> 8388608`).

## 3. GPU path (`TARGET=gb10`)

The warp-per-row RMS kernels (`gpu/gr.om` slots 10 and 11) hold n = D/32 columns per lane in four
register banks. For n ≤ 8 (every v1 shape) the banks stay at R32, R40, R48, R56, so the v1 kernels
are the same instructions. For 8 < n ≤ 12 the banks sit at R72 + n·k (highest R119) and the slots
declare 128 GPRs (highest GPR + 3, rounded up to a multiple of 8). `grall` refuses D > 384. The
`gcmp2` row scratch `ggfs` (`gpu/gg.om`, one f64 per FFN unit) holds F ≤ 1536; at 1024 it trapped
(exit 103, BOUNDS) at the first v2-maximum `gcmp2` (gate window gg-r7g).

## 4. Required checks

1. v0 and v1: every existing `tests/omegallm/*` check passes, with the v1 limit cases moved to the
   v2 boundaries (`v1-oracle.sh`: D 386 and F 1537 are exit 12; D 384, F 1536 init byte-identically
   to the referee).
2. GPU, v1 shapes: a v1 run on the v2 binary reproduces the v1 binary's checkpoint and geval line
   bit for bit.
3. GPU, v2 shapes: `gcmp2` and `gacmp` pass at D 384 / F 1536, and the RMSB mutant r is caught there.
4. `tests/omegallm/gpu-disasm.sh` with `SHAPE="4096 256 384 12 1536 64"` finds no slot LOW.
