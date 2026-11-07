# DRA-146 corpus v4: split checker receipts

Aggregate counts and hashes only. The corpus, its TSV projection and every original stay on the Spark in
the lane's private root, outside this repository. Labels: the checker is IMPLEMENTED and TESTED; the
corpus split is EXERCISED (checked below). Nothing here is TRAINED, EVALUATED or DEPLOYED.

## Tool

| item | value |
|---|---|
| unit | `native/personal/splitcheck.om` sha256 `2373dc32b3c01b6b6874f6fca9f2a46fad544bd813d3e60113b0abedd154384d` |
| compiler | omega-mv `e5b32567` seed omc, sha256 `2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f` |
| binary | sha256 `f4954f9540753dfeed65224d5a8d1ae0c89a288a1d0229729735e9a50d22ef52` (AArch64 Linux, compile exit 0) |
| host | DGX Spark (GB10), CPU only, `taskset -c 0 nice -n 10` |

## Synthetic test (`OMC=... sh tests/personal/splitcheck.sh`)

```
splitcheck-test: omc=2c82480596bbdc50 compile=0
PASS ok.tsv (exit 0, FAIL lines 0)
PASS ok_dash.tsv (exit 0, FAIL lines 0)
PASS bad_two_splits.tsv (exit 1, FAIL lines 2)
PASS bad_cutoff.tsv (exit 1, FAIL lines 1)
PASS bad_start_ts.tsv (exit 1, FAIL lines 1)
PASS bad_train_dev_text.tsv (exit 1, FAIL lines 1)
PASS bad_train_test_shingle.tsv (exit 1, FAIL lines 1)
PASS bad_dev_test_shingle.tsv (exit 1, FAIL lines 1)
PASS bad_malformed.tsv (exit 2, FAIL lines 1)
PASS ok.tsv counts
SUMMARY pass=10 fail=0
```

Every `bad_*.tsv` is a negative control with one planted violation; each was detected with the named check.

## Real (private) projection

The private corpus-v4 split files (train, dev, test after cross-split dedupe) were projected to
1,532,090 rows in 4 hash-prefix partitions (70,770,171 distinct hashes in total, at most 17,696,286 per partition,
under the 50,331,648 capacity). Each partition carries every row. Partition TSV sha256:
`5cfc0637...4769e7`, `e051c758...79d022c`, `c5a1e26b...e033f337`, `67c7fe2d...e822b7e4`.

```
== partition 0
splitcheck rows=1532090 convs=11507 hashes=17692765 train=1275338 dev=144968 test=111784
PASS conv_one_split violations=0
PASS conv_one_start_ts violations=0
PASS split_matches_cutoffs violations=0
PASS no_shared_hash_train_dev violations=0
PASS no_shared_hash_train_test violations=0
PASS no_shared_hash_dev_test violations=0
PASS well_formed_rows violations=0
PASS table_capacity violations=0
SUMMARY pass=8 fail=0
exit 0
```

Partitions 1, 2 and 3 printed the same lines with `hashes=17696286`, `17689784` and `17691336`, all
`SUMMARY pass=8 fail=0`, exit 0. Wall time about 15 s and 0.6 GB peak RSS per partition.

Real-data negative control: partition 0 plus one appended row (a new test-split conversation carrying the
hashes of an existing train row) printed `FAIL no_shared_hash_train_test violations=59`,
`SUMMARY pass=7 fail=1`, exit 1.

## Corpus v4 aggregates (for the reviewer; no text)

Records by role and split, corpus v4.1 (after a relabel pass that set 164 harness/runtime turns, 1,185 records,
from drake/drake_quote to system; text, conversations and splits unchanged, so the projection above still
applies). Split by conversation start; dev/test after cross-split dedupe are the counts
in the split files; `no start ts` conversations have no timestamp and are in no split):

| role | train | dev (before dedupe) | test (before dedupe) | no start ts | total |
|---|---|---|---|---|---|
| drake | 100836 | 624 | 901 | 431 | 102792 |
| drake_quote | 12643 | 150 | 17 | 140 | 12950 |
| third_party | 3 | 0 | 3 | 0 | 6 |
| agent | 666811 | 102608 | 84729 | 1783 | 855931 |
| tool | 445853 | 81479 | 67326 | 0 | 594658 |
| system | 47586 | 7334 | 8007 | 0 | 62927 |
| unknown | 1606 | 959 | 791 | 0 | 3356 |
| all | 1275338 | 193154 | 161774 | 2354 | 1632620 |

Conversations: train 10150, dev 619, test 910, no start ts 23. Cross-split dedupe dropped from dev 7568
(exact) + 40618 (13-word shingle) records and from test 7778 + 32101 (train) and 1675 + 8436 (dev).

## Review fix (lead dra146, 2026-11-07)

Reviewer verdict COMMENT on 1deaf0e3 (gpt-6-astra): B1 malformed input passed (split prefixes `trash`, `d`,
`testing`; timestamps `zzz...`, `2026-10-32...`, `+01:00` offsets; empty hash fields, embedded `-`, empty
shingle tokens); N1 hash 0 collapsed into 1; N2 the declared 786,432-conversation capacity was not enforced.
Fixed: exact split tokens; a UTC timestamp grammar with calendar ranges; the hash-field grammar; occupancy by
nonzero mask/code instead of a rewritten key; a full conversation table exits 2. Fixtures added: `ok_zero_one`,
`bad_zero_shared`, `ok_ts_forms` and 12 malformed forms, plus a generated 786,432 / 786,433 capacity case.
`OMC=<pinned omc> sh tests/personal/splitcheck.sh` -> `SUMMARY pass=26 fail=0`. The 1deaf0e3 build gives the
wrong exit on all 13 new fixture cases (ok_zero_one exit 1; each malformed form exit 0). Rerun on the private
projection with the fixed build: all 4 partitions `SUMMARY pass=8 fail=0`, exit 0, same row/conversation/hash
counts as above.
