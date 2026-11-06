# Explore Omega LLM on an Apple Silicon Mac

The existing rung-10 model runs locally on an M2 MacBook Air in an ARM64 Linux
VM using Apple Virtualization.framework. This is local CPU execution, not a
native macOS executable or Apple GPU acceleration. The model was trained on
Spark; inference uses the MacBook only. No new training is claimed.

## Reproduce

Build the current CPU runner on Linux ARM64 with the pinned compiler using
`OMC=/path/to/pinned/omc OUT=/path/to/output sh tests/omegallm/build.sh`.
The Mac run used source commit `77cffb6d6698f59b0644552bcbfe0b639da94abe`.
Copy that runner, the rung-10 step-60000 checkpoint, its `merges4096.bin`, and
`held.tok` to the Mac. Keep weights outside the repository. Their exact hashes
are in `evidence/OMEGALLM/macbook-20261106/pins.json`.

With Lima 2.2.0 installed, create a private VM with no host-directory mounts:

```sh
limactl start --name=omega-llm --vm-type=vz --cpus=2 --memory=2 --disk=8 \
  --containerd=none --mount-none --tty=false template:debian
limactl shell omega-llm mkdir -p omega
# Copy the four files with limactl copy to the guest user's omega directory.
# In that directory, run:
./ollm adamck
./ollm eval omega-v2.ck held.tok 1 merges4096.bin
./ollm sample omega-v2.ck 42 32 800 "Once upon a time, a little robot" merges4096.bin
```

The selected Debian image was trixie ARM64 `20260712-2537`. On the checked
window both the rebuilt CPU runner and the historical reference printed
`E 60000 1 1022938 374803`. A truncated checkpoint was refused with exit 10.
This one-window comparison does not repeat the full original held-out gate.

## Capability boundary

The three fixed exploratory prompts and raw output are retained in
`evidence/OMEGALLM/macbook-20261106/`. The model continues the robot/kitten story
coherently, but answers the arithmetic question incorrectly and invents the
number of apples in an extraction task. It is not an instruction-tuned assistant
and does not yet replace a general small chat model.

The `qwen` fields record the initial default-device reference. The separate
`*-omega-backend.json` files record Qwen2.5-0.5B with the verified Omega device
explicitly selected. Backend execution was checked independently in ggml-omega
with a deliberately wrong addition kernel. Different tokenizers mean raw tokens
per second should not be used as a direct cross-model speed ratio. Wall times
include guest command startup on the Omega LLM side. These are single samples,
not repeated performance or capability qualification.

Stop the VM when finished with `limactl stop omega-llm`. It stores model files on
its private disk and does not mount the Mac home directory.
