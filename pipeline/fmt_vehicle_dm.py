"""Schadensmodelle der Fahrzeuge (MODELS\\DM<Modell>.4ds) -> orig_cache/<m>/models/dm_<modell>.glb.

Original (docs/re_notes_ai.md Par. 4, hd2.exe):
  - 0x4E09D0 liest beim Laden eines Fahrzeugs das Schadensmodell "DM%s" (String 0x83BE6C) mit den Frames
    SEATnn (Insassen), HOR*/VERT (folgen Turm/Rohr), D_ZONEnn {HP<n>, matid<n>} (Trefferzonen mit eigener
    Gesundheit und Material), EXPL_Dnn {EXPL<s>, PARTID<n>} (Explosionspunkte, Verzoegerung in s), PARTICLE
    {SID, PFIRE, PSMOKE} [B].
  - 0x4E1A20 (Schaden): Zone per Strahltest (Geschoss/Rakete) bzw. naechste Zone (Explosion, Art 2); Rest =
    Schaden - Panzerung(matid, hdmaterials.def +0x28); Rest > 0 -> HP -= Rest; HP < 0 -> Fahrzeug zerstoert
    (Geschoss Art 1: nach EXPL-Verzoegerung des naechsten EXPL_D) [B].
Die glb-Dateien enthalten nur Geometrie und Frame-Parameter (extras.params), keine Texturen; Koordinaten wie
convert_mission.model_to_gltf (z gespiegelt), d. h. deckungsgleich mit dem Fahrzeugmodell <modell>.glb.

Aufruf:
  pyenv\\Scripts\\python.exe -I fmt_vehicle_dm.py --all        (alle Missionsordner mit Fahrzeugmodellen)
  pyenv\\Scripts\\python.exe -I fmt_vehicle_dm.py AFRICA1
"""
import glob
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import convert_mission as cm  # noqa: E402
import fmt_4ds  # noqa: E402


class _NoTextures:
    """Schadensmodelle werden nie gezeichnet: keine Texturen."""
    def get(self, *_a, **_k):
        return None


def _vehicle_models(mdir: str) -> list:
    """Modellnamen aller Fahrzeugakteure (Typ 4) eines Missionsordners (scene.json + vehicles.json)."""
    out = []
    vp = os.path.join(mdir, "vehicles.json")
    if os.path.isfile(vp):
        for v in json.load(open(vp, encoding="utf-8")).get("vehicles", {}).values():
            m = str(v.get("model", "")).lower()
            if m and m not in out:
                out.append(m)
    sp = os.path.join(mdir, "scene.json")
    if os.path.isfile(sp):
        for a in json.load(open(sp, encoding="utf-8")).get("actors", []):
            if a.get("actor_type") == 4:
                m = str(a.get("model", "")).lower()
                if m and m not in out:
                    out.append(m)
    return out


def convert_dir(mdir: str) -> int:
    n = 0
    for model in _vehicle_models(mdir):
        data = cm.read_file("models/DM%s.4ds" % model, ["Models.dta"])
        if data is None:
            continue
        mdl = fmt_4ds.read_model(data, quiet=True)
        dst = os.path.join(mdir, "models", "dm_%s.glb" % model)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        cm.model_to_gltf(mdl, _NoTextures(), "../../textures/", dst)
        zones = sum(1 for f in mdl["frames"] if str(f.get("name", "")).upper().startswith("D_ZONE"))
        print("  %s: DM%s -> %s (%d Zonen)" % (os.path.basename(mdir), model, os.path.basename(dst), zones))
        n += 1
    return n


def main(argv):
    if not argv:
        print(__doc__)
        return 1
    if argv[0] == "--all":
        dirs = sorted(p for p in glob.glob(os.path.join(cm.CACHE, "*")) if os.path.isdir(os.path.join(p, "models")))
    else:
        dirs = [os.path.join(cm.CACHE, a.lower()) for a in argv]
    total = 0
    for d in dirs:
        total += convert_dir(d)
    print("Schadensmodelle: %d" % total)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
