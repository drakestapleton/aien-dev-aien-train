# Baseline: integration build serving the v3 rung-10 checkpoint (MEASURED, 2026-11-07T00:19Z..03:56Z)

Server: `taskset -c 6 nice -n 10 /dev/shm/hive/ownmodel/b/ollm serve 18297 /tmp/gk/r10/run/ck60000.bin
merges4096.bin` (identities in `ident.txt`: ollm beecf5fa..., ck60000 a53ced72..., merges4096 73a29baf...;
T 256, one generation slot). Runner a20097120cc6... (run.sh, arm t0: temperature 0, seed 1, concurrency 2,
`SPLITS="dev test" PUBLIC=0 REPEATS=0`, PREREG amendment A1), harness rows through the harness lane's run.sh
(origin/feat/ollm-harness 6d753aa, Hermes v0.22.5, verify f1adcad1...). run.sh's own `accept sum` step failed
(rc 127: the runner file had been replaced on disk while the run held it), so the table was produced after the
run with runner 8c4fb0cb... (`accept sum`, same scoring code plus `fill`, which added 0 rows: `results-8.tsv` is
header only). `t0.summary.final` is the `accept sum` table; `results-*.tsv` one row per item;
`harness-summary.txt` the harness lane's rows; `serve.log` one line per HTTP response.

| role | split | n | pass | Wilson 95% | failure reasons | gate |
|---|---|---|---|---|---|---|
| assistant | test | 44 | 0 | [0, 0.0803] | rule 22, busy 20, conn 2 | FAIL |
| coding | test | 28 | 0 | [0, 0.1206] | busy 14, ctx 14 | FAIL |
| hive | test | 46 | 0 | [0, 0.0771] | busy 23, ctx 23 | FAIL |
| harness | test | 18 | 0 | [0, 0.1759] | http 18 (400: Hermes prompt 4397 tokens > T 256) | FAIL |
| assistant | dev (own) | 10 | 0 | [0, 0.2775] | rule 5, busy 5 | report |
| coding | dev (own) | 12 | 0 | [0, 0.2425] | ctx 12 | report |
| hive | dev | 16 | 0 | [0, 0.1936] | ctx 15, busy 1 | report |

Overall FAIL. Assistant test latency over its 22 status-200 rows: p50 371844 ms, p95 674603 ms (limit 30000);
context used max 256 = T. Every coding and hive prompt is refused for context (the hive system prompt alone is
about 1.8 KB; coding prompts 1.5-2.4 KB) whenever it is not refused as busy. At concurrency 2 the one-slot server
answers 503 to the second request while it generates; two requests waited the runner's full 1800 s deadline
unanswered (reason conn). The generated replies are unrelated story text (for example `x-as-de-mem-recall-00`:
"It's a way to stretch." ... "The end."). All numbers re-computed in Wolfram (Wilson bounds, nearest-rank
quantiles, 119113 ms / 64 tokens = 1.861 s per token at a 23-token prompt).

NOT_RUN for this baseline (A1, time): the public dev rows (IFEval 369, HumanEval 164) and the stochastic arms
s1..s3. NOT_RUN always: the retired 35B, outside models, Grokbot/Muse (PREREG section 9).
