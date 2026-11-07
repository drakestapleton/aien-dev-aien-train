# COLLECTIVE-P0-ADMIT: P0 descriptor admission refusals (DRA-15, aien-train#26)

## Outcome and scope

EXERCISED on host Linux AArch64 (Spark spark-b87b, cores 10-11, nice 10), 2026-11-07T10:28:49Z,
at aien-train `b4c67516abdd2c862c812ce168c36045cbfda339`:

`ADMITP0 PASS selftest+a1 x3 cli=46/46 comparators=refuse usage=4/4 mutants_killed=20/20 overflow=trap1 swap_compile_refused=4/4`

(`run-20261107/run.stdout`, exit 0). An exact rerun gave a byte-identical receipt and stdout
(`run-20261107/rerun.cmp`, receipt sha256 `32e08a26…23fd`). The wrong-compiler control printed
`ADMITP0 NOT_RUN` and exited 77 (`run-20261107/negctl-wrong-compiler.*`, omc `3ad9f10f…`).
Measured wall time (Wolfram from the nanosecond stamps in `run-20261107/context.txt`):
5015.0 ms for the run and 3951.8 ms for the rerun (about 70 compiles and 1,060 process runs each).

This closes the MISSING_IMPLEMENTATION row of `evidence/COLLECTIVE-P0/README.md` (branch
`hive/t_60180a9d-collective-p0`) for the synthetic P0 contract. It is a new unit,
`native/collective/admit_p0.om`. The merged and replayed `shared_bank_p0.om` is not changed.
It admits one bank descriptor and one microjob request before any adapter arithmetic. It is
not AEGIS authority, not a router, and it involves no model, checkpoint or GPU. Production
capability and reservation binding (AEGIS#79, protocols#70) stays NOT_RUN.

## Pins

| Subject | Value |
| --- | --- |
| aien-train | base main `0518c915`; branch `hive/t_8cf72aaf-collective-admit` |
| contract | `native/collective/fixtures/admission_v0.json`, committed in `18ad1e6` before the unit existed |
| oracle | `oracle-query.wl` and `oracle-wolfram-raw.json`, committed in `8c09ced` before the unit existed |
| omc | omega-mv `e5b32567a7aff3ce594e3254a622a846a6cd190b` `seed/out/omc` (`git show` of the committed blob), sha256 `2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f` |
| self-test binary | sha256 `ba4c1cdd444f09c5cafb93d06e6427d643dc9ad80bcecb8c9bf27067a914e203`, exit 0, three compiles identical |
| A1 observation binary | sha256 `a476ceeac1a4e7bd5a2a8f21269f2b60a3dbe529c71d2116fff9e11ca272472a`, exit 0 |
| CLI binary | sha256 `ad5e7f4e6ae3a48ee0704762eed2d2cb00f81ab8818a9cbaf0c4830ca4f4579d` |
| Lean | lean-verify project `8b969194`, `leanprover/lean4:v4.35.0`, Mathlib `v4.35.0` |

## Independent oracle

`oracle-query.wl` implements the fixture's rules: check order, codes, response formula and
the rule that state persists. It works from the fixture text, not from the `.om`, and it ran in
the hosted WolframLanguageEvaluator. It returned the following:

- `statuses_match_fixture -> True`: the 46 precommitted `expect_status` values hold;
- the three base identities (FNV-1a 64): `10035045484153181716` (B),
  `9153321889483684885` (B with B[4]=1), `9990611769663005102` (B with B[0]=65537). The unit
  declares them as constants;
- `admit/expected-a1.out` (sha256 `a41baa40…c66a`). It holds the status, response y0 y1, base
  count and adapter count after each of the 46 cases, run in one process;
- `admit/expected-cli.out` (sha256 `90c11b09…6ab8`). It holds the exit status and stdout of each
  case run in its own process: exit = -status, and `-` means empty stdout;
- the overflow ceiling `3*65536^2 + 9*65536^3 = 2533287675297792 < 2^63-1`.

`admit/run.sh` refuses any expected file whose hash differs from Wolfram's. The two tails
(`admit/a1emit-main.om`, `admit/cli-main.om`) only print. Each is appended to every line of the
unit before `fn main to int`, byte for byte.

## Contract classes: one positive and at least one refusal case each, all EXERCISED

Case numbers refer to `fixtures/admission_v0.json`. Every positive case returned 0 and wrote
the Wolfram response. Every refusal case returned its code, wrote no response and left the
counters where the last admitted case left them (A1). Run alone, it exited with -status and
printed nothing (CLI). In the guard column, `admit` lines are those of `admit_p0.om` at
`b4c67516`.

| Class | Code | Positive | Refusal | Guard (line) | Removal mutant: A1 oracle verdict |
| --- | --- | --- | --- | --- | --- |
| rank | -4 | 0 | 1 desc rank 2, 2 req rank 2 | 221 | g01 killed: cases 1,2 admitted |
| shape | -5 | 0 | 3,4 descriptor 3x3/2x2; 5,6 request rows 1 / cols 4 | 224 `shapebad` | g02 killed: cases 3-6 admitted |
| missing base | -6 | 0, 11 | 7 desc+req 0, 8 req 0 | 227 | g03 killed: 7,8 give -7 |
| wrong base (request) | -7 | 11 (other base, own identity) | 9 req identity xor 1 | 230 | g04 killed: case 9 admitted |
| wrong base (content) | -7 | 11 | 10 B[4] changed, identity kept | 233 FNV-1a of B | g05 killed: case 10 admitted |
| model generation | -8 | 16 (all at generation 9) | 12 request generation 6 | 236 | g06 killed: case 12 admitted |
| stale candidate | -9 | 15 (stale but not planned) | 13 stale, 14 newer, 45 stale via selection | 276 | g14 killed: 13,14,45 admitted |
| budget empty | -10 | 19 (k=1) | 17 k=0 | 249 | g09 killed: case 17 admitted with base only |
| budget ceiling | -11 | 20 (k=3) | 18 k=4 | 252 | g10 killed: case 18 admitted, 4 adapters |
| request mode | -16 | 33 (mode 1) | 38 mode 2 | 245 | g08 killed: case 38 admitted |
| invalid index | -1 | 23 (index 7) | 21 index 8, 22 index 2^64-1 | 270 | g12 killed: trap 3 (exit 103) at case 21, no END |
| denied | -2 | 25 (deny an unplanned one) | 24 deny planned 3 | 273 | g13 killed: case 24 admitted |
| phase | -3 | 28 (both -1) | 26 phase 0, 27 phase 2 | 280 | g15 killed: 26,27 admitted |
| duplicate | -12 | 20 (3 distinct) | 29 {3,3}, 30 {1,3,1} | 283 | g16 killed: 29,30 admitted |
| score/permission (runtime) | -13 | 33, 35 (top-k by score among permitted) | 31 arrays swapped, 32 permission 2 | 240 | g07 killed: case 31 gives -2, 32 admitted |
| score/permission (types) | omc error 7 | the unit compiles | x1-x4: four call-site swaps | `abstract perm`, `abstract score` | compile refused 4/4 (lines 273, 191, 273, 240) |
| ALL denied | -14 | 34 (deny top, pick next) | 36 all denied, 37 only 2 of 3 permitted | 260 | g11 killed: 36,37 give -1 |
| value range / overflow | -15 | 39 (x at the bound), 44 (out of range but not planned) | 40 x0 65537, 41 x2 2^62, 42 U planned, 43 B with matching identity | 287 | g17 killed: case 40 admitted with a response; case 41 traps 1 (exit 101) in its own process |

Mutants that are not guard removals:

| Mutant | Change | Self-test | A1 oracle |
| --- | --- | --- | --- |
| m18-compute-before-verdict | the response is computed before the status is checked | exit 103 (trap 3 at case 21) | killed: case 1 still returns -4 but the counters move (2 4). This is the "no partial state change" check. It traps 3 at case 21 |
| m19-select-order | top-k selection takes the lowest score | exit 46 | killed: cases 33-35 choose other candidates |
| m20-coordinated | g14 plus the self-test's own expectations rewritten (Exp 13/14/45 and the final counters) | **exit 0 (missed)** | killed: 33 lines differ |

Every guard-removal mutant replaces one `if` line with `if eq ulong 1 ulong 0`. The harness
checks the original line's text before it edits. Every mutant compiled with exit 0; a
mutant that does not compile counts as a harness failure, not a kill. The CLI oracle also
killed all 20 mutants. First differing A1 lines per mutant: `run-20261107/kill-reasons.txt`.

## Overflow: guard plus a proved invariant

The range guard (-15) refuses before the arithmetic. With it removed (g17), case 41 overflows
and the compiler's checked arithmetic traps 1. That is the language backstop. It does not
create a refusal, and the harness requires it (`g17-range-case41 overflow-backstop TRAP1`).
`lean/AdmitP0Bound.lean` proves, for a model hand-copied from `bxrow`, `vdot` and `compute`,
that every prefix sum, f = phase*dot, d = f*U and the accumulator after each of at most 3
adapters stays within 3M^2 + 9M^3 and fits in signed 64 bits. Result: PROVED, `lake env lean`
rc 0. Axioms are a subset of [propext, Classical.choice, Quot.sound]; there is no sorryAx
(`lean/lean-check.log`, file sha256 `273d2269…d62f`). Negative controls in the same file: a
range of 2^20 does not fit (`looser_bound_overflows`), and the ceiling is attained
(`ceiling_attained`). The model-to-code link was made by reading; nothing generated it.

## Reproduce

```sh
OMC=<omega-mv e5b32567 seed/out/omc> sh native/collective/admit/run.sh OUTDIR
```

`run-20261107/out/` keeps the receipt, the A1 stdout and CLI table of every build, the status
files and the compile-refusal stderr. Binaries and the per-case CLI stdout files are not kept;
the run regenerates them.

## Not run or not claimed

- Device, model, trained adapters, router, Spark admission (Core #737) and P1-P4: NOT_RUN.
- AEGIS capability or reservation authority: not modelled (P0 synthetic admission only).
- The x86 build of the unit: NOT_RUN. omc writes an AArch64 ELF only.
- CI: NOT_RUN. GitHub writes are on hold, so nothing was pushed. Independent review is pending.
- One Unix principal and one host. No statistical or vendor-independence claim.
