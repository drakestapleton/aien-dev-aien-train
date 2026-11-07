# DRA-146 correction-sequence examples: validator receipts

Aggregate counts and hashes only; the examples, the eval tasks and their TSV projection stay on the Spark in
the lane's private root. Labels: the validator is IMPLEMENTED and TESTED; the curated example set is
PREPARED and EXERCISED (validated below). Nothing here is TRAINED, EVALUATED or DEPLOYED.

## Tool

| item | value |
|---|---|
| unit | `native/personal/exvalid.om` sha256 `a3597a3ac476bcd7e2545c42a8be81c2e63f6f774bd08a9a06cd67ab38345091` |
| compiler | omega-mv `e5b32567` seed omc, sha256 `2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f` |
| binary | sha256 `ced1526963fcba9121c3cc3269e4995eeac61d848829c61da5ef1e315af4f91e` (AArch64 Linux, compile exit 0) |
| host | DGX Spark (GB10), CPU only, `taskset -c 0 nice -n 10` |

## Synthetic test (`OMC=... sh tests/personal/exvalid.sh`)

```
exvalid-test: omc=2c82480596bbdc50 compile=0
PASS ok.tsv (exit 0, FAIL lines 0)
PASS bad_user_target.tsv (exit 1, FAIL lines 1)
PASS bad_allowed_unverified.tsv (exit 1, FAIL lines 1)
PASS bad_allowed_rejected.tsv (exit 1, FAIL lines 1)
PASS bad_conv_two_splits.tsv (exit 1, FAIL lines 1)
PASS bad_shared_train_dev.tsv (exit 1, FAIL lines 1)
PASS bad_shared_train_test.tsv (exit 1, FAIL lines 1)
PASS bad_shared_dev_test.tsv (exit 1, FAIL lines 1)
PASS bad_cond_oversize.tsv (exit 1, FAIL lines 1)
PASS bad_target_oversize.tsv (exit 1, FAIL lines 1)
PASS bad_malformed.tsv (exit 2, FAIL lines 1)
PASS ok.tsv counts
SUMMARY pass=12 fail=0
```

## Real (private) projection

328 example rows (projection sha256 `cd3fcbdce63d302391945ccad7b3a8c7f5bfa71f0793ea574787cb13e2230356`):

```
exvalid rows=328 convs=216 hashes=22251 target_allowed=64
PASS target_role_agent violations=0
PASS allowed_only_verified_or_approved violations=0
PASS conv_one_split violations=0
PASS no_shared_hash_train_dev violations=0
PASS no_shared_hash_train_test violations=0
PASS no_shared_hash_dev_test violations=0
PASS cond_bytes_le_600 violations=0
PASS target_bytes_le_400 violations=0
PASS well_formed_rows violations=0
PASS table_capacity violations=0
SUMMARY pass=10 fail=0
exit 0
```

Real-data negative controls (one row edited in a copy of the projection): target_allowed set to 1 on an
unverified example printed `FAIL allowed_only_verified_or_approved violations=1` (exit 1); target role set
to `drake` printed `FAIL target_role_agent violations=1` (exit 1).

## Example counts (by split, type, outcome label; target_allowed in parentheses)

| split | correction verified | correction rejected | correction unverified | preference verified | preference approved | total |
|---|---|---|---|---|---|---|
| train | 4 (4) | 15 (0) | 244 (0) | 40 (40) | 12 (12) | 315 |
| dev | 1 (1) | 0 | 4 (0) | 6 (6) | 0 | 11 |
| test | 0 | 0 | 1 (0) | 1 (1) | 0 | 2 |

Rejected attempts are never targets; unverified and rejected outcomes are never targets; every target is
agent text. Held-out eval tasks: 121 (intent_following 20, remembering_corrections 21, agent_coordination 20,
coding_correctness 20, stale_preference 20, privacy_leak_probes 20), built from dev and test only.
