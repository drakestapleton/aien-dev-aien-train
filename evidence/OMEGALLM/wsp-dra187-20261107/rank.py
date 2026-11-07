"""DRA-187 probe-output analysis (external instrument, not product code).
python3 rank.py SPLIT.json PROBE.out [PROBE2.out ...]
For each probe output: teacher-forced exact counts by role and length (a record is exact when every
answer token is the row argmax: `R idx np na -1`). For the first file only: over the failure rows whose
first divergence is a digit-copy failure (expected token a digit byte 48..57, predicted `.` 46 or another
digit), the mean head parts (H l n) and the mean neuron parts (N l f; a neuron absent from a row's top 16 of
its layer counts 0 there), and the mean logit gap."""
import json, sys, collections

def parse(path):
    recs, cur = {}, None
    for line in open(path, encoding='utf-8', errors='replace'):
        f = line.split()
        if not f:
            continue
        if f[0] == 'R':
            cur = dict(idx=int(f[1]), np=int(f[2]), na=int(f[3]), div=int(f[4]), H={}, N={}, M={})
            if cur['div'] >= 0:
                cur['exp'], cur['pred'] = int(f[5]), int(f[6])
            recs[cur['idx']] = cur
        elif f[0] == 'LD':
            cur['ld'] = float(f[1])
        elif f[0] == 'H':
            cur['H'][(int(f[1]), int(f[2]))] = float(f[3])
        elif f[0] == 'M':
            cur['M'][int(f[1])] = float(f[2])
        elif f[0] == 'N':
            cur['N'][(int(f[1]), int(f[2]))] = float(f[3])
    return recs

rows = {r['idx']: r for r in json.load(open(sys.argv[1]))}
for k, path in enumerate(sys.argv[2:]):
    recs = parse(path)
    assert len(recs) == len(rows), (path, len(recs), len(rows))
    tab = collections.Counter()
    for i, r in rows.items():
        tab[(r['role'], r['length'], recs[i]['div'] < 0)] += 1
    parts = []
    for role in ('target', 'control'):
        ls = sorted({r['length'] for r in rows.values() if r['role'] == role})
        p = sum(tab[(role, n, True)] for n in ls); t = p + sum(tab[(role, n, False)] for n in ls)
        parts.append('%s %d/%d (%s)' % (role, p, t, ' '.join('L%d %d/%d' % (n, tab[(role, n, True)], tab[(role, n, True)] + tab[(role, n, False)]) for n in ls)))
    print(path, '|', ' | '.join(parts))
    if k:
        continue
    fail = [x for x in recs.values() if x['div'] >= 0 and 48 <= x['exp'] <= 57 and (x['pred'] == 46 or 48 <= x['pred'] <= 57)]
    other = [x for x in recs.values() if x['div'] >= 0 and x not in fail]
    print('digit-copy failure rows', len(fail), '(pred "." %d, pred digit %d); other divergences %d'
          % (sum(x['pred'] == 46 for x in fail), sum(x['pred'] != 46 for x in fail), len(other)))
    if not fail:
        continue
    n = len(fail)
    print('mean logit gap %.4f' % (sum(x['ld'] for x in fail) / n))
    hs = collections.Counter()
    for x in fail:
        for key, v in x['H'].items():
            hs[key] += v / n
    print('heads by mean part (top 8):', ' '.join('%d.%d:%+.3f' % (l, h, v) for (l, h), v in hs.most_common(8)))
    print('heads by mean part (bottom 4):', ' '.join('%d.%d:%+.3f' % (l, h, v) for (l, h), v in sorted(hs.items(), key=lambda kv: kv[1])[:4]))
    ms = collections.Counter()
    for x in fail:
        for key, v in x['M'].items():
            ms[key] += v / n
    print('MLP mean part:', ' '.join('%d:%+.3f' % (l, ms[l]) for l in sorted(ms)))
    ns = collections.Counter()
    for x in fail:
        for key, v in x['N'].items():
            ns[key] += v / n
    neg = sorted(ns.items(), key=lambda kv: kv[1])[:32]
    print('neurons by mean part (most negative 32):', ' '.join('%d.%d:%+.3f' % (l, f, v) for (l, f), v in neg))
    pos = ns.most_common(8)
    print('neurons by mean part (most positive 8):', ' '.join('%d.%d:%+.3f' % (l, f, v) for (l, f), v in pos))
