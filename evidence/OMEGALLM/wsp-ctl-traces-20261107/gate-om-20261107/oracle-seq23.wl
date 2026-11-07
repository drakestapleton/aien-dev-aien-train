Module[{j, s0, s1, cpu, busy, la, psi, mi, g, gk, u, uv, chk, res},
j = ImportString["{\"battery_runtime_s\": 2275, \"core_busy_pct\": {\"c0\": 100.0, \"c1\": 21.94, \"c10\": 10.31, \"c11\": 38.87, \"c12\": 11.87, \"c13\": 13.32, \"c14\": 15.68, \"c15\": 9.66, \"c16\": 14.03, \"c17\": 17.74, \"c18\": 100.0, \"c19\": 100.0, \"c2\": 10.37, \"c3\": 10.48, \"c4\": 31.59, \"c5\": 99.6, \"c6\": 83.83, \"c7\": 6.68, \"c8\": 7.69, \"c9\": 6.85}, \"gpu_mem_util_pct\": 0.0, \"gpu_power_w\": 17.93, \"gpu_pstate\": \"P0\", \"gpu_sm_mhz\": 1007.0, \"gpu_temp_c\": 59.0, \"gpu_util_pct\": 38.0, \"input_voltage\": 122, \"loadavg\": [11.01, 8.97, 8.1], \"mem\": {\"MemAvailable_kb\": 73108508, \"MemTotal_kb\": 127598532, \"SwapFree_kb\": 0, \"SwapTotal_kb\": 0}, \"psi_cpu\": {\"full_avg10\": 0.0, \"full_avg300\": 0.0, \"full_avg60\": 0.0, \"full_total\": 0, \"some_avg10\": 15.85, \"some_avg300\": 4.23, \"some_avg60\": 11.02, \"some_total\": 69303242816}, \"psi_io\": {\"full_avg10\": 0.26, \"full_avg300\": 1.72, \"full_avg60\": 1.36, \"full_total\": 12753291591, \"some_avg10\": 0.39, \"some_avg300\": 1.98, \"some_avg60\": 1.81, \"some_total\": 13621011703}, \"psi_mem\": {\"full_avg10\": 0.0, \"full_avg300\": 0.0, \"full_avg60\": 0.0, \"full_total\": 1060561871, \"some_avg10\": 0.0, \"some_avg300\": 0.0, \"some_avg60\": 0.0, \"some_total\": 1118326917}, \"runnable\": \"9/4559\", \"sample_cost_us\": 424823, \"seq\": 23, \"thermal_c\": {\"tz0\": 74.9, \"tz1\": 64.7, \"tz2\": 69.4, \"tz3\": 63.0, \"tz4\": 74.9, \"tz5\": 62.3, \"tz6\": 68.8}, \"ts_unix\": 1794037569.548, \"ts_utc\": \"2026-11-07T07:46:09Z\", \"ups_load_pct\": 22, \"ups_realpower_nominal_w\": 1000, \"ups_status\": \"OL\"}", "RawJSON"];
s0 = "cpu  43958919 193847232 69189504 1277638760 14747793 0 421562 0 0 301
cpu0 1533568 5481356 3350602 67871330 1005441 0 20512 0 0 9
cpu1 1386280 6933800 3105832 67452095 913231 0 57336 0 0 0
cpu2 1315253 5733887 3233153 68525556 1091455 0 4413 0 0 0
cpu3 1291860 6566087 3094636 68171040 855234 0 4099 0 0 51
cpu4 1216771 6781991 3128722 68109624 739261 0 4055 0 0 9
cpu5 4937214 7358735 3356169 63676921 718097 0 8792 0 0 16
cpu6 3262768 12564232 3250804 60433892 583595 0 6176 0 0 12
cpu7 3363105 10095768 3016159 63001341 604008 0 7115 0 0 53
cpu8 3373501 11679646 3364996 61110227 551533 0 7226 0 0 20
cpu9 3065088 12764474 3062650 60784573 444499 0 6280 0 0 0
cpu10 1121734 14163518 5308398 58533378 870543 0 5120 0 0 25
cpu11 1126991 14103850 5143036 58900837 770354 0 4743 0 0 38
cpu12 1169832 11503360 3590894 62796657 955122 0 4068 0 0 30
cpu13 1337724 11233580 3509454 62816010 660603 0 223967 0 0 0
cpu14 1294370 11934045 3528611 62640732 638767 0 20382 0 0 0
cpu15 2931405 9364031 3327901 63624965 709588 0 7462 0 0 10
cpu16 2803418 8831435 3324790 64393651 730586 0 7451 0 0 0
cpu17 2794199 8855631 3192115 64571666 694532 0 7417 0 0 17
cpu18 2380971 8960861 3191231 64936080 655068 0 7425 0 0 3
cpu19 2252858 8936937 3109344 65288176 556267 0 7515 0 0 0
intr 13451885662 0 360900179 18225545 0 0 65777988 1303233 0 0 2 0 2258 3387761421 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 4 0 0 2569181 420521 41 0 0 6101 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 358 0 0 0 0 0 0 0 0 0 0 0 222231963 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 1 0 1 1 0 1 0 0 1 0 0 1 0 0 0 0 85649060 0 0 0 0 0 0 0 92289358 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 42574 63597554 65708869 57963587 34799883 33032546 30656843 26385144 71668115 73061624 32637793 32366610 28814292 27434285 25495633 20770541 5206 0 136047 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 182710
ctxt 14642792724
btime 1793232395
processes 376528161
procs_running 10
procs_blocked 0
softirq 3985812411 710713 326443272 35884 355379356 26705660 0 5239210 591084121 5583342 2674630853
"; s1 = "cpu  43959360 193849694 69190067 1277644832 14747809 0 421573 0 0 301
cpu0 1533568 5481813 3350644 67871330 1005441 0 20512 0 0 9
cpu1 1386301 6933800 3105876 67452343 913232 0 57341 0 0 0
cpu2 1315288 5733887 3233169 68525997 1091455 0 4413 0 0 0
cpu3 1291898 6566087 3094650 68171482 855236 0 4099 0 0 51
cpu4 1216780 6782134 3128727 68109963 739262 0 4055 0 0 9
cpu5 4937214 7359118 3356285 63676921 718099 0 8792 0 0 16
cpu6 3262769 12564649 3250806 60433973 583595 0 6176 0 0 12
cpu7 3363131 10095768 3016166 63001798 604012 0 7115 0 0 53
cpu8 3373521 11679646 3365014 61110682 551534 0 7226 0 0 20
cpu9 3065106 12764474 3062666 60785034 444500 0 6280 0 0 0
cpu10 1121764 14163518 5308418 58533813 870543 0 5120 0 0 25
cpu11 1127017 14103907 5143145 58901138 770355 0 4743 0 0 38
cpu12 1169867 11503360 3590918 62797095 955122 0 4068 0 0 30
cpu13 1337763 11233580 3509472 62816407 660603 0 223971 0 0 0
cpu14 1294412 11934045 3528643 62641129 638768 0 20382 0 0 0
cpu15 2931446 9364031 3327908 63625413 709589 0 7462 0 0 10
cpu16 2803456 8831439 3324818 64394079 730587 0 7451 0 0 0
cpu17 2794221 8855633 3192157 64571972 694532 0 7417 0 0 17
cpu18 2380971 8961361 3191231 64936080 655068 0 7425 0 0 3
cpu19 2252858 8937437 3109344 65288176 556267 0 7515 0 0 0
intr 13452011482 0 360900794 18259077 0 0 65778082 1303241 0 0 2 0 2258 3387847723 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 4 0 0 2569223 420521 41 0 0 6101 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 358 0 0 0 0 0 0 0 0 0 0 0 222233591 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 1 0 1 1 0 1 0 0 1 0 0 1 0 0 0 0 85650410 0 0 0 0 0 0 0 92290295 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 42574 63597568 65708873 57963597 34799893 33032547 30656843 26385144 71668538 73061726 32637794 32366722 28814292 27434489 25495913 20770692 5206 0 136047 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 182710
ctxt 14642894579
btime 1793232395
processes 376529589
procs_running 11
procs_blocked 0
softirq 3985833498 710715 326446230 35884 355383790 26705661 0 5239397 591087157 5583392 2674641272
";
cpu[s_] := Association@Cases[StringSplit[s, "\n"], l_ /; StringMatchQ[l, "cpu" ~~ DigitCharacter .. ~~ " " ~~ ___] :> (StringReplace[First[StringSplit[l]], "cpu" -> "c"] -> ToExpression /@ Take[Rest[StringSplit[l]], 8])];
busy = Association@KeyValueMap[Function[{c, b}, c -> With[{a = cpu[s0][c]}, With[{dt = Total[b] - Total[a], di = b[[4]] + b[[5]] - a[[4]] - a[[5]]}, If[dt > 0, 100 (dt - di)/dt, Null]]]], cpu[s1]];
la = StringSplit["11.01 8.97 8.10 9/4559 3418309
"];
psi[t_] := Association@Flatten@Map[Function[l, With[{w = StringSplit[l]}, (First[w] <> "_" <> First[#] -> ToExpression[Last[#]]) & /@ (StringSplit[#, "="] & /@ Rest[w])]], StringSplit[t, "\n"]];
mi = Association@Cases[StringSplit["MemTotal:       127598532 kB
MemFree:        30967688 kB
MemAvailable:   73108508 kB
Buffers:         7644392 kB
Cached:         35479260 kB
SwapCached:            0 kB
Active:         23567932 kB
Inactive:       38805356 kB
Active(anon):   20466140 kB
Inactive(anon): 14547572 kB
Active(file):    3101792 kB
Inactive(file): 24257784 kB
Unevictable:       31020 kB
Mlocked:           22912 kB
SwapTotal:             0 kB
SwapFree:              0 kB
Zswap:                 0 kB
Zswapped:              0 kB
Dirty:            454932 kB
Writeback:             0 kB
AnonPages:      19281260 kB
Mapped:          8912608 kB
Shmem:          15762320 kB
KReclaimable:   20974868 kB
Slab:           24411892 kB
SReclaimable:   20974868 kB
SUnreclaim:      3437024 kB
KernelStack:       73424 kB
ShadowCallStack:   18404 kB
PageTables:       254764 kB
SecPageTables:     56976 kB
NFS_Unstable:          0 kB
Bounce:                0 kB
WritebackTmp:          0 kB
CommitLimit:    63799264 kB
Committed_AS:   183726504 kB
VmallocTotal:   135288315904 kB
VmallocUsed:      275740 kB
VmallocChunk:          0 kB
Percpu:            52800 kB
HardwareCorrupted:     0 kB
AnonHugePages:   1949696 kB
ShmemHugePages:        0 kB
ShmemPmdMapped:        0 kB
FileHugePages:     98304 kB
FilePmdMapped:         0 kB
CmaTotal:              0 kB
CmaFree:           77404 kB
Balloon:               0 kB
HugePages_Total:       0
HugePages_Free:        0
HugePages_Rsvd:        0
HugePages_Surp:        0
Hugepagesize:       2048 kB
Hugetlb:               0 kB
", "\n"], l_ :> (StringTrim[First[StringSplit[l, ":"]]] <> "_kb" -> ToExpression[First[StringSplit[Last[StringSplit[l, ":"]]]]])];
g = StringTrim /@ StringSplit[First[StringSplit["38, 0, 17.93, 59, 1007, P0
", "\n"]], ","];
gk = {"gpu_util_pct", "gpu_mem_util_pct", "gpu_power_w", "gpu_temp_c", "gpu_sm_mhz", "gpu_pstate"};
u = Association@Cases[StringSplit["battery.charge: 100
battery.charge.low: 10
battery.charge.warning: 20
battery.mfr.date: CPS
battery.runtime: 2275
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
input.voltage: 122.0
input.voltage.nominal: 120
output.voltage: 122.0
ups.beeper.status: enabled
ups.delay.shutdown: 20
ups.delay.start: 30
ups.load: 22
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
 Flatten[Table[With[{ps = psi[t[[2]]]}, KeyValueMap[chk[t[[1]] <> "." <> #1, #2, j[t[[1]]][#1], 0] &, ps]], {t, {{"psi_cpu", "some avg10=15.85 avg60=11.02 avg300=4.23 total=69303242816
full avg10=0.00 avg60=0.00 avg300=0.00 total=0
"}, {"psi_mem", "some avg10=0.00 avg60=0.00 avg300=0.00 total=1118326917
full avg10=0.00 avg60=0.00 avg300=0.00 total=1060561871
"}, {"psi_io", "some avg10=0.39 avg60=1.81 avg300=1.98 total=13621011703
full avg10=0.26 avg60=1.36 avg300=1.72 total=12753291591
"}}}], 1],
 MapIndexed[chk["thermal_c.tz" <> ToString[First[#2] - 1], ToExpression[StringTrim[#1]]/1000, j["thermal_c"]["tz" <> ToString[First[#2] - 1]], 0] &, {"74900
", "64700
", "69400
", "63000
", "74900
", "62300
", "68800
"}],
 chk["mem." <> #, mi[#], j["mem"][#], 0] & /@ {"MemTotal_kb", "MemAvailable_kb", "SwapTotal_kb", "SwapFree_kb"},
 MapThread[chk[#1, If[StringMatchQ[#2, NumberString], ToExpression[#2], #2], j[#1], 0] &, {gk, g}],
 {chk["ups_load_pct", uv["ups.load"], j["ups_load_pct"], 0], chk["ups_realpower_nominal_w", uv["ups.realpower.nominal"], j["ups_realpower_nominal_w"], 0], chk["ups_status", u["ups.status"], j["ups_status"], 0], chk["input_voltage", uv["input.voltage"], j["input_voltage"], 0], chk["battery_runtime_s", uv["battery.runtime"], j["battery_runtime_s"], 0]},
 {chk["ts_utc_vs_ts_unix", DateString[FromUnixTime[Floor[j["ts_unix"]], TimeZone -> 0], {"Year", "-", "Month", "-", "Day", "T", "Hour", ":", "Minute", ":", "Second", "Z"}], j["ts_utc"], 0]}];
<|"seq" -> j["seq"], "checked" -> Length[res], "failed" -> Select[res, ! Last[#] &], "rows" -> ({#[[1]], If[NumericQ[#[[2]]] && ! IntegerQ[#[[2]]], N[#[[2]], 8], #[[2]]], #[[3]], #[[4]]} & /@ res)|>]