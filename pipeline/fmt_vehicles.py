"""Fahrzeugdaten (Akteurtyp 4 "Car") von Hidden & Dangerous 2 -> orig_cache/<m>/vehicles.json.

Quelle: Akteursdefinitionen 0xAE20 > 0xAE21 {0xAE22 Typ 4, 0xAE23 Name, 0xAE24 Parameter} in
missions\\<m>\\actors.bin bzw. scene2.bin (Leser 0x4D10A0 -> 0x4E2E30, docs/re_notes_interactive.md Par. 9).
Parameterblock: u32 Version (3), u32 Laenge, dann ein RLE-gepackter Datensatz (hd2.exe FUN_004d0110 [B]):
  "COMP", u32 ungepackte Laenge, u32 gepackte Laenge (inkl. 13-Byte-Kopf), u8 Fluchtzeichen;
  ab +13: Byte == Flucht -> (Wert, Anzahl) wiederholen, sonst Literal.
Ungepackter Datensatz (Deutung per Datenabgleich ueber alle 116 Fahrzeuge, Konfidenz je Feld):
  +0x00 f32 Masse kg [P: Kuebel 1100, Opel 4000, Tiger 60000]
  +0x04 f32 Motorleistung [P: Kuebel 45, Jeep 55, Opel 110, Tiger 550 – Einheit vermutlich PS]
  +0x0C f32 Hoechstdrehzahl, +0x10 Drehzahlbegrenzer, +0x14 Leerlauf [P]
  +0x24/+0x28 f32 Drehzahlen (Schaltschwellen/Drehmomentband?) [?]
  +0x4C f32 Zahl der Vorwaertsgaenge [P: Jeep 3, Kuebel 4, Halbkette 5]
  +0x50 je Gang 3 x f32 {Gesamtuebersetzung, ?, ?}: Gang 0 = Rueckwaerts, dann 1..n
        [P: Kuebel 23,9 / 21,65 / 12,85 / 8,59 / 6,75 ~ real 24,7 / 22,3 / 12,8 / 7,8 / 5,0]
Hoechstgeschwindigkeit = Hoechstdrehzahl x 2pi x Radradius / (60 x Uebersetzung oberster Gang); den
Radradius liefert das Modell (Frames DWHLnn/DWHRnn mit Rad-Mesh), daher rechnet das Spiel sie aus.

Aufruf:
  pyenv\\Scripts\\python.exe -I fmt_vehicles.py ARCTIC1 [ziel.json]
  pyenv\\Scripts\\python.exe -I fmt_vehicles.py --all     (alle Missionen mit orig_cache/<m>/scene.json)
"""
import glob
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fmt_scene2  # noqa: E402
import fmt_actors_items as fai  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, "DangerousHidden2", "orig_cache")


def unrle(p: bytes) -> bytes:
    """RLE-Entpacker wie hd2.exe FUN_004d0110 (Modus Entpacken)."""
    if p[0:4] != b"COMP":
        return b""
    raw, comp, esc = struct.unpack_from("<IIB", p, 4)
    out = bytearray()
    i = 13
    while i < comp and i < len(p):
        c = p[i]
        if c == esc:
            out += bytes([p[i + 1]]) * p[i + 2]
            i += 3
        else:
            out.append(c)
            i += 1
    return bytes(out[:raw])


def decode(params: bytes) -> dict:
    if len(params) < 8 + 13:
        return {}
    body = unrle(params[8:])
    if len(body) < 0x50 + 12:
        return {}
    f = struct.unpack_from("<%df" % (min(len(body), 0x100) // 4), body, 0)
    gears = int(round(f[19]))
    if gears < 1 or gears > 8:
        return {}
    ratios = [round(f[20 + 3 * k], 4) for k in range(gears + 1)]
    return {
        "mass_kg": round(f[0], 2),
        "power": round(f[1], 3),
        "rpm_max": round(f[3], 1),
        "rpm_limit": round(f[4], 1),
        "rpm_idle": round(f[5], 1),
        "rpm_band": [round(f[9], 1), round(f[10], 1)],
        "gears": gears,
        "ratio_reverse": ratios[0],
        "ratios": ratios[1:],
        "gear_extra_?": [[round(f[21 + 3 * k], 2), round(f[22 + 3 * k], 2)] for k in range(gears + 1)],
        "head_?": [round(x, 4) for x in f[:20]],
    }


def build(mission: str) -> dict:
    m = mission.upper()
    mdir = os.path.join(CACHE, m.lower())
    models = {}
    sp = os.path.join(mdir, "scene.json")
    if os.path.isfile(sp):
        scene = json.load(open(sp, encoding="utf-8"))
        models = {a.get("name", ""): a.get("model", "") for a in scene.get("actors", [])}
    out = {}
    for src in ("scene2.bin", "actors.bin"):
        d, _ = fai.read_orig("missions\\%s\\%s" % (m, src), "Missions.dta")
        if not d:
            continue
        for name, (typ, params) in fmt_scene2.parse_actor_defs(d).items():
            if typ != 4:
                continue
            v = decode(params)
            if not v:
                continue
            v["model"] = models.get(name, "")
            v["source"] = src
            out[name] = v
    return {"mission": m, "source": "actors.bin/scene2.bin Typ 4, RLE 'COMP' (hd2.exe FUN_004d0110)",
            "vehicles": out}


def main(argv):
    if not argv:
        print(__doc__)
        return 1
    if argv[0] == "--all":
        ms = sorted(os.path.basename(p).upper() for p in glob.glob(os.path.join(CACHE, "*"))
                    if os.path.isfile(os.path.join(p, "scene.json")))
    else:
        ms = [argv[0]]
    for m in ms:
        try:
            res = build(m)
        except Exception as ex:  # fehlende Missionsdateien in der Installation
            print("%s: %s" % (m, ex))
            continue
        if not res["vehicles"]:
            continue
        dst = argv[1] if len(argv) > 1 and argv[0] != "--all" else os.path.join(CACHE, m.lower(), "vehicles.json")
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst, "w", encoding="utf-8") as fh:
            json.dump(res, fh, ensure_ascii=False, indent=1)
        print("%s: %d Fahrzeuge -> %s" % (m, len(res["vehicles"]), dst))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
