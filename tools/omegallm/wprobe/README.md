# wprobe: look inside the Omega model and try edits without changing any file

`wprobe` is an Omega (`.om`) tool for the Omega LLM checkpoints (OLLMCK02). It answers these questions:

1. What does the model write for these prompts? (`gen`)
2. When it writes the wrong token, which parts of the model pushed it there? (`probe`, summed up by `rank`)
3. What happens if we turn one part of the model up or down? (hooks on `gen` and `probe`, and `save`)
4. Is the effect of an edit specific, or would any edit of the same size do it? (`controls`)
5. Does an edit stay put when training continues? (`survive`)

It never changes the checkpoint it reads. `save` writes a new file and refuses to overwrite one.

## Build

`ollm.om` comes from `tests/omegallm/build.sh` (it writes `OUT/ollm.om` beside `OUT/ollm`). Then, with
the pinned omc and the Omega build driver in `tools/omegallm/wdrive/`:

```sh
OMC=<omc pinned in tests/omegallm/build.sh> CORE=0 wbuild OUT/wprobe OUT/ollm.om@ollmmain tools/omegallm/wprobe/wprobe.om
```

`wbuild` renames `ollm.om`'s `main` to `ollmmain`, appends `wprobe.om`, compiles and prints the binary's,
the composed source's and the compiler's sha256. How to bootstrap `wbuild` is in
`tools/omegallm/wdrive/README.md`.

## Records file

Plain bytes. Each record ends with byte 0. A record is the prompt, and for `probe` also byte 31 and
the expected answer. `tools/omegallm/wsplit` writes them.

## Commands

| Command | What it does |
|---|---|
| `wprobe gen CK MERGES N FILE [hooks]` | greedy answer of up to N tokens for every record; the same bytes as `ollm sample CK 0 N 0 PROMPT MERGES`, about 18 times faster because earlier rows are reused |
| `wprobe probe CK MERGES FILE [hooks]` | feeds the expected answer; at the first token the model gets wrong, splits the logit gap between the right and the wrong token into embedding, each head, each MLP and the 16 largest neurons per MLP, and lists where the strongest heads look |
| `wprobe save CK OUT [hooks]` | applies weight hooks and writes OUT (same header, same optimizer state) |
| `wprobe rank META PROBE.out` | sums up a `probe` output: exact answers by role and length from META (lines `idx role length kind`), then over the rows that fail on a digit the mean gap and the mean part of every head, MLP and neuron, strongest first |
| `wprobe controls CK SEED [hooks]` | for a selected weight edit (kinds 1 and 2), draws the same number of other heads or neurons in the same layers and scales them so the change has the same size (Frobenius norm within 1%); prints the control arm line |
| `wprobe survive BASE EDIT BASE1 EDIT1 [EDIT2]` | after BASE and EDIT both took one training step (BASE1, EDIT1), how much of the edit is left: `<d1,d0>/<d0,d0>` over the changed weights, and the largest relative change |
| `wprobe rng SEED N` | the first N outputs of the random generator `controls` uses (MT19937 seeded as CPython's `random.Random(SEED)`) |

## Hooks

Groups of four numbers `K L I A`, at most 64 groups. A is in thousandths (1500 means 1.5). Instead of
typing them, give one last argument `@PATH`: the same numbers in a file, separated by spaces or newlines.
A program started from Omega can pass at most 64 arguments in total, so large edits need the file form.

| K | Meaning | Kind |
|---|---|---|
| 1 | multiply the output rows (`wo`) of head I in layer L by A | weight edit |
| 2 | multiply neuron I's output row (`w2`) in layer L by A | weight edit |
| 3 | multiply head I's output in layer L by A, only on the answer rows | activation test |
| 4 | subtract A from the score of token I when the previous token is a digit | decoding change |
| 5 | round every weight to f32 (L 0, I 0, A 0), the GPU runtime's representation | representation |

## Exit codes

0 success; 2 bad arguments or a hook outside its range; 60 the checkpoint needs bank-B pools (layers
past the bank-A capacity), which wprobe does not handle; 61 records file, record or input too long (or
a short read in `survive`); 62 the context window is full; 63 `save` output exists; 64 a weight not
finite or over 1e6; 65 `rank`: the probe output and META disagree on the record count; 66 `controls`:
the size could not be matched within 1% or the scale is outside 0 to 4; 67 `survive`: parameter counts
differ or EDIT2's weights differ from EDIT's; 68 `survive`: EDIT equals BASE; 70 I/O; the checkpoint
loader's own codes (10 to 15) for a bad checkpoint.

## Checks

`wcheck BUILD` (`tools/omegallm/wdrive/wcheck.om`) is an independent outside check of `save` (8 cases,
including every refusal). Parity of `gen` with `ollm sample` and the readout sum are recorded in
`evidence/OMEGALLM/wsp-dra187-20261107/`.
