# Omega LLM as a UEFI application (x86efi): EMULATED

Evidence class: **EMULATED** (QEMU 8.2.2 TCG, q35 + OVMF, on a DGX Spark GB10 host). It is not
hardware qualification. The physical iMac run is EXERCISED on physical hardware (one machine);
its receipt is [`../imac/`](../imac/).

## What ran

`ollm.efi` is the same `native/omegallm/*.om` source as the AArch64 Linux `ollm`, compiled with
`target x86efi` and the platform unit `eio.om` (CONTRACT §9) instead of `lio.om`. It reads
`\OLLM\JOB.TXT` from the boot volume, runs each line as an `ollm` command and writes the
concatenated output to `\OLLM\OUT.TXT`. The job is `tests/omegallm/efi-job.txt` (11 commands:
mathck, adamck, prep, base, init, gcheck, train 20, eval S.CK, eval CK 64, two samples).

| Item | Value |
|---|---|
| Compiler | omc `b4f45121f6c6d5d8a6ed0f5c4f3934b7cc4bec369bfa89523699bd33928f9b55`, omega-mv PR [#1015](https://github.com/aien-dev/omega-mv/pull/1015) commit `5ce9ecaa7b2034d5a7b4502403591d5c2489c06d`. 2026-11-04: omega-mv #1015 merged at `d3d1b1bc`; same omc `b4f45121`. The omc built from `d3d1b1bc` (`5ce9ecaa` is its ancestor) builds the same `ollm.efi` and `ollm-mut-b.efi` bytes (`repin-d3d1b1bc.txt`) |
| `ollm.efi` | sha256 `2474a842…8d7f`, source sha256 `412f1255…b5b6` (`build.txt`) |
| Reference | AArch64 Linux `ollm` `52f5684f…ac1b` from the same tree, omc `2c824805…` (omega-mv `e5b32567`), run by `efi-ref.sh` on core 7 (`ref.out`, `ref-files.txt`) |
| Image | `ollm.img` sha256 `2b9a420a93486a4d37ed78141a45861427090535502243ecbb67fa4008b6c162`, 100663296 bytes, GPT, one EF00 partition, FAT label ALLEN (`image.txt`) |
| Inputs | `inputs.txt`: TinyStoriesV2-GPT4-valid.txt, the v0 checkpoint `ck-20000.bin`, mathref.txt, efi-job.txt |
| Main boot | core 7 (Cortex-X925, MIDR `0x410fd851`), nice 19: `done=1 seconds=1006` (`main/qemu.txt`) |

## Results (`summary.tsv`, all PASS)

| Check | Want | Got |
|---|---|---|
| main | banner `OLLM efi N` first, exactly one `J ms` after each job, `OLLM DONE 11 ms` last. The OUT.TXT body matches the AArch64 reference after efi-check.sh strips the banner, J (timing) and DONE lines | EQUAL |
| mut-b (negative control) | the one-line mutant `ollm-mut-b.efi` must differ | differs: `byte 375, line 13` (`mut-b/check.txt`) |
| ckbad | a checkpoint with one payload byte zeroed: the reference refuses it (rc 14) and the UEFI body equals the reference body | `body-equal,ref-refused` |
| job65535 | a 65535-byte JOB.TXT (OJCAP − 1) runs | EQUAL |
| job65536 | a 65536-byte JOB.TXT is refused with `OLLM efi JOB.TXT?` and no OUT.TXT | refused |

The last line of `main/OUT.TXT` is `OLLM DONE 11 1004245`: 11 jobs in 1004245 ms measured by the
guest's TSC clock (TCG timing, not iMac timing).

## Rerun

From the clone's parent, with the omega-mv #1015 omc and the Omega `imac-image` builder:

```sh
IMAC_IMAGE=<imac-image> EOMC=<omc b4f45121> ABUILD=build-rf EBUILD=build-efi CORE=7 MCORE=8 \
  EV=<new or empty dir> sh aien-train/tests/omegallm/efi-receipts.sh
```

It exits 1 on any FAIL. Wall time here: 1640 s. `EV` is required: the script refuses (exit 2) an
unset `EV` or one that exists and is not an empty directory, including this committed directory,
so a rerun cannot overwrite these receipts. (Before 2026-11-04 the script wrote here directly.)

2026-11-04, aien-train e08443c plus the uncommitted EV guard, core 4 (`CORE=4 MCORE=4`, so the
main and mut-b boots shared one core), into a scratch `EV`: every `summary.tsv` row PASS, and
`summary.tsv`, `ref.out`, `ref-files.txt`, `image.txt`, `image-mut-b.txt` and `inputs.txt` are
byte-equal (`cmp`) to the files here; image `2b9a420a…c162` again. Wall time 2934 s; main
`OUT.TXT` ends `OLLM DONE 11 2283206`. These scratch receipts are not committed. Same day, a
48-byte JOB.TXT (a comment, a line of only spaces and a tab, `adamck`) booted the same `ollm.efi`:
OUT.TXT echoes the blank line with no `J` line and ends `OLLM DONE 1 213`, and `efi-check.sh`
against the new `efi-ref.sh` output prints `EQUAL`; the pre-2026-11-04 `efi-ref.sh` stops at that
line with `rc=2`, and the pre-2026-11-04 `efi-check.sh` prints `DIFFERENT` (not committed).

`build.txt` from the committed run carried absolute paths. They were removed after the run with exactly
the substitution the script now applies (`sed "s|<clone parent>/||g"`, the `build.txt` line of
efi-receipts.sh). No other byte of the receipts was changed.

## Host tools (exact versions in `tools.txt`)

| Tool | Role | Omega replacement |
|---|---|---|
| `imac-image` (Omega) | builds the GPT disk and the FAT volume and writes `EFI/BOOT/BOOTX64.EFI` into it (`efi-image.sh` runs it on a directory holding `BOOTX64.EFI`) | already Omega |
| mtools 4.0.43 (`mmd`, `mcopy`) | makes `::/OLLM`, adds the `OLLM/*` files, and reads every member back for `cmp`, including `BOOTX64.EFI` (`efi-image.sh`); copies OUT.TXT and the written files out after a boot (`efi-qemu.sh`) | PROPOSED: a FAT member writer in `imac-image` (directory entries and cluster chains); the read-back stays an oracle |
| sgdisk 1.0.10 | only its version is recorded in `tools.txt`; no receipt step runs it | none needed |
| QEMU 8.2.2, OVMF 2024.02-2ubuntu0.10 (`OVMF_CODE_4M.fd` `ad23261d…b083`) | emulator and firmware (verification oracle) | none; the physical run is [`../imac/`](../imac/) (EXERCISED on physical hardware (one machine)) |
| sh, coreutils (`sha256sum`, `cmp`, `tr`) | glue and comparison (oracle) | none needed |

## Note (2026-11-04): identity line prefix

`main/OUT.TXT` and the other OUT.TXT files here predate the identity line. Their checks
(`check.txt`) were made at aien-train `e08443c` with the `efi-check.sh` of that commit, which
expects no identity line. From `07e332d` the second OUT.TXT line is an identity line: `M ...` at
`07e332d`, `ID ...` from the bounds fix of aien-train#55 (so it shares no prefix with mathck's
`M e`/`M l` lines). The current `efi-check.sh` requires that line, so it does not accept these
historical files; recheck them with `git show e08443c:tests/omegallm/efi-check.sh`. Nothing in this
directory was changed. The fresh EMULATED run with the identity line is `../efi-ident/20261104/`.
