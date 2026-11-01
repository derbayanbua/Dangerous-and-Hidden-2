"""B-035: Glow-Frames (Visual 6, „Lichthof/Flare“) einer Mission aus scene.4ds exportieren.

convert_mission.py legt Glow-Frames nur als leere Knoten (extras.visual = 6) in scene.glb an; die Glow-Elemente
(f32 Position, f32 Größe, u16 Material, fmt_4ds.read_frame) gehen dabei verloren. Dieses Werkzeug schreibt sie nach
orig_cache/<mission>/glows.json: {"glows": [{"name", "elements": [{"pos", "size", "texture"}]}]}.
Texturen liegen bereits in orig_cache/textures (Name ohne Pfad, .png wie convert_mission).

Aufruf: python -I tools/fmt_glows.py [MISSION ...]   (ohne Angabe: alle Missionen mit scene.4ds)
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import convert_mission as cm  # noqa: E402
import fmt_4ds  # noqa: E402


def glows_of(mission):
    data = cm.read_file("missions/%s/scene.4ds" % mission.upper(), ["Missions.dta"])
    if data is None:
        return None
    mdl = fmt_4ds.read_model(data, quiet=True)
    mats = mdl["materials"]
    out = []
    for fr in mdl["frames"]:
        if fr["type"] != fmt_4ds.FRAME_VISUAL or fr.get("visual") != fmt_4ds.VIS_GLOW:
            continue
        els = []
        for pos, size, mat in fr.get("glows", []):
            tex = ""
            if 1 <= mat <= len(mats):
                tex = mats[mat - 1].get("diffuse_map") or ""
            els.append({"pos": pos, "size": size, "material": mat, "texture": tex})
        out.append({"name": fr["name"], "render_flags": fr.get("render_flags", 0), "elements": els})
    return out


def main(argv):
    missions = argv or sorted(d for d in os.listdir(cm.CACHE) if os.path.isfile(os.path.join(cm.CACHE, d, "scene.glb")))
    for m in missions:
        try:
            g = glows_of(m)
        except Exception as ex:  # noqa: BLE001 – einzelne Mission darf scheitern
            print("%s: Fehler %s" % (m, ex))
            continue
        if g is None:
            print("%s: keine scene.4ds" % m)
            continue
        dst = os.path.join(cm.CACHE, m.lower(), "glows.json")
        with open(dst, "w", encoding="utf-8") as f:
            json.dump({"mission": m.upper(), "glows": g}, f, indent=1)
        print("%s: %d Glow-Frames" % (m, len(g)))


if __name__ == "__main__":
    main(sys.argv[1:])
