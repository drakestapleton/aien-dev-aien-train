# Omega LLM v3 contract (deep-thin, L ≤ 16)

v3 extends the v2 contract (`CONTRACT-V2.md`, normative for everything this file does not change,
and through it `CONTRACT-V1.md` and `CONTRACT.md`). It raises one shape maximum, L, from 8 to 16.
The same two implementations must agree with it: the `.om` product (`native/omegallm/`, CPU and
`TARGET=gb10`) and the Python-stdlib referee (`tests/omegallm/oracle.py`, verification only).

Compatibility rule: every v0, v1 and v2 command, file, output and test keeps its exact bytes. The
only statements that change are the L maximum and the refusal boundaries that follow from it (exit
12 at L 17; exit 15 for a checkpoint over the v3 maximum image). Arithmetic is unchanged: every sum
runs in the same order; only the storage location of a value changes.

## 1. Shapes

| Name | Meaning | v2 max | v3 max |
|---|---|---|---|
| V | vocabulary | 4096 | 4096 |
| T | context length | 256 | 256 |
| D | model width | 384 | 384 |
| H | heads, D mod H = 0 | 16 | 16 |
| F | FFN width | 1536 | 1536 |
| L | layers | 8 | 16 |
| B | sequences per step | 64 | 64 |
| G | gradient blocks per step | B | B |

At the maxima P = 29,995,392; a CK01 checkpoint is 112 + 24·P = 719,889,520 B and a CK02 one
120 + 24·P = 719,889,528 B. A file over 719,889,529 B is exit 15 before its header is read.
Wolfram: `params[V_,T_,D_,F_,L_]:=V D+T D+L(4D^2+2D F+2D)+D; params[4096,256,384,1536,16] ->
29995392`; `112+24*29995392 -> 719889520`; `120+24*29995392 -> 719889528`.
Attention probabilities L·H·T² stay within one array exactly at H 16, L 16:
`16*16*256^2 -> 16777216` = `2^24 -> 16777216`.

Correction to CONTRACT-V2 §1: the out-of-reach wide shape is `params[4096,256,512,2048,8] ->
27402752`, not 27,394,560 as printed there.

The x86efi build keeps the bank-B pools at one element (§2), so it accepts only shapes whose
layout fits bank A (every v2 shape); larger L is refused by `ogeom`.

## 2. Storage layout (product only)

omc refuses a program whose globals exceed 1 GiB (error 23) and any array over 2^24 elements, so
the v3 maximum cannot live in v2's single arrays. Values move into layer-aligned banks; the
virtual index of every value is unchanged, so every v2 shape uses exactly the v2 layout.

- Parameters: bank A `ow` (OWC = 15,833,472) holds wte, wpe, layers [0, LA) and a one-layer
  window; bank B `oww` holds layers [LA, L) and the final gain. `ostw l` copies a bank-B layer
  into the window at the start of `olayf`/`olayb`; `opx` gives the physical index for hot reads.
  With LSTR = 4D² + 2DF + 2D and SB = VD + TD, LA = ⌊(OWC − SB − LSTR − D)/LSTR⌋. At the maximum
  (Wolfram): LSTR `4*384^2+2*384*1536+2*384 -> 1770240`, SB `4096*384+256*384 -> 1671168`,
  LA `Floor[(15833472-1671168-1770240-384)/1770240] -> 7`, bank B `(16-7)*1770240 -> 15932160`.
- Gradient GRD and Adam m, v: a cold store of 3·P f64 (`ocsg/ocsp`), an anonymous mapping of
  `24*29995392 -> 719889408` B on aarch64/x86linux (`lio.om`), global arrays on x86efi
  (`eio.om`). The block buffer BLK is `ogr` [0, OGC) then `ogb` (`29995392-15833472 -> 14161920`).
- Activations: bank A `oa` (OAC = 15,016,192) holds layers [0, LAA) plus two layer windows and the
  temporaries; bank B `oab` the rest. With ASTR = 8TD + 2T + 2TF (`-> 1573376`) and temporaries
  `-> 2429184`, LAA `Floor[(15016192-2429184-2*1573376)/1573376] -> 6`, bank B
  `(16-6)*1573376 -> 15733760`.
- Totals: `15833472+15932160+15833472+14161920+15016192+15733760+16777216 -> 109288192` f64,
  `8*109288192 -> 874305536` B of model globals (gb10 build: 1,002,517,520 B with its non-model
  globals, under `2^30 -> 1073741824`).
- Peak resident set at the maximum, measured: init 703,520 kB (`evidence/OMEGALLM/v3/check5-init.txt`).

## 3. GPU path (`TARGET=gb10`)

The kernels do not depend on L (`grset` has no L argument); at the v2 maximum the v3 gb10 code is
byte-identical to v2 (`gpu-disasm.sh`, code_sha256 0664d426…). The chip arena (`gg.om ggplan`) grows
with L: at V 4096, T 256, D 384, H 12, F 1536, B 64 it is 5,892,226,816 B at L 8 and
10,951,814,912 B at L 16 (Wolfram, the `ggplan` sum with 256-byte rounding), within `nvalloc`'s
64 GiB cap. No host scratch in `gg.om` depends on L; `ggsj`/`ogmask` read through `opx`/`oahin`.

## 4. Required checks

1. v0/v1/v2: `core-receipts.sh` rows and receipts equal `evidence/OMEGALLM/core`; `v1-oracle.sh`
   with L 17 exit 12, L 16 small and the full v3 maximum init byte-identical to the referee.
2. v2 maximum: the v3 CPU build gives the v2 build's eval lines and training checkpoints byte for byte.
3. Bank crossing (`build.sh --variant bx`) gives the normal build's checkpoints (K 1, K 2), eval and
   sample output; mutant v (wrong bank) is caught.
4. `gcheck` passes at an L 16 small shape and on the bx build.
5. v3 maximum: init byte-identical to the referee; one training step runs; peak RSS under 2 GB.
6. CPU eval time per window at the v2 maximum regresses at most 5% against the v2 build.
7. `gpu-disasm.sh` at the v2 and v3 shapes finds no slot LOW. Chip gates: v2-shape bit identity
   against the rung-7 step-250 checkpoint, `gcmp2`/`gacmp` at L 16.
