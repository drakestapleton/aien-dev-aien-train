# Omega LLM v3 acceptance receipts (host CPU, EXERCISED; chip NOT_RUN)

Builds (pinned omc 2c824805): aarch64 `ollm` 5e20559a…, bx `ollm-var-bx` deacaf60…, mutant v
`ollm-mut-v` e83cc90f…, gb10 303e1891…, x86linux def60c4a…, x86efi `ollm.efi` e6f544eb…; all BUILD_OK.
Cores 1–8, nice 19, machine shared (timings non-quiet).

| Check | Status | Receipt |
|---|---|---|
| 1 v1-oracle.sh, L 17 exit 12, L 16 small and full v3-max init = referee | PASS (pass=56 fail=0 not_run=1, the v0 ck01 case needs a v0 binary) | `v1-oracle.txt` |
| 1 core-receipts.sh vs `../core` | NOT_RUN to completion here (was running at commit time) | — |
| 2 train 2 steps from rung-7 ckL0, v2 vs v3 checkpoint | NOT_RUN to completion here (job running at commit time) | — |
| 3 bank crossing 256 8 16 2 32 4 4, K 1 and K 2: bx = normal checkpoint, T lines, eval W4, sample | PASS; mutant v differs in all four: caught | `c34/cmp.txt`, `c34/t-*`, `c34/e-*`, `c34/s-*` |
| 4 gcheck at L 16 (256 8 16 2 32 16 2 …) and on bx (L 4, and the L 16 checkpoint) | PASS rc 0 | `c34/g-*.txt` |
| 5 v3-max init vs referee | PASS byte-identical, I 29995392; v2 binary refuses rc 12; peak RSS 703,520 kB, 7.52 s | `check5-init.txt` |
| 5 one train step + checkpoint round trip at v3 max | NOT_RUN to completion here (job running at commit time) | — |
| 6 eval W 4 of rung-7 ck30000, v2 vs v3 | INCOMPLETE: rep 1 v2 62.99 s, v3 71.42 s wall (same E line `E 30000 4 1371037 498023`); reps 2–3 running | — |
| 7 gpu-disasm v3-max, v2-max, parity shape | PASS, no LOW; v3 = v2 code_sha256 at both shapes | `check7-disasm-*.txt` |
| chip gates | NOT_RUN (no GPU authorization) | — |
