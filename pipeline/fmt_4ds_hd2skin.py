"""HD2-Ergänzung zu fmt_4ds: Singlemesh/Singlemorph (Charaktere) und Gelenk-Frames.

fmt_4ds.read_frame liest bei Visual-Typ 2/3 die Skin-Daten falsch (je LOD ein voller
Skin-Kopf; tatsächlich gibt es EINEN Kopf und je LOD nur das Vertex-Zuordnungsfeld)
und kann Singlemorph nicht. Dieses Modul liefert eine korrigierte read_model()-Variante;
fmt_4ds.py selbst bleibt unverändert (siehe docs/re_notes_5ds_skin.md).

Formate (rekonstruiert aus GE10.4ds / EN01.4ds, HD2 v0x29):

Skin (nach den LODs eines Singlemesh/Singlemorph-Visuals):
  u8   joint_count
  vec4 bbox_min, vec4 bbox_max              (Mesh-Raum)
  u8   blend_parent[joint_count]            (Gelenk, mit dem Vertices dieses Gelenks
                                             überblendet werden, i. d. R. Elternteil)
  joint_count * { f32 inv_bind[16]          (Zeilenvektor-Konvention, Translation in 12..14;
                                             entspricht 1:1 dem glTF-Spaltenlayout)
                  vec4 bmin, vec4 bmax }    (Gelenk-lokale Hülle, 1e16/-1e16 = leer)
  je LOD: u32 n ; n * { u8 joint ; u8 w }   (Vertex i, i < n; w/255 = Anteil von
                                             blend_parent[joint], Rest auf joint)
Morph (nur Singlemorph, nach dem Skin):
  u8 targets ; wenn > 0: u8 channels ; u8 unk ;
     je Kanal: u16 nv ; falls nv > 0: nv*targets*(vec3 pos, vec3 nrm) ; u8 has_links ;
               [u16 links[nv]]   (nv == 0: Kanal endet direkt nach nv)
     danach (nur bei targets > 0): vec4 min, vec4 max, vec3 center, f32 radius  (48 Byte)
Singlemesh (Visual 2, z. B. Hund "(pes", BL/BP/FL/FP): Skin wie oben, KEIN Morph, KEIN Trailer.
  (BL/BP/FL/FP haben n = 0 Vertex-Einträge -> alle Vertices starr am Mesh-Frame.)
Joint-Frame (Typ 10): Standard-Frame-Kopf + u32 joint_id
"""
import struct

import fmt_4ds
from fmt_4ds import Reader


def read_skin_hd2(r: Reader, nlods: int) -> dict:
    nj = r.u8()
    s = {"bbox_min": r.vec(4), "bbox_max": r.vec(4)}
    s["blend_parent"] = list(r.raw(nj))
    s["joints"] = []
    for _ in range(nj):
        s["joints"].append({"inv_bind": r.vec(16), "bmin": r.vec(4), "bmax": r.vec(4)})
    s["lod_weights"] = []
    for _ in range(nlods):
        n = r.u32()
        raw = r.raw(n * 2)
        s["lod_weights"].append([(raw[2 * i], raw[2 * i + 1]) for i in range(n)])
    return s


def read_morph_hd2(r: Reader) -> dict:
    m = {"targets": r.u8(), "channels": []}
    if m["targets"]:
        nch = r.u8()
        m["unk"] = r.u8()
        for _ in range(nch):
            nv = r.u16()
            ch = {"nv": nv, "data": b""}
            m["channels"].append(ch)
            if nv == 0:
                continue          # leerer Kanal: weder Daten noch Link-Flag (GE02a, Ge09b)
            ch["data"] = r.raw(nv * m["targets"] * 24)
            if r.u8():
                ch["links"] = list(struct.unpack_from("<%dH" % nv, r.d, r.p))
                r.p += nv * 2
        # Morph-Trailer (Hülle): nur wenn Morph-Ziele vorhanden (wie Mafia); Singlemesh hat keinen
        m["bounds"] = {"min": r.vec(4), "max": r.vec(4), "center": r.vec(3), "radius": r.f32()}
    return m


def read_frame_hd2(r: Reader, idx: int) -> dict:
    start = r.p
    t = r.d[r.p]
    if t == fmt_4ds.FRAME_VISUAL and r.d[r.p + 1] in (fmt_4ds.VIS_SINGLEMESH, fmt_4ds.VIS_SINGLEMORPH):
        fr = {"index": idx, "type": r.u8(), "visual": r.u8(), "render_flags": r.u16(), "parent": r.u16(),
              "pos": r.vec(3), "rot": r.vec(4), "scale": r.vec(3), "unk": r.u32(), "culling": r.u8()}
        fr["name"] = r.pstr()
        fr["params"] = r.pstr()
        fr["instance"] = r.u16()
        fr["lods"] = fmt_4ds.read_lods(r) if fr["instance"] == 0 else []
        fr["skin"] = read_skin_hd2(r, len(fr["lods"]))
        if fr["visual"] == fmt_4ds.VIS_SINGLEMORPH:
            fr["morph"] = read_morph_hd2(r)
        return fr
    if t == fmt_4ds.FRAME_TARGET:
        # Kopf wie üblich, dann u16 flags ; u8 n ; u16 links[n] (wie Mafia)
        fr = {"index": idx, "type": r.u8(), "parent": r.u16(), "pos": r.vec(3), "rot": r.vec(4),
              "scale": r.vec(3), "unk": r.u32(), "culling": r.u8()}
        fr["name"] = r.pstr()
        fr["params"] = r.pstr()
        fr["target_flags"] = r.u16()
        fr["links"] = [r.u16() for _ in range(r.u8())]
        return fr
    r.p = start
    return fmt_4ds.read_frame(r, idx)


def read_model(d: bytes) -> dict:
    ver, mats, r = fmt_4ds.read_header(d)
    n = r.u16()
    frames = []
    for i in range(n):
        frames.append(read_frame_hd2(r, i))
    rest = r.d[r.p:]
    return {"version": ver, "materials": mats, "frames": frames, "frame_count": n, "end": r.p, "trailer": rest}
