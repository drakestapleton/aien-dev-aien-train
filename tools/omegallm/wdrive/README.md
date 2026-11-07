# wdrive: Omega drivers for lane wsp (DRA-187)

These four seeded Omega programs build, run and check `wprobe`. They replace the lane's Python and
shell instruments:

| Old file | Omega program |
|---|---|
| `tools/omegallm/wprobe/build.sh` | `wbuild.om` |
| `evidence/OMEGALLM/wsp-dra187-20261107/runarms.py` | `wrun.om` (scoring stays with `wscore`) |
| `tools/omegallm/wprobe/check.py` | `wcheck.om` |
| `evidence/OMEGALLM/wsp-dra187-20261107/policy_check.py` | `wpolicy.om` (its survival formula is `wprobe survive`) |

Every program is compiled by the pinned omc: omega-mv `e5b32567`, `seed/out/omc`, sha256
`2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f`. Output is plain text, one record
per line. Children run with an empty environment, are started through `fork` and `execprog`, and are
reaped with `waitpid`. The pool lock is taken in Omega with the `flock` host word.

## Build

`wbuild.om` is a whole program and also the shared library for the other three. Bootstrap it once,
from the aien-train checkout:

```sh
OMC < tools/omegallm/wdrive/wbuild.om > wbuild && chmod +x wbuild
```

Each of the others is composed after `wbuild.om`, with that unit's `main` renamed to `wbmain`:

```sh
OMC=OMC CORE=0 wbuild OUT/wrun    tools/omegallm/wdrive/wbuild.om@wbmain tools/omegallm/wdrive/wrun.om
OMC=OMC CORE=0 wbuild OUT/wcheck  tools/omegallm/wdrive/wbuild.om@wbmain tools/omegallm/wdrive/wcheck.om
OMC=OMC CORE=0 wbuild OUT/wpolicy tools/omegallm/wdrive/wbuild.om@wbmain tools/omegallm/wdrive/wpolicy.om
OMC=OMC CORE=0 wbuild OUT/wprobe  $ODRV/om2.om $NET $OLLM_PRE $N/lio.om@ollmmain $OLLM_POST tools/omegallm/wprobe/wprobe.om
OMC=OMC CORE=0 wbuild OUT/ollm    $ODRV/om2.om $NET $OLLM_PRE $N/lio.om $OLLM_POST
OMC=OMC CORE=0 wbuild OUT/wsplit  ../omega-mv/om/sha256/sha256-om2.om tools/omegallm/wsplit/wsplit.om
OMC=OMC CORE=0 wbuild OUT/wscore  tools/omegallm/wscore/wscore.om
```

with

```sh
ODRV=tools/omegallm/wdrive  N=native/omegallm
NET="$N/net/http.om $N/net/json.om $N/net/jsonw.om"
OLLM_PRE="$N/math.om $N/data.om $N/lpool.om $N/model.om $N/adam.om $N/ckpt.om $N/bpe.om $N/cli.om"
OLLM_POST="$N/serve.om $N/nogpu.om"
```

These are the files, in the same order, that the aarch64 target of the ollm lane's
`tests/omegallm/build.sh` joins after its `om2` line (`om2.om` is that one line), so no shell script is
in this build path. MEASURED 2026-11-07 at omega-mv `e5b32567`: ollm built this way is byte-identical
to build.sh's (`819664d5…`), and so is wprobe (`cdfd3150…`, against the build.sh-composed route).
build.sh also checks the three `net/` files against pinned sha256s; here the `source_sha256` that
wbuild prints identifies the whole composed source instead. `../omega-mv` is omega-mv at `e5b32567`.

## wbuild

`wbuild OUTBIN PART...`, with environment `OMC` (the pinned omc) and `CORE` (the taskset core,
default 0).

A PART is `FILE`, which is appended as it is, or `FILE@NAME`, which is appended with its single line
`fn main to int` renamed to `fn NAME to int`. If any part has an `om2` line, the output starts with
one `om2` line. Next come every part's `layout ... end` blocks in order, then the parts without their
`om2` lines and layout blocks. Every line that starts with `export fn ` is written as `fn `: the
output is always a program, and a program has no exports. This is how omega-mv's
`om/sha256/sha256-om2.om`, which has four exports, joins wsplit. Without layout blocks and exports
this is plain concatenation, which is what `build.sh` did.

`wbuild` checks the sha256 of `OMC` against the pin. It writes `OUTBIN-all.om` and compiles it with
`taskset -c CORE nice -n 19 OMC`. It renames the result to `OUTBIN`, sets mode 0775, and prints:

```
BUILD_OK <sha256 OUTBIN> OUTBIN source_sha256 <sha256 OUTBIN-all.om> omc <sha256 OMC>
```

| Exit | Meaning |
|---|---|
| 0 | Built. |
| 1 | omc refused the unit. stderr has `BUILD_FAIL omc rc=N`, and `OUTBIN.tmp` is removed. |
| 2 | Usage error. |
| 3 | `OMC` is not the pinned compiler (`OMC_PIN_MISMATCH`). |
| 4 | A renamed part does not have exactly one `main`. |
| 61 | A part is over 8 MiB. |
| 70 | I/O error. |

## wrun

`wrun ARMS OUTDIR`

ARMS is plain text with one arm per line: `NAME SPLIT MODE [ck=PATH] K L I A ...`. Blank lines and
lines starting with `#` are skipped, so the output of `wprobe controls` can be used directly as an
ARMS file. MODE is `gen` or `probe`. Hooks are groups of four decimals, which wprobe judges. Every
line is checked before any arm runs. A bad line exits 2 with `BAD_ARM line N`.

An arm runs only if `OUTDIR/NAME.out` does not exist yet. wrun first takes the pool lock: it opens
LOCK read-only, creating it with mode 0666, and tries an exclusive `flock` every 10 ms for at most
7200 s. This is what `flock -w 7200 -o LOCK` did, and it shares the lock with any other process that
uses `flock` on the same file. If the wait runs out, stderr gets `LOCK_TIMEOUT LOCK` and the arm
counts as exit status 1, which is flock's status for a timeout. The child does not inherit the lock
descriptor (`-o`); wrun holds the lock until the child has exited. The child runs as:

```
/usr/bin/taskset -c POOL /usr/bin/nice -n 10 WPROBE gen CK MERGES 64 SPLITS/SPLIT.rec hooks
```

In `probe` mode the command is `WPROBE probe CK MERGES REC hooks`.

stdout goes to `NAME.out.tmp`. On exit status 0 the file is renamed to `NAME.out`; otherwise it is
renamed to `NAME.out.failed`. wrun then prints the line below and appends it to `OUTDIR/runs.log`:

```
RUN NAME SPLIT MODE RC WALL_MS START_UNIX_MS CK_SHA256 WPROBE_SHA256 OUT_SHA256 hooks...
```

An arm that already has its output prints `SKIP NAME`.

Environment variables:

| Variable | Default |
|---|---|
| `HOME` | None. It is required. |
| `POOL` | 19 |
| `LOCK` | `HOME/handoffs/hive/queen/pool-POOL.lock` |
| `WPROBE` | `HOME/work/wsp/build/wprobe` |
| `CK` | `HOME/.local/share/omega-tool-model/round40/model.ck` |
| `MERGES` | `merges.bin` beside CK |
| `SPLITS` | `HOME/work/wsp/aien-train/evidence/OMEGALLM/wsp-dra187-20261107/splits` |

| Exit | Meaning |
|---|---|
| 0 | Every arm that ran exited 0. |
| 1 | Some arm failed. |
| 2 | Usage error or a bad ARMS line. |
| 70 | I/O error. |

Scoring is done by `wscore`, not by wrun.

**Hooks file.** An arm has at most 64 hook groups (256 words), wprobe's own limit; more is a bad
line (`BAD_ARM`, exit 2). The pinned omc's `execprog` packed list holds at most 64 records and 4096
bytes (omega-mv `e5b32567` `docs/one_layer/OMEGESE.md`, the packed-list paragraph). The pool prefix
and the wprobe command take 13 records, so an arm with at most 48 hook words passes them as
arguments. An arm with more writes them to `OUTDIR/NAME.hooks`, one line, and passes the single last
argument `@OUTDIR/NAME.hooks`, which wprobe reads in place of the hook words. The file is kept as
evidence. Such arms need a wprobe built from `wprobe.om` with `@PATH` support (after aien-train
`72d3377`; `~/work/wsp/build-rank/wprobe`, sha256 `cdfd3150...8aec`, has it). The `RUN` line lists the
hook words either way.

## wcheck

`wcheck BUILD_DIR [MILLI]`. BUILD_DIR must hold `ollm` and `wprobe`.

wcheck is an outside check of `wprobe save`. It works in a fresh `/tmp/wcheck-<ns>` directory, which
it removes afterwards. It makes a small checkpoint with `ollm init` and one `ollm train` step, then
checks eight cases, printing `CASE <name> PASS|FAIL` for each:

| Case | What it checks |
|---|---|
| `edit` | Head and neuron row factors. Only those rows change. The header is kept and its payload FNV is correct. The optimizer state is unchanged. |
| `f32` | Rounding to f32. |
| `exists` | Saving onto an existing file exits 63. |
| `act` | An activation hook exits 2. |
| `dec` | A decoding hook exits 2. |
| `badhook` | A hook on a layer that does not exist exits 2. |
| `nofiles` | No file was left behind by the three refused saves. |
| `big` | A weight over the limit exits 64. |

The last line is `WPROBE_SAVE_CHECK PASS 8 cases` (exit 0) or `WPROBE_SAVE_CHECK FAIL <n> of 8 cases`
(exit 1). Any MILLI other than 1500 is the negative control: the `edit` case must then fail.

| Exit | Meaning |
|---|---|
| 0 | Pass. |
| 1 | Fail, or `SETUP_FAIL`. |
| 2 | Usage error. |
| 70 | I/O error. |

## wpolicy

`wpolicy prep|run BASE P0 P2 WORKDIR`. This is PREREG section 9.

- **BASE** is the unedited checkpoint, at step 600 of 600.
- **P0** is the edit with Adam m and v kept.
- **P2** is the same edit applied with wpatch policy 2.

Both modes first run `WPROBE survive BASE P0 BASE P0 P2` and print its line after `PRE `. That
command exits 67 if P2's weights differ from P0's, and 68 if P0 changes nothing.

Each checkpoint is then copied to `WORKDIR/base.ck`, `p0.ck` and `p2.ck`. Header words 9 and 10 must
both be 600. Word 10 is set to 601, so that `ollm train` takes exactly one step. This changes only
byte 80, because the payload FNV covers the payload alone. Each copy prints `PREP NAME PATH`.

`run` mode goes on to train each copy one step on TRAIN, with stdout to `WORKDIR/NAME.train.log`.
For each copy it prints `TRAIN NAME RC LOG`. Then it prints:

```
p0 S ...    from WPROBE survive BASE P0 WORKDIR/base.ck WORKDIR/p0.ck P2
p2 S ...    from WPROBE survive BASE P2 WORKDIR/base.ck WORKDIR/p2.ck
```

Children run under the same pool lock and prefix as wrun's, taken the same way; a lock timeout is
`FAIL STEP rc=1`.

Environment variables:

| Variable | Default |
|---|---|
| `HOME`, `POOL`, `LOCK` | As for wrun. |
| `OLLM` | `HOME/work/wsp/build/ollm` |
| `WPROBE` | `HOME/work/wsp/build/wprobe` |
| `TRAIN` | `HOME/handoffs/tool-omega-20261104/round40/data/train.tok` |

| Exit | Meaning |
|---|---|
| 0 | Done. |
| 1 | A child exited nonzero. stderr has `FAIL STEP rc=N`. |
| 2 | Usage error. |
| 65 | A header is not at step 600 of 600. stderr has `HEADER NAME STEP TOTAL`. |
| 70 | I/O error. |

## Host programs in the run path

| Program | Version | What it does | Omega replacement |
|---|---|---|---|
| `/usr/bin/flock` | util-linux 2.39.3 | Pool lock with a 7200 s wait. | Done. `wdlock` in `wbuild.om` uses the `flock fd op` host word (OMEGESE.md, keyword id 197) with `LOCK_EX` and `LOCK_NB`, and `sleepns` between tries. |
| `/usr/bin/taskset` | util-linux 2.39.3 | Pins to the pool core (and to CORE for compiles). | Proposed: host word `setaffinity pid A off n`, Linux `sched_setaffinity` (ARM64 syscall 122), with a CPU mask slice of `n` bytes, `n` a multiple of 8 and at most 128. Returns 0 or minus errno. |
| `/usr/bin/nice` | coreutils 9.4 | Adds 10 to the niceness (19 for compiles). | Proposed: host words `getprio which who` and `setprio which who prio`, Linux `getpriority` and `setpriority` (ARM64 syscalls 141 and 140); `which` 0 is a process and `who` 0 is the caller. `setprio` returns 0 or minus errno. `getprio` returns the niceness, not the kernel's `20 - nice` encoding. |

With these host words, `wdspawn` would set the mask and add the increment in the child between
`fork` and `execprog` (`setaffinity 0` with only bit POOL set, then `setprio 0 0` of `getprio 0 0`
plus 10), and the argument list would be only the wprobe command. That frees 7 more records, so up
to 56 hook words would fit as arguments. Neither host word exists at omega-mv `e5b32567`: the
host-word table in `docs/one_layer/OMEGESE.md` has no affinity or priority entry. Until they do,
taskset and nice keep the same arguments that runarms.py, policy_check.py and build.sh used.

## Oracles

None is kept. All four replaced files were deleted. The Python and shell references served only to
gate the Omega programs: identical binaries from wbuild and build.sh, an identical `S4-base.out` from
wrun and runarms.py, the same eight PASS cases from wcheck and check.py, and an identical prepared
`p0.ck` from wpolicy and policy_check.py's header code.
