"""Original-Soldatenkader, Missions-Ausruestung und Inventarregeln (HD2 v1.12) lesen.

Quellen (nur gelesen, Patch zuerst):
  TABLES\\HumanStore.def      Soldatenprofile (Leser hd2.exe 0x6A18E0 -> 0x6A00A0, Eintrag 0x74 Byte, Ktor 0x6A1D80)
  GAMEDATA\\Gamedata00.gdt    Kampagnenablauf; Menueknoten 0x0014 {0x15 Typ, 0x16 u8, 0x17 u8, 0x18 16-Byte-Saetze}
                              (Schreiber 0x6BCE40, Verbrauch 0x6736D0 / 0x6B93C0)
  GAMEDATA\\miss_itm.def      Empfohlene Vorlagen + Pflicht-Gegenstaende je Missions-Ordinal (Leser 0x67E350)
  GAMEDATA\\presets.def       Ausruestungsvorlagen (440-Byte-Saetze, Lader 0x67D6xx)
  hd2.exe                     Konstanten (Rangschwellen 0x8423C0, Tabelle 0x841CB0, Trainingskonstanten)
  orig_cache/items.json       Gegenstaende (fmt_actors_items.py)

Ausgabe: orig_cache/roster.json, orig_cache/inventory_rules.json
Belege/Adressen: docs/re_notes_roster_inventory.md

Aufruf: pyenv\\Scripts\\python.exe -I fmt_roster.py
"""
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import convert_mission as cm  # noqa: E402

EXE = os.path.join(cm.ORIG, "hd2.exe")
STAT_NAMES = ["health", "strength", "endurance", "morale", "shooting", "unknown5", "stealth", "first_aid", "lockpick"]
# Soldatenpanel (0x4A46B6 / 0x83A9C0): Zeilen Shooting, Strenght, Health, Endurance, Stealth, First aid, Lockpick
PANEL_ORDER = [4, 1, 0, 2, 6, 7, 8]
RANKS = ["Private", "Corporal", "Sergeant", "Staff-Sergeant", "Warrant Officer", "Second-Lieutenant",
         "Lieutenant", "Captain", "Major"]
MEDALS = ["Distinguished Service Order", "Distinguished Conduct Medal", "Military Medal",
          "Africa General Service Medal", "General Service Medal 1918-1962", "War Medal", "Defence Medal",
          "Military Cross", "Victoria Cross", "Germany, France Star", "Africa Star", "Burma Star"]
CAMPAIGNS = ["Tutorial", "Arctic", "Africa", "Norway", "Burma", "Alps", "Normandy", "Czech"]


# --------------------------------------------------------------------------- Hilfen
def chunks(b):
    p = 0
    while p + 6 <= len(b):
        cid, sz = struct.unpack_from("<HI", b, p)
        if sz < 6 or p + sz > len(b):
            return
        yield cid, b[p + 6:p + sz]
        p += sz


def cstr(b):
    return b.split(b"\0")[0].decode("latin-1").strip()


def i32(b):
    return struct.unpack("<i", b)[0] if len(b) == 4 else None


class Exe:
    def __init__(self, path):
        import pefile
        self.d = open(path, "rb").read()
        pe = pefile.PE(path, fast_load=True)
        self.base = pe.OPTIONAL_HEADER.ImageBase
        self.secs = [(s.VirtualAddress, s.PointerToRawData, s.SizeOfRawData) for s in pe.sections]

    def off(self, va):
        for v, raw, sz in self.secs:
            if self.base + v <= va < self.base + v + sz:
                return va - self.base - v + raw
        raise ValueError(hex(va))

    def ints(self, va, n):
        return list(struct.unpack_from("<%di" % n, self.d, self.off(va)))

    def f32(self, va):
        return round(struct.unpack_from("<f", self.d, self.off(va))[0], 6)

    def f64(self, va):
        return struct.unpack_from("<d", self.d, self.off(va))[0]


# --------------------------------------------------------------------------- HumanStore.def
def parse_humanstore(data):
    """Wurzel 0x029A; je Soldat 0x2328 mit Unterchunks (Leser 0x6A00A0)."""
    out = []
    for cid, pay in chunks(data):
        if cid != 0x029A:
            continue
        for c2, p2 in chunks(pay):
            if c2 != 0x2328:
                continue
            s = {"index": len(out), "medals": []}
            for c3, p3 in chunks(p2):
                if c3 == 0x2396:
                    s["first_name"] = cstr(p3)
                elif c3 == 0x23A0:
                    s["last_name"] = cstr(p3)
                elif c3 == 0x23AA:
                    s["nickname"] = cstr(p3)
                elif c3 == 0x23F0:
                    s["portrait"] = cstr(p3)
                elif c3 == 0x26DE:
                    s["rank"] = i32(p3)            # Eintrag +0x24
                elif c3 == 0x26F3:
                    s["experience"] = i32(p3)      # +0x38
                elif c3 == 0x26F4:
                    s["counter_3c"] = i32(p3)      # +0x3C (je Mission +1, 0x68CB70)
                elif c3 == 0x26F5:
                    s["counter_40"] = i32(p3)      # +0x40 (je Mission +1)
                elif c3 == 0x26FC:
                    s["medals"].append(i32(p3))    # Vektor +0x28 (push_back 0x4205C0)
                elif c3 == 0x26AD:                 # roh 0x28 Byte nach +0x44
                    s["bio_text_id"] = struct.unpack_from("<i", p3, 0)[0]
                    vals = struct.unpack_from("<9f", p3, 4)
                    s["stats"] = {k: round(v, 3) for k, v in zip(STAT_NAMES, vals)}
                elif c3 == 0x26AC:                 # Altformat: 10 x i32 (int -> float)
                    v = struct.unpack_from("<10i", p3, 0)
                    s["bio_text_id"] = v[0]
                    s["stats"] = {k: float(x) for k, x in zip(STAT_NAMES, v[1:])}
                else:
                    s.setdefault("unknown_chunks", {})["%04x" % c3] = p3.hex()
            out.append(s)
    return out


# --------------------------------------------------------------------------- Gamedata00.gdt
def parse_menu(pay):
    m = {"records": []}
    for c, p in chunks(pay):
        if c == 0x15:
            m["type"] = i32(p)
        elif c == 0x16:
            m["flag_16"] = p[0] if p else 0
        elif c == 0x17:
            m["flag_17"] = p[0] if p else 0
        elif c == 0x18:
            item, count, unk = struct.unpack_from("<3i", p, 0)
            m["records"].append({"item": item, "count": count, "unk_8": unk, "ammo_of_weapon": p[12]})
    return m


def parse_gdt(data):
    """Linearer Ablauf je Kampagne: Video (0x0A), Menue (0x14), Mission (0x32 -> 0x05 {..., 0x1E Spiel})."""
    campaigns = []
    ordinal = 0

    def walk_list(pay, sink, mission):
        nonlocal ordinal
        for c, p in chunks(pay):
            if c == 0x000A:
                v = {}
                for c2, p2 in chunks(p):
                    if c2 == 0x0B:
                        v["video"] = cstr(p2)
                sink.append({"node": "video", **v})
            elif c == 0x0014:
                sink.append({"node": "menu", **parse_menu(p)})
            elif c == 0x001E:
                sink.append({"node": "play"})
            elif c == 0x0032:
                ms = {"node": "mission", "ordinal": ordinal, "flow": []}
                ordinal += 1
                for c2, p2 in chunks(p):
                    if c2 == 0x33:
                        ms["mission_id"] = i32(p2)
                    elif c2 == 0x36:
                        ms["folder"] = cstr(p2)
                    elif c2 == 0x05:
                        walk_list(p2, ms["flow"], ms)
                sink.append(ms)

    def find_campaigns(b):
        for c, p in chunks(b):
            if c == 0x003C:
                cp = {"index": len(campaigns), "flow": []}
                for c2, p2 in chunks(p):
                    if c2 == 0x3D:
                        cp["text_id"] = i32(p2)
                    elif c2 == 0x05:
                        walk_list(p2, cp["flow"], None)
                campaigns.append(cp)
            elif c in (0x0001, 0x0005):
                find_campaigns(p)
    find_campaigns(data)
    return campaigns


# --------------------------------------------------------------------------- miss_itm.def / presets.def
def parse_miss_itm(d):
    p = 0

    def u():
        nonlocal p
        v = struct.unpack_from("<i", d, p)[0]
        p += 4
        return v
    ver = u()
    hdr_count = u()
    hdr_n = 15 if ver == 1 else 50           # 0x3C bzw. 0xC8 Byte (0x67E39C)
    hdr = list(struct.unpack_from("<%di" % hdr_n, d, p))
    p += hdr_n * 4
    n = u()
    slots = {}
    for i in range(n):
        if not u():
            continue
        o0 = u()
        k = u()
        tri = [struct.unpack_from("<3i", d, p + 12 * j) for j in range(k)]
        p += 12 * k
        m = u()
        req = [struct.unpack_from("<2i", d, p + 8 * j) for j in range(m)]
        p += 8 * m
        slots[i] = {"field0": o0,
                    "recommended": [{"preset": a, "head_item": b, "uniform_item": c} for a, b, c in tri if a != -1],
                    "required_items": [{"item": a, "count": c} for a, c in req]}
    return {"version": ver, "header_count": hdr_count, "header": hdr, "slots": slots}


def parse_presets(d):
    ver, n = struct.unpack_from("<II", d, 0)
    out = []
    for i in range(n):
        r = d[8 + i * 440:8 + (i + 1) * 440]
        slots = struct.unpack_from("<5i", r, 32)
        na = struct.unpack_from("<i", r, 52)[0]
        nb = struct.unpack_from("<i", r, 168)[0]
        flags, tid, z = struct.unpack_from("<3i", r, 428)
        out.append({"index": i, "name": cstr(r[:32]),
                    "head": slots[0], "hands": slots[1], "shoulder": slots[2], "uniform": slots[3], "backpack": slots[4],
                    "pockets": [list(struct.unpack_from("<2i", r, 56 + 8 * k)) for k in range(na)],
                    "backpack_contents": [list(struct.unpack_from("<2i", r, 172 + 8 * k)) for k in range(nb)],
                    "flags": flags, "name_text_id": tid})
    return {"version": ver, "presets": out}


# --------------------------------------------------------------------------- Hauptteil
def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    texts = json.load(open(os.path.join(cm.CACHE, "texts_german.json"), encoding="utf-8"))
    items = {it["id"]: it for it in json.load(open(os.path.join(cm.CACHE, "items.json"), encoding="utf-8"))["items"]}
    exe = Exe(EXE)

    def iname(i):
        it = items.get(i)
        return it["name"] if it else None

    # --- Konstanten aus hd2.exe
    rank_thr = exe.ints(0x8423C0, 7)
    defence_tab = {}
    for c in range(8):
        v = exe.ints(0x841CB0 + c * 0x28, 10)
        lst = []
        for x in v:
            if x < 0:
                break
            lst.append(x)
        defence_tab[CAMPAIGNS[c]] = lst
    training = {
        "endurance": {"setter": "0x5A93A0", "per_mission_cap": exe.f32(0x80F9FC), "accum_field": "+0xC8",
                      "trigger": "0x5A88F0: Zeit in Sprint-Bewegung (+0x5C & 0x10000 und Zustand & 8) summiert in +0xE8; "
                                 "je >25000 -> +0.1 (Immediate 0x3DCCCCCD @0x5A8932)",
                      "gain": 0.1, "unit_threshold": 25000},
        "stealth": {"setter": "0x5A94F0", "per_mission_cap": exe.f32(0x80FC1C), "accum_field": "+0xD4",
                    "trigger": "0x5A88F0: Zeit in Schleich-Bewegung (+0x5C & 0x1000) in +0xE4; je >20000 -> +0.05; "
                               "Toetung (0x5A0BE0): Opfer-KI-Zustand 5 -> +0.03, Opfer hat Schuetzen nicht erfasst und "
                               "Alarmzeit > 60000 -> +0.02",
                    "gain_sneak": 0.05, "unit_threshold": 20000, "gain_kill_unaware": 0.03, "gain_kill_unnoticed": 0.02},
        "shooting": {"setter": "0x5A9480", "per_mission_cap": exe.f32(0x80FC1C), "accum_field": "+0xD0",
                     "trigger": "0x5A0BE0: Feind mit Schadensart 1 (Schuss) getoetet -> +0.04", "gain_kill": 0.04},
        "first_aid": {"setter": "0x5A9560", "per_mission_cap": exe.f32(0x80F9FC), "accum_field": "+0xD8",
                      "trigger": "0x546DC0 / 0x588AA0: Verbandskasten benutzt (Heilung) -> +0.1", "gain_use": 0.1},
        "lockpick": {"setter": "0x5A95D0", "per_mission_cap": exe.f32(0x80F9FC), "accum_field": "+0xDC",
                     "trigger": "0x584E30 Fall 0xE: Schloss geknackt -> +0.5", "gain_use": 0.5},
        "strength": {"setter": "0x5A9330 (ohne Aufrufer)", "per_mission_cap": exe.f32(0x80F518), "accum_field": "+0xC4",
                     "trigger": "kein Aufrufer; Startwert je Mission 0.5 (0x59C4D0) -> fester Zuwachs +0.5 pro Mission",
                     "fixed_per_mission": 0.5},
        "morale": {"setter": "0x5A9410 (ohne Aufrufer)", "per_mission_cap": exe.f32(0x80F524), "accum_field": "+0xCC",
                   "trigger": "kein Aufrufer; Startwert je Mission 1.0 (0x59C4D0) -> fester Zuwachs +1.0 pro Mission",
                   "fixed_per_mission": 1.0},
        "health": {"setter": "0x5A92F0 (ohne Aufrufer)", "per_mission_cap": exe.f32(0x80FA08), "accum_field": "+0xC0",
                   "trigger": "kein Aufrufer, Startwert 0 -> keine Aenderung"},
    }
    reserve = {"factor_min": exe.f64(0x815910), "factor_span": exe.f32(0x80FAD4),
               "rand_scale": exe.f32(0x80FF64)}

    # --- HumanStore
    hs = parse_humanstore(cm.read_file("tables/HumanStore.def", ["others.DTA"]))
    soldiers = []
    for s in hs:
        idx = s["index"]
        port = s.get("portrait", "")
        num = port[4:-4] if port.lower().startswith("x_f_") else None
        st = s.get("stats", {})
        e = {
            "store_index": idx,
            "first_name": s.get("first_name"), "last_name": s.get("last_name"), "nickname": s.get("nickname") or None,
            "selectable_sp": idx <= 29,
            "category": ("sas_campaign" if idx <= 29 else
                         "mp_slot" if s.get("first_name") == "MP" else "npc_profile"),
            "portrait": port, "portrait_id": num,
            "face_texture": ("e_f%s" % num) if num else None,
            "bio_text_id": s.get("bio_text_id"),
            "bio_de": texts.get(str(s.get("bio_text_id"))) if s.get("bio_text_id", -1) >= 0 else None,
            "rank": s.get("rank"),
            "rank_name": RANKS[s["rank"]] if s.get("rank") is not None and 0 <= s["rank"] < len(RANKS) else None,
            "rank_text_id": 10000 + 2 * s["rank"] if s.get("rank") is not None else None,
            "experience": s.get("experience"), "counter_3c": s.get("counter_3c"), "counter_40": s.get("counter_40"),
            "medals": s["medals"],
            "stats": st,
            "carry_limit_kg": int(st["strength"]) if "strength" in st else None,
            "panel": {n: st.get(STAT_NAMES[i]) for n, i in zip(
                ["Shooting", "Strenght", "Health", "Endurance", "Stealth", "First aid", "Lockpick"], PANEL_ORDER)},
            "defence_medal_campaign": [c for c, l in defence_tab.items() if idx in l] or None,
        }
        if "unknown_chunks" in s:
            e["unknown_chunks"] = s["unknown_chunks"]
        soldiers.append(e)

    roster = {
        "source": "TABLES\\HumanStore.def (patch.dta v1.12), Leser hd2.exe 0x6A00A0; Details docs/re_notes_roster_inventory.md",
        "stat_order": STAT_NAMES,
        "panel_order_indices": PANEL_ORDER,
        "notes": {
            "pool": "Einzelspieler-Auswahl nur Store-Index 0..29 (Schleifen 0x695450/0x694AE0/0x68C300: <30), "
                    "ohne Tote (+0x70) und ohne bereits gewaehlte",
            "team_size_max": 4,
            "solo_missions_ordinals": [2, 15],
            "voice": "Sprachsatz pro Teamplatz 1..4 (erster freier, 0x695AD0; sonst zufaellig 0x59EDC0), nicht pro Soldat",
            "face": "e_fNNN aus x_f_NNN abgeleitet (0x69FEF0); Gesichtstextur-Tausch 0x48A5C0 (Prefix 'e_f0')",
            "body_model": "nicht im Profil; Koerper kommt aus Uniform-Gegenstand (Slot uniform) [?]",
        },
        "ranks": [{"rank": i, "name": n, "text_id": 10000 + 2 * i, "abbr_text_id": 10001 + 2 * i,
                   "promote_when_total_xp_gt": rank_thr[i] if i < 7 else None} for i, n in enumerate(RANKS)],
        "medals": [{"id": i, "name": n, "text_id": 10100 + 2 * i, "desc_text_id": 10101 + 2 * i}
                   for i, n in enumerate(MEDALS)],
        "defence_medal_table_0x841CB0": defence_tab,
        "training": training,
        "reserve_gain": {"formula": "f = rand()/32767*%g + %g (U[0.6,1.4]) je Wert und Soldat; Zuwachs = f * "
                                    "Durchschnittszuwachs der lebenden Teammitglieder" % (reserve["factor_span"],
                                                                                         reserve["factor_min"]),
                         **reserve},
        "soldiers": soldiers,
    }

    # --- Gamedata00.gdt
    gdt = parse_gdt(cm.read_file("gamedata/Gamedata00.gdt", ["others.DTA"]))
    mitm = parse_miss_itm(cm.read_file("gamedata/miss_itm.def", ["others.DTA"]))
    presets = parse_presets(cm.read_file("gamedata/presets.def", ["others.DTA"]))
    pname = {p["index"]: p["name"] for p in presets["presets"]}

    def menu_out(m):
        recs = []
        for r in m["records"]:
            it = items.get(r["item"])
            rr = dict(r)
            rr["item_name"] = iname(r["item"])
            if r["ammo_of_weapon"]:
                rr["resolved_item"] = it.get("ammo_item") if it else None
                rr["resolved_name"] = iname(rr["resolved_item"])
            else:
                rr["resolved_item"] = r["item"]
                rr["resolved_name"] = rr["item_name"]
            recs.append(rr)
        t = m.get("type")
        meaning = {1: "team_refill", 2: "team_select", 3: "equipment_new_storage", 4: "equipment_keep_storage",
                   5: "debriefing"}.get(t)
        return {"type": t, "meaning": meaning, "flag_16": m.get("flag_16"), "flag_17": m.get("flag_17"),
                "storage_records": recs}

    missions = []
    camp_out = []
    for cp in gdt:
        cflow = []
        pending = []
        for n in cp["flow"]:
            if n["node"] == "menu":
                pending.append(menu_out(n))
                cflow.append({"menu": n.get("type")})
            elif n["node"] == "video":
                cflow.append({"video": n.get("video")})
            elif n["node"] == "mission":
                flow = []
                for f in n["flow"]:
                    if f["node"] == "menu":
                        flow.append({"menu": menu_out(f)})
                    elif f["node"] == "video":
                        flow.append({"video": f.get("video")})
                    elif f["node"] == "play":
                        flow.append({"play": True})
                pre = pending
                pending = []
                allm = pre + [x["menu"] for x in flow if "menu" in x]
                eq = [x for x in allm if x["type"] in (3, 4)]
                ordn = n["ordinal"]
                mi = mitm["slots"].get(ordn, {})
                missions.append({
                    "ordinal": ordn, "folder": n.get("folder"), "mission_id": n.get("mission_id"),
                    "campaign": CAMPAIGNS[cp["index"]] if cp["index"] < len(CAMPAIGNS) else cp["index"],
                    "before_mission_menus": pre,
                    "flow": flow,
                    "team_selection": "select" if any(x["type"] == 2 for x in allm) else
                                      "refill" if any(x["type"] == 1 for x in allm) else "keep",
                    "solo_mission": ordn in (2, 15),
                    "max_team": 1 if ordn in (2, 15) else 4,
                    "equipment_screen": (eq[0]["meaning"] if eq else None),
                    "storage_items_campaign": (eq[0]["storage_records"] if eq and eq[0]["type"] == 3 else []),
                    "list_only_single_mission": (eq[0]["storage_records"] if eq and eq[0]["type"] == 4 else []),
                    "recommended": [dict(r, preset_name=pname.get(r["preset"]), head_name=iname(r["head_item"]),
                                         uniform_name=iname(r["uniform_item"])) for r in mi.get("recommended", [])],
                    "mission_essentials": [dict(r, item_name=iname(r["item"])) for r in mi.get("required_items", [])],
                })
                cflow.append({"mission": n.get("folder")})
        camp_out.append({"index": cp["index"], "name": CAMPAIGNS[cp["index"]] if cp["index"] < len(CAMPAIGNS) else None,
                         "text_id": cp.get("text_id"), "flow": cflow})

    # --- Gegenstands-Raumbedarf/Gewicht
    def space(sc):
        return 1 if sc == 0 else 2 * sc
    backpacks = []
    for i, it in items.items():
        for b in it.get("behaviours", []):
            raw = b.get("raw_u32") or []
            if len(raw) >= 5 and raw[1] == 7:
                backpacks.append({"item": i, "name": it["name"], "weight_kg": it["weight_kg"],
                                  "max_weight_kg": struct.unpack("<f", struct.pack("<I", raw[3]))[0],
                                  "space_units": int(struct.unpack("<f", struct.pack("<I", raw[4]))[0])})
    item_rules = [{"item": i, "name": it["name"], "kind": it["kind"], "weight_kg": it["weight_kg"],
                   "size_class": it["size_class"], "space_units": space(it["size_class"])}
                  for i, it in sorted(items.items())]

    rules = {
        "source": "hd2.exe v1.12 (Adressen s. docs/re_notes_roster_inventory.md), Gamedata00.gdt, miss_itm.def, "
                  "presets.def, items.json",
        "team": {"max_size": 4, "solo_ordinals": [2, 15],
                 "selection_pool": "HumanStore 0..29, lebend, nicht im Team",
                 "auto_select_0x695450": "Platz1 beste Shooting, Platz2 beste First aid, Platz3 beste Shooting, "
                                         "Platz4 (Strength-0.1*Shooting)*10; je Top-5, Zufall daraus"},
        "slots": [
            {"mask": 1, "name": "head", "text_id": 2711, "member_field": "+0x4C", "items_dat_slot": 0},
            {"mask": 2, "name": "uniform", "text_id": 2714, "member_field": "+0x52", "items_dat_slot": 4},
            {"mask": 4, "name": "hands", "text_id": 2713, "member_field": "+0x64", "items_dat_slot": 3},
            {"mask": 8, "name": "back (backpack item)", "text_id": 2710, "member_field": "+0x58", "items_dat_slot": 5},
            {"mask": 16, "name": "shoulder", "text_id": 2715, "member_field": "+0x5E", "items_dat_slot": 2},
            {"mask": 32, "name": "pockets (holsters)", "text_id": 2716, "member_field": "+0x70 list", "items_dat_slot": 1,
             "capacity_space_units": exe.f32(0x863758)},
            {"mask": 64, "name": "backpack contents", "text_id": 2717, "member_field": "+0x80 list", "items_dat_slot": None,
             "capacity": "aus Rucksack-Gegenstand (max_weight_kg, space_units)"},
        ],
        "space_units_formula": "size_class == 0 ? 1 : 2*size_class (0x6A30C4, 0x6A2E14)",
        "carry_limit": "int(Strength) kg (Mitglied +0x8C = ftol(Store+0x4C), 0x6A23D8)",
        "placement_rules_0x6A3080": {
            "single_slot": "erlaubt wenn Gesamtgewicht + neu - ersetzt <= Tragegrenze",
            "backpack_item": "zusaetzlich neue Rucksack-Kapazitaet (Gewicht, Raum) >= aktueller Rucksackinhalt",
            "pockets": "stueckweise, solange Taschenraum + Raum <= 12 und Gesamtgewicht <= Tragegrenze",
            "backpack_contents": "stueckweise, solange Rucksackgewicht <= max_weight, Rucksackraum <= space_units, "
                                 "Gesamtgewicht <= Tragegrenze",
        },
        "overload_check_0x673D60": "Weiter blockiert, wenn ein Mitglied Gewicht/Tragegrenze > 1.0 (Text 2023)",
        "unarmed_check_0x6743F0": "Warnung (Text 9521), wenn ein aktives Mitglied keine Schusswaffe (Typ 1) in "
                                  "Haenden/Schulter/Taschen/Rucksack hat",
        "stamina_0x588710": {
            "load": "Last = Gewicht(+0x7C) / Strength",
            "range": "0 .. Endurance",
            "per_ms": "stamina += dt_ms * f * 0.001",
            "f_by_mode": {"mode0": "((1-Last)+E/E0)*1.5", "mode1": "((1-Last)+E/E0)*1.0", "mode2": "-1*Last",
                          "mode5": "-20*Last", "other_posture1": "((1-Last)+E/E0)*4", "other_posture2": "((1-Last)+E/E0)*6",
                          "other": "((1-Last)+E/E0)*2"},
            "sprint_drop": "Stamina 0 waehrend Sprint (0x10000) -> Laufen (0x4000)",
            "jump_cost": "10 (0x583C30, nur wenn Stamina > 10)",
        },
        "back_slot_items": backpacks,
        "presets_def": presets,
        "miss_itm_def": {"version": mitm["version"], "header": mitm["header"]},
        "storage_semantics": {
            "type3": "Lager [0x8AE914] wird geleert und mit den 0x18-Saetzen gefuellt (0x6736D0)",
            "type4": "Lager bleibt (keine Auffuellung im Kampagnenmodus); 0x18-Liste nur fuer Einzelmission "
                     "(0x6B93C0 sammelt alle Listen der Kampagne bis zur Mission)",
            "record": "u32 Gegenstand, u32 Anzahl, i32 (-1, unbenutzt), u8 Flag: 1 = Anzahl Magazine der Munition "
                      "der Waffe (Item-vfunc +0x18), 0 = Gegenstand selbst; 3 Fuellbytes",
        },
        "campaigns": camp_out,
        "missions": missions,
        "items": item_rules,
    }

    p1 = os.path.join(cm.CACHE, "roster.json")
    p2 = os.path.join(cm.CACHE, "inventory_rules.json")
    json.dump(roster, open(p1, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    json.dump(rules, open(p2, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    for s in soldiers[:30]:
        print("%2d %-14s %-12s %-7s rank %d  %s" % (s["store_index"], s["first_name"], s["last_name"],
                                                     s["nickname"] or "", s["rank"],
                                                     " ".join("%s=%g" % (k[:4], v) for k, v in s["stats"].items())))
    for m in missions:
        print("%2d %-10s team=%-6s eq=%-24s storage=%d essentials=%s" % (
            m["ordinal"], m["folder"], m["team_selection"], m["equipment_screen"],
            len(m["storage_items_campaign"]), [x["item_name"] for x in m["mission_essentials"]]))
    print("->", p1)
    print("->", p2)


if __name__ == "__main__":
    main()
