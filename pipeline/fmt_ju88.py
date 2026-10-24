"""Ju-88-Flug der Mission AFRICA6 („Raubvögel“) -> orig_cache/africa6/ju88.json

Liest die Originaldaten (nur lesend) und schreibt alles, was der Nachbau für den
Junkers88-Akteur (Typ 34) und die angreifenden Bf 109 braucht:
  * Flugbahn der Ju 88: MODELS\\#aircraftA1..A6.5DS (Objekt "airdummy"), so wie sie
    hd2.exe abspielt (0x5EFDD0: Pfadfolger "#aircraftdum" + "#aircraftA%d", 0x5F62A0
    schaltet nach Ablauf auf das nächste Segment, 0x5F6100 setzt die Welt-Matrix des
    Akteur-Frames = Welt-Matrix von "airdummy").
  * Flugbahnen der 9 möglichen Jäger: MODELS\\#airfight_0N_A1..A6.5DS (Objekt "stihac")
    inkl. Ereignissen fire_start/fire_end (Callback 0x5F54C0).
  * Akteursparameter (actors.bin 0xAE24, Leser 0x5F29F0), Sitze/MG-Stände aus
    MODELS\\la_Ju88High.4ds (SEATxx, BARRELxx_00), Waffenwerte aus orig_cache/items.json.
  * Zielpunkte AF5_obj/AF5_switchcam aus scene.json und daraus berechnete Zeitpunkte.

Koordinaten wie scene.json (glTF/Godot): Position (x, y, -z), Quaternion (x, y, -z, w)
(5DS-Konvention wie 4DS, siehe skinned_gltf.qconv / docs/re_notes_5ds_skin.md).
Zeitbasis: 25 Bilder/s (Abgleich: #JunkersFlyA 930 Bilder <-> Skriptwechsel nach 37,2 s).

Belege und Konfidenz: DangerousHidden2/docs/re_notes_ju88.md

Aufruf: python -I tools/fmt_ju88.py [Ausgabedatei]
"""
import json
import math
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dta_extract  # noqa: E402
import fmt_4ds  # noqa: E402
import fmt_5ds  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ORIG = os.environ.get("DH2_ORIG") or os.path.join(ROOT, "HD2_orig")
CACHE = os.environ.get("DH2_CACHE") or os.path.join(ROOT, "DangerousHidden2", "orig_cache")
MDIR = os.path.join(CACHE, "africa6")
FPS = 25.0
ROUND_POS = 3
ROUND_ROT = 5

_arcs = {}


def read_model_file(name):
    """Datei aus patch.dta (zuerst) oder MODELS.DTA lesen."""
    key = ("MODELS\\" + name).lower()
    for a in ("patch.dta", "MODELS.DTA"):
        if a not in _arcs:
            arc = dta_extract.Archive(os.path.join(ORIG, a))
            arc.index = {e[0].lower(): e for e in arc.entries}
            _arcs[a] = arc
        arc = _arcs[a]
        if key in arc.index:
            return arc.read(arc.index[key]), a
    raise FileNotFoundError(name)


# --- Koordinaten (wie convert_mission.cpos / skinned_gltf.qconv) ---------------

def cpos(p):
    return [p[0], p[1], -p[2]]


def crot(q):
    return [q[0], q[1], -q[2], q[3]]


def qmul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return [aw * bx + ax * bw + ay * bz - az * by,
            aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw,
            aw * bw - ax * bx - ay * by - az * bz]


def qrot(q, v):
    x, y, z, w = q
    vx, vy, vz = v
    # v' = q v q*
    tx = 2 * (y * vz - z * vy)
    ty = 2 * (z * vx - x * vz)
    tz = 2 * (x * vy - y * vx)
    return [vx + w * tx + (y * tz - z * ty), vy + w * ty + (z * tx - x * tz), vz + w * tz + (x * ty - y * tx)]


def qinv(q):
    return [-q[0], -q[1], -q[2], q[3]]


def rnd(v, n):
    return [round(x, n) for x in v]


# --- 5DS-Pfade ----------------------------------------------------------------

def load_segment(fname, obj_name):
    data, src = read_model_file(fname)
    a = fmt_5ds.parse(data)
    o = [x for x in a["objects"] if x["name"].lower() == obj_name.lower()][0]
    seg = {
        "file": "MODELS\\" + fname,
        "source": src,
        "last_frame": a["last_frame"],
        "key_end": max(o["pos_frames"][-1], o["rot_frames"][-1]),
        "pos": [[f] + rnd(cpos(p), ROUND_POS) for f, p in zip(o["pos_frames"], o["pos"])],
        "rot": [[f] + rnd(crot(q), ROUND_ROT) for f, q in zip(o["rot_frames"], o["rot"])],
    }
    if o.get("events"):
        seg["events"] = [[f, e] for f, e in zip(o["event_frames"], o["events"])]
    return seg


def sample(seg, frame):
    """Lineare Interpolation (Position) / nlerp (Rotation) - nur für Auswertungen."""
    def lerp_keys(keys, f, n):
        if f <= keys[0][0]:
            return keys[0][1:]
        for i in range(1, len(keys)):
            if keys[i][0] >= f:
                a, b = keys[i - 1], keys[i]
                t = (f - a[0]) / max(1e-9, b[0] - a[0])
                if n == 4 and sum(x * y for x, y in zip(a[1:], b[1:])) < 0:
                    b = [b[0]] + [-x for x in b[1:]]
                v = [x + (y - x) * t for x, y in zip(a[1:], b[1:])]
                if n == 4:
                    l = math.sqrt(sum(x * x for x in v)) or 1.0
                    v = [x / l for x in v]
                return v
        return keys[-1][1:]
    return lerp_keys(seg["pos"], frame, 3), lerp_keys(seg["rot"], frame, 4)


def build_path(prefix, obj_name, count, length_mode):
    segs = []
    t0 = 0.0
    for i in range(1, count + 1):
        s = load_segment("%s%d.5DS" % (prefix, i), obj_name)
        frames = s["last_frame"] if length_mode == "last_frame" else s["key_end"]
        s["start_s"] = round(t0, 3)
        s["duration_s"] = round(frames / FPS, 3)
        t0 += frames / FPS
        segs.append(s)
    return segs, round(t0, 3)


def sample_at(segs, t):
    """Position/Rotation zur Zeit t (s) entlang der Segmentfolge."""
    for s in segs:
        if t <= s["start_s"] + s["duration_s"] or s is segs[-1]:
            return sample(s, min((t - s["start_s"]) * FPS, s["duration_s"] * FPS))
    return sample(segs[-1], segs[-1]["duration_s"] * FPS)


def path_length(segs):
    d = 0.0
    for s in segs:
        p = s["pos"]
        d += sum(math.dist(p[k][1:], p[k + 1][1:]) for k in range(len(p) - 1))
    return d


def iter_samples(segs, step_frames=1):
    """(t_s, pos, rot) entlang der Segmentfolge (Segmentlänge = duration_s)."""
    for s in segs:
        n = int(round(s["duration_s"] * FPS))
        for f in range(0, n + 1, step_frames):
            p, q = sample(s, f)
            yield s["start_s"] + f / FPS, p, q


# --- Ju-88-Modell: Sitze, MG-Stände --------------------------------------------

def parse_params(s):
    out = {}
    for part in (s or "").split(","):
        part = part.strip()
        if not part:
            continue
        k = part.rstrip("0123456789-")
        v = part[len(k):]
        out[k] = int(v) if v.lstrip("-").isdigit() else v
    return out


def anim_pose(fname):
    """Erste Keys je Objekt einer 5DS (glTF): {Name: (pos|None, rot|None)}."""
    data, _ = read_model_file(fname)
    a = fmt_5ds.parse(data)
    out = {}
    for o in a["objects"]:
        out[o["name"]] = (cpos(o["pos"][0]) if o.get("pos") else None,
                          crot(o["rot"][0]) if o.get("rot") else None)
    return out


def model_frames(fname, pose=None):
    """Frames eines 4DS mit Welt-(Modell-)Transformation in glTF; pose überschreibt lokale
    Transformationen einzelner Frames (wie eine laufende Animation)."""
    data, _ = read_model_file(fname)
    m = fmt_4ds.read_model(data, quiet=True)
    fr = m["frames"]
    world = {}
    pose = pose or {}

    def w(i):
        if i in world:
            return world[i]
        f = fr[i]
        lp, lq = cpos(f["pos"]), crot(f["rot"])
        if f["name"] in pose:
            pp_, pq_ = pose[f["name"]]
            lp = pp_ if pp_ is not None else lp
            lq = pq_ if pq_ is not None else lq
        if f["parent"]:
            pp, pq = w(f["parent"] - 1)
            p = [a + b for a, b in zip(pp, qrot(pq, lp))]
            q = qmul(pq, lq)
        else:
            p, q = lp, lq
        world[i] = (p, q)
        return world[i]

    def path(i):
        f = fr[i]
        s = f["name"]
        while f["parent"]:
            f = fr[f["parent"] - 1]
            s = f["name"] + "/" + s
        return s

    return fr, w, path


def seat_info(texts, weapons):
    # Laufzeit-Pose: Init (0x5EF6D0 -> 0x5F70D0(0)) spielt #adamage0 auf dem Akteur; dessen Spur
    # "BODY" (-90 Grad Gier) hebt die +90 Grad von BODY01 auf -> Bug zeigt entlang Akteur +Z.
    fr, w, path = model_frames("la_Ju88High.4ds", anim_pose("#adamage0.5DS"))
    by_parent = {}
    for f in fr:
        by_parent.setdefault(f["parent"] - 1, []).append(f["index"])

    def descendants(i):
        out = []
        for c in by_parent.get(i, []):
            out.append(c)
            out += descendants(c)
        return out

    seats = []
    for f in fr:
        if not f["name"].upper().startswith("SEAT") or f["type"] != 6:
            continue
        prm = parse_params(f["params"])
        bits = [int(c) for c in str(prm.get("SEAT", ""))]
        p, q = w(f["index"])
        seat = {
            "index": int(f["name"][4:]),
            "frame": f["name"],
            "node_path": path(f["index"]),
            "params_raw": f["params"],
            "seat_flags_digits": bits,
            "seat_mask": sum(1 << b for b in bits),
            "has_turret": 8 in bits,
            "name_text": prm.get("name"),
            "name": texts.get(str(prm.get("name")), None),
            "pos_actor": rnd(p, 4),
            "rot_actor": rnd(q, 5),
        }
        for d in descendants(f["index"]):
            g = fr[d]
            gp, gq = w(d)
            nm = g["name"].upper()
            if nm.startswith("BARREL"):
                bp = parse_params(g["params"])
                wid = bp.get("itemid")
                seat["turret"] = {
                    "barrel_frame": g["name"],
                    "node_path": path(d),
                    "params_raw": g["params"],
                    "weapon_item": wid,
                    "weapon": weapons.get(wid),
                    "limit_up_deg": bp.get("up"), "limit_down_deg": bp.get("down"),
                    "limit_left_deg": bp.get("left"), "limit_right_deg": bp.get("right"),
                    "speed_h": bp.get("hs"), "speed_v": bp.get("vs"),
                    "barrel_pos_actor": rnd(gp, 4),
                    "barrel_rot_actor": rnd(gq, 5),
                    "fire_anim": "MODELS\\la_Ju88High_f%02d_00.5DS" % seat["index"],
                }
            elif nm.startswith("CAMERAFPV"):
                seat["camera_fpv"] = {"frame": g["name"], "pos_actor": rnd(gp, 4), "rot_actor": rnd(gq, 5)}
            elif nm.startswith("CAMERA3RD"):
                seat.setdefault("camera_3rd", []).append({"frame": g["name"], "pos_actor": rnd(gp, 4)})
            elif nm.startswith(("HORT", "VERT")):
                seat.setdefault("pivots", []).append({"frame": g["name"], "node_path": path(d),
                                                      "pos_actor": rnd(gp, 4), "rot_actor": rnd(gq, 5)})
        seats.append(seat)
    seats.sort(key=lambda s: s["index"])
    damage_parts = sorted({f["name"] for f in fr if f["name"].endswith("d") and
                           f["name"].rstrip("d").rstrip("0123456789").rstrip("_")
                           in ("engine_l", "engine_r", "left_wing", "right_wing", "flap_l", "flap_r",
                               "listy_l", "listy_r", "elevator_left", "elevator_right", "flap_r01a", "flap_r00a")})
    return seats, damage_parts


# --- Akteursparameter ------------------------------------------------------------

def actor_params(inter):
    a = inter["ju88"][0]
    raw = bytes.fromhex(a["raw"])
    ch = {}
    p = 0
    while p + 6 <= len(raw):
        cid, ln = struct.unpack_from("<HI", raw, p)
        ch[cid] = raw[p + 6:p + ln]
        p += ln
    f = lambda cid: struct.unpack("<f", ch[cid])[0] if cid in ch else None  # noqa: E731
    i = lambda cid: struct.unpack("<i", ch[cid])[0] if cid in ch else None  # noqa: E731
    return a, {
        "c100_health": {"field": "+0x31C", "value": f(100), "default": 1000.0,
                        "meaning": "Lebenspunkte der Ju 88 (Startwert +0x280)"},
        "c200_fighter_health": {"field": "+0x320", "value": f(200), "default": 10.0,
                                "meaning": "Lebenspunkte je Bf 109 (x Schwierigkeitsfaktor)"},
        "c300_attack_damage": {"field": "+0x324", "value": f(300), "default": 30.0,
                               "meaning": "Schadensrate je feuerndem Jäger (pro s, x SetupJunkers88 a/100)"},
        "c400_unknown_angle": {"field": "+0x328", "value": f(400), "default": 1.0471976,
                               "meaning": "? (Wert 1,396 = 80 Grad, Standard 60 Grad); Verwendung nicht gefunden"},
        "c500_label_text": {"field": "+0x32C", "value": i(500), "default": 7166,
                            "meaning": "? vermutlich Text-ID (Standard 7166 'Junkers 88'); Datei: -1"},
    }


def main():
    out_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(MDIR, "ju88.json")
    texts = json.load(open(os.path.join(CACHE, "texts_german.json"), encoding="utf-8"))
    items = json.load(open(os.path.join(CACHE, "items.json"), encoding="utf-8"))
    weapons = {w["id"]: w for w in items.get("weapons", [])}
    inter = json.load(open(os.path.join(MDIR, "interactive.json"), encoding="utf-8"))
    scene = json.load(open(os.path.join(MDIR, "scene.json"), encoding="utf-8"))
    objs = {o["name"]: o for o in scene["objects"]}

    actor, params = actor_params(inter)
    ju_segs, ju_total = build_path("#aircraftA", "airdummy", 6, "last_frame")
    seats, damage_parts = seat_info(texts, weapons)

    # Vorwärtsachse des Modells: Bewegungsrichtung im lokalen System (glTF)
    fwd = [0.0, 0.0, 0.0]
    s = ju_segs[1]
    for k in range(10, len(s["pos"]) - 10, 25):
        p0, p1 = s["pos"][k][1:], s["pos"][k + 1][1:]
        q = sample(s, s["pos"][k][0])[1]
        v = qrot(qinv(q), [b - a for a, b in zip(p0, p1)])
        fwd = [a + b for a, b in zip(fwd, v)]
    l = math.sqrt(sum(x * x for x in fwd)) or 1.0
    fwd = rnd([x / l for x in fwd], 3)

    # Ziel-/Kamera-Auslöser entlang der Bahn
    marks = {}
    for nm, lim in (("AF5_obj", 500.0), ("AF5_switchcam", 200.0)):
        o = objs[nm]
        best = (1e18, None)
        first = None
        for t, p, _ in iter_samples(ju_segs):
            d = math.dist(p, o["pos"])
            if d < best[0]:
                best = (d, t)
            if first is None and int(d) < lim:
                first = t
        marks[nm] = {"pos": o["pos"], "threshold_m": lim, "first_time_s": None if first is None else round(first, 2),
                     "closest_m": round(best[0], 1), "closest_time_s": round(best[1], 2)}

    # Jäger-Bahnen
    fighters = []
    for n in range(1, 10):
        segs_k, tot_k = build_path("#airfight_0%d_A" % n, "stihac", 6, "key_end")
        anomalies = [{"segment": "A%d" % (i + 1), "last_frame": sg["last_frame"], "key_end": sg["key_end"]}
                     for i, sg in enumerate(segs_k) if sg["last_frame"] != sg["key_end"]]
        # Feuerphasen (Annahme: Segmentlänge = key_end, d. h. synchron zur Ju 88)
        fire = []
        open_t = None
        for sg in segs_k:
            for f, e in sg.get("events", []):
                t = sg["start_s"] + f / FPS
                late = f > sg["key_end"]
                if e == "fire_start":
                    open_t = (t, late)
                elif e == "fire_end" and open_t is not None:
                    fire.append({"start_s": round(open_t[0], 2), "end_s": round(t, 2),
                                 "beyond_keys": bool(open_t[1] or late)})
                    open_t = None
        if open_t is not None:
            fire.append({"start_s": round(open_t[0], 2), "end_s": None, "beyond_keys": open_t[1]})
        for fw in fire:
            if not fw["beyond_keys"]:
                pf = sample_at(segs_k, fw["start_s"])[0]
                pj = sample_at(ju_segs, fw["start_s"])[0]
                fw["dist_to_ju88_at_start_m"] = round(math.dist(pf, pj), 1)
        # Abstand zur Ju 88 (synchron) als Plausibilitätsprüfung
        dmin, dmax = 1e9, 0.0
        for (t, p, _), (t2, pj, _) in zip(iter_samples(segs_k, 25), iter_samples(ju_segs, 25)):
            d = math.dist(p, pj)
            dmin, dmax = min(dmin, d), max(dmax, d)
        fighters.append({
            "id": n,
            "path_prefix": "MODELS\\#airfight_0%d_A" % n,
            "frame_name_runtime": "interceptor_%d" % n,
            "segments": segs_k,
            "length_m": round(path_length(segs_k), 1),
            "segment_length_anomalies": anomalies,
            "fire_windows": fire,
            "fire_total_s": round(sum(w["end_s"] - w["start_s"] for w in fire
                                      if not w["beyond_keys"] and w["end_s"] is not None), 2),
            "distance_to_ju88_sync_m": {"min": round(dmin, 1), "max": round(dmax, 1)},
        })

    out = {
        "mission": "AFRICA6",
        "generator": "tools/fmt_ju88.py",
        "notes": "docs/re_notes_ju88.md",
        "coords": "glTF/Godot wie scene.json: pos (x,y,-z), rot (x,y,-z,w); Zeit = Bild/25",
        "fps": FPS,
        "actor": {
            "name": actor["name"], "type": 34, "class": "Junkers88", "model": actor["model"],
            "scene_parent": actor["parent"], "scene_local": actor["local"], "scene_world": actor["world"],
            "script": actor.get("script"),
            "inventory": {"item": 216, "name": "AMMO MG 42", "count": len(actor.get("inventory", []))},
            "params": params,
            "path_forward_axis_gltf": fwd,
            "runtime_pose": {
                "anim": "MODELS\\#adamage0.5DS (Slot 1, beim Init 0x5EF6D0 -> 0x5F70D0(0))",
                "BODY_local_rot_gltf": rnd(crot([0.0, -0.70711, 0.0, 0.70711]), 5),
                "note": "la_ju88high.glb hat in Ruhelage den Bug entlang Modell +X (BODY01 +90 Grad Gier). "
                        "#adamage0 setzt BODY auf -90 Grad Gier -> Bug entlang Akteur +Z = Flugrichtung. "
                        "Sitz-/Laufpositionen unten (pos_actor) gelten mit dieser Pose. Gleiches für die Bf 109.",
            },
        },
        "path": {
            "runtime": "Pfadfolger 0x5F5F20: lädt #aircraftdum (Frame airdummy) und spielt #aircraftA1..6 "
                       "nacheinander (0x5F62A0); Akteur-Welt-Matrix = Welt-Matrix airdummy (0x5F6100). "
                       "Fortschritt nur, solange der Akteur-Frame eingeschaltet ist (Tick 0x5F7710).",
            "object": "airdummy",
            "segments": ju_segs,
            "duration_s": ju_total,
            "length_m": round(path_length(ju_segs), 1),
            "avg_speed_mps": round(path_length(ju_segs) / ju_total, 2),
            "unused_variant": "MODELS\\#aircraft1..6.5DS (Skript af5_airanim.scr, keinem Objekt zugeordnet; "
                              "Segmente 2-6 identisch bis auf y+62,8 m)",
        },
        "objective": {
            "script_function": "_FrameInRange(frame) = ganzzahliger Abstand (m) zwischen Welt-Position von frame "
                               "und dem Frame des ausführenden Skripts (0x41E3F0 Fall 0xF); toter Mensch -> 1000",
            "triggers": marks,
        },
        "setup_junkers88": {
            "handler": "Opcode 0x102 -> 0x4176E7 -> 0x5EDDC0: +0x284 = a*0.01, +0x288 = b*0.01",
            "a_meaning": "Multiplikator Schaden an der Ju 88 (Script: 40 + 20*Schwierigkeit)",
            "b_meaning": "Divisor für Treffer auf Jäger: Schaden/(b*0.01) (Script: 100 -> 1,0)",
            "ju88_damage_per_s": "a*0.01 * c300 * Anzahl gerade feuernder Jäger",
        },
        "set_actor_state": {
            "handler": "0x5F0A90(n): nur wenn noch keine Jäger existieren; n verschiedene Zufalls-IDs aus 1..9",
            "fighter_health": "c200 * Faktor (Schwierigkeit [0x8AE924]+0xC: 0 -> 0.7, 1 -> 0.85, sonst 1.0)",
            "script_values": {"value_letadla==1": 5, "value_letadla==2": 6, "value_letadla==0": 7},
        },
        "damage_model": {
            "health_start": params["c100_health"]["value"],
            "stage_formula": "stage = trunc(5 - health/(c100*0.2)); bei Wechsel und stage<=4 -> Animation "
                             "#adamage<stage> (MODELS\\#adamage1..4.5DS), stage 4 -> beide Motoren brennen",
            "parts_first_below": 0.75, "parts_second_below": 0.25,
            "damage_part_frames": damage_parts,
            "on_zero": "Funkspruch Gruppe 4, zufällige Absturzanimation #jushotdwn1..8, alle Jäger beenden Feuer, "
                       "Missionsende (0x423C70)",
            "copy_protection_note": "nach 120 s Missionszeit wird Schadensrate auf 1000 gesetzt, falls eine "
                                    "Prüfsumme (0x8CA730/0x8CAE30) nicht stimmt - im Nachbau ignorieren",
        },
        "fighters": {
            "model": "la_Bf109Canyon",
            "dummy_model": "#airfightdum (Frame stihac)",
            "health_base": params["c200_fighter_health"]["value"],
            "difficulty_factor": [0.7, 0.85, 1.0],
            "visibility_fade": {"from_ms": 9000, "to_ms": 11000,
                                "note": "Missionszeit (0x698500()+0x2C); vorher unsichtbar"},
            "anims": {"slot1": "#adamage0", "slot2": "#bfcanygrup", "shot_down": "#bfshotdwn1..3 (zufällig)"},
            "weapon_frames": ["weapon_r00", "weapon_l00", "weapons_r01", "weapon_l01"],
            "fire": {"tracer_interval_ms": 200, "tracer_speed_mps": 500, "tracer_max_range_m": 500,
                     "tracer_scale": [5, 5, 25], "tracers_damage": False,
                     "impact_fx_on_ju88_ms": [[200, 299], [250, 374]]},
            "on_fire_start": "Ju88 +0x28C += c300; Funkspruch Gruppe 0",
            "on_fire_end": "Ju88 +0x28C -= c300 (min 0)",
            "shot_down": "Rauch an left_wing/right_wing (Partikel 16), #bfshotdwn, Bodenkontakt -> Explosion "
                         "(Partikel 0x67/0x68), dann entfernt; Funkspruch Gruppe 3",
            "paths": fighters,
        },
        "seats": seats,
        "seats_note": "Sitz-MG-Stände: Bit 8 in SEATxx (Ziffer '8') -> Geschützobjekt 0x4C19D0 je Sitz (0x5F81B0), "
                      "Grenzen/Geschwindigkeiten aus BARREL-Parametern (up/down/left/right Grad, hs/vs). "
                      "Laufmündung = lokale -Z-Achse (glTF) des BARREL-Frames [P: Sitz 0/3 vorn 180 Grad gedreht, "
                      "Sitz 1/2/4 nach hinten]. Schwenk über HORTxx (Gier) / VERTxx (Nick) [P, Namen].",
        "board_vehicle_script": {"Board01": 1, "Board02": 2, "Board03": 3, "Board04": 0,
                                 "note": "HUMAN_BoardVehicle(\"ju88\", 1, Sitz): Sitze 0..3 besetzt, Sitz 4 frei"},
        "radio": {
            "groups": {
                "0_attack": [90005527, 90005528, 90005529, 90005530, 90005531, 90005532, 90005533, 90005534],
                "1_ju88_hit": [90005535, 90005536, 90005512, 90005513, 90005514, 90005517],
                "2_fighter_hit": [90005538, 90005539, 90005540, 90005544, 90005545, 90005518, 90005519,
                                  90005520, 90005521, 90005522],
                "3_fighter_down": [90005541, 90005542, 90005543, 90005523, 90005524, 90005525, 90005526],
                "4_ju88_down": [90005537, 90005515, 90005516],
                "5_clock_callout": list(range(90005500, 90005512)),
            },
            "interval_ms": {"0": [2000, 4000], "1": [2000, 4000], "2": [2000, 4000], "3": [300, 600],
                            "4": None, "5": [3000, 9500]},
            "clock_rule": "Gruppe 5: zufälliger Jäger in 20..60 m, Uhrzeit aus Winkel zur Ju-88-Längsachse",
            "files": "SOUNDS\\<ID>.wav",
        },
        "sounds": {"engine": ["ju88mtr1.wav", "ju88mtr2.wav"], "engine_damaged": ["DMGMTR01.wav", "DMGMTR02.wav"],
                   "engine_explode": ["expmtr01.wav", "expmtr02.wav"], "fighter_engine": "motor1..4.wav",
                   "fighter_guns": "kul_d1..5.wav", "whizz": "whizz%d.wav"},
    }
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(out, fh, ensure_ascii=False, separators=(",", ":"))
    print("geschrieben:", out_path, "(%d KB)" % (os.path.getsize(out_path) // 1024))
    print("Ju88: %d Segmente, %.1f s, %.0f m, %.1f m/s, Vorwärtsachse %s" % (
        len(ju_segs), ju_total, path_length(ju_segs), path_length(ju_segs) / ju_total, fwd))
    for k, v in marks.items():
        print("  %s: erstmals < %d m bei t=%s s, nächster Punkt %.1f m bei %.1f s" % (
            k, v["threshold_m"], v["first_time_s"], v["closest_m"], v["closest_time_s"]))
    for f in fighters:
        print("  Jäger %d: %.0f m, Feuerphasen %d (davon jenseits Keys %d), Abstand Ju88 %s, Anomalien %s" % (
            f["id"], f["length_m"], len(f["fire_windows"]), sum(1 for w in f["fire_windows"] if w["beyond_keys"]),
            f["distance_to_ju88_sync_m"], [a["segment"] for a in f["segment_length_anomalies"]]))
        print("     Feuer gesamt %.2f s; (s, Abstand m):" % f["fire_total_s"], [(w["start_s"], w["end_s"], w.get("dist_to_ju88_at_start_m"))
                                            for w in f["fire_windows"]])
    for s in seats:
        t = s.get("turret", {})
        print("  Sitz %d %-12s mask %#x MG %s (%s) hoch %s runter %s links %s rechts %s" % (
            s["index"], s["name"], s["seat_mask"], t.get("weapon_item"),
            (t.get("weapon") or {}).get("name"), t.get("limit_up_deg"), t.get("limit_down_deg"),
            t.get("limit_left_deg"), t.get("limit_right_deg")))


if __name__ == "__main__":
    main()
