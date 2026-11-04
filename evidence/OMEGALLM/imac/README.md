# Omega LLM on the physical iMac (x86efi): EXERCISED on physical hardware (one machine)

Evidence class: **EXERCISED on physical hardware (one machine)**. The UEFI build of `ollm` was
booted from a USB stick on Drake's Intel iMac. OUT.TXT is 3346 bytes and `../efi/ref.out`
is 3237. The OUT.TXT body matches the AArch64 reference after efi-check.sh strips the banner,
J (timing) and DONE lines. TR.BIN, HE.BIN and S.CK match
the hashes in `../efi/ref-files.txt`. This covers the 11 commands of `tests/omegallm/efi-job.txt`
and nothing wider: there was no long training run on the iMac and no second machine.

## What ran

| Item | Value |
|---|---|
| Machine | The run itself does not record machine identity. `ollm` prints no SMBIOS and no CPUID; adding that output is a follow-up. The names iMac18,3 (27-inch Retina 5K, 2017), Intel Core i5-7500 and Apple firmware come from earlier aienux evidence, [aienux `evidence/imac_boot0_2026-10-16`](https://github.com/aien-dev/aienux/blob/main/evidence/imac_boot0_2026-10-16/README.md) |
| Program | `ollm.efi` sha256 `2474a842…8d7f`, the same file as in `../efi/build.txt`: omc `b4f45121…` from draft omega-mv [#1015](https://github.com/aien-dev/omega-mv/pull/1015) `5ce9ecaa` (not merged). `boot.txt`: the stick's `\EFI\BOOT\BOOTX64.EFI`, taken from the same partition copy, has sha256 `2474a842…8d7f` and is byte-equal to a rebuild at aien-train `b30e185` (`cmp` rc 0; a one-byte-changed copy, rc 1) |
| Stick image | `aien-imac-ollm-2474a842.img` sha256 `2b9a420a93486a4d37ed78141a45861427090535502243ecbb67fa4008b6c162`, the `../efi/image.txt` image, written by Drake to a SanDisk Cruzer Glide on 2026-11-01 |
| Job | `\OLLM\JOB.TXT`, `tests/omegallm/efi-job.txt` (678 bytes; banner `OLLM efi 678`) |
| Run | FAT times of `TR.BIN`/`HE.BIN`/`S.CK` 23:37, `OUT.TXT` 23:38 (firmware clock); last line `OLLM DONE 11 186521` |
| Readback | `ollm-readback.sh` on the MacBook copied the stick's partition 1 (99597824 bytes, sha256 `c504af04…b069`) with `dd`, read-only. The files were taken out of the copy with mtools on the Spark (`stick.txt`) |

## Results

| Check | Want | Got | Receipt |
|---|---|---|---|
| OUT.TXT | 3346 bytes; `../efi/ref.out` is 3237. Banner `OLLM efi 678` first, exactly one `J ms` after each job, `OLLM DONE 11 ms` last. The OUT.TXT body matches the AArch64 reference after efi-check.sh strips the banner, J (timing) and DONE lines | EQUAL, rc 0 | `check.txt`, `OUT.TXT` |
| TR.BIN, HE.BIN, S.CK | sha256 equal to `../efi/ref-files.txt` | all three equal | `files.txt`, `check.txt` |
| negative control: one byte of OUT.TXT changed | DIFFERENT | DIFFERENT, rc 1 | `check.txt` |
| negative control: job count 10 instead of 11 | DIFFERENT | DIFFERENT, rc 1 | `check.txt` |
| negative control: banner byte count 677 | DIFFERENT | DIFFERENT, rc 1 | `check.txt` |
| negative control: a `J` line inserted in job output | DIFFERENT | DIFFERENT, rc 1 | `check.txt` |
| negative control: a second `J` line after the first job | DIFFERENT | DIFFERENT, rc 1 | `check.txt` |
| negative control: the first `J` line moved before that job's output | DIFFERENT | DIFFERENT, rc 1 | `check.txt` |
| negative control: `OLLM DONE` not last | DIFFERENT | DIFFERENT, rc 1 | `check.txt` |
| negative control: OUT.TXT truncated, no `OLLM DONE` line | DIFFERENT | DIFFERENT, rc 1 | `check.txt` |
| negative control: CR LF line endings | DIFFERENT | DIFFERENT, rc 1 | `check.txt` |
| negative control: a line after `OLLM DONE` | DIFFERENT | DIFFERENT, rc 1 | `check.txt` |
| FAT after the firmware's writes | `fsck.vfat -n` clean | rc 0, 14 files; of sectors 0, 1, 6 and 7 (boot, FSInfo and their backups) only FSInfo changed (free count, next free); both FATs equal | `stick.txt` |

## Job times

Milliseconds from the firmware clock (`efi 10`), as printed in OUT.TXT, next to the emulated run
(`../efi/main/OUT.TXT`, QEMU 8.2.2 TCG on one GB10 core). Times are not part of the comparison.

| Command | iMac ms | QEMU TCG ms |
|---|---|---|
| `mathck` | 121 | 90 |
| `adamck` | 53 | 107 |
| `prep` (writes TR.BIN, HE.BIN) | 128958 | 31202 |
| `base` | 4874 | 35116 |
| `init` | 658 | 80 |
| `gcheck` | 2813 | 7491 |
| `train … 20 10` | 3468 | 2913 |
| `eval S.CK … 16` | 440 | 448 |
| `eval CK.BIN … 64` | 7058 | 138964 |
| `sample … 0` | 18324 | 393666 |
| `sample … 800` | 18328 | 394110 |
| total (`OLLM DONE`) | 186521 | 1004245 |

[INFERENCE] The jobs that write files (`prep`, `init`, `train`) are slower on the iMac than under
emulation, and the compute jobs (`eval CK.BIN`, `sample`) are faster. That fits writes going
through the Apple firmware's FAT driver to a USB stick, while QEMU writes to an image file. Nothing
here measured that.

## macOS mount note

After the run, macOS 26.6.2 on the MacBook refused to mount the stick's partition, even read-only
(`diskutil mount readOnly`: "failed to mount"). The same bytes, copied with `dd` and attached as
a file (`hdiutil attach -readonly`), mount with all eight files, and `fsck.vfat -n` finds no error.
So the FAT the iMac wrote is valid and the refusal is about the device path; its cause is
not known. The readback therefore copies the raw partition instead of mounting it.

## Reproduce the check

    sh tests/omegallm/efi-check.sh evidence/OMEGALLM/imac/OUT.TXT evidence/OMEGALLM/efi/ref.out 11 678
    MTOOLS_SKIP_CHECK=1 mcopy -i STICK.img ::/OLLM/TR.BIN ::/OLLM/HE.BIN ::/OLLM/S.CK DIR/
    (cd DIR && sha256sum TR.BIN HE.BIN S.CK) | diff - evidence/OMEGALLM/efi/ref-files.txt

`678` is the byte size of `tests/omegallm/efi-job.txt`. The same checker on the emulated
`../efi/main/OUT.TXT` also returns EQUAL (`check.txt`). That file is the existing receipt, not a
new boot. `STICK.img` is the partition copy; it is not in the repository (99597824 bytes, sha256 above).

## Note (2026-11-04): identity line prefix

`OUT.TXT` here was written by the build of `e08443c`, before the identity line, and the check above
was made with the `efi-check.sh` of that commit. From aien-train#55 the second OUT.TXT line is the
identity line (`ID ...`), which the current `efi-check.sh` requires, so recheck this file with
`git show e08443c:tests/omegallm/efi-check.sh`. Nothing in this directory was changed. No physical
run of the identity build (`cee4f9ae…404d` at `07e332d`, or the bounds-fixed build) is recorded.
