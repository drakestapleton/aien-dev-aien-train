"""DRA-187 diagnosis split D (external instrument): unread-state jobs/item rows of the round40 copy
grid (lengths 3 to 6) and of the round41 d-item diagnosis set (3, 4, 5, 7, 8), as wprobe probe records."""
import json, sys, os, hashlib
SRC = '/home/drakestapleton/handoffs/tool-omega-20261104'
rows = []
for r in json.load(open(SRC + '/round40/grid-selected.json')):
    if r['stem'] == 'jobs/item':
        rows.append(dict(src='round40-grid', length=r['length'], pattern=r['pattern'], path=r['path'], prompt=r['prompt'], answer=r['answer']))
for r in json.load(open(SRC + '/round41/c2/diag/d-item.json')):
    if r['state'] == 'unread':
        rows.append(dict(src='round41-d-item', length=r['length'], pattern=r['pattern'], path=r['path'], prompt=r['prompt'], answer=r['answer']))
for i, r in enumerate(rows):
    r['idx'] = i; r['role'] = 'target' if r['length'] >= 6 else 'control'
out = sys.argv[1]
js = json.dumps(rows, indent=1).encode()
rec = b''.join((r['prompt'] + '\x1f' + r['answer']).encode() + b'\0' for r in rows)
open(os.path.join(out, 'D.json'), 'wb').write(js); open(os.path.join(out, 'D.rec'), 'wb').write(rec)
print('D', len(rows), hashlib.sha256(js).hexdigest(), hashlib.sha256(rec).hexdigest())
