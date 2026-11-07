"""DRA-187 round40 retention gates on one candidate checkpoint (PREREG section 7). External orchestration only;
sampling and scoring are the native Omega GPU binaries the round40/round41 lanes use. Run inside a spark window.
python3 gates.py CANDIDATE.ck OUTDIR
Reuses round41's lib/repair/checker modules unchanged (as round41/c2/c2lib.py does) and redirects every write
(receipts, scratch, fixtures, results) into OUTDIR, so no round40/round41 file is touched. Order: latency pair
first (base then candidate, the same 64 copy-final prompts, which also give the copies gate), then the gates;
stops at the first failed gate. Resumable across windows (a window lease is at most 20 min): gates already in
OUTDIR/gates.json are skipped, and a task that would overrun WSP_BUDGET seconds (default 1080) is left for the
next window (exit 10). Exit 0 when finished. Prints and writes OUTDIR/gates.json.
Open the window with --quiet exclusive: the latency gate is a timing."""
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
GJ = OUT / 'gates.json'
res = json.loads(GJ.read_text()) if GJ.exists() else dict(candidate=str(CAND), candidate_sha256=sha(CAND), start=utc(), gates={}, windows=[])
assert res['candidate_sha256'] == sha(CAND), 'OUTDIR belongs to another candidate'
res['windows'].append(os.environ['SPARK_WINDOW'])
BUDGET = float(os.environ.get('WSP_BUDGET', '1080')); T0 = time.time()

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

def gate(name, value, ok):
    res['gates'][name] = dict(value=value, pass_=bool(ok), window=os.environ['SPARK_WINDOW'], at=utc()); put()
    print(name, value, 'PASS' if ok else 'FAIL', flush=True)

def t_latency():
    # same 64 copy-final prompts, same harness, base then candidate; also yields the copies gate
    for who, ck in (('base', BASE), ('candidate', CAND)):
        t = time.time(); n = probes(f'latency-{who}-copy', ck, d40('copy-final'))
        res[f'latency_{who}_s'] = round(time.time() - t, 2); res[f'latency_{who}_copy_pass'] = n
    r = res['latency_candidate_s'] / res['latency_base_s']
    gate('latency', round(r, 4), r <= 1.02)
    gate('copies', res['latency_candidate_copy_pass'], res['latency_candidate_copy_pass'] == 64)
def t_screen():
    v = probes('screen', CAND, d40('localization-screen'), True); gate('screen', v, v == 8)
def t_dev():
    rows = cycles('dev-jobs', CAND, d40('dev-jobs'))
    logic = sum(r['pass'] for r in rows if r['job']['fault'] == 'logic')
    controls = sum(r['pass'] for r in rows if r['job']['fault'] != 'logic')
    pairs = {r['job']['pair'] for r in rows if 'pair' in r['job']}
    pp = sum(all(r['pass'] for r in rows if r['job'].get('pair') == p) for p in pairs)
    gate('dev_jobs', dict(logic=logic, controls=controls, pairs=pp), logic >= 72 and controls >= 12 and pp >= 24)
def t_regression():
    v = probes('regression', CAND, d40('regression')); gate('regression', v, v == 685)
def t_retention():
    v = sum(r['pass'] for r in cycles('retention-jobs', CAND, d40('retention-jobs'))); gate('retention', v, v == 847)
def t_story():
    v = score('story-w256', CAND, R40 / 'data/story-final.tok', 256); gate('story_w256', v, v * 10000 <= STORY_R40_W256 * 10025)

# (gate names produced, task, worst-case seconds from round41's task budgets)
TASKS = [(('latency', 'copies'), t_latency, 150), (('screen',), t_screen, 60), (('dev_jobs',), t_dev, 400),
         (('regression',), t_regression, 150), (('story_w256',), t_story, 40), (('retention',), t_retention, 700)]
NAMES = [n for names, _, _ in TASKS for n in names]
for names, task, est in TASKS:
    if any(not res['gates'][n]['pass_'] for n in res['gates']):
        break  # stop at the first failed gate
    if all(n in res['gates'] for n in names):
        continue
    if time.time() - T0 + est > BUDGET:
        put(); print('WINDOW_BUDGET_REACHED', flush=True); sys.exit(10)
    task()
res['all_pass'] = all(n in res['gates'] and res['gates'][n]['pass_'] for n in NAMES)
res['end'] = utc(); put(); print('ALL_PASS' if res['all_pass'] else 'NOT_ALL_PASS', flush=True)
