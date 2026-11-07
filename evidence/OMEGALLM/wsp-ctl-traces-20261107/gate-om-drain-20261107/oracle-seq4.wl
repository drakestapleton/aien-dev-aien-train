Module[{j, s0, s1, cpu, busy, la, psi, mi, g, gk, u, uv, chk, res},
j = ImportString["{\"battery_runtime_s\": 1950, \"core_busy_pct\": {\"c0\": 15.24, \"c1\": 100.0, \"c10\": 13.37, \"c11\": 11.27, \"c12\": 10.35, \"c13\": 14.11, \"c14\": 13.52, \"c15\": 10.79, \"c16\": 100.0, \"c17\": 16.13, \"c18\": 11.31, \"c19\": 100.0, \"c2\": 19.14, \"c3\": 7.74, \"c4\": 32.52, \"c5\": 5.89, \"c6\": 85.97, \"c7\": 6.1, \"c8\": 14.75, \"c9\": 89.42}, \"gpu_mem_util_pct\": 0.0, \"gpu_power_w\": 22.0, \"gpu_pstate\": \"P0\", \"gpu_sm_mhz\": 598.0, \"gpu_temp_c\": 58.0, \"gpu_util_pct\": 0.0, \"input_voltage\": 121, \"loadavg\": [12.89, 12.54, 10.19], \"mem\": {\"MemAvailable_kb\": 81492504, \"MemTotal_kb\": 127598532, \"SwapFree_kb\": 0, \"SwapTotal_kb\": 0}, \"psi_cpu\": {\"full_avg10\": 0.0, \"full_avg300\": 0.0, \"full_avg60\": 0.0, \"full_total\": 0, \"some_avg10\": 8.81, \"some_avg300\": 7.77, \"some_avg60\": 11.96, \"some_total\": 69346264326}, \"psi_io\": {\"full_avg10\": 1.1, \"full_avg300\": 5.21, \"full_avg60\": 3.81, \"full_total\": 12782201231, \"some_avg10\": 1.12, \"some_avg300\": 5.86, \"some_avg60\": 4.31, \"some_total\": 13653304856}, \"psi_mem\": {\"full_avg10\": 0.0, \"full_avg300\": 0.05, \"full_avg60\": 0.02, \"full_total\": 1062097253, \"some_avg10\": 0.0, \"some_avg300\": 0.06, \"some_avg60\": 0.02, \"some_total\": 1119909932}, \"runnable\": \"8/4644\", \"sample_cost_us\": 82126, \"seq\": 4, \"thermal_c\": {\"tz0\": 77.0, \"tz1\": 67.1, \"tz2\": 70.6, \"tz3\": 64.1, \"tz4\": 77.0, \"tz5\": 65.1, \"tz6\": 67.8}, \"ts_unix\": 1794038079.047, \"ts_utc\": \"2026-11-07T07:54:39Z\", \"ups_load_pct\": 25, \"ups_realpower_nominal_w\": 1000, \"ups_status\": \"OL\"}", "RawJSON"];
s0 = "cpu  44037906 194121244 69280077 1278129163 14812706 0 422820 0 0 301
cpu0 1537648 5493538 3354322 67896126 1010297 0 20529 0 0 9
cpu1 1390159 6964697 3108963 67463160 914203 0 57489 0 0 0
cpu2 1320085 5736452 3236843 68557928 1097338 0 4427 0 0 0
cpu3 1296724 6566249 3097813 68206697 861007 0 4112 0 0 51
cpu4 1219492 6793540 3130796 68139981 742389 0 4062 0 0 9
cpu5 4940801 7366785 3367025 63700120 722591 0 8813 0 0 16
cpu6 3263269 12609947 3251386 60437580 583937 0 6186 0 0 12
cpu7 3368380 10095867 3019464 63037598 609069 0 7155 0 0 53
cpu8 3378118 11690943 3372778 61134067 554362 0 7248 0 0 20
cpu9 3067345 12778851 3074307 60804283 446864 0 6299 0 0 0
cpu10 1126283 14163838 5312842 58568719 875161 0 5133 0 0 25
cpu11 1131034 14106229 5150308 58932609 774594 0 4754 0 0 38
cpu12 1174622 11503739 3595237 62831898 959952 0 4085 0 0 30
cpu13 1344320 11234047 3513358 62849717 664599 0 224588 0 0 0
cpu14 1301240 11934298 3532375 62676150 641970 0 20457 0 0 0
cpu15 2939679 9364164 3331912 63659391 712941 0 7530 0 0 10
cpu16 2806946 8849043 3331217 64413990 732940 0 7523 0 0 0
cpu17 2797405 8873375 3198092 64592229 696917 0 7474 0 0 17
cpu18 2381482 9007903 3191583 64938700 655290 0 7433 0 0 3
cpu19 2252864 8987729 3109448 65288211 556278 0 7515 0 0 0
intr 13471031529 0 361139983 24010163 0 0 65783641 1304166 0 0 2 0 2258 3398466434 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 4 0 0 2570968 420521 41 0 0 6101 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 358 0 0 0 0 0 0 0 0 0 0 0 222385433 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 1 0 1 1 0 1 0 0 1 0 0 1 0 0 0 0 85829227 0 0 0 0 0 0 0 92475032 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 42603 63825437 65947904 58164487 34884287 33112758 30668044 26385486 71836924 73317652 32739721 32519233 28825211 27609560 25587587 20857640 5206 0 136047 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 182816
ctxt 14664533486
btime 1793232395
processes 376822456
procs_running 6
procs_blocked 1
softirq 3990895635 710962 326855219 36039 356119529 26822746 0 5255971 591684336 5588453 2677822380
"; s1 = "cpu  44038344 194123639 69280605 1278135251 14813104 0 422827 0 0 301
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
";
cpu[s_] := Association@Cases[StringSplit[s, "\n"], l_ /; StringMatchQ[l, "cpu" ~~ DigitCharacter .. ~~ " " ~~ ___] :> (StringReplace[First[StringSplit[l]], "cpu" -> "c"] -> ToExpression /@ Take[Rest[StringSplit[l]], 8])];
busy = Association@KeyValueMap[Function[{c, b}, c -> With[{a = cpu[s0][c]}, With[{dt = Total[b] - Total[a], di = b[[4]] + b[[5]] - a[[4]] - a[[5]]}, If[dt > 0, 100 (dt - di)/dt, Null]]]], cpu[s1]];
la = StringSplit["12.89 12.54 10.19 8/4644 3712371
"];
psi[t_] := Association@Flatten@Map[Function[l, With[{w = StringSplit[l]}, (First[w] <> "_" <> First[#] -> ToExpression[Last[#]]) & /@ (StringSplit[#, "="] & /@ Rest[w])]], StringSplit[t, "\n"]];
mi = Association@Cases[StringSplit["MemTotal:       127598532 kB
MemFree:        34503252 kB
MemAvailable:   81492504 kB
Buffers:         9083900 kB
Cached:         38707268 kB
SwapCached:            0 kB
Active:         21385908 kB
Inactive:       45173648 kB
Active(anon):   20485520 kB
Inactive(anon): 14048060 kB
Active(file):     900388 kB
Inactive(file): 31125588 kB
Unevictable:       31020 kB
Mlocked:           22912 kB
SwapTotal:             0 kB
SwapFree:              0 kB
Zswap:                 0 kB
Zswapped:              0 kB
Dirty:            927524 kB
Writeback:             0 kB
AnonPages:      18799968 kB
Mapped:          1223488 kB
Shmem:          15762640 kB
KReclaimable:   21156900 kB
Slab:           24576196 kB
SReclaimable:   21156900 kB
SUnreclaim:      3419296 kB
KernelStack:       74736 kB
ShadowCallStack:   18712 kB
PageTables:       241784 kB
SecPageTables:     42396 kB
NFS_Unstable:          0 kB
Bounce:                0 kB
WritebackTmp:          0 kB
CommitLimit:    63799264 kB
Committed_AS:   182146404 kB
VmallocTotal:   135288315904 kB
VmallocUsed:      184632 kB
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
g = StringTrim /@ StringSplit[First[StringSplit["0, 0, 22.00, 58, 598, P0
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
 Flatten[Table[With[{ps = psi[t[[2]]]}, KeyValueMap[chk[t[[1]] <> "." <> #1, #2, j[t[[1]]][#1], 0] &, ps]], {t, {{"psi_cpu", "some avg10=8.81 avg60=11.96 avg300=7.77 total=69346264326
full avg10=0.00 avg60=0.00 avg300=0.00 total=0
"}, {"psi_mem", "some avg10=0.00 avg60=0.02 avg300=0.06 total=1119909932
full avg10=0.00 avg60=0.02 avg300=0.05 total=1062097253
"}, {"psi_io", "some avg10=1.12 avg60=4.31 avg300=5.86 total=13653304856
full avg10=1.10 avg60=3.81 avg300=5.21 total=12782201231
"}}}], 1],
 MapIndexed[chk["thermal_c.tz" <> ToString[First[#2] - 1], ToExpression[StringTrim[#1]]/1000, j["thermal_c"]["tz" <> ToString[First[#2] - 1]], 0] &, {"77000
", "67100
", "70600
", "64100
", "77000
", "65100
", "67800
"}],
 chk["mem." <> #, mi[#], j["mem"][#], 0] & /@ {"MemTotal_kb", "MemAvailable_kb", "SwapTotal_kb", "SwapFree_kb"},
 MapThread[chk[#1, If[StringMatchQ[#2, NumberString], ToExpression[#2], #2], j[#1], 0] &, {gk, g}],
 {chk["ups_load_pct", uv["ups.load"], j["ups_load_pct"], 0], chk["ups_realpower_nominal_w", uv["ups.realpower.nominal"], j["ups_realpower_nominal_w"], 0], chk["ups_status", u["ups.status"], j["ups_status"], 0], chk["input_voltage", uv["input.voltage"], j["input_voltage"], 0], chk["battery_runtime_s", uv["battery.runtime"], j["battery_runtime_s"], 0]},
 {chk["ts_utc_vs_ts_unix", DateString[FromUnixTime[Floor[j["ts_unix"]], TimeZone -> 0], {"Year", "-", "Month", "-", "Day", "T", "Hour", ":", "Minute", ":", "Second", "Z"}], j["ts_utc"], 0]}];
<|"seq" -> j["seq"], "checked" -> Length[res], "failed" -> Select[res, ! Last[#] &], "rows" -> ({#[[1]], If[NumericQ[#[[2]]] && ! IntegerQ[#[[2]]], N[#[[2]], 8], #[[2]]], #[[3]], #[[4]]} & /@ res)|>]
