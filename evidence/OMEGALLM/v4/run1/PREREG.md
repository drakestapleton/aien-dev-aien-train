# run1: the first own Omega LLM candidate for the harness path (pre-registration)

Written 2026-11-07 by ownmodel (Hermes worker, claude-opus-5-5) BEFORE any training step of this run.
Its sha256 is posted on the BOARD before leg 1. Nothing below is a result.

## Identity
- Source: aien-dev/aien-train `feat/ollm-path-integ2` @ cfec44b3d72fd0261f3926658cbcd2ed11a701f9 (main 0518c91 + #72 + #74
  + feat/ollm-v4-wide + feat/ollm-serve-v4 + feat/ollm-v4-gb10 + feat/ollm-harness + feat/ollm-accept-124, lead
  conflict resolution, tune4 T/B/G extension).
- omc omega-mv e5b32567, sha256 2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f.
- Binaries: `ollm` (aarch64) 353dde359d1b0c6aad86fee31d86ab006a288709d9a4e806561cb79338ba9fab,
  `ollm-gb10` 2467d11f848953c44801d2fb5dd6fb20ed24c8dbf50be538c13cd98341014c0b.
- Tokenizer OLLMTOK1 V 32768 `merges32k.bin` sha256 688b723a894baa831ee92aaf814918d30823225c45de68c85d9dd244eb79947c,
  learned only from public text (first 600 MB of the base corpus + aien-train and omega-mv sources, `tok-train.txt`
  sha256 a8c363680fe947a613bea851f11ac03c26c55e9d38bf6740a3b61ea9c6c08bf0).

## Shape (decision D7)
S2 = V 32768, D 384, H 6, F 1536, L 8 (P = 26,745,216, printed by init4). Chosen over S1 (D 512, P 41,951,744) because
every S2 layer stays resident in the CPU window, so the CPU server decodes without per-token layer staging
(MEASURED on core 5, sample4, untrained init: S2 64 tokens after a 32-token prompt 5.63 s incl. load, S1 26.15 s).
S1 remains the GB10 capacity qualification shape (CONTRACT-V4-GB10 section 4).

## Data (all on the Spark, not in git; sha256)
- Stage A: `base-train.u16` c4cca0f8...573abf, 473,589,744 tokens: ~/data-omega/base/train.txt (public-domain
  Gutenberg, python-docs, rust-book; sources.json), form-feed document lines replaced by `<|doc|>`, chat-mode
  encoded (the corpus contains no other marker string: grep count 0).
- Held-out general text: `base-val.u16` 3dd6efee...0576f, 23,508,237 tokens (the corpus's own document-level split).
- Stage B: `mixB.u16` 15e4113a...70be8 = `sft-train.u16` (119d5764..., 51,479,609 tokens: 20,000 CHAT1
  conversations from `sftgen 20261107 20000`, harness TRAIN families only, Hermes v0.22.5 `-t terminal` system
  prompt and tool schemas, tool results replayed against real bash by sftgen-check) + the last 60,000,000 bytes
  (30,000,000 tokens) of base-train.u16. SFT share 63.2% (Wolfram).
- Held-out tool-use text: `sft-val.u16` 6d6af9ed..., 1,287,104 tokens (`sftgen 99 500`; 0 lines shared with train).
- The DRA-124 test holdout and the harness held-out families (sha256, replace_word, sort_lines, uppercase, concat,
  arith) are never in training data.

## Schedule
- Init: `init4 ck.bin 32768 1024 384 6 1536 8 16 20261107 24000 3000 1` (CK03 sha256 8826e738...6f768).
- Stage A: BF16 `gtrain4` on base-train.u16, T 1024, B 16 (16,384 tokens/step), lr 0.003, 100-step warmup, linear
  decay to 0.1x at TOTAL 24,000 steps = 393,216,000 tokens (0.83 epoch).
- Stage B: `tune4 ckA-final.bin ck.bin 7300 1000 4096 4 1` (T 4096, B 4, G 1; Adam moments reset, warmup again),
  BF16 `gtrain4` on mixB.u16, 7,300 steps = 119,603,200 tokens (1.47 SFT epochs).
- One exclusive spark-window lease per leg (`--lease 20 --gb10 exclusive --quiet none --wait`), about 780 s of steps
  per leg, save every 500 steps, `geval4` after each leg (stage A: base-val W 64; stage B: base-val W 16 and
  sft-val W 16). Driver: drive.sh/leg.sh in this directory. Throughput figures from these legs are non-quiet.
- Compute (MODELED, 6 P tokens, attention excluded): 8.23e16 FLOP for both stages; 19.2 tokens per parameter.

## Predictions (pre-registered)
- P1 stage A final held-out E (base-val, W 64, nats/token): 3.9, acceptable band [3.4, 4.4].
- P2 stage B final base-val E within +0.30 of the stage A final value (limited forgetting).
- P3 stage B final sft-val E below 0.50 nats/token (system prompt and tool format learned; most tokens are the fixed
  prompt, so this is a format check, not task competence).
- P4 Capability (judged only by the DRA-124 suite and the harness runner, never by loss): on unseen instances of the
  TRAIN harness families, at least 50% of tasks verified PASS by verify.om through real Hermes; on the HELD-OUT
  families, the DRA-124 PREREG harness gate (Wilson lower bound 0.70) is NOT expected to pass [INFERENCE]; coding,
  hive and assistant roles are expected to FAIL (no training data for them in run1).

## Stop rules
- S1 any leg exits nonzero (driver stops; the last saved CK stays).
- S2 stage A held-out E at or after step 6000 at or above 5.5 nats/token.
- S3 40 legs.
A stopped run is reported as stopped, with its last checkpoint and the reason.

## Afterwards
CPU `eval4` of the final checkpoint (re-timed to T 1024 with tune4 so the CPU training layout fits) must equal chip
`geval4` at the same T and W (as CONTRACT-V4-GB10 section 3); then serve-check (CHAT1 suite) on the final CK, the
harness runner, and the DRA-124 suite (its own PREREG, sha256 7133f654...).
