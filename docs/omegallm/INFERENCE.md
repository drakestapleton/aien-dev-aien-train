# Resident inference and ordered ARM kernels

Inference retains the complete checkpoint's weights and validates every byte,
including optimizer state, without retaining optimizer arrays or training
activations. The original training and scalar `sample` paths remain available.
`samplekv` opts into the inference path. There is no quantization or changed
checkpoint, tokenizer, temperature conversion, random-number draw, or learned
position convention.

The cache computes the final position's logits and retains earlier keys and
values. At a full context-window shift it invalidates the cache and recomputes
the shifted window, because this model's learned positions start at zero.
A rolling cache that retained old positions would change its answers.
`osaminit` and `osamnext` expose one-token progression to resident transports.
Cancellation polls inside inference and invalidates per-request cache state.

`neon.om` uses Omega's ordered `vdot4` primitive to vectorize four independent
output columns. Each column visits inputs in the scalar order with separate
binary64 multiply and add instructions. The scalar kernel remains the oracle.

## Build and reproduce

The original `tests/omegallm/build.sh` retains its historical compiler pins.
The resident builder takes the new compiler pinned in its own script:

```sh
sh tests/omegallm/build-resident.sh NEW_OMC FRESH_OUTPUT neon
sh tests/omegallm/build-resident.sh NEW_OMC OTHER_FRESH_OUTPUT scalar
sh tests/omegallm/inference.sh REFERENCE_OMC FRESH_PARITY_OUTPUT NEW_OMC
python3 tests/omegallm/resident.py RESIDENT REFERENCE CHECKPOINT MERGES
```

The parity gate compares exact binary64 logits and seeded draws across
prefill, decode, window rollover and repeated requests. It checks greedy and
seeded sampled bytes, deliberately stale-cache code, corrupt optimizer bytes,
truncated/overlong checkpoints and wrong compiler pins. The optional new
compiler argument adds ordered NEON parity against the same scalar dump.

The resident protocol is an external test/comparison interface. It loads once,
announces readiness, streams bounded frames, accepts cancellation and the next
request without restart, and exits on input closure. Its lifecycle verifier
checks three startup/shutdown cycles, split UTF-8, request limits and exact
reference output. `MERGES=-` selects the existing byte-tokenizer mode for tiny
fixture checkpoints. Test/build Python and shell are external orchestration;
the inference executable is compiled Omega.

The Aienux HTTP and Omega UI consumer lives in `aien-dev/aienux`, under
`native/omega/allen`. Its guest and Linux comparison server use this same
model code. Model parity is not a claim of Linux-level guest speed; paired
same-machine latency, memory, startup and idle-CPU measurements are separate.
