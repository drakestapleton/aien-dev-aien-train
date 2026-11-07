"""Independent external check of `wprobe save` (instrument only; the tool is wprobe.om).
python3 check.py BUILD_DIR   (BUILD_DIR holds ollm and wprobe)
On a small `ollm init` checkpoint: a head-gain edit (kind 1) and a neuron edit (kind 2) change exactly
the documented rows by the documented factor and nothing else; f32 rounding (kind 5) equals Python's
struct round trip; header fields other than the payload FNV and the whole optimizer state are kept;
refusals: OUT exists 63, activation or decoding hook 2, a parameter over 1e6 64, bad hook 2."""
import struct, subprocess, sys, tempfile
from pathlib import Path

b = Path(sys.argv[1]).resolve()
ollm, wp = b / 'ollm', b / 'wprobe'

def run(*a, rc=0):
    p = subprocess.run([str(x) for x in a], capture_output=True)
    assert p.returncode == rc, (a, p.returncode, rc, p.stderr[-300:])

def load(p):
    x = p.read_bytes()
    h = struct.unpack('<15Q', x[:120])
    n = h[12]
    return x, h, struct.unpack('<%dd' % (3 * n), x[120:120 + 24 * n])

def fnv(data):
    v = 0xcbf29ce484222325
    for c in data:
        v = ((v ^ c) * 0x100000001b3) & 0xffffffffffffffff
    return v

def layout(h):
    V, T, D, H, F, L = h[1], h[2], h[3], h[4], h[5], h[6]
    lstr = 4 * D * D + 2 * D * F + 2 * D
    lay0 = V * D + T * D
    wo = lambda l: lay0 + l * lstr + D + 3 * D * D
    w2 = lambda l: lay0 + l * lstr + D + 4 * D * D + D + D * F
    return D, H, F, wo, w2

ok = 0
with tempfile.TemporaryDirectory(prefix='wprobe-check-') as t:
    t = Path(t)
    base = t / 'base.ck'
    run(ollm, 'init', base, 256, 8, 16, 2, 32, 2, 2, 1, 10, 3000, 1)
    (t / 'tr.bin').write_bytes(b'abc abcd abcde\0' * 200)
    run(ollm, 'train', base, t / 'tr.bin', 2, 1)
    bx, bh, bv = load(base)
    n = bh[12]
    D, H, F, wo, w2 = layout(bh)
    E = D // H
    out = t / 'e1.ck'
    run(wp, 'save', base, out, 1, 1, 1, 1500, 2, 0, 7, 250)
    ox, oh, ov = load(out)
    assert oh[:14] == bh[:14], 'header changed'
    assert oh[14] == fnv(ox[120:]), 'FNV of the written payload'
    assert ov[n:] == bv[n:], 'optimizer state changed'
    rows = set(range(wo(1) + E * D, wo(1) + 2 * E * D))
    rows2 = set(range(w2(0) + 7 * D, w2(0) + 8 * D))
    for i in range(n):
        want = bv[i] * 1.5 if i in rows else bv[i] * 0.25 if i in rows2 else bv[i]
        assert ov[i] == want, (i, ov[i], want)
    ok += 1
    out5 = t / 'f32.ck'
    run(wp, 'save', base, out5, 5, 0, 0, 0)
    _, _, fv = load(out5)
    assert all(fv[i] == struct.unpack('<f', struct.pack('<f', bv[i]))[0] for i in range(n)), 'f32 rounding'
    assert sum(fv[i] != bv[i] for i in range(n)) > 0
    ok += 1
    run(wp, 'save', base, out, 1, 1, 1, 1500, rc=63)
    run(wp, 'save', base, t / 'a3.ck', 3, 1, 1, 1500, rc=2)
    run(wp, 'save', base, t / 'a4.ck', 4, 0, 46, 1000, rc=2)
    run(wp, 'save', base, t / 'bad.ck', 1, 2, 0, 1000, rc=2)
    assert not (t / 'a3.ck').exists() and not (t / 'a4.ck').exists() and not (t / 'bad.ck').exists()
    big = bytearray(bx)
    struct.pack_into('<d', big, 120 + 8 * 5, 2.0e6)
    struct.pack_into('<Q', big, 112, fnv(bytes(big[120:])))
    (t / 'big.ck').write_bytes(bytes(big))
    run(wp, 'save', t / 'big.ck', t / 'big-out.ck', 1, 0, 0, 1000, rc=64)
    assert not (t / 'big-out.ck').exists()
    ok += 6
print('WPROBE_SAVE_CHECK PASS', ok, 'cases')
