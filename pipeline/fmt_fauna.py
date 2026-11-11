"""Fauna-Modelle (B-053) in den Missions-Cache schreiben.

Vogelschwarm (Akteurtyp 29) und Fische (Akteurtyp 32) erzeugen ihre Modelle nur im Programmcode:
Vogel = Modellname aus den Akteurparametern (immer "ptacekletacek"), Fisch = fest "ryba" (String in hd2.exe).
convert_mission.py exportiert nur Modelle aus scene2.bin/actors.bin, daher fehlen sie im Cache.
Dieses Skript konvertiert sie nur fuer Missionen, deren interactive.json Voegel bzw. Fische enthaelt.

Aufruf: python fmt_fauna.py [mission ...]   (ohne Argument: alle Missionsordner im Cache)
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import convert_mission as cm  # noqa: E402
import fmt_4ds  # noqa: E402

FISH_MODEL = "ryba"


def models_for(inter):
    names = set()
    for b in inter.get("birds", []):
        nm = str(b.get("params", {}).get("name_?", "") or "").strip().lower()
        if nm:
            names.add(nm)
    if inter.get("fish"):
        names.add(FISH_MODEL)
    return sorted(names)


def main(argv):
    missions = argv or sorted(d for d in os.listdir(cm.CACHE)
                              if os.path.isfile(os.path.join(cm.CACHE, d, "interactive.json")))
    textures = cm.Textures(os.path.join(cm.CACHE, "textures"))
    total = 0
    for m in missions:
        mdir = os.path.join(cm.CACHE, m.lower())
        try:
            with open(os.path.join(mdir, "interactive.json"), encoding="utf-8") as f:
                inter = json.load(f)
        except OSError:
            continue
        for name in models_for(inter):
            data = cm.read_file("models/%s.4ds" % name, ["Models.dta"])
            if data is None:
                print("%s: %s fehlt" % (m, name))
                continue
            mdl = fmt_4ds.read_model(data, quiet=True)
            os.makedirs(os.path.join(mdir, "models"), exist_ok=True)
            cm.model_to_gltf(mdl, textures, "../../textures/", os.path.join(mdir, "models", name + ".glb"))
            total += 1
            print("%s: %s" % (m, name))
    print("Fauna-Modelle: %d geschrieben" % total)


if __name__ == "__main__":
    main(sys.argv[1:])
