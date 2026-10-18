"""Mehrspielerkarten (HD2 v1.12) -> orig_cache/<ordner>/mp.json + orig_cache/mp_maps.json.

Aufruf:  pyenv\\Scripts\\python.exe -I fmt_mp.py [ORDNER ...]      (ohne Argument: alle MP-Ordner)
Voraussetzung: Ordner vorher mit convert_all.ps1 konvertiert (scene.json, interactive.json, scene.glb).

Quellen (nur gelesen): HD2_orig\\mpmaplist.txt (= GameData\\mpmaplist.txt aus patch.dta), Missions.dta/patch.dta
(actors.bin: Zonen-Dummy-BBox Chunk 0x4050; mpscripts.dta/scripts.dta: Skriptzuordnung), Scripts.dta (Skripte),
GameData\\presets.def (Klassen), Texte texts_german.json, items.json.
Belege und Feldbedeutungen: docs/re_notes_multiplayer.md. Koordinaten wie scene.json: glTF/Godot, Position (x, y, -z).
"""
import json
import math
import os
import re
import struct
import sys
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import convert_mission as CM  # noqa: E402  (read_file, archive, ORIG, CACHE)
import fmt_interactive as FI  # noqa: E402  (World, Matrizen)
import fmt_scene2 as S2  # noqa: E402

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
ORIG, CACHE = CM.ORIG, CM.CACHE

# hd2.exe 0x83EC48: feste Liste der 30 zulässigen MP-Ordner; der mpmaplist-Parser (0x618A00) übernimmt nur
# MAP-Einträge, deren dir hier steht (0x6189C0, stricmp)  [B]
WHITELIST = ["Africa1_mp", "Africa3_mp", "Africa5_mp", "Arctic1_mp", "Arctic2_mp", "Burma1_mp", "Czech3_mp",
             "Normandy_mp", "africa2_mp_zone", "Africa5_mp_zone", "Alps1_mp_zone", "Arctic4_mp_zone",
             "Burma1_mp_zone", "Czech2_mp_zone", "Czech4_mp_zone", "Czech5_mp_zone", "Czech6_mp_zone",
             "Normandy2_mp_zone", "NORMANDY2B_MP_ZONE", "Normandy3_mp", "Africa1_obj", "Africa3_obj", "Africa4_obj",
             "Arctic1_obj", "Arctic3_obj", "Burma1_obj", "Burma2_obj", "Czech1_obj", "Czech2_obj", "Czech3_obj"]

# GAMESTYLE type (mpmaplist) -> Spielstil-Nummer im Server-Config (+0x224) und Texte  [B: 0x618A00, 0x722DE0]
STYLES = {
    "deathmatch": {"style": 0, "name": "deathmatch", "text_id": 2891, "points_text_id": 2602},
    "teamplay": {"style": 1, "name": "occupation", "text_id": 2892, "points_text_id": 2603},
    "hd2multiplayer": {"style": 2, "name": "objectives", "text_id": 2893, "points_text_id": 2604},
}
OWNER = {0: "axis", 1: "allied", 2: "neutral"}
TEAM = {0: "axis", 1: "allied", 2: "both"}


def load_json(p, default=None):
    try:
        return json.load(open(p, encoding="utf-8"))
    except Exception:
        return default


TEXTS = load_json(os.path.join(CACHE, "texts_german.json"), {})
TEXTS = TEXTS.get("texts", TEXTS) if isinstance(TEXTS, dict) else {}
_items = load_json(os.path.join(CACHE, "items.json"), {}) or {}
ITEMS = {i["id"]: i for i in _items.get("items", [])}


def text(tid):
    if tid is None or tid < 0:
        return None
    return TEXTS.get(str(tid))


def item_name(iid):
    it = ITEMS.get(iid)
    return it.get("name") if it else None


# ------------------------------------------------------------------------------------------------- mpmaplist

def read_mpmaplist():
    """Wie hd2.exe 0x618A00: zuerst 'mpmaplist.txt' im Spielordner, sonst GameData\\mpmaplist.txt (Archiv)."""
    p = os.path.join(ORIG, "mpmaplist.txt")
    if os.path.exists(p):
        return open(p, "rb").read(), "HD2_orig\\mpmaplist.txt"
    return CM.read_file("GameData/mpmaplist.txt", ["others.DTA"]), "GameData\\mpmaplist.txt (Archiv)"


def parse_mpmaplist(data):
    root = ET.fromstring(data.decode("latin-1"))
    out = []   # Liste von Karteneinträgen je Spielstil
    for gs in root.findall("GAMESTYLE"):
        typ = gs.get("type")
        st = STYLES.get(typ)
        for m in gs.findall("MAP"):
            e = {"style_type": typ, "style": st["style"] if st else None, "style_name": st["name"] if st else typ,
                 "style_text_id": st["text_id"] if st else None, "style_text": text(st["text_id"]) if st else None,
                 "name": m.get("name"), "dir": m.get("dir"),
                 "in_whitelist": any(m.get("dir", "").lower() == w.lower() for w in WHITELIST),
                 "mode": m.get("mode"), "frontline": (m.get("mode") or "").upper() == "FRONTLINE",
                 "desc_text_id": int(m.get("desc")) if m.get("desc") else None}
            b = m.find("BALANCED")
            if b is not None:
                e["balanced"] = {"allied": int(b.get("allied")), "axis": int(b.get("axis"))}
            a = m.find("AIRCRAFTATACK")
            if a is not None:
                e["aircraft_attack"] = {"allied": int(a.get("allied", "0")), "axis": int(a.get("axis", "0"))}
            ai = m.find("ALLOWEDITEMS")
            if ai is not None:
                lst = []
                for it in ai.findall("ITEM"):
                    iid = int(it.get("item_id"))
                    rec = {"item_id": iid, "name": item_name(iid), "item_num": int(it.get("item_num", "-1"))}
                    if it.get("ammo_num") is not None:
                        rec["ammo_num"] = int(it.get("ammo_num"))
                        am = (ITEMS.get(iid) or {}).get("ammo_item")
                        if am is not None and am >= 0:
                            rec["ammo_item"] = am
                            rec["ammo_name"] = item_name(am)
                    lst.append(rec)
                e["allowed_items_version"] = ai.get("version")
                e["allowed_items"] = lst
                # Seitenzuordnung über items.sav +0x7C (hd2.exe Gegenstand +0x44): 0 Alliierte, 1 Achse, 2 beide,
                # 3 nicht wählbar; der Original-Code filtert Ersatzgegenstände bei Achsen-Uniform auf Kennung 1
                # (0x6777A0/0x679850) [B Daten, P Zuordnung je Seite] – docs/re_notes_multiplayer.md §1.7a
                by_side = {"allied": [], "axis": []}
                for rec in lst:
                    tf = (ITEMS.get(rec["item_id"]) or {}).get("team_flag", 2)
                    rec["team_flag"] = tf
                    if tf in (0, 2):
                        by_side["allied"].append(rec["item_id"])
                    if tf in (1, 2):
                        by_side["axis"].append(rec["item_id"])
                e["allowed_items_by_side"] = by_side
            ap = m.find("ALLOWEDPRESETS")
            if ap is not None and ap.text:
                e["allowed_presets"] = re.findall(r'"([^"]+)"', ap.text)
            objs = []
            for i, o in enumerate(m.findall("OBJECTIVE")):
                side = (o.get("side") or "ALLIED").upper()
                # side = Team, dem das Ziel bei SetObjectiveStatus(i, 1) gutgeschrieben wird (Standard ALLIED)
                # [B: Parser 0x618A00, Gutschrift 0x69BA60 -> 0x69B900]
                rec = {"index": i + 1, "type": "VIP" if (o.get("type") or "").upper() == "VIP" else "normal",
                       "side": "axis" if side == "AXIS" else "allied",
                       "side_team": 0 if side == "AXIS" else 1,
                       "value": int(o.get("value")) if o.get("value") else None,
                       "allied_text_id": int(o.get("allied_text")) if o.get("allied_text") else None,
                       "axis_text_id": int(o.get("axis_text")) if o.get("axis_text") else None}
                rec["allied_text"] = text(rec["allied_text_id"])
                rec["axis_text"] = text(rec["axis_text_id"])
                if rec["type"] == "VIP":
                    rec["vip_uniform_id"] = int(o.get("vip_uniform_id", "-1"))
                    rec["vip_uniform"] = item_name(rec["vip_uniform_id"])
                    rec["vip_team"] = "allied" if rec["side_team"] == 0 else "axis"   # VIP = Gegenseite [B 0x69D9C0]
                objs.append(rec)
            if objs:
                e["objectives"] = objs
            out.append(e)
    return out


def read_presets():
    """GameData\\presets.def (u32 Version, u32 Anzahl, je 0x1B8 Bytes; Aufbau docs/re_notes_profiles.md §3)."""
    d = CM.read_file("GameData/presets.def", ["others.DTA"])
    res = {}
    if not d:
        return res
    ver, n = struct.unpack_from("<II", d, 0)
    for i in range(n):
        o = 8 + i * 440
        name = d[o:o + 32].split(b"\0")[0].decode("latin-1")
        slots = list(struct.unpack_from("<5i", d, o + 32))
        na = struct.unpack_from("<i", d, o + 52)[0]
        la = [struct.unpack_from("<2i", d, o + 56 + 8 * k) for k in range(14)][:max(0, na)]
        nb = struct.unpack_from("<i", d, o + 168)[0]
        lb = [struct.unpack_from("<2i", d, o + 172 + 8 * k) for k in range(32)][:max(0, nb)]
        flags, tid, _ = struct.unpack_from("<3i", d, o + 428)
        res[name] = {"index": i, "name": name, "flags": flags, "text_id": tid, "text": text(tid),
                     "side": "allied" if flags & 32 else ("axis" if flags & 16 else None),
                     "slots": [{"item_id": s, "name": item_name(s)} for s in slots],
                     "list_a": [{"item_id": a, "count": c, "name": item_name(a)} for a, c in la],
                     "list_b": [{"item_id": a, "count": c, "name": item_name(a)} for a, c in lb]}
    return res


# ------------------------------------------------------------------------------------------------- Kartenordner

def mp_folders():
    names = set()
    for a in ["Missions.dta", "patch.dta"]:
        for key in CM.archive(a).index:
            m = re.match(r"missions\\([^\\]+)\\scene\.4ds$", key)
            if m and re.search(r"_mp|_obj", m.group(1)):
                names.add(m.group(1).upper())
    return sorted(names)


def script_map(folder):
    """mpscripts.dta (MP) bzw. scripts.dta: Paare Frame -> Skriptdatei (Chunk-Format wie scripts.dta)."""
    res = {}
    for fn in ("mpscripts.dta", "scripts.dta"):
        d = CM.read_file("missions/%s/%s" % (folder, fn), ["Missions.dta"])
        if not d:
            continue
        p, pair, mp = 6, [], {}
        while p + 6 <= len(d):
            t, ln = struct.unpack_from("<HI", d, p)
            if ln < 6:
                break
            pair.append(d[p + 6:p + ln].split(b"\0")[0].decode("latin-1"))
            p += ln
            if len(pair) == 2:
                mp[pair[0]] = pair[1]
                pair = []
        res[fn] = mp
    return res


def script_facts(mdir):
    """Je Skript: verwendete Ziel-Nummern (SetObjectiveStatus) und MP-Befehle."""
    out = {}
    sdir = os.path.join(mdir, "scripts")
    if not os.path.isdir(sdir):
        return out
    for fn in sorted(os.listdir(sdir)):
        txt = open(os.path.join(sdir, fn), "rb").read().decode("latin-1")
        code = re.sub(r"//[^\n]*", "", txt)
        objs = sorted({(int(a), int(b)) for a, b in re.findall(r"SetObjectiveStatus\s*\(\s*(\d+)\s*,\s*(\d+)", code)})
        mpc = sorted(set(re.findall(r"\b(_?MP_\w+)", code)))
        if objs or mpc:
            out[fn] = {"set_objective_status": [list(x) for x in objs], "mp_commands": mpc}
    return out


def dummy_bboxes(folder):
    """Lokale BBox (Chunk 0x4050: min xyz, max xyz) aller Objekte aus actors.bin/scene2.bin."""
    res = {}
    for fn in ("actors.bin", "scene2.bin"):
        d = CM.read_file("missions/%s/%s" % (folder, fn), ["Missions.dta"])
        if not d:
            continue
        try:
            _, objs = S2.parse(d)
        except Exception:
            continue
        for o in objs:
            ch = o["chunks"].get(0x4050)
            if ch and o.get("name") and o["name"] not in res:
                s, e = ch
                if e - s >= 24:
                    mn = struct.unpack_from("<3f", d, s)
                    mx = struct.unpack_from("<3f", d, s + 12)
                    res[o["name"]] = (mn, mx)
    return res


def decode_zone(raw):
    """MPZone (Akteurtyp 37) – Leser hd2.exe 0x5EDA60, Felder s. re_notes_multiplayer.md §4."""
    b = bytes.fromhex(raw)
    p = 0
    first = struct.unpack_from("<i", b, p)[0]
    p += 4
    z = {}
    if first < 0x8001:
        z["version"] = 0
        z["index"] = first
    else:
        z["version"] = first
        z["index"] = struct.unpack_from("<i", b, p)[0]
        p += 4
    z["shape_code"], z["initial_owner"], z["name_text_id"] = struct.unpack_from("<3i", b, p)
    p += 12
    flags = []
    for k in range(3):
        flags.append(b[p:p + 16].split(b"\0")[0].decode("latin-1"))
        p += 16
    z["flag_frames"] = {"axis": flags[0] or None, "allied": flags[1] or None, "neutral": flags[2] or None}
    z["objective"], z["capture_time_s"] = struct.unpack_from("<2i", b, p)
    p += 8
    # +0xAC: 1 = Besetzungsregeln (anwesende Besitzer/Gleichstand blockieren, je capture_time/2 neutralisieren
    # und einnehmen); 0 = Einweg-Zone (nur Gegner des Anfangsbesitzers, einmalig)  [B 0x5EC060/0x5ECF20]
    z["ac_occupation_rules"] = bool(b[p]) if (z["version"] > 0x8000 and p < len(b)) else False
    return z


def world_of(W, name):
    m = W.world(name)
    return FI.decompose(m) if m is not None else None, m


def glb_aabb(mdir):
    """Welt-AABB aller Meshes der scene.glb (Plausibilitätsprüfung)."""
    p = os.path.join(mdir, "scene.glb")
    if not os.path.exists(p):
        return None
    j = FI.glb_json(p)
    nodes, acc, meshes = j.get("nodes", []), j.get("accessors", []), j.get("meshes", [])
    lo, hi = [1e30] * 3, [-1e30] * 3
    stack = [(r, FI.IDENT) for r in (j["scenes"][j.get("scene", 0)]["nodes"] if j.get("scenes") else [])]
    n_mesh = 0
    while stack:
        i, P = stack.pop()
        n = nodes[i]
        if "matrix" in n:
            mm = n["matrix"]
            L = [[mm[c * 4 + r] for c in range(4)] for r in range(4)]
        else:
            L = FI.trs_matrix(n.get("translation", [0, 0, 0]), n.get("rotation", [0, 0, 0, 1]), n.get("scale", [1, 1, 1]))
        M = FI.mat_mul(P, L)
        if "mesh" in n:
            n_mesh += 1
            for pr in meshes[n["mesh"]]["primitives"]:
                a = acc[pr["attributes"]["POSITION"]]
                for x in (a["min"][0], a["max"][0]):
                    for y in (a["min"][1], a["max"][1]):
                        for zz in (a["min"][2], a["max"][2]):
                            v = FI.mat_apply(M, [x, y, zz])
                            lo = [min(lo[k], v[k]) for k in range(3)]
                            hi = [max(hi[k], v[k]) for k in range(3)]
        for c in n.get("children", []):
            stack.append((c, M))
    if not n_mesh:
        return {"nodes": len(nodes), "mesh_nodes": 0}
    return {"nodes": len(nodes), "mesh_nodes": n_mesh, "min": [round(v, 2) for v in lo], "max": [round(v, 2) for v in hi]}


def inside(aabb, pos, margin=5.0):
    if not aabb or "min" not in aabb or pos is None:
        return None
    return all(aabb["min"][k] - margin <= pos[k] <= aabb["max"][k] + margin for k in range(3))


# ------------------------------------------------------------------------------------------------- je Karte

def build(folder, maplist, presets):
    mdir = os.path.join(CACHE, folder.lower())
    scene = load_json(os.path.join(mdir, "scene.json"))
    inter = load_json(os.path.join(mdir, "interactive.json"))
    entries = [e for e in maplist if (e["dir"] or "").lower() == folder.lower()]
    res = {"folder": folder, "coords": "glTF/Godot wie scene.json: Position (x, y, -z), Rotation (x, y, z, w)",
           "listed_in_mpmaplist": bool(entries),
           "in_hd2_whitelist": any(folder.lower() == w.lower() for w in WHITELIST),
           "playable_in_original": bool(entries) and any(e["in_whitelist"] for e in entries),
           "map_name": entries[0]["name"] if entries else None,
           "title_note": "Kartentitel = mpmaplist name (kein Text-ID-Attribut 'desc' in v1.12)",
           "game_styles": [], "teams": {"0": {"name": "axis", "text_id": 2621, "text": text(2621)},
                                         "1": {"name": "allied", "text_id": 2620, "text": text(2620)}}}
    for e in entries:
        g = {k: v for k, v in e.items() if k not in ("dir",)}
        if "allowed_presets" in g:
            g["presets"] = [presets.get(n, {"name": n, "missing": True}) for n in g["allowed_presets"]]
        res["game_styles"].append(g)
    if scene is None or inter is None:
        res["error"] = "nicht konvertiert (scene.json/interactive.json fehlt)"
        return res
    W = FI.World(mdir, scene)
    aabb = glb_aabb(mdir)
    res["scene_aabb"] = aabb
    # --- Spawnpunkte (Typ 10): +0x90 MP-Spawn, +0x94 Team  [B: Auswahl 0x475840]
    sps = []
    for s in inter.get("spawn_points", []):
        pr = s.get("params", {})
        w = s.get("world") or {}
        mp_flag, team = pr.get("u90_?"), pr.get("u94_?")
        sps.append({"name": s["name"], "pos": w.get("pos"), "rot": w.get("rot"),
                    "mp_spawn": mp_flag == 1, "team": team, "team_name": TEAM.get(team),
                    "sp_profile_a4": pr.get("ua4_?"), "u98": pr.get("u98_?"), "ua0": pr.get("ua0_?"),
                    "inside_scene_aabb": inside(aabb, w.get("pos"))})
    res["spawn_points"] = sps
    # --- Zonen (Typ 37)
    bbs = dummy_bboxes(folder)
    zones = []
    objs_by_parent = {}
    for o in scene.get("objects", []):
        objs_by_parent.setdefault(o.get("parent", ""), []).append(o)
    for o in inter.get("other", []):
        if o.get("actor_type") != 37:
            continue
        z = decode_zone(o["raw"])
        z["name"] = o["name"]
        z["name_text"] = text(z["name_text_id"])
        z["initial_owner_name"] = OWNER.get(z["initial_owner"])
        z["shape"] = {0: "box", 1: "sphere"}.get(z["shape_code"], "none")
        wd, wm = world_of(W, o["name"])
        z["world"] = wd
        bb = bbs.get(o["name"], ((-0.5, -0.5, -0.5), (0.5, 0.5, 0.5)))
        mn, mx = bb
        z["bbox_local"] = {"min": [round(v, 4) for v in mn], "max": [round(v, 4) for v in mx],
                           "source": "Chunk 0x4050" if o["name"] in bbs else "Standard ±0,5 (nicht gefunden)"}
        if wm is not None:
            c_l = [(mn[k] + mx[k]) / 2 for k in range(3)]
            c_l = [c_l[0], c_l[1], -c_l[2]]           # LS3D-lokal -> glTF-lokal (z gespiegelt)
            z["center"] = [round(v, 3) for v in FI.mat_apply(wm, c_l)]
            sc = wd["scale"]
            half = [abs(mx[k] - mn[k]) / 2 for k in range(3)]
            if z["shape"] == "sphere":
                r_l = math.sqrt(sum(h * h for h in half))   # |min - Mitte| im lokalen Raum
                z["radius_local"] = round(r_l, 4)
                z["radii_world"] = [round(r_l * sc[k], 3) for k in range(3)]
            elif z["shape"] == "box":
                z["half_extents_world"] = [round(half[k] * sc[k], 3) for k in range(3)]
            z["inside_scene_aabb"] = inside(aabb, z["center"])
        z["capturable"] = z["capture_time_s"] > 0
        z["objective_text"] = None
        for k, fr in list(z["flag_frames"].items()):
            if fr:
                fw, _ = world_of(W, fr)
                z["flag_frames"][k] = {"frame": fr, "pos": fw["pos"] if fw else None}
        sf = o["name"] + "spawn"     # hd2.exe 0x5ED110: Frame "<Zone>spawn", Kinder = Spawnplätze
        sw, _ = world_of(W, sf)
        slots = []
        for c in sorted(objs_by_parent.get(sf, []), key=lambda x: x.get("name", "")):
            cw, _ = world_of(W, c["name"])
            if cw:
                slots.append({"name": c["name"], "pos": cw["pos"], "rot": cw["rot"],
                              "inside_scene_aabb": inside(aabb, cw["pos"])})
        z["spawn_frame"] = {"name": sf, "found": sw is not None, "pos": sw["pos"] if sw else None}
        z["spawn_slots"] = slots
        zones.append(z)
    zones.sort(key=lambda z: (z["index"], z["name"]))
    # Zielzonen mit Zieltext verknüpfen
    for g in res["game_styles"]:
        for ob in g.get("objectives", []):
            for z in zones:
                if z["objective"] == ob["index"]:
                    z["objective_text"] = {"allied": ob["allied_text"], "axis": ob["axis_text"]}
    res["zones"] = zones
    res["scripts"] = {"assignments": script_map(folder), "facts": script_facts(mdir)}
    # Kurzfassung / Prüfungen
    flat = [x for x in sps] + [s for z in zones for s in z["spawn_slots"]]
    res["checks"] = {"spawn_points": len(sps), "mp_spawn_points": sum(1 for s in sps if s["mp_spawn"]),
                     "zones": len(zones), "zone_spawn_slots": sum(len(z["spawn_slots"]) for z in zones),
                     "positions_outside_scene_aabb": sum(1 for s in flat if s.get("inside_scene_aabb") is False),
                     "zone_spawn_frames_missing": [z["name"] for z in zones if not z["spawn_frame"]["found"]]}
    return res


def main(argv):
    data, src = read_mpmaplist()
    maplist = parse_mpmaplist(data)
    presets = read_presets()
    folders = [a.upper() for a in argv] or mp_folders()
    summary = []
    for f in folders:
        r = build(f, maplist, presets)
        r["mpmaplist_source"] = src
        out = os.path.join(CACHE, f.lower(), "mp.json")
        os.makedirs(os.path.dirname(out), exist_ok=True)
        json.dump(r, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
        c = r.get("checks", {})
        summary.append({"folder": f, "map_name": r["map_name"], "listed_in_mpmaplist": r["listed_in_mpmaplist"],
                        "playable_in_original": r["playable_in_original"],
                        "styles": [{"type": g["style_type"], "style": g["style_name"], "mode": g.get("mode"),
                                    "objectives": len(g.get("objectives", []))} for g in r["game_styles"]],
                        "spawn_points": c.get("spawn_points"), "mp_spawn_points": c.get("mp_spawn_points"),
                        "zones": c.get("zones"), "zone_spawn_slots": c.get("zone_spawn_slots"),
                        "outside_aabb": c.get("positions_outside_scene_aabb"), "error": r.get("error"),
                        "file": "%s/mp.json" % f.lower()})
        print("%-20s %-10s styles=%s spawns=%s/%s zones=%s slots=%s outside=%s %s" % (
            f, r["map_name"], [s["style"] for s in summary[-1]["styles"]], c.get("mp_spawn_points"),
            c.get("spawn_points"), c.get("zones"), c.get("zone_spawn_slots"), c.get("positions_outside_scene_aabb"),
            r.get("error") or ""))
    if not argv:
        json.dump({"source": src, "whitelist_hd2exe_0x83EC48": WHITELIST,
                   "styles": {k: dict(v, text=text(v["text_id"]), points_text=text(v["points_text_id"]))
                              for k, v in STYLES.items()},
                   "maplist": maplist, "maps": summary},
                  open(os.path.join(CACHE, "mp_maps.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
        print("-> mp_maps.json (%d Ordner, %d mpmaplist-Einträge)" % (len(summary), len(maplist)))


if __name__ == "__main__":
    main(sys.argv[1:])
