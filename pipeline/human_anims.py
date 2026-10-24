"""Ganzkörper-Animationen der Menschen aus TABLES\\anim.sav (Zuordnung) und den 5DS-Dateien (Länge, Ereignisse,
natürliche Laufgeschwindigkeit). Genutzt von export_characters.py.

Belege (DangerousHidden2/docs/re_notes_weapons.md §12):
  anim.sav Menschentabelle ab Datei 0x10 (Mann; ab 0x55F0 dieselbe Tabelle für Frauen „_chuzezena“…),
  Einträge zu 0x1C Byte, der Name beginnt 1 Byte nach dem Eintragsanfang [B Daten].
  Bewegung je Richtung 18 Einträge = 3 Haltungen (stehen/hocken/liegen) × 6 Gangarten
  (0 langsam, 1 normal, 2 schnell, 3 verwundet, 4 Wache, 5 Sprint) [B Daten, P Deutung über Namen/Längen];
  Richtungen vor, zurück, links, rechts, vorn-links, vorn-rechts, hinten-links, hinten-rechts;
  ohne Waffe ab 0x367F, mit Waffe („ZB“ = zbraň) ab 0x463F [B Daten].
  Lehnen 0x352F (vykouk/kackuk/leh_vykl, mit Waffe 0x35D7), Haltungswechsel 0x088E–0x0B12, Tode 0x2616–0x31E6,
  Treffer 0x1A4AF (je Zone 3 Einträge stehen/hocken/liegen), Gefangener 0x1ABE6, Leiter 0x22CE/0x2322,
  Schwimmen 0x1D8E–0x1EC2, Türen 0x0022, Aufheben 0x1EDE (uch = uchopit), Messer: Haltesatz „hand“ +0xF40/+0xFA0.
"""
import math
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import convert_mission as cm  # noqa: E402
import fmt_5ds  # noqa: E402
import skinned_gltf  # noqa: E402

FPS = skinned_gltf.FPS
DIRS = ["fwd", "back", "left", "right", "fl", "fr", "bl", "br"]
MODES = ["slow", "normal", "fast", "limp", "guard", "sprint"]
MOVE_ARMED = 0x463F
MOVE_UNARMED = 0x367F
REC = 0x1C


def read_anim_sav():
    return cm.read_file("tables/anim.sav", ["others.DTA"])


def _name(d, o):
    return d[o + 1:o + 21].split(b"\0")[0].decode("latin1")


def move_table(d, start=MOVE_ARMED):
    """{stance(0..2): {dir: [6 5DS-Namen je Gangart]}}"""
    out = {}
    for di, dn in enumerate(DIRS):
        base = start + di * 18 * REC
        for st in range(3):
            out.setdefault(st, {})[dn] = [_name(d, base + (st * 6 + m) * REC) for m in range(6)]
    return out


# Übrige Ganzkörperclips (Schlüssel -> 5DS); Zuordnung über Tabellenlage und tschechische Namen [P]
FULL = {
    # Ruhe mit Waffe je Haltung (0x11BF, 0x147B, 0x1593)
    "idle_zb": "!staticZB", "crouch_zb": "!drepZB1", "prone_zb": "!lehZB",
    # Haltungswechsel stehen<->hocken<->liegen (0x088E…0x0B12)
    "st_dr": "!st-dr3", "dr_st": "!dr-st3", "dr_le": "!dr-leR", "le_dr": "!le-drR", "st_le": "!st-leR", "le_st": "!le-st3",
    # Lehnen (vykouknutí) links/rechts je Haltung, mit Waffe (0x35D7…)
    "lean_l0": "!vykouk_LZB", "lean_l1": "#kackukLzb", "lean_l2": "!leh_vyklL1b",
    "lean_r0": "!vykouk_PZB", "lean_r1": "#kackukRzb", "lean_r2": "!leh_vyklR1b",
    # Drehen auf der Stelle (mit Waffe)
    "turn_l": "!otocL1zb", "turn_r": "!otocP1zb",
    # Springen, Landen (doskok), Fall (pád), Klettern über Hindernis (překážka), Aufsteigen (nakročit)
    "jump_up": "!jump", "land": "!doskSTb", "land_crouch": "!doskKLa", "fall": "!vPAD01",
    "step_up": "!nakroc4a", "obstacle_low": "!stPREKca", "obstacle_mid": "!vPREKha", "obstacle_high": "!vys_prek2a",
    # Leiter (lézt nahoru/dolů, žebřík)
    "ladder_up": "#LEZUP2da", "ladder_down": "#LEZDWN1da", "ladder_on_top": "!slezZEBda", "ladder_off_top": "!zZEBda",
    # Schwimmen / Wassertreten / Tauchen
    "swim": "!plavani3", "swim_idle": "!plavST", "dive": "!potapec", "dive_move": "!potapecM",
    # Türen, Benutzen, Aufheben, Manipulieren (Schalter/Sprengstoff kniend), Schloss
    "door_st": "!dvereST02", "door_kl": "!dvereKL03", "pickup_st": "(uchprestoj4", "pickup_dr": "(uchpredrep",
    "manip_kl": "!manipulm", "manip_st": "!manipul1",
    # Gefangener gefesselt / wird gefesselt / fesselt
    "tied": "!svazanej", "being_tied": "!svazovanej", "tying": "!svazuje1",
    # Verwundet am Boden (Skriptclips %zranenej …)
    "wounded_lie": "%zranenej",
    # Messer von hinten (podřezat), stehend
    "knife_back_st": "!podrezSTa",
    # Tode: stehend nach hinten (B = zurück), vorn (#death), links/rechts, zusammensacken (M), Explosion (BAZ)
    "death_b1": "!smrtB1a", "death_b2": "!smrtB2a", "death_b3": "!smrtB3b", "death_b4": "!smrtB4a",
    "death_f1": "#death13", "death_f2": "#death121", "death_f3": "#death3", "death_f4": "#death5", "death_f5": "#death6",
    "death_l": "!smrtL1c", "death_r": "!smrtP2a", "death_m": "!smrtM2b",
    "death_exp0": "!dthBAZs", "death_exp1": "!dthBAZd", "death_exp2": "!dthBAZl",
    "death_c1": "#-death1", "death_c2": "#-death2", "death_c3": "#-death3", "death_c4": "#-death4",
    "death_kb1": "#dthkB1", "death_kb3": "#dthkB3", "death_kl": "#dthkL5", "death_kr": "#dthkR1",
    "death_p1": "#deathleh1", "death_p2": "#deathleh2", "death_p4": "#deathleh4", "death_p5": "#deathleh5",
    "death_p6": "#deathleh6", "death_throat": "!smrtpodrez", "death_tied": "!svazSMRT",
    # Treffer je Zone: stehen ")z", hocken ")z-", liegen ")z_" (Tabelle 0x1A4AF)
    "hit_head0": ")zhlava4", "hit_head1": ")z-hlava3", "hit_head2": ")z_hlava2",
    "hit_shl0": ")zramenoL", "hit_shl1": ")z-ramenoL2", "hit_shl2": ")z_rukaL",
    "hit_shr0": ")zramenoP", "hit_shr1": ")z-ramenoP", "hit_shr2": ")z_rukaP",
    "hit_legl0": ")znohaL1", "hit_legl1": ")z-nohaL", "hit_legl2": ")z_nohaL",
    "hit_legr0": ")znohaP1", "hit_legr1": ")z-nohaP1", "hit_legr2": ")z_nohaP1",
    "hit_belly0": ")zbricho1", "hit_belly1": ")z-hlava2", "hit_belly2": ")z_bolL1",
    "hit_back0": ")zzada", "hit_back1": ")z-zada", "hit_back2": ")z_bolP2",
}
# Oberkörperclips für die Haltungsschicht (Präfix h_ -> ohne Becken/Beine; export_characters.channel_filter)
UPPER = {
    # Messerstich stehend/hockend (Haltesatz „hand“ +0xF40/+0xF60), von hinten hockend (+0xFC0)
    "knife_st": "(bodnuti", "knife_dr": "(bodnuti drep", "knife_back_kl": "(podrezKL02",
    # Ergeben / Hände hoch je Haltung (zajatec = Gefangener, 0x1ABE6)
    "surrender0": "!zajatecST", "surrender1": "!zajatecDR", "surrender2": "!zajatecLE",
}
# anim.sav schreibt „(bodnutidrep“, die Datei heißt „(bodnuti drep“ [B Daten]
ALIASES = {"(bodnutidrep": "(bodnuti drep"}

LIMB_POINTS = ["u", "v", "q", "r", "t", "p", "i", "m", "j", "n"]


def clip_key(a5):
    return "m_" + "".join(c for c in a5 if c.isalnum())


def upper_key(a5):
    return "h_" + "".join(c for c in a5 if c.isalnum())


def read5(name):
    name = ALIASES.get(name, name)
    return cm.read_file("models/%s.5ds" % name, ["patch.dta", "MODELS.DTA"])


def _interp(frames, vals, f, quat=False):
    if not frames:
        return None
    if f <= frames[0]:
        return vals[0]
    for i in range(1, len(frames)):
        if f <= frames[i]:
            t = (f - frames[i - 1]) / max(frames[i] - frames[i - 1], 1e-6)
            a, b = vals[i - 1], vals[i]
            if quat and sum(x * y for x, y in zip(a, b)) < 0:
                b = [-x for x in b]
            v = [a[k] + (b[k] - a[k]) * t for k in range(len(a))]
            if quat:
                n = math.sqrt(sum(x * x for x in v)) or 1.0
                v = [x / n for x in v]
            return v
    return vals[-1]


def _fk_points(model, anim, names):
    """Weltlage (glTF-Raum, Figur blickt nach -Z) der Frames names für jedes Bild."""
    frames = model["frames"]
    byname = {f["name"].lower(): f for f in frames if f["name"]}
    tracks = {o["name"].lower(): o for o in anim["objects"]}
    chains = {}
    for n in names:
        chain = []
        f = byname.get(n)
        while f is not None:
            chain.append(f)
            f = frames[f["parent"] - 1] if f["parent"] else None
        chains[n] = chain
    out = []
    for k in range(anim["last_frame"] + 1):
        pts = {}
        for n, chain in chains.items():
            m = [[1.0 if i == j else 0.0 for j in range(4)] for i in range(4)]
            for fr in reversed(chain):
                o = tracks.get(fr["name"].lower())
                pos = cm.cpos(fr["pos"])
                rot = skinned_gltf.qconv(fr["rot"])
                if o is not None:
                    p = _interp(o.get("pos_frames"), o.get("pos"), k)
                    if p is not None:
                        pos = cm.cpos(p)
                    q = _interp(o.get("rot_frames"), o.get("rot"), k, quat=True)
                    if q is not None:
                        rot = skinned_gltf.qconv(q)
                m = skinned_gltf.mat_mul(m, skinned_gltf.mat_trs(pos, rot, fr["scale"]))
            pts[n] = (m[0][3], m[1][3], m[2][3])
        out.append(pts)
    return out


def natural_velocity(model, anim):
    """Natürliche Fortbewegung einer Ort-Schleife (m/s, lokal x/z; -z = vorwärts): je Bildpaar bewegt sich der
    jeweils tiefste Gliedpunkt (Standfuß, beim Kriechen Knie/Ellbogen) relativ zur Figur rückwärts; Mittel über
    die Schleife [E]."""
    pts = _fk_points(model, anim, LIMB_POINTS)
    if len(pts) < 3:
        return 0.0, 0.0
    # aufgesetzt = höchstens 2,5 cm über der tiefsten Lage dieses Punktes in der Schleife (Füße; beim Kriechen
    # liegen die Füße kaum auf -> alle Gliedpunkte)
    feet = ["u", "v", "q", "r"]
    lowest = min(p[n][1] for p in pts for n in LIMB_POINTS)
    cands = feet if min(p[n][1] for p in pts for n in feet) < lowest + 0.05 else LIMB_POINTS
    vx = vz = 0.0
    n = 0
    for nm in cands:
        ymin = min(p[nm][1] for p in pts)
        if ymin > lowest + 0.12:
            continue                         # Punkt berührt den Boden nie
        for k in range(len(pts) - 1):
            a, b = pts[k][nm], pts[k + 1][nm]
            if a[1] <= ymin + 0.025 and b[1] <= ymin + 0.025:
                vx -= (b[0] - a[0]) * FPS
                vz -= (b[2] - a[2]) * FPS
                n += 1
    if n == 0:
        return 0.0, 0.0
    return round(vx / n, 3), round(vz / n, 3)


def events(anim):
    for o in anim["objects"]:
        if o["name"].lower() == "a" and o.get("events"):
            return [[round(f / FPS, 3), e] for f, e in zip(o.get("event_frames", []), o["events"])]
    return []


def build(model):
    """-> (anims {Clipname: 5DS}, table für human_anims.json)."""
    d = read_anim_sav()
    mt = move_table(d)
    anims, info = {}, {}
    move = {}
    for st, dirs in mt.items():
        for dn, lst in dirs.items():
            keys = []
            for a5 in lst:
                k = clip_key(a5)
                anims[k] = ALIASES.get(a5, a5)
                keys.append(k)
            move.setdefault(str(st), {})[dn] = keys
    full = {}
    for k, a5 in FULL.items():
        ck = clip_key(a5)
        anims[ck] = ALIASES.get(a5, a5)
        full[k] = ck
    upper = {}
    for k, a5 in UPPER.items():
        ck = upper_key(a5)
        anims[ck] = ALIASES.get(a5, a5)
        upper[k] = ck
    loco = {c for dirs in move.values() for lst in dirs.values() for c in lst}
    missing = []
    for ck, a5 in list(anims.items()):
        b = read5(a5)
        if b is None:
            missing.append(a5)
            del anims[ck]
            continue
        a = fmt_5ds.parse(b)
        e = {"length": round(a["last_frame"] / FPS, 3)}
        ev = events(a)
        if ev:
            e["events"] = ev
        if ck in loco:
            vx, vz = natural_velocity(model, a)
            e["vel"] = [vx, vz]
            e["speed"] = round(math.hypot(vx, vz), 3)
        info[ck] = e
    return anims, {"move": move, "full": full, "upper": upper, "clips": info, "modes": MODES, "dirs": DIRS,
                   "missing": missing}
