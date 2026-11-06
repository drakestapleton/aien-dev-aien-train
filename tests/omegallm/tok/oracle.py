#!/usr/bin/env python3
"""Test oracle for the own BPE tokenizer ollm-tok (tests/omegallm/tok/FORMAT.md).

Verification only, never part of the build: a naive, independent reading of FORMAT.md in
Python 3 standard library, with the same command line, stdout lines, output files and exit
codes as the .om program, so check.sh can compare the two byte for byte. It recounts every pair
after every merge, so it is meant for texts of a few hundred KB.

    oracle.py toktrain MODE TEXT MERGES V MAXBYTES   -> T V types chunks bytes markers
    oracle.py tokenc MODE MERGES TEXT TOKS           -> E V bytes chunks tokens markers
    oracle.py tokdec MERGES TOKS OUT                 -> D V tokens bytes
    oracle.py tokinfo MERGES                         -> I V merges fnv
    oracle.py mkbad KIND IN OUT                      -> rehashed merges file with one bad pair
    oracle.py gen BYTES SEED OUT                     -> synthetic test text (word salad)

The training line of ollm-tok carries two more fields (pairs, list nodes) that depend on its data
structures; check.sh compares the first six fields only.
"""

import random
import struct
import sys

FIRST = 272
VMAX = 32768
MARKS = [b"<|end|>", b"<|system|>", b"<|user|>", b"<|assistant|>", b"<|tool_call|>",
         b"<|tool_result|>", b"<|pad|>", b"<|doc|>"]
MAXCAP = 130016
FNV0 = 14695981039346656037
FNVP = 1099511628211
M64 = (1 << 64) - 1


def cls(c):
    if 48 <= c <= 57 or 65 <= c <= 90 or 97 <= c <= 122 or c >= 128:
        return 1
    if 9 <= c <= 13 or c == 32:
        return 2
    return 0


CL = [cls(c) for c in range(256)]


def clen(t, i, n):
    """FORMAT.md section 3: length of the chunk at t[i] in a text ending at n."""
    e = min(i + 64, n)
    k = CL[t[i]]
    j = i + 1
    if t[i] == 32 and j < n and CL[t[j]] != 2:
        k = CL[t[j]]
        j += 1
    while j < e and CL[t[j]] == k:
        j += 1
    if k == 2 and j < n and CL[t[j]] != 2 and j - i >= 2 and t[j - 1] == 32:
        j -= 1
    return j - i


def mark_at(t, i):
    for k, m in enumerate(MARKS):
        if t.startswith(m, i):
            return 256 + k
    return 0


def pieces(t, chat):
    """yields (special id, b'') for a marker and (0, chunk) for a text chunk"""
    n = len(t)
    i = 0
    nxt = -1
    while i < n:
        if chat:
            m = mark_at(t, i)
            if m:
                yield m, b""
                i += len(MARKS[m - 256])
                continue
            if nxt <= i:
                nxt = n
                j = t.find(b"<|", i + 1)
                while j >= 0:
                    if mark_at(t, j):
                        nxt = j
                        break
                    j = t.find(b"<|", j + 1)
            e = nxt
        else:
            e = n
        l = clen(t, i, e)
        yield 0, t[i:i + l]
        i += l


def fnv(buf):
    h = FNV0
    for c in buf[:24] + buf[32:]:
        h = ((h ^ c) * FNVP) & M64
    return h


def seal(v, pairs):
    body = b"".join(struct.pack("<HH", a, b) for a, b in pairs)
    buf = bytearray(b"OLLMTOK1" + struct.pack("<QQQ", v, 16, 0) + body)
    buf[24:32] = struct.pack("<Q", fnv(bytes(buf)))
    return bytes(buf)


def load(path):
    """the merges of a checked OLLMTOK1 file: (V, pairs); exit 26 on any fault"""
    buf = open(path, "rb").read(131072)
    n = len(buf)
    if n < 32 or n > MAXCAP or buf[:8] != b"OLLMTOK1":
        sys.exit(26)
    v, ns, h = struct.unpack("<QQQ", buf[8:32])
    if v < FIRST or v > VMAX or ns != 16 or n != 32 + 4 * (v - FIRST) or fnv(buf) != h:
        sys.exit(26)
    ln = [1] * 256 + [0] * 16
    for k, m in enumerate(MARKS):
        ln[256 + k] = len(m)
    pairs = []
    seen = set()
    for k in range(v - FIRST):
        a, b = struct.unpack("<HH", buf[32 + 4 * k:36 + 4 * k])
        t = FIRST + k
        for x in (a, b):
            if not (x < 256 or FIRST <= x < t):
                sys.exit(26)
        if ln[a] + ln[b] > 64 or (a, b) in seen:
            sys.exit(26)
        seen.add((a, b))
        pairs.append((a, b))
        ln.append(ln[a] + ln[b])
    return v, pairs


def replace(seq, a, b, t):
    out = []
    j = 0
    while j < len(seq):
        if j + 1 < len(seq) and seq[j] == a and seq[j + 1] == b:
            out.append(t)
            j += 2
        else:
            out.append(seq[j])
            j += 1
    return out


def mode(s):
    if s == "raw":
        return False
    if s == "chat":
        return True
    sys.exit(2)


def num(s):
    if not (1 <= len(s) <= 19) or not s.isdigit():
        sys.exit(2)
    return int(s)


def train(argv):
    if len(argv) != 5:
        sys.exit(2)
    chat = mode(argv[0])
    v = num(argv[3])
    if v < FIRST or v > VMAX:
        sys.exit(2)
    lim = num(argv[4])
    t = open(argv[1], "rb").read()
    if lim:
        t = t[:lim]
    if len(t) >= 1 << 33:
        sys.exit(21)
    types = {}
    chunks = marks = 0
    for sp, c in pieces(t, chat):
        if sp:
            marks += 1
        else:
            chunks += 1
            types[c] = types.get(c, 0) + 1
    words = [[list(c), n] for c, n in types.items()]
    pairs = []
    for k in range(v - FIRST):
        cnt = {}
        for seq, n in words:
            for j in range(len(seq) - 1):
                p = (seq[j], seq[j + 1])
                cnt[p] = cnt.get(p, 0) + n
        best = None
        for p, n in cnt.items():
            if best is None or (n, -p[0], -p[1]) > (cnt[best], -best[0], -best[1]):
                best = p
        if best is None:
            sys.exit(28)
        tok = FIRST + k
        pairs.append(best)
        for w in words:
            if len(w[0]) > 1:
                w[0] = replace(w[0], best[0], best[1], tok)
    with open(argv[2], "wb") as f:
        f.write(seal(v, pairs))
    print("T %d %d %d %d %d" % (v, len(types), chunks, len(t), marks))


def encode_chunk(c, rank, pairs):
    seq = list(c)
    while len(seq) > 1:
        best = min(rank.get((seq[j], seq[j + 1]), 65535) for j in range(len(seq) - 1))
        if best == 65535:
            break
        a, b = pairs[best - FIRST]
        seq = replace(seq, a, b, best)
    return seq


def enc(argv):
    if len(argv) != 4:
        sys.exit(2)
    chat = mode(argv[0])
    v, pairs = load(argv[1])
    rank = {p: FIRST + k for k, p in enumerate(pairs)}
    t = open(argv[2], "rb").read()
    out = []
    memo = {}
    chunks = marks = 0
    for sp, c in pieces(t, chat):
        if sp:
            marks += 1
            out.append(sp)
        else:
            chunks += 1
            if c not in memo:
                memo[c] = encode_chunk(c, rank, pairs)
            out.extend(memo[c])
    with open(argv[3], "wb") as f:
        f.write(struct.pack("<%dH" % len(out), *out))
    print("E %d %d %d %d %d" % (v, len(t), chunks, len(out), marks))


def dec(argv):
    if len(argv) != 3:
        sys.exit(2)
    v, pairs = load(argv[0])
    raw = open(argv[1], "rb").read()
    if len(raw) % 2:
        sys.exit(21)
    toks = struct.unpack("<%dH" % (len(raw) // 2), raw)
    for t in toks:
        if t >= v or 256 + len(MARKS) <= t < FIRST:
            sys.exit(25)
    memo = {}

    def bytes_of(t):
        if t < 256:
            return bytes([t])
        if t < FIRST:
            return MARKS[t - 256]
        if t not in memo:
            a, b = pairs[t - FIRST]
            memo[t] = bytes_of(a) + bytes_of(b)
        return memo[t]

    out = b"".join(bytes_of(t) for t in toks)
    with open(argv[2], "wb") as f:
        f.write(out)
    print("D %d %d %d" % (v, len(toks), len(out)))


def info(argv):
    if len(argv) != 1:
        sys.exit(2)
    v, _ = load(argv[0])
    h = struct.unpack("<Q", open(argv[0], "rb").read(32)[24:32])[0]
    print("I %d %d %d" % (v, v - FIRST, h))


def mkbad(argv):
    """KIND special|reserved|forward|self|dup|long: one bad pair, rehashed so only it is wrong"""
    kind, src, dst = argv
    buf = open(src, "rb").read()
    v = struct.unpack("<Q", buf[8:16])[0]
    pairs = [struct.unpack("<HH", buf[32 + 4 * k:36 + 4 * k]) for k in range(v - FIRST)]
    last = FIRST + len(pairs) - 1
    if kind == "special":
        pairs[-1] = (259, 97)
    elif kind == "reserved":
        pairs[-1] = (97, 270)
    elif kind == "forward":
        pairs[-1] = (97, last + 1)
    elif kind == "self":
        pairs[-1] = (last, 97)
    elif kind == "dup":
        pairs[-1] = pairs[0]
    elif kind == "long":
        # merges whose decoded lengths double: 2, 4, 8, 16, 32, 64, then 128 (> 64)
        chain = [(97, 97)] + [(FIRST + k, FIRST + k) for k in range(6)]
        if len(pairs) < len(chain):
            sys.exit(2)
        pairs = chain + pairs[len(chain):]
    else:
        sys.exit(2)
    with open(dst, "wb") as f:
        f.write(seal(v, pairs))


def gen(argv):
    """deterministic synthetic text: words, digits, punctuation, runs of white space, UTF-8 and
    near misses of the chat markers; no private and no outside text"""
    n, seed = int(argv[0]), int(argv[1])
    rnd = random.Random(seed)
    syl = ["ka", "lo", "mi", "ra", "sen", "to", "vu", "el", "an", "the", "ing", "er", "qu",
           "st", "ch", "o", "a", "i"]
    uni = ["\u00e9t\u00e9", "na\u00efve", "\u00fcber", "\u0436\u0438\u0437\u043d\u044c",
           "\u03bb\u03cc\u03b3\u03bf\u03c2", "\u65e5\u672c\u8a9e", "\u0645\u0631\u062d\u0628\u0627",
           "\U0001f600", "\u2603"]
    words = ["".join(rnd.choice(syl) for _ in range(rnd.randint(1, 4))) for _ in range(400)]
    out = []
    size = 0
    while size < n:
        r = rnd.random()
        if r < 0.80:
            w = rnd.choice(words)
            if rnd.random() < 0.1:
                w = w.capitalize()
        elif r < 0.85:
            w = rnd.choice(uni)
        elif r < 0.90:
            w = str(rnd.randint(0, 99999))
        elif r < 0.97:
            w = rnd.choice([".", ",", "!", "?", "...", "--", "\"", "'s", "(", ")", ":", ";"])
        else:
            w = rnd.choice(["<|", "|>", "<|user", "<|end>", "<||>", "<x|end|>"])
        sp = rnd.choice([" ", " ", " ", " ", " ", "\n", "  ", "\n\n", "\t", " \n ", "    "])
        piece = (w + sp).encode()
        out.append(piece)
        size += len(piece)
    with open(argv[2], "wb") as f:
        f.write(b"".join(out)[:n])


def main():
    cmds = {"toktrain": train, "tokenc": enc, "tokdec": dec, "tokinfo": info,
            "mkbad": mkbad, "gen": gen}
    if len(sys.argv) < 2 or sys.argv[1] not in cmds:
        sys.exit(2)
    cmds[sys.argv[1]](sys.argv[2:])


if __name__ == "__main__":
    main()
