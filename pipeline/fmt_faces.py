"""B-035: Gesichtstexturen für FRM_SwitchFaceTexture bereitstellen.

Die Skripte (z. B. *_faceassigner.scr) wechseln die Gesichtstextur von Figuren per Name („e_f054“, „e_f073.bmp“).
convert_mission.py exportiert nur Texturen, die ein Modell referenziert – die meisten Skript-Gesichter fehlen daher
im Cache. Dieses Werkzeug sammelt alle Namen aus orig_cache/*/scripts/*.scr und konvertiert sie (MAPS\\<name>.bmp)
nach orig_cache/textures/<name>.png (gleiche Konvertierung wie convert_mission.Textures).

Aufruf: python -I tools/fmt_faces.py
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import convert_mission as cm  # noqa: E402

PAT = re.compile(r"FRM_SwitchFaceTexture\s*\(\s*[^,]+,\s*\"([^\"]+)\"", re.I)


def main():
    names = set()
    for p in glob.glob(os.path.join(cm.CACHE, "*", "scripts", "*.scr")):
        try:
            txt = open(p, encoding="latin-1").read()
        except OSError:
            continue
        for line in txt.splitlines():
            if line.lstrip().startswith("//"):
                continue
            for m in PAT.finditer(line):
                names.add(os.path.splitext(m.group(1).strip())[0].lower())
    tex = cm.Textures(os.path.join(cm.CACHE, "textures"))
    ok, missing = 0, []
    for n in sorted(names):
        if tex.get(n + ".bmp") or tex.get(n + ".tga"):
            ok += 1
        else:
            missing.append(n)
    print("Gesichter: %d Namen, %d konvertiert, fehlend: %s" % (len(names), ok, missing))


if __name__ == "__main__":
    main()
