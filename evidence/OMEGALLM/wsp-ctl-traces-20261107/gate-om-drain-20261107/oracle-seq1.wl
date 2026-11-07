Module[{j, s0, s1, cpu, busy, la, psi, mi, g, gk, u, uv, chk, res},
j = ImportString["{\"battery_runtime_s\": 1600, \"core_busy_pct\": {\"c0\": 25.51, \"c1\": 100.0, \"c10\": 19.88, \"c11\": 19.84, \"c12\": 13.01, \"c13\": 16.73, \"c14\": 14.63, \"c15\": 13.88, \"c16\": 57.83, \"c17\": 64.99, \"c18\": 100.0, \"c19\": 100.0, \"c2\": 11.41, \"c3\": 8.35, \"c4\": 28.23, \"c5\": 6.69, \"c6\": 91.18, \"c7\": 8.52, \"c8\": 7.68, \"c9\": 100.0}, \"gpu_mem_util_pct\": 0.0, \"gpu_power_w\": 43.41, \"gpu_pstate\": \"P0\", \"gpu_sm_mhz\": 2496.0, \"gpu_temp_c\": 64.0, \"gpu_util_pct\": 59.0, \"input_voltage\": 121, \"loadavg\": [14.68, 12.84, 10.25], \"mem\": {\"MemAvailable_kb\": 80561972, \"MemTotal_kb\": 127598532, \"SwapFree_kb\": 0, \"SwapTotal_kb\": 0}, \"psi_cpu\": {\"full_avg10\": 0.0, \"full_avg300\": 0.0, \"full_avg60\": 0.0, \"full_total\": 0, \"some_avg10\": 16.35, \"some_avg300\": 7.72, \"some_avg60\": 12.88, \"some_total\": 69344971075}, \"psi_io\": {\"full_avg10\": 0.71, \"full_avg300\": 5.42, \"full_avg60\": 4.54, \"full_total\": 12781989793, \"some_avg10\": 0.81, \"some_avg300\": 6.1, \"some_avg60\": 5.18, \"some_total\": 13653084474}, \"psi_mem\": {\"full_avg10\": 0.0, \"full_avg300\": 0.06, \"full_avg60\": 0.03, \"full_total\": 1062091006, \"some_avg10\": 0.0, \"some_avg300\": 0.06, \"some_avg60\": 0.03, \"some_total\": 1119903639}, \"runnable\": \"8/4674\", \"sample_cost_us\": 75089, \"seq\": 1, \"thermal_c\": {\"tz0\": 78.0, \"tz1\": 68.1, \"tz2\": 71.4, \"tz3\": 65.6, \"tz4\": 78.0, \"tz5\": 69.1, \"tz6\": 72.3}, \"ts_unix\": 1794038064.047, \"ts_utc\": \"2026-11-07T07:54:24Z\", \"ups_load_pct\": 26, \"ups_realpower_nominal_w\": 1000, \"ups_status\": \"OL\"}", "RawJSON"];
s0 = "cpu  44036429 194113840 69278267 1278110637 14812270 0 422799 0 0 301
cpu0 1537504 5493535 3354260 67894894 1010275 0 20528 0 0 9
cpu1 1390159 6963279 3108885 67463160 914203 0 57485 0 0 0
cpu2 1319990 5736447 3236808 68556623 1097300 0 4426 0 0 0
cpu3 1296640 6566249 3097782 68205366 860976 0 4111 0 0 51
cpu4 1219430 6793180 3130778 68138942 742380 0 4062 0 0 9
cpu5 4940720 7366784 3367004 63698762 722568 0 8812 0 0 16
cpu6 3263265 12608632 3251382 60437405 583937 0 6185 0 0 12
cpu7 3368304 10095867 3019440 63036228 609056 0 7155 0 0 53
cpu8 3378007 11690942 3372759 61132737 554338 0 7247 0 0 20
cpu9 3067345 12778185 3073473 60804283 446864 0 6299 0 0 0
cpu10 1126210 14163828 5312704 58567494 875148 0 5133 0 0 25
cpu11 1130948 14106156 5150085 58931546 774568 0 4754 0 0 38
cpu12 1174517 11503737 3595187 62830629 959903 0 4083 0 0 30
cpu13 1344173 11234045 3513309 62848499 664563 0 224578 0 0 0
cpu14 1301107 11934297 3532321 62674911 641918 0 20457 0 0 0
cpu15 2939546 9364164 3331861 63658128 712901 0 7529 0 0 10
cpu16 2806896 8848385 3331177 64413266 732920 0 7523 0 0 0
cpu17 2797337 8873088 3198026 64591201 696876 0 7473 0 0 17
cpu18 2381460 9006800 3191570 64938343 655288 0 7433 0 0 3
cpu19 2252864 8986229 3109448 65288211 556278 0 7515 0 0 0
intr 13470609196 0 361135774 23863986 0 0 65783261 1304138 0 0 2 0 2258 3398221287 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 4 0 0 2570921 420521 41 0 0 6101 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 358 0 0 0 0 0 0 0 0 0 0 0 222378342 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 1 0 1 1 0 1 0 0 1 0 0 1 0 0 0 0 85824495 0 0 0 0 0 0 0 92470028 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 42600 63822547 65946746 58163175 34883850 33111917 30667979 26385486 71836436 73316703 32739488 32518884 28825210 27609236 25587123 20857640 5206 0 136047 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 182813
ctxt 14664109207
btime 1793232395
processes 376817316
procs_running 12
procs_blocked 0
softirq 3990775226 710955 326844130 36038 356097371 26822003 0 5255235 591671301 5588303 2677749890
"; s1 = "cpu  44036955 194116662 69278935 1278116288 14812484 0 422807 0 0 301
cpu0 1537594 5493536 3354293 67895242 1010292 0 20529 0 0 9
cpu1 1390159 6963759 3108904 67463160 914203 0 57486 0 0 0
cpu2 1320031 5736448 3236821 68557031 1097327 0 4427 0 0 0
cpu3 1296668 6566249 3097795 68205804 860988 0 4111 0 0 51
cpu4 1219448 6793296 3130784 68139297 742381 0 4062 0 0 9
cpu5 4940746 7366784 3367011 63699208 722582 0 8812 0 0 16
cpu6 3263266 12609085 3251383 60437449 583937 0 6185 0 0 12
cpu7 3368337 10095867 3019449 63036668 609067 0 7155 0 0 53
cpu8 3378037 11690942 3372767 61133176 554356 0 7247 0 0 20
cpu9 3067345 12778405 3073753 60804283 446864 0 6299 0 0 0
cpu10 1126230 14163834 5312774 58567874 875155 0 5133 0 0 25
cpu11 1130976 14106161 5150149 58931928 774578 0 4754 0 0 38
cpu12 1174557 11503738 3595209 62831034 959926 0 4084 0 0 30
cpu13 1344227 11234046 3513332 62848887 664583 0 224582 0 0 0
cpu14 1301152 11934298 3532347 62675314 641935 0 20457 0 0 0
cpu15 2939592 9364164 3331883 63658539 712918 0 7530 0 0 10
cpu16 2806908 8848641 3331197 64413469 732927 0 7523 0 0 0
cpu17 2797349 8873369 3198056 64591360 696891 0 7473 0 0 17
cpu18 2381460 9007300 3191570 64938343 655288 0 7433 0 0 3
cpu19 2252864 8986729 3109448 65288211 556278 0 7515 0 0 0
intr 13470773535 0 361138179 23921207 0 0 65783332 1304154 0 0 2 0 2258 3398316147 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 4 0 0 2570929 420521 41 0 0 6101 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 358 0 0 0 0 0 0 0 0 0 0 0 222380252 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 1 0 1 1 0 1 0 0 1 0 0 1 0 0 0 0 85826134 0 0 0 0 0 0 0 92471735 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 42603 63824051 65947289 58163648 34883983 33112204 30667979 26385486 71836703 73317147 32739501 32519084 28825211 27609504 25587486 20857640 5206 0 136047 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 182816
ctxt 14664294364
btime 1793232395
processes 376819769
procs_running 8
procs_blocked 1
softirq 3990819918 710957 326848179 36038 356105154 26822247 0 5255446 591675804 5588353 2677777740
";
cpu[s_] := Association@Cases[StringSplit[s, "\n"], l_ /; StringMatchQ[l, "cpu" ~~ DigitCharacter .. ~~ " " ~~ ___] :> (StringReplace[First[StringSplit[l]], "cpu" -> "c"] -> ToExpression /@ Take[Rest[StringSplit[l]], 8])];
busy = Association@KeyValueMap[Function[{c, b}, c -> With[{a = cpu[s0][c]}, With[{dt = Total[b] - Total[a], di = b[[4]] + b[[5]] - a[[4]] - a[[5]]}, If[dt > 0, 100 (dt - di)/dt, Null]]]], cpu[s1]];
la = StringSplit["14.68 12.84 10.25 8/4674 3708602
"];
psi[t_] := Association@Flatten@Map[Function[l, With[{w = StringSplit[l]}, (First[w] <> "_" <> First[#] -> ToExpression[Last[#]]) & /@ (StringSplit[#, "="] & /@ Rest[w])]], StringSplit[t, "\n"]];
mi = Association@Cases[StringSplit["MemTotal:       127598532 kB
MemFree:        32360752 kB
MemAvailable:   80561972 kB
Buffers:         8944800 kB
Cached:         40056840 kB
SwapCached:            0 kB
Active:         21705624 kB
Inactive:       46440896 kB
Active(anon):   20827792 kB
Inactive(anon): 14081920 kB
Active(file):     877832 kB
Inactive(file): 32358976 kB
Unevictable:       31020 kB
Mlocked:           22912 kB
SwapTotal:             0 kB
SwapFree:              0 kB
Zswap:                 0 kB
Zswapped:              0 kB
Dirty:            938384 kB
Writeback:             0 kB
AnonPages:      19177424 kB
Mapped:          1572776 kB
Shmem:          15762620 kB
KReclaimable:   21158036 kB
Slab:           24577528 kB
SReclaimable:   21158036 kB
SUnreclaim:      3419492 kB
KernelStack:       75024 kB
ShadowCallStack:   18816 kB
PageTables:       243180 kB
SecPageTables:     42840 kB
NFS_Unstable:          0 kB
Bounce:                0 kB
WritebackTmp:          0 kB
CommitLimit:    63799264 kB
Committed_AS:   183910632 kB
VmallocTotal:   135288315904 kB
VmallocUsed:      190148 kB
VmallocChunk:          0 kB
Percpu:            52800 kB
HardwareCorrupted:     0 kB
AnonHugePages:   1949696 kB
ShmemHugePages:        0 kB
ShmemPmdMapped:        0 kB
FileHugePages:    165888 kB
FilePmdMapped:         0 kB
CmaTotal:              0 kB
CmaFree:           94088 kB
Balloon:               0 kB
HugePages_Total:       0
HugePages_Free:        0
HugePages_Rsvd:        0
HugePages_Surp:        0
Hugepagesize:       2048 kB
Hugetlb:               0 kB
", "\n"], l_ :> (StringTrim[First[StringSplit[l, ":"]]] <> "_kb" -> ToExpression[First[StringSplit[Last[StringSplit[l, ":"]]]]])];
g = StringTrim /@ StringSplit[First[StringSplit["59, 0, 43.41, 64, 2496, P0
", "\n"]], ","];
gk = {"gpu_util_pct", "gpu_mem_util_pct", "gpu_power_w", "gpu_temp_c", "gpu_sm_mhz", "gpu_pstate"};
u = Association@Cases[StringSplit["battery.charge: 100
battery.charge.low: 10
battery.charge.warning: 20
battery.mfr.date: CPS
battery.runtime: 1600
battery.runtime.low: 300
battery.type: PbAcid
battery.voltage: 27.2
battery.voltage.nominal: 24
device.mfr: CPS
device.model: CP1500PFCLCDa
device.serial: CXXRQ7011530
device.type: ups
driver.debug: 0
driver.flag.allow_killpower: 0
driver.name: usbhid-ups
driver.parameter.pollfreq: 30
driver.parameter.pollinterval: 2
driver.parameter.port: auto
driver.parameter.synchronous: auto
driver.parameter.vendorid: 0764
driver.state: quiet
driver.version: 2.8.1
driver.version.data: CyberPower HID 0.8
driver.version.internal: 0.52
driver.version.usb: libusb-1.0.27 (API: 0x100010a)
input.voltage: 121.0
input.voltage.nominal: 120
output.voltage: 121.0
ups.beeper.status: enabled
ups.delay.shutdown: 20
ups.delay.start: 30
ups.load: 26
ups.mfr: CPS
ups.model: CP1500PFCLCDa
ups.productid: 0601
ups.realpower.nominal: 1000
ups.serial: CXXRQ7011530
ups.status: OL
ups.test.result: No test initiated
ups.timer.shutdown: -60
ups.timer.start: -60
ups.vendorid: 0764
", "\n"], l_ /; StringContainsQ[l, ": "] :> (First[StringSplit[l, ": ", 2]] -> Last[StringSplit[l, ": ", 2]])];
uv[key_] := ToExpression[u[key]];
chk[name_, exp_, got_, tol_] := {name, exp, got, If[StringQ[exp] || exp === Null, exp === got, Abs[exp - got] <= tol]};
res = Join[
 KeyValueMap[chk["core_busy_pct." <> #1, #2, j["core_busy_pct"][#1], 1/200] &, busy],
 MapIndexed[chk["loadavg." <> ToString[First[#2] - 1], ToExpression[#1], j["loadavg"][[First[#2]]], 0] &, Take[la, 3]],
 {chk["runnable", la[[4]], j["runnable"], 0]},
 Flatten[Table[With[{ps = psi[t[[2]]]}, KeyValueMap[chk[t[[1]] <> "." <> #1, #2, j[t[[1]]][#1], 0] &, ps]], {t, {{"psi_cpu", "some avg10=16.35 avg60=12.88 avg300=7.72 total=69344971075
full avg10=0.00 avg60=0.00 avg300=0.00 total=0
"}, {"psi_mem", "some avg10=0.00 avg60=0.03 avg300=0.06 total=1119903639
full avg10=0.00 avg60=0.03 avg300=0.06 total=1062091006
"}, {"psi_io", "some avg10=0.81 avg60=5.18 avg300=6.10 total=13653084474
full avg10=0.71 avg60=4.54 avg300=5.42 total=12781989793
"}}}], 1],
 MapIndexed[chk["thermal_c.tz" <> ToString[First[#2] - 1], ToExpression[StringTrim[#1]]/1000, j["thermal_c"]["tz" <> ToString[First[#2] - 1]], 0] &, {"78000
", "68100
", "71400
", "65600
", "78000
", "69100
", "72300
"}],
 chk["mem." <> #, mi[#], j["mem"][#], 0] & /@ {"MemTotal_kb", "MemAvailable_kb", "SwapTotal_kb", "SwapFree_kb"},
 MapThread[chk[#1, If[StringMatchQ[#2, NumberString], ToExpression[#2], #2], j[#1], 0] &, {gk, g}],
 {chk["ups_load_pct", uv["ups.load"], j["ups_load_pct"], 0], chk["ups_realpower_nominal_w", uv["ups.realpower.nominal"], j["ups_realpower_nominal_w"], 0], chk["ups_status", u["ups.status"], j["ups_status"], 0], chk["input_voltage", uv["input.voltage"], j["input_voltage"], 0], chk["battery_runtime_s", uv["battery.runtime"], j["battery_runtime_s"], 0]},
 {chk["ts_utc_vs_ts_unix", DateString[FromUnixTime[Floor[j["ts_unix"]], TimeZone -> 0], {"Year", "-", "Month", "-", "Day", "T", "Hour", ":", "Minute", ":", "Second", "Z"}], j["ts_utc"], 0]}];
<|"seq" -> j["seq"], "checked" -> Length[res], "failed" -> Select[res, ! Last[#] &], "rows" -> ({#[[1]], If[NumericQ[#[[2]]] && ! IntegerQ[#[[2]]], N[#[[2]], 8], #[[2]]], #[[3]], #[[4]]} & /@ res)|>]
