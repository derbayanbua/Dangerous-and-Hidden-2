"""HD2-Charaktere (4DS Singlemesh/Singlemorph + 5DS-Animationen) -> GLB mit Skin + Animationen.

Nur zur Konvertierung der Original-Assets des Nutzers in einen lokalen Cache
(orig_cache/ bzw. re_work/), nicht zur Weitergabe.

Nutzung:
    from skinned_gltf import export_character
    export_character(open("GE10.4ds","rb").read(), {"idle": open("!stani01.5DS","rb").read()},
                     convert_mission.Textures(tex_dir), "textures/", "ge10.glb")

Kommandozeile (liest direkt aus HD2_orig, schreibt nach Zielordner):
    python -I tools/skinned_gltf.py <modell> <zielordner> [name=anim5ds ...]

Aufbau des glTF:
  Wurzelknoten <modell> -> alle 4DS-Frames als Knoten (gleiche Hierarchie, Namen wie im 4DS).
  Gelenke des Skins: [Mesh-Frame "a" (Becken/Wurzel)] + Joint-Frames nach joint_id.
  Der Skin-Mesh hängt an einem eigenen Knoten "<name>_skin" (Kind der Wurzel), Vertices
  im lokalen Raum des Mesh-Frames. Starre Teilmeshes (Augen, Kopfteile) hängen als
  Kinder an ihren Gelenk-Knoten.
  Animationen: je 5DS eine glTF-Animation; Kanäle für Frames, die im Modell existieren.
"""
import math
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import convert_mission as cm  # noqa: E402  (glTF-Schreiber, Texturen, Koordinaten)
import fmt_4ds  # noqa: E402
import fmt_4ds_hd2skin  # noqa: E402
import fmt_5ds  # noqa: E402

FPS = 25.0   # Annahme: LS3D-Animationsrate (wie Mafia); siehe Notizen


def qconv(q):
    """LS3D-Quaternion (x, y, z, w) aus 4DS-Frames UND 5DS-Spuren -> glTF (x, y, z, w).

    LS3D-Quaternionen beschreiben mit der üblichen (Hamilton-/Spaltenvektor-)Formel die
    INVERSE Rotation (Zeilenvektor-Nutzung derselben Matrix). Belege: gespeicherte
    Inverse-Bind-Matrizen von "(pes"/BL stimmen nur mit konjugierten Frame-Rotationen
    (Fehler 0.0 statt 1.95); 5DS-Ruhepose des Hundes == 4DS-Ruhelage (gleiche Konvention);
    Anatomie-Test (Arme hängen, Knie knicken nach hinten) nur mit Konjugation.
    Konjugieren (-x,-y,-z,w) und z-Spiegelung (-x,-y,z,w) ergeben zusammen (x, y, -z, w).
    HINWEIS: convert_mission.crot_xyzw liefert (-x,-y,z,w), d. h. die inverse Rotation.
    """
    return [q[0], q[1], -q[2], q[3]]


# --- kleine Matrix-Helfer (Spaltenvektoren, m[r][c]) --------------------------

def mat_trs(t, q, s):
    x, y, z, w = q
    r = [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
         [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
         [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]
    m = [[r[i][j] * s[j] for j in range(3)] + [t[i]] for i in range(3)]
    m.append([0.0, 0.0, 0.0, 1.0])
    return m


def mat_mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


def mat_inv_affine(m):
    """Inverse einer affinen 4x4-Matrix (allgemein über 3x3-Inverse)."""
    a = [row[:3] for row in m[:3]]
    det = (a[0][0] * (a[1][1] * a[2][2] - a[1][2] * a[2][1]) - a[0][1] * (a[1][0] * a[2][2] - a[1][2] * a[2][0])
           + a[0][2] * (a[1][0] * a[2][1] - a[1][1] * a[2][0]))
    inv = [[(a[(j + 1) % 3][(i + 1) % 3] * a[(j + 2) % 3][(i + 2) % 3] - a[(j + 1) % 3][(i + 2) % 3] * a[(j + 2) % 3][(i + 1) % 3]) / det
            for j in range(3)] for i in range(3)]
    t = [m[i][3] for i in range(3)]
    it = [-sum(inv[i][k] * t[k] for k in range(3)) for i in range(3)]
    return [inv[i] + [it[i]] for i in range(3)] + [[0.0, 0.0, 0.0, 1.0]]


def gltf_col_major(m):
    return [m[r][c] for c in range(4) for r in range(4)]


def ls3d_mat_to_gltf(v16):
    """4DS-Matrix (Zeilenvektor-Konvention, Translation in 12..14) -> glTF-Spaltenmatrix
    (als m[r][c]) inkl. z-Spiegelung S*M*S."""
    m = [[v16[c * 4 + r] for c in range(4)] for r in range(4)]   # transponieren -> Spaltenvektoren
    s = [1, 1, -1, 1]
    return [[m[r][c] * s[r] * s[c] for c in range(4)] for r in range(4)]


# --- Export -------------------------------------------------------------------

def _frame_name(fr):
    return fr["name"] or ("frame%d" % fr["index"])


def _skin_primitives(g, lod, mat_ids, joints4, weights4):
    verts = lod["vertices"]
    n = len(verts)
    pos = bytearray(); nrm = bytearray(); uv = bytearray(); jb = bytearray(); wb = bytearray()
    mn = [1e30] * 3; mx = [-1e30] * 3
    for i, v in enumerate(verts):
        p = (v[0], v[1], -v[2])
        pos += struct.pack("<3f", *p)
        nl = math.sqrt(v[3] ** 2 + v[4] ** 2 + v[5] ** 2) or 1.0
        nrm += struct.pack("<3f", v[3] / nl, v[4] / nl, -v[5] / nl)
        uv += struct.pack("<2f", v[6], v[7])
        jb += struct.pack("<4H", *joints4[i])
        wb += struct.pack("<4f", *weights4[i])
        for k in range(3):
            mn[k] = min(mn[k], p[k]); mx[k] = max(mx[k], p[k])
    pa = g._acc(g._view(bytes(pos), 34962), 5126, n, "VEC3", mn, mx)
    na = g._acc(g._view(bytes(nrm), 34962), 5126, n, "VEC3")
    ua = g._acc(g._view(bytes(uv), 34962), 5126, n, "VEC2")
    ja = g._acc(g._view(bytes(jb), 34962), 5123, n, "VEC4")
    wa = g._acc(g._view(bytes(wb), 34962), 5126, n, "VEC4")
    prims = []
    for grp in lod["groups"]:
        fc = grp["faces"]
        if not fc:
            continue
        idx = bytearray()
        for i in range(0, len(fc), 3):
            idx += struct.pack("<3H", fc[i], fc[i + 2], fc[i + 1])   # Umlaufsinn umdrehen
        ia = g._acc(g._view(bytes(idx), 34963), 5123, len(fc), "SCALAR")
        prim = {"attributes": {"POSITION": pa, "NORMAL": na, "TEXCOORD_0": ua, "JOINTS_0": ja, "WEIGHTS_0": wa},
                "indices": ia}
        mid = grp["material"] - 1
        if 0 <= mid < len(mat_ids):
            prim["material"] = mat_ids[mid]
        prims.append(prim)
    return prims


def _vertex_weights(skin, nverts, lod_index=0):
    """-> (joints4, weights4) mit Skin-Gelenkindizes (0 = Mesh-Frame, jid+1 = Joint-Frame)."""
    W = skin["lod_weights"][lod_index]
    bp = skin["blend_parent"]
    joints4, weights4 = [], []
    for i in range(nverts):
        if i < len(W):
            b, w = W[i]
            partner = bp[b - 1] if b > 0 else 0
            wp = w / 255.0
            if partner == b or wp == 0.0:
                joints4.append((b, 0, 0, 0)); weights4.append((1.0, 0.0, 0.0, 0.0))
            else:
                joints4.append((b, partner, 0, 0)); weights4.append((1.0 - wp, wp, 0.0, 0.0))
        else:
            joints4.append((0, 0, 0, 0)); weights4.append((1.0, 0.0, 0.0, 0.0))   # ohne Eintrag: starr am Mesh-Frame
    return joints4, weights4


def export_character(model_4ds_bytes, anims, textures, tex_rel, out_path, name=None, fps=FPS, report=None,
                     channel_filter=None, model=None):
    """4DS-Charakter + {name: 5DS-Bytes} -> GLB. Gibt ein Info-dict zurück.
    channel_filter(anim_name, frame_name) -> False lässt die Spur weg (z. B. Oberkörper-Haltungen ohne Becken/Beine).
    model: bereits gelesenes (ggf. zusammengesetztes) Modell statt model_4ds_bytes (FPV-Hände + Waffe)."""
    model = model or fmt_4ds_hd2skin.read_model(model_4ds_bytes)
    name = name or os.path.splitext(os.path.basename(out_path))[0]
    g = cm.Gltf(tex_rel)
    g.j["asset"]["generator"] = "DH2 skinned_gltf"
    mat_ids = []
    for m in model["materials"]:
        tex = textures.get(m.get("diffuse_map"), m.get("alpha_map") if m["flags"] & fmt_4ds.MTL_ALPHATEX else None,
                           bool(m["flags"] & fmt_4ds.MTL_COLORKEY)) if textures else None
        mat_ids.append(g.material(m, tex))
    frames = model["frames"]
    root = g.node({"name": name, "children": []})
    g.j["scenes"][0]["nodes"].append(root)
    node_of = {}
    for fr in frames:
        node = {"name": _frame_name(fr), "translation": cm.cpos(fr["pos"]), "rotation": qconv(fr["rot"]),
                "scale": list(fr["scale"]), "extras": {"type": fr["type"]}}
        if fr.get("joint_id") is not None:
            node["extras"]["joint_id"] = fr["joint_id"]
        if fr["type"] == fmt_4ds.FRAME_VISUAL and fr.get("visual") == fmt_4ds.VIS_STANDARD and fr.get("lods"):
            mi = g.mesh(node["name"], fr["lods"][0], mat_ids)
            if mi is not None:
                node["mesh"] = mi
        node_of[fr["index"] + 1] = g.node(node)
    for fr in frames:
        ni = node_of[fr["index"] + 1]
        par = fr["parent"]
        if par and par in node_of and par != fr["index"] + 1:
            g.j["nodes"][node_of[par]].setdefault("children", []).append(ni)
        else:
            g.j["nodes"][root]["children"].append(ni)

    # lokale Ruhelagen (glTF-Raum) für Kontrollrechnung
    local = {fr["index"] + 1: mat_trs(cm.cpos(fr["pos"]), qconv(fr["rot"]), fr["scale"]) for fr in frames}
    parent = {fr["index"] + 1: fr["parent"] for fr in frames}

    def rel_to(idx, anc):
        m = [[1.0 if i == j else 0.0 for j in range(4)] for i in range(4)]
        while idx and idx != anc:
            m = mat_mul(local[idx], m)
            idx = parent[idx]
        assert idx == anc, "Gelenk liegt nicht unter dem Mesh-Frame"
        return m

    info = {"skins": [], "animations": {}}
    for fr in frames:
        if "skin" not in fr or not fr.get("lods"):
            continue
        skin = fr["skin"]
        mesh_idx = fr["index"] + 1
        jframes = {f["joint_id"]: f["index"] + 1 for f in frames if f["type"] == fmt_4ds.FRAME_JOINT}
        nj = len(skin["joints"])
        joint_nodes = [node_of[mesh_idx]] + [node_of[jframes[j]] for j in range(nj)]
        ibm = [[[1.0 if i == j else 0.0 for j in range(4)] for i in range(4)]]
        max_err = 0.0
        for j in range(nj):
            stored = ls3d_mat_to_gltf(skin["joints"][j]["inv_bind"])
            computed = mat_inv_affine(rel_to(jframes[j], mesh_idx))
            max_err = max(max_err, max(abs(stored[r][c] - computed[r][c]) for r in range(4) for c in range(4)))
            ibm.append(stored)
        ibm_bytes = b"".join(struct.pack("<16f", *gltf_col_major(m)) for m in ibm)
        ibm_acc = g._acc(g._view(ibm_bytes), 5126, len(ibm), "MAT4")
        g.j.setdefault("skins", []).append({"name": _frame_name(fr) + "_skin", "joints": joint_nodes,
                                            "inverseBindMatrices": ibm_acc, "skeleton": node_of[mesh_idx]})
        lod = fr["lods"][0]
        j4, w4 = _vertex_weights(skin, len(lod["vertices"]))
        prims = _skin_primitives(g, lod, mat_ids, j4, w4)
        g.j["meshes"].append({"name": _frame_name(fr), "primitives": prims})
        sk_node = g.node({"name": name + "_" + _frame_name(fr) + "_skin", "mesh": len(g.j["meshes"]) - 1,
                          "skin": len(g.j["skins"]) - 1})
        g.j["nodes"][root]["children"].append(sk_node)
        info["skins"].append({"frame": _frame_name(fr), "joints": len(joint_nodes), "verts": len(lod["vertices"]),
                              "weighted": len(skin["lod_weights"][0]), "ibm_max_err": max_err})

    # Animationen
    by_name = {}
    for fr in frames:
        by_name.setdefault(_frame_name(fr).lower(), node_of[fr["index"] + 1])
    for aname, data in anims.items():
        a = fmt_5ds.parse(data)
        samplers, channels, skipped = [], [], []
        tmax = 0.0

        def add(node, path, frames_, vals, conv, typ):
            nonlocal tmax
            times = [f / fps for f in frames_]
            tmax = max(tmax, times[-1])
            tb = struct.pack("<%df" % len(times), *times)
            ta = g._acc(g._view(tb), 5126, len(times), "SCALAR", [min(times)], [max(times)])
            vb = b"".join(struct.pack("<%df" % len(conv(v)), *conv(v)) for v in vals)
            va = g._acc(g._view(vb), 5126, len(vals), typ)
            samplers.append({"input": ta, "output": va, "interpolation": "LINEAR"})
            channels.append({"sampler": len(samplers) - 1, "target": {"node": node, "path": path}})

        def qnorm(q):
            q = qconv(q)
            l = math.sqrt(sum(x * x for x in q)) or 1.0
            return [x / l for x in q]

        for o in a["objects"]:
            node = by_name.get(o["name"].lower())
            if node is not None and channel_filter is not None and not channel_filter(aname, o["name"]):
                continue
            if node is None:
                skipped.append(o["name"])
                continue
            if o.get("rot"):
                rv = [qnorm(q) for q in o["rot"]]
                for k in range(1, len(rv)):   # Vorzeichenstetigkeit für Interpolation
                    if sum(x * y for x, y in zip(rv[k - 1], rv[k])) < 0:
                        rv[k] = [-x for x in rv[k]]
                add(node, "rotation", o["rot_frames"], rv, lambda q: q, "VEC4")
            if o.get("pos"):
                add(node, "translation", o["pos_frames"], o["pos"], cm.cpos, "VEC3")
            if o.get("scale"):
                add(node, "scale", o["scale_frames"], o["scale"], list, "VEC3")
        if channels:
            g.j.setdefault("animations", []).append({"name": aname, "samplers": samplers, "channels": channels})
        info["animations"][aname] = {"channels": len(channels), "length_s": tmax, "last_frame": a["last_frame"],
                                     "skipped": skipped}
    g.save(out_path)
    return info


# --- Kommandozeile ------------------------------------------------------------

def _read_model_file(path):
    return cm.read_file(path, ["MODELS.DTA"])


if __name__ == "__main__":
    import json
    mdl, out_dir = sys.argv[1], sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)
    anims = {}
    for arg in sys.argv[3:]:
        k, v = arg.split("=", 1)
        d = _read_model_file("models/%s.5ds" % v)
        if d is None:
            print("Animation fehlt:", v)
            continue
        anims[k] = d
    data = _read_model_file("models/%s.4ds" % mdl)
    tex = cm.Textures(os.path.join(out_dir, "textures"))
    out = os.path.join(out_dir, mdl.lower() + ".glb")
    info = export_character(data, anims, tex, "textures/", out)
    print(out)
    print(json.dumps(info, indent=1))
    if tex.missing:
        print("fehlende Texturen:", sorted(tex.missing))
