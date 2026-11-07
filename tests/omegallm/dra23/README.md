# DRA-23 live identity probe (`dra23live`)

DRA-23 asks for proof that the model served on `127.0.0.1:18091` consumes one canonical GPU backend.
After the 35B retirement (2026-11-06) the model on `:18091` is the own Omega LLM (`ollm serve`,
DRA-125, lead ownmodel). This directory holds the probe that checks the live process, the gate that
exercises it, and the script for the live row.

| File | Role |
|---|---|
| `live.om` | The probe, OM-2 program mode, read-only: listener inode from `/proc/net/tcp*`, the one process holding that socket, `sha256(/proc/PID/exe)`, `/proc/PID/cmdline`, `GET /health`, `GET /v1/models`, a one-token `POST /v1/chat/completions` (so a lazily opened device is open), then `/proc/PID/maps` (no shared object may be mapped) and `/proc/PID/fd` device nodes, classified as `none`, `nvrm` (`/dev/nvidiactl`, `/dev/nvidiaN`, `/dev/nvidia-uvm`), `aiengpu` (`/dev/aien-gpu*`), `drm` or `accel`. Two classes at once is `gpu_backend_mixed`. |
| `sha256-om2.om` | FIPS 180-4 SHA-256, vendored unmodified from omega-mv `e5b32567` `om/sha256/sha256-om2.om` (blob `748c8711`, sha256 `dbf002dd…94bb`, pinned in `build.sh`). |
| `build.sh` | Composes `sha256-om2.om` (its four `export fn` become `fn`, counted) and `live.om`; compiles with the pinned omc `2c824805…` (omega-mv `e5b32567`, the aarch64 pin of `tests/omegallm/build.sh`). `--mutant m1/m2/m3` plants one-line defects. |
| `check.sh` | Gate: starts its own `ollm serve` and a dynamically linked fixture listener on test ports (never `:18091`), runs 15 rows (positive cases, negative controls, mutants) and stops only what it started. |
| `live-18091.sh` | The live row. Rebuilds the deployed aien-train revision twice (must be bit-identical: that digest is the expected `/proc/PID/exe` sha256), runs the static backend census, then runs the probe against `:18091`. Never starts or stops the server. |
| `VerdictModel.lean` | Lean 4 model of the verdict logic: PASS implies one holder, matching exe, no shared object and an observed GPU class equal to the declared one, which is none or one backend; two classes never PASS. |

Usage:

```sh
sh tests/omegallm/dra23/build.sh                       # BUILD_OK <sha256> ...
OLLM=../build/ollm CK=<ck> MERGES=<merges> [GPUPID=<pid holding /dev/nvidia*>] \
  sh tests/omegallm/dra23/check.sh                     # DRA23CHECK PASS
REV=<deployed aien-train commit> CK=<ck as on the cmdline> MERGES=<merges as on the cmdline> \
  [TARGET=gb10] sh tests/omegallm/dra23/live-18091.sh  # exit 0 PASS, 1 FAIL, 3 NOT_RUN, 4 static FAIL
../build/dra23/dra23live 18091 <exe sha256|-> none|nvrm|aiengpu [PATH SHA256]...
../build/dra23/dra23live --pid PID none|nvrm|aiengpu  # /proc inspection only, no HTTP
```

Limits: an fd/maps snapshot shows what the process holds at that instant; files are hashed when the
probe runs, not when the server loaded them; `ollm serve` reports no build identity of its own, so
identity rests on the exe digest and its reproducible rebuild. Receipts: `evidence/OMEGALLM/dra23/`.
