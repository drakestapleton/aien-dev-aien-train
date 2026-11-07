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

Records by role and split (split by conversation start; dev/test after cross-split dedupe are the counts
in the split files; `no start ts` conversations have no timestamp and are in no split):

| role | train | dev (before dedupe) | test (before dedupe) | no start ts | total |
|---|---|---|---|---|---|
| drake | 101502 | 624 | 906 | 431 | 103463 |
| drake_quote | 13153 | 150 | 21 | 140 | 13464 |
| third_party | 3 | 0 | 3 | 0 | 6 |
| agent | 666811 | 102608 | 84729 | 1783 | 855931 |
| tool | 445853 | 81479 | 67326 | 0 | 594658 |
| system | 46410 | 7334 | 7998 | 0 | 61742 |
| unknown | 1606 | 959 | 791 | 0 | 3356 |
| all | 1275338 | 193154 | 161774 | 2354 | 1632620 |

Conversations: train 10150, dev 619, test 910, no start ts 23. Cross-split dedupe dropped from dev 7568
(exact) + 40618 (13-word shingle) records and from test 7778 + 32101 (train) and 1675 + 8436 (dev).
