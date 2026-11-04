# Omega LLM v1, rung 3: the config-b run

Status at commit 4899562 (the source the run's binary was built from), 2026-11-04: EXERCISED. One
run, one seed, on the DGX Spark Grace CPU (spark-b87b, aarch64), no GPU.

## What ran

- Binary `ollm` b9b4e02d80e589227716c6e069529b6ea941cd1bdab5f3a9ea2dcc606b79997b, 112,144 B.
  `checks/core-aarch64/build.txt` shows the branch's sources build this same binary (source
  sha256 9281bb19…).
- Shape (config b, CONTRACT-V1): V 4096, T 128, D 192, H 6, F 768, L 4, B 40, G 20; seed 1,
  LR 0.003, 9000 steps, P = 2,582,208 (`init.txt`: `I 2582208`). The init command is not in
  `run.sh`; its arguments are the header of `ck0.bin` (the step-0 checkpoint):
  `ollm init ck0.bin 4096 128 192 6 768 4 40 1 9000 3000 20`.
- `run.sh`: `ollm train ck.bin v1-data/train.tok 9000 250 20`, i.e. a checkpoint and a T line every
  250 steps, K = 20 worker processes. `after.sh`: held-out eval on core 6, then six samples on
  core 7.
- Data (`inputs.sha256`): `train.tok` 1,020,738,604 B = 510,369,302 tokens, `held.tok`
  1,148,552 B = 574,276 tokens, `merges4096.bin` 15,384 B. `held.tok` encodes the same text as
  v0's `held.bin` (2,220,914 B).

## Result

| What | Value | File |
|---|---|---|
| start, end | 2026-11-02T01:38:06Z, 13:15:00Z | `start.txt`, `end.txt` |
| train exit, wall | rc 0, 41,814 s | `train.rc` (stderr empty: `train.err`, 0 B) |
| time per step | 4.646 s | 41814 / 9000 |
| training tokens, rate | 46,080,000; 1,102.0 tokens/s | 9000 · 40 · 128 |
| batch loss | 3.130320 nats at step 250 → 1.756201 at step 9000 (36 T lines; ln 4096 = 8.317766) | `train.txt` |
| held-out eval | `E 9000 4486 1823975 680427`: 1.823975 nats/token, 0.680427 bpb; rc 0, 1,785 s on core 6 | `after.txt` |
| samples | 3 prompts × temperature 0 and 0.8, seed 1, 200 tokens; all rc 0 (not cross-checked) | `samples.txt` |
| final checkpoint | 61,973,112 B = 120 + 24 · 2,582,208 (CK02); sha256 27486195… | `outputs.sha256`, `after.txt` |
| step-0 checkpoint | 61,973,112 B; sha256 d2efaf93… | `outputs.sha256` |

The batch loss is one batch per T line and moves up and down (for example 2.102209 at step 2250,
2.383803 at 2500), so the last T line is not a smoothed value. The held-out loss (1.823975) is
0.067774 nats above the last batch loss.

### Held-out coverage, and the comparison with v0

v1's eval scores W 4486 windows of T 128: 574,208 target tokens out of 574,276 held tokens, i.e.
0.99988 of `held.tok` (68 tokens are unscored; 4486 is the largest W that fits). v0's 1.463036 bpb
(`evidence/OMEGALLM/v0/run/`) scores 4096 windows of 64 bytes: 262,144 of 2,220,914 held bytes,
0.11803 of the same text. 0.680427 bpb is 0.4651 of 1.463036, but the two numbers are measured on
different position sets (v1 nearly all of the held text, v0 its first 11.8%); no v1 eval over v0's
prefix was run.

## Files

- `run.sh`, `after.sh`: the scripts as run. They `cd` to the parent of their directory and expect
  the layout `v1-night/` (this directory: the scripts, `ollm`, `ck.bin`) beside `v1-data/`
  (`train.tok`, `held.tok`, `merges4096.bin`). They are copied verbatim.
- `start.txt`, `end.txt`, `init.txt`, `train.txt`, `train.rc`, `train.err`, `after.txt`,
  `samples.txt`, `inputs.sha256`: the run's outputs, copied verbatim (file times 2026-11-01 19:37
  to 2026-11-02 07:54 local, UTC−6). The sha256 lines name files relative to the run's parent
  directory.
- `outputs.sha256`: written 2026-11-04T12:46:44Z on spark-b87b from the same run directory, for the
  two checkpoints, which are not committed (61,973,112 B each).
- `checks/`: the v0 receipt suite and the v1 checks run on this branch; see `checks/README.md`.

## Not measured

- One seed only; no spread.
- Throughput on fewer cores, and the eval over v0's 4096 × 64 prefix.
- Peak memory of the run.
- `run.sh` let K = 20 workers use all 20 cores; per-core placement was not recorded.
