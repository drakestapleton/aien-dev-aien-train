# Pure-Omega port of the DRA-187 instruments (Drake directive 2026-11-07 ~07:31Z)

Every new first-party instrument of this lane is now seeded Omega compiled by the pinned omc
`2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f` (omega-mv `e5b32567`). Each port was
proven against the frozen output of the Python script it replaces (still readable in git history at
`dc61d1c9`) and against a negative control. The Python scripts are deleted. Runs made before the port
(S base, D base, P1, P2, the S search) used the Python runner and scorer; their outputs are re-derived by
the Omega tools below and agree.

| Replaced | Successor | Gate (MEASURED) | Negative control (MEASURED) | Status |
|---|---|---|---|---|
| `rank.py` | `wprobe rank META PROBE` | byte-identical output to rank.py on `diag/D-base.out`, `diag/D-P1-copyheads-x1.5.out`, `diag/D-P2-copyheads-x0.out` (3/3, `cmp`) | a probe file with record 0 removed exits 65; one head value of row 57 set to 9.9999 changes only head 6.6's mean (+3.556 to +3.632) | PASS |
| `make_controls.py` | `wprobe controls CK SEED [hooks]` (+ `wprobe rng`) | arm lines byte-identical to make_controls.py for seeds 187101..187103 on a 12-group selection (4 heads at 2000, 8 neurons at 500); target and realised norms equal to 4 decimals; `wprobe rng 187101 2000` equals CPython `random.Random(187101).getrandbits(32)` x2000 (sha256 `e16c709e…`) | a selection with groups on both sides of 1 exits 2; kind 3 exits 2; seed 187104 draws other units | PASS |
| `policy_check.py` (computation) | `wprobe survive BASE EDIT BASE1 EDIT1 [EDIT2]` | on four saved checkpoints with a planted one-step change (edit x1.5/x0.5, after-step x1.4/x0.6): `S 12672 0.800000000 0.200000000`, equal to policy_check.py's formula evaluated in Python on the same files | EDIT2 with one neuron scale changed exits 67; EDIT equal to BASE exits 68; a missing file exits 70 | PASS |
| `make_splits.py`, `make_d.py` | `wsplit splits OUTDIR [OFFSET]`, `wsplit d OUTDIR` (`tools/omegallm/wsplit`) | on the same inputs, all 8 `.json`/`.rec` files and the summary stdout byte-identical to the Python; S, G, D byte-identical to the committed files (re-run by wsp, `cmp`); the four new `.meta` files equal the ones derived from the frozen splits | seed offset 1 changes all 6 S/H/G files | PASS; H frozen, see below |
| `score.py` | `wscore SPLIT.rec SPLIT.meta GEN.out` (`tools/omegallm/wscore`) | per-row pass vector equal to each stored `.score.json` on all 16 scored S arms (re-run by wsp); summary lines equal score.py; synthetic G/S/H/D outputs and 7 fuzz seeds (3783 rows each) equal the ORACLE `oracle_score.py`, 0 row differences | `"path"` changed to `"paht"` in one passing row: that row 1 to 0, control 24/24 to 23/24, ORACLE agrees | PASS |
| (new) `wprobe` hooks from a file | last argument `@PATH` | `controls` and `gen` (2 S records) byte-identical with hooks on the command line and in a file | 5-word file exits 2; missing file exits 70; 65 groups exits 2 | PASS |
| `wprobe/build.sh` | `wdrive/wbuild OUTBIN PART...` | wprobe built from the same source is byte-identical to build.sh's (`4009fd6b…`); wbuild rebuilds itself byte-identically; wsplit via wbuild equals the old sed+cat route; wscore via wbuild equals plain omc (re-run by wsp) | wrong omc exits 3; a renamed part without exactly one main exits 4; composing SHA-256 without the export rule fails to compile (omc error 9) | PASS |
| `runarms.py` | `wdrive/wrun ARMS OUTDIR` | `S4-base.out` byte-identical to runarms.py's (`324e55c9…`); the 32-group arm `S-E2-m32-b500` on 4 S records, passed as a 128-word hooks file, byte-identical to wprobe given the same 128 numbers inline (re-run by wsp); a held pool lock is waited for | bad hook: `.out.failed`, rc 1; 65 groups: `BAD_ARM line 1`, rc 2 (re-run by wsp) | PASS |
| `wprobe/check.py` | `wdrive/wcheck BUILD_DIR [MILLI]` | `WPROBE_SAVE_CHECK PASS 8 cases`, as check.py (re-run by wsp) | MILLI 1499: `FAIL 7 of 8 cases` (re-run by wsp) | PASS |
| `policy_check.py` (driver) | `wdrive/wpolicy prep`/`run` | `prep`: precheck `PRE S 10 1.000000000 0.000000000`, prepared `p0.ck` identical to policy_check.py's header code; `run` NOT_RUN (needs the one-step training runs of section 9) | applied checkpoint as P2: survive rc 67; P0 equal to BASE: rc 68 | PASS (prep); NOT_RUN (run) |

Binaries: the `rank`, `controls` and `survive` rows used wprobe sha256
`4009fd6bfa8ff1b11c8ffbf24ece33253b5b075f390e0d1ed0296d937f9fcf8f` (source `a9d9dfd1…`); the `@PATH` row
used `cdfd3150a8b9b03e14ff8089057cb3c1ea3d82232491935692de3f4448c48aec`, which wbuild reproduces exactly.
Both were built in private directories; the search binary in `~/work/wsp/build` was not replaced while the
search ran.

**H stays frozen.** Regenerating H today differs from the committed H in 3 of 288 rows (indices 31, 61,
248). The cause is one new exclusion, item 1199, which first appears in
`round41/c9/results/c9b-round40-fam-dev.json` (written 07:32:25Z, after H was cut at 06:04:35Z); it is an
evaluation output containing model text, not round40 training data. Excluding only 1199 reproduces the
committed H.json and H.rec exactly. Evidence in `port/wsplit/`.

`oracle_score.py` is an ORACLE: it imports `check_answer` from round40 `repair.py` and is used only to
check wscore. It is not part of any run.

The Python used in these gates (rank.py, make_controls.py, the policy_check formula, CPython's random)
served only as the reference being reproduced; none of it ships.
