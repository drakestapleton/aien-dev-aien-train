# Public OpenWALDO record exchange pilot

This bounded host pilot imports one public schema-1 pretrain JSONL record,
retains its complete original bytes and provenance, extracts compact Omega,
resolves a pinned catalog, compiles and executes the expanded unit, and exports
the original JSONL byte for byte. It produces a hash inventory connecting the
original, imported and exported records, compact and expanded source, catalog,
lock, resolution map, compiler, resolver, exchange executable and compiled program.

It is an interchange smoke test. It does not admit data to training, retrieve
an indexed corpus, validate a complete OpenWALDO BOM, train a model or alter a
runtime. `kind: pretrain` is the upstream interchange type, not permission to
train. Both provenance documents explicitly mark this fixture ineligible for
training and evaluation. The fixture is authored here; no benchmark prompts,
solutions, held-out tasks, transcripts or private data are inputs.

## Run

Supply an Omega checkout at `049356cbf40e7238fa1c206a9f58f58d60575bdd`.
The build extracts its dependencies directly from Git objects, so dirty worktree
copies cannot silently substitute the compiler, resolver or catalog.

```sh
sh tools/openwaldo/build.sh /path/to/omega /new/build
python3 tools/openwaldo/test.py /new/build/exchange tools/openwaldo/public.jsonl
sh tools/openwaldo/pilot.sh /new/build /new/exchange
```

Both output directories must be new. On failure discard only those outputs;
`RECEIPT.json` is written only after all steps pass. Never treat a partially
written output directory as a completed exchange. `SHA256SUMS` is the artifact
inventory, not a signature or legal proof. The entry point accepts no corpus
argument and reads only the checked-in public smoke fixture.

`exchange import`, `exchange export` and `exchange extract` use stdin/stdout.
Import and export validate then preserve the full input bytes. Extract writes
the decoded `text` field. The utility accepts exactly one LF-terminated record
smaller than 16384 bytes, rejects embedded raw newlines and duplicate top-level
keys (including escaped equivalents), requires nonempty string `sha256`, `kind`,
`text`, `source` and `license`, and accepts only `kind=pretrain`. It computes the
decoded text's SHA-256 in Omega and matches lowercase hex. Valid unknown fields
and metadata are preserved unchanged. It does not enforce every upstream
optional-field invariant, license policy, token count, privacy policy or BOM
relationship. It is not a general corpus validator or conversation adapter.

Refusals: 20 usage, 21 required string, 22 size/line framing, 23 JSON, 24 duplicate
key, 25 unsupported kind, 26 decoded text, 27 SHA-256, 90 I/O. A validation refusal
emits no bytes. Consumers must also check process exit status for I/O failures.

## Pinned upstream contract

Read at OpenWALDO commit `cec5e69c306460ba0c89aa0d1e6a0c9d95c4f0f0`:

- [Corpus export BOM contract](https://github.com/openwaldo/waldo/blob/cec5e69c306460ba0c89aa0d1e6a0c9d95c4f0f0/docs/OPENWALDO-BOM.md):
  `e8404f11e376eb8dba09989503aeed1fb0e8f3bd4796fa89e056249bb3721de3`.
- [Model export contract](https://github.com/openwaldo/waldo/blob/cec5e69c306460ba0c89aa0d1e6a0c9d95c4f0f0/docs/MODEL-EXPORTS.md):
  `41f0c25c6744c4eb4415910a1c69dcfa93cf99fee40ed90e7a25115735128a3f`.
- [Canonical record implementation](https://github.com/openwaldo/waldo/blob/cec5e69c306460ba0c89aa0d1e6a0c9d95c4f0f0/internal/record/record.go):
  `bc8c4788b6eb3edc5c0164880c095f021f37ca7966234b7cc0f38f4814a25713`.

The official `EXPORT.json` envelope retains the resolved corpus BOM separately
from exported file identities. This pilot does not manufacture that envelope:
its authored fixture has no original indexed export BOM. `ORIGIN.json` states
that absence explicitly. Unknown record fields remain byte-identical; they do
not disappear during parsing or reserialization.

`oracle.go` is a test-only adapter for the pinned upstream `record.Record`
implementation. In a scratch checkout of that exact upstream commit, copy it
to `cmd/aien-pilot-oracle/main.go`, then run:

```sh
GOMAXPROCS=1 go run -p=1 ./cmd/aien-pilot-oracle /new/exchange/exported.jsonl
```

It calls upstream `Validate` through `AppendCanonical` and requires exact output
bytes. It is never linked into the Omega implementation. Python is also only a
host test oracle. No Go or Python trainer is installed or invoked.

## Reuse and compatibility limits

The implementation reuses `native/omegallm/net/json.om`, the existing strict
Omega JSON reader. SHA-256, catalog resolver, total catalog, lock and compiler
come from the pinned Omega tree. The corpus/data branch contains a historical
Python extractor and Rust BPE tokenizer, not a provenance-preserving Omega
exchange; the DRA-146 corpus branch also contains no OpenWALDO adapter. Local
current source, these branches and shared ownership were inspected. GitHub code
search was unavailable under the existing host guard, so no remote-search
completeness is claimed.

Model conversion is **REFUSED_ARCHITECTURE_TOKENIZER_NOT_SUPPORTED**. The pinned
WALDO derived exports require the standard supported Llama mapping and
`byte@builtin-byte-schema-1` vocabulary 259. Existing OLLM contracts describe
byte vocabulary 256 or its own BPE up to 4096. A vocabulary number or tensor
shape alone cannot prove token IDs, special tokens, positional behavior or
architecture parity. No exact adapter is established, so no weights were loaded,
converted or exported. The next work would need an independently verified exact
architecture/tokenizer adapter before any conversion experiment.
