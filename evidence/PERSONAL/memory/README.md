# DRA-146 personal memory: evidence

Aggregate-only. No private text: the private store, its curation and the private eval rows stay under the
private DRA-146 directory and are not in this repository.

## What this is

`native/personal/mem.om` is an editable personal memory. It is derived from the ChatMemory `mem.om`
(chatlog-personalization-20261105). It keeps that file's BM25 ranking and parameters (k1 1.2, b 0.75,
coverage tau 0.5, FNV-1a 64 tokens) and adds a supersession layer:

- **Store:** an append-only TAB log `op rid ts kind key value prov target`. Ops are `add`, `correct` (supersedes `target`) and `retract`.
- **Kinds:** `preference | decision | fact | correction | project_fact`.
- **Provenance:** `conv_id:record_id:sha256`. It holds an id only, never text.
- **Resolve:** a record linked by `correct` is superseded, and one linked by `retract` is retracted. Within one identity (kind + normalized key), only the newest explicitly active record by (ts, rid) stays active. Every rebuild from the log is deterministic.
- **Query:** BM25 top-k runs over active records only. A strongly matching superseded record is reported as `superseded: ... -> now: <chain end>`, or `-> retracted`. It is never reported as current. The block is at most 600 bytes and holds whole lines only.
- **CLI:**
  - `mem add|correct|retract|query|hits|history|dump|check STORE ...`
  - The eval uses `mem query STORE K TEXT`.

## Tests

The tests are `tests/personal/build-mem.sh` and `tests/personal/mem-check.sh`, with output in `mem-check.txt`.

- **Pinned omc:** 2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f
- **Builds:**

  | build | sha256 | source sha256 |
  |---|---|---|
  | `mem` | 792d522d34054f6bea60ff23c812db0d80d1812efff87a3c47fcd6cb2fe2f6d2 | 1d46f4a2… |
  | `mem-nosup` (negative control: `OMSUP 0`, one line changed) | 1dd703f5a5f23e9522ba2d109dade72fb7ab9d1f8706f63bf51c3609ec7797ef | — |

- **Result:** 29 PASS, `MEM_PASS`, rc 0. All data is synthetic.
- **Cases covered:**
  - stale preference
  - chained supersession
  - chain ending in a retraction
  - retract
  - same-ts tie (larger rid wins)
  - key collision across kinds
  - query matching only the old text
  - unicode, and a cut on a UTF-8 boundary
  - empty store and missing store
  - the 600-byte block cap
  - history
  - deterministic rebuild
  - refused edits leave the store byte-identical
- **Negative control:** 6 of 6 supersession cases FAIL with `mem-nosup`, which returns the stale value as current.

## Lean

`proofs/personal/MemSupersession.lean` is core Lean 4 with no sorry. Axioms are listed in `lean-axioms.txt`; each theorem uses a subset of `propext`, `Classical.choice` and `Quot.sound`.

**Proved theorems:**
- `retrieve_key`, `retrieve_active`
- `retrieve_never_superseded`: never returns a superseded or retracted record.
- `retrieve_max`: the returned record is the max-(ts, rid) active record of its key.
- `retrieve_unique`: there is one current record per key.

**Negative controls, also proved:**
- `nosup_returns_superseded`: retrieval without supersession returns a superseded record.
- `nostatus_returns_retracted`: newest-per-key without status returns a retracted record.

**Limit:** these theorems are about the model. The link from the model to `mem.om` is stated in the file header and was checked by reading, not mechanically.

## Private runs (aggregates only)

**Store v1.** 48 curated records, all from Drake's own dated words in TRAIN-period conversations (start < 2026-10-29T00:00Z).

| kind | active | superseded | retracted |
|---|---|---|---|
| preference | 14 | 9 | 0 |
| decision | 9 | 5 | 0 |
| correction | 7 | 3 | 0 |
| project_fact | 0 | 1 | 0 |
| fact | 0 | 0 | 0 |
| **total** | **30** | **18** | **0** |

**Stale-preference eval.** 16 items, sealed before the run. Each item is a question, its current answer and its superseded answer, from TRAIN.

| measure | result |
|---|---|
| superseded answer returned as current | 0/16 |
| current answer present in the k=3 block | 9/16 = 0.5625 |
| block size | max 309 bytes |
| exit codes | all 0 |

In the other 7 items no current record ranked in the top 3 for the question's wording. They are retrieval-recall misses, not staleness errors.

**ChatMemory rebuild.** This resolves the earlier INCONCLUSIVE result.
- `mem build` on the current ChatCorpus (turns sha256 66a60083…, split 78958458…) with the ChatMemory pinned omc. The binary is byte-identical to the shipped `mem` (f56a7860…).
- The rebuilt index is byte-identical to the shipped `train.idx` (bbb39d0d…): 11094 docs, 3044 dup chunks.
- The preregistered eval was rerun unchanged (40 positives, 10 negatives):

| setting | strict | lenient | negative hits | shift-20 control |
|---|---|---|---|---|
| tau 0.5 | **30/40 = 0.75** | 31/40 | **0/10** | **1/40 = 0.025** |
| raw (no tau) | 34/40 | — | 10/10 | — |
| tau 0.4 | 32/40 | — | 4/10 | — |
| tau 0.6 | 21/40 | — | — | — |
| tau 0.7 | 13/40 | — | — | — |

  - These match the shipped RESULTS.md: strict 30/40.
  - Index query latency, measured in-process: p50 165.1 µs, p95 275.7 µs (n 150).

**Same 50 questions on the new personal memory** (`mem hits`, k 5):

| measure | result |
|---|---|
| strict | 6/40 = 0.15 |
| negative hits | 0/10 |
| control | 0/40 |
| process wall latency per query | p50 1.29 ms, p95 1.54 ms (n 150, includes exec) |

  The personal store is a 48-record curated preference/decision memory, not a full-history index. Most of the 40 ChatMemory questions ask about topics it does not hold. The two systems complement each other.

Ratios were computed with Wolfram.
