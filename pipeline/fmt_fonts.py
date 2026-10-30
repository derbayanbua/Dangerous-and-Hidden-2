"""Original-Bitmapschriften von Hidden & Dangerous 2 -> BMFont (Text-.fnt + PNG) fuer Godot (B-003).

Quelle (nur lesen): <HD2>\\Text\\Fonts\\<ANSI|CE>\\Set1..3\\{BIG,SMALL}.tga + .tbl
  .tbl = 256 Eintraege a 20 Byte: u0, v0, u1, v1 (Anteile der Textur), Seitenverhaeltnis Breite/Hoehe (float32).
  Glyphenfarbe in der TGA ist weiss, Form im Alpha -> eingefaerbt wird zur Laufzeit (Stilfarbe).
Satzwahl im Original [B] hd2.exe 0x63DCA7: Bildbreite >= 1024 -> Set3, >= 800 -> Set2, sonst Set1.

Zusaetzlich die Textstil-Tabelle aus hd2.exe (0x641E30, 90 Stile: Schrift BIG=2/SMALL=3, Farbe ARGB, Hoehe als
Anteil der Bildhoehe, Lage x/y im Rechteck, Rand, Ausrichtung) -> text_styles.json.

Aufruf: python -I fmt_fonts.py [HD2-Ordner] [Zielordner]
  Standard: D:\\Workspace_D\\HD2_orig -> D:\\Workspace_D\\DangerousHidden2\\orig_cache\\ui\\fonts
"""
import json
import os
import re
import struct
import sys

from PIL import Image

HD2 = sys.argv[1] if len(sys.argv) > 1 else r"D:\Workspace_D\HD2_orig"
OUT = sys.argv[2] if len(sys.argv) > 2 else r"D:\Workspace_D\DangerousHidden2\orig_cache\ui\fonts"
CODEPAGE = {"ANSI": "cp1252", "CE": "cp1250"}


def convert_font(group: str, sset: str, name: str) -> dict:
    base = os.path.join(HD2, "Text", "Fonts", group, sset, name)
    tbl = open(base + ".tbl", "rb").read()
    img = Image.open(base + ".tga").convert("RGBA")
    w, h = img.size
    stem = f"{group.lower()}_{sset.lower()}_{name.lower()}"
    img.save(os.path.join(OUT, stem + ".png"))
    chars = []
    line_h = 0
    for code in range(32, 256):
        u0, v0, u1, v1, _ratio = struct.unpack_from("<5f", tbl, code * 20)
        x, y = int(round(u0 * w)), int(round(v0 * h))
        cw, ch = int(round((u1 - u0) * w)), int(round((v1 - v0) * h))
        if cw <= 0 or ch <= 0:
            continue
        try:
            uni = ord(bytes([code]).decode(CODEPAGE[group]))
        except UnicodeDecodeError:
            continue
        line_h = max(line_h, ch)
        chars.append((uni, x, y, cw, ch))
    lines = [f'info face="HD2 {sset} {name}" size={line_h} bold=0 italic=0 charset="" unicode=1 stretchH=100 '
             f'smooth=1 aa=1 padding=0,0,0,0 spacing=0,0',
             f"common lineHeight={line_h} base={int(line_h * 0.8)} scaleW={w} scaleH={h} pages=1 packed=0",
             f'page id=0 file="{stem}.png"', f"chars count={len(chars)}"]
    for uni, x, y, cw, ch in chars:
        lines.append(f"char id={uni} x={x} y={y} width={cw} height={ch} xoffset=0 yoffset=0 xadvance={cw} "
                     f"page=0 chnl=15")
    open(os.path.join(OUT, stem + ".fnt"), "w", encoding="utf-8").write("\n".join(lines) + "\n")
    return {"file": stem + ".fnt", "line_height": line_h, "glyphs": len(chars), "texture": [w, h]}


# ---------------------------------------------------------------- Textstile aus hd2.exe
def read_styles() -> list:
    import capstone
    d = open(os.path.join(HD2, "hd2.exe"), "rb").read()
    pe = struct.unpack_from("<I", d, 0x3C)[0]
    n = struct.unpack_from("<H", d, pe + 6)[0]
    osz = struct.unpack_from("<H", d, pe + 20)[0]
    base = struct.unpack_from("<I", d, pe + 24 + 28)[0]
    secs = []
    for i in range(n):
        o = pe + 24 + osz + i * 40
        _vs, va, rs, ra = struct.unpack_from("<IIII", d, o + 8)
        secs.append((va, ra, rs))

    def v2f(v):
        for va, ra, rs in secs:
            if base + va <= v < base + va + rs:
                return v - base - va + ra
        return None

    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32)
    regs = {"ebx": 0, "edi": 1, "ebp": 2, "bl": 0}

    def val(t):
        if t.startswith("0x") or t.isdigit():
            return int(t, 0)
        return regs.get(t)

    delta, buf, pushes, raw = 0, {}, [], []
    # Funktion 0x641E30 (Stile in Aufrufreihenfolge = Stilnummer), Register ebx=0 edi=1 ebp=2 bleiben fest
    for ins in md.disasm(d[v2f(0x641E49):v2f(0x64378E)], 0x641E49):
        m, o = ins.mnemonic, ins.op_str
        if m == "push":
            delta += 4
            pushes.append(val(o) if o not in ("eax", "ecx", "edx") else None)
            continue
        mm = re.match(r"(?:byte|dword) ptr \[esp \+ (0x[0-9a-f]+)\], (\w+)", o)
        if m == "mov" and mm:
            buf[int(mm.group(1), 16) - delta - 0x10] = val(mm.group(2))
            continue
        if m == "call" and o == "0x643790":          # Konstruktor mit 14 Argumenten
            raw.append(list(reversed(pushes[-14:])))
            delta -= 56
            pushes = pushes[:-14]
            continue
        if m == "call" and o == "0x641d90":          # Stil anhaengen
            delta -= 4
            pushes = pushes[:-1]
            if buf:
                raw.append([buf.get(k) for k in range(0, 0x2C, 4)])
            buf = {}

    def f(x):
        return round(struct.unpack("<f", struct.pack("<I", x))[0], 4) if isinstance(x, int) and x > 0xFF else x

    out = []
    for k, a in enumerate(raw):
        out.append({"id": k, "font": {2: "BIG", 3: "SMALL"}.get(a[0], a[0]),
                    "argb": ("%08x" % a[1]) if a[1] is not None else None, "height": f(a[2]),
                    "x": f(a[4]), "y": f(a[5]), "pad": [f(a[6]), f(a[7])], "halign": a[9], "valign": a[10]})
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    fonts = {}
    for group in ("ANSI", "CE"):
        for sset in ("Set1", "Set2", "Set3"):
            for name in ("BIG", "SMALL"):
                if os.path.exists(os.path.join(HD2, "Text", "Fonts", group, sset, name + ".tbl")):
                    fonts[f"{group}/{sset}/{name}"] = convert_font(group, sset, name)
    styles = read_styles()
    json.dump({"source": "hd2.exe 0x641E30 (Textstile), 0x63DCA7 (Satzwahl), Text\\Fonts", "fonts": fonts,
               "set_by_width": [[1024, "Set3"], [800, "Set2"], [0, "Set1"]], "styles": styles},
              open(os.path.join(OUT, "fonts.json"), "w", encoding="utf-8"), indent=1)
    print(f"{len(fonts)} Schriften, {len(styles)} Textstile -> {OUT}")


if __name__ == "__main__":
    main()
