"""Fahrspuren für HUMAN_Drive / HUMAN_DriveNearPlayer (Hidden & Dangerous 2) -> drive.json.

Quelle (belegt in hd2.exe, siehe DangerousHidden2/docs/re_notes_drive.md):
  missions\\<m>\\check2.bin enthält ZWEI aufeinanderfolgende Netz-Abschnitte gleichen Formats.
  Lader 0x6D4323: FUN_00523c00(Datei, Welt+0x54) = Fußwegenetz (HUMAN_Move),
                  FUN_00523c00(Datei, Welt+0x54+0x3C) = Fahrzeugnetz (HUMAN_Drive).
  HUMAN_Drive (Opcode 0x26, Fall 0x422F5B) sucht den Namen per _strnicmp(.., 16) in den Namen
  des 2. Abschnitts (FUN_0051e1a0), erster Treffer gewinnt.

Abschnitt (Parser FUN_0051de80, nur Version 0x7ED00109):
  u32 magic 0x7ED00109, u32 Abschnittslänge (inkl. Kopf), u32 Punkte (u16 genutzt),
  u32 Verbindungen gesamt, u32 Namen (u16), u32 Frame-Verweise (u16), u32 Akteur-Verweise (u16)
  Punkt (FUN_00524620): f32 x,y,z; u32 @0x0C; u16 @0x10; u8 @0x12; u8 @0x13 (Spurbreite, ×1/16 m);
        u16 @0x14 Flags (Bits 0..5 = Anzahl Verbindungen, 0x40 = Endmarke im Speicher,
        0x100 = von HUMAN_DriveNearPlayer ausgeschlossen); 10 B Rest; dann Anzahl × (u16 Ziel, u16 Wert)
  Name (FUN_0051c7b0): u16 Punktindex, char[16]
  Frame-Verweis (FUN_0051c870): u16 Punktindex, C-String (Frame-Name)
  Akteur-Verweis (FUN_0051c910): u16 Punktindex, C-String (Frame-Name, dessen Akteur)

Koordinaten wie scene.json: (x, y, -z).

Aufruf:
  python -I tools/fmt_drive.py <MISSION> [ziel.json]
  python -I tools/fmt_drive.py --all          (24 Kampagnenmissionen -> orig_cache/<m>/drive.json)
  python -I tools/fmt_drive.py --survey       (Abschnitte/Versionen aller Missionen in Missions.dta)
  python -I tools/fmt_drive.py --check        (alle HUMAN_Drive-Namen der Skripte auflösen)
"""
import json
import os
import re
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fmt_actors_items as fai  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.environ.get("DH2_CACHE") or os.path.join(ROOT, "DangerousHidden2", "orig_cache")
MAGIC = 0x7ED00109
CAMPAIGN = ["ARCTIC1", "ARCTIC2", "ARCTIC3", "ARCTIC4", "AFRICA1", "AFRICA2", "AFRICA3", "AFRICA4",
            "AFRICA5", "AFRICA6", "NORWAY", "BURMA1", "BURMA2", "ALPS1", "ALPS2", "NORMANDY",
            "NORMANDY2", "CZECH1", "CZECH2", "CZECH3", "CZECH4", "CZECH5", "CZECH6", "TUTORIAL"]
SPEED_FACTOR = 0.28      # hd2.exe 0x80F71C: Skript-kmh × 0,28 = m/s
ARRIVE_DIST = 2.0        # 0x80F9F8 = 4,0 (Abstand²) -> 2 m um den Zielpunkt
NODE_SNAP = 10.0         # FUN_0055f320: nächster Netzknoten im Umkreis 10 m (Start und Ziel)
NEAR_PLAYER_RADIUS = 20.0  # Opcode 0x2B: 20,0 (0x41A00000)


def cpos(p):
    return [round(p[0], 4), round(p[1], 4), round(-p[2], 4)]


def _cstr(d, p):
    e = d.index(b"\0", p)
    return d[p:e].decode("latin-1"), e + 1


def parse_section(d, base):
    """Ein Netz-Abschnitt ab Offset base. Rückgabe (dict, Ende)."""
    magic, size, npts, nlinks, nnames, nframes, nactors = struct.unpack_from("<7I", d, base)
    if magic != MAGIC:
        raise ValueError("Abschnitt @%#x: Magie %#x (nur 0x7ED00109 wird vom Spiel gelesen)" % (base, magic))
    p = base + 28
    nodes = []
    nl_total = 0
    for i in range(npts & 0xFFFF):
        x, y, z, u0c, u10, b12, width, flags = struct.unpack_from("<3fIHBBH", d, p)
        rest = d[p + 0x16:p + 0x20]
        cnt = flags & 0x3F
        links = [list(struct.unpack_from("<HH", d, p + 32 + 4 * k)) for k in range(cnt)]
        nl_total += cnt
        nodes.append({"raw": (x, y, z), "u0c": u0c, "u10": u10, "b12": b12, "width": width,
                      "flags": flags, "rest": rest.hex(), "links": links})
        p += 32 + 4 * cnt
    names = []
    for _ in range(nnames & 0xFFFF):
        idx = struct.unpack_from("<H", d, p)[0]
        nm = d[p + 2:p + 18].split(b"\0")[0].decode("latin-1")
        names.append((nm, idx))
        p += 18
    frames = []
    for _ in range(nframes & 0xFFFF):
        idx = struct.unpack_from("<H", d, p)[0]
        s, p = _cstr(d, p + 2)
        frames.append((s, idx))
    actors = []
    for _ in range(nactors & 0xFFFF):
        idx = struct.unpack_from("<H", d, p)[0]
        s, p = _cstr(d, p + 2)
        actors.append((s, idx))
    sec = {"offset": base, "size": size, "end": p, "nodes": nodes, "links_header": nlinks,
           "links_counted": nl_total, "names": names, "frames": frames, "actors": actors}
    return sec, p


def parse_check2(d):
    """Alle Abschnitte der Datei (das Spiel liest die ersten zwei)."""
    secs = []
    p = 0
    while p + 28 <= len(d):
        sec, end = parse_section(d, p)
        if end != p + sec["size"]:
            raise ValueError("Abschnitt @%#x: Ende %#x != Kopflänge %#x" % (p, end, p + sec["size"]))
        secs.append(sec)
        p = end
    if p != len(d):
        raise ValueError("Rest %d Bytes" % (len(d) - p))
    return secs


def lookup(names, key):
    """Wie FUN_0051e1a0: _strnicmp(Name, Schlüssel, 16), erster Treffer; sonst None."""
    k = key[:16].lower()
    for nm, idx in names:
        if nm[:16].lower() == k:
            return idx
    return None


def read_check2(mission):
    d, src = fai.read_orig("missions\\%s\\check2.bin" % mission, "Missions.dta")
    return d, src


def network_json(sec):
    nodes = sec["nodes"]
    out_nodes = []
    for n in nodes:
        # Verbindung: [Zielknoten, Kosten]; Kosten ≈ Abstand × 224 (empirisch, Median 223,9)
        out_nodes.append({"pos": cpos(n["raw"]), "width_m": n["width"] / 16.0, "flags": n["flags"],
                          "near_player_excluded": bool(n["flags"] & 0x100),
                          "links": [[t, v] for t, v in n["links"]]})
    return {
        "nodes": out_nodes,
        "names": [{"name": nm, "node": idx, "pos": cpos(nodes[idx]["raw"]) if idx < len(nodes) else None}
                  for nm, idx in sec["names"]],
        "frame_refs": [{"frame": s, "node": i} for s, i in sec["frames"]],
        "actor_refs": [{"frame": s, "node": i} for s, i in sec["actors"]],
    }


def build(mission):
    d, src = read_check2(mission)
    if d is None:
        return None
    secs = parse_check2(d)
    res = {
        "mission": mission,
        "source": "missions\\%s\\check2.bin (%s), Abschnitt 2 = Fahrzeugnetz" % (mission, src),
        "coords": "glTF/Godot wie scene.json: (x, y, -z)",
        "semantics": {
            "speed_factor_kmh_to_mps": SPEED_FACTOR,
            "arrive_dist_m": ARRIVE_DIST,
            "node_snap_radius_m": NODE_SNAP,
            "near_player_radius_m": NEAR_PLAYER_RADIUS,
            "name_match": "case-insensitive, erste 16 Zeichen, erster Treffer",
        },
        "sections": len(secs),
        "vehicle": network_json(secs[1]) if len(secs) > 1 else None,
    }
    return res


# --- Skriptnamen ---------------------------------------------------------------

RX_DRIVE = re.compile(r'HUMAN_Drive\s*\(\s*"([^"]*)"\s*,\s*(-?\d+)\s*\)', re.I)


def strip_comments(t):
    t = re.sub(r"/\*.*?\*/", "", t, flags=re.S)
    return re.sub(r"//[^\n]*", "", t)


def script_drive_names(mission):
    sdir = os.path.join(CACHE, mission.lower(), "scripts")
    out = []
    if not os.path.isdir(sdir):
        return out
    for fn in sorted(os.listdir(sdir)):
        if not fn.lower().endswith(".scr"):
            continue
        with open(os.path.join(sdir, fn), "rb") as f:
            t = strip_comments(f.read().decode("latin-1"))
        for m in RX_DRIVE.finditer(t):
            out.append((fn, m.group(1), int(m.group(2))))
    return out


def check(missions):
    tot = res = empty = 0
    unresolved = []
    for m in missions:
        d, _ = read_check2(m)
        secs = parse_check2(d) if d else []
        vn = secs[1]["names"] if len(secs) > 1 else []
        wn = secs[0]["names"] if secs else []
        uses = script_drive_names(m)
        r = 0
        e = 0
        for fn, nm, kmh in uses:
            if nm == "":
                e += 1
                continue
            if lookup(vn, nm) is not None:
                r += 1
            else:
                hint = "im Fußnetz" if lookup(wn, nm) is not None else ""
                near = [n for n, _ in vn if n.strip().lower() == nm.strip().lower()]
                if near:
                    hint = "Fahrnetz-Name mit Leerzeichen: %r" % near[0]
                unresolved.append((m, fn, nm, kmh, hint))
        print("%-10s Aufrufe %3d  leer %3d  aufgelöst %3d/%3d" % (m, len(uses), e, r, len(uses) - e))
        tot += len(uses) - e
        res += r
        empty += e
    print("SUMME: benannte Aufrufe %d, aufgelöst %d (%.1f %%), leere Namen (Halt) %d"
          % (tot, res, 100.0 * res / max(tot, 1), empty))
    for u in unresolved:
        print("  NICHT AUFGELÖST: %s %s %r kmh=%d %s" % u)
    return unresolved


def survey():
    names = fai.mission_names()
    for m in names:
        d, src = read_check2(m)
        if d is None:
            print("%-22s -" % m)
            continue
        try:
            secs = parse_check2(d)
        except Exception as ex:
            print("%-22s FEHLER %s" % (m, ex))
            continue
        parts = []
        for s in secs:
            edges = {(i, t) for i, n in enumerate(s["nodes"]) for t, _ in n["links"]}
            oneway = sum(1 for i, t in edges if (t, i) not in edges)
            parts.append("P%d L%d/%d(1w %d) N%d F%d A%d" % (
                len(s["nodes"]), s["links_counted"], s["links_header"], oneway,
                len(s["names"]), len(s["frames"]), len(s["actors"])))
        print("%-22s %-9s %d Abschn.  %s" % (m, src, len(secs), " | ".join(parts)))


def main(argv):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    if argv[0] == "--survey":
        survey()
        return 0
    if argv[0] == "--check":
        check(CAMPAIGN)
        return 0
    missions = CAMPAIGN if argv[0] == "--all" else [argv[0].upper()]
    for m in missions:
        res = build(m)
        if res is None:
            print(m, "keine check2.bin")
            continue
        dst = argv[1] if len(argv) > 1 and argv[0] != "--all" else os.path.join(CACHE, m.lower(), "drive.json")
        with open(dst, "w", encoding="utf-8") as f:
            json.dump(res, f, ensure_ascii=False, indent=1)
        v = res["vehicle"]
        print("%-10s Abschnitte %d  Fahrnetz: %d Knoten, %d Namen -> %s" % (
            m, res["sections"], len(v["nodes"]) if v else 0, len(v["names"]) if v else 0, dst))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
