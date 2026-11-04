#!/bin/sh
# rung 3 overnight training: config b (V4096 T128 D192 H6 F768 L4 B40, G=20), K=20 workers on all 20 cores, nice 19.
# Resumable: ck.bin is saved every 250 steps and train resumes from its step; logs append.
cd "$(dirname "$0")/.."
s=$(date -u +%s)
date -u +%FT%TZ >> v1-night/start.txt
v1-night/ollm train v1-night/ck.bin v1-data/train.tok 9000 250 20 >> v1-night/train.txt 2>> v1-night/train.err
echo "rc=$?" >> v1-night/train.rc
e=$(date -u +%s)
echo "wall_s=$((e-s))" >> v1-night/train.rc
date -u +%FT%TZ >> v1-night/end.txt
