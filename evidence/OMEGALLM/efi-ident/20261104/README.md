# Omega LLM x86efi with the identity line (aien-train#55): EMULATED

Evidence class: **EMULATED** (QEMU 8.2.2 TCG, q35 + OVMF 2024.02-2ubuntu0.10 `OVMF_CODE_4M.fd`
`ad23261d…b083`, on a DGX Spark GB10 host, core 9, nice 19). It is not hardware qualification, and
the binary built here has not been run on the iMac.

## What changed

aien-train#55 adds the identity line (`efi 14`, omega-mv PR #1022) as the second OUT.TXT line. Review
found that `native/omegallm/eio.om` trimmed the CPU brand with
`while and lt s 48 or eq ... get oidb s ...`: Omega `and`/`or` are eager, so on a brand of only NULs
or blanks `oidb[48]` was read and the application trapped 3. The SMBIOS readers could also read past
the 64 KiB copy and did not stop at the structure's double NUL. The fix tests the bound alone, keeps
every SMBIOS read below the copied length, prints `-` for a missing or cut-off field, and changes the
prefix from `M` to `ID` (no line shares a prefix with mathck's `M e`/`M l` lines).

## Builds (`builds.txt`)

| Build | `ollm.efi` sha256 | source sha256 |
|---|---|---|
| `07e332d` (before the fix) | `cee4f9ae397b1b12a46fe8865c517b0fecafeb845843f118b2953ba0b1b6404d` | `61a10a54…5e72` |
| this commit (fixed `eio.om`) | `0b0ad56e106a87e96dabdb231853ff56b7217e91b1e0a252e469f69dae9f76c5` | `ce01bd60…80a0` |

Both with omc `3ad9f10f64309e7acf8a725082b28e23a2a4aeb07e98322fb4dc0fcd8fc93194` (omega-mv #1022).
The `07e332d` rebuild is byte-identical to `EFI/BOOT/BOOTX64.EFI` on the iMac stick image
`aien-imac-ollm-ident-d99d83e2.img` staged for the physical run, so that stick carries the pre-fix
binary.

## Full job (`summary.tsv`, `tests/omegallm/efi-receipts.sh`, all PASS, rc 0)

| Check | Got |
|---|---|
| main: 11-job `efi-job.txt`, body vs the AArch64 reference (`main/check.txt`) | `body EQUAL` |
| main: written TR.BIN, HE.BIN, S.CK vs the reference (`ref-files.txt`) | all three sha256 equal (`101b41c6…`, `729e0a4a…`, `e7beedb6…`), and equal to `../../efi/ref-files.txt` |
| mut-b (negative control, one-line mutant `36ea3a3a…`) | differs, `byte 375, line 13` |
| ckbad | `body-equal,ref-refused` |
| job65535 | EQUAL |
| job65536 | refused |

`main/OUT.TXT` line 2 is
`ID cpu=QEMU TCG CPU version 2.5+ fw=Ubuntu distribution of EDK II fwrev=00010000 smbios=QEMU/Standard PC (Q35 + ICH9, 2009)/pc-q35-8.2`
and its last line is `OLLM DONE 11 1467033` (guest TSC time under TCG, with other jobs on core 9;
not iMac timing). `main/qemu.txt`: `done=1 seconds=1503`.

## Identity edge cases (`tests/omegallm/efi-ident.sh`)

Each case boots a one-job `JOB.TXT` (`adamck`, sha256 `de383a56…`) under QEMU with the machine,
`-cpu` and `-smbios` options listed in the script's header. SMBIOS blobs (`ident/blobs.txt`): n2 `ff855b02…`
(38 bytes), capwalk `089a0c28…` (12250 bytes), capscan `9bb38f75…` (77805 bytes).

| Case | `ident-07e332d/` (old build, negative control, rc 1) | `ident/` (fixed build, rc 0) |
|---|---|---|
| nul: brand all NUL | trap 3: `failed to start Boot0001 … : 00000067`, empty OUT.TXT | `ID cpu=- …` PASS |
| blank: brand all blanks | trap 3, empty OUT.TXT | `ID cpu=- …` PASS |
| n2: type 1 string number past the string set | `M … smbios=OmegaTest/-/??` | `smbios=OmegaTest/-/-` PASS |
| capwalk: type 1 at the 64 KiB copy edge | `M … smbios=OmegaTest/-/???????` | `smbios=OmegaTest/-/-` PASS |
| capscan: no terminator before the copy edge | trap 3, empty OUT.TXT | `smbios=-/-/-` PASS |

OVMF's `00000067` is 103, the status `2^63 | (100 + T)` with T = 3 (bounds trap).

## Rerun

From the clone's parent (`aien-train`, `omega-efi-ident` with omc `3ad9f10f`, `omega-mv`, `data`, `run`):

```sh
IMAC_IMAGE=<imac-image> CORE=9 MCORE=9 EV=aien-train/evidence/OMEGALLM/efi-ident/<new dir> \
  sh aien-train/tests/omegallm/efi-receipts.sh
IMAC_IMAGE=<imac-image> CORES=9 sh aien-train/tests/omegallm/efi-ident.sh <ollm.efi> <outdir>
```

efi-receipts.sh removes `EV` first, so always pass a new directory. Here it ran from a copy of the
work tree at `/tmp` (the work tree is reached through a symlink, which `..` does not follow).

## Not preserved, NOT_RUN

- The first 11-job run of `07e332d` (`OLLM DONE 11 1092577`, its negative controls and the S.CK /
  TR.BIN equality listed in the earlier PR body) was made in scratch space that was not kept. Only
  its binary is reproduced (above). This directory is a fresh run of the fixed build.
- Physical iMac run of `0b0ad56e…`: NOT_RUN. The physical receipt `../../imac/` is the pre-identity
  `e08443c` build.
- The error-44 path (no SMBIOS table) and a firmware with no FirmwareVendor: NOT_RUN (OVMF provides
  both).

`SHA256SUMS` lists every file in this directory.
