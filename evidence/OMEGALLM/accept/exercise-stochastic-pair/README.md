run.sh with REPEATS=2 against the ref stub on :18298 (SPLITS="dev test" PUBLIC=0, runner 8c4fb0cb): exercises the
t0 arm, the stochastic arms s1 and s2 (temperature 0.7, seeds 1 and 2: the stub ignores both, so the pairs are all
concordant; protocol only, NOT capability), thresholds-stochastic.tsv and `accept pair`. pair-synthetic.txt
checks the paired counts and the exact McNemar p on hand-made rows (p re-computed in Wolfram).
