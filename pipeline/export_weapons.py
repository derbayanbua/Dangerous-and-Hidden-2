"""Original-Waffenmodelle (Weltmodelle + FPV-Modelle aus TABLES\\items.sav) in den lokalen Cache konvertieren.

Aufruf (venv):  pyenv\\Scripts\\python.exe -I export_weapons.py
  -> orig_cache/weapons/<modell>.glb      Weltmodelle (Texturen: orig_cache/textures, geteilt)
  -> orig_cache/weapons/fpv/<fpv>.glb      1.-Person-Modell: FPV-Hände (FPV_hands.4ds, Skin) + FPV-Waffe
                                           (w_*FPV.4ds) + Animationen aus TABLES\\FpvAnims.sav
  -> orig_cache/weapons/overlays/*.png     Zielfernrohr-/Fernglas-Overlays aus MODELS\\gameinterface.4ds
  -> orig_cache/weapons/weapons.json       Gegenstand -> Modell, Haltesatz, Zoom (items.sav Verhalten 5),
                                           FPV-Aktionen, Clip-Längen, Auslösezeitpunkte (Wurf)
Voraussetzung: orig_cache/items.json (fmt_actors_items.py) für die Zuordnung Gegenstand -> Modell
(items.sav Basis-Datensatz: +0x28 Weltmodell, +0x00 FPV-Modell; docs/re_notes_actors_items.md).

Befestigung in der Hand (hd2.exe 0x7B9260, docs/re_notes_weapons.md): Waffe als Kind des Dummys hw1
(rechte Hand), Rotation SetDir((1,0,0), 0) im hw1-Raum, Position so, dass der Waffen-Dummy RW auf hw1 liegt.
Haltungen: TABLES\\anim.sav, Waffensätze (0x2220 Byte je Satz ab 0xB6F4) -> HOLD_SETS unten.
FPV (hd2.exe C_FirstPersonView 0x490C80/0x4922A0/0x492A90, docs/re_notes_weapons.md §6): Hände + Waffe hängen
als Kinder eines Modell-Frames im Kameraraum (Lage 0, Richtung +z); FpvAnims.sav: je Waffentyp (= Gegenstands-
nummer) 13 Aktionen × bis zu 4 Varianten (Name + Zufallsanteil).
"""
import json
import math
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import convert_mission as cm  # noqa: E402
import fmt_4ds  # noqa: E402
import fmt_4ds_hd2skin  # noqa: E402
import fmt_5ds  # noqa: E402
import skinned_gltf  # noqa: E402

FPS = skinned_gltf.FPS

# Haltesätze aus TABLES\anim.sav (je Satz, Einträge zu 32 Byte; Gruppen zu je 3 = Stehen/Hocken/Liegen):
#   +0x40 Ruhe, +0x100 Anschlag, +0x1C0 Wegstecken (sch*), +0x220 Ziehen (vyt*), +0x3A0 Feuer (puf*),
#   +0x1240 Granatwurf mit Waffe (hod*: v = Ganzkörper, vP = nur Oberkörper/in Bewegung),
#   +0x1300 Nachladen (3 Varianten × 3 Haltungen: +0x1300/+0x1360/+0x13C0).
# Satzzuordnung über den Inhalt [P]: 0 Hand (Granate/Messer), 1 MP (preSA = samopal), 2 Pistole (REV),
# 3 Gewehr (PU = puška), 4 MG, 5 Panzerbüchse.
HOLD_SETS = {
    "hand":    {"calm": ["!drzgran1", "!drzgran1", "!drzgran1"], "aim": ["!drzgran1", "!drzgran1", "!drzgran1"],
                "draw": ["!vytITEMs1", "!vytITEMk1", "!vytITEMl3"], "holster": ["!vytITEMs1", "!vytITEMk1", "!vytITEMl3"],
                "throw": ["!hodHSTv", "!hodHDRv1", "!hodHLEv"], "throw_move": ["!hodHSTvP", "!hodHDRvP", "!hodHLEv"]},
    "smg":     {"calm": ["!klidMG", "(pzbks", "!sLE1b6"], "aim": ["!!zbp04a", "!!zbpSKL", "!puLE1a1"],
                "holster": ["!submSTs", "!submDRs", "!schSUBMleh5"], "draw": ["!submSTvN", "!submDRvR", "!vytSUBMleh5"],
                "fire": ["!pohotMG", "!_pufSKL", "!pufLE"],
                "reload": [["(preSAs66", "(preSAd66", "(preSAl66"], ["(preTSAs66", "(preTSAd66", "(preSAl66"]],
                "throw": ["!hodHSTv", "!hodHDRv1", "!hodHLEv"], "throw_move": ["!hodHSTvP", "!hodHDRvP", "!hodHLEv"]},
    "pistol":  {"calm": ["(kliddrz21", "(kliddrz21", "(kliddrz_1"], "aim": ["!drzREVst", "!drzREVst", "(revleh16"],
                "holster": ["!revSST3", "(schorevkle2", "!schREVleh"], "draw": ["!revVST3", "(tasrevklek5", "!vytREVleh"],
                "fire": ["!pufPst", "!pufPst", "!pufPst"],
                "reload": [["(preREst2", "(preREdre5", "(preREle6"]],
                "throw": ["!hodHSTv", "!hodHDRv1", "!hodHLEv"], "throw_move": ["!hodHSTvP", "!hodHDRvP", "!hodHLEv"]},
    "rifle":   {"calm": ["(pzbp", "(pzbkp", "!puLE1b5"], "aim": ["!!zbp04a", "!!zbpKL", "!puLE1a1"],
                "holster": ["!rifleSTs", "!rifleDRs", "!schoPUleh1"], "draw": ["!rifleSTvN", "!rifleDRv", "!vytPUleh5"],
                "fire": ["!_puf", "!_pufKL", "!pufLE"],
                "reload": [["(reloadpuI66", "(relpudre", "(reloadpu66"], ["(prePUs80", "(prePUd80", "(prePUl80"],
                           ["(prePUs118", "(prePUd118", "(prePUl118"]],
                "throw": ["!hodHSTv", "!hodHDRv1", "!hodHLEv"], "throw_move": ["!hodHSTvP", "!hodHDRvP", "!hodHLEv"]},
    "mg":      {"calm": ["!klidMG", "(pzbkp", "!sLE1b6"], "aim": ["!pohotMG", "!!zbpKL", "!puLE1a1"],
                "holster": ["!submSTs", "!submDRs", "!schSUBMleh5"], "draw": ["!submSTvN", "!submDRvR", "!vytSUBMleh5"],
                "fire": ["!pohotMG", "!_pufKL", "!pufLE"],
                "reload": [["(preSAs66", "(preSAd66", "(preSAl66"], ["(preTSAs66", "(preTSAd66", "(preSAl66"]],
                "throw": ["!hodHSTv", "!hodHDRv1", "!hodHLEv"], "throw_move": ["!hodHSTvP", "!hodHDRvP", "!hodHLEv"]},
    "bazooka": {"calm": ["!bazKLIDst", "!bazKLIDdr", "!drzBAZle"], "aim": ["!bazPOHst", "!bazPOHdr", "!drzBAZle"],
                "holster": ["!schBAZst1", "!schBAZdr1", "!schBAZleh"], "draw": ["!vytBAZst1", "!vytBAZdr1", "!vytBAZleh"],
                "fire": ["!bazPOHst", "!bazPOHst", "!bazPOHst"],
                "reload": [["!bazRELst", "!bazRELdr1", "!bazRELle"]],
                "throw": ["!hodHSTv", "!hodHDRv1", "!hodHLEv"], "throw_move": ["!hodHSTvP", "!hodHDRvP", "!hodHLEv"]},
}
# Schusswaffen-Animationsklasse (items.sav Verhaltensblock 4, dw6) -> Haltesatz
ANIM_CLASS_SET = {11: "smg", 12: "rifle", 13: "pistol", 65: "mg"}
# FpvAnims.sav: Aktionsnummern 0..12 (Chunk 2000+n); 11/12 = Zoom ein/aus (hd2.exe 0x492130: PlayAnim(0xB/0xC))
FPV_ACTIONS = ["idle", "idle_last", "shot", "shot_last", "aimshot", "aimshot_last", "reload", "jammed", "arm",
               "disarm", "disarm_last", "aim", "daim"]
FPV_HANDS = "FPV_hands"
# Vorgabe Auftraggeber: Panzerfaust (Typ 38, im Original ohne Nachladen) improvisiert mit dem Bazooka-Nachladen
FPV_OVERRIDES = {38: {"reload": [("#FPVBazReload", 100)]}}
# items.sav Verhalten 5: [0, 4, Overlay, FOV (rad)]; Overlay 0 arisaka, 1 k98, 2 springfield, 3 lee_enfield
# (hd2.exe 0x4A8C10/0x4A8CC0), 4 = Fernglas-Maske "scope", 5 = ohne (Kimme/Korn)
SCOPE_FRAMES = {0: ["sniper", "cross3"], 1: ["sniper", "cross4"], 2: ["sniper", "cross2"], 3: ["sniper", "cross1"],
                4: ["scope", "Object02"]}


def clip_name(anim_5ds):
    """5DS-Name -> Animationsname im Figuren-glb (nur Buchstaben/Ziffern, Präfix h_)."""
    return "h_" + "".join(c for c in anim_5ds if c.isalnum())


def _set_lists(s):
    """Alle 5DS-Listen eines Haltesatzes (Nachladen hat Varianten -> verschachtelt)."""
    for k, v in s.items():
        if k == "reload":
            for var in v:
                yield var
        else:
            yield v


def hold_anims():
    """{Clipname: 5DS-Name} aller Haltungs-/Aktionsclips (für export_characters.py)."""
    out = {}
    for s in HOLD_SETS.values():
        for lst in _set_lists(s):
            for a in lst:
                n = clip_name(a)
                assert out.get(n, a) == a, "Clipname doppelt: %s" % n
                out[n] = a
    return out


def item_set(it):
    beh = it.get("behaviours", [])
    codes = [b.get("code") for b in beh]
    for b in beh:
        if b.get("code") == 4 and b.get("anim_class") in ANIM_CLASS_SET:
            return ANIM_CLASS_SET[b["anim_class"]]
    if 3 in codes and float(it.get("weight_kg", 0)) > 2.0:
        return "bazooka"            # Panzerfaust/Bazooka/Panzerschreck (Werfer, Code 3)
    return "hand"                   # Messer, Granaten, Sprengsätze


def item_zoom(it):
    """items.sav Verhalten 5 -> {"scope": Overlay-Typ, "fov_deg": Zoom-FOV (Grad, wie im Original)} oder None."""
    for b in it.get("behaviours", []):
        if b.get("code") == 5 and len(b.get("raw_u32", [])) >= 4:
            r = b["raw_u32"]
            fov = struct.unpack("<f", struct.pack("<I", r[3] & 0xFFFFFFFF))[0]
            return {"scope": int(r[2]), "fov_deg": round(math.degrees(fov), 3)}
    return None


def _read5(name):
    return cm.read_file("models/%s.5ds" % name, ["patch.dta", "MODELS.DTA"])


def anim_length(name):
    d = _read5(name)
    return fmt_5ds.parse(d)["last_frame"] / FPS if d else 0.0


def reload_variant(it, set_name):
    """Nachlade-Variante (Index in HOLD_SETS[set]["reload"]) [P]: Thompson (items.sav +0x78 = 52) nutzt die
    zweite MP-Reihe (preTSA*), sonst die Variante, deren Länge der Original-Nachladezeit am nächsten liegt."""
    vs = HOLD_SETS.get(set_name, {}).get("reload", [])
    if len(vs) <= 1:
        return 0
    if set_name in ("smg", "mg"):
        return 1 if int(it.get("u78", 0)) == 52 else 0
    rel = 0.0
    for b in it.get("behaviours", []):
        if b.get("code") == 4:
            rel = float(b.get("reload_ms", 0.0)) / 1000.0
    lens = [anim_length(v[0]) for v in vs]
    return min(range(len(vs)), key=lambda i: abs(lens[i] - rel))


# --- Vorwärtskinematik für den Auslösezeitpunkt beim Wurf -------------------------------------------

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


def release_time(model, anim_bytes, frame_name, highest=False):
    """Zeitpunkt (s) des Loslassens [P]: größte Geschwindigkeit des Frames frame_name (Hand der Figur) bzw.
    highest=True: höchster Punkt (FPV-Granate; danach springt sie in die Ausgangslage zurück)."""
    a = fmt_5ds.parse(anim_bytes)
    tracks = {o["name"].lower(): o for o in a["objects"]}
    frames = model["frames"]
    byname = {f["name"].lower(): f for f in frames if f["name"]}
    chain = []
    f = byname.get(frame_name.lower())
    while f is not None:
        chain.append(f)
        f = frames[f["parent"] - 1] if f["parent"] else None
    if not chain:
        return 0.0
    last = a["last_frame"]
    pts = []
    for k in range(0, last + 1):
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
        pts.append((m[0][3], m[1][3], m[2][3]))
    if highest:
        return round(max(range(len(pts)), key=lambda k: pts[k][1]) / FPS, 3)
    best, best_v = 0, -1.0
    for k in range(1, len(pts)):
        v = math.dist(pts[k], pts[k - 1])
        if v > best_v:
            best, best_v = k, v
    return round(best / FPS, 3)


# --- FPV -------------------------------------------------------------------------------------------

def read_fpv_table():
    """TABLES\\FpvAnims.sav -> {Typ (= Gegenstandsnummer): [Aktion 0..12: [(5DS-Name, Anteil), ...]]}."""
    d = cm.read_file("tables/FpvAnims.sav", ["patch.dta", "others.DTA"])

    def chunks(b):
        o = 0
        while o + 6 <= len(b):
            cid, sz = struct.unpack_from("<HI", b, o)
            if sz < 6:
                break
            yield cid, b[o + 6:o + sz]
            o += sz
    out = {}
    for _cid, body in chunks(d):            # 0x3039
        for tid, tb in chunks(body):        # 100 + Typ
            acts = []
            for _aid, ab in chunks(tb):     # 2000 + Aktion
                vs = []
                for _vid, vb in chunks(ab):  # 3000 + Variante
                    for sid, sb in chunks(vb):
                        if sid == 1000:
                            nm = sb.split(b"\0")[0].decode("latin1")
                            rest = vb[6 + len(sb):]
                            ratio = struct.unpack("<i", rest[:4])[0] if len(rest) >= 4 else 100
                            vs.append((os.path.splitext(nm)[0], ratio))
                acts.append(vs)
            out[tid - 100] = acts
    return out


def merge_models(hands, weapon):
    """FPV-Hände (Skin) + FPV-Waffe zu einem Modell (Frames hintereinander, Eltern/Materialien umnummeriert)."""
    nf, nm = len(hands["frames"]), len(hands["materials"])
    frames = list(hands["frames"])
    for f in weapon["frames"]:
        g = dict(f)
        g["index"] = f["index"] + nf
        g["parent"] = f["parent"] + nf if f["parent"] else 0
        if f.get("lods"):
            lods = []
            for lod in f["lods"]:
                l2 = dict(lod)
                l2["groups"] = [dict(gr, material=(gr["material"] + nm if gr["material"] else 0)) for gr in lod["groups"]]
                lods.append(l2)
            g["lods"] = lods
        frames.append(g)
    return {"version": hands.get("version"), "materials": hands["materials"] + weapon["materials"], "frames": frames}


def export_fpv(items, tex, out_dir):
    table = read_fpv_table()
    hands_d = cm.read_file("models/%s.4ds" % FPV_HANDS, ["patch.dta", "MODELS.DTA"])
    hands = fmt_4ds_hd2skin.read_model(hands_d)
    os.makedirs(os.path.join(out_dir, "fpv"), exist_ok=True)
    result, failed = {}, []
    for it in items:
        fpv = (it.get("fpv_model") or "").strip()
        acts = table.get(int(it["id"]))
        if not fpv or not acts or not any(acts):
            continue
        key = fpv.lower()
        if key in result:
            result[key]["items"].append(it["id"])
            continue
        wd = cm.read_file("models/%s.4ds" % fpv, ["patch.dta", "MODELS.DTA"])
        if wd is None:
            failed.append((it["id"], fpv, "fehlt"))
            continue
        try:
            weapon = fmt_4ds_hd2skin.read_model(wd)
        except Exception as e:  # einzelne Modelle dürfen scheitern
            failed.append((it["id"], fpv, repr(e)[:80]))
            continue
        model = merge_models(hands, weapon)
        anims, actions, lengths = {}, {}, {}
        acts = [list(v) for v in acts[:len(FPV_ACTIONS)]]
        for an, vs in FPV_OVERRIDES.get(int(it["id"]), {}).items():
            acts[FPV_ACTIONS.index(an)] = list(vs)
        for i, vs in enumerate(acts):
            lst = []
            for nm, ratio in vs:
                cn = "".join(c for c in nm if c.isalnum())
                if cn not in anims:
                    d = _read5(nm)
                    if d is None:
                        continue
                    anims[cn] = d
                    lengths[cn] = round(fmt_5ds.parse(d)["last_frame"] / FPS, 3)
                lst.append([cn, ratio])
            if lst:
                actions[FPV_ACTIONS[i]] = lst
        try:
            skinned_gltf.export_character(b"", anims, tex, "../../textures/", os.path.join(out_dir, "fpv", key + ".glb"),
                                          name="fpv", model=model)
        except Exception as e:
            failed.append((it["id"], fpv, repr(e)[:100]))
            continue
        entry = {"items": [it["id"]], "actions": actions, "lengths": lengths,
                 "frames": sorted(f["name"] for f in weapon["frames"] if f["name"])}
        shot = (actions.get("shot") or [[None]])[0][0]
        if item_set(it) == "hand" and shot and shot in anims:
            entry["release"] = release_time(model, anims[shot], "fpv_weapon", highest=True)   # Granate verlässt die Hand
        result[key] = entry
    return result, failed


def export_fpv_hands(items_all, tex, out_dir):
    """Ego-Hände je Uniform (hd2.exe 0x4922A0): FPV-Modell = items.sav +0x00 des getragenen Uniform-Gegenstands
    („w_default“ -> FPV_hands). Exportiert jede vorkommende Hände-Variante als fpv/hands_<name>.glb (nur Skin, ohne
    Animationen; das Spiel tauscht damit das Haut-Mesh im FPV-Modell) und liefert {Figurenmodell: Variante}."""
    variants, mapping = set(), {}
    for it in items_all:
        fpv = (it.get("fpv_model") or "").strip()
        model = (it.get("model") or "").strip().lower()
        if it.get("kind") != "equipment" or not model or not fpv.lower().startswith("fpv_hands"):
            continue
        key = fpv.lower().rsplit(".", 1)[0]
        mapping[model] = key
        variants.add(fpv.rsplit(".", 1)[0])
    variants.add(FPV_HANDS)
    os.makedirs(os.path.join(out_dir, "fpv"), exist_ok=True)
    done = []
    for v in sorted(variants):
        d = cm.read_file("models/%s.4ds" % v, ["patch.dta", "MODELS.DTA"])
        if d is None:
            continue
        hands = fmt_4ds_hd2skin.read_model(d)
        skinned_gltf.export_character(b"", {}, tex, "../../textures/",
                                      os.path.join(out_dir, "fpv", "hands_%s.glb" % v.lower()), name="fpv", model=hands)
        done.append(v.lower())
    return mapping, done


# --- Overlays (gameinterface.4ds) ------------------------------------------------------------------

def export_overlays(out_dir):
    import fmt_4ds_ui as U
    from PIL import Image
    data = cm.read_file("models/gameinterface.4ds", ["Models.dta"])
    m = U.read_model(data)
    F, mats = m["frames"], m["materials"]
    W = U.world_matrices(F, conjugate=True)
    byname = {f["name"]: i for i, f in enumerate(F)}
    tex = {}
    W_, H_ = 1024, 768
    os.makedirs(os.path.join(out_dir, "overlays"), exist_ok=True)
    out = {}
    for typ, names in SCOPE_FRAMES.items():
        canvas = Image.new("RGBA", (W_, H_), (0, 0, 0, 0))
        # hintere Ebenen zuerst (größeres z liegt hinten)
        idx = sorted([byname[n] for n in names if n in byname],
                     key=lambda i: -sum(U.xform(W[i], v[:3])[2] for v in F[i]["lods"][0]["vertices"]) / len(F[i]["lods"][0]["vertices"]))
        for i in idx:
            lod = F[i]["lods"][0]
            pts = [(p[0] * W_, -p[1] / 0.75 * H_) for p in (U.xform(W[i], v[:3]) for v in lod["vertices"])]
            for g in lod["groups"]:
                mt = mats[g["material"] - 1] if g["material"] else None
                tn = ((mt or {}).get("diffuse_map") or "").upper()
                if tn and tn not in tex:
                    raw = cm.read_tex(tn)
                    tex[tn] = Image.open(__import__("io").BytesIO(raw)).convert("RGBA") if raw else None
                img = tex.get(tn)
                fc = g["faces"]
                for t in range(0, len(fc), 3):
                    tri = fc[t:t + 3]
                    _draw_tri_rgba(canvas, [pts[k] for k in tri], [lod["vertices"][k][6:8] for k in tri], img)
        fn = "overlays/scope_%d.png" % typ
        canvas.save(os.path.join(out_dir, fn))
        out[str(typ)] = fn
    return out


def _draw_tri_rgba(canvas, P, UV, img):
    """Dreieck texturiert mit Alpha-Überblendung („over“) in ein transparentes RGBA-Bild."""
    xs = [p[0] for p in P]; ys = [p[1] for p in P]
    x0, x1 = int(max(0, min(xs))), int(min(canvas.size[0] - 1, max(xs) + 1))
    y0, y1 = int(max(0, min(ys))), int(min(canvas.size[1] - 1, max(ys) + 1))
    if x1 < x0 or y1 < y0 or img is None:
        return
    (ax, ay), (bx, by), (cx, cy) = P
    den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
    if abs(den) < 1e-9:
        return
    src = img.load()
    tw, th = img.size
    dst = canvas.load()
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            px, py = x + 0.5, y + 0.5
            l1 = ((by - cy) * (px - cx) + (cx - bx) * (py - cy)) / den
            l2 = ((cy - ay) * (px - cx) + (ax - cx) * (py - cy)) / den
            l3 = 1 - l1 - l2
            if l1 < -1e-4 or l2 < -1e-4 or l3 < -1e-4:
                continue
            u = l1 * UV[0][0] + l2 * UV[1][0] + l3 * UV[2][0]
            v = l1 * UV[0][1] + l2 * UV[1][1] + l3 * UV[2][1]
            c = src[int(u * tw) % tw, int(v * th) % th]
            a = c[3] / 255.0
            if a <= 0:
                continue
            d = dst[x, y]
            da = d[3] / 255.0
            oa = a + da * (1 - a)
            if oa <= 0:
                continue
            col = tuple(int((c[k] * a + d[k] * da * (1 - a)) / oa) for k in range(3))
            dst[x, y] = col + (int(oa * 255),)


def main():
    items = json.load(open(os.path.join(cm.CACHE, "items.json"), encoding="utf-8"))["items"]
    out_dir = os.path.join(cm.CACHE, "weapons")
    os.makedirs(out_dir, exist_ok=True)
    tex = cm.Textures(os.path.join(cm.CACHE, "textures"))
    hold = {}
    for k, s in HOLD_SETS.items():
        e = {}
        for m, v in s.items():
            e[m] = [[clip_name(a) for a in var] for var in v] if m == "reload" else [clip_name(a) for a in v]
        hold[k] = e
    table = {"items": {}, "hold_sets": hold, "attach": {"frame": "hw1", "grip": "RW", "setdir": [1, 0, 0]},
             "clips": {}}
    # Clip-Längen (s) und Auslösezeitpunkte der Würfe (Hand-Dummy hw1 der Figur ge01a, größte Geschwindigkeit)
    ref = fmt_4ds_hd2skin.read_model(cm.read_file("models/ge01a.4ds", ["patch.dta", "MODELS.DTA"]))
    for cn, a5 in hold_anims().items():
        d = _read5(a5)
        if d is None:
            continue
        c = {"length": round(fmt_5ds.parse(d)["last_frame"] / FPS, 3)}
        if a5.startswith("!hod"):
            c["release"] = release_time(ref, d, "j")
        table["clips"][cn] = c
    done, failed = {}, []
    for it in items:
        if it.get("kind") != "weapon":
            continue
        model = (it.get("model") or "").strip()
        st = item_set(it)
        entry = {"name": it.get("name"), "set": st, "fpv_model": it.get("fpv_model") or "",
                 "reload_variant": reload_variant(it, st)}
        z = item_zoom(it)
        if z:
            entry["zoom"] = z
        if model:
            key = model.lower()
            if key not in done:
                data = cm.read_file("models/%s.4ds" % model, ["MODELS.DTA"])
                if data is None:
                    failed.append((it["id"], model, "fehlt"))
                    key = ""
                else:
                    try:
                        m = fmt_4ds.read_model(data, quiet=True)
                        cm.model_to_gltf(m, tex, "../textures/", os.path.join(out_dir, key + ".glb"))
                        done[key] = sorted(f["name"] for f in m["frames"] if f["type"] == fmt_4ds.FRAME_DUMMY)
                    except Exception as e:   # einzelne Modelle dürfen scheitern, werden gemeldet
                        failed.append((it["id"], model, repr(e)[:100]))
                        key = ""
            if key:
                entry["model"] = key
                entry["dummies"] = done[key]
        table["items"][str(it["id"])] = entry
    # Hilfsmittel in der Hand (Verbandskasten l_medkit, Fernglas w_binocul) als Weltmodelle
    for it in items:
        if it["id"] in (53, 54, 99) and it.get("model"):
            key = it["model"].lower()
            data = cm.read_file("models/%s.4ds" % it["model"], ["patch.dta", "MODELS.DTA"])
            if data is not None and key not in done:
                m = fmt_4ds.read_model(data, quiet=True)
                cm.model_to_gltf(m, tex, "../textures/", os.path.join(out_dir, key + ".glb"))
                done[key] = []
            z = item_zoom(it)
            table["items"][str(it["id"])] = {"name": it.get("name"), "set": "hand", "model": key, **({"zoom": z} if z else {})}
    fpv, ffail = export_fpv([it for it in items if it.get("kind") == "weapon"], tex, out_dir)
    table["fpv"] = fpv
    for it in table["items"]:
        e = table["items"][it]
        k = (e.get("fpv_model") or "").lower()
        if k in fpv:
            e["fpv"] = k
    table["overlays"] = export_overlays(out_dir)
    table["fpv_hands"], _ = export_fpv_hands(items, tex, out_dir)
    json.dump(table, open(os.path.join(out_dir, "weapons.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("Modelle:", len(done), sorted(done))
    print("FPV:", len(fpv), sorted(fpv))
    print("Fehler:", failed + ffail)
    if tex.missing:
        print("fehlende Texturen:", sorted(tex.missing))


def main_hands():
    """Nur die Ego-Hände je Uniform nachziehen (weapons.json bleibt sonst unverändert): --hands"""
    items = json.load(open(os.path.join(cm.CACHE, "items.json"), encoding="utf-8"))["items"]
    out_dir = os.path.join(cm.CACHE, "weapons")
    path = os.path.join(out_dir, "weapons.json")
    table = json.load(open(path, encoding="utf-8"))
    tex = cm.Textures(os.path.join(cm.CACHE, "textures"))
    table["fpv_hands"], done = export_fpv_hands(items, tex, out_dir)
    json.dump(table, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("Hände:", done, "Uniformen:", len(table["fpv_hands"]))
    if tex.missing:
        print("fehlende Texturen:", sorted(tex.missing))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    if "--hands" in sys.argv:
        main_hands()
    else:
        main()
