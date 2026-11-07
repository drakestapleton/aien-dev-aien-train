# DRA-187 causal tests (PREREG section 3, P1 and P2), MEASURED

Split D (186 unread rows: 66 target of 6/7/8 digits, 120 control of 3/4/5 digits), teacher-forced exact copy
(`wprobe probe`, R line `div` = -1). Hook 3 scales the output of heads 6.6, 7.11, 6.11 and 7.0 on answer rows
only (the four heads `rank.py` ranks first on the 59 base failure rows). Core 19, pool-19 lock, nice 10.
Commands, binary sha256 and timings: `runs/runs.jsonl`. Outputs: `diag/D-base.out`, `diag/D-P1-copyheads-x1.5.out`,
`diag/D-P2-copyheads-x0.out`.

| Arm | Target exact (of 66) | gained / lost vs base | Control exact (of 120) | gained / lost vs base | Mean gap on failures |
|---|---|---|---|---|---|
| base | 7 | | 120 | | -7.063 |
| P1 heads ×1.5 | 16 | 9 / 0 | 114 | 0 / 6 | -5.455 |
| P2 heads ×0 | 0 | 0 / 7 | 19 | 0 / 101 | |

Exact one-sided sign (McNemar) tests on the discordant rows:
- P1 target: `WolframLanguageEvaluator: N[(1/2)^9] -> 0.001953125`.
- P1 control loss: `WolframLanguageEvaluator: N[(1/2)^6] -> 0.015625`.
- P2 control loss: `WolframLanguageEvaluator: ScientificForm[N[(1/2)^101], 4] -> 3.944 × 10^-31`.

P1: PASS (raises 6/7/8-digit copies). P2: PASS (breaks 3/4/5-digit copies). E1 stays in the search.

Reading: the four heads carry the copy; turning them up helps long IDs but already costs some short ones
(6 of 120), so the control gate in section 5 is a real constraint on E1, not a formality.
