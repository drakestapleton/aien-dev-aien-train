# wsp controller telemetry traces, 2026-11-07

Evidence for `docs/omegallm/WSP-CONTROLLER.md` section 5 (Linear DRA-187, lane wsp, B4).

## Instrument

The instrument going forward is the seeded Omega sampler `tools/omegallm/ctlsamp/ctlsamp.om`
(README in the same directory). It writes one row with the keys of both old files below.

## Data captured with the old sampler (kept as data)

| File | Produced by | Rows | sha256 |
|---|---|---|---|
| `trace-001.jsonl` | old `sampler.py` (Python), 5 s interval | 360 | `531da5be7473ce80b4d98f736810365dd33339d3f0626ea7b99cb15bcb51a03e` |
| `ups-001.jsonl` | old `ups-sampler.sh` (shell, `upsc spark`), 5 s interval | 340 | `fd8a873d20491667d05f81462f2f7848676151addb6f2ced1a1ef3c9caab894c` |
| `run-start.txt`, `sampler.log`, `ups-sampler.log` | start time and the (empty) logs of those runs | | |

The old sampler produced these 30 minute traces. Its source is in commit
`a64e8707ebd2693254f27285dee6d8bdd0391559` (`sampler.py` sha256
`d45206003f03be9881ae4dc2419b1c5d9ada84ead0f69b5c79c397cae02317e8`, `ups-sampler.sh` sha256
`1cd419f15260f4c8d3d6b4023b561b02f515cd5114eae207089d6e67c377f09a`). Both files were deleted from
this directory when the Omega port landed; `git show a64e8707:<path>` still prints them.

## Port gate for ctlsamp.om: `gate-om-20261107/`

Built with omc from omega-mv `e5b32567` (omc sha256
`2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f`). Gate binary sha256
`0d48c231261a7a7dd23682bbfdc3170f0344948ae2b4c1ee58e130a030877b7c`, from `ctlsamp.om` sha256
`2dbe7f4daa9d9f1b968ca3adc1be3d86e6a3ab2c4233e7b1c705ceaf9f8b2d3a`.

Run (2026-11-07T07:44:09Z to 07:46:09Z, `start.txt`), exit 0 (`exit.txt`):
`taskset -c 0 nice -n 19 ctlsamp gate-om.jsonl 5 24 /usr/bin/nvidia-smi /usr/bin/upsc raw.log`.
24 rows in `gate-om.jsonl`; `raw.log` holds the exact bytes of every read, which are the
same-moment readings of the original commands and files.

Results, MEASURED:

1. Keys and types: PASS. The jq signature (every scalar path with its JSON type) over all 24 rows
   equals the union of the signatures of `trace-001.jsonl` and of the five UPS keys of
   `ups-001.jsonl`: 74 entries each, none on one side only (`sig-compare.json`).
2. Paired values: PASS. For rows seq 0, 11 and 23 a Wolfram program parsed the raw records
   independently and compared 71 values per row with the JSON: 20 core busy shares (from the two
   `/proc/stat` records, tolerance 1/200 for the 2 decimal rounding), 3 loadavg and `runnable`,
   24 PSI values, 7 thermal zones, 4 meminfo values, 6 nvidia-smi fields, 5 upsc fields, and
   `ts_utc` against `ts_unix`. All other tolerances are 0. Failures: none in all 3 rows
   (`oracle-seq{0,11,23}.wl` and `.out`). A subset of the pairs (raw reading = row value):

   | Field | seq 0 | seq 11 | seq 23 |
   |---|---|---|---|
   | core c0 busy % | 17.5258 = 17.53 | 36.0825 = 36.08 | 100 = 100.0 |
   | load1 | 7.6 = 7.6 | 10.76 = 10.76 | 11.01 = 11.01 |
   | runnable | 6/3851 | 14/4570 | 9/4559 |
   | PSI cpu some avg10 | 1.13 | 11.45 | 15.85 |
   | tz0 C | 82.5 | 83.6 | 74.9 |
   | MemAvailable kB | 75044120 | 72799800 | 73108508 |
   | GPU util / W / C / MHz / pstate | 93 / 44.77 / 72 / 2099 / P0 | 87 / 31.78 / 72 / 1755 / P0 | 38 / 17.93 / 59 / 1007 / P0 |
   | UPS load % / status / V / runtime s | 26 / OL / 121 / 1600 | 27 / OL / 121 / 1950 | 22 / OL / 122 / 2275 |
   | ts_utc | 07:44:14Z | 07:45:09Z | 07:46:09Z |

3. Comparator negative control: PASS. The same Wolfram program on seq 0 with two values changed
   by one unit in the last digit (core c0 17.54, gpu_power_w 44.771) reports exactly those two as
   failures (`oracle-negctl-seq0.wl` and `.out`).
4. Command negative control: PASS. `ctlsamp neg-control.jsonl 5 1 /nonexistent/nvidia-smi
   /nonexistent/upsc` exited 0 and wrote one valid row with `"gpu_error": "rc=127"` and
   `"ups_error": "rc=127"`, the GPU and UPS keys absent (`neg-control.jsonl`). A missing command is
   a read error in the row, not a crash.
5. Cadence: `WolframLanguageEvaluator: With[{t=<ts_unix>, c=<sample_cost_us>}, {Last[t]-First[t],
   {Mean,Min,Max}[Differences[t]], {Min,Max,Median,Mean}[c]}]` -> span 115 s, interval
   {5.000, 4.992, 5.008} s, sample cost {79847, 424823, 99149.5, 113802.2} us
   (`oracle-cadence.wl` and `.out`). The median cost is higher than the old sampler's 55943 us
   because one sample now also runs `upsc`, which the old shell sampler ran as a second process.
6. Cross-check against the independent sensors log `~/yardsticks/sensors/2026-11-07.csv` (rows
   within 3 s, `sensors-near.txt`; not the same moment, so this is a sanity check, not the gate):
   load1 7.60, 10.76 and 11.01 match the rows exactly; UPS W 260, 270 and 220 equal ups_load_pct
   times 10; GPU W and util move within seconds, so they agree only roughly: seq 23 (17.93 W)
   sits inside its neighbours (14.58 to 21.88 W), while seq 0 (44.77 W, neighbours 43.71 to
   44.53 W) and seq 11 (31.78 W, neighbours 11.52 to 30.51 W) read a little above them.

ORACLE only, not shipped: `/usr/bin/jq` (reports `jaq 3.1.1`) for the signature and the Wolfram
MCP evaluator for the value checks. The Wolfram programs were generated from `raw.log` and
`gate-om.jsonl` in the agent's session; the generated programs are the filed `.wl` files.
