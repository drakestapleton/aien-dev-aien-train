# evidence/OMEGALLM/gpu-bf: BF16 tensor-core GEMM path

The contract is `docs/omegallm/CONTRACT-BF16.md`. This README (added 2026-11-04) says how the
receipts here were produced and what a replay needs. The receipts themselves are not edited.

| Path | What |
|---|---|
| `disasm-27-36.txt`, `f32-identity.txt`, `build.txt` | host evidence at e329675 |
| `build-2.txt` | build hashes after the gbfrag amendment (f28e6ad); the binaries of both windows |
| `g1/` | chip window bf-g1, gates B1-B12 (EXERCISED, one GB10, non-quiet) |
| `t1/` | chip window bf-t1, profile and the 2000-step gate T1-T3 (EXERCISED, one GB10, non-quiet) |
| `fix-pad/` | gbfrag padding check (2026-11-04): host build and kernel-byte identity; chip run NOT_RUN |

## Build

From the repository root, with the pinned omc (omega-mv seed/out/omc, sha256
2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f):

```sh
OMC=<omc> TARGET=gb10 OUT=<dir> CORE=3 sh tests/omegallm/build.sh               # ollm-gb10
OMC=<omc> TARGET=gb10 OUT=<dir> CORE=3 sh tests/omegallm/build.sh --mutant u    # also l, o, v
```

At f28e6ad this gives the binaries of both windows (`build-2.txt`): ollm-gb10
54fb8233c62a13c0b3bac13a38dd5b583943e9e9097342baaa57fc22db2ceb49, mutants u efc983e9..., l
b62ce7f8..., o af048991..., v ef2ddbfc.... On 2026-11-04 the same command on a82fc1a rebuilt
54fb8233... again (`fix-pad/build.txt`).

## Inputs

The expected sha256 values are those of `g1/prereg.txt` and `t1/prereg.txt`:

| Path (original run) | sha256 | Origin |
|---|---|---|
| `/tmp/gk/r7/ckb8.bin` | 0a4c382cbd2fdbb9fe6bc6f5e07e59b1012ec738491ce05570fe38a15be854a3 | `ollm init ckb8.bin 4096 256 384 12 1536 8 8 1 9000 3000 8`, the v2 maximum shape at B 8, made for rung-7 gate 1 (`../gpu-r7/gate1/prereg.txt` lines 22-23) and used again by rung-7 gate 2 |
| `/tmp/gk/r7/ckL0.bin` | fc8835feae77a7ee93b59807337d51c72dd5df277b48fd93f011e5c592c5ac86 | `ollm init ckL0.bin 4096 256 384 12 1536 8 64 1 30000 3000 16`, the rung-7 start (same prereg, lines 24-25) |
| `/tmp/gk/r7/run/ck30000.bin` | 378d5a2d877841007a1e9319ba2f7c2378a8ad575520adc71f08ca6b15113a73 | rung 7 final checkpoint |
| `/tmp/gk/r6/ck30000.bin` | 8ccaa099ad68ab02afafef9743b8fddc793b9cad029ab8291e91fb86e82d5509 | rung 6 final checkpoint |
| `/tmp/gk/r6/ck9000.bin` | e91349fbfe2e0851491af1a02799af5bad045b09a602fb7b56f4f320df8b206d | rung 6 step 9000 (g1 trains a copy) |
| `/tmp/gk/r7/g/ckg.bin` | 1ab162bf8d2e06e56884045ef17ca6999c4d328f01f75d666e0433c92c9b7094 | a copy of ckL0 after rung-7 gate 1's `gtrainf 250 250` (`../gpu-r7/gate1/run.sh` lines 26-28) |
| `cks.bin` (in `g1/`'s run directory) | c8693160c03c47781d69b6001794be43148221c4995bb0bfa07b18e0931a40ac | `cpu/ollm init cks.bin 256 32 64 2 128 2 8 1 100 10` (`g1/prereg.txt` line 40) |
| `/tmp/gk/r7/gpu2/ollm-gb10` (P7) | 1853303e82e9770822e643d0a22e5af9d3c7377a1a8b2c5cbf55ba6774814f0f | the rung-7 run binary |

The data directory is `~/handoffs/omega-llm-20261101/v1-data`. The receipts above record the
sha256 of held.tok (8f6ac61a...) and merges4096.bin (73a29baf...), for example
`../gpu-r6/eval30000.txt`. On 2026-11-04 the files there hashed to train.tok
23a8dcb6415c93b70a3a3bb2ab04f5334faa340b2d08dbb1cfb73a45bd6eb4b0, held.tok
8f6ac61acfb59acc285383531f93d8c56b25f70827a07e4aea137e80c46aa1cf, merges4096.bin
73a29baf97619a746a21232c403bf08af71a76e48b3b2cde6d64dab766083882 and train.dec
a8e1143ef7d40e0e39c64fcad3705365b5096bf3f2072cc3680a4e9d66a2f9dc.

## Running a window

`window.sh` and `run.sh` hard-code the paths of the original run: the binaries in
`/dev/shm/ollm-bf/build-gb10`, the run directories `/dev/shm/ollm-bf/chip/g1` and
`/dev/shm/ollm-bf/chip/t1`, the checkpoints under `/tmp/gk`, and the data directory above. A
replay copies prereg.txt, prereg.sha256, run.sh and window.sh into such a directory and changes
the paths only if the inputs live elsewhere. window.sh is committed without the execute bit, so
start it with `sh window.sh`. It first checks prereg.sha256 (exit 7 on a mismatch), posts to
`~/handoffs/BOARD.md`, opens the spark-window, runs `sh run.sh` inside it and closes it. The chip
needs the current window authorization; these files are not one.

## Note on the 118.81 TFLOP/s reference (2026-11-04)

`t1/REPORT.txt` compares the BF16 GEMM rates with "the 118.81 TFLOP/s HMMA rate measured on our
own path". That rate was not measured with gkgemmb or any part of this lane. It comes from
`docs/physics/gb10-training.md` line 61 on branch physics/gb10 (001ec9a9): BF16 tensor rate
(HMMA.16816.F32.BF16) 118.81 TFLOPS, measured by L151 in `raw/gpu-tc-peak.txt` of omega
`doc/machine-ceiling@3c8ce239`, `evidence/MACHINE-CEILING-20261020/`, window
20261020T030919Z-9d9d5a. Line 322 of the same file names the kernel generator,
`src/omega_blackwell_codegen_tc.c`, a C generator. Read "measured on our own path" as "measured
on this GB10 with the machine-ceiling kernel". The receipt keeps its original wording.
