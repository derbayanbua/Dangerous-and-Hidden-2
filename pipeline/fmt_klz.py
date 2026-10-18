"""Kollisionsflaechen mit Original-Material (tree.klz) einer Mission -> orig_cache/<mission>/surface.bin

Zweck: Untergrund fuer Schrittgeraeusche (hdmaterials.def +0x20 -> IngameSounds Kat. 0) und Einschlagklaenge
(hdmaterials.def +0x30 -> Kat. 4) wie im Original; Laufzeit: src/audio/surface_map.gd.

tree.klz (MISSIONS\\<m>\\tree.klz, Kennung "GifC", Version 5) [B, docs/re_notes_audio.md]:
  0x00 "GifC", u16 5, u16 1, u32 Datenoffset, u32 Anzahl Links, u32, u32; u32 Offsets[Links] -> {u32 Flags, Name}
  Daten: f32 minX, minZ, maxX, maxZ, Zellbreite, Zellhoehe; u32 Raster X, Raster Z; f32 Hoehenraster (4);
         u32 ...; +0x48 Anzahl Dreiecke, +0x50 Anzahl XTOBB, +0x68 Anzahl OBB (Kopf 0xA4 Byte);
         f32 Zellgrenzen X[nx+1], Y[ny+1], Z[nz+1]; 4 x f32; Dreiecke je 32 Byte:
         u32 Eigenschaften (Byte 3 = Material = Zeile in hdmaterials.def, hd2.exe 0x75C940),
         3 x {u16 Vertexindex, u16 Link} (Vertex des LOD0-Meshes des Link-Frames), f32 Normale[3], f32 d
         (Ebene n.p + d = 0 in Weltkoordinaten; Pruefung: 99,6 % der ARCTIC1-Dreiecke liegen auf ihrer Ebene).
Links: Frame aus scene.4ds oder "Objekt.Frame" (scene2-Objekt mit Modell, Frame im Modell).
Jedes Dreieck wird nur uebernommen, wenn die berechneten Weltpunkte auf der gespeicherten Ebene liegen (5 cm).

surface.bin (Godot-Koordinaten, z gespiegelt): "HDSF", u32 Version 1, u32 n, dann n x {u8 Material, 3 Byte 0,
9 x f32 Punkte}. Aufruf: pyenv\\Scripts\\python.exe -I fmt_klz.py ARCTIC1
Zusaetzlich collision.json (Flaechen-/Volumen-Links, versteckte Kollisionsersatz-Frames, siehe write_collision);
nur diese Datei: fmt_klz.py --collision ARCTIC1 ARCTIC1_MP …
"""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import convert_mission as cm  # noqa: E402
import fmt_4ds  # noqa: E402
import fmt_scene2  # noqa: E402

try:
    import numpy as np
except ImportError:
    np = None


def qmat(x, y, z, w):
    """Rotationsmatrix der KONJUGIERTEN Quaternion (Original-Konvention, docs/re_notes_lights_tracks_sounds.md §0)."""
    x, y, z = -x, -y, -z
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def trs(pos, rot_xyzw, scale):
    m = np.eye(4)
    m[:3, :3] = qmat(*rot_xyzw) @ np.diag(scale)
    m[:3, 3] = pos
    return m


class Model:
    """4DS-Frames mit Weltmatrix relativ zur Modellwurzel."""

    def __init__(self, data):
        self.m = fmt_4ds.read_model(data, quiet=True)
        self.by_index = {fr["index"] + 1: fr for fr in self.m["frames"]}
        self.by_name = {}
        for fr in self.m["frames"]:
            self.by_name.setdefault(fr["name"], fr)
        self._mat = {}

    def local(self, fr):
        k = fr["index"]
        if k not in self._mat:
            m = trs(fr["pos"], fr["rot"], fr["scale"])
            par = self.by_index.get(fr["parent"]) if fr["parent"] else None
            if par is not None and par is not fr:
                m = self.local(par) @ m
            self._mat[k] = m
        return self._mat[k]

    def verts(self, fr):
        src = self.by_index.get(fr.get("instance"), fr) if fr.get("instance") else fr
        lods = src.get("lods") or []
        return lods[0]["vertices"] if lods else []


def parse_klz(d):
    if d[:4] != b"GifC":
        raise ValueError("kein tree.klz (GifC)")
    coff, nlinks = struct.unpack_from("<II", d, 8)
    offs = struct.unpack_from("<%dI" % nlinks, d, 24)
    links = [d[o + 4:d.index(b"\0", o + 4)].decode("latin-1") for o in offs]
    nx, nz = struct.unpack_from("<II", d, coff + 24)
    ny = struct.unpack_from("<I", d, coff + 48)[0]
    nfaces = struct.unpack_from("<I", d, coff + 0x48)[0]
    p = coff + 0xA4 + 4 * ((nx + 1) + (ny + 1) + (nz + 1)) + 16
    faces = []
    for k in range(nfaces):
        q = p + 32 * k
        prop = struct.unpack_from("<I", d, q)[0]
        i0, l0, i1, _l1, i2, _l2 = struct.unpack_from("<6H", d, q + 4)
        n = struct.unpack_from("<4f", d, q + 16)
        faces.append((prop >> 24, links[l0], (i0, i1, i2), n))
    return links, faces


def link_flags(d):
    """{Linkname: Flags} – Bit 0 = Dreiecke (Flaechenkollision), Bit 1 = Volumen (XTOBB/OBB-Kisten).
    Beleg ARCTIC1: alle 514+11 Links mit Bit 0 werden von Dreiecken referenziert, alle 2543+11 mit Bit 1 von
    XTOBB (192 B: u32 Eigenschaften, u32 Link, Welt-AABB, lokale Halbachsen, 2 Matrizen) bzw. OBB (160 B)."""
    coff, nlinks = struct.unpack_from("<II", d, 8)
    offs = struct.unpack_from("<%dI" % nlinks, d, 24)
    return {d[o + 4:d.index(b"\0", o + 4)].decode("latin-1"): struct.unpack_from("<I", d, o)[0] for o in offs}


VOLUME_SIZE = {0x80: 192, 0x81: 32, 0x83: 160}   # XTOBB, AABB, OBB (Byte 0 der Eigenschaften = Art)


def volume_links(d):
    """Links der Volumina nach Art: {"box": XTOBB/AABB-Links, "obb": OBB-Links}. Die Volumina folgen den Dreiecken;
    Art und Groesse aus Byte 0 der Eigenschaften (0x81 AABB 32 B, 0x80 XTOBB 192 B, 0x83 OBB 160 B). Unbekannte
    Arten (0x82/0x84, selten) werden ueber die Groesse bestimmt, bei der der naechste Satz wieder plausibel ist."""
    coff, nlinks = struct.unpack_from("<II", d, 8)
    offs = struct.unpack_from("<%dI" % nlinks, d, 24)
    links = [d[o + 4:d.index(b"\0", o + 4)].decode("latin-1") for o in offs]
    nx, nz = struct.unpack_from("<II", d, coff + 24)
    ny = struct.unpack_from("<I", d, coff + 48)[0]
    cnt = [struct.unpack_from("<I", d, coff + 0x48 + 8 * i)[0] for i in range(6)]
    q = coff + 0xA4 + 4 * ((nx + 1) + (ny + 1) + (nz + 1)) + 16 + 32 * cnt[0]
    out = {"box": set(), "obb": set()}

    def plausible(p):
        if p + 8 > len(d):
            return False
        prop, link = struct.unpack_from("<II", d, p)
        return 0x80 <= (prop & 0xFF) <= 0x84 and link < nlinks

    for _ in range(sum(cnt[1:])):
        if not plausible(q):
            break
        prop, link = struct.unpack_from("<II", d, q)
        kind = prop & 0xFF
        size = VOLUME_SIZE.get(kind)
        if size is None:
            size = next((s for s in (20, 24, 28, 32, 36, 40, 48) if plausible(q + s)), 32)
        if kind in (0x80, 0x81):
            out["box"].add(links[link])
        elif kind == 0x83:
            out["obb"].add(links[link])
        q += size
    return out


def write_collision(mission):
    """orig_cache/<m>/collision.json: Kollisionsaufbau wie im Original [B, docs/re_notes_collision.md]:
      faces   – Frames/„Objekt.Frame“ mit Flaechenkollision in tree.klz (Link-Bit 0)
      volumes – Frames nur mit Kistenvolumen (Link-Bit 1)
      hidden  – scene2.bin-Eintraege mit Chunk 0x4033 (unsichtbar): Kollisionsersatz der Leveldesigner,
                z. B. Treppenrampen x_schody*/xx_schod_col_*, Bodenvolumen VOLUM_*, Kartenrand BORDER.
    Sichtbare Treppenstufen haben im Original KEINE Flaechenkollision; begangen wird der unsichtbare Ersatz."""
    mdir = mission.upper()
    klz = cm.read_file("missions/%s/tree.klz" % mdir, ["Missions.dta"])
    s2 = cm.read_file("missions/%s/scene2.bin" % mdir, ["Missions.dta"])
    if not klz or len(klz) < 64 or klz[:4] != b"GifC" or not s2:
        print("%s collision.json: kein tree.klz/scene2.bin" % mdir)
        return False
    fl = link_flags(klz)
    _, objs = fmt_scene2.parse(s2)
    hidden = sorted({o.get("name", "") for o in objs if 0x4033 in o.get("chunks", {}) and o.get("name")})
    vl = volume_links(klz)
    out = {"version": 2, "mission": mdir,
           "faces": sorted(n for n, f in fl.items() if f & 1),
           "volumes": sorted(n for n, f in fl.items() if f & 2 and not f & 1),
           "boxes": sorted(vl["box"]),      # Kisten (XTOBB/AABB): z. B. Moebel, Balken – Kollision behalten
           "hidden": hidden}
    dst = os.path.join(cm.CACHE, mdir.lower(), "collision.json")
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    import json
    with open(dst, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=0)
    print("%s collision.json: %d Flaechen-Links, %d Volumen-Links (%d Kisten, %d OBB), %d versteckt" % (
        mdir, len(out["faces"]), len(out["volumes"]), len(vl["box"]), len(vl["obb"]), len(hidden)))
    return True


def build(mission):
    if np is None:
        raise SystemExit("numpy fehlt (tools/pyenv)")
    mdir = mission.upper()
    klz = cm.read_file("missions/%s/tree.klz" % mdir, ["Missions.dta"])
    if not klz:
        print("kein tree.klz fuer", mdir)
        return
    write_collision(mdir)
    links, faces = parse_klz(klz)
    scene = Model(cm.read_file("missions/%s/scene.4ds" % mdir, ["Missions.dta"]))
    _, objs = fmt_scene2.parse(cm.read_file("missions/%s/scene2.bin" % mdir, ["Missions.dta"]))
    objects = {}
    for o in objs:
        objects.setdefault(o.get("name", ""), o)
    models = {}
    obj_world = {}

    def model(name):
        key = name.lower()
        if key not in models:
            data = cm.read_file("models/%s.4ds" % name, ["Models.dta"])
            models[key] = Model(data) if data else None
        return models[key]

    def node_world(name, depth=0):
        """Weltmatrix eines scene2-Objekts bzw. scene.4ds-Frames (None = unbekannt)."""
        if depth > 12:
            return None
        if name in obj_world:
            return obj_world[name]
        res = None
        o = objects.get(name)
        if o is not None and "pos" in o:
            w, x, y, z = o.get("rot", (1, 0, 0, 0))
            m = trs(o["pos"], (x, y, z, w), o.get("scale", (1, 1, 1)))
            par = o.get("parent", "")
            pm = np.eye(4)
            if par and par != name:
                pw = node_world(par, depth + 1)
                if pw is not None:
                    pm = pw
            res = pm @ m
        elif name in scene.by_name:
            res = scene.local(scene.by_name[name])
        elif "." in name:
            on, fn = name.split(".", 1)
            ow = node_world(on, depth + 1)
            mo = model(objects[on]["model"]) if on in objects and objects[on].get("model") else None
            if ow is not None and mo is not None and fn in mo.by_name:
                res = ow @ mo.local(mo.by_name[fn])
        obj_world[name] = res
        return res

    def frame_verts(link):
        if link in scene.by_name:
            return scene.verts(scene.by_name[link])
        if "." in link:
            on, fn = link.split(".", 1)
            o = objects.get(on)
            mo = model(o["model"]) if o and o.get("model") else None
            if mo is not None and fn in mo.by_name:
                return mo.verts(mo.by_name[fn])
        return []

    out = bytearray()
    kept = dropped = unresolved = 0
    vcache = {}
    for mat, link, idx, n in faces:
        if link not in vcache:
            vcache[link] = (node_world(link), frame_verts(link))
        w, vs = vcache[link]
        if w is None or not vs or max(idx) >= len(vs):
            unresolved += 1
            continue
        pts = [w @ np.array([vs[i][0], vs[i][1], vs[i][2], 1.0]) for i in idx]
        if any(abs(n[0] * p[0] + n[1] * p[1] + n[2] * p[2] + n[3]) > 0.05 for p in pts):
            dropped += 1
            continue
        out += struct.pack("<B3x", mat)
        for p in pts:
            out += struct.pack("<3f", p[0], p[1], -p[2])     # LS3D -> Godot/glTF (z gespiegelt)
        kept += 1
    dst = os.path.join(cm.CACHE, mdir.lower(), "surface.bin")
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    with open(dst, "wb") as f:
        f.write(b"HDSF" + struct.pack("<II", 1, kept) + bytes(out))
    print("%s surface.bin: %d Dreiecke uebernommen, %d verworfen (Ebene), %d ohne Geometrie; Links %d" % (
        mdir, kept, dropped, unresolved, len(links)))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    if sys.argv[1] == "--collision":
        # nur collision.json (schnell), z. B. fuer alle Ordner: fmt_klz.py --collision ARCTIC1 ARCTIC1_MP …
        for m in sys.argv[2:]:
            write_collision(m)
    else:
        build(sys.argv[1])
