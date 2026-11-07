# wpatch

CPU-only checked patches for Drake's OLLMCK02 checkpoints. The product is Omega.
It does not import model weights, run inference, open a GPU, or claim a quality
improvement. Python is an independent acceptance instrument, not a product path.

## Build

From the repository root, with the pinned omega-mv checkout beside it:

```sh
OUT="$HOME/work/wsp/wpatch-build" CORE=0 sh tools/omegallm/wpatch/build.sh
```

`OMC` and `OMEGA_MV` can select the compiler binary and source checkout. The build
checks the compiler and SHA source identities. It composes the existing CPU ollm
sources without changing `native/omegallm`. The SHA layout comes before every
function. The ollm entry point becomes `wpollm`; SHA private symbols receive a
`ws` prefix. The exact source transformation is in `OUT/sha256.diff`.

Compiler: omega-mv `e5b32567a7aff3ce594e3254a622a846a6cd190b`, omc SHA-256
`2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f`.
SHA source: `om/sha256/sha256-om2.om` at that revision, SHA-256
`dbf002dd6aa36585632b9d01d98ac3f0bd2fa0f0475082940de53638847994bb`.

## Commands

```text
wpatch inspect CK
wpatch inspect CK KIND LAYER R0 R1 C0 C1
wpatch diff BASE EDITED POLICY PARAMS_FILE RATIONALE_FILE OUTDIR
wpatch show PATCH
wpatch validate PATCH BASE
wpatch apply PATCH BASE OUT
wpatch verify PATCH CK
wpatch revert PATCH EDITED OUT
wpatch bind PATCH CK RUNTIME_BIN OUT
wpatch checkbind BINDING CK RUNTIME_BIN
```

Indices are zero-based. Slice ends are exclusive. Tensor kinds are `wte`, `wpe`,
`g1`, `wq`, `wk`, `wv`, `wo`, `g2`, `w1`, `w2`, `gf`. Use layer zero for the three
nonlayer tensors. `w1` is D by F and `w2` is F by D, in checkpoint row-major order.
Offsets printed by inspect are flat weight indices, not byte offsets. Decimal
values are diagnostic; the adjacent 16-digit hexadecimal word is authoritative.
Inspect prints all header fields and per-tensor SHA, RMS, maximum absolute finite
value, and nonfinite count. The scaled RMS accumulates finite values, treating
nonfinite values as zero in its full-tensor denominator. Check the nonfinite
count before interpreting either statistic.

`diff` requires matching headers apart from FNV and bit-identical m/v arrays.
It records the changed weight words and applies the requested optimizer policy
to its expected output, not to either input. Policy 0 keeps m/v; policy 1 clears
changed m; policy 2 clears changed m and v. Policies 1 and 2 save old m/v words
for exact rollback. Changes that disappear in f32 remain in the manifest.
Params and rationale are exact UTF-8 file contents, each at most 16 MiB. They may
be empty. Params need not be JSON. OUTDIR must exist. The result path is printed.

`show` emits JSON with identities, policy, total changed count, the first twenty
entries, params and rationale. `validate` checks the base, all entries and tensor
records, and the complete simulated output including its f32 identity. `apply`
writes a new file only after this check and rechecks the written bytes. `verify`
checks an applied checkpoint and reports total edits and edits surviving f32.
`revert` restores the exact old weight and optimizer words and requires the base
SHA to match. All checkpoint-writing commands refresh the payload FNV.

`bind` first verifies the applied checkpoint, then binds checkpoint SHA, f32
weight SHA, runtime executable SHA and manifest SHA in a checksummed record.
`checkbind` checks that record and the checkpoint/runtime identities. It takes no
manifest argument, never rereads the manifest, and cannot detect a replaced
manifest. It also does not load a model or invalidate an existing runtime cache.
A serving caller must retain the intended manifest identity, run checkbind,
discard cached weights and KV state, and load the exact bound files before
claiming a repaired run. Merely creating a binding is not deployment.

No output is overwritten, including a symlink or an output equal to BASE. Patches
and bindings are created read-only. Checkpoints are mode 0600. Inputs are mapped
privately, never written. Keep all inputs and the output directory stable while
a command runs. These are integrity checks, not cryptographic signatures or
protection against a malicious concurrent writer. A crash or forced termination
can leave a partial newly created output; do not use it without verification.

The full binary format, limits and refusal codes are in
[`docs/omegallm/WSP-PATCH.md`](../../../docs/omegallm/WSP-PATCH.md).

## Independent acceptance

Use a new work directory each time:

```sh
taskset -c 0 nice -n 19 python3 tools/omegallm/wpatch/check.py \
  --build "$HOME/work/wsp/wpatch-build" --work "$HOME/work/wsp/ck/wpatch-small-new"
```

The instrument trains an own-model small checkpoint, checks all commands and all
optimizer policies, independently parses and hashes manifests/checkpoints,
checks f32 cast boundaries, and exercises corruptions with exact refusal codes.
It builds expected output bytes directly from BASE and the requested edits,
including optimizer resets, without taking expected values from a manifest.
A fully rehashed manifest for a different finite value passes product verify but
fails this independent byte oracle. That intentional FAIL is marked as a
negative control; the overall acceptance must PASS. JSONL records each command,
exit code and elapsed nanoseconds.

For the pinned round40 fixture, add `--real PATH_TO_ROUND40/model.ck` and use a
separate work directory. It changes ten layer-3 w2 entries in a copy, performs
diff/validate/apply/verify/revert, compares every output byte against the
independently built expectation, and checks restored SHA and expected f32 SHA.
It never writes into the source model directory. For the wsp review rerun, queue
behind other authorized core-19 work:

```sh
flock -w 3600 -o "$HOME/handoffs/hive/queen/pool-19.lock" \
  taskset -c 19 nice -n 10 python3 tools/omegallm/wpatch/check.py \
  --build "$HOME/work/wsp/wpatch-build" --work "$HOME/work/wsp/ck/wpatch-real-new" \
  --real "$HOME/.local/share/omega-tool-model/round40/model.ck"
```

Do not run on reserved cores 3, 7 or 15.

Evidence: `evidence/OMEGALLM/wsp-patch-20261107/`. Host CPU execution is not GPU
qualification, a model-quality result, a merge, or a deployment.
