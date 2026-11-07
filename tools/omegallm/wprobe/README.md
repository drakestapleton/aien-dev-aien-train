# wprobe: look inside the Omega model and try edits without changing any file

`wprobe` is an Omega (`.om`) tool for the Omega LLM checkpoints (OLLMCK02). It answers three questions:

1. What does the model write for these prompts? (`gen`)
2. When it writes the wrong token, which parts of the model pushed it there? (`probe`)
3. What happens if we turn one part of the model up or down? (hooks on `gen` and `probe`, and `save`)

It never changes the checkpoint it reads. `save` writes a new file and refuses to overwrite one.

## Build

```sh
OUT=~/work/wsp/build OMC=<omc pinned in tests/omegallm/build.sh> sh tools/omegallm/wprobe/build.sh
```

The build makes `ollm.om` with `tests/omegallm/build.sh` if `OUT` has none, renames its `main`, appends
`wprobe.om` and compiles. It prints the binary's sha256 and the compiler's sha256.

## Records file

Plain bytes. Each record ends with byte 0. A record is the prompt, and for `probe` also byte 31 and
the expected answer. `evidence/OMEGALLM/wsp-dra187-20261107/make_splits.py` shows how to write one.

## Commands

| Command | What it does |
|---|---|
| `wprobe gen CK MERGES N FILE [hooks]` | greedy answer of up to N tokens for every record; the same bytes as `ollm sample CK 0 N 0 PROMPT MERGES`, about 18 times faster because earlier rows are reused |
| `wprobe probe CK MERGES FILE [hooks]` | feeds the expected answer; at the first token the model gets wrong, splits the logit gap between the right and the wrong token into embedding, each head, each MLP and the 16 largest neurons per MLP, and lists where the strongest heads look |
| `wprobe save CK OUT [hooks]` | applies weight hooks and writes OUT (same header, same optimizer state) |

## Hooks

Groups of four numbers `K L I A`, at most 64 groups. A is in thousandths (1500 means 1.5).

| K | Meaning | Kind |
|---|---|---|
| 1 | multiply the output rows (`wo`) of head I in layer L by A | weight edit |
| 2 | multiply neuron I's output row (`w2`) in layer L by A | weight edit |
| 3 | multiply head I's output in layer L by A, only on the answer rows | activation test |
| 4 | subtract A from the score of token I when the previous token is a digit | decoding change |
| 5 | round every weight to f32 (L 0, I 0, A 0), the GPU runtime's representation | representation |

## Exit codes

0 success; 2 bad arguments or a hook outside its range; 60 the checkpoint needs bank-B pools (layers
past the bank-A capacity), which wprobe does not handle; 61 records file or record too long; 62 the
context window is full; 63 `save` output exists; 64 a weight not finite or over 1e6; 70 I/O; the
checkpoint loader's own codes (10 to 15) for a bad checkpoint.

## Checks

`python3 tools/omegallm/wprobe/check.py BUILD` is an independent outside check of `save` (8 cases,
including every refusal). Parity of `gen` with `ollm sample` and the readout sum are recorded in
`evidence/OMEGALLM/wsp-dra187-20261107/`.
