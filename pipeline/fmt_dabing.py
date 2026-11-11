"""Gesichtsdaten der Sprachaufnahmen (TABLES\\dabing\\%08d.dat aus others.DTA/patch.dta) in den Cache kopieren.

Aufruf (venv):  pyenv\\Scripts\\python.exe -I fmt_dabing.py
  -> orig_cache/dabing/<id>.dat   (Originalbytes, unverändert)
     orig_cache/dabing/index.json (IDs, Bildzahl je Datei, Formatangaben)

Format [B] hd2.exe 0x71E860 (Laden) / 0x71EE00 (Abspielen):
  u32 Bildzahl n ; u32 (immer 1) ; n × 8 Byte je Bild.
  Bild i liegt ab Byte 8 + 8·i; gelesen werden nur die Bytes 0–5 (Wert/255), Bytes 6–7 ungenutzt.
  Bildindex = Abspielzeit_ms / 20 (50 Bilder/s). Datei-ID = Nummer der Sprachaufnahme (<id>.wav).
"""
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import convert_mission as cm  # noqa: E402

PREFIX = "tables\\dabing\\"


def collect():
    files = {}
    for a in ["others.DTA", "patch.dta"]:   # Patch überschreibt
        p = os.path.join(cm.ORIG, a)
        if not os.path.exists(p):
            continue
        arc = cm.archive(a)
        for k, e in arc.index.items():
            if k.startswith(PREFIX) and k.endswith(".dat"):
                files[os.path.basename(k)[:-4]] = (arc, e)
    return files


def main():
    out = os.path.join(cm.CACHE, "dabing")
    os.makedirs(out, exist_ok=True)
    idx, bad = {}, []
    for name, (arc, e) in sorted(collect().items()):
        d = arc.read(e)
        if len(d) < 8:
            bad.append(name)
            continue
        n = struct.unpack_from("<I", d)[0]
        if len(d) < 8 + 8 * n:
            bad.append(name)
            continue
        with open(os.path.join(out, name + ".dat"), "wb") as f:
            f.write(d)
        idx[name] = n
    json.dump({"source": "TABLES\\dabing\\%08d.dat (hd2.exe 0x71E860/0x71EE00)", "fps": 50, "frame_bytes": 8,
               "params": 6, "frames": idx}, open(os.path.join(out, "index.json"), "w", encoding="utf-8"), indent=0)
    print("Gesichtsdaten:", len(idx), "Dateien, fehlerhaft:", bad)


if __name__ == "__main__":
    main()
