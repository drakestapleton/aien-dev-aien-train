# tests/omegallm/accept: DRA-124 acceptance suite

`PREREG.md` is normative (roles, splits, protocol, checkers, gates, controls, amendments). `SOURCES.md` gives
the provenance of every item text. `CHANGES.md` lists code fixes after the freeze (C1: the context-window gate).

    OMC=<pinned omc> OUT=<dir> CORE=<core> sh build.sh            # -> <dir>/accept (and --mutant line|exec|crit|ctx)
    OMC=... CORE=... [HARNESS=<harness dir> VERIFY=<verify>] sh controls.sh WORKDIR [PORT]   # ends CONTROLS PASS
    ACCEPT=<dir>/accept OMC=... CORES=... [CTX=<tokens>] [HARNESS=... VERIFY=...] sh run.sh HOST PORT OUTDIR [MODEL]
                                              # CTX required when GET /health has no model.T
    accept sum OUTDIR suite/thresholds.tsv     # per role x split: n, pass, rate, Wilson 95%, p50/p95 ms, context, reasons, gate, verdict_reason
    accept pair OUTDIR_A OUTDIR_B             # paired table + exact McNemar p
    accept fill SUITEDIR OUTDIR               # NOT_RUN (cut) rows for items a cut-off run never reached
    accept stub PORT ref|garbage SUITEDIR [COUNT [T]]  # the scripted control endpoints (protocol only); T: /health model.T
    accept selftest suite/selftest.jsonl      # IFEval checkers vs recorded upstream verdicts

The test split is private: `~/work/hive/ownmodel/accept/holdout/` (sha256 in `suite/HOLDOUT.sha256`); without
it `run.sh` runs only `SPLITS="train"` or `"dev"`. Ports used by this lane: 18297-18298.
