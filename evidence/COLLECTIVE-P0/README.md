# COLLECTIVE-P0: native replay of the sparse-collective P0 pilot (DRA-15, aien-train#26)

## Outcome and scope

EXERCISED on host Linux AArch64 (Spark spark-b87b, cores 10-11), 2026-11-07:
`P0REPLAY PASS original=selftest+oracle x3 comparator=refuses mutants_killed=8/8 overflow=trap1`
(`run-20261107/run.stdout`, exit 0).

The merged P0 program `native/collective/shared_bank_p0.om` (blob `92693265`, unchanged
since PR #27 squash `352fdaeb`, which equals its final head `0a905c64`) was compiled with
the pinned seeded compiler, executed, and judged by an oracle the program does not carry.
Eight compiled mutants were each rejected by that oracle; one of them also rewrites the
program's own expected tables and passes the program's self-test, which shows why the
external oracle is needed.

This is P0 only: the algebra and compiler path of a synthetic 2x3 shared base with eight
signed rank-one differences. No model, checkpoint, trained adapter, router, GPU or
runtime is involved, and no quality, latency or storage benefit is claimed (46 vs 48
scalars before metadata, from the frozen golden file). Scaling 8 -> 32 -> 128 still
requires P1-P4 under their owners.

## Pins

| Subject | Value |
| --- | --- |
| aien-train | main `0518c915dea370b3bffbb90d579b1daa5ba8b8f5`; branch `hive/t_60180a9d-collective-p0` |
| program | `native/collective/shared_bank_p0.om`, sha256 `aa0904a7…4345` |
| golden | `native/collective/fixtures/golden_v0.json`, sha256 `9b650a0d…3a9a` |
| omc | omega-mv `e5b32567a7aff3ce594e3254a622a846a6cd190b` (the aien-train aarch64 pin), sha256 `2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f`, source `7703da00…7e1b`. Re-born from the 408-byte seed-0 with `sh seed/omega-from-seed.sh` (RC=0, stage2 = stage3 fixpoint); the born binary equals the committed pin. |
| self-test binary | sha256 `b3368c5e9cf2b238fee63c0c04b38223205d6b634ce871dba8c9ceaf50f3bba8`, exit 0, three compiles identical. This equals the binary in the 2026-10-30 reviewer record in `native/collective/README.md`. |
| observation binary | sha256 `a97b8a8589d8edfc71f8c9cf046dd146907819133144fe6be73626149395fcf0`, exit 0 |

## Independent oracle

`native/collective/replay/p0emit-main.om` replaces only the self-test `fn main`. It is
appended to every line of the program before `fn main to int` (lines 1..149), byte for
byte, so the same `init`, `makebase`, `pick` and `apply` run, and it prints every
observable: base matvec, the 16 signed outputs with their status, top-2 admitted
selection, deny-1 selection, the three refusal statuses, the all-denied sentinel, and the
base/adapter call counts. It does no arithmetic and checks nothing itself.

The expected stdout `native/collective/replay/expected-p0e1.out` is the string returned by
the hosted WolframLanguageEvaluator for `oracle-query.wl`; Wolfram's own SHA-256 of that
string, `829b9a67…cfff`, is the file's hash, and `run.sh` refuses any other file. Raw result:
`oracle-wolfram-raw.json`. The Wolfram outputs equal every entry of `golden_v0.json`
(base [16,-8]; 8 positive and 8 negative pairs; top-2 [1,3]; deny-1 top 3; all-denied 8).
The refusal codes -1/-2/-3 are the contract of `golden_v0.json`, transcribed, not computed.
The observation build's stdout equals that file byte for byte in all three repeats.

## Mutants and refusals (`run-20261107/out/receipt.tsv`)

| Case | Change | Self-test | Independent oracle |
| --- | --- | --- | --- |
| m1-sign | `apply`: `add` -> `sub` of the signed difference | exit 4 | killed: 14 of 16 output lines differ (candidate 2 has V.x = 0, so its sign is invisible) |
| m2-route | `pick`: `gt` -> `lt` score order | exit 11 | killed: top2 8 8, deny1top 8 |
| m3-factor | `U[i][0]`: `sid-3` -> `sid-4` | exit 4 | killed: 14 of 16 output lines differ |
| m4-rebase | base matvec recomputed inside every admitted call (cache reuse removed) | exit 9 | killed: counts 17 16 |
| m5-mask | `pick` ignores the admission mask | exit 13 | killed: deny1top 1, alldenied 1 |
| m6-phase | bad phase returns 0 instead of -3 | exit 16 | killed: status -2 -1 0 |
| m7-index | index guard `ge id 8` -> `ge id 9` | exit 103 (trap 3) | killed: trap 3, no END |
| m8-coordinated | m1 plus the program's own Plus/Minus tables swapped | **exit 0 (missed)** | killed: 14 of 16 output lines differ |
| c1-overflow | input x2 = 2^63-1, base matvec overflows | n/a | refused: trap 1, exit 101, no END |
| comparator | expectation with one changed byte | n/a | refused (cmp differs) |

Every mutant is a line-addressed edit whose original line is checked before editing; each
compiled with exit 0 (a mutant that fails to compile counts as a harness failure, not a kill).
Harness negative control: the same run with omc `d6290c76…` (another pin) prints
`P0REPLAY NOT_RUN` and exits 77 (`run-20261107/negctl-wrong-compiler.*`).
Measured wall time of the whole replay (23 compiles, 23 runs): 233.25433 ms.

## Refusal contract of aien-train#26 P0, status

| Contract item | Status at this revision |
| --- | --- |
| invalid specialist index | EXERCISED: `apply 8 1` returns -1; weakening the guard (m7) traps 3 instead of inventing a result |
| denied candidate | EXERCISED: -2 after deny-1 |
| unsupported phase | EXERCISED: -3; removing it (m6) is caught |
| ALL denied | EXERCISED: sentinel 8, no dispatch |
| overflow | EXERCISED via the language's checked signed arithmetic (trap 1); the program has no overflow check of its own |
| wrong/changed rank, shapes, missing/wrong base, wrong model generation, budget ceiling, swapped score/permission, stale candidate | MISSING_IMPLEMENTATION: the P0 program has fixed constant shapes, one base, no generation, budget or provenance fields, so there is no input that could be refused. Follow-up: Spark hive kanban card t_8cf72aaf (DRA-15). |

## Not run

Real model inventory and specialization (P1), learned adapters (P2), native shared-base
realization inside model math (P3), full-economics evaluation in benchmarks #38 (P4),
GB10/GPU execution, x86 execution: NOT_RUN. Host execution is not device qualification.

## Reproduce

    OMC=<omega-mv e5b32567 seed/out/omc> sh native/collective/replay/run.sh OUTDIR

Run by t_60180a9d (Hermes worker, claude-opus-5-5, anthropic) for DRA-15.
