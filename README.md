# aien-train

Pre-alpha. Training our own language model on AIEN's own engine (Omega, no CUDA, no third-party training framework), starting on one DGX Spark (GB10).

The thesis under test: the big labs got where they are by pushing mass data and mass compute through a stack they built as they went. We know their pitfalls now. If we go back through that history first, write the lessons down, and design the training run around the physics of the chip (keep the work on the math cores, stop streaming weights through slow memory every step), a small machine can train a real model the right way the first time.

Every claim in `docs/` links to a source or to a receipt in `evidence/`. Numbers carry the chip they were measured on.

## How it works

**Problem.** Train a language model with no CUDA and no third-party training framework. Every forward pass, gradient, optimizer step, tokenizer and checkpoint is first-party Omega (`.om`) source, compiled by the seeded Omega compiler `omc` from [omega-mv](https://github.com/aien-dev/omega-mv).

**Mechanism.** [Omega LLM](docs/omegallm/README.md) is a decoder-only transformer in [`native/omegallm/`](native/omegallm/).

- **Build.** [`tests/omegallm/build.sh`](tests/omegallm/build.sh) concatenates `math.om data.om`, a pool unit, `model.om adam.om ckpt.om bpe.om cli.om` and a platform unit into one program, `ollm`.
- **Train.** `ollm train` reads u16 tokens and runs the forward pass, cross-entropy loss, backward pass and Adam step. It writes a checkpoint every `EVERY` steps.
- **Evaluate.** `ollm eval` reports held-out nats per token.
- **On the GB10.** `gtrainf` and `gtrainb` keep the weights and Adam state on the chip ([rung 4 onward](docs/omegallm/README.md#gb10-gpu-training-rung-4)).
- **Specs.** [CONTRACT.md](docs/omegallm/CONTRACT.md), [V1](docs/omegallm/CONTRACT-V1.md), [V2](docs/omegallm/CONTRACT-V2.md), [V3](docs/omegallm/CONTRACT-V3.md), [BF16](docs/omegallm/CONTRACT-BF16.md).

The earlier [NL1 experiment](native/neuralese/README.md), a learned numerical channel between two small networks, uses the same toolchain on a much smaller scale.

**Design choices, and why.**

- **An outside referee for the math.** The built-in `gcheck` and `adamck` are smoke checks of the binary against itself. The gate for the gradient and the Adam step is a separate Python-stdlib referee: [`tests/omegallm/ORACLE.md`](tests/omegallm/ORACLE.md) and [`evidence/OMEGALLM/oracle/`](evidence/OMEGALLM/oracle/). Deliberately broken builds (mutants) must fail it.
- **Exact checkpoints that refuse damage.** Steps 0→40 in one run and 0→20→40 in two runs give byte-identical checkpoints. A truncated, flipped or overlong file exits 10–15 instead of loading ([status table](docs/omegallm/README.md#status)).
- **The chip is checked against the CPU.** In rung 10, the f64 CPU `eval` printed exactly the GB10 line `E 60000 2243 1204466 449322` ([`evidence/OMEGALLM/gpu-r10/README.md`](evidence/OMEGALLM/gpu-r10/README.md)).
- **BF16 training, f32 evaluation.** This was Drake's decision, recorded in [CONTRACT-BF16 §7](docs/omegallm/CONTRACT-BF16.md).

**Worked budget.** All arithmetic is WolframLanguageEvaluator, and each figure is checked against a file. A checkpoint holds the parameters plus Adam's two moments, all f64, so it costs 3 × 8 = 24 bytes per parameter plus a header:

- **v0, 119,104 parameters, MEASURED.** `112+24*119104 -> 2858608` B. This is the size of the file `ollm init` writes (reproduced below).
- **v2, 15,833,472 parameters, MEASURED.** `120+24*15833472 -> 380003448` B, about 362.4 MiB. `evidence/OMEGALLM/gpu-r7/cpu/ock-boundary.txt` loads exactly that file.
- **Training time, rung 10 on the GB10, MEASURED.** The summed `gtrainb` wall time from step 250 to 60000 is 11,478.56 s. `11478.56/(60000-250) -> 0.19211` s per step, about 3.19 h in total.
- **Not counted:** activations, scratch buffers and the CPU side.
- **What fits on the chip's own storage, MODELED.** The GB10 physics note estimates that a fully on-chip model has about 1–4 million parameters. That note is on the unmerged branch [`physics/gb10` @ 001ec9a](https://github.com/aien-dev/aien-train/blob/001ec9a944023a4280791c1be6e7f6f3727afb01/docs/physics/gb10-training.md), not on main.

**Limitations and failed approaches.**

- **NL1 missed its main target.** The learned channel reconstructed 14 of 16 inputs for every seed, not 16 of 16. The README records this as a FAIL of the target under the frozen schedule; it was not tuned away.
- **A gradient check had to be replaced.** At rung 5, the chip gradient check `gcmp` failed because of ReLU branch flips (`evidence/OMEGALLM/gpu-max/gc-max.txt`, rc 45) and was replaced by `gcmp2`.
- **The model is small.** The best model is the v2 shape: 15,833,472 parameters, trained on TinyStories, held-out loss 1.204466 nats per token. It is not a chat model.
- **The history and lessons notes are not on main.** They live on the unmerged `study/*` and `docs/lessons` branches; see [PLAN.md](docs/PLAN.md).

### Reproduce on a CPU (offline, no model download, no GPU)

Requirements: AArch64 Linux, POSIX `sh`, `git`, `sha256sum` and `cmp`. The compiler is born from omega-mv's seed with no C toolchain.

```sh
git clone https://github.com/aien-dev/omega-mv && cd omega-mv
git checkout 1fe5976d398646b17acabbf6d9dfae96b017e439
sh seed/omega-from-seed.sh            # ends RC=0
sha256sum seed/out/omc                # d6290c7663c2b4bafb59eb3fdf812476e977f4c144def71095c6248ef9b96b84
OMC=$PWD/seed/out/omc; cd ..
git clone https://github.com/aien-dev/aien-train && cd aien-train/native/neuralese
cat hadamard.om io.om check.om > /tmp/nl1-fixed.om && "$OMC" < /tmp/nl1-fixed.om > /tmp/nl1-fixed && chmod +x /tmp/nl1-fixed
/tmp/nl1-fixed > /tmp/nl1-fixed.out; echo rc=$?                 # rc=0, last line NL1FIX PASS
cmp /tmp/nl1-fixed.out evidence/fixed.stdout && echo SAME      # SAME
cat hadamard.om io.om affine.om learn.om > /tmp/nl1-learn.om && "$OMC" < /tmp/nl1-learn.om > /tmp/nl1-learn && chmod +x /tmp/nl1-learn
sha256sum /tmp/nl1-learn             # ea8aeebe161bd3319a319de2d7cb836c3014a5d1ae887348ee3e5db768ef50bd
/tmp/nl1-learn > /tmp/nl1-learn.out; tail -1 /tmp/nl1-learn.out   # NL1LEARN END, 15175 lines
```

- **Positive case.**
  - The fixed-channel check reproduces `evidence/fixed.stdout` byte for byte.
  - The learning binary has the recorded sha256.
  - Its stream matches `evidence/learned-final.stdout` in every field except the measured host timings: `T` rows and the `encoder_ns`/`decoder_ns` columns of `R` rows (`experiment.json` `result_schema`).
- **Refusal case.** Swap `affine.om` for a mutant in [`mutants/`](native/neuralese/mutants/) and build with `gradientcheck.om` (`cat hadamard.om io.om mutants/gradient-sign.om gradientcheck.om`). It compiles, then exits 61; `update-sign.om` exits 63. The recorded exits are in `evidence/mutants.json`.

The same CPU-only pattern works for Omega LLM itself, with omega-mv `e5b32567`'s omc (sha256 `2c824805…`; see [Build](docs/omegallm/README.md#build)):

- `sh tests/omegallm/build.sh`, then `ollm adamck` prints `A 5 3cd046ce38e38e38 0`.
- The mutant build `--mutant c` exits 41.
- `ollm init v0.ck 256 64 64 4 256 2 16 52 20000 3000` prints `I 119104` and writes 2,858,608 bytes.
- That file cut to 100,000 bytes makes `ollm eval` exit 10.

Training at scale and the chip commands need TinyStories data and an authorized GB10 window. They are outside this recipe.

Layout:
- `native/` first-party `.om` source per experiment (`omegallm`, `neuralese`, `si19`, `omegese45`, …)
- `tests/` build and check scripts for those experiments
- `docs/` contracts and write-ups (`docs/omegallm/`, `docs/si19/`, …); `docs/PLAN.md` streams, directories, branches
- `evidence/` receipts for every measurement
- `docs/history/`, `docs/LESSONS.md` and `docs/physics/` are planned in PLAN.md and live only on their unmerged branches so far

## Human-Directed Agentic Engineering

Development follows Human-Directed Agentic Engineering (HDAE): humans define goals, architecture, constraints, acceptance criteria, and stopping points; agents implement, execute checks, diagnose failures, and revise within those boundaries. Human review retains responsibility for claims, acceptance, and release decisions.

For the documented method and a systems-software case study, see Gregory M. Kurtzer, [*Ginux: Building an Independent Kernel That Runs Linux Userspace through Human-Directed Agentic Engineering* (2026)](https://doi.org/10.5281/zenodo.23682548). This is a development-method citation, not evidence that a training run or earlier experiment has passed.
