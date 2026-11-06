# Explore Omega LLM on an Apple Silicon Mac

The existing rung-10 model runs locally on an M2 MacBook Air in an ARM64 Linux
VM using Apple Virtualization.framework. This is local CPU execution, not a
native macOS executable or Apple GPU acceleration. The model was trained on
Spark; inference uses the MacBook only. No new training is claimed.

## Active checkpoint on Drake's MacBook

The browser launchers now expose this checkpoint in the existing llama UI:
`http://127.0.0.1:8098` uses the fast ARM64 Linux guest; the separate
`http://127.0.0.1:8099` experiment uses Aienux's firmware-hosted Omega application
under x86-64 emulation. Open **Omega LLM.command** or **Aienux Omega.command**
in Applications/Omega. Select **Omega-Astra-2026-11-04** or
**Omega-Astra-Aienux**, respectively. The adapter and its limits are documented
in [the UI experiment](../../tools/omegallm-ui/README.md). It is temporary host
C++ compatibility code, not a native Omega macOS runtime. The firmware guest
does model inference without Linux; it is not the standalone Aienux kernel.

At the operator's request, the local `Omega LLM.command` launcher now selects
Astra's November 4 inference experiment: `alpha-950-gain-1000.ck`, installed as
`omega-v2-edited-20261104.ck`. This is the 95% final / 5% midpoint weight edit
from [the weight-edit experiment](WEIGHT-EDIT.md), with final gain 1.00.
The original `omega-v2.ck` is preserved alongside it. The tokenizer is unchanged.
The interactive runner flushes each decoded token and exposes a resident-model
sampling entry point; greedy and seeded samples match the prior runner in
[the parity receipt](../../evidence/OMEGALLM/macbook-ui-20261106/parity.json).
No new training or change to the repository's recommended
training checkpoint is implied.

The edited file's SHA-256 is
`131f7e3f26f5494a9882d8107096d4209651978a5bf35eccb3f953203d1f07d6`.
The Mac and guest copies match. Its one-window local load/evaluation returns
`E 60000 1 1024131 375240`; this smoke check is not a quality benchmark.
The experiment's complete held-out result improved story loss by only
0.016192%, below its 0.1% preference threshold. It did not establish better
arithmetic or reasoning. Edited checkpoints are for inference, not training
continuation with the preserved optimizer state.

Local fixed-prompt checks for this selection are in
`evidence/OMEGALLM/macbook-edited-20261106/`. The edited model still answers
17 + 25 with 12 and describes three apples as five. These probes do not show
a math or extraction improvement. The original results below remain unchanged
for comparison. To reproduce with the active edited model, substitute
`omega-v2-edited-20261104.ck` for `omega-v2.ck` in the commands below.

## Reproduce the original baseline

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
