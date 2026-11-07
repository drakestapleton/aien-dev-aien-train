"""ORACLE for DRA-187 scoring: a reference used only to check tools/omegallm/wscore/wscore.om.
It is not the scorer; runs score with wscore. python3 oracle_score.py SPLIT.json GEN.out [OUT.json]
GEN.out holds `G idx<TAB>escaped text` lines from `wprobe gen`. S/H rows pass when round40's
check_answer passes; it is imported from round40/repair.py (sha256 df025230...d206 when this was
written), not copied. G rows (rows with `word`) pass when the stripped first line of the text equals
the answer. Prints counts by role and length; OUT.json gets the per-row results."""
import json, sys, collections
sys.path.insert(0, '/home/drakestapleton/handoffs/tool-omega-20261104/round40')
from repair import check_answer

def unescape(s):
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c != '\\':
            out.append(c); i += 1; continue
        n = s[i + 1]
        if n == 'x':
            out.append(chr(int(s[i + 2:i + 4], 16))); i += 4; continue
        out.append({'t': '\t', 'n': '\n', 'r': '\r', '"': '"', '\\': '\\'}[n]); i += 2
    return ''.join(out)

rows = json.load(open(sys.argv[1]))
gen = {}
for line in open(sys.argv[2], encoding='utf-8', errors='replace'):
    if line.startswith('G '):
        k, _, t = line[2:].rstrip('\n').partition('\t')
        gen[int(k)] = unescape(t)
assert len(gen) == len(rows), (len(gen), len(rows))
res, tab = [], collections.Counter()
for r in rows:
    raw = gen[r['idx']]
    if 'word' in r:
        ok = raw.split('\n')[0].strip() == r['answer']
    else:
        ok = check_answer(raw, r)
    res.append(dict(idx=r['idx'], length=r['length'], role=r['role'], pattern=r['pattern'], pass_=ok, raw=raw))
    tab[(r['role'], r['length'], ok)] += 1
tot = collections.Counter()
for (role, n, ok), c in sorted(tab.items()):
    tot[(role, ok)] += c
for role in ('target', 'control'):
    p, f = tot[(role, True)], tot[(role, False)]
    by = ' '.join('L%d %d/%d' % (n, tab[(role, n, True)], tab[(role, n, True)] + tab[(role, n, False)])
                  for n in sorted({r['length'] for r in rows if r['role'] == role}))
    print('%s %d/%d  %s' % (role, p, p + f, by))
if len(sys.argv) > 3:
    json.dump(res, open(sys.argv[3], 'w'), indent=1)
