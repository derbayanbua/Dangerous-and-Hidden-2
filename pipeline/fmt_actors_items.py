"""Hidden & Dangerous 2 (LS3D, v1.12): Akteursparameter (actors.bin 0xAE24), Inventar
(missions\\<m>\\items.dat) und Gegenstandstabelle (TABLES\\items.sav).

Reverse Engineering (hd2.exe, Belege in DangerousHidden2/docs/re_notes_actors_items.md):
  - Mensch (Akteurtyp 3): Parameterleser = vtable 0x8111E0 [+0x34] = FUN_0059E800
  - Hund   (Akteurtyp 30): Parameterleser = vtable 0x8120E0 [+0x34] = FUN_005D6630
  - items.sav: Lader FUN_007DC500, Basisdatensatz FUN_007DFCF0
  - items.dat: Lader um 0x7D8240 (Version 16)

Nur Analyse/Konvertierung; Originaldaten werden nicht verändert und nicht ins Spiel kopiert.

Aufruf:
  python -I tools/fmt_actors_items.py ARCTIC1 <actor_params.json>   (schreibt zusätzlich orig_cache/items.json)
  python -I tools/fmt_actors_items.py survey                         (Wertebereiche aller Missionen)
"""
import json
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

ORIG = r"D:\Workspace_D\HD2_orig"
CACHE = r"D:\Workspace_D\DangerousHidden2\orig_cache"

# --------------------------------------------------------------------------- Menschen
# Reihenfolge der 12 u32-Werte = Akteursfelder +0xEC..+0x118 (Standardwerte aus Konstruktor 0x59BF00)
HUMAN_STATS = [
    ("health", 800),        # +0xEC  Lebenspunkte (aktuell); Kopie +0x11C = Maximum; Anzeige % = cur/max
    ("strength", 80),       # +0xF0  UI "Strenght" (Ganzzahl)
    ("endurance", 80),      # +0xF4  UI "Endurance" (Ganzzahl)
    ("morale", 80),         # +0xF8  versteckt; KI-Schwellen 90/75; "Update Morale"
    ("shooting", 80),       # +0xFC  UI "Shooting" (%)
    ("skill5_unknown", 80), # +0x100 nicht angezeigt, nicht trainiert, von Schwierigkeit skaliert
    ("stealth", 50),        # +0x104 UI "Stealth" (%)
    ("first_aid", 30),      # +0x108 UI "First aid" (%)
    ("lockpick", 20),       # +0x10C UI "Lockpick" (%)
    ("sight_range", 50),    # +0x110 m; Skriptbefehl HUMAN_SETSIGHTRANGE (Opcode 0xD3) schreibt hierher
    ("speech_set", 0),      # +0x114 Index in TABLES\speech.set (0 => "have empty speechset")
    ("hear_range", 80),     # +0x118 m; Skriptbefehl HUMAN_SETHEARRANGE (Opcode 0xD4) schreibt hierher
]

SIDES = {1: "player/allied squad", 2: "enemy (axis)", 3: "neutral/friendly NPC",
         4: "allied NPC (stats from profile)", 5: "hostile, stats from profile"}

# Schwierigkeitsskalierung (FUN_005A8990, nur Seite 2 beim Init FUN_0059F2C0)
DIFFICULTY_SCALE = {
    1: {"health": 0.7, "morale": 0.9, "skills_3_8": 0.7},
    2: {"health": 0.85, "morale": 0.95, "skills_3_8": 0.85},
    3: {"health": 1.0, "morale": 1.0, "skills_3_8": 1.0},
    4: {"note": "skills idx 2..8 (endurance..lockpick) set to 100, health unchanged"},
}


def decode_human_params(p: bytes) -> dict:
    """actors.bin 0xAE24 eines Menschen (Akteurtyp 3), Versionen 11..15."""
    v = p[0]
    if v < 11:
        raise ValueError("human params version %d < 11 (loader rejects)" % v)
    o = 1
    side, group = struct.unpack_from("<ii", p, o); o += 8
    stats = struct.unpack_from("<12i", p, o); o += 48
    profile = struct.unpack_from("<i", p, o)[0]; o += 4
    d = {"version": v, "side": side, "side_name": SIDES.get(side, "?"), "group": group}
    for (name, _default), val in zip(HUMAN_STATS, stats):
        d[name] = val
    d["profile"] = profile
    flags = {}
    if v >= 12:
        flags["counted_flag"] = p[o]; o += 1          # +0x1A4
    if v >= 13:
        flags["noncombatant_flag"] = p[o]; o += 1     # +0x1A5
    if v >= 14:
        flags["checks_list_flag"] = p[o]; o += 1      # +0x1A6
    d.update(flags)
    if v >= 15:
        t = struct.unpack_from("<i", p, o)[0]; o += 4
        d["name_text_id"] = -1 if t == 0 else t       # +0x1A8 (0 -> -1 wie Lader)
    else:
        d["name_text_id"] = -1
    if o != len(p):
        d["_trailing_bytes"] = len(p) - o
    return d


def decode_dog_params(p: bytes) -> dict:
    """actors.bin 0xAE24 eines Hundes (Akteurtyp 30): u32 Version + 4 x i32 (+0x4A0..+0x4AC)."""
    ver, health, bite, sight, hear = struct.unpack_from("<5i", p, 0)
    return {"version": ver, "health": health, "bite_damage": bite,
            "sight_range": sight, "hear_range": hear}


# --------------------------------------------------------------------------- items.sav
ITEM_KINDS = {0: "ammo", 1: "weapon", 2: "equipment"}
# Verhaltensblock-Code (Basisdatensatz +0x80) -> serialisierte Groesse (vfunc +4 der Klassen)
BEHAVIOUR_SIZE = {1: 0x24, 2: 0x28, 3: 0x88, 4: 0x80, 5: 0x10, 6: 0x0C, 7: 0x0C, 8: 0x1C, 9: 0x10, 10: 0}
BEHAVIOUR_NAME = {1: "melee", 2: "placed_explosive", 3: "projectile_launcher", 4: "firearm"}


def _cs(b):
    return b.split(b"\0")[0].decode("latin-1")


def _i(b, o):
    return struct.unpack_from("<i", b, o)[0]


def _f(b, o):
    return round(struct.unpack_from("<f", b, o)[0], 6)


def _decode_behaviour(code, b):
    """b = Rohdaten des Verhaltensblocks (ab Feld dw0)."""
    if code == 4:   # Schusswaffe (Klasse 0x817314, 0x58 Byte + 2 x char[20])
        return {
            "handling_f": _f(b, 8),            # 0.6 Pistole / 0.8 MP / 1.0 Gewehr / 1.2 Schrotflinte (unklar)
            "damage": _f(b, 12),               # Schaden (zotti); vgl. item_shoot.tbl f6
            "u4": _i(b, 16),
            "fire_interval_ms": _f(b, 20),     # min. Schussabstand (Repetierer 1400, Automaten 100)
            "anim_class": _i(b, 24),           # 13 Pistole, 12 Gewehr, 11 MP, 65 MG (vermutet)
            "flag7": b[28],
            "u8": _i(b, 32),
            "u9": _i(b, 36),
            "u10": _i(b, 40),
            "reload_ms": _f(b, 44),
            "muzzle_velocity": _f(b, 48),      # m/s
            "dist_param": _f(b, 52),           # vermutl. Reichweite/Abfall in m
            "recoil_spread": _f(b, 56),        # Grundstreuung/Rückstoß
            "aim_spread": _f(b, 60),           # Zielstreuung (ZF-Varianten klein)
            "spread_f16": _f(b, 64),
            "u17": _i(b, 68),
            "u18": _i(b, 72),
            "short_name": _cs(b[76:84]),
            "f21": _f(b, 84),
        }
    if code == 3:   # Werfer/Granate/Geschütz (Klasse 0x817348, 0x60 Byte + 2 x char[20])
        return {
            "f2": _f(b, 8), "damage_f3": _f(b, 12), "u4": _i(b, 16),
            "interval_ms": _f(b, 20), "anim_class": _i(b, 24), "flag7": b[28],
            "short_name": _cs(b[32:40]), "u10": _i(b, 40), "u11": _i(b, 44),
            "reload_ms": _f(b, 48), "velocity": _f(b, 52), "f14": _f(b, 56),
            "f15": _f(b, 60), "f16": _f(b, 64), "f17": _f(b, 68), "u18": _i(b, 72),
            "fuse_ms": _i(b, 76),
        }
    return {"raw_u32": [_i(b, k) for k in range(0, len(b) - 3, 4)]}


def parse_items(d: bytes) -> list:
    """TABLES\\items.sav: 500 Slots; Slot = u32 belegt; [u32 Art, 500 Byte Daten]. Slotindex = Item-ID."""
    out = []
    p = 0
    for slot in range(500):
        if p + 4 > len(d):
            break
        present = struct.unpack_from("<I", d, p)[0]; p += 4
        if not present:
            continue
        kind = struct.unpack_from("<I", d, p)[0]
        if kind not in (0, 1, 2):     # Lader: unbekannte Art -> Slot leer, nur 4 Byte weiter
            p += 4
            continue
        b = d[p + 4:p + 504]; p += 504
        it = {
            "id": slot, "kind": ITEM_KINDS[kind],
            "fpv_model": _cs(b[0x00:0x14]), "icon": _cs(b[0x14:0x28]), "model": _cs(b[0x28:0x3C]),
            "u3c": _i(b, 0x3C), "name": _cs(b[0x50:0x64]).strip(),
            "text_id": _i(b, 0x64), "weight_kg": _f(b, 0x68), "size_class": _i(b, 0x6C),
            "u70": _i(b, 0x70), "u74": _i(b, 0x74), "u78": _i(b, 0x78), "team_flag": _i(b, 0x7C),
        }
        o = 0x80
        behaviours = []
        for _ in range(2):
            code = _i(b, o); o += 4
            if code == 0:
                continue
            size = BEHAVIOUR_SIZE.get(code, 0)
            blk = b[o:o + size]; o += size
            beh = {"code": code, "type": BEHAVIOUR_NAME.get(code, "code%d" % code)}
            beh.update(_decode_behaviour(code, blk))
            behaviours.append(beh)
        it["behaviours"] = behaviours
        tail = 0xA8 + sum(BEHAVIOUR_SIZE.get(bh["code"], 0) for bh in behaviours)
        if kind == 0:
            it["rounds"] = _f(b, tail)                          # Ammo +0x54
        elif kind == 1:
            it["inv_w"], it["inv_h"], it["u60"], it["ammo_item"] = struct.unpack_from("<4i", b, tail)
        else:
            it["equip_raw"] = list(struct.unpack_from("<5i", b, tail))
        out.append(it)
    return out


def weapon_table(items: list) -> list:
    """Kompakte Waffentabelle (nur Schusswaffen) inkl. Magazin aus dem Munitionsgegenstand."""
    by_id = {it["id"]: it for it in items}
    rows = []
    for it in items:
        fa = [b for b in it.get("behaviours", []) if b["code"] == 4]
        if it["kind"] != "weapon" or not fa:
            continue
        f = fa[0]
        ammo = by_id.get(it.get("ammo_item", -1))
        iv = f["fire_interval_ms"]
        rows.append({
            "id": it["id"], "name": it["name"], "short_name": f["short_name"],
            "damage": f["damage"], "fire_interval_ms": iv,
            "rate_rpm": round(60000.0 / iv) if iv else None,
            "reload_ms": f["reload_ms"], "muzzle_velocity": f["muzzle_velocity"],
            "dist_param": f["dist_param"], "aim_spread": f["aim_spread"],
            "recoil_spread": f["recoil_spread"], "weight_kg": it["weight_kg"],
            "ammo_item": it.get("ammo_item"), "ammo_name": ammo["name"] if ammo else None,
            "magazine": int(ammo["rounds"]) if ammo and ammo.get("rounds", -1) > 0 else None,
            "inv_size": [it.get("inv_w"), it.get("inv_h")],
        })
    return rows


# --------------------------------------------------------------------------- items.dat
SLOTS = {0: "head/generic", 1: "pack (ammo, pistol, grenades)", 2: "weapon (hand?)",
         3: "weapon (shoulder?)", 4: "uniform", 5: "backpack"}


def parse_items_dat(d: bytes) -> list:
    """missions\\<m>\\items.dat (Version 13..16): Inventar je Akteur bzw. frei platzierte Gegenstände."""
    ver = struct.unpack_from("<I", d, 0)[0]
    p = 4
    out = []
    while p + 4 <= len(d):
        try:
            ln = struct.unpack_from("<I", d, p)[0]; p += 4
            owner = d[p:p + ln + 1].split(b"\0")[0].decode("latin-1"); p += ln + 1   # Lader liest len+1 Byte
            slot, item, idx, placed = struct.unpack_from("<4i", d, p); p += 16
            rec = {"owner": owner, "slot": slot, "item": item, "index": idx}
            if placed:
                if ver <= 14:
                    pos = struct.unpack_from("<3f", d, p); rot = struct.unpack_from("<4f", d, p + 12); p += 28
                else:
                    pos = struct.unpack_from("<3f", d, p + 0); rot = struct.unpack_from("<4f", d, p + 16); p += 32
                rec["pos"] = [round(x, 4) for x in pos]
                rec["rot"] = [round(x, 6) for x in rot]
            if ver > 13:
                rec["flag_a"] = struct.unpack_from("<i", d, p)[0]; p += 4
            if ver > 15:
                rec["flag_b"] = struct.unpack_from("<i", d, p)[0]; p += 4
            out.append(rec)
        except struct.error:
            break       # abgeschnittene Datei (z. B. NORMANDY3_MP_ZONE)
    return out


# --------------------------------------------------------------------------- Archivzugriff
_ARCH = {}


def _archive(name):
    from dta_extract import Archive
    if name not in _ARCH:
        _ARCH[name] = Archive(os.path.join(ORIG, name))
    return _ARCH[name]


def read_orig(path: str, base_archive: str):
    """Liest path aus patch.dta (v1.12), sonst aus dem Basisarchiv. Rückgabe (bytes, quelle)."""
    for arc in ("patch.dta", base_archive):
        try:
            a = _archive(arc)
        except Exception:
            continue
        for e in a.entries:
            if e[0].lower() == path.lower():
                try:
                    return a.read(e), arc
                except Exception:
                    continue
    return None, None


def mission_names():
    a = _archive("Missions.dta")
    names = set()
    for e in a.entries:
        parts = e[0].split("\\")
        if len(parts) == 3 and parts[2].lower() == "actors.bin":
            names.add(parts[1])
    return sorted(names)


# --------------------------------------------------------------------------- CLI
def build_mission(mission: str):
    from fmt_scene2 import parse_actor_defs
    actors_raw, a_src = read_orig("MISSIONS\\%s\\actors.bin" % mission, "Missions.dta")
    items_raw, i_src = read_orig("MISSIONS\\%s\\items.dat" % mission, "Missions.dta")
    sav_raw, s_src = read_orig("TABLES\\items.sav", "others.DTA")
    items = parse_items(sav_raw)
    by_id = {it["id"]: it for it in items}
    inv = parse_items_dat(items_raw) if items_raw else []
    loadout = {}
    for r in inv:
        it = by_id.get(r["item"])
        e = {"slot": r["slot"], "slot_name": SLOTS.get(r["slot"], "?"), "item": r["item"],
             "name": it["name"] if it else None, "kind": it["kind"] if it else None}
        if "pos" in r:
            e["pos"] = r["pos"]; e["rot"] = r["rot"]
        loadout.setdefault(r["owner"], []).append(e)
    defs = parse_actor_defs(actors_raw)
    actors = {}
    for name, (typ, params) in sorted(defs.items()):
        rec = {"actor_type": typ}
        if typ == 3:
            rec["params"] = decode_human_params(params)
        elif typ == 30:
            rec["params"] = decode_dog_params(params)
        else:
            rec["params_hex"] = params.hex() if len(params) <= 128 else None
        lo = loadout.get(name)
        if lo:
            # zusammengefasst: Waffe(n), Munition, Rest
            weapons = [x for x in lo if x["kind"] == "weapon" and x["slot"] in (2, 3)]
            sidearms = [x for x in lo if x["kind"] == "weapon" and x["slot"] not in (2, 3)]
            counts = {}
            for x in lo:
                counts[x["name"]] = counts.get(x["name"], 0) + 1
            rec["weapon"] = weapons[0]["name"] if weapons else (sidearms[0]["name"] if sidearms else None)
            rec["weapon_id"] = weapons[0]["item"] if weapons else (sidearms[0]["item"] if sidearms else None)
            rec["inventory"] = lo
            rec["inventory_counts"] = counts
        actors[name] = rec
    other = {k: v for k, v in loadout.items() if k not in defs}
    return {
        "mission": mission,
        "sources": {"actors.bin": a_src, "items.dat": i_src, "items.sav": s_src},
        "human_stat_order": [n for n, _ in HUMAN_STATS],
        "slot_names": SLOTS,
        "actors": actors,
        "non_actor_stores": other,   # z. B. MG-Nester, Kisten, frei platzierte Gegenstände (Owner "")
    }, items


def survey():
    from fmt_scene2 import parse_actor_defs
    import collections
    cols = collections.defaultdict(collections.Counter)
    dogs = []
    for m in mission_names():
        raw, src = read_orig("MISSIONS\\%s\\actors.bin" % m, "Missions.dta")
        if not raw:
            continue
        for name, (t, p) in parse_actor_defs(raw).items():
            if t == 3:
                for k, v in decode_human_params(p).items():
                    if not isinstance(v, str):
                        cols[k][v] += 1
            elif t == 30:
                dogs.append((m, name, decode_dog_params(p)))
    for k, c in cols.items():
        vals = [x for x in c if x is not None]
        print("%-18s n=%4d min=%s max=%s top=%s" % (k, sum(c.values()), min(vals), max(vals), c.most_common(8)))
    for x in dogs:
        print("dog", x)


def main(argv):
    if len(argv) >= 2 and argv[1] == "survey":
        survey()
        return
    if len(argv) < 2:
        print(__doc__)
        return
    mission = argv[1].upper()
    out = argv[2] if len(argv) > 2 else os.path.join(CACHE, mission.lower(), "actor_params.json")
    data, items = build_mission(mission)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    items_out = os.path.join(CACHE, "items.json")
    with open(items_out, "w", encoding="utf-8") as f:
        json.dump({"source": data["sources"]["items.sav"], "items": items,
                   "weapons": weapon_table(items)}, f, ensure_ascii=False, indent=1)
    print("geschrieben:", out, "(%d Akteure)" % len(data["actors"]), "|", items_out, "(%d Items)" % len(items))


if __name__ == "__main__":
    main(sys.argv)
