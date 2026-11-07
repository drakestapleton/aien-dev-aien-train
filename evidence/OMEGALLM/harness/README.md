# Harness lane receipts (ownmodel-harness, branch feat/ollm-harness)

Host spark-b87b (aarch64), core 6, ports 18296 (proxy/capture) and 18299 (server/fixture).
Hermes Agent v0.22.5 (2026.9.24) `bf0203a794a0`, OMP 18.17.0. Pinned omc sha256
`2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f`. Arithmetic below checked with
Wolfram (`mcp__wolfram__WolframLanguageEvaluator`).

## Isolation (what was created)

- No Hermes profile was created or edited. Hermes ran with `HERMES_HOME=~/work/hive/ownmodel/harness/hh`
  (a scratch data root outside `~/.hermes/profiles`, ~400 MB of borrowed runtime deps), an empty
  environment except HOME/PATH/TERM, `--safe-mode --ignore-user-config --ignore-rules`, `--in` a
  temp work dir (`tests/omegallm/harness/hermes1.sh`).
- OMP ran with `HOME=/dev/shm/hive/ownmodel/harness/omphome` holding only `.omp/agent/models.yml`
  (provider `ollmcand`, baseUrl `http://127.0.0.1:18296/v1`); the locked `~/.omp/agent/config.yml`
  was not touched. Command: `omp -p --model ollmcand/ollm --no-session --no-title --no-skills
  --no-rules --no-context-files --no-extensions [--tools=...]`.

## 1. Real requests (captures/) and their CHAT1 length

Captured with `capture.sh` (socat + `respond.sh`, scripted answers, never model output). Hermes
sends `stream: true` with `stream_options.include_usage`, no `max_tokens`, plus an auxiliary
title request (`response_format` json_schema, no tools). `-t terminal` gives 4 tools: `terminal`,
`tool_search`, `tool_describe`, `tool_call` (the bridge for the deferred `process_manage`).
Tool results are `{"output": "<stdout+stderr, final newline stripped>", "exit_code": N, "error": null}`.

MEASURED, `ollm chatenc` (serve4 c3cf792, sha256 `62711f66…`) with merges32k
(`688b723a…`), `measure-chatenc.txt`. Serve prompt = chatenc + 1 (the generation prompt 259).
chatenc tokens + [259] are byte-identical to `chat1-render.sh | ollm-tok tokenc chat` for 10/10 files.

| Request | Bytes | Serve prompt tokens |
|---|---|---|
| Hermes `-t terminal`, turn 1 | 10241 | 2502 |
| Hermes `-t terminal`, turn 2 (1 tool round) | 10536 | 2551 |
| Hermes `-t terminal`, turn 10 (9 short tool rounds) | 13072 | 3026 |
| Hermes title request (no tools) | 1345 | 273 |
| Hermes `-t file`, turn 1 | 10914 | 2697 |
| Hermes `-t file,terminal`, turn 1 | 15792 | 3900 |
| Hermes defaults under `--safe-mode` (= file,terminal), turn 1 | 15867 | 3928 |
| OMP default tools (11), turn 1 | 30250 | 8773 |
| OMP `--tools=bash`, turn 1 | 10426 | 2903 |
| OMP `--tools=bash,read,write`, turn 1 | 13639 | 3924 |
| Runner requests with tools (fixture:ref run, 44 requests, 22 tasks) | 10237 .. 10582 | max 2571 (chatenc max 2570, mean 2538.41) |
| SFT conversations, `sftgen 1 500` (full conversations incl. answers) | 5324815 total | 2526 .. 2634 each, median 2576 |

Per tool round with short outputs the prompt grows (3026 − 2502)/9 = 58.2 tokens; ~4.09 bytes
per token on these prompts (10241/2502). Headroom at T 4096: 1594 tokens after turn 1 of the
terminal setup, 1070 after turn 10, 168 after turn 1 of Hermes's default file+terminal surface;
OMP's default surface (8773) exceeds even 8192 by 581.

Smallest real toolset for file/terminal tasks: `-t terminal` (every task family runs through the
shell; `-t file` alone cannot rename, hash or count). 

**Recommendation: T = 4096** for the harness configuration used here (Hermes `-t terminal`,
`--max-turns 4`): every measured runner request is at most 2571 prompt tokens and every SFT
conversation at most 2634, leaving more than 1400 tokens. 8192 is needed only to serve Hermes's
default `file,terminal` surface for more than a turn or two (3928 tokens before any tool output),
and no T in {4096, 8192} fits OMP's default surface. Note for training: the system prompt and
tools are about 2400 of the ~2575 tokens of each SFT conversation; only 51 tokens per conversation
(25508 of 1287472, 1.98 %) are assistant tokens under chatenc's loss mask (`sft500-stats.txt`).

## 2. Runner and verifier (tests/omegallm/harness/, format in TASKS.md)

Gates (MEASURED, `verify-check-*.out`, `build.txt`):
- `verify-check.sh` with `verify` (sha256 `f1adcad1…`): GATE PASS n=51 (every task: pre-check FAIL,
  `@ref` applied, post-check PASS for train/heldout and FAIL for both controls; unknown id exit 3;
  `..`, absolute path, unterminated block, unknown kind exit 2; no expectations FAIL).
- Negative controls: mutant `verify-eqtrue` GATE FAIL bad=5, mutant `verify-absentok` GATE FAIL bad=1.

## 3. SFT generator (native/omegallm/sftgen/)

`sftgen-check.sh` on 500 conversations of seed 11 (`sftgen-check.out`): GATE PASS checks=11 n=500
calls=746: deterministic, another seed differs, Hermes message shape, tools byte-equal to the
capture, system prompt equal to the capture with only home/HERMES_HOME/cwd/date replaced, 352
distinct dates all equal to GNU `date` America/Chicago, train families only, and every one of the
746 tool calls replayed with real bash gives exactly the simulated tool message, 500/500 outcomes
PASS verify. Negative controls: `sftgen-sgcount` (counts +1), `sftgen-sgnostrip` (keeps the final
newline), `sftgen-sgsys` (one system-prompt byte) each GATE FAIL bad=1.

## 4. Runs (run-*/: summary.txt, per task pre/verify/hermes output, full wire of the first task)

| Run | Endpoint | Label | train | heldout | controls FAIL |
|---|---|---|---|---|---|
| run-r10 | integ `ollm` beecf5fa serving v3 rung-10 `ck60000.bin`, merges4096, :18299 | honest baseline | 0/13 | 0/7 | 2/2 |
| run-ref | `fixture:ref` (socat scripted, @ref tool call) | protocol check only | 13/13 | 7/7 | 2/2 |
| run-plain | `fixture:plain` (plain success claim, no tool call) | negative control | 0/13 | 0/7 | 2/2 |
| run-t1ref | serve4 `ollm` 62711f66 `test=1`, untrained CK03 T 8192 (`tiny-ck03.txt`), merges32k, proxy-injected `ollm_test_output` (`INJECT=ref`) | protocol check only | 13/13 | 7/7 | 2/2 |
| run-t1plain | same server, injected plain success claim (`INJECT=plain`) | negative control | 0/13 | 0/7 | 2/2 |
| run-tinygen | serve4 `ollm` 62711f66, same untrained CK03, no test mode, no injection | real generation, untrained floor | 0/13 | 0/7 | 2/2 |

run-r10: every task's single chat request was refused `400 context_length_exceeded` ("prompt is
4358 .. 4380 tokens including the start token; the context window is 256 tokens"; merges4096 BPE,
the interim template), and Hermes stopped ("This conversation has grown too long for ollm").
No model output reached any task: the baseline is 0/20 because the v3 window (T 256) cannot hold a
real harness prompt, not a measure of the model's tool use.

run-t1ref is the strongest protocol check: real Hermes requests (prompt 2502 .. 2571 tokens,
CHAT1, merges32k) go through serve4's own encoder; the injected `<|tool_call|>` text is parsed by
the server into an SSE `tool_calls` delta (`finish_reason: tool_calls`), Hermes runs the command,
and the next request carries the real tool result. It says nothing about model capability: the
answers are scripted.

run-tinygen sends the same real requests to the same server with nothing scripted: the untrained
random-init checkpoint generates freely (no `max_tokens` from Hermes, so up to T − prompt tokens)
and Hermes acts on whatever comes back. It is the floor of the whole own-model path, not a
trained-model result.

Runner hashes: run-r10/ref/plain used the runner of commit 6d753aa (`c194727d…`); run-t1*/tinygen
the runner of f239340 (`f4ab706a…`, adds `INJECT`). Task file sha256 `03e5c1cf…` in every run.

## NOT_RUN

- A trained own checkpoint behind a CHAT1 server with T ≥ 4096: none exists yet (the v3 rung-10
  checkpoint is T 256, CK01/02, merges4096). The harness is ready for it:
  `VERIFY=bin/verify sh tests/omegallm/harness/run.sh http://127.0.0.1:PORT/v1 tests/omegallm/harness/tasks.txt OUT`.
- OMP task runs (only OMP's request sizes were measured).
