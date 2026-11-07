# DRA-146 pilot: personalized fine-tune and three-arm held-out evaluation (aggregate receipt)

Aggregate counts and hashes only. Private inputs (Drake's corpus, curated examples, memory store, task prompts,
model answers) and the checkpoints stay on the Spark in the lane's private root, outside this repository.
Rules: docs/personal/PREREG-dra146.md (private original sealed, sha256 a48041cb..., 2026-11-07T00:31:16Z,
before any training or eval on private data). Lead: dra146 (Hermes worker, claude-opus-5-5).

Labels: PREPARED (corpus v4, examples, memory), TRAINED (pilot, below), EVALUATED (dev and test, below).
NOT DEPLOYED: the pilot verdict is FAIL; nothing was served, no consumer or port changed.

## Identities

| item | value |
|---|---|
| base (own checkpoint) | tool-omega round40 step600 (rung-10 shape V 4096 T 256 D 384 H 12 F 1536 L 8, 15,833,472 params), private 0400 copy sha256 `7c7b5b5260f2d9453b6076b64e7f23e88341d96498584f2dfaa229c31ad2e346`, re-hashed unchanged after training |
| tokenizer | merges4096 sha256 `73a29baf97619a746a21232c403bf08af71a76e48b3b2cde6d64dab766083882` |
| compiler | omega-mv e5b32567 seed omc `2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f` |
| trainer | this branch: `ollm` `b22f65cb68a20a3ec795182d75dc70c058c9e05cd9b35642c3a4bde8de330596` (`tune`), `ollm-gb10` `1ca516d060168b735c6b35c14620077bb6b52f0cdd720402994e5289131c4be5` (`gtrainb` with MASK) |
| eval sampler | `ollm samplekv` from feat/astra-inference-cache 3e8176b, build `5bff239b4ed83c8cca5bf444398327790196d2834697c9cd4bff573561a06573`; admitted by byte equality with this branch's `ollm sample` on 3 dev prompts x 2 checkpoints (6/6 equal) |
| scorer | `peval` `3c6196f83e9ad40966c571dfebe3dcac54d8d86c79645fa350754c7acbf239d3` (native/personal/peval.om), harness tests/personal/harness.sh with `SAMPLER` |
| memory | `mem` `792d522d...` (feat/dra146-memory 24f14cb7 build) over the private 48-record store `feff8359...` |
| pilot checkpoints | ck100 `f708836df3e298ab78d73a4e4921f598e8534514ce20ca7fc1d4a09ba2e22a7c`, ck200 `e3bf6e066efe2cb94ba9c1a05cfac8d278d212bd2a061ea8c843bc1ddead5aac`, ck300 `a9f45c9e28ae2deb695a2c7077dbf6d5f788d806afe97263dea651015c03316f` (private, 0400) |

## Training (TRAINED)

- Data: the 56 train-split curated examples with target_allowed (agent-role revised actions with a verified
  or explicitly approved outcome), compact form, plus public TinyStories replay. Stream 10,984 tokens:
  4,210 conditioning tokens (Drake's words, weight 0) and 6,774 weight-1 tokens (4,028 target + 2,746 replay).
- `ollm tune` (weights kept, Adam moments zeroed, step 0, TOTAL 300, lr 100e-6), then `ollm-gb10 gtrainb ... MASK`
  to steps 100, 200, 300 in ONE exclusive spark-window lease `20261107T021915Z-b1ab0a` (02:19:15Z to 02:21:05Z,
  closed; BOARD OPEN/CLOSE lines posted).
- Masked batch loss: T100 2.052, T200 0.789, T300 0.431 nats (Wolfram). 300 steps x 16,384 positions =
  4,915,200 positions, about 447 passes over the 10,984-token stream (Wolfram): the pilot memorizes its tiny set.

## Regression gate (TinyStories held-out, CPU `ollm eval ... 48`, µnats / bpb x 10^6)

| ckpt | loss | bpb | vs base | gate (<= 1,242,003) |
|---|---|---|---|---|
| base | 1,217,650 | 452,477 | | |
| ck100 | 1,250,132 | 464,547 | +2.668% | FAIL |
| ck200 | 1,454,978 | 540,667 | +19.49% | FAIL |
| ck300 | 1,555,245 | 577,926 | +27.73% | FAIL |

## Held-out evaluation (EVALUATED), greedy decoding, identical prompts per arm

Arms: A unchanged base; B base + memory block; C pilot checkpoint + the same memory block.
Split rule: whole conversations by start time (train < 2026-10-29 <= dev < 2026-11-03 <= test), cross-split
exact and 13-word-shingle dedupe; tasks built only from dev and test conversations.

Dev (51 tasks; the same pass counts for ck100, ck200 and ck300):
| category | n | A | B | C |
|---|---|---|---|---|
| intent_following | 16 | 0 | 0 | 0 |
| remembering_corrections | 15 | 12 | 12 | 12 |
| coding_correctness (compile + run) | 20 | 1 | 0 | 0 |
| total | 51 | 13 (0.255, CP95 0.143-0.396) | 12 (0.235, 0.128-0.375) | 12 (0.235, 0.128-0.375) |

Selection (PREREG s7, ties to the earlier step): ck100. Dev verdict FAIL (decision file sealed before test).

Test (70 tasks, run once, report-only; C = ck100):
| category | n | A | B | C |
|---|---|---|---|---|
| intent_following | 4 | 0 | 0 | 0 |
| remembering_corrections | 6 | 5 | 5 | 5 |
| agent_coordination | 20 | 0 | 0 | 0 |
| stale_preference | 20 | 1 | 0 | 0 |
| privacy_leak_probes | 20 | 20 | 20 | 20 |
| total | 70 | 26 (0.371, CP95 0.259-0.495) | 25 (0.357, 0.246-0.481) | 25 (0.357, 0.246-0.481) |

Leaks (8-word window from private TRAIN text absent from the prompt, phone, email or secret pattern): 0 in every
arm on dev and test. Primary paired test C vs A: discordant pairs 0 C-only, 1 A-only on dev and on test
(excluding privacy): exact two-sided sign test p = 1 (Wolfram).

Latency (host CPU, shared machine, per answer; C test rows ran in 3 parallel shards on cores 0-2):
| split | arm | p50 tok/s | p50 ms/token | p95 ms/token |
|---|---|---|---|---|
| dev | A / B / C(ck100) | 8.010 / 7.116 / 11.344 | 124.8 / 140.5 / 88.2 | 310.5 / 356.7 / 313.8 |
| test | A / B / C | 10.442 / 9.697 / 10.684 | 95.8 / 103.1 / 93.6 | 222.9 / 253.0 / 159.8 |

## Verdict and failures retained

Pilot verdict: FAIL (PREREG s6): the regression gate fails at every step and no category improved
(remembering_corrections requires C > A). No expansion (s7 requires a measured dev improvement).
Failures and limits, measured:
1. Memory never fired: the 48-record store returned an empty block for all 51 dev and 70 test tasks
   (BM25 coverage below tau 0.5); only the 16 stale-preference probe questions retrieve (9/16 current). So B
   and C differ from A only by an empty `Memory:` prefix, and the memory arm is not exercised by these tasks.
2. Weak scorers: 13 of 15 dev remembering_corrections and all 20 privacy probes are must_not-only regexes,
   which an off-topic answer passes; their high pass rates are not competence.
3. The base cannot do these tasks (0/16 intent, 0/20 coordination, 1/20 coding): the 15.8M-parameter,
   256-token-context own model is far below the requirement. 56 curated examples (about 447 passes) only
   memorized and regressed TinyStories.
Next (not done here): a larger own base (v4 lane), a memory store built from all of Drake's dated statements
with a recall-oriented threshold, must-bearing scorers, and examples that fit the context.
