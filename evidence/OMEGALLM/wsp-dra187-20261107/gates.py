"""DRA-187 round40 retention gates on one candidate checkpoint (PREREG section 7). External orchestration only;
sampling and scoring are the native Omega GPU binaries the round40/round41 lanes use. Run inside a spark window.
python3 gates.py CANDIDATE.ck OUTDIR
Reuses round41's lib/repair/checker modules unchanged (as round41/c2/c2lib.py does) and redirects every write
(receipts, scratch, fixtures, results) into OUTDIR, so no round40/round41 file is touched. Order: latency pair
first (base then candidate, the same 64 copy-final prompts), then the gates; stops at the first failed gate.
Prints and writes OUTDIR/gates.json."""
import json, os, sys, time
from pathlib import Path
R41 = Path('/home/drakestapleton/handoffs/tool-omega-20261104/round41')
sys.path.insert(0, str(R41))
import lib, repair, checker
OUT = Path(sys.argv[2]).resolve(); OUT.mkdir(parents=True, exist_ok=True)
for m in (lib, repair, checker, checker.prior):
    m.R = OUT
checker.prior.FIX = OUT / 'fixtures'
for d in ('fixtures', 'receipts', 'results', 'data'):
    (OUT / d).mkdir(exist_ok=True)
from lib import read, save, sha, utc, sample, score
assert os.environ.get('SPARK_WINDOW'), 'run inside spark-window'
CAND = Path(sys.argv[1]).resolve()
BASE = Path('/home/drakestapleton/.local/share/omega-tool-model/round40/model.ck')
BASE_SHA = '7c7b5b5260f2d9453b6076b64e7f23e88341d96498584f2dfaa229c31ad2e346'
R40 = lib.R40
STORY_R40_W256 = 1190843  # round41 state.json final-round40-story (read only)
assert sha(BASE) == BASE_SHA
res = dict(candidate=str(CAND), candidate_sha256=sha(CAND), window=os.environ['SPARK_WINDOW'], start=utc(), gates={})

def d40(n): return read(R40 / f'data/{n}.json')
def probes(label, ck, rows, first_request=False):
    answers = sample(label, ck, [x['prompt'] for x in rows]); out = []
    for i, (row, raw) in enumerate(zip(rows, answers)):
        d = dict(index=i, kind=row['kind'], prompt=row['prompt'], expected=row['answer'], raw_output=raw)
        d.update({'pass': repair.check_answer(raw, row)} if first_request else checker.check(raw, row, f'{label}-{i}'))
        out.append(d)
    save(f'results/{label}.json', out); return sum(x['pass'] for x in out)
def cycles(label, ck, jobs):
    out = repair.jobs_run(jobs, lambda lab, prompts: sample(lab, ck, prompts), label)
    save(f'results/{label}.json', out); return out
def put():
    (OUT / 'gates.json').write_text(json.dumps(res, indent=2))

# latency pair: same prompts, same harness, base then candidate
copies = d40('copy-final')
for who, ck in (('base', BASE), ('candidate', CAND)):
    t = time.time(); n = probes(f'latency-{who}-copy', ck, copies)
    res[f'latency_{who}_s'] = round(time.time() - t, 2); res[f'latency_{who}_copy_pass'] = n
res['latency_ratio'] = res['latency_candidate_s'] / res['latency_base_s']
put()

def gate(name, value, ok):
    res['gates'][name] = dict(value=value, pass_=bool(ok)); put(); print(name, value, 'PASS' if ok else 'FAIL', flush=True)
    return ok

v = probes('screen', CAND, d40('localization-screen'), True); ok = gate('screen', v, v == 8)
if ok:
    rows = cycles('dev-jobs', CAND, d40('dev-jobs'))
    logic = sum(r['pass'] for r in rows if r['job']['fault'] == 'logic')
    controls = sum(r['pass'] for r in rows if r['job']['fault'] != 'logic')
    pairs = {r['job']['pair'] for r in rows if 'pair' in r['job']}
    pp = sum(all(r['pass'] for r in rows if r['job'].get('pair') == p) for p in pairs)
    ok = gate('dev_jobs', dict(logic=logic, controls=controls, pairs=pp), logic >= 72 and controls >= 12 and pp >= 24)
if ok:
    v = probes('regression', CAND, d40('regression')); ok = gate('regression', v, v == 685)
if ok:
    v = sum(r['pass'] for r in cycles('retention-jobs', CAND, d40('retention-jobs'))); ok = gate('retention', v, v == 847)
if ok:
    v = res['latency_candidate_copy_pass']; ok = gate('copies', v, v == 64)
if ok:
    v = score('story-w256', CAND, R40 / 'data/story-final.tok', 256); ok = gate('story_w256', v, v * 10000 <= STORY_R40_W256 * 10025)
gate('latency', round(res['latency_ratio'], 4), res['latency_ratio'] <= 1.02)
res['end'] = utc(); res['all_pass'] = all(g['pass_'] for g in res['gates'].values()) and len(res['gates']) == 7
put(); print('ALL_PASS' if res['all_pass'] else 'NOT_ALL_PASS', flush=True)
