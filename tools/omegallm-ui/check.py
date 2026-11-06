#!/usr/bin/env python3
"""HTTP test oracle only. Not a model runtime or installation dependency."""
import argparse
import hashlib
import json
import time
import urllib.error
import urllib.request
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument("--port", type=int, choices=(8098, 8099), required=True)
p.add_argument("--output", type=Path, required=True)
a = p.parse_args()
model = "Omega-Astra-Aienux" if a.port == 8099 else "Omega-Astra-2026-11-04"
base = f"http://127.0.0.1:{a.port}"
results = []

def request(path, body=None, headers=None):
    return urllib.request.urlopen(urllib.request.Request(
        base + path, None if body is None else json.dumps(body).encode(),
        {"Content-Type": "application/json", **(headers or {})}), timeout=180)

body = {"model": model, "messages": [{"role": "user", "content":
    "Once upon a time, a little robot found a lost kitten."}],
    "temperature": 0, "seed": 42, "max_tokens": 1, "stream": True}
start = time.monotonic()
text = ""
first = None
done = False
with request("/v1/chat/completions", body) as response:
    for raw in response:
        if not raw.startswith(b"data: "):
            continue
        line = raw[6:].strip()
        if line == b"[DONE]":
            done = True
            break
        part = json.loads(line)["choices"][0]["delta"].get("content", "")
        if part and first is None:
            first = time.monotonic() - start
        text += part
assert text == " The" and done, (text, done)
results.append({"case": "stream-parity", "model": model, "text": text,
    "first_text_seconds": first, "total_seconds": time.monotonic() - start, "pass": True})

for name, payload, headers, expected in [
    ("unknown-model", {"model": "unknown", "messages": []}, {}, 404),
    ("empty-prompt", {"model": model, "messages": []}, {}, 400),
    ("foreign-origin", body, {"Origin": "https://example.invalid"}, 403),
    ("foreign-host", body, {"Host": "example.invalid"}, 403),
    ("tools", {**body, "tools": [{}]}, {}, 400),
]:
    try:
        with request("/v1/chat/completions", payload, headers) as r:
            status = r.status
    except urllib.error.HTTPError as e:
        status = e.code
    assert status == expected, (name, status, expected)
    results.append({"case": name, "status": status, "pass": True})

with request("/") as r:
    actual = r.read()
with urllib.request.urlopen(urllib.request.Request("http://127.0.0.1:8097/",
        headers={"Accept-Encoding": "gzip"}), timeout=10) as r:
    reference = r.read()
assert actual == reference, "UI asset proxy changed the upstream bytes"
results.append({"case": "ui-assets", "sha256": hashlib.sha256(actual).hexdigest(), "pass": True})

with request("/v1/chat/completions", {"model": "build-mac/qwen.gguf", "messages": [
        {"role": "user", "content": "What is 17 plus 25? Answer with only the number."}],
        "temperature": 0, "max_tokens": 8, "stream": False}) as r:
    answer = json.load(r)["choices"][0]["message"]["content"]
assert "42" in answer, answer
results.append({"case": "qwen-route", "text": answer, "pass": True})
a.output.parent.mkdir(parents=True, exist_ok=True)
a.output.write_text(json.dumps({"port": a.port, "results": results}, indent=2) + "\n")
print(f"PASS port={a.port} checks={len(results)}")
