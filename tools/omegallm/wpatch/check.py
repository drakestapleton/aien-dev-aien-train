#!/usr/bin/env python3
"""Independent external instrument, never imported or invoked by wpatch.

Usage: check.py --build DIR --work DIR [--real ROUND40_CK]
Every command, return code, stdout and elapsed time is printed as JSONL.
Run in a private, previously absent --work directory. Heavy work needs the lane's
CPU lock and taskset wrapper. All fixtures are derived from own-model checkpoints.
"""
import argparse
import hashlib
import json
import math
import mmap
from pathlib import Path
import shutil
import struct
import subprocess
import time

U = struct.Struct('<Q')
F = struct.Struct('<d')
MAGIC = b'OLLMWP01'
BASE_SHA = '7c7b5b5260f2d9453b6076b64e7f23e88341d96498584f2dfaa229c31ad2e346'
passed = 0
commands = 0


def record(**kw):
    print(json.dumps(kw, ensure_ascii=False), flush=True)


def need(ok, label):
    global passed
    if not ok:
        raise AssertionError(label)
    passed += 1
    record(status='PASS', check=label)


def run(*args, expect=0):
    global commands
    t = time.monotonic_ns()
    p = subprocess.run(list(map(str, args)), capture_output=True, text=True)
    commands += 1
    record(command=list(map(str, args)), exit=p.returncode, expected=expect,
           elapsed_ns=time.monotonic_ns()-t, stdout=p.stdout, stderr=p.stderr)
    need(p.returncode == expect, 'exit: ' + ' '.join(map(str, args)))
    return p.stdout


def sha(b):
    return hashlib.sha256(b).digest()


def file_sha(path):
    with open(path, 'rb') as f:
        return hashlib.file_digest(f, 'sha256').digest()


def u(b, o):
    return U.unpack_from(b, o)[0]


def put(b, o, x):
    U.pack_into(b, o, x)


def fnv(b):
    h = 14695981039346656037
    for x in b:
        h = ((h ^ x) * 1099511628211) & 0xffffffffffffffff
    return h


def reseal(b):
    put(b, 112, fnv(memoryview(b)[120:]))
    return b


def f32bits(bits):
    x = F.unpack(U.pack(bits))[0]
    try:
        return struct.pack('<f', x)
    except OverflowError:
        return struct.pack('<f', math.copysign(math.inf, x))


def f32hash(b):
    h = hashlib.sha256()
    p = u(b, 96)
    for o in range(120, 120+8*p, 8*8192):
        end = min(o+8*8192, 120+8*p)
        h.update(b''.join(f32bits(u(b, j)) for j in range(o, end, 8)))
    return h.digest()


def tensors(header):
    _, v,t,d,h,f,l,*_ = header
    out = []
    off = 0
    def add(kind, layer, rows, cols):
        nonlocal off
        out.append((kind, layer, rows, cols, off, rows*cols))
        off += rows*cols
    add(0,0,v,d)
    add(1,0,t,d)
    for ly in range(l):
        for kind, rows, cols in ((2,1,d),(3,d,d),(4,d,d),(5,d,d),(6,d,d),
                                 (7,1,d),(8,d,f),(9,f,d)):
            add(kind,ly,rows,cols)
    add(10,0,1,d)
    return out


def checkpoint(b):
    hd = struct.unpack_from('<15Q', b)
    need(b[:8] == b'OLLMCK02', 'oracle CK02 magic')
    need(len(b) == 120+24*hd[12], 'oracle checkpoint length')
    need(fnv(memoryview(b)[120:]) == hd[14], 'oracle checkpoint FNV')
    ts = tensors(hd)
    need(ts[-1][4]+ts[-1][5] == hd[12], 'oracle checkpoint geometry P')
    return hd, ts


def manifest(path):
    b = path.read_bytes()
    need(b[:8] == MAGIC, 'oracle manifest magic')
    need(path.name == sha(b).hex()+'.wp', 'oracle canonical manifest name')
    need(u(b,8) == len(b), 'oracle manifest length')
    pol, nt, ne, pp = (u(b,o) for o in (16,24,32,40))
    need(pol in (0,1,2), 'oracle policy')
    es = 24 if pol == 0 else 40
    eo = 376+128*nt
    end = eo+es*ne
    need(sha(b[eo:end]) == b[192:224], 'oracle edit identity')
    pn, rn = u(b,224), u(b,232)
    need(end+pn+rn == len(b), 'oracle metadata lengths')
    params = b[end:end+pn].decode('utf-8')
    reason = b[end+pn:].decode('utf-8')
    rows = []
    for i in range(nt):
        o = 376+128*i
        rec = struct.unpack_from('<8Q',b,o)
        rows.append((rec, b[o+64:o+96], b[o+96:o+128]))
    entries = [struct.unpack_from('<'+'Q'*(es//8),b,o) for o in range(eo,end,es)]
    need(all(entries[i][0] < entries[i+1][0] for i in range(ne-1)), 'oracle strict order')
    need(all(e[0] < pp for e in entries), 'oracle indices in bounds')
    return b, rows, entries, params, reason


def oracle(path, base, edited, expected_params, expected_reason):
    m, rows, entries, params, reason = manifest(path)
    hd, ts = checkpoint(base)
    need(m[256:376] == base[:120], 'oracle preserved base header')
    need(tuple(u(m,48+8*i) for i in range(6)) == hd[1:7], 'oracle manifest geometry')
    need(u(m,40) == hd[12], 'oracle manifest P')
    need(m[96:128] == sha(base), 'oracle base SHA')
    need((params,reason) == (expected_params,expected_reason), 'oracle UTF8 provenance')
    out = bytearray(edited)
    pol = u(m,16)
    for e in entries:
        ix, old, new = e[:3]
        need(u(base,120+8*ix) == old and u(edited,120+8*ix) == new, 'oracle entry bits')
        need(old != new and math.isfinite(F.unpack(U.pack(new))[0]), 'oracle entry changed finite')
        need(abs(F.unpack(U.pack(new))[0]) <= 1e6, 'oracle entry magnitude')
        if pol:
            need(e[3:] == (u(base,120+8*(hd[12]+ix)),u(base,120+8*(2*hd[12]+ix))),
                 'oracle saved moments')
            put(out,120+8*(hd[12]+ix),0)
            if pol == 2:
                put(out,120+8*(2*hd[12]+ix),0)
    reseal(out)
    need(m[128:160] == sha(out), 'oracle expected output SHA')
    need(m[160:192] == f32hash(out), 'oracle expected f32 SHA')
    need(len(rows) == len(ts), 'oracle all tensors present')
    for (rec, bh, oh), (kind,ly,rr,cc,off,nn) in zip(rows,ts):
        need(rec[:6] == (kind,ly,rr,cc,64,off), 'oracle tensor record geometry')
        need(rec[6] == sum(off <= e[0] < off+nn for e in entries), 'oracle tensor changed count')
        need(bh == sha(base[120+8*off:120+8*(off+nn)]), 'oracle tensor base SHA')
        need(oh == sha(out[120+8*off:120+8*(off+nn)]), 'oracle tensor output SHA')
    return bytes(out)


def small(build, work):
    wp, ollm = build/'wpatch', build/'ollm'
    basep = work/'base.ck'
    train = work/'train.bin'
    train.write_bytes(b'abc abcd abcde\0'*200)
    run(ollm,'init',basep,256,8,16,2,32,2,2,1,10,3000,1)
    run(ollm,'train',basep,train,2,1)
    base = basep.read_bytes()
    hd, ts = checkpoint(base)
    pp = hd[12]
    edited = bytearray(base)
    # Exercise every tensor, zero sign and an f64 edit that disappears in f32.
    indices = [t[4] for t in ts]
    for ix in indices:
        F.pack_into(edited,120+8*ix,F.unpack_from(base,120+8*ix)[0]+0.001)
    # Least significant mantissa-bit edit, distinct from selected tensor starts.
    put(edited,128,u(base,128)^1)
    reseal(edited)
    ep = work/'edited.ck'
    ep.write_bytes(edited)
    params = '{"delta":0.001,"name":"Ω patch"}\n'
    reason = 'Own-model fixture. Preserve exact rollback.\n'
    pf, rf = work/'params.txt',work/'rationale.txt'
    pf.write_text(params)
    rf.write_text(reason)
    run(wp,'inspect',basep)
    sl = run(wp,'inspect',basep,'wte',0,0,1,0,2)
    need(f'{u(base,120):016x}' in sl and f'{u(base,128):016x}' in sl, 'inspect exact slice bits')
    run(wp,'inspect',basep,'wte',0,0,99999,0,1,expect=27)
    patches = []
    for policy in (0,1,2):
        od = work/f'patches-{policy}'
        od.mkdir()
        path = Path(run(wp,'diff',basep,ep,policy,pf,rf,od).strip())
        patches.append(path)
        expected = oracle(path,base,edited,params,reason)
        shown = json.loads(run(wp,'show',path))
        need(shown['params'] == params and shown['rationale'] == reason, 'show UTF8 provenance')
        run(wp,'validate',path,basep)
        out, rev = work/f'applied-{policy}.ck',work/f'reverted-{policy}.ck'
        run(wp,'apply',path,basep,out)
        need(out.read_bytes() == expected, 'apply exact oracle bytes')
        report = run(wp,'verify',path,out)
        ent = manifest(path)[2]
        survivors = sum(f32bits(e[1]) != f32bits(e[2]) for e in ent)
        need(f'f32_surviving={survivors} changed={len(ent)}' in report, 'verify f32 survival count')
        run(wp,'revert',path,out,rev)
        need(rev.read_bytes() == base, 'revert byte-identical base')
        binding = work/f'binding-{policy}'
        run(wp,'bind',path,out,wp,binding)
        bb = binding.read_bytes()
        need(len(bb) == 168 and bb[:8] == b'OLLMWB01', 'oracle binding format')
        need(bb[8:40] == sha(expected) and bb[40:72] == f32hash(expected), 'oracle binding CK and f32')
        need(bb[72:104] == file_sha(wp) and bb[104:136] == file_sha(path), 'oracle binding runtime and patch')
        need(bb[136:] == sha(bb[:136]), 'oracle binding self digest')
        run(wp,'checkbind',binding,out,wp)
        run(wp,'checkbind',binding,basep,wp,expect=60)
        changed_runtime = work/f'runtime-{policy}'
        changed_runtime.write_bytes(wp.read_bytes()+b'\0')
        run(wp,'checkbind',binding,out,changed_runtime,expect=62)
        badbinding = bytearray(bb)
        badbinding[40] ^= 1
        badbinding[136:] = sha(badbinding[:136])
        bp = work/f'wrong-f32-binding-{policy}'
        bp.write_bytes(badbinding)
        run(wp,'checkbind',bp,out,wp,expect=61)
        badbinding[104] ^= 1
        bp.write_bytes(badbinding)
        run(wp,'checkbind',bp,out,wp,expect=59)
        before = out.read_bytes()
        run(wp,'apply',path,basep,out,expect=52)
        need(out.read_bytes() == before, 'OUT exists preserved')
        run(wp,'apply',path,basep,basep,expect=52)
        run(wp,'revert',path,out,basep,expect=52)
        run(wp,'diff',basep,ep,policy,pf,rf,od,expect=52)
    need(basep.read_bytes() == base, 'BASE never written')
    path = patches[1]
    mb = path.read_bytes()
    eo, es = 376+128*u(mb,24), 40
    def mutated(name, change, code, reseal_entries=True):
        b = bytearray(mb)
        change(b)
        if reseal_entries:
            b[192:224] = sha(b[eo:eo+es*u(b,32)])
        dest = work/(name+'.wp')
        dest.write_bytes(b)
        run(wp,'validate',dest,basep,expect=code)
        out = work/(name+'.ck')
        run(wp,'apply',dest,basep,out,expect=code)
        need(not out.exists(), name+': refusal creates no output')
    mutated('wrong-base-sha',lambda b:b.__setitem__(96,b[96]^1),50)
    mutated('geometry',lambda b:put(b,48,u(b,48)+1),36)
    mutated('shape',lambda b:put(b,376+16,u(b,376+16)+1),37)
    mutated('oob',lambda b:put(b,eo,pp),38)
    mutated('nan',lambda b:put(b,eo+16,0x7ff8000000000000),40)
    mutated('inf',lambda b:put(b,eo+16,0x7ff0000000000000),41)
    mutated('magnitude',lambda b:F.pack_into(b,eo+16,1000001.0),42)
    def unsort(b):
        b[eo:eo+es],b[eo+es:eo+2*es] = b[eo+es:eo+2*es],b[eo:eo+es]
    mutated('unsorted',unsort,39)
    mutated('duplicate',lambda b:put(b,eo+es,u(b,eo)),43)
    mutated('old-bits',lambda b:put(b,eo+8,u(b,eo+8)^1),47)
    mutated('old-moment',lambda b:put(b,eo+24,u(b,eo+24)^1),48)
    mutated('entries-hash',lambda b:b.__setitem__(192,b[192]^1),46,False)
    mutated('tensor-count',lambda b:put(b,424,u(b,424)+1),45)
    mutated('tensor-base-sha',lambda b:b.__setitem__(440,b[440]^1),49)
    mutated('tensor-out-sha',lambda b:b.__setitem__(472,b[472]^1),49)
    mutated('output-sha',lambda b:b.__setitem__(128,b[128]^1),53)
    mutated('output-f32-sha',lambda b:b.__setitem__(160,b[160]^1),54)
    # Canonical hash-name tampering, all patch-consuming commands must reject it.
    bad_dir = work/'flipped'
    bad_dir.mkdir()
    flip = bytearray(mb)
    flip[-1] ^= 1
    bp = bad_dir/path.name
    bp.write_bytes(flip)
    for cmd, rest in [('show',()),('validate',(basep,)),('verify',(work/'applied-1.ck',)),
                      ('apply',(basep,work/'bad-apply.ck')),('revert',(work/'applied-1.ck',work/'bad-revert.ck')),
                      ('bind',(work/'applied-1.ck',wp,work/'bad-bind'))]:
        run(wp,cmd,bp,*rest,expect=30)
    trunc = work/'truncated.wp'
    trunc.write_bytes(mb[:-1])
    run(wp,'validate',trunc,basep,expect=32)
    trunc.write_bytes(mb[:100])
    run(wp,'show',trunc,expect=32)
    run(wp,'diff',basep,basep,0,pf,rf,work,expect=55)
    wrong_m = bytearray(edited)
    put(wrong_m,120+8*pp,u(wrong_m,120+8*pp)^1)
    reseal(wrong_m)
    mp = work/'wrong-m.ck'
    mp.write_bytes(wrong_m)
    run(wp,'diff',basep,mp,0,pf,rf,work,expect=56)
    # Signed zero, subnormal, ties-to-even, overflow, NaN and infinity cast oracle.
    # Unchanged exotic values are permitted; new nonfinite edits are refused above.
    exotic = bytearray(base)
    vals = [0,0x8000000000000000,1,0x3690000000000000,0x3ff0000010000000,
            0x3ff0000030000000,0x47f0000000000000,0x7ff0000000000000,
            0xfff0000000000000,0x7ff8000000000000,0x7fefffffffffffff]
    for i,bits in enumerate(vals):
        put(exotic,120+8*i,bits)
    reseal(exotic)
    xp = work/'exotic.ck'
    xp.write_bytes(exotic)
    xe = bytearray(exotic)
    F.pack_into(xe,120+8*12,0.25)
    reseal(xe)
    xep = work/'exotic-edited.ck'
    xep.write_bytes(xe)
    xd = work/'exotic-patches'
    xd.mkdir()
    patch = Path(run(wp,'diff',xp,xep,0,pf,rf,xd).strip())
    need(patch.read_bytes()[160:192] == f32hash(xe), 'f32 cast boundary vectors')
    run(wp,'validate',patch,xp)
    inspection = run(wp,'inspect',xp)
    wte = next(line for line in inspection.splitlines() if line.startswith('wte '))
    rms = float(wte.split('rms=')[1].split()[0])
    need(math.isfinite(rms) and rms > 0 and 'nonfinite=3' in wte,
         'scaled RMS survives maximum finite f64, counts nonfinite separately')
    need(basep.read_bytes() == base, 'final base identity')


def real(build, work, source):
    wp = build/'wpatch'
    need(file_sha(source).hex() == BASE_SHA, 'real base pinned SHA')
    edited = work/'round40-edited.ck'
    shutil.copyfile(source, edited)
    with edited.open('r+b') as f:
        with mmap.mmap(f.fileno(),0) as mm:
            hd = struct.unpack_from('<15Q',mm)
            ts = tensors(hd)
            off = next(t[4] for t in ts if t[:2] == (9,3))
            need(off == 8162304, 'Wolfram layer3 w2 offset')
            for i in range(10):
                o = 120+8*(off+i)
                F.pack_into(mm,o,F.unpack_from(mm,o)[0]+0.001)
            put(mm,112,fnv(memoryview(mm)[120:]))
            mm.flush()
    pf,rf = work/'params.txt',work/'rationale.txt'
    pf.write_text('{"kind":"w2","layer":3,"entries":10,"delta":0.001}\n')
    rf.write_text('Read-only round40 baseline. Checked patch integration fixture, not a quality claim.\n')
    od = work/'patches'
    od.mkdir()
    patch = Path(run(wp,'diff',source,edited,2,pf,rf,od).strip())
    mb, rows, entries, *_ = manifest(patch)
    need(len(entries) == 10 and all(e[0] == off+i for i,e in enumerate(entries)), 'real ten entry identity')
    run(wp,'validate',patch,source)
    out,rev = work/'round40-applied.ck',work/'round40-reverted.ck'
    run(wp,'apply',patch,source,out)
    run(wp,'verify',patch,out)
    run(wp,'revert',patch,out,rev)
    text = run('sha256sum',source,rev,out)
    need(file_sha(rev).hex() == BASE_SHA, 'real byte-identical revert SHA')
    need(file_sha(source).hex() == BASE_SHA, 'real base unchanged')
    need(file_sha(out) == mb[128:160], 'real output SHA oracle')
    with out.open('rb') as f:
        with mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ) as mm:
            need(f32hash(mm) == mb[160:192], 'real f32 SHA oracle')
    record(real_patch=str(patch), real_hashes=text)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--build',type=Path,required=True)
    p.add_argument('--work',type=Path,required=True)
    p.add_argument('--real',type=Path)
    a = p.parse_args()
    a.build = a.build.resolve()
    a.work = a.work.resolve()
    a.work.mkdir(parents=True,exist_ok=False)
    record(instrument='external Python stdlib only', wpatch_sha256=file_sha(a.build/'wpatch').hex())
    if a.real:
        real(a.build,a.work,a.real.resolve())
    else:
        small(a.build,a.work)
    record(status='PASS', checks=passed, commands=commands, failures=0)


if __name__ == '__main__':
    main()
