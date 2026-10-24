"""Zerstörbare Szenenobjekte: Liste der Schadensmodelle MODELS\\d<Modell>.4ds -> orig_cache/dmodels.json.

Original (docs/re_notes_script_anims.md §5, hd2.exe):
  - 0x43B000 Treffer an einem zerstörbaren Frame: HP (+8) > Schaden -> HP -= Schaden; sonst 0x43CCA0.
  - 0x43CCA0/0x43CE40: lädt beim ersten Durchschlagen das Modell "d%s" (String 0x832CD8, %s = Modellname ohne Pfad
    und Endung), liest Frame-Parameter "version" (Standard 100, 0x43CD20) und "sound" (Standard -1) und löst OnDeath
    des Skripts aus (0x41D920 an 0x43D118).
Ausgabe: {"<modell klein>": {"dmodel": "dm_tut_panak01", "frames": {"Box01": "matid12"}}} für alle Modelle,
zu denen ein d<modell>.4ds existiert (nur Analyse der eigenen Installation).
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import convert_mission as cm  # noqa: E402
import dta_extract  # noqa: E402
import fmt_4ds  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ORIG = os.environ.get("DH2_ORIG") or os.path.join(ROOT, "HD2_orig")


def main():
    names = set()
    for a in ("patch.dta", "MODELS.DTA"):
        arc = dta_extract.Archive(os.path.join(ORIG, a))
        for e in arc.entries:
            n = e[0].lower()
            if n.startswith("models\\") and n.endswith(".4ds"):
                names.add(n[7:-4])
    out = {}
    for n in sorted(names):
        if n.startswith("d") and n[1:] in names:
            frames = {}
            try:
                m = fmt_4ds.read_model(cm.read_file("models/%s.4ds" % n, ["patch.dta", "Models.dta"]), quiet=True)
                frames = {f["name"]: f.get("params") or "" for f in m["frames"]}
            except Exception as ex:  # nicht lesbare Modelle: nur Name
                frames = {"_error": str(ex)}
            out[n[1:]] = {"dmodel": n, "frames": frames}
    dst = os.path.join(cm.CACHE, "dmodels.json")
    with open(dst, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=0, ensure_ascii=False)
    print("dmodels.json: %d zerstörbare Modelle" % len(out))


if __name__ == "__main__":
    main()
