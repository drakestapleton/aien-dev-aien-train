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

Binary for these gates: wprobe sha256 `4009fd6bfa8ff1b11c8ffbf24ece33253b5b075f390e0d1ed0296d937f9fcf8f`
(source `a9d9dfd1…`), built in `~/work/wsp/build-rank`; the search binary in `~/work/wsp/build` was not
replaced while the search ran.

The Python used in these gates (rank.py, make_controls.py, the policy_check formula, CPython's random)
served only as the reference being reproduced; none of it ships.
