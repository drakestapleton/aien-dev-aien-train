# Operator guide: checked weight edits for the Omega LLM

Status: tools IMPLEMENTED and EXERCISED on CPU. No edited checkpoint is deployed anywhere.

This guide is for the person who looks after the model. It covers the life of one weight edit: find it,
write it as a checked patch, check it, apply it, verify it, tie it to the program that will run it, roll it
back, and the rules for promoting it. Every step runs on the CPU and only ever writes new files.

Two Omega tools do the work:

- `wprobe` (`tools/omegallm/wprobe/`) looks inside the model and tries an edit in memory. Its `save` command
  writes the edited checkpoint as a new file.
- `wpatch` (`tools/omegallm/wpatch/`) turns "base checkpoint plus edited checkpoint" into a small sealed
  patch file, and checks, applies and reverses it exactly.

Build both first (each README has the one-line build). Heavy commands take a pool core:
`flock -w 3600 -o ~/handoffs/hive/queen/pool-19.lock taskset -c 19 nice -n 10 <command>`.

## 1. Inspect

```sh
wpatch inspect BASE.ck
```

This prints the model's shape, its training step and, for every weight table, a fingerprint, its size and the
count of broken (not-a-number) values. That count must be 0. Keep the base checkpoint's sha256: everything
after this point is tied to it.

## 2. Find what pushes the wrong answer

```sh
wprobe probe BASE.ck MERGES RECORDS > PROBE.out
wprobe rank META PROBE.out
```

`probe` feeds each record's right answer and, at the first token the model gets wrong, splits the gap between
the right and the wrong token into the share of every head, every MLP and its strongest neurons. `rank`
averages those shares over the rows that fail on a digit and lists the parts that push hardest each way.
META has one line per record, `idx role length kind`. Test a suspect before editing weights: hook kind 3
turns a head up or down in memory only, and the right answers should move with it.

## 3. Make the edit

```sh
wprobe save BASE.ck EDITED.ck K L I A [K L I A ...]
```

Hook kinds 1 (scale a head's output rows) and 2 (scale one neuron's output row) are weight edits. `save`
refuses to overwrite a file (exit 63), refuses activation or decoding hooks (exit 2), and refuses a result
with a broken or huge value (exit 64). It keeps the header and the optimizer state as they were.

## 4. Check that the edit is specific

```sh
wprobe controls BASE.ck SEED K L I A [K L I A ...]   # seeds 187101, 187102, 187103
```

For the same edit, `controls` picks other heads or neurons in the same layers and scales them so the change
has the same size. Run the evaluation on each control arm it prints. If the controls help as much as the edit,
the edit is not doing what the diagnosis says.

## 5. Write the patch

```sh
wpatch diff BASE.ck EDITED.ck POLICY params.txt rationale.txt PATCHDIR/
```

`params.txt` holds the exact hook arguments; `rationale.txt` says in one paragraph why the edit exists and
which receipts back it. POLICY says what happens to the optimizer's memory for the changed weights if
training continues later: 0 keep, 1 clear the first moment, 2 clear both. Use 2 for an edit that will be
fine-tuned further (stale momentum would push the edited weights back); use 0 when the checkpoint will only
be served. The patch is named after its own sha256, so the name is its identity.

## 6. Check before use

```sh
wpatch show PATCH.wp          # what it changes, the parameters and the rationale, as JSON
wpatch validate PATCH.wp BASE.ck
```

`validate` confirms the patch belongs to this exact base, every changed weight is in range and was what
the patch expects before the change, the new values are finite, and the whole result, including its f32
copy (the form the GPU runtime loads), hashes to what the patch promises.

## 7. Apply and verify

```sh
wpatch apply PATCH.wp BASE.ck APPLIED.ck
wpatch verify PATCH.wp APPLIED.ck
```

`apply` writes a new file only, rechecks the written bytes and deletes the file on any mismatch. `verify`
reports how many changed weights survive rounding to f32. If that number is 0, the GPU runtime would serve
the base model unchanged.

## 8. Bind to the runtime, and clear caches

```sh
wpatch bind PATCH.wp APPLIED.ck RUNTIME_BINARY BINDING
wpatch checkbind BINDING APPLIED.ck RUNTIME_BINARY
```

A binding records which checkpoint, which f32 weights, which runtime program and which patch belong
together. `checkbind` takes no patch argument, so it cannot notice a replaced patch file; keep patches
read-only and compare names. Neither command touches a running server. Before anyone claims "the server
runs the repaired model", the serving side must run `checkbind`, throw away cached weights and cached
conversation state (the KV cache), load exactly the bound files, and only then answer.

## 9. Roll back

```sh
wpatch revert PATCH.wp APPLIED.ck RESTORED.ck
sha256sum BASE.ck RESTORED.ck      # must be identical
```

`revert` puts back the exact old weights and optimizer words, byte for byte. Measured on the round40 model
(380,003,448 bytes): the restored file hashes to the base, `7c7b5b52…e346`. To roll back a server, point it
at the base checkpoint again and repeat the cache clearing in step 8.

## 10. Check that the edit survives training

```sh
wprobe survive BASE.ck EDITED.ck BASE-STEP.ck EDITED-STEP.ck [EDITED-OTHER-POLICY.ck]
```

Train the base and the edited checkpoint one more step each (`tools/omegallm/wdrive` has the driver), then
`survive` reports how much of the edit is left: 1 means fully kept, 0 means training erased it. If a later
training round would start from this checkpoint, a low number means the repair would have to be redone.

## 11. Promotion rules

An edit is a candidate, never a deployment, until all of these hold, in this order:

1. Its preregistered held-out evaluation passed (for DRA-187: `evidence/OMEGALLM/wsp-dra187-20261107/PREREG.md`).
2. The round40 retention gates ran on the GPU under a posted reservation and passed. NOT_RUN blocks promotion.
3. An independent review approved the evidence.
4. The serving owner (lane ownmodel for :18091) accepts it. This lane never changes :18091.

Report each of these as MEASURED, PENDING or NOT_RUN. "The patch applies" proves only that the file is
correct, not that the model got better.
