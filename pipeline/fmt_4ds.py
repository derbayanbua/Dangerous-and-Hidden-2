"""Parser für LS3D-4DS-Modelle aus Hidden & Dangerous 2 (Version 0x29).

Rekonstruiert aus den Originaldaten (siehe DangerousHidden2/docs/RE_FINDINGS.md, Abschnitt 4DS).
Ausgangspunkt war die bekannte Mafia-Struktur (v29); HD2-Abweichungen sind markiert.
Nur zur Konvertierung der Original-Assets des Nutzers in einen lokalen Cache.
"""
import struct

# Materialflags (Bitbelegung wie Mafia)
MTL_DIFFUSE = 0x00040000
MTL_ENVMAP = 0x00080000
MTL_MIPMAP = 0x00800000
MTL_ANIM_ALPHA = 0x02000000
MTL_ANIM_DIFFUSE = 0x04000000
MTL_COLORED = 0x08000000
MTL_DOUBLESIDED = 0x10000000
MTL_COLORKEY = 0x20000000
MTL_ALPHATEX = 0x40000000
MTL_ADDITIVE = 0x80000000


class Reader:
    def __init__(self, data: bytes, pos: int = 0):
        self.d = data
        self.p = pos

    def u8(self):
        v = self.d[self.p]; self.p += 1; return v

    def u16(self):
        v = struct.unpack_from("<H", self.d, self.p)[0]; self.p += 2; return v

    def u32(self):
        v = struct.unpack_from("<I", self.d, self.p)[0]; self.p += 4; return v

    def f32(self):
        v = struct.unpack_from("<f", self.d, self.p)[0]; self.p += 4; return v

    def vec(self, n):
        v = struct.unpack_from("<%df" % n, self.d, self.p); self.p += 4 * n; return list(v)

    def pstr(self):
        n = self.u8()
        s = self.d[self.p:self.p + n].decode("latin-1"); self.p += n; return s

    def raw(self, n):
        v = self.d[self.p:self.p + n]; self.p += n; return v


def read_material(r: Reader) -> dict:
    m = {"flags": r.u32()}
    m["ambient"] = r.vec(4)
    m["diffuse"] = r.vec(4)
    m["emission"] = r.vec(4)
    m["specular"] = r.vec(4)        # HD2: zusätzliche Farbe gegenüber Mafia
    m["glossiness"] = r.f32()
    m["opacity"] = r.f32()
    f = m["flags"]
    if f & MTL_ENVMAP:
        m["env_ratio"] = r.f32()
        m["env_map"] = r.pstr()
    m["diffuse_map"] = r.pstr()
    # Alpha-Textur nur bei vorhandener Diffuse-Textur und ohne Additiv/Colorkey/0x01000000
    # (LS3DF.dll FUN_1002bbe0 / FUN_1002be30: test 0x40000000, test 0xA1000000)
    if m["diffuse_map"] and f & MTL_ALPHATEX and not f & 0xA1000000:
        m["alpha_map"] = r.pstr()
    if f & MTL_ANIM_DIFFUSE:
        m["anim"] = [r.u32(), r.u16(), r.u32(), r.u32(), r.u32()]
    return m


# Frame-Typen (LS3DF.dll: Fabrik FUN_10018e40, Namen „FRAME_*“ im Datensegment; Ladefunktion je
# Klasse = vtable+0x70; Belege in DangerousHidden2/docs/re_notes_4ds_visuals.md)
FRAME_VISUAL = 1
FRAME_LIGHT = 2
FRAME_CAMERA = 3
FRAME_SOUND = 4
FRAME_SECTOR = 5
FRAME_DUMMY = 6
FRAME_TARGET = 7
FRAME_USER = 8
FRAME_MODEL = 9
FRAME_JOINT = 10
FRAME_VOLUME = 11
FRAME_OCCLUDER = 12
FRAME_SCENE = 13
FRAME_AREA = 14
FRAME_LANDSCAPE = 15
# Frame-Typen ohne Zusatzdaten nach dem gemeinsamen Kopf (Ladefunktion = Basis FUN_1001ec40)
FRAMES_HEADER_ONLY = (FRAME_CAMERA, FRAME_SOUND, FRAME_USER, FRAME_MODEL, FRAME_VOLUME, FRAME_SCENE,
                      FRAME_LANDSCAPE)

# Visual-Typen = Index in die Klassentabelle OBJ_/LMAP/SNGM/SMMR/BBRD/MRPH/LENS/PROJ/MIRR/EMTR/LNDP/SHD
# (LS3DF.dll VA 0x100a6edc; Fabrik FUN_10019750)
VIS_STANDARD = 0      # OBJ_  Objekt
VIS_LITOBJECT = 1     # LMAP  Lit-object (gleiches Dateiformat wie Standard)
VIS_SINGLEMESH = 2    # SNGM  Skin-Mesh
VIS_SINGLEMORPH = 3   # SMMR  Skin-Mesh + Morph
VIS_BILLBOARD = 4     # BBRD
VIS_MORPH = 5         # MRPH  Mesh + Morph
VIS_GLOW = 6          # LENS  Lensflare/Glow
VIS_PROJECTOR = 7     # PROJ
VIS_MIRROR = 8        # MIRR
VIS_EMITOR = 9        # EMTR  Partikelemitter
VIS_LANDPATCH = 10    # LNDP  (Fabrik erzeugt keine Instanz -> im Original ein Ladefehler)
VIS_SHADOW = 11       # SHD   (keine Zusatzdaten)
VIS_NAMES = ["standard", "lit-object", "singlemesh", "singlemorph", "billboard", "morph", "glow",
             "projector", "mirror", "emitor", "landpatch", "shadow"]
MESH_VISUALS = (VIS_STANDARD, VIS_LITOBJECT, VIS_SINGLEMESH, VIS_SINGLEMORPH, VIS_BILLBOARD, VIS_MORPH)


def read_lods(r: Reader) -> list:
    """Mesh-LODs (LS3DF.dll FUN_1005ddd0). Je LOD: f32 Distanz, u32 Zusatzstrom (0 in allen
    HD2-Dateien, sonst Fehler), u16 nv; nv == 0xFFFF: Positionen/Normalen von LOD 0, nur
    nv0×8 B (UV); sonst nv×32 B (Pos, Normale, UV); u8 Gruppen × (u16 nf, nf×3 u16, u16 Material)."""
    lods = []
    n = r.u8()
    if n > 10:
        raise NotImplementedError("LOD-Anzahl %d > 10 @%x" % (n, r.p - 1))
    for _ in range(n):
        lod = {"distance": r.f32(), "unk": r.u32()}
        if lod["unk"]:
            raise NotImplementedError("LOD-Zusatzstrom 0x%x @%x" % (lod["unk"], r.p - 4))
        nv = r.u16()
        if nv == 0xFFFF:
            base = lods[0]["vertices"] if lods else []
            raw = r.raw(len(base) * 8)
            uv = [struct.unpack_from("<2f", raw, i * 8) for i in range(len(base))]
            lod["vertices"] = [tuple(base[i][:6]) + uv[i] for i in range(len(base))]
            lod["shared_positions"] = True
        else:
            raw = r.raw(nv * 32)
            lod["vertices"] = [struct.unpack_from("<8f", raw, i * 32) for i in range(nv)]
        groups = []
        for _ in range(r.u8()):
            nf = r.u16()
            faces = struct.unpack_from("<%dH" % (nf * 3), r.d, r.p)
            r.p += nf * 6
            groups.append({"faces": faces, "material": r.u16()})
        lod["groups"] = groups
        lods.append(lod)
    return lods


def read_mirror(r: Reader) -> dict:
    """Spiegel (FUN_10033e80): 48 B (min vec4, max vec4, vec4 ?), 92 B (Matrix 4×4, Farbe vec4,
    f32 Sichtweite, u32 nv, u32 nf), nv×vec4, nf×3 u16."""
    m = {"min": r.vec(4), "max": r.vec(4), "unk": r.vec(4), "matrix": r.vec(16), "color": r.vec(4),
         "distance": r.f32()}
    nv = r.u32()
    nf = r.u32()
    m["vertices"] = [r.vec(4)[:3] for _ in range(nv)]
    m["faces"] = struct.unpack_from("<%dH" % (nf * 3), r.d, r.p); r.p += nf * 6
    return m


def read_emitor(r: Reader) -> dict:
    """Partikelemitter (FUN_1003d6c0): u32 Materialflags, pstr Textur; nur wenn Textur
    vorhanden und Flags & 0x40000000 (Alpha-Textur) und nicht & 0xA1000000: pstr Alpha-Textur."""
    e = {"flags": r.u32(), "texture": r.pstr()}
    if e["texture"] and e["flags"] & 0x40000000 and not e["flags"] & 0xA1000000:
        e["alpha_texture"] = r.pstr()
    return e


def read_frame(r: Reader, idx: int, lod_counts=None) -> dict:
    """Ein Frame. lod_counts: {Frameindex 1-basiert: LOD-Anzahl} für Skin-Daten instanzierter Meshes."""
    fr = {"index": idx, "type": r.u8()}
    t = fr["type"]
    if t == FRAME_VISUAL:
        fr["visual"] = r.u8()
        fr["render_flags"] = r.u16()
    fr["parent"] = r.u16()
    fr["pos"] = r.vec(3)
    fr["rot"] = r.vec(4)          # Quaternion (x, y, z, w)
    fr["scale"] = r.vec(3)
    fr["unk"] = r.u32()           # HD2: zusätzlich
    fr["culling"] = r.u8()
    fr["name"] = r.pstr()
    fr["params"] = r.pstr()
    if t == FRAME_VISUAL:
        v = fr["visual"]
        if v in MESH_VISUALS:
            fr["instance"] = r.u16()
            if fr["instance"] == 0:
                fr["lods"] = read_lods(r)
                nlods = len(fr["lods"])
            else:
                nlods = (lod_counts or {}).get(fr["instance"], 0)
            if lod_counts is not None:
                lod_counts[idx + 1] = nlods
            if v in (VIS_SINGLEMESH, VIS_SINGLEMORPH):
                fr["skin"] = read_skin(r, nlods)
            if v == VIS_BILLBOARD:
                fr["billboard_axis"] = r.u32()
                fr["billboard_ignore_cam"] = r.u8()
            if v in (VIS_SINGLEMORPH, VIS_MORPH):
                fr["morph"] = read_morph(r)
        elif v == VIS_GLOW:
            # je Element 8 B (f32 Position, f32 Größe) + u16 Material (FUN_10009610)
            fr["glows"] = [(r.f32(), r.f32(), r.u16()) for _ in range(r.u8())]
        elif v == VIS_PROJECTOR:
            fr["projector"] = (r.u8(), r.u8(), r.u16())
        elif v == VIS_MIRROR:
            fr["mirror"] = read_mirror(r)
        elif v == VIS_EMITOR:
            fr["emitor"] = read_emitor(r)
        elif v == VIS_SHADOW:
            pass
        else:
            raise NotImplementedError("Visual-Typ %d (Frame %d %s) @%x" % (v, idx, fr["name"], r.p))
    elif t == FRAME_LIGHT:
        fr["light"] = r.raw(96)      # Lichtparameter (96 B, FUN_10022e60), nicht ausgewertet
    elif t == FRAME_SECTOR:
        fr["sector"] = read_sector(r)
    elif t == FRAME_DUMMY:
        fr["min"] = r.vec(3); r.u32()
        fr["max"] = r.vec(3); r.u32()
    elif t == FRAME_TARGET:
        fr["target_flags"] = r.u16()
        fr["links"] = [r.u16() for _ in range(r.u8())]
    elif t == FRAME_JOINT:
        fr["joint_id"] = r.u32()     # HD2: Knochen-ID
    elif t == FRAME_OCCLUDER:
        nv = r.u32()
        nf = r.u32()
        verts = []
        for _ in range(nv):
            verts.append(r.vec(3)); r.u32()
        fr["vertices"] = verts
        fr["faces"] = struct.unpack_from("<%dH" % (nf * 3), r.d, r.p); r.p += nf * 6
    elif t in FRAMES_HEADER_ONLY:
        pass
    else:
        raise NotImplementedError("Frame-Typ %d (Frame %d %s) @%x" % (t, idx, fr["name"], r.p))
    return fr


def read_skin(r: Reader, nlods: int) -> dict:
    """Skin-Block eines SingleMesh/SingleMorph (LS3DF.dll FUN_10053900):
    u8 Gelenke; nur wenn > 0: Bounding-Box (2×vec4); u8[Gelenke] Zuordnung;
    je Gelenk 96 B (4×4-Matrix + 2×vec4); danach JE LOD: u32 n, n×u16.
    Feldnamen wie fmt_4ds_hd2skin (bbox_min, blend_parent, inv_bind, lod_weights=[(joint, w)])."""
    nj = r.u8()
    s = {"joints": [], "blend_parent": [], "lod_weights": []}
    if nj == 0:
        return s
    s["bbox_min"] = r.vec(4)
    s["bbox_max"] = r.vec(4)
    s["blend_parent"] = list(r.raw(nj))
    for _ in range(nj):
        s["joints"].append({"inv_bind": r.vec(16), "bmin": r.vec(4), "bmax": r.vec(4)})
    for _ in range(nlods):
        n = r.u32()
        raw = r.raw(n * 2)
        s["lod_weights"].append([(raw[2 * i], raw[2 * i + 1]) for i in range(n)])
    return s


def read_morph(r: Reader) -> dict:
    """Morph-Block (Morph/SingleMorph, LS3DF.dll FUN_10035490): u8 Ziele; nur wenn > 0:
    u8 Kanäle, u8 ?; je Kanal u16 nv; nur wenn nv > 0: nv×Ziele×(Pos vec3 + Normale vec3),
    u8 Indexflag, [nv×u16]; danach 48 B Hülle (min vec4, max vec4, Mittelpunkt vec3, Radius f32)."""
    m = {"targets": r.u8(), "channels": []}
    if m["targets"] == 0:
        return m
    nch = r.u8()
    m["unk"] = r.u8()
    for _ in range(nch):
        nv = r.u16()
        ch = {"nv": nv, "data": b""}
        m["channels"].append(ch)
        if nv == 0:
            continue
        ch["data"] = r.raw(nv * m["targets"] * 24)
        if r.u8():
            ch["links"] = list(struct.unpack_from("<%dH" % nv, r.d, r.p)); r.p += nv * 2
    m["bounds"] = {"min": r.vec(4), "max": r.vec(4), "center": r.vec(3), "radius": r.f32()}
    return m


def read_sector(r: Reader) -> dict:
    """Sektor (Sichtbarkeitsraum) mit Portalen. Geometrie wird nicht gerendert."""
    s = {"flags": (r.u32(), r.u32())}
    nv = r.u32()
    nf = r.u32()
    s["min"] = r.vec(3); r.u32()
    s["max"] = r.vec(3); r.u32()
    s["vertices"] = []
    for _ in range(nv):
        s["vertices"].append(r.vec(3)); r.u32()
    s["faces"] = struct.unpack_from("<%dH" % (nf * 3), r.d, r.p); r.p += nf * 6
    portals = []
    for _ in range(r.u8()):
        n = r.u8()
        p = {"plane": r.vec(4), "flags": r.u32(), "near": r.f32(), "far": r.f32(), "unk": r.f32(), "vertices": []}
        for _ in range(n):
            p["vertices"].append(r.vec(3)); r.u32()
        portals.append(p)
    s["portals"] = portals
    return s


def read_model(d: bytes, verbose=False, quiet=False):
    ver, mats, r = read_header(d)
    n = r.u16()
    frames = []
    stop = None
    lod_counts = {}
    for i in range(n):
        start = r.p
        try:
            frames.append(read_frame(r, i, lod_counts))
        except (NotImplementedError, IndexError, struct.error) as ex:
            stop = "%s Start @%x" % (ex, start)
            if not quiet:
                print("STOPP bei Frame", i, "von", n, ":", stop)
            break
    return {"version": ver, "materials": mats, "frames": frames, "frame_count": n, "end": r.p, "stop": stop}


def read_header(d: bytes):
    r = Reader(d)
    assert r.raw(4) == b"4DS\0", "kein 4DS"
    ver = r.u16()
    r.raw(8)  # FILETIME
    n = r.u16()
    mats = [read_material(r) for _ in range(n)]
    return ver, mats, r


if __name__ == "__main__":
    import sys
    d = open(sys.argv[1], "rb").read()
    ver, mats, r = read_header(d)
    print("Version", hex(ver), "Materialien", len(mats), "Ende Materialblock @", hex(r.p))
    flags = {}
    for m in mats:
        flags[hex(m["flags"])] = flags.get(hex(m["flags"]), 0) + 1
    print("Flags:", flags)
    for m in mats[:3] + mats[-3:]:
        print(" ", hex(m["flags"]), m.get("diffuse_map"), m.get("alpha_map", ""), m.get("env_map", ""))
    mdl = read_model(d)
    fr = mdl["frames"]
    print("Frames gelesen:", len(fr), "/", mdl["frame_count"])
    for f in fr[:5]:
        nv = sum(len(l["vertices"]) for l in f.get("lods", []))
        print("  ", f["index"], f["type"], f.get("visual"), f["name"], "parent", f["parent"], "verts", nv, "pos", [round(x, 2) for x in f["pos"]])
