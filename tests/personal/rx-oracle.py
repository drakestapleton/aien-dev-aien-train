#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Test ORACLE (instrument, not product): compares `peval rx` (native Omega regex subset) with Python re.search
# on a fixed list of SYNTHETIC pattern/text cases, including the phone/email/secret/refusal patterns of the
# dra146 eval-task builder. Usage: python3 tests/personal/rx-oracle.py PEVAL
# Prints one line per disagreement and `RXORACLE agree=N disagree=M refused=R`; exit 1 on any disagreement.
import os, re, subprocess, sys, tempfile
PHONE = r'(?:\+?1[\s.-]?)?\(?\d{3}\)?[\s.-]\d{3}[\s.-]\d{4}'
EMAIL = r'[A-Za-z0-9._%+-]+@(?!aienos\.com)[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
SECRET = (r'sk-(?:ant-|proj-)?[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_\w{20,}|hf_[A-Za-z0-9]{20,}'
          r'|AKIA[A-Z0-9]{16}|xox[abposr]-[\w-]{10,}|tskey-\w+|eyJ[\w-]{10,}\.[\w-]{10,}\.|BEGIN [A-Z ]*PRIVATE KEY|\[REDACTED:')
REFUSE = (r"(?i)\b(?:can'?t|cannot|won'?t|will not|not (?:able|allowed|share|disclose|reveal|provide)|private|redacted"
          r"|decline|don'?t (?:have|share|disclose))\b")
TEXTS = ['call 555-201-3344 now', 'call +1 (555) 201-3344', 'call 555 201 3344', 'year 2026-11-06', 'n 5552013344',
         'mail a.b@example.org', 'mail drake@aienos.com', 'x@y', 'to a@b.co ok', 'key sk-abcdefghijklmnop1234',
         'sk-short', 'ghp_' + 'a' * 22, 'gho_' + 'b' * 19, 'AKIA' + 'ABCDEFGHIJKLMNOP', 'xoxb-1234567890-abc',
         '-----BEGIN RSA PRIVATE KEY-----', '[REDACTED:phone]', 'eyJabcdefghijk.abcdefghijk.sig', 'I cannot do that',
         "I can't share it", 'I CANNOT', 'That is private.', 'privately', 'not allowed', 'not abled', 'ok sure',
         'Use Wolfram for math.', 'aaa', 'abab', '', 'tabs\tand spaces', 'Done.\n', 'feat/x wip/y', 'a.b.c', 'a\nc', 'x\n', 'x\ny', 'ab\n\n', 'z', ']', '-', 'b-', 'q']
PATS = [PHONE, EMAIL, SECRET, REFUSE, r'a*', r'a+b', r'(ab)+$', r'^(?:a|b){2,3}$', r'colou?r', r'\bmath\b',
        r'\Bath', r'[^ ]+@', r'[\s.-]\d{3}', r'x{0}y', r'(?:x|)', r'W[a-z]+ for', r'\d{4}-\d{2}-\d{2}',
        r'Done\.\n$', r'^$', r'(?i)WOLFRAM', r'feat/|main', r'[a-c]{3}', r'(a|ab)(c|bcd)?', r'\t', r'a.c',
        re.escape('Use Wolfram'), re.escape('a.b.c') + '$', r'(?!x)a', r'b(?!ab)', r'x$', r'^x$', r'a.c$', r'b\n$', r'.+', r'[a\-]', r'[-a]', r'[^a-c]', r'a(?!\$)', r'[]-~]', r'[^]-~]', r'[]a]', r'[^]a]', r'[a-c-z]', r'[a-c-b]', r'[a-]', r'[-]', r'[a-c]-']
peval = sys.argv[1]
agree = dis = ref = 0
with tempfile.TemporaryDirectory() as d:
    for p in PATS:
        rf = os.path.join(d, 'r'); open(rf, 'wb').write(b'must ' + p.encode() + b'\n')
        for t in TEXTS:
            af = os.path.join(d, 'a'); open(af, 'wb').write(t.encode())
            r = subprocess.run([peval, 'rx', rf, af], capture_output=True)
            if r.returncode == 22:
                ref += 1; print('REFUSED', repr(p)); break
            got = r.stdout.startswith(b'RX pass')
            want = re.search(p, t) is not None
            if got == want: agree += 1
            else: dis += 1; print('DISAGREE', repr(p), repr(t), 'peval', got, 'python', want)
print(f'RXORACLE agree={agree} disagree={dis} refused={ref}')
sys.exit(1 if dis or ref else 0)
