Module[{j, s0, s1, cpu, busy, la, psi, mi, g, gk, u, uv, chk, res},
j = ImportString["{\"battery_runtime_s\": 1600, \"core_busy_pct\": {\"c0\": 17.54, \"c1\": 12.86, \"c10\": 11.36, \"c11\": 14.11, \"c12\": 16.06, \"c13\": 22.95, \"c14\": 24.04, \"c15\": 18.55, \"c16\": 100.0, \"c17\": 19.27, \"c18\": 35.14, \"c19\": 100.0, \"c2\": 13.67, \"c3\": 12.58, \"c4\": 69.34, \"c5\": 83.53, \"c6\": 98.39, \"c7\": 9.9, \"c8\": 8.47, \"c9\": 9.33}, \"gpu_mem_util_pct\": 0.0, \"gpu_power_w\": 44.771, \"gpu_pstate\": \"P0\", \"gpu_sm_mhz\": 2099.0, \"gpu_temp_c\": 72.0, \"gpu_util_pct\": 93.0, \"input_voltage\": 121, \"loadavg\": [7.6, 7.61, 7.6], \"mem\": {\"MemAvailable_kb\": 75044120, \"MemTotal_kb\": 127598532, \"SwapFree_kb\": 0, \"SwapTotal_kb\": 0}, \"psi_cpu\": {\"full_avg10\": 0.0, \"full_avg300\": 0.0, \"full_avg60\": 0.0, \"full_total\": 0, \"some_avg10\": 1.13, \"some_avg300\": 0.98, \"some_avg60\": 1.1, \"some_total\": 69290190012}, \"psi_io\": {\"full_avg10\": 0.03, \"full_avg300\": 1.75, \"full_avg60\": 1.05, \"full_total\": 12750908879, \"some_avg10\": 0.03, \"some_avg300\": 1.88, \"some_avg60\": 1.16, \"some_total\": 13617896426}, \"psi_mem\": {\"full_avg10\": 0.0, \"full_avg300\": 0.0, \"full_avg60\": 0.0, \"full_total\": 1060547589, \"some_avg10\": 0.0, \"some_avg300\": 0.0, \"some_avg60\": 0.0, \"some_total\": 1118312292}, \"runnable\": \"6/3851\", \"sample_cost_us\": 96825, \"seq\": 0, \"thermal_c\": {\"tz0\": 82.5, \"tz1\": 73.3, \"tz2\": 77.5, \"tz3\": 72.9, \"tz4\": 82.5, \"tz5\": 79.8, \"tz6\": 75.7}, \"ts_unix\": 1794037454.548, \"ts_utc\": \"2026-11-07T07:44:14Z\", \"ups_load_pct\": 26, \"ups_realpower_nominal_w\": 1000, \"ups_status\": \"OL\"}", "RawJSON"];
s0 = "cpu  43938687 193796262 69171878 1277508778 14741810 0 421113 0 0 301
cpu0 1532253 5479494 3349820 67864734 1004801 0 20510 0 0 9
cpu1 1384976 6933450 3105232 67443826 912622 0 57276 0 0 0
cpu2 1313916 5733833 3232540 68517098 1090706 0 4411 0 0 0
cpu3 1290585 6566029 3094083 68162243 854708 0 4098 0 0 51
cpu4 1216304 6776826 3128442 68104326 739108 0 4054 0 0 9
cpu5 4937185 7352244 3351824 63676389 718028 0 8792 0 0 16
cpu6 3262685 12553928 3250710 60432909 583586 0 6176 0 0 12
cpu7 3361925 10095733 3015636 62992287 603536 0 7114 0 0 53
cpu8 3372383 11679602 3364406 61101040 551177 0 7225 0 0 20
cpu9 3063986 12764442 3062060 60775160 444245 0 6278 0 0 0
cpu10 1120682 14162992 5307403 58525123 870246 0 5118 0 0 25
cpu11 1126031 14103019 5141468 58893390 770046 0 4742 0 0 38
cpu12 1168579 11503240 3589944 62788106 954814 0 4067 0 0 30
cpu13 1335984 11233465 3508572 62808200 660437 0 223619 0 0 0
cpu14 1292647 11933934 3527654 62632391 638642 0 20376 0 0 0
cpu15 2929660 9363981 3326971 63616718 709433 0 7461 0 0 10
cpu16 2802642 8825468 3324046 64390160 730386 0 7446 0 0 0
cpu17 2793085 8854446 3190924 64564398 694111 0 7406 0 0 17
cpu18 2380313 8954688 3190793 64932096 654901 0 7421 0 0 3
cpu19 2252858 8925439 3109342 65288176 556267 0 7515 0 0 0
intr 13447617406 0 360840841 16616311 0 0 65776026 1303002 0 0 2 0 2258 3385517105 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 4 0 0 2568918 420521 41 0 0 6101 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 358 0 0 0 0 0 0 0 0 0 0 0 222193321 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 1 0 1 1 0 1 0 0 1 0 0 1 0 0 0 0 85565399 0 0 0 0 0 0 0 92168822 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 42568 63588772 65700286 57957593 34793541 33021149 30654622 26385144 71650872 73042590 32634676 32359589 28813965 27425572 25489615 20765294 5206 0 136047 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 182683
ctxt 14638429882
btime 1793232395
processes 376466975
procs_running 12
procs_blocked 0
softirq 3984529944 710656 326358094 35884 354915690 26703069 0 5235045 590953383 5581878 2674036245
"; s1 = "cpu  43939499 193798330 69172457 1277515151 14741862 0 421119 0 0 301
cpu0 1532311 5479503 3349838 67865128 1004807 0 20510 0 0 9
cpu1 1385017 6933453 3105250 67444241 912634 0 57277 0 0 0
cpu2 1313962 5733838 3232556 68517514 1090713 0 4411 0 0 0
cpu3 1290632 6566030 3094097 68162672 854710 0 4098 0 0 51
cpu4 1216309 6777160 3128449 68104479 739108 0 4054 0 0 9
cpu5 4937186 7352394 3352089 63676460 718039 0 8792 0 0 16
cpu6 3262685 12554417 3250711 60432917 583586 0 6176 0 0 12
cpu7 3361955 10095739 3015649 62992727 603542 0 7114 0 0 53
cpu8 3372399 11679611 3364423 61101493 551178 0 7225 0 0 20
cpu9 3064007 12764446 3062081 60775607 444245 0 6278 0 0 0
cpu10 1120720 14162994 5307419 58525559 870247 0 5118 0 0 25
cpu11 1126074 14103022 5141492 58893815 770047 0 4742 0 0 38
cpu12 1168631 11503246 3589965 62788517 954816 0 4067 0 0 30
cpu13 1336062 11233475 3508592 62808576 660437 0 223623 0 0 0
cpu14 1292733 11933944 3527677 62632767 638642 0 20376 0 0 0
cpu15 2929736 9363982 3326986 63617122 709433 0 7461 0 0 10
cpu16 2802642 8825968 3324046 64390160 730386 0 7446 0 0 0
cpu17 2793131 8854464 3190955 64564793 694114 0 7406 0 0 17
cpu18 2380441 8954696 3190832 64932418 654902 0 7421 0 0 3
cpu19 2252858 8925940 3109342 65288176 556267 0 7515 0 0 0
intr 13447745110 0 360842547 16652895 0 0 65776194 1303013 0 0 2 0 2258 3385600052 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 4 0 0 2568923 420521 41 0 0 6101 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 358 0 0 0 0 0 0 0 0 0 0 0 222195842 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 1 0 1 1 0 1 0 0 1 0 0 1 0 0 0 0 85566845 0 0 0 0 0 0 0 92170350 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 42568 63588784 65700309 57957598 34793541 33021269 30654626 26385144 71651122 73042688 32634676 32359780 28813965 27425638 25489625 20765302 5206 0 136047 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 182683
ctxt 14638545944
btime 1793232395
processes 376468326
procs_running 5
procs_blocked 0
softirq 3984567983 710658 326361650 35884 354920934 26703073 0 5235124 590958747 5581928 2674059985
";
cpu[s_] := Association@Cases[StringSplit[s, "\n"], l_ /; StringMatchQ[l, "cpu" ~~ DigitCharacter .. ~~ " " ~~ ___] :> (StringReplace[First[StringSplit[l]], "cpu" -> "c"] -> ToExpression /@ Take[Rest[StringSplit[l]], 8])];
busy = Association@KeyValueMap[Function[{c, b}, c -> With[{a = cpu[s0][c]}, With[{dt = Total[b] - Total[a], di = b[[4]] + b[[5]] - a[[4]] - a[[5]]}, If[dt > 0, 100 (dt - di)/dt, Null]]]], cpu[s1]];
la = StringSplit["7.60 7.61 7.60 6/3851 3357045
"];
psi[t_] := Association@Flatten@Map[Function[l, With[{w = StringSplit[l]}, (First[w] <> "_" <> First[#] -> ToExpression[Last[#]]) & /@ (StringSplit[#, "="] & /@ Rest[w])]], StringSplit[t, "\n"]];
mi = Association@Cases[StringSplit["MemTotal:       127598532 kB
MemFree:        37850948 kB
MemAvailable:   75044120 kB
Buffers:         7494072 kB
Cached:         30801164 kB
SwapCached:            0 kB
Active:         20845792 kB
Inactive:       34419064 kB
Active(anon):   18162248 kB
Inactive(anon): 14571796 kB
Active(file):    2683544 kB
Inactive(file): 19847268 kB
Unevictable:       31020 kB
Mlocked:           22912 kB
SwapTotal:             0 kB
SwapFree:              0 kB
Zswap:                 0 kB
Zswapped:              0 kB
Dirty:             26388 kB
Writeback:             0 kB
AnonPages:      17001424 kB
Mapped:          8739040 kB
Shmem:          15762568 kB
KReclaimable:   20855984 kB
Slab:           24285388 kB
SReclaimable:   20855984 kB
SUnreclaim:      3429404 kB
KernelStack:       61904 kB
ShadowCallStack:   15580 kB
PageTables:       236484 kB
SecPageTables:     56976 kB
NFS_Unstable:          0 kB
Bounce:                0 kB
WritebackTmp:          0 kB
CommitLimit:    63799264 kB
Committed_AS:   178618084 kB
VmallocTotal:   135288315904 kB
VmallocUsed:      261424 kB
VmallocChunk:          0 kB
Percpu:            52800 kB
HardwareCorrupted:     0 kB
AnonHugePages:   1949696 kB
ShmemHugePages:        0 kB
ShmemPmdMapped:        0 kB
FileHugePages:     75776 kB
FilePmdMapped:         0 kB
CmaTotal:              0 kB
CmaFree:           81140 kB
Balloon:               0 kB
HugePages_Total:       0
HugePages_Free:        0
HugePages_Rsvd:        0
HugePages_Surp:        0
Hugepagesize:       2048 kB
Hugetlb:               0 kB
", "\n"], l_ :> (StringTrim[First[StringSplit[l, ":"]]] <> "_kb" -> ToExpression[First[StringSplit[Last[StringSplit[l, ":"]]]]])];
g = StringTrim /@ StringSplit[First[StringSplit["93, 0, 44.77, 72, 2099, P0
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
driver.state: updateinfo
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
 Flatten[Table[With[{ps = psi[t[[2]]]}, KeyValueMap[chk[t[[1]] <> "." <> #1, #2, j[t[[1]]][#1], 0] &, ps]], {t, {{"psi_cpu", "some avg10=1.13 avg60=1.10 avg300=0.98 total=69290190012
full avg10=0.00 avg60=0.00 avg300=0.00 total=0
"}, {"psi_mem", "some avg10=0.00 avg60=0.00 avg300=0.00 total=1118312292
full avg10=0.00 avg60=0.00 avg300=0.00 total=1060547589
"}, {"psi_io", "some avg10=0.03 avg60=1.16 avg300=1.88 total=13617896426
full avg10=0.03 avg60=1.05 avg300=1.75 total=12750908879
"}}}], 1],
 MapIndexed[chk["thermal_c.tz" <> ToString[First[#2] - 1], ToExpression[StringTrim[#1]]/1000, j["thermal_c"]["tz" <> ToString[First[#2] - 1]], 0] &, {"82500
", "73300
", "77500
", "72900
", "82500
", "79800
", "75700
"}],
 chk["mem." <> #, mi[#], j["mem"][#], 0] & /@ {"MemTotal_kb", "MemAvailable_kb", "SwapTotal_kb", "SwapFree_kb"},
 MapThread[chk[#1, If[StringMatchQ[#2, NumberString], ToExpression[#2], #2], j[#1], 0] &, {gk, g}],
 {chk["ups_load_pct", uv["ups.load"], j["ups_load_pct"], 0], chk["ups_realpower_nominal_w", uv["ups.realpower.nominal"], j["ups_realpower_nominal_w"], 0], chk["ups_status", u["ups.status"], j["ups_status"], 0], chk["input_voltage", uv["input.voltage"], j["input_voltage"], 0], chk["battery_runtime_s", uv["battery.runtime"], j["battery_runtime_s"], 0]},
 {chk["ts_utc_vs_ts_unix", DateString[FromUnixTime[Floor[j["ts_unix"]], TimeZone -> 0], {"Year", "-", "Month", "-", "Day", "T", "Hour", ":", "Minute", ":", "Second", "Z"}], j["ts_utc"], 0]}];
<|"seq" -> j["seq"], "checked" -> Length[res], "failed" -> Select[res, ! Last[#] &], "rows" -> ({#[[1]], If[NumericQ[#[[2]]] && ! IntegerQ[#[[2]]], N[#[[2]], 8], #[[2]]], #[[3]], #[[4]]} & /@ res)|>]