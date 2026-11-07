"""PREREG section 6 item 5: norm-matched control edits (external instrument).
python3 make_controls.py CK SELECTED_HOOKS_JSON OUT_ARMS_JSON
SELECTED_HOOKS_JSON: [[K, L, I, A], ...] with K 1 (wo rows of head I, layer L) or 2 (w2 row I, layer L).
For each seed in 187101..187103 the same operation is applied to randomly chosen heads (K 1) or neurons
(K 2) of the same layers, excluding the selected ones, one per selected unit; one common scale per kind
is solved so that the Frobenius norm of that kind's weight change equals the selected edit's
(change norm = |s - 1| * sqrt(sum of squared entries of the scaled rows)), on the same side of 1.
A is in thousandths (integer), so the realised norm is recomputed and must be within 1%."""
import array, json, math, random, struct, sys

ck, sel_path, out_path = sys.argv[1:4]
f = open(ck, 'rb')
h = struct.unpack('<15Q', f.read(120))
V, T, D, H, F, L = h[1], h[2], h[3], h[4], h[5], h[6]
E = D // H
w = array.array('d'); w.frombytes(f.read(8 * h[12]))
lay = V * D + T * D
per = D + 4 * D * D + D + 2 * D * F

def wo_off(l): return lay + l * per + D + 3 * D * D
def w2_off(l): return lay + l * per + D + 4 * D * D + D + D * F

def sq(k, l, i):
    if k == 1:
        o = wo_off(l) + i * E * D; n = E * D
    else:
        o = w2_off(l) + i * D; n = D
    return sum(x * x for x in w[o:o + n])

sel = json.load(open(sel_path))
kinds = sorted({g[0] for g in sel})
assert all(k in (1, 2) for k in kinds)
arms, report = [], []
for seed in (187101, 187102, 187103):
    rng = random.Random(seed)
    hooks, info = [], {}
    for k in kinds:
        groups = [g for g in sel if g[0] == k]
        target = math.sqrt(sum(((g[3] / 1000.0) - 1.0) ** 2 * sq(k, g[1], g[2]) for g in groups))
        side = 1 if groups[0][3] > 1000 else -1
        assert all((g[3] > 1000) == (side > 0) for g in groups)
        taken = {(g[1], g[2]) for g in sel if g[0] == k}
        units = []
        for g in groups:
            pool = range(H) if k == 1 else range(F)
            while True:
                c = rng.choice(pool)
                if (g[1], c) not in taken:
                    break
            taken.add((g[1], c)); units.append((g[1], c))
        ss = sum(sq(k, l, i) for l, i in units)
        a = int(round(1000 * (1.0 + side * target / math.sqrt(ss))))
        real = abs(a / 1000.0 - 1.0) * math.sqrt(ss)
        assert abs(real - target) <= 0.01 * target, (seed, k, real, target)
        assert 0 <= a <= 4000, (seed, k, a)
        hooks += [[k, l, i, a] for l, i in units]
        info[k] = dict(target_norm=target, realised_norm=real, scale_milli=a, units=units)
    arms.append(dict(name='H-control-%d' % seed, split='H', mode='gen', hooks=hooks + [[5, 0, 0, 0]]))
    report.append(dict(seed=seed, **{('kind%d' % k): v for k, v in info.items()}))
json.dump(arms, open(out_path, 'w'), indent=0)
print(json.dumps(report))
