# Platform-unit refactor receipts (aien-train#52)

The I/O moved out of the shared units into one platform unit concatenated last (CONTRACT §9):
`lio.om` (Linux: `aarch64`, `x86linux`) and `eio.om` (UEFI: `x86efi`). The shared units now call
`ocmd` (cli.om) from the platform's `main`, and the globals `owfd`, `opth` and `opk` live in
`lio.om`. These receipts show that the refactor did not change what the AArch64 build computes.
Chip: DGX Spark GB10, Grace CPU, core 7 (Cortex-X925), nice 19; omc omega-mv e5b32567
(`2c824805…`).

| Receipt | What it shows |
|---|---|
| `equiv-b729cc35-52f5684f.txt` | `tests/omegallm/equiv.sh` between the committed binary b729cc35 and the refactored 52f5684f: the same `E 2000 256 1337354 1929394` line on the v0 run's step-2000 checkpoint, and byte-identical checkpoints (`4f94c453…`) after 20 more steps. Verdict EQUAL |
| `core/` | the full `core-receipts.sh` suite on the refactored source (`build.txt`: ollm 52f5684f, source `076871af…`, and the mutants/variants built from it): `summary.tsv` 48/48 PASS |
| `compare-core.txt` | the value lines of all 44 receipts in `core/` against the committed `../core/`, with the host, binary, source, command and wall-time lines excluded and the scratch directory name normalised: 44 EQUAL, 0 DIFFERENT |

Reproduce from the parent of this clone:

```sh
BUILD=build-rf WORK=scratch-rf/work CORE=7 EV=aien-train/evidence/OMEGALLM/refactor/core \
  sh aien-train/tests/omegallm/core-receipts.sh
```
