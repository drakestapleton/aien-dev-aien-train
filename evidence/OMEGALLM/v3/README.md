# Omega LLM v3 acceptance receipts (host CPU, EXERCISED; chip NOT_RUN)

Builds (pinned omc 2c824805): aarch64 `ollm` 5e20559a…, bx `ollm-var-bx` deacaf60…, mutant v
`ollm-mut-v` e83cc90f…, gb10 303e1891…, x86linux def60c4a…, x86efi `ollm.efi` e6f544eb…; all BUILD_OK.
Cores 1–8, nice 19, machine shared (timings non-quiet). In the `/usr/bin/time -v` receipts (`*.time`)
the home directory prefix is replaced with `~/`; nothing else in them is changed.

| Check | Status | Receipt |
|---|---|---|
| 1 v1-oracle.sh, L 17 exit 12, L 16 small and full v3-max init = referee | PASS (pass=56 fail=0 not_run=1, the v0 ck01 case needs a v0 binary) | `v1-oracle.txt` |
| 1 core-receipts.sh vs `../core`, aarch64 and x86linux (qemu-x86_64), core 7 | PASS: both 48 rows all PASS (aarch64 script rc 0; the x86 launcher did not record the script's exit status, its log ends at the summary line); receipt/rc/expect columns equal `../core/summary.tsv`; x86 vs aarch64 receipt files 46 of 46 equal after the `../x86` normalisation. An earlier x86 run was killed with the agent session after 40 PASS rows and rerun from the start | `check1-core.txt`, `core-summary-*.tsv`, `check1-core-*.log` |
| 2 train 2 steps from rung-7 ckL0, v2 vs v3 checkpoint; W1 evals | PASS: checkpoints byte-equal (sha256 ac05dfeb…); W1 E lines equal on ck30000 and ckL0, and ckL0 equals the rung-7 referee line | `check2-6.txt` |
| 3 bank crossing 256 8 16 2 32 4 4, K 1 and K 2: bx = normal checkpoint, T lines, eval W4, sample | PASS; mutant v differs in all four: caught | `c34/cmp.txt`, `c34/t-*`, `c34/e-*`, `c34/s-*` |
| 4 gcheck at L 16 (256 8 16 2 32 16 2 …) and on bx (L 4, and the L 16 checkpoint) | PASS rc 0 | `c34/g-*.txt` |
| 5 v3-max init vs referee | PASS byte-identical, I 29995392; v2 binary refuses rc 12; peak RSS 703,520 kB, 7.52 s | `check5-init.txt` |
| 5 one train step at v3 max, peak RSS < 2 GB; plus a checkpoint round trip (1 step, save, resume 1 step vs 2 steps straight) | PASS: `T 1 8427992` rc 0, peak RSS 1,524,480 kB (A1, core 1, 1:40:28); resumed step 2 and straight 2 steps both print `T 2 7822893`, rc 0, and the checkpoints are byte-equal (`cmp rc=0`, sha256 4cb1fbe2…), from ck0 3612c260… (= the referee init). The first run was killed with the agent session at about 22:42Z and rerun from the start by `c5/c5t.sh` | `c5/` |
| 6 eval W 4 of rung-7 ck30000, v2 vs v3 (first measurement) | INCONCLUSIVE: 3 alternating reps; mean ratio 1.06666 (over 5%), median ratio 1.04583 (under 5%). The contract names no statistic. Kept as measured | `check2-6.txt` |
| 6 follow-up, statistic fixed in `c6b/prereg.txt` before the first run: ratio of medians ≤ 1.05 | PASS: 5 ABBA blocks (20 runs, core 4), Median v3/v2 = 71.085/69.56 s → 1.02192; mean ratio 1.04045; all 20 E lines `E 30000 4 1371037 498023` | `c6b/summary.txt`, `c6b/runs/` |
| 7 gpu-disasm v3-max, v2-max, parity shape | PASS, no LOW; v3 = v2 code_sha256 at both shapes | `check7-disasm-*.txt` |
| chip gates | NOT_RUN (no GPU authorization) | — |
