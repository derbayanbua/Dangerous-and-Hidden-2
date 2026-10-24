"""Lichter, Kameras, Kameraspuren und Umgebungsklänge einer LS3D/HD2-Mission.

Quellen (alle aus missions\\<M>\\ in Missions.dta):
  scene2.bin  Objekttyp 2 = Licht (Chunk 0x4040), Typ 3 = Kamera (0x4036), Kopf-Chunks 0x3010/0x3011/0x3200/0x3211
  sounds.bin  Objekttyp 4 = Klangquelle (Chunk 0x4060), gleicher Objektrahmen wie scene2.bin
  tracks.dat  Kamera-/Objektspuren (FRM_WatchTrack): 0x2426 > 0x2454 Spur > 0x24B8 Schlüssel
Musik: TABLES\\IngameSounds.def (others.DTA), Kategorie 12 = Musik; PlayMusic(n)/PlayCutsceneMusic(n)
indizieren diese Liste. Formate, Belege und Konfidenz: DangerousHidden2/docs/re_notes_lights_tracks_sounds.md

Koordinaten: Ausgabe in glTF/Godot (rechtshändig, y oben, Meter): Position (x, y, -z).
WICHTIG Quaternion: Die in scene2.bin/sounds.bin/tracks.dat gespeicherten Werte (w,x,y,z) wirken im
Original als KONJUGIERTE Rotation (belegt über 0x002C-Weltpositionen von Kindobjekten, Kamera->Ziel,
Flugzeugkurs). Korrekt umgerechnet: glTF (x, y, -z, w). Lokale +Z-Achse = Blick-/Leuchtrichtung;
nach der Spiegelung ist das -Z, also passt die Rotation direkt für Godot Camera3D/SpotLight3D/
DirectionalLight3D (die entlang -Z zeigen).

Aufruf: python -I fmt_mission_extra.py ARCTIC1 [out.json]
"""
import json
import math
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fmt_scene2 import chunks, cstr, parse  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ORIG = os.environ.get("DH2_ORIG") or os.path.join(ROOT, "HD2_orig")
CACHE = os.environ.get("DH2_CACHE") or os.path.join(ROOT, "DangerousHidden2", "orig_cache")

LIGHT_TYPES = {1: "point", 2: "spot", 3: "directional", 4: "ambient", 5: "fog",
               6: "point_ambient", 8: "layered_fog"}   # 6/8 aus Mafia-LS3D, in ARCTIC1 nicht vorhanden


# --- Mathematik ---------------------------------------------------------------

def qmul(a, b):
    w1, x1, y1, z1 = a
    w2, x2, y2, z2 = b
    return (w1 * w2 - x1 * x2 - y1 * y2 - z1 * z2, w1 * x2 + x1 * w2 + y1 * z2 - z1 * y2,
            w1 * y2 - x1 * z2 + y1 * w2 + z1 * x2, w1 * z2 + x1 * y2 - y1 * x2 + z1 * w2)


def qrot(q, v):
    w, x, y, z = q
    return qmul(qmul(q, (0.0,) + tuple(v)), (w, -x, -y, -z))[1:]


def conj(q):
    return (q[0], -q[1], -q[2], -q[3])


def qnorm(q):
    n = math.sqrt(sum(c * c for c in q)) or 1.0
    return tuple(c / n for c in q)


def eff(q_stored):
    """Gespeichertes (w,x,y,z) -> tatsächlich wirkende Rotation (Hamilton, LS3D-Koordinaten)."""
    return conj(q_stored)


def gpos(p):
    return [round(p[0], 5), round(p[1], 5), round(-p[2], 5)]


def gdir(v):
    return [round(v[0], 5), round(v[1], 5), round(-v[2], 5)]


def gquat_eff(q):
    """Wirkende LS3D-Rotation (w,x,y,z) -> glTF (x,y,z,w) mit gespiegelter z-Achse."""
    w, x, y, z = q
    return [round(-x, 6), round(-y, 6), round(z, 6), round(w, 6)]


def gquat_stored(q):
    """Gespeichertes scene2/tracks-Quaternion (w,x,y,z) -> glTF (x,y,z,w) = (x, y, -z, w)."""
    return gquat_eff(eff(q))


# --- Weltlage über Elternketten -------------------------------------------------

class Resolver:
    """Weltlage von Objekten. Eltern: Objektname, Sektorname (Identität) oder 'Objekt.Frame'
    (Frame im 4DS-Modell des Objekts, z. B. '_.telo'). Position: gespeicherte 0x002C-Weltposition
    (maßgeblich); Rotation: Elternkette (konjugierte Quaternionen)."""

    def __init__(self, objs, frame_loader=None):
        self.by = {}
        for o in objs:
            self.by.setdefault(o.get("name"), o)
        self.frame_loader = frame_loader
        self.unresolved = set()

    def _model_frame(self, obj, frame):
        if not self.frame_loader or not obj.get("model"):
            return None
        frames = self.frame_loader(obj["model"])
        if not frames:
            return None
        byname = {f["name"]: f for f in frames}
        byidx = {f["index"]: f for f in frames}
        f = byname.get(frame)
        if f is None:
            return None
        q = (1.0, 0.0, 0.0, 0.0)
        while f is not None:      # 4DS-Quaternion (x,y,z,w); hier nur Identität belegt -> Annahme
            x, y, z, w = f["rot"]
            q = qmul((w, x, y, z), q)
            par = f.get("parent", 0)
            f = byidx.get(par - 1) if par else None
        return q

    def world_rot(self, name, depth=0):
        """Wirkende Weltrotation (LS3D, w,x,y,z) des Objekts oder Eltern-Bezeichners."""
        if depth > 32 or not name:
            return (1.0, 0.0, 0.0, 0.0)
        o = self.by.get(name)
        if o is None:
            if "." in name:
                base, frame = name.split(".", 1)
                bo = self.by.get(base)
                if bo is not None:
                    fq = self._model_frame(bo, frame)
                    if fq is None:
                        self.unresolved.add(name)
                        fq = (1.0, 0.0, 0.0, 0.0)
                    return qmul(self.world_rot(base, depth + 1), fq)
            return (1.0, 0.0, 0.0, 0.0)      # Sektor / Primary sector: Identität
        q = eff(o.get("rot", (1.0, 0.0, 0.0, 0.0)))
        par = o.get("parent")
        if par and par != name:
            q = qmul(self.world_rot(par, depth + 1), q)
        return qnorm(q)

    def transform(self, o):
        """Dict mit lokaler und Welt-Lage (glTF) für Objekt o."""
        pos = o.get("pos", (0.0, 0.0, 0.0))
        wq = self.world_rot(o.get("name"))
        wp = o.get("world_pos", pos)
        return {
            "parent": o.get("parent", ""),
            "pos": gpos(pos), "rot": gquat_stored(o.get("rot", (1.0, 0.0, 0.0, 0.0))),
            "scale": [round(s, 6) for s in o.get("scale", (1.0, 1.0, 1.0))],
            "world_pos": gpos(wp), "world_rot": gquat_eff(wq),
            "forward": gdir(qrot(wq, (0.0, 0.0, 1.0))),     # LS3D +Z = Blick-/Leuchtrichtung
        }


def _f(d, a, b):
    return [round(x, 6) for x in struct.unpack_from("<%df" % ((b - a) // 4), d, a)]


# --- Lichter (scene2.bin, Objekttyp 2) -----------------------------------------

def parse_lights(scene2_bytes, resolver=None, objs=None):
    d = scene2_bytes
    if objs is None:
        _, objs = parse(d)
    res = resolver or Resolver(objs)
    out = []
    for o in objs:
        if o.get("type") != 2 or 0x4040 not in o["chunks"]:
            continue
        s, e = o["chunks"][0x4040]
        L = {"name": o.get("name", ""), "sectors": []}
        for t, a, b in chunks(d, s, e):
            if t == 0x4041:
                L["type_id"] = struct.unpack_from("<I", d, a)[0]
                L["type"] = LIGHT_TYPES.get(L["type_id"], "unknown")
            elif t == 0x0026:
                v = _f(d, a, b)
                L["color"] = v[:3]
                L["color_extra"] = v[3:]          # immer (1,1,1, 0,0,0) in ARCTIC1 – Bedeutung offen
            elif t == 0x4042:
                v = _f(d, a, b)
                L["power"] = v[0]
                L["power_extra"] = v[1:]          # immer (1,1)
            elif t == 0x4043:
                v = _f(d, a, b)
                L["cone_inner"], L["cone_outer"] = v[0], v[1]     # Radiant (voller Winkel, s. Doku)
            elif t == 0x4044:
                v = _f(d, a, b)
                L["range"] = v[0]                 # Reichweite (Meter), v[5] == v[0]
                L["falloff_raw"] = v              # [range, a, 0, b, a, range] – Kurve, Bedeutung offen
            elif t == 0x4045:
                L["flags"] = struct.unpack_from("<I", d, a)[0]
            elif t == 0x4046:
                L["sectors"].append(cstr(d, a, b))
            else:
                L.setdefault("unknown_chunks", {})["%04x" % t] = d[a:b].hex()
        if 0x4033 in o["chunks"]:
            L["has_4033"] = True                  # leerer Marker-Chunk (nur FOG_WATER/AMBIENT-WATER)
        fl = L.get("flags", 0)
        L["flags_hex"] = "0x%x" % fl
        L["lightmap_only"] = bool(fl & 0x08)      # Hypothese (s. Doku): Bake-Licht, nicht zur Laufzeit
        L.update(res.transform(o))
        out.append(L)
    return out


# --- Kameras (scene2.bin, Objekttyp 3) -----------------------------------------

def parse_cameras(scene2_bytes, resolver=None, objs=None):
    d = scene2_bytes
    if objs is None:
        _, objs = parse(d)
    res = resolver or Resolver(objs)
    out = []
    for o in objs:
        if o.get("type") != 3:
            continue
        c = {"name": o.get("name", "")}
        if 0x4036 in o["chunks"]:
            s, e = o["chunks"][0x4036]
            for t, a, b in chunks(d, s, e):
                if t == 0x3010:
                    c["fov"] = round(struct.unpack_from("<f", d, a)[0], 6)     # Radiant
                elif t == 0x3011:
                    c["far"] = round(struct.unpack_from("<f", d, a)[0], 6)
        c.update(res.transform(o))
        out.append(c)
    return out


def parse_scene_settings(scene2_bytes):
    d = scene2_bytes
    header, _ = parse(d)
    out = {}
    if 0x3010 in header:
        out["camera_fov"] = round(struct.unpack_from("<f", d, header[0x3010][0])[0], 6)
    if 0x3011 in header:
        out["view_distance"] = round(struct.unpack_from("<f", d, header[0x3011][0])[0], 6)
    if 0x3200 in header:
        out["background_color"] = _f(d, *header[0x3200])
    if 0x3211 in header:
        out["clip_near_far"] = _f(d, *header[0x3211])
    return out


# --- Spuren (tracks.dat) --------------------------------------------------------

def parse_tracks(data):
    tracks = []
    for t, s, e in chunks(data, 0, len(data)):
        if t != 0x2426:
            continue
        for t2, s2, e2 in chunks(data, s, e):
            if t2 != 0x2454:
                continue
            tr = {"name": "", "keys": []}
            for t3, s3, e3 in chunks(data, s2, e2):
                if t3 == 0x2486:
                    tr["name"] = cstr(data, s3, e3)
                elif t3 == 0x2490:
                    tr["param_2490"] = round(struct.unpack_from("<f", data, s3)[0], 6)
                elif t3 == 0x249A:
                    tr["param_249a"] = round(struct.unpack_from("<f", data, s3)[0], 6)
                elif t3 == 0x24B8:
                    k = {}
                    for t4, s4, e4 in chunks(data, s3, e3):
                        if t4 == 0x251C:
                            k["_p"] = struct.unpack_from("<3f", data, s4)
                        elif t4 == 0x2580:
                            k["speed"] = round(struct.unpack_from("<f", data, s4)[0], 6)
                        elif t4 == 0x25E4:
                            k["_q"] = struct.unpack_from("<4f", data, s4)
                    tr["keys"].append(k)
                else:
                    tr.setdefault("unknown_chunks", {})["%04x" % t3] = data[s3:e3].hex()
            # Ableitungen: Segmentlänge, geschätzte Zeit unter der Annahme "speed = m/s ab diesem Schlüssel"
            t_acc = 0.0
            keys = tr["keys"]
            for i, k in enumerate(keys):
                k["time_est"] = round(t_acc, 4)
                if i + 1 < len(keys):
                    seg = math.dist(k["_p"], keys[i + 1]["_p"])
                    k["seg_len"] = round(seg, 4)
                    if k.get("speed"):
                        t_acc += seg / k["speed"]
            tr["duration_est"] = round(t_acc, 4)
            for k in keys:
                p, q = k.pop("_p"), k.pop("_q")
                k["pos"] = gpos(p)
                k["rot"] = gquat_stored(q)
                k["forward"] = gdir(qrot(eff(q), (0.0, 0.0, 1.0)))
            tracks.append(tr)
    return tracks


# --- Klangquellen (sounds.bin, Objekttyp 4) ------------------------------------

def parse_sounds(data, resolver=None, objs=None):
    if objs is None:
        _, objs = parse(data)
    res = resolver or Resolver(objs)
    out = []
    for o in objs:
        if o.get("type") != 4 or 0x4060 not in o["chunks"]:
            continue
        s, e = o["chunks"][0x4060]
        S = {"name": o.get("name", ""), "sectors": []}
        flags = set()
        for t, a, b in chunks(data, s, e):
            if t == 0x0010:
                S["file"] = cstr(data, a, b)
            elif t == 0x4061:
                S["type_id"] = struct.unpack_from("<I", data, a)[0]   # 1 = Punktquelle, 3 = Ambient (2D)
            elif t == 0x4062:
                S["volume"] = round(struct.unpack_from("<f", data, a)[0], 6)
            elif t == 0x4063:
                S["outer_volume"] = round(struct.unpack_from("<f", data, a)[0], 6)   # Kegel-Außenlautstärke?
            elif t == 0x4064:
                S["cone_inner"], S["cone_outer"] = _f(data, a, b)    # Radiant
            elif t == 0x4068:
                v = _f(data, a, b)
                S["radius_inner"], S["radius_outer"] = v[0], v[1]
                S["radius_extra"] = v[2:]          # meist (1, 0); Bedeutung offen
            elif t == 0x4066:
                flags.add("4066")
            elif t == 0x4067:
                flags.add("4067")
            elif t == 0xB800:
                S["pitch"] = round(struct.unpack_from("<f", data, a)[0], 6)
            elif t == 0xB200:
                S["sectors"].append(cstr(data, a, b))
            else:
                S.setdefault("unknown_chunks", {})["%04x" % t] = data[a:b].hex()
        S["loop"] = "4066" in flags              # Hypothese, mittlere Konfidenz (s. Doku)
        S["flag_4067"] = "4067" in flags         # Hypothese: beim Start eingeschaltet
        S["ambient"] = S.get("type_id") == 3
        S.update(res.transform(o))
        out.append(S)
    return out


# --- Musik (IngameSounds.def) ---------------------------------------------------

def parse_music_table(ingame_sounds_def):
    """Kategorie mit *.ogg-Gruppen (Index = Argument von PlayMusic/PlayCutsceneMusic)."""
    d = ingame_sounds_def
    for t, s, e in chunks(d, 0, len(d)):
        for t2, s2, e2 in chunks(d, s, e):
            groups = []
            for t3, s3, e3 in chunks(d, s2, e2):
                if t3 != 0x04B0:
                    continue
                g = {"index": len(groups), "name": "", "files": []}
                for t4, s4, e4 in chunks(d, s3, e3):
                    if t4 == 0x04BA:
                        g["name"] = cstr(d, s4, e4)
                    elif t4 == 0x0514:
                        for t5, s5, e5 in chunks(d, s4, e4):
                            if t5 == 0x0578:
                                g["files"].append(cstr(d, s5, e5))
                groups.append(g)
            if groups and any(f.lower().endswith(".ogg") for g in groups for f in g["files"]):
                return groups
    return []


# --- CLI -----------------------------------------------------------------------

def _archive_reader():
    import dta_extract
    cache = {}

    def get(name):
        if name not in cache:
            a = dta_extract.Archive(os.path.join(ORIG, name))
            a.index = {e[0].lower(): e for e in a.entries}
            cache[name] = a
        return cache[name]

    def read(path, archives):
        key = path.lower().replace("/", "\\")
        for n in ["patch.dta"] + archives:
            a = get(n)
            if key in a.index:
                try:
                    return a.read(a.index[key])
                except ValueError:
                    continue      # ISD1-Blocktypen im Patch noch nicht lesbar
        return None
    return read


def build(mission):
    read = _archive_reader()
    m = mission.upper()

    def mf(name):
        return read("missions/%s/%s" % (m, name), ["Missions.dta"])

    import fmt_4ds
    fcache = {}

    def frame_loader(model):
        if model not in fcache:
            data = read("models/%s.4ds" % model, ["MODELS.DTA"])
            fcache[model] = fmt_4ds.read_model(data, quiet=True)["frames"] if data else None
        return fcache[model]

    s2 = mf("scene2.bin")
    _, sobjs = parse(s2)
    snd = mf("sounds.bin")
    nobjs = parse(snd)[1] if snd else []
    res = Resolver(sobjs + nobjs, frame_loader)
    out = {
        "mission": m,
        "coords": "glTF/Godot: pos (x,y,-z); quat xyzw = (x,y,-z,w) from stored (w,x,y,z); forward = light/camera direction",
        "scene": parse_scene_settings(s2),
        "lights": parse_lights(s2, res, sobjs),
        "cameras": parse_cameras(s2, res, sobjs),
        "tracks": parse_tracks(mf("tracks.dat") or b""),
        "sounds": parse_sounds(snd, res, nobjs) if snd else [],
    }
    isd = read("tables/IngameSounds.def", ["others.DTA"])
    if isd:
        out["music_table"] = parse_music_table(isd)
    out["unresolved_parents"] = sorted(res.unresolved)
    return out


def main():
    mission = sys.argv[1] if len(sys.argv) > 1 else "ARCTIC1"
    dst = sys.argv[2] if len(sys.argv) > 2 else os.path.join(CACHE, mission.lower(), "extra.json")
    out = build(mission)
    os.makedirs(os.path.dirname(os.path.abspath(dst)), exist_ok=True)
    with open(dst, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=1)
    print("%s: %d Lichter, %d Kameras, %d Spuren (%d Schlüssel), %d Klangquellen, %d Musikgruppen -> %s" % (
        mission, len(out["lights"]), len(out["cameras"]), len(out["tracks"]),
        sum(len(t["keys"]) for t in out["tracks"]), len(out["sounds"]), len(out.get("music_table", [])), dst))
    if out["unresolved_parents"]:
        print("  unaufgelöste Eltern:", out["unresolved_parents"])


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    main()
