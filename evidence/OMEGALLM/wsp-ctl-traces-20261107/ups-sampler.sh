#!/bin/sh
# Companion instrument for trace-001: whole-UPS load from NUT (upsc spark), read-only.
# ups.load is an integer percent of ups.realpower.nominal (1000 W) for EVERYTHING on the UPS.
# It is coarse and unqualified: PARTIAL telemetry, never wall energy of the Spark.
# Usage: taskset -c 0 nice -n 19 sh ups-sampler.sh OUT.jsonl COUNT   (5 s interval)
out=$1
n=${2:-360}
i=0
while [ "$i" -lt "$n" ]; do
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  tu=$(date +%s.%N)
  v=$(timeout 4 upsc spark 2>/dev/null | awk -F': ' '
    $1=="ups.load"{l=$2} $1=="ups.realpower.nominal"{p=$2} $1=="ups.status"{s=$2}
    $1=="input.voltage"{iv=$2} $1=="battery.runtime"{rt=$2}
    END{printf "\"ups_load_pct\":%s,\"ups_realpower_nominal_w\":%s,\"ups_status\":\"%s\",\"input_voltage\":%s,\"battery_runtime_s\":%s", l+0, p+0, s, iv+0, rt+0}')
  printf '{"seq":%d,"ts_utc":"%s","ts_unix":%s,%s}\n' "$i" "$ts" "$tu" "$v" >> "$out"
  i=$((i + 1))
  sleep 5
done
