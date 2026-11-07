"""DRA-187 arm runner (external instrument, not product code).
python3 runarms.py ARMS.json OUTDIR
ARMS.json: [{"name": str, "split": "S"|"H"|"G"|"D", "mode": "gen"|"probe", "ck": path (optional,
default round40), "hooks": [[K, L, I, A], ...]}]. Each arm runs `wprobe` once on one pool core
(flock -w on the pool lock, taskset, nice 10), writes OUTDIR/<name>.out, scores it (score.py for gen,
rank.py for probe) and appends a line with the command, sha256s, start/end UTC and wall seconds to
OUTDIR/runs.jsonl. An arm whose .out already exists is skipped."""
import hashlib, json, os, subprocess, sys, time
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
WP = os.environ.get('WPROBE', os.path.expanduser('~/work/wsp/build/wprobe'))
BASE = os.path.expanduser('~/.local/share/omega-tool-model/round40/model.ck')
MERGES = os.path.expanduser('~/.local/share/omega-tool-model/round40/merges.bin')
POOL = os.environ.get('POOL', '19')
LOCK = os.path.expanduser('~/handoffs/hive/queen/pool-%s.lock' % POOL)
NN = '64'

def sha(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for c in iter(lambda: f.read(1 << 20), b''):
            h.update(c)
    return h.hexdigest()

def now():
    return datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

arms, out = json.load(open(sys.argv[1])), sys.argv[2]
os.makedirs(out, exist_ok=True)
for a in arms:
    o = os.path.join(out, a['name'] + '.out')
    if os.path.exists(o):
        continue
    ck = a.get('ck', BASE)
    rec = os.path.join(HERE, 'splits', a['split'] + '.rec')
    hooks = [str(x) for h in a.get('hooks', []) for x in h]
    if a['mode'] == 'gen':
        cmd = [WP, 'gen', ck, MERGES, NN, rec] + hooks
    else:
        cmd = [WP, 'probe', ck, MERGES, rec] + hooks
    full = ['flock', '-w', '7200', '-o', LOCK, 'taskset', '-c', POOL, 'nice', '-n', '10'] + cmd
    t0, s0 = time.time(), now()
    with open(o + '.tmp', 'wb') as f:
        rc = subprocess.run(full, stdout=f).returncode
    t1 = time.time()
    if rc != 0:
        print('FAIL', a['name'], rc, flush=True)
        os.rename(o + '.tmp', o + '.failed')
        continue
    os.rename(o + '.tmp', o)
    js = os.path.join(HERE, 'splits', a['split'] + '.json')
    tool = 'score.py' if a['mode'] == 'gen' else 'rank.py'
    sc = subprocess.run(['python3', os.path.join(HERE, tool), js, o] + ([os.path.join(out, a['name'] + '.score.json')] if a['mode'] == 'gen' else []),
                        capture_output=True, text=True).stdout
    line = dict(name=a['name'], split=a['split'], mode=a['mode'], cmd=cmd, hooks=a.get('hooks', []), ck_sha256=sha(ck),
                wprobe_sha256=sha(WP), out_sha256=sha(o), start=s0, end=now(), wall_s=round(t1 - t0, 1), score=sc.strip())
    with open(os.path.join(out, 'runs.jsonl'), 'a') as f:
        f.write(json.dumps(line) + '\n')
    print(a['name'], line['wall_s'], 's |', sc.strip().replace('\n', ' | '), flush=True)
