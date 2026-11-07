# v4 wte banks (wide4): receipts

Branch `feat/ollm-v4-wide`; layout and limits in [CONTRACT-V4 section 2.1](../../../../docs/omegallm/CONTRACT-V4.md),
results in section 6.1. Spark core 6, pinned omc `2c824805…`.

| Path | What |
|---|---|
| `summary.tsv`, `*.txt`, `same.txt`, `build.txt` | `sh tests/omegallm/v4-wide-check.sh` (CORES=6): 53 of 53 PASS; reference = build of 63353c9 (`old/ollm`, sha256 `beecf5fa…`) |
| `v4-check/` | the pre-existing `tests/omegallm/v4-check.sh` run on the bank build from a snapshot of `ce3bb2d` (`SOURCE.txt`): 17 of 17 PASS |
| `gcheck-textdep.txt` | `v4-check.sh`'s gcheck4 depends on the repository text: on one text both builds fail identically (rc 40) |
| `v3-equiv.txt`, `v3-equiv-bx.txt` | `tests/omegallm/equiv.sh` reference vs bank build on a v3 CK02 (product and `--variant bx`): EQUAL |
| `s1/` | full S1 (V 32768 T 256 D 512 H 8 F 2048 L 8 B 2 G 2): init4, train4 (3 steps), eval4, sample4, kvck, tune4; S1 at T 4096 (init4, sample4, train4 refused 12); D 768 L 8 init4 + eval4. `DATA.txt` names the text |
| `timing/` | user + sys CPU per step: S1 1-step vs 2-step processes (marginal 107.0 s / 512 tokens); V 32768 D 384 one step, bank build vs reference (115.5 s vs 129.8 s, checkpoints identical) |

Core 6 was shared with other lanes' processes during these runs; wall times are noisy, CPU times are
the cost figures. Numbers derived from them were computed with Wolfram.

`v4-wide-check.sh` trains on the sources and docs of the fixed commit 63353c9 concatenated in C
collation order (`LC_ALL=C`), so its data, and with it gcheck4's worst coordinate, does not change
with later commits or the caller's locale. Run: `OMC=<pinned omc> BUILD=../v4w-build WORK=../v4w-work
CORES=6 sh tests/omegallm/v4-wide-check.sh` from the clone root (exit 0, 53 of 53 PASS).
