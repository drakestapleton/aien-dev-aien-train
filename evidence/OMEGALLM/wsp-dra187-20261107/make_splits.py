"""DRA-187 split generator (external instrument, not product code).
Builds the edit-selection split S and the locked held-out split H of first-action path-copy
records for the round40 Omega tool model. Templates (Task lines, Goal forms) come from the round40
copy grid and the round41 d-item diagnosis set; every path ID is fresh: no `item<digits>` string in
any JSON under round40/data or round41 (files < 50 MB) is reused, and S and H are disjoint.
Usage: python3 make_splits.py OUTDIR"""
import json, random, re, sys, glob, os, hashlib
SRC = '/home/drakestapleton/handoffs/tool-omega-20261104'
out = sys.argv[1]
tasks, forms = set(), set()
for f in ['round40/data/copy-grid.json', 'round41/c2/diag/d-item.json',
          'round40/data/localization-screen.json', 'round40/data/target-jobs.json']:
    for r in json.load(open(os.path.join(SRC, f))):
        p = r.get('prompt')
        if not p:
            continue
        for l in p.split('\n'):
            if l.startswith('Task: '):
                tasks.add(l)
            if l.startswith('Goal: '):
                forms.add(re.sub(r'\d+', '{}', l))
tasks, forms = sorted(tasks), sorted(forms)
used = set()
files = glob.glob(SRC + '/round40/data/*.json') + glob.glob(SRC + '/round41/**/*.json', recursive=True)
for f in files:
    if os.path.getsize(f) < 50 << 20:
        used.update(re.findall(r'item(\d+)', open(f, errors='replace').read()))
def ident(rng, n, pattern):
    """A fresh n-digit ID; a structured pattern with no fresh value left after 200 draws
    falls back to 'random'. Returns (digits, pattern used)."""
    tries = 0
    while True:
        tries += 1
        if pattern != 'random' and tries > 200:
            pattern = 'random'
        if pattern == 'random':
            d = [rng.randrange(10) for _ in range(n)]
            if d[0] == 0:
                continue
        elif pattern == 'run':
            s = rng.randrange(1, 10); step = rng.choice([1, -1])
            d = [(s + step * i) % 10 for i in range(n)]
            if d[0] == 0:
                continue
        else:  # pair: two digits alternate in runs
            a, b = rng.sample(range(1, 10), 2)
            d = [a if (i // 2) % 2 == 0 else b for i in range(n)]
        s = ''.join(map(str, d))
        if s not in used:
            used.add(s)
            return s, pattern
def goal(rng, form):
    k = form.count('{}')
    vals = [rng.randrange(2, 10) if i < k - 1 else rng.randrange(1, 100) for i in range(k)]
    if 'times in a for loop' in form:
        vals = [rng.randrange(2, 10), rng.randrange(1, 6), rng.randrange(1, 100)][:k]
    return form.format(*vals)
def split(name, seed, per_target, per_control):
    rng = random.Random(seed)
    rows = []
    for n, per in [(6, per_target), (7, per_target), (8, per_target), (3, per_control), (4, per_control), (5, per_control)]:
        for i in range(per):
            ids, pat = ident(rng, n, ['random', 'random', 'run', 'pair'][i % 4])
            path = 'jobs/item%s.om' % ids
            p = '%s\nFile: %s\n%s\nState: unread\nAnswer:\n' % (rng.choice(tasks), path, goal(rng, rng.choice(forms)))
            rows.append(dict(split=name, length=n, role='target' if n >= 6 else 'control', pattern=pat,
                             path=path, prompt=p, answer='{"tool":"read_file","path":"%s"}' % path))
    rng.shuffle(rows)
    for i, r in enumerate(rows):
        r['idx'] = i
    js = json.dumps(rows, indent=1).encode()
    rec = b''.join((r['prompt'] + '\x1f' + r['answer']).encode() + b'\0' for r in rows)
    open(os.path.join(out, name + '.json'), 'wb').write(js)
    open(os.path.join(out, name + '.rec'), 'wb').write(rec)
    return len(rows), hashlib.sha256(js).hexdigest(), hashlib.sha256(rec).hexdigest()
print('templates', len(tasks), 'goal forms', len(forms), 'excluded ids', len(used))
print('S', *split('S', 187001, 24, 8))
print('H', *split('H', 187002, 64, 32))
for f in files:
    if os.path.getsize(f) < 50 << 20:
        used.update(re.findall(r'hello(\d+)', open(f, errors='replace').read()))
def gsplit(name, seed, per_target, per_control):
    """Secondary generalisation set (no gate): long numbers inside a code-writing answer, in the
    form of round40 copy-final (4-digit IDs there). Scored on the answer's first line."""
    rng = random.Random(seed)
    rows = []
    for n, per in [(6, per_target), (7, per_target), (8, per_target), (4, per_control), (5, per_control)]:
        for i in range(per):
            ids, pat = ident(rng, n, ['random', 'random', 'run', 'pair'][i % 4])
            p = 'Task: Write Omega that prints hello%s followed by a newline.\nAnswer:\n' % ids
            rows.append(dict(split=name, length=n, role='target' if n >= 6 else 'control', pattern=pat,
                             word='hello' + ids, prompt=p, answer='text msg "hello%s\\n"' % ids))
    rng.shuffle(rows)
    for i, r in enumerate(rows):
        r['idx'] = i
    js = json.dumps(rows, indent=1).encode()
    rec = b''.join(r['prompt'].encode() + b'\0' for r in rows)
    open(os.path.join(out, name + '.json'), 'wb').write(js)
    open(os.path.join(out, name + '.rec'), 'wb').write(rec)
    return len(rows), hashlib.sha256(js).hexdigest(), hashlib.sha256(rec).hexdigest()
print('G', *gsplit('G', 187003, 24, 12))
