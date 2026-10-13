"""Konvertiert eine Original-Mission von Hidden & Dangerous 2 in den lokalen Cache
von Dangerous Hidden 2 (glTF-Modelle, PNG-Texturen, Szenenbeschreibung JSON).

Quelle: die Installation des Nutzers (HD2_orig, nur gelesen).
Ziel:   DangerousHidden2/orig_cache/<mission>/ (nicht im Export, nicht weitergeben)

Aufruf: python -I tools/convert_mission.py ARCTIC1

Koordinaten: LS3D ist linkshändig (x rechts, y oben, z vorn). glTF/Godot sind
rechtshändig -> z wird gespiegelt, Quaternion (x,y,z,w) -> (-x,-y,z,w),
Dreiecks-Umlaufsinn wird umgedreht.
"""
import io
import json
import os
import re
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dta_extract  # noqa: E402
import fmt_4ds  # noqa: E402
import fmt_scene2  # noqa: E402

from PIL import Image  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ORIG = os.path.join(ROOT, "HD2_orig")
CACHE = os.path.join(ROOT, "DangerousHidden2", "orig_cache")
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

_archives = {}


def archive(name):
    if name not in _archives:
        _archives[name] = dta_extract.Archive(os.path.join(ORIG, name))
        _archives[name].index = {e[0].lower(): e for e in _archives[name].entries}
    return _archives[name]


def read_file(path, archives):
    """Datei aus dem ersten Archiv lesen, das sie enthält (Patch zuerst)."""
    key = path.lower().replace("/", "\\")
    for a in ["patch.dta"] + archives:
        arc = archive(a)
        if key in arc.index:
            try:
                return arc.read(arc.index[key])
            except ValueError as ex:
                PATCH_ERRORS.append("%s in %s: %s" % (path, a, ex))
    return None


PATCH_ERRORS = []


# --- Koordinaten -------------------------------------------------------------

def cpos(p):
    return [p[0], p[1], -p[2]]


def crot_xyzw(q):
    """4DS-Quaternion (x,y,z,w) -> glTF (x,y,z,w) mit gespiegelter z-Achse.
    Auch hier wirkt im Original die inverse (konjugierte) Rotation (belegt über gespeicherte
    Bind-Matrizen der Skin-Modelle; docs/re_notes_5ds_skin.md) -> (x, y, -z, w)."""
    return [q[0], q[1], -q[2], q[3]]


def crot_wxyz(q):
    """scene2-Quaternion (w,x,y,z) -> glTF (x,y,z,w) mit gespiegelter z-Achse.
    Das Original wendet den gespeicherten Wert konjugiert an (belegt über gespeicherte
    Kind-Weltpositionen, Chunk 0x2C, und Kamerablickrichtungen; docs/re_notes_lights_tracks_sounds.md):
    konj. (w,-x,-y,-z), dann z-Spiegelung -> (x, y, -z, w)."""
    return [q[1], q[2], -q[3], q[0]]


# --- Texturen ----------------------------------------------------------------

def read_tex(name):
    """Textur aus Maps.dta (MAPS\\) oder Maps_C.dta (MAPS_C\\)."""
    d = read_file("maps/" + name, ["Maps.dta"])
    if d is None:
        d = read_file("maps_c/" + name, ["Maps_C.dta"])
    return d

class Textures:
    def __init__(self, out_dir):
        self.out = out_dir
        os.makedirs(out_dir, exist_ok=True)
        self.done = {}
        self.missing = set()

    def get(self, diffuse, alpha=None, colorkey=False):
        # Manche Materialnamen enthalten Reste nach einem Nullbyte (C-String)
        diffuse = re.split(r"[\x00-\x1f]", diffuse or "")[0].strip()
        alpha = re.split(r"[\x00-\x1f]", alpha or "")[0].strip() or None
        if not diffuse:
            return None
        key = (diffuse.upper(), (alpha or "").upper(), colorkey)
        if key in self.done:
            return self.done[key]
        data = read_tex(diffuse)
        if data is None:
            self.missing.add(diffuse)
            self.done[key] = None
            return None
        img = Image.open(io.BytesIO(data))
        has_alpha = False
        if alpha:
            ad = read_tex(alpha)
            if ad is not None:
                a = Image.open(io.BytesIO(ad)).convert("L").resize(img.size)
                img = img.convert("RGBA")
                img.putalpha(a)
                has_alpha = True
        elif colorkey and img.mode == "P":
            # Farbschlüssel: Palettenindex 0 ist transparent (LS3D-Konvention)
            rgba = img.convert("RGBA")
            px = img.load()
            out = rgba.load()
            w, h = img.size
            for y in range(h):
                for x in range(w):
                    if px[x, y] == 0:
                        out[x, y] = (0, 0, 0, 0)
            img = rgba
            has_alpha = True
        else:
            img = img.convert("RGB")
        name = os.path.splitext(diffuse)[0].lower()
        if alpha:
            name += "__" + os.path.splitext(alpha)[0].lower()
        if colorkey:
            name += "__ck"
        fn = name + ".png"
        # nur bei geändertem Inhalt schreiben (Zeitstempel steuert das HD-Upscaling)
        buf = io.BytesIO()
        img.save(buf, "PNG")
        dst = os.path.join(self.out, fn)
        if not os.path.exists(dst) or open(dst, "rb").read() != buf.getvalue():
            open(dst, "wb").write(buf.getvalue())
        self.done[key] = (fn, has_alpha)
        return self.done[key]


# --- glTF-Schreiber ------------------------------------------------------------

class Gltf:
    def __init__(self, tex_rel):
        self.j = {"asset": {"version": "2.0", "generator": "DH2 convert_mission"},
                  "scenes": [{"nodes": []}], "scene": 0, "nodes": [], "meshes": [],
                  "materials": [], "textures": [], "images": [], "samplers": [{"wrapS": 10497, "wrapT": 10497}],
                  "accessors": [], "bufferViews": [], "buffers": []}
        self.bin = bytearray()
        self.tex_rel = tex_rel
        self.img_index = {}

    def _view(self, data, target=None):
        while len(self.bin) % 4:
            self.bin.append(0)
        off = len(self.bin)
        self.bin += data
        v = {"buffer": 0, "byteOffset": off, "byteLength": len(data)}
        if target:
            v["target"] = target
        self.j["bufferViews"].append(v)
        return len(self.j["bufferViews"]) - 1

    def _acc(self, view, ctype, count, typ, mn=None, mx=None):
        a = {"bufferView": view, "componentType": ctype, "count": count, "type": typ}
        if mn is not None:
            a["min"] = mn
            a["max"] = mx
        self.j["accessors"].append(a)
        return len(self.j["accessors"]) - 1

    def material(self, m, tex):
        mat = {"name": (m.get("diffuse_map") or "mat"), "pbrMetallicRoughness": {"metallicFactor": 0.0, "roughnessFactor": 0.9}}
        f = m["flags"]
        if tex:
            fn, has_alpha = tex
            if fn not in self.img_index:
                self.j["images"].append({"uri": self.tex_rel + fn})
                self.j["textures"].append({"source": len(self.j["images"]) - 1, "sampler": 0})
                self.img_index[fn] = len(self.j["textures"]) - 1
            mat["pbrMetallicRoughness"]["baseColorTexture"] = {"index": self.img_index[fn]}
            if has_alpha:
                mat["alphaMode"] = "MASK"
                mat["alphaCutoff"] = 0.5
        else:
            c = m["diffuse"]
            mat["pbrMetallicRoughness"]["baseColorFactor"] = [min(c[0] * 2.5, 1), min(c[1] * 2.5, 1), min(c[2] * 2.5, 1), 1.0]
        if m.get("opacity", 1.0) < 0.99 or f & fmt_4ds.MTL_ADDITIVE:
            mat["alphaMode"] = "BLEND"
            pbr = mat["pbrMetallicRoughness"]
            col = pbr.get("baseColorFactor", [1, 1, 1, 1])
            col[3] = max(min(m.get("opacity", 1.0), 1.0), 0.05)
            pbr["baseColorFactor"] = col
        if f & fmt_4ds.MTL_DOUBLESIDED or f & fmt_4ds.MTL_COLORKEY or m.get("alpha_map"):
            mat["doubleSided"] = True
        self.j["materials"].append(mat)
        return len(self.j["materials"]) - 1

    def mesh(self, name, lod, mat_ids):
        verts = lod["vertices"]
        n = len(verts)
        pos = bytearray()
        nrm = bytearray()
        uv = bytearray()
        mn = [1e30] * 3
        mx = [-1e30] * 3
        for v in verts:
            p = (v[0], v[1], -v[2])
            pos += struct.pack("<3f", *p)
            nrm += struct.pack("<3f", v[3], v[4], -v[5])
            uv += struct.pack("<2f", v[6], v[7])
            for k in range(3):
                mn[k] = min(mn[k], p[k])
                mx[k] = max(mx[k], p[k])
        if n == 0:
            return None
        pa = self._acc(self._view(bytes(pos), 34962), 5126, n, "VEC3", mn, mx)
        na = self._acc(self._view(bytes(nrm), 34962), 5126, n, "VEC3")
        ua = self._acc(self._view(bytes(uv), 34962), 5126, n, "VEC2")
        prims = []
        for g in lod["groups"]:
            fc = g["faces"]
            if not fc:
                continue
            idx = bytearray()
            for i in range(0, len(fc), 3):
                idx += struct.pack("<3H", fc[i], fc[i + 2], fc[i + 1])   # Umlaufsinn umdrehen
            ia = self._acc(self._view(bytes(idx), 34963), 5123, len(fc), "SCALAR")
            mid = g["material"] - 1           # 1-basiert, 0 = kein Material
            prim = {"attributes": {"POSITION": pa, "NORMAL": na, "TEXCOORD_0": ua}, "indices": ia}
            if 0 <= mid < len(mat_ids):
                prim["material"] = mat_ids[mid]
            prims.append(prim)
        if not prims:
            return None
        self.j["meshes"].append({"name": name, "primitives": prims})
        return len(self.j["meshes"]) - 1

    def node(self, d):
        self.j["nodes"].append(d)
        return len(self.j["nodes"]) - 1

    def save(self, path):
        if not self.j["images"]:
            for k in ("images", "textures", "samplers"):
                self.j.pop(k)
        for k in ("materials", "meshes", "accessors", "bufferViews"):
            if not self.j[k]:
                self.j.pop(k)
        if self.bin:
            self.j["buffers"] = [{"byteLength": len(self.bin)}]
        else:
            self.j.pop("buffers")
        js = json.dumps(self.j, separators=(",", ":")).encode()
        while len(js) % 4:
            js += b" "
        b = bytes(self.bin)
        while len(b) % 4:
            b += b"\0"
        total = 12 + 8 + len(js) + (8 + len(b) if b else 0)
        out = struct.pack("<III", 0x46546C67, 2, total)
        out += struct.pack("<II", len(js), 0x4E4F534A) + js
        if b:
            out += struct.pack("<II", len(b), 0x004E4942) + b
        with open(path, "wb") as f:
            f.write(out)


SKIP_FRAMES = (fmt_4ds.FRAME_SECTOR, fmt_4ds.FRAME_OCCLUDER)


def model_to_gltf(model, textures, tex_rel, out_path, collision_hint=False):
    """4DS-Modell -> GLB mit Knotenhierarchie. Sektoren/Occluder entfallen."""
    g = Gltf(tex_rel)
    mat_ids = []
    for m in model["materials"]:
        tex = textures.get(m.get("diffuse_map"), m.get("alpha_map") if m["flags"] & fmt_4ds.MTL_ALPHATEX else None,
                           bool(m["flags"] & fmt_4ds.MTL_COLORKEY))
        mat_ids.append(g.material(m, tex))
    frames = model["frames"]
    node_of = {}
    mesh_of_frame = {}
    for fr in frames:
        node = {"name": fr["name"] or ("frame%d" % fr["index"]),
                "translation": cpos(fr["pos"]), "rotation": crot_xyzw(fr["rot"]), "scale": list(fr["scale"])}
        extras = {"type": fr["type"]}
        if "visual" in fr:
            extras["visual"] = fr["visual"]     # Visual-Typ (fmt_4ds.VIS_*), z. B. 6 Glow, 8 Spiegel
        if fr.get("params"):
            extras["params"] = fr["params"]
        if fr["type"] in SKIP_FRAMES:
            extras["skipped"] = True
        node["extras"] = extras
        if fr["type"] == fmt_4ds.FRAME_VISUAL and fr.get("lods"):
            mi = g.mesh(node["name"], fr["lods"][0], mat_ids)
            if mi is not None:
                node["mesh"] = mi
                mesh_of_frame[fr["index"] + 1] = mi
        node_of[fr["index"] + 1] = g.node(node)
    # Instanzen (gleiche Geometrie wie ein anderer Frame)
    for fr in frames:
        inst = fr.get("instance", 0)
        if inst and inst in mesh_of_frame:
            g.j["nodes"][node_of[fr["index"] + 1]]["mesh"] = mesh_of_frame[inst]
    # Hierarchie
    for fr in frames:
        ni = node_of[fr["index"] + 1]
        par = fr["parent"]
        if par and par in node_of and par != fr["index"] + 1:
            g.j["nodes"][node_of[par]].setdefault("children", []).append(ni)
        else:
            g.j["scenes"][0]["nodes"].append(ni)
    g.save(out_path)
    return len(g.j.get("meshes", []))


EXTRA_MODELS = {"AFRICA6": ["la_Bf109Canyon"]}


def convert(mission):
    mdir = mission.upper()
    out = os.path.join(CACHE, mdir.lower())
    os.makedirs(os.path.join(out, "models"), exist_ok=True)
    textures = Textures(os.path.join(CACHE, "textures"))

    def mission_file(name):
        return read_file("missions/%s/%s" % (mdir, name), ["Missions.dta"])

    # 1. Statische Szene (scene.4ds)
    scene = fmt_4ds.read_model(mission_file("scene.4ds"), quiet=True)
    n = model_to_gltf(scene, textures, "../textures/", os.path.join(out, "scene.glb"))
    print("scene.glb: %d Frames, %d Meshes" % (len(scene["frames"]), n))

    # 2. Objekte (scene2.bin)
    _, objs = fmt_scene2.parse(mission_file("scene2.bin"))
    models = sorted({o["model"] for o in objs if o.get("model")})
    n_scene_models = len(models)
    ok = 0
    failed = []
    for name in models:
        dst = os.path.join(out, "models", name.lower() + ".glb")
        data = read_file("models/%s.4ds" % name, ["Models.dta"])
        if data is None:
            failed.append(name + " (fehlt)")
            continue
        mdl = fmt_4ds.read_model(data, quiet=True)
        if mdl.get("stop"):
            failed.append("%s (%s)" % (name, mdl["stop"][:40]))
        model_to_gltf(mdl, textures, "../../textures/", dst)
        ok += 1
    print("Modelle: %d konvertiert, %d Probleme" % (ok, len(failed)))
    for f in failed[:20]:
        print("   ", f)

    # 3. Akteure (actors.bin): Positionen, Modelle, Definitionen
    adata = mission_file("actors.bin")
    actors = []
    if adata:
        _, aobjs = fmt_scene2.parse(adata)
        defs = fmt_scene2.parse_actor_defs(adata)
        for o in aobjs:
            a = {"name": o.get("name", ""), "pos": cpos(o.get("pos", (0, 0, 0))),
                 "rot": crot_wxyz(o.get("rot", (1, 0, 0, 0))), "scale": list(o.get("scale", (1, 1, 1))),
                 "parent": o.get("parent", "")}
            if o.get("model"):
                a["model"] = o["model"].lower()
            if a["name"] in defs:
                typ, params = defs[a["name"]]
                a["actor_type"] = typ
                a["params"] = list(params)
            actors.append(a)
            if o.get("model") and o["model"].lower() not in [m.lower() for m in models]:
                models.append(o["model"])
        done_now = {m.lower() for m in models[:n_scene_models]}
        for name in sorted({a.get("model") for a in actors if a.get("model")}):
            dst = os.path.join(out, "models", name + ".glb")
            # nur in diesem Lauf bereits geschriebene überspringen – vorhandene Dateien aus
            # älteren Läufen (z. B. alte Quaternion-Konvention) werden neu erzeugt
            if name.lower() in done_now:
                continue
            done_now.add(name.lower())
            data = read_file("models/%s.4ds" % name, ["Models.dta"])
            if data is None:
                failed.append(name + " (fehlt)")
                continue
            mdl = fmt_4ds.read_model(data, quiet=True)
            if mdl.get("stop"):
                failed.append("%s (%s)" % (name, mdl["stop"][:40]))
            model_to_gltf(mdl, textures, "../../textures/", dst)
        print("Akteure: %d (%d mit Definition)" % (len(actors), sum(1 for a in actors if "actor_type" in a)))

    # 3a. Modelle, die nur im Programmcode erzeugt werden (nicht in scene2/actors), z. B. AFRICA6 Bf 109
    #     als Unterobjekt der Ju 88 (docs/re_notes_ju88.md)
    extra = list(EXTRA_MODELS.get(mdir, []))
    # Weltmodelle frei liegender Gegenstände (items.dat ohne Besitzer, Modell aus items.sav), z. B. „item_slozka3“
    try:
        import fmt_actors_items as fai
        idat, _ = fai.read_orig("MISSIONS\\%s\\items.dat" % mdir, "Missions.dta")
        isav, _ = fai.read_orig("TABLES\\items.sav", "others.DTA")
        if idat and isav:
            by_id = {it["id"]: it for it in fai.parse_items(isav)}
            for r in fai.parse_items_dat(idat):
                m = by_id.get(r["item"], {}).get("model", "")
                if not r["owner"] and "pos" in r and m and m not in extra:
                    extra.append(m)
    except Exception as ex:   # Gegenstandsmodelle sind optional (Platzhalter im Spiel)
        print("Gegenstandsmodelle:", ex)
    for name in extra:
        data = read_file("models/%s.4ds" % name, ["Models.dta"])
        if data is None:
            failed.append(name + " (fehlt)")
            continue
        model_to_gltf(fmt_4ds.read_model(data, quiet=True), textures, "../../textures/",
                      os.path.join(out, "models", name.lower() + ".glb"))
        print("Zusatzmodell:", name)

    # 3b. KI-Wegpunkte (check2.bin): benannte Punkte für HUMAN_Move("GG_3") usw.
    waypoints = {}
    cdata = mission_file("check2.bin")
    if cdata:
        npts, nlinks, nnames = struct.unpack_from("<III", cdata, 8)
        p = 0x1C
        pts = []
        for _ in range(npts):
            x, y, z = struct.unpack_from("<3f", cdata, p)
            nl = cdata[p + 20] & 0x1F      # obere Bits sind Flags (z. B. 0x40)
            pts.append((x, y, z))
            p += 12 + 4 + 4 + 1 + 11 + nl * 4
        for _ in range(nnames):
            idx = struct.unpack_from("<H", cdata, p)[0]
            name = cdata[p + 2:p + 18].split(b"\0")[0].decode("latin-1")
            p += 18
            if idx < len(pts):
                waypoints[name] = cpos(pts[idx])
        print("Wegpunkte: %d Punkte, %d benannt" % (len(pts), len(waypoints)))

    # 4. Skripte: Zuordnung Objekt -> Skriptdatei (missions\<m>\scripts.dta) + Skripttexte
    sdata = mission_file("scripts.dta")
    script_map = {}
    if sdata:
        p = 6   # Kopf-Chunk (Typ 0, Gesamtlänge)
        pair = []
        while p + 6 <= len(sdata):
            t, ln = struct.unpack_from("<HI", sdata, p)
            if ln < 6:
                break
            pair.append(sdata[p + 6:p + ln].split(b"\0")[0].decode("latin-1"))
            p += ln
            if len(pair) == 2:
                script_map[pair[0]] = pair[1]
                pair = []
    sdir = os.path.join(out, "scripts")
    os.makedirs(sdir, exist_ok=True)
    nscr = 0
    # alle Skripte des Missionsordners (auch per ScriptAssign zur Laufzeit zugewiesene),
    # Patch-Fassung hat Vorrang
    prefix = "scripts\\%s\\" % mdir.lower()
    names = set()
    for a in ["Scripts.dta", "patch.dta"]:
        for key in archive(a).index:
            if key.startswith(prefix) and key.endswith(".scr") and "\\" not in key[len(prefix):]:
                names.add(key[len(prefix):])   # Unterordner (CVS-Sicherungen) auslassen
    for scr in sorted(names):
        txt = read_file("scripts/%s/%s" % (mdir, scr), ["Scripts.dta"])
        if txt is None:
            print("  Skript fehlt:", scr)
            continue
        with open(os.path.join(sdir, scr.lower()), "wb") as f:
            f.write(txt)
        nscr += 1
    print("Skripte: %d Zuordnungen, %d Dateien" % (len(script_map), nscr))

    # 5. Sprachaufnahmen: in den Skripten referenzierte Text-IDs (8-stellig) -> SOUNDS\<id>.wav
    import re
    ids = set()
    for fn in os.listdir(sdir):
        txt = open(os.path.join(sdir, fn), "rb").read().decode("latin-1")
        txt = re.sub(r"//[^\n]*", "", txt)
        ids.update(re.findall(r"\b(\d{8})\b", txt))
    snd_dir = os.path.join(CACHE, "sounds")
    os.makedirs(snd_dir, exist_ok=True)
    nsnd = 0
    for i in sorted(ids):
        dst = os.path.join(snd_dir, i + ".wav")
        if os.path.exists(dst):
            nsnd += 1
            continue
        data = read_file("sounds/%s.wav" % i, ["Sounds.dta"])
        if data:
            open(dst, "wb").write(data)
            nsnd += 1
    print("Sprachaufnahmen: %d von %d referenzierten IDs" % (nsnd, len(ids)))

    entries = []
    for o in objs:
        e = {"name": o.get("name", ""), "type": o.get("type", -1), "parent": o.get("parent", "")}
        if "pos" in o:
            e["pos"] = cpos(o["pos"])
        if "rot" in o:
            e["rot"] = crot_wxyz(o["rot"])
        if "scale" in o:
            e["scale"] = list(o["scale"])
        if o.get("model"):
            e["model"] = o["model"].lower()
        if e["type"] == -1:
            continue   # Ergänzungen zu scene.4ds-Frames (Lightmaps etc.) – vorerst ungenutzt
        entries.append(e)
    with open(os.path.join(out, "scene.json"), "w", encoding="utf-8") as f:
        json.dump({"mission": mdir, "objects": entries, "actors": actors, "scripts": script_map,
                   "waypoints": waypoints}, f, indent=1)
    convert_texts()
    # Godot soll den Cache nicht importieren (wird zur Laufzeit per GLTFDocument geladen)
    open(os.path.join(CACHE, ".gdignore"), "w").close()
    print("scene.json: %d Objekte; Texturen: %d, fehlend: %s" % (len(entries), len(textures.done), sorted(textures.missing)[:10]))
    for e in PATCH_ERRORS:
        print("  WARNUNG", e)


def convert_texts(lang="german"):
    """Original-Texte (Dialoge/Untertitel + Spieltexte) -> orig_cache/texts_<lang>.json {id: text}."""
    texts = {}
    base = os.path.join(ORIG, "Text", lang)
    dlg = None
    for fn in os.listdir(base):
        if fn.lower() == "dialogs.bin":
            dlg = open(os.path.join(base, fn), "rb").read()
    if dlg:
        def walk(a, b):
            p = a
            cur = None
            while p + 6 <= b:
                t, ln = struct.unpack_from("<HI", dlg, p)
                if ln < 6:
                    return
                if t == 0x09C7:
                    cur = struct.unpack_from("<I", dlg, p + 6)[0]
                elif t == 0x09C8 and cur is not None:
                    texts[str(cur)] = dlg[p + 6:p + ln].split(b"\0")[0].decode("cp1252", "replace")
                elif t in (0x09C4, 0x09C6):
                    walk(p + 6, p + ln)
                p += ln
        walk(0, len(dlg))
    for fn in os.listdir(base):
        if fn.lower().startswith("texty") and fn.lower().endswith(".txt"):
            for line in open(os.path.join(base, fn), encoding="cp1252", errors="replace"):
                line = line.strip()
                if not line or line.startswith(";"):
                    continue
                parts = line.split(None, 1)
                if len(parts) == 2 and parts[0].isdigit() and parts[1].startswith('"'):
                    texts.setdefault(str(int(parts[0])), parts[1].split('"')[1])
    with open(os.path.join(CACHE, "texts_%s.json" % lang), "w", encoding="utf-8") as f:
        json.dump(texts, f, ensure_ascii=False, indent=0)
    print("Texte (%s): %d" % (lang, len(texts)))


if __name__ == "__main__":
    convert(sys.argv[1])
