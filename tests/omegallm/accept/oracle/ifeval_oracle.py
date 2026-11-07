#!/usr/bin/env python3
"""IFEval verification oracle for the DRA-124 acceptance suite (PREREG.md section 5).

Not part of the runner. It re-checks responses with the unchanged upstream checker
(google-research@0eebfd40 instruction_following_eval, vendored under data/upstream/) so the
Omega checkers in accept.om can be compared against it.

  ifeval_oracle.py check UPSTREAM RESP     every RESP line's "ours" verdict must equal upstream strict
  ifeval_oracle.py selftest UPSTREAM RESP GPT4 OUT
                                           OUT = self-test lines (row + response + expect) for the
                                           ref, garbage and GPT-4 responses of every RESP row

The upstream modules import nltk, langdetect, absl and immutabledict. The shims below provide only
what the registered rows reach (nltk RegexpTokenizer(r"\\w+"), absl logging); any other path raises,
so a registered row that needs punkt sentences or language detection fails loudly here.
"""
import json
import os
import re
import sys
import types

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "data", "upstream"))


def _shims():
    nltk = types.ModuleType("nltk")
    tok = types.ModuleType("nltk.tokenize")

    class RegexpTokenizer:
        def __init__(self, pattern):
            self._re = re.compile(pattern)

        def tokenize(self, text):
            return self._re.findall(text)

    def _unavailable(*a, **k):
        raise RuntimeError("nltk path not available to the oracle")

    tok.RegexpTokenizer = RegexpTokenizer
    nltk.tokenize = tok
    nltk.word_tokenize = _unavailable
    nltk.data = types.SimpleNamespace(load=_unavailable)
    sys.modules["nltk"] = nltk
    sys.modules["nltk.tokenize"] = tok

    ld = types.ModuleType("langdetect")

    class LangDetectException(Exception):
        pass

    ld.LangDetectException = LangDetectException
    ld.detect = _unavailable
    sys.modules["langdetect"] = ld

    absl = types.ModuleType("absl")
    absl.logging = types.SimpleNamespace(error=lambda *a, **k: None, info=lambda *a, **k: None)
    sys.modules["absl"] = absl
    sys.modules["absl.logging"] = absl.logging

    im = types.ModuleType("immutabledict")
    im.immutabledict = dict
    sys.modules["immutabledict"] = im


_shims()
from instruction_following_eval import evaluation_lib  # noqa: E402


def rows(path):
    out = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            if line.strip():
                r = json.loads(line)
                out[r["key"]] = r
    return out


def strict(row, response):
    inp = evaluation_lib.InputExample(
        key=row["key"],
        instruction_id_list=row["instruction_id_list"],
        prompt=row["prompt"],
        kwargs=row["kwargs"],
    )
    return evaluation_lib.test_instruction_following_strict(inp, {row["prompt"]: response}).follow_all_instructions


def check(upstream, resp):
    up = rows(upstream)
    n = bad = passed = 0
    with open(resp, encoding="utf-8") as f:
        for line in f:
            r = json.loads(line)
            v = strict(up[r["key"]], r["response"])
            ours = r["ours"] == 0
            n += 1
            passed += v
            if v != ours:
                bad += 1
                print("MISMATCH", r["key"], "upstream", v, "ours", ours)
    print(f"oracle check rows={n} upstream_pass={passed} mismatches={bad}")
    return 1 if bad or n == 0 else 0


def selftest(upstream, resp, gpt4, out):
    up = rows(upstream)
    g = {}
    with open(gpt4, encoding="utf-8") as f:
        for line in f:
            if line.strip():
                r = json.loads(line)
                g[r["prompt"]] = r["response"]
    n = t = 0
    with open(resp, encoding="utf-8") as f, open(out, "w", encoding="utf-8") as o:
        for line in f:
            r = json.loads(line)
            row = up[r["key"]]
            cand = [r["response"], "zq"] + ([g[row["prompt"]]] if row["prompt"] in g else [])
            for response in cand:
                e = strict(row, response)
                d = dict(row)
                d["response"] = response
                d["expect"] = e
                o.write(json.dumps(d, ensure_ascii=False) + "\n")
                n += 1
                t += e
    print(f"oracle selftest lines={n} expect_true={t}")
    return 0


if __name__ == "__main__":
    a = sys.argv[1:]
    if len(a) == 3 and a[0] == "check":
        sys.exit(check(a[1], a[2]))
    if len(a) == 5 and a[0] == "selftest":
        sys.exit(selftest(a[1], a[2], a[3], a[4]))
    sys.exit(2)
