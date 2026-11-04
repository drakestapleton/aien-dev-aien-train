# fix-pad: gbfrag checks C's padding columns (2026-11-04)

A review of the bf-g1 gates found that gbfrag's 26 short cases compared only columns 0..n-1 of C.
The eight padding columns of each row (row stride n + 8) were not checked, so a store into them
would have passed. Only the eight long-K cases (`gblrow`) already checked them. Commit f5a6941
adds the same check to the short cases (`docs/omegallm/CONTRACT-BF16.md` 4.1):

- `gbwcr` fills the padding of C with NaN (0x7fc00000) before every case. With epilogue 1 or 2 it
  also fills the padding of Y or M.
- `gbfrow` counts every padding word that is no longer NaN as a mismatch, so it shows in the
  case's `GF` bad count and in GFS.

The BF16 dispatch takes only m and n that are multiples of 64 (`gk.om` gktile), so no gbfrag case
has a partial tile. The check catches a store outside columns 0..n-1 of its row on a full tile,
for example a wrong column offset.

Status: IMPLEMENTED and built (host). The chip run is NOT_RUN. Nothing in this directory ran on
the GPU.

## Host receipts

- `build.txt`: the five gb10 binaries built from f5a6941, the control rebuild of the parent
  a82fc1a (equal to `../build-2.txt`), and the kernel-byte identity.
- `disasm-identity.txt`: the `gpu-disasm.sh` summary of f5a6941. Its SLOT, GPR and SMEM lines
  equal those of a82fc1a, and code_sha256 is unchanged (f2628fda...). gpu-code.bin and
  gpu-gpr.bin compare identical.
- `build-n.txt` (e62a495): mutant n, the negative control of the padding check, and the six
  binaries rebuilt at that head. The product hash changes (05880627..., source change OMUTN only)
  and no kernel byte changes. For a chip run of e62a495 or later, use these hashes, not
  `build.txt`'s.

## Chip run (pending; for the integrator's pre-registered window)

Build the binaries into one directory B with the command in `build-n.txt` (product, then
`--mutant n`, `u`, `l`, `o`, `v`), and check them against the hashes in `build-n.txt`. The input
is the same checkpoint as bf-g1: `/tmp/gk/r7/ckb8.bin`, sha256
0a4c382cbd2fdbb9fe6bc6f5e07e59b1012ec738491ce05570fe38a15be854a3 (provenance in `../README.md`).
Inside the window, use the same command and timeout as `../g1/run.sh`:

```sh
CKB8=/tmp/gk/r7/ckb8.bin
timeout 900 $B/ollm-gb10 gbfrag $CKB8; echo rc=$?
for m in n u l o v; do timeout 900 $B/ollm-mut-$m-gb10 gbfrag $CKB8; echo rc=$?; done
```

Expected results:

| Binary | Expected |
|---|---|
| ollm-gb10 05880627... | `GBFRAG PASS`, `GFS 0`, rc 0, 26 GF lines and 8 GFL lines, all with bad 0 |
| ollm-mut-n-gb10 34595bb0... | `GBFRAG FAIL`, rc 50; 26 GF lines with bad 1, 8 GFL lines with bad 0, `GFS 26` |
| ollm-mut-u-gb10 922b5693... | `GBFRAG FAIL`, rc 50 |
| ollm-mut-l-gb10 11fe8a37... | `GBFRAG FAIL`, rc 50 |
| ollm-mut-o-gb10 d26fbbf1... | `GBFRAG FAIL`, rc 50 |
| ollm-mut-v-gb10 4e9862e1... | `GBFRAG FAIL`, rc 50 |

None of the four planted kernel mutants (u, l, o, v) writes into the padding; they already failed
gbfrag in bf-g1 on column values alone. Mutant n is the padding check's negative control (added
2026-11-04, e62a495). After each short case's launch, and before the comparison, the host writes
0.0 into C's first padding word (block 0, row 0, column n). No column 0..n-1 value changes, so
each short case's one mismatch can come only from the padding check. The long-K cases are not
touched. A product PASS together with mutant n's `GFS 26` shows that the check fires and that no
BF16 store reached the padding in these cases. Both are NOT_RUN on the chip.
