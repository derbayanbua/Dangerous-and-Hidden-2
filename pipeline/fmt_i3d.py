"""Skriptanimationen (*.i3d) der Original-Missionsskripte in den lokalen Cache exportieren.

FRM_SetAnimation(frame, "%%name.i3d", kanal), FRM_SetAnimationDelayed(...) und CSC_SetCameraAnimation(frame, "#name")
verweisen auf LS3D-Animationen: "name.i3d" = MODELS\\name.5DS (+ gleichnamige Dummy-.4ds), "%%" im Skripttext steht für
ein einzelnes "%" (im Archiv gibt es nur "%sedim.5DS", kein "%%sedim.5DS"; Ju-88-Beleg re_notes_ju88 §2.2).

Ausgabe: orig_cache/anims/<name klein>.json  (name ohne Endung, "%%" -> "%")
  {"file": "MODELS\\%sedim.5DS", "last_frame": n, "fps": 25,
   "objects": [{"name": "a", "rot": [[f, x, y, z, w], ...], "pos": [[f, x, y, z], ...], "scale": [[f, x, y, z], ...],
                "events": [[f, "text"], ...]}]}
Koordinaten bereits in glTF/Godot: Position (x, y, -z), Rotation (x, y, -z, w) (re_notes_5ds_skin §3).
Zusätzlich orig_cache/anims/index.json: Name -> Skripte, die ihn verwenden; fehlende Dateien.

Aufruf: pyenv\\Scripts\\python.exe -I fmt_i3d.py   (liest alle orig_cache/*/scripts/*.scr)
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dta_extract  # noqa: E402
import fmt_5ds  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ORIG = os.environ.get("DH2_ORIG") or os.path.join(ROOT, "HD2_orig")
CACHE = os.environ.get("DH2_CACHE") or os.path.join(ROOT, "DangerousHidden2", "orig_cache")
OUT = os.path.join(CACHE, "anims")

CALL = re.compile(r"(FRM_SetAnimation(?:Delayed)?|CSC_SetCameraAnimation)\s*\(\s*[^,]*,\s*\"([^\"]*)\"", re.I)
# HUMAN_SetAnim("%%lenin", Einblenden ms, Ausblenden ms, Schleife) – Menschen-Dispatcher hd2.exe 0x421E66 → 0x5AF780
CALL_HUMAN = re.compile(r"(HUMAN_SetAnim)\s*\(\s*\"([^\"]*)\"", re.I)


def norm(name: str) -> str:
    n = name.strip().replace("%%", "%")
    if n.lower().endswith(".i3d"):
        n = n[:-4]
    return n


def main():
    used = {}
    for d in sorted(os.listdir(CACHE)):
        sd = os.path.join(CACHE, d, "scripts")
        if not os.path.isdir(sd):
            continue
        for fn in os.listdir(sd):
            t = open(os.path.join(sd, fn), encoding="latin-1").read()
            t = re.sub(r"//[^\n]*", "", t)
            t = re.sub(r"/\*.*?\*/", "", t, flags=re.S)
            for m in list(CALL.finditer(t)) + list(CALL_HUMAN.finditer(t)):
                n = norm(m.group(2))
                if n:
                    used.setdefault(n.lower(), {"name": n, "scripts": set()})["scripts"].add("%s/%s" % (d, fn))
    arcs = []
    for a in ("patch.dta", "MODELS.DTA"):
        arc = dta_extract.Archive(os.path.join(ORIG, a))
        arc.index = {e[0].lower(): e for e in arc.entries}
        arcs.append(arc)
    os.makedirs(OUT, exist_ok=True)
    index = {"anims": {}, "missing": []}
    for key, u in sorted(used.items()):
        fname = "MODELS\\" + u["name"] + ".5DS"
        data = None
        for arc in arcs:
            e = arc.index.get(fname.lower())
            if e:
                try:
                    data = arc.read(e)
                except Exception as ex:  # z. B. nicht unterstützter Blocktyp
                    print("Lesefehler", fname, ex)
                break
        if data is None:
            index["missing"].append({"name": u["name"], "scripts": sorted(u["scripts"])})
            continue
        a = fmt_5ds.parse(data)
        objs = []
        for o in a["objects"]:
            r = {"name": o["name"]}
            if o.get("rot"):
                r["rot"] = [[f, round(q[0], 6), round(q[1], 6), round(-q[2], 6), round(q[3], 6)] for f, q in zip(o["rot_frames"], o["rot"])]
            if o.get("pos"):
                r["pos"] = [[f, round(p[0], 5), round(p[1], 5), round(-p[2], 5)] for f, p in zip(o["pos_frames"], o["pos"])]
            if o.get("scale"):
                r["scale"] = [[f, round(s[0], 5), round(s[1], 5), round(s[2], 5)] for f, s in zip(o["scale_frames"], o["scale"])]
            if o.get("events"):
                r["events"] = [[f, ev] for f, ev in zip(o["event_frames"], o["events"])]
            objs.append(r)
        # Binärformat (JSON mit verschachtelten Feldern kostete in Godot bis ~50 MB je Datei beim Parsen):
        # "HDA1", u32 last_frame, u16 n_obj; je Objekt: u8 len + Name, dann 3 Kanäle rot/pos/scale:
        # u32 n, n × (f32 Bild, Werte 4/3/3 × f32); Ereignisse: u32 n, n × (f32 Bild, u16 len, Text latin-1)
        import struct
        b = bytearray(b"HDA1") + struct.pack("<IH", a["last_frame"], len(objs))
        for r in objs:
            nm = r["name"].encode("latin-1")[:255]
            b += struct.pack("<B", len(nm)) + nm
            for ch, w in (("rot", 4), ("pos", 3), ("scale", 3)):
                ks = r.get(ch, [])
                b += struct.pack("<I", len(ks))
                for k in ks:
                    b += struct.pack("<%df" % (w + 1), *k)
            evs = r.get("events", [])
            b += struct.pack("<I", len(evs))
            for fr, ev in evs:
                e = ev.encode("latin-1")
                b += struct.pack("<fH", fr, len(e)) + e
        old = os.path.join(OUT, key + ".json")
        if os.path.exists(old):
            os.remove(old)
        with open(os.path.join(OUT, key + ".hda"), "wb") as f:
            f.write(bytes(b))
        index["anims"][key] = {"name": u["name"], "last_frame": a["last_frame"], "objects": len(objs),
                               "scripts": sorted(u["scripts"])}
    with open(os.path.join(OUT, "index.json"), "w", encoding="utf-8") as f:
        json.dump(index, f, indent=1, ensure_ascii=False)
    print("Animationen: %d exportiert, %d fehlen" % (len(index["anims"]), len(index["missing"])))
    for m in index["missing"]:
        print("  fehlt:", m["name"], m["scripts"][:3])


if __name__ == "__main__":
    main()
