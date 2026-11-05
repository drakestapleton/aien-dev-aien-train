"""Independent external test instrument for the Omega checkpoint editor."""
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile

build = Path(sys.argv[1]).resolve()
tool = build / 'weight-edit'
ollm = build / 'ollm'

def run(*args, expected=0):
    p = subprocess.run([str(x) for x in args], capture_output=True)
    assert p.returncode == expected, (str(args[0]), p.returncode, expected, p.stderr.decode())

def values(path):
    b = path.read_bytes()
    h = struct.unpack('<15Q', b[:120])
    return b, h, struct.unpack('<' + 'd' * (h[12] * 3), b[120:])

with tempfile.TemporaryDirectory(prefix='weight-edit-check-') as tmp:
    r = Path(tmp)
    old, new = r/'old.ck', r/'new.ck'
    run(ollm, 'init', old, 256, 8, 16, 2, 32, 2, 2, 1, 10, 3000, 1)
    new.write_bytes(old.read_bytes())
    (r/'train.bin').write_bytes(b'abc abcd abcde\0' * 200)
    run(ollm, 'train', new, r/'train.bin', 2, 1)
    run(tool, old, new, r/'identity.ck', 1000, 1000)
    assert new.read_bytes() == (r/'identity.ck').read_bytes()
    oldb, oldh, oldv = values(old)
    newb, newh, newv = values(new)
    p, d = newh[12], newh[3]
    for alpha, gain in [(500, 1000), (900, 1000), (1100, 1000), (1000, 950), (1050, 1100)]:
        out = r/f'a{alpha}-g{gain}.ck'
        run(tool, old, new, out, alpha, gain)
        b, h, v = values(out)
        assert h[:-1] == newh[:-1]
        assert b[120 + p*8:] == newb[120 + p*8:], 'optimizer state changed'
        expected = [newv[i] + (alpha/1000.0-1.0)*(newv[i]-oldv[i]) for i in range(p)]
        for i in range(p-d, p):
            expected[i] *= gain/1000.0
        assert tuple(expected) == v[:p], 'weight calculation differs from independent reference'
        # Production loader checks payload checksum and file structure.
        run(ollm, 'eval', out, r/'train.bin', 1)
    run(tool, old, new, new, 1100, 1000, expected=52)
    assert new.read_bytes() == newb
    run(tool, old, new, r/'bad-range.ck', 1201, 1000, expected=51)
    run(tool, old, new, r/'bad-low-range.ck', 499, 1000, expected=51)
    corrupt = bytearray(oldb)
    corrupt[-1] ^= 1
    (r/'corrupt.ck').write_bytes(corrupt)
    run(tool, r/'corrupt.ck', new, r/'bad-hash.ck', 1000, 1000, expected=14)
    run(ollm, 'init', r/'wrong.ck', 256, 8, 16, 2, 32, 1, 2, 1, 10, 3000, 1)
    run(tool, r/'wrong.ck', new, r/'bad-shape.ck', 1000, 1000, expected=53)
    assert not any((r/name).exists() for name in ('bad-range.ck','bad-low-range.ck','bad-hash.ck','bad-shape.ck'))
    assert old.read_bytes() == oldb
    print(json.dumps({'identity': 'PASS', 'five_weight_reference_cases': 'PASS',
                      'checksum_loads': 'PASS', 'optimizer_bytes_preserved': 'PASS',
                      'overwrite_range_hash_shape_refusals': 'PASS', 'originals_unchanged': 'PASS'}))
