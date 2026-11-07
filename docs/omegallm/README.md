# Omega LLM v0 (aien-train#52)

Omega LLM v0 is a proof of concept. It is a byte-level, decoder-only transformer with 119,104
parameters:

- V 256, T 64, D 64, H 4, F 256, L 2, B 16.
- It is trained from random initialization entirely in seeded `.om` (omc, omega-mv e5b32567).
- Training runs single-threaded on the DGX Spark Grace CPU, with no GPU.

The normative spec is [CONTRACT.md](CONTRACT.md). The receipts are under
`evidence/OMEGALLM/core/` (the `.om` lane) and `evidence/OMEGALLM/oracle/` (the Python-stdlib referee).

## v1 (aien-train#54)

v1 adds a byte-pair tokenizer in `.om` (`bpe.om`, concatenated between `ckpt.om` and `cli.om`),
shapes up to V 4096, T 256, D 256, L 8, B 64, gradient blocks G and K worker processes with
byte-identical results for every valid K, and the `OLLMCK02` checkpoint. The spec is
[CONTRACT-V1.md](CONTRACT-V1.md); v0 commands and files keep their bytes.

```sh
ollm bpefit TEXT MERGES V [MAXBYTES]   # fit merges: M V types chunks fitbytes
ollm bpeenc MERGES V TEXT TOKS         # encode to u16 tokens: K bytes tokens
ollm bpedec MERGES TOKS OUT            # decode: D tokens bytes
ollm init CK V T D H F L B SEED TOTAL LRMICRO [G]
ollm train CK TOKS UNTIL EVERY [K]     # K worker processes, G mod K = 0 (Linux only)
ollm eval CK HELD W MERGES             # MERGES required when V > 256
ollm sample CK SEED N TEMPMILLI PROMPT MERGES
ollm tune CK OUT TOTAL LRMICRO        # fine-tune: keep weights, step 0, new TOTAL and lr, Adam m = v = 0
```

| What | Status | Receipt |
|---|---|---|
| rung 3: config b (V4096 T128 D192 H6 F768 L4 B40, G = K = 20, P 2,582,208), 9000 steps | EXERCISED, 2026-11-02, 41,814 s on the Grace CPU; held-out `E 9000 4486 1823975 680427` (0.680427 bpb over 0.99988 of `held.tok`) | `evidence/OMEGALLM/v1/` |
| v0 receipt suite on the v1 binary b9b4e02d, aarch64 | EXERCISED, 48/48 PASS (2026-11-04) | `evidence/OMEGALLM/v1/checks/core-aarch64/` |
| v1 referee checks, mutants d and e, K = 1/2/4 and config-a K = 1/4 identity | EXERCISED (2026-11-04) | `evidence/OMEGALLM/v1/checks/reruns.txt` |

v0's 1.463036 bpb scores 4096 × 64 bytes, 0.11803 of the same held text; v1's 0.680427 scores
nearly all of it, so the two are not measured on the same positions.

## Status

Evidence for every row is in `evidence/OMEGALLM/core/summary.tsv` (48/48 as expected). Every receipt
names the binary and source sha256 it ran; `core-receipts.sh` builds all six binaries first
(`build.txt`):

- `ollm` b729cc35faa6b3543ff1893c64e8a6feafc224feba7b99f7f13353e1d2179f22, source 47c27b0b;
- mutants: a 69825ec6, b c7ddea4c, c 41c85250; gcheck step variants: h5 0ba9e2c6, h7 2c1e9b3b.

| What | Status | Receipt (`evidence/OMEGALLM/core/`) |
|---|---|---|
| `prep` on TinyStoriesV2-GPT4-valid.txt | EXERCISED | `prep.txt`: `P 27630 24867 2763 19883834 2220914` |
| `base` unigram/bigram bpb | EXERCISED | `base.txt`: `B 4415645 3295113` (4.415645 / 3.295113 bpb) |
| `init` v0 | EXERCISED | `init-v0.txt`: `I 119104` |
| `train`, 50 v0 steps | EXERCISED | `train-v0-50.txt`: loss 5.429638 at step 5 to 3.110411 at step 50 nats; ln 256 = 5.545177 |
| resume is bit-identical | EXERCISED | `resume-cmp.txt`: steps 0→40 in one run and 0→20→40 in two runs give the same checkpoint; `cmp` rc 0 |
| checkpoint refusal | EXERCISED | `refuse-truncated.txt` (rc 10), `refuse-flip-magic.txt` (rc 11), `refuse-shape.txt` (D = 0, rc 12), `refuse-count.txt` (P byte changed, rc 13), `refuse-flip-payload.txt` (rc 14), `refuse-long.txt` (one byte appended, rc 15) |
| largest shape | EXERCISED | `init-max.txt`: `I 217664`, a 5224048-byte checkpoint; `eval-max.txt` (W 2): `E 0 2 5566611 8030922` |
| overflow refusals | EXERCISED | `refuse-eval-hugew.txt`: W = 2^58 → rc 23; `refuse-grad-hugeoff.txt`: 16 offsets of 2^64 − 1 → rc 22 |
| `eval` | EXERCISED | `eval-v0.txt`: `E 50 256 3049318 4399237` |
| `sample` | EXERCISED (runs; output is not cross-checked) | `sample-v0-argmax.txt`, `sample-v0-t800.txt` |
| gradient self-check (smoke; the gate is the oracle's `xgrad`) | EXERCISED | `gcheck.txt` (small shape) maxrel 3.08146e-4; `gcheck-v0-init.txt` (v0, seed 1) 1.05146e-4; `gcheck-v0-step50.txt` (v0, 50 steps) 5.15267e-4; 76 indices each, 0 retries |
| gcheck step size | EXERCISED | `var-h5-*` (h = 1e-5) and `var-h7-*` (h = 1e-7) fail with rc 40 on both v0 checkpoints; see "Self-check constants" |
| Adam self-check (smoke; the gate is the oracle's `xstep`) | EXERCISED | `adamck.txt`: `A 5 3cd046ce38e38e38 0` |
| exp/log against Wolfram | EXERCISED | `mathck.txt`: exp at most 1 ulp, log at most 2 ulp |
| mutants a (dK sign), c (no bias correction) | EXERCISED, killed | `mut-a-gcheck.txt` and `mut-a-gcheck-v0.txt` (rc 40, maxrel 2.0), `mut-c-adamck.txt` (rc 41, maxrel 0.639088) |
| mutant b (targets shifted) | killed by the oracle only | `mut-b-gcheck.txt` passes the self-check, as expected; the kill is in `evidence/OMEGALLM/oracle/` |
| cross-check against the referee | EXERCISED by the oracle lane, on b729cc35 and the three mutants | `evidence/OMEGALLM/oracle/` and `tests/omegallm/ORACLE.md` |
| the v0 run, 20000 steps (`tests/omegallm/v0-run.sh`) | EXERCISED: 2026-11-01T15:24:54Z to 19:23:57Z on core 9, binary a9b5f3ec, unit `Result=success`; held-out 1.463036 bpb at W=4096 | `evidence/OMEGALLM/v0/run/` (see "v0 result") |
| a9b5f3ec and b729cc35 compute the same v0 run | EXERCISED | `evidence/OMEGALLM/v0/equiv-a9b5f3ec-b729cc35.txt`: same `E 2000` line from the run's step-2000 checkpoint, byte-identical checkpoint after 10 more steps; control `equiv-control-mut-b.txt` differs |
| `ollm` as an x86-64 Linux program (`TARGET=x86linux`, omega-mv main `ba5559d9`) | EXERCISED, EMULATED (qemu-x86_64 8.2.2 user mode) | `evidence/OMEGALLM/x86/`: the whole receipt suite, 48/48 PASS, every receipt equal to the AArch64 one apart from hashes, paths and wall time; the v0 checkpoint's final eval `E 20000 4096 1014099 1463036` reproduced |
| `ollm` as a UEFI application (`TARGET=x86efi`, compiler from omega-mv #1015, merged as main `d3d1b1bc`) | EXERCISED, EMULATED (QEMU 8.2.2 TCG + OVMF) | `evidence/OMEGALLM/efi/`: the 11 commands of `tests/omegallm/efi-job.txt` read from `\OLLM\JOB.TXT`; the OUT.TXT body matches the AArch64 reference after efi-check.sh strips the banner, J (timing) and DONE lines; TR.BIN, HE.BIN and S.CK written on the FAT volume identical; mutant b differs at byte 375; corrupted checkpoint, 65535- and 65536-byte job controls pass |
| the same image on one physical machine (names iMac18,3 and Core i5-7500 are from earlier aienux evidence; this run does not record them) | EXERCISED on physical hardware (one machine) | `evidence/OMEGALLM/imac/`: the OUT.TXT body matches the AArch64 reference after efi-check.sh strips the banner, J (timing) and DONE lines; TR.BIN, HE.BIN and S.CK identical, `OLLM DONE 11 186521`; negative controls in `check.txt` DIFFERENT; FAT clean after the firmware's writes |

b729cc35 differs from a9b5f3ec only in bounds handling. The source diff shows it: the concatenated
source goes from `cb80250d…` (a9b5f3ec, recorded in commit da910097's `init-v0.txt`) to `47c27b0b…`
(`build.txt`), and the only code changes are `OCKCAP` in `native/omegallm/ckpt.om` and the two range
checks in `native/omegallm/cli.om` (`ooffrow`, `cmdeval`); the rest are note lines.
`evidence/OMEGALLM/v0/bounds-ab.txt` (core 7, 20 s timeout) shows the behaviour. On a valid
largest-shape `init`, a9b5f3ec exits 103 (bounds trap). On `eval` with W = 2^58, where `W·T + 1`
wraps, it was still running at 20 s and the timeout killed it (rc 124). On a huge `grad` offset it
exits 103. b729cc35 sizes the checkpoint buffer for the largest shape (`I 217664`, rc 0) and refuses
the other two with 23 and 22; `eval-edge-w3`/`refuse-eval-edge-w4` and
`grad-edge-o128`/`refuse-grad-edge-o129` pin the exact boundaries. On in-range inputs the two give
identical output (the equivalence receipt). `evidence/OMEGALLM/v0/provenance.txt` ties the running
unit to the compared files: the sha256 of the run directory's `ollm`, `run.sh` and `ck-2000.bin`
against `frozen/ollm` and the copied checkpoint, and the unit's start time and command line.

## Build

```sh
sh tests/omegallm/build.sh               # -> ../build/ollm (AArch64 Linux)
sh tests/omegallm/build.sh --mutant a    # also b, c: -> ../build/ollm-mut-X
sh tests/omegallm/build.sh --variant h5  # also h7: -> ../build/ollm-var-hX
sh tests/omegallm/build.sh --variant bx  # small bank-A capacities (CONTRACT-V3 check 3): -> ../build/ollm-var-bx
sh tests/omegallm/build.sh --mutant y    # bx plus the wrong bank-B layer (four lines): -> ../build/ollm-mut-y
TARGET=x86linux sh tests/omegallm/build.sh   # x86-64 Linux ELF
TARGET=x86efi sh tests/omegallm/build.sh     # -> ../build/ollm.efi, a UEFI x86-64 application
TARGET=gb10 sh tests/omegallm/build.sh       # -> ../build/ollm-gb10, CPU ollm plus the GB10 GPU commands
TARGET=gb10 sh tests/omegallm/build.sh --mutant g   # also h, m, f, k, s, p, t, r, x, q, w: -> ../build/ollm-mut-X-gb10
TARGET=gb10 sh tests/omegallm/build.sh --variant r0  # GEMM FFMAs without reuse: -> ../build/ollm-var-r0-gb10
```

The build script does four things:

1. It checks the sha256 of the target's omc (`OMC`, defaulting to a sibling checkout):
   - aarch64: `2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f`
     (omega-mv `e5b32567`, `../omega-mv`);
   - x86linux: `be8c51301307555254fc59e351d281aae1aa096d91521777e33a41c8b446448a`
     (omega-mv main `ba5559d9`, `../omega-mv-x86`);
   - x86efi: `b4f45121f6c6d5d8a6ed0f5c4f3934b7cc4bec369bfa89523699bd33928f9b55`
     (omega-mv main `d3d1b1bc`, PR #1015 merged 2026-11-04, `../omega-efi`; the receipts were
     built from #1015's commit `5ce9ecaa`, an ancestor, with this same omc).
2. It concatenates `math.om data.om`, the pool unit (`lpool.om` on Linux, `epool.om` on UEFI;
   CONTRACT-V3 §2), `model.om adam.om ckpt.om bpe.om cli.om` and the platform unit
   (`lio.om` for Linux, `eio.om` for UEFI; CONTRACT §9). The x86 targets put the line
   `target x86linux` or `target x86efi` first.
3. For a mutant, it changes exactly one line of the concatenated copy (`OMUTA`, `OMUTB`, `OMUTC`;
   mutant y changes four: bx's three capacities and `OMUTY`). A variant sets both gcheck steps `GCH`
   and `GCH2` to 1e-5 (h5) or 1e-7 (h7) and must change exactly those two lines (bx: the three
   bank-A capacities); any other count stops the build with exit 4.
4. It compiles under `taskset -c $CORE nice -n 19` and prints
   `BUILD_OK <bin sha256> <path> source_sha256 <sha>`.

## Run

```sh
B=../build/ollm; R="taskset -c 6 nice -n 19"
$R $B prep TinyStoriesV2-GPT4-valid.txt train.bin held.bin
$R $B base train.bin held.bin
$R $B init v0.ck 256 64 64 4 256 2 16 SEED TOTAL LRMICRO
$R $B train v0.ck train.bin UNTIL EVERY
$R $B eval v0.ck held.bin 256
$R $B sample v0.ck SEED 200 800 "Once upon a time"
```

Never commit the data or the `.bin` and `.ck` files. Every receipt in the table can be reproduced
with `sh tests/omegallm/core-receipts.sh`; set `CORE`, `BUILD`, `DATA` or `WORK` to override the
defaults. The exit codes are listed in CONTRACT §7.

## Serve (DRA-119)

```sh
ollm serve PORT CK MERGES [MAXCONN] [tplmax=N] [test=1]   # AArch64 Linux only; prints "PORT n" once listening
```

`serve.om` (aarch64 builds only; gb10 and the x86 targets get `noserve.om`, which exits 2) answers
OpenAI-style chat requests on 127.0.0.1:PORT with omega-mv's `seed/net/http.om` and
`seed/json/{json,jsonw}.om`, vendored byte for byte from omega-mv `e5b32567` into
`native/omegallm/net/`. `build.sh` checks their sha256 (`NET_PIN_MISMATCH`, exit 3) and puts `om2`
first. One request at a time and one request per connection (`Connection: close`), so a pooled
idle client cannot hold the listener. A connection is served only once its first bytes arrive:
one that sends nothing within 20 ms of its accept waits in one of 8 pending slots (polled with
the listener; when all 8 are taken, new connections wait in the listen backlog) and is closed
unanswered 10 s after its accept. Once bytes arrive the head must complete within 10 s and the
body within 60 s, so a client that starts a request and stalls holds an idle server up to that
bound. `tplmax=N` (256 to 983040, default 65536) caps the chat template in bytes. `test=1`
enables the test-only members `ollm_test_output` (a string whose encoding replaces the drawn
tokens, then token 0) and `ollm_test_delay_ms` (0 to 10000, how long the server waits for
connections before each token); without it they are 400.

- `GET /health` → `{"status":"ok","in_flight":0,"busy":false}`; `GET /v1/models` → one model, `ollm`.
  `in_flight` is the number of chat completions generating, 0 or 1 (one slot), and `busy` is
  `in_flight == 1`; connections waiting in pending slots or the backlog are not counted.
- One generation slot. Between tokens the listener and the pending connections are served:
  `GET /health` answers `{"status":"ok","in_flight":1,"busy":true}`, `GET /v1/models` the list,
  and every other request 503 `server_busy` with `Retry-After: 1` (since DRA-121 a chat
  completion waits in a FIFO queue instead and health also reports `queued` and `capacity`: see
  Serve v4 below). These side requests get a
  250 ms head and 1 s body deadline, so one that starts and stalls costs the generation at most
  about 1.3 s; a silent connection costs it 20 ms once.
- Between tokens the generating request's socket is peeked (`MSG_PEEK | MSG_DONTWAIT`). End of
  stream or a socket error means the client left: generation stops, nothing more is sent, the
  slot frees and the log line has status 499 and finish 4. A client that half-closes its
  sending side after the request counts as gone. A stream also ends when a chunk cannot be sent.
- `POST /v1/chat/completions`: `messages` (content a string, null, or an array of
  `{"type":"text","text":...}` parts joined with no separator; other part types are 400),
  `max_tokens` or `max_completion_tokens` (1 to 999999), `temperature` (0 to 2, no exponent; 0 is
  argmax), `seed`, `top_k` (-1 to 999999; -1, 0 and K ≥ V are off), `top_p` (0 to 1, no
  exponent, resolution 0.000001; 0 keeps only the most probable token, 1 is off), `stop` (a
  string or an array of at most 8 strings of 1 to 128 bytes), `tools`, `tool_choice` (`none`,
  `auto`, `required` or an object), `stream`,
  `stream_options.include_usage`, `n` = 1; other members are ignored (`model`). JSON or SSE
  (`data:` chunks: role, content, tool calls, finish, optional usage, `[DONE]`).
- Interim template, until DRA-123 fixes a shared one: when `tools` is non-empty, `tools: ` and
  the tools JSON exactly as sent, then `\n`; then `role: content\n` per message, an assistant's
  `tool_calls` appended to its content as `<tool_call>{"name":NAME,"arguments":ARGS}</tool_call>`
  (ARGS the decoded string or the object's JSON text as sent); then `assistant: `. At most
  `tplmax` bytes. The context is token 0 plus the template's encoding; when that reaches T the
  answer is 400 `context_length_exceeded`, stating the prompt's tokens and T (the 14,364-byte
  allen-chat system prompt gets this against a T = 256 checkpoint). Output is at most
  min(max_tokens, T − prompt tokens) tokens drawn with `sample`'s step (`osstep`), so the same
  SEED and TEMPMILLI give `sample`'s bytes; with `top_k`/`top_p` on, the kept tokens are the most
  probable (ties to the lower id), up to K and until their mass reaches `top_p`, drawn by the same
  uniform scaled to the kept mass. Token 0 ends with `stop`, the limit with `length`, the earliest
  stop string with `stop` (content cut before it; a stream never sends bytes a stop could still
  claim). Bytes are sent as UTF-8; an ill-formed sequence becomes U+FFFD.
- Tool calls (tools non-empty, `tool_choice` not `none`): when the content from the first
  `<tool_call>` on is 1 to 8 blocks `<tool_call>{"name":N,"arguments":A}</tool_call>` with only
  whitespace between and after, each N a declared tool, the answer carries `tool_calls` (ids
  `call_<request>_<i>`, `arguments` the object's JSON text or the string) with `finish_reason`
  `tool_calls` and content the text before (null when empty); otherwise the text is plain content.
  A stream holds back a possible marker and sends the calls in one delta chunk. Role `tool`
  messages are rendered like any other role. Whether the model emits such blocks is a model
  matter; the checks script the output with `ollm_test_output`.
- Refusals are JSON `{"error":{...}}`: 400 (`invalid_json`, `invalid_request`,
  `context_length_exceeded`), 404, 405, 503 `server_busy`, and 413 `request_too_large` for a body
  over 983040 bytes (refused at the head) or over 65532 JSON tokens (the JSON parser's tape).
- stdout gets one line per response: `C status prompt_tokens completion_tokens finish ms`
  (finish 0 none, 1 stop, 2 length, 3 tool_calls, 4 client left).

`tests/omegallm/serve-check.sh` starts two servers under taskset/nice/bwrap (defaults on PORT,
`tplmax=4000 test=1` on TPORT), referees them with `serve-check.py` (96 checks at DRA-119's
parity merge, 105 with DRA-121's queue checks; the content oracle
is the same binary's `sample`, decoded with Python's `errors="replace"`; the 499 log line is read
from `server-test.log` via `SERVE_TLOG`) and stops the PIDs it started. The checks added since
DRA-119's first 27 come with control checks (`*_control`, `*_is_sample`,
`sample_differs_from_greedy`, `t_ctl_*`, `t_forced_plain`): the same request with one input
changed, expecting the other outcome. A refusal (`refuse_*`) is controlled by the accepted
request it varies. Receipts: `evidence/OMEGALLM/serve/`.

## Serve v4: own checkpoints, own tokenizer, CHAT1, queue, prefix reuse (DRA-121)

`ollm serve PORT CK MERGES ...` now takes:

- **Checkpoints**: OLLMCK03 (v4.om) is loaded with `xload` and decoded with v4's KV cache (`xdpos`,
  RoPE): a generated token costs one decode position, O(context), not a full re-forward. OLLMCK01
  and OLLMCK02 keep the v3 path (a full forward per token, as before).
- **Tokenizer by magic**: a merges file starting `OLLMTOK1` (our own BPE, `tests/omegallm/tok/FORMAT.md`)
  is loaded through `tok/tkcore.om` + `otok.om`; anything else through the v1 `bpe.om` as before.
  The same detection serves `sample4` and `eval4`. OLLMTOK1 merges whose V is not the checkpoint's V
  are refused at startup with exit 31 (the output layer and the tokenizer must agree exactly).
  `build.sh` concatenates `tok/tkcore.om otok.om` after `cli.om` on aarch64, gb10 and x86linux.
- **CHAT1** (with OLLMTOK1 merges; v1 merges keep the interim text template). A conversation is
  token ids built in `serve.om` (`c1conv`): `263 <|doc|>`, then per message `257` (system or
  developer) / `258` user / `259` assistant / `261` tool, `raw(content)`, and `256 <|end|>`. The
  first system message also gets `raw("\n\n# Tools\n" + tools JSON as sent)` when `tools` is
  non-empty (no system message: a system turn holding only that section follows `263`). An
  assistant message adds per tool call `260` then `raw({"name":NAME,"arguments":ARGS})` (NAME the
  JSON string as sent, ARGS the decoded string, the object's JSON text as sent, or `{}`); one `256`
  ends the turn. The generation prompt is `259`. `raw()` is OLLMTOK1 raw mode, so content can never
  forge a special (FORMAT.md section 6). Other roles are 400. Output ends at `<|end|>` (and at any
  other special or reserved id 257 – 271 except `260`: a turn start ends the turn) with
  `finish_reason` `stop`, at `max_tokens` or T with `length`. With tools declared, text before the
  first generated `<|tool_call|>` is `content`; each `260` starts one call whose text (to the next
  `260` or the end, whitespace around dropped) must be a JSON object naming a declared tool, else
  the whole output is plain content. `tool_calls` and `finish_reason` `tool_calls` as in #72's
  protocol, JSON and SSE.
- **`ollm chatenc MERGES IN.jsonl OUT.u16 [MASK.u8]`** runs the same request parser and `c1conv`
  per JSONL line (`{"messages":[...],"tools":[...]}`), so training data and serving produce the same
  tokens; MASK has 1 for the assistant tokens after each `259` (content, calls, the closing `256`).
  It prints `H lines tokens masked`; a refused line is `F line code`, exit 22.
- **Context**: the prompt is counted in tokens; prompt + 1 > T is 400 `context_length_exceeded`
  stating both counts; output is at most min(max_tokens, T − prompt) tokens (the window never
  slides).
- **Prefix reuse** (CK03): the KV cache of the last sequence stays; a request whose token prefix
  matches keeps those positions and prefills only the rest (at least the last prompt position is
  always decoded for its logits). Positions after the first difference are invalidated. The log
  line reports both counts: `C status prompt completion finish ms reused prefilled queue_ms`.
- **Queue**: one generation slot and a FIFO of 32 waiting chat completions. A completion that
  arrives while another generates is read whole (the pending-slot and head/body deadline
  protections stay), queued with its connection, and served in arrival order when the slot frees.
  Only a full queue answers 503 `queue_full` with `Retry-After: 1`. A waiting client that
  disconnects frees its slot at the next token (logged 499, finish 4). During a long prefill the
  side connections are served every 32 positions. `GET /health` →
  `{"status":"ok","in_flight":N,"queued":Q,"capacity":32,"busy":B}`. Why 32: an agent fleet with
  one request in flight per client stays far below it, and each slot holds a full-size body
  (32 × (2,560 + 131,072 + 983,040) bytes = 35.7 MB of globals, inside the 1 GiB globals limit).
  Parallel generation slots by `fork` were measured and not added (see below).
- **Test-only members** (`test=1`): `ollm_test_info: true` adds `"ollm_test":{"logits_fnv",
  "reused","prefilled","prompt"}` to a JSON answer (the word-wise FNV-1a of the first sampled
  step's logits and the prompt ids); `ollm_test_cold: true` drops the cache first (a cold prefill);
  `ollm_test_serial: true` decodes the prompt position by position (sample4's order) instead of
  layer by layer.

Checks (`serve-check.py`, `SERVE_CHECK PASS` required; 105 checks with v1 merges, 43 with
OLLMTOK1 merges): with OLLMTOK1 merges the referee runs the CHAT1 suite: content against `sample4` (same binary, chat-mode prompt), `c1_serve_eq_chatenc`
(DRA-123: serve's prompt ids for five conversations, including tool calls, tool results, content
parts, Unicode and forged marker text, equal chatenc's ids + 259), `c1_chatenc_eq_reference` and
`c1_mask_eq_reference` (an independent Python reading of CHAT1 on `tok/oracle.py`'s raw encoder),
`c1_injection_raw`, context and clamp checks, CHAT1 tool calls with controls, prefix reuse
(`c1_reuse_two_turn`, `c1_reuse_bitexact`, `c1_reuse_diverge_bitexact`: warm logits equal a cold
prefill's in every bit), the layer-by-layer prefill against the position-by-position decode
(`c1_prefill_layer_bitexact`, test member `ollm_test_serial`) and the queue checks (`t_queue_*`, shared with the v1 suite, where
`t_busy_503` became `t_busy_queued`). Negative controls: mutant `c1` (chatenc's writer drops each
conversation's first token) must fail `c1_serve_eq_chatenc`; mutant `j` (prefix invalidation
skipped) must fail `c1_reuse_diverge_bitexact`; mutant `pl` (the layer-by-layer prefill skips the
last layer) must fail `c1_prefill_layer_bitexact`; `t_queue_full_503` is the queue's refusal control.
Receipts: `evidence/OMEGALLM/serve/v4/`.

### Serve v4 measurements (MEASURED, 2026-11-07, spark-b87b, core 4 only, `nice -n 10`)

Binary `ollm` sha256 `f667ba15c67d0ec0f984c4462ec8bcdb717ad4d3f12d6b8d5dcce3ea1ec55ec0` (omc
`2c824805…`, omega-mv e5b32567), merges `merges32k.bin` (OLLMTOK1, V 32768, sha256 `688b723a…`).
Driver `tests/omegallm/serve-bench.sh` (server log times, serve.om's monotonic clock; cold
prefills by `ollm_test_cold`; decode = the difference of two warm requests with 1 and 32 tokens,
divided by 31). Receipts: `evidence/OMEGALLM/serve/v4/bench-B.txt`, `bench-A.txt`. Ratios by
Wolfram. The checkpoints are real CK03 files of our own model, trained only 4 `train4` steps
(B 4, T 256, lr 0.003) on tokenized `val.txt` text (losses 10.09 and 9.81 nats against ln 32768 =
10.40), then their header T raised (RoPE has no positional parameters, so P and the payload do
not depend on T): speed and protocol numbers, not quality.

- **CK-B** V 32768, D 256, H 4, F 768, L 6, T 4096 (P 12,324,096): every layer resident in the
  window (RW = L) and every KV layer resident (RK = L).
- **CK-A** V 32768, D 384, H 6, F 1536, L 6, T 2048 (P 23,204,736): the largest of the requested
  shape that loads today. T 4096 at D 384 is refused (`init4` exit 12: the v4 activation layout,
  about T (11 D + F) values, passes OAC), and its V D + D + LSTR fills the weight window so RW = 0:
  every layer is staged from the master mapping for each decode position (the wide4 lane's window
  work targets this).

| | CK-B (D256, T4096) | CK-A (D384, T2048) |
|---|---|---|
| startup to `PORT` (warm page cache) | 3.08 s | 5.45 s |
| peak RSS (VmHWM) | 479.7 MiB | 719.2 MiB |
| prefill, prompt 256 | 107.4 tok/s | 26.6 tok/s |
| prefill, prompt 1024 | 72.3 tok/s | 18.9 tok/s |
| prefill, prompt 4064 (B) / 2016 (A) | 38.4 tok/s | 19.6 tok/s |
| decode at context 256 | 25.5 ms/token = 39.2 tok/s | 409.5 ms = 2.44 tok/s |
| decode at context 1024 | 32.3 ms = 31.0 tok/s | 418.7 ms = 2.39 tok/s |
| decode at context 4064 (B) / 2016 (A) | 57.9 ms = 17.3 tok/s | 434.4 ms = 2.30 tok/s |
| 2-turn reuse: turn 2 (927 tokens) warm vs cold | 534 ms vs 11,326 ms = 21.2x (908 reused, 19 prefilled) | 5,675 ms vs 77,987 ms = 13.7x |
| 4 concurrent clients (259-token prompts, 16 tokens): client latency | 2.74, 5.45, 8.16, 12.10 s (mean 7.11) | 25.8, 52.7, 79.5, 101.9 s (mean 65.0) |

The 4 clients are served one after another in arrival order (each waits in the queue until the
previous one finishes: the log's queue_ms); no request was refused. Prefill is O(context) per position, so its tok/s
falls with length on CK-B; on CK-A it is bound by staging (32 positions share one staging of each
layer; a decode position stages all six).

During a 4,064-token cold prefill on CK-B (106.9 s), `GET /health` polled every 0.5 s was
answered 113 times out of 113 (median 0.42 s, max 0.88 s: the side connections wait at most one
32-position chunk; `health-during-prefill.txt`).

**Fork slots, measured and rejected**: the same `sample4` run (CK-B: load, prompt and a 64-token
decode, all CPU) took 4.29 s alone and 8.61 s for each of two copies run at once on core 4 (8.61 / (2 x 4.29) = 1.003): one core
gives no throughput from parallel slots, each request becomes twice as slow, and forked children
would not share the prefix cache. `serve` keeps one generation slot and the FIFO queue
(`evidence/OMEGALLM/serve/v4/fork-decision.txt`).

**allen-chat system prompt** (`/opt/allen-chat/system-prompt.txt`, 14,364 bytes): 3,672 tokens in
raw mode with `merges32k.bin` (`ollm-tok tokenc raw`); as a CHAT1 prompt with a user "hi" it is
3,679 tokens (263 257 … 256 258 hi 256 259), which leaves 417 tokens of output in T 4096.

## iMac

`tests/omegallm/efi-receipts.sh` leaves the boot image at `$WORK/ollm.img` (`scratch-efi/ollm.img`;
the image of the receipted run is sha256 `2b9a420a93486a4d37ed78141a45861427090535502243ecbb67fa4008b6c162`).
It is a GPT disk with one EFI system partition, FAT label ALLEN, holding:

- `EFI/BOOT/BOOTX64.EFI`, the `ollm.efi` application;
- `OLLM/JOB.TXT` (a copy of `tests/omegallm/efi-job.txt`), `OLLM/CK.BIN` (the v0 checkpoint),
  `OLLM/STORIES.TXT` (TinyStoriesV2-GPT4-valid.txt) and `OLLM/MATHREF.TXT`.

Write it whole to a USB stick and start the Intel iMac from the stick (hold Option at the chime and
pick "EFI Boot"). `ollm` runs the 11 jobs, shows each job's output on the console and appends it to
`\OLLM\OUT.TXT`. After the last job the console shows `OLLM DONE 11 <ms>`, and `ollm` waits up to
300 s for a key before returning to the firmware. A refusal ends the application at once; OUT.TXT
then ends with that job's output. Copy `OLLM/OUT.TXT` (and `TR.BIN`, `HE.BIN`, `S.CK`) off the stick
and check them against the Linux reference. `678` is the byte size of `tests/omegallm/efi-job.txt`,
which the banner must equal:

```sh
sh tests/omegallm/efi-check.sh OUT.TXT evidence/OMEGALLM/efi/ref.out 11 678
(cd <copied files> && sha256sum TR.BIN HE.BIN S.CK) | diff - evidence/OMEGALLM/efi/ref-files.txt
```

Status: EXERCISED on physical hardware (one machine) (`evidence/OMEGALLM/imac/`, run 2026-11-01). Apple's
firmware ran all 11 jobs and its FAT driver accepted the writes: the OUT.TXT body matches the AArch64
reference after efi-check.sh strips the banner, J (timing) and DONE lines, the three written files match
`ref-files.txt`, and `fsck.vfat -n` finds the volume clean. The firmware clock gave 186521 ms in total,
against 1004245 ms under TCG on one GB10 core. The run itself does not record machine identity.
Whether the console showed the `efi 13` text was not recorded.

Reading the stick back: after the run, macOS 26 refused to mount the stick's partition, even
read-only, although a `dd` copy of the same bytes mounts as a file and checks clean. Copy the raw
partition (`sudo dd if=/dev/rdiskNs1 of=STICK.img bs=1m`) and take the files out with
`MTOOLS_SKIP_CHECK=1 mcopy -i STICK.img ::/OLLM/OUT.TXT …`.

## Throughput

All timings ran on Spark GB10 Grace core 6. `host.txt` records its `midr_el1` (0x410fd851, Arm part
0xd85, Cortex-X925) and a 3900 MHz maximum clock. The process ran single-threaded under `nice -n 19`
on a shared host, so the step time depends on what else runs on that core. Each figure below is one
run, not a distribution.

- `train-v0-50.txt`: 50 steps took 35.315644994 s wall, including 10 checkpoint saves.
  - Per step: WolframLanguageEvaluator `35.315644994/50` → 0.70631 s.
  - Throughput: `50*1024/35.315644994` → 1449.78 training bytes/s.
- `resume-a-0-40.txt`: 40 steps with one save took 28.143739881 s. Per step: `28.143739881/40` →
  0.70359 s. `100*(sps-s40)/s40` → 0.39%: this run's per-step time with a save every 5 steps was
  0.39% above the one-save run. With one sample of each, that is not a measured cost of saving.
- `gcheck-v0-init.txt`: 44.7 s for 76 indices.
- A checkpoint is `112+24*119104` → 2,858,608 B.

## The v0 run

`tests/omegallm/v0-run.sh` is the script of the first full run. It is the init line of the receipts
with seed 1 and TOTAL 20000, trained in 1000-step chunks; each chunk is followed by a held-out eval
at W=256 and a saved checkpoint. Chunking does not change the result, because resume is
bit-identical (`resume-cmp.txt`). After the last chunk it runs one eval at W=4096 and writes three
samples at TEMPMILLI 800 and one argmax sample, each 400 bytes after the prompt "Once upon a time".

The run directory holds `v0-run.sh` copied as `run.sh` (sha256 `4898aae5…`), the binary as
`ollm`, `train.bin` and `held.bin`. On 2026-11-04 a four-line usage comment (lines 2-5) was added
to `tests/omegallm/v0-run.sh`; `sed 2,5d tests/omegallm/v0-run.sh | sha256sum` still gives
`4898aae5…`, so the run's `run.sh` is the script without that comment. It was started with

```sh
systemd-run --user --unit=ollm-v0 --collect -p CPUAffinity=9 -p Nice=19 -p MemoryMax=1G \
  /bin/sh <run dir>/run.sh
```

The unit keeps systemd's default working directory (the home directory); `run.sh` begins with
`cd "$(dirname "$0")"`, so every file it names is in the run directory. `provenance.txt` records
the unit's `ExecStart`, `CPUAffinity`, `Nice`, `MemoryMax`, `WorkingDirectory` and start time, and the
sha256 of the running `ollm`, `run.sh`, `ck-2000.bin` and data against the copies the equivalence
receipts used.

The running binary is a9b5f3ec, built before the bounds fix. On in-range inputs it gives the same
output as b729cc35: `evidence/OMEGALLM/v0/equiv-a9b5f3ec-b729cc35.txt` evaluates and trains 10 steps
from the run's own step-2000 checkpoint with both binaries, and the two checkpoints are byte-equal
(`equiv-control-mut-b.txt` is the negative control). `bounds-ab.txt` shows where they differ: init at
the largest shape and the two overflow refusals.

Planned length, WolframLanguageEvaluator with sps = 0.70631 s/step from `train-v0-50.txt`:

- Duration: `20000*sps/3600` → 3.92 h of training on one X925 core at nice 19 on a shared host,
  plus the evals. (The launch estimate, from an earlier run of the same receipt at 0.70749 s/step,
  was 3.93 h.)
- Data seen: `20000*16*64/19883834` → 1.03 passes over the training bytes, in expectation.
- LRMICRO 3000 is the only learning rate exercised.

## v0 result

All figures below come from `evidence/OMEGALLM/v0/run/` (core 9, Cortex-X925, nice 19, binary
a9b5f3ec, data `101b41c6…`/`729e0a4a…` in `shas.txt`). Arithmetic is WolframLanguageEvaluator,
quoted with each result.

- The unit ended `Result=success`, `ExecMainStatus=0` (`unit.txt`). It ran from 15:24:54Z to
  19:23:57Z, 14343 s: `14343/20000` → 0.717 s/step, including 21 evals and 20 checkpoint copies.
- Final checkpoint `ck.bin` = `ck-20000.bin`, sha256 `ddf790fc…`, 2,858,608 B (not committed).
- Held-out loss, first 256 windows (`evals.txt`), bits per byte:

| step | 0 | 1000 | 2000 | 5000 | 10000 | 15000 | 19000 | 20000 |
|---|---|---|---|---|---|---|---|---|
| bpb | 7.991001 | 2.163609 | 1.929394 | 1.693245 | 1.563117 | 1.491841 | 1.440312 | 1.432839 |

  Still falling at the end: 19000→20000 is `100*(1.432839-1.440312)/1.440312` → −0.519%,
  18000→19000 → −0.947%. This run does not show where it stops falling.
- Final eval (`final-eval.txt`): `E 20000 4096 1014099 1463036`, 1.463036 bpb over 4096 windows,
  `4096*64/2220914` → 11.8% of the held-out positions (the W=256 series covers 0.74%).
  `final-eval-b729cc35.txt` recomputes this line from `ck-20000.bin` with the bounds-fixed binary.
- Against the byte baselines in `base.txt`: `100*(1-1.463036/3.295113)` → 55.6% below bigram,
  `100*(1-1.463036/4.415645)` → 66.9% below unigram. The baselines score every byte transition of
  the held-out file, the eval only the first 4096 windows, so this compares different position sets.
- Training loss of the last step (`train.txt`, one batch): `T 20000 917244` → `0.917244/ln 2` →
  1.3233 bits per byte. Single-batch values swing (19500: 0.937854, 19750: 1.003060 nats), so the
  gap to held-out is not measured here.
- Samples (`sample-*.txt`, 400 bytes after "Once upon a time"; not cross-checked by the oracle):
  the model writes TinyStories-shaped text with names, quotes and sentence structure, plus misspelled
  and invented words ("chisting", "spinnat"). The argmax sample falls into a loop ("The bird said, \"I
  will help you to the park.\"" repeats from about byte 100).

This is a 119,104-parameter byte model trained once with one learning rate on one seed. The run
shows that the `.om` trainer learns on real data end to end; it does not establish quality against
any other implementation's training run of the same shape.

## Self-check constants

- `MCTOL 1e-15`: the allowed relative error of first-party `fexp`/`flog` against the correctly rounded
  Wolfram value.
  - In ulps: WolframLanguageEvaluator `10.^-15/2.^-52` → 4.50 ulp-equivalents.
  - Observed (`mathck.txt`): exp 2.70e-16 (`2.70*^-16/2.^-52` → 1.22) and log 3.37e-16 (→ 1.52).
  - The margin is `10.^-15/3.37*^-16` → 2.97×.
- `tests/omegallm/mathref.txt` is the reference: 3017 `e` lines and 2122 `l` lines.
  - Each RBITS value is the round-half-even f64 of a 60-digit Wolfram `Exp`/`Log` at the exact
    XBITS value. The bits are constructed explicitly, including the subnormal, overflow and zero
    cases.
  - The exp grid covers k/1000 on [−1, 1], 1000 points on [−745, 709.78], and the
    overflow/underflow thresholds.
  - The log grid covers 1/2 + k/1000 up to 2, 10^k for k = −307..307, the subnormals, the largest
    f64, and 1 ± 1 ulp.
- The generator is `tests/omegallm/mathref.wl` (sha256
  `fd94187c1e267c527f9876bb4dd076e5a0b7487d1ba82149375e09d199f3bf75`). Running it, then evaluating
  `{StringLength[text], IntegerString[Hash[text,"SHA256"],16,64]}` in WolframLanguageEvaluator,
  gives 185004 and `3ecc26a3cdf64d640e098eb057e2adfbe390e78fef20b64d5f83e5fa907e961a`. That is the
  same as `sha256sum tests/omegallm/mathref.txt`, so the committed file is exactly what the generator
  writes.
- gcheck takes four indices per tensor instance, drawn by splitmix64, and computes the central
  difference `(L(p+h)−L(p−h))/((p+h)−(p−h))` against the hand gradient. For each index,
  `rel = |num−g|/max(|num|,|g|,GCFLOOR)`. GCFLOOR 1e-6 and GCTOL 1e-3 are unchanged.
- `GCH` was 1e-5. The h5 variant build reproduces that: on the v0 init checkpoint it fails (rc 40)
  at index 34180, `c 34180 284589607 286581380` (hand gradient and difference, ×1e-12), rel
  6.950114e-3 (`var-h5-gcheck-v0-init.txt`); at step 50 it fails at index 82501, rel 2.588816e-3.
  The real build (h = 1e-6) has `c 34180 284589607 284589241` at the same index
  (`gcheck-v0-init.txt`), so the hand gradient is unchanged and only the difference moved. The
  oracle's `xgrad-v0` agrees with the hand gradient code to ≤ 3.3e-12 per tensor
  (`evidence/OMEGALLM/oracle/README.md`). A difference that is wrong while the gradient is right is
  the signature of `p ± h` moving a ReLU pre-activation across 0, where the loss has a kink: the
  difference then measures a one-sided slope, not the gradient.
  - WolframLanguageEvaluator `rel[g_,n_]:=Abs[n-g]/Max[Abs[n],Abs[g],10^6]` on the two lines →
    6.950113e-3 (h = 1e-5) and 1.286062e-6 (h = 1e-6).
- `GCH` is now 1e-6. An index over GCTOL is redone once at `GCH2 = 2.5e-7`, and the smaller rel is
  kept; the `C` line counts these retries. A smaller h narrows the band of pre-activations whose
  kink it can cross. The cost is more f64 rounding noise in L(p±h)/h.
  - Roundoff in the difference is about `eps·L/h` with eps = 2^-53 and L ≈ 5.545 (the init loss).
    WolframLanguageEvaluator `With[{e=2.^-53,L=5.545},{e*L/10.^-6, e*L/(2.5*^-7), e*L/10.^-7}]` →
    6.16e-10, 2.46e-9, 6.16e-9 absolute. Divided by GCFLOOR 1e-6 that is a worst-case rel of 6.2e-4,
    2.5e-3 and 6.2e-3 for a gradient at the floor.
  - The h7 variant build (h = 1e-7) fails on that roundoff, as the bound predicts: v0 init rel
    1.883774e-3 at index 27146, `c 27146 -6471488 -6483702`; step 50 rel 3.555355e-3 at index 76993
    (`var-h7-gcheck-v0-*.txt`). The real build has `c 27146 -6471488 -6471712` there; `rel` above →
    1.883800e-3 and 3.461217e-5.
  - In the variant builds GCH2 equals GCH, so their retry count is a repeat at the same h, not a
    second step size.
  - The h/4 retry can exceed GCTOL from roundoff alone, but it only replaces rel when it is smaller,
    so it cannot turn a pass into a fail, and a wrong gradient (mutant a, rel 2.0) fails at both step
    sizes.
- Observed rels of the real build, all with 0 retries; margin WolframLanguageEvaluator
  `10.^-3/{3.08146*^-4, 1.05146*^-4, 5.15267*^-4, 4.72375*^-4}` → {3.245, 9.511, 1.941, 2.117}:
  small shape 3.08146e-4, v0 init 1.05146e-4, v0 at step 50 5.15267e-4, mutant-b small shape
  4.72375e-4.
- Mutant a reaches 2.0, with 23 retries on the small shape and 38 at v0. It exits 40 on both.
- These constants are deterministic per checkpoint, so a pass is reproducible. The 1.94× margin at
  a trained v0 checkpoint is the tightest; recheck it if the shapes change.
- gcheck and adamck are smoke checks of the binary against itself. The gate for the gradient and
  the Adam step is the oracle's `xgrad`/`xstep` (`evidence/OMEGALLM/oracle/`).

## Sizing

Every query is WolframLanguageEvaluator, 2026-11-01.

- **Pool (`OWN` 1400000 f64, model.om).** `geom` transcribes the layout of model.om
  `ogeom`/`ogeom3`/`oastr`/`ogeom2`:

  ```
  geom[{v_,t_,d_,h_,f_,l_}]:=Module[{lstr,lay0,gf,p,astr,hf,sf,z,pr,end}, lstr=4 d d+2 d f+2 d; lay0=v d+t d; gf=lay0+l lstr; p=gf+d; astr=8 t d+2 t+h t t+2 t f; hf=4 p+l astr; sf=hf+t d; z=sf+t; pr=z+t d; end=pr+t v+7 t d+t f+256; {p,end}]
  ```

  `{geom[{256,64,64,4,256,2}], geom[{256,64,64,8,256,4}]}` → {{119104, 710464}, {217664, 1334336}}:
  P and the pool end for v0 and for the largest shape. Both end below 1400000, and `ogeom` refuses
  a layout past it (exit 12). `init-max.txt` prints `I 217664`.
- **Checkpoint buffer (`OCKCAP`, ckpt.om).** A checkpoint is 112 header bytes plus params, m and v:
  `{112+24*217664, 112+24*119104}` → {5224048, 2858608} B for the largest shape and v0.
  `OCKCAP` is 5224048 + 1: the spare byte lets a read detect a file longer than any checkpoint
  (exit 15). `init-max.txt` records the 5224048 B file.
  v2 (2026-11-04 note, CONTRACT-V2): the v2 maximum (V 4096, T 256, D 384, H 12, F 1536, L 8,
  P 15,833,472) has a 120-byte header (`OLLMCK02`), so a checkpoint is `120+24*15833472` →
  380003448 B and `OCKCAP` is 380003449. `../../evidence/OMEGALLM/gpu-r7/cpu/ock-boundary.txt`: the
  380003448 B file loads, the file plus one or two bytes exits 15. The pool and the numbers above
  are the v0/v1 sizing; the v2 storage split is in CONTRACT-V2 §2.
- **adamck under mutant c (adam.om).** Without bias correction the step-s update is the corrected
  one times `r[s_]:=(1-(9/10)^(s+1))/Sqrt[1-(99/100)^(s+1)]`; `Table[r[s],{s,0,4}]` → {1, 1.346874,
  1.572475, 1.732455, 1.849790}. With adamck's warmup lr `lr[s_]:=(1/1000)(s+1)/100`, epsilon
  `e=10^-8` and its gradients |g| ∈ {1, 2, 3}·1e-4:

  ```
  mut[g_]:=Sum[lr[s](1-(9/10)^(s+1)) g/(Abs[g] Sqrt[1-(99/100)^(s+1)]+e),{s,0,4}];
  ref[g_]:=Sum[lr[s] g/(Abs[g]+e),{s,0,4}]; rel[g_]:=Abs[mut[g]-ref[g]]/Abs[ref[g]];
  N[{rel[10^-4],rel[2 10^-4],rel[3 10^-4]},16]
  ```

  → {0.6386062690569244, 0.6389678457053756, 0.6390884175446797}. The maximum agrees with
  `mut-c-adamck.txt`, `A 5 3fe473698d936acd 639088417544678` (maxrel × 1e15), to 14 significant
  digits: WolframLanguageEvaluator decodes the bits to 0.6390884175446786, |Δ| → 1.143e-15, f64
  rounding of the sum.

## GB10 GPU training (rung 4)

`TARGET=gb10` builds `ollm-gb10`: the aarch64 `ollm` with its `fn main` renamed `ocpumain` and
`native/omegallm/gpu/` appended. `gk.om` (f32 GEMMs: 32×32 tiles as ids 0-7 plus the fused-epilogue
ids 25/26; 64×64 tiles as the even ids 40-54 plus the fused-epilogue ids 56/58, two slots each) and
`gr.om` (slots 9-24, with 12, 17 and 18 empty: embedding, RMS norm, column sums, causal softmax,
copy/zero, CE, the embedding-gradient CSR gather, the SQN sum of squares and ADAM) emit
SASS for sm_121 into a code image; `gg.om` plans
an arena, uploads, launches and reads back through `context.om`/`vector.om`/`launch.om`, vendored from
aien-dev/CUDApp dcba8bb8, on the raw NVIDIA driver. No CUDA runtime or toolkit is used to build or run
it; nvdisasm is a read-only oracle (`tests/omegallm/gpu-disasm.sh SLOT...`).
The `evidence/OMEGALLM/gpu-k*/run.sh` files are as-run window receipts with machine-local paths; the
reusable entry points are `tests/omegallm/build.sh` and `tests/omegallm/gpu-disasm.sh`.

```sh
B=../build/ollm-gb10
$B gcmp CK DATA S                 # chip gradient vs CPU f64 ograd for batch S; GCMP PASS or exit 45
$B gcmp2 CK DATA S                # branch-conditioned parity (ReLU flips split out); GCMP2 PASS or exit 47
$B gacmp CK DATA S                # one step, on-chip f32 Adam vs CPU f64 oadam; GACMP PASS or exit 46
$B gtrain CK TRAIN UNTIL EVERY    # train with the chip gradient, Adam on the CPU
$B gtrainf CK TRAIN UNTIL EVERY   # train with weights and Adam state resident on the chip
$B geval CK HELD W [MERGES]       # eval's forward on the chip in f32; prints eval's E line
$B gprof CK TRAIN N              # N gtrainf steps, nothing saved; GP id gx gy gz m n k wait_ns per launch of the last step
```

Run them only inside a `spark-window`. The checkpoint format is unchanged, so CPU `eval`, `sample` and
`train` read what `gtrain`/`gtrainf` write.

| What | Status | Receipt (`evidence/OMEGALLM/gpu/`) |
|---|---|---|
| chip gradient matches the CPU f64 gradient within γ_R = R·2^-24 | EXERCISED (GB10, non-quiet) | `gc-small.txt` rel 2.35e-7, `gc-night.txt` rel 1.614e-4 < 3.05e-4; mutant g FAIL rc 45 on both |
| on-chip Adam matches `oadam` above f32 weight rounding (resid < 2^-16) | EXERCISED (GB10, non-quiet) | `ga-small.txt` resid 2.34e-7, `ga-night.txt` resid 1.28e-7; mutant h FAIL rc 46 on the night checkpoint (step 1000); on the step-0 checkpoint mutant h is invisible by construction |
| `gtrain` 1750→9000 on the v1 night shape | EXERCISED (GB10, non-quiet) | `gtrain1-3.txt`, 0.235-0.248 s/step |
| `gtrainf` 0→9000, the whole v1 schedule | EXERCISED (GB10, non-quiet) | `gtrainf-0-9000.txt`, 483.8 s, 0.0538 s/step; trajectory within 1.14% of `gtrain` at every shared save point |
| held-out eval of both step-9000 checkpoints (CPU `eval`, W 4486) | EXERCISED | `eval9000-gtrain.txt` 1.824653 nats, 0.680680 bpb; `eval9000-gtrainf.txt` 1.826877 nats, 0.681510 bpb |
| rung 5 (V 4096, T 256, D 256, L 8, P 7,409,920, B 64): `gcmp` fails on ReLU branch flips; `gcmp2` passes | EXERCISED (GB10, non-quiet) | `../gpu-max/gc-max.txt` FAIL rc 45; `../gpu-max/gc2-max-s7.txt`, `gc2-max-s11.txt`, `gc2-night-s7.txt`, `gc2-small-s3.txt` PASS; mutants g, m, f FAIL rc 47 |
| rung 5 `gtrainf` 0→9000 | EXERCISED (GB10, non-quiet) | `../gpu-max/gtrainf-0-250.txt`, `gtrainf-250-9000.txt`: 0.3808 s/step, 43,023 tokens/s; mean batch loss of the last four saves 1.4978 nats |
| held-out eval of rung-5 steps 2000 and 9000 (CPU `eval`, W 2243 at T 256) | EXERCISED | `../gpu-max/eval2000.txt` 1.789590 nats, 0.667600 bpb; `../gpu-max/eval9000.txt` 1.445466 nats, 0.539226 bpb |
| CE kernel sum fix: the plain f32 sum of exp over V 4096 ran ~1.04e-5 low; Kahan sum in `grce` | EXERCISED (GB10, non-quiet) | `../geval/plain/gd-*.txt` before, `../geval/gd-*.txt` after; the rung-4 and rung-5 runs above trained with the plain sum |
| `geval` matches CPU `eval` within 10 µnats | EXERCISED (GB10, non-quiet) | `../geval/ge-night-gtrainf.txt`, `ge-night-gtrain.txt`, `ge-max-2000.txt`, `ge-max-9000.txt`: the CPU E lines exactly, 8.47 s of chip time for the step-9000 eval against 7323 s of CPU; mutant k (plain sum) Δ −11 FAIL; the first build failed the gate (`../geval/plain/`). `geval` has no loss gate and exits 0 whenever it completes (the mutant k receipts too); the 10 µnat gate is the E-line comparison against CPU `eval`, applied by the reviewer |
| rung 6 `gtrainf` 0→30000 at the rung-5 shape in 18 spark-windows, `geval` after every leg | EXERCISED (GB10, non-quiet) | `../gpu-r6/`: every leg and `geval` rc 0; 0.37712 s/step, 43,445 tokens/s; held-out loss fell at every leg to E 30000 2243 1338156 499194 (1.338156 nats, 0.499194 bpb); CPU `eval` of `ck30000` gives the same E line (`eval30000.txt`) |
| k1 kernels: one-warp softmax rows, split-K weight gradients, spin wait; product passes `gcmp2`, `gacmp`, `geval` | EXERCISED (GB10, non-quiet) | `../gpu-k1/`: `geval` of rung 5 `ck9000` and rung 6 `ck30000` give the earlier E lines exactly; mutants s, p FAIL rc 47; 200 steps 1.182× faster than the softmax-only build |
| k2: 64×64 f32 GEMM tile (slots 32-39) when m and n are multiples of 64 | EXERCISED (GB10, non-quiet) | `../gpu-k2/`: `gcmp2`, `gacmp`, both `geval` E lines exact; mutant t FAIL rc 47; the checkpoint after 200 steps is bit-identical to k1's; 200 steps 1.061× faster than k1, GEMM wait −17.45% |
| k3: RMS norm kernels (ids 10, 11) one warp per row, coalesced, single pass | EXERCISED (GB10, non-quiet) | `../gpu-k3/`: `gcmp2`, `gacmp`, both `geval` E lines exact; mutant r FAIL rc 47 (small and max); RMS kernels 2.50× and 2.47× faster in the profile; 200 steps 1.058× faster than k2 in the same window |
| k4: cross-entropy kernel (id 21) one warp per row, coalesced, no stored e (3 reads + 1 write) | EXERCISED (GB10, non-quiet) | `../gpu-k4/`: `gcmp2`, `gacmp`, both `geval` E lines exact; mutant x FAIL rc 47 (small and max) and `geval` Δ −362083 µnats; `grce` 3.68× faster in the profile; 200 steps 1.041× faster than k3 in the same window |
| k5: causal attention GEMMs (ids 0, 1, 35 at batch 512) skip blocks and K tiles above the diagonal via arg words; `grsoftb` masks dp above it | EXERCISED (GB10, non-quiet) | `../gpu-k5/`: `gcmp2`, `gacmp`, both `geval` E lines exact; mutant q FAIL rc 47 (small and max); the checkpoint after 200 steps is bit-identical to k4's; the three attention GEMMs 1.35×, 1.52×, 1.42× faster in the profile; 200 steps 1.059× faster than k4 in the same window |
| k6: softmax kernels (ids 15, 16) load and store only the causal chunks of each row (predicated `LDG`/`STG`); `gkisge` predicate-field fix | EXERCISED (GB10, non-quiet) | `../gpu-k6/`: `gcmp2`, `gacmp`, both `geval` E lines exact; mutant w FAIL rc 47 (max; at the small shape its code equals the product's); the checkpoint after 200 steps is bit-identical to k5's; `grsoftf` 1.64× and `grsoftb` 1.68× faster in the profile; 200 steps 1.053× faster than k5 in the same window |
| k7: GEMM FFMAs (ids 0-7, 32-39) carry Ra operand reuse with control bit 109; accumulator columns remapped (j xor 1) off the b registers' banks | EXERCISED (GB10, non-quiet) | `../gpu-k7/`: `gcmp2`, `gacmp`, both `geval` E lines exact; mutant t FAIL rc 47 (small and max); the checkpoint after 200 steps is bit-identical to k6's; 64×64 GEMM wait 0.918× of k6's in the profile, all from reuse (remap-only variant r0 0.989×, inside the k6 spread); 200 steps 1.034× faster than k6 in the same window |
| k7b: the accumulator remap removed (`OKBNK`, `gkcol`, variant b0); Ra reuse with bit 109 kept, GPU code byte-equal to k7's reuse-only variant | EXERCISED (GB10, non-quiet) | `../gpu-k7b/`: `gcmp2`, `gacmp`, both `geval` E lines exact; mutant t FAIL rc 47 (small and max); the checkpoint after 200 steps is bit-identical to k6's and k7's; GEMM wait 0.955× of k6's over three rotated profile rounds (k7 0.934×, max k7b below min k6); 200 steps 1.0457× faster than k6 and equal to k7 (1.0003) in the same window |
| k8: 64×64 GEMM K loop double-buffered (ids 40-54, two slots each, `gkgpr` 168); QMD word 36 TARGET sized per kernel by `gksmw` (Mesa NAK policy); `gpu-disasm.sh` GPR guard (`gkgpr` ≥ highest GPR + 3) | EXERCISED (GB10, non-quiet) | `../gpu-k8/`: three windows kept. a1 hung (R158 under `gkgpr` 160); a2 bit-identical but 1.12× slower GEMM wait (NULL); a3 (new prereg): `gcmp2`, `gacmp`, both `geval` E lines exact, mutant t FAIL rc 47 (small and max), the checkpoint after 200 steps bit-identical to k7b's; 64×64 wait 0.913× of k7b's kernel under the same TARGET rule (max k8 below min k7b every round); GEMM wait 0.914×, 200 steps 0.969× of k7b's wall in the same window |
| k9: ReLU fused into the FFN GEMM epilogues (ep 1 ids 25/56 store FP and relu(FP); ep 2 ids 26/58 mask dF by FP > 0); `gr.om` RELUF/RELUB (ids 17/18) removed; `gkope` arms the next `gkmm`, `gkepok` refuses any other combination (-22); mutant m moves to the ep 2 threshold | EXERCISED (GB10, non-quiet) | `../gpu-k9/`: `gcmp2` (small, max, and an odd shape F = 96 on the 32×32 ids 25/26), `gacmp`, both `geval` E lines exact; mutant t FAIL rc 47 (small and max), mutant m FAIL rc 47 (small, max, odd); the checkpoint after 200 steps bit-identical to k8's; 48 fewer launches per profile (3 steps); summed GPU wait 0.924× of k8's (144.56 → 133.54 ms/step, max k9 below min k8 every round); 200 steps 0.942× of k8's wall in the same window |
| rung 7: the v2 shape (D 384, F 1536, H 12, P 15,833,472) `gtrainf` 0→30000 on rung 6's data, seed and schedule in 12 spark-windows, `geval` after every leg | EXERCISED (GB10, non-quiet) | `../gpu-r7/`: every leg and `geval` rc 0; chip `geval` E 30000 2243 1254741 468077 (1.254741 nats, rung 6 1.338156); CPU `eval` of `ck30000` (P5) prints the identical E line (`run/eval30000.txt`) |

The γ_R gate, the ReLU kink cases that the night shape exposes, the Adam residual, the windows and all
timings are in `evidence/OMEGALLM/gpu/README.md`. Not QUALIFIED: no quiet-machine timing, one chip, and
a bitwise comparison with the CPU path is not expected (f32 against f64).
