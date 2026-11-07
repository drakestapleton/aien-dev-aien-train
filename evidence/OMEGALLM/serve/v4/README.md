# Serve v4 receipts (DRA-121, branch feat/ollm-serve-v4)

Binary under test: `ollm` sha256 `f667ba15c67d0ec0f984c4462ec8bcdb717ad4d3f12d6b8d5dcce3ea1ec55ec0`,
built with the pinned omc `2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f`
(omega-mv e5b32567) on spark-b87b (aarch64), core 4 (`build.txt`). Merges: `merges32k.bin`
(OLLMTOK1, V 32768, sha256 `688b723a…79947c`, tokinfo `I 32768 32496 10523558034196511166`).

| File | What | Result |
|---|---|---|
| `build.txt` | aarch64 build + mutants c1, j, pl (one changed line each), gb10 and x86linux builds | BUILD_OK x 6; x86linux run and x86efi build NOT_RUN |
| `check-v1/` | `serve-check.sh` on the v3 rung-10 checkpoint `/tmp/gk/r10/run/ck60000.bin` with v1 `merges4096.bin` (interim template; queue checks replace `t_busy_503`) | SUMMARY pass=105 fail=0, SERVE_CHECK PASS |
| `check-chat1/` | `serve-check.sh` on the CK03 `t.ck` (V 32768, T 512, D 64, 20 train4 steps) with merges32k: the CHAT1 suite (`c1_*`) + queue checks | SUMMARY pass=43 fail=0, SERVE_CHECK PASS |
| `mutants/ollm-mut-c1.txt` | chatenc's writer drops each conversation's first token | FAIL c1_serve_eq_chatenc (+2), SERVE_CHECK FAIL (caught) |
| `mutants/ollm-mut-j.txt` | prefix invalidation skipped | FAIL c1_reuse_bitexact, c1_reuse_diverge_bitexact (caught) |
| `mutants/ollm-mut-pl.txt` | layer-by-layer prefill skips the last layer | FAIL c1_prefill_layer_bitexact, c1_chat_json_t800 (caught) |
| `refusals.txt` | OLLMTOK1 V ≠ CK V: serve, sample4, eval4 exit 31; v1 merges control; eval4/sample4 with OLLMTOK1; chatenc refuses v1 merges (26) | as listed |
| `chatenc.txt` | a chatenc run with its ids and mask, a refused line (exit 22), the allen-chat prompt's token counts | 3,672 raw tokens; 3,679 as a CHAT1 prompt |
| `bench-B.txt`, `bench-A.txt` | `serve-bench.sh` on CK-B (D256 T4096) and CK-A (D384 T2048) | MEASURED table in docs/omegallm/README.md |
| `checkpoints.txt` | how the measurement checkpoints were made (init4, train4, the header T change) | |
| `fork-decision.txt` | one vs two concurrent decodes on one core | 4.29 s vs 8.61 s each: no gain, not added |
