Module[{j, s0, s1, cpu, busy, la, psi, mi, g, gk, u, uv, chk, res},
j = ImportString["{\"battery_runtime_s\": 1950, \"core_busy_pct\": {\"c0\": 9.09, \"c1\": 100.0, \"c10\": 11.09, \"c11\": 9.61, \"c12\": 11.48, \"c13\": 11.2, \"c14\": 12.22, \"c15\": 8.38, \"c16\": 100.0, \"c17\": 10.55, \"c18\": 9.09, \"c19\": 100.0, \"c2\": 10.72, \"c3\": 8.33, \"c4\": 48.89, \"c5\": 5.89, \"c6\": 94.98, \"c7\": 6.07, \"c8\": 21.91, \"c9\": 82.93}, \"gpu_mem_util_pct\": 0.0, \"gpu_power_w\": 42.79, \"gpu_pstate\": \"P0\", \"gpu_sm_mhz\": 2509.0, \"gpu_temp_c\": 62.0, \"gpu_util_pct\": 59.0, \"input_voltage\": 121, \"loadavg\": [12.5, 12.46, 10.18], \"mem\": {\"MemAvailable_kb\": 80698916, \"MemTotal_kb\": 127598532, \"SwapFree_kb\": 0, \"SwapTotal_kb\": 0}, \"psi_cpu\": {\"full_avg10\": 0.0, \"full_avg300\": 0.0, \"full_avg60\": 0.0, \"full_total\": 0, \"some_avg10\": 4.83, \"some_avg300\": 7.61, \"some_avg60\": 10.82, \"some_total\": 69346293943}, \"psi_io\": {\"full_avg10\": 1.51, \"full_avg300\": 5.15, \"full_avg60\": 3.64, \"full_total\": 12782320571, \"some_avg10\": 1.52, \"some_avg300\": 5.78, \"some_avg60\": 4.09, \"some_total\": 13653426371}, \"psi_mem\": {\"full_avg10\": 0.0, \"full_avg300\": 0.05, \"full_avg60\": 0.02, \"full_total\": 1062097253, \"some_avg10\": 0.0, \"some_avg300\": 0.06, \"some_avg60\": 0.02, \"some_total\": 1119909932}, \"runnable\": \"9/4652\", \"sample_cost_us\": 76039, \"seq\": 5, \"thermal_c\": {\"tz0\": 74.5, \"tz1\": 65.7, \"tz2\": 69.9, \"tz3\": 62.8, \"tz4\": 74.5, \"tz5\": 66.8, \"tz6\": 66.6}, \"ts_unix\": 1794038084.047, \"ts_utc\": \"2026-11-07T07:54:44Z\", \"ups_load_pct\": 25, \"ups_realpower_nominal_w\": 1000, \"ups_status\": \"OL\"}", "RawJSON"];
s0 = "cpu  44038344 194123639 69280605 1278135251 14813104 0 422827 0 0 301
cpu0 1537679 5493560 3354344 67896540 1010300 0 20529 0 0 9
cpu1 1390159 6965151 3109007 67463160 914203 0 57491 0 0 0
cpu2 1320102 5736503 3236869 68558310 1097353 0 4427 0 0 0
cpu3 1296750 6566249 3097825 68207139 861018 0 4112 0 0 51
cpu4 1219507 6793670 3130810 68140275 742427 0 4063 0 0 9
cpu5 4940819 7366785 3367036 63700550 722624 0 8813 0 0 16
cpu6 3263272 12610365 3251394 60437649 583938 0 6186 0 0 12
cpu7 3368400 10095867 3019474 63038035 609094 0 7155 0 0 53
cpu8 3378136 11690977 3372799 61134483 554368 0 7248 0 0 20
cpu9 3067347 12779119 3074485 60804332 446868 0 6299 0 0 0
cpu10 1126314 14163847 5312867 58569101 875200 0 5133 0 0 25
cpu11 1131064 14106234 5150328 58933004 774632 0 4754 0 0 38
cpu12 1174646 11503739 3595263 62832253 960030 0 4085 0 0 30
cpu13 1344364 11234047 3513379 62850100 664630 0 224591 0 0 0
cpu14 1301286 11934298 3532395 62676550 641992 0 20457 0 0 0
cpu15 2939719 9364165 3331924 63659801 712969 0 7530 0 0 10
cpu16 2806946 8849543 3331217 64413990 732940 0 7523 0 0 0
cpu17 2797449 8873378 3198125 64592627 696935 0 7474 0 0 17
cpu18 2381512 9007905 3191607 64939133 655296 0 7433 0 0 3
cpu19 2252864 8988229 3109448 65288211 556278 0 7515 0 0 0
intr 13471176959 0 361141287 24053966 0 0 65783778 1304181 0 0 2 0 2258 3398541012 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 4 0 0 2570980 420521 41 0 0 6101 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 358 0 0 0 0 0 0 0 0 0 0 0 222387737 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 1 0 1 1 0 1 0 0 1 0 0 1 0 0 0 0 85830743 0 0 0 0 0 0 0 92476591 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 42603 63829008 65953457 58167026 34884287 33113752 30668348 26385486 71837191 73319098 32741611 32521014 28825247 27610872 25587874 20857840 5206 0 136047 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 182840
ctxt 14664678269
btime 1793232395
processes 376823534
procs_running 10
procs_blocked 0
softirq 3990938033 710965 326859203 36039 356126795 26823838 0 5256211 591688811 5588503 2677847668
"; s1 = "cpu  44038714 194126165 69281039 1278141352 14813501 0 422835 0 0 301
cpu0 1537701 5493561 3354364 67896955 1010325 0 20530 0 0 9
cpu1 1390159 6965615 3109041 67463160 914203 0 57493 0 0 0
cpu2 1320122 5736519 3236885 68558708 1097388 0 4427 0 0 0
cpu3 1296780 6566250 3097835 68207576 861032 0 4112 0 0 51
cpu4 1219512 6793902 3130816 68140522 742434 0 4063 0 0 9
cpu5 4940836 7366786 3367047 63700974 722663 0 8813 0 0 16
cpu6 3263272 12610832 3251400 60437674 583938 0 6186 0 0 12
cpu7 3368418 10095867 3019485 63038479 609114 0 7156 0 0 53
cpu8 3378149 11691048 3372823 61134846 554390 0 7248 0 0 20
cpu9 3067348 12779370 3074646 60804415 446870 0 6299 0 0 0
cpu10 1126338 14163859 5312884 58569503 875231 0 5134 0 0 25
cpu11 1131093 14106234 5150346 58933433 774645 0 4754 0 0 38
cpu12 1174680 11503742 3595281 62832619 960088 0 4085 0 0 30
cpu13 1344399 11234049 3513392 62850500 664658 0 224595 0 0 0
cpu14 1301332 11934298 3532408 62676971 642002 0 20458 0 0 0
cpu15 2939745 9364165 3331939 63660204 713014 0 7530 0 0 10
cpu16 2806946 8850043 3331217 64413990 732940 0 7523 0 0 0
cpu17 2797478 8873380 3198146 64593049 696954 0 7474 0 0 17
cpu18 2381533 9007908 3191627 64939552 655327 0 7434 0 0 3
cpu19 2252864 8988729 3109448 65288211 556278 0 7515 0 0 0
intr 13471316591 0 361142120 24093679 0 0 65783932 1304185 0 0 2 0 2258 3398613863 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 4 0 0 2570988 420521 41 0 0 6101 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 358 0 0 0 0 0 0 0 0 0 0 0 222390448 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 1 0 1 1 0 1 0 0 1 0 0 1 0 0 0 0 85832254 0 0 0 0 0 0 0 92478181 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 42603 63831413 65957704 58169579 34884287 33114750 30670024 26385486 71838543 73321528 32741951 32522951 28825247 27611981 25588973 20857950 5206 0 136047 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 182840
ctxt 14664818732
btime 1793232395
processes 376824270
procs_running 7
procs_blocked 0
softirq 3990976380 710967 326863139 36043 356134023 26824329 0 5256368 591693267 5588553 2677869691
";
cpu[s_] := Association@Cases[StringSplit[s, "\n"], l_ /; StringMatchQ[l, "cpu" ~~ DigitCharacter .. ~~ " " ~~ ___] :> (StringReplace[First[StringSplit[l]], "cpu" -> "c"] -> ToExpression /@ Take[Rest[StringSplit[l]], 8])];
busy = Association@KeyValueMap[Function[{c, b}, c -> With[{a = cpu[s0][c]}, With[{dt = Total[b] - Total[a], di = b[[4]] + b[[5]] - a[[4]] - a[[5]]}, If[dt > 0, 100 (dt - di)/dt, Null]]]], cpu[s1]];
la = StringSplit["12.50 12.46 10.18 9/4652 3713107
"];
psi[t_] := Association@Flatten@Map[Function[l, With[{w = StringSplit[l]}, (First[w] <> "_" <> First[#] -> ToExpression[Last[#]]) & /@ (StringSplit[#, "="] & /@ Rest[w])]], StringSplit[t, "\n"]];
mi = Association@Cases[StringSplit["MemTotal:       127598532 kB
MemFree:        33543488 kB
MemAvailable:   80698916 kB
Buffers:         9244500 kB
Cached:         38712300 kB
SwapCached:            0 kB
Active:         21758548 kB
Inactive:       45335708 kB
Active(anon):   20856316 kB
Inactive(anon): 14045788 kB
Active(file):     902232 kB
Inactive(file): 31289920 kB
Unevictable:       31020 kB
Mlocked:           22912 kB
SwapTotal:             0 kB
SwapFree:              0 kB
Zswap:                 0 kB
Zswapped:              0 kB
Dirty:            883420 kB
Writeback:             0 kB
AnonPages:      19168844 kB
Mapped:          1588872 kB
Shmem:          15762684 kB
KReclaimable:   21156900 kB
Slab:           24578260 kB
SReclaimable:   21156900 kB
SUnreclaim:      3421360 kB
KernelStack:       74928 kB
ShadowCallStack:   18824 kB
PageTables:       245220 kB
SecPageTables:     42840 kB
NFS_Unstable:          0 kB
Bounce:                0 kB
WritebackTmp:          0 kB
CommitLimit:    63799264 kB
Committed_AS:   185482348 kB
VmallocTotal:   135288315904 kB
VmallocUsed:      188404 kB
VmallocChunk:          0 kB
Percpu:            52800 kB
HardwareCorrupted:     0 kB
AnonHugePages:   1949696 kB
ShmemHugePages:        0 kB
ShmemPmdMapped:        0 kB
FileHugePages:    135168 kB
FilePmdMapped:         0 kB
CmaTotal:              0 kB
CmaFree:          105912 kB
Balloon:               0 kB
HugePages_Total:       0
HugePages_Free:        0
HugePages_Rsvd:        0
HugePages_Surp:        0
Hugepagesize:       2048 kB
Hugetlb:               0 kB
", "\n"], l_ :> (StringTrim[First[StringSplit[l, ":"]]] <> "_kb" -> ToExpression[First[StringSplit[Last[StringSplit[l, ":"]]]]])];
g = StringTrim /@ StringSplit[First[StringSplit["59, 0, 42.79, 62, 2509, P0
", "\n"]], ","];
gk = {"gpu_util_pct", "gpu_mem_util_pct", "gpu_power_w", "gpu_temp_c", "gpu_sm_mhz", "gpu_pstate"};
u = Association@Cases[StringSplit["battery.charge: 100
battery.charge.low: 10
battery.charge.warning: 20
battery.mfr.date: CPS
battery.runtime: 1950
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
ups.load: 25
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
 Flatten[Table[With[{ps = psi[t[[2]]]}, KeyValueMap[chk[t[[1]] <> "." <> #1, #2, j[t[[1]]][#1], 0] &, ps]], {t, {{"psi_cpu", "some avg10=4.83 avg60=10.82 avg300=7.61 total=69346293943
full avg10=0.00 avg60=0.00 avg300=0.00 total=0
"}, {"psi_mem", "some avg10=0.00 avg60=0.02 avg300=0.06 total=1119909932
full avg10=0.00 avg60=0.02 avg300=0.05 total=1062097253
"}, {"psi_io", "some avg10=1.52 avg60=4.09 avg300=5.78 total=13653426371
full avg10=1.51 avg60=3.64 avg300=5.15 total=12782320571
"}}}], 1],
 MapIndexed[chk["thermal_c.tz" <> ToString[First[#2] - 1], ToExpression[StringTrim[#1]]/1000, j["thermal_c"]["tz" <> ToString[First[#2] - 1]], 0] &, {"74500
", "65700
", "69900
", "62800
", "74500
", "66800
", "66600
"}],
 chk["mem." <> #, mi[#], j["mem"][#], 0] & /@ {"MemTotal_kb", "MemAvailable_kb", "SwapTotal_kb", "SwapFree_kb"},
 MapThread[chk[#1, If[StringMatchQ[#2, NumberString], ToExpression[#2], #2], j[#1], 0] &, {gk, g}],
 {chk["ups_load_pct", uv["ups.load"], j["ups_load_pct"], 0], chk["ups_realpower_nominal_w", uv["ups.realpower.nominal"], j["ups_realpower_nominal_w"], 0], chk["ups_status", u["ups.status"], j["ups_status"], 0], chk["input_voltage", uv["input.voltage"], j["input_voltage"], 0], chk["battery_runtime_s", uv["battery.runtime"], j["battery_runtime_s"], 0]},
 {chk["ts_utc_vs_ts_unix", DateString[FromUnixTime[Floor[j["ts_unix"]], TimeZone -> 0], {"Year", "-", "Month", "-", "Day", "T", "Hour", ":", "Minute", ":", "Second", "Z"}], j["ts_utc"], 0]}];
<|"seq" -> j["seq"], "checked" -> Length[res], "failed" -> Select[res, ! Last[#] &], "rows" -> ({#[[1]], If[NumericQ[#[[2]]] && ! IntegerQ[#[[2]]], N[#[[2]], 8], #[[2]]], #[[3]], #[[4]]} & /@ res)|>]
