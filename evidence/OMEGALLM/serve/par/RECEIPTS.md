# servefast receipts (branch feat/ollm-serve-par; spark-b87b; cores 4 and 6; 2026-11-07)

Build: `OMC=/home/drakestapleton/workspace/hive-worktrees/arch-scale-x/omc/seed/out/omc OUT=DIR CORE=6 sh tests/omegallm/build.sh [--mutant X]`
(omc sha256 2c82480596bbdc50…, omega-mv e5b32567).

| binary | sha256 | what |
|---|---|---|
| before | 353dde359d1b0c6aad86fee31d86ab006a288709d9a4e806561cb79338ba9fab | base feat/ollm-path-integ2 2114454 |
| measured | f7d25df612e85d5feb52176f81d57367fd653f66c84751fd956416e33175d09b | 0c41a27 / e2f29fe (bench rows, gates-measured-binary/) |
| final | ae4977d3c2352ab9f267721a2b389542d578ae327e8b3c8b6968f2e5dfb894d5 | head: measured + mutant lw's guarded branch (gates-final/) |
| mutant pp | 88d15f1613a764590759693edf431e301ffc1409afe4bb4d5a1b12b54a48bf8b | prefill worker skips stage B of its last position |
| mutant pq | 436666b90986e47b12b32a1d25ff31d1dd39487276b1d4a63905eefbf2e0332a | logits worker skips its last row |
| mutant kg | 79ba8c1ecc338d3de868d59d08e81efcd35b03e7bdf6a84924bf36c0eea1f06f | KV bank 2 loads one row fewer |
| mutant lw | 03f53809308092d64577c9c8163014c3f00736815de304a23e1a5ccd3249428e | logits worker ignores end of file |

Inputs: S2 `~/work/hive/ownmodel/ck/s2.ck` ae7559ea… (V 32768 D 384 H 6 F 1536 L 8 T 4096, init4
step 0); S1 `~/work/hive/ownmodel/wide4/ck/s1.ck` 8a8e13a1… (D 512, T 256, R1 27,660: the S1
prompts hold 4 token ids >= 27,660, so the layer prefill reads wte bank 2); CHAT1 suite
`/dev/shm/hive/ownmodel/serve4/t.ck` 477d8965…; merges `merges32k.bin` 688b723a…; v1 suite
`/tmp/gk/r10/run/ck60000.bin` + `merges4096.bin`.

## Gates

| gate | command (env) | binary | result |
|---|---|---|---|
| CHAT1 suite par=1 | `serve-check.sh` CK=t.ck SARGS=par=1 | measured, final | SUMMARY pass=43 fail=0, SERVE_CHECK PASS (rc 0), both |
| CHAT1 suite par=2 | same, SARGS=par=2 | measured, final | 43/0 PASS (rc 0), both |
| v1 suite par=1 | `serve-check.sh` CK=ck60000.bin MERGES=merges4096.bin SARGS=par=1 | measured, final | 105/0 PASS (rc 0) |
| v1 suite par=2 | same, SARGS=par=2 | measured, final | 105/0 PASS (rc 0), both |
| par check S1 | `serve-par-check.sh` CK=s1.ck LEN=500 GEN=16 | final (also measured, older driver) | PAR_CHECK PASS (rc 0) |
| par check S2 vs before-binary | `serve-par-check.sh` CK=s2.ck ONE_OLLM=before LEN=1500 GEN=24 | measured (b2 and b3), final | PAR_CHECK PASS |
| par check S2 par=2 vs par=1 | same without ONE_OLLM | final | see gates-final/par-s2.out |
| lifecycle | `serve-par-life.sh` CK=s2.ck | final | PAR_LIFE PASS (rc 0) |
| mutant pp | `serve-par-check.sh` S1 | mutant pp | PAR_CHECK FAIL fails=3 (rc 1): required |
| mutant pq | `serve-par-check.sh` S1 | mutant pq | PAR_CHECK FAIL fails=3 (rc 1): required |
| mutant kg | `serve-par-check.sh` S2 ONE_OLLM=before | mutant kg | PAR_CHECK FAIL fails=3 (rc 1): required |
| mutant lw | `serve-par-life.sh` S2 | mutant lw | PAR_LIFE FAIL (sigterm_mid_prefill: the logits worker left; the driver then killed it) (rc 1): required |

## Benchmarks

`tests/omegallm/serve-bench.sh` with `LENS="512 2048 3072" DEC=16 TURN=2500 ONLY=1`, driver under
`taskset -c 4|6 nice -n 10`, the server under `taskset -c CORES nice -n NICE` (NICE 10 by default;
`NICE=0` gives the server nice 10 when the driver is niced). Files `bench-*.txt` (+ server logs);
tables and Wolfram ratios in MEASURED.md.
micro.txt: host-word costs (mapset, mapget, fork, pipe) of micro-host-words.om.
