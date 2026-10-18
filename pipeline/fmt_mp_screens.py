"""Original-Ladebildschirm und MP-Spawnzonen-Karte einer Mission -> orig_cache (lokal, gitignored).

  MISSIONS\\<m>\\loader.4ds -> orig_cache/<m>/loader_layout.json  (Ladebildschirm: Hintergrund X_NMN01-12,
                                Ladebalken LOADINGBAR.BMP, Textfelder; MP zusaetzlich Kartenbild MAPA_*, Flaggen)
  MISSIONS\\<m>\\map.4ds    -> orig_cache/<m>/map_layout.json     (nur MP-Besetzung/-Aufgaben: Spawnzonen-Karte
                                'mapa' = Kartenbild MAPA_*, je Zone 'zoneN' mit 'alliedN'/'axisN' (Besitzerflagge)
                                und 'zone_disabledN', Auswahlmarke 'selectzone')
  Texturen -> orig_cache/ui/menu/textures/*.png (wie tools/_menu_export.py), Vorschau <m>/<name>_preview.png.

Format wie orig_cache/ui/menu/layout/*.json: Frames mit Bildschirmrechteck und Dreiecken (px @1024x768 = x*1024,
-y*1024 der 4DS-Einheiten, UV). map.4ds liegt um den Ursprung (eigene Kamera im Original) -> Koordinaten werden
im Spiel auf die Kartenflaeche skaliert.

Aufruf: pyenv\\Scripts\\python.exe -I fmt_mp_screens.py [--preview] [ORDNER ...]
        (ohne Ordner: alle Kartenordner in orig_cache mit scene.glb)
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
import convert_mission as cm  # noqa: E402
import fmt_4ds  # noqa: E402
import _menu_4ds  # noqa: E402,F401  (Materialregel der Menuemodelle: Alpha-Map nur ohne 0x01000000)
import _menu_layout as L  # noqa: E402
import _menu_export as E  # noqa: E402

TDIR = os.path.join(cm.CACHE, "ui", "menu", "textures")


def mission_model(mdir, name):
    d = cm.read_file("missions/%s/%s" % (mdir, name), ["Missions.dta"])
    return fmt_4ds.read_model(d) if d else None


def export(mdir, name, out_name, done, missing, preview):
    mdl = mission_model(mdir, name)
    if mdl is None:
        return None
    orig = L.M4.load
    L.M4.load = lambda _n: mdl
    try:
        el = L.layout(name)
    finally:
        L.M4.load = orig
    for e in el:
        if "_tris" in e:
            e["tris"] = [[tn or "", [[round(L.to_px(v)[0], 2), round(L.to_px(v)[1], 2), round(v[3], 5), round(v[4], 5)]
                                     for v in tri]] for tn, tri in e["_tris"]]
    frames = L.strip(el)
    texs = sorted({g["texture"] for e in frames for g in e.get("groups", []) if g["texture"]})
    for t in texs:
        E.export_tex(t, TDIR, done, missing)
    names = {e["name"]: e for e in frames}
    for e in frames:
        p, root = e.get("parent"), None
        while p:
            root = p
            pe = names.get(p)
            p = pe.get("parent") if pe else None
        e["root"] = root
    out = os.path.join(cm.CACHE, mdir.lower(), out_name + ".json")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    json.dump({"model": "MISSIONS\\%s\\%s" % (mdir, name), "screen": "1024x768 reference; px = x*1024, py = -y*1024",
               "textures": texs, "frames": frames}, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    if preview:
        if out_name == "map_layout":
            # um den Ursprung -> fuer die Vorschau in die Bildmitte schieben
            for e in el:
                if "_tris" in e:
                    e["_tris"] = [(tn, [(v[0] + 0.5, v[1] - 0.375, v[2], v[3], v[4]) for v in tri]) for tn, tri in e["_tris"]]
        L.render(el, os.path.join(cm.CACHE, mdir.lower(), out_name.replace("_layout", "") + "_preview.png"),
                 skip=lambda e: not e.get("_tris"), outline=False)
    return len(frames)


def main(args):
    preview = "--preview" in args
    dirs = [a for a in args if not a.startswith("--")]
    if not dirs:
        dirs = sorted(d.upper() for d in os.listdir(cm.CACHE)
                      if os.path.isfile(os.path.join(cm.CACHE, d, "scene.glb")))
    os.makedirs(TDIR, exist_ok=True)
    done, missing = {}, set()
    for m in dirs:
        a = export(m, "loader.4ds", "loader_layout", done, missing, preview)
        b = export(m, "map.4ds", "map_layout", done, missing, preview)
        print("%-20s loader %s  map %s" % (m, a, b))
    print("Texturen:", sum(1 for v in done.values() if v), "fehlend:", sorted(missing))


if __name__ == "__main__":
    main(sys.argv[1:])
