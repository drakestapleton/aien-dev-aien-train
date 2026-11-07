# wpatch

CPU-only checked patches for Drake's OLLMCK02 checkpoints. The product, its build
driver and its test driver are Omega. It does not import model weights, run
inference, open a GPU, or claim a quality improvement. One small Python file is a
labeled ORACLE (a digest calculator); it is not part of the product or the build.

## Files

| File | Role |
| --- | --- |
| `wpatch.om` | The product: inspect, diff, show, validate, apply, verify, revert, bind, checkbind. |
| `wpbuild.om` | Omega build driver. Builds `wpatch` and `wpcheck`. |
| `wpcheck.om` | Omega test driver. Runs every case, owns all exit codes, files, refusals and PASS/FAIL. |
| `wporacle.py` | ORACLE only. Answers digest requests from wpcheck; never decides PASS or FAIL. |

## Build

From the repository root, with the pinned omega-mv checkout beside it, compile
the build driver once with the pinned compiler and run it:

```sh
OMC=../omega-mv/seed/out/omc
taskset -c 0 nice -n 19 "$OMC" < tools/omegallm/wpatch/wpbuild.om > /tmp/wpbuild && chmod +x /tmp/wpbuild
taskset -c 0 nice -n 19 /tmp/wpbuild . "$HOME/work/wsp/wpatch-build" "$OMC" ../omega-mv 0
```

Arguments are `REPO OUT OMC OMEGA_MV CORE`; all five are required. OUT is created
when absent. The driver:

1. builds ollm with the repository's `tests/omegallm/build.sh` (TARGET=aarch64),
   which checks the compiler pin and writes `OUT/ollm.om` and `OUT/ollm`;
2. extracts `om/sha256/sha256-om2.om` at the omega-mv pin with git and requires
   its SHA-256 to equal the pin below;
3. vendors it in Omega: the SHA layout goes before every function, `export fn`
   becomes `fn`, and SHA private symbols receive a `ws` prefix. The exact source
   transformation is written to `OUT/sha256.diff` as a review record;
4. composes `OUT/wpatch-all.om` (SHA layout, ollm with its entry point renamed
   `wpollm`, SHA functions, `wpatch.om`) and `OUT/wpcheck-all.om` (SHA layout, SHA
   functions, `wpcheck.om`);
5. compiles both on CORE, then prints the SHA-256 of the compiler, the SHA source,
   both compositions and both binaries, and ends with `WPBUILD PASS`.

Exit codes: 0 PASS, 2 usage, 3 SHA source digest differs from the pin, 4 the
ollm source does not hold exactly one `fn main to int`, 5 I/O or capacity, 6 a
host tool failed (its status is printed), otherwise the compiler's own status.
`native/omegallm` is never changed. The `wpatch` binary and `wpatch-all.om` are
byte-identical to the earlier shell build (SHA-256 below).

Compiler: omega-mv `e5b32567a7aff3ce594e3254a622a846a6cd190b`, omc SHA-256
`2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f`.
SHA source: `om/sha256/sha256-om2.om` at that revision, SHA-256
`dbf002dd6aa36585632b9d01d98ac3f0bd2fa0f0475082940de53638847994bb`.
wpatch: SHA-256 `bf993a780c7421cc2cd23d42fef5692135e9bd339f19a90059d4ef7f17be0847`,
from `wpatch-all.om` SHA-256 `7e8b3ca2cf378af25029ce42ca6c760c880fa3612691216e2f2339c369c22591`.

Host tools the build driver runs (pinned build tools, not product code): the
compiler, `/bin/sh` for `tests/omegallm/build.sh`, `/usr/bin/env`, git,
sha256sum, diff, taskset and nice.

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

## Acceptance: wpcheck

`wpcheck` is built by wpbuild into the same OUT directory. WORK must not exist;
wpcheck creates it. ORACLE is the path of `wporacle.py`.

```sh
B="$HOME/work/wsp/wpatch-build"
taskset -c 0 nice -n 19 "$B/wpcheck" small "$B" "$HOME/work/wsp/ck/wpatch-small-new" \
  tools/omegallm/wpatch/wporacle.py
```

Exit codes: 0 PASS, 1 FAIL (the first failed check is printed and the run stops),
2 usage. Output is plain text: a header with the Omega SHA-256 of the wpatch under
test; for each child process its argument list, its stdout as `| ` lines, and
`EXIT got=X want=Y elapsed_ns=T`; one `PASS label` line per check; and a last line
`WPCHECK PASS checks=N commands=M` or `WPCHECK FAIL ...`. Children run through
fork, execprog and waitpid with an empty environment and stdout captured through
a pipe.

The small mode trains an own-model small checkpoint, runs every command and all
three optimizer policies, parses every manifest, tensor record, entry and binding
field, checks f32 cast boundaries, and exercises each corruption with its exact
refusal code and no output left behind. It builds the expected output bytes
directly from BASE and the requested edits, including optimizer resets, without
taking expected values from a manifest. A fully rehashed manifest for a different
finite value passes product verify but is rejected by this independent byte
comparison; that in-run negative control must be rejected for the run to PASS.

The real mode takes the pinned round40 checkpoint as a fifth argument. It
requires the pinned base SHA-256, changes ten layer-3 w2 entries in a copy,
performs diff/validate/apply/verify/revert, compares every output byte against the
independently built expectation, and checks the restored SHA and expected f32 SHA.
It never writes into the source model directory. Queue behind other authorized
core-19 work:

```sh
flock -w 3600 -o "$HOME/handoffs/hive/queen/pool-19.lock" \
  taskset -c 19 nice -n 10 "$B/wpcheck" real "$B" "$HOME/work/wsp/ck/wpatch-real-new" \
  tools/omegallm/wpatch/wporacle.py "$HOME/.local/share/omega-tool-model/round40/model.ck"
```

Do not run on reserved cores 3, 7 or 15.

## ORACLE

`wporacle.py` (Python 3.12.3 standard library: hashlib, struct, mmap) is the only
Python. It is an ORACLE: wpcheck writes a request file, runs
`/usr/bin/python3 wporacle.py REQUEST`, and compares each answer line itself. It
answers three requests: SHA-256 of a byte range, SHA-256 of the IEEE f32 casts of
the checkpoint weights, and a count of entries whose old and new values differ
after the f32 cast. It shares no code with wpatch or wpcheck, and nothing in the
product or the build calls it. Any malformed request makes it exit nonzero, which
wpcheck reports as FAIL.

Evidence: `evidence/OMEGALLM/wsp-patch-20261107/pure-omega/`. Host CPU execution is
not GPU qualification, a model-quality result, a merge, or a deployment.
