"""B-035: Lightmap-Stufen, Lightmap-Gruppen und Umhängungen aus scene2.bin → orig_cache/<mission>/lightmaps.json.

Belegt aus den Daten (docs/status/b035.md):
- Objekte ohne Typ (Ergänzungen zu scene.4ds-Frames) tragen Chunk 0x4090 „LMAP“ + 0x40A0 Lightmap-Daten.
  0x40A0: u8 Maske (Bit k = Stufe k+1 vorhanden), danach je Stufe ein Satz
  [u8 0x21/0x22][u8 6][u8 1][4 B][f32][f32 45][u8 Stufennummer 1..][u16 Vertices][u16 Blöcke][u16 ?] + Blöcke:
  Art 0 = u32 1, u32 w, u32 h, w*h RGB-Texel; Art 1 = RGBA einfarbig + u32 1, u32 3, u32 3. Danach UV/Indizes (nicht gelesen).
- Header-Chunk 0xB810: Lightmap-Gruppen, 0x0100 Name, 0x0110 Mitglied (Frame „Objekt.Unterframe“ oder Szenen-Frame).
- 0x4020/0x0010 bei Objekten ohne Typ: neuer Eltern-Frame (z. B. NORMANDY majak_volum01 → m_maj_svet01).
- 0xB110 bei Glow-Frames („LENS“): sechs Parameter (Kennung 0xB112..0xB117, je f32).

Ausgabe: {"levels": {frame: {"1": mittlere Helligkeit 0..255, "2": ...}}, "groups": {name: [frames]},
          "reparent": {frame: eltern}, "lens": {frame: [f32 x6]}}
Skriptstufe n (FRM_SetLightmap/SetGroupLightmap) = Satz n+1 [P aus den Skripten: 0 = Licht an, 1 = aus].

Aufruf: python -I tools/fmt_lightmaps.py [MISSION ...]
"""
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import convert_mission as cm  # noqa: E402
import fmt_scene2 as s2  # noqa: E402


def _blocks(b, p, n):
    tot = 0.0
    cnt = 0
    for _ in range(n):
        if p >= len(b):
            return None, p
        k = b[p]
        if k == 1:
            if p + 17 > len(b):
                return None, p
            r, g, bb = b[p + 1:p + 4]
            _, w, h = struct.unpack_from("<3I", b, p + 5)
            if w > 1024 or h > 1024:
                return None, p
            tot += (r + g + bb) / 3.0 * w * h
            cnt += w * h
            p += 17
        elif k == 0:
            if p + 13 > len(b):
                return None, p
            one, w, h = struct.unpack_from("<3I", b, p + 1)
            if one != 1 or w > 1024 or h > 1024 or p + 13 + w * h * 3 > len(b):
                return None, p
            tx = b[p + 13:p + 13 + w * h * 3]
            tot += sum(tx) / 3.0
            cnt += w * h
            p += 13 + w * h * 3
        else:
            return None, p
    return (tot / cnt if cnt else 0.0), p


def lightmap_levels(b):
    """Stufennummer -> mittlere Helligkeit (0..255)."""
    out = {}
    p = 1
    while p + 21 <= len(b):
        if b[p] in (0x21, 0x22) and b[p + 1] == 6 and b[p + 2] == 1:
            idx = b[p + 14]
            nv, nblk, _ = struct.unpack_from("<3H", b, p + 15)
            if 1 <= idx <= 8 and 0 < nblk < 8192 and nv > 0:
                mean, p2 = _blocks(b, p + 21, nblk)
                if mean is not None:
                    out[str(idx)] = round(mean, 2)
                    p = p2
                    continue
        p += 1
    return out


def extract(mission):
    d = cm.read_file("missions/%s/scene2.bin" % mission.upper(), ["Missions.dta"])
    if d is None:
        return None
    hdr, objs = s2.parse(d)
    levels, reparent, lens = {}, {}, {}
    for o in objs:
        name = o.get("name") or ""
        if o.get("type", -1) != -1 or not name:
            continue
        par = o.get("parent") or ""
        if par and not par.lower().startswith("sector") and par.lower() != "primary sector":
            reparent[name] = par
        ch = o["chunks"]
        if 0x40A0 in ch:
            s, e = ch[0x40A0]
            lv = lightmap_levels(d[s:e])
            mask = d[s] if e > s else 0
            # Maske mit mehreren Sätzen, aber nicht alle lesbar (z. B. CZECH1 la_zasten_: Satz 2 nicht gefunden) →
            # trotzdem aufnehmen; die Laufzeit ergänzt fehlende Sätze mit dem Median der Mission (OrigLevel.lightmap_factor)
            if len(lv) > 1 or (lv and bin(mask).count("1") > 1):
                levels[name] = lv
        if 0xB110 in ch:
            s, e = ch[0xB110]
            vals = []
            for t, a, b2 in s2.chunks(d, s, e):
                if b2 - a >= 4:
                    vals.append(round(struct.unpack_from("<f", d, a)[0], 4))
            lens[name] = vals
    groups = {}
    if 0xB810 in hdr:
        s, e = hdr[0xB810]
        cur = None
        for t, a, b2 in s2.chunks(d, s, e):
            if t == 0x0100:
                cur = s2.cstr(d, a, b2)
                groups[cur] = []
            elif t == 0x0110 and cur is not None:
                groups[cur].append(s2.cstr(d, a, b2))
    return {"mission": mission.upper(), "levels": levels, "groups": groups, "reparent": reparent, "lens": lens}


def main(argv):
    missions = argv or sorted(dd for dd in os.listdir(cm.CACHE) if os.path.isfile(os.path.join(cm.CACHE, dd, "scene.glb")))
    for m in missions:
        try:
            r = extract(m)
        except Exception as ex:  # noqa: BLE001
            print("%s: Fehler %s" % (m, ex))
            continue
        if r is None:
            print("%s: keine scene2.bin" % m)
            continue
        with open(os.path.join(cm.CACHE, m.lower(), "lightmaps.json"), "w", encoding="utf-8") as f:
            json.dump(r, f, indent=1)
        print("%s: %d Frames mit Stufen, %d Gruppen, %d Umhängungen, %d Lens" % (
            m, len(r["levels"]), len(r["groups"]), len(r["reparent"]), len(r["lens"])))


if __name__ == "__main__":
    main(sys.argv[1:])
