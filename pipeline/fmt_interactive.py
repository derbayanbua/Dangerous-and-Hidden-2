"""Interaktive Weltobjekte von Hidden & Dangerous 2 (v1.12): Tueren, Leitern, Schalter, Sprengpunkte,
zerstoerbare Objekte, MG-/Flak-Stellungen, Kisten u. a. – Parameter-Dekoder + Weltlage.

Quelle der Definitionen: Akteursdefinitionen 0xAE20 > 0xAE21 {0xAE22 Typ, 0xAE23 Name, 0xAE24 Parameter}
  * in missions\\<m>\\actors.bin (Akteure mit eigenem Objekt in actors.bin) UND
  * in missions\\<m>\\scene2.bin (Akteure, die auf vorhandene Frames zeigen: v. a. TUEREN, Typ 6).
Die Parameterleser sind die vtable-Slots +0x34 der Akteursklassen in hd2.exe (Belege und Konfidenz in
DangerousHidden2/docs/re_notes_interactive.md).

Aufruf:
  pyenv\\Scripts\\python.exe -I fmt_interactive.py ARCTIC1 [ziel.json]
      -> DangerousHidden2/orig_cache/<mission>/interactive.json
  pyenv\\Scripts\\python.exe -I fmt_interactive.py --survey     (Typenzaehlung ueber alle Missionen)

Koordinaten: wie scene.json (glTF/Godot: x, y, -z; Quaternion xyzw). Weltlage wird ueber die Elternkette
aufgeloest: scene.glb-Frames (scene.4ds) > scene.json-Objekte > Akteure; "Objekt.Frame" = Frame im Modell
des Objekts (models/<modell>.glb). Eltern "Primary sector"/leer = Ursprung (wie src/orig/orig_level.gd).
"""
import json
import math
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fmt_scene2  # noqa: E402
import fmt_actors_items as fai  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ORIG = os.environ.get("DH2_ORIG") or os.path.join(ROOT, "HD2_orig")
CACHE = os.environ.get("DH2_CACHE") or os.path.join(ROOT, "DangerousHidden2", "orig_cache")

# Klassenname je Typ: Rueckgabe der Fabrik-Methode (+4) der Erzeuger bei 0x839460[typ] (hd2.exe) [B]
CLASS_NAMES = {
    2: "?(Mine)", 3: "Human", 4: "Car", 5: "Barrel", 6: "Door", 7: "Radio", 8: "Ladder", 9: "SupplyBox",
    10: "SpawnPoint", 11: "Item", 12: "Debris", 13: "Switch", 14: "Train", 15: "Photo place",
    20: "Submarine", 21: "StaticWeapon", 22: "Explosive place", 23: "Document place", 25: "Animation",
    27: "Clock", 28: "Pike", 29: "FowlGenerator", 30: "Dog", 31: "Bike", 32: "Fish", 33: "NullActor",
    34: "Junkers88", 35: "WireCut", 36: "AirAttack", 37: "MPZone", 38: "Explosion [TS]",
}

# Ausgabegruppen fuer interactive.json
GROUPS = {6: "doors", 8: "ladders", 13: "switches", 22: "explosive_places", 25: "destructibles",
          5: "barrels", 21: "emplacements", 9: "crates", 7: "radios", 15: "photo_places",
          23: "document_places", 4: "vehicles", 10: "spawn_points", 20: "submarines", 14: "trains",
          27: "clocks", 29: "birds", 32: "fish", 30: "dogs", 33: "null_actors", 34: "ju88",
          36: "air_attacks", 28: "barriers"}


# ============================================================================ Hilfen: Bytes/Chunks

def _u8(b, o):
    return b[o]


def _i32(b, o):
    return struct.unpack_from("<i", b, o)[0]


def _f32(b, o):
    return round(struct.unpack_from("<f", b, o)[0], 6)


def _cstr(b):
    return b.split(b"\0")[0].decode("latin-1")


def subchunks(b, start=0, end=None):
    """Chunkfolge u16 id + u32 Laenge (inkl. 6-Byte-Kopf). Liefert [(id, daten)] (unvollstaendige Reste -> stop)."""
    end = len(b) if end is None else end
    out = []
    p = start
    while p + 6 <= end:
        cid, ln = struct.unpack_from("<HI", b, p)
        if ln < 6 or p + ln > end:
            break
        out.append((cid, b[p + 6:p + ln]))
        p += ln
    return out


# ============================================================================ Dekoder je Typ
# Feldnamen mit Suffix "_?" = Bedeutung nicht belegt (nur Lage im Objekt bekannt).

DOOR_SOUND_SLOTS = ["open", "closed", "moving", "lock", "unlock", "wrong_key", "lockpick", "slot7_?",
                    "locked_rattle"]


def decode_door(p: bytes) -> dict:
    """Typ 6 Door, Leser 0x601AC0 (Objekt +0x2xx). 39 Byte fester Kopf, dann Chunks 0x65..0x6D."""
    d = {
        "motion": _i32(p, 0),             # +0x220: 0 = Drehtuer (0x5FF700), 1 = Schiebetuer/-tor (0x5FFBD0)
        "initial_state": _i32(p, 4),      # +0x224: 0 zu, 1 offen (Laufzeit: 2 oeffnet, 3 schliesst)
        "open_amount": _f32(p, 8),        # +0x228: Drehwinkel rad (Drehtuer) bzw. Weg m (Schiebetuer)
        "speed": _f32(p, 12),             # +0x22C: rad/s bzw. m/s (x dt_ms x 0.001)
        "axis_ls3d": [_f32(p, 16), _f32(p, 20), _f32(p, 24)],   # +0x210 Achse (LS3D, Frame-lokal)
        "key_item": _i32(p, 28),          # +0x230: Schluessel-Item-ID (-1 = kein Schluessel noetig)
        "locked": bool(_u8(p, 32)),       # +0x234
        "u23c_?": _u8(p, 38),             # +0x23C (alle bekannten Daten: 1)
        # Defaults laut Konstruktor 0x5FF210:
        "sounds": [-1] * 9, "has_room_?": False, "partner_door": None, "auto_close": True,
        "flag_99_?": 1, "open_dir_ls3d": None, "flag_190_?": 0, "lockpickable": True,
        "label_text": 7153, "no_grenade_room": 0,
    }
    d["axis_gltf"] = [d["axis_ls3d"][0], d["axis_ls3d"][1], -d["axis_ls3d"][2]]
    for cid, c in subchunks(p, 39):
        if cid == 0x65 and len(c) >= 36:
            d["sounds"] = list(struct.unpack_from("<9i", c, 0))
        elif cid == 0x66:
            d["has_room_?"] = bool(c[0])          # +0xA0: Portal/Sektor-Verknuepfung (0x600A50)
        elif cid == 0x67:
            d["partner_door"] = _cstr(c)         # +0x120: Name des Fluegels einer Doppeltuer
        elif cid == 0x68:
            d["auto_close"] = bool(c[0])         # +0x98: von KI geoeffnet -> nach 15 s wieder zu
        elif cid == 0x69:
            d["flag_99_?"] = c[0]                # +0x99
        elif cid == 0x6A and len(c) >= 12:
            d["open_dir_ls3d"] = [_f32(c, 0), _f32(c, 4), _f32(c, 8)]   # +0x200 (Editor-berechnet)
        elif cid == 0x6B:
            d["flag_190_?"] = c[0]               # +0x190: setzt Kollisionsflag 0x100000 der Tuer
        elif cid == 0x6C:
            d["lockpickable"] = bool(c[0])       # +0x235: Menue "Schloss aufbrechen" moeglich
        elif cid == 0x6D and len(c) >= 5:
            d["label_text"] = _i32(c, 0)         # +0x114 (HUD-Name, Std 7153 "Tuer")
            d["no_grenade_room"] = c[4]          # +0x118: sperrt Befehl "Granate in den Raum"
    if d["open_dir_ls3d"]:
        v = d["open_dir_ls3d"]
        d["open_dir_gltf"] = [v[0], v[1], -v[2]]
    d["sound_slots"] = {DOOR_SOUND_SLOTS[i]: s for i, s in enumerate(d["sounds"]) if s != -1}
    d["motion_name"] = {0: "rotate", 1: "slide"}.get(d["motion"], "?")
    return d


def decode_ladder(p: bytes) -> dict:
    """Typ 8 Ladder, Leser 0x5EBBD0: u8 Version, i32 +0x170, +0x174, +0x178, (v>1) i32 +0x17C, (v>2) u8 +0x180."""
    v = p[0]
    d = {"version": v, "label_text": _i32(p, 1), "climb_sound": _i32(p, 5), "fast_down_sound": _i32(p, 9),
         "u17c_?": 1, "u180_?": 0}
    if v > 1 and len(p) >= 17:
        d["u17c_?"] = _i32(p, 13)
    if v > 2 and len(p) >= 18:
        d["u180_?"] = p[17]
    return d


def decode_switch(p: bytes) -> dict:
    """Typ 13 Switch, Leser 0x613E10: Chunk 0 -> +0xD4 Startzustand (1..3), Chunk 1 -> +0xD8 Klang (-1 keiner)."""
    d = {"initial_state": 1, "sound": -1}
    for cid, c in subchunks(p):
        if cid == 0 and len(c) >= 4:
            d["initial_state"] = _i32(c, 0)
        elif cid == 1 and len(c) >= 4:
            d["sound"] = _i32(c, 0)
    return d


def decode_explosive_place(p: bytes) -> dict:
    """Typ 22 Explosive place, Leser 0x60CA30 (Defaults Konstruktor 0x60C230)."""
    d = {"label_text": 7161, "has_timer": True, "required_item": 68, "timer_ms": 0,
         "explosion_sound": -1, "particle_?": -1, "strength_?": 0, "radius_?": 0,
         "armed_at_start": False, "hidden": False}
    for cid, c in subchunks(p):
        if cid == 0x64 and len(c) >= 5:
            d["label_text"] = _i32(c, 0)      # +0x9C
            d["has_timer"] = bool(c[4])       # +0x98: Countdown laeuft (0 = Magnetmine ohne Zeitzuender)
        elif cid == 0x65 and len(c) >= 4:
            d["required_item"] = _i32(c, 0)   # +0xA0: benoetigter Gegenstand (items.sav-ID)
        elif cid == 0x66 and len(c) >= 4:
            d["timer_ms"] = _i32(c, 0)        # +0xA4
        elif cid == 0x67 and len(c) >= 16:
            a, b, s, r = struct.unpack_from("<4i", c, 0)
            d["explosion_sound"] = a          # +0xA8 (IngameSounds Kategorie 6 "Explosion")
            d["particle_?"] = b               # +0xAC (Effekt-ID an 0x451DB0)
            d["strength_?"] = s               # +0xB0 (Explosionsstruktur +0x14)
            d["radius_?"] = r                 # +0xB4 (Explosionsstruktur +0x10, Std. dort 10.0)
        elif cid == 0x68 and len(c) >= 1:
            d["armed_at_start"] = bool(c[0])  # +0xB8: Init im Zustand 1 statt 0
        elif cid == 0x69 and len(c) >= 1:
            d["hidden"] = bool(c[0])          # +0xB9: Zustand 0 ohne Markierung/Text ("Hidden ...")
    return d


def decode_supply_box(p: bytes) -> dict:
    """Typ 9 SupplyBox, Leser 0x5FC200: u8 Version, 5x i32, 10+10 Item-IDs, i32 Text."""
    if len(p) < 105:
        return {"raw_len": len(p)}
    ver = p[0]
    equip, u120, maxc, u12c, u134 = struct.unpack_from("<5i", p, 1)
    la = [x for x in struct.unpack_from("<10i", p, 21) if x != -1]
    lb = [x for x in struct.unpack_from("<10i", p, 61) if x != -1]
    return {"version": ver, "equipment_box": bool(equip),   # +0x11C: 0 Munitionskiste, 1 Gegenstandskiste
            "u120_?": u120, "take_limit": maxc,              # +0x128: Menue aktiv solange Bestand des Soldaten < Wert
            "u12c_?": u12c, "u134_?": u134,
            "items_list_a": la, "items_list_b": lb,          # +0xFC/+0x10C-Vektor, Auswahl je Seite (0x5A8820)
            "label_text": _i32(p, 101)}                      # +0x210


def decode_animation(p: bytes) -> dict:
    """Typ 25 Animation (zerstoerbar/animiert), Leser 0x5B5AF0, Zerstoerung 0x5B55E0."""
    d = {"anim_file": "", "health": -1.0, "u_a2_?": 0, "destroy_sound": -1, "particle_?": -1,
         "frame_name_?": "", "label_text": -1, "u_a4_?": 0}
    for cid, c in subchunks(p):
        if cid == 0:
            d["anim_file"] = _cstr(c)
        elif cid == 1 and len(c) >= 4:
            d["health"] = _f32(c, 0)          # +0xD0 (<-1 -> -1); Schaden in +0xD4 aufsummiert
        elif cid == 2 and c:
            d["u_a2_?"] = c[0]
        elif cid == 3 and len(c) >= 4:
            d["destroy_sound"] = _i32(c, 0)   # +0xA8 (Kategorie 6 "Explosion")
        elif cid == 4 and len(c) >= 4:
            d["particle_?"] = _i32(c, 0)      # +0xAC (an 0x4451B0)
        elif cid == 5:
            d["frame_name_?"] = _cstr(c)
        elif cid == 6 and len(c) >= 4:
            d["label_text"] = _i32(c, 0)      # +0xB0
        elif cid == 7 and c:
            d["u_a4_?"] = c[0]
    d["indestructible_by_damage"] = d["health"] < 0
    return d


def decode_barrel(p: bytes) -> dict:
    """Typ 5 Barrel, Leser 0x60A280: Wurzelchunk 0x3039 mit Unterchunks 2000..13000 (Bedeutung weitgehend offen)."""
    d = {}
    root = subchunks(p)
    body = root[0][1] if root else b""
    names = {2000: "lid_frame_?", 3000: "f_c4_?", 4000: "f_c0_?", 5000: "f_cc_?", 6000: "u_dc_?",
             7000: "body_frame_?", 8000: "s_8000_?", 9000: "u_138_?", 10000: "u8_144_?",
             11000: "u_134_?", 12000: "f_140_?", 13000: "u8_200_?"}
    for cid, c in subchunks(body):
        k = names.get(cid, "c%d" % cid)
        if cid in (2000, 7000, 8000):
            d[k] = _cstr(c)
        elif cid in (3000, 4000, 5000, 12000) and len(c) >= 4:
            d[k] = _f32(c, 0)
        elif cid in (10000, 13000) and c:
            d[k] = c[0]
        elif len(c) >= 4:
            d[k] = _i32(c, 0)
    return d


def decode_radio(p: bytes) -> dict:
    """Typ 7 Radio, Leser 0x60AE40: 0x64 {+0x94 Klang, +0x98 benoetigtes Item}, 0x65 {+0x9C}."""
    d = {"active_sound": -1, "required_item": -1, "u9c_?": 2}
    for cid, c in subchunks(p):
        if cid == 0x64 and len(c) >= 8:
            d["active_sound"], d["required_item"] = struct.unpack_from("<2i", c, 0)
        elif cid == 0x65 and len(c) >= 4:
            d["u9c_?"] = _i32(c, 0)
    return d


def decode_photo_place(p: bytes) -> dict:
    d = {"label_text": -1}
    for cid, c in subchunks(p):
        if cid == 0x64 and len(c) >= 4:
            d["label_text"] = _i32(c, 0)
    d["required_item"] = 229        # Menue "Foto machen" nur mit Item 229 "Fotoaparat" (0x4B1C9A)
    return d


def decode_document_place(p: bytes) -> dict:
    d = {"label_text": 1255, "required_item": 68, "action_text": 7051}
    for cid, c in subchunks(p):
        if cid == 0x64 and len(c) >= 8:
            d["label_text"], d["required_item"] = struct.unpack_from("<2i", c, 0)
        elif cid == 0x65 and len(c) >= 4:
            d["action_text"] = _i32(c, 0)
    return d


def decode_spawn_point(p: bytes) -> dict:
    d = {}
    names = {0: "version", 1: "u90_?", 2: "u94_?", 3: "ua4_?", 4: "u98_?", 5: "ua0_?"}
    for cid, c in subchunks(p):
        if len(c) >= 4:
            d[names.get(cid, "c%d" % cid)] = _i32(c, 0)
    return d


def decode_submarine(p: bytes) -> dict:
    d = {}
    for cid, c in subchunks(p):
        if cid == 0 and len(c) >= 4:
            d["version"] = _i32(c, 0)
        elif cid == 1 and len(c) >= 4:
            d["f_d8_?"] = _f32(c, 0)
    return d


def decode_train(p: bytes) -> dict:
    d = {"wagons": []}
    cur = None
    for cid, c in subchunks(p):
        if cid == 1 and len(c) >= 4:
            d["version"] = _i32(c, 0)
        elif cid == 0x0A:
            cur = {"frame": _cstr(c), "f38_?": 10.0, "f3c_?": 3.0}
            d["wagons"].append(cur)
        elif cid == 0x14 and cur is not None and len(c) >= 4:
            cur["f38_?"] = _f32(c, 0)
        elif cid == 0x1E and cur is not None and len(c) >= 4:
            cur["f3c_?"] = _f32(c, 0)
    return d


def decode_fowl(p: bytes) -> dict:
    d = {}
    for cid, c in subchunks(p):
        if cid == 0 and len(c) >= 4:
            d["version"] = _i32(c, 0)
        elif cid == 1 and len(c) >= 4:
            d["ua0_?"] = _i32(c, 0)
        elif cid in (2, 3) and len(c) >= 4:
            d["f%s_?" % ("a8" if cid == 2 else "ac")] = _f32(c, 0)
        elif cid == 4 and len(c) >= 4:
            d["count_?"] = _i32(c, 0)
        elif cid == 5:
            d["name_?"] = _cstr(c)
    return d


def decode_fish(p: bytes) -> dict:
    if len(p) < 12:
        return {}
    return {"f_bc_?": _f32(p, 0), "f_c0_?": _f32(p, 4), "u_c4_?": _i32(p, 8)}


def decode_air_attack(p: bytes) -> dict:
    d = {}
    for cid, c in subchunks(p):
        if cid == 2 and len(c) >= 4:
            d["f158_?"] = _f32(c, 0)
        elif cid == 4 and len(c) >= 4:
            d["f15c_?"] = _f32(c, 0)
    return d


def decode_pike(p: bytes) -> dict:
    """Typ 28 Pike (Schranke/Schlagbaum), Leser 0x5B9C80: i32 +0x184 Zustand, f +0x18C, f +0x190,
    3 f Achse (+0x90), 3 i32 Klaenge (+0x194..). SetActorState: !=0 -> 2 (oeffnen), 0 -> 3 (schliessen)."""
    if len(p) < 36:
        return {"raw_len": len(p)}
    ax = [_f32(p, 12), _f32(p, 16), _f32(p, 20)]
    return {"initial_state": _i32(p, 0), "open_angle_?": _f32(p, 4), "speed_?": _f32(p, 8),
            "axis_ls3d": ax, "axis_gltf": [ax[0], ax[1], -ax[2]],
            "sounds": list(struct.unpack_from("<3i", p, 24))}


def decode_generic_chunks(p: bytes) -> dict:
    cs = subchunks(p)
    if not cs:
        return {}
    out = {}
    for cid, c in cs:
        out["c%d" % cid] = c.hex()
    return out


def decode_vehicle(p: bytes) -> dict:
    if len(p) < 8:
        return {}
    return {"version": _i32(p, 0), "body_len": _i32(p, 4), "note": "Fahrzeugdaten nicht dekodiert (Leser 0x4D10A0 -> 0x4E2E30)"}


def decode_params(typ: int, p: bytes) -> dict:
    try:
        if typ == 6:
            return decode_door(p)
        if typ == 8:
            return decode_ladder(p)
        if typ == 13:
            return decode_switch(p)
        if typ == 22:
            return decode_explosive_place(p)
        if typ == 9:
            return decode_supply_box(p)
        if typ == 25:
            return decode_animation(p)
        if typ == 5:
            return decode_barrel(p)
        if typ == 7:
            return decode_radio(p)
        if typ == 15:
            return decode_photo_place(p)
        if typ == 23:
            return decode_document_place(p)
        if typ == 10:
            return decode_spawn_point(p)
        if typ == 20:
            return decode_submarine(p)
        if typ == 14:
            return decode_train(p)
        if typ == 29:
            return decode_fowl(p)
        if typ == 32:
            return decode_fish(p)
        if typ == 36:
            return decode_air_attack(p)
        if typ == 30:
            return fai.decode_dog_params(p)
        if typ == 28:
            return decode_pike(p)
        if typ == 4:
            return decode_vehicle(p)
        if typ in (21, 27, 33):
            return {}          # Leser liefert sofort 1 / liest nichts
        return decode_generic_chunks(p)
    except Exception as ex:  # robust gegen abweichende Daten
        return {"decode_error": str(ex)}


# ============================================================================ Weltlage (glTF-Raum)

def _quat_to_mat3(q):
    x, y, z, w = q
    n = math.sqrt(x * x + y * y + z * z + w * w) or 1.0
    x, y, z, w = x / n, y / n, z / n, w / n
    return [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]


def trs_matrix(t, q, s):
    r = _quat_to_mat3(q)
    m = [[r[i][j] * s[j] for j in range(3)] + [t[i]] for i in range(3)]
    m.append([0.0, 0.0, 0.0, 1.0])
    return m


def mat_mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


IDENT = [[1.0, 0, 0, 0], [0, 1.0, 0, 0], [0, 0, 1.0, 0], [0, 0, 0, 1.0]]


def mat_apply(m, v):
    return [m[i][0] * v[0] + m[i][1] * v[1] + m[i][2] * v[2] + m[i][3] for i in range(3)]


def mat_dir(m, v):
    return [m[i][0] * v[0] + m[i][1] * v[1] + m[i][2] * v[2] for i in range(3)]


def decompose(m):
    t = [m[0][3], m[1][3], m[2][3]]
    sx = math.sqrt(sum(m[i][0] ** 2 for i in range(3)))
    sy = math.sqrt(sum(m[i][1] ** 2 for i in range(3)))
    sz = math.sqrt(sum(m[i][2] ** 2 for i in range(3)))
    r = [[m[i][0] / (sx or 1), m[i][1] / (sy or 1), m[i][2] / (sz or 1)] for i in range(3)]
    tr = r[0][0] + r[1][1] + r[2][2]
    if tr > 0:
        s = math.sqrt(tr + 1.0) * 2
        w, x, y, z = 0.25 * s, (r[2][1] - r[1][2]) / s, (r[0][2] - r[2][0]) / s, (r[1][0] - r[0][1]) / s
    elif r[0][0] > r[1][1] and r[0][0] > r[2][2]:
        s = math.sqrt(1.0 + r[0][0] - r[1][1] - r[2][2]) * 2
        w, x, y, z = (r[2][1] - r[1][2]) / s, 0.25 * s, (r[0][1] + r[1][0]) / s, (r[0][2] + r[2][0]) / s
    elif r[1][1] > r[2][2]:
        s = math.sqrt(1.0 + r[1][1] - r[0][0] - r[2][2]) * 2
        w, x, y, z = (r[0][2] - r[2][0]) / s, (r[0][1] + r[1][0]) / s, 0.25 * s, (r[1][2] + r[2][1]) / s
    else:
        s = math.sqrt(1.0 + r[2][2] - r[0][0] - r[1][1]) * 2
        w, x, y, z = (r[1][0] - r[0][1]) / s, (r[0][2] + r[2][0]) / s, (r[1][2] + r[2][1]) / s, 0.25 * s
    rnd = lambda v: [round(c, 5) for c in v]  # noqa: E731
    return {"pos": rnd(t), "rot": [round(c, 6) for c in (x, y, z, w)], "scale": rnd([sx, sy, sz])}


def _conj_rot(m):
    """Matrix mit transponiertem (= konjugiertem) Rotationsanteil, gleiche Translation/Skalierung."""
    d = decompose(m)
    x, y, z, w = d["rot"]
    return trs_matrix(d["pos"], [-x, -y, -z, w], d["scale"])


def glb_json(path):
    d = open(path, "rb").read()
    ln = struct.unpack_from("<I", d, 12)[0]
    return json.loads(d[20:20 + ln])


def glb_node_table(path):
    """{name: (lokale Matrix, Elternname|None)} fuer alle Knoten eines glb (erster Name gewinnt)."""
    j = glb_json(path)
    nodes = j.get("nodes", [])
    parent = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[c] = i
    out = {}
    for i, n in enumerate(nodes):
        if "matrix" in n:
            mm = n["matrix"]
            m = [[mm[c * 4 + r] for c in range(4)] for r in range(4)]
        else:
            m = trs_matrix(n.get("translation", [0, 0, 0]), n.get("rotation", [0, 0, 0, 1]), n.get("scale", [1, 1, 1]))
        nm = n.get("name", "#%d" % i)
        if nm not in out:
            out[nm] = (m, nodes[parent[i]].get("name") if i in parent else None, n.get("extras"))
    return out


class World:
    def __init__(self, mdir, scene):
        self.mdir = mdir
        self.scene_nodes = {}
        sg = os.path.join(mdir, "scene.glb")
        if os.path.exists(sg):
            self.scene_nodes = glb_node_table(sg)
        self.objs = {}
        for o in scene.get("objects", []) + scene.get("actors", []):
            self.objs.setdefault(o.get("name", ""), o)
        self.model_cache = {}
        self.cache = {}
        self.unresolved = set()

    def model_nodes(self, model):
        if model not in self.model_cache:
            p = os.path.join(self.mdir, "models", model.lower() + ".glb")
            self.model_cache[model] = glb_node_table(p) if os.path.exists(p) else None
        return self.model_cache[model]

    def _model_frame_world(self, model, frame, base, conj_parents=False):
        """Weltmatrix eines Frames im Modell-glb. conj_parents=True: Rotationen der VORFAHREN innerhalb des
        Modells konjugiert anwenden (Gegenprobe zur 4DS-Quaternionkonvention, s. re_notes_interactive.md)."""
        nodes = self.model_nodes(model)
        if not nodes or frame not in nodes:
            return None
        m = IDENT
        cur = frame
        guard = 0
        while cur is not None and guard < 64:
            lm, par, _ = nodes[cur]
            if conj_parents and cur != frame:
                lm = _conj_rot(lm)
            m = mat_mul(lm, m)
            cur = par
            guard += 1
        return mat_mul(base, m)

    def world(self, name, depth=0):
        """Weltmatrix (glTF) eines Namens oder None."""
        if name in ("", "Primary sector", None):
            return IDENT
        if name in self.cache:
            return self.cache[name]
        if depth > 40:
            return None
        res = None
        if name in self.scene_nodes:
            m, par, _ = self.scene_nodes[name]
            pm = self.world(par, depth + 1) if par else IDENT
            res = mat_mul(pm, m) if pm is not None else m
        elif name in self.objs:
            o = self.objs[name]
            lm = trs_matrix(o.get("pos", [0, 0, 0]), o.get("rot", [0, 0, 0, 1]), o.get("scale", [1, 1, 1]))
            par = o.get("parent", "")
            pm = self.world(par, depth + 1)
            if pm is None:
                self.unresolved.add(par)
                pm = IDENT
            res = mat_mul(pm, lm)
        elif "." in name:
            obj, frame = name.split(".", 1)
            base = self.world(obj, depth + 1)
            o = self.objs.get(obj)
            if base is not None and o and o.get("model"):
                res = self._model_frame_world(o["model"], frame, base)
        self.cache[name] = res
        return res

    def model_subframes(self, model, prefix):
        nodes = self.model_nodes(model) if model else None
        if not nodes:
            return []
        return [n for n in nodes if n.lower().startswith(prefix.lower())]


# ============================================================================ Nachschlagetabellen

def _load_json(path, default):
    try:
        return json.load(open(path, encoding="utf-8"))
    except Exception:
        return default


def load_lookups():
    texts = _load_json(os.path.join(CACHE, "texts_german.json"), {})
    items = {i["id"]: i for i in _load_json(os.path.join(CACHE, "items.json"), {}).get("items", [])}
    sounds = {}
    try:
        import fmt_mission_extra as fx
        read = fx._archive_reader()
        d = read("tables/IngameSounds.def", ["others.DTA"])
        if d:
            for t, s, e in fx.chunks(d, 0, len(d)):
                for ci, (t2, s2, e2) in enumerate(fx.chunks(d, s, e)):
                    names = []
                    for t3, s3, e3 in fx.chunks(d, s2, e2):
                        if t3 != 0x04B0:
                            continue
                        nm = ""
                        for t4, s4, e4 in fx.chunks(d, s3, e3):
                            if t4 == 0x04BA:
                                nm = fx.cstr(d, s4, e4)
                        names.append(nm)
                    sounds[ci] = names
    except Exception as ex:
        print("  Hinweis: IngameSounds.def nicht lesbar:", ex)
    return texts, items, sounds


def text_of(texts, tid):
    if tid is None or tid < 0:
        return None
    return texts.get(str(tid))


def item_of(items, iid):
    if iid is None or iid < 0:
        return None
    it = items.get(iid)
    return it["name"] if it else None


def sound_of(sounds, cat, sid):
    if sid is None or sid < 0:
        return None
    lst = sounds.get(cat) or []
    return lst[sid] if sid < len(lst) else None


# ============================================================================ Aufbau interactive.json

def read_mission_file(m, name):
    d, _ = fai.read_orig("missions\\%s\\%s" % (m, name), "Missions.dta")
    return d


def annotate(typ, d, texts, items, sounds):
    """Lesbare Zusatzfelder (Texte/Items/Klaenge)."""
    a = {}
    for k in ("label_text", "action_text"):
        if k in d and isinstance(d[k], int):
            a[k.replace("_text", "")] = text_of(texts, d[k])
    for k in ("required_item", "key_item"):
        if k in d and isinstance(d[k], int):
            a[k + "_name"] = item_of(items, d[k])
    if typ == 6:
        a["sound_names"] = {k: sound_of(sounds, 1, v) for k, v in d.get("sound_slots", {}).items()}
    elif typ == 8:
        a["climb_sound_name"] = sound_of(sounds, 0, d.get("climb_sound"))
        a["fast_down_sound_name"] = sound_of(sounds, 0, d.get("fast_down_sound"))
    elif typ == 13:
        a["sound_name"] = sound_of(sounds, 1, d.get("sound"))
    elif typ == 22:
        a["explosion_sound_name"] = sound_of(sounds, 6, d.get("explosion_sound"))
    elif typ == 25:
        a["destroy_sound_name"] = sound_of(sounds, 6, d.get("destroy_sound"))
    elif typ == 7:
        a["active_sound_name"] = sound_of(sounds, 1, d.get("active_sound"))
    elif typ == 9:
        a["items_list_a_names"] = [item_of(items, i) for i in d.get("items_list_a", [])]
        a["items_list_b_names"] = [item_of(items, i) for i in d.get("items_list_b", [])]
    return {k: v for k, v in a.items() if v not in (None, {}, [])}


def build(mission: str) -> dict:
    m = mission.upper()
    mdir = os.path.join(CACHE, m.lower())
    scene = _load_json(os.path.join(mdir, "scene.json"), {"objects": [], "actors": [], "scripts": {}})
    world = World(mdir, scene)
    texts, items, sounds = load_lookups()
    scripts = {k.lower(): v for k, v in scene.get("scripts", {}).items()}

    defs = []      # (name, typ, params, quelle)
    for src in ("scene2.bin", "actors.bin"):
        d = read_mission_file(m, src)
        if not d:
            continue
        for name, (typ, params) in fmt_scene2.parse_actor_defs(d).items():
            defs.append((name, typ, params, src))

    inv = {}
    idat = read_mission_file(m, "items.dat")
    if idat:
        for rec in fai.parse_items_dat(idat):
            if rec["owner"]:
                inv.setdefault(rec["owner"].lower(), []).append(
                    {"slot": rec["slot"], "item": rec["item"], "name": item_of(items, rec["item"])})

    actors_by = {a.get("name", ""): a for a in scene.get("actors", [])}
    out = {"mission": m,
           "coords": "glTF/Godot wie scene.json: pos (x,y,-z), rot xyzw; world = aufgeloeste Elternkette",
           "source": "actors.bin + scene2.bin, Chunk 0xAE20/0xAE21 (Typ 0xAE22, Name 0xAE23, Parameter 0xAE24)",
           "sound_tables": {"door/switch/radio": "IngameSounds.def Kategorie 1 'Object Manipulation'",
                            "ladder": "Kategorie 0 'Puppet Movement' (Annahme ueber Namen)",
                            "explosion": "Kategorie 6 'Explosion'"},
           "counts": {}}
    for g in sorted(set(GROUPS.values()) | {"other"}):
        out[g] = []
    for name, typ, params, src in defs:
        if typ == 3:
            continue                       # Menschen: actor_params.json (fmt_actors_items.py)
        dec = decode_params(typ, params)
        e = {"name": name, "actor_type": typ, "class": CLASS_NAMES.get(typ, "?"), "def_source": src,
             "params": dec, "raw": params.hex()}
        ann = annotate(typ, dec, texts, items, sounds)
        if ann:
            e["labels"] = ann
        a = actors_by.get(name)
        if a:
            e["model"] = a.get("model")
            e["parent"] = a.get("parent", "")
            e["local"] = {"pos": a.get("pos"), "rot": a.get("rot"), "scale": a.get("scale")}
        elif name in world.objs:
            o = world.objs[name]
            e["model"] = o.get("model")
            e["parent"] = o.get("parent", "")
            e["frame_kind"] = "scene2-Objekt"
        elif name in world.scene_nodes:
            e["frame_kind"] = "scene.4ds-Frame"
            e["parent"] = world.scene_nodes[name][1] or ""
        elif "." in name:
            e["frame_kind"] = "Modell-Frame"
        wm = world.world(name)
        if wm is not None:
            e["world"] = decompose(wm)
        else:
            e["world"] = None
            e["world_note"] = ("Frame weder in scene.glb noch in scene.json/Modellen gefunden – scene.glb "
                               "veraltet (convert_mission.py neu ausführen) oder Frame nur zur Laufzeit erzeugt")
            world.unresolved.add(name)
        if name.lower() in scripts:
            e["script"] = scripts[name.lower()]
        if name.lower() in inv:
            e["inventory"] = inv[name.lower()]
        # typabhaengige Zusatzgeometrie
        if typ == 8 and wm is not None and e.get("model"):
            # Dummies "up*"/"down*" im Leitermodell (0x5EA5D0); Weltlage wie im konvertierten glb.
            # Frühere Ersatzrechnung mit konjugierten Vorfahren-Rotationen entfällt: crot_xyzw ist korrekt
            # (Gegenprobe m_a1_zebrik01/02, re_notes_interactive.md Abschnitt 5) – liegt up dennoch unter down,
            # ist die glb veraltet bzw. die Konvertierung fehlerhaft -> nur melden, nicht kaschieren.
            pts = {}
            for key, pre in (("top", "up"), ("bottom", "down")):
                fr = world.model_subframes(e["model"], pre)
                if fr:
                    fm = world._model_frame_world(e["model"], fr[0], wm)
                    pts[key] = [round(c, 4) for c in mat_apply(fm, [0, 0, 0])]
            if "top" in pts and "bottom" in pts:
                e["top_world"] = pts["top"]
                e["bottom_world"] = pts["bottom"]
                e["height"] = round(e["top_world"][1] - e["bottom_world"][1], 3)
                if e["height"] <= 0:
                    e["dummy_note"] = ("WARNUNG: up liegt nicht über down – Modell-glb veraltet oder "
                                       "Konvertierung fehlerhaft (convert_mission.py neu ausführen)")
                    print("  WARNUNG Leiter %s: up nicht über down (Höhe %.3f)" % (name, e["height"]))
            fwd = mat_dir(wm, [0, 0, -1])     # LS3D-Frame-Z (Matrix +0x60) -> glTF lokal -Z
            fwd[1] = 0.0
            ln = math.hypot(fwd[0], fwd[2]) or 1.0
            e["facing_dir_world_?"] = [round(fwd[0] / ln, 4), 0.0, round(fwd[2] / ln, 4)]
        if typ == 6 and wm is not None:
            ax = dec.get("axis_gltf")
            if ax:
                w = mat_dir(wm, ax)
                ln = math.sqrt(sum(c * c for c in w)) or 1.0
                e["axis_world"] = [round(c / ln, 5) for c in w]
        if typ == 13 and e.get("model"):
            e["state_frames"] = world.model_subframes(e["model"], "1") + world.model_subframes(e["model"], "2") + \
                world.model_subframes(e["model"], "3")
        if typ == 22 and e.get("model"):
            mf = world.model_subframes(e["model"], "explosive_")
            if mf:
                e["marker_frames"] = mf
        out[GROUPS.get(typ, "other")].append(e)
    for g in list(out):
        if isinstance(out[g], list):
            out["counts"][g] = len(out[g])
    out["unresolved"] = sorted(x for x in world.unresolved if x)
    return out


def survey():
    import collections
    names = fai.mission_names()
    cnt = collections.Counter()
    src = collections.Counter()
    for m in sorted(names):
        for f in ("scene2.bin", "actors.bin"):
            d = read_mission_file(m, f)
            if not d:
                continue
            for name, (typ, params) in fmt_scene2.parse_actor_defs(d).items():
                cnt[typ] += 1
                src[(typ, f)] += 1
    for t in sorted(cnt):
        print("%3d %-16s %5d   scene2.bin %4d   actors.bin %4d" % (
            t, CLASS_NAMES.get(t, "?"), cnt[t], src[(t, "scene2.bin")], src[(t, "actors.bin")]))


def main(argv):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 1
    if argv[0] == "--survey":
        survey()
        return 0
    mission = argv[0]
    dst = argv[1] if len(argv) > 1 else os.path.join(CACHE, mission.lower(), "interactive.json")
    out = build(mission)
    os.makedirs(os.path.dirname(os.path.abspath(dst)), exist_ok=True)
    with open(dst, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=1, ensure_ascii=False)
    print("%s -> %s" % (mission.upper(), dst))
    print("  " + ", ".join("%s %d" % (k, v) for k, v in out["counts"].items() if v))
    if out["unresolved"]:
        print("  unaufgeloest:", out["unresolved"][:20])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
