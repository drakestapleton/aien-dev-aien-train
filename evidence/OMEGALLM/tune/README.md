# ollm tune host evidence

Source commit: `b4187dae0954825de7488d811b7884419e1a0f44`. Base: train main `77cffb6`.
Host: Linux 7.0.0-1019-nvidia aarch64 (DGX Spark host CPU), CPU only. No GPU ran.
Build: `OMC=<pinned omc> sh tests/omegallm/build.sh` with omc sha256
`2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f`:
`ollm` sha256 `f3005415ecc48239ac19f498e24a27e386abb7661318f7dcc4fa74b9b0cd1559`
(source `c83edec0`). `TARGET=gb10` also builds: `ollm-gb10` `bf87a3ae` (source `d90f9abd`), not run.
Command: `OLLM=<ollm> OMC=<pinned omc> sh tests/omegallm/tune-check.sh`, exit 0, output in `check.txt`
(MEASURED, 2026-11-06, about 43 s).

Data is the repository `LICENSE` as V 256 bytes on the v0 shape (P 119104): a smoke task for the
command, not a quality result. The checks cover: training past TOTAL makes no step (the gap this
closes), tune keeps the weights (eval loss and bpb equal), resets the step, zeroes Adam m and v,
fine-tuning then lowers eval loss (4.901318 to 4.816743 nats after 20 steps), resume is
bit-identical, tune is deterministic, bad TOTAL, argument count and a truncated checkpoint are
refused with no output, and a build with the moment reset removed is caught.
