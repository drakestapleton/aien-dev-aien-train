# splitcheck.om: corpus split verifier (DRA-146 v4)

`splitcheck.om` checks a TSV projection of a split corpus against the DRA-146 v4 pre-registered split rule.
It reads only hashes and timestamps, never text, so the projection of a private corpus can be checked
without the corpus leaving its machine.

## Rule being checked

- The unit is a whole conversation (`conv_id`); every row of a conversation must carry the same split
  and the same conversation start time.
- Split by conversation start time (UTC): `train < 2026-10-29T00:00:00 <= dev < 2026-11-03T00:00:00 <= test`.
- After the split, no normalized-text hash and no 13-word shingle hash may be shared train-dev,
  train-test or dev-test. Sharing inside one split is allowed.

## Input

One row per record, five TAB-separated fields, on stdin:

| field | value |
|---|---|
| conv_id | conversation id (any bytes except TAB and newline) |
| split | exactly `train`, `dev` or `test` (no prefixes) |
| start_ts | `YYYY-MM-DDTHH:MM:SS`, optional `.` and 1 to 9 digits, then `Z` (UTC only, no offsets); month, day (Gregorian leap years), hour, minute and second ranges are checked; the first 19 bytes are compared with the cutoffs |
| text_hash | exactly one token of 16 lowercase hex digits (first 64 bits of sha256 of the NFKC, lowercased, whitespace-collapsed text), or exactly `-` |
| shingle_hashes | a nonempty comma-separated list of 16-hex 13-word shingle hashes, or exactly `-`; empty tokens, trailing commas and embedded `-` are malformed |

A projection with more than 50,331,648 distinct hashes is split by leading hex digit into partitions;
each partition carries every row (with `-` for hashes outside it) and is checked by its own run. All runs
must pass.

## Output and exit

One `PASS`/`FAIL` line per check (`conv_one_split`, `conv_one_start_ts`, `split_matches_cutoffs`,
`no_shared_hash_train_dev`, `no_shared_hash_train_test`, `no_shared_hash_dev_test`, `well_formed_rows`,
`table_capacity`) with its violation count, then `SUMMARY pass=N fail=M`. Exit 0 when every check passes,
1 on a split violation, 2 on malformed input or a full table (more than 50,331,648 hashes or 786,432
conversations). Every 64-bit hash value, `0000000000000000` included, is a distinct key.

## Build and test

Compiled with the omc pinned by the omegallm tests (omega-mv `e5b32567`, sha256 `2c824805...`):

```sh
OMC=path/to/omc sh tests/personal/splitcheck.sh
```

The test compiles the unit and runs the synthetic fixtures in `tests/personal/splitcheck/`: `ok.tsv` and
`ok_dash.tsv` must pass; each `bad_*.tsv` plants one violation (negative control) and must fail with the
named check. Conversation ids are compared by FNV-1a 64 of their bytes (a collision would merge two
conversations and could only add violations, never hide one).

Pin notes observed with this omc: loop bounds above 999999 are refused (error 8) and an array is limited
to 2^24 elements (error 23), so the 2^26-slot table is four 2^24 arrays and long loops are nested.
