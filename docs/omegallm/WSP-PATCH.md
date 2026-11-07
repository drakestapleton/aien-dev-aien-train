# Checked weight-space patches

`tools/omegallm/wpatch` implements inspect, diff, show, validate, apply, verify,
revert, bind and checkbind in seeded Omega. This format describes an exact edit,
not a training algorithm or a claim that the edit improves the model.

Base implementation revision: aien-train `0518c915dea370b3bffbb90d579b1daa5ba8b8f5`.
Compiler and SHA implementation: omega-mv
`e5b32567a7aff3ce594e3254a622a846a6cd190b`.
The tool README gives build instructions, commands, source hashes and cache rules.

## Checkpoint convention

OLLMCK02 has fifteen little-endian u64 header words: magic, V, T, D, H, F, L, B,
seed, step, total, learning-rate word, P, G and payload FNV-1a-64. The payload is
P f64 weight words followed by P m words and P v words. This tool preserves all
header words except the refreshed payload FNV. Diff requires BASE and EDITED to
have the same first fourteen header words and identical m/v bytes. It rejects a
no-op diff. It does not change training step or learning rate.

The tied embedding/head `wte[V,D]` comes first, then `wpe[T,D]`. Each layer has
`g1[1,D]`, `wq[D,D]`, `wk[D,D]`, `wv[D,D]`, `wo[D,D]`, `g2[1,D]`, `w1[D,F]`,
`w2[F,D]`. The final tensor is `gf[1,D]`. All are row-major. Flat offsets are
weight-element indices; checkpoint byte offsets are 120 + 8 times that index.
The existing `ogeom` validator is reused, rather than duplicating its limits.

## OLLMWP01 manifest

All integers and f64 bit patterns are little-endian u64. Hashes are raw 32-byte
SHA-256 digests in their normal byte order, never integer words. There is no
padding between the tables or text. A manifest is named `<sha256>.wp` using its
whole-file SHA-256 in lowercase hexadecimal. Every patch-consuming command
recomputes that digest. A filename of 64 hex digits plus `.wp` must match it;
uppercase hex names are recognized but refused as noncanonical. Other filenames
are permitted for transport and corruption diagnostics, without a filename
identity assertion. The digest remains visible through show and bind.

Fixed header, 376 bytes:

| Byte offset | Field |
| --- | --- |
| 0 | ASCII `OLLMWP01` |
| 8 | Total file bytes |
| 16 | Optimizer policy: 0 keep, 1 zero changed m, 2 zero changed m/v |
| 24 | Tensor count, exactly 3 + 8L |
| 32 | Number of changed weight words, nonzero |
| 40 | P |
| 48,56,64,72,80,88 | V,T,D,H,F,L |
| 96 | SHA-256 of complete BASE checkpoint |
| 128 | SHA-256 of expected applied checkpoint, including selected m/v policy |
| 160 | SHA-256 of all expected weights cast to contiguous little-endian f32 |
| 192 | SHA-256 of the exact entry-table bytes |
| 224,232 | Params and rationale byte lengths |
| 240 | Saved checkpoint header length, exactly 120 |
| 248 | Reserved, zero |
| 256 | Exact original 120-byte checkpoint header |

Immediately after the header are tensor records, each 128 bytes, in the canonical
checkpoint order. Kind codes: wte=0, wpe=1, g1=2, wq=3, wk=4, wv=5, wo=6, g2=7,
w1=8, w2=9, gf=10. Every tensor is recorded, including unchanged tensors.

| Record byte offset | Field |
| --- | --- |
| 0,8 | Kind code, layer (zero for nonlayer tensors) |
| 16,24 | Rows, columns |
| 32 | Dtype code, exactly 64 for f64 |
| 40 | Flat weight offset |
| 48 | Changed-entry count in this tensor |
| 56 | Reserved, zero |
| 64,96 | Base and expected output raw tensor-byte SHA-256 |

The entry table follows. Policy 0 entries are 24 bytes: flat index, old f64 bits,
new f64 bits. Policies 1 and 2 entries are 40 bytes: those three words, old m bits,
old v bits. Both saved moment words are present even when only m is reset.
Indices must be strictly ascending and unique. Every index belongs to its
canonical tensor interval, and each tensor's count must agree with the scan.
Old and new words must differ. New values must be finite with absolute magnitude
at most 1e6. Old words may encode any f64, so a broken weight can be repaired and
reverted exactly. New signed-zero changes are valid and retain their exact bits.

Params bytes follow the entry table, then rationale bytes. Both are strict UTF-8;
overlong encodings, surrogates, invalid continuations and incomplete sequences
are refused. NUL is permitted in metadata and escaped by show. Each field is at
most 16 MiB. The length sum must equal the exact file length. The tool's mapped
input ceiling is 2,400,000,000 bytes and entry ceiling is 29,995,392, further
limited by the actual checkpoint geometry. Length checks precede table reads.

## Validation and output behavior

Validate checks checkpoint format, exact size and FNV, manifest geometry, every
tensor shape/dtype/offset, ordered entry membership and count, entries hash,
exact saved base header, full base SHA, tensor hashes, old weight bits and saved
optimizer bits. It applies the entries in a private copy and checks the resulting
full SHA, per-tensor SHA and f32 SHA before reporting PASS. Apply repeats this
path, creates OUT with exclusive creation, writes it, then reopens and hashes it.
A postwrite hash mismatch unlinks the newly created output. No output is silently
reused or overwritten. Revert verifies the edited checkpoint, restores saved
words, refreshes FNV and requires the exact base SHA before and after writing.

F32 identity is SHA-256 over P contiguous little-endian IEEE-754 binary32 values
cast from checkpoint f64 weights with the pinned CPU's round-to-nearest conversion.
It excludes header, m and v. Verify compares f64 checkpoint and f32 identities and
reports how many entries have different old/new f32 bits. Those counts distinguish
an encoded edit from one that survives the deployed weight representation. This
is not evidence that a serving process actually reloaded those weights.

Inputs use private file mappings and must remain stable for the command's entire
lifetime. There is no lock against an external writer. Forced termination can
leave a partial new output, and writes are not an atomic deployment transaction.
Run verify before consuming a checkpoint. Content addressing detects accidental
corruption and binds exact content; it does not authenticate an author.

## OLLMWB01 binding

The 168-byte binding record contains ASCII `OLLMWB01` at offset 0; complete
checkpoint SHA at 8; f32 weight SHA at 40; runtime executable SHA at 72; manifest
SHA at 104; SHA of the preceding 136 bytes at 136. Bind verifies PATCH against CK
before creating the record. Checkbind validates record magic/length/checksum and
CK/runtime identities. It does not take a patch path and does not prove that the
record's patch is trusted. Preserve the canonical manifest alongside the binding.

A consumer must fail closed on checkbind failure, discard previously loaded
weight and KV caches, and load the bound checkpoint with the bound executable.
Changing a manifest, checkpoint or runtime requires a fresh checked binding.
No server, loader or live model is changed by this tool.

## Refusal exit codes

Exit 0 means command success. There is no automatic fallback.

| Exit | Refusal |
| --- | --- |
| 2 | Invalid command, arity or numeric argument |
| 20 | Empty input or checkpoint shorter than header |
| 21 | Input exceeds mapped size ceiling |
| 22 | Checkpoint magic |
| 23 | Unsupported/invalid checkpoint geometry, G or total |
| 24 | Checkpoint P disagrees with geometry |
| 25 | Checkpoint exact payload length |
| 26 | Checkpoint payload FNV |
| 27 | Unknown tensor/layer or invalid slice bounds |
| 30 | Content-addressed manifest filename does not match bytes |
| 31 | Metadata is not strict UTF-8 |
| 32 | Manifest truncated, length mismatch or table bounds |
| 33 | Manifest magic, fixed header length or reserved header word |
| 34 | Unsupported optimizer policy |
| 35 | Zero or excessive manifest edit count |
| 36 | Manifest/base geometry or checkpoint-header mismatch |
| 37 | Tensor order, shape, dtype, offset or reserved word |
| 38 | Flat entry index is out of bounds |
| 39 | Entry indices descend |
| 40 | New weight is NaN |
| 41 | New weight is infinite |
| 42 | New weight magnitude exceeds 1e6 |
| 43 | Duplicate entry index |
| 44 | Entry old bits equal new bits |
| 45 | Tensor changed count disagrees with entries |
| 46 | Entry-table SHA mismatch |
| 47 | Expected old/new weight bits mismatch |
| 48 | Saved or policy-applied optimizer bits mismatch |
| 49 | Tensor SHA mismatch |
| 50 | Input base/applied full checkpoint SHA mismatch |
| 52 | OUT already exists, including symlinks |
| 53 | Generated or written output checkpoint SHA mismatch |
| 54 | F32 weight SHA mismatch |
| 55 | Diff has no changed weight words |
| 56 | Diff EDITED changed m or v |
| 57 | Metadata field exceeds limit |
| 58 | Binding magic or length |
| 59 | Binding checksum |
| 60 | Bound checkpoint SHA mismatch |
| 61 | Bound f32 SHA mismatch |
| 62 | Bound runtime executable SHA mismatch |
| 70 | Open, map, read, write, permission or close I/O failure |
| 71 | Failed to unlink a newly created rejected output |

When an input violates multiple rules, the first check determines the code. For
example, a truncated canonical-name patch can fail filename identity before a
later field check. Noncanonical corruption fixtures in check.py isolate the
individual refusal paths. Omega runtime traps remain nonzero compiler/runtime
errors, not successful refusals; no trap is counted as an expected test result.

## Evidence and dependency boundary

`evidence/OMEGALLM/wsp-patch-20261107/` records host CPU execution, the source
composition diff, exact identities, small acceptance and round40 rollback.
All product transformations and hashing are Omega. Build orchestration currently
uses dash 0.5.12-6ubuntu5, sed 0.1.1, git 2.43.0, sha256sum 0.8.0, diff
(pi-uu-diff) 0.8.0, taskset util-linux 2.39.3 and GNU nice 9.4. The shell composition
role is the existing build path; its Omega replacement would be a bounded source
composer, not a hidden host implementation of checkpoint editing. The compiler
is a pinned verification/build tool. Python 3.12.3 and hashlib/struct/mmap are
external acceptance oracles only. No new host library enters the product runtime.

WolframLanguageEvaluator checks used during implementation:

```text
FromDigits[Reverse[ToCharacterCode["OLLMWP01"]],256] -> 3544421242629803087
FromDigits[Reverse[ToCharacterCode["OLLMWB01"]],256] -> 3544405849467014223
With[{v=256,t=8,d=16,f=32,l=2},v*d+t*d+l*(4*d*d+2*d*f+2*d)+d] -> 8400
With[{v=4096,t=256,d=384,f=1536,l=8},
 {v*d+t*d+l*(4*d*d+2*d*f+2*d)+d,
  v*d+t*d+3*(4*d*d+2*d*f+2*d)+2*d+4*d*d+d*f}]
 -> {15833472,8162304}
FullSimplify[(m^2*s+a^2)/a^2,Assumptions->{a>m>0,s>=0}]
 -> 1 + (m^2*s)/a^2
FullSimplify[Sqrt[m^2*s/n],Assumptions->{m>=0,s>=0,n>0}]
 -> m*Sqrt[s/n]
```

The last two identities justify the scaled RMS accumulator, which avoids
squaring the largest finite f64. Evidence labels remain separate: this tool is
IMPLEMENTED and host-CPU EXERCISED. GPU qualification, model-quality improvement,
merge and deployment are not established by these receipts.
