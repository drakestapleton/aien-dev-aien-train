# Sources and provenance of item text (DRA-124 acceptance suite)

| file | content | origin | license |
|---|---|---|---|
| `suite/ifeval.jsonl` | 369 IFEval prompts with instruction ids and kwargs (the registered rows) | google-research `instruction_following_eval/data/input_data.jsonl` at commit 0eebfd40 | Apache-2.0, `data/licenses/LICENSE-google-research` |
| `suite/selftest.jsonl` | the same rows with reference, constant (`zq`) and upstream GPT-4 sample responses, each labelled with the upstream checker's strict verdict | upstream `input_response_data_gpt4_20231107_145030.jsonl` (same commit) plus responses built by `accept stub ref` / garbage | Apache-2.0 |
| `data/upstream/instruction_following_eval/` | the unmodified upstream checker (oracle only, never in the scoring path) | google-research 0eebfd40 | Apache-2.0 |
| `suite/humaneval.jsonl` | 164 HumanEval problems (prompt, canonical solution, test, entry point) | openai/human-eval `data/HumanEval.jsonl.gz` | MIT, `data/licenses/LICENSE-human-eval` |
| `suite/items-train.jsonl`, `suite/items-dev.jsonl` | assistant, coding and hive items (prompts, fixture repositories, hidden tests, references) | own-written by ownmodel-accept on 2026-11-07 | this repository's license |
| `suite/hive-system.txt` | the hive conventions system prompt | own-written, summarising the hive rules in `~/handoffs/hive/ownmodel/SHARED-CONTEXT.md` and the `spark-window` / `ledger` help texts | this repository's license |
| `suite/controls.jsonl`, `suite/critical.txt`, `suite/harness.jsonl`, `suite/thresholds*.tsv` | control items, critical patterns, harness row ids, gates | own-written | this repository's license |
| holdout `items-test.jsonl` (not in git; sha256 in `suite/HOLDOUT.sha256`) | test-split assistant, coding and hive items | own-written, same generator, seed 20261107 | this repository's license |
| holdout `harness-test.txt` (not in git) | 18 Hermes tasks, new instances of the harness lane's held-out families; every one checked with the lane's `verify` binary (pre-check FAIL, reference PASS) | own-written | this repository's license |

The own items were written with an authoring script kept next to the holdout
(`~/work/hive/ownmodel/accept/gen/`, outside git because it also writes the test split). It expands
hand-written templates and fixture repositories with a seeded generator and, for every coding item, runs the
reference solution (must pass) and the stub or injected bug (must fail) through the same driver the runner
uses. It is an authoring tool, not part of the runner or scorer. Expected values in the harness tasks
(SHA-256 digests, products) were re-computed in Wolfram.

No item text was produced by a language model's generation at evaluation time, and no outside model weights,
tokenizers or inference engines were used.
