"""Original H&D2 (v1.12) player profiles: PlayersProfiles/<name>/{profile.sav, Options.bin, user_presets_orig.def}.

Formats reverse-engineered from hd2.exe (evidence + confidence: DangerousHidden2/docs/re_notes_profiles.md).

    python -I fmt_profile.py <PlayersProfiles dir> <out.json>

API: parse_profile(bytes) -> dict, parse_options(bytes) -> dict, parse_presets(bytes) -> dict,
     parse_profile_dir(path) -> dict, default_options() -> dict.

Chunk format (profile.sav, Options.bin): u16 id, u32 size (incl. 6-byte header), payload; containers nest.
"""
import json
import os
import struct
import sys

# ----------------------------------------------------------------------------------------------
# Tables
# ----------------------------------------------------------------------------------------------

# Mission ordinal -> mission. Ordinal = running index over all mission nodes (type 3, chunk 0x32)
# of the game tree in GAMEDATA\Gamedata00.gdt (campaign nodes = type 2, chunk 0x3C), tutorial
# included (hd2.exe 0x6B85D0 / 0x6B8660). "id" = gdt chunk 0x33 = text id of the mission title.
# Verified: ordinal 5 = id 25 "OP. NOMADE - SPAGHETTI FLUGHAFEN" matches LASTSAVETEXT of profile.
MISSIONS_ORIGINAL = [
    # (ordinal, mission folder, id/title text, campaign key, campaign text id)
    (0, "Tutorial", 45, "training", 209),
    (1, "Arctic1", 21, "arctic", 201),
    (2, "Arctic2", 22, "arctic", 201),
    (3, "Arctic3", 23, "arctic", 201),
    (4, "Arctic4", 24, "arctic", 201),
    (5, "Africa1", 25, "africa", 202),
    (6, "africa2", 26, "africa", 202),
    (7, "Africa3", 27, "africa", 202),
    (8, "Africa4", 28, "africa", 202),
    (9, "Africa5", 29, "africa", 202),
    (10, "Africa6", 30, "africa", 202),
    (11, "Norway", 31, "norway", 207),
    (12, "Burma1", 32, "burma", 203),
    (13, "Burma2", 33, "burma", 203),
    (14, "Alps1", 35, "alps", 205),
    (15, "Alps2", 36, "alps", 205),
    (16, "Normandy", 34, "normandy", 206),
    (17, "Normandy2", 44, "normandy", 206),
    (18, "Czech1", 38, "czech", 208),
    (19, "Czech2", 39, "czech", 208),
    (20, "Czech3", 40, "czech", 208),
    (21, "Czech4", 41, "czech", 208),
    (22, "Czech5", 42, "czech", 208),
    (23, "Czech6", 43, "czech", 208),
]

DIFFICULTY = {1: ("easy", 2157), 2: ("normal", 2158), 3: ("hard", 2159), 4: ("very_hard", 2160)}

# LASTSAVE slot order in chunk 0x1EF5 / 0x1EFA..0x1EFE (setter 0x6B3D00)
SAVE_SLOTS = [
    ("campaign", 2202, "CAM_"),
    ("lone_wolf", 2203, "LOW_"),
    ("carnage", 2204, "CAR_"),
    ("single_mission", 2205, "SMCAM_"),
    ("single_mission_carnage", 2206, "SMCAR_"),
]

# chunk 0x1EC8: one "seen" byte per video, stored in reverse order (index 9 first) (0x6A6B10/0x6A6D80)
VIDEOS = ["Intro.bik", "IntroArctic.bik", "IntroAfrica.bik", "IntroNorway.bik", "IntroBurma.bik",
          "IntroAlps.bik", "IntroNormandy.bik", "IntroCzech.avi", "Outro1.bik", "Outro2.bik"]

DETAIL_PRESETS = ["low", "medium", "high", "custom"]                      # texts 2414..2417
DETAIL_TOGGLES = ["shadows", "morphing", "footprints_decorations", "bloodstains", "grass",
                  "dynamics", "high_res_models"]                         # texts 2418..2424 (GD00..GD06)

BIND_CATEGORIES = {0: "movement", 1: "weapons", 2: "advanced", 3: "commands", 4: "tactical", -1: "hidden"}
BIND_CONTEXT = {1: "always", 2: "game", 3: "tactical_map"}
BIND_DEVICE = {1: "keyboard", 2: "mouse"}
MOUSE_CODES = {1: "button_left", 2: "button_right", 4: "button_middle",
               0x100: "axis_x", 0x200: "axis_y", 0x300: "wheel"}

# binding text id -> action key (labels: texts_german.json)
BIND_ACTIONS = {
    2801: "move_forward", 2802: "move_backward", 2803: "strafe_left", 2804: "strafe_right",
    2805: "speed_up", 2806: "speed_down", 2807: "lean_left", 2808: "lean_right", 2809: "jump",
    2810: "climb", 2811: "crouch", 2812: "prone",
    2821: "fire_primary", 2822: "fire_secondary", 2823: "throw_grenade", 2824: "reload",
    2825: "previous_weapon", 2826: "next_weapon", 2827: "drop_item",
    2841: "action", 2842: "action_menu", 2843: "game_info", 2844: "tactical_map",
    2845: "interface_mode", 2846: "map", 2847: "inventory", 2848: "pause", 2849: "binoculars",
    2850: "light", 2851: "camera", 2852: "console", 2853: "chat_all", 2854: "chat_team",
    2855: "handbrake", 2856: "show_players",
    2861: "next_soldier", 2862: "select_soldier_1", 2863: "select_soldier_2",
    2864: "select_soldier_3", 2865: "select_soldier_4", 2866: "command_all",
    2867: "command_1", 2868: "command_2", 2869: "command_3", 2870: "command_4",
    2871: "command_5", 2872: "command_6",
    7420: "tac_regroup", 7421: "tac_signal_1", 7422: "tac_signal_2", 7423: "tac_stand",
    7424: "tac_crouch", 7425: "tac_prone", 7426: "tac_sprint", 7427: "tac_run", 7428: "tac_walk",
    7429: "tac_slow", 7430: "tac_passive", 7431: "tac_defensive", 7432: "tac_aggressive",
    7433: "tac_delete", 7434: "tac_delete_all", 7435: "tac_options", 7436: "tac_camera_move",
    7437: "tac_cam_forward", 7438: "tac_cam_backward", 7439: "tac_cam_left", 7440: "tac_cam_right",
    7441: "tac_cam_up", 7442: "tac_cam_down", 7443: "tac_cam_rotate", 7444: "tac_cam_rotate_left",
    7445: "tac_cam_rotate_right", 7446: "tac_cam_pitch_up", 7447: "tac_cam_pitch_down",
    7448: "tac_zoom_in", 7449: "tac_zoom_out",
}

# DirectInput DIK_* scan codes
DIK = {
    0x01: "ESCAPE", 0x02: "1", 0x03: "2", 0x04: "3", 0x05: "4", 0x06: "5", 0x07: "6", 0x08: "7",
    0x09: "8", 0x0A: "9", 0x0B: "0", 0x0C: "MINUS", 0x0D: "EQUALS", 0x0E: "BACKSPACE", 0x0F: "TAB",
    0x10: "Q", 0x11: "W", 0x12: "E", 0x13: "R", 0x14: "T", 0x15: "Y", 0x16: "U", 0x17: "I",
    0x18: "O", 0x19: "P", 0x1A: "LBRACKET", 0x1B: "RBRACKET", 0x1C: "RETURN", 0x1D: "LCONTROL",
    0x1E: "A", 0x1F: "S", 0x20: "D", 0x21: "F", 0x22: "G", 0x23: "H", 0x24: "J", 0x25: "K",
    0x26: "L", 0x27: "SEMICOLON", 0x28: "APOSTROPHE", 0x29: "GRAVE", 0x2A: "LSHIFT",
    0x2B: "BACKSLASH", 0x2C: "Z", 0x2D: "X", 0x2E: "C", 0x2F: "V", 0x30: "B", 0x31: "N", 0x32: "M",
    0x33: "COMMA", 0x34: "PERIOD", 0x35: "SLASH", 0x36: "RSHIFT", 0x37: "NUMPADSTAR",
    0x38: "LALT", 0x39: "SPACE", 0x3A: "CAPSLOCK", 0x3B: "F1", 0x3C: "F2", 0x3D: "F3", 0x3E: "F4",
    0x3F: "F5", 0x40: "F6", 0x41: "F7", 0x42: "F8", 0x43: "F9", 0x44: "F10", 0x45: "NUMLOCK",
    0x46: "SCROLL", 0x47: "NUMPAD7", 0x48: "NUMPAD8", 0x49: "NUMPAD9", 0x4A: "NUMPADMINUS",
    0x4B: "NUMPAD4", 0x4C: "NUMPAD5", 0x4D: "NUMPAD6", 0x4E: "NUMPADPLUS", 0x4F: "NUMPAD1",
    0x50: "NUMPAD2", 0x51: "NUMPAD3", 0x52: "NUMPAD0", 0x53: "NUMPADPERIOD", 0x56: "OEM_102",
    0x57: "F11", 0x58: "F12", 0x9C: "NUMPADENTER", 0x9D: "RCONTROL", 0xB5: "NUMPADSLASH",
    0xB7: "SYSRQ", 0xB8: "RALT", 0xC5: "PAUSE", 0xC7: "HOME", 0xC8: "UP", 0xC9: "PGUP",
    0xCB: "LEFT", 0xCD: "RIGHT", 0xCF: "END", 0xD0: "DOWN", 0xD1: "PGDN", 0xD2: "INSERT",
    0xD3: "DELETE", 0xDB: "LWIN", 0xDC: "RWIN", 0xDD: "APPS",
}

# ----------------------------------------------------------------------------------------------
# Chunk helpers
# ----------------------------------------------------------------------------------------------


def iter_chunks(b, off=0, end=None):
    """yield (id, payload_off, payload_end) for consecutive chunks in b[off:end]."""
    end = len(b) if end is None else end
    p = off
    while p + 6 <= end:
        cid, size = struct.unpack_from("<HI", b, p)
        if size < 6 or p + size > end:
            raise ValueError("bad chunk 0x%04X at %d (size %d)" % (cid, p, size))
        yield cid, p + 6, p + size
        p += size


def _cstr(b):
    return b.split(b"\0", 1)[0].decode("cp1252", errors="replace")


def _i32(b, o=0):
    return struct.unpack_from("<i", b, o)[0]


def mission_by_ordinal(ordinal):
    if ordinal is None or ordinal < 0:
        return None
    for o, folder, mid, camp, ctext in MISSIONS_ORIGINAL:
        if o == ordinal:
            return {"ordinal": o, "folder": folder, "title_text_id": mid, "campaign": camp,
                    "campaign_text_id": ctext}
    return {"ordinal": ordinal, "folder": None}


# ----------------------------------------------------------------------------------------------
# profile.sav
# ----------------------------------------------------------------------------------------------


def parse_profile(data):
    """Decode profile.sav (root chunk 0x1EDC). Writer hd2.exe 0x6B09A0, reader 0x6AFB00."""
    out = {
        "name": None,
        "difficulty": None,
        "progress": {},
        "last_save": {"file": "", "text": "", "parts": None},
        "mode_saves": [],
        "videos_seen": {},
        "unknown_chunks": [],
    }
    root = list(iter_chunks(data))
    if not root or root[0][0] != 0x1EDC:
        raise ValueError("not a profile.sav (root chunk 0x1EDC missing)")
    _, ro, re_ = root[0]
    slot_ints = [-1] * 5
    slot_files = [""] * 5
    legacy_ee8 = 0
    progress = [None, None]
    for cid, o, e in iter_chunks(data, ro, re_):
        pl = data[o:e]
        if cid == 0x1EDD:
            out["name"] = _cstr(pl)
        elif cid == 0x1EFF:
            out["difficulty"] = _i32(pl)
        elif cid in (0x1F05, 0x1F06):
            progress[cid - 0x1F05] = struct.unpack_from("<4i", pl)
        elif cid == 0x1EE6:  # legacy: difficulty + record 0
            out["difficulty"] = _i32(pl)
            progress[0] = struct.unpack_from("<4i", pl, 4)
        elif cid == 0x1EEA:
            out["last_save"]["file"] = _cstr(pl)
        elif cid == 0x1EEB:
            out["last_save"]["text"] = _cstr(pl)
        elif cid == 0x1EE8:  # legacy: 1st = LASTSAVE, 2nd = LASTSAVETEXT
            out["last_save"]["file" if legacy_ee8 == 0 else "text"] = _cstr(pl)
            legacy_ee8 += 1
        elif cid == 0x1EF5:
            n = min(5, len(pl) // 4)
            slot_ints[:n] = struct.unpack_from("<%di" % n, pl)
        elif 0x1EFA <= cid <= 0x1EFE:
            slot_files[cid - 0x1EFA] = _cstr(pl)
        elif cid == 0x1EF0:
            for sid, so, se in iter_chunks(data, o, e):
                if sid == 0x1EC8:
                    flags = data[so:se]
                    for k, byte in enumerate(flags[:len(VIDEOS)]):
                        out["videos_seen"][VIDEOS[len(VIDEOS) - 1 - k]] = bool(byte)
                else:
                    out["unknown_chunks"].append({"id": "0x%04X" % sid, "parent": "0x1EF0",
                                                  "hex": data[so:se].hex()})
        else:
            out["unknown_chunks"].append({"id": "0x%04X" % cid, "hex": pl.hex()})

    d = out["difficulty"]
    out["difficulty"] = {"value": d, "key": DIFFICULTY.get(d, (None, None))[0],
                         "text_id": DIFFICULTY.get(d, (None, None))[1]}
    for gi, gname in enumerate(("original", "sabre_squadron")):
        rec = progress[gi]
        if rec is None:
            continue
        mx, cam, low, car = rec
        g = {"max_ordinal": mx, "campaign": cam, "lone_wolf": low, "carnage": car}
        if gi == 0:
            g["campaign_mission"] = mission_by_ordinal(cam)
            g["max_mission"] = mission_by_ordinal(mx)
            g["lone_wolf_mission"] = mission_by_ordinal(low)
            g["carnage_mission"] = mission_by_ordinal(car)
        out["progress"][gname] = g
    for k, (mode, text_id, prefix) in enumerate(SAVE_SLOTS):
        out["mode_saves"].append({
            "mode": mode, "mode_text_id": text_id, "mission_ordinal": slot_ints[k],
            "mission": mission_by_ordinal(slot_ints[k]), "file": slot_files[k]})
    t = out["last_save"]["text"]
    if t.count("$") >= 2:
        mode_txt, mission_txt, date_txt = t.split("$", 2)
        out["last_save"]["parts"] = {"mode": mode_txt, "mission": mission_txt, "date": date_txt}
    return out


# ----------------------------------------------------------------------------------------------
# Options.bin
# ----------------------------------------------------------------------------------------------

OPTIONS_VERSION = 0x141   # chunk 0x25A0, checked by reader 0x6B2D80 (else defaults)
BINDINGS_VERSION = 0x42   # chunk 0x22B8, checked by 0x6A8900


def _decode_settings(pl):
    """60-byte settings struct (profile +0x38), chunk 0x1201 inside 0x25A5 (writer 0x6B3530)."""
    f = struct.unpack_from("<5f", pl, 0)
    preset = _i32(pl, 0x18)
    sets = {}
    for k, name in enumerate(DETAIL_PRESETS):
        raw = pl[0x1C + 7 * k:0x1C + 7 * k + 7]
        sets[name] = {DETAIL_TOGGLES[i]: bool(raw[i]) for i in range(7)}
    active = DETAIL_PRESETS[preset] if 0 <= preset < 4 else None
    return {
        "mouse_sensitivity": round(f[0], 4),         # 0..100, engine value int(1000 - 9*v)
        "gamma": round(f[1], 4),                     # 0..100, 50 = neutral ramp
        "sound_volume": round(f[2], 4),              # 0..100 (x0.01)
        "music_volume": round(f[3], 4),              # 0..100 (x0.01)
        "voice_chat_volume": round(f[4], 4),         # 0..100 (x0.01)
        "unused_0x14": "0x%08X" % struct.unpack_from("<I", pl, 0x14)[0],
        "detail_preset": {"index": preset, "key": active,
                          "text_id": 2414 + preset if 0 <= preset < 4 else None},
        "detail_toggles": sets.get(active) if active else None,
        "detail_preset_tables": sets,
        "voice_chat_enabled": bool(pl[0x38]),
        "invert_mouse": bool(pl[0x39]),
        "subtitles": bool(pl[0x3A]),
        "allow_crosshair": bool(pl[0x3B]),           # v1.12 text 20212 (element 'parental lock')
    }


def _decode_binding(rec, idx):
    action, dev, code, direction, ctx, cat, text_id, active = struct.unpack_from("<IHHiiiiB", rec)
    if dev == 1:
        key = DIK.get(code, "DIK_0x%02X" % code)
    elif dev == 2:
        key = MOUSE_CODES.get(code, "MOUSE_0x%X" % code)
        if code >= 0x100:
            key += {1: "+", 2: "-"}.get(direction, "")
    else:
        key = "DEV%d_0x%X" % (dev, code)
    return {
        "index": idx, "action_id": action,
        "action": BIND_ACTIONS.get(text_id, "hidden_%d" % action if text_id == -1 else "text_%d" % text_id),
        "text_id": text_id, "category": BIND_CATEGORIES.get(cat, cat),
        "context": BIND_CONTEXT.get(ctx, ctx), "device": BIND_DEVICE.get(dev, dev),
        "code": code, "direction": direction, "key": key, "runtime_active_flag": active,
    }


def parse_options(data, texts=None):
    out = {"version": None, "version_ok": False, "bindings_version": None, "bindings": [],
           "settings": None, "unknown_chunks": []}
    for cid, o, e in iter_chunks(data):
        pl = data[o:e]
        if cid == 0x25A0:
            out["version"] = _i32(pl)
            out["version_ok"] = out["version"] == OPTIONS_VERSION
        elif cid == 0x25A6:
            for sid, so, se in iter_chunks(data, o, e):
                if sid == 0x22B8:
                    out["bindings_version"] = _i32(data, so)
                elif sid == 0x22B9:
                    raw = data[so:se]
                    for k in range(len(raw) // 28):
                        b = _decode_binding(raw[28 * k:28 * k + 28], k)
                        if texts and str(b["text_id"]) in texts:
                            b["label_de"] = texts[str(b["text_id"])]
                        out["bindings"].append(b)
                else:
                    out["unknown_chunks"].append({"id": "0x%04X" % sid, "hex": data[so:se].hex()})
        elif cid == 0x25A5:
            for sid, so, se in iter_chunks(data, o, e):
                if sid == 0x1201 and se - so >= 60:
                    out["settings"] = _decode_settings(data[so:se])
                else:
                    out["unknown_chunks"].append({"id": "0x%04X" % sid, "hex": data[so:se].hex()})
        else:
            out["unknown_chunks"].append({"id": "0x%04X" % cid, "hex": pl.hex()})
    return out


def default_options():
    """Defaults written by hd2.exe 0x6B3420 when Options.bin is missing/invalid (bindings: layout 1)."""
    pl = bytearray(60)
    struct.pack_into("<5f", pl, 0, 66.6, 50.0, 50.0, 50.0, 50.0)
    struct.pack_into("<I", pl, 0x14, 0xCCCCCCCC)
    struct.pack_into("<i", pl, 0x18, 2)
    pl[0x1C:0x23] = bytes([0, 0, 0, 0, 0, 0, 0])
    pl[0x23:0x2A] = bytes([0, 1, 0, 1, 0, 1, 0])
    pl[0x2A:0x31] = bytes([1, 1, 1, 1, 1, 1, 1])
    pl[0x31:0x38] = bytes([0, 1, 0, 1, 0, 1, 1])
    pl[0x38:0x3C] = bytes([0, 0, 1, 1])
    s = _decode_settings(bytes(pl))
    return {"version": None, "defaults": True, "bindings": "default layout 1 (STANDARD-EINSTELLUNGEN 1, "
            "arrow keys; built in code at 0x6A8C00, not decoded here)", "settings": s}


# ----------------------------------------------------------------------------------------------
# user_presets_orig.def
# ----------------------------------------------------------------------------------------------

PRESET_SIZE = 0x1B8  # 440 bytes, read raw (0x67D6xx)


def parse_presets(data, item_names=None):
    ver, n = struct.unpack_from("<II", data, 0)
    out = {"version": ver, "count": n, "presets": []}
    for k in range(n):
        r = data[8 + k * PRESET_SIZE:8 + (k + 1) * PRESET_SIZE]
        if len(r) < PRESET_SIZE:
            break
        v = struct.unpack_from("<102i", r, 32)

        def items(cnt_idx, max_pairs):
            cnt = v[cnt_idx]
            res = []
            if 0 <= cnt <= max_pairs:
                for i in range(cnt):
                    it, num = v[cnt_idx + 1 + 2 * i], v[cnt_idx + 2 + 2 * i]
                    e = {"item": it, "count": num}
                    if item_names and it in item_names:
                        e["name"] = item_names[it]
                    res.append(e)
            return res

        slots = list(v[0:5])
        p = {"index": k, "name": _cstr(r[:32]), "slots": slots,
             "slot_names": [item_names.get(s) if item_names else None for s in slots],
             "list_a": items(5, 14), "list_b": items(34, 32),
             "flags": v[99], "name_text_id": v[100], "reserved": v[101]}
        out["presets"].append(p)
    return out


# ----------------------------------------------------------------------------------------------
# savegame (identification only)
# ----------------------------------------------------------------------------------------------


def identify_save(data):
    if len(data) < 16:
        return None
    magic, ver = struct.unpack_from("<IH", data, 0)
    info = {"magic": "0x%08X" % magic, "header_u16": ver, "size": len(data)}
    cid, size = struct.unpack_from("<HI", data, 6)
    if cid == 0x0BB6 and size == 10:
        info["mission_ordinal"] = _i32(data, 12)
        info["mission"] = mission_by_ordinal(info["mission_ordinal"])
    return info


# ----------------------------------------------------------------------------------------------
# directory / CLI
# ----------------------------------------------------------------------------------------------


def _load_json(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return None


def parse_profile_dir(path, texts=None, item_names=None):
    res = {"folder": os.path.basename(os.path.normpath(path)), "files": sorted(os.listdir(path))}
    p = os.path.join(path, "profile.sav")
    if os.path.isfile(p):
        res["profile"] = parse_profile(open(p, "rb").read())
    p = os.path.join(path, "Options.bin")
    res["options"] = parse_options(open(p, "rb").read(), texts) if os.path.isfile(p) else default_options()
    p = os.path.join(path, "user_presets_orig.def")
    if os.path.isfile(p):
        res["user_presets"] = parse_presets(open(p, "rb").read(), item_names)
    saves = {}
    for f in res["files"]:
        if f.lower().endswith(".sav") and f.lower() != "profile.sav":
            sp = os.path.join(path, f)
            with open(sp, "rb") as fh:
                info = identify_save(fh.read(64))
            if info:
                info["size"] = os.path.getsize(sp)
            saves[f] = info
    res["savegames"] = saves
    if texts and "profile" in res:
        pr = res["profile"]
        if pr["difficulty"]["text_id"]:
            pr["difficulty"]["label_de"] = texts.get(str(pr["difficulty"]["text_id"]))
        for m in [pr["progress"].get("original", {}).get(k) for k in
                  ("campaign_mission", "max_mission", "lone_wolf_mission", "carnage_mission")] + \
                [s["mission"] for s in pr["mode_saves"]]:
            if m and m.get("title_text_id"):
                m["title_de"] = texts.get(str(m["title_text_id"]))
                m["campaign_de"] = texts.get(str(m["campaign_text_id"]))
    return res


def main(argv):
    if len(argv) != 3:
        print(__doc__)
        return 2
    root, out_path = argv[1], argv[2]
    here = os.path.dirname(os.path.abspath(__file__))
    cache = os.environ.get("DH2_CACHE") or os.path.join(here, "..", "DangerousHidden2", "orig_cache")
    texts = _load_json(os.path.join(cache, "texts_german.json"))
    items_j = _load_json(os.path.join(cache, "items.json"))
    item_names = {i["id"]: i["name"] for i in items_j["items"]} if items_j else None
    profiles = []
    for name in sorted(os.listdir(root)):
        d = os.path.join(root, name)
        if os.path.isdir(d):
            profiles.append(parse_profile_dir(d, texts, item_names))
    doc = {"source": os.path.abspath(root), "format_notes": "DangerousHidden2/docs/re_notes_profiles.md",
           "profiles": profiles}
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, ensure_ascii=False, indent=1)
    for p in profiles:
        pr = p.get("profile", {})
        print("%-10s name=%r difficulty=%s progress=%s bindings=%s" % (
            p["folder"], pr.get("name"), pr.get("difficulty", {}).get("key"),
            pr.get("progress", {}).get("original", {}).get("campaign"),
            len(p["options"]["bindings"]) if isinstance(p["options"].get("bindings"), list) else "default"))
    print("->", out_path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
