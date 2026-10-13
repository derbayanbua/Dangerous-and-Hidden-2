"""Testet fmt_4ds über alle extrahierten 4DS-Dateien und fasst Fehlerursachen zusammen."""
import collections
import glob
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fmt_4ds  # noqa: E402

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
root = sys.argv[1]
files = glob.glob(os.path.join(root, "**", "*.4ds"), recursive=True)
ok = 0
reasons = collections.Counter()
examples = {}
for f in files:
    d = open(f, "rb").read()
    try:
        m = fmt_4ds.read_model(d, quiet=True)
    except Exception as ex:  # noqa: BLE001
        key = "Ausnahme: " + str(ex).split("@")[0][:70]
        reasons[key] += 1
        examples.setdefault(key, f)
        continue
    if m.get("stop"):
        key = m["stop"].split("(Frame")[0]
        reasons[key] += 1
        examples.setdefault(key, f + "  " + m["stop"])
    elif m["end"] not in (len(d), len(d) - 1):
        key = "Rest am Ende"
        reasons[key] += 1
        examples.setdefault(key, f)
    else:
        ok += 1
print("Dateien:", len(files), "vollständig:", ok)
for k, v in reasons.most_common():
    print("%5d  %s\n        z.B. %s" % (v, k, examples[k]))
