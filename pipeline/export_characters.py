"""Original-Figuren einer Mission als skinned glTF mit Originalanimationen exportieren.

Aufruf (venv):  pyenv\\Scripts\\python.exe -I export_characters.py ARCTIC1
                pyenv\\Scripts\\python.exe -I export_characters.py --all   (alle Figuren im Cache neu)
  -> orig_cache/characters/<modell>.glb   (Texturen: orig_cache/textures, geteilt mit dem Level)
Figuren: alle Menschen-Akteure (Typ 3) der Mission, die Kommandos und Hunde (Typ 30).
Formate/Belege: docs/re_notes_5ds_skin.md (fmt_4ds_hd2skin, fmt_5ds, skinned_gltf).
Waffenhaltungen (Oberkörper-Schicht, Clips h_*): export_weapons.HOLD_SETS (TABLES\\anim.sav).
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import convert_mission as cm  # noqa: E402
import export_weapons  # noqa: E402
import fmt_4ds_hd2skin  # noqa: E402
import human_anims  # noqa: E402
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
    # Verbandskasten (Ganzkörper, kniend): anim.sav Menschentabelle 0x856 „!medik01“ (Kamerad versorgen),
    # „!medik“ (kniend, 4,2 s) für die Selbstversorgung [P: Zuordnung über Länge/Haltung]
    "medic": "!medik01",
    "medic_self": "!medik",
    # Bedienhaltungen an Waffenstellungen: anim.sav Tabelle ab 0x1B36C (je Zeile 3 × char[20]):
    # (mg42_stand/(w97_stand, (mg42crouch/(w97_crouch, (mg42lie, (jeep1919/(flaksed  [B Daten; Zuordnung zur
    # Stellung über Modellname und SEAT-Haltungsziffer 2/3/6 = stehend/hockend/liegend, docs/re_notes_weapons.md §11]
    "emp_mg42_stand": "(mg42_stand",
    "emp_mg42crouch": "(mg42crouch",
    "emp_mg42lie": "(mg42lie",
    "emp_w97_stand": "(w97_stand",
    "emp_w97_crouch": "(w97_crouch",
    "emp_jeep1919": "(jeep1919",
    "emp_flaksed": "(flaksed",
}
HUMAN_ANIMS.update(export_weapons.hold_anims())
# Bewegung je Haltung/Richtung/Gangart, Haltungswechsel, Lehnen, Tode, Treffer, Gefangener, Messer … aus
# TABLES\anim.sav (human_anims.py); Zuordnungstabelle -> orig_cache/characters/human_anims.json
_REF = fmt_4ds_hd2skin.read_model(cm.read_file("models/en01.4ds", ["patch.dta", "MODELS.DTA"]))
_HA, HUMAN_TABLE = human_anims.build(_REF)
HUMAN_ANIMS.update(_HA)
COMMANDO_MODELS = ["en01"]
# Haltungen sind Oberkörper-Schichten (das Original legt sie über die Bewegung): Becken, Beine und
# Kamera-/Haltungsdummies weglassen, damit die Bewegungsanimation dort wirkt.
LOWER = {"a", "o", "p", "q", "r", "s", "t", "u", "v", "camera3rd", "camerafpv", "lie1", "lie2", "lie3", "lie4",
         "stand1", "stand2", "stand3", "stand4", "kneel1", "kneel2"}


def channel_filter(aname, frame):
    return not (aname.startswith("h_") and frame.lower() in LOWER)


def export(models):
    out_dir = os.path.join(cm.CACHE, "characters")
    os.makedirs(out_dir, exist_ok=True)
    json.dump(HUMAN_TABLE, open(os.path.join(out_dir, "human_anims.json"), "w", encoding="utf-8"), ensure_ascii=False,
              indent=1)
    anims = {}
    for k, v in HUMAN_ANIMS.items():
        d = cm.read_file("models/%s.5ds" % v, ["patch.dta", "MODELS.DTA"])
        if d is not None:
            anims[k] = d
        else:
            print("Animation fehlt:", k, v)
    tex = cm.Textures(os.path.join(cm.CACHE, "textures"))
    done, failed = [], []
    for m in sorted(models):
        data = cm.read_file("models/%s.4ds" % m, ["patch.dta", "MODELS.DTA"])
        if data is None:
            failed.append((m, "fehlt"))
            continue
        try:
            info = skinned_gltf.export_character(data, anims, tex, "../textures/", os.path.join(out_dir, m + ".glb"),
                                                 channel_filter=channel_filter)
            done.append((m, len(info["skins"]), len(info["animations"])))
        except Exception as e:  # einzelne Modelle dürfen scheitern, werden gemeldet
            failed.append((m, repr(e)[:120]))
    print("Figuren:", done)
    print("Fehler:", failed)


def main(mission):
    if mission == "--all":
        cdir = os.path.join(cm.CACHE, "characters")
        export([f[:-4] for f in os.listdir(cdir) if f.lower().endswith(".glb")])
        return
    mdir = os.path.join(cm.CACHE, mission.lower())
    scene = json.load(open(os.path.join(mdir, "scene.json"), encoding="utf-8"))
    models = set(COMMANDO_MODELS)
    for a in scene["actors"]:
        if a.get("actor_type") == 3 and a.get("model"):
            models.add(a["model"].lower())
    export(models)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    main(sys.argv[1])
