# DRA-124 acceptance suite: code changes after the freeze

PREREG.md is frozen (sha256 7133f654c23b087c4b1df7531f0b67c9bf9fe349d0ebc5325a73b2f3814a04c9, unchanged).
The entries below are code fixes that make the runner enforce what PREREG already says. They are not
threshold amendments: no gate, item, checker or threshold file changed (suite/SHA256SUMS still holds).

## C1 (2026-11-07): enforce the context-window gate (PREREG section 4)

Defect. PREREG section 4 gates every role at "context window >= 8192 tokens", and `suite/thresholds.tsv`
carries it as ctx_min (column 6). `accept sum` loaded ctx_min (`acthr`, tv[3]) but the verdict function
`acgv` never read it, so an endpoint serving a shorter context could PASS a gated role whenever its rows
passed (for example a short-prompt pass at T 4096). Only the row reason `ctx` (a 400
context_length_exceeded) was checked, which a window just big enough for the suite's prompts never trips.

Fix (accept.om, run.sh, build.sh, controls.sh):
- `accept run`: before its items each worker writes OUTDIR/context-W.tsv (`context TAB source`, then
  `CTX TAB SOURCE`): SOURCE `health` = GET /health answered 200 with a numeric "model":{"T":..} (the
  served context of `ollm serve`, feat/ollm-deploy + queen/serve-loaded-identity; its CHAT1 server refuses
  prompts over T with 400 context_length_exceeded); else `declared` = environment variable CTX (decimal
  tokens; REQUIRED for endpoints without model.T, documented in run.sh); else `unknown` (CTX `-`).
  /health model.T wins over CTX.
- `accept sum`: reads context-0..8.tsv; the endpoint context is the smallest recorded, unknown if any
  record is unknown; with no record (outdirs from before this fix) it uses CTX from its environment
  (source `sum_env`). The summary gains a `context TAB CTX TAB SOURCE` line and a 17th column
  `verdict_reason` (columns 1-16 unchanged).
- `acgv`: first, regardless of row results, a gated line with ctx_min > 0 FAILS with reason
  `context_unknown` when the context is unknown and `context_below_prereg` when it is below ctx_min.
  Otherwise as before; the other reasons are rows_missing (NOT_RUN), n_mismatch, below_min, p95_over,
  crit_busy_ctx_rows, ok. The stochastic thresholds carry the same ctx_min 8192, so each seed is held to it.
- `accept stub PORT MODE SUITEDIR [COUNT [T]]`: T > 0 makes GET /health declare model.T = T.
- `build.sh --mutant ctx` (ACMUT 4): `acgv` skips the context check; controls.sh must catch it.
- controls.sh: C1 now runs the ref stub at T 8192 (as before, plus context and verdict_reason checks);
  C5 ref at T 4096: every gated role FAIL context_below_prereg while its rows are 44/44, 28/28, 46/46 PASS;
  M5 the ctx mutant summing C5's rows PASSES the chat roles (caught); C6 no model.T, no CTX: every gated
  role FAIL context_unknown; C7 no model.T, CTX=8192: PASS; C8 sum fallback: none -> context_unknown,
  CTX=8191 -> context_below_prereg, CTX=8192 -> PASS. C4's scripted harness fixture is given CTX=8192.

Receipts: evidence/OMEGALLM/accept/controls-dfe061ff/ (runner dfe061ff..., CONTROLS PASS, selftest
1124/0) and evidence/OMEGALLM/accept/context-fix/ (a real integ3 `ollm serve` at T 256 and, after
`ollm tune4 ... 8192 4 2`, at T 8192: records `256 health` even with CTX=8192 declared, and `8192 health`;
the baseline r10 rows re-summed: verdicts unchanged FAIL, reason context_unknown without CTX and
context_below_prereg with CTX=256, its served T).
