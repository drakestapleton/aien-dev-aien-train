Module[{j, s0, s1, cpu, busy, la, psi, mi, g, gk, u, uv, chk, res},
j = ImportString["{\"battery_runtime_s\": 1950, \"core_busy_pct\": {\"c0\": 36.08, \"c1\": 29.77, \"c10\": 29.18, \"c11\": 30.47, \"c12\": 27.03, \"c13\": 40.29, \"c14\": 32.85, \"c15\": 37.9, \"c16\": 42.02, \"c17\": 37.17, \"c18\": 100.0, \"c19\": 100.0, \"c2\": 27.25, \"c3\": 24.69, \"c4\": 63.86, \"c5\": 99.6, \"c6\": 97.79, \"c7\": 29.64, \"c8\": 19.39, \"c9\": 18.7}, \"gpu_mem_util_pct\": 0.0, \"gpu_power_w\": 31.78, \"gpu_pstate\": \"P0\", \"gpu_sm_mhz\": 1755.0, \"gpu_temp_c\": 72.0, \"gpu_util_pct\": 87.0, \"input_voltage\": 121, \"loadavg\": [10.76, 8.43, 7.87], \"mem\": {\"MemAvailable_kb\": 72799800, \"MemTotal_kb\": 127598532, \"SwapFree_kb\": 0, \"SwapTotal_kb\": 0}, \"psi_cpu\": {\"full_avg10\": 0.0, \"full_avg300\": 0.0, \"full_avg60\": 0.0, \"full_total\": 0, \"some_avg10\": 11.45, \"some_avg300\": 1.91, \"some_avg60\": 4.84, \"some_total\": 69294037954}, \"psi_io\": {\"full_avg10\": 1.9, \"full_avg300\": 1.78, \"full_avg60\": 1.67, \"full_total\": 12752145777, \"some_avg10\": 2.3, \"some_avg300\": 1.96, \"some_avg60\": 1.98, \"some_total\": 13619398538}, \"psi_mem\": {\"full_avg10\": 0.0, \"full_avg300\": 0.0, \"full_avg60\": 0.0, \"full_total\": 1060547899, \"some_avg10\": 0.0, \"some_avg300\": 0.0, \"some_avg60\": 0.0, \"some_total\": 1118312676}, \"runnable\": \"14/4570\", \"sample_cost_us\": 97832, \"seq\": 11, \"thermal_c\": {\"tz0\": 83.6, \"tz1\": 73.7, \"tz2\": 79.4, \"tz3\": 74.5, \"tz4\": 83.6, \"tz5\": 74.1, \"tz6\": 79.6}, \"ts_unix\": 1794037509.548, \"ts_utc\": \"2026-11-07T07:45:09Z\", \"ups_load_pct\": 27, \"ups_realpower_nominal_w\": 1000, \"ups_status\": \"OL\"}", "RawJSON"];
s0 = "cpu  43949499 193820098 69181922 1277568403 14744883 0 421315 0 0 301
cpu0 1532947 5479807 3350232 67868330 1005129 0 20511 0 0 9
cpu1 1385617 6933775 3105595 67447567 912912 0 57300 0 0 0
cpu2 1314602 5733872 3232924 68520936 1091106 0 4412 0 0 0
cpu3 1291227 6566072 3094440 68166251 854969 0 4099 0 0 51
cpu4 1216521 6779936 3128618 68106162 739188 0 4055 0 0 9
cpu5 4937213 7354192 3354728 63676921 718083 0 8792 0 0 16
cpu6 3262715 12559246 3250748 60433009 583589 0 6176 0 0 12
cpu7 3362515 10095762 3015934 62996513 603806 0 7115 0 0 53
cpu8 3372979 11679636 3364798 61105224 551369 0 7226 0 0 20
cpu9 3064557 12764467 3062400 60779542 444375 0 6278 0 0 0
cpu10 1121274 14163047 5307877 58529089 870407 0 5119 0 0 25
cpu11 1126584 14103287 5142247 58896879 770237 0 4742 0 0 38
cpu12 1169252 11503293 3590390 62792082 954987 0 4067 0 0 30
cpu13 1336941 11233511 3508986 62811783 660518 0 223773 0 0 0
cpu14 1293610 11933993 3528100 62636218 638709 0 20381 0 0 0
cpu15 2930652 9363999 3327488 63620494 709502 0 7461 0 0 10
cpu16 2803147 8827645 3324540 64392174 730531 0 7450 0 0 0
cpu17 2793695 8855138 3191575 64567689 694277 0 7412 0 0 17
cpu18 2380583 8958476 3190949 64933353 654912 0 7423 0 0 3
cpu19 2252858 8930937 3109344 65288176 556267 0 7515 0 0 0
intr 13449442734 0 360870451 17167728 0 0 65776768 1303121 0 0 2 0 2258 3386605911 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 4 0 0 2569073 420521 41 0 0 6101 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 358 0 0 0 0 0 0 0 0 0 0 0 222209898 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 1 0 1 1 0 1 0 0 1 0 0 1 0 0 0 0 85597084 0 0 0 0 0 0 0 92211854 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 42571 63595319 65705839 57961379 34798079 33026494 30654825 26385144 71660571 73053868 32636851 32362310 28814033 27430767 25492942 20768019 5206 0 136047 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 182707
ctxt 14640147805
btime 1793232395
processes 376496371
procs_running 12
procs_blocked 0
softirq 3985084973 710684 326398708 35884 355078327 26704809 0 5236732 591018021 5582473 2674319335
"; s1 = "cpu  43950995 193822262 69182795 1277573668 14744897 0 421354 0 0 301
cpu0 1533085 5479809 3350266 67868640 1005129 0 20512 0 0 9
cpu1 1385731 6933776 3105621 67447909 912912 0 57304 0 0 0
cpu2 1314710 5733872 3232949 68521291 1091106 0 4412 0 0 0
cpu3 1291327 6566072 3094461 68166620 854969 0 4099 0 0 51
cpu4 1216554 6780211 3128628 68106342 739188 0 4055 0 0 9
cpu5 4937213 7354488 3354930 63676921 718085 0 8792 0 0 16
cpu6 3262716 12559717 3250763 60433020 583589 0 6176 0 0 12
cpu7 3362620 10095763 3015975 62996861 603807 0 7115 0 0 53
cpu8 3373054 11679637 3364818 61105622 551370 0 7226 0 0 20
cpu9 3064628 12764468 3062420 60779940 444377 0 6278 0 0 0
cpu10 1121354 14163057 5307930 58529433 870410 0 5119 0 0 25
cpu11 1126664 14103298 5142305 58897218 770238 0 4742 0 0 38
cpu12 1169330 11503296 3590442 62792440 954988 0 4067 0 0 30
cpu13 1337047 11233519 3509032 62812068 660519 0 223806 0 0 0
cpu14 1293711 11933998 3528154 62636545 638709 0 20381 0 0 0
cpu15 2930776 9364001 3327550 63620800 709504 0 7461 0 0 10
cpu16 2803236 8827695 3324609 64392460 730532 0 7450 0 0 0
cpu17 2793787 8855164 3191640 64568000 694277 0 7413 0 0 17
cpu18 2380583 8958976 3190949 64933353 654912 0 7423 0 0 3
cpu19 2252858 8931437 3109344 65288176 556267 0 7515 0 0 0
intr 13449746985 0 360874210 17322117 0 0 65776808 1303130 0 0 2 0 2258 3386729360 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 4 0 0 2569081 420521 41 0 0 6101 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 358 0 0 0 0 0 0 0 0 0 0 0 222211217 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 1 0 1 1 0 1 0 0 1 0 0 1 0 0 0 0 85605222 0 0 0 0 0 0 0 92223532 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 42571 63595397 65705876 57961405 34798131 33026523 30654825 26385144 71660695 73054023 32636852 32362977 28814033 27430843 25493047 20768130 5206 0 136047 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 182707
ctxt 14640501392
btime 1793232395
processes 376499351
procs_running 15
procs_blocked 0
softirq 3985181374 710686 326402538 35884 355128088 26704815 0 5236901 591026259 5582566 2674353637
";
cpu[s_] := Association@Cases[StringSplit[s, "\n"], l_ /; StringMatchQ[l, "cpu" ~~ DigitCharacter .. ~~ " " ~~ ___] :> (StringReplace[First[StringSplit[l]], "cpu" -> "c"] -> ToExpression /@ Take[Rest[StringSplit[l]], 8])];
busy = Association@KeyValueMap[Function[{c, b}, c -> With[{a = cpu[s0][c]}, With[{dt = Total[b] - Total[a], di = b[[4]] + b[[5]] - a[[4]] - a[[5]]}, If[dt > 0, 100 (dt - di)/dt, Null]]]], cpu[s1]];
la = StringSplit["10.76 8.43 7.87 14/4570 3388070
"];
psi[t_] := Association@Flatten@Map[Function[l, With[{w = StringSplit[l]}, (First[w] <> "_" <> First[#] -> ToExpression[Last[#]]) & /@ (StringSplit[#, "="] & /@ Rest[w])]], StringSplit[t, "\n"]];
mi = Association@Cases[StringSplit["MemTotal:       127598532 kB
MemFree:        33745588 kB
MemAvailable:   72799800 kB
Buffers:         7593848 kB
Cached:         32526456 kB
SwapCached:            0 kB
Active:         23138912 kB
Inactive:       35826212 kB
Active(anon):   20053168 kB
Inactive(anon): 14555848 kB
Active(file):    3085744 kB
Inactive(file): 21270364 kB
Unevictable:       31020 kB
Mlocked:           22912 kB
SwapTotal:             0 kB
SwapFree:              0 kB
Zswap:                 0 kB
Zswapped:              0 kB
Dirty:            706352 kB
Writeback:             0 kB
AnonPages:      18876988 kB
Mapped:          8931096 kB
Shmem:          15762320 kB
KReclaimable:   20891728 kB
Slab:           24328040 kB
SReclaimable:   20891728 kB
SUnreclaim:      3436312 kB
KernelStack:       73584 kB
ShadowCallStack:   18464 kB
PageTables:       255136 kB
SecPageTables:     56976 kB
NFS_Unstable:          0 kB
Bounce:                0 kB
WritebackTmp:          0 kB
CommitLimit:    63799264 kB
Committed_AS:   180345144 kB
VmallocTotal:   135288315904 kB
VmallocUsed:      276228 kB
VmallocChunk:          0 kB
Percpu:            52800 kB
HardwareCorrupted:     0 kB
AnonHugePages:   1949696 kB
ShmemHugePages:        0 kB
ShmemPmdMapped:        0 kB
FileHugePages:     81920 kB
FilePmdMapped:         0 kB
CmaTotal:              0 kB
CmaFree:           79496 kB
Balloon:               0 kB
HugePages_Total:       0
HugePages_Free:        0
HugePages_Rsvd:        0
HugePages_Surp:        0
Hugepagesize:       2048 kB
Hugetlb:               0 kB
", "\n"], l_ :> (StringTrim[First[StringSplit[l, ":"]]] <> "_kb" -> ToExpression[First[StringSplit[Last[StringSplit[l, ":"]]]]])];
g = StringTrim /@ StringSplit[First[StringSplit["87, 0, 31.78, 72, 1755, P0
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
ups.load: 27
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
 Flatten[Table[With[{ps = psi[t[[2]]]}, KeyValueMap[chk[t[[1]] <> "." <> #1, #2, j[t[[1]]][#1], 0] &, ps]], {t, {{"psi_cpu", "some avg10=11.45 avg60=4.84 avg300=1.91 total=69294037954
full avg10=0.00 avg60=0.00 avg300=0.00 total=0
"}, {"psi_mem", "some avg10=0.00 avg60=0.00 avg300=0.00 total=1118312676
full avg10=0.00 avg60=0.00 avg300=0.00 total=1060547899
"}, {"psi_io", "some avg10=2.30 avg60=1.98 avg300=1.96 total=13619398538
full avg10=1.90 avg60=1.67 avg300=1.78 total=12752145777
"}}}], 1],
 MapIndexed[chk["thermal_c.tz" <> ToString[First[#2] - 1], ToExpression[StringTrim[#1]]/1000, j["thermal_c"]["tz" <> ToString[First[#2] - 1]], 0] &, {"83600
", "73700
", "79400
", "74500
", "83600
", "74100
", "79600
"}],
 chk["mem." <> #, mi[#], j["mem"][#], 0] & /@ {"MemTotal_kb", "MemAvailable_kb", "SwapTotal_kb", "SwapFree_kb"},
 MapThread[chk[#1, If[StringMatchQ[#2, NumberString], ToExpression[#2], #2], j[#1], 0] &, {gk, g}],
 {chk["ups_load_pct", uv["ups.load"], j["ups_load_pct"], 0], chk["ups_realpower_nominal_w", uv["ups.realpower.nominal"], j["ups_realpower_nominal_w"], 0], chk["ups_status", u["ups.status"], j["ups_status"], 0], chk["input_voltage", uv["input.voltage"], j["input_voltage"], 0], chk["battery_runtime_s", uv["battery.runtime"], j["battery_runtime_s"], 0]},
 {chk["ts_utc_vs_ts_unix", DateString[FromUnixTime[Floor[j["ts_unix"]], TimeZone -> 0], {"Year", "-", "Month", "-", "Day", "T", "Hour", ":", "Minute", ":", "Second", "Z"}], j["ts_utc"], 0]}];
<|"seq" -> j["seq"], "checked" -> Length[res], "failed" -> Select[res, ! Last[#] &], "rows" -> ({#[[1]], If[NumericQ[#[[2]]] && ! IntegerQ[#[[2]]], N[#[[2]], 8], #[[2]]], #[[3]], #[[4]]} & /@ res)|>]