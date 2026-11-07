# Review fix for #72: side-request burst (reviewer gpt-6-astra verdict MERGE_AFTER_FIX at 9d373fc4)

Finding: `svside` called `svwait` once more after its 9th serviced connection and dropped that
descriptor unanswered. Fix (native/omegallm/serve.om `svside`): acquire each connection inside the
bounded loop (timeout only on the first pass), so a connection is accepted only when it is served.

Regression (tests/omegallm/serve-check.py, after t_side_partial_head_control): during a streaming
generation, 12 ready `GET /health` connections; all 12 must get HTTP 200 (`t_side_burst12_answered`)
and the server's /proc fd count must return to its value before the burst (`t_side_burst12_fds`).

| build | ollm sha256 | serve-check (v1 suite, rung-10 ck60000 + merges4096, CORES=4) |
|---|---|---|
| fixed | 5b2e68f4cb69315497f51ee61fc97d65b0594d6337b4dce6d5c8ded81eb8aecb | SUMMARY pass=98 fail=0 (serve-check-fixed.txt) |
| 9d373fc4 (before fix; = reviewer's 3b83f064) | 3b83f064f045ca4132063d10e275ac7e49157cdb580796ea68a7f3ab076875a3 | SUMMARY pass=96 fail=2: t_side_burst12_answered, t_side_burst12_fds (serve-check-before-fix.txt) |

The before-fix build is the negative control: the new checks fail on exactly the reviewed defect.
