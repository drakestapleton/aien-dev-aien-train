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
