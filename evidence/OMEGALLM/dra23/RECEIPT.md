# DRA-23 receipt: own Omega LLM serving identity and GPU backend (host, 2026-11-07)

Card si023 (kanban t_f35fbfcd), Hermes worker claude-opus-5-5. Spark `spark-b87b`, aarch64, cores 10-11,
nice 10. No GPU lease was opened and no GPU device was opened by this work; `:18091` was not bound.

Source: aien-train main `0518c915dea370b3bffbb90d579b1daa5ba8b8f5`, omc sha256
`2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f` (omega-mv `e5b32567`).
Probe `dra23live` sha256 `bcc179a2d091b19016f1b37a4263d29bdbb01ab61828de6dfff094fff9803aef`.

## 1. Which build serves, and which GPU backend each build contains (static, EXERCISED)

| Build (`tests/omegallm/build.sh`) | sha256, two independent builds | `serve` | Device node texts / `devcall` lines in the composed source |
|---|---|---|---|
| `TARGET=aarch64` `ollm` (265792 bytes, static ELF) | `819664d5a2284189cd9baca67681675ed2b4685e19d1d976ce071b0f6fcaa5ea` both | yes (`serve.om`) | 0 / 0: no GPU backend |
| `TARGET=gb10` `ollm-gb10` (391916 bytes, static ELF) | `c35798fdeb5818f07aaf0979676469be366655dfcf77d3baa8092c3ee539a257` both | no: `noserve.om`, `cmdserve` exits 2 | 3 (`/dev/nvidiactl`, `/dev/nvidia0`, `/dev/nvidia-uvm`) / 2, all in `native/omegallm/gpu/context.om` |

Finding: at aien-train main no build both serves and drives the GPU. A `:18091` deployment of `ollm serve`
today is CPU-only, so its live identity row is `gpu_observed none`. One canonical GPU backend on `:18091`
needs a gb10 serve build first (owner ownmodel, DRA-119/DRA-125).

The gb10 device layer is CUDApp's. `gpu/context.om`, `vector.om`, `launch.om` have the git blob ids of
CUDApp `dcba8bb8` `native/nvrm/context.om`, `native/blackwell/vector.om`, `native/blackwell/launch.om`
(`5280fea0`, `d2c1bc83`, `fb70bee4`). CUDApp main `b774723f` is 152 commits ahead of `dcba8bb8`; in those
three files it changes only the SPDX note line (AGPL-3.0-only to Apache-2.0 WITH LLVM-exception). A gb10
build with the three CUDApp main files substituted is bit-identical: `c35798fd…a257`.

Gap: `tests/omegallm/build.sh` pins `net/*.om` by sha256 but not the vendored `gpu/` files. A code edit
in `gpu/context.om` (`/dev/nvidia0` to `/dev/nvidia1`) builds with rc 0 to `300052a0…cf68`; a note-only
edit builds to the same `c35798fd`. `live-18091.sh` performs the missing check (controls below).

## 2. Probe gate (`check.sh`, EXERCISED, `DRA23CHECK PASS`, 15/15 rows)

Against `ollm serve 18923 ck60000.bin merges4096.bin` started by the gate (ck sha256 `a53ced72…2d0f`,
merges `73a29baf…3882`), a `python3 -m http.server` fixture on 18924, and the running omega-tool-model
GPU server (inspected read-only through `/proc`, `--pid` mode). Per-row outputs in `check/`.

| Row | Expect | Got |
|---|---|---|
| p1 own model CPU serve, exe + ck + merges hashes, `gpu none` | PASS | PASS; `/health`, `/v1/models`, chat 200; `gpu_observed none` |
| n1 wrong exe digest | `exe_sha256_mismatch` | FAIL as expected |
| n2 declared `nvrm` against the CPU server | `gpu_expect_mismatch` | FAIL as expected |
| n3 wrong ck digest | `file_sha256_mismatch` | FAIL as expected |
| n4 ck path not verbatim on the cmdline | `file_not_in_cmdline` | FAIL as expected |
| n5/n6 dynamically linked fixture | `shared_object_mapped`, `http_health_not_200` | FAIL as expected |
| n7 unknown GPU class `cuda` | usage, rc 2 | rc 2 |
| p2 GPU server, declared `nvrm` | PASS | PASS (`/dev/nvidiactl`, `/dev/nvidia0`, `/dev/nvidia-uvm` fds, no shared object) |
| n8 GPU server, declared `none` | `gpu_expect_mismatch` | FAIL as expected |
| n9 port with no listener | NOT_RUN, rc 3 | rc 3 |
| m1 mutant (digest compare disabled) on n1 | survives as PASS | PASS: n1's failure depends on the compare |
| m2 mutant (nvrm class disabled) on p2 | flips to FAIL | FAIL |
| m3 mutant (`.so` match disabled) on n5 | no `shared_object_mapped` | none reported |

## 3. Live row script (`live-18091.sh`)

| Run | Result |
|---|---|
| `TARGET=aarch64` against `:18091`, 2026-11-07T00:04Z | STATIC PASS (expected exe `819664d5…5ea`, census 0/0); live `verdict NOT_RUN no_listener_on_port`, rc 3 |
| `TARGET=gb10` against `:18091` | STATIC PASS (expected exe `c35798fd…a257`, 3 CUDApp_MATCH, census 3/2); live NOT_RUN, rc 3 |
| Same script, aarch64, against a test server on 18923 (pre-repo copy) | PASS, rc 0 |
| s1 commit editing `gpu/context.om` code, gb10 | `CUDApp_MISMATCH`, `STATIC FAIL vendored_device_layer`, rc 4 |
| s2 commit adding a device node text to `gpu/gg.om`, gb10 | `STATIC FAIL second_device_layer nodes=4 calls=2 want=3/2`, rc 4 |
| s3 dirty tree / s4 abbreviated REV | `DIRTY_TREE 1` rc 4 / `REV_MISMATCH` rc 4 |
| s5 the s1 commit, aarch64 | STATIC PASS 0/0: the CPU build does not include `gpu/` |

## 4. Verdict model (Lean 4, lean MCP)

`VerdictModel.lean`: `pass_safe`, `mixed_iff_two_classes` (all g < 16), `mixed_never_pass` checked;
axioms `propext`, `Classical.choice`, `Quot.sound` only. Control: `mixedFail 3 = false` is rejected.
This is a model of the decision logic, not a proof about the compiled probe.

## Labels

| Item | Label |
|---|---|
| Probe, gate, live script | IMPLEMENTED, EXERCISED (host), gate TESTED on this branch |
| Static identity of both builds, CUDApp device-layer identity | EXERCISED (host) |
| Live `:18091` row | NOT_RUN: nothing listens (35B retired; own model not deployed, DRA-125) |
| One canonical GPU backend on `:18091` | NOT_RUN: no gb10 serve build exists |
| GB10 hardware, physical numeric/correctness controls | NOT_RUN |
| Earlier 35B static receipt (`DRA-23-IDENTITY-RECEIPT.v2.json`, bin-19173f9e) | historical, retired model |
