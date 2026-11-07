Module[{j, s0, s1, cpu, busy, la, psi, mi, g, gk, u, uv, chk, res},
j = ImportString["{\"battery_runtime_s\": 1625, \"core_busy_pct\": {\"c0\": 8.59, \"c1\": 100.0, \"c10\": 10.59, \"c11\": 27.47, \"c12\": 10.32, \"c13\": 13.2, \"c14\": 12.17, \"c15\": 10.91, \"c16\": 82.53, \"c17\": 9.88, \"c18\": 27.77, \"c19\": 100.0, \"c2\": 7.72, \"c3\": 8.1, \"c4\": 30.38, \"c5\": 8.27, \"c6\": 88.02, \"c7\": 6.29, \"c8\": 13.74, \"c9\": 100.0}, \"gpu_mem_util_pct\": 0.0, \"gpu_power_w\": 40.48, \"gpu_pstate\": \"P0\", \"gpu_sm_mhz\": 2496.0, \"gpu_temp_c\": 62.0, \"gpu_util_pct\": 49.0, \"input_voltage\": 121, \"loadavg\": [13.58, 12.67, 10.22], \"mem\": {\"MemAvailable_kb\": 81185388, \"MemTotal_kb\": 127598532, \"SwapFree_kb\": 0, \"SwapTotal_kb\": 0}, \"psi_cpu\": {\"full_avg10\": 0.0, \"full_avg300\": 0.0, \"full_avg60\": 0.0, \"full_total\": 0, \"some_avg10\": 13.14, \"some_avg300\": 7.88, \"some_avg60\": 12.78, \"some_total\": 69346231946}, \"psi_io\": {\"full_avg10\": 0.44, \"full_avg300\": 5.25, \"full_avg60\": 3.9, \"full_total\": 12782056913, \"some_avg10\": 0.47, \"some_avg300\": 5.9, \"some_avg60\": 4.44, \"some_total\": 13653157595}, \"psi_mem\": {\"full_avg10\": 0.0, \"full_avg300\": 0.06, \"full_avg60\": 0.02, \"full_total\": 1062094719, \"some_avg10\": 0.0, \"some_avg300\": 0.06, \"some_avg60\": 0.02, \"some_total\": 1119907365}, \"runnable\": \"7/4681\", \"sample_cost_us\": 87957, \"seq\": 3, \"thermal_c\": {\"tz0\": 76.4, \"tz1\": 67.9, \"tz2\": 71.7, \"tz3\": 64.5, \"tz4\": 76.4, \"tz5\": 68.8, \"tz6\": 69.2}, \"ts_unix\": 1794038074.047, \"ts_utc\": \"2026-11-07T07:54:34Z\", \"ups_load_pct\": 25, \"ups_realpower_nominal_w\": 1000, \"ups_status\": \"OL\"}", "RawJSON"];
s0 = "cpu  44037373 194118968 69279524 1278122655 14812679 0 422814 0 0 301
cpu0 1537622 5493538 3354306 67895680 1010296 0 20529 0 0 9
cpu1 1390159 6964234 3108928 67463160 914203 0 57488 0 0 0
cpu2 1320059 5736450 3236833 68557476 1097336 0 4427 0 0 0
cpu3 1296693 6566249 3097804 68206245 861005 0 4112 0 0 51
cpu4 1219463 6793425 3130789 68139636 742388 0 4062 0 0 9
cpu5 4940769 7366784 3367017 63699665 722591 0 8813 0 0 16
cpu6 3263266 12609512 3251383 60437520 583937 0 6186 0 0 12
cpu7 3368359 10095867 3019454 63037136 609069 0 7155 0 0 53
cpu8 3378056 11690943 3372772 61133641 554361 0 7248 0 0 20
cpu9 3067345 12778633 3074025 60804283 446864 0 6299 0 0 0
cpu10 1126252 14163838 5312821 58568280 875161 0 5133 0 0 25
cpu11 1130996 14106194 5150245 58932251 774593 0 4754 0 0 38
cpu12 1174587 11503739 3595222 62831457 959950 0 4084 0 0 30
cpu13 1344269 11234046 3513349 62849299 664596 0 224585 0 0 0
cpu14 1301196 11934298 3532359 62675720 641967 0 20457 0 0 0
cpu15 2939638 9364164 3331899 63658952 712939 0 7530 0 0 10
cpu16 2806936 8848644 3331215 64413906 732937 0 7523 0 0 0
cpu17 2797375 8873372 3198076 64591786 696913 0 7474 0 0 17
cpu18 2381460 9007800 3191570 64938343 655288 0 7433 0 0 3
cpu19 2252864 8987229 3109448 65288211 556278 0 7515 0 0 0
intr 13470919031 0 361139574 23973605 0 0 65783441 1304160 0 0 2 0 2258 3398398618 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 4 0 0 2570941 420521 41 0 0 6101 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 358 0 0 0 0 0 0 0 0 0 0 0 222382616 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 1 0 1 1 0 1 0 0 1 0 0 1 0 0 0 0 85827577 0 0 0 0 0 0 0 92473261 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 42603 63825399 65947722 58164264 34884117 33112523 30667979 26385486 71836826 73317537 32739691 32519224 28825211 27609533 25587536 20857640 5206 0 136047 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 182816
ctxt 14664432210
btime 1793232395
processes 376821686
procs_running 10
procs_blocked 0
softirq 3990859333 710960 326852019 36038 356111846 26822618 0 5255667 591680162 5588403 2677801620
"; s1 = "cpu  44037906 194121244 69280077 1278129163 14812706 0 422820 0 0 301
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
";
cpu[s_] := Association@Cases[StringSplit[s, "\n"], l_ /; StringMatchQ[l, "cpu" ~~ DigitCharacter .. ~~ " " ~~ ___] :> (StringReplace[First[StringSplit[l]], "cpu" -> "c"] -> ToExpression /@ Take[Rest[StringSplit[l]], 8])];
busy = Association@KeyValueMap[Function[{c, b}, c -> With[{a = cpu[s0][c]}, With[{dt = Total[b] - Total[a], di = b[[4]] + b[[5]] - a[[4]] - a[[5]]}, If[dt > 0, 100 (dt - di)/dt, Null]]]], cpu[s1]];
la = StringSplit["13.58 12.67 10.22 7/4681 3711289
"];
psi[t_] := Association@Flatten@Map[Function[l, With[{w = StringSplit[l]}, (First[w] <> "_" <> First[#] -> ToExpression[Last[#]]) & /@ (StringSplit[#, "="] & /@ Rest[w])]], StringSplit[t, "\n"]];
mi = Association@Cases[StringSplit["MemTotal:       127598532 kB
MemFree:        33572192 kB
MemAvailable:   81185388 kB
Buffers:         8950292 kB
Cached:         39462988 kB
SwapCached:            0 kB
Active:         21508380 kB
Inactive:       45820276 kB
Active(anon):   20611360 kB
Inactive(anon): 14068332 kB
Active(file):     897020 kB
Inactive(file): 31751944 kB
Unevictable:       31020 kB
Mlocked:           22912 kB
SwapTotal:             0 kB
SwapFree:              0 kB
Zswap:                 0 kB
Zswapped:              0 kB
Dirty:            922796 kB
Writeback:             0 kB
AnonPages:      18920672 kB
Mapped:          1235452 kB
Shmem:          15762340 kB
KReclaimable:   21157412 kB
Slab:           24576808 kB
SReclaimable:   21157412 kB
SUnreclaim:      3419396 kB
KernelStack:       75136 kB
ShadowCallStack:   18872 kB
PageTables:       242792 kB
SecPageTables:     42396 kB
NFS_Unstable:          0 kB
Bounce:                0 kB
WritebackTmp:          0 kB
CommitLimit:    63799264 kB
Committed_AS:   183920708 kB
VmallocTotal:   135288315904 kB
VmallocUsed:      185480 kB
VmallocChunk:          0 kB
Percpu:            52800 kB
HardwareCorrupted:     0 kB
AnonHugePages:   1949696 kB
ShmemHugePages:        0 kB
ShmemPmdMapped:        0 kB
FileHugePages:    145408 kB
FilePmdMapped:         0 kB
CmaTotal:              0 kB
CmaFree:           96644 kB
Balloon:               0 kB
HugePages_Total:       0
HugePages_Free:        0
HugePages_Rsvd:        0
HugePages_Surp:        0
Hugepagesize:       2048 kB
Hugetlb:               0 kB
", "\n"], l_ :> (StringTrim[First[StringSplit[l, ":"]]] <> "_kb" -> ToExpression[First[StringSplit[Last[StringSplit[l, ":"]]]]])];
g = StringTrim /@ StringSplit[First[StringSplit["49, 0, 40.48, 62, 2496, P0
", "\n"]], ","];
gk = {"gpu_util_pct", "gpu_mem_util_pct", "gpu_power_w", "gpu_temp_c", "gpu_sm_mhz", "gpu_pstate"};
u = Association@Cases[StringSplit["battery.charge: 100
battery.charge.low: 10
battery.charge.warning: 20
battery.mfr.date: CPS
battery.runtime: 1625
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
 Flatten[Table[With[{ps = psi[t[[2]]]}, KeyValueMap[chk[t[[1]] <> "." <> #1, #2, j[t[[1]]][#1], 0] &, ps]], {t, {{"psi_cpu", "some avg10=13.14 avg60=12.78 avg300=7.88 total=69346231946
full avg10=0.00 avg60=0.00 avg300=0.00 total=0
"}, {"psi_mem", "some avg10=0.00 avg60=0.02 avg300=0.06 total=1119907365
full avg10=0.00 avg60=0.02 avg300=0.06 total=1062094719
"}, {"psi_io", "some avg10=0.47 avg60=4.44 avg300=5.90 total=13653157595
full avg10=0.44 avg60=3.90 avg300=5.25 total=12782056913
"}}}], 1],
 MapIndexed[chk["thermal_c.tz" <> ToString[First[#2] - 1], ToExpression[StringTrim[#1]]/1000, j["thermal_c"]["tz" <> ToString[First[#2] - 1]], 0] &, {"76400
", "67900
", "71700
", "64500
", "76400
", "68800
", "69200
"}],
 chk["mem." <> #, mi[#], j["mem"][#], 0] & /@ {"MemTotal_kb", "MemAvailable_kb", "SwapTotal_kb", "SwapFree_kb"},
 MapThread[chk[#1, If[StringMatchQ[#2, NumberString], ToExpression[#2], #2], j[#1], 0] &, {gk, g}],
 {chk["ups_load_pct", uv["ups.load"], j["ups_load_pct"], 0], chk["ups_realpower_nominal_w", uv["ups.realpower.nominal"], j["ups_realpower_nominal_w"], 0], chk["ups_status", u["ups.status"], j["ups_status"], 0], chk["input_voltage", uv["input.voltage"], j["input_voltage"], 0], chk["battery_runtime_s", uv["battery.runtime"], j["battery_runtime_s"], 0]},
 {chk["ts_utc_vs_ts_unix", DateString[FromUnixTime[Floor[j["ts_unix"]], TimeZone -> 0], {"Year", "-", "Month", "-", "Day", "T", "Hour", ":", "Minute", ":", "Second", "Z"}], j["ts_utc"], 0]}];
<|"seq" -> j["seq"], "checked" -> Length[res], "failed" -> Select[res, ! Last[#] &], "rows" -> ({#[[1]], If[NumericQ[#[[2]]] && ! IntegerQ[#[[2]]], N[#[[2]], 8], #[[2]]], #[[3]], #[[4]]} & /@ res)|>]
