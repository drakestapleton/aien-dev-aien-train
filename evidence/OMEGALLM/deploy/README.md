# evidence/OMEGALLM/deploy: DRA-125 staged deployment, rehearsal receipts

Host spark-b87b (aarch64), core 6, nice 10. Branch `feat/ollm-deploy` (from `feat/ollm-path-integ2` 2114454).
`:18091` was not touched: `ss -Hltnp 'sport = :18091'` was empty before and after the run (`rehearsal/env.txt`).
Nothing is DEPLOYED. Procedure: [docs/omegallm/DEPLOY.md](../../../docs/omegallm/DEPLOY.md).

## Final run (run 3), 2026-11-07T04:54:52Z .. 04:57:01Z

`rehearsal/summary.txt`: **REHEARSAL pass=55 fail=0** (each step's command, output and rc in `rehearsal/NAME.txt`).

| Item | Value |
|---|---|
| commit staged (`deploy.manifest` commit) | 09e270f829002b14a28d915a74cce808702e64b7 |
| omc | 2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f (omega-mv e5b32567) |
| `ollm` (serve, with /health identity) | 8bfd6c1b0ea399cdc87880863fdb84e60a8bb4c5f3927a879ad7eacf44439757 |
| `ollm-mut-id` (negative control) | af94ab2f34e6eaa7559e51832b03286d35d98b67a8bc3b24c8f9ed6f13be8463 |
| `mancheck` | 4cde05ce70d66735308946cac9ffc7e464775e3a01e1d64f8225915c83218bb4 |
| `osup` | b831ae59b6606da0913eb383c27da1150659fa87d6f4d14b9d06361581788309 |
| stage A (candidate) | copy of run1 `ck.bin` at step 3000, OLLMCK03 sha256 a034be45f1609fc9d8b32211823294831128e9ec03790b4c38dcdcfc5c475be0, ck_fnv df3d63290ce275c4; `A.model.manifest` sha256 9b38e68c... |
| stage R (rollback) | run1 `ck0.bin` (step 0, its pre-registered sha256 8826e738c66109720970aab2715e9efe9da0059edc22e1bcfe7782a198a6f768 re-verified), ck_fnv e9c5eff757d02c69 |
| tokenizer (both) | OLLMTOK1 V 32768 `merges32k.bin` sha256 688b723a894baa831ee92aaf814918d30823225c45de68c85d9dd244eb79947c, tok_fnv 920b3046a17db9be |
| serve-check (18296 + fixture 18297) | `SUMMARY pass=47 fail=0`: c1_* CHAT1 JSON/SSE at t 0 and 0.8, chatenc identity, tool-call JSON/SSE + 12 refusal controls, prefix reuse bit-exact, t_queue_* FIFO/503/disconnect, identity_stable/expected on both ports |
| cancellation on the candidate | streaming client left after 3 s (curl rc 28): log `C 499 13 27 4 3049 0 13 0`, server idle again |
| kill -9 | pid 2917567 -> 2970914, parent osup 2917564; same `/health` identity; `live` PASS |
| rollback | switch A -> R (`live R` PASS, `live A` refused), R -> A (`live A` PASS); a switch to a failing stage refused, A kept serving |
| clean stop | three `STATE.PORT` files: `UNAVAILABLE ... no ollm process, no listener, /health connection refused (curl rc 7)`; `nothing_left` clean |

These are rehearsal artifacts: stage A is a training snapshot (stage A of run1, T 1024), not a release
candidate. The frozen tuple for SI (t_fceb3625 / t_6c998e75) stays PENDING until a candidate passes
DEPLOY.md section 4.

### Negative controls (19, each refused with the reason shown in summary.txt)

wrong checkpoint sha256 (SUMS), checkpoint sha256 that is no file line, swapped checkpoint (same
size), swapped checkpoint with model.manifest rewritten to match (caught only by the recomputed
header/FNV vs deploy.manifest), wrong FNV in deploy.manifest, forbidden name `qwen3.6-35b`, `url`
line, SI's shipped `PENDING` manifest, duplicate key, another serve binary, one payload byte changed
(gate, `mancheck id`, and `ollm serve` exit 14), one tokenizer byte changed, live check against the
other manifest (A vs R, R vs A), live check of byte-identical files in another directory (resolved exe
path), refused switch, mutant id (`/health` ck_fnv xor 1).

### MEASURED (Wolfram-checked)

| Quantity | Value |
|---|---|
| `/health` 200 after start / restart, run 3 (6 starts: A, kill -9, R, A back, fixture, mutant) | mean 3305.8 ms, min 3055, max 4172 |
| same, run 2 (04:46Z, same steps; core 6 shared then) | mean 21015 ms, min 18629, max 23053 |
| checkpoint bytes = 128 + 24 P, P = 26,745,216 | 641,885,312 |
| model.manifest `bytes` (checkpoint + tokenizer) | 642,015,328 |
| allen-chat system prompt + one user word, CHAT1 tokens (`ollm chatenc`, OLLMTOK1 32K) | 3,678; T 4096 leaves 418 |

### Earlier runs (not receipts; superseded)

Run 1 (04:43Z) found two harness defects: `deploy.sh start` recorded the pid of a shell function
wrapper, so `switch` sent SIGTERM to osup itself and orphaned its child (killed by hand, a process this
lane started), and the expected-identity JSON kept a trailing brace. Run 2 (04:46Z) passed 54/55: the
leftover check counted another lane's `ollm` on :18295. Both fixed before run 3. Run 3's `env.txt`
`host deps` line lists only the first tool (a `command -v` defect fixed after the run): the host tools
are /usr/bin/sha256sum, /usr/bin/curl, /usr/bin/ss, /usr/bin/taskset, /usr/bin/nice, /usr/bin/git and the
Hermes venv python3 (serve-check referee).

## Inventory

`consumers.md`: the read-only :18091 consumer inventory (2026-11-07T04:31Z) used by DEPLOY.md section 5.5.
