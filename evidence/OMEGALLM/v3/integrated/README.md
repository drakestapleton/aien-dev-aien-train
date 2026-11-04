# v3 on the integrated tree (2026-11-04)

Tree: feat/omega-llm-v3 at b42a068, after merging feat/omega-llm-v2 43f374a (9e525fb) and
feat/omega-llm-bf16 cb55646 (b42a068), with v3's bank-crossing mutant renamed v -> y (f8b497f).
Pinned omc 2c824805..., host CPU (DGX Spark aarch64), nice 19, cores 0 and 1. EXERCISED on the host;
nothing here ran on the GPU. The chip gates are pre-registered in `../chip-g1/`.

| item | result | receipt |
|---|---|---|
| builds: gb10 product + mutants r u l o v n; aarch64 product, mut-y, var-bx | all BUILD_OK. aarch64 ollm 5e20559a..., ollm-mut-y e83cc90f... (the old ollm-mut-v bytes) and ollm-var-bx deacaf60... equal the v3 lane's binaries, so the CPU receipts in `..` describe these bytes | `build.txt` |
| check 7: gpu-disasm.sh, every slot (0-36, 40-58 even), max grset 4096 256 384 12 1536 64 and parity 256 32 64 2 128 2, integrated vs BF16 head cb55646 | no LOW at either shape; gpu-code.bin, gpu-gpr.bin and all SLOT/GPR/SMEM/listing lines identical to BF16's (code_sha256 f85abb94... max, f2628fda... parity, the latter equal to gpu-bf's). Only the DUMP and source sha differ (host sources) | `disasm-lines.txt` |
| checks 3-4 rerun (c34: gcheck at L 16 and with bx, bank crossing G 1 and G 2 normal vs bx vs mut-y) | every receipt equal to `../c34` after its command line; x checkpoints equal, mut-y checkpoints differ at G 1 and G 2 | `c34/` |
| check 5 at H 16 (finding S5): shape 4096 256 16 16 32 16, L*H*T^2 = 16*16*256^2 = 16777216 = 2^24 (Wolfram), product vs oracle.py | init byte-identical (fb4a25a0..., I 102928); one train step: both `T 1 8314921` rc 0; checkpoints differ bytewise and `oracle.py cmp ck` gives PASS (rtol 1e-9; params relerr 1.179e-13), the v1-oracle train-chain rule | `h16/` |
| chip-g1 inputs (ck16, ck16b8, cks) from the integrated CPU build | ck16 3612c260... (= check 5's), cks c8693160... (= gpu-bf/g1's) | `inputs.txt` |

`h16/run.sh`, `h16/*.time` and the `c34` command lines had the home directory written as `~/` when
copied here. NOT_RUN on the integrated tree, because the CPU bytes are unchanged and their receipts in
`..` stand: check 2 (v2-max train steps), c5 one train step at the v3 maximum (1:40:28), c6b eval
timing, the x86linux/x86efi builds and core-receipts.sh. v1-oracle.sh was started on core 0 but is not
recorded here.

Note 2026-11-04: that v1-oracle.sh run finished at 12:59:55Z on core 0 with the integrated aarch64
build 5e20559a...: `SUMMARY pass=56 fail=0 not_run=1` rc 0 (`v1-oracle.txt`). The NOT_RUN item is
v0-v1-ck01, which needs V0BIN and was not given. The chip gates of this build are in `../chip-g1/`.
