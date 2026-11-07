#!/usr/bin/env python3
"""wsp controller telemetry sampler (external measurement instrument, not product).

Reads only world-readable kernel files and one-shot nvidia-smi queries. No root,
no GPU work submitted. Writes one JSON object per line to OUT.

Usage: taskset -c 0 nice -n 19 python3 sampler.py OUT.jsonl [interval_s] [count]
"""
import json
import subprocess
import sys
import time

OUT = sys.argv[1]
INTERVAL = float(sys.argv[2]) if len(sys.argv) > 2 else 5.0
COUNT = int(sys.argv[3]) if len(sys.argv) > 3 else 360
if INTERVAL < 5.0:
    sys.exit("interval must be >= 5 s (nvidia-smi read rate limit)")

NV_FIELDS = "utilization.gpu,utilization.memory,power.draw,temperature.gpu,clocks.sm,pstate"
NV_KEYS = ["gpu_util_pct", "gpu_mem_util_pct", "gpu_power_w", "gpu_temp_c", "gpu_sm_mhz", "gpu_pstate"]


def read(path):
    with open(path) as f:
        return f.read()


def psi(kind):
    out = {}
    for line in read(f"/proc/pressure/{kind}").splitlines():
        parts = line.split()
        tag = parts[0]
        for kv in parts[1:]:
            k, v = kv.split("=")
            out[f"{tag}_{k}"] = float(v) if k != "total" else int(v)
    return out


def cpu_times():
    cores = {}
    for line in read("/proc/stat").splitlines():
        if line.startswith("cpu") and line[3].isdigit():
            f = line.split()
            vals = [int(x) for x in f[1:]]
            idle = vals[3] + vals[4]  # idle + iowait
            cores[int(f[0][3:])] = (sum(vals[:8]), idle)  # exclude guest (already in user)
    return cores


def thermal():
    out = {}
    i = 0
    while True:
        try:
            out[f"tz{i}"] = int(read(f"/sys/class/thermal/thermal_zone{i}/temp")) / 1000.0
        except FileNotFoundError:
            break
        i += 1
    return out


def meminfo():
    want = {"MemTotal", "MemAvailable", "SwapTotal", "SwapFree"}
    out = {}
    for line in read("/proc/meminfo").splitlines():
        k, rest = line.split(":", 1)
        if k in want:
            out[k + "_kb"] = int(rest.split()[0])
    return out


def nvsmi():
    try:
        r = subprocess.run(
            ["nvidia-smi", f"--query-gpu={NV_FIELDS}", "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=4,
        )
    except subprocess.TimeoutExpired:
        return {"gpu_error": "timeout"}
    if r.returncode != 0:
        return {"gpu_error": f"rc={r.returncode}"}
    vals = [v.strip() for v in r.stdout.strip().splitlines()[0].split(",")]
    out = {}
    for k, v in zip(NV_KEYS, vals):
        try:
            out[k] = float(v)
        except ValueError:
            out[k] = v  # "[N/A]" or pstate string
    return out


def main():
    prev = cpu_times()
    next_t = time.monotonic() + INTERVAL
    with open(OUT, "a") as fo:
        for seq in range(COUNT):
            time.sleep(max(0.0, next_t - time.monotonic()))
            next_t += INTERVAL
            t0 = time.monotonic()
            cur = cpu_times()
            busy = {}
            for c in range(20):
                dt = cur[c][0] - prev[c][0]
                di = cur[c][1] - prev[c][1]
                busy[f"c{c}"] = round(100.0 * (dt - di) / dt, 2) if dt > 0 else None
            prev = cur
            la = read("/proc/loadavg").split()
            row = {
                "seq": seq,
                "ts_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "ts_unix": round(time.time(), 3),
                "loadavg": [float(la[0]), float(la[1]), float(la[2])],
                "runnable": la[3],
                "psi_cpu": psi("cpu"),
                "psi_mem": psi("memory"),
                "psi_io": psi("io"),
                "core_busy_pct": busy,
                "thermal_c": thermal(),
                "mem": meminfo(),
            }
            row.update(nvsmi())
            row["sample_cost_us"] = int((time.monotonic() - t0) * 1e6)
            fo.write(json.dumps(row, sort_keys=True) + "\n")
            fo.flush()


if __name__ == "__main__":
    main()
