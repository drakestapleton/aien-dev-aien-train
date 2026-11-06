#!/usr/bin/env python3
"""Referee for `ollm serve` (DRA-119, native/omegallm/serve.om).

Usage: serve-check.py PORT OLLM CK MERGES
Talks to an `ollm serve` already listening on 127.0.0.1:PORT and prints one line per check,
`PASS name detail` or `FAIL name detail`, then `SUMMARY pass=N fail=M`; exit 1 on any FAIL.
The content oracle is the same binary's `sample` command (the CLI's sampler, cmdsamp) on the
interim template, decoded with Python's UTF-8 decoder (errors="replace", the maximal-subpart
U+FFFD practice that serve.om follows).
"""
import http.client
import json
import socket
import subprocess
import sys
import time

PORT, OLLM, CK, MERGES = int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
HOST = "127.0.0.1"
results = []


def check(name, ok, detail=""):
    results.append(ok)
    print(("PASS" if ok else "FAIL"), name, detail, flush=True)


def call(method, path, body=None, raw=None, timeout=600):
    c = http.client.HTTPConnection(HOST, PORT, timeout=timeout)
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    hdr = {"Content-Type": "application/json", "Authorization": "Bearer "} if data is not None else {}
    t0 = time.monotonic()
    c.request(method, path, body=data, headers=hdr)
    r = c.getresponse()
    out = r.read()
    dt = time.monotonic() - t0
    ctype = r.getheader("Content-Type", "")
    c.close()
    return r.status, ctype, out, dt


def template(msgs):
    return "".join(f"{m['role']}: {m.get('content') or ''}\n" for m in msgs) + "assistant: "


def oracle(msgs, seed, n, tm):
    p = subprocess.run([OLLM, "sample", CK, str(seed), str(n), str(tm), template(msgs), MERGES],
                       capture_output=True, check=True)
    return p.stdout.decode("utf-8", errors="replace")


def err_code(out):
    try:
        e = json.loads(out)["error"]
        return e["code"], e["message"], e["type"]
    except Exception as x:  # noqa: BLE001 - any shape error is a FAIL
        return None, repr(x), None


def sse(out):
    events, done = [], False
    for line in out.decode().split("\n"):
        if not line.startswith("data: "):
            continue
        d = line[6:]
        if d == "[DONE]":
            done = True
            continue
        events.append(json.loads(d))
    return events, done


# --- positive -------------------------------------------------------------------------------
st, ct, out, _ = call("GET", "/health")
h = json.loads(out) if st == 200 else {}
check("health", st == 200 and h.get("status") == "ok" and h.get("in_flight") == 0, f"{st} {out!r}")

st, ct, out, _ = call("GET", "/v1/models")
ids = [m["id"] for m in json.loads(out).get("data", [])] if st == 200 else []
check("models", st == 200 and ids == ["ollm"] and ct.startswith("application/json"), f"{st} {ids}")

msgs = [{"role": "user", "content": "What is Omega?"}]
for tm, seed, n in ((0, 7, 12), (800, 7, 12)):
    req = {"model": "ollm", "messages": msgs, "max_tokens": n, "temperature": tm / 1000, "seed": seed}
    st, ct, out, dt = call("POST", "/v1/chat/completions", req)
    j = json.loads(out) if st == 200 else {}
    ch = (j.get("choices") or [{}])[0]
    u = j.get("usage", {})
    content = ch.get("message", {}).get("content")
    want = oracle(msgs, seed, n, tm)
    ok = (st == 200 and j.get("object") == "chat.completion" and ch.get("finish_reason") in ("stop", "length")
          and ch["message"]["role"] == "assistant" and u.get("total_tokens") == u.get("prompt_tokens", 0) + u.get("completion_tokens", 0)
          and 1 <= u.get("completion_tokens", 0) <= n and content == want)
    check(f"chat_json_t{tm}", ok, f"{st} usage={u} finish={ch.get('finish_reason')} s={dt:.2f} content={content!r} oracle={want!r}")

    req.update(stream=True, stream_options={"include_usage": True})
    st, ct, out, dt = call("POST", "/v1/chat/completions", req)
    ev, done = sse(out) if st == 200 else ([], False)
    deltas = [e["choices"][0]["delta"] for e in ev if e.get("choices")]
    text = "".join(d.get("content", "") for d in deltas)
    fins = [e["choices"][0].get("finish_reason") for e in ev if e.get("choices")]
    usage = [e["usage"] for e in ev if e.get("usage")]
    ok = (st == 200 and ct.startswith("text/event-stream") and done and deltas and deltas[0].get("role") == "assistant"
          and all(e.get("object") == "chat.completion.chunk" for e in ev) and fins[-1] == ch.get("finish_reason")
          and all(f is None for f in fins[:-1]) and text == content and usage == [u] and ev[-1].get("choices") == [])
    check(f"chat_sse_t{tm}", ok, f"{st} events={len(ev)} done={done} usage={usage} text={text!r}")

# allen-chat's body shapes (/opt/allen-chat/allen_chat.py): system + user, tools, tool_choice none
ac = {"model": "omega", "messages": [{"role": "system", "content": "Be brief."}, {"role": "user", "content": "hi"}],
      "max_tokens": 4, "temperature": 0.3, "stream": False,
      "tools": [{"type": "function", "function": {"name": "x", "parameters": {"type": "object"}}}], "tool_choice": "none"}
st, ct, out, _ = call("POST", "/v1/chat/completions", ac)
j = json.loads(out) if st == 200 else {}
check("allen_chat_shape", st == 200 and j["choices"][0]["finish_reason"] in ("stop", "length") and "tool_calls" not in j["choices"][0]["message"], f"{st} {out[:200]!r}")

# --- negative controls ------------------------------------------------------------------------
long_text = " ".join(f"word{i} omega{i * 7}" for i in range(300))[:3800]
st, ct, out, _ = call("POST", "/v1/chat/completions", {"messages": [{"role": "user", "content": long_text}], "max_tokens": 4})
code, msg, typ = err_code(out)
check("refuse_context", st == 400 and code == "context_length_exceeded" and "context window is 256" in msg, f"{st} {code} {msg!r}")

st, ct, out, _ = call("POST", "/v1/chat/completions", {"messages": [{"role": "user", "content": "x" * 4100}]})
code, msg, typ = err_code(out)
check("refuse_template_bytes", st == 400 and code == "invalid_request" and "4000" in msg, f"{st} {code} {msg!r}")

for name, raw in (("refuse_bad_json", b"{\"messages\": [}"), ("refuse_not_object", b"[1]"),
                  ("refuse_trailing", b"{\"messages\":[{\"role\":\"user\",\"content\":\"a\"}]} x")):
    st, ct, out, _ = call("POST", "/v1/chat/completions", raw=raw)
    code, msg, typ = err_code(out)
    check(name, st == 400 and typ == "invalid_request_error", f"{st} {code} {msg!r}")

bad = [("refuse_empty_messages", {"messages": []}),
       ("refuse_array_content", {"messages": [{"role": "user", "content": [{"type": "text", "text": "a"}]}]}),
       ("refuse_no_role", {"messages": [{"content": "a"}]}),
       ("refuse_neg_temp", {"messages": msgs, "temperature": -1}),
       ("refuse_hot_temp", {"messages": msgs, "temperature": 2.5}),
       ("refuse_zero_max", {"messages": msgs, "max_tokens": 0}),
       ("refuse_n2", {"messages": msgs, "n": 2}),
       ("refuse_stream_str", {"messages": msgs, "stream": "yes"})]
for name, body in bad:
    st, ct, out, _ = call("POST", "/v1/chat/completions", body)
    code, msg, typ = err_code(out)
    check(name, st == 400 and code == "invalid_request", f"{st} {code} {msg!r}")

st, ct, out, _ = call("POST", "/v1/chat/completions", raw=b"{\"messages\":[{\"role\":\"user\",\"content\":\"a\"}],\"temperature\":1e-3}")
code, msg, typ = err_code(out)
check("refuse_exp_temp", st == 400 and code == "invalid_request" and "temperature" in msg, f"{st} {code} {msg!r}")

st, ct, out, _ = call("GET", "/v1/nope")
check("refuse_404", st == 404 and err_code(out)[0] == "not_found", f"{st} {out!r}")
st, ct, out, _ = call("GET", "/v1/chat/completions")
check("refuse_405", st == 405 and err_code(out)[0] == "method_not_allowed", f"{st} {out!r}")

s = socket.create_connection((HOST, PORT), timeout=30)
s.sendall(b"POST /v1/chat/completions HTTP/1.1\r\nHost: x\r\nContent-Type: application/json\r\nContent-Length: 1000000\r\n\r\n")
resp = b""
while True:
    b = s.recv(65536)
    if not b:
        break
    resp += b
s.close()
check("refuse_413", resp.startswith(b"HTTP/1.1 413") and b"request_too_large" in resp, f"{resp[:120]!r}")

# One request per connection: a client that keeps its connection open (allen-chat pools one)
# must not hold the serial listener; the next client is answered at once.
held = http.client.HTTPConnection(HOST, PORT, timeout=30)
held.request("GET", "/health")
r = held.getresponse()
r.read()
conn_hdr = (r.getheader("Connection") or "").lower()
t0 = time.monotonic()
st, ct, out, _ = call("GET", "/health", timeout=5)
dt = time.monotonic() - t0
held.close()
check("held_conn_not_blocking", conn_hdr == "close" and st == 200 and dt < 2,
      f"Connection={conn_hdr!r} next={st} in {dt:.3f}s")

# A connection that never sends a head is dropped after the 10 s head deadline.
silent = socket.create_connection((HOST, PORT), timeout=30)
t0 = time.monotonic()
st, ct, out, _ = call("GET", "/health", timeout=30)
dt = time.monotonic() - t0
silent.close()
check("silent_conn_dropped", st == 200 and 8 < dt < 15, f"next={st} after {dt:.3f}s")

st, ct, out, _ = call("GET", "/health")
check("alive_after_negatives", st == 200, f"{st}")

fails = results.count(False)
print(f"SUMMARY pass={results.count(True)} fail={fails}", flush=True)
sys.exit(1 if fails else 0)
