# OMEGALLM oracle cross-check receipts

Run date: 2026-11-01. Host: DGX Spark, GB10 Grace. All runs were pinned to core 8 with `taskset -c 8 nice -n 19`. Core 8 is a Cortex-X925: `/sys/devices/system/cpu/cpu8/regs/identification/midr_el1` = `0x410fd851`, part 0xd85. Python 3.12.3, standard library only.

The binaries were built with `tests/omegallm/build.sh` using the pinned omc (omega-mv e5b32567), source sha256 `47c27b0b6f0f962f359330d5fbbaa4b9f974265feb6471359202710d5e70c889` for `ollm`. Each JSON receipt records the sha256 of the binary it ran (`binary_sha256`) and of the referee (`oracle_sha256`, `tests/omegallm/oracle.py` = `3edfb60718c1b7c786275e16d4d593cc6418f591be4f30c5a5e17e0555c0d0fa`); within each label every check ran on the same binary.

| label | binary | sha256 checked |
|---|---|---|
| real | build/ollm (final candidate) | b729cc35faa6b3543ff1893c64e8a6feafc224feba7b99f7f13353e1d2179f22 |
| mut-a | build/ollm-mut-a (attention dK sign) | 69825ec63bde79737483561760b2fa1caabbb019a5019210e84d14ac6f2d93d2 |
| mut-b | build/ollm-mut-b (target shift y = data[o+2..]) | c7ddea4cea9952209e6e4516fc01e98aaf33940a80ccf9a4d7a5cb4d6881fa89 |
| mut-c | build/ollm-mut-c (Adam bias correction removed) | 41c852501c356dcc969ca06cdb367798d36018e2bbb1d896985b453be90bfddb |

An earlier run of this lane checked the pre-fix binaries (ollm a9b5f3ec; mutants f1747fcd, 4b12510f,
73afec79). The fix changed only bounds handling, and every `results` entry of all 28 JSON receipts is
identical between the two runs once shas, paths and timings are left out.

## Commands

These were run from the directory that holds the `aien-train` clone, `build/` and `data/`, after
`sh aien-train/tests/omegallm/core-receipts.sh` had built `build/`. Every path is relative; `xcheck.sh`
points the referee's scratch files at `$WORK/<label>/tmp`, so the receipts name no absolute paths.

```sh
rm -rf scratch-oracle aien-train/evidence/OMEGALLM/oracle/real aien-train/evidence/OMEGALLM/oracle/mut-?
export DATA=data/TinyStoriesV2-GPT4-valid.txt WORK=scratch-oracle/work
sh aien-train/tests/omegallm/xcheck.sh build/ollm real aien-train/evidence/OMEGALLM/oracle v0   # exit 0
for m in a b c; do sh aien-train/tests/omegallm/xcheck.sh build/ollm-mut-$m mut-$m aien-train/evidence/OMEGALLM/oracle; done
# mut-a exit 1, mut-b exit 1, mut-c exit 1
```

`<label>/summary.tsv` lists every check with its exit code and the exact command. `<label>/<check>.log` holds the full output, and `<label>/<check>.json` holds the receipt: argv, rc, stdout, stderr tail, seconds, binary and oracle sha256, and per-result details. The derived `.bin` files stay under `WORK` and are not committed.

## Matrix (exit codes of each check)

| check | real | mut-a | mut-b | mut-c |
|---|---|---|---|---|
| selftest (oracle only) | 0 | 0 | 0 | 0 |
| xprep | 0 | 0 | 0 | 0 |
| xbase | 0 | 0 | 0 | 0 |
| xinit | 0 | 0 | 0 | 0 |
| xgrad | 0 | **1** | **1** | 0 |
| xstep | 0 | **1** | **1** | **1** |
| xeval | 0 | 0 | **1** | 0 |
| xinit / xgrad / xstep / xeval at v0 | 0 / 0 / 0 / 0 | not run | not run | not run |

How each mutant was killed:

- **mut-a**: xgrad `init: gradient` and `perturbed: gradient`; xstep params, m and v in `step0-init` and `step1-chain`.
- **mut-b**:
  - xgrad: loss and gradient in both cases;
  - xstep: stdout, params, m and v;
  - xeval: stdout `E 5 4 6407857 9244584` against the oracle's `E 5 4 6285327 9067810`.
- **mut-c**: xstep params in all four cases (`step0-init`, `step1-chain`, `step2-unclipped`, `step150-synthetic-clip`). xgrad passes, as expected, because the gradient is unchanged.

## Real binary: observed maximum error per tensor

The error is |got − ref| / max(|ref|, 1e-3·max|ref in that tensor|), and every check must stay at or below 1e-9. The derivation of that limit is in `tests/omegallm/ORACLE.md`.

- **xgrad, small** (V=256 T=8 D=16 H=2 F=32 L=2 B=2):
  - loss relative error 0 in both cases, with the micro value equal;
  - maximum gradient error 1.6e-13 at init (wk.1);
  - maximum gradient error 4.1e-13 when perturbed (wq.0).
- **xgrad, v0** (64/64/4/256/2, B=16, P=119104):
  - loss relative error 0 at init and 2.1e-16 when perturbed;
  - gradient at init: wq 2.9e-13, wk 2.2e-13, wpe 1.4e-13, w1 1.2e-13, all others ≤ 7.1e-14;
  - gradient when perturbed: wpe 3.3e-12, wk 2.5e-12, wq 1.8e-12, wo 1.0e-12, w1 9.8e-13, w2 7.4e-13, wte 6.9e-13, g1 6.8e-13, wv 5.9e-13, g2 7.9e-14, gf 9.1e-15.
- **xstep, small**, maximum over the four cases:
  - params 1.2e-13 (w2, in step2-unclipped);
  - m 5.7e-13;
  - v 1.7e-14.
- **xstep, v0**, maximum over the four cases:
  - params 2.5e-13;
  - m 1.5e-11 (wq, in step150-synthetic-clip);
  - v 2.4e-13.
  - The `step` field and the `T` stdout line match exactly.
- Clip coverage is asserted in the receipts:
  - step2-unclipped ran unclipped, at both sizes;
  - the other three cases were clipped.
- **xinit**: params bit-for-bit and the whole-file sha256 identical, at both small and v0.
- **xprep**: stdout `P 27630 24867 2763 19883834 2220914`. TRAIN sha256 is `101b41c6…2fd62fef` and HELD sha256 is `729e0a4a…338ed`, identical to the oracle's own prep.
- **xbase**: `B 4415645 3295113` on both sides.
- **xeval**: stdout identical at both sizes.

The largest observed error is 1.5e-11, below the 1e-9 limit.

## Timings (core 8)

| measurement | real binary | oracle |
|---|---|---|
| v0 grad, B=16, one call | 0.731–0.734 s | 7.73–7.88 s |
| small train step | 0.007–0.008 s | not measured |
| whole real-binary xcheck run, v0 included | 63 s wall (15:59:02Z–16:00:05Z), binary and oracle together | |

## Oracle self-test and negative controls

The receipts are in `selftest/`, run against oracle sha256 `3edfb607…`; the mutated copies were made in scratch, and each file holds its one-line diff:

- `selftest.txt` shows `SELFTEST PASS (0 failures)`, rc 0.
- `negctl-nc_attn.txt` uses an oracle with the dK accumulation sign flipped (the diff is in the file). It shows `SELFTEST FAIL (34 failures)`, rc 1.
- `negctl-nc_ce.txt` uses an oracle with the cross-entropy one-hot sign flipped. It shows `SELFTEST FAIL (55 failures)`, rc 1.

## NOT_RUN

- `sample` is not cross-checked. The contract defines it, but the oracle has no check for it.
- The mutants were run only at the small configuration, not at v0.
- `train` was cross-checked only for one step per case. No multi-step run or long training run was compared.
- The oracle does not test the binary's refusals. Those are core receipts: checkpoint exits 10–15 and data-range exits 22/23 in `evidence/OMEGALLM/core/refuse-*.txt`, and the pre-fix/fixed A/B in `evidence/OMEGALLM/v0/bounds-ab.txt`.
