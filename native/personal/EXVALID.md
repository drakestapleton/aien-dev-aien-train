# exvalid.om: curated-example validator (DRA-146)

`exvalid.om` checks a TSV projection of the correction-sequence examples before any of them is used for
training. It reads labels, sizes and hashes only, never text.

## Rules being enforced

- A training target is agent text only: every row's `target_role` must be `agent` (never the user role).
- `target_allowed = 1` only when the outcome is `verified` (independent tool evidence in the thread) or
  `approved` (Drake explicitly approved). A `rejected` or `unverified` outcome can never be a target;
  silence is not approval and an agent's own PASS claim is not verification.
- Every example inherits its conversation's split: a conversation may not appear in two splits.
- No hash of the compact example text (exact or 13-word shingle) may be shared train-dev, train-test or
  dev-test.
- The compact fields fit the model context: `cond_bytes <= 600`, `target_bytes <= 400`.

## Input

One row per example, nine TAB-separated fields, on stdin:
`id split conv_id target_role outcome_label target_allowed cond_bytes target_bytes hashes`
(`hashes`: 16 lowercase hex digits, comma separated, or `-`).

## Output and exit

One `PASS`/`FAIL` line per check (`target_role_agent`, `allowed_only_verified_or_approved`, `conv_one_split`,
`no_shared_hash_train_dev`, `no_shared_hash_train_test`, `no_shared_hash_dev_test`, `cond_bytes_le_600`,
`target_bytes_le_400`, `well_formed_rows`, `table_capacity`), then `SUMMARY pass=N fail=M`. Exit 0 when
every check passes, 1 on a rule violation, 2 on malformed input or a full table (12,582,912 distinct hashes).

## Build and test

```sh
OMC=path/to/omc sh tests/personal/exvalid.sh
```

The pinned omc is omega-mv `e5b32567` (sha256 `2c824805...`). The test runs the synthetic fixtures in
`tests/personal/exvalid/`: `ok.tsv` must pass, and each `bad_*.tsv` plants one violation (negative control:
a user-role target, an allowed target with an unverified or rejected outcome, a conversation in two splits,
a hash shared across each split pair, an oversize compact field, a malformed row).
