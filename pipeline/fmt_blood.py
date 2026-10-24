"""Original-Bluttexturen (Maps.dta: MAPS\\x_blood00..05.tga, d_blood.tga, d_bloodflak.tga, blood/blooda.bmp)
nach DangerousHidden2/orig_cache/effects/blood/*.png (nur lokaler Cache, nicht im Repo).

Beleg: hd2.exe enthaelt die Formatzeichenkette "x_blood%02d.tga" direkt neben "x_expl%02d.tga" und
"x_decal%02d.tga" (Dateioffset 0x439066) -> nummerierte Blut-Effekttexturen 00..05.

Aufruf: pyenv\\Scripts\\python.exe -I fmt_blood.py [HD2_orig] [orig_cache]
"""
import io
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dta_extract import Archive  # noqa: E402
from PIL import Image  # noqa: E402

NAMES = ["x_blood00.tga", "x_blood01.tga", "x_blood02.tga", "x_blood03.tga", "x_blood04.tga",
         "x_blood05.tga", "d_blood.tga", "d_bloodflak.tga", "blood.bmp", "blooda.bmp"]


def main() -> None:
    here = os.path.dirname(os.path.abspath(__file__))
    orig = sys.argv[1] if len(sys.argv) > 1 else (os.environ.get("DH2_ORIG") or os.path.join(here, "..", "HD2_orig"))
    cache = sys.argv[2] if len(sys.argv) > 2 else (os.environ.get("DH2_CACHE") or os.path.join(here, "..", "DangerousHidden2", "orig_cache"))
    out = os.path.join(cache, "effects", "blood")
    os.makedirs(out, exist_ok=True)
    arc = Archive(os.path.join(orig, "Maps.dta"))
    n = 0
    for e in arc.entries:
        f = e[0].replace("\\", "/").split("/")[-1].lower()
        if f not in NAMES:
            continue
        im = Image.open(io.BytesIO(arc.read(e))).convert("RGBA")
        im.save(os.path.join(out, os.path.splitext(f)[0] + ".png"))
        n += 1
    print("Bluttexturen:", n, "->", out)


if __name__ == "__main__":
    main()
