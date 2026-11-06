# Harness tasks: file format, runner and verifier

Lane: ownmodel-harness (aien-train `feat/ollm-harness`). Everything here is a test driver; the
checking logic is Omega (`verify.om`), built with the pinned omc by `build.sh`.

## Files

| File | Role |
|---|---|
| `tasks.txt` | the 20 tasks and 2 controls (format below) |
| `verify.om` | task tool and independent verifier (`list`, `prompt`, `ref`, `setup`, `check`) |
| `verify-check.sh` | the verifier's own gate (no model): setup, pre-check FAIL, `@ref`, post-check |
| `build.sh` | builds `verify` (and `sftgen` from `native/omegallm/sftgen.om`); `--mutant eqtrue/absentok` |
| `run.sh` | runs every task through Hermes against an endpoint and verifies it |
| `hermes1.sh` | one isolated Hermes oneshot (scratch `HERMES_HOME`, `--safe-mode`, temp work dir) |
| `proxy1.sh` | logging proxy child: exact request bodies and raw responses per HTTP exchange |
| `respond.sh`, `sse.sh` | scripted fixture endpoint for captures and protocol checks only |
| `capture.sh` | one Hermes run against the fixture, saving every request |
| `chat1-render.sh`, `measure.sh` | CHAT1 rendering and token counts of captured requests (APPROX until `ollm chatenc`) |

## Task file format

Line based. Lines outside directives (blank, `#` comments) are ignored. A task starts at a line
`@task ID FAMILY SPLIT` and runs to the next `@task` line or the end of the file.

- `ID`: 1 .. 64 bytes, no spaces. `SPLIT`: `train`, `heldout` or `control`.
- Block directives end at a line that is exactly `@end`. A block's content is its lines, each with
  its LF (`@file-`, `exact-` and the prompt/ref blocks drop the final LF).
- `@prompt` (block): the user request given to Hermes (no final LF).
- `@ref` (block): a reference shell command that solves the task. Used only by the `fixture:ref`
  protocol check and by `verify-check.sh`; never shown to the model.
- `@file PATH` / `@file- PATH` (block): a file created in the work dir before Hermes runs
  (parent directories made).
- `@expect KIND PATH`: one outcome check, all must hold.
  - `exact` (block): the file's bytes equal the block; `exact-`: the same without the final LF.
  - `trim` (block): equal after both drop leading and trailing space, tab, CR, LF.
  - `contains` (block, final LF dropped): the text occurs in the file.
  - `absent` (no block): the path does not exist. `dir` (no block): the path is a directory.
- Paths are relative to the work dir: bytes `[A-Za-z0-9._/-]`, no leading `/`, no `..`, 1 .. 255
  bytes. A malformed file is exit 2; an unknown id exit 3; a task without `@expect` FAILs.

## Verifier independence

`verify check` reads only the task file and the files under the work dir. It never reads Hermes
stdout, the transcript or the model's claims. The runner also checks every task *before* Hermes
runs: that pre-check must FAIL, else the row is `INVALID` (the outcome was already there).

## Families and split

| Split | Families (tasks) |
|---|---|
| train | create (t01 t02), append (t03 t04), count_lines (t05 t06), list_dir (t07), rename (t08), copy (t09), mkdir_file (t10), first_line (t11), delete (t12), count_words (t13) |
| heldout | sha256 (t14 t15), replace_word (t16), sort_lines (t17), uppercase (t18), concat (t19), arith (t20) |
| control | c01 (create, expected text deliberately wrong), c02 (rename, expected content deliberately wrong) |

The SFT generator produces only the train families. The accept sibling owns the frozen held-out
evaluation; its items must come from the heldout families (new instances are fine), never from the
train families.

## Runner

`VERIFY=bin/verify sh run.sh ENDPOINT tasks.txt OUTDIR` (see the header of `run.sh` for the
environment). ENDPOINT is `http://HOST:PORT/v1` or a fixture (`fixture:ref`, `fixture:plain`).
Hermes runs `-t terminal --max-turns 4` (`TOOLSETS`, `MAXTURNS`), each task in a fresh temp work
dir with a per-task timeout (`TMO`, default 300 s). Results are in `OUTDIR/summary.txt`.

Negative controls: c01 and c02 must FAIL in every run; with `fixture:plain` (a plain answer that
claims success, no tool call) every train and heldout task must FAIL; with `fixture:ref` every
train and heldout task must PASS (a protocol check of runner, Hermes tool execution and verifier,
not a model capability claim).
