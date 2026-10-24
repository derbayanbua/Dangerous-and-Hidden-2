"""Original-Trefferzonen der Menschen: MODELS\\humanzones.4ds -> orig_cache/humanzones.json

Beleg (docs/re_notes_weapons.md §10a): hd2.exe 0x455670 testet 10 Volumen in fester Reihenfolge; Index = Zone
(0 Körper, 1 Kopf, 2-5 Arme, 6-9 Beine, Helm vorab = 11). Jedes Volumen übernimmt die Weltmatrix des gleichnamigen
Figurgelenks (Skalierung 1). Bezeichnertabelle neben dem String „humanzones“: c f l m h i s t o p.
humanzones.4ds enthält genau diese 10 Kisten (je 24 Vertices) als Frames mit Gelenknamen; die Vertices liegen im
Gelenkraum (Arme entlang +X, Beine entlang -Y wie die Gelenkhüllen der Figur-Skins).
Ausgabe in Godot-Koordinaten (4DS z gespiegelt wie im übrigen Konverter): je Zone Gelenk, Zone, min/max.

Aufruf: pyenv\\Scripts\\python.exe -I fmt_humanzones.py
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import convert_mission as cm  # noqa: E402
import fmt_4ds_hd2skin as hs  # noqa: E402

ZONE_OF = {"c": "torso", "f": "head", "h": "arm", "i": "arm", "l": "arm", "m": "arm",
           "s": "leg", "t": "leg", "o": "leg", "p": "leg"}
ORDER = ["c", "f", "l", "m", "h", "i", "s", "t", "o", "p"]     # Original-Index 0..9


def main():
    d = cm.read_file("models/humanzones.4ds", ["patch.dta", "MODELS.DTA"])
    if d is None:
        print("humanzones.4ds fehlt")
        return 1
    m = hs.read_model(d)
    zones = {}
    for f in m["frames"]:
        name = f["name"].lower()
        if name not in ZONE_OF or not f.get("lods"):
            continue
        vs = f["lods"][0]["vertices"]
        pts = [v["pos"] if isinstance(v, dict) else v[:3] for v in vs]
        mn = [min(p[k] for p in pts) for k in range(3)]
        mx = [max(p[k] for p in pts) for k in range(3)]
        # 4DS -> Godot: z spiegeln
        zones[name] = {"bone": name, "zone": ZONE_OF[name],
                       "min": [round(mn[0], 4), round(mn[1], 4), round(-mx[2], 4)],
                       "max": [round(mx[0], 4), round(mx[1], 4), round(-mn[2], 4)],
                       "bind_pos": [round(f["pos"][0], 4), round(f["pos"][1], 4), round(-f["pos"][2], 4)]}
    out = {"source": "MODELS/humanzones.4ds", "order": ORDER, "zones": [zones[n] for n in ORDER if n in zones]}
    path = os.path.join(cm.CACHE, "humanzones.json")
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=1)
    print(path, len(out["zones"]), "Zonen")
    return 0


if __name__ == "__main__":
    sys.exit(main())
