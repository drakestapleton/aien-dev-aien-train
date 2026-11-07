Module[{j, s0, s1, cpu, busy, la, psi, mi, g, gk, u, uv, chk, res},
j = ImportString["{\"battery_runtime_s\": 2425, \"core_busy_pct\": {\"c0\": 14.02, \"c1\": 100.0, \"c10\": 10.53, \"c11\": 9.11, \"c12\": 10.14, \"c13\": 14.58, \"c14\": 13.56, \"c15\": 15.38, \"c16\": 79.44, \"c17\": 85.0, \"c18\": 100.0, \"c19\": 100.0, \"c2\": 10.37, \"c3\": 9.33, \"c4\": 33.73, \"c5\": 8.5, \"c6\": 83.77, \"c7\": 7.89, \"c8\": 12.5, \"c9\": 100.0}, \"gpu_mem_util_pct\": 0.0, \"gpu_power_w\": 43.32, \"gpu_pstate\": \"P0\", \"gpu_sm_mhz\": 2489.0, \"gpu_temp_c\": 64.0, \"gpu_util_pct\": 59.0, \"input_voltage\": 121, \"loadavg\": [15.08, 12.89, 10.25], \"mem\": {\"MemAvailable_kb\": 80861856, \"MemTotal_kb\": 127598532, \"SwapFree_kb\": 0, \"SwapTotal_kb\": 0}, \"psi_cpu\": {\"full_avg10\": 0.0, \"full_avg300\": 0.0, \"full_avg60\": 0.0, \"full_total\": 0, \"some_avg10\": 14.63, \"some_avg300\": 7.47, \"some_avg60\": 12.19, \"some_total\": 69344049548}, \"psi_io\": {\"full_avg10\": 0.7, \"full_avg300\": 5.52, \"full_avg60\": 4.95, \"full_total\": 12781931497, \"some_avg10\": 0.87, \"some_avg300\": 6.21, \"some_avg60\": 5.65, \"some_total\": 13653017639}, \"psi_mem\": {\"full_avg10\": 0.0, \"full_avg300\": 0.06, \"full_avg60\": 0.03, \"full_total\": 1062091006, \"some_avg10\": 0.0, \"some_avg300\": 0.06, \"some_avg60\": 0.03, \"some_total\": 1119903639}, \"runnable\": \"13/4631\", \"sample_cost_us\": 75947, \"seq\": 0, \"thermal_c\": {\"tz0\": 88.0, \"tz1\": 68.6, \"tz2\": 70.8, \"tz3\": 65.5, \"tz4\": 88.0, \"tz5\": 68.7, \"tz6\": 72.4}, \"ts_unix\": 1794038059.047, \"ts_utc\": \"2026-11-07T07:54:19Z\", \"ups_load_pct\": 26, \"ups_realpower_nominal_w\": 1000, \"ups_status\": \"OL\"}", "RawJSON"];
s0 = "cpu  44035889 194110758 69277819 1278104888 14812188 0 422793 0 0 301
cpu0 1537457 5493532 3354242 67894498 1010254 0 20528 0 0 9
cpu1 1390159 6962803 3108863 67463160 914203 0 57483 0 0 0
cpu2 1319951 5736446 3236797 68556202 1097280 0 4426 0 0 0
cpu3 1296602 6566249 3097774 68204925 860970 0 4111 0 0 51
cpu4 1219410 6793037 3130773 68138613 742379 0 4062 0 0 9
cpu5 4940688 7366784 3366994 63698315 722563 0 8812 0 0 16
cpu6 3263262 12608218 3251381 60437324 583937 0 6185 0 0 12
cpu7 3368276 10095867 3019429 63035777 609052 0 7155 0 0 53
cpu8 3377952 11690942 3372752 61132304 554337 0 7247 0 0 20
cpu9 3067345 12777921 3073238 60804283 446864 0 6299 0 0 0
cpu10 1126177 14163827 5312686 58567053 875147 0 5133 0 0 25
cpu11 1130915 14106156 5150073 58931097 774568 0 4754 0 0 38
cpu12 1174481 11503737 3595173 62830190 959899 0 4083 0 0 30
cpu13 1344118 11234045 3513296 62848085 664561 0 224575 0 0 0
cpu14 1301059 11934297 3532303 62674485 641917 0 20456 0 0 0
cpu15 2939483 9364164 3331848 63657711 712900 0 7529 0 0 10
cpu16 2806888 8848019 3331154 64413169 732914 0 7522 0 0 0
cpu17 2797333 8872676 3198017 64591135 696867 0 7473 0 0 17
cpu18 2381460 9006300 3191570 64938343 655288 0 7433 0 0 3
cpu19 2252864 8985730 3109448 65288211 556278 0 7515 0 0 0
intr 13470482764 0 361135438 23819867 0 0 65783129 1304132 0 0 2 0 2258 3398147460 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 4 0 0 2570909 420521 41 0 0 6101 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 358 0 0 0 0 0 0 0 0 0 0 0 222375656 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 1 0 1 1 0 1 0 0 1 0 0 1 0 0 0 0 85822842 0 0 0 0 0 0 0 92468258 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 42600 63822469 65946545 58162991 34883500 33111619 30667979 26385486 71836145 73316401 32739482 32518817 28825210 27609143 25587101 20857640 5206 0 136047 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 182813
ctxt 14663970776
btime 1793232395
processes 376816862
procs_running 10
procs_blocked 0
softirq 3990737884 710952 326840632 36038 356090114 26821900 0 5254953 591666925 5588253 2677728117
"; s1 = "cpu  44036429 194113840 69278267 1278110637 14812270 0 422799 0 0 301
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
";
cpu[s_] := Association@Cases[StringSplit[s, "\n"], l_ /; StringMatchQ[l, "cpu" ~~ DigitCharacter .. ~~ " " ~~ ___] :> (StringReplace[First[StringSplit[l]], "cpu" -> "c"] -> ToExpression /@ Take[Rest[StringSplit[l]], 8])];
busy = Association@KeyValueMap[Function[{c, b}, c -> With[{a = cpu[s0][c]}, With[{dt = Total[b] - Total[a], di = b[[4]] + b[[5]] - a[[4]] - a[[5]]}, If[dt > 0, 100 (dt - di)/dt, Null]]]], cpu[s1]];
la = StringSplit["15.08 12.89 10.25 13/4631 3706149
"];
psi[t_] := Association@Flatten@Map[Function[l, With[{w = StringSplit[l]}, (First[w] <> "_" <> First[#] -> ToExpression[Last[#]]) & /@ (StringSplit[#, "="] & /@ Rest[w])]], StringSplit[t, "\n"]];
mi = Association@Cases[StringSplit["MemTotal:       127598532 kB
MemFree:        32743304 kB
MemAvailable:   80861856 kB
Buffers:         8941560 kB
Cached:         39976704 kB
SwapCached:            0 kB
Active:         21709332 kB
Inactive:       46383268 kB
Active(anon):   20834140 kB
Inactive(anon): 14104320 kB
Active(file):     875192 kB
Inactive(file): 32278948 kB
Unevictable:       31020 kB
Mlocked:           22912 kB
SwapTotal:             0 kB
SwapFree:              0 kB
Zswap:                 0 kB
Zswapped:              0 kB
Dirty:            949188 kB
Writeback:             0 kB
AnonPages:      19205788 kB
Mapped:          1601028 kB
Shmem:          15762376 kB
KReclaimable:   21158036 kB
Slab:           24577528 kB
SReclaimable:   21158036 kB
SUnreclaim:      3419492 kB
KernelStack:       74304 kB
ShadowCallStack:   18680 kB
PageTables:       243032 kB
SecPageTables:     42840 kB
NFS_Unstable:          0 kB
Bounce:                0 kB
WritebackTmp:          0 kB
CommitLimit:    63799264 kB
Committed_AS:   183995644 kB
VmallocTotal:   135288315904 kB
VmallocUsed:      189276 kB
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
g = StringTrim /@ StringSplit[First[StringSplit["59, 0, 43.32, 64, 2489, P0
", "\n"]], ","];
gk = {"gpu_util_pct", "gpu_mem_util_pct", "gpu_power_w", "gpu_temp_c", "gpu_sm_mhz", "gpu_pstate"};
u = Association@Cases[StringSplit["battery.charge: 100
battery.charge.low: 10
battery.charge.warning: 20
battery.mfr.date: CPS
battery.runtime: 2425
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
 Flatten[Table[With[{ps = psi[t[[2]]]}, KeyValueMap[chk[t[[1]] <> "." <> #1, #2, j[t[[1]]][#1], 0] &, ps]], {t, {{"psi_cpu", "some avg10=14.63 avg60=12.19 avg300=7.47 total=69344049548
full avg10=0.00 avg60=0.00 avg300=0.00 total=0
"}, {"psi_mem", "some avg10=0.00 avg60=0.03 avg300=0.06 total=1119903639
full avg10=0.00 avg60=0.03 avg300=0.06 total=1062091006
"}, {"psi_io", "some avg10=0.87 avg60=5.65 avg300=6.21 total=13653017639
full avg10=0.70 avg60=4.95 avg300=5.52 total=12781931497
"}}}], 1],
 MapIndexed[chk["thermal_c.tz" <> ToString[First[#2] - 1], ToExpression[StringTrim[#1]]/1000, j["thermal_c"]["tz" <> ToString[First[#2] - 1]], 0] &, {"88000
", "68600
", "70800
", "65500
", "88000
", "68700
", "72400
"}],
 chk["mem." <> #, mi[#], j["mem"][#], 0] & /@ {"MemTotal_kb", "MemAvailable_kb", "SwapTotal_kb", "SwapFree_kb"},
 MapThread[chk[#1, If[StringMatchQ[#2, NumberString], ToExpression[#2], #2], j[#1], 0] &, {gk, g}],
 {chk["ups_load_pct", uv["ups.load"], j["ups_load_pct"], 0], chk["ups_realpower_nominal_w", uv["ups.realpower.nominal"], j["ups_realpower_nominal_w"], 0], chk["ups_status", u["ups.status"], j["ups_status"], 0], chk["input_voltage", uv["input.voltage"], j["input_voltage"], 0], chk["battery_runtime_s", uv["battery.runtime"], j["battery_runtime_s"], 0]},
 {chk["ts_utc_vs_ts_unix", DateString[FromUnixTime[Floor[j["ts_unix"]], TimeZone -> 0], {"Year", "-", "Month", "-", "Day", "T", "Hour", ":", "Minute", ":", "Second", "Z"}], j["ts_utc"], 0]}];
<|"seq" -> j["seq"], "checked" -> Length[res], "failed" -> Select[res, ! Last[#] &], "rows" -> ({#[[1]], If[NumericQ[#[[2]]] && ! IntegerQ[#[[2]]], N[#[[2]], 8], #[[2]]], #[[3]], #[[4]]} & /@ res)|>]
