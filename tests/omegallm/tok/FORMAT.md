# Omega LLM own BPE tokenizer: format OLLMTOK1

This tokenizer belongs to Omega LLM. Its code lives in `native/omegallm/tok/*.om`, it is built with the pinned seeded omc (omega-mv e5b32567), and it learns its merges only from text we choose. It uses no outside tokenizer, vocabulary or model. The older v1 tokenizer, `bpe.om` (`OLLMBPE1`, V ≤ 4096), is a separate thing and is unchanged.

## 1. Token ids

| Ids | Meaning |
|---|---|
| 0 – 255 | the byte with that value |
| 256 | `<\|end\|>`: ends a turn |
| 257 | `<\|system\|>`: starts a system turn |
| 258 | `<\|user\|>`: starts a user turn |
| 259 | `<\|assistant\|>`: starts an assistant turn |
| 260 | `<\|tool_call\|>`: starts a tool call (inside an assistant turn) |
| 261 | `<\|tool_result\|>`: starts a tool result turn |
| 262 | `<\|pad\|>`: padding; carries no text |
| 263 | `<\|doc\|>`: starts a document; separates training documents |
| 264 – 271 | reserved; never valid (decode exits 25, a merge using one is refused) |
| 272 – V−1 | merge k = id − 272, in rank order (lower id merges first) |

`272 ≤ V ≤ 32768`. Token files are u16 little-endian with no header.

## 2. Merges file

All integers are little-endian.

| Offset | Size | Field |
|---|---|---|
| 0 | 8 | magic `OLLMTOK1` |
| 8 | 8 | V |
| 16 | 8 | special id count, always 16 (ids 256 – 271) |
| 24 | 8 | FNV-1a 64 of every byte of the file except bytes 24 – 31 |
| 32 | 4 (V − 272) | merge k: u16 a, u16 b; token 272 + k is a followed by b |

A loader refuses the file with exit 26 when any of these hold:
- the length is below 32 or above 130016;
- the magic is wrong;
- V is outside 272 … 32768;
- the special count is not 16;
- the length is not 32 + 4 (V − 272);
- the checksum differs;
- a pair member is a special or reserved id, or is not a byte or an earlier merge;
- a token would decode to more than 64 bytes;
- a pair appears twice.

FNV-1a catches any single changed byte. The file is integrity-checked, but it is not signed.

## 3. Chunks

Merges never cross a chunk boundary. Each byte belongs to one class:
- **A**: digits, ASCII letters, and every byte ≥ 128, so UTF-8 letters stay whole;
- **W**: 9 – 13 and space;
- **P**: every other byte.

A text is cut left to right. At position i, with E = min(i + 64, n):

1. A space followed by a byte that is not W makes one chunk: the space, then the longest run of the next byte's class.
2. Otherwise the chunk is the longest run of bytes of the class of byte i.
3. A W run of 2 or more bytes that ends with a space, and is followed by a byte that is not W, gives that last space to the next chunk, so `"  hello"` becomes `" "` and `" hello"`.
4. A chunk never runs past E, so no chunk is longer than 64 bytes.

## 4. Encoding and decoding

In each chunk, repeatedly find the present adjacent pair with the lowest merge id and replace every occurrence of it, left to right and without overlap. Stop when no pair is a merge. This gives the same result as applying the merges in rank order.

Decoding writes the bytes of each token. A special id writes its marker's bytes. The round trip `decode(encode(x)) = x` is exact for every byte string in both modes, including invalid UTF-8.

## 5. Training

Training counts chunk types, then repeats V − 272 times:
1. Take the adjacent pair with the largest count over all types, weighted by type count. Break ties by the smallest a, then the smallest b.
2. Record the pair as the next merge.
3. Replace it in every type, left to right and without overlap.

If no pair is left before V is reached, training exits 28 and writes no file. The same text, mode, V and MAXBYTES always give the same file, byte for byte. Texts of 2^33 bytes or more are refused with exit 21.

## 6. Chat format and the injection rule

A conversation is a sequence of turns:

```
<|doc|><|system|>...<|end|><|user|>...<|end|><|assistant|>...<|tool_call|>{json}<|end|><|tool_result|>...<|end|><|assistant|>...<|end|>
```

- In **chat** mode, every exact marker string becomes its special id. Any other text, including near misses such as `<|user` or `<|USER|>`, is ordinary text, and chunks never span a marker.
- In **raw** mode, no special id is ever produced, so marker strings are just bytes.

**Injection rule:** content that did not come from the conversation's own structure must be encoded in raw mode, segment by segment, with the specials inserted by the program that builds the turn. This covers user text, tool output, files and web pages. Then a user cannot forge `<|assistant|>` or `<|tool_result|>`. Chat mode is only for trusted, already-structured text, such as our own training transcripts.

## 7. Program `ollm-tok`

Build it with `sh tests/omegallm/tok/build.sh`. It combines the units `tkcore tkio tkfit tkcli`.

```
ollm-tok toktrain MODE TEXT MERGES V MAXBYTES   -> T V types chunks bytes markers pairs nodes
ollm-tok tokenc MODE MERGES TEXT TOKS           -> E V bytes chunks tokens markers
ollm-tok tokdec MERGES TOKS OUT                 -> D V tokens bytes
ollm-tok tokinfo MERGES                         -> I V merges checksum
```

`MODE` is `raw` or `chat`. A `MAXBYTES` of 0 means the whole text. The merges file is written as `MERGES.tmp`, fsynced, and then renamed over `MERGES`. `tokdec` checks every token before it creates `OUT`.

Exit codes:

| Code | Meaning |
|---|---|
| 2 | usage |
| 21 | a capacity limit was reached, the text is too big, or the token file has an odd length |
| 25 | invalid token |
| 26 | bad merges file |
| 28 | no pair left |
| 70 | I/O error |

Trainer capacities:

| Item | Limit |
|---|---|
| Chunk types | 2,097,152 |
| Pool symbols | 16,777,216 |
| Pairs | 6,000,000 |
| List nodes | 16,777,216 |

`tkcore.om` uses about 1.7 MiB of globals and no host words. A model program can concatenate it and call `tkinit`, `tkload`, `tknext`, `tkencc` and `tkdec1`. The trainer, at about 441 MiB, stays in `ollm-tok` because `ollm` already uses about 954 MiB of the 1 GiB global limit.

## 8. Tests

- `check.sh` compares the program against the Python test oracle `oracle.py`, which is used for verification only. It covers training, encoding, decoding, round trips, specials, determinism, refusals of corrupted files and every exit code.
- `ratio.sh` measures compression on a public-domain sample.
- The fixtures `chat.txt` and `unicode.txt` are synthetic and were written for these tests.
