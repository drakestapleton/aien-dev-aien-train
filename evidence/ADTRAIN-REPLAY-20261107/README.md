# evidence/ADTRAIN-REPLAY-20261107: independent replay of the native AD training path (DRA-14)

Replayed by kanban card t_3dad9df7 (Hermes worker, claude-opus-5-5, anthropic) on
2026-11-07 on the DGX Spark host (Linux aarch64, `baseline/host.txt`), cores 10-11,
nice 10, through `~/handoffs/hive/queen/pool-10-11.lock`. No GPU was used.

Subjects, at their merged pins:

| subject | pin |
|---|---|
| omega-mv #930 (native tape) | merge `19b8340dbae70888c49fcc98299be928831bfd26` (train r5 #996) |
| aien-train #42 (adtrain example) | merge `80bcbd183b597bb1bb3dd220f3e9bf53b008ebee` |
| pinned tape source used by #42 | omega-mv `965fb762…` `native/autodiff664/tape.om` sha256 `1b4ed431…8bde` |
| pinned metadata used by #42 | omega-mv `89752875…` `native/ecosystem663/metadata.om` sha256 `f60b6d62…c7a4` |
| adtrain compiler | omega-mv `bf54b19f` `seed/out/omc` sha256 `62775d2a…712b` |
| current mains (also replayed) | omega-mv `943d955531b9…` (omc `5f90edea…f6df`), aien-train `0518c915dea3…` |

Both pinned `.om` dependencies are byte-identical at `965fb762`/`89752875`, at the merge
`19b8340d` and at omega-mv main `943d9555`. Between `80bcbd18` and aien-train main
`0518c915` nothing under `native/adtrain`, `tests/adtrain`, `docs/adtrain` or
`evidence/ADTRAIN` changed; between `19b8340d` and `943d9555` only `native/autodiff664/.crumb`
and `CONTRACT.md` changed under the AD paths.

## 1. Baseline: the authors' own gates (`baseline/`)

| command | result |
|---|---|
| omega-mv@19b8340d `tests/autodiff664/run-tape.sh`, omc `be8c5130` (the pin at 19b8340d) | `TAPE_SUITE_PASS NATIVE_TAPE_PASS checks=302`; mutants 0/1/2 exit 1 at checks 212/66/171 |
| same, omc `62775d2a` | identical |
| same, omc `5f90edea` (omega-mv main) | identical |
| omega-mv@943d9555 `run-tape.sh`, omc `5f90edea` | `TAPE_SUITE_PASS NATIVE_TAPE_PASS checks=302` |
| aien-train@80bcbd18 `tests/adtrain/run-adtrain.sh`, OMEGA@19b8340d | `ADTRAIN_SUITE_PASS`; refusals 66/65/65/65; mutants 86/0/0; C M21 host arm `exact=75/75 max_ulp=0 verdict=PASS`, mutant-sign `exact=43/75 … FAIL` as required |
| same, OMEGA@943d9555 | `ADTRAIN_SUITE_PASS` |
| same with omc `5f90edea` (control) | `ADTRAIN_SUITE_FAIL compiler-sha256 (5f90edea…)`, exit 1 |
| C M21 replay of PR #42's frozen `evidence/ADTRAIN/frozen/adtrain.fix` | `exact=75/75 max_ulp=0 verdict=PASS`; mutant-sign FAIL as required |

Reproduction: `adtrain.fix`, `adtrain.ck.good` and `run/{T,G,D,R,S,fixture-host}.stdout`
of this replay are byte-identical (`cmp`) to PR #42's `evidence/ADTRAIN` receipts.

## 2. Independent replay (`replay-pin/`, `replay-main/`)

`tests/adtrain/replay/run-replay.sh` (new). Mutant injection is `subst.om` (exact-once
substitution; a pattern that does not match exactly once is an INVALID setup, never a
kill) and checkpoint forging is `ckforge.om` (its own FNV-1a 64 and word codec); neither
reuses the authors' `mutate.om` injectors. Predictions were written before the runs
(`predictions.txt`, three dated addenda).

Final run (run 5), OMEGA = omega-mv `19b8340d` (`replay-pin/replay.txt`) and OMEGA = `943d9555`
(`replay-main/replay.txt`): `REPLAY_PASS fail=0 invalid=0 gap=5`, identical verdict lines.
Its verdicts equal run 3 (`history/run3-replay.txt`) plus the two PADPROBE lines.

**Checkpoint refusals with a valid checksum (18 PASS lines).** PR #42's own refusal
cases only reach two checks: a byte flip is always caught by the checksum, so the
"byte 100 padding" case of `docs/adtrain/CONTRACT.md` is in fact a checksum refusal.
Re-checksummed images reach every check of `ckcheck` on its own:

| image | expect | observed |
|---|---|---|
| mode 0 (re-checksummed, unchanged) | 0, tail = uninterrupted T | 0, identical; forger output byte-identical to the input |
| step 200 (boundary) | 0 | 0 |
| magic, version 2, step 201, count 57, lr bits+1, word 7 = 1, param bit 32, param NaN, param +Inf, checksum byte only | 65 | 65 each |
| data hash xor 1 (valid checksum) | 66 | 66 |
| 537 bytes, 0 bytes, 535 bytes, missing file | 65 | 65 each |

**Each check is load-bearing (12/12 LOADBEARING).** With one check removed from
`mlp.om` (and everything else intact) the good image still loads (exit 0) and the
matching forged image is no longer refused: checksum, magic, version, count, lr, zero
word, data hash and size then load (exit 0); NaN/Inf parameters then fail later in
training (exit 86); a parameter with bit 32 set traps in the checked `uint` conversion
(exit 105); step 201 makes `dtrain`'s `sub upto start` wrap to 2^64−1 and the loop
traps 4 after 1,000,000 passes (exit 104; output kept as a head/tail excerpt with its
sha256). So the step ≤ 200 check is also the only guard of that loop.

**Independent tape mutants (13; 12 KILLED by `tape-test.om`).** Accumulate-overwrite,
E1 tree on 16 lanes, gB stride, gA from the wrong operand, broadcast row 0 only, SUM
axis swap, relu forward identity, relu backward −0, capacity 33 (trap 3), second
`tpback` allowed, seed 2.0 and operand-b admission skipped are all killed. 7 of them also
change the adtrain T trajectory; the other 5 do not reach this 17-node graph.

**Independent trainer mutants (6; 2 KILLED by `run-adtrain.sh`).** `m-db2-index` is
killed by the gradient check. `m-lr32` is killed only because `tests/adtrain/main.om`
`dgc` uses `eps = mllr`, so changing lr also changes the finite-difference epsilon.

### GAP lines (findings about the suites, not failures of the replay)

| mutant | what it does | killed by an existing gate? | caught by the golden receipts? |
|---|---|---|---|
| `t-e1-pad-pos0` | pads E1 reduction lanes with +0 instead of −0 | no: `tape-test.om` 302/302 PASS | no (adtrain T unchanged) |
| `m-skip-last-param` | never updates b2[1] | no: `ADTRAIN_SUITE_PASS` | yes: T stdout and checkpoint differ |
| `m-lr-update-only` | doubles lr in the update only | no: `ADTRAIN_SUITE_PASS` | yes |
| `m-hash-T15` | data hash omits the last target value | no: `ADTRAIN_SUITE_PASS` | yes: checkpoint bytes differ |
| `m-no-fsync` | drops `fsync` before `fclose` of the checkpoint | no | no (not observable without a crash test; NOT_RUN) |

`t-e1-pad-pos0` contradicts the contract (`native/autodiff664/CONTRACT.md`: pad with −0
to match `src/omega_numeric_reduce.c`). `padprobe.om` shows it is not an equivalent
mutant: summing four −0 leaves with `tpsum` gives −0 on the pinned tape (exit 11) and +0
on the mutant (exit 10). `tape-test.om` passes 302/302 with the mutant, so none of its checks
distinguishes the two pads. `run-adtrain.sh` checks only self-consistency (T against R, gradients
against central differences, the C oracle on one step); it does not bind the 200-step
trajectory or the checkpoint bytes to a recorded golden, which `run-replay.sh` does
(`GOLDEN … PASS` lines, against `evidence/ADTRAIN/run/T.stdout` and
`evidence/ADTRAIN/frozen/adtrain.ck.good`).

## 3. Controls of the replay runner (`history/`)

- Wrong compiler (`5f90edea`): `REPLAY_FAIL compiler-sha256 …`, exit 1.
- Non-empty OUT: `REPLAY_FAIL OUT not empty`, exit 1.
- Run 1 (`history/run1-replay.txt`): two patterns matched twice, `INVALID subst=76`,
  `REPLAY_FAIL fail=0 invalid=2 gap=3`, exit 1. Patterns widened, predictions unchanged.
- Run 2 (`history/run2-replay.txt`): `m-lr-update-only` edited the line the suite's own
  `mutate.om` mode 0 injects into, so the suite failed with `mutant0-inject`. That was a
  setup collision recorded as a kill; the runner now classifies `*-inject` as INVALID and
  the mutant edits `mllr`'s use in `mlupd` instead.

## Commands

From the aien-train checkout (branch `hive/t_3dad9df7-adtrain-replay`, adtrain files identical
to `80bcbd18`), with `OMC` = omega-mv `bf54b19f` `seed/out/omc` (sha256 `62775d2a…712b`):

```sh
flock -o POOL taskset -c 10,11 nice -n 10 env OMC=$OMC OMEGA=<omega-mv at 19b8340d> OUT=<new dir> \
    sh tests/adtrain/replay/run-replay.sh          # replay-pin/
flock -o POOL taskset -c 10,11 nice -n 10 env OMC=$OMC OMEGA=<omega-mv at 943d9555> OUT=<new dir> \
    sh tests/adtrain/replay/run-replay.sh          # replay-main/
# baseline/: the authors' commands, from omega-mv and aien-train respectively
OMC=<omc> OUT=<dir> sh tests/autodiff664/run-tape.sh
OMC=$OMC OMEGA=<omega-mv> OUT=<dir> sh tests/adtrain/run-adtrain.sh
make -s test-autodiff-fixture FIXTURE=<aien-train>/evidence/ADTRAIN/frozen/adtrain.fix
```

One replay run takes about 50 s of host CPU on two cores.

## Not claimed / NOT_RUN

GPU execution of the native tape (the GB10 arm of PR #42 replays the C M21 tape, not the
native one; not re-run here), general training (aien-train #6), atomic checkpoint
publication and crash durability (no `rename` host word; `m-no-fsync` is undetectable on
the host), performance, x86 and any hardware qualification. Host evidence only.

Paths: the four `baseline/*/omc.sha256` files had the scratch work directory prefix rewritten
to `$W/` before commit. No other run output was edited; `ckmut-c-step-s.stdout` (18,889,999
bytes) is kept as a head/tail excerpt carrying its byte count and sha256, which
`replay-pin/artifacts.sha256` also lists.
