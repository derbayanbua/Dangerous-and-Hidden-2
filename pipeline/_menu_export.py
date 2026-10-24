"""Exportiert die Original-Hauptmenue-Assets von HD2 nach orig_cache/ui/menu/ (lokal, gitignored).
  textures/*.png      alle von den Menue-4DS benutzten Texturen + Cursor/Logos
  backgrounds/*.png   1024x768-Hintergrund je Menue (menu1-Kachelgitter 4x3 a 256 px)
  previews/*.png      Referenz-Rendering (Hintergrund + Normalzustand, Textfelder gelb umrandet)
  layout/*.json       alle Frames je Menue mit Bildschirmrechteck (px @1024x768 und normiert)
  audio/              Menue-Musik + Klickklang
Aufruf: pyenv\\Scripts\\python.exe -I _menu_export.py
"""
import io, json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
import _menu_layout as L
import convert_mission as cm
from PIL import Image, ImageDraw

OUT = os.path.join(cm.CACHE, "ui", "menu")
MENUS = ["main_menu", "change_profile", "singleplayer", "single mission 2", "options", "multiplayer menu",
         "create server", "server filters", "gameinfo", "password", "confirm", "description", "kurzor_menu",
         # Bildschirme vor dem Einsatz (Teamauswahl, Inventar, aktiver Soldat) und MP-Spieler-Setup
         "team members selection", "items selection", "selection screen", "player screen",
         # Nachbesprechung/Tagebuch, Pausemenue im Einsatz, Spiel-Info
         "debriefing", "diary", "main ingame", "ingame_info"]
EXTRA_TEX = ["HD_logo.bmp", "HD_logo_b.bmp", "x_b_logo.bmp", "x_nmn04_logo.bmp", "x_esrb.bmp", "x_kursor.tga",
             "x_nmnbtn.bmp", "x_nmnbtw.bmp", "x_nmzsel.tga", "x_nmzsed.tga", "x_nmshd.tga",
             "x_square.bmp", "x_bubble.bmp", "mm_red.bmp", "x_medals.tga", "x_blcka.tga", "x_ranks.tga"]
AUDIO = ["main menu.ogg", "main menu 2.ogg", "credits.ogg", "success menu.ogg", "fail menu.ogg", "button.wav"]


def save_png(img, path):
    buf = io.BytesIO(); img.save(buf, "PNG")
    if not os.path.exists(path) or open(path, "rb").read() != buf.getvalue():
        open(path, "wb").write(buf.getvalue())


def export_tex(name, tdir, done, missing):
    key = name.upper()
    if key in done:
        return done[key]
    d = cm.read_tex(name)
    if d is None:
        missing.add(name); done[key] = None; return None
    img = Image.open(io.BytesIO(d))
    mode = img.mode
    img = img.convert("RGBA") if mode in ("RGBA", "LA") or name.lower().endswith(".tga") else img.convert("RGB")
    fn = os.path.splitext(name)[0].lower() + ".png"
    save_png(img, os.path.join(tdir, fn))
    done[key] = {"file": "textures/" + fn, "size": list(img.size), "src_mode": mode}
    return done[key]


def bg_grid(elems):
    """menu1 / Hintergrund-Frame: Kacheln mit Position (Spalte/Zeile) und Spiegelung."""
    for e in elems:
        if e.get("rect_px") == [0.0, -0.0, 1024.0, 768.0] or (e.get("rect_px") and e["rect_px"][2] - e["rect_px"][0] > 1000):
            tiles = []
            for tn, tri in e["_tris"]:
                pass
            # je Gruppe 2 Dreiecke -> Rechteck
            by_tex = {}
            for tn, tri in e["_tris"]:
                by_tex.setdefault(tn, []).extend(tri)
            for tn, vs in by_tex.items():
                px = [L.to_px(v) for v in vs]
                x0 = min(p[0] for p in px); y0 = min(p[1] for p in px)
                x1 = max(p[0] for p in px); y1 = max(p[1] for p in px)
                tl = min(vs, key=lambda v: (round(L.to_px(v)[1]), round(L.to_px(v)[0])))
                br = max(vs, key=lambda v: (round(L.to_px(v)[1]), round(L.to_px(v)[0])))
                tiles.append({"texture": tn, "rect_px": [round(x0), round(y0), round(x1), round(y1)],
                              "col": int(round(x0 / 256)), "row": int(round(y0 / 256)),
                              "flip_u": tl[3] > br[3], "flip_v": tl[4] > br[4]})
            tiles.sort(key=lambda t: (t["row"], t["col"]))
            return e["name"], tiles
    return None, []


def compose_bg(tiles):
    img = Image.new("RGB", (1024, 768))
    for t in tiles:
        im = L.tex(t["texture"])
        if im is None:
            continue
        im = im.convert("RGB")
        if t["flip_u"]:
            im = im.transpose(Image.FLIP_LEFT_RIGHT)
        if t["flip_v"]:
            im = im.transpose(Image.FLIP_TOP_BOTTOM)
        r = t["rect_px"]
        img.paste(im.resize((r[2] - r[0], r[3] - r[1])), (r[0], r[1]))
    return img


def main():
    for sub in ("textures", "backgrounds", "previews", "layout", "audio"):
        os.makedirs(os.path.join(OUT, sub), exist_ok=True)
    tdir = os.path.join(OUT, "textures")
    done, missing = {}, set()
    summary = {}
    for m in MENUS:
        el = L.layout(m + ".4ds")
        # Dreiecke je Frame (Bildschirm-px @1024x768 + UV) fuer die originalgetreue Darstellung inkl.
        # gedrehter/gespiegelter Atlas-Ausschnitte (Pfeile, Bildlaufleisten) im Spiel
        for e in el:
            if "_tris" in e:
                e["tris"] = [[tn or "", [[round(L.to_px(v)[0], 2), round(L.to_px(v)[1], 2), round(v[3], 5), round(v[4], 5)]
                                         for v in tri]] for tn, tri in e["_tris"]]
        frames = L.strip(el)
        texs = sorted({g["texture"] for e in frames for g in e.get("groups", []) if g["texture"]})
        for t in texs:
            export_tex(t, tdir, done, missing)
        bgname, tiles = bg_grid(el) if m != "kurzor_menu" else (None, [])
        # Wurzel-Gruppe je Frame (oberster Dummy-Vorfahr)
        byname = {e["frame"]: e for e in frames}
        names = {e["name"]: e for e in frames}
        for e in frames:
            p = e.get("parent"); root = None
            while p:
                root = p
                pe = names.get(p)
                p = pe.get("parent") if pe else None
            e["root"] = root
        lay = {"model": "MODELS\\%s.4ds" % m, "screen": "1024x768 reference; px = x*1024, py = -y*1024 (4DS units)",
               "background_frame": bgname, "background_tiles": tiles, "frames": frames}
        json.dump(lay, open(os.path.join(OUT, "layout", m + ".json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
        if tiles:
            save_png(compose_bg(tiles), os.path.join(OUT, "backgrounds", m + ".png"))
            for t in tiles:
                export_tex(t["texture"], tdir, done, missing)
        if m != "kurzor_menu":
            bgn = bgname
            L.render(el, os.path.join(OUT, "previews", m + ".png"),
                     skip=lambda e: e["name"].startswith(("actived", "inactived")) or e["name"] == bgn or not e.get("onscreen"))
            # Hintergrund ohne Naehte darunterlegen
            if tiles:
                pv = Image.open(os.path.join(OUT, "previews", m + ".png")).convert("RGB")
                bg = compose_bg(tiles)
                mask = Image.eval(pv.convert("L"), lambda v: 255 if v > 0 else 0)
                bg.paste(pv, (0, 0), mask)
                save_png(bg, os.path.join(OUT, "previews", m + ".png"))
        summary[m] = {"frames": len(frames), "textures": texs, "bg_tiles": [t["texture"] for t in tiles]}
    for t in EXTRA_TEX:
        export_tex(t, tdir, done, missing)
    # Gegenstandssymbole (items.sav-Feld "icon", 64x32 BMP aus Maps/Maps_C) fuer Inventar-/MP-Bildschirm
    idir = os.path.join(OUT, "items")
    os.makedirs(idir, exist_ok=True)
    icons = {}
    items_json = os.path.join(cm.CACHE, "items.json")
    if os.path.exists(items_json):
        for it in json.load(open(items_json, encoding="utf-8")).get("items", []):
            ic = (it.get("icon") or "").strip()
            if not ic or ic.lower() in icons:
                continue
            d = cm.read_tex(ic + ".bmp")
            if d is None:
                missing.add(ic + ".bmp"); continue
            img = Image.open(io.BytesIO(d)).convert("RGB")
            save_png(img, os.path.join(idir, ic.lower() + ".png"))
            icons[ic.lower()] = list(img.size)
    print("Gegenstandssymbole:", len(icons))
    adir = os.path.join(OUT, "audio")
    aud = {}
    for a in AUDIO:
        d = cm.read_file("sounds/" + a, ["Sounds.dta"])
        if d is None:
            missing.add(a); continue
        open(os.path.join(adir, a), "wb").write(d)
        aud[a] = len(d)
    json.dump({"textures": done, "missing": sorted(missing), "audio": aud, "menus": summary, "item_icons": icons},
              open(os.path.join(OUT, "export_index.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("Texturen:", sum(1 for v in done.values() if v), "fehlend:", sorted(missing))
    print("Audio:", aud)
    for m, s in summary.items():
        print(m, s["frames"], s["bg_tiles"][:3])


def export_credits():
    """Abspann-Rolltext (Text\\german\\Subtitles\\credits.txt, cp1250) -> orig_cache/ui/menu/credits.txt (UTF-8, LF).
    Nur lokal im Cache (urheberrechtlich geschuetzter Originaltext, nicht ins Repository); main_menu.gd liest ihn
    zur Laufzeit (Parser wie hd2.exe 0x689340)."""
    src = None
    for lang in ("german", "German"):
        for sub in ("Subtitles", "subtitles"):
            p = os.path.join(cm.ORIG, "Text", lang, sub, "credits.txt")
            if os.path.isfile(p):
                src = p
                break
        if src:
            break
    if src is None:
        print("credits.txt nicht gefunden")
        return
    txt = open(src, "rb").read().decode("cp1250").replace("\r\n", "\n").replace("\r", "\n")
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "credits.txt"), "w", encoding="utf-8", newline="\n") as f:
        f.write(txt)
    print("Mitwirkende:", src, len(txt.splitlines()), "Zeilen")


if __name__ == "__main__":
    if sys.argv[1:] == ["credits"]:
        export_credits()
    else:
        main()
        export_credits()
