#!/usr/bin/env python3
"""External protocol/parity verifier. Never part of the inference executable."""
import argparse
import os
import select
import struct
import subprocess


def exact(stream, count):
    result = bytearray()
    while len(result) < count:
        if not select.select([stream], [], [], 30)[0]:
            raise AssertionError("resident response timed out")
        piece = os.read(stream.fileno(), count - len(result))
        if not piece:
            raise AssertionError("resident closed mid-frame")
        result.extend(piece)
    return bytes(result)


def frame(stream):
    header = exact(stream, 5)
    count = struct.unpack("<I", header[1:])[0]
    assert count <= 4096, ("unbounded frame", count)
    return chr(header[0]), exact(stream, count)


def request(prompt, tokens=20, temperature=700, seed=42):
    return b"G" + struct.pack("<IIII", len(prompt), tokens, temperature, seed) + prompt


def response(stream):
    result = bytearray()
    while True:
        tag, body = frame(stream)
        if tag == "D":
            result.extend(body)
        else:
            assert not body
            return tag, bytes(result)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("resident")
    parser.add_argument("reference")
    parser.add_argument("checkpoint")
    parser.add_argument("merges")
    args = parser.parse_args()
    prompt = b"A little robot."
    oracle = subprocess.check_output([
        args.reference, "sample", args.checkpoint, "42", "20", "700",
        prompt.decode(), args.merges,
    ], timeout=120)
    for startup in range(3):
        proc = subprocess.Popen([args.resident, args.checkpoint, args.merges],
                                stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, bufsize=0)
        try:
            assert frame(proc.stdout) == ("R", b"")
            for _ in range(2):
                proc.stdin.write(request(prompt))
                assert response(proc.stdout) == ("E", oracle)
            # Cancellation and the next request are queued together. The next request must
            # survive the cancelled request's transport poll and must not inherit its cache.
            proc.stdin.write(request(prompt, 128) + b"C" + request(prompt))
            assert response(proc.stdout)[0] == "C"
            assert response(proc.stdout) == ("E", oracle)
            # Bounds errors must leave framing intact for an immediately following request.
            for tokens, temperature in [(0, 700), (129, 700), (20, 2001)]:
                proc.stdin.write(request(prompt, tokens, temperature) + request(prompt))
                assert response(proc.stdout) == ("X", b"")
                assert response(proc.stdout) == ("E", oracle)
            # Split a multi-byte UTF-8 sequence over writes. Transport reads must preserve bytes.
            unicode_prompt = "A cat named 雪.".encode()
            wire = request(unicode_prompt)
            for byte in wire:
                proc.stdin.write(bytes([byte]))
            expected = subprocess.check_output([
                args.reference, "sample", args.checkpoint, "42", "20", "700",
                unicode_prompt.decode(), args.merges,
            ], timeout=120)
            assert response(proc.stdout) == ("E", expected)
            proc.stdin.write(request(b"a" * 4000, 128, 0))
            assert response(proc.stdout)[0] == "E"
            proc.stdin.close()
            assert proc.wait(timeout=5) == 0, proc.stderr.read()
        finally:
            if proc.poll() is None:
                proc.kill()
            proc.wait()
        print(f"PASS startup {startup + 1}: parity, cancel/next, bounds, split UTF-8, limits, shutdown")


if __name__ == "__main__":
    main()
