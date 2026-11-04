# v1 checks (PR #54)

Host spark-b87b (DGX Spark, Grace aarch64), nice 19, one core per job. No GPU.

| Check | Run | Result | File |
|---|---|---|---|
| v0 receipt suite (`core-receipts.sh`) on the v1 binary, aarch64 (CONTRACT-V1 §9.1) | 2026-11-04T12:43:46Z to 12:48:00Z, core 5, clone at 4899562, omc 2c824805 | 48/48 PASS; builds `ollm` b9b4e02d (source 9281bb19), the rung-3 binary | `core-aarch64/` (`summary.tsv`, `build.txt`), `core-aarch64.log` |
| v0 receipt suite (`core-receipts.sh`) on the v1 binary, x86linux, EMULATED (qemu-x86_64 user mode under binfmt) | 2026-11-04T12:43:46Z to 14:16:31Z, core 6, source built at 4899562, the x86linux omc pinned and checked by `build.sh` | 48/48 PASS; builds `ollm` 5163c1fb (source 0fb34872) | `core-x86linux/`, `core-x86linux.log` |
| x86efi `efi-receipts.sh` (CONTRACT-V1 §9.1 `efi-check`), EMULATED (QEMU 8.2.2 + OVMF, not the iMac) | 2026-11-04T14:16:37Z to 14:36:25Z, cores 5 and 6, clone at 7b5e59e, x86efi omc b4f45121 (`EOMC`) | 8/8 PASS: main EQUAL with TR.BIN, HE.BIN, S.CK equal to the aarch64 reference; mut-b differs; ckbad; job65535; job65536 refused | `efi-20261104/`, `efi-20261104.log` |
| v1 referee checks (`v1-oracle.sh`) with V0BIN, aarch64 | 2026-11-04T12:52:04Z to 12:53:06Z, core 5, clone at 18d83430 (notes, docs and the V0BIN path fix since 4899562; `ollm` still b9b4e02d, `build` section) | `SUMMARY pass=54 fail=0 not_run=0` | `reruns.txt` |
| mutant e under `v1-oracle.sh` | same | killed: exit 1, `fail=12` | `reruns.txt` |
| K = 1, 2, 4 identity at G = 4 (V300 config, 5 steps) | same | all three e1df7ad3…, EQUAL | `reruns.txt` |
| mutant d, K = 1 vs K = 2 | same | 186bcab9… vs e1df7ad3…, DIFFERENT (caught) | `reruns.txt` |
| config a (V 4096, the shape set in `reruns.sh`), K = 1 vs K = 4, 2 steps on `v1-data/train.tok` | same | both 1ec5df1f…, EQUAL (init 7fbaaf09…) | `reruns.txt` |
| v0 → v1 equivalence on a v0 checkpoint (binaries 52f5684f v0, b9b4e02d v1) | local run, file time 2026-11-01 19:34 −0600, copied verbatim | `verdict EQUAL` | `equiv-v0-v1.txt` |
| x86linux `v1-oracle.sh` (EMULATED, qemu user mode) | earlier local run, copied verbatim; contains the run directory's home path | `SUMMARY pass=54 fail=0 not_run=0` | `x86-v1-oracle-ox.log` |
| `bpe-check.sh` | earlier local run, copied verbatim; its binary is `99beb26d…`, an earlier build, not b9b4e02d | `SUMMARY pass=33 fail=0` | `bpe-check-bc.log` |

`reruns.sh` is the script that produced `reruns.txt`; it removes the working directory's prefix from
printed paths. The first `reruns.sh` attempt passed `DATA` and `V0BIN` as relative paths, which the
referee cannot open from its own directory; that is fixed (`DATA` absolute in the script, `V0BIN`
made absolute by `v1-oracle.sh` at 18d83430) and only the fixed run is kept.

The x86linux suite built from the 4899562 source. Between 4899562 and 2e70de4, `native/omegallm` differs
only in comment lines (`git diff --stat 4899562 2e70de4 -- native/omegallm`: `.crumb` 10, `eio.om` 2,
`lio.om` 2 lines, the `note` function lists of N2); that binary was not rebuilt at 2e70de4.
The EFI run's aarch64 reference build at 7b5e59e (source 12530a53, after the N2 `note` edits) is
again `ollm` b9b4e02d, so those comment edits leave the aarch64 binary unchanged. Its `build.sh`
call passes an empty `OMC`, whose default is `../omega-mv` beside the clone; in the worktree layout
used here that path is a symlink to the pinned omega-mv checkout (omc 2c824805, checked by `build.sh`).
