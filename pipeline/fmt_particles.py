"""Original-Partikeltabelle TABLES\\effects.def -> DangerousHidden2/orig_cache/effects/particles.json
(+ Partikeltexturen MAPS\\d_*.tga -> orig_cache/effects/particles/*.png). Nur lokaler Cache.

Aufbau (Chunks: u16 Kennung, u32 Groesse inkl. Kopf) [B = Struktur gelesen, P = Bedeutung aus Wertemustern]:
  0x03E8 Wurzel
    0x03F2 Effekt (121 Stueck, Reihenfolge = Nummer im Namen "NN - ..." = Index fuer FRM_CreateParticle) [B/P]
      0x0064  u8 ?, u8 Mischart (1 = normal/Alpha, 2 = additiv: alle Feuer/Muendungs-Effekte) [P]
      0x0065  Name (slowakisch/tschechisch, z. B. "53-vybuch cisterna")
      0x0066  Textur (MAPS\\d_*.tga)
      0x0067  Emitter (1..n)
        0x00C8 u32 Stoss-Anzahl, u32 ?, u32 Rate/s; f32 @44..@72: Groesse min/max, Geschw. min/max, Wachstum [P]
        0x00CA f32 @16/@20/@24 = Alpha Anfang/Mitte/Ende [P]
        0x00CB enthaelt 0x012C: vec3 Ausdehnung @8, u32 Lebensdauer ms @24, f32 @44 Steigen, rgb Farbe @52,
              f32 @84 Schwerkraft [P]; 0x012E ?
        0x00CC u32 Flag
      0x0068 f32 20, 50 (Sichtweiten?) ; 0x0069 u32 5, 6 [P]

Zuordnung Index -> Skript belegt durch Namen und Skriptverwendung (docs/status/b028.md): 108 "Afrika2 cut-piesok za
jeepom" = cutscene_af2 JEEPprach, 114 "fire works" = TUTORIAL t_fw*, 113 "meteorit" = af3b_ee meteor, 23 "dymovnica
cervena" = africa4 dymovnica, 16 "dym junkers 88" = af2_actprelet dymzkridla, 53 "vybuch cisterna" = af1 cisterny.

Aufruf: pyenv\\Scripts\\python.exe -I fmt_particles.py
"""
import io
import json
import os
import re
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import convert_mission as cm  # noqa: E402


def _f(p, o):
    return struct.unpack_from("<f", p, o)[0] if o + 4 <= len(p) else 0.0


def _u(p, o):
    return struct.unpack_from("<I", p, o)[0] if o + 4 <= len(p) else 0


def _chunks(b, off, end):
    while off + 6 <= end:
        cid, sz = struct.unpack_from("<HI", b, off)
        if sz < 6 or off + sz > end:
            return
        yield cid, off + 6, off + sz
        off += sz


def _emitter(b, s, e):
    em = {}
    for cid, ps, pe in _chunks(b, s, e):
        p = b[ps:pe]
        if cid == 0xC8:
            em.update({"burst": _u(p, 0), "u4": _u(p, 4), "rate": _u(p, 8),
                       "size": [round(_f(p, 44), 4), round(_f(p, 48), 4), round(_f(p, 52), 4), round(_f(p, 56), 4)],
                       "speed": [round(_f(p, 56), 4), round(_f(p, 64), 4)], "grow": round(_f(p, 72), 4),
                       "angle": round(_f(p, 84), 4)})
        elif cid == 0xCA:
            em["alpha"] = [round(_f(p, 16), 4), round(_f(p, 20), 4), round(_f(p, 24), 4)]
        elif cid == 0xCB:
            for sid, qs, qe in _chunks(b, ps, pe):
                if sid == 0x12C:
                    q = b[qs:qe]
                    em["extent"] = [round(_f(q, 8), 4), round(_f(q, 12), 4), round(_f(q, 16), 4)]
                    em["f20"] = round(_f(q, 20), 4)
                    em["life_ms"] = _u(q, 24)
                    em["rise"] = round(_f(q, 44), 4)
                    em["end_color"] = [round(_f(q, 52), 4), round(_f(q, 56), 4), round(_f(q, 60), 4)]
                    em["gravity"] = round(_f(q, 84), 4)
                    em["raw"] = q.hex()
        elif cid == 0xCC:
            em["flag"] = _u(p, 0)
    return em


def parse(b):
    out = []
    root_end = len(b)
    for cid, s, e in _chunks(b, 0, root_end):
        if cid != 0x3E8:
            continue
        for ecid, es, ee in _chunks(b, s, e):
            if ecid != 0x3F2:
                continue
            fx = {"index": len(out), "name": "", "texture": "", "blend": 1, "emitters": []}
            for c, ps, pe in _chunks(b, es, ee):
                p = b[ps:pe]
                if c == 0x64:
                    fx["flags0"] = p[0] if p else 0
                    fx["blend"] = p[1] if len(p) > 1 else 1
                elif c == 0x65:
                    fx["name"] = p.split(b"\0")[0].decode("latin1").strip()
                elif c == 0x66:
                    fx["texture"] = p.split(b"\0")[0].decode("latin1").strip().lower()
                elif c == 0x67:
                    fx["emitters"].append(_emitter(b, ps, pe))
                elif c == 0x68:
                    fx["range"] = [round(_f(p, 0), 3), round(_f(p, 4), 3)]
            m = re.match(r"\s*(\d+)", fx["name"])
            fx["name_number"] = int(m.group(1)) if m else -1
            fx["kind"] = classify(fx["name"], fx["texture"])
            out.append(fx)
    return out


## Grobe Art fuer die Darstellung (aus Name/Textur) [P]
def classify(name, tex):
    n = name.lower()
    if "vybuch" in n or "explo" in n or "granat" in n or tex.startswith("d_explo"):
        return "explosion"
    if "ohen" in n or "fire" in n or "plamen" in n or "muzzle" in n or "vystrel" in n:
        return "fire"
    if "spark" in n or "skrat" in n or "odraz" in n or "kulka kov" in n or "bzrr" in n or "sparkles" in tex:
        return "sparks"
    if "voda" in n or "vodopad" in n or "water" in n or "kvapk" in n or "bubble" in n or "waterfall" in n:
        return "water"
    if "para" in n:
        return "steam"
    if "pisek" in n or "piesok" in n or "prach" in n or "hlina" in n or "bahno" in n or "sneh" in n or "trava" in n \
            or "piliny" in n or "listy" in n or "sut" in n or "drevo" in n or "beton" in n:
        return "dust"
    if "krv" in n or "blood" in tex:
        return "blood"
    return "smoke"


def main():
    raw = cm.read_file("tables/effects.def", ["others.DTA"])
    fxs = parse(raw)
    out_dir = os.path.join(cm.CACHE, "effects")
    tex_dir = os.path.join(out_dir, "particles")
    os.makedirs(tex_dir, exist_ok=True)
    want = {f["texture"] for f in fxs if f["texture"]}
    n_tex = 0
    try:
        from PIL import Image
        from dta_extract import Archive
        arc = Archive(os.path.join(cm.ORIG, "Maps.dta"))
        for e in arc.entries:
            f = e[0].replace("\\", "/").split("/")[-1].lower()
            if f in want:
                im = Image.open(io.BytesIO(arc.read(e))).convert("RGBA")
                im.save(os.path.join(tex_dir, os.path.splitext(f)[0] + ".png"))
                n_tex += 1
    except Exception as ex:  # Texturen optional, Tabelle trotzdem schreiben
        print("Partikeltexturen:", ex)
    with open(os.path.join(out_dir, "particles.json"), "w", encoding="utf-8") as fo:
        json.dump({"source": "TABLES\\effects.def (fmt_particles.py, Semantik [P] docs/status/b028.md)",
                   "effects": fxs}, fo, indent=1, ensure_ascii=False)
    print("Partikeleffekte: %d, Texturen: %d/%d -> %s" % (len(fxs), n_tex, len(want), out_dir))


if __name__ == "__main__":
    main()
