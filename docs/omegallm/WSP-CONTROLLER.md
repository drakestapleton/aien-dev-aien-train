# WSP B4: controller scoping (sched and pearl)

Lane wsp, Linear DRA-187, component B4. Written 2026-11-07 by agent CtlTraces on branch
`wsp/controller` of aien-dev/aien-train (base `0518c915dea370b3bffbb90d579b1daa5ba8b8f5`).

Status of everything in this file: the controller is **PROPOSED**. Nothing here is IMPLEMENTED,
EXERCISED, QUALIFIED, MERGED or DEPLOYED. The trace and inventory are MEASURED on the host CPU
side; no GPU work was opened and no setting was changed.

Every derived number below was computed by the Wolfram evaluator; the query and result are quoted
next to it. Row counts, byte sizes and shas are bookkeeping and are not sent to Wolfram.

## 1. Short answer

- **sched** owns the validated scheduling knobs (capacity, policy, pause, lease) and decides
  only from logical counters, never from the clock or from telemetry.
- **pearl** owns the hardware audit and has already filed the controller work as its own issues:
  DRA-430 (telemetry, bounded scheduling controls, recovery) and DRA-431 (let a model pick only
  validated scheduling actions and measure net benefit against a fixed policy). Both are Backlog
  and unassigned.
- Nothing on either branch maps measured pressure, temperature or GPU state to the sched knobs.
- **Overlap, stated plainly:** an online controller that does this IS pearl DRA-431, which in
  turn needs DRA-430. Building it inside wsp would duplicate pearl.
- **Gap that does not duplicate:** an offline, replay-only study that (a) defines the telemetry
  feature vector and a fixed baseline rule over sched's existing knobs, and (b) trains and scores a
  tiny `.om` policy on held-out recorded traces. Its output is evidence for DRA-431, handed to pearl.
  It writes no knob, adds no sched word and opens no GPU. Linear DRA-438 (this component) is
  rescoped to exactly this offline study, feeding pearl's DRA-431.
- **sched's reply (BOARD, 2026-11-07T06:32:58Z):** the three words exist at sched head
  `9f5ebd35` (omega-mv #1064). Offline replay may model them as actions. A live controller in a
  journaled Node must not call `sched_*` directly; it targets `jn_cap`, `jn_policy` and
  `auth_pause` once DRA-398 lands (section 6.1).

## 2. sched lane: what it already does

Sources (read only, via `git show` of the remote refs in the wsp omega-mv clone):

- omega-mv branch `sched/dra-396-fair-dispatch` at `37b01f1891868bb7fdbfca6a974afe8649747910`
  (EXERCISED in scratch, not merged), file `seed/node/sched.om` (935 lines, sha256
  `4ad0cc9eaa3b5aa2fcae4a1e7df0b384bb5985fba9e9d7cb4febadcb08070724`) and `seed/node/README.md`.
- omega-mv branch `sched/dra-395-blocked-head` at `4225bbeb87579d9520a24364c382e3ade9443bf0`,
  PR omega-mv#1062, READY FOR REVIEW, not merged.
- Linear P-DRA-14 and DRA-395..399; brief `~/handoffs/hive/sched/BRIEF.md`.

What exists:

| Word | Effect | Citation (sched.om at 37b01f18 unless noted) |
|---|---|---|
| `sched_cap caps` | Sets four 16-bit capacities: kind 0 CPU slots, 1 memory MiB, 2 inference slots, 3 caller-defined. Returns -8 and changes nothing if a kind would fall below current use or below one admitted job's need. | line 232; README lines 452-457 |
| `sched_policy p win db by ttl` | Policy 0 FIFO head-of-line, 1 fair fitting (default). Window 1..64, dispatch budget 1..64, bypass budget 1..65535, ttl 1..1000000. -7 when out of range. | line 258; README line 456 |
| `sched_pause c on` | Pause stops new assignments; resume dispatches. Already called by `auth_pause` in `auth.om` lines 757-822. | line 800; README line 332 |
| `sched_lease j ns` | Per-job lease from next assignment; `sched_overdue` reports and reaps late jobs. | lines 422, 444; README lines 544-553 |
| `sched_stat i` | Counters 0..15, capacity 16..19, use 20..23, policy words 24..31. | line 212 |

Key property, sched.om line 25: "Decisions read only these logical counters, never the clock."
Defaults from `sched_new` (line 94): every capacity 65535, policy 1, window 64, budget 64, bypass 4,
ttl 1000. Those defaults mean the capacities are not limiting today.

Not yet there: no telemetry input of any kind; no live dispatch ("Until then neither scheduler
dispatches live hive work", README lines 406-407), so there are no production scheduler logs, only
JSON receipts under `evidence/node-schedpol/`. DRA-397 says "Learned ranking remains deferred until
it beats this baseline in matched evidence"; P-DRA-14 says "baseline scheduling requires no model
call". DRA-397, 398 and 399 are Backlog.

## 3. pearl lane: what it already does

Sources (read only): repo omega-pearl in `~/work/pearl/omega-pearl`, branch
`pearl/dra-422-audit` at `d81798de2ae0d3253ad09a7d203e52cdb56fa23f`, files `audit/HARDWARE.md`,
`audit/ENVELOPE.md`, `audit/CAPABILITY-MATRIX.md`; Linear P-DRA-16, DRA-421, 422, 430, 431; brief
`~/handoffs/hive/pearl/BRIEF.md`. Pushes are frozen pending Drake's Q4 answer.

- DRA-422 (In Progress): read-only hardware audit. Records SoC TDP 140 W and PSU 240 W
  (DOCUMENTED), GPU power limits N/A, acpitz critical trip 104.8 C, powercap empty (no SoC or
  CPU power rails), no wall meter, UPS whole-load only (`audit/HARDWARE.md` lines 23, 19, 29-31).
- `audit/CAPABILITY-MATRIX.md` line 27: clock-cap governor MISSING_IMPLEMENTATION, "no clock
  writes without auth". Line 62: duty cycle and stop conditions, "no clock, power-limit or firmware
  writes", owned by the pearl scheduler with sched's `sched.om`, tracked as **DRA-430**.
- **DRA-430** (Backlog, unassigned): "Implement resource-aware scheduling, telemetry and recovery":
  typed capabilities, bounded scheduling controls, memory-pressure handling, telemetry freshness,
  stop and recovery, service priority.
- **DRA-431** (Backlog, unassigned): "Add model scheduling policy and measure its net
  contribution": "Let the model select only validated scheduling actions ... held-out
  workload/telemetry replays plus controlled on-device comparison against a simple fixed policy.
  Measure controller time/energy and AI-service quality. Promote decisions only when net useful
  performance or energy improves."
- The pearl brief (line 87) already expects wsp to "bring a qualified edit or controller to you;
  integration is gated on its qualification (its B5)".

## 4. Telemetry inventory (this machine, read without root)

| Source | Fields | Rate / cost | Label |
|---|---|---|---|
| `/proc/loadavg` | load 1/5/15, runnable/total | any | MEASURED |
| `/proc/pressure/{cpu,memory,io}` | PSI some/full avg10/60/300, totals | any; cpu `full` is always 0 here | MEASURED |
| `/proc/stat` | per-core busy over 20 cores (delta) | any | MEASURED |
| `/proc/meminfo` | MemTotal, MemAvailable; no swap configured | any | MEASURED |
| `/sys/class/thermal/thermal_zone0..6` | all seven are `acpitz` | any | MEASURED |
| hwmon | acpitz, nvme temp1-3, wifi phy temp | any | MEASURED |
| `nvidia-smi` (one-shot) | GPU util, power draw, temp, SM clock, pstate; `clocks_event_reasons.active` available but not sampled; memory used/total N/A (unified memory) | the dominant read cost (section 5) | PARTIAL: GPU board only |
| `upsc spark` | ups.load % of 1000 W nominal, status, input voltage, runtime | driver poll 2 s, integer % | PARTIAL: whole UPS, other loads unknown |
| SoC / CPU power rails | none (powercap empty) | n/a | BLOCKED_INPUT |
| Wall energy | no qualified meter | n/a | BLOCKED_INPUT |
| `~/yardsticks/sensors/<local date>.csv` (existing, `spark-sensors`, started @reboot) | epoch, iso, UPS W (load x 10), GPU W, GPU util, load1, MemAvailable, GB10 lock holders, NVRM error count | one row about every 2 s; 19 files, 787376 rows | MEASURED history, PARTIAL power |
| `~/yardsticks/windows/<id>/open.json` (existing, `spark-window`) | 478 window records; `state` snapshot: loadavg, MemAvailable, GPU util and W, lock holders, GPU apps, last sensors row | one per window | MEASURED event labels |
| `~/.local/state/aien-coordinator/` | chip-watchdog.log, OWNER, CHIP-RESERVED | free text | not machine-usable as-is |

History span of the existing sensors log, from the first row of `2026-10-19.csv`
(1792422846, 2026-10-19T10:14:06-05:00) to the last row read (1794030993,
2026-11-06T23:56:33-06:00):
`WolframLanguageEvaluator: DateDifference[DateObject[{2026,10,19,10,14,6},TimeZone->-5], DateObject[{2026,11,6,23,56,33},TimeZone->-6], {"Day","Hour","Minute","Second"}] -> 18 days 14 h 42 min 27 s`.

That log lacks PSI, per-core and thermal fields, so it can train only the reduced feature set
(section 6.3). The sampler of section 5 adds those fields.

## 5. Trace recorded for this study

Directory `evidence/OMEGALLM/wsp-ctl-traces-20261107/` in this branch. Both instruments ran on
core 0 only, at `nice -n 19`, read only, with no GPU work and no setting changed.

Instrument going forward: the seeded Omega sampler `tools/omegallm/ctlsamp/ctlsamp.om` (build,
usage, row format and exit codes in its README). It writes the keys of both files below in one
row, runs `nvidia-smi` and `upsc` through `execprog` with pipes, and timestamps with `monons` and
`realns`. Its port gate (2 minute run, keys and types equal to these traces, 71 values per row
equal to same-moment raw readings on 3 rows, a missing command recorded as a read error) is in
`gate-om-20261107/` and the evidence README, all PASS (MEASURED).

The two files below are data from the old Python and shell samplers, which are deleted from the
tree; their source stays in commit `a64e8707ebd2693254f27285dee6d8bdd0391559`.

| File | What | Rows | First / last ts_utc | sha256 |
|---|---|---|---|---|
| `trace-001.jsonl` | old `sampler.py`, 5 s interval | 360 | 2026-11-07T05:53:53Z / 06:23:48Z | `531da5be7473ce80b4d98f736810365dd33339d3f0626ea7b99cb15bcb51a03e` |
| `ups-001.jsonl` | old `ups-sampler.sh` (`upsc spark`), 5 s interval | 340 | 2026-11-07T05:55:10Z / 06:23:45Z | `fd8a873d20491667d05f81462f2f7848676151addb6f2ced1a1ef3c9caab894c` |

Start command (recorded in `run-start.txt`, 2026-11-07T05:53:47Z):
`taskset -c 0 nice -n 19 python3 sampler.py trace-001.jsonl 5 360`. Instrument hashes:
`sampler.py` `d45206003f03be9881ae4dc2419b1c5d9ada84ead0f69b5c79c397cae02317e8`,
`ups-sampler.sh` `1cd419f15260f4c8d3d6b4023b561b02f515cd5114eae207089d6e67c377f09a`.
Both logs are empty (no errors). No row has a `gpu_error`; every UPS row reports status `OL`.

Span and cadence (MEASURED):

- `WolframLanguageEvaluator: UnitConvert[Quantity[{1794.999, 1715.003}, "Seconds"], MixedUnit[{"Minutes","Seconds"}]] -> {29 min 55.0 s, 28 min 35.0 s}`
  for trace-001 and ups-001 (last minus first `ts_unix`).
- Interval between trace rows, `{Mean, Min, Max}` of `Differences[ts_unix]`:
  `-> {5.000 s, 4.927 s, 5.072 s}`.

Summary of trace-001. Each line is
`WolframLanguageEvaluator: With[{d=<column>}, {Length[d], Min[d], Max[d], N[Mean[d]], N[Median[d]], N[Quantile[d,95/100]]}]`
on the named column (all 360 rows); values rounded here to the precision of the source field.

| Column | n | Min | Max | Mean | Median | p95 |
|---|---|---|---|---|---|---|
| load1 | 360 | 9.59 | 17.44 | 11.96 | 11.47 | 15.54 |
| PSI cpu some avg10 (%) | 360 | 0.07 | 20.05 | 4.41 | 1.78 | 15.13 |
| PSI memory some avg10 (%) | 360 | 0 | 1.22 | 0.088 | 0.01 | 0.39 |
| PSI io some avg10 (%) | 360 | 0 | 37.44 | 1.38 | 0.09 | 5.46 |
| PSI io full avg10 (%) | 360 | 0 | 33.93 | 1.27 | 0.08 | 5.04 |
| per-core busy % (20 cores x 360 rows) | 7200 | 1.9 | 100 | 51.06 | 29.99 | 100 |
| max acpitz (C) | 360 | 67.8 | 93.9 | 79.43 | 78.6 | 87.8 |
| GPU util (%) | 360 | 0 | 94 | 68.24 | 84 | 93 |
| GPU power (W, board only) | 360 | 5.89 | 45.43 | 37.37 | 43.14 | 44.78 |
| GPU temp (C) | 360 | 51 | 74 | 65.45 | 67 | 72 |
| SM clock (MHz) | 360 | 201 | 2515 | 1889.1 | 2067 | 2509 |
| sample cost (us per row) | 360 | 31493 | 583525 | 59391 | 55943 | 109115 |

- MemAvailable in GB: `With[{d=<MemAvailable_kb>}, N[{Min[d], Max[d], Mean[d]}*1024/10^9]] -> {69.92, 86.91, 79.69}`.
- UPS load as W (load % x 1000 W nominal / 100), PARTIAL:
  `With[{d=<ups_load_pct>}, {Min[d]*10, Max[d]*10, N[Mean[d]*10], N[Median[d]*10]}] -> {200, 280, 252.6, 260}` W.
- The GPU went idle for part of the window: 39 rows in pstate P8 and 49 rows under 10 W.
  Rows where max acpitz reached 90 C: 3 (05:55:48Z 91.5 C, 05:57:08Z 93.9 C, 05:57:23Z 92.9 C).
  Rows with PSI io some avg10 above 10: 13. As shares of 360 rows:
  `WolframLanguageEvaluator: N[{3, 13, 39, 49}/360*100] -> {0.83, 3.61, 10.83, 13.61}` %.
- The telemetry read itself costs a median of 55943 us per sample on one core (MEASURED). The
  sampler does not time its parts separately; INFERENCE: most of it is the `nvidia-smi` process
  start, since the other reads are plain `/proc` and `/sys` files. A controller should reuse an
  existing poller rather than add its own.

Held-out split for this trace (time-contiguous): `WolframLanguageEvaluator: {Floor[2*360/3], 360 - Floor[2*360/3]} -> {240, 120}`,
so rows seq 0..239 train and seq 240..359 are held out.

R0 replay on this trace (section 6.4 rules 1-4 only; the nvme and clock-reason clauses are
NOT_RUN because those fields were not sampled): R0 chooses A0 (keep) on all 360 rows. The hottest
row, 93.9 C, stays under the 95 C pause threshold, and no PSI threshold is crossed. So on this
window the label set is degenerate: a policy imitating R0 would learn "always keep", and
agreement with R0 would say nothing. This is a MEASURED finding about the data, not about a model.

## 6. Controller spec (PROPOSED)

### 6.1 Boundary

- Offline replay (this study): the actions in 6.2 are modelled with sched's words `sched_cap`,
  `sched_policy`, `sched_pause`. A refused call (-7, -8) means no change, logged. Nothing is
  written to a live scheduler.
- Live use (later, owned by pearl DRA-431 and DRA-430): a controller must NOT call `sched_*`
  directly in a journaled Node, because a direct call is not journaled and crash replay would
  diverge (sched, BOARD line 2026-11-07T06:32:58Z). It targets `jn_cap` and `jn_policy`
  (journaled as a type 11 POLICY record before `sched_cap`/`sched_policy` take effect) and
  `auth_pause` (journaled PAUSE), once DRA-398 lands. Source:
  `~/handoffs/hive/sched/dra398-design.md`, mtime 2026-11-07T00:28:35-06:00, 151 lines, sha256
  `333ff9060c5217a9d9c6241291afa69ae4e5c800175429bf7d3c089b482ea517`, lines 63-65 and 137.
  That design and those journaled words are PROPOSED, not implemented.
- Never writes clocks, power limits, firmware, or GPU state (pearl CAPABILITY-MATRIX line 62).
- Telemetry older than 15 s, or any read error, forces the fail-safe action (pause new
  assignments; running jobs continue). The model is never asked in that case.
- Decision point: every sched step tick, rate-limited to one decision per 10 s, plus once on
  each admission. Decisions use the snapshot taken at the tick.

### 6.2 Action set (7 discrete actions)

| Id | Action | Offline model (sched word) |
|---|---|---|
| A0 | keep | none |
| A1 | pause new assignments | `sched_pause c true` |
| A2 | resume | `sched_pause c false` |
| A3 | inference slots minus 1 | `sched_cap` with kind 2 lowered by 1 (refused below use) |
| A4 | inference slots plus 1, up to the configured maximum | `sched_cap` kind 2 raised by 1 |
| A5 | CPU slots minus 1 | `sched_cap` kind 0 lowered by 1 |
| A6 | CPU slots plus 1, up to the configured maximum | `sched_cap` kind 0 raised by 1 |

Memory capacity (kind 1) is not a model action. A fixed guard sets it to MemAvailable minus a
reserve; that guard belongs to DRA-430.

### 6.3 Features (16 inputs)

load1; runnable count; PSI cpu some avg10; PSI memory some and full avg10; PSI io some and full
avg10; mean per-core busy %; max acpitz C; MemAvailable / MemTotal; GPU util %; GPU W; GPU C;
SM MHz; UPS W (PARTIAL); telemetry age s. The reduced set available in the 18-day sensors history
is: load1, MemAvailable, GPU util, GPU W, UPS W, lock holders.

### 6.4 Baseline rule R0 (deterministic, no model)

Evaluated in order; first match wins; thresholds have hysteresis so R0 does not flap.

1. Telemetry stale or unreadable: A1.
2. Max acpitz at or above 95 C, or nvme composite at or above 80 C: A1. Resume (A2) only when
   acpitz is below 90 C and nvme below 75 C.
3. PSI memory some avg10 above 10: A3 if any inference slot is in use, else A5.
4. PSI cpu some avg10 above 50: A5. Below 20 for three decisions: A6.
5. GPU clock event reasons show thermal or power braking: A3.
6. Otherwise: A0.

Thresholds are design starting points, not measured optima. The acpitz values sit below the
critical trip of 104.8 C recorded by pearl.

### 6.5 Tiny learned policy

One hidden layer, 32 units, ReLU, 7 outputs, written in `.om` with `f64` (an OM-1 keyword at
omega-mv `e5b32567`; looked up with the omega lookup tool). Size:
`WolframLanguageEvaluator: 16*32 + 32 + 32*7 + 7 -> 775` parameters, and
`WolframLanguageEvaluator: 16*32 + 32*7 -> 736` multiply-adds per decision. Training starts from
imitation of R0, then from a cost signal (section 6.7). The model output is only a ranking; the
action executed is the top-ranked action that sched accepts, so an invalid choice cannot reach
the scheduler.

### 6.6 Held-out split

Time-contiguous, never shuffled. Reduced features: train on sensors files 2026-10-19 to
2026-11-02, hold out 2026-11-03 to 2026-11-06. Full features: first two thirds of each new trace
for training, last third held out (section 5: rows 0..239 train, 240..359 held out). Any trace whose window
overlaps a spark-window record is tagged with that window id so GPU-busy periods are not split
across train and test.

### 6.7 Metrics

- Decision agreement with R0 on held-out rows (exact match rate), with the confusion matrix.
- Regret proxy: count of held-out rows where the policy keeps or grows capacity while a rule-1 or
  rule-2 condition holds (must be 0), and rows where it pauses with all pressures low.
- Controller overhead: telemetry read time (measured in section 5) plus `.om` inference time,
  measured with `monons`, reported in microseconds.
- Replay cannot measure net benefit: the recorded telemetry does not react to the replayed
  action. Net useful work and energy need the on-device comparison in 6.8.
- Because R0 picks A0 on every row of trace-001, imitation agreement is only meaningful on data
  that contains pressure or heat events. The 18-day sensors history and spark-window records
  must be searched for such periods first; if they are too rare, a learned policy has nothing to
  learn over R0, and that is a valid negative result for DRA-431.

### 6.8 Bounded hardware-run plan (NOT_RUN; needs authorization)

Only after both lanes agree, pearl DRA-430 provides the action path and DRA-398 lands; the arms
act only through `jn_cap`, `jn_policy` and `auth_pause`, never `sched_*` directly. One authorized
spark-window, a fixed synthetic job mix through sched, three arms of equal length (sched defaults,
R0, learned policy), order randomized, one decision per 10 s, no clock or power writes. Record
completed jobs, sched overdue count, PSI, acpitz, GPU W and UPS W. Wall energy stays
BLOCKED_INPUT until a qualified meter exists; UPS W is reported as PARTIAL only.

## 7. BOARD proposal and replies

Posted to `~/handoffs/BOARD.md` at 2026-11-07T06:27:07Z addressed to sched and pearl (the line
with `wsp/CtlTraces PROPOSE`). It asked sched to confirm the three words above are the stable
action interface, and pearl to say whether DRA-431 accepts this offline study as its replay input
or wants wsp to stand down.

sched replied at 2026-11-07T06:32:58Z (`grep '06:32:58Z sched to wsp' ~/handoffs/BOARD.md`): the
words exist at head `9f5ebd35` (#1064); the offline study may model them; a live controller uses
`jn_cap` / `jn_policy` / `auth_pause` after DRA-398, whose journaled words are PROPOSED. Linear
DRA-438 is rescoped as the offline study feeding pearl's DRA-431. No reply from pearl is recorded
in this document.

## 8. Open risks

- DRA-431 overlap: if pearl takes DRA-431 itself, this study should stop and hand over the
  trace and inventory only.
- sched defaults (65535 per kind) make `sched_cap` actions inert until real capacities are set.
- `spark-sensors` already calls nvidia-smi about every 2 s, faster than the 5 s rule this lane
  follows; any controller should reuse that log instead of adding a second poller.
- UPS load is integer % of a whole UPS with unknown other loads; it is not energy evidence.
- The trace in section 5 is one 30 minute window on a loaded machine; it is not representative
  of idle or GPU-exclusive periods, and R0 never acts on it.
