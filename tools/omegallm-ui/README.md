# Experimental local llama UI adapter

This explicitly enabled **C++ host compatibility adapter** reuses llama.cpp's
existing web UI and translates its chat requests into Omega's text sampling.
Model inference remains in the `.om` runner. It provides no new model training,
instruction tuning, or improvement in arithmetic.

`--enable-local-ui-bridge` serves the ARM64 Linux guest on loopback port 8098.
Adding `--aienux` serves the Aienux firmware experiment on loopback port 8099,
without invoking Lima for that model. Both proxy the existing Qwen/Omega server
and UI assets on port 8097. These are local development endpoints, not a remote
service or a replacement for llama.cpp's complete API.

The Linux runner is `ollm-ui` in the `omega-llm` guest's `~/omega` directory.
It uses `omega-v2-edited-20261104.ck` and `merges4096.bin`. The firmware runner
is the opt-in `native/omega/allen/local-model.om` application in `aien-dev/aienux`.
The Mac's `Applications/Omega/Aienux` directory holds its private QEMU disk,
firmware, process identifier and Unix sockets. The Aienux launcher verifies the
installed image digests before starting it.

## Private voice model

On the Linux port, the adapter also lists `Omega-Drake-Voice`. It is a private
fine-tune of the rung-10 checkpoint, made with `ollm tune` and `gtrainb`, and it
uses the same `merges4096.bin`. Its checkpoint, `drake-voice.ck`, exists only
in the guest's `~/omega` directory and is never committed. For this model the
adapter turns user messages into `them: ` lines and assistant messages into
`me: ` lines, one line per text bubble, and skips system messages. It keeps
about the last 700 bytes at a line boundary and ends the prompt with `me:`. It
holds back the generated text and returns Drake's reply only, which ends at the
first blank line or line that does not start with `me:`. Later `me:` lines
become new lines in the same reply, so a streamed reply arrives as one chunk.
It runs `ollm-kv samplekv`, the cached sampler from `feat/astra-inference-cache`
(aarch64 build, omc 2c824805). On Drake's MacBook guest it gave the same bytes as
`sample`, in about 2.2 s instead of 21 s for 32 tokens. Sampling stops as soon as the reply is
complete. Aienux does not offer this model.

## Build and operate

```sh
sh tools/omegallm-ui/build.sh /private/output
/private/output/omega-ui-bridge --enable-local-ui-bridge
# Or, in a separate process:
/private/output/omega-ui-bridge --enable-local-ui-bridge --aienux
```

The dependency revision and digests are pinned in `build.sh`. cpp-httplib and
nlohmann/json are MIT licensed, vendored by upstream llama.cpp; preserve their
notices. Drake's installation runs both adapters as user LaunchAgents, with
explicit HOME and PATH. The launchers restart those agents after Stop Omega.
This avoids tying the server's lifetime to a short-lived terminal command.

Linux accepts at most 4000 prompt bytes, 128 output tokens, and a 120-second
runner deadline. Aienux accepts one printable ASCII prompt of at most 159
bytes, caps each reply at eight tokens, and has a 1200-second deadline including
boot. Start a new chat for each Aienux prompt. The checkpoint has only a
256-token context window. Message text is joined as plain text, not transformed
into an instruction chat template.

Only one Omega request is admitted per adapter. Linux cancellation terminates
only that request's guest process group. Firmware cancellation stops this
experiment's private VM through its private monitor socket; reopen **Aienux
Omega.command** afterward. Its read-only checkpoint disk is preserved. This
is slower than keeping a reusable cancelled context but prevents stale output
from being mistaken for the next response. Qwen requests use the existing
server separately. After a successful firmware request the adapter pauses its VM;
the next request resumes it. This prevents UEFI idle polling from consuming a
Mac CPU core. Tools offered by the UI are ignored and the model answers in text; a request
that forces a tool call, structured output and multimodal inputs are refused.

## Evidence and harness boundary

`evidence/OMEGALLM/macbook-ui-20261106` records Linux sampling parity, streamed
output, request validation and final endpoint checks. Aienux records its EFI
image hash, native-reference parity, invalid-frame and truncated-checkpoint
refusals, Mac HTTP output and cancellation in its own
`evidence/OMEGA-LOCAL-MODEL/macbook-20261106` directory. Browser assets were
checked over HTTP; browser clicks and rendering were not automated.

The Omega harness was used for compiler pins, reuse, explicit boundaries,
positive execution and negative controls. **Full harness compliance is not
claimed:** its first-party language rule requires an Omega successor and a
compiler PR for last-resort host code. This adapter's intended successor is an
Omega HTTP/JSON and local-process/Unix-socket runtime on macOS. No such compiler
PR is provided by this experiment. The existing omega-bridge macOS path rejects
Linux host words; its scalar Mach-O support does not supply these runtime APIs.
That migration remains open work, rather than being disguised as generated
code or inferred from model inference running in Omega.
