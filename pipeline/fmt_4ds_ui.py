"""4DS-Leser für HD2-Oberflächenmodelle (v. a. MODELS\\gameinterface.4ds, das In-Game-HUD).

fmt_4ds.read_model scheitert an gameinterface.4ds nicht wegen eines neuen Frame-Typs, sondern
weil fmt_4ds.read_material bei gesetztem MTL_ALPHATEX (0x40000000) immer einen Alpha-Textur-
namen liest. In HD2 gilt (belegt per Vollerhebung über alle 5214 Modelle in Models.dta,
docs/re_notes_hud.md):

    Alpha-Name folgt  <=>  (flags & MTL_ALPHATEX) and not (flags & 0x01000000) and diffuse != ""

Bit 0x01000000 ("Alpha aus der Diffuse-Textur selbst") ist bei allen *.TGA-Materialien mit
ALPHATEX gesetzt; diese haben keinen separaten Alpha-Namen. Materialien ohne Diffuse-Namen
(leerer String, z. B. Flags 0x08000001 "nur Farbe") haben ebenfalls keinen.

Danach ist der Rest der Datei mit den Frame-Lesern aus fmt_4ds / fmt_4ds_hd2skin vollständig
lesbar (gameinterface.4ds: 602 Frames = 577 Visual/Standard + 25 Dummy, 1 Byte Rest).

fmt_4ds.py bleibt unverändert. Zusätzlich: Welttransformationen der Frames (für HUD-Layout).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fmt_4ds  # noqa: E402
import fmt_4ds_hd2skin  # noqa: E402
from fmt_4ds import Reader  # noqa: E402

MTL_ALPHA_IN_DIFFUSE = 0x01000000   # HD2: Alpha steckt in der (TGA-)Diffuse-Textur


def read_material(r: Reader) -> dict:
    m = {"flags": r.u32()}
    m["ambient"] = r.vec(4)
    m["diffuse"] = r.vec(4)
    m["emission"] = r.vec(4)
    m["specular"] = r.vec(4)
    m["glossiness"] = r.f32()
    m["opacity"] = r.f32()
    f = m["flags"]
    if f & fmt_4ds.MTL_ENVMAP:
        m["env_ratio"] = r.f32()
        m["env_map"] = r.pstr()
    m["diffuse_map"] = r.pstr()
    if f & fmt_4ds.MTL_ALPHATEX and not f & MTL_ALPHA_IN_DIFFUSE and m["diffuse_map"]:
        m["alpha_map"] = r.pstr()
    if f & fmt_4ds.MTL_ANIM_DIFFUSE:
        m["anim"] = [r.u32(), r.u16(), r.u32(), r.u32(), r.u32()]
    return m


def read_header(d: bytes):
    r = Reader(d)
    assert r.raw(4) == b"4DS\0", "kein 4DS"
    ver = r.u16()
    r.raw(8)  # FILETIME
    n = r.u16()
    mats = [read_material(r) for _ in range(n)]
    return ver, mats, r


def read_model(d: bytes) -> dict:
    ver, mats, r = read_header(d)
    n = r.u16()
    frames = [fmt_4ds_hd2skin.read_frame_hd2(r, i) for i in range(n)]
    return {"version": ver, "materials": mats, "frames": frames, "frame_count": n,
            "end": r.p, "trailer": d[r.p:]}


# --- Transformationen ----------------------------------------------------------------------

def quat_to_mat(q, conjugate=False):
    """3x3-Rotationsmatrix (Spaltenvektor-Konvention) aus 4DS-Quaternion (x, y, z, w)."""
    x, y, z, w = q
    if conjugate:
        x, y, z = -x, -y, -z
    return [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]


def local_matrix(fr, conjugate=False):
    R = quat_to_mat(fr["rot"], conjugate)
    s = fr["scale"]
    M = [[R[i][j] * s[j] for j in range(3)] + [fr["pos"][i]] for i in range(3)]
    M.append([0.0, 0.0, 0.0, 1.0])
    return M


def matmul(A, B):
    return [[sum(A[i][k] * B[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


def xform(M, p):
    return [M[i][0] * p[0] + M[i][1] * p[1] + M[i][2] * p[2] + M[i][3] for i in range(3)]


def world_matrices(frames, conjugate=False):
    """Eltern-Index ist 1-basiert (0 = Wurzel)."""
    out = [None] * len(frames)
    for i, fr in enumerate(frames):
        L = local_matrix(fr, conjugate)
        p = fr["parent"]
        out[i] = matmul(out[p - 1], L) if p else L
    return out


if __name__ == "__main__":
    import sys
    d = open(sys.argv[1], "rb").read()
    m = read_model(d)
    print("Version", hex(m["version"]), "Materialien", len(m["materials"]), "Frames", len(m["frames"]),
          "Ende", hex(m["end"]), "/", hex(len(d)), "Rest", m["trailer"].hex())
