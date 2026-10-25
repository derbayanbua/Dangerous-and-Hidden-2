"""Kopfgegenstände (Helme/Mützen, items.sav Ausrüstung Kategorie 16) in den lokalen Cache konvertieren (B-014).

Aufruf (venv):  pyenv\\Scripts\\python.exe -I export_head_items.py
  -> orig_cache/heads/<modell>.glb   Modell aus MODELS\\<modell>.4ds (Texturen: orig_cache/textures, geteilt)
  -> orig_cache/heads/heads.json     Gegenstand -> Modell
Die Helmmodelle liegen im Figurraum der Bindungslage (Ursprung ≈ 1,74 m über dem Boden); der Nachbau hängt sie
mit dieser Lage an das Kopfgelenk f (src/actors/helmet.gd). Voraussetzung: orig_cache/items.json.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import convert_mission as cm  # noqa: E402
import fmt_4ds  # noqa: E402

HEAD_CATEGORY = 16


def main():
    items = json.load(open(os.path.join(cm.CACHE, "items.json"), encoding="utf-8"))["items"]
    out_dir = os.path.join(cm.CACHE, "heads")
    os.makedirs(out_dir, exist_ok=True)
    tex = cm.Textures(os.path.join(cm.CACHE, "textures"))
    table, done, failed = {}, set(), []
    for it in items:
        eq = it.get("equip_raw") or []
        if len(eq) < 2 or eq[1] != HEAD_CATEGORY:
            continue
        model = (it.get("model") or "").strip()
        if not model:
            continue
        key = model.lower()
        if key not in done:
            data = cm.read_file("models/%s.4ds" % model, ["patch.dta", "MODELS.DTA"])
            if data is None:
                failed.append((it["id"], model, "fehlt"))
                continue
            try:
                m = fmt_4ds.read_model(data, quiet=True)
                cm.model_to_gltf(m, tex, "../textures/", os.path.join(out_dir, key + ".glb"))
                done.add(key)
            except Exception as e:   # einzelne Modelle dürfen scheitern, werden gemeldet
                failed.append((it["id"], model, repr(e)[:100]))
                continue
        table[str(it["id"])] = key
    json.dump({"items": table}, open(os.path.join(out_dir, "heads.json"), "w", encoding="utf-8"), indent=1)
    print("Modelle:", len(done), sorted(done))
    print("Fehler:", failed)
    if tex.missing:
        print("fehlende Texturen:", sorted(tex.missing))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    main()
