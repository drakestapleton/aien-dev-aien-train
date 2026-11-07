# DRA-146 personal-model pilot: tooling evidence (synthetic data only)

Branch feat/dra146-eval. Host: DGX Spark aarch64, `taskset -c 2 nice -n 10`. omc: omega-mv e5b32567 seed,
sha256 2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f. No private text, data or checkpoint
is in this repository; the private pre-registration is sealed by sha256 outside it (public copy:
docs/personal/PREREG-dra146.md).

| file | what | status |
|---|---|---|
| mask/host-check.txt | tests/personal/mask-check.sh: loss mask on the CPU (exact zero contribution, all-ones = no mask bit-identical, unmasked train/grad bit-identical to origin/main, refusals, deterministic resume, negative control mutant z caught) | TESTED, MASK_PASS (25 PASS) |
| mask/gpu-smoke-20261107T001921Z.txt | tests/personal/mask-gpu.sh in one exclusive spark-window lease: masked gcmp CPU vs GB10 agree (3 batches), mutant j (chip ignores the mask) caught, unmasked gcmp numbers and gtrainb checkpoint bit-identical to origin/main, 20-step masked gtrainb at the rung-10 shape rc 0 with loss falling | EXERCISED; one FAIL: tiny-shape masked gtrainb exit 84 (not yet diagnosed) |
| harness/harness-check.txt | tests/personal/harness-check.sh: peval split/rx/leak/shingle/jtext/pack/agg and the three-arm harness end to end with a stub sampler, exact aggregate | TESTED, HARNESS_PASS |
| harness/rx-oracle.txt | peval rx against Python re.search (test oracle only) on synthetic cases incl. phone/email/secret/refusal patterns | TESTED, 0 disagreements |

Python appears only as the rx test oracle (tests/personal/rx-oracle.py). The product path (mask, packer,
splitter, scorers, leak detector, aggregator) is native Omega: native/omegallm/{data,model,adam,cli}.om,
native/omegallm/gpu/{gr,gg}.om, native/personal/{mpack,peval}.om.
