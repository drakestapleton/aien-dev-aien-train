#!/usr/bin/env python3
"""ORACLE for wpcheck. A digest calculator only; it never decides PASS or FAIL.

wpcheck (Omega) writes a request file and runs `/usr/bin/python3 wporacle.py REQUEST`.
Each request line produces exactly one output line, in order. The path is always the
last field and may contain spaces.

  sha OFF LEN PATH            hex SHA-256 (hashlib) of LEN bytes at OFF; LEN `-` means to end.
  f32 PATH                    hex SHA-256 of the little-endian IEEE f32 casts of the CK02
                              parameter words (count P = u64 at 96, words from byte 120);
                              a finite value too large for f32 casts to a same-signed infinity.
  f32ne A B STRIDE COUNT PATH decimal count of k < COUNT where the f32 casts of the u64 at
                              A + k*STRIDE and at B + k*STRIDE differ.

It is independent of the product: it shares no code with wpatch or wpcheck, and nothing in
the build or in wpatch calls it. Any malformed request raises and exits nonzero.
"""
import hashlib
import math
import mmap
import struct
import sys

U = struct.Struct('<Q')
F = struct.Struct('<d')


def f32bits(bits):
    x = F.unpack(U.pack(bits))[0]
    try:
        return struct.pack('<f', x)
    except OverflowError:
        return struct.pack('<f', math.copysign(math.inf, x))


def mapped(path):
    with open(path, 'rb') as f:
        return mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)


def sha(off, n, path):
    with mapped(path) as m:
        end = len(m) if n == '-' else int(off) + int(n)
        if int(off) > end or end > len(m):
            raise ValueError('range outside file: ' + path)
        h = hashlib.sha256()
        for o in range(int(off), end, 1 << 20):
            h.update(m[o:min(o + (1 << 20), end)])
        return h.hexdigest()


def f32(path):
    with mapped(path) as m:
        p = U.unpack_from(m, 96)[0]
        h = hashlib.sha256()
        for o in range(120, 120 + 8 * p, 8 * 8192):
            end = min(o + 8 * 8192, 120 + 8 * p)
            h.update(b''.join(f32bits(U.unpack_from(m, j)[0]) for j in range(o, end, 8)))
        return h.hexdigest()


def f32ne(a, b, stride, count, path):
    with mapped(path) as m:
        a, b, stride, count = int(a), int(b), int(stride), int(count)
        return str(sum(f32bits(U.unpack_from(m, a + k * stride)[0])
                       != f32bits(U.unpack_from(m, b + k * stride)[0])
                       for k in range(count)))


def main():
    with open(sys.argv[1], encoding='utf-8') as req:
        for line in req.read().splitlines():
            op = line.split(' ', 1)[0]
            if op == 'sha':
                _, off, n, path = line.split(' ', 3)
                print(sha(off, n, path))
            elif op == 'f32':
                print(f32(line.split(' ', 1)[1]))
            elif op == 'f32ne':
                _, a, b, stride, count, path = line.split(' ', 5)
                print(f32ne(a, b, stride, count, path))
            else:
                raise ValueError('unknown request: ' + line)


if __name__ == '__main__':
    main()
