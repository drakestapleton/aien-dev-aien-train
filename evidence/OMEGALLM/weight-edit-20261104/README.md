# Direct checkpoint edits: marginal gain, no substantive upgrade

Status: EXERCISED on one GB10. No speed or general hardware-qualification claim.
The operator authorized direct weight experiments. Original checkpoints, training state,
harnesses, service routes and installed skills were not replaced.

The first fixed search selected 95% of the rung-10 final BF16 weights plus 5% of
its step-30000 weights, with no final-gain scaling. Fresh final loss fell from
1.210473 to 1.210277 nats/token (0.016192%); published held loss fell from
1.204466 to 1.204325. Fifteen of sixteen paired final blocks improved; one worsened.
The greedy 40-token continuation of the fixed prompt was identical. The gain is
below the preregistered 0.1% preference for a substantive upgrade. Retain this copy
as an optional inference experiment, not the recommended continuation checkpoint.
Its SHA256 is `131f7e3f26f5494a9882d8107096d4209651978a5bf35eccb3f953203d1f07d6`.

## First search

| Alpha | Final gain | Calibration loss (micronats/token) |
|---:|---:|---:|
| 1000/1000 | 1000/1000 | 1203286 |
| 900/1000 | 1000/1000 | 1203611 |
| 950/1000 | 1000/1000 | 1203149 |
| 1050/1000 | 1000/1000 | 1204058 |
| 1100/1000 | 1000/1000 | 1205527 |
| 950/1000 | 900/1000 | 1212338 |
| 950/1000 | 950/1000 | 1204743 |
| 950/1000 | 1050/1000 | 1206428 |
| 950/1000 | 1100/1000 | 1213711 |

## Second, independent search

After the marginal first result, a separate final search used fresh, disjoint reserve
stories and blended the completed BF16 and f32 siblings. They shared initialization,
data and schedule; they are distinct numerical trajectories. Every blend worsened
calibration loss. The unmodified BF16 baseline won, so the subsequent final and
block rows compare the same checkpoint with itself. Those identity rows do not
establish an edited-model improvement. No further search was performed.

| BF16 fraction | f32 fraction | Calibration loss (micronats/token) |
|---:|---:|---:|
| 1000/1000 | 0/1000 | 1196691 |
| 900/1000 | 100/1000 | 1290081 |
| 750/1000 | 250/1000 | 2013795 |
| 500/1000 | 500/1000 | 3451507 |

## Validation and interpretation

- Native Omega performs all weight arithmetic and checkpoint serialization.
- Independent small-model reference cases, no-op byte identity, damaged-checkpoint,
  incompatible-shape, out-of-range and overwrite refusals passed. The editor range
  expanded to alpha 500..1200 before the second experiment; gain stays 800..1200.
- Independent full-size calculations checked all 15,833,472 weights in the selected
  first-round model and the 90% BF16 sibling blend: zero mismatches. Optimizer bytes
  were unchanged. This rules out an edit arithmetic error as the cause of the poor blend.
- The original published baseline score was reproduced, and the baseline and selected
  CPU/GPU spot checks agreed within 10 micronats (differences at most 1).
- Each study used 2,048 calibration stories and 4,096 different final stories. They were
  reserved during data preparation. The audit excluded lowercase/whitespace-normalized
  exact matches to training text, published evaluation text, and earlier-study selections.
  Semantic near-duplicates are not ruled out. This is a TinyStories result, not a
  reasoning, coding, instruction-following, or broad conversational evaluation.
- The edited copy retains historical optimizer state for provenance. It is not a
  tested state for continued training. Continue training from the untouched baseline.

## Provenance and retained records

Base source: `56cc88706a9a685ed9c5dae8050e4643cc7f1aae`.
First editor source: `c530c5e`; second editor source: `7683595`.
Both use compiler SHA256 `2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f`.
The unchanged scoring binary is the rung-10 GPU binary
`54fb8233c62a13c0b3bac13a38dd5b583943e9e9097342baaa57fc22db2ceb49`.

`round*-PREREG.md` records each fixed procedure. The local preregistration hashes in
`round*-manifest.json` identify original files; public copies use path aliases and
omit the private operator quote, so they have different file hashes. Each selection
was locked before its final evaluation. `round*-commands.json` retains commands,
return codes, timestamps and scores; `round*-native-lines.txt` retains numerical
program output. `round*-results.json` retains final blocks, and manifests retain
binary/source hashes. Story index lists and source hashes permit reconstruction of
the exact partitions without publishing the text. Calculations used Wolfram; the
queries, units and results are retained here.

Path aliases in copied receipts: `$RUN1` and `$RUN2` are the two private experiment
directories; `$DATA` holds the original tokenizer/data; `$R10` and `$R8` are retained
training-run directories. Only those path strings are normalized. Checkpoints remain
outside Git. Local full records, source scripts, data and candidate files are preserved.

GPU windows: `20261104T152014Z-055e87` and `20261104T152457Z-efc0d9`, both shared,
without a quiet-machine lock. No new training or shared-model service changes occurred.
