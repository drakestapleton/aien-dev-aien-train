# Weight-space programming: method note (DRA-187)

Status: method note only. Every published figure below is labelled "published, not reproduced here".
Every Omega result is PENDING until the DRA-187 experiment fills it in. Nothing in this note is a
measurement made by us.

## Sources (pinned, accessed 2026-11-07)

| Short name | Source | Pin |
|---|---|---|
| BLOG | Takehi, Teoh, Zhang, Khattab, "Sparks of Weight-Space Programming: LLMs can natively read & write neural network weights", https://rikiyat.github.io/blog/weight-space-programming/ | published 2026-11-02; no version id on the page, so quotes below are from the text served on 2026-11-07 |
| LOGS | https://github.com/RikiyaT/lm_understand-logs, folder `exp8_math/` (sparse clone at `~/work/wsp/refs/lm_understand-logs`) | commit `4d09ba6d6a7e891dd8063974dfe81b3d78e3494f` |
| HF | https://huggingface.co/RikiyaT/Qwen3.5-0.8B-weight-space-programming (README and file listing only, read through the HF tree API and the raw README) | revision `d1671a178705bcab7644806d23c535517f35723b` |

Rules we kept while reading. No weight file was downloaded or run (no `.safetensors`, `.bin` or `.gguf`).
The HF listing shows one weight file, `model.safetensors-00001-of-00001.safetensors`, 1,746,943,032 bytes,
LFS sha256 `fd1e42acdd118ac1b300d37500fd2885e75f5a09de3a33010d802bf7f737b553`; we record it and did not fetch it.
Derived numbers were computed with the Wolfram Language evaluator; each one is quoted with its query.

## 1. What weight-space programming is

In plain words: a general-purpose language model (the "editor") reads another network's weights and
changes them directly, by reasoning about what each part computes. It does not run gradient descent,
it does not fit weights to a loss, and it does not write a training loop. It may look at the network's
behaviour through a small, counted budget of forward passes.

BLOG reports eight experiments. This note covers Experiment 8 only (make Qwen3.5-0.8B better at math)
and its Gemma 3 270M follow-up, because that is the one that resembles our DRA-187 question: can a
targeted, gradient-free edit fix a demonstrated failure of a language model without harming the rest.

### 1.1 The harness (LOGS `exp8_math/README.md`)

- Editor: "GPT-6 Astra" through the Codex CLI, reasoning effort max. Codex's own tools were off; every
  action went through the experimenters' harness. The harness code itself is not released
  (LOGS README, "Not included").
- Edited model: the text part of `Qwen/Qwen3.5-0.8B` at revision `2fc06364715b967f1860aea9cf38778875588b17`,
  24 layers, thinking mode on.
- Editor's tools: a CPU-only Python kernel over the weights (at most 300 code runs; `save_edit(name, tensor)`
  to change a tensor), practice problems from GSM8K train (7,469) and MATH train (7,275), and a forward-pass
  tool with a budget of 10, 25 or 50 passes. One pass is either a generation (up to 512 practice answers, or a
  paired "both" pass of 256 original plus 256 edited answers on the same problems) or a teacher-forced read of
  up to 1,024 texts that returns log-probs, hidden states, MLP activations or attention.
- Refused by `save_edit`: the final norm, the embedding and output layer
  (`profiles.py`: `frozen = (norm.weight, embed_tokens.weight, lm_head.weight)`), and any edit that only
  multiplies a whole tensor by a constant (`refuse_rescale: True`).
- The editor never saw the benchmarks.

### 1.2 The published workflow, step by step (run `p50c`, 50 passes)

Reconstructed from `runs/p50c/work_notes/final_report.md`, `experiment_history.md` and `final_choice.json`.

1. **Behavioural contrast.** The first generation pass on 96 practice problems: 11 correct, 85 answers ran to
   the 32,768-token limit, and the cut tails were about 95% duplicated 8-word sequences
   (`requests/fwd_1.done.json`: `cut_at_max_tokens: 85`, `generations: 96`). The diagnosis: the model loops,
   so the target is repetition, not missing math facts.
2. **Matched productive vs looping contexts.** Teacher-forced reads of pairs of texts that share content but
   continue either productively or with repetition. The first attempt was invalid because the chat template
   inserted an empty think block; the editor corrected it to the raw thinking template (pass 3).
3. **Direction.** One unit "repetition direction" per site, taken from four matched productive/looping contexts
   at the residual outputs after layers 16 and 20 (that is, the outputs of blocks 15 and 19).
4. **Locating the MLP writers.** Early single-neuron ablation (layer 19 neuron 11) and a layer-19-only rank-one
   removal each gave +6.25 pp (SE 4.35) on 32 reused problems: weak. Removing the direction from both
   layer 15 and layer 19 MLP `down_proj` was much stronger. Candidate attention heads (L15 head 7, L19 head 5)
   were tested and dropped as less selective. Finally the 64 MLP neurons per layer whose write vectors carry
   the most of the direction were chosen, on the original model's pass-4 data only.
5. **The edit.** `W = W0 - alpha * outer(u, mask64 * (u @ W0))` on `layers.{15,19}.mlp.down_proj.weight`
   (shape 1024 x 3584, HF layout `[out, in]`), with `alpha = 6`. `u` is the unit direction in the 1,024-wide
   residual space; `mask64` keeps only the 64 chosen intermediate neurons, so only 64 columns change per tensor.
6. **Dose-response.** Teacher-forced log-prob change on the looping branch vs the productive branch
   (nats per token): alpha 1: -0.02410 vs +0.00232; alpha 2: -0.04870 vs +0.00343; full alpha 4: -0.10372 vs +0.00453;
   top-64 alpha 6: -0.10311 vs -0.00903. Paired generation passes rose with dose (alpha 1 +12.50 pp, alpha 2 +24.61 pp
   on the same 64 x 4 problem set).
7. **Layer isolation.** L15-only alpha 4: -0.08130 on the looping branch; L19-only alpha 4: -0.03446. Both sites
   contribute.
8. **Norm-matched random control.** Directions orthogonal to the repetition direction, per-layer Frobenius norm
   matched within 0.03% to the full alpha 4 edit: looping-branch change +0.00955 (not selective) and, in a paired
   generation pass on 64 x 2 answers, +1.56 pp (SE 3.52), 8 rescues and 6 losses, with the cut share rising
   89.06% to 91.41%. Note: the control was matched to the full alpha 4 edit, not to the final top-64 alpha 6 edit.
9. **Freeze, then paired confirmation.** The top-64 alpha 6 edit was frozen and hash-audited before any
   confirmation. Confirmation used 1,152 practice problems reserved in `fresh_splits.json` (validation_3 128,
   validation_4 256, final_1/2/3 256 each), disjoint from every problem used in selection, generated paired within
   each pass with the evaluation sampling, one sample each, 32,768 tokens.
10. **Submission and release.** The editor submitted float32 copies of the two tensors; the evaluation cast them
    to bfloat16 (`build_ckpt.py`). HF hosts this edited checkpoint.

### 1.3 The three published edits

| Run | Passes | Edit (LOGS `final_answer.md` and `edit/manifest.json`) | bf16 entries changed |
|---|---|---|---|
| p10c | 10 | 30 rank-one edits `W' = W - 1.5 u (u^T W)` on attention and MLP output matrices in layers 8 to 22 | 72,986,982 |
| p25c | 25 | zero columns 1792:2048 of `layers.15.self_attn.o_proj.weight` (switches off attention head 7 of layer 15) | 262,144 |
| p50c | 50 | the top-64 alpha 6 repetition-direction removal on `layers.15` and `layers.19` `mlp.down_proj.weight` | 130,188 of 131,072 touched |

Correction to our brief: the brief said "released checkpoints p10c/p25c/p50c". HF releases only the p50c
model. p10c and p25c are published as exact edit diffs in LOGS (`runs/<run>/edit/`), not as checkpoints.

Wolfram checks for the edit sizes:
- `2*64*1024` -> 131072 (p50c touched weights; matches BLOG "131,072").
- `256*1024` -> 262144 (p25c; matches the manifest).
- `N[100*2*64*1024/(8*10^8)]` -> 0.016384 (percent of 0.8 billion; BLOG says "0.016%").
- `N[100*72986982/(8*10^8)]` -> 9.12337275 (p10c changed about 9.1% of the model, so the "0.016%" figure applies to p50c only).
- `131072-130188` -> 884 touched entries that rounded back to the original bfloat16 value.
- `N[100*64/3584]` -> 1.7857 (percent of intermediate neurons edited per layer).

### 1.4 What the released code does (LOGS `exp8_math/code/`)

- `make_edit_diff.py`: compares the evaluated bf16 checkpoint with the base model tensor by tensor (bit patterns),
  checks that the changed tensors are exactly the submitted ones and that `bf16(submission)` equals the checkpoint,
  then stores each changed tensor as `sparse` (flat int32 indices plus new bf16 bit patterns, used when at most 30%
  of entries change) or `lowrank` (SVD factors of `submission - base` up to rank 8, plus "fixup" entries where
  rounding differs). Writes `edit.npz` and `manifest.json` with base and edited sha256 per tensor.
- `apply_edit.py`: rebuilds each edited tensor from the base safetensors and the diff, asserting the base tensor
  sha256 before and the edited sha256 after. Output is either a full `.safetensors` file or one float32 `.npy`
  per edited tensor.
- `build_ckpt.py`: builds the evaluation checkpoint by replacing every tensor named in `<run>/submission/*.npy`,
  cast to the original dtype (bf16), copying the tied embedding to `lm_head` if needed, and records each tensor's
  relative change. Its docstring still says "Qwen3-1.7B"; the model actually comes from the selected profile.
- `profiles.py`: per-model settings chosen by `MATHEDIT_PROFILE`: paths, frozen tensors, rescale refusal and
  sampling. `qwen35think` (the Experiment 8 runs) is thinking on, temperature 0.6, top_p 0.95, top_k 20,
  presence_penalty 1.5, max 32,768 tokens, seed 0. `V3_LIMITS` sets the pass sizes (512 answers, 1,024
  teacher-forced texts, 524,288 teacher-forced tokens per pass). It also holds the LFM2.5-350M and Gemma 3 270M profiles.
- `evaluate.py`: builds the benchmark files (MATH-500, GSM8K test, AIME 24/25, AMC23, Minerva, OlympiadBench,
  MMLU-Pro 1k, GPQA Diamond, IFEval), runs vLLM with the chat template, grades the last `\boxed{}` with math-verify,
  and scores the mean accuracy over all samples. It imports IFEval and multiple-choice graders that are not released.
  Its top docstring describes an older Qwen3-1.7B non-thinking protocol; the Experiment 8 protocol is `SAMPLING_THINK35`.

## 2. Published numbers (all "published, not reproduced here")

Sampling for every Qwen row: vLLM, chat template with thinking on, temperature 0.6, top_p 0.95, top_k 20,
presence penalty 1.5, at most 32,768 new tokens, seed 0. Samples per problem: MATH-500 4, GSM8K 2, IFEval 2,
AMC23 16, Minerva 4, OlympiadBench 4, GPQA Diamond 4, MMLU-Pro (fixed 1,000) 1. Sources: BLOG table, LOGS
`eval/<run>/merged.json`, `eval/RESULTS_excerpt.md`. We re-read the four `merged.json` files and they match BLOG.

| Qwen3.5-0.8B | MATH-500 % | GSM8K % | IFEval % | MATH-500 hit token limit % | Label |
|---|---|---|---|---|---|
| Base | 7.9 | 13.8 | 21.0 | 93.0 | published, not reproduced here |
| p10c (10 passes) | 12.3 | 25.7 | 49.0 | 87.2 | published, not reproduced here |
| p25c (25 passes) | 14.1 | 25.1 | 39.9 | 86.4 | published, not reproduced here |
| p50c (50 passes) | 48.1 | 67.1 | 62.3 | 33.1 | published, not reproduced here |

Other benchmarks, base / p10c / p25c / p50c (published, not reproduced here): AMC23 0.5 / 1.1 / 1.1 / 23.4;
Minerva 1.5 / 3.9 / 3.5 / 25.4; OlympiadBench 1.3 / 2.4 / 3.9 / 21.8; MMLU-Pro 1k 40.3 / 40.0 / 44.7 / 45.5;
GPQA Diamond 22.7 / 29.4 / 30.1 / 36.6. BLOG's figure shows 24.5 for base GPQA, an interim value; LOGS says
the finished value is 22.7.

Base to p50c differences (Wolfram, inputs are the published figures):
`48.1-7.9` -> 40.2 pp MATH-500; `67.1-13.8` -> 53.3 pp GSM8K; `62.3-21.0` -> 41.3 pp IFEval;
`62.3/21.0` -> 2.967 (BLOG's "3x"); `93.0-33.1` -> 59.9 pp fewer MATH-500 answers at the token limit.
Base IFEval answers also hit the limit often: `ifeval.cut_share` 74.9% base vs 2.2% p50c (LOGS `merged.json`).

### 2.1 Paired confirmation on 1,152 practice problems (p50c; published, not reproduced here)

From `runs/p50c/work_notes/final_report.md`. These are held-out practice problems, not benchmark items.

| Source | n | Original correct | Edited correct | Gain | Label |
|---|---|---|---|---|---|
| GSM8K practice | 576 | 67 (11.6%) | 408 (70.8%) | +59.2 pp, SE 2.1 | published, not reproduced here |
| MATH practice | 576 | 55 (9.5%) | 288 (50.0%) | +40.5 pp, SE 2.0 | published, not reproduced here |
| Combined | 1,152 | 122 (10.6%) | 696 (60.4%) | +49.8 pp, SE 1.5 | published, not reproduced here |

579 rescues and 5 regressions; 576 of the rescues were originally truncated answers. All 696 edited correct
answers closed their thinking, median 9,172 tokens (9,171.5 in the JSON), against 5,310.5 for the original's correct
answers. Answers cut at the limit: 1,038 original vs 212 edited. Published, not reproduced here.

Wolfram check of the paired statistic: with `n=1152; b=579; c=5; d=(b-c)/n`,
`N[d]` -> 0.498264; `N[Sqrt[((b+c)/n - d^2)/(n-1)]]` -> 0.0149914 (equals the reported SE, so the source used the
n-1 form); `N[{d-1.96 se, d+1.96 se}]` -> {0.46888, 0.52765} (equals the reported 95% normal interval);
`b-c` -> 574 = 696 - 122 net newly correct. `N[100*85/96]` -> 88.54 (share of the first 96 practice answers cut).

### 2.2 Other published points

- HF independent re-run of the p50c checkpoint by a third party (akhaliq, 2026-11-02, H200, vLLM 0.33.0):
  MATH-500 51.0%, 31.6% at the token limit; a 25-problem base smoke test gave 5.0%. Published, not reproduced here.
  Wolfram `51.0-48.1` -> 2.9 pp above BLOG's figure, inside what sampling variance on one run could produce
  but not tested by us.
- Smaller budgets: p10c's own paired check on 512 practice problems was +3.71 pp (SE 1.79), described by the editor
  as "modest"; p25c's on 768 practice problems was +8.33 pp (SE 1.43). Published, not reproduced here.
- Other runs in `RESULTS_excerpt.md`, not in BLOG: 0 and 5 passes made no edit; prompt v4 at 10 passes submitted
  no edit; prompt v4 at 25 passes gave 14.1 / 25.1. So the method did not always produce an edit.
- Gemma 3 270M IT negative result (lenient MATH-500 grading, model-card sampling temperature 1.0, top_k 64,
  top_p 0.95, max 8,192): base 6.8%; 5 / 10 / 25 / 50 passes 7.0 / 7.6 / 7.7 / 7.0. Only 8.5% of Gemma's answers
  reach its token limit vs 93.0% for Qwen. Published, not reproduced here. Wolfram `7.7-6.8` -> 0.9 pp best gain;
  BLOG and the editor both call it not established. Edits stayed small (for example doubling one number neuron).

## 3. Claims and how far the sources support them

DEMONSTRATED = shown with controls in the source. CONDITIONAL = shown only in their setting (one model,
one failure mode, practice problems rather than test, agent-driven search). SPECULATIVE = a generalisation
the sources do not test.

| # | Claim | Class | Basis and limits |
|---|---|---|---|
| C1 | The p50c edit is targeted: only two tensors, 64 columns each, 131,072 weights, change | DEMONSTRATED | Bit-exact diff with sha256 per tensor (`edit/manifest.json`, `apply_edit.py`); HF lists the same two hashes |
| C2 | Removing the repetition direction causally reduces looping | DEMONSTRATED (on practice text) | Dose-response on matched branches, layer isolation, norm-matched random control (+1.56 pp, SE 3.52, not selective). Limit: the control was matched to the full alpha 4 edit, not the final top-64 alpha 6 edit, and used 128 answers |
| C3 | The edit does not just force early termination | DEMONSTRATED (on practice text) | All 696 edited correct answers closed thinking, median 9,172 tokens; premature-close log-prob stayed near -19 |
| C4 | The edit raises held-out practice accuracy (+49.8 pp, SE 1.5) | DEMONSTRATED (on practice text) | Frozen edit, 1,152 problems disjoint from selection, paired within pass. One sample per problem |
| C5 | The edit raises MATH-500 and GSM8K test scores | CONDITIONAL | One model, one failure (loops), one evaluation run per checkpoint; a third-party re-run gave 51.0% on MATH-500 |
| C6 | The gain generalises across benchmarks (IFEval 21.0 to 62.3, MMLU-Pro, GPQA) | CONDITIONAL | Shown for this model because loops are not task specific; base IFEval answers were 74.9% cut. Says nothing about failures other than loops |
| C7 | Weight-space programming generalises to other models and failure types | SPECULATIVE | Gemma 3 270M, whose errors are not loops, did not improve (best +0.9 pp, not established) |
| C8 | Other skills are retained (no catastrophic forgetting) | CONDITIONAL for p50c, SPECULATIVE as a general claim | No dedicated retention suite. Indirect evidence only: productive-branch log-prob change -0.009 nats/token, MMLU-Pro and GPQA did not fall. BLOG's "avoid the catastrophic forgetting" is a forward-looking claim |
| C9 | Cost: a few forward passes, no gradients | CONDITIONAL | The no-gradient rule was enforced by an unreleased harness. The real cost for p50c was 158 editor turns, 80 Python runs and 20.3 wall-clock hours, including a 4.7-hour outage (LOGS README), plus full 32,768-token generation passes on a GPU serving the model |
| C10 | An agent can do this automatically | CONDITIONAL | One editor model, one prompt version (v3), three runs at different budgets; 10 and 25 passes gave small gains, other prompt versions sometimes submitted nothing. Not shown for other editors |
| C11 | LLM-driven weight editing will replace optimisers, enable auditing, merging, self-improvement | SPECULATIVE | BLOG "What comes next" section; no experiment tests these |
| C12 | The math gain reflects new math ability | Not claimed by the sources | BLOG says loop removal "lets the model finish answers it could already work out"; the Gemma follow-up exists to test exactly this, and it was negative |

## 4. Reproduction status

**Qwen3.5-0.8B reproduction: NOT_RUN by Drake's no-outside-models rule (2026-11-07). The method, not the model, is reproduced on our own Omega checkpoints under DRA-187.**

Our target is the round40 own tool model (`~/.local/share/omega-tool-model/round40/model.ck`, sha256
`7c7b5b5260f2d9453b6076b64e7f23e88341d96498584f2dfaa229c31ad2e346`, read in place only): V 4096, T 256,
D 384, H 12, F 1536, L 8, P 15,833,472 parameters, OLLMCK02 layout (CONTRACT-V1 section 6). All probes and edits
are `.om` units built on `tests/omegallm/build.sh`, run on CPU. Python is allowed only as an independent checker.

Layout note for the mapping. Qwen stores `down_proj` as `[out, in]`, so one MLP neuron's write vector is a
column. Our checkpoint stores `w2[F][D]` with `y = x . W`, so the same vector is a **row** of `w2`
(384 values). The Omega form of the p50c edit is `w2'[j] = w2[j] - alpha * (w2[j] . u) * u` for the selected
rows `j`, and nothing else.

| Published step | Omega equivalent (DRA-187) | Status |
|---|---|---|
| Behavioural contrast on practice problems | CPU `.om` generation probe on round40 over a tuning split; classify failures (loop, wrong answer, malformed tool call) and pick one demonstrated failure | PENDING |
| Matched productive vs failing contexts | `.om` teacher-forced probe on matched pairs that share a prefix and diverge; record per-layer residual outputs and per-token log-probs in f64 | PENDING |
| Direction | Unit difference-of-means direction per candidate layer, computed in `.om` | PENDING |
| Locating MLP writers | Score each of the 1,536 `w2` rows per layer by its write onto the direction; choose rows on the tuning split only | PENDING |
| The edit | `.om` checked patch: OLLMCK02 in, new file out, base sha256, edit parameters and seed, delta and undo artifact; refuse `wte`, `gf` and whole-tensor rescales, mirroring the published `frozen` list | PENDING |
| Dose-response | Several alpha values, teacher-forced branch log-prob change and paired generation | PENDING |
| Layer isolation | Each site alone vs together | PENDING |
| Norm-matched random control | Orthogonal random direction with the same per-tensor Frobenius change as the chosen edit (the final one, not an earlier dose) | PENDING |
| Paired confirmation | Locked held-out split, never used for selection, paired original vs edited, pre-registered gain threshold | PENDING |
| Decoding-adjustment comparator | Same failure attacked without weight changes (for example a repetition or presence penalty at inference), same held-out split | PENDING |
| Fine-tune comparator | Ordinary fine-tuning of round40 with the Omega trainer on the same tuning data and a matched compute budget | PENDING |
| Retention | Unrelated held-out tasks and general loss on the published evaluation set, original vs edited | PENDING |
| Deployment check | Edited weights rounded f64 to f32 as the GPU runtime does; count edited entries that round back to the original | PENDING |
| Restore | Byte-identical restore of the base checkpoint from the undo artifact | PENDING |

## 5. Risks and threats to validity

1. **Selection on the practice set.** In the source, every candidate (alpha 1, 2, 3, top-64 at alpha 4 and 6) was
   chosen on practice problems from GSM8K and MATH train, and the editor read many outputs. Only the final
   1,152 problems were reserved. For us: the locked held-out split must be written and hashed before the first
   probe, and no probe may read it.
2. **Sampling variance.** Each benchmark checkpoint was scored once (4 or 2 samples per problem); the third-party
   re-run differs by 2.9 pp on MATH-500. LOGS notes that separate generation passes have batching-dependent random
   numbers, so only within-pass pairs are valid comparisons. For us: pair original and edited on the same prompts
   and seeds, report paired SE, and repeat the final check.
3. **Benchmark contamination.** MATH-500 is drawn from the MATH test split and GSM8K test is public; the base
   model may have seen either during pretraining. Loop removal does not depend on this, but the absolute scores
   might. For us: deduplicate held-out items against training text by normalized SHA-256, as in
   `WEIGHT-EDIT.md`, and say that exact matching misses near duplicates.
4. **Model size.** round40 has 15,833,472 parameters. Wolfram `N[100*15833472/(8*10^8)]` -> 1.979 (percent of
   0.8 billion) and `N[8*10^8/15833472]` -> 50.53 (times smaller). A small model may not hold a single clean
   failure direction; the Gemma 3 270M result shows the method can find nothing to fix. A rejected method is an
   acceptable DRA-187 outcome.
5. **f32 deployment rounding of small edits.** The deployed runtime uploads weights as f32, rounded to nearest
   from f64. Wolfram `N[2^-24]` -> 5.96e-8, the relative half-step of f32; an edit smaller than that relative to
   a weight disappears. For comparison, the source's bf16 cast (`N[2^-8]` -> 0.0039) erased 884 of 131,072 touched
   entries. For us: score the f32-rounded edited file, not the f64 one, and report how many edited entries survive.
6. **Retention measurement.** The source has no dedicated retention suite; its "other skills" evidence is
   benchmark gains that may themselves come from fewer loops. For us: retention gets its own pre-registered tasks
   and threshold, and a loss on them rejects the edit even if the target metric improves.
7. **The failure must exist.** The method fixed a failure that dominated the base model (93.0% of MATH-500
   answers cut). If round40 has no single dominant failure, a large gain is not expected and should not be
   reported from a small or post-hoc subset.
8. **Agent-driven search.** The published edit came from a long, adaptive search by one editor model. Our search
   is designed in advance and run by our own tools, so it is not the same procedure; differences in outcome may
   come from the search, not the weights.
9. **Optimizer state.** As `WEIGHT-EDIT.md` already says for our checkpoints, an edited copy keeps Adam moments
   that do not describe the edited weights; edited checkpoints are for inference until a policy exists.

## 6. What this note does not do

It does not run Qwen3.5-0.8B or any outside weights, it does not reproduce any published number, and it
qualifies nothing. Results for section 4 belong to the DRA-187 experiment and its evidence folder.
