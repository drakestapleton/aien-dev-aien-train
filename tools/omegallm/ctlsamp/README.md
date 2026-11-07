# ctlsamp: controller telemetry sampler (seeded Omega)

`ctlsamp.om` is the telemetry instrument for the wsp controller study (Linear DRA-187,
`docs/omegallm/WSP-CONTROLLER.md` section 5). It is the instrument going forward. It replaces the
old `sampler.py` and `ups-sampler.sh`, which produced the traces already filed in
`evidence/OMEGALLM/wsp-ctl-traces-20261107/` and were deleted when this port landed.

It is a measurement tool, not product code. It needs no root, does no GPU work and changes no
setting. Each sample it:

- reads `/proc/stat`, `/proc/loadavg`, `/proc/pressure/{cpu,memory,io}`,
  `/sys/class/thermal/thermal_zone*/temp` and `/proc/meminfo`;
- runs `nvidia-smi --query-gpu=utilization.gpu,utilization.memory,power.draw,temperature.gpu,clocks.sm,pstate --format=csv,noheader,nounits`
  once, through `fork`, `pipefds`, `dupfd` and `execprog`, with stdout on a pipe and stderr on
  `/dev/null`;
- runs `upsc spark` once the same way;
- appends one JSON object per line to OUT.

Timing uses `monons` (schedule and `sample_cost_us`) and `realns` (`ts_unix`, `ts_utc`).

## Build

With the pinned compiler (omega-mv `e5b32567`, omc sha256
`2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f`):

```
taskset -c 0 nice -n 19 omc < ctlsamp.om > ctlsamp && chmod +x ctlsamp
```

omc exits with the error code on a refused compile. Do not run the output of a refused compile.

## Usage

```
taskset -c 0 nice -n 19 ./ctlsamp OUT [interval_s] [count] [nvsmi_path] [upsc_path] [raw_log]
```

| Argument | Default | Rule |
|---|---|---|
| `OUT` | required | opened for append, created mode 0644 |
| `interval_s` | 5 | whole seconds, 5 to 86400. 5 is the floor because of the machine rule of at most one `nvidia-smi` read every 5 s |
| `count` | 360 | 0 to 999999 rows (999999 is the largest `while` bound this omc accepts) |
| `nvsmi_path` | `/usr/bin/nvidia-smi` | full path, no PATH search; an empty argument means the default |
| `upsc_path` | `/usr/bin/upsc` | full path, no PATH search; an empty argument means the default |
| `raw_log` | none | if given, every raw byte read is appended here (see below) |

The child processes get an empty environment. Run it on core 0 at nice 19, as above.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | all rows written |
| 2 | usage error, or OUT or raw_log could not be opened |
| 3 | a kernel file (`/proc/...`) could not be read; the old Python sampler crashed here too |

A failing `nvidia-smi` or `upsc` is not an exit: it is recorded in the row (next section).

## Row format

Keys are sorted and separated the way Python `json.dumps(row, sort_keys=True)` does (", " and
": "), so rows match `trace-001.jsonl` byte for byte in layout. Keys:

- `core_busy_pct` (`c0`..`c19`): busy share of each core since the previous sample, from
  `/proc/stat` (first 8 counters; idle is idle plus iowait), rounded half up to 2 decimals, or
  `null` when the core's counters did not move.
- `loadavg` (3 numbers) and `runnable` (string, for example `"6/3867"`) from `/proc/loadavg`.
- `psi_cpu`, `psi_mem`, `psi_io`: `some_` and `full_` `avg10`, `avg60`, `avg300` (numbers) and
  `total` (integer).
- `thermal_c` (`tz0`.. until the first missing zone): degrees C, millidegrees divided by 1000.
- `mem`: `MemTotal_kb`, `MemAvailable_kb`, `SwapTotal_kb`, `SwapFree_kb` (integers).
- `gpu_util_pct`, `gpu_mem_util_pct`, `gpu_power_w`, `gpu_temp_c`, `gpu_sm_mhz`: numbers printed
  the way Python prints a float (`93.0`, `44.64`); a field that is not a number (for example
  `[N/A]`) is kept as a string. `gpu_pstate` is a string.
- `battery_runtime_s`, `input_voltage`, `ups_load_pct`, `ups_realpower_nominal_w`: numbers in the
  awk `$2+0` style of the old shell sampler (`121.0` prints as `121`); `ups_status` is a string.
- `seq` (from 0), `ts_unix` (seconds, rounded to 3 decimals, trailing zeros dropped), `ts_utc`
  (`YYYY-MM-DDTHH:MM:SSZ` from the same clock read), `sample_cost_us` (integer).

These are the keys of `trace-001.jsonl` plus the UPS keys of `ups-001.jsonl`, now in one row.

Errors:

- `"gpu_error": "rc=N"` when `nvidia-smi` exits with code N (a path that cannot be executed gives
  `rc=127`), `"rc=-S"` when it dies on signal S, `"rc=-1001"` when the pipe or fork failed, and
  `"timeout"` when it has not finished in 4 s (it is then killed with signal 9). The six GPU keys
  are absent in that row, as in the old sampler.
- `"truncated"` when the command wrote more than 8192 bytes. The sampler keeps the first 8192
  bytes, reads the rest until the command ends and drops it, so a command with a large or endless
  output can never block on a full pipe. Both labels are joined when both apply, for example
  `"timeout,truncated"` for a command that writes without end and is killed at 4 s, or
  `"rc=1,truncated"`. The keys of that command are absent in that row.
- `"ups_error"` with the same forms when `upsc` fails. The five UPS keys are absent in that row.
  This differs from the old shell sampler, which wrote zeros when `upsc` failed.

## raw_log

With `raw_log`, each read is appended as a header line `== <seq> <source> <nbytes>`, then the exact
bytes, then a newline. Sources are the kernel file paths, `gpu` (the `nvidia-smi` stdout) and `ups`
(the `upsc` stdout). `/proc/stat` appears once before row 0 (the baseline) and once per row, so the
busy shares of row k come from the `/proc/stat` record of row k and the one before it. This is the
same-moment reading of the original commands used by the port gate.

## Gate checks and ORACLE label

The port gate (`evidence/OMEGALLM/wsp-ctl-traces-20261107/gate-om-20261107/`) compares the rows with
the raw log and with the independent sensors log; `gate-om-drain-20261107/` next to it holds the
large and endless output controls and a 30 s rerun of the same checks. The comparators are ORACLE
only and are not shipped:

- ORACLE: `/usr/bin/jq` (it reports `jaq 3.1.1`) for the key and type signature;
- ORACLE: Wolfram Language through the Wolfram MCP evaluator for the paired value checks. The
  Wolfram programs that ran are filed next to their outputs (`oracle-*.wl`, `oracle-*.out`).
