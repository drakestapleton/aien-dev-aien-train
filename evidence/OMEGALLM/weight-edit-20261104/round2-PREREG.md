# Round 2: blend full-length BF16 and f32 siblings

Round 1 found only a marginal aggregate improvement (0.0162 percent on its fresh final set), below the predefined 0.1 percent preference. Its final block checks continue; no original was replaced. This second, separate experiment uses different stories and a different direction in weight space, not further tuning against round 1 final scores.

Baseline remains the unmodified rung-10 BF16 ck60000. OLD is rung-8 f32 ck60000. Both have the same initial checkpoint, data order, seed, dimensions and schedule according to the original run records. SHA256s are captured in selection-locked.json and commands retain all runs. No use of another initial seed or permutation alignment is implied.

Selection set and final set are drawn after story index 20000 in held-v1.bin and exclude any normalized text from either first-round partition, the training corpus, and published held text. New partitions have 2048 calibration and 4096 final stories. No second-round score has been read when this file is written.

Fixed candidates: 100, 90, 75 and 50 percent BF16 checkpoint weights, with the remainder from the f32 sibling. No confidence scaling. Choose the minimum calibration loss, with ties preferring the unmodified baseline. Lock before opening final evaluation. No further rounds or parameter search after this study. Require at least 0.1 percent lower final loss for a substantive upgrade, no more than 0.2 percent regression on published held text, matching CPU/GPU check within 10 micronats, and report the 16 paired final blocks. Otherwise retain the original recommendation and report small or failed edits honestly.

Use the updated bounded Omega editor (alpha 500..1200, gain 800..1200); five independent reference cases and refusal tests pass. This only widens the allowed blend, not the calculation. Record all original and tool hashes. Output checkpoints are inference candidates; their preserved optimizer moments are not a tested continuation state. No model service or harness changes.
