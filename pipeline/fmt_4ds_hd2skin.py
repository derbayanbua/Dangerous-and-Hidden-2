"""HD2-Ergänzung zu fmt_4ds: Singlemesh/Singlemorph (Charaktere) und Gelenk-Frames.

Ursprünglich eigene Leser, weil fmt_4ds die Skin-Daten falsch las und Singlemorph nicht
konnte. Seit der Rekonstruktion der Ladefunktionen aus LS3DF.dll (docs/re_notes_4ds_visuals.md)
liest fmt_4ds selbst alle Frame-/Visual-Typen; dieses Modul delegiert nur noch dorthin und
behält Schnittstelle und Feldnamen (skin/morph/target) für skinned_gltf.py und fmt_4ds_ui.py.

Formate (HD2 v0x29, Belege docs/re_notes_5ds_skin.md und docs/re_notes_4ds_visuals.md):

Skin (nach den LODs eines Singlemesh/Singlemorph-Visuals, LS3DF.dll FUN_10053900):
  u8   joint_count                          (0: Block endet hier)
  vec4 bbox_min, vec4 bbox_max              (Mesh-Raum)
  u8   blend_parent[joint_count]            (Gelenk, mit dem Vertices dieses Gelenks
                                             überblendet werden, i. d. R. Elternteil)
  joint_count * { f32 inv_bind[16]          (Zeilenvektor-Konvention, Translation in 12..14;
                                             entspricht 1:1 dem glTF-Spaltenlayout)
                  vec4 bmin, vec4 bmax }    (Gelenk-lokale Hülle, 1e16/-1e16 = leer)
  je LOD: u32 n ; n * { u8 joint ; u8 w }   (Vertex i, i < n; w/255 = Anteil von
                                             blend_parent[joint], Rest auf joint)
Morph (Singlemorph nach dem Skin, Morph-Visual nach dem Mesh; FUN_10035490):
  u8 targets ; wenn > 0: u8 channels ; u8 unk ;
     je Kanal: u16 nv ; falls nv > 0: nv*targets*(vec3 pos, vec3 nrm) ; u8 has_links ;
               [u16 links[nv]]   (nv == 0: Kanal endet direkt nach nv)
     danach (nur bei targets > 0): vec4 min, vec4 max, vec3 center, f32 radius  (48 Byte)
Joint-Frame (Typ 10): Standard-Frame-Kopf + u32 joint_id
Target-Frame (Typ 7): Standard-Frame-Kopf + u16 flags ; u8 n ; u16 links[n]
"""
import fmt_4ds
from fmt_4ds import Reader

read_skin_hd2 = fmt_4ds.read_skin
read_morph_hd2 = fmt_4ds.read_morph


def read_frame_hd2(r: Reader, idx: int, lod_counts=None) -> dict:
    fr = fmt_4ds.read_frame(r, idx, lod_counts)
    if fr["type"] == fmt_4ds.FRAME_VISUAL and fr.get("visual") in (fmt_4ds.VIS_SINGLEMESH, fmt_4ds.VIS_SINGLEMORPH):
        fr.setdefault("lods", [])
    return fr


def read_model(d: bytes) -> dict:
    ver, mats, r = fmt_4ds.read_header(d)
    n = r.u16()
    frames = []
    lod_counts = {}
    for i in range(n):
        frames.append(read_frame_hd2(r, i, lod_counts))
    rest = r.d[r.p:]
    return {"version": ver, "materials": mats, "frames": frames, "frame_count": n, "end": r.p, "trailer": rest}
