# PR 79 review repair receipt

This records the review repair after `ca047de8e449dac95ae8cbfe1eaeb8c1cd93ffac`.
Earlier receipts are retained unchanged. `review-before.json` records reproductions
against the earlier binary. `review-build.log` and `review-small.jsonl` describe
the repaired candidate.

Candidate binary SHA-256:
`bf993a780c7421cc2cd23d42fef5692135e9bd339f19a90059d4ef7f17be0847`.

| Finding | Reproduced | Evidence and change |
| --- | --- | --- |
| Real oracle checked self-consistency, not the requested edit | Yes | A different finite-value patch passed product verify and both old hash comparisons while differing from the requested output. `requested_output` now builds the expectation directly from BASE plus the requested bits and policy resets. `compare_requested` compares every byte. Real SHA/f32 expectations come from that independent file, not from the manifest. |
| Admission omitted each metadata field's 16 MiB ceiling | Yes | The old binary accepted a transport-name manifest with 16,777,217 params bytes, exit 0. Admission now checks both field lengths and exits 57 before parsing text. Tests cover params and rationale with validate, show and apply; rejected apply creates no output. |
| README link needs another parent traversal | No | Resolving the existing `../../../docs/omegallm/WSP-PATCH.md` from the README directory reaches the existing repository document. The receipt records the resolved path and existence. The link is intentionally unchanged. |
| Checkbind manifest-replacement limitation unclear | Yes, documentation gap | README and the format document now state directly that checkbind takes no manifest argument, never rereads it, and cannot detect a replaced manifest. |

## Small acceptance and new controls

```text
OUT=/home/drakestapleton/work/wsp/wpatch-build CORE=0 sh tools/omegallm/wpatch/build.sh
exit 0

taskset -c 0 nice -n 19 python3 tools/omegallm/wpatch/check.py \
 --build /home/drakestapleton/work/wsp/wpatch-build \
 --work /tmp/wpatch-review-kvpuocsc/small
exit 0; 702 assertions PASS, 108 commands, zero failures
```

The independent-oracle mutant is constructed by Python: one finite new value is
changed, the expected checkpoint is rebuilt, and the manifest's output, tensor,
f32 and entry hashes and canonical filename are recomputed. Product verify
accepts it, exit 0. The requested-byte oracle reports FAIL with
`negative_control: true`, and the enclosing negative-control assertion passes.
The normal outputs pass the same byte comparator for all optimizer policies.
This demonstrates that a self-consistent manifest cannot define oracle success.

A previously absent negative case runs on the small `/tmp` fixture: an invalid
UTF-8 byte in a transport-name manifest is refused with exit 31. This case is
also retained in check.py. Oversized params and rationale both return exit 57.
All subprocess exit codes are asserted and retained in review-small.jsonl.

Only the owned wpatch crumb was retained from regeneration. Exact pre-command
snapshots of unrelated generated crumbs were restored; review-crumb.log records
that operation. The parent-directory crumb remains the integrator's scope.
No native source, runtime, GPU, deployed checkpoint or historical receipt was
changed. Host CPU checks are not quality improvement or deployment evidence.

## Locked round40 acceptance

The requested serialized command completed with exit 0:

```sh
flock -w 3600 -o /home/drakestapleton/handoffs/hive/queen/pool-19.lock \
 taskset -c 19 nice -n 10 python3 tools/omegallm/wpatch/check.py \
 --build /home/drakestapleton/work/wsp/wpatch-build \
 --work /home/drakestapleton/work/wsp/ck/wpatch-review-20261107 \
 --real /home/drakestapleton/.local/share/omega-tool-model/round40/model.ck
```

`review-real.jsonl`: 24 assertions PASS, six commands, zero failures. Every byte
of the applied checkpoint equals the independent expected checkpoint built from
BASE plus the requested ten edits and policy-2 resets. Complete checkpoint and
f32 hashes also match independently derived expectations. Product verify reports
`PASS f32_surviving=10 changed=10`. Revert and the unchanged source both hash to
`7c7b5b5260f2d9453b6076b64e7f23e88341d96498584f2dfaa229c31ad2e346`.

IMPLEMENTED and host-CPU EXERCISED. GPU qualification, model-quality improvement,
merge and deployment remain NOT_RUN.
