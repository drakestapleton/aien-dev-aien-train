# DRA-124 acceptance suite: evidence

Branch `feat/ollm-accept-124`. Suite, runner and gates: `tests/omegallm/accept/` (PREREG.md is normative).

## controls/ and controls-8c4fb0cb/

`controls.sh` (protocol checks, NOT capability). Two runs:
- `controls/`: runner a20097120cc6c521d497fb2401a434728b51adc3a0616ac8d89cd4b35eb387ad, with the harness lane's
  fixtures (C4) through Hermes v0.22.5 and the lane's `verify` f1adcad1... (origin/feat/ollm-harness 6d753aa).
- `controls-8c4fb0cb/`: the final runner 8c4fb0cb9f8de0c27da96d29ad69ccf4601b703132d78cd68aaecfc3b97eb5bd
  (adds `fill`; ingestion code unchanged), C1-C3 and M1-M4 (C4 needs ports 18297/18298, which the baseline held).
Each `controls.txt` lists every check and ends `CONTROLS PASS`; the `*.sum` files are the `accept sum` tables.

## baseline-r10/

The first scored candidate (PREREG section 7, amendment A1): see `baseline-r10/README.md`.

## controls-dfe061ff/ and context-fix/ (CHANGES.md C1, 2026-11-07)

The context-window gate fix. `controls-dfe061ff/`: runner dfe061ffac26cda85367e117bcfba1fcabb3a9478245a75be00cff4a7f7422ac,
C1-C3, C5-C8, M1-M5 (`controls.txt` ends CONTROLS PASS; `receipt.txt` has the command, hashes, rc 0, selftest 1124/0;
C4 NOT_RUN). `context-fix/`: the runner against a real integ3 `ollm serve` (/health model.T 256 and 8192) and the
baseline r10 rows re-summed (verdicts unchanged: FAIL).
