# wscore: score `wprobe gen` output against a DRA-187 split

`wscore` is an Omega (`.om`) tool. It reads the text that `wprobe gen` wrote for every row of a split, decides which rows pass, and prints pass counts by role and by length plus the result of each row. It replaces the Python `score.py` that was in `evidence/OMEGALLM/wsp-dra187-20261107/`, and it gives the same results (see Verification).

A row passes under these rules, the same as round40's `check_answer`:

- **path rows** (S, H and D splits): the text is cut at the first `\nDone.` and stripped of Python whitespace. If both the text and the answer parse as JSON, the row passes when the two values are equal as Python values. Otherwise the row passes when the two strings are equal.
- **word rows** (G split): the first line of the text, stripped of Python whitespace, must equal the answer.

## Build

With the pinned omc (omega-mv `e5b32567`, sha256 `2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f`) and `wbuild` built as in `tools/omegallm/wdrive/README.md`:

```sh
OMC=omc CORE=0 wbuild OUT/wscore tools/omegallm/wscore/wscore.om
```

wscore is one standalone unit, so `OUT/wscore-all.om` is `wscore.om` unchanged and the binary is the one plain `omc < wscore.om` gives (MEASURED 2026-11-07, sha256 `8da6494e...207e`). wbuild prints `BUILD_OK`; on a compile error it exits 1 with omc's code in `BUILD_FAIL omc rc=N` and leaves no binary.

## Usage

```sh
wscore SPLIT.rec SPLIT.meta GEN.out
```

- **SPLIT.rec**
  - Each record ends with byte 0.
  - A record is either `PROMPT 0x1f ANSWER 0x00`, or a G prompt alone. The committed `G.rec` holds prompts only.
  - For a prompt alone, the answer is derived. The prompt must read exactly `Task: Write Omega that prints WORD followed by a newline.\nAnswer:\n`, and the answer is then `text msg "WORD\n"`, with a backslash and `n` and no newline character. This is the rule in `make_splits.py` `gsplit`, and all 96 committed G rows follow it (MEASURED). Such a row must have kind `word`.
- **SPLIT.meta**
  - One line per record: `idx role length kind`.
  - `idx` is the line number, counting from 0.
  - `role` is `target` or `control`.
  - `length` is a decimal below 4096.
  - `kind` is `path` or `word`.
  - `tools/omegallm/wsplit` writes this file beside the `.rec`.
- **GEN.out**
  - The output of `wprobe gen`. Lines end at `\n`, `\r\n` or `\r`.
  - Only lines starting with `G ` are read. Each is `G idx<TAB>text`.
  - A later line for the same idx replaces an earlier one.
  - The text escapes are `\t \n \r \" \\ \xHH`. Bytes 128 and above are UTF-8, and invalid UTF-8 becomes U+FFFD the same way Python `errors='replace'` does.

## Output

```
target 4/72  L6 4/24 L7 0/24 L8 0/24
control 24/24  L3 8/8 L4 8/8 L5 8/8
P 0 1
P 1 0
...
```

- The first two lines are byte for byte what `score.py` printed.
- After them comes one `P idx 0|1` line per row, in idx order. This takes the place of the per-row `pass_` field in score.py's OUT.json.
- `score.py` also copied the raw text into OUT.json. `wscore` does not; the text is already in GEN.out.

## Exit codes

| code | meaning |
|---|---|
| 0 | scored |
| 2 | usage: not exactly three arguments |
| 3 | a file could not be opened or read |
| 4 | a capacity limit was exceeded (see Limits) |
| 5 | malformed SPLIT.rec, SPLIT.meta or G line key; meta and rec row counts differ; a derived G answer on a `path` row |
| 6 | the G lines do not cover idx 0 to rows-1 exactly |
| 7 | a bad escape in any G line, including a line a later one replaces |
| 8 | JSON nesting deeper than 9990 |
| 9 | writing stdout failed |

## Limits

- Each of SPLIT.rec and GEN.out may be up to 16 MiB. SPLIT.meta may be up to 4 MiB.
- There may be at most 262144 rows.
- A record or a GEN line may be at most 999989 bytes.
- GEN.out may have at most 999989 lines.
- One decoded text may be at most 999989 code points.
- At most 2097152 JSON values and 2097152 pooled digits or code points may be held for one row.
- JSON nesting may be at most 9990 levels. Inside the scorer's `check_answer`, CPython 3.12.3 raises `RecursionError` on some inputs from 9991 levels on, and on all of them from 9994 (MEASURED). Python then stops with a traceback rather than giving an answer, so `wscore` refuses at the point where Python stops being reliable.

The loop bounds come from the pinned omc: `while ... bound N` accepts N up to 999999 (1000000 gives error 8), and a global array may hold at most 16777216 elements (more gives error 23). Both were MEASURED with the pin.

## Where wscore is stricter than score.py

On these inputs score.py either crashed or accepted something malformed. `wscore` exits with a nonzero code instead of guessing:

- A G line key that Python `int()` accepts but is not plain digits, such as `+3`, ` 3` or `3_0`, exits 5.
- `\x` followed by fewer than two hex digits, or by `+` or a space, which `int(..., 16)` accepts, exits 7.
- A meta or rec file that does not match the split shape exits 5. score.py read SPLIT.json and never saw these files.

JSON parsing follows Python 3.12.3 `json.loads` exactly:

- `NaN`, `Infinity` and `-Infinity` are accepted.
- Duplicate keys keep the last value.
- Lone surrogates are kept, and `\ud83d\ude00` pairs combine.
- An int with more than 4300 digits is a parse error, so the strings are compared instead.

Number equality follows Python. Floats are correctly rounded binary64 (ties to even, with subnormals and overflow to infinity). An int equals a float only when the float holds exactly that value. `true` equals `1` and `1.0`. A top-level `NaN` does not equal itself, but `[NaN]` equals `[NaN]`, because `json` reuses one NaN object.

## Verification (MEASURED 2026-11-07, wscore.om sha256 `4aecb288...e881`, binary sha256 `8da6494e...207e`)

- **Gate: PASS.** Run on the 15 `S-*.out` arm outputs in `~/work/wsp/run/arms/`. For every file, the two summary lines equal the original `score.py` stdout (taken from git HEAD) and the ORACLE's stdout. The P vector equals `pass_` in score.py's OUT.json and in the `.score.json` that runarms wrote beside each output.
- **All four splits: PASS.** Synthetic GEN outputs for G, S, H and D: the summary and every row match the ORACLE.
- **JSON and number fuzz: PASS.** 7 seeds of 3783 rows each, 26481 rows in total, with 0 row differences from the ORACLE. They cover:
  - random JSON with duplicate keys, escapes, surrogates, NaN and Infinity;
  - fixed edge cases;
  - 1500 float pairs per seed at half-ulp boundaries, including subnormals and values near the largest double;
  - 600 int and float pairs between 2^53 and 2^70.
- **Raw UTF-8 cases: PASS.** 23 cases of invalid UTF-8, `\xHH` of 0x80 and above, and non-ASCII whitespace in the strip all match the ORACLE.
- **Negative control: PASS.** In `S-E1-k2-a2000.out`, changing `"path"` to `"paht"` in passing row 0 changed `P 0 1` to `P 0 0` and control from 24/24 to 23/24 (L4 8/8 to 7/8). The ORACLE agrees.
- **Exit codes: PASS** for 2, 3, 5, 6, 7, 8 and 9, including a bad escape on a line that a later line replaces (7) and a `+3` key (5).
- **Runtime:** one S scoring run took 0.00 s wall time and 1472 KB maximum resident memory.

## ORACLE

`evidence/OMEGALLM/wsp-dra187-20261107/oracle_score.py` is an ORACLE: a Python reference used only to check `wscore`. It is not the scorer.

- It imports `check_answer` from round40 `repair.py` instead of keeping its own copy. That file is `/home/drakestapleton/handoffs/tool-omega-20261104/round40/repair.py`, sha256 `df025230...d206`.
- It takes the same arguments as score.py: `python3 oracle_score.py SPLIT.json GEN.out [OUT.json]`.
