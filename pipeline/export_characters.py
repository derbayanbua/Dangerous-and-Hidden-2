"""Original-Figuren einer Mission als skinned glTF mit Originalanimationen exportieren.

Aufruf (venv):  pyenv\\Scripts\\python.exe -I export_characters.py ARCTIC1
  -> orig_cache/characters/<modell>.glb   (Texturen: orig_cache/textures, geteilt mit dem Level)
Figuren: alle Menschen-Akteure (Typ 3) der Mission, die Kommandos und Hunde (Typ 30).
Formate/Belege: docs/re_notes_5ds_skin.md (fmt_4ds_hd2skin, fmt_5ds, skinned_gltf).
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import convert_mission as cm  # noqa: E402
import skinned_gltf  # noqa: E402

# Zuordnung Animationsname -> Original-5DS (Deutung der tschechischen Dateinamen, siehe Notizen)
HUMAN_ANIMS = {
    "idle": "!stani01",
    "walk": "(chuzezbr41",
    "run": "(beh1b6",
    "sprint": "!sprint01",
    "death": "!smrtB1a",
    "jump": "!jump",
    "crouch": "!drepZB",   # dřep = Hocke, mit Waffe (Höhe ~0,38 m)
    "prone": "!leziN",     # leží = liegt (Höhe ~0,15 m)
}
COMMANDO_MODELS = ["en01"]


def main(mission):
    mdir = os.path.join(cm.CACHE, mission.lower())
    scene = json.load(open(os.path.join(mdir, "scene.json"), encoding="utf-8"))
    models = set(COMMANDO_MODELS)
    for a in scene["actors"]:
        if a.get("actor_type") == 3 and a.get("model"):
            models.add(a["model"].lower())
    out_dir = os.path.join(cm.CACHE, "characters")
    os.makedirs(out_dir, exist_ok=True)
    anims = {}
    for k, v in HUMAN_ANIMS.items():
        d = cm.read_file("models/%s.5ds" % v, ["MODELS.DTA"])
        if d is not None:
            anims[k] = d
    tex = cm.Textures(os.path.join(cm.CACHE, "textures"))
    done, failed = [], []
    for m in sorted(models):
        data = cm.read_file("models/%s.4ds" % m, ["patch.dta", "MODELS.DTA"])
        if data is None:
            failed.append((m, "fehlt"))
            continue
        try:
            info = skinned_gltf.export_character(data, anims, tex, "../textures/", os.path.join(out_dir, m + ".glb"))
            done.append((m, len(info["skins"]), sorted(info["animations"])))
        except Exception as e:  # einzelne Modelle dürfen scheitern, werden gemeldet
            failed.append((m, repr(e)[:120]))
    print("Figuren:", done)
    print("Fehler:", failed)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    main(sys.argv[1])
