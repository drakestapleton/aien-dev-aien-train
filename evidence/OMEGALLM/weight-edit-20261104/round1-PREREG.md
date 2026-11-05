# Direct weight adjustment, 2026-11-04

Operator-authorized direct weight experiment.

Baseline is rung-10 BF16 ck60000, sha256 a53ced7265818c8f6197449315e9ca4082721665022fec4f81d4538e8d6c2d0f. Earlier point is rung-10 ck30000. Originals never overwritten. Native Omega editor implements current + (alpha-1)*(current-old), then scales the final RMS gain by s. Optimizer state remains byte-preserved but must not be used for continuation without a separate decision. All candidates are inference experiments.

Calibration and final data are selected from held-v1.bin. data-audit.json records selection and normalized training-overlap exclusion. Final stories were not used for choosing changes. Original published held.tok is an additional regression check, not the optimization target.

Fixed search: stage 1 alpha = 0.90, 0.95, 1.00 (baseline), 1.05, 1.10, s=1. Stage 2 at the stage-1 winner: s=0.90,0.95,1.00,1.05,1.10. Minimize calibration next-token loss; ties prefer the smaller change. Keep all failures and measurements. No further search after opening final results. If any candidate loses on final or regresses the published held loss by more than 0.2 percent, do not promote it. Prefer at least 0.1 percent relative final improvement; report smaller gains as inconclusive. Also compare baseline and selected candidate over 16 contiguous equal-window final blocks, preserving the one-token boundary overlap. No claims about reasoning, knowledge, or general assistant quality.

Evaluation uses the unchanged rung-10 GPU binary 54fb8233c62a13c0b3bac13a38dd5b583943e9e9097342baaa57fc22db2ceb49, normal f32 geval. Before candidate evaluation, reproduce baseline published E=1204466 and baseline CPU-vs-GPU score on the first calibration window. One shared GPU window, no speed claims. Exact commands, return codes, data/model hashes, and results retained. No changes to the shared model service, harness, or deployment.
