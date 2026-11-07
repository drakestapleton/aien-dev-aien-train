#!/bin/sh
# Test stub for tests/personal/harness.sh SAMPLER: CK SEED NTOK TEMP PROMPTFILE. Answers come from
# $STUBANS/good|bad/<sha256 of the Task line>: good when the prompt holds a Memory block or CK is "ckc".
k=$(sed -n 's/^Task: //p' "$5" | head -n 1 | tr -d '\n' | sha256sum | cut -d' ' -f1)
m=bad; grep -q '^Memory:$' "$5" && m=good; [ "$1" = ckc ] && m=good
cat "$STUBANS/$m/$k" 2> /dev/null
