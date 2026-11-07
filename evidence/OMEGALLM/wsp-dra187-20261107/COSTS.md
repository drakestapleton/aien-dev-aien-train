# DRA-187 cost log

Every run: UTC start and end, cores, records, wall time. Per-arm machine lines are in `runs/runs.jsonl`
(written by `runarms.py`). Energy: whole-system wall energy BLOCKED_INPUT (no qualified meter).

## Agent time (orchestrator lane wsp, omp, model claude-opus-5-5)

| UTC | Work |
|---|---|
| 05:44 to 06:06 | reconcile, claim, wprobe written and verified, splits and PREREG committed (`d329de73`) |

Subagents (all model claude-opus-5-5 via omp `task`): MethodNote 4 min 29 s (PR aien-train#77);
WPatch and CtlTraces running (times added when they finish).

## CPU runs (core 19 unless noted)

| UTC start | End | Run | Records | Wall |
|---|---|---|---|---|
| 05:55 | 05:56 | `ollm sample` parity, 1 record (full recompute) | 1 | 89.8 s |
| 05:58 | 05:58 | `wprobe gen` parity, 4 records | 4 | 20.1 s |
| 05:59 | 05:59 | `wprobe probe` parity, 4 records | 4 | 17.9 s |
| 06:00 | 06:01 | `wprobe gen` hook 5 (f32) parity, 4 records | 4 | about 20 s |
| 06:06:57 | | `wprobe probe` base on D | 186 | |

## GPU

None so far.
