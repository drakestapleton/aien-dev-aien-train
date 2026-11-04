#!/usr/bin/env python3
"""Omega LLM v0 referee (aien-train#52).

Python 3 standard library only. Implements docs/omegallm/CONTRACT.md independently of the .om
product and cross-checks the `ollm` binary against it. Verification only; never part of the build.

Usage: see tests/omegallm/ORACLE.md.
"""

import hashlib
import contextlib
import json
import math
import os
import random
import shutil
import struct
import subprocess
import sys
import tempfile
import time
from collections import Counter
from operator import mul

M64 = (1 << 64) - 1
GOLDEN = 0x9E3779B97F4A7C15
EPS_RMS = 1e-5
INIT_SCALE = 0.034641016151377546  # Wolfram: N[0.02 Sqrt[3]] -> 0.034641016151377546
BETA1, BETA2, ADAM_EPS = 0.9, 0.99, 1e-8
FNV_OFFSET, FNV_PRIME = 0xCBF29CE484222325, 0x100000001B3
MAXS = {"V": 256, "T": 64, "D": 64, "H": 8, "F": 256, "L": 4, "B": 16}
SMALL = dict(V=256, T=8, D=16, H=2, F=32, L=2, B=2)
V0 = dict(V=256, T=64, D=64, H=4, F=256, L=2, B=16)
SEP = b"<|endoftext|>"

# Cross-check tolerance (see ORACLE.md "Tolerance"). Each entry error is
# |a-b| / max(|b|, FLOOR_FRAC * maxabs(tensor of b)), and must be <= RTOL.
RTOL = 1e-9
FLOOR_FRAC = 1e-3



@contextlib.contextmanager
def scratch():
    """A temporary directory, under $OLLM_TMP when it is set. The path is made relative to the
    current directory there, so receipts that log commands name no absolute (private) path."""
    base = os.environ.get("OLLM_TMP")
    if not base:
        with tempfile.TemporaryDirectory() as d:
            yield d
        return
    os.makedirs(base, exist_ok=True)
    d = os.path.relpath(tempfile.mkdtemp(dir=base))
    try:
        yield d
    finally:
        shutil.rmtree(d)

# ---------------------------------------------------------------- integers and hashes

def splitmix64(x):
    z = (x + GOLDEN) & M64
    z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & M64
    z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & M64
    return z ^ (z >> 31)


def fnv1a64(data):
    h = FNV_OFFSET
    for c in data:
        h = ((h ^ c) * FNV_PRIME) & M64
    return h


def f2bits(x):
    return struct.unpack("<Q", struct.pack("<d", x))[0]


def bits2f(u):
    return struct.unpack("<d", struct.pack("<Q", u))[0]


def micro(x):
    """round(x * 10^6), half away from zero (agreed reading A7)."""
    v = x * 1e6
    q = math.trunc(v)
    if abs(v - q) >= 0.5:
        q += 1 if v > 0 else -1
    return int(q)


# ---------------------------------------------------------------- layout

def tensor_specs(c):
    V, T, D, F, L = c["V"], c["T"], c["D"], c["F"], c["L"]
    specs = [("wte", V, D), ("wpe", T, D)]
    for l in range(L):
        specs += [("g1.%d" % l, 1, D), ("wq.%d" % l, D, D), ("wk.%d" % l, D, D),
                  ("wv.%d" % l, D, D), ("wo.%d" % l, D, D), ("g2.%d" % l, 1, D),
                  ("w1.%d" % l, D, F), ("w2.%d" % l, F, D)]
    specs.append(("gf", 1, D))
    out, off = [], 0
    for name, r, cc in specs:
        out.append((name, off, r, cc))
        off += r * cc
    return out


def param_count(c):
    V, T, D, F, L = c["V"], c["T"], c["D"], c["F"], c["L"]
    return V * D + T * D + L * (4 * D * D + 2 * D * F + 2 * D) + D


def unpack(c, flat):
    t = {}
    for name, off, r, cc in tensor_specs(c):
        if name.startswith("g"):
            t[name] = flat[off:off + cc]
        else:
            t[name] = [flat[off + i * cc: off + (i + 1) * cc] for i in range(r)]
    return t


def pack(c, t):
    flat = []
    for name, _, _, _ in tensor_specs(c):
        v = t[name]
        if name.startswith("g"):
            flat.extend(v)
        else:
            for row in v:
                flat.extend(row)
    return flat


def zeros_like(c):
    t = {}
    for name, _, r, cc in tensor_specs(c):
        t[name] = [0.0] * cc if name.startswith("g") else [[0.0] * cc for _ in range(r)]
    return t


# ---------------------------------------------------------------- init (§5)

def init_params(c, seed):
    L = c["L"]
    scale_res = 1.0 / math.sqrt(2 * L)
    flat = []
    for name, off, r, cc in tensor_specs(c):
        base = name.split(".")[0]
        for i in range(off, off + r * cc):
            if base in ("g1", "g2", "gf"):
                flat.append(1.0)
                continue
            ri = (splitmix64((seed + i) & M64) >> 11) * 2.0 ** -53
            v = (2.0 * ri - 1.0) * INIT_SCALE
            if base in ("wo", "w2"):
                v = v * scale_res
            flat.append(v)
    return flat


# ---------------------------------------------------------------- files (§6)

def write_file(path, magic, c, seed, step, total, lr, payloads):
    P = param_count(c)
    body = b"".join(struct.pack("<%dd" % P, *p) for p in payloads)
    hdr = magic + struct.pack("<7Q", *(c[k] for k in "VTDHFLB"))
    hdr += struct.pack("<4Q", seed & M64, step, total, f2bits(lr)) + struct.pack("<Q", P)
    hdr += struct.pack("<Q", fnv1a64(body))
    assert len(hdr) == 112
    tmp = path + ".tmp"
    with open(tmp, "wb") as f:
        f.write(hdr + body)
    os.rename(tmp, path)


class FormatError(Exception):
    pass


def read_file(path, magic, npay):
    with open(path, "rb") as f:
        raw = f.read()
    if len(raw) < 112:
        raise FormatError("short header")
    if raw[:8] != magic:
        raise FormatError("bad magic %r" % raw[:8])
    vals = struct.unpack("<7Q", raw[8:64])
    c = dict(zip("VTDHFLB", vals))
    seed, step, total, lrb, P = struct.unpack("<5Q", raw[64:104])
    (h,) = struct.unpack("<Q", raw[104:112])
    for k, v in c.items():
        if v > MAXS[k] or v == 0:
            raise FormatError("shape %s=%d out of range" % (k, v))
    if c["D"] % c["H"]:
        raise FormatError("D not divisible by H")
    if P != param_count(c):
        raise FormatError("P=%d disagrees with shapes (%d)" % (P, param_count(c)))
    if len(raw) != 112 + 8 * P * npay:
        raise FormatError("length %d != %d" % (len(raw), 112 + 8 * P * npay))
    body = raw[112:]
    if fnv1a64(body) != h:
        raise FormatError("hash mismatch")
    pays = [list(struct.unpack("<%dd" % P, body[8 * P * i: 8 * P * (i + 1)])) for i in range(npay)]
    return dict(c=c, seed=seed, step=step, total=total, lr=bits2f(lrb), lr_bits=lrb, P=P,
                hash=h, payloads=pays, raw=raw)


def write_ck(path, ck):
    write_file(path, b"OLLMCK01", ck["c"], ck["seed"], ck["step"], ck["total"], ck["lr"],
               [ck["params"], ck["m"], ck["v"]])


def read_ck(path):
    r = read_file(path, b"OLLMCK01", 3)
    r["params"], r["m"], r["v"] = r.pop("payloads")
    return r


def read_gr(path):
    r = read_file(path, b"OLLMGR01", 1)
    r["grad"] = r.pop("payloads")[0]
    return r


# ---------------------------------------------------------------- model (§3)

def rms_fwd(v, g):
    D = len(v)
    den = math.sqrt(sum(map(mul, v, v)) / D + EPS_RMS)
    return [v[i] / den * g[i] for i in range(D)], den


def rms_bwd(v, g, den, dy, dg):
    D = len(v)
    for i in range(D):
        dg[i] += dy[i] * v[i] / den
    s = sum(dy[i] * g[i] * v[i] for i in range(D))
    k = s / (D * den * den * den)
    return [g[i] * dy[i] / den - v[i] * k for i in range(D)]


def transpose(W):
    return [list(col) for col in zip(*W)]


def vecmat(x, WT):
    """y = x . W with WT the transpose (columns of W)."""
    return [sum(map(mul, x, col)) for col in WT]


def outer_acc(dW, x, dy):
    for r, xr in enumerate(x):
        if xr != 0.0:
            row = dW[r]
            dW[r] = [a + xr * b for a, b in zip(row, dy)]


def seq_loss_grad(c, P, PT, x, y, scale, G):
    """Loss of one sequence; accumulates scale * d(loss)/d(params) into G (dict of tensors)."""
    T, D, H, L, V = c["T"], c["D"], c["H"], c["L"], c["V"]
    E = D // H
    sE = math.sqrt(E)
    rs = 1.0 / sE
    wte, wpe = P["wte"], P["wpe"]
    h = [[a + b for a, b in zip(wte[x[t]], wpe[t])] for t in range(T)]
    caches = []
    for l in range(L):
        g1, g2 = P["g1.%d" % l], P["g2.%d" % l]
        hin = h
        an = [rms_fwd(v, g1) for v in hin]
        a = [p[0] for p in an]
        q = [vecmat(r, PT["wq.%d" % l]) for r in a]
        k = [vecmat(r, PT["wk.%d" % l]) for r in a]
        u = [vecmat(r, PT["wv.%d" % l]) for r in a]
        o = [[0.0] * D for _ in range(T)]
        probs = []
        for n in range(H):
            lo, hi = n * E, n * E + E
            pn = []
            for t in range(T):
                qt = q[t][lo:hi]
                s = [sum(map(mul, qt, k[j][lo:hi])) / sE for j in range(t + 1)]
                mx = max(s)
                e = [math.exp(v - mx) for v in s]
                z = sum(e)
                p = [v / z for v in e]
                pn.append(p)
                ot = o[t]
                for j in range(t + 1):
                    pj = p[j]
                    uj = u[j]
                    for i in range(lo, hi):
                        ot[i] += pj * uj[i]
            probs.append(pn)
        att = [vecmat(r, PT["wo.%d" % l]) for r in o]
        h1 = [[a_ + b_ for a_, b_ in zip(hv, av)] for hv, av in zip(hin, att)]
        bn = [rms_fwd(v, g2) for v in h1]
        b = [p[0] for p in bn]
        f = [vecmat(r, PT["w1.%d" % l]) for r in b]
        rf = [[v if v > 0.0 else 0.0 for v in r] for r in f]
        ff = [vecmat(r, PT["w2.%d" % l]) for r in rf]
        h2 = [[a_ + b_ for a_, b_ in zip(hv, fv)] for hv, fv in zip(h1, ff)]
        caches.append((hin, an, a, q, k, u, o, probs, h1, bn, b, f, rf))
        h = h2
    gf = P["gf"]
    zn = [rms_fwd(v, gf) for v in h]
    loss = 0.0
    dh = []
    dgf = G["gf"]
    dwte = G["wte"]
    for t in range(T):
        z = zn[t][0]
        lg = [sum(map(mul, z, wte[cc])) for cc in range(V)]
        mx = max(lg)
        e = [math.exp(v - mx) for v in lg]
        se = sum(e)
        loss += -(lg[y[t]] - mx - math.log(se))
        w = scale / T
        dl = [ev / se * w for ev in e]
        dl[y[t]] -= w
        dz = [0.0] * D
        for cc in range(V):
            d = dl[cc]
            row = wte[cc]
            dz = [a_ + d * b_ for a_, b_ in zip(dz, row)]
            dwte[cc] = [a_ + d * b_ for a_, b_ in zip(dwte[cc], z)]
        dh.append(rms_bwd(h[t], gf, zn[t][1], dz, dgf))
    loss /= T
    for l in range(L - 1, -1, -1):
        hin, an, a, q, k, u, o, probs, h1, bn, b, f, rf = caches[l]
        W = {n: P["%s.%d" % (n, l)] for n in ("wq", "wk", "wv", "wo", "w1", "w2")}
        dW = {n: G["%s.%d" % (n, l)] for n in ("wq", "wk", "wv", "wo", "w1", "w2")}
        g1, g2 = P["g1.%d" % l], P["g2.%d" % l]
        dg1, dg2 = G["g1.%d" % l], G["g2.%d" % l]
        dh1 = []
        for t in range(T):
            d = dh[t]
            outer_acc(dW["w2"], rf[t], d)
            drf = [sum(map(mul, d, row)) for row in W["w2"]]
            df = [dv if fv > 0.0 else 0.0 for dv, fv in zip(drf, f[t])]
            outer_acc(dW["w1"], b[t], df)
            db = [sum(map(mul, df, row)) for row in W["w1"]]
            dr = rms_bwd(h1[t], g2, bn[t][1], db, dg2)
            dh1.append([a_ + b_ for a_, b_ in zip(d, dr)])
        do = []
        for t in range(T):
            outer_acc(dW["wo"], o[t], dh1[t])
            do.append([sum(map(mul, dh1[t], row)) for row in W["wo"]])
        dq = [[0.0] * D for _ in range(T)]
        dk = [[0.0] * D for _ in range(T)]
        du = [[0.0] * D for _ in range(T)]
        for n in range(H):
            lo, hi = n * E, n * E + E
            for t in range(T):
                p = probs[n][t]
                dot = do[t][lo:hi]
                dp = [sum(map(mul, dot, u[j][lo:hi])) for j in range(t + 1)]
                for j in range(t + 1):
                    duj = du[j]
                    pj = p[j]
                    for i in range(lo, hi):
                        duj[i] += pj * do[t][i]
                sdp = sum(map(mul, p, dp))
                ds = [p[j] * (dp[j] - sdp) * rs for j in range(t + 1)]
                dqt = dq[t]
                qt = q[t]
                for j in range(t + 1):
                    dsj = ds[j]
                    kj = k[j]
                    dkj = dk[j]
                    for i in range(lo, hi):
                        dqt[i] += dsj * kj[i]
                        dkj[i] += dsj * qt[i]
        dhin = []
        for t in range(T):
            outer_acc(dW["wq"], a[t], dq[t])
            outer_acc(dW["wk"], a[t], dk[t])
            outer_acc(dW["wv"], a[t], du[t])
            da = [sum(map(mul, dq[t], r1)) + sum(map(mul, dk[t], r2)) + sum(map(mul, du[t], r3))
                  for r1, r2, r3 in zip(W["wq"], W["wk"], W["wv"])]
            dr = rms_bwd(hin[t], g1, an[t][1], da, dg1)
            dhin.append([a_ + b_ for a_, b_ in zip(dh1[t], dr)])
        dh = dhin
    for t in range(T):
        G["wte"][x[t]] = [a_ + b_ for a_, b_ in zip(G["wte"][x[t]], dh[t])]
        G["wpe"][t] = [a_ + b_ for a_, b_ in zip(G["wpe"][t], dh[t])]
    return loss


def loss_and_grad(c, flat, seqs):
    """seqs: list of (x, y). Returns (mean loss, flat gradient of the mean loss)."""
    P = unpack(c, flat)
    PT = {n: transpose(v) for n, v in P.items() if not n.startswith("g")}
    G = zeros_like(c)
    scale = 1.0 / len(seqs)
    tot = 0.0
    for x, y in seqs:
        tot += seq_loss_grad(c, P, PT, x, y, scale, G)
    return tot / len(seqs), pack(c, G)


def loss_only(c, flat, seqs):
    return loss_and_grad(c, flat, seqs)[0]


# ---------------------------------------------------------------- data (§4)

def batch_offsets(seed, step, B, N, T):
    return [splitmix64((seed ^ (((step * B + b) * GOLDEN) & M64)) & M64) % (N - T)
            for b in range(B)]


def seqs_at(data, offs, T):
    return [(list(data[o:o + T]), list(data[o + 1:o + T + 1])) for o in offs]


def prep(inp):
    stories = [s.strip(b"\t\n\r ") for s in inp.split(SEP)]
    stories = [s for s in stories if s]
    train, held = bytearray(), bytearray()
    nt = nh = 0
    for i, s in enumerate(stories):
        if i % 10 == 9:
            held += s + b"\0"
            nh += 1
        else:
            train += s + b"\0"
            nt += 1
    return bytes(train), bytes(held), (len(stories), nt, nh, len(train), len(held))


def base(train, held):
    N = len(train)
    uni = Counter(train)
    pair = Counter(zip(train, train[1:]))
    rowtot = [0] * 256
    for (a, _), n in pair.items():
        rowtot[a] += n
    hpair = Counter(zip(held, held[1:]))
    hn = len(held) - 1
    ln2 = math.log(2.0)
    su = sb = 0.0
    for (a, b), n in hpair.items():
        su += n * -math.log((uni[b] + 1) / (N + 256)) / ln2
        sb += n * -math.log((pair[(a, b)] + 1) / (rowtot[a] + 256)) / ln2
    return su / hn, sb / hn


def eval_held(c, flat, held, W):
    T = c["T"]
    offs = [w * T for w in range(W)]
    tot = 0.0
    for o in offs:
        tot += loss_only(c, flat, seqs_at(held, [o], T))
    return tot / W


# ---------------------------------------------------------------- optimizer (§5)

def lr_at(lr, s, total):
    if s < 100:
        return lr * (s + 1) / 100
    return lr * (1 - 0.9 * (s - 100) / max(1, total - 100))


def adam_step(ck, grad):
    """Returns (new ck dict, info). Uses the pre-increment step s."""
    s = ck["step"]
    g = list(grad)
    n = math.sqrt(sum(v * v for v in g))
    clipped = n > 1.0
    if clipped:
        inv = 1.0 / n
        g = [v * inv for v in g]
    lrs = lr_at(ck["lr"], s, ck["total"])
    pw1 = pw2 = 1.0
    for _ in range(s + 1):  # agreed reading A3: powers by repeated multiplication
        pw1 *= BETA1
        pw2 *= BETA2
    c1 = 1.0 - pw1
    c2 = 1.0 - pw2
    p2, m2, v2 = [], [], []
    for p, m, v, gi in zip(ck["params"], ck["m"], ck["v"], g):
        m = BETA1 * m + (1 - BETA1) * gi
        v = BETA2 * v + (1 - BETA2) * gi * gi
        p = p - lrs * (m / c1) / (math.sqrt(v / c2) + ADAM_EPS)
        p2.append(p)
        m2.append(m)
        v2.append(v)
    out = dict(ck)
    out.update(params=p2, m=m2, v=v2, step=s + 1)
    return out, dict(norm=n, clipped=clipped, lr_s=lrs)


# ---------------------------------------------------------------- comparison helpers

def compare_flat(c, got, ref, rtol=RTOL):
    """Per-tensor max mixed relative error; returns (ok, {tensor: (maxerr, argmax, got, ref)})."""
    res, ok = {}, True
    for name, off, r, cc in tensor_specs(c):
        seg_r = ref[off:off + r * cc]
        seg_g = got[off:off + r * cc]
        floor = FLOOR_FRAC * max(abs(v) for v in seg_r)
        worst = (0.0, -1, 0.0, 0.0)
        for i, (a, b) in enumerate(zip(seg_g, seg_r)):
            den = max(abs(b), floor)
            err = abs(a - b) / den if den > 0 else (0.0 if a == b else math.inf)
            if not err <= worst[0] and not (err == 0.0 and worst[1] >= 0):
                worst = (err, i, a, b)
        if worst[1] < 0:
            worst = (0.0, 0, seg_g[0], seg_r[0])
        res[name] = worst
        if not worst[0] <= rtol:
            ok = False
    return ok, res


def fmt_tensor_errs(res):
    return "\n".join("  %-6s maxerr %.3e at %d (got %.17g ref %.17g)" % (n, e, i, a, b)
                     for n, (e, i, a, b) in res.items())


def max_err_by_base(res):
    out = {}
    for n, (e, *_) in res.items():
        k = n.split(".")[0]
        out[k] = max(out.get(k, 0.0), e)
    return out


# ---------------------------------------------------------------- selftest

def selftest():
    fails = []

    def check(cond, msg):
        print(("PASS " if cond else "FAIL ") + msg)
        if not cond:
            fails.append(msg)

    # Known answers, all computed with Wolfram (see ORACLE.md, query W1).
    kat_fnv = {b"": 0xCBF29CE484222325, b"a": 0xAF63DC4C8601EC8C,
               b"foobar": 0x85944171F73967E8, b"OLLMCK01": 0x29C48BB36358F164}
    for k, v in kat_fnv.items():
        check(fnv1a64(k) == v, "fnv1a64(%r) = %016x" % (k, v))
    kat_sm = {0: 0xE220A8397B1DCDAF, 1: 0x910A2DEC89025CC1, M64: 0xE4D971771B652C20,
              42: 0xBDD732262FEB6E95}
    for k, v in kat_sm.items():
        check(splitmix64(k) == v, "splitmix64(%d) = %016x" % (k, v))
    # Batch rule: S=7, s=3, B=2, b=1 -> splitmix64(7 xor (7*G mod 2^64)) mod 1000 = 533 (Wolfram W1).
    check(batch_offsets(7, 3, 2, 1000 + 8, 8)[1] == 533, "batch offset KAT 533")
    # Init draw: (splitmix64(42+5) >> 11) = 4352384759967643 (Wolfram W1).
    check(splitmix64(47) >> 11 == 4352384759967643, "init draw KAT S=42 i=5")
    c = SMALL
    P = param_count(c)
    check(P == 8400, "small P = 8400")
    check(param_count(V0) == 119104, "v0 P = 119104")
    flat = init_params(c, 42)
    check(flat[5] == (2.0 * (4352384759967643 * 2.0 ** -53) - 1.0) * INIT_SCALE, "init value i=5")
    # checkpoint round trip
    rng = random.Random(1)
    ck = dict(c=dict(c), seed=42, step=3, total=50, lr=3e-3, params=flat,
              m=[rng.uniform(-1, 1) for _ in range(P)], v=[rng.random() for _ in range(P)])
    with scratch() as d:
        p = os.path.join(d, "ck")
        write_ck(p, ck)
        r = read_ck(p)
        check(all(r[k] == ck[k] for k in ("seed", "step", "total", "lr", "params", "m", "v"))
              and r["c"] == ck["c"] and not os.path.exists(p + ".tmp"), "checkpoint round trip")
        raw = bytearray(r["raw"])
        raw[200] ^= 1
        with open(p, "wb") as f:
            f.write(raw)
        try:
            read_ck(p)
            check(False, "hash mismatch refused")
        except FormatError:
            check(True, "hash mismatch refused")
    # gradient vs central differences. Perturb params away from init so gains/ReLU are generic.
    data = bytes(rng.randrange(1, 256) for _ in range(200))
    seqs = seqs_at(data, [5, 77], c["T"])
    pf = [v + rng.gauss(0, 0.3) for v in flat]
    loss, g = loss_and_grad(c, pf, seqs)
    check(math.isfinite(loss) and loss > 0, "loss finite %.6f" % loss)
    hstep = 1e-5
    worst = 0.0
    for name, off, r, cc in tensor_specs(c):
        n = r * cc
        idxs = [off + rng.randrange(n) for _ in range(3)]
        if name == "wte":
            idxs.append(off + seqs[0][0][2] * cc + 1)  # a row that is also an input
        for i in idxs:
            sv = pf[i]
            pf[i] = sv + hstep
            lp = loss_only(c, pf, seqs)
            pf[i] = sv - hstep
            lm = loss_only(c, pf, seqs)
            pf[i] = sv
            num = (lp - lm) / (2 * hstep)
            err = abs(num - g[i]) / max(abs(g[i]), abs(num), 1e-6)
            worst = max(worst, err)
            check(err < 1e-5, "grad %-6s [%d] analytic %.10e numeric %.10e relerr %.2e"
                  % (name, i - off, g[i], num, err))
    print("selftest worst finite-difference relerr %.3e" % worst)
    # adam: step 0 update equals -lr_0 * sign(g) up to eps for unclipped g.
    ck0 = dict(c=dict(c), seed=1, step=0, total=10, lr=1e-2, params=[0.0] * P,
               m=[0.0] * P, v=[0.0] * P)
    gg = [1e-3] * P
    n = math.sqrt(P) * 1e-3
    ck1, info = adam_step(ck0, gg)
    want = -1e-4 * 1e-3 / (1e-3 + ADAM_EPS)  # lr_0 = lr/100; mhat = g, sqrt(vhat) = |g|
    check(abs(ck1["params"][0] - want) < 1e-15 and not info["clipped"] and n < 1,
          "adam step 0 = -lr/100 * g/(|g|+eps)")
    ck1, info = adam_step(ck0, [1.0] * P)
    check(info["clipped"] and abs(ck1["m"][0] - 0.1 / math.sqrt(P)) < 1e-15, "clip to norm 1")
    # prep: separators, trimming, empty-story drop, i mod 10 == 9 to HELD, 0 terminators.
    parts = [b" s%d\r\n" % i for i in range(11)]
    parts.insert(3, b"\t \n")  # empty after trim: dropped, does not count
    tr, he, st = prep(SEP.join(parts))
    want_tr = b"".join(b"s%d\0" % i for i in range(11) if i != 9)
    check(tr == want_tr and he == b"s9\0" and st == (11, 10, 1, len(want_tr), 3), "prep KAT")
    # base: direct per-transition evaluation equals the counted form.
    trn, hld = b"abcab\0aab\0", b"abz\0ba\0"
    u, b = base(trn, hld)
    N = len(trn)
    pairs = list(zip(trn, trn[1:]))
    ud = bd = 0.0
    for a_, b_ in zip(hld, hld[1:]):
        ud += -math.log2((trn.count(bytes([b_])) + 1) / (N + 256))
        row = [p for p in pairs if p[0] == a_]
        bd += -math.log2((row.count((a_, b_)) + 1) / (len(row) + 256))
    check(abs(u - ud / 6) < 1e-12 and abs(b - bd / 6) < 1e-12, "base direct = counted")
    print("SELFTEST %s (%d failures)" % ("PASS" if not fails else "FAIL", len(fails)))
    return 0 if not fails else 1


# ---------------------------------------------------------------- cross-checks

def sha256_file(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for blk in iter(lambda: f.read(1 << 20), b""):
            h.update(blk)
    return h.hexdigest()


class Receipt:
    def __init__(self, check, binary):
        self.r = dict(check=check, binary=binary,
                      binary_sha256=sha256_file(binary) if os.path.exists(binary) else None,
                      oracle_sha256=sha256_file(os.path.abspath(__file__)),
                      started=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                      affinity=sorted(os.sched_getaffinity(0)), nice=os.nice(0),
                      commands=[], results=[], verdict=None)

    def run(self, argv):
        t0 = time.monotonic()
        p = subprocess.run(argv, capture_output=True)
        dt = time.monotonic() - t0
        rec = dict(argv=argv, rc=p.returncode, stdout=p.stdout.decode("latin-1"),
                   stderr=p.stderr.decode("latin-1")[-2000:], seconds=round(dt, 3))
        self.r["commands"].append(rec)
        print("$ %s\n  rc=%d %.2fs stdout=%r" % (" ".join(argv), p.returncode, dt, rec["stdout"][:300]))
        if rec["stderr"]:
            print("  stderr=%r" % rec["stderr"][:300])
        return rec

    def result(self, name, ok, **kw):
        kw.update(name=name, ok=ok)
        self.r["results"].append(kw)
        print(("PASS " if ok else "FAIL ") + name)

    def finish(self, out):
        ok = all(x["ok"] for x in self.r["results"]) and bool(self.r["results"])
        self.r["verdict"] = "PASS" if ok else "FAIL"
        self.r["finished"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        if out:
            os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
            with open(out, "w") as f:
                json.dump(self.r, f, indent=1)
        print("%s %s" % (self.r["check"].upper(), self.r["verdict"]))
        return 0 if ok else 1


def cfg_args(c):
    return [str(c[k]) for k in "VTDHFLB"]


def make_ck(c, seed, total, lrmicro):
    return dict(c=dict(c), seed=seed, step=0, total=total, lr=float(lrmicro) / 1000000.0,
                params=init_params(c, seed), m=[0.0] * param_count(c), v=[0.0] * param_count(c))


def x_init(a):
    R = Receipt("xinit", a.ollm)
    c, seed, total, lrm = load_cfg(a.cfg), a.seed, 50, 3000
    with scratch() as d:
        ckp = os.path.join(d, "ck")
        rec = R.run([a.ollm, "init", ckp] + cfg_args(c) + [str(seed), str(total), str(lrm)])
        P = param_count(c)
        R.result("rc 0", rec["rc"] == 0, rc=rec["rc"])
        R.result("stdout 'I P'", rec["stdout"].split() == ["I", str(P)], stdout=rec["stdout"])
        if rec["rc"] != 0:
            return R.finish(a.receipt)
        got = read_ck(ckp)
        ref = make_ck(c, seed, total, lrm)
        diff = [i for i in range(P) if f2bits(got["params"][i]) != f2bits(ref["params"][i])]
        R.result("params bit-identical", not diff, ndiff=len(diff), first=diff[:5])
        R.result("m, v zero", all(v == 0.0 for v in got["m"] + got["v"]))
        R.result("header", got["c"] == c and got["seed"] == seed and got["step"] == 0
                 and got["total"] == total and got["P"] == P,
                 header=dict(c=got["c"], seed=got["seed"], step=got["step"], total=got["total"]))
        lrb = f2bits(float(lrm) / 1000000.0)  # agreed reading A8: one f64 division
        R.result("lr bits = 3000/1e6", got["lr_bits"] == lrb,
                 got="%016x" % got["lr_bits"], ref="%016x" % lrb)
        refp = os.path.join(d, "ref")
        write_ck(refp, ref)
        R.result("whole file sha256 identical", sha256_file(refp) == sha256_file(ckp),
                 got=sha256_file(ckp), ref=sha256_file(refp))
    return R.finish(a.receipt)


def load_cfg(name):
    return dict(SMALL if name == "small" else V0)


def synth_ck(c, seed, step, total, lr, scale):
    """Init params plus seeded noise, nonzero m and v (exercises gains, clip and step>0 paths)."""
    rng = random.Random(seed)
    P = param_count(c)
    p = [v + rng.gauss(0, scale) for v in init_params(c, seed)]
    m = [rng.gauss(0, 1e-3) for _ in range(P)]
    v = [rng.random() * 1e-5 for _ in range(P)]
    return dict(c=dict(c), seed=seed, step=step, total=total, lr=lr, params=p, m=m, v=v)


def x_grad(a):
    R = Receipt("xgrad", a.ollm)
    c = load_cfg(a.cfg)
    if a.batch:
        c["B"] = a.batch
    with open(a.data, "rb") as f:
        data = f.read()
    R.r["data"] = dict(path=a.data, sha256=hashlib.sha256(data).hexdigest(), bytes=len(data))
    with scratch() as d:
        cases = [("init", make_ck(c, a.seed, 1000, 3000)),
                 ("perturbed", synth_ck(c, a.seed + 1, 7, 1000, 3e-3, 0.3))]
        for label, ck in cases:
            ckp = os.path.join(d, "ck." + label)
            write_ck(ckp, ck)
            offs = batch_offsets(ck["seed"], ck["step"], c["B"], len(data), c["T"])
            offp = os.path.join(d, "offs." + label)
            with open(offp, "wb") as f:
                f.write(struct.pack("<%dQ" % len(offs), *offs))
            outp = os.path.join(d, "gr." + label)
            rec = R.run([a.ollm, "grad", ckp, a.data, offp, outp])
            t0 = time.monotonic()
            loss, g = loss_and_grad(c, ck["params"], seqs_at(data, offs, c["T"]))
            R.r.setdefault("oracle_seconds", {})[label] = round(time.monotonic() - t0, 2)
            R.result(label + ": rc 0", rec["rc"] == 0, rc=rec["rc"], offsets=offs)
            if rec["rc"] != 0:
                continue
            f_ = rec["stdout"].split()
            ok = len(f_) == 3 and f_[0] == "G"
            gl = bits2f(int(f_[1], 16)) if ok else math.nan
            lerr = abs(gl - loss) / loss
            R.result(label + ": loss", ok and lerr <= RTOL and int(f_[2]) == micro(loss),
                     got=gl, ref=loss, relerr=lerr, got_micro=f_[2] if ok else None,
                     ref_micro=micro(loss))
            gr = read_gr(outp)
            R.result(label + ": OLLMGR01 header", gr["c"] == c and gr["step"] == c["B"]
                     and gr["seed"] == ck["seed"] and gr["total"] == ck["total"]
                     and gr["lr_bits"] == f2bits(ck["lr"]),
                     header=dict(c=gr["c"], step=gr["step"], seed=gr["seed"], total=gr["total"],
                                 lr="%016x" % gr["lr_bits"]))
            okg, res = compare_flat(c, gr["grad"], g)
            print(fmt_tensor_errs(res))
            R.result(label + ": gradient (rtol %g)" % RTOL, okg,
                     max_err_per_tensor={n: e for n, (e, *_) in res.items()},
                     max_err_by_kind=max_err_by_base(res),
                     grad_norm=math.sqrt(sum(v * v for v in g)))
    return R.finish(a.receipt)


def x_step(a):
    R = Receipt("xstep", a.ollm)
    c = load_cfg(a.cfg)
    with open(a.data, "rb") as f:
        data = f.read()
    R.r["data"] = dict(path=a.data, sha256=hashlib.sha256(data).hexdigest(), bytes=len(data))
    with scratch() as d:
        small_gf = make_ck(c, a.seed + 1, 300, 3000)
        small_gf["step"] = 2
        _, off, _, cc = tensor_specs(c)[-1]
        for i in range(off, off + cc):
            small_gf["params"][i] = 0.1  # gf = 0.1 keeps the gradient norm below 1 (no clip)
        # (label, checkpoint or None = the binary's previous output, clip expected)
        cases = [("step0-init", make_ck(c, a.seed, 300, 3000), True),
                 ("step1-chain", None, True),
                 ("step2-unclipped", small_gf, False),
                 ("step150-synthetic-clip", synth_ck(c, a.seed + 2, 150, 300, 3e-3, 0.5), True)]
        prev = None
        for label, ck, want_clip in cases:
            ckp = os.path.join(d, "ck." + label)
            if ck is None and prev is None:
                R.result(label + ": previous case produced no checkpoint", False)
                continue
            if ck is None:
                # continue from the binary's own step-1 output (m, v nonzero, step 1)
                ck = read_ck(prev)
                ck["c"] = dict(ck["c"])
            write_ck(ckp, ck)
            s = ck["step"]
            offs = batch_offsets(ck["seed"], s, c["B"], len(data), c["T"])
            loss, g = loss_and_grad(c, ck["params"], seqs_at(data, offs, c["T"]))
            ref, info = adam_step(ck, g)
            R.result(label + ": covers clip=%s" % want_clip, info["clipped"] == want_clip,
                     norm=info["norm"])
            rec = R.run([a.ollm, "train", ckp, a.data, str(s + 1), "1"])
            R.result(label + ": rc 0", rec["rc"] == 0, rc=rec["rc"])
            if rec["rc"] != 0:
                continue
            want = ["T", str(s + 1), str(micro(loss))]
            got_line = rec["stdout"].split()
            R.result(label + ": stdout", got_line == want, got=got_line, want=want,
                     loss=loss, **info)
            got = read_ck(ckp)
            R.result(label + ": step", got["step"] == s + 1, got=got["step"])
            R.result(label + ": header unchanged", got["c"] == c and got["seed"] == ck["seed"]
                     and got["total"] == ck["total"] and got["lr_bits"] == f2bits(ck["lr"]))
            for k in ("params", "m", "v"):
                okk, res = compare_flat(c, got[k], ref[k])
                print(k)
                print(fmt_tensor_errs(res))
                R.result("%s: %s (rtol %g)" % (label, k, RTOL), okk,
                         max_err_by_kind=max_err_by_base(res))
            prev = os.path.join(d, "keep.%s" % label)
            os.rename(ckp, prev)
    return R.finish(a.receipt)


def x_prep(a):
    R = Receipt("xprep", a.ollm)
    with open(a.data, "rb") as f:
        inp = f.read()
    R.r["data"] = dict(path=a.data, sha256=hashlib.sha256(inp).hexdigest(), bytes=len(inp))
    tr, he, st = prep(inp)
    os.makedirs(a.outdir, exist_ok=True)
    otr, ohe = os.path.join(a.outdir, "oracle-train.bin"), os.path.join(a.outdir, "oracle-held.bin")
    for p, b in ((otr, tr), (ohe, he)):
        with open(p, "wb") as f:
            f.write(b)
    btr, bhe = os.path.join(a.outdir, "ollm-train.bin"), os.path.join(a.outdir, "ollm-held.bin")
    rec = R.run([a.ollm, "prep", a.data, btr, bhe])
    R.result("rc 0", rec["rc"] == 0, rc=rec["rc"])
    want = ["P"] + [str(v) for v in st]
    R.result("stdout", rec["stdout"].split() == want, got=rec["stdout"].split(), want=want)
    if rec["rc"] == 0:
        for lab, o, b in (("TRAIN", otr, btr), ("HELD", ohe, bhe)):
            so, sb = sha256_file(o), sha256_file(b)
            R.result(lab + " sha256 identical", so == sb, oracle=so, ollm=sb,
                     bytes=os.path.getsize(o))
    return R.finish(a.receipt)


def x_base(a):
    R = Receipt("xbase", a.ollm)
    with open(a.train, "rb") as f:
        tr = f.read()
    with open(a.held, "rb") as f:
        he = f.read()
    R.r["data"] = dict(train=sha256_file(a.train), held=sha256_file(a.held))
    u, b = base(tr, he)
    rec = R.run([a.ollm, "base", a.train, a.held])
    want = ["B", str(micro(u)), str(micro(b))]
    R.result("rc 0", rec["rc"] == 0, rc=rec["rc"])
    R.result("stdout micro values", rec["stdout"].split() == want, got=rec["stdout"].split(),
             want=want, uni_bpb=u, bi_bpb=b)
    return R.finish(a.receipt)


def x_eval(a):
    R = Receipt("xeval", a.ollm)
    c = load_cfg(a.cfg)
    with open(a.held, "rb") as f:
        he = f.read()
    with scratch() as d:
        ck = synth_ck(c, a.seed + 3, 5, 100, 1e-3, 0.3)
        ckp = os.path.join(d, "ck")
        write_ck(ckp, ck)
        W = 4
        loss = eval_held(c, ck["params"], he, W)
        rec = R.run([a.ollm, "eval", ckp, a.held, str(W)])
        want = ["E", "5", str(W), str(micro(loss)), str(micro(loss / math.log(2)))]
        R.result("rc 0", rec["rc"] == 0, rc=rec["rc"])
        R.result("stdout", rec["stdout"].split() == want, got=rec["stdout"].split(), want=want,
                 loss=loss)
    return R.finish(a.receipt)


# ---------------------------------------------------------------- CLI

def main(argv):
    import argparse
    ap = argparse.ArgumentParser(prog="oracle.py")
    sp = ap.add_subparsers(dest="cmd", required=True)
    sp.add_parser("selftest")
    for name in ("xinit", "xgrad", "xstep", "xprep", "xbase", "xeval"):
        p = sp.add_parser(name)
        p.add_argument("--ollm", required=True)
        p.add_argument("--receipt")
        p.add_argument("--seed", type=int, default=42)
        if name in ("xgrad", "xstep", "xprep"):
            p.add_argument("--data", required=True)
        if name in ("xinit", "xgrad", "xstep", "xeval"):
            p.add_argument("--cfg", choices=("small", "v0"), default="small")
        if name == "xgrad":
            p.add_argument("--batch", type=int, help="override B")
        if name == "xprep":
            p.add_argument("--outdir", required=True)
        if name == "xbase":
            p.add_argument("--train", required=True)
        if name in ("xbase", "xeval"):
            p.add_argument("--held", required=True)
    p = sp.add_parser("prep")
    p.add_argument("inp"); p.add_argument("train"); p.add_argument("held")
    p = sp.add_parser("base")
    p.add_argument("train"); p.add_argument("held")
    a = ap.parse_args(argv)
    if a.cmd == "selftest":
        return selftest()
    if a.cmd == "prep":
        with open(a.inp, "rb") as f:
            tr, he, st = prep(f.read())
        for p_, b_ in ((a.train, tr), (a.held, he)):
            with open(p_, "wb") as f:
                f.write(b_)
        print("P %d %d %d %d %d" % st)
        return 0
    if a.cmd == "base":
        with open(a.train, "rb") as f:
            tr = f.read()
        with open(a.held, "rb") as f:
            he = f.read()
        u, b = base(tr, he)
        print("B %d %d" % (micro(u), micro(b)))
        return 0
    return dict(xinit=x_init, xgrad=x_grad, xstep=x_step, xprep=x_prep, xbase=x_base,
                xeval=x_eval)[a.cmd](a)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
