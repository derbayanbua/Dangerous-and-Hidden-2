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
    if f & MTL_ALPHATEX:
        m["alpha_map"] = r.pstr()
    if f & MTL_ANIM_DIFFUSE:
        m["anim"] = [r.u32(), r.u16(), r.u32(), r.u32(), r.u32()]
    return m


FRAME_VISUAL = 1
FRAME_SECTOR = 5
FRAME_DUMMY = 6
FRAME_TARGET = 7
FRAME_JOINT = 10
FRAME_OCCLUDER = 12

# Visual-Typen (Nummerierung wie Mafia)
VIS_STANDARD = 0
VIS_SINGLEMESH = 2
VIS_SINGLEMORPH = 3
VIS_BILLBOARD = 4
VIS_MORPH = 5
VIS_GLOW = 6
VIS_MIRROR = 8


def read_lods(r: Reader) -> list:
    lods = []
    for _ in range(r.u8()):
        lod = {"distance": r.f32(), "unk": r.u32()}   # HD2: u32 zusätzlich
        nv = r.u16()
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


def read_frame(r: Reader, idx: int) -> dict:
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
        if v in (VIS_STANDARD, VIS_BILLBOARD):
            fr["instance"] = r.u16()
            if fr["instance"] == 0:
                fr["lods"] = read_lods(r)
            if v == VIS_BILLBOARD:
                fr["billboard_axis"] = r.u32()
                fr["billboard_ignore_cam"] = r.u8()
        elif v in (VIS_SINGLEMESH, VIS_SINGLEMORPH):
            fr["instance"] = r.u16()
            if fr["instance"] == 0:
                fr["lods"] = read_lods(r)
            fr["skins"] = [read_skin(r) for _ in fr.get("lods", [])]
            if v == VIS_SINGLEMORPH:
                raise NotImplementedError("SingleMorph-Daten (Frame %d %s) @%x" % (idx, fr["name"], r.p))
        elif v == VIS_GLOW:
            fr["glows"] = [(r.f32(), r.u16()) for _ in range(r.u8())]
        else:
            raise NotImplementedError("Visual-Typ %d (Frame %d %s) @%x" % (v, idx, fr["name"], r.p))
    elif t == FRAME_SECTOR:
        fr["sector"] = read_sector(r)
    elif t == FRAME_DUMMY:
        fr["min"] = r.vec(3); r.u32()
        fr["max"] = r.vec(3); r.u32()
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
    else:
        raise NotImplementedError("Frame-Typ %d (Frame %d %s) @%x" % (t, idx, fr["name"], r.p))
    return fr


def read_skin(r: Reader) -> dict:
    """Skin-Daten eines LOD (HD2, vorläufig rekonstruiert):
    u8 Gelenke; Bounding-Box (2×vec4); u8[Gelenke] Zuordnung;
    je Gelenk 4×4-Matrix + 2×vec4; u32 n; n×? Gewichte."""
    nj = r.u8()
    s = {"min": r.vec(4), "max": r.vec(4)}
    s["map"] = list(r.raw(nj))
    s["joints"] = []
    for _ in range(nj):
        s["joints"].append({"matrix": r.vec(16), "bmin": r.vec(4), "bmax": r.vec(4)})
    n = r.u32()
    s["weight_count"] = n
    if n:
        s["weights"] = r.raw(n * 4)   # Annahme: float je gewichtetem Vertex
    return s


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
    for i in range(n):
        start = r.p
        try:
            frames.append(read_frame(r, i))
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
