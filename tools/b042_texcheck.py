"""B-042: KI-Texturstufen (textures_hd / textures_4k) gegen die Originale prüfen.

Aufruf: tools\\pyenv\\Scripts\\python.exe -I tools\\b042_texcheck.py <orig_cache> [--write]

Geprüft je Datei: Original vorhanden, Alpha nicht verloren (Original mit transparenten Pixeln, KI-Fassung ohne
Alphakanal), gleiches Seitenverhältnis, Breite/Höhe durch 4 teilbar (Blockkompression B-039), Farbtreue (8×8-Mittel
über die deckenden Pixel, größte Kanalabweichung > 40/255). Mit --write wird je Stufe `_reject.txt` geschrieben;
OrigLevel._swap_textures überspringt die dort gelisteten Dateien und nimmt die nächste Stufe (4K → HD → Original).
"""
import os
import sys
import warnings
from PIL import Image

warnings.filterwarnings("ignore")
COLOR_LIMIT = 40


def check(root: str, write: bool) -> int:
    base = os.path.join(root, "textures")
    bad_total = 0
    for suf in ("_hd", "_4k"):
        d = os.path.join(root, "textures" + suf)
        if not os.path.isdir(d):
            print(suf, "fehlt")
            continue
        files = sorted(f for f in os.listdir(d) if f.lower().endswith(".png"))
        reject = {}
        missing = 0
        for f in files:
            o = os.path.join(base, f)
            if not os.path.exists(o):
                missing += 1
                continue
            try:
                io = Image.open(o)
                ih = Image.open(os.path.join(d, f))
                io.load()
                ih.load()
            except Exception as e:  # defekte Datei
                reject[f] = "unlesbar: %s" % e
                continue
            ao = io.convert("RGBA")
            a_min = ao.getchannel("A").getextrema()[0]
            h_alpha = ih.mode in ("RGBA", "LA") or "transparency" in ih.info
            if a_min < 250 and not h_alpha:
                reject[f] = "Alpha verloren"
                continue
            ro, rh = ih.size[0] / io.size[0], ih.size[1] / io.size[1]
            if abs(ro - rh) > 0.01:
                reject[f] = "Seitenverhältnis %s -> %s" % (io.size, ih.size)
                continue
            if ih.size[0] % 4 or ih.size[1] % 4:
                reject[f] = "Größe nicht durch 4 teilbar %s" % (ih.size,)
                continue
            hh = ih.convert("RGBA").resize(io.size, Image.BOX)
            m = ao.getchannel("A").point(lambda v: 255 if v > 128 else 0)
            bg = Image.new("RGB", io.size)
            so = Image.composite(ao.convert("RGB"), bg, m).resize((8, 8), Image.BOX)
            sh = Image.composite(hh.convert("RGB"), bg, m).resize((8, 8), Image.BOX)
            dmax = max(abs(a - b) for x, y in zip(so.getdata(), sh.getdata()) for a, b in zip(x, y))
            if dmax > COLOR_LIMIT:
                reject[f] = "Farbabweichung %d" % dmax
        print("%s: %d Dateien, ohne Original %d, abgelehnt %d" % (suf, len(files), missing, len(reject)))
        for f, why in list(reject.items())[:40]:
            print("  %-40s %s" % (f, why))
        bad_total += len(reject)
        if write:
            with open(os.path.join(d, "_reject.txt"), "w", encoding="utf-8") as fh:
                fh.write("# B-042 tools/b042_texcheck.py – Datei<TAB>Grund\n")
                for f, why in reject.items():
                    fh.write("%s\t%s\n" % (f, why))
    return bad_total


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    n = check(sys.argv[1], "--write" in sys.argv)
    print("ABGELEHNT GESAMT", n)
