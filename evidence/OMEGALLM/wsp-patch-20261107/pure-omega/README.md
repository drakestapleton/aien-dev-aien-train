# wpatch pure-Omega drivers, 2026-11-07

Status: wpbuild.om and wpcheck.om IMPLEMENTED and host-CPU EXERCISED.
GPU qualification, inference-quality improvement, merge and deployment: NOT_RUN.
No GPU was opened and no live service was changed. Round40 was read-only.

Directive: `DIRECTIVE-20261107-pure-omega.md` (Drake, relayed by the wsp lane).
The shell build script and the Python test driver were ported to Omega and
deleted. Python remains only as the labeled ORACLE `wporacle.py`.

| File | Status |
| --- | --- |
| `tools/omegallm/wpatch/build.sh` | ported to `wpbuild.om`, deleted |
| `tools/omegallm/wpatch/check.py` | ported to `wpcheck.om`, deleted |
| `tools/omegallm/wpatch/wporacle.py` | ORACLE (digest calculator; never decides PASS or FAIL) |
| `tools/omegallm/wpatch/wpatch.om` | unchanged product |

Compiler: omega-mv `e5b32567a7aff3ce594e3254a622a846a6cd190b`, omc SHA-256
`2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f`.
ORACLE interpreter: `/usr/bin/python3` (Python 3.12.3), SHA-256
`c86f21d0da9290ece2d7d49a3f7ed52aed59cb029abdf0ea25c79634f6cbe960`.

## Build gate: byte-identical wpatch

```text
taskset -c 0 nice -n 19 ../omega-mv/seed/out/omc < tools/omegallm/wpatch/wpbuild.om > /tmp/wpp/wpbuild
exit 0
taskset -c 0 nice -n 19 /tmp/wpp/wpbuild . /tmp/wpp/out2 ../omega-mv/seed/out/omc ../omega-mv 0
exit 0; build.log, last line WPBUILD PASS
```

| Output | SHA-256 | Earlier shell build |
| --- | --- | --- |
| wpatch | `bf993a780c7421cc2cd23d42fef5692135e9bd339f19a90059d4ef7f17be0847` | same bytes (cmp) |
| wpatch-all.om | `7e8b3ca2cf378af25029ce42ca6c760c880fa3612691216e2f2339c369c22591` | same bytes (cmp) |
| wpcheck | `eeb9bdfb7d4979efbdd797b69f79f791445cce64ba7a27ffd07e528d6c0af959` | new |
| wpcheck-all.om | `ad050062f8d44affe7756b934f79d27e23394ee38eaa7fbb03e5c12eb92f82b3` | new |

`cmp` against `/home/drakestapleton/work/wsp/wpatch-build` (the shell build)
also found ollm, ollm.om, sha256-source.om, sha256-layout.om,
sha256-functions.om and sha256-vendored.om identical. sha256.diff differs only
in its two header lines (file paths and timestamps). Result: PASS.

## Small acceptance

```text
taskset -c 0 nice -n 19 /tmp/wpp/out2/wpcheck small /tmp/wpp/out2 /tmp/wpp/w2 tools/omegallm/wpatch/wporacle.py
exit 0; small.log, last line WPCHECK PASS checks=698 commands=117
```

The 117 child processes are 2 ollm, 108 wpatch and 7 ORACLE runs. The in-run
ORACLE negative control (a fully rehashed manifest for a different finite value)
is accepted by wpatch verify and rejected by wpcheck's independent byte
comparison, as required. Result: PASS.

## Driver negative controls

Each control compiles a mutant wpatch from a copy of `wpatch-all.om` with one
changed line (the diff is kept beside the log) and runs the same wpcheck
against it. wpcheck must exit 1 and name the failed check.

| Control | One-line change | wpcheck result |
| --- | --- | --- |
| neg-moment | policy 2 apply writes v = 1 instead of clearing it | exit 1, `FAIL exit` (validate of the policy 2 patch exited 53, want 0), checks=589 commands=45 |
| neg-survive | f32 survival counts unchanged instead of changed entries | exit 1, `FAIL verify f32 survival count` (wpatch exited 0 but printed a count that differs from the ORACLE count), checks=178 commands=11 |

Mutant wpatch SHA-256: neg-moment
`406bb2ef1e1c3ba0cff707d8eeb9c9266bc5777ac7aec19ab896d13e44fe5ea9`, neg-survive
`9c00dd6dae3af708858062a353907f64f1ced5f1d2e9411f832d46203031282f`.
Both controls: PASS (the wrong result was caught).

Driver refusals, also exercised: `wpcheck bogus a b c` exits 2 with the usage
line; `wpcheck small` with an existing WORK exits 1 with
`FAIL /tmp/wpp/exists: I/O failure`; `wpbuild a b` exits 2 with the usage line.

## Real round40 acceptance

```text
flock -w 3600 -o /home/drakestapleton/handoffs/hive/queen/pool-19.lock \
  /usr/bin/time -v taskset -c 19 nice -n 10 /tmp/wpp/out2/wpcheck real /tmp/wpp/out2 \
  /home/drakestapleton/work/wsp/ck/wpatch-pure-real-20261107 tools/omegallm/wpatch/wporacle.py \
  /home/drakestapleton/.local/share/omega-tool-model/round40/model.ck
exit 0; real.log, last line WPCHECK PASS checks=31 commands=9
```

Queued at 08:07:23Z behind the pool-19 lock, finished at 08:11:23Z. The run
itself took 37.21 s wall on core 19 (real.time, MEASURED). The 9 child processes
are 5 wpatch (diff, validate, apply, verify, revert), 3 ORACLE runs and one
sha256sum. The base matched its pinned SHA-256
`7c7b5b5260f2d9453b6076b64e7f23e88341d96498584f2dfaa229c31ad2e346`; the
reverted copy has the same SHA-256 and the source model was unchanged. The
applied checkpoint equals the bytes wpcheck built from the request, with SHA-256
`95c8676227161d5fd425082462333a9180fe0c870478b69446bbf92678f47eac`, the same
value as the earlier Python-driver review run. Result: PASS.

## Labels

Host CPU execution only. This is not GPU qualification, a model-quality result,
a merge or a deployment.
