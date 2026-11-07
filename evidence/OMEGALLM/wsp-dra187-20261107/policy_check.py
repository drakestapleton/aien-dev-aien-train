"""PREREG section 9 instrument (external, secondary, not a gate).
python3 policy_check.py BASE.ck POLICY0.ck POLICY2.ck WORKDIR
POLICY0.ck = edited checkpoint with Adam m/v unchanged (wpatch policy 0 / wprobe save output).
POLICY2.ck = the same edit applied by wpatch with policy 2 (m and v of changed entries zeroed).
Each of the three is copied into WORKDIR, its header word 10 (TOTAL) is raised from 600 to 601 so that
`ollm train` takes exactly one step (step 600, lr = lr0 (1 - 0.9 * 500/501) by adam.om olrs), and trained one
step on round40 data/train.tok (plain next-token loss; round40 itself trained with a mask on GPU, disclosed).
Edit survival after the step, against the base's own one-step trajectory:
  d0 = w_edit - w_base (before), d1 = w_edit' - w_base' (after); survival = <d1, d0> / <d0, d0>
over the changed entries, plus the largest |d1 - d0| relative to |d0|. Prints one JSON line."""
import json, os, shutil, struct, subprocess, sys
OLLM = os.path.expanduser('~/work/wsp/build/ollm')
TRAIN = os.path.expanduser('~/handoffs/tool-omega-20261104/round40/data/train.tok')
POOL = os.environ.get('POOL', '19')
LOCK = os.path.expanduser('~/handoffs/hive/queen/pool-%s.lock' % POOL)

def weights(p):
    with open(p, 'rb') as f:
        h = struct.unpack('<15Q', f.read(120))
        P = h[12]
        import array
        a = array.array('d'); a.frombytes(f.read(8 * P))
    return h, a

def step(src, dst):
    shutil.copyfile(src, dst)
    with open(dst, 'r+b') as f:
        h = list(struct.unpack('<15Q', f.read(120)))
        assert h[9] == 600 and h[10] == 600, h[9:11]
        h[10] = 601
        f.seek(0); f.write(struct.pack('<15Q', *h))
    out = subprocess.run(['flock', '-w', '7200', '-o', LOCK, 'taskset', '-c', POOL, 'nice', '-n', '10',
                          OLLM, 'train', dst, TRAIN, '601', '1'], capture_output=True, text=True)
    assert out.returncode == 0, (dst, out.returncode, out.stderr)
    return out.stdout.strip()

base, p0, p2, work = sys.argv[1:5]
os.makedirs(work, exist_ok=True)
_, wb = weights(base); _, w0 = weights(p0); _, w2 = weights(p2)
idx = [i for i in range(len(wb)) if wb[i] != w0[i]]
assert idx and all(w0[i] == w2[i] for i in range(len(wb))), 'policy 0 and 2 must share weights'
logs = {k: step(src, os.path.join(work, k + '.ck')) for k, src in (('base', base), ('p0', p0), ('p2', p2))}
_, ab = weights(os.path.join(work, 'base.ck'))
res = dict(changed=len(idx), train_lines=logs)
for k in ('p0', 'p2'):
    _, a = weights(os.path.join(work, k + '.ck'))
    num = den = 0.0; worst = 0.0
    for i in idx:
        d0 = w0[i] - wb[i]; d1 = a[i] - ab[i]
        num += d1 * d0; den += d0 * d0
        worst = max(worst, abs(d1 - d0) / abs(d0))
    res[k] = dict(survival=num / den, max_rel_change=worst)
print(json.dumps(res))
