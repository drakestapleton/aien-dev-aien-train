# wsplit

Seeded Omega replacement for `make_splits.py` and `make_d.py` in
`evidence/OMEGALLM/wsp-dra187-20261107/`. All generation, parsing, random draws,
JSON formatting, record framing, metadata and SHA-256 execute in Omega.
The program reads the original inputs below, never the committed split outputs:

`/home/drakestapleton/handoffs/tool-omega-20261104`

## Build

Linux AArch64. Pin `omega-mv` to
`e5b32567a7aff3ce594e3254a622a846a6cd190b`:

- `seed/out/omc` SHA-256:
  `2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f`
- `om/sha256/sha256-om2.om` SHA-256:
  `dbf002dd6aa36585632b9d01d98ac3f0bd2fa0f0475082940de53638847994bb`

From the aien-train root, with `OUT` an existing private build directory and `wbuild` built as in
`tools/omegallm/wdrive/README.md`:

```sh
OMEGA_MV=../omega-mv
sha256sum "$OMEGA_MV/seed/out/omc" "$OMEGA_MV/om/sha256/sha256-om2.om"
OMC="$OMEGA_MV/seed/out/omc" CORE=0 wbuild "$OUT/wsplit" "$OMEGA_MV/om/sha256/sha256-om2.om" tools/omegallm/wsplit/wsplit.om
```

wbuild writes every line starting `export fn ` as `fn `, because the output is a program, so SHA's
four `export fn` declarations become `fn`. It also moves the `om2` line and the `layout shactx`
block to the top of `$OUT/wsplit-all.om`. The layout, implementation and constants are unchanged.
wbuild checks omc's sha256, compiles with `taskset -c CORE nice -n 19`, and leaves no output from a
failed compile. On 2026-11-07 (MEASURED) the binary was byte for byte the one from the earlier
`sed 's/^export fn /fn /'` and `cat` route, sha256 `be6f7f0d...f19f`. There is no foreign runtime
dependency.

## Commands

```sh
mkdir -p /tmp/wsplit-output /tmp/wsplit-negative
taskset -c 0 nice -n 19 "$OUT/wsplit" splits /tmp/wsplit-output
taskset -c 0 nice -n 19 "$OUT/wsplit" d /tmp/wsplit-output
taskset -c 0 nice -n 19 "$OUT/wsplit" splits /tmp/wsplit-negative 1
```

`OUTDIR` must exist. Existing `S`, `H`, `G` or `D` output files are overwritten.
`splits` writes `S`, then `H`, then `G`, sharing the used-ID set as the Python
instrument does. `d` preserves the selected source rows' order. Each writes
`X.json`, `X.rec` and `X.meta`. Summary stdout matches the Python instrument:
template/form/exclusion counts for `splits`, then split name, row count, JSON
SHA-256 and record SHA-256. The optional unsigned seed offset (0 to 999999)
is accepted only for `splits`; offset 1 is the negative control, not a new split.

Metadata is ASCII, one newline-terminated row per JSON row:

```text
idx role length kind
```

There is no header. For example, `0 control 4 path`. Role is `target` for
length at least 6 and `control` otherwise. Kind is `word` for G and `path`
for S/H/D. The index is the post-shuffle JSON index.

S/H/D records contain UTF-8 `prompt`, byte 31, UTF-8 `answer`, byte 0.
G records contain only UTF-8 `prompt`, byte 0, matching the original generator.
JSON has Python's one-space indentation, insertion-order keys, ASCII escapes,
lowercase Unicode escape hex and no final newline.

## Exactness and bounds

MT19937 helpers are symbol-renamed copies of the verified `wprobe.om` helpers
at aien-train `72d3377`. Integer seeding uses `init_by_array` with a single
32-bit key word, which covers every seed and offset accepted here. `_randbelow`
uses high-bit `getrandbits` rejection, including rejection for powers of two.
The small-pool `sample(range(1, 10), 2)`, choice, descending shuffle, range draws,
200-attempt pattern fallback, discarded leading-zero draws and the extra loop
Goal draws preserve Python's call order. No float random API is needed.

The tokenizer covers the supplied arrays of objects, their strings (JSON
escapes and UTF-8), integer lengths, and skipped primitive/nested values. Task
and Goal lines are extracted, deduplicated and sorted from inputs, not embedded
as a fixture. Goal digit runs become `{}` before sorted form selection.
Raw `item<digits>` and then `hello<digits>` scanning is over file bytes, not
parsed JSON. The frozen corpus uses ASCII digits; non-ASCII decimal digit
semantics of Python `re` are outside this input subset. Leading-zero strings
remain distinct through numeric value plus digit length. The scanner is
streaming, including matches crossing read boundaries. Hidden entries are
excluded as in Python glob. Source symlinks and unknown directory-entry types
are refused; the observed inputs have neither.

Explicit capacities: each parsed JSON input is smaller than 524288 bytes,
output buffer 524288 bytes, string arena 4194304 bytes, 32767 stored strings,
256 tasks and 256 forms, 1024 rows, 32768 excluded/generated IDs, 18 digits per
raw ID, directory depth 32. Raw scanned JSON files are filtered at the same
strictly-less-than 52428800-byte size limit as Python and are not loaded whole.
The program refuses exhaustion; it does not silently drop input.

Exit codes: 0 success; 2 usage/unsupported seed; 61 capacity; 62 unsupported or
malformed input; 63 random rejection limit; 70 I/O failure. Omega's checked
runtime may also report its standard trap exit statuses.

## ORACLE and acceptance

ORACLE: the existing, independent CPython instruments `make_splits.py` and
`make_d.py`, retained in historical evidence. They are verification references
only, never executed by wsplit or needed to build or run it. CPython's algorithms
are documented by [random.py](https://github.com/python/cpython/blob/v3.12.3/Lib/random.py)
and [_randommodule.c](https://github.com/python/cpython/blob/v3.12.3/Modules/_randommodule.c).
Byte comparison uses `cmp`; SHA-256 can also be checked with `sha256sum`.

The input tree includes actively written evaluation results. A historical H
must not be regenerated or rewritten: its preregistered hashes remain frozen.
The accepted comparison, confirmed by the integrating lane, is current-input
Omega versus current-input Python for all four splits, plus committed S/G/D.
The frozen H discrepancy must be causally accounted for separately, not hidden
by excluding a particular ID in product code or by adding a snapshot mode.

On 2026-11-07, current-input H differed from committed H at indices 31, 61 and
248. The new raw output `src/item1199.om` in
`round41/c9/results/c9b-round40-fam-dev.json` excluded a previously fresh ID.
An ORACLE-only intervention deleting precisely `1199` from the exclusion set
restored both committed H files byte for byte. Product code has no such
intervention. The changed file is a round41 evaluation result, not round40
training data. See the integrating lane's port receipt for timestamps, hashes,
commands, sizes, runtime, metadata checks and the seed-offset negative control.

No compiler, language, host-word, gate or repository-ownership contract changed;
this tool-specific README is the affected guide.

## MT19937 attribution

The MT19937 recurrence and initialization originate with Makoto Matsumoto and
Takuji Nishimura, as retained in CPython's `_randommodule.c`:

Copyright (C) 1997 - 2002, Makoto Matsumoto and Takuji Nishimura,
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice,
   this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.
3. The names of its contributors may not be used to endorse or promote products
   derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
