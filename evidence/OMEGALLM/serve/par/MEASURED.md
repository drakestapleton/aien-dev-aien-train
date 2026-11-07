# servefast MEASURED (S2 `~/work/hive/ownmodel/ck/s2.ck`, sha256 ae7559ea…, V 32768 D 384 H 6 F 1536 L 8 T 4096)

All numbers from the bench receipts in this directory (server log ms, `C status prompt completion
finish ms reused prefilled queue_ms`). Binaries: before = `353dde359d1b0c6a…` (base 2114454),
after = `f7d25df612e85d5f…` (this branch; comment-only edits rebuild to the same sha256).
tok/s = tokens / (ms / 1000); decode ms/token = (17-token warm ms - 1-token warm ms) / 16.
Wolfram (WolframLanguageEvaluator) computed every ratio below from these ms values.

| run (receipt) | server nice | cores | prefill tok/s 512 / 2048 / 3072 | decode ms/token 512 / 2048 / 3072 | turn 2500+60 |
|---|---|---|---|---|---|
| before, 04:22 (bench-b0-0422-nice19) | 19 | 4 | 15.89 / 11.83 / 9.837 | 164.6 / 397.4 / 640.9 | not run |
| before, 05:14 (bench-b0-0514-nice19) | 19 | 4 | 27.56 / 18.87 / 8.777 | 127.5 / 355.7 / 612.9 | 356.161 s |
| before, 05:36 (bench-b0-0536-nice10, beside par=1 on core 6) | 10 | 4 | 13.20 / 12.07 / 11.32 | 192.1 / 358.6 / 564.4 | 341.687 s |
| par=1, 05:05 (bench-par1-0505-nice19) | 19 | 4 | 28.22 / 19.27 / 16.33 | 62.81 / 102.9 / 129.1 | 151.644 s |
| par=1, 05:36 (bench-par1-0536-nice10, beside before on core 4) | 10 | 6 | 28.27 / 19.57 / 24.71 | 65.94 / 109.9 / 69.50 | 93.184 s |
| par=2, 04:57 (bench-par2-0457-nice19) | 19 | 4,6 | 39.88 / 27.67 / 23.73 | 74.13 / 140.5 / 140.8 | 85.852 s |
| par=2, 05:31 (bench-par2-0531-nice10) | 10 | 4,6 | 74.60 / 55.64 / 48.04 | 36.81 / 54.94 / 82.81 | 51.647 s |

Turn ratios (Wolfram): before/par=2 = 356.161 / 51.647 = 6.896 (nice 19 before vs nice 10 par=2),
341.687 / 51.647 = 6.616 (both nice 10), 356.161 / 85.852 = 4.149 (both nice 19);
par=1/par=2 = 151.644 / 85.852 = 1.766 (nice 19), 93.184 / 51.647 = 1.804 (nice 10).
Prefill par=2 / par=1 tok/s: 1.413 / 1.436 / 1.453 (nice 19), 2.639 / 2.844 / 1.944 (nice 10).
MODELED (Wolfram Fit of the 04:22 before-run prefill ms to a x + b x^2 and decode to c + d x):
before turn 261.9 s; the measured before turn (356.2 s, 341.7 s) is higher, the host's load varied.

Peak RSS (VmHWM): before 1,009,904 – 1,009,968 kB; par=1 1,009,984 – 1,009,996 kB; par=2 parent
1,011,764 – 1,011,796 kB (PSS 591,042 – 591,072 kB) plus the logits worker 841,688 – 841,692 kB
(PSS 420,966 – 420,968 kB): PSS sum 1,012,040 kB, the pages are shared copy-on-write.

Conditions: spark-b87b shared with other lanes (load average 11 – 13; another ownmodel lane ran
`ollm serve` on core 6 from about 05:04; the lead's GB10 trainer on core 5). Runs at nice 19
(driver and script both niced) were slower and noisier; at nice 19 the parent and the prefill
worker were often on the same core (`ps -o psr` samples). The same binary's 512-token prefill
ranged 18.6 – 38.8 s across runs: compare rows taken at the same time, and read single ratios as
indicative.
