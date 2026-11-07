# P0 admission refusal contract (DRA-15, aien-train#26)

`../admit_p0.om` is a seeded-Omega (OM-2) unit. It admits one synthetic bank descriptor and
one microjob request **before** any adapter arithmetic. It is separate from the merged pilot
`../shared_bank_p0.om`, which it does not change.

- Contract: `../fixtures/admission_v0.json`, precommitted. It holds 17 status codes, the check
  order, the refusal rule and 46 cases with expected statuses.
- Refusal means a nonzero status. The response and the counters are not written. Run as a
  process, a refused case exits with -status and prints nothing.
- Score and permission are distinct `abstract` types. A swap fails to compile (omc error 7).
  A permission entry other than 0 or 1 is refused at run time (-13).
- Judge: `run.sh` compares two observation builds with Wolfram outputs, byte for byte.
  `a1emit-main.om` runs all cases in one process (status, response and counters).
  `cli-main.om` runs one case per process (exit status and stdout). The expected outputs are
  `expected-a1.out` and `expected-cli.out`, made by
  `evidence/COLLECTIVE-P0-ADMIT/oracle-query.wl`. `run.sh` also runs 20 compiled mutants
  that the oracle must kill (17 guard removals, compute-before-verdict, selection order,
  coordinated) and 4 swaps that must not compile.

```sh
OMC=<omega-mv e5b32567 seed/out/omc, sha256 2c824805...> sh native/collective/admit/run.sh OUTDIR
```

Prints `ADMITP0 PASS ...` (exit 0), `ADMITP0 FAIL ...` (exit 1) or `ADMITP0 NOT_RUN ...`
(exit 77: another compiler or a non-AArch64 host). Receipt, status table per contract class,
and the Lean proof of the overflow bound: `evidence/COLLECTIVE-P0-ADMIT/README.md`.

Synthetic P0 admission only. It is not AEGIS authority and not a router, and it involves
no model, checkpoint or GPU.
