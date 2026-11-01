# Omega LLM on x86-64 Linux (EMULATED)

Every result here is **EMULATED**: the x86-64 ELF built by omc runs on a GB10 Cortex-X925 core through
the host's `qemu-x86_64` user-mode binfmt handler (QEMU 8.2.2, Debian 1:8.2.2+ds-0ubuntu1.18, flags
`PO`). No physical x86 CPU ran it; timings measure the emulator, not an x86 chip.

Compiler: omega-mv main `ba5559d9`, `seed/out/omc` sha256
`be8c51301307555254fc59e351d281aae1aa096d91521777e33a41c8b446448a` (x86-64 Linux backend with SSE2
floats). The source is the AArch64 source with the first line `target x86linux`
(`tests/omegallm/build.sh`, `TARGET=x86linux`).

## `core/`: the full receipt suite

`tests/omegallm/core-receipts.sh` with `TARGET=x86linux`, the same script and pinned value lines as
`../core/` (AArch64 native). Binary `build-rx/ollm` sha256
`49b15b591658d7d32b5e9e3d51a27e3ccac921bee90276b991737772412ec228`, source `b9972546…` (shared units
plus `lio.om`); mutants and variants are in `core/build.txt`. Core 6 (MIDR `0x410fd851`), nice 19,
wall 6720 s.

| Check | Result |
|---|---|
| `core/summary.tsv` rows | 48, all PASS; receipt names, exit codes and expected codes equal `../core/summary.tsv` |
| Receipt files compared with `../core/` | 44 of 44 equal after dropping the `target:`, `binary:`, `source:` and `wall_ns=` lines and mapping `build-rx/`→`build/`, `scratch-x86/work`→`scratch-core/work` |

So the x86-64 build prints the same losses, gradients, checkpoint hashes, samples and refusals as the
AArch64 build, bit for bit, including the three mutants (rejected) and the two step-size variants (rc 40).

Rerun from the clone's parent:

```sh
TARGET=x86linux BUILD=build-rx WORK=scratch-x86/work EV=aien-train/evidence/OMEGALLM/x86/core CORE=6 \
  sh aien-train/tests/omegallm/core-receipts.sh
```

## `v0/`: the trained checkpoint on x86-64

Made before the platform units existed, with the v0 source (`2dafb137`, body `47c27b0b…`, the source
of the AArch64 v0 binary `b729cc35`) plus `target x86linux`.

| Receipt | Result |
|---|---|
| `v0/equiv-aarch64-x86.txt` | eval of `ck-2000.bin` and 10 training steps from it: eval lines and the resulting checkpoint equal the AArch64 build (core 7) |
| `v0/equiv-control-x86-mut-b.txt` | negative control: the mut-b x86 build differs in both |
| `v0/final-eval-x86.txt` | `E 20000 4096 1014099 1463036`, the same line as `../v0/run/final-eval.txt` (1.463036 bpb on 4096 held-out windows) |
| `v0/provenance.txt` | the two x86 binaries (`b457ca78…`, mut-b `3c57e8e1…`) rebuilt byte for byte from the committed source; the earlier receipts did not record the source hash |

## Host tools

| Tool | Version | Role | Omega replacement |
|---|---|---|---|
| qemu-x86_64 (binfmt) | 8.2.2 | runs the x86-64 ELF on the AArch64 host | none: verification oracle; a physical x86 run would replace it |
| coreutils `sha256sum`, `cmp`, `taskset` | host | hashes, comparison, core pinning | none: verification oracles |
