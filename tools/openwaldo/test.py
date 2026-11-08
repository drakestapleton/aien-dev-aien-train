"""Host oracle and negative controls, never a training-data generator."""
import hashlib
import json
import pathlib
import subprocess
import sys

binary, fixture = map(pathlib.Path, sys.argv[1:])
raw = fixture.read_bytes()
record = json.loads(raw)

def run(data, mode="import"):
    return subprocess.run([str(binary), mode], input=data, capture_output=True, timeout=10)

def encode(obj):
    return (json.dumps(obj, separators=(",", ":")) + "\n").encode()

for mode in ("import", "export"):
    p = run(raw, mode)
    assert p.returncode == 0 and p.stdout == raw, (mode, p)
p = run(raw, "extract")
assert p.returncode == 0 and p.stdout == record["text"].encode()
assert hashlib.sha256(p.stdout).hexdigest() == record["sha256"]
# Alternate escaping and unknown future metadata survive without reserialization.
alternate = dict(record, future={"unicode": "λ", "integer": 9007199254740993})
alternate_raw = encode(alternate)
assert run(alternate_raw).stdout == alternate_raw
assert run(alternate_raw).returncode == 0
controls = {
    "bad-hash": encode(dict(record, sha256="0" * 64)),
    "uppercase-hash": encode(dict(record, sha256=record["sha256"].upper())),
    "missing-source": encode({k:v for k,v in record.items() if k != "source"}),
    "empty-license": encode(dict(record, license="")),
    "conversation": encode(dict(record, kind="conversation")),
    "eval-kind": encode(dict(record, kind="evaluation")),
    "invalid-json": b'{"sha256":}\n',
    "duplicate-key": raw[:-2] + b',"kind":"pretrain"}\n',
    "escaped-duplicate": raw[:-2] + b',"k\\u0069nd":"pretrain"}\n',
    "missing-newline": raw.rstrip(b"\n"),
    "second-record": raw + raw,
    "empty": b"",
    "over-limit": b" " * 16384,
    "invalid-utf8": raw[:-2] + b',"x":"\xff"}\n',
    "array-root": b'[]\n',
}
for name, data in controls.items():
    for mode in ("import", "export", "extract"):
        p = run(data, mode)
        assert p.returncode != 0 and not p.stdout, (name, mode, p)
print("PASS exact import/export, extraction, unknown metadata, SHA256 oracle")
print(f"PASS {len(controls)} refusal inputs across three modes; no output on refusal")
